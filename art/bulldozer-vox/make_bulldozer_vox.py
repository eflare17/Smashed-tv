#!/usr/bin/env python3
"""
Voxel bulldozer generator -> multi-model MagicaVoxel .vox   (detailed version)

Builds a bulldozer about 126 long x 72 wide x 72 tall out of separate models:

    body          main body, engine hood, fenders, rear tank, mounting points
    cab           cab with windows
    exhaust       exhaust stack
    track_left    left track   (machine's own left, looking forward)
    track_right   right track
    blade         blade (detachable)
    blade_lift    push arms + hydraulic lift rams (detachable)
    ripper        rear ripper (detachable)

Axes (MagicaVoxel, Z up):
    X = width   0..71    (machine's left is HIGH x, right is LOW x)
    Y = length  0..125   (front / blade is LOW y, rear / ripper is HIGH y)
    Z = height  0..71    (ground is z = 0)

Every part is modelled in that one shared grid, so nothing overlaps and
everything fits together.  Files written:

    bulldozer.vox           each model cropped tight to its own voxels and
                            placed with a scene-graph transform (named nodes).
                            Opens assembled in MagicaVoxel.
    bulldozer_samegrid.vox  every model uses the full grid with no offsets, for
                            importers that ignore the scene graph: drop all the
                            models at the same position and they line up.
    bulldozer_mounts.json   where each part sits and where the mounting points
                            are, in grid voxels, for hooking up in Unity.

Run:   python make_bulldozer_vox.py             (writes next to this script)
       python make_bulldozer_vox.py --preview   (also PNG previews)
       python make_bulldozer_vox.py --flat      (flat colours, no paint variation)
       python make_bulldozer_vox.py --dusty     (bake dust and mud onto the low parts)

The machine is clean by default, so dirt can be added and washed off in the game.
No third-party packages are needed.
"""

import argparse
import json
import math
import os
import struct

# ----------------------------------------------------------------------------
# Grid and palette
# ----------------------------------------------------------------------------
W, L, H = 72, 126, 72            # X, Y, Z size of the shared grid

PALETTE = {                      # colour index -> (r, g, b)
    1:  (246, 186, 6),           # yellow
    2:  (226, 152, 4),           # amber (shaded yellow)
    3:  (214, 122, 12),          # orange
    4:  (172, 92, 12),           # dark orange
    5:  (60, 62, 68),            # dark grey
    6:  (32, 33, 38),            # near black
    7:  (122, 126, 132),         # steel grey
    8:  (182, 186, 192),         # light steel
    9:  (30, 64, 82),            # window glass
    10: (64, 116, 140),          # glass highlight
    11: (255, 240, 190),         # lamp
    12: (206, 60, 30),           # red light
    13: (234, 172, 4),           # yellow, slightly worn
    14: (252, 202, 44),          # yellow, sun-bleached
    15: (198, 108, 10),          # orange, worn
    16: (74, 76, 82),            # dark grey, worn
    17: (178, 130, 74),          # dust
    18: (142, 98, 54),           # dried mud
}
(YEL, AMB, ORA, DOR, DGR, BLK, STL, LST, GLS, GHI, LAMP, RED,
 YEL2, YEL3, ORA2, DGR2, DUST, MUD) = range(1, 19)


def mirror(x):
    return W - 1 - x


class Part:
    """A named set of voxels in the shared grid: {(x, y, z): colour index}."""

    def __init__(self, name):
        self.name = name
        self.v = {}

    def set(self, x, y, z, c):
        if not (0 <= x < W and 0 <= y < L and 0 <= z < H):
            raise ValueError(f"{self.name}: voxel {(x, y, z)} is outside the grid")
        self.v[(x, y, z)] = c

    def set_sym(self, x, y, z, c):
        self.set(x, y, z, c)
        self.set(mirror(x), y, z, c)

    def box(self, x0, x1, y0, y1, z0, z1, c):
        """Solid box, all bounds inclusive."""
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    self.set(x, y, z, c)

    def box_sym(self, x0, x1, y0, y1, z0, z1, c):
        """Solid box plus its mirror image on the other side of the machine."""
        self.box(x0, x1, y0, y1, z0, z1, c)
        self.box(mirror(x1), mirror(x0), y0, y1, z0, z1, c)

    def remove_box(self, x0, x1, y0, y1, z0, z1):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    self.v.pop((x, y, z), None)

    def remove_sym(self, x0, x1, y0, y1, z0, z1):
        self.remove_box(x0, x1, y0, y1, z0, z1)
        self.remove_box(mirror(x1), mirror(x0), y0, y1, z0, z1)

    def recolour(self, x0, x1, y0, y1, z0, z1, c):
        """Change the colour of voxels that already exist in the box."""
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    if (x, y, z) in self.v:
                        self.v[(x, y, z)] = c

    def recolour_sym(self, x0, x1, y0, y1, z0, z1, c):
        self.recolour(x0, x1, y0, y1, z0, z1, c)
        self.recolour(mirror(x1), mirror(x0), y0, y1, z0, z1, c)

    def cyl_z(self, cx, cy, r, z0, z1, c):
        """Upright cylinder; cx, cy are the centre (can be .5)."""
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            for y in range(int(cy - r - 1), int(cy + r + 2)):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    for z in range(z0, z1 + 1):
                        self.set(x, y, z, c)

    def disc_x(self, x0, x1, cy, cz, r, c):
        """Cylinder lying across the machine (axis along X)."""
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for z in range(int(cz - r - 1), int(cz + r + 2)):
                if (y - cy) ** 2 + (z - cz) ** 2 <= r * r:
                    for x in range(x0, x1 + 1):
                        self.set(x, y, z, c)

    def disc_x_sym(self, x0, x1, cy, cz, r, c):
        self.disc_x(x0, x1, cy, cz, r, c)
        self.disc_x(mirror(x1), mirror(x0), cy, cz, r, c)

    def bounds(self):
        xs, ys, zs = zip(*self.v)
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


# ----------------------------------------------------------------------------
# Key positions shared between parts, so mounts always meet
# ----------------------------------------------------------------------------
TRACK_R_X = (6, 20)                               # right track x range (left is mirrored)
IDLER = (33.0, 12.0, 12.0)                        # front idler: y, z, radius of the track loop
SPROCKET = (88.0, 13.0, 13.0)                     # rear sprocket: y, z, radius of the track loop
TRUNNION = dict(y0=57, y1=62, z0=9, z1=14)        # cross bar the push arms pivot on
CHASSIS = dict(x0=21, x1=50, y0=24, y1=101)
DECK_Z = (27, 30)
HOOD = dict(x0=18, x1=53, y0=24, y1=58, z0=31, z1=53)
CAB = dict(x0=18, x1=53, y0=59, y1=89, z0=31)
TANK = dict(x0=15, x1=56, y0=90, y1=101, z0=31, z1=46)
RAM_X = (13, 16)                                  # right-hand lift ram (left is mirrored)
RAM_BRACKET = dict(x0=12, x1=17, y0=39, y1=44, z0=42, z1=55)
REAR_PLATE = dict(x0=24, x1=47, y0=102, y1=104, z0=9, z1=29)
EXHAUST = dict(cx=28.5, cy=41.5, r=3.0)
BLADE_BACK = 13                                   # y of the blade's back plate
BLADE_TOP = 32
BLADE_LUG_Y = (14, 17)


# ----------------------------------------------------------------------------
# Parts
# ----------------------------------------------------------------------------
def build_body():
    p = Part("body")
    c, h, t = CHASSIS, HOOD, TANK

    # chassis between the tracks, with belly plate and a tow eye at the front
    p.box(c["x0"], c["x1"], c["y0"], c["y1"], 6, 26, DOR)
    p.box(c["x0"], c["x1"], c["y0"], c["y1"], 6, 7, DGR)
    p.box(c["x0"], c["x1"], c["y0"], c["y0"], 8, 26, AMB)
    p.box(c["x0"], c["x1"], c["y0"], c["y0"], 8, 10, DOR)
    p.box(33, 38, c["y0"], c["y0"], 12, 17, DGR)
    p.box(35, 36, c["y0"], c["y0"], 14, 15, BLK)
    for x in range(c["x0"] + 2, c["x1"], 5):      # belly guard bolts
        p.set(x, c["y0"], 9, DGR)

    # trunnion cross bar: runs out through both tracks to the push arm pivots
    p.box(5, mirror(5), TRUNNION["y0"], TRUNNION["y1"], TRUNNION["z0"], TRUNNION["z1"], DGR)
    p.box_sym(5, 5, TRUNNION["y0"] + 2, TRUNNION["y1"] - 2, TRUNNION["z0"] + 2, TRUNNION["z1"] - 2, LST)

    # deck and fenders over the tracks
    p.box(h["x0"], h["x1"], 24, 37, DECK_Z[0], DECK_Z[1], YEL)
    p.box(6, mirror(6), 38, 101, DECK_Z[0], DECK_Z[1], YEL)
    p.box_sym(6, 6, 38, 101, DECK_Z[0], DECK_Z[1], AMB)            # fender edge
    p.box(6, mirror(6), 38, 38, DECK_Z[0], DECK_Z[0], AMB)
    for x in range(7, 18):                                          # tread plate
        for y in range(39, 101):
            if (x + y) % 3 == 0:
                p.set_sym(x, y, DECK_Z[1], AMB)

    # engine hood
    p.box(h["x0"], h["x1"], h["y0"], h["y1"], h["z0"], h["z1"], YEL)
    p.remove_sym(h["x0"], h["x0"] + 1, h["y0"], h["y1"], h["z1"], h["z1"])   # rounded top edges
    p.remove_sym(h["x0"], h["x0"], h["y0"], h["y1"], h["z1"] - 1, h["z1"] - 1)
    for y in (35, 47):                                              # panel seams across the top
        p.recolour(h["x0"], h["x1"], y, y, h["z1"] - 2, h["z1"], AMB)
    p.recolour(35, 36, h["y0"] + 3, h["y1"], h["z1"], h["z1"], YEL2)
    # side engine panels with louvres and a latch
    for x in (h["x0"], h["x1"]):
        p.box(x, x, 29, 55, 34, 48, ORA)
        for y in range(29, 56):
            for z in range(34, 49):
                if y in (29, 55, 46) or z in (34, 48):
                    p.set(x, y, z, DOR)
        for z in range(37, 46, 2):
            p.box(x, x, 32, 43, z, z, DGR)
        p.box(x, x, 49, 52, 41, 41, DGR)
        p.box(x, x, 49, 52, 37, 38, DOR)

    # radiator guard and grille
    p.box(h["x0"], h["x1"], 24, 26, DECK_Z[0], h["z1"] - 1, YEL)
    p.box(h["x0"] + 2, h["x1"] - 2, 24, 26, h["z1"], h["z1"], YEL)
    for x in range(22, 50):
        for z in range(31, 50):
            if x in (31, 40):
                col = YEL                                           # upright guard bars
            elif z % 3 == 0:
                col = DGR                                           # mesh bars
            else:
                col = BLK
            p.set(x, 24, z, col)
    p.box(21, 50, 24, 24, 30, 30, AMB)
    p.box(21, 50, 24, 24, 50, 50, AMB)
    p.box(32, 39, 24, 24, 51, 52, DGR)                              # badge plate
    p.box(34, 37, 24, 24, 51, 51, LST)
    p.box_sym(19, 20, 24, 24, 43, 48, DGR)                          # headlight housings
    p.box_sym(19, 20, 24, 24, 44, 47, LAMP)
    p.box_sym(19, 20, 24, 24, 39, 40, RED)                          # marker lights

    # rear tank behind the cab
    p.box(t["x0"], t["x1"], t["y0"], t["y1"], t["z0"], t["z1"], YEL)
    p.remove_sym(t["x0"], t["x0"], t["y0"], t["y1"], t["z1"], t["z1"])
    p.remove_box(t["x0"], t["x1"], t["y1"], t["y1"], t["z1"], t["z1"])
    for x in (t["x0"], t["x1"]):                                    # side panels
        p.box(x, x, 92, 99, 34, 43, ORA)
        for y in range(92, 100):
            for z in range(34, 44):
                if y in (92, 99) or z in (34, 43):
                    p.set(x, y, z, DOR)
    p.box(20, 51, t["y1"], t["y1"], 34, 43, AMB)                    # rear panel
    for z in range(35, 43, 2):
        p.box(28, 43, t["y1"], t["y1"], z, z, DGR)
    p.box_sym(17, 18, t["y1"], t["y1"], 40, 43, RED)                # tail lights
    p.box_sym(17, 18, t["y1"], t["y1"], 36, 38, LAMP)               # reversing lights
    p.box(22, 24, 94, 96, t["z1"] + 1, t["z1"] + 1, DGR)            # fuel cap
    p.set(23, 95, t["z1"] + 2, STL)

    # tool boxes on the fenders beside the cab, with grab rails
    p.box_sym(8, 16, 64, 86, 31, 38, YEL)
    p.box_sym(8, 16, 64, 86, 38, 38, AMB)
    p.box_sym(8, 8, 66, 84, 33, 36, ORA)
    p.box_sym(8, 8, 75, 75, 33, 36, DOR)
    p.box_sym(8, 8, 70, 71, 35, 35, DGR)
    p.box_sym(8, 8, 79, 80, 35, 35, DGR)
    for y in (65, 75, 85):
        p.box_sym(9, 9, y, y, 39, 44, DGR)
    p.box_sym(9, 9, 65, 85, 45, 45, DGR)

    # air pre-cleaner on the hood
    p.cyl_z(42.5, 48.5, 1.6, h["z1"] + 1, h["z1"] + 2, DGR)
    p.cyl_z(42.5, 48.5, 3.0, h["z1"] + 3, h["z1"] + 8, DGR)
    p.cyl_z(42.5, 48.5, 3.0, h["z1"] + 5, h["z1"] + 5, STL)
    p.cyl_z(42.5, 48.5, 2.1, h["z1"] + 9, h["z1"] + 9, STL)

    # ---- mounting points (dark grey so they read as hard points) ----
    # exhaust socket on the hood top
    p.cyl_z(EXHAUST["cx"], EXHAUST["cy"], EXHAUST["r"] + 1.0, h["z1"], h["z1"], DGR)
    # lift ram brackets on pedestals beside the hood
    b = RAM_BRACKET
    p.box_sym(b["x0"], b["x1"], b["y0"], b["y1"], 31, b["z0"] - 1, YEL)
    p.box_sym(b["x0"], b["x1"], b["y0"], b["y1"], 31, 32, AMB)
    p.box_sym(b["x0"], b["x1"], b["y0"], b["y1"], b["z0"], b["z1"], DGR)
    p.box_sym(b["x0"], b["x0"], b["y0"] + 2, b["y0"] + 3, b["z1"] - 5, b["z1"] - 4, LST)   # pin
    # rear attachment plate (ripper, or anything else, pins on here)
    r = REAR_PLATE
    p.box(r["x0"], r["x1"], r["y0"], r["y1"], r["z0"], r["z1"], DGR)
    for x in (r["x0"] + 2, r["x1"] - 3):
        for z in (r["z0"] + 2, r["z1"] - 3):
            p.box(x, x + 1, r["y1"], r["y1"], z, z + 1, LST)        # pin bosses
    for x in range(r["x0"] + 1, r["x1"], 4):
        p.set(x, r["y1"], (r["z0"] + r["z1"]) // 2, BLK)            # bolt row
    return p


def build_cab():
    p = Part("cab")
    x0, x1, y0, y1, z0 = CAB["x0"], CAB["x1"], CAB["y0"], CAB["y1"], CAB["z0"]
    wz0, wz1 = 41, 62                                # window band

    # base with door outlines
    p.box(x0, x1, y0, y1, z0, 40, YEL)
    p.box(x0, x1, y0, y1, z0, z0 + 1, AMB)
    for x in (x0, x1):
        for z in range(z0 + 2, 41):
            p.set(x, 62, z, DOR)
            p.set(x, 73, z, DOR)
        p.box(x, x, 62, 73, z0 + 2, z0 + 2, DOR)
        p.box(x, x, 70, 71, 38, 38, DGR)             # door handle
    # solid dark interior, then frames and glass on the outside
    p.box(x0, x1, y0, y1, wz0, wz1, BLK)

    def pane(setter, a, b):
        """Glass pane from a..b along a face, with a black gasket and streaks."""
        for u in range(a, b + 1):
            for z in range(wz0, wz1 + 1):
                if u in (a, b) or z in (wz0, wz1):
                    col = BLK
                elif (u - a) + (z - wz0) in (13, 14, 19) and wz0 + 3 < z < wz1 - 3:
                    col = GHI
                else:
                    col = GLS
                setter(u, z, col)

    for y in (y0, y1):                               # front and rear faces
        p.box(x0, x1, y, y, wz0, wz1, YEL)
        pane(lambda u, z, col, y=y: p.set(u, y, z, col), x0 + 3, x1 - 3)
    for x in (x0, x1):                               # side faces: door pane + rear pane
        p.box(x, x, y0, y1, wz0, wz1, YEL)
        pane(lambda u, z, col, x=x: p.set(x, u, z, col), y0 + 3, 73)
        pane(lambda u, z, col, x=x: p.set(x, u, z, col), 76, y1 - 3)
        p.box(x, x, 74, 75, wz0, wz1, BLK)           # door pillar
    for i in range(11):                              # wiper on the windscreen
        p.set(34 - i // 2, y0, wz0 + 1 + i, DGR)

    # header, roof with overhang, top cap, beacon
    p.box(x0, x1, y0, y1, 63, 65, YEL)
    p.box(x0, x1, y0, y1, 63, 63, AMB)
    p.box(x0 - 2, x1 + 2, y0 - 2, y1 + 2, 66, 69, YEL)
    for x in range(x0 - 2, x1 + 3):
        for y in range(y0 - 2, y1 + 3):
            if x in (x0 - 2, x1 + 2) or y in (y0 - 2, y1 + 2):
                p.set(x, y, 66, AMB)
    for x in (x0 - 2, x1 + 2):                       # clipped roof corners
        for y in (y0 - 2, y1 + 2):
            p.remove_box(x, x, y, y, 66, 69)
    p.remove_sym(x0 - 2, x0 - 2, y0 - 2, y1 + 2, 69, 69)
    p.box(x0 + 1, x1 - 1, y0 + 1, y1 - 1, 70, 70, YEL2)
    p.box(34, 37, 82, 85, 71, 71, ORA)               # beacon
    # work lights under the roof edge, front and rear
    for ya, yb, face in ((y0 - 4, y0 - 3, y0 - 4), (y1 + 3, y1 + 4, y1 + 4)):
        p.box_sym(21, 25, ya, yb, 66, 69, DGR)
        p.box_sym(22, 24, face, face, 67, 68, LAMP)
    return p


def build_exhaust():
    p = Part("exhaust")
    cx, cy, r = EXHAUST["cx"], EXHAUST["cy"], EXHAUST["r"]
    z = HOOD["z1"] + 1
    p.cyl_z(cx, cy, r, z, z + 1, STL)                # flange
    p.cyl_z(cx, cy, r, z + 2, z + 9, DGR)            # muffler
    p.cyl_z(cx, cy, r, z + 6, z + 6, BLK)
    p.cyl_z(cx, cy, r, z + 10, z + 10, STL)          # clamp
    p.cyl_z(cx, cy, 2.2, z + 11, z + 16, BLK)        # pipe
    # slanted tip
    for (x, y, zz) in list(p.v):
        if zz == z + 16 and y < cy:
            del p.v[(x, y, zz)]
        if zz == z + 15 and y < cy - 1:
            del p.v[(x, y, zz)]
    return p


def _track_colour(y, z):
    """Colour of the wheel-and-frame face inside the track loop."""
    sy, sz, _ = SPROCKET
    iy, iz, _ = IDLER
    dr = math.hypot(y - sy, z - sz)
    if dr <= 9.6:                                    # drive sprocket
        ang = math.atan2(z - sz, y - sy) + math.pi
        if dr > 7.4:
            return ORA if int(ang / (2 * math.pi) * 20) % 2 == 0 else BLK   # teeth
        if dr <= 1.2:
            return DGR
        if dr <= 2.8:
            return YEL
        if 4.4 <= dr <= 5.6 and int(ang / (2 * math.pi) * 16) % 2 == 0:
            return DGR                               # bolt circle
        return ORA
    if 55 <= y <= 64 and 7 <= z <= 16:
        return DGR                                   # collar round the trunnion bar
    if 40 <= y <= 78 and 9 <= z <= 16:               # roller frame
        if z in (9, 16):
            return AMB
        if y % 6 == 0 and z in (11, 14):
            return DGR
        return YEL
    di = math.hypot(y - iy, z - iz)
    if di <= 8.6:                                    # front idler
        if di > 6.6:
            return AMB
        if di <= 2.2:
            return YEL
        if abs(y - iy) < 1 or abs(z - iz) < 1:
            return AMB
        return DOR
    if 34 <= y <= 40 and 10 <= z <= 14:
        return YEL                                   # idler yoke
    for cy in (44, 51, 58, 65, 72):                  # bottom rollers
        d = math.hypot(y - cy, z - 6)
        if d <= 2.7:
            return YEL if d <= 1.2 else STL
    for cy in (52, 68):                              # carrier rollers
        d = math.hypot(y - cy, z - 21)
        if d <= 2.3:
            return YEL if d <= 1.0 else STL
    return BLK


def build_track(name, x0, x1):
    """Track loop with separate pads and grousers, 15 wide.  The wheels and
    frame sit 2 voxels in from each edge of the pads."""
    p = Part(name)
    (fy, fz, fr), (ry, rz, rr) = IDLER, SPROCKET
    seg_len2 = (ry - fy) ** 2 + (rz - fz) ** 2
    for y in range(int(fy - fr), int(ry + rr) + 1):
        for z in range(0, int(rz + rr) + 1):
            t = ((y - fy) * (ry - fy) + (z - fz) * (rz - fz)) / seg_len2
            tc = min(1.0, max(0.0, t))
            cy, cz, r = fy + tc * (ry - fy), fz + tc * (rz - fz), fr + tc * (rr - fr)
            d = r - math.hypot(y - cy, z - cz)       # depth in from the outside of the loop
            if d < 0:
                continue
            # distance along the loop, used to space the pads
            if t <= 0:
                s = math.atan2(z - fz, y - fy) * fr
            elif t >= 1:
                s = math.atan2(z - rz, y - ry) * rr
            else:
                s = y if z > cz else -y
            if d < 1.0:                              # grouser bars
                if int(math.floor(s / 2.0)) % 2:
                    continue
                for x in range(x0, x1 + 1):
                    p.set(x, y, z, DGR2 if x in (x0, x1) else DGR)
            elif d < 3.2:                            # pads
                col = DGR if int(math.floor(s / 4.0)) % 2 else BLK
                for x in range(x0, x1 + 1):
                    p.set(x, y, z, col)
            else:                                    # wheels and frame
                col = _track_colour(y, z)
                for x in range(x0 + 2, x1 - 1):
                    p.set(x, y, z, col)
    # hole where the body's trunnion bar passes through
    p.remove_box(x0, x1, TRUNNION["y0"], TRUNNION["y1"], TRUNNION["z0"], TRUNNION["z1"])
    return p


BLADE_SKIN = 4                                    # thickness of the curved blade plate


def blade_face(z):
    """How far back the blade's face sits at height z.  The cutting edge leads
    at the bottom, the middle is dished back, and the top lip curls forward."""
    return int(round(10 * (1 - ((z - 17) / 17.0) ** 2)))


def build_blade():
    p = Part("blade")
    lug_end = BLADE_LUG_Y[1]

    def back(z):
        return blade_face(z) + BLADE_SKIN - 1

    # curved plate: the same thickness all the way up, so the back curves too
    for z in range(0, BLADE_TOP + 1):
        front = blade_face(z)
        for x in range(2, W - 2):
            for y in range(front, back(z) + 1):
                if z < 3:
                    if y == front and z == 1 and x % 5 == 2:
                        col = BLK                    # cutting edge bolts
                    else:
                        col = STL                    # cutting edge
                elif y == back(z) or z >= BLADE_TOP - 1:
                    col = YEL
                elif y == front and z in (10, 20):
                    col = DOR                        # wear lines across the face
                elif y == front and z in (11, 21):
                    col = ORA2
                else:
                    col = ORA
                p.set(x, y, z, col)
    # end plates follow the curve and stick out in front of the face as wings
    for x in (0, 1, W - 2, W - 1):
        for z in range(0, BLADE_TOP + 1):
            wing = 5 if 4 <= z <= BLADE_TOP - 3 else 3
            for y in range(max(0, blade_face(z) - wing), back(z) + 1):
                p.set(x, y, z, LST if z < 3 else YEL)
        for z in range(5, BLADE_TOP - 3, 6):
            p.set(x, max(0, blade_face(z) - 5), z, AMB)
    # stiffening on the back: ribs fill the hollow of the curve
    rib_end = BLADE_LUG_Y[0] + 1
    for xa in (11, 23, 35, 47, 59):
        for z in range(2, BLADE_TOP - 1):
            for y in range(back(z) + 1, rib_end + 1):
                p.box(xa, xa + 1, y, y, z, z, AMB)
    for z0, z1 in ((26, 30), (12, 15)):               # top and middle beams
        for z in range(z0, z1 + 1):
            for y in range(back(z) + 1, back(z) + 3):
                p.box(2, W - 3, y, y, z, z, AMB if z == z0 else YEL)
    # lugs reach back from the curved plate to where the arms and rams pin on
    def lug(x0, x1, z0, z1):
        for z in range(z0, z1 + 1):
            for y in range(back(z) + 1, lug_end + 1):
                p.box_sym(x0, x1, y, y, z, z, DGR)

    lug(0, 5, 6, 17)                                  # push arm lugs, low and outside
    p.box_sym(0, 0, lug_end - 2, lug_end - 1, 10, 13, LST)
    lug(RAM_X[0] - 1, RAM_X[1] + 1, 17, 26)           # ram lugs, higher up
    p.box_sym(RAM_X[0] - 1, RAM_X[0] - 1, lug_end - 2, lug_end - 1, 20, 23, LST)
    return p


def build_blade_lift():
    p = Part("blade_lift")
    y_front = BLADE_LUG_Y[1] + 1
    ty = (TRUNNION["y0"] + TRUNNION["y1"] + 1) / 2 - 0.5
    tz = (TRUNNION["z0"] + TRUNNION["z1"] + 1) / 2 - 0.5
    # push arms, outside the tracks, from the blade lugs back to the trunnions
    p.box_sym(1, 4, y_front, 58, 9, 14, YEL)
    p.box_sym(1, 4, y_front, 58, 9, 9, AMB)
    p.box_sym(1, 1, y_front + 6, 50, 11, 12, AMB)                  # pressed channel
    for y in range(y_front + 8, 50, 8):
        p.set_sym(1, y, 13, DGR)                                   # bolts
    p.box_sym(0, 4, y_front, y_front + 3, 7, 16, DGR)              # clevis at the blade
    p.box_sym(0, 0, y_front + 1, y_front + 2, 10, 13, LST)
    p.disc_x_sym(0, 4, ty, tz, 6.6, YEL)                           # pivot boss
    p.disc_x_sym(0, 0, ty, tz, 6.6, AMB)
    p.disc_x_sym(0, 0, ty, tz, 3.2, DGR)                           # pin cap
    p.disc_x_sym(0, 0, ty, tz, 1.2, LST)
    # lift rams, from the blade's ram lugs up to the body brackets
    z_lo, z_hi = 21, 51
    y_hi = RAM_BRACKET["y0"] - 1
    for z in range(z_lo, z_hi + 1):
        yc = int(round(y_front + (z - z_lo) * (y_hi - y_front) / float(z_hi - z_lo)))
        if z >= 33:                                                # cylinder barrel
            col = DGR if z in (33, 34, z_hi) else (AMB if z % 6 == 0 else YEL)
            for y in range(max(y_front, yc - 1), min(y_hi, yc + 2) + 1):
                for x in range(RAM_X[0], RAM_X[1] + 1):
                    p.set_sym(x, y, z, col)
        else:                                                      # bright rod
            for y in range(max(y_front, yc), min(y_hi, yc + 1) + 1):
                for x in range(RAM_X[0] + 1, RAM_X[1]):
                    p.set_sym(x, y, z, LST)
    p.box_sym(RAM_X[0], RAM_X[1], y_front, y_front + 2, 19, 22, DGR)   # rod eye
    return p


def build_ripper():
    p = Part("ripper")
    y0 = REAR_PLATE["y1"] + 1                         # first row behind the body (105)
    # mounting ears against the plate, upper and lower links
    p.box_sym(24, 29, y0, y0 + 2, 9, 28, YEL)
    p.box_sym(24, 29, y0, y0 + 11, 23, 28, YEL)
    p.box_sym(24, 29, y0, y0 + 11, 23, 23, AMB)
    p.box_sym(24, 29, y0, y0 + 11, 9, 14, YEL)
    p.box_sym(24, 29, y0, y0 + 11, 9, 9, AMB)
    for z in (11, 25):
        p.box_sym(24, 24, y0 + 1, y0 + 2, z, z + 1, LST)           # pins at the body
        p.box_sym(24, 24, y0 + 9, y0 + 10, z, z + 1, DGR)          # pins at the beam
    # two rams between the links
    p.box_sym(31, 34, y0, y0 + 6, 17, 20, YEL)
    p.box_sym(31, 34, y0 + 6, y0 + 6, 17, 20, DGR)
    p.box_sym(32, 33, y0 + 7, y0 + 11, 18, 19, LST)
    # tool beam
    by0, by1 = y0 + 12, y0 + 17
    bx0, bx1 = 6, 65                                  # as wide as the outside of the tracks
    p.box(bx0, bx1, by0, by1, 7, 28, YEL)
    p.remove_box(bx0, bx1, by1, by1, 28, 28)
    p.remove_box(bx0, bx1, by1, by1, 7, 7)
    p.box(bx0, bx1, by0, by1, 7, 8, AMB)
    p.box(bx0 + 1, bx1 - 1, by1, by1, 15, 20, ORA)
    p.box(bx0 + 1, bx1 - 1, by1, by1, 15, 15, DOR)
    for x in range(bx0 + 2, bx1 - 1, 4):
        p.set(x, by1, 24, DGR)
        p.set(x, by1, 11, DGR)
    for x in (bx0, bx1):
        p.box(x, x, by0 + 1, by1 - 1, 10, 25, AMB)
    # three shanks: upright through the beam, curving forward to the tip
    lower = {5: (by1 + 0, by1 + 3), 4: (by1 - 1, by1 + 3), 3: (by1 - 3, by1 + 2),
             2: (by1 - 5, by1 + 0), 1: (by1 - 8, by1 - 3), 0: (by1 - 10, by1 - 6)}
    for sx in (10, 34, 58):
        p.box(sx - 1, sx + 4, by1 - 1, by1, 9, 26, DGR)            # shank holder
        p.box(sx, sx + 3, by1 + 1, by1 + 3, 6, 30, DGR)            # upright
        p.box(sx, sx + 3, by1 + 3, by1 + 3, 6, 30, DGR2)
        for z in (22, 27):
            p.box(sx + 1, sx + 2, by1 + 3, by1 + 3, z, z, LST)     # height pin holes
        for z, (ya, yb) in lower.items():
            p.box(sx, sx + 3, ya, yb, z, z, DGR)
        p.box(sx, sx + 3, by1 - 10, by1 - 9, 0, 0, LST)            # tip
        p.box(sx, sx + 3, by1 - 8, by1 - 8, 1, 1, LST)
    return p


# ----------------------------------------------------------------------------
# Paint wear and dust
# ----------------------------------------------------------------------------
def _rand(x, y, z, salt):
    n = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (salt * 2654435761)
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65536.0


WEAR = {            # base colour -> [(variant, chance), ...]
    YEL: [(YEL2, 0.16), (YEL3, 0.07)],
    AMB: [(YEL2, 0.10)],
    ORA: [(ORA2, 0.20)],
    DGR: [(DGR2, 0.20)],
    BLK: [(DGR, 0.06)],
}
DUSTING = {         # part -> (how much, up to what height)
    "track_left": (0.55, 26), "track_right": (0.55, 26), "blade": (0.45, 16),
    "ripper": (0.40, 12), "blade_lift": (0.18, 14), "body": (0.10, 30),
}
NO_DUST = (LAMP, RED, GLS, GHI, LST)


def weather(part, dusty=False):
    """Break up the flat colours a little; with dusty=True also dust the low parts."""
    strength, top = DUSTING.get(part.name, (0.0, 1)) if dusty else (0.0, 1)
    for (x, y, z), c in part.v.items():
        r = _rand(x, y, z, 1)
        if strength and c not in NO_DUST and r < strength * max(0.0, 1.0 - z / float(top)) ** 1.5:
            part.v[(x, y, z)] = DUST if _rand(x, y, z, 2) < 0.6 else MUD
            continue
        r = _rand(x, y, z, 3)
        for variant, chance in WEAR.get(c, ()):
            if r < chance:
                part.v[(x, y, z)] = variant
                break
            r -= chance


def build_all(flat=False, dusty=False):
    (rx0, rx1) = TRACK_R_X
    parts = [
        build_body(),
        build_cab(),
        build_exhaust(),
        build_track("track_left", mirror(rx1), mirror(rx0)),
        build_track("track_right", rx0, rx1),
        build_blade(),
        build_blade_lift(),
        build_ripper(),
    ]
    # no two parts may claim the same voxel
    seen = {}
    for part in parts:
        for pos in part.v:
            if pos in seen:
                raise AssertionError(f"{part.name} overlaps {seen[pos]} at {pos}")
            seen[pos] = part.name
    if not flat:
        for part in parts:
            weather(part, dusty=dusty)
    return parts


def mount_points():
    """Mounting points in grid voxels.  A point is the centre of the face where
    the attachment meets the part it mounts on (x, y, z, same axes as the grid)."""
    t, b, r = TRUNNION, RAM_BRACKET, REAR_PLATE
    ty = (t["y0"] + t["y1"] + 1) / 2
    tz = (t["z0"] + t["z1"] + 1) / 2
    by = BLADE_LUG_Y[1] + 1.0
    return {
        "push_arm_pivot_right": {"on": "body", "takes": "blade_lift", "at": [5.0, ty, tz],
                                 "note": "end of the trunnion bar; push arms pivot here"},
        "push_arm_pivot_left": {"on": "body", "takes": "blade_lift", "at": [W - 5.0, ty, tz],
                                "note": "end of the trunnion bar; push arms pivot here"},
        "lift_ram_right": {"on": "body", "takes": "blade_lift",
                           "at": [(RAM_X[0] + RAM_X[1] + 1) / 2, float(b["y0"]), b["z1"] - 4.0],
                           "note": "front face of the ram bracket"},
        "lift_ram_left": {"on": "body", "takes": "blade_lift",
                          "at": [W - (RAM_X[0] + RAM_X[1] + 1) / 2, float(b["y0"]), b["z1"] - 4.0],
                          "note": "front face of the ram bracket"},
        "rear_hitch": {"on": "body", "takes": "ripper",
                       "at": [(r["x0"] + r["x1"] + 1) / 2, r["y1"] + 1.0, (r["z0"] + r["z1"] + 1) / 2],
                       "note": "rear face of the attachment plate, 24 wide x 21 tall"},
        "exhaust_socket": {"on": "body", "takes": "exhaust",
                           "at": [EXHAUST["cx"] + 0.5, EXHAUST["cy"] + 0.5, HOOD["z1"] + 1.0],
                           "note": "top of the hood"},
        "cab_seat": {"on": "body", "takes": "cab",
                     "at": [W / 2.0, (CAB["y0"] + CAB["y1"] + 1) / 2, float(CAB["z0"])],
                     "note": "deck top under the cab, 36 wide x 31 long"},
        "blade_push_right": {"on": "blade", "takes": "blade_lift", "at": [3.0, by, 12.0],
                             "note": "back of the blade's lower lug"},
        "blade_push_left": {"on": "blade", "takes": "blade_lift", "at": [W - 3.0, by, 12.0],
                            "note": "back of the blade's lower lug"},
        "blade_ram_right": {"on": "blade", "takes": "blade_lift",
                            "at": [(RAM_X[0] + RAM_X[1] + 1) / 2, by, 21.5],
                            "note": "back of the blade's upper lug"},
        "blade_ram_left": {"on": "blade", "takes": "blade_lift",
                           "at": [W - (RAM_X[0] + RAM_X[1] + 1) / 2, by, 21.5],
                           "note": "back of the blade's upper lug"},
    }


# ----------------------------------------------------------------------------
# .vox writer
# ----------------------------------------------------------------------------
def _chunk(tag, content=b"", children=b""):
    return tag + struct.pack("<ii", len(content), len(children)) + content + children


def _string(s):
    data = s.encode("ascii")
    return struct.pack("<i", len(data)) + data


def _dict(d):
    out = struct.pack("<i", len(d))
    for k, v in d.items():
        out += _string(k) + _string(v)
    return out


WORLD_OFFSET = (-(W // 2), -(L // 2), 0)     # centres the machine, ground at z = 0


def write_vox(path, parts, same_grid=False):
    """Write parts as one multi-model .vox.

    same_grid=False: each model is cropped to its voxels and positioned by its
                     scene-graph transform.
    same_grid=True : every model is the whole grid, all at the same position.
    """
    body = b""
    translations = []
    for part in parts:
        if same_grid:
            lo, size = (0, 0, 0), (W, L, H)
        else:
            lo, hi = part.bounds()
            size = tuple(hi[i] - lo[i] + 1 for i in range(3))
        body += _chunk(b"SIZE", struct.pack("<iii", *size))
        vox = bytearray()
        for (x, y, z), c in sorted(part.v.items()):
            vox += bytes((x - lo[0], y - lo[1], z - lo[2], c))
        body += _chunk(b"XYZI", struct.pack("<i", len(part.v)) + bytes(vox))
        # MagicaVoxel puts a model's centre (size // 2) at the translation
        translations.append(tuple(lo[i] + size[i] // 2 + WORLD_OFFSET[i] for i in range(3)))

    # scene graph: root transform -> group -> (transform -> shape) per model
    child_ids = [2 + 2 * i for i in range(len(parts))]
    body += _chunk(b"nTRN", struct.pack("<i", 0) + _dict({"_name": "bulldozer"})
                   + struct.pack("<iiii", 1, -1, -1, 1) + _dict({}))
    body += _chunk(b"nGRP", struct.pack("<i", 1) + _dict({})
                   + struct.pack("<i", len(child_ids))
                   + b"".join(struct.pack("<i", c) for c in child_ids))
    for i, part in enumerate(parts):
        trn, shp = 2 + 2 * i, 3 + 2 * i
        t = "%d %d %d" % translations[i]
        body += _chunk(b"nTRN", struct.pack("<i", trn) + _dict({"_name": part.name})
                       + struct.pack("<iiii", shp, -1, 0, 1) + _dict({"_t": t}))
        body += _chunk(b"nSHP", struct.pack("<i", shp) + _dict({})
                       + struct.pack("<i", 1) + struct.pack("<i", i) + _dict({}))

    # palette: colour index i is stored in slot i - 1
    rgba = bytearray()
    for i in range(1, 257):
        r, g, b = PALETTE.get(i, (0, 0, 0))
        rgba += bytes((r, g, b, 255 if i < 256 else 0))
    body += _chunk(b"RGBA", bytes(rgba))

    with open(path, "wb") as f:
        f.write(b"VOX " + struct.pack("<i", 150) + _chunk(b"MAIN", b"", body))


def read_vox(path):
    """Minimal reader used to check what was written.  Returns a list of
    (name, translation, size, {(x, y, z): colour}) in the file's model order."""
    with open(path, "rb") as f:
        data = f.read()
    assert data[:4] == b"VOX "
    pos = 8 + 12                                   # header + MAIN chunk header
    sizes, models, names, trans = [], [], {}, {}

    def rd_string(buf, o):
        n = struct.unpack_from("<i", buf, o)[0]
        return buf[o + 4:o + 4 + n].decode("ascii"), o + 4 + n

    def rd_dict(buf, o):
        n = struct.unpack_from("<i", buf, o)[0]
        o += 4
        d = {}
        for _ in range(n):
            k, o = rd_string(buf, o)
            v, o = rd_string(buf, o)
            d[k] = v
        return d, o

    shape_of, model_of = {}, {}
    while pos < len(data):
        tag = data[pos:pos + 4]
        n, m = struct.unpack_from("<ii", data, pos + 4)
        c = data[pos + 12:pos + 12 + n]
        pos += 12 + n + m
        if tag == b"SIZE":
            sizes.append(struct.unpack("<iii", c))
        elif tag == b"XYZI":
            count = struct.unpack_from("<i", c)[0]
            models.append({(c[4 + 4 * i], c[5 + 4 * i], c[6 + 4 * i]): c[7 + 4 * i] for i in range(count)})
        elif tag == b"nTRN":
            nid = struct.unpack_from("<i", c)[0]
            attrs, o = rd_dict(c, 4)
            child = struct.unpack_from("<i", c, o)[0]
            frame, _ = rd_dict(c, o + 16)
            names[nid] = attrs.get("_name", "")
            trans[nid] = tuple(int(v) for v in frame.get("_t", "0 0 0").split())
            shape_of[child] = nid
        elif tag == b"nSHP":
            nid = struct.unpack_from("<i", c)[0]
            _, o = rd_dict(c, 4)
            model_of[nid] = struct.unpack_from("<i", c, o + 4)[0]
    out = [None] * len(models)
    for shp, mid in model_of.items():
        trn = shape_of[shp]
        out[mid] = (names[trn], trans[trn], sizes[mid], models[mid])
    return out


# ----------------------------------------------------------------------------
# Optional PNG preview (no extra packages needed)
# ----------------------------------------------------------------------------
def _write_png(path, width, height, pixels):
    """pixels: bytearray of RGB, row by row."""
    import zlib
    raw = b"".join(bytes(1) + bytes(pixels[y * width * 3:(y + 1) * width * 3]) for y in range(height))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(bytes((137, 80, 78, 71, 13, 10, 26, 10))
                + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def render_preview(path, parts, rear=False, explode=False, scale=6):
    """Simple angled picture of the machine, drawn back to front."""
    spread = {"blade": (0, -20, 0), "blade_lift": (0, -9, 26), "ripper": (0, 20, 0),
              "cab": (0, 0, 26), "exhaust": (0, 0, 44),
              "track_left": (20, 0, 0), "track_right": (-20, 0, 0)}
    vox = {}
    for part in parts:
        dx, dy, dz = spread.get(part.name, (0, 0, 0)) if explode else (0, 0, 0)
        for (x, y, z), c in part.v.items():
            x, y, z = x + dx, y + dy, z + dz
            if rear:                                # turn the machine half a turn
                x, y = -x, -y
            vox[(x, y, z)] = c

    def proj(x, y, z):                              # camera sits at +x, -y, +z
        return ((x + y) * scale * 0.866, (x - y) * scale * 0.5 - z * scale)

    xs = [p[0] for p in vox]
    ys = [p[1] for p in vox]
    zs = [p[2] for p in vox]
    corners = [proj(x, y, z) for x in (min(xs), max(xs) + 1) for y in (min(ys), max(ys) + 1)
               for z in (min(zs), max(zs) + 1)]
    minx, miny = min(p[0] for p in corners), min(p[1] for p in corners)
    maxx, maxy = max(p[0] for p in corners), max(p[1] for p in corners)
    pad = 20
    width, height = int(maxx - minx) + 2 * pad, int(maxy - miny) + 2 * pad
    pixels = bytearray(bytes((236, 238, 240)) * (width * height))

    def P(x, y, z):
        px, py = proj(x, y, z)
        return (px - minx + pad, py - miny + pad)

    def fill(poly, rgb):                            # convex polygon scanline fill
        ys_ = [p[1] for p in poly]
        for row in range(max(0, int(min(ys_))), min(height - 1, int(max(ys_))) + 1):
            yc = row + 0.5
            hits = []
            for i in range(len(poly)):
                (ax, ay), (bx, by) = poly[i], poly[(i + 1) % len(poly)]
                if (ay <= yc < by) or (by <= yc < ay):
                    hits.append(ax + (yc - ay) * (bx - ax) / (by - ay))
            if len(hits) >= 2:
                a, b = max(0, int(round(min(hits)))), min(width, int(round(max(hits))))
                if b > a:
                    pixels[(row * width + a) * 3:(row * width + b) * 3] = bytes(rgb) * (b - a)

    def shade(c, k):
        return tuple(int(v * k) for v in PALETTE[c])

    for (x, y, z) in sorted(vox, key=lambda p: (p[0] - p[1] + p[2], p[2])):
        c = vox[(x, y, z)]
        if (x, y, z + 1) not in vox:
            fill([P(x, y, z + 1), P(x + 1, y, z + 1), P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], shade(c, 1.0))
        if (x, y - 1, z) not in vox:
            fill([P(x, y, z), P(x + 1, y, z), P(x + 1, y, z + 1), P(x, y, z + 1)], shade(c, 0.84))
        if (x + 1, y, z) not in vox:
            fill([P(x + 1, y, z), P(x + 1, y + 1, z), P(x + 1, y + 1, z + 1), P(x + 1, y, z + 1)], shade(c, 0.68))
    _write_png(path, width, height, pixels)


# ----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Generate the voxel bulldozer .vox files.")
    ap.add_argument("--out", default=os.path.dirname(os.path.abspath(__file__)),
                    help="folder to write into (default: next to this script)")
    ap.add_argument("--preview", action="store_true", help="also write PNG previews")
    ap.add_argument("--flat", action="store_true", help="flat colours: no paint variation")
    ap.add_argument("--dusty", action="store_true", help="bake dust and mud onto the low parts")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    parts = build_all(flat=args.flat, dusty=args.dusty)

    main_path = os.path.join(args.out, "bulldozer.vox")
    grid_path = os.path.join(args.out, "bulldozer_samegrid.vox")
    write_vox(main_path, parts, same_grid=False)
    write_vox(grid_path, parts, same_grid=True)

    # read both files back and check they rebuild the same machine
    for path in (main_path, grid_path):
        back = read_vox(path)
        assert [m[0] for m in back] == [p.name for p in parts], "model names or order changed"
        for (name, t, size, voxels), part in zip(back, parts):
            lo = tuple(t[i] - size[i] // 2 - WORLD_OFFSET[i] for i in range(3))
            rebuilt = {(x + lo[0], y + lo[1], z + lo[2]): c for (x, y, z), c in voxels.items()}
            assert rebuilt == part.v, f"{name} did not read back the same from {path}"

    info = {
        "axes": "x = width (machine's left is high x), y = length (front is low y), z = up; units are voxels",
        "grid_size": [W, L, H],
        "world_offset_in_vox_file": list(WORLD_OFFSET),
        "parts": {},
        "mounts": mount_points(),
    }
    all_lo = [min(p.bounds()[0][i] for p in parts) for i in range(3)]
    all_hi = [max(p.bounds()[1][i] for p in parts) for i in range(3)]
    for p in parts:
        lo, hi = p.bounds()
        info["parts"][p.name] = {"min": list(lo), "size": [hi[i] - lo[i] + 1 for i in range(3)],
                                 "voxels": len(p.v)}
    with open(os.path.join(args.out, "bulldozer_mounts.json"), "w") as f:
        json.dump(info, f, indent=2)

    print("Whole machine: %d wide x %d long x %d tall" % tuple(all_hi[i] - all_lo[i] + 1 for i in range(3)))
    for p in parts:
        lo, hi = p.bounds()
        print("  %-12s %6d voxels   size %2d x %3d x %2d   min corner %s" % (
            p.name, len(p.v), hi[0] - lo[0] + 1, hi[1] - lo[1] + 1, hi[2] - lo[2] + 1, lo))
    print("Wrote", main_path)
    print("Wrote", grid_path)
    print("Both files read back and matched the parts. No part overlaps another.")

    if args.preview:
        for fname, kw in (("preview_front.png", {}), ("preview_rear.png", {"rear": True}),
                          ("preview_exploded.png", {"explode": True})):
            render_preview(os.path.join(args.out, fname), parts, **kw)
            print("Wrote", os.path.join(args.out, fname))


if __name__ == "__main__":
    main()
