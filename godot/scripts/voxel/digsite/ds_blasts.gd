class_name DsBlasts
extends Node3D
## Dynamite at the Dig Site (stage 9): a stick put down and lit (the Dynamite's left click, DsDynamite), its fuse
## hissing and sparking for FUSE seconds (run), then it goes off: a sphere of the ground blown out, bigger in soft
## ground than hard (DsMats.BLAST: dirt all of RADIUS, stone 60%, hard rock less; bedrock and the edge never; a prop
## goes too), a shell round it cracked loose (it slumps); what's blown out flies as chunks that land as loose blocks
## round the crater (nothing's made or lost: a blasted ore pocket's ore lies there to be shovelled up). A roof it opens
## up may cave in (stage 7: it all wakes). Anyone near is hurt, nearer worse. The game that runs the ground blows it
## up and lands the chunks; a guest's stick goes to the host as an action ("dyn"), and the guest gets "boom" events
## for the bang, the flash and chunks to watch. Owned by the voxel session.

const FUSE := 4.0
const RADIUS := 1.3             # m, in the softest ground
const CRACK := 1.35             # the shell cracked loose, past the hole
const HURT := 70.0              # at the middle
const HURT_R := 4.5             # m out it hurts
const CHUNKS := 22
const CHUNK_S := 0.22           # m, a flying chunk's size

var site: Node3D                # DigSite
var sticks := {}                # id -> {at, t, node, real}
var flying := []                # {node, v, m, n, real}
var booms := 0                  # (the tests')
var last := {}                  # (the tests: the last blast's {n, cracked, at})
var _seq := 0

func setup(s: Node3D) -> void:
	site = s
	name = "Blasts"
	site.net.register_op("dyn", _dyn_op)
	site.net.register_event("dyn", func(a: Array): _dyn_op(a, false))
	site.net.register_event("boom", func(a: Array): _boom_fx(a[0], float(a[1]), a[2], false))

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
	var id := "%s%d" % [site.net.role().left(1), _seq]
	site.net.act("dyn", [id, p, FUSE])
	a.say("Lit! Run! (%d s)" % int(FUSE), 1.5)
	return true

# a stick lit (both games: the one that runs the ground blows it up; the other shows it)
func _dyn_op(a: Array, again: bool) -> void:
	if again or a.size() < 3:
		return
	var id := String(a[0])
	if sticks.has(id):
		return
	var real: bool = site.net.runs()
	var node := _stick_node(a[1])
	sticks[id] = {"at": a[1], "t": float(a[2]), "node": node, "real": real}
	site.arena.sound.play("bbq_light", a[1], 0.0, 1.4)
	if real and site.net.role() == "host":
		site.net.event("dyn", a)           # (the guest sees it too; its own comes back: already there)

func _stick_node(at: Vector3) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = 0.22
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color8(200, 30, 30)
	mi.material_override = m
	mi.position = Vector3(0, 0.11, 0)
	n.add_child(mi)
	var ps := CPUParticles3D.new()
	ps.amount = 24
	ps.lifetime = 0.4
	ps.direction = Vector3.UP
	ps.spread = 60.0
	ps.initial_velocity_min = 0.5
	ps.initial_velocity_max = 1.5
	ps.gravity = Vector3(0, -3, 0)
	var sm := BoxMesh.new()
	sm.size = Vector3.ONE * 0.015
	var sp := StandardMaterial3D.new()
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
	# the chunks in the air
	var tr: DsTerrain = site.terrain
	for i in range(flying.size() - 1, -1, -1):
		var f: Dictionary = flying[i]
		var node: Node3D = f.node
		f.v = (f.v as Vector3) + Vector3(0, -9.8 * dt, 0)
		node.global_position += (f.v as Vector3) * dt
		node.rotation += Vector3(3.0, 2.0, 1.0) * dt
		var p := node.global_position
		var top := tr.top_at(p.x, p.z)
		if top == -INF:
			top = 0.0
		if (p.y <= top and float((f.v as Vector3).y) < 0.0) or p.y < -30.0:
			if bool(f.real):
				var q := _inside(p)
				_dump_spread(q, int(f.m), int(f.n))
			node.queue_free()
			flying.remove_at(i)

# a point kept on the grid (a chunk landing in the field: on the site's edge instead)
func _inside(p: Vector3) -> Vector3:
	var half: float = site.SIZE * 0.5 - 1.2
	return Vector3(clampf(p.x, site.AT.x - half, site.AT.x + half), p.y, clampf(p.z, site.AT.z - half, site.AT.z + half))

## n loose blocks of m dumped at p, spilling over to the columns round it when one's full
func _dump_spread(p: Vector3, m: int, n: int) -> int:
	var tr: DsTerrain = site.terrain
	var left := n
	var r := 0
	while left > 0 and r < 6:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r or left <= 0:
					continue
				left -= tr.dump(p + Vector3(dx, 0, dz) * DsTerrain.CELL, m, mini(left, 24))
		r += 1
	return n - left

# (the game that runs the ground) the bang: the hole, the cracks, the chunks, the hurt
func _blow(at: Vector3) -> void:
	var tr: DsTerrain = site.terrain
	var got: Dictionary = tr.grid.blast_sphere(tr.to_cells(at), RADIUS / DsTerrain.CELL, PackedFloat32Array(DsMats.BLAST), CRACK)
	var counts: PackedInt32Array = got.counts
	last = {"n": int(got.n), "cracked": int(got.cracked), "at": at}
	# the chunks: each carrying its share of what came out, by material
	var mats := []
	for m in counts.size():
		if counts[m] > 0:
			mats.append([m, counts[m]])
	var chunks := []
	var k := mini(CHUNKS, maxi(1, int(got.n)))
	for m_n in mats:
		var share := maxi(1, roundi(float(k) * m_n[1] / maxf(1.0, float(got.n))))
		var left: int = m_n[1]
		for j in share:
			var c := left / (share - j)
			left -= c
			if c > 0:
				chunks.append([m_n[0], c])
	var seed := randi()
	_boom_fx(at, RADIUS, [seed, chunks], true)
	site.net.event("boom", [at, RADIUS, [seed, chunks]])
	site.arena.hurt_players_near(at, HURT_R, HURT)

# the bang, the flash, the dust, the chunks flying (both games; only the one that runs the ground lands them)
func _boom_fx(at: Vector3, r: float, chunks_in: Array, real: bool) -> void:
	booms += 1
	if not site.active:
		return
	var a = site.arena
	a.sound.play("mine_boom", at, 6.0, randf_range(0.9, 1.05))
	a.sound.play("grenades_boom", at, 2.0, 0.8)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 8.0
	light.omni_range = 10.0
	add_child(light)
	light.global_position = at + Vector3(0, 0.5, 0)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	tw.tween_callback(light.queue_free)
	if a.player.global_position.distance_to(at) < 12.0:
		a._kick = maxf(a._kick, 1.0 - a.player.global_position.distance_to(at) / 12.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(chunks_in[0]) if chunks_in.size() > 0 else 1
	var list: Array = chunks_in[1] if chunks_in.size() > 1 else []
	for c in list:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * CHUNK_S * clampf(sqrt(float(c[1])) / 8.0, 0.6, 1.6)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = DsMats.COL[clampi(int(c[0]), 0, DsMats.COL.size() - 1)]
		mi.material_override = m
		add_child(mi)
		mi.global_position = at + Vector3(rng.randf_range(-0.3, 0.3), 0.2, rng.randf_range(-0.3, 0.3))
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.8, 1.6), rng.randf_range(-1, 1)).normalized()
		flying.append({"node": mi, "v": dir * rng.randf_range(4.0, 8.0) * (r / RADIUS), "m": int(c[0]), "n": int(c[1]), "real": real})
	# a cloud of dust
	var ps := CPUParticles3D.new()
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
	var dm := BoxMesh.new()
	dm.size = Vector3.ONE * 0.09
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color8(140, 112, 84)
	dm.material = dmat
	ps.mesh = dm
	add_child(ps)
	ps.global_position = at
	ps.emitting = true
	ps.finished.connect(ps.queue_free)

## Everything still in the air (or lit): the chunks land, the sticks... (the tests, leaving)
func busy() -> bool:
	return not sticks.is_empty() or not flying.is_empty()
