"""Turns the owner's recorded sounds (sounds/*.mp3, long takes) into the clips the game plays.

    python make_sounds.py            writes voxel-dozer-unity/Assets/Resources/Sounds/*.wav

The game (SoundBank.cs) plays a file from Resources/Sounds whenever there is one, and makes the sound in code when
there isn't.  Each take becomes one of:
  - a LOOP: the steadiest stretch of the take, with its end faded into its start so it goes round without a click;
  - ONE-SHOTS: single hits cut out of a take at the times listed (name_0.wav, name_1.wav ...); the game picks one
    at random each time.
The table below says which take makes which clip.  Needs ffmpeg (WinGet Gyan.FFmpeg); no other packages.
"""
import array, glob, math, os, subprocess, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'sounds')
OUT = os.path.join(HERE, '..', '..', 'voxel-dozer-unity', 'Assets', 'Resources', 'Sounds')
RATE = 48000

#  game sound      take                 kind     settings
LOOPS = [
    ('engine',      'engine.mp3',        dict(within=(0.2, 2.9), length=2.2, rms=0.20)),   # the idle at the start of the take
    ('engine_lug',  'engine.mp3',        dict(within=(6.4, 9.6), length=2.4, rms=0.22)),   # the loud, labouring middle
    ('tracks',      'tracks.mp3',        dict(length=4.0, rms=0.18)),
    ('dirt',        'blade.mp3',         dict(length=4.0, rms=0.20)),
    ('hydraulic',   'hydraulics.mp3',    dict(within=(0.6, 6.2), length=3.0, rms=0.14)),
    ('ripper',      'ripper.mp3',        dict(length=4.0, rms=0.20)),
    ('jackhammer',  'jackhammer.mp3',    dict(length=3.0, rms=0.20)),
    ('cart_roll',   'cart_rolling.mp3',  dict(length=4.0, rms=0.18)),
    ('tip_rumble',  'hopper_tip.mp3',    dict(within=(1.0, 6.0), length=3.0, rms=0.20)),
    ('mine_hum',    'ambience_mine.mp3', dict(length=20.0, rms=0.12)),
    ('wind',        'ambience_bush.mp3', dict(length=20.0, rms=0.12)),
]
SHOTS = [
    #  game sound      take               where in the take (seconds), one clip each      lowpass (0..1, 1 = as recorded)
    ('pick_rock',     'pick.mp3',         [(0.33, 1.6)],                                   1.0),
    ('pick_dirt',     'pick.mp3',         [(0.33, 0.9)],                                   0.15),   # the same hit, short and dulled: a thud into dirt
    ('shovel_scrape', 'shovel.mp3',       [(0.75, 1.15)],                                   1.0),
    ('shovel_whump',  'shovel.mp3',       [(10.4, 11.0)],                                  1.0),    # the shovelful landing
    ('clunk',         'rock_clunk.mp3',   [(0.0, 1.5)],                                    1.0),
    ('kaching',       'coins.mp3',        [(0.0, 1.4)],                                    1.0),
]
FADE = 0.25                                       # seconds folded over at a loop's join


def ffmpeg():
    hits = glob.glob(os.path.expandvars(r'%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe'))
    return hits[0] if hits else 'ffmpeg'


def load(name):
    raw = subprocess.run([ffmpeg(), '-v', 'error', '-i', os.path.join(SRC, name), '-ac', '1', '-ar', str(RATE), '-f', 's16le', '-'],
                         capture_output=True, check=True).stdout
    a = array.array('h'); a.frombytes(raw)
    return [x / 32768.0 for x in a]


def write(name, s):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-9, max(abs(x) for x in s))
    if peak > 0.97: s = [x * 0.97 / peak for x in s]
    data = array.array('h', [max(-32768, min(32767, int(round(x * 32767)))) for x in s]).tobytes()
    with open(os.path.join(OUT, name + '.wav'), 'wb') as f:
        f.write(b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVE')
        f.write(b'fmt ' + struct.pack('<IHHIIHH', 16, 1, 1, RATE, RATE * 2, 2, 16))
        f.write(b'data' + struct.pack('<I', len(data)) + data)


def rms(s):
    return math.sqrt(sum(x * x for x in s) / max(1, len(s)))


def envelope(s, win):
    n = int(win * RATE)
    return [rms(s[i:i + n]) for i in range(0, len(s), n)]


def make_loop(s, within=None, length=4.0, rms_to=0.2):
    a0, a1 = within if within else (0.3, len(s) / RATE - 0.3)
    a1 = min(a1, len(s) / RATE - 0.05)
    need = length + FADE
    if a1 - a0 < need: length = a1 - a0 - FADE; need = length + FADE
    # the steadiest stretch: the one whose loudness (0.1 s steps) varies least
    env = envelope(s, 0.1)
    best, best_at = 1e9, a0
    t = a0
    while t + need <= a1 + 1e-6:
        e = env[int(t / 0.1):int((t + need) / 0.1)]
        m = sum(e) / len(e)
        var = sum((x - m) ** 2 for x in e) / len(e) / max(1e-9, m * m)
        if var < best: best, best_at = var, t
        t += 0.1
    i0, n, f = int(best_at * RATE), int(length * RATE), int(FADE * RATE)
    seg = s[i0:i0 + n + f]
    out = seg[:n]
    for i in range(f):                               # equal-power fold of the tail into the head
        k = i / f
        out[i] = seg[i] * math.sin(k * math.pi / 2) + seg[n + i] * math.cos(k * math.pi / 2)
    g = rms_to / max(1e-9, rms(out))
    return [x * g for x in out], best_at


def cut(s, t0, t1):
    """The clip between t0 and t1, started just before the sound does (no silence first), faded out at the end."""
    h = s[int(t0 * RATE):min(len(s), int(t1 * RATE))]
    peak = max(1e-9, max(abs(x) for x in h))
    first = next((i for i, x in enumerate(h) if abs(x) > 0.02 * peak), 0)
    h = h[max(0, first - int(0.008 * RATE)):]
    fo = min(len(h) // 3, int(0.06 * RATE))
    for i in range(fo): h[len(h) - 1 - i] *= i / fo
    return h


def lowpass(s, k):
    y, o = 0.0, []
    for x in s: y += k * (x - y); o.append(y)
    return o


def main():
    for f in glob.glob(os.path.join(OUT, '*.wav')): os.remove(f)
    cache = {}
    def take(n):
        if n not in cache: cache[n] = load(n)
        return cache[n]
    for name, src, opt in LOOPS:
        if not os.path.exists(os.path.join(SRC, src)): continue
        loop, at = make_loop(take(src), opt.get('within'), opt['length'], opt['rms'])
        write(name, loop)
        print('loop  %-13s from %-18s %.1f-%.1f s' % (name, src, at, at + opt['length']))
    for name, src, windows, lp in SHOTS:
        if not os.path.exists(os.path.join(SRC, src)): continue
        hits = [cut(take(src), a, b) for a, b in windows]
        for i, h in enumerate(hits):
            if lp < 1.0: h = lowpass(lowpass(h, lp), lp)
            peak = max(1e-9, max(abs(x) for x in h))
            write('%s_%d' % (name, i), [x * 0.9 / peak for x in h])
        print('shots %-13s from %-18s %d hits (%s s)' % (name, src, len(hits), ', '.join('%.2f' % (len(h) / RATE) for h in hits)))


if __name__ == '__main__':
    main()
