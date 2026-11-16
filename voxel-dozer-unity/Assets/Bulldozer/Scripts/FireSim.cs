// The bushfire, for the prologue.  Not used in normal play (the game is set twenty years after it).
//
// The ground is a grid of 2 m squares, each with fuel or not: grass, bush and forest burn; bare dirt, the track,
// the quarry and anything the dozer has scraped bare don't.  Fire spreads square to square on its own clock:
//   - with the wind it runs fast, against it slowly, and a little faster uphill;
//   - a square is checked for fuel when the fire gets there, so a firebreak cut while the fire is coming still works;
//   - in a strong wind, burning squares throw embers well ahead that start spot fires, and burning crowns light the
//     crowns downwind of them.  So a break holds in a light wind, and a wind change can carry the fire over it.
// Every tree knows when it caught.  The ground shader (VoxelTerrain) does the rest from two small textures: each
// tree scorches orange, glows, goes black and loses its leaves; the ground chars behind a glowing front.
// Badly burnt trees fall: thinner trees, and trees burning in a strong wind, are likelier to; one that falls goes
// 14-40 s after it caught, mostly downwind.  The shader tips it over (and its shadow); once down, its trunk is solid
// (SiteProps.Blocks).  The prologue can also fell a chosen tree at a chosen moment (FellTree).
// It is all seeded, so the same fire plays out the same way every time.
using System.Collections.Generic;
using UnityEngine;

public class FireSim : MonoBehaviour
{
    public static FireSim Instance { get; private set; }

    public const float Cell = 2f, X0 = -110f, Z0 = -2f;
    public const int W = 110, H = 96;                              // x -110..110, z -2..190

    // the trees, registered by SiteProps as it builds them (their id is in their blocks' vertex colours)
    public struct FireTree
    {
        public Vector3 at; public float height;
        public Vector3 top;                                        // where the trunk ends and the branches start
        public Vector3[] clumps;                                   // the leaf clumps, where the crown burns
    }
    /// For each tree, the burning tree whose crown lit it (-1: it caught from the ground).  For FireFX.
    public int LitFrom(int t) { return litFrom != null && t < litFrom.Length ? litFrom[t] : -1; }
    int[] litFrom; float[] litFromAt;
    public static readonly List<FireTree> Trees = new List<FireTree>();

    public bool Running { get; private set; }
    public float Now { get; private set; }                         // seconds since the fire started
    public float speedUp = 1f;                                     // tests and recordings run it faster
    public int CellsBurnt { get; private set; }
    public int TreesBurnt { get; private set; }

    // wind: from windA to windB over a few seconds at windChangeAt (metres a second, the way it blows)
    Vector2 windA = new Vector2(0f, -5f), windB = new Vector2(0f, -5f);
    float windChangeAt = 1e9f, windChangeTook = 4f;

    float[] fuel, cellIgnite, treeIgnite, treeFallAt, treeFallAngle;
    public const float FallTook = 2.6f;                            // seconds from starting to tip to hitting the ground
    public int TreesFallen { get; private set; }
    /// Trees that have just hit the ground, for FireFX's sparks (it empties this).
    public readonly List<int> Landed = new List<int>();
    const int LandFlag = 1 << 25;
    List<int>[] treesIn;                                           // trees standing in each square
    List<int>[] treeNear;                                          // trees within crown reach of each tree
    readonly List<int> burning = new List<int>();                  // squares alight now (for embers)
    float emberClock;
    System.Random rng = new System.Random(1998);
    Texture2D treeTex, groundTex;
    readonly List<int> newCells = new List<int>(), newTrees = new List<int>();
    const float Never = 1e6f;

    // a small heap of (time, index); cells and trees in one, trees flagged by adding a big offset
    readonly List<float> heapT = new List<float>();
    readonly List<int> heapI = new List<int>();
    const int TreeFlag = 1 << 24;

    void Awake() { Instance = this; Shader.SetGlobalFloat("_FireTime", -1e6f); }
    void OnDestroy() { if (Instance == this) Instance = null; Shader.SetGlobalFloat("_FireTime", -1e6f); }

    void Start() { Build(); }

    public Vector2 WindAt(float t) { return Vector2.Lerp(windA, windB, Mathf.SmoothStep(0f, 1f, (t - windChangeAt) / windChangeTook)); }

    /// The wind before and after a change at `at` seconds.
    public void SetWind(Vector2 before, Vector2 after, float at) { windA = before; windB = after; windChangeAt = at; }

    static int CellOf(float x, float z)
    {
        int i = Mathf.FloorToInt((x - X0) / Cell), j = Mathf.FloorToInt((z - Z0) / Cell);
        return i < 0 || j < 0 || i >= W || j >= H ? -1 : i + W * j;
    }
    static Vector3 CentreOf(int c) { return new Vector3(X0 + (c % W + 0.5f) * Cell, 0f, Z0 + (c / W + 0.5f) * Cell); }

    /// Does this square have anything to burn right now?
    bool HasFuel(int c)
    {
        Vector3 p = CentreOf(c);
        var w = VoxelWorld.Instance;
        bool inSite = p.z < VoxelWorld.NZ / 2 * VoxelWorld.Voxel - 0.5f && Mathf.Abs(p.x) < VoxelWorld.NX / 2 * VoxelWorld.Voxel - 0.5f;
        if (inSite) return fuel[c] > 0f && ((w != null && w.GrassAt(p.x, p.z) > 0) || treesIn[c].Count > 0);
        return fuel[c] > 0f;
    }

    void Build()
    {
        int n = W * H;
        fuel = new float[n]; cellIgnite = new float[n]; treesIn = new List<int>[n];
        for (int c = 0; c < n; c++)
        {
            treesIn[c] = new List<int>();
            cellIgnite[c] = Never;
            Vector3 p = CentreOf(c);
            bool pastFence = p.z > VoxelWorld.NZ / 2 * VoxelWorld.Voxel - 0.5f && Mathf.Abs(p.x) < 140f;
            bool onTrack = Mathf.Abs(p.x - VoxelWorld.TrackCentreX(p.z)) < VoxelWorld.TrackHalf + 0.5f;
            fuel[c] = onTrack ? 0f : pastFence ? 1f : 1f;              // inside the fence, grass decides (HasFuel)
        }
        int nt = Trees.Count;
        treeIgnite = new float[nt]; treeFallAt = new float[nt]; treeFallAngle = new float[nt];
        litFrom = new int[nt]; litFromAt = new float[nt];
        for (int t = 0; t < nt; t++) { litFrom[t] = -1; litFromAt[t] = Never; }
        for (int t = 0; t < nt; t++)
        {
            treeIgnite[t] = Never; treeFallAt[t] = Never;
            int c = CellOf(Trees[t].at.x, Trees[t].at.z);
            if (c >= 0) treesIn[c].Add(t);
        }
        // crown reach: trees within 7 m of each other
        treeNear = new List<int>[nt];
        var grid = new Dictionary<long, List<int>>();
        for (int t = 0; t < nt; t++)
        {
            long k = Key(Trees[t].at);
            if (!grid.TryGetValue(k, out var l)) grid[k] = l = new List<int>();
            l.Add(t);
        }
        for (int t = 0; t < nt; t++)
        {
            treeNear[t] = new List<int>();
            Vector3 a = Trees[t].at;
            int gx = Mathf.FloorToInt(a.x / 7f), gz = Mathf.FloorToInt(a.z / 7f);
            for (int dz = -1; dz <= 1; dz++) for (int dx = -1; dx <= 1; dx++)
                if (grid.TryGetValue(((long)(gx + dx) << 32) ^ (uint)(gz + dz), out var l))
                    foreach (int o in l) if (o != t && (Trees[o].at - a).sqrMagnitude < 49f) treeNear[t].Add(o);
        }
        // the textures the shader reads: when each tree and each square caught (Never = not yet)
        int th = Mathf.Max(1, (nt + 255) / 256);
        treeTex = new Texture2D(256, th, TextureFormat.RGBAFloat, false, true) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
        var tp = new Color[256 * th]; for (int i = 0; i < tp.Length; i++) tp[i] = new Color(Never, i < nt ? Trees[i].at.y : 0f, Never, 0f);   // caught, foot height, falls, which way
        treeTex.SetPixels(tp); treeTex.Apply(false);
        var baseTex = new Texture2D(256, th, TextureFormat.RGFloat, false, true) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
        var bp = new Color[256 * th]; for (int i = 0; i < bp.Length; i++) bp[i] = i < nt ? new Color(Trees[i].at.x, Trees[i].at.z, 0, 0) : Color.clear;
        baseTex.SetPixels(bp); baseTex.Apply(false);
        Shader.SetGlobalTexture("_TreeBase", baseTex);
        groundTex = new Texture2D(W, H, TextureFormat.RFloat, false, true) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
        var gp = new Color[W * H]; for (int i = 0; i < gp.Length; i++) gp[i] = new Color(Never, 0, 0, 0);
        groundTex.SetPixels(gp); groundTex.Apply(false);
        Shader.SetGlobalTexture("_TreeFire", treeTex);
        Shader.SetGlobalVector("_TreeFireSize", new Vector4(256f, th, 1f / 256f, 1f / th));
        Shader.SetGlobalTexture("_GroundFire", groundTex);
        Shader.SetGlobalVector("_GroundFireRect", new Vector4(X0, Z0, 1f / (W * Cell), 1f / (H * Cell)));
    }

    static long Key(Vector3 a) { return ((long)Mathf.FloorToInt(a.x / 7f) << 32) ^ (uint)Mathf.FloorToInt(a.z / 7f); }

    /// Takes the fuel out of a rectangle of squares (a test's stand-in for a cut firebreak past the fence).
    public void ClearFuel(float x0, float z0, float x1, float z1)
    {
        for (int c = 0; c < W * H; c++)
        {
            Vector3 p = CentreOf(c);
            if (p.x >= x0 && p.x <= x1 && p.z >= z0 && p.z <= z1) fuel[c] = 0f;
        }
    }

    /// Lights a line of fire from a to b now.
    public void Ignite(Vector3 a, Vector3 b)
    {
        int steps = Mathf.CeilToInt(Vector3.Distance(a, b) / Cell) + 1;
        for (int k = 0; k <= steps; k++)
        {
            Vector3 p = Vector3.Lerp(a, b, k / (float)steps);
            int c = CellOf(p.x, p.z);
            if (c >= 0) Push(Now + (float)rng.NextDouble() * 2f, c);
        }
    }

    public void Begin()
    {
        Running = true; Now = 0f; Shader.SetGlobalFloat("_FireTime", 0f);
        if (GetComponent<FireFX>() == null) gameObject.AddComponent<FireFX>();        // flames, smoke, embers, the red sky
    }

    // for FireFX: what's alight now
    public readonly List<int> ActiveTrees = new List<int>();
    public List<int> BurningCells { get { return burning; } }
    public float TreeIgnite(int t) { return treeIgnite[t]; }
    public float CellIgnite(int c) { return cellIgnite[c]; }
    public Vector3 CellCentre(int c) { return CentreOf(c); }
    public void Stop() { Running = false; Shader.SetGlobalFloat("_FireTime", -1e6f); }

    void Update()
    {
        if (!Running) return;
        Now += Time.deltaTime * speedUp;
        Shader.SetGlobalFloat("_FireTime", Now);
        Vector2 wind = WindAt(Now);
        float ws = wind.magnitude;

        // embers from a strong wind: spot fires well ahead of the front
        for (int k = burning.Count - 1; k >= 0; k--) if (Now - cellIgnite[burning[k]] > 20f) burning.RemoveAt(k);
        emberClock += Time.deltaTime * speedUp;
        while (emberClock >= 0.5f)
        {
            emberClock -= 0.5f;
            float rate = Mathf.Clamp01((ws - 7f) / 5f) * 0.05f;
            if (rate <= 0f) continue;
            for (int k = burning.Count - 1; k >= 0; k--)
            {
                int c = burning[k];
                if (rng.NextDouble() > rate) continue;
                Vector2 dir = Rotate(wind / ws, ((float)rng.NextDouble() - 0.5f) * 0.5f);
                float d = Mathf.Lerp(8f, 26f, (float)rng.NextDouble()) * ws / 10f;
                Vector3 p = CentreOf(c);
                int land = CellOf(p.x + dir.x * d, p.z + dir.y * d);
                if (land >= 0) Push(Now + 1.5f, land);
            }
        }

        // everything due by now
        while (heapT.Count > 0 && heapT[0] <= Now)
        {
            float t = heapT[0]; int i = heapI[0]; Pop();
            if (i >= LandFlag) Land(i - LandFlag);
            else if (i >= TreeFlag) LightTree(i - TreeFlag, t);
            else LightCell(i, t);
        }
        if (newCells.Count > 0)
        {
            foreach (int c in newCells) groundTex.SetPixel(c % W, c / W, new Color(cellIgnite[c], 0, 0, 0));
            groundTex.Apply(false); newCells.Clear();
        }
        if (newTrees.Count > 0)
        {
            foreach (int t in newTrees) treeTex.SetPixel(t % 256, t / 256, new Color(treeIgnite[t], Trees[t].at.y, treeFallAt[t], treeFallAngle[t]));
            treeTex.Apply(false); newTrees.Clear();
        }
    }

    static Vector2 Rotate(Vector2 v, float a) { float c = Mathf.Cos(a), s = Mathf.Sin(a); return new Vector2(v.x * c - v.y * s, v.x * s + v.y * c); }

    void LightCell(int c, float t)
    {
        if (cellIgnite[c] < Never || !HasFuel(c)) return;
        cellIgnite[c] = t;
        newCells.Add(c); burning.Add(c); CellsBurnt++;
        foreach (int tr in treesIn[c]) Push(t + (float)rng.NextDouble() * 1.5f, tr + TreeFlag);
        Vector2 wind = WindAt(t);
        float ws = wind.magnitude;
        Vector3 p = CentreOf(c);
        float hHere = SiteProps.HillY(p.x, p.z);
        int ci = c % W, cj = c / W;
        for (int dj = -1; dj <= 1; dj++)
            for (int di = -1; di <= 1; di++)
            {
                if (di == 0 && dj == 0) continue;
                int ni = ci + di, nj = cj + dj;
                if (ni < 0 || nj < 0 || ni >= W || nj >= H) continue;
                int nc = ni + W * nj;
                if (cellIgnite[nc] < Never) continue;
                Vector2 dir = new Vector2(di, dj).normalized;
                float dist = Cell * (di != 0 && dj != 0 ? 1.414f : 1f);
                float along = ws > 0.01f ? Vector2.Dot(dir, wind / ws) * Mathf.Min(1f, ws / 8f) : 0f;
                float speed = 0.45f * (along >= 0f ? 1f + 3f * along : 1f + 0.6f * along);   // metres a second
                Vector3 q = CentreOf(nc);
                float slope = (SiteProps.HillY(q.x, q.z) - hHere) / dist;
                speed *= Mathf.Clamp(1f + slope * 1.5f, 0.5f, 2.5f);                       // faster uphill
                Push(t + dist / speed * (0.8f + 0.4f * (float)rng.NextDouble()), nc);
            }
    }

    void LightTree(int tr, float t)
    {
        if (treeIgnite[tr] < Never) return;                         // already alight
        treeIgnite[tr] = t;
        if (litFromAt[tr] > t + 0.01f) litFrom[tr] = -1;
        newTrees.Add(tr); TreesBurnt++; ActiveTrees.Add(tr);
        Vector2 wind = WindAt(t);
        float ws = wind.magnitude;
        // does it burn through and fall?  Thin trees and a strong wind make it likelier
        if (treeFallAt[tr] >= Never)
        {
            float chance = 0.08f + 0.17f * Mathf.Clamp01((ws - 4f) / 8f) + (Trees[tr].height < 17f ? 0.06f : 0f);   // about 1 in 5 (the owner: fewer)
            if (rng.NextDouble() < chance)
            {
                float down = ws > 0.5f ? Mathf.Atan2(wind.x, wind.y) : (float)rng.NextDouble() * 6.283f;
                FellTree(tr, t + 14f + (float)rng.NextDouble() * 26f, down + ((float)rng.NextDouble() - 0.5f) * 1.4f);
            }
        }
        // crowning: in a strong wind a burning crown lights the crowns downwind of it
        if (ws < 7f) return;
        Vector3 a = Trees[tr].at;
        foreach (int o in treeNear[tr])
        {
            if (treeIgnite[o] < Never) continue;
            Vector3 d = Trees[o].at - a;
            float dist = new Vector2(d.x, d.z).magnitude;
            float along = Vector2.Dot(new Vector2(d.x, d.z) / Mathf.Max(dist, 0.01f), wind / ws);
            if (along < 0.25f) continue;
            float arrive = t + dist / (0.8f + 2.5f * along) * (0.8f + 0.4f * (float)rng.NextDouble());
            if (arrive < litFromAt[o]) { litFromAt[o] = arrive; litFrom[o] = tr; }
            Push(arrive, o + TreeFlag);
        }
    }

    /// Makes a tree fall, starting at `at` seconds, towards `angle` (radians: 0 = +z, pi/2 = +x).  If it isn't
    /// alight by then it catches just before.  (The prologue uses this for the trees that come down around the dozer.)
    public void FellTree(int tr, float at, float angle, bool solid = true)
    {
        if (tr < 0 || tr >= Trees.Count || treeFallAt[tr] < Never) return;
        treeFallAt[tr] = at; treeFallAngle[tr] = angle;
        if (!solid) notSolid.Add(tr);
        if (treeIgnite[tr] >= Never) Push(Mathf.Max(Now, at - 6f), tr + TreeFlag);
        else newTrees.Add(tr);                                       // (already alight: rewrite its pixel with the fall)
        Push(at + FallTook, tr + LandFlag);
    }

    /// The tree nearest a point (for the prologue to pick one by where it stands).  -1 if none within `within` m.
    public static int TreeNear(Vector3 p, float within)
    {
        int best = -1; float bd = within * within;
        for (int t = 0; t < Trees.Count; t++) { float d = (new Vector2(Trees[t].at.x - p.x, Trees[t].at.z - p.z)).sqrMagnitude; if (d < bd) { bd = d; best = t; } }
        return best;
    }

    readonly HashSet<int> notSolid = new HashSet<int>();         // a log the prologue's dozer shoves aside

    /// Turns a tree that is lying down (swung round about its foot, as when the blade shoves it).
    public void SetFallAngle(int t, float angle)
    {
        treeFallAngle[t] = angle;
        treeTex.SetPixel(t % 256, t / 256, new Color(treeIgnite[t], Trees[t].at.y, treeFallAt[t], angle));
        treeTex.Apply(false);
    }

    /// Long after: the fire out, everything it burnt left burnt (black trunks, fallen logs), no glow, no smoke.
    public void Settle()
    {
        Running = false;
        Shader.SetGlobalFloat("_FireTime", Now + 10000f);
    }

    public bool HasFallen(int t) { return t >= 0 && t < Trees.Count && Now >= treeFallAt[t] + FallTook; }
    public float FallAngle(int t) { return treeFallAngle[t]; }

    void Land(int tr)
    {
        TreesFallen++;
        Landed.Add(tr);
        var tree = Trees[tr];
        Vector3 dir = new Vector3(Mathf.Sin(treeFallAngle[tr]), 0f, Mathf.Cos(treeFallAngle[tr]));
        if (!notSolid.Contains(tr)) SiteProps.AddFallen(tree.at + dir * 1.2f, tree.at + dir * tree.height * 0.85f, 0.45f);   // the trunk on the ground is solid
    }

    public bool CellBurnt(Vector3 p) { int c = CellOf(p.x, p.z); return c >= 0 && cellIgnite[c] < Never; }

    // ---- the heap
    void Push(float t, int i)
    {
        heapT.Add(t); heapI.Add(i);
        int k = heapT.Count - 1;
        while (k > 0) { int p = (k - 1) / 2; if (heapT[p] <= heapT[k]) break; Swap(k, p); k = p; }
    }
    void Pop()
    {
        int last = heapT.Count - 1;
        Swap(0, last); heapT.RemoveAt(last); heapI.RemoveAt(last);
        int k = 0;
        while (true)
        {
            int l = 2 * k + 1, r = l + 1, m = k;
            if (l < heapT.Count && heapT[l] < heapT[m]) m = l;
            if (r < heapT.Count && heapT[r] < heapT[m]) m = r;
            if (m == k) break;
            Swap(k, m); k = m;
        }
    }
    void Swap(int a, int b) { float t = heapT[a]; heapT[a] = heapT[b]; heapT[b] = t; int i = heapI[a]; heapI[a] = heapI[b]; heapI[b] = i; }
}
