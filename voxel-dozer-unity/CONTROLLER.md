# Playing Digger Game with a controller

The game reads an Xbox-style pad. Any Xbox pad works when plugged in. The Steam Controller works through
Steam: Steam turns it into an Xbox pad for the game, and turns its gyro into right-stick movement, which the
game uses to move the blade.

Keyboard and mouse still work as before. The help on screen switches to pad buttons as soon as you touch the
pad, and back to keys when you touch the keyboard or mouse.

## Buttons

### In the dozer

| Button | Does |
|---|---|
| Left stick | drive and steer |
| Right trigger | blade down (R/F on the keyboard is up/down) |
| Left trigger | blade up |
| RB / LB | ripper up / down (T / G) |
| D-pad left / right | angle the blade (Q / E) |
| D-pad up / down | tilt the blade (Z / C) |
| X | straighten the blade (X) |
| B | lights (L) |
| Right stick | look round |
| **Right stick click, held** | **gyro blade** (see below) |
| Y | get out (Enter) |
| Start | upgrades (U) |

### On foot

| Button | Does |
|---|---|
| Left stick | walk |
| Right stick | look and aim |
| Right trigger | use the tool (left mouse / Space) |
| RB / LB | next tool / last tool (1 / 2 / 3) |
| D-pad up / down | jackhammer bite bigger / smaller (Shift+wheel or [ ]) |
| A | what E does: take hold of the cart, tip it at the hopper, sell gold, pick up and fit parts |
| X | squirt the backpack into the cart (Q) |
| B | tip the cart (T) |
| Back (View) | switch view: over the shoulder / eyes (Tab) |
| D-pad right | get on / off the motor cart (R); riding, the left stick drives it out / back in |
| Y | get in the dozer (Enter) |
| Start | upgrades (U) |

### In the upgrades

D-pad left / right picks a branch (a `>` marks it), A buys its next level, X sells the newest level back,
Start closes.

## The gyro blade

While the **gyro button** is held, the right stick's *position* is the blade's position:

- **Right stick left / right = blade tilt.** Roll the controller (drop one hand) and that end of the blade drops.
  All the way over is the blade's full tilt.
- **Right stick up / down = blade angle.** Tip the controller forward / back to swing the blade left / right.
  All the way is the blade's full angle.
- It starts from where the blade already is, so the blade never jumps when you press the button.
- **Let go and the blade stays where it is.** The camera doesn't move while the button is held, either.
- There is a small dead zone and some smoothing, so it doesn't twitch.

The game's gyro button is **right stick click**. On the Steam Controller, set a back grip to send right stick
click *and* to switch the gyro on (step 6 below). Then you hold the grip, tilt, and let go.

**Why tip forward/back for the angle and not a twist?** Steam turns the gyro into one stick, and a stick has only
two directions. Steam puts forward/back tip on up/down, and lets you choose roll or twist (yaw) for
left/right. Roll goes to the tilt, so the angle gets the forward/back tip. If that feels wrong, say so: it's a small
change in the game.

## Making the game

In Unity: **Tools > Bulldozer > Build Windows game**. It makes `voxel-dozer-unity/Builds/DiggerGame/DiggerGame.exe`
(not a Development build). Or from a command line:

```
Unity.exe -projectPath <...>/voxel-dozer-unity -executeMethod BulldozerBuilder.BuildWindowsFromCommandLine -logFile build.log
```

The built game uses the same save file as Play mode in the editor (F5 / F6).

## Adding it to Steam, step by step

The new Steam Controller's menus may use slightly different words from the ones below. These are the names in
Steam's controller settings on the PC as of 2025–26. Look for the nearest match.

1. **Add the game.** In Steam: **Games > Add a Non-Steam Game to My Library...** > **Browse...** > pick
   `DiggerGame.exe` > **Add Selected Programs**. It shows in your library as *DiggerGame*.
2. **Turn Steam Input on for it.** Right-click *DiggerGame* > **Properties... > Controller**. Set it to
   **Enable Steam Input**.
3. **Start the game from Steam** (not by double-clicking the exe). Steam Input only works when Steam starts it.
4. **Open its controller layout.** Press the **Steam button** (or, in the library, click the controller icon on
   the game's page) > **Controller Settings** / **Edit Layout**.
5. **Pick a gamepad layout.** Under **Templates**, choose **Gamepad** (or "Gamepad with Joystick Trackpad").
   That gives the buttons in the table above. The sticks, triggers, bumpers, A B X Y, D-pad, Back and Start just
   work.
6. **Set up a back grip as the gyro button.**
   - Go to **Grip Buttons** / **Back Buttons**. Choose a right-hand one (it may be called R4, R5, or Right Grip)
     and set it to **Right Stick Click** (sometimes **Right Joystick Click**). This tells the game the gyro is
     on.
7. **Set up the gyro.**
   - Go to **Gyro Behavior** (may be called **Motion** or **Gyro**).
   - Set it to **As Joystick** with output **Joystick Deflection** (may be called **Gyro to Joystick
     Deflection**). This is important: deflection means tilting holds the stick over, not "move like a mouse".
   - Output stick: **Right Joystick**.
   - **Gyro Activation / Enable Buttons:** pick the same back grip as in step 6, set to **On while held**
     (so the gyro only works while you hold the grip).
   - Left/right input (may be called **Steering Axis** or **Yaw or Roll**): choose **Roll**.
   - **Sensitivity / Maximum Deflection Angle:** start at about **30 degrees** tilt for full stick. Make it
     smaller if you have to tilt too far, bigger if the blade is too twitchy.
   - Leave dead zones small. The game has its own.
8. **Try it.** In the game, get in the dozer and hold the grip. The help at the top left shows **[GYRO ON]**.
   Roll the controller: the blade tilts. Tip it forward / back: the blade angles. Let go of the grip: the blade
   stays put.
   - Blade goes the wrong way? In the gyro settings turn on **Invert Horizontal** (tilt) or **Invert Vertical**
     (angle).
9. Steam saves the layout for this game by itself.

If something in the layout won't do what the steps say, holding the right stick in (clicking it) and moving it
with your thumb does the same thing as the gyro. Use that to check the game side works.

## For changing it later

- The pad is read in `art/bulldozer-vox/unity-src/Pad.cs` through Unity's old Input Manager. No packages were
  added. The axes it needs (`Pad LX` ... `Pad TRIG`) are added to the Input Manager by the editor builder
  (`BulldozerBuilder.EnsurePadAxes`, also **Tools > Bulldozer > Add game pad axes**).
- Gyro dead zone and smoothing: `gyroDeadZone`, `gyroSmoothing` on the dozer prefab's DozerController.
- Test: `-executeMethod BulldozerBuilder.PadTest` drives the dozer and the worker through the pad path and checks
  the blade follows the held stick and stays when let go. It prints `BULLDOZER_PAD_RESULT`.
