class_name DigInstall
extends RefCounted
## The digging part's entry point (PLAN.md "Later: digging", level 2 and ploughing). In main.gd, after
## FarmInstall (field plots are the farm's):
##     DigInstall.install(self)
## Adds main/Dig (the grid, tools, saving, online) with the ground in main.world (World/DigGround), and
## main/DigUI. Idempotent: returns the Dig already there.

static func install(main: Node) -> Dig:
	var old: Dig = main.get_node_or_null("Dig")
	if old:
		return old
	var d := Dig.new()
	d.name = "Dig"
	# (headless runs, the tests, keep the save file alone; the tests save and load on purpose)
	d.persist = DisplayServer.get_name() != "headless"
	main.add_child(d)
	d.setup(main)
	var ui := DigUI.new()
	ui.name = "DigUI"
	ui.dig = d
	d.ui = ui
	main.add_child(ui)
	return d
