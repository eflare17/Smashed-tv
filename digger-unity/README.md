# Digger Game (Unity) — Stage 1: bulldozer prototype

Stage 1 from the Build Brief: one tracked 1990s-style bulldozer in a small dirt test yard,
built for Unity 6 LTS with HDRP. Nothing past Stage 1 is here yet.

| Brief item | What's in this stage |
| --- | --- |
| Tracked bulldozer with realistic driving | Track physics: each track grips the ground through six spring contacts, limited by grip and a 120 kW engine. Three forward and three reverse gears. Steering slows the inside track; with no throttle the tracks counter-rotate for a pivot turn. |
| Blade: lift, tilt and angle | Three PhysX articulation-body joints with hydraulic-style drives: lift (−0.5 m dig to +1 m), tilt (±8°, one corner lower) and angle (±25° swing). |
| Small deformable test yard; blade cuts and pushes dirt into piles | A 64 × 64 m terrain. The cutting edge shaves off soil and heaps it in front of the blade, the heap travels with the blade, and loose soil slumps to a 37° angle of repose. An angled blade rolls soil off the trailing end as a windrow. Disturbed ground turns to fresh-soil colour. The heap and the cut push back on the blade, so the dozer slows as it loads up. |
| Dust effect while pushing | Dust from both blade ends while cutting, and from behind the tracks at speed. |
| Blade cam | A camera on top of the blade looking down at the cutting edge, shown in a box in the bottom-right corner (B toggles it). |
| Optional: gyro tilt | Map the Steam Controller gyro to the right stick in Steam Input, press G (or View/Back) and the gyro tilts the blade. |
| HDRP lighting: sun, shadows, ambient occlusion | A low afternoon sun with soft shadows, plus a global volume with screen-space ambient occlusion. The sky and fog come from your HDRP template scene. |

The dozer is a **placeholder model built from boxes and cylinders** (blade, push arms, lift
cylinders, ROPS canopy, tracks that roll, work lights). It can be swapped for the Dozer Drive
model later, exported as FBX or glTF.

## Set up (once)

1. In **Unity Hub**, install **Unity 6 LTS** (6000.0.x).
2. Create a new project from the **High Definition 3D** template (call it `DiggerGame`).
3. Copy the folder `digger-unity/Assets/Digger` from this repo into the new project's `Assets`
   folder, so you have `DiggerGame/Assets/Digger`.
4. Go back to Unity and wait for it to compile. If it asks about an **API update**, click
   *I Made a Backup. Go Ahead!*.

## Build the test yard

1. Open the template's sample scene (the one that opens when the new project is created). The
   builder copies that scene's sun, sky and fog, so the lighting matches HDRP's settings.
2. Menu **Digger ▸ Build Stage 1 Test Yard**.
3. It creates and opens `Assets/Digger/Scenes/Stage1_TestYard.unity`. Press **Play**.

Running the menu again rebuilds the yard in place.

## Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Drive forward / reverse | W / S | Left stick up/down, or RT / LT |
| Steer (pivot turn when stopped) | A / D | Left stick left/right |
| Gear down / up | Q / E | D-pad down / up |
| Brake | Space | A |
| Raise / lower blade | R / F (or ↑ / ↓) | Right stick up/down |
| Tilt blade (left / right corner down) | C / Z | RB / LB |
| Angle blade left / right | ← / → | Right stick left/right |
| Orbit camera / zoom | Hold right mouse and move / wheel | D-pad left/right |
| Cab view | V | Y |
| Blade cam on/off | B | X |
| Work lights | L | B |
| Gyro tilt on/off | G | View / Back |
| Reset dozer / reset ground | P / Backspace | Start / – |
| Show or hide controls | H | – |

With gyro tilt on, the right stick's left/right sets the blade tilt directly, and LB/RB lower and
raise the blade.

## What to test

1. **Driving:** drive in gears 1–3, reverse, and pivot on the spot. It should feel heavy:
   slow to turn, with no sliding about.
2. **Blade joints:** raise and lower the blade, then tilt it and angle it. Watch the lift
   cylinders follow, and the HUD readout for height, tilt and angle.
3. **Pushing dirt:** lower the blade a little below grade (blade height about −10 cm) and drive
   at the pile straight ahead. Dirt should shave off, heap in front of the blade, travel with it
   and slump off the sides. The engine-load bar should climb and the dozer slow down as the load
   grows.
4. **Windrow:** angle the blade 20° and push. The soil should roll off the trailing end.
5. **Cutting a bench:** cut into the bank at the far end of the yard.
6. **Blade cam:** watch the cutting edge in the corner box while you work.
7. **Dust:** look for dust off the blade ends while cutting, and behind the tracks in gear 3.
8. **Work lights:** turn them on (L). They show best in the cab view under the canopy.
9. **Props:** push the rocks and logs about.

## How this was checked

It was written in a cloud session where Unity can't run, so **nobody has pressed Play on it
yet**. What was checked:

- All scripts compile against Unity's reference assemblies, with both input systems (new and old)
  and with obsolete-API warnings switched on.
- The soil code was ported to Python and simulated. Soil volume is conserved exactly, pushed soil
  heaps up ahead of the blade and travels with it, and an angled blade sends soil to the correct
  side.
- The track force model was simulated as a rigid body. It settles on its springs, reaches each
  gear's top speed, pivot-turns at about 21°/s and stays stable at Unity's 50 Hz physics rate.

If something misbehaves, copy any red errors from the **Console** and describe what you saw
(for example "the blade drops to the ground and won't lift" or "the dust is pink").

Things most likely to need a tweak on first run:

- **Joint drive strength:** blade drive stiffness is set on the three blade links.
- **Dust in HDRP:** the dust uses a small custom shader. If it shows pink, it can move to a
  VFX Graph.
- **Steep-pile spring tuning:** the ground-contact springs on steep piles.

## Code layout

- `Scripts/Runtime/DozerController.cs`: track physics, gears, blade joints, track and lift
  cylinder visuals, work lights.
- `Scripts/Runtime/BladeCutter.cs` and `DeformableGround.cs`: cutting, pushing, slumping and
  soil resistance.
- `Scripts/Runtime/DozerInput.cs`: keyboard, mouse and gamepad, including the Steam Controller
  through Steam Input.
- `Scripts/Runtime/DozerCameraRig.cs`: chase camera, cab view and the blade cam box.
- `Scripts/Runtime/DozerHud.cs`: readout and controls card.
- `Scripts/Runtime/DustEmitters.cs` and `Shaders/DiggerDust.shader`: dust.
- `Scripts/Editor/Stage1Builder.cs`: builds the whole yard, the dozer, lighting and props.

Multiplayer is planned from the start, as the brief asks. The machine reads its commands from a
`DozerControls` struct through `IDozerControlSource`, so a network player or AI can drive it in
place of the keyboard. Ground edits raise a `HeightsChanged` event with the changed area, which a
network layer can replicate.
