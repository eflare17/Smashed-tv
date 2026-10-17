# Lighting: milestones 1.4 (day and night) and 1.5 (the look pass)

Branch `claude/godot-lighting`. Everything is in this session's own folders: `scripts/clock/`, `scripts/look/`,
`scenes/look/`, `test/lighting/` and this note. No existing file was edited.

## Installing it (the main session)

`project.godot`, under `[autoload]` (after GameData):

```
GameClock="*res://scripts/clock/game_clock.gd"
```

`scripts/main.gd`, the last line of `_ready()` (after the World is built and Gothica placed, before the
`print("Smashed TV ...ready")` is fine too):

```gdscript
	LightingInstall.install(self)
```

That's all. Without the autoload it still works: the install adds the GameClock at `/root/GameClock` itself.
main.gd's own fog toggle (`_on_mode`: haze in first person only) stays as it is; the install only changes the
haze's colour and distances.

Optional, in `project.godot` (not needed, the install registers them at runtime; listing them there just saves
that step and silences nothing):

```
[shader_globals]
look_tint={"type": "vec3", "value": Vector3(1, 1, 1)}
look_lamp_color={"type": "vec3", "value": Vector3(0, 0, 0)}
look_lamp_level={"type": "float", "value": 0.0}
look_lamp0={"type": "vec4", "value": Vector4(0, 0, 0, 0)}
look_lamp1={"type": "vec4", "value": Vector4(0, 0, 0, 0)}
look_lamp2={"type": "vec4", "value": Vector4(0, 0, 0, 0)}
look_lamp3={"type": "vec4", "value": Vector4(0, 0, 0, 0)}
```

## What works

**The GameClock** (`scripts/clock/game_clock.gd`, exactly PARALLEL.md's interface): `day`, `hour`, `paused`,
`day_length_sec = 1200`, `hour_changed(hour)`, `day_started(day)`, `time_skipped(hours)`, `advance_hours(h)`,
`sleep_to_morning()`, `is_night()`, `save_state()`, `load_state(d)`. 7 am to 9 pm takes 840 real seconds (a game
hour a minute), the night 360 (`DAY_SHARE = 0.7` of `day_length_sec`, the one tunable number). Extras, not in
the contract: `is_host` (false on an online guest: it stops ticking and follows `load_state` from the host's
snapshots, firing the same signals for what it passes), `speed` (a multiplier for tests), `tick(real_sec)`,
`total_hours()` (game hours since 7 am day 1, handy for the farm), `time_text()` ("7:05 am").

**Day and night** (`scripts/look/day_night.gd`): the sun rises in the east, crosses the north (it's Australia;
the HTML game already lights north faces most) up to 62 degrees at about 1 pm, and sets in the west; one
DirectionalLight3D (main's `$Sun`) is the sun by day and the moon by night, swapping over in the dark between.
Twelve looks through the day (night, pre-dawn, dawn, morning, day, golden hour, sunset, dusk, night) blend into
each other: sky colours, the light's colour and strength, the ambient light, the haze colour, the stars, the
lamps. The sky is a small custom sky shader (gradient, sun disc and glow, moon, twinkling stars), never baked
into a radiance map (that was most of the frame time when its colours changed every frame).

**Lamps**: four ceiling lights in the lounge, one in the bedroom, the nightstand lamp, a cyan pool light and the
porch light over the back door. They fade up through golden hour and sunset (from about 6 pm, fully on by 8) and go off in the
morning (by about 7:20 am). Ceiling lights have a glowing bulb in first person (hidden from above with the ceiling).

**The look** (`scripts/look/look_pass.gd`), HD-2D: the World's unshaded materials become lit ones (same
picture, nearest filtering, the same vertex colours), lit mostly by a strong ambient of the day's colour plus a
gentler sun, so a sunlit floor at noon looks as the HTML game drew it and shade is a soft darkening, never black.
The meshes have no normals, so the shader works each face's normal out on screen (flat, toward the camera).
- **Shadows**: the sun's, soft, two splits, 40 m. Characters cast their own shape: each CharSprite gets an
  invisible caster (its picture as a Y billboard in the light's own view, so it stands broadside to the sun).
  The house's walls cast in first person (a shadow-only copy without the roof and ceiling, so rooms stay sunlit
  the way the view from above shows them); the low cut walls cast from above; the trampoline casts; the yard's
  solids cast in first person.
- **Characters and props** are lit with a normal tipped up to the sky, with wrap lighting, so they never go black
  with the sun behind them. Hit flashes (CharSprite.modulate) still work.
- **Glow**: the arcade screens and marquees glow (brighter at night) with a soft halo in front in first
  person; the pool's water ripples, shines and is lit from below at night.
- **Haze**: first person's distance haze takes the time of day's colour (warm at golden hour, dark blue at night).
- **Far blur** (first person, high look): the Compatibility renderer has no depth texture (tried: the shader
  won't compile on the web), so the lit material blends far surfaces (from 12 m, fully by 45 m) into a smoothly
  filtered copy of their own picture. Near things stay crisp pixel art.
- **Top-down stays crisp**: no haze, no blur; the floors keep their drawn shadows; at night the rooms are warm
  pools of lamp light and the yard is moonlit blue.

**Quality**: "high" (shadows, all the lamps, the far blur, the glow) and "low" (phones: unshaded pictures times
one day colour, plus up to four lamps worked out in the material: no light passes, no shadows). Phones
(`web_android`, `web_ios`, `mobile`) start low; desktops start high and **drop to low by themselves** if the
median frame takes over 26 ms in the first seconds. F8 toggles; `?look=low` / `?look=high` in the address
picks one (and turns the automatic drop off).

**The HUD clock** (`scripts/clock/clock_hud.gd`, its own CanvasLayer; hud.gd untouched): "Day 3   7:42 am" with a
sun or a moon, top right under the view label.

**Sleeping**: a stand-in `BedSleep` Interactable on the bed (game_data.json's BED, reach 106 units): E says
SLEEP; the screen fades out, the clock goes to 7 am on the next day (`sleep_to_morning`), "Day N" shows, it
fades back in; the player can't move meanwhile. **As soon as any node with a `sleep_requested` signal enters
the tree (the Lobby session's bed), the install connects that signal to the same sleep and takes its stand-in
out of the "interactable" group.** So the lobby's bed only needs to `emit sleep_requested(...)` (any arguments)
when you lie down; the fade and the skip are done here.

**Saving**: the day and time go to `user://gameclock.json` every 10 seconds, after every skip and new day, and
when the window loses focus or closes; they're loaded at install (straight in, no signals fired, so nothing
counts a load as time passing). The main save can take `GameClock.save_state()` over later.

**Online (later)**: the host's clock is the one. Put `GameClock.save_state()` in the host's snapshot; on the
guest set `GameClock.is_host = false` and call `GameClock.load_state(snapshot.clock)`. Sleeping online should
wait for both players in bed (the bed's job), then the host calls `sleep_to_morning()`.

## Tests

- `test/lighting/clock_test.gd` (headless logic): `godot --headless --path godot --script res://test/lighting/clock_test.gd`
  25 checks: a day is 1200 s, 840 s of day and 360 of night, 24 hour_changed and one day_started a day, the
  tunable length, sleeping at 11 pm / 2 am / an afternoon, advance_hours, save/load, a guest following
  snapshots, paused, time_text. All pass.
- `scenes/look/install_test.tscn` (headless, inside the real game): `godot --headless --path godot res://scenes/look/install_test.tscn`
  25 checks: the clock at /root/GameClock, nothing left unshaded, the casters, the sun in the east / north /
  west, lamps off at noon and on at night, the moon, the quality switch, E says SLEEP beside the bed, sleeping
  to 7 am day 2, the save, a lobby bed's `sleep_requested` taking over. All pass.
- `scenes/look/look_test.tscn`: the game with the install, for the web build and screenshots. Its address takes
  `hour=`, `day=`, `look=`, `view=fp`, `at=x,y`, `face=deg`, `ly=`, `zoom=`, `perf` (prints frame times),
  `nolight` (the game without the install, to compare). `test/lighting/shots.mjs` takes a screenshot per query.
  To export it, point the copy's `run/main_scene` at it.

**Frame times** (the web export in headless Chromium, which draws with the CPU (SwiftShader), 480x270; only
the ratios mean anything): without the install 41 ms; low look 48-54 ms (about +20%); high look 94 ms at noon
and 123 ms at night with all the lamps. A real GPU runs the high look easily; phones get the low look, and a
slow desktop drops to it.

## Input actions added (in code, at install)

- `look_quality`: F8 (high / low look)
- `clock_skip`: F6 (an hour on: a debug key for trying the times of day; remove it if it's unwanted)

## Contract changes wanted

- **CharSprite**: LookPass reaches into `_mat` (sets its shader to a lit copy of `_SHADER_CODE`) and the
  "Picture" child (copies its texture, offset and flip to the shadow caster each frame). Better: a public
  `shader_override: Shader` (kept when `shaded` changes) and a public `picture: Sprite3D`. `shaded = true`
  itself isn't usable for this look (its normal faces the camera, so with the sun in the north the characters
  are lit from behind all day in the top-down view).
- **WorldBuilder**: the house's lid (ceiling, roof, wall tops) in a mesh of its own (or tagged surfaces) would
  let the shadow caster skip it without the geometry test in `_caster_without_roof`; normals in the SurfaceTools
  (`st.generate_normals()`) would let the shader skip the screen-space normal. The props' shader code is
  copied from the material and patched by string replace (`render_mode unshaded, ` and
  `ALPHA_SCISSOR_THRESHOLD = 0.5;`); if PROP_SHADER changes, keep those two strings or tell this session.
- **The Lobby session's bed**: a `sleep_requested` signal (see Sleeping). Its other interactables don't need
  anything.
- **Anyone adding unshaded StandardMaterial3Ds later** (enemies' props, gore...): they stay unshaded unless
  passed to `LookPass.light_tree(node)` (`main.get_node("Lighting").look.light_tree(node)`): it swaps
  unshaded, mix-blended StandardMaterial3Ds for lit ones. CharSprites are picked up automatically.

## Decisions (for the owner)

- **The day number goes up at 7 am, not midnight**: a game day runs morning to morning, so sleeping at 11 pm or
  at 2 am both wake you at 7 am on the next day, and `day_started` (a new market day) fires at 7 am.
- **Night is 9 pm to 7 am** for `is_night()` (the 6 real minutes); the look gets dark from about 8 pm (sunset
  7:54 pm) and light from about 6 am.
- **The sun crosses the north** (southern hemisphere), matching the HTML game's lit north faces.
- **Rooms are sunlit by day in both views**: the roof doesn't throw its shadow over the inside (it would make
  first person dark inside all day while the top-down view, which has no roof, stays bright).
- **Sleeping works at any time** (an afternoon nap goes to 7 am tomorrow), from either side of the bed.
- **The far blur is done in the material** (no depth texture in the web renderer).
- **The renderer's own glow is left on in the high look but isn't relied on**: the screens' glow is drawn.
- **The Compatibility renderer lights each object with at most 8 lights**, and the World is one big mesh, so the
  high look has exactly 8 lamps; adding more (e.g. yard lights) means raising
  `rendering/limits/opengl/max_lights_per_object` in project.godot or splitting the World's mesh.
- **Phones start on the low look**, desktops on high with an automatic drop to low if slow.
- **The clock saves to its own file** (`user://gameclock.json`) until there's a game save to join.
- **F6 skips an hour** (debug).

## What's left

- Real 3D models (PLAN.md's "later").
- Window glow from outside at night (the house has no windows yet) and lights in the yard beyond the porch.
- Online: send the clock in the snapshot and the both-in-bed rule (milestone 4).
- The farm and the trading game hook into `day_started` / `time_skipped` / `total_hours()`.
- Testing on a real phone and a real GPU (only SwiftShader here).
