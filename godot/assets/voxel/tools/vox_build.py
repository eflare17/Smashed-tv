#!/usr/bin/env python3
"""Builds the block (voxel) characters from their pixel art. Owned by the voxel session (integration/voxel.md).

    python3 godot/assets/voxel/tools/vox_build.py [jared|goth|tyson|weapons|all]

For each character it reads the sprites in godot/assets/CHARS (a front frame, a side frame and a back frame), cuts the
body into parts (head, hair, torso, upper/lower arms, hands, upper/lower legs, feet, accessories) and turns each part
into a voxel grid, about one voxel per sprite pixel:

  * the shape: each row of a part is the front frame's silhouette across (so from the front it is the pixel art,
    pixel for pixel) and a depth range front to back (from the side frame where it shows the part cleanly, else a
    profile written below), rounded into a super-ellipse so limbs are round and the chest is a barrel;
  * the colours: every surface voxel takes the colour of the frame that faces it: the front frame for voxels facing
    front, the back frame (part by part, its own box scaled onto the part's) for voxels facing back, the side frame
    (head) or the front frame's colour just inside its outline (limbs, torso) for the sides. The sprites' own
    outline and shading come along with them, so it reads like the pixel art from any side.

Each part is saved as a MagicaVoxel .vox file (assets/voxel/<char>/<part>.vox, editable in MagicaVoxel) and the rig
(bones with their pivots, which part hangs on which bone, where each grid sits) as assets/voxel/<char>/rig.json.

Axes. Model space is in voxels with the feet's centre on the floor at the origin: x across (+x is the character's
left, the viewer's right when he faces you), y up, z forward (toward the viewer of the front frame). A .vox file
stores (vx, vy, vz) with z up; the reader maps vox (vx, vy, vz) to model (ox + vx, oy + vz, oz + (sy - 1 - vy)),
where (ox, oy, oz) is the part's "origin" in rig.json and sy its grid's depth. So in MagicaVoxel the character
stands upright and looks toward -y.
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(GODOT, "assets", "voxel")


# ------------------------------------------------------------------ .vox

def write_vox(path, vox):
    """vox: dict (x, y, z) model-relative ints (y up, z forward) -> (r, g, b). Saved with its own palette."""
    if not vox:
        raise ValueError("empty part " + path)
    xs = [p[0] for p in vox]
    ys = [p[1] for p in vox]
    zs = [p[2] for p in vox]
    x0, y0, z0 = min(xs), min(ys), min(zs)
    sx, sy, sz = max(xs) - x0 + 1, max(zs) - z0 + 1, max(ys) - y0 + 1   # vox axes: depth is vy, up is vz
    cols = sorted(set(vox.values()))
    if len(cols) > 255:
        cols, remap = quantise(cols, 255)
    else:
        remap = {c: c for c in cols}
    index = {c: i + 1 for i, c in enumerate(cols)}
    xyzi = bytearray()
    for (x, y, z), c in vox.items():
        vx = x - x0
        vy = (sy - 1) - (z - z0)
        vz = y - y0
        xyzi += struct.pack("<BBBB", vx, vy, vz, index[remap[c]])
    pal = bytearray()
    for i in range(256):
        c = cols[i] if i < len(cols) else (0, 0, 0)
        pal += struct.pack("<BBBB", c[0], c[1], c[2], 255)

    def chunk(cid, content, children=b""):
        return cid + struct.pack("<ii", len(content), len(children)) + content + children

    size = chunk(b"SIZE", struct.pack("<iii", sx, sy, sz))
    xy = chunk(b"XYZI", struct.pack("<i", len(vox)) + bytes(xyzi))
    rgba = chunk(b"RGBA", bytes(pal))
    main = chunk(b"MAIN", b"", size + xy + rgba)
    with open(path, "wb") as f:
        f.write(b"VOX " + struct.pack("<i", 150) + main)
    return [x0, y0, z0], [sx, sy, sz]


def quantise(cols, n):
    """Median-cut-ish: merge the closest colours until n are left. Returns (palette, {colour: palette colour})."""
    arr = np.array(cols, dtype=float)
    img = Image.fromarray(arr.reshape(1, -1, 3).astype(np.uint8), "RGB")
    q = img.quantize(colors=n, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()[: n * 3]
    idx = np.array(q).reshape(-1)
    palette = [tuple(pal[i * 3: i * 3 + 3]) for i in range(n)]
    remap = {tuple(int(v) for v in cols[i]): palette[idx[i]] for i in range(len(cols))}
    used = sorted(set(remap.values()))
    return used, remap


def read_vox(path):
    """For checks: returns {(vx, vy, vz): (r, g, b)} and the size."""
    data = open(path, "rb").read()
    assert data[:4] == b"VOX "
    i = 8
    size = None
    pts = []
    pal = None
    while i < len(data):
        cid = data[i: i + 4]
        n, m = struct.unpack("<ii", data[i + 4: i + 12])
        body = data[i + 12: i + 12 + n]
        if cid == b"MAIN":
            i += 12
            continue
        if cid == b"SIZE":
            size = struct.unpack("<iii", body)
        elif cid == b"XYZI":
            k = struct.unpack("<i", body[:4])[0]
            pts = [tuple(body[4 + j * 4: 8 + j * 4]) for j in range(k)]
        elif cid == b"RGBA":
            pal = [tuple(body[j * 4: j * 4 + 3]) for j in range(256)]
        i += 12 + n + m
    return {(p[0], p[1], p[2]): pal[p[3] - 1] for p in pts}, size


# ------------------------------------------------------------------ pictures

def load(sheet, key, scale=1.0):
    p = os.path.join(GODOT, "assets", "CHARS", sheet, "sprites", key + ".png")
    im = Image.open(p).convert("RGBA")
    if scale != 1.0:
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.NEAREST)
    return np.array(im).astype(int)


def opaque(img, c, r):
    return 0 <= r < img.shape[0] and 0 <= c < img.shape[1] and img[r, c, 3] > 128


def rgb(img, c, r):
    p = img[r, c]
    return (int(p[0]), int(p[1]), int(p[2]))


def is_skin(p):
    r, g, b = p[0], p[1], p[2]
    return r > g + 25 and r > 110 and g > 0.48 * r


def is_whiteish(p):
    return p[0] > 200 and p[1] > 200 and p[2] > 200


def nearest_opaque(img, c, r, box, ok=None):
    """The nearest opaque pixel to (c, r) inside box (c0, r0, c1, r1), optionally passing ok(pixel)."""
    c0, r0, c1, r1 = box
    c = min(max(int(round(c)), c0), c1)
    r = min(max(int(round(r)), r0), r1)
    for rad in range(0, 40):
        best = None
        for dr in range(-rad, rad + 1):
            for dc in range(-rad, rad + 1):
                if max(abs(dr), abs(dc)) != rad:
                    continue
                cc, rr = c + dc, r + dr
                if c0 <= cc <= c1 and r0 <= rr <= r1 and opaque(img, cc, rr):
                    if ok is None or ok(img[rr, cc]):
                        d = dr * dr + dc * dc
                        if best is None or d < best[0]:
                            best = (d, cc, rr)
        if best:
            return rgb(img, best[1], best[2])
    return None


def lerp_profile(keys, r):
    """keys: [(row, a, b), ...] sorted by row; linear between them, held past the ends."""
    if r <= keys[0][0]:
        return keys[0][1], keys[0][2]
    for (ra, a0, b0), (rb, a1, b1) in zip(keys, keys[1:]):
        if ra <= r <= rb:
            t = (r - ra) / float(rb - ra)
            return a0 + (a1 - a0) * t, b0 + (b1 - b0) * t
    return keys[-1][1], keys[-1][2]


# ------------------------------------------------------------------ the builder

class Model:
    """Collects parts in model space. Coordinates: x = front column - cx0, y = foot - row, z = depth."""

    def __init__(self, name, front, cx0, foot, back=None, side=None, cz0=0.0):
        self.name = name
        self.front = front
        self.back = back
        self.side = side
        self.cx0 = cx0
        self.cz0 = cz0
        self.foot = foot          # the row just under the feet (a voxel in row r spans y = foot - 1 - r)
        self.parts = {}           # name -> {"vox": {(x,y,z): rgb}, "bone": str, ...}
        self.part_meta = {}
        self.bones = []           # [{"name", "parent", "pivot"}]
        self.occ = None

    def bone(self, name, parent, pivot):
        self.bones.append({"name": name, "parent": parent, "pivot": [float(v) for v in pivot]})

    def y_of(self, r):
        return self.foot - 1 - r

    def x_of(self, c):
        return int(c - self.cx0)

    def add_shape(self, part, bone, rows, row_mask, depth, power=2.4, mirror=False, colour=None, side_img=False,
                  back_box=None, front_box=None, z_round=True):
        """One part from front-frame rows: row_mask(r) -> list of columns in the part on that row; depth(r, c0, c1)
        -> (zb, zf) the depth range there. mirror: reflect across x = 0 (the left arm from the right one's pixels).
        back_box: (c0, r0, c1, r1) where the part is in the back frame. colour: how surface voxels pick colours
        (filled in later, see colourise)."""
        vox = {}
        for r in rows:
            cols = sorted(row_mask(r))
            if not cols:
                continue
            c0, c1 = cols[0], cols[-1]
            xc = (c0 + c1 + 1) / 2.0
            hw = max(0.5, (c1 + 1 - c0) / 2.0)
            zb, zf = depth(r, c0, c1)
            zc = (zb + zf) / 2.0
            hd = max(0.5, (zf - zb) / 2.0)
            y = self.y_of(r)
            for c in cols:
                u = abs((c + 0.5) - xc) / hw
                u = min(u, 1.0)
                k = (1.0 - u ** power) ** (1.0 / power) if z_round else 1.0
                half = max(0.75, hd * k)
                for z in range(int(np.floor(zc - half)), int(np.ceil(zc + half))):
                    if zc - half <= z + 0.5 <= zc + half:
                        x = self.x_of(c)
                        if mirror:
                            x = -x - 1
                        vox[(x, y, z)] = (c, r)
        self.parts[part] = {"vox": vox, "bone": bone, "mirror": mirror, "side_img": side_img,
                            "back_box": back_box, "front_box": front_box, "colour": colour}
        return vox

    def add_voxels(self, part, bone, vox):
        self.parts[part] = {"vox": vox, "bone": bone, "fixed": True}

    # -- colours

    def normals(self):
        allv = {}
        for p in self.parts.values():
            for k in p["vox"]:
                allv[k] = True
        xs = [k[0] for k in allv]
        ys = [k[1] for k in allv]
        zs = [k[2] for k in allv]
        self.min = (min(xs) - 3, min(ys) - 3, min(zs) - 3)
        shape = (max(xs) - self.min[0] + 4, max(ys) - self.min[1] + 4, max(zs) - self.min[2] + 4)
        occ = np.zeros(shape, dtype=np.float32)
        for k in allv:
            occ[k[0] - self.min[0], k[1] - self.min[1], k[2] - self.min[2]] = 1.0
        self.occ = occ
        empty = 1.0 - occ
        n = np.zeros(shape + (3,), dtype=np.float32)
        R = 2
        pad = np.pad(empty, R, constant_values=1.0)
        for dx in range(-R, R + 1):
            for dy in range(-R, R + 1):
                for dz in range(-R, R + 1):
                    if dx == dy == dz == 0:
                        continue
                    w = 1.0 / (dx * dx + dy * dy + dz * dz)
                    sh = pad[R + dx: R + dx + shape[0], R + dy: R + dy + shape[1], R + dz: R + dz + shape[2]]
                    n[..., 0] += sh * dx * w
                    n[..., 1] += sh * dy * w
                    n[..., 2] += sh * dz * w
        self.nrm = n

    def exposed(self, k):
        x, y, z = k[0] - self.min[0], k[1] - self.min[1], k[2] - self.min[2]
        o = self.occ
        return (o[x + 1, y, z] == 0 or o[x - 1, y, z] == 0 or o[x, y + 1, z] == 0 or o[x, y - 1, z] == 0
                or o[x, y, z + 1] == 0 or o[x, y, z - 1] == 0)

    def normal(self, k):
        v = self.nrm[k[0] - self.min[0], k[1] - self.min[1], k[2] - self.min[2]]
        l = float(np.linalg.norm(v))
        return v / l if l > 1e-6 else np.array([0.0, 0.0, 1.0])

    def colourise(self):
        self.normals()
        for name, p in self.parts.items():
            if p.get("fixed"):
                continue
            vox = p["vox"]
            col = {}
            surf = []
            for k, (c, r) in vox.items():
                if not self.exposed(k):
                    continue
                n = self.normal(k)
                col[k] = self.pick(p, k, c, r, n)
                surf.append(col[k])
            fill = self.fill_colour(surf)
            for k in vox:
                if k not in col:
                    col[k] = fill
            p["vox"] = col

    @staticmethod
    def fill_colour(surf):
        if not surf:
            return (60, 40, 40)
        a = np.array(surf, dtype=float)
        m = np.median(a, axis=0) * 0.7
        return tuple(int(v) for v in m)

    def row_cols(self, p, r):
        return sorted(c for (c, rr) in p["_rows"].get(r, [])) if "_rows" in p else []

    def pick(self, p, k, c, r, n):
        img = self.front
        # which way it faces: front, back or a side (top and bottom go with the front/back they lean to)
        nz, nx, ny = n[2], n[0], n[1]
        if p.get("mirror"):
            nx = -nx
        rows = p.setdefault("_rowx", {})
        if r not in rows:
            cs = [cc for (cc, rr) in p["vox"].values() if rr == r]
            rows[r] = (min(cs), max(cs))
        c0, c1 = rows[r]
        if nz > 0.42 or (ny > 0.6 and nz > -0.25) or (ny < -0.6 and nz > -0.25):
            kw = p.get("keep_white")
            if opaque(img, c, r) and (not is_whiteish(img[r, c]) or (kw and kw[0] <= c <= kw[1])):
                return rgb(img, c, r)
            q = nearest_opaque(img, c, r, (c0, r - 2, c1, r + 2), lambda px: not is_whiteish(px))
            return q or (80, 60, 50)
        if nz < -0.42 or ny > 0.6 or ny < -0.6:
            return self.from_back(p, k, c, r, c0, c1)
        # a side
        if p.get("side_img") and self.side is not None:
            sc = int(round(k[2] + self.cz0))
            q = None
            if opaque(self.side, sc, r):
                q = rgb(self.side, sc, r)
            else:
                q = nearest_opaque(self.side, sc, r, p["side_img"])
            if q:
                return q
        inset = 2
        cc = c0 + inset if nx < 0 else c1 - inset
        if p.get("mirror"):
            cc = c0 + inset if nx > 0 else c1 - inset
        if nz < -0.1 and self.back is not None and p.get("back_box"):
            return self.from_back(p, k, cc, r, c0, c1, side=True)
        if opaque(img, cc, r) and not is_whiteish(img[r, cc]):
            return rgb(img, cc, r)
        q = nearest_opaque(img, cc, r, (c0, r - 3, c1, r + 3), lambda px: not is_whiteish(px))
        return q or (80, 60, 50)

    def from_back(self, p, k, c, r, c0, c1, side=False):
        bb = p.get("back_box")
        if self.back is None or bb is None:
            q = nearest_opaque(self.front, c, r, (c0, r - 3, c1, r + 3), lambda px: not is_whiteish(px))
            return darker(q or (80, 60, 50), 0.85)
        fb = p.get("front_box")
        if fb is None:
            vs = p["vox"].values()
            fb = (min(v[0] for v in vs), min(v[1] for v in vs), max(v[0] for v in vs), max(v[1] for v in vs))
            p["front_box"] = fb
        fc0, fr0, fc1, fr1 = fb
        bc0, br0, bc1, br1 = bb
        u = (c + 0.5 - fc0) / max(1.0, fc1 + 1 - fc0)
        v = (r + 0.5 - fr0) / max(1.0, fr1 + 1 - fr0)
        if p.get("back_mirror", True):
            u = 1.0 - u
        bc = bc0 + u * (bc1 + 1 - bc0)
        br = br0 + v * (br1 + 1 - br0)
        if side:
            # the back frame's own edge on this row, inset like the front
            pass
        q = nearest_opaque(self.back, bc, br, bb, lambda px: not is_whiteish(px))
        return q or (80, 60, 50)

    # -- output

    def save(self, extra=None):
        d = os.path.join(OUT, self.name)
        os.makedirs(d, exist_ok=True)
        parts = []
        for name, p in self.parts.items():
            vox = p["vox"]
            if not vox:
                continue
            origin, size = write_vox(os.path.join(d, name + ".vox"), vox)
            meta = {"name": name, "bone": p["bone"], "file": name + ".vox", "origin": origin, "size": size}
            meta.update(p.get("meta", {}))
            parts.append(meta)
        rig = {"char": self.name, "bones": self.bones, "parts": parts}
        if extra:
            rig.update(extra)
        with open(os.path.join(d, "rig.json"), "w") as f:
            json.dump(rig, f, indent=1)
        n = sum(len(p["vox"]) for p in self.parts.values())
        print("%s: %d parts, %d voxels" % (self.name, len(parts), n))


def darker(c, k):
    return tuple(int(max(0, min(255, v * k))) for v in c)


# ------------------------------------------------------------------ helpers for masks

def run_from(img, r, start, step, ok):
    """Columns from start going step while ok(pixel) (transparent stops it)."""
    out = []
    c = start
    while 0 <= c < img.shape[1] and opaque(img, c, r) and ok(img[r, c], c):
        out.append(c)
        c += step
    return out


def cols_where(img, r, c0, c1, ok=None):
    return [c for c in range(max(0, c0), min(img.shape[1] - 1, c1) + 1)
            if opaque(img, c, r) and (ok is None or ok(img[r, c]))]


def side_extent(img, r, c0, c1):
    cs = cols_where(img, r, c0, c1)
    return (cs[0], cs[-1]) if cs else None


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    sys.path.insert(0, HERE)
    import chars
    chars.build(which)
