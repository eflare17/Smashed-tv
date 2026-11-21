// The dozer pushes trees over, and their wood is picked up (the owner asked for it: clear trees with the blade, and
// collect the wood for braces in the tunnel later).
//   - Drive into a standing tree (one whose trunk stops machines) going forward: the dozer strains against it and the
//     tree leans away, then after a moment (longer for a big gum) it goes over, away from the dozer, with a crash.
//   - When it hits the ground it breaks up into chunks of wood lying along where it fell, and the tree is gone.
//   - Drive the dozer over the chunks and they are picked up: each one is a piece of wood (Wood).
//   - Only the dozer does this (not the Dingo, not on foot).  The save keeps which trees are down, the wood, and the
//     chunks still lying about (SaveGame).
// The falling and the hiding are done in the ground shader (VoxelTerrain: _TreeFell), as the bushfire's trees are,
// because many trees share one mesh.
using System.Collections.Generic;
using System.IO;
using UnityEngine;

public class TreeFelling : MonoBehaviour
{
    public static TreeFelling Instance { get; private set; }

    public const float FallTook = 2.6f;        // s, from tipping to hitting the ground (the shader's own number too)
    public const float PickReach = 2.6f;       // m from the dozer's middle (or its blade) that a chunk is picked up

    /// Pieces of wood collected.
    public int Wood { get; set; }
    /// Trees pushed over (FireSim.Trees ids).
    public readonly List<int> Felled = new List<int>();
    public int ChunkCount { get { return chunks.Count; } }
    public int ChunksMade { get; private set; }          // chunks made by trees landing this session (tests)
    public int Pushing { get; private set; } = -1;      // the tree being pushed this moment (-1: none)
    public float PushShare { get; private set; }         // how far through the push, 0..1

    struct Chunk { public Vector3 at; public Quaternion rot; public float size, born, picked; public GameObject go; public Vector3 from; }
    readonly List<Chunk> chunks = new List<Chunk>();

    Texture2D tex;
    float clock;                                         // the shader's _FellClock
    float pushTime, lastPush = -1f, leanWay;
    readonly List<(int tree, float at, float way)> landing = new List<(int, float, float)>();
    Mesh[] chunkMesh = new Mesh[2];

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; Shader.SetGlobalFloat("_FellOn", 0f); }

    void Start()
    {
        EnsureTex();
        foreach (int t in Felled) Hide(t);              // (loaded before Start)
    }

    void EnsureTex()
    {
        if (tex != null) return;
        int nt = Mathf.Max(1, FireSim.Trees.Count), th = (nt + 255) / 256;
        tex = new Texture2D(256, th, TextureFormat.RGBAFloat, false, true) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
        var px = new Color[256 * th];
        for (int i = 0; i < px.Length; i++) px[i] = new Color(1e9f, 0f, 0f, 0f);
        tex.SetPixels(px); tex.Apply(false);
        Shader.SetGlobalTexture("_TreeFell", tex);
        Shader.SetGlobalFloat("_FellClock", clock);
        Shader.SetGlobalFloat("_FellOn", 1f);
    }

    void SetPixel(int t, Color c) { EnsureTex(); if (t < 0 || t >= tex.width * tex.height) return; tex.SetPixel(t % 256, t / 256, c); tex.Apply(false); }

    static float Height(int t) { return t >= 0 && t < FireSim.Trees.Count ? FireSim.Trees[t].height : 8f; }

    /// Seconds of pushing it takes to put this tree over: a small gum about a second, a tall one about three.
    public static float PushNeeded(int t) { return Mathf.Lerp(1.0f, 3.0f, Mathf.InverseLerp(7f, 22f, Height(t))); }

    /// The dozer is driving into tree t (forward is the way it faces).  Called every frame it is held up by the
    /// trunk.  The tree leans further and further away, and goes over once it has been pushed long enough.
    /// Returns true the moment it goes.
    public bool Push(int t, Vector3 forward, float dt)
    {
        if (t < 0 || Felled.Contains(t)) return false;
        if (t != Pushing) { Pushing = t; pushTime = 0f; GameAudio.PlayAt("creak", FireSim.Trees[t].at + Vector3.up * 3f, 0.9f, 0.8f); }
        pushTime += dt; lastPush = Time.time;
        leanWay = Mathf.Atan2(forward.x, forward.z);
        float need = PushNeeded(t);
        PushShare = Mathf.Clamp01(pushTime / need);
        if (pushTime < need)
        {
            SetPixel(t, new Color(1e9f, 0f, 0.03f + 0.17f * PushShare * PushShare, leanWay));
            return false;
        }
        Fell(t, leanWay, 0.2f);
        Pushing = -1; PushShare = 0f;
        return true;
    }

    /// Puts tree t over now, falling towards `way` (radians: 0 = +z, pi/2 = +x).
    public void Fell(int t, float way, float leanFrom = 0f)
    {
        if (t < 0 || Felled.Contains(t)) return;
        Felled.Add(t);
        SiteProps.SetFelled(t);
        SetPixel(t, new Color(clock, way, leanFrom, way));
        landing.Add((t, clock + FallTook, way));
        GameAudio.PlayAt("creak", FireSim.Trees[t].at + Vector3.up * 4f, 1f, 0.65f);
    }

    /// A tree already down when the game is loaded: gone at once (its chunks come from the save).
    void Hide(int t) { SiteProps.SetFelled(t); SetPixel(t, new Color(-1e6f, 0f, 0f, 0f)); }

    void Update()
    {
        clock += Time.deltaTime;
        Shader.SetGlobalFloat("_FellClock", clock);
        // let go of a tree: it straightens up again
        if (Pushing >= 0 && Time.time - lastPush > 0.25f)
        {
            if (!Felled.Contains(Pushing)) SetPixel(Pushing, new Color(1e9f, 0f, 0f, 0f));
            Pushing = -1; PushShare = 0f;
        }
        for (int i = landing.Count - 1; i >= 0; i--)
            if (clock >= landing[i].at) { Land(landing[i].tree, landing[i].way); landing.RemoveAt(i); }
        UpdateChunks();
    }

    /// It has hit the ground: a thump, dust, and the trunk and branches broken into chunks along where it lay.
    void Land(int t, float way)
    {
        var w = VoxelWorld.Instance;
        var tree = FireSim.Trees[t];
        Vector3 dir = new Vector3(Mathf.Sin(way), 0f, Mathf.Cos(way));
        Vector3 side = new Vector3(dir.z, 0f, -dir.x);
        var rng = new System.Random(t * 7919 + 13);
        float h = tree.height;
        int n = Mathf.Clamp(Mathf.RoundToInt(h * 0.6f), 4, 14);
        for (int k = 0; k < n; k++)
        {
            float along = Mathf.Lerp(1.0f, h * 0.8f, (k + 0.5f) / n) + ((float)rng.NextDouble() - 0.5f) * 0.8f;
            float off = ((float)rng.NextDouble() - 0.5f) * (0.6f + along * 0.12f);
            Vector3 p = tree.at + dir * along + side * off;
            p.y = w != null ? w.HeightAt(p.x, p.z) : p.y;
            float size = Mathf.Lerp(1.3f, 0.8f, along / h) * (0.8f + 0.4f * (float)rng.NextDouble());
            ChunksMade++;
            AddChunk(p, Quaternion.Euler(0f, way * Mathf.Rad2Deg + (float)rng.NextDouble() * 70f - 35f, 0f), size, Time.time + k * 0.03f);
        }
        Vector3 mid = tree.at + dir * h * 0.45f;
        if (w != null) mid.y = w.HeightAt(mid.x, mid.z);
        GameAudio.PlayAt("tip_rumble", mid, 1f, 0.75f);
        GameAudio.PlayAt("clunk", mid, 1f, 0.6f, 0.05f);
        for (int k = 0; k < 6; k++)
        {
            Vector3 q = tree.at + dir * h * (0.15f + 0.14f * k);
            if (w != null) q.y = w.HeightAt(q.x, q.z) + 0.3f;
            HeavyFX.Dust(q, 5, 1.2f, new Color(0.62f, 0.55f, 0.42f, 0.55f));
        }
    }

    void AddChunk(Vector3 at, Quaternion rot, float size, float born)
    {
        var go = new GameObject("Wood");
        go.transform.SetParent(transform, false);
        go.AddComponent<MeshFilter>().sharedMesh = ChunkMesh(chunks.Count % 3 == 0 ? 1 : 0);
        var r = go.AddComponent<MeshRenderer>();
        if (VoxelWorld.Instance != null) r.sharedMaterial = VoxelWorld.Instance.material;
        go.transform.localScale = Vector3.one * size;
        chunks.Add(new Chunk { at = at, rot = rot, size = size, born = born, picked = -1f, go = go });
        Place(chunks.Count - 1);
    }

    void Place(int i)
    {
        var c = chunks[i];
        float since = Time.time - c.born;
        Vector3 p = c.at;
        if (c.picked >= 0f)
        {
            // flying up into the dozer
            float u = Mathf.Clamp01((Time.time - c.picked) / 0.35f);
            var d = FindFirstObjectByType<DozerController>();
            Vector3 to = d != null ? d.transform.position + Vector3.up * 2.2f : c.from;
            p = Vector3.Lerp(c.from, to, u) + Vector3.up * Mathf.Sin(u * Mathf.PI) * 1.2f;
            c.go.transform.localScale = Vector3.one * c.size * (1f - 0.7f * u);
        }
        else if (since < 0.5f)
        {
            float u = Mathf.Clamp01(since / 0.5f);                       // dropped from the falling trunk, with a small bounce
            p.y += (1f - u) * (1f - u) * 1.4f + Mathf.Abs(Mathf.Sin(u * Mathf.PI * 2f)) * 0.15f * (1f - u);
        }
        c.go.transform.SetPositionAndRotation(p + Vector3.up * c.size * 0.16f, c.rot);
        chunks[i] = c;
    }

    void UpdateChunks()
    {
        var d = FindFirstObjectByType<DozerController>();
        var wk = Worker.Instance;
        bool driving = d != null && wk != null && wk.InDozer;
        Vector3 dp = d != null ? d.transform.position : Vector3.zero, fwd = d != null ? d.transform.forward : Vector3.forward;
        Vector2 mid = new Vector2(dp.x, dp.z), blade = mid + new Vector2(fwd.x, fwd.z) * 3f;
        for (int i = chunks.Count - 1; i >= 0; i--)
        {
            var c = chunks[i];
            if (c.picked >= 0f)
            {
                if (Time.time - c.picked >= 0.35f)
                {
                    Destroy(c.go); chunks.RemoveAt(i); Wood++;
                    GameAudio.Play("pick_rock", 0.5f, 0.7f + 0.1f * (Wood % 3));
                    continue;
                }
            }
            else if (driving && Time.time - c.born > 0.6f)
            {
                Vector2 a = new Vector2(c.at.x, c.at.z);
                if ((a - mid).sqrMagnitude < PickReach * PickReach || (a - blade).sqrMagnitude < PickReach * PickReach)
                { c.picked = Time.time; c.from = c.go.transform.position; chunks[i] = c; }
            }
            Place(i);
        }
    }

    Mesh ChunkMesh(int kind)
    {
        if (chunkMesh[kind] != null) return chunkMesh[kind];
        // a short log: a long box of gum bark (15), or split timber (11); plain colour (alpha 255: not part of any tree)
        byte mat = kind == 0 ? (byte)11 : (byte)15;
        var v = new List<Vector3>(); var nrm = new List<Vector3>(); var col = new List<Color32>(); var tri = new List<int>();
        Vector3 half = new Vector3(0.3f, 0.22f, 0.8f);
        Vector3[] n = { Vector3.right, Vector3.left, Vector3.up, Vector3.down, Vector3.forward, Vector3.back };
        foreach (var f in n)
        {
            Vector3 u = Mathf.Abs(f.y) > 0.5f ? Vector3.right : Vector3.up, s = Vector3.Cross(f, u);
            int b = v.Count;
            for (int k = 0; k < 4; k++)
            {
                Vector3 c = f + ((k & 1) == 0 ? -u : u) + ((k & 2) == 0 ? -s : s);
                v.Add(Vector3.Scale(c, half)); nrm.Add(f); col.Add(new Color32(mat, 0, 0, 255));
            }
            tri.AddRange(new[] { b, b + 1, b + 3, b, b + 3, b + 2 });
        }
        var mesh = new Mesh();
        mesh.SetVertices(v); mesh.SetNormals(nrm); mesh.SetColors(col); mesh.SetTriangles(tri, 0);
        // make every face point outwards whichever way round the corners came out
        var t = mesh.triangles; var vv = mesh.vertices;
        for (int i = 0; i < t.Length; i += 3)
        {
            Vector3 fn = Vector3.Cross(vv[t[i + 1]] - vv[t[i]], vv[t[i + 2]] - vv[t[i]]);
            if (Vector3.Dot(fn, nrm[t[i]]) < 0f) { int x = t[i + 1]; t[i + 1] = t[i + 2]; t[i + 2] = x; }
        }
        mesh.triangles = t;
        mesh.RecalculateBounds();
        chunkMesh[kind] = mesh;
        return mesh;
    }

    // ---- the save
    public void WriteState(BinaryWriter w)
    {
        w.Write(Wood);
        w.Write(Felled.Count);
        foreach (int t in Felled) w.Write(t);
        int lying = 0; foreach (var c in chunks) if (c.picked < 0f) lying++;
        w.Write(lying);
        foreach (var c in chunks)
        {
            if (c.picked >= 0f) continue;
            w.Write(c.at.x); w.Write(c.at.y); w.Write(c.at.z); w.Write(c.rot.eulerAngles.y); w.Write(c.size);
        }
    }

    public void ReadState(BinaryReader r)
    {
        foreach (var c in chunks) if (c.go != null) Destroy(c.go);
        chunks.Clear(); Felled.Clear(); landing.Clear();
        Wood = r.ReadInt32();
        int nf = r.ReadInt32();
        for (int i = 0; i < nf; i++) { int t = r.ReadInt32(); if (t >= 0 && t < FireSim.Trees.Count && !Felled.Contains(t)) { Felled.Add(t); Hide(t); } }
        int nc = r.ReadInt32();
        for (int i = 0; i < nc; i++)
        {
            Vector3 p = new Vector3(r.ReadSingle(), r.ReadSingle(), r.ReadSingle());
            float yaw = r.ReadSingle(), size = r.ReadSingle();
            AddChunk(p, Quaternion.Euler(0f, yaw, 0f), size, -100f);
        }
    }

    /// A save from before trees could be pushed over: every tree standing, no wood.
    public void FromOldSave()
    {
        foreach (var c in chunks) if (c.go != null) Destroy(c.go);
        chunks.Clear(); Wood = 0;
    }
}
