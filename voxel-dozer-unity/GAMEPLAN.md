# Mine game: the plan

One page. A new idea gets checked against this page. It either goes on the **Later** list, or it swaps
something out of **In**. Nothing gets built that isn't on here.

Status: agreed with the owner, 16 Nov 2026. Items marked *(suggested)* are Claude's, still open to change.
Numbers (litres, prices, speeds) are starting points to tune once it's playable.

## The game in one line

Dig out an old caved-in gold mine, haul it out by cart for money, and climb from a pick and shovel to
jackhammers, a suction backpack and carts that run themselves. Play it with up to 3 friends.

## The loop

1. Dig: break ground (pick, later the jackhammer), move it (shovel, later the backpack).
2. Fill the cart and get it out of the mine (push it, later ride it, later send it).
3. It tips at the dump and you get paid. Everything pays a little; gold pays far more.
4. Open the upgrade tree (one key), click an upgrade, and it works straight away. There's no store.
5. Dig faster and deeper. Repeat.

**Feel:** like incremental games. The first upgrade comes within a couple of minutes, then each one
takes a bit longer. Every upgrade should make a difference you can feel at once.

## Money and gold

- **The hopper** at the end of the rails: E tips the cart into it, and it sorts the load. Soil, clay,
  rock and quartz are **sold on the spot**: **1 coin per 10 litres**. A full starting cart of dirt is
  about 100 coins.
- **Gold is kept** in the team's **gold store**. The **gold buyer's shed** by the mine entrance buys it
  (E at the counter sells all of it), at **about 50 times** the price of dirt. Gold you don't sell is
  what machinery costs.
- Gold is rare at first (flecks in the quartz seam in the rock), so dirt pays for the early upgrades
  and gold takes over deeper in.
- **Levels cost money.** **New machinery costs money plus gold**, so the more gold you find, the more
  machinery you can unlock.
- **The dump** is at the end of the rails, **about 8 m straight out of the mine door** (the owner's call,
  19 Nov; it used to be 50 m away, down by the road). `DumpOut` in `SiteProps.cs`.

## The upgrade tree

Each tool goes up in levels (money), then steps up to a new machine (money plus gold).

| Branch | Levels (money) | Then the next machine (needs gold) |
|---|---|---|
| **Breaking** | Pick 1–5: a bigger chunk each hit, faster on rock | **Jackhammer**, with its own levels |
| **Moving dirt** | Shovel 1–6: from today's ~120 L a scoop to ~350 L, swings 1.6× faster | **Backpack**, with 8 levels |
| **Hauling** | Cart 1–2: bigger (1,000 L, then more) | **Motor cart** (ride it out with a button), bigger again, then **Automatic** (one button sends it out full, it tips itself, and comes back empty) |

**The backpack's 8 levels** grow from 200 L and slow to 1,000 L and about 4× faster. Its levels follow
the ground, because heavier material needs more suction:
- Level 1: soil
- Level 3: clay
- Level 5: rock rubble
- Level 7: quartz
- Level 8: gold

Anything heavier than your level only **trickles in slowly** *(suggested)*. It doesn't stop dead.

**Prices** *(suggested)*: the first upgrade is about 40 coins. Each level costs about 1.6× the last.
Machines also cost gold.

**Selling back:** any player can sell back the newest upgrade in a branch for a full refund. That's the
undo. The tree shows which player bought each upgrade.

### Motor cart: choices made

Built 19 Nov 2026 *(suggested, all easy to change)*:
- **Where it sits:** in the Hauling branch after Cart 2. Cart levels 3–5 are the motor cart (Motor cart,
  Motor cart 2, Motor cart 3), the same trick as the jackhammer, so saves didn't change.
- **Price:** the unlock is 800 coins (it was 800 coins + 10 L of gold until the 22 Nov tuning, which made it
  coins only so there's something to buy while digging through to the gold). Motor cart 2 is 400 coins, Motor cart 3 is 640.
  (`Steps` in `Upgrades.cs`.)
- **Speed:** 3, 4, then 5 m/s (pushing is 2). It speeds up and slows down over about a second.
  (`MotorSpeed` in `Upgrades.cs`, `MotorAccel` in `MineCart.cs`.)
- **Size:** the motor cart keeps the Cart 2 tub (1,500 L). The plan's "bigger again" is the **Bigger cart**
  (built 22 Nov: 2,000 L, 900 coins), then the **Automatic cart** (built 22 Nov: G sends it to the hopper and
  back, 1,200 coins + 20 L gold). See MORNING_REPORT.md.
- **Controls:** **R** at either end of the cart gets on. **W** drives it out towards the dump, **S** back
  into the mine. **R** (or E away from the dump) gets off, onto the track behind it. At the dump, **E**
  tips it and he stays on, ready to drive back in. He can still push it by hand with E as before.
- **Where he rides:** on a steel footboard on the back end (the mine end), hands on the push bar.
- **Stops:** the same as pushing: rubble on the track and the ends of the rails. Backing in, it also
  stops early enough that he isn't pushed into the rubble behind him.
- **The look:** an orange motor box with fins and an exhaust stub on the front end, plus the footboard.
  Both only show once it's bought.
- **Tested by** `BulldozerBuilder.MotorCartTest`.

## Build order

1. **The dump and money.** Tipping a cart at the dump pays into the pot, with a money display.
2. **The upgrade tree screen.** One key opens it, with the branches, levels, prices, buying, selling
   back and "bought by".
3. **The tools get their levels:** pick, shovel and cart. Today's shovel and backpack become level 1
   of their branches, and the backpack is locked until the shovel is maxed.
4. **Gold:** machines cost gold, and the backpack's suction follows the ground.
5. **New machines:** the jackhammer, then the motor cart, then the automatic cart.
6. **Multiplayer** on Wi-Fi (see below).
7. **Play and tune** the prices and pacing.
8. **A phone check-in.**

The owner chose the upgrades before multiplayer, so the game is fun to play sooner. To keep the later
rework small, every action that changes the game (dig, scoop, suck, tip, buy, sell back) goes through
one place in the code from the start, ready to be sent to other players.

## Multiplayer

- One player hosts and up to 3 join (**4 players**). The host's game is the real one.
- The ground is never sent whole (it's 528 MB). Every game builds the same starting mine from the same
  recipe, the same way saving does. After that, only the changes get sent.
- The host runs the falling dirt, and the others are told where the clods are and where they settle.
- **One shared pot of money and one shared upgrade tree.** Solo play works the same way.
- Hand-written on C#'s built-in network connections, like Smashed, with nothing to install.
- **Same Wi-Fi first, then the internet.** The connection layer is kept separate from the game, so
  internet play gets added by swapping that layer. It'll need a go-between service or an open router
  port, chosen when we get there.
- **PC and phone together.** Built on PC first, with a check-in on the phone now and then. Quality
  scales from the owner's RTX 4090 down to the S25 Ultra. The phone needs touch controls and Unity's
  Android build support, which is an install and needs an OK.

## Later (not in version 1)

- **Version 2 machinery** (costs gold): a mini digger, the Dingo, the dozer as an earned machine. The
  dozer stays drivable for testing until then.
- Two carts with a passing spot
- The filter machine and gold sorting
- A shop building
- Enemies (voxel style like Smashed, with limbs that come off)
- Finishing a mine, then the next shaft with its machinery
- Supports and shoring, deeper and harder layers, the tunnel sloping down
- Each player upgrading their own tools from the shared pot
- Washing the dozer

## Open questions

- None blocking. The numbers get tuned in step 7.
