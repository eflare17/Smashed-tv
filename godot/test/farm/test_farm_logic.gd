extends SceneTree
## Headless logic tests for the farm: godot --headless --path godot -s res://test/farm/test_farm_logic.gd
## Prints PASS/FAIL per check and "FARM LOGIC: n passed, m failed"; exits 1 on any failure.

const D := preload("res://scripts/farm/farm_data.gd")
const ClockStandin := preload("res://scripts/farm/game_clock_standin.gd")
const WalletStandin := preload("res://scripts/farm/farm_wallet_standin.gd")

var passed := 0
var failed := 0

func ok(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("PASS ", what)
	else:
		failed += 1
		print("FAIL ", what)

func near(a: float, b: float, what: String, eps: float = 0.001) -> void:
	ok(absf(a - b) <= eps, "%s (%.4f vs %.4f)" % [what, a, b])

func _init() -> void:
	_state_tests()
	process_frame.connect(_later, CONNECT_ONE_SHOT)

func _later() -> void:
	_farm_tests()
	print("FARM LOGIC: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _fresh() -> FarmState:
	var s := FarmState.new()
	s.rng.seed = 1234
	return s

func _state_tests() -> void:
	var s := _fresh()
	ok(s.plots.size() == 8 + 24 + 120 + D.FIELD_PLOTS, "plots: 8 yard + 24 neighbour + 120 paddock + the field plots (scripts/dig)")
	ok(s.plot_open(0) and not s.plot_open(8) and not s.plot_open(40), "only the yard is open at first")
	ok(s.plot_label(0, 0) == "", "nothing to plant without seeds")
	s.add_seed(0, 0, 2)
	ok(s.plot_label(0, 0) == "PLANT NL", "plant label with a NL seed")
	ok(s.plot_act(0, 0).begins_with("PLANTED"), "planting")
	ok(s.inv_of(0).seeds[0] == 1 and s.plots[0].s == 0, "a seed used, plot holds NL")
	ok(s.stage(0) == 0, "seedling stage")
	# dry: half speed, 4 h strain -> after 2 h dry it's grown 0.25; it wilts at 2.5 h
	s.grow(2.0)
	near(s.plots[0].g, 0.25, "dry growth at half speed")
	ok(s.plots[0].wilt == 0, "dry 2 h: not wilted yet")
	s.grow(0.5)
	ok(s.plots[0].wilt == 1, "dry 2.5 h: wilted")
	ok(s.look(0) == 2, "wilted look")
	# a fresh one watered: full speed 3 h, then dry
	s.plant(1, 0, 0)
	ok(s.plot_label(1, 0) == "", "no can: nothing to do at a growing plant")
	s.fill_can(0)
	ok(s.inv_of(0).can == D.CAN_SIZE, "can full")
	ok(s.plot_label(1, 0) == "WATER", "water label with the can")
	s.plot_act(1, 0)
	ok(s.inv_of(0).can == D.CAN_SIZE - 1 and s.watered(1), "watered, one used")
	s.grow(3.0)
	near(s.plots[1].g, 0.75, "3 h watered = 0.75 of a 4 h strain")
	ok(s.plots[1].wet == 0.0 and s.plots[1].wilt == 0, "water ran out, not wilted yet")
	s.grow(0.5)
	near(s.plots[1].g, 0.8125, "then dry at half speed")
	ok(s.stage(1) == 2, "fan leaves")
	s.plot_act(1, 0)          # water again
	s.grow(1.0)
	ok(s.plots[1].g >= 1.0 and s.stage(1) == 3, "ready")
	ok(s.plot_label(1, 0) == "HARVEST", "harvest label")
	ok(s.plot_act(1, 0) == "+3 NL BUDS", "harvest 3 buds")
	ok(s.bud_count(0) == 3 and s.plots[1].s == -1, "buds in the bag, plot empty")
	# the wilted one loses a bud
	s.grow(10.0)
	ok(s.plots[0].g >= 1.0, "the wilted one ripens dry")
	ok(s.plot_act(0, 0) == "+2 NL BUDS", "wilted gives one bud fewer")
	ok(s.bud_value(0) == 67, "5 NL buds = 5 x 40/3 = $67 (got %d)" % s.bud_value(0))
	# fertiliser
	s.add_seed(0, 5, 1)
	s.add_fert(0, 3, 1)
	s.plant(2, 0, 5)
	ok(s.plot_label(2, 0) == "WATER", "water comes before fertiliser")
	s.inv_of(0).can = 0
	ok(s.plot_label(2, 0) == "FERTILISE SUPER", "fertilise label")
	s.plot_act(2, 0)
	near(s.speed(s.plots[2]), 2.0 / 15.0, "super grow doubles WW's speed")
	s.plots[2].wet = 100.0
	s.grow(7.5)
	ok(s.plots[2].g >= 1.0, "WW with super grow in 7.5 h")
	s.harvest(2, 0)
	ok(s.inv_of(0).buds[5][1] == 3, "WW + super: 3 potent buds")
	near(D.bud_price(5, 1), 150.0 * 1.15, "potent bud price")
	# smoking
	var b := s.smoke(0, 5)
	ok(b.damage_mult == 1.6 and b.trippy and b.waves == 3 and b.potent, "WW buff, potent lasts 3 waves")
	ok(s.inv_of(0).buds[5][1] == 2, "a bud smoked")
	s.wave_survived()
	s.wave_survived()
	ok(s.buff.waves == 1, "buff counts down")
	s.wave_survived()
	ok(s.buff.is_empty(), "buff over")
	b = s.smoke(0, 1)
	ok(b.is_empty(), "can't smoke what you haven't got")
	b = s.smoke(0, 0)
	ok(b.heal == 2 and b.speed_mult == 1.0, "NL heals, other fields neutral")
	# selling
	var v := s.take_buds(0, -1)
	ok(v > 0 and s.bud_count(0) == 0, "sold everything ($%d)" % v)
	# market prices
	s.inv_of(0).buds[0][0] = 3
	ok(s.bud_value(0, {0: 2.0}) == 80, "market x2 doubles")
	# raids
	var r := _fresh()
	for i in 8:
		r.add_seed(0, 5, 1)
		r.plant(i, 0, 5)
	var hits := 0
	for n in 200:
		hits += r.raid_roll().size()
	ok(hits > 200 and hits < 500, "WW raid risk 22%% of 8 plants over 200 waves (%d hits)" % hits)
	var lost := r.raid_lose([0, 1])
	ok(lost.size() == 2 and r.plots[0].s == -1, "raided plants are gone")
	# breeding
	var br := _fresh()
	br.add_seed(0, 0, 2)
	ok(br.breed(0, 0, 0) >= 0 and br.seed_count(0) == 0, "NL + NL on the table")
	ok(br.breed_collect(0) == -1, "not ready yet")
	br.wave_survived()
	var got := br.breed_collect(0)
	ok(got >= 2, "bred a seed (strain %d)" % got)
	br.add_seed(0, 1, 1)
	ok(br.breed(0, 1, 0) == -1, "SD + NL isn't a recipe")
	br.add_seed(0, 1, 1)
	br.breed(0, 1, 1)
	br.grow(D.BREED_HOURS)
	ok(br.breed_collect(0) >= 3, "bred seed ready after the hours")
	# land: neighbour plots, sprinkler
	var l := _fresh()
	l.land.neighbour = true
	l.upgrades.sprinkler = true
	l.add_seed(0, 0, 1)
	l.plant(8, 0, 0)
	l.grow(4.0)
	ok(l.plots[8].g >= 1.0 and l.plots[8].wilt == 0, "sprinkled neighbour plot grows at full speed")
	# paddock rows with the tractor
	var pd := _fresh()
	pd.land.paddock = true
	ok(pd.row_label(0, 0) == "NEED TRACTOR", "tractor needed")
	pd.upgrades.tractor = true
	pd.add_seed(0, 1, 12)
	ok(pd.row_label(0, 0) == "PLANT ROW SD", "plant row label")
	ok(pd.row_act(0, 0) == "PLANTED 10", "a row of 10 planted")
	ok(pd.row_label(0, 0) == "WATER ROW", "then water")
	pd.row_act(0, 0)
	pd.grow(3.0)
	pd.row_act(0, 0)
	pd.grow(3.0)
	ok(pd.row_label(0, 0) == "HARVEST ROW", "row ready")
	ok(pd.row_act(0, 0).begins_with("+30 BUDS"), "row harvest 30 buds")
	# compost
	var c := _fresh()
	c.upgrades.compost = true
	c.add_seed(0, 0, 3)
	for i in 3:
		c.plant(i, 0, 0)
		c.plots[i].g = 1.0
		c.harvest(i, 0)
	ok(c.compost_bags == 1, "3 harvests = a compost bag")
	# save round trip
	var sv := _fresh()
	sv.add_seed(0, 3, 2, true)
	sv.add_fert(0, 2, 4)
	sv.plant(3, 0, 3)
	sv.plots[3].g = 0.4
	sv.plots[3].wet = 1.5
	sv.land.neighbour = true
	sv.smoke(0, 0)
	sv.inv_of(0).buds[2][3] = 5
	sv.smoke(0, 2)
	var txt := JSON.stringify(sv.to_dict())
	var back := FarmState.new()
	back.from_dict(JSON.parse_string(txt))
	ok(back.plots[3].s == 3 and absf(back.plots[3].g - 0.4) < 0.001 and back.plots[3].frosty, "save: plot")
	ok(back.inv_of(0).frosty[3] == 1 and back.inv_of(0).ferts[2] == 4, "save: inventory")
	ok(back.land.neighbour and back.buff.strain == 2 and back.inv_of(0).buds[2][3] == 4, "save: land, buff, buds")

func _farm_tests() -> void:
	var clock = ClockStandin.new()
	clock.name = "GameClock"
	root.add_child(clock)
	var wallet = WalletStandin.new()
	wallet.name = "Wallet"
	wallet.cash = 100
	root.add_child(wallet)
	var f := Farm.new()
	f.persist = false
	f.clock = clock
	f.wallet = wallet
	root.add_child(f)
	f.state.rng.seed = 99
	ok(Farm.instance == f, "Farm.instance (%s)" % Farm.instance)
	ok(f.buy_seed(0, 0, 2) == "+2 NL SEEDS" and wallet.cash == 80, "buy seeds with the wallet")
	ok(f.buy_seed(0, 2) == "NOT FOR SALE", "GDP seeds aren't sold")
	ok(f.buy_fert(0, 3, 2) == "NEED $160", "can't afford")
	ok(f.buy_land("neighbour").begins_with("NEED"), "land too dear")
	f.state.plant(0, 0, 0)
	f.state.fill_can(0)
	f.state.water(0, 0)
	clock.advance_hours(2.0)
	f.sync_clock()
	near(f.state.plots[0].g, 0.5, "grows with the clock's hours")
	var buffs := []
	f.buff_changed.connect(func(b): buffs.append(b))
	f.state.inv_of(0).buds[1][0] = 1
	f.smoke(0, 1)
	ok(buffs.size() == 1 and buffs[0].speed_mult == 1.25, "buff_changed on smoking SD")
	ok(f.buff_value("fire_rate_mult") == 1.25 and f.buff_value("cash_mult") == 1.0, "buff_value")
	var h0: float = clock.hour
	f.state.water(0, 0)
	f.on_wave_survived(1)
	ok(f.state.plots[0].g >= 1.0, "a wave survived moves time on: NL ready (2 + 2.5 h)")
	ok(absf(fposmod(clock.hour - h0, 24.0) - D.WAVE_HOURS) < 0.01, "clock moved WAVE_HOURS")
	ok(buffs.size() == 2 and buffs[1].is_empty(), "buff worn off after its wave")
	# a raid the fighting runs
	for i in range(1, 8):
		f.state.add_seed(0, 5, 1)
		f.state.plant(i, 0, 5)
	var raid := {}
	for n in 50:
		raid = f.on_wave_started(n)
		if not raid.is_empty():
			break
		f.on_wave_survived(n)
	ok(not raid.is_empty() and raid.raiders == raid.targets.size() * 2, "a raid rolled with raiders")
	var before := 0
	for p in f.state.plots:
		if p.s >= 0:
			before += 1
	f.raid_result(2)
	var after := 0
	for p in f.state.plots:
		if p.s >= 0:
			after += 1
	ok(before - after == 1, "two raiders escaped: one plant lost")
	# selling earns
	f.state.inv_of(0).buds[0][0] = 3
	var c0: int = wallet.cash
	ok(f.sell(0) == 40 and wallet.cash == c0 + 40, "sell 3 NL buds = $40 into the wallet")
	# save round trip through the farm (stand-in clock and wallet ride along)
	var d := f.to_dict()
	ok(d.has("clock_standin") and d.wallet_standin == wallet.cash, "stand-ins saved with the farm")
	# past midnight (the hour wraps, the day turns at 7 am): growth still counts the hours
	f.state.add_seed(0, 5, 1)
	for i in f.state.plots.size():
		if f.state.plots[i].zone == "yard" and f.state.plots[i].s < 0:
			f.state.plant(i, 0, 5)
			f.state.plots[i].wet = 100.0
			clock.hour = 23.0
			f._clock_reset()
			clock.advance_hours(2.0)
			f.sync_clock()
			near(f.state.plots[i].g, 2.0 / 15.0, "growth across midnight")
			break
	# sleeping grows too
	f.state.add_seed(0, 0, 1)
	f.state.plant(0, 0, 0)
	clock.sleep_to_morning()
	f.sync_clock()
	ok(f.state.plots[0].g >= 1.0 or f.state.plots[0].g > 0.4, "sleeping to morning grows (g %.2f)" % f.state.plots[0].g)
	ok(clock.hour >= 6.99 and clock.hour <= 7.01, "the stand-in sleeps to 7 am")
