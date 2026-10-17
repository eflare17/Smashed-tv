class_name FarmState
extends RefCounted
## The farm's state and rules, with no nodes: the plots and what's growing in them, what each player carries
## (seeds, buds, fertiliser bags, the watering can), the land and upgrades bought, the breeding table, the active
## buff. The Farm node drives it from the GameClock and the player's E; the headless tests drive it directly.
## Money is the Farm's (the shared wallet): the buy and sell functions here are told it's been paid, or say what
## it comes to.
##
## The HTML game's b332 weed bed is the model (farmAction, farmStep, farmWave): a plot holds one plant; it grows
## at full speed watered and half speed dry; left dry too long it wilts and loses a bud (once); ready, E harvests
## its buds; the garage buys every bud. Fertiliser, raids, breeding, smoking and the land stages are FARM.md's.

const D := preload("res://scripts/farm/farm_data.gd")

signal changed
## Time passed (grow): emitted every time; `changed` only when something you'd see changed (a stage, dry or
## wilted, ready, the breeding table), so the panel isn't rebuilt every frame.
signal grew

## Every plot: {zone ("yard", "neighbour", "paddock"), row (paddock row, else -1), x, y (HTML units), s (strain,
## -1 empty), g (0..1 grown), wet (game hours of water left), dry (hours dry), wilt (0/1), fert (0 none, 1-3),
## frosty (bool)}.
var plots: Array = []
## What each player carries, by player id (0 the host, 1 the guest): see _fresh_inv().
var inv: Dictionary = {}
var land := {"neighbour": false, "paddock": false}
var upgrades := {"compost": false, "sprinkler": false, "lights": false, "tractor": false}
var compost_count := 0           # harvests since the last bag
var compost_bags := 0            # free Basic bags waiting in the bin
## The breeding table: {} or {s, frosty, hours, waiting (true until a wave or BREED_HOURS)}.
var breeding: Dictionary = {}
## The buff from the last thing smoked: {} or {strain, name, waves, potent, ...the buff fields (FarmData.BUFF_NEUTRAL)}.
var buff: Dictionary = {}
## Totals, for the panel and tests.
var stats := {"harvests": 0, "sold": 0, "raided": 0, "smoked": 0}
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()
	reset()

func reset() -> void:
	plots.clear()
	for h in D.YARD_HOLES:
		plots.append(_plot("yard", -1, h[0], h[1]))
	for r in D.N_PLOT_ROWS:
		for c in D.N_PLOT_COLS:
			plots.append(_plot("neighbour", -1, D.N_PLOT_ORIGIN.x + c * D.N_PLOT_STEP.x, D.N_PLOT_ORIGIN.y + r * D.N_PLOT_STEP.y))
	for r in D.P_ROWS:
		for k in D.P_ROW_PLANTS:
			plots.append(_plot("paddock", r, D.P_ROW_X0 + k * D.P_ROW_DX, D.P_ROW_Y0 + r * D.P_ROW_DY))
	inv = {0: _fresh_inv(), 1: _fresh_inv()}
	land = {"neighbour": false, "paddock": false}
	upgrades = {"compost": false, "sprinkler": false, "lights": false, "tractor": false}
	compost_count = 0
	compost_bags = 0
	breeding = {}
	buff = {}
	stats = {"harvests": 0, "sold": 0, "raided": 0, "smoked": 0}

func _plot(zone: String, row: int, x: float, y: float) -> Dictionary:
	return {"zone": zone, "row": row, "x": x, "y": y, "s": -1, "g": 0.0, "wet": 0.0, "dry": 0.0, "wilt": 0, "fert": 0, "frosty": false}

## seeds[s], frosty[s] (frosty seeds), buds[s][q] (q: bit 1 potent, bit 2 frosty), ferts[f] (bags, 1-3), can
## (waterings left in the can, 0 not holding it), pick (the seed E plants), fert_pick (the bag E uses).
func _fresh_inv() -> Dictionary:
	var buds := []
	for s in D.STRAINS.size():
		buds.append([0, 0, 0, 0])
	return {"seeds": _zeros(D.STRAINS.size()), "frosty": _zeros(D.STRAINS.size()), "buds": buds,
		"ferts": [0, 0, 0, 0], "can": 0, "pick": 0, "fert_pick": 1}

static func _zeros(n: int) -> Array:
	var a := []
	a.resize(n)
	a.fill(0)
	return a

func inv_of(pid: int) -> Dictionary:
	if not inv.has(pid):
		inv[pid] = _fresh_inv()
	return inv[pid]

## ---------------------------------------------------------------- reading

func plot_open(i: int) -> bool:
	var p: Dictionary = plots[i]
	return p.zone == "yard" or bool(land.get(p.zone, false))

func stage(i: int) -> int:
	var p: Dictionary = plots[i]
	return -1 if p.s < 0 else D.stage_of(p.g)

## 0 healthy, 1 dry (droops, wants water), 2 wilted (dry and lost a bud).
func look(i: int) -> int:
	var p: Dictionary = plots[i]
	if p.s < 0 or p.g >= 1.0 or p.wet > 0.0:
		return 0
	return 1 + int(p.wilt)

func watered(i: int) -> bool:
	var p: Dictionary = plots[i]
	return p.wet > 0.0 or _sprinkled(p)

func _sprinkled(p: Dictionary) -> bool:
	return p.zone == "neighbour" and bool(upgrades.sprinkler)

## The plant's grow speed now (a fraction of its whole growth a game hour).
func speed(p: Dictionary) -> float:
	if p.s < 0:
		return 0.0
	var st := D.strain(p.s)
	var k := 1.0
	if p.fert > 0:
		k += float(D.FERTS[p.fert].speed)
	if p.zone == "neighbour" and upgrades.lights:
		k += D.LIGHTS_SPEED
	return k / float(st.hours)

## How many buds it gives harvested now.
func buds_of(p: Dictionary) -> int:
	if p.s < 0:
		return 0
	var n: int = int(D.strain(p.s).buds) - int(p.wilt)
	if p.fert > 0:
		n += int(D.FERTS[p.fert].buds)
	return maxi(1, n)

## Hours of growing left at full speed watered (for the hints).
func hours_left(p: Dictionary) -> float:
	var sp := speed(p)
	return 0.0 if sp <= 0.0 else (1.0 - p.g) / sp

func seed_count(pid: int) -> int:
	var v := inv_of(pid)
	var n := 0
	for s in D.STRAINS.size():
		n += int(v.seeds[s]) + int(v.frosty[s])
	return n

func bud_count(pid: int, s: int = -1) -> int:
	var v := inv_of(pid)
	var n := 0
	for k in D.STRAINS.size():
		if s < 0 or s == k:
			for q in 4:
				n += int(v.buds[k][q])
	return n

func fert_count(pid: int) -> int:
	var v := inv_of(pid)
	return int(v.ferts[1]) + int(v.ferts[2]) + int(v.ferts[3])

## What every bud you carry sells for (prices: an optional {strain: multiplier} from a market day).
func bud_value(pid: int, prices: Dictionary = {}, s_only: int = -1) -> int:
	var v := inv_of(pid)
	var total := 0.0
	for s in D.STRAINS.size():
		if s_only >= 0 and s != s_only:
			continue
		var m := float(prices.get(s, 1.0))
		for q in 4:
			total += float(v.buds[s][q]) * D.bud_price(s, q) * m
	return int(round(total))

## The seed E would plant: the kind picked (bought or chosen last), or else any you have; -1 none.
## Frosty seeds of a kind go first.
func seed_pick(pid: int) -> int:
	var v := inv_of(pid)
	var s: int = v.pick
	if s >= 0 and s < D.STRAINS.size() and int(v.seeds[s]) + int(v.frosty[s]) > 0:
		return s
	for k in D.STRAINS.size():
		if int(v.seeds[k]) + int(v.frosty[k]) > 0:
			return k
	return -1

## The bag E would use: the picked one, or else any; 0 none.
func fert_pick(pid: int) -> int:
	var v := inv_of(pid)
	var f: int = v.fert_pick
	if f >= 1 and f <= 3 and int(v.ferts[f]) > 0:
		return f
	for k in [1, 2, 3]:
		if int(v.ferts[k]) > 0:
			return k
	return 0

## ---------------------------------------------------------------- what E does at a plot

## The label E shows at plot i for player pid ("" nothing), like farmLabel. Order: plant an empty one; harvest a
## ready one; water a thirsty one (if you hold water); fertilise one with none (if you carry a bag).
func plot_label(i: int, pid: int) -> String:
	if not plot_open(i):
		return ""
	var p: Dictionary = plots[i]
	var v := inv_of(pid)
	if p.s < 0:
		var s := seed_pick(pid)
		return ("PLANT " + D.STRAINS[s].short) if s >= 0 else ""
	if p.g >= 1.0:
		return "HARVEST"
	if int(v.can) > 0 and not _sprinkled(p) and p.wet < D.WET_HOURS - 0.33:
		return "WATER"
	if p.fert == 0:
		var f := fert_pick(pid)
		if f > 0:
			return "FERTILISE " + D.FERTS[f].short
	return ""

## Do what plot_label says. Returns a short line for a floater ("" nothing done).
func plot_act(i: int, pid: int) -> String:
	var l := plot_label(i, pid)
	if l.begins_with("PLANT"):
		return plant(i, pid, seed_pick(pid))
	if l == "HARVEST":
		return harvest(i, pid)
	if l == "WATER":
		return water(i, pid)
	if l.begins_with("FERTILISE"):
		return fertilise(i, pid, fert_pick(pid))
	return ""

func plant(i: int, pid: int, s: int) -> String:
	var p: Dictionary = plots[i]
	var v := inv_of(pid)
	if p.s >= 0 or s < 0 or int(v.seeds[s]) + int(v.frosty[s]) <= 0:
		return ""
	var frosty := int(v.frosty[s]) > 0
	if frosty:
		v.frosty[s] -= 1
	else:
		v.seeds[s] -= 1
	p.s = s
	p.g = 0.0
	p.wet = 0.0
	p.dry = 0.0
	p.wilt = 0
	p.fert = 0
	p.frosty = frosty
	changed.emit()
	return "PLANTED " + D.STRAINS[s].short + (" (FROSTY)" if frosty else "")

func harvest(i: int, pid: int) -> String:
	var p: Dictionary = plots[i]
	if p.s < 0 or p.g < 1.0:
		return ""
	var v := inv_of(pid)
	var n := buds_of(p)
	var q := (1 if p.fert == 3 else 0) | (2 if p.frosty else 0)
	v.buds[p.s][q] += n
	var name: String = D.STRAINS[p.s].short
	_clear(p)
	stats.harvests += 1
	if upgrades.compost:
		compost_count += 1
		if compost_count >= D.COMPOST_PER_BAG:
			compost_count = 0
			compost_bags += 1
	changed.emit()
	return "+%d %s BUDS" % [n, name]

func water(i: int, pid: int) -> String:
	var p: Dictionary = plots[i]
	var v := inv_of(pid)
	if p.s < 0 or int(v.can) <= 0:
		return ""
	p.wet = D.WET_HOURS
	p.dry = 0.0
	v.can -= 1
	changed.emit()
	return "WATERED"

func fertilise(i: int, pid: int, f: int) -> String:
	var p: Dictionary = plots[i]
	var v := inv_of(pid)
	if p.s < 0 or p.g >= 1.0 or p.fert != 0 or f < 1 or f > 3 or int(v.ferts[f]) <= 0:
		return ""
	v.ferts[f] -= 1
	p.fert = f
	changed.emit()
	return D.FERTS[f].short + " FERTILISER"

func _clear(p: Dictionary) -> void:
	p.s = -1
	p.g = 0.0
	p.wet = 0.0
	p.dry = 0.0
	p.wilt = 0
	p.fert = 0
	p.frosty = false

## ---------------------------------------------------------------- the paddock's rows (the tractor does a whole row)

func row_plots(r: int) -> Array:
	var out := []
	for i in plots.size():
		if plots[i].zone == "paddock" and plots[i].row == r:
			out.append(i)
	return out

## What the tractor does at row r: "PLANT ROW NL", "HARVEST ROW", "WATER ROW", "FERTILISE ROW", or "" / "NEED TRACTOR".
func row_label(r: int, pid: int) -> String:
	if not land.paddock:
		return ""
	if not upgrades.tractor:
		return "NEED TRACTOR"
	var idx := row_plots(r)
	var empty := 0
	var ready := 0
	var thirsty := 0
	var unfed := 0
	for i in idx:
		var p: Dictionary = plots[i]
		if p.s < 0:
			empty += 1
		elif p.g >= 1.0:
			ready += 1
		else:
			if p.wet < D.WET_HOURS - 0.33:
				thirsty += 1
			if p.fert == 0:
				unfed += 1
	if ready > 0:
		return "HARVEST ROW"
	if empty > 0 and seed_pick(pid) >= 0:
		return "PLANT ROW " + D.STRAINS[seed_pick(pid)].short
	if thirsty > 0:
		return "WATER ROW"
	if unfed > 0 and fert_pick(pid) > 0:
		return "FERTILISE ROW"
	return ""

func row_act(r: int, pid: int) -> String:
	var l := row_label(r, pid)
	var idx := row_plots(r)
	var n := 0
	if l == "HARVEST ROW":
		var buds := 0
		for i in idx:
			if plots[i].s >= 0 and plots[i].g >= 1.0:
				buds += buds_of(plots[i])
				harvest(i, pid)
				n += 1
		return "+%d BUDS (%d PLANTS)" % [buds, n] if n else ""
	if l.begins_with("PLANT ROW"):
		for i in idx:
			var s := seed_pick(pid)
			if s < 0:
				break
			if plots[i].s < 0:
				plant(i, pid, s)
				n += 1
		return "PLANTED %d" % n if n else ""
	if l == "WATER ROW":
		for i in idx:
			var p: Dictionary = plots[i]
			if p.s >= 0 and p.g < 1.0:
				p.wet = D.WET_HOURS       # the tractor's tank: free
				p.dry = 0.0
				n += 1
		changed.emit()
		return "WATERED %d" % n
	if l == "FERTILISE ROW":
		for i in idx:
			var f := fert_pick(pid)
			if f <= 0:
				break
			if fertilise(i, pid, f) != "":
				n += 1
		return "FERTILISED %d" % n if n else ""
	return ""

## ---------------------------------------------------------------- growing

## Game time passing: every plant grows (farmStep, in game hours). Watered, at full speed while its water lasts;
## then dry, at half speed, and after DRY_WILT_HOURS dry it wilts. Ready plants wait. Also ticks the breeding table.
func grow(hours: float) -> void:
	if hours <= 0.0:
		return
	var before := _look_sig()
	for p in plots:
		if p.s < 0 or p.g >= 1.0:
			continue
		if p.zone != "yard" and not land.get(p.zone, false):
			continue
		var left := hours
		var sp := speed(p)
		var guard := 0
		while left > 1e-6 and p.g < 1.0 and guard < 8:
			guard += 1
			if _sprinkled(p):
				p.wet = D.WET_HOURS
				p.g = minf(1.0, p.g + sp * left)
				left = 0.0
			elif p.wet > 0.0:
				var step := minf(left, p.wet)
				p.g = minf(1.0, p.g + sp * step)
				p.wet -= step
				left -= step
				if p.wet <= 1e-6:
					p.wet = 0.0
			else:
				p.g = minf(1.0, p.g + sp * D.DRY_SPEED * left)
				p.dry += left
				if not p.wilt and p.dry >= D.DRY_WILT_HOURS:
					p.wilt = 1
				left = 0.0
		if p.g >= 0.9999:                       # (rounding: a plant due now is ready now)
			p.g = 1.0
			p.wet = 0.0
	if not breeding.is_empty() and breeding.waiting:
		breeding.hours -= hours
		if breeding.hours <= 0.0:
			breeding.waiting = false
	grew.emit()
	if _look_sig() != before:
		changed.emit()

## What the plots and the table look like (stage, look, watered), to tell whether time passing changed anything.
func _look_sig() -> String:
	var a := PackedStringArray()
	for i in plots.size():
		var p: Dictionary = plots[i]
		if p.s >= 0:
			a.append("%d:%d%d%d" % [i, stage(i), look(i), 1 if watered(i) else 0])
	a.append(str(breeding.get("waiting", "")))
	return ",".join(a)

## A wave survived: the buff counts down (time itself moves on through the GameClock), and a seed on the
## breeding table is ready.
func wave_survived() -> void:
	if not buff.is_empty():
		buff.waves -= 1
		if buff.waves <= 0:
			buff = {}
	if not breeding.is_empty():
		breeding.waiting = false
	changed.emit()

## ---------------------------------------------------------------- the can, buying, selling

func fill_can(pid: int) -> void:
	inv_of(pid).can = D.CAN_SIZE
	changed.emit()

func drop_can(pid: int) -> void:
	inv_of(pid).can = 0
	changed.emit()

func add_seed(pid: int, s: int, n: int = 1, frosty: bool = false) -> void:
	var v := inv_of(pid)
	if frosty:
		v.frosty[s] += n
	else:
		v.seeds[s] += n
	v.pick = s
	changed.emit()

func add_fert(pid: int, f: int, n: int = 1) -> void:
	var v := inv_of(pid)
	v.ferts[f] += n
	v.fert_pick = f
	changed.emit()

## Take every bud of strain s (all strains: -1) out of pid's bag; returns what they're worth.
func take_buds(pid: int, s_only: int = -1, prices: Dictionary = {}) -> int:
	var value := bud_value(pid, prices, s_only)
	var v := inv_of(pid)
	for s in D.STRAINS.size():
		if s_only < 0 or s == s_only:
			v.buds[s] = [0, 0, 0, 0]
	stats.sold += value
	changed.emit()
	return value

## ---------------------------------------------------------------- smoking

## Smoke one bud of strain s from pid's bag (the plainest one first): its buff replaces the one going, and
## lasts its buff waves (a potent bud one more). Returns the buff ({} if there was no bud).
func smoke(pid: int, s: int) -> Dictionary:
	var v := inv_of(pid)
	if s < 0 or s >= D.STRAINS.size():
		return {}
	var q := -1
	for k in [0, 2, 1, 3]:
		if int(v.buds[s][k]) > 0:
			q = k
			break
	if q < 0:
		return {}
	v.buds[s][q] -= 1
	var st := D.strain(s)
	var b: Dictionary = D.BUFF_NEUTRAL.duplicate()
	for k in st.buff:
		b[k] = st.buff[k]
	b["strain"] = s
	b["name"] = st.name
	b["potent"] = bool(q & 1)
	b["waves"] = int(st.buff_waves) + (D.POTENT_BUFF_WAVES if q & 1 else 0)
	buff = b
	stats.smoked += 1
	changed.emit()
	return b

## ---------------------------------------------------------------- raids

## Roll this wave's raid: each planted plant (growing or ready) is targeted with its strain's risk.
## Returns the targeted plot indices (empty: no raid).
func raid_roll() -> Array:
	var targets := []
	for i in plots.size():
		var p: Dictionary = plots[i]
		if p.s < 0 or not plot_open(i):
			continue
		if rng.randf() < D.RAID_RISK[int(D.strain(p.s).risk)]:
			targets.append(i)
	return targets

## Raiders got away with these plants: they're gone.
func raid_lose(targets: Array) -> Array:
	var lost := []
	for i in targets:
		if i >= 0 and i < plots.size() and plots[i].s >= 0:
			lost.append(D.STRAINS[plots[i].s].short)
			_clear(plots[i])
			stats.raided += 1
	changed.emit()
	return lost

## A raider dropped a seed: a strain of the raided ones' tier or one higher (rarer strains raid more, and drop
## better). Returns the strain.
func raider_seed(target_strains: Array) -> int:
	var tier := 0
	for s in target_strains:
		tier = maxi(tier, int(D.strain(s).tier))
	if rng.randf() < 0.35:
		tier = mini(3, tier + 1)
	var pool := []
	for s in D.STRAINS.size():
		if int(D.STRAINS[s].tier) == tier:
			pool.append(s)
	return pool[rng.randi() % pool.size()] if pool.size() else 0

## ---------------------------------------------------------------- breeding

## Cross two seeds pid has (recipe in FarmData.RECIPES). Returns the strain it'll make, or -1.
func breed(pid: int, a: int, b: int) -> int:
	if not breeding.is_empty():
		return -1
	var out := D.recipe_for(a, b)
	if out < 0:
		return -1
	var v := inv_of(pid)
	var need := {}
	need[a] = int(need.get(a, 0)) + 1
	need[b] = int(need.get(b, 0)) + 1
	for s in need:
		if int(v.seeds[s]) + int(v.frosty[s]) < int(need[s]):
			return -1
	for s in [a, b]:
		if int(v.seeds[s]) > 0:
			v.seeds[s] -= 1
		else:
			v.frosty[s] -= 1
	var frosty := false
	if rng.randf() < D.BREED_LUCKY:
		if rng.randf() < 0.5 and int(D.strain(out).tier) < 3:
			var nt := int(D.strain(out).tier) + 1
			for s in D.STRAINS.size():
				if int(D.STRAINS[s].tier) == nt:
					out = s
					break
		else:
			frosty = true
	breeding = {"s": out, "frosty": frosty, "hours": D.BREED_HOURS, "waiting": true}
	changed.emit()
	return out

## Take the bred seed off the table (once it's ready). Returns its strain, or -1.
func breed_collect(pid: int) -> int:
	if breeding.is_empty() or breeding.waiting:
		return -1
	var s: int = breeding.s
	add_seed(pid, s, 1, bool(breeding.frosty))
	breeding = {}
	changed.emit()
	return s

## ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var ps := []
	for p in plots:
		ps.append([p.s, snappedf(p.g, 0.0001), snappedf(p.wet, 0.001), snappedf(p.dry, 0.001), p.wilt, p.fert, 1 if p.frosty else 0])
	var iv := {}
	for k in inv:
		iv[str(k)] = inv[k].duplicate(true)
	return {"v": 2, "plots": ps, "inv": iv, "land": land.duplicate(), "upgrades": upgrades.duplicate(),
		"compost": [compost_count, compost_bags], "breeding": breeding.duplicate(), "buff": buff.duplicate(),
		"stats": stats.duplicate()}

func from_dict(d: Dictionary) -> void:
	reset()
	if int(d.get("v", 0)) != 2:
		return
	var ps: Array = d.get("plots", [])
	for i in mini(ps.size(), plots.size()):
		var a = ps[i]
		if not (a is Array) or a.size() < 7:
			continue
		var s := int(a[0])
		if s < 0 or s >= D.STRAINS.size():
			continue
		var p: Dictionary = plots[i]
		p.s = s
		p.g = clampf(float(a[1]), 0.0, 1.0)
		p.wet = maxf(0.0, float(a[2]))
		p.dry = maxf(0.0, float(a[3]))
		p.wilt = 1 if int(a[4]) else 0
		p.fert = clampi(int(a[5]), 0, 3)
		p.frosty = int(a[6]) != 0
	var iv: Dictionary = d.get("inv", {})
	for k in iv:
		var src: Dictionary = iv[k]
		var v := _fresh_inv()
		for s in D.STRAINS.size():
			v.seeds[s] = maxi(0, int(_at(src.get("seeds", []), s)))
			v.frosty[s] = maxi(0, int(_at(src.get("frosty", []), s)))
			var bq = _at(src.get("buds", []), s)
			for q in 4:
				v.buds[s][q] = maxi(0, int(_at(bq if bq is Array else [], q)))
		for f in 4:
			v.ferts[f] = maxi(0, int(_at(src.get("ferts", []), f)))
		v.can = clampi(int(src.get("can", 0)), 0, D.CAN_SIZE)
		v.pick = clampi(int(src.get("pick", 0)), 0, D.STRAINS.size() - 1)
		v.fert_pick = clampi(int(src.get("fert_pick", 1)), 1, 3)
		inv[int(k)] = v
	var l: Dictionary = d.get("land", {})
	for k in land:
		land[k] = bool(l.get(k, false))
	var u: Dictionary = d.get("upgrades", {})
	for k in upgrades:
		upgrades[k] = bool(u.get(k, false))
	var c: Array = d.get("compost", [0, 0])
	compost_count = int(_at(c, 0))
	compost_bags = int(_at(c, 1))
	var b: Dictionary = d.get("breeding", {})
	if b.has("s") and int(b.s) >= 0 and int(b.s) < D.STRAINS.size():
		breeding = {"s": int(b.s), "frosty": bool(b.get("frosty", false)), "hours": float(b.get("hours", 0.0)), "waiting": bool(b.get("waiting", false))}
	var bf: Dictionary = d.get("buff", {})
	if bf.has("strain") and int(bf.get("waves", 0)) > 0:
		buff = bf.duplicate()
		buff.strain = int(buff.strain)
		buff.waves = int(buff.waves)
		for k in D.BUFF_NEUTRAL:                # JSON gives every number back as a float
			buff[k] = type_convert(buff.get(k, D.BUFF_NEUTRAL[k]), typeof(D.BUFF_NEUTRAL[k]))
	var st: Dictionary = d.get("stats", {})
	for k in stats:
		stats[k] = int(st.get(k, 0))
	changed.emit()

static func _at(a, i: int):
	return a[i] if a is Array and i < a.size() else 0
