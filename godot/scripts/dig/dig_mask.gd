extends RefCounted
## Which of the depth grid's cells can be dug or ploughed: grass in the yard (calls.lobbyAreas 5 and 6), clear
## of the house and the deck, of every yard solid (the shed, garage, ute, tank, trampoline, fences, crop beds,
## compost, bush, junk...) and of the farm's things (the weed bed, the seed crate, its signs and gates) by
## D.MARGIN, and green in the yard picture (no digging the driveway, the paths or the vegetable patch).

const D := preload("res://scripts/dig/dig_data.gd")
const FD := preload("res://scripts/farm/farm_data.gd")

## The vegetable patch drawn in the yard picture (rows of plants, not a solid), HTML units.
const VEG_PATCH := Rect2(40, 960, 472, 525)

## d: GameData.data; img: the yard picture (YARD_IMG@1985) or null to skip the colour test.
static func build(d: Dictionary, img: Image) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(D.NX * D.NY)
	var areas: Array = d.get("calls", {}).get("lobbyAreas", [])
	if areas.size() < 7:
		return m
	var inside: Array = [_rect(areas[5]).grow(-D.MARGIN), _rect(areas[6]).grow(-D.MARGIN)]
	var outside: Array = []
	for i in 5:
		outside.append(_rect(areas[i]).grow(D.MARGIN))          # the house's rooms, doorways and the deck
	var circles: Array = []
	for s in d.get("YARD_SOLIDS", []):
		if s.has("r"):
			circles.append([Vector2(float(s.cx), float(s.cy)), float(s.r) + D.MARGIN])
		else:
			outside.append(Rect2(float(s.x0), float(s.y0), float(s.x1) - float(s.x0), float(s.y1) - float(s.y0)).grow(D.MARGIN))
	outside.append(VEG_PATCH)
	# the farm's: the weed bed's holes, the seed crate, the signs and gates, and the shed's tool rack
	var hx0 := INF
	var hy0 := INF
	var hx1 := -INF
	var hy1 := -INF
	for h in FD.YARD_HOLES:
		hx0 = minf(hx0, h[0])
		hy0 = minf(hy0, h[1])
		hx1 = maxf(hx1, h[0])
		hy1 = maxf(hy1, h[1])
	outside.append(Rect2(hx0, hy0, hx1 - hx0, hy1 - hy0).grow(70))
	var c: Dictionary = FD.CRATE
	outside.append(Rect2(c.x0, c.y0, c.x1 - c.x0, c.y1 - c.y0).grow(D.MARGIN + 8))
	for p in [FD.N_SIGN, FD.N_GATE, FD.P_SIGN, FD.P_GATE, D.RACK]:
		circles.append([Vector2(float(p.x), float(p.y)), 40.0])
	var Y: Dictionary = d.get("YARD", {"ox": -45, "oy": -50})
	var ox := float(Y.ox)
	var oy := float(Y.oy)
	for cy in D.NY:
		for cx in D.NX:
			var p := Vector2(D.X0 + (cx + 0.5) * D.CELL, D.Y0 + (cy + 0.5) * D.CELL)
			if not (inside[0].has_point(p) or inside[1].has_point(p)):
				continue
			var ok := true
			for r in outside:
				if r.has_point(p):
					ok = false
					break
			if ok:
				for cc in circles:
					if p.distance_to(cc[0]) < cc[1]:
						ok = false
						break
			if ok and img != null:
				var green := 0
				for o in [Vector2(0, 0), Vector2(-3, -3), Vector2(3, -3), Vector2(-3, 3), Vector2(3, 3)]:
					var px := int(p.x + o.x - ox)
					var py := int(p.y + o.y - oy)
					if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
						continue
					if is_grass(img.get_pixel(px, py)):
						green += 1
				ok = green >= 4
			if ok:
				m[cy * D.NX + cx] = 1
	return m

## A grass colour in the yard picture: green well over red and blue.
static func is_grass(c: Color) -> bool:
	return c.g > c.r + 0.06 and c.g > c.b + 0.08 and c.g < 0.85

static func _rect(a: Dictionary) -> Rect2:
	return Rect2(float(a.x0), float(a.y0), float(a.x1) - float(a.x0), float(a.y1) - float(a.y0))
