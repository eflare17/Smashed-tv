import json, base64, struct, os, re, sys
SRC = '/home/user/Smashed-tv/Smashed.html'
OUT = '/home/user/Smashed-tv/godot/scripts/lobby_life/art/bedroom'
os.makedirs(OUT + '/hair', exist_ok=True)
L = open(SRC, encoding='utf-8').read().split('\n')
def obj(line):
    l = L[line - 1]; return json.loads(l[l.index('{'):l.rindex('}') + 1])
def size(b): return struct.unpack('>II', b[16:24])
rows = []
def save(name, b, note):
    assert b[:4] == b'\x89PNG'
    open(os.path.join(OUT, name), 'wb').write(b)
    rows.append((name, size(b), note))
art = obj(1037)
for src, dst, note in [('wardrobe-0.png', 'wardrobe_0_shut.png', 'WARD_ART[0] doors shut (k<=0)'),
                       ('wardrobe-1.png', 'wardrobe_1_one_door.png', 'WARD_ART[1] one door open (0<k<1)'),
                       ('wardrobe-2.png', 'wardrobe_2_both_open.png', 'WARD_ART[2] both doors open (k>=1)'),
                       ('bedroom.png', 'bedroom_floor.png', 'BED_ART: whole bedroom floor incl. bed/nightstand/rug, drawn stretched to BEDROOM rect 440x342')]:
    save(dst, base64.b64decode(art[src]), note)
hair = obj(1418)
for line, key in [(1421, 'tyson'), (1424, 'mohawk'), (1426, 'mohawk_blue'), (1427, 'mohawk_purple'), (1428, 'mohawk_green')]:
    hair[key] = obj(line)
anchors = {}
for style, views in hair.items():
    anchors[style] = {}
    for view, (ax, ay, uri) in views.items():
        b = base64.b64decode(uri.split(',', 1)[1])
        name = f'hair/{style}_{view}.png'
        save(name, b, f'HAIR_ART.{style}.{view}, anchor at=[{ax},{ay}] (run-frame-0 px)')
        anchors[style][view] = {'at': [ax, ay], 'file': name, 'size': list(size(b))}
fit = obj(1447)
beards = []
for l in L[1429:1438]:
    m = re.search(r"key: '(\w+)',\s*label: '([^']+)'(, face: true)?", l)
    if m: beards.append({'key': m.group(1), 'label': m.group(2), 'face': bool(m.group(3))})
head = {'front': [48.5, 9, 53, 19], 'diag': [53.5, 9, 53, 19], 'side': [60.5, 9, 51, 19.5], 'back': [47, 9, 46, 17], 'bdiag': [51, 9, 47, 18]}
json.dump({'BEARDS': beards, 'HAIR_ART': anchors, 'HAIR_HEAD': head, 'HAIR_HEAD_fields': 'centre x, top, bottom, half width (run frame 0 px)',
           'HAIR_FIT': fit, 'HAIR_FIT_fields': '"<charId>.<key>.<frameIndex>": [s, ox, oy]: head in frame = offset + s * run frame 0'},
          open(OUT + '/hair_data.json', 'w'), indent=1)
for r in rows: print(r[0], '%dx%d' % r[1], '-', r[2])
print(len(fit), 'HAIR_FIT entries;', len(beards), 'styles')
