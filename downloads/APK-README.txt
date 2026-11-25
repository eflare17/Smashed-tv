SMASHED TV -- VOXEL ARENA, THE ANDROID BUILD
============================================

File:     SmashedVoxelArena.apk
Size:     42,124,149 bytes (40.2 MB)
SHA-256:  0e0092ffd2517e19af8cd9f2ec5c352594374404eba358aab9a82195a2191bc7
Built:    25 November 2026, Godot 4.4.1 stable, export preset "Android Voxel Arena"
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
- Graphics start on Low, the same as the browser does on a phone, and the 3D
  picture is drawn at about 1280 across however many real pixels the screen
  has, with the far distance pulled in to 260 m. SET (under "...") changes all
  of it, and APPLY RECOMMENDED runs the benchmark and picks a preset for you.
  If it feels smooth, try Medium -- native is a good deal faster than the
  browser was and the Low default is deliberately careful.

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
It loads in nine named steps with a "Loading: step N of 9" line on a dark
screen. The yard is the slow one. Give it some seconds the first time; it is
building the world, not stuck. After that it is the same every launch.

Nobody has run this build on a phone yet -- it was built and inspected on a
machine with no Android device attached. If it falls over, the thing worth
knowing is which loading step it got to.
