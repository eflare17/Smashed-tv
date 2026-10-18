extends SceneTree
## Works out the diggable cells (scripts/dig/dig_mask.gd) and writes them into scripts/dig/dig_mask_data.gd,
## plus a picture of them over the yard (test/dig/mask.png, not exported) to look at.
## Run: godot --headless --path <copy> -s res://test/dig/make_mask.gd

const D := preload("res://scripts/dig/dig_data.gd")
const DigMask := preload("res://scripts/dig/dig_mask.gd")

func _init() -> void:
	var f := FileAccess.open("res://data/game_data.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var im := Image.load_from_file(ProjectSettings.globalize_path("res://assets/misc/line1985_0.webp"))
	im.convert(Image.FORMAT_RGBA8)
	var t0 := Time.get_ticks_msec()
	var m := DigMask.build(d, im)
	print("mask built in %d ms" % (Time.get_ticks_msec() - t0))
	var n := 0
	for b in m:
		n += b
	print("diggable cells: %d of %d" % [n, m.size()])
	var z := m.compress(FileAccess.COMPRESSION_DEFLATE)
	var b64 := Marshalls.raw_to_base64(z)
	var src := FileAccess.get_file_as_string("res://scripts/dig/dig_mask_data.gd")
	var a := src.find("const B64 := \"")
	var e := src.find("\"", a + 14)
	src = src.substr(0, a) + "const B64 := \"" + b64 + src.substr(e)
	var w := FileAccess.open("res://scripts/dig/dig_mask_data.gd", FileAccess.WRITE)
	w.store_string(src)
	w.close()
	print("wrote %d chars" % b64.length())
	# the picture: the yard, diggable cells tinted
	var Y: Dictionary = d.YARD
	for cy in D.NY:
		for cx in D.NX:
			if m[cy * D.NX + cx] == 0:
				continue
			for yy in 8:
				for xx in 8:
					var px := int(D.X0 + cx * 8 + xx - float(Y.ox))
					var py := int(D.Y0 + cy * 8 + yy - float(Y.oy))
					if px >= 0 and py >= 0 and px < im.get_width() and py < im.get_height():
						im.set_pixel(px, py, im.get_pixel(px, py).lerp(Color(1, 0.2, 1), 0.35))
	im.resize(1024, 1024)
	im.save_png(ProjectSettings.globalize_path("res://test/dig/mask.png"))
	quit()
