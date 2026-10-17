import re, base64, json, os, struct, sys
HTML = '/home/user/Smashed-tv/Smashed.html'
OUT = '/home/user/Smashed-tv/godot/scripts/lobby_life/art/gym'
os.makedirs(OUT, exist_ok=True)
lines = open(HTML, encoding='utf-8').read().split('\n')
def L(n): return lines[n-1]
def b64s(line): return re.findall(r"([A-Za-z0-9+/=]{200,})", line)
def save(name, b):
    data = base64.b64decode(b)
    open(os.path.join(OUT, name), 'wb').write(data)
    w, h = struct.unpack('>II', data[16:24])
    print(f'{name}\t{w}x{h}')
# bench press frames (also in godot/assets/misc/line786_0.png..789)
for i, n in enumerate(range(786, 790)):
    save(f'bench_press_frame{i}.png', b64s(L(n))[0])
save('bench.png', b64s(L(791))[0])
save('plate_tree_rack.png', b64s(L(792))[0])
save('barbell.png', b64s(L(793))[0])
pl = b64s(L(794))  # L, M, S order in source
for s, b in zip('LMS', pl): save(f'plate_{s}.png', b)
save('collar.png', b64s(L(795))[0])
# ART_B64 dict on line 1037
m = re.search(r'const ART_B64 = (\{.*?\});', L(1037))
art = json.loads(m.group(1))
ren = {'legplate-L.png':'legplate_L.png','legplate-M.png':'legplate_M.png','legplate-S.png':'legplate_S.png',
       'legpress.png':'legpress_machine.png','legpress-base.png':'legpress_base.png','legpress-sled.png':'legpress_sled.png'}
for k in sorted(art):
    if k.startswith('leg'):
        save(ren.get(k, k.replace('legpress-', 'legpress_frame').replace('-', '_')), art[k])
