// The size of everything drawn on screen (the help boxes, the coins, the upgrades, the menu).
//
// The panels are laid out for a 1080-high screen.  Every OnGUI starts with Ui.Begin(), which scales the drawing to
// the real screen height (1440 high draws everything a third bigger), times the UI size setting in the menu
// (Size, 75% to 200%).  Inside OnGUI, lay out against Ui.W and Ui.H (the screen in those 1080-high units) instead of
// Screen.width and Screen.height.
//
// Begin also gives the boxes a solid dark backing, so the panels read over a busy background.
using UnityEngine;

public static class Ui
{
    public static float Size = 1f;                                    // the UI size setting, 0.75 to 2
    public const float MinSize = 0.75f, MaxSize = 2f;

    /// The scale the setting and the screen height ask for (1080 high at 100% is 1).
    public static float Wanted { get { return Mathf.Max(0.5f, Screen.height / 1080f) * Size; } }
    /// The scale the last Begin() used.
    public static float Scale { get; private set; } = 1f;
    /// The screen's width and height in the units the panels are laid out in.
    public static float W { get { return Screen.width / Scale; } }
    public static float H { get { return Screen.height / Scale; } }

    /// Call first in every OnGUI.  fitW / fitH (optional): a panel that size must fit on screen, so the scale is
    /// held down if the setting would make it bigger than the screen.
    public static void Begin(float fitW = 0f, float fitH = 0f)
    {
        float f = Wanted;
        if (fitW > 0f) f = Mathf.Min(f, Screen.width / fitW);
        if (fitH > 0f) f = Mathf.Min(f, Screen.height / fitH);
        Scale = Mathf.Max(0.3f, f);
        GUI.matrix = Matrix4x4.Scale(new Vector3(Scale, Scale, 1f));
        if (TrailerMode.On) GUI.matrix = Matrix4x4.Translate(new Vector3(-100000f, -100000f, 0f));   // trailer mode: every panel drawn far off the screen
        DarkBoxes();
    }

    /// A point on the real screen (from WorldToScreenPoint: pixels, y up) in the panels' units (y down).
    public static Vector2 FromScreen(Vector3 p) { return new Vector2(p.x / Scale, (Screen.height - p.y) / Scale); }

    // ---- the solid dark box backing
    static Texture2D boxTex;
    static GUISkin skinDone;
    public static readonly Color Back = new Color(0.07f, 0.08f, 0.10f, 0.94f);
    public static readonly Color Edge = new Color(0.36f, 0.38f, 0.42f, 1f);

    static void DarkBoxes()
    {
        if (GUI.skin == skinDone && boxTex != null) return;
        if (boxTex == null)
        {
            const int n = 8;
            boxTex = new Texture2D(n, n, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp, hideFlags = HideFlags.DontSave };
            var px = new Color[n * n];
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                    px[y * n + x] = x == 0 || y == 0 || x == n - 1 || y == n - 1 ? Edge : Back;
            boxTex.SetPixels(px);
            boxTex.Apply();
        }
        var box = GUI.skin.box;
        box.normal.background = boxTex;
        box.border = new RectOffset(2, 2, 2, 2);
        box.normal.textColor = new Color(0.93f, 0.93f, 0.93f);
        skinDone = GUI.skin;
    }

    /// A plain filled rectangle in a colour.
    public static void Fill(Rect r, Color c)
    {
        var old = GUI.color; GUI.color = c;
        GUI.DrawTexture(r, Texture2D.whiteTexture);
        GUI.color = old;
    }
}
