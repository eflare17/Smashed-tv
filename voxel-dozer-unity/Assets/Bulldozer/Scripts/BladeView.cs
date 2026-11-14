// Two small live pictures in the top right, because from the driver's camera the machine hides its own blade.
//   Side:      a slice through the ground along the machine, with the blade, ripper and the heap being pushed.
//   From seat: the blade seen from behind, across its width, so you can see which end is lower when it is tilted.
// Both show the real ground (topsoil, clay, rock) and the real loose clods.  V hides and shows them.
using UnityEngine;

public class BladeView : MonoBehaviour
{
    public bool show = true;
    public float updatesPerSecond = 12f;

    const float Mpp = VoxelWorld.Voxel;                  // one voxel per pixel
    const int SW = 184, SH = 84;                         // side view: 11.5 m x 5.25 m
    const int FW = 96, FH = 56;                          // seat view: 6 m x 3.5 m
    const int Zoom = 2, FZoom = 3;

    static readonly Color32 Yellow = new Color32(246, 186, 6, 255), Amber = new Color32(214, 140, 8, 255),
                            Dark = new Color32(52, 54, 60, 255), Steel = new Color32(200, 204, 210, 255),
                            Glass = new Color32(40, 80, 104, 255), White = new Color32(255, 255, 255, 255);

    DozerController dozer;
    VoxelWorld world;
    Transform blade, ripper, liftMount, bladeHinge, rearMount;
    Texture2D sideTex, frontTex;
    Color32[] side, front;
    float timer;
    string depthText = "", angleText = "";
    GUIStyle label;

    // the picture being drawn into, and how world positions map onto it
    Color32[] px; int pw, ph;
    Vector3 vCentre, vU, vV;

    void Start()
    {
        dozer = GetComponent<DozerController>();
        world = VoxelWorld.Instance;
        blade = Find(transform, "Blade"); ripper = Find(transform, "Ripper");
        liftMount = Find(transform, "Mount_BladeLift"); bladeHinge = Find(transform, "Mount_Blade"); rearMount = Find(transform, "Mount_Rear");
        sideTex = new Texture2D(SW, SH, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
        frontTex = new Texture2D(FW, FH, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
        side = new Color32[SW * SH]; front = new Color32[FW * FH];
    }

    void Update()
    {
        if (dozer != null && !dozer.driven) return;                       // only while someone is driving
        if (Input.GetKeyDown(KeyCode.V)) show = !show;
        if (!show || world == null || blade == null) return;
        timer -= Time.unscaledDeltaTime;
        if (timer > 0f) return;
        timer = 1f / updatesPerSecond;
        Redraw();
    }

    void Redraw()
    {
        Vector3 fwd = transform.forward; fwd.y = 0f; fwd.Normalize();
        Vector3 right = new Vector3(fwd.z, 0f, -fwd.x);
        Vector3 pos = transform.position;

        // ---------------- side view ----------------
        Begin(side, SW, SH, pos + fwd * 1.3f + Vector3.up * 1.1f, fwd, Vector3.up);
        world.RenderSlice(side, SW, SH, vCentre, vU, vV, Mpp, right, 2.3f);
        // the level the tracks are riding at: the blade edge against this line is your cut
        for (int i = 0; i < SW; i += 3) Dot(new Vector3(0f, 0f, 0f), i, 0, White, true, pos.y);
        // tracks, body, hood, cab, tank, exhaust
        Poly(transform, Dark, -2.45f, 0.75f, -2.3f, 0.15f, -1.7f, 0.02f, 1.7f, 0.02f, 2.4f, 0.25f, 2.48f, 0.9f, 2.0f, 1.5f, -1.9f, 1.62f);
        Rect(transform, Amber, -2.44f, 1.66f, 2.44f, 1.94f);
        Rect(transform, Yellow, 0.31f, 1.94f, 2.44f, 3.37f);
        Rect(transform, Yellow, -1.69f, 1.94f, 0.31f, 4.45f);
        Rect(transform, Glass, -1.4f, 2.6f, 0.05f, 3.95f);
        Rect(transform, Yellow, -2.44f, 1.94f, -1.69f, 2.9f);
        Rect(transform, Dark, 1.25f, 3.37f, 1.6f, 4.35f);
        // lift arm, then the blade's curved face with its steel cutting edge
        if (liftMount != null && bladeHinge != null) Line(liftMount.position, bladeHinge.position, Amber, 2);
        Path(blade, Yellow, 2, 1.125f, -0.75f, 0.95f, -0.5f, 0.6f, 0.0f, 0.5f, 0.3f, 0.62f, 0.8f, 0.98f, 1.2f, 1.125f, 1.31f);
        Path(blade, Steel, 2, 1.125f, -0.75f, 0.95f, -0.5f);
        // ripper: links, beam and one shank
        if (ripper != null)
        {
            Path(ripper, Amber, 2, 0f, 0.3f, -0.8f, 0.3f);
            Path(ripper, Amber, 2, 0f, -0.3f, -0.8f, -0.3f);
            Rect(ripper, Yellow, -1.06f, -0.75f, -0.75f, 0.53f);
            Path(ripper, Dark, 2, -1.19f, 0.66f, -1.19f, -0.84f, -0.9f, -1.1f, -0.47f, -1.2f);
        }
        sideTex.SetPixels32(side); sideTex.Apply(false);

        // ---------------- from the seat ----------------
        Vector3 face = blade.TransformPoint(new Vector3(0f, 0f, 1.3f));
        Begin(front, FW, FH, new Vector3(face.x, pos.y + 0.75f, face.z), right, Vector3.up);
        world.RenderSlice(front, FW, FH, vCentre, vU, vV, Mpp, fwd, 0.75f);
        for (int i = 0; i < FW; i += 3) Dot(Vector3.zero, i, 0, White, true, pos.y);
        Vector3 bl = blade.TransformPoint(new Vector3(-2.25f, -0.75f, 1.1f)), br = blade.TransformPoint(new Vector3(2.25f, -0.75f, 1.1f));
        Vector3 tl = blade.TransformPoint(new Vector3(-2.25f, 1.31f, 1.1f)), tr = blade.TransformPoint(new Vector3(2.25f, 1.31f, 1.1f));
        Line(bl, tl, Yellow, 2); Line(br, tr, Yellow, 2); Line(tl, tr, Yellow, 2);
        Line(bl, br, Steel, 2);
        frontTex.SetPixels32(front); frontTex.Apply(false);

        // ---------------- the numbers ----------------
        float edge = Mathf.Min(bl.y, br.y) - pos.y;                       // lowest corner of the cutting edge, against the tracks
        depthText = edge < -0.01f ? "Cutting " + Mathf.RoundToInt(-edge * 100f) + " cm" : "Blade " + Mathf.RoundToInt(edge * 100f) + " cm up";
        angleText = "";
        if (dozer != null)
        {
            if (Mathf.Abs(dozer.BladeYaw) > 0.5f) angleText += "Angled " + Mathf.RoundToInt(Mathf.Abs(dozer.BladeYaw)) + (dozer.BladeYaw > 0f ? " right" : " left");
            if (Mathf.Abs(dozer.BladeTilt) > 0.5f) angleText += (angleText.Length > 0 ? "   " : "") + (dozer.BladeTilt > 0f ? "Right" : "Left") + " end " + Mathf.RoundToInt(Mathf.Abs(bl.y - br.y) * 100f) + " cm lower";
            if (angleText.Length == 0) angleText = "Blade straight";
        }
    }

    // ---------------------------------------------------------------- drawing helpers
    void Begin(Color32[] target, int w, int h, Vector3 centre, Vector3 u, Vector3 v) { px = target; pw = w; ph = h; vCentre = centre; vU = u; vV = v; }

    Vector2 ToPx(Vector3 world)
    {
        Vector3 d = world - vCentre;
        return new Vector2(Vector3.Dot(d, vU) / Mpp + pw * 0.5f, Vector3.Dot(d, vV) / Mpp + ph * 0.5f);
    }

    void Set(int x, int y, Color32 c) { if (x >= 0 && y >= 0 && x < pw && y < ph) px[x + y * pw] = c; }

    // a dot on a level line at world height `height`, at picture column `column`
    void Dot(Vector3 unused, int column, int dy, Color32 c, bool onHeight, float height)
    {
        int y = Mathf.RoundToInt((height - vCentre.y) / Mpp + ph * 0.5f) + dy;
        Set(column, y, c);
    }

    void Line(Vector3 a, Vector3 b, Color32 c, int thick)
    {
        Vector2 p = ToPx(a), q = ToPx(b);
        int steps = Mathf.Max(1, Mathf.CeilToInt(Vector2.Distance(p, q) * 1.5f));
        for (int i = 0; i <= steps; i++)
        {
            Vector2 m = Vector2.Lerp(p, q, i / (float)steps);
            int x0 = Mathf.RoundToInt(m.x - thick * 0.5f), y0 = Mathf.RoundToInt(m.y - thick * 0.5f);
            for (int dy = 0; dy < thick; dy++) for (int dx = 0; dx < thick; dx++) Set(x0 + dx, y0 + dy, c);
        }
    }

    // a line through points given as (forward, up) pairs in a part's own space
    void Path(Transform part, Color32 c, int thick, params float[] zy)
    {
        if (part == null) return;
        for (int i = 0; i + 3 < zy.Length; i += 2)
            Line(part.TransformPoint(new Vector3(0f, zy[i + 1], zy[i])), part.TransformPoint(new Vector3(0f, zy[i + 3], zy[i + 2])), c, thick);
    }

    void Rect(Transform part, Color32 c, float z0, float y0, float z1, float y1) { Poly(part, c, z0, y0, z1, y0, z1, y1, z0, y1); }

    // a filled shape through points given as (forward, up) pairs in a part's own space
    void Poly(Transform part, Color32 c, params float[] zy)
    {
        if (part == null) return;
        int n = zy.Length / 2;
        var pts = new Vector2[n];
        float lo = 1e9f, hi = -1e9f;
        for (int i = 0; i < n; i++)
        {
            pts[i] = ToPx(part.TransformPoint(new Vector3(0f, zy[i * 2 + 1], zy[i * 2])));
            lo = Mathf.Min(lo, pts[i].y); hi = Mathf.Max(hi, pts[i].y);
        }
        for (int y = Mathf.Max(0, Mathf.FloorToInt(lo)); y <= Mathf.Min(ph - 1, Mathf.CeilToInt(hi)); y++)
        {
            float yc = y + 0.5f, xa = 1e9f, xb = -1e9f;
            for (int i = 0; i < n; i++)
            {
                Vector2 a = pts[i], b = pts[(i + 1) % n];
                if ((a.y <= yc && b.y > yc) || (b.y <= yc && a.y > yc))
                {
                    float x = a.x + (yc - a.y) * (b.x - a.x) / (b.y - a.y);
                    xa = Mathf.Min(xa, x); xb = Mathf.Max(xb, x);
                }
            }
            for (int x = Mathf.Max(0, Mathf.RoundToInt(xa)); x < Mathf.Min(pw, Mathf.RoundToInt(xb)); x++) px[x + y * pw] = c;
        }
    }

    static Transform Find(Transform t, string name)
    {
        if (t.name == name) return t;
        for (int i = 0; i < t.childCount; i++)
        {
            var f = Find(t.GetChild(i), name);
            if (f != null) return f;
        }
        return null;
    }

    /// Draws the two pictures into whatever is being rendered to right now (used when recording clips,
    /// since the normal on-screen drawing does not go into a recording).
    public void DrawInto(int width, int height)
    {
        if (!show || sideTex == null || world == null || blade == null || (dozer != null && !dozer.driven)) return;
        Redraw();
        GL.PushMatrix();
        GL.LoadPixelMatrix(0, width, height, 0);
        int w = SW * Zoom, x = width - w - 14, fw = FW * FZoom, fh = FH * FZoom;
        Graphics.DrawTexture(new Rect(x, 30, w, SH * Zoom), sideTex);
        Graphics.DrawTexture(new Rect(x + (w - fw) / 2, 30 + SH * Zoom + 28, fw, fh), frontTex);
        GL.PopMatrix();
    }

    void OnGUI()
    {
        if (world == null || sideTex == null || (dozer != null && !dozer.driven)) return;
        if (label == null) label = new GUIStyle(GUI.skin.label) { fontSize = 13, fontStyle = FontStyle.Bold };
        int w = SW * Zoom, x = Screen.width - w - 14;
        if (!show) { GUI.Box(new Rect(Screen.width - 150, 10, 140, 24), "V   blade view"); return; }
        int fw = FW * FZoom, fh = FH * FZoom;
        GUI.Box(new Rect(x - 6, 6, w + 12, SH * Zoom + fh + 78), GUIContent.none);
        GUI.Label(new Rect(x, 8, w, 20), "Side     " + depthText + "        (V hides)", label);
        GUI.DrawTexture(new Rect(x, 30, w, SH * Zoom), sideTex);
        int y2 = 30 + SH * Zoom + 6;
        GUI.Label(new Rect(x, y2, w, 20), "From the seat     " + angleText, label);
        GUI.DrawTexture(new Rect(x + (w - fw) / 2, y2 + 22, fw, fh), frontTex);
    }
}
