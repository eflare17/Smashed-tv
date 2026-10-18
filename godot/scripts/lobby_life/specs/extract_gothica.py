import re, base64, struct, sys, os
src = '/home/user/Smashed-tv/Smashed.html'
out = '/home/user/Smashed-tv/godot/scripts/lobby_life/art/gothica'
lines = open(src, encoding='utf-8').read().split('\n')
line = lines[9741 - 1]
assert line.startswith('const CARRY_FRAMES')
uris = re.findall(r'data:image/png;base64,([A-Za-z0-9+/=]+)', line)
names = ['carry_stand.png', 'carry_stride.png', 'carry_squat.png']
assert len(uris) == 3, len(uris)
for n, b in zip(names, uris):
    d = base64.b64decode(b)
    w, h = struct.unpack('>II', d[16:24])
    open(os.path.join(out, n), 'wb').write(d)
    print(n, w, h, len(d))
