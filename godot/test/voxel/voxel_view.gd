extends Node
## The real game with the block characters on, set up for a look (web screenshots, or by hand). Options from the web
## address (?vox=a,b,...) or after -- on the command line (--vox=a,b,...):
##   pixel          start in pixel mode (default blocks)
##   pair           a pixel-art copy of player 1 standing beside him (the comparison)
##   run            walk him round in a circle; still otherwise
##   face=DEG       stand facing this way (0 toward the camera, 90 east...)
##   weapon=ID      fists, spud, blaster, shotgun, launcher (player 1's fight weapon)
##   act=ID         victory, roll (looping), reload, charge
##   fp             first person (another character shown: Gothica... and the pair copy)
##   at=X:Y         put him there (HTML units)
##   zoom=N         top-down zoom level (0..2)
##   style=N        the mirror's hair style
##   char=ID        juicy, tyson2, goth
## The lighting's own options work too (?hour=19 ...).

var main: Node
var opts := {}
var pair: CharSprite
var _t := 0.0

func _ready() -> void:
	process_priority = 850      # after the Player and the Fight have told the sprite what to show, before the blocks read it
	opts = _opts()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var sw := VoxelSwitch.install(main)
	sw.set_mode("pixel" if opts.has("pixel") else "blocks", false)
	var pl: Player = main.player
	if opts.has("char"):
		pl.char_id = String(opts["char"])
	if opts.has("style"):
		LobbyLook.load_saved()
		LobbyLook.style = int(opts["style"])
		LobbyLook.rev += 1
	if opts.has("print"):
		LobbyLook.load_saved()
		var im := (load("res://assets/COG_ART_src.png") as Texture2D).get_image()
		im.decompress()
		LobbyLook.set_art(im, false)
	if opts.has("at"):
		var a := String(opts["at"]).split(":")
		pl.place(float(a[0]), float(a[1]))
	if opts.has("zoom"):
		main.rig.zoom_level = int(opts["zoom"])
	if opts.has("pair"):
		pair = CharSprite.new()
		if not opts.has("pairblocks"):
			pair.set_meta("no_blocks", true)
		pair.name = "PixelPair"
		main.add_child(pair)
	if opts.has("fp"):
		main.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
		pl.look_y = 0.12
	pl.face_mouse = false
	if opts.has("lobby"):
		for i in 10:
			await get_tree().process_frame
		var ll := LobbyLife.current
		match String(opts["lobby"]):
			"bed":
				ll.things["bed"].lie_down(pl, 1)
			"sit":
				ll.things["table"].sit(pl, 1)
			"carry":
				var gp: Vector2 = main.gothica.html_pos2()
				pl.place(gp.x, gp.y + 20.0)
				await get_tree().process_frame
				ll.things["goth_life"].pick_up(pl)
	print("VOXVIEW ready ", opts)

func _opts() -> Dictionary:
	var s := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vox="):
			s = a.substr(6)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String:
			var i := (q as String).find("vox=")
			if i >= 0:
				s = (q as String).substr(i + 4).split("&")[0].uri_decode()
	var d := {}
	for part in s.split(",", false):
		var kv := part.split("=")
		d[kv[0]] = kv[1] if kv.size() > 1 else true
	return d

func _physics_process(delta: float) -> void:
	if main == null or main.player == null:
		return
	_t += delta
	var pl: Player = main.player
	if opts.has("weapon") and Fight.me and Fight.me.f:
		var f = Fight.me.f
		f.blasters = 99
		f.w_time = 99.0
		f.rockets = 3
		f.weapon = String(opts["weapon"])
	if opts.has("run"):
		var a := _t * 0.9
		pl.steer = Vector2(cos(a), sin(a))
		Input.action_release("move_left")
		var dir := Vector2(-sin(a), cos(a))
		_press(dir)
	elif opts.has("face"):
		var d := deg_to_rad(float(opts["face"]))
		pl.facing = Vector2(sin(d), cos(d))
		if Fight.me and Fight.me.f:
			Fight.me.f.fx = sin(d)
			Fight.me.f.fy = cos(d)

func _press(dir: Vector2) -> void:
	for act in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(act)
	if dir.x < -0.3: Input.action_press("move_left", minf(1.0, -dir.x))
	if dir.x > 0.3: Input.action_press("move_right", minf(1.0, dir.x))
	if dir.y < -0.3: Input.action_press("move_up", minf(1.0, -dir.y))
	if dir.y > 0.3: Input.action_press("move_down", minf(1.0, dir.y))

func _process(_d: float) -> void:
	if main == null:
		return
	var pl: Player = main.player
	var spr := pl.sprite
	if opts.has("face") and not opts.has("run"):
		var d := deg_to_rad(float(opts["face"]))
		pl.facing = Vector2(sin(d), cos(d))
		spr.facing = pl.facing
	if opts.has("jog"):
		spr.moving = true
		spr.odo = _t * 150.0
		var vj := spr.get_node_or_null("Blocks") as VoxelChar
		if vj:
			vj.speed_override = 150.0
	if opts.has("act"):
		match String(opts["act"]):
			"victory":
				spr.action = "victory"
			"roll":
				spr.action = "roll"
				spr.roll_t = float(opts["rollt"]) if opts.has("rollt") else fmod(_t * 1.2, 1.0)
	var vc := spr.get_node_or_null("Blocks") as VoxelChar
	if vc and opts.has("face") and not opts.has("run"):
		var d2 := deg_to_rad(float(opts["face"]))
		vc.facing_override = Vector2(sin(d2), cos(d2))
		if pair:
			spr.facing = vc.facing_override
	if vc and vc.mesh_inst:
		if opts.has("rawcol"):
			vc._mat.set_shader_parameter("srgb_colors", false)
		if opts.has("unlit"):
			vc._mat.shader = VoxelChar.shader_for(true)
		if opts.has("notip"):
			vc._mat.set_shader_parameter("tip", 0.0)
		if opts.has("plainmat") and not (vc.mesh_inst.material_override is StandardMaterial3D):
			var sm := StandardMaterial3D.new()
			sm.vertex_color_use_as_albedo = true
			sm.vertex_color_is_srgb = true
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			vc.mesh_inst.material_override = sm
		if opts.has("noskel") and vc.mesh_inst.skeleton != NodePath(""):
			vc.mesh_inst.skeleton = NodePath("")
			vc.mesh_inst.skin = null
	if opts.has("debug") and Engine.get_process_frames() % 20 == 0 and LobbyLife.current:
		var gl = LobbyLife.current.things.get("goth_life")
		var gb = main.gothica.sprite.get_node_or_null("Blocks")
		print("VOXCARRY carrier=%s pose=%s goth=%s gvis=%s" % [gl.carrier if gl else null, vc.lobby_pose if vc else "-", gb.lobby_pose if gb else "-", main.gothica.sprite.visible])
		if gb:
			print("VOXGOTH vis=%s tree=%s pos=%s gpos=%s root=%s mesh=%s goth_vis=%s" % [gb.visible, gb.is_visible_in_tree(), gb.global_position, main.gothica.global_position, gb.skeleton.get_bone_global_pose(0).origin if gb.skeleton else null, gb.mesh_inst.mesh if gb.mesh_inst else null, main.gothica.visible])
	if vc and vc.skeleton and opts.has("debug") and Engine.get_process_frames() % 20 == 0:
		print("VOXDBG st=%s key=%s made=%d pf=%d frames=%d vis=%s yaw=%.2f facing=%s root=%s mi=%s skel=%s" % [vc.last_state, spr.current_key, VoxelChar.made, Engine.get_process_frames(), vc.frames, vc.visible, vc.yaw, spr.facing, vc.skeleton.get_bone_global_pose(0), vc.mesh_inst.global_transform.origin, vc.skeleton.global_transform.basis.get_euler()])
	if opts.has("fp"):
		pl.look_ang = -PI / 2.0
		pl.look_y = 0.1
	if pair:
		pair.char_id = spr.char_id
		pair.facing = spr.facing
		pair.moving = spr.moving
		pair.odo = spr.odo
		pair.action = spr.action
		pair.roll_t = spr.roll_t
		pair.visible = true
		var off := Vector3(1.4, 0, 0) if not opts.has("fp") else Vector3(0, 0, -3.0)
		pair.global_position = pl.get_global_transform_interpolated().origin + off
		if opts.has("fp"):
			var cam := get_viewport().get_camera_3d()
			var fw := -cam.global_transform.basis.z
			fw = Vector3(fw.x, 0.0, fw.z).normalized()
			pair.global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z) + fw * 2.6
			var pb := pair.get_node_or_null("Blocks") as VoxelChar
			if pb and opts.has("jog"):
				pb.speed_override = 150.0
			if pb and opts.has("weapon"):
				pb.weapon_override = String(opts["weapon"])
			if pb and opts.has("face"):
				var d3 := deg_to_rad(float(opts["face"]))
				pb.facing_override = Vector2(sin(d3), cos(d3))
