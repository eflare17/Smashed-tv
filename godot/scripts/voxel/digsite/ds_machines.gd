class_name DsMachines
extends Node3D
## The Dig Site's machines (stage 6 on): parked round the site, E near one to get on and drive it (E again to get
## off), one driver at a time, either player. While you drive, you stand (or sit) on it and it takes the keys and
## the mouse buttons (DsMachine.read_input); your view turns with it. The game that runs the ground moves them all
## (the host in co-op): a guest asks to drive ("drive"/"off" events: the host says who has it, in each machine's
## state), then sends its controls 20 times a second; the host sends each machine's state 20 times a second (DsNet's
## fast channel). Owned by the voxel session.

const NEAR := 2.6               # m: this near a machine, E gets on
const SEND_HZ := 20.0
const CMD_BASE := 128           # (a driver's controls go as the machine's id + this)

var site: Node3D                # DigSite
var list: Array[DsMachine] = []
var driving: DsMachine = null   # the one this player's on
var near: DsMachine = null      # the one E would get on
var _send_t := 0.0
var _yaw_was := 0.0
var _asked := 0.0               # (a guest: asked to drive this long ago)
var third := true               # driving seen from behind (V: from the seat)
var cam_dist := 6.0             # (the mouse wheel: nearer, further)
const CAM_FOLLOW := 9.0         # per second: the view's aim follows the machine along the ground ...
const CAM_FOLLOW_UP := 4.0      # ... and up and down, more softly
var _cam_m: DsMachine
var _cam_at := Vector3.ZERO
var _cam_floor := -INF
var gauge: DsGauge              # the level while driving

func setup(s: Node3D) -> void:
	site = s
	name = "Machines"
	gauge = DsGauge.new()
	gauge.visible = false
	s.arena._hud_layer.add_child(gauge)

## Every machine parked where it starts (and its net hooks)
func make() -> void:
	var dingo := DsDingo.new()
	add_child(dingo)
	dingo.setup(site, 1, site.AT + Vector3(9.0, 0.0, 27.0), 0.0)
	_add(dingo)
	var bobcat := DsBobcat.new()
	add_child(bobcat)
	bobcat.setup(site, 2, site.AT + Vector3(13.0, 0.0, 27.0), 0.0)
	_add(bobcat)
	var digger := DsExcavator.new()
	add_child(digger)
	digger.setup(site, 3, site.AT + Vector3(-16.0, 0.0, 25.0), 0.0)
	_add(digger)
	var truck := DsTruck.new()
	add_child(truck)
	truck.setup(site, 4, site.AT + Vector3(-4.0, 0.0, 26.0), 0.0)
	_add(truck)
	var dozer := DsDozer.new()
	add_child(dozer)
	dozer.setup(site, 5, site.AT + Vector3(20.0, 0.0, 24.0), 0.0)
	_add(dozer)
	var n: DsNet = site.net
	n.register_event("prop_load", func(a: Array): _prop_load(by_id(int(a[0])), int(a[1])))
	n.register_event("prop_take", func(a: Array): _prop_take(by_id(int(a[0])), false))
	n.register_event("prop_give", func(_a: Array): _given())

func _add(m: DsMachine) -> void:
	list.append(m)
	var n: DsNet = site.net
	n.register_fast(m.id, m.net_take)
	n.register_fast(m.id + CMD_BASE, func(d: PackedByteArray): _cmds_in(m, d))

## The truck whose tray a bucket's pouring over (from: the machine pouring), or null
func catcher(p: Vector3, from: DsMachine) -> DsTruck:
	for m in list:
		if m != from and m is DsTruck and (m as DsTruck).over_tray(p):
			return m
	return null

func trucks() -> Array:
	return list.filter(func(m): return m is DsTruck)

## A key at the Dig Site: L (driving the truck by the office: concrete supports on it), G (on foot at a truck's back:
## one off it). True if it did something.
func key(k: int) -> bool:
	var a = site.arena
	if k == KEY_L and driving is DsTruck:
		var t := driving as DsTruck
		var w: Vector3 = site.AT + site.OFFICE_WINDOW
		if Vector2(t.global_position.x - w.x, t.global_position.z - w.z).length() > 9.0:
			a.say("Park by the site office to load concrete supports", 1.5)
			return true
		var room := DsTruck.PROPS_MOST - t.props
		var n := mini(room, a.cash / DsTruck.PROP_COST)
		if n <= 0:
			a.say("The truck's full of supports" if room <= 0 else "Not enough cash: $%d a support" % DsTruck.PROP_COST, 1.5)
			return true
		a.cash -= n * DsTruck.PROP_COST
		a.sound.play("hammer_thud_0", Vector3.INF, -6.0)
		a.say("%d concrete supports loaded ($%d)" % [n, n * DsTruck.PROP_COST], 2.0)
		if site.net.runs():
			_prop_load(t, n)
		else:
			site.net.event("prop_load", [t.id, n])
		return true
	if k == KEY_G and driving == null:
		var t := near_truck_back()
		if t == null:
			return false
		if t.props <= 0:
			a.say("No concrete supports on the truck (load them by the site office: L)", 1.5)
			return true
		if site.net.runs():
			_prop_take(t, true)
		else:
			site.net.event("prop_take", [t.id])
		return true
	return false

## The truck whose back this player's standing at (on foot), or null
func near_truck_back() -> DsTruck:
	var p: Vector3 = site.arena.player.global_position
	for t in trucks():
		var b: Vector3 = (t as DsTruck).spout()
		if Vector2(b.x - p.x, b.z - p.z).length() < 2.2:
			return t
	return null

func _prop_load(t: DsTruck, n: int) -> void:
	if t == null or not site.net.runs():
		return
	t.props = mini(DsTruck.PROPS_MOST, t.props + n)

# (the host's) a support off the truck: to this player, or (asked by the guest) to the guest
func _prop_take(t: DsTruck, mine: bool) -> void:
	if t == null or not site.net.runs() or t.props <= 0:
		return
	t.props -= 1
	if mine:
		_given()
	else:
		site.net.event("prop_give", [])

func _given() -> void:
	var a = site.arena
	a.receive({"id": "prop_concrete", "n": 1}, "inv")
	a.sound.play("item_pick", Vector3.INF, -4.0)
	a.say("A concrete support off the truck (%d in your backpack)" % a.inv.count("prop_concrete"), 1.5)

func by_id(i: int) -> DsMachine:
	for m in list:
		if m.id == i:
			return m
	return null

## This player's number as a driver: 1 the host (or solo), 2 the guest
func me() -> int:
	return 2 if site.net.role() == "guest" else 1

# ---------------------------------------------------------------- getting on and off

## E: on the one near, or off the one this player's on. True if it did something.
func use() -> bool:
	if driving:
		get_off()
		return true
	if near == null:
		return false
	if near.driver != 0:
		site.arena.say("Your mate's driving the %s" % near.kind, 1.5)
		return true
	if site.net.runs():
		near.driver = me()
		_on(near)
	else:
		_asked = 0.0
		site.net.event("drive", [near.id])     # (the host says yes in its next state)
		site.arena.say("Getting on the %s ..." % near.kind, 1.0)
	return true

func _on(m: DsMachine) -> void:
	driving = m
	_yaw_was = m.view_yaw()
	gauge.machine = m
	cam_dist = clampf(m.length * 1.5 + 3.0, 5.0, 16.0)
	site.arena.look_yaw = m.view_yaw()
	site.arena.look_pitch = -0.3 if third else 0.0
	_show_me(third)
	m.stop_cmds()
	site.arena._let_go()
	site.arena.say(m.keys(), 4.0)

func get_off() -> void:
	var m := driving
	if m == null:
		return
	driving = null
	_asked = 99.0                   # (a guest: not straight back on while the host's state still says it's ours)
	gauge.machine = null
	site.arena.look_pitch = 0.0
	_show_me(false)
	m.stop_cmds()
	if site.net.runs():
		m.driver = 0
	else:
		site.net.event("off", [m.id])
	# stood beside it, on the left
	var at := m.global_position - m.right() * (m.width * 0.5 + 0.6)
	var y: float = m.ground_y(at.x, at.z)
	site._put(Vector3(at.x, y + 0.05, at.z), site.arena.look_yaw, site.arena.look_pitch)

## (the host's) a guest's ask to drive, or to get off
func on_event(kind: String, a: Array) -> void:
	var m := by_id(int(a[0])) if not a.is_empty() else null
	if m == null or not site.net.runs():
		return
	if kind == "drive" and m.driver == 0:
		m.driver = 2
	elif kind == "off" and m.driver == 2:
		m.driver = 0
		m.stop_cmds()

func _cmds_in(m: DsMachine, d: PackedByteArray) -> void:
	if site.net.runs() and m.driver == 2:
		m.net_take_cmds(d)

# ---------------------------------------------------------------- each frame

func _process(dt: float) -> void:
	if not site.active:
		return
	var a = site.arena
	var runs: bool = site.net.runs()
	# a guest: the host said yes (or no, or took it off us)
	if not runs:
		for m in list:
			if m.driver == 2 and driving == null and _asked < 3.0:
				_on(m)
			elif driving == m and m.driver != 2 and _asked > 1.0:
				driving = null
				a.say("Off the %s" % m.kind, 1.5)
		_asked += dt
	# the link gone: the guest's driver off
	if runs:
		for m in list:
			if m.driver == 2 and site.net.role() == "":
				m.driver = 0
				m.stop_cmds()
	if driving:
		if a.phone.is_open() or a.down_t > 0.0:
			driving.stop_cmds()
		elif not driving.auto:
			driving.read_input()
	for m in list:
		m.step(dt)
	# the driver stands on it; the view turns with it
	if driving:
		site._put_keep(driving.seat_world())
		a.look_yaw += wrapf(driving.view_yaw() - _yaw_was, -PI, PI)
		_yaw_was = driving.view_yaw()
		a._use_label.text = driving.status()
		if third:
			_third_cam(driving, dt)
	# who's near (on foot)
	near = null
	if driving == null:
		var p: Vector3 = a.player.global_position
		var best := NEAR
		for m in list:
			var d := Vector2(m.global_position.x - p.x, m.global_position.z - p.z).length()
			if d < best:
				best = d
				near = m
	# the network: states out (the host), a guest driver's controls out
	_send_t += dt
	if _send_t >= 1.0 / SEND_HZ:
		_send_t = 0.0
		for m in list:
			if runs:
				site.net.send_fast(m.id, m.net_state())
			elif driving == m:
				site.net.send_fast(m.id + CMD_BASE, m.net_cmds())

## V while driving: from behind it, or from the seat
func toggle_view() -> void:
	third = not third
	site.arena.look_pitch = -0.3 if third else 0.0
	_show_me(third)
	site.arena.say("Seen from behind it (V: from the seat; mouse: look round it; wheel: nearer, further)" if third else "From the seat (V: from behind it)", 2.0)

## The mouse wheel while driving, from behind: nearer or further
func zoom(nearer: bool) -> void:
	cam_dist = clampf(cam_dist * (0.88 if nearer else 1.14), 3.0, 30.0)

# your own Jared seen on the machine (from behind), or not (from the seat: the arena hides him again)
func _show_me(on: bool) -> void:
	var a = site.arena
	if a.avatar == null:
		return
	if on:
		a._set_layers(a.avatar, 1)
	a.avatar.visible = on

# the camera behind the machine, round it with the mouse (the arena's look), not through the ground; you on it
func _third_cam(m: DsMachine, dt: float) -> void:
	var a = site.arena
	# what it looks at follows the machine softly (a quick follow along the ground, a slower one up and down), so a bump
	# under the tracks doesn't jolt the view (the owner, 9 Nov: "it's still so jumpy")
	var raw := m.global_position + Vector3(0, 1.0 + m.length * 0.12, 0)
	if _cam_m != m or _cam_at.distance_to(raw) > 6.0:
		_cam_m = m
		_cam_at = raw
		_cam_floor = -INF
	var kh := 1.0 - exp(-CAM_FOLLOW * dt)
	var kv := 1.0 - exp(-CAM_FOLLOW_UP * dt)
	_cam_at = Vector3(lerpf(_cam_at.x, raw.x, kh), lerpf(_cam_at.y, raw.y, kv), lerpf(_cam_at.z, raw.z, kh))
	var target := _cam_at
	var yaw: float = a.look_yaw
	var p := clampf(float(a.look_pitch), -1.25, 0.3)
	var dir := Vector3(-sin(yaw) * cos(p), sin(p), -cos(yaw) * cos(p))
	var pos := target - dir * cam_dist
	# kept out of the ground, the lift eased too (a heap passing under it doesn't pop it up), never let into it
	var floor_y: float = m.ground_y(pos.x, pos.z) + 0.5
	_cam_floor = floor_y if _cam_floor == -INF else lerpf(_cam_floor, floor_y, kv)
	pos.y = maxf(pos.y, maxf(_cam_floor, floor_y - 0.35))
	a.cam.global_position = pos
	if pos.distance_to(target) > 0.05:
		a.cam.look_at(target, Vector3.UP)
	a.cross.visible = false
	var av = a.avatar
	if av:
		av.visible = true
		av.global_position = m.seat_world()
		var f := Vector3(-sin(m.view_yaw()), 0, -cos(m.view_yaw()))
		av.yaw = atan2(f.x, f.z)
		av.speed = 0.0
		av.animate(dt, false)

## The prompt on foot near one
func line() -> String:
	if near == null:
		var t := near_truck_back()
		return "G  take a concrete support off the truck (%d on it)" % t.props if t and t.props > 0 else ""
	return ("E  drive the %s" % near.kind) if near.driver == 0 else ("Your mate's driving the %s" % near.kind)
