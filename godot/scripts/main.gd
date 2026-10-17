extends Node3D
## The game (milestone 1): the lobby, the bedroom and the yard (World, a WorldBuilder), the player standing where
## the HTML game starts you (calls.playerStart), the camera rig following him (top-down, V for first person),
## the HUD, the backyard trampoline (TRAMP.cx/cy) and Gothica wandering the lounge (calls.npcGoth), and a sun.
## Owned by the Putting it together task.
##
## The nodes are in scenes/main.tscn; this places them from game_data.json, builds the World and wires them up.
## The World draws everything unshaded (the HTML game's shading is baked in), so the sun is only for what's lit
## (and for the day and night pass, 1.4).
##
## Debugging: run with the user argument --state (or open the web build with ?state in its address) and it
## prints a "STATE ..." line ten times a second: where the player is, his height, the view, what E says, where
## Gothica is. The browser tests read these.

@onready var world: WorldBuilder = $World
@onready var sun: DirectionalLight3D = $Sun
@onready var trampoline: Trampoline = $Trampoline
@onready var gothica: Gothica = $Gothica
@onready var player: Player = $Player
@onready var rig: CameraRig = $CameraRig
@onready var hud: Hud = $Hud

## Print STATE lines (see above).
var print_state: bool = false
var _state_t: float = 0.0

func _ready() -> void:
	var d: Dictionary = GameData.data
	var calls: Dictionary = d.get("calls", {})
	var t: Dictionary = d.get("T", {})
	# the World: its own trampoline left off (the Trampoline node is the one you bounce on)
	world.add_to_group("world_builder")
	world.player_radius = float(t.get("radius", 14.0))
	world.include_trampoline = false
	world.build()
	# the haze is for first person: from high over the yard it would wash the top-down view out
	if world.environment:
		world.environment.fog_enabled = false
	# the player where the lobby starts you
	var ps: Dictionary = calls.get("playerStart", {"x": 380, "y": 260})
	player.place(float(ps.x), float(ps.y))
	player.facing = Vector2(0, 1)
	# the camera: follows him, kept inside the whole lobby (camView keeps the view inside worldW x worldH)
	rig.bounds = Rect2(0, 0, float(calls.get("worldW", 2003)), float(calls.get("worldH", 1998)))
	rig.target = player
	rig.mode_changed.connect(_on_mode)
	hud.player = player
	hud.rig = rig
	# Gothica where the lobby has her
	var g: Dictionary = calls.get("npcGoth", {"x": 200, "y": 360})
	gothica.start = Vector2(float(g.x), float(g.y))
	gothica.place(float(g.x), float(g.y))
	gothica.refresh_obstacles()
	_on_mode(rig.mode)
	print_state = "--state" in OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.find("state") >= 0:
			print_state = true
	print("Smashed TV (Godot) ", hud.build_text, ": ready")

func _on_mode(m: int) -> void:
	# first person has the HTML game's distance haze; top-down doesn't (the HTML view has none)
	if world.environment:
		world.environment.fog_enabled = m == CameraRig.Mode.FIRST_PERSON

func _process(delta: float) -> void:
	if not print_state:
		return
	_state_t += delta
	if _state_t < 0.1:
		return
	_state_t = 0.0
	var hp := player.html_pos()
	var gp := gothica.html_pos2()
	print("STATE x=%.1f y=%.1f dz=%.1f tramp=%s frozen=%s mode=%d zoom=%d label=%s char=%s look=%.2f/%.2f goth=%.1f,%.1f gm=%s cut=%s fps=%d" % [
		hp.x, hp.y, player.dz, player.on_tramp, player.frozen, rig.mode, rig.zoom_level, player.focus_label,
		player.char_id, player.look_ang, player.look_y, gp.x, gp.y, gothica.moving, world.is_cut_away(),
		Engine.get_frames_per_second()])
