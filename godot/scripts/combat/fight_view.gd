class_name FightView
extends FightGfx
## Draws the FightSim in 3D each frame, the HTML game's renderBase for the fight (godot/specs: weapons 11,
## gore_loot 6-11, enemies_waves 7): floor stains, shadows, plants, notes, landing rings, sparks, bullets, thrown
## potatoes, falling potatoes, rockets with their smoke, blasts, the nuke, blood sprays, corpses and flying parts,
## shrapnel, muzzle flashes, the lobby dummies, and the bars and pips over heads. Enemies, Gary and Gothica are
## EnemyView's. Positions from the sim (HTML units), drawn with FightGfx.

var sim: FightSim
var fight: Node                      ## the Fight node (players' sprites, the local player)

var _tex: Dictionary = {}
var _smoke: Array = []               # [x, y, z, vx, vy, vz, r, life, max, col]
var _trail_last: Dictionary = {}     # rocket id -> Vector3 last puff spot
var _bullet_from: Dictionary = {}    # bullet -> Vector3 where its picture starts (the gun)
var _flecks: Array = []              # [x, y, z, vx, vy, vz, life]

const HIT_Z := 26.0                  # sparks and hit sprays: about chest height on an enemy

func _ready() -> void:
	name = "FightView"

func tex(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists("res://" + path):
		t = GameData.tex(path)
	_tex[path] = t
	return t

func man(key: String):
	return GameData.manifest.get(key)

func spud_tex(i: int) -> Texture2D:
	var l = man("SPUD_SPRITES")
	return tex(l[clampi(i, 0, 4)]) if l is Array else null

func blood_tex(kind: String, i: int) -> Texture2D:
	var b = man("BLOOD_SPRITES")
	if b is Dictionary and b.has(kind):
		var l: Array = b[kind]
		return tex(l[clampi(i, 0, l.size() - 1)])
	return null

func boom_tex(i: int) -> Texture2D:
	var n = man("NUKE_SPRITES")
	return tex(n["boom"][clampi(i, 0, 7)]) if n is Dictionary else null

func aspect(t: Texture2D) -> float:
	return float(t.get_height()) / maxf(1.0, float(t.get_width())) if t else 1.0

## Rotation in the view plane (clockwise positive, like the canvas) of a direction on the ground.
func screen_rot(dx: float, dy: float, dz := 0.0) -> float:
	var d := Vector3(dx, dz, dy)
	return atan2(-d.dot(stand_up), d.dot(cam_right))

## A picture centred at a 3D point, turned rot (clockwise) in the view plane.
func sprite_at(b: Batch, c: Vector3, w: float, h: float, rot: float, col: Color, flip := false) -> void:
	var cs := cos(rot)
	var sn := sin(rot)
	var r := (cam_right * cs - stand_up * sn) * (w * 0.5 * U)
	var u := (stand_up * cs + cam_right * sn) * (h * 0.5 * U)
	if flip:
		r = -r
	quad(b, c, r, u, col)

func stand_ellipse(b: Batch, c: Vector3, rx: float, ry: float, col: Color, segs := 14) -> void:
	var prev := c + cam_right * rx * U
	for i in range(1, segs + 1):
		var a := float(i) / segs * TAU
		var p := c + cam_right * (cos(a) * rx * U) + stand_up * (sin(a) * ry * U)
		tri(b, c, prev, p, col)
		prev = p

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	begin(camera)
	if sim and camera and not (sim.secret and sim.secret.phase == "intro"):
		_draw_all(minf(delta, 0.05))
	finish()

func _draw_all(dt: float) -> void:
	var s := sim
	var col := batch(null, true, false, 1)           # plain colour, blended, depth tested
	var floor_c := batch(null, true, false, -2)      # shadows and rings on the floor
	var top := batch(null, true, true, 5)            # bars and pips: over everything
	var addc := batch(null, true, false, 6, true)    # additive glows
	# floor stains
	for sp: FT.Splat in s.splats:
		var t := blood_tex("splat", sp.k)
		if t == null:
			continue
		var w := s.tv("bloodSize", 42) * 1.5 * sp.scale
		var a := minf(1.0, sp.life / 3.0) * s.tv("splatAlpha", 0.62)
		floor_quad(batch(t, true, false, -4), sp.x, sp.y, w, w * aspect(t), sp.a, Color(1, 1, 1, a), 0.3)
	# corpses: pools, shadows, bodies, parts
	_draw_corpses(col, floor_c, dt)
	# plants
	var grow := s.tv("spudGrow", 9)
	for pl: FT.Plant in s.plants:
		var f := minf(1.0, pl.t / grow)
		var t := spud_tex(4 if f >= 1.0 else mini(3, int(floor(4.0 * f))))
		floor_ellipse(floor_c, pl.x, pl.y + 1.0, 13.0, 6.0, Color(0, 0, 0, 0.28))
		if t:
			var w := 30.0
			stand(batch(t, false), pl.x, pl.y, 0.0, w, w * aspect(t), Color.WHITE)
		if f >= 1.0:
			var g := 0.5 + 0.5 * sin(s.t * 5.0 + pl.x)
			dot(addc, pl.x, pl.y, 18.0, 2.0 + 2.0 * g, Color(1, 0.94, 0.7, 0.5 * g))
	# loose notes
	_draw_coins(col, floor_c)
	# landing rings
	var R := s.tv("blastRadius", 110)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 8.0)
	for p: FT.Fighter in s.players:
		if not p.alive or not p.aim_on:
			continue
		if not ((p.weapon == "launcher" and p.rockets > 0) or (p.weapon == "lob" and p.charging)):
			continue
		var pc: Color = FightSim.P_COLOURS[p.id % 2]
		var rr := R if p.weapon == "launcher" else s.tv("splatRadius", 72)
		floor_ellipse(floor_c, p.tx, p.ty, rr, rr, Color(pc, 0.14 + 0.06 * pulse), 0.8, 32)
		floor_ring(floor_c, p.tx, p.ty, rr, rr, 2.5, Color(pc, 0.85), 0.9, 56, 8.0, 6.0, -14.0 * pulse)
		floor_quad(floor_c, p.tx, p.ty, 14.0, 2.0, 0.0, Color(pc, 0.85), 1.0)
		floor_quad(floor_c, p.tx, p.ty, 2.0, 10.0, 0.0, Color(pc, 0.85), 1.0)
		var H := s.tv("lobHeight", 110) * 0.6
		for k in range(1, 10):
			var ss := k / 10.0
			var x := p.x + (p.tx - p.x) * ss
			var y := p.y + (p.ty - p.y) * ss
			var z := 30.0 * (1.0 - ss) + 4.0 * H * ss * (1.0 - ss)
			dot(col, x, y, z, 3.0, Color(pc, 0.35))
	for r: FT.Rocket in s.rockets:
		var sr := minf(1.0, r.t / s.tv("lobTime", 0.75))
		floor_ring(floor_c, r.tx, r.ty, R, R, 2.0, Color(0.88, 0.28, 0.25, 0.45 + 0.5 * sr), 0.9, 48)
		floor_ellipse(floor_c, r.tx, r.ty, R * sr, R * sr, Color(0.88, 0.28, 0.25, 0.08 + 0.22 * sr), 0.8, 32)
	# sparks
	for b: FT.Bit in s.bits:
		dot(col, b.x, b.y, HIT_Z, 3.0, Color(b.col, clampf(b.life / 0.6, 0.0, 1.0)))
	# the dummies (lobby)
	if s.lobby():
		_draw_dummies(col, floor_c, top)
	# bullets
	_draw_bullets(col)
	# thrown potatoes
	var husk_t := spud_tex(4)
	for h: FT.Husk in s.husks:
		var sf := maxf(0.35, 1.0 - h.dz / 260.0)
		floor_ellipse(floor_c, h.x, h.y + 2.0, 12.0 * sf, 5.0 * sf, Color(0, 0, 0, 0.3 * sf))
		if husk_t:
			var w := 28.0 if h.whole else 22.0
			sprite_at(batch(husk_t, false), p3(h.x, h.y, h.dz + w * 0.35), w, w * aspect(husk_t), h.rot, Color.WHITE)
	for r: FT.Rain in s.rain:
		if r.delay > 0.0:
			continue
		var sf := maxf(0.3, 1.0 - r.dz / 300.0)
		floor_ellipse(floor_c, r.x, r.y + 2.0, 13.0 * sf, 5.0 * sf, Color(0, 0, 0, 0.28 * sf))
		if husk_t:
			var w := 30.0 * (1.0 + 0.3 * r.squash)
			var h2 := 30.0 * aspect(husk_t) * (1.0 - 0.3 * r.squash)
			sprite_at(batch(husk_t, false), p3(r.x, r.y, r.dz + h2 * 0.5), w, h2, r.rot, Color.WHITE)
	# shrapnel: little darts, waist high, along their flight
	for sh: FT.Shard in s.shards:
		var a := atan2(sh.vy, sh.vx)
		var c := p3(sh.x, sh.y, 14.0)
		var fwd := Vector3(cos(a), 0, sin(a)) * U
		var sd := Vector3(-sin(a), 0, cos(a)) * U
		tri(col, c + fwd * 9.0, c - fwd * 6.0 - sd * 6.0, c - fwd * 6.0 + sd * 6.0, Color("#ff4d3d"))
		var c2 := c + Vector3(0, 0.3 * U, 0)
		tri(col, c2 + fwd * 4.0, c2 - fwd * 3.0 - sd * 2.5, c2 - fwd * 3.0 + sd * 2.5, Color("#ffd9c2"))
	# rockets, smoke, blasts, the nuke
	_draw_rockets(col, floor_c, dt)
	for bl: FT.Blast in s.blasts:
		var f := minf(0.999, bl.t / s.tv("blastTime", 0.6))
		floor_ring(floor_c, bl.x, bl.y, R * (0.6 + 0.5 * f), R * (0.6 + 0.5 * f), 3.0, Color(1, 0.78, 0.47, 0.5 * (1.0 - f)), 1.0, 48)
		var bt := boom_tex(int(floor(8.0 * f)))
		if bt:
			var w := s.tv("blastSize", 340) * (0.55 + 0.6 * f) * 0.6
			stand(batch(bt, true, false, 7), bl.x, bl.y, 0.0, w, w * aspect(bt), Color.WHITE)
		if f < 0.15:
			floor_ellipse(addc, bl.x, bl.y, R * 1.6, R * 1.6, Color(1, 0.96, 0.88, 0.8 * (1.0 - f / 0.15)), 2.0, 32)
	if s.nuke:
		_draw_nuke(floor_c)
	# blood sprays
	for bs: FT.Blood in s.blood:
		if bs.t < 0.0:
			continue
		var f := int(minf(7.0, floor(bs.t / s.tv("bloodTime", 0.34) * 8.0)))
		var t := blood_tex("boom" if bs.big else "hit", f)
		if t == null:
			continue
		var dw := s.tv("bloodSize", 42) * bs.scale * (1.25 if bs.big else 1.0)
		var dh := dw * aspect(t)
		var alpha := 1.0 - pow(bs.t / s.tv("bloodTime", 0.34), 3.0)
		var rot := screen_rot(cos(bs.a), sin(bs.a))
		var c := p3(bs.x, bs.y, HIT_Z - 4.0) + (cam_right * cos(rot) - stand_up * sin(rot)) * (0.15 * dw * U)
		sprite_at(batch(t, true, false, 3), c, dw, dh, rot, Color(1, 1, 1, alpha))
	# the players' extras: flashes, rings, pips, bars
	for p: FT.Fighter in s.players:
		_draw_player_extras(p, col, floor_c, top, addc)
	# gore flecks
	_draw_flecks(col, dt)

func _draw_bullets(col: Batch) -> void:
	var seen := {}
	for b: FT.Bullet in sim.bullets:
		seen[b] = true
		if not _bullet_from.has(b):
			_bullet_from[b] = _gun_point(b.owner)
		var start: Vector3 = _bullet_from[b]
		var real := p3(b.x, b.y, FightSim.SHOT_Z)
		var k := clampf(b.travelled / 70.0, 0.0, 1.0)
		var at := start.lerp(real, k) if start != Vector3.INF else real
		if fight and fight.has_method("hide_own_shot") and fight.hide_own_shot(b):
			continue
		var sp := Vector2(b.vx, b.vy).length()
		if b.spud:
			var r := b.rot + sim.t * 14.0
			var cc := at
			quad(col, cc, cam_right * (2.3 * U) * cos(r) + stand_up * (2.3 * U) * sin(r), stand_up * (1.8 * U) * cos(r) - cam_right * (1.8 * U) * sin(r), Color("#5a3b22"))
			quad(col, cc + to_cam * 0.01, cam_right * (1.6 * U), stand_up * (1.3 * U), Color("#e8d3a0"))
			continue
		var back := Vector3(-b.vx, 0, -b.vy) / maxf(sp, 1.0) * 12.0 * U
		var pc := Color("#f6d17a") if b.owner == 0 else Color("#a8d8ff")
		line3(col, at, at + back, b.size, pc)
	for b in _bullet_from.keys():
		if not seen.has(b):
			_bullet_from.erase(b)

## Where a player's gun is in 3D (the barrel map for the frame his picture shows), or INF.
func _gun_point(owner: int) -> Vector3:
	if fight == null or not fight.has_method("visual_muzzle"):
		return Vector3.INF
	return fight.visual_muzzle(owner)

func _draw_corpses(col: Batch, floor_c: Batch, dt: float) -> void:
	var s := sim
	for c: FT.Corpse in s.corpses:
		var key: String = s.e_key[c.t]
		var im := EnemyArt.corpse_tex(key, c.odo)
		var f := clampf(c.life / c.max_life, 0.0, 1.0)
		var r := s.e_rad(c.t)
		var alpha := minf(1.0, f * 2.2)
		var is_part := c.part >= 0
		if not is_part and c.mask != 0:
			var pim := blood_tex("splat", (absi(int(round(c.odo))) + c.t) % 6)
			if pim:
				var age := c.max_life - c.life
				var ps := r * 2.6 * (0.35 + 0.65 * minf(1.0, age / 1.4))
				floor_quad(batch(pim, true, false, -3), c.x, c.y + r * 0.2, ps, ps * aspect(pim), c.odo * 0.37,
					Color(1, 1, 1, alpha * 0.85 * s.tv("splatAlpha", 0.62)), 0.4)
		var sk := 0.45 if is_part else 1.0
		floor_ellipse(floor_c, c.x, c.y, r * 0.9 * sk, r * 0.6 * sk, Color(0, 0, 0, 0.3 * maxf(0.25, 1.0 - c.z / 60.0) * alpha))
		if im == null:
			continue
		var h := r * s.tv("enemyScale", 3.4)
		var k := h / float(im.get_height())
		if is_part:
			var pc := EnemyArt.gore_part(im, c.part)
			if pc.is_empty():
				continue
			var pt: Texture2D = pc.tex
			var w: float = pc.w * k
			var hh: float = pc.h * k
			sprite_at(batch(pt, false), p3(c.x, c.y, c.z + hh * 0.5 + 2.0), w, hh, c.rot, Color(1, 1, 1, alpha), c.flip)
			if c.z > 1.0 and _flecks.size() < 260 and randf() < dt * 30.0:
				_flecks.append([c.x, c.y, c.z, c.vx * 0.3 + (randf() - 0.5) * 50.0, c.vy * 0.3 + (randf() - 0.5) * 50.0, 30.0 + randf() * 50.0, 0.5 + randf() * 0.4])
		else:
			var body := EnemyArt.gore_body(im, c.mask)
			var bt: Texture2D = body.tex if not body.is_empty() else im
			# the body lies where it fell, tumbling as it slides: pivot 55% of the way down the picture
			var bw := h * float(bt.get_width()) / float(im.get_height())
			var bh := h * float(bt.get_height()) / float(im.get_height())
			var lie := clampf((c.max_life - c.life) / 0.35, 0.0, 1.0)
			var zc := h * 0.45 * (1.0 - lie) + bh * 0.25 * lie + 1.0
			sprite_at(batch(bt, false), p3(c.x, c.y, zc), bw, bh, c.rot + (PI / 2.0 if not c.flip else -PI / 2.0) * lie * 0.8,
				Color(1, 1, 1, alpha), c.flip)

func _draw_flecks(col: Batch, dt: float) -> void:
	var keep := []
	for f in _flecks:
		f[6] -= dt
		f[5] -= 420.0 * dt
		f[2] += f[5] * dt
		f[0] += f[3] * dt
		f[1] += f[4] * dt
		if f[2] <= 0.0 or f[6] <= 0.0:
			continue
		keep.append(f)
		dot(col, f[0], f[1], f[2], 2.0, Color("#c21a2e") if f[6] > 0.3 else Color("#8e1022"))
	_flecks = keep

func _draw_coins(col: Batch, floor_c: Batch) -> void:
	var s := sim
	for c: FT.Coin in s.coins:
		if c.life < 2.0 and int(floor(c.life * 8.0)) % 2 == 0:
			continue
		var in_air := c.arm > 0.0
		var sp := Vector2(c.vx, c.vy).length()
		if sp > 110.0:
			var u := Vector2(c.vx, c.vy) / sp
			var ln := minf(46.0, sp * 0.055)
			for k in range(1, 5):
				var f := k / 4.0
				var s2 := 6.0 * (1.0 - f * 0.55)
				floor_quad(col, c.x - u.x * ln * f, c.y - u.y * ln * f, s2 * 2.0, s2 * 1.2, 0.0,
					Color("#9df0b4" if c.pull else "#58b37a", 0.34 * (1.0 - f)), 6.0)
		var tt := s.t + c.phase
		var bob := sin(tt * 4.0) * 1.2
		var flat := 1.0 if c.pull else 0.35 + 0.65 * absf(cos(tt * 5.0 + c.rot))
		floor_ellipse(floor_c, c.x, c.y + 3.0, 6.0, 3.0, Color(0, 0, 0, 0.28))
		var z := 4.0 + bob + (8.0 if in_air else 0.0)
		var a := c.rot * 0.25
		floor_quad(col, c.x, c.y, 16.0, 10.0 * flat, a, Color("#2f7d4f"), z)
		floor_quad(col, c.x, c.y, 14.0, 8.0 * flat, a, Color("#7fd89a") if (in_air or c.pull) else Color("#58b37a"), z + 0.2)
		floor_quad(col, c.x, c.y, 4.8, 4.8 * flat, a, Color("#2f7d4f"), z + 0.4)

func _draw_dummies(col: Batch, floor_c: Batch, top: Batch) -> void:
	var s := sim
	var hpmax := s.tv("dummyHp", 6)
	for d: FT.Dummy in s.dummies:
		floor_ellipse(floor_c, d.x, d.y, 15.0, 8.0, Color(0, 0, 0, 0.32))
		if d.down > 0.0:
			floor_quad(col, d.x + 6.0, d.y, 34.0, 12.0, 0.3, Color("#6b5636"), 4.0)
			continue
		var rot := sin(s.t * 26.0) * d.wob * 0.35
		var sack := Color.WHITE if d.flash > 0.0 else Color("#c8a86a")
		var pivot := p3(d.x, d.y, 0.0)
		var up := stand_up.rotated(to_cam, -rot) if absf(rot) > 0.0001 else stand_up
		var rt := cam_right.rotated(to_cam, -rot) if absf(rot) > 0.0001 else cam_right
		# post, sack, rings, strap
		quad(col, pivot + up * (9.0 * U), rt * (3.0 * U), up * (9.0 * U), Color("#5a4a30"))
		var sc := pivot + up * (30.0 * U)
		var prev := sc + rt * (14.0 * U)
		for i in range(1, 17):
			var a := float(i) / 16.0 * TAU
			var pp := sc + rt * (cos(a) * 14.0 * U) + up * (sin(a) * 17.0 * U)
			tri(col, sc, prev, pp, sack)
			prev = pp
		var rc := pivot + up * (32.0 * U) + to_cam * (0.05)
		for rr in [8.0, 3.5]:
			var pr: Vector3 = rc + rt * (rr * U)
			for i in range(1, 17):
				var a := float(i) / 16.0 * TAU
				var pp: Vector3 = rc + rt * (cos(a) * rr * U) + up * (sin(a) * rr * U)
				line3(col, pr, pp, 2.0, Color(20 / 255.0, 22 / 255.0, 28 / 255.0, 0.55))
				pr = pp
		quad(col, pivot + up * (44.0 * U) + to_cam * 0.05, rt * (14.0 * U), up * (2.0 * U), Color(20 / 255.0, 22 / 255.0, 28 / 255.0, 0.5))
		if d.hp < hpmax:
			bar(top, d.x - 16.0, d.y, 54.0, 32.0, 4.0, Color(20 / 255.0, 22 / 255.0, 28 / 255.0, 0.7))
			bar(top, d.x - 16.0, d.y, 54.0, 32.0 * clampf(d.hp / hpmax, 0.0, 1.0), 4.0, Color("#f6d17a"))

func _draw_rockets(col: Batch, floor_c: Batch, dt: float) -> void:
	var s := sim
	var rs = man("ROCKET_SPRITES")
	var lit := tex(rs["lit_c" if int(Time.get_ticks_msec() / 50) % 2 else "lit_b"]) if rs is Dictionary else null
	for r: FT.Rocket in s.rockets:
		var q := s.rocket_at(r, r.t)
		var v3 := Vector3(q.vx, q.vh, q.vy)
		var dir := v3.normalized() if v3.length() > 1.0 else Vector3(0, 1, 0)
		var pos := p3(q.x, q.y, q.h)
		var sh := maxf(0.35, 1.0 - q.h / 220.0)
		floor_ellipse(floor_c, q.x, q.y, 14.0 * sh, 7.0 * sh, Color(0, 0, 0, 0.3))
		var rot := screen_rot(dir.x, dir.z, dir.y)
		# the smoke trail: a puff every 6 units of the tail's path
		var tail := pos - dir * (24.0 * U)
		var last: Vector3 = _trail_last.get(r.id, tail)
		var gap := last.distance_to(tail) / U
		var n := 0
		while gap >= 6.0 and n < 20:
			var k := 6.0 / gap
			last = last.lerp(tail, k)
			gap = last.distance_to(tail) / U
			n += 1
			if _smoke.size() < 300:
				var hp := last / U
				_smoke.append([hp.x + randf_range(-2, 2), hp.z + randf_range(-2, 2), hp.y, (randf() - 0.5) * 14.0, (randf() - 0.5) * 14.0, 6.0 + randf() * 6.0,
					2.5 + randf() * 2.5, 0.8 + randf() * 0.6, 0.0, Color("#6f6f6f") if randf() < 0.5 else Color("#8a8a8a")])
		_trail_last[r.id] = last
		if lit:
			var w := 61.0
			var h := 21.5
			var c := pos - (cam_right * cos(rot) - stand_up * sin(rot)) * (8.5 * U)
			sprite_at(batch(lit, false), c, w, h, rot, Color.WHITE)
	var keep := []
	for p in _smoke:
		p[8] += dt
		if p[8] >= p[7]:
			continue
		p[0] += p[3] * dt
		p[1] += p[4] * dt
		p[2] += p[5] * dt
		keep.append(p)
		var f: float = p[8] / p[7]
		var c: Color = p[9] if f < 0.5 else Color("#bdbdbd")
		dot(col, p[0], p[1], p[2], p[6] * 2.0 * (1.0 + 1.6 * f), Color(c, 0.75 * (1.0 - f)))
	_smoke = keep
	if s.rockets.is_empty() and _trail_last.size() > 0:
		_trail_last.clear()

func _draw_nuke(floor_c: Batch) -> void:
	var s := sim
	var n := s.nuke
	var nk = man("NUKE_SPRITES")
	if not n.boom:
		var f := minf(1.0, n.t / s.tv("nukeFall", 1.9))
		var sr := 14.0 + 46.0 * f
		floor_ellipse(floor_c, n.x, n.y, sr, sr, Color(0, 0, 0, 0.18 + 0.35 * f))
		floor_ring(floor_c, n.x, n.y, sr, sr, 2.0, Color(0.88, 0.28, 0.25, 0.35 + 0.5 * f))
		if nk is Dictionary:
			var bt := tex(nk["bomb"][mini(3, int(floor(4.0 * f)))])
			if bt:
				var h := 40.0 + 120.0 * f
				stand(batch(bt, false), n.x, n.y, 420.0 * (1.0 - f), h / aspect(bt), h, Color.WHITE)
	else:
		var f := minf(0.999, n.t / s.tv("nukeBoom", 0.85))
		var bt := boom_tex(int(floor(8.0 * f)))
		if bt:
			var w := s.tv("nukeSize", 340) * (0.55 + 0.75 * f) * 0.8
			stand(batch(bt, true, false, 7), n.x, n.y, 0.0, w, w * aspect(bt), Color.WHITE)

func _draw_player_extras(p: FT.Fighter, col: Batch, floor_c: Batch, top: Batch, addc: Batch) -> void:
	var s := sim
	if not p.alive:
		return
	var fp: bool = fight != null and fight.has_method("is_fp") and fight.is_fp(p.id)
	var r := s.tv("radius", 14)
	var head := 80.0 * (1.0 if CharFrames.is_new_art(p.ch) else 0.8)
	var blink := p.iframe > 0.0 and int(floor(p.iframe * 20.0)) % 2 == 0
	# magnet and speed rings
	if p.magnet > 0.0:
		var pr := s.tv("magnetRange", 460) * 0.5 * (0.88 + sin(s.t * 1.7) * 0.12)
		floor_ring(floor_c, p.x, p.y, pr, pr, 2.0, Color(0.96, 0.82, 0.48, 0.28), 1.2, 64)
	if p.speed > 0.0:
		floor_ring(floor_c, p.x, p.y, r * 1.3, r * 1.3, 2.0, Color(0.44, 0.83, 0.63, 0.5), 1.2, 32)
	if p.spin > 0.0:
		var frac := 1.0 - p.spin / maxf(0.05, s.tv("spinTime", 1.6))
		var segs := int(40 * frac)
		var prev := p3(p.x, p.y - (r + 14.0), 2.0)
		for i in range(1, segs + 1):
			var a := -PI / 2.0 + float(i) / 40.0 * TAU
			var pp := p3(p.x + cos(a) * (r + 14.0), p.y + sin(a) * (r + 14.0), 2.0)
			line3(floor_c, prev, pp, 3.0, Color("#f6d17a"))
			prev = pp
	if fp:
		return
	# the muzzle flash
	if p.muzzle > 0.0 and not blink:
		_draw_flash(p, col, addc)
	if blink:
		return
	# hp pips over his head
	var shown := maxi(int(s.tv("playerHp", 5)), int(ceil(p.hp)))
	# (over his head wherever it is: up on a bounce or the dive board too, as the HTML draws them inside its
	# translate(0, -p.dz))
	var lift := 0.0
	if p.node and is_instance_valid(p.node):
		var dz = p.node.get("dz")
		if dz != null:
			lift = maxf(0.0, float(dz))
	var pip_z := head * s.tv("hpHeight", 1.05) + 4.0 + lift
	for i in shown:
		var c: Color
		if i < int(ceil(p.hp)):
			c = Color("#f6d17a") if i >= int(s.tv("playerHp", 5)) else FightSim.P_COLOURS[p.id % 2]
		else:
			c = Color(1, 1, 1, 0.15)
		bar(top, p.x - shown * 3.0 + i * 6.0, p.y, pip_z, 4.0, 4.0, c)
	# throw power, shotgun time
	var bar_z := pip_z + 8.0
	if p.charging:
		bar(top, p.x - 17.0, p.y, bar_z, 34.0, 4.0, Color(20 / 255.0, 22 / 255.0, 28 / 255.0, 0.75))
		var hot := p.charge >= 1.0
		var fc := Color("#d8b878")
		if hot:
			fc = Color("#ffb070") if int(Time.get_ticks_msec() / 83) % 2 == 0 else Color("#ff6a3d")
		bar(top, p.x - 17.0, p.y, bar_z, 34.0 * p.charge, 4.0, fc)
	elif p.weapon == "shotgun" and p.w_time > 0.0:
		bar(top, p.x - 17.0, p.y, bar_z, 34.0, 4.0, Color(20 / 255.0, 22 / 255.0, 28 / 255.0, 0.75))
		var red := p.w_time < 3.0 and int(floor(p.w_time * 6.0)) % 2 == 0
		bar(top, p.x - 17.0, p.y, bar_z, 34.0 * p.w_time / s.tv("shotgunTime", 12), 4.0, Color("#e0473f") if red else Color("#f6d17a"))

## The muzzle flash (weapons 11.2): a cone, a cross and a core, pointing along the shot, at the gun.
func _draw_flash(p: FT.Fighter, col: Batch, addc: Batch) -> void:
	var g := WeaponDefs.w(p.weapon)
	var dur := float(g.get("flashTime", 0.055))
	if dur <= 0.0:
		dur = 0.055
	var t := clampf(p.muzzle / dur, 0.0, 1.0)
	var mul := sim.tv("shotgunFlash", 1.7) if p.weapon == "shotgun" else float(g.get("flash", 1.0))
	if mul <= 0.0:
		return
	var scale := mul * sim.tv("flashSize", 13)
	var grow := 1.0 if t > 0.55 else 0.55 + 0.8 * t
	var ln := scale * grow * (1.6 + 0.5 * (1.0 - t))
	var wd := scale * grow * 0.62
	var at := _gun_point_live(p)
	var rot := screen_rot(p.mdx, p.mdy)
	var fwd := (cam_right * cos(rot) - stand_up * sin(rot)) * U
	var sd := (stand_up * cos(rot) + cam_right * sin(rot)) * U
	at += to_cam * 0.04
	var a := 0.9 * (0.4 + 0.6 * t)
	# the light on the floor under the gun
	var gx := p.x + p.mdx * 30.0
	var gy := p.y + p.mdy * 30.0
	floor_ellipse(batch(null, true, false, -1), gx, gy, 0.8 * ln, 0.8 * ln, Color(1, 0.83, 0.47, 0.16 * t), 1.5, 18)
	_poly(col, at, fwd, sd, [Vector2(ln, 0), Vector2(0.35 * wd, -wd), Vector2(-0.5 * wd, 0), Vector2(0.35 * wd, wd)], Color(1, 0.6, 0.24, a))
	_poly(col, at + to_cam * 0.005, fwd, sd, [Vector2(0.55 * ln, 0), Vector2(0, -1.15 * wd), Vector2(-0.45 * wd, 0), Vector2(0, 1.15 * wd)], Color(1, 0.83, 0.47, a))
	_poly(col, at + to_cam * 0.01, fwd, sd, [Vector2(0.55 * ln, 0), Vector2(0.2 * wd, -0.42 * wd), Vector2(-0.2 * wd, 0), Vector2(0.2 * wd, 0.42 * wd)], Color(1, 0.98, 0.91, t))

func _gun_point_live(p: FT.Fighter) -> Vector3:
	var gp := _gun_point(p.id)
	if gp == Vector3.INF:
		return p3(p.x + p.mdx * 30.0, p.y + p.mdy * 30.0, FightSim.SHOT_Z)
	return gp

func _poly(b: Batch, c: Vector3, fwd: Vector3, sd: Vector3, pts: Array, col: Color) -> void:
	var w := []
	for v in pts:
		w.append(c + fwd * v.x + sd * v.y)
	for i in range(1, w.size() - 1):
		tri(b, w[0], w[i], w[i + 1], col)
