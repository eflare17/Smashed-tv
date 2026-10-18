class_name CharFrames
extends RefCounted
## The characters' frame tables: which picture (a path in assets/manifest.json) for which character, view
## and frame, and how big each one is drawn. Everything here is read from the HTML game (Smashed.html:
## CHARS, NEW_ROLL, NEW_ART, CHAR_POSE_SCALE, the *_SHOTGUN_SCALE tables, cyclePose/poseFor/drawJared).
## Owned by the Characters task. All static: CharFrames.frames("juicy", "front_run") etc.
##
## Character ids are the manifest's CHARS keys: "juicy" (Juicy Jared), "tyson2" (Tornado Tyson: a recolour of
## juicy, made in the shader), "goth" (Gothica), "inky", old art "jared" and "tyson", and the weapon sheets
## ("juicy_shotgun", "tyson2_spud", ...). Frame keys are the manifest's sprite keys: front_run (7 frames),
## diag_run, side_run, bdiag_run, back_run, front_a, front_b, ..., back, roll1..4, victory.

## The five views, in the order the angle sweeps from toward-the-camera to away from it.
const VIEWS: Array[String] = ["front", "diag", "side", "bdiag", "back"]

## Playable characters, in the HTML game's order (data CHAR_IDS).
const PLAYABLE: Array[String] = ["juicy", "tyson2", "goth"]

## The new art (160 px tall sheets, drawn at T.altScale). The HTML game's NEW_ART set.
const NEW_ART: Array[String] = ["juicy", "tyson2", "goth", "inky"]

## Weapon sheet suffixes: "juicy_shotgun" is Juicy holding the shotgun.
const WEAPON_SUFFIXES: Array[String] = ["_shotgun", "_spud", "_launcher"]

## Sheets that get the hand-drawn new-art roll (NEW_ROLL) instead of their own roll1..4 (and so do their
## recolours: tyson2 and its weapon sheets).
const NEW_ROLL_SHEETS: Array[String] = ["juicy", "juicy_shotgun", "juicy_spud", "juicy_launcher"]

## Per-pose size corrections (Smashed.html CHAR_POSE_SCALE and the shotgun tables), by sheet then frame key.
const CHAR_POSE_SCALE := {
	"tyson": {"front_run": 1.0078, "diag_run": 1.0952, "side_run": 1.1948, "bdiag_run": 1.1948, "back_run": 1.0557},
}
const SHEET_POSE_SCALE := {
	"jared_shotgun": {"back": 1.0, "bdiag_a": 1.0, "bdiag_b": 1.0105, "diag_a": 1.1566, "diag_b": 1.0549, "front_a": 1.1034, "front_b": 1.1034, "side_a": 1.0, "side_b": 1.0},
	"tyson_shotgun": {"front_a": 1.0, "front_b": 1.0, "diag_a": 1.1026, "diag_b": 1.1125, "side_a": 1.1719, "side_b": 1.1719, "bdiag_a": 1.1294, "bdiag_b": 1.0988, "back": 1.0787, "back_b": 1.0787},
	"juicy_shotgun": {"front_a": 1.1852, "front_b": 1.1852, "diag_a": 1.2308, "diag_b": 1.2308, "side_a": 1.2308, "side_b": 1.2468, "bdiag_a": 1.2308, "bdiag_b": 1.2308, "back": 1.0, "back_b": 1.0},
	"tyson2_shotgun": {"front_a": 1.1852, "front_b": 1.1852, "diag_a": 1.2308, "diag_b": 1.2308, "side_a": 1.2308, "side_b": 1.2468, "bdiag_a": 1.2308, "bdiag_b": 1.2308, "back": 1.0, "back_b": 1.0},
}
## Old-art roll frames: where the lowest pixel sits in each 96 px frame (drawJared's ROLL_FLOOR).
const ROLL_FLOOR := {"roll1": 78.0, "roll2": 65.0, "roll3": 95.0, "roll4": 95.0}

## The roll, frame by frame (Smashed.html ROLL_FRAMES): share of rollTime, speed, height off the floor
## (times T.rollHop).
const ROLL_FRAMES := [
	{"dur": 0.20, "speed": 1.00, "lift": 0.35},
	{"dur": 0.26, "speed": 0.95, "lift": 1.00},
	{"dur": 0.28, "speed": 0.55, "lift": 0.55},
	{"dur": 0.26, "speed": 0.10, "lift": 0.00},
]

## HTML T values used here, with the game's own numbers as fallbacks if game_data.json lacks them.
const T_DEFAULTS := {
	"radius": 14.0, "spriteScale": 4.6, "altScale": 1.242, "altWide": 1.0, "runStride": 13.0,
	"rollScale": 1.35, "rollHop": 7.0, "rollTime": 0.42, "flexScale": 1.25,
	"diagFlip": 0, "bdiagFlip": 0, "altSideFlip": 0, "altDiagFlip": 0, "altBdiagFlip": 1,
	"sgSideFlip": 0, "sgDiagFlip": 1, "sgBdiagFlip": 1, "diagAnim": 1, "diagFrame": 0,
}

## A T value (the HTML game's tuning table), from game_data.json.
static func t(key: String) -> float:
	var gd = _gd()
	if gd != null and gd.data.has("T") and gd.data["T"].has(key) and gd.data["T"][key] != null:
		return float(gd.data["T"][key])
	return float(T_DEFAULTS.get(key, 0.0))

static func _gd() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("GameData")
	return null

static func _chars() -> Dictionary:
	var gd = _gd()
	if gd == null or not gd.manifest.has("CHARS"):
		return {}
	return gd.manifest["CHARS"]

## Every sheet the manifest has ("juicy", "juicy_shotgun", "tyson2", ...).
static func sheet_ids() -> PackedStringArray:
	return PackedStringArray(_chars().keys())

## The character a sheet belongs to: "juicy_shotgun" -> "juicy", "tyson2_spud" -> "tyson2".
static func base_char(id: String) -> String:
	for s in WEAPON_SUFFIXES:
		if id.ends_with(s):
			return id.substr(0, id.length() - s.length())
	return id

static func is_new_art(id: String) -> bool:
	return NEW_ART.has(base_char(id))

## The shotgun and launcher sheets carry their own flips.
static func is_shotgun(id: String) -> bool:
	return id.ends_with("_shotgun")

static func is_launcher(id: String) -> bool:
	return id.ends_with("_launcher")

## The sheet whose pictures this one uses: tyson2 is juicy's art recoloured (CHARS.tyson2.recolourOf).
static func source_sheet(id: String) -> String:
	var c: Dictionary = _chars()
	if c.has(id) and c[id].get("recolourOf", null) != null:
		return str(c[id]["recolourOf"])
	return id

## The recolour palette ({green, blue, boost}) for a recoloured sheet, or {} for none.
static func palette(id: String) -> Dictionary:
	var c: Dictionary = _chars()
	if c.has(id) and c[id].get("recolourOf", null) != null and c[id].get("palette", null) is Dictionary:
		return c[id]["palette"]
	return {}

## The display name ("Juicy Jared (new)").
static func display_name(id: String) -> String:
	var c: Dictionary = _chars()
	return str(c[id].get("name", id)) if c.has(id) else id

## CHARS[id].scale (all 1 today).
static func char_scale(id: String) -> float:
	var c: Dictionary = _chars()
	var b := base_char(id)
	if c.has(b) and c[b].get("scale", null) != null:
		return float(c[b]["scale"])
	return 1.0

## The frame keys a sheet has.
static func keys(id: String) -> PackedStringArray:
	var c: Dictionary = _chars()
	var src := source_sheet(id)
	if not c.has(src):
		return PackedStringArray()
	return PackedStringArray(c[src]["sprites"].keys())

## The manifest paths of one frame key (a single picture comes back as a list of one). Empty if the sheet
## hasn't got it. roll1..4 of the Juicy sheets (and their recolours) are NEW_ROLL, like the HTML game.
static var _frames_cache := {}
static func frames(id: String, key: String) -> PackedStringArray:
	var ck := id + "|" + key
	if _frames_cache.has(ck):
		return _frames_cache[ck]
	var f := _frames_uncached(id, key)
	if not _chars().is_empty():
		_frames_cache[ck] = f
	return f

static func _frames_uncached(id: String, key: String) -> PackedStringArray:
	var c: Dictionary = _chars()
	var src := source_sheet(id)
	if NEW_ROLL_SHEETS.has(src) and key.begins_with("roll") and key.length() == 5:
		var gd = _gd()
		var n := int(key.substr(4)) - 1
		if gd != null and gd.manifest.has("NEW_ROLL") and n >= 0 and n < gd.manifest["NEW_ROLL"].size():
			return PackedStringArray([gd.manifest["NEW_ROLL"][n]])
	if not c.has(src):
		return PackedStringArray()
	var v = c[src]["sprites"].get(key, null)
	if v is Array:
		return PackedStringArray(v)
	if v is String:
		return PackedStringArray([v])
	return PackedStringArray()

static func has(id: String, key: String) -> bool:
	return frames(id, key).size() > 0

static func frame_count(id: String, key: String) -> int:
	return frames(id, key).size()

## One frame's manifest path ("" if none). idx is clamped like the HTML game does.
static func path(id: String, key: String, idx: int = 0) -> String:
	var f := frames(id, key)
	if f.is_empty():
		return ""
	return f[clampi(idx, 0, f.size() - 1)]

## The run cycle key for a view, if the sheet has one ("front_run"), else "".
static func run_key(id: String, view: String) -> String:
	var k := view + "_run"
	return k if has(id, k) else ""

## The a/b stand key for a view, the way poseFor falls back when there's no run cycle: side_a/b,
## diag_a/b (or one held when T.diagAnim is 0), front_a/b, bdiag_a/b, and "back" for the back.
static func stand_key(id: String, view: String, b: bool) -> String:
	if view == "back":
		return "back"
	if view == "diag" and t("diagAnim") == 0:
		b = t("diagFrame") != 0
	return view + ("_b" if b else "_a")

## Which way each view's art faces, per sheet: true means the picture is flipped for the sectors on the
## east side of the screen (poseFor's sF, dF, bF2). The other side gets the opposite.
static func flips(id: String) -> Dictionary:
	var alt := is_new_art(id)
	var gun := is_shotgun(id)
	var d: bool
	var b: bool
	var s: bool
	if gun:
		d = t("sgDiagFlip") != 0
		b = t("sgBdiagFlip") != 0
		s = t("sgSideFlip") != 0
	elif alt:
		d = (t("altDiagFlip") != 0) != (base_char(id) == "goth")   # Gothica's down-diagonal faces the other way
		b = t("altBdiagFlip") != 0
		s = t("altSideFlip") != 0
	else:
		d = t("diagFlip") != 0
		b = t("bdiagFlip") != 0
		s = false
	if is_launcher(id):
		b = true if alt else not b
	return {"side": s, "diag": d, "bdiag": b}

## The pose-size correction for one frame key (CHAR_POSE_SCALE and the shotgun tables).
static func pose_scale(id: String, key: String) -> float:
	var k := 1.0
	var b := base_char(id)
	if CHAR_POSE_SCALE.has(b):
		k *= float(CHAR_POSE_SCALE[b].get(key, 1.0))
	if SHEET_POSE_SCALE.has(id):
		k *= float(SHEET_POSE_SCALE[id].get(key, 1.0))
	return k

static func is_roll_key(key: String) -> bool:
	return key.begins_with("roll")

## How tall a frame is drawn, in HTML units (drawJared: T.radius * T.spriteScale * CHAR scale * pose scale,
## times T.altScale for the new art, T.flexScale for victory, T.rollScale for an old-art roll). The new art
## comes out at 80 units for its 160 px sheets (2 m: his eyes are at 62).
static func draw_height(id: String, key: String) -> float:
	var h := t("radius") * t("spriteScale") * char_scale(id) * pose_scale(id, key)
	if key == "victory":
		h *= t("flexScale")
	if is_roll_key(key) and not is_new_art(id):
		h *= t("rollScale")
	if is_new_art(id):
		h *= t("altScale")
	return h

## How much wider than tall-scaled a frame is drawn (T.altWide for the new art; 1 today).
static func draw_wide(id: String) -> float:
	return t("altWide") if is_new_art(id) else 1.0

## Where the feet are in a frame, as a share of its height from the top (1 = the bottom row). Only the old
## art's roll frames differ (ROLL_FLOOR).
static func foot_frac(id: String, key: String) -> float:
	if is_roll_key(key) and not is_new_art(id):
		return float(ROLL_FLOOR.get(key, 96.0)) / 96.0
	return 1.0

## The roll at fraction f (0..1 through it): which roll frame (0..3) and the hop off the floor in HTML units,
## like rollPhase() and drawJared's lift.
static func roll_phase(f: float) -> Dictionary:
	var frac := clampf(f, 0.0, 0.9999)
	var acc := 0.0
	var i := ROLL_FRAMES.size() - 1
	var tt := 1.0
	for n in ROLL_FRAMES.size():
		var d: float = ROLL_FRAMES[n]["dur"]
		if frac < acc + d:
			i = n
			tt = (frac - acc) / d
			break
		acc += d
	var fr: Dictionary = ROLL_FRAMES[i]
	var nx: Dictionary = ROLL_FRAMES[mini(ROLL_FRAMES.size() - 1, i + 1)]
	var lift := (float(fr["lift"]) + (float(nx["lift"]) - float(fr["lift"])) * tt) * t("rollHop")
	return {"i": i, "t": tt, "lift": lift, "speed": float(fr["speed"])}

## The victory frame after `elapsed` seconds, like drawJared's breather dance; -1 if the sheet has none.
static func victory_frame(id: String, elapsed: float) -> int:
	var n := frame_count(id, "victory")
	if n == 0:
		return -1
	if n >= 8:
		var play := [0, 1, 2, 3, 4, 5, 4, 5, 7, 6, 4, 5, 4, 5, 7, 6]
		return play[mini(play.size() - 1, int(floor(elapsed * 7.0)))]
	if n == 4:
		if elapsed < 0.15:
			return 0
		if elapsed < 0.3:
			return 1
		return 2 + int(floor(elapsed * 4.0)) % 2
	if n >= 5 and base_char(id) != "goth":
		return mini(n - 1, int(floor(elapsed * 8.0)))
	return 0

## The opaque rows (alpha > 76) of every picture the recolour touches (the Juicy sheets and NEW_ROLL): first and
## last, measured from the art. recolourImage() shifts the blue only across the torso band between them.
const OPAQUE_ROWS := {
	"assets/CHARS/juicy/sprites/back.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/back_a.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/back_b.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/back_run_0.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/back_run_1.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/back_run_2.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/back_run_3.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/back_run_4.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/back_run_5.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/back_run_6.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/bdiag_a.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/bdiag_b.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/bdiag_run_0.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/bdiag_run_1.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/bdiag_run_2.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/bdiag_run_3.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/bdiag_run_4.png": Vector2i(10, 157),
	"assets/CHARS/juicy/sprites/bdiag_run_5.png": Vector2i(10, 157),
	"assets/CHARS/juicy/sprites/bdiag_run_6.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/diag_a.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/diag_b.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/diag_run_0.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/diag_run_1.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/diag_run_2.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/diag_run_3.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/diag_run_4.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/diag_run_5.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/diag_run_6.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/front_a.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/front_b.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/front_run_0.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/front_run_1.png": Vector2i(11, 159),
	"assets/CHARS/juicy/sprites/front_run_2.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/front_run_3.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/front_run_4.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/front_run_5.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/front_run_6.png": Vector2i(10, 157),
	"assets/CHARS/juicy/sprites/roll1.png": Vector2i(16, 78),
	"assets/CHARS/juicy/sprites/roll2.png": Vector2i(30, 65),
	"assets/CHARS/juicy/sprites/roll3.png": Vector2i(0, 95),
	"assets/CHARS/juicy/sprites/roll4.png": Vector2i(0, 95),
	"assets/CHARS/juicy/sprites/side_a.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/side_b.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/side_run_0.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/side_run_1.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/side_run_2.png": Vector2i(10, 157),
	"assets/CHARS/juicy/sprites/side_run_3.png": Vector2i(10, 158),
	"assets/CHARS/juicy/sprites/side_run_4.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/side_run_5.png": Vector2i(10, 159),
	"assets/CHARS/juicy/sprites/side_run_6.png": Vector2i(10, 157),
	"assets/CHARS/juicy_launcher/sprites/back.png": Vector2i(10, 159),
	"assets/CHARS/juicy_launcher/sprites/back_b.png": Vector2i(10, 159),
	"assets/CHARS/juicy_launcher/sprites/bdiag_a.png": Vector2i(44, 159),
	"assets/CHARS/juicy_launcher/sprites/bdiag_b.png": Vector2i(43, 159),
	"assets/CHARS/juicy_launcher/sprites/diag_a.png": Vector2i(38, 159),
	"assets/CHARS/juicy_launcher/sprites/diag_b.png": Vector2i(40, 159),
	"assets/CHARS/juicy_launcher/sprites/front_a.png": Vector2i(38, 159),
	"assets/CHARS/juicy_launcher/sprites/front_b.png": Vector2i(38, 159),
	"assets/CHARS/juicy_launcher/sprites/roll1.png": Vector2i(16, 78),
	"assets/CHARS/juicy_launcher/sprites/roll2.png": Vector2i(30, 65),
	"assets/CHARS/juicy_launcher/sprites/roll3.png": Vector2i(0, 95),
	"assets/CHARS/juicy_launcher/sprites/roll4.png": Vector2i(0, 95),
	"assets/CHARS/juicy_launcher/sprites/side_a.png": Vector2i(49, 159),
	"assets/CHARS/juicy_launcher/sprites/side_b.png": Vector2i(50, 159),
	"assets/CHARS/juicy_shotgun/sprites/back.png": Vector2i(0, 95),
	"assets/CHARS/juicy_shotgun/sprites/back_b.png": Vector2i(0, 95),
	"assets/CHARS/juicy_shotgun/sprites/bdiag_a.png": Vector2i(18, 95),
	"assets/CHARS/juicy_shotgun/sprites/bdiag_b.png": Vector2i(18, 95),
	"assets/CHARS/juicy_shotgun/sprites/diag_a.png": Vector2i(18, 95),
	"assets/CHARS/juicy_shotgun/sprites/diag_b.png": Vector2i(18, 95),
	"assets/CHARS/juicy_shotgun/sprites/front_a.png": Vector2i(15, 95),
	"assets/CHARS/juicy_shotgun/sprites/front_b.png": Vector2i(15, 95),
	"assets/CHARS/juicy_shotgun/sprites/roll1.png": Vector2i(16, 78),
	"assets/CHARS/juicy_shotgun/sprites/roll2.png": Vector2i(30, 65),
	"assets/CHARS/juicy_shotgun/sprites/roll3.png": Vector2i(0, 95),
	"assets/CHARS/juicy_shotgun/sprites/roll4.png": Vector2i(0, 95),
	"assets/CHARS/juicy_shotgun/sprites/side_a.png": Vector2i(18, 95),
	"assets/CHARS/juicy_shotgun/sprites/side_b.png": Vector2i(19, 95),
	"assets/CHARS/juicy_spud/sprites/back.png": Vector2i(10, 159),
	"assets/CHARS/juicy_spud/sprites/back_b.png": Vector2i(10, 159),
	"assets/CHARS/juicy_spud/sprites/back_run_0.png": Vector2i(11, 158),
	"assets/CHARS/juicy_spud/sprites/back_run_1.png": Vector2i(11, 157),
	"assets/CHARS/juicy_spud/sprites/back_run_2.png": Vector2i(11, 158),
	"assets/CHARS/juicy_spud/sprites/back_run_3.png": Vector2i(11, 157),
	"assets/CHARS/juicy_spud/sprites/back_run_4.png": Vector2i(11, 158),
	"assets/CHARS/juicy_spud/sprites/back_run_5.png": Vector2i(11, 157),
	"assets/CHARS/juicy_spud/sprites/back_run_6.png": Vector2i(11, 158),
	"assets/CHARS/juicy_spud/sprites/bdiag_a.png": Vector2i(11, 159),
	"assets/CHARS/juicy_spud/sprites/bdiag_b.png": Vector2i(11, 159),
	"assets/CHARS/juicy_spud/sprites/bdiag_run_0.png": Vector2i(12, 159),
	"assets/CHARS/juicy_spud/sprites/bdiag_run_1.png": Vector2i(12, 159),
	"assets/CHARS/juicy_spud/sprites/bdiag_run_2.png": Vector2i(12, 159),
	"assets/CHARS/juicy_spud/sprites/bdiag_run_3.png": Vector2i(12, 159),
	"assets/CHARS/juicy_spud/sprites/bdiag_run_4.png": Vector2i(12, 159),
	"assets/CHARS/juicy_spud/sprites/bdiag_run_5.png": Vector2i(12, 159),
	"assets/CHARS/juicy_spud/sprites/bdiag_run_6.png": Vector2i(12, 159),
	"assets/CHARS/juicy_spud/sprites/diag_a.png": Vector2i(10, 158),
	"assets/CHARS/juicy_spud/sprites/diag_b.png": Vector2i(10, 158),
	"assets/CHARS/juicy_spud/sprites/diag_run_0.png": Vector2i(8, 155),
	"assets/CHARS/juicy_spud/sprites/diag_run_1.png": Vector2i(7, 155),
	"assets/CHARS/juicy_spud/sprites/diag_run_2.png": Vector2i(7, 149),
	"assets/CHARS/juicy_spud/sprites/diag_run_3.png": Vector2i(7, 156),
	"assets/CHARS/juicy_spud/sprites/diag_run_4.png": Vector2i(7, 156),
	"assets/CHARS/juicy_spud/sprites/diag_run_5.png": Vector2i(7, 156),
	"assets/CHARS/juicy_spud/sprites/diag_run_6.png": Vector2i(7, 159),
	"assets/CHARS/juicy_spud/sprites/front_a.png": Vector2i(10, 158),
	"assets/CHARS/juicy_spud/sprites/front_b.png": Vector2i(10, 158),
	"assets/CHARS/juicy_spud/sprites/front_run_0.png": Vector2i(12, 158),
	"assets/CHARS/juicy_spud/sprites/front_run_1.png": Vector2i(12, 158),
	"assets/CHARS/juicy_spud/sprites/front_run_2.png": Vector2i(12, 158),
	"assets/CHARS/juicy_spud/sprites/front_run_3.png": Vector2i(12, 158),
	"assets/CHARS/juicy_spud/sprites/front_run_4.png": Vector2i(12, 158),
	"assets/CHARS/juicy_spud/sprites/front_run_5.png": Vector2i(12, 156),
	"assets/CHARS/juicy_spud/sprites/front_run_6.png": Vector2i(12, 158),
	"assets/CHARS/juicy_spud/sprites/pickup_0.png": Vector2i(20, 159),
	"assets/CHARS/juicy_spud/sprites/pickup_1.png": Vector2i(51, 158),
	"assets/CHARS/juicy_spud/sprites/pickup_2.png": Vector2i(22, 159),
	"assets/CHARS/juicy_spud/sprites/pickup_3.png": Vector2i(10, 159),
	"assets/CHARS/juicy_spud/sprites/reload_0.png": Vector2i(11, 159),
	"assets/CHARS/juicy_spud/sprites/reload_1.png": Vector2i(11, 159),
	"assets/CHARS/juicy_spud/sprites/reload_2.png": Vector2i(12, 159),
	"assets/CHARS/juicy_spud/sprites/reload_3.png": Vector2i(12, 159),
	"assets/CHARS/juicy_spud/sprites/reload_4.png": Vector2i(15, 159),
	"assets/CHARS/juicy_spud/sprites/reload_5.png": Vector2i(14, 159),
	"assets/CHARS/juicy_spud/sprites/reload_side_0.png": Vector2i(11, 159),
	"assets/CHARS/juicy_spud/sprites/reload_side_1.png": Vector2i(10, 159),
	"assets/CHARS/juicy_spud/sprites/reload_side_2.png": Vector2i(10, 159),
	"assets/CHARS/juicy_spud/sprites/reload_side_3.png": Vector2i(13, 159),
	"assets/CHARS/juicy_spud/sprites/reload_side_4.png": Vector2i(11, 159),
	"assets/CHARS/juicy_spud/sprites/reload_side_5.png": Vector2i(10, 159),
	"assets/CHARS/juicy_spud/sprites/roll1.png": Vector2i(16, 78),
	"assets/CHARS/juicy_spud/sprites/roll2.png": Vector2i(30, 65),
	"assets/CHARS/juicy_spud/sprites/roll3.png": Vector2i(0, 95),
	"assets/CHARS/juicy_spud/sprites/roll4.png": Vector2i(0, 95),
	"assets/CHARS/juicy_spud/sprites/side_a.png": Vector2i(10, 159),
	"assets/CHARS/juicy_spud/sprites/side_b.png": Vector2i(10, 158),
	"assets/CHARS/juicy_spud/sprites/side_run_0.png": Vector2i(8, 156),
	"assets/CHARS/juicy_spud/sprites/side_run_1.png": Vector2i(8, 157),
	"assets/CHARS/juicy_spud/sprites/side_run_2.png": Vector2i(8, 153),
	"assets/CHARS/juicy_spud/sprites/side_run_3.png": Vector2i(9, 157),
	"assets/CHARS/juicy_spud/sprites/side_run_4.png": Vector2i(9, 158),
	"assets/CHARS/juicy_spud/sprites/side_run_5.png": Vector2i(8, 159),
	"assets/CHARS/juicy_spud/sprites/side_run_6.png": Vector2i(8, 157),
	"assets/CHARS/juicy_spud/sprites/throw_front_0.png": Vector2i(4, 159),
	"assets/CHARS/juicy_spud/sprites/throw_front_1.png": Vector2i(5, 159),
	"assets/CHARS/juicy_spud/sprites/throw_front_2.png": Vector2i(5, 159),
	"assets/CHARS/juicy_spud/sprites/throw_front_3.png": Vector2i(5, 159),
	"assets/CHARS/juicy_spud/sprites/throw_front_4.png": Vector2i(5, 159),
	"assets/CHARS/juicy_spud/sprites/throw_side_0.png": Vector2i(10, 159),
	"assets/CHARS/juicy_spud/sprites/throw_side_1.png": Vector2i(10, 159),
	"assets/CHARS/juicy_spud/sprites/throw_side_2.png": Vector2i(13, 159),
	"assets/CHARS/juicy_spud/sprites/throw_side_3.png": Vector2i(14, 159),
	"assets/CHARS/juicy_spud/sprites/throw_side_4.png": Vector2i(10, 159),
	"assets/NEW_ROLL_0.png": Vector2i(47, 159),
	"assets/NEW_ROLL_1.png": Vector2i(43, 118),
	"assets/NEW_ROLL_2.png": Vector2i(67, 158),
	"assets/NEW_ROLL_3.png": Vector2i(57, 159),
}

## A picture's first and last opaque rows (for the recolour's torso band). Pictures not in the table are
## measured once from their image, or taken as the whole height if that can't be read.
static var _rows_cache := {}
static func opaque_rows(p: String, tex: Texture2D) -> Vector2i:
	if OPAQUE_ROWS.has(p):
		return OPAQUE_ROWS[p]
	if _rows_cache.has(p):
		return _rows_cache[p]
	var r := Vector2i(0, maxi(1, tex.get_height() - 1) if tex else 159)
	var img: Image = tex.get_image() if tex else null
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var top := -1
		var bot := -1
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 76.0 / 255.0:
					if top < 0:
						top = y
					bot = y
					break
		if top >= 0:
			r = Vector2i(top, bot)
	_rows_cache[p] = r
	return r
