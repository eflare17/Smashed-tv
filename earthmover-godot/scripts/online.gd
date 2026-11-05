class_name Online
extends Node
## Playing together: one player hosts and gets a room code, the other joins with it. The host's game runs everything: every machine
## and all the dirt. A guest only sends what its thumbs are doing and draws what it's told, so the two can't drift apart and the
## soil total only has to be right in one place.
##
## The host sends the machines 20 times a second and the cells of whichever chunks changed about 8 times a second. A guest draws
## its machines easing towards the last word, so they don't move in steps. Everything is by player number (`drivers`), and only the
## connection itself still knows there's one guest.

const SNAP_HZ := 20.0
const INPUT_HZ := 20.0
const DIRT_HZ := 8.0
const DIRT_CHUNKS := 10         # chunks in a dirt message at most
const BACKLOG_MOST := 200000    # bytes waiting to go out: past this, it holds back until the line catches up
const AIR_MOST := 60            # falling lumps it tells a guest about
const STALE_MS := 600           # nothing from the guest for this long: its machine lets go of the controls
const SILENT_MS := 8000         # nothing at all for this long: they've gone
const ABC := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"     # no O/0, no I/1

enum {SNAP, CMD, DIRT, ACTION, PIPE, READY, LOADING}
const LOADING_MS := 30000       # how long a game gets to build the next job before it counts as gone

var game: Node
var role := "local"             # "local", "host", "guest", or "joining" until a guest is connected
var code := ""
var live := false               # the other player is here
var status_text := ""
var status_bad := false
var transport: NetTransport
## Which machine each player is in, by its place in game.machines. The host is player 0.
var drivers: Array[int] = []
var my_player := 0
var bytes_out := 0
var bytes_in := 0
var dirt_chunks_in := 0
var last_dirt_bytes := 0

var _send_t := 0.0
var _dirt_t := 0.0
var _heard_ms := 0
var _cmd_ms := 0
var _pipes_sent := 0
var _demo_t := 0.0
var _say_t := 0.0
var report := false
var _demo_swapped := false
var _demo_next := false
var _demo_wait := 0.0
var _bot: RefCounted
var carrying := false           # between one job's game and the next: the connection goes on through it

static func make_code() -> String:
	var s := ""
	for i in 4:
		s += ABC[randi() % ABC.length()]
	return s

static func available() -> bool:
	return PeerJsTransport.available()

func _make_transport() -> void:
	if transport != null:
		transport.close()
	transport = PeerJsTransport.new() if PeerJsTransport.available() else ENetTransport.new()
	transport.opened.connect(_on_opened)
	transport.connected.connect(_on_connected)
	transport.received.connect(_on_received)
	transport.disconnected.connect(_on_gone)
	transport.status.connect(_on_status)

func is_guest() -> bool:
	return role == "guest"

func is_host() -> bool:
	return role == "host"

func is_online() -> bool:
	return role == "host" or role == "guest" or role == "joining"

## The machine another player's in, on the host's game. There's room for more than one guest here when the connection can do it.
func guest_machine() -> Machine:
	if role != "host" or drivers.size() < 2:
		return null
	return game.machines[drivers[1]]

func host(wanted_code := "") -> void:
	_make_transport()
	role = "host"
	code = wanted_code if wanted_code != "" else make_code()
	drivers = [game.machines.find(game.active)]
	game.view_data.net_watch = true
	transport.host(code)

func join(room: String) -> void:
	_make_transport()
	role = "joining"
	code = room
	transport.join(room)

func leave() -> void:
	if transport != null:
		transport.close()
	role = "local"
	live = false

func _exit_tree() -> void:
	if transport != null and not carrying:
		transport.close()

func _on_opened(c: String) -> void:
	code = c
	game.online_changed()

func _on_status(text: String, kind: String) -> void:
	status_text = text
	status_bad = kind == "bad"
	game.online_changed()

func _on_connected() -> void:
	live = true
	_heard_ms = Time.get_ticks_msec()
	if role == "joining":
		role = "guest"
		my_player = 1
		game.online_joined()
	elif role == "host":
		_send_everything()
		drivers.resize(1)
		drivers.append(_free_machine(drivers[0]))
	game.online_changed()

## Everything that's happened so far goes over bit by bit.
func _send_everything() -> void:
	_cmd_ms = _heard_ms
	var view: GroundView = game.view_data
	view.changed.clear()
	for c in DirtSim.CHUNKS * DirtSim.CHUNKS:
		view.changed[c] = true
	_pipes_sent = 0

## Starting a job reloads the whole game. This comes out of the old game first, so the connection carries on into the new one.
func carry_over() -> void:
	carrying = true
	if live:
		_send([LOADING])
		transport.poll()
	get_parent().remove_child(self)
	Engine.set_meta("online_keep", self)

## In the new game: the host starts the job's first machine, and a guest asks for all of the new ground.
func arrive(new_game: Node) -> void:
	game = new_game
	carrying = false
	_demo_t = 0.0
	_bot = null
	_heard_ms = Time.get_ticks_msec()
	if role == "host":
		game.view_data.net_watch = true
		drivers = [game.machines.find(game.active)]
		if live:
			_send_everything()
			drivers.append(_free_machine(drivers[0]))
	elif live:
		_send([READY])
	game.online_changed()

func _on_gone() -> void:
	live = false
	if role == "host":
		var gm := guest_machine()
		if gm:
			gm.stop_commands()
		drivers.resize(1)
		game.online_changed()
	else:
		game.online_ended()

## The next machine round from this one that nobody's in. The truck first for a guest, as that's a job to do straight away.
func _free_machine(from: int) -> int:
	var count: int = game.machines.size()
	var truck_at: int = game.machines.find(game.truck)
	var start: int = truck_at if truck_at >= 0 and drivers.size() == 1 and role == "host" and truck_at != from else from + 1
	for k in count:
		var m := (start + k) % count
		if m not in drivers:
			return m
	return from

## The next machine for this player. It stays put if the rest are all taken.
func swap_for(player: int) -> void:
	var count: int = game.machines.size()
	for k in range(1, count):
		var m := (drivers[player] + k) % count
		if m not in drivers:
			game.machines[drivers[player]].stop_commands()
			drivers[player] = m
			return

func _process(_delta: float) -> void:
	if transport == null:
		return
	transport.poll()
	if live and Time.get_ticks_msec() - _heard_ms > SILENT_MS:
		transport.drop_peer()
		_on_gone()

## ---------------------------------------------------------------- the host

## Each physics tick, once everything's moved.
func host_tick(dt: float) -> void:
	if not live:
		return
	var gm := guest_machine()
	if gm and Time.get_ticks_msec() - _cmd_ms > STALE_MS:
		gm.stop_commands()
	var waiting := transport.backlog()
	_send_t += dt
	if _send_t >= 1.0 / SNAP_HZ:
		_send_t = 0.0
		if waiting < BACKLOG_MOST:
			_send([SNAP, PackedInt32Array(drivers), _machine_states(), game.trees.net_state(), game.trees.down, _air_state(), game.mission.get("id", ""), game.mission_done])
	_send_pipes()
	_dirt_t += dt
	if _dirt_t >= 1.0 / DIRT_HZ:
		_dirt_t = 0.0
		if waiting < BACKLOG_MOST:
			_send_dirt()

func _machine_states() -> Array:
	var out := []
	for m: Machine in game.machines:
		out.append(m.net_state())
	return out

func _air_state() -> PackedFloat32Array:
	var sim: DirtSim = game.sim
	var n := mini(sim.air_amt.size(), AIR_MOST)
	var out := PackedFloat32Array()
	out.resize(n * 4)
	for k in n:
		var p := sim.air_pos[k]
		out[k * 4] = p.x
		out[k * 4 + 1] = p.y
		out[k * 4 + 2] = p.z
		# A lump of dust goes as a negative size.
		out[k * 4 + 3] = -sim.air_amt[k] if sim.air_dust[k] * 2 > sim.air_amt[k] else sim.air_amt[k]
	return out

func _send_pipes() -> void:
	var pipes: Pipes = game.pipes
	var all := pipes.points()
	if all.size() <= _pipes_sent:
		return
	_send([PIPE, all.slice(_pipes_sent)])
	_pipes_sent = all.size()

func _send_dirt() -> void:
	var view: GroundView = game.view_data
	if view.changed.is_empty():
		return
	var list := PackedInt32Array()
	for c: int in view.changed:
		list.append(c)
		if list.size() >= DIRT_CHUNKS:
			break
	var cells := PackedInt32Array()
	for c: int in list:
		view.changed.erase(c)
		_read_chunk(c, cells)
	var raw := cells.to_byte_array()
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	last_dirt_bytes = packed.size()
	_send([DIRT, list, raw.size(), packed])

func _chunk_rows(c: int) -> Array:
	var ci := c % DirtSim.CHUNKS
	var cj := c / DirtSim.CHUNKS
	return [ci * DirtSim.CHUNK, cj * DirtSim.CHUNK, mini((ci + 1) * DirtSim.CHUNK, DirtSim.CELLS), mini((cj + 1) * DirtSim.CHUNK, DirtSim.CELLS)]

func _read_chunk(c: int, out: PackedInt32Array) -> void:
	var sim: DirtSim = game.sim
	var r := _chunk_rows(c)
	for grid: PackedInt32Array in [sim.bed, sim.soil, sim.dust]:
		for j in range(r[1], r[3]):
			var a: int = j * DirtSim.CELLS + r[0]
			out.append_array(grid.slice(a, a + r[2] - r[0]))

## ---------------------------------------------------------------- a guest

## Each physics tick: what the thumbs are doing goes off, and the machines ease towards where the host last said.
func guest_tick(dt: float) -> void:
	if not live:
		return
	_send_t += dt
	if _send_t >= 1.0 / INPUT_HZ:
		_send_t = 0.0
		_send([CMD, game.machines.find(game.active), game.active.net_cmds()])
	for m: Machine in game.machines:
		m.net_follow(dt)
	if report:
		_say_every(dt)

## A button that does something to the machine, asked of the host.
func ask(what: String, arg := 0) -> void:
	_send([ACTION, what, arg])

func _load_chunks(list: PackedInt32Array, raw_size: int, packed: PackedByteArray) -> void:
	var cells := packed.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE).to_int32_array()
	var sim: DirtSim = game.sim
	var at := 0
	for c: int in list:
		var r := _chunk_rows(c)
		for grid: PackedInt32Array in [sim.bed, sim.soil, sim.dust]:
			for j in range(r[1], r[3]):
				var n: int = j * DirtSim.CELLS + r[0]
				for i in r[2] - r[0]:
					grid[n + i] = cells[at]
					at += 1
		sim.dirty[c] = true
		dirt_chunks_in += 1

func _load_air(a: PackedFloat32Array) -> void:
	var sim: DirtSim = game.sim
	var n := a.size() / 4
	sim.air_pos.resize(n)
	sim.air_amt.resize(n)
	sim.air_dust.resize(n)
	for k in n:
		sim.air_pos[k] = Vector3(a[k * 4], a[k * 4 + 1], a[k * 4 + 2])
		var amt := int(a[k * 4 + 3])
		sim.air_amt[k] = absi(amt)
		sim.air_dust[k] = -amt if amt < 0 else 0

## ---------------------------------------------------------------- messages

func _send(what: Array) -> void:
	var bytes := var_to_bytes(what)
	bytes_out += bytes.size()
	transport.send(bytes)

func _on_received(data: PackedByteArray) -> void:
	# On its way to the next job: whatever else came in the same breath is about this one, and all of it gets sent again.
	if carrying:
		return
	_heard_ms = Time.get_ticks_msec()
	bytes_in += data.size()
	var d: Variant = bytes_to_var(data)
	if not (d is Array) or (d as Array).is_empty():
		return
	var msg: Array = d
	if role == "guest":
		match int(msg[0]):
			SNAP:
				_load_snapshot(msg)
			DIRT:
				_load_chunks(msg[1], msg[2], msg[3])
			PIPE:
				for p: Vector3 in msg[1]:
					game.pipes.lay_to(p)
			LOADING:
				_heard_ms = Time.get_ticks_msec() + LOADING_MS
	elif role == "host":
		match int(msg[0]):
			CMD:
				var gm := guest_machine()
				# A word about a machine it's just been moved out of counts for nothing.
				if gm and int(msg[1]) == drivers[1]:
					gm.net_take_cmds(msg[2])
					_cmd_ms = _heard_ms
			ACTION:
				game.online_action(1, msg[1], msg[2])
			READY:
				_send_everything()
			LOADING:
				_heard_ms = Time.get_ticks_msec() + LOADING_MS

func _load_snapshot(msg: Array) -> void:
	# The host's in a different job from this game: everything else in the message is about that one.
	var job: String = msg[6]
	if job != game.mission.get("id", ""):
		game.online_go_to(job)
		return
	drivers.assign(msg[1])
	var states: Array = msg[2]
	for k in states.size():
		game.machines[k].net_take(states[k])
	game.trees.net_take(msg[3], msg[4])
	_load_air(msg[5])
	if my_player < drivers.size():
		game.online_my_machine(drivers[my_player])
	if msg[7] and not game.mission_done:
		game.finish_mission()

## ---------------------------------------------------------------- checks

## Two copies of the game on this PC: `--online=host:ABCD --demo=nethost` and `--online=join:ABCD --demo=netguest`.
func run_demo(dt: float) -> void:
	if not live:
		return
	_demo_t += dt
	var sim: DirtSim = game.sim
	if not game.mission.is_empty():
		_run_job_demo(dt)
		return
	if role == "host":
		var dozer: Dozer = game.dozer
		dozer.lift_cmd = -1.0 if _demo_t < 1.0 else 0.0
		dozer.throttle = 1.0 if _demo_t > 1.0 and _demo_t < 9.0 else 0.0
		dozer.steer = 0.3 if _demo_t > 5.0 and _demo_t < 9.0 else 0.0
	elif role == "guest":
		var m: Machine = game.active
		if _demo_t < 1.0:
			print("GUEST in the %s" % m.machine_name)
		m.throttle = 0.8 if _demo_t > 1.0 and _demo_t < 6.0 else 0.0
		m.steer = 0.4 if _demo_t > 3.0 and _demo_t < 6.0 else 0.0
		if _demo_t > 7.0 and not _demo_swapped:
			_demo_swapped = true
			print("GUEST at %s before asking to swap" % m.spot)
			game._swap_machine()
		if _demo_t > 8.0 and _demo_t < 8.1:
			print("GUEST swapped to the %s" % game.active.machine_name)
	_say_every(dt)
	if _demo_t > 60.0 and not OS.has_feature("web"):
		get_tree().quit()

## Both players on a job: the test bot does the host's share, the guest drives, and when it's done the host starts the next one.
func _run_job_demo(dt: float) -> void:
	if role == "host":
		if not game.mission_done and game.mission["id"] == "driveway":
			if _bot == null:
				_bot = load("res://test/spread_bot.gd").new(game.active, game.sim, game.mission)
			_bot.tick(dt)
			# The bot is slow: past this the check fills in the rest, as it is the finish that it is after.
			if _demo_t > 25.0:
				var r: Rect2 = game.mission["rect"]
				var from := DirtSim.cell_of(r.position)
				var to := DirtSim.cell_of(r.end)
				for j in range(from.y, to.y):
					for i in range(from.x, to.x):
						game.sim.dust[j * DirtSim.CELLS + i] = maxi(game.sim.dust[j * DirtSim.CELLS + i], Mission.COVERED_MM)
						game.view_data.changed[(j / DirtSim.CHUNK) * DirtSim.CHUNKS + i / DirtSim.CHUNK] = true
		elif game.mission_done and not _demo_next and not Mission.after(game.mission).is_empty():
			_demo_wait += dt
			if _demo_wait < 4.0:
				_say_every(dt)
				return
			_demo_next = true
			print("HOST on to the next job")
			game.active.stop_commands()
			game._start_mission(Mission.after(game.mission)["id"])
			return
	else:
		var m: Machine = game.active
		if _demo_t < dt * 1.5:
			print("GUEST in job %s, machine %d of %d, a %s at %s" % [game.mission["id"], game.machines.find(m), game.machines.size(), m.machine_name, m.spot])
		m.throttle = -0.5 if _demo_t > 2.0 and _demo_t < 4.0 else 0.0
	_say_every(dt)
	if _demo_t > 30.0 and game.mission["id"] == "long_driveway" and not OS.has_feature("web"):
		get_tree().quit()

## With ?report in the page's address, or in a check: the ground and machines every so often, to compare between two games.
func _say_every(dt: float) -> void:
	_say_t += dt
	if _say_t < 10.0:
		return
	_say_t = 0.0
	var sim: DirtSim = game.sim
	var sum := 0
	for n in sim.bed.size():
		sum = (sum * 31 + sim.bed[n] + sim.soil[n] * 7 + sim.dust[n] * 3) & 0xffffffffff
	var at := ""
	for k: Machine in game.machines:
		at += "%s %.2f,%.2f  " % [k.machine_name, k.spot.x, k.spot.y]
	print("%s ground %d waiting %d | %s| trees %d | sent %d KB, got %d KB, chunks in %d, last dirt %d B, moving %d" % [role.to_upper(), sum, game.view_data.changed.size(), at, game.trees.down, bytes_out / 1024, bytes_in / 1024, dirt_chunks_in, last_dirt_bytes, sim.awake_count()])
