# Morning summary (18 Oct)

Play it: https://eflare17.github.io/Smashed-tv/godot-play/ (your HTML game is untouched at /Smashed.html).

## Done and playable
- **The 3D world**: lounge, bedroom, backyard; top-down (Z zooms, starts at 1x and remembers) and first person (V).
- **Day and night**: 20-minute days, sun, sky, lamps, shadows; sleep in the bed to skip to 7 am.
- **Fighting**: modes (arrows at the top, Enter to start), waves, all weapons (1-6), gore, cash, Protect Gothica, Tab for controls.
- **Lobby life**: pool and dive tower, gym, bell rope, bong and trip, blackjack with Gothica, mirror and hair, shirt editor,
  wardrobe, bed, mushroom, slot machine, barbecue, Gothica wandering, watching, talking, being carried.
- **Arcade**: Sand Miner, Brick Brawl, Spud Snake, and the Mega Drive / SNES cabinet (add games from your device).
- **Farm**: crop beds in the yard, six strains, 4 growth stages, water, fertiliser, harvest, sell, smoke for buffs, raids.
  Clearing a wave moves the clock on 2.5 hours, so fighting grows the crops.
- **One wallet** for everything, saved.
- **Online co-op**: ONLINE (O) -> Host gives a room code, your friend Joins with it (same free PeerJS server as the HTML game).
- **Phones**: full screen button, portrait and landscape layouts, touch controls; gamepad support throughout.
- **Sound** on/off button (and F9).

## Decided for you (change any of them)
- Everything from the HTML game came across; both views fully supported.
- A day is 20 real minutes.
- No vending machine in the lobby (the HTML game only has it in runs; one in the lobby blocked the Bricks cabinet).
- Lobby, arcade and farm were built on Sonnet to stretch your usage; fighting, lighting, online on Opus.
- VR is on hold until you say "do VR".

## Known issues / not yet done
- Online has only been tested between two browsers on one machine: you and your friend are the first real test.
- The emulator cabinet hasn't been tried with a real ROM.
- Raids are rolled when a wave ends (no raiders walk in to fight yet); the White Widow "trippy screen" isn't drawn.
- Portrait phones open at 1x, which shows the whole house small; press ZOOM for closer.
- The Google Drive games folder needs the OAuth client ID from you.

## What's left (when you want it)
- Your notes from playing: send anything broken or that feels off.
- VR on your Quest ("do VR").
- Vesper, once you have her sprite sheets.
