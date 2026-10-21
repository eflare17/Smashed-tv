class_name VoxelArena
extends Node3D
## The PC voxel arena test (PLAN.md, 20 Oct: "PC only, voxel destruction"). One arena, block enemies (grunt,
## swarmer, brute, batter) coming at you one at a time (F3 / F5 send in more), and every shot makes a hole exactly
## where it hits: the cubes there are knocked out (flying, bouncing, settling), the meat and bone inside show, a limb shot mostly away comes off, a head
## or chest shot through drops them. Only the hit body parts are meshed again, on worker threads, a few a frame.
## The top left shows what it costs (frame rate, frame time, draw calls, triangles, cubes flying, meshing jobs).
## Owned by the voxel session. Desktop renderer (Forward+); the Windows build boots straight into this scene.
##
## Keys: Tab (or I) the backpack, E at a chest or cabinet opens it (elsewhere: the vacuum and back), L at a chest its
## padlock, E at a bed lies down on it, WASD move, mouse look, 1-5 the weapon groups (melee, guns, special, explosives, the vacuum; the key again for
## the next one in it), the wheel, Q the last weapon, both mouse buttons the weapon's own two moves, R reload,
## Shift run, Space jump, V top-down / first person, F1 shadows, F2 cube size (1 or 2 sprite pixels a cube), F3 ten
## more enemies, F4 freeze them, F5 a big wave (40), Esc frees the mouse (click to grab it again).
##
## Testing (after -- on the command line): --auto (it aims at the nearest enemy and fires by itself, single shots
## and blasts), --enemies=N, --shot=path.png and --secs=S (save a screenshot after S seconds and quit),
## --topdown, --chunk=2, --stats (print the frame numbers every second).

const KEYS := ["grunt", "grunt", "swarmer", "swarmer", "brute", "batter", "batter", "batter"]
const HEIGHT := {"grunt": 1.85, "swarmer": 1.7, "brute": 2.2, "batter": 1.9}
const MAX_JOBS := 12            # meshing jobs running at once
const ARENA := 22.0             # half the arena's width, metres
const PILLARS := [Vector3(-8, 0, -8), Vector3(8, 0, -8), Vector3(-8, 0, 8), Vector3(8, 0, 8)]
const PILLAR_HALF := 0.6        # half a pillar's width (they're 3.5 m tall)
const MAX_DEAD := 40
## The player's health (the owner, 21 Oct: "add health"): enemies' swings, blasts, fire take it; it comes back slowly
## after a while unhurt; at nothing you're down (no moving, no weapons) till you get up again, or (co-op) your mate
## stands by you a moment and gets you up.
const HP_MAX := 100.0
const REGEN_WAIT := 5.0         # seconds unhurt before health comes back ...
const REGEN := 4.0              # ... this much a second
const DOWN_SOLO := 4.0          # seconds down before getting up alone ...
const DOWN_COOP := 15.0         # ... and in co-op (your mate can get you up first)
const REVIVE_R := 1.6           # metres your mate stands within ...
const REVIVE_T := 2.5           # ... for this long to get you up
const SWING_HURT := {"grunt": 6.0, "swarmer": 4.0, "brute": 12.0, "batter": 8.0}
const BURN_TOUCH := 6.0         # health a second brushing against one on fire            # corpses and lying pieces kept (the oldest go past this; the vacuum takes them too)

var chunk := 1                  # sprite pixels a cube
var bodies: Array[VoxelBody] = []
var debris: VoxelDebris
var player: CharacterBody3D
var cam: Camera3D
var avatar: VoxelBody
var sun: DirectionalLight3D
var hud: Label
var help: Label
var cross: Label
var top_down := false
var frozen := false
var wave := 0
var knocked := 0
var kills := 0
var look_yaw := 0.0
var look_pitch := 0.0
var _jobs := []                 # [{id, body: WeakRef, part, out: Dictionary}]
var _jobs_done := 0
var _fire_cd := 0.0
var _sg_cd := 0.0
var _hud_t := 0.0
var _flash: OmniLight3D
var _flash_t := 0.0
var _tracers: MeshInstance3D
var _tracer_list := []          # [{a, b, t}]
var _mat: StandardMaterial3D
var _kick := 0.0
var _opts := {}
var _t := 0.0
var _stat_t := 0.0
var _frames := PackedFloat32Array()
var _next_t := 0.0
var _code_ms := 0.0            # the arena's own code a frame (smoothed)
var _prof := {}                 # section -> microseconds this second (--stats)
## The melee weapons (the owner, 20 Oct: five, each doing something different): weapon id -> script; one whose
## file isn't there is left out of the slots.
## Every weapon with a script (VoxelMelee: melee, guns, the special ones): weapon id -> script; one whose file isn't
## there is left out of the slots.
const MELEE := {"sword": "res://scripts/voxel/arena/voxel_sword.gd", "bat": "res://scripts/voxel/arena/voxel_melee_bat.gd",
	"hammer": "res://scripts/voxel/arena/voxel_melee_hammer.gd", "chainsaw": "res://scripts/voxel/arena/voxel_melee_chainsaw.gd",
	"spear": "res://scripts/voxel/arena/voxel_melee_spear.gd",
	"pistol": "res://scripts/voxel/arena/voxel_gun_pistol.gd", "shotgun": "res://scripts/voxel/arena/voxel_gun_shotgun.gd",
	"laser": "res://scripts/voxel/arena/voxel_weapon_laser.gd", "flamethrower": "res://scripts/voxel/arena/voxel_weapon_flamethrower.gd",
	"freezeray": "res://scripts/voxel/arena/voxel_weapon_freezeray.gd", "harpoon": "res://scripts/voxel/arena/voxel_weapon_harpoon.gd",
	"gravity": "res://scripts/voxel/arena/voxel_weapon_gravity.gd", "grenades": "res://scripts/voxel/arena/voxel_weapon_grenades.gd",
	"shovel": "res://scripts/voxel/arena/voxel_tool.gd", "pick": "res://scripts/voxel/arena/voxel_tool.gd"}
var loadout := VoxelLoadout.new()   # the weapon slots in their groups: keys 1-5, the wheel, Q the last one
var sound: VoxelSound           # every sound (VoxelSound)
var me: VoxelShooter            # the local player, as the weapons see whoever holds them
var player_hp := HP_MAX
var down_t := 0.0               # seconds left down (0: up)
var godmode := false            # (--godmode: the player can't be hurt)
var _since_hurt := 99.0
var _revive := 0.0
var _hurt_fx := 0.0
var _hp_bar: ColorRect
var _hp_back: ColorRect
var _hp_label: Label
var _vignette: ColorRect
var _down_label: Label
var net = null                  # VoxelNet when playing with someone (null alone)
## The backpack, the chests and the screen to move things between them (the owner, 21 Oct, Stage 2: "a proper
## inventory" in place of the vacuum's counts, and storage chests/cabinets).
var inv := VoxelInventory.new(24)
var stash: VoxelStorages
var inv_ui: VoxelInventoryUI
static var blocks := []         # walkers kept out of these too, like the pillars: [centre, half x, half z] (the chests)
var _near_st: VoxelStorage      # the chest the player is at (E opens it)
var _use_label: Label
var _say_label: Label
var _say_t := 0.0
var lost := 0                   # cubes sucked up with the backpack full (gone)
## The bedroom through the south wall (Stage 3): its beds, the chests at their feet with their padlocks.
var house: VoxelBedroom
var lock_view: VoxelLockView
var lock_then_chest := false    # the padlock was opened to get into the chest: once it springs open, the chest opens
var _unlock_t := 0.0
var lying := 0                  # the bed (1, 2) lain on, 0 standing
## The back yard (Stage 4): ground to dig with the shovel and the pick, the tool bench.
var yard: VoxelYard
var shovel_tier := 0            # 0 rusty, 1 good, 2 golden (made at the tool bench; saved)
var _near_bench := false
var _near_bed := 0
var _near_ward := false
var _self_t := 0.0
var hold_suck := false          # (tests: the vacuum's click held down)
var flames: VoxelFlames         # fire, as little glowing cubes
var melee := {}                 # weapon id -> its VoxelMelee
var sword: VoxelSword           # melee.sword (F slashes with it whatever is out)
var pieces: VoxelPieces         # the bits melee weapons take off, lying about
var vacuum: VoxelVacuum
var bar: VoxelWeaponBar
var _sucking := false
var _held := {}                 # mouse button -> true: down since a press the melee weapon out was told of
var _ignore := {}               # mouse button -> true: down since before the last switch (ignored till let go)
var _clicked := {}              # mouse button -> true: pressed since the last frame (a click quicker than a frame)
var _aiming := false            # a gun aimed in (the pistol's right click): the view closes in
var _aim_k := 0.0               # 0 at the hip .. 1 aimed (the view closes in)
var _hand_id := "-"             # top-down: what Jared's hand holds now
var _hands := []                # top-down: the BoneAttachment3Ds holding it
var _hud_layer: CanvasLayer
var _dash_v := Vector3.ZERO     # a forced dash (a chainsaw's lunge): the player moves at this, not by the keys
var _dash_t := 0.0
var _mouse_v := Vector2.ZERO    # the mouse's recent movement (the way a slash goes)
var _flip := 1.0                # still mouse: slashes go back and forth

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		_opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	chunk = int(_opts.get("chunk", "1"))
	top_down = _opts.has("topdown")
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.95
	_world()
	_player()
	_hud()
	debris = VoxelDebris.new()
	add_child(debris)
	debris.setup(_cube_m("grunt"))
	debris.bound = ARENA - 0.5 - _cube_m("grunt")     # the walls' inner faces: cubes bounce off them
	debris.rooms = _rooms()
	_tracers = MeshInstance3D.new()
	_tracers.mesh = ImmediateMesh.new()
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.9, 0.5)
	tm.emission_enabled = true
	tm.emission = Color(1.0, 0.8, 0.3)
	_tracers.material_override = tm
	_tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tracers)
	sound = VoxelSound.new()
	add_child(sound)
	flames = VoxelFlames.new()
	add_child(flames)
	flames.setup(_cube_m("grunt"))
	VoxelBody.on_shatter = func(b: VoxelBody, bits: Array, dir: Vector3) -> void:
		knocked += bits.size()
		debris.burst(bits, dir.normalized() if dir.length() > 0.01 else Vector3.UP, 3.0)
		sound.play("shatter", b.global_position)
	pieces = VoxelPieces.new()
	add_child(pieces)
	pieces.setup(self)
	debris.on_take = _on_take
	stash = VoxelStorages.new()
	add_child(stash)
	stash.setup(self)
	blocks = stash.blocks()
	# saved between games (not the self-tests'; --save=path elsewhere, --nosave never)
	var testing := false
	for t in ["auto", "meleetest", "weaponshots", "swordtest", "walkcheck", "nosave", "secs"]:
		testing = testing or _opts.has(t)
	stash.save_path = String(_opts.get("save", "")) if _opts.has("save") else ("" if testing else VoxelStorages.SAVE_PATH)
	stash.load_save()
	var have := []
	me = VoxelShooter.local_for(self)
	for id in MELEE:
		if ResourceLoader.exists(MELEE[id]):
			var w: VoxelMelee = load(MELEE[id]).new()
			add_child(w)
			w.setup(self, me, id)
			melee[id] = w
			have.append(id)
	sword = melee.get("sword")
	set_shovel_tier(shovel_tier)          # (the save's, loaded before the tools were made)
	vacuum = VoxelVacuum.new()
	add_child(vacuum)
	vacuum.setup(self, cam)
	have.append("vacuum")
	loadout.keep_only(have)
	if loadout.index_of("pistol") >= 0:
		loadout.select(loadout.index_of("pistol"))       # the pistol out first
		loadout.switch_t = 0.0
		me.weapon = "pistol"
		melee.pistol.on_select()
	bar = VoxelWeaponBar.new()
	_hud_layer.add_child(bar)
	bar.setup(loadout, self)
	inv_ui = VoxelInventoryUI.new()
	_hud_layer.add_child(inv_ui)
	inv_ui.setup(self, inv)
	lock_view = VoxelLockView.new()
	_hud_layer.add_child(lock_view)
	lock_view.setup(self)
	cam.cull_mask &= ~(1 << (VoxelMirror.LAYER_SELF - 1))      # (your own Jared in first person: the mirror's only)
	_warm_up()
	net = VoxelNet.new()
	add_child(net)
	net.setup(self)
	net.changed.connect(_net_hud)
	if _opts.has("walkcheck"):
		_walkcheck_setup()
	elif _opts.has("swordtest"):
		_swordtest_setup()
	elif _opts.has("meleetest"):
		_meleetest_setup()
	elif _opts.has("weaponshots"):
		frozen = true
		spawn(1)
	elif _opts.has("enemies"):
		wave = 1
		spawn(int(_opts.enemies))
	else:
		_next_wave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (top_down or _opts.has("auto")) else Input.MOUSE_MODE_CAPTURED
	# --host=CODE / --join=CODE (co-op straight away; --via=enet for an address, --server=ws://... a PeerJS server,
	# --local no STUN/TURN)
	godmode = _opts.has("godmode") or _opts.has("auto") or _opts.has("meleetest") or _opts.has("weaponshots") or _opts.has("swordtest")
	if _opts.has("host") or _opts.has("join"):
		net.debug = _opts.has("netdebug")
		net.lag = float(_opts.get("lag", "0")) / 1000.0       # (--lag=ms, --loss=% : a bad line, for the tests)
		net.loss = float(_opts.get("loss", "0")) / 100.0
		var via := String(_opts.get("via", "rtc"))
		if _opts.has("host"):
			net.host(String(_opts.host), via, String(_opts.get("server", "")), _opts.has("local"))
		else:
			net.join(String(_opts.join), via, String(_opts.get("server", "")), _opts.has("local"))
	print("VoxelArena: ready (renderer ", RenderingServer.get_current_rendering_method(), ")")

func _cube_m(key: String) -> float:
	var md := VoxelModel.get_model(key)
	var rows := float(md.rig.get("ref_rows", 80)) if md else 80.0
	return float(HEIGHT.get(key, 1.85)) / rows * float(chunk)

# ---------------------------------------------------------------- the place

func _world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.45, 0.68)
	sm.sky_horizon_color = Color(0.7, 0.72, 0.75)
	sm.ground_horizon_color = Color(0.45, 0.42, 0.4)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-35), 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	# the floor: the Smash TV arena's dark grid, big tiles
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ARENA * 2.0, ARENA * 2.0)
	floor_mi.mesh = pm
	var fs := ShaderMaterial.new()
	fs.shader = Shader.new()
	fs.shader.code = """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = abs(fract(w.xz / 2.0 + 0.5) - 0.5) * 2.0;
	float line = 1.0 - smoothstep(0.0, 0.025, min(1.0 - g.x, 1.0 - g.y));
	float n = fract(sin(dot(floor(w.xz / 2.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = mix(vec3(0.018, 0.02, 0.028) * (0.8 + 0.4 * n), vec3(0.08, 0.1, 0.2), line);
	ROUGHNESS = 0.8;
}
"""
	floor_mi.material_override = fs
	add_child(floor_mi)
	var fb := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(ARENA * 2.0, 1.0, ARENA * 2.0)
	fc.shape = fsh
	fc.position = Vector3(0, -0.5, 0)
	fb.add_child(fc)
	add_child(fb)
	# walls and a few pillars
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.16, 0.17, 0.22)
	wall_mat.roughness = 0.9
	for i in range(1, 4):
		var a := i * PI / 2.0
		_box(Vector3(sin(a) * ARENA, 2.0, cos(a) * ARENA), Vector3(ARENA * 2.0 if i % 2 == 0 else 1.0, 4.0, 1.0 if i % 2 == 0 else ARENA * 2.0), wall_mat)
	# the south wall: the bedroom's doorway (Stage 3) and the back door to the yard (Stage 4) in it
	var gaps := [[VoxelBedroom.DOOR_X0, VoxelBedroom.DOOR_X1], [VoxelYard.DOOR_X0, VoxelYard.DOOR_X1]]
	var from := -ARENA - 0.5
	for g in gaps:
		_box(Vector3((from + float(g[0])) * 0.5, 2.0, ARENA), Vector3(float(g[0]) - from, 4.0, 1.0), wall_mat)
		_box(Vector3((float(g[0]) + float(g[1])) * 0.5, (VoxelBedroom.DOOR_H + 4.0) * 0.5, ARENA), Vector3(float(g[1]) - float(g[0]), 4.0 - VoxelBedroom.DOOR_H, 1.0), wall_mat)
		from = float(g[1])
	_box(Vector3((from + ARENA + 0.5) * 0.5, 2.0, ARENA), Vector3(ARENA + 0.5 - from, 4.0, 1.0), wall_mat)
	house = VoxelBedroom.new()
	add_child(house)
	house.setup(self)
	yard = VoxelYard.new()
	add_child(yard)
	yard.setup(self)
	var pil := StandardMaterial3D.new()
	pil.albedo_color = Color(0.3, 0.12, 0.35)
	pil.emission_enabled = true
	pil.emission = Color(0.5, 0.1, 0.6)
	pil.emission_energy_multiplier = 0.15
	for p in PILLARS:
		_box(p + Vector3(0, 1.75, 0), Vector3(PILLAR_HALF * 2.0, 3.5, PILLAR_HALF * 2.0), pil)

func _box(at: Vector3, size: Vector3, mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.position = at
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	add_child(sb)

func _player() -> void:
	player = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	player.add_child(cs)
	player.position = Vector3(0, 0, 6)
	add_child(player)
	cam = Camera3D.new()
	cam.fov = 80.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.4)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	add_child(_flash)
	# Juicy Jared in blocks, seen in the top-down view
	avatar = VoxelBody.new()
	add_child(avatar)
	avatar.setup("jared", 0.0125 * 2.0, 2, _mat)
	avatar.visible = false

func _hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	_hud_layer = cl
	hud = Label.new()
	hud.position = Vector2(12, 10)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 5)
	cl.add_child(hud)
	help = Label.new()
	help.text = "Tab backpack   E open a chest (or the vacuum)   6 dig (yard)   1-5 weapon groups (again: next in it) or wheel   Q last   R reload   F quick sword slash   WASD move   mouse look   Shift run   Space jump   V view   F1 shadows   F2 cube size   F3 +10 enemies   F4 freeze   F5 big wave   F6 can't die   Esc mouse"
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 4)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.offset_top = -30
	cl.add_child(help)
	cross = Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 28)
	cross.add_theme_color_override("font_outline_color", Color.BLACK)
	cross.add_theme_constant_override("outline_size", 4)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.offset_left = -8
	cross.offset_top = -20
	cl.add_child(cross)
	# health: a red flash round the edge when hurt, a bar bottom left, a line in the middle when down
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; uniform float k = 0.0; uniform float grey = 0.0; void fragment() { vec2 d = UV - 0.5; float e = smoothstep(0.25, 0.75, length(d) * 1.3); COLOR = vec4(mix(vec3(0.7, 0.0, 0.0), vec3(0.08), grey), clamp(e * k + grey * 0.45, 0.0, 0.9)); }"
	vm.shader = sh
	_vignette.material = vm
	cl.add_child(_vignette)
	_hp_back = ColorRect.new()
	_hp_back.color = Color(0, 0, 0, 0.55)
	_hp_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_back.position = Vector2(16, -160)          # (above the weapon bar)
	_hp_back.size = Vector2(220, 18)
	cl.add_child(_hp_back)
	_hp_bar = ColorRect.new()
	_hp_bar.color = Color(0.85, 0.12, 0.12)
	_hp_bar.position = Vector2(2, 2)
	_hp_bar.size = Vector2(216, 14)
	_hp_back.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.position = Vector2(226, -3)
	_hp_label.add_theme_font_size_override("font_size", 16)
	_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hp_label.add_theme_constant_override("outline_size", 5)
	_hp_back.add_child(_hp_label)
	_down_label = Label.new()
	_down_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_down_label.offset_top = 40
	_down_label.offset_left = -300
	_down_label.offset_right = 300
	_down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_down_label.add_theme_font_size_override("font_size", 28)
	_down_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_down_label.add_theme_constant_override("outline_size", 7)
	cl.add_child(_down_label)
	# "E  open Chest" in the middle when at one; a message line under it (the backpack full)
	_use_label = Label.new()
	_use_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_use_label.offset_top = 30
	_use_label.offset_left = -250
	_use_label.offset_right = 250
	_use_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_use_label.add_theme_font_size_override("font_size", 20)
	_use_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_use_label.add_theme_constant_override("outline_size", 6)
	cl.add_child(_use_label)
	_say_label = Label.new()
	_say_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_say_label.offset_top = 70
	_say_label.offset_left = -400
	_say_label.offset_right = 400
	_say_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_say_label.add_theme_font_size_override("font_size", 18)
	_say_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_say_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_say_label.add_theme_constant_override("outline_size", 6)
	cl.add_child(_say_label)

# ---------------------------------------------------------------- enemies

## One enemy at a time (the owner, 20 Oct): the next walks in a moment after the last one drops.
func _next_wave() -> void:
	wave += 1
	spawn(1)

# ---------------------------------------------------------------- the player's health

## The player hurt (an enemy's swing, a blast, fire); nothing while down, or with --godmode.
func hurt_player(amount: float) -> void:
	if godmode or down_t > 0.0 or amount <= 0.0:
		return
	player_hp -= amount
	_since_hurt = 0.0
	_hurt_fx = minf(1.0, _hurt_fx + 0.25 + amount / 25.0)
	_kick = maxf(_kick, minf(1.2, 0.3 + amount / 30.0))
	if amount >= 2.0:
		sound.play("hit_flesh", Vector3.INF, -4.0, 0.8)
	if player_hp <= 0.0:
		player_hp = 0.0
		down_t = DOWN_COOP if net.linked else DOWN_SOLO
		_revive = 0.0
		_let_go()
		sound.play("crunch", Vector3.INF, 0.0, 0.7)

# who an enemy is at: 0 this player, 1 the other (co-op: their game takes it)
func _hurt_target(i: int, amount: float) -> void:
	if i == 0 and down_t <= 0.0:
		hurt_player(amount)
	elif i == 1:
		net.hurt_other(amount)

## A blast or a fire's heat round p: every player within r metres hurt, by how near (the host's or alone; a guest's
## copies of weapons don't).
func hurt_players_near(p: Vector3, r: float, amount: float) -> void:
	if net.role == "guest" and net.linked:
		return
	var mine := player.global_position + Vector3(0, 0.9, 0)
	if mine.distance_to(p) < r:
		hurt_player(amount * (1.0 - mine.distance_to(p) / r))
	if net.linked and net.other:
		var theirs: Vector3 = net.other.player.global_position + Vector3(0, 0.9, 0)
		if theirs.distance_to(p) < r:
			net.hurt_other(amount * (1.0 - theirs.distance_to(p) / r))

# the weapon out lets go of whatever's held (going down)
func _let_go() -> void:
	var id := loadout.id()
	if melee.has(id):
		for btn in _held:
			if _held[btn]:
				melee[id].release(btn)
				net.local_input("release", btn)
	_held.clear()

# regeneration, the red flash fading, down: the count, your mate getting you up, getting up
func _health_step(dt: float) -> void:
	_since_hurt += dt
	_hurt_fx = maxf(0.0, _hurt_fx - dt * 1.5)
	if down_t > 0.0:
		down_t -= dt
		var near: bool = net.linked and net.other and not net.other_down and net.other.player.global_position.distance_to(player.global_position) < REVIVE_R
		_revive = _revive + dt if near else maxf(0.0, _revive - dt)
		if _revive >= REVIVE_T or down_t <= 0.0:
			player_hp = HP_MAX * (0.5 if _revive >= REVIVE_T else 1.0)
			down_t = 0.0
			_revive = 0.0
			_since_hurt = 0.0
			sound.play("switch", Vector3.INF, -2.0, 0.7)
	elif lying > 0 and player_hp < HP_MAX:
		player_hp = minf(HP_MAX, player_hp + REGEN * 3.0 * dt)      # (resting in bed)
	elif _since_hurt > REGEN_WAIT and player_hp < HP_MAX:
		player_hp = minf(HP_MAX, player_hp + REGEN * dt)
	if _hp_bar:
		_hp_bar.size.x = 216.0 * player_hp / HP_MAX
		var mate := ""
		if net.linked and net.other:
			mate = "     mate %d%s" % [int(net.other_hp), " DOWN" if net.other_down else ""]
		_hp_label.text = "%d%s" % [int(ceil(player_hp)), mate]
		(_vignette.material as ShaderMaterial).set_shader_parameter("k", _hurt_fx)
		(_vignette.material as ShaderMaterial).set_shader_parameter("grey", 1.0 if down_t > 0.0 else 0.0)
		if down_t > 0.0:
			_down_label.text = ("DOWN — up in %d   (your mate can get you up: %d%%)" % [ceili(down_t), int(_revive / REVIVE_T * 100.0)]) if net.linked else "DOWN — up in %d" % ceili(down_t)
		elif net.linked and net.other_down:
			_down_label.text = "your mate is DOWN — stand by them to get them up"
		else:
			_down_label.text = ""

# ---------------------------------------------------------------- the bedroom: padlocks, beds

## A chest's padlock up close to dial (then_chest: opened by E at a locked chest, the chest opens once it springs).
func open_lock(st: VoxelStorage, then_chest: bool) -> void:
	_let_go()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lock_then_chest = then_chest
	_unlock_t = 0.0
	lock_view.open(st)

func close_lock() -> void:
	lock_view.close()
	lock_then_chest = false
	if not top_down and not _opts.has("auto"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func arena_lock_on(st: VoxelStorage) -> bool:
	return stash.lock_on(st)

## A chest's padlock changed (here or by the host): the padlock being dialled follows; a chest locked while open
## shuts.
func on_lock_changed(st: VoxelStorage) -> void:
	if lock_view.is_open() and lock_view.storage == st:
		lock_view.refresh()
	if inv_ui.is_open() and inv_ui.storage == st and st.locked:
		close_inventory()

## Off the arena, where the enemies never go (the bedroom, the yard).
static func safe(p: Vector3) -> bool:
	return VoxelBedroom.in_house(p) or VoxelYard.in_yard(p)

# the cubes' rooms off the arena (they stay in them): the bedroom, the yard
static func _rooms() -> Array:
	return [Rect2(VoxelBedroom.X0, VoxelBedroom.Z0, VoxelBedroom.X1 - VoxelBedroom.X0, VoxelBedroom.Z1 - VoxelBedroom.Z0),
		Rect2(VoxelYard.X0 + 0.1, VoxelYard.Z0, VoxelYard.X1 - VoxelYard.X0 - 0.1, VoxelYard.Z1 - VoxelYard.Z0)]

## The next shovel the tool bench makes (null: the golden one's made).
func next_upgrade():
	for u in VoxelYard.UPGRADES:
		if int(u.tier) == shovel_tier + 1:
			return u
	return null

## What the tool bench says: the next shovel, what it takes, what you've got.
func bench_line() -> String:
	var u = next_upgrade()
	if u == null:
		return "Tool bench: your shovel's as golden as it gets"
	var need := []
	var ok := true
	for id in u.cost:
		var have: int = inv.count(id)
		need.append("%d %s (%d)" % [int(u.cost[id]), VoxelItems.name_of(id).to_lower(), have])
		ok = ok and have >= int(u.cost[id])
	return ("E  make a %s: " % u.name if ok else "Tool bench: a %s needs " % u.name) + ", ".join(need)

## E at the tool bench: the next shovel made if you've got what it takes (out of the backpack).
func bench_make() -> bool:
	var u = next_upgrade()
	if u == null:
		return false
	for id in u.cost:
		if inv.count(id) < int(u.cost[id]):
			say("Not enough: " + bench_line().trim_prefix("Tool bench: "), 2.5)
			return false
	for id in u.cost:
		inv.remove(id, int(u.cost[id]))
	set_shovel_tier(int(u.tier))
	sound.play("gold_find" if int(u.tier) == 2 else "hammer_hit", Vector3.INF, -6.0)
	say("Made: a %s (%s)" % [u.name, u.desc], 3.0)
	return true

func set_shovel_tier(t: int) -> void:
	shovel_tier = clampi(t, 0, 2)
	if melee.has("shovel"):
		melee["shovel"].set_tier(shovel_tier)
	stash._dirty = true

## Lying down on bed i: on the mattress, the eye on the pillow looking along the bed; health back three times as fast.
func lie_down(i: int) -> void:
	_let_go()
	lying = i
	look_yaw = PI
	look_pitch = 0.25
	player.global_position = house.lie_spot(i)
	player.reset_physics_interpolation()
	sound.play("chest_close", house.lie_spot(i), -10.0, 0.5)

func get_up() -> void:
	var i := lying
	lying = 0
	player.global_position = house.up_spot(i)
	player.reset_physics_interpolation()
	look_pitch = 0.0
	look_yaw = PI * 0.5

# ---------------------------------------------------------------- the backpack and the chests

## The inventory screen: the backpack, with a chest or cabinet above it (null: the backpack alone).
func open_inventory(st: VoxelStorage) -> void:
	_let_go()
	if not top_down:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	inv_ui.open(st)
	if st:
		st.open_here = true
		stash.open_changed(st)
	else:
		sound.play("bag_open", Vector3.INF, -6.0)

func close_inventory() -> void:
	var st := inv_ui.storage
	inv_ui.close()
	if st:
		st.open_here = false
		stash.open_changed(st)
	if not top_down and not _opts.has("auto"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# which chest the player is at (E opens it), and the screen shut if they walk off from the open one
func _storage_step(dt: float) -> void:
	_say_t = maxf(0.0, _say_t - dt)
	_say_label.text = _say_text if _say_t > 0.0 else ""
	if lock_view.is_open():
		_use_label.text = ""
		var lst := lock_view.storage
		if lst and lst.front().distance_to(player.global_position) > 2.6:
			close_lock()
		elif lst and lock_then_chest and not lst.locked:
			_unlock_t += dt
			if _unlock_t > 0.7:
				close_lock()
				open_inventory(lst)       # (dialled open: into the chest)
		return
	if lying > 0:
		_use_label.text = "E, WASD or Space: get up"
		return
	if inv_ui.is_open():
		_use_label.text = ""
		var st := inv_ui.storage
		if st and st.front().distance_to(player.global_position) > 2.6:
			close_inventory()
		return
	if top_down:
		var pp := player.global_position + Vector3(0, 1.0, 0)
		var at := _mouse_floor()
		var dir := (Vector3(at.x, pp.y, at.z) - pp).normalized() if at != Vector3.INF else -cam.global_transform.basis.z
		_near_st = stash.pick(pp, dir, 1.4)
	_near_bed = 0
	_near_ward = false
	_near_bench = false
	if not top_down:
		# whatever the look lands on first: a chest, a bed, the wardrobe
		var eye := cam.global_position
		var fwd := -cam.global_transform.basis.z
		var sh: Array = stash.pick_ray(eye, fwd)
		var bh: Array = house.bed_hit(eye, fwd)
		_near_st = sh[0] if float(sh[1]) <= float(bh[1]) else null
		_near_bed = int(bh[0]) if _near_st == null else 0
		_near_ward = _near_st == null and _near_bed == 0 and house.wardrobe_at(eye, fwd)
		_near_bench = _near_st == null and _near_bed == 0 and not _near_ward and yard.bench_at(eye, fwd)
	var t := ""
	if _near_st:
		if _near_st.locked:
			t = "E  unlock %s (padlock)" % _near_st.title
		else:
			t = "E  open %s" % _near_st.title + ("     L  padlock" if _near_st.has_lock else ("     L  hang a padlock" if inv.count("padlock") > 0 else ""))
	elif _near_bed > 0:
		t = "E  lie down" + ("  (your bed)" if _near_bed == stash.my_pid() else "")
	elif _near_ward:
		t = "E  %s the wardrobe" % ("close" if house.ward_open else "open")
	elif _near_bench:
		t = bench_line()
	_use_label.text = t if down_t <= 0.0 else ""
	if down_t > 0.0:
		_near_st = null
		_near_bed = 0

var _say_text := ""
## A line in the middle of the screen for a moment.
func say(text: String, secs := 2.0) -> void:
	_say_text = text
	_say_t = secs

## Nothing more of what the vacuum takes would fit.
func backpack_full() -> bool:
	for id in ["meat", "bone", "brain", "blocks", "charred"]:
		if inv.room_for(id) > 0:
			return false
	return true

# a cube the vacuum took, into the backpack
func _on_take(id: String, n: int) -> void:
	var left := inv.add(id, n)
	if left > 0:
		lost += left
		say("Backpack full: empty it into a chest (E at one)", 1.5)

## A stack given to this player (co-op: by the host, for a chest move or the corpses their vacuum took): into the
## hand (where "cursor") or the backpack; what doesn't fit back in the open chest, or on the floor.
func receive(stack: Dictionary, where: String) -> void:
	var left := stack
	if where == "cursor":
		left = inv_ui.receive_to_cursor(stack)
	if left.is_empty():
		return
	var n := inv.add(left.id, int(left.n))
	if n > 0:
		if inv_ui.storage:
			stash.add(inv_ui.storage, {"id": left.id, "n": n})
		else:
			drop_stack({"id": left.id, "n": n})

## A stack thrown on the floor in front of the player, as its cubes (the vacuum takes them back).
func drop_stack(stack: Dictionary) -> void:
	if stack.is_empty() or int(stack.n) <= 0:
		return
	var at: Vector3
	var dir: Vector3
	if top_down:
		var pp := player.global_position + Vector3(0, 1.0, 0)
		var m := _mouse_floor()
		dir = (Vector3(m.x, pp.y, m.z) - pp).normalized() if m != Vector3.INF else Vector3.FORWARD
		at = pp + dir * 0.5
	else:
		dir = -cam.global_transform.basis.z
		dir = Vector3(dir.x, 0.0, dir.z).normalized()
		at = cam.global_position + dir * 0.6 + Vector3.DOWN * 0.4
	var seed := randi() | 1
	drop_cubes(at, dir, String(stack.id), int(stack.n), seed)
	stash.dropped(at, dir, String(stack.id), int(stack.n), seed)
	sound.play("cubes_fall", at, -4.0)

func drop_cubes(at: Vector3, dir: Vector3, id: String, n: int, seed: int = 0) -> void:
	debris.throw(at, dir, VoxelItems.colour(id), n, seed)

func _backpack_line() -> String:
	var parts := []
	for id in VoxelItems.ITEMS:
		var c := inv.count(id)
		if c > 0:
			parts.append("%d %s" % [c, VoxelItems.name_of(id).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "empty"

# F3 / F5: n more enemies (a co-op guest asks the host)
func _more(n: int) -> void:
	if net.role == "guest" and net.linked:
		net.request_more(n)
	else:
		spawn(n)

# F8: a line to type the room code (or an address) into; Enter joins, Esc doesn't
var _prompt: LineEdit
func _join_prompt() -> void:
	if _prompt:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_prompt = LineEdit.new()
	_prompt.placeholder_text = "room code (or an address for a direct game) — Enter"
	_prompt.custom_minimum_size = Vector2(420, 40)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-210, -20)
	_hud_layer.add_child(_prompt)
	_prompt.grab_focus()
	_prompt.text_submitted.connect(func(t: String):
		var c := t.strip_edges()
		if c != "":
			net.join(c.to_upper() if not (c.contains(".") or c.contains(":")) else c, "enet" if (c.contains(".") or c.contains(":")) else "rtc")
		_prompt.queue_free()
		_prompt = null
		if not top_down:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)

# the co-op line at the top: the room code, how it's going
var _net_label: Label
func _net_hud() -> void:
	if _net_label == null:
		_net_label = Label.new()
		_net_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_net_label.position = Vector2(-300, 8)
		_net_label.custom_minimum_size = Vector2(600, 0)
		_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_net_label.add_theme_font_size_override("font_size", 18)
		_net_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_net_label.add_theme_constant_override("outline_size", 6)
		_hud_layer.add_child(_net_label)
	if net.role == "":
		_net_label.text = ""
		return
	var head := ("CO-OP  room %s" % net.code) if net.role == "host" else "CO-OP  joined %s" % net.code
	_net_label.text = "%s — %s   (F9 leave)" % [head, net.status_text]

## n more enemies round the arena's edge.
func spawn(n: int) -> void:
	for i in n:
		var key: String = KEYS[randi() % KEYS.size()]
		var b := VoxelBody.new()
		add_child(b)
		b.setup(key, _cube_m(key), chunk, _mat)
		var a := randf() * TAU
		b.position = Vector3(cos(a), 0.0, sin(a)) * (ARENA - 2.0) * randf_range(0.7, 1.0)
		b.speed = randf_range(1.1, 1.9) * (1.4 if key == "swarmer" else (0.75 if key == "brute" else 1.0))
		b.died.connect(_on_died)
		bodies.append(b)

# every kind made once while loading (their flesh and meshes cached), so the first of each doesn't stall the game
func _warm_up() -> void:
	for key in HEIGHT:
		var b := VoxelBody.new()
		add_child(b)
		b.setup(key, _cube_m(key), chunk, _mat)
		b.queue_free()

func _on_died(_b: VoxelBody) -> void:
	kills += 1

func _respawn_all() -> void:
	var n := 0
	for b in bodies:
		if b.alive:
			n += 1
		b.queue_free()
	bodies.clear()
	for j in _jobs:
		WorkerThreadPool.wait_for_task_completion(j.id)     # (a task never waited on crashes the game at quit)
	_jobs.clear()
	var got := debris.got
	debris.queue_free()
	debris = VoxelDebris.new()
	add_child(debris)
	debris.setup(_cube_m("grunt"))
	debris.bound = ARENA - 0.5 - _cube_m("grunt")
	debris.rooms = _rooms()
	debris.got = got
	debris.on_take = _on_take
	spawn(maxi(n, 1))

# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] \
			and (top_down or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		_clicked[e.button_index] = true                  # (a click quicker than a frame still counts)
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := 0.0025 * cam.fov / 80.0           # slower when aimed in
		look_yaw -= e.relative.x * sens
		look_pitch = clampf(look_pitch - e.relative.y * sens, -1.4, 1.4)
		_mouse_v += e.relative
	elif e is InputEventMouseMotion:
		_mouse_v += e.relative
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if not top_down and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return                                       # the mouse let go (Esc): the wheel does nothing either
		var up: bool = e.button_index == MOUSE_BUTTON_WHEEL_UP
		if loadout.id() == "vacuum" and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			vacuum.wheel(up)                          # vacuum: right click held + wheel sizes the brush
		else:
			_switch(func(): loadout.cycle(-1 if up else 1))
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2] and (top_down or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		_sword_key(false)
	elif e is InputEventMouseButton and e.pressed and not top_down and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# first person grabs the mouse on a click (that click does nothing else); top-down keeps it free (aiming
		# follows the pointer)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_ignore[e.button_index] = true
	elif e is InputEventKey and e.pressed and not e.echo:
		if inv_ui.is_open():
			# the inventory screen open: these close it, the rest do nothing
			if e.physical_keycode in [KEY_TAB, KEY_I, KEY_E, KEY_ESCAPE]:
				close_inventory()
			return
		if lock_view.is_open():
			if e.physical_keycode in [KEY_E, KEY_L, KEY_ESCAPE]:
				close_lock()
			elif e.physical_keycode == KEY_R:
				lock_view.take_off()
			return
		if lying > 0:
			if e.physical_keycode in [KEY_E, KEY_SPACE, KEY_W, KEY_A, KEY_S, KEY_D, KEY_ESCAPE]:
				get_up()
				if e.physical_keycode == KEY_ESCAPE:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return
		match e.physical_keycode:
			KEY_TAB, KEY_I:
				open_inventory(null)
			KEY_L:
				if _near_st and _near_st.has_lock:
					open_lock(_near_st, false)
				elif _near_st:
					if arena_lock_on(_near_st):
						say("Padlock hung on the %s: L to set its code" % _near_st.title.to_lower(), 2.5)
					else:
						say("No padlock in your backpack (take one off a bed chest: L there, then R)", 2.5)
			KEY_F:
				_sword_key(false)
			KEY_C:
				_sword_key(true)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var g: int = e.physical_keycode - KEY_1 + 1
				_switch(func(): loadout.select_group(g))
			KEY_R:
				if melee.has(loadout.id()):
					melee[loadout.id()].reload_key()
					net.local_input("reload")
			KEY_Q:
				_switch(func(): loadout.swap_last())
			KEY_E:
				if _near_st and _near_st.locked:
					open_lock(_near_st, true)        # (locked: dial it open first, then the chest opens)
				elif _near_st:
					open_inventory(_near_st)
				elif _near_bed > 0:
					lie_down(_near_bed)
				elif _near_ward:
					house.ward_open = not house.ward_open
				elif _near_bench:
					bench_make()
				else:
					var vi := loadout.index_of("vacuum")
					_switch(func(): loadout.swap_last() if loadout.current == vi else loadout.select(vi))
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				if _prompt:
					_prompt.queue_free()
					_prompt = null
			KEY_V:
				top_down = not top_down
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if top_down else Input.MOUSE_MODE_CAPTURED
			KEY_F1:
				sun.shadow_enabled = not sun.shadow_enabled
			KEY_F2:
				if not net.linked:            # (the cube size is the host's world: not mid co-op)
					chunk = 2 if chunk == 1 else 1
					_warm_up()
					_respawn_all()
			KEY_F3:
				_more(10)
			KEY_F4:
				if net.role != "guest":
					frozen = not frozen
			KEY_F5:
				_more(40)
			KEY_F6:
				if net.role != "guest":
					VoxelBody.immortal = not VoxelBody.immortal
			KEY_F7:
				# co-op: host a room (a code to give your mate; Shift: on a port, for a LAN or a forwarded port)
				if net.role == "":
					var c := ""
					for i in 4:
						c += "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[randi() % 32]
					net.host(c, "enet" if e.shift_pressed else "rtc")
			KEY_F8:
				if net.role == "":
					_join_prompt()
			KEY_F9:
				net.leave()

# ---------------------------------------------------------------- each frame

# --swordtest=dir: a grunt standing in front, frozen, slashed through an arm, at the neck, then at the knees,
# a frame saved round each cut (sword_<cut>_<k>.png), what each cut did printed, then quit
const SWORD_CUTS := [[1.15, Vector2(0.3, 1.0), -0.5], [1.45, Vector2(-1, 0), 0.0], [0.25, Vector2(1, 0), 0.0]]   # [height, slash, across]
var _st_i := 0
var _st_t := 0.0
func _swordtest_setup() -> void:
	var b := VoxelBody.new()
	add_child(b)
	b.setup("grunt", _cube_m("grunt"), chunk, _mat)
	b.position = Vector3(0, 0, 4.5)
	b.yaw = 0.0
	b.died.connect(_on_died)
	bodies.append(b)
	frozen = true
	VoxelBody.immortal = _opts.has("immortal")
	player.position = Vector3(0.25, 0, 6.0)
	look_yaw = 0.0

func _swordtest(dt: float) -> void:
	_st_t += dt
	if _st_i >= SWORD_CUTS.size():
		# then the vacuum, looking down at the mess, for two seconds
		if loadout.id() != "vacuum":
			loadout.select(loadout.index_of("vacuum"))
			loadout.switch_t = 0.0
		look_pitch = -0.75
		_sucking = _st_t > 1.0
		for k in 3:
			var tag := "vf%d" % k
			if _st_t >= [0.95, 1.35, 2.2][k] and not _opts.has(tag):
				_opts[tag] = "1"
				_shot_png("%s/vacuum_%d.png" % [String(_opts.swordtest), k])
		if _st_t > 3.1:
			print("SWORD vacuum: got %s, lying %d, pieces %d" % [str(debris.got), debris.lying(), pieces.count()])
			_finish()
		return
	var c: Array = SWORD_CUTS[_st_i]
	var b: VoxelBody = bodies[0]
	var target := b.global_position + Vector3(float(c[2]), float(c[0]), 0)
	var to := target - cam.global_position
	look_yaw = atan2(-to.x, -to.z)
	look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	if _st_t > 1.0 and sword.ready_to_swing() and not _opts.has("sc%d" % _st_i):
		_opts["sc%d" % _st_i] = "1"
		sword.slash(c[1])
	for k in 6:
		var at: float = 1.0 + [0.02, 0.06, 0.15, 0.3, 0.6, 1.2][k]
		var tag := "sf%d_%d" % [_st_i, k]
		if _st_t >= at and not _opts.has(tag):
			_opts[tag] = "1"
			_shot_png("%s/sword_%d_%d.png" % [String(_opts.swordtest), _st_i, k])
	if _st_t > 2.4:
		print("SWORD cut %d at %.2f m: %s; legs lost %d, alive %s" % [_st_i, c[0], str(sword.last), b.legs_lost(), str(b.alive)])
		_st_i += 1
		_st_t = 0.8

# --meleetest=<weapon id> --shots=dir [--topdown] [--immortal] [--headaim]: a grunt standing in front, frozen; the weapon out;
# left click pressed at 1 s, held, let go at 1.8 s; a fresh grunt at 3 s; right click pressed at 3.4 s, held, let go
# at 4.4 s; frames saved round each (melee_<id>_<L|R>_<k>.png), what each did printed (MELEE ...), then quit at 6.6 s
const MT_SHOTS := [0.03, 0.12, 0.3, 0.6, 0.95, 1.6, 2.2]
var _mt_t := 0.0
var _mt_body: VoxelBody
func _meleetest_setup() -> void:
	VoxelBody.immortal = _opts.has("immortal")
	frozen = true
	player.position = Vector3(0.25, 0, 6.0)
	look_yaw = 0.0
	_mt_body = _mt_grunt()
	var i := loadout.index_of(String(_opts.meleetest))
	if i < 0:
		print("MELEE no such weapon: ", _opts.meleetest)
	else:
		_switch(func(): loadout.select(i))
		loadout.switch_t = 0.0

func _mt_grunt() -> VoxelBody:
	var b := VoxelBody.new()
	add_child(b)
	b.setup("grunt", _cube_m("grunt"), chunk, _mat)
	b.position = Vector3(0, 0, 4.6)
	b.yaw = 0.0
	b.died.connect(_on_died)
	bodies.append(b)
	return b

func _meleetest(dt: float) -> void:
	_mt_t += dt
	var id := String(_opts.meleetest)
	var w: VoxelMelee = melee.get(id)
	if w == null:
		if _mt_t > 0.5:
			print("MELEE no such weapon: ", id)
			_finish()
		return
	# look at the grunt's chest (top-down: the mouse on him)
	var b := _mt_body
	# (--headaim: the right click goes at the head)
	var target := b.global_position + Vector3(0, 1.7 if (_opts.has("headaim") and _mt_t > 3.2) else 1.1, 0)
	if top_down:
		get_viewport().warp_mouse(cam.unproject_position(target))
	else:
		var to := target - cam.global_position
		look_yaw = atan2(-to.x, -to.z)
		look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	for ph in [["L", MOUSE_BUTTON_LEFT, 1.0, 1.8], ["R", MOUSE_BUTTON_RIGHT, 3.4, 4.4]]:
		var t0: float = ph[2]
		var t1: float = ph[3]
		var tag: String = ph[0]
		if _mt_t >= t0 and not _opts.has("mp" + tag):
			_opts["mp" + tag] = "1"
			if _opts.has("swing"):        # --swing=left|right: the mouse moving that way as it's pressed
				_mouse_v = Vector2(-600.0 if String(_opts.swing) == "left" else 600.0, 0.0)
			w.press(ph[1])
		elif _mt_t > t0 and _mt_t < t1:
			w.hold(ph[1], dt)
		elif _mt_t >= t1 and not _opts.has("mr" + tag):
			_opts["mr" + tag] = "1"
			w.release(ph[1])
		for k in MT_SHOTS.size():
			var st := "ms%s%d" % [tag, k]
			if _mt_t >= t0 + float(MT_SHOTS[k]) and not _opts.has(st) and _opts.has("shots"):
				_opts[st] = "1"
				_shot_png("%s/melee_%s_%s_%d.png" % [String(_opts.shots), id, tag, k])
	if _mt_t >= 2.2 and _opts.has("again") and not _opts.has("mag"):
		_opts["mag"] = "1"            # --again: a second left click (the gravity gun's throw)
		w.press(MOUSE_BUTTON_LEFT)
		w.release(MOUSE_BUTTON_LEFT)
	if _mt_t >= 4.7 and _opts.has("rkey") and not _opts.has("mrk"):
		_opts["mrk"] = "1"            # --rkey: R (sticky bombs set off, a reload, the laser's vent)
		w.reload_key()
	if _mt_t >= 3.2 and not _opts.has("mpr1"):
		_opts["mpr1"] = "1"
		print("MELEE %s left: %s | grunt alive %s, legs lost %d, floored %s, at %s, hp %.0f, pieces %d, cubes %d" % [id, str(w.last), str(b.alive), b.legs_lost(), str(b.floored()), str(b.position.snapped(Vector3.ONE * 0.01)), b.hp, pieces.count(), knocked])
		_mt_body = _mt_grunt()
	if _mt_t >= 6.5 and not _opts.has("mpr2"):
		_opts["mpr2"] = "1"
		var b2 := _mt_body
		print("MELEE %s right: %s | grunt alive %s, legs lost %d, floored %s, at %s, hp %.0f, pieces %d, cubes %d" % [id, str(w.last), str(b2.alive), b2.legs_lost(), str(b2.floored()), str(b2.position.snapped(Vector3.ONE * 0.01)), b2.hp, pieces.count(), knocked])
	if _mt_t >= 6.6:
		_finish()

# --weaponshots=dir: every slot taken out in turn, first person then top-down, a frame of each (weapons_<fp|td>_<n>.png)
func _weaponshots() -> void:
	var n := loadout.slots.size()
	var k := int(floor((_t - 1.0) / 0.7))
	if k < 0:
		return
	if k >= 2 * n:
		_finish()
		return
	if k == n and not top_down:
		top_down = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.62, 0.35))
	var i := k % n
	if loadout.current != i:
		_switch(func(): loadout.select(i))
	var tag := "ws%d" % k
	if _t >= 1.0 + k * 0.7 + 0.55 and not _opts.has(tag):
		_opts[tag] = "1"
		_shot_png("%s/weapons_%s_%d.png" % [String(_opts.weaponshots), "td" if top_down else "fp", i + 1])

func _shot_png(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

# --walkcheck=dir: the four kinds side by side, walking on the spot side-on to the camera, a frame saved every
# tenth of a second (walk_0.png ...), then quit
func _walkcheck_setup() -> void:
	var i := 0
	for key in ["grunt", "swarmer", "brute", "batter"]:
		var b := VoxelBody.new()
		add_child(b)
		b.setup(key, _cube_m(key), chunk, _mat)
		b.position = Vector3(-2.4 + i * 1.6, 0, 0)
		b.yaw = PI / 2.0
		b.speed = 2.6 if key != "brute" else 1.9
		if _opts.has("legless"):     # --legless: both legs off, to see the worm crawl
			b._blow("thigh_l")
			b._blow("thigh_r")
			b.speed *= b.move_factor()
		bodies.append(b)
		i += 1
	frozen = true
	player.position = Vector3(0, 0, 5.0)
	look_yaw = 0.0
	look_pitch = -0.12

func _walkcheck(dt: float) -> void:
	for b in bodies:
		b.odo += b.speed * dt
		b.animate(dt, true)
	var k := int(floor((_t - 1.0) / 0.1))
	if k >= 0 and k < 10 and not _opts.has("wk%d" % k):
		_opts["wk%d" % k] = "1"
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/walk_%d.png" % [String(_opts.walkcheck), k])
	if k >= 10:
		get_tree().quit()

func _physics_process(dt: float) -> void:
	if _opts.has("walkcheck"):
		return
	# the player: WASD by where you look (top-down: by the screen)
	var iv := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var sp := 7.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 4.5
	var dir := Vector3.ZERO
	if top_down:
		dir = Vector3(iv.x, 0, iv.y)
	else:
		var f := Vector3(-sin(look_yaw), 0, -cos(look_yaw))
		var r := Vector3(cos(look_yaw), 0, -sin(look_yaw))
		dir = r * iv.x - f * iv.y
	if dir.length() > 1.0:
		dir = dir.normalized()
	if down_t > 0.0:
		dir = Vector3.ZERO          # (down: no moving)
	if lying > 0:
		player.velocity = Vector3.ZERO
		player.global_position = house.lie_spot(lying)
		dir = Vector3.ZERO
	player.velocity.x = dir.x * sp
	player.velocity.z = dir.z * sp
	if _dash_t > 0.0:
		_dash_t -= dt
		player.velocity.x = _dash_v.x
		player.velocity.z = _dash_v.z
	if player.is_on_floor():
		if Input.is_physical_key_pressed(KEY_SPACE):
			player.velocity.y = 5.0
	else:
		player.velocity.y -= 14.0 * dt
	if lying <= 0:
		player.move_and_slide()
	# the enemies come at you (the nearest of you two in co-op; a guest's are moved by the host's snapshots)
	if net.role == "guest" and net.linked:
		return
	var targets: Array = net.targets()
	var everyone_down := targets.is_empty()
	if everyone_down:
		targets = [player.global_position]
	var to_fly: Array[VoxelBody] = []
	for i in bodies.size():
		var b := bodies[i]
		if not b.alive:
			if b.fragment and b.airborne:
				to_fly.append(b)          # a lying piece knocked flying: a piece again
				continue
			if b.fragment and b.cubes_left() == 0:
				to_fly.append(b)
				continue
			if b.airborne or b.knock.length_squared() > 0.0001:
				b.react_step(dt)          # knocked flying dead: still flies, lands, slides
				b.position.x = clampf(b.position.x, -ARENA + 1.0, ARENA - 1.0)
				b.position.z = clampf(b.position.z, -ARENA + 1.0, ARENA - 1.0)
			continue
		var pp: Vector3 = targets[0]
		var ti := 0
		for j2 in targets.size():
			var tp: Vector3 = targets[j2]
			if tp.distance_squared_to(b.position) < pp.distance_squared_to(b.position):
				pp = tp
				ti = j2
		var to := Vector3(pp.x - b.position.x, 0, pp.z - b.position.z)
		var d := to.length()
		var mv := Vector3.ZERO
		var stop := 4.5 if _opts.has("auto") else 1.2
		b.react_step(dt)
		var ice := b.frozen()                       # frozen solid: a statue till it thaws or shatters
		var panic := b.panic_t > 0.0 and not ice    # on fire: running about, flailing, not fighting
		var can := not frozen and not ice and b.stagger <= 0.0 and not b.floored()
		if can and panic:
			mv = b.panic_dir * b.speed * 1.4 * b.move_factor()
		elif can and d > stop:
			mv = to / d * b.speed * b.move_factor()
		# keep apart
		for j in range(maxi(0, i - 6), mini(bodies.size(), i + 7)):
			if ice or j == i or not bodies[j].alive:
				continue
			var away := b.position - bodies[j].position
			away.y = 0
			var dl := away.length()
			if dl < 0.8 and dl > 0.001:
				mv += away / dl * (0.8 - dl) * 6.0
		b.position += mv * dt
		b.position.x = clampf(b.position.x, -ARENA + 1.0, ARENA - 1.0)
		b.position.z = clampf(b.position.z, -ARENA + 1.0, ARENA - 1.0)
		var out := out_of_pillars(b.position, 0.35)
		if out != b.position and mv.length_squared() > 0.01:
			# against a pillar: slide along its face, round toward the player
			var push := out - b.position
			var side := Vector3(-push.z, 0.0, push.x).normalized()
			var c: Vector3 = PILLARS[0]
			for pc: Vector3 in PILLARS + blocks.map(func(bk): return bk[0]):
				if Vector2(pc.x - out.x, pc.z - out.z).length() < Vector2(c.x - out.x, c.z - out.z).length():
					c = pc
			var toward := side.dot(to.normalized())
			# round toward the player; straight behind it, the way it's already off the pillar's middle
			if toward < -0.3 or (absf(toward) <= 0.3 and side.dot(out - c) < 0.0):
				side = -side
			out += side * b.speed * b.move_factor() * dt
		b.position = out
		if panic and can:
			b.yaw = lerp_angle(b.yaw, atan2(b.panic_dir.x, b.panic_dir.z), 1.0 - exp(-dt * 6.0))
		elif d > 0.01 and can:
			b.yaw = lerp_angle(b.yaw, atan2(to.x, to.z), 1.0 - exp(-dt * 8.0))
		b.odo += mv.length() * dt
		var a0 := b.attack
		b.attack = fmod(b.attack + dt * 1.6, 1.0) if (d <= stop + 0.2 and can and not panic and not everyone_down) else 0.0
		# the swing landing on whoever it's at (in reach still); one on fire brushing past burns
		if a0 < 0.55 and b.attack >= 0.55 and d <= stop + 0.5 and not _opts.has("auto"):
			_hurt_target(ti, float(SWING_HURT.get(b.key, 8.0)))
		if b.burning() and d < 0.9 and not everyone_down:
			_hurt_target(ti, BURN_TOUCH * dt)
	_bowl()
	for b in to_fly:
		if b.cubes_left() == 0:
			bodies.erase(b)
			b.queue_free()
		else:
			pieces.from_fragment(b)

# a body flying fast (batted, blasted, thrown) knocks over whoever it hits
func _bowl() -> void:
	for b in bodies:
		if not b.airborne or b.fragment or b.position.y > 1.6 or b.air_v.length_squared() < 9.0 or b.cubes_left() == 0:
			continue
		for o in bodies:
			if o == b or o.airborne or o.fragment or not o.alive:
				continue
			var dd := o.position - b.position
			dd.y = 0.0
			if dd.length_squared() < 0.64:
				var v := b.air_v
				o.launch(Vector3(v.x, 0.0, v.z) * 0.6 + Vector3.UP * 2.5, 5.0)
				o.hurt(6.0)
				b.air_v = Vector3(v.x * 0.6, v.y, v.z * 0.6)
				sound.play("thwack", o.position + Vector3.UP, -4.0)

# fire and ice: the fire spreading and eating (flames, ash falling, burnt-off bits dropping), the thaw
func _status_step(dt: float) -> void:
	var any_burning := false
	var ash_ok := true                # one body's ash taken out a frame
	for b: VoxelBody in bodies.duplicate():
		if not is_instance_valid(b) or not b.has_status():
			continue
		var st: Dictionary = b.status_step(dt, ash_ok)
		if not (st.removed as Dictionary).is_empty():
			ash_ok = false
		if b.burning():
			any_burning = true
		for p in st.flames:
			flames.emit(p, 2, Vector3.ZERO, 2.6, 0.55)
		var r: Dictionary = st.removed
		if not r.is_empty():
			knocked += (r.bits as Array).size()
			debris.burst(r.bits, Vector3.UP, 0.6)
			if not (r.pieces as Array).is_empty():
				pieces.spawn(b, r.pieces, Vector3.UP * 0.4, Vector3.ZERO)
	if any_burning:
		sound.loop("burning", "burn_loop", null, -8.0)
	elif sound.playing("burning"):
		sound.stop("burning")

## p pushed out of any pillar it's within r metres of (level; above the pillars' tops nothing): walking, flying, dragged,
## held, pulled bodies don't go through them.
static func out_of_pillars(p: Vector3, r: float) -> Vector3:
	if p.y > 3.5:
		return p
	for c: Vector3 in PILLARS:
		p = _out_of_box(p, c, PILLAR_HALF + r, PILLAR_HALF + r)
	if p.y < 1.9:
		for bk in blocks:
			p = _out_of_box(p, bk[0], float(bk[1]) + r, float(bk[2]) + r)
	return p

# p out of a level box round c (half sizes hx, hz) by its nearest face
static func _out_of_box(p: Vector3, c: Vector3, hx: float, hz: float) -> Vector3:
	var dx := p.x - c.x
	var dz := p.z - c.z
	if absf(dx) < hx and absf(dz) < hz:
		if hx - absf(dx) < hz - absf(dz):
			p.x = c.x + hx * (1.0 if dx >= 0.0 else -1.0)
		else:
			p.z = c.z + hz * (1.0 if dz >= 0.0 else -1.0)
	return p

func _process(dt: float) -> void:
	_t += dt
	_frames.append(dt)
	if _opts.has("stats"):
		_stat_t += dt
		if _stat_t >= 1.0:
			_stat_t = 0.0
			_hud_text()
			print("ARENA ", hud.text.replace("\n", " | "))
			var ps := ""
			for k in _prof:
				ps += "%s %.1f  " % [k, _prof[k] / 1000.0 / maxf(1.0, Engine.get_frames_per_second())]
			print("ARENA ms a frame: ", ps, " debris ", "%.1f" % (debris.prof_us / 1000.0 / maxf(1.0, Engine.get_frames_per_second())))
			debris.prof_us = 0
			_prof.clear()
	if _opts.has("burst"):
		var k := int(floor((_t - float(_opts.get("burst_at", "3")) ) / 0.1))
		if k >= 0 and k < 12 and not _opts.has("bk%d" % k):
			_opts["bk%d" % k] = "1"
			_burst_save(k)
	if _opts.has("secs") and _t >= float(_opts.secs):
		_finish()
		return
	if _opts.has("walkcheck"):
		_camera(dt)
		_walkcheck(dt)
		return
	if _opts.has("swordtest"):
		_swordtest(dt)
	if _opts.has("weaponshots"):
		_weaponshots()
	var t0 := Time.get_ticks_usec()
	_camera(dt)
	var t1 := Time.get_ticks_usec()
	_shoot(dt)
	if _opts.has("meleetest"):
		_meleetest(dt)           # (after _shoot, which clears _aiming each frame)
	var guest: bool = net.role == "guest" and net.linked     # (a guest's world is the host's: no fire, culling, waves)
	if not guest:
		_status_step(dt)
	var t2 := Time.get_ticks_usec()
	for b in bodies:
		var moving := b.alive and not frozen
		if not b.alive:
			if not b.frozen():
				b.dead_t += dt        # (frozen mid-fall, a statue: it falls the rest of the way once it thaws)
			if b.dead_t > 0.7 and not b.airborne and b.since_air > 0.5 and b.knock.length_squared() <= 0.0001:
				continue          # lying still
		b.animate(dt, moving and b.attack <= 0.0)
	# the dead stay, to be cut up as long as you like; past MAX_DEAD the oldest go
	var dead := 0
	for b in bodies:
		if not b.alive:
			dead += 1
	var i0 := 0
	while dead > MAX_DEAD and i0 < bodies.size() and not guest:
		var b := bodies[i0]
		if not b.alive:
			b.queue_free()
			bodies.remove_at(i0)
			dead -= 1
		else:
			i0 += 1
	var t3 := Time.get_ticks_usec()
	if not guest and not bodies.any(func(x): return x.alive):
		_next_t += dt
		if _next_t >= 1.5:
			_next_t = 0.0
			_next_wave()
	var t4 := Time.get_ticks_usec()
	_mesh_jobs()
	var t5 := Time.get_ticks_usec()
	_prof["camera"] = _prof.get("camera", 0) + t1 - t0
	_prof["shoot"] = _prof.get("shoot", 0) + t2 - t1
	_prof["animate"] = _prof.get("animate", 0) + t3 - t2
	_prof["spawn"] = _prof.get("spawn", 0) + t4 - t3
	_prof["jobs"] = _prof.get("jobs", 0) + t5 - t4
	_code_ms = lerpf(_code_ms, (t5 - t0) / 1000.0, 0.1)
	_draw_tracers(dt)
	_mouse_v *= exp(-dt * 14.0)
	_weapons_step(dt)
	_health_step(dt)
	_storage_step(dt)
	for b in bodies:
		if not guest and not b.fragment and (b.airborne or b.stagger > 0.0 or not b.alive):
			b.position = out_of_pillars(b.position, 0.3)     # (flying, dragged, held, pulled after the weapons moved them)
	_flash_t = maxf(0.0, _flash_t - dt)
	_flash.light_energy = 4.0 * _flash_t / 0.05 if _flash_t > 0.0 else 0.0
	_hud_t += dt
	if _hud_t >= 0.25:
		_hud_t = 0.0
		_hud_text()

func _camera(dt: float) -> void:
	var pp := player.get_global_transform_interpolated().origin
	_kick = maxf(0.0, _kick - dt * 6.0)
	avatar.visible = top_down
	if top_down:
		avatar.global_position = pp
		var aim := _mouse_floor()
		if aim != Vector3.INF:
			var to := aim - pp
			avatar.yaw = atan2(to.x, to.z)
		avatar.speed = Vector2(player.velocity.x, player.velocity.z).length()
		avatar.odo += avatar.speed * dt
		avatar.attack = maxf(0.0, avatar.attack - dt * 2.5)    # a sword swing's arms, back down
		avatar.animate(dt, avatar.speed > 0.2)
		var shake := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.06 * _kick    # a blow shakes it here too
		cam.global_position = pp + Vector3(0, 13.0, 6.0) + shake
		cam.look_at(pp + Vector3(0, 0.8, 0) + shake, Vector3.UP)
		cross.visible = false
	elif lying > 0:
		cam.global_position = house.lie_eye(lying)
		cam.rotation = Vector3(look_pitch, look_yaw, 0.0)
		cross.visible = false
	else:
		var low := minf(1.0, (down_t if down_t > 0.0 else 0.0) * 4.0)     # down: on the floor, the view tipped over
		cam.global_position = pp + Vector3(0, lerpf(1.65, 0.35, low), 0)
		cam.rotation = Vector3(look_pitch + _kick * 0.04, look_yaw, lerpf(0.0, 1.1, low))
		cross.visible = true
	_self_in_mirror(dt, pp)

# first person in the bedroom: your own Jared stands (or lies) where you are, on the layer only the mirror's camera sees
func _self_in_mirror(dt: float, pp: Vector3) -> void:
	if top_down:
		_set_layers(avatar, 1 | (1 << (VoxelMirror.LAYER_SELF - 1)))
		return
	var show := VoxelBedroom.in_house(pp)
	avatar.visible = show
	if not show:
		return
	_self_t -= dt
	if _self_t <= 0.0:
		_self_t = 0.5
		_set_layers(avatar, 1 << (VoxelMirror.LAYER_SELF - 1))
	avatar.global_position = house.lie_spot(lying) if lying > 0 else pp
	avatar.yaw = 0.0 if lying > 0 else atan2(-sin(look_yaw), -cos(look_yaw))
	avatar.down_t = 1.0 if lying > 0 else 0.0
	avatar.speed = 0.0 if lying > 0 else Vector2(player.velocity.x, player.velocity.z).length()
	avatar.odo += avatar.speed * dt
	avatar.animate(dt, avatar.speed > 0.2)

static func _set_layers(n: Node, mask: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = mask
	for c in n.get_children():
		_set_layers(c, mask)

func _mouse_floor() -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t := (1.2 - o.y) / d.y
	return o + d * t if t > 0 else Vector3.INF

# where the gun points from: the eye (first person) or Jared's chest toward the mouse (top-down)
func _aim() -> Array:
	if top_down:
		var pp := player.global_position + Vector3(0, 1.2, 0)
		var at := _mouse_floor()
		if at == Vector3.INF:
			return []
		return [pp, (at - pp).normalized()]
	return [cam.global_position, -cam.global_transform.basis.z]

func _shoot(dt: float) -> void:
	loadout.step(dt)
	me.weapon = loadout.id()
	if down_t > 0.0:
		_sucking = false
		_aiming = false
		_let_go()                   # (down: no weapons; buttons held are let go)
		return
	if not _opts.has("swordtest"):
		_sucking = hold_suck
	_aiming = false
	if inv_ui.is_open() or lock_view.is_open() or lying > 0:
		_let_go()                   # (the inventory screen, the padlock: the mouse is for that; lying in bed: no)
		_clicked.clear()
		return
	_fire_cd = maxf(0.0, _fire_cd - dt)
	_sg_cd = maxf(0.0, _sg_cd - dt)
	if _opts.has("auto"):
		_auto()
		return
	for btn in _ignore.keys():
		if not Input.is_mouse_button_pressed(btn):
			_ignore.erase(btn)
	var free := Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not top_down    # first person, the mouse let go
	var id := loadout.id()
	var tapped_l := _clicked.has(MOUSE_BUTTON_LEFT)
	var tapped_r := _clicked.has(MOUSE_BUTTON_RIGHT)
	_clicked.clear()
	var lmb := (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or tapped_l) and not _ignore.has(MOUSE_BUTTON_LEFT)
	var rmb := (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or tapped_r) and not _ignore.has(MOUSE_BUTTON_RIGHT)
	if melee.has(id):
		# a melee weapon: told of each press, each frame held, each let-go (let-gos even with the mouse free, so
		# nothing stays held; no new press then)
		var w: VoxelMelee = melee[id]
		for btn in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			var down := lmb if btn == MOUSE_BUTTON_LEFT else rmb
			var still := Input.is_mouse_button_pressed(btn)    # a tap pressed and let go in one frame: press, then release
			var was: bool = _held.get(btn, false)
			if down and not was and loadout.usable() and not free:
				_held[btn] = true
				w.press(btn)
				net.local_input("press", btn)
				if not still:
					_held[btn] = false
					w.release(btn)
					net.local_input("release", btn)
			elif down and was:
				w.hold(btn, dt)
			elif not down and was:
				_held[btn] = false
				w.release(btn)
				net.local_input("release", btn)
		return
	if free:
		return
	var a := _aim()
	if a.is_empty():
		return
	if not loadout.usable():
		return
	if id == "vacuum" and not _opts.has("swordtest"):
		_sucking = lmb or hold_suck

# F (or a mouse side button): a sword slash the way the mouse was moving, whatever is out; C: a chop (top-down: a
# low sweep at the legs)
func _sword_key(low: bool) -> void:
	if sword == null or not sword.ready_to_swing() or (not top_down and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
		return
	sword.quick(low)
	net.local_input("quick", low)

# a weapon switch (change: what moves the loadout): the melee weapon put away lets go of its buttons, buttons still
# down count for nothing till they're let go
func _switch(change: Callable) -> void:
	var before := loadout.id()
	change.call()
	var now := loadout.id()
	if now == before:
		return
	net.local_input("switch", now)     # (before any press with it: the other game's copy switches first)
	if melee.has(before):
		for btn in _held:
			if _held[btn]:
				melee[before].release(btn)
		melee[before].on_deselect()
	_held.clear()
	_clicked.clear()
	for btn in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if Input.is_mouse_button_pressed(btn):
			_ignore[btn] = true
	if melee.has(now):
		melee[now].on_select()
	sound.play("switch", Vector3.INF, -6.0)

# a gun's mesh at scale metres a voxel (built here, not through VoxelModel.weapon_arrays, whose cache keeps one scale;
# kept, as reading and meshing a .vox takes ~20 ms)
static var _gun_meshes := {}
static func _gun_mesh(name: String, scale: float) -> ArrayMesh:
	var ck := "%s|%.5f" % [name, scale]
	if _gun_meshes.has(ck):
		return _gun_meshes[ck]
	var am := _gun_mesh_build(name, scale)
	_gun_meshes[ck] = am
	return am

static func _gun_mesh_build(name: String, scale: float) -> ArrayMesh:
	var meta: Dictionary = VoxelModel.weapon_meta()
	if not meta.has(name):
		return ArrayMesh.new()
	var v := VoxFile.load_file(VoxelModel.DIR + "weapons/" + String(meta[name].file))
	if v == null:
		return ArrayMesh.new()
	var o: Array = meta[name].origin
	return VoxelBody.array_mesh(VoxMesher.mesh(v.model_grid(), Vector3(o[0], o[1], o[2]), scale))

## The player thrown along at vel (m/s, level) for secs, whatever the keys say (a lunge).
func dash(vel: Vector3, secs: float) -> void:
	_dash_v = Vector3(vel.x, 0.0, vel.z)
	_dash_t = secs

## How much of a weapon's cooldown is left (the weapon bar), 1 to 0.
func slot_cooling(id: String) -> float:
	if melee.has(id):
		return melee[id].cooling()
	return loadout.cooling(id)

# every frame: the weapons' own steps, the view of the one out (going down / coming up on a switch, kicking when it
# fires, closing in when aimed), and what Jared holds top-down
func _weapons_step(dt: float) -> void:
	me.weapon = loadout.id()
	pieces.step(dt)
	for id in melee:
		melee[id].step(dt)
	var cur := loadout.id()
	avatar.recoil = maxf(0.0, avatar.recoil - dt * 6.0)
	_aim_k = move_toward(_aim_k, 1.0 if _aiming and not top_down else 0.0, dt * 6.0)
	cam.fov = lerpf(80.0, 50.0, _aim_k)
	# a switch: the first half the old one goes down, the second half the new one comes up
	var k := 1.0 - loadout.switch_frac()
	var shown := cur
	if k < 0.5 and loadout.last < loadout.slots.size():
		shown = String(loadout.slots[loadout.last].id)
	var drop := -0.35 * (k / 0.5 if k < 0.5 else (1.0 - k) / 0.5)
	var away := lying > 0 or lock_view.is_open()      # (in bed, dialling a padlock: the weapon put away)
	vacuum.step(dt, shown == "vacuum" and not away, _sucking and cur == "vacuum")
	for id in melee:
		var w: VoxelMelee = melee[id]
		w.view.visible = not top_down and not away and (id == shown or w.busy())
		w.view.position = Vector3(0, drop if id == shown else 0.0, 0)
	vacuum.view.visible = shown == "vacuum" and not top_down and not away
	vacuum.view.position = Vector3(0.24, -0.23 + (drop if shown == "vacuum" else 0.0), -0.5)
	if top_down and _hand_id != cur:
		_hold_in_hand(cur)

# top-down: the weapon out in Jared's right hand (its hand_mesh) and the arms to hold it with
func _hold_in_hand(id: String) -> void:
	_hand_id = id
	for h in _hands:
		h.queue_free()
	_hands.clear()
	var md: VoxelModel = avatar.model
	var m := md.voxel_m
	var g: Array = md.rig.get("grip_r", [-34.5, 56.0, 0.0])
	var down := Basis(Vector3.RIGHT, PI / 2.0)    # the weapon's +z (out of the fist) along the arm
	avatar.weapon = melee[id].hand_pose() if melee.has(id) else ("spud" if id == "vacuum" else "")
	for side in ["_r"]:
		var b := md.bone("hand" + side)
		if b < 0:
			continue
		var node: Node3D = null
		if id == "vacuum":
			node = Node3D.new()
			var vm := vacuum._model()
			vm.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 0.12))
			vm.visible = true
			node.add_child(vm)
		elif melee.has(id):
			node = melee[id].hand_mesh()
		if node == null:
			continue
		var att := BoneAttachment3D.new()
		att.bone_idx = b
		avatar.skeleton.add_child(att)
		var grip := Vector3(g[0] * (1.0 if side == "_r" else -1.0), g[1], -2.0)
		node.transform = Transform3D(down, (grip - md.bone_pivot[b]) * m)
		att.add_child(node)
		_hands.append(att)

## One trigger pull: pellets rays spread degrees apart, each knocking a hole r cubes round where it lands. opts:
## muzzle (world: where the flash and tracer start), falloff (metres at which the hole is half as big). Returns the
## hits: [{body, dist, part, point, res}].
func fire(from: Vector3, dir: Vector3, pellets: int, spread: float, r: float, opts: Dictionary = {}) -> Array:
	var muzzle: Vector3 = opts.get("muzzle", from + dir * 0.5 + Vector3(0, -0.12, 0))
	var falloff: float = opts.get("falloff", 0.0)
	_flash.global_position = muzzle
	_flash_t = 0.05
	_kick = maxf(_kick, 1.0)
	var hits := []
	for i in pellets:
		var d := dir
		if spread > 0.0:
			var b := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
			var ax := deg_to_rad(randf_range(-spread, spread))
			var ay := deg_to_rad(randf_range(-spread, spread))
			d = (b * Vector3(ax, ay, -1.0)).normalized()
		var best := {}
		var best_b: VoxelBody = null
		var reach := 60.0
		for b2 in bodies:
			var h := b2.trace(from, d, reach)
			if not h.is_empty() and float(h.dist) < reach:
				reach = h.dist
				best = h
				best_b = b2
		# the world (walls, pillars, floor) stops it first?
		var q := PhysicsRayQueryParameters3D.create(from, from + d * reach)
		q.exclude = [player.get_rid()]
		q.collision_mask = 1            # walls, pillars, floor: not the pieces flying about (layer 2)
		q.exclude = me.exclude()        # (and neither player)
		var wh := get_world_3d().direct_space_state.intersect_ray(q)
		var end := from + d * reach
		if not wh.is_empty():
			end = wh.position
			best_b = null
			# sparks off the wall or floor
			flames.emit(end, 3, (wh.normal as Vector3) * 2.0, 0.8, 0.18)
			sound.play("hit_world", end, -4.0)
		_tracer_list.append({"a": muzzle, "b": end, "t": 0.06})
		if best_b:
			var rr := r
			if falloff > 0.0:
				rr = maxf(0.9, r * pow(0.5, float(best.dist) / falloff))
			var res := best_b.damage(best, rr)
			if not res.get("shattered", false):
				best_b.hit_react(d, (res.bits as Array).size(), String(best.part))
			knocked += (res.bits as Array).size()
			var bits: Array = res.bits
			if bits.size() > 40:
				bits = bits.slice(0, 40) + (bits.slice(40) as Array).filter(func(_x): return randf() < 0.35)
			debris.burst(bits, d, 4.0 if String(res.get("limb", "")) == "" else 2.5)
			sound.play("shatter" if res.get("shattered", false) else "hit_flesh", best.point, -3.0)
			hits.append({"body": best_b, "dist": best.dist, "part": best.part, "point": best.point, "res": res})
	return hits

# ---------------------------------------------------------------- meshing on worker threads

func _mesh_jobs() -> void:
	# finished ones swapped in
	for i in range(_jobs.size() - 1, -1, -1):
		var j: Dictionary = _jobs[i]
		if WorkerThreadPool.is_task_completed(j.id):
			WorkerThreadPool.wait_for_task_completion(j.id)
			var b = (j.body as WeakRef).get_ref()
			if b and is_instance_valid(b):
				b.set_part_arrays(j.part, j.out.arrays)
			_jobs.remove_at(i)
			_jobs_done += 1
	# new ones, while there's room
	for b in bodies:
		if _jobs.size() >= MAX_JOBS:
			break
		for n in b.dirty_parts():
			if _jobs.size() >= MAX_JOBS:
				break
			var p: Dictionary = b.parts[n]
			p.dirty = false
			var g := {"size": p.grid.size, "cells": (p.grid.cells as PackedInt32Array).duplicate()}
			var out := {}
			var origin: Vector3 = b.mesh_origin(n)
			var vm: float = b.vm
			var id := WorkerThreadPool.add_task(func(): out["arrays"] = VoxMesher.mesh(g, origin, vm))
			p.job = id
			_jobs.append({"id": id, "body": weakref(b), "part": n, "out": out})

func _draw_tracers(dt: float) -> void:
	var im: ImmediateMesh = _tracers.mesh
	im.clear_surfaces()
	for i in range(_tracer_list.size() - 1, -1, -1):
		_tracer_list[i].t -= dt
		if _tracer_list[i].t <= 0.0:
			_tracer_list.remove_at(i)
	if _tracer_list.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for tr in _tracer_list:
		im.surface_add_vertex(tr.a)
		im.surface_add_vertex(tr.b)
	im.surface_end()

func _hud_text() -> void:
	var alive := 0
	var tris := 0
	for b in bodies:
		if b.alive:
			alive += 1
		tris += b.triangles()
	var fps := Engine.get_frames_per_second()
	hud.text = "%d fps   %.1f ms a frame   (game code %.1f ms)\ndraw calls %d   triangles on screen %s   (enemies %s)\nenemy %d   enemies %d alive, %d lying   kills %d\ncubes knocked out %d   flying now %d   meshing jobs %d running, %d done\ncube %.1f cm (%d sprite pixel%s a cube)   shadows %s   %s\n%s   cubes lying %s   pieces %d   backpack: %s   (Tab)" % [
		fps, 1000.0 / maxf(1.0, fps), _code_ms + debris.last_ms,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		_k(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)), _k(tris),
		wave, alive, bodies.size() - alive, kills, knocked, debris.count(), _jobs.size(), _jobs_done,
		_cube_m("grunt") * 100.0, chunk, "" if chunk == 1 else "s", ("on" if sun.shadow_enabled else "off") + ("   CAN'T DIE" if VoxelBody.immortal else ""),
		RenderingServer.get_current_rendering_method(),
		("%d %s" % [loadout.current + 1, loadout.slot().name]) + ("  (brush %.1f m)" % vacuum.brush_r if loadout.id() == "vacuum" else ""), _k(debris.lying()), pieces.count(),
		_backpack_line()]

static func _k(n: int) -> String:
	return "%.1fk" % (n / 1000.0) if n >= 1000 else str(n)

# the self-test: look at the nearest standing enemy's chest and fire (blaster, a shotgun blast now and then)
func _auto() -> void:
	var pp := cam.global_position
	var best: VoxelBody = null
	var bd := INF
	for b in bodies:
		if b.alive:
			var d := b.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = b
	if best == null:
		return
	var target := best.global_position + Vector3(0, best.height * (0.62 if randf() < 0.7 else 0.9), 0)
	var to := target - pp
	look_yaw = atan2(-to.x, -to.z)
	look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	var dir := to.normalized()
	if _fire_cd <= 0.0:
		_fire_cd = 0.1
		fire(pp, dir, 1, 0.6, 1.9)
	if _sg_cd <= 0.0:
		_sg_cd = 1.5
		fire(pp, dir, 9, 4.5, 1.4)

func _burst_save(k: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/burst_%d.png" % [String(_opts.burst), k])

# closing the window: no meshing job left running on a worker thread
func _exit_tree() -> void:
	VoxelBody.on_shatter = Callable()      # (a lambda on this arena: left behind once it's freed, it corrupts the heap)
	for j in _jobs:
		WorkerThreadPool.wait_for_task_completion(j.id)
	_jobs.clear()

func _finish() -> void:
	pieces.finish_jobs()
	for j in _jobs:
		WorkerThreadPool.wait_for_task_completion(j.id)
	_jobs.clear()
	var fr := _frames.slice(mini(_frames.size() - 1, 30))
	var sorted := Array(fr)
	sorted.sort()
	var med: float = sorted[sorted.size() / 2] if sorted.size() > 0 else 0.0
	print("ARENA done: %d frames, median %.1f ms, worst %.1f ms; kills %d, cubes %d, meshing jobs %d" % [
		_frames.size(), med * 1000.0, (sorted[-1] if sorted.size() > 0 else 0.0) * 1000.0, kills, knocked, _jobs_done])
	if _opts.has("shot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(_opts.shot))
		print("ARENA shot saved: ", _opts.shot)
	get_tree().quit()
