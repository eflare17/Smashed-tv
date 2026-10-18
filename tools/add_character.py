#!/usr/bin/env python3
"""Put a character made with sprite-maker.html into Smashed.html.

    python3 tools/add_character.py inky.json            (adds her, or replaces her art if she's already in)
    python3 tools/add_character.py inky.json --check    (just says what's in the file and what's missing)

It fills in the five places the game lists characters:
  CHARS (the art), CHAR_IDS (the order sent over the network: new ones go on the end so old
  numbers don't change), NEW_ART (160px art, same flips as Juicy: side faces right, diagonals
  down-right and up-right), BARREL_SETS (her gun barrel spots, calibrated in game), and both
  character dropdowns.
"""
import json, re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(HERE, '..', 'Smashed.html')
# everything Gothica has: the game falls back to a coloured box for any pose that's missing
NEEDED = ['front_run', 'diag_run', 'side_run', 'bdiag_run', 'back_run',
          'front_a', 'front_b', 'diag_a', 'diag_b', 'side_a', 'side_b', 'bdiag_a', 'bdiag_b', 'back_a', 'back_b', 'back',
          'roll1', 'roll2', 'roll3', 'roll4', 'victory']


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args:
        sys.exit(__doc__)
    ch = json.load(open(args[0], encoding='utf-8'))
    cid, name, sprites = ch['id'], ch['name'], ch['sprites']
    if not re.fullmatch(r'[a-z][a-z0-9_]*', cid):
        sys.exit('bad id: %r' % cid)
    missing = [k for k in NEEDED if k not in sprites]
    print('%s (%s): %d poses%s' % (name, cid, len(sprites), ', missing: ' + ', '.join(missing) if missing else ', all there'))
    if '--check' in sys.argv:
        return

    s = open(GAME, encoding='utf-8').read()

    # 1. the art
    m = re.search(r'const CHARS = ', s)
    start = m.end()
    chars, end = json.JSONDecoder().raw_decode(s, start)
    was = cid in chars
    chars[cid] = {'name': name, 'scale': 1.0, 'sprites': sprites}
    s = s[:start] + json.dumps(chars) + s[end:]

    # 2-4. the lists
    def add_to(pattern, after=None):
        nonlocal s
        m = re.search(pattern, s)
        if not m:
            sys.exit('could not find ' + pattern)
        body = m.group(2)
        if re.search(r"'%s'" % cid, body):
            return
        if after and "'%s'" % after in body:
            body = body.replace("'%s'" % after, "'%s', '%s'" % (after, cid), 1)
        else:
            body = body.rstrip() + ", '%s'" % cid
        s = s[:m.start(2)] + body + s[m.end(2):]

    add_to(r"(const CHAR_IDS = \[)([^\]]*)")                  # on the end, so old numbers keep their meaning
    add_to(r"(const NEW_ART = new Set\(\[)([^\]]*)")
    add_to(r"(const BARREL_SETS = \[)([^\]]*)", after='goth')

    # 5. both dropdowns, just after Gothica
    opt = '<option value="%s">%s</option>' % (cid, name)
    if 'value="%s"' % cid not in s:
        n = s.count('<option value="goth">')
        s = s.replace('<option value="goth">Gothica (test)</option>',
                      '<option value="goth">Gothica (test)</option>\n    ' + opt)
        if n != 2:
            print('note: found %d Gothica dropdown entries (expected 2)' % n)

    open(GAME, 'w', encoding='utf-8').write(s)
    print(('replaced %s\'s art' if was else 'added %s') % name)


if __name__ == '__main__':
    main()
