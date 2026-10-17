# Standing orders: the Godot build, overnight

The owner, 17 Oct 2026, about 10 pm their time (UTC+11), in their words: "I just want you to just make it all
and then we can just edit that in the morning... I've got a reset and I need to use it by the 23rd so just mash
it out."

- **Don't stop to ask.** Make every call yourself, the way that best fits the HTML game. Log each judgement call
  under "Decisions" below, for the morning.
- **Go milestone after milestone** (PLAN.md): 1 (the 3D world), 1.5 (the look pass), 2 (fighting), 3 (lobby
  life), 4 (online), 5 (extras), as far as it gets. Use workflows with several agents, a review step and a fix
  step each time. Credits aren't a concern.
- **Publish each finished milestone** to the site: the web export in `/home/user/Smashed-tv/godot-play/`
  (approved by the owner: "put it in its own folder on my site"), committed on the dev branch
  `claude/github-game-repo-tdm9yz` and pushed to main (fast-forward; merge main in first if it moved).
  Link: https://eflare17.github.io/Smashed-tv/godot-play/
- **Never touch `Smashed.html`** (the live HTML game) or `html-version-b331` (its saved copy).
- **Morning:** a summary for the owner: what's done, what's playable, what was decided for them, what's left.

## Decisions (for the owner to check in the morning)

- Views: top-down and first person both fully supported (owner skipped the question; can change).
- Bring everything across, cut nothing (owner skipped the question; can trim).
- Day length 20 real minutes (7 am-9 pm ~14 min, night ~6), owner said they didn't know; one tunable number.

## Progress

- Milestone 1 workflow wf_473b6552-01f started 10:24 UTC. Milestone 2 specs workflow wf_79888b3a-794 started
  10:35 UTC (writes godot/specs/).
- 10:54 UTC: an interrupt in the chat stopped every running agent (and the machine restarted at 11:24). Lesson:
  an interrupt/stop kills the background agents. 11:25 UTC: both workflows resumed (finished agents cached:
  characters, the weapons and enemies specs); the interrupted build agents carry on from their work folders.
- 11:58 UTC: M2 specs finished (godot/specs/: weapons, enemies_waves, gore_loot, modes_hud, README with gaps);
  sound recordings extracted (assets/sounds). M1: characters and world done, player nearly, tramp+Gothica
  building; then integrate, review, fix. Preview build at 12:10 UTC.
- 12:12 UTC: preview published: the integrator's first working build copied to godot-play/ and pushed to main
  (Pages deployed 1cf7ecf). M1 integrate step still running; then review, fix, and godot-play/ gets the final.
- 12:44 UTC: the owner asked for extra sessions: three started (fighting M2 on `claude/godot-fighting`, lobby life
  M3 on `claude/godot-lobby`, arcade cabinets on `claude/godot-arcade`; see PARALLEL.md). This session: finish M1,
  then 1.4, 1.5, merging them in, then online (M4). godot-play/ updated with the integrator's 12:29 build.
- 12:55 UTC: the owner asked for two more sessions to use a reset that expires soon: Lighting (1.4 day/night +
  1.5 look, `claude/godot-lighting`) and Farm (`claude/godot-farm`). This session: finish M1, merge, online.
  Half-hour resume checks (:27 and :57) restart anything stopped by a usage limit.
- 12:57 UTC heartbeat: M1 integrate still running; fighting pushed its simulation (weapons, enemies, waves, gore, money, Protect Gothica, headless tests); lobby pushed its framework; arcade, lighting, farm setting up.
- 13:43 UTC: lobby, arcade, farm now on Sonnet sessions (owner's request, to stretch usage); IDs in PARALLEL.md.
- 13:50 UTC: arcade merged (Status: done) with Arcade.install in main.gd; godot-play/ updated (M1 so far + arcade). NOTE: if the M1 fix step copies main.gd back, re-add Arcade.install(self).
- 14:05 UTC: farm merged (Status: done), FarmInstall.install after Arcade in main.gd; godot-play/ updated (M1 + arcade + farm). Archived: farm Sonnet session done.
- 14:20 UTC: M1 finished (review + 23 fixes: 120 Hz physics clock, layers, input actions, touch controls). Farm HUD fix merged. godot-play/ updated (M1 final + arcade + farm). Fighting, lighting, lobby told to merge the dev branch (new shared conventions in PLAN.md).
- 14:35 UTC: fighting merged (Status: done), FightInstall.install after FarmInstall; godot-play/ updated (M1 + arcade + farm + fighting). Fighting session idle/done.
- 14:45 UTC: lobby life merged (Status: done), LobbyLife.install last in main.gd; lobby life and arcade join group lobby_only, which Fight hides at the start of a run (they showed in the arena). godot-play/ updated (M1 + arcade + farm + fighting + lobby).
- 15:00 UTC: lighting merged (by its own session, into dev and main) and live. All five parts done. Online (M4) session started (claude/godot-online). Fighting session doing the HUD/one-wallet polish.
- 15:05 UTC: the owner put VR on hold (don't start it until they say "do VR").
- 15:35 UTC: merged the HUD/one-wallet polish (fighting) and the mirror fix (lobby); godot-play/ updated.
