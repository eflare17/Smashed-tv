class_name DsCaves
extends Node3D
## Cave-ins at the Dig Site (stage 7), what you see and hear of them: DigSiteGrid decides (a roof wider than its
## material spans unheld: DsMats.SPAN), this shows it. A roof starting to go creaks and groans and dust trickles down
## from it for the few seconds before it falls (hold it up in time and it settles: stage 8's supports); falling, it
## rumbles, a cloud of dust bursts out, and anyone under it is hurt. In co-op only the host's game decides; the
## guest's is told ("cave" events) and shows the same. Owned by the voxel session.

const HURT := 30.0              # at the middle of a fall, less further out (one fall in 2 s hurts)
const HURT_R := 2.5             # metres round it

var site: Node3D                # DigSite
var _dust := {}                 # key (cell) -> CPUParticles3D trickling till it falls
var warnings := 0               # (the tests')
var falls := 0
var held := 0
var _hurt_ms := -100000

func setup(s: Node3D) -> void:
	site = s
	name = "Caves"
	site.net.register_event("cave", func(a: Array): _show(int(a[0]), a[1], int(a[2])))

## (the game that runs the ground) the grid's news since last time: shown here, sent to the guest
func poll() -> void:
	var tr: DsTerrain = site.terrain
	var ev: PackedInt32Array = tr.grid.take_cave_events()
	for i in range(0, ev.size() - 4, 5):
		var at := tr.centre_of(Vector3i(ev[i + 1], ev[i + 2], ev[i + 3])) + Vector3(0, -0.06, 0)
		_show(ev[i], at, ev[i + 4])
		site.net.event("cave", [ev[i], at, ev[i + 4]])
		if ev[i] == 2 and Time.get_ticks_msec() - _hurt_ms > 2000:
			_hurt_ms = Time.get_ticks_msec()
			site.arena.hurt_players_near(at + Vector3(0, -1.0, 0), HURT_R, HURT)

func _key(at: Vector3) -> String:
	return "%d,%d,%d" % [roundi(at.x * 2.0), roundi(at.y * 2.0), roundi(at.z * 2.0)]

func _show(kind: int, at: Vector3, n: int) -> void:
	if not site.active:
		return
	var snd = site.arena.sound
	match kind:
		1:
			warnings += 1
			snd.play("mine_groan", at, 2.0, randf_range(0.8, 1.0))
			snd.play("mine_crumble", at, -4.0, 1.2)
			var ps := _particles(at, 2.0, false)
			_dust[_key(at)] = ps
			if site.arena.player.global_position.distance_to(at) < 12.0:
				site.arena.say("The roof's creaking! Get out (or hold it up)", 2.5)
		2:
			falls += 1
			_end_dust(at)
			snd.play("mine_collapse", at, 4.0, randf_range(0.9, 1.05))
			_particles(at + Vector3(0, -0.8, 0), 0.0, true)
			if site.arena.player.global_position.distance_to(at) < 10.0:
				site.arena.say("Cave-in! (%d blocks came down)" % n, 2.0)
		3:
			held += 1
			_end_dust(at)
			snd.play("hammer_thud_0", at, -6.0, 0.7)

func _end_dust(at: Vector3) -> void:
	var k := _key(at)
	if _dust.has(k):
		var ps: CPUParticles3D = _dust[k]
		if is_instance_valid(ps):
			ps.emitting = false
			ps.get_tree().create_timer(2.0).timeout.connect(ps.queue_free)
		_dust.erase(k)

# dust: a trickle down from a roof (on till it falls) or a burst out (once)
func _particles(at: Vector3, _secs: float, burst: bool) -> CPUParticles3D:
	var ps := CPUParticles3D.new()
	ps.amount = 120 if burst else 30
	ps.lifetime = 1.6 if burst else 1.2
	ps.one_shot = burst
	ps.explosiveness = 0.9 if burst else 0.0
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = 1.2 if burst else 0.5
	ps.direction = Vector3.UP if burst else Vector3.DOWN
	ps.spread = 80.0 if burst else 15.0
	ps.initial_velocity_min = 1.0 if burst else 0.2
	ps.initial_velocity_max = 3.0 if burst else 0.6
	ps.gravity = Vector3(0, -2.0 if burst else -6.0, 0)
	ps.scale_amount_min = 0.6
	ps.scale_amount_max = 1.6
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * (0.08 if burst else 0.03)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color8(150, 120, 90)
	m.roughness = 1.0
	bm.material = m
	ps.mesh = bm
	add_child(ps)
	ps.global_position = at
	ps.emitting = true
	if burst:
		ps.finished.connect(ps.queue_free)
	return ps
