# Makes the farm's pictures from tools/strains.py (the six strains' four growth stages) plus a few icons.
# Run from the repo root: python3 godot/assets/farm/make_sprites.py
import os, sys
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'tools'))
from strains import STRAINS, plant
W, H = 44, 64
sheet = Image.new('RGBA', (W * 4, H * len(STRAINS)), (0, 0, 0, 0))
for i, st in enumerate(STRAINS):
    for k in range(4):
        im = plant(st, k)
        sheet.alpha_composite(im, (k * W, i * H))
sheet.save(os.path.join(HERE, 'strains.png'))
# icons, 16 x 16 pixel art (drawn at 1x, shown big with nearest filtering)
def icon(name, draw):
    im = Image.new('RGBA', (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im); draw(d); im.save(os.path.join(HERE, name + '.png'))
def seed(d):
    d.rectangle([3, 1, 12, 14], fill=(239, 228, 198)); d.rectangle([3, 1, 12, 14], outline=(120, 100, 70))
    d.rectangle([4, 5, 11, 13], fill=(79, 154, 60)); d.rectangle([7, 6, 8, 12], fill=(180, 236, 132)); d.rectangle([5, 8, 10, 9], fill=(180, 236, 132))
def bud(d):
    d.ellipse([3, 1, 12, 15], fill=(79, 138, 58), outline=(40, 70, 30))
    for x, y in ((5, 4), (8, 9), (6, 12), (9, 5)): d.point((x, y), fill=(214, 235, 176))
    for x, y in ((9, 3), (5, 8), (8, 13), (10, 10)): d.point((x, y), fill=(226, 138, 62))
def can(d):
    d.rectangle([4, 6, 12, 14], fill=(147, 160, 172), outline=(86, 97, 108)); d.rectangle([4, 6, 12, 7], fill=(195, 204, 213))
    d.line([4, 9, 0, 4], fill=(86, 97, 108), width=2); d.rectangle([0, 2, 2, 4], fill=(86, 97, 108)); d.arc([5, 1, 11, 9], 180, 360, fill=(86, 97, 108))
def drop(d):
    d.polygon([(8, 1), (12, 9), (10, 13), (6, 13), (4, 9)], fill=(124, 200, 255), outline=(40, 90, 140))
    d.point((7, 7), fill=(230, 245, 255))
def bag(col):
    def f(d):
        d.polygon([(3, 3), (12, 3), (13, 15), (2, 15)], fill=(196, 168, 120), outline=(110, 86, 52))
        d.rectangle([4, 7, 11, 12], fill=col); d.line([3, 3, 12, 3], fill=(150, 120, 80))
    return f
def joint(d):
    d.line([2, 12, 12, 4], fill=(240, 236, 224), width=3); d.point((13, 3), fill=(255, 140, 60)); d.point((12, 3), fill=(220, 80, 40))
    d.point((14, 1), fill=(200, 200, 200)); d.point((13, 0), fill=(170, 170, 170))
def coin(d):
    d.ellipse([2, 2, 13, 13], fill=(246, 209, 122), outline=(150, 110, 40)); d.text((5, 2), '$', fill=(120, 80, 20))
icon('seed', seed); icon('bud', bud); icon('can', can); icon('drop', drop); icon('joint', joint); icon('coin', coin)
icon('fert_basic', bag((120, 170, 80))); icon('fert_premium', bag((80, 130, 200))); icon('fert_super', bag((220, 90, 200)))
print('wrote', HERE)

# the sounds (the HTML game's farmFx: filtered noise bursts and tones made in code), as small WAVs
import wave, struct, math, random
def wav(name, samples, rate=22050):
    with wave.open(os.path.join(HERE, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s)) * 32000)) for s in samples))
def noise(dur, f0, f1, vol, q=1.0, rate=22050):
    # a noise burst through a swept resonant band-pass, fading out
    random.seed(name_seed[0]); out = []; y1 = y2 = 0.0; n = int(dur * rate)
    for i in range(n):
        t = i / n; f = f0 + (f1 - f0) * t; w0 = 2 * math.pi * f / rate; al = math.sin(w0) / (2 * q)
        b0, a0, a1, a2 = al, 1 + al, -2 * math.cos(w0), 1 - al
        x = random.uniform(-1, 1); y = (b0 * x - a1 * y1 - a2 * y2) / a0; y2, y1 = y1, y
        out.append(y * vol * 6 * (1 - t) ** 2 * min(1, i / (0.005 * rate)))
    return out
def tone(dur, f0, f1, vol, kind='sq', rate=22050):
    out = []; ph = 0.0; n = int(dur * rate)
    for i in range(n):
        t = i / n; ph += 2 * math.pi * (f0 + (f1 - f0) * t) / rate
        v = (1 if math.sin(ph) > 0 else -1) if kind == 'sq' else (2 / math.pi) * math.asin(math.sin(ph))
        out.append(v * vol * (1 - t))
    return out
name_seed = [1]
wav('snd_plant', noise(0.14, 320, 110, 0.5))
name_seed[0] = 2; wav('snd_snip', noise(0.3, 4200, 2400, 0.35, 0.8))
name_seed[0] = 3; wav('snd_water', noise(0.8, 800, 1700, 0.3, 0.6))
name_seed[0] = 4; wav('snd_fill', noise(0.55, 1500, 700, 0.35, 1.2))
wav('snd_seed', tone(0.06, 880, 1320, 0.25) + tone(0.08, 1320, 1320, 0.2, 'tri'))
wav('snd_cash', tone(0.07, 1046, 1046, 0.22) + tone(0.12, 1568, 1568, 0.22) + [0.0] * 800 + tone(0.07, 1046, 1046, 0.18) + tone(0.14, 1568, 1568, 0.18))
wav('snd_smoke', noise(0.9, 600, 300, 0.25, 0.5))
print('sounds made')
