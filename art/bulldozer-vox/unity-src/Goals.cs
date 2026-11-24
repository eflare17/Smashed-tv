// Small goals: one at a time, top middle of the screen.  When it is done it ticks, plays a sound, pays a small coin
// bonus, and the next one comes up.  Saved with the game (SaveGame.cs).
//
// THE LIST is the table just below: add, remove or reorder rows there.  Each row is
//     id (what the save remembers: never change or reuse one),  what it says,  the coin bonus,  how it is checked.
// A goal that is already true when it comes up ticks straight away.  Loading a save from before there were goals
// skips (no bonus) every goal the save has already done.
using System.Collections.Generic;
using UnityEngine;

public class Goals : MonoBehaviour
{
    public static Goals Instance { get; private set; }

    public struct Goal
    {
        public string id, text; public long bonus; public System.Func<Goals, bool> done;
        public System.Func<Goals, string> progress;      // a short "how far" line, or null
    }
    static Goal G(string id, string text, long bonus, System.Func<Goals, bool> done, System.Func<Goals, string> progress = null)
    { return new Goal { id = id, text = text, bonus = bonus, done = done, progress = progress }; }

    // ------------------------------------------------------------------ THE LIST
    public static readonly Goal[] List =
    {
        G("cave1_dig",   "Dig into the first cave-in",                    20, g => g.CaveDug(0)),
        G("cart_fill",   "Fill the cart",                                  20, g => g.CartFull(), g => g.CartLine()),
        G("cart_tip",    "Push the cart to the dump and tip it",           30, g => g.tipped),
        G("upgrade1",    "Buy your first upgrade (U, or Start on the pad)", 30, g => AnyUpgrade()),
        G("cave1_clear", "Clear the first cave-in, so the cart gets through", 60, g => g.CaveClear(0)),
        G("find_part",   "Find something buried in the cave-in (a dozer part)", 60, g => AnyFound()),
        G("earn1000",    "Earn 1,000 coins",                              100, g => Earned >= 1000, g => Earned.ToString("N0") + " of 1,000"),
        G("gold_find",   "Find gold in the quartz seam",                  100, g => g.goldSeen || (Money.Instance != null && Money.Instance.GoldStore > 0)),
        G("gold_sell",   "Sell gold at the gold buyer's shed",            100, g => g.goldSold),
        G("caves_all",   "Clear all three cave-ins",                      300, g => g.CaveClear(0) && g.CaveClear(1) && g.CaveClear(2), g => g.CavesLine()),
        G("dozer_fixed", "Fit all three parts: restore Dad's old dozer",  300, g => PartsFitted() == Finds.Count, g => PartsFitted() + " of " + Finds.Count + " fitted"),
        G("jackhammer",  "Buy the jackhammer",                            150, g => Upgrades.Instance != null && Upgrades.Instance.Level(Upgrades.Branch.Pick) >= 6),
        G("motor_cart",  "Buy the motor cart",                            200, g => Upgrades.Instance != null && Upgrades.Instance.HasMotorCart),
        // extras
        G("road_grade",  "Grade a stretch of the mountain road",          150, g => MountainRoadJob.Instance != null && MountainRoadJob.Instance.TickedCount >= 1),
        G("push50",      "Push 50 m3 of dirt with the dozer",             200, g => g.pushedM3 >= 50f, g => g.pushedM3.ToString("F0") + " of 50 m3"),
        // the game's goal: with the dozer restored, finish the road (then the ending plays: Ending.cs)
        G("road_done",   "Finish the mountain road: every stretch ticked", 250, g => MountainRoadJob.Instance != null && MountainRoadJob.Instance.TickedCount >= MountainRoad.Stretches,
                         g => (MountainRoadJob.Instance != null ? MountainRoadJob.Instance.TickedCount : 0) + " of " + MountainRoad.Stretches + " stretches ticked"),
    };

    // ------------------------------------------------------------------ state (saved)
    readonly HashSet<string> done = new HashSet<string>();
    float pushedM3;
    bool tipped, goldSeen, goldSold;

    public int Current { get; private set; }                           // index into List (List.Length = all done)
    public Goal? CurrentGoal { get { return Current < List.Length ? List[Current] : (Goal?)null; } }
    public string CurrentId { get { return Current < List.Length ? List[Current].id : ""; } }
    public bool IsDone(string id) { return done.Contains(id); }
    public int DoneCount { get { return done.Count; } }
    public float PushedM3 { get { return pushedM3; } }

    // on screen
    string tickText = ""; float tickTimer, checkTimer;
    float startedAt;

    void Awake() { Instance = this; startedAt = Time.time; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    // ------------------------------------------------------------------ what the game tells it
    public static void Tipped() { if (Instance != null) Instance.tipped = true; }
    public static void GoldSeen() { if (Instance != null) Instance.goldSeen = true; }
    public static void GoldSold() { if (Instance != null) Instance.goldSold = true; }
    public static void Pushed(int voxels) { if (Instance != null) Instance.pushedM3 += voxels * VoxelWorld.VoxelVolume; }

    // ------------------------------------------------------------------ checking
    void Update()
    {
        if (tickTimer > 0f) tickTimer -= Time.unscaledDeltaTime;
        if (Prologue.Playing || Time.time - startedAt < 1.5f) return;     // (the built game carries on from its save first)
        checkTimer -= Time.deltaTime;
        if (checkTimer > 0f) return;
        checkTimer = 0.5f;
        Check(true);
    }

    /// Ticks the current goal if it is done, and any after it that are already done too.
    public void Check(bool pay)
    {
        for (int guard = 0; guard < List.Length && Current < List.Length; guard++)
        {
            var g = List[Current];
            if (!done.Contains(g.id) && !g.done(this)) return;
            Tick(g, pay);
        }
    }

    void Tick(Goal g, bool pay)
    {
        bool fresh = done.Add(g.id);
        Current = NextOpen(0);
        if (!pay || !fresh) return;
        if (Money.Instance != null) Money.Instance.Bonus(g.bonus);
        GameAudio.Play("goal", 0.8f);
        tickText = g.text + "   +" + g.bonus + " coins";
        tickTimer = 3.5f;
    }

    int NextOpen(int from)
    {
        for (int i = from; i < List.Length; i++) if (!done.Contains(List[i].id)) return i;
        return List.Length;
    }

    /// For tests: counts the current goal as done (with its bonus).
    public void TestComplete() { if (Current < List.Length) Tick(List[Current], true); }

    // ---- the checks
    static long Earned { get { return Money.Instance != null ? Money.Instance.Earned : 0; } }
    static bool AnyUpgrade()
    {
        var u = Upgrades.Instance;
        return u != null && (u.Level(Upgrades.Branch.Pick) > 1 || u.Level(Upgrades.Branch.Shovel) > 1 || u.Level(Upgrades.Branch.Backpack) > 0 || u.Level(Upgrades.Branch.Cart) > 1);
    }
    static int PartsFitted()
    {
        var f = Finds.Instance;
        int n = 0;
        if (f != null) for (int k = 0; k < Finds.Count; k++) if (f.Installed[k]) n++;
        return n;
    }
    static bool AnyFound()
    {
        var f = Finds.Instance;
        if (f == null) return false;
        for (int k = 0; k < Finds.Count; k++) if (f.Found[k] || f.Collected[k]) return true;
        return false;
    }
    bool CartFull()
    {
        var c = MineCart.Instance; var w = VoxelWorld.Instance;
        return c != null && w != null && w.CartVoxels >= c.capacity * 0.9f;
    }
    string CartLine()
    {
        var c = MineCart.Instance; var w = VoxelWorld.Instance;
        if (c == null || w == null) return null;
        float l = w.CartVoxels * VoxelWorld.VoxelVolume * 1000f, h = c.capacity * VoxelWorld.VoxelVolume * 1000f;
        return l.ToString("F0") + " of " + h.ToString("F0") + " L";
    }
    string CavesLine() { int n = 0; for (int c = 0; c < 3; c++) if (CaveClear(c)) n++; return n + " of 3 clear"; }

    // ---- the cave-ins (the three collapses in the tunnel, VoxelWorld.CollapseFill)
    // metres along the tunnel from its mouth
    public static readonly float[] CaveFrom = { 3f, 13f, 23f }, CaveTo = { 7f, 19f, 28f };
    /// How full a fresh cave-in is (share of the tunnel's space, from GoalsTest); a bit less than this means dug into.
    public static readonly float[] FreshFill = { 0.80f, 0.52f, 0.61f };   // (the second and third are part-blocked: VoxelWorld.CollapseShare)
    public const float DugBy = 0.03f, ClearHeight = 0.5f;

    /// The share of the tunnel's space (floor to roof, wall to wall) that is ground or rubble in cave-in c.
    public float CaveFill(int c)
    {
        var w = VoxelWorld.Instance;
        if (w == null) return 1f;
        int solid = 0, all = 0;
        for (float a = CaveFrom[c] + 0.25f; a < CaveTo[c]; a += 0.25f)
        {
            float half = VoxelWorld.TunnelHalfWidthAt(a) - 0.15f, top = VoxelWorld.TunnelHeightAt(a) - 0.1f;
            for (float x = -half; x <= half; x += 0.3f)
                for (float y = 0.03f; y < top; y += 0.125f)
                {
                    all++;
                    if (w.MaterialAt(new Vector3(VoxelWorld.PortalX + x, y, VoxelWorld.PortalZ + a)) != VoxelWorld.Air) solid++;
                }
        }
        return all > 0 ? (float)solid / all : 1f;
    }

    public bool CaveDug(int c) { return CaveFill(c) < FreshFill[c] - DugBy || CaveClear(c); }

    /// A way through for the cart: along the rails (the middle of the tunnel) the rubble is nowhere higher than ClearHeight.
    public bool CaveClear(int c) { return CaveHighest(c) < ClearHeight; }

    /// The highest rubble along the middle of cave-in c, in metres above the floor.
    public float CaveHighest(int c)
    {
        var w = VoxelWorld.Instance;
        if (w == null) return 9f;
        float worst = 0f;
        for (float a = CaveFrom[c]; a <= CaveTo[c]; a += 0.25f)
            for (float x = -0.5f; x <= 0.51f; x += 0.5f)
            {
                float y = 0.03f;
                while (y < 2.5f && w.MaterialAt(new Vector3(VoxelWorld.PortalX + x, y, VoxelWorld.PortalZ + a)) != VoxelWorld.Air) y += 0.0625f;
                worst = Mathf.Max(worst, y - 0.03f);
            }
        return worst;
    }

    // ------------------------------------------------------------------ saving
    public void WriteState(System.IO.BinaryWriter w)
    {
        w.Write(1);                                                     // this section's own version
        w.Write(done.Count);
        foreach (var id in done) w.Write(id);
        w.Write(pushedM3); w.Write(tipped); w.Write(goldSeen); w.Write(goldSold);
    }

    public void ReadState(System.IO.BinaryReader r)
    {
        int version = r.ReadInt32();
        done.Clear();
        int n = r.ReadInt32();
        for (int i = 0; i < n; i++) done.Add(r.ReadString());
        pushedM3 = r.ReadSingle(); tipped = r.ReadBoolean(); goldSeen = r.ReadBoolean(); goldSold = r.ReadBoolean();
        if (version > 1) { }                                            // (later versions add their fields after these)
        Current = NextOpen(0);
        tickTimer = 0f;
    }

    public void Reset() { done.Clear(); pushedM3 = 0f; tipped = goldSeen = goldSold = false; Current = 0; tickTimer = 0f; }

    /// A save from before there were goals: work out what it has already done, and skip those (no bonus).
    public void FromOldSave()
    {
        Reset();
        var m = Money.Instance;
        if (m != null && m.Earned > 0) tipped = true;                     // it has sold a load at the hopper
        if (m != null && m.GoldStore > 0) goldSeen = true;
        for (int i = 0; i < List.Length; i++) if (List[i].done(this)) done.Add(List[i].id);
        if (done.Contains("cave1_clear")) done.Add("cave1_dig");
        if (done.Contains("caves_all")) { done.Add("cave1_dig"); done.Add("cave1_clear"); }
        if (done.Contains("gold_sell")) done.Add("gold_find");
        Current = NextOpen(0);
    }

    // ------------------------------------------------------------------ on screen: top middle
    void OnGUI()
    {
        if (Prologue.Playing) return;
        Ui.Begin();
        float w = 560f, x = (Ui.W - w) / 2f, y = 10f;
        if (tickTimer > 0f)
        {
            var st = new GUIStyle(GUI.skin.box) { fontSize = 18, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            st.normal.textColor = new Color(0.45f, 1f, 0.5f);
            GUI.Box(new Rect(x, y, w, 34f), "DONE!   " + tickText, st);
            return;
        }
        if (Current >= List.Length) return;
        var g = List[Current];
        string prog = g.progress != null ? g.progress(this) : null;
        var head = new GUIStyle(GUI.skin.label) { fontSize = 13, fontStyle = FontStyle.Bold, alignment = TextAnchor.UpperCenter };
        head.normal.textColor = new Color(1f, 0.82f, 0.3f);
        var body = new GUIStyle(GUI.skin.label) { fontSize = 17, alignment = TextAnchor.UpperCenter, wordWrap = true };
        float h = 50f + (prog != null ? 18f : 0f);
        GUI.Box(new Rect(x, y, w, h), GUIContent.none);
        GUI.Label(new Rect(x, y + 3f, w, 18f), "GOAL  (+" + g.bonus + " coins)", head);
        GUI.Label(new Rect(x + 8f, y + 21f, w - 16f, 24f), g.text, body);
        if (prog != null)
        {
            var small = new GUIStyle(GUI.skin.label) { fontSize = 13, alignment = TextAnchor.UpperCenter };
            small.normal.textColor = new Color(0.8f, 0.8f, 0.8f);
            GUI.Label(new Rect(x, y + 46f, w, 18f), prog, small);
        }
    }
}
