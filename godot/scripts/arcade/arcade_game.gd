class_name ArcadeGame
extends RefCounted
## One arcade game, the way the HTML game's ARCADE_GAMES entries are made (Smashed.html, "the arcade row"):
## a fresh state each go, step() it with the stick, draw() it into the cabinet's 480 x 320 screen, mini() for
## the little screen on the cabinet. The overlay (ArcadeOverlay) runs the go: PUSH TO START sets live, the game
## sets over (and wait, the pause before PUSH TO PLAY AGAIN), and the score is kept as the high score.
##
## The stick (st) is a Dictionary the overlay fills each frame:
##   x, y      -1..1, the keys / d-pad / left stick / a finger's drag (arcadeStick)
##   fire      space, enter, a tap, or the pad's A
##   go        fire, or the stick pushed past half (starts a go)
##   ptr       where the pointer is on the screen (480 x 320 units), or null when there's none
##   ptr_in    the pointer's over the screen
##   ptr_down  its main button (or a finger) is down
##   ptr_alt   its second button is down (the right mouse button)
##   touch     the pointer is a finger
##   pressed   Dictionary of game keys pressed this frame ("q", "u", ...), for one-shot actions
##   held      Dictionary of game keys held ("f", "jump", "dig", "launch", ...)
##   aim       Vector2, the pad's right stick (Sand Miner aims the shovel with it)

const SW := 480.0
const SH := 320.0

var live := false
var over := false
var wait := 0.0
var score := 0
var won := false
## The bleeps (set by the overlay; null in tests).
var sfx: ArcadeSfx

## The name on the marquee.
func title() -> String:
	return ""

## The line under the screen, for the device in use: "keys", "pad" or "touch".
func hint(_device: String) -> String:
	return ""

func step(_dt: float, _st: Dictionary) -> void:
	pass

## Draw the game into s (a 480 x 320 rect) on ci.
func draw(_ci: CanvasItem, _s: Rect2) -> void:
	pass

## (Each game also has a static mini(ci, r, t): the little screen on the cabinet, playing to itself.)

## On-screen buttons this game wants on a touch screen: [[id, label, side ("left"/"right"), row, col], ...].
## Held ones arrive in st.held[id], and a press in st.pressed[id].
func touch_buttons() -> Array:
	return []

func tone(dur: float, f0: float, f1: float, gain: float, wave: String = "square") -> void:
	if sfx:
		sfx.tone(dur, f0, f1, gain, wave)

func noise(dur: float, freq: float, q: float, gain: float, type: String = "lowpass") -> void:
	if sfx:
		sfx.noise(dur, freq, q, gain, type)

static func font() -> Font:
	return ThemeDB.fallback_font

## The HTML game's arcSpud: a little potato.
static func spud(ci: CanvasItem, p: Vector2, r: float) -> void:
	ci.draw_set_transform(p, 0.4, Vector2(1.15, 0.85))
	ci.draw_circle(Vector2.ZERO, r, Color("#8a5a2b"))
	ci.draw_set_transform(p + Vector2(-r * 0.15, -r * 0.15), 0.4, Vector2(0.85, 0.55))
	ci.draw_circle(Vector2.ZERO, r, Color("#c69a5b"))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_rect(Rect2(p.x - r * 0.4, p.y - r * 0.1, 2, 2), Color("#6b4220"))
	ci.draw_rect(Rect2(p.x + r * 0.3, p.y + r * 0.2, 2, 2), Color("#6b4220"))
