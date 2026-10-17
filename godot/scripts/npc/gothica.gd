class_name Gothica
extends CharacterBody3D
## Gothica wandering the lobby, the HTML game's lobby NPC (Smashed.html: NPC_AREA, NPC_GOTH, npcPickSpot,
## npcNextPoint, lobbyGoth). Owned by the Trampoline and Gothica task.
##
## She strolls at T.npcSpeed between random spots on the open floor of NPC_AREA (never one inside furniture),
## waits 1.5-4 s at each facing the room, then picks another. She walks the genuinely shortest way round the
## furniture: the nodes are her, the spot and the corners of every obstacle (each solid box grown by NPC_PAD,
## the corners 2 further out), joined where the straight line between them is clear; she heads for the first
## hop. If she hasn't actually moved 6 units in 2 s (someone in her way) she gives that spot up (the backstop).
##
## The obstacles are the World's solids: WorldBuilder.ground_boxes() (the node in the "world_builder" group, or
## any WorldBuilder in the tree), else calls.lobbySolidBoxes from game_data.json; only those near NPC_AREA count.
## Her picture is a CharSprite child (char_id "goth"), given her facing, moving and odo so she walks properly.
## Collision: a capsule on layer 3 (bit 4, "npcs"), hitting layer 1 (the World), moved with move_and_slide.
## Not yet: being carried, thrown, watching the lifts, dealing cards, talking.

## Where she starts, HTML units (NPC_GOTH.x, y).
@export var start: Vector2 = Vector2(200, 360)
## Put her at start in _ready (off: wherever the scene put her).
@export var place_on_ready: bool = true

## Her state, the HTML game's NPC_GOTH (HTML ground axes and units).
var facing: Vector2 = Vector2(0, 1)       ## fx, fy
var odo: float = 0.0
var moving: bool = false
var target: Vector2 = Vector2(200, 360)   ## tx, ty: the spot she's heading for
var wait: float = 1.0                     ## seconds left standing at a spot
var hop: Vector2 = Vector2.ZERO           ## the point she's walking straight at now (npcNextPoint)
## The obstacles she walks round, grown by NPC_PAD: [{x0, y0, x1, y1}] (HTML units).
var obstacles: Array = []
## The area she picks spots in (NPC_AREA).
var area: Rect2 = Rect2(70, 250, 520, 160)
var sprite: CharSprite

const NPC_PAD := 12.0          # her radius, and a bit
const CORNER := 2.0            # npcNextPoint's e
const RADIUS := 8.0            # the HTML game pushes her out of the table at 8
const BODY_H := 60.0
const NEAR := 60.0             # obstacles this close to NPC_AREA count
const U := 0.025

var _stuck_t: float = 0.0
var _stuck_at = null           # Vector2 or null (n.stuckX undefined)
var _speed: float = 38.0
var _enabled: bool = true
var _have_obstacles: bool = false
var _raw: Array = []            # the obstacles before padding

func _enter_tree() -> void:
	add_to_group("npc")
	add_to_group("gothica")

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1 << 3
	collision_mask = 1
	wall_min_slide_angle = 0.0
	safe_margin = 0.004
	var d: Dictionary = GameData.data
	var t: Dictionary = d.get("T", {})
	_speed = float(t.get("npcSpeed", 38.0))
	_enabled = float(t.get("npcGoth", 1)) != 0.0
	var a = d.get("NPC_AREA", null)
	if a is Dictionary:
		area = Rect2(a.x0, a.y0, a.x1 - a.x0, a.y1 - a.y0)
	var shape: CollisionShape3D = null
	for c in get_children():
		if c is CollisionShape3D and shape == null:
			shape = c
		elif c is CharSprite and sprite == null:
			sprite = c
	if shape == null:
		shape = CollisionShape3D.new()
		shape.name = "Body"
		add_child(shape)
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS * U
	cap.height = BODY_H * U
	shape.shape = cap
	shape.position = Vector3(0, (0.8 + BODY_H / 2.0) * U, 0)
	if sprite == null:
		sprite = CharSprite.new()
		sprite.name = "Sprite"
		add_child(sprite)
	sprite.char_id = "goth"
	if place_on_ready:
		place(start.x, start.y)
	target = html_pos2()
	visible = _enabled
	_sync_sprite()

## Where she is, HTML units on the ground.
func html_pos2() -> Vector2:
	var p := GameData.from_3d(global_position)
	return Vector2(p.x, p.y)

## Put her somewhere (HTML units) and stand her there.
func place(x: float, y: float) -> void:
	global_position = GameData.world_to_3d(x, y, 0.0)
	target = Vector2(x, y)
	moving = false
	_stuck_at = null

## Take the obstacles again (after the World has changed).
func refresh_obstacles() -> void:
	_have_obstacles = false

# ------------------------------------------------------------------ the obstacles

func _load_obstacles() -> void:
	_have_obstacles = true
	var boxes: Array = []
	var w: Node = null
	if is_inside_tree():
		w = get_tree().get_first_node_in_group("world_builder")
		if w == null:
			for n in get_tree().root.find_children("*", "Node3D", true, false):
				var sc = n.get_script()
				if sc is Script and sc.get_global_name() == "WorldBuilder" and n.has_method("ground_boxes"):
					w = n
					break
	if w and w.has_method("ground_boxes"):
		boxes = w.ground_boxes()
	else:
		var c = GameData.data.get("calls", {})
		if c is Dictionary:
			boxes = c.get("lobbySolidBoxes", [])
	var near := area.grow(NEAR)
	_raw = []
	obstacles = []
	for b in boxes:
		if not (b is Dictionary) or not b.has("x0"):
			continue
		var r := Rect2(float(b.x0), float(b.y0), float(b.x1) - float(b.x0), float(b.y1) - float(b.y0))
		if not r.intersects(near):
			continue
		_raw.append({"x0": r.position.x, "y0": r.position.y, "x1": r.end.x, "y1": r.end.y})
		obstacles.append({"x0": r.position.x - NPC_PAD, "y0": r.position.y - NPC_PAD,
			"x1": r.end.x + NPC_PAD, "y1": r.end.y + NPC_PAD})

static func in_box(x: float, y: float, b: Dictionary) -> bool:
	return x > b.x0 and x < b.x1 and y > b.y0 and y < b.y1

## Does the segment a->b pass through the inside of box r? (Liang-Barsky, segHitsBox)
static func seg_hits_box(ax: float, ay: float, bx: float, by: float, r: Dictionary) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var dx := bx - ax
	var dy := by - ay
	for pq in [[-dx, ax - r.x0], [dx, r.x1 - ax], [-dy, ay - r.y0], [dy, r.y1 - ay]]:
		var p: float = pq[0]
		var q: float = pq[1]
		if p == 0.0:
			if q <= 0.0:
				return false
			continue
		var t := q / p
		if p < 0.0:
			if t > t1:
				return false
			if t > t0:
				t0 = t
		else:
			if t < t0:
				return false
			if t < t1:
				t1 = t
	return t1 - t0 > 1e-6

func _clear(a: Vector2, b: Vector2) -> bool:
	for o in obstacles:
		if seg_hits_box(a.x, a.y, b.x, b.y, o):
			return false
	return true

func _inside_any(x: float, y: float) -> bool:
	for o in obstacles:
		if in_box(x, y, o):
			return true
	return false

## npcPickSpot: a random free spot in NPC_AREA (30 tries; nowhere free: stay put).
func pick_spot() -> void:
	for i in 30:
		var x := area.position.x + randf() * area.size.x
		var y := area.position.y + randf() * area.size.y
		if not _inside_any(x, y):
			target = Vector2(x, y)
			return
	target = html_pos2()

## npcNextPoint: the first hop of the shortest walkable path from `from` to the target.
func next_point(from: Vector2) -> Vector2:
	if _clear(from, target):
		return target
	var pts: Array = [from, target]
	for b in obstacles:
		for c in [Vector2(b.x0 - CORNER, b.y0 - CORNER), Vector2(b.x1 + CORNER, b.y0 - CORNER),
				Vector2(b.x0 - CORNER, b.y1 + CORNER), Vector2(b.x1 + CORNER, b.y1 + CORNER)]:
			if not _inside_any(c.x, c.y):
				pts.append(c)
	# Dijkstra from the spot back towards her, so the next hop can be read off
	var N := pts.size()
	var dist: Array = []
	var nxt: Array = []
	var done: Array = []
	dist.resize(N)
	nxt.resize(N)
	done.resize(N)
	for i in N:
		dist[i] = INF
		nxt[i] = -1
		done[i] = false
	dist[1] = 0.0
	while true:
		var u := -1
		for i in N:
			if not done[i] and dist[i] < INF and (u < 0 or dist[i] < dist[u]):
				u = i
		if u < 0:
			break
		done[u] = true
		for v in N:
			if done[v] or v == u:
				continue
			if not _clear(pts[u], pts[v]):
				continue
			var nd: float = dist[u] + (pts[u] as Vector2).distance_to(pts[v])
			if nd < dist[v]:
				dist[v] = nd
				nxt[v] = u
	var h: int = nxt[0]
	return target if h < 0 else pts[h]      # no way round: fall back and let the backstop sort it

## The whole path from her to the target, for tests and debugging (each hop's next_point).
func path_points() -> Array:
	var out: Array = []
	var at := html_pos2()
	for i in 32:
		var p := next_point(at)
		out.append(p)
		if p.distance_to(target) < 0.01:
			break
		at = p
	return out

# ------------------------------------------------------------------ lobbyGoth

func _physics_process(delta: float) -> void:
	if not _enabled:
		return
	if not _have_obstacles:
		_load_obstacles()
	var dt := clampf(delta, 0.0, 0.1)
	_step(dt)
	_sync_sprite()

func _step(dt: float) -> void:
	var at := html_pos2()
	if wait > 0.0:
		wait -= dt
		moving = false
		if wait <= 0.0:
			pick_spot()
			_stuck_t = 0.0
			_stuck_at = null
		return
	if at.distance_to(target) < 3.0:
		wait = 1.5 + randf() * 2.5
		moving = false
		facing = Vector2(0, 1)              # turn to face the room
		return
	# backstop: hasn't actually moved in a couple of seconds (a player in her way, say): give that spot up.
	# "Hasn't moved", not "hasn't got closer": going round the table takes her further away for a while.
	if _stuck_at == null or at.distance_to(_stuck_at) > 6.0:
		_stuck_at = at
		_stuck_t = 0.0
	else:
		_stuck_t += dt
		if _stuck_t > 2.0:
			pick_spot()
			_stuck_t = 0.0
			_stuck_at = null
			return
	hop = next_point(at)
	var d := hop - at
	var dl := d.length()
	if dl < 0.0001:
		dl = 1.0
	var dir := d / dl
	var step := minf(dl, _speed * dt)
	facing = dir
	moving = true
	# move, sliding along anything solid (her path keeps NPC_PAD clear of the solids, so normally nothing)
	velocity = Vector3(dir.x, 0.0, dir.y) * (step / maxf(dt, 0.0001)) * U * (dt / maxf(get_physics_process_delta_time(), 0.0001))
	global_position.y = 0.0
	move_and_slide()
	velocity = Vector3.ZERO
	global_position.y = 0.0
	var now := html_pos2()
	odo += now.distance_to(at)
	_push_out()

# lobbySolids' backstop: pushOutOfBox(NPC_GOTH, 8, box) for each solid she might be in.
func _push_out() -> void:
	var p := html_pos2()
	var moved := false
	for b in _raw:
		var cx := clampf(p.x, b.x0, b.x1)
		var cy := clampf(p.y, b.y0, b.y1)
		var dx := p.x - cx
		var dy := p.y - cy
		var d := sqrt(dx * dx + dy * dy)
		if d >= RADIUS:
			continue
		if d > 0.0001:
			p += Vector2(dx, dy) / d * (RADIUS - d)
		else:
			# inside it: out the nearest side
			var l: float = p.x - b.x0
			var r: float = b.x1 - p.x
			var t: float = p.y - b.y0
			var bo: float = b.y1 - p.y
			var m := minf(minf(l, r), minf(t, bo))
			if m == l:
				p.x = b.x0 - RADIUS
			elif m == r:
				p.x = b.x1 + RADIUS
			elif m == t:
				p.y = b.y0 - RADIUS
			else:
				p.y = b.y1 + RADIUS
		moved = true
	if moved:
		global_position = GameData.world_to_3d(p.x, p.y, 0.0)

func _sync_sprite() -> void:
	if sprite == null:
		return
	sprite.char_id = "goth"
	sprite.facing = facing
	sprite.moving = moving
	sprite.odo = odo
