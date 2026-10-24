class_name VoxelBarbecue
extends Node3D
## The barbecue (the owner, 24 Oct: "add a barbecue so you can cook the chicken carcass"): a gas barbecue on a steel
## stand in the back yard, against the south fence between the shredder and the water tank. E with a chicken carcass
## in your backpack puts it on the grill (three at a time; the burners light with a whoomp); it sizzles, smokes and
## browns, and after COOK_T it's done: E takes it off as a roast chicken (the same as one the flamethrower roasts:
## H eats it for health, the buyer pays more for it than a raw carcass). Left on past BURN_T it burns black: a burnt
## chicken, worth next to nothing (the shredder takes it).
##
## Co-op: the host's (like the shredder): a guest's put and take go to the host as requests ("put", "take"), the host
## answers with what they got ("give"); the grill goes to the guest every 2 s and on every change, and both games
## cook along meanwhile for the look. Saved with the rest. Owned by the voxel session.

const AT := Vector3(18.0, 0, 38.45)     # where it stands (its front to the north, the yard)
const SPOTS := 3                        # chickens on the grill at once
const COOK_T := 30.0                    # seconds on the grill till it's cooked ...
const BURN_T := 75.0                    # ... and till it's burnt
const BURNT_PRICE := 2                  # at the buyer's crate (a roast chicken: VoxelChickens.ROAST_PRICE)
const BURNT_POINTS := 350.0             # in the shredder
const GRILL_Y := 0.91                   # the grate's top
const SYNC_T := 2.0
## How it looks as it cooks: raw (plucked pink) -> golden -> browned -> burnt black (the carcass's colours times these).
const TINT_RAW := Color(1, 1, 1)
const TINT_COOKED := Color(0.86, 0.56, 0.3)
const TINT_BROWN := Color(0.55, 0.32, 0.16)
const TINT_BURNT := Color(0.13, 0.1, 0.08)

var arena: Node3D
var grill := []                 # per spot: seconds it's been on (-1: empty)
var _views := []                # per spot: the carcass on it (or null)
var _sync_t := 0.0
var _dirty := false
var _dirty_t := 0.0
var _own = null
var _was_role := ""
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D
var _smoke: CPUParticles3D
var _smoke_mat: StandardMaterial3D
var _lit := 0.0                 # the burners, 0 off .. 1 going
var _told := {}                 # spot -> what's been said of it ("cooked", "burnt")

func setup(arena_: Node3D) -> void:
	arena = arena_
	position = AT
	grill = []
	_views = []
	for k in SPOTS:
		grill.append(-1.0)
		_views.append(null)
	_build()

func _is_guest() -> bool:
	return arena.net != null and arena.net.role == "guest" and arena.net.linked

func _is_host() -> bool:
	return arena.net != null and arena.net.role == "host" and arena.net.linked

## In the yard by the barbecue, top-down (within r metres of it): "grill" or "".
static func near(p: Vector3, r := 1.4) -> String:
	return "grill" if Vector2(p.x - AT.x, p.z - AT.z).length() < r else ""

## Cooked (or past it), burnt, still raw: by seconds on.
static func state_of(t: float) -> String:
	if t < 0.0:
		return ""
	if t >= BURN_T:
		return "burnt"
	if t >= COOK_T:
		return "cooked"
	return "raw"

static func tint_of(t: float) -> Color:
	if t < COOK_T:
		return TINT_RAW.lerp(TINT_COOKED, clampf(t / COOK_T, 0.0, 1.0))
	var over := (t - COOK_T) / (BURN_T - COOK_T)
	if over < 0.6:
		return TINT_COOKED.lerp(TINT_BROWN, over / 0.6)
	return TINT_BROWN.lerp(TINT_BURNT, clampf((over - 0.6) / 0.4, 0.0, 1.0))

# ---------------------------------------------------------------- cooking

func _process(dt: float) -> void:
	var role: String = arena.net.role if arena.net and arena.net.linked else ""
	if role != _was_role:
		if _was_role == "guest" and _own != null:
			from_data(_own)
			_own = null
		if role == "host":
			_send_all()
		_was_role = role
	for k in SPOTS:
		var t0 := float(grill[k])
		if t0 < 0.0:
			continue
		var t1 := t0 + dt
		grill[k] = t1
		if not _is_guest():
			if t0 < COOK_T and t1 >= COOK_T:
				_ready_said(k, "cooked")
			elif t0 < BURN_T and t1 >= BURN_T:
				_ready_said(k, "burnt")
	if _is_host():
		_sync_t += dt
		if _dirty:
			_dirty_t += dt
		if _sync_t >= SYNC_T or _dirty_t >= 0.15:
			_sync_t = 0.0
			_dirty_t = 0.0
			_dirty = false
			_send_all()
	_show(dt)

# (the host's, or alone) a chicken done, or burnt: said to whoever's in the yard, the change sent
func _ready_said(k: int, what: String) -> void:
	_changed()
	var msg := "Chicken's roasted: E at the barbecue takes it off" if what == "cooked" else "The chicken on the barbecue's burnt black!"
	arena.sound.play("bbq_tongs" if what == "cooked" else "flamethrower_lob", global_position + Vector3(0, 1.0, 0), -4.0)
	if VoxelYard.in_yard(arena.player.global_position):
		arena.say(msg, 2.5)
	_msg(["said", msg])

# ---------------------------------------------------------------- what a player does (the arena calls these)

## What the look lands on: ["grill", distance], ["", INF] for nothing.
func pick(eye: Vector3, dir: Vector3, reach := 2.6) -> Array:
	var box := AABB(AT + Vector3(-0.75, 0.0, -0.36), Vector3(1.5, 1.45, 0.72))
	var hit = box.intersects_ray(eye, dir)
	if hit != null:
		var d := (hit as Vector3).distance_to(eye)
		if d <= reach:
			return ["grill", d]
	return ["", INF]

func _done() -> Array:
	var out := []
	for k in SPOTS:
		if float(grill[k]) >= COOK_T:
			out.append(k)
	return out

func _free() -> int:
	for k in SPOTS:
		if float(grill[k]) < 0.0:
			return k
	return -1

## What it says, looked at.
func line(_tag := "grill") -> String:
	var parts := []
	for k in SPOTS:
		var t := float(grill[k])
		match state_of(t):
			"raw":
				parts.append("cooking %d%%" % int(t / COOK_T * 100.0))
			"cooked":
				parts.append("roasted" + (" (burning soon!)" if t > BURN_T - 15.0 else ""))
			"burnt":
				parts.append("burnt")
	var s := "Barbecue: " + (", ".join(parts) if not parts.is_empty() else "empty")
	var done := _done()
	if not done.is_empty():
		var cooked := 0
		for k in done:
			if state_of(float(grill[k])) == "cooked":
				cooked += 1
		var burnt := done.size() - cooked
		var what := []
		if cooked > 0:
			what.append("%d roast chicken%s" % [cooked, "" if cooked == 1 else "s"])
		if burnt > 0:
			what.append("%d burnt one%s" % [burnt, "" if burnt == 1 else "s"])
		return s + "     E  take off " + " and ".join(what)
	var have: int = arena.inv.count("chicken_carcass")
	if have > 0 and _free() >= 0:
		return s + "     E  put a chicken carcass on (%d in your backpack)" % have
	if have > 0:
		return s + " (the grill's full)"
	if parts.is_empty():
		return s + ": kill a chicken out in the yard, pick up its carcass, cook it here"
	return s

func use(_tag := "grill") -> void:
	if not _done().is_empty():
		take()
	else:
		put()

## E: a chicken carcass out of this player's backpack onto the grill. Returns the spot, or -1.
func put() -> int:
	var k := _free()
	if arena.inv.count("chicken_carcass") < 1:
		arena.say("Nothing to cook: kill a chicken out in the yard and pick up its carcass (E)", 2.5)
		return -1
	if k < 0:
		arena.say("The grill's full: wait till they're cooked", 2.0)
		return -1
	var was_empty := _free_count() == SPOTS
	arena.inv.remove("chicken_carcass", 1)
	arena.stash._dirty = true
	grill[k] = 0.0
	_told.erase(k)
	arena.sound.play("bbq_light" if was_empty else "bbq_tongs", global_position + Vector3(0, 1.0, 0), -3.0)
	arena.say("On the barbecue: cooked in %d s (don't leave it too long)" % int(COOK_T), 2.5)
	if _is_guest():
		_msg(["put", k])
	else:
		_changed()
	return k

func _free_count() -> int:
	var n := 0
	for k in SPOTS:
		if float(grill[k]) < 0.0:
			n += 1
	return n

## E: everything cooked (or burnt) off the grill into this player's backpack. Returns how many.
func take() -> int:
	var done := _done()
	if done.is_empty():
		return 0
	arena.sound.play("bbq_tongs", global_position + Vector3(0, 1.0, 0), -3.0)
	var cooked := 0
	var burnt := 0
	for k in done:
		if state_of(float(grill[k])) == "burnt":
			burnt += 1
		else:
			cooked += 1
		grill[k] = -1.0
	var bits := []
	if cooked > 0:
		bits.append("+%d roast chicken%s: H eats one (+%d health), or sell it at the buyer ($%d)" % [cooked, "" if cooked == 1 else "s", int(VoxelChickens.ROAST_HP), VoxelChickens.ROAST_PRICE])
	if burnt > 0:
		bits.append("+%d burnt chicken%s (left on too long)" % [burnt, "" if burnt == 1 else "s"])
	arena.say("; ".join(bits), 3.0)
	if _is_guest():
		_msg(["take", done])
		return done.size()
	if cooked > 0:
		arena.receive({"id": "roast_chicken", "n": cooked}, "inv")
	if burnt > 0:
		arena.receive({"id": "burnt_chicken", "n": burnt}, "inv")
	_msg(["said", "Your mate took the chicken off the barbecue"])
	_changed()
	return done.size()

## Items for VoxelItems: the burnt chicken (a done one is VoxelChickens' roast chicken).
static func items() -> Dictionary:
	return {
		"burnt_chicken": {"name": "Burnt chicken", "col": Color8(36, 28, 24), "stack": 20,
			"desc": "Left on the barbecue too long. The buyer gives $%d; the shredder takes it." % BURNT_PRICE},
	}

# ---------------------------------------------------------------- co-op

func _msg(m: Array) -> void:
	if arena.net and arena.net.linked:
		arena.net.send_barbecue(m)

func _changed() -> void:
	arena.stash._dirty = true
	_dirty = true

func _send_all() -> void:
	_msg(["all", to_data()])

func send_all() -> void:
	if _is_host():
		_send_all()

func on_net(m: Array) -> void:
	var host := _is_host()
	match String(m[0]):
		"all":
			if _is_guest():
				if _own == null:
					_own = to_data()
				from_data(m[1])
		"put":
			if host:
				var k := int(m[1])
				if k < 0 or k >= SPOTS or float(grill[k]) >= 0.0:
					k = _free()
				if k < 0:
					_msg(["give", {"id": "chicken_carcass", "n": 1}])
					_msg(["said", "The grill's full: your carcass is back in your backpack"])
				else:
					grill[k] = 0.0
					_changed()
		"take":
			if host and typeof(m[1]) == TYPE_ARRAY:
				var cooked := 0
				var burnt := 0
				for kk in m[1]:
					var k2 := int(kk)
					if k2 < 0 or k2 >= SPOTS:
						continue
					match state_of(float(grill[k2])):
						"cooked":
							cooked += 1
						"burnt":
							burnt += 1
						_:
							continue
					grill[k2] = -1.0
				if cooked > 0:
					_msg(["give", {"id": "roast_chicken", "n": cooked}])
				if burnt > 0:
					_msg(["give", {"id": "burnt_chicken", "n": burnt}])
				if cooked + burnt > 0:
					arena.say("Your mate took the chicken off the barbecue", 2.0)
				_changed()
		"said":
			arena.say(String(m[1]), 2.5)
		"give":
			var g: Dictionary = m[1]
			if VoxelItems.has(String(g.get("id", ""))) and int(g.get("n", 0)) > 0:
				arena.receive({"id": String(g.id), "n": int(g.n)}, "inv")

# ---------------------------------------------------------------- saving

func to_data() -> Dictionary:
	return {"grill": grill.duplicate()}

func from_data(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	var g = d.get("grill", [])
	for k in SPOTS:
		var t := -1.0
		if typeof(g) == TYPE_ARRAY and k < g.size():
			t = clampf(float(g[k]), -1.0, BURN_T + 600.0)
		grill[k] = t if t >= 0.0 else -1.0

func save_data() -> Dictionary:
	return _own if _own != null else to_data()

# ---------------------------------------------------------------- showing it

func _show(dt: float) -> void:
	var on := _free_count() < SPOTS
	var burning := false
	for k in SPOTS:
		var t := float(grill[k])
		var v: Node3D = _views[k]
		if t < 0.0:
			if v != null:
				v.queue_free()
				_views[k] = null
			continue
		if t >= BURN_T - 10.0:
			burning = true
		if v == null:
			v = VoxelChicken.carcass(k % VoxelChicken.COATS.size(), false, k, false, true)
			v.scale = Vector3.ONE * 0.62
			v.position = Vector3(0.3 - k * 0.3 - 0.08, GRILL_Y - 0.01, 0.02)      # (the first on the left, seen from the yard)
			v.rotation.y = 0.15 * (k - 1)
			add_child(v)
			_views[k] = v
		var mat: StandardMaterial3D = v.get_meta("mat")
		mat.albedo_color = tint_of(t)
	# the burners, the light under the grate, the smoke, the sizzle
	_lit = move_toward(_lit, 1.0 if on else 0.0, dt * 2.0)
	var fl := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.023) * sin(Time.get_ticks_msec() * 0.011)
	_glow_mat.emission_energy_multiplier = 3.5 * _lit * fl
	_glow_mat.albedo_color = Color8(60, 30, 20).lerp(Color8(255, 120, 30), _lit)
	_light.light_energy = 1.6 * _lit * fl
	_light.visible = _lit > 0.02
	_smoke.emitting = on
	_smoke_mat.albedo_color = Color(0.15, 0.13, 0.12, 0.55) if burning else Color(0.8, 0.8, 0.8, 0.35)
	if on:
		arena.sound.loop("bbq", "sizzle", self, -10.0 if not burning else -6.0, 1.0)
	elif arena.sound.playing("bbq"):
		arena.sound.stop("bbq")

# ---------------------------------------------------------------- building it

func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _box(size: Vector3, at: Vector3, m: Material, parent: Node3D = self, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func _cyl(r: float, h: float, at: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = m
	mi.position = at
	mi.rotation = rot
	add_child(mi)
	return mi

func _build() -> void:
	var enamel := _mat(Color8(30, 30, 34), 0.45, 0.4)
	var steel := _mat(Color8(176, 180, 186), 0.3, 0.85)
	var iron := _mat(Color8(46, 44, 42), 0.6, 0.6)
	var red := _mat(Color8(176, 36, 32), 0.45, 0.2)
	var wood := _mat(Color8(150, 104, 60), 0.85)
	var black := _mat(Color8(18, 18, 20), 0.7)
	# the stand: four legs, a shelf, the gas bottle on it
	for lx in [-0.46, 0.46]:
		for lz in [-0.22, 0.22]:
			_box(Vector3(0.04, 0.64, 0.04), Vector3(lx, 0.32, lz), steel)
	_box(Vector3(0.96, 0.03, 0.48), Vector3(0, 0.18, 0), steel)
	_cyl(0.13, 0.42, Vector3(0.24, 0.42, 0.02), red)
	_cyl(0.05, 0.06, Vector3(0.24, 0.66, 0.02), steel)
	_box(Vector3(0.22, 0.02, 0.02), Vector3(0.0, 0.66, 0.02), black, self, Vector3(0, 0, -0.5))   # (the hose up)
	# the firebox, the control panel and its knobs, the burners glowing under the grate
	_box(Vector3(1.0, 0.26, 0.56), Vector3(0, 0.77, 0), enamel)
	_box(Vector3(1.0, 0.12, 0.03), Vector3(0, 0.72, -0.29), steel)
	for i in 3:
		_cyl(0.025, 0.03, Vector3(-0.3 + i * 0.3, 0.72, -0.315), black, Vector3(PI * 0.5, 0, 0))
	_glow_mat = _mat(Color8(60, 30, 20), 0.9)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color8(255, 110, 30)
	_glow_mat.emission_energy_multiplier = 0.0
	for i in 3:
		_box(Vector3(0.82, 0.015, 0.06), Vector3(0, 0.86, -0.15 + i * 0.15), _glow_mat)
	# the grate: bars side to side
	for i in 10:
		_box(Vector3(0.96, 0.014, 0.014), Vector3(0, GRILL_Y - 0.007, -0.245 + i * 0.0545), iron)
	_box(Vector3(0.014, 0.014, 0.52), Vector3(-0.47, GRILL_Y - 0.007, 0), iron)
	_box(Vector3(0.014, 0.014, 0.52), Vector3(0.47, GRILL_Y - 0.007, 0), iron)
	# the hood, open, leaning back; its thermometer
	_box(Vector3(1.0, 0.5, 0.03), Vector3(0, 1.15, 0.33), enamel, self, Vector3(-0.22, 0, 0))
	_box(Vector3(1.0, 0.03, 0.18), Vector3(0, 1.41, 0.37), enamel, self, Vector3(-0.22, 0, 0))
	_box(Vector3(0.6, 0.03, 0.03), Vector3(0, 1.22, 0.29), steel, self, Vector3(-0.22, 0, 0))     # (its handle)
	_cyl(0.04, 0.02, Vector3(0, 1.05, 0.29), steel, Vector3(PI * 0.5 - 0.22, 0, 0))
	# a side table with the tongs on it
	_box(Vector3(0.34, 0.03, 0.5), Vector3(0.68, GRILL_Y - 0.03, 0), wood)
	_box(Vector3(0.03, 0.03, 0.5), Vector3(0.53, GRILL_Y - 0.06, 0), steel)
	_box(Vector3(0.025, 0.012, 0.32), Vector3(0.66, GRILL_Y - 0.005, -0.02), steel, self, Vector3(0, 0.08, 0))
	_box(Vector3(0.025, 0.012, 0.32), Vector3(0.7, GRILL_Y - 0.005, -0.02), steel, self, Vector3(0, -0.06, 0))
	# solid: you bump into it
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.4, 1.0, 0.6)
	cs.shape = sh
	cs.position = Vector3(0.1, 0.5, 0)
	body.add_child(cs)
	# the light off the burners, the smoke rising
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 1.0, 0)
	_light.light_color = Color8(255, 150, 70)
	_light.omni_range = 2.2
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	_smoke = CPUParticles3D.new()
	_smoke.position = Vector3(0, GRILL_Y + 0.1, 0)
	_smoke.amount = 28
	_smoke.lifetime = 2.6
	_smoke.emitting = false
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_smoke.emission_box_extents = Vector3(0.4, 0.02, 0.2)
	_smoke.direction = Vector3(0, 1, 0)
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 0.25
	_smoke.initial_velocity_max = 0.5
	_smoke.gravity = Vector3(0.05, 0.25, 0)
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.2))
	_smoke.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.8))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	_smoke.color_ramp = grad
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	sm.radial_segments = 8
	sm.rings = 4
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.albedo_color = Color(0.8, 0.8, 0.8, 0.35)
	sm.material = _smoke_mat
	_smoke.mesh = sm
	add_child(_smoke)
	# the sign
	var l := Label3D.new()
	l.text = "BBQ"
	l.font_size = 40
	l.pixel_size = 0.004
	l.outline_size = 8
	l.modulate = Color8(255, 210, 140)
	l.position = Vector3(0, 1.7, 0.3)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
