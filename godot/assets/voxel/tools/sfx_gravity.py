import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
# The gravity gun's sounds (the owner, 20 Oct: six new weapons, each doing something different), made like sfx.py's:
#     python3 -I godot/assets/voxel/tools/sfx_gravity.py
# writes godot/assets/voxel/sound/gravity_<name>.wav. Owned by the voxel session.


def crackle(secs, rate, lo, hi):
    """Electric crackle: short random sparks of noise."""
    n = int(secs * SR)
    out = np.zeros(n)
    k = 0
    while k < n:
        g = int(rng.uniform(0.002, 0.009) * SR)
        burst = rng.uniform(-1.0, 1.0, g) * env(g, 0.0002, g / SR * 0.5, 4) * rng.uniform(0.2, 1.0)
        out[k:k + g] += burst[:n - k]
        k += int(SR / rate * rng.uniform(0.3, 1.7))
    return band(out, lo, hi)


def hum(f0, secs, pulse=0.0, buzz=0.3):
    """The gun's field: a low saw with its octave and a buzz on top, throbbing pulse times a second."""
    x = t(secs)
    h = tone(f0, secs, "saw") * 0.5 + tone(f0 * 2.0, secs) * 0.35 + tone(f0 * 3.01, secs, "square") * 0.08 * buzz
    h = lowpass(h, 1600)
    if pulse > 0.0:
        h *= 0.65 + 0.35 * np.sin(2 * np.pi * pulse * x)
    return h


def zap(secs, f_hi, f_lo):
    """A bright electric zap falling in pitch."""
    n = int(secs * SR)
    sweep = np.geomspace(f_hi, f_lo, n)
    z = tone(sweep, secs, "saw") * 0.5 + band(noise(secs), 1500, 9000) * 0.6
    return z * env(n, 0.0008, secs * 0.6, 4)


def build():
    # grab: a zap, then the field taking hold, a hum swelling up
    n = int(0.55 * SR)
    swell = hum(np.linspace(45, 62, n), 0.55, 7.0) * np.clip(np.linspace(0, 2.5, n), 0, 1) * np.clip(np.linspace(2.2, 0, n), 0, 1)
    save("gravity_grab", mix(zap(0.16, 4200, 500) * 0.8, crackle(0.25, 260, 2000, 8000) * 0.4, at(swell, 0.03)), peak=0.75)
    # held: a low throbbing electric hum with a crackle running through it (loop)
    x = t(1.6)
    loop = hum(52, 1.6, 5.0) + crackle(1.6, 90, 2500, 9000) * 0.18 + tone(104 * (1 + 0.004 * np.sin(2 * np.pi * 2.5 * x)), 1.6) * 0.15
    save("gravity_hold_loop", loop, peak=0.5, loop=True)
    # launch: a big whump (a low thump falling, air shoved) and a zap
    n = int(0.7 * SR)
    whump = tone(np.geomspace(140, 32, n), 0.7) * env(n, 0.001, 0.45, 4)
    air = lowpass(noise(0.5), np.geomspace(3500, 200, int(0.5 * SR))) * env(int(0.5 * SR), 0.001, 0.3, 5)
    save("gravity_launch", mix(whump * 1.3, air * 0.8, zap(0.3, 6000, 300) * 0.7, crackle(0.35, 300, 2500, 9000) * 0.3), peak=0.9)
    # drop: the field letting go, a hum sinking away with a soft puff
    n = int(0.45 * SR)
    sink = hum(np.linspace(60, 30, n), 0.45, 0.0) * env(n, 0.005, 0.35, 3)
    puff = lowpass(noise(0.2), 900) * env(int(0.2 * SR), 0.003, 0.12, 4)
    save("gravity_drop", mix(sink, puff * 0.5, click(0.02, 1800, 0.004) * 0.3), peak=0.55)
    # miss: a dry click of the prongs and a short servo whine
    servo = tone(np.linspace(900, 700, int(0.08 * SR)), 0.08, "square") * env(int(0.08 * SR), 0.002, 0.05, 4)
    save("gravity_miss", mix(click(0.03, 2600, 0.004), at(click(0.03, 1700, 0.005) * 0.8, 0.045), at(lowpass(servo, 2500) * 0.15, 0.01)), peak=0.5)
    # the black hole opening: air drawn in (a swell), then a deep 'vwomm' and a shimmer
    n = int(1.1 * SR)
    suck_in = lowpass(noise(0.45), np.geomspace(300, 4000, int(0.45 * SR))) * np.linspace(0, 1, int(0.45 * SR)) ** 2
    vwom = tone(np.geomspace(90, 34, n), 1.1) * env(n, 0.01, 0.9, 3)
    shimmer = mix(*[tone(f * (1 + 0.01 * np.sin(2 * np.pi * 5 * t(1.0))), 1.0) * env(int(1.0 * SR), 0.05, 0.8, 3) * 0.08 for f in (620, 930, 1395)])
    save("gravity_hole_open", mix(suck_in * 0.7, at(vwom * 1.2, 0.4), at(shimmer, 0.42), at(crackle(0.4, 200, 1500, 6000) * 0.25, 0.4)), peak=0.85)
    # open: a deep swirling drone with a rumble under it, the swirl sweeping round (loop)
    secs = 2.4
    x = t(secs)
    drone = tone(38, secs) * 0.6 + tone(38.6, secs) * 0.5 + tone(57, secs, "saw") * 0.12
    swirl_c = 500 + 380 * np.sin(2 * np.pi * x / (secs / 3))
    swirl = lowpass(highpass(noise(secs), 120), swirl_c) * (0.6 + 0.4 * np.sin(2 * np.pi * x / (secs / 2)))
    rumble = lowpass(noise(secs), 90) * 2.5
    save("gravity_hole_loop", mix(lowpass(drone, 400), swirl * 0.5, rumble), peak=0.6, loop=True)
    # closing: everything sucked into it (a rising roar and tone), a blink of silence, then the boom
    n = int(0.36 * SR)
    rise = lowpass(noise(0.36), np.geomspace(200, 6000, n)) * np.linspace(0.1, 1, n) ** 2
    pitch_up = tone(np.geomspace(60, 700, n), 0.36, "saw") * np.linspace(0, 1, n) ** 3 * 0.35
    n2 = int(1.6 * SR)
    boom = lowpass(noise(1.6), np.geomspace(4000, 60, n2)) * env(n2, 0.001, 1.1, 4)
    thud = tone(np.geomspace(80, 24, n2), 1.6) * env(n2, 0.001, 1.0, 3.5)
    save("gravity_hole_close", mix(rise, pitch_up, at(boom * 1.1, 0.38), at(thud * 1.5, 0.38),
                                   at(crackle(0.3, 300, 2000, 9000) * 0.3, 0.38)), peak=0.95)


if __name__ == "__main__":
    build()
