extends SceneTree
## Puts two folders of close-ups side by side (before on the left, after on the right), one row per shot.
## godot --headless --path . --script res://tools/side_by_side.gd -- --left=<dir> --right=<dir> --names=a,b,c --out=<file>
func _initialize() -> void:
	var left := ""
	var right := ""
	var names: PackedStringArray
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--left="):
			left = a.substr(7)
		elif a.begins_with("--right="):
			right = a.substr(8)
		elif a.begins_with("--names="):
			names = a.substr(8).split(",")
		elif a.begins_with("--out="):
			out = a.substr(6)
	var rows: Array = []
	for n in names:
		rows.append([Image.load_from_file(left + "/" + n + ".png"), Image.load_from_file(right + "/" + n + ".png")])
	var cw: int = rows[0][0].get_width()
	var ch: int = rows[0][0].get_height()
	var gap := 8
	var img := Image.create(cw * 2 + gap * 3, (ch + gap) * rows.size() + gap, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.1))
	for r in rows.size():
		for c in 2:
			var src: Image = rows[r][c]
			src.convert(Image.FORMAT_RGBA8)
			img.blit_rect(src, Rect2i(0, 0, cw, ch), Vector2i(gap + c * (cw + gap), gap + r * (ch + gap)))
	img.save_png(out)
	quit()
