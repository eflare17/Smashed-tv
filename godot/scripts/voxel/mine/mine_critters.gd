class_name MineCritters
extends Node3D
## The trial hazards that move (the owner, 23 Oct; each one switched on or off in the settings): rats in the sewers
## (they run along the floor and chew the hull; drive over them fast to squash them), the cop bunker's drones (breach
## the bunker and the alarm goes, they chase you through your own tunnels, and if one catches you you're busted: the
## cargo and some cash gone, towed up top; ram one fast and it's scrap) and the rival dealers' crew (pods that patrol
## their tunnels and ram you; ram them back harder and they break up, run and they give up). The chasers find their
## way along the open tiles by a distance map from the ship, made again a few times a second. Owned by the voxel
## session.

const RAT_MAX := 8
const RAT_SPEED := 1.6
const RAT_CHEW := 3.0           # hull a second a rat chewing takes
const DRONES := 3
const DRONE_SPEED := 3.4
const DRONE_GIVE_UP := 50.0     # seconds of chasing
const ALARM_REST := 60.0        # seconds before the bunker can go off again
const PODS := 3
const POD_SPEED := 3.8
const POD_HP := 3
const POD_RAM := 7.0            # hull a pod's ram takes
const SMASH := 4.2              # the ship going this fast at a drone or a pod breaks it
const FIELD_T := 0.35
const FIELD_MAX := 48           # tiles: farther than this the chasers lose the trail

var mine                        # VoxelMine
var ground: MineGround
var rats: Array = []            # {n: Node3D, p: Vector2, dir: int, fall: float}
var drones: Array = []          # {n, p: Vector2, light: OmniLight3D}
var pods: Array = []            # {n, p, hp, cool, chase: bool, dir: Vector2i, home: Vector2}
var alarm := false
var alarm_t := 0.0
var alarm_rest := 0.0
var _field := {}                # tile -> steps from the ship's tile
var _field_t := 0.0
var _rat_t := 0.0
var _flash := 0.0
var _chew_said := 0.0

func setup(mine_, ground_: MineGround) -> void:
	mine = mine_
	ground = ground_

## Everything gone (a new ground, a load).
func clear() -> void:
	for a in [rats, drones, pods]:
		for c in a:
			if is_instance_valid(c.n):
				c.n.queue_free()
		a.clear()
	alarm = false
	alarm_t = 0.0
	mine.sound.stop("mine_siren")

## Going down: the rats and the crew there (if they're switched on), topped up.
func on_enter() -> void:
	if VoxelMine.hazards.get("sewers", true) and ground.flags.get("sewers", true):
		while rats.size() < RAT_MAX:
			if not _spawn_rat():
				break
	if VoxelMine.hazards.get("rivals", true) and ground.flags.get("rivals", true):
		var tries := 0
		while pods.size() < PODS and tries < 40:
			tries += 1
			_spawn_pod()
	if not VoxelMine.hazards.get("sewers", true):
		_drop(rats)
	if not VoxelMine.hazards.get("rivals", true):
		_drop(pods)
	if not VoxelMine.hazards.get("cops", true):
		stand_down()

func _drop(a: Array) -> void:
	for c in a:
		if is_instance_valid(c.n):
			c.n.queue_free()
	a.clear()

# ---------------------------------------------------------------- the distance map

func _make_field(from: Vector2i) -> void:
	_field.clear()
	if MineTiles.solid(ground.at(from.x, from.y)):
		return
	var q := [from]
	_field[from] = 0
	var h := 0
	while h < q.size():
		var c: Vector2i = q[h]
		h += 1
		var d: int = _field[c]
		if d >= FIELD_MAX:
			continue
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if _field.has(n) or n.y < -2 or n.y >= MineGround.D or n.x < 0 or n.x >= MineGround.W:
				continue
			if MineTiles.solid(ground.at(n.x, n.y)):
				continue
			_field[n] = d + 1
			q.append(n)

## Where a chaser at p heads next: the middle of the open tile next to it nearer the ship (p itself: no trail).
func _next(p: Vector2) -> Vector2:
	var t := MineGround.tile_of(p)
	if not _field.has(t):
		return p
	var best := t
	var bd: int = _field[t]
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = t + o
		if _field.has(n) and int(_field[n]) < bd:
			bd = _field[n]
			best = n
	if best == t:
		return mine.ship.p
	return MineGround.centre(best.x, best.y)

# ---------------------------------------------------------------- each step

func step(dt: float) -> void:
	var ship: MineShip = mine.ship
	_flash += dt
	_field_t -= dt
	if _field_t <= 0.0 and (alarm or not pods.is_empty()):
		_field_t = FIELD_T
		_make_field(MineGround.tile_of(ship.p))
	_rats(dt, ship)
	_cops(dt, ship)
	_pods(dt, ship)

func _rats(dt: float, ship: MineShip) -> void:
	_chew_said -= dt
	var chewing := 0
	for i in range(rats.size() - 1, -1, -1):
		var r: Dictionary = rats[i]
		var t := MineGround.tile_of(r.p)
		# falling, if what it ran on is dug away
		if not ground.solid_at(t.x, t.y + 1):
			r.p.y -= dt * 6.0
			r.n.position = Vector3(r.p.x, r.p.y, 0.1)
			if r.p.y < -MineGround.D:
				r.n.queue_free()
				rats.remove_at(i)
			continue
		else:
			r.p.y = -t.y - 1.0 + 0.1
		var to_ship: Vector2 = ship.p - r.p
		if absf(to_ship.y) < 1.2 and absf(to_ship.x) < 6.0:
			r.dir = 1 if to_ship.x > 0.0 else -1
		var nx: float = r.p.x + r.dir * RAT_SPEED * dt
		var ahead := floori(nx + r.dir * 0.2)
		if ground.solid_at(ahead, t.y) or not ground.solid_at(ahead, t.y + 1):
			r.dir = -r.dir
		else:
			r.p.x = nx
		r.n.position = Vector3(r.p.x, r.p.y, 0.1)
		r.n.rotation.y = 0.0 if r.dir > 0 else PI
		r.n.get_child(0).position.y = absf(sin(_flash * 14.0 + i)) * 0.03
		# on the ship: chewing, unless it's squashed
		var d: Vector2 = ship.p - r.p
		if absf(d.x) < 0.55 and absf(d.y) < 0.55:
			if ship.v.length() > 2.5 or ship.drilling:
				mine.sound.play("mine_rat", Vector3.INF, -2.0, 0.8)
				mine.say("Squashed a rat", 1.2)
				r.n.queue_free()
				rats.remove_at(i)
				continue
			chewing += 1
	if chewing > 0:
		mine.hurt(RAT_CHEW * chewing * dt, "rats")
		if _chew_said <= 0.0:
			_chew_said = 1.6
			mine.sound.play("mine_rat", Vector3.INF, -4.0, randf_range(0.9, 1.3))
			mine.say("Rats are chewing the hull! Drive over them", 1.5)
	# more come out of the sewers while you're away from them
	_rat_t -= dt
	if _rat_t <= 0.0:
		_rat_t = 20.0
		if rats.size() < RAT_MAX and VoxelMine.hazards.get("sewers", true) and ground.flags.get("sewers", true) and ship.p.y < -16.0:
			_spawn_rat()

func _spawn_rat() -> bool:
	var sw: Array = ground.features.get("sewer", [])
	if sw.is_empty():
		return false
	var s: Array = sw[randi() % sw.size()]
	var x := randi_range(int(s[0]), int(s[2]))
	var r := int(s[1]) + 0     # (the tunnel's floor row)
	if ground.at(x, r) != MineTiles.AIR or not ground.solid_at(x, r + 1):
		return false
	var n := Node3D.new()
	var body := Node3D.new()
	n.add_child(body)
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color8(90, 80, 74)
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.09
	cm.height = 0.36
	mi.mesh = cm
	mi.rotation.z = PI * 0.5
	mi.material_override = fur
	mi.position.y = 0.09
	body.add_child(mi)
	var tail := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.012
	tm.bottom_radius = 0.02
	tm.height = 0.3
	tail.mesh = tm
	var pink := StandardMaterial3D.new()
	pink.albedo_color = Color8(220, 150, 150)
	tail.material_override = pink
	tail.rotation.z = 1.2
	tail.position = Vector3(-0.28, 0.06, 0)
	body.add_child(tail)
	var eye := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	eye.mesh = sm
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	red.emission_enabled = true
	red.emission = Color.RED
	red.emission_energy_multiplier = 3.0
	eye.material_override = red
	eye.position = Vector3(0.17, 0.13, 0.07)
	body.add_child(eye)
	add_child(n)
	var p := Vector2(x + 0.5, -r - 1.0 + 0.1)
	n.position = Vector3(p.x, p.y, 0.1)
	rats.append({"n": n, "p": p, "dir": 1 if randf() < 0.5 else -1})
	return true

# ---------------------------------------------------------------- the cops

## In the bunker (or drilling its walls): the alarm.
func check_bunker(tile: Vector2i, drilled_wall: bool) -> void:
	if alarm or alarm_rest > 0.0 or not VoxelMine.hazards.get("cops", true):
		return
	var b: Array = ground.features.get("bunker", [])
	if b.is_empty():
		return
	var inside := tile.x > int(b[0]) and tile.x < int(b[2]) and tile.y > int(b[1]) and tile.y < int(b[3])
	if inside or drilled_wall:
		_raise_alarm()

func _raise_alarm() -> void:
	alarm = true
	alarm_t = 0.0
	var b: Array = ground.features.bunker
	mine.say("ALARM! The cops are coming: get out of here!", 3.0)
	mine.tip("cops")
	for k in DRONES:
		var p := Vector2(lerpf(float(b[0]) + 1.5, float(b[2]) - 1.5, (k + 0.5) / DRONES), -float(b[1]) - 1.6)
		drones.append(_make_drone(p))
	_field_t = 0.0

func _make_drone(p: Vector2) -> Dictionary:
	var n := Node3D.new()
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color8(30, 34, 46)
	shell.metallic = 0.6
	shell.roughness = 0.4
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.22, 0.4)
	mi.mesh = bm
	mi.material_override = shell
	n.add_child(mi)
	for sx in [-0.28, 0.28]:
		var rot := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.16
		cm.height = 0.02
		rot.mesh = cm
		rot.material_override = shell
		rot.position = Vector3(sx, 0.14, 0)
		n.add_child(rot)
	var lamp := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.24, 0.07, 0.12)
	lamp.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.emission_enabled = true
	lmat.emission_energy_multiplier = 4.0
	lamp.material_override = lmat
	lamp.position = Vector3(0, 0.15, 0.1)
	n.add_child(lamp)
	var lt := OmniLight3D.new()
	lt.omni_range = 3.5
	lt.light_energy = 2.0
	lt.position = Vector3(0, 0.2, 0.6)
	n.add_child(lt)
	add_child(n)
	n.position = Vector3(p.x, p.y, 0.0)
	return {"n": n, "p": p, "light": lt, "lamp": lmat}

func _cops(dt: float, ship: MineShip) -> void:
	alarm_rest = maxf(0.0, alarm_rest - dt)
	if not alarm:
		return
	alarm_t += dt
	mine.sound.loop("mine_siren", "mine_siren", null, -8.0)
	if ship.p.y > -0.3 or alarm_t > DRONE_GIVE_UP or drones.is_empty():
		var lost := not drones.is_empty()
		stand_down()
		if lost:
			mine.say("The cops lost you", 2.0)
		return
	var blue := fmod(_flash, 0.5) < 0.25
	for i in range(drones.size() - 1, -1, -1):
		var d: Dictionary = drones[i]
		var to := _next(d.p)
		var step := to - (d.p as Vector2)
		var sp := DRONE_SPEED * (1.0 if _field.has(MineGround.tile_of(d.p)) else 0.3)
		if step.length() > 0.001:
			d.p += step.normalized() * minf(step.length(), sp * dt)
		d.n.position = Vector3(d.p.x, d.p.y + sin(_flash * 6.0 + i) * 0.05, 0.0)
		var c := Color(0.2, 0.4, 1.0) if (blue != (i % 2 == 1)) else Color(1.0, 0.15, 0.1)
		d.light.light_color = c
		d.lamp.emission = c
		d.lamp.albedo_color = c
		if (d.p as Vector2).distance_to(ship.p) < 0.65:
			if ship.v.length() > SMASH:
				mine.sound.play("mine_boom", Vector3.INF, -6.0, 1.6)
				mine.say("Smashed a cop drone!", 1.5)
				mine.spark(d.p, Color(0.3, 0.5, 1.0))
				d.n.queue_free()
				drones.remove_at(i)
			else:
				mine.busted()
				return

## The alarm off, the drones gone (busted, given up, a new ground).
func stand_down() -> void:
	for d in drones:
		if is_instance_valid(d.n):
			d.n.queue_free()
	drones.clear()
	if alarm:
		alarm_rest = ALARM_REST
	alarm = false
	if mine and mine.sound:
		mine.sound.stop("mine_siren")

# ---------------------------------------------------------------- the rivals

func _spawn_pod() -> void:
	var cells: Array = ground.features.get("rival", [])
	if cells.is_empty():
		return
	var c: Vector2i = cells[randi() % cells.size()]
	if ground.at(c.x, c.y) != MineTiles.AIR:
		return
	var n := Node3D.new()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color8(150, 30, 40)
	paint.metallic = 0.4
	paint.roughness = 0.5
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.5
	mi.mesh = sm
	mi.material_override = paint
	n.add_child(mi)
	var ram := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.36, 0.42)
	ram.mesh = bm
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color8(160, 160, 170)
	steel.metallic = 0.9
	ram.material_override = steel
	ram.position = Vector3(0.3, -0.02, 0)
	n.add_child(ram)
	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.18, 0.06, 0.05)
	eye.mesh = em
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color8(255, 210, 60)
	glow.emission_enabled = true
	glow.emission = Color8(255, 190, 40)
	glow.emission_energy_multiplier = 3.0
	eye.material_override = glow
	eye.position = Vector3(0.12, 0.1, 0.28)
	n.add_child(eye)
	add_child(n)
	var p := MineGround.centre(c.x, c.y)
	n.position = Vector3(p.x, p.y, 0)
	pods.append({"n": n, "p": p, "hp": POD_HP, "cool": 0.0, "chase": false, "dir": Vector2i(1 if randf() < 0.5 else -1, 0), "go": p, "face": 1})

func _pods(dt: float, ship: MineShip) -> void:
	for i in range(pods.size() - 1, -1, -1):
		var d: Dictionary = pods[i]
		d.cool = maxf(0.0, float(d.cool) - dt)
		var t := MineGround.tile_of(d.p)
		var dist := int(_field.get(t, 999))
		if not d.chase and dist <= 14 and (d.p as Vector2).distance_to(ship.p) < 9.0:
			d.chase = true
			mine.say("The rival crew's coming for you: ram them back harder, or run", 2.5)
			mine.tip("rivals")
		elif d.chase and (dist > 24 or ship.p.y > -0.3):
			d.chase = false
		var to: Vector2 = d.go
		var sp := POD_SPEED
		if d.chase and d.cool <= 0.0:
			to = _next(d.p)
		elif d.cool > 0.0:
			sp = 1.5
			to = d.p + ((d.p as Vector2) - ship.p).normalized() * 0.5     # (backing off after a ram)
		else:
			sp = 1.4
			# patrolling: along the tunnel, turning at its ends
			if (d.p as Vector2).distance_to(d.go) < 0.05:
				var nt: Vector2i = t + d.dir
				if MineTiles.solid(ground.at(nt.x, nt.y)) or randf() < 0.05:
					var opts := []
					for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if not MineTiles.solid(ground.at(t.x + o.x, t.y + o.y)) and ground.bg_at(t.x + o.x, t.y + o.y) == MineTiles.BG_RIVAL:
							opts.append(o)
					if not opts.is_empty():
						d.dir = opts[randi() % opts.size()]
					nt = t + d.dir
				if not MineTiles.solid(ground.at(nt.x, nt.y)):
					d.go = MineGround.centre(nt.x, nt.y)
			to = d.go
		var step := to - (d.p as Vector2)
		if step.length() > 0.001:
			var mv := step.normalized() * minf(step.length(), sp * dt)
			var np: Vector2 = d.p + mv
			if not MineTiles.solid(ground.at(MineGround.tile_of(np).x, MineGround.tile_of(np).y)):
				d.p = np
			if absf(mv.x) > 0.001:
				d.face = 1 if mv.x > 0.0 else -1
		d.n.position = Vector3(d.p.x, d.p.y + sin(_flash * 4.0 + i * 2.0) * 0.04, 0.0)
		d.n.rotation.y = 0.0 if int(d.face) > 0 else PI
		# a ram
		var gap: Vector2 = ship.p - d.p
		if gap.length() < 0.72 and d.cool <= 0.0:
			var dir := gap.normalized() if gap.length() > 0.01 else Vector2(1, 0)
			var mine_in := -ship.v.dot(dir)           # the ship's speed into the pod
			d.cool = 1.3
			if mine_in > SMASH * 0.6:
				d.hp -= 1
				mine.sound.play("mine_hit", Vector3.INF, -2.0, 0.8)
				mine.spark(d.p, Color(1.0, 0.6, 0.2))
				d.p -= dir * 0.6
				if d.hp <= 0:
					mine.sound.play("mine_boom", Vector3.INF, -4.0, 1.2)
					mine.say("Rammed their pod to bits! +$60 scrap", 2.0)
					mine.pay(60)
					d.n.queue_free()
					pods.remove_at(i)
					continue
				mine.say("Rammed them! (%d more)" % int(d.hp), 1.2)
			else:
				mine.hurt(POD_RAM, "rammed")
				ship.v += dir * 6.0
				mine.sound.play("mine_hit", Vector3.INF, 0.0, 0.7)
				mine.say("Rammed by the rival crew!", 1.2)

## Dynamite (or a gas pocket) at c, radius r: what's in it is gone.
func blast(c: Vector2, r: float) -> int:
	var n := 0
	for a in [rats, drones, pods]:
		for i in range(a.size() - 1, -1, -1):
			if (a[i].p as Vector2).distance_to(c) <= r:
				a[i].n.queue_free()
				a.remove_at(i)
				n += 1
	return n
