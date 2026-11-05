extends RefCounted
## Does a driveway job with the same controls a player's thumbs have: scoop, carry, dump at the far end of a lane, lower, back up.
## It only proves the job can be done: a real player won't drive like this. Used by test/mission_test.gd and --demo=spread.


var m: Loader
var sim: DirtSim
var job: Dictionary
var state := "scoop"
var clock := 0.0
var lanes: Array[float] = []
var trip := 0
var drop_z := 0.0
var lane_x := 0.0
var loads_a_lane := 1
var target := Vector2.ZERO
var want_trips := 0
var creep_to := 0.0

func _init(machine: Loader, s: DirtSim, j: Dictionary) -> void:
	m = machine
	sim = s
	job = j
	var r: Rect2 = j["rect"]
	var w := m.bucket_half * 2.0 * 0.92
	var count := int(ceil(r.size.x / w))
	for k in count:
		lanes.append(lerpf(r.position.x + m.bucket_half, r.end.x - m.bucket_half, float(k) / maxi(count - 1, 1)))
	var per_load := DirtSim.to_m3(m.capacity) / (w * Mission.SPREAD_MM * 0.001)
	loads_a_lane = int(ceil(r.size.y / per_load))
	want_trips = loads_a_lane * lanes.size()
	_next_trip()

func _next_trip() -> void:
	if m.spread_on:
		m.toggle_spread()
	_pick_drop()
	state = "scoop"
	clock = 0.0
	target = _thickest_dust()

## As a player would, by eye: the lane with a gap nearest the house, and tip the load just on the house side of the gap.
func _pick_drop() -> void:
	var r: Rect2 = job["rect"]
	var best := INF
	var best_lane: float = lanes[0]
	var lane_count := lanes.size()
	# As big a gap as is worth a load: a load from the Bobcat runs a long way.
	var gap_rows := 4 if m.kind == Loader.BOBCAT else 1
	for n in lane_count:
		var x: float = lanes[(trip + n) % lane_count]
		var z := r.position.y + 0.35
		var run := 0
		while z < r.end.y:
			var bare := 0
			for w in 3:
				var at := DirtSim.cell_of(Vector2(x + (w - 1) * m.bucket_half * 0.6, z))
				if sim.dust[at.y * DirtSim.CELLS + at.x] < Mission.COVERED_MM:
					bare += 1
			run = run + 1 if bare > 0 else 0
			# A real gap, a few rows long: a whole load isn't tipped on one thin row.
			if run >= gap_rows:
				var gap_at := z - DirtSim.CELL_M * (gap_rows - 1)
				if gap_at < best:
					best = gap_at
					best_lane = x
				break
			z += DirtSim.CELL_M
	lane_x = best_lane
	drop_z = (best if best < INF else r.position.y) + 0.3

## The thickest dust on the whole block, on the driveway or off it: what's been left in a heap or spilled gets used again, as a player would.
func _thickest_dust() -> Vector2:
	var site := Mission.site(job)
	var a := DirtSim.cell_of(site.position)
	var b := DirtSim.cell_of(site.end)
	var best := 0
	var spot: Vector2 = job["pile"]
	for j in range(a.y, b.y):
		for i in range(a.x, b.x):
			var d := sim.dust[j * DirtSim.CELLS + i]
			if d > best:
				best = d
				spot = Vector2(-DirtSim.HALF_M + i * DirtSim.CELL_M, -DirtSim.HALF_M + j * DirtSim.CELL_M)
	return spot

## Turns it to face this point. Returns how far off it is, in radians.
func _aim(p: Vector2, backing := false) -> float:
	var to := (p - m.spot) * (-1.0 if backing else 1.0)
	var off := wrapf(atan2(-to.y, to.x) - m.angle, -PI, PI)
	m.steer = clampf(-off * 3.0, -1.0, 1.0)
	return off

func tick(dt: float) -> void:
	clock += dt
	m.throttle = 0.0
	m.steer = 0.0
	m.lift_cmd = 0.0
	m.curl_cmd = 0.0
	var r: Rect2 = job["rect"]
	match state:
		"scoop":
			# The bucket stays up until it's nearly there, so it doesn't scrape up the work on the way across. Then low, with the edge
			# held just off the firm ground, so what goes in is dust and not dirt.
			var near := m.spot.distance_to(target) < _reach() + 2.5
			if near:
				if m.arm > m.arm_low + 0.02:
					m.lift_cmd = -1.0
			elif m.arm < lerpf(m.arm_low, m.arm_high, 0.3):
				m.lift_cmd = 1.0
			_hold_edge(0.02)
			var off := _aim(target)
			m.throttle = 1.0 if absf(off) < 0.5 else 0.0
			if m.fill() > 0.95 or clock > 14.0:
				state = "lift"
				clock = 0.0
		"lift":
			m.curl_cmd = 1.0 if m.curl < 0.6 else 0.0
			m.lift_cmd = 1.0 if m.arm < lerpf(m.arm_low, m.arm_high, 0.45) else 0.0
			m.throttle = -1.0
			if clock > 1.6:
				state = "to_lane"
				clock = 0.0
		"to_lane":
			var mouth := Vector2(lane_x, r.end.y + 2.2)
			var off := _aim(mouth)
			m.throttle = 1.0 if absf(off) < 0.35 else 0.0
			if m.spot.distance_to(mouth) < 0.5:
				state = "to_drop"
				clock = 0.0
		"to_drop":
			var off := _aim(Vector2(lane_x, r.position.y - 4.0))
			m.throttle = 1.0 if absf(off) < 0.35 else 0.0
			# Allowing for how far it takes to stop.
			if m.spot.y <= drop_z + _reach() + absf(m.speed) * 0.75:
				state = "stop"
				clock = 0.0
		"stop":
			if absf(m.speed) < 0.05:
				state = "dump"
				clock = 0.0
		"dump":
			m.curl_cmd = -1.0
			if m.bucket_mm == 0 and clock > 0.3:
				m.curl_cmd = 0.0
				m.toggle_spread()
				state = "settle"
				clock = 0.0
		"settle":
			if m.arm <= m.arm_low + 0.05:
				var low_reach: float = m.pivot.x + cos(m.arm_low) * m.arm_len + cos(Loader.SPREAD_CURL) * m.bucket_len
				creep_to = maxf(m.spot.y - 1.0, r.position.y + low_reach + 0.1)
				state = "push"
				clock = 0.0
		"push":
			# Into the heap, which goes along in front and leaves an even layer behind.
			m.throttle = 0.6
			_aim(Vector2(lane_x, r.position.y - 4.0))
			if m.spot.y <= creep_to or clock > 5.0:
				state = "back_up"
				clock = 0.0
		"back_up":
			_aim(Vector2(lane_x, r.end.y + 40.0), true)
			m.throttle = -1.0
			if m.spot.y > r.end.y + 1.6:
				trip += 1
				_next_trip()

## How far ahead of its middle the bucket's edge is.
func _reach() -> float:
	return m._edge_local().x

## Curls the bucket so its edge sits this far above the firm ground under it.
func _hold_edge(above: float) -> void:
	var gap := m.teeth.y - sim.firm_at(Vector2(m.teeth.x, m.teeth.z)) - above
	if m.arm > m.arm_low + 0.05:
		m.curl_cmd = 1.0 if m.curl < 0.25 else -1.0 if m.curl > 0.3 else 0.0
	else:
		m.curl_cmd = clampf(-gap * 6.0, -0.5, 0.5)
