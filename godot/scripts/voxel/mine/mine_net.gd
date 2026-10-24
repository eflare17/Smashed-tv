class_name MineNet
extends Node
## The shared mine (the owner, 24 Oct: "build the shared mine so we can dig together"): in co-op both players dig the
## host's ground. The host's game runs it (the sand, the water, the lava, the cave-ins), even with the host up in the
## arena; when the guest goes down, the host sends the whole ground (in parts), then every 1/15 s the chunks of it
## that changed (MineSim.take_diff: only what's moved, zstd-packed). The guest's game digs, blasts, shoots and sucks up
## water on its own copy at once (it feels like your own) and sends each as an op; the host does the same to the real
## ground; until a chunk update says the host has done an op (its number), the guest does its pending ones again on
## top of each update, so a hole doesn't flicker shut. Each game shows the other's Mole (the host's yellow, the
## guest's blue, both with Jared in), from its state 20 times a second, and keeps sand and water out of both ships'
## boxes. The guest's cargo, cash, upgrades and fuel stay its own (and its own ground waits, put back on the way up).
## The critters each game runs for its own player; the worm only in the host's. Owned by the voxel session.

const DIFF_HZ := 15.0
const STATE_HZ := 20.0
const PART := 48000             # bytes of the ground a message on the way down
const FAST := 77                # (the fast messages' first byte: a ship's state)

var mine: Node                  # VoxelMine
# the host's
var guest_down := false         # the guest's down the (host's) mine
var _applied := 0               # the last of the guest's ops done here
var _diff_t := 0.0
# the guest's
var shared := false             # digging the host's ground
var _want := false              # asked for it, waiting
var _parts := []
var _seq := 0
var _pending := []              # [[seq, kind, args]] not yet done by the host
var _outbox := []               # (the same, not sent yet: they go 30 times a second)
var _out_t := 0.0
var _own_ground := PackedByteArray()
# both
var other: MineShip             # the other player's Mole, shown
var other_on := false           # (down there, from their last state)
var other_fuel := 1.0           # their tank and hull, how full (0 .. 1), and stranded out of fuel waiting for help
var other_hull := 1.0
var other_stranded := false
var _o_to := Vector2()
var _o_look := {}
var _state_t := 0.0
var _o_seen := 0.0
var _s_out := 0                 # (the states' numbers: one older than the last in, come late, dropped)
var _s_in := -1
var stats := {"ch": 0, "ch_bytes": 0, "ops": 0}     # (the tests': chunk updates, their packed bytes, ops)

func setup(m: Node) -> void:
	mine = m

func _net():
	return mine.arena.net if mine.arena and mine.arena.net and mine.arena.net.linked else null

func role() -> String:
	var n = _net()
	return String(n.role) if n else ""

func _send(m: Array) -> void:
	var n = _net()
	if n:
		n.send_mine(m)

# ---------------------------------------------------------------- the guest's way down and up

## (the guest's) going down: true if the host's ground has to come first (asked for; enter() again when it's here)
func need_world() -> bool:
	if role() != "guest" or shared:
		return false
	if not _want:
		_want = true
		_parts.clear()
		_send(["want", mine.ship_look()])
	return true

## (the guest's) back up: its own ground back, the host told
func gone_up() -> void:
	if role() == "guest" and shared:
		_send(["up"])
	_drop_shared()

func _drop_shared() -> void:
	if not shared:
		_want = false
		return
	shared = false
	_want = false
	_pending.clear()
	_outbox.clear()
	if not _own_ground.is_empty():
		mine.ground_back(_own_ground)
	_own_ground = PackedByteArray()

# ---------------------------------------------------------------- ops (the guest's)

## (the guest's, sharing) something done to the ground here, done to the host's too: "dig" (MineSim.dig's args), "boom"
## (explode's), "dep" (deposit's), "suck" (cells to empty: x, y, ...)
func op(kind: String, args: Array) -> void:
	if not shared:
		return
	_seq += 1
	_pending.append([_seq, kind, args])
	_outbox.append([_seq, kind, args])

func _do(sim: MineSim, kind: String, a: Array, again: bool) -> void:
	match kind:
		"dig":
			if a.size() == 11:
				sim.dig(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], 0.0 if again else a[8], a[9], a[10], false)
		"boom":
			if a.size() == 4:
				sim.explode(a[0], a[1], a[2], 0.0 if again else a[3])
		"dep":
			if a.size() == 5:
				sim.deposit(a[0], a[1], a[2], a[3], a[4])
		"suck":
			# (the water round the nozzle, then round the ship: as many cells as the guest's game sucked up)
			if a.size() == 5:
				var want := int(a[4])
				var found: PackedInt32Array = sim.find(MineTiles.WATER, a[0] - 9, a[1] - 9, a[0] + 9, a[1] + 9, want)
				if found.size() / 2 < want:
					found.append_array(sim.find(MineTiles.WATER, a[2] - 6, a[3] - 6, a[2] + 6, a[3] + 6, want - found.size() / 2))
				for k in range(0, found.size() - 1, 2):
					sim.set_cell(found[k], found[k + 1], MineTiles.AIR)

## The cells an op can change (x0, y0, x1, y1)
func _reach(kind: String, a: Array) -> PackedInt32Array:
	match kind:
		"dig":
			if a.size() == 11:
				var rx := float(a[2]) + float(a[4]) + 2.0
				var ry := float(a[3]) + float(a[4]) + 2.0
				return PackedInt32Array([int(a[0] - rx), int(a[1] - ry), int(a[0] + rx), int(a[1] + ry)])
		"boom", "dep":
			if a.size() >= 3:
				var r := float(a[2]) + 3.0
				return PackedInt32Array([int(a[0] - r), int(a[1] - r), int(a[0] + r), int(a[1] + r)])
		"suck":
			if a.size() == 5:
				return PackedInt32Array([a[0] - 9, a[1] - 9, a[0] + 9, a[1] + 9, a[2] - 6, a[3] - 6, a[2] + 6, a[3] + 6])
	return PackedInt32Array()

# ---------------------------------------------------------------- each frame

func step(dt: float) -> void:
	var r := role()
	if r == "":
		if shared:
			mine.lost_link()
			_drop_shared()
		if guest_down and mine._built:
			mine.ground.sim.set_block2(0, 0, 0, 0)
		guest_down = false
		_want = false
		other_on = false
		_s_in = -1
		_show_other(dt, false)
		return
	# the guest's ops, to the host
	_out_t += dt
	if not _outbox.is_empty() and _out_t >= 1.0 / 30.0:
		_out_t = 0.0
		_send(["ops", _outbox])
		_outbox = []
	# this player's Mole, to the other game
	_state_t += dt
	if _state_t >= 1.0 / STATE_HZ:
		_state_t = 0.0
		var on: bool = mine.active and (r == "host" or shared)
		var n = _net()
		if n and (on or other_on or guest_down):
			n.send_mine_fast(_state(on))
	# the host: the changed chunks to the guest; the guest's Mole keeps the sand and water out
	if r == "host" and guest_down:
		var gb := MineGround.cells_of(_o_to, Vector2(MineShip.HALF, MineShip.HALF)) if other_on else Rect2i()
		mine.ground.sim.set_block2(gb.position.x, gb.position.y, gb.size.x, gb.size.y)
		if other_on:
			mine.ground.sim.displace(gb.position.x, gb.position.y, gb.size.x, gb.size.y)
		_diff_t += dt
		if _diff_t >= 1.0 / DIFF_HZ:
			_diff_t = 0.0
			var d: PackedByteArray = mine.ground.sim.take_diff(240)
			if d.size() > 0:
				var z := d.compress(FileAccess.COMPRESSION_ZSTD)
				stats.ch += 1
				stats.ch_bytes += z.size()
				_send(["ch", _applied, d.size(), z])
			elif _applied > 0:
				_send(["ack", _applied])
	_o_seen += dt
	if _o_seen > 1.5:
		other_on = false            # (no word from them: gone)
	_show_other(dt, other_on and mine._built and (r == "host" and guest_down or r == "guest" and shared))

func _state(on: bool) -> PackedByteArray:
	var s: MineShip = mine.ship
	var b := StreamPeerBuffer.new()
	b.put_u8(FAST)
	_s_out = (_s_out + 1) & 0xffff
	b.put_u16(_s_out)
	b.put_float(s.p.x)
	b.put_float(s.p.y)
	b.put_float(s.v.x)
	b.put_float(s.v.y)
	var f := 0
	f |= 1 if s.face > 0 else 0
	f |= 2 if s.drilling else 0
	f |= 4 if s.thrusting else 0
	f |= 8 if s.grounded else 0
	f |= 16 if on else 0
	f |= 32 if (s.drilling and s.drill_dir.y < 0.0) else 0
	f |= 64 if mine.stranded else 0
	b.put_u8(f)
	b.put_u8(int(clampf(s.hose_out, 0.0, 1.0) * 255.0))
	b.put_u8(int(clampf(s.cargo_full, 0.0, 1.0) * 255.0))
	b.put_u8(int(clampf(s.heat, 0.0, 1.0) * 255.0))
	b.put_u8(int(clampf(mine.fuel / maxf(0.01, mine.tank_max()), 0.0, 1.0) * 255.0))
	b.put_u8(int(clampf(mine.hull / maxf(0.01, mine.hull_max()), 0.0, 1.0) * 255.0))
	return b.data_array

## The other game's Mole's state (VoxelNet: the fast messages starting FAST)
func on_fast(d: PackedByteArray) -> void:
	if d.size() < 25 or other == null:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = d
	b.get_u8()
	var sq := b.get_u16()
	if _s_in >= 0 and ((sq - _s_in) & 0xffff) >= 0x8000:
		return
	_s_in = sq
	var p := Vector2(b.get_float(), b.get_float())
	var v := Vector2(b.get_float(), b.get_float())
	var f := b.get_u8()
	var on := (f & 16) != 0
	if on and not other_on:
		other.place(p)
	other_on = on
	_o_seen = 0.0
	_o_to = p
	other.v = v
	other.face = 1 if (f & 1) else -1
	other.drilling = (f & 2) != 0
	other.thrusting = (f & 4) != 0
	other.grounded = (f & 8) != 0
	other.drill_dir = Vector2(0, -1) if (f & 32) else Vector2(float(other.face), 0)
	other.hose_out = b.get_u8() / 255.0
	other.cargo_full = b.get_u8() / 255.0
	other.heat = b.get_u8() / 255.0
	other_fuel = b.get_u8() / 255.0
	other_hull = b.get_u8() / 255.0
	other_stranded = (f & 64) != 0

func _show_other(dt: float, on: bool) -> void:
	if other == null:
		if not mine._built:
			return
		other = MineShip.new()
		other.ground = mine.ground
		mine.world.add_child(other)
		other.build(_o_look if not _o_look.is_empty() else {"coat": 1})
	other.visible = on
	if not on:
		return
	# smoothed toward where they are (a jump: there at once)
	if other.p.distance_to(_o_to) > 2.0:
		other.p = _o_to
	else:
		other.p = other.p.lerp(_o_to + other.v * 0.05, minf(1.0, dt * 14.0))
	other._pose(dt)

# ---------------------------------------------------------------- messages (VoxelNet "N")

func on_net(m: Array) -> void:
	if m.is_empty():
		return
	var r := role()
	match String(m[0]):
		"want":
			# (the host's) the guest's coming down: the ground as it is, in parts; what changes after, chunk by chunk
			if r != "host":
				return
			mine.serve_start()
			_look_in(m[1] if m.size() > 1 else {})
			var all: PackedByteArray = mine.ground.save_bytes()
			mine.ground.sim.diff_reset()
			_applied = 0
			guest_down = true
			var n := ceili(float(all.size()) / PART)
			for i in n:
				_send(["wp", i, n, all.slice(i * PART, mini(all.size(), (i + 1) * PART)), mine.ship_look()])
		"wp":
			# (the guest's) a part of the host's ground; the last one in: down we go
			if r != "guest" or not _want:
				return
			_parts.append(m[3])
			if m.size() > 4:
				_look_in(m[4])
			if _parts.size() >= int(m[2]):
				var all := PackedByteArray()
				for p in _parts:
					all.append_array(p)
				_parts.clear()
				_own_ground = mine.ground.save_bytes()
				if mine.ground_shared(all):
					shared = true
					_seq = 0
					_pending.clear()
					_outbox.clear()
					mine.enter()
				else:
					_want = false
					mine.say("Couldn't get your mate's mine", 2.0)
		"ops":
			if r == "host" and guest_down and m.size() >= 2 and typeof(m[1]) == TYPE_ARRAY:
				for o in m[1]:
					if typeof(o) == TYPE_ARRAY and o.size() == 3 and typeof(o[2]) == TYPE_ARRAY:
						_applied = int(o[0])
						_do(mine.ground.sim, String(o[1]), o[2], false)
		"ch", "ack":
			if r != "guest" or not shared:
				return
			var ack := int(m[1])
			while not _pending.is_empty() and int(_pending[0][0]) <= ack:
				_pending.pop_front()
			if String(m[0]) == "ch" and m.size() >= 4:
				var d: PackedByteArray = (m[3] as PackedByteArray).decompress(int(m[2]), FileAccess.COMPRESSION_ZSTD)
				stats.ch += 1
				stats.ch_bytes += (m[3] as PackedByteArray).size()
				# (the ops the host hasn't done yet, done again on top: holes stay holes; the chunks they reach that this
				# update leaves alone have them already: kept as they are)
				var sim: MineSim = mine.ground.sim
				var keep := PackedByteArray()
				if not _pending.is_empty():
					var rects := PackedInt32Array()
					for o in _pending:
						rects.append_array(_reach(String(o[1]), o[2]))
					keep = sim.chunks_in(rects, d)
				sim.apply_chunks(d)
				for o in _pending:
					_do(sim, String(o[1]), o[2], true)
				if not keep.is_empty():
					sim.apply_chunks(keep)
		"up":
			if r == "host":
				guest_down = false
				other_on = false
				mine.ground.sim.set_block2(0, 0, 0, 0)
		"look":
			_look_in(m[1] if m.size() > 1 else {})
		"cave":
			if r == "guest" and shared and mine.active and m.size() >= 4:
				var at := Vector2(float(m[2]), float(m[3]))
				var near := clampf(1.0 - at.distance_to(mine.ship.p) / 14.0, 0.0, 1.0)
				if String(m[1]) == "groan":
					mine.sound.play("mine_groan", Vector3.INF, lerpf(-12.0, -4.0, near), randf_range(0.85, 1.1))
				else:
					mine.sound.play("mine_collapse", Vector3.INF, lerpf(-14.0, 0.0, near), randf_range(0.9, 1.05))
					mine.shake(0.15 + near * 0.6)
		"help":
			if m.size() >= 3 and mine.active and (shared or r == "host"):
				mine.helped(float(m[1]), float(m[2]))
		"hurt":
			if r == "guest" and shared and m.size() >= 3:
				mine.hurt(float(m[1]), String(m[2]))
				mine.say("Cave-in!", 1.5)

## The other player's Mole's upgrades (how it looks): it's drawn again
func _look_in(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	_o_look = d.duplicate()
	if other:
		other.build(_o_look)

## This player's Mole's looks changed (an upgrade): the other game told
func send_look() -> void:
	if role() != "" and (shared or guest_down):
		_send(["look", mine.ship_look()])

## Fuel (litres) and hull given to the other player's Mole (holding G next to it)
func help(fuel: float, hull: float) -> void:
	if role() != "" and other_on:
		_send(["help", fuel, hull])

## Whether the other player's Mole is down here with this one (for the marker, for helping)
func mate_here() -> bool:
	return other_on and other != null and other.visible

## (the host's) a roof cracking ("groan") or coming down ("collapse") at at: the guest hears it
func cave_fx(kind: String, at: Vector2) -> void:
	if role() == "host" and guest_down:
		_send(["cave", kind, at.x, at.y])

## (the host's) a cave-in on the guest's Mole
func hurt_other(n: float, why: String) -> void:
	if role() == "host" and guest_down:
		_send(["hurt", n, why])
