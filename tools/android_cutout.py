#!/usr/bin/env python3
"""Edge to edge on a phone with a punch-hole camera: adds

    android:windowLayoutInDisplayCutoutMode="shortEdges"

to the exported APK's <activity>, which Godot 4.4 has no export option or project setting for.

Why it is needed: Godot's Android theme (GodotAppMainTheme, inside the prebuilt export template) sets
windowDrawsSystemBarBackgrounds and windowSwipeToDismiss and nothing else, and the engine's immersive mode only
calls setDecorFitsSystemWindows(false) + WindowInsetsController.hide(systemBars).  None of that touches the
window's layoutInDisplayCutoutMode, so it stays LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT, and DEFAULT means the
window is laid out NOT to overlap the cutout whenever the cutout is not inside a system bar -- which is every
landscape-locked game on a phone whose camera hole sits on what is now a short edge.  The system puts a black
band roughly the hole's depth (about 100 px on a 2340x1080 Galaxy S25) down one side.  shortEdges lets the
window cover it; VoxelTouch then keeps the buttons out of the hole with DisplayServer.get_display_safe_area().

What it does: unpacks the APK, rewrites the binary AndroidManifest.xml (one new attribute on the GodotApp
activity -- a new attribute-name string, a new resource-map entry, every string index after it shifted up),
repacks and re-signs with the same key, so the new APK still installs over the old one.

    tools/android_cutout.py <in.apk> <out.apk> --keystore K --alias A --pass P [--build-tools DIR]

Read back with:  aapt2 dump xmltree --file AndroidManifest.xml out.apk | grep -i cutout
"""

import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

RES_XML_TYPE = 0x0003
RES_STRING_POOL = 0x0001
RES_XML_RESOURCE_MAP = 0x0180
RES_XML_START_NS = 0x0100
RES_XML_END_NS = 0x0101
RES_XML_START_ELEM = 0x0102
RES_XML_END_ELEM = 0x0103
RES_XML_CDATA = 0x0104
NIL = 0xFFFFFFFF
TYPE_STRING = 0x03
TYPE_INT_DEC = 0x10

ANDROID_NS = "http://schemas.android.com/apk/res/android"
ATTR_NAME = "windowLayoutInDisplayCutoutMode"
ATTR_ID = 0x01010546            # android.R.attr.windowLayoutInDisplayCutoutMode
SHORT_EDGES = 1                 # LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
MTIME = 1104537600             # 2005-01-01, the zip stamp on the one entry this replaces


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


class Pool:
    """A ResStringPool, read into a plain list of strings (manifests carry no styles)."""

    def __init__(self, data):
        self.count = u32(data, 8)
        self.style_count = u32(data, 12)
        self.flags = u32(data, 16)
        strings_start = u32(data, 20)
        self.utf8 = bool(self.flags & 0x100)
        if self.style_count:
            raise ValueError("string pool has styles; not handled")
        self.strings = []
        for i in range(self.count):
            p = strings_start + u32(data, 28 + 4 * i)
            if self.utf8:
                n = data[p]
                p += 1
                if n & 0x80:
                    p += 1
                m = data[p]
                p += 1
                if m & 0x80:
                    m = ((m & 0x7F) << 8) | data[p]
                    p += 1
                self.strings.append(data[p:p + m].decode("utf-8"))
            else:
                n = u16(data, p)
                p += 2
                if n & 0x8000:
                    n = ((n & 0x7FFF) << 16) | u16(data, p)
                    p += 2
                self.strings.append(data[p:p + 2 * n].decode("utf-16-le"))

    def build(self):
        blob = bytearray()
        offs = []
        for s in self.strings:
            offs.append(len(blob))
            if self.utf8:
                b = s.encode("utf-8")
                if len(s) >= 0x80 or len(b) >= 0x80:
                    raise ValueError("long UTF-8 string; not handled")
                blob += bytes([len(s), len(b)]) + b + b"\x00"
            else:
                b = s.encode("utf-16-le")
                if len(s) >= 0x8000:
                    raise ValueError("long UTF-16 string; not handled")
                blob += struct.pack("<H", len(s)) + b + b"\x00\x00"
        while len(blob) % 4:
            blob += b"\x00"
        strings_start = 28 + 4 * len(self.strings)
        out = bytearray(struct.pack("<HHIIIIII", RES_STRING_POOL, 28, strings_start + len(blob),
                                    len(self.strings), 0, self.flags, strings_start, 0))
        for o in offs:
            out += struct.pack("<I", o)
        return bytes(out + blob)


def parse(data):
    if u16(data, 0) != RES_XML_TYPE:
        raise ValueError("not a binary XML file")
    total = u32(data, 4)
    pos = u16(data, 2)
    pool = resids = None
    nodes = []
    while pos < total:
        t, hs, sz = u16(data, pos), u16(data, pos + 2), u32(data, pos + 4)
        chunk = data[pos:pos + sz]
        if t == RES_STRING_POOL:
            pool = Pool(chunk)
        elif t == RES_XML_RESOURCE_MAP:
            resids = [u32(chunk, hs + 4 * i) for i in range((sz - hs) // 4)]
        else:
            nodes.append(bytearray(chunk))
        pos += sz
    if pool is None or resids is None:
        raise ValueError("manifest has no string pool or no resource map")
    return pool, resids, nodes


def serialize(pool, resids, nodes):
    body = pool.build()
    body += struct.pack("<HHI", RES_XML_RESOURCE_MAP, 8, 8 + 4 * len(resids))
    body += b"".join(struct.pack("<I", r) for r in resids)
    for n in nodes:
        body += bytes(n)
    return struct.pack("<HHI", RES_XML_TYPE, 8, 8 + len(body)) + body


def string_refs(n):
    """Every offset in node chunk `n` that holds a string-pool index."""
    t, hs = u16(n, 0), u16(n, 2)
    yield 12                                        # the node's comment
    if t in (RES_XML_START_NS, RES_XML_END_NS, RES_XML_END_ELEM):
        yield hs
        yield hs + 4
    elif t == RES_XML_CDATA:
        yield hs
        if n[hs + 7] == TYPE_STRING:
            yield hs + 8
    elif t == RES_XML_START_ELEM:
        yield hs
        yield hs + 4
        astart, asize, acount = u16(n, hs + 8), u16(n, hs + 10), u16(n, hs + 12)
        for i in range(acount):
            a = hs + astart + i * asize
            yield a                                 # namespace
            yield a + 4                             # name
            yield a + 8                             # raw value
            if n[a + 15] == TYPE_STRING:
                yield a + 16


def attrs_of(n):
    hs = u16(n, 2)
    astart, asize, acount = u16(n, hs + 8), u16(n, hs + 10), u16(n, hs + 12)
    return [hs + astart + i * asize for i in range(acount)], asize, acount


def patch_manifest(data):
    pool, resids, nodes = parse(data)
    if serialize(pool, resids, nodes) != data:
        raise ValueError("cannot rebuild this manifest byte for byte; refusing to patch it")
    if ATTR_ID in resids:
        raise ValueError("the manifest already names %s" % ATTR_NAME)
    if ANDROID_NS not in pool.strings:
        raise ValueError("no android namespace in the manifest")

    # the new attribute name goes in the resource-map half of the pool, in resource-id order (what aapt2 does)
    new_idx = len([r for r in resids if r < ATTR_ID])
    pool.strings.insert(new_idx, ATTR_NAME)
    pool.count += 1
    resids.insert(new_idx, ATTR_ID)
    for n in nodes:                                 # every index at or after it moves up one
        for off in string_refs(n):
            v = u32(n, off)
            if v != NIL and v >= new_idx:
                struct.pack_into("<I", n, off, v + 1)

    # the activity to put it on: the one that is com.godot.game.GodotApp (every index read from here on is the
    # pool's new numbering, which is what the nodes now hold)
    ns_idx = pool.strings.index(ANDROID_NS)
    name_idx = pool.strings.index("name")
    activity_idx = pool.strings.index("activity")
    target = None
    for n in nodes:
        if u16(n, 0) != RES_XML_START_ELEM or u32(n, u16(n, 2) + 4) != activity_idx:
            continue
        offs, asize, _ = attrs_of(n)
        for a in offs:
            if u32(n, a) == ns_idx and u32(n, a + 4) == name_idx and n[a + 15] == TYPE_STRING \
                    and pool.strings[u32(n, a + 16)].endswith(".GodotApp"):
                target = n
                break
        if target is not None:
            break
    if target is None:
        raise ValueError("no GodotApp <activity> in the manifest")

    hs = u16(target, 2)
    offs, asize, acount = attrs_of(target)
    if asize != 20:
        raise ValueError("unexpected attribute size %d" % asize)
    # in resource-id order among this element's attributes, as aapt2 writes them
    at = len(offs)
    for i, a in enumerate(offs):
        nm = u32(target, a + 4)
        if nm < len(resids) and resids[nm] > ATTR_ID:
            at = i
            break
    attr = struct.pack("<IIIHBBI", ns_idx, new_idx, NIL, 8, 0, TYPE_INT_DEC, SHORT_EDGES)
    ins = hs + u16(target, hs + 8) + at * asize
    target[ins:ins] = attr
    struct.pack_into("<H", target, hs + 12, acount + 1)
    struct.pack_into("<I", target, 4, u32(target, 4) + asize)
    for fld in (14, 16, 18):                        # id/class/style index: 1-based, shifted by an insert before them
        v = u16(target, hs + fld)
        if v > at:
            struct.pack_into("<H", target, hs + fld, v + 1)
    return serialize(pool, resids, nodes)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("apk_in")
    ap.add_argument("apk_out")
    ap.add_argument("--keystore", required=True)
    ap.add_argument("--alias", required=True)
    ap.add_argument("--pass", dest="password", required=True)
    ap.add_argument("--build-tools", default=os.environ.get("ANDROID_BUILD_TOOLS", ""))
    a = ap.parse_args()

    tool = lambda t: os.path.join(a.build_tools, t) if a.build_tools else t
    tmp = tempfile.mkdtemp(prefix="cutout-")
    try:
        with zipfile.ZipFile(a.apk_in) as zin:
            old = zin.read("AndroidManifest.xml")
        new = patch_manifest(old)
        print("AndroidManifest.xml: %d bytes -> %d, %s=shortEdges on the activity" % (len(old), len(new), ATTR_NAME))
        # the rest of the APK is left exactly as the export wrote it: one entry replaced in a copy of the zip (822
        # of its 2705 entries are stored uncompressed, and repacking them in Python would recompress the lot)
        staged = os.path.join(tmp, "staged.apk")
        shutil.copyfile(a.apk_in, staged)
        manifest = os.path.join(tmp, "AndroidManifest.xml")
        with open(manifest, "wb") as f:
            f.write(new)
        os.utime(manifest, (MTIME, MTIME))          # (zip stamps the entry from the file: a fixed one, so two runs
                                                    #  over the same export give the same APK byte for byte)
        subprocess.run(["zip", "-q", "-d", staged, "META-INF/*.RSA", "META-INF/*.SF", "META-INF/MANIFEST.MF"],
                       check=False)                 # (an unsigned export has none)
        subprocess.run(["zip", "-q", "-X", staged, "AndroidManifest.xml"], cwd=tmp, check=True)
        aligned = os.path.join(tmp, "aligned.apk")
        subprocess.run([tool("zipalign"), "-p", "-f", "4", staged, aligned], check=True)
        if os.path.exists(a.apk_out):
            os.remove(a.apk_out)
        subprocess.run([tool("apksigner"), "sign", "--ks", a.keystore, "--ks-key-alias", a.alias,
                        "--ks-pass", "pass:" + a.password, "--key-pass", "pass:" + a.password,
                        "--v4-signing-enabled", "false",    # (v4 is a separate .idsig file nothing here wants)
                        "--out", a.apk_out, aligned], check=True)
        subprocess.run([tool("apksigner"), "verify", "--print-certs", a.apk_out], check=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
