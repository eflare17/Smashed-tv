extends Node
## The farm inside the real game: instances scenes/main.tscn, calls FarmInstall.install(main) as main.gd will,
## and sets up a scene to look at from the options (web: the address's ?query, desktop: user args after --):
##   farmdemo        cash, seeds and buds; the 8 backyard holes planted at every stage (some dry, one wilted);
##                   the neighbour's block bought and half planted; the player at the weed bed
##   farmall         farmdemo plus the paddock, the tractor and every upgrade, rows planted
##   at=X,Y          put the player there (HTML units)
##   fp              first person;  look=ANG  where he looks (radians)
##   panel=NAME      open the panel (bag, shop, sell, land, breed)
##   zoom=N          top-down zoom level (0, 1, 2)
##   waves=N         survive N waves (moves the clock on)
##   smoke=S         smoke a bud of strain S
##   selftest        play the loop through the real player's E and the panel's buttons, print SELFTEST lines, quit
## It prints "FARM ..." lines (what E says, the plots) a few times a second for the browser tests.

const D := preload("res://scripts/farm/farm_data.gd")
var main: Node
var farm: Farm
var opts := {}
var _t := 0.0
var _n := 0

func _ready() -> void:
	opts = _read_opts()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	farm = FarmInstall.install(main)
	farm.persist = not opts.has("farmdemo") and not opts.has("farmall")
	_setup.call_deferred()

func _read_opts() -> Dictionary:
	var out := {}
	var args: Array = OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.length() > 1:
			args = q.substr(1).split("&")
	for a in args:
		var kv: PackedStringArray = str(a).trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out

func _setup() -> void:
	await get_tree().process_frame
	var st := farm.state
	if opts.has("farmdemo") or opts.has("farmall"):
		st.reset()
		farm.wallet.cash = 5000
		for s in D.STRAINS.size():
			st.add_seed(0, s, 4)
			st.inv_of(0).buds[s][0] = 2 + s
		st.add_fert(0, 1, 3)
		st.add_fert(0, 3, 2)
		st.inv_of(0).pick = 0
		var gs := [0.05, 0.3, 0.6, 1.0, 1.0, 0.7, 0.35, 1.0]
		for i in 8:
			st.plant(i, 0, i % 6)
			st.plots[i].g = gs[i]
			st.plots[i].wet = 2.0 if i % 3 != 1 else 0.0
		st.plots[6].wilt = 1
		st.plots[6].wet = 0.0
		st.plots[6].dry = 3.0
		st.land.neighbour = true
		for i in range(8, 8 + 14):
			st.plant(i, 0, (i * 7) % 6)
			st.plots[i].g = fmod(i * 0.173, 1.05)
			st.plots[i].wet = 1.0
		st.fill_can(0)
		main.player.place(1500, 640)
	if opts.has("farmall"):
		st.land.paddock = true
		for k in st.upgrades:
			st.upgrades[k] = true
		for r in 6:
			for i in st.row_plots(r):
				st.plant(i, 0, r % 6) if st.inv_of(0).seeds[r % 6] > 0 else null
				if st.plots[i].s < 0:
					st.add_seed(0, r % 6, 1)
					st.plant(i, 0, r % 6)
				st.plots[i].g = minf(1.0, 0.2 * r)
	st.changed.emit()
	if opts.has("at"):
		var xy: PackedStringArray = opts.at.split(",")
		main.player.place(float(xy[0]), float(xy[1]))
	if opts.has("zoom"):
		main.rig.set_zoom(int(opts.zoom))
	if opts.has("fp"):
		main.rig.set_mode(1)
		main.rig.capture_mouse = false
	if opts.has("look"):
		main.player.look_ang = float(opts.look)
	if opts.has("waves"):
		for w in int(opts.waves):
			farm.on_wave_survived(w)
	if opts.has("smoke"):
		farm.smoke(0, int(opts.smoke))
	main.rig.snap()
	if opts.has("panel"):
		await get_tree().process_frame
		var ui: FarmUI = main.get_node("FarmUI")
		ui.open(opts.panel, 0)
	print("FARM ready plots=%d cash=%d" % [st.plots.size(), farm.cash()])
	if opts.has("selftest"):
		await _selftest()

var _pass := 0
var _fail := 0
func _ok(c: bool, what: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
	print("SELFTEST %s %s" % ["PASS" if c else "FAIL", what])

func _at(x: float, y: float) -> String:
	main.player.place(x, y)
	main.player.halt()
	await get_tree().process_frame
	await get_tree().process_frame
	return main.player.focus_label

func _press(prefix: String) -> bool:
	var ui: FarmUI = main.get_node("FarmUI")
	for b in ui._all_buttons():
		if b.text.begins_with(prefix) and not b.disabled and b.is_visible_in_tree():
			b.pressed.emit()
			await get_tree().process_frame
			return true
	return false

func _selftest() -> void:
	var st := farm.state
	var ui: FarmUI = main.get_node("FarmUI")
	var p: Node = main.player
	st.reset()
	farm.wallet.cash = 100
	st.changed.emit()
	var l := await _at(456, 1745)
	_ok(l == "SHOP", "at the crate E says SHOP (%s)" % l)
	p.use()
	await get_tree().process_frame
	_ok(ui.is_open() and ui._context == "shop", "E opens the shop")
	_ok(not p.controls_enabled, "the player stands still while the panel's open")
	_ok(await _press("$10"), "press the NL seed's button")
	_ok(st.inv_of(0).seeds[0] == 1 and farm.cash() == 90, "bought a NL seed for $10")
	await _press("$10")
	ui.close()
	_ok(not ui.is_open() and p.controls_enabled, "closed, can move again")
	l = await _at(1380, 1795)
	_ok(l == "FILL CAN", "at the tank E says FILL CAN (%s)" % l)
	p.use()
	_ok(st.inv_of(0).can == 8, "the can is full")
	l = await _at(1426, 196)
	_ok(l == "PLANT NL", "at the first hole: PLANT NL (%s)" % l)
	p.use()
	_ok(st.plots[0].s == 0, "planted")
	await get_tree().process_frame
	_ok(p.focus_label == "WATER", "then WATER (%s)" % p.focus_label)
	p.use()
	_ok(st.plots[0].wet > 2.9 and st.inv_of(0).can == 7, "watered")
	var wv: FarmPlotView = main.get_node("FarmWorld").views[0]
	_ok(wv._plant.visible and wv._soil.visible, "the plant and its soil show")
	farm.auto_raids = false
	farm.on_wave_survived(1)
	farm.on_wave_survived(2)
	await get_tree().process_frame
	_ok(st.plots[0].g >= 1.0, "two waves survived: NL ready (g %.2f)" % st.plots[0].g)
	_ok(p.focus_label == "HARVEST", "HARVEST (%s)" % p.focus_label)
	p.use()
	_ok(st.bud_count(0) == 3, "3 buds harvested")
	l = await _at(1426, 330)
	_ok(l == "PLANT NL", "the second seed into the next hole (%s)" % l)
	p.use()
	l = await _at(1070, 1010)
	_ok(l == "SELL $40", "at the garage door: SELL $40 (%s)" % l)
	p.use()
	await get_tree().process_frame
	_ok(ui.is_open() and ui._context == "sell", "the sell panel")
	st.inv_of(0).buds[1][0] = 1
	st.changed.emit()
	await get_tree().process_frame
	_ok(await _press("SELL $40"), "sell the NL buds only")
	_ok(farm.cash() == 120 and st.bud_count(0) == 1, "+$40, SD bud kept (cash %d)" % farm.cash())
	ui.open("bag", 0)
	await get_tree().process_frame
	var buffs := []
	farm.buff_changed.connect(func(b): buffs.append(b))
	_ok(await _press("SMOKE"), "smoke the SD bud from the bag")
	_ok(buffs.size() == 1 and farm.buff_value("speed_mult") == 1.25, "SD buff on")
	ui.close()
	l = await _at(1650, 1190)
	_ok(l == "FOR SALE $2500", "the FOR SALE sign (%s)" % l)
	farm.wallet.cash = 3000
	p.use()
	await get_tree().process_frame
	_ok(await _press("BUY $2500"), "buy the neighbour's block")
	_ok(st.land.neighbour and farm.cash() == 500, "it's yours")
	ui.close()
	l = await _at(1690, 1240)
	_ok(l == "GATE", "the gate (%s)" % l)
	p.use()
	await get_tree().process_frame
	_ok(p.html_pos().x > 1708, "through the gate (x %.0f)" % p.html_pos().x)
	var o: Vector2 = D.N_PLOT_ORIGIN
	l = await _at(o.x, o.y + 25)
	_ok(l == "" or l.begins_with("PLANT"), "a neighbour plot (%s)" % l)
	st.add_seed(0, 1, 1)
	await get_tree().process_frame
	_ok(p.focus_label == "PLANT SD", "neighbour plot: PLANT SD (%s)" % p.focus_label)
	main.rig.set_mode(1)
	await get_tree().process_frame
	_ok(p.focus_label == "PLANT SD", "same in first person")
	main.rig.set_mode(0)
	# the clock's hour moves and growth follows
	var h0: float = farm.clock.hour
	farm.clock.advance_hours(1.0)
	await get_tree().process_frame
	_ok(absf(fposmod(farm.clock.hour - h0, 24.0) - 1.0) < 0.05, "advance_hours")
	# save round trip
	farm.persist = true
	farm.save()
	var keep := JSON.stringify(farm.to_dict())
	st.reset()
	_ok(farm.load_save(), "saved farm loads")
	var again := JSON.stringify(farm.to_dict())
	_ok(again == keep, "and comes back the same")
	if again != keep:
		print(keep.left(600), "\n", again.left(600))
	farm.persist = false
	print("SELFTEST DONE %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5 or farm == null:
		return
	_t = 0.0
	_n += 1
	if _n > 40:
		return
	var p: Node = main.player
	var h: Vector3 = p.html_pos()
	print("FARM t=%d x=%.0f y=%.0f label=%s g0=%.2f cash=%d hour=%.2f fps=%d" % [_n, h.x, h.y, p.focus_label, farm.state.plots[0].g, farm.cash(),
		float(farm.clock.get("hour")) if farm.clock else -1.0, Engine.get_frames_per_second()])
