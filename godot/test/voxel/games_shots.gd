extends SceneTree
## Screenshots of Stage 7 (not headless: under a display, e.g. xvfb-run): the games room from the door, the console
## wall, the bookcase of game cases, a case open in your hands, and on the couch playing our test cartridge on the TV.
## A few stand-in games are put on the shelf for the pictures (copies of the test cartridge) and taken away after.
## -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var out := "user://"
const FAKE := ["Super Smash TV (USA).md", "Kart Racer 2.md", "Ninja Duck.sfc", "Space Blaster (Europe).md", "Tennis Ace.sms", "Pocket Rally.gg", "Mega Puzzle.sfc", "Robo Brawl.md"]

# [name, player position, yaw, pitch, what to do first]
const SHOTS := [
	["games_room", Vector3(-9.7, 0, 23.2), PI, -0.12, ""],
	["games_consoles", Vector3(-12.3, 0, 26.2), PI * 0.5, -0.15, ""],
	["games_shelf", Vector3(-6.9, 0, 26.2), -PI * 0.5, -0.2, ""],
	["games_case", Vector3(-6.9, 0, 25.0), -PI * 0.5, -0.25, "take"],
	["games_playing", Vector3(-9.7, 0, 26.4), PI, -0.05, "play"],
]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var dir := ProjectSettings.globalize_path("user://games")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in FAKE:
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets/voxel/retro/test_cart.md"), dir.path_join(f))
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if step == 0:
		arena.frozen = true
		for b in arena.bodies:
			b.queue_free()
		arena.bodies.clear()
		_setup_shot(0)
		mark = t
		step = 1
		return false
	var k2 := (step - 1) / 2
	if k2 >= SHOTS.size():
		if t - mark > 0.5:
			arena.games.tv.stop()
			var dir := ProjectSettings.globalize_path("user://games")
			for f in FAKE:
				DirAccess.remove_absolute(dir.path_join(f))
			return true
		return false
	if (step - 1) % 2 == 0:
		if t - mark > (1.2 if SHOTS[k2][4] != "play" else 3.0):
			_shot(SHOTS[k2][0])
			mark = t
			step += 1
	elif t - mark > 0.3:
		if k2 + 1 < SHOTS.size():
			_setup_shot(k2 + 1)
		mark = t
		step += 1
	return false

func _setup_shot(k: int) -> void:
	var s: Array = SHOTS[k]
	var g: VoxelGamesRoom = arena.games
	arena.player.global_position = s[1]
	arena.player.reset_physics_interpolation()
	arena.look_yaw = s[2]
	arena.look_pitch = s[3]
	match String(s[4]):
		"take":
			g.take(3)
		"play":
			g.put_back()
			g.take(0)
			g.insert(0)
			g.sit(1)
			arena.look_pitch = -0.05
