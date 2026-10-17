# The farm: integration note (branch `claude/godot-farm`)

## Handoff (17 Oct, for the next session)

**Done and working:** everything listed under "What works" below, all pushed on `claude/godot-farm`. Nothing is
half-done: there's no uncommitted work. 76 logic checks and 40 in-game self-test checks pass, and the web export
renders and takes real clicks.

**Files** (all in the farm session's own folders):
- `scripts/farm/farm_data.gd`: every number.
- `farm_state.gd`: the rules. No nodes, so the headless tests drive it directly.
- `farm.gd`: the Farm node: the clock, the wallet, saving, and the hooks for the other sessions.
- `farm_spot.gd`: the Interactables.
- `farm_plot_view.gd`: the plant and soil pictures, with their shaders.
- `farm_world.gd`: the props, the land stages and the fences.
- `farm_ui.gd`: the panel, the status strip, the hints, toasts, floaters, the held can and the sounds.
- `farm_install.gd`: the entry point.
- `game_clock_standin.gd` and `farm_wallet_standin.gd`: stand-ins until the real clock and wallet are merged.
- `assets/farm/make_sprites.py`: makes the pictures and the WAVs from `tools/strains.py`.
- `scenes/farm/farm_test.tscn` with `test/farm/farm_test_scene.gd`: the farm inside the real game, with demo options.
- `test/farm/test_farm_logic.gd`: the headless logic tests.

**Next steps, in order** (all optional polish; the main session only needs the install line):
1. When the Lighting GameClock is merged, run both tests against it. Delete the stand-in if you like.
2. When the fighting session lands, wire its wave start and end to `on_wave_started`, `raid_result` and
   `on_wave_survived`, then set `auto_raids = false`.
3. Co-op snapshot (M4): send `state.to_dict()` from the host, and turn the guest's E into requests to
   `Farm.spot_act`.
4. Real art for the neighbour's block and the paddock (they're boxes and flat colours for now).
5. Tune `farm_data.gd` by playing.

**Gotchas:**
- `-s` test scripts get no autoloads, so `GameData` isn't there. The farm logic preloads
  `res://scripts/game_data.gd` for its static helpers. Anything that needs the real game goes in the test scene's
  `selftest` instead.
- In a `-s` script's `_init` the tree isn't running yet: the node tests run on the first `process_frame`.
- The clock's hour wraps at midnight while the day number turns at 7 am, so growth uses the hour's step forward
  mod 24 (`Farm.sync_clock`). Never use `day * 24 + hour`.
- `FarmState.grow()` must not emit `changed` every frame. Doing so rebuilt the panel constantly and swallowed
  clicks; it emits `grew` every frame and `changed` only on visible changes.
- Headless runs have no window size, so mouse events can't be tested there. Test clicks with a Playwright click
  in the web build.
- Pad A wasn't in `ui_accept` in this project: `FarmUI` adds it, plus B and the d-pad.
- Don't run two Godots on one folder. Test in a scratch copy: tar the `godot/` folder over, keeping `.godot`
  (rsync isn't installed).

**How to test:**
- Setup: `bash godot/tools/setup_godot.sh`, then `godot --headless --path <copy> --import`.
- Logic: `godot --headless --path <copy> -s res://test/farm/test_farm_logic.gd` should end
  "FARM LOGIC: 76 passed, 0 failed".
- In-game: `godot --headless --path <copy> --fixed-fps 60 res://scenes/farm/farm_test.tscn -- selftest` should end
  "SELFTEST DONE 40 passed, 0 failed".
- Web:
  1. In the copy only, set `run/main_scene="res://scenes/farm/farm_test.tscn"` in `project.godot`.
  2. Export with `--export-release "Web" build/web/index.html`.
  3. Serve the copy and open `build/web/index.html` with options, e.g. `?farmdemo&zoom=0&at=1500,420`. The other
     options are `farmall`, `fp&look=-1.57`, `panel=shop|bag|sell|land|breed`, `waves=N` and `smoke=S`.
  4. Screenshot with `godot/tools/gd_shot.mjs`.

The farm from `../FARM.md`, running on the game clock (PLAN.md 1.4). Everything is in `scripts/farm/`,
`scenes/farm/`, `assets/farm/`, `test/farm/` and this note; nothing else was touched.

## What works

Tested in the real web export (screenshots, a real mouse click in Chromium) and headless: `test/farm/test_farm_logic.gd`
(76 checks) and the in-game self-test, which plays the loop through the real player's E and the panel (40 checks).

- **The backyard weed bed:** the 8 holes in the yard art (the HTML game's `WEED.holes`). E at an empty hole plants
  (the seed you bought or picked last, frosty ones first); the soil fills in, dark and damp when it's watered.
- **The six strains, four stages each:** the pictures come from `tools/strains.py` (`assets/farm/strains.png`, made by
  `assets/farm/make_sprites.py`). Seedling, young, fan leaves, ready with buds. They stand up in first person and
  lean back to lie flat seen from above, like the characters, and sway from the foot. Dry plants droop and go
  yellow with a drop bobbing over them. Wilted ones droop further and go brown. Ready ones glint.
- **Growth on the game clock, in game hours:** a card's "minutes" are its game hours (a daytime game hour is one
  real minute). Ticking, `advance_hours` and `sleep_to_morning` all count; the farm reads how far the clock moved
  (crossing midnight included).
- **Watering:** E at the water tank fills the can (8 waterings) or leaves it. E at a thirsty plant waters it.
  Watered, a plant grows at full speed for 3 h. Dry, it grows at half speed. After 2.5 h dry it wilts and loses a
  bud (once). You see the can in his hand top-down and at the bottom of the screen in first person.
- **Fertiliser** (bought at the crate; one bag a plant a harvest): Basic +25% speed; Premium +50% and +1 bud;
  Super Grow 2x speed, +1 bud and +1 potency (potent buds sell for 15% more, and their buff lasts a wave longer).
  E fertilises a growing plant with your picked bag (watering comes first when both apply).
- **A wave survived moves time on:** `Farm.on_wave_survived()` calls `GameClock.advance_hours(2.5)`. With 2.5 h a
  wave, every strain grows in exactly its card's wave count (NL 2, SD and GDP 3, BD and AG 4, WW 6).
- **Harvest:** E at a ready plant puts its buds in your bag.
- **Selling:** E at the garage's roller door opens the sell tab. "Sell all" is focused first, and you can sell one
  strain at a time to keep some for smoking. The money goes into the wallet (one wallet, see Hooks).
- **Smoking:** "SMOKE" in the bag (Tab / I / pad Y / the BAG button), or the bong through
  `Farm.smoke(player, strain)`. This starts the strain's buff, exposed as data and a signal (see Hooks).
- **Raids by risk:** each wave, each planted plant is targeted with its strain's risk (Low 4%, Medium 8%, High 14%,
  Very high 22%). The fighting session can run the raid (raiders sent, `raid_result(escaped)`, seeds dropped by
  killed raiders). Until it does, the farm settles raids itself on a wave survived: each target is lost 50% of the
  time, and there's a chance of a dropped rare seed. A toast says what happened.
- **The land (FARM.md's three stages):**
  - **Stage 2, the neighbour's block:** a FOR SALE sign in the yard by the east fence ($2,500), then a gate. It has
    24 plots, their house as the grow house, the breeding table, a sprinkler (an upgrade that keeps those plots
    watered) and grow lights (an upgrade: +25% speed there).
  - **Stage 3, the paddock:** a FOR SALE sign by the bottom fence's farm gate ($8,000). It has 12 long rows of 10
    plants, the tractor shed, a silo, a tank and a dirt track. With the tractor ($4,000), E at a row plants, waters,
    fertilises or harvests the whole row.
  - The new land has its own fences, so each part is reached through its gate.
- **Breeding** at the table (FARM.md's recipes): NL+NL makes GDP, SD+SD makes AG, GDP+SD makes BD, BD+AG makes WW.
  The seed is ready after the next wave survived or 6 game hours. A 5% lucky cross jumps a tier or comes out frosty
  (frosty sells for +50%).
- **The compost bin** ($250 upgrade, the bin already in the yard art): every 3 harvests make a free bag of Basic.
- **Every action is an Interactable** (`FarmSpot extends Interactable`), so E, the pad's A and the HUD's round
  button work in both views. A line or two about what's in front of you (strain, % grown, hours to go, dry or
  watered; the can; prices) shows under the E prompt in both views.
- **The farm panel** is all buttons:
  - Mouse and touch: click or tap.
  - Gamepad: the d-pad or stick moves, A presses, B closes, Y opens the bag.
  - Keyboard: arrows, Enter or Space, Esc or Tab to close.
  - It opens with the first useful button focused (pink ring). The player stands still and the mouse is freed
    while it's open; the mouse is captured again on closing in first person.
  - Tabs: bag (pick the seed and the bag E uses, smoke, the can, totals), seeds & fertiliser, sell, land &
    upgrades, breeding.
- **Status strip** under the character picker: cash, seeds, buds, the can, bags, the buff with waves left, and the
  day and time.
- **Sounds** (the HTML game's farmFx, made in code as WAVs): planting, snipping, watering, the can filling, buying,
  cash, smoking.
- **Saving:** the whole farm: plots, each player's bag, land, upgrades, compost, the breeding table, the buff and
  totals. Web builds use localStorage `smashed-godot-farm`; desktop builds use `user://smashed-farm.json`. It
  saves within a couple of seconds of any action, and every 10 s while things grow. The stand-in clock's time and
  the stand-in wallet's cash ride along in the same save; the real ones should save themselves.
- **Co-op ready:** every bag is per player id (`Farm.pid_of(player)`: 0 the host; a guest's player node carries
  `farm_pid` 1 as a meta or property). There is one shared farm.

## How to install it (main.gd)

Add one line at the end of `main._ready()`, **after** the Lighting install (so the real GameClock is already at
`/root/GameClock`; if it isn't there, the farm adds its stand-in):

```gdscript
	FarmInstall.install(self)
```

This adds `main/Farm`, `main/FarmWorld`, `main/FarmUI` and `main/FarmBounds`, and `/root/GameClock` and
`/root/Wallet` stand-ins if they're missing. The test scene `scenes/farm/farm_test.tscn` does exactly this around
`scenes/main.tscn`.

## Hooks for the fighting session

Get the farm with `Farm.instance` (or `get_tree().get_first_node_in_group("farm")`). Check it isn't null: the
farm may not be installed.

```gdscript
# a wave starts: maybe a raid on the crops
var raid := Farm.instance.on_wave_started(wave)      # {} or {targets: [plot idx], raiders: n, strains: [..]}
if not raid.is_empty():
	spawn_raiders(raid.raiders)                      # like Protect Gothica, but for the harvest
# a raider killed: maybe a seed (already added to the host's bag; spawn a pickup sprite if you like)
var s := Farm.instance.raider_killed()               # strain or -1
# the wave over: how many raiders got away (two take a plant). Then:
Farm.instance.raid_result(escaped)
Farm.instance.on_wave_survived(wave)                 # moves the clock on 2.5 h, counts the buff down, readies a bred seed
```

Once the fighting runs raids, set `Farm.instance.auto_raids = false`. (It also turns itself off for any wave where
`on_wave_started` was called.)

**The buff** (smoking a strain): `Farm.instance.buff_changed(buff: Dictionary)` fires when one starts, counts down
or ends (`{}` when it ends). You can also read `Farm.instance.active_buff()` or
`Farm.instance.buff_value("speed_mult")`. Fields, with their neutral values:

| key | neutral | who has it |
|---|---|---|
| `speed_mult` | 1.0 | Sour Diesel 1.25, Granddaddy Purple 0.85 |
| `fire_rate_mult` | 1.0 | Sour Diesel 1.25 |
| `damage_taken_mult` | 1.0 | Granddaddy Purple 0.6 |
| `enemy_speed_mult` | 1.0 | Blue Dream 0.7 (enemies move and shoot slower) |
| `cash_mult` | 1.0 | Acapulco Gold 2.0 (double cash from kills) |
| `damage_mult` | 1.0 | White Widow 1.6 |
| `trippy` | false | White Widow (the mushroom's trippy first person: the lobby session's effect) |
| `heal` | 0 | Northern Lights 2 (heal once, when `smoked` fires) |

Also on the buff: `strain`, `name`, `waves` (left), `potent`. Use `smoked(pid, strain, buff)` for one-off effects
(heal, the trippy screen starting). Buffs last 1 or 2 waves (+1 for a potent bud) and count down on
`on_wave_survived`.

## Hooks for the money and the trading game

- **One wallet.** The farm uses whatever node is at `/root/Wallet` (or `Farm.instance.wallet = node`), duck typed:
  `get_cash() -> int`, `add_cash(n: int, why: String)`, `spend_cash(n: int, why: String) -> bool`, and ideally
  `signal cash_changed(cash: int)`. The stand-in (`scripts/farm/farm_wallet_standin.gd`, starts at $50) is exactly
  that. When the shared wallet exists (wave cash, coins), give it those three functions or set `Farm.instance.wallet`
  to it. The farm only keeps the stand-in's cash in its own save.
- **Market days.** `Farm.instance.set_market_prices({strain_index: multiplier})` changes what the garage pays (the
  panel shows "market x1.30"). The trading game would call it on `GameClock.day_started`.
- **Selling elsewhere.** `Farm.instance.state.take_buds(pid, strain, mults)` takes buds out of a bag and returns their
  value (the trading game can buy stock this way). `Farm.instance.sold(pid, amount)` fires when the garage buys.
  `FarmData.bud_price(strain, quality)` is the base price.
- **The bong (lobby session).** `Farm.instance.smoke(player, strain)` returns the buff (`{}` if they have no bud of
  it). `Farm.instance.state.bud_count(pid, strain)` says what they can smoke.

## Input actions added (in code, at startup)

- `farm_bag`: Tab, I, pad Y. Opens and closes the bag.
- The panel's pad controls: `ui_accept` gets pad A, `ui_cancel` pad B, and `ui_up` / `ui_down` / `ui_left` /
  `ui_right` the d-pad, each only if missing.
- Touch: the BAG button (bottom left) and the HUD's own round E button.

## Contract changes wanted

1. **WorldBuilder: take a fence down.** FARM.md says the fence comes down when you buy the neighbour's block. The
   world's fences are one merged mesh and one body, so the farm can't remove a piece; meanwhile there's a gate you
   E through (it moves you to the other side). Wanted: `WorldBuilder.open_fence(rect: Rect2)` (or a
   `lobbyAreas` entry for the new land), which the farm would call on buying.
2. **The yard's seed crate as a solid in `game_data.json`.** The HTML game has it in `YARD_SOLIDS` from b332; the
   Godot data is b331. The farm builds the crate and its collision itself, so nothing breaks.
3. **The real GameClock:** keep exactly the PARALLEL.md shape. The farm uses `day`, `hour`, `advance_hours`,
   and duck-types the rest. One note: the stand-in turns the day number at 7 am; the farm copes either way.
4. **Camera bounds.** main keeps the top-down camera inside `worldW x worldH` (2003 x 1998). Out on the new land,
   `FarmBounds` widens `rig.bounds` to the whole farm (2580 x 3080) and puts it back in the yard. If main ever
   manages bounds itself, fold this in.
5. **A shared wallet** with the three functions above (PLAN.md's one wallet).

## Decisions (for the owner)

- **Time:** a strain card's "minutes on its own" became game hours (one daytime game hour is a real minute at the
  20-minute day). A wave survived is 2.5 game hours, so the cards' wave counts come out exactly.
- **Water:** a watering lasts 3 game hours (the HTML game's 3 minutes). Plants wilt after **2.5 h dry** (the HTML
  game says 2 minutes). With time moving on per wave, 2 h made a plant watered once wilt on the very wave it ripened.
- **A night's sleep** moves about 10 game hours, so dry plants wilt overnight unless you have the sprinkler (stage 2).
  That's a reason to buy it; tune `WET_HOURS` / `DRY_WILT_HOURS` in `farm_data.gd` if it's too harsh.
- **Prices** are first guesses aimed at the first land after about 3 game days (PLAN.md):
  - Land: the neighbour's block $2,500, the paddock $8,000 (after the neighbour's).
  - Upgrades: the tractor $4,000, the sprinkler $600, grow lights $900, the compost bin $250.
  - Seeds: NL $10, SD $30. Fertiliser: $10 / $30 / $80. The stand-in wallet starts with $50.
- **Grow lights:** FARM.md's "plants keep going between waves" means nothing when everything grows on the clock,
  so they became +25% speed on the neighbour's plots.
- **The shop is one crate** against the shed (FARM.md: seeds at the crate, fertiliser at the shed): E opens a panel
  instead of each bin buying one seed. The panel has six strains and three bags; the HTML crate had two bins.
- **Selling** opens the sell tab (one more press than the HTML game's E-sells-everything), so you can keep buds to
  smoke.
- **Smoking:** possible from the bag as a joint as well as at the bong (the lobby session owns the bong). One buff
  at a time; a new one replaces the old.
- **Raids:** without the fighting session, the farm settles them on a wave survived: half the targets are lost, with
  a chance of a dropped seed. With it, raiders who escape take the plants (two raiders per plant).
- **Seeds:** GDP, BD, AG and WW seeds can't be bought, only bred or dropped by raiders (FARM.md).
- **Paddock rows:** the tractor waters a row from its own tank (free), so no can is needed there.
- **The neighbour's block** gets a gate in the east fence instead of the fence coming down (contract change 1).
- **The potato patch isn't in:** potatoes are spud gun ammo, which is the fighting session's.
- **Co-op:** each player has their own bag; whoever sells gets the cash (as in the HTML game). There is one shared
  farm, saved on the host.

## What's left

- Co-op over the network (M4): pack the state (`state.to_dict()`, or a compact snapshot like the HTML game's
  `farmPack`) into the host's snapshot. The guest's E should come in as a request to `Farm.spot_act`.
- Raiders really coming into the yard (the fighting session), and a pickup sprite for dropped seeds.
- Real art for the neighbour's block and the paddock (FARM.md: each stage as its own picture, made in Gemini). For
  now they're flat ground and boxes: grow house, breeding table, tractor shed, silo, tank, tractor. The fences are
  plain boxes.
- The tractor driving: right now it's E at a row's end.
- Applying the buffs (fighting) and the trippy screen (lobby's mushroom effect).
- Tuning every number in `scripts/farm/farm_data.gd` by playing.
