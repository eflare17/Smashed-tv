class_name VoxelParkInvasion
extends Node
## "Luna Park: Invasion" (the owner, 24 Nov: "an option to have enemies in Luna Park": enemies riding the rides that
## you have to kill, and enemies in the park that come as you get near each part of it). Picked on the phone.
##
## On every ride with seats, a third to a half of the people riding are arena enemies instead (the scenery rider hidden
## the way the Carousel's thrown one is). They're real VoxelBody enemies, put on their seat every frame (marked
## "riding": the arena doesn't walk them), so every weapon hits them where they're drawn and they fall off as bodies
## and pieces. Throwers throw at you from the ride; the rest jump off and come at you when you're within GET_OFF m or
## one of their ride's riders is hit. A rider further than NEAR_ON m isn't made yet (and is put away again past
## NEAR_OFF, if nobody's touched it), so only the rides round you cost anything.
##
## Each part of the park (every ride, the Ghost Train, Luna Palace, the forecourt) has a group of 3 to 6 that comes in
## out of sight the first time you're within AREA_R m of it, and a few more one at a time while its ride still has
## riders on it. Clearing a ride pays RIDE_CASH; clearing the lot shows your time and kills, the best time kept in
## user://. Going down doesn't end it. The phone's Home (or St Kilda, or the other game) stops it and puts the
## scenery riders back.

const FILL := 0.4                # of a ride's riders that are enemies ...
const MIN_RIDERS := 2            # ... this many at least (or every one, on a ride with fewer)
const GET_OFF := 8.0             # m: you this near a rider and it jumps off
const NEAR_ON := 60.0            # m: riders nearer than this are made ...
const NEAR_OFF := 75.0           # ... and put away again past this (untouched ones)
const AREA_R := 25.0             # m from a part of the park: its group comes
const GROUP := Vector2i(3, 6)
const MORE_EVERY := 14.0         # s between the extra ones while an area's ride still has riders
const MORE_MAX := 3              # extra ones an area at most
const MORE_R := 45.0             # (only while you're this near it)
const MAX_ALIVE := 24            # about this many bodies alive at once (the ones on the ground wait their turn)
const SPAWN_GAP := 0.3
const FAR := 14.0                # m from you at least, where the ground ones come in
const RIDE_CASH := 20
const THROW_R := Vector2(3.5, 26.0)     # m: a thrower on a ride throws at you this near
const HOP_H := 2.5               # a seat lower than this: a hop down; higher: a fall
const RIDER_KINDS := ["grunt", "swarmer", "batter", "thrower", "grunt", "batter", "thrower", "swarmer"]
const BEST_FILE := "user://stkilda_invasion.cfg"
const RIDE_NAMES := {"Carousel": "Carousel", "SkyRider": "Sky Rider", "Supernova": "Supernova", "PharaohsCurse": "Pharaoh's Curse",
	"ConeyDrop": "Coney Drop", "Spider": "Spider", "PowerSurge": "Power Surge", "ArabianMerry": "Arabian Merry",
	"SkScenicRailway": "Scenic Railway"}
const HIPS := 0.88               # a scenery rider's hips above their feet (SkLunaRides._seat)

enum { SEATED, HOPPING, OFF, DEAD }

var sk: VoxelStKilda
var running := false
var over := false                # cleared: the banner's up
var kills := 0
var time := 0.0
var best_time := 0.0             # (0: none yet)
var seed_ := 0                   # (tests: the same riders and groups every time; 0: different each game)
var rides: Array = []            # {name, title, node, riders: [rec], cleared, alert}
var areas: Array = []            # {name, at: Vector3, ride: int (-1 none), n, done, more, more_t}
var cleared := 0
var paid := 0                    # $ paid for rides cleared, this game
var _recs: Array = []            # every rider: {ride, kind, state, body, hp0, at (a seat: see _seat_xf), legs, prev, off_t, ...}
var _ground: Array = []          # the ones on the ground (the areas' groups), alive or lying
var _due: Array = []             # area numbers, one for each still to come in
var _gap := 0.0
var _hidden: Array = []          # [a Riders' seat, where they sat]: the scenery riders taken off
var _rng := RandomNumberGenerator.new()
var _hud: Label
var _end: Label

func setup(s: VoxelStKilda) -> void:
	sk = s
	name = "Invasion"
	process_priority = 100       # (after the rides have turned this frame: the riders put on where their seats are now)
	var cf := ConfigFile.new()
	if cf.load(BEST_FILE) == OK:
		best_time = float(cf.get_value("best", "time", 0.0))
	_hud = _label(26, Color("#ffd54a"), 8)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.offset_left = -460
	_hud.offset_right = 460
	_hud.offset_top = 64
	_end = _label(30, Color.WHITE, 10)
	_end.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end.offset_left = -400
	_end.offset_right = 400
	_end.offset_top = -250
	_end.offset_bottom = -60

func _label(size: int, c: Color, outline: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.visible = false
	sk.arena._hud_layer.add_child(l)
	return l

## Off we go (you're in St Kilda).
func start() -> void:
	stop()
	if sk.game:
		sk.game.stop()                       # (not both games at once)
	if seed_ != 0:
		_rng.seed = seed_
	else:
		_rng.randomize()
	if not sk.nav.ready_:
		sk.nav.bake()
	sk.game._find_spots()                    # (where the ground ones come in: inside the wall, the Ghost Train's door)
	_find_rides()
	_find_areas()
	running = true
	over = false
	kills = 0
	time = 0.0
	cleared = 0
	paid = 0
	_gap = 0.0
	_hud.visible = true
	_end.visible = false
	_hud_line()

## Stopped (going home, another game, starting again): its enemies gone, the scenery riders back on their seats.
func stop() -> void:
	var was := running or over
	running = false
	over = false
	if _hud:
		_hud.visible = false
		_end.visible = false
	var touched := {}
	for h in _hidden:
		(h[0] as Array)[2] = h[1]
		touched[h[2]] = true
	_hidden.clear()
	for r in touched:
		if is_instance_valid(r):
			(r as SkLunaRides.Riders).follow()
	rides.clear()
	areas.clear()
	_recs.clear()
	_ground.clear()
	_due.clear()
	if was:
		sk.clear_park()

## Enemies still to kill: on the rides, on the ground, and the groups that haven't come yet.
func left() -> int:
	var n := _due.size()
	for rec in _recs:
		if rec.state != DEAD:
			n += 1
	for b in _ground:
		if is_instance_valid(b) and b.alive:
			n += 1
	for a in areas:
		if not a.done:
			n += int(a.n)
	return n

## The riders still on their seats (made or not).
func seated() -> int:
	var n := 0
	for rec in _recs:
		if rec.state == SEATED:
			n += 1
	return n

# ---------------------------------------------------------------- the rides, their seats

func _find_rides() -> void:
	var by_ride := {}                        # the ride's node -> [its Riders]
	for r in _all_riders(sk):
		var top: Node = r
		while top.get_parent() != sk and top.get_parent() != null:
			top = top.get_parent()
		if not by_ride.has(top):
			by_ride[top] = []
		(by_ride[top] as Array).append(r)
	for c in sk.get_children():              # (in the order they were built: the same every time)
		if by_ride.has(c):
			var ride := _new_ride(c)
			var seats := []
			for r: SkLunaRides.Riders in by_ride[c]:
				var legs := 1.0
				var m := r.material_override as ShaderMaterial
				if m and m.get_shader_parameter("legs") != null:
					legs = float(m.get_shader_parameter("legs"))
				for i in r.seats.size():
					if ((r.seats[i] as Array)[2] as Transform3D).basis.get_scale().x >= 0.01:      # (not one thrown off already)
						seats.append([r, i, legs])
			var want := mini(seats.size(), maxi(MIN_RIDERS, roundi(seats.size() * FILL)))
			# (spread round the ride: every few seats, from a seat picked by the game's seed)
			var first := _rng.randi() % maxi(1, seats.size())
			var touched := {}
			for k in want:
				var s: Array = seats[(first + k * seats.size() / want) % seats.size()]
				var r: SkLunaRides.Riders = s[0]
				var seat: Array = r.seats[s[1]]
				_hidden.append([seat, seat[2], r])
				_add_rider(ride, {"riders": r, "i": s[1], "xf": seat[2]}, float(s[2]))
				var xf: Transform3D = seat[2]
				seat[2] = Transform3D(xf.basis.scaled(Vector3.ONE * 0.001), xf.origin)      # (as the Carousel's thrown one)
				touched[r] = true
			for r in touched:
				(r as SkLunaRides.Riders).follow()
		elif c is Node3D and c.name == "SkScenicRailway":
			# the coaster's trains carry nobody: two to a train (the second row of the front car, the front of the back one)
			var ride := _new_ride(c)
			for t in c.get_children():
				if not (t is SkScenicRailway.Train):
					continue
				var cars: Array = (t as SkScenicRailway.Train)._cars
				for k in mini(2, cars.size()):
					var x := 0.45 if k == 0 else -0.45
					var z := -0.42 if k == 0 else -1.04
					_add_rider(ride, {"car": cars[k], "xf": Transform3D(Basis.IDENTITY, Vector3(x, 1.02 - HIPS, z))}, 1.0)

func _all_riders(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is SkLunaRides.Riders:
			out.append(c)
		else:
			out.append_array(_all_riders(c))
	return out

func _new_ride(n: Node) -> Dictionary:
	var ride := {"name": String(n.name), "title": String(RIDE_NAMES.get(String(n.name), String(n.name))), "node": n, "riders": [],
		"cleared": false, "alert": false, "i": rides.size()}
	rides.append(ride)
	return ride

func _add_rider(ride: Dictionary, at: Dictionary, legs: float) -> void:
	var rec := {"ride": int(ride.i), "kind": RIDER_KINDS[_rng.randi() % RIDER_KINDS.size()], "state": SEATED, "body": null,
		"at": at, "legs": legs, "prev": Vector3.INF, "v": Vector3.ZERO, "wait": INF, "hop": 0.0, "made": false, "fall": false, "hp0": 0.0, "cb": Callable(), "from": Vector3.ZERO, "to": Vector3.ZERO}
	(ride.riders as Array).append(rec)
	_recs.append(rec)

## Where a rider's seat is now (the world): a scenery rider's frame, their feet at its origin, facing its -z.
func _seat_xf(rec: Dictionary) -> Transform3D:
	var at: Dictionary = rec.at
	if at.has("car"):
		return (at.car as Node3D).global_transform * (at.xf as Transform3D)
	var r: SkLunaRides.Riders = at.riders
	var s: Array = r.seats[int(at.i)]
	var on := Transform3D.IDENTITY           # (as Riders.follow)
	if s[0] is MultiMesh:
		on = (s[0] as MultiMesh).get_instance_transform(s[1])
	elif s[0] is Node3D:
		on = (s[0] as Node3D).transform
	return r.global_transform * on * (at.xf as Transform3D)

## The enemy's own frame on that seat: upright in the seat's frame, its hips where the scenery rider's were.
func _body_xf(b: VoxelBody, seat: Transform3D) -> Transform3D:
	var basis := seat.basis.orthonormalized()
	var hip_y: float = b.model.bone_pivot[maxi(0, b.model.bone("hips"))].y * b.model.voxel_m
	return Transform3D(basis, seat * Vector3(0, HIPS, 0) - basis * Vector3(0, hip_y, 0))

func _seen(rec: Dictionary) -> bool:
	var at: Dictionary = rec.at
	var n: Node3D = at.car if at.has("car") else at.riders
	return n.is_visible_in_tree()

# a rider made: a real enemy, sat on its seat
func _make(rec: Dictionary, seat: Transform3D) -> void:
	var b := sk.arena.spawn_kind(String(rec.kind), seat.origin)
	b.set_meta("park", true)
	b.set_meta("riding", true)
	b.sit = float(rec.legs)
	b.yaw = PI                                # (a body faces its +z; the seat's front is its -z)
	b.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF      # (moved by the frame, with the ride)
	b.global_transform = _body_xf(b, seat)
	b.act_cool = _rng.randf_range(0.5, 2.5)
	rec.body = b
	rec.hp0 = b.hp
	rec.prev = Vector3.INF
	rec.cb = _rider_died.bind(rec)
	b.died.connect(rec.cb, CONNECT_ONE_SHOT)

func _rider_died(_b: VoxelBody, rec: Dictionary) -> void:
	if not running or rec.state == DEAD:
		return
	var was_on: bool = rec.state == SEATED
	rec.state = DEAD
	kills += 1
	var ride: Dictionary = rides[int(rec.ride)]
	if was_on:
		_alert(ride)
	rec.fall = true                           # (still on the seat: let go of next frame, _riders_step)
	if not ride.cleared and (ride.riders as Array).all(func(r): return r.state == DEAD):
		ride.cleared = true
		cleared += 1
		sk.arena.cash += RIDE_CASH
		paid += RIDE_CASH
		sk.arena.stash._dirty = true
		sk.arena.stash._save_t = 0.0
		sk.arena.sound.play("gold_find", Vector3.INF, -2.0)
		sk.arena.say("%s cleared   +$%d" % [ride.title, RIDE_CASH], 3.0)

# one of a ride's riders hit: the rest of them (not the throwers) get off, one after another
func _alert(ride: Dictionary) -> void:
	if ride.alert:
		return
	ride.alert = true
	for rec in ride.riders:
		if rec.state == SEATED and rec.kind != "thrower" and float(rec.wait) == INF:
			rec.wait = _rng.randf_range(0.15, 1.6)

# a body let go of its seat: upright in the world again (about its middle), walked or thrown by the arena from here
func _let_go(b: VoxelBody) -> void:
	var xf := b.global_transform
	var mid := xf * Vector3(0, b.height * 0.5, 0)
	var fwd := xf.basis * Vector3(sin(b.yaw), 0, cos(b.yaw))
	b.remove_meta("riding")
	b.sit = -1.0
	b.visible = true
	b.global_transform = Transform3D(Basis.IDENTITY, mid - Vector3(0, b.height * 0.5, 0))
	if Vector2(fwd.x, fwd.z).length() > 0.05:
		b.yaw = atan2(fwd.x, fwd.z)
	b.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	b.reset_physics_interpolation()

# off the ride and at you: a hop down from a low seat, a fall from a high one
func _get_off(rec: Dictionary) -> void:
	var b: VoxelBody = rec.body
	var me := sk.arena.player.global_position
	_let_go(b)
	b.act = 0
	b.act_p = 0.0
	var to := Vector3(me.x - b.position.x, 0, me.z - b.position.z)
	var out := to.normalized() * minf(2.5, to.length() * 0.5) if to.length() > 0.1 else Vector3.ZERO
	var land := sk.nav.spot_near(Vector3(b.position.x + out.x, 0, b.position.z + out.z))
	if to.length() > 0.1:
		b.yaw = atan2(to.x, to.z)
	if b.position.y > HOP_H:
		# a long way down: falling, landing flat, getting up
		var h := b.position.y
		var t := sqrt(2.0 * h / 9.8) + 0.2
		var v := (land - b.position) / t
		v.y = (0.5 * 9.8 * t * t - h) / t
		b.launch(v, 1.2)
		rec.state = OFF
	else:
		b.set_meta("riding", true)            # (the arena leaves it alone till it's down)
		rec.state = HOPPING
		rec.hop = 0.0
		rec.from = b.position
		rec.to = land

func _riders_step(dt: float) -> void:
	var a := sk.arena
	var me := a.player.global_position
	var eye := me + Vector3(0, 0.9, 0)
	for rec in _recs:
		var b: VoxelBody = rec.body if rec.body != null and is_instance_valid(rec.body) else null
		if rec.state == DEAD:
			if b and rec.fall:
				rec.fall = false
				if b.has_meta("riding"):
					_let_go(b)
					if not b.airborne and b.position.y > 0.05:
						b.launch((rec.v as Vector3).limit_length(9.0) + Vector3(0, 1.0, 0), 3.0)      # (off the seat, the way it was going)
			continue
		if rec.state == OFF:
			continue
		if rec.state == HOPPING:
			if b == null:
				rec.state = OFF
				continue
			rec.hop = float(rec.hop) + dt / 0.45
			var k := minf(1.0, float(rec.hop))
			if b.airborne or k >= 1.0:        # (down; or hit out of the air on the way: the arena's now)
				b.remove_meta("riding")
				if not b.airborne:
					b.position = rec.to
				b.reset_physics_interpolation()
				rec.state = OFF
			else:
				var p: Vector3 = (rec.from as Vector3).lerp(rec.to, k)
				p.y += sin(k * PI) * 0.7
				b.position = p
			continue
		# on its seat
		var seat := _seat_xf(rec)
		var d := seat.origin.distance_to(me)
		if b == null:
			if rec.body != null:              # (gone some other way: cleared as lying, shattered to bits)
				rec.body = null
				if rec.made:
					_rider_died(null, rec)
					continue
			if d < NEAR_ON and not rec.made:
				_make(rec, seat)
				rec.made = true
			continue
		if d > NEAR_OFF and b.hp >= float(rec.hp0) and b.hit_by_me_t == 0 and not b.has_status() and float(rec.wait) == INF:
			# far off and never touched: put away (made again when you're back)
			a.bodies.erase(b)
			b.died.disconnect(rec.cb)
			b.queue_free()
			rec.body = null
			rec.made = false
			continue
		if b.airborne or not b.has_meta("riding"):
			# knocked off (a bat, a blast, the gravity gun, the harpoon): the arena's from here
			if b.has_meta("riding"):
				_let_go(b)
			rec.state = OFF
			_alert(rides[int(rec.ride)])
			continue
		if rec.prev != Vector3.INF and dt > 0.0:
			rec.v = (seat.origin - (rec.prev as Vector3)) / dt
		rec.prev = seat.origin
		b.global_transform = _body_xf(b, seat)
		b.visible = _seen(rec)
		if b.hp < float(rec.hp0) or b.stagger > 0.0:
			_alert(rides[int(rec.ride)])
		if b.frozen():
			continue                          # (a statue on its seat)
		var thrower: bool = rec.kind == "thrower" and VoxelKinds.can_throw(b)
		rec.wait = float(rec.wait) - dt       # (INF till its ride's been hit)
		var off := b.panic_t > 0.0 or (not thrower and (d < GET_OFF or float(rec.wait) <= 0.0))
		if rec.kind == "thrower" and not thrower:
			off = true                        # (no arm to throw with: down to hit you)
		if off and a.down_t <= 0.0:
			_get_off(rec)
			continue
		if thrower:
			_throw_step(b, eye, d, dt)

# a thrower on its seat: an arm back, and over (VoxelKinds' own throw; the arena's frozen here, so its step isn't run)
func _throw_step(b: VoxelBody, eye: Vector3, d: float, dt: float) -> void:
	var a := sk.arena
	b.act_cool = maxf(0.0, b.act_cool - dt)
	var loc := b.global_transform.basis.inverse() * (eye - b.global_position)      # (you, in its seat's frame)
	var want := atan2(loc.x, loc.z) if (b.act != 0 and Vector2(loc.x, loc.z).length() > 0.1) else PI
	b.yaw = lerp_angle(b.yaw, want, 1.0 - exp(-dt * 8.0))
	match b.act:
		VoxelBody.ACT_AIM:
			b.act_t -= dt
			b.act_p = 1.0 - b.act_t / VoxelKinds.AIM
			if b.act_t <= 0.0:
				a.kinds.throw_from(b, eye + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4)))
				b.act = VoxelBody.ACT_THROW
				b.act_t = VoxelKinds.THROW_FOLLOW
				b.act_p = 0.0
		VoxelBody.ACT_THROW:
			b.act_t -= dt
			b.act_p = 1.0 - b.act_t / VoxelKinds.THROW_FOLLOW
			if b.act_t <= 0.0:
				b.act = 0
				b.act_p = 0.0
				b.act_cool = randf_range(VoxelKinds.THROW_EVERY.x, VoxelKinds.THROW_EVERY.y)
		_:
			if b.act_cool <= 0.0 and d >= THROW_R.x and d <= THROW_R.y and a.down_t <= 0.0 and b.stagger <= 0.0 and b.visible:
				b.act = VoxelBody.ACT_AIM
				b.act_t = VoxelKinds.AIM
				b.act_p = 0.0

# ---------------------------------------------------------------- the parts of the park, their groups

func _find_areas() -> void:
	for ride in rides:
		var n: Node3D = ride.node
		var at := n.global_position
		if n.has_meta("board"):               # (the Scenic Railway: where you get on)
			at = sk.global_transform * (n.get_meta("board") as Vector3)
		_add_area(String(ride.title), at, int(ride.i))
	for nm in ["GhostTrain", "LunaPalace"]:
		var n := sk.get_node_or_null(nm) as Node3D
		if n:
			_add_area("Ghost Train" if nm == "GhostTrain" else "Luna Palace", n.global_position, -1)
	_add_area("Forecourt", sk.arrive_spot()[0], -1)

func _add_area(nm: String, at: Vector3, ride: int) -> void:
	areas.append({"name": nm, "at": Vector3(at.x, 0, at.z), "ride": ride, "n": _rng.randi_range(GROUP.x, GROUP.y), "done": false,
		"more": 0, "more_t": MORE_EVERY, "came": 0})

func _areas_step(dt: float) -> void:
	var me := sk.arena.player.global_position
	for i in areas.size():
		var a: Dictionary = areas[i]
		var d := Vector2(me.x - a.at.x, me.z - a.at.z).length()
		if not a.done:
			if d < AREA_R:
				a.done = true
				for k in int(a.n):
					_due.append(i)
			continue
		# a few more, one at a time, while its ride still has riders on it and you're about
		if int(a.ride) < 0 or int(a.more) >= MORE_MAX or d > MORE_R:
			continue
		if not (rides[int(a.ride)].riders as Array).any(func(r): return r.state == SEATED):
			continue
		a.more_t = float(a.more_t) - dt
		if float(a.more_t) <= 0.0:
			a.more_t = MORE_EVERY
			a.more = int(a.more) + 1
			_due.append(i)
	_gap -= dt
	if _due.is_empty() or _gap > 0.0:
		return
	var alive := 0
	var mine := 0
	for b in sk.arena.bodies:
		if b.alive and b.has_meta("park"):
			alive += 1
	for b in _ground:
		if is_instance_valid(b) and b.alive:
			mine += 1
	if alive < MAX_ALIVE or mine < 4:         # (riders all round you: a few on the ground come anyway)
		_come_in(areas[int(_due.pop_front())])
		_gap = SPAWN_GAP

# one of an area's group in: at a way in near the area, away from you and where you can't see it if there's one
func _come_in(a: Dictionary) -> void:
	var arena := sk.arena
	var me := arena.player.global_position
	var eye := me + Vector3(0, 1.6, 0)
	var look := Vector3(-sin(arena.look_yaw), 0, -cos(arena.look_yaw))
	var space := sk.get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_s := INF
	var spots: Array = sk.game._spots
	var from := _rng.randi() % spots.size()
	for k in spots.size():
		var p: Vector3 = spots[(from + k) % spots.size()]
		var dm := Vector2(p.x - me.x, p.z - me.z).length()
		if dm < FAR:
			continue
		var s := Vector2(p.x - a.at.x, p.z - a.at.z).length() + _rng.randf() * 6.0     # (near its area, not all at one spot)
		var to := (p - me).normalized()
		if not arena.top_down and look.dot(Vector3(to.x, 0, to.z).normalized()) > 0.5:
			# in front of you: fine if something's in the way
			var q := PhysicsRayQueryParameters3D.create(eye, p + Vector3(0, 1.2, 0), SkData.LAYER_WORLD)
			if space.intersect_ray(q).is_empty():
				s += 60.0
		if s < best_s:
			best_s = s
			best = p
	if best == Vector3.INF:
		best = spots[from]
	var kinds: Array = VoxelParkGame.KINDS
	a.came = int(a.came) + 1
	var b := sk.spawn(kinds[_rng.randi() % kinds.size()], best)
	_ground.append(b)
	b.died.connect(_ground_died, CONNECT_ONE_SHOT)
	if arena.debris:
		arena.debris.throw(b.position + Vector3(0, 0.3, 0), Vector3.UP, Color(0.55, 0.55, 0.58), 12)

func _ground_died(_b: VoxelBody) -> void:
	if running:
		kills += 1

# ---------------------------------------------------------------- the frame, the score

func _process(dt: float) -> void:
	if not running:
		return
	time += dt
	_riders_step(dt)
	_areas_step(dt)
	_ground = _ground.filter(func(b): return is_instance_valid(b))
	_hud_line()
	if cleared == rides.size() and left() == 0:
		_all_clear()

func _hud_line() -> void:
	_hud.text = "Luna Park invasion: rides cleared %d/%d, enemies left %d     %s" % [cleared, rides.size(), left(), VoxelParkGame._clock(time)]

func _all_clear() -> void:
	running = false
	over = true
	var new_best := best_time <= 0.0 or time < best_time
	if new_best:
		best_time = time
		var cf := ConfigFile.new()
		cf.set_value("best", "time", best_time)
		cf.set_value("best", "kills", kills)
		cf.save(BEST_FILE)
	_hud.visible = false
	_end.text = "LUNA PARK CLEARED\n%s in %s%s\nbest time %s\nP: the phone (home, or play again)" % [VoxelParkGame._n(kills),
		VoxelParkGame._clock(time), "   NEW BEST!" if new_best else "", VoxelParkGame._clock(best_time)]
	_end.visible = true
	sk.arena.sound.play("gold_find", Vector3.INF, 0.0, 0.8)
