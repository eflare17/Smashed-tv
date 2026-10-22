#!/usr/bin/env python3
"""The trailer's music (made here, so it's ours to use): a cheery ukulele-and-glockenspiel tune in C at 120 bpm
(I-V-vi-IV), claps and a shaker coming in, a kick in the busy part; a tape stop and a record scratch at the boss
(SCRATCH_AT s), silence, a bright sting for the title (STING_AT s) and a soft tag for the last shot (TAG_AT s).
Writes a 44.1 kHz stereo WAV. Usage: make_music.py out.wav. Owned by the voxel session (godot/tools/trailer)."""
import sys
import wave
import numpy as np

SR = 44100
BPM = 120.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
SCRATCH_AT = 44.0
STING_AT = 48.5
TAG_AT = 52.5
LENGTH = 57.5

rng = np.random.default_rng(7)
N = int(LENGTH * SR)
L = np.zeros(N)
R = np.zeros(N)

def hz(note):
    names = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
    n, o = note[:-1], int(note[-1])
    return 440.0 * 2 ** ((names[n] + 12 * (o + 1) - 69) / 12.0)

def add(sig, t, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i >= N:
        return
    j = min(N, i + len(sig))
    s = sig[: j - i] * gain
    L[i:j] += s * (1.0 - max(0.0, pan))
    R[i:j] += s * (1.0 + min(0.0, pan))

def pluck(f, dur, bright=0.5):
    """Karplus-Strong: a plucked nylon string."""
    n = int(dur * SR)
    p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p)
    out = np.zeros(n)
    for k in range(n):
        out[k] = buf[k % p]
        nxt = buf[(k + 1) % p]
        buf[k % p] = (bright * buf[k % p] + (1 - bright) * nxt) * 0.996
    env = np.minimum(1.0, np.arange(n) / (0.002 * SR))
    return out * env

_pl = {}
def pluck_c(f, dur):
    key = (round(f, 2), dur)
    if key not in _pl:
        _pl[key] = pluck(f, dur)
    return _pl[key]

def bell(f, dur, decay=3.0):
    """A glockenspiel bar: a few inharmonic partials, ringing down."""
    t = np.arange(int(dur * SR)) / SR
    s = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 6)
         + 0.15 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 12))
    return s * np.exp(-t * decay) * np.minimum(1.0, t / 0.001)

def bass(f, dur):
    t = np.arange(int(dur * SR)) / SR
    s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)
    return s * np.exp(-t * 2.5) * np.minimum(1.0, t / 0.004)

def noise_hit(dur, decay, lp=0.5):
    n = int(dur * SR)
    x = rng.uniform(-1, 1, n)
    y = np.zeros(n)
    a = 0.0
    for k in range(n):        # a one-pole low/high-ish shaping
        a = a + lp * (x[k] - a)
        y[k] = x[k] - a if lp < 0.5 else a
    t = np.arange(n) / SR
    return y * np.exp(-t * decay)

CLAP = sum(noise_hit(0.25, 30, 0.7) * 0.5 for _ in range(1))
SHAKE = noise_hit(0.08, 60, 0.2)
def kick():
    t = np.arange(int(0.35 * SR)) / SR
    f = 50 + 90 * np.exp(-t * 25)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
KICK = kick()

CHORDS = {  # re-entrant ukulele voicings (G C E A strings)
    "C": ["G4", "C4", "E4", "C5"], "G": ["G4", "D4", "G4", "B4"], "Am": ["A4", "C4", "E4", "A4"], "F": ["A4", "C4", "F4", "A4"],
}
ROOT = {"C": "C2", "G": "G2", "Am": "A2", "F": "F2"}
PROG = ["C", "G", "Am", "F"]
MELODY = [  # per chord: (beat, note, length in beats)
    [(0, "E5", 0.5), (0.5, "G5", 0.5), (1, "C6", 1), (2, "G5", 0.5), (2.5, "E5", 0.5), (3, "D5", 0.5), (3.5, "E5", 0.5)],
    [(0, "D5", 0.5), (0.5, "G5", 0.5), (1, "B5", 1), (2, "G5", 0.5), (2.5, "D5", 0.5), (3, "C5", 0.5), (3.5, "D5", 0.5)],
    [(0, "C5", 0.5), (0.5, "E5", 0.5), (1, "A5", 1), (2, "E5", 0.5), (2.5, "C5", 0.5), (3, "B4", 0.5), (3.5, "C5", 0.5)],
    [(0, "A4", 0.5), (0.5, "C5", 0.5), (1, "F5", 1), (2, "A5", 1), (3, "G5", 1)],
]
STRUM = [0, 1, 1.5, 2.5, 3, 3.5]

def bar_part(b, t0, busy):
    ch = PROG[b % 4]
    for k, beat in enumerate(STRUM):
        st = t0 + beat * BEAT
        down = k % 2 == 0 or beat == 0
        notes = CHORDS[ch] if down else list(reversed(CHORDS[ch]))
        for i, nt in enumerate(notes):
            add(pluck_c(hz(nt), 1.0), st + i * 0.012, 0.16 if down else 0.11, -0.25)
    add(bass(hz(ROOT[ch]), BEAT * 1.9), t0, 0.32)
    add(bass(hz(ROOT[ch]), BEAT * 1.9), t0 + 2 * BEAT, 0.28)
    if b >= 2:
        for beat, nt, ln in MELODY[b % 4]:
            add(bell(hz(nt), ln * BEAT + 0.6), t0 + beat * BEAT, 0.22, 0.3)
    if b >= 4:
        for beat in (1, 3):
            add(CLAP, t0 + beat * BEAT, 0.2, 0.1)
        for k in range(8):
            add(SHAKE, t0 + k * BEAT / 2, 0.05 if k % 2 else 0.03, -0.4)
    if busy:
        for beat in range(4):
            add(KICK, t0 + beat * BEAT, 0.6)

# the tune: bars up to the scratch (the busy part from bar 14)
bars = int(SCRATCH_AT / BAR)
for b in range(bars):
    bar_part(b, b * BAR, b >= 14)

# the tape stop: the last 0.45 s before the scratch slowed to a halt, then a scratch, then nothing
i0, i1 = int((SCRATCH_AT - 0.45) * SR), int(SCRATCH_AT * SR)
for ch in (L, R):
    seg = ch[i0:i1].copy()
    n = len(seg)
    pos = np.cumsum(np.linspace(1.0, 0.0, n))
    pos = pos / pos[-1] * (n - 1) * 0.55
    ch[i0:i1] = np.interp(pos, np.arange(n), seg) * np.linspace(1.0, 0.2, n)
    ch[i1:] = 0.0
t = np.arange(int(0.32 * SR)) / SR
sweep = np.sin(2 * np.pi * np.cumsum(900 * np.exp(-t * 6) + 200 * np.sin(t * 40)) / SR)
scr = (sweep * 0.6 + rng.uniform(-1, 1, len(t)) * 0.25) * np.exp(-t * 7)
add(scr, SCRATCH_AT, 0.5)

# the title's sting: a strummed C, a rising glock arpeggio, a low hit
add(KICK, STING_AT, 0.9)
for i, nt in enumerate(["C4", "E4", "G4", "C5"]):
    add(pluck(hz(nt), 3.5), STING_AT + i * 0.02, 0.25, -0.2)
for i, nt in enumerate(["C5", "E5", "G5", "C6", "E6"]):
    add(bell(hz(nt), 3.0, 1.6), STING_AT + 0.1 + i * 0.09, 0.22, 0.25)
add(bass(hz("C2"), 3.5), STING_AT, 0.7)

# the tag: two soft bars, the tune's first phrase, ending on C
for b, ch in enumerate(["C", "F"]):
    t0 = TAG_AT + b * BAR
    for beat in (0, 2):
        for i, nt in enumerate(CHORDS[ch]):
            add(pluck_c(hz(nt), 1.0), t0 + beat * BEAT + i * 0.015, 0.12, -0.25)
    add(bass(hz(ROOT[ch]), BAR), t0, 0.35)
for beat, nt, ln in MELODY[0][:5]:
    add(bell(hz(nt), ln * BEAT + 0.6), TAG_AT + beat * BEAT, 0.18, 0.3)
add(bell(hz("C6"), 2.0, 2.0), TAG_AT + 2 * BAR, 0.2, 0.3)
for i, nt in enumerate(CHORDS["C"]):
    add(pluck(hz(nt), 2.0), TAG_AT + 2 * BAR + i * 0.02, 0.14, -0.2)

# out: a gentle limiter, -1 dB peak, a fade at the very end
mix = np.stack([L, R], axis=1)
mix = np.tanh(mix * 1.2) / np.tanh(1.2)
mix *= 0.89 / max(1e-6, np.abs(mix).max())
fade = int(0.8 * SR)
mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
pcm = (mix * 32767).astype(np.int16)
with wave.open(sys.argv[1] if len(sys.argv) > 1 else "trailer_music.wav", "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("wrote", LENGTH, "s")
