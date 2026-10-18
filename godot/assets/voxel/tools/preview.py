"""Quick look at a built character without Godot: python3 preview.py jared out.png [style]"""
import json, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vox_build import read_vox, OUT

def model_points(char, style="classic", extra=()):
    rig = json.load(open(os.path.join(OUT, char, "rig.json")))
    pts = []; cols = []
    for p in rig["parts"]:
        if p.get("group") == "hair" and p.get("style") != style:
            continue
        vox, size = read_vox(os.path.join(OUT, char, p["file"]))
        ox, oy, oz = p["origin"]; sx, sy, sz = size
        for (vx, vy, vz), c in vox.items():
            pts.append((ox + vx, oy + vz, oz + (sy - 1 - vy))); cols.append(c)
    return np.array(pts, float) + 0.5, np.array(cols, float)

def render(pts, cols, yaw, pitch, s=3, W=None):
    a, b = np.radians(yaw), np.radians(pitch)
    # turn the model by yaw round y, then look down by pitch (camera on +z)
    x = pts[:,0]*np.cos(a) + pts[:,2]*np.sin(a)
    z = -pts[:,0]*np.sin(a) + pts[:,2]*np.cos(a)
    y = pts[:,1]
    sy_ = y*np.cos(b) + z*np.sin(b)
    depth = z*np.cos(b) - y*np.sin(b)
    X = ((x - x.min()) * s).astype(int) + 4; Y = ((sy_.max() - sy_) * s).astype(int) + 4
    w = X.max() + s + 8; h = Y.max() + s + 8
    img = np.zeros((h, w, 3)) + (90, 140, 90); zb = np.full((h, w), -1e9)
    order = np.argsort(depth)
    shade = 1.0
    for i in order:
        pass
    X = X[order]; Y = Y[order]; D = depth[order]; C = cols[order]
    for dx in range(s):
        for dy in range(s):
            img[Y+dy, X+dx] = C
    return img.astype(np.uint8)

if __name__ == "__main__":
    char, out = sys.argv[1], sys.argv[2]
    style = sys.argv[3] if len(sys.argv) > 3 else "classic"
    pts, cols = model_points(char, style)
    views = [render(pts, cols, 0, 0), render(pts, cols, 90, 0), render(pts, cols, 180, 0), render(pts, cols, -90, 0),
             render(pts, cols, 30, 25), render(pts, cols, 0, 65)]
    H = max(v.shape[0] for v in views); W = sum(v.shape[1] for v in views)
    o = np.zeros((H, W, 3), np.uint8) + np.array([90,140,90], np.uint8); x = 0
    for v in views:
        o[:v.shape[0], x:x+v.shape[1]] = v; x += v.shape[1]
    Image.fromarray(o).save(out)
