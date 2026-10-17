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
