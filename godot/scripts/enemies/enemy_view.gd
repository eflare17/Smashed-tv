class_name EnemyView
extends FightGfx
## Draws the enemies, Gary and Protect-mode Gothica from the FightSim (godot/specs/enemies_waves.md 6, 9.4, 12.4;
## modes_hud.md 2.7). Each enemy is an upright picture with the characters' own shader (CharSprite's: it stands up
## at eye level and tips back to face a camera looking down, and sorts like a standing figure), its pose picked from
## its velocity relative to the camera (the HTML's enemyPose with "toward the camera" for "down the screen"), white
## while flashing; the spawn ring shrinking onto it, the batter's red wind-up ring, a shadow and an hp bar.
## (The HTML's procedural walk rigs aren't baked yet: walking enemies bob instead.)

var sim: FightSim
var _pool: Array[Sprite3D] = []
var _goth: CharSprite
var _jan: Sprite3D
var _mats: Dictionary = {}           # Sprite3D -> ShaderMaterial

func _ready() -> void:
	name = "EnemyView"
	_jan = _new_sprite()
	_goth = CharSprite.new()
	_goth.char_id = "goth"
	_goth.auto_update = false
	_goth.visible = false
	add_child(_goth)

func _new_sprite() -> Sprite3D:
	var s := Sprite3D.new()
	s.centered = true
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.double_sided = true
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.extra_cull_margin = 3.0
	var m := ShaderMaterial.new()
	m.shader = CharSprite._shader(false)
	m.set_shader_parameter("modulate", Color.WHITE)
	m.set_shader_parameter("tip_from", 0.55)
	m.set_shader_parameter("tip_to", 0.9)
	m.set_shader_parameter("recolour", false)
	s.material_override = m
	_mats[s] = m
	s.visible = false
	add_child(s)
	return s

func _sprite(i: int) -> Sprite3D:
	while _pool.size() <= i:
		_pool.append(_new_sprite())
	return _pool[i]

## Show a picture on a pooled sprite: feet at HTML (x, y), h units tall, anchor across (0.5 middle), flipped.
func _show(s: Sprite3D, t: Texture2D, x: float, y: float, z: float, h: float, anchor: float, flip: bool, mod: Color,
		src_h := -1.0, foot_row := -1.0) -> void:
	if t == null:
		s.visible = false
		return
	s.visible = true
	if s.texture != t:
		s.texture = t
		_mats[s].set_shader_parameter("tex", t)
	_mats[s].set_shader_parameter("modulate", mod)
	var ph := float(t.get_height())
	var pw := float(t.get_width())
	s.pixel_size = h / (src_h if src_h > 0.0 else ph) * U
	s.flip_h = flip
	var ax := (0.5 - anchor) * pw
	var foot := foot_row if foot_row >= 0.0 else ph
	s.offset = Vector2(-ax if flip else ax, ph / 2.0 - (ph - foot))
	s.position = p3(x, y, z)

## Which pose the camera sees for a ground velocity (enemyPose, with the camera's "toward me" for "south").
func view_oct(x: float, y: float, vx: float, vy: float) -> int:
	var c := Vector2(to_cam.x, to_cam.z)
	if cam and cam.global_transform.basis.z.y < 0.6:
		var d := cam.global_position - p3(x, y, 0)
		c = Vector2(d.x, d.z)
	if c.length() < 0.0001:
		c = Vector2(0, 1)
	var th := atan2(vy, vx) - atan2(c.y, c.x)
	return posmod(int(round((th + PI / 2.0) / (PI / 4.0))), 8)

func _process(_delta: float) -> void:
	begin(get_viewport().get_camera_3d())
	if sim and cam:
		_draw()
	else:
		for s in _pool:
			s.visible = false
		_jan.visible = false
		_goth.visible = false
	finish()

func _draw() -> void:
	var s := sim
	var floor_c := batch(null, true, false, -2)
	var top := batch(null, true, true, 5)
	var used := 0
	for e: FT.Enemy in s.enemies:
		var key: String = s.e_key[e.t]
		var r := s.e_rad(e.t)
		var col: Color = s.e_col[e.t]
		if e.spawn > 0.0:
			floor_ring(floor_c, e.x, e.y, r * (0.6 + e.spawn * 1.6), r * (0.6 + e.spawn * 1.6), 2.0, Color(col, 0.7), 1.0, 32)
			continue
		if e.st == EnemySim.WINDUP:
			var left := clampf(e.st_t / s.tv("batWindup", 0.38), 0.0, 1.0)
			var rr := s.tv("batReach", 46) * (0.5 + left * 0.8)
			floor_ring(floor_c, e.x, e.y, rr, rr, 2.5, Color(0.85, 0.29, 0.29, 0.85), 1.1, 40)
		floor_ellipse(floor_c, e.x, e.y, r * 0.9, r * 0.6, Color(0, 0, 0, 0.3))
		var pose := "idle"
		var frame := 0
		var flip := false
		var scale := 1.0
		var anchor := 0.5
		var bob := 0.0
		if e.st != EnemySim.CHASE and key == "batter":
			var dur := s.tv("batWindup", 0.38) if e.st == EnemySim.WINDUP else (0.16 if e.st == EnemySim.SWING else s.tv("batRecover", 0.55))
			var prog := 1.0 - clampf(e.st_t / dur, 0.0, 1.0)
			var base := 0 if e.st == EnemySim.WINDUP else (2 if e.st == EnemySim.SWING else 4)
			pose = "swing"
			frame = base + (0 if prog < 0.5 else 1)
			# facing the swing: flipped when it goes left as the camera sees it
			var so := view_oct(e.x, e.y, e.sdx, e.sdy)
			flip = so >= 3 and so <= 5
			scale = 401.0 / 325.0
			anchor = 0.401
		else:
			var sp := Vector2(e.vx, e.vy).length()
			if sp >= 12.0:
				var oct := view_oct(e.x, e.y, e.vx, e.vy)
				var bat := key == "batter"
				match oct:
					0: pose = "side"
					1: pose = "side" if bat else "diag"
					2: pose = "front"
					3:
						pose = "side" if bat else "diag"
						flip = true
					4:
						pose = "side"
						flip = true
					5:
						pose = "side" if bat else "back"
						flip = true
					6: pose = "back"
					_: pose = "side"
				var n := EnemyArt.frame_count(key, pose)
				if n > 1:
					frame = int(floor(e.odo / (s.tv("enemyStride", 10) * 4.0 / n))) % n
				else:
					# no walk frames here: a step bob (the HTML's rigs plant the feet; this is the stand-in)
					bob = absf(sin(e.odo / (s.tv("enemyStride", 10) * 2.0) * PI)) * s.tv("enemyBob", 2) * 1.5
				if e.stun > 0.0:
					bob = 0.0
		var h := r * s.tv("enemyScale", 3.4) * scale
		var mod := Color(2.6, 2.6, 2.6) if e.flash > 0.0 else Color.WHITE
		if pose != "idle" and pose != "swing" and RigBaker.has_rig(key, pose):
			# the walk rig: planted feet, bending knees (80 px = his height, feet at row 96)
			_show(_sprite(used), RigBaker.frame(key, pose, e.odo, h), e.x, e.y, 0.0, h, 0.5, flip, mod, 80.0, 96.0)
		else:
			_show(_sprite(used), EnemyArt.tex(key, pose, frame), e.x, e.y, bob, h, anchor, flip, mod)
		used += 1
		var mh := s.e_max_hp(e.t)
		if mh > 1.0 and e.hp < mh:
			bar(top, e.x - r, e.y, r * s.tv("enemyScale", 3.4) + 5.0, 2.0 * r, 3.0, Color(20 / 255.0, 22 / 255.0, 28 / 255.0, 0.75))
			bar(top, e.x - r, e.y, r * s.tv("enemyScale", 3.4) + 5.0, 2.0 * r * maxf(0.0, e.hp) / mh, 3.0, Color("#f6d17a"))
	for i in range(used, _pool.size()):
		_pool[i].visible = false
	_draw_janitor(floor_c)
	_draw_goth(floor_c, top)

func _draw_janitor(floor_c: Batch) -> void:
	var j := sim.janitor
	if not sim.started or j.phase == "idle" or j.phase == "done":
		_jan.visible = false
		return
	var key := "walk1"
	match j.phase:
		"enter", "exit", "trudge":
			var dy := j.wdy
			var dx := j.wdx
			# up or down the screen as the camera sees it
			var o := view_oct(j.x, j.y, dx, dy)
			var n := int(floor(j.odo / 13.0)) % 4 + 1
			if o == 2:
				key = "front%d" % n
			elif o == 6:
				key = "back%d" % n
			else:
				key = "walk%d" % n
		"chase":
			key = "charge_a" if int(floor(j.odo / 13.0)) % 2 == 0 else "charge_b"
		"down":
			key = "down_flat" if j.t < 0.35 else "down_elbow"
		"rise":
			key = "getting_up" if j.t < 0.45 else "angry"
		"swing":
			key = ["swing_start", "swing_up", "swing_down", "swing_hit"][mini(3, int(floor(j.t / 0.30 * 4.0)))]
		"yeet":
			key = "yeet_wind" if j.t < 0.2 else "yeet"
		"bend":
			key = "crouch_start" if j.t < 0.2 else "bend"
		"pocket":
			key = "stand_up" if j.t < 0.2 else "pocket"
		"gripe", "stare":
			key = "angry"
		"regrab":
			key = "pickup"
		"whack":
			key = "swing_hit"
		"giveup":
			key = "giveup"
	var vert := key.begins_with("front") or key.begins_with("back")
	var h := 14.0 * sim.tv("spriteScale", 4.6) * sim.tv("janitorScale", 0.9) * (0.94 if vert else 1.0)
	floor_ellipse(floor_c, j.x, j.y, 12.6, 8.0, Color(0, 0, 0, 0.34))
	if j.phase in ["down", "rise", "gripe"]:
		var hm := EnemyArt.janitor_tex("hammer_prop")
		if hm:
			floor_quad(batch(hm, false), j.x + 35.0, j.y + 12.0, 26.0, 26.0 * float(hm.get_height()) / hm.get_width(), 0.0, Color.WHITE, 0.8)
	_show(_jan, EnemyArt.janitor_tex(key), j.x, j.y, 0.0, h, 0.5, j.flip and not vert, Color.WHITE)

func _draw_goth(floor_c: Batch, top: Batch) -> void:
	var g := sim.goth
	if g == null:
		_goth.visible = false
		return
	if g.carrier >= 0:
		# in his arms: lying across them, chest high (the HTML swaps in the carry pictures)
		_goth.visible = false
		var cp := CharFrames.path("goth", "front_run", 0)
		if cp != "":
			var tx := GameData.tex(cp)
			var hh := 70.0
			var ww := hh * float(tx.get_width()) / tx.get_height()
			var side := -1.0 if g.face else 1.0
			quad(batch(tx, false), p3(g.x, g.y + 2.0, 34.0) + to_cam * 0.08, cam_right * (side * hh * 0.5 * U), stand_up * (ww * 0.5 * U), Color.WHITE)
		return
	var blink := g.hurt > 0.0 and int(floor(g.hurt * 20.0)) % 2 == 0
	if g.hp <= 0.0:
		_goth.visible = false
		var t := CharFrames.path("goth", "front_run", 0)
		if t != "":
			var tx := GameData.tex(t)
			var h := 80.0
			var w := h * float(tx.get_width()) / tx.get_height()
			floor_ellipse(floor_c, g.x, g.y, 13.0, 7.0, Color(0, 0, 0, 0.35))
			var b := batch(tx, false)
			quad(b, p3(g.x, g.y, w * 0.5), Vector3(0, 0, -h * 0.5 * U), stand_up * (w * 0.5 * U), Color.WHITE)
		return
	_goth.visible = not blink
	_goth.position = p3(g.x, g.y, 0)
	_goth.facing = Vector2(g.fx, g.fy)
	_goth.moving = g.moving
	_goth.odo = g.odo
	_goth.update_view(cam)
	var y := 80.0 * 1.25 * 0.83
	bar(top, g.x - 21.0, g.y, y, 42.0, 7.0, Color(0, 0, 0, 0.65))
	var f := clampf(g.hp / g.max_hp, 0.0, 1.0)
	var c := Color("#f7a8ff") if f > 0.5 else (Color("#f6d17a") if f > 0.25 else Color("#e0473f"))
	bar(top, g.x - 20.0, g.y, y + 1.0, 40.0 * f, 5.0, c)
