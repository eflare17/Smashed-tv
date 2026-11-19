// The game pad.  Reads an Xbox-style pad through Unity's old Input Manager (the project has no Input System
// package).  Steam turns the Steam Controller into exactly this kind of pad for a non-Steam game, so this is
// how the Steam Controller gets in too, gyro and all: Steam turns the gyro into right-stick movement.
//
// The stick, trigger and d-pad axes are named "Pad LX" .. "Pad DY" in the Input Manager.  The editor builder
// (BulldozerBuilder.EnsurePadAxes) adds them if they are missing.  If they are still missing, the pad's
// buttons work and the sticks read nothing, rather than the game stopping with an error.
//
// Tests (and anything else) can drive it without a real pad: set overrideOn and the o* values.
using UnityEngine;

public static class Pad
{
    public enum B { A = 0, B = 1, X = 2, Y = 3, LB = 4, RB = 5, Back = 6, Start = 7, LS = 8, RS = 9 }

    // name, Unity joystick axis (0 = X axis, 3 = 4th axis ...), upside down
    public static readonly string[] AxisNames = { "Pad LX", "Pad LY", "Pad RX", "Pad RY", "Pad LT", "Pad RT", "Pad DX", "Pad DY", "Pad TRIG" };
    public static readonly int[] AxisNumbers = { 0, 1, 3, 4, 8, 9, 5, 6, 2 };
    public static readonly bool[] AxisInvert = { false, true, false, true, false, false, false, false, false };

    // ---- driven by script (tests)
    public static bool overrideOn;
    public static float oLX, oLY, oRX, oRY, oLT, oRT;
    public static int oDX, oDY;                 // -1, 0 or +1
    public static int oButtons;                 // bit per B: 1 << (int)B.A ...
    public static void Hold(B b, bool down) { if (down) oButtons |= 1 << (int)b; else oButtons &= ~(1 << (int)b); }
    public static void ClearOverride() { oLX = oLY = oRX = oRY = oLT = oRT = 0f; oDX = oDY = 0; oButtons = 0; }

    // ---- what the pad is doing this frame
    public static Vector2 LeftStick { get { Refresh(); return ls; } }     // dead zone taken out; up is +y
    public static Vector2 RightStick { get { Refresh(); return rs; } }    // raw (small dead zone only): the gyro rides on it
    public static float LT { get { Refresh(); return lt; } }              // 0..1
    public static float RT { get { Refresh(); return rt; } }
    public static int DX { get { Refresh(); return dx; } }                // d-pad: -1, 0, +1
    public static int DY { get { Refresh(); return dy; } }
    public static bool DUpDown { get { Refresh(); return dy > 0 && pdy <= 0; } }
    public static bool DDownDown { get { Refresh(); return dy < 0 && pdy >= 0; } }
    public static bool DLeftDown { get { Refresh(); return dx < 0 && pdx >= 0; } }
    public static bool DRightDown { get { Refresh(); return dx > 0 && pdx <= 0; } }
    public static bool Held(B b) { Refresh(); return (buttons & (1 << (int)b)) != 0; }
    public static bool Down(B b) { Refresh(); return (buttons & (1 << (int)b)) != 0 && (prevButtons & (1 << (int)b)) == 0; }
    /// True once the pad has been used more recently than the keyboard and mouse: the help on screen shows the pad.
    public static bool InUse { get { Refresh(); return inUse; } }

    /// "E" or "A" (say), depending on what is being played with.
    public static string Key(string keyboard, string pad) { return InUse ? pad : keyboard; }

    static int frame = -1;
    static Vector2 ls, rs;
    static float lt, rt;
    static int dx, dy, pdx, pdy, buttons, prevButtons;
    static bool inUse, axesOk = true, warned;

    static float Axis(int i)
    {
        if (!axesOk) return 0f;
        try { return Input.GetAxisRaw(AxisNames[i]); }
        catch (System.ArgumentException)
        {
            axesOk = false;
            if (!warned) { warned = true; Debug.LogWarning("Pad: the pad axes are not in the Input Manager.  Run Tools > Bulldozer > Rebuild prefab once."); }
            return 0f;
        }
    }

    static Vector2 DeadZone(Vector2 v, float dead)
    {
        float m = v.magnitude;
        if (m <= dead) return Vector2.zero;
        return v / m * Mathf.Min(1f, (m - dead) / (1f - dead));
    }

    static void Refresh()
    {
        if (frame == Time.frameCount) return;
        frame = Time.frameCount;
        prevButtons = buttons; pdx = dx; pdy = dy;
        Vector2 l, r; float tl, tr; int x, y, b = 0;
        if (overrideOn)
        {
            l = new Vector2(oLX, oLY); r = new Vector2(oRX, oRY); tl = oLT; tr = oRT; x = oDX; y = oDY; b = oButtons;
        }
        else
        {
            l = new Vector2(Axis(0), Axis(1));
            r = new Vector2(Axis(2), Axis(3));
            tl = Axis(4); tr = Axis(5);
            // some drivers give both triggers on one shared axis instead (left +, right -)
            if (tl == 0f && tr == 0f) { float t = Axis(8); tl = Mathf.Max(0f, t); tr = Mathf.Max(0f, -t); }
            float fx = Axis(6), fy = Axis(7);
            x = fx > 0.5f ? 1 : fx < -0.5f ? -1 : 0;
            y = fy > 0.5f ? 1 : fy < -0.5f ? -1 : 0;
            for (int i = 0; i <= 9; i++) if (Input.GetKey(KeyCode.JoystickButton0 + i)) b |= 1 << i;
        }
        ls = DeadZone(l, 0.18f);
        rs = DeadZone(r, 0.04f);
        lt = Mathf.Clamp01(tl); rt = Mathf.Clamp01(tr);
        dx = x; dy = y; buttons = b;

        // which was touched last: the pad, or the keyboard and mouse
        bool padNow = buttons != 0 || dx != 0 || dy != 0 || ls != Vector2.zero || rs.sqrMagnitude > 0.04f || lt > 0.2f || rt > 0.2f;
        if (padNow) inUse = true;
        else if (!overrideOn && (Input.GetMouseButtonDown(0) || Input.GetMouseButtonDown(1)
                 || Mathf.Abs(Input.GetAxis("Mouse X")) > 0.5f || Mathf.Abs(Input.GetAxis("Mouse Y")) > 0.5f
                 || (Input.anyKeyDown && !AnyJoystickButtonDown())))
            inUse = false;
    }

    static bool AnyJoystickButtonDown()
    {
        for (int i = 0; i < 20; i++) if (Input.GetKeyDown(KeyCode.JoystickButton0 + i)) return true;
        return false;
    }
}
