# The farm (planned)

Smashed gets an outside area with a farming side: grow, harvest and sell crops between runs, and spend the
cash on guns, upgrades and more land. Agreed with Tyson on 17 Oct 2026; nothing is built in the game yet.

## How it works
- **Loop:** plant, water, wait, harvest, sell (at the garage), spend.
- **Growth:** real time while the game is open, slowly (about 5 minutes for a crop on its own), and every wave
  you clear gives every crop a big boost. Fighting makes farming go faster.
- **Co-op:** one shared farm. It's the host's, saved on the host's machine, like Gothica. Whoever sells a crop
  gets the cash.
- **Raids:** sometimes enemies come for the crops during a wave (like Protect Gothica, but the harvest).
  Rarer strains get raided more.

## The land: three stages (layout: 2580 x 3080 game units)
1. **Your backyard (free).** Around the house: patio, driveway and garage (sell here), a weed bed of 8 plants and
   a potato patch, both done by hand, a lawn with a trampoline, a shed, garden beds, a water tank. A farm gate in
   the bottom fence. Art: made in Gemini, toned to match the house, with the weed bed left as empty holes (the game
   draws the plants).
2. **The neighbour's block (buy it).** To the right. The fence comes down when bought. Their house becomes a
   grow house; big weed plots (24 plants) and a sprinkler so you're not watering by hand. A FOR SALE sign till then.
3. **The paddock (buy it, then buy a tractor).** Out the back. 12 long rows the tractor plants or harvests one
   whole row at a time, a tractor shed, a silo and water tank, a dirt track.

Make each stage's art as its own picture (one picture of everything is too blurry at game size). Gemini won't draw
cannabis, so maps get empty dug beds and the plants are our own pixel art (tools/strains.py).

## Crops
- **Potatoes:** spud gun ammo (already in the game, growing in the arena).
- **Weed:** sells for cash. Several strains:

| Strain | Type | Tier | Effect when smoked at the bong before a run |
|---|---|---|---|
| Northern Lights | Indica | Common | Small health boost |
| Sour Diesel | Sativa | Uncommon | Run and fire faster |
| Granddaddy Purple | Indica | Uncommon | Slower, but take less damage |
| Blue Dream | Hybrid | Rare | Slow-mo: enemies slow down |
| Acapulco Gold | Sativa | Rare | Double cash from kills |
| White Widow | Hybrid | Legendary | Big damage boost, plus the mushroom's trippy first person |

Stronger strains sell for more and take longer to grow. The buff lasts the next wave or two. New strains: buy
seeds, rare seeds dropped by raiders, and later breeding (cross two plants).

## Art
- `tools/strains.py` draws every strain's 4 growth stages (seedling, young, full fan leaves, ready with buds) as
  pixel art: indicas short and bushy with broad leaflets, sativas tall with thin leaflets, hybrids in between,
  each with its own leaf, tip and bud colours, orange hairs, and frost on the frosty ones.

## Strain cards
`tools/strain_cards.py` makes a stat card for each strain (plant, potency, price, grow time, buds per plant, buff
length, raid risk, effect, fun fact). The game numbers in it are a first go and all tunable:

| Strain | Potency | Sells for | Grows in | Buds | Buff | Raid risk |
|---|---|---|---|---|---|---|
| Northern Lights | 4/10 | $40 | 4 min or 2 waves | 3 | 1 wave | Low |
| Sour Diesel | 6/10 | $75 | 6 min or 3 waves | 3 | 1 wave | Medium |
| Granddaddy Purple | 6/10 | $80 | 6 min or 3 waves | 4 | 1 wave | Medium |
| Blue Dream | 7/10 | $140 | 9 min or 4 waves | 3 | 2 waves | High |
| Acapulco Gold | 7/10 | $150 | 10 min or 4 waves | 2 | 2 waves | High |
| White Widow | 9/10 | $300 | 15 min or 6 waves | 2 | 2 waves | Very high |

## Speeding crops up (agreed 17 Oct)
- **Water (free):** watered = full speed (dark soil, a drop icon); dry = half speed and droops; left dry too long it
  wilts and loses a bud. Fill the watering can at the water tank; the stage 2 sprinkler does it for you.
- **Fertiliser (bought at the shed, one bag per plant per harvest):** Basic $10 = 25% faster; Premium $30 = 50%
  faster, +1 bud; Super Grow $80 = twice as fast, +1 bud, +1 potency.
- **Later:** grow lights in the grow house (plants keep going between waves); a compost bin that turns old plants
  into free Basic fertiliser.
- All of it stacks with the wave boost. The numbers say Super Grow loses money on cheap strains and pays well on
  the good ones, which is the point.

## Breeding (agreed 17 Oct)
Cross two seeds at a breeding table in the grow house; the new seed is ready after the next wave.
Two seeds of one tier make one of the next (so a White Widow takes 8 Northern Lights seeds the long way):

| Parent 1 | Parent 2 | Makes |
|---|---|---|
| Northern Lights | Northern Lights | Granddaddy Purple (indica stays indica) |
| Sour Diesel | Sour Diesel | Acapulco Gold (sativa stays sativa) |
| Granddaddy Purple | Sour Diesel | Blue Dream (indica + sativa makes a hybrid) |
| Blue Dream | Acapulco Gold | White Widow |

A small lucky chance (5%) that a cross jumps a tier or comes out as a special frosty seed that sells for more.
Seeds you can buy: Northern Lights and Sour Diesel (prices still to decide; first guesses $10 and $30).

All of these numbers live in `farm-numbers.xlsx` (water, fertiliser, strains, a grow and profit calculator,
breeding, upgrades); change the yellow cells and the rest works itself out.
