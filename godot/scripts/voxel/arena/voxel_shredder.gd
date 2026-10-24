class_name VoxelShredder
extends Node3D
## The shredder (the owner, 21 Oct, Stage 6.5: "gore pieces become a resource: shred them into bags of blood and bone
## fertiliser for crops, the worm farm and chickens; throw limbs in the top, it grinds with blood spray, bags drop out
## the bottom; upgrade tiers: hand-crank mincer -> bigger shredder -> industrial woodchipper; charred pieces give
## lower-value fertiliser").
##
## Against the back yard's south fence. Whatever comes to its mouth is taken in: a piece flying or dropped in (the
## gravity gun carries them out of the arena; the harpoon drags them), a lying limb or corpse put in, or (E) the gore in
## your backpack. Too big for it (the mincer takes a hand, a foot, a forearm; the shredder a head or a leg; the
## woodchipper anything dead, a whole body: the gravity gun carries one out through the back door) and it sits in the
## top. In, it grinds it at the tier's
## rate, spraying blood (grey ash puffs for burnt stuff), and every BAG_POINTS a bag of blood and bone drops out of the
## bottom onto a pile (E takes them). Meat and brain are a point a cube, bone two, burnt (charred) cubes 0.35, clothes and
## gear (rubble) 0.1: a body burnt black makes few bags (and its ash made none). A bag feeds a plant (like castings),
## the worm farm (150 scraps' worth) or the chickens' feeder (12 feeds). Its sign upgrades it.
##
## Co-op: the host's: the host's game takes in what comes to its mouth; a guest's backpack gore, bag taking and
## upgrading go to the host as requests (network message "M"); its state goes to the guest every 2 s and on every
## change. Saved with the rest. Owned by the voxel session.

const AT := Vector3(14.0, 0, 38.3)      # where it stands (its front to the north)
const BAG_POINTS := 4000.0
## What a cube of each is worth.
const VALUE := {"meat": 1.0, "brain": 1.0, "bone": 2.0, "charred": 0.35, "blocks": 0.1,
	"chicken_carcass": VoxelChickens.CARCASS_POINTS}
const FEED_MOST := 20000                # backpack cubes put in at a go
const BAG_FEEDS := 12                   # a bag in the chickens' feeder
const BAG_SCRAPS := 150.0               # a bag in the worm farm
## The tiers: name, cubes a second, the biggest thing it takes (cubes; 0 any), its mouth (local box), the pile, the
## sign, the loop, how much it sprays, what the next costs.
const TIERS := [
	{"name": "Hand-crank mincer", "rate": 300.0, "most": 2000, "mouth": [Vector3(-0.32, 0.85, -0.32), Vector3(0.64, 1.1, 0.64)],
		"pile": Vector3(0.85, 0, 0.0), "sign": Vector3(-0.85, 0, -0.45), "loop": "mince_loop", "spray": 30},
	{"name": "Electric shredder", "rate": 1500.0, "most": 8000, "mouth": [Vector3(-0.6, 1.15, -0.55), Vector3(1.2, 1.3, 1.1)],
		"pile": Vector3(1.15, 0, 0.0), "sign": Vector3(-1.05, 0, -0.55), "loop": "shred_loop", "spray": 90, "cash": 200, "cost": {"stone": 300}},
	{"name": "Industrial woodchipper", "rate": 8000.0, "most": 0, "mouth": [Vector3(-2.15, 0.35, -0.75), Vector3(1.75, 1.9, 1.5)],
		"pile": Vector3(0.35, 0, -1.05), "sign": Vector3(1.75, 0, -0.75), "loop": "chip_loop", "spray": 260, "cash": 600, "cost": {"gold": 60}},
]
const SYNC_T := 2.0
const CHECK_T := 0.1

var arena: Node3D
var tier := 0
var queue := {}                 # item id -> cubes waiting to be ground
var points := 0.0
var bags := 0
var ground := 0.0               # cubes ever ground (the blood on the ground)
var _sync_t := 0.0
var _check_t := 0.0
var _dirty := false
var _dirty_t := 0.0
var _own = null
var _was_role := ""
var _said := {}                 # (too big: said once a thing)
var _models := []               # per tier: its root
var _spin := []                 # per tier: [node, axis] turning while it grinds
var _spray: CPUParticles3D
var _spray_mat: StandardMaterial3D
var _stain: MeshInstance3D
var _pile := []                 # bag meshes on the pile
var _pile_label: Label3D
var _sign: Label3D
var _sign_post: Node3D
var _falling := []              # [mesh, t] bags dropping out
var _grinding := false
var _acc := 0.0                 # (the cubes it's due to grind: the frames' fractions add up)
var _crunch_t := 0.0
var _shake := 0.0

func setup(arena_: Node3D) -> void:
	arena = arena_
	position = AT
	_build()
	_show_tier()

func _is_guest() -> bool:
	return arena.net != null and arena.net.role == "guest" and arena.net.linked

func _is_host() -> bool:
	return arena.net != null and arena.net.role == "host" and arena.net.linked

func queued() -> int:
	var n := 0
	for id in queue:
		n += int(queue[id])
	return n

## How many bags these cubes make (their points).
static func points_of(counts: Dictionary) -> float:
	var p := 0.0
	for id in counts:
		p += int(counts[id]) * float(VALUE.get(id, 0.0))
	return p

# ---------------------------------------------------------------- grinding

func _process(dt: float) -> void:
	var role: String = arena.net.role if arena.net and arena.net.linked else ""
	if role != _was_role:
		if _was_role == "guest" and _own != null:
			from_data(_own)
			_own = null
		if role == "host":
			_send_all()
		_was_role = role
	if not _is_guest():
		_check_t += dt
		if _check_t >= CHECK_T:
			_check_t = 0.0
			_mouth()
	_grind(dt)
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

func _grind(dt: float) -> void:
	var n := queued()
	_grinding = n > 0
	if n == 0:
		_acc = 0.0
		return
	_acc += float(TIERS[tier].rate) * dt
	var budget := int(_acc)
	if budget <= 0:
		return
	var burnt := 0
	var bone := 0
	for id in queue.keys():
		if budget <= 0:
			break
		var k := mini(int(queue[id]), budget)
		queue[id] = int(queue[id]) - k
		budget -= k
		_acc -= k
		points += k * float(VALUE.get(id, 0.0))
		ground += k
		if id == "charred":
			burnt += k
		elif id == "bone":
			bone += k
		if int(queue[id]) <= 0:
			queue.erase(id)
	_spray_mat.albedo_color = Color8(70, 66, 62) if burnt > 0 and bone == 0 and not queue.has("meat") else Color8(150, 10, 16)
	if bone > 0:
		_crunch_t -= dt
		if _crunch_t <= 0.0:
			_crunch_t = randf_range(0.12, 0.35)
			arena.sound.play("crunch", global_position + Vector3(0, 1.0, 0), -8.0)
	# (a co-op guest's grinding is for the look: its bags are the host's, from the host, or one could be taken
	# before the host had made it)
	while points >= BAG_POINTS and not _is_guest():
		points -= BAG_POINTS
		bags += 1
		_bag_out()
		_changed()
	if queued() == 0:
		_acc = 0.0
		_changed()

# (the host's, or alone) what's at its mouth taken in
func _mouth() -> void:
	var t: Dictionary = TIERS[tier]
	var box := AABB(AT + (t.mouth[0] as Vector3), t.mouth[1])
	var most := int(t.most)
	for b in arena.bodies.duplicate():
		if not is_instance_valid(b):
			continue
		if b.alive:
			continue
		if not _body_in(b, box):
			continue
		var size: int = b.cubes_left()
		if most > 0 and size > most:
			_too_big(b, size)
			continue
		var counts := {}
		var bits: Array = b.cubes(1, counts)
		_take_in(_items_of(counts, bits))
		arena.bodies.erase(b)
		b.queue_free()
	var pcs: Array = arena.pieces._pieces
	for i in range(pcs.size() - 1, -1, -1):
		var pc: Dictionary = pcs[i]
		if not is_instance_valid(pc.rb):
			continue
		var rb: RigidBody3D = pc.rb
		if not box.has_point(rb.global_position):
			continue
		var counts := {}
		var bits := VoxelPieces.cubes_of(pc, 1, counts)
		var size := bits.size()
		for v in counts:
			size += int(counts[v])
		if most > 0 and size > most:
			_too_big(rb, size)
			continue
		_take_in(_items_of(counts, bits))
		rb.queue_free()
		pcs.remove_at(i)

func _body_in(b: VoxelBody, box: AABB) -> bool:
	for n in b.parts:
		var p: Dictionary = b.parts[n]
		if p.gone:
			continue
		var mi: MeshInstance3D = p.mesh
		if mi.mesh and box.has_point(mi.global_transform * mi.mesh.get_aabb().get_center()):
			return true
	return false

func _too_big(o: Node, size: int) -> void:
	var id := o.get_instance_id()
	if _said.has(id):
		return
	_said[id] = true
	var near: bool = arena.player.global_position.distance_to(AT) < 8.0
	if near:
		arena.say("Too big for the %s (%d cubes; it takes %d): cut it smaller, or upgrade it" % [String(TIERS[tier].name).to_lower(), size, int(TIERS[tier].most)], 3.0)

# cubes by cell value (a colour + 1) and a few bits, as items
static func _items_of(counts: Dictionary, bits: Array) -> Dictionary:
	var out := {}
	for v in counts:
		var k := int(v) - 1
		var id := VoxelItems.of_colour(Color8((k >> 16) & 255, (k >> 8) & 255, k & 255))
		out[id] = int(out.get(id, 0)) + int(counts[v])
	for bt in bits:
		var id2 := VoxelItems.of_colour(bt.col)
		out[id2] = int(out.get(id2, 0)) + 1
	return out

func _take_in(items: Dictionary) -> void:
	var was := queued()
	for id in items:
		if VALUE.has(id):
			queue[id] = int(queue.get(id, 0)) + int(items[id])
	if was == 0 and queued() > 0:
		arena.sound.play("machine_start", global_position + Vector3(0, 0.8, 0), -6.0, [1.3, 1.0, 0.7][tier])
	arena.sound.play("crunch", global_position + Vector3(0, 1.0, 0), -4.0)
	_changed()

func _bag_out() -> void:
	arena.sound.play("bag_drop", global_position + (TIERS[tier].pile as Vector3), -6.0)
	var m := MeshInstance3D.new()
	m.mesh = _bag_mesh()
	m.material_override = _bag_mat()
	add_child(m)
	_falling.append([m, 0.0])

# ---------------------------------------------------------------- what a player does

## What the look lands on: ["machine" / "bags" / "sign", distance], ["", INF] for nothing.
func pick(eye: Vector3, dir: Vector3, reach := 2.6) -> Array:
	var t: Dictionary = TIERS[tier]
	var boxes := {}
	var mb: AABB = [AABB(Vector3(-0.4, 0, -0.35), Vector3(0.8, 1.6, 0.7)), AABB(Vector3(-0.65, 0, -0.55), Vector3(1.3, 2.3, 1.1)),
		AABB(Vector3(-2.1, 0, -0.75), Vector3(3.4, 2.4, 1.5))][tier]
	boxes["machine"] = AABB(AT + mb.position, mb.size)
	var pp: Vector3 = AT + (t.pile as Vector3)
	boxes["bags"] = AABB(pp + Vector3(-0.35, 0, -0.35), Vector3(0.7, 0.6, 0.7))
	var sp: Vector3 = AT + (t.sign as Vector3)
	boxes["sign"] = AABB(sp + Vector3(-0.3, 0.9, -0.1), Vector3(0.6, 0.6, 0.2))
	var best := ""
	var bd := INF
	for k in boxes:
		var hit = (boxes[k] as AABB).intersects_ray(eye, dir)
		if hit != null:
			var d := (hit as Vector3).distance_to(eye)
			if d <= reach and d < bd:
				bd = d
				best = k
	return [best, bd]

func _gore() -> Dictionary:
	var out := {}
	var left := FEED_MOST
	for id in ["meat", "brain", "bone", "charred", "chicken_carcass"]:
		var n: int = mini(arena.inv.count(id), left)
		if n > 0:
			out[id] = n
			left -= n
	return out

func line(tag: String) -> String:
	var t: Dictionary = TIERS[tier]
	match tag:
		"machine":
			var s := String(t.name)
			var q := queued()
			if q > 0:
				s += ": grinding (%d cubes to go)" % q
			var g := _gore()
			if not g.is_empty():
				var n := 0
				for id in g:
					n += int(g[id])
				return s + "     E  put in your gore (%d cubes)" % n
			return s + ("" if q > 0 else ": throw limbs in the top (the gravity gun carries them), or vacuum gore and E")
		"bags":
			return ("E  take %d bag%s of blood and bone" % [bags, "" if bags == 1 else "s"]) if bags > 0 else "Bags of blood and bone drop out here (%d%% to the next)" % int(points / BAG_POINTS * 100.0)
		"sign":
			var s2 := "%s: takes %s, %d cubes a second" % [t.name, ("anything" if int(t.most) == 0 else "up to %d cubes" % int(t.most)), int(t.rate)]
			if tier + 1 >= TIERS.size():
				return s2 + " (the biggest there is)"
			var nx: Dictionary = TIERS[tier + 1]
			var need := ["$%d (%d)" % [int(nx.cash), arena.cash]]
			for id in nx.cost:
				need.append("%d %s (%d)" % [int(nx.cost[id]), VoxelItems.name_of(id).to_lower(), arena.inv.count(id)])
			return ("E  " if _can_upgrade() else "") + "upgrade to the %s: " % String(nx.name).to_lower() + ", ".join(need)
	return ""

func use(tag: String) -> void:
	match tag:
		"machine":
			feed()
		"bags":
			take_bags()
		"sign":
			upgrade()

## E at the machine: the gore in this player's backpack (meat, brain, bone, charred bits, chicken carcasses) put in.
func feed() -> int:
	var g := _gore()
	if g.is_empty():
		arena.say("Nothing to put in: throw in limbs, or vacuum up gore first", 2.0)
		return 0
	var n := 0
	for id in g:
		arena.inv.remove(id, int(g[id]))
		n += int(g[id])
	arena.say("In it goes: %d cubes (about %.1f bags)" % [n, points_of(g) / BAG_POINTS], 2.0)
	if _is_guest():
		_msg(["feed", g])
		for id in g:
			queue[id] = int(queue.get(id, 0)) + int(g[id])        # (shown at once; the host's is the real one)
	else:
		_take_in(g)
	return n

## E at the pile: the bags into this player's backpack.
func take_bags() -> int:
	var n := bags
	if n <= 0:
		return 0
	arena.sound.play("item_pick", Vector3.INF, -4.0)
	arena.say("+%d blood and bone: E at a plant, the worm farm or the chickens' feeder" % n, 2.5)
	bags = 0
	if _is_guest():
		_msg(["take", n])
		return n
	arena.receive({"id": "blood_bone", "n": n}, "inv")
	_changed()
	return n

func _can_upgrade() -> bool:
	if tier + 1 >= TIERS.size():
		return false
	var nx: Dictionary = TIERS[tier + 1]
	if arena.cash < int(nx.cash):
		return false
	for id in nx.cost:
		if arena.inv.count(id) < int(nx.cost[id]):
			return false
	return true

func upgrade() -> bool:
	if tier + 1 >= TIERS.size():
		return false
	if not _can_upgrade():
		arena.say("Not enough: " + line("sign").get_slice(": ", 1), 2.5)
		return false
	var nx: Dictionary = TIERS[tier + 1]
	arena.cash -= int(nx.cash)
	for id in nx.cost:
		arena.inv.remove(id, int(nx.cost[id]))
	arena.stash._dirty = true
	arena.sound.play("hammer_hit", Vector3.INF, -6.0)
	arena.say("Upgraded: the %s (takes %s)" % [String(nx.name).to_lower(), "anything" if int(nx.most) == 0 else "up to %d cubes" % int(nx.most)], 3.0)
	if _is_guest():
		_msg(["up", tier + 1])
	tier += 1
	_show_tier()
	_changed()
	return true

## The bag item for VoxelItems.
static func items() -> Dictionary:
	return {"blood_bone": {"name": "Blood and bone", "col": Color8(140, 60, 50), "stack": 99,
		"desc": "A bag of shredded gore. Feeds a plant (E at it), the worm farm or the chickens' feeder."}}

# ---------------------------------------------------------------- co-op

func _msg(m: Array) -> void:
	if arena.net and arena.net.linked:
		arena.net.send_shredder(m)

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
		"feed":
			if host and typeof(m[1]) == TYPE_DICTIONARY:
				var g := {}
				for id in m[1]:
					if VALUE.has(id):
						g[id] = clampi(int(m[1][id]), 0, FEED_MOST)
				_take_in(g)
		"take":
			if host and bags > 0:
				_msg(["give", {"id": "blood_bone", "n": bags}])
				bags = 0
				_changed()
		"up":
			if host and int(m[1]) == tier + 1 and tier + 1 < TIERS.size():
				tier += 1
				_show_tier()
				_changed()
		"give":
			var g2: Dictionary = m[1]
			if VoxelItems.has(String(g2.get("id", ""))) and int(g2.get("n", 0)) > 0:
				arena.receive({"id": String(g2.id), "n": int(g2.n)}, "inv")

# ---------------------------------------------------------------- saving

func to_data() -> Dictionary:
	return {"tier": tier, "queue": queue.duplicate(), "points": points, "bags": bags, "ground": ground}

func from_data(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	var t0 := tier
	tier = clampi(int(d.get("tier", 0)), 0, TIERS.size() - 1)
	queue = {}
	var q = d.get("queue", {})
	if typeof(q) == TYPE_DICTIONARY:
		for id in q:
			if VALUE.has(id) and int(q[id]) > 0:
				queue[String(id)] = int(q[id])
	points = clampf(float(d.get("points", 0.0)), 0.0, BAG_POINTS)
	var b0 := bags
	bags = maxi(0, int(d.get("bags", 0)))
	ground = maxf(0.0, float(d.get("ground", 0.0)))
	if tier != t0:
		_show_tier()
	if bags > b0 and is_inside_tree() and _is_guest():
		for i in mini(bags - b0, 3):
			_bag_out()

func save_data() -> Dictionary:
	return _own if _own != null else to_data()

# ---------------------------------------------------------------- showing it

func _show(dt: float) -> void:
	var t: Dictionary = TIERS[tier]
	var on := _grinding
	if on:
		arena.sound.loop("shredder", String(t.loop), self, -4.0)
	elif arena.sound.playing("shredder"):
		arena.sound.stop("shredder")
	_spray.emitting = on
	_shake = move_toward(_shake, 1.0 if on else 0.0, dt * 4.0)
	var root: Node3D = _models[tier]
	root.position = Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * 0.008 * _shake * (1.0 + tier)
	for s in _spin[tier]:
		var n: Node3D = s[0]
		n.rotate_object_local(s[1], dt * float(s[2]) * _shake)
	# the bags dropping out and the pile
	var pile_at: Vector3 = t.pile
	var drop_from: Vector3 = [Vector3(0.45, 0.85, 0.0), Vector3(0.8, 0.55, 0.0), Vector3(0.35, 0.45, -0.6)][tier]
	for i in range(_falling.size() - 1, -1, -1):
		var f: Array = _falling[i]
		f[1] = float(f[1]) + dt
		var k := clampf(float(f[1]) / 0.45, 0.0, 1.0)
		var m: MeshInstance3D = f[0]
		m.position = drop_from.lerp(pile_at + Vector3(0, 0.12, 0), k) + Vector3(0, sin(k * PI) * 0.15, 0)
		m.rotation.z = k * 2.0
		if k >= 1.0:
			m.queue_free()
			_falling.remove_at(i)
	var showing := mini(bags - _falling.size(), _pile.size())
	for i in _pile.size():
		var bm: MeshInstance3D = _pile[i]
		bm.visible = i < showing
		bm.position = pile_at + [Vector3(-0.15, 0.12, -0.12), Vector3(0.15, 0.12, -0.1), Vector3(-0.14, 0.12, 0.14), Vector3(0.16, 0.12, 0.15),
			Vector3(0.0, 0.33, 0.0), Vector3(0.02, 0.33, -0.2), Vector3(-0.02, 0.33, 0.2), Vector3(0.0, 0.54, 0.02)][i]
	_pile_label.visible = bags > 0
	_pile_label.text = "%d bag%s" % [bags, "" if bags == 1 else "s"]
	_pile_label.position = pile_at + Vector3(0, 0.95, 0)
	var stain_m: StandardMaterial3D = _stain.material_override
	stain_m.albedo_color.a = clampf(ground / 120000.0, 0.0, 0.7)
	_stain.visible = ground > 0.0
	_sign.text = "%s\n%s" % [String(t.name).to_upper(), "E: upgrade" if tier + 1 < TIERS.size() else "top of the range"]

func _show_tier() -> void:
	if _models.is_empty():
		return
	for i in _models.size():
		var r: Node3D = _models[i]
		r.visible = i == tier
		for c in r.find_children("*", "CollisionShape3D", true, false):
			(c as CollisionShape3D).disabled = i != tier
	var t: Dictionary = TIERS[tier]
	_spray.amount = int(t.spray)          # (here, not every frame: setting it restarts the whole spray)
	_spray.position = [Vector3(0, 1.3, 0), Vector3(0, 1.55, 0), Vector3(1.0, 2.2, 0.3)][tier]
	_spray.direction = [Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0.6, 1, 0.3)][tier]
	_spray.initial_velocity_min = [1.2, 2.0, 4.0][tier]
	_spray.initial_velocity_max = [2.2, 3.5, 7.0][tier]
	_sign_post.position = t.sign
	_stain.scale = Vector3.ONE * [1.0, 1.4, 2.2][tier]

# ---------------------------------------------------------------- building it

func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _box(size: Vector3, at: Vector3, m: Material, parent: Node3D, solid := false) -> Node3D:
	var n: Node3D = StaticBody3D.new() if solid else Node3D.new()
	n.position = at
	parent.add_child(n)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	n.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		n.add_child(cs)
	return n

func _cyl(r_top: float, r_bot: float, h: float, at: Vector3, m: Material, parent: Node3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = m
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static var _bm: Mesh
static var _bmat: StandardMaterial3D
func _bag_mesh() -> Mesh:
	if _bm == null:
		var b := BoxMesh.new()
		b.size = Vector3(0.26, 0.2, 0.18)
		_bm = b
	return _bm

func _bag_mat() -> StandardMaterial3D:
	if _bmat == null:
		_bmat = _mat(Color8(176, 150, 112), 1.0)
	return _bmat

func _build() -> void:
	var wood := _mat(Color8(140, 98, 58), 0.85)
	var iron := _mat(Color8(52, 54, 58), 0.5, 0.7)
	var steel := _mat(Color8(160, 164, 170), 0.35, 0.85)
	var green := _mat(Color8(52, 110, 64), 0.55, 0.3)
	var orange := _mat(Color8(226, 120, 30), 0.5, 0.2)
	var dark := _mat(Color8(40, 40, 44), 0.6, 0.4)
	var rubber := _mat(Color8(24, 24, 24), 0.9)
	# the hand-crank mincer on a wooden stand: a cast-iron body, a bowl on top, the crank, a bucket below its nose
	var m0 := Node3D.new()
	add_child(m0)
	_box(Vector3(0.7, 0.06, 0.55), Vector3(0, 0.84, 0), wood, m0, true)
	for lx in [-0.3, 0.3]:
		for lz in [-0.22, 0.22]:
			_box(Vector3(0.06, 0.82, 0.06), Vector3(lx, 0.41, lz), wood, m0, true)
	_cyl(0.11, 0.11, 0.42, Vector3(0, 1.0, 0), iron, m0, Vector3(0, 0, PI * 0.5))
	_cyl(0.22, 0.07, 0.25, Vector3(0, 1.22, 0), iron, m0)
	_box(Vector3(0.1, 0.14, 0.18), Vector3(0, 0.9, 0), iron, m0)
	var crank := Node3D.new()
	crank.position = Vector3(-0.25, 1.0, 0)
	m0.add_child(crank)
	_box(Vector3(0.03, 0.3, 0.04), Vector3(0, 0.13, 0), iron, crank)
	_cyl(0.025, 0.025, 0.14, Vector3(-0.07, 0.27, 0), wood, crank, Vector3(0, 0, PI * 0.5))
	_cyl(0.12, 0.12, 0.03, Vector3(0.23, 1.0, 0), steel, m0, Vector3(0, 0, PI * 0.5))       # (the cutting plate)
	_box(Vector3(0.2, 0.04, 0.16), Vector3(0.42, 0.93, 0), steel, m0).rotation.z = -0.6     # (the chute off the side)
	_models.append(m0)
	_spin.append([[crank, Vector3.RIGHT, 6.0]])
	# the electric shredder: a green steel box on legs, a hopper, two toothed drums, a motor, a chute out the side
	var m1 := Node3D.new()
	add_child(m1)
	_box(Vector3(0.9, 0.7, 0.8), Vector3(0, 0.85, 0), green, m1, true)
	for lx in [-0.4, 0.4]:
		for lz in [-0.35, 0.35]:
			_box(Vector3(0.08, 0.5, 0.08), Vector3(lx, 0.25, lz), dark, m1, true)
	for side in [[Vector3(0, 1.48, -0.45), Vector3(1.1, 0.05, 0.5), Vector3(-0.85, 0, 0)], [Vector3(0, 1.48, 0.45), Vector3(1.1, 0.05, 0.5), Vector3(0.85, 0, 0)],
			[Vector3(-0.5, 1.48, 0), Vector3(0.5, 0.05, 0.95), Vector3(0, 0, 0.85)], [Vector3(0.5, 1.48, 0), Vector3(0.5, 0.05, 0.95), Vector3(0, 0, -0.85)]]:
		var pnl := _box(side[1], side[0], green, m1)
		pnl.rotation = side[2]
	var drums := []
	for dz in [-0.12, 0.12]:
		var dr := Node3D.new()
		dr.position = Vector3(0, 1.22, dz)
		m1.add_child(dr)
		_cyl(0.1, 0.1, 0.8, Vector3.ZERO, steel, dr, Vector3(0, 0, PI * 0.5))
		for k in 8:
			var tooth := _box(Vector3(0.05, 0.05, 0.05), Vector3(-0.35 + k * 0.1, 0.1, 0), steel, dr)
			tooth.position = Vector3(-0.35 + k * 0.1, cos(k * 1.3) * 0.11, sin(k * 1.3) * 0.11)
		drums.append([dr, Vector3.RIGHT, 9.0 if dz < 0 else -9.0])
	_cyl(0.16, 0.16, 0.45, Vector3(0, 0.95, 0.55), dark, m1, Vector3(PI * 0.5, 0, 0))     # the motor
	_box(Vector3(0.45, 0.05, 0.4), Vector3(0.62, 0.42, 0), steel, m1).rotation.z = -0.5    # the chute
	_models.append(m1)
	_spin.append(drums)
	# the industrial woodchipper: a trailer, wheels, an orange drum housing, the engine, the big feed chute (west), the
	# discharge chute up and out east
	var m2 := Node3D.new()
	add_child(m2)
	_box(Vector3(2.6, 0.14, 1.0), Vector3(0, 0.5, 0), dark, m2, true)
	for wz in [-0.6, 0.6]:
		_cyl(0.32, 0.32, 0.2, Vector3(0.2, 0.32, wz), rubber, m2, Vector3(PI * 0.5, 0, 0))
		_cyl(0.16, 0.16, 0.22, Vector3(0.2, 0.32, wz), steel, m2, Vector3(PI * 0.5, 0, 0))
	_box(Vector3(0.08, 0.08, 1.0), Vector3(1.6, 0.5, 0), dark, m2)          # the drawbar
	_box(Vector3(0.9, 0.95, 0.95), Vector3(0.1, 1.05, 0), orange, m2, true)  # the drum housing
	_box(Vector3(0.65, 0.75, 0.9), Vector3(0.9, 0.95, 0), dark, m2, true)    # the engine
	_box(Vector3(0.06, 0.4, 0.06), Vector3(1.05, 1.5, 0.3), iron, m2)        # the exhaust
	var drum := Node3D.new()
	drum.position = Vector3(0.1, 1.05, -0.49)
	m2.add_child(drum)
	_cyl(0.36, 0.36, 0.04, Vector3.ZERO, steel, drum, Vector3(PI * 0.5, 0, 0))
	for k in 4:
		var spoke := _box(Vector3(0.62, 0.05, 0.02), Vector3.ZERO, iron, drum)
		spoke.rotation.z = k * PI * 0.25
	# the feed chute: a flared box tunnel from the housing out west
	var chute := Node3D.new()
	chute.position = Vector3(-0.35, 0.95, 0)
	m2.add_child(chute)
	_box(Vector3(1.4, 0.05, 1.0), Vector3(-0.7, -0.38, 0), orange, chute, true)
	_box(Vector3(1.4, 0.05, 1.0), Vector3(-0.7, 0.42, 0), orange, chute)
	for cz in [-0.5, 0.5]:
		_box(Vector3(1.4, 0.85, 0.05), Vector3(-0.7, 0.02, cz), orange, chute, true)
	for fz in [-0.62, 0.62]:
		_box(Vector3(0.4, 1.0, 0.05), Vector3(-1.5, 0.02, fz), _mat(Color8(240, 200, 40), 0.5), chute).rotation.y = -0.4 * signf(fz)
	# the discharge chute: up from the housing, bent out east
	_box(Vector3(0.3, 0.9, 0.3), Vector3(0.1, 1.9, 0.0), orange, m2)
	var dis := _box(Vector3(0.7, 0.28, 0.28), Vector3(0.45, 2.35, 0.0), orange, m2)
	dis.rotation.z = -0.35
	_models.append(m2)
	_spin.append([[drum, Vector3.UP, 30.0]])
	# the blood spray, the stain on the ground, the bags' pile, the sign
	_spray = CPUParticles3D.new()
	_spray.amount = 60
	_spray.lifetime = 0.9
	_spray.emitting = false
	_spray.spread = 35.0
	_spray.gravity = Vector3(0, -9.8, 0)
	_spray.scale_amount_min = 0.6
	_spray.scale_amount_max = 1.4
	var pm := BoxMesh.new()
	pm.size = Vector3.ONE * 0.045
	_spray_mat = _mat(Color8(150, 10, 16), 0.3)
	pm.material = _spray_mat
	_spray.mesh = pm
	add_child(_spray)
	_stain = MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.9
	sm.bottom_radius = 0.9
	sm.height = 0.004
	_stain.mesh = sm
	var stm := _mat(Color(0.35, 0.02, 0.03, 0.0), 0.3)
	stm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stain.material_override = stm
	_stain.position = Vector3(0, 0.006, 0)
	add_child(_stain)
	for i in 8:
		var b := MeshInstance3D.new()
		b.mesh = _bag_mesh()
		b.material_override = _bag_mat()
		b.rotation.y = i * 0.7
		b.visible = false
		add_child(b)
		_pile.append(b)
		# (a red stripe: blood and bone)
		var st := MeshInstance3D.new()
		var stb := BoxMesh.new()
		stb.size = Vector3(0.265, 0.05, 0.185)
		st.mesh = stb
		st.material_override = _mat(Color8(150, 30, 30), 1.0)
		b.add_child(st)
	_pile_label = Label3D.new()
	_pile_label.font_size = 32
	_pile_label.pixel_size = 0.003
	_pile_label.outline_size = 8
	_pile_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_pile_label)
	_sign_post = Node3D.new()
	add_child(_sign_post)
	_box(Vector3(0.06, 1.2, 0.06), Vector3(0, 0.6, 0.04), wood, _sign_post)
	_box(Vector3(0.6, 0.45, 0.04), Vector3(0, 1.2, 0), _mat(Color8(230, 220, 190), 0.9), _sign_post)
	_sign = Label3D.new()
	_sign.font_size = 22
	_sign.pixel_size = 0.0025
	_sign.outline_size = 6
	_sign.modulate = Color8(40, 26, 14)
	_sign.outline_modulate = Color8(240, 230, 200)
	_sign.position = Vector3(0, 1.2, -0.03)
	_sign.rotation.y = PI
	_sign.autowrap_mode = TextServer.AUTOWRAP_WORD
	_sign.width = 190.0
	_sign_post.add_child(_sign)
