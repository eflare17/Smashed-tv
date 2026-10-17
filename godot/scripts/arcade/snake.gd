class_name SnakeGame
extends ArcadeGame
## SPUD SNAKE (Smashed.html, ARCADE_GAMES.snake): eat the potatoes, don't eat yourself. A 24 x 16 board, a step
## every 0.13 s, 3% quicker per potato (down to 0.06 s). The tail's square is free to move into (it moves on the
## same step) unless you're eating. Fill the board and you've won. Score: potatoes eaten.
## Steering: keys (WASD / arrows), the d-pad or left stick, or a swipe (drag from where the finger lands).

var cols := 24
var rows := 16
var t := 0.0
var speed := 0.13
var body: Array[Vector2i] = [Vector2i(8, 8), Vector2i(7, 8), Vector2i(6, 8)]
var dir := Vector2i(1, 0)
var next := Vector2i(1, 0)
var food := Vector2i(-1, -1)
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()
	place_food()

func title() -> String:
	return "SPUD SNAKE"

func hint(device: String) -> String:
	match device:
		"pad": return "d-pad or stick to steer"
		"touch": return "swipe to steer"
	return "WASD / arrows / drag to steer"

## A free square for the potato, or the board's full and you've won.
func place_food() -> void:
	var free: Array[Vector2i] = []
	for x in cols:
		for y in rows:
			var c := Vector2i(x, y)
			if not body.has(c):
				free.append(c)
	if free.is_empty():
		food = Vector2i(-1, -1)
		over = true
		wait = 0.8
		won = true
		tone(0.3, 600, 1200, 0.12)
		return
	food = free[rng.randi() % free.size()]

func step(dt: float, st: Dictionary) -> void:
	var sx: float = st.get("x", 0.0)
	var sy: float = st.get("y", 0.0)
	if absf(sx) > 0.5 or absf(sy) > 0.5:
		var d := Vector2i(int(signf(sx)), 0) if absf(sx) > absf(sy) else Vector2i(0, int(signf(sy)))
		if d != -dir:
			next = d                                   # no turning back on yourself
	if not live:
		return
	t += dt
	while t >= speed and not over:
		t -= speed
		dir = next
		var h := body[0] + dir
		var eat := h == food
		var hit := h.x < 0 or h.y < 0 or h.x >= cols or h.y >= rows
		if not hit:
			for i in body.size():
				if (eat or i < body.size() - 1) and body[i] == h:
					hit = true
					break
		if hit:
			over = true
			wait = 0.8
			tone(0.4, 300, 60, 0.12)
			return
		body.push_front(h)
		if eat:
			score += 1
			speed = maxf(0.06, speed * 0.97)
			place_food()
			tone(0.07, 520, 900, 0.1)
		else:
			body.pop_back()

func draw(ci: CanvasItem, s: Rect2) -> void:
	var c := s.size.x / cols
	ci.draw_rect(s, Color("#0b1f12"))
	var alt := Color("#0f2a18")
	for i in cols:
		for j in rows:
			if (i + j) % 2:
				ci.draw_rect(Rect2(s.position.x + i * c, s.position.y + j * c, c, c), alt)
	if food.x >= 0:
		spud(ci, s.position + Vector2((food.x + 0.5) * c, (food.y + 0.5) * c), c * 0.42)
	for i in body.size():
		var b := body[i]
		var col := Color("#b8ffc6") if i == 0 else (Color("#4fd26e") if i % 2 else Color("#43bd61"))
		ci.draw_rect(Rect2(s.position.x + b.x * c + 1, s.position.y + b.y * c + 1, c - 2, c - 2), col)
	var h := body[0]                                   # two eyes, looking where it's going
	for side: int in [-1, 1]:
		var ex := s.position.x + (h.x + 0.5 + dir.x * 0.2 + side * dir.y * 0.22) * c - 2
		var ey := s.position.y + (h.y + 0.5 + dir.y * 0.2 + side * dir.x * 0.22) * c - 2
		ci.draw_rect(Rect2(ex, ey, 4, 4), Color("#0b1f12"))

static func mini(ci: CanvasItem, r: Rect2, tt: float) -> void:
	ci.draw_rect(r, Color("#0b1f12"))
	var k := int(floor(tt * 6))
	for i in 6:
		var q := (k - i + 280) % 28
		var x := q if q < 14 else 27 - q
		ci.draw_rect(Rect2(r.position.x + 3 + x * (r.size.x - 8) / 14.0, r.position.y + r.size.y / 2 - 1, 3, 3),
			Color("#b8ffc6") if i == 0 else Color("#4fd26e"))
	ci.draw_rect(Rect2(r.end.x - 8, r.position.y + 5, 3, 3), Color("#c69a5b"))
