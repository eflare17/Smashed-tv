extends SceneTree
## A MOCK-UP video of playing a herbivore (the owner's idea, not in the game): a tiny fruitadens (the compsognathus
## tinted green, as a stand-in) nibbles a fern, ducks into a bush as a raptor goes by; later, a triceratops (the
## charger) charges a raptor and gores chunks out of it. Everything here is puppeted by this script. Record with:
##   godot --path . --write-movie herbivore.avi --fixed-fps 30 --script res://tests/video_herbivore.gd

var main: Node
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int, follow: Node2D = null) -> void:
	for i in n:
		if follow:
			main.player.position = follow.position
		await process_frame
		while main.state == main.CHOOSE:
			main._pick(0)

func _popup(text: String, at: Vector2, col := Color(0.8, 1.0, 0.6)) -> void:
	main.get("_popups").append([text, at, 1.0, col])

## A puppet: no brain of its own (state 99), it just goes where it's pushed and animates.
func _puppet(c: Prey) -> Prey:
	c.state = 99
	c.vel = Vector2.ZERO
	return c

func _fern(x: float) -> Sprite2D:
	var img := Image.create(22, 16, false, Image.FORMAT_RGBA8)
	var leaf := Color(0.3, 0.55, 0.22)
	for f in 7:
		var a := -PI * 0.5 + (f - 3) * 0.38
		var p := Vector2(11, 15)
		for s in 12:
			p += Vector2(cos(a), sin(a) + s * 0.06)
			if p.x >= 0 and p.x < 22 and p.y >= 0 and p.y < 16:
				img.set_pixel(int(p.x), int(p.y), leaf if s % 3 else leaf.lightened(0.25))
				if int(p.x) + 1 < 22:
					img.set_pixel(int(p.x) + 1, int(p.y), leaf.darkened(0.15))
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(img)
	s.set_meta("img", img)
	s.centered = false
	s.position = Vector2(x - 11, main.GROUND_Y - 16)
	s.z_index = -1
	main.area.add_child(s)
	return s

## A bite out of the fern: its pixels there go, and fly off as bits of leaf.
func _nibble(fern: Sprite2D, at: Vector2) -> void:
	var img: Image = fern.get_meta("img")
	var c := at - fern.position
	var bits: Array = []
	for y in img.get_height():
		for x in img.get_width():
			if Vector2(x, y).distance_to(c) < 3.2 and img.get_pixel(x, y).a > 0.0:
				bits.append([fern.position + Vector2(x, y), img.get_pixel(x, y)])
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	(fern.texture as ImageTexture).update(img)
	main.gore.spray(bits, Vector2(-1, -0.6), 0.9)
	main.sfx.play("tear", 0.1, -6.0)

func _bush(x: float) -> Sprite2D:
	var img := Image.create(60, 30, false, Image.FORMAT_RGBA8)
	var leaf := Color(0.16, 0.36, 0.16)
	for k in 26:
		var c := Vector2(rng.randf_range(10, 50), rng.randf_range(10, 26))
		var r := rng.randf_range(6, 11)
		for y in 30:
			for xx in 60:
				if Vector2(xx, y).distance_to(c) < r:
					var col := leaf.lightened(0.18) if y < c.y - r * 0.4 else leaf
					if (xx * 3 + y * 5) % 9 == 0:
						col = col.darkened(0.25)
					img.set_pixel(xx, y, col)
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(img)
	s.centered = false
	s.position = Vector2(x - 30, main.GROUND_Y - 29)
	s.z_index = 3
	main.area.add_child(s)
	return s

func _run() -> void:
	rng.seed = 5
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.auto_zoom = false
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()
	var pl: Player = main.player
	pl.visible = false
	# 1. tiny: nibble, hide, the raptor goes by
	main.zoom_mult = 2.1
	var fx := 300.0
	var fern1 := _fern(fx)
	_fern(fx + 40.0)
	var bush := _bush(fx - 70.0)
	var me := _puppet(main.spawn_prey(fx - 110.0, Prey.COMPY))
	me.rig.modulate = Color(0.75, 1.1, 0.65)
	me.set_facing(1.0)
	main.hud.show_banner("YOU ARE A FRUITADENS", 2.0)
	me.vel.x = 28.0
	for f in 75:
		await _frames(1, me)
		if me.position.x > fx - 12.0:
			me.vel.x = 0.0
	me.vel.x = 0.0
	for k in 3:
		_nibble(fern1, me.front_point() + Vector2(2, -2 + k * 2))
		_popup("MUNCH", me.position + Vector2(0, -16))
		await _frames(18, me)
	# a raptor
	var raptor := _puppet(main.spawn_hunter(fx + 110.0)) as Hunter
	raptor.set_facing(-1.0)
	raptor.vel.x = -55.0
	main.hud.show_banner("A RAPTOR! HIDE!", 1.6)
	main.sfx.play("cry", 0.05, -4.0)
	await _frames(12, me)
	me.set_facing(-1.0)
	me.vel.x = -75.0
	for f in 60:
		await _frames(1, me)
		if me.position.x < bush.position.x + 30.0:
			me.vel.x = 0.0
	_popup("HIDDEN", me.position + Vector2(0, -22), Color(0.6, 1.0, 0.6))
	# the raptor sniffs about by the bush, then walks on
	for f in 70:
		await _frames(1, me)
		if raptor.position.x < bush.position.x + 52.0 and raptor.vel.x != 0.0:
			raptor.vel.x = 0.0
			_popup("?", raptor.position + Vector2(0, -30), Color(1, 0.8, 0.4))
	raptor.set_facing(-1.0)
	raptor.vel.x = -50.0
	await _frames(55, me)
	_popup("PHEW", me.position + Vector2(0, -22))
	await _frames(20, me)
	# 2. later, big: a triceratops gores a raptor
	main.hud.show_banner("LATER... YOU ARE A TRICERATOPS", 2.2)
	main.hud.flash(Color(0, 0, 0), 0.8)
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()
	main.zoom_mult = 0.9
	var trike := _puppet(main._spawn_herd_kind(Area.HERD_CHARGER, 700.0))
	trike.set_facing(1.0)
	var r1 := _puppet(main.spawn_hunter(900.0)) as Hunter
	var r2 := _puppet(main.spawn_hunter(960.0)) as Hunter
	for r: Hunter in [r1, r2]:
		r.set_facing(-1.0)
		r.vel.x = -45.0
	for f in 50:
		await _frames(1, trike)
		for r: Hunter in [r1, r2]:
			if r.position.x < trike.position.x + 130.0:
				r.vel.x = 0.0
	# paw the ground (the flashing warning), then charge
	main.sfx.play("thud", 0.1, -2.0)
	for f in 24:
		(trike.rig.material as ShaderMaterial).set_shader_parameter("flash", 0.4 if f % 4 < 2 else 0.0)
		await _frames(1, trike)
	main.sfx.play("cry", 0.1, 0.0)
	trike.vel.x = 150.0
	var gored := 0
	for f in 90:
		await _frames(1, trike)
		var horn: Vector2 = trike.front_point()
		if gored < 6 and absf(horn.x - r1.global_position.x) < 14.0:
			# the horns tear chunks out, and the raptor is thrown back
			var at := r1.global_position + Vector2(rng.randf_range(-6, 6), -r1.height * r1.scale.y * rng.randf_range(0.3, 0.7))
			var res: Dictionary = r1.bite(at, 7.0, rng)
			main.gore.spray(res.removed, Vector2(1, -0.4), 0.5)
			main.gore.blood(at, Vector2(1, -0.5), 14, 140.0)
			for isl: Dictionary in res.islands:
				main.gore.piece(isl, Vector2(rng.randf_range(40, 120), -rng.randf_range(80, 160)), 0.0)
			main.sfx.play("crunch", 0.1, 2.0)
			main.set("_shake", 0.8)
			r1.vel = Vector2(90.0, -60.0)
			gored += 1
			if gored == 6:
				r1.die()
				main._kill_moment(r1, at, Vector2(1, 0))
				_popup("GORED!", r1.global_position + Vector2(0, -40), Color(1, 0.4, 0.3))
				trike.vel.x = 0.0
				r2.set_facing(1.0)
				r2.vel.x = 110.0
		elif gored == 6:
			trike.vel.x = move_toward(trike.vel.x, 0.0, 6.0)
	await _frames(40, trike)
	main.queue_free()
	quit()
