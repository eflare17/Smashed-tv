extends Node3D
## A test bed for the Player, CameraRig and Hud on their own (not part of the game): the lounge floor picture
## on a floor, walls round it, a few solid boxes, a test Interactable, the player, the rig and the HUD.
## Prints "STATE ..." lines (where he is, the view, what E says) twice a second for scripted checks.
## Run it as a scene's root script (a scene in a test copy, e.g. test/player/player_test.tscn).

var player: Player
var rig: CameraRig
var hud: Hud
var thing: TestThing
var _t := 0.0

class TestThing extends Interactable:
	var uses := 0
	var mesh: MeshInstance3D
	func label_for(_p: Node) -> String:
		return "PRESS" if uses % 2 == 0 else "UNPRESS"
	func act(_p: Node) -> void:
		uses += 1
		print("TEST act: uses=", uses)
		if mesh:
			var m := mesh.material_override as StandardMaterial3D
			m.albedo_color = Color(0.2, 0.9, 0.3) if uses % 2 == 1 else Color(0.9, 0.3, 0.6)

func _ready() -> void:
	var a: Dictionary = GameData.data["ARENA"]
	var W: float = a["w"]
	var H: float = a["h"]
	var wall: float = a["wall"]
	# the floor: the lounge picture inside the walls, on a solid slab
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2((W - wall * 2) * GameData.UNIT, (H - wall * 2) * GameData.UNIT)
	floor_mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = GameData.tex(GameData.manifest["LOUNGE_IMG.src"])
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mi.material_override = mat
	floor_mi.position = GameData.world_to_3d(W / 2.0, H / 2.0)
	add_child(floor_mi)
	_solid(0, 0, W, H, -20, 0, Color(0.25, 0.22, 0.2), false)                  # the slab under the floor
	# walls (150 high, the HTML game's SHROOM_WALL), with a gap at the bottom right like a door
	var wc := Color(0.35, 0.33, 0.38)
	_solid(0, 0, W, wall, 0, 150, wc)
	_solid(0, 0, wall, H, 0, 150, wc)
	_solid(W - wall, 0, W, H, 0, 150, wc)
	_solid(0, H - wall, W - 140, H, 0, 150, wc)
	_solid(W - 80, H - wall, W, H, 0, 150, wc)
	_solid(W - 140, H + 60, W - 80, H + 80, 0, 40, wc)                        # something past the door
	_solid(W - 160, H, W - 140, H + 200, 0, 150, wc)
	_solid(W - 80, H, W - 60, H + 200, 0, 150, wc)
	_solid(W - 160, H + 200, W - 60, H + 220, 0, 150, wc)
	# a few solid boxes: the table, a low crate, a tall cabinet
	_solid(135, 280, 195, 320, 0, 30, Color(0.55, 0.35, 0.2))
	_solid(380, 230, 420, 270, 0, 20, Color(0.4, 0.6, 0.8))
	_solid(560, 160, 600, 200, 0, 100, Color(0.7, 0.3, 0.3))
	# a test Interactable: a pink post you can PRESS
	thing = TestThing.new()
	thing.name = "TestThing"
	thing.reach = 40.0
	thing.position = GameData.world_to_3d(300, 360)
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 8 * GameData.UNIT
	cm.bottom_radius = 8 * GameData.UNIT
	cm.height = 40 * GameData.UNIT
	post.mesh = cm
	post.position.y = 20 * GameData.UNIT
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.9, 0.3, 0.6)
	post.material_override = pmat
	thing.mesh = post
	thing.add_child(post)
	add_child(thing)
	# light
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.09, 0.1, 0.13)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	# the player, the cameras and the HUD
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.place(430, 330)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.bounds = Rect2(0, 0, W, H + 240)
	rig.target = player
	hud = Hud.new()
	hud.name = "Hud"
	hud.player = player
	hud.rig = rig
	add_child(hud)
	player.interacted.connect(func(n): print("TEST interacted: ", n.name))
	rig.mode_changed.connect(func(m): print("TEST mode: ", m))

func _solid(x0: float, y0: float, x1: float, y1: float, z0: float, z1: float, col: Color, show := true) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var size := Vector3(x1 - x0, z1 - z0, y1 - y0) * GameData.UNIT
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	if show:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		mi.material_override = m
		sb.add_child(mi)
	sb.position = GameData.world_to_3d((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)
	add_child(sb)

func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		var hp := player.html_pos()
		print("STATE x=%.1f y=%.1f z=%.1f vel=%.1f roll=%.2f moving=%s facing=(%.2f,%.2f) odo=%.0f mode=%d zoom=%d label=%s uses=%d char=%s view=%s cap=%s look=%.2f/%.2f sprite=%s" % [
			hp.x, hp.y, hp.z, player.vel.length(), player.roll, player.moving, player.facing.x, player.facing.y,
			player.odo, rig.mode, rig.zoom_level, player.focus_label, thing.uses, player.char_id,
			player.sprite.current_view, rig.mouse_captured(), player.look_ang, player.look_y, player.sprite.visible])
