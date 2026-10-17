import re, base64, struct, sys
SRC = '/home/user/Smashed-tv/Smashed.html'
OUT = '/home/user/Smashed-tv/godot/scripts/lobby_life/art/table/'
lines = open(SRC, encoding='utf-8').read().split('\n')
# (html line, name) ; one gymImg per line
want = {
  3489: 'bong', 3490: 'vape', 3491: 'torch_unused',
  5622: 'torch2',
  3520: 'sit_bong_0_hold', 3521: 'sit_bong_1_torch', 3522: 'sit_bong_2_pull', 3523: 'sit_bong_3_blow',
  5183: 'sit_idle_0_relaxed', 5184: 'sit_idle_1_breathe', 5185: 'sit_idle_2_relaxed', 5186: 'sit_idle_3_look',
  4997: 'trip_mantis_0', 4998: 'trip_mantis_1', 4999: 'trip_mantis_2', 5000: 'trip_mantis_3',
}
for ln, name in sorted(want.items()):
    m = re.search(r"gymImg\('([A-Za-z0-9+/=]+)'\)", lines[ln - 1])
    if not m: print('NO IMAGE on line', ln, name); continue
    data = base64.b64decode(m.group(1))
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    w, h = struct.unpack('>II', data[16:24])
    open(OUT + name + '.png', 'wb').write(data)
    print(f'{ln}\t{name}.png\t{w}x{h}')
