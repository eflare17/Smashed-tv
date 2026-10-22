#!/usr/bin/env python3
# The trailer: the first frame of every shot in the rendered frames (dir of f<n>.png), printed as indices. Owned by the voxel session.
# the first frame of every shot in the AVI (where the picture changes most, near each cut): printed as indices
import sys
import numpy as np
from PIL import Image
fr = sys.argv[1]
starts = [6, 7, 10, 11, 14, 15, 18, 19, 20, 22, 24, 26, 28, 30, 31, 32, 33, 34, 35, 36, 37, 38.5, 39, 41, 44, 46.5, 48.5, 52.5]
def img(k):
    return np.asarray(Image.open(f"{fr}/f{k}.png").convert("L"), dtype=float)
out = []
for s in starts:
    f = int(round(60 + s * 30 - 1))
    best, bk = -1, f
    for k in range(f - 1, f + 3):
        d = np.abs(img(k) - img(k - 1)).mean()
        if d > best:
            best, bk = d, k
    out.append(bk)
print(" ".join(str(k) for k in out))
