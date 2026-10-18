#!/usr/bin/env python3
"""Put a character made with sprite-maker.html into the Godot port (godot/), blocks and all.

    python3 tools/add_godot_character.py inky.json            (adds her, or replaces her files if she's already in)
    python3 tools/add_godot_character.py inky.json --check    (just says what's in the file)
    python3 tools/add_godot_character.py inky.json --godot DIR  (another copy of godot/)

What it writes (the way Jared's are loaded, see godot/integration/voxel.md):
  * the blocks, from the file's "voxel" field (the sprite maker's Blocks card): godot/assets/voxel/<id>/rig.json and
    one MagicaVoxel .vox per part. VoxelModel finds them by the character's id (VoxelModel.model_for_sheet: a sheet
    whose character has assets/voxel/<id>/rig.json shows as blocks when the game is set to blocks).
  * the pictures: godot/assets/CHARS/<id>/sprites/<key>.png (<key>_<n>.png for the runs) and the character's entry
    in godot/assets/manifest.json's CHARS, like Inky's, so a CharSprite can show her (pixel or blocks).
It doesn't add her to a character menu (the port's playable list is CharFrames.PLAYABLE); see her with the voxel
test scene: ?vox=char=<id> (test/voxel/voxel_view.tscn).
"""
import base64
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.normpath(os.path.join(HERE, '..', 'godot'))
PARTS = ['head', 'torso', 'pelvis', 'thigh_l', 'thigh_r', 'shin_l', 'shin_r', 'foot_l', 'foot_r',
         'arm_r', 'arm_l', 'forearm_r', 'forearm_l', 'hand_r', 'hand_l']
BONES = ['hips', 'chest', 'head', 'arm_r', 'forearm_r', 'hand_r', 'arm_l', 'forearm_l', 'hand_l',
         'thigh_l', 'shin_l', 'foot_l', 'thigh_r', 'shin_r', 'foot_r']


def vox_count(data):
    """Checks a .vox (as VoxFile reads it); returns (size, voxel count)."""
    if data[:4] != b'VOX ':
        raise ValueError('not a .vox')
    i, size, n = 8, None, None
    while i + 12 <= len(data):
        cid = data[i:i + 4]
        a, b = struct.unpack('<ii', data[i + 4:i + 12])
        body = data[i + 12:i + 12 + a]
        if cid == b'MAIN':
            i += 12
            continue
        if cid == b'SIZE':
            size = struct.unpack('<iii', body)
        elif cid == b'XYZI':
            n = struct.unpack('<i', body[:4])[0]
        i += 12 + a + b
    if size is None or n is None:
        raise ValueError('no SIZE / XYZI')
    return size, n


def data_url_png(u):
    m = re.match(r'data:image/png;base64,(.*)$', u, re.S)
    if not m:
        raise ValueError('not a PNG data URL')
    return base64.b64decode(m.group(1))


def main():
    args = sys.argv[1:]
    godot = GODOT
    if '--godot' in args:
        godot = os.path.abspath(args[args.index('--godot') + 1])
        del args[args.index('--godot'):args.index('--godot') + 2]
    files = [a for a in args if not a.startswith('--')]
    if not files:
        sys.exit(__doc__)
    ch = json.load(open(files[0], encoding='utf-8'))
    cid, name, sprites = ch['id'], ch['name'], ch.get('sprites', {})
    if not re.fullmatch(r'[a-z][a-z0-9_]*', cid):
        sys.exit('bad id: %r' % cid)
    vx = ch.get('voxel')
    blocks = {}
    if vx:
        if vx.get('format') != 'smashed-blocks-1':
            sys.exit('unknown voxel format: %r' % vx.get('format'))
        rig = vx['rig']
        bones = [b['name'] for b in rig['bones']]
        if sorted(bones) != sorted(BONES):
            sys.exit('the rig\'s bones aren\'t the game\'s: %s' % ', '.join(bones))
        for p in rig['parts']:
            data = base64.b64decode(vx['files'][p['file']])
            size, n = vox_count(data)
            if list(size) != list(p['size']):
                sys.exit('%s: size %s but rig.json says %s' % (p['file'], size, p['size']))
            blocks[p['file']] = (data, n)
        rig['char'] = cid
    total = sum(n for _, n in blocks.values())
    print('%s (%s): %d poses, %s' % (name, cid, len(sprites),
                                     '%d parts, %d blocks' % (len(blocks), total) if vx else 'no blocks (make them in the Blocks card)'))
    if '--check' in sys.argv:
        return

    # 1. the blocks
    if vx:
        d = os.path.join(godot, 'assets', 'voxel', cid)
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            if f.endswith('.vox') or f == 'rig.json':
                os.remove(os.path.join(d, f))
        for f, (data, _) in blocks.items():
            open(os.path.join(d, f), 'wb').write(data)
        with open(os.path.join(d, 'rig.json'), 'w') as f:
            json.dump(rig, f, indent=1)
        print('blocks: %s' % os.path.relpath(d, os.path.dirname(godot)))

    # 2. the pictures and the manifest entry
    if sprites:
        rel = 'assets/CHARS/%s/sprites' % cid
        d = os.path.join(godot, rel)
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            if f.endswith('.png'):
                os.remove(os.path.join(d, f))
        entry = {}
        for k, v in sprites.items():
            if isinstance(v, list):
                entry[k] = []
                for i, u in enumerate(v):
                    open(os.path.join(d, '%s_%d.png' % (k, i)), 'wb').write(data_url_png(u))
                    entry[k].append('%s/%s_%d.png' % (rel, k, i))
            else:
                open(os.path.join(d, k + '.png'), 'wb').write(data_url_png(v))
                entry[k] = '%s/%s.png' % (rel, k)
        mp = os.path.join(godot, 'assets', 'manifest.json')
        man = json.load(open(mp, encoding='utf-8'))
        was = cid in man['CHARS']
        man['CHARS'][cid] = {'name': name, 'scale': 1.0, 'sprites': entry}
        with open(mp, 'w', encoding='utf-8') as f:
            json.dump(man, f, indent=1)
        print(('replaced %s\'s pictures' if was else 'added %s\'s pictures') % name + ' (%s)' % rel)


if __name__ == '__main__':
    main()
