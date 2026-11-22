// The grunts: the first enemy, taken from the Voxel Arena (branch claude/voxel-arena-f7bada: Grunts.cs, Gibs.cs,
// VoxModel.cs).  The same 1.5 m grunt built of 6.25 cm blocks, the same two walk frames, and the same burst into
// 6.25 cm cubes when it dies.
//   - They come out of the deep tunnel: one at a time, now and then (the first after about 1.5 minutes, then every
//     35 seconds or so), never more than 3 about.  They only come once there's a way: while you're in the mine, from
//     deeper in than you (as far as the tunnel is open); while you're outside, only once the whole tunnel is dug
//     through, from its far end.
//   - They walk at you (on the ground, as you do: no climbing walls, they need head room).
//   - The rifle kills one with a shot (each grunt is IShootable, Rifle.cs).  A gas blast (Fluids.cs) kills every
//     grunt it reaches.  A machine you're driving squashes one that walks into it.
//   - If one reaches you it knocks you back and you drop 5 coins (or nothing, if you have none).  You never die.
//   - Off in Esc > Settings > Enemies: they all go at once and no more come.
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class Grunts : MonoBehaviour
{
    public static Grunts Instance { get; private set; }
    public static bool On = true;                            // Esc > Settings > Enemies (kept in PlayerPrefs "set.enemies")

    public const int MaxAlive = 3;
    public const float FirstAfter = 90f, Every = 35f, EveryJitter = 10f;
    public const float Speed = 1.5f;                         // metres a second (you walk 2.6)
    public const float Radius = 0.44f, Height = 24 * VoxelWorld.Voxel;
    public const float Reach = 0.75f;                        // this close and it has you
    public const int CoinsLost = 5;
    public const float DeepEnd = 30.5f;                      // where they come from: this far along the tunnel

    public static int Spawned { get; private set; }          // (tests)
    public static int Killed { get; private set; }
    public static int Touches { get; private set; }
    public int Alive { get { return list.Count; } }

    public class Grunt : MonoBehaviour, IShootable
    {
        public Grunts owner;
        public Vector3 pos;
        public Vector2 facing = Vector2.up, veer;
        public float phase, rest;
        public Transform frameA, frameB;
        public void Shot(Vector3 at, Vector3 dir) { owner.Kill(this, at - dir); }
    }

    readonly List<Grunt> list = new List<Grunt>();
    Mesh meshA, meshB;
    Material mat;
    float timer;
    DozerController dozerCache;

    void Awake()
    {
        Instance = this;
        On = PlayerPrefs.GetInt("set.enemies", 1) == 1;
        timer = FirstAfter;
    }
    void Start() { Fluids.Exploded += OnBlast; }
    void OnDestroy() { if (Instance == this) Instance = null; Fluids.Exploded -= OnBlast; }

    public static void SetOn(bool on)
    {
        On = on;
        PlayerPrefs.SetInt("set.enemies", on ? 1 : 0);
        PlayerPrefs.Save();
        if (!on && Instance != null) Instance.RemoveAll();
    }

    /// Every grunt gone at once, no bits (switched off, or a load).
    public void RemoveAll()
    {
        foreach (var g in list) if (g != null) Destroy(g.gameObject);
        list.Clear();
        timer = Every;
    }

    void Meshes()
    {
        if (meshA != null) return;
        meshA = GruntModel.FromBoxes(GruntModel.GruntBoxesFine(0), new Vector3(7.5f, 0f, 4f), VoxelWorld.Voxel);
        meshB = GruntModel.FromBoxes(GruntModel.GruntBoxesFine(1), new Vector3(7.5f, 0f, 4f), VoxelWorld.Voxel);
        var sh = Shader.Find("Voxel/VertexColour");
        mat = new Material(sh != null ? sh : Shader.Find("Standard"));
    }

    Transform Frame(Transform parent, Mesh m, string name)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent, false);
        go.AddComponent<MeshFilter>().sharedMesh = m;
        var r = go.AddComponent<MeshRenderer>();
        r.sharedMaterial = mat;
        return go.transform;
    }

    /// A grunt standing at `p` (on the ground there).
    public Grunt SpawnAt(Vector3 p)
    {
        Meshes();
        var w = VoxelWorld.Instance;
        var go = new GameObject("Grunt");
        go.transform.SetParent(transform, false);
        var g = go.AddComponent<Grunt>();
        g.owner = this;
        p.y = w != null ? w.FloorAt(p + Vector3.up * 0.45f) : p.y;
        g.pos = p;
        g.phase = Random.value * Mathf.PI * 2f;
        float a = Random.Range(-0.4f, 0.4f);
        g.veer = new Vector2(Mathf.Cos(a), Mathf.Sin(a));
        g.frameA = Frame(go.transform, meshA, "Walk A");
        g.frameB = Frame(go.transform, meshB, "Walk B");
        var col = go.AddComponent<CapsuleCollider>();
        col.isTrigger = true;                                // (the rifle's ray finds it; nothing bumps into it)
        col.radius = Radius; col.height = Height; col.center = new Vector3(0f, Height * 0.5f, 0f);
        go.transform.position = p;
        list.Add(g);
        Spawned++;
        return g;
    }

    public void Kill(Grunt g, Vector3 from)
    {
        if (g == null || !list.Contains(g)) return;
        list.Remove(g);
        Killed++;
        Vector3 away = g.pos - from; away.y = 0f;
        if (away.sqrMagnitude < 1e-4f) away = Vector3.forward;
        GruntGibs.Burst(g.pos + Vector3.up * Height * 0.55f, away.normalized, GruntModel.GruntGibsFine, 40, VoxelWorld.Voxel);
        HeavyFX.Dust(g.pos + Vector3.up * 0.9f, 2, 0.35f, new Color(0.55f, 0.06f, 0.05f, 0.55f));
        GameAudio.PlayAt("grunt_die", g.pos, 0.7f, 0.9f + 0.25f * Random.value);
        Destroy(g.gameObject);
    }

    void OnBlast(Vector3 at, float r)
    {
        for (int i = list.Count - 1; i >= 0; i--)
        {
            var g = list[i];
            if (Vector3.Distance(g.pos + Vector3.up * 0.8f, at) < r) Kill(g, at);
        }
    }

    /// The furthest along the tunnel (from `from`, going deeper) a grunt could walk: the floor never steps up more than
    /// half a metre and there's head room all the way.
    public static float OpenTo(float from)
    {
        var w = VoxelWorld.Instance;
        float x = VoxelWorld.PortalX;
        float y = w.FloorAt(new Vector3(x, 0.45f, VoxelWorld.PortalZ + from));
        float along = from;
        for (float a = from + 0.25f; a <= DeepEnd; a += 0.25f)
        {
            float z = VoxelWorld.PortalZ + a;
            float f = w.FloorAt(new Vector3(x, y + 0.45f, z));
            if (f - y > 0.5f) break;
            if (w.MaterialAt(new Vector3(x, Mathf.Max(f, y) + 1.4f, z)) != VoxelWorld.Air) break;
            y = f; along = a;
        }
        return along;
    }

    public void TrySpawn(Vector3 player)
    {
        var w = VoxelWorld.Instance;
        float playerAlong = player.z - VoxelWorld.PortalZ;
        bool inMine = GameAudio.InMine(player);
        float from = inMine ? Mathf.Max(0.5f, playerAlong) : 0.5f;
        float open = OpenTo(from);
        float at;
        if (inMine) { if (open - playerAlong < 6f) return; at = open; }
        else { if (open < DeepEnd - 0.3f) return; at = DeepEnd; }
        SpawnAt(new Vector3(VoxelWorld.PortalX + Random.Range(-0.5f, 0.5f), 0f, VoxelWorld.PortalZ + at));
    }

    void Update()
    {
        var wk = Worker.Instance; var w = VoxelWorld.Instance;
        if (wk == null || w == null) return;
        if (!On) { if (list.Count > 0) RemoveAll(); return; }
        float dt = Time.deltaTime;
        if (dt <= 0f) return;
        bool busy = Prologue.Playing || TrailerMode.On || Ending.Playing;
        Vector3 player = wk.transform.position;
        if (wk.InDozer && dozerCache == null) dozerCache = FindFirstObjectByType<DozerController>();
        DozerController dozer = wk.InDozer ? dozerCache : null;
        bool onMachine = dozer != null || Dingo.Working || wk.RidingCart;   // (riding the motor cart: it runs them down)
        if (Ending.Playing) return;                              // (they stand still while the ending plays)
        if (dozer != null) player = dozer.transform.position;
        else if (Dingo.Working) player = Dingo.Instance.transform.position;

        if (!busy)
        {
            timer -= dt;
            if (timer <= 0f)
            {
                timer = Every + Random.Range(-EveryJitter, EveryJitter);
                if (list.Count < MaxAlive) TrySpawn(player);
            }
        }
        for (int i = list.Count - 1; i >= 0; i--) Step(list[i], player, onMachine, dt);
    }

    void Step(Grunt g, Vector3 target, bool onMachine, float dt)
    {
        var w = VoxelWorld.Instance;
        Vector2 p = new Vector2(g.pos.x, g.pos.z), tgt = new Vector2(target.x, target.z);
        Vector2 to = tgt - p;
        float dist = to.magnitude;
        if (g.rest > 0f) g.rest -= dt;
        // a machine you're driving squashes it
        if (onMachine && dist < 1.6f && Mathf.Abs(target.y - g.pos.y) < 2f) { Kill(g, target); return; }
        Vector2 dir = dist > 0.01f ? to / dist : g.facing;
        if (dist > 3f) dir = new Vector2(dir.x * g.veer.x - dir.y * g.veer.y, dir.x * g.veer.y + dir.y * g.veer.x);
        float sp = g.rest > 0f ? -0.6f : Speed;                 // backs off a moment after it got you
        // push apart from the others
        Vector2 push = Vector2.zero;
        foreach (var o in list)
        {
            if (o == g) continue;
            Vector2 d = p - new Vector2(o.pos.x, o.pos.z);
            float l = d.magnitude;
            if (l < Radius * 2f && l > 1e-3f) push += d / l * (Radius * 2f - l);
        }
        Vector2 step = dir * (sp * dt) + push * 0.5f;
        float y = g.pos.y;
        if (!Walk(ref p, ref y, step) && !Walk(ref p, ref y, new Vector2(step.x, 0f))) Walk(ref p, ref y, new Vector2(0f, step.y));
        float floor = w.FloorAt(new Vector3(p.x, y + 0.45f, p.y));
        y = floor > y ? Mathf.MoveTowards(y, floor, 3.5f * dt + 0.02f) : Mathf.MoveTowards(y, floor, 7f * dt);
        g.pos = new Vector3(p.x, y, p.y);
        if (dir.sqrMagnitude > 0.001f && g.rest <= 0f) g.facing = dir;
        g.phase += dt * Speed * 2.4f;
        float bob = Mathf.Abs(Mathf.Sin(g.phase)) * 0.08f;
        g.transform.SetPositionAndRotation(g.pos + Vector3.up * bob, Quaternion.LookRotation(new Vector3(g.facing.x, 0f, g.facing.y)));
        bool a = ((int)(g.phase / Mathf.PI) & 1) == 0;
        if (g.frameA.gameObject.activeSelf != a) { g.frameA.gameObject.SetActive(a); g.frameB.gameObject.SetActive(!a); }

        // it has you: a knock back, a few coins dropped, never hurt
        if (!onMachine && g.rest <= 0f && dist < Reach && Mathf.Abs(target.y - g.pos.y) < 1.4f) GotYou(g, dir);
    }

    void GotYou(Grunt g, Vector2 dir)
    {
        var wk = Worker.Instance; var m = Money.Instance;
        Touches++;
        g.rest = 1.6f;
        wk.Knock(new Vector3(dir.x, 0f, dir.y) * 6f);
        long lost = m != null ? System.Math.Min(CoinsLost, m.Coins) : 0;
        if (lost > 0) m.Spend(lost);
        GameAudio.PlayAt("hurt", wk.transform.position, 0.7f);
        wk.Say("A grunt got you!" + (lost > 0 ? "  -" + lost + " coins." : "") + "  The rifle (4) stops them.", 2.5f);
    }

    /// One small step for a grunt, like the worker's: not up more than half a metre, and it needs head room.
    bool Walk(ref Vector2 p, ref float y, Vector2 step)
    {
        if (step.sqrMagnitude < 1e-10f) return false;
        var w = VoxelWorld.Instance;
        Vector2 next = p + step;
        float lim = VoxelWorld.SiteHalf - 1.2f;
        if (Mathf.Abs(next.x) > lim || Mathf.Abs(next.y) > lim) return false;
        Vector2 ahead = next + step.normalized * 0.25f;
        float floor = Mathf.Max(w.FloorAt(new Vector3(next.x, y + 0.45f, next.y)), w.FloorAt(new Vector3(ahead.x, y + 0.45f, ahead.y)));
        if (floor - y > 0.5f) return false;
        if (w.MaterialAt(new Vector3(next.x, Mathf.Max(floor, y) + 1.4f, next.y)) != VoxelWorld.Air) return false;
        p = next;
        return true;
    }
}

/// The grunt's look, from the Voxel Arena's VoxModel.cs (Smashed's grunt redrawn in 6.25 cm blocks): boxes of blocks
/// with a colour each; only faces with no neighbour are kept.  Front is +Z, feet at y = 0.
public static class GruntModel
{
    public struct B { public int x0, y0, z0, x1, y1, z1; public Color c; public B(int a, int b, int cc, int d, int e, int f, Color col) { x0 = a; y0 = b; z0 = cc; x1 = d; y1 = e; z1 = f; c = col; } }

    public static readonly Color Skin = new Color(0.95f, 0.72f, 0.52f);
    public static readonly Color GruntShirt = new Color(0.36f, 0.62f, 0.22f);
    public static readonly Color GruntPants = new Color(0.42f, 0.3f, 0.18f);
    public static readonly Color GruntCap = new Color(0.85f, 0.15f, 0.12f);
    public static readonly Color Boot = new Color(0.12f, 0.1f, 0.1f);
    public static readonly Color Eye = new Color(0.1f, 0.05f, 0.05f);
    public static readonly Color Blood = new Color(0.6f, 0.03f, 0.03f);

    public static readonly Color[] GruntGibsFine =
    {
        GruntShirt, GruntShirt, GruntShirt, new Color(0.36f * 0.78f, 0.62f * 0.78f, 0.22f * 0.78f), Skin, Skin,
        GruntPants, GruntPants, Boot, GruntCap, Blood, Blood, Blood,
    };

    static Color Shade(Color c, float f) { return new Color(Mathf.Clamp01(c.r * f), Mathf.Clamp01(c.g * f), Mathf.Clamp01(c.b * f), c.a); }

    public static B[] GruntBoxesFine(int frame)
    {
        int a = frame == 0 ? 2 : 0, b = 2 - a;
        Color shirtDark = Shade(GruntShirt, 0.78f), shirtLight = Shade(GruntShirt, 1.12f), hand = Shade(Skin, 0.9f);
        Color belt = new Color(0.2f, 0.13f, 0.07f), buckle = new Color(0.78f, 0.66f, 0.3f), mouth = new Color(0.45f, 0.12f, 0.1f);
        Color capDark = Shade(GruntCap, 0.8f), pantsDark = Shade(GruntPants, 0.82f);
        var l = new List<B>
        {
            new B(3, 2, 1 + a, 6, 8, 4 + a, GruntPants), new B(8, 2, 1 + b, 11, 8, 4 + b, GruntPants),
            new B(3, 2, 1 + a, 6, 2, 4 + a, pantsDark), new B(8, 2, 1 + b, 11, 2, 4 + b, pantsDark),
            new B(3, 0, 1 + a, 6, 1, 5 + a, Boot), new B(8, 0, 1 + b, 11, 1, 5 + b, Boot),
            new B(3, 7, 1, 11, 8, 6, GruntPants),
            new B(2, 9, 0, 12, 9, 7, belt), new B(6, 9, 7, 8, 9, 7, buckle),
            new B(2, 10, 0, 12, 16, 7, GruntShirt),
            new B(2, 10, 0, 12, 10, 7, shirtDark), new B(2, 11, 0, 2, 15, 7, shirtDark), new B(12, 11, 0, 12, 15, 7, shirtDark),
            new B(3, 16, 1, 11, 16, 6, shirtLight),
            new B(0, 13, 2, 1, 16, 5, GruntShirt), new B(13, 13, 2, 14, 16, 5, GruntShirt),
            new B(0, 14, 6, 1, 16, 7 + a, Skin), new B(13, 14, 6, 14, 16, 7 + b, Skin),
            new B(0, 13, 8 + a, 1, 16, 9 + a, hand), new B(13, 13, 8 + b, 14, 16, 9 + b, hand),
            new B(4, 17, 0, 10, 21, 7, Skin),
            new B(5, 19, 7, 6, 20, 7, Eye), new B(8, 19, 7, 9, 20, 7, Eye),
            new B(7, 18, 8, 7, 19, 8, hand),
            new B(6, 17, 7, 8, 17, 7, mouth),
            new B(4, 22, 0, 10, 23, 7, GruntCap), new B(5, 23, 1, 9, 23, 6, Shade(GruntCap, 1.08f)),
            new B(4, 22, 8, 10, 22, 9, capDark),
        };
        return l.ToArray();
    }

    static readonly Vector3Int[] Dirs = { new Vector3Int(1, 0, 0), new Vector3Int(-1, 0, 0), new Vector3Int(0, 1, 0), new Vector3Int(0, -1, 0), new Vector3Int(0, 0, 1), new Vector3Int(0, 0, -1) };
    static readonly Vector3[][] Corners =
    {
        new[] { new Vector3(1, 0, 0), new Vector3(1, 1, 0), new Vector3(1, 1, 1), new Vector3(1, 0, 1) },
        new[] { new Vector3(0, 0, 0), new Vector3(0, 0, 1), new Vector3(0, 1, 1), new Vector3(0, 1, 0) },
        new[] { new Vector3(0, 1, 0), new Vector3(0, 1, 1), new Vector3(1, 1, 1), new Vector3(1, 1, 0) },
        new[] { new Vector3(0, 0, 0), new Vector3(1, 0, 0), new Vector3(1, 0, 1), new Vector3(0, 0, 1) },
        new[] { new Vector3(0, 0, 1), new Vector3(1, 0, 1), new Vector3(1, 1, 1), new Vector3(0, 1, 1) },
        new[] { new Vector3(0, 0, 0), new Vector3(0, 1, 0), new Vector3(1, 1, 0), new Vector3(1, 0, 0) },
    };

    /// Boxes -> one mesh of the outside faces.  `centre` (in blocks) lands on the origin; `size` is one block in metres.
    public static Mesh FromBoxes(B[] boxes, Vector3 centre, float size)
    {
        var grid = new Dictionary<Vector3Int, Color>();
        foreach (var bx in boxes)
            for (int x = bx.x0; x <= bx.x1; x++)
                for (int y = bx.y0; y <= bx.y1; y++)
                    for (int z = bx.z0; z <= bx.z1; z++)
                        grid[new Vector3Int(x, y, z)] = bx.c;
        var verts = new List<Vector3>(); var norms = new List<Vector3>(); var cols = new List<Color>(); var tris = new List<int>();
        bool linear = QualitySettings.activeColorSpace == ColorSpace.Linear;
        foreach (var key in new List<Vector3Int>(grid.Keys)) if (linear) grid[key] = grid[key].linear;
        foreach (var kv in grid)
            for (int f = 0; f < 6; f++)
            {
                if (grid.ContainsKey(kv.Key + Dirs[f])) continue;
                int s = verts.Count;
                for (int k = 0; k < 4; k++) { verts.Add(((Vector3)kv.Key + Corners[f][k] - centre) * size); norms.Add(Dirs[f]); cols.Add(kv.Value); }
                Vector3 n = Dirs[f], e1 = Corners[f][1] - Corners[f][0], e2 = Corners[f][2] - Corners[f][0];
                if (Vector3.Dot(Vector3.Cross(e1, e2), n) > 0f) { tris.Add(s); tris.Add(s + 1); tris.Add(s + 2); tris.Add(s); tris.Add(s + 2); tris.Add(s + 3); }
                else { tris.Add(s); tris.Add(s + 2); tris.Add(s + 1); tris.Add(s); tris.Add(s + 3); tris.Add(s + 2); }
            }
        var m = new Mesh();
        m.SetVertices(verts); m.SetNormals(norms); m.SetColors(cols); m.SetTriangles(tris, 0);
        m.RecalculateBounds();
        return m;
    }
}

/// Gib cubes (the Voxel Arena's Gibs.cs): what a grunt bursts into.  Each is thrown out, tumbles, bounces on the
/// ground (FloorAt), lies there a few seconds and sinks away.  Drawn instanced, one batch per colour.  Not dirt.
public class GruntGibs : MonoBehaviour
{
    static GruntGibs instance;
    const int Max = 1500;
    const float Life = 6f;
    readonly Vector3[] pos = new Vector3[Max], vel = new Vector3[Max], spin = new Vector3[Max];
    readonly Quaternion[] rot = new Quaternion[Max];
    readonly float[] age = new float[Max], size = new float[Max];
    readonly int[] colour = new int[Max];
    int count;
    Color[] colours = new Color[0];
    Material[] mats = new Material[0];
    Matrix4x4[][] bufs = new Matrix4x4[0][];
    int[] fill = new int[0];
    Mesh cube;

    public static int Count { get { return instance != null ? instance.count : 0; } }
    public static int Made { get; private set; }

    static GruntGibs Get()
    {
        if (instance == null) instance = new GameObject("Grunt gibs").AddComponent<GruntGibs>();
        return instance;
    }
    void Awake()
    {
        instance = this;
        var c = GameObject.CreatePrimitive(PrimitiveType.Cube);
        cube = c.GetComponent<MeshFilter>().sharedMesh;
        Destroy(c);
    }
    void OnDestroy() { if (instance == this) instance = null; }

    int ColourIndex(Color c)
    {
        for (int i = 0; i < colours.Length; i++) if (colours[i] == c) return i;
        int n = colours.Length;
        System.Array.Resize(ref colours, n + 1); System.Array.Resize(ref mats, n + 1); System.Array.Resize(ref bufs, n + 1); System.Array.Resize(ref fill, n + 1);
        colours[n] = c;
        mats[n] = new Material(Shader.Find("Standard")) { color = c, enableInstancing = true };
        mats[n].SetFloat("_Glossiness", c.r > 0.5f && c.g < 0.1f ? 0.45f : 0.1f);
        bufs[n] = new Matrix4x4[Max];
        return n;
    }

    public static void Burst(Vector3 at, Vector3 dir, Color[] palette, int n, float cubeSize)
    {
        var g = Get();
        for (int k = 0; k < n; k++)
        {
            int i = g.count < Max ? g.count++ : Random.Range(0, Max);
            g.pos[i] = at + Vector3.Scale(Random.insideUnitSphere, new Vector3(0.35f, 0.6f, 0.35f));
            g.vel[i] = dir * Random.Range(2f, 5.5f) + Random.insideUnitSphere * 2.5f + Vector3.up * Random.Range(2.5f, 5f);
            g.spin[i] = Random.insideUnitSphere * 720f;
            g.rot[i] = Random.rotation;
            g.age[i] = 0f;
            g.size[i] = cubeSize;
            g.colour[i] = g.ColourIndex(palette[Random.Range(0, palette.Length)]);
            Made++;
        }
    }

    void Update()
    {
        float dt = Time.deltaTime;
        var world = VoxelWorld.Instance;
        for (int i = 0; i < count; i++)
        {
            age[i] += dt;
            if (age[i] > Life) { count--; pos[i] = pos[count]; vel[i] = vel[count]; spin[i] = spin[count]; rot[i] = rot[count]; age[i] = age[count]; size[i] = size[count]; colour[i] = colour[count]; i--; continue; }
            Vector3 v = vel[i];
            v.y -= 9.81f * dt;
            Vector3 p = pos[i] + v * dt;
            float floor = world != null ? world.FloorAt(p + Vector3.up * 0.3f) : 0f;
            float r = size[i] * 0.5f;
            if (age[i] > Life - 1.2f) floor -= (age[i] - (Life - 1.2f)) * 0.3f;
            if (p.y - r < floor)
            {
                p.y = floor + r;
                if (v.y < -1.5f) { v.y = -v.y * 0.3f; v.x *= 0.6f; v.z *= 0.6f; spin[i] *= 0.5f; }
                else { v.y = 0f; v.x *= Mathf.Exp(-8f * dt); v.z *= Mathf.Exp(-8f * dt); spin[i] *= Mathf.Exp(-6f * dt); }
            }
            pos[i] = p; vel[i] = v;
            rot[i] = Quaternion.Euler(spin[i] * dt) * rot[i];
        }
        for (int c = 0; c < fill.Length; c++) fill[c] = 0;
        for (int i = 0; i < count; i++) { int c = colour[i]; bufs[c][fill[c]++] = Matrix4x4.TRS(pos[i], rot[i], Vector3.one * size[i]); }
        var bounds = new Bounds(Vector3.zero, Vector3.one * 400f);
        for (int c = 0; c < fill.Length; c++)
            if (fill[c] > 0)
                Graphics.RenderMeshInstanced(new RenderParams(mats[c]) { worldBounds = bounds, shadowCastingMode = ShadowCastingMode.On, receiveShadows = true }, cube, 0, bufs[c], fill[c]);
    }
}
