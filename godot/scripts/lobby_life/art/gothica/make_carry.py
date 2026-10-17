# Builds the composited carry frames the HTML game builds at load time (Smashed.html L9745-L9850):
#   carry_walk_0..6.png  Jared's side-run legs under the stride frame's upper body (carryWalkFrame)
#   carry_stand_c.png    the one of those with the narrowest feet (carryStandFrame)
#   carry_squat_m.png    the squat frame with his skin matched to his run art (matchSkin)
# Run:  python3 make_carry.py   (from this folder; reads ../../../../assets/CHARS/juicy/sprites)
from PIL import Image
import os
here = os.path.dirname(os.path.abspath(__file__))
juicy = os.path.join(here, '../../../../assets/CHARS/juicy/sprites')

def match_skin(im):
    im = im.convert('RGBA'); px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if not a or not (r > 170 and 80 < g < 185 and 40 < b < 150 and r > g + 30 and g > b + 10):
                continue
            px[x, y] = (min(255, round(r * 1.04)), min(255, round(g * 1.2)), min(255, round(b * 1.18)), a)
    return im

body = match_skin(Image.open(os.path.join(here, 'carry_stride.png')))
squat = match_skin(Image.open(os.path.join(here, 'carry_squat.png')))
squat.save(os.path.join(here, 'carry_squat_m.png'))
W, H, WAIST = 160, 185, 106

def walk(k):
    run = Image.open(os.path.join(juicy, 'side_run_%d.png' % k)).convert('RGBA')
    R = run.load(); B = body.load()
    gx = gn = 0; st = -1
    for y in range(run.height):
        n = 0
        for x in range(run.width):
            r, g, b, a = R[x, y]
            if not a: continue
            if y < run.height * 0.4 and b > 150 and g > 90 and r < 120 and b > r + 60:
                gx += x; gn += 1
            if y > 85 and 110 < r < 200 and b > r and b > 130 and abs(g - b) < 30:
                n += 1
        if st < 0 and n >= 6: st = y
    assert st >= 0
    gx = gx / gn if gn else run.width / 2
    dx = round(72 - gx); dy = WAIST - st
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0)); O = out.load()
    for y in range(st, run.height):
        for x in range(run.width):
            tx, ty = x + dx, y + dy
            if 0 <= tx < W and 0 <= ty < H and R[x, y][3]:
                r, g, b, a = R[x, y]; O[tx, ty] = (r, g, b, 255)
    skin = lambda p: p[0] > 180 and 90 < p[1] < 175 and p[2] < 140
    dark = lambda p: max(p[:3]) < 80 and p[3]
    for y in range(H):
        if y < WAIST:
            for x in range(W):
                p = B[x, y]
                if p[3]: O[x, y] = (p[0], p[1], p[2], 255)
            continue
        if y >= WAIST + 40: break
        cut = -1
        for x in range(W):
            p = B[x, y]
            if p[3] and skin(p): cut = x
        if cut < 0: continue
        x = cut + 3
        while x < W:
            if not dark(B[x, y]): x += 1; continue
            e = x
            while e < W and dark(B[e, y]): e += 1
            if e - x >= 5:
                for xx in range(x, e):
                    p = B[xx, y]; O[xx, y] = (p[0], p[1], p[2], 255)
            x = e
    return out

best = -1; bw = 1e9
for k in range(7):
    walk(k).save(os.path.join(here, 'carry_walk_%d.png' % k))
    run = Image.open(os.path.join(juicy, 'side_run_%d.png' % k)).convert('RGBA'); R = run.load()
    x0, x1 = 10**9, -1
    for y in range(run.height - 24, run.height):
        for x in range(run.width):
            if R[x, y][3]:
                x0 = min(x0, x); x1 = max(x1, x)
    if x1 - x0 < bw: bw = x1 - x0; best = k
print('stand frame uses run', best, 'width', bw)
Image.open(os.path.join(here, 'carry_walk_%d.png' % best)).save(os.path.join(here, 'carry_stand_c.png'))
