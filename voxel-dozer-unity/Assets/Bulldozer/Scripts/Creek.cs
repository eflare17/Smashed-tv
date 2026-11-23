// The creek (the owner's route, 23 Nov 2026): a spring in the bush on the hill above the mine, outside the quarry
// cut, running west through the trees, then south down the outside of the quarry and off the bottom of the map.
//
// It is a bed cut into the ground: about a metre wide and at least 35 cm deep, its banks easing back up to the
// ground 1.5 m out, and always running downhill (where the hill bumps up, it cuts deeper: a small gully).  The bed
// is cut after the trees are placed (so the forest, and the trees a save has felled, don't change); the line bends
// round any trunk that stands in its way.  Water comes out at the spring (Fluids.cs) and drains away where the
// creek leaves the map.  Reeds and bushes line its banks (SiteProps.CreekPlants).
//
// Cutting the bed is part of making the ground: the chunks it touches count as dug, so a save keeps them; after a
// load or a ground reset it is cut again (it only ever takes away, and taking away what's gone takes nothing).
using System.Collections.Generic;
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;

public static class Creek
{
    /// The route, as the owner saw it on the map: (x, z) in metres.
    static readonly Vector2[] Route =
    {
        new Vector2(1f, 23f), new Vector2(-6f, 22.5f), new Vector2(-13f, 22f), new Vector2(-20f, 21f), new Vector2(-27f, 17f),
        new Vector2(-34f, 11f), new Vector2(-39f, 3f), new Vector2(-41f, -7f), new Vector2(-40f, -17f), new Vector2(-37f, -27f),
        new Vector2(-34f, -36f), new Vector2(-32f, -44f), new Vector2(-31.5f, -47.2f),
    };
    public const float Step = 0.25f;                         // metres between points along it
    public const float BedHalf = 0.5f, BankOut = 1.5f, Depth = 0.35f;
    public const float MinFall = 0.004f;                     // the bed drops at least this much every point (1.6 cm a metre)

    /// The line along the middle of the bed: x, bed height, z.  Empty until Build.
    public static readonly List<Vector3> Line = new List<Vector3>();
    static readonly List<float> groundAt = new List<float>();
    public static Vector3 Spring { get { return Line.Count > 0 ? Line[0] : Vector3.zero; } }
    public static Vector3 End { get { return Line.Count > 0 ? Line[Line.Count - 1] : Vector3.zero; } }
    public static long Carved { get; private set; }          // voxels the last cut took away (tests)

    /// Lays out the line (bent round the trees) and cuts the bed.  `obstacles`: (x, z, radius) of trunks and props.
    public static void Build(VoxelWorld w, List<Vector3> obstacles)
    {
        Line.Clear(); groundAt.Clear();
        // a smooth curve through the route, sampled every Step, with a gentle wander
        var pts = new List<Vector2>();
        for (int i = 0; i < Route.Length - 1; i++)
        {
            Vector2 p0 = Route[Mathf.Max(0, i - 1)], p1 = Route[i], p2 = Route[i + 1], p3 = Route[Mathf.Min(Route.Length - 1, i + 2)];
            float len = Vector2.Distance(p1, p2);
            int n = Mathf.Max(1, Mathf.CeilToInt(len / Step));
            for (int k = 0; k < n; k++) pts.Add(CatmullRom(p0, p1, p2, p3, k / (float)n));
        }
        pts.Add(Route[Route.Length - 1]);
        float s = 0f;
        for (int i = 1; i < pts.Count - 1; i++)
        {
            s += Vector2.Distance(pts[i], pts[i - 1]);
            Vector2 dir = (pts[i + 1] - pts[i - 1]).normalized, side = new Vector2(-dir.y, dir.x);
            pts[i] += side * (0.55f * Mathf.Sin(s * 0.31f) + 0.3f * Mathf.Sin(s * 0.83f + 1f));
        }
        // bend round anything standing in the way, a few relaxing passes
        for (int pass = 0; pass < 12; pass++)
        {
            bool moved = false;
            for (int i = 1; i < pts.Count - 1; i++)
                foreach (var o in obstacles)
                {
                    Vector2 d = pts[i] - new Vector2(o.x, o.z);
                    float need = o.y + BedHalf + 0.35f, l = d.magnitude;
                    if (l >= need) continue;
                    pts[i] += (l > 1e-3f ? d / l : Vector2.right) * (need - l);
                    moved = true;
                }
            for (int i = 1; i < pts.Count - 1; i++) pts[i] = Vector2.Lerp(pts[i], (pts[i - 1] + pts[i + 1]) * 0.5f, 0.3f);
            if (!moved) break;
        }
        // the bed: always downhill, at least Depth under the ground
        float bed = float.MaxValue;
        foreach (var p in pts)
        {
            float g = w.TopAt(p.x, p.y);
            bed = Mathf.Min(g - Depth, bed - MinFall);
            Line.Add(new Vector3(p.x, bed, p.y));
            groundAt.Add(g);
        }
        // the spring: a little pool a bit deeper than the bed
        Line[0] = new Vector3(Line[0].x, Line[0].y - 0.1f, Line[0].z);
        w.CurrentLine = Line;                              // its bed's cells get a current (VoxelWorldFluid.cs)
        Cut(w);
    }

    /// Cuts the bed into the ground (again: after a load or a reset).  Returns the voxels it took away.
    public static long Cut(VoxelWorld w)
    {
        if (Line.Count == 0) return 0;
        var pts = new NativeArray<float4>(Line.Count, Allocator.TempJob);
        for (int i = 0; i < Line.Count; i++) pts[i] = new float4(Line[i].x, Line[i].y, Line[i].z, groundAt[i]);
        Carved = w.CarveCreek(pts);
        pts.Dispose();
        return Carved;
    }

    /// The nearest point of the line to (x, z), and how far.
    public static float Nearest(float x, float z, out int index)
    {
        index = -1; float best = float.MaxValue;
        for (int i = 0; i < Line.Count; i++)
        {
            float dx = Line[i].x - x, dz = Line[i].z - z, d = dx * dx + dz * dz;
            if (d < best) { best = d; index = i; }
        }
        return Mathf.Sqrt(best);
    }

    static Vector2 CatmullRom(Vector2 p0, Vector2 p1, Vector2 p2, Vector2 p3, float t)
    {
        float t2 = t * t, t3 = t2 * t;
        return 0.5f * (2f * p1 + (p2 - p0) * t + (2f * p0 - 5f * p1 + 4f * p2 - p3) * t2 + (3f * p1 - p0 - 3f * p2 + p3) * t3);
    }
}

public partial class VoxelWorld
{
    /// Cuts the creek's bed (Creek.cs): along the points (x, bed height, z, the ground there), every column within
    /// BankOut is cut down to the bed, its banks easing back up to the ground.  Only takes ground away.  The chunks
    /// count as touched (saved).  Returns how many voxels went.
    public long CarveCreek(NativeArray<float4> pts)
    {
        var result = new NativeArray<long>(1, Allocator.TempJob);
        new CreekJob { vox = vox, blocks = blocks, top = top, grass = grass, dirty = dirty, pts = pts, origin = origin, result = result }.Run();
        long gone = result[0];
        result.Dispose();
        SolidCount -= gone;
        StartTotal -= gone;
        if (grassTex != null) { grassTex.LoadRawTextureData(grass); grassTex.Apply(false); }
        return gone;
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct CreekJob : IJob
    {
        public NativeArray<byte> vox, grass, dirty;
        [ReadOnly] public NativeArray<int4> blocks;
        public NativeArray<ushort> top;
        [ReadOnly] public NativeArray<float4> pts;
        public float3 origin;
        public NativeArray<long> result;

        public void Execute()
        {
            long gone = 0;
            int reach = (int)math.ceil(Creek.BankOut / Voxel) + 1;
            for (int i = 0; i < pts.Length; i++)
            {
                float4 p = pts[i];
                int cx = (int)math.floor((p.x - origin.x) / Voxel), cz = (int)math.floor((p.z - origin.z) / Voxel);
                for (int z = cz - reach; z <= cz + reach; z++)
                    for (int x = cx - reach; x <= cx + reach; x++)
                    {
                        if (x < Rim + 8 || z < Rim + 8 || x >= NX - Rim - 8 || z >= NZ - Rim - 8) continue;
                        if (blocks[(x >> 5) + CX * (z >> 5)].w != BlockSite) continue;
                        float wx = origin.x + (x + 0.5f) * Voxel, wz = origin.z + (z + 0.5f) * Voxel;
                        float d = math.distance(new float2(wx, wz), new float2(p.x, p.z));
                        if (d > Creek.BankOut) continue;
                        float h = p.y;
                        if (d > Creek.BedHalf)
                        {
                            float t = math.saturate((d - Creek.BedHalf) / (Creek.BankOut - Creek.BedHalf));
                            h += t * t * (3f - 2f * t) * math.max(0f, p.w - p.y + 0.05f);
                        }
                        int lo, hi;
                        int cb = ColBase(blocks, x, z, out lo, out hi);
                        if (cb < 0) continue;
                        int keep = math.clamp(Ground + (int)math.round(h / Voxel), lo + 1, hi - 1);
                        int col = x + NX * z;
                        if (top[col] <= keep) continue;
                        for (int y = keep; y < hi; y++)
                        {
                            if (vox[cb + y] == Air) continue;
                            vox[cb + y] = Air;
                            gone++;
                            Mark(ref dirty, x, y, z);
                        }
                        top[col] = (ushort)keep;
                        if (d < Creek.BedHalf + 0.15f) grass[col] = 0;    // the bed is bare; the banks keep their grass
                    }
            }
            result[0] = gone;
        }
    }
}
