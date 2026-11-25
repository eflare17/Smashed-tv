class_name DsBlasts
extends Node3D
## Dynamite at the Dig Site (stage 9): a stick put down and lit (the Dynamite's left click, DsDynamite), its fuse
## hissing and sparking for FUSE seconds (run), then it goes off: a sphere of the ground blown out, bigger in soft
## ground than hard (DsMats.BLAST: dirt all of RADIUS, stone 60%, hard rock less; bedrock and the edge never; a prop
## goes too), a shell round it cracked loose (it slumps); what's blown out is thrown as clods (DsDirt: chunks mostly,
## that fly, bounce, roll and melt into the ground round the crater; dirt physics, stage 7), nothing made or lost. Ore
## isn't thrown: it lies loose in the hole, in whole blocks, to be shovelled up (a clod's dirt melts into the loose
## layer, which is of one material a column). A roof it opens up may cave in (stage 7: it all wakes). Anyone near is
## hurt, nearer worse. The game that runs the ground blows it up and throws the clods; a guest's stick goes to the
## host as an action ("dyn"), and the guest gets a "boom" event for the bang and the flash, and a "clods" one: what
## came out and the host's dirt's random number, from which it throws the same clods itself, with nothing in them
## (dirt physics, stage 8: a couple of hundred lumps in one message, not sent one by one). Owned by the voxel session.

const FUSE := 4.0
const RADIUS := 1.3             # m, in the softest ground
const CRACK := 1.35             # the shell cracked loose, past the hole
const HURT := 70.0              # at the middle
const HURT_R := 4.5             # m out it hurts
const CHUNKS := 22              # (what a guest's shown)
const CHUNK_S := 0.22           # m, one of those's size
const THROW_UP_LO := 3.5        # m/s up the clods are thrown, least and most ...
const THROW_UP_HI := 6.5
const THROW_NEAR := 1.0         # ... to come down this far off, least and most (m, in dirt; less far from a smaller hole):
const THROW_FAR := 2.7          # a quarter falls back in the hole, the rest is its rim and the scatter round it

var site: Node3D                # DigSite
var sticks = {}                # id -> {at, t, node, real}
var flying = []                # a guest's chunks to watch: {node, v}
var clods = true               # (the tests' baseline: false, what's blown out is laid round the crater at once)
var thrown = 0                 # (the tests: clods thrown so far, and the mm in them; what went straight down)
var thrown_mm = 0
var laid_mm = 0
var _out = false               # clods thrown by a blast may still be in the air
var booms = 0                  # (the tests')
var last = {}                  # (the tests: the last blast's {n, cracked, at})
var _seq = 0

func setup(s: Node3D) -> void:
	site = s
	name = "Blasts"
	site.net.register_op("dyn", _dyn_op)
	site.net.register_event("dyn", func(a: Array): _dyn_op(a, false))
	site.net.register_event("boom", func(a: Array): _boom_fx(a[0], float(a[1]), a[2], false))
	site.net.register_event("clods", _clods_in)

## (the Dynamite) a stick put down at p and lit: false if there's none in the backpack
func light(p: Vector3) -> bool:
	var a = site.arena
	if a.inv.count("dynamite") <= 0:
		a.say("No dynamite in your backpack: the site office sells it (X)", 2.0)
		return false
	if not site.net.can_change():
		a.say("Waiting for your mate's ground ...", 1.0)
		return false
	a.inv.remove("dynamite", 1)
	_seq += 1
	var id = "%s%d" % [site.net.role().left(1), _seq]
	site.net.act("dyn", [id, p, FUSE])
	a.say("Lit! Run! (%d s)" % int(FUSE), 1.5)
	return true

# a stick lit (both games: the one that runs the ground blows it up; the other shows it)
func _dyn_op(a: Array, again: bool) -> void:
	if again or a.size() < 3:
		return
	var id = String(a[0])
	if sticks.has(id):
		return
	var real: bool = site.net.runs()
	var node = _stick_node(a[1])
	sticks[id] = {"at": a[1], "t": float(a[2]), "node": node, "real": real}
	site.arena.sound.play("bbq_light", a[1], 0.0, 1.4)
	if real and site.net.role() == "host":
		site.net.event("dyn", a)           # (the guest sees it too; its own comes back: already there)

func _stick_node(at: Vector3) -> Node3D:
	var n = Node3D.new()
	var mi = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = 0.22
	mi.mesh = cm
	var m = StandardMaterial3D.new()
	m.albedo_color = Color8(200, 30, 30)
	mi.material_override = m
	mi.position = Vector3(0, 0.11, 0)
	n.add_child(mi)
	var ps = CPUParticles3D.new()
	ps.amount = 24
	ps.lifetime = 0.4
	ps.direction = Vector3.UP
	ps.spread = 60.0
	ps.initial_velocity_min = 0.5
	ps.initial_velocity_max = 1.5
	ps.gravity = Vector3(0, -3, 0)
	var sm = BoxMesh.new()
	sm.size = Vector3.ONE * 0.015
	var sp = StandardMaterial3D.new()
	sp.albedo_color = Color(1.0, 0.8, 0.3)
	sp.emission_enabled = true
	sp.emission = Color(1.0, 0.6, 0.1)
	sp.emission_energy_multiplier = 3.0
	sm.material = sp
	ps.mesh = sm
	ps.position = Vector3(0, 0.24, 0)
	n.add_child(ps)
	add_child(n)
	n.global_position = at
	return n

func _process(dt: float) -> void:
	if not site.active:
		return
	for id in sticks.keys():
		var s: Dictionary = sticks[id]
		s.t = float(s.t) - dt
		if float(s.t) <= 0.0:
			if is_instance_valid(s.node):
				(s.node as Node).queue_free()
			sticks.erase(id)
			if bool(s.real):
				_blow(s.at)
		elif fmod(float(s.t), 0.5) < dt:
			site.arena.sound.play("dig_scrape", s.at, -12.0, 2.5)   # (the fuse fizzing)
	# (the clods a blast threw: at rest, when there's none awake)
	if _out and (site.dirt == null or site.dirt.awake() == 0):
		_out = false
	# a guest's chunks to watch
	var tr: DsTerrain = site.terrain
	for i in range(flying.size() - 1, -1, -1):
		var f: Dictionary = flying[i]
		var node: Node3D = f.node
		f.v = (f.v as Vector3) + Vector3(0, -9.8 * dt, 0)
		node.global_position += (f.v as Vector3) * dt
		node.rotation += Vector3(3.0, 2.0, 1.0) * dt
		var p = node.global_position
		var top = tr.top_at(p.x, p.z)
		if top == -INF:
			top = 0.0
		if (p.y <= top and float((f.v as Vector3).y) < 0.0) or p.y < -30.0:
			node.queue_free()
			flying.remove_at(i)

# What a blast at `at` blew out (counts: blocks by material, n of them) thrown as clods from the hole: chunks mostly,
# bigger ones as the awake fill up (twice over a fifth of the room, three times over half, as DsDirt.spawn_mass), out
# and up from under the hole's middle. Ore lies in the hole in whole blocks. All of it's kept.
# (`more`: clods to count as awake besides those here: a guest throwing the host's blast, the host's then)
func _throw(at: Vector3, counts: PackedInt32Array, n: int, power: float, more := 0) -> void:
	var tr: DsTerrain = site.terrain
	var d: DsDirt = site.dirt
	var real: bool = d == null or not d.ghost
	var c = tr.to_cells(at)
	var r = DsTerrain.CELL * pow(maxf(1.0, float(n)) * 0.2387, 1.0 / 3.0)     # (a ball of n blocks)
	for m in counts.size():
		var mm: int = counts[m] * DsTerrain.MM
		if mm <= 0:
			continue
		if m >= DsMats.COAL and m <= DsMats.GEM:
			if not real:
				continue
			var put: int = tr.grid.fill_sphere(c, RADIUS / DsTerrain.CELL + 2.0, m, counts[m], true)
			mm -= put * DsTerrain.MM
			laid_mm += put * DsTerrain.MM
			if mm > 0 and d:
				d.lay(at, m, mm)
				laid_mm += mm
			continue
		if d == null:
			continue
		if not clods and real:
			# (the tests' baseline: in a ring round the hole, at once)
			var k = CHUNKS
			for j in k:
				var one = mm / (k - j)
				var a = TAU * j / k
				d.lay(at + Vector3(cos(a), 0, sin(a)) * RADIUS * 1.3, m, one)
				mm -= one
				laid_mm += one
			continue
		while mm >= DsDirt.CRUMB:
			var coarse = 1
			if (d.n + more) * 5 > d.fly_max:
				coarse = 3 if (d.n + more) * 2 > d.fly_max else 2
			var k = d._rnd() % 20
			var one = DsDirt.CHUNK
			if k < 2:
				one = DsDirt.CRUMB
			elif k < 9:
				one = DsDirt.CLOD
			one = mini(one * coarse, mm)
			# from over the hole's middle (the top half of a ball half its size) ...
			var o = Vector3(d.randf01() - 0.5, d.randf01() - 0.5, d.randf01() - 0.5) * 2.0
			if o.length_squared() > 1.0:
				o = o.normalized() * d.randf01()
			var p = at + Vector3(o.x, absf(o.y), o.z) * r * 0.5
			if tr.grid.get_cell(int((p.x - tr.origin.x) / DsTerrain.CELL), int((p.y - tr.origin.y) / DsTerrain.CELL), int((p.z - tr.origin.z) / DsTerrain.CELL)) != 0:
				p = at + Vector3(o.x * 0.1, 0.1, o.z * 0.1)
			# ... up, and out as far as it takes to come down THROW_NEAR to THROW_FAR m off (the small ones further)
			var out = Vector3(o.x, 0.0, o.z)
			if out.length_squared() < 0.0004:
				out = Vector3(1, 0, 0).rotated(Vector3.UP, d.randf01() * TAU)
			var up = lerpf(THROW_UP_LO, THROW_UP_HI, d.randf01())
			var far = lerpf(THROW_NEAR, THROW_FAR, d.randf01()) * power * (1.12 if one <= DsDirt.CLOD else 1.0)
			var vel = out.normalized() * (far * 9.8 / (2.0 * up)) + Vector3(0, up, 0)
			if d.spawn(p, vel, m, one):
				thrown += 1
				thrown_mm += one
			else:
				laid_mm += one
			mm -= one
		if mm > 0:
			d.lay(at, m, mm)
			laid_mm += mm
	_out = d != null and d.awake() > 0

# (the game that runs the ground) the bang: the hole, the cracks, the chunks, the hurt
func _blow(at: Vector3) -> void:
	var tr: DsTerrain = site.terrain
	var got: Dictionary = tr.grid.blast_sphere(tr.to_cells(at), RADIUS / DsTerrain.CELL, PackedFloat32Array(DsMats.BLAST), CRACK)
	var counts: PackedInt32Array = got.counts
	last = {"n": int(got.n), "cracked": int(got.cracked), "at": at}
	# a guest's chunks to watch: each its share of what came out, by material (what's real is the clods: _throw)
	var mats = []
	for m in counts.size():
		if counts[m] > 0:
			mats.append([m, counts[m]])
	var chunks = []
	var k = mini(CHUNKS, maxi(1, int(got.n)))
	for m_n in mats:
		var share = maxi(1, roundi(float(k) * m_n[1] / maxf(1.0, float(got.n))))
		var left: int = m_n[1]
		for j in share:
			var c = left / (share - j)
			left -= c
			if c > 0:
				chunks.append([m_n[0], c])
	var seed = randi()
	var power = clampf(pow(maxf(1.0, float(got.n)) / 2300.0, 1.0 / 3.0), 0.35, 1.2)
	var d: DsDirt = site.dirt
	# (a guest there throws them too, from where the dirt's random numbers are now: they're not sent it one by one)
	var told: bool = d != null and clods and site.net.role() == "host" and site.net.guest_here
	if told:
		site.net.event("clods", [at, counts, int(got.n), power, d._rng, d.n, d.fly_max])
		d.net_tag = DsDirt.N_OWN
	_throw(at, counts, int(got.n), power)
	if d:
		d.net_tag = DsDirt.N_NEW
	_boom_fx(at, RADIUS, [seed, [] if told else chunks], true)
	site.net.event("boom", [at, RADIUS, [seed, [] if told else chunks]])
	site.arena.hurt_players_near(at, HURT_R, HURT)

# the bang, the flash, the dust (both games); a guest's chunks to watch (where the ground runs they're clods: _throw)
func _boom_fx(at: Vector3, r: float, chunks_in: Array, real: bool) -> void:
	booms += 1
	if not site.active:
		return
	var a = site.arena
	a.sound.play("mine_boom", at, 6.0, randf_range(0.9, 1.05))
	a.sound.play("grenades_boom", at, 2.0, 0.8)
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 8.0
	light.omni_range = 10.0
	add_child(light)
	light.global_position = at + Vector3(0, 0.5, 0)
	var tw = light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	tw.tween_callback(light.queue_free)
	if a.player.global_position.distance_to(at) < 12.0:
		a._kick = maxf(a._kick, 1.0 - a.player.global_position.distance_to(at) / 12.0)
	var rng = RandomNumberGenerator.new()
	rng.seed = int(chunks_in[0]) if chunks_in.size() > 0 else 1
	var list: Array = chunks_in[1] if chunks_in.size() > 1 else []
	for c in list:
		if real:
			break
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = Vector3.ONE * CHUNK_S * clampf(sqrt(float(c[1])) / 8.0, 0.6, 1.6)
		mi.mesh = bm
		var m = StandardMaterial3D.new()
		m.albedo_color = DsMats.COL[clampi(int(c[0]), 0, DsMats.COL.size() - 1)]
		mi.material_override = m
		add_child(mi)
		mi.global_position = at + Vector3(rng.randf_range(-0.3, 0.3), 0.2, rng.randf_range(-0.3, 0.3))
		var dir = Vector3(rng.randf_range(-1, 1), rng.randf_range(0.8, 1.6), rng.randf_range(-1, 1)).normalized()
		flying.append({"node": mi, "v": dir * rng.randf_range(4.0, 8.0) * (r / RADIUS), })
	# a cloud of dust
	var ps = CPUParticles3D.new()
	ps.one_shot = true
	ps.amount = 90
	ps.lifetime = 1.4
	ps.explosiveness = 0.95
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = r
	ps.direction = Vector3.UP
	ps.spread = 90.0
	ps.initial_velocity_min = 2.0
	ps.initial_velocity_max = 5.0
	ps.gravity = Vector3(0, -3.0, 0)
	var dm = BoxMesh.new()
	dm.size = Vector3.ONE * 0.09
	var dmat = StandardMaterial3D.new()
	dmat.albedo_color = Color8(140, 112, 84)
	dm.material = dmat
	ps.mesh = dm
	add_child(ps)
	ps.global_position = at
	ps.emitting = true
	ps.finished.connect(ps.queue_free)

# (a guest's) the host's blast's clods thrown here too, as it threw them: the same random numbers, the same sizes,
# nothing in them (DsDirt.ghost). They fly, bounce and roll on this game's copy of the ground and shrink away at rest;
# the dirt itself comes with the host's ground as its own clods land.
func _clods_in(a: Array) -> void:
	var d: DsDirt = site.dirt
	if a.size() < 7 or d == null or not d.ghost or not site.active:
		return
	var was = d._rng
	var most = d.fly_max
	d._rng = int(a[4])
	d.fly_max = int(a[6])
	_throw(a[0], a[1], int(a[2]), float(a[3]), int(a[5]) - d.n)
	d._rng = was
	d.fly_max = most

## Anything still lit or in the air: a stick, a blast's clods not yet at rest, a guest's chunks (the tests, leaving)
func busy() -> bool:
	return not sticks.is_empty() or not flying.is_empty() or _out
