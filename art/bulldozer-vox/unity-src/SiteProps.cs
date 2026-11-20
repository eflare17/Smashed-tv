// The scenery of the quarry: the timber mine entrance and its lantern, the rails running out of it,
// gum trees, crates, log piles, and green hills in the distance.
//
// Everything here is built from plain boxes when the game starts, and drawn with the ground's own
// shader, so each box picks up the same small-block texture as the ground.  None of it can be dug.
// The bigger things are solid to the dozer (see Blocks).
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

public class SiteProps : MonoBehaviour
{
    // material ids understood by the ground shader
    const byte Bracken = 30;
    const byte Timber = 11, DarkTimber = 12, Steel = 13, Leaves = 14, Bark = 15, Rock = 3, Gold = 5, HiVis = 16, Dark = 20, ForestFloor = 25, TrackDirt = 26;

    struct Solid { public Vector2 at; public float radius; public bool machineOnly; public float below; }   // below: only solid to a machine lower than this (metres)
    static readonly List<Solid> solids = new List<Solid>();

    /// The middle of the track, point by point, from deep in the tunnel out to the end of the line.
    public static readonly List<Vector3> RailPath = new List<Vector3>();

    /// True if a machine of the given radius at this spot would be inside something solid.
    /// A person on foot is not stopped by things that only keep machines out (the mine tunnel).
    // trunks lying on the ground (fallen in the fire): solid along their length
    struct Log { public Vector2 a, b; public float radius; }
    static readonly List<Log> fallen = new List<Log>();
    public static void AddFallen(Vector3 a, Vector3 b, float radius) { fallen.Add(new Log { a = new Vector2(a.x, a.z), b = new Vector2(b.x, b.z), radius = radius }); }
    public static int FallenCount { get { return fallen.Count; } }
    public static void ClearFallen() { fallen.Clear(); }

    public static bool Blocks(Vector3 pos, float radius, bool onFoot = false)
    {
        Vector2 p2 = new Vector2(pos.x, pos.z);
        for (int i = 0; i < fallen.Count; i++)
        {
            Vector2 ab = fallen[i].b - fallen[i].a;
            float u = Mathf.Clamp01(Vector2.Dot(p2 - fallen[i].a, ab) / Mathf.Max(ab.sqrMagnitude, 1e-4f));
            float r = fallen[i].radius + radius;
            if ((fallen[i].a + ab * u - p2).sqrMagnitude < r * r) return true;
        }
        for (int i = 0; i < solids.Count; i++)
        {
            if (onFoot && solids[i].machineOnly) continue;
            if (pos.y >= solids[i].below) continue;                          // (the tunnel: a machine up on the hilltop above it is not in it)
            float r = solids[i].radius + radius;
            if ((new Vector2(pos.x, pos.z) - solids[i].at).sqrMagnitude < r * r) return true;
        }
        return false;
    }

    // ---------------------------------------------------------------- box builder
    readonly List<Vector3> verts = new List<Vector3>();
    readonly List<Vector3> normals = new List<Vector3>();
    readonly List<Color32> colours = new List<Color32>();
    readonly List<int> tris = new List<int>();
    static readonly Vector3[] FaceN = { Vector3.right, Vector3.left, Vector3.up, Vector3.down, Vector3.forward, Vector3.back };
    static readonly Vector3[] FaceU = { Vector3.forward, Vector3.back, Vector3.right, Vector3.left, Vector3.left, Vector3.right };

    void Box(Vector3 centre, Vector3 size, byte mat) { Box(centre, size, Quaternion.identity, mat); }

    // the tree being built, if any: its id goes in the blocks' colours (blue, alpha) so the fire can burn it alone
    int curTree = -1;

    void SetCrown(Vector3 top, List<Vector3> clumps)
    {
        if (curTree < 0) return;
        var ft = FireSim.Trees[curTree];
        ft.top = top; ft.clumps = clumps.ToArray();
        FireSim.Trees[curTree] = ft;
    }

    int BeginTree(Vector3 at, float height)
    {
        FireSim.Trees.Add(new FireSim.FireTree { at = at, height = height });
        curTree = FireSim.Trees.Count - 1;
        return curTree;
    }

    void Box(Vector3 centre, Vector3 size, Quaternion rot, byte mat)
    {
        var col = curTree >= 0 ? new Color32(mat, 0, (byte)(curTree & 255), (byte)(curTree >> 8)) : new Color32(mat, 0, 0, 255);
        Vector3 half = size * 0.5f;
        for (int f = 0; f < 6; f++)
        {
            Vector3 n = FaceN[f], u = FaceU[f], v = Vector3.Cross(n, u);
            int start = verts.Count;
            for (int k = 0; k < 4; k++)
            {
                float su = (k == 1 || k == 2) ? 1f : -1f, sv = k >= 2 ? 1f : -1f;
                Vector3 local = Vector3.Scale(n + u * su + v * sv, half);
                verts.Add(centre + rot * local);
                normals.Add(rot * n);
                colours.Add(col);
            }
            tris.Add(start); tris.Add(start + 2); tris.Add(start + 1);
            tris.Add(start); tris.Add(start + 3); tris.Add(start + 2);
        }
    }

    /// A beam from a to b with a square section.
    void Beam(Vector3 a, Vector3 b, float thick, byte mat)
    {
        Vector3 d = b - a;
        if (d.sqrMagnitude < 1e-6f) return;
        Box((a + b) * 0.5f, new Vector3(thick, thick, d.magnitude), Quaternion.LookRotation(d), mat);
    }

    /// Twenty years on: bracken clumps and young gums on the burnt ground either side of the escape track.
    public void BuildRegrowth(FireSim fire, Vector3 keepClear)
    {
        var rng = new System.Random(77);
        System.Func<float, float, float> R = (a, b) => a + (float)rng.NextDouble() * (b - a);
        int n = 0;
        for (int k = 0; k < 2400 && n < 700; k++)
        {
            float z = R(20f, 72f), off = R(-16f, 16f);
            if (Mathf.Abs(off) < VoxelWorld.TrackHalf + 0.5f) continue;              // the track stays clear
            float x = VoxelWorld.TrackCentreX(z) + off;
            var p = new Vector3(x, 0f, z);
            if (fire == null || !fire.CellBurnt(p) || Blocks(p, 0.8f)) continue;
            if ((new Vector2(x - keepClear.x, z - keepClear.z)).magnitude < 5f) continue;   // room round the dozer for the ending's camera
            p.y = HillY(x, z);
            n++;
            if (rng.NextDouble() < 0.2)
            {
                // a young gum: a thin stem and a few leafy lumps
                float h = R(1.4f, 3.6f);
                Box(p + Vector3.up * h * 0.5f, new Vector3(0.1f, h, 0.1f), Bark);
                for (int c = 0; c < 3; c++)
                    Box(p + new Vector3(R(-0.35f, 0.35f), h * (0.62f + 0.16f * c), R(-0.35f, 0.35f)), Vector3.one * (h * 0.24f - c * 0.08f), Leaves);
            }
            else
            {
                // bracken: a low clump of green fronds
                int fronds = 3 + rng.Next(4);
                for (int f = 0; f < fronds; f++)
                    Box(p + new Vector3(R(-0.55f, 0.55f), R(0.12f, 0.4f), R(-0.55f, 0.55f)), new Vector3(R(0.3f, 0.65f), R(0.2f, 0.45f), R(0.3f, 0.65f)), Bracken);
            }
        }
        Finish("Regrowth", false);
    }

    GameObject Finish(string name, bool shadows = true)
    {
        var go = new GameObject(name);
        go.transform.SetParent(transform, false);
        var mesh = new Mesh { indexFormat = UnityEngine.Rendering.IndexFormat.UInt32 };
        mesh.SetVertices(verts); mesh.SetNormals(normals); mesh.SetColors(colours); mesh.SetTriangles(tris, 0);
        mesh.RecalculateBounds();
        go.AddComponent<MeshFilter>().sharedMesh = mesh;
        var r = go.AddComponent<MeshRenderer>();
        r.sharedMaterial = world.material;
        r.shadowCastingMode = shadows ? UnityEngine.Rendering.ShadowCastingMode.On : UnityEngine.Rendering.ShadowCastingMode.Off;
        verts.Clear(); normals.Clear(); colours.Clear(); tris.Clear();
        return go;
    }

    void Solidify(float x, float z, float radius, bool machineOnly = false, float below = float.MaxValue) { solids.Add(new Solid { at = new Vector2(x, z), radius = radius, machineOnly = machineOnly, below = below }); }

    // ---------------------------------------------------------------- the site
    VoxelWorld world;
    System.Random rng;
    float Rand(float a, float b) { return a + (float)rng.NextDouble() * (b - a); }
    float Ground(float x, float z) { return HillY(x, z); }

    // the rails' height: on the tunnel floor inside the mine (not the hilltop above it), on the ground outside
    float RailY(float x, float z)
    {
        bool inTunnel = z > VoxelWorld.PortalZ - 0.8f && Mathf.Abs(x - VoxelWorld.PortalX) < VoxelWorld.TunnelHalfWidth;
        return inTunnel ? 0f : Ground(x, z);                // (the tunnel floor is at 0, under any rubble)
    }

    void Start()
    {
        world = VoxelWorld.Instance;
        if (world == null) return;
        solids.Clear();
        fallen.Clear();
        FireSim.Trees.Clear();
        rng = new System.Random(11);
        var cam = Camera.main;
        if (cam != null) cam.farClipPlane = 900f;
        RenderSettings.fogDensity = 0.0030f;                 // thinner haze than the bare test site had, so the far hills read as hills

        if (Worker.Instance == null) new GameObject("Worker").AddComponent<Worker>();   // the person you play as
        MineEntrance();
        Rails();
        if (MineCart.Instance == null) new GameObject("Mine cart").AddComponent<MineCart>();
        if (Finds.Instance == null) new GameObject("Finds").AddComponent<Finds>();
        if (SaveGame.Instance == null) new GameObject("Save game").AddComponent<SaveGame>();
        if (Money.Instance == null) new GameObject("Money").AddComponent<Money>();
        if (Upgrades.Instance == null) new GameObject("Upgrades").AddComponent<Upgrades>();
        if (PauseMenu.Instance == null) new GameObject("Pause menu").AddComponent<PauseMenu>();   // Esc: resume, settings, quit
        if (Hud.Instance == null) new GameObject("Hud").AddComponent<Hud>();                     // H help, F3 debug
        if (GameAudio.Instance == null) new GameObject("Sound").AddComponent<GameAudio>();         // everything you hear
        if (Goals.Instance == null) new GameObject("Goals").AddComponent<Goals>();                // one small goal at a time
        if (FireSim.Instance == null) new GameObject("Fire").AddComponent<FireSim>();      // idle unless the prologue lights it
        Dump();
        Clutter();
        Hillside();
        if (MountainRoadJob.Instance == null) new GameObject("Mountain road job").AddComponent<MountainRoadJob>();   // the road's guides and its pay
        TrackGums();
        GoldShed();                                          // after the crates and logs, so it can keep clear of them
        Trees();
        FarHills();
    }

    void OnDestroy() { solids.Clear(); }

    void MineEntrance()
    {
        float px = VoxelWorld.PortalX, pz = VoxelWorld.PortalZ - 0.6f, hw = VoxelWorld.TunnelHalfWidth + 0.25f, h = VoxelWorld.TunnelHeight + 0.15f;
        // two heavy frames, one at the mouth and one a little way out, with a plank roof between
        for (int f = 0; f < 2; f++)
        {
            float z = pz - f * 1.5f;
            Box(new Vector3(px - hw, h * 0.5f, z), new Vector3(0.36f, h, 0.36f), Timber);
            Box(new Vector3(px + hw, h * 0.5f, z), new Vector3(0.36f, h, 0.36f), Timber);
            Box(new Vector3(px, h + 0.2f, z), new Vector3(hw * 2f + 0.9f, 0.4f, 0.42f), DarkTimber);
        }
        for (float x = px - hw - 0.3f; x <= px + hw + 0.31f; x += 0.42f)
            Box(new Vector3(x, h + 0.5f, pz - 0.75f), new Vector3(0.36f, 0.14f, 2.3f), (int)(x * 7f) % 2 == 0 ? Timber : DarkTimber);
        // props holding the roof in the open stretches (the ones in the collapses went down with the roof), and a
        // lantern hanging in each open stretch
        foreach (float a in new[] { 8.2f, 11.6f, 20.0f, 22.2f, 28.6f, 30.4f })
        {
            float z = VoxelWorld.PortalZ + a, w = VoxelWorld.TunnelHalfWidthAt(a) + 0.25f, ph = VoxelWorld.TunnelHeightAt(a) + 0.15f;
            Box(new Vector3(px - w + 0.3f, ph * 0.5f, z), new Vector3(0.26f, ph, 0.26f), DarkTimber);
            Box(new Vector3(px + w - 0.3f, ph * 0.5f, z), new Vector3(0.26f, ph, 0.26f), DarkTimber);
            Box(new Vector3(px, ph - 0.05f, z), new Vector3(w * 2f, 0.24f, 0.26f), DarkTimber);
        }
        // a prop knocked flat by collapse 1, lying on the floor where it came out
        Beam(new Vector3(px - 1.1f, 0.15f, VoxelWorld.PortalZ + 7.4f), new Vector3(px + 0.4f, 0.15f, VoxelWorld.PortalZ + 9.2f), 0.24f, DarkTimber);
        var lamps = new[] { new Vector3(px + 0.6f, h - 0.8f, VoxelWorld.PortalZ + 10f), new Vector3(px - 0.8f, 2.25f, VoxelWorld.PortalZ + 21f), new Vector3(px + 0.9f, 2.4f, VoxelWorld.PortalZ + 29.5f) };
        foreach (var lp in lamps)
        {
            Box(lp + Vector3.up * 0.2f, new Vector3(0.2f, 0.04f, 0.2f), Steel);
            Box(lp, new Vector3(0.14f, 0.24f, 0.14f), Gold);
        }
        // a low timber fence either side of the mouth
        for (int side = -1; side <= 1; side += 2)
        {
            float x0 = px + side * (hw + 0.5f), x1 = px + side * (hw + 3.6f);
            Box(new Vector3(x0, 0.45f, pz - 0.5f), new Vector3(0.2f, 0.9f, 0.2f), Timber);
            Box(new Vector3(x1, 0.45f, pz - 0.5f), new Vector3(0.2f, 0.9f, 0.2f), Timber);
            Beam(new Vector3(x0, 0.7f, pz - 0.5f), new Vector3(x1, 0.7f, pz - 0.5f), 0.12f, DarkTimber);
            Beam(new Vector3(x0, 0.32f, pz - 0.5f), new Vector3(x1, 0.32f, pz - 0.5f), 0.12f, DarkTimber);
        }
        // the lantern: a little cage hanging from the first roof beam, with a warm light in it
        Vector3 lamp = new Vector3(px - 0.7f, h - 0.75f, pz + 0.6f);
        Beam(lamp + Vector3.up * 0.7f, lamp + Vector3.up * 0.2f, 0.05f, Steel);
        Box(lamp + Vector3.up * 0.2f, new Vector3(0.24f, 0.05f, 0.24f), Steel);
        Box(lamp, new Vector3(0.18f, 0.3f, 0.18f), Gold);
        Box(lamp - Vector3.up * 0.18f, new Vector3(0.24f, 0.05f, 0.24f), Steel);
        Finish("Mine entrance");
        for (int k = 0; k < 4; k++)
        {
            var light = new GameObject("Lantern light").AddComponent<Light>();
            light.transform.SetParent(transform, false);
            light.transform.position = k == 0 ? lamp : lamps[k - 1] - Vector3.up * 0.2f;
            light.type = LightType.Point;
            light.color = new Color(1f, 0.62f, 0.25f);
            light.intensity = k == 0 ? 3.2f : 2.2f;
            light.range = 9f;
            light.shadows = k == 0 ? LightShadows.Soft : LightShadows.None;
        }
        Solidify(px - hw, pz - 0.7f, 0.3f); Solidify(px + hw, pz - 0.7f, 0.3f);
        // nothing gets into the tunnel itself: it is too low for the machine.  (Only down at the tunnel's own level: up on
        // the hilltop above it the machine can drive across, which is the way to the mountain road.)
        for (float z = pz + 1f; z < pz + VoxelWorld.TunnelLength; z += 1.5f) Solidify(px, z, VoxelWorld.TunnelHalfWidth, true, VoxelWorld.TunnelHeight + 0.4f);
    }

    void Rails()
    {
        // from inside the tunnel, straight out of the door to the dump, DumpOut metres out (the owner's choice, 19 Nov:
        // the dump not far out of the mine door; it used to be 50 m away, down by the road)
        Vector3[] way =
        {
            new Vector3(VoxelWorld.PortalX, 0f, VoxelWorld.PortalZ + VoxelWorld.TunnelLength - 1.2f),
            new Vector3(VoxelWorld.PortalX, 0f, VoxelWorld.PortalZ - DumpOut - 0.9f),     // (the cart stops 0.9 m short of the end)
        };
        var pts = new List<Vector3>();
        for (int i = 0; i < way.Length - 1; i++)
        {
            Vector3 p0 = way[Mathf.Max(i - 1, 0)], p1 = way[i], p2 = way[i + 1], p3 = way[Mathf.Min(i + 2, way.Length - 1)];
            for (int s = 0; s < 14; s++)
            {
                float t = s / 14f;
                pts.Add(0.5f * ((2f * p1) + (-p0 + p2) * t + (2f * p0 - 5f * p1 + 4f * p2 - p3) * t * t + (-p0 + 3f * p1 - 3f * p2 + p3) * t * t * t));
            }
        }
        pts.Add(way[way.Length - 1]);
        RailPath.Clear();
        RailPath.AddRange(pts);
        float sinceSleeper = 1f;
        for (int i = 0; i < pts.Count - 1; i++)
        {
            Vector3 a = pts[i], b = pts[i + 1];
            a.y = RailY(a.x, a.z); b.y = RailY(b.x, b.z);
            Vector3 dir = (b - a).normalized, side = new Vector3(dir.z, 0f, -dir.x);
            Beam(a + side * 0.45f + Vector3.up * 0.15f, b + side * 0.45f + Vector3.up * 0.15f, 0.09f, Steel);
            Beam(a - side * 0.45f + Vector3.up * 0.15f, b - side * 0.45f + Vector3.up * 0.15f, 0.09f, Steel);
            sinceSleeper += (b - a).magnitude;
            if (sinceSleeper >= 0.7f)
            {
                sinceSleeper = 0f;
                Box(a + Vector3.up * 0.06f, new Vector3(0.2f, 0.11f, 1.5f), Quaternion.LookRotation(side), DarkTimber);
            }
        }
        Finish("Rails");
    }

    /// The dump at the end of the rails: a timber buffer stop across the track, the hopper beside it on the side
    /// the cart tips to (a timber-walled pit with a steel grate over a dark hole), and a sign on the other side.
    void Dump()
    {
        int n = RailPath.Count;
        if (n < 2) return;
        Vector3 end = RailPath[n - 1], before = RailPath[n - 2];
        Vector3 dir = (end - before); dir.y = 0f; dir.Normalize();
        Vector3 right = Vector3.Cross(Vector3.up, dir);           // the cart's right as it reaches the end
        float g = Ground(end.x, end.z);
        var rot = Quaternion.LookRotation(dir);
        // buffer stop: two posts and a heavy beam across the rails, just past their end
        Vector3 stop = end + dir * 0.35f;
        foreach (float sd in new[] { -0.55f, 0.55f })
            Box(stop + right * sd + Vector3.up * (g + 0.35f), new Vector3(0.22f, 0.7f, 0.22f), rot, DarkTimber);
        Box(stop + Vector3.up * (g + 0.55f), new Vector3(1.6f, 0.26f, 0.26f), rot, Timber);
        Box(stop + Vector3.up * (g + 0.55f) - dir * 0.15f, new Vector3(1.2f, 0.12f, 0.05f), rot, HiVis);   // bright face
        // the hopper, on the cart's left (it tips over its left side), level with where the cart stops
        Vector3 cartStop = end - dir * 0.85f;
        Vector3 hop = cartStop - right * (HopperAway + HopperHalf.x);
        float gh = Ground(hop.x, hop.z);
        hop.y = gh;
        Box(hop + Vector3.up * 0.015f, new Vector3(HopperHalf.x * 2f, 0.03f, HopperHalf.z * 2f), rot, Dark);   // the hole
        Vector3 hx = rot * Vector3.right, hz = rot * Vector3.forward;
        foreach (float sd in new[] { -1f, 1f })
        {
            Box(hop + hx * sd * (HopperHalf.x + 0.07f) + Vector3.up * 0.25f, new Vector3(0.14f, 0.5f, HopperHalf.z * 2f + 0.28f), rot, Timber);
            Box(hop + hz * sd * (HopperHalf.z + 0.07f) + Vector3.up * 0.25f, new Vector3(HopperHalf.x * 2f, 0.5f, 0.14f), rot, DarkTimber);
        }
        for (float k = -HopperHalf.z + 0.2f; k < HopperHalf.z; k += 0.32f)                        // the grate
            Box(hop + hz * k + Vector3.up * 0.46f, new Vector3(HopperHalf.x * 2f, 0.04f, 0.05f), rot, Steel);
        Box(hop + Vector3.up * 0.46f, new Vector3(0.05f, 0.04f, HopperHalf.z * 2f), rot, Steel);
        HopperToWorld = Matrix4x4.TRS(hop, rot, Vector3.one);
        // the sign, just past the end of the line, facing back up the track so you see it as you push the cart out
        Vector3 sign = end + dir * 2.2f + right * 0.6f;
        float gs = Ground(sign.x, sign.z);
        var face = Quaternion.LookRotation(-dir);
        right = Vector3.Cross(Vector3.up, -dir);
        foreach (float sd in new[] { -0.6f, 0.6f })
            Box(sign + right * sd + Vector3.up * (gs + 0.9f), new Vector3(0.14f, 1.8f, 0.14f), face, DarkTimber);
        Box(sign + Vector3.up * (gs + 1.55f), new Vector3(1.5f, 0.6f, 0.08f), face, HiVis);
        Box(sign + Vector3.up * (gs + 1.55f) - dir * 0.05f, new Vector3(1.1f, 0.12f, 0.04f), face, DarkTimber);   // a stripe across it
        Finish("Dump");
        Solidify(sign.x, sign.z, 0.8f);
        Solidify(stop.x, stop.z, 0.8f);
        Solidify(hop.x, hop.z, 0.9f);
        DumpSign = sign + Vector3.up * (gs + 2.1f);
    }

    /// The gold buyer's shed, east of the mine entrance past the crates: a small timber shed on a plank floor,
    /// open at the front with a counter (orange band, a few gold nuggets on it), a sloping roof, and a sign board.
    /// It faces west, towards the rails.
    void GoldShed()
    {
        // On the quarry floor east of the entrance: the first spot, nearest first, that is level with the rails
        // where they leave the mine, flat across the whole shed, and clear of the crates and log piles.
        float floorY = Ground(VoxelWorld.PortalX, VoxelWorld.PortalZ - 3f);
        Vector3 want = new Vector3(-13f, 0f, 2f), at = want;          // on the west side of the floor, out of the dozer's way
        bool found = false;
        for (float r = 0f; r <= 14f && !found; r += 0.5f)
            for (int k = 0; k < 16 && !found; k++)
            {
                float a = k * Mathf.PI / 8f;
                Vector3 c = want + new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a)) * r;
                bool nearRails = false;                                      // keep it off the rails and the entrance
                foreach (var rp in RailPath) if ((new Vector2(rp.x - c.x, rp.z - c.z)).sqrMagnitude < 4.5f * 4.5f) { nearRails = true; break; }
                if (nearRails) continue;
                if (Mathf.Abs(c.x) < 7f) continue;                          // the middle of the floor is where the dozer works
                if (Mathf.Abs(c.x - VoxelWorld.TrackX) < 6f && c.z > VoxelWorld.TrackZ0 - 22f) continue;   // and off the way up to the track
                float lo = 99f, hi = -99f;
                for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) { float h = Ground(c.x + i * 1.6f, c.z + j * 1.4f); lo = Mathf.Min(lo, h); hi = Mathf.Max(hi, h); }
                if (hi - lo > 0.25f || Mathf.Abs(lo - floorY) > 0.3f || Blocks(c, 2.0f)) continue;
                at = c; found = true;
            }
        at.y = Ground(at.x, at.z);
        var rot = Quaternion.LookRotation(Vector3.left);            // its front faces west
        Vector3 fw = rot * Vector3.forward, rt = rot * Vector3.right;
        const float W = 2.6f, D = 2.0f, H = 2.3f;                    // width (across the front), depth, wall height
        Box(at + Vector3.up * 0.08f, new Vector3(W + 0.3f, 0.16f, D + 0.3f), rot, DarkTimber);                     // floor
        Box(at - fw * (D * 0.5f) + Vector3.up * (H * 0.5f + 0.16f), new Vector3(W, H, 0.12f), rot, Timber);       // back wall
        foreach (float sd in new[] { -1f, 1f })
            Box(at + rt * (sd * W * 0.5f) + Vector3.up * (H * 0.5f + 0.16f), new Vector3(0.12f, H, D), rot, Timber);   // side walls
        foreach (float sd in new[] { -1f, 1f })                                                                  // front posts
            Box(at + fw * (D * 0.5f) + rt * (sd * W * 0.5f) + Vector3.up * (H * 0.5f + 0.16f), new Vector3(0.16f, H, 0.16f), rot, DarkTimber);
        // the roof, sloping down to the back, overhanging the front
        Quaternion roofTilt = rot * Quaternion.Euler(-12f, 0f, 0f);
        Box(at + fw * 0.2f + Vector3.up * (H + 0.32f), new Vector3(W + 0.6f, 0.12f, D + 0.9f), roofTilt, DarkTimber);
        // the counter across the front, with its bright band and a few nuggets on top
        Box(at + fw * (D * 0.5f - 0.05f) + Vector3.up * 0.62f, new Vector3(W - 0.2f, 0.92f, 0.36f), rot, Timber);
        Box(at + fw * (D * 0.5f + 0.14f) + Vector3.up * 0.82f, new Vector3(W - 0.3f, 0.14f, 0.04f), rot, HiVis);
        Box(at + fw * (D * 0.5f) + Vector3.up * 1.12f + rt * -0.5f, new Vector3(0.16f, 0.1f, 0.13f), rot, Gold);
        Box(at + fw * (D * 0.5f) + Vector3.up * 1.12f + rt * -0.25f, new Vector3(0.11f, 0.08f, 0.1f), rot, Gold);
        Box(at + fw * (D * 0.5f) + Vector3.up * 1.12f + rt * 0.45f, new Vector3(0.3f, 0.06f, 0.2f), rot, Steel);    // the scales
        Box(at + fw * (D * 0.5f) + Vector3.up * 1.25f + rt * 0.45f, new Vector3(0.05f, 0.2f, 0.05f), rot, Steel);
        // the sign board over the front
        Box(at + fw * (D * 0.5f + 0.15f) + Vector3.up * (H + 0.75f), new Vector3(W - 0.2f, 0.55f, 0.08f), rot, HiVis);
        Box(at + fw * (D * 0.5f + 0.2f) + Vector3.up * (H + 0.75f), new Vector3(W - 0.7f, 0.14f, 0.04f), rot, Gold);
        Finish("Gold buyer's shed");
        Solidify(at.x, at.z, 1.55f);
        GoldShedFront = at + fw * (D * 0.5f + 0.9f);
        GoldShedSign = at + fw * (D * 0.5f) + Vector3.up * (H + 1.3f);
    }

    /// Where you stand to sell gold (in front of the counter), and where its label floats.
    public static Vector3 GoldShedFront, GoldShedSign;

    /// Where the dump's sign is (for the "DUMP" label over it).
    public static Vector3 DumpSign;
    /// The hopper: its middle at ground level, turned to the track.  HopperHalf is half its opening (x across
    /// the track, z along it); HopperAway is the gap from the middle of the track to its near side.
    public static Matrix4x4 HopperToWorld = Matrix4x4.zero;
    public static readonly Vector3 HopperHalf = new Vector3(0.7f, 0.5f, 1.1f);
    public const float HopperAway = 0.95f;
    /// How far out of the mine door the cart stops at the dump, metres.
    public const float DumpOut = 8f;

    void Crate(Vector3 at, float size, float turn)
    {
        var rot = Quaternion.Euler(0f, turn, 0f);
        Box(at + Vector3.up * size * 0.5f, new Vector3(size, size, size) * 0.92f, rot, Timber);
        foreach (float s in new[] { -1f, 1f })
        {
            Box(at + rot * new Vector3(s * size * 0.5f, size * 0.5f, 0f), new Vector3(0.07f, size, size), rot, DarkTimber);
            Box(at + rot * new Vector3(0f, size * 0.5f, s * size * 0.5f), new Vector3(size, 0.16f, 0.07f), rot, DarkTimber);
        }
    }

    void Logs(Vector3 at, float turn, int count, float length)
    {
        var rot = Quaternion.Euler(0f, turn, 0f);
        int row = count, y = 0, n = 0;
        while (row > 0)
        {
            for (int k = 0; k < row; k++)
            {
                float x = (k - (row - 1) * 0.5f) * 0.42f;
                Box(at + rot * new Vector3(x, 0.2f + y * 0.36f, Rand(-0.2f, 0.2f)), new Vector3(0.38f, 0.38f, length * Rand(0.85f, 1f)), rot, n++ % 3 == 0 ? DarkTimber : Timber);
            }
            row--; y++;
        }
    }

    void Clutter()
    {
        float px = VoxelWorld.PortalX, pz = VoxelWorld.PortalZ;
        // by the mine entrance
        (float x, float z, float size, float turn)[] crates =
        {
            (px - 4.6f, pz - 2.6f, 1.0f, 12f), (px - 5.5f, pz - 3.3f, 0.8f, 40f), (px - 4.7f, pz - 2.7f, 0.0f, 0f),
            (-10f, -22f, 1.0f, 25f), (-11.2f, -21.4f, 0.8f, 70f),
        };
        foreach (var c in crates)
        {
            if (c.size <= 0f) { Crate(new Vector3(c.x, Ground(c.x, c.z) + 0.95f, c.z), 0.7f, 30f); continue; }   // one stacked on another
            Crate(new Vector3(c.x, Ground(c.x, c.z), c.z), c.size, c.turn);
            Solidify(c.x, c.z, c.size * 0.7f);
        }
        (float x, float z, float turn, int count, float len)[] piles =
        {
            (px + 12f, pz - 13.6f, 70f, 4, 3.4f), (px - 7f, pz - 6.5f, -20f, 3, 3.0f), (3f, -27f, 85f, 4, 3.6f),
        };
        foreach (var l in piles)
        {
            Logs(new Vector3(l.x, Ground(l.x, l.z), l.z), l.turn, l.count, l.len);
            Solidify(l.x, l.z, 1.5f);
        }
        Finish("Crates and logs");
    }

    void Tree(Vector3 at, float height) { BeginTree(at, height); TreeShape(at, height); curTree = -1; }

    void TreeShape(Vector3 at, float height)
    {
        // a gum tree: a pale leaning trunk that forks, with loose clumps of leaves at the ends of the branches
        Vector3 p = at;
        float thick = 0.5f, lean = Rand(-0.12f, 0.12f), leanZ = Rand(-0.12f, 0.12f);
        int segs = Mathf.RoundToInt(height * 0.55f / 0.8f);
        for (int s = 0; s < segs; s++)
        {
            Vector3 q = p + new Vector3(lean, 0.8f, leanZ);
            Beam(p - Vector3.up * 0.05f, q, thick, Bark);
            p = q; thick = Mathf.Max(0.22f, thick - 0.05f);
        }
        int branches = rng.Next(3, 5);
        var clumpsT = new List<Vector3>();
        for (int b = 0; b < branches; b++)
        {
            float ang = (b + Rand(0f, 0.6f)) * Mathf.PI * 2f / branches, reach = height * Rand(0.22f, 0.36f);
            Vector3 tip = p + new Vector3(Mathf.Cos(ang) * reach, height * Rand(0.2f, 0.38f), Mathf.Sin(ang) * reach);
            clumpsT.Add(tip);
            Vector3 mid = Vector3.Lerp(p, tip, 0.55f) + Vector3.up * 0.25f;
            Beam(p, mid, thick * 0.75f, Bark);
            Beam(mid, tip, thick * 0.5f, Bark);
            int leaves = rng.Next(40, 58);
            float spread = height * 0.25f;
            for (int k = 0; k < leaves; k++)
            {
                Vector3 off = new Vector3(Rand(-1f, 1f), Rand(-0.35f, 0.45f), Rand(-1f, 1f));
                if (off.sqrMagnitude > 1.2f) off *= 0.7f;
                float size = Rand(0.55f, 1.1f);
                Box(tip + off * spread, new Vector3(size, size * Rand(0.6f, 1f), size), Quaternion.Euler(0f, Rand(0f, 90f), 0f), Leaves);
            }
        }
        SetCrown(p, clumpsT);
    }

    void Trees()
    {
        // on the hill round the quarry, and out on the open ground: never on the work floor or the road
        (float x, float z, float h)[] spots =
        {
            (-27f, 14f, 8.5f), (-20f, 22f, 7.5f), (-8f, 27f, 9f), (2f, 30f, 7f), (27f, 17f, 9f), (33f, 4f, 7.5f),
            (31f, -12f, 8f), (-33f, 2f, 9f), (-31f, -14f, 7.5f), (24f, -30f, 8f), (-22f, -33f, 8.5f), (13f, -37f, 7f),
            (-38f, 24f, 8f), (38f, 30f, 8.5f), (-12f, 38f, 7.5f), (24f, 38f, 8f), (-36f, -34f, 7.5f), (36f, -36f, 8f),
        };
        int n = 0;
        foreach (var s in spots)
        {
            if (InBreakLane(s.x, s.z) || NearRoad(s.x, s.z)) continue;
            Tree(new Vector3(s.x, Ground(s.x, s.z) - 0.1f, s.z), s.h);
            Solidify(s.x, s.z, 0.45f);
            Finish("Gum tree " + (++n));
        }
        // low scrub scattered on the grassy ground
        for (int k = 0; k < 90; k++)
        {
            float x = Rand(-43f, 43f), z = Rand(-43f, 43f);
            float inFloor = new Vector2(x / 26.5f, (z + 6f) / 21.5f).magnitude;
            if (inFloor < 1f || (z < -18f && Mathf.Abs(x - VoxelWorld.RoadX) < 8f)) continue;
            float y = Ground(x, z), size = Rand(0.35f, 0.8f);
            for (int j = 0; j < 5; j++)
                Box(new Vector3(x + Rand(-0.4f, 0.4f), y + size * Rand(0.2f, 0.7f), z + Rand(-0.4f, 0.4f)), Vector3.one * size * Rand(0.5f, 1f), Quaternion.Euler(0f, Rand(0f, 90f), 0f), Leaves);
        }
        Finish("Scrub");
    }

    // ---------------------------------------------------------------- the hillside behind the mine
    // Past the north fence the hill keeps climbing, as scenery you can't dig: from the height of the site's own hill at
    // the fence, up about 26 m over the next 100 m.  The escape track carries on up it as bare dirt.
    const float HalfSite = VoxelWorld.SiteHalf;           // 48 m

    // (The recipes are in Mountain, in MountainRoad.cs, so the voxel jobs can use them too.)

    /// The hillside past the north fence, with the mountain standing on it.
    public static float HillsideY(float x, float z) { return Mountain.PastFenceY(x, z) + MountainRoad.ShapeDelta(x, z); }

    /// Ground height anywhere: the site's voxels inside the fence, the hillside past the north fence (and the road
    /// strip's voxels on the mountain), flat elsewhere.
    public static float HillY(float x, float z)
    {
        var w = VoxelWorld.Instance;
        if (z > HalfSite - 0.5f && Mathf.Abs(x) < 140f)
            return w != null && w.KindAt(x, z) == VoxelWorld.BlockStrip ? w.HeightAt(x, z) : HillsideY(x, z);
        return w != null ? w.HeightAt(x, z) : 0f;
    }

    /// Kept clear of trees: the road up the mountain, and a way onto it from the firebreak lane.
    public static bool NearRoad(float x, float z, float clear = 7f) { return MountainRoad.DistanceTo(x, z) < clear; }

    void Hillside()
    {
        // one corner of the mesh's 2 m grid sits on a corner of the voxel blocks, so the holes left for the road strip
        // line up with it exactly
        const float x0 = -140f, x1 = 140f, z0 = 48f, z1 = 190f, step = 2f;
        int nx = Mathf.RoundToInt((x1 - x0) / step) + 1, nz = Mathf.RoundToInt((z1 - z0) / step) + 1;
        var hs = new float[nx * nz];
        for (int j = 0; j < nz; j++) for (int i = 0; i < nx; i++) hs[i + nx * j] = HillsideY(x0 + i * step, z0 + j * step);
        Vector3 o = world.Origin;
        System.Func<float, float, bool> strip = (qx, qz) =>
            world.BlockIsStrip(Mathf.FloorToInt((qx - o.x) / step), Mathf.FloorToInt((qz - o.z) / step));
        for (int j = 0; j < nz; j++)
            for (int i = 0; i < nx; i++)
            {
                float x = x0 + i * step, z = z0 + j * step;
                float hx = hs[Mathf.Min(i + 1, nx - 1) + nx * j] - hs[Mathf.Max(i - 1, 0) + nx * j];
                float hz = hs[i + nx * Mathf.Min(j + 1, nz - 1)] - hs[i + nx * Mathf.Max(j - 1, 0)];
                verts.Add(new Vector3(x, hs[i + nx * j], z));
                normals.Add(new Vector3(-hx, 4f * step / 2f, -hz).normalized);
                colours.Add(new Color32(ForestFloor, 0, 0, 255));   // one material: ids must not blend across a triangle
            }
        int holes = 0;
        for (int j = 0; j < nz - 1; j++)
            for (int i = 0; i < nx - 1; i++)
            {
                if (strip(x0 + (i + 0.5f) * step, z0 + (j + 0.5f) * step)) { holes++; continue; }   // the road strip's voxels are here
                int a = i + nx * j, b = a + 1, c = a + nx, d = c + 1;
                tris.Add(a); tris.Add(c); tris.Add(b);
                tris.Add(b); tris.Add(c); tris.Add(d);
            }
        // Round each hole, a wall from the hillside's surface down to the bottom of the strip's voxels, facing into the
        // strip.  It is only seen where the strip has been dug lower than the mountain beside it: the mountain's own
        // ground, which can't be dug (grey, like rock).
        int walls = 0;
        for (int j = 0; j < nz - 1; j++)
            for (int i = 0; i < nx - 1; i++)
            {
                float cx = x0 + (i + 0.5f) * step, cz = z0 + (j + 0.5f) * step;
                if (!strip(cx, cz)) continue;
                int bx = Mathf.FloorToInt((cx - o.x) / step), bz = Mathf.FloorToInt((cz - o.z) / step);
                float bottom = world.BlockLoY(bx, bz) - 0.05f;
                for (int side = 0; side < 4; side++)
                {
                    int nbx = bx + (side == 0 ? 1 : side == 1 ? -1 : 0), nbz = bz + (side == 2 ? 1 : side == 3 ? -1 : 0);
                    if (world.BlockHasVoxels(nbx, nbz)) continue;
                    // the shared edge, as two grid corners, ordered so the wall faces into this block
                    int ia, ja, ib, jb;
                    if (side == 0) { ia = i + 1; ja = j; ib = i + 1; jb = j + 1; }
                    else if (side == 1) { ia = i; ja = j + 1; ib = i; jb = j; }
                    else if (side == 2) { ia = i + 1; ja = j + 1; ib = i; jb = j + 1; }
                    else { ia = i; ja = j; ib = i + 1; jb = j; }
                    Vector3 pa = new Vector3(x0 + ia * step, hs[ia + nx * ja], z0 + ja * step), pb = new Vector3(x0 + ib * step, hs[ib + nx * jb], z0 + jb * step);
                    Vector3 inward = new Vector3(side == 0 ? -1 : side == 1 ? 1 : 0, 0, side == 2 ? -1 : side == 3 ? 1 : 0);
                    int start = verts.Count;
                    verts.Add(pa); verts.Add(pb); verts.Add(new Vector3(pb.x, bottom, pb.z)); verts.Add(new Vector3(pa.x, bottom, pa.z));
                    for (int k = 0; k < 4; k++) { normals.Add(inward); colours.Add(new Color32(Rock, 0, 0, 255)); }
                    tris.Add(start); tris.Add(start + 2); tris.Add(start + 1);     // (Unity's front faces go clockwise)
                    tris.Add(start); tris.Add(start + 3); tris.Add(start + 2);
                    walls++;
                }
            }
        HillsideHoles = holes; HillsideWalls = walls;
        Finish("Hillside");
        // the track up it: a strip of dirt laid just over the ground
        for (float z = z0; z < z1 - 1f; z += 1f)
        {
            float cx = VoxelWorld.TrackCentreX(z);
            int start = verts.Count;
            for (int k = -1; k <= 1; k += 2)
            {
                float x = cx + k * VoxelWorld.TrackHalf;
                verts.Add(new Vector3(x, HillsideY(x, z) + 0.04f, z)); normals.Add(Vector3.up); colours.Add(new Color32(TrackDirt, 0, 0, 255));
            }
            if (z > z0) { int a = start - 2; tris.Add(a); tris.Add(start); tris.Add(a + 1); tris.Add(a + 1); tris.Add(start); tris.Add(start + 1); }
        }
        Finish("Hillside track");
    }

    /// A tall gum (mountain ash): a long, straight, pale trunk, bare for most of its height, with its leaves in
    /// loose clumps right at the top.  The kind of forest the prologue is set in.
    void TallGum(Vector3 at, float height) { BeginTree(at, height); TallGumShape(at, height); curTree = -1; }

    void TallGumShape(Vector3 at, float height)
    {
        Vector3 p = at;
        float lean = Rand(-0.04f, 0.04f), leanZ = Rand(-0.04f, 0.04f);
        float thick = Rand(0.55f, 0.75f);
        int segs = Mathf.RoundToInt(height * 0.72f / 1.2f);
        for (int s = 0; s < segs; s++)
        {
            Vector3 q = p + new Vector3(lean, 1.2f, leanZ);
            Beam(p - Vector3.up * 0.05f, q, thick, Bark);
            p = q; thick = Mathf.Max(0.26f, thick - 0.025f);
        }
        int branches = rng.Next(3, 6);
        var clumpsG = new List<Vector3>();
        for (int b = 0; b < branches; b++)
        {
            float ang = (b + Rand(0f, 0.7f)) * Mathf.PI * 2f / branches, reach = height * Rand(0.1f, 0.18f);
            Vector3 tip = p + new Vector3(Mathf.Cos(ang) * reach, height * Rand(0.12f, 0.24f), Mathf.Sin(ang) * reach);
            clumpsG.Add(tip);
            Beam(p, tip, thick * 0.6f, Bark);
            int leaves = rng.Next(16, 26);
            float spread = height * 0.11f;
            for (int k = 0; k < leaves; k++)
            {
                Vector3 off = new Vector3(Rand(-1f, 1f), Rand(-0.45f, 0.5f), Rand(-1f, 1f));
                float size = Rand(0.8f, 1.5f);
                Box(tip + off * spread, new Vector3(size, size * Rand(0.55f, 0.9f), size), Quaternion.Euler(0f, Rand(0f, 90f), 0f), Leaves);
            }
        }
        SetCrown(p, clumpsG);
    }

    /// Dense tall gums on both sides of the escape track, from the hilltop behind the mine up the hillside.
    void TrackGums()
    {
        int n = 0, inMesh = 0;
        for (float z = 15f; z < 175f; z += 3.4f)
            for (int side = -1; side <= 1; side += 2)
                for (float o = VoxelWorld.TrackHalf + 2.2f; o < 34f; o += (z < 110f ? 3.4f : 5.5f) * (o > 18f ? 1.5f : 1f))
                {
                    if (o > 18f && Rand(0f, 1f) < (o - 18f) / 22f) continue;          // thinning out at the edges
                    float x = VoxelWorld.TrackCentreX(z) + side * (o + Rand(-0.9f, 0.9f)), zz = z + Rand(-1.3f, 1.3f);
                    if (z > 110f && Rand(0f, 1f) < 0.35f) continue;
                    if (NearRoad(x, zz)) continue;
                    bool inSite = zz < HalfSite - 1f;
                    if (inSite)
                    {
                        // inside the fence only on the untouched hilltop: not on the quarry's benches or over the mine
                        if (world.HeightAt(x, zz) < 3.4f || Mathf.Abs(x) > HalfSite - 3f || InBreakLane(x, zz)) continue;
                        if (Mathf.Abs(x - VoxelWorld.PortalX) < 4.5f && zz < VoxelWorld.PortalZ + 4f) continue;
                    }
                    float h = Rand(16f, 24f) * (z > 120f ? 0.85f : 1f);
                    TallGum(new Vector3(x, HillY(x, zz) - 0.15f, zz), h);
                    if (inSite) Solidify(x, zz, 0.5f);
                    n++;
                    if (++inMesh >= 14) { Finish("Track gums " + n); inMesh = 0; }
                }
        if (inMesh > 0) Finish("Track gums " + n);
        TrackGumCount = n;
        HillGums();
    }

    /// A gum seen from a distance: a straight pale trunk and a few big clumps of leaves at the top.  About a tenth of
    /// the blocks of a TallGum, so the whole hillside can be covered.
    void FarGum(Vector3 at, float height) { BeginTree(at, height); FarGumShape(at, height); curTree = -1; }

    void FarGumShape(Vector3 at, float height)
    {
        float thick = Rand(0.5f, 0.75f);
        Vector3 top = at + new Vector3(Rand(-0.4f, 0.4f), height * 0.78f, Rand(-0.4f, 0.4f));
        Beam(at - Vector3.up * 0.1f, top, thick, Bark);
        int clumps = rng.Next(3, 6);
        var clumpsF = new List<Vector3>();
        for (int k = 0; k < clumps; k++)
        {
            Vector3 off = new Vector3(Rand(-1f, 1f), Rand(-0.2f, 0.6f), Rand(-1f, 1f)) * height * 0.13f;
            float size = height * Rand(0.12f, 0.2f);
            Box(top + off, new Vector3(size, size * Rand(0.45f, 0.7f), size), Quaternion.Euler(0f, Rand(0f, 90f), 0f), Leaves);
            clumpsF.Add(top + off);
        }
        SetCrown(top, clumpsF);
    }

    /// The rest of the hill: the hilltop round the mine gets detailed gums (you walk among them), the hillside past
    /// the fence gets far gums all over it, in clumps and gaps so it looks like bush and not a plantation.
    void HillGums()
    {
        int n = 0, inMesh = 0;
        // the hilltop inside the fence, away from the track's own band of trees
        for (float z = 14f; z < HalfSite - 1.5f; z += 4.6f)
            for (float x = -HalfSite + 3f; x < HalfSite - 3f; x += 4.6f)
            {
                float px = x + Rand(-1.6f, 1.6f), pz = z + Rand(-1.6f, 1.6f);
                if (Mathf.Abs(px - VoxelWorld.TrackCentreX(pz)) < 36f) continue;            // the track's trees cover that
                if (world.HeightAt(px, pz) < 3.4f || Blocks(new Vector3(px, 0f, pz), 1.2f) || InBreakLane(px, pz)) continue;
                if (noise.snoise(new float2(px, pz) * 0.06f) < -0.35f) continue;               // a clearing
                if (NearRoad(px, pz)) continue;
                TallGum(new Vector3(px, HillY(px, pz) - 0.15f, pz), Rand(13f, 20f));
                Solidify(px, pz, 0.5f);
                n++;
                if (++inMesh >= 14) { Finish("Hilltop gums " + n); inMesh = 0; }
            }
        if (inMesh > 0) Finish("Hilltop gums " + n);
        HillGumCount = n;
        // the hillside past the fence: far gums everywhere except right along the track (it has its own)
        int far = 0; inMesh = 0;
        for (float z = HalfSite + 1f; z < 186f; z += 5.2f)
            for (float x = -136f; x < 136f; x += 5.2f)
            {
                float px = x + Rand(-2f, 2f), pz = z + Rand(-2f, 2f);
                if (Mathf.Abs(px - VoxelWorld.TrackCentreX(pz)) < 30f && pz < 172f) continue;
                float clump = noise.snoise(new float2(px, pz) * 0.025f);
                if (clump < -0.45f || Rand(0f, 1f) < 0.12f + Mathf.Max(0f, -clump) * 0.4f) continue;   // clumps and gaps
                if (NearRoad(px, pz)) continue;
                float h = Rand(14f, 22f) * (1f - 0.25f * Mathf.InverseLerp(60f, 186f, pz));
                FarGum(new Vector3(px, HillsideY(px, pz) - 0.2f, pz), h);
                far++;
                if (++inMesh >= 120) { Finish("Hillside gums " + far, false); inMesh = 0; }
            }
        if (inMesh > 0) Finish("Hillside gums " + far, false);
        FarGumCount = far;
    }

    public static int HillGumCount, FarGumCount;
    public static int HillsideHoles, HillsideWalls;          // the road strip's holes in the hillside mesh, and the walls round them

    public static int TrackGumCount;

    /// The lane the prologue's firebreak is cut along: kept clear of trees (an old fire trail).
    public static bool InBreakLane(float x, float z)
    {
        return Mathf.Abs(z - Prologue.LaneZ) < 4.5f && x > Prologue.LaneX0 - 4f && x < Prologue.LaneX1 + 3f;
    }

    void FarHills()
    {
        // stepped green hills a few hundred metres off, so the site sits in a valley and not on a bare plain
        for (int k = 0; k < 16; k++)
        {
            float ang = (k + Rand(-0.3f, 0.3f)) * Mathf.PI * 2f / 16f, dist = Rand(210f, 380f);
            float width = Rand(130f, 230f), height = Rand(30f, 75f);
            Vector3 c = new Vector3(Mathf.Cos(ang) * dist, -1f, Mathf.Sin(ang) * dist);
            int steps = 6;
            for (int s = 0; s < steps; s++)
            {
                float t = s / (float)steps, w = width * (1f - t * 0.82f);
                Box(c + new Vector3(Rand(-6f, 6f) * s, height * (t + 0.5f / steps), Rand(-6f, 6f) * s), new Vector3(w, height / steps, w * Rand(0.7f, 1f)),
                    Quaternion.Euler(0f, Rand(0f, 90f), 0f), Leaves);
            }
        }
        Finish("Far hills", false);
    }
}
