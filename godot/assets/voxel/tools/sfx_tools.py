import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
"""The digging tools' sounds (voxel_tool.gd), made from noise and tones like sfx.py's:
    python3 -I godot/assets/voxel/tools/sfx_tools.py
writes godot/assets/voxel/sound/: dig_dirt_0..2 (a shovel biting into earth: a crunchy thud and the soil sliding),
dig_stone_0..1 (the pick on stone: a bright clink and chips), dig_scrape (the rusty shovel slipping), dig_clang (the
shovel on stone it can't cut: a ringing clang), gold_find (a happy little chime), worm_find (a wet squelch). Owned by
the voxel session."""


def build_tools():
    for v in range(3):
        n = int(0.4 * SR)
        thud = tone(np.linspace(140 - 15 * v, 60, n), 0.4) * env(n, 0.001, 0.12, 4)
        crunch = band(noise(0.4), 400 + 100 * v, 3000) * env(n, 0.001, 0.08, 4)
        slide = lowpass(noise(0.4), np.linspace(2000, 300, n)) * env(n, 0.03, 0.25, 2)
        save("dig_dirt_%d" % v, mix(thud * 1.1, crunch * 1.3, at(slide * 0.7, 0.04, 0.4)), peak=0.8)
    for v in range(2):
        clink = metal([2600 + 300 * v, 4100, 6300], 0.35, 0.12)
        chips = np.zeros(int(0.35 * SR))
        for k in range(6):
            c = click(0.02, rng.uniform(3000, 6000), 0.003) * rng.uniform(0.3, 0.7)
            o = int(rng.uniform(0.01, 0.2) * SR)
            chips[o:o + len(c)] += c[:len(chips) - o]
        save("dig_stone_%d" % v, mix(clink * 0.9, click(0.03, 2200, 0.004) * 1.4, chips), peak=0.8)
    n = int(0.3 * SR)
    save("dig_scrape", band(noise(0.3), 900, 4500) * env(n, 0.01, 0.2, 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 45 * t(0.3))), peak=0.6)
    save("dig_clang", mix(metal([620, 1470, 2380, 3500], 0.9, 0.5), click(0.03, 2000, 0.005) * 1.5), peak=0.85)
    notes = [988, 1319, 1976]
    chime = np.zeros(int(0.7 * SR))
    for k, f in enumerate(notes):
        nn = tone(f, 0.5) * env(int(0.5 * SR), 0.003, 0.35, 4) + tone(f * 2, 0.5) * env(int(0.5 * SR), 0.003, 0.2, 4) * 0.3
        o = int(k * 0.08 * SR)
        chime[o:o + len(nn)] += nn[:len(chime) - o]
    save("gold_find", chime, peak=0.6)
    n = int(0.3 * SR)
    wob = 0.5 + 0.5 * np.sin(2 * np.pi * np.linspace(18, 7, n) * t(0.3))
    save("worm_find", band(noise(0.3), 200, 1500) * wob * env(n, 0.005, 0.18, 3), peak=0.6)


if __name__ == "__main__":
    build_tools()
