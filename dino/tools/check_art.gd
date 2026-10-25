extends SceneTree
## Counts the separate blobs in each imported picture (a sprite should be one), and the transparent holes inside.
func _initialize() -> void:
	var dir := DirAccess.open("res://art")
	for f in dir.get_files():
		if not f.ends_with(".png") or f.begins_with("_"):
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/" + f))
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var seen := PackedByteArray()
		seen.resize(w * h)
		var blobs: Array = []
		for i in w * h:
			if img.get_pixel(i % w, i / w).a > 0.5 and seen[i] == 0:
				var n := 0
				var stack := PackedInt32Array([i])
				seen[i] = 1
				while not stack.is_empty():
					var j := stack[stack.size() - 1]
					stack.remove_at(stack.size() - 1)
					n += 1
					var x := j % w
					var y := j / w
					for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
						var nx: int = x + d[0]
						var ny: int = y + d[1]
						if nx >= 0 and ny >= 0 and nx < w and ny < h:
							var k := ny * w + nx
							if seen[k] == 0 and img.get_pixel(nx, ny).a > 0.5:
								seen[k] = 1
								stack.append(k)
				blobs.append(n)
		blobs.sort()
		blobs.reverse()
		print("%s %dx%d: %d blobs %s" % [f, w, h, blobs.size(), blobs.slice(0, 6)])
	quit()
