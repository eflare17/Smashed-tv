// What stays on screen, and the switches for the rest.
//
//   Top left       coins and gold (Money.cs), and a small "H  help" reminder
//   Top middle     the current goal (Goals.cs)
//   Top right      frames a second, only if it is switched on (F11, or Show fps in Esc > Settings)
//   Bottom right   what you are working with: in the dozer the blade view, how full the blade is, its depth and any
//                  warning; on foot your tool, the cart and the backpack, each with a fill bar
//
//   H (pad: left stick click)   the help: every control.  It also shows by itself for the first minute of a new game.
//   F3                          the debug numbers (ground volume, dirt moving, work per step ...)
//
// The panels are laid out in Ui's 1080-high units, so the UI size setting scales them all.
using UnityEngine;

public class Hud : MonoBehaviour
{
    public static Hud Instance { get; private set; }
    public const float HelpFirstSeconds = 60f;
    public static bool HelpKey;                      // H switched the help on
    public static bool DebugOn;                      // F3
    static float helpUntil = -1f;                    // the help shows by itself until this time (unscaled), a new game only
    bool carryChecked;

    /// True while the controls should be shown.
    public static bool HelpOn { get { return HelpKey || Time.unscaledTime < helpUntil; } }

    // where the panels go (in Ui units)
    public const float Margin = 10f;
    public const float TopLeftBottom = 76f;          // the coins box ends here: the help and debug go below it
    public const float RightW = 380f;                // the bottom-right column

    void Awake()
    {
        Instance = this;
        helpUntil = Time.unscaledTime + HelpFirstSeconds;
        // In the editor, keep playing when another window is in front (the tests run unattended).  The built game
        // still pauses when you switch away from it.
        if (Application.isEditor) Application.runInBackground = true;
    }
    void OnDestroy() { if (Instance == this) Instance = null; }

    void Update()
    {
        // carrying on from a save is not a new game: no help unless asked for
        if (!carryChecked && SaveGame.Instance != null && SaveGame.Instance.CarriedOn) { carryChecked = true; helpUntil = -1f; }
        if (PauseMenu.Blocking) return;
        if (Worker.Instance != null && Worker.Instance.useOverride) return;   // not while a test drives
        if (Input.GetKeyDown(KeyCode.H) || Pad.Down(Pad.B.LS)) ToggleHelp();
        if (Input.GetKeyDown(KeyCode.F3)) DebugOn = !DebugOn;
    }

    public static void ToggleHelp()
    {
        if (HelpOn) { HelpKey = false; helpUntil = -1f; }
        else HelpKey = true;
    }

    /// For tests: forget the first-minute help (as if a minute had gone by).
    public static void SkipFirstHelp() { helpUntil = -1f; }

    // ---------------------------------------------------------------- drawing helpers
    static GUIStyle small, smallBold, helpStyle;
    public static GUIStyle Small { get { if (small == null) small = new GUIStyle(GUI.skin.label) { fontSize = 15 }; return small; } }
    public static GUIStyle SmallBold { get { if (smallBold == null) smallBold = new GUIStyle(GUI.skin.label) { fontSize = 15, fontStyle = FontStyle.Bold }; return smallBold; } }

    /// A fill bar: dark track, coloured fill.
    public static void Bar(Rect r, float fill, Color c)
    {
        Ui.Fill(r, new Color(0f, 0f, 0f, 0.55f));
        Ui.Fill(new Rect(r.x + 1, r.y + 1, (r.width - 2) * Mathf.Clamp01(fill), r.height - 2), c);
    }

    /// One labelled bar line: "Blade  ####----  2.1 of 5 m3".  Returns the next y.
    public static float BarLine(float x, float y, float w, string name, float fill, string amount, Color c)
    {
        GUI.Label(new Rect(x, y, 90, 22), name, SmallBold);
        Bar(new Rect(x + 92, y + 6, w - 92 - 130, 11), fill, c);
        GUI.Label(new Rect(x + w - 126, y, 126, 22), amount, Small);
        return y + 22f;
    }

    /// The help (controls) box, top left under the coins.  Returns its bottom.
    public static float HelpBox(string text, float width)
    {
        if (helpStyle == null) helpStyle = new GUIStyle(GUI.skin.box) { fontSize = 14, alignment = TextAnchor.UpperLeft, wordWrap = false, padding = new RectOffset(8, 8, 6, 6) };
        width = Mathf.Max(width, helpStyle.CalcSize(new GUIContent(text)).x + 4f);
        float h = helpStyle.CalcHeight(new GUIContent(text), width);
        var r = new Rect(Margin, TopLeftBottom + 6f, width, h);
        GUI.Box(r, text, helpStyle);
        return r.yMax;
    }

    /// The F3 debug box, under the help (or under the coins).
    public static void DebugBox(string text, float top)
    {
        var st = new GUIStyle(GUI.skin.box) { fontSize = 13, alignment = TextAnchor.UpperLeft, padding = new RectOffset(8, 8, 6, 6) };
        st.normal.textColor = new Color(0.75f, 0.9f, 1f);
        float h = st.CalcHeight(new GUIContent(text), 520f);
        GUI.Box(new Rect(Margin, top + 6f, 520f, h), text, st);
    }

    /// The bottom-right panel: a box `h` high sitting on `bottom` (Ui units).  Returns its rect.
    public static Rect RightPanel(float bottom, float h)
    {
        var r = new Rect(Ui.W - RightW - Margin, bottom - h, RightW, h);
        GUI.Box(r, GUIContent.none);
        return r;
    }

    /// Warning text in the bottom-right column (bold, orange).
    static GUIStyle warnStyle;
    public static GUIStyle Warn
    {
        get
        {
            if (warnStyle == null) { warnStyle = new GUIStyle(GUI.skin.label) { fontSize = 15, fontStyle = FontStyle.Bold, wordWrap = true }; warnStyle.normal.textColor = new Color(1f, 0.62f, 0.2f); }
            return warnStyle;
        }
    }

    void OnGUI()
    {
        if (Prologue.Playing) return;
        Ui.Begin();
        // the reminder of how to get the help, under the coins
        var st = new GUIStyle(GUI.skin.label) { fontSize = 13 };
        st.normal.textColor = new Color(1f, 1f, 1f, 0.75f);
        if (!HelpOn) GUI.Label(new Rect(Margin + 4f, TopLeftBottom - 2f, 300f, 20f), Pad.InUse ? "Left stick click   help" : "H   help     F3   debug", st);
    }
}
