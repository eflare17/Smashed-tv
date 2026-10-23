extends SceneTree
## Makes the reshaped block characters' grids ahead (VoxelReshape is seconds of work in GDScript): every part of each
## model with "reshape", stored in assets/voxel/baked/<char>.bin with the code's version (VoxelModel.source_version).
## Run before exporting: godot --headless --path . -s res://tools/bake_reshape.gd. Owned by the voxel session.

func _initialize() -> void:
	VoxelModel.use_baked = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VoxelModel.BAKED_DIR))
	for ch in VoxelModel.VARIANTS:
		if not bool(VoxelModel.VARIANTS[ch].get("reshape", false)):
			continue
		var t0 := Time.get_ticks_msec()
		var m := VoxelModel.get_model(ch)
		var parts := {}
		for n in m.parts:
			var g := m.grid(n)
			parts[n] = {"grid": g, "origin": m.parts[n].origin}
		var f := FileAccess.open_compressed(VoxelModel.BAKED_DIR + ch + ".bin", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		f.store_var({"version": VoxelModel.source_version(), "parts": parts})
		f.close()
		print("BAKED ", ch, " ", parts.size(), " parts, ", Time.get_ticks_msec() - t0, " ms")
	quit()
