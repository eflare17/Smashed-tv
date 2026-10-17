class_name Farm
extends Node
## The farm (FARM.md), running on the GameClock. One per game; FarmInstall makes it (as main's child "Farm", in
## group "farm"; also Farm.instance). It owns the FarmState, grows it with game time, saves it, talks to the
## wallet, and is what every farm Interactable asks (spot_label / spot_act) and what the panel calls.
##
## Hooks for the other parts (see integration/farm.md):
## - Fighting: on_wave_started(wave) -> raid {} or {targets, raiders, strains}; raid_result(escaped);
##   raider_killed() -> dropped seed's strain or -1; on_wave_survived(wave) (moves the clock on WAVE_HOURS, counts
##   the buff down, readies a bred seed, and if the fighting didn't run a raid this wave rolls one itself).
##   The buff: buff_changed(buff) / active_buff() / buff_value(key) (FarmData.BUFF_NEUTRAL's keys).
## - Lobby: smoke(player_or_pid, strain) for the bong; buds_of(pid) for what to offer.
## - Money / trading: the wallet (get_cash, add_cash, spend_cash), sold(pid, amount) and market prices
##   (set_market_prices({strain: multiplier}), e.g. on GameClock.day_started).

const D := preload("res://scripts/farm/farm_data.gd")
const GD := preload("res://scripts/game_data.gd")
const SAVE_KEY := "smashed-godot-farm"
const SAVE_PATH := "user://smashed-farm.json"

static var instance: Farm

signal changed
## Something to say over a player's head (floaters): text, colour, HTML ground position.
signal floater(text: String, colour: Color, at: Vector2)
## The active buff changed: the buff ({} when it's worn off). Fields: FarmData.BUFF_NEUTRAL's plus strain, name,
## waves (left), potent.
signal buff_changed(buff: Dictionary)
signal smoked(pid: int, strain: int, buff: Dictionary)
## A raid this wave: {targets: [plot indices], raiders: n, strains: [strain per target]}.
signal raid_started(raid: Dictionary)
## A raid's end: {lost: [short names], defended: bool}.
signal raid_resolved(info: Dictionary)
signal sold(pid: int, amount: int)
signal seed_dropped(strain: int)
## A farm sound to play ("plant", "snip", "water", "fill", "seed", "cash", "smoke": assets/farm/snd_<name>.wav).
signal sound(name: String)
## The panel should open ("bag", "shop", "sell", "land", "breed") for this player.
signal panel_wanted(context: String, pid: int)

var state := FarmState.new()
var clock: Node
var wallet: Node
## The game (main): the player, the rig. Optional (the logic tests run without).
var main: Node
## Raid by itself on a wave survived when the fighting didn't start one (until the fighting session drives raids).
var auto_raids := true
## Market day price multipliers by strain (the trading game sets them).
var price_mults: Dictionary = {}
## Save to disk / localStorage (off in tests).
var persist := true

var _last_hour := -1.0            # the clock's hour at the last look (-1: not looked yet)
var _last_day := 0
var _dirty := false
var _save_t := 0.0
var _raid: Dictionary = {}          # this wave's raid, while the fighting runs it
var _raid_wave_started := false

func _enter_tree() -> void:
	instance = self
	add_to_group("farm")

func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _dirty:
		save()

func _ready() -> void:
	state.changed.connect(_on_state_changed)
	state.grew.connect(func(): _dirty = true)
	if clock == null:
		clock = get_node_or_null("/root/GameClock")
	if wallet == null:
		wallet = get_node_or_null("/root/Wallet")
	if wallet and wallet.has_signal("cash_changed"):
		# the wallet saves itself a second after a change: save the farm's side of a purchase soon too
		wallet.cash_changed.connect(_on_wallet_changed)
	if persist:
		load_save()
	_clock_reset()

func _on_wallet_changed(_c: int) -> void:
	if _dirty:
		_save_t = maxf(_save_t, 9.0)

func _on_state_changed() -> void:
	_dirty = true
	changed.emit()

func _process(delta: float) -> void:
	sync_clock()
	if persist and _dirty:
		_save_t += delta
		if _save_t > 10.0:
			save()

## Grow by however much game time has passed on the clock since the last look (ticking, advance_hours and
## sleep_to_morning all count the same way). The hour wraps at midnight while the day number may turn at 7 am,
## so it's the hour's step forward (mod 24) that counts, plus whole days if the day jumped more than one.
func sync_clock() -> void:
	if clock == null or not is_instance_valid(clock):
		return
	var day := int(clock.get("day"))
	var hour := float(clock.get("hour"))
	if _last_hour < 0.0:
		_last_day = day
		_last_hour = hour
		return
	var d := fposmod(hour - _last_hour, 24.0)
	if day - _last_day >= 2:
		d += 24.0 * (day - _last_day - 1)
	_last_day = day
	_last_hour = hour
	if d > 0.0 and d < 24.0 * 30.0:
		state.grow(d)

## Forget where the clock was (after loading, or when the clock is swapped): the next look starts from now.
func _clock_reset() -> void:
	_last_hour = -1.0
	sync_clock()

## ---------------------------------------------------------------- money

func cash() -> int:
	return int(wallet.get_cash()) if wallet and wallet.has_method("get_cash") else 0

func spend(n: int, why: String) -> bool:
	if n <= 0:
		return true
	return wallet != null and wallet.has_method("spend_cash") and bool(wallet.spend_cash(n, why))

func earn(n: int, why: String) -> void:
	if wallet and wallet.has_method("add_cash") and n > 0:
		wallet.add_cash(n, why)

## ---------------------------------------------------------------- players

## Which inventory a player uses: 0 the host; a guest player node carries "farm_pid" 1 (meta or property).
static func pid_of(p) -> int:
	if p is int:
		return p
	if p is Object and p != null:
		if p.has_meta("farm_pid"):
			return int(p.get_meta("farm_pid"))
		var v = p.get("farm_pid")
		if v != null:
			return int(v)
	return 0

static func html_xy(p) -> Vector2:
	if p is Node3D:
		var h := GD.from_3d(p.global_position)
		return Vector2(h.x, h.y)
	return Vector2.ZERO

func say(text: String, at: Vector2, col: Color = Color("#9fe07a")) -> void:
	floater.emit(text, col, at)

## ---------------------------------------------------------------- the spots (Interactables ask these)

func spot_label(spot: Node, p) -> String:
	var pid := pid_of(p)
	var k: String = spot.kind
	var i: int = spot.idx
	match k:
		"plot":
			return state.plot_label(i, pid)
		"row":
			return state.row_label(i, pid)
		"tank":
			return "FILL CAN" if int(state.inv_of(pid).can) < D.CAN_SIZE else "LEAVE CAN"
		"crate":
			return "SHOP"
		"sell":
			return ("SELL $%d" % state.bud_value(pid, price_mults)) if state.bud_count(pid) > 0 else ""
		"compost":
			if not state.upgrades.compost:
				return "COMPOST BIN $%d" % D.UPGRADES.compost.price
			return ("TAKE %d BASIC" % state.compost_bags) if state.compost_bags > 0 else ""
		"sign_neighbour":
			return "" if state.land.neighbour else "FOR SALE $%d" % D.LAND_PRICES.neighbour
		"sign_paddock":
			return "" if state.land.paddock else "FOR SALE $%d" % D.LAND_PRICES.paddock
		"gate_neighbour":
			return "GATE" if state.land.neighbour else ""
		"gate_paddock":
			return "GATE" if state.land.paddock else ""
		"breed":
			if not state.land.neighbour:
				return ""
			if not state.breeding.is_empty():
				return "" if state.breeding.waiting else "TAKE SEED"
			return "BREED"
		"shed":
			return "UPGRADES"
	return ""

func spot_act(spot: Node, p) -> void:
	var pid := pid_of(p)
	var at := html_xy(p)
	var l := spot_label(spot, p)
	if l == "":
		return
	var k: String = spot.kind
	var i: int = spot.idx
	match k:
		"plot":
			var r := state.plot_act(i, pid)
			if r != "":
				say(r, at, Color("#8fd3ff") if r == "WATERED" else Color("#9fe07a"))
				sound.emit("plant" if l.begins_with("PLANT") else ("snip" if l == "HARVEST" else ("water" if l == "WATER" else "plant")))
		"row":
			if l == "NEED TRACTOR":
				panel_wanted.emit("land", pid)
				return
			var r := state.row_act(i, pid)
			if r != "":
				say(r, at)
				sound.emit("snip" if l == "HARVEST ROW" else ("water" if l == "WATER ROW" else "plant"))
		"tank":
			if l == "FILL CAN":
				state.fill_can(pid)
				say("CAN FULL", at, Color("#8fd3ff"))
				sound.emit("fill")
			else:
				state.drop_can(pid)
		"crate":
			panel_wanted.emit("shop", pid)
		"sell":
			panel_wanted.emit("sell", pid)
		"compost":
			if not state.upgrades.compost:
				panel_wanted.emit("land", pid)
			else:
				var n := state.compost_bags
				state.compost_bags = 0
				state.add_fert(pid, 1, n)
				say("+%d BASIC" % n, at)
		"sign_neighbour", "sign_paddock", "shed":
			panel_wanted.emit("land", pid)
		"gate_neighbour", "gate_paddock":
			_through_gate(spot, p)
		"breed":
			if l == "TAKE SEED":
				var s := state.breed_collect(pid)
				if s >= 0:
					say("+1 " + D.STRAINS[s].short + " SEED", at)
			else:
				panel_wanted.emit("breed", pid)
	_save_soon()

## A line or two about what's at a spot (farmHint): the strain and how grown, dry or watered; what's for sale;
## the can. Shown under the E prompt whether or not E does something there.
func hint_lines(spot: Node, p) -> Array:
	var pid := pid_of(p)
	var st := state
	var v := st.inv_of(pid)
	var k: String = spot.kind
	match k:
		"plot":
			var i: int = spot.idx
			if not st.plot_open(i):
				return []
			var pl: Dictionary = st.plots[i]
			if pl.s < 0:
				return ["an empty hole", "no seeds: buy some at the crate by the shed" if st.seed_count(pid) == 0 else "E plants your " + D.STRAINS[st.seed_pick(pid)].name]
			var nm: String = D.STRAINS[pl.s].name + (" (frosty)" if pl.frosty else "")
			if pl.g >= 1.0:
				return [nm + ": ready!", "%d buds%s" % [st.buds_of(pl), " (it lost one wilting)" if pl.wilt else ""]]
			var second := ""
			if st.watered(i):
				second = "watered" + (" by the sprinkler" if pl.zone == "neighbour" and st.upgrades.sprinkler else ": %.1f h of water left" % pl.wet)
			elif pl.wilt:
				second = "wilted: it lost a bud. water it!"
			else:
				second = "dry: growing at half speed" + ("" if int(v.can) > 0 else " (fill the can at the tank)")
			var f := ""
			if pl.fert > 0:
				f = ", " + D.FERTS[pl.fert].name
			return ["%s: %d%% grown%s, about %.1f h to go" % [nm, int(pl.g * 100.0), f, st.hours_left(pl)], second]
		"row":
			if not st.land.paddock:
				return []
			var idx := st.row_plots(spot.idx)
			var planted := 0
			var ready := 0
			var g := 0.0
			for i in idx:
				if st.plots[i].s >= 0:
					planted += 1
					g += st.plots[i].g
					if st.plots[i].g >= 1.0:
						ready += 1
			if planted == 0:
				return ["row %d: empty" % (spot.idx + 1), "the tractor plants %d at once" % D.P_ROW_PLANTS]
			return ["row %d: %d planted, %d ready" % [spot.idx + 1, planted, ready], "%d%% grown on average" % int(g / planted * 100.0)]
		"tank":
			return ["watering can: %d of %d left" % [v.can, D.CAN_SIZE] if int(v.can) > 0 else "the watering can", "a full can waters %d plants" % D.CAN_SIZE]
		"crate":
			return ["seeds and fertiliser", "cash $%d" % cash()]
		"sell":
			return ["the garage buys buds", "%d buds on you, worth $%d" % [st.bud_count(pid), st.bud_value(pid, price_mults)]]
		"compost":
			if not st.upgrades.compost:
				return ["the compost bin", D.UPGRADES.compost.what]
			return ["compost: %d of %d harvests to the next bag" % [st.compost_count, D.COMPOST_PER_BAG], "%d bags of Basic waiting" % st.compost_bags]
		"sign_neighbour":
			return [] if st.land.neighbour else ["the neighbour's block: 24 plots, a grow house", "buy it for $%d" % D.LAND_PRICES.neighbour]
		"sign_paddock":
			return [] if st.land.paddock else ["the paddock: 12 long rows (needs a tractor)", "buy it for $%d" % D.LAND_PRICES.paddock]
		"breed":
			if not st.land.neighbour:
				return []
			if st.breeding.is_empty():
				return ["the breeding table: cross two seeds", "the new seed is ready after the next wave"]
			var b: Dictionary = st.breeding
			return ["crossing: a " + D.STRAINS[b.s].name + (" (frosty!)" if b.frosty else "") + " seed", "ready!" if not b.waiting else "ready after the next wave, or in %.1f h" % b.hours]
	return []

## Gates: step through to the other side (until the world takes the fence down: integration note).
func _through_gate(spot: Node, p) -> void:
	if not (p is Node3D):
		return
	var at := html_xy(p)
	var g: Vector2 = spot.gate_pos
	var to: Vector2
	if spot.kind == "gate_neighbour":
		to = Vector2(g.x + 48, g.y) if at.x < g.x else Vector2(g.x - 48, g.y)
	else:
		to = Vector2(g.x, g.y + 48) if at.y < g.y else Vector2(g.x, g.y - 48)
	if p.has_method("place"):
		p.place(to.x, to.y)
	else:
		p.global_position = GD.world_to_3d(to.x, to.y)
	if p.has_method("halt"):
		p.halt()
	if main and main.get("rig") and main.rig.has_method("snap"):
		main.rig.snap()

## ---------------------------------------------------------------- the panel's actions (each returns a line to show)

func buy_seed(pid: int, s: int, n: int = 1) -> String:
	var st := D.strain(s)
	if st.is_empty() or int(st.seed) <= 0:
		return "NOT FOR SALE"
	var c := int(st.seed) * n
	if not spend(c, "seeds"):
		return "NEED $%d" % c
	state.add_seed(pid, s, n)
	sound.emit("seed")
	_save_soon()
	return "+%d %s SEED%s" % [n, st.short, "S" if n > 1 else ""]

func buy_fert(pid: int, f: int, n: int = 1) -> String:
	if f < 1 or f > 3:
		return ""
	var c := int(D.FERTS[f].price) * n
	if not spend(c, "fertiliser"):
		return "NEED $%d" % c
	state.add_fert(pid, f, n)
	sound.emit("seed")
	_save_soon()
	return "+%d %s" % [n, D.FERTS[f].short]

func buy_land(k: String) -> String:
	if not D.LAND_PRICES.has(k) or state.land[k]:
		return ""
	var c := int(D.LAND_PRICES[k])
	if not spend(c, "land"):
		return "NEED $%d" % c
	state.land[k] = true
	state.changed.emit()
	save()
	return "BOUGHT THE " + ("NEIGHBOUR'S BLOCK" if k == "neighbour" else "PADDOCK")

func buy_upgrade(k: String) -> String:
	if not D.UPGRADES.has(k) or state.upgrades[k]:
		return ""
	var u: Dictionary = D.UPGRADES[k]
	if u.needs != "" and not state.land[u.needs]:
		return "BUY THE LAND FIRST"
	if not spend(int(u.price), "upgrade"):
		return "NEED $%d" % int(u.price)
	state.upgrades[k] = true
	state.changed.emit()
	save()
	return u.name.to_upper() + "!"

## Sell every bud (s -1) or one strain's. Returns the amount.
func sell(pid: int, s: int = -1) -> int:
	var v := state.take_buds(pid, s, price_mults)
	if v > 0:
		earn(v, "buds")
		sold.emit(pid, v)
		sound.emit("cash")
		_save_soon()
	return v

func pick_seed(pid: int, s: int) -> void:
	state.inv_of(pid).pick = s
	state.changed.emit()

func pick_fert(pid: int, f: int) -> void:
	state.inv_of(pid).fert_pick = f
	state.changed.emit()

func breed(pid: int, a: int, b: int) -> int:
	var s := state.breed(pid, a, b)
	_save_soon()
	return s

## Smoke a bud of strain s (the bong, or the bag's joint): the buff starts now.
func smoke(p, s: int) -> Dictionary:
	var pid := pid_of(p)
	var b := state.smoke(pid, s)
	if b.is_empty():
		return b
	smoked.emit(pid, s, b)
	sound.emit("smoke")
	buff_changed.emit(b)
	_save_soon()
	return b

## ---------------------------------------------------------------- the buff

func active_buff() -> Dictionary:
	return state.buff

## One field of the active buff (FarmData.BUFF_NEUTRAL's keys), or its neutral value.
func buff_value(key: String):
	if state.buff.has(key):
		return state.buff[key]
	return D.BUFF_NEUTRAL.get(key)

## ---------------------------------------------------------------- waves and raids (the fighting session calls these)

## A wave starts: roll a raid on the crops. The fighting sends {raiders} enemies for the plants and calls
## raid_result() when the wave ends (or they're all dead: raid_result(0)).
func on_wave_started(_wave: int = 0) -> Dictionary:
	_raid_wave_started = true
	_raid = {}
	var targets := state.raid_roll()
	if targets.is_empty():
		return {}
	var strains := []
	for i in targets:
		strains.append(state.plots[i].s)
	_raid = {"targets": targets, "raiders": targets.size() * D.RAIDERS_PER_PLANT, "strains": strains}
	raid_started.emit(_raid)
	return _raid

## How many raiders got away: each takes a targeted plant (a pair takes one: RAIDERS_PER_PLANT).
func raid_result(escaped: int) -> void:
	if _raid.is_empty():
		return
	var n := int(ceil(float(escaped) / D.RAIDERS_PER_PLANT))
	var t: Array = _raid.targets.slice(0, mini(n, _raid.targets.size()))
	var lost := state.raid_lose(t)
	raid_resolved.emit({"lost": lost, "defended": lost.is_empty()})
	_raid = {}
	_save_soon()

## A raider killed: maybe a seed (added to the host's bag). Returns the strain, or -1.
func raider_killed(pid: int = 0) -> int:
	if state.rng.randf() >= D.RAIDER_SEED_DROP:
		return -1
	var s := state.raider_seed(_raid.get("strains", []))
	state.add_seed(pid, s, 1)
	seed_dropped.emit(s)
	return s

## A wave survived: time moves on (GameClock.advance_hours), the buff counts down, a bred seed is ready. If the
## fighting didn't run a raid this wave and auto_raids is on, one is rolled and settled here.
func on_wave_survived(_wave: int = 0) -> void:
	if not _raid.is_empty():
		raid_result(0)                     # survived with raiders unaccounted for: the crop held
	elif not _raid_wave_started and auto_raids:
		_auto_raid()
	_raid_wave_started = false
	var had := not state.buff.is_empty()
	state.wave_survived()
	if had and state.buff.is_empty():
		buff_changed.emit({})
	elif had:
		buff_changed.emit(state.buff)
	if clock and clock.has_method("advance_hours"):
		clock.advance_hours(D.WAVE_HOURS)
	else:
		state.grow(D.WAVE_HOURS)
	sync_clock()
	_save_soon()

func _auto_raid() -> void:
	var targets := state.raid_roll()
	if targets.is_empty():
		return
	var strains := []
	for i in targets:
		strains.append(state.plots[i].s)
	var lose := []
	for i in targets:
		if state.rng.randf() < D.AUTO_RAID_LOSS:
			lose.append(i)
	var lost := state.raid_lose(lose)
	var drop := -1
	if state.rng.randf() < D.RAIDER_SEED_DROP * D.RAIDERS_PER_PLANT * targets.size():
		drop = state.raider_seed(strains)
		state.add_seed(0, drop, 1)
		seed_dropped.emit(drop)
	raid_resolved.emit({"lost": lost, "defended": lost.is_empty(), "targets": targets.size(), "drop": drop})

## ---------------------------------------------------------------- market (the trading game)

func set_market_prices(mults: Dictionary) -> void:
	price_mults = mults.duplicate()
	changed.emit()

## ---------------------------------------------------------------- saving

func _save_soon() -> void:
	_dirty = true
	_save_t = 8.0          # within a couple of seconds

func to_dict() -> Dictionary:
	var d := state.to_dict()
	if clock and clock.get("STANDIN") == true:
		d["clock_standin"] = clock.save_state()
	if wallet and wallet.get("STANDIN") == true:
		d["wallet_standin"] = wallet.get_cash()
	return d

func from_dict(d: Dictionary) -> void:
	state.from_dict(d)
	if d.has("clock_standin") and clock and clock.get("STANDIN") == true:
		clock.load_state(d.clock_standin)
	if d.has("wallet_standin") and wallet and wallet.get("STANDIN") == true:
		wallet.cash = int(d.wallet_standin)
		wallet.cash_changed.emit(wallet.cash)
	_clock_reset()

func save() -> void:
	_dirty = false
	_save_t = 0.0
	if not persist:
		return
	var txt := JSON.stringify(to_dict())
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('%s', %s)}catch(e){}" % [SAVE_KEY, JSON.stringify(txt)], true)
	else:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(txt)

func load_save() -> bool:
	var txt := ""
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('%s')||''}catch(e){return ''}})()" % SAVE_KEY, true)
		txt = v if v is String else ""
	elif FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			txt = f.get_as_text()
	if txt == "":
		return false
	var d = JSON.parse_string(txt)
	if not (d is Dictionary):
		return false
	from_dict(d)
	return true

## Wipe the farm (the panel's reset; tests).
func wipe() -> void:
	state.reset()
	if wallet and wallet.get("STANDIN") == true:
		wallet.cash = D.START_CASH
		wallet.cash_changed.emit(wallet.cash)
	save()
