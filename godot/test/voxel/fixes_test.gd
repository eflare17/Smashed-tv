extends SceneTree
## Small fixes from the overnight bug sweep (24 Oct), each checked on its own (headless: -s test/voxel/fixes_test.gd):
## a settings file from before Gore and Jiggle existed takes them from the preset it matches (a Low player doesn't wake
## up to Ultra gore); Jiggle Off's zero reach eases to nothing, not NaN (Gothica's torso shader). Owned by the voxel
## session.

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("FIX ok   ", what)
	else:
		failed += 1
		print("FIX FAIL ", what)

func _initialize() -> void:
	# an old settings file: the Low preset's values, no gore, no jiggle
	var path := "user://fixes_test_settings.cfg"
	var cf := ConfigFile.new()
	for k in VoxelSettings.PRESETS["low"]:
		if k != "gore" and k != "jiggle":
			cf.set_value("settings", k, VoxelSettings.PRESETS["low"][k])
	cf.set_value("settings", "fx", VoxelSettings.FX_PRESETS["low"])
	cf.save(path)
	var s := VoxelSettings.new()
	s.file = path
	s.load_file()
	check(int(s.v.gore) == int(VoxelSettings.PRESETS["low"].gore) and s.preset == "low", "an old Low settings file: gore %d (Low's), still LOW (%s)" % [int(s.v.gore), s.preset])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var e := VoxelJiggle._ease(Vector3(0.01, -0.02, 0.0), Vector3.ZERO)
	check(e == Vector3.ZERO and not is_nan(e.x) and not is_nan(e.y), "Jiggle Off: no reach, no movement, no NaN (%s)" % str(e))
	var e2 := VoxelJiggle._ease(Vector3(0.01, 0.0, 0.0), Vector3(0.02, 0.02, 0.02))
	check(e2.x > 0.0 and e2.x < 0.01, "Jiggle on: eased as before (%s)" % str(e2))
	print("FIX done %d passed, %d failed" % [passed, failed])
	quit()
