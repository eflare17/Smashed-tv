#!/usr/bin/env python3
"""Sound effects for the voxel arena (the owner, 20 Oct: "sound"), made from noise and tones so they can be remade:
    python3 godot/assets/voxel/tools/sfx.py
writes godot/assets/voxel/sound/<name>.wav (22050 Hz, 16-bit mono). Loops (names ending _loop) are cut so their ends
meet. The pistol uses the game's own shots (assets/sounds/pistol_*.mp3); everything else is here. Owned by the voxel
session."""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "sound")
rng = np.random.default_rng(20)


def t(secs):
    return np.arange(int(secs * SR)) / SR


def noise(secs):
    return rng.uniform(-1.0, 1.0, int(secs * SR))


def env(n, attack=0.003, decay=0.2, curve=4.0):
    """An envelope n samples long: a quick rise, then an exponential fall reaching ~0 after decay seconds."""
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0.0, 1.0)
    return a * np.exp(-curve * x / max(decay, 1e-4))


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be a number or an array (a sweep)."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    k = 1.0 - np.exp(-2.0 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += k[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def band(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def tone(freq, secs, kind="sine"):
    """A tone; freq may be an array (a glide)."""
    n = int(secs * SR)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    ph = np.cumsum(2.0 * np.pi * f / SR)
    if kind == "saw":
        return 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    if kind == "square":
        return np.sign(np.sin(ph))
    return np.sin(ph)


def pad(x, secs):
    n = int(secs * SR)
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:max(n, len(x))]


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, secs, total=None):
    """x delayed by secs."""
    return np.concatenate([np.zeros(int(secs * SR)), x])


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x * (peak / m)


def save(name, x, peak=0.9, loop=False):
    x = norm(x, peak)
    if loop:
        # the ends cross-faded into each other so it loops without a click
        f = int(0.05 * SR)
        x = x.copy()
        head = x[:f].copy()
        x = x[f:]
        x[-f:] = x[-f:] * np.linspace(1, 0, f) + head * np.linspace(0, 1, f)
    else:
        f = min(64, len(x))
        x[-f:] *= np.linspace(1, 0, f)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("%-22s %.2f s" % (name, len(x) / SR))


def click(secs=0.03, f=2500, q=0.004):
    n = noise(secs)
    return band(n, f * 0.5, f * 1.5) * env(len(n), 0.0005, q, 6)


def metal(freqs, secs, decay):
    out = np.zeros(int(secs * SR))
    for i, f in enumerate(freqs):
        out += tone(f, secs) * env(len(out), 0.001, decay / (1 + i * 0.4), 5) / (1 + i * 0.5)
    return out


def swoosh(secs, lo, hi, peak_at=0.4):
    n = noise(secs)
    x = np.linspace(0, 1, len(n))
    sweep = lo + (hi - lo) * np.exp(-((x - peak_at) / 0.22) ** 2)
    shape = np.exp(-((x - peak_at) / 0.28) ** 2)
    return lowpass(highpass(n, lo * 0.5), sweep) * shape


def build():
    # ---------------------------------------------------------------- guns
    boom = lowpass(noise(0.9), np.linspace(5000, 300, int(0.9 * SR))) * env(int(0.9 * SR), 0.001, 0.5, 5)
    thump = tone(np.linspace(120, 45, int(0.4 * SR)), 0.4) * env(int(0.4 * SR), 0.001, 0.3, 5)
    save("shotgun_shot", mix(boom, thump * 0.9, click(0.02, 4000) * 0.6))
    save("shotgun_double", mix(boom * 1.2, at(boom * 0.8, 0.012), thump * 1.4, at(thump, 0.02)))
    rack = mix(click(0.05, 1800, 0.01), at(metal([2200, 3100], 0.12, 0.05) * 0.4, 0.005))
    save("shotgun_pump", mix(rack, at(rack * 1.1, 0.16), at(click(0.03, 900, 0.01) * 0.6, 0.17)))
    save("shell_in", mix(click(0.04, 1500, 0.008), at(metal([1700], 0.08, 0.04) * 0.3, 0.004)))
    save("shell_drop", mix(metal([3900, 5300, 7100], 0.25, 0.12), at(metal([4100, 5600], 0.2, 0.08) * 0.5, 0.09)), peak=0.5)
    save("mag_out", mix(click(0.05, 1200, 0.012), at(metal([1900], 0.1, 0.05) * 0.3, 0.01)))
    save("mag_in", mix(click(0.05, 1600, 0.01), at(click(0.04, 2400, 0.006) * 0.9, 0.09)))
    save("dry_fire", click(0.03, 3000, 0.004), peak=0.5)
    # ---------------------------------------------------------------- hits
    sq = lowpass(noise(0.22), np.linspace(2500, 300, int(0.22 * SR))) * env(int(0.22 * SR), 0.002, 0.12, 4)
    save("hit_flesh", mix(sq, tone(np.linspace(220, 90, int(0.15 * SR)), 0.15) * env(int(0.15 * SR), 0.001, 0.1, 5) * 0.5))
    save("hit_world", mix(band(noise(0.06), 2000, 8000) * env(int(0.06 * SR), 0.0005, 0.02, 6),
                          metal([5200, 7600], 0.2, 0.06) * 0.35), peak=0.6)
    # ---------------------------------------------------------------- melee
    save("swoosh_sword", swoosh(0.3, 1500, 6000), peak=0.6)
    save("swoosh_bat", swoosh(0.35, 500, 2500), peak=0.7)
    save("swoosh_heavy", swoosh(0.55, 150, 900, 0.5), peak=0.8)
    slice_ = mix(band(noise(0.18), 1500, 7000) * env(int(0.18 * SR), 0.001, 0.07, 5), sq * 0.7)
    save("slice", slice_)
    save("thwack", mix(tone(np.linspace(160, 60, int(0.25 * SR)), 0.25) * env(int(0.25 * SR), 0.0005, 0.15, 5),
                       band(noise(0.08), 800, 4000) * env(int(0.08 * SR), 0.0005, 0.03, 6) * 0.8))
    save("home_run", mix(band(noise(0.12), 1500, 9000) * env(int(0.12 * SR), 0.0002, 0.04, 6),
                         tone(np.linspace(260, 80, int(0.4 * SR)), 0.4) * env(int(0.4 * SR), 0.0005, 0.25, 5),
                         at(metal([900, 1350], 0.3, 0.2) * 0.3, 0.01)))
    crunch = mix(*[at(lowpass(noise(0.08), 2500) * env(int(0.08 * SR), 0.001, 0.04, 5) * (0.8 - i * 0.12), i * 0.025) for i in range(5)])
    save("crunch", mix(crunch, tone(np.linspace(90, 40, int(0.35 * SR)), 0.35) * env(int(0.35 * SR), 0.001, 0.3, 4)))
    rumble = lowpass(noise(1.4), np.linspace(900, 80, int(1.4 * SR))) * env(int(1.4 * SR), 0.004, 1.0, 4)
    save("slam", mix(rumble, tone(np.linspace(70, 28, int(1.0 * SR)), 1.0) * env(int(1.0 * SR), 0.002, 0.8, 4) * 1.4))
    # the chainsaw: a two-stroke putter idling, a howl revving, a grind in flesh (all loops)
    def engine(f0, secs, rough):
        x = t(secs)
        f = f0 * (1 + 0.03 * np.sin(2 * np.pi * 3.0 * x))
        e = tone(f, secs, "saw") * 0.6 + tone(f * 2, secs, "square") * 0.15
        return lowpass(e + noise(secs) * rough, 2500)
    save("chainsaw_idle_loop", engine(28, 1.2, 0.25), peak=0.6, loop=True)
    save("chainsaw_rev_loop", engine(95, 1.2, 0.35), peak=0.7, loop=True)
    g = band(noise(1.2), 600, 5000) * (0.7 + 0.3 * np.sin(2 * np.pi * 23 * t(1.2)))
    save("chainsaw_cut_loop", mix(engine(85, 1.2, 0.3) * 0.6, g), peak=0.75, loop=True)
    save("spear_thrust", swoosh(0.22, 900, 4500, 0.35), peak=0.6)
    save("spear_throw", swoosh(0.45, 600, 3500, 0.3), peak=0.65)
    save("spear_stick", mix(tone(np.linspace(330, 140, int(0.2 * SR)), 0.2) * env(int(0.2 * SR), 0.0005, 0.12, 5),
                            metal([620, 930, 1240], 0.5, 0.35) * 0.4, click(0.02, 1500) * 0.5))
    # ---------------------------------------------------------------- the vacuum, the switch, cubes
    x = t(1.5)
    hum = lowpass(noise(1.5), 1400) * 0.6 + tone(118, 1.5) * 0.25 + tone(236, 1.5) * 0.1 + band(noise(1.5), 3000, 6000) * 0.12 * (1 + np.sin(2 * np.pi * 7 * x))
    save("vacuum_loop", hum, peak=0.5, loop=True)
    save("vacuum_pop", mix(tone(np.linspace(900, 1800, int(0.05 * SR)), 0.05) * env(int(0.05 * SR), 0.001, 0.025, 5)), peak=0.35)
    save("switch", mix(click(0.04, 1400, 0.01), at(click(0.04, 2200, 0.008) * 0.8, 0.07)), peak=0.5)
    # ---------------------------------------------------------------- fire and ice (any weapon's)
    def tinkle(n, secs, spread):
        return mix(*[at(metal([2600 + 900 * ((i * 7) % 5), 4100 + 700 * ((i * 3) % 4)], 0.3, 0.12) * (0.9 - 0.6 * i / n),
                        spread * (i / n) ** 1.4 + 0.004 * ((i * 5) % 3)) for i in range(n)])
    crack = band(noise(0.12), 1200, 9000) * env(int(0.12 * SR), 0.0003, 0.04, 6)
    save("shatter", mix(crack * 1.2, at(tinkle(16, 0.6, 0.45) * 0.6, 0.01),
                        lowpass(noise(0.5), 1800) * env(int(0.5 * SR), 0.002, 0.3, 4) * 0.5), peak=0.8)
    fz = mix(*[at(band(noise(0.03), 2500, 9000) * env(int(0.03 * SR), 0.0005, 0.01, 6) * (0.4 + 0.6 * ((i * 11) % 7) / 6),
                  0.03 * i + 0.01 * ((i * 3) % 4)) for i in range(18)])
    save("freeze", mix(fz, tone(np.linspace(1800, 2600, int(0.7 * SR)), 0.7) * env(int(0.7 * SR), 0.05, 0.6, 3) * 0.08), peak=0.55)
    # fire: a soft roar with crackles in it
    x = t(2.0)
    roar = lowpass(noise(2.0), 700) * (0.8 + 0.2 * np.sin(2 * np.pi * 1.3 * x))
    pops = np.zeros(len(x))
    for i in range(60):
        k = int(rng.uniform(0, len(x) - 400))
        c = click(0.015, rng.uniform(1500, 4500), 0.003) * rng.uniform(0.3, 1.0)
        pops[k:k + len(c)] += c[:len(pops) - k]
    save("burn_loop", mix(roar, pops * 0.7), peak=0.45, loop=True)
    save("ignite", mix(lowpass(noise(0.5), np.linspace(400, 2500, int(0.5 * SR))) * env(int(0.5 * SR), 0.06, 0.35, 3),
                       tone(np.linspace(60, 110, int(0.4 * SR)), 0.4) * env(int(0.4 * SR), 0.04, 0.3, 4) * 0.5), peak=0.6)
    save("cubes_fall", mix(*[at(click(0.02, 1800 + 600 * (i % 3), 0.003) * (0.5 + 0.5 * ((i * 7) % 3) / 2), 0.012 * i + 0.004 * ((i * 5) % 3)) for i in range(14)]), peak=0.35)


if __name__ == "__main__":
    build()
