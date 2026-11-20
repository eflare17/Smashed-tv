// The mountain road job: build the road up the mountain to its grade (see MountainRoad.cs for the line and the ground).
//
// The guides, all worked out from the real ground as it is now, a few times a second:
//   - survey pegs every 5 m along each edge of the road, tagged with how far the ground there is from grade:
//     "CUT 1.2" = the ground is 1.2 m too high, cut it down; "FILL 0.4" = 0.4 m too low, fill it; "ON GRADE" within 10 cm;
//   - a tint on the road itself: red = too high (cut), blue = too low (fill), green = on grade (within 10 cm);
//   - in the cab, when the dozer is on the road: the road's slope against the machine's, how far the blade's cutting
//     edge is above or below grade, and an arrow: lower the blade, or raise it.
// A small key on screen explains every colour.
//
// Finishing: the road is judged in 15 stretches.  A stretch gets a green tick once 7 in 10 of it is within 15 cm of
// grade (a little looser than the green tint, so a reasonable job counts).  A tick, once earned, stays.  When all 15
// are ticked the job pays 500 coins, once.
using System.Collections.Generic;
using UnityEngine;

public class MountainRoadJob : MonoBehaviour
{
    public static MountainRoadJob Instance { get; private set; }

    public const float OnGrade = 0.10f;          // the green tint and the pegs' "ON GRADE": within this of grade
    public const float TickTolerance = 0.15f;    // for a stretch's tick, the ground counts as on grade within this
    public const float TickShare = 0.70f;        // and this much of the stretch must be
    public const long Reward = 500;              // coins when every stretch is ticked
    const float Cell = 0.25f;                    // the tint's squares
    const float RefreshEvery = 0.25f;

    static readonly Color32 CutColour = new Color32(220, 40, 30, 150), FillColour = new Color32(40, 90, 230, 150), GradeColour = new Color32(40, 200, 60, 150);

    // the road's surface, square by square: where, the grade there, which stretch, and which square of the tint picture
    float[] sx, sz, sg; int[] sk, si;
    Texture2D tint; Color32[] tintPx;
    int tw, th; Vector2 tintMin;
    readonly int[] inTol = new int[MountainRoad.Stretches], total = new int[MountainRoad.Stretches];
    readonly bool[] ticked = new bool[MountainRoad.Stretches];
    public bool Paid { get; private set; }
    float refreshTimer;
    public float LastRefreshMs { get; private set; }
    public float SetupMs { get; private set; }

    // the pegs
    struct Peg { public Transform post, label; public TextMesh text; public float s, side; public Vector2 at; public float value; }
    readonly List<Peg> pegs = new List<Peg>();
    // the ticks, one per stretch, beside the road
    readonly GameObject[] tickSigns = new GameObject[MountainRoad.Stretches];

    Texture2D white, arrow;
    VoxelWorld world;
    DozerController dozer;
    string payNote = ""; float payNoteUntil;
    public string CabText { get; private set; }  // what the cab readout last showed ("" = not shown)
    public bool LegendShown { get; private set; }
    public int CabArrow { get; private set; }    // -1 lower, +1 raise, 0 on grade

    void Awake() { Instance = this; CabText = ""; }
    void OnDestroy() { if (Instance == this) Instance = null; Shader.SetGlobalFloat("_RoadTintOn", 0f); }

    void Start()
    {
        world = VoxelWorld.Instance;
        if (world == null) { enabled = false; return; }
        var watch = System.Diagnostics.Stopwatch.StartNew();
        BuildSquares();
        BuildPegs();
        BuildTicks();
        OpenFence();
        white = Texture2D.whiteTexture;
        arrow = MakeArrow();
        Refresh();
        SetupMs = (float)watch.Elapsed.TotalMilliseconds;
    }

    // ------------------------------------------------------------------ setting up
    void BuildSquares()
    {
        Vector2 lo = MountainRoad.Min - Vector2.one * 3f, hi = MountainRoad.Max + Vector2.one * 3f;
        tintMin = lo;
        tw = Mathf.CeilToInt((hi.x - lo.x) / Cell); th = Mathf.CeilToInt((hi.y - lo.y) / Cell);
        var lx = new List<float>(); var lz = new List<float>(); var lg = new List<float>(); var lk = new List<int>(); var li = new List<int>();
        // a quick first pass on a 2 m grid, so only squares near the line are looked at closely
        const float coarse = 2f;
        int cw = Mathf.CeilToInt((hi.x - lo.x) / coarse), ch = Mathf.CeilToInt((hi.y - lo.y) / coarse);
        for (int cj = 0; cj < ch; cj++)
            for (int ci = 0; ci < cw; ci++)
            {
                float cx = lo.x + (ci + 0.5f) * coarse, cz = lo.y + (cj + 0.5f) * coarse;
                if (MountainRoad.DistanceTo(cx, cz) > MountainRoad.RoadHalf + coarse) continue;
                int per = Mathf.RoundToInt(coarse / Cell);
                for (int j = 0; j < per; j++)
                    for (int i = 0; i < per; i++)
                    {
                        int ti = ci * per + i, tj = cj * per + j;
                        if (ti >= tw || tj >= th) continue;
                        float x = lo.x + (ti + 0.5f) * Cell, z = lo.y + (tj + 0.5f) * Cell, s, off;
                        Vector2 dir;
                        if (MountainRoad.Nearest(x, z, out s, out off, out dir) > MountainRoad.RoadHalf) continue;
                        if (world.KindAt(x, z) == 0) continue;
                        lx.Add(x); lz.Add(z); lg.Add(MountainRoad.GradeAt(s)); lk.Add(MountainRoad.StretchOf(s)); li.Add(ti + tw * tj);
                    }
            }
        sx = lx.ToArray(); sz = lz.ToArray(); sg = lg.ToArray(); sk = lk.ToArray(); si = li.ToArray();
        for (int k = 0; k < sk.Length; k++) total[sk[k]]++;
        tint = new Texture2D(tw, th, TextureFormat.RGBA32, false, true) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp, name = "Road tint" };
        tintPx = new Color32[tw * th];
        Shader.SetGlobalTexture("_RoadTint", tint);
        Shader.SetGlobalVector("_RoadRect", new Vector4(lo.x, lo.y, 1f / (tw * Cell), 1f / (th * Cell)));
        Shader.SetGlobalFloat("_RoadTintOn", 1f);
    }

    static Material Plain(Color c)
    {
        var m = new Material(Shader.Find("Standard")) { color = c };
        m.SetFloat("_Glossiness", 0.1f);
        return m;
    }

    static GameObject Block(Transform parent, Vector3 localPos, Vector3 size, Material mat, Quaternion rot)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
        Destroy(go.GetComponent<Collider>());
        go.transform.SetParent(parent, false);
        go.transform.localPosition = localPos; go.transform.localRotation = rot; go.transform.localScale = size;
        go.GetComponent<MeshRenderer>().sharedMaterial = mat;
        return go;
    }

    void BuildPegs()
    {
        var stake = Plain(new Color(0.85f, 0.70f, 0.45f));
        var flag = Plain(new Color(1f, 0.45f, 0.05f));
        var font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        var root = new GameObject("Survey pegs").transform;
        root.SetParent(transform, false);
        for (float s = 0f; s <= MountainRoad.Length + 0.01f; s += 5f)
            for (int side = -1; side <= 1; side += 2)
            {
                Vector2 at = PointAt(s, side * (MountainRoad.RoadHalf + 0.25f));
                var post = new GameObject("Peg " + s.ToString("F0") + (side < 0 ? " R" : " L")).transform;
                post.SetParent(root, false);
                Block(post, new Vector3(0f, 0.45f, 0f), new Vector3(0.07f, 0.9f, 0.07f), stake, Quaternion.identity);
                Block(post, new Vector3(0f, 0.86f, 0f), new Vector3(0.09f, 0.14f, 0.09f), flag, Quaternion.identity);
                var label = new GameObject("Tag").transform;
                label.SetParent(post, false);
                label.localPosition = new Vector3(0f, 1.05f, 0f);
                var tm = label.gameObject.AddComponent<TextMesh>();
                tm.font = font; tm.fontSize = 64; tm.characterSize = 0.035f; tm.anchor = TextAnchor.LowerCenter; tm.fontStyle = FontStyle.Bold;
                label.GetComponent<MeshRenderer>().sharedMaterial = font.material;
                pegs.Add(new Peg { post = post, label = label, text = tm, s = s, side = side, at = at });
            }
    }

    void BuildTicks()
    {
        var green = Plain(new Color(0.15f, 0.85f, 0.25f));
        green.EnableKeyword("_EMISSION"); green.SetColor("_EmissionColor", new Color(0.05f, 0.4f, 0.1f));
        var post = Plain(new Color(0.85f, 0.85f, 0.82f));
        var root = new GameObject("Stretch ticks").transform;
        root.SetParent(transform, false);
        for (int k = 0; k < MountainRoad.Stretches; k++)
        {
            float s = (k + 0.5f) * MountainRoad.Length / MountainRoad.Stretches;
            Vector2 at = PointAt(s, MountainRoad.RoadHalf + 1.1f);
            var sign = new GameObject("Tick " + (k + 1));
            sign.transform.SetParent(root, false);
            sign.transform.position = new Vector3(at.x, 0f, at.y);
            Block(sign.transform, new Vector3(0f, 0.7f, 0f), new Vector3(0.08f, 1.4f, 0.08f), post, Quaternion.identity);
            // a tick: a short stroke and a long one
            Block(sign.transform, new Vector3(-0.17f, 1.55f, 0f), new Vector3(0.12f, 0.36f, 0.06f), green, Quaternion.Euler(0f, 0f, 40f));
            Block(sign.transform, new Vector3(0.12f, 1.7f, 0f), new Vector3(0.12f, 0.7f, 0.06f), green, Quaternion.Euler(0f, 0f, -30f));
            sign.SetActive(false);
            tickSigns[k] = sign;
        }
    }

    /// The site fence crosses the road: take out the posts and rail where the road goes through.
    void OpenFence()
    {
        var fence = GameObject.Find("Site fence");
        if (fence == null) return;
        var rails = new List<Transform>();
        foreach (Transform c in fence.transform)
        {
            Vector3 p = c.position, sc = c.lossyScale;
            if (p.z < VoxelWorld.SiteHalf - 3f) continue;                     // only the north side
            if (sc.x > 5f) { rails.Add(c); continue; }
            if (SiteProps.NearRoad(p.x, p.z, MountainRoad.StripHalf + 1f)) c.gameObject.SetActive(false);
        }
        foreach (var rail in rails)
        {
            // the rail runs the whole side: cut it into lengths that stop short of the road
            Vector3 p = rail.position, sc = rail.localScale;
            float x0 = p.x - rail.lossyScale.x * 0.5f, x1 = p.x + rail.lossyScale.x * 0.5f, from = x0;
            bool open = false;
            for (float x = x0; x <= x1 + 0.01f; x += 0.25f)
            {
                bool gap = x < x1 && SiteProps.NearRoad(x, p.z, MountainRoad.StripHalf + 1f);
                if (gap && !open) { Piece(rail, from, x); open = true; }
                if (!gap && open) { from = x; open = false; }
            }
            if (!open) Piece(rail, from, x1);
            rail.gameObject.SetActive(false);
        }
    }

    static void Piece(Transform rail, float a, float b)
    {
        if (b - a < 0.3f) return;
        var copy = Instantiate(rail.gameObject, rail.parent);
        copy.name = rail.name + " (piece)";
        Vector3 p = rail.position; p.x = (a + b) * 0.5f;
        copy.transform.position = p;
        Vector3 sc = copy.transform.localScale; sc.x *= (b - a) / rail.lossyScale.x;
        copy.transform.localScale = sc;
    }

    static Texture2D MakeArrow()
    {
        const int n = 32;
        var t = new Texture2D(n, n, TextureFormat.RGBA32, false) { filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Clamp };
        var px = new Color32[n * n];
        for (int y = 0; y < n; y++)
            for (int x = 0; x < n; x++)
            {
                // pointing down: wide at the top, a point at the bottom
                float half = (y + 0.5f) / n * 0.5f;
                bool inside = Mathf.Abs((x + 0.5f) / n - 0.5f) < half;
                px[x + n * y] = inside ? new Color32(255, 255, 255, 255) : new Color32(255, 255, 255, 0);
            }
        t.SetPixels32(px); t.Apply(false);
        return t;
    }

    static Vector2 PointAt(float s, float off)
    {
        int n = MountainRoad.Count;
        int i = Mathf.Clamp(Mathf.FloorToInt(s / MountainRoad.Step), 0, n - 2);
        float u = Mathf.Clamp01((s - MountainRoad.AlongAt(i)) / MountainRoad.Step);
        Vector2 a = MountainRoad.Point(i), b = MountainRoad.Point(i + 1);
        Vector2 dir = (b - a).normalized, left = new Vector2(-dir.y, dir.x);
        return Vector2.Lerp(a, b, u) + left * off;
    }

    // ------------------------------------------------------------------ keeping up with the ground
    void Update()
    {
        refreshTimer -= Time.deltaTime;
        if (refreshTimer <= 0f) { refreshTimer = RefreshEvery; Refresh(); }
    }

    /// Works everything out again from the ground as it is now: the tint, the pegs, the stretches and their ticks.
    public void Refresh()
    {
        if (world == null || sx == null) return;
        var watch = System.Diagnostics.Stopwatch.StartNew();
        System.Array.Clear(inTol, 0, inTol.Length);
        for (int k = 0; k < sx.Length; k++)
        {
            float d = world.TopAt(sx[k], sz[k]) - sg[k];
            tintPx[si[k]] = d > OnGrade ? CutColour : d < -OnGrade ? FillColour : GradeColour;
            if (Mathf.Abs(d) <= TickTolerance) inTol[sk[k]]++;
        }
        tint.SetPixels32(tintPx); tint.Apply(false);
        for (int i = 0; i < pegs.Count; i++)
        {
            var p = pegs[i];
            float h = world.HeightAt(p.at.x, p.at.y);
            p.value = h - MountainRoad.GradeAt(p.s);
            p.post.position = new Vector3(p.at.x, h, p.at.y);
            p.text.text = Mathf.Abs(p.value) <= OnGrade ? "ON GRADE" : (p.value > 0f ? "CUT " : "FILL ") + Mathf.Abs(p.value).ToString("F1");
            p.text.color = Mathf.Abs(p.value) <= OnGrade ? new Color(0.3f, 1f, 0.35f) : p.value > 0f ? new Color(1f, 0.35f, 0.3f) : new Color(0.45f, 0.65f, 1f);
            pegs[i] = p;
        }
        for (int k = 0; k < ticked.Length; k++)
        {
            if (!ticked[k] && total[k] > 0 && inTol[k] >= TickShare * total[k]) ticked[k] = true;
            if (tickSigns[k] != null)
            {
                tickSigns[k].SetActive(ticked[k]);
                if (ticked[k])
                {
                    Vector3 sp = tickSigns[k].transform.position;
                    sp.y = world.HeightAt(sp.x, sp.z);
                    tickSigns[k].transform.position = sp;
                }
            }
        }
        if (!Paid && TickedCount == MountainRoad.Stretches)
        {
            Paid = true;
            if (Money.Instance != null) Money.Instance.Reward(Reward, "Mountain road finished: all 15 stretches on grade.  +" + Reward + " coins");
            payNote = "Mountain road finished!  +" + Reward + " coins"; payNoteUntil = Time.time + 6f;
        }
        LastRefreshMs = (float)watch.Elapsed.TotalMilliseconds;
    }

    void LateUpdate()
    {
        var cam = Camera.main;
        if (cam == null) return;
        Vector3 cp = cam.transform.position;
        for (int i = 0; i < pegs.Count; i++)
        {
            var p = pegs[i];
            float d = Vector2.Distance(new Vector2(cp.x, cp.z), p.at);
            bool show = d < 55f;
            if (p.label.gameObject.activeSelf != show) p.label.gameObject.SetActive(show);
            if (show) p.label.rotation = Quaternion.LookRotation(p.label.position - cp);    // the tag faces the camera
        }
    }

    // ------------------------------------------------------------------ questions (the HUD and tests)
    public int TickedCount { get { int n = 0; foreach (bool t in ticked) if (t) n++; return n; } }
    public bool Ticked(int k) { return ticked[k]; }
    /// How much of stretch k is within TickTolerance of grade (0..1), as of the last refresh.
    public float StretchShare(int k) { return total[k] > 0 ? inTol[k] / (float)total[k] : 0f; }
    public int StretchSquares(int k) { return total[k]; }
    public int SquareCount { get { return sx != null ? sx.Length : 0; } }
    public int PegCount { get { return pegs.Count; } }
    public string PegText(int i) { return pegs[i].text.text; }
    public float PegValue(int i) { return pegs[i].value; }
    public Vector2 PegAt(int i) { return pegs[i].at; }
    public float PegAlong(int i) { return pegs[i].s; }
    /// The tint on the road square at (x, z): 1 red (cut), -1 blue (fill), 0 green, 99 not on the road.
    public int TintAt(float x, float z)
    {
        int ti = Mathf.FloorToInt((x - tintMin.x) / Cell), tj = Mathf.FloorToInt((z - tintMin.y) / Cell);
        if (ti < 0 || tj < 0 || ti >= tw || tj >= th) return 99;
        var c = tintPx[ti + tw * tj];
        if (c.a == 0) return 99;
        return c.r == CutColour.r && c.b == CutColour.b ? 1 : c.b == FillColour.b && c.r == FillColour.r ? -1 : 0;
    }
    /// For tests: every road square of stretch k (its own squares only), set to grade.
    public void TestGradeStretch(int k)
    {
        for (int i = 0; i < sx.Length; i++)
            if (sk[i] == k) SetSquare(i);
    }
    void SetSquare(int i)
    {
        // a road square is 4 x 4 voxel columns
        for (float dz = -Cell * 0.5f + 0.03f; dz < Cell * 0.5f; dz += VoxelWorld.Voxel)
            for (float dx = -Cell * 0.5f + 0.03f; dx < Cell * 0.5f; dx += VoxelWorld.Voxel)
                world.TestSetColumn(sx[i] + dx, sz[i] + dz, sg[i]);
    }
    public void TestClearTicks() { System.Array.Clear(ticked, 0, ticked.Length); Paid = false; }

    // ------------------------------------------------------------------ saving
    public void WriteState(System.IO.BinaryWriter w)
    {
        w.Write(ticked.Length);
        for (int k = 0; k < ticked.Length; k++) w.Write(ticked[k]);
        w.Write(Paid);
    }

    public void ReadState(System.IO.BinaryReader r)
    {
        int n = r.ReadInt32();
        for (int k = 0; k < n; k++) { bool t = r.ReadBoolean(); if (k < ticked.Length) ticked[k] = t; }
        Paid = r.ReadBoolean();
        Refresh();
    }

    public void Clear() { TestClearTicks(); }

    // ------------------------------------------------------------------ on screen
    void OnGUI()
    {
        if (Prologue.Playing || world == null) return;
        if (dozer == null) dozer = FindFirstObjectByType<DozerController>();
        Vector3 here = dozer != null && dozer.driven ? dozer.transform.position : Worker.Instance != null ? Worker.Instance.transform.position : Vector3.zero;
        float s, off; Vector2 dir;
        float dist = MountainRoad.Nearest(here.x, here.z, out s, out off, out dir);
        LegendShown = dist < 25f;
        if (LegendShown) Legend();
        CabText = "";
        if (dozer != null && dozer.driven && dist <= MountainRoad.CorridorHalf) Cab(s, dir);
        if (Time.time < payNoteUntil)
        {
            var big = new GUIStyle(GUI.skin.box) { fontSize = 24, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            big.normal.textColor = new Color(0.4f, 1f, 0.45f);
            GUI.Box(new Rect(Screen.width / 2 - 300, Screen.height / 2 - 140, 600, 50), payNote, big);
        }
    }

    void Swatch(Rect r, Color c) { var old = GUI.color; GUI.color = c; GUI.DrawTexture(r, white); GUI.color = old; }

    void Legend()
    {
        const float W = 480f, H = 178f;
        float x = 10f, y = Screen.height - H - 44f;                 // (above the "get out" box)
        GUI.Box(new Rect(x, y, W, H), "");
        var head = new GUIStyle(GUI.skin.label) { fontSize = 15, fontStyle = FontStyle.Bold };
        var line = new GUIStyle(GUI.skin.label) { fontSize = 13 };
        GUI.Label(new Rect(x + 10, y + 6, W - 20, 22), "MOUNTAIN ROAD   " + TickedCount + " / " + MountainRoad.Stretches + " ticked   " + (Paid ? "(paid " + Reward + " coins)" : "(all ticked pays " + Reward + " coins)"), head);
        float ly = y + 30f;
        Swatch(new Rect(x + 12, ly + 3, 22, 13), CutColour.AsOpaque()); GUI.Label(new Rect(x + 42, ly, W - 50, 20), "RED: ground too high.  Cut it down.", line); ly += 20f;
        Swatch(new Rect(x + 12, ly + 3, 22, 13), FillColour.AsOpaque()); GUI.Label(new Rect(x + 42, ly, W - 50, 20), "BLUE: ground too low.  Fill it.", line); ly += 20f;
        Swatch(new Rect(x + 12, ly + 3, 22, 13), GradeColour.AsOpaque()); GUI.Label(new Rect(x + 42, ly, W - 50, 20), "GREEN: on grade (within " + Mathf.RoundToInt(OnGrade * 100f) + " cm).", line); ly += 20f;
        GUI.Label(new Rect(x + 12, ly, W - 20, 20), "Pegs: CUT 1.2 = cut 1.2 m down there.  FILL 0.4 = fill 0.4 m up.", line); ly += 20f;
        Swatch(new Rect(x + 12, ly + 3, 22, 13), new Color(0.15f, 0.85f, 0.25f));
        GUI.Label(new Rect(x + 42, ly, W - 50, 36), "Green tick beside the road: that stretch is done\n(7 in 10 of it within " + Mathf.RoundToInt(TickTolerance * 100f) + " cm of grade).", line); ly += 38f;
        GUI.Label(new Rect(x + 12, ly, W - 20, 20), "No colour: not the road.  Grey wall: the mountain, can't be dug.", line);
    }

    void Cab(float s, Vector2 roadDir)
    {
        Vector3 fwd = dozer.transform.forward;
        Vector2 f2 = new Vector2(fwd.x, fwd.z);
        float facing = f2.sqrMagnitude > 1e-4f && Vector2.Dot(f2.normalized, roadDir) < 0f ? -1f : 1f;   // facing down the road: it falls
        float roadDeg = Mathf.Atan(MountainRoad.SlopeAt(s)) * Mathf.Rad2Deg * facing;
        float machineDeg = Mathf.Asin(Mathf.Clamp(fwd.y, -1f, 1f)) * Mathf.Rad2Deg;
        string text = "ROAD GUIDE\n";
        text += "Road slope    " + Updown(roadDeg) + (Mathf.Abs(roadDeg) > 0.5f ? "  (1 in 8)" : "  (the flat top)") + "\n";
        text += "Machine       " + Updown(machineDeg) + "\n";
        var blade = dozer.Blade;
        float edgeOff = 0f;
        bool haveBlade = blade != null;
        if (haveBlade)
        {
            Vector3 edge = (blade.TransformPoint(new Vector3(-2.25f, -0.75f, 1.1f)) + blade.TransformPoint(new Vector3(2.25f, -0.75f, 1.1f))) * 0.5f;
            float es, eoff; Vector2 ed;
            MountainRoad.Nearest(edge.x, edge.z, out es, out eoff, out ed);
            edgeOff = edge.y - MountainRoad.GradeAt(es);
            text += "Blade edge    " + Mathf.Abs(edgeOff).ToString("F2") + " m " + (edgeOff >= 0f ? "above" : "below") + " grade";
        }
        CabArrow = !haveBlade || Mathf.Abs(edgeOff) <= OnGrade ? 0 : edgeOff > 0f ? -1 : 1;
        string act = CabArrow < 0 ? "LOWER the blade" : CabArrow > 0 ? "RAISE the blade" : "Blade ON GRADE";
        CabText = text + "\n" + act;

        const float W = 300f, H = 150f;
        float x = Screen.width - W - 10f, y = Screen.height - H - 48f;   // bottom right, clear of the blade view and the upgrades box
        GUI.Box(new Rect(x, y, W, H), "");
        var st = new GUIStyle(GUI.skin.label) { fontSize = 14, fontStyle = FontStyle.Bold };
        GUI.Label(new Rect(x + 10, y + 6, W - 20, 90), text, st);
        var actStyle = new GUIStyle(GUI.skin.label) { fontSize = 18, fontStyle = FontStyle.Bold };
        Color ac = CabArrow < 0 ? new Color(1f, 0.4f, 0.3f) : CabArrow > 0 ? new Color(0.5f, 0.7f, 1f) : new Color(0.4f, 1f, 0.45f);
        actStyle.normal.textColor = ac;
        GUI.Label(new Rect(x + 62, y + 108, W - 70, 30), act, actStyle);
        var old = GUI.color; GUI.color = ac;
        Rect ar = new Rect(x + 16, y + 98, 38, 42);
        if (CabArrow < 0) GUI.DrawTexture(ar, arrow);                                            // pointing down
        else if (CabArrow > 0) GUI.DrawTextureWithTexCoords(ar, arrow, new Rect(0, 1, 1, -1));  // flipped: pointing up
        else GUI.DrawTexture(new Rect(x + 18, y + 114, 34, 10), white);                          // level
        GUI.color = old;
    }

    static string Updown(float deg) { return Mathf.Abs(deg) < 0.5f ? "level" : Mathf.Abs(deg).ToString("F1") + "° " + (deg > 0f ? "up" : "down"); }
}

static class ColourExt
{
    public static Color AsOpaque(this Color32 c) { return new Color(c.r / 255f, c.g / 255f, c.b / 255f, 1f); }
}
