import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
# The laser cutter's sounds (voxel_weapon_laser.gd), made like sfx.py's from tones and noise:
#     python3 -I godot/assets/voxel/tools/sfx_laser.py
# writes godot/assets/voxel/sound/laser_*.wav. Owned by the voxel session.


def buzz(f0, secs, hum=100.0):
    """An electric whine: a thin saw tone at f0 wavering a little, chopped by a mains hum."""
    x = t(secs)
    f = f0 * (1 + 0.004 * np.sin(2 * np.pi * 5.0 * x))
    w = tone(f, secs, "saw") * 0.5 + tone(f * 2.003, secs) * 0.25 + tone(f * 0.5, secs, "square") * 0.08
    return w * (0.75 + 0.25 * np.sign(np.sin(2 * np.pi * hum * x)))


def crackles(secs, n, lo, hi, q=0.003):
    """n little pops scattered over secs."""
    out = np.zeros(int(secs * SR))
    for i in range(n):
        k = int(rng.uniform(0, len(out) - 600))
        c = click(0.02, rng.uniform(lo, hi), q) * rng.uniform(0.3, 1.0)
        out[k:k + len(c)] += c[:len(out) - k]
    return out


def build():
    # the beam: a steady electric whine and buzz (looped; pitched up while it cuts flesh)
    x = t(1.0)
    whine = lowpass(buzz(880, 1.0), 5000)
    save("laser_loop", mix(whine, band(noise(1.0), 3000, 9000) * 0.12 * (1 + 0.5 * np.sin(2 * np.pi * 12 * x)),
                           tone(120, 1.0) * 0.15), peak=0.45, loop=True)
    # in a body: frying, spitting
    x = t(1.2)
    fry = band(noise(1.2), 1800, 8000) * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 9 * x)))
    save("laser_sizzle_loop", mix(fry, crackles(1.2, 70, 2000, 6000) * 0.9), peak=0.5, loop=True)
    # switched on: a zap up into the whine
    n = int(0.16 * SR)
    chirp = tone(np.geomspace(250, 1300, n), 0.16, "saw") * env(n, 0.002, 0.12, 2.5)
    save("laser_start", mix(lowpass(chirp, 6000), click(0.03, 3500, 0.006) * 0.8,
                            band(noise(0.1), 2000, 8000) * env(int(0.1 * SR), 0.001, 0.05, 5) * 0.4), peak=0.55)
    # overheated: a long steam hiss, the whine dying, a couple of ticks from the metal cooling
    n = int(2.0 * SR)
    hiss = highpass(noise(2.0), 2500) * env(n, 0.02, 1.6, 2.2)
    die = tone(np.geomspace(900, 160, int(0.7 * SR)), 0.7, "saw") * env(int(0.7 * SR), 0.001, 0.6, 3) * 0.35
    ticks = mix(at(metal([3100, 4700], 0.15, 0.06) * 0.25, 0.75), at(metal([2900, 4300], 0.15, 0.06) * 0.2, 1.3))
    save("laser_overheat", mix(hiss, lowpass(die, 4000), ticks), peak=0.6)
    # the overcharge: a whine rising and wavering faster as it fills (0.65 s), then the shot's thump and the roar
    n = int(0.65 * SR)
    x = t(0.65)
    rise = np.geomspace(180, 2000, n)
    trem = 0.7 + 0.3 * np.sin(2 * np.pi * np.cumsum(np.linspace(6, 40, n)) / SR)
    charge = (tone(rise, 0.65, "saw") * 0.5 + tone(rise * 1.5, 0.65) * 0.3) * trem * np.clip(x / 0.5, 0.1, 1.0)
    save("laser_charge", mix(lowpass(charge, 7000), band(noise(0.65), 2000, 7000) * np.linspace(0.0, 0.25, n)), peak=0.55)
    n = int(0.6 * SR)
    thump = tone(np.geomspace(140, 40, n), 0.6) * env(n, 0.001, 0.45, 4)
    zap = band(noise(0.35), 600, 6000) * env(int(0.35 * SR), 0.001, 0.25, 4)
    save("laser_blast", mix(thump * 1.2, zap, buzz(330, 0.4) * env(int(0.4 * SR), 0.001, 0.3, 4) * 0.4), peak=0.85)
    x = t(1.0)
    roar = lowpass(noise(1.0), 1400) * (0.8 + 0.2 * np.sin(2 * np.pi * 17 * x))
    save("laser_blast_loop", mix(roar, lowpass(buzz(55, 1.0, 50), 900) * 0.9, lowpass(buzz(440, 1.0), 3000) * 0.25,
                                 crackles(1.0, 40, 800, 3000, 0.004) * 0.5), peak=0.75, loop=True)
    # let go before it was charged: the whine falls away
    n = int(0.28 * SR)
    save("laser_fizzle", lowpass(tone(np.geomspace(1400, 250, n), 0.28, "saw"), 4000) * env(n, 0.002, 0.25, 3), peak=0.35)


if __name__ == "__main__":
    build()
