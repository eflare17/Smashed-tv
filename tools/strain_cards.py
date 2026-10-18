# Stat cards for each strain: python3 tools/strain_cards.py  (writes strain-cards/*.png and strain-cards.png)
import os, sys, textwrap
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from strains import STRAINS, plant
OUT = sys.argv[1] if len(sys.argv) > 1 else 'strain-cards'
os.makedirs(OUT, exist_ok=True)
B = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'; N = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
TIER = {'Common': (190, 194, 204), 'Uncommon': (96, 214, 110), 'Rare': (96, 160, 255), 'Legendary': (255, 186, 64)}
# game numbers (all tunable): sell price per plant, time to grow alone, waves to grow, buds per plant, buff length, raid risk
GAME = {
 'Northern Lights':   dict(potency=4, price=40,  mins=4,  waves=2, yld=3, buff='1 wave',  raid='Low'),
 'Sour Diesel':       dict(potency=6, price=75,  mins=6,  waves=3, yld=3, buff='1 wave',  raid='Medium'),
 'Granddaddy Purple': dict(potency=6, price=80,  mins=6,  waves=3, yld=4, buff='1 wave',  raid='Medium'),
 'Blue Dream':        dict(potency=7, price=140, mins=9,  waves=4, yld=3, buff='2 waves', raid='High'),
 'Acapulco Gold':     dict(potency=7, price=150, mins=10, waves=4, yld=2, buff='2 waves', raid='High'),
 'White Widow':       dict(potency=9, price=300, mins=15, waves=6, yld=2, buff='2 waves', raid='Very high'),
}
EFFECT = {
 'Northern Lights':   'Heals 2 health when you smoke it.',
 'Sour Diesel':       '+25% run speed and +25% fire rate.',
 'Granddaddy Purple': 'Take 40% less damage, but move 15% slower.',
 'Blue Dream':        'Enemies move and shoot at 70% speed.',
 'Acapulco Gold':     'Every kill drops double cash.',
 'White Widow':       '+60% damage, and the screen goes trippy.',
}
FACT = {
 'Northern Lights':   'One of the most famous indicas of all time. It came out in the 1980s and is a parent of loads of modern strains.',
 'Sour Diesel':       'Named for its sharp, fuel-like smell. It turned up on the US East Coast in the early 1990s.',
 'Granddaddy Purple': 'Bred in California in the early 2000s and famous for its deep purple leaves and buds.',
 'Blue Dream':        'A Californian cross of Blueberry and Haze, and one of the most popular strains in the US in the 2010s.',
 'Acapulco Gold':     'An old sativa from around Acapulco, Mexico, legendary since the 1960s for its golden buds.',
 'White Widow':       'A Dutch hybrid from the 1990s, named for the white coat of crystals that covers its buds.',
}
def card(st):
    g = GAME[st['name']]; tc = TIER[st['tier']]
    W, H = 340, 572
    im = Image.new('RGB', (W, H), (18, 20, 26)); d = ImageDraw.Draw(im)
    d.rounded_rectangle([3, 3, W - 4, H - 4], 16, fill=(28, 31, 40), outline=tc, width=4)
    fT = ImageFont.truetype(B, 22); fS = ImageFont.truetype(B, 13); fN = ImageFont.truetype(N, 12); fV = ImageFont.truetype(B, 14)
    d.text((W // 2, 30), st['name'].upper(), font=fT, fill=(255, 255, 255), anchor='mm')
    d.text((W // 2, 54), st['type'] + '  ·  ' + st['tier'], font=fS, fill=tc, anchor='mm')
    # the plant, ready to harvest, on dirt
    art = plant(st, 3); Z = 3
    bx0, by0, bw, bh = 40, 70, W - 80, 64 * Z + 8
    d.rounded_rectangle([bx0, by0, bx0 + bw, by0 + bh], 10, fill=(92, 64, 44))
    big = art.resize((art.width * Z, art.height * Z), Image.NEAREST)
    im.paste(big, (W // 2 - big.width // 2, by0 + 4), big)
    y = by0 + bh + 14
    # potency bar
    d.text((24, y), 'POTENCY', font=fS, fill=(200, 204, 214))
    for i in range(10):
        x = 120 + i * 19; on = i < g['potency']
        d.rectangle([x, y + 1, x + 14, y + 13], fill=tc if on else (52, 56, 68))
    y += 26
    rows = [('Sells for', '$%d a plant' % g['price']), ('Grows in', '%d min, or %d waves' % (g['mins'], g['waves'])),
            ('Buds per plant', str(g['yld'])), ('Buff lasts', g['buff']), ('Raid risk', g['raid'])]
    for k, v in rows:
        d.text((24, y), k, font=fN, fill=(170, 174, 186)); d.text((W - 24, y), v, font=fV, fill=(240, 240, 245), anchor='ra'); y += 21
    y += 6
    d.rounded_rectangle([18, y, W - 18, y + 46], 8, fill=(44, 38, 20) if st['tier'] == 'Legendary' else (34, 40, 52))
    d.text((28, y + 6), 'EFFECT', font=fS, fill=tc)
    d.text((28, y + 25), EFFECT[st['name']], font=fN, fill=(235, 235, 240))
    y += 58
    d.text((24, y), 'FUN FACT', font=fS, fill=(200, 204, 214)); y += 18
    for line in textwrap.wrap(FACT[st['name']], 46):
        d.text((24, y), line, font=fN, fill=(190, 194, 204)); y += 16
    return im
cards = [card(s) for s in STRAINS]
for s, c in zip(STRAINS, cards): c.save(os.path.join(OUT, s['name'].lower().replace(' ', '-') + '.png'))
sheet = Image.new('RGB', (3 * 350 + 10, 2 * 582 + 10), (14, 15, 20))
for i, c in enumerate(cards): sheet.paste(c, (10 + (i % 3) * 350, 10 + (i // 3) * 582))
sheet.save(OUT + '.png')
print('made', len(cards))
