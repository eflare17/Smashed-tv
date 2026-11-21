// The ending: a short beat once the game's goal is reached.  A placeholder (the owner hasn't designed the ending
// yet, 22 Nov 2026): all of it is easy to change.
//
// The goal, in the order the goals list (Goals.cs) leads you through it:
//   dig and earn, find gold  ->  fit all three buried parts (Dad's dozer restored)  ->  finish the mountain road
//   (all 15 stretches ticked).
// When both "dozer_fixed" and "road_done" are ticked, this plays ONCE (saved):
//   - the bars come in and the panels go;
//   - the camera flies up the finished road from its foot to the top (about 14 s), with two captions;
//   - at the top it hangs, looking back down the road, over a card with the stats (dirt sold at the hopper, dirt
//     pushed by the dozer, gold found, coins earned, goals done);
//   - "Keep playing" (Enter, Space, E, or A on the pad, or a click) gives the game back as it was.
// Nothing stops in the world while it plays; the worker and the dozer are just held still.
//
// It also keeps the totals the stats card needs (Money.Pay tells it what went down the hopper).  They are saved
// in their own section at the end of the save (SaveGame.cs); a save from before it starts them at nothing.
using UnityEngine;

public class Ending : MonoBehaviour
{
    public static Ending Instance { get; private set; }
    public static bool Playing { get { return Instance != null && Instance.playing; } }
    /// True only while the ending draws its own card (Ui.cs hides every other panel while it plays).
    public static bool Drawing { get; private set; }

    // ---- the totals (saved)
    public double SoldLitres { get; private set; }        // dirt (soil, clay, rock, quartz) that went down the hopper
    public double GoldFoundLitres { get; private set; }   // gold that went down the hopper into the gold store
    public bool Shown { get; private set; }               // the ending has played

    public const float FlyFor = 14f, HoldFor = 2f;        // the flight up the road, and the pause before the card
    bool playing;
    float t0;
    Transform cam;
    FollowCamera follow;
    bool followWas, wkOverrideWas, dzOverrideWas;
    DozerController dz;

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    /// Money.Pay: what went down the hopper (voxels of each loose material).
    public static void CountPaid(int[] voxelsByMaterial)
    {
        if (Instance == null) return;
        double l = VoxelWorld.VoxelVolume * 1000.0;
        for (int m = VoxelWorld.LooseSoil; m <= VoxelWorld.LooseGold && m < voxelsByMaterial.Length; m++)
        {
            if (voxelsByMaterial[m] <= 0) continue;
            if (m == VoxelWorld.LooseGold) Instance.GoldFoundLitres += voxelsByMaterial[m] * l;
            else Instance.SoldLitres += voxelsByMaterial[m] * l;
        }
    }

    /// Is the game's goal reached?
    public static bool GoalReached
    {
        get { var g = Goals.Instance; return g != null && g.IsDone("dozer_fixed") && g.IsDone("road_done"); }
    }

    void Update()
    {
        if (!playing)
        {
            if (Shown || TrailerMode.On || Prologue.Playing || Time.timeSinceLevelLoad < 3f) return;
            if (GoalReached) Begin();
            return;
        }
        float t = Time.unscaledTime - t0;
        Fly(t);
        if (t > FlyFor + HoldFor && (Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.KeypadEnter) || Input.GetKeyDown(KeyCode.Space)
                                     || Input.GetKeyDown(KeyCode.E) || Pad.Down(Pad.B.A)))
            Finish();
    }

    /// Starts the ending (tests can call it straight away).
    public void Begin()
    {
        if (playing) return;
        var c = Camera.main;
        if (c == null) return;
        playing = true; Shown = true;
        t0 = Time.unscaledTime;
        cam = c.transform;
        follow = c.GetComponent<FollowCamera>();
        followWas = follow != null && follow.enabled;
        if (follow != null) follow.enabled = false;
        var wk = Worker.Instance;
        if (wk != null) { wkOverrideWas = wk.useOverride; wk.useOverride = true; wk.overrideWalk = 0f; wk.overrideUse = false; }
        dz = FindFirstObjectByType<DozerController>();
        if (dz != null) { dzOverrideWas = dz.useOverride; dz.useOverride = true; dz.overrideThrottle = 0f; dz.overrideSteer = 0f; dz.overrideBlade = 0f; dz.overrideRipper = 0f; dz.overrideAngle = 0f; dz.overrideTilt = 0f; }
        Cursor.lockState = CursorLockMode.None;
        GameAudio.Play("goal", 0.9f);
    }

    /// "Keep playing": hands everything back.
    public void Finish()
    {
        if (!playing) return;
        playing = false;
        if (follow != null) follow.enabled = followWas;
        var wk = Worker.Instance;
        if (wk != null) wk.useOverride = wkOverrideWas;
        if (dz != null) dz.useOverride = dzOverrideWas;
        if (SaveGame.AutoOn && SaveGame.Instance != null) SaveGame.Instance.Save();   // so it doesn't play again after a crash
    }

    // the camera: up the road 12 m above it and a little behind, looking ahead and down; then it rises and turns
    // to look back down the whole road
    void Fly(float t)
    {
        if (cam == null) return;
        float L = MountainRoad.Length;
        float u = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01(t / FlyFor));
        float s = u * (L - 6f);
        Vector2 p = PointAlong(s), ahead = PointAlong(Mathf.Min(L, s + 14f));
        float y = MountainRoad.GradeAt(s);
        Vector3 from = new Vector3(p.x, y + 12f, p.y), look = new Vector3(ahead.x, MountainRoad.GradeAt(s + 14f) + 1f, ahead.y);
        if (t > FlyFor)
        {
            // at the top: drift up and round to look back down the road
            float k = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01((t - FlyFor) / 5f));
            Vector2 top = Vector2.Lerp(PointAlong(L - 6f), PointAlong(L * 0.45f), 0.25f), down = PointAlong(L * 0.45f);
            Vector3 hang = new Vector3(top.x, MountainRoad.GradeAt(L) + 48f, top.y);     // well above the gum trees
            Vector3 lookDown = new Vector3(down.x, MountainRoad.GradeAt(L * 0.45f), down.y);
            from = Vector3.Lerp(from, hang, k);
            look = Vector3.Lerp(look, lookDown, k);
        }
        cam.SetPositionAndRotation(from, Quaternion.LookRotation((look - from).normalized, Vector3.up));
    }

    static Vector2 PointAlong(float s)
    {
        int n = MountainRoad.Count;
        s = Mathf.Clamp(s, 0f, MountainRoad.Length);
        for (int i = 1; i < n; i++)
            if (MountainRoad.AlongAt(i) >= s)
                return Vector2.Lerp(MountainRoad.Point(i - 1), MountainRoad.Point(i), Mathf.InverseLerp(MountainRoad.AlongAt(i - 1), MountainRoad.AlongAt(i), s));
        return MountainRoad.Point(n - 1);
    }

    // ---- on screen
    /// The stats card's lines (tests and the screen).
    public string[] StatLines()
    {
        var m = Money.Instance; var g = Goals.Instance;
        return new[]
        {
            "Dirt sold at the hopper:   " + (SoldLitres / 1000.0).ToString("N1") + " m³",
            "Dirt pushed by the dozer:   " + (g != null ? g.PushedM3 : 0f).ToString("N0") + " m³",
            "Gold found:   " + GoldFoundLitres.ToString("N0") + " L",
            "Coins earned:   " + (m != null ? m.Earned : 0).ToString("N0"),
            "Goals done:   " + (g != null ? g.DoneCount : 0) + " of " + Goals.List.Length,
        };
    }

    void OnGUI()
    {
        if (!playing) return;
        GUI.depth = -20;                                           // over everything
        float t = Time.unscaledTime - t0;
        float sw = Screen.width, sh = Screen.height;
        GUI.matrix = Matrix4x4.identity;
        // the bars, sliding in
        float bar = sh * 0.11f * Mathf.Clamp01(t / 1f);
        var old = GUI.color;
        GUI.color = Color.black;
        GUI.DrawTexture(new Rect(0, 0, sw, bar), Texture2D.whiteTexture);
        GUI.DrawTexture(new Rect(0, sh - bar, sw, bar), Texture2D.whiteTexture);
        GUI.color = old;
        float f = Mathf.Max(0.5f, sh / 1080f);
        GUI.matrix = Matrix4x4.Scale(new Vector3(f, f, 1f));
        float W = sw / f, H = sh / f;
        var cap = new GUIStyle(GUI.skin.label) { fontSize = 34, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
        string line = t < 1.5f ? "" : t < 7.5f ? "The mountain road is finished." : t < FlyFor ? "Dad's dozer is working again." : "";
        if (line.Length > 0)
        {
            float a = Mathf.Clamp01(Mathf.Min(t - 1.5f, (t < 7.5f ? 7.5f : FlyFor) - t));
            cap.normal.textColor = new Color(1f, 0.95f, 0.85f, a);
            GUI.Label(new Rect(0, H - 118f / 1080f * H - 10f, W, 60f), line, cap);
        }
        if (t < FlyFor + HoldFor) return;
        // the card
        Drawing = true; Ui.Begin(); Drawing = false;               // (for the solid box backing)
        GUI.matrix = Matrix4x4.Scale(new Vector3(f, f, 1f));
        float cw = 620f, ch = 380f, cx = (W - cw) / 2f, cy = (H - ch) / 2f;
        GUI.Box(new Rect(cx, cy, cw, ch), GUIContent.none);
        var title = new GUIStyle(GUI.skin.label) { fontSize = 30, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
        title.normal.textColor = new Color(1f, 0.82f, 0.3f);
        GUI.Label(new Rect(cx, cy + 16f, cw, 44f), "The mine and the road are done", title);
        var row = new GUIStyle(GUI.skin.label) { fontSize = 20, alignment = TextAnchor.MiddleLeft };
        row.normal.textColor = Color.white;
        var lines = StatLines();
        for (int i = 0; i < lines.Length; i++) GUI.Label(new Rect(cx + 60f, cy + 78f + i * 36f, cw - 100f, 32f), lines[i], row);
        var btn = new GUIStyle(GUI.skin.button) { fontSize = 22, fontStyle = FontStyle.Bold };
        if (GUI.Button(new Rect(cx + cw / 2f - 140f, cy + ch - 78f, 280f, 56f), Pad.InUse ? "A   Keep playing" : "Keep playing", btn)) Finish();
    }

    // ---- saved (SaveGame.cs: its own section, last)
    public void WriteState(System.IO.BinaryWriter w)
    {
        w.Write(1);                                                // version
        w.Write(Shown); w.Write(SoldLitres); w.Write(GoldFoundLitres);
    }

    public void ReadState(System.IO.BinaryReader r)
    {
        int version = r.ReadInt32();
        Shown = r.ReadBoolean(); SoldLitres = r.ReadDouble(); GoldFoundLitres = r.ReadDouble();
        if (version > 1) { }                                       // (later versions add their fields after these)
    }

    /// A new game, or a save from before the ending.  (An old save that has already reached the goal gets the
    /// ending once, a few seconds after it loads.)
    public void Clear() { Shown = false; SoldLitres = 0; GoldFoundLitres = 0; playing = false; }

    /// Tests: as if it had never played.
    public void TestReset() { if (playing) Finish(); Clear(); }
}
