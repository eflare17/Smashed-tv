class_name ZombieInstall
extends RefCounted
## The zombie's one entry point: main.gd calls ZombieInstall.install(self) after FightInstall (it needs the Fight)
## and before Net. Adds the ZombieNight node (the backyard's night zombies; it makes the ZombieView and ZombieSfx
## under the Fight). The arena's zombies need nothing more: they're in the fight's waves (EnemySim.wave_mix).

static func install(main: Node) -> ZombieNight:
	var z := ZombieNight.new()
	z.main = main
	main.add_child(z)
	return z
