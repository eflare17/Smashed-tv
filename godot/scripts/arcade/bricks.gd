class_name BricksGame
extends ArcadeGame
## BRICK BRAWL (Smashed.html, ARCADE_GAMES.bricks): keep the ball up, smash the wall. Eight columns of five rows,
## the top rows two hits from level 2 on (ceil(level / 2) of them), 1 point a crack and 5 a brick, three lives,
## a new wall a level up when it's cleared (the ball 25 faster each level). Where the ball hits the paddle
## steers it.
## Controls: left / right (keys, d-pad, stick) move the paddle at 380 a second, as in the HTML game; the mouse
## over the screen, or a finger dragging, puts the paddle where it points (decided for the Godot version: the
## owner asked for "drag the paddle"). Space, up, A, a click or a tap launches.

var lives := 3
var level := 1
var px := 240.0
var bx := 240.0
var by := 288.0
var vx := 0.0
var vy := 0.0
var stuck := true
## Each brick: {x, y, hp, row}.
var bricks: Array = []

const COLS := ["#ff5d8f", "#ff8ad8", "#c98bff", "#8fb4ff", "#8ff0ff"]

func _init() -> void:
	wall()
	serve()

func title() -> String:
	return "BRICK BRAWL"

func hint(device: String) -> String:
	match device:
		"pad": return "stick or d-pad to move  ·  A to launch"
		"touch": return "drag the paddle  ·  tap to launch"
	return "mouse or left / right to move  ·  click, space or up to launch"

func wall() -> void:
	bricks.clear()
	for j in 5:
		for i in 8:
			bricks.append({"x": 12.0 + i * 57, "y": 36.0 + j * 18, "hp": 2 if j < ceili(level / 2.0) else 1, "row": j})

func serve() -> void:
	stuck = true
	bx = px
	by = 288.0
	vx = 0.0
	vy = 0.0

func step(dt: float, st: Dictionary) -> void:
	var target = st.get("paddle", null)
	if target != null:
		px = clampf(float(target), 36.0, 444.0)
	else:
		px = clampf(px + float(st.get("x", 0.0)) * 380.0 * dt, 36.0, 444.0)
	if stuck:                                          # on the paddle: fire (or push up) to launch
		bx = px
		if live and (st.get("fire", false) or float(st.get("y", 0.0)) < -0.5):
			stuck = false
			var sp := 250.0 + level * 25.0
			vx = sp * 0.45
			vy = -sp
		return
	bx += vx * dt
	by += vy * dt
	if bx < 5.0:
		bx = 5.0; vx = absf(vx)
	if bx > 475.0:
		bx = 475.0; vx = -absf(vx)
	if by < 5.0:
		by = 5.0; vy = absf(vy)
	if vy > 0.0 and by > 290.0 and by < 304.0 and absf(bx - px) < 40.0:   # the paddle: where it hits steers it
		var sp := Vector2(vx, vy).length()
		var a := (bx - px) / 40.0 * 1.05
		vx = sin(a) * sp
		vy = -cos(a) * sp
		by = 290.0
		tone(0.04, 330, 330, 0.08)
	for b in bricks:
		if b.hp <= 0 or bx < b.x - 5 or bx > b.x + 59 or by < b.y - 5 or by > b.y + 19:
			continue
		var ox := minf(bx - (b.x - 5), b.x + 59 - bx)
		var oy := minf(by - (b.y - 5), b.y + 19 - by)
		if ox < oy:
			vx = -vx
		else:
			vy = -vy
		b.hp -= 1
		score += 1 if b.hp > 0 else 5
		tone(0.05, 600 if b.hp > 0 else 900, 700, 0.08)
		break
	if not bricks.any(func(b): return b.hp > 0):
		level += 1
		wall()
		serve()
	if by > 330.0:
		lives -= 1
		tone(0.35, 260, 70, 0.12)
		if lives <= 0:
			over = true
			wait = 0.8
		else:
			serve()

func draw(ci: CanvasItem, s: Rect2) -> void:
	var o := s.position
	ci.draw_rect(s, Color("#16091a"))
	for b in bricks:
		if b.hp <= 0:
			continue
		ci.draw_rect(Rect2(o.x + b.x, o.y + b.y, 54, 14), Color(COLS[b.row]))
		ci.draw_rect(Rect2(o.x + b.x, o.y + b.y, 54, 3), Color(1, 1, 1, 0.35))
		if b.hp > 1:
			ci.draw_rect(Rect2(o.x + b.x + 4, o.y + b.y + 6, 46, 3), Color(0, 0, 0, 0.35))
	ci.draw_rect(Rect2(o.x + px - 36, o.y + 294, 72, 8), Color("#f6d17a"))
	ci.draw_rect(Rect2(o.x + bx - 4, o.y + by - 4, 8, 8), Color.WHITE)
	var txt := "♥".repeat(maxi(0, lives)) + "  LV " + str(level)
	var f := font()
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	ci.draw_string(f, Vector2(o.x + s.size.x - 8 - w, o.y + s.size.y - 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ff8ad8"))

static func mini(ci: CanvasItem, r: Rect2, t: float) -> void:
	ci.draw_rect(r, Color("#16091a"))
	var cols := ["#ff5d8f", "#c98bff", "#8ff0ff"]
	for j in 3:
		for i in 5:
			ci.draw_rect(Rect2(r.position.x + 2 + i * (r.size.x - 4) / 5.0, r.position.y + 3 + j * 4, (r.size.x - 4) / 5.0 - 1, 3), Color(cols[j]))
	var f := fmod(t * 0.7, 1.0)
	var bxx := r.position.x + 3 + absf(f * 2 - 1) * (r.size.x - 6)
	var byy := r.end.y - 6 - absf(sin(t * 3)) * (r.size.y - 20)
	ci.draw_rect(Rect2(bxx, byy, 2, 2), Color.WHITE)
	ci.draw_rect(Rect2(r.position.x + r.size.x / 2 - 5 + sin(t * 2) * 6, r.end.y - 3, 10, 2), Color("#f6d17a"))
