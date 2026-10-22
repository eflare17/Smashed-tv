class_name VoxelWaves
extends Node
## Escalating waves and the boss (Stage 12 of the overnight plan, 22 Oct: "escalating waves plus a big voxel boss
## every few waves, carvable piece by piece"). Each wave is bigger than the last (plan(): 2, 4, 6, 8 ... up to 34),
## the kinds come in as it goes (batters from wave 2, brutes and chargers from 3, throwers from 4, shield brutes from
## 6), walking in a few at a time (TRICKLE s apart, never more than LIVE_CAP up at once) and a little quicker each
## wave; a rest of REST s once a wave's all down, its number up in the middle of the screen. Every BOSS_EVERY-th wave
## THE BUTCHER comes first (VoxelKinds' "boss": a brute twice the size, crimson, much tougher each time he comes back;
## his health in a bar at the top), with a third of a wave behind him.
## Run by the host (or alone); the guest gets the banner and the boss's health bar (event "wv").
## F12 switches to the old way (one enemy at a time, the owner's of 20 Oct) and back. Tests' games keep the old way
## unless --waves. Owned by the voxel session.

const BOSS_EVERY := 5
const LIVE_CAP := 24
const TRICKLE := 0.45
const REST := 3.0
const BOSS_NAME := "THE BUTCHER"

var arena: Node3D
var on := true
var queue: Array = []           # the kinds still to walk in this wave
var wave_size := 0
var cleared := 0                # enemies cleared toward the crops' next jump (VoxelFarm.WAVE_ENEMIES)
var boss_max := 0.0             # the boss's health at full (the bar), 0: no boss this wave
var bosses := 0                 # bosses sent in so far
var _trickle := 0.0
var _rest := 0.0
var _layer: CanvasLayer
var _banner: Label
var _banner_t := 0.0
var _bar_back: ColorRect
var _bar_fill: ColorRect
var _bar_name: Label

func setup(a: Node3D) -> void:
	arena = a
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-400, 150)
	_banner.size = Vector2(800, 120)
	_banner.add_theme_font_size_override("font_size", 46)
	_banner.add_theme_color_override("font_color", Color("#f6d17a"))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.visible = false
	_layer.add_child(_banner)
	_bar_name = Label.new()
	_bar_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_bar_name.position = Vector2(-300, 44)
	_bar_name.size = Vector2(600, 30)
	_bar_name.add_theme_font_size_override("font_size", 20)
	_bar_name.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_bar_name.add_theme_constant_override("outline_size", 6)
	_bar_name.text = BOSS_NAME
	_layer.add_child(_bar_name)
	_bar_back = ColorRect.new()
	_bar_back.color = Color(0, 0, 0, 0.6)
	_bar_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_bar_back.position = Vector2(-300, 74)
	_bar_back.size = Vector2(600, 16)
	_layer.add_child(_bar_back)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.85, 0.12, 0.1)
	_bar_fill.position = Vector2(2, 2)
	_bar_fill.size = Vector2(596, 12)
	_bar_back.add_child(_bar_fill)
	_show_bar(false)

## The kinds in wave w, in the order they walk in (the boss first).
static func plan(w: int) -> Array:
	var pool := ["grunt", "grunt", "grunt", "swarmer", "swarmer"]
	if w >= 2:
		pool += ["batter", "batter"]
	if w >= 3:
		pool += ["brute", "charger", "charger"]
	if w >= 4:
		pool += ["thrower", "thrower"]
	if w >= 6:
		pool += ["shielder"]
	var n := mini(1 + int(w * 1.8), 34)
	var out := []
	if w % BOSS_EVERY == 0:
		out.append("boss")
		n = maxi(2, n / 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = w * 7919 + 13
	for i in n:
		out.append(pool[rng.randi() % pool.size()])
	return out

## How tough the boss is the k-th time he comes (1 the first).
static func boss_tough(k: int) -> float:
	return 3.0 + float(k - 1)

## A new wave: its kinds queued, its number shown (and told to the guest).
func begin_wave() -> void:
	cleared += wave_size
	while cleared >= VoxelFarm.WAVE_ENEMIES:
		cleared -= VoxelFarm.WAVE_ENEMIES
		if arena.yard:
			arena.yard.farm.on_wave()          # (a wave's worth cleared: the crops jump ahead)
	arena.wave += 1
	queue = plan(int(arena.wave))
	wave_size = queue.size()
	_trickle = 0.0
	boss_max = 0.0
	if queue.has("boss"):
		bosses += 1
		boss_max = VoxelKinds.BOSS_HP * boss_tough(bosses)
	banner(int(arena.wave), boss_max)
	if arena.net and arena.net.linked and arena.net.role == "host":
		arena.net.send_wave(int(arena.wave), boss_max)

## The wave's number in the middle of the screen a moment (and the boss's bar ready when there's one).
func banner(w: int, bmax: float) -> void:
	boss_max = bmax
	_banner.text = ("WAVE %d\n%s" % [w, BOSS_NAME]) if bmax > 0.0 else "WAVE %d" % w
	_banner.add_theme_color_override("font_color", Color("#ff6a5a") if bmax > 0.0 else Color("#f6d17a"))
	_banner.visible = true
	_banner_t = 2.5
	if arena.sound:
		arena.sound.play("grenades_beep" if bmax <= 0.0 else "slam", Vector3.INF, -6.0 if bmax <= 0.0 else 0.0, 0.8)

## Any words in the middle of the screen a moment (the boss down).
func banner_text(text: String, col: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.visible = true
	_banner_t = 2.5

## Each frame (both games: the banner and the bar; the host's or alone: the waves).
func step(dt: float, run: bool) -> void:
	if _banner_t > 0.0:
		_banner_t -= dt
		_banner.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0)
		if _banner_t <= 0.0:
			_banner.visible = false
	var boss: VoxelBody = null
	for b in arena.bodies:
		if b.key == "boss" and b.alive and not b.fragment:
			boss = b
	_show_bar(boss != null)
	if boss:
		var mx := maxf(float(boss.get_meta("hp_max", boss_max)), maxf(1.0, boss.hp))
		_bar_fill.size.x = 596.0 * clampf(boss.hp / mx, 0.0, 1.0)
	if not run or not on:
		return
	var alive := 0
	for b in arena.bodies:
		if b.alive:
			alive += 1
	if not queue.is_empty():
		_trickle -= dt
		if _trickle <= 0.0 and alive < LIVE_CAP:
			_trickle = TRICKLE
			var key: String = queue.pop_front()
			var nb: VoxelBody = arena.spawn_kind(key)
			if key == "boss":
				arena.kinds.make_boss(nb, boss_tough(bosses))
		return
	if alive == 0:
		_rest += dt
		if _rest >= REST:
			_rest = 0.0
			begin_wave()
	else:
		_rest = 0.0

## F12: the waves off (one at a time, the old way: its own count of enemies, the wave's left to walk in dropped) or on
## again (from the wave they were at).
var _wave_at := 0
func toggle() -> void:
	on = not on
	if not on:
		_wave_at = int(arena.wave)
		queue.clear()
	else:
		arena.wave = maxi(_wave_at, 0)
		_rest = 0.0

func _show_bar(v: bool) -> void:
	_bar_back.visible = v
	_bar_name.visible = v
