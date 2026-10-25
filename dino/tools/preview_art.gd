extends SceneTree
## Lays every art/<creature>_<part>.png out on one picture, scaled up 4x, to check the import by eye.
## godot --headless --path . --script res://tools/preview_art.gd  ->  art/_preview.png
func _initialize() -> void:
	var dir := DirAccess.open("res://art")
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".png") and not f.begins_with("_"):
			files.append(f)
	files.sort()
	var out := Image.create(1400, 1400, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.2, 0.2, 0.2))
	var x := 4
	var y := 4
	var row_h := 0
	for f: String in files:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/" + f))
		img.convert(Image.FORMAT_RGBA8)
		img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
		if x + img.get_width() > out.get_width():
			x = 4
			y += row_h + 8
			row_h = 0
		out.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(x, y))
		x += img.get_width() + 8
		row_h = maxi(row_h, img.get_height())
	out.save_png(ProjectSettings.globalize_path("res://art/_preview.png"))
	quit()
