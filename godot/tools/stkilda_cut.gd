extends SceneTree
## St Kilda in the voxel game: cut the St Kilda map (stkilda-godot data/town.json) down to the slice the voxel game
## has: Luna Park (its wall, OpenStreetMap's way SkLunaPark.WALL_WAY in data/luna.json) and MARGIN m round it.
## Anything flat or built that touches the slice is kept whole (so nothing's cut in half at the edge); roads are
## trimmed to a little past it. The slice's box goes in as "slice" [x0, z0, x1, z1] (map metres), for its walls.
## The whole slice is then moved PLACE_X m east (its middle there), well away from the arena: every x on the map, and
## its origin's longitude so Luna Park's own data (lat / lon, data/luna.json) lands there too (an east-west move only,
## so it's exact). The St Kilda code then works in its own map's metres with nothing to add (some of it reads where
## things are in the world, some where they are on the map: the same here).
## Writes data/stkilda/town.json and data/stkilda/luna.json. Run by tools/stkilda_sync.sh (-- --src=<stkilda-godot>).

const MARGIN := 50.0
const WALL_WAY := 15477129      # (SkLunaPark.WALL_WAY: not loaded here, the copied classes may not be in yet)
const ROAD_PAST := 30.0         # roads go on this far past the slice
const PLACE_X := 3000.0         # where the slice's middle goes (m east of the arena: far past its sky line)

func _init() -> void:
	var src := "C:/Users/Admin/Documents/stkilda-godot"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			src = a.trim_prefix("--src=")
	var town: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src + "/data/town.json"))
	var luna_text := FileAccess.get_file_as_string(src + "/data/luna.json")
	var luna: Dictionary = JSON.parse_string(luna_text)
	var lat0: float = town.origin[0]
	var lon0: float = town.origin[1]
	var s: float = town.scale
	var lo := Vector2(INF, INF)
	var hi := -lo
	for e in luna.elements:
		if e.type == "way" and int(e.id) == WALL_WAY:
			for g in e.geometry:
				var p := Vector2((float(g.lon) - lon0) * 111320.0 * cos(deg_to_rad(lat0)) * s, -(float(g.lat) - lat0) * 110574.0 * s)
				lo = lo.min(p)
				hi = hi.max(p)
	if lo.x == INF:
		push_error("stkilda_cut: Luna Park's wall isn't in luna.json")
		quit(1)
		return
	var box := Rect2(lo, hi - lo).grow(MARGIN)
	var out := {}
	for k in town:
		var v = town[k]
		match k:
			"areas", "parks", "water", "buildings", "piers":
				out[k] = (v as Array).filter(func(it: Dictionary) -> bool: return _touches(it.p, box))
			"roads", "streams":
				var kept := []
				for r in v:
					var t := _trim(r.p, box)
					if not t.is_empty():
						var r2: Dictionary = (r as Dictionary).duplicate()
						r2.p = t
						kept.append(r2)
				out[k] = kept
			"trees", "crossings", "lights":
				out[k] = _flat(v, {"trees": 3, "crossings": 5, "lights": 5}[k], box)
			_:
				out[k] = v
	# moved east, out of the arena's way
	var dx := PLACE_X - box.get_center().x
	for k in ["areas", "parks", "water", "buildings", "piers", "roads", "streams", "bays", "rails"]:
		for it in out.get(k, []):
			it.p = _east(it.p, dx, 2)
	for k in ["trees", "crossings", "lights"]:
		out[k] = _east(out[k], dx, {"trees": 3, "crossings": 5, "lights": 5}[k])
	out.slice = [box.position.x + dx, box.position.y, box.end.x + dx, box.end.y]
	out.origin = [lat0, lon0 - dx / (111320.0 * cos(deg_to_rad(lat0)) * s)]
	out.note = String(town.get("note", "")) + " Cut to Luna Park and %d m round it by tools/stkilda_cut.gd." % int(MARGIN)
	var f := FileAccess.open("res://data/stkilda/town.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	f = FileAccess.open("res://data/stkilda/luna.json", FileAccess.WRITE)
	f.store_string(luna_text)
	f.close()
	print("stkilda_cut: slice ", box, ": ", out.buildings.size(), " buildings, ", out.roads.size(), " roads (of ",
			town.buildings.size(), ", ", town.roads.size(), ")")
	quit()

## The [x, z, ...] runs of `stride` numbers each, every x moved dx.
static func _east(v: Array, dx: float, stride: int) -> Array:
	var out := v.duplicate()
	for i in range(0, out.size() - 1, stride):
		out[i] = float(out[i]) + dx
	return out

## Whether a flat [x, z, x, z ...] outline's box touches the slice.
static func _touches(p: Array, box: Rect2) -> bool:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for i in range(0, p.size() - 1, 2):
		lo = lo.min(Vector2(p[i], p[i + 1]))
		hi = hi.max(Vector2(p[i], p[i + 1]))
	return Rect2(lo, hi - lo).intersects(box, true)

## A road's points from the one before it first comes within ROAD_PAST of the slice to the one after it last is
## ([] if it never comes near).
static func _trim(p: Array, box: Rect2) -> Array:
	var near := box.grow(ROAD_PAST)
	var first := -1
	var last := -1
	var n := p.size() / 2
	for i in n:
		if near.has_point(Vector2(p[i * 2], p[i * 2 + 1])):
			if first < 0:
				first = i
			last = i
	if first < 0:
		return p.duplicate() if _touches(p, box) else []
	first = maxi(0, first - 1)
	last = mini(n - 1, last + 1)
	return p.slice(first * 2, last * 2 + 2)

## The [x, z, ...] runs of `stride` numbers each whose spot is in the slice.
static func _flat(v: Array, stride: int, box: Rect2) -> Array:
	var out := []
	for i in range(0, v.size() - stride + 1, stride):
		if box.grow(10.0).has_point(Vector2(v[i], v[i + 1])):
			out.append_array(v.slice(i, i + stride))
	return out
