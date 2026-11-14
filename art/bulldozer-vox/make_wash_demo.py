#!/usr/bin/env python3
"""
Writes wash-demo/dozer-data.js: the clean bulldozer's outside voxels, for the
pressure-wash example page (wash-demo/index.html).

Each outside voxel is 6 bytes: x, y, z, colour index, part index, face mask.
Face mask bits: 1 = +x, 2 = -x, 4 = +y, 8 = -y, 16 = +z, 32 = -z  (set = that face shows).

Run:   python make_wash_demo.py      then open wash-demo/index.html
"""

import base64
import json
import os

import make_bulldozer_vox as dozer

DIRS = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))


def main():
    parts = dozer.build_all()                    # clean machine, paint variation only
    solid = set()
    for part in parts:
        solid.update(part.v)

    data = bytearray()
    count = 0
    for pi, part in enumerate(parts):
        for (x, y, z), c in part.v.items():
            mask = 0
            for bit, (dx, dy, dz) in enumerate(DIRS):
                if (x + dx, y + dy, z + dz) not in solid:
                    mask |= 1 << bit
            if mask:
                data += bytes((x, y, z, c, pi, mask))
                count += 1

    palette = [[0, 0, 0]] + [list(dozer.PALETTE[i]) for i in range(1, max(dozer.PALETTE) + 1)]
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wash-demo")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "dozer-data.js")
    with open(path, "w") as f:
        f.write("window.DOZER = " + json.dumps({
            "size": [dozer.W, dozer.L, dozer.H],
            "count": count,
            "parts": [p.name for p in parts],
            "palette": palette,
            "b64": base64.b64encode(bytes(data)).decode("ascii"),
        }) + ";\n")
    print("Wrote %s  (%d outside voxels of %d)" % (path, count, len(solid)))


if __name__ == "__main__":
    main()
