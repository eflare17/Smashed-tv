# Online (milestone 4): integration note

Status: in progress.

Branch `claude/godot-online`. Files: `scripts/net/`, `test/net/`, this note; small hooks in `scripts/main.gd` and
`scripts/combat/fight.gd` (listed below).

## What works (so far)

- **Host and join by a room code** (4 letters from the HTML game's alphabet, no O/0 or I/1). Web build: PeerJS
  exactly as the HTML game sets it up (its STUN and TURN servers, a reliable data channel, its status lines), loaded
  from unpkg like the HTML game. Native builds: ENet over UDP (LAN; the "code" is the host's address).
- **The fight is the host's** (as in the HTML game): its FightSim runs both players, the guest is its player 2,
  moved by the guest's input (sent 30 times a second); the whole sim goes to the guest 20 times a second; the
  guest steps it on between snapshots so it moves smoothly, its own player predicted from its own input.
- **Both players see each other** in the lobby (where, which way, walking/rolling, on the trampoline, the
  character) and in the run.
- **The clock** is the host's (in the snapshot); **sleeping** needs both in bed, then both screens fade to the
  next morning.
- **The farm** is shared: whoever acts sends the farm's state; the host's copy goes every 4 s too.
- Tested with two headless games over ENet (`test/net/drive.gd`, see Testing): all checks pass.

## Install

`scripts/main.gd`, last line of the installs in `_ready()` (done on this branch):

```gdscript
	Net.install(self)                   # playing together online (milestone 4): last, it hooks into all the above
```

## Testing

Two headless games over ENet on one machine (work copy `$W`):

```
godot --headless --path $W --fixed-fps 60 -- --host=TEST --netdrive=res://test/net/drive.gd &
godot --headless --path $W --fixed-fps 60 -- --join=127.0.0.1 --netdrive=res://test/net/drive.gd
```

Each prints `CHECK ... ok/FAIL` and `DRIVE DONE fails=N`. `--netstate` (or `?netstate`) prints a `NET ...` line
twice a second.

## Decisions

- See net.gd's header for who runs what.
