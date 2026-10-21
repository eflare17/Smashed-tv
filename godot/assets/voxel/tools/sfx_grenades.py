import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
# The grenade launcher's sounds (voxel_weapon_grenades.gd), made from tones and noise like sfx.py's:
#     python3 -I godot/assets/voxel/tools/sfx_grenades.py
# writes godot/assets/voxel/sound/grenades_*.wav: the launch's hollow thoomp, the drum turning, a grenade's clink as
# it bounces and its tick as it blinks, a sticky bomb's clank on the world and wet thwap on a body, the detonator's
# beep, the big boom with its crackling tail, and the reload (the drum swung out, a round pushed in, swung shut).

rng = np.random.default_rng(44)


def crackle(secs, n, lo, hi, start=0.0, fade=1.0):
    """n little pops scattered over secs, thinning and quieting toward the end (burning bits, falling grit)."""
    out = np.zeros(int(secs * SR))
    for i in range(n):
        u = rng.uniform(0.0, 1.0) ** 1.8
        k = int((start + u * (secs - start - 0.03)) * SR)
        c = click(0.02, rng.uniform(lo, hi), rng.uniform(0.002, 0.006)) * rng.uniform(0.3, 1.0) * np.exp(-fade * u * 3.0)
        out[k:k + len(c)] += c[:len(out) - k]
    return out


def build():
    # the launch: a hollow tube thoomp (a deep drop and a resonant pop) with the action's click on top
    n = int(0.55 * SR)
    drop = tone(np.linspace(170, 48, n), 0.55) * env(n, 0.002, 0.32, 4)
    pop = band(noise(0.55), 250, 900) * env(n, 0.001, 0.09, 5) * 0.9
    tube = tone(np.linspace(420, 300, n), 0.55) * env(n, 0.002, 0.12, 5) * 0.35
    puff = band(noise(0.3), 800, 3500) * env(int(0.3 * SR), 0.004, 0.12, 4) * 0.25
    save("grenades_fire", mix(drop, pop, tube, puff, click(0.02, 2600, 0.004) * 0.4), peak=0.85)
    # the drum turning to the next chamber: a ratchet clack
    save("grenades_drum", mix(click(0.03, 1900, 0.006), at(click(0.03, 1300, 0.008) * 0.8, 0.045),
                              at(metal([2300, 3400], 0.1, 0.04) * 0.25, 0.045)), peak=0.45)
    # a bounce: a hard little shell on concrete, a dull knock and a clink
    knock = tone(np.linspace(260, 150, int(0.08 * SR)), 0.08) * env(int(0.08 * SR), 0.0005, 0.04, 5)
    save("grenades_bounce", mix(knock * 0.8, metal([1850, 2780, 4050], 0.28, 0.1) * 0.6, click(0.015, 3500, 0.003) * 0.5), peak=0.6)
    # the fuse light blinking: a soft high tick
    save("grenades_tick", tone(3100, 0.04) * env(int(0.04 * SR), 0.001, 0.02, 4) * 0.5 + tone(6200, 0.04) * env(int(0.04 * SR), 0.001, 0.01, 4) * 0.1, peak=0.3)
    # a sticky bomb on the world: a magnetic clank
    save("grenades_stick", mix(metal([640, 1060, 1590, 2410], 0.35, 0.12), click(0.025, 1700, 0.006) * 0.8,
                               tone(np.linspace(180, 90, int(0.1 * SR)), 0.1) * env(int(0.1 * SR), 0.001, 0.05, 5) * 0.6), peak=0.6)
    # ... on a body: a wet thwap (a slap, then a squelch wobbling down)
    n = int(0.3 * SR)
    slap = lowpass(noise(0.3), np.linspace(3500, 400, n)) * env(n, 0.0008, 0.07, 5)
    sq = band(noise(0.3), 300, 1400) * env(n, 0.01, 0.18, 4) * (0.6 + 0.4 * np.sin(2 * np.pi * np.linspace(38, 14, n) * t(0.3)))
    save("grenades_stick_flesh", mix(slap, sq * 0.7, tone(np.linspace(240, 80, n), 0.3) * env(n, 0.001, 0.12, 5) * 0.5,
                                     at(metal([900, 1400], 0.15, 0.05) * 0.15, 0.005)), peak=0.65)
    # the detonator: two quick rising beeps
    def beep(f, secs):
        m = int(secs * SR)
        x = tone(f, secs, "square") * 0.35 + tone(f, secs) * 0.65
        e = np.clip(np.minimum(np.arange(m), m - 1 - np.arange(m)) / (0.003 * SR), 0.0, 1.0)
        return lowpass(x * e, 6000)
    save("grenades_beep", mix(beep(2100, 0.055), at(beep(2800, 0.07), 0.075)), peak=0.45)
    # the boom: a sharp crack, a deep thump falling away, a long rumble, then the crackle of burning bits and grit
    secs = 2.8
    n = int(secs * SR)
    crack = band(noise(0.12), 500, 7000) * env(int(0.12 * SR), 0.0003, 0.04, 5)
    thump = tone(np.linspace(70, 22, int(1.6 * SR)), 1.6) * env(int(1.6 * SR), 0.003, 1.2, 3.5)
    whump = tone(np.linspace(140, 40, int(0.4 * SR)), 0.4) * env(int(0.4 * SR), 0.001, 0.25, 4)
    body = lowpass(noise(1.2), np.linspace(2200, 150, int(1.2 * SR))) * env(int(1.2 * SR), 0.002, 0.8, 3.5)
    rumble = lowpass(lowpass(noise(secs), np.linspace(380, 50, n)), 300) * env(n, 0.05, 2.6, 3.0)
    tail = crackle(secs, 170, 700, 4200, 0.15, 0.7)
    grit = crackle(secs, 60, 2000, 6000, 0.6, 0.4)
    save("grenades_boom", mix(crack * 0.7, thump * 1.5, whump * 0.9, body * 1.3, rumble * 5.0, tail * 0.7, grit * 0.3), peak=0.95)
    # the reload: the drum swung out (a latch and a slide), a round pushed in (a click and a thunk), swung shut
    save("grenades_open", mix(click(0.03, 1500, 0.007), at(band(noise(0.12), 1500, 5000) * env(int(0.12 * SR), 0.01, 0.06, 4) * 0.4, 0.02),
                              at(metal([1250, 1900], 0.15, 0.06) * 0.35, 0.09)), peak=0.5)
    save("grenades_load", mix(click(0.03, 2000, 0.005) * 0.8, at(tone(np.linspace(210, 140, int(0.07 * SR)), 0.07) * env(int(0.07 * SR), 0.001, 0.04, 5), 0.01),
                              at(metal([1600], 0.08, 0.03) * 0.2, 0.012)), peak=0.5)
    save("grenades_close", mix(click(0.04, 1100, 0.01), metal([980, 1520, 2200], 0.2, 0.07) * 0.5,
                               tone(np.linspace(160, 90, int(0.09 * SR)), 0.09) * env(int(0.09 * SR), 0.001, 0.05, 5) * 0.6), peak=0.6)


if __name__ == "__main__":
    build()
