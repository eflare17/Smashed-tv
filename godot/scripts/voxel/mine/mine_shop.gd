class_name MineShop
extends RefCounted
## The dig mode's money (the owner, 23 Oct): what the cargo sells for at the trader up top (each price wobbling a
## little day to day, one thing in demand each day), the fuel's price a litre, the mechanic's five upgrades (four
## levels each, each changing how the ship looks), the supplies (dynamite, repair kits, the emergency teleport home)
## and a fresh claim (new ground). The cash is the arena's own (arena.cash): one wallet. Owned by the voxel session.

## What goes in the cargo hold: its name, its price on an ordinary day
const CARGO := {
	"coal": {"name": "Coal", "price": 8},
	"copper": {"name": "Copper", "price": 20},
	"silver": {"name": "Silver", "price": 46},
	"gold": {"name": "Gold", "price": 105},
	"opal": {"name": "Opal", "price": 230},
	"diamond": {"name": "Diamond", "price": 520},
	"spore": {"name": "Spore clump", "price": 38},
	"shroom": {"name": "Giant mushroom", "price": 160},
	"junk": {"name": "Sewer junk", "price": 14},
	"evidence": {"name": "Evidence bag", "price": 280},
	"stash": {"name": "Rival stash", "price": 190},
	"hoard": {"name": "Hoard diamond", "price": 900},
}
## The order they're listed in
const CARGO_ORDER := ["coal", "copper", "silver", "gold", "opal", "diamond", "spore", "shroom", "junk", "evidence", "stash", "hoard"]

## The upgrades: what each level gives, what the next level costs (level 0 is what the ship starts with)
const UPGRADES := {
	"drill": {"name": "Drill", "k": [1.0, 1.6, 2.4, 3.6], "cost": [260, 900, 2800], "unit": "x speed",
		"names": ["Steel bit", "Bronze Mk II", "Gold Mk III", "Diamond Mk IV"]},
	"tank": {"name": "Fuel tank", "k": [12.0, 20.0, 32.0, 50.0], "cost": [160, 600, 1800], "unit": " L",
		"names": ["Jerry can", "Twin tanks", "Saddle tanks", "Long-range"]},
	"cargo": {"name": "Cargo bay", "k": [8.0, 14.0, 22.0, 34.0], "cost": [200, 720, 2100], "unit": " slots",
		"names": ["Tray", "Box", "Hold", "Freighter"]},
	"hull": {"name": "Hull", "k": [30.0, 50.0, 80.0, 125.0], "cost": [200, 800, 2400], "unit": " hp",
		"names": ["Tin", "Plated", "Armoured", "Tank"]},
	"lights": {"name": "Lights", "k": [6.0, 9.0, 13.0, 18.0], "cost": [110, 420, 1200], "unit": " m",
		"names": ["Torch", "Twin lamps", "Floodlights", "Stadium"]},
	"launcher": {"name": "Launcher", "k": [10.0, 13.0, 17.0, 22.0], "cost": [150, 500, 1400], "unit": " m/s",
		"names": ["Slingshot", "Spring gun", "Air cannon", "Rail launcher"]},
}
const UPGRADE_ORDER := ["drill", "tank", "cargo", "hull", "lights", "launcher"]

## The supplies: [id, name, cost, the most you can carry]
const ITEMS := {
	"dynamite": {"name": "Dynamite", "cost": 120, "max": 5, "key": "1", "desc": "blows the rock round you open"},
	"repair": {"name": "Repair kit", "cost": 150, "max": 5, "key": "2", "desc": "patches 40% of the hull"},
	"teleport": {"name": "Teleport home", "cost": 260, "max": 3, "key": "3", "desc": "beams you up top, cargo and all"},
}
const ITEM_ORDER := ["dynamite", "repair", "teleport"]

const FUEL_PRICE := 2.0         # a litre, on an ordinary day
const REPAIR_PRICE := 3.0       # a hull point at the mechanic
const CLAIM_COST := 400         # fresh ground

static func k(track: String, level: int) -> float:
	return float(UPGRADES[track].k[clampi(level, 0, 3)])

## The next level's cost (-1: at the top)
static func cost(track: String, level: int) -> int:
	if level >= 3:
		return -1
	return int(UPGRADES[track].cost[level])

## Today (days since 1970, from the PC's clock): the prices change each day.
static func today() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)

static func _wob(day: int, salt: String) -> float:
	var h := hash(str(day) + salt)
	return float(absi(h) % 1000) / 1000.0

## What's in demand today (it sells for half as much again)
static func hot(day: int) -> String:
	var ores := ["coal", "copper", "silver", "gold", "opal", "diamond", "spore"]
	return ores[int(_wob(day, "hot") * ores.size()) % ores.size()]

## A cargo item's price today: within a fifth either way of its usual, half as much again if it's in demand.
static func price(id: String, day: int) -> int:
	if not CARGO.has(id):
		return 0
	var p := float(CARGO[id].price) * (0.8 + 0.4 * _wob(day, id))
	if id == hot(day):
		p *= 1.5
	return maxi(1, int(round(p)))

## How much today's price is up or down on the usual (a share: 0.1 = 10% up)
static func trend(id: String, day: int) -> float:
	return float(price(id, day)) / float(CARGO[id].price) - 1.0

static func fuel_price(day: int) -> float:
	return snappedf(FUEL_PRICE * (0.85 + 0.3 * _wob(day, "fuel")), 0.05)

## What a hold full of cargo ({id: count}) sells for today
static func value(cargo: Dictionary, day: int) -> int:
	var v := 0
	for id in cargo:
		v += price(String(id), day) * int(cargo[id])
	return v
