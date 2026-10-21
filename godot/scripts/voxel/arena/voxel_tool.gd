class_name VoxelTool
extends VoxelMelee
## The digging tools (the owner, 21 Oct, Stage 4: "Tools: shovel + pick for harder materials. Upgrade tiers: rusty
## shovel (digs poorly) -> good shovel -> silly golden shovel. Worms can be found while digging"), group 6. One script,
## two weapons (weapon_id "shovel" or "pick"):
## - the shovel, left click: a scoop out of the ground where you look (dirt, grass, clay; not stone). Rusty: small
##   scoops, slow, and one in four slips off with half a scoop; good (made at the tool bench): bigger, quicker; golden:
##   huge, very quick, and it even goes through stone. Right click: a scoop of dirt from your backpack put back (fill
##   holes in).
## - the pick, left click: a small bite out of anything but bedrock: stones, stone, the hard rock, gold ore.
## What comes up goes in your backpack (dirt, clay, stone, gold nuggets); now and then a worm wriggles out of the dirt
## (yours too). A swing where nothing gives: a clang ("too hard: the pick"). Only the game whose player swung digs
## (VoxelYard tells the other game); the other player's tool in your game just swings. Owned by the voxel session.

const REACH := 3.0              # metres from the eye (top-down: the chest) it reaches
const IMPACT := 0.16            # seconds into the swing it bites
const SWING_T := 0.5
## The shovel by tier: [scoop radius (m), the hardest it digs, seconds between scoops, name].
const SHOVEL := [[0.2, 2, 0.7, "Rusty shovel"], [0.32, 2, 0.4, "Good shovel"], [0.5, 3, 0.22, "Golden shovel"]]
const PICK := [0.21, 4, 0.55, "Pick"]
const BLADE := [Color8(142, 76, 40), Color8(176, 180, 188), Color8(242, 198, 64)]

var tier := 0                   # the shovel's (the local player's: arena.shovel_tier)
var _cd := 0.0
var _t := -1.0                  # seconds into a swing (-1: none)
var _filling := false
var _bit := false               # the swing has bitten
var _pivot: Node3D
var _blade_mat: StandardMaterial3D
var _hand_node: Node3D

func is_shovel() -> bool:
	return weapon_id == "shovel"

func stats() -> Array:
	return SHOVEL[clampi(tier, 0, 2)] if is_shovel() else PICK

func _build() -> void:
	_pivot = Node3D.new()
	view.add_child(_pivot)
	_pivot.position = Vector3(0.26, -0.34, -0.5)
	_blade_mat = StandardMaterial3D.new()
	_model(_pivot, 1.0)
	_pose(0.0)

func set_tier(t: int) -> void:
	tier = clampi(t, 0, 2)
	for c in _pivot.get_children():
		c.queue_free()
	_model(_pivot, 1.0)

func _paint(m: StandardMaterial3D) -> void:
	if not is_shovel():
		m.albedo_color = Color8(120, 122, 128)
		m.metallic = 0.7
		m.roughness = 0.4
		return
	m.albedo_color = BLADE[tier]
	m.metallic = [0.3, 0.85, 0.95][tier]
	m.roughness = [0.85, 0.3, 0.2][tier]
	m.emission_enabled = tier == 2
	m.emission = Color8(255, 200, 60)
	m.emission_energy_multiplier = 0.35

# the tool, its grip at parent's origin, its shaft along -z (forward), its working end at the far end
func _model(parent: Node3D, s: float) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color8(150, 104, 58)
	wood.roughness = 0.8
	_paint(_blade_mat)
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.016 * s
	sm.bottom_radius = 0.018 * s
	sm.height = 0.8 * s
	sm.radial_segments = 10
	shaft.mesh = sm
	shaft.material_override = wood
	shaft.rotation.x = PI * 0.5
	shaft.position = Vector3(0, 0, -0.3 * s)
	parent.add_child(shaft)
	if is_shovel():
		# a D grip at the near end, the blade at the far
		var grip := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.11, 0.025, 0.025) * s
		grip.mesh = gm
		grip.material_override = wood
		grip.position = Vector3(0, 0, 0.1 * s)
		parent.add_child(grip)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.012, 0.26) * s
		blade.mesh = bm
		blade.material_override = _blade_mat
		blade.position = Vector3(0, 0.02 * s, -0.8 * s)
		blade.rotation.x = 0.85             # (its face turned up to you: a scoop)
		parent.add_child(blade)
		var neck := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(0.05, 0.03, 0.08) * s
		neck.mesh = nm
		neck.material_override = _blade_mat
		neck.position = Vector3(0, 0, -0.67 * s)
		parent.add_child(neck)
		if tier == 0:
			# rust spots
			var rust := StandardMaterial3D.new()
			rust.albedo_color = Color8(96, 46, 24)
			rust.roughness = 1.0
			for k in 4:
				var sp := MeshInstance3D.new()
				var spm := BoxMesh.new()
				spm.size = Vector3(0.04, 0.014, 0.035) * s
				sp.mesh = spm
				sp.material_override = rust
				sp.position = Vector3((-0.07 + 0.045 * k) * s, 0.002 * s, (0.04 - 0.035 * (k % 3)) * s)
				blade.add_child(sp)
	else:
		# the pick's head across the far end: a point each way
		var head := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.05, 0.38, 0.05) * s
		head.mesh = hm
		head.material_override = _blade_mat
		head.position = Vector3(0, 0, -0.72 * s)
		parent.add_child(head)
		for e in [-1.0, 1.0]:
			var tip := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.03, 0.08, 0.03) * s
			tip.mesh = tm
			tip.material_override = _blade_mat
			tip.position = Vector3(0, e * 0.22 * s, -0.7 * s)
			tip.rotation.x = e * 0.4
			parent.add_child(tip)

# the view's pose k into a swing (0 at rest): the shovel thrusts in and scoops up; the pick swings up then down
func _pose(k: float) -> void:
	if is_shovel():
		var push := sin(clampf(k / 0.4, 0.0, 1.0) * PI * 0.5) * (1.0 - clampf((k - 0.5) / 0.5, 0.0, 1.0))
		var scoop := sin(clampf((k - 0.3) / 0.5, 0.0, 1.0) * PI)
		_pivot.position = Vector3(0.27 - 0.08 * push, -0.27 - 0.06 * push + 0.05 * scoop, -0.42 - 0.22 * push)
		_pivot.rotation = Vector3(-0.32 - 0.45 * push + 0.6 * scoop, 0.28 - 0.12 * push, 0.12)
	else:
		var up := sin(clampf(k / 0.3, 0.0, 1.0) * PI * 0.5) * (1.0 - clampf((k - 0.3) / 0.12, 0.0, 1.0))
		var down := clampf((k - 0.3) / 0.12, 0.0, 1.0) * (1.0 - clampf((k - 0.6) / 0.4, 0.0, 1.0))
		_pivot.position = Vector3(0.26, -0.3 + 0.08 * up, -0.5 + 0.05 * up)
		_pivot.rotation = Vector3(-0.2 + 1.0 * up - 0.9 * down, 0.1, 0.05)

func press(button: int) -> void:
	if _cd > 0.0 or _t >= 0.0:
		return
	if button == MOUSE_BUTTON_RIGHT and not is_shovel():
		return
	_filling = button == MOUSE_BUTTON_RIGHT
	_t = 0.0
	_bit = false
	_cd = float(stats()[2])
	sfx("swoosh_heavy", Vector3.INF if shooter == arena.me else shooter.player.global_position, -10.0, 1.3)

func step(dt: float) -> void:
	_cd = maxf(0.0, _cd - dt)
	if _t < 0.0:
		_pose(0.0)
		return
	_t += dt
	_pose(_t / SWING_T)
	if not _bit and _t >= IMPACT:
		_bit = true
		if shooter == arena.me:
			_bite()
	if _t >= SWING_T:
		_t = -1.0

func cooling() -> float:
	return _cd / float(stats()[2]) if _cd > 0.0 else 0.0

func bar_text() -> String:
	return ["rusty", "good", "gold"][tier] if is_shovel() else ""

# where the look meets the ground within reach: [point, normal] or []
func _aim_ground() -> Array:
	var yard = arena.yard
	if yard == null:
		return []
	var from := eye()
	var dir := look()
	if top_down():
		var ray: Array = shooter.mouse_ray()
		if ray.is_empty():
			return []
		from = ray[0]
		dir = ray[1]
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * (REACH + (14.0 if top_down() else 0.0)))
	q.exclude = shooter.exclude()
	var hit := arena.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return []
	var p: Vector3 = hit.position
	if not yard.ground.contains(p) or (top_down() and Vector2(p.x - shooter.player.global_position.x, p.z - shooter.player.global_position.z).length() > REACH):
		return []
	var col: Object = hit.collider
	if col == null or not (col as Node).get_parent() == yard.ground:
		return []
	return [p, hit.normal]

# the swing lands: dig (or fill) where it points; what comes up into the backpack
func _bite() -> void:
	var a := _aim_ground()
	if a.is_empty():
		return
	var p: Vector3 = a[0]
	var n: Vector3 = a[1]
	var st := stats()
	var r: float = st[0]
	var yard = arena.yard
	if _filling:
		var have: int = arena.inv.count("dirt")
		if have <= 0:
			arena.say("No dirt in your backpack to fill with", 1.5)
			return
		var k: int = yard.fill(p + n * r * 0.6, r, have)
		if k > 0:
			arena.inv.remove("dirt", k)
			sfx("dig_dirt", p, -2.0, 0.85)
			_dust(p, VoxelTerrain.COL[VoxelTerrain.DIRT])
		return
	if is_shovel() and tier == 0 and randf() < 0.25:
		r *= 0.6                  # (the rusty one slips: half a scoop)
		sfx("dig_scrape", p, -4.0)
	var got: Dictionary = yard.dig(p - n * r * 0.45, r, int(st[1]))
	var cells: Array = got.get("_cells", [])
	if cells.is_empty():
		sfx("dig_clang", p, -2.0)
		arena.say("Too hard for the %s: the pick breaks stone" % String(st[3]).to_lower() if is_shovel() else "Bedrock: nothing breaks it", 1.5)
		_dust(p, Color8(200, 200, 200))
		return
	var stone := int(got.get("stone", 0)) + int(got.get("gold", 0))
	sfx("dig_stone" if stone * 2 > cells.size() else "dig_dirt", p, -2.0, randf_range(0.9, 1.1))
	var most := VoxelTerrain.DIRT
	for id in got:
		if id != "_cells":
			arena.receive({"id": id, "n": int(got[id])}, "inv")
	if int(got.get("gold", 0)) > 0:
		sfx("gold_find", p, 0.0)
		arena.say("Gold! (%d nuggets in your backpack)" % arena.inv.count("gold"), 2.0)
		most = VoxelTerrain.GOLD
	elif stone > 0:
		most = VoxelTerrain.STONE
	elif int(got.get("clay", 0)) > int(got.get("dirt", 0)):
		most = VoxelTerrain.CLAY
	_dust(p, VoxelTerrain.COL[most])
	# worms in the dirt dug out
	var worms := 0
	for c: Vector3i in cells:
		if VoxelTerrain.worm_in(c.x, c.y, c.z):
			worms += 1
			var w := VoxelWorm.new()
			arena.add_child(w)
			w.start(yard.ground.centre_of(c.x, c.y, c.z) + Vector3.UP * 0.05, arena.player)
	if worms > 0:
		arena.receive({"id": "worm", "n": worms}, "inv")
		sfx("worm_find", p, -2.0)
		arena.say("A worm! (%d in your backpack)" % arena.inv.count("worm") if worms == 1 else "%d worms! (%d in your backpack)" % [worms, arena.inv.count("worm")], 2.0)

# a puff of bits flying up from the dig
func _dust(p: Vector3, col: Color) -> void:
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.amount = 24
	ps.lifetime = 0.7
	ps.explosiveness = 0.95
	ps.direction = Vector3.UP
	ps.spread = 50.0
	ps.initial_velocity_min = 1.2
	ps.initial_velocity_max = 2.6
	ps.gravity = Vector3(0, -9.8, 0)
	ps.scale_amount_min = 0.6
	ps.scale_amount_max = 1.2
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * VoxelTerrain.CELL * 0.35
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	bm.material = m
	ps.mesh = bm
	arena.add_child(ps)
	ps.global_position = p
	ps.emitting = true
	ps.finished.connect(ps.queue_free)

func hand_mesh() -> Node3D:
	var root := Node3D.new()
	var inner := Node3D.new()
	inner.rotation.y = PI          # (the model's shaft goes along -z; the hand wants +z away from it)
	root.add_child(inner)
	var m := StandardMaterial3D.new()
	_paint(m)
	var keep := _blade_mat
	_blade_mat = m
	_model(inner, 0.9)
	_blade_mat = keep
	return root

func hand_pose() -> String:
	return "spud"

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var y := r.position.y + r.size.y * 0.5
	ci.draw_rect(Rect2(r.position.x + r.size.x * 0.05, y - 2, r.size.x * 0.62, 4), Color(0.6, 0.42, 0.24, col.a))
	if is_shovel():
		var bc: Color = BLADE[tier]
		ci.draw_rect(Rect2(r.position.x + r.size.x * 0.66, y - r.size.y * 0.22, r.size.x * 0.28, r.size.y * 0.44), Color(bc.r, bc.g, bc.b, col.a))
	else:
		ci.draw_rect(Rect2(r.position.x + r.size.x * 0.66, y - r.size.y * 0.38, r.size.x * 0.08, r.size.y * 0.76), Color(0.6, 0.6, 0.64, col.a))
