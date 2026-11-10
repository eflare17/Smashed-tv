class_name DigSite
extends Node3D
## The Dig Site (the owner, 8 Nov: "a new 3D voxel digging/mining location ... reached via the in-game phone"): a
## building site off past the arena (3 km east of it, in its world, under its sky, like the gun range is 3 km west),
## on the phone's Travel. You dig it, tunnel it and drive machines on it; with a mate, you both go (the host's Dig Site:
## its ground, its machines). The arena waits while you're here (VoxelArena.elsewhere).
##
## Stage 1: the site itself, travel there and back, together in co-op. Stage 2: the voxel ground (DsTerrain). The tools, the dirt, the machines,
## the cave-ins and the rest come in later stages (docs/digsite_notes.md). Owned by the voxel session.

const AT := Vector3(3000.0, 0.0, 0.0)     # the site's middle at ground level
const SIZE := 64.0                        # metres across (x and z)
const SPAWN := Vector3(4.0, 0.05, 36.0)   # where you arrive: at the gate by the site office, looking in across the site
const SEED := 20261108                    # the ground's (stage 12 keeps a site's own)

var arena: Node3D                         # VoxelArena
var active := false
var built := false
var _home_at := Vector3.ZERO
var _home_yaw := 0.0
var _home_pitch := 0.0
var _was_frozen := false
var _debris_bound := INF
var _help_text := ""
var _hud: Label
var terrain: DsTerrain                    # the voxel ground (stage 2)
var tools: DsTools                        # the hand tools' digging and tiers (stage 3)
var net: DsNet                            # co-op: the host's ground, the guest's actions (stage 5)
var machines: DsMachines                  # the Dingo and the rest (stage 6 on)
var caves: DsCaves                        # cave-ins shown and heard (stage 7)
var supports: DsSupports                  # props and concrete supports, and the weight on them (stage 8)
var blasts: DsBlasts                      # dynamite (stage 9)
var lamp: SpotLight3D                     # the hard hat's lamp, on under a roof (stage 7)
var look: DsLook                            # the site's sky, sun, toon shading and ink
var clods: DsClods                          # the lumps on the loose dirt, fixed in place, riding the gliding surface
var near_office := false
const OFFICE_WINDOW := Vector3(-6.6, 1.1, 36.0)   # the site office's counter (its side facing the gate)

func setup(a: Node3D) -> void:
	arena = a
	name = "DigSite"
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.offset_left = -420
	_hud.offset_right = 420
	_hud.offset_top = 64
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_theme_font_size_override("font_size", 22)
	_hud.add_theme_color_override("font_color", Color("#ffd27a"))
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 8)
	_hud.visible = false
	a._hud_layer.add_child(_hud)
	net = DsNet.new()
	add_child(net)
	net.setup(self)
	tools = DsTools.new(self)
	if a.get("stash") != null:
		tools.load_data(a.stash.ds_tools)

## The site's place in the world for a point given from its middle
static func world(local: Vector3) -> Vector3:
	return AT + local

## Whether a world point is on the site
static func on_site(p: Vector3) -> bool:
	return absf(p.x - AT.x) < SIZE * 0.5 + 12.0 and absf(p.z - AT.z) < SIZE * 0.5 + 12.0   # (the gate and the office too)

# ---------------------------------------------------------------- the site

func _build() -> void:
	built = true
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var grass := _mat(Color(0.29, 0.50, 0.18))
	var fence := _mat(Color("#ff7a1a"))
	var hut := _mat(Color8(214, 218, 222))
	var roof := _mat(Color8(70, 86, 110))
	# the voxel ground in the middle (stage 2), the field round it (four slabs: none under the ground)
	look = DsLook.new()
	add_child(look)
	look.setup(self)
	terrain = DsTerrain.new()
	add_child(terrain)
	terrain.setup(self, AT, SEED)
	clods = DsClods.new()
	add_child(clods)
	clods.setup(self)
	terrain.hook(net)
	tools.hook(net)
	machines = DsMachines.new()
	add_child(machines)
	machines.setup(self)
	machines.make()
	caves = DsCaves.new()
	add_child(caves)
	caves.setup(self)
	supports = DsSupports.new()
	add_child(supports)
	supports.setup(self)
	blasts = DsBlasts.new()
	add_child(blasts)
	blasts.setup(self)
	lamp = SpotLight3D.new()
	lamp.spot_range = 14.0
	lamp.spot_angle = 32.0
	lamp.light_energy = 2.2
	lamp.light_color = Color(1.0, 0.95, 0.82)
	lamp.visible = false
	arena.cam.add_child(lamp)
	net.register_event("drive", func(a: Array): machines.on_event("drive", a))
	net.register_event("off", func(a: Array): machines.on_event("off", a))
	var f := SIZE + 40.0
	var band := (f - SIZE) * 0.5
	for sgn in [-1.0, 1.0]:
		_box(body, Vector3(f, 1.0, band), Vector3(0, -0.5, sgn * (SIZE * 0.5 + band * 0.5)), grass)
		_box(body, Vector3(band, 1.0, SIZE), Vector3(sgn * (SIZE * 0.5 + band * 0.5), -0.5, 0), grass)
	# the paddock out to the horizon, and pines round the site (none across the gate)
	# (four strips round the grass bands, not one sheet under everything: under the site it showed through any hole
	# over a metre deep as a green floor)
	var reach := 1200.0
	var strip := (reach - f) * 0.5
	for side in [[Vector2(reach, strip), Vector3(0, 0, 1)], [Vector2(reach, strip), Vector3(0, 0, -1)],
			[Vector2(strip, f), Vector3(1, 0, 0)], [Vector2(strip, f), Vector3(-1, 0, 0)]]:
		var far := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = side[0]
		far.mesh = pm
		far.material_override = _mat(Color(0.29, 0.50, 0.18))
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far.position = AT + Vector3(0, -1.02, 0) + (side[1] as Vector3) * (f * 0.5 + strip * 0.5)
		add_child(far)
	# (10 Nov, against the digger game's picture from the same camera: its trees stand tall and close, inked, all round,
	# with a plainer treeline behind so the horizon's never bare; ours were 46 small ones far off, a bare green
	# band behind them. So: a ring of big ones just outside the fence, more scattered behind, and its far treeline)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED * 7 + 3
	var half := SIZE * 0.5 + 1.0
	var near := [DsKit.new(), DsKit.new(), DsKit.new(), DsKit.new()]     # (a mesh a quarter: what's behind you isn't drawn)
	var spots: Array[Vector2] = []
	var tries := 0
	while spots.size() < 96 and tries < 4000:
		tries += 1
		var ang := rng.randf() * TAU
		# (a third of them in the first few metres past the fence, the rest out to 40 m)
		var r := half + (rng.randf_range(2.5, 8.0) if spots.size() < 34 else rng.randf_range(8.0, 40.0))
		var at := Vector2(cos(ang) * r, sin(ang) * r) * (1.0 / maxf(absf(cos(ang)), absf(sin(ang))) if spots.size() < 34 else 1.0)
		if at.y > SIZE * 0.5 and absf(at.x) < 17.0:
			continue                              # (the gate and the office stay clear)
		var ok := true
		for o in spots:
			if o.distance_to(at) < 3.2:
				ok = false
				break
		if not ok:
			continue
		spots.append(at)
		var q := (0 if at.x < 0.0 else 1) + (0 if at.y < 0.0 else 2)
		DsProps.pine(near[q], Vector3(at.x, 0.0, at.y), rng.randf_range(7.5, 13.5), rng)
	for kit: DsKit in near:
		var trees := MeshInstance3D.new()
		trees.mesh = kit.mesh()
		trees.material_override = DsLook.prop_mat()
		trees.position = AT
		add_child(trees)
	var far_kit := DsKit.new()
	for i in 170:
		var ang := rng.randf() * TAU
		var d := half + rng.randf_range(42.0, 150.0)
		DsProps.pine(far_kit, Vector3(cos(ang) * d, 0.0, sin(ang) * d), rng.randf_range(8.0, 15.0), rng, 2, 6)
	var treeline := MeshInstance3D.new()
	treeline.mesh = far_kit.mesh()
	treeline.material_override = DsLook.prop_mat()
	treeline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	treeline.position = AT
	add_child(treeline)
	# the site fence, the digger game's: cream posts and a strip of orange tape round the dirt, a gap at the front
	# (ours was see-through orange mesh panels: over the grass they read as a muddy olive wall)
	var post := _mat(Color("#efe8d8"))
	var n := int(round(2.0 * half / 6.1))
	for side in 4:
		for i in n + 1:
			var t := -half + i * (2.0 * half / float(n))
			var at := Vector3(t, 0.65, -half) if side == 0 else (Vector3(t, 0.65, half) if side == 1 else (Vector3(-half, 0.65, t) if side == 2 else Vector3(half, 0.65, t)))
			if side == 1 and absf(t) < 5.0:
				continue                          # (the way in)
			_box(body, Vector3(0.14, 1.3, 0.14), at, post)
		var len := 2.0 * half
		if side == 1:
			for sg in [-1.0, 1.0]:
				_box(null, Vector3(half - 5.0, 0.09, 0.03), Vector3(sg * (5.0 + (half - 5.0) * 0.5), 1.12, half), fence)
			for sg in [-1.0, 1.0]:
				_box(body, Vector3(0.14, 1.3, 0.14), Vector3(sg * 5.0, 0.65, half), post)      # (the gateposts)
		elif side == 0:
			_box(null, Vector3(len, 0.09, 0.03), Vector3(0, 1.12, -half), fence)
		else:
			_box(null, Vector3(0.03, 0.09, len), Vector3(half if side == 3 else -half, 1.12, 0), fence)
	# the site office: a portable hut by the gate, its sign
	_box(body, Vector3(6.0, 2.6, 2.6), Vector3(-10.0, 1.3, half + 3.0), hut)
	_box(null, Vector3(6.3, 0.15, 2.9), Vector3(-10.0, 2.68, half + 3.0), roof)
	# its counter: a window on the side facing the gate, a shelf under it, a sign over it
	var counter := _mat(Color8(150, 104, 58))
	_box(body, Vector3(0.5, 0.08, 1.6), OFFICE_WINDOW + Vector3(0.25, -0.05, 0), counter)
	_box(null, Vector3(0.04, 0.8, 1.4), OFFICE_WINDOW + Vector3(-0.38, 0.45, 0), _mat(Color8(40, 50, 60)))
	var tl := Label3D.new()
	tl.text = "SITE OFFICE\npicks & hammers"
	tl.font_size = 40
	tl.pixel_size = 0.008
	tl.outline_size = 8
	tl.modulate = Color("#ffd27a")
	tl.position = AT + OFFICE_WINDOW + Vector3(-0.35, 1.25, 0)
	tl.rotation.y = PI * 0.5
	add_child(tl)
	var sign := Label3D.new()
	sign.text = "DIG SITE"
	sign.font_size = 120
	sign.pixel_size = 0.01
	sign.outline_size = 18
	sign.modulate = Color("#ffd27a")
	sign.double_sided = false                 # (not mirrored from inside the site)
	sign.position = AT + Vector3(0.0, 3.2, half + 0.2)
	add_child(sign)
	var sub := Label3D.new()
	sub.text = "Hard hats on. Dig safe."
	sub.font_size = 48
	sub.pixel_size = 0.008
	sub.outline_size = 10
	sub.double_sided = false
	sub.position = AT + Vector3(0.0, 2.4, half + 0.2)
	add_child(sub)
	_props(body, half)

## What stands about outside the gate (the digger game's site has a barrow, a sand heap, a ute; ours was bare but
## for its machines): all past the fence, off the ground that's dug, so nothing's left standing on air
func _props(body: StaticBody3D, half: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var z0 := half
	# a ute parked along the fence
	var ute := DsKit.new()
	DsProps.ute_body(ute)
	var un := _prop(ute, Vector3(10.5, 0.0, z0 + 4.6), PI)
	var wk := DsKit.new()
	DsProps.wheel(wk, 0.26)
	var tyre := wk.mesh()
	for sx in [-1.55, 1.55]:
		for sz in [-0.8, 0.8]:
			var w := MeshInstance3D.new()
			w.mesh = tyre
			w.material_override = DsLook.prop_mat()
			w.position = Vector3(sx, 0.38, sz)
			w.basis = Basis.IDENTITY.scaled(Vector3(0.38, 0.38, 1.0))
			un.add_child(w)
	_solid(body, Vector3(4.9, 1.9, 1.8), Vector3(10.5, 0.95, z0 + 4.6))
	# a barrow by the office, a heap of sand and one of gravel, drums, a pallet of bags
	var bn := Node3D.new()
	bn.transform = Transform3D(Basis(Vector3.UP, 2.4), AT + Vector3(-5.2, 0.2, z0 + 2.6))
	add_child(bn)
	var bt := MeshInstance3D.new()
	var bk2 := DsKit.new()
	DsProps.barrow(bk2, Vector3(0.78, 0.2, 0.0))
	bt.mesh = bk2.mesh()
	bt.material_override = DsLook.prop_mat()
	bn.add_child(bt)
	var bw := MeshInstance3D.new()
	var bwk := DsKit.new()
	DsProps.wheel(bwk, 0.09)
	bw.mesh = bwk.mesh()
	bw.material_override = DsLook.prop_mat()
	bw.basis = Basis.IDENTITY.scaled(Vector3(0.2, 0.2, 1.0))
	bn.add_child(bw)
	var kit := DsKit.new()
	var sand := DsProps.c("#e3d2a0")
	var sand_dark := DsProps.c("#cdb986")
	kit.cone(Vector3(14.6, 0.0, z0 + 4.2), Vector3(14.7, 1.15, z0 + 4.3), 1.9, 0.2, 9, sand, 0.16, rng)
	kit.cone(Vector3(15.6, 0.0, z0 + 3.2), Vector3(15.6, 0.6, z0 + 3.2), 1.1, 0.15, 8, sand_dark, 0.16, rng)
	var gravel := DsProps.c("#9a9a94")
	kit.cone(Vector3(14.4, 0.0, z0 + 7.6), Vector3(14.4, 0.95, z0 + 7.6), 1.6, 0.2, 9, gravel, 0.16, rng)
	for d: Array in [[Vector3(-15.0, 0.0, z0 + 2.0), "#2d6fb3"], [Vector3(-15.7, 0.0, z0 + 2.3), "#c9402c"], [Vector3(-15.2, 0.0, z0 + 2.9), "#2d6fb3"]]:
		var at: Vector3 = d[0]
		kit.cone(at, at + Vector3(0, 0.88, 0), 0.29, 0.29, 10, DsProps.c(d[1]))
		kit.cone(at + Vector3(0, 0.3, 0), at + Vector3(0, 0.34, 0), 0.305, 0.305, 10, DsProps.CHARCOAL)
		kit.cone(at + Vector3(0, 0.58, 0), at + Vector3(0, 0.62, 0), 0.305, 0.305, 10, DsProps.CHARCOAL)
	_solid(body, Vector3(1.4, 0.9, 1.6), Vector3(-15.3, 0.45, z0 + 2.4))
	# (a pallet, two layers of cement bags on it)
	var pal := Vector3(-3.6, 0.0, z0 + 4.4)
	kit.box(pal + Vector3(0, 0.07, 0), Vector3(1.2, 0.14, 1.0), DsProps.c("#b88a55"))
	for layer in 2:
		for k in 4:
			var o := Vector3(-0.3 + 0.6 * (k % 2), 0.24 + layer * 0.2, -0.24 + 0.48 * (k / 2))
			kit.box(pal + o, Vector3(0.56, 0.18, 0.44), DsProps.c("#d9d4c6") if (k + layer) % 2 == 0 else DsProps.c("#cbc5b4"))
	_solid(body, Vector3(1.2, 0.6, 1.0), pal + Vector3(0, 0.3, 0))
	# a stack of concrete pipes: three, two on them
	var pipe := DsProps.c("#b9b9b2")
	for k in 5:
		var px: float = -17.2 + (float(k) if k < 3 else k - 2.5) * 0.74
		var py: float = 0.36 if k < 3 else 0.99
		var a := Vector3(px, py, z0 + 5.2)
		kit.cone(a, a + Vector3(0, 0, 2.4), 0.36, 0.36, 10, pipe)
		kit.cone(a + Vector3(0, 0, -0.01), a + Vector3(0, 0, 0.0), 0.27, 0.27, 10, DsProps.BLACK)
		kit.cone(a + Vector3(0, 0, 2.4), a + Vector3(0, 0, 2.41), 0.27, 0.27, 10, DsProps.BLACK)
	_solid(body, Vector3(2.3, 1.3, 2.4), Vector3(-16.45, 0.65, z0 + 6.4))
	# witches' hats either side of the gate, a row of pegs along the way in
	for at: Vector3 in [Vector3(-5.9, 0, z0 + 1.2), Vector3(5.9, 0, z0 + 1.2), Vector3(-6.2, 0, z0 + 3.4), Vector3(6.2, 0, z0 + 3.4)]:
		kit.box(at + Vector3(0, 0.02, 0), Vector3(0.36, 0.04, 0.36), DsProps.HI_VIS)
		kit.cone(at + Vector3(0, 0.04, 0), at + Vector3(0, 0.62, 0), 0.13, 0.03, 8, DsProps.HI_VIS)
		kit.cone(at + Vector3(0, 0.3, 0), at + Vector3(0, 0.42, 0), 0.085, 0.066, 8, DsProps.c("#f4f1ea"))
	for k in 4:
		DsProps.survey_peg(kit, Vector3(4.6 if k % 2 == 0 else -4.6, 0.0, z0 + 5.5 + 2.2 * (k / 2)))
	# a light tower at the corner, its lamps over the site
	DsProps.light_tower(kit, Vector3(16.6, 0.0, z0 + 1.6), -2.2)
	_solid(body, Vector3(2.2, 1.6, 1.4), Vector3(16.6, 0.8, z0 + 1.6))
	_prop(kit, Vector3.ZERO, 0.0)

## A prop's mesh shown at `at` (from the site's middle), turned yaw
func _prop(kit: DsKit, at: Vector3, yaw: float) -> Node3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = DsLook.prop_mat()
	m.transform = Transform3D(Basis(Vector3.UP, yaw), AT + at)
	add_child(m)
	return m

## Something solid there (a box), not drawn
func _solid(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = AT + at
	body.add_child(cs)

func _mat(c: Color) -> Material:
	return DsLook.flat(c)

func _box(body: StaticBody3D, size: Vector3, at: Vector3, m: Material, alpha := 1.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	if alpha < 1.0:
		# (see-through: the fence's mesh panels; plain, not toon: the ink would draw their edges anyway)
		var sm := StandardMaterial3D.new()
		var c: Vector3 = (m as ShaderMaterial).get_shader_parameter("albedo")
		sm.albedo_color = Color(c.x, c.y, c.z, alpha)
		sm.roughness = 1.0
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = sm
	else:
		mi.material_override = m
	mi.position = AT + at
	add_child(mi)
	if body:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = AT + at
		body.add_child(cs)

# ---------------------------------------------------------------- going and coming back

## Off to the Dig Site: the arena waits. (In co-op: VoxelPhone asks travel(), which takes both.)
func go() -> void:
	if active:
		return
	if not built:
		_build()
	_home_at = arena.player.global_position
	_home_yaw = arena.look_yaw
	_home_pitch = arena.look_pitch
	_was_frozen = arena.frozen
	arena.frozen = true
	_debris_bound = arena.debris.bound
	arena.debris.bound = INF
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_help_text = arena.help.text
	arena.help.text = "DIG SITE   P phone (travel home)   WASD walk   6 tools: shovel, pick, hammer   E site office, E drive a machine   4 dynamite   Tab backpack"
	_hud.visible = true
	look.enter()
	var spot := SPAWN + (Vector3(1.5, 0, 0) if _is_guest() else Vector3.ZERO)     # (the two of you side by side)
	_put(AT + spot, 0.0, -0.1)
	terrain.build_now(900.0)                  # (the screen's black: the ground near you there before you see it, the rest streams in)
	net.arrived()                             # (a guest: the host's ground asked for)

## Back to the arena, where you were.
func home() -> void:
	if not active:
		return
	if machines and machines.driving:
		machines.get_off()
	if lamp:
		lamp.visible = false
	net.left()
	active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	arena.frozen = _was_frozen
	arena.debris.bound = _debris_bound
	arena.help.text = _help_text
	_hud.visible = false
	look.leave()
	_put(_home_at, _home_yaw, _home_pitch)

func _put(at: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = at
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

func _process(_dt: float) -> void:
	if not active:
		return
	var who := "with your mate" if _linked() else "on your own"
	_hud.text = "DIG SITE   (%s)   P: the phone takes you home" % who
	var p: Vector3 = arena.player.global_position
	var w := AT + OFFICE_WINDOW
	near_office = Vector2(p.x - w.x, p.z - w.z).length() < 2.2 and absf(p.y - w.y) < 2.5
	if near_office:
		arena._use_label.text = tools.office_line() + "\n" + tools.shop_line()
	elif machines and not driving() and machines.line() != "":
		arena._use_label.text = machines.line()
	# the hard hat's lamp: on with solid ground over your head (in a tunnel)
	if lamp and terrain:
		var c := terrain.cell_of(p + Vector3(0, 1.7, 0))
		var top := terrain.grid.column_top(c.x, c.z)
		lamp.visible = terrain.contains(p) and top > c.y + 1

## Whether this player's driving a machine here (the arena: no walking, no weapons)
func driving() -> bool:
	return active and machines != null and machines.driving != null

## The player put at p, the look left as it is (riding a machine)
func _put_keep(p: Vector3) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO

func _unhandled_input(e: InputEvent) -> void:
	if not active or arena.phone.is_open():
		return
	# driving: V the view, the wheel nearer or further (not the weapons)
	if driving() and e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		machines.zoom(e.button_index == MOUSE_BUTTON_WHEEL_UP)
		get_viewport().set_input_as_handled()
		return
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if driving() and (e as InputEventKey).physical_keycode == KEY_V:
		machines.toggle_view()
		get_viewport().set_input_as_handled()
		return
	var k := (e as InputEventKey).physical_keycode
	if near_office and k in [KEY_B, KEY_C, KEY_V, KEY_X]:
		match k:
			KEY_B:
				tools.buy_props()
			KEY_X:
				tools.buy_dynamite()
			KEY_C:
				tools.make_concrete()
			KEY_V:
				tools.sell_ore()
		get_viewport().set_input_as_handled()
		return
	if machines and k in [KEY_L, KEY_G] and machines.key(k):
		get_viewport().set_input_as_handled()
		return
	if k != KEY_E:
		return
	if driving() or (machines and machines.near and not near_office):
		machines.use()
		get_viewport().set_input_as_handled()
	elif near_office:
		tools.office_make()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- co-op: both of you go

func _net():
	var n = arena.get("net")
	return n if n != null and n.linked else null

func _linked() -> bool:
	return _net() != null

func _is_guest() -> bool:
	var n = _net()
	return n != null and n.role == "guest"

## The phone's Travel to the Dig Site (there: true) or home (false). On your own: you go. With a mate: the host takes
## you both (a guest's choice is asked of the host, who sends both of you).
func travel(there: bool) -> void:
	var n = _net()
	if n == null:
		_here(there)
		return
	if n.role == "guest":
		n.send_digsite(["want", there])
		return
	_both(there)

func _here(there: bool) -> void:
	if there:
		go()
	else:
		home()

func _both(there: bool) -> void:
	arena.phone.arrive(_here.bind(there), "Off to the Dig Site ..." if there else "Heading home ...")
	var n = _net()
	if n:
		n.send_digsite(["go", there])

## Messages from the other game (VoxelNet "D")
func on_net(m: Array) -> void:
	if not m.is_empty() and String(m[0]) == "n":
		net.on_net(m.slice(1))                # (the ground's sync: DsNet)
		return
	if m.is_empty():
		return
	var n = _net()
	if n == null:
		return
	match String(m[0]):
		"want":
			if n.role == "host" and m.size() > 1:
				_both(bool(m[1]))
		"go":
			if n.role == "guest" and m.size() > 1:
				arena.phone.arrive(_here.bind(bool(m[1])), "Off to the Dig Site ..." if bool(m[1]) else "Heading home ...")
