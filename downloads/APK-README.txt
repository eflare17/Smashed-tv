SMASHED TV -- VOXEL ARENA, THE ANDROID BUILD
============================================

File:     SmashedVoxelArena.apk
Size:     42,132,341 bytes (40.2 MB)
SHA-256:  1fe53fa4dcef8617598f984c8cc35f35f728eacc9a624ee1d7dfeb9044e97585
Built:    25 November 2026, Godot 4.4.1 stable, export preset "Android Voxel Arena"
          (tools/build_android.sh; same signing key as the first build, so it
          installs straight over it)
Phones:   64-bit ARM (arm64-v8a) -- a Galaxy S25 or anything else from the last ten years.
          Android 5.0 or newer. Nothing else is in the file: no 32-bit, no Intel.


PUTTING IT ON THE PHONE
-----------------------
1. On the phone, open this file's page on GitHub and tap Download (or the raw
   link). Chrome will warn you that this kind of file can harm your device --
   that warning is about APKs in general, not this one. Tap Download anyway.
2. Open the downloaded file (Downloads, or the notification).
3. Android will say "For your security, your phone is not allowed to install
   unknown apps from this source." Tap Settings, turn on "Allow from this
   source", then come back.
4. Tap Install. Play Protect may add "Scan app?" or "Unsafe app blocked" --
   that is because the app is not from the Play Store and is signed with a
   plain development key. Choose "Install anyway" / "Install without
   scanning".
5. It lands in the app drawer as "Smashed TV voxel arena". The icon is the
   stock Godot robot -- there is no game icon in the project yet.

Updating later: a newer APK installs straight over this one as long as it is
signed with the same key. If Android ever refuses with "App not installed",
uninstall the old one first.


WHAT IS IN IT
-------------
- The voxel arena, start to finish: the yard and the house, the weapons, the
  waves, the chests, St Kilda and Luna Park, the gun range, Demolition with
  the wrecking-ball crane, the phone, the backpack, the settings and the
  benchmark.
- The touch controls, on from the first frame (no browser, no full-screen
  button, no address bar eating the screen). Left half walks, right half
  looks, FIRE / AIM / E / R / JUMP and the weapon bar bottom right, "..."
  for PHONE, BAG, VIEW, HELP, SET.
- Landscape. Hold the phone sideways.
- It fills the panel now, punch-hole camera and all. The first build sat in a
  black band down one side: a landscape app whose window says nothing about the
  display cutout gets laid out so it cannot overlap the camera hole, and the
  system fills the leftover strip black -- about 100 px of a Galaxy S25's 2340.
  The APK now asks for the cutout (windowLayoutInDisplayCutoutMode=shortEdges),
  so the picture goes right to the edges, and the buttons and the fps line keep
  themselves out of the camera's band instead. Nothing moves under your thumbs:
  the left half still walks and the right half still looks, hole or no hole.
- Graphics start much higher than the first build, which was still running the
  browser's settings. The 3D picture is now drawn at the screen's own pixels
  (2340 x 1080 on an S25, where it used to be drawn 858 x 396 and stretched --
  7.4 times the pixels), the far distance goes out to 420 m instead of 260 m,
  and Luna Park keeps its scenery in full out to 110 m instead of 60 m. The
  rest stays where Low had it, so loading is no slower than before.
  Measured: the longer view costs nothing at all in Luna Park and 11 draw calls
  at the worst spot in the arena; the scenery step is about a third more
  triangles there. The pixels cannot be measured without a phone, which is why
  everything else was left alone.
- Two things were deliberately left off, because they are the ones that could
  cost real frames and nobody could measure them here: the sun's SHADOWS (four
  shadow splits over 60 m -- it could double what Luna Park draws) and YOUR OWN
  BLOCKS at Fine (12 seconds of building on the loading screen for a body you
  only see in the mirror). Both are one tap away: MEDIUM in SET.
  SET says "Custom" rather than "Low" on the first run for exactly this reason
  -- it is Low with the render scale and the scenery moved up, nothing else.
- IF IT IS TOO MUCH FOR THE PHONE, in this order:
  1. SET -> Render scale -> 85%, then 77%. That row now means what it says on
     a phone, and 77% is barely over half the pixels of 100%.
  2. SET -> Scenery detail -> Near (60 m), which is where the first build had
     it.
  3. LOW, which puts everything back to the first build's settings bar the
     draw distance.
  APPLY RECOMMENDED still runs the benchmark and picks a preset for you.
- Swinging the view round no longer hitches. The phone's renderer compiles a
  shader the first time anything is really drawn with it, which is why turning
  used to stutter the first time you looked somewhere new; the game now turns
  the camera right round behind the loading screen so all of that is done
  before you can touch anything. It costs a couple of seconds of loading and
  it happens every launch, not just the first.
- The enemies have their blocks back, and it is a setting now: "Enemy detail
  (cube size)" in SET, Fine on every preset including Low. There is a second
  row, "Your own blocks", for the Jared you see top-down, in the bedroom
  mirror and in co-op -- that one still starts Chunky on Low, because he is
  eight times the blocks of an enemy and all of it is built while you wait on
  the loading screen. Turn him up if you do not mind the wait.

WHAT IS NOT IN IT
-----------------
- The DIG SITE and the MINE. Both are built on native code add-ons compiled
  for PC only (there is no Android build of them), so they are left out, the
  same as in the browser version. Travelling to either on the phone shows
  "The Dig Site is in the PC version only" / "The mine is in the PC version
  only" and leaves you in the arena. It does not crash.
- The RETRO TV (the playable arcade cabinet) -- same reason.
- ONLINE / co-op. The WebRTC add-on is PC-only too, and the APK asks for no
  permissions at all, internet included. Tapping ONLINE and hosting or
  joining says "Online play is in the PC and browser versions only".
  Everything single-player works.

Permissions the APK asks for: none. It cannot reach the network, your files,
the camera, the microphone or your location. Saves and settings live in the
app's own private storage and go when you uninstall it.


FIRST RUN
---------
It loads in ten named steps with a "Loading: step N of 10" line on a dark
screen. The yard is the slow one, and the last step before "done" is the
camera being swung round to warm the picture up. Give it some seconds; it is
building the world, not stuck. It does the same on every launch, not only the
first one.

Nobody has run this build on a phone yet -- it was built and inspected on a
machine with no Android device attached. If it falls over, the thing worth
knowing is which loading step it got to. If the picture is still not reaching
the edges, the thing worth knowing is whether the black band is on the camera's
side of the screen or the other one.
