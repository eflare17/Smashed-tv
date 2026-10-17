class_name LobbyGym
extends LobbyThing
## The lounge gym: bench press with its bar and plates, the plate tree, the leg press (specs/gym.md, Smashed.html
## gymNear 934, gymAction 962, stepGym 994, drawBenchStation 878, drawLoadedBar 830, drawRackStation 896,
## drawLegStation 1109). Owned by the Lobby life session.
##
## E near a spot does what the HTML game's gymNear says (the zones are tested in its order: leg press, plate tree,
## bar ends, bench front): TAKE / RACK IT a plate off / on the tree, LOAD / UNLOAD the bar (3 plates a side, an
## animation of 0.9 s) or the leg press horns (3 a side, at once), BENCH (LOAD IT EVEN if the two sides differ) and
## LEG PRESS. On a machine he is pinned to it and pumps by itself, a rep at the end of every cycle (the cycle is
## 1.3 + 0.012 s a kg on the bench, 1.2 + 0.008 on the leg press, fixed when he lies down); E (GET UP), the move keys
## or stick (past 0.3) or the roll get him off. Plates in hand are drawn at his side (not in first person).
##
## Everything is drawn with the HTML game's art as little pictures standing on each machine's line (LobbyPic), in the
## machine's own picture coordinates, so top-down it is the HTML picture and in first person they stand up. The
## World's static bench, plate tree and leg press are hidden and replaced by these.
##
## For the others (Gothica watching, the pool): signal rep(player, machine, reps); lifting(p), reps(p),
## machine_of(p), watch_spot(machine) and watch_at(machine), holding_plate(p), rack_plate(size), drop_plate(p).

signal rep(player: Node, machine: String, reps: int)
signal got_up(player: Node, machine: String, reps: int)

const PLATE_KG := {"S": 5, "M": 10, "L": 20}
const BAR_KG := 20
const LEG_KG := 50
const BENCH_X := 420.0
const BENCH_Y := 130.0
const RACK_X := 528.0
const RACK_Y := 112.0
const LEG_X := 470.0
const LEG_Y := 236.0
const BAR_REST := Vector2(420.85, 71.05)
const FISTS: Array = [[41.8, 19.1, 94.7, 16.1], [37.8, 41.8, 95.7, 38.8], [41.5, 65.3, 96.1, 60.6], [38.5, 41.5, 94.1, 37.2]]
const PEGS: Array = [[22.8, 27.6, -1], [22.8, 63.6, -1], [22.8, 100.8, -1], [64.8, 21.6, 1], [64.8, 60.0, 1], [64.8, 96.0, 1]]
const PEG_ROWS: Array = [[16, 37], [53, 74], [90, 115], [12, 31], [50, 70], [86, 108]]
const LEG_HORNS: Array = [
	{"L": [74.5, 41.0], "R": [178.0, 58.5]}, {"L": [96.0, 29.6], "R": [190.0, 46.5]},
	{"L": [74.5, 42.0], "R": [178.0, 60.0]}, {"L": [74.5, 41.0], "R": [178.5, 58.5]},
	{"L": [74.5, 42.0], "R": [178.0, 60.0]}, {"L": [74.5, 42.0], "R": [178.0, 60.0]}]
const LEG_DIR := {"L": Vector2(-1, -0.03), "R": Vector2(1, 0.06)}
const LEG_STEP := 5.0
const ANIM_DUR := 0.9
const BENCH_O := Vector2(389, 59)       # benchOrigin: the bench picture's top left
const RACK_O := Vector2(507, 33)
const LEG_O := Vector2(420, 154)

## GYM.bar / pegs / anim and LEG.horn (the HTML game's state).
var bar: Dictionary = {"L": [], "R": []}
var pegs: Array = [["S"], ["M"], ["L"], ["S"], ["M"], ["L"]]
var horn: Dictionary = {"L": [], "R": []}
var anim: Dictionary = {}
## Who lifts: player -> {t, reps, rep} (the bench), and on the leg press.
var lifts: Dictionary = {}
var legs: Dictionary = {}
## Who holds a plate: player -> "S" | "M" | "L".
var plates: Dictionary = {}
var clock: float = 0.0

var _world: Node
var _hid: bool = false
var _bench: _Station
var _rack: _Station
var _leg: _Station
var _held: Dictionary = {}          # player -> LobbyPic
var _tex: Dictionary = {}
var _atlas: Dictionary = {}
var _anim_marks: Dictionary = {}

func _ready() -> void:
	ll = get_parent() as LobbyLife
	global_position = GameData.world_to_3d(470.0, 150.0, 0.0)
	reach = 200.0
	_bench = _Station.new(self, BENCH_Y)
	_rack = _Station.new(self, RACK_Y)
	_leg = _Station.new(self, LEG_Y)

# ------------------------------------------------------------------ the numbers

static func side_kg(plate_list: Array) -> int:
	var k := 0
	for s in plate_list:
		k += int(PLATE_KG[s])
	return k

## gymKg: the bar and both sides.
func bench_kg() -> int:
	return BAR_KG + side_kg(bar.L) + side_kg(bar.R)

func leg_kg() -> int:
	return LEG_KG + side_kg(horn.L) + side_kg(horn.R)

func lifting(p: Node) -> bool:
	return lifts.has(p) or legs.has(p)

func machine_of(p: Node) -> String:
	return "bench" if lifts.has(p) else ("leg" if legs.has(p) else "")

## Reps so far on the machine he is on (0 when he is on none).
func reps(p: Node) -> int:
	if lifts.has(p):
		return lifts[p].reps
	if legs.has(p):
		return legs[p].reps
	return 0

func holding_plate(p: Node) -> String:
	return plates.get(p, "")

## Where Gothica stands to watch a machine, and what she looks at (HTML units).
static func watch_spot(machine: String) -> Vector2:
	return Vector2(LEG_X - 80.0, LEG_Y + 26.0) if machine == "leg" else Vector2(BENCH_X + 58.0, BENCH_Y + 24.0)

static func watch_at(machine: String) -> Vector2:
	return Vector2(LEG_X - 16.0, LEG_Y - 30.0) if machine == "leg" else Vector2(BENCH_X, BENCH_Y - 10.0)

# ------------------------------------------------------------------ plates on the tree

## rackPlate (818): back on the tree (a home peg first, the emptier; max 2 a peg).
func rack_plate(size: String) -> void:
	var want: Array = {"S": [0, 3], "M": [1, 4], "L": [2, 5]}[size]
	want.sort_custom(func(a, b): return pegs[a].size() < pegs[b].size())
	var peg := -1
	for i in want:
		if pegs[i].size() < 2:
			peg = i
			break
	if peg < 0:
		for i in pegs.size():
			if pegs[i].size() < 2:
				peg = i
				break
	if peg >= 0:
		pegs[peg].append(size)

## Put the plate he holds back (dived, died, run started).
func drop_plate(p: Node) -> void:
	if plates.has(p):
		rack_plate(plates[p])
		plates.erase(p)

func _tree_has() -> bool:
	for q in pegs:
		if not q.is_empty():
			return true
	return false

func _tree_room() -> bool:
	for q in pegs:
		if q.size() < 2:
			return true
	return false

func _take_plate() -> String:
	var size := ""
	for s in ["L", "M", "S"]:
		for q in pegs:
			if q.has(s):
				size = s
				break
		if size != "":
			break
	if size == "":
		return ""
	var best := -1
	for i in pegs.size():
		var q: Array = pegs[i]
		if not q.is_empty() and q[-1] == size and (best < 0 or q.size() > pegs[best].size()):
			best = i
	if best >= 0:
		pegs[best].pop_back()
		return size
	for i in pegs.size():
		var idx: int = pegs[i].rfind(size)
		if idx >= 0:
			pegs[i].remove_at(idx)
			return size
	return ""

# ------------------------------------------------------------------ E

## legSide (1057): which horn a plate goes on / comes off.
func leg_side(load_: bool) -> String:
	var kl := side_kg(horn.L)
	var kr := side_kg(horn.R)
	var nl: int = horn.L.size()
	var nr: int = horn.R.size()
	if load_:
		if nr >= 3:
			return "L"
		if nl >= 3:
			return "R"
		return "L" if kl < kr else "R"
	if nl == 0:
		return "R"
	if nr == 0:
		return "L"
	return "L" if kl > kr else "R"

## gymNear (934): {kind, label, side} or {}.
func gym_near(p: Node3D) -> Dictionary:
	if p == null or not is_instance_valid(p) or bool(p.get_meta("carrying_goth", false)):
		return {}
	var o := ppos(p)
	if lifts.has(p):
		return {"kind": "getup", "label": "GET UP"}
	if legs.has(p):
		return {"kind": "legoff", "label": "GET UP"}
	if not anim.is_empty():
		return {}
	var hp: String = plates.get(p, "")
	var n: int = horn.L.size() + horn.R.size()
	if absf(o.x - (LEG_X + 56.0)) < 20.0 and o.y > LEG_Y - 62.0 and o.y < LEG_Y + 14.0:
		if hp != "":
			return {"kind": "legload", "label": "LOAD"} if n < 6 else {}
		return {"kind": "legunload", "label": "UNLOAD"} if n > 0 else {}
	if hp == "" and absf(o.x - (LEG_X - 16.0)) < 24.0 and o.y > LEG_Y - 4.0 and o.y < LEG_Y + 32.0:
		return {"kind": "leg", "label": "LEG PRESS"}
	if absf(o.x - RACK_X) < 40.0 and o.y > RACK_Y - 19.0 and o.y < RACK_Y + 44.0:
		if hp != "":
			return {"kind": "rack", "label": "RACK IT"} if _tree_room() else {}
		return {"kind": "take", "label": "TAKE"} if _tree_has() else {}
	for s in ["L", "R"]:
		var ex := BAR_REST.x + (-48.0 if s == "L" else 48.0)
		if absf(o.x - ex) < 18.0 and o.y > BENCH_Y - 45.0 and o.y < BENCH_Y + 16.0:
			if hp != "":
				return {"kind": "load", "side": s, "label": "LOAD"} if bar[s].size() < 3 else {}
			return {"kind": "unload", "side": s, "label": "UNLOAD"} if not bar[s].is_empty() else {}
	if hp == "" and absf(o.x - BENCH_X) < 22.0 and o.y > BENCH_Y - 4.0 and o.y < BENCH_Y + 36.0:
		return {"kind": "lift", "label": "BENCH"}
	return {}

func label_for(p: Node) -> String:
	if lifts.has(p) or legs.has(p):
		return "GET UP"
	if not can_start(p):
		return ""
	return String(gym_near(p).get("label", ""))

func act(p: Node) -> void:
	if can_start(p):
		do_action(p as Player, gym_near(p))

func busy_label(p: Player) -> String:
	return "GET UP" if lifting(p) else ""

func busy_act(p: Player) -> void:
	if lifts.has(p):
		do_action(p, {"kind": "getup"})
	elif legs.has(p):
		do_action(p, {"kind": "legoff"})

func clank() -> void:
	ll.sfx.play("clank")

## gymAction (962).
func do_action(p: Player, a: Dictionary) -> void:
	if a.is_empty():
		return
	var side: String = a.get("side", "")
	match a.kind:
		"take":
			var s := _take_plate()
			if s != "":
				plates[p] = s
				clank()
		"rack":
			rack_plate(plates[p])
			plates.erase(p)
			clank()
		"load":
			anim = {"kind": "load", "side": side, "size": plates[p], "t": 0.0, "dur": ANIM_DUR, "who": p}
			plates.erase(p)
			_anim_marks = {}
		"unload":
			var s2: String = bar[side].pop_back()
			anim = {"kind": "unload", "side": side, "size": s2, "t": 0.0, "dur": ANIM_DUR, "who": p}
			_anim_marks = {}
		"lift":
			if side_kg(bar.L) != side_kg(bar.R):
				ll.ui.float_text(BENCH_X, BENCH_Y, 70.0, "LOAD IT EVEN", Color("#ffb070"), 0.9, 18)
				return
			var kg := bench_kg()
			lifts[p] = {"t": 0.0, "reps": 0, "rep": 1.3 + kg * 0.012}
			ll.hold(p, self)
			_pin(p)
			ll.ui.float_text(BENCH_X, BENCH_Y, 70.0, "%d KG" % kg, Color("#f6d17a"), 0.9, 18)
		"getup":
			var n: int = lifts[p].reps
			lifts.erase(p)
			ll.release(p)
			p.dz = 0.0
			got_up.emit(p, "bench", n)
			if n > 0:
				ll.ui.float_text(BENCH_X, BENCH_Y, 70.0, "%d REP%s" % [n, "" if n == 1 else "S"], Color("#8fd3ff"), 0.9, 18)
		"legload":
			horn[leg_side(true)].append(plates[p])
			plates.erase(p)
			clank()
		"legunload":
			plates[p] = horn[leg_side(false)].pop_back()
			clank()
		"leg":
			var kg2 := leg_kg()
			legs[p] = {"t": 0.0, "reps": 0, "rep": 1.2 + kg2 * 0.008}
			ll.hold(p, self)
			_pin(p)
			ll.ui.float_text(LEG_X - 10.0, LEG_Y, 100.0, "%d KG" % kg2, Color("#f6d17a"), 0.9, 18)
		"legoff":
			var n2: int = legs[p].reps
			legs.erase(p)
			ll.release(p)
			p.dz = 0.0
			got_up.emit(p, "leg", n2)
			if n2 > 0:
				ll.ui.float_text(LEG_X - 10.0, LEG_Y, 100.0, "%d REP%s" % [n2, "" if n2 == 1 else "S"], Color("#8fd3ff"), 0.9, 18)

## Pinned to the bench or the seat (first person: his eyes low, lying down).
func _pin(p: Player) -> void:
	var fp := p.is_first_person()
	if lifts.has(p):
		# first person: eyes a little back from the bench so you see the lift (the HTML game steps first person aside)
		if fp:
			put(p, BENCH_X, BENCH_Y + 120.0, -12.0)
		else:
			put(p, BENCH_X, BENCH_Y + 18.0, 0.0)
		p.facing = Vector2(0, -1)
	elif legs.has(p):
		if fp:
			put(p, LEG_X - 20.0, LEG_Y + 110.0, -12.0)
		else:
			put(p, LEG_X - 16.0, LEG_Y + 6.0, 0.0)
		p.facing = Vector2(0, -1)

## Off by the stick or the roll: no floater, the bench leaves him where he lies, the leg press puts him in front.
func _get_off(p: Player) -> void:
	var n: int
	if lifts.has(p):
		n = lifts[p].reps
		lifts.erase(p)
		ll.release(p)
		p.dz = 0.0
		got_up.emit(p, "bench", n)
	elif legs.has(p):
		n = legs[p].reps
		legs.erase(p)
		ll.release(p)
		p.dz = 0.0
		p.place(LEG_X - 16.0, LEG_Y + 20.0)
		got_up.emit(p, "leg", n)

func busy_end(p: Player) -> void:
	lifts.erase(p)
	legs.erase(p)

func hides_sprite(p: Player) -> bool:
	return lifting(p)

func busy_step(p: Player, dt: float) -> void:
	if not lifting(p):
		return
	if p.read_steer().length() > 0.3 or Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_action_pressed("roll"):
		_get_off(p)
		return
	_pin(p)
	var s: Dictionary = lifts[p] if lifts.has(p) else legs[p]
	var before := int(floor(s.t / s.rep))
	s.t += minf(dt, 0.1)
	if int(floor(s.t / s.rep)) > before:
		s.reps += 1
		var bench := lifts.has(p)
		var mach := "bench" if bench else "leg"
		if bench:
			ll.ui.float_text(BENCH_X, BENCH_Y, 64.0, str(s.reps), Color("#8fd3ff"), 0.9, 18)
		else:
			ll.ui.float_text(LEG_X - 10.0, LEG_Y, 96.0, str(s.reps), Color("#8fd3ff"), 0.9, 18)
		ll.sfx.noise(0.08, 0.12, 0.12)
		ll.sfx.play("grunt")
		rep.emit(p, mach, s.reps)

# ------------------------------------------------------------------ every frame: the load animation, the pictures

func _process(dt: float) -> void:
	clock += dt
	_hide_world_props()
	if not anim.is_empty():
		_step_anim(minf(dt, 0.1))
	_draw_bench()
	_draw_rack()
	_draw_leg()
	_draw_held()

func _step_anim(dt: float) -> void:
	var before: float = anim.t / anim.dur
	anim.t += dt
	var f: float = anim.t / anim.dur
	if before < 0.3 and f >= 0.3:
		ll.sfx.tone(700, 0.05, "square", 0.1, 500)
	if before < 0.62 and f >= 0.62:
		ll.sfx.tone(260, 0.09, "triangle", 0.2, 180)
		ll.sfx.noise(0.06, 0.14, 0.5)
	if anim.t >= anim.dur:
		var an := anim
		anim = {}
		if an.kind == "load":
			bar[an.side].append(an.size)
		else:
			var who = an.who
			if is_instance_valid(who) and not plates.has(who):
				plates[who] = an.size
			else:
				rack_plate(an.size)

func _hide_world_props() -> void:
	if _hid:
		return
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world_builder")
	if _world == null:
		return
	var pr = _world.get("props")
	if pr is Dictionary and pr.has("bench"):
		for k in ["bench", "rack", "legpress"]:
			if pr.has(k):
				pr[k].visible = false
		_hid = true

func _art(n: String) -> Texture2D:
	if not _tex.has(n):
		_tex[n] = LobbyPic.art("gym/%s.png" % n)
	return _tex[n]

## A piece of a picture (the HTML game's part() / the tips): sx, sy, sw, sh in its art pixels.
func _part(n: String, r: Rect2) -> Texture2D:
	var src := _art(n)
	if src == null:
		return null
	var x0 := clampf(r.position.x, 0.0, src.get_width() - 1.0)
	var y0 := clampf(r.position.y, 0.0, src.get_height() - 1.0)
	var w := clampf(r.size.x, 1.0, src.get_width() - x0)
	var h := clampf(r.size.y, 1.0, src.get_height() - y0)
	var key := "%s|%d|%d|%d|%d" % [n, x0, y0, w, h]
	if not _atlas.has(key):
		var a := AtlasTexture.new()
		a.atlas = src
		a.region = Rect2(x0, y0, w, h)
		_atlas[key] = a
	return _atlas[key]

func _lifter_of(d: Dictionary) -> Player:
	for q in d:
		if is_instance_valid(q):
			return q
	return null

func _tint(p: Player) -> String:
	return p.char_id if p != null and p.char_id == "tyson2" else ""

# --- the bench

func _draw_bench() -> void:
	var who := _lifter_of(lifts)
	var gkg := bench_kg()
	var fi := 0
	if who:
		var f: float = fmod(lifts[who].t, lifts[who].rep) / lifts[who].rep
		fi = 0 if f < 0.2 else (1 if f < 0.4 else (2 if f < 0.6 else (3 if f < 0.8 and gkg >= 60 else (1 if f < 0.8 else 0))))
	var sig := "%s|%d|%s|%s|%s|%s" % [who != null, fi, str(bar), "" if anim.is_empty() else "%s%s%d" % [anim.kind, anim.side, int(anim.t * 60.0)], _tint(who), ""]
	if sig == _bench.sig:
		return
	_bench.sig = sig
	_bench.begin()
	if who == null:
		_bench.add(_art("bench"), BENCH_O.x + 31.0, BENCH_O.y + 35.5, false)
		_loaded_bar(_bench, BAR_REST.x, BAR_REST.y)
	else:
		var px := BENCH_O.x - 0.5
		var py := BENCH_O.y
		var fr := _art("bench_press_frame%d" % fi)
		_bench.add(fr, px + 37.25, py + 41.0, false, _tint(who))
		var F: Array = FISTS[fi]
		_loaded_bar(_bench, px + (F[0] + F[2]) / 4.0, py + (F[1] + F[3]) / 4.0 + 0.5)
		_bench.add(_art("fist_%d" % fi), px + 37.25, py + 41.0, false, _tint(who))
	_bench.end()

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

## drawLoadedBar (830): the bar, then each side's plates and collar, sliding in or out during the animation.
func _loaded_bar(st: _Station, cx: float, cy: float) -> void:
	st.add(_art("barbell"), cx, cy, false)
	for s in ["L", "R"]:
		var dir := -1.0 if s == "L" else 1.0
		var flip: bool = s == "R"
		var shoulder := cx + dir * (54.0 - 27.5)
		var end := cx + dir * 54.0
		var list: Array = bar[s]
		var n := list.size()
		var an_here: bool = not anim.is_empty() and anim.side == s
		var f: float = anim.t / anim.dur if an_here else 0.0
		var slot := func(k: float) -> float: return shoulder + dir * (2.0 + 3.35 * k)
		var cpos := func(m: float) -> float: return shoulder + dir * (2.0 + 3.35 * m + 2.0)
		for k in n:
			st.add(_art("plate_" + list[k]), slot.call(k), cy, flip)
		var collar_x: float = cpos.call(n)
		var out := end + dir * 8.0
		if an_here:
			if anim.kind == "load":
				if f >= 0.3:
					var px: float = end + (float(slot.call(n)) - end) * _ease((f - 0.3) / 0.35)
					st.add(_art("plate_" + anim.size), px, cy, flip)
				if f < 0.3:
					collar_x = lerpf(float(cpos.call(n)), out, _ease(f / 0.3))
				elif f < 0.65:
					collar_x = NAN
				else:
					collar_x = lerpf(out, float(cpos.call(n + 1)), _ease((f - 0.65) / 0.35))
			else:
				if f < 0.65:
					var px2: float = float(slot.call(n)) if f < 0.3 else lerpf(float(slot.call(n)), end + dir * 11.0, _ease((f - 0.3) / 0.35))
					st.add(_art("plate_" + anim.size), px2, cy, flip)
				if f < 0.3:
					collar_x = lerpf(float(cpos.call(n + 1)), out, _ease(f / 0.3))
				elif f < 0.65:
					collar_x = NAN
				else:
					collar_x = lerpf(out, float(cpos.call(n)), _ease((f - 0.65) / 0.35))
		if not is_nan(collar_x):
			st.add(_art("collar"), collar_x, cy, flip)

# --- the plate tree

func _draw_rack() -> void:
	var sig := str(pegs)
	if sig == _rack.sig:
		return
	_rack.sig = sig
	_rack.begin()
	var c := Vector2(RACK_O.x + 21.0, RACK_O.y + 39.5)
	_rack.add(_art("rack_back"), c.x, c.y, false)
	for i in [3, 4, 5]:
		var q: Array = pegs[i]
		for k in range(q.size() - 1, -1, -1):
			_rack.add(_art("plate_" + q[k]), _plate_at(i, k).x, _plate_at(i, k).y, true)
	_rack.add(_art("rack_post"), c.x, c.y, false)
	_rack.add(_art("rack_front"), c.x, c.y, false)
	for i in [0, 1, 2]:
		var q2: Array = pegs[i]
		for k in q2.size():
			_rack.add(_art("plate_" + q2[k]), _plate_at(i, k).x, _plate_at(i, k).y, false)
	for i in [0, 1, 2]:
		var n: int = pegs[i].size()
		if n == 0:
			continue
		var hole: float = float(PEGS[i][0]) - 4.0 * (n - 1)
		var cut := maxf(0.0, hole - 1.0)
		if cut < 1.0:
			continue
		var r0: float = PEG_ROWS[i][0]
		var r1: float = PEG_ROWS[i][1]
		var tip := _part("rack_front", Rect2(0, r0, round(cut), r1 - r0))
		if tip:
			_rack.add(tip, RACK_O.x + round(cut) / 4.0, RACK_O.y + r0 / 2.0 + (r1 - r0) / 4.0, false)
	_rack.add(_art("rack_base"), c.x, c.y, false)
	_rack.end()

func _plate_at(i: int, k: int) -> Vector2:
	var side: float = PEGS[i][2]
	return Vector2(RACK_O.x + (float(PEGS[i][0]) + side * 4.0 * k) / 2.0, RACK_O.y + (float(PEGS[i][1]) - side * 0.4 * k) / 2.0)

# --- the leg press

func _draw_leg() -> void:
	var who := _lifter_of(legs)
	var fi := -1
	if who:
		var s: Dictionary = legs[who]
		var f: float = fmod(s.t, s.rep) / s.rep
		fi = 0 if f < 0.2 else (1 if f < 0.4 else (2 if f < 0.6 else ((3 if s.reps >= 10 else 4) if f < 0.8 else 0)))
	var sig := "%d|%s|%s" % [fi, str(horn), _tint(who)]
	if sig == _leg.sig:
		return
	_leg.sig = sig
	_leg.begin()
	var src_name := "legpress_machine" if fi < 0 else "legpress_frame%d" % (fi + 1)
	var src := _art(src_name)
	var c := Vector2(LEG_O.x + 53.5, LEG_O.y + 41.0)
	_leg.add(src, c.x, c.y, false, _tint(who))
	var H: Dictionary = LEG_HORNS[fi + 1]
	var nl: int = horn.L.size()
	var nr: int = horn.R.size()
	var lx: float = H.L[0]
	var ly: float = H.L[1]
	var rx: float = H.R[0]
	var ry: float = H.R[1]
	for k in nl:
		var p: Vector2 = Vector2(lx, ly) + LEG_DIR.L * LEG_STEP * k
		_leg.add(_art("legplate_" + horn.L[k]), LEG_O.x + p.x / 2.0, LEG_O.y + p.y / 2.0, false)
	if nl > 0:
		var x0 := lx - 20.5
		var last: Vector2 = Vector2(lx, ly) + LEG_DIR.L * LEG_STEP * (nl - 1)
		_leg_part(src_name, x0, ly - 7.0, last.x - x0, 14.0, _tint(who))
		_leg_part(src_name, lx + 7.5, ly - 27.0, 18.0, 62.0, _tint(who))
	for k in nr:
		var p2: Vector2 = Vector2(rx, ry) + LEG_DIR.R * LEG_STEP * k
		_leg.add(_art("legplate_" + horn.R[k]), LEG_O.x + p2.x / 2.0, LEG_O.y + p2.y / 2.0, true)
	if nr > 0:
		var last2: Vector2 = Vector2(rx, ry) + LEG_DIR.R * LEG_STEP * (nr - 1)
		var x := ceilf(last2.x) + 1.0
		_leg_part(src_name, x, ry - 8.5, src.get_width() - x, 18.0, _tint(who))
	_leg.end()

## part(sx, sy, sw, sh): that rectangle of the machine picture drawn again over the plates.
func _leg_part(src_name: String, sx: float, sy: float, sw: float, sh: float, tint: String) -> void:
	sx = maxf(0.0, floorf(sx / 2.0) * 2.0)
	var t := _part(src_name, Rect2(sx, round(sy), round(sw), round(sh)))
	if t == null:
		return
	var a := t as AtlasTexture
	_leg.add(t, LEG_O.x + (a.region.position.x + a.region.size.x / 2.0) / 2.0, LEG_O.y + (a.region.position.y + a.region.size.y / 2.0) / 2.0, false, tint)

# --- the plate in hand (drawHeldPlate 1151)

func _draw_held() -> void:
	for p in plates.keys():
		if not is_instance_valid(p):
			plates.erase(p)
			continue
	for p in _held.keys():
		if not plates.has(p) or not is_instance_valid(p):
			if is_instance_valid(_held[p]):
				_held[p].queue_free()
			_held.erase(p)
	for p in plates:
		var pic: LobbyPic = _held.get(p, null)
		if pic == null:
			pic = LobbyPic.make(null, 0.5, 0.0)
			pic.name = "HeldPlate"
			ll.add_child(pic)
			_held[p] = pic
		var tex := _art("plate_" + plates[p])
		var o := ppos(p)
		var left: bool = p.facing.x < 0.0
		if pic.texture != tex:
			pic.texture = tex
		pic.flip = left
		pic.global_position = GameData.world_to_3d(o.x + (-4.0 if left else 4.0), o.y + 0.6, p.dz)
		pic.lift = 16.0 - tex.get_height() * 0.25
		pic.visible = not p.is_first_person() and not lifting(p)

## One machine's pictures: a pool of LobbyPics on one standing line, in the order drawn (each a hair nearer).
class _Station:
	var gym: LobbyGym
	var feet: float
	var pics: Array = []
	var n: int = 0
	var sig: String = ""

	func _init(g: LobbyGym, f: float) -> void:
		gym = g
		feet = f

	func begin() -> void:
		n = 0

	func add(tex: Texture2D, cx: float, cy: float, flip: bool, tint: String = "") -> void:
		if tex == null:
			return
		if n >= pics.size():
			var pc := LobbyPic.make(null, 0.5, 0.0)
			gym.ll.add_child(pc)
			pics.append(pc)
		var pic: LobbyPic = pics[n]
		pic.visible = true
		pic.texture = tex
		pic.flip = flip
		pic.recolour_for = tint
		pic.global_position = GameData.world_to_3d(cx, feet + 0.3 + n * 0.12, 0.0)
		pic.lift = feet - (cy + tex.get_height() * 0.25)
		n += 1

	func end() -> void:
		for i in range(n, pics.size()):
			pics[i].visible = false

# ------------------------------------------------------------------ test scene

## ?lobby=gym[,fp][,bench][,leg][,plate][,load]: stand in front of what is asked and use it.
func test_scene(tl: Node, parts: PackedStringArray) -> void:
	var p: Player = ll.player
	if parts.has("leg"):
		horn.L = ["L", "M"]
		horn.R = ["L"]
		tl.go(454.0, 250.0, Vector2(0, -1))
		tl.later(0.6, func(): tl.use())
	elif parts.has("plate"):
		tl.go(528.0, 150.0, Vector2(1, 0))
		tl.later(0.6, func(): tl.use())
	elif parts.has("load"):
		tl.go(374.0, 140.0, Vector2(0, -1))
		tl.later(0.5, func(): plates[p] = "L"; tl.use())
	elif parts.has("bench"):
		bar.L = ["L", "M"]
		bar.R = ["L", "M"]
		tl.go(420.0, 150.0, Vector2(0, -1))
		tl.later(0.6, func(): tl.use())
	else:
		tl.go(470.0, 190.0, Vector2(0, -1))
