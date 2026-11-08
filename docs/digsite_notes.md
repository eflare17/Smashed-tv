# Dig Site: notes, decisions and open questions

The Dig Site is a 3D voxel digging and mining location in the PC voxel arena (Smashed), reached through the phone's
Travel app, co-op from the start. Code lives in `godot/scripts/voxel/digsite/`, scenes in `godot/scenes/voxel/digsite/`.

## Decisions

- **The branch.** The phone (and St Kilda, its first place) was on `claude/stkilda-voxel`, a branch made from
  `claude/godot-voxel`. `claude/godot-voxel` was fast-forwarded onto it (8 Nov) so the Dig Site sits next to St Kilda
  on the phone. Nothing was rewritten: `claude/stkilda-voxel` was this branch plus 39 commits.
- **Where it is.** Like the gun range (3 km west of the arena), the Dig Site is 3 km east of it in the arena's own
  world (`DigSite.AT = (3000, 0, 0)`), under its sky. So the player, the backpack, the tools, the co-op link and
  the other player's avatar all just work there. The arena waits while you're there (`VoxelArena.elsewhere()`).
- **Co-op travel.** The phone's Travel was off in co-op (St Kilda's choice). It now offers Home and the Dig Site with a
  mate: the host's choice takes both players (message "D" `go`); a guest's choice is asked of the host (`want`), who
  then sends both. St Kilda, its game and the gun range stay off in co-op.
- **The scene.** `scenes/voxel/digsite/dig_site.tscn` is a plain Node3D with `dig_site.gd`. The arena instances it
  and calls `setup(arena)`.

## Open questions

- Pre-existing, not from the Dig Site: St Kilda's own test prints thousands of "Out of bounds set index" errors from
  `sk_crowd.gd:345` headless (it still says PASS). Worth a look by whoever owns St Kilda.

## Stages

1. Scene + phone travel: done.
