# Extract the machines' embedded art from Smashed.html (read only) to PNGs.
import re, base64, io, json, sys
from PIL import Image
HTML = '/home/user/Smashed-tv/Smashed.html'
OUT = '/home/user/Smashed-tv/godot/scripts/lobby_life/art/machines/'
lines = open(HTML, encoding='utf-8').read().split('\n')
def line_of(prefix):
    for i, l in enumerate(lines):
        if l.startswith(prefix): return i + 1, l
    sys.exit('missing ' + prefix)
def save(b64, name):
    im = Image.open(io.BytesIO(base64.b64decode(b64)))
    im.save(OUT + name)
    print(f'{name}\t{im.size[0]}x{im.size[1]}\t{im.mode}')
# SLOT_SPRITES / VEND_SPRITES: one JSON-ish object per line
for var, pre in [('SLOT_SPRITES', 'slot_'), ('VEND_SPRITES', 'vend_')]:
    n, l = line_of('const ' + var + ' = ')
    obj = json.loads(l[l.index('{'):l.rindex('}') + 1])
    for k, v in obj.items():
        save(v.split(',', 1)[1], pre + k + '.png')
# FP_BLASTER (first-person left blaster in hand; right one is its mirror)
n, l = line_of("FP_BLASTER.img.src = 'data:image/png;base64,")
save(l.split('base64,', 1)[1].rstrip("';"), 'fp_blaster_left.png')
# BOOT_PIX: pixel-art boot from code (procedural, 18 x 22)
s = '\n'.join(lines)
rows = re.findall(r"^\s*'([.KDHLEWGgSs]{18})',", s[s.index('const BOOT_PIX = ['):s.index('const BOOT_COL')], re.M)
col = {'K': '#141a24', 'D': '#2c3442', 'H': '#46505f', 'L': '#7a8698', 'E': '#1a2029', 'W': '#9aa3b0', 'G': '#5f6776', 'g': '#3e4552', 'S': '#f39461', 's': '#c9724d'}
im = Image.new('RGBA', (18, len(rows)), (0, 0, 0, 0))
for y, r in enumerate(rows):
    for x, ch in enumerate(r):
        if ch != '.': im.putpixel((x, y), tuple(int(col[ch][i:i + 2], 16) for i in (1, 3, 5)) + (255,))
im.save(OUT + 'fp_boot_pix.png'); print(f'fp_boot_pix.png\t18x{len(rows)}')
# the mushroom pickup (drawShroomPickup, bob=0, no glow), 1 px = 1 arena unit; origin x=52,y=424 -> (9,17) in this 18x19 image
im = Image.new('RGBA', (18, 19), (0, 0, 0, 0))
from PIL import ImageDraw
d = ImageDraw.Draw(im); ox, oy = 9, 17
def R(x, y, w, h, c): d.rectangle([ox + x, oy + y, ox + x + w - 1, oy + y + h - 1], fill=c)
R(-3, -8, 6, 9, '#e9dcc0'); R(-3, -8, 2, 9, '#c8b894')
R(-9, -12, 18, 5, '#b3202a'); R(-7, -15, 14, 3, '#b3202a'); R(-4, -17, 8, 2, '#b3202a')
R(-6, -15, 8, 2, '#e0414a'); R(-9, -8, 18, 1, '#7c141c')
for a in [(-5, -13, 2, 2), (2, -15, 2, 2), (5, -11, 2, 2), (-8, -10, 2, 1)]: R(*a, '#fff6ea')
im.save(OUT + 'shroom_pickup.png'); print('shroom_pickup.png\t18x19 (anchor 9,17 = SHROOM_SPOT)')
