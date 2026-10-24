import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
"""The barbecue's sounds (voxel_barbecue.gd), made from noise and tones like sfx.py's:
    python3 -I godot/assets/voxel/tools/sfx_barbecue.py
writes godot/assets/voxel/sound/: sizzle (a loop: fat spitting on the hot plate, a soft roar of gas under it),
bbq_light (the burner catching: a click, then a whoomp), bbq_tongs (a chicken turned or lifted: a metal scrape).
Owned by the voxel session."""


def build_barbecue():
    secs = 2.0
    n = int(secs * SR)
    hiss = band(noise(secs), 2500, 9000) * 0.25
    roar = band(noise(secs), 120, 700) * 0.18
    out = hiss + roar
    for k in range(260):
        c = click(rng.uniform(0.003, 0.012), rng.uniform(2500, 8000), 0.0015) * rng.uniform(0.15, 0.9)
        o = int(rng.uniform(0.0, secs - 0.02) * SR)
        out[o:o + len(c)] += c[:n - o]
    save("sizzle", out, peak=0.5, loop=True)
    secs = 0.7
    n = int(secs * SR)
    whoomp = lowpass(noise(secs), 500) * env(n, 0.03, 0.45, 2) * 2.0
    save("bbq_light", mix(click(0.02, 3200, 0.002), at(whoomp, 0.06, secs)), peak=0.6)
    secs = 0.25
    n = int(secs * SR)
    save("bbq_tongs", band(noise(secs), 1800, 6000) * env(n, 0.01, 0.2, 2) + metal([2100, 3400], secs, 0.12) * 0.3, peak=0.45)


if __name__ == "__main__":
    build_barbecue()
