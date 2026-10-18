class_name FarmData
extends RefCounted
## The farm's numbers, all in one place (FARM.md, tools/strain_cards.py and farm-numbers.xlsx; the HTML game's
## b332 STRAIN and WEED tables). Everything here is tunable.
##
## Time: crops grow in GAME HOURS on the GameClock. The strain cards' "minutes on its own" are real minutes of
## daytime, and a day's daytime runs one game hour a real minute (20-minute day: 7 am-9 pm in 14 minutes), so a
## card's minutes are its game hours. Surviving a wave moves the clock on WAVE_HOURS, which makes each strain grow
## in the cards' wave counts (NL 4 h = 2 waves of 2.5 h, WW 15 h = 6 waves).
##
## Positions are the HTML game's units (x across, y down the screen); the backyard's are the HTML game's own.

## ---------------------------------------------------------------- the six strains
## name, short, type, tier, potency /10, price ($ a whole plant: each bud is price / buds), grow hours, waves (the
## card's, for the panel), buds a plant, seed price (0: can't be bought, only bred or dropped by raiders), buff
## waves, raid risk (index into RAID_RISK), the buff, and the card's effect line.
const STRAINS := [
	{"name": "Northern Lights", "short": "NL", "type": "Indica", "tier": 0, "potency": 4, "price": 40, "hours": 4.0,
		"waves": 2, "buds": 3, "seed": 10, "buff_waves": 1, "risk": 0, "effect": "Heals 2 health when you smoke it.",
		"buff": {"heal": 2}},
	{"name": "Sour Diesel", "short": "SD", "type": "Sativa", "tier": 1, "potency": 6, "price": 75, "hours": 6.0,
		"waves": 3, "buds": 3, "seed": 30, "buff_waves": 1, "risk": 1, "effect": "+25% run speed and +25% fire rate.",
		"buff": {"speed_mult": 1.25, "fire_rate_mult": 1.25}},
	{"name": "Granddaddy Purple", "short": "GDP", "type": "Indica", "tier": 1, "potency": 6, "price": 80, "hours": 6.0,
		"waves": 3, "buds": 4, "seed": 0, "buff_waves": 1, "risk": 1, "effect": "Take 40% less damage, but move 15% slower.",
		"buff": {"damage_taken_mult": 0.6, "speed_mult": 0.85}},
	{"name": "Blue Dream", "short": "BD", "type": "Hybrid", "tier": 2, "potency": 7, "price": 140, "hours": 9.0,
		"waves": 4, "buds": 3, "seed": 0, "buff_waves": 2, "risk": 2, "effect": "Enemies move and shoot at 70% speed.",
		"buff": {"enemy_speed_mult": 0.7}},
	{"name": "Acapulco Gold", "short": "AG", "type": "Sativa", "tier": 2, "potency": 7, "price": 150, "hours": 10.0,
		"waves": 4, "buds": 2, "seed": 0, "buff_waves": 2, "risk": 2, "effect": "Every kill drops double cash.",
		"buff": {"cash_mult": 2.0}},
	{"name": "White Widow", "short": "WW", "type": "Hybrid", "tier": 3, "potency": 9, "price": 300, "hours": 15.0,
		"waves": 6, "buds": 2, "seed": 0, "buff_waves": 2, "risk": 3, "effect": "+60% damage, and the screen goes trippy.",
		"buff": {"damage_mult": 1.6, "trippy": true}},
]
const TIER_NAMES := ["Common", "Uncommon", "Rare", "Legendary"]
const TIER_COLOURS := [Color8(190, 194, 204), Color8(96, 214, 110), Color8(96, 160, 255), Color8(255, 186, 64)]
## A buff's fields when nothing changes them (the fighting session multiplies by these).
const BUFF_NEUTRAL := {"speed_mult": 1.0, "fire_rate_mult": 1.0, "damage_taken_mult": 1.0, "enemy_speed_mult": 1.0,
	"cash_mult": 1.0, "damage_mult": 1.0, "trippy": false, "heal": 0}
## A potent bud (grown with Super Grow) makes its buff last this many waves longer.
const POTENT_BUFF_WAVES := 1

## ---------------------------------------------------------------- growing (game hours)
## The fraction grown where each stage starts: seedling, young, fan leaves, ready with buds (weedStage).
const STAGE_AT := [0.0, 0.2, 0.5, 1.0]
## A watering lasts this long; then the plant is dry (half speed, droops) and after DRY_WILT_HOURS dry it wilts
## (goes brown and loses a bud, once).
const WET_HOURS := 3.0
const DRY_WILT_HOURS := 2.5
const DRY_SPEED := 0.5
## A full can waters this many plants.
const CAN_SIZE := 8
## The clock moves on this much when a wave is survived.
const WAVE_HOURS := 2.5

## ---------------------------------------------------------------- fertiliser (bought at the shed, a bag a plant a harvest)
const FERTS := [
	{},   # 0: none
	{"name": "Basic", "short": "BASIC", "price": 10, "speed": 0.25, "buds": 0, "potency": 0, "icon": "fert_basic"},
	{"name": "Premium", "short": "PREMIUM", "price": 30, "speed": 0.5, "buds": 1, "potency": 0, "icon": "fert_premium"},
	{"name": "Super Grow", "short": "SUPER", "price": 80, "speed": 1.0, "buds": 1, "potency": 1, "icon": "fert_super"},
]
## Each extra potency point adds this much to a bud's price (farm-numbers.xlsx).
const POTENCY_PRICE := 0.15
## A frosty seed's plant sells for this much more.
const FROSTY_PRICE := 0.5

## ---------------------------------------------------------------- raids
## The chance, each wave, that raiders go for one growing or ready plant of each risk (Low, Medium, High, Very high).
const RAID_RISK := [0.04, 0.08, 0.14, 0.22]
const RISK_NAMES := ["Low", "Medium", "High", "Very high"]
## Raiders sent for each targeted plant.
const RAIDERS_PER_PLANT := 2
## Without the fighting session driving it (auto raids), each targeted plant is lost with this chance.
const AUTO_RAID_LOSS := 0.5
## A raider killed drops a seed with this chance (a strain of the raided plants' tier or one higher).
const RAIDER_SEED_DROP := 0.15

## ---------------------------------------------------------------- breeding (the table in the grow house, stage 2)
const RECIPES := [[0, 0, 2], [1, 1, 4], [2, 1, 3], [3, 4, 5]]   # parent, parent, makes (NL+NL GDP, SD+SD AG, GDP+SD BD, BD+AG WW)
const BREED_HOURS := 6.0         # ready after the next wave survived, or this many game hours, whichever first
const BREED_LUCKY := 0.05        # jumps a tier, or comes out frosty

## ---------------------------------------------------------------- the land (FARM.md: 2580 x 3080)
const LAND_W := 2580.0
const LAND_H := 3080.0
## The backyard's weed bed: the 8 holes in the yard art (WEED.holes), the reach to use one (WEED.reach).
const YARD_HOLES := [[1426, 174], [1571, 174], [1426, 302], [1571, 302], [1426, 430], [1571, 430], [1426, 558], [1571, 558]]
const HOLE_REACH := 48.0
## The plant art (44 x 64, its stem's foot at 21.5, 60) in world units (WEED.S).
const PLANT_SCALE := 1.25
## Where things are in the backyard (the HTML game's WEED table).
const CRATE := {"x0": 420, "y0": 1690, "x1": 492, "y1": 1724}       # the seed crate against the shed
const SELL := {"x0": 932, "y0": 948, "x1": 1208, "y1": 1036}        # in front of the garage's roller door
const TANK := {"cx": 1380, "cy": 1680, "d": 162}                     # round the water tank
const COMPOST := {"x0": 1520, "y0": 1560, "x1": 1638, "y1": 1728}   # the compost bin in the yard art
## The neighbour's block (stage 2): east of the yard's fence.
const N_BLOCK := {"x0": 1740, "y0": 60, "x1": 2560, "y1": 1880}
const N_GATE := {"x": 1708, "y": 1240}            # the gate in the east fence (once bought)
const N_SIGN := {"x": 1650, "y": 1150}            # the FOR SALE sign, in the yard by the fence
const N_PLOT_ORIGIN := Vector2(1840, 720)         # the 24 plots: 4 rows of 6
const N_PLOT_STEP := Vector2(120, 150)
const N_PLOT_COLS := 6
const N_PLOT_ROWS := 4
const GROW_HOUSE := {"x0": 2120, "y0": 140, "x1": 2500, "y1": 500, "h": 96}
const BREED_TABLE := {"x": 2310, "y": 560}
const SPRINKLER := {"x": 2140, "y": 1000}
## The paddock (stage 3): out the back, through the farm gate in the bottom fence.
const PADDOCK := {"x0": 40, "y0": 1920, "x1": 2540, "y1": 3040}
const P_GATE := {"x": 955, "y": 1882}
const P_SIGN := {"x": 1060, "y": 1830}
const P_ROWS := 12
const P_ROW_PLANTS := 10
## Plots on ploughed soil in the yard (the digging part, scripts/dig/, places them where you plant): zone "field",
## open while placed ("on").
const FIELD_PLOTS := 48
const P_ROW_X0 := 520.0
const P_ROW_DX := 150.0
const P_ROW_Y0 := 2080.0
const P_ROW_DY := 76.0
const TRACTOR_SHED := {"x0": 80, "y0": 2060, "x1": 380, "y1": 2380, "h": 80}
const SILO := {"cx": 220, "cy": 2620, "r": 90, "h": 220}
const P_TANK := {"cx": 220, "cy": 2860, "r": 80, "h": 80}

## ---------------------------------------------------------------- what things cost (first guesses; PLAN.md: the first
## extra land after about 3 game days)
const LAND_PRICES := {"neighbour": 2500, "paddock": 8000}
const UPGRADES := {
	"compost": {"name": "Compost bin", "price": 250, "needs": "", "what": "Every 3 harvests make a free bag of Basic."},
	"sprinkler": {"name": "Sprinkler", "price": 600, "needs": "neighbour", "what": "Waters the neighbour's plots for you."},
	"lights": {"name": "Grow lights", "price": 900, "needs": "neighbour", "what": "Neighbour's plots grow 25% faster."},
	"tractor": {"name": "Tractor", "price": 4000, "needs": "paddock", "what": "Plants, waters and harvests a whole paddock row."},
}
const COMPOST_PER_BAG := 3
const LIGHTS_SPEED := 0.25
## The stand-in wallet's starting cash (until the shared wallet is in).
const START_CASH := 50

static func strain(s: int) -> Dictionary:
	return STRAINS[s] if s >= 0 and s < STRAINS.size() else {}

static func stage_of(g: float) -> int:
	return 3 if g >= 1.0 else (2 if g >= STAGE_AT[2] else (1 if g >= STAGE_AT[1] else 0))

## What one bud of strain s sells for, by its quality (bit 1: potent from Super Grow, bit 2: frosty).
static func bud_price(s: int, q: int = 0) -> float:
	var st := strain(s)
	if st.is_empty():
		return 0.0
	var v := float(st.price) / float(st.buds)
	if q & 1:
		v *= 1.0 + POTENCY_PRICE
	if q & 2:
		v *= 1.0 + FROSTY_PRICE
	return v

## The breeding recipe's result for these two parents (either order), or -1.
static func recipe_for(a: int, b: int) -> int:
	for r in RECIPES:
		if (r[0] == a and r[1] == b) or (r[0] == b and r[1] == a):
			return r[2]
	return -1
