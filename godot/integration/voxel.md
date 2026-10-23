Merged and live (18 Oct, at the owner's request): main.gd installs it, the web preset packs `*.vox`, godot-play/ rebuilt.
Default still pixel: F10, the "Chars" button, or `?voxel=blocks` on the live link.

Status: done (Jared, Tornado Tyson, Gothica and the four enemies in blocks; tests 73/73, and the fight, lobby and
arcade suites pass with the install line in both modes)

Jared: ready for review (screenshots in `integration/voxel_shots/`, see "Screenshots" below)

Sprite maker blocks: done (18 Oct, branch `claude/sprite-maker-blocks`; see "Block characters from the sprite maker"
below, screenshots `integration/voxel_shots/sprite_maker_*.png`)

## The PC voxel arena test (20 Oct, PLAN.md "PC only, voxel destruction")

Download (Windows): `downloads/SmashedVoxelArena-win64.zip` on this branch (`claude/godot-voxel`): the exe, its .pck and
the WebRTC DLL (co-op), no install (Windows SmartScreen: More info, Run anyway). The game data is NOT embedded in the exe: Chrome flagged the
embedded build as a virus (a known false positive with embedded PCKs), so the exe is now Godot 4.4.1's own Windows
template byte for byte (SHA-256 b493c1d5...200f9a4b) and the game is in SmashedVoxelArena.pck beside it. Built from `scripts/voxel/arena/voxel_arena.tscn` with the desktop
renderer (Forward+), via the export presets "Windows Voxel Arena" / "Linux Voxel Arena" (custom feature
`voxel_arena`: `project.godot` picks that scene and Forward+ for it; the main game and the web build are unchanged).

- Block enemies one at a time (the owner, 20 Oct; F3 / F5 send in more; grunt, swarmer, brute, batter, about 1.7-2.2 m tall, 2.3 cm cubes = one sprite pixel a
  cube; F2 switches to two pixels a cube) come at you.
- **Weapons in groups on 1-5, as in Half-Life** (the owner, 20 Oct; `voxel_loadout.gd`, `voxel_weapon_bar.gd`):
  1 melee (sword, bat, sledgehammer, chainsaw, spear), 2 guns (pistol, shotgun, laser cutter), 3 special
  (flamethrower, freeze ray, harpoon gun, gravity gun), 4 explosives (grenade launcher), 5 the vacuum. A key takes out
  the one last used in its group; again steps to the next in it. The wheel cycles all of them, Q goes back to the last
  one, R reloads (or the weapon's own R move), E the vacuum and back. Every weapon uses both mouse buttons. A switch
  takes 0.25 s. The weapon bar along the bottom draws the groups under their keys, a drawing of each weapon, its rounds
  or fuel or heat, a cooldown filling its edge, and the one out's name and both buttons' moves above. Every weapon is a
  script on `voxel_melee.gd` (press / hold / release / step, a first-person view, a hand mesh for top-down, a drawing,
  sounds, headless checks); a weapon whose file isn't there is left out.
- **Sound** (`voxel_sound.gd`): every weapon has its sounds, made from noise and tones by
  `assets/voxel/tools/sfx.py` and one `sfx_<weapon>.py` each (rerun with `python3 -I`; they write
  `assets/voxel/sound/*.wav`); the pistol uses the game's own shots.
- **Pistol and shotgun, reworked** (the owner: "the pistol and shotgun need some work"; `voxel_gun.gd` and its two):
  the game's block guns with a clip (12) or a tube (6), R or firing empty reloads (the pistol's magazine drops out and a
  fresh one goes in; the shotgun loads shell by shell, a shot stops it), a muzzle flash and light, tracers from the
  muzzle, spent shells thrown out of the side that lie where they land. Pistol: held fire sprays wider (bloom), tapped
  shots land true; right click aims in. Shotgun: 9 pellets and a pump, holes smaller further off; up close it knocks
  them off their feet; right click is both barrels (18 pellets), and at point blank it blows a chunk out of them and
  throws them across the room.
- **Fire and ice** (`voxel_body.gd`, `voxel_flames.gd`): set alight, a body burns by itself, the fire spreading cube to
  cube, charring them black and burning them to ash (the burnt-off bits drop), hurting; a burning enemy panics and runs
  about flailing, not fighting. Frost slows them, then freezes them solid: an ice statue for 8 s that then thaws; the
  cold puts fire out. A frozen body shatters into ice cubes at any blow (a shot, a swing, being knocked flying, landing).
  An enemy knocked flying fast bowls over whoever it hits.
- **Flamethrower** (slot 3, `voxel_weapon_flamethrower.gd`): hold left for a 6 m stream of fire that sets alight
  everything it reaches (alive, dead or lying), a frozen one thawed first; a tank of 8 s that refills. Right click lobs
  a fire bomb: a patch of fire on the floor for 6 s that catches everyone standing or lying in it.
- **Freeze ray** (slot 3, `voxel_weapon_freezeray.gd`): hold left for a twisting cyan beam that freezes them solid in
  about 0.75 s. Right click fires an ice shard: into a statue it shatters it (and flies on to the next), into anyone
  else a small hole and more frost.
- **Laser cutter** (slot 2, `voxel_weapon_laser.gd`): hold left for a thin red beam that cuts right through along its
  line, so dragging it across them cuts a clean plane: limbs, heads, bodies in half; cauterised (few bits, glowing);
  5 s overheats it (R vents). Hold right to overcharge, then a fat beam through every body in line to the wall.
- **Harpoon gun** (slot 3, `voxel_weapon_harpoon.gd`): left click harpoons the first body and reels it in to stand
  staggering in front of you (corpses too); right click harpoons a limb or the head and yanks it off whole, flying back
  at you on the line. Top-down it aims at the body under the mouse.
- **Gravity gun** (slot 3, `voxel_weapon_gravity.gd`): left click grabs a piece, a corpse or a live enemy (flailing)
  and holds it in front of you; click again to throw it (a thrown body bowls the others over); right click drops it.
  Right click with nothing held fires a black hole: for 4.5 s it drags in every body near, lifting and spinning them,
  crushes the nearest bit by bit, swallows the pieces and the flying cubes, then bursts.
- **Grenade launcher** (slot 4, `voxel_weapon_grenades.gd`): left click a bouncing grenade (off at once on a body hit
  hard, else after 2.2 s); right click a sticky bomb that sticks to a wall, the floor or a body part (riding on it); R
  sets them all off one after another (with none out, R reloads the drum of six). The blast tears craters on the side
  facing it, limbs off at point blank, throws them, sets the near ones alight, shatters frozen ones.
- After the weapons (21 Oct): big craters cost half as much (a cut that leaves everything joined takes only its cubes
  out; 480 random cuts give the same results as before); burning bodies take their ash out cheaply (ten burning: 3-5 ms
  a frame, not 20-35); the laser cuts through a group swept across (lines queued per body); nothing goes through the
  pillars (walking enemies slide round them toward you; flying, dragged, held or pulled bodies are pushed out).
- Screenshots of the new weapons (software-rendered): `voxel_shots/weapon_flamethrower.png`, `weapon_freezeray_statue.png`,
  `weapon_freezeray_shatter.png`, `weapon_laser_cut_in_half.png`, `weapon_harpoon_head.png`, `weapon_gravity_black_hole.png`,
  `weapon_grenade_blast.png`, `weapon_hammer_side_swing.png`, `weapon_shotgun_both_barrels.png`. Each new weapon was built by
  one pass and then reviewed by a second that tried to break it (switching mid-move, targets freed, frozen or dead,
  top-down, cost); a review of the shared fire, ice and gun code found and fixed 16 more problems.
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
- **Sword** (the owner 20 Oct; `voxel_sword.gd`; slot 1: left click slashes the way the mouse was moving, still mouse
  back and forth, right click chops down, top-down a low sweep at the legs); F (or a mouse side button) slashes with
  any weapon out, C chops (the blade shows only while it swings). The slash is the plane through your eye along
  where you look and the swing; every cube within a cube of it, inside 2.6 m and the 160-degree sweep, is cut out
  (`VoxelBody.slice`), then whatever is no longer joined to its part's joint comes off as one rigid body with real
  meshes and boxes: an arm, half a forearm, the legs at the knee (then they crawl), the top of the head, the head
  (kills). A joint inside the cut keeps the side toward its parent, so a neck cut takes the whole head. A slash
  through the body takes a third of its health; cut through the middle, the top half comes off. A hit freezes the
  game for 70 ms (hit-stop). A cut costs 6-15 ms here (worker threads mesh the cut-off ends).
- **Bat** (slot 1, `voxel_melee_bat.gd`): blunt, never cuts. Left click a quick level swing: the nearest one in the
  arc takes a dent (the cubes fly), loses some health and is knocked flying (`VoxelBody.launch`: tumbling backward,
  lands, lies a moment, gets up; dead ones fly too). Hold right click to wind up a home run (0.95 s to full; it glows
  and shakes), let go: harder, further, a longer hit-stop; a full charge hits everyone in the arc and a full-charge
  hit on the head knocks it clean off (top-down: put the mouse on the top of the head).
- **Sledgehammer** (slot 1, `voxel_melee_hammer.gd`): crushing. Left click with the mouse moving sideways swings it
  that way (the owner: "can you make it so the sledge hammer can swing left and right"): a level sweep across the front
  that craters the first body it meets and throws it sideways across the room, bowling over whoever it lands on.
  Left click with the mouse still (or moving up or down) is an overhead smash where you look: a round
  crater (`VoxelBody.carve`, a ball 0.17 m) in whatever it meets: a chest caved in, the top of a head (kills), an arm or
  leg knocked off where it lands; on the floor it throws the lying cubes back up. Right click a ground slam: a
  shockwave rings out 4.5 m and throws everyone it reaches up and away (nearer, harder) and down; lying cubes jump.
- **Chainsaw** (slot 1, `voxel_melee_chainsaw.gd`): grinding. Hold left: the bar goes out and about ten times a second
  grinds a thin kerf (a short `carve` capsule) out of every body it touches, so sweeping the mouse drags the cut
  through and saws off an arm, a leg, the head or the top half; in flesh the bar drags behind the mouse; the one being
  sawn is held, twitching; chips and blood spray. Right click lunges (every 1.5 s): thrown forward grinding, into the
  first one, then rips up out of them through the head.
- **Spear** (slot 1, `voxel_melee_spear.gd`): piercing. Left click a thrust: the tip's line (to 3.2 m) bores a thin
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
- **Vacuum gun** (slot 5, or E; `voxel_vacuum.gd`), sucking like Astroneer's terrain tool (the owner, 20
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
  (336); `-- --meleetest=<id> --shots=dir [--topdown] [--headaim] [--swing=left|right] [--again] [--rkey]` runs a weapon's left then right click on a
  standing grunt, saving frames; `-- --weaponshots=dir` takes every slot out, first person then top-down; `-- --swordtest=dir`
  slashes a standing grunt (an arm, the neck, the knees) then vacuums, saving frames; `-- --walkcheck=dir --legless`
  shows the worm crawl. The arena's own self-test:
  `godot --path godot res://scripts/voxel/arena/voxel_arena.tscn -- --auto --secs=30 --stats` (or the built exe with
  `-- --auto --secs=30 --shot=out.png`). Screenshots: `voxel_shots/arena_fp1.png`, `arena_fp2.png`, `arena_td2.png`
  (software-rendered, so the fps there means nothing).

### Co-op and health (21 Oct, the owner's Stage 1: "online with my mate", 2 players)

- Keys: F7 hosts (a 4-letter room code at the top), F8 joins (type the code; anything with a "." or ":" is an address
  for the direct link), Shift+F7 hosts directly on UDP 24643, F9 leaves. Command line: `-- --host=CODE` /
  `--join=CODE`, `--via=rtc|enet`, `--server=ws://...` (the PeerJS server), `--local` (no STUN/TURN), `--netdebug`,
  and for tests `--lag=ms --loss=%` (a bad line: every message held back, the fast ones partly lost).
- Transports (`scripts/voxel/net/`, both the main game's `NetTransport` calls plus `send_fast`): `VoxelRtcTransport`,
  native WebRTC (`addons/webrtc`, godotengine/webrtc-native 1.1.0, Windows and Linux x86_64 only; the export puts the
  DLL beside the exe) introduced through the PeerJS server (its WebSocket protocol spoken directly; peer ids
  "smashedvx-" + code), the HTML game's STUN servers and metered.ca TURN relay; channels "rel" (reliable, long
  messages in 15000-byte pieces) and "fast" (unreliable). `VoxelEnetTransport`: ENet, channel 0 reliable, 1
  unsequenced. GodotSteam later is a third transport with the same calls. The main game's `scripts/net/` is untouched.
- `VoxelNet` (`voxel_net.gd`): the host is the authority. It runs the enemies and both players' weapons; the guest's
  weapons on the host are driven by the guest's input events (press/release/reload/quick/switch) and its player state
  at 30 Hz, through a `VoxelShooter` (each weapon asks its shooter for camera, player, aim, mouse ray; `voxel_shooter.gd`).
  Voxel data is not streamed: every body change on the host (cut, carve, burn, char, ash, freeze, thaw, shatter,
  sever) is sent as a hit event with the body's pose at that moment, and the guest replays the same call on the same
  pose, so its cubes come out the same (checked: 20/20 bodies identical). The guest's bodies are locked against
  changes of their own (`VoxelBody.net_locked`). Every 2 s the two compare body fingerprints; a body that differs is
  put right by sending its grid (zstd). Snapshots of the bodies' poses at 20 Hz, shown 0.1 s behind; cut-off pieces
  appear from spawn events and follow the host's at 15 Hz. Joining mid-fight gets the whole world in one message.
  About 1.5-2 MB a minute with both players going through all 14 weapons.
- Digging later: chunk changes go the same way (an event per dig, the chunk's fingerprint checked, the chunk sent
  whole only if it differs), so terrain never has to stream.
- Health (`voxel_arena.gd`): 100; enemies' swings (grunt 6, swarmer 4, brute 12, batter 8 as the swing lands),
  touching a burning one, grenades and fire (your own too) hurt; back at 4 a second after 5 s unhurt. At 0 you're
  down (no moving, the view low and grey): 4 s alone; in co-op your mate standing within 1.6 m for 2.5 s gets you up
  at half health, or 15 s on your own; with both down the enemies stop swinging. HUD: the bar above the weapon bar, a
  red flash when hurt. `--godmode` (and the self-tests) can't be hurt.
- Tests: `test/voxel/coop_test.gd` (two copies, host first: both players through every weapon at once, then the
  fingerprints compared; `--early` lets the host fight alone first so the guest joins mid-fight),
  `test/voxel/health_test.gd` (solo 7 checks; with `--host`/`--join` 3 co-op checks), `test/voxel/net_link_test.gd`
  (the link alone), `test/voxel/peer_server.js` (a local PeerJS server for the WebRTC runs). Results: 0 bodies
  different over ENet, over WebRTC, with 120 ms lag and 10% loss and a mid-fight join, and from the exported build
  hosting; health 7/7 and 3/3; logic 337/337.
- Not done yet: lag compensation (the guest's shots land where the host has the enemies, 0.1 s on); the harpoon's
  and gravity gun's held pieces only roughly follow on the guest; resources the guest vacuums up aren't counted.

### Backpack and chests (21 Oct, the owner's Stage 2: "a proper inventory", "storage chests/cabinets")

- The vacuum no longer just counts: every cube it takes goes into the **backpack** (`VoxelInventory`, 24 slots) as an
  item by its colour (`voxel_items.gd`: rubble, meat, bone, brain, charred bits; stacks of 9999, since one grunt is
  ~28,000 cubes). Full: the vacuum stops and says so. Later stages add their items to `VoxelItems.ITEMS`.
- **Chests and a cabinet** (`voxel_storage.gd`) against the north wall: two wooden chests (18 slots, a lid on hinges)
  and a steel cabinet (27 slots, two doors). Solid: players bump into them, enemies walk round them (they're in
  `VoxelArena.blocks`, beside the pillars). Look at one within reach: "E  open Chest"; E opens it (the lid swings up
  while either player has it open), the inventory screen showing it above the backpack. Elsewhere E is still the
  vacuum.
- **The screen** (`voxel_inventory_ui.gd`): Tab or I the backpack alone; left click pick up / put down / swap, right
  click half / one, shift+click straight across, a click outside the panels drops what's in your hand on the floor as
  its cubes (the vacuum takes them back), Tab / E / Esc close it, walking away from the chest closes it. No weapons
  while it's open.
- **Saved** (`voxel_storages.gd`): the backpack and the chests to `user://voxel_arena_save.json` (on Windows
  `%APPDATA%\Godot\app_userdata\Smashed TV\`) a moment after a change and at quit; loaded at start. The self-tests
  don't save (`--nosave`; `--save=path` for another file).
- **Co-op**: the host's chests are the real ones. A guest's moves go to the host as requests (take this, put this
  there) and come back as a "give" of what ends up in their hand or backpack, so nothing is made twice when both are
  at one chest; every change to a chest goes to the guest whole. A guest's own chests are kept as they were while in
  someone else's game. The corpses and pieces a guest vacuums are given to the guest by the host (Stage 1 left that
  out), each player's vacuum clears the same lying cubes in the other's game (brush messages, 10 a second), and a stack
  dropped falls in both games the same way (a shared seed).
- The ENet guest now tries again with a fresh socket every 3 s until the host answers (status "try N"): pressing F8
  before your mate has pressed Shift+F7 just waits.
- Tests: `test/voxel/inventory_test.gd` (29 checks alone; with `--host` / `--join` 3 + 9 co-op checks);
  `test/voxel/inventory_shots.gd` (screenshots under a display: `voxel_shots/inv_wall.png`, `inv_chest_open.png`,
  `inv_cabinet_open.png`, `inv_backpack.png`). The two-copy tests now give up on linking by real time (with
  `--fixed-fps` the games run several times faster than real time, so a game-time limit could end the host before the
  guest came).

### The bedroom (21 Oct, the owner's Stage 3: "two beds, a chest at the end of each bed (one per player)", "a
physical spin-dial combination padlock on each chest (no typed password)")

- Through a door in the arena's south wall (behind where you start), `voxel_bedroom.gd`: the HTML game's bedroom
  rebuilt at its own size (its units at 2.25 cm a unit: 9.9 x 7.7 m), its floor picture (planks, rug, dumbbell, books;
  its painted bed covered over: `assets/voxel/art/bedroom_floor.png`), the door top left, the wardrobe (E opens its
  doors: the gang's clothes inside) and the full-length mirror against the back wall, papered walls, a ceiling light
  with shadows, a lamp on the nightstand. Two beds against the arena wall: P1 (blue, the host's, as in the HTML game)
  and P2 (green, the guest's). The door swings open as anyone comes near it.
- **Safe room**: enemies can't come in (the arena keeps them out) and don't go for anyone in here (`VoxelNet.targets`).
- **Beds**: look at one, E lies you down (the eye on the pillow, the weapon put away, health back at three times the
  rate); E, WASD or Space gets you up beside it. In co-op your mate sees you lying in it.
- **Chests**: one at the foot of each bed (`bed_chest_1` / `bed_chest_2` in `VoxelStorages`), named for whoever's
  looking: "Your chest", "Mate's chest" (alone, P2's is the "Spare chest"). Each starts with a padlock hanging open on
  its hasp.
- **Padlocks** (`voxel_padlock.gd`, `voxel_lock_view.gd`): a real 3D spin-dial lock, four number wheels and a steel
  shackle. L at a chest holds its padlock up close; the mouse wheel over a wheel (or a click on its top or bottom)
  turns it a digit with a click. Open, click the shackle to shut it: locked with the code the wheels show (shown a
  moment; the wheels are then spun to hide it). Locked, E at the chest brings the padlock up: turn the wheels to the
  code and it springs open, then the chest opens. R takes an open padlock off into your backpack ("Padlock" item); L
  at a chest without one hangs it on. A locked chest gives nothing and takes nothing (the host checks). The padlocks
  are saved with the chests. Co-op: the host's game alone keeps the codes; a guest's lock is sent to the host, every
  turn of a locked padlock's wheels is tried by the host, and the guest's game only hears locked or open.
- **Mirror** (`voxel_mirror.gd`): a real reflection: a second camera at your eye's reflection behind the glass with an
  off-axis frustum cut to the glass (its near plane on the glass), drawn on it flipped; in first person you see
  yourself (your Jared, on a render layer only the mirror's camera sees). It only renders when you're near it, facing
  it.
- Also: chests are now picked by what your look's ray hits first (a chest, a bed, the wardrobe), not by roughly
  facing it; cubes dropped in the bedroom stay in it (`VoxelDebris.rooms`); the padlock can't be dropped as cubes.
- Tests: `test/voxel/bedroom_test.gd` (34 checks alone; with `--host` / `--join` 7 + 5 co-op checks),
  `test/voxel/bedroom_shots.gd` (screenshots under a display: `voxel_shots/bed_doorway.png`, `bed_room.png`,
  `bed_beds.png`, `bed_mirror.png`, `bed_padlock.png`, `bed_lying.png`, `bed_topdown.png`).

### Digging in the yard (21 Oct, the owner's Stage 4: "voxel digging with small chunky blocks", "shovel + pick",
"rusty -> good -> silly golden shovel", "worms"; built separately from the other session's `scripts/dig/`, which is
untouched, as the owner chose)

- **The yard** (`voxel_yard.gd`): a back door in the arena's south wall (x 12 to 13.45) into a fenced garden east of
  the bedroom, 17 x 17.5 m. Safe like the bedroom (the enemies don't come in or go for you there).
- **The ground** (`voxel_terrain.gd`): 16 x 16 m and 3 m deep in 12.5 cm blocks (128 x 24 x 128, one byte each).
  Block size tuned: 6.25 cm made too many faces to mesh fast in GDScript, 25 cm looked like Minecraft. Layers: grass,
  dirt (to ~0.75 m) with clay pockets and stones in it, stone (to ~1.75 m), hard rock with rare seams of gold ore,
  bedrock; a ring round the edge that never digs, so a hole never opens onto nothing. The same every game (fixed
  seed). Each visible face is drawn in its block's colour, a shade off its neighbours and darker deeper down; meshed
  in 2 x 2 m columns on worker threads, with a matching collision mesh (you can walk in holes and fall into deep ones).
  Measured: making it 0.25 s and meshing 0.7 s at load (on workers), a dig 0.2-1.3 ms on the main thread, the chunks it
  touched re-meshed off the main thread (about 10-40 ms each, there a frame or two later).
- **The tools** (`voxel_tool.gd`, key 6): the shovel digs a scoop (dirt, grass, clay; not stone) and right click puts a
  scoop of dirt back from the backpack. Rusty (to start): small scoops, slow, one in four slips. Good: bigger,
  quicker. Golden: huge, very quick, through stone too. The pick breaks anything but bedrock (stones, stone, rock, gold
  ore). Too hard: a clang ("the pick breaks stone"). What comes up goes in the backpack: dirt, clay, stone, gold
  nuggets; now and then a worm wriggles out of the dirt (`voxel_worm.gd`), into the backpack too. Dust puffs and their
  own sounds (`assets/voxel/tools/sfx_tools.py`).
- **The tool bench** by the back door: E makes the next shovel. Good: 150 stone + 500 bone. Golden: 80 gold nuggets +
  500 brain (out of the backpack). The shovel's tier is saved.
- **Co-op**: a dig or fill is the same call in both games, so only the call goes (either way); each player keeps what
  their own digging brings up. The host sends each chunk's fingerprint every 3 s; a chunk that differs is sent whole.
  A guest joining gets every chunk dug so far. A guest's own yard is kept while they're away. The dug chunks are saved
  with the backpack and chests.
- Tests: `test/voxel/dig_test.gd` (19 checks alone; with `--host` / `--join` 1 + 3 co-op checks, and both games print
  the ground's fingerprint: they agree), `test/voxel/dig_shots.gd` (screenshots under a display: `voxel_shots/dig_*.png`).
  The logic test's loadout checks updated for the sixth group; the co-op health test now waits for the hit by real
  time.

### Farming (21 Oct, the owner's Stage 5: "bring the weed growing mechanics across", "hoe dirt into rows, plant seeds,
watering can", "rebuild the fertilising system from scratch", "worm farms")

- **The HTML game's weed growing** (b332, `FARM.md`), its numbers (`VoxelFarm.STRAINS`): six strains; Northern Lights
  ($10) and Sour Diesel ($30) seeds at the seed crate; a plant grows in real time (NL 4 min ... White Widow 15),
  watered at full speed for 3 minutes, dry at half, droops and wants water, dry 2 minutes it wilts and loses a bud;
  seedling, young, fan leaves, ready with buds; E harvests; the buyer's crate pays a plant's price for all its buds. A
  wave cleared jumps everything ahead (NL 2 waves ... WW 6), where a wave here is 8 of the arena's one-at-a-time
  enemies (`WAVE_ENEMIES`: the HTML game's waves are crowds). **Cash** (new to the voxel game): kills pay as in the
  HTML game (grunt and swarmer $1, batter $3, brute $5), each player's own, shown over the health bar, saved.
- **The plants** (`voxel_plant.gd`): the HTML game's own plant art (`assets/voxel/art/weed_sheet.png`, taken out of
  `Smashed.html`'s WEED_SHEET) built in cubes, two pictures crossed; dry ones squashed and yellowed, wilted browned (as
  its weedArt), a drop over them; the black outline left out (in cubes it was specks); sway in the breeze.
- **The hoe** (6): a row of three planting spots (0.75 m apart, `VoxelFarm.SPOT`) the way you face turned to tilled
  soil (a terrain block of its own, furrowed), where it's grass or dirt. Plant on it with E (the seed you bought last,
  or any). Dig a plant's ground away and it's gone.
- **The watering can** (6): hold left to pour (a stream of water); the plants where it lands are watered; 8 plants a
  can; E at the water tank fills it.
- **Fertiliser, from scratch**: worm castings from the worm farm. E at a growing plant feeds it: once 35% faster and a
  bud more, twice 70% and two more. **The worm farm**: E puts in your worms (found digging) and up to 3000 scraps
  (meat, brain; charred bits count half); the worms eat 2 a second each, make a casting every 300, and breed while
  fed (up to 60); E takes the castings. (Stage 6's chicken poo and 6.5's blood and bone go into the same feeding.)
- **Co-op**: the farm is the host's, like the chests: a guest's planting, watering, feeding, harvesting and worm-farm
  turns go to the host as requests and come back as gives (buds, castings, a seed back); the plants' state goes to the
  guest every 2 s and on every change; the hoe's tilling is a terrain call like a dig. Seeds, buds, cash and the can
  are each player's own. Saved with the rest. (Found on the way: network message "F" was already the fingerprints'
  fix request; the farm's is "K".)
- Tests: `test/voxel/farm_test.gd` (25 checks alone; with `--host` / `--join` 3 + 4 co-op checks),
  `test/voxel/farm_shots.gd` (`voxel_shots/farm_*.png`). The logic test's loadout checks updated (18 weapons).

### Chickens (21 Oct, the owner's Stage 6: "feed chickens; collect chicken poo as fertiliser (optionally via the
worm farm); collect eggs, eggs can hatch into more chickens, more feeding = faster breeding; walk-in chicken coop with
a nesting area; chickens can be let out to roam the yard; max chicken cap tied to the coop, upgrading raises it")

- **The run** (`voxel_chickens.gd`): wired in east of the back yard (x 22.65..31.6, z 22.5..40), through a timber gate
  in the yard's east fence (E opens / shuts it; it swings into the run). Safe like the yard (`VoxelArena.safe`), a room
  of its own for the cubes (`_rooms`). **The walk-in coop** in its south-east corner: plank walls, an iron roof (off
  from above when you're inside, top-down), a lamp; nest boxes on a shelf along the east wall, perches, a tube feeder
  and a waterer, GRAIN sacks by the door (E: 10 for $5), a COOP sign by the door (how many chickens; E upgrades).
- **The hens** (`voxel_chicken.gd`): little cube chickens (white, brown, black; chicks small and yellow), the head,
  wings and legs moving apart: they walk, peck, look about, flap, sit. They wander the run and the coop (round the
  coop's corner, in and out of its door), go in to eat when they're under 60% fed and the feeder has feed, go up into
  a nest box to lay when they've built up an egg (fed full every 120 s, half fed every 240 s, under a quarter never),
  flap off from anyone running at them, and poo (a little heap of brown and white cubes the vacuum takes as **chicken
  poo**). Gate open, they roam the yard too (through the gate, and back to eat and lay); gate shut, nobody's let
  through.
- **Feeding**: E at the feeder puts in your grain (a feed each) and worms (3 each), up to 60; a feed fills a hen half.
  **Eggs**: a nest box holds 3; E collects them; sold at the buyer's crate ($4) or eaten (H, +20 health, when hurt).
  Left in the nest they **hatch** in 150 s at speed 1, the speed 0.5 + the hens' average fill (more feeding, faster
  breeding: up to 3x), while there's room under the coop's cap; a chick grows into a hen in 4 minutes.
- **The coop's levels** (`LEVELS`): 4 chickens and 2 nest boxes; $100 + 150 stone: 8 and 4; $300 + 400 stone: 16 and
  6. Two hens to start.
- **Poo as fertiliser**: 20 chicken poo feeds a plant (`VoxelFarm.POO_FEED`; castings first if you've both); in the
  worm farm a poo cube is worth 1.5 scraps. Items: egg, grain, chicken poo (`VoxelChickens.items`, through
  `VoxelItems`; poo is cubes, by colour, like meat and bone).
- **Co-op**: the chickens are the host's: a guest's gate, feeding, egg collecting and upgrading go to the host as
  requests (network message "B"), the eggs come back as gives; where the hens are goes to the guest 10 times a second
  (smoothed), everything else every 2 s and a moment after any change; poo heaps fall the same in both games (a
  seed); the hens' sounds play in both. Grain, eggs and cash are each player's own. Saved with the rest.
- Sounds (`assets/voxel/tools/sfx_chickens.py`): clucks, the egg song, chick peeps, wing flaps, the gate creaking,
  grain pouring, an egg picked up.
- Tests: `test/voxel/chickens_test.gd` (41 checks alone; with `--host` / `--join` 4 + 7 co-op checks),
  `test/voxel/chickens_shots.gd` (`voxel_shots/chickens_*.png`).

### The shredder, blood and bone, burning (21 Oct, the owner's Stage 6.5: "gore pieces become a resource: shred them
into bags of blood and bone fertiliser for crops, the worm farm and chickens; shredder: throw limbs in the top, it
grinds with blood spray, bags drop out the bottom; upgrade tiers: hand-crank mincer -> bigger shredder -> industrial
woodchipper; flamethrower burning: skin chars black first, then sustained flame crumbles charred voxels to ash, exposing
bone; ash is lost; charred pieces give lower-value fertiliser")

- **The shredder** (`voxel_shredder.gd`) against the back yard's south fence. What comes to its mouth is taken in: a
  piece flying or dropped in (the gravity gun carries them out of the arena through the back door; a dead body carried
  or thrown can now go out the door into the yard too, `VoxelArena._keep_dead`), a lying limb or corpse put in, or E:
  the gore in your backpack (meat, brain, bone, charred bits, up to 20000). It grinds at its tier's rate with the
  machine shaking, its drums or crank turning, blood spraying (grey for burnt stuff), crunches for bone; every 4000
  points a **bag of blood and bone** drops out onto a pile (E takes them). Points a cube: meat and brain 1, bone 2,
  charred 0.35, rubble (clothes, gear) 0.1: a grunt is about 6 bags, a burnt one far fewer. A blood stain spreads
  round it the more it's ground.
- **Tiers** (its sign upgrades it): the **hand-crank mincer** (a cast-iron mincer on a stand; 300 cubes a second;
  takes up to 2000 cubes: a hand, a foot, a forearm), the **electric shredder** ($200 + 300 stone; 1500 a second; up
  to 8000: a head, a leg), the **industrial woodchipper** ($600 + 60 gold; a trailer chipper, its big feed chute and
  the spray out of its discharge; 8000 a second; anything, a whole corpse). Too big: it sits in the top and says so.
- **Blood and bone**: a bag feeds a plant like castings (E; castings first, then blood and bone, then chicken poo), is
  150 scraps' worth in the worm farm, or 12 feeds in the chickens' feeder.
- **Burning** (`VoxelBody`): a cube alight chars black after 0.8 s; at 1.6 s it crumbles to ash only if the flame is
  still on it (an ignite in the last 0.4 s: the flamethrower's stream re-lights where it lands every 0.1 s, a fire
  patch every 0.2 s), else it goes out, charred. Fire spreads to fresh cubes beside burning ones (fast round the flame,
  slowly away from it, so it dies down when the flame moves off), never to charred cubes or bone: held on, the flame
  digs into the flesh and stops at the bone. **The ash is lost**: its cubes (a grey of their own, `VoxelBody.ASH`)
  crumble away where they land and the vacuum gets nothing from them. Charred cubes vacuumed are "charred bits"
  (half in the worm farm, a third in the shredder).
- **Co-op**: the shredder is the host's: the host's game takes in what comes to its mouth (the pieces and corpses
  going are told to the guest as before); a guest's backpack gore, bag taking and upgrading go to the host as requests
  (network message "M"), the bags come back as gives; its state goes to the guest every 2 s and on every change. The
  burning is decided in the host's game and its char and ash go to the guest as before. Saved with the rest.
- Sounds (`assets/voxel/tools/sfx_shredder.py`): the mincer's squelch and creak, the shredder's motor and teeth, the
  woodchipper's diesel and drum, bone crunches, a bag dropping, a motor winding up.
- Tests: `test/voxel/shredder_test.gd` (27 checks alone; with `--host` / `--join` 4 + 5 co-op checks),
  `test/voxel/shredder_shots.gd` (`voxel_shots/shredder_*.png`); the logic test's fire checks and the flamethrower's
  self-test changed for the new burning (a lick of flame chars, the flame held on makes ash, bone stays, it dies down).

### The retro games room (22 Oct, the owner's Stage 7: "couch + TV area with all the consoles on the wall; pick a
system and it pops up on the table; physically pull game cases off a shelf, open them and play; built-in emulator for
Mega Drive games, Smash TV etc.")

- **The emulator** (`addons/voxel_retro/`): a small libretro frontend as a GDExtension (`RetroCore`, C++ in `src/`,
  built with godot-cpp 4.4 for Linux and Windows x86_64: `src/build.sh`) that loads a libretro core, loads a game,
  runs it a frame at a time, and hands back the picture (an RGB8 Image from 0RGB1555 / RGB565 / XRGB8888) and the
  sound (stereo frames), takes the buttons (and the bitmask form), and saves / loads states. The cores are built from
  source here too (the libretro buildbot is blocked from this container): **Genesis Plus GX** (Mega Drive, Master
  System, Game Gear) and **Snes9x** (Super Nintendo), both free for non-commercial use only. The Windows DLLs need
  nothing but KERNEL32 and msvcrt; the export puts the plugin and the cores next to the exe (`[dependencies]` in the
  `.gdextension`). **No games are included**: players add their own. Our own **test cartridge**
  (`assets/voxel/retro/test_cart.s`, 68000 assembly, built with binutils' m68k assembler: a drifting checkerboard the
  d-pad scrolls, B / C flash it red and beep) is on the shelf so the TV has something to play.
- **The TV** (`voxel_retro_tv.gd`): the game runs at the console's own frame rate (catching up at most three frames a
  frame), its picture on the screen through a CRT shader (a little curve, scanlines, a vignette), its sound out of
  the TV (an AudioStreamGenerator at the core's sample rate, 3D), the room lit by the picture's average colour. On the
  couch, the keyboard and any pad are player 1's controller (arrows / WASD the d-pad; J K L, U I O the face buttons as
  A B C / X Y Z on a Mega Drive pad, Y B A / L X R on a Super Nintendo's; Enter start; Tab mode / select). Ejected, it
  saves a state (`user://retro_saves/`) and the same game carries on from it next time.
- **The room** (`voxel_games_room.gd`): west of the bedroom (x -14.2..-5.2, z 22.5..30.2), its own door in the arena's
  south wall (a neon frame, GAMES ROOM over it); a 90s arcade carpet (made in code), purple walls, posters, a lamp; a
  big rear-projection TV against the back wall, a coffee table with two pads, a couch with two seats facing it; the
  four consoles on wall shelves (E: down onto the table, flying, the other back up); a bookcase of cases (spines out,
  the game's colour and name; up to 60 a shelf, the eye-level shelf first). E at a case: into your hands, its lid
  swinging open on the cartridge; E at the table: in (the right console comes down by itself), the TV on; E at the
  couch: sit (the view on the TV, narrower); E: up; E at the console while on: eject. The **library**: the test
  cartridge, then every game file in `user://games` and (in a build) the `games` folder beside the exe, by extension
  (.md .bin .gen .smd, .sfc .smc, .sms .sg, .gg), a .zip's first game taken out into a cache, names tidied ("Super
  Smash TV (USA)" -> "Super Smash TV"). E at the ADD GAMES plaque opens the system's file picker (Windows) and copies
  them in. A safe room (`VoxelArena.safe`, the cubes' rooms). `--retrotest` (the exported game's own check): the test
  cartridge put in and played 2 s, what came out printed, quits.
- **Co-op**: the room is the host's. The host's TV picture goes to the guest 15 times a second (192 x 134 JPEG,
  unreliable, binary message 84); the console on the table and what's on go as network message "R"; a guest on the
  couch is player 2 (their buttons to the host's console when they change). The guest can't put games in (the files
  are the host's); a guest's own console is switched off while they're in someone's game.
- Tests: `test/voxel/games_test.gd` (26 checks alone; with `--host` / `--join` 2 + 3), `test/voxel/games_shots.gd`
  (`voxel_shots/games_*.png`); the Windows build checked under Wine (`SmashedVoxelArena.exe --headless -- --retrotest`:
  the plugin loads, Genesis Plus GX plays the test cartridge, 179 frames, 320 x 224).

### Bones hold the body together (22 Oct, the owner's Stage 8: "bones hold the body together, skin/meat stays attached
to blown-off bones, dangling limbs tear off from strain, shooting the skin finishes it")

- **Held by the bone** (`VoxelBody`, its end section): after every cut the joints are looked at from the body down. A
  limb (upper arm, forearm, thigh, shin) is held while its own bone is there by its joint and the bone of the part above
  it, from where that's held, still reaches the joint (a flood through the bone cubes); hands and feet (no bone of their
  own) are held while the bone above reaches them. Compared with the same kind whole (`_baseline`: some models' bones
  have gaps, a batter's shin): a joint with no bone when whole asks for none. A limb broken in its upper half (under half
  of its whole bone still joined to its joint) hangs from that joint; broken lower down, what's below it hangs.
- **Dangling**: a part shot or cut through the bone but still joined by flesh is **loose**: it and everything below it
  swing from the joint as a pendulum (a Verlet tip, gravity, lagging as the body moves, kicked by hits, resting on the
  floor on a corpse), the bone turned to point at it, what's below limp. A dangling leg counts as a lost leg (the limp,
  the crawl). Bone doesn't burn, so fire never loosens a limb.
- **Strain**: a hanging chain strains from its weight (its cubes), every jerk (the swing's acceleration), walking, and
  every hit on the body, divided by the strip it hangs by (its cubes round the joint): a thin strip tears in a few
  seconds, a thick flap holds a while (`TEAR_K`, `HIT_STRAIN`). Strained through, the host's arena tears it off
  (`_tear_step`: a sever, so a co-op guest gets it like any cut), a spray of blood, a wet rip (`flesh_tear_*`). A cut
  that takes cubes from a hanging limb or its strip **finishes it** at once. What comes off keeps its meat on its bone.
- **Easier to see, floppier** (22 Oct, the owner: "make it more visible and floppier"): the swing keeps more of
  itself each frame (`SWING_KEEP` 0.996: it swings a long while), walking sways it side to side in step, a hit flings
  it 6-11 cm and it swings back; the hand or foot below flops against the swing. A hanging limb **sags** from its joint
  (`SAG` 7 cm, bouncing like a spring with the swing), a thin strand of raw flesh across the gap on the side the skin
  is left on (`_strip_side`), thinning as the strip is shot away; **blood drips** off it (faster as it nears tearing). All looks only
  (no cubes, nothing to vacuum); the cuts land where the limb is drawn.
- **Torn edges, not flat cuts** (22 Oct, the owner: "I can't see the bone", "such a straight cut looks kinda bad"):
  the parts are separate grids, so a limb hanging or off showed a flat face at its joint. Now (`_seams_step`,
  `seam_cols`, `seam_mesh`) wherever a part's neighbour is gone or hanging, a torn edge is built from the cubes at that
  face: each column of it its own length, raw meat over the middle, the sleeve or skin torn ragged round the edge, and
  the **bone sticking out jagged and white** where the bone is (on a limb with none left there, where it would be; it
  glows a touch so it shows in the limb's shade). Both sides of a hanging limb's gap, the stump left on the body, and
  the end of the piece that comes off (VoxelPieces; a co-op guest's copy too). Little cubes on the part's bone, so they
  move with it; looks only (nothing to hit or vacuum). The earlier box bone stubs are gone. A **stump's** bone sticks
  out twice as far (a splintered point, longest in the middle; the neck shows its spine); a torn-off piece's end 1.3x.
  Pieces that settle into lying bodies keep their torn end (built when they settle and after every cut, since lying
  bodies aren't animated).
- Tests: `test/voxel/stump_shots.gd` (`voxel_shots/stump_*.png`: the elbow, knee and neck stumps, the torn-off forearm
  and the head lying on the floor, from their torn ends).
- Co-op: the loose parts follow from the cubes (the same in both games); the swing is each game's own, and the cuts
  are made against the host's pose (sent with them) as before; the tear is the host's sever.
- Tests: `test/voxel/dangle_test.gd` (12 checks), `test/voxel/dangle_shots.gd` (`voxel_shots/dangle_*.png`: `dangle_hanging` close up, `dangle_bone` front on (the broken bone); four-frame sheets
  `dangle_close` (shoved, swinging), `dangle_walk` (walking at you, the forearm flopping), `dangle_knee` (the shin
  hanging, shoved), `dangle_tear` (strained through, torn off)); the
  co-op body check still finds no body different.

### Settings and the benchmark (22 Oct, the owner's Stage 9: "PC first, as physics/graphics heavy as possible, but
scalable settings, plus a recommended-settings test based on the player's hardware")

- `scripts/voxel/arena/voxel_settings.gd` (`VoxelSettings`: the settings, the presets, saving, putting them into
  effect) and `voxel_settings_menu.gd` (`VoxelSettingsMenu`: the screen and the benchmark). A **SETTINGS (F10)** button
  under ONLINE (O); the co-op line moved down under both.
- **Presets** LOW / MEDIUM / HIGH (the game as it was) / ULTRA; any row changed makes it CUSTOM (changed back, the
  preset again). The rows: render scale (50-100%; FSR 1 upscaling below 100% on Forward+, the Windows build), MSAA
  (off/2x/4x/8x), TAA, shadows (off / hard 2048 / soft 4096), ambient occlusion, SSIL, glow, SDFGI, volumetric fog
  (TAA, SDFGI and fog are Forward+ only), the bedroom mirror; the gore's weight: the cube size (1 or 2 sprite pixels a
  cube, an eighth of the cubes; like F2, not mid co-op), cubes lying about (40k-300k), cubes flying at once (3k-12k),
  cut-off pieces (12-45), corpses kept (12-60); and your own (not in the presets): frame cap, vsync, full screen, field
  of view (60-110°), mouse speed, volume. Low: 67% scale, no shadows / AO / glow / mirror, chunky cubes, small caps.
  Ultra: 4x MSAA, TAA, SSIL, SDFGI, fog, 300k lying, 12k flying, 45 pieces, 60 corpses.
- Everything takes effect at once and is saved in `user://voxel_settings.cfg`. The first run guesses a preset from the
  graphics card's name (`VoxelSettings.guess()`: RTX 30 80/90, 40, 50 or RX 79xx Ultra; other RTX / RX 6000-7000 High;
  integrated graphics Low; anything else Medium). The screen shows the PC: processor, threads, memory, graphics card.
- **RUN BENCHMARK** (alone only: greyed out in co-op): from Ultra down, each preset gets the same fight to draw (24
  enemies kept topped up, shot at with a gun and a shotgun, set alight now and then, you facing them, god mode), no
  frame cap and no vsync: 1.5 s to settle, 4 s measured. The first preset whose slowest 5% of frames are inside
  16.7 ms (holds 60 fps) is recommended (nothing does: Low); lower ones aren't tried. The table shows each one's
  average and slowest-5% fps; APPLY RECOMMENDED puts it on. After, your settings, the enemies you had, where you
  stood and god mode are put back. Esc stops it part way (nothing changes).
- A test's game (any test option, or the arena not the main scene) is left as it was (High, never saved); `--settings`
  loads the file anyway, `--preset=low|medium|high|ultra|extreme` picks one.
- Tests: `test/voxel/settings_test.gd` (30 checks), `test/voxel/settings_shots.gd` (`voxel_shots/settings_*.png`,
  `preset_low.png`, `preset_ultra.png`, `preset_extreme.png`).
- **EXTREME** (Stage 10 of the overnight plan, 22 Oct: the owner's PC ran Ultra at 287 fps average): above Ultra.
  Supersampled (150% render scale: drawn bigger, shrunk to the screen), 8x MSAA + TAA, the sharpest shadows (8192
  atlas, soft ultra filter), SSAO / SSIL / SDFGI / fog at their best and screen-space reflections (the new **Effects
  quality** row: Normal / Best; Best is only in Extreme, any preset with it turned up by hand is Custom), denser fog;
  twice Ultra's gore: 600k cubes lying, 25k flying, 90 pieces, 120 corpses. The rows got 125% / 150% render scale,
  Sharpest (8192) shadows and the new caps. The benchmark now starts at Extreme, and its fight also sets off a
  grenade at the nearest enemy's feet every 2 s (`BENCH_BLAST`; the grenade launcher's own `explode`: craters, torn
  limbs, cubes popped up, pieces tossed), so the flying and lying cubes and pieces fill up toward each preset's caps:
  it measures the gore at full load, not only the drawing.

### Enemy variety (Stage 11 of the overnight plan, 22 Oct: "a fast charger, a ranged thrower and a tanky shield brute")

- `scripts/voxel/arena/voxel_kinds.gd` (`VoxelKinds`, the arena's `kinds`): each kind's own move, run on the host (or
  alone) from the enemies' loop (`kinds.step`: the walk it wants this frame), and the thrown globs (both games).
- **Models**: `VoxelModel.VARIANTS`: an old model's files recoloured toward a tint (`_tinted`, keeping how light each
  cube is): the charger from the swarmer (red), the thrower from the grunt (green), the shield brute from the brute
  (blue steel). The shield brute gets a **shield**: a 30x2x38 steel plate (`shield_grid()`: a dark rim, rivets, a red
  cross, a boss) as a part on a bone of its own (`shield`, under `hand_l`), laid flat at rest; `VoxelBody.animate`
  pins the left arm so the forearm points ahead and the shield stands up in front. It's an ordinary part: shots,
  blades, fire and blasts take its cubes (no flesh inside, no health lost: `PART_WEIGHT` has none for it), holes go
  through, bits cut loose fall off as pieces, the arm cut off takes it along, it's synced like any part.
- **Charger**: from 3-10 m it crouches 0.6 s (`ACT_WINDUP`), runs headlong 11 m/s up to 0.9 s (`ACT_CHARGE`; it
  doesn't turn), whoever it runs into takes 15 and is thrown 9 m/s (`shove_target`: the other player through "ds"),
  then dazed 1 s (`ACT_DAZE`; a pillar or the wall: stopped dead, 8 hurt, 2.2 s). 2.5-4 s before the next. No
  charge on a lost leg; knocked over, set alight or frozen mid-move, it's off. Speed 1.3x a grunt's.
- **Thrower**: keeps 6-11 m off (in from further, back when you're near, sidestepping between); every 2.4-3.6 s
  draws its right arm back 0.7 s (`ACT_AIM`) and lobs a glob (an arc timed by the distance) at your chest: 10 where
  it lands (1.1 m round, less further out), a green splash of cubes either way. The arm off or hanging
  (`can_throw`): it comes in to hit you like a grunt.
- **Shield brute**: 0.6x a brute's speed; the shield takes the shots from the front (`fire`: a clang and sparks for
  a shield hit, a shove not a stagger: `hit_react`); under 40% of it left (`SHIELD_BROKEN`), or hanging, or off with
  the arm: 1.5x faster. Hammers, grenades and the harpoon treat him as heavy (`VoxelBody.heavy()`).
- In the mix (`VoxelArena.KEYS`, one each in eleven), paid for kills (charger $2, thrower $2, shield brute $6),
  their swings hurt like their base kind's. F4 freezes them mid-move.
- Co-op: the move is the host's; the guest gets it in the snapshots (`act_k`: the move and how far through, one
  float) and poses it; a thrown glob is sent as event "gl" and the guest throws a copy that only looks.
- Tests: `test/voxel/kinds_test.gd` (19 checks: the models, the shield taking shots and shot away, the charger's
  charge, hit and daze, the pillar, the thrower's glob, the arm off); `test/voxel/kinds_shots.gd`
  (`voxel_shots/kinds_lineup.png`, `kinds_moves.png`, `kinds_shield.png`).

### Waves and the boss (Stage 12 of the overnight plan, 22 Oct: "escalating waves plus a big voxel boss every few
waves, carvable piece by piece")

- `scripts/voxel/arena/voxel_waves.gd` (`VoxelWaves`, the arena's `waves`). **The waves** replace one-at-a-time in
  the real game: wave w is `plan(w)` (1 + 1.8w enemies, up to 34: 2, 4, 6, 8 ...), the kinds joining as it goes
  (grunts and swarmers; batters from 2; brutes and chargers from 3; throwers from 4; shield brutes from 6), walking
  in one every 0.45 s, never more than 24 up at once (`LIVE_CAP`), each wave's 2.5% quicker (to 20 waves); all down,
  a 3 s rest and the next, "WAVE n" big in the middle of the screen. The crops still jump every 8 enemies cleared.
  **F12** switches back to one at a time (the owner's of 20 Oct) and back; a test's game (any test option, or
  --host/--join from the command line) keeps one at a time unless `--waves`; `--wave=N` starts at wave N.
- **THE BUTCHER** every fifth wave, first in (a third of a wave behind him): `VoxelModel.VARIANTS.boss`, the brute
  recoloured red, 4.4 m tall (twice the size: his cubes are twice as big, as many of them). `VoxelBody.tough`
  (3 the first time, one more each time he comes back): his health 200 x tough, a limb takes tough x the hits to
  come off, his brain tough x as much gone (to 85%); knocks move him 0.15 as far, throws 0.3. His bar at the top.
  His moves (`VoxelKinds._boss`): walks at you (stops 2.6 m off); within 3.4 m both fists up (`ACT_SLAM_UP`, 1.1 s:
  get away) and down (`ACT_SLAM`): everyone within 4.8 m hurt up to 28 by how near and thrown away, the enemies
  near him knocked over, the cubes lying about thrown up, the view kicked; every 14 s he roars (`ACT_ROAR`) and two
  swarmers come running at his sides. Under half health: 1.45x faster, slams and roars sooner. Down: "THE BUTCHER IS
  DOWN", $40.
- Co-op: the host's waves; event "wv" shows the guest the wave's number and gives its bar the boss's full health,
  "sl" the slam's dust and kick (looks only).
- Tests: `test/voxel/waves_test.gd -- --waves` (19 checks: the plans grow, kinds join, the rest, the boss's size and
  toughness, bar, slam, roar, limb hits, his pay, F12); `test/voxel/boss_shots.gd -- --waves`
  (`voxel_shots/boss_wave.png`, `boss_slam.png`, `boss_carved.png`); co-op with `coop_test.gd -- --host=X --waves
  --wave=5` (0 bodies different).

### The weapon bench (Stage 13 of the overnight plan, 22 Oct: "kill and harvest money buys weapon upgrades (damage,
clips, fuel) at a lobby bench")

- `scripts/voxel/arena/voxel_upgrades.gd` (`VoxelUpgrades`, the arena's `upgrades`): a steel **WEAPON BENCH** in the
  back yard against the south wall, west of the buyer's crate (the voxel game has no lobby; the bedroom and the games
  room stay as the HTML game has them, so it went to the yard, by the tool bench). Three racks (DAMAGE, CLIPS, FUEL),
  each with what it upgrades hung over it and a tag (its level in dots, the next price); looking at one shows its
  line, E buys its next level (`arena.upgrade_buy`) with this player's cash.
- **DAMAGE** x1.2 / x1.4 / x1.65 ($25 / $60 / $120): `VoxelBody.hit_k`, the DAMAGE of whoever's weapons are running,
  scales every hole, cut and blow as it's made (`damage` r, `carve` r and health a cube, `slice` thickness, `hurt`
  amount), before it's recorded for the guest (who makes it as told). It's this player's all the time except while
  the host runs the other player's weapon copies (`VoxelNet._as_other`: their inputs, held buttons, steps, a switch).
- **CLIPS** x1.5 / x2 / x2.5 ($20 / $50 / $100): `VoxelGun.apply_upgrades` (the pistol's 12, the shotgun's 6, the
  launcher's 6, filled on purchase).
- **FUEL** x1.5 / x2 / x2.5 ($20 / $50 / $100): the flamethrower's tank drains (and a fire bomb costs) that much
  slower, the laser's heat builds that much slower, the freeze ray's charge lasts that much longer.
- Each player's own (`VoxelShooter.upg`, `upg_k(track)`), saved with the backpack ("tools": {"upg"}); in co-op each
  game sends its player's levels when they link and on every purchase (net "U"), so the host's copies of the
  guest's weapons are sized and hit as theirs.
- Tests: `test/voxel/upgrades_test.gd` (14 checks alone: the bench, the racks, no cash no sale, CLIPS, DAMAGE's bigger
  hole, FUEL, the top level, saved and loaded; `--host` / `--join`: the guest's levels on the host's copies and their
  DAMAGE on their hits); `test/voxel/upgrades_shots.gd` (`voxel_shots/upgrades_bench.png`).

### Jared sculpted from scratch (23 Oct, the owner: "rebuild from scratch, do Jared first")

- `scripts/voxel/chars/voxel_sculpt.gd` (`VoxelSculpt`): characters built in code as smooth shapes (signed distance
  functions: ellipsoids, capsules, tapering capsules, rounded boxes, blended with fillets) filled with cubes at the
  model's voxel size; each surface cube painted by what it is, shaded by which way it faces and how tucked in it is
  (creases darker). The models' rigs are kept: they animate, carry weapons and come apart (gore) as before.
- `scripts/voxel/chars/jared_build.gd` (`JaredBuild`), the "jared_new" model (VoxelModel.VARIANTS "built"), from
  his sprites' front, three-quarter, side and back views: a big tanned head (drawn 12% bigger than life, as in his
  pictures) with a heavy brow, square jaw, big nose, ears and a drooping moustache; short back and sides with a
  flatter top; blue wrap-around shades to his ears; a barrel chest and belly in his green singlet (JUICY JARED and
  a round logo on the front, the back mottled green and blue, a deep scoop neck, thick straps, big armholes, a darker
  trim, the singlet a layer over him); huge arms (deltoids, biceps, triceps, forearms, fists); grey shorts to
  mid-thigh with rolled cuffs; thick legs; chunky black laced boots up the shin. Limbs built on his left, mirrored.
- The arena's Jared (yours, and your mate's in co-op) is jared_new. Built ahead by `tools/bake_reshape.gd`
  (`assets/voxel/baked/jared_new.bin`, in the export): loads in 0.1 s instead of 5.
- Other hair styles (the old files) aren't refitted to the bigger head yet; the arena uses his classic hair.
- `test/voxel/head_shots.gd` (head close, or the whole body with --dist=4.6 --y=0.95, from five sides),
  `test/voxel/jared_clip.gd` (a clip: turning, head close, running).

### Jared and Gothica made solid (23 Oct, the owner: Gothica's side view "look bad"; Jared "a bit blurry, a little off")

**Taken back out** (the owner, after the video: "Jared's looks bad and Gothica looks terrible ... put them back"):
the models are the plain ones again ("jared_hd" is Jared at full detail with no reshaping; "gothica" keeps only her
chest's sculpt for VoxelJiggle). VoxelReshape, the bake tool and the turntable tests stay for later. Next: both
rebuilt from scratch in code as real 3D figures (Jared first), their pictures for colour and design.

- Jared was built at half detail (every 2 x 2 x 2 of his picture's pixels averaged into one cube: his face and the
  JUICY JARED print smudged). The arena's Jared (yours, and your mate's in co-op) is now the "jared_hd" model at full
  detail (VoxelModel.VARIANTS), like Gothica.
- `scripts/voxel/voxel_reshape.gd` (`VoxelReshape`), for models with "reshape" (jared_hd, gothica): the models were
  made from flat front and back pictures, so from the side every part was a slab, each row of the picture stretched
  through it (stripes), faces flat. Each part as it's loaded:
  - despeckle(): thin bits sticking out taken off (plates one cube thick at Jared's shoulders);
  - roundify(): each slice trimmed to a rounded oval (sizes smoothed over the slices either side, an even taper),
    the front and back pictures put back on the new surface (no inside cubes showing); a head only at the back
    (the face stays as drawn);
  - unline(): thin dark lines across a limb (the picture's outlines between segments: rings in blocks) filled;
  - recolour(): sides and tops coloured from the front's and back's rows (the light colours, smoothed over five
    rows), blended front to back, faded in from a few cubes behind each picture; the outline at the very edge
    filled; hair gets strands running down;
  - hair_clear(): Gothica's long hair moved back off the side of her face (it ran forward past her face: a dark
    band across her cheek from the side), tapering above her forehead;
  - face(): a nose and chin built out (Jared: his moustache out too, ears);
  - glasses(): Jared's glasses' arms run back to his ears;
  - joints(): forearms, hands, shins and feet reach up into the part above (no gap at a bent elbow or knee).
- Smooth shading: every part's rounded shape (VoxelReshape.shape) goes to the shader (VoxelJiggle.shader,
  VoxelJiggle.dress), which lights each pixel partly as that shape (an oval body, or a limb rounded along its length
  with capped ends) and partly as its cube's face: rounded light, the blocks still there.
- Gothica's arms are held a little out from her sides.
- Reshaping takes seconds in GDScript, so it's baked ahead: `tools/bake_reshape.gd` writes
  `assets/voxel/baked/<model>.bin` (run before exporting; included in the Windows export). A bake is ignored if the
  code has changed since (where the source can be read: the editor, the tests).
- `test/voxel/turntable_shots.gd` (front, three-quarters, side, back, and both faces face on and side on; --old for
  the models as they were): `voxel_shots/turntable_new.png`, `turntable_old.png`, `faces_new.png`, `faces_old.png`.

### Gothica (23 Oct, the owner: "get the character Gothica brought into the game ... her jiggle physics impressive,
out of this world impressive")

- `scripts/voxel/arena/voxel_gothica.gd` (`VoxelGothica`, the arena's `gothica`): she lives in the bedroom and the games
  room. She strolls between the places she likes (the mirror, the rug, the end of the beds, by the wardrobe; behind the
  couch and either side of the TV) along a little network of paths that keeps her off the furniture, stands a while
  at each (breathing, her weight shifting from foot to foot, looking round), and now and then goes through to the
  other room along the arena's south wall. Walking, her hips sway and her chest turns against them.
- E at her: a cheer hop (arms up), a line, and she follows you round the house, walking, or running when you're more
  than 4.5 m ahead. She won't go out into the fight: she waits in the bedroom doorway. E again and she stays where
  she is. Walk into her and she's bumped. Each game has its own Gothica (co-op: not sent).
- Her body: a VoxelBody of the "gothica" model (VoxelModel.VARIANTS: the goth model with her chest sculpted round,
  `_sculpt_bust`: two rounded shapes built out of the torso's front, coloured from what was there, the top's black and
  the neckline's skin, shaded underneath and between).
- `scripts/voxel/arena/voxel_jiggle.gd` (`VoxelJiggle`): her chest, hair and skirt are simulated, not animated. Each
  frame it measures how the bone each hangs from really moved (that point's acceleration in the world, including the
  body turning, and which way gravity pulls in the body's frame) and lets springs answer, sub-stepped at 480 Hz:
  - each side of her chest: its own spring up and down, side to side and in and out, the softest up and down. Lightly
    damped, so a jolt rings on for a second, with more damping on a big swing so it settles into a long gentle ring.
    A quicker 8 Hz wobble rides on top. The two sides collide in the middle. The shape stretches as it's pulled down
    and squashes as it's thrown up. What's drawn eases into a reach (no hard stop);
  - running, landing, turning, stopping and being bumped all come out of the body's own movement; a walking heel
    adds a small kick;
  - the hair is a heavy, slow pendulum off the back of her head; the skirt is quicker, off her hips, with its hem
    rippling as she goes.
  The look: one shader for all of her bends the cubes in the vertex shader. Each shape's front moves most and its
  base where it meets her chest doesn't move at all, so it bends like something soft rather than sliding as a block.
  The chest is shaded as the smooth round shape it stands for (not its cubes' steps), turned as it bends, so the light
  runs over it; her top is satin there, everything else matt (a sheen on voxel steps shows as stripes).
- Settings: Jiggle (Off / Natural / Bouncy / Out of this world; every preset starts on Out of this world).
  A run is about ±2 cm, a hop's landing near the full 3 cm. Standing still it settles to nothing in a few seconds.
- `test/voxel/gothica_test.gd` (14: the sculpt, wandering, following into the games room, waiting in the doorway,
  staying, a hop's bounce and settling, Jiggle Off), `test/voxel/gothica_shots.gd` (`voxel_shots/goth_front.png`,
  `goth_three.png`, `goth_room.png`), `test/voxel/gothica_clip.gd` (a clip for the movie maker: hop, run, stop, turn,
  run at the camera, hop, walk).

### Ultra Gore (23 Oct, the owner: "ultra gore mode with dripping etc")

- `scripts/voxel/arena/voxel_blood.gd` (`VoxelBlood`, the arena's `blood`): the blood after a hit. Every cut a body
  takes (its public `damage`, `carve`, `slice`, `sever`) tells `VoxelBody.on_wound` about the hole it left (where the
  cubes came out, on the part they came out of) and every part that came off (a stump at the joint, on the part it was
  joined to). The guest's replays of the host's cuts go through the same calls, so each game bleeds its own and nothing
  new goes over the network (the drops and pools needn't match).
- Holes bleed for 9 s, dripping less and less. Stumps spurt like a heartbeat for 7 s: a quarter-second jet every beat
  (an arc out of the stump, the head's strongest), weaker and slower each time, with a wet thump. A cut-off piece drips
  from where it lies (and goes on once it's settled into a body of its own). A shot through a body sprays out the far
  side along its way.
- Drops are little dark red cubes that fall (stretched as they go fast). On the floor (the yard's dug ground too:
  `VoxelTerrain.surface_y`) they make pools that grow as more lands in them, glossy and dark red, drying darker over a
  minute; on the arena's walls and pillars they leave splats, longer the harder and more sideways they hit. All three
  are MultiMeshes (one draw call each). Drips into pools and splats make small wet sounds.
- A hit within 1.9 m in front of you in first person splashes your view: clumpy drops, mostly away from the middle,
  that run down and fade over about 3 s.
- Settings: Gore (Normal: holes drip, small pools, no spurts or screen splashes; Ultra; Extreme: more drops, pools,
  splats and wounds kept). Low and Medium start on Normal, High and Ultra on Ultra, Extreme on Extreme. Cleared when
  the fight starts over.
- `test/voxel/blood_shots.gd` (`voxel_shots/blood_stump.png`, `blood_pools.png`, `blood_wall.png`, `blood_screen.png`).
- Stage 2: whoever walks through a pool less than 40 s old (you, your mate, the enemies) leaves bloody footprints for
  about ten steps, left and right, fainter each (a squelch when you tread in it); an enemy with no legs dragging itself
  on its arms leaves a smear behind it. Blood runs down a body from each hole and stump: a decal on that part, a blot
  with streaks and drips, growing down it over 5 s (a shot's starts where it went in, on the face it hit). Melee
  weapons get bloodier with every hit (a coat over the view model, up to half of it, wet and shiny, drying dark over 45 s)
  and drip in front of you while wet. Footprints and smears are MultiMesh rings; runs are kept to 24 (Extreme 48; none
  on Normal). `test/voxel/blood2_shots.gd` (`voxel_shots/blood_prints.png`, `blood_crawl.png`, `blood_runs.png`,
  `blood_bat.png`).
- Cost (a test box, slower than a gaming PC): 30 enemies shot to bits for 10 s on Extreme, about 1 ms a frame.

### The mirror, sharper (23 Oct, the owner: "the mirror ... looks blurry looking at Jared")

- `VoxelMirror` drew its reflection at 360 pixels high whatever: close up the glass covers most of the screen, so it was
  stretched two or three times. Now it's drawn at as many pixels as the glass covers on screen (worked out each frame
  from how far off it is and the view's width, in steps of 64), up to `max_res`, with MSAA of its own: both from the
  settings' anti-aliasing (off 720 / none, 2x 1080 / 2x, 4x 1440 / 4x, 8x 2160 / 8x). `test/voxel/mirror_shots.gd`
  (`voxel_shots/mirror_sharp.png`; `mirror_old.png` in its run shows the 360 it was).
- A vanity light on top of its frame (the owner: "add a light so I can see him"): a brass bar, three frosted bulbs, and
  a warm spot out of it, a little down, onto whoever stands in front (the ceiling light's behind you there: you were a
  dark shape in it).

### The slot machine (23 Oct, the owner: "an old school one that you have to pull the lever and the dials spin";
"a bit of a beat up looking machine, maybe some of the lights flicker"; "a spider in the machine that sometimes comes
down or falls onto one of the spinning wheels and gets flung around")

- `scripts/voxel/arena/voxel_slot_machine.gd` (`VoxelSlotMachine`, the arena's `slot`): against the north wall right of
  the chests (7, -21.15), a 1950s one-armed bandit on its own stand, built in code from 2.5 cm cubes (no files): the red
  faded to brick and chipped to grey at every edge, rust running down from the screws, a dent, four bullet holes and old
  blood in its left side, flames up both sides, cream front, dull pitted chrome (one strip of trim bent out), a brass pay
  table hanging crooked, the coin slot taped on, gum in the payout tray, a bare scuffed kick plate ("KICK HERE"), a foot
  missing (it leans; cardboard under the corner), coins and cigarette butts on the floor. The marquee: a cracked arch,
  "LUCKY SPUD" in gold (K and U dead, now and then flickering back), a crowned potato half its crown peeled off, twenty
  bulbs round it (six dead, three gone, one loose and always flickering); now and then the lot dims, cuts out, buzzes
  back. The bulbs chase (faster with someone stood at it), flash unevenly while it spins, all at once on a win, go dull
  red and out on three skulls.
- Three real drums (eight symbols each: cherries, bell, BAR, 7, spud, chicken, skull, THE BUTCHER; pixel art on a
  faceted drum, a blurred copy while spinning fast), lit from inside (the right one dying, flickering), behind smudged
  glass with a spiderweb crack, a faded orange win line, a WIN lamp with "BROKE" on a bit of tape.
- E at its front pulls the bent chrome lever (a chipped red ball, taped): it swings down, the reels start, it springs
  back wobbling (one in four sticks halfway, juddering, then clunks home). The outcome's picked at the pull; the reels
  stop left to right with a click and a clank, each a turn and a half on and a little past and back; the third waits
  longer when the first two match.
- The spider lives in the top of the window: now and then it lets itself down on a thread over a reel, dangles, goes
  back up; caught down there while they spin, or shaken down by a pull, it lands on a drum, rides round it, is flung off,
  bounces about behind the glass, lies on its back a moment and climbs back up the side.
- Next: what a pull costs and pays (the original's prizes), hitting it to stop the flickering, co-op.
- `test/voxel/slot_shots.gd` (`voxel_shots/slot_front.png`, `slot_reels.png`, `slot_flung.png`, `slot_win.png`,
  `slot_side.png`, `slot_lever.png`).

### The kill announcer (23 Oct, the owner: "like from Unreal ... double kill, multi kill, ultra kill")

- `scripts/voxel/arena/voxel_announcer.gd` (`VoxelAnnouncer`, the arena's `announcer`): kills within 3 s of each
  other chain: DOUBLE KILL (+$2), MULTI KILL (+$4), MEGA KILL (+$7), ULTRA KILL (+$10), MONSTER KILL (+$15),
  LUDICROUS KILL (+$25), then HOLY SHIT (+$40) for every kill after. Kills without going down are a spree: KILLING
  SPREE at 5 (+$10), RAMPAGE 10 (+$20), DOMINATING 15 (+$35), UNSTOPPABLE 20 (+$50), GODLIKE 25 (+$80), WICKED
  SICK 30 (+$120); going down ends it (SPREE OVER). The first kill is FIRST BLOOD; a kill with the head off or the
  brain shot through is a HEADSHOT (+$1). Big callouts in the upper middle (a punch in, colours climbing, HOLY SHIT
  in rainbow), what else it was under them, the bonus under that.
- Only this player's kills: a body remembers when this player last hit it (`VoxelBody.by_me`: stamped in `_net_in`
  for this game's own changes, and in `_net_block` for a co-op guest's own hits, never for the other game's replayed
  ones), and a death within 6 s of that is theirs. In co-op each of you gets your own callouts and bonuses.
- Voices: until there are recordings it plays stingers (`assets/voxel/tools/sfx_announcer.py`: announce_1..7, a
  spree swell, a headshot crack). A recording named for its line (double_kill, multi_kill, mega_kill, ultra_kill,
  monster_kill, ludicrous_kill, holy_shit, killing_spree, rampage, dominating, unstoppable, godlike, wicked_sick,
  headshot, first_blood, spree_over; .mp3, .ogg or .wav) in the `voices` folder next to the game's .exe (or
  user://voices, or `assets/voxel/sound/voice/` in the project) is played instead, no rebuild needed.
- Settings: Kill announcer: Off / Callouts only / Callouts and sound.
- Tests: `test/voxel/announcer_test.gd` (14 checks: first blood, the chain to HOLY SHIT and its bonuses, the spree,
  a pause ending the chain, a real headshot, someone else's kill counting for nothing, going down ending the spree,
  Off, a recording picked up); `test/voxel/announcer_shots.gd` (a MONSTER KILL, a HEADSHOT).

### The mine in pixels (23 Oct, the owner: "the graphics from my sandy digging game, rebuilt in Godot, every pixel destructible, really satisfying when drilling"; the ship, everything kept, chunky pixels, the launcher)

The mine's ground (below) was 1 m tiles; it's now Sand Miner's (the cabinet game in Smashed.html) pixel world:
- **`addons/mine_sim`** (a GDExtension, C++, built for Linux and Windows by `src/build.sh` against godot-cpp 4.4; the
  export puts `mine_sim.windows.x86_64.dll` next to the exe): `MineSim`, a grid of cells (8 a metre: 400 x 1248 with
  6 m of sky), each a material with its own shade, drilling damage and the back wall behind it. Sand and loose rubble
  fall and pile (sinking through water); water flows and pools; lava oozes, turns to obsidian against water and
  cools to basalt when it's sat open to the air ~30 s; thin crumbly bits of dirt and clay with nothing under them
  crumble off; chips knocked out fly and land as rubble. Only 32 x 32 chunks where something's moving are simulated
  (a step ~0.2 ms). It paints a window of itself as Sand Miner did (eight shades a material, dark outlines on edges,
  a soft shadow inside them, grass on top, rims round ore and rock, sparkles in silver, gold, opal and diamonds, cracks
  spreading as the drill works it, a darker back wall where it's dug; what glows into a second picture) into RGBA8.
- `mine_tiles.gd`: the materials (Sand Miner's palettes: coal, silver, gold and diamond's shades are its own) and back
  walls, handed to MineSim. New: sand (lenses that pour when undermined), water (pockets), obsidian.
- `mine_ground.gd`: makes the world from its seed through MineSim's primitives (zones with wavy edges, ore veins as
  rough blobs, boulders, gas, sand, water, little caves, the mushroom caves and the cathedral with a domed giant
  mushroom, the sewers' brick tubes, the bunker's slabs and lockers, the rivals' tunnels, timber, crates and shortcut,
  lava pockets, the worm's cavern, bedrock, the pads); draws the window round the camera each frame onto a quad at
  z = 0 in the mine's 3D world (lit by the lamps and the caves' glow; the ship, critters and decor just in front);
  saves the cells (zstd-packed) to their own file beside the backpack's save (`<save>_mine.bin`).
- **The drill** (`mine_ship.gd`): push into the ground (or hold S) and the bit works a ship-sized box in front of it
  cell by cell (each cell's damage rising with the drill's power over its hardness, faster at the near side and a
  little uneven so the face breaks up); the ship works its way in as the face gives (about 3 m/s through dirt with
  the first drill, 1 m/s through stone). It steps up small ledges, shoves through loose rubble and sand, floats and
  drags in water.
- **The feel**: crunches (five variants, pitched by the rock, played as it chews), sparks off hard rock (stone and
  harder), dust puffs, chips flying, the screen shaking with the rock's hardness, the bit glowing hot in hard rock, the
  ship rattling; ore drilled out pops as nuggets that fly to the ship (their chime climbing for a run of them); a
  split-second freeze on a rare find or a blast; a thump when you break through into open space.
- **The launcher** (Sand Miner's): the drill fills a hopper with the dirt, clay and sand it brings up (600 cells of
  each); right click (held) or F shoots 14 cells' worth where the mouse points (the arc shown while aiming), Q picks:
  dirt lands loose and piles, sand pours, clay sticks where it hits (wall off lava, build a ledge, block a tunnel).
  Shots squash rats, gum up cop drones (down they go) and knock the rival pods back. Its range is a mechanic upgrade
  (Slingshot 10 m/s, Spring gun 13, Air cannon 17, Rail launcher 22).
- The critters find their way on a half-metre map made from the cells; rats walk the pixel floors; the worm eats round
  tunnels through anything but bedrock (chunks flying) and its hoard is a heap of loose diamonds that tumbles out.
- Tests: `test/voxel/mine_test.gd` (48 checks, `--seed=N`: the zones, ore deeper, drilling down 5 m in 3 s through
  dirt, a gold vein into nuggets, a full hold, the dirt in the hopper, a Mk III boulder, gas, lava running into a
  tunnel, sand falling and piling, water pooling, a little lava settling, the trip, the cops, the crew, rats, the worm
  and its hoard, dynamite's nuggets, a clay shot sticking to a wall, saving and loading the cells, the tow, coming back
  up); `mine_shots.gd`, `mine_clip.gd`.

### The mine: dig mode (23 Oct, the owner: "build it all", the Motherload-style digging from their design notes)

- **Getting in:** a garage roller door in the yard side of the arena's south wall, between the buyer and the back
  door (`scripts/voxel/mine/mine_hatch.gd`, MINE sign over it). E at it: the door rolls up and the mine fades in.
  Up at the LIFT (top left of the mine) E takes you back to the yard. While you're down there the arena carries on
  (you're stood in the yard, where nothing comes for you); it isn't drawn (`disable_3d`), its keys and weapons are
  off. Solo or in co-op (the mine is each player's own).
- **Its own world:** `voxel_mine.gd` (`VoxelMine`, the arena's `mine`) draws a separate 3D world in a SubViewport on a
  CanvasLayer over the screen, with its own light: daylight up top, darker the deeper you go, the screen's edges
  fading dark with depth (a screen shader, which also does the mushroom trip and the red flash when you're hurt).
- **Keys:** A/D drive (push into rock to drill through it), S drill down, W/Up/Space thrusters, E use a building,
  1 dynamite, 2 repair kit, 3 teleport home; a building's menu: click a line or press its number, E/Esc closes.
- **The ground** (`mine_ground.gd`, `mine_tiles.gd`): 50 x 150 tiles of 1 m (the outer columns and the bottom row
  bedrock), side-on. Topsoil and clay, grey stone (from ~19 m), deep red rock (~50 m), black basalt (~86 m),
  glowing crystal rock (~121 m), the zones' edges wavy; each deeper zone slower to drill. Made the same every time
  from a seed (saved), drawn in 8 x 8 tile chunks (only a changed chunk is drawn again, ~0.5 ms), the pictures drawn
  in code into one atlas (16 px a tile, mirrored at random so it doesn't look tiled), what's dug darker with a soft
  shadow along the tunnels' edges, ores glinting in the dark.
- **Ores:** coal (from 3 m), copper, silver, gold (from 52 m), opal, diamonds (from 100 m): each most common at its
  own depth, in little veins, the deeper ones rarer and worth far more.
- **The ship** (`mine_ship.gd`): drives on what's dug, drills left, right and down (Motherload style: it slides into
  the tile as it's drilled; harder rock takes longer, the drill's level speeds it up), flies up on its thrusters,
  falls, hurts landing hard (over ~9 m/s) or hitting a wall fast. Fuel burns all the time (more driving, much more
  flying and drilling); out of fuel or wrecked, you're towed up top: the cargo's lost and there's a fee (40 + 10% of
  your cash). Its look changes with every upgrade: the drill bit (steel, bronze, gold, glowing diamond, bigger each
  time), the fuel tanks (a jerry can, then tanks along its side), the cargo crate on its back, the hull (yellow,
  teal with a skirt, red with plates, gunmetal with gold trim), the lamps on its nose (and how far its light reaches).
- **Up top:** FUEL (paid by the litre, the price changing day to day), TRADER (sell the hold: each price wobbles a
  fifth either way each day, one thing in demand at half as much again; a cash pop-up and the till; supplies:
  dynamite $120, repair kit $150, teleport home $260; a fresh claim, brand new ground, $400), MECHANIC (hull repairs,
  and the five upgrades, four levels each: drill 1x/1.6x/2.4x/3.6x (each level also opens a boulder tier), fuel
  tank 12/20/32/50 L, cargo 8/14/22/34, hull 30/50/80/125, lights 6/9/13/18 m), LIFT (back to the yard). The cash
  is the arena's own (`arena.cash`): one wallet with the kills, the farm and everything else.
- **HUD** (`mine_hud.gd`): fuel, hull, cargo, depth, cash, the supplies; a line in the middle for what happens, the
  prompt at a building, tips on the first dives (each once ever: how to drill, selling, low fuel, a full hold,
  boulders, lava, gas, the mushroom caves, the cops, the rivals, the worm), the worm's health bar, WANTED when the
  cops are after you.
- **Hazards:** boulders that need a better drill (granite Mk II, ironstone Mk III, obsidian Mk IV); gas pockets
  (greenish patches) that go off when drilled (they blow the rock open round them, hurt, set off gas next to them);
  lava pockets that glow, flow out into whatever you dig (falling, spreading), burn the hull, and cool to basalt after
  sitting still 30 s (never round the ship); little natural caves.
- **Mushroom caves** (five, 30..100 m): open caves with a purple back wall that glow through the dirt round them,
  mushrooms on their floors, spore clumps to sell, fool's gold in their walls (looks like gold, crumbles to nothing).
  In one you trip: the screen swims and shifts colour, the ship floats (gravity down to 40%), and the steering
  drifts, more the longer you stay; it wears off slowly once you're out. **The mushroom cathedral** (~113 m): a huge
  cave with a giant mushroom in it (each of its tiles sells as Giant mushroom), a stronger trip.
- **Trial hazards** (each switched off or on in the settings, F10: Mine: sewers and rats / the cop bunker / rival
  dealers' tunnels; off: their critters are gone at once, the tunnels themselves on the next fresh claim):
  - the **sewers** (two brick tunnels a few metres down): junk in their walls (a bit of cash), rats that run along the
    floors and chew the hull when they're on you (drive over them fast to squash them; more come out while you're
    away);
  - the **cop bunker** (~40..55 m): a concrete box (needs Mk II) with red and blue lights that show through its cracks
    (weak spots of plain stone), evidence lockers inside (worth a lot). Get in (or drill its walls) and the alarm goes:
    three drones come after you through your own tunnels (they find their way by a map of the open tiles from the
    ship); one touches you and you're BUSTED: the cargo and a fifth of your cash taken, towed up. Ram one fast and it's
    scrap; get up top or keep away for 50 s and they give up (the bunker rests a minute before it can go off again);
  - the **rival dealers' tunnels** (~70..84 m): timber-propped tunnels with lanterns, their stash at the ends (sells),
    a hidden shaft from just under the topsoil down to them (their shortcut), and their crew: three red pods that
    patrol and come for you when you're near, ramming (7 hull). Ram them back harder (fly at them fast) and they
    break up after three ($60 scrap), or run: they give up when you're far off.
- **The rock worm** (`mine_worm.gd`, the bottom cavern): wakes when you come below ~126 m, burrows through anything
  but bedrock (eating tunnels as it goes), wriggles at you and bites (14, harder when it's below half). Ram it fast,
  drill into it, or dynamite it (32); dead, it pops segment by segment and its diamond hoard (14 hoard diamonds, $900
  each on an ordinary day) spills out where it died. Once a ground (a fresh claim brings a new one).
- **Supplies:** dynamite blows the rock round you open (ore in it scooped into the hold, the critters and the worm
  in it hurt); a repair kit patches 40% of the hull; the teleport beams you up top with your cargo.
- **Sounds** (`assets/voxel/tools/sfx_mine.py`): the drill's whine (pitched by how hard the rock is for your drill),
  the engine and thrusters, ore clinking in, hull knocks, the low-fuel beeps, the till, blasts, the siren, rats,
  the worm's roar, the roller door, crumbling, the teleport, lava's hiss.
- **Saved** with the backpack (VoxelStorages, the "mine" key): upgrades, fuel, hull, cargo, supplies, the ground (its
  seed and every tile as it is), the worm, the tips seen.
- **Tests:** `test/voxel/mine_test.gd` (headless, 39 checks: the door, going down, the zones and ores, drilling down
  and sideways, a full hold, fuel, selling and the price wobble, upgrades, a boulder needing Mk III, gas, lava
  flowing, the trip, the bunker's alarm and being busted, the rival crew ramming, the rats, the worm and its hoard,
  dynamite, saving and loading, the tow, coming back up; `--seed=N` for a particular ground);
  `test/voxel/mine_shots.gd` (pictures: the door, the surface, a shaft, ore, a mushroom cave, the bunker, the rivals,
  lava, the cathedral, the worm, the trader, the ship basic and fully upgraded); `test/voxel/mine_clip.gd` (a film
  played by an autopilot).
- Not in it (from the notes): co-op digging together, fighting on foot, the tunnel to St Kilda (needs the travel
  map), Dope Wars trading.

### The trailer (22 Oct, the owner: "cheery, happy music, feeding the chickens and digging and catching worms, then
cutting to the fight ... one step of the peaceful stuff, then back to gory")

- `tools/trailer/` (not part of the game): `make_music.py` writes the music (ours: a ukulele-and-glockenspiel tune
  made in numpy, 120 bpm, I-V-vi-IV; claps and a shaker in from bar 5, a kick in the busy part; a tape stop and a
  record scratch at 44 s, silence for THE BUTCHER, a sting for the title at 48.5 s, a soft tag for the last shot);
  `trailer.gd` plays the shot list in the real game in time with it (29 shots, bars of 2 s: the yard, a shotgun to a
  grunt, hens, a sword through a neck, digging up a worm, the harpoon tearing an arm off, watering crops as they
  grow, the chainsaw through a brute, chicks; the loop with words: "Grow your own..." the shredder, "...with 100%
  organic fertiliser" the crops shooting up, "Upgrade." the weapon bench, "Repeat." a DAMAGE 3 shotgun; then the
  swaps faster: grenades, the couch and the TV, the flamethrower, the bedroom, a frozen one smashed, hens by the
  coop, the laser through a neck, the crops, a home run, eggs, a charger, a crowd; the scratch, "WAVE 5 THE BUTCHER"
  walking in, his fists up and down, black; SMASHED TV "Grow. Dig. Feed the chickens. Kill everything."; a hen
  pecking by a head on the grass, "Co-op for two · PC"). Letterboxed, the HUD hidden; the farm from cameras of its
  own, the fights first person, the weapons pressed as a player would (a head or a limb taken off by hand only if
  the swing missed). `render.sh out.mp4` does it all: the music, Godot's movie maker (Forward+, Ultra, 30 fps,
  every frame however long it takes: about 22 minutes on a CPU), the game's own sound mixed under the music, H.264.
  `-- --only=NAME --stills=dir` plays one shot and saves four stills of it, to change one without the rest.
- The result: `downloads/SmashedVoxelArena-trailer.mp4` (57.5 s, 1280x720).

### The overnight work's bug sweep (Stage 14, 22 Oct)

Three reviewers read Stages 10-13 (settings and the bench; the kinds; the waves and the boss); every finding was
checked against the code before it was fixed (`kinds_test` 19 checks, `waves_test` 19 now):
- DAMAGE scaled a hole's radius, so the cubes (and health) went up by its cube (x4.5 at x1.65): the radius now goes
  up by the cube root (the cubes by the level's number), a carve's health a cube not at all.
- The weapon bench and the tool bench could be used through the arena's south wall: only from the yard now.
- Health off a body that no weapon did (bowled over, a charger into a pillar) took the local player's DAMAGE:
  `arena._plain_hurt`.
- Any purchase refilled the clips: only a CLIPS one does. The fire bomb asked for the unscaled fuel.
- The benchmark: its grenades froze time a blink (hit-stop: lighter frames, a rosier result) and kicked the view;
  its fight took the player's DAMAGE; the waves kept walking in during it; its extra pieces outlived it. All fixed;
  after it, the same kinds come back (the boss too), not a random lot.
- F2 (or anything that starts the fight over) swapped the boss for a random enemy: the same kinds come back
  (`living_kinds`, `_respawn_all(count, kinds)`).
- The guest's copy of the boss didn't know he's tough (his limbs came off three times sooner there, then popped
  back): his toughness and full health are in the body's birth; a guest joining mid-boss gets his bar's full health
  in the welcome.
- A frozen boss shattered whole at the next knock: tough ones frost over (slower) but never freeze solid.
- The test set-ups (--weaponshots, --meleetest ...) got waves; F12 off and on jumped the wave number (one at a time
  counts each enemy): the waves pick up where they were, the old wave's leftovers dropped.
- The shield's bone was under the forearm but held at the fingertips: the hand off left it floating, still
  blocking. It's under the hand now. Steel doesn't burn. The guest's copy of a glob splats on the guest too. A
  dazed charger set alight runs about. The boss goes round pillars at his own size; his angry wind-up poses right.

### The whole-game bug sweep (22 Oct, the owner: "check over the whole game for bugs")

- A multi-agent sweep read the whole voxel game (about 31,000 lines): one finder per area plus co-op, saving,
  object-lifetime and long-session checks, each area read twice. 164 suspects, 127 after merging duplicates, each checked by
  skeptics told to refute it (every medium or high one by two): **109 confirmed** (6 high, 23 medium, 80 low), 18 thrown out.
  All 109 fixed, in four commits: A (the bodies), B (co-op and weapons), C (the backpack, saving, the arena), D (the 60 low
  ones, fixed in parallel by six agents on separate files, each fix independently reviewed).
- What changed that a player might notice: a full backpack never turns items into rubble (non-cube items **wait**, saved,
  and go in when there's room); kill cash is saved; F2's cube size sticks; a downed player can't attack; co-op deaths are the
  host's call and the host's F6 reaches the guest; the guest's view no longer jerks on hit-stops; hanging limbs swing the same
  at any frame rate (fixed 240 Hz steps); pistol and shotgun holes make limbs hang; the gravity gun carries corpses out the
  back door to the yard; a joining guest gets the host's lying cubes; the spear stays in step in co-op; benchmark kills
  don't pay; the room-code box takes IPv6 and host names; Tornado Tyson looks right in blocks.
- Tests: `test/voxel/sweep_test.gd` (30 checks) and `sweep_arena_test.gd`, `sweep_net_test.gd`, `sweep_weapons_test.gd`,
  `sweep_yard_test.gd`, `sweep_games_test.gd`, `sweep_misc_test.gd` (123 more); `weapons_smoke.gd` (every weapon on a crowd,
  frame times). The shredder and health co-op tests were made robust (a race in the shredder one was also a real glitch: a
  guest could take a bag the host hadn't made yet).

### The online menu (22 Oct, the owner: "can you make it easier to join? I like the set up in the last game")

- `scripts/voxel/net/voxel_net_menu.gd`, the main game's PLAY ONLINE panel (`NetMenu`) rebuilt for the voxel game:
  an ONLINE (O) button top right (it shows the state: waiting, host / guest and the room); the panel has the status
  line, HOST A GAME (a new 4-letter room, shown big, **copied to the clipboard**: paste it to your mate), the code box
  with JOIN and PASTE (opening the menu **fills the box** from a code you've copied, even inside a message like "join
  me, code K7QD", or else with the last room you joined, kept in `user://voxel_online.cfg`), the on-screen letters,
  LEAVE GAME, CLOSE, and SAME HOUSE? HOST DIRECT (ENet on the port; your home-network address shown and copied; the
  other types it in the code box). While the host waits the room code shows big on screen. A room code that's taken
  gets a new one by itself (three goes). The game behind takes no keys, clicks or walking while it's open. F7 still
  hosts (and copies the code), Shift+F7 hosts direct, F8 opens the menu; the co-op line moved top right under the
  button. `--server` / `--local` apply to the menu's rooms too (tests).
- Tests: `test/voxel/net_menu_test.gd` (9 checks alone; `--as-host` / `--as-guest` 3 + 3, done with the menu's buttons:
  HOST DIRECT and the address typed in, or `--room=CODE` with a local PeerJS server, HOST A GAME and the code typed in:
  both link), `test/voxel/net_menu_shots.gd` (`voxel_shots/online_*.png`).

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
