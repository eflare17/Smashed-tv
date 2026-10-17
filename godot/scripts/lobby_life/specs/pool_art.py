import re, base64, hashlib, struct, zlib, os, sys
src = open('/home/user/Smashed-tv/Smashed.html').read().split('\n')
out = '/home/user/Smashed-tv/godot/scripts/lobby_life/art/pool'
os.makedirs(out, exist_ok=True)
def pngsize(b): return struct.unpack('>II', b[16:24])
# tower (line 766)
m = re.search(r"data:image/png;base64,([A-Za-z0-9+/=]+)", src[765])
tb = base64.b64decode(m.group(1))
open(os.path.join(out, 'dive_tower.png'), 'wb').write(tb)
fb = open('/home/user/Smashed-tv/godot/assets/TOWER_IMG_src.png','rb').read()
print('tower', pngsize(tb), 'same as assets file:', tb == fb)
# lounge size
m = re.search(r"data:image/webp;base64,([A-Za-z0-9+/=]+)", src[763])
lb = base64.b64decode(m.group(1)); fl = open('/home/user/Smashed-tv/godot/assets/LOUNGE_IMG_src.webp','rb').read()
print('lounge webp same as assets file:', lb == fl, len(lb))
# ducks from DUCK_ROWS (lines 5802-5818) and DUCK_LOOKS
rows = [re.search(r"'([^']+)'", src[i]).group(1) for i in range(5802, 5817)]
looks = {
 'yellow': {'K':'#3a2408','Y':'#ffd21f','y':'#e8a400','W':'#fff7b0','O':'#ff8a1e','o':'#d8621a','E':'#1c1410'},
 'black':  {'K':'#0e0a14','Y':'#2c2438','y':'#1a1422','W':'#6b5a86','O':'#8a2a52','o':'#5e1a38','E':'#e8e0f0'},
}
def writepng(path, w, h, px):
    raw = b''.join(b'\x00' + bytes(sum((px[y][x] for x in range(w)), ())) for y in range(h))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
for name, pal in looks.items():
    px = [[(0,0,0,0)] * 18 for _ in rows]
    for y, r in enumerate(rows):
        assert len(r) == 18, r
        for x, ch in enumerate(r):
            if ch != '.':
                c = pal[ch]; px[y][x] = (int(c[1:3],16), int(c[3:5],16), int(c[5:7],16), 255)
    writepng(os.path.join(out, f'duck_{name}.png'), 18, len(rows), px)
    print('duck', name, 18, len(rows))
