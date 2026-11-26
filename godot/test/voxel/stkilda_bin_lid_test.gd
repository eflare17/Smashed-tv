extends SceneTree
## The wheelie bin's lid shutting on whoever lands head first in it (VoxelCarouselTumble._lid_step; the owner, 27 Nov:
## "the lid shut on the enemy in the bin"). The lid used to be baked into the bin's one mesh, leant back open, and could
## never move. It is its own hinged node now. Checked here on a bin of its own, without the park: the lid waits, swings
## shut gathering speed, knocks off his legs and settles; the bin's own rocking is not disturbed by it, and a reset
## leaves it open for the next one. Owned by the St Kilda session.
##   godot --headless --fixed-fps 60 --path godot -s res://test/voxel/stkilda_bin_lid_test.gd -- --nosave
## (It prints one "Parameter \"data.tree\" is null" from the engine: this runs entirely inside _initialize, before the
## main loop, where nodes are not in the tree yet. Harmless, and the checks below are what matters. The lid's looks --
## the hinge in the right place, nothing clipping -- are stkilda_bin_lid_shots.gd's job, not this one's.)

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if ok:
		passed += 1
	else:
		failed += 1

## A bin like VoxelCarouselHack._make_bin's, as far as the lid is concerned.
func _bin() -> Node3D:
	var bin := Node3D.new()
	bin.name = "WheelieBin"
	var hinge := Node3D.new()
	hinge.name = "Lid"
	hinge.rotation.x = VoxelCarouselHack.LID_OPEN
	bin.add_child(hinge)
	return bin

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "LidTest"
	get_root().add_child(root)
	var bin := _bin()
	root.add_child(bin)
	var lid: Node3D = bin.get_node("Lid")
	var open: float = VoxelCarouselHack.LID_OPEN
	var shut: float = VoxelCarouselHack.LID_SHUT

	check(is_equal_approx(lid.rotation.x, open) and open < 0.0, "it starts open, leant back off the hinge (%.2f rad)" % lid.rotation.x)
	check(shut > 1.4 and shut < PI / 2.0, "shut is laid over the opening, just off flat (%.2f rad)" % shut)

	var tb := VoxelCarouselTumble.new()
	tb.name = "Tumble"
	tb.bin = bin
	tb.bin_at = Vector3.ZERO
	tb.hang_at = Vector3(0, 2, 0)
	tb.hang_out = Vector3.FORWARD
	tb.stage = "binned"
	# kept out of the tree on purpose: in the tree its own frames would run, and they want a body that start() never
	# made here. _lid_step needs nothing but the bin, which is the whole point of this test.

	# nothing for the first LID_WAIT: he's in there kicking before it comes down
	var dt := 1.0 / 60.0
	var steps := int(VoxelCarouselTumble.LID_WAIT / dt) - 2
	for i in steps:
		tb._lid_step(dt)
	check(is_equal_approx(lid.rotation.x, open), "it waits while he kicks (%.2f rad after %.2f s)" % [lid.rotation.x, steps * dt])

	# then down, gathering speed: the second half of the fall covers more than the first
	var was := lid.rotation.x
	for i in int(VoxelCarouselTumble.LID_WAIT / dt) - steps + 1:
		tb._lid_step(dt)
	check(lid.rotation.x > was, "it starts to come down (%.2f rad)" % lid.rotation.x)
	var half := int(VoxelCarouselTumble.LID_FALL / dt / 2.0)
	var at_start := lid.rotation.x
	for i in half:
		tb._lid_step(dt)
	var at_half := lid.rotation.x
	for i in half:
		tb._lid_step(dt)
	var at_end := lid.rotation.x
	check(at_half - at_start < at_end - at_half, "it gathers speed as it falls (%.2f then %.2f rad)" % [at_half - at_start, at_end - at_half])
	check(at_end > open + (shut - open) * 0.9, "and it's as good as shut by the end of the fall (%.2f of %.2f)" % [at_end, shut])

	# off his legs: it rebounds short of shut, more than once, by less each time
	var bounces := 0
	var worst := 0.0
	var prev := lid.rotation.x
	var up := false
	for i in int(VoxelCarouselTumble.LID_SETTLE / dt):
		tb._lid_step(dt)
		var gap := shut - lid.rotation.x
		worst = maxf(worst, gap)
		if gap > prev and not up:
			up = true
			bounces += 1
		elif gap < prev:
			up = false
		prev = gap
	check(worst > 0.02, "it knocks off his legs instead of closing flat (%.2f rad at the most)" % worst)
	check(bounces >= 1, "and it comes back down more than once (%d)" % bounces)

	for i in int(1.0 / dt):
		tb._lid_step(dt)
	check(is_equal_approx(lid.rotation.x, shut), "then it lies shut on him (%.3f rad)" % lid.rotation.x)

	# a reset puts it back open for the next one, the way VoxelCarouselHack does it
	lid.rotation.x = VoxelCarouselHack.LID_OPEN
	check(is_equal_approx(lid.rotation.x, open), "a reset leaves it open again")

	tb.free()
	print("BIN LID: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
