class_name MineWorm
extends Node3D
## The boss at the bottom of the mine (the owner, 23 Oct): a giant rock worm that lives in the cavern at the bottom and
## wakes when you come down that far. It burrows through anything but bedrock (eating its own tunnels as it goes),
## comes at you wriggling, and bites. Ram it hard, drill into it, or dynamite it; killed, its diamond hoard spills out
## where it died. Once a ground (a fresh claim brings a new one). Owned by the voxel session.

const SEGS := 16
const GAP := 0.6
const HP_MAX := 140.0
const WAKE_ROW := 126           # the ship this deep wakes it
const HOME_ROW := 100           # it doesn't come up past here
const BITE := 14.0
const BODY := 5.0               # hull a second touching its body
const SPEED := 3.0

var mine
var ground: MineGround
var alive := true
var awake := false
var hp := HP_MAX
var head := Vector2()
var dir := Vector2(1, 0)
var _trail: Array[Vector2] = []
var _segs: Array[Node3D] = []
var _seg_p: Array[Vector2] = []
var _cool := 0.0
var _hurt_cool := 0.0
var _t := 0.0
var _roar_t := 0.0
var _dying := -1.0
var _flesh: StandardMaterial3D

func setup(mine_, ground_: MineGround) -> void:
	mine = mine_
	ground = ground_

## A new worm in its cavern (or none, if it's dead on this ground).
func spawn(dead: bool) -> void:
	for s in _segs:
		s.queue_free()
	_segs.clear()
	_seg_p.clear()
	_trail.clear()
	alive = not dead
	awake = false
	hp = HP_MAX
	_dying = -1.0
	if dead:
		return
	var w: Array = ground.features.get("worm", [25.0, 141.5, 11.0, 4.5])
	head = Vector2(float(w[0]), -float(w[1]))
	_flesh = StandardMaterial3D.new()
	_flesh.albedo_color = Color8(150, 110, 120)
	_flesh.roughness = 0.6
	var ring := StandardMaterial3D.new()
	ring.albedo_color = Color8(110, 70, 84)
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color8(255, 220, 60)
	eye.emission_enabled = true
	eye.emission = Color8(255, 200, 40)
	eye.emission_energy_multiplier = 4.0
	var tooth := StandardMaterial3D.new()
	tooth.albedo_color = Color8(240, 230, 210)
	for i in SEGS:
		var n := Node3D.new()
		var r := lerpf(0.55, 0.22, float(i) / SEGS) if i > 0 else 0.62
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		mi.mesh = sm
		mi.material_override = _flesh
		n.add_child(mi)
		var rg := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.92
		tm.outer_radius = r * 1.04
		rg.mesh = tm
		rg.material_override = ring
		rg.rotation.z = PI * 0.5
		n.add_child(rg)
		if i == 0:
			for ey in [0.22, -0.22]:
				var e := MeshInstance3D.new()
				var es := SphereMesh.new()
				es.radius = 0.09
				es.height = 0.18
				e.mesh = es
				e.material_override = eye
				e.position = Vector3(0.3, 0.25, ey + 0.2)
				n.add_child(e)
			for k in 6:
				var t := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0
				cm.bottom_radius = 0.07
				cm.height = 0.3
				t.mesh = cm
				t.material_override = tooth
				var a := (k / 6.0) * TAU
				t.position = Vector3(0.55, cos(a) * 0.3, sin(a) * 0.3)
				t.rotation.z = -PI * 0.5
				n.add_child(t)
		add_child(n)
		_segs.append(n)
		_seg_p.append(head - Vector2(i * GAP, 0))
	for i in SEGS * 4:
		_trail.append(head - Vector2(i * GAP * 0.25, 0))
	_place()

func step(dt: float) -> void:
	if _segs.is_empty():
		return
	_t += dt
	var ship: MineShip = mine.ship
	if _dying >= 0.0:
		_die_step(dt)
		return
	if not alive:
		return
	if not awake:
		if MineGround.tile_of(ship.p).y >= WAKE_ROW:
			awake = true
			mine.sound.play("mine_roar", Vector3.INF, 0.0, 0.8)
			mine.say("Something huge is coming through the rock...", 3.0)
			mine.tip("worm")
			mine.shake(0.6)
		else:
			# asleep: a slow curl about its cavern
			var w: Array = ground.features.get("worm", [25.0, 141.5, 11.0, 4.5])
			var home := Vector2(float(w[0]), -float(w[1]))
			var want := Vector2(cos(_t * 0.3), sin(_t * 0.5) * 0.3)
			if head.distance_to(home) > 5.0:
				want = home - head
			_steer(want, dt, 0.8, 0.6)
			_place()
			return
	_cool = maxf(0.0, _cool - dt)
	_hurt_cool = maxf(0.0, _hurt_cool - dt)
	_roar_t -= dt
	if _roar_t <= 0.0:
		_roar_t = randf_range(5.0, 9.0)
		mine.sound.play("mine_roar", Vector3.INF, -6.0, randf_range(0.7, 1.0))
	var rage := 1.0 if hp > HP_MAX * 0.5 else 1.4
	var goal := ship.p
	if goal.y > -HOME_ROW:
		goal = Vector2(goal.x, -HOME_ROW - 6.0)     # (it won't follow you up: it waits below)
	var to := (goal - head).normalized()
	var wig := Vector2(-to.y, to.x) * sin(_t * 3.0) * 0.6
	_steer(to + wig, dt, SPEED * rage, 2.2 * rage)
	_place()
	# its bite, its body
	var d := head.distance_to(ship.p)
	if d < 0.95 and _cool <= 0.0:
		_cool = 1.1
		mine.hurt(BITE * rage, "worm")
		ship.v += (ship.p - head).normalized() * 8.0 + Vector2(0, 3)
		mine.sound.play("mine_hit", Vector3.INF, 2.0, 0.6)
		mine.shake(0.4)
	var touching := false
	for i in range(2, SEGS):
		if _seg_p[i].distance_to(ship.p) < 0.75:
			touching = true
			break
	if touching:
		mine.hurt(BODY * dt, "worm")
	# what hurts it: ramming it fast, drilling into it
	if _hurt_cool <= 0.0:
		for i in SEGS:
			var gap := _seg_p[i] - ship.p
			var near := gap.length() < 1.05
			var into := ship.v.dot(gap.normalized()) > 3.5
			var tipp := ship.p + (Vector2(ship.drill_dir.x * 0.7, 0.0) if ship.drill_dir.y == 0.0 else Vector2(0.0, -0.7))
			var drill := ship.drilling and tipp.distance_to(_seg_p[i]) < 0.9
			if near and (into or drill):
				hurt(10.0 if into else 6.0)
				_hurt_cool = 0.35
				break

func _steer(want: Vector2, dt: float, speed: float, turn: float) -> void:
	if want.length() < 0.01:
		return
	var a := dir.angle_to(want.normalized())
	dir = dir.rotated(clampf(a, -turn * dt, turn * dt)).normalized()
	var np := head + dir * speed * dt
	# it stays in the ground, below its home, inside the edges
	np.x = clampf(np.x, 1.8, MineGround.W - 1.8)
	np.y = clampf(np.y, -MineGround.D + 1.8, -HOME_ROW + 2.0)
	if np.distance_to(head + dir * speed * dt) > 0.01:
		dir = (np - head).normalized() if (np - head).length() > 0.001 else -dir
	head = np
	# burrowing: what's round its head is eaten away (chunks flying), but not bedrock
	var hc := Vector2(head.x * MineGround.C, -head.y * MineGround.C + MineGround.SKY)
	ground.sim.dig(hc.x, hc.y, 0.9 * MineGround.C, 0.9 * MineGround.C, 0.9 * MineGround.C, 999.0, 9, dt, 0.12, dir.x, -dir.y, false)
	if _trail.is_empty() or _trail[0].distance_to(head) > GAP * 0.25:
		_trail.push_front(head)
		if _trail.size() > SEGS * 5:
			_trail.pop_back()

func _place() -> void:
	# each segment GAP along the trail behind the one before
	_seg_p[0] = head
	var want := GAP
	var acc := 0.0
	var si := 1
	for i in range(1, _trail.size()):
		if si >= SEGS:
			break
		acc += _trail[i].distance_to(_trail[i - 1])
		if acc >= want:
			_seg_p[si] = _trail[i]
			si += 1
			want += GAP
	for i in range(si, SEGS):
		_seg_p[i] = _seg_p[i - 1] - dir * GAP * 0.5
	for i in SEGS:
		var s := _segs[i]
		s.position = Vector3(_seg_p[i].x, _seg_p[i].y + sin(_t * 6.0 - i * 0.7) * 0.05, 0.4)
		var ahead := _seg_p[i - 1] if i > 0 else head + dir
		var f := ahead - _seg_p[i]
		if f.length() > 0.001:
			s.rotation.z = f.angle()
	_flesh.albedo_color = Color8(150, 110, 120).lerp(Color8(255, 255, 255), clampf(_hurt_cool * 2.0, 0.0, 1.0))

func hurt(n: float) -> void:
	if not alive or _dying >= 0.0:
		return
	if not awake:
		awake = true
	hp -= n
	mine.sound.play("mine_roar", Vector3.INF, -3.0, 1.4)
	mine.spark(head, Color8(255, 120, 140))
	if hp <= 0.0:
		hp = 0.0
		_dying = 0.0
		mine.say("THE ROCK WORM IS DEAD! Its diamond hoard spills out", 4.0)
		mine.sound.play("mine_roar", Vector3.INF, 4.0, 0.5)
		mine.shake(1.0)

## Dynamite (or gas) at c, radius r: a big chunk of its health if any of it's in it.
func blast(c: Vector2, r: float) -> void:
	if not alive or _segs.is_empty():
		return
	for p in _seg_p:
		if p.distance_to(c) <= r + 0.6:
			hurt(32.0)
			return

func _die_step(dt: float) -> void:
	_dying += dt
	# the segments pop one after another from the tail
	var gone := int(_dying / 0.12)
	for i in SEGS:
		var k := SEGS - 1 - i
		if i < gone and _segs[k].visible:
			_segs[k].visible = false
			mine.spark(_seg_p[k], Color8(255, 150, 160))
			mine.sound.play("mine_boom", Vector3.INF, -10.0, 1.5)
	if gone >= SEGS:
		alive = false
		_dying = -1.0
		_hoard(head)
		mine.on_worm_dead()

## Its hoard: a heap of loose diamonds tumbling out where it died (clear of the ship)
func _hoard(at: Vector2) -> void:
	var c := MineGround.cell(at)
	var away: Vector2 = at + (at - mine.ship.p).normalized() * 0.6 if at.distance_to(mine.ship.p) < 1.6 else at
	c = MineGround.cell(away)
	ground.sim.deposit(c.x + 0.5, c.y + 0.5, 1.3 * MineGround.C, MineTiles.HOARD, true)
	ground.sim.spray(c.x + 0.5, c.y + 0.5, MineTiles.HOARD, 40, 0.0, -1.0, 2.0)
