import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
"""The kill announcer's stingers (voxel_announcer.gd), made from noise and tones like sfx.py's:
    python3 -I godot/assets/voxel/tools/sfx_announcer.py
writes godot/assets/voxel/sound/: announce_1..7 (DOUBLE KILL up to HOLY SHIT: a hit and a brassy chord, bigger,
higher and longer each tier), announce_spree (a sweeping choir-ish swell and a gong), announce_head (a crack and a
ping). A recorded voice for a line plays instead of these (see voxel_announcer.gd). Owned by the voxel session."""

# chords (semitones over the root) for each tier: brighter and wider as it climbs
CHORDS = [[0, 7, 12], [0, 4, 7, 12], [0, 5, 7, 12], [0, 4, 7, 11, 14], [0, 3, 7, 10, 15], [0, 4, 8, 12, 16], [0, 7, 12, 16, 19, 24]]


def brass(freq, secs, bright):
    """A saw stack through a filter that opens and closes: a brass stab."""
    n = int(secs * SR)
    x = tone(freq, secs, "saw") + tone(freq * 1.005, secs, "saw") * 0.7 + tone(freq * 0.995, secs, "saw") * 0.7
    cut = 300 + bright * np.exp(-3.0 * np.arange(n) / SR) * 4000
    return lowpass(x, cut)


def build():
    for tier in range(1, 8):
        secs = 0.9 + tier * 0.12
        n = int(secs * SR)
        root = 110.0 * 2 ** ((tier - 1) * 2 / 12.0)
        chord = sum(brass(root * 2 ** (s / 12.0), secs, 0.6 + tier * 0.15) for s in CHORDS[tier - 1])
        chord = chord * env(n, 0.01, secs * 0.6, 2.5)
        boom = lowpass(noise(secs), np.linspace(900, 60, n)) * env(n, 0.002, 0.35, 5) * (2.0 + tier * 0.3)
        sub = tone(np.linspace(80, 38, n), secs) * env(n, 0.003, 0.5, 4) * 1.2
        shimmer = band(noise(secs), 4000, 9000) * env(n, 0.05, secs * 0.7, 3) * (0.05 * tier)
        save("announce_%d" % tier, mix(chord * 0.5, boom, sub, shimmer), peak=0.9)
    # the spree: a swell of detuned voices and a gong
    secs = 2.0
    n = int(secs * SR)
    tt = t(secs)
    voices = sum(lowpass(tone(f * (1 + 0.004 * np.sin(2 * np.pi * (0.3 + i * 0.1) * tt)), secs, "saw"), 1400) for i, f in enumerate([220, 277.2, 329.6, 440, 554.4]))
    swell = np.clip(tt / 0.6, 0, 1) * np.exp(-1.2 * np.maximum(tt - 1.0, 0))
    gong = metal([98, 196.5, 263, 351, 527], secs, 1.8)
    save("announce_spree", mix(voices * swell * 0.35, gong * 0.8, lowpass(noise(secs), 120) * env(n, 0.002, 0.4, 4) * 2.0), peak=0.85)
    # a headshot: a crack and a bright ping
    n = int(0.6 * SR)
    crack = band(noise(0.6), 1500, 8000) * env(n, 0.0005, 0.03, 6) * 2.0
    ping = metal([1760, 2640, 3520], 0.6, 0.35)
    thump = lowpass(noise(0.6), 200) * env(n, 0.001, 0.08, 5) * 2.0
    save("announce_head", mix(crack, ping * 0.7, thump), peak=0.8)


if __name__ == "__main__":
    build()
