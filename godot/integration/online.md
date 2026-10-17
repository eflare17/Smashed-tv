# Online (milestone 4): integration note

Status: done (tested: two headless games over ENet, all checks; two Chromium pages over PeerJS with a local broker, all 22 checks of the earlier drive; screenshots looked at).

Branch `claude/godot-online`. Files: `scripts/net/` (net.gd, net_transport.gd, peerjs_transport.gd,
enet_transport.gd, net_codec.gd, net_mirror.gd, net_menu.gd), `test/net/`, this note; small hooks in
`scripts/main.gd` and `scripts/combat/fight.gd` (listed under Install).

## What works

- **Host and join by a room code**, like the HTML game: 4 letters from its alphabet (no O/0, no I/1). The
  ONLINE button (bottom left, above BAG), O, or the pad's left-stick click opens the menu: HOST A GAME shows the
  code big; JOIN takes a typed code or one picked from the on-screen letters (mouse, touch, or a pad: d-pad to
  move, A to press, B to close); LEAVE GAME; the HTML game's status lines ("room ABCD — waiting for player 2",
  "connected — you are player 2", "room ABCD not found — host first, then join", ...). While the host waits, the
  code shows big at the bottom of the screen (as the HTML game draws it).
- **Web build: PeerJS**, the HTML game's own set-up (Smashed.html "NET": `PEER_OPTS` with its STUN servers and the
  metered.ca TURN relay, the room code as the host's peer id, a reliable data channel, the same timeouts and
  messages), loaded from unpkg (peerjs@1.5.4) like the HTML game, through JavaScriptBridge (`window.SmashedNet`).
  The broker only introduces the two browsers; then it's a direct WebRTC channel, so it works from GitHub Pages.
- **Native builds: ENet** (LAN; the "code" is the host's address, or any code for the same machine). Both behind
  `NetTransport` (host, join, send, poll, close; signals opened, connected, received, disconnected, status), so
  another transport (Steam, WebSocket relay...) is one more subclass.
- **The fight is the host's**, as in the HTML game: its FightSim runs both players, the guest is its player 2,
  moved by the guest's input (30 a second: move, aim, fire, roll, weapon picks, E). The whole sim goes to the
  guest 20 times a second (`NetCodec`, by reflection over the FT records: enemies, bullets, potatoes, rockets,
  gore, coins, the janitor, the slot machine, Protect Gothica, the bonus room), with the host's sounds, hit
  events and banners. The guest steps it on between snapshots, so nothing moves in 20 fps steps, and its own
  player is predicted from its own input (kept unless the host has it 48+ units away, thrown or down). Both
  shoot, both get paid, both can die and come back at the next wave. Enter (or the Start button) on the guest
  asks the host to start; R / the game-over tap asks the host to restart, and both games restart together.
- **Seeing each other**: in the lobby each player walks themselves and tells the other where they are, which way
  they face, walking or rolling, on the trampoline, their character, their **hair style and shirt print** (sent
  as pictures; the other's Jared is baked with them, not with yours), and the pictures lobby life shows for them
  (lying in bed, lifting, sitting at the table, the bong, carrying Gothica...: `NetMirror` stands copies of the
  same pictures in the same places). In a run the sim places both.
- **Every E action on both screens**: each player's E things run on their own screen for their own player (the
  wardrobe and clothes, the mirror, the bong and its trip only for your own hits, the gym, the pool and tower,
  the slot and vending machines, the barbecue, the mushroom, the arcade), which is what the HTML game's b309 fixes
  get to. **Lobby Gothica is one Gothica for both** (b309): the host's game runs her at first and the guest sees
  her where she is on the host's screen (position, walk, her poses: carried, swimming, thrown); either player
  (as Jared) can pick her up: E on the other game's Gothica asks for her, and from then on the game of whoever
  picked her up runs her (carrying, putting down, throwing her off the board, her wandering) until the other
  picks her up again.
- **The clock is the host's** (in every snapshot; the guest's GameClock follows with `is_host = false`, firing
  the same signals; the guest's own saved day and time are left alone and come back when it leaves). **Sleeping needs both in bed**: when the second lies down, both screens fade to 7 am of the
  next day.
- **The farm** is shared and saved on the host: whoever acts (plant, water, harvest, buy, sell, breed) sends the
  farm's state; the host's copy goes every 4 s and on every change. Each player has their own bag (the guest's
  player carries `farm_pid` 1) and pays from their own wallet.
- **The Mega Drive cabinet's player 2** (integration/arcade.md's hooks): its messages go over this connection,
  and when the friend joins, whoever is playing calls them with the picture and sound (`SmashedMD.streamTo` with
  this PeerJS peer; incoming calls go to `SmashedMD.answerCall`). Not tested (no ROM here).
- **Restarts and leaving**: the connection lives at `/root/Net`, so a restart (the scene reloading) keeps it and
  hooks into the new game. If the other player leaves, the host's room stays open; a guest mid-run goes back to
  its own lobby, its own farm save and its own clock.

## Install

`scripts/main.gd`, after the other installs in `_ready()` (done on this branch):

```gdscript
	Net.install(self)                   # playing together online (milestone 4): last, it hooks into all the above
```

Changes to existing files (done on this branch):
- `scripts/combat/fight.gd`: `net_input2`, `net_step`, `net_request` Callables (player 2's input from the network,
  the guest's step, Enter/R/P through the network); `start_run(forced)` / `restart(forced)` ask the network first
  unless forced; player 2 only slides through the lobby by himself when `f2.driven`; the arrows aren't taken from
  first-person turning when player 2 is online; and (a fix found here) a lobby life pose (lying in bed, lifting...)
  hides the fighter's sprite instead of being drawn over by it.
- `scripts/combat/fight_sim.gd`: at a run's start two players coming from the yard or the bedroom stand side by
  side at the back door instead of on top of each other.
- `scripts/look/lighting_install.gd`: the clock save is skipped while the clock is a guest's (`is_host` false).

Input actions added (in code): `net_menu` (O, pad left-stick click).

## Testing

Two headless games over ENet on one machine (in a work copy `$W`, imported):

```
godot --headless --path $W --fixed-fps 60 -- --host=TEST --netdrive=res://test/net/drive.gd &
godot --headless --path $W --fixed-fps 60 -- --join=127.0.0.1 --netdrive=res://test/net/drive.gd
```

Each prints `CHECK ... ok/FAIL` and `DRIVE DONE fails=N`: seeing each other walk, the character change, the guest
planting (both see it), both in bed (both wake the next morning), the run (both see enemies, both fire, each sees
the other fire, kills), the guest asking for a restart (both back in the lobby, still connected). All pass.
`--netstate` / `?netstate` prints a `NET ...` line twice a second.

Two headless Chromium pages on the web export, over PeerJS (WebRTC): the container can't reach unpkg.com or
the public PeerJS broker (the proxy blocks them), so the test serves peerjs.min.js itself (from npm, the same
1.5.4) and runs a local broker:

```
npm install peer@1.0.2 peerjs@1.5.4             # in a scratch folder
npx peerjs --port 9000 --host 127.0.0.1 &
cp node_modules/peerjs/dist/peerjs.min.js $W/build/web/
python3 -m http.server 8741 --directory $W &
node godot/test/net/two_pages.mjs http://127.0.0.1:8741/build/web/index.html <out dir> "peer=127.0.0.1:9000&peerjs=peerjs.min.js"
```

(export with `test/net/*` left in: the export preset excludes `test/*`). The page takes `?host[=CODE]`,
`?join=CODE`, `?peer=host:port[/path]` (a PeerJS broker of your own; `&peerssl` for wss), `?peerjs=<url>`,
`?lan` (native only), `?netdrive=res://test/net/drive.gd`, `?netstate`.

## Decisions

- **Who runs what.** The HTML game runs everything on the host and draws the guest from snapshots. Here the
  fight, the clock, the farm and lobby Gothica are the host's, but in the lobby each player walks themselves
  and runs their own E things for their own player, telling the other what they look like. Lobby life is written
  for one player per screen (its things hold "the player"), so this gives every E action to both players without
  rewriting it, and the guest's walking is instant instead of a round trip away.
- **The friend's lobby gear**: the online player 2 gets the lobby's blasters, 20 pellets and cash like player 1
  (the local P-key player 2 gets only the cash, as the HTML's addPlayer).
- **Peer ids are `smashedgd-<code>`** (the HTML game's are `jucyjared-<code>`), so a Godot room and an HTML room
  never meet: they don't speak the same messages.
- **The farm syncs as whole state**, last action wins (the host's copy every 4 s and on each change; the guest
  ignores the host's copy for 1.5 s after acting, so its own action doesn't flicker back). Its messages are small.
- **Snapshots are compressed** (Godot's var_to_bytes, deflate): about 0.8 KB in the lobby, a few KB in a run.
- **The guest predicts its own player** between snapshots (keeps its own position unless the host disagrees by
  48+ units), so walking and rolling feel local; shots appear when the host's snapshot has them (as in the HTML
  game).

## What's left

- The public PeerJS broker and unpkg aren't reachable from the build container: online play on GitHub Pages with
  the real broker, and on real phones, is untested (the code is the HTML game's own set-up).
- The other player in the pool isn't cut at the waterline; the wardrobe doors and the gym's plates aren't
  synced (each screen has its own); the host's tuning panel values (HTML's cfg message) aren't sent (same build,
  same numbers).
- Packing the fight costs up to ~5 ms a snapshot natively in a busy wave (more in wasm): if phones struggle as
  host, send fewer cosmetic records (sparks, blood) or pack them by hand.
- The Mega Drive player-2 video call is wired but not tried with a ROM.
- The first-person test shot (test/net/look.gd) aims its look at the other player loosely; the view itself works.
