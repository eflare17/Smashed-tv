import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
"""The flamethrower's sounds (voxel_weapon_flamethrower.gd), made from noise and tones like sfx.py's:
    python3 -I godot/assets/voxel/tools/sfx_flamethrower.py
writes godot/assets/voxel/sound/flamethrower_*.wav. Owned by the voxel session."""


def puff(secs, lo, hi, decay, attack=0.004):
    """A soft burst of gas: noise swept down from hi to lo."""
    n = int(secs * SR)
    return lowpass(highpass(noise(secs), 60), np.linspace(hi, lo, n)) * env(n, attack, decay, 4)


def crackles(secs, n, lo=1500, hi=5000, amp=(0.3, 1.0)):
    """n little pops scattered through secs."""
    out = np.zeros(int(secs * SR))
    for _ in range(n):
        k = int(rng.uniform(0, len(out) - 500))
        c = click(0.012, rng.uniform(lo, hi), rng.uniform(0.002, 0.005)) * rng.uniform(*amp)
        out[k:k + len(c)] += c[:len(out) - k]
    return out


def build_flamethrower():
    # lit: the igniter's tick, then the whoomph of the fuel catching
    n = int(0.75 * SR)
    whoomph = lowpass(noise(0.75), np.concatenate([np.linspace(250, 3200, n // 5), np.linspace(3200, 500, n - n // 5)]))
    whoomph *= env(n, 0.035, 0.5, 3)
    thump = tone(np.linspace(48, 95, int(0.45 * SR)), 0.45) * env(int(0.45 * SR), 0.03, 0.35, 4)
    save("flamethrower_start", mix(click(0.02, 3500, 0.003) * 0.5, at(whoomph, 0.02), at(thump * 0.8, 0.03)), peak=0.8)
    # spraying: a roaring hiss that churns (the turbulence of the burning fuel), a low rumble under it, a few crackles
    x = t(1.6)
    churn = 0.75 + 0.15 * np.sin(2 * np.pi * 9.0 * x) + 0.1 * np.sin(2 * np.pi * 13.7 * x + 1.0)
    roar = band(noise(1.6), 180, 1800) * churn
    hiss = band(noise(1.6), 2500, 7500) * 0.22 * (0.85 + 0.15 * np.sin(2 * np.pi * 6.3 * x))
    rumble = lowpass(noise(1.6), 140) * 2.2
    save("flamethrower_loop", mix(roar, hiss, rumble, crackles(1.6, 25) * 0.25), peak=0.6, loop=True)
    # let go: the last of it puffs out
    save("flamethrower_stop", mix(puff(0.45, 150, 1800, 0.25), click(0.015, 1200, 0.004) * 0.3), peak=0.55)
    # run dry: a few weak coughs, a gurgle, a hiss dying away
    sp = np.zeros(int(1.0 * SR))
    for i, (when, amp) in enumerate([(0.0, 1.0), (0.17, 0.75), (0.31, 0.85), (0.52, 0.5), (0.7, 0.35)]):
        p = puff(0.16, 150, 1400 - i * 150, 0.07, 0.002) * amp
        g = tone(np.linspace(140, 70, int(0.06 * SR)), 0.06) * env(int(0.06 * SR), 0.001, 0.04, 5) * 0.4 * amp
        k = int(when * SR)
        sp[k:k + len(p)] += p[:len(sp) - k]
        sp[k:k + len(g)] += g[:len(sp) - k]
    tail = band(noise(1.0), 2000, 6000) * np.exp(-np.linspace(0, 6, int(1.0 * SR))) * 0.12
    save("flamethrower_empty", mix(sp, at(click(0.02, 2200, 0.004) * 0.4, 0.05), tail), peak=0.55)
    # the fire bomb: a hollow thunk out of the nozzle and the blob whooshing off
    thunk = tone(np.linspace(150, 55, int(0.22 * SR)), 0.22) * env(int(0.22 * SR), 0.001, 0.14, 5)
    save("flamethrower_lob", mix(thunk, puff(0.2, 200, 2500, 0.08) * 0.6, at(swoosh(0.4, 400, 2200, 0.35) * 0.7, 0.03)), peak=0.75)
    # it bursts: a wet splat, then the whoomph of the patch going up, crackling
    splat = band(noise(0.2), 300, 3500) * env(int(0.2 * SR), 0.001, 0.07, 5)
    n = int(1.0 * SR)
    up = lowpass(noise(1.0), np.concatenate([np.linspace(300, 2600, n // 4), np.linspace(2600, 400, n - n // 4)])) * env(n, 0.05, 0.7, 3)
    save("flamethrower_splash", mix(splat, at(up, 0.03), tone(np.linspace(55, 40, int(0.6 * SR)), 0.6) * env(int(0.6 * SR), 0.01, 0.5, 4) * 0.8,
                                    at(crackles(0.9, 18), 0.1) * 0.5), peak=0.8)
    # the patch burning: a low flutter of flame and a lot of crackling
    x = t(2.0)
    flutter = lowpass(noise(2.0), 450) * (0.75 + 0.25 * np.sin(2 * np.pi * 2.1 * x) * np.sin(2 * np.pi * 0.7 * x))
    save("flamethrower_patch_loop", mix(flutter, crackles(2.0, 90, 1200, 5500) * 0.8), peak=0.5, loop=True)
    # ice meeting the stream: steam hissing off
    x = t(1.2)
    save("flamethrower_steam_loop", band(noise(1.2), 3000, 9000) * (0.8 + 0.2 * np.sin(2 * np.pi * 11 * x)), peak=0.4, loop=True)


if __name__ == "__main__":
    build_flamethrower()
