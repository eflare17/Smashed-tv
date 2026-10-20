Merged and live (18 Oct, at the owner's request): main.gd installs it, the web preset packs `*.vox`, godot-play/ rebuilt.
Default still pixel: F10, the "Chars" button, or `?voxel=blocks` on the live link.

Status: done (Jared, Tornado Tyson, Gothica and the four enemies in blocks; tests 73/73, and the fight, lobby and
arcade suites pass with the install line in both modes)

Jared: ready for review (screenshots in `integration/voxel_shots/`, see "Screenshots" below)

Sprite maker blocks: done (18 Oct, branch `claude/sprite-maker-blocks`; see "Block characters from the sprite maker"
below, screenshots `integration/voxel_shots/sprite_maker_*.png`)

## The PC voxel arena test (20 Oct, PLAN.md "PC only, voxel destruction")

Download (Windows): `downloads/SmashedVoxelArena-win64.zip` on this branch (`claude/godot-voxel`): the exe and its .pck, no
install (Windows SmartScreen: More info, Run anyway). The game data is NOT embedded in the exe: Chrome flagged the
embedded build as a virus (a known false positive with embedded PCKs), so the exe is now Godot 4.4.1's own Windows
template byte for byte (SHA-256 b493c1d5...200f9a4b) and the game is in SmashedVoxelArena.pck beside it. Built from `scripts/voxel/arena/voxel_arena.tscn` with the desktop
renderer (Forward+), via the export presets "Windows Voxel Arena" / "Linux Voxel Arena" (custom feature
`voxel_arena`: `project.godot` picks that scene and Forward+ for it; the main game and the web build are unchanged).

- Block enemies one at a time (the owner, 20 Oct; F3 / F5 send in more; grunt, swarmer, brute, batter, about 1.7-2.2 m tall, 2.3 cm cubes = one sprite pixel a
  cube; F2 switches to two pixels a cube) come at you.
- **Weapons on the number keys** (the owner, 20 Oct; `voxel_loadout.gd`, `voxel_weapon_bar.gd`): 1 blaster, 2 shotgun,
  3 sword, 4 bat, 5 sledgehammer, 6 chainsaw, 7 spear, 8 vacuum (a melee weapon whose script isn't there is left out);
  the wheel cycles, Q goes back to the last one, E to the vacuum and back. Each uses both mouse buttons: blaster fire
  (10 a second, holes about 4 cubes wide) / aim in (zoom, tighter, slower look); shotgun fire (9 pellets) / both
  barrels (18, wider, longer reload); sword slash / chop; vacuum suck / right click held + wheel sizes the brush. A
  switch takes 0.25 s (the old one goes down, the new comes up; buttons held through it count for nothing till let go).
  The weapon bar along the bottom: each slot's number, a drawing, its name (the vacuum's with the cubes taken), the
  one out lit and taller, a cooldown filling its edge, and what the two buttons do above. In first person the game's
  own block blaster and shotgun are in your hands (kick when fired, closing in when aimed); top-down Jared holds the one
  out (two blasters, one a hand, as in the game). Melee weapons share `voxel_melee.gd` (press / hold / release, a view,
  a hand mesh, a drawing, checks) and `voxel_pieces.gd` (the bits cut off, as rigid bodies).
- **A hole exactly where each shot lands**: the shot is traced into the body part's voxel grid (the ray turned into
  that bone's rest space, stepped cell by cell), the cubes in a ball round the hit are knocked out and fly (a
  MultiMesh of up to 8000 cubes in one draw call, bouncing; once at rest they stay, in a second MultiMesh of up to
  150,000 that only changes when cubes are taken, so a covered floor costs nothing a frame); inside is flesh, bone
  down the limbs and a skull round the head. A limb hit 1-3 times comes off (with what hangs from it) without killing (the
  owner, 20 Oct): one leg off and they limp, both and they worm-crawl (hump up, stretch out, wiggle, moving in pulses); the chest and hips take health, ten
  times slower than at first (a grunt survives 30 chest shots); the head kills once a quarter of the brain (pink cubes
  inside the skull) is knocked out (a grunt took 39 blaster shots spread over his face). F6: can't die at all. Every hit staggers them (no pushing forward
  for about a third of a second, a shove back along the shot by how many cubes it took, the chest and head thrown
  back); after a stagger they push through for 0.6 s (hits only nudge), so held fire slows them but can't pin them. Walking: the step is scaled to each kind's leg length so the feet
  keep up with the ground (they skated before), arms swing against the legs. The dead topple and lie 12 s.
- **Sword** (the owner 20 Oct; `voxel_sword.gd`; slot 3: left click slashes the way the mouse was moving, still mouse
  back and forth, right click chops down, top-down a low sweep at the legs); F (or a mouse side button) slashes with
  any weapon out, C chops (the blade shows only while it swings). The slash is the plane through your eye along
  where you look and the swing; every cube within a cube of it, inside 2.6 m and the 160-degree sweep, is cut out
  (`VoxelBody.slice`), then whatever is no longer joined to its part's joint comes off as one rigid body with real
  meshes and boxes: an arm, half a forearm, the legs at the knee (then they crawl), the top of the head, the head
  (kills). A joint inside the cut keeps the side toward its parent, so a neck cut takes the whole head. A slash
  through the body takes a third of its health; cut through the middle, the top half comes off. A hit freezes the
  game for 70 ms (hit-stop). A cut costs 6-15 ms here (worker threads mesh the cut-off ends).
- **Bat** (slot 4, `voxel_melee_bat.gd`): blunt, never cuts. Left click a quick level swing: the nearest one in the
  arc takes a dent (the cubes fly), loses some health and is knocked flying (`VoxelBody.launch`: tumbling backward,
  lands, lies a moment, gets up; dead ones fly too). Hold right click to wind up a home run (0.95 s to full; it glows
  and shakes), let go: harder, further, a longer hit-stop; a full charge hits everyone in the arc and a full-charge
  hit on the head knocks it clean off (top-down: put the mouse on the top of the head).
- **Sledgehammer** (slot 5, `voxel_melee_hammer.gd`): crushing. Left click an overhead smash where you look: a round
  crater (`VoxelBody.carve`, a ball 0.17 m) in whatever it meets: a chest caved in, the top of a head (kills), an arm or
  leg knocked off where it lands; on the floor it throws the lying cubes back up. Right click a ground slam: a
  shockwave rings out 4.5 m and throws everyone it reaches up and away (nearer, harder) and down; lying cubes jump.
- **Chainsaw** (slot 6, `voxel_melee_chainsaw.gd`): grinding. Hold left: the bar goes out and about ten times a second
  grinds a thin kerf (a short `carve` capsule) out of every body it touches, so sweeping the mouse drags the cut
  through and saws off an arm, a leg, the head or the top half; in flesh the bar drags behind the mouse; the one being
  sawn is held, twitching; chips and blood spray. Right click lunges (every 1.5 s): thrown forward grinding, into the
  first one, then rips up out of them through the head.
- **Spear** (slot 7, `voxel_melee_spear.gd`): piercing. Left click a thrust: the tip's line (to 3.2 m) bores a thin
  tunnel through every body on it, two or three skewered at once; through the brain it kills, through a joint the limb
  comes off. Right click throws it (28 m/s): it bores through up to three bodies and sticks in the wall or floor where
  it lands; your hands are empty till right click again (or walking up to it) calls it back, boring through anyone in
  the way. With an enemy right up close the spear slides back through your grip.
- **Bodies can always be cut up** (the owner, 20 Oct): corpses stay (no longer gone after 12 s; past 40 lying about the
  oldest go). A cut-off piece that comes to rest (or is just rocking on the floor, after 1.5 s) is made a body again, a
  dead VoxelBody "fragment" with only its parts, each posed where it lay and never animated, so every weapon and gun
  goes on cutting it (a hand off the arm lying there, the lying top half in two); knocked flying (the bat, a slam) a
  fragment is a rigid piece again, and lies down a body again. The vacuum takes corpses and fragments too.
- Screenshots (software-rendered): `voxel_shots/melee_bat_flying.png`, `melee_hammer_crater.png`, `melee_hammer_slam.png`,
  `melee_chainsaw_lunge.png`, `melee_spear_thrust.png`.
- A last review of the shared code (cuts, weapon input, runtime) found 24 problems, all reproduced, fixed and checked
  again with the same probes: among them a crash at quit after F2 with meshing still running, Esc while holding a melee
  button leaving it held, the click that grabs the mouse also firing, a nick at the front of a knee taking the leg off,
  a chop down the middle keeping both halves, cubes coming to rest outside the walls, pieces knocked over the walls
  falling forever. The quick cut path and the full one give the same result over 2880 random cuts. Not fixed: shaving
  the side of a brute's chest at the shoulder can take that arm off.
- Each melee weapon's moves were built and then reviewed by a second pass that tried to break them (switching mid-move,
  the target freed mid-swing, F2, no bodies, dead bodies, holding forever, top-down with the mouse off the floor). Shared
  body fixes from that: a cut through the hips no longer takes the whole top half off (the root part never comes off
  whole); a cut next to a joint keeps the cubes still there; carve's health per cube scales with the cube's size (F2);
  a cut that can't have split a part skips the fill over the whole part (a chainsaw bite into the chest about 5 ms
  instead of 7-20); tiny bits left floating at a cut's edge fly off as cubes, not pieces.
- **Vacuum gun** (slot 8, or E; `voxel_vacuum.gd`), sucking like Astroneer's terrain tool (the owner, 20
  Oct): a see-through brush sphere sits where you point (the floor, a wall, or 6.5 m out), right click + the wheel
  sizes it (0.35-1.6 m). Hold click: the cubes inside it (lying or flying) come loose at 1500 a second, nearest the middle
  first, and swirl up a twisting beam into the nozzle, counted as resources by colour (blocks, meat, bone, brain; the
  HUD's last line); a cut-off piece in the brush comes apart and goes in too. Let go and the ones in the air fall.
- Each body part is its own mesh on its bone (BoneAttachment3D, no skinning), so a hit re-meshes only that part, on a
  worker thread (WorkerThreadPool, 12 at a time); fresh enemies share ready-made meshes until they're shot.
- V: top-down (Juicy Jared in blocks in the middle, aim with the mouse); first person otherwise. F1 shadows, F3 +10
  enemies, F4 freeze, F5 a wave of 40. Clicking in top-down no longer grabs the mouse (the aim stuck to the middle). Top left: fps, ms a frame, the arena's own code time, draw calls,
  triangles, cubes flying, meshing jobs.
- Measured here (no GPU in the cloud, so only the CPU side counts): the arena's own code is about 1-3 ms a frame with
  20-50 enemies and ~1000 cubes flying; the worst frame (a new wave appearing) about 20 ms. The GPU side (a few
  hundred draw calls, 0.5-2 million triangles with shadows) is for the owner's RTX 4090 to judge.
- Tests: `test/voxel/logic_test.tscn` checks the tracing, holes, sword cuts, vacuum, weapon slots, carve/launch and each melee weapon's own checks
  (193/193); `-- --meleetest=<id> --shots=dir [--topdown] [--headaim]` runs a weapon's left then right click on a
  standing grunt, saving frames; `-- --weaponshots=dir` takes every slot out, first person then top-down; `-- --swordtest=dir`
  slashes a standing grunt (an arm, the neck, the knees) then vacuums, saving frames; `-- --walkcheck=dir --legless`
  shows the worm crawl. The arena's own self-test:
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
