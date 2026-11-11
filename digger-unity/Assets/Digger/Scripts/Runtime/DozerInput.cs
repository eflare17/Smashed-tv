using UnityEngine;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

namespace Digger
{
    /// <summary>
    /// Local player input: keyboard + mouse, and any gamepad (Xbox, PlayStation, or the
    /// Steam Controller through Steam Input). Produces <see cref="DozerControls"/> for the
    /// machine and a few camera / UI requests for the rig and HUD.
    ///
    /// Steam Controller gyro: in Steam, set the controller's gyro to output "Joystick"
    /// on the right stick (roll for steering axis). In game press G (keyboard) or View/Back
    /// (gamepad) to switch on gyro tilt: the right stick's X then sets the blade tilt
    /// directly, and LB/RB lower/raise the blade.
    /// </summary>
    public class DozerInput : MonoBehaviour, IDozerControlSource
    {
        [Tooltip("Right stick X sets blade tilt directly (map the controller gyro to the right stick in Steam Input).")]
        public bool gyroTilt;
        [Tooltip("Degrees of camera orbit per pixel of mouse movement.")]
        public float mouseLookSpeed = 0.18f;
        [Tooltip("Degrees per second of camera orbit from a gamepad.")]
        public float padLookSpeed = 110f;

        // Camera and UI requests (valid for the current frame).
        public bool CameraTogglePressed { get; private set; }
        public bool BladeCamPressed { get; private set; }
        public bool HelpPressed { get; private set; }
        public Vector2 Look { get; private set; }
        public float Zoom { get; private set; }

        DozerControls controls;
        int polledFrame = -1;

        public DozerControls Read()
        {
            Poll();
            return controls;
        }

        void Update()
        {
            Poll();
        }

        void Poll()
        {
            if (polledFrame == Time.frameCount) return;
            polledFrame = Time.frameCount;

            var c = new DozerControls();
            bool camToggle = false, bladeCam = false, help = false, gyroToggle = false;
            Vector2 look = Vector2.zero;
            float zoom = 0f;

#if ENABLE_INPUT_SYSTEM
            var kb = Keyboard.current;
            if (kb != null)
            {
                if (kb.wKey.isPressed) c.throttle += 1f;
                if (kb.sKey.isPressed) c.throttle -= 1f;
                if (kb.dKey.isPressed) c.steer += 1f;
                if (kb.aKey.isPressed) c.steer -= 1f;
                if (kb.spaceKey.isPressed) c.brake = 1f;
                if (kb.rKey.isPressed || kb.upArrowKey.isPressed) c.bladeLift += 1f;
                if (kb.fKey.isPressed || kb.downArrowKey.isPressed) c.bladeLift -= 1f;
                if (kb.cKey.isPressed) c.bladeTilt += 1f;
                if (kb.zKey.isPressed) c.bladeTilt -= 1f;
                if (kb.rightArrowKey.isPressed) c.bladeAngle += 1f;
                if (kb.leftArrowKey.isPressed) c.bladeAngle -= 1f;
                if (kb.eKey.wasPressedThisFrame) c.gearDelta += 1;
                if (kb.qKey.wasPressedThisFrame) c.gearDelta -= 1;
                if (kb.lKey.wasPressedThisFrame) c.toggleLights = true;
                if (kb.pKey.wasPressedThisFrame) c.resetMachine = true;
                if (kb.backspaceKey.wasPressedThisFrame) c.resetGround = true;
                camToggle |= kb.vKey.wasPressedThisFrame;
                bladeCam |= kb.bKey.wasPressedThisFrame;
                help |= kb.hKey.wasPressedThisFrame;
                gyroToggle |= kb.gKey.wasPressedThisFrame;
            }

            var mouse = Mouse.current;
            if (mouse != null)
            {
                if (mouse.rightButton.isPressed) look += mouse.delta.ReadValue() * mouseLookSpeed;
                float scroll = mouse.scroll.ReadValue().y;
                if (Mathf.Abs(scroll) > 0.01f) zoom += Mathf.Sign(scroll);
            }

            var pad = Gamepad.current;
            if (pad != null)
            {
                Vector2 ls = pad.leftStick.ReadValue();
                Vector2 rs = pad.rightStick.ReadValue();
                c.throttle += ls.y + pad.rightTrigger.ReadValue() - pad.leftTrigger.ReadValue();
                c.steer += ls.x;
                if (gyroTilt)
                {
                    c.useTiltDirect = true;
                    c.tiltDirect = rs.x;
                    if (pad.rightShoulder.isPressed) c.bladeLift += 1f;
                    if (pad.leftShoulder.isPressed) c.bladeLift -= 1f;
                }
                else
                {
                    c.bladeLift += rs.y;
                    c.bladeAngle += rs.x;
                    if (pad.rightShoulder.isPressed) c.bladeTilt += 1f;
                    if (pad.leftShoulder.isPressed) c.bladeTilt -= 1f;
                }
                if (pad.buttonSouth.isPressed) c.brake = 1f;
                if (pad.dpad.up.wasPressedThisFrame) c.gearDelta += 1;
                if (pad.dpad.down.wasPressedThisFrame) c.gearDelta -= 1;
                if (pad.buttonEast.wasPressedThisFrame) c.toggleLights = true;
                if (pad.startButton.wasPressedThisFrame) c.resetMachine = true;
                camToggle |= pad.buttonNorth.wasPressedThisFrame;
                bladeCam |= pad.buttonWest.wasPressedThisFrame;
                gyroToggle |= pad.selectButton.wasPressedThisFrame;
                float padYaw = (pad.dpad.right.isPressed ? 1f : 0f) - (pad.dpad.left.isPressed ? 1f : 0f);
                look.x += padYaw * padLookSpeed * Time.deltaTime;
            }
#else
            // Old Input Manager fallback (keyboard and mouse only).
            if (Input.GetKey(KeyCode.W)) c.throttle += 1f;
            if (Input.GetKey(KeyCode.S)) c.throttle -= 1f;
            if (Input.GetKey(KeyCode.D)) c.steer += 1f;
            if (Input.GetKey(KeyCode.A)) c.steer -= 1f;
            if (Input.GetKey(KeyCode.Space)) c.brake = 1f;
            if (Input.GetKey(KeyCode.R) || Input.GetKey(KeyCode.UpArrow)) c.bladeLift += 1f;
            if (Input.GetKey(KeyCode.F) || Input.GetKey(KeyCode.DownArrow)) c.bladeLift -= 1f;
            if (Input.GetKey(KeyCode.C)) c.bladeTilt += 1f;
            if (Input.GetKey(KeyCode.Z)) c.bladeTilt -= 1f;
            if (Input.GetKey(KeyCode.RightArrow)) c.bladeAngle += 1f;
            if (Input.GetKey(KeyCode.LeftArrow)) c.bladeAngle -= 1f;
            if (Input.GetKeyDown(KeyCode.E)) c.gearDelta += 1;
            if (Input.GetKeyDown(KeyCode.Q)) c.gearDelta -= 1;
            if (Input.GetKeyDown(KeyCode.L)) c.toggleLights = true;
            if (Input.GetKeyDown(KeyCode.P)) c.resetMachine = true;
            if (Input.GetKeyDown(KeyCode.Backspace)) c.resetGround = true;
            camToggle |= Input.GetKeyDown(KeyCode.V);
            bladeCam |= Input.GetKeyDown(KeyCode.B);
            help |= Input.GetKeyDown(KeyCode.H);
            gyroToggle |= Input.GetKeyDown(KeyCode.G);
            if (Input.GetMouseButton(1))
                look += new Vector2(Input.GetAxis("Mouse X"), Input.GetAxis("Mouse Y")) * (mouseLookSpeed * 20f);
            float wheel = Input.mouseScrollDelta.y;
            if (Mathf.Abs(wheel) > 0.01f) zoom += Mathf.Sign(wheel);
#endif

            if (gyroToggle) gyroTilt = !gyroTilt;

            c.throttle = Mathf.Clamp(c.throttle, -1f, 1f);
            c.steer = Mathf.Clamp(c.steer, -1f, 1f);
            c.bladeLift = Mathf.Clamp(c.bladeLift, -1f, 1f);
            c.bladeTilt = Mathf.Clamp(c.bladeTilt, -1f, 1f);
            c.bladeAngle = Mathf.Clamp(c.bladeAngle, -1f, 1f);
            c.tiltDirect = Mathf.Clamp(c.tiltDirect, -1f, 1f);

            controls = c;
            CameraTogglePressed = camToggle;
            BladeCamPressed = bladeCam;
            HelpPressed = help;
            Look = look;
            Zoom = zoom;
        }
    }
}
