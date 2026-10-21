import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
"""The shredder's sounds (voxel_shredder.gd), made from noise and tones like sfx.py's:
    python3 -I godot/assets/voxel/tools/sfx_shredder.py
writes godot/assets/voxel/sound/: mince_loop (the hand-crank mincer: a wet squelching grind and the crank's creak),
shred_loop (the electric shredder: a motor's whine and teeth chewing), chip_loop (the woodchipper: a diesel thrumming
and the drum chipping hard), crunch_0..2 (bone going in), bag_drop (a full bag thumping down), machine_start (a motor
winding up); and (Stage 8) flesh_tear_0..1, a dangling limb's strip ripping through: a wet tearing crackle. The loops are cut so their ends meet. Owned by the voxel session."""


def chew(secs, rate, lo, hi, sharp=0.02):
    """Bursts of filtered noise rate a second (teeth biting)."""
    n = int(secs * SR)
    out = np.zeros(n)
    k = 0.0
    while k < secs:
        b = band(noise(sharp * 4), lo, hi) * env(int(sharp * 4 * SR), 0.002, sharp, 3) * rng.uniform(0.5, 1.0)
        i = int(k * SR)
        out[i:i + len(b)] += b[:n - i]
        k += 1.0 / rate * rng.uniform(0.6, 1.4)
    return out


def build_shredder():
    secs = 2.0
    tt = t(secs)
    # the mincer: slow squelch (the crank goes round once a second), a creak each turn
    wet = band(noise(secs), 150, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 2.0 * tt)) ** 2
    creak = band(tone(260 + 30 * np.sin(2 * np.pi * 1.0 * tt), secs, "saw"), 400, 1800) * np.clip(np.sin(2 * np.pi * 1.0 * tt), 0, 1) ** 6
    save("mince_loop", mix(wet * 1.0, creak * 0.35, chew(secs, 6, 300, 1500, 0.04) * 0.6), peak=0.55, loop=True)
    # the shredder: a motor's whine and teeth
    motor = band(tone(120, secs, "saw") + tone(240, secs, "saw") * 0.5, 80, 1200) * (0.9 + 0.1 * np.sin(2 * np.pi * 7 * tt))
    whine = tone(1800, secs) * 0.08
    save("shred_loop", mix(motor * 0.6, whine, chew(secs, 22, 600, 4000, 0.015) * 0.9, band(noise(secs), 200, 800) * 0.25), peak=0.7, loop=True)
    # the woodchipper: diesel thrum and the drum chipping
    thrum = lowpass(tone(42, secs, "square"), 300) * (0.7 + 0.3 * np.sin(2 * np.pi * 21 * tt))
    drum = band(noise(secs), 300, 3000) * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 9 * tt)))
    save("chip_loop", mix(thrum * 0.8, drum * 0.6, chew(secs, 40, 800, 5000, 0.012) * 1.0), peak=0.8, loop=True)
    for v in range(3):
        n = int(0.25 * SR)
        c = mix(click(0.03, 1800 + 400 * v, 0.004) * 1.4, band(noise(0.25), 500, 3500) * env(n, 0.002, 0.12, 4) * 0.8,
                at(click(0.02, 2600, 0.003), 0.05 + 0.02 * v))
        save("crunch_%d" % v, c, peak=0.7)
    n = int(0.3 * SR)
    save("bag_drop", mix(tone(np.linspace(110, 60, n), 0.3) * env(n, 0.002, 0.12, 4), band(noise(0.3), 200, 1500) * env(n, 0.002, 0.08, 4) * 0.6), peak=0.7)
    n = int(1.0 * SR)
    wind = tone(np.linspace(30, 120, n), 1.0, "saw")
    save("machine_start", band(wind, 60, 1500) * env(n, 0.3, 1.0, 1.0), peak=0.6)


def build_tear():
    for v in range(2):
        secs = 0.5
        n = int(secs * SR)
        rip = chew(secs, 60 + 20 * v, 400, 3500, 0.006) * np.linspace(1.0, 0.2, n)
        wet = band(noise(secs), 150, 900) * env(n, 0.005, 0.3, 3) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t(secs)))
        save("flesh_tear_%d" % v, mix(rip * 1.0, wet * 0.8, click(0.03, 1200 + 300 * v, 0.004) * 1.2), peak=0.8)


if __name__ == "__main__":
    build_shredder()
    build_tear()
