extends SceneTree
## Packs the eight dino sheets (art/raw/<creature>_sheet.jpg) into tools/dino-refs.js at the top of the repo, as
## the style and layout references for tools/dino-maker.html. Rerun after adding or replacing a sheet:
##   godot --headless --path . --script res://tools/make_maker_refs.gd

const SHEETS := ["raptor", "hatchling", "allosaur", "tyrant", "grazer", "runner", "charger", "flyer"]
const SIZE := 768

func _initialize() -> void:
	var out := "// The dino game's sprite sheets (dino/art/raw), shrunk to %d px, used by dino-maker.html as style and\n" % SIZE
	out += "// layout references. Made by dino/tools/make_maker_refs.gd: rerun that after a sheet changes.\n"
	out += "const DINO_REFS = {\n"
	for creature: String in SHEETS:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/raw/%s_sheet.jpg" % creature))
		if img == null:
			print("%s: no sheet" % creature)
			continue
		img.resize(SIZE, SIZE * img.get_height() / img.get_width(), Image.INTERPOLATE_BILINEAR)
		var b64 := Marshalls.raw_to_base64(img.save_jpg_to_buffer(0.9))
		out += "  \"%s\": \"data:image/jpeg;base64,%s\",\n" % [creature, b64]
		print("%s: %d KB" % [creature, b64.length() / 1024])
	out += "};\n"
	var path := ProjectSettings.globalize_path("res://").path_join("../tools/dino-refs.js").simplify_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("wrote ", path)
	quit()
