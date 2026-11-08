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
	var grass := _mat(Color8(86, 120, 58))
	var fence := _mat(Color8(220, 140, 40))
	var hut := _mat(Color8(214, 218, 222))
	var roof := _mat(Color8(70, 86, 110))
	# the voxel ground in the middle (stage 2), the field round it (four slabs: none under the ground)
	terrain = DsTerrain.new()
	add_child(terrain)
	terrain.setup(self, AT, SEED)
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
	# the site fence: orange mesh panels on posts round the dirt, a gap at the front
	var half := SIZE * 0.5 + 1.0
	for side in 4:
		var n := int(SIZE / 4.0) + 1
		for i in n:
			var t := -half + i * (2.0 * half / float(n - 1))
			var at := Vector3(t, 0.6, -half) if side == 0 else (Vector3(t, 0.6, half) if side == 1 else (Vector3(-half, 0.6, t) if side == 2 else Vector3(half, 0.6, t)))
			if side == 1 and absf(t) < 5.0:
				continue                          # (the way in)
			_box(body, Vector3(0.1, 1.2, 0.1), at, fence)
		var len := 2.0 * half
		if side == 1:
			for s in [-1.0, 1.0]:
				_box(null, Vector3(half - 5.0, 1.0, 0.03), Vector3(s * (5.0 + (half - 5.0) * 0.5), 0.6, half), fence, 0.55)
		elif side == 0:
			_box(null, Vector3(len, 1.0, 0.03), Vector3(0, 0.6, -half), fence, 0.55)
		else:
			_box(null, Vector3(0.03, 1.0, len), Vector3(half if side == 3 else -half, 0.6, 0), fence, 0.55)
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

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _box(body: StaticBody3D, size: Vector3, at: Vector3, m: StandardMaterial3D, alpha := 1.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	if alpha < 1.0:
		m = m.duplicate()
		m.albedo_color.a = alpha
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
