extends SceneTree
## The bulldozer's wave of clods, filmed (integration/dirt_physics_plan.md, stage 5; under a display, software-rendered
## here at a frame or two a second:
##   xvfb-run -a /root/godot/godot --path godot --fixed-fps 30 --write-movie <dir>/clip.png -s res://test/voxel/digsite_dozer_clod_clip.gd -- --nosave
## ). The yard's push (the levelled patch, the bulldozer flat out across it, blade 0.1 m in the ground) for --secs=10,
## 30 frames a second: the first half seen from in front of the blade, looking back at the heap and the blade's face;
## the second from behind and above, over the blade. Godot writes every frame as <dir>/clip00000000.png on; this
## prints the frame the push starts at (DSCLIP push from frame N), so the frames before it (the travel there, nothing
## drawn) can be thrown away. --share=0 films the blade as it was before the clods. Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
# [from this many seconds into the push, look yaw, look pitch, camera distance]
const VIEWS := [
	[0.0, PI * 0.8, -0.24, 7.5],
	[5.0, -0.55, -0.5, 8.0],
]

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var secs := 10.0
var share := -1.0
var frame := 0
var drive_t := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
		elif a.begins_with("--share="):
			share = float(a.trim_prefix("--share="))
	y.boot(self)

func _view(k: int) -> void:
	var s: Array = VIEWS[k]
	y.arena.look_yaw = float(s[1])
	y.arena.look_pitch = float(s[2])
	y.ds().machines.cam_dist = float(s[3])

func _process(dt: float) -> bool:
	t += dt
	frame += 1
	match step:
		0:
			if t > 1.5:
				RenderingServer.render_loop_enabled = false
				y.travel()
				step = 1
				mark = t
		1:
			if y.arrived() and t - mark > 1.0:
				y.level()
				step = 2
				mark = t
		2:
			if t - mark > 1.0:
				var dz := y.park_dozer()
				y.mount(dz)
				if share >= 0.0:
					dz.clod_share = share
				_view(0)
				step = 3
				mark = t
		3:
			if t - mark > 1.5:
				RenderingServer.render_loop_enabled = true
				step = 4
				mark = t
		4:
			if t - mark > 0.3:          # (a few frames drawn first: the view's come round, the ground's sections are up)
				print("DSCLIP push from frame %d" % frame)
				step = 5
		5:
			var dz := y.dozer()
			y.drive_dozer(dz, 1.0, -0.1)
			drive_t += dt
			for k in VIEWS.size():
				if drive_t >= float(VIEWS[k][0]):
					_view(k)
			if drive_t >= secs:
				print("DSCLIP done at frame %d: %.2f m, %d clods let go, %d awake" % [frame, dz.global_position.distance_to(y.dozer_start()), dz.clods_made, y.ds().dirt.n])
				return true
	return false
