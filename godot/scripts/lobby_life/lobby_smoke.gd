class_name LobbySmoke
extends Node3D
## Puffs of smoke and steam (the HTML game's VAPOUR: the bong, the barbecue): soft round billboards that drift,
## slow, rise, grow and fade. Positions and speeds in HTML units (x, y on the ground, z up). Owned by the Lobby
## life session.

var _puffs: Array = []       # {spr, x, y, z, vx, vy, vz, r, grow, life, a, t, col}
static var _tex: Texture2D

## A puff at (x, y, z) moving (vx, vy, vz) a second; r its first radius, grow how much it swells, life seconds,
## a its first alpha. vz up; the HTML game's screen-up vy is -vz here.
func puff(x: float, y: float, z: float, vx: float, vy: float, vz: float, r: float, grow: float, life: float, a: float, col: Color = Color("#e9e6ee")) -> void:
	var s := Sprite3D.new()
	s.texture = _soft()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.no_depth_test = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.modulate = Color(col.r, col.g, col.b, a)
	add_child(s)
	_puffs.append({"spr": s, "x": x, "y": y, "z": z, "vx": vx, "vy": vy, "vz": vz, "r": r, "grow": grow,
		"life": life, "a": a, "t": 0.0})
	_place(_puffs[-1])

func count() -> int:
	return _puffs.size()

func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	for p in _puffs.duplicate():
		p.t += dt
		if p.t >= p.life:
			p.spr.queue_free()
			_puffs.erase(p)
			continue
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.z += p.vz * dt
		var k := 1.0 - dt * 1.4
		p.vx *= k
		p.vy *= k
		p.vz += 4.0 * dt
		_place(p)

func _place(p: Dictionary) -> void:
	var k: float = p.t / p.life
	var r: float = p.r + p.grow * sqrt(k)
	var s: Sprite3D = p.spr
	s.position = GameData.world_to_3d(p.x, p.y, p.z)
	s.pixel_size = r * 2.0 / 32.0 * GameData.UNIT
	var c := s.modulate
	c.a = p.a * (1.0 - k) * (1.0 - k * 0.3)
	s.modulate = c

static func _soft() -> Texture2D:
	if _tex:
		return _tex
	var im := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			# a brighter core up and to the left, like the HTML game's second, white circle
			var hl := clampf(1.0 - Vector2(x - 12, y - 11).length() / 9.0, 0.0, 1.0) * 0.6
			im.set_pixel(x, y, Color(1, 1, 1, clampf(a * 1.6, 0.0, 1.0) * (0.8 + hl * 0.3)))
	_tex = ImageTexture.create_from_image(im)
	return _tex
