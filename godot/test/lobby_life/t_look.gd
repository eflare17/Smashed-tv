extends RefCounted
## Hair and the shirt print on every juicy sheet, and the reflection copying the real sprite.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var m: LobbyMirror = ll.things["mirror"]
	LobbyLook.set_style(5)
	var im := Image.create(40, 30, false, Image.FORMAT_RGBA8)
	im.fill(Color.RED)
	LobbyLook.set_art(im, false)
	for sheet in ["juicy", "juicy_spud", "juicy_shotgun", "juicy_launcher"]:
		var n := 0
		var changed := 0
		for key in ["front_a", "side_a", "diag_b", "front_run_0", "side_run_3", "back"]:
			var path := "assets/CHARS/%s/sprites/%s.png" % [sheet, key]
			var tex := GameData.tex(path)
			if tex == null:
				continue
			n += 1
			if LobbyLook.baked(path, tex, false) != tex:
				changed += 1
		t.check(n > 0 and changed >= n - 1, "%s frames wear hair and print (%d of %d)" % [sheet, changed, n])
	# the victory and roll frames
	var vt := GameData.tex("assets/CHARS/juicy/sprites/roll1.png")
	t.check(vt != null, "roll frame exists")
	# the live sprite and its reflection
	t.place(246, 650, Vector2(0, -1))
	ll.player.char_id = "juicy_spud"
	await t.wait(0.5)
	var tex = ll.player.sprite._mat.get_shader_parameter("tex")
	t.check(ll.player.sprite.char_id == "juicy_spud" and tex != GameData.tex(ll.player.sprite.current_path), "an armed Jared wears the hair and print")
	var refl: CharSprite = m._refl.get(ll.player)
	t.check(refl != null and refl.char_id == "juicy_spud", "the reflection is the same sheet")
	# the fight session aims his sprite (toward the mouse), so the reflection copies the sprite, y turned round
	var sf: Vector2 = ll.player.sprite.facing
	t.check(refl != null and refl.facing.distance_to(Vector2(sf.x, -sf.y)) < 0.01, "the reflection faces as the sprite does, front and back swapped (%s vs %s)" % [refl.facing, sf])
	ll.player.char_id = "juicy"
	LobbyLook.set_style(0)
	LobbyLook.clear_art()
