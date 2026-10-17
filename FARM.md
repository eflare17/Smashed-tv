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
