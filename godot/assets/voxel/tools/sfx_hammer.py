import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
"""The sledgehammer's own sounds (voxel_melee_hammer.gd), made from noise and tones like sfx.py's:
    python3 -I godot/assets/voxel/tools/sfx_hammer.py
writes godot/assets/voxel/sound/hammer_*.wav: hammer_hit_0..2 (the head landing in a body: a deep meaty thump, bones
crunching, a wet slap; the game picks one at random) and hammer_thud_0..1 (the head on the floor: a dull heavy thud
and the loose cubes rattling). The swings use sfx.py's swoosh_heavy, the ground slam its slam. Owned by the voxel
session."""


def thump(secs, f0, f1, decay):
    """A deep body blow: a tone falling from f0 to f1."""
    n = int(secs * SR)
    return tone(np.linspace(f0, f1, n), secs) * env(n, 0.0008, decay, 4)


def cracks(secs, n, lo, hi, spread):
    """n bone cracks, the first loudest, inside spread seconds."""
    out = np.zeros(int(secs * SR))
    for i in range(n):
        k = int((spread * (i / max(n - 1, 1)) ** 1.3 + rng.uniform(0, 0.006)) * SR)
        c = click(0.03, rng.uniform(lo, hi), rng.uniform(0.004, 0.009)) * (1.0 - 0.6 * i / n) * rng.uniform(0.7, 1.0)
        out[k:k + len(c)] += c[:len(out) - k]
    return out


def rattle(secs, n, start, spread):
    """Little cubes falling back and bouncing: soft high ticks scattered after start."""
    out = np.zeros(int(secs * SR))
    for i in range(n):
        k = int((start + spread * rng.uniform(0, 1) ** 0.7) * SR)
        c = click(0.02, rng.uniform(1600, 3200), 0.003) * rng.uniform(0.2, 0.6)
        out[k:k + len(c)] += c[:len(out) - k]
    return out


def build_hammer():
    for v in range(3):
        n = int(0.6 * SR)
        # the head sinking in: a dull wide slap (noise closing down fast), a deep thump under it
        slap = lowpass(noise(0.6), np.linspace(3200 - 300 * v, 160, n)) * env(n, 0.0006, 0.16, 4)
        body = thump(0.55, 150 - 15 * v, 40, 0.3)
        sub = thump(0.6, 55, 30, 0.5)
        # the bones going: a burst of crunches; the wet of it, a squelch of low noise wobbling
        crunch = band(cracks(0.25, 7 + v, 1300, 4200, 0.07), 900, 6500)
        wob = 0.6 + 0.4 * np.sin(2 * np.pi * (31 + 6 * v) * t(0.3))
        wet = band(noise(0.3), 250, 1400) * wob * env(int(0.3 * SR), 0.004, 0.14, 4)
        save("hammer_hit_%d" % v, mix(slap * 2.2, body * 1.2, sub * 0.6, at(crunch * 1.6, 0.004), at(wet * 1.6, 0.012)), peak=0.92)
    for v in range(2):
        n = int(0.8 * SR)
        # steel on the floor: a dull heavy thud (no ring: it's a blunt face into packed ground), cubes skittering
        thud = thump(0.7, 85 - 10 * v, 30, 0.42)
        dust = lowpass(noise(0.8), np.linspace(900, 90, n)) * env(n, 0.001, 0.3, 4)
        knock = band(noise(0.05), 300, 1800) * env(int(0.05 * SR), 0.0004, 0.02, 6)
        save("hammer_thud_%d" % v, mix(thud * 1.2, dust * 1.6, knock * 1.2, rattle(0.8, 16, 0.08, 0.55) * 0.7), peak=0.88)


if __name__ == "__main__":
    build_hammer()
