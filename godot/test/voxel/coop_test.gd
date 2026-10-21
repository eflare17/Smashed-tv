extends SceneTree
## Co-op end to end: two copies of the arena, one hosting and one joined, both players going through every weapon on
## the host's crowd at once (both buttons, R), then the bodies compared. Run the host first:
##   godot --headless --fixed-fps 60 -s res://test/voxel/coop_test.gd -- --host=COOP --via=enet --enemies=8
##   godot --headless --fixed-fps 60 -s res://test/voxel/coop_test.gd -- --join=COOP --via=enet
## (--via=rtc --server=ws://127.0.0.1:9000/ --local over WebRTC with test/voxel/peer_server.js.) Each prints "COOP ..."
## lines; the guest's last says how many fingerprint checks found a body different and how many were put right, and
## the host's lists its bodies' fingerprints so the two lists can be compared. Owned by the voxel session.

var arena: Node
var t := 0.0
var ids := []
var k := -1
var wt := 0.0
var started := -1.0
var role := ""
var done_at := -1.0
var dur := 2.6                  # seconds each weapon is used
var early := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--early":
			early = true
		if a.begins_with("--dur="):
			dur = maxf(2.6, float(a.trim_prefix("--dur=")))       # (seconds a weapon: longer to watch it)
		if a.begins_with("--host"):
			role = "host"
		elif a.begins_with("--join"):
			role = "guest"
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _ready_to_play() -> bool:
	var n = arena.net
	return n.linked and (n.role == "host" or n._got_world)

func _process(dt: float) -> bool:
	t += dt
	if arena.net == null:
		return false
	if role == "host" and early and started < 0.0 and not arena.net.linked:
		_play(dt)                    # (--early: the host fights alone first; the guest joins mid-fight)
		return false
	if not _ready_to_play() and started < 0.0:
		if t > 40.0:
			print("COOP %s FAIL: never linked (%s)" % [role, arena.net.status_text])
			return true
		return false
	if started < 0.0:
		started = t
		print("COOP %s linked after %.1f s: %d bodies" % [role, t, arena.bodies.size()])
		ids.clear()
		k = -1
		wt = 0.0
		for s in arena.loadout.slots:
			if String(s.id) != "vacuum":
				ids.append(String(s.id))
		if role == "guest":
			ids.reverse()            # (the two players on different weapons at once)
	if done_at < 0.0:
		_play(dt)
	elif t > done_at + (6.0 if role == "guest" else 20.0) or (role == "guest" and not arena.net.linked):
		var n = arena.net
		if role == "host":
			var fps := []
			for b in arena.bodies:
				fps.append("%d:%d" % [b.net_id, b.fingerprint()])
			fps.sort()
			print("COOP host done: %d bodies, sent %d KB, %d events, %d fixes" % [arena.bodies.size(), n.stats.sent / 1024, n.stats.events, n.stats.fixes])
			print("COOP host fps ", ",".join(fps))
		else:
			var fps2 := []
			for b in arena.bodies:
				fps2.append("%d:%d" % [b.net_id, b.fingerprint()])
			fps2.sort()
			print("COOP guest done: %d bodies, received %d KB, %d checks, %d bodies found different, %d put right" % [arena.bodies.size(), n.stats.recv / 1024, n.stats.checks, n.stats.mismatch, n.stats.fixes])
			print("COOP guest fps ", ",".join(fps2))
		return true
	return false

func _play(dt: float) -> void:
	if ids.is_empty():
		for s in arena.loadout.slots:
			if String(s.id) != "vacuum":
				ids.append(String(s.id))
	if k >= ids.size():
		k = -1                       # (fighting alone before the guest came: round again)
	var id: String = ids[k] if k >= 0 else ""
	if k < 0 or wt > dur:
		if k >= 0 and arena.melee.has(id):
			arena.melee[id].release(MOUSE_BUTTON_LEFT)
			arena.net.local_input("release", MOUSE_BUTTON_LEFT)
			arena.melee[id].release(MOUSE_BUTTON_RIGHT)
			arena.net.local_input("release", MOUSE_BUTTON_RIGHT)
		k += 1
		wt = 0.0
		if k >= ids.size():
			done_at = t
			print("COOP %s played every weapon" % role)
			return
		id = ids[k]
		var i: int = arena.loadout.index_of(id)
		arena._switch(func(): arena.loadout.select(i))
		arena.loadout.switch_t = 0.0
		if role == "host" and arena.bodies.filter(func(b): return b.alive).size() < 5:
			arena.spawn(3)
	wt += dt
	# look at the nearest one standing (each player from where they are)
	var best: VoxelBody = null
	for b in arena.bodies:
		if b.alive and (best == null or b.global_position.distance_to(arena.player.global_position) < best.global_position.distance_to(arena.player.global_position)):
			best = b
	if best:
		var to: Vector3 = best.global_position + Vector3(0, 1.1, 0) - arena.cam.global_position
		arena.look_yaw = atan2(-to.x, -to.z)
		arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	var w = arena.melee.get(id)
	if w == null:
		return
	var once := dt * 1.5
	var n = arena.net
	if wt < once:
		w.press(MOUSE_BUTTON_LEFT)
		n.local_input("press", MOUSE_BUTTON_LEFT)
	elif wt < 0.8:
		w.hold(MOUSE_BUTTON_LEFT, dt)
	elif wt < 0.8 + once:
		w.release(MOUSE_BUTTON_LEFT)
		n.local_input("release", MOUSE_BUTTON_LEFT)
	elif wt > 1.2 and wt < 1.2 + once:
		w.press(MOUSE_BUTTON_LEFT)
		n.local_input("press", MOUSE_BUTTON_LEFT)
		w.release(MOUSE_BUTTON_LEFT)
		n.local_input("release", MOUSE_BUTTON_LEFT)
	elif wt > 1.5 and wt < 1.5 + once:
		w.press(MOUSE_BUTTON_RIGHT)
		n.local_input("press", MOUSE_BUTTON_RIGHT)
	elif wt > 1.5 and wt < 2.2:
		w.hold(MOUSE_BUTTON_RIGHT, dt)
	elif wt > 2.2 and wt < 2.2 + once:
		w.release(MOUSE_BUTTON_RIGHT)
		n.local_input("release", MOUSE_BUTTON_RIGHT)
	elif wt > 2.4 and wt < 2.4 + once:
		w.reload_key()
		n.local_input("reload")
