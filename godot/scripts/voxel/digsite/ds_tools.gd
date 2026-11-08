class_name DsTools
extends RefCounted
## The hand tools at the Dig Site (stage 3): the shovel, the pick and the hammer (VoxelTool; the hammer's DsHammer)
## dig its ground (DsTerrain) where you look, what comes up into the backpack, a block a block. Like the back yard's
## shovel, the tools come in tiers: the shovel's are the yard's (made at the tool bench), the pick's and the hammer's
## are made at the Dig Site's office (E at its counter) out of what you dig up. Hardness is the yard's scale
## (DsMats.HARD): the shovel takes soil (a golden one stone), the pick rock, a steel pick gems too; bedrock and the
## site's edge never. The hammer chips a block or two (it's for building supports: stage 8). Owned by the voxel session.

## The pick by tier: [radius (m), the hardest it breaks, seconds a swing, name] (tier 0 is the yard's pick)
const PICK := [[0.21, 4, 0.55, "Pick"], [0.27, 5, 0.42, "Steel pick"], [0.36, 5, 0.3, "Diamond pick"]]
## The hammer by tier: the same (a small chip; later, how quick it builds)
const HAMMER := [[0.08, 3, 0.4, "Hammer"], [0.1, 4, 0.3, "Framing hammer"], [0.12, 5, 0.2, "Nail gun"]]
## What the site office makes: the next pick or hammer, out of what the ground gives
const UPGRADES := [
	{"tool": "pick", "tier": 1, "name": "Steel pick", "cost": {"iron_ore": 20, "coal": 20, "stone": 60}, "desc": "breaks gems, bigger and quicker"},
	{"tool": "pick", "tier": 2, "name": "Diamond pick", "cost": {"gem": 6, "gold": 8, "iron_ore": 30}, "desc": "huge bites, very quick"},
	{"tool": "hammer", "tier": 1, "name": "Framing hammer", "cost": {"iron_ore": 10, "stone": 30}, "desc": "chips rock, builds quicker"},
	{"tool": "hammer", "tier": 2, "name": "Nail gun", "cost": {"iron_ore": 30, "coal": 10, "gold": 4}, "desc": "builds supports very quickly"},
]

var site: Node3D                # DigSite
var pick_tier := 0
var hammer_tier := 0

## The backpack's Dig Site things (VoxelItems merges these)
static func items() -> Dictionary:
	return {
		"sand": {"name": "Sand", "col": DsMats.COL[DsMats.SAND], "stack": 9999, "desc": "Dug at the Dig Site. Soft and dry."},
		"gravel": {"name": "Gravel", "col": DsMats.COL[DsMats.GRAVEL], "stack": 9999, "desc": "Little stones from the Dig Site."},
		"coal": {"name": "Coal", "col": Color8(40, 38, 42), "stack": 9999, "desc": "Black and dusty, from the Dig Site's stone. The site office wants it."},
		"iron_ore": {"name": "Iron ore", "col": DsMats.COL[DsMats.IRON], "stack": 9999, "desc": "Rusty rock from deep in the Dig Site. Picks and hammers are made of it."},
		"gem": {"name": "Gem", "col": DsMats.COL[DsMats.GEM], "stack": 999, "desc": "A glittering gem from right down at the Dig Site. Only a steel pick breaks it out."},
		"prop_wood": {"name": "Wooden prop", "col": DsMats.COL[DsMats.WOOD], "stack": 99, "desc": "Holds a tunnel's roof up (the hammer's right click). Not deep down: too much weight."},
		"dynamite": {"name": "Dynamite", "col": Color8(200, 30, 30), "stack": 50, "desc": "Light it, run (the Dynamite's left click at the Dig Site)."},
		"prop_concrete": {"name": "Concrete support", "col": DsMats.COL[DsMats.CONCRETE], "stack": 99, "desc": "Holds a roof up however deep (the hammer's right click)."},
	}

## The site office's shop: props, concrete, your ore bought (stage 8)
const PROPS := 5                # wooden props for ...
const PROPS_COST := 10          # ... this much cash
const CONCRETE := {"stone": 8, "sand": 4, "gravel": 4}
const PRICES := {"coal": 1, "iron_ore": 2, "gold": 5, "gem": 15}
const DYNAMITE := 3             # sticks for ...
const DYNAMITE_COST := 15

func shop_line() -> String:
	var a := arena()
	var c := []
	for id in CONCRETE:
		c.append("%d %s" % [int(CONCRETE[id]), VoxelItems.name_of(id).to_lower()])
	return "B  %d wooden props ($%d)     X  %d sticks of dynamite ($%d)     C  a concrete support (%s)     V  sell your ore ($%d; you've $%d)" % [PROPS, PROPS_COST, DYNAMITE, DYNAMITE_COST, ", ".join(c), ore_value(), a.cash]

func ore_value() -> int:
	var v := 0
	for id in PRICES:
		v += arena().inv.count(id) * int(PRICES[id])
	return v

func buy_props() -> bool:
	var a := arena()
	if a.cash < PROPS_COST:
		a.say("Not enough cash: $%d for %d props (V sells your ore)" % [PROPS_COST, PROPS], 2.0)
		return false
	a.cash -= PROPS_COST
	a.receive({"id": "prop_wood", "n": PROPS}, "inv")
	a.sound.play("item_pick", Vector3.INF, -4.0)
	a.say("%d wooden props in your backpack (%d)" % [PROPS, a.inv.count("prop_wood")], 2.0)
	a.stash._dirty = true
	return true

func buy_dynamite() -> bool:
	var a := arena()
	if a.cash < DYNAMITE_COST:
		a.say("Not enough cash: $%d for %d sticks (V sells your ore)" % [DYNAMITE_COST, DYNAMITE], 2.0)
		return false
	a.cash -= DYNAMITE_COST
	a.receive({"id": "dynamite", "n": DYNAMITE}, "inv")
	a.sound.play("item_pick", Vector3.INF, -4.0)
	a.say("%d sticks of dynamite (%d): press 4 for it" % [DYNAMITE, a.inv.count("dynamite")], 2.0)
	a.stash._dirty = true
	return true

func make_concrete() -> bool:
	var a := arena()
	for id in CONCRETE:
		if a.inv.count(id) < int(CONCRETE[id]):
			a.say("A concrete support needs %d %s (you've %d)" % [int(CONCRETE[id]), VoxelItems.name_of(id).to_lower(), a.inv.count(id)], 2.0)
			return false
	for id in CONCRETE:
		a.inv.remove(id, int(CONCRETE[id]))
	a.receive({"id": "prop_concrete", "n": 1}, "inv")
	a.sound.play("hammer_hit", Vector3.INF, -6.0)
	a.say("A concrete support (%d in your backpack)" % a.inv.count("prop_concrete"), 2.0)
	return true

func sell_ore() -> int:
	var a := arena()
	var v := 0
	for id in PRICES:
		var n: int = a.inv.count(id)
		if n > 0:
			a.inv.remove(id, n)
			v += n * int(PRICES[id])
	if v <= 0:
		a.say("No ore to sell (coal, iron ore, gold, gems)", 1.5)
		return 0
	a.cash += v
	a.sound.play("gold_find", Vector3.INF, -6.0)
	a.say("Sold your ore: +$%d ($%d)" % [v, a.cash], 2.0)
	a.stash._dirty = true
	return v

func _init(s: Node3D) -> void:
	site = s

func arena() -> Node3D:
	return site.arena

## The other game's tool bit: its dust and its sound shown here too
func hook(n: DsNet) -> void:
	n.register_event("fx", _fx_in)

func _fx_in(a: Array) -> void:
	if a.size() < 3 or not site.active:
		return
	var p: Vector3 = a[1]
	var m := int(a[2])
	var snd := String(a[0])
	site.arena.sound.play(snd, p, -4.0, randf_range(0.9, 1.1))
	if snd != "dig_clang":
		_dust_at(p, DsMats.COL[clampi(m, 0, DsMats.COL.size() - 1)])

func _dust_at(p: Vector3, col: Color) -> void:
	var tool = site.arena.melee.get("shovel")
	if tool:
		tool._dust(p, col)

## Blocks within r of p (no harder than hardest) dug out (through DsNet: a guest's goes to the host's too)
func dig_at(p: Vector3, r: float, hardest: int) -> Dictionary:
	var tr: DsTerrain = site.terrain
	var got = site.net.act("dig", [tr.to_cells(p), r / DsTerrain.CELL, hardest])
	return got if got is Dictionary else {"counts": PackedInt32Array(), "n": 0, "refused": 0}

## Up to most loose blocks of m put into the air within r of p (lowest first): how many
func fill_at(p: Vector3, r: float, m: int, most: int) -> int:
	var tr: DsTerrain = site.terrain
	var got = site.net.act("fill", [tr.to_cells(p), r / DsTerrain.CELL, m, most, true])
	return int(got) if got != null else 0

# ---------------------------------------------------------------- tiers

## A tool's stats at the Dig Site ([radius, hardest, seconds, name]), or [] (not one of these)
func stats(id: String) -> Array:
	match id:
		"pick":
			return PICK[clampi(pick_tier, 0, 2)]
		"hammer_ds":
			return HAMMER[clampi(hammer_tier, 0, 2)]
	return []

func set_tiers(p: int, h: int) -> void:
	pick_tier = clampi(p, 0, 2)
	hammer_tier = clampi(h, 0, 2)
	var m: Dictionary = arena().melee
	if m.has("pick"):
		m["pick"].set_tier(pick_tier)
	if m.has("hammer_ds"):
		m["hammer_ds"].set_tier(hammer_tier)

func save_data() -> Dictionary:
	return {"pick": pick_tier, "hammer": hammer_tier}

func load_data(d) -> void:
	if typeof(d) == TYPE_DICTIONARY:
		set_tiers(int(d.get("pick", 0)), int(d.get("hammer", 0)))

## The next thing the office makes for a tool (null: as good as it gets)
func next_upgrade(tool: String):
	var t := pick_tier if tool == "pick" else hammer_tier
	for u in UPGRADES:
		if u.tool == tool and int(u.tier) == t + 1:
			return u
	return null

## The office's next offer: the pick's first, then the hammer's (null: both as good as they get)
func offer():
	var u = next_upgrade("pick")
	return u if u != null else next_upgrade("hammer")

func _afford(u) -> bool:
	for id in u.cost:
		if arena().inv.count(id) < int(u.cost[id]):
			return false
	return true

## What the office counter says
func office_line() -> String:
	var u = offer()
	if u == null:
		return "Site office: your pick and hammer are as good as they get"
	var need := []
	for id in u.cost:
		need.append("%d %s (%d)" % [int(u.cost[id]), VoxelItems.name_of(id).to_lower(), arena().inv.count(id)])
	return ("E  make a %s: " % u.name if _afford(u) else "Site office: a %s needs " % u.name) + ", ".join(need)

## E at the office counter: the next tool made if the backpack has what it takes
func office_make() -> bool:
	var u = offer()
	var a := arena()
	if u == null:
		return false
	if not _afford(u):
		a.say("Not enough: " + office_line().trim_prefix("Site office: "), 2.5)
		return false
	for id in u.cost:
		a.inv.remove(id, int(u.cost[id]))
	if u.tool == "pick":
		set_tiers(int(u.tier), hammer_tier)
	else:
		set_tiers(pick_tier, int(u.tier))
	a.sound.play("hammer_hit", Vector3.INF, -6.0)
	a.say("Made: a %s (%s)" % [u.name, u.desc], 3.0)
	a.stash._dirty = true
	return true

# ---------------------------------------------------------------- the swing lands

## A tool (VoxelTool) bites the ground at p (normal n): dug blocks into the backpack, or (the shovel's right click,
## filling) dirt out of it put back. -> blocks moved
func bite(tool: Node3D, p: Vector3, n: Vector3, filling: bool) -> int:
	var a := arena()
	if not site.net.can_change():
		a.say("Waiting for your mate's ground ...", 1.0)
		return 0
	var st: Array = tool.stats()
	var r: float = st[0]
	if filling:
		var have: int = a.inv.count("dirt")
		if have <= 0:
			a.say("No dirt in your backpack to fill with", 1.5)
			return 0
		var k := fill_at(p + n * r * 0.6, r, DsMats.DIRT, have)
		if k > 0:
			a.inv.remove("dirt", k)
			tool.sfx("dig_dirt", p, -2.0, 0.85)
			tool._dust(p, DsMats.COL[DsMats.DIRT])
			site.net.event("fx", ["dig_dirt", p, DsMats.DIRT])
		return k
	if tool.weapon_id == "shovel" and tool.tier == 0 and randf() < 0.25:
		r *= 0.6                  # (the rusty one slips: half a scoop)
		tool.sfx("dig_scrape", p, -4.0)
	var got: Dictionary = dig_at(p - n * (r * 0.45 + 0.06), r, int(st[1]))     # (a little in: the smooth surface can sit half a block off the blocks)
	if VoxelBody.credit and a.get("guide"):
		a.guide.tried("dig")
	var counts: PackedInt32Array = got.counts
	if int(got.n) == 0:
		tool.sfx("dig_clang", p, -2.0)
		tool._dust(p, Color8(200, 200, 200))
		site.net.event("fx", ["dig_clang", p, 0])
		a.say(_too_hard(tool.weapon_id, int(got.refused), String(st[3])), 1.5)
		return 0
	var rock := 0
	var best := DsMats.DIRT
	var best_n := -1
	for m in counts.size():
		var c: int = counts[m]
		if c <= 0:
			continue
		if DsMats.HARD[m] >= 3:
			rock += c
		if c > best_n:
			best = m
			best_n = c
		var id: String = DsMats.ITEM[m] if m < DsMats.ITEM.size() else ""
		if id != "":
			a.receive({"id": id, "n": c}, "inv")
	var snd := "dig_stone" if rock * 2 > int(got.n) else "dig_dirt"
	tool.sfx(snd, p, -2.0, randf_range(0.9, 1.1))
	tool._dust(p, DsMats.COL[best])
	site.net.event("fx", [snd, p, best])
	for m in [DsMats.GEM, DsMats.GOLD, DsMats.IRON, DsMats.COAL]:
		if m < counts.size() and counts[m] > 0:
			var id: String = DsMats.ITEM[m]
			tool.sfx("gold_find" if m == DsMats.GEM or m == DsMats.GOLD else "item_pick", p, -2.0 if m >= DsMats.GOLD else -8.0)
			a.say("%s! (%d in your backpack)" % [VoxelItems.name_of(id), a.inv.count(id)], 2.0)
			break
	if int(got.refused) > 0 and int(got.n) < 4:
		a.say(_too_hard(tool.weapon_id, int(got.refused), String(st[3])), 1.5)
	return int(got.n)

func _too_hard(id: String, hard: int, tool_name: String) -> String:
	if hard >= 99:
		return "Nothing breaks that: it's bedrock (or the site's edge)"
	if id == "shovel":
		return "Too hard for the %s: the pick breaks rock" % tool_name.to_lower()
	if hard >= 5:
		return "Too hard for the %s: a steel pick breaks gems (the site office makes one)" % tool_name.to_lower()
	return "Too hard for the %s" % tool_name.to_lower()
