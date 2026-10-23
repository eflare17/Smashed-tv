class_name VoxelAnnouncer
extends Node
## The kill announcer (the owner, 23 Oct: "like from Unreal ... double kill, multi kill, ultra kill"): kills close
## together chain (DOUBLE KILL, MULTI KILL, MEGA KILL, ULTRA KILL, MONSTER KILL, LUDICROUS KILL, then HOLY SHIT), kills
## without going down are a spree (KILLING SPREE at 5, RAMPAGE 10, DOMINATING 15, UNSTOPPABLE 20, GODLIKE 25, WICKED
## SICK 30), a kill through the head is a HEADSHOT, the first kill is FIRST BLOOD. Each pays a bonus on top of the
## kill's own cash. Only this player's own kills count (VoxelBody.by_me: in co-op each of you has your own).
##
## Voices: a recording for a line (double_kill, multi_kill, mega_kill, ultra_kill, monster_kill, ludicrous_kill,
## holy_shit, killing_spree, rampage, dominating, unstoppable, godlike, wicked_sick, headshot, first_blood, spree_over;
## .mp3, .ogg or .wav) dropped in the "voices" folder next to the game (or user://voices, or the project's
## assets/voxel/sound/voice) is played for it; without one, a stinger. Owned by the voxel session.

static var level := 2           # 0 off, 1 callouts only, 2 callouts and sound (VoxelSettings: announcer)

const CHAIN_T := 3.0            # seconds a kill keeps a multi-kill going
## [kills in a row, voice line, callout, bonus $, colour]
const MULTI := [
	[2, "double_kill", "DOUBLE KILL", 2, Color("#f6d17a")],
	[3, "multi_kill", "MULTI KILL", 4, Color("#ffb347")],
	[4, "mega_kill", "MEGA KILL", 7, Color("#ff8c3a")],
	[5, "ultra_kill", "ULTRA KILL", 10, Color("#ff5a3a")],
	[6, "monster_kill", "M O N S T E R   K I L L", 15, Color("#ff2a4a")],
	[7, "ludicrous_kill", "LUDICROUS KILL", 25, Color("#d43aff")],
	[8, "holy_shit", "HOLY SHIT", 40, Color("#ffffff")],
]
## [kills without going down, voice line, callout, bonus $, colour]
const SPREES := [
	[5, "killing_spree", "KILLING SPREE", 10, Color("#7fd89a")],
	[10, "rampage", "RAMPAGE", 20, Color("#5ad6c8")],
	[15, "dominating", "DOMINATING", 35, Color("#5aa8ff")],
	[20, "unstoppable", "UNSTOPPABLE", 50, Color("#8a6aff")],
	[25, "godlike", "GODLIKE", 80, Color("#ffd700")],
	[30, "wicked_sick", "WICKED SICK", 120, Color("#ff3aa0")],
]
const HEADSHOT_CASH := 1

var arena: Node3D
var chain := 0                  # kills in the current multi-kill
var spree := 0                  # kills since last going down
var best_chain := 0
var best_spree := 0
var first := true
var _chain_t := 0.0
var _big: Label
var _small: Label
var _cash: Label
var _show_t := 0.0
var _flash := Color.WHITE
var _rainbow := false
var _voices := {}               # line -> AudioStream or null (looked for once)
var _voice: AudioStreamPlayer
var last := []                  # (tests) the lines of the last kill's callout

func setup(arena_: Node3D, layer: CanvasLayer) -> void:
	arena = arena_
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_big = _label(root, 64, 185)
	_small = _label(root, 30, 262)
	_cash = _label(root, 24, 296)
	_cash.add_theme_color_override("font_color", Color("#7fd89a"))
	_voice = AudioStreamPlayer.new()
	add_child(_voice)

func _label(root: Control, sz: int, y: float) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.position = Vector2(-600, y)
	l.size = Vector2(1200, sz * 1.4)
	l.pivot_offset = Vector2(600, sz * 0.7)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", maxi(6, sz / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	root.add_child(l)
	return l

## A body died: counted if it was this player's kill.
func on_kill(b: VoxelBody) -> void:
	if level <= 0 or b == null or not b.by_me():
		return
	chain = chain + 1 if _chain_t > 0.0 else 1
	_chain_t = CHAIN_T
	spree += 1
	best_chain = maxi(best_chain, chain)
	best_spree = maxi(best_spree, spree)
	var lines := []                 # [voice line, callout, bonus, colour], most important first
	if chain >= 2:
		var m: Array = MULTI[mini(chain, 8) - 2]
		lines.append(m.slice(1))
	for s in SPREES:
		if spree == int(s[0]):
			lines.append(s.slice(1))
	if first:
		first = false
		lines.append(["first_blood", "FIRST BLOOD", 0, Color("#ff4a3a")])
	if b.head_gone:
		lines.append(["headshot", "HEADSHOT", HEADSHOT_CASH, Color("#ffe27a")])
	if lines.is_empty():
		return
	var bonus := 0
	for l in lines:
		bonus += int(l[2])
	if bonus > 0:
		arena.cash += bonus
		if arena.stash:
			arena.stash._dirty = true
	last = lines.map(func(l): return String(l[1]))
	_show(lines, bonus)

func _show(lines: Array, bonus: int) -> void:
	var top: Array = lines[0]
	_big.text = String(top[1])
	_flash = top[3]
	_rainbow = String(top[0]) == "holy_shit"
	_big.add_theme_color_override("font_color", _flash)
	var rest := []
	for i in range(1, lines.size()):
		rest.append(String(lines[i][1]))
	_small.text = "   +   ".join(rest)
	_small.add_theme_color_override("font_color", lines[1][3] if lines.size() > 1 else Color.WHITE)
	_cash.text = "+$%d bonus" % bonus if bonus > 0 else ""
	for l in [_big, _small, _cash]:
		l.visible = l.text != ""
		l.modulate.a = 1.0
	_show_t = 2.2
	# the sound: the line's recording if there is one (the biggest), or a stinger
	if level >= 2:
		var v = _voice_for(String(top[0]))
		if v != null:
			_voice.stream = v
			_voice.volume_db = arena.sound.volume_db + 2.0 if arena.sound else 0.0
			_voice.play()
		elif arena.sound:
			var tier := 0
			for i in MULTI.size():
				if String(MULTI[i][1]) == String(top[0]):
					tier = i + 1
			var spree_line := false
			for s in SPREES:
				if String(s[1]) == String(top[0]):
					spree_line = true
			if tier > 0:
				arena.sound.play("announce_%d" % mini(tier, 7), Vector3.INF, -2.0)
			elif spree_line:
				arena.sound.play("announce_spree", Vector3.INF, -2.0)
			elif String(top[0]) == "headshot":
				arena.sound.play("announce_head", Vector3.INF, -3.0)
			else:
				arena.sound.play("announce_1", Vector3.INF, -3.0, 0.8)

## The recording for a line, looked for once: the "voices" folder next to the game, user://voices, the project's
## assets/voxel/sound/voice (null: none).
func _voice_for(line: String):
	if _voices.has(line):
		return _voices[line]
	var found = null
	var dirs := [OS.get_executable_path().get_base_dir().path_join("voices"), "user://voices", "res://assets/voxel/sound/voice"]
	for d in dirs:
		for ext in ["mp3", "ogg", "wav"]:
			var p: String = String(d).path_join(line + "." + ext)
			if p.begins_with("res://"):
				if ResourceLoader.exists(p):
					found = load(p)
			elif FileAccess.file_exists(p):
				match ext:
					"mp3":
						found = AudioStreamMP3.load_from_file(p)
					"ogg":
						found = AudioStreamOggVorbis.load_from_file(p)
					"wav":
						found = AudioStreamWAV.load_from_file(p)
			if found != null:
				break
		if found != null:
			break
	_voices[line] = found
	return found

func _process(dt: float) -> void:
	if not arena:
		return
	_chain_t = maxf(0.0, _chain_t - dt)
	# down: the spree's over
	if arena.down_t > 0.0 and spree > 0:
		if spree >= int(SPREES[0][0]) and level > 0:
			_big.visible = false
			_small.text = "SPREE OVER (%d)" % spree
			_small.add_theme_color_override("font_color", Color("#ff6a5a"))
			_small.visible = true
			_small.modulate.a = 1.0
			_cash.text = ""
			_show_t = 1.8
			if level >= 2:
				var v = _voice_for("spree_over")
				if v != null:
					_voice.stream = v
					_voice.play()
		spree = 0
		chain = 0
	if _show_t > 0.0:
		_show_t -= dt
		# a punch in, a hold, a fade
		var age := 2.2 - _show_t
		var s := 1.0 + maxf(0.0, 0.18 - age) * 4.0
		_big.scale = Vector2(s, s)
		if _rainbow:
			_big.add_theme_color_override("font_color", Color.from_hsv(fmod(age * 2.5, 1.0), 0.8, 1.0))
		var a := clampf(_show_t / 0.5, 0.0, 1.0)
		for l in [_big, _small, _cash]:
			l.modulate.a = a
		if _show_t <= 0.0:
			for l in [_big, _small, _cash]:
				l.visible = false
