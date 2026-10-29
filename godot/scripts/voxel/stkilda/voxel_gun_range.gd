class_name VoxelGunRange
extends Node3D
## The gun range (the owner, 29 Oct: "a tutorial to show off how each gun works"): on the phone (Travel: Gun range),
## a firing line of lanes off past the arena (3 km west of it, in its world, under its sky), a lane a weapon. Walk onto
## a lane's mat and its weapon comes out; its sign says what it is, its keys and what it's good for; and there's
## something down the lane to try it on, set out to show it off: dummies far off for the pistol, a bunch close up for
## the shotgun, a line of them for the laser and the spear, a heap of cubes for the vacuum. They stand still (the
## arena's waiting while you're here). Knock a lane's all down and it says DONE, then sets them up again. ] and [ step
## to the next lane and back. The tools' lane only points you at the back yard (they work its ground). The phone
## takes you home.

const AT := Vector3(-3000.0, 0.0, 0.0)   # the firing line's left end
const LANE := 12.0                       # each lane's width
const LONG := 48.0                       # how far down the range goes
const RESET_T := 3.0                     # s after a lane's cleared before it's set up again

## Every lane: the weapon, what it's good for, and what's down the lane: [kind, x across, z down] each (or "pile").
const STOPS := [
	["sword", "Close up: slash the way you move the mouse; right click chops down.", [["grunt", -1.0, 3.0], ["grunt", 1.2, 3.5]]],
	["bat", "Knocks them flying. Hold right click for a home run.", [["grunt", -1.0, 3.0], ["swarmer", 1.2, 3.5]]],
	["hammer", "Heavy hits. Right click slams the ground and floors everyone near.", [["grunt", -1.5, 3.0], ["grunt", 0.0, 3.5], ["grunt", 1.5, 3.0]]],
	["chainsaw", "Hold to saw right through. Right click lunges.", [["brute", 0.0, 3.5]]],
	["spear", "A thrust skewers a whole line. Right click throws it (again to call it back).", [["grunt", 0.0, 4.0], ["grunt", 0.0, 5.5], ["grunt", 0.0, 7.0]]],
	["pistol", "Picks them off far away. Right click aims in: tight shots, headshots.", [["grunt", -2.0, 10.0], ["grunt", 1.5, 20.0], ["grunt", -0.5, 30.0]]],
	["shotgun", "A bunch close up. Right click: both barrels.", [["grunt", -1.2, 6.0], ["grunt", 0.0, 6.5], ["grunt", 1.2, 6.0], ["swarmer", -0.6, 7.5], ["swarmer", 0.6, 7.5]]],
	["laser", "Hold and drag to cut. Hold right click to overcharge: a beam through a whole line.", [["grunt", 0.0, 8.0], ["grunt", 0.0, 10.0], ["grunt", 0.0, 12.0], ["grunt", 0.0, 14.0]]],
	["flamethrower", "Sets them alight; fire spreads between them. Right click lobs a fire bomb.", [["grunt", -1.5, 6.0], ["grunt", 0.0, 6.5], ["grunt", 1.5, 6.0], ["grunt", 0.0, 8.0]]],
	["freezeray", "Freeze them solid, then the ice shot (right click) shatters them.", [["grunt", -2.0, 8.0], ["brute", 0.0, 9.0], ["grunt", 2.0, 8.0]]],
	["harpoon", "Drags them to you. Right click yanks a limb off.", [["grunt", -1.5, 14.0], ["brute", 1.5, 16.0]]],
	["gravity", "Grab a body, launch it into the others. Right click: a black hole.", [["grunt", -2.0, 8.0], ["grunt", 0.0, 9.0], ["grunt", 2.0, 8.0]]],
	["grenades", "Bounce one into a crowd. Right click sticks a bomb on; R sets them off.", [["grunt", -1.5, 15.0], ["grunt", 0.0, 15.5], ["grunt", 1.5, 15.0], ["swarmer", -0.8, 17.0], ["swarmer", 0.8, 17.0], ["brute", 0.0, 18.5]]],
	["vacuum", "Sucks up the cubes they leave (they go in your backpack). Hold right click and turn the wheel: brush size.", ["pile"]],
	["shovel", "The tools work the back yard's ground: the shovel and pick dig and break, the hoe makes rows to plant, the can waters. Try them out there.", []],
]

var arena: VoxelArena
var active := false
var built := false
var lane := -1                   # the lane you're on
var done := {}                   # lane -> true once cleared (this visit)
var _bodies: Array = []          # the current lane's
var _reset := -1.0
var _home_at := Vector3.ZERO
var _home_yaw := 0.0
var _home_pitch := 0.0
var _was_frozen := false
var _debris_bound := INF
var _help_text := ""
var _hud: Label
var _signs: Array = []           # Label3D a lane

func setup(a: VoxelArena) -> void:
	arena = a
	name = "GunRange"
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.offset_left = -420
	_hud.offset_right = 420
	_hud.offset_top = 64
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_theme_font_size_override("font_size", 22)
	_hud.add_theme_color_override("font_color", Color("#9fe7ff"))
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 8)
	_hud.visible = false
	a._hud_layer.add_child(_hud)

func _build() -> void:
	built = true
	var n := STOPS.size()
	var w := n * LANE
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var conc := _mat(Color("#8d8a84"))
	var mat_c := _mat(Color("#3f6f4a"))
	var wall_c := _mat(Color("#6b5a48"))
	_box(body, Vector3(w + 8.0, 1.0, LONG + 14.0), AT + Vector3(w * 0.5, -0.5, -LONG * 0.5 + 3.0), conc)          # the floor
	_box(body, Vector3(w + 8.0, 5.0, 1.5), AT + Vector3(w * 0.5, 2.5, -LONG - 2.0), wall_c)                      # the back
	_box(body, Vector3(w + 8.0, 2.0, 0.6), AT + Vector3(w * 0.5, 1.0, 10.0), wall_c)                              # behind you
	for s in [-4.0, w + 4.0]:
		_box(body, Vector3(0.6, 2.0, LONG + 14.0), AT + Vector3(s, 1.0, -LONG * 0.5 + 3.0), wall_c)            # the ends
	for i in n + 1:
		_box(body, Vector3(0.3, 1.1, LONG - 2.0), AT + Vector3(i * LANE, 0.55, -LONG * 0.5 - 1.0), wall_c)      # between lanes
	for i in n:
		var x := i * LANE + LANE * 0.5
		_box(null, Vector3(LANE - 1.5, 0.04, 3.0), AT + Vector3(x, 0.02, 1.5), mat_c)                           # the mat
		var sign := Label3D.new()
		sign.text = _sign_text(i)
		sign.font_size = 34
		sign.pixel_size = 0.006
		sign.outline_size = 10
		sign.width = 900
		sign.autowrap_mode = TextServer.AUTOWRAP_WORD
		sign.modulate = Color("#fff4c2")
		sign.position = AT + Vector3(x, 2.3, -2.5)
		add_child(sign)
		_signs.append(sign)
		var num := Label3D.new()
		num.text = str(i + 1)
		num.font_size = 120
		num.pixel_size = 0.01
		num.rotation = Vector3(-PI / 2.0, 0, 0)
		num.position = AT + Vector3(x, 0.06, 2.4)
		num.modulate = Color(1, 1, 1, 0.7)
		add_child(num)

func _sign_text(i: int) -> String:
	var id: String = STOPS[i][0]
	if id == "shovel":
		return "%d  THE TOOLS\n%s" % [i + 1, STOPS[i][1]]
	var slot: Dictionary = VoxelLoadout.ALL.filter(func(sl): return sl.id == id)[0]
	var keys := "Left: %s" % slot.left
	if String(slot.right) != "":
		keys += "\nRight: %s" % slot.right
	return "%d  %s%s\n%s\n%s" % [i + 1, String(slot.name).to_upper(), "   DONE" if done.has(i) else "", keys, STOPS[i][1]]

static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _box(body: StaticBody3D, size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	add_child(mi)
	if body:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = at
		body.add_child(cs)

## Where you stand at a lane, facing down it.
func spot(i: int) -> Vector3:
	return AT + Vector3(i * LANE + LANE * 0.5, 0.05, 1.5)

## Off to the range: the arena waits.
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
	done.clear()
	_help_text = arena.help.text
	arena.help.text = "GUN RANGE   walk onto a lane: its weapon   ] next lane   [ back   P phone (home)   WASD walk   mouse look   V view"
	_hud.visible = true
	lane = -1
	to_lane(5)                               # (the pistol's first)

func home() -> void:
	if not active:
		return
	active = false
	_clear()
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

## Stood on lane i, facing down it.
func to_lane(i: int) -> void:
	i = clampi(i, 0, STOPS.size() - 1)
	_put(spot(i), 0.0, -0.05)
	_enter(i)

func _enter(i: int) -> void:
	if i == lane:
		return
	lane = i
	_set_up(i)
	var id: String = STOPS[i][0]
	var k := arena.loadout.index_of(id)
	if k >= 0:
		arena._switch(func(): arena.loadout.select(k))

func _set_up(i: int) -> void:
	_clear()
	_reset = -1.0
	var base := spot(i)
	for t in STOPS[i][2]:
		if t is String and t == "pile":
			var cols := [Color8(150, 22, 28), Color8(226, 220, 204), Color8(218, 150, 162), Color8(120, 118, 128)]
			for k in 6:
				arena.debris.plop(base + Vector3(randf_range(-1.5, 1.5), 0.2, -3.0 - randf_range(0.0, 2.0)), cols, 60)
			continue
		var b := arena.spawn_kind(String(t[0]), base + Vector3(float(t[1]), -0.05, -float(t[2])))
		b.yaw = 0.0                           # (facing you)
		b.set_meta("range", true)
		_bodies.append(b)

func _clear() -> void:
	for b in _bodies:
		if is_instance_valid(b):
			arena.bodies.erase(b)
			b.queue_free()
	_bodies.clear()
	arena.debris.clear_near(spot(maxi(lane, 0)) + Vector3(0, 0, -LONG * 0.5), LONG, 100000)

func _process(dt: float) -> void:
	# the lane you're on
	var p := arena.player.global_position
	var i := clampi(floori((p.x - AT.x) / LANE), 0, STOPS.size() - 1)
	if p.z > AT.z - 4.0:
		_enter(i)
	var id: String = STOPS[lane][0]
	var left := _bodies.filter(func(b): return is_instance_valid(b) and b.alive).size()
	if not _bodies.is_empty() and left == 0:
		if _reset < 0.0:
			_reset = RESET_T
			if not done.has(lane):
				done[lane] = true
				(_signs[lane] as Label3D).text = _sign_text(lane)
		_reset -= dt
		if _reset <= 0.0:
			_set_up(lane)
	var name_ := "the tools" if id == "shovel" else String(VoxelLoadout.ALL.filter(func(sl): return sl.id == id)[0].name)
	_hud.text = "GUN RANGE   lane %d of %d: %s%s   %d of %d done   ] next  [ back" % [lane + 1, STOPS.size(), name_,
		("   DONE, setting up again" if _reset > 0.0 else ("   %d to go" % left if not _bodies.is_empty() else "")), done.size(), STOPS.size() - 1]

func _unhandled_input(e: InputEvent) -> void:
	if not active or arena.phone.is_open() or not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k := (e as InputEventKey).physical_keycode
	if k == KEY_BRACKETRIGHT:
		to_lane(lane + 1)
		get_viewport().set_input_as_handled()
	elif k == KEY_BRACKETLEFT:
		to_lane(lane - 1)
		get_viewport().set_input_as_handled()
