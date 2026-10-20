import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
# The harpoon gun's sounds (the owner, 20 Oct: six new weapons, each doing something different), made like sfx.py's:
#     python3 -I godot/assets/voxel/tools/sfx_harpoon.py
# writes godot/assets/voxel/sound/harpoon_<name>.wav. Owned by the voxel session.


def twang(f0, secs, decay, wobble=0.012):
    """A plucked taut line: a bright saw dulling as it rings, its pitch wavering a little."""
    x = t(secs)
    f = f0 * (1 + wobble * np.sin(2 * np.pi * 9.0 * x) * np.exp(-x * 6))
    s = tone(f, secs, "saw") * 0.5 + tone(f * 2.01, secs) * 0.35 + tone(f * 3.02, secs) * 0.15
    return lowpass(s, np.linspace(5000, 900, len(s))) * env(len(s), 0.001, decay, 5)


def grains(secs, rate, lo, hi, seed_amp=1.0):
    """Noise chopped into short random bursts (a tear, a crackle)."""
    n = int(secs * SR)
    out = np.zeros(n)
    k = 0
    while k < n:
        g = int(rng.uniform(0.004, 0.018) * SR)
        a = rng.uniform(0.25, 1.0) * seed_amp
        burst = rng.uniform(-1.0, 1.0, g) * env(g, 0.0005, g / SR * 0.6, 3) * a
        out[k:k + g] += burst[:n - k]
        k += int(SR / rate * rng.uniform(0.4, 1.6))
    return band(out, lo, hi)


def build():
    # fired: the air let go in a thunk, the line twanging out after the harpoon and whizzing off the reel
    thunk = tone(np.linspace(170, 50, int(0.3 * SR)), 0.3) * env(int(0.3 * SR), 0.0008, 0.16, 5)
    air = band(noise(0.25), 700, 5000) * env(int(0.25 * SR), 0.0005, 0.07, 5)
    whizz = band(noise(0.45), 2500, 7000) * np.linspace(1, 0, int(0.45 * SR)) ** 2
    save("harpoon_fire", mix(thunk * 1.3, air * 0.9, click(0.02, 2200, 0.004) * 0.7,
                             at(twang(196, 0.6, 0.35) * 0.45, 0.008), at(whizz * 0.18, 0.02)), peak=0.85)
    # into flesh: a deep meaty thud and a wet squelch
    sq = lowpass(noise(0.3), np.linspace(1800, 200, int(0.3 * SR))) * env(int(0.3 * SR), 0.002, 0.15, 4)
    thud = tone(np.linspace(120, 42, int(0.35 * SR)), 0.35) * env(int(0.35 * SR), 0.001, 0.22, 5)
    save("harpoon_hit", mix(thud * 1.3, sq, at(grains(0.12, 220, 300, 2500, 0.5), 0.01), twang(150, 0.3, 0.15) * 0.15))
    # into a wall or the floor: a clank, the shaft ringing as it quivers
    ring = metal([1380, 2270, 3650, 5100], 0.7, 0.4)
    quiver = twang(410, 0.5, 0.3, 0.03) * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * t(0.5)))
    save("harpoon_clank", mix(click(0.025, 3500, 0.005) * 1.2, ring * 0.5, quiver * 0.35,
                              band(noise(0.08), 1500, 7000) * env(int(0.08 * SR), 0.0005, 0.03, 6) * 0.6), peak=0.75)
    # reeling in: a pawl ratcheting over the gear (28 clicks a second, a whole number in the loop) over a whir
    secs = 1.0
    rat = np.zeros(int(secs * SR))
    for i in range(28):
        c = click(0.012, 2600 + 300 * (i % 3), 0.0025) * (0.75 + 0.25 * (i % 2))
        k = int(i * secs * SR / 28)
        rat[k:k + len(c)] += c[:len(rat) - k]
    x = t(secs)
    whir = tone(150, secs, "saw") * 0.18 + tone(300, secs) * 0.1 + band(noise(secs), 900, 3000) * 0.25 * (1 + 0.3 * np.sin(2 * np.pi * 14 * x))
    save("harpoon_reel_loop", mix(rat, lowpass(whir, 2500)), peak=0.55, loop=True)
    # a limb torn off: a wet ripping crackle sliding down, a pop as it comes away, the squelch
    rip = grains(0.45, 600, 500, 4500) * np.linspace(1.0, 0.5, int(0.45 * SR)) ** 0.5
    rip = lowpass(rip, np.linspace(4500, 1200, len(rip)))
    pop = tone(np.linspace(220, 70, int(0.2 * SR)), 0.2) * env(int(0.2 * SR), 0.001, 0.1, 5)
    save("harpoon_rip", mix(rip * 1.2, at(pop, 0.3), at(sq * 0.9, 0.28), at(click(0.02, 1200, 0.006) * 0.6, 0.3)), peak=0.85)
    # the line pulled taut on a tug: a short creaking groan rising
    x = t(0.3)
    groan = tone(np.linspace(85, 150, len(x)) * (1 + 0.05 * np.sin(2 * np.pi * 31 * x)), 0.3, "saw")
    save("harpoon_taut", mix(lowpass(groan, 1400) * env(len(x), 0.03, 0.25, 3), click(0.02, 1800, 0.004) * 0.4), peak=0.6)
    # back on the rail: it slides home with a clack, then the air's pumped up again
    hiss = band(noise(0.3), 2500, 8000) * env(int(0.3 * SR), 0.05, 0.2, 3)
    save("harpoon_load", mix(click(0.03, 1600, 0.008), at(metal([1900, 2800], 0.12, 0.05) * 0.4, 0.004),
                             at(click(0.03, 1100, 0.01) * 0.8, 0.2), at(hiss * 0.35, 0.22)), peak=0.6)


if __name__ == "__main__":
    build()
