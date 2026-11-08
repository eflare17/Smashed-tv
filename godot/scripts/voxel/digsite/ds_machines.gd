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

func setup(s: Node3D) -> void:
	site = s
	name = "Machines"

## Every machine parked where it starts (and its net hooks)
func make() -> void:
	var dingo := DsDingo.new()
	add_child(dingo)
	dingo.setup(site, 1, site.AT + Vector3(9.0, 0.0, 27.0), 0.0)
	_add(dingo)

func _add(m: DsMachine) -> void:
	list.append(m)
	var n: DsNet = site.net
	n.register_fast(m.id, m.net_take)
	n.register_fast(m.id + CMD_BASE, func(d: PackedByteArray): _cmds_in(m, d))

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
	_yaw_was = m.yaw
	m.stop_cmds()
	site.arena._let_go()
	site.arena.say(m.keys(), 4.0)

func get_off() -> void:
	var m := driving
	if m == null:
		return
	driving = null
	_asked = 99.0                   # (a guest: not straight back on while the host's state still says it's ours)
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
		a.look_yaw += driving.yaw - _yaw_was
		_yaw_was = driving.yaw
		a._use_label.text = driving.status()
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

## The prompt on foot near one
func line() -> String:
	if near == null:
		return ""
	return ("E  drive the %s" % near.kind) if near.driver == 0 else ("Your mate's driving the %s" % near.kind)
