class_name Bones
extends RefCounted
## What carries over between runs. Dying pays BONES for the run (kills, eating, new areas and evolving, each about
## an equal share of a typical run); on the death screen you spend them on permanent starting ranks in the seven
## level-up upgrades (main.gd's UPGRADES, max MAX_RANK each, a rank is about half an in-run level-up) and on one
## big unlock: starting the run as a Raptor. Also your leaderboard id and name. Saved in user:// (a file on a PC,
## the browser's storage on the web).

## Bones per kill, per body eaten, per new area reached, per evolution. A decent run (15 kills, 6 eaten, area 2,
## evolved once) pays about 94, in four roughly equal shares; the demo bot's clumsy runs pay 20-60. (Doubled at
## the owner's ask: a bad run paying 7 felt like nothing.)
const PER_KILL := 2
const PER_EAT := 4
const PER_AREA := 20
const PER_EVOLVE := 20
const MAX_RANK := 5
## The price of rank 1..5 of an upgrade (about two ranks a decent run), and of starting as a Raptor (about 4-5
## decent runs; buyable any time). Agreed with the owner ("medium").
const PRICES := [30, 40, 55, 75, 100]
const RAPTOR_PRICE := 400
## What one rank adds (half an in-run level-up): bite radius, speed x, bite cooldown x, health, lunge x, big-bite
## charge time x, shake x. In UPGRADES order.
const RANK_BITE := 0.75
const RANK_SPEED := 1.09
const RANK_RATE := 0.88
const RANK_HEALTH := 15.0
const RANK_LUNGE := 1.12
const RANK_CHARGE := 0.84
const RANK_SHAKE := 1.15
## The shop's eighth item (after the seven upgrades).
const RAPTOR := 7

## Leaderboard names: a random one of each and a number ("BLOODY RAPTOR 42"); NEW NAME rolls another.
const NAME_A := ["BLOODY", "SAVAGE", "HUNGRY", "RAVENOUS", "GORY", "FERAL", "GRUMPY", "SNEAKY", "MIGHTY", "TOOTHY",
		"VICIOUS", "RABID", "FURIOUS", "GREEDY", "SLOPPY", "SCALY", "SPIKY", "BONY", "WILD", "STINKY"]
const NAME_B := ["RAPTOR", "REX", "TYRANT", "ALLOSAUR", "HATCHLING", "CHOMPER", "BITER", "GNASHER", "MUNCHER",
		"STALKER", "LIZARD", "CLAW", "FANG", "JAWS", "MAW"]

## Where it's saved ("" = nowhere: the tests and the demo bot never touch your real save).
var path := "user://bones.cfg"
var bones := 0
var ranks: Array[int] = [0, 0, 0, 0, 0, 0, 0]
var raptor := false
## You on the leaderboard: a random id (so a new name keeps your totals) and your name. Made on first load.
var player_id := ""
var name := ""

static func random_name() -> String:
	return "%s %s %d" % [NAME_A[randi() % NAME_A.size()], NAME_B[randi() % NAME_B.size()], randi_range(1, 99)]

## A new name, different from the one you have.
func new_name() -> void:
	var was := name
	while name == was:
		name = random_name()
	save()

## Makes you an id and a name the first time.
func _ensure_player() -> void:
	if player_id == "":
		# a random version-4 UUID (what the database expects)
		var b := PackedByteArray()
		for k in 16:
			b.append(randi() % 256)
		b[6] = (b[6] & 0x0f) | 0x40
		b[8] = (b[8] & 0x3f) | 0x80
		var h := b.hex_encode()
		player_id = "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20)]
	if name == "":
		name = random_name()

## What a run pays: kills, whole bodies eaten, areas reached past the first, and times evolved.
static func earned(kills: int, eaten: int, areas: int, evolves: int) -> int:
	return kills * PER_KILL + eaten * PER_EAT + areas * PER_AREA + evolves * PER_EVOLVE

func add(n: int) -> void:
	bones += n
	save()

## What the next rank of item `i` costs (or the Raptor), or -1 if there's nothing left to buy.
func price(i: int) -> int:
	if i == RAPTOR:
		return -1 if raptor else RAPTOR_PRICE
	return -1 if ranks[i] >= MAX_RANK else PRICES[ranks[i]]

func can_buy(i: int) -> bool:
	var p := price(i)
	return p >= 0 and bones >= p

## Buys the next rank of item `i` (or the Raptor) if you can afford it. True if it did.
func buy(i: int) -> bool:
	if not can_buy(i):
		return false
	bones -= price(i)
	if i == RAPTOR:
		raptor = true
	else:
		ranks[i] += 1
	save()
	return true

## Puts the bought ranks on a fresh player (and makes it a Raptor if that's unlocked), full health.
func apply(p: Player) -> void:
	if raptor:
		p.set_stage(Player.stage_of("RAPTOR"))
	p.bite_bonus += RANK_BITE * ranks[0]
	p.speed_mult *= pow(RANK_SPEED, ranks[1])
	p.cool_mult *= pow(RANK_RATE, ranks[2])
	p.hp_bonus += RANK_HEALTH * ranks[3]
	p.lunge_mult *= pow(RANK_LUNGE, ranks[4])
	p.charge_time *= pow(RANK_CHARGE, ranks[5])
	p.shake_mult *= pow(RANK_SHAKE, ranks[6])
	p.apply_stage()
	p.hp = p.max_hp

func load_save() -> void:
	var cf := ConfigFile.new()
	if path != "" and cf.load(path) == OK:
		bones = int(cf.get_value("bones", "bones", 0))
		var r: Array = cf.get_value("bones", "ranks", [])
		for k in mini(r.size(), ranks.size()):
			ranks[k] = clampi(int(r[k]), 0, MAX_RANK)
		raptor = bool(cf.get_value("bones", "raptor", false))
		player_id = str(cf.get_value("player", "id", ""))
		name = str(cf.get_value("player", "name", ""))
	var had := player_id != "" and name != ""
	_ensure_player()
	if not had:
		save()

func save() -> void:
	if path == "":
		return
	var cf := ConfigFile.new()
	cf.set_value("bones", "bones", bones)
	cf.set_value("bones", "ranks", Array(ranks))
	cf.set_value("bones", "raptor", raptor)
	cf.set_value("player", "id", player_id)
	cf.set_value("player", "name", name)
	cf.save(path)
