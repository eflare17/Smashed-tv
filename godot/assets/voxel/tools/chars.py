"""The characters' part tables for vox_build.py: which pixels of which frame make which part, the joints, the depth
profiles. Coordinates are the reference frames' pixels (column, row); see vox_build.py for the model axes."""
import json
import os

import numpy as np

from vox_build import (Model, load, opaque, rgb, is_skin, is_whiteish, cols_where, side_extent, darker,
                       write_vox, OUT, GODOT, nearest_opaque)


def dark(p):
    return max(p[0], p[1], p[2]) < 100


def arm_run(img, r, start_max=24):
    """The arm hanging on the frame's left: from the first opaque column (left of start_max), skin and its outline,
    stopping at the first dark pixel that isn't followed by more skin."""
    c = 0
    while c < start_max and not opaque(img, c, r):
        c += 1
    if c >= start_max:
        return []
    out = []
    while c < img.shape[1] and opaque(img, c, r):
        p = img[r, c]
        if is_skin(p) or (p[0] > 150 and p[0] > p[2] + 30):
            out.append(c)
        elif dark(p):
            ahead = [img[r, c + k] for k in (1, 2) if c + k < img.shape[1] and opaque(img, c + k, r)]
            if any(is_skin(q) for q in ahead):
                out.append(c)
            else:
                out.append(c)
                break
        else:
            break
        c += 1
    return out


def joint(m, c, r, z=0.0):
    return (c - m.cx0, m.foot - r, z)


def mirror_pt(p):
    return (-p[0], p[1], p[2])


def is_hair(p):
    mx = max(p[0], p[1], p[2])
    return mx < 125 and p[0] >= p[2] - 4 and p[1] < p[0] + 25


def is_blue(p):
    return p[2] > 150 and p[0] < 110 and p[2] > p[1] + 10


def neighbours6(k):
    x, y, z = k
    return [(x + 1, y, z), (x - 1, y, z), (x, y + 1, z), (x, y - 1, z), (x, y, z + 1), (x, y, z - 1)]


# ------------------------------------------------------------------ Juicy Jared

def jared():
    front = load("juicy_spud", "reload_0")          # standing, arms down (91 x 160)
    side = load("juicy_spud", "reload_side_1")      # side on, facing right
    back = load("juicy_spud", "back")               # from behind (drawn from higher up: boxes per part)
    m = Model("jared", front, cx0=42, foot=160, back=back, side=side, cz0=35)

    # -- bones (front-frame pixels; z forward)
    sh = joint(m, 12.5, 52, -2)
    el = joint(m, 9.5, 81, -2)
    wr = joint(m, 7.5, 97, -2)
    hip = joint(m, 58.5, 108, 0)
    kn = joint(m, 59.5, 132, 0)
    an = joint(m, 61.0, 148, -1)
    m.bone("hips", "", joint(m, 42, 98, 0))
    m.bone("chest", "hips", joint(m, 42, 92, 0))
    m.bone("head", "chest", joint(m, 42, 50, 1))
    m.bone("arm_r", "chest", sh)
    m.bone("forearm_r", "arm_r", el)
    m.bone("hand_r", "forearm_r", wr)
    m.bone("arm_l", "chest", mirror_pt(sh))
    m.bone("forearm_l", "arm_l", mirror_pt(el))
    m.bone("hand_l", "forearm_l", mirror_pt(wr))
    m.bone("thigh_l", "hips", hip)
    m.bone("shin_l", "thigh_l", kn)
    m.bone("foot_l", "shin_l", an)
    m.bone("thigh_r", "hips", mirror_pt(hip))
    m.bone("shin_r", "thigh_r", mirror_pt(kn))
    m.bone("foot_r", "shin_r", mirror_pt(an))

    # -- head (with the hair and the sunglasses, split off below)
    def head_cols(r):
        if r < 40:
            return cols_where(front, r, 20, 62)
        return cols_where(front, r, 29, 55, lambda p: not (p[1] > p[0] + 20))

    def head_depth(r, c0, c1):
        e = side_extent(side, r, 21, 58) if r < 40 else side_extent(side, r, 30, 58)
        if e is None:
            return (-12.0, 14.0)
        zb, zf = e[0] - m.cz0, e[1] + 1 - m.cz0
        if r >= 44:
            zb = max(zb, -8.0)
        return (zb, zf)

    m.add_shape("head", "head", range(12, 56), head_cols, head_depth, power=2.6, side_img=(20, 8, 60, 56),
                back_box=(22, 25, 50, 58))

    # -- torso (the singlet, the shoulders' tops and the neck's sides)
    def arm_end(r):
        a = arm_run(front, r)
        return a[-1] if a else 15

    def torso_cols(r):
        lo = arm_end(r) + 1
        hi = int(2 * m.cx0) - lo
        if r >= 80:
            lo, hi = max(lo, 20), min(hi, 63 if r < 85 else 60)     # (the sprite's gun at his side, his other hand on his hip)
        if r >= 62:
            return cols_where(front, r, lo, hi, lambda p: not is_skin(p) and not (p[0] > 150 and p[0] > p[2] + 30))
        return cols_where(front, r, lo, hi)

    torso_prof = [(40, -10, 6), (48, -15, 12), (60, -18, 17), (75, -19, 20), (88, -19, 20), (96, -19, 18)]
    m.add_shape("torso", "chest", range(44, 96), torso_cols, lambda r, a, b: lerp(torso_prof, r), power=2.3,
                back_box=(17, 58, 58, 103))
    m.parts["torso"]["keep_white"] = (24, 60)

    # -- pelvis (the shorts' top)
    def pelvis_cols(r):
        lo = max(arm_end(r) + 1, 20)
        hi = min(int(2 * m.cx0) - lo, 64)
        cs = cols_where(front, r, lo, hi, lambda p: not is_skin(p) and not (p[0] > 150 and p[0] > p[2] + 30))
        return [c for c in cs if c <= 70 - max(0, 100 - r)] if r < 108 else cs

    m.add_shape("pelvis", "hips", range(96, 109), pelvis_cols, lambda r, a, b: (-20.0, 17.0), power=2.6,
                back_box=(15, 101, 60, 116))

    # -- legs (the left one from the frame's right-hand leg; the right one its mirror)
    def leg_cols(r0, r1, c0, c1):
        return lambda r: cols_where(front, r, c0, c1) if r0 <= r <= r1 else []

    def round_depth(k=1.0, zc=0.0):
        def f(r, c0, c1):
            w = (c1 + 1 - c0) * k
            return (zc - w / 2.0, zc + w / 2.0)
        return f

    foot_prof = [(147, -8, 8), (151, -10, 15), (159, -10, 17)]
    legs = [("thigh", range(109, 132), (44, 72), round_depth(0.95, 0.0), (15, 112, 37, 136)),
            ("shin", range(132, 148), (44, 74), round_depth(0.95, -1.0), (15, 136, 37, 148)),
            ("foot", range(148, 160), (46, 80), lambda r, a, b: lerp(foot_prof, r), (15, 148, 37, 159))]
    for nm, rows, (c0, c1), dep, bb in legs:
        rr = list(rows)
        m.add_shape(nm + "_l", nm + "_l", rr, leg_cols(rr[0], rr[-1], c0, c1), dep, power=2.4 if nm != "foot" else 3.2,
                    back_box=bb)
        rb = (bb[0] + 24, bb[1], bb[2] + 23, bb[3])      # the other leg in the back frame
        m.add_shape(nm + "_r", nm + "_r", rr, leg_cols(rr[0], rr[-1], c0, c1), dep, power=2.4 if nm != "foot" else 3.2,
                    mirror=True, back_box=rb)
        m.parts[nm + "_r"]["back_mirror"] = False

    # -- arms (the right one from the frame's left-hand arm; the left one its mirror)
    def arm_cols(r0, r1):
        return lambda r: arm_run(front, r) if r0 <= r <= r1 else []

    arm_depth = round_depth(0.95, -2.0)
    for nm, r0, r1 in [("arm", 44, 81), ("forearm", 82, 97), ("hand", 98, 108)]:
        m.add_shape(nm + "_r", nm + "_r", range(r0, r1 + 1), arm_cols(r0, r1), arm_depth, power=2.2)
        m.add_shape(nm + "_l", nm + "_l", range(r0, r1 + 1), arm_cols(r0, r1), arm_depth, power=2.2, mirror=True)

    for nm in ("torso", "pelvis"):
        for k in [k for k in m.parts[nm]["vox"] if k in m.parts["head"]["vox"]]:
            del m.parts[nm]["vox"][k]
    for k in [k for k in m.parts["pelvis"]["vox"] if k in m.parts["torso"]["vox"]]:
        del m.parts["pelvis"]["vox"][k]
    m.colourise()
    split_head(m)
    hair_styles(m)
    m.save({"ref_sheet": "juicy_spud", "ref_key": "reload", "ref_frame": 0, "ref_rows": 160,
            "cx0": m.cx0, "foot": m.foot, "cz0": m.cz0,
            "grip_r": list(joint(m, 7.5, 104, 0)), "styles": STYLE_LIST})
    return m


def lerp(keys, r):
    if r <= keys[0][0]:
        return keys[0][1], keys[0][2]
    for (ra, a0, b0), (rb, a1, b1) in zip(keys, keys[1:]):
        if ra <= r <= rb:
            t = (r - ra) / float(rb - ra)
            return a0 + (a1 - a0) * t, b0 + (b1 - b0) * t
    return keys[-1][1], keys[-1][2]


SCALP = (168, 104, 74)


def split_head(m):
    """Hair and sunglasses off the head into their own parts; a scalp under the hair."""
    head = m.parts["head"]["vox"]
    ys = [k[1] for k in head]
    top = max(ys)
    hair0 = set()
    glasses = {}
    for k, c in head.items():
        if not m.exposed(k):
            continue
        n = m.normal(k)
        row = m.foot - 1 - k[1]
        if is_blue(c) and n[2] > 0.2 and row < 40:
            glasses[k] = c
        elif is_hair(c) and row < 44 and (row < 30 or n[2] < 0.35) and not (row >= 35 and n[2] > 0.0):
            hair0.add(k)
    hair = {k: head[k] for k in hair0}
    for k in list(hair0):
        for q in neighbours6(k):
            if q in head and q not in hair and not m.exposed(q):
                hair[q] = head[k]
    for k in hair:
        del head[k]
    for k in list(head.keys()):
        if any(q in hair for q in neighbours6(k)):
            head[k] = SCALP
    gl = {}
    for k, c in glasses.items():
        gl[(k[0], k[1], k[2] + 1)] = c
        head[k] = (34, 34, 44)
    m.add_voxels("hair_classic", "head", hair)
    m.parts["hair_classic"]["meta"] = {"group": "hair", "style": "classic"}
    m.add_voxels("glasses", "head", gl)
    m.parts["glasses"]["meta"] = {"group": "glasses"}
    m.scalp = set(k for k, c in head.items() if c == SCALP)


# ------------------------------------------------------------------ hair styles (the mirror's)

STYLE_LIST = ["classic", "braids", "mullet", "slick", "tyson", "mohawk", "mohawk_blue", "mohawk_purple", "mohawk_green"]


def hair_styles(m):
    """Each mirror style from its front / side / back art (scripts/lobby_life/art/bedroom/hair), placed on the run
    frame 0's head (HAIR_HEAD) and fitted to this model's head: the art's hair pixels, front x side as a hull, kept
    outside the bald head."""
    from PIL import Image
    base = os.path.join(GODOT, "scripts", "lobby_life", "art", "bedroom")
    data = json.load(open(os.path.join(base, "hair_data.json")))
    heads = data["HAIR_HEAD"]          # view: [centre x, top, bottom, half width] in the run frame 0
    head = m.parts["head"]["vox"]
    hx = [k[0] for k in head]
    hy = [k[1] for k in head]
    hz = [k[2] for k in head]
    # this model's head: centre x, top y, the face's front z, the back z
    mcx = (min(hx) + max(hx) + 1) / 2.0
    mtop = max(hy) + 1 + 2         # (the hair was on top: put back the classic's height)
    mhw = (max(hx) + 1 - min(hx)) / 2.0
    zf = max(hz) + 1
    zb = min(hz)
    occ = set(head.keys())

    def img(st, view):
        p = os.path.join(base, "hair", "%s_%s.png" % (st, view))
        return np.array(Image.open(p).convert("RGBA")).astype(int) if os.path.exists(p) else None

    for st in STYLE_LIST[1:]:
        art = data["HAIR_ART"].get(st)
        if not art:
            continue
        F, S, B = img(st, "front"), img(st, "side"), img(st, "back")
        fh, sh_, bh = heads["front"], heads["side"], heads["back"]
        # front: run-frame x -> model x; y: run-frame row -> model y (head top lines up)
        s = mhw / fh[3]

        def fpix(x, y):
            col = (x + 0.5 - mcx) / s + fh[0] - art["front"]["at"][0]
            row = (mtop - (y + 0.5)) / s + fh[1] - art["front"]["at"][1] - 2
            return int(np.floor(col)), int(np.floor(row))

        # side: run frame's side view faces right; its head spans HAIR_HEAD.side centre +- half width in depth too
        sd = (zf - zb) / 2.0
        szc = (zf + zb) / 2.0
        ss = sd / sh_[3]

        def spix(z, y):
            col = (z + 0.5 - szc) / ss + sh_[0] - art["side"]["at"][0] + 2
            row = (mtop - (y + 0.5)) / s + sh_[1] - art["side"]["at"][1] - 2
            return int(np.floor(col)), int(np.floor(row))

        def bpix(x, y):
            col = -(x + 0.5 - mcx) / (mhw / bh[3]) + bh[0] - art["back"]["at"][0]
            row = (mtop - (y + 0.5)) / s + bh[1] - art["back"]["at"][1] - 2
            return int(np.floor(col)), int(np.floor(row))

        def hairy(im, c, r):
            if im is None or not opaque(im, c, r):
                return False
            p = im[r, c]
            return not is_skin(p) and not is_blue(p) and not (p[0] > 200 and p[1] > 200 and p[2] > 200)

        vox = {}
        X0, X1 = int(mcx - mhw * 1.8), int(mcx + mhw * 1.8)
        Y0, Y1 = int(mtop - 70), int(mtop + 30)
        Z0, Z1 = int(zb - 14), int(zf + 6)
        for x in range(X0, X1):
            for y in range(Y0, Y1):
                fc, fr = fpix(x, y)
                if not hairy(F, fc, fr):
                    continue
                for z in range(Z0, Z1):
                    if (x, y, z) in occ:
                        continue
                    sc, sr = spix(z, y)
                    if hairy(S, sc, sr):
                        vox[(x, y, z)] = None
        if not vox:
            print("style", st, "empty")
            continue
        # thin it to a shell (outside the head, within 6 voxels of it or of the hull's outside)
        keep = {}
        for k in vox:
            exposed = any(q not in vox and q not in occ for q in neighbours6(k))
            if exposed:
                keep[k] = True
        for _ in range(2):
            for k in list(keep.keys()):
                for q in neighbours6(k):
                    if q in vox:
                        keep[q] = True
        out = {}
        for k in keep:
            x, y, z = k
            nb = [q for q in neighbours6(k) if q not in vox and q not in occ]
            facing = None
            if any(q[2] > z for q in nb):
                facing = "front"
            elif any(q[2] < z for q in nb):
                facing = "back"
            elif nb:
                facing = "side"
            c = None
            if facing == "front":
                fc, fr = fpix(x, y)
                if hairy(F, fc, fr):
                    c = rgb(F, fc, fr)
            elif facing == "back" and B is not None:
                bc, br = bpix(x, y)
                if hairy(B, bc, br):
                    c = rgb(B, bc, br)
                else:
                    c = nearest_opaque(B, bc, br, (0, 0, B.shape[1] - 1, B.shape[0] - 1), lambda p: not is_skin(p))
            if c is None:
                sc, sr = spix(z, y)
                if hairy(S, sc, sr):
                    c = rgb(S, sc, sr)
                else:
                    fc, fr = fpix(x, y)
                    c = rgb(F, fc, fr) if hairy(F, fc, fr) else (40, 28, 24)
            out[k] = c
        m.add_voxels("hair_" + st, "head", out)
        m.parts["hair_" + st]["meta"] = {"group": "hair", "style": st, "optional": True}


# ------------------------------------------------------------------ weapons

def weapon(name, sheet, key, box, grip, thick, scale=1.0, drop=None, keep=None, round_k=0.6, extra=None):
    """A gun from a side frame (facing right): the pixels in box (c0, r0, c1, r1) that aren't skin (or pass keep),
    extruded thick voxels across, rounded at the top and bottom edges. grip (column, row): where the hand holds it,
    the model's origin. Forward is +z (the frame's right), up +y, across x."""
    im = load(sheet, key, scale)
    c0, r0, c1, r1 = [int(round(v * scale)) for v in box]
    gc, gr = grip[0] * scale, grip[1] * scale
    mask = {}
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            if not opaque(im, c, r):
                continue
            p = im[r, c]
            if drop and drop(p, c / scale, r / scale):
                continue
            if keep is not None and not keep(p, c / scale, r / scale):
                continue
            mask[(c, r)] = rgb(im, c, r)
    vox = {}
    cols = {}
    for (c, r) in mask:
        cols.setdefault(c, []).append(r)
    for (c, r), col in mask.items():
        rs = cols[c]
        lo, hi = min(rs), max(rs)
        mid = (lo + hi) / 2.0
        half = max(1.0, (hi - lo + 1) / 2.0)
        u = abs(r + 0.5 - mid - 0.5) / half
        w = thick / 2.0 * (1.0 - round_k * max(0.0, u - 0.55) / 0.45) if u > 0.55 else thick / 2.0
        w = max(0.75, w)
        z = int(c - gc)
        y = int(gr - r)
        for x in range(int(np.floor(-w)), int(np.ceil(w))):
            if -w <= x + 0.5 <= w:
                edge = x + 0.5 >= w - 1.0 or x + 0.5 <= -w + 1.0
                vox[(x, y, z)] = darker(col, 0.82) if edge else col
    if extra:
        extra(vox)
    d = os.path.join(OUT, "weapons")
    os.makedirs(d, exist_ok=True)
    origin, size = write_vox(os.path.join(d, name + ".vox"), vox)
    print("weapon %s: %d voxels" % (name, len(vox)))
    return {"file": name + ".vox", "origin": origin, "size": size}


def weapons():
    out = {}
    skinlike = lambda p, c, r: is_skin(p) and p[1] > 0.5 * p[0]
    out["spud"] = weapon("spud", "juicy_spud", "side_a", (82, 51, 128, 72), (92, 68), 6,
                         drop=lambda p, c, r: (is_skin(p) and p[1] > 0.5 * p[0] and c < 100) or (r > 66 and c < 96))
    out["blaster"] = weapon("blaster", "juicy", "side_a", (64, 57, 118, 76), (80, 72), 9,
                            drop=lambda p, c, r: is_skin(p) or (c < 72 and r > 70))
    out["shotgun"] = weapon("shotgun", "juicy_shotgun", "side_a", (28, 38, 82, 52), (40, 49), 6, scale=2.0,
                            drop=lambda p, c, r: is_skin(p) and p[1] > 0.45 * p[0] and not (52 <= c <= 70))
    out["launcher"] = weapon("launcher", "juicy_launcher", "side_a", (0, 52, 124, 92), (84, 90), 20,
                             drop=lambda p, c, r: is_skin(p) or (r > 82 and not (78 <= c <= 92)) or (52 <= c <= 76 and r > 60 and dark(p) and r > 64 and is_hairish(p)),
                             round_k=0.9)
    with open(os.path.join(OUT, "weapons", "weapons.json"), "w") as f:
        json.dump(out, f, indent=1)


def is_hairish(p):
    return is_hair(p) and p[0] > p[1] + 4


# ------------------------------------------------------------------ Gothica

def side_run(img, r, from_left):
    """The arm hanging at one side of a frame: skin and its outline from the edge inward."""
    w = img.shape[1]
    cs = range(0, w) if from_left else range(w - 1, -1, -1)
    out = []
    started = False
    for c in cs:
        if not opaque(img, c, r):
            if started:
                break
            continue
        p = img[r, c]
        if is_skin(p) or (p[0] > 120 and p[0] > p[2] + 20):
            out.append(c)
            started = True
        elif not started and dark(p):
            out = [c]              # (hair or outline before the arm: keep only the last, its outline)
            if abs(c - (cs[0] if from_left else cs[0])) > 18:
                break
        elif started and dark(p):
            out.append(c)
            break
        else:
            break
    if not any(is_skin(img[r, c]) for c in out):
        return []
    return sorted(out)


def goth():
    front = load("goth", "front_a")
    side = load("goth", "side_a")
    back = load("goth", "back_a")
    m = Model("goth", front, cx0=29, foot=160, back=back, side=side, cz0=37)

    def j(c, r, z=0.0):
        return (c - m.cx0, m.foot - r, z)

    sh, el, wr = j(11.5, 58, -1), j(10.5, 75, -1), j(9.5, 86, -1)
    hip, kn, an = j(23.5, 110, 0), j(23.5, 129, 0), j(23.5, 147, -1)
    m.bone("hips", "", j(29, 92))
    m.bone("chest", "hips", j(29, 80))
    m.bone("head", "chest", j(30, 54, 1))
    m.bone("arm_r", "chest", sh)
    m.bone("forearm_r", "arm_r", el)
    m.bone("hand_r", "forearm_r", wr)
    m.bone("arm_l", "chest", mirror_pt(sh))
    m.bone("forearm_l", "arm_l", mirror_pt(el))
    m.bone("hand_l", "forearm_l", mirror_pt(wr))
    m.bone("thigh_r", "hips", hip)
    m.bone("shin_r", "thigh_r", kn)
    m.bone("foot_r", "shin_r", an)
    m.bone("thigh_l", "hips", mirror_pt(hip))
    m.bone("shin_l", "thigh_l", mirror_pt(kn))
    m.bone("foot_l", "shin_l", mirror_pt(an))

    # the face (her hair is its own part, over it)
    def head_cols(r):
        return cols_where(front, r, 21, 41) if r >= 26 else []
    head_prof = [(26, -8, 9), (34, -9, 13), (46, -8, 12), (56, -5, 6)]
    m.add_shape("head", "head", range(24, 57), lambda r: cols_where(front, r, 21, 41) if r >= 24 else [],
                lambda r, a, b: lerp(head_prof, r), power=2.6, side_img=(30, 24, 52, 56))

    def larm(r):
        return side_run(front, r, True)

    def rarm(r):
        return side_run(front, r, False)

    def torso_cols(r):
        a = larm(r)
        b = rarm(r)
        lo = (a[-1] + 1) if a else 14
        hi = (b[0] - 1) if b else 44
        lo, hi = max(lo, 15), min(hi, 43)
        return cols_where(front, r, lo, hi)
    torso_prof = [(54, -7, 6), (62, -9, 11), (70, -8, 9), (80, -8, 8)]
    m.add_shape("torso", "chest", range(54, 80), torso_cols, lambda r, a, b: lerp(torso_prof, r), power=2.3,
                back_box=(20, 56, 50, 80))

    # the skirt (on the hips; flares out)
    def skirt_cols(r):
        cs = cols_where(front, r, 6, 52, lambda p: not is_skin(p))
        a = larm(r)
        b = rarm(r)
        if a:
            cs = [c for c in cs if c > a[-1]]
        if b:
            cs = [c for c in cs if c < b[0]]
        return cs
    skirt_prof = [(78, -9, 9), (92, -12, 13), (108, -15, 16)]
    m.add_shape("skirt", "hips", range(78, 110), skirt_cols, lambda r, a, b: lerp(skirt_prof, r), power=2.0,
                back_box=(12, 76, 58, 118))
    m.parts["skirt"]["meta"] = {"group": "skirt"}

    def round_depth(k=1.0, zc=0.0):
        def f(r, c0, c1):
            w = (c1 + 1 - c0) * k
            return (zc - w / 2.0, zc + w / 2.0)
        return f

    foot_prof = [(146, -7, 7), (151, -9, 12), (159, -9, 13)]
    legs = [("thigh", range(110, 129), (15, 31), round_depth(1.0), (18, 118, 36, 132)),
            ("shin", range(129, 147), (15, 31), round_depth(1.0, -1.0), (18, 132, 36, 147)),
            ("foot", range(147, 160), (14, 33), lambda r, a, b: lerp(foot_prof, r), (18, 147, 36, 159))]
    for nm, rows, (c0, c1), dep, bb in legs:
        rr = list(rows)
        f = (lambda c0_, c1_: (lambda r: cols_where(front, r, c0_, c1_)))(c0, c1)
        m.add_shape(nm + "_r", nm + "_r", rr, f, dep, power=2.4 if nm != "foot" else 3.0, back_box=bb)
        m.add_shape(nm + "_l", nm + "_l", rr, f, dep, power=2.4 if nm != "foot" else 3.0, mirror=True,
                    back_box=(bb[0] + 18, bb[1], bb[2] + 18, bb[3]))
        m.parts[nm + "_r"]["back_mirror"] = False

    arm_depth = round_depth(0.95, -1.0)
    for nm, r0, r1 in [("arm", 54, 74), ("forearm", 75, 85), ("hand", 86, 92)]:
        f = (lambda a_, b_: (lambda r: larm(r) if a_ <= r <= b_ else []))(r0, r1)
        m.add_shape(nm + "_r", nm + "_r", range(r0, r1 + 1), f, arm_depth, power=2.2)
        m.add_shape(nm + "_l", nm + "_l", range(r0, r1 + 1), f, arm_depth, power=2.2, mirror=True)

    # parts don't share voxels: the earlier wins (the skirt over the thighs' tops, the torso over the skirt's)
    order = ["head", "torso", "skirt"]
    for i, a in enumerate(order):
        for b in list(m.parts.keys()):
            if b in order[: i + 1]:
                continue
            for k in [k for k in m.parts[b]["vox"] if k in m.parts[a]["vox"]]:
                del m.parts[b]["vox"][k]
    m.colourise()
    long_hair(m, front, side, back)
    m.save({"ref_sheet": "goth", "ref_key": "front_a", "ref_frame": 0, "ref_rows": 160,
            "cx0": m.cx0, "foot": m.foot, "cz0": m.cz0, "grip_r": list(j(9.5, 90, 0))})
    return m


def is_goth_hair(p):
    return not is_skin(p) and max(p[0], p[1], p[2]) < 140 and not (p[0] > 200 and p[1] > 200)


def long_hair(m, front, side, back):
    """Her hair: the front frame's hair (and, behind her, the back frame's, mirrored) across, the side frame's front
    to back, kept outside her body; coloured from the frame facing each voxel."""
    occ = set()
    for p in m.parts.values():
        occ.update(p["vox"].keys())
    W = front.shape[1]
    bw = back.shape[1]
    # the back frame: centred on its own body (its hair's middle)
    bcx = 32.0

    def front_hair(c, r):
        return opaque(front, c, r) and is_goth_hair(front[r, c]) and r < 58 and not (21 <= c <= 41 and 27 <= r <= 56)

    def back_hair(x, r):
        bc = int(round(bcx - (x + 0.5)))     # model x -> back frame column (mirrored)
        return opaque(back, bc, r) and is_goth_hair(back[r, bc]) and r < 104

    def side_hair(z, r):
        sc = int(np.floor(z + m.cz0))
        return opaque(side, sc, r) and is_goth_hair(side[r, sc])

    hair = {}
    for r in range(10, 106):
        y = m.foot - 1 - r
        for x in range(-30, 32):
            c = int(x + m.cx0)
            fh = front_hair(c, r)
            bh = back_hair(x, r)
            if not (fh or bh):
                continue
            for z in range(-30, 20):
                if (x, y, z) in occ:
                    continue
                if not side_hair(z, r):
                    continue
                # in front of the face only where the front frame shows hair; behind her, the back frame's
                if z > 0 and not fh:
                    continue
                hair[(x, y, z)] = None
    # keep a shell 4 deep from the outside
    shell = {}
    for k in hair:
        if any(q not in hair and q not in occ for q in neighbours6(k)):
            shell[k] = True
    for _ in range(3):
        for k in list(shell.keys()):
            for q in neighbours6(k):
                if q in hair:
                    shell[q] = True
    out = {}
    for k in shell:
        x, y, z = k
        r = m.foot - 1 - y
        nb = [q for q in neighbours6(k) if q not in hair and q not in occ]
        c = None
        if any(q[2] > z for q in nb):
            cc = int(x + m.cx0)
            if front_hair(cc, r):
                c = rgb(front, cc, r)
        if c is None and any(q[2] < z for q in nb):
            bc = int(round(bcx - (x + 0.5)))
            if back_hair(x, r):
                c = rgb(back, bc, r)
        if c is None:
            sc = int(np.floor(z + m.cz0))
            if side_hair(z, r):
                c = rgb(side, sc, r)
        out[k] = c or (40, 30, 50)
    m.add_voxels("hair", "head", out)
    m.parts["hair"]["meta"] = {"group": "hair_long"}


def build(which):
    if which in ("jared", "all"):
        jared()
    if which in ("goth", "all"):
        goth()
    if which in ("weapons", "all"):
        weapons()
