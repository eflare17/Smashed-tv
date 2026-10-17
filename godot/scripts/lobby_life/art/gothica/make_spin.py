# Gothica thrown (Smashed.html drawThrownGoth L10370): her front_run_0 picture turning about its middle, one
# frame every 22.5 degrees clockwise (goth_spin_00..15.png, 172x172); frame 04 is lying on her side.
from PIL import Image
import os
here = os.path.dirname(os.path.abspath(__file__))
src = Image.open(os.path.join(here, '../../../../assets/CHARS/goth/sprites/front_run_0.png')).convert('RGBA')
S = 172
for i in range(16):
    c = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    c.alpha_composite(src, ((S - src.width) // 2, (S - src.height) // 2))
    c.rotate(-22.5 * i, resample=Image.NEAREST).save(os.path.join(here, 'goth_spin_%02d.png' % i))
