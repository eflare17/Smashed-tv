class_name VoxelMine
extends Node
## The dig mode (the owner, 23 Oct: "build it all"; the Motherload-style mine from their design notes): through the
## roller door in the yard (MineHatch) down to a side-on world of its own (its own 3D world in a SubViewport over the
## arena's screen, its own light and dark): the ground (MineGround), the ship (MineShip), the buildings up top (the
## fuel station, the trader, the mechanic, the lift back up), the moving hazards (MineCritters: the sewer rats, the
## cop drones, the rival crew) and the worm at the bottom (MineWorm). The fuel runs down as you drive, fly and drill;
## run out (or wreck the hull) and you're towed up without your cargo. Cargo sells at the trader for the arena's own
## cash (one wallet); the mechanic sells upgrades that change the ship's look; the trader sells dynamite, repair kits
## and a teleport home. The mushroom caves trip you out (the screen swims, the ship floats, the controls drift the
## longer you stay). Everything's saved with the backpack (VoxelStorages: "mine"). While you're down there the arena
## carries on without you (you're stood in the yard, where nothing comes for you). Owned by the voxel session.

## The trial hazards, each switched on or off in the settings (VoxelSettings: mine_sewers, mine_cops, mine_rivals)
static var hazards := {"sewers": true, "cops": true, "rivals": true}

const LAYER := 20
const FUEL_IDLE := 0.035        # litres a second, sat there ...
const FUEL_DRIVE := 0.09
const FUEL_THRUST := 0.30
const FUEL_DRILL := 0.24
const LAVA_BURN := 16.0         # hull a second in lava
const FALL_HURT := 3.2          # hull a m/s landing over the safe speed
const BUMP_HURT := 2.0
const TRIP_UP := 1.0 / 10.0     # the trip coming on a second in a mushroom cave ...
const TRIP_DOWN := 1.0 / 18.0   # ... and wearing off
const SAVE_EVERY := 8.0
const CAM_Z := 10.0             # the camera's distance (Sand Miner's chunky pixels: ~7 screen pixels a cell at 720p)
const CAM_EDGE := 9.0           # (it stops short of the world's sides)
const AMMO_ORDER := ["dirt", "clay", "sand", "water"]
const AMMO_MAT := {"dirt": MineTiles.DIRT, "clay": MineTiles.CLAY, "sand": MineTiles.SAND, "water": MineTiles.WATER}
const AMMO_NAME := {"dirt": "Dirt", "clay": "Clay (sticks)", "sand": "Sand", "water": "Water (turns lava to stone)"}
const WATER_CELLS := 6          # a squirt of water: smaller, faster (a hose, not a cannon)
const WATER_EVERY := 0.07
const SUCK_RATE := 110.0        # cells of water a second the hose sucks up
const AMMO_MAX := 600           # cells of each the hopper holds
const SHOT_CELLS := 14          # cells a shot takes
const SHOT_EVERY := 0.22
const NUG_RARE := ["gold", "opal", "diamond", "hoard", "evidence", "stash", "shroom"]

const TIPS := {
	"welcome": "Welcome to the mine! A/D drives (push into rock to drill through it), S drills down, W or Space flies you up. Fuel runs down all the time: keep an eye on it.",
	"first_ore": "Ore goes in your cargo bay. Fly back up and squirt it into the ORE box by the fuel station (E by it).",
	"fuel_low": "Fuel's low! Get up to the FUEL station before it runs out, or the tow truck drags you up and you lose your cargo.",
	"cargo_full": "Your cargo bay's full: what you dig now is lost. Go and sell, or get a bigger bay at the MECHANIC.",
	"sold": "Spend it at the MECHANIC: a faster drill, a bigger tank, more cargo, a tougher hull, brighter lights.",
	"hard": "Too hard for your drill: that boulder needs a better bit (the MECHANIC).",
	"deep": "It gets darker and the rock harder the deeper you go. Better lights help you see the ore.",
	"lava": "Lava! It runs into your tunnels and burns the hull. Spray water on it and it turns to stone you can dig through.",
	"water": "Water! Hold R to suck it up with the hose. Q picks Water for the launcher: spray it on lava to turn it to stone.",
	"gas": "Gas pocket! The greenish patches go off when you drill them.",
	"mush": "A mushroom cave... the spores get in your head (and the controls). Spore clumps sell well. Not all that glitters is gold.",
	"cops": "You've set off the cop bunker's alarm! Don't let a drone catch you (you'd lose your cargo and some cash). Ram one at speed to smash it, or get up top.",
	"rivals": "The rival dealers' tunnels! Their crew rams you: ram them back harder (fly at them fast) or run. Their stash sells.",
	"worm": "Something enormous lives down here. Ram it, drill into it, or dynamite it.",
	"items": "1 throws dynamite, 2 uses a repair kit, 3 teleports you home with your cargo. Buy them at the TRADER.",
	"sewer": "Old sewers: junk worth a bit, and rats that chew your hull. Drive over them fast to squash them.",
}

const TRIP_SHADER := """
shader_type canvas_item;
uniform float trip = 0.0;
uniform float dark = 0.2;
uniform float hurt = 0.0;
uniform float fade = 1.0;
vec3 hue(vec3 c, float a) {
	const vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}
void fragment() {
	vec2 uv = UV;
	float t = TIME;
	if (trip > 0.001) {
		uv += trip * 0.014 * vec2(sin(uv.y * 17.0 + t * 2.1), cos(uv.x * 13.0 + t * 1.7));
		uv = (uv - 0.5) * (1.0 - trip * 0.04 * sin(t * 1.3)) + 0.5;
	}
	float ab = trip * 0.009;
	vec3 c = vec3(texture(TEXTURE, uv + vec2(ab, 0.0)).r, texture(TEXTURE, uv).g, texture(TEXTURE, uv - vec2(ab, 0.0)).b);
	if (trip > 0.001) {
		c = mix(c, hue(c, t * 1.2 + uv.y * 4.0 + uv.x * 2.0), trip * 0.75);
		c *= 1.0 + trip * 0.25 * sin(t * 3.0 + uv.x * 9.0);
	}
	float d = distance(UV, vec2(0.5));
	c *= 1.0 - smoothstep(0.3, 0.8, d) * dark;
	c = mix(c, vec3(0.9, 0.05, 0.0), hurt * 0.45 * smoothstep(0.25, 0.75, d));
	COLOR = vec4(c * fade, 1.0);
}
"""

var arena: Node3D
var sound: VoxelSound:          # (the arena's: made after the mine's set up)
	get:
		return arena.sound
var active := false
var hatch: MineHatch
var layer: CanvasLayer
var _root: Control
var svc: SubViewportContainer
var vp: SubViewport
var screen_mat: ShaderMaterial
var world: Node3D
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var ground: MineGround
var ship: MineShip
var critters: MineCritters
var worm: MineWorm
var hud: MineHud
var auto = null                 # (tests) a Dictionary of held keys {x, up, down} in place of the keyboard
var cam_hold := false           # (tests, pictures) the camera left where it's put
# what's kept (saved)
var upg := {"drill": 0, "tank": 0, "cargo": 0, "hull": 0, "lights": 0, "launcher": 0, "lift": 0}
var fuel := 12.0
var hull := 30.0
var cargo := {}
var items := {"dynamite": 1, "repair": 1, "teleport": 0}
var worm_dead := false
var tips_done := {}
var stats := {"dives": 0, "deepest": 0, "earned": 0}
# the moment
var trip := 0.0
var cave_t := 0.0
var drift := 0.0
var day := 0
var _built := false
var _save := {}                 # a save waiting for the first time down
var _fade := 0.0
var _going := 0                 # 1 going down, -1 coming up, 0 neither
var _shake := 0.0
var _hurt := 0.0
var _alarm_t := 0.0
var _refuse_t := 0.0
var _save_t := 0.0
var _near := ""
var ore_box: MineOreBox         # where the cargo's sold: squirted in up top
var _water_hose := 0.0          # (the hose run out for water: sucking it up)
var sucking := false            # R held: the hose sucking water up
var _suck_acc := 0.0
var _suck_none_t := 0.0
var _drops: Array = []          # {n, from, t}: water flying up the hose
var _steam_t := 0.0
var _spray_t := 0.0
var _chain: Array = []          # gas pockets about to go off: [time, Vector2]
var _cave_lights: Array = []
var _lava_lights: Array[OmniLight3D] = []
var _bunker_lights: Array[OmniLight3D] = []
var _lava_t := 0.0
var _sparks: Array = []
var _was_lava := false
var _boom_light: OmniLight3D
var _cam_at := Vector3(25, 0, 10)
var _soft_dirty := false
var last_hurt := ""             # what hurt the ship last ("fall", "lava", "rats" ...)
var _resume := Vector2.INF      # where the ship was left underground (a quit down there): back there next time
# the launcher (Sand Miner's): dirt, clay and sand the drill brings up, shot where the mouse points
var ammo := {"dirt": 0, "clay": 0, "sand": 0, "water": 0}
var ammo_sel := "dirt"
var aim := Vector2.ZERO         # the world point the mouse is on
var aiming := false             # the mouse is over the mine (the HUD draws the shot's arc)
var _shots: Array = []          # {n: MeshInstance3D, p, v, m (material)}
var _launch_t := 0.0
var _nuggets: Array = []        # {n: MeshInstance3D, p, v, id, age, rare}
var _carry := {}                # material -> cells of it drilled towards the next nugget
var _combo := 0                 # nuggets in a row (their chime climbs)
var _combo_t := 0.0
var _hitstop := 0.0             # a split second's freeze on a big find
var _crunch := 0.0              # cells broken towards the next crunch
var _spark_t := 0.0
var _dust_t := 0.0
var _fools_t := 0.0
var _touch := 0.0               # how much the drill's been biting lately (a breakthrough when it stops dead)
var _ground_mem := PackedByteArray()     # (no save file: the tests) the ground's bytes
var _ground_dirty := false

func setup(arena_: Node3D) -> void:
	arena = arena_
	hatch = MineHatch.new()
	hatch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arena.add_child(hatch)
	hatch.setup()

# ---------------------------------------------------------------- the world down there

func _build() -> void:
	if _built:
		return
	_built = true
	layer = CanvasLayer.new()
	layer.layer = LAYER
	layer.visible = false
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)
	svc = SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(svc)
	screen_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TRIP_SHADER
	screen_mat.shader = sh
	svc.material = screen_mat
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.handle_input_locally = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	world = Node3D.new()
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # (it all moves in _process)
	vp.add_child(world)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.current = true
	cam.position = Vector3(25, 0, CAM_Z)
	world.add_child(cam)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color8(120, 170, 220)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	world.add_child(sun)
	ground = MineGround.new()
	world.add_child(ground)
	ship = MineShip.new()
	ship.ground = ground
	world.add_child(ship)
	ship.dug.connect(_on_dug)
	ship.bumped.connect(_on_bump)
	critters = MineCritters.new()
	world.add_child(critters)
	critters.setup(self, ground)
	worm = MineWorm.new()
	world.add_child(worm)
	worm.setup(self, ground)
	_buildings()
	ore_box = MineOreBox.new()
	world.add_child(ore_box)
	ore_box.setup(self)
	for k in 6:
		var l := OmniLight3D.new()
		l.light_color = Color8(255, 120, 30)
		l.omni_range = 3.5
		l.light_energy = 0.0
		world.add_child(l)
		_lava_lights.append(l)
	_boom_light = OmniLight3D.new()
	_boom_light.light_color = Color8(255, 190, 120)
	_boom_light.omni_range = 7.0
	_boom_light.light_energy = 0.0
	world.add_child(_boom_light)
	hud = MineHud.new()
	_root.add_child(hud)
	hud.setup(self)
	var gb := _read_ground()
	if gb.is_empty() or not ground.load_bytes(gb):
		ground.generate(randi() % 1000000 + 1, _flags())
		_ground_dirty = true
	ground.build_all()
	_feature_lights()
	worm.spawn(worm_dead)
	ship.build(upg)
	ship.place(_lift_spot())

func _flags() -> Dictionary:
	return {"sewers": hazards.get("sewers", true), "cops": hazards.get("cops", true), "rivals": hazards.get("rivals", true)}

func _lift_spot() -> Vector2:
	return Vector2(MineGround.building_x("lift"), MineShip.HALF + 0.002)

## The buildings up top (behind the ship's way, along the ground)
func _buildings() -> void:
	var root := Node3D.new()
	world.add_child(root)
	var signs := {"lift": ["LIFT", Color8(240, 186, 40)], "fuel": ["FUEL", Color8(230, 60, 50)], "trader": ["TRADER", Color8(80, 200, 110)], "mechanic": ["MECHANIC", Color8(90, 150, 240)]}
	for b in MineGround.BUILDINGS:
		var name := String(b[0])
		var x0 := float(b[1])
		var x1 := float(b[2]) + 1.0
		var w := x1 - x0
		var h := 3.2 if name != "lift" else 4.4
		var col: Color = signs[name][1]
		var wall := StandardMaterial3D.new()
		wall.albedo_color = Color8(200, 196, 186) if name != "lift" else Color8(90, 94, 100)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w - 0.2, h, 1.6)
		box.mesh = bm
		box.material_override = wall
		box.position = Vector3((x0 + x1) * 0.5, h * 0.5, -1.45)
		root.add_child(box)
		var trim := StandardMaterial3D.new()
		trim.albedo_color = col
		var roof := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(w + 0.1, 0.25, 1.9)
		roof.mesh = rm
		roof.material_override = trim
		roof.position = Vector3((x0 + x1) * 0.5, h + 0.12, -1.4)
		root.add_child(roof)
		# a doorway, lit
		var door := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(minf(1.6, w - 1.0), 1.9, 0.05)
		door.mesh = dm
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color8(40, 36, 30) if name != "lift" else Color8(10, 10, 12)
		dmat.emission_enabled = name != "lift"
		dmat.emission = Color8(255, 210, 140)
		dmat.emission_energy_multiplier = 0.4
		door.material_override = dmat
		door.position = Vector3((x0 + x1) * 0.5, 0.95, -0.63)
		root.add_child(door)
		var l := Label3D.new()
		l.text = String(signs[name][0])
		l.font_size = 96
		l.pixel_size = 0.006
		l.outline_size = 14
		l.modulate = col.lightened(0.3)
		l.position = Vector3((x0 + x1) * 0.5, h - 0.5, -0.62)
		root.add_child(l)
		var lt := OmniLight3D.new()
		lt.light_color = Color8(255, 220, 170)
		lt.omni_range = 4.0
		lt.light_energy = 0.7
		lt.position = Vector3((x0 + x1) * 0.5, 2.4, 0.3)
		root.add_child(lt)
		if name == "fuel":
			for px in [x0 + 0.7, x1 - 0.7]:
				var pump := MeshInstance3D.new()
				var pm := BoxMesh.new()
				pm.size = Vector3(0.4, 1.2, 0.35)
				pump.mesh = pm
				pump.material_override = trim
				pump.position = Vector3(px, 0.6, -0.35)
				root.add_child(pump)
	# the lift's headframe over its shaft: a steel tower and a wheel
	var lx := MineGround.building_x("lift")
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color8(110, 70, 50)
	steel.metallic = 0.5
	for sx in [-1.4, 1.4]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.15, 6.5, 0.15)
		leg.mesh = lm
		leg.material_override = steel
		leg.position = Vector3(lx + sx * 0.7, 3.25, -2.4)
		leg.rotation.z = -sx * 0.08
		root.add_child(leg)
	var wheel := MeshInstance3D.new()
	var wm := TorusMesh.new()
	wm.inner_radius = 0.45
	wm.outer_radius = 0.6
	wheel.mesh = wm
	wheel.material_override = steel
	wheel.rotation.x = PI * 0.5
	wheel.position = Vector3(lx, 6.4, -2.4)
	root.add_child(wheel)
	# hills far off, and the back of the yard's fence
	var hill := StandardMaterial3D.new()
	hill.albedo_color = Color8(70, 120, 60)
	for k in 7:
		var hm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 9.0 + (k % 3) * 3.0
		sm.height = sm.radius * 1.2
		hm.mesh = sm
		hm.material_override = hill
		hm.position = Vector3(-10 + k * 12.0, -4.0, -26.0 - (k % 2) * 6.0)
		root.add_child(hm)
	var fence := StandardMaterial3D.new()
	fence.albedo_color = Color8(150, 112, 70)
	var fm := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(MineGround.W + 30.0, 1.8, 0.1)
	fm.mesh = fb
	fm.material_override = fence
	fm.position = Vector3(MineGround.W * 0.5, 0.9, -4.5)
	root.add_child(fm)

## The lights in the ground's features: the mushroom caves glow (it shows through the dirt), the bunker's red and
## blue through its cracks, a dull red in the worm's cavern.
func _feature_lights() -> void:
	for l in _cave_lights:
		if is_instance_valid(l):
			l.queue_free()
	_cave_lights.clear()
	_bunker_lights.clear()
	for c in ground.features.get("caves", []):
		_cave_lights.append(_light(Vector2(c[0], -c[1]), Color.from_hsv(randf_range(0.72, 0.92), 0.7, 1.0), float(c[2]) + 3.0, 1.6))
	var cat: Array = ground.features.get("cathedral", [])
	if not cat.is_empty():
		_cave_lights.append(_light(Vector2(cat[0], -cat[1]), Color8(230, 90, 255), 14.0, 2.6))
		_cave_lights.append(_light(Vector2(float(cat[4]) + 1.0, -float(cat[5]) + 6.0), Color8(255, 120, 200), 6.0, 2.0))
	var b: Array = ground.features.get("bunker", [])
	if not b.is_empty():
		for k in 2:
			var l := _light(Vector2(lerpf(float(b[0]), float(b[2]), 0.3 + 0.4 * k), -float(b[1]) - 2.0), Color.RED, 7.5, 2.0)
			_cave_lights.append(l)
			_bunker_lights.append(l)
	var w: Array = ground.features.get("worm", [])
	if not w.is_empty():
		_cave_lights.append(_light(Vector2(w[0], -w[1]), Color8(200, 50, 40), 12.0, 1.2))

func _light(at: Vector2, c: Color, r: float, e: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.omni_range = r
	l.light_energy = e
	l.omni_attenuation = 1.4
	l.position = Vector3(at.x, at.y, 0.9)
	world.add_child(l)
	return l

# ---------------------------------------------------------------- going down, coming up

func can_enter() -> bool:
	return not active and _going == 0

func enter() -> void:
	if not can_enter():
		return
	_build()
	_going = 1
	_fade = 0.0
	hatch.want = 1.0
	sound.play("mine_door", Vector3.INF, -2.0)
	active = true
	layer.visible = true
	_root.modulate.a = 0.0
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	day = MineShop.today()
	fuel = minf(fuel, tank_max())
	hull = minf(hull, hull_max())
	ship.build(upg)
	ship.place(_resume if _resume != Vector2.INF else _lift_spot())
	_resume = Vector2.INF
	critters.on_enter()
	stats.dives = int(stats.dives) + 1
	trip = 0.0
	cave_t = 0.0
	hud.close_menu()
	tip("welcome")

func leave() -> void:
	if not active or _going == -1:
		return
	_going = -1
	hud.close_menu()
	ore_box.finish_now()
	sound.play("mine_door", Vector3.INF, -2.0, 0.9)
	sound.stop("mine_drill")
	sound.stop("mine_engine")
	sound.stop("mine_prop")
	sound.stop("mine_booster")
	sound.stop("mine_suck")
	sound.stop("mine_spray")
	sound.stop("mine_siren")
	critters.stand_down()
	arena.get_viewport().disable_3d = false
	arena.player.global_position = Vector3(MineHatch.AT.x, 0.05, MineHatch.AT.z + 1.0)
	arena.player.velocity = Vector3.ZERO
	arena.look_yaw = PI
	arena.look_pitch = 0.0
	if arena.stash:
		arena.stash.save()

func _finish_going(dt: float) -> void:
	if _going == 1:
		_fade = minf(1.0, _fade + dt * 2.2)
		_root.modulate.a = _fade
		if _fade >= 1.0:
			_going = 0
			arena.get_viewport().disable_3d = true      # (the arena isn't seen: not drawn either)
	elif _going == -1:
		_fade = maxf(0.0, _fade - dt * 2.2)
		_root.modulate.a = _fade
		if _fade <= 0.0:
			_going = 0
			active = false
			layer.visible = false
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			hatch.want = 0.0
			if not arena.top_down:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ---------------------------------------------------------------- what's kept

func tank_max() -> float:
	return MineShop.k("tank", upg.tank)

func hull_max() -> float:
	return MineShop.k("hull", upg.hull)

func cargo_cap() -> int:
	return int(MineShop.k("cargo", upg.cargo))

func cargo_count() -> int:
	var n := 0
	for id in cargo:
		n += int(cargo[id])
	return n

## Something worth saving now (money, upgrades): the backpack's save soon.
func _dirty() -> void:
	if arena.stash:
		arena.stash._dirty = true

## Something to save in a while (damage, a tile, cargo, a tip): with the next of the mine's own saves.
func _soft() -> void:
	_soft_dirty = true

func save_data() -> Dictionary:
	var d := {"v": 1, "upg": upg.duplicate(), "fuel": fuel, "hull": hull, "cargo": cargo.duplicate(), "items": items.duplicate(),
		"worm_dead": worm_dead, "tips": tips_done.keys(), "stats": stats.duplicate()}
	if _built and active and ship.p.y < -0.5:
		d["ship"] = [ship.p.x, ship.p.y]     # (quit down there: back down there)
	elif _resume != Vector2.INF:
		d["ship"] = [_resume.x, _resume.y]
	d["ammo"] = ammo.duplicate()
	if _built:
		ground.changed += ground.sim.take_changed()
	if _built and ground.changed > 0:
		_ground_dirty = true     # (dug since the last tick: the ground goes with the cargo, or the ore's back to dig again)
		ground.changed = 0
	_write_ground()
	return d

## Where the ground's kept: beside the backpack's save (it's big: every cell), "" for none (the tests)
func _ground_path() -> String:
	var sp := String(arena.stash.save_path) if arena.stash else ""
	return "" if sp == "" else sp.get_basename() + "_mine.bin"

func _read_ground() -> PackedByteArray:
	var path := _ground_path()
	if path != "" and FileAccess.file_exists(path):
		return FileAccess.get_file_as_bytes(path)
	return _ground_mem

## The ground written out, if it's changed since
func _write_ground() -> void:
	if not _built or not _ground_dirty:
		return
	_ground_dirty = false
	var b := ground.save_bytes()
	var path := _ground_path()
	if path == "":
		_ground_mem = b
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(b)

func load_data(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	if typeof(d.get("upg")) == TYPE_DICTIONARY:
		for k in upg:
			upg[k] = clampi(int(d.upg.get(k, 0)), 0, 3)
	if typeof(d.get("ammo")) == TYPE_DICTIONARY:
		for k in ammo:
			ammo[k] = clampi(int(d.ammo.get(k, 0)), 0, AMMO_MAX)
	fuel = clampf(float(d.get("fuel", tank_max())), 0.0, tank_max())
	hull = clampf(float(d.get("hull", hull_max())), 1.0, hull_max())
	cargo = {}
	if typeof(d.get("cargo")) == TYPE_DICTIONARY:
		for id in d.cargo:
			if MineShop.CARGO.has(String(id)) and int(d.cargo[id]) > 0:
				cargo[String(id)] = int(d.cargo[id])
	if typeof(d.get("items")) == TYPE_DICTIONARY:
		for id in items:
			items[id] = clampi(int(d.items.get(id, 0)), 0, int(MineShop.ITEMS[id].max))
	worm_dead = bool(d.get("worm_dead", false))
	tips_done = {}
	if typeof(d.get("tips")) == TYPE_ARRAY:
		for t in d.tips:
			tips_done[String(t)] = true
	if typeof(d.get("stats")) == TYPE_DICTIONARY:
		for k in stats:
			stats[k] = int(d.stats.get(k, 0))
	_resume = Vector2.INF
	if typeof(d.get("ship")) == TYPE_ARRAY and (d.ship as Array).size() == 2:
		_resume = Vector2(clampf(float(d.ship[0]), 1.5, MineGround.W - 1.5), clampf(float(d.ship[1]), -MineGround.D + 1.5, 0.0))
	_save = d
	if _built:
		worm.spawn(worm_dead)
	var gb := _read_ground() if _built else PackedByteArray()
	if _built and not gb.is_empty() and ground.load_bytes(gb):
		critters.clear()
		ground.build_all()
		_feature_lights()
		worm.spawn(worm_dead)
		ship.build(upg)
		ship.place(_lift_spot())

# ---------------------------------------------------------------- each frame

func _process(dt: float) -> void:
	if not active:
		# (--mine on the command line: straight down the mine once the arena's up)
		if arena._opts.has("mine") and not arena._opts.has("mine_done") and Engine.get_process_frames() > 30:
			arena._opts["mine_done"] = "1"
			enter()
			print("MINE entered from the command line: ground %d x %d cells" % [MineGround.CW, MineGround.CH])
		return
	_finish_going(dt)
	if not active:
		return
	dt = minf(dt, 1.0 / 30.0)       # (a long frame, a window dragged: not through the floor)
	if _going == 0 and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE     # (a menu closing grabs it for the arena: the mine's is clickable)
	var menu_up: bool = hud.menu_open() or (arena.settings_menu and arena.settings_menu.is_open()) or (arena.net_menu and arena.net_menu.is_open()) or _going != 0
	var ix := 0.0
	var up := false
	var down := false
	if auto != null:
		ix = float(auto.get("x", 0.0))
		up = bool(auto.get("up", false))
		down = bool(auto.get("down", false))
		sucking = bool(auto.get("suck", false))
	elif not menu_up:
		sucking = Input.is_physical_key_pressed(KEY_R)
		ix = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		up = Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_SPACE)
		down = Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	# the trip: the controls drift (more the longer you've been in there)
	drift = clampf(drift + randf_range(-1.0, 1.0) * dt * 3.0, -1.0, 1.0)
	var dk := trip * clampf(cave_t / 20.0, 0.25, 1.0)
	ix = clampf(ix + drift * dk * 0.9, -1.0, 1.0)
	ship.grav_k = lerpf(1.0, 0.4, trip)
	var was_drilling := ship.drilling
	# a big find: the world holds its breath a moment
	var frozen := _hitstop > 0.0
	_hitstop = maxf(0.0, _hitstop - dt)
	if not frozen:
		ground.keep_clear = MineGround.cells_of(ship.p, Vector2(MineShip.HALF, MineShip.HALF))
		ship.step(dt, ix, up, down, fuel > 0.0)
		ground.keep_clear = MineGround.cells_of(ship.p, Vector2(MineShip.HALF, MineShip.HALF))
		ground.tick(dt)
	if ship.refused > 0 and ship.broke == 0 and _refuse_t <= 0.0:
		_refuse_t = 1.2
		if ship.refused >= 100:
			say("Nothing gets through that", 1.0)
		else:
			say("Too hard: needs the %s drill" % String(MineShop.UPGRADES.drill.names[clampi(ship.refused, 0, 3)]), 1.5)
			tip("hard")
		sound.play("mine_hit", Vector3.INF, -10.0, 1.6)
	_refuse_t -= dt
	_fools_t -= dt
	if not ship.drilling:
		if _touch > 6.0 and ground.count(ship.p + Vector2(ship.drill_dir.x, -absf(ship.drill_dir.y)) * 0.9, Vector2(0.4, 0.4), -6) > 30:
			# broke through into open space
			sound.play("mine_boom", Vector3.INF, -8.0, 1.8)
			sound.play("mine_hit", Vector3.INF, -2.0, 0.5)
			shake(0.3)
		_touch = 0.0
	if menu_up and auto == null:
		sucking = false
	_launcher(dt, menu_up)
	_suck(dt)
	if ship.wet > 0.2:
		tip("water")
	_step_nuggets(dt)
	_step_shots(dt)
	# fuel
	var use := FUEL_IDLE
	if ship.thrusting:
		use += FUEL_THRUST * MineShop.LIFT_FUEL[clampi(int(upg.lift), 0, 3)]
	if ship.drilling:
		use += FUEL_DRILL
	if ship.driving:
		use += FUEL_DRIVE
	if _going == 0 and not hud.menu_open():
		fuel = maxf(0.0, fuel - use * dt)
	if fuel < tank_max() * 0.2 and fuel > 0.0 and ship.p.y < -1.0:
		_alarm_t -= dt
		if _alarm_t <= 0.0:
			_alarm_t = 2.0
			sound.play("mine_alarm", Vector3.INF, -8.0)
			tip("fuel_low")
	if fuel <= 0.0 and not ship.drilling:
		tow("fuel")                 # (anywhere, up top too: with none you can't move to the pumps)
	# the ground: lava burning, gas going off one after another
	var in_lava := ground.count(ship.p, Vector2(MineShip.HALF + 0.12, MineShip.HALF + 0.12), -4) > 0
	if in_lava:
		hurt(LAVA_BURN * dt, "lava")
		if not _was_lava:
			sound.play("mine_lava", Vector3.INF, -2.0)
			say("Lava! It's burning the hull", 1.5)
			tip("lava")
	_was_lava = in_lava
	for i in range(_chain.size() - 1, -1, -1):
		_chain[i][0] -= dt
		if _chain[i][0] <= 0.0:
			var at: Vector2 = _chain[i][1]
			_chain.remove_at(i)
			explode(at, 2.2, false)
	# the trip
	var bgk := ground.bg_at(ship.p)
	if bgk == MineTiles.BG_MUSH or bgk == MineTiles.BG_CATHEDRAL:
		trip = minf(1.0, trip + TRIP_UP * (1.6 if bgk == MineTiles.BG_CATHEDRAL else 1.0) * dt)
		cave_t += dt
		tip("mush")
	else:
		trip = maxf(0.0, trip - TRIP_DOWN * dt)
		cave_t = maxf(0.0, cave_t - dt * 2.0)
	if bgk == MineTiles.BG_SEWER:
		tip("sewer")
	if bgk == MineTiles.BG_RIVAL:
		tip("rivals")
	critters.check_bunker(ship.p, false)
	critters.step(dt)
	worm.step(dt)
	# the wreck
	if hull <= 0.0:
		tow("wreck")
	var depth := int(maxf(0.0, -ship.p.y))
	if depth > int(stats.deepest):
		stats.deepest = depth
	if depth >= 50:
		tip("deep")
	_buildings_near()
	_sounds(dt, was_drilling)
	_view(dt)
	_save_t += dt
	if _save_t > SAVE_EVERY:
		_save_t = 0.0
		if ground.changed > 0 or _soft_dirty:
			if ground.changed > 0:
				_ground_dirty = true
			ground.changed = 0
			_soft_dirty = false
			_dirty()

func _sounds(dt: float, was_drilling: bool) -> void:
	if _going == -1:
		return
	var thrust := ship.thrusting
	sound.loop("mine_engine", "mine_engine", null, -10.0 if thrust else (-12.0 if ship.driving else -17.0), 1.1 if thrust else (1.0 if ship.driving else 0.8))
	# the lift: the propeller's whup-whup (faster with the big blades), the boosters' roar (deeper for the mega)
	var lv := clampi(int(upg.lift), 0, 3)
	var lift_snd := "mine_prop" if lv < 2 else "mine_booster"
	var other := "mine_booster" if lv < 2 else "mine_prop"
	if sound.playing(other):
		sound.stop(other)
	if thrust:
		sound.loop(lift_snd, lift_snd, null, -5.0 if lv < 2 else -3.0, [0.9, 1.25, 1.15, 0.85][lv])
	elif sound.playing(lift_snd):
		sound.stop(lift_snd)
	if ship.drilling:
		# the whine's pitch: lower and harsher the harder the rock (for the drill you've got)
		var k := ship.hardness / maxf(0.5, ship.drill_power)
		sound.loop("mine_drill", "mine_drill", null, -5.0, clampf(1.5 - k * 0.35, 0.55, 1.5))
	elif sound.playing("mine_drill"):
		sound.stop("mine_drill")

func _view(dt: float) -> void:
	var depth := maxf(0.0, -ship.p.y)
	var sky := clampf(1.0 - depth / 9.0, 0.0, 1.0)
	var deep := clampf(depth / float(MineGround.D), 0.0, 1.0)
	sun.light_energy = 1.1 * sky
	env.ambient_light_energy = lerpf(lerpf(0.24, 0.06, deep), 0.8, sky)
	env.ambient_light_color = Color(0.7, 0.75, 0.85).lerp(Color(0.5, 0.45, 0.6), deep)
	env.background_color = Color8(120, 170, 220).lerp(Color(0, 0, 0), 1.0 - sky)
	var want := Vector3(clampf(ship.p.x, CAM_EDGE, MineGround.W - CAM_EDGE), ship.p.y + 0.6 + sky * 1.5, CAM_Z)
	if not cam_hold:
		_cam_at = _cam_at.lerp(want, minf(1.0, dt * 6.0)) if _cam_at.distance_to(want) < 12.0 else want
		_shake = maxf(0.0, _shake - dt * 1.8)
		cam.position = _cam_at + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.25
	ground.view(Vector2(cam.position.x, cam.position.y))
	_hurt = maxf(0.0, _hurt - dt * 2.0)
	screen_mat.set_shader_parameter("trip", trip)
	screen_mat.set_shader_parameter("dark", lerpf(0.15, 0.85, clampf(depth / 60.0, 0.0, 1.0)))
	screen_mat.set_shader_parameter("hurt", _hurt)
	# the lava's glow on what's round it (the nearest few)
	_lava_t -= dt
	if _lava_t <= 0.0:
		_lava_t = 0.4
		var near := _lava_near()
		for i in _lava_lights.size():
			var l := _lava_lights[i]
			if i < near.size():
				l.position = Vector3(near[i].x, near[i].y, 0.7)
				l.light_energy = 1.6
			else:
				l.light_energy = 0.0
	for l in _lava_lights:
		if l.light_energy > 0.0:
			l.light_energy = 1.3 + sin(Time.get_ticks_msec() / 300.0 + l.position.x) * 0.3
	# the bunker's lights: a slow red and blue, quick when the alarm's going
	var rate := 6.0 if critters.alarm else 1.4
	for i in _bunker_lights.size():
		var on := fmod(Time.get_ticks_msec() / 1000.0 * rate + i * 0.5, 1.0) < 0.5
		_bunker_lights[i].light_color = Color(1.0, 0.1, 0.05) if on else Color(0.15, 0.3, 1.0)
	_boom_light.light_energy = maxf(0.0, _boom_light.light_energy - dt * 12.0)
	for i in range(_sparks.size() - 1, -1, -1):
		_sparks[i][1] -= dt
		if _sparks[i][1] <= 0.0:
			(_sparks[i][0] as Node).queue_free()
			_sparks.remove_at(i)

## Parked by a building up top (or over the ORE box, with cargo to squirt in): its prompt.
func _buildings_near() -> void:
	_near = ""
	if ship.grounded and ship.p.y > 0.0 and ship.p.y < 1.0:
		_near = MineGround.building_at(ship.p.x)
	# (the box: when you're over it in the air, or parked between the buildings by it)
	if ore_box and (_near == "" or ore_box.unloading) and MineOreBox.in_reach(ship.p) and (cargo_count() > 0 or ore_box.unloading):
		_near = "orebox"
	ship.hose_out = maxf(ore_box.hose if ore_box else 0.0, _water_hose)
	var t := ""
	match _near:
		"lift": t = "E  ride the lift up to the yard"
		"fuel": t = "E  FUEL station"
		"trader": t = "E  TRADER: dynamite, repair kits, teleports"
		"mechanic": t = "E  MECHANIC: upgrades and repairs"
		"orebox": t = "Squirting it in..." if ore_box.unloading else "E  squirt your cargo into the ORE box"
	hud.prompt(t)

# ---------------------------------------------------------------- keys

func _unhandled_input(e: InputEvent) -> void:
	if not active or _going != 0:
		return
	if (arena.settings_menu and arena.settings_menu.is_open()) or (arena.net_menu and arena.net_menu.is_open()):
		return
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k: int = e.physical_keycode
	if hud.menu_open():
		if k == KEY_E or k == KEY_ESCAPE:
			hud.close_menu()
		elif k >= KEY_1 and k <= KEY_9:
			hud.menu_key(k - KEY_1 + 1)
		get_viewport().set_input_as_handled()
		return
	match k:
		KEY_E:
			use()
		KEY_1:
			use_item("dynamite")
		KEY_2:
			use_item("repair")
		KEY_3:
			use_item("teleport")
		KEY_Q:
			ammo_sel = AMMO_ORDER[(AMMO_ORDER.find(ammo_sel) + 1) % AMMO_ORDER.size()]
			say("Launcher: %s (%d)" % [AMMO_NAME[ammo_sel], int(ammo[ammo_sel])], 1.2)
		KEY_F:
			_launch_t = 0.0
			shoot()
		KEY_ESCAPE:
			if _near == "":
				say("Up at the LIFT (top left) to leave the mine", 2.0)
	get_viewport().set_input_as_handled()

## E: the building you're parked at.
func use() -> void:
	match _near:
		"lift":
			leave()
		"fuel":
			_fuel_menu()
		"trader":
			_trader_menu()
		"mechanic":
			_mechanic_menu()
		"orebox":
			ore_box.start(cargo)

# ---------------------------------------------------------------- what the drill brings up

## What the drill broke this step: ore towards nuggets (they pop out and fly to the ship), dirt, clay and sand into
## the launcher's hopper, gas going off, fool's gold crumbling, the bunker's walls setting off its alarm; and the
## feel of it: the crunch, sparks off hard rock, dust, the shake.
func _on_dug(res: Dictionary, dir: Vector2) -> void:
	var counts: PackedInt32Array = res.counts
	var sx: PackedFloat32Array = res.sx
	var sy: PackedFloat32Array = res.sy
	var broke := int(res.broke)
	var hard := float(res.hard)
	_touch = minf(30.0, _touch * 0.9 + float(res.touched))
	var gas_at := Vector2.INF
	for m in counts.size():
		var n := counts[m]
		if n <= 0:
			continue
		var at := MineGround.world(Vector2i(int(sx[m] / n), int(sy[m] / n)))
		match m:
			MineTiles.GAS:
				gas_at = at     # (after the rest's counted: what broke with it is still yours)
				continue
			MineTiles.FOOLS:
				if _fools_t <= 0.0:
					_fools_t = 2.5
					say("Fool's gold! It crumbled to dust", 1.8)
					sound.play("mine_crumble", Vector3.INF, -2.0)
			MineTiles.CONCRETE, MineTiles.EVIDENCE:
				critters.check_bunker(at, true)
		for a in AMMO_ORDER:
			if int(AMMO_MAT[a]) == m:
				ammo[a] = mini(AMMO_MAX, int(ammo[a]) + n)
		_ore(m, n, at)
	if gas_at != Vector2.INF:
		tip("gas")
		explode(gas_at, 2.2, false)
		return
	if broke > 0:
		_crunch += broke
		if _crunch >= 6.0:
			_crunch = 0.0
			sound.play("mine_crunch", Vector3.INF, -6.0 + minf(4.0, broke * 0.3), clampf(1.35 - hard * 0.2, 0.6, 1.4), 0.15)
		var tipp := ship.p + (Vector2(dir.x * (MineShip.HALF + 0.3), 0.0) if dir.y == 0.0 else Vector2(0.0, -MineShip.HALF - 0.3))
		_spark_t -= get_process_delta_time()
		if hard >= 0.9 and _spark_t <= 0.0:
			_spark_t = 0.07
			spark(tipp, Color(1.0, 0.75, 0.35).lerp(Color(1, 1, 1), ship.heat), 5 + int(hard * 2.0))
		_dust_t -= get_process_delta_time()
		if _dust_t <= 0.0:
			_dust_t = 0.18
			_dust(tipp)
		shake(minf(0.22, 0.03 + hard * 0.05))

## Drilled cells of material m (n of them, around at) towards nuggets of what it is
func _ore(m: int, n: int, at: Vector2) -> void:
	var inf := MineTiles.info(m)
	var id := String(inf.cargo)
	if id == "":
		return
	var per := maxi(1, int(inf.per))
	_carry[m] = float(_carry.get(m, 0.0)) + n
	var made := 0
	while float(_carry[m]) >= per and made < 6:
		_carry[m] = float(_carry[m]) - per
		made += 1
		_nugget(id, m, at)

## A nugget popping out of the rock (it flies to the ship after a moment)
func _nugget(id: String, m: int, at: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.16)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	var sh := MineTiles.shades(m)
	mat.albedo_color = sh[6]
	mat.emission_enabled = true
	mat.emission = sh[7]
	mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	mi.position = Vector3(at.x, at.y, 0.5)
	world.add_child(mi)
	var rare := id in NUG_RARE
	_nuggets.append({"n": mi, "p": at, "v": Vector2(randf_range(-1.5, 1.5), randf_range(2.5, 4.5)), "id": id, "age": 0.0})
	if rare:
		_hitstop = maxf(_hitstop, 0.07)
		shake(0.25)
		sound.play("mine_clink", Vector3.INF, 0.0, 1.5)

func _step_nuggets(dt: float) -> void:
	_combo_t -= dt
	if _combo_t <= 0.0:
		_combo = 0
	for i in range(_nuggets.size() - 1, -1, -1):
		var g: Dictionary = _nuggets[i]
		g.age += dt
		var to: Vector2 = ship.p - g.p
		if g.age > 0.3:
			# pulled to the ship
			g.v = (g.v as Vector2).lerp(to.normalized() * (6.0 + g.age * 6.0), minf(1.0, dt * 6.0))
		else:
			g.v.y -= 14.0 * dt
		g.p += g.v * dt
		(g.n as MeshInstance3D).position = Vector3(g.p.x, g.p.y, 0.5)
		(g.n as MeshInstance3D).rotation += Vector3(dt * 5.0, dt * 7.0, 0)
		if (g.age > 0.3 and to.length() < 0.45) or g.age > 4.0:
			g.n.queue_free()
			_nuggets.remove_at(i)
			_combo += 1
			_combo_t = 0.7
			_take(String(g.id), mini(_combo, 10))

func _take(c: String, combo := 1) -> void:
	if cargo_count() >= cargo_cap():
		say("Cargo full! The %s fell out" % String(MineShop.CARGO[c].name).to_lower(), 1.5)
		sound.play("mine_crumble", Vector3.INF, -6.0, 1.3)
		tip("cargo_full")
		return
	cargo[c] = int(cargo.get(c, 0)) + 1
	sound.play("mine_clink", Vector3.INF, -3.0, 0.85 + combo * 0.07 + MineShop.CARGO_ORDER.find(c) * 0.03, 0.0)
	hud.pop("+ " + String(MineShop.CARGO[c].name), Color8(255, 230, 140))
	tip("first_ore")
	if cargo_count() >= cargo_cap():
		tip("cargo_full")
	_soft()

func _on_bump(speed: float, landing: bool) -> void:
	if landing and speed > MineShip.FALL_SAFE:
		hurt((speed - MineShip.FALL_SAFE) * FALL_HURT, "fall")
		sound.play("mine_hit", Vector3.INF, 0.0, 0.8)
		shake(0.35)
	elif speed > MineShip.BUMP_SAFE:
		hurt((speed - MineShip.BUMP_SAFE) * BUMP_HURT, "bump")
		sound.play("mine_hit", Vector3.INF, -4.0, 1.0)
	else:
		sound.play("mine_hit", Vector3.INF, -16.0, 1.3)

# ---------------------------------------------------------------- harm

func hurt(n: float, why: String) -> void:
	if n <= 0.0 or _going != 0:
		return
	hull = maxf(0.0, hull - n)
	last_hurt = why
	hud.flash = 0.4
	_hurt = minf(1.0, _hurt + n * 0.08)
	_soft()

## Out of fuel or wrecked: hauled up to the lift, the cargo lost, a fee.
func tow(why: String) -> void:
	var fee := mini(arena.cash, 40 + int(arena.cash * 0.1))
	arena.cash -= fee
	cargo.clear()
	fuel = maxf(fuel, tank_max() * 0.3)
	hull = maxf(hull, hull_max() * 0.4)
	critters.stand_down()
	ship.place(_lift_spot())
	trip = 0.0
	_chain.clear()
	if why == "fuel":
		say("Out of fuel! The tow truck dragged you up. Cargo lost, $%d fee" % fee, 4.0)
	else:
		say("Wrecked! The salvage crew hauled you up. Cargo lost, $%d fee" % fee, 4.0)
	sound.play("mine_hit", Vector3.INF, 0.0, 0.5)
	shake(0.5)
	_dirty()

## Caught by a cop drone: the cargo and a fifth of the cash taken, towed up.
func busted() -> void:
	var fine := mini(arena.cash, maxi(50, int(arena.cash * 0.2)))
	arena.cash -= fine
	cargo.clear()
	critters.stand_down()
	ship.place(_lift_spot())
	trip = 0.0
	_chain.clear()
	say("BUSTED! The cops took your cargo and $%d, and towed you up" % fine, 4.5)
	sound.play("mine_siren", Vector3.INF, -2.0)
	_dirty()

## A blast at c (dynamite, a gas pocket): the rock in reach gone (not bedrock, nor the pads), the ore in it scooped up
## if it was dynamite (and there's room), anyone in it hurt, gas in it going off next.
func explode(c: Vector2, rad: float, dynamite: bool) -> void:
	var cc := MineGround.cell(c)
	var res: Dictionary = ground.sim.explode(cc.x + 0.5, cc.y + 0.5, rad * MineGround.C, 0.45)
	var counts: PackedInt32Array = res.counts
	for m in counts.size():
		if counts[m] > 0 and dynamite and m != MineTiles.FOOLS:
			_ore(m, counts[m], c)
	# gas just outside it goes off next
	if counts[MineTiles.GAS] > 0:
		var r := int((rad + 1.6) * MineGround.C)
		var g: PackedInt32Array = ground.sim.find(MineTiles.GAS, cc.x - r, cc.y - r, cc.x + r, cc.y + r, 1)
		if g.size() >= 2:
			_chain.append([0.18, MineGround.world(Vector2i(g[0], g[1]))])
	var d := c.distance_to(ship.p)
	if not dynamite and d < rad + 1.5:
		hurt(20.0 * (1.0 - d / (rad + 1.5)), "gas")
		ship.v += (ship.p - c).normalized() * 6.0
	critters.blast(c, rad + 0.5)
	worm.blast(c, rad)
	sound.play("mine_boom", Vector3.INF, 0.0 if not dynamite else -2.0)
	shake(0.7)
	_hitstop = maxf(_hitstop, 0.05)
	spark(c, Color8(255, 180, 80), 26)
	_boom_light.position = Vector3(c.x, c.y, 1.2)
	_boom_light.light_energy = 6.0
	_soft()

## A puff of dust at c
func _dust(c: Vector2) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 6
	p.lifetime = 0.7
	p.explosiveness = 0.9
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.3, 0)
	p.scale_amount_min = 0.18
	p.scale_amount_max = 0.4
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.48, 0.4, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	p.mesh = sm
	p.position = Vector3(c.x, c.y, 0.55)
	world.add_child(p)
	_sparks.append([p, 1.0])

## Lava open to the air near the ship (for the glow on what's round it): a few spots, spread out
func _lava_near() -> Array:
	var c := MineGround.cell(ship.p)
	var r := 14 * MineGround.C
	var f: PackedInt32Array = ground.sim.find(MineTiles.LAVA, c.x - r, c.y - r, c.x + r, c.y + r, 400)
	var out := []
	var i := 0
	while i < f.size() and out.size() < _lava_lights.size():
		var p := MineGround.world(Vector2i(f[i], f[i + 1]))
		var far := true
		for q in out:
			if (q as Vector2).distance_to(p) < 2.5:
				far = false
				break
		if far:
			out.append(p)
		i += 2
	return out

# ---------------------------------------------------------------- the launcher

## Right mouse (held) or F: a shot of what's picked (Q) toward the mouse
func _launcher(dt: float, menu_up: bool) -> void:
	_launch_t = maxf(0.0, _launch_t - dt)
	var mp := arena.get_viewport().get_mouse_position()
	var vr := arena.get_viewport().get_visible_rect()
	aiming = not menu_up and vr.has_point(mp) and auto == null
	var o := cam.project_ray_origin(mp)
	var n := cam.project_ray_normal(mp)
	if absf(n.z) > 0.0001:
		var t := -o.z / n.z
		aim = Vector2(o.x + n.x * t, o.y + n.y * t)
	if aiming and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _launch_t <= 0.0:
		shoot()

func launch_speed() -> float:
	return MineShop.k("launcher", int(upg.get("launcher", 0)))

## The shot's start and velocity toward the aim
func shot_start() -> Array:
	var from := ship.p + Vector2(0, 0.25)
	var dir := (aim - from).normalized() if aim.distance_to(from) > 0.05 else Vector2(ship.face, 0.3).normalized()
	return [from + dir * 0.5, dir * launch_speed()]

func shoot() -> void:
	if _launch_t > 0.0:
		return
	var wet := ammo_sel == "water"
	var cells := WATER_CELLS if wet else SHOT_CELLS
	_launch_t = WATER_EVERY if wet else SHOT_EVERY
	if int(ammo.get(ammo_sel, 0)) < cells:
		if wet:
			say("Out of water: hold R in a pool to suck some up", 1.5)
		else:
			say("Out of %s: drill some up" % String(AMMO_NAME[ammo_sel]).to_lower(), 1.2)
		return
	ammo[ammo_sel] = int(ammo[ammo_sel]) - cells
	var sv: Array = shot_start()
	var m := int(AMMO_MAT[ammo_sel])
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.14, 0.14) if wet else Vector3(0.22, 0.22, 0.22)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = MineTiles.shades(m)[4]
	if wet:
		mat.albedo_color = Color(0.45, 0.75, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.45, 0.8)
		mat.emission_energy_multiplier = 0.6
	mi.material_override = mat
	world.add_child(mi)
	var v: Vector2 = sv[1]
	if wet:
		v = v.rotated(randf_range(-0.05, 0.05)) * randf_range(0.95, 1.05)     # (a spray, not a rod)
	_shots.append({"n": mi, "p": sv[0], "v": v, "m": m})
	if wet:
		sound.loop("mine_spray", "mine_spray", null, -8.0, 1.0)
		_spray_t = 0.15
	else:
		sound.play("mine_door", Vector3.INF, -12.0, 2.2)

func _step_shots(dt: float) -> void:
	for i in range(_shots.size() - 1, -1, -1):
		var s: Dictionary = _shots[i]
		var hit := false
		for k in 4:
			s.v.y -= 12.0 * dt / 4.0
			var np: Vector2 = s.p + s.v * dt / 4.0
			if ground.solid_at(np) or ground.count(np, Vector2(0.06, 0.06), -2) > 0 or ground.count(np, Vector2(0.06, 0.06), -3) > 0 \
					or np.y < -MineGround.D or critters.shot_hit(np):
				hit = true
				break
			s.p = np
		(s.n as MeshInstance3D).position = Vector3(s.p.x, s.p.y, 0.5)
		if hit or s.p.y > 14.0:
			if hit:
				var c := MineGround.cell(s.p)
				if int(s.m) == MineTiles.WATER:
					ground.sim.deposit(c.x + 0.5, c.y + 0.5, 1.6, MineTiles.WATER, false)
					# on lava: steam, and the lava it touches goes to stone
					if ground.count(s.p, Vector2(0.5, 0.5), -4) > 0 and _steam_t <= 0.0:
						_steam_t = 0.35
						sound.play("mine_steam", Vector3.INF, -4.0, randf_range(0.9, 1.15))
						_puff(s.p)
						tip("lava")
				else:
					ground.sim.deposit(c.x + 0.5, c.y + 0.5, 2.6, int(s.m), int(s.m) == MineTiles.DIRT)
					sound.play("mine_crumble", Vector3.INF, -8.0, 1.4)
			s.n.queue_free()
			_shots.remove_at(i)

## R held: the hose out of its back sucking up the water round its nozzle (into the launcher's tank), drops flying
## up it, a gurgle.
func _suck(dt: float) -> void:
	_steam_t -= dt
	_spray_t -= dt
	if _spray_t <= 0.0 and sound.playing("mine_spray"):
		sound.stop("mine_spray")
	_water_hose = move_toward(_water_hose, 1.0 if sucking else 0.0, dt * 4.0)
	var got := 0
	var have := int(ammo.get("water", 0))
	if sucking and _water_hose >= 1.0 and have < AMMO_MAX:
		_suck_acc = minf(_suck_acc + SUCK_RATE * dt, 20.0)
		var want := mini(int(_suck_acc), AMMO_MAX - have)
		if want > 0:
			var nz := ship.nozzle_at()
			var c := MineGround.cell(nz)
			var r := 9          # (cells round the nozzle: a bit over a metre)
			var found: PackedInt32Array = ground.sim.find(MineTiles.WATER, c.x - r, c.y - r, c.x + r, c.y + r, want)
			# (and round the ship, when it's sat in it)
			if found.size() / 2 < want:
				var sc := MineGround.cell(ship.p)
				found.append_array(ground.sim.find(MineTiles.WATER, sc.x - 6, sc.y - 6, sc.x + 6, sc.y + 6, want - found.size() / 2))
			for k in range(0, found.size(), 2):
				if ground.sim.get_cell(found[k], found[k + 1]) != MineTiles.WATER:
					continue
				ground.sim.set_cell(found[k], found[k + 1], MineTiles.AIR)
				got += 1
				if _drops.size() < 40 and k % 6 == 0:
					_drop(MineGround.world(Vector2i(found[k], found[k + 1])))
			_suck_acc -= float(got)
			ammo["water"] = have + got
	if got > 0:
		sound.loop("mine_suck", "mine_suck", null, -7.0, 1.0)
		_suck_none_t = 0.0
	else:
		if sound.playing("mine_suck") and (not sucking or _suck_none_t > 0.2):
			sound.stop("mine_suck")
		if sucking and _water_hose >= 1.0:
			_suck_none_t += dt
			if _suck_none_t > 0.6 and have < AMMO_MAX:
				_suck_none_t = -2.0
				say("No water here: find a pool", 1.2)
			elif have >= AMMO_MAX and _suck_none_t > 0.3:
				_suck_none_t = -2.0
				say("The water tank's full", 1.2)
	# the drops flying up the hose
	var nzp := ship.nozzle_at()
	for i in range(_drops.size() - 1, -1, -1):
		var d: Dictionary = _drops[i]
		d.t += dt * 4.0
		var p: Vector2 = (d.from as Vector2).lerp(nzp, minf(1.0, d.t * d.t))
		(d.n as MeshInstance3D).position = Vector3(p.x, p.y, 0.5)
		if d.t >= 1.0:
			d.n.queue_free()
			_drops.remove_at(i)

func _drop(from: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.08, 0.08)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.5, 0.9)
	mat.emission_energy_multiplier = 0.8
	mi.material_override = mat
	mi.position = Vector3(from.x, from.y, 0.5)
	world.add_child(mi)
	_drops.append({"n": mi, "from": from, "t": 0.0})

## A puff of steam at c (water on lava)
func _puff(c: Vector2) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 26
	p.lifetime = 1.2
	p.explosiveness = 0.8
	p.direction = Vector3(0, 1, 0)
	p.spread = 45.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.9, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.14
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.96, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	bm.material = m
	p.mesh = bm
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.8))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = grad
	p.position = Vector3(c.x, c.y, 0.6)
	world.add_child(p)
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

## A burst of sparks at c.
func spark(c: Vector2, col: Color, n := 14) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = n
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -9, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	bm.material = m
	p.mesh = bm
	p.position = Vector3(c.x, c.y, 0.6)
	world.add_child(p)
	_sparks.append([p, 1.0])

func shake(k: float) -> void:
	_shake = maxf(_shake, k)

func say(text: String, secs := 2.0) -> void:
	if hud:
		hud.say(text, secs)

## A tip, once ever (and not over one still showing, unless it matters more)
func tip(id: String) -> void:
	if tips_done.has(id) or not TIPS.has(id) or hud == null:
		return
	if hud.tip_showing() and not id in ["fuel_low", "cops", "worm", "cargo_full"]:
		return
	tips_done[id] = true
	hud.tip(String(TIPS[id]))
	_soft()

## Paid without the till (a nugget into the ORE box: the box does its own clunk)
func pay_quiet(n: int) -> void:
	arena.cash += n
	stats.earned = int(stats.earned) + n
	_dirty()

## The ORE box has everything that was squirted in: the till, the takings
func unloaded(total: int) -> void:
	hud.pop("+$%d" % total, Color8(120, 255, 120))
	sound.play("mine_register", Vector3.INF, -3.0)
	say("Into the ORE box: $%d" % total, 2.0)
	tip("sold")
	_soft()

func pay(n: int) -> void:
	arena.cash += n
	stats.earned = int(stats.earned) + n
	hud.pop("+$%d" % n, Color8(120, 255, 120))
	sound.play("mine_register", Vector3.INF, -3.0)
	_dirty()

func _spend(n: int) -> bool:
	if n > arena.cash:
		say("Not enough cash", 1.2)
		return false
	arena.cash -= n
	hud.pop("-$%d" % n, Color8(255, 140, 120))
	sound.play("mine_register", Vector3.INF, -5.0, 0.85)
	_dirty()
	return true

func on_worm_dead() -> void:
	worm_dead = true
	_dirty()

# ---------------------------------------------------------------- the supplies

func use_item(id: String) -> void:
	if int(items.get(id, 0)) <= 0:
		say("No %s: buy some at the TRADER" % String(MineShop.ITEMS[id].name).to_lower(), 1.5)
		tip("items")
		return
	if ship.p.y > 0.0 and id != "repair":
		say("Not up here", 1.0)
		return
	items[id] = int(items[id]) - 1
	match id:
		"dynamite":
			explode(ship.p, 1.9, true)
			say("BOOM", 0.8)
		"repair":
			hull = minf(hull_max(), hull + hull_max() * 0.4)
			sound.play("mine_clink", Vector3.INF, -2.0, 0.6)
			say("Hull patched", 1.2)
		"teleport":
			spark(ship.p, Color8(120, 200, 255), 30)
			critters.stand_down()
			ship.place(_lift_spot())
			sound.play("mine_zap", Vector3.INF, -2.0)
			say("Beamed up top", 1.5)
	_dirty()

# ---------------------------------------------------------------- the buildings' menus

func _fuel_menu() -> void:
	var lp := MineShop.fuel_price(day)
	var need := tank_max() - fuel
	var full := int(ceil(need * lp))
	hud.open_menu("FUEL   ($%.2f a litre today)" % lp, [
		["Fill up: %.1f L for $%d" % [need, full], need > 0.05 and arena.cash > 0, func(): buy_fuel(need)],
		["5 litres: $%d" % int(ceil(minf(5.0, need) * lp)), need > 0.05 and arena.cash > 0, func(): buy_fuel(minf(5.0, need))],
		["Tank: %.1f of %.0f L" % [fuel, tank_max()], true, null],
	])

## Fuel bought (as much of l litres as the cash runs to)
func buy_fuel(l: float) -> void:
	var lp := MineShop.fuel_price(day)
	l = minf(l, tank_max() - fuel)
	var can := float(arena.cash) / lp
	l = minf(l, can)
	if l <= 0.01:
		say("Not enough cash", 1.2)
		return
	var c := maxi(1, int(ceil(l * lp)))
	if c > arena.cash:
		c = arena.cash
	arena.cash -= c
	fuel = minf(tank_max(), fuel + l)
	hud.pop("-$%d" % c, Color8(255, 140, 120))
	sound.play("mine_register", Vector3.INF, -5.0, 0.85)
	_dirty()
	_fuel_menu()

func _trader_menu() -> void:
	var rows := []
	rows.append(["Ore sells at the ORE box (by the fuel station): today's prices", true, null])
	var hot := MineShop.hot(day)
	var line := "Today:  "
	var k := 0
	for id in MineShop.CARGO_ORDER:
		if k >= 7:
			break
		var tr := MineShop.trend(id, day)
		line += "%s $%d%s   " % [MineShop.CARGO[id].name, MineShop.price(id, day), " ^" if tr > 0.05 else (" v" if tr < -0.05 else "")]
		k += 1
	rows.append([line, true, null])
	rows.append(["In demand today: %s (half as much again)" % MineShop.CARGO[hot].name, true, null])
	for id in MineShop.ITEM_ORDER:
		var it: Dictionary = MineShop.ITEMS[id]
		var have := int(items.get(id, 0))
		rows.append(["%s: $%d   (%s; you've %d of %d)" % [it.name, it.cost, it.desc, have, it.max], have < int(it.max) and arena.cash >= int(it.cost), func(): buy_item(id)])
	rows.append(["Fresh claim: brand new ground, $%d" % MineShop.CLAIM_COST, arena.cash >= MineShop.CLAIM_COST, func(): new_claim()])
	hud.open_menu("TRADER", rows)

func sell_all() -> void:
	var v := MineShop.value(cargo, day)
	if v <= 0:
		return
	var n := cargo_count()
	cargo.clear()
	pay(v)
	say("Sold %d for $%d" % [n, v], 2.0)
	tip("sold")
	_trader_menu()

func buy_item(id: String) -> void:
	var it: Dictionary = MineShop.ITEMS[id]
	if int(items.get(id, 0)) >= int(it.max):
		return
	if _spend(int(it.cost)):
		items[id] = int(items.get(id, 0)) + 1
		tip("items")
	_trader_menu()

func new_claim() -> void:
	if not hud.confirm("claim"):
		return
	if not _spend(MineShop.CLAIM_COST):
		return
	critters.clear()
	_chain.clear()
	ground.generate(randi() % 1000000 + 1, _flags())
	_ground_dirty = true
	ground.build_all()
	_feature_lights()
	worm_dead = false
	worm.spawn(false)
	ship.place(_lift_spot())
	hud.close_menu()
	say("Fresh ground staked out. New ore, new caves, a new worm.", 3.0)
	critters.on_enter()
	_dirty()

func _mechanic_menu() -> void:
	var rows := []
	var dmg := hull_max() - hull
	var rc := int(ceil(dmg * MineShop.REPAIR_PRICE))
	rows.append(["Repair the hull: %d hp for $%d" % [int(ceil(dmg)), rc], dmg > 0.5 and arena.cash > 0, func(): repair()])
	for t in MineShop.UPGRADE_ORDER:
		var u: Dictionary = MineShop.UPGRADES[t]
		var lv := int(upg[t])
		var c := MineShop.cost(t, lv)
		if c < 0:
			rows.append(["%s: %s (the best there is)" % [u.name, u.names[lv]], false, func(): pass])
		else:
			var kv := MineShop.k(t, lv + 1)
			var val := str(int(kv)) if is_equal_approx(kv, roundf(kv)) and t != "drill" else ("%.1f" % kv)
			rows.append(["%s: %s -> %s (%s%s): $%d" % [u.name, u.names[lv], u.names[lv + 1], val, u.unit, c], arena.cash >= c, func(): buy_upgrade(t)])
	hud.open_menu("MECHANIC", rows)

func repair() -> void:
	var dmg := hull_max() - hull
	var hp := minf(dmg, float(arena.cash) / MineShop.REPAIR_PRICE)
	if hp <= 0.0:
		say("Not enough cash", 1.2)
		return
	var c := maxi(1, int(ceil(hp * MineShop.REPAIR_PRICE)))
	c = mini(c, arena.cash)
	arena.cash -= c
	hull = minf(hull_max(), hull + hp)
	hud.pop("-$%d" % c, Color8(255, 140, 120))
	sound.play("mine_register", Vector3.INF, -5.0, 0.85)
	_dirty()
	_mechanic_menu()

func buy_upgrade(t: String) -> void:
	var lv := int(upg[t])
	var c := MineShop.cost(t, lv)
	if c < 0 or not _spend(c):
		return
	var old_tank := tank_max()
	var old_hull := hull_max()
	upg[t] = lv + 1
	if t == "tank":
		fuel += tank_max() - old_tank       # (the new tank comes full of what the extra holds)
	if t == "hull":
		hull += hull_max() - old_hull
	ship.build(upg)
	ship.place(ship.p)
	say("%s: %s" % [MineShop.UPGRADES[t].name, MineShop.UPGRADES[t].names[lv + 1]], 2.0)
	sound.play("mine_clink", Vector3.INF, 0.0, 0.7)
	_mechanic_menu()
