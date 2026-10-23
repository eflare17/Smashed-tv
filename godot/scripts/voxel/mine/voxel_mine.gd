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
const FALL_HURT := 4.5          # hull a m/s landing over the safe speed
const BUMP_HURT := 2.0
const TRIP_UP := 1.0 / 10.0     # the trip coming on a second in a mushroom cave ...
const TRIP_DOWN := 1.0 / 18.0   # ... and wearing off
const SAVE_EVERY := 8.0

const TIPS := {
	"welcome": "Welcome to the mine! A/D drives (push into rock to drill through it), S drills down, W or Space flies you up. Fuel runs down all the time: keep an eye on it.",
	"first_ore": "Ore goes in your cargo bay. Fly back up and sell it at the TRADER (E at a building).",
	"fuel_low": "Fuel's low! Get up to the FUEL station before it runs out, or the tow truck drags you up and you lose your cargo.",
	"cargo_full": "Your cargo bay's full: what you dig now is lost. Go and sell, or get a bigger bay at the MECHANIC.",
	"sold": "Spend it at the MECHANIC: a faster drill, a bigger tank, more cargo, a tougher hull, brighter lights.",
	"hard": "Too hard for your drill: that boulder needs a better bit (the MECHANIC).",
	"deep": "It gets darker and the rock harder the deeper you go. Better lights help you see the ore.",
	"lava": "Lava! It runs into your tunnels and burns the hull. Left alone it cools to basalt.",
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
var upg := {"drill": 0, "tank": 0, "cargo": 0, "hull": 0, "lights": 0}
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
var _chain: Array = []          # gas pockets about to go off: [time, Vector2]
var _cave_lights: Array = []
var _lava_lights: Array[OmniLight3D] = []
var _bunker_lights: Array[OmniLight3D] = []
var _lava_t := 0.0
var _sparks: Array = []
var _was_lava := false
var _boom_light: OmniLight3D
var _cam_at := Vector3(25, 0, 12)

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
	cam.position = Vector3(25, 0, 12)
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
	ship.drilled.connect(_on_drilled)
	ship.bumped.connect(_on_bump)
	critters = MineCritters.new()
	world.add_child(critters)
	critters.setup(self, ground)
	worm = MineWorm.new()
	world.add_child(worm)
	worm.setup(self, ground)
	_buildings()
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
	if not _save.is_empty() and typeof(_save.get("ground")) == TYPE_DICTIONARY and ground.load_data(_save.ground):
		pass
	else:
		ground.generate(randi() % 1000000 + 1, _flags())
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
	ship.place(_lift_spot())
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
	sound.play("mine_door", Vector3.INF, -2.0, 0.9)
	sound.stop("mine_drill")
	sound.stop("mine_engine")
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

func _dirty() -> void:
	if arena.stash:
		arena.stash._dirty = true

func save_data() -> Dictionary:
	var d := {"v": 1, "upg": upg.duplicate(), "fuel": fuel, "hull": hull, "cargo": cargo.duplicate(), "items": items.duplicate(),
		"worm_dead": worm_dead, "tips": tips_done.keys(), "stats": stats.duplicate()}
	if _built:
		d["ground"] = ground.save_data()
	elif _save.has("ground"):
		d["ground"] = _save.ground
	return d

func load_data(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	if typeof(d.get("upg")) == TYPE_DICTIONARY:
		for k in upg:
			upg[k] = clampi(int(d.upg.get(k, 0)), 0, 3)
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
	_save = d
	if _built and typeof(d.get("ground")) == TYPE_DICTIONARY and ground.load_data(d.ground):
		critters.clear()
		ground.build_all()
		_feature_lights()
		worm.spawn(worm_dead)
		ship.build(upg)
		ship.place(_lift_spot())

# ---------------------------------------------------------------- each frame

func _process(dt: float) -> void:
	if not active:
		return
	_finish_going(dt)
	if not active:
		return
	var menu_up: bool = hud.menu_open() or (arena.settings_menu and arena.settings_menu.is_open()) or _going != 0
	var ix := 0.0
	var up := false
	var down := false
	if auto != null:
		ix = float(auto.get("x", 0.0))
		up = bool(auto.get("up", false))
		down = bool(auto.get("down", false))
	elif not menu_up:
		ix = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		up = Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_SPACE)
		down = Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	# the trip: the controls drift (more the longer you've been in there)
	drift = clampf(drift + randf_range(-1.0, 1.0) * dt * 3.0, -1.0, 1.0)
	var dk := trip * clampf(cave_t / 20.0, 0.25, 1.0)
	ix = clampf(ix + drift * dk * 0.9, -1.0, 1.0)
	ship.grav_k = lerpf(1.0, 0.4, trip)
	var was_drilling := ship.drilling
	ship.step(dt, ix, up, down, fuel > 0.0)
	if ship.refused != "" and _refuse_t <= 0.0:
		_refuse_t = 1.2
		if ship.refused == "too_hard":
			say("Nothing gets through that", 1.0)
		else:
			var lv := int(ship.refused.substr(4))
			say("Too hard: needs the %s drill" % String(MineShop.UPGRADES.drill.names[lv]), 1.5)
			tip("hard")
		sound.play("mine_hit", Vector3.INF, -10.0, 1.6)
	_refuse_t -= dt
	# fuel
	var use := FUEL_IDLE
	if ship.thrusting:
		use += FUEL_THRUST
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
	if fuel <= 0.0 and ship.p.y < -0.5 and not ship.drilling:
		tow("fuel")
	# the ground: lava, gas going off one after another
	ground.lava_step(dt)
	var st := MineGround.tile_of(ship.p)
	var in_lava := false
	for o in [Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(-0.3, 0.3), Vector2(0.3, 0.3)]:
		var tt := MineGround.tile_of(ship.p + o)
		if ground.at(tt.x, tt.y) == MineTiles.LAVA:
			in_lava = true
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
	var bgk := ground.bg_at(st.x, st.y)
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
	critters.check_bunker(st, false)
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
		if ground.changed > 0:
			ground.changed = 0
			_dirty()

func _sounds(dt: float, was_drilling: bool) -> void:
	if _going == -1:
		return
	var thrust := ship.thrusting
	sound.loop("mine_engine", "mine_engine", null, -6.0 if thrust else (-12.0 if ship.driving else -17.0), 1.25 if thrust else (1.0 if ship.driving else 0.8))
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
	env.ambient_light_energy = lerpf(lerpf(0.17, 0.04, deep), 0.8, sky)
	env.ambient_light_color = Color(0.7, 0.75, 0.85).lerp(Color(0.5, 0.45, 0.6), deep)
	env.background_color = Color8(120, 170, 220).lerp(Color(0, 0, 0), 1.0 - sky)
	var want := Vector3(clampf(ship.p.x, 10.5, MineGround.W - 10.5), ship.p.y + 0.6 + sky * 1.5, 12.0)
	if not cam_hold:
		_cam_at = _cam_at.lerp(want, minf(1.0, dt * 6.0)) if _cam_at.distance_to(want) < 12.0 else want
		_shake = maxf(0.0, _shake - dt * 1.8)
		cam.position = _cam_at + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.25
	_hurt = maxf(0.0, _hurt - dt * 2.0)
	screen_mat.set_shader_parameter("trip", trip)
	screen_mat.set_shader_parameter("dark", lerpf(0.15, 0.85, clampf(depth / 60.0, 0.0, 1.0)))
	screen_mat.set_shader_parameter("hurt", _hurt)
	# the lava's glow on what's round it (the nearest few)
	_lava_t -= dt
	if _lava_t <= 0.0:
		_lava_t = 0.4
		var near := ground.lava_near(ship.p, _lava_lights.size())
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

## Parked by a building up top: its prompt.
func _buildings_near() -> void:
	_near = ""
	if ship.grounded and ship.p.y > 0.0 and ship.p.y < 1.0:
		_near = MineGround.building_at(ship.p.x)
	var t := ""
	match _near:
		"lift": t = "E  ride the lift up to the yard"
		"fuel": t = "E  FUEL station"
		"trader": t = "E  TRADER: sell your cargo, buy supplies"
		"mechanic": t = "E  MECHANIC: upgrades and repairs"
	hud.prompt(t)

# ---------------------------------------------------------------- keys

func _unhandled_input(e: InputEvent) -> void:
	if not active or _going != 0:
		return
	if arena.settings_menu and arena.settings_menu.is_open():
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

# ---------------------------------------------------------------- what the drill brings up

func _on_drilled(x: int, r: int, t: int) -> void:
	var c := String(MineTiles.info(t).cargo)
	ground.set_tile(x, r, MineTiles.AIR)
	match t:
		MineTiles.GAS:
			tip("gas")
			explode(MineGround.centre(x, r), 2.2, false)
			return
		MineTiles.FOOLS:
			say("Fool's gold! It crumbled to dust", 1.8)
			sound.play("mine_crumble", Vector3.INF, -2.0)
			return
		MineTiles.CONCRETE, MineTiles.EVIDENCE:
			critters.check_bunker(Vector2i(x, r), true)
	if c != "":
		_take(c)

func _take(c: String) -> void:
	if cargo_count() >= cargo_cap():
		say("Cargo full! The %s fell out" % String(MineShop.CARGO[c].name).to_lower(), 1.5)
		sound.play("mine_crumble", Vector3.INF, -6.0, 1.3)
		tip("cargo_full")
		return
	cargo[c] = int(cargo.get(c, 0)) + 1
	sound.play("mine_clink", Vector3.INF, -3.0, 0.9 + MineShop.CARGO_ORDER.find(c) * 0.06)
	hud.pop("+ " + String(MineShop.CARGO[c].name), Color8(255, 230, 140))
	tip("first_ore")
	if cargo_count() >= cargo_cap():
		tip("cargo_full")
	_dirty()

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
	hud.flash = 0.4
	_hurt = minf(1.0, _hurt + n * 0.08)
	_dirty()

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
	say("BUSTED! The cops took your cargo and $%d, and towed you up" % fine, 4.5)
	sound.play("mine_siren", Vector3.INF, -2.0)
	_dirty()

## A blast at c (dynamite, a gas pocket): the rock in reach gone (not bedrock, nor the pads), the ore in it scooped up
## if it was dynamite (and there's room), anyone in it hurt, gas in it going off next.
func explode(c: Vector2, rad: float, dynamite: bool) -> void:
	var t0 := MineGround.tile_of(c)
	var ir := ceili(rad)
	for r in range(t0.y - ir, t0.y + ir + 1):
		for x in range(t0.x - ir, t0.x + ir + 1):
			if MineGround.centre(x, r).distance_to(c) > rad:
				continue
			var t := ground.at(x, r)
			if t == MineTiles.AIR or t == MineTiles.BEDROCK or t == MineTiles.PAD or t == MineTiles.LAVA or r < 0:
				continue
			if t == MineTiles.GAS:
				_chain.append([0.18, MineGround.centre(x, r)])
				ground.set_tile(x, r, MineTiles.AIR)
				continue
			var cg := String(MineTiles.info(t).cargo)
			ground.set_tile(x, r, MineTiles.AIR)
			if dynamite and cg != "" and t != MineTiles.FOOLS:
				_take(cg)
	var d := c.distance_to(ship.p)
	if not dynamite and d < rad + 1.5:
		hurt(32.0 * (1.0 - d / (rad + 1.5)), "gas")
		ship.v += (ship.p - c).normalized() * 6.0
	critters.blast(c, rad + 0.5)
	worm.blast(c, rad)
	sound.play("mine_boom", Vector3.INF, 0.0 if not dynamite else -2.0)
	shake(0.7)
	spark(c, Color8(255, 180, 80), 26)
	_boom_light.position = Vector3(c.x, c.y, 1.2)
	_boom_light.light_energy = 6.0
	_dirty()

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
	_dirty()

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
	var v := MineShop.value(cargo, day)
	rows.append(["Sell everything: $%d" % v, cargo_count() > 0, func(): sell_all()])
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
	ground.generate(randi() % 1000000 + 1, _flags())
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
			var val := ("%.1f" % kv) if t == "drill" else str(int(kv))
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
