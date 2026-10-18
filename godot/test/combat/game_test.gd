extends Node
## The real game with the fighting installed (what main.gd's one line will do), for headless runs:
##   godot --headless --path godot res://test/combat/game_test.tscn -- --fight=run,auto --secs=20
## Prints a FIGHT line a second (wave, enemies, hp, kills, coins) and quits after --secs.

var secs := 20.0
var t := 0.0
var next := 1.0
var main: Node

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	FightInstall.install(main)

func _process(delta: float) -> void:
	t += delta
	if t >= next:
		next += 1.0
		var fg := Fight.me
		if fg:
			var s := fg.sim
			print("FIGHT t=%.0f started=%s wave=%d enemies=%d hp=%.0f alive=%s kills=%d coins=%d weapon=%s ammo=%d over=%s jan=%s fps=%d" % [
				t, s.started, s.wave, s.enemies.size(), fg.f.hp, fg.f.alive, fg.f.kills, fg.f.coins, fg.f.weapon, fg.f.ammo, s.over,
				s.janitor.phase, Engine.get_frames_per_second()])
	if t >= secs:
		get_tree().quit()
