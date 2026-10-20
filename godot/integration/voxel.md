Merged and live (18 Oct, at the owner's request): main.gd installs it, the web preset packs `*.vox`, godot-play/ rebuilt.
Default still pixel: F10, the "Chars" button, or `?voxel=blocks` on the live link.

Status: done (Jared, Tornado Tyson, Gothica and the four enemies in blocks; tests 73/73, and the fight, lobby and
arcade suites pass with the install line in both modes)

Jared: ready for review (screenshots in `integration/voxel_shots/`, see "Screenshots" below)

Sprite maker blocks: done (18 Oct, branch `claude/sprite-maker-blocks`; see "Block characters from the sprite maker"
below, screenshots `integration/voxel_shots/sprite_maker_*.png`)

## The PC voxel arena test (20 Oct, PLAN.md "PC only, voxel destruction")

Download (Windows): `downloads/SmashedVoxelArena-win64.zip` on this branch (`claude/godot-voxel`): one exe, no install
(Windows SmartScreen: More info, Run anyway). Built from `scripts/voxel/arena/voxel_arena.tscn` with the desktop
renderer (Forward+), via the export presets "Windows Voxel Arena" / "Linux Voxel Arena" (custom feature
`voxel_arena`: `project.godot` picks that scene and Forward+ for it; the main game and the web build are unchanged).

- Block enemies one at a time (the owner, 20 Oct; F3 / F5 send in more; grunt, swarmer, brute, batter, about 1.7-2.2 m tall, 2.3 cm cubes = one sprite pixel a
  cube; F2 switches to two pixels a cube) come at you. Blaster (left click, 10 a second, holes about 4 cubes wide)
  and shotgun (right click, 9 pellets).
- **A hole exactly where each shot lands**: the shot is traced into the body part's voxel grid (the ray turned into
  that bone's rest space, stepped cell by cell), the cubes in a ball round the hit are knocked out and fly (a
  MultiMesh of up to 8000 cubes in one draw call, bouncing and settling, gone after 4-7 s); inside is flesh, bone
  down the limbs and a skull round the head. A limb hit 1-3 times comes off (with what hangs from it) without killing (the
  owner, 20 Oct): one leg off and they limp, both and they crawl on their arms; only head, chest and hip hits take
  health (the head most). F6: can't die at all. Walking: the step is scaled to each kind's leg length so the feet
  keep up with the ground (they skated before), arms swing against the legs. The dead topple and lie 12 s.
- Each body part is its own mesh on its bone (BoneAttachment3D, no skinning), so a hit re-meshes only that part, on a
  worker thread (WorkerThreadPool, 12 at a time); fresh enemies share ready-made meshes until they're shot.
- V: top-down (Juicy Jared in blocks in the middle, aim with the mouse); first person otherwise. F1 shadows, F3 +10
  enemies, F4 freeze, F5 a wave of 40. Top left: fps, ms a frame, the arena's own code time, draw calls,
  triangles, cubes flying, meshing jobs.
- Measured here (no GPU in the cloud, so only the CPU side counts): the arena's own code is about 1-3 ms a frame with
  20-50 enemies and ~1000 cubes flying; the worst frame (a new wave appearing) about 20 ms. The GPU side (a few
  hundred draw calls, 0.5-2 million triangles with shadows) is for the owner's RTX 4090 to judge.
- Tests: `test/voxel/logic_test.tscn` checks the tracing and holes (80/80); the arena's own self-test:
  `godot --path godot res://scripts/voxel/arena/voxel_arena.tscn -- --auto --secs=30 --stats` (or the built exe with
  `-- --auto --secs=30 --shot=out.png`). Screenshots: `voxel_shots/arena_fp1.png`, `arena_fp2.png`, `arena_td2.png`
  (software-rendered, so the fps there means nothing).

# Block (voxel) characters: integration note

Branch `claude/godot-voxel`. Owned files: `scripts/voxel/`, `assets/voxel/`, `test/voxel/`, this note,
`integration/voxel_shots/`. No existing file was edited.

The characters "recreated in voxel graphics but in the same style": hand-built block models with moving parts, made
from each character's own pixel art (one voxel per sprite pixel, the sprites' colours and outlines), rigged, animated
in code, and switched on with a setting **Characters: pixel / blocks** (default pixel until the owner approves).

## Install (for the main session, when merging)

1. In `scripts/main.gd`, at the end of `_ready()` (after `Net.install(self)`, before the `print`):
   ```gdscript
   	VoxelSwitch.install(self)           # Characters: pixel / blocks (F10, the HUD's "Chars" button)
   ```
2. In `export_presets.cfg`, the Web preset must pack the `.vox` files (they're plain files, like the JSON):
   ```
   include_filter="*.json,*.vox"
   ```
   Without it the web build has no models and every character just stays a picture (nothing breaks).

That's all. The switch finds every CharSprite (the player, player 2 on the keyboard or online, Gothica, the mirror's
reflection) by itself, now and as new ones appear.

## Using it

- **F10** or the HUD's **Chars: pixel / blocks** button (in the top row, after Sound) switches; kept in
  `user://smashed.cfg` (`[chars] look`). The web address can say `?voxel=blocks` (or `?voxel=pixel`); the
  command line `--voxel=blocks` after `--`.
- Input action added in code: `voxel_toggle` (F10).
- Characters with a model: Juicy Jared (`juicy` and all its weapon sheets), Tornado Tyson (`tyson2`: Jared's blocks
  recoloured the way the pictures are, `recolourImage`'s green and blue hue swaps), Gothica (`goth`: the lobby's
  wandering Gothica, Protect mode's, or playing as her) with her long hair and skirt as their own parts.
- **Enemies** (`VoxelEnemies`, added by the switch once a fight exists): grunt, swarmer, brute and the batter (with a
  nail bat: the wind-up lifts it back over his shoulder, the swing sweeps it across, the recovery follows through)
  stand in for EnemyView's pictures, facing where they walk, legs by their odo, white when hit. Gary the janitor,
  corpses and gore stay pictures. On the low look they're made at half detail.

## How it works

- **Models as data** (`assets/voxel/<char>/`): one MagicaVoxel `.vox` per part (head, hair_<style>, glasses, torso
  = the singlet, pelvis, arm/forearm/hand _l/_r, thigh/shin/foot _l/_r) plus `rig.json` (the bones, their pivots, which
  part hangs on which bone and where each grid sits). Open any part in MagicaVoxel to edit it; the game reads the
  files at run time (`VoxFile`, a small SIZE/XYZI/RGBA reader and writer). Weapons: `assets/voxel/weapons/`
  (spud gun, blaster, shotgun, nuke launcher), grip at the origin, barrel toward +z.
- **Built from the sprites** by `assets/voxel/tools/vox_build.py` (+ `chars.py`, the part tables; `preview.py` draws
  six views without Godot): each row of a part is the front frame's silhouette across (so from the front it's the
  pixel art pixel for pixel) and a depth range from the side frame (the head) or a written profile (torso, limbs),
  rounded; every surface voxel takes its colour from the frame that faces it (front, back, side, or the front's colour
  just inside its outline for the sides). Jared: front `juicy_spud/reload_0` (standing, arms down), side
  `juicy_spud/reload_side_1`, back `juicy_spud/back`. The right arm and leg are the left ones mirrored. Hair styles:
  each mirror style's front/side/back art (`scripts/lobby_life/art/bedroom/hair`) as a hull outside the bald head.
  Re-run: `python3 godot/assets/voxel/tools/vox_build.py all` (needs numpy and Pillow). Hand edits in MagicaVoxel are
  lost if the builder is re-run for that character, so once the owner edits a model, stop rebuilding it.
- **Meshes** (`VoxMesher`): greedy meshing (faces of one colour on one plane merge), vertex colours, all parts in one
  skinned mesh on a `Skeleton3D` (each vertex on its part's bone): **one draw call a character**, one material.
  Triangles (full / half detail): Jared 53k / 22k, Gothica 53k / 23k, grunt 13k / 6k, swarmer 11k / 5k, brute 15k / 7k,
  batter 14k / 6k.
- **Rig and animation** (`VoxelAnim`, all in code): idle breathing and a look round; walk/run from the sprite's odo
  (stride, the knees, the bob, the chest twist, arms swinging) with the stride's size from his measured speed; the
  dive roll (tucked, turning over once, the roll's hop); tumbling when thrown; the victory flex; holding each weapon
  (blasters: both arms aim and kick in turn; spud gun: the right arm aims; shotgun: two hands; launcher: on the right
  shoulder; fists: a guard, the jab), the reload, the potato wind-up and throw, bending to pick up; the lobby's poses
  (lying in bed, sitting at the table, swimming; also bench, leg press, lift, carry, carried, in VoxelAnim but not yet
  shown, see below). Facing turns smoothly (no 5-direction flips).
- **Hooked in** (`VoxelChar`, `VoxelSwitch`): a VoxelChar is added under each CharSprite and stands in for its
  picture: it reads what the sprite was told (char_id = the weapon sheet, facing, moving, odo, action, roll_t, the
  fight's frame keys for the weapon actions, modulate for the hit flash) and hides the picture (the contact shadow
  stays). Hanging under the sprite, whatever hides or scales the sprite (first person, the iframe blink, lobby
  pictures, the bonus room) does the same to the blocks. The weapon held comes from the fight's record (`Fight.me.f`,
  `f2`) when there is one, else from the sheet.
- **The look**: lit like the world's pictures on the high look (LookPass's picture normal, mostly, so the pixel art's
  drawn shading isn't fought by the light), the look's tint and lamps on the low look, which also gets **half-size
  blocks** (phones). The blocks **cast** sun shadows; they don't receive them (self-shadow acne on voxels in the
  Compatibility renderer). Seen from the top-down camera the body **leans back** toward the camera (half the camera's
  pitch), the way the pictures tip back, so the face and singlet read from up there; its depth is kept at the upright
  body's chest so it sorts against the world like the pictures. In first person nothing leans.
- **Mirror and wardrobe**: the hair style picks the hair part; the shirt picture is painted onto the singlet's front
  (and back) voxels, darkened by its folds as LobbyLook does on the pictures. The mirror's reflection is blocks too,
  pressed flat against the glass.

## Decisions (made for the owner; easy to change)

- Default **pixel** (as asked); F10 because F6-F9 are taken (clock skip, pad setup, look quality, mute).
- One voxel = one sprite pixel (0.0125 m), so the blocks are exactly as big as the picture.
- Built from the spud-gun sheet's frames (the look players see most: the lobby starts with the spud gun) and its
  camo-print singlet with JUICY JARED on the front; the plain blaster sheet's green singlet isn't separate.
- The lean toward the top-down camera (`VoxelChar.tip` = 0.5): without it a 3D body seen from 65 degrees up shows
  mostly the top of his head. 0 turns it off.
- Shadows cast but not received (see above). Lighting kept flat-ish, like the pictures.
- The gym's lifts keep lobby life's pictures: those pictures draw the machine and him together. Carrying Gothica is
  blocks (his arms out, hers lying across them; the lobby's carry picture and her hidden node are swapped for it).
- Tornado Tyson uses Jared's blocks recoloured (as his pictures are Juicy's recoloured); his recolour is per vertex in
  HSV (the shader's is HSL), close enough by eye.
- The fight's bullets and muzzle flashes still start where the pictures' barrel maps put them (a few pixels off the
  block guns at some angles).
- Sprites with no model (old-art sheets, Inky) are left as pictures.
- Gothica holds the fight's weapons in blocks (her pictures have no weapon sheets; with blocks her arms aim anyway).
- Enemies are built from their idle frames (the batter from his walk frame: his idle has the bat over his shoulder);
  one voxel per sprite pixel, so they're chunkier than the characters, as their pictures are. The batter's bat is
  built in code (a straight tapering club in the sprite's browns with grey nails) rather than cut from the diagonal
  sprite.

## Contract changes wanted

None needed. Nice to have: a public `CharSprite.picture()` (VoxelChar reaches the private `_spr` to hide it) and a
`LobbyLife` hook to replace a pose picture (VoxelSwitch hides `pose_of(p)` itself each frame).

## Testing

- Logic: `godot --headless --fixed-fps 60 --path godot res://test/voxel/logic_test.tscn` (65 checks: .vox round trip
  byte for byte, greedy mesh counts and winding, the model and rig, every pose, VoxelChar in the real game: the
  picture hidden, the weapon, walking, turning, switching back). Exit code 0 = all pass.
- CPU cost: `godot --headless --fixed-fps 60 --path godot res://test/voxel/perf_test.tscn`. First build of Jared's
  meshes ~0.45 s full, ~0.15 s half (desktop; a one-off when blocks first show); each block character ~0.1 ms a frame
  after that.
- Look: `test/voxel/voxel_view.tscn` is the real game with the blocks on and options from the address
  (`?vox=pair,face=0,weapon=shotgun,zoom=2`, `fp`, `jog`, `act=roll|victory`, `lobby=bed|sit`, `style=N`,
  `print`, `pixel`, `pairblocks`...; see the script's header). To build it for the web, in a copy of godot/: set
  `run/main_scene` to it, add `*.vox` to the include filter and drop `test/*` from the exclude filter, export.
- Existing tests re-run in a copy with the install line in `main.gd`, both as pictures and with `--voxel=blocks`:
  `test/combat/logic_test.tscn` 53/53, `test/lobby_life/run.tscn` 286/286, `scenes/arcade/arcade_test.tscn -- --logic`
  0 failed (all with `--fixed-fps 60`).

## Screenshots (`integration/voxel_shots/`)

Each top-down shot has the blocks Jared on the left and the pixel Jared (a copy of the same sprite) on the right.
First-person shots look at a blocks Jared standing in front of you. `overview.png` has them all on one page.

| file | what |
|---|---|
| `td_1x.png` | the whole lounge at 1x, blocks Jared (left of the pair) and the pixel one |
| `td_idle_spud.png` | standing with the spud gun (aimed at you: from above the arm points down the screen) |
| `td_run.png` | running (stride from his speed) |
| `td_blasters.png`, `td_shotgun.png`, `td_launcher.png`, `td_fists.png` | each weapon held |
| `td_roll.png`, `td_victory.png` | mid-roll, the victory flex |
| `td_hair_print.png` | the mirror's mohawk and a shirt picture, on both |
| `td_bed.png`, `td_sit.png` | lying in bed, sitting at the table (the lobby's poses) |
| `td_low_look.png` | the phones' low look: half-size blocks, the look's tint |
| `fp_front_blasters.png`, `fp_back.png` | first person: a blocks Jared from the front (blasters) and from behind |
| `fp_spud.png`, `fp_shotgun.png`, `fp_launcher.png`, `fp_fists.png` | first person, each weapon |
| `fp_run.png`, `fp_mullet.png` | first person: running, the mullet |
| `goth_td.png`, `goth_fp_front.png`, `goth_fp_back.png` | Gothica in blocks (playing as her) beside her picture; first person front and back |
| `td_carry.png` | carrying Gothica: both blocks |
| `enemies_wave.png`, `enemies_wave_pixel.png` | a wave in blocks (batters with bats, swarmers, brutes) and the same wave as pictures |

(Shot in the cloud's software-rendered browser, so the lighting is the high look at 7 am.)

## What's left

- The gym poses as blocks (needs the machines drawn without him); Gary the janitor; Inky.
- Frame times on a real phone (the cloud's browser has no GPU: everything, pictures included, runs at ~1 fps there).
  A full wave in blocks is ~20 skinned meshes (~250k triangles high, ~120k low): if a phone struggles, a lower
  detail for the low look (a third) is a one-line change in `VoxelMesher.downsample`'s use.
- The first switch to blocks builds the meshes (~0.4 s a character on desktop, more on the web): a one-off hitch.
- Mixamo / UniMate clips (the owner's ideas): the rig is a plain 16-bone humanoid, so clips made on it could be
  baked into VoxelAnim as extra moves (dances, deaths); the game-driven moves stay in code.

## Block characters from the sprite maker

`tools/sprite-maker.html` (the owner's page that turns one design picture into a character's sprite sheets) has a
**Blocks** card that makes the same thing `vox_build.py` makes for Jared, from the sheets the page already made:

- **Make blocks** carves the model (`tools/sprite-blocks.js`): the standing sheet's front frame cut into the same
  parts as Jared (head, torso, pelvis, arm/forearm/hand, thigh/shin/foot _l/_r: the arms, neck, waist and crotch found
  in the picture), each row rounded front to back with its depth from the side frame (a super-ellipse, as
  `add_shape`), so the head is round and the limbs round. Every surface block takes its colour from whichever frame
  (front, back, side, the diagonals; the right-facing ones flipped for the other side) looks at it most squarely and
  can see it, so the side-on face is on the side of the head and the clothes wrap round; hair that frames the face in
  front stays hair on the head's sides. A leg drawn lifted or an arm lost against the body is the other one
  mirrored. The rig is Jared's 15 bones with pivots found the same way (shoulder, elbow, wrist, hip, knee, ankle).
- **Size**: one block per sprite pixel, as Jared. The game draws the new art's 160 px frame 80 units (2 m) tall, so a
  160 px sprite makes a model about 150 blocks tall (Jared's are 150; the sprite maker draws everyone at Gothica's
  148 px). `rig.json` says `ref_sheet: goth` so the game sizes the blocks the way it sizes her pixels (0.0125 m).
- **Preview**: plain WebGL (no library): drag to spin, pinch or scroll to zoom, Stand / Walk / Attack (VoxelAnim's
  walk and the fists' jab, ported).
- **Painter** (touch-friendly): pick a part, look from the front, side or top, step through the layers; Add puts
  blocks on the layer, Paint / Remove / Pick work on the block you see; colours from the model and the design
  picture or any colour; mirror left/right; zoom; undo and redo. Or tick **Tap to paint** and use the tools on the
  3D model directly.
- **Cleaner views from Gemini** (optional): sends the design and the standing turnaround and asks for straight
  front, side and back views with the arms and legs apart (Copy prompt and Use my own picture work without a key);
  Make blocks then carves from those.
- **Download for the game** adds a `voxel` field to the same JSON: `{format: "smashed-blocks-1", rig: <rig.json>,
  files: {"head.vox": <base64>, ...}}`. `tools/add_character.py` ignores it (Smashed.html is unchanged by it).
- **Open a downloaded .json** (in "The character") brings a character's sheets and blocks back to carry on.

### Putting one in the Godot game

```
python3 tools/add_godot_character.py inky.json           # --check to just look; --godot DIR for another copy
```

writes `godot/assets/voxel/<id>/` (`rig.json` and a `.vox` per part, exactly like Jared's) and her pictures to
`godot/assets/CHARS/<id>/sprites/` with her entry in `assets/manifest.json`'s CHARS (like Inky's). `VoxelModel` finds
the blocks by the character's id (`model_for_sheet`), so any CharSprite showing her sheet is blocks when the game is set
to blocks (F10). Nothing else changes; she isn't added to a character menu (`CharFrames.PLAYABLE`, and `NEW_ART` for
her pictures' size, are the Characters task's lists). Look at her in `test/voxel/voxel_view.tscn` with
`?vox=char=<id>` (or `--vox=char=<id>`). Each part is a normal MagicaVoxel file, so it can be edited there too.

### Tests

- `node tools/test/sprite_blocks_shots.js [out dir]`: the page on a 390 x 844 touch phone in headless Chromium,
  with a test character made from Juicy Jared's sprites (`godot/assets/CHARS/juicy/sprites`; `CHAR=goth` for
  Gothica's): opens it as a .json, makes the blocks, screenshots the preview from four sides plus walking and
  attacking, paints a block with a tap (mirror on: 2 blocks), undo / redo, screenshots the painter and the card, and
  downloads the game JSON (`$JSON_OUT`). No page errors.
- `tools/add_godot_character.py` on that download into a copy of godot/, then `tools/test/godot_blocks_check.gd`
  (in a one-node scene, headless): the model loads, the same 15 bones as Jared, the same block size (0.0125 m), 1.87 m
  tall like Jared, a 48k-triangle mesh, the player set to that character gets the blocks and walks: 9/9.
- `tools/add_character.py` on the same download (into a copy of Smashed.html): adds the character as before.

| file | what |
|---|---|
| `sprite_maker_front.png`, `_side`, `_back`, `_diag` | the test Jared's blocks from four sides (made from his run-and-gun sheet: his blasters come along) |
| `sprite_maker_walk.png`, `sprite_maker_attack.png` | walking, the jab |
| `sprite_maker_card_phone.png`, `sprite_maker_painter_phone.png` | the card and the painter on a phone |

Known limits: carved from single frames, so what a picture hides (inside the arms, under hair) is a guess; a
character holding something in its standing frame gets it in its hands (the test Jared's blasters); long hair over
the shoulders is carved into the body and arms (paint it, or ask Gemini for the cleaner views).
