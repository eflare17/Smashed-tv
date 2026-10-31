"""Stylized ibis figurine, built from blended signed-distance primitives.

Usage: python3 make_ibis.py [--res 0.4] [--height-in 6]
Writes ibis.stl next to this script. Units are millimetres; +x is the
direction the bird faces, +z is up, base sits on z = 0.
Needs: numpy, scikit-image, trimesh, fast-simplification.
"""
import argparse
import os

import numpy as np
from skimage import measure
import trimesh


# ---------------------------------------------------------------- SDF helpers
def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax_sub(a, b, k):
    """Smooth subtraction: a minus b."""
    h = np.clip(0.5 - 0.5 * (b + a) / k, 0.0, 1.0)
    return a * (1 - h) + (-b) * h + k * h * (1 - h)


def frame(pitch_deg=0.0, yaw_deg=0.0, roll_deg=0.0):
    """Rotation matrix whose columns are the local forward/side/up axes."""
    p, y, r = np.radians([pitch_deg, yaw_deg, roll_deg])
    ry = np.array([[np.cos(p), 0, -np.sin(p)], [0, 1, 0], [np.sin(p), 0, np.cos(p)]])
    rz = np.array([[np.cos(y), -np.sin(y), 0], [np.sin(y), np.cos(y), 0], [0, 0, 1]])
    rx = np.array([[1, 0, 0], [0, np.cos(r), -np.sin(r)], [0, np.sin(r), np.cos(r)]])
    return rz @ ry @ rx


def sd_ellipsoid(X, Y, Z, c, radii, rot=None):
    dx, dy, dz = X - c[0], Y - c[1], Z - c[2]
    if rot is not None:
        dx, dy, dz = (dx * rot[0, 0] + dy * rot[1, 0] + dz * rot[2, 0],
                      dx * rot[0, 1] + dy * rot[1, 1] + dz * rot[2, 1],
                      dx * rot[0, 2] + dy * rot[1, 2] + dz * rot[2, 2])
    rx, ry, rz = radii
    k0 = np.sqrt((dx / rx) ** 2 + (dy / ry) ** 2 + (dz / rz) ** 2)
    k1 = np.sqrt((dx / rx ** 2) ** 2 + (dy / ry ** 2) ** 2 + (dz / rz ** 2) ** 2)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_round_cone(X, Y, Z, a, b, r1, r2):
    """Tapered capsule from a (radius r1) to b (radius r2)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ba = b - a
    l2 = ba @ ba
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pax, pay, paz = X - a[0], Y - a[1], Z - a[2]
    y = pax * ba[0] + pay * ba[1] + paz * ba[2]
    z = y - l2
    qx, qy, qz = pax * l2 - ba[0] * y, pay * l2 - ba[1] * y, paz * l2 - ba[2] * y
    x2 = qx * qx + qy * qy + qz * qz
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    d_mid = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + y * rr) * il2 - r1
    d = np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - r1, d_mid)
    return np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - r2, d)


def sd_base(X, Y, Z, c, rx, ry, h, edge):
    """Elliptical slab from z=0 to z=h with rounded top edge."""
    dx, dy = (X - c[0]) / rx, (Y - c[1]) / ry
    d2 = (np.sqrt(dx * dx + dy * dy) - 1.0) * min(rx, ry) + edge
    dz = np.abs(Z - h / 2) - h / 2 + edge
    out = np.sqrt(np.maximum(d2, 0) ** 2 + np.maximum(dz, 0) ** 2)
    return out + np.minimum(np.maximum(d2, dz), 0) - edge


def bezier(p0, p1, p2, p3, n):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2, p3 = (np.asarray(p, float) for p in (p0, p1, p2, p3))
    return ((1 - t) ** 3) * p0 + 3 * ((1 - t) ** 2) * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3


# ------------------------------------------------------------- field builder
class Field:
    """Dense SDF grid. Each primitive is evaluated only inside its bounding box
    (padded by the blend radius), which keeps the build fast."""

    def __init__(self, lo, hi, res):
        self.res = res
        self.lo = np.asarray(lo, float)
        self.axes = [np.arange(l, h + res, res) for l, h in zip(lo, hi)]
        self.F = np.full([len(a) for a in self.axes], 1e3, dtype=np.float32)

    def _slices(self, bmin, bmax):
        sl = []
        for ax, mn, mx in zip(self.axes, bmin, bmax):
            i0 = max(int(np.searchsorted(ax, mn)) - 1, 0)
            i1 = min(int(np.searchsorted(ax, mx)) + 1, len(ax))
            sl.append(slice(i0, i1))
        return tuple(sl)

    def apply(self, fn, bmin, bmax, k=0.0, op="union"):
        pad = k + 2 * self.res
        sl = self._slices(np.asarray(bmin) - pad, np.asarray(bmax) + pad)
        X, Y, Z = np.meshgrid(*(ax[s] for ax, s in zip(self.axes, sl)), indexing="ij")
        d = fn(X, Y, Z).astype(np.float32)
        if op == "union":
            self.F[sl] = smin(self.F[sl], d, k)
        else:
            self.F[sl] = smax_sub(self.F[sl], d, k)

    # convenience wrappers ---------------------------------------------------
    def ellipsoid(self, c, radii, rot=None, k=0.0, op="union"):
        r = max(radii)
        self.apply(lambda X, Y, Z: sd_ellipsoid(X, Y, Z, c, radii, rot),
                   np.subtract(c, r), np.add(c, r), k, op)

    def cone(self, a, b, r1, r2, k=0.0, op="union"):
        r = max(r1, r2)
        bmin = np.minimum(a, b) - r
        bmax = np.maximum(a, b) + r
        self.apply(lambda X, Y, Z: sd_round_cone(X, Y, Z, a, b, r1, r2), bmin, bmax, k, op)

    def tube(self, pts, r0, r1, k=0.0, seg_k=None):
        """Chain of tapered capsules along a polyline, radius r0 -> r1."""
        radii = np.linspace(r0, r1, len(pts))
        for i in range(len(pts) - 1):
            self.cone(pts[i], pts[i + 1], radii[i], radii[i + 1],
                      k if i == 0 else (seg_k if seg_k is not None else 0.0))


def build(res):
    f = Field(lo=(-72, -40, -1), hi=(92, 40, 160), res=res)

    # --- base -----------------------------------------------------------------
    f.apply(lambda X, Y, Z: sd_base(X, Y, Z, (2, 0), 46, 32, 5.0, 1.6),
            (-46, -34, -1), (50, 34, 6))

    # --- feet: three forward toes + one hind toe per foot, resting on base ---
    feet = [((5.0, 7.5), 8.0), ((-7.0, -7.5), -6.0)]  # (ankle xy, yaw deg)
    for (fx, fy), yaw in feet:
        ankle = np.array([fx, fy, 8.0])
        for a in (-32, 0, 32):
            ang = np.radians(a + yaw)
            tip = np.array([fx + 19 * np.cos(ang), fy + 19 * np.sin(ang), 5.6])
            mid = (ankle + tip) / 2 + np.array([0, 0, 1.2])
            f.cone(ankle, mid, 2.6, 2.1, k=1.0)
            f.cone(mid, tip, 2.1, 1.5, k=0.6)
        ang = np.radians(180 + yaw)
        f.cone(ankle, (fx + 9 * np.cos(ang), fy + 9 * np.sin(ang), 5.8), 2.4, 1.6, k=1.0)
        # small rounded pad blending the toes into the base
        f.ellipsoid((fx, fy, 6.0), (5.5, 4.5, 2.6), k=1.5)

    # --- legs -----------------------------------------------------------------
    for (fx, fy), _ in feet:
        heel = np.array([fx - 3.0, fy * 0.9, 50.0])
        hip = np.array([fx - 6.0, fy * 0.8, 70.0])
        f.cone((fx, fy, 8.0), heel, 2.9, 3.2, k=1.0)        # tarsus
        f.ellipsoid(heel, (4.2, 3.8, 4.4), k=1.2)          # heel joint
        f.cone(heel, hip, 3.6, 7.5, k=2.0)                 # feathered thigh

    # --- body -----------------------------------------------------------------
    f.ellipsoid((0, 0, 81), (36, 17, 21), frame(pitch_deg=16), k=4.0)
    f.ellipsoid((19, 0, 83), (17, 14, 17), frame(pitch_deg=30), k=8.0)   # breast
    f.ellipsoid((-6, 0, 73), (24, 13, 12), frame(pitch_deg=10), k=6.0)   # belly

    # --- wings: three stacked feather layers per side for a carved look -------
    for s in (1, -1):
        f.ellipsoid((10, s * 12.5, 89), (19, 5.5, 12.5), frame(14, -s * 6, s * 4), k=0.8)
        f.ellipsoid((-4, s * 13.5, 86), (27, 5.5, 13.5), frame(12, -s * 4, s * 3), k=0.8)
        f.ellipsoid((-20, s * 11.5, 82), (31, 4.8, 10.5), frame(17, s * 2, s * 2), k=0.8)

    # --- drooping tail plumes (stylized take on the ibis' shaggy tertials) ----
    for y0, drop, r1 in ((-7.5, 0, 4.0), (-3.8, 2, 4.4), (0, 3.5, 4.6), (3.8, 2, 4.4), (7.5, 0, 4.0)):
        pts = bezier((-22, y0 * 0.8, 85), (-38, y0, 83), (-52, y0 * 1.05, 75 - drop),
                     (-61, y0 * 1.1, 65 - drop), 20)
        f.tube(pts, r1, 1.4, k=1.4)

    # --- neck -----------------------------------------------------------------
    neck = bezier((22, 0, 90), (38, 0, 108), (17, 0, 120), (27, 0, 133), 36)
    f.tube(neck, 9.5, 6.2, k=4.0)

    # --- head -----------------------------------------------------------------
    f.ellipsoid((30, 0, 137), (11.5, 8.2, 9.5), frame(pitch_deg=-8), k=3.0)

    # --- beak: long down-curved taper -----------------------------------------
    beak = bezier((37, 0, 137), (57, 0, 136), (72, 0, 125), (80, 0, 102), 40)
    f.tube(beak, 4.4, 1.25, k=2.5)

    # --- eyes: shallow sockets with a domed eye inside -------------------------
    for s in (1, -1):
        f.ellipsoid((34.5, s * 7.6, 139.5), (2.6, 1.6, 2.6), k=0.6, op="sub")
        f.ellipsoid((34.5, s * 6.9, 139.5), (1.7, 1.2, 1.7), k=0.3)

    return f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--res", type=float, default=0.4, help="voxel size in mm")
    ap.add_argument("--height-in", type=float, default=6.0)
    ap.add_argument("--faces", type=int, default=300_000, help="target triangle count")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "ibis.stl"))
    args = ap.parse_args()

    f = build(args.res)
    verts, faces, _, _ = measure.marching_cubes(f.F, level=0.013,  # offset avoids exact zeros on grid planes
                                           spacing=(args.res,) * 3)
    verts += f.lo
    mesh = trimesh.Trimesh(verts, faces, process=True)
    mesh = max(mesh.split(only_watertight=False), key=lambda m: len(m.faces))

    if len(mesh.faces) > args.faces:
        import fast_simplification
        v, fc = fast_simplification.simplify(mesh.vertices, mesh.faces,
                                             1 - args.faces / len(mesh.faces))
        mesh = trimesh.Trimesh(v, fc, process=True)

    trimesh.repair.fix_normals(mesh)
    mesh.apply_translation(-mesh.bounds[0] * [0, 0, 1])
    mesh.apply_scale(args.height_in * 25.4 / mesh.extents[2])
    lo, hi = mesh.bounds
    mesh.apply_translation([-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]])

    mesh.export(args.out)
    print(f"wrote {args.out}")
    print(f"  size (mm): {mesh.extents.round(1)}  faces: {len(mesh.faces)}"
          f"  watertight: {mesh.is_watertight}  volume: {mesh.volume / 1000:.1f} cm^3")


if __name__ == "__main__":
    main()
