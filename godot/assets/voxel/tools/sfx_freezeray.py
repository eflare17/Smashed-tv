import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
# The freeze ray's sounds (voxel_weapon_freezeray.gd), made from tones and noise like sfx.py's:
#     python3 -I godot/assets/voxel/tools/sfx_freezeray.py
# writes godot/assets/voxel/sound/freezeray_*.wav: the beam's cold whine (a loop), its crackle on a body (a loop), its
# start and stop, the ice shard's zing as it leaves and its tink as it hits.

rng = np.random.default_rng(31)


def crackles(secs, n, lo, hi, q=0.003):
    """n little ice cracks scattered over secs (frost forming)."""
    out = np.zeros(int(secs * SR))
    for i in range(n):
        k = int(rng.uniform(0, len(out) - 600))
        c = click(0.02, rng.uniform(lo, hi), q) * rng.uniform(0.25, 1.0)
        out[k:k + len(c)] += c[:len(out) - k]
    return out


def glass(freqs, secs, decay):
    """Inharmonic bell partials, the higher dying quicker (ice, glass)."""
    out = np.zeros(int(secs * SR))
    for i, f in enumerate(freqs):
        out += tone(f, secs) * env(len(out), 0.0008, decay / (1 + i * 0.6), 5) / (1 + i * 0.35)
    return out


def build():
    # the beam: a high cold whine wavering over a low hum, a hiss of frost and crackle in it
    secs = 1.6
    x = t(secs)
    whine = tone(1250 + 18 * np.sin(2 * np.pi * 5.0 * x), secs) * 0.32 + tone(1875 + 25 * np.sin(2 * np.pi * 5.0 * x), secs) * 0.12
    hum = tone(110, secs) * 0.35 + tone(220, secs, "saw") * 0.06
    shimmer = tone(2500, secs) * 0.05 * (0.5 + 0.5 * np.sin(2 * np.pi * 7.5 * x))
    hiss = band(noise(secs), 3500, 9000) * 0.22 * (0.8 + 0.2 * np.sin(2 * np.pi * 2.5 * x))
    save("freezeray_loop", mix(whine, lowpass(hum, 900), shimmer, hiss, crackles(secs, 40, 3000, 7000) * 0.45), peak=0.5, loop=True)
    # on a body: frost crackling over it, thick and fast
    secs = 1.2
    fizz = band(noise(secs), 2500, 8000) * 0.18
    save("freezeray_crackle_loop", mix(fizz, crackles(secs, 90, 2000, 8000, 0.0025)), peak=0.45, loop=True)
    # start: a rising charge-up chirp and a puff of cold air
    n = int(0.32 * SR)
    chirp = tone(np.linspace(300, 1250, n), 0.32) * env(n, 0.03, 0.4, 2.5) * 0.6
    chirp2 = tone(np.linspace(450, 1875, n), 0.32) * env(n, 0.05, 0.4, 2.5) * 0.2
    puff = band(noise(0.32), 1500, 8000) * env(n, 0.04, 0.2, 3) * 0.5
    save("freezeray_start", mix(chirp, chirp2, puff, at(glass([2900, 4400], 0.2, 0.12) * 0.25, 0.2)), peak=0.6)
    # stop: the whine falling away, a hiss venting and a tinkle of frost
    n = int(0.45 * SR)
    fall = tone(np.linspace(1250, 260, n), 0.45) * env(n, 0.002, 0.35, 3) * 0.5
    vent = band(noise(0.45), 2000, 7000) * env(n, 0.01, 0.3, 3) * 0.45
    save("freezeray_stop", mix(fall, vent, at(crackles(0.3, 10, 3500, 7500), 0.05) * 0.4), peak=0.55)
    # the ice shard leaving: a crystalline zing (a bright glide and glassy partials) on a breathy fsst
    n = int(0.4 * SR)
    zing = tone(np.linspace(2600, 4800, n), 0.4) * env(n, 0.001, 0.22, 4) * 0.4
    ring = glass([3100, 4650, 6950, 8200], 0.4, 0.3) * 0.5
    fsst = band(noise(0.18), 3000, 10000) * env(int(0.18 * SR), 0.001, 0.09, 4) * 0.6
    thump = tone(np.linspace(240, 90, int(0.1 * SR)), 0.1) * env(int(0.1 * SR), 0.001, 0.06, 5) * 0.5
    save("freezeray_shard", mix(zing, ring, fsst, thump), peak=0.65)
    # a shard hitting: a sharp crack and a glassy tink, a few chips tinkling after
    crack = band(noise(0.05), 2500, 10000) * env(int(0.05 * SR), 0.0002, 0.015, 6)
    tink = glass([3700, 5300, 7400], 0.35, 0.18)
    chips = mix(*[at(glass([4200 + 700 * ((i * 3) % 5), 6100 + 500 * i], 0.12, 0.05) * (0.5 - 0.08 * i), 0.04 + 0.035 * i + 0.01 * (i % 2)) for i in range(5)])
    save("freezeray_tink", mix(crack, tink * 0.7, chips * 0.5), peak=0.6)


if __name__ == "__main__":
    build()
