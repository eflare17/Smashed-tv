class_name WeaponDefs
extends RefCounted
## The weapon table (WEAPONS, Smashed.html L636; also game_data.json) and the barrel maps (MUZZLE_BY_CHAR,
## weapons.md 10.1, with the mirrors derived for every set: "calibrate four, get eight"). Static.

const ORDER: Array[String] = ["fists", "spud", "lob", "blaster", "shotgun", "launcher"]
const LABEL := {"spud": "SPUD", "blaster": "BLAST", "shotgun": "SHOT", "launcher": "NUKE", "fists": "FISTS", "lob": "THROW"}
## The order weapons go over the network (snapshot p[16]).
const NET_ORDER: Array[String] = ["blaster", "shotgun", "spud", "launcher", "fists", "lob"]

static func t(key: String, fallback: float = 0.0) -> float:
	var tt: Dictionary = GameData.data.get("T", {})
	return float(tt.get(key, fallback))

static func w(id: String) -> Dictionary:
	var ws: Dictionary = GameData.data.get("WEAPONS", {})
	return ws.get(id, ws.get("blaster", {}))

static func fire_rate(id: String) -> float:
	var g := w(id)
	if g.get("rocket", false):
		return t("launcherRate", 1.1)
	return float(g.get("fireRate", t("fireRate", 9.5)))

static func has_weapon(f: FT.Fighter, id: String) -> bool:
	match id:
		"spud", "fists", "lob":
			return true
		"blaster":
			return f.blasters > 0
		"shotgun":
			return f.w_time > 0.0
		"launcher":
			return f.rockets > 0
	return false

## The sheet the character wears holding it (WEAPONS[id].skin[ch], else the character's own).
static func skin_for(ch: String, id: String) -> String:
	var sk = w(id).get("skin")
	if sk is Dictionary and sk.has(ch):
		return String(sk[ch])
	return ch

static func uses_ammo(id: String) -> bool:
	return bool(w(id).get("ammo", false))

# ---------------------------------------------------------------- barrels

## Facings 0 = E, 1 = SE, 2 = S (toward the viewer), 3 = SW, 4 = W, 5 = NW, 6 = N, 7 = NE; [gun 0, gun 1], in
## screen pixels as drawn from his centre (feet at +12.6). Mirrors derived (10.1 "derived" rows).
const _JARED := [[Vector2(7, -6.4), Vector2(24, -23.4)], [Vector2(-8, -12.5), Vector2(-16.5, -7)],
	[Vector2(-20, 7), Vector2(20.5, 6)], [Vector2(16.5, -7), Vector2(8, -12.5)], [Vector2(-30, -28.5), Vector2(-13.5, -18)],
	[Vector2(20, -41.5), Vector2(-22, -40.5)], [Vector2(20.5, -42), Vector2(-20, -40.5)], [Vector2(13.5, -18), Vector2(30, -28.5)]]
const _JUICY := [[Vector2(26.5, -41.6), Vector2(19, -33.6)], [Vector2(-11, -29.6), Vector2(26, -33.6)],
	[Vector2(-12, -33.1), Vector2(10.5, -34.6)], [Vector2(6.5, -27.6), Vector2(-25.5, -31.1)], [Vector2(-29, -41.1), Vector2(-20.5, -35.1)],
	[Vector2(20, -41.5), Vector2(-22, -40.5)], [Vector2(20.5, -42), Vector2(-20, -40.5)], [Vector2(22, -40.5), Vector2(-20, -41.5)]]
const _SHOTGUN := [Vector2(22, -22), Vector2(14, -14), Vector2(2, 4), Vector2(-14, -14), Vector2(-22, -22), Vector2(-14, -38),
	Vector2(2, -44), Vector2(14, -38)]
const _LAUNCHER := [Vector2(31, -28), Vector2(15, -13), Vector2(-10, -26), Vector2(-15, -13), Vector2(-31, -28), Vector2(-20, -42),
	Vector2(0, -56), Vector2(21, -42)]
const _SPUD := [[Vector2(30, -11), Vector2(30, -25)], [Vector2(21, -38), Vector2(21, -38)], [Vector2(-7, 12), Vector2(7, 12)],
	[Vector2(-21, -38), Vector2(-21, -38)], [Vector2(-30, -25), Vector2(-30, -11)], [Vector2(-10, -66), Vector2(-10, -66)],
	[Vector2(10, -66), Vector2(10, -66)], [Vector2(30, -11), Vector2(30, -25)]]
const _GOTH := [[Vector2(30, -11), Vector2(30, -25)], [Vector2(16.3, 8.2), Vector2(26.2, -1.7)], [Vector2(-7, 12), Vector2(7, 12)],
	[Vector2(-26.2, -1.7), Vector2(-16.3, 8.2)], [Vector2(-30, -25), Vector2(-30, -11)], [Vector2(7, -48), Vector2(-7, -48)],
	[Vector2(7, -48), Vector2(-7, -48)], [Vector2(30, -11), Vector2(30, -25)]]

static var _maps: Dictionary = {}

static func _build() -> void:
	if not _maps.is_empty():
		return
	_maps["jared"] = _JARED
	var tyson: Array = _JARED.duplicate(true)
	tyson[0] = [Vector2(29, -27.9), Vector2(13, -10.9)]
	_maps["tyson"] = tyson
	_maps["juicy"] = _JUICY
	var t2: Array = _JARED.duplicate(true)
	t2[0] = [Vector2(13.5, -18), Vector2(30, -28.5)]
	t2[7] = [Vector2(22, -40.5), Vector2(-20, -41.5)]
	_maps["tyson2"] = t2
	_maps["goth"] = _GOTH
	_maps["inky"] = _GOTH
	for k in ["jared_shotgun", "tyson_shotgun", "juicy_shotgun", "tyson2_shotgun"]:
		_maps[k] = _pairs(_SHOTGUN)
	for k in ["juicy_launcher", "tyson2_launcher"]:
		_maps[k] = _pairs(_LAUNCHER)
	for k in ["juicy_spud", "tyson2_spud"]:
		_maps[k] = _SPUD

static func _pairs(one: Array) -> Array:
	var out := []
	for v in one:
		out.append([v, v])
	return out

## barrelKey: the weapon's skin for this character, else the character.
static func barrel_key(ch: String, id: String) -> String:
	return skin_for(ch, id)

## The barrel offset (screen pixels as drawn, x right, y down, from his centre; his feet are at +12.6).
static func barrel(key: String, oct: int, gun: int) -> Vector2:
	_build()
	var m: Array = _maps.get(key, _maps.get(key.split("_")[0], _JARED))
	var pair: Array = m[posmod(oct, 8)]
	return pair[gun & 1 if t("dualGuns", 1) > 0.0 else 0]

## octOf: the nearest of the eight facings to (ax, ay).
static func oct_of(ax: float, ay: float) -> int:
	return posmod(int(round(atan2(ay, ax) / (PI / 4.0))), 8)
