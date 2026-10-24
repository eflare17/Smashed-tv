import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
"""The chickens' sounds (voxel_chickens.gd), made from noise and tones like sfx.py's:
    python3 -I godot/assets/voxel/tools/sfx_chickens.py
writes godot/assets/voxel/sound/: cluck_0..3 (a hen's "buk": a short nasal squawk), egg_song (laid one: "buk buk buk
ba-GAWK"), peep_0..1 (a chick's chirp), flap (wings beating), gate_creak, grain_pour (feed rattling into the
feeder), egg_pick (a little hollow tock), squawk_0..2 (hit: a loud panicked "BAWK!"), death_squawk (killed:
a last strangled squawk dying away). Owned by the voxel session."""


def buk(secs, f0, f1, bright=1.0):
    n = int(secs * SR)
    src = tone(np.linspace(f0, f1, n), secs, "saw") + noise(secs) * 0.25
    # two formants, nasal
    v = band(src, 500, 1100) * 1.0 + band(src, 1600, 2800) * 0.6 * bright
    return v * env(n, 0.006, secs * 0.6, 3)


def build_chickens():
    for v in range(4):
        f = 380 + 60 * v
        save("cluck_%d" % v, buk(0.12 + 0.02 * v, f * 1.15, f * 0.85), peak=0.6)
    song = np.zeros(int(1.3 * SR))
    for k, (o, s, f) in enumerate([(0.0, 0.1, 420), (0.18, 0.1, 430), (0.36, 0.1, 440), (0.55, 0.08, 470), (0.66, 0.4, 780)]):
        b = buk(s, f * 1.2, f * (0.7 if k == 4 else 0.9), 1.4 if k == 4 else 1.0)
        i = int(o * SR)
        song[i:i + len(b)] += b[:len(song) - i] * (1.4 if k == 4 else 1.0)
    save("egg_song", song, peak=0.65)
    for v in range(2):
        n = int(0.16 * SR)
        f = np.concatenate([np.linspace(3200 + 300 * v, 4200, n // 2), np.linspace(4200, 2800, n - n // 2)])
        save("peep_%d" % v, tone(f, 0.16) * env(n, 0.01, 0.1, 3), peak=0.4)
    n = int(0.45 * SR)
    beats = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 14 * t(0.45)))
    save("flap", band(noise(0.45), 300, 2500) * beats * env(n, 0.01, 0.35, 2), peak=0.6)
    n = int(0.7 * SR)
    creak = tone(np.linspace(240, 330, n) + 25 * np.sin(2 * np.pi * 37 * t(0.7)), 0.7, "saw")
    save("gate_creak", band(creak, 300, 2200) * env(n, 0.05, 0.6, 1.5), peak=0.5)
    out = np.zeros(int(0.8 * SR))
    for k in range(70):
        c = click(0.015, rng.uniform(2500, 6500), 0.002) * rng.uniform(0.2, 0.8)
        o = int(rng.uniform(0.0, 0.7) ** 1.4 * SR)
        out[o:o + len(c)] += c[:len(out) - o]
    save("grain_pour", out, peak=0.6)
    n = int(0.12 * SR)
    save("egg_pick", mix(tone(np.linspace(1500, 1100, n), 0.12) * env(n, 0.001, 0.05, 4), click(0.02, 3000, 0.002)), peak=0.5)
    # hit: a loud squawk, high and rising then breaking, with a flutter of wing noise under it
    for v in range(3):
        secs = 0.32 + 0.05 * v
        n = int(secs * SR)
        f = 620 + 70 * v
        sq = buk(secs, f * 1.1, f * 1.5, 1.8) * 1.2 + buk(secs, f * 2.0, f * 2.6, 1.0) * 0.4
        wob = 1.0 + 0.35 * np.sin(2 * np.pi * (22 + 3 * v) * t(secs))
        flut = band(noise(secs), 300, 2500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 16 * t(secs)))) * 0.25
        save("squawk_%d" % v, (sq * wob + flut) * env(n, 0.004, secs * 0.7, 2), peak=0.7)
    # killed: one last squawk, falling and dying away
    secs = 0.7
    n = int(secs * SR)
    sq = buk(secs, 820, 300, 1.6) * (1.0 + 0.4 * np.sin(2 * np.pi * 18 * t(secs)))
    save("death_squawk", sq * env(n, 0.004, 0.5, 2.5), peak=0.65)


if __name__ == "__main__":
    build_chickens()
