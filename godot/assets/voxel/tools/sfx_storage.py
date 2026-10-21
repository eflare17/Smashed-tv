import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
"""The chests', cabinets' and backpack's sounds (voxel_storage.gd, voxel_inventory_ui.gd), made from noise and tones
like sfx.py's:
    python3 -I godot/assets/voxel/tools/sfx_storage.py
writes godot/assets/voxel/sound/: chest_open_0..1 (a wooden lid creaking up on old hinges), chest_close (the lid
dropping shut, a hollow wooden knock), cabinet_open (a steel door unlatched and swung, a tinny rattle), cabinet_close
(the door slammed into its latch), item_pick and item_put (a soft cloth-and-cube tick taking a stack up and setting it
down), bag_open (a zip and a rustle). Owned by the voxel session."""


def creak(secs, f0, f1, wob):
    """An old hinge: a scraping tone wandering between f0 and f1, rough with noise."""
    n = int(secs * SR)
    x = np.linspace(0, 1, n)
    f = f0 + (f1 - f0) * x + wob * np.sin(2 * np.pi * 3.3 * x * secs) * (1 - x)
    saw = tone(f, secs, "saw")
    rough = band(noise(secs), 600, 3000) * 0.35
    return band(saw + rough, 300, 3500) * env(n, 0.04, secs * 0.7, 2.5)


def knock(secs, f, decay):
    """Hollow wood: a low tone and a short band of noise."""
    n = int(secs * SR)
    return tone(f, secs) * env(n, 0.0006, decay, 5) + band(noise(secs), f * 2, f * 8) * env(n, 0.0004, decay * 0.3, 6)


def build_storage():
    for v in range(2):
        save("chest_open_%d" % v, mix(creak(0.55, 520 + 90 * v, 380 + 60 * v, 70) * 0.9, at(knock(0.25, 180, 0.08) * 0.5, 0.0)), peak=0.7)
    save("chest_close", mix(knock(0.5, 140, 0.18) * 1.4, at(knock(0.2, 260, 0.05) * 0.5, 0.018), lowpass(noise(0.3), 700) * env(int(0.3 * SR), 0.001, 0.08, 4) * 0.6), peak=0.85)
    door = metal([410, 1130, 2270, 3410], 0.6, 0.35) * 0.5
    latch = click(0.04, 3200, 0.006)
    save("cabinet_open", mix(at(latch, 0.0), at(door * 0.7, 0.03), at(creak(0.4, 900, 700, 40) * 0.4, 0.05)), peak=0.7)
    save("cabinet_close", mix(metal([300, 860, 1900, 2950], 0.7, 0.4) * 0.9, at(click(0.05, 2600, 0.008) * 1.2, 0.006),
                               lowpass(noise(0.15), 1200) * env(int(0.15 * SR), 0.0005, 0.04, 5)), peak=0.85)
    tick = lambda f: band(noise(0.05), f * 0.6, f * 1.6) * env(int(0.05 * SR), 0.0004, 0.012, 6)
    save("item_pick", mix(tick(2400), at(tick(3300) * 0.6, 0.025), lowpass(noise(0.08), 1500) * env(int(0.08 * SR), 0.002, 0.03, 4) * 0.4), peak=0.55)
    save("item_put", mix(tick(1600), at(tick(1100) * 0.7, 0.02), lowpass(noise(0.1), 900) * env(int(0.1 * SR), 0.002, 0.04, 4) * 0.5), peak=0.55)
    n = int(0.35 * SR)
    zipper = band(noise(0.35), 2500, 7000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * np.linspace(60, 140, n) * t(0.35)))) * env(n, 0.01, 0.3, 2)
    save("bag_open", mix(zipper * 0.8, at(lowpass(noise(0.3), 1800) * env(int(0.3 * SR), 0.02, 0.15, 3) * 0.5, 0.15)), peak=0.5)


if __name__ == "__main__":
    build_storage()
