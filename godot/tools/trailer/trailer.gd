extends SceneTree
## The trailer (the owner, 22 Oct: "cheery, happy music, feeding the chickens and digging and catching worms, then cutting
## to the fight ... one step of the peaceful stuff, then back to gory"). A shot list played in the real game, in time
## with tools/trailer/make_music.py's tune (120 bpm: a bar is 2 s): the farm's calm shots and one-second bursts of gore
## swapping, then the loop (the shredder, the crops growing on it, the weapon bench, a bigger hole), the swaps coming
## faster, the record scratch, THE BUTCHER, his slam, the title, a last joke. Letterboxed, the HUD hidden; the farm from
## cameras of its own, the fights first person as you play them.
## Render (tools/trailer/render.sh does it all): godot --rendering-method forward_plus --write-movie out.avi
## --fixed-fps 30 -s res://tools/trailer/trailer.gd -- --nosave --godmode. -- --only=NAME plays one shot (with a still
## of its middle in --stills=dir) to check it. Owned by the voxel session.

const FPS := 30.0
const WARM := 2.0               # seconds of loading before the trailer's first frame (cut off after)
const BAR := 2.0

var arena: Node
var frame := 0
var t := 0.0                    # the trailer's clock (frames / FPS: hit-stops don't stretch it)
var warm := WARM
var shots := []                 # [name, start, end]
var cur := -1
var only := ""
var stills := ""
var quality := ""               # --quality=ultra|extreme...: the settings preset to film at
var cine: Camera3D
var _cam_k := {}                # the cinematic camera's move: {a, a_at, b, b_at, fov}
var ui: CanvasLayer
var _black: ColorRect
var _text: Label
var _text_k := []               # [shown from, to] (shot time)
var _title: Label
var _tag: Label
var _bars: Array[ColorRect] = []
var v := {}                     # what a shot keeps between its frames
var _still_done := false
var _pressed := []              # [weapon id, button] pressed and not let go (let go at the next cut)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--stills="):
			stills = a.trim_prefix("--stills=")
		elif a.begins_with("--quality="):
			quality = a.trim_prefix("--quality=")
	# a game on the shelf for the couch shot (a copy of the test cartridge; taken away at the end)
	var dir := ProjectSettings.globalize_path("user://games")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets/voxel/retro/test_cart.md"), dir.path_join("Robo Brawl.md"))
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)
	shots = [
		["yard", 0.0, 6.0], ["g_shotgun", 6.0, 7.0], ["chickens", 7.0, 10.0], ["g_sword", 10.0, 11.0],
		["dig", 11.0, 14.0], ["g_harpoon", 14.0, 15.0], ["water", 15.0, 18.0], ["g_chainsaw", 18.0, 19.0],
		["chicks", 19.0, 20.0],
		["shredder", 20.0, 22.0], ["grow", 22.0, 24.0], ["bench", 24.0, 26.0], ["g_big", 26.0, 28.0],
		["g_grenade", 28.0, 30.0], ["couch", 30.0, 31.0], ["g_flame", 31.0, 32.0], ["bed", 32.0, 33.0],
		["g_freeze", 33.0, 34.0], ["hens", 34.0, 35.0], ["g_laser", 35.0, 36.0], ["crops", 36.0, 37.0],
		["g_bat", 37.0, 38.5], ["eggs", 38.5, 39.0], ["g_charger", 39.0, 41.0], ["g_crowd", 41.0, 44.0],
		["boss_in", 44.0, 46.5], ["boss_slam", 46.5, 48.5], ["title", 48.5, 52.5], ["gag", 52.5, 57.5],
	]
	if only != "":
		for s in shots:
			if s[0] == only:
				t = float(s[1])
	_ui()

# ---------------------------------------------------------------- the frame

func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		# (the player's only ever put somewhere in the trailer, never walked: no interpolating from where they were,
		# or a cut shows a frame from the last shot's spot)
		arena.player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		arena.cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if frame == 2 and quality != "":
		arena.settings_menu.s.set_preset(quality)
		arena.settings_menu.s.v.vsync = false
		arena.settings_menu.s.v.fps = 0
		arena.settings_menu.s.apply(arena)
	arena._next_t = -1e9                 # (no enemy walking in between shots)
	arena.player_hp = VoxelArena.HP_MAX
	_hide_hud()
	if warm > 0.0:
		warm -= 1.0 / FPS
		_black.color.a = 1.0
		return false
	t += 1.0 / FPS
	var k := -1
	for i in shots.size():
		if t >= float(shots[i][1]) and t < float(shots[i][2]):
			k = i
	if k < 0:
		_cleanup()
		return true
	if only != "" and shots[k][0] != only:
		_cleanup()
		return true
	if k != cur:
		cur = k
		v = {}
		_text_k = []
		_text.visible = false
		_title.visible = false
		_tag.visible = false
		_black.color.a = 0.0
		_still_done = false
		call("s_" + String(shots[k][0]))
	var lt := t - float(shots[k][1])
	var len_ := float(shots[k][2]) - float(shots[k][1])
	if has_method("f_" + String(shots[k][0])):
		call("f_" + String(shots[k][0]), lt)
	_cam_step(lt / len_)
	_text_step(lt)
	if stills != "" and only == "" and not v.has("_first"):
		v["_first"] = true
		_still(String(shots[k][0]) + "_0")
	if stills != "" and only == "" and not _still_done and lt >= len_ * 0.6:
		_still_done = true
		_still(String(shots[k][0]))
	elif stills != "" and only != "":
		# (one shot: four stills through it)
		var q := int(lt / len_ * 4.0)
		if q != int(v.get("_q", -1)):
			v["_q"] = q
			_still("%s_%d" % [only, q])
	return false

func _still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [stills, name])
	print("STILL ", name)

func _cleanup() -> void:
	if arena.games.tv:
		arena.games.tv.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://games").path_join("Robo Brawl.md"))

# ---------------------------------------------------------------- helpers

func _ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 20
	root.add_child(ui)
	for top in [true, false]:
		var r := ColorRect.new()
		r.color = Color.BLACK
		r.size = Vector2(1280, 92)
		r.position = Vector2(0, 0 if top else 720 - 92)
		ui.add_child(r)
		_bars.append(r)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.size = Vector2(1280, 720)
	ui.add_child(_black)
	_text = _label(54, Color("#fff4d6"))
	_text.position = Vector2(0, 720 - 92 - 110)
	_text.size = Vector2(1280, 90)
	_title = _label(132, Color("#f6d17a"))
	_title.add_theme_color_override("font_outline_color", Color("#7a1010"))
	_title.add_theme_constant_override("outline_size", 22)
	_title.position = Vector2(0, 230)
	_title.size = Vector2(1280, 170)
	_tag = _label(30, Color("#e8e2d0"))
	_tag.position = Vector2(0, 420)
	_tag.size = Vector2(1280, 60)

func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", maxi(6, size / 6))
	l.visible = false
	ui.add_child(l)
	return l

func _hide_hud() -> void:
	arena._hud_layer.visible = false
	arena.net_menu.visible = false
	arena.settings_menu.visible = false
	if cur < 0 or shots[cur][0] != "boss_in":
		arena.waves._layer.visible = false

## Words at the bottom from a to b seconds into the shot (fading in and out).
func say(s: String, a: float, b: float) -> void:
	_text.text = s
	_text_k = [a, b]

func _text_step(lt: float) -> void:
	if _text_k.is_empty():
		return
	var a: float = _text_k[0]
	var b: float = _text_k[1]
	_text.visible = lt >= a and lt <= b
	_text.modulate.a = clampf(minf((lt - a) / 0.15, (b - lt) / 0.15), 0.0, 1.0)

func _clear() -> void:
	for pb in _pressed:
		arena.melee[pb[0]].release(pb[1])
	_pressed.clear()
	for key in arena.sound._loops.keys():
		arena.sound.stop(key)
	var sh: VoxelShredder = arena.yard.shredder
	sh.queue = {}                        # (its grinding stops with its shot)
	if arena.lying > 0:
		arena.get_up()
	if arena.games.seated > 0:
		arena.games.get_up()
	for b in arena.bodies:
		b.queue_free()
	arena.bodies.clear()
	arena.kinds.clear()
	arena.frozen = false
	VoxelBody.immortal = false
	arena.set_upgrades({})
	arena.set_shovel_tier(0)
	arena.waves.on = false

## First person at p looking yaw/pitch with weapon id out.
func fp(p: Vector3, yaw: float, pitch: float, id: String) -> void:
	_clear()
	if cine:
		cine.current = false
	arena.cam.current = true
	arena.top_down = false
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch
	var i: int = arena.loadout.index_of(id)
	if i >= 0 and arena.loadout.id() != id:
		arena._switch(func(): arena.loadout.select(i))
	arena.loadout.switch_t = 0.0
	# (the view there this frame, not the last shot's: the arena's follows the player's interpolated place, a frame late)
	arena.cam.global_position = p + Vector3(0, 1.65, 0)
	arena.cam.rotation = Vector3(pitch, yaw, 0.0)

## A camera of its own moving from a (looking at a_at) to b (looking at b_at) over the shot, eased.
func cam(a: Vector3, a_at: Vector3, b: Vector3, b_at: Vector3, fov := 55.0) -> void:
	_clear()
	if cine == null:
		cine = Camera3D.new()
		cine.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # (moved every frame: no lag, no judder)
		arena.add_child(cine)
	cine.fov = fov
	cine.current = true
	_cam_k = {"a": a, "a_at": a_at, "b": b, "b_at": b_at}
	_cam_step(0.0)
	arena.player.global_position = Vector3(0, 0, 14)     # (out of the way, in the arena)

func _cam_step(k: float) -> void:
	if cine == null or not cine.current or _cam_k.is_empty():
		return
	var e := smoothstep(0.0, 1.0, k)
	cine.global_position = (_cam_k.a as Vector3).lerp(_cam_k.b, e)
	cine.look_at((_cam_k.a_at as Vector3).lerp(_cam_k.b_at, e))

func enemy(key: String, p: Vector3, yaw := 0.0) -> VoxelBody:
	var b: VoxelBody = arena.spawn_kind(key, p)
	b.yaw = yaw
	b.animate(0.0, false)
	return b

func press(id: String, btn := MOUSE_BUTTON_LEFT) -> void:
	arena.melee[id].press(btn)
	_pressed.append([id, btn])

func hold(id: String, btn := MOUSE_BUTTON_LEFT) -> void:
	arena.melee[id].hold(btn, 1.0 / FPS)

func release(id: String, btn := MOUSE_BUTTON_LEFT) -> void:
	arena.melee[id].release(btn)
	_pressed.erase([id, btn])

## Head (or any part) off b whole, flung, with a spray, if the weapon didn't do it.
func off(b: VoxelBody, part: String, fling: Vector3) -> void:
	if not is_instance_valid(b) or not b.parts.has(part) or b.parts[part].gone:
		return
	var at: Vector3 = b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(b.parts[part].bone)).origin
	var r: Dictionary = b.sever(part)
	if not (r.pieces as Array).is_empty():
		arena.pieces.spawn(b, r.pieces, fling, Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)))
	var bits := []
	for i in 40:
		bits.append({"pos": at + Vector3(randf_range(-0.04, 0.04), randf_range(-0.04, 0.04), randf_range(-0.04, 0.04)),
			"col": VoxelBody.FLESH[i % VoxelBody.FLESH.size()]})
	arena.debris.burst(bits, fling.normalized() + Vector3.UP * 0.5, 2.5)
	arena.sound.play("flesh_tear", at, 0.0)

func _eye() -> Vector3:
	return arena.cam.global_position

## yaw/pitch from the eye at p to look at q.
func aim_at(p_eye: Vector3, q: Vector3) -> Vector2:
	var d := q - p_eye
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func look(p: Vector3, q: Vector3, id: String) -> void:
	var a := aim_at(p + Vector3(0, 1.62, 0), q)
	fp(p, a.x, a.y, id)

# the yard as it'll be seen: rows of crops at every stage, a few young ones, hens about
func _yard_setup(young := false) -> void:
	var farm: VoxelFarm = arena.yard.farm
	if v.get("yard_done", false):
		return
	var base := farm.spot_of(Vector3(10.0, 0, 28.0))
	for s in 6:
		var keys := []
		for k in 7:
			keys.append(base + s * 2000 + k)
		arena.yard.till(keys)
		for k in 7:
			var g: float = 0.08 if young else [0.4, 0.7, 1.0, 1.0, 0.7, 1.0, 0.4][k]
			farm.plants[base + s * 2000 + k] = {"s": s % 4, "g": g, "wet": 100.0, "dry": 0.0, "wilt": 0, "fed": 0}
			farm._changed(base + s * 2000 + k)
	arena.yard.ground.finish()

func _hens(spots: Array, st := "peck", age := 1.0) -> void:
	var ch: VoxelChickens = arena.yard.chickens
	ch.level = 2
	ch.gate = true
	ch.food = 40.0
	ch.hens.clear()
	for i in spots.size():
		var h: Dictionary = ch._hatch(spots[i], age if i % 4 != 3 else 0.2, i % 3)
		h.full = 0.9
		h.t = 999.0 if st != "walk" else 0.0
		h.st = st if st != "walk" else "idle"

func _plants_g(g: float) -> void:
	var farm: VoxelFarm = arena.yard.farm
	for key in farm.plants:
		var st0 := VoxelFarm.stage_of(float(farm.plants[key].g))
		farm.plants[key].g = g
		if VoxelFarm.stage_of(g) != st0:
			farm._changed(key)

# ---------------------------------------------------------------- the shots

func s_yard() -> void:
	_yard_setup()
	_hens([Vector2(17.0, 31.5), Vector2(18.2, 30.6), Vector2(16.4, 33.0), Vector2(19.0, 32.4), Vector2(15.6, 30.2),
		Vector2(18.6, 34.4), Vector2(20.2, 29.8), Vector2(14.8, 34.8)], "walk")
	cam(Vector3(21.8, 5.5, 39.6), Vector3(13.0, 0.4, 29.0), Vector3(19.2, 2.0, 35.6), Vector3(12.6, 0.5, 28.6), 60.0)

func s_g_shotgun() -> void:
	look(Vector3(0, 0, 5), Vector3(0, 1.25, 2.6), "shotgun")
	v.b = enemy("grunt", Vector3(0, 0, 2.4))

func f_g_shotgun(lt: float) -> void:
	if lt >= 0.3 and not v.has("fired"):
		v.fired = true
		press("shotgun")
		release("shotgun")

func s_chickens() -> void:
	_hens([Vector2(25.0, 28.0), Vector2(25.7, 28.4), Vector2(24.4, 28.8), Vector2(25.3, 29.3), Vector2(23.9, 27.6),
		Vector2(26.4, 27.8)], "peck")
	cam(Vector3(26.3, 0.42, 30.9), Vector3(25.0, 0.22, 28.2), Vector3(25.8, 0.36, 30.0), Vector3(25.0, 0.2, 28.3), 50.0)

func s_g_sword() -> void:
	look(Vector3(0, 0, 4.5), Vector3(0, 1.45, 3.0), "sword")
	v.b = enemy("grunt", Vector3(0, 0, 3.0))
	arena.frozen = true

func f_g_sword(lt: float) -> void:
	if lt >= 0.25 and not v.has("cut"):
		v.cut = true
		arena._mouse_v = Vector2(1500, 0)
		arena.me.mouse_v = Vector2(1500, 0)
		press("sword")
		release("sword")
	if lt >= 0.42 and not v.has("sure"):
		v.sure = true
		off(v.b, "head", Vector3(1.4, 2.2, -0.6))
	if lt >= 0.45:
		arena.frozen = false

func s_dig() -> void:
	look(Vector3(18.6, 0, 23.7), Vector3(18.6, -0.15, 25.4), "shovel")
	arena.set_shovel_tier(2)             # (the golden one: big scoops, the dirt flying)

func f_dig(lt: float) -> void:
	for at in [0.2, 1.1, 2.0]:
		if lt >= at and not v.has(at):
			v[at] = true
			press("shovel")
			release("shovel")
	if lt >= 0.85 and not v.has("worm"):
		v.worm = true
		var w := VoxelWorm.new()
		arena.add_child(w)
		w.start(Vector3(18.75, -0.08, 25.15), arena.player)
		arena.sound.play("worm_find", Vector3(18.6, 0, 25.2), 0.0)

func s_g_harpoon() -> void:
	look(Vector3(0, 0, 6), Vector3(0, 1.3, -2.0), "harpoon")
	v.b = enemy("grunt", Vector3(0, 0, -2.0))

func f_g_harpoon(lt: float) -> void:
	if lt >= 0.05 and not v.has("fired"):
		v.fired = true
		press("harpoon", MOUSE_BUTTON_RIGHT)
		release("harpoon", MOUSE_BUTTON_RIGHT)

func s_water() -> void:
	look(Vector3(11.3, 0, 31.4), Vector3(11.4, 0, 29.6), "can")
	_yard_setup(true)
	arena.melee.can.water = VoxelFarm.CAN
	press("can")

func f_water(lt: float) -> void:
	hold("can")
	_plants_g(clampf(0.08 + lt * 0.32, 0.0, 1.0))
	if lt > 2.9:
		release("can")

func s_g_chainsaw() -> void:
	look(Vector3(0, 0, 4.2), Vector3(-0.35, 1.15, 3.0), "chainsaw")
	v.b = enemy("brute", Vector3(0, 0, 3.0))
	arena.frozen = true
	press("chainsaw")

func f_g_chainsaw(lt: float) -> void:
	hold("chainsaw")
	var a := aim_at(Vector3(0, 1.62, 4.2), Vector3(lerpf(-0.45, 0.5, clampf(lt / 0.9, 0, 1)), 1.15 - 0.15 * lt, 3.0))
	arena.look_yaw = a.x
	arena.look_pitch = a.y

func s_chicks() -> void:
	_hens([Vector2(25.0, 28.0), Vector2(25.3, 28.2), Vector2(24.8, 28.4), Vector2(25.5, 27.8)], "peck", 0.2)
	cam(Vector3(25.6, 0.25, 29.1), Vector3(25.1, 0.12, 28.1), Vector3(25.5, 0.22, 28.9), Vector3(25.1, 0.12, 28.1), 45.0)

func s_shredder() -> void:
	var sh: VoxelShredder = arena.yard.shredder
	sh.tier = 2
	sh._show_tier()
	sh.queue = {"meat": 900000}
	sh.bags = 4
	AudioServer.set_bus_volume_db(0, -6.0)
	sh.ground = 120000.0
	var at := VoxelShredder.AT
	cam(at + Vector3(-1.6, 1.7, -2.6), at + Vector3(0, 1.0, 0), at + Vector3(-0.8, 1.5, -2.1), at + Vector3(0, 1.0, 0), 50.0)
	say("Grow your own...", 0.15, 1.95)

func f_shredder(lt: float) -> void:
	# limbs and gore tipped in at the top
	if int(lt * 10) != int(v.get("k", -1)):
		v.k = int(lt * 10)
		var bits := []
		for i in 14:
			bits.append({"pos": VoxelShredder.AT + Vector3(randf_range(-0.2, 0.2), 1.9 + randf() * 0.3, randf_range(-0.2, 0.2)),
				"col": VoxelBody.FLESH[i % 4] if i % 5 else VoxelBody.BONE})
		arena.debris.burst(bits, Vector3.DOWN, 0.6)

func s_grow() -> void:
	AudioServer.set_bus_volume_db(0, 0.0)
	_yard_setup(true)
	_plants_g(0.05)
	cam(Vector3(12.6, 0.55, 26.9), Vector3(11.4, 0.3, 28.6), Vector3(12.3, 0.75, 27.1), Vector3(11.4, 0.4, 28.6), 50.0)
	say("...with 100% organic fertiliser", 0.1, 1.95)

func f_grow(lt: float) -> void:
	_plants_g(clampf(0.05 + lt * 0.55, 0.0, 1.0))

func s_bench() -> void:
	var at := VoxelUpgrades.AT
	cam(at + Vector3(-0.2, 1.55, 1.5), at + Vector3(0, 1.15, 0), at + Vector3(0.15, 1.45, 1.15), at + Vector3(0, 1.15, 0), 50.0)
	arena.cash = 1000
	say("Upgrade.", 0.1, 1.95)

func f_bench(lt: float) -> void:
	for p in [[0.35, "damage"], [0.8, "damage"], [1.2, "clip"], [1.55, "damage"]]:
		if lt >= float(p[0]) and not v.has(p[0]):
			v[p[0]] = true
			arena.upgrade_buy(String(p[1]))

func s_g_big() -> void:
	look(Vector3(0, 0, 5.4), Vector3(0, 1.35, 3.0), "shotgun")
	arena.set_upgrades({"damage": 3, "clip": 1, "fuel": 0})
	v.b = enemy("brute", Vector3(0, 0, 3.0))
	arena.frozen = true
	say("Repeat.", 0.1, 1.9)

func f_g_big(lt: float) -> void:
	for at in [0.3, 1.15]:
		if lt >= at and not v.has(at):
			v[at] = true
			press("shotgun")
			release("shotgun")

func s_g_grenade() -> void:
	look(Vector3(0, 0, 9), Vector3(0, 0.6, -0.5), "grenades")
	for i in 7:
		enemy(["grunt", "swarmer", "grunt", "batter", "grunt", "swarmer", "charger"][i], Vector3(-1.5 + (i % 4) * 1.0, 0, -0.8 + (i / 4) * 1.1))

func f_g_grenade(lt: float) -> void:
	if lt >= 0.08 and not v.has("f"):
		v.f = true
		press("grenades")
		release("grenades")

func s_couch() -> void:
	_clear()
	if cine:
		cine.current = false
	arena.cam.current = true
	var g: VoxelGamesRoom = arena.games
	if g.inserted < 0:
		g.take(0)
		g.insert(0)
	g.sit(1)
	arena.look_pitch = -0.08
	arena._camera(0.0)

func s_g_flame() -> void:
	look(Vector3(0, 0, 6), Vector3(0, 1.0, 2.8), "flamethrower")
	for x in [-0.9, 0.0, 0.9]:
		enemy("grunt", Vector3(x, 0, 2.6 - absf(x) * 0.3))
	press("flamethrower")

func f_g_flame(lt: float) -> void:
	hold("flamethrower")
	var a := aim_at(Vector3(0, 1.62, 6), Vector3(sin(lt * 4.0) * 0.9, 1.0, 2.8))
	arena.look_yaw = a.x
	arena.look_pitch = a.y

func s_bed() -> void:
	cam(Vector3(-1.4, 1.75, 29.4), Vector3(2.4, 0.55, 23.8), Vector3(-0.9, 1.6, 28.9), Vector3(2.4, 0.55, 23.8), 55.0)

func s_g_freeze() -> void:
	look(Vector3(0, 0, 4.4), Vector3(0, 1.0, 3.0), "hammer")
	v.b = enemy("grunt", Vector3(0, 0, 3.0))
	arena.frozen = true
	v.b.chill(1.0)
	arena._mouse_v = Vector2.ZERO
	arena.me.mouse_v = Vector2.ZERO
	press("hammer")
	release("hammer")

func s_hens() -> void:
	_hens([Vector2(28.4, 32.0), Vector2(29.6, 32.4), Vector2(27.6, 31.4), Vector2(30.4, 31.6), Vector2(28.9, 30.9)], "peck")
	cam(Vector3(25.6, 0.9, 27.6), Vector3(29.0, 0.6, 33.2), Vector3(26.2, 0.8, 28.2), Vector3(29.0, 0.6, 33.4), 50.0)

func s_g_laser() -> void:
	look(Vector3(0, 0, 5.0), Vector3(-0.55, 1.47, 3.0), "laser")
	v.b = enemy("grunt", Vector3(0, 0, 3.0))
	arena.frozen = true
	press("laser")

func f_g_laser(lt: float) -> void:
	hold("laser")
	var a := aim_at(Vector3(0, 1.62, 5.0), Vector3(lerpf(-0.55, 0.55, clampf(lt / 0.9, 0, 1)), 1.47, 3.0))
	arena.look_yaw = a.x
	arena.look_pitch = a.y

func s_crops() -> void:
	_yard_setup()
	_plants_g(1.0)
	cam(Vector3(9.4, 1.1, 26.4), Vector3(12.0, 0.4, 29.0), Vector3(10.4, 1.0, 26.2), Vector3(12.6, 0.4, 29.2), 55.0)

func s_g_bat() -> void:
	look(Vector3(0, 0, 4.6), Vector3(0, 1.5, 3.0), "bat")
	v.b = enemy("grunt", Vector3(0, 0, 3.0))
	arena.frozen = true
	press("bat", MOUSE_BUTTON_RIGHT)

func f_g_bat(lt: float) -> void:
	if lt < 1.0:
		hold("bat", MOUSE_BUTTON_RIGHT)
	elif not v.has("r"):
		v.r = true
		release("bat", MOUSE_BUTTON_RIGHT)
		arena.frozen = false

func s_eggs() -> void:
	var ch: VoxelChickens = arena.yard.chickens
	ch.level = 2
	for k in 6:
		(ch.nests[k] as Array).clear()
		for e in [0.3, 0.6, 0.9]:
			(ch.nests[k] as Array).append(e)
	var n := Vector3(VoxelChickens.NEST_X, VoxelChickens.NEST_Y, VoxelChickens.NEST_Z + VoxelChickens.NEST_DZ)
	cam(n + Vector3(-1.6, 0.5, 0.6), n + Vector3(0, -0.05, 0.2), n + Vector3(-1.4, 0.45, 0.5), n + Vector3(0, -0.05, 0.2), 55.0)

func s_g_charger() -> void:
	look(Vector3(0, 0, 8), Vector3(0, 1.1, 2.0), "pistol")
	v.b = enemy("charger", Vector3(0, 0, 2.0))
	v.b.act_cool = 0.0

func f_g_charger(lt: float) -> void:
	if is_instance_valid(v.b) and v.b.alive:
		var a := aim_at(_eye(), v.b.global_position + Vector3(0, 1.1, 0))
		arena.look_yaw = lerp_angle(arena.look_yaw, a.x, 0.3)
		arena.look_pitch = lerpf(arena.look_pitch, a.y, 0.3)
	for at in [1.35, 1.55, 1.75]:
		if lt >= at and not v.has(at):
			v[at] = true
			press("pistol")
			release("pistol")

func s_g_crowd() -> void:
	look(Vector3(0, 0, 10), Vector3(0, 0.9, 0.0), "shotgun")
	var kinds := ["grunt", "swarmer", "shielder", "charger", "batter", "grunt", "thrower", "brute", "swarmer", "grunt",
		"batter", "grunt", "swarmer", "shielder", "grunt", "charger", "grunt", "swarmer"]
	for i in kinds.size():
		var b := enemy(kinds[i], Vector3(-5.0 + (i % 6) * 2.0 + randf_range(-0.4, 0.4), 0, -3.0 - (i / 6) * 2.2 + randf_range(-0.4, 0.4)))
		b.speed *= 1.6

func f_g_crowd(lt: float) -> void:
	var a := aim_at(_eye(), Vector3(sin(lt * 1.7) * 2.0, 1.1, 10.0 - 3.5 - lt * 2.6))
	arena.look_yaw = lerp_angle(arena.look_yaw, a.x, 0.2)
	arena.look_pitch = lerpf(arena.look_pitch, a.y, 0.2)
	for at in [0.5, 1.3, 2.1, 2.8]:
		if lt >= at and not v.has(at):
			v[at] = true
			press("shotgun")
			release("shotgun")

func s_boss_in() -> void:
	cam(Vector3(1.4, 0.35, 1.2), Vector3(0, 3.4, -5.0), Vector3(1.0, 0.3, 0.6), Vector3(0, 3.3, -3.6), 60.0)
	arena.player.global_position = Vector3(0, 0, 6)
	v.b = enemy("boss", Vector3(0, 0, -6.0))
	arena.kinds.make_boss(v.b, 3.0)
	v.b.set_meta("roar_t", 99.0)
	v.b.act_cool = 99.0
	arena.waves._layer.visible = true
	arena.waves.banner(5, VoxelKinds.BOSS_HP * 3.0)
	arena.waves._banner_t = 2.4

func s_boss_slam() -> void:
	look(Vector3(0, 0, 5.4), Vector3(0, 3.0, 2.2), "pistol")
	v.b = enemy("boss", Vector3(0, 0, 2.2))
	arena.kinds.make_boss(v.b, 3.0)
	v.b.set_meta("roar_t", 99.0)
	v.b.act_cool = 99.0
	arena.frozen = true

func f_boss_slam(lt: float) -> void:
	if lt >= 0.25 and not v.has("up"):
		v.up = true
		arena.frozen = false
		v.b.act = VoxelBody.ACT_SLAM_UP
		v.b.act_t = VoxelKinds.SLAM_UP
		v.b.set_meta("act_d", VoxelKinds.SLAM_UP)
		v.b.act_cool = 0.0
		arena.sound.play("swoosh_heavy", v.b.position + Vector3.UP * 3.0, 0.0, 0.5)
	if lt >= 1.82:
		_black.color.a = 1.0

func s_title() -> void:
	_clear()
	AudioServer.set_bus_mute(0, true)
	_black.color.a = 1.0
	_title.text = "SMASHED TV"
	_title.visible = true
	_tag.text = "Grow.  Dig.  Feed the chickens.  Kill everything."
	_tag.visible = true

func f_title(lt: float) -> void:
	_title.modulate.a = clampf(lt / 0.12, 0, 1)
	_tag.modulate.a = clampf((lt - 0.6) / 0.4, 0, 1)
	if lt > 3.6:
		_title.modulate.a = clampf((4.0 - lt) / 0.4, 0, 1)
		_tag.modulate.a = _title.modulate.a

func s_gag() -> void:
	AudioServer.set_bus_mute(0, false)
	var p := Vector3(25.0, 0, 27.0)
	var b := enemy("grunt", p + Vector3(0.9, 0, 0.2), 1.6)
	b.alive = false
	b.dead_t = 99.0
	b.since_air = 99.0
	off(b, "head", Vector3(-0.4, 0.2, 0.1))
	_hens([Vector2(p.x - 0.75, p.z + 0.15)], "peck")
	cam(p + Vector3(-2.3, 1.0, 2.6), p + Vector3(0.1, 0.2, 0.0), p + Vector3(-1.9, 0.85, 2.2), p + Vector3(0.1, 0.2, 0.0), 45.0)
	say("Co-op for two  ·  PC", 1.2, 4.6)

func f_gag(lt: float) -> void:
	_black.color.a = clampf((lt - 4.3) / 0.6, 0.0, 1.0)
