// The scenery of the quarry: the timber mine entrance and its lantern, the rails running out of it,
// gum trees, crates, log piles, and green hills in the distance.
//
// Everything here is built from plain boxes when the game starts, and drawn with the ground's own
// shader, so each box picks up the same small-block texture as the ground.  None of it can be dug.
// The bigger things are solid to the dozer (see Blocks).
using System.Collections.Generic;
using UnityEngine;

public class SiteProps : MonoBehaviour
{
    // material ids understood by the ground shader
    const byte Timber = 11, DarkTimber = 12, Steel = 13, Leaves = 14, Bark = 15, Rock = 3, Gold = 5, HiVis = 16, Dark = 20;

    struct Solid { public Vector2 at; public float radius; public bool machineOnly; }
    static readonly List<Solid> solids = new List<Solid>();

    /// The middle of the track, point by point, from deep in the tunnel out to the end of the line.
    public static readonly List<Vector3> RailPath = new List<Vector3>();

    /// True if a machine of the given radius at this spot would be inside something solid.
    /// A person on foot is not stopped by things that only keep machines out (the mine tunnel).
    public static bool Blocks(Vector3 pos, float radius, bool onFoot = false)
    {
        for (int i = 0; i < solids.Count; i++)
        {
            if (onFoot && solids[i].machineOnly) continue;
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

    void Box(Vector3 centre, Vector3 size, Quaternion rot, byte mat)
    {
        var col = new Color32(mat, 0, 0, 255);
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

    void Solidify(float x, float z, float radius, bool machineOnly = false) { solids.Add(new Solid { at = new Vector2(x, z), radius = radius, machineOnly = machineOnly }); }

    // ---------------------------------------------------------------- the site
    VoxelWorld world;
    System.Random rng;
    float Rand(float a, float b) { return a + (float)rng.NextDouble() * (b - a); }
    float Ground(float x, float z) { return world.HeightAt(x, z); }

    void Start()
    {
        world = VoxelWorld.Instance;
        if (world == null) return;
        solids.Clear();
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
        Dump();
        Clutter();
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
        // props holding the roof further in
        for (float z = pz + 3f; z < pz + VoxelWorld.TunnelLength - 1f; z += 3.5f)
        {
            Box(new Vector3(px - hw + 0.3f, h * 0.5f, z), new Vector3(0.26f, h, 0.26f), DarkTimber);
            Box(new Vector3(px + hw - 0.3f, h * 0.5f, z), new Vector3(0.26f, h, 0.26f), DarkTimber);
            Box(new Vector3(px, h - 0.05f, z), new Vector3(hw * 2f, 0.24f, 0.26f), DarkTimber);
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
        for (int k = 0; k < 2; k++)
        {
            var light = new GameObject("Lantern light").AddComponent<Light>();
            light.transform.SetParent(transform, false);
            light.transform.position = k == 0 ? lamp : new Vector3(px + 0.6f, h - 0.8f, pz + 8f);
            light.type = LightType.Point;
            light.color = new Color(1f, 0.62f, 0.25f);
            light.intensity = k == 0 ? 3.2f : 2.2f;
            light.range = 9f;
            light.shadows = k == 0 ? LightShadows.Soft : LightShadows.None;
        }
        Solidify(px - hw, pz - 0.7f, 0.3f); Solidify(px + hw, pz - 0.7f, 0.3f);
        // nothing gets into the tunnel itself: it is too low for the machine
        for (float z = pz + 1f; z < pz + VoxelWorld.TunnelLength; z += 1.5f) Solidify(px, z, VoxelWorld.TunnelHalfWidth, true);
    }

    void Rails()
    {
        // from inside the tunnel, out across the floor and away down the road to the south
        Vector3[] way =
        {
            new Vector3(VoxelWorld.PortalX, 0f, VoxelWorld.PortalZ + 10f), new Vector3(VoxelWorld.PortalX, 0f, 3f),
            new Vector3(6f, 0f, -6f), new Vector3(-1f, 0f, -15f), new Vector3(VoxelWorld.RoadX, 0f, -24f),
            new Vector3(VoxelWorld.RoadX, 0f, -40f),
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
            a.y = Ground(a.x, a.z); b.y = Ground(b.x, b.z);
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
        Vector3 want = new Vector3(VoxelWorld.PortalX + 6f, 0f, VoxelWorld.PortalZ - 5f), at = want;
        bool found = false;
        for (float r = 0f; r <= 8f && !found; r += 0.5f)
            for (int k = 0; k < 16 && !found; k++)
            {
                float a = k * Mathf.PI / 8f;
                Vector3 c = want + new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a)) * r;
                if (c.x < VoxelWorld.PortalX + 3.5f) continue;              // keep it off the rails and the entrance
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
            (px + 4.4f, pz - 3.2f, 1.1f, -8f), (-10f, -22f, 1.0f, 25f), (-11.2f, -21.4f, 0.8f, 70f),
        };
        foreach (var c in crates)
        {
            if (c.size <= 0f) { Crate(new Vector3(c.x, Ground(c.x, c.z) + 0.95f, c.z), 0.7f, 30f); continue; }   // one stacked on another
            Crate(new Vector3(c.x, Ground(c.x, c.z), c.z), c.size, c.turn);
            Solidify(c.x, c.z, c.size * 0.7f);
        }
        (float x, float z, float turn, int count, float len)[] piles =
        {
            (px + 5.2f, pz - 6.2f, 70f, 4, 3.4f), (px - 7f, pz - 6.5f, -20f, 3, 3.0f), (3f, -27f, 85f, 4, 3.6f),
        };
        foreach (var l in piles)
        {
            Logs(new Vector3(l.x, Ground(l.x, l.z), l.z), l.turn, l.count, l.len);
            Solidify(l.x, l.z, 1.5f);
        }
        Finish("Crates and logs");
    }

    void Tree(Vector3 at, float height)
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
        for (int b = 0; b < branches; b++)
        {
            float ang = (b + Rand(0f, 0.6f)) * Mathf.PI * 2f / branches, reach = height * Rand(0.22f, 0.36f);
            Vector3 tip = p + new Vector3(Mathf.Cos(ang) * reach, height * Rand(0.2f, 0.38f), Mathf.Sin(ang) * reach);
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
    }

    void Trees()
    {
        // on the hill round the quarry, and out on the open ground: never on the work floor or the road
        (float x, float z, float h)[] spots =
        {
            (-27f, 14f, 8.5f), (-20f, 22f, 7.5f), (-8f, 27f, 9f), (2f, 30f, 7f), (17f, 27f, 8.5f), (27f, 17f, 9f), (33f, 4f, 7.5f),
            (31f, -12f, 8f), (-33f, 2f, 9f), (-31f, -14f, 7.5f), (24f, -30f, 8f), (-22f, -33f, 8.5f), (13f, -37f, 7f),
            (-38f, 24f, 8f), (38f, 30f, 8.5f), (-12f, 38f, 7.5f), (24f, 38f, 8f), (-36f, -34f, 7.5f), (36f, -36f, 8f),
        };
        int n = 0;
        foreach (var s in spots)
        {
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
