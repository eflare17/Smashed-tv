// The mountain behind the mine, and the road to its top (a first try at the road job: 20 m high).
//
// The mountain stands past the north fence, west of the escape track, on the hillside that already rises there.
// It is about 110 m across and its top is about 20 m above the site's hilltop.  Most of it is a plain solid mesh
// (SiteProps.Hillside), which can't be dug.  Only a strip along the road line is real diggable ground: VoxelWorld
// keeps voxels there, in 2 m columns, and nowhere else outside the site (see VoxelWorld.BuildBlocks).
//
// The road line: it leaves the hilltop just north of the firebreak lane, crosses the fence, and climbs the
// mountain's south face at 1 in 8 in three legs with two switchbacks, then a flat pad at the top.  About 172 m.
//   - the road is 4 m wide (RoadHalf), inside an 8 m wide strip of voxels (StripHalf) about 3 m deep;
//   - the ground starts as the natural mountainside, so some stretches need cutting and some filling.
//
// Everything here is plain arithmetic, so the voxel jobs (Burst) can call the ground recipe too.
using Unity.Mathematics;
using UnityEngine;

/// The natural ground: the site's hill, the hillside past the fence, and the mountain on it.
public static class Mountain
{
    public const float CX = -28f, CZ = 96f;                  // the top of the mountain
    public const float Base = 4.5f, Tall = 20.5f;            // its foot is at about the hilltop's height; its top 20.5 m above that
    public const float R0 = 6f, R1 = 56f;                    // rounded top inside R0, foot at R1
    public const float Fence = 48f;                          // the north fence (the site's edge)

    static float SS(float a, float b, float x) { return math.smoothstep(a, b, x); }

    /// The mountain's height at a distance r from its top: mostly a straight-sided cone, rounded at the top and foot.
    public static float Profile(float r)
    {
        float u = math.saturate((r - R0) / (R1 - R0));
        float p = 0.6f * u + 0.4f * u * u * (3f - 2f * u);
        float h = Base + Tall * (1f - p);
        if (r > R1) h *= 1f - SS(R1, R1 + 10f, r);
        return h;
    }

    /// Small lumps on the mountain's face, so the cut and fill vary.
    public static float Bumps(float x, float z)
    {
        return 0.35f * math.sin(x * 0.21f + 1.3f) * math.sin(z * 0.17f + 0.4f) + 0.2f * math.sin((x + z) * 0.43f);
    }

    /// The mountain on its own (it fades out towards the fence, so it meets the site's hill smoothly).
    public static float ConeY(float x, float z)
    {
        float r = math.distance(new float2(x, z), new float2(CX, CZ));
        float c = Profile(r) + Bumps(x, z) * SS(R1, R1 - 8f, r);
        float west = SS(-40f, -50f, x);                      // west of the site there is no hill at the fence to meet
        c *= SS(Fence - 0.5f, 60f, z) * (1f - west) + SS(Fence, 62f, z) * west;
        return c;
    }

    /// The site's own hill before the quarry was cut (VoxelWorld.GenerateJob's recipe without the cut).
    public static float SiteHill(float x, float z)
    {
        float2 p = new float2(x, z);
        float n1 = noise.snoise(p * 0.035f), n2 = noise.snoise(p * 0.11f);
        float inside = math.min(Fence - math.abs(x), z > 0f ? 99f : Fence - math.abs(z));
        float fade = SS(1.5f, 9f, inside);
        float south = SS(-36f, -19f, z);
        return math.max(0f, (4.5f + 1.1f * n1 + 0.35f * n2) * south * fade);
    }

    /// The site's own hill height at the north fence.
    public static float SiteHillAtEdge(float x)
    {
        float2 p = new float2(x, Fence);
        float n1 = noise.snoise(p * 0.035f), n2 = noise.snoise(p * 0.11f);
        float fade = SS(1.5f, 9f, Fence - math.abs(x));
        return math.max(0f, (4.5f + 1.1f * n1 + 0.35f * n2) * fade);
    }

    public static float TrackCentreX(float z) { return VoxelWorld.TrackX + 1.2f * math.sin(z * 0.09f); }

    /// The hillside past the north fence as it was before the mountain: up about 26 m over 100 m, the track eased level.
    public static float HillsideY(float x, float z)
    {
        float dz = math.max(0f, z - Fence);
        float2 p = new float2(x, z);
        float rise = 26f * SS(0f, 100f, dz) + (2.6f * noise.snoise(p * 0.03f) + 0.6f * noise.snoise(p * 0.12f)) * SS(0f, 14f, dz);
        float y = SiteHillAtEdge(x) + rise;
        float off = math.abs(x - TrackCentreX(z));
        if (off < VoxelWorld.TrackHalf + 2f)
        {
            float level = SiteHillAtEdge(TrackCentreX(z)) + 26f * SS(0f, 100f, dz);
            y = math.lerp(level, y, SS(VoxelWorld.TrackHalf, VoxelWorld.TrackHalf + 2f, off));
        }
        return y;
    }

    /// Past the fence: the hillside, with the mountain standing on it.
    public static float PastFenceY(float x, float z) { return math.max(HillsideY(x, z), ConeY(x, z)); }

    /// Ground anywhere outside the voxel site: the hillside and mountain past the north fence, flat elsewhere.
    public static float OutsideY(float x, float z) { return z > Fence - 0.5f && math.abs(x) < 140f ? PastFenceY(x, z) : 0f; }

    /// The untouched ground anywhere: the site's hill inside the fence (before the quarry), OutsideY beyond it.
    public static float NaturalY(float x, float z)
    {
        return z < Fence && math.abs(x) < Fence ? SiteHill(x, z) : OutsideY(x, z);
    }
}

/// The road line up the mountain, and questions about it: how far along a point is, how far off the line, and
/// what height the finished road should be there (its grade).
public static class MountainRoad
{
    public const float RoadHalf = 2f;                        // the road is 4 m wide
    public const float StripHalf = 4f;                       // inside an 8 m wide strip of diggable ground
    public const float CorridorHalf = 3.2f;                  // how far off the line the dozer may drive
    public const float Slope = 1f / 8f, Climb = 20f;         // 1 in 8 (about 7 degrees), 20 m up
    public const float PadLength = 12f;                      // the flat pad at the top
    public const float Step = 0.5f;                          // the line is kept as points this far apart
    public const int Stretches = 15;                         // the road is judged in this many stretches
    const float HairpinR = 4.6f;                             // the switchbacks: the legs either side are 9.2 m apart
    const float Wobble = 0.45f;                              // the line wanders this much above and below the ground, so there is cut and fill
    static readonly float2 StartAt = new float2(-12f, 42f);  // on the hilltop, just north of the firebreak lane

    static Vector2[] pts;                                    // the line, Step apart
    static float[] along;
    static Vector2 lo, hi;                                   // its bounding box
    public static float Length { get; private set; }
    public static float StartY { get; private set; }         // the grade where it starts (the ground there)
    public static float TopY { get { Ensure(); return StartY + Climb; } }
    public static int Count { get { Ensure(); return pts.Length; } }
    public static Vector2 Point(int i) { Ensure(); return pts[i]; }
    public static float AlongAt(int i) { Ensure(); return along[i]; }
    public static Vector2 Min { get { Ensure(); return lo; } }
    public static Vector2 Max { get { Ensure(); return hi; } }

    static void Ensure() { if (pts == null) Build(); }

    /// The height the finished road should be at this distance along it: 1 in 8 up to the top, then flat.
    public static float GradeAt(float s) { Ensure(); return StartY + Mathf.Min(Climb, Mathf.Max(0f, s) * Slope); }
    /// How steep the road is at this distance along it (a fraction: 0.125 is 1 in 8).
    public static float SlopeAt(float s) { return s < Climb / Slope ? Slope : 0f; }

    /// The point on the line nearest (x, z): how far along the road it is, and how far off the line (+ to the left
    /// going up).  Returns the distance off the line.
    public static float Nearest(float x, float z, out float s, out float off, out Vector2 dir)
    {
        Ensure();
        float best = float.MaxValue; s = 0f; off = 0f; dir = Vector2.up;
        Vector2 p = new Vector2(x, z);
        if (x < lo.x - 30f || z < lo.y - 30f || x > hi.x + 30f || z > hi.y + 30f)
        {
            int k = 0; float bd = float.MaxValue;
            for (int i = 0; i < pts.Length; i += 8) { float d = (pts[i] - p).sqrMagnitude; if (d < bd) { bd = d; k = i; } }
            s = along[k]; dir = (pts[Mathf.Min(k + 1, pts.Length - 1)] - pts[Mathf.Max(k - 1, 0)]).normalized;
            off = 0f;
            return Mathf.Sqrt(bd);
        }
        for (int i = 0; i + 1 < pts.Length; i++)
        {
            Vector2 a = pts[i], ab = pts[i + 1] - a;
            float len2 = ab.sqrMagnitude;
            float u = Mathf.Clamp01(Vector2.Dot(p - a, ab) / len2);
            Vector2 q = a + ab * u;
            float d = (p - q).sqrMagnitude;
            if (d < best)
            {
                best = d;
                s = along[i] + (along[i + 1] - along[i]) * u;
                dir = ab / Mathf.Sqrt(len2);
                Vector2 left = new Vector2(-dir.y, dir.x);
                off = Vector2.Dot(p - q, left);
            }
        }
        // before the start or past the end, the distance runs on along the line
        Vector2 d0 = pts[1] - pts[0];
        if (Vector2.Dot(p - pts[0], d0) < 0f && s <= 0.001f) { float back = (p - pts[0]).magnitude; return back; }
        return Mathf.Sqrt(best);
    }

    public static float DistanceTo(float x, float z) { float s, off; Vector2 d; return Nearest(x, z, out s, out off, out d); }

    /// True on the road itself (within 2 m of the line).
    public static bool OnRoad(float x, float z) { return DistanceTo(x, z) <= RoadHalf; }

    /// Which stretch (0..14) a distance along the road is in.
    public static int StretchOf(float s) { Ensure(); return Mathf.Clamp(Mathf.FloorToInt(s / Length * Stretches), 0, Stretches - 1); }

    // ------------------------------------------------------------------ laying out the line
    // Each leg goes round the mountain at the height the road should be (plus a little wobble), so it climbs at 1 in 8.
    // Going round, it looks along a line in from the foot towards the top for where the natural ground is that high.
    // At each switchback it turns uphill in a half circle; the natural ground rises faster across the turn than the
    // road does, so the line runs a little above the ground going into it (fill) and below it coming out (cut).
    static readonly System.Collections.Generic.List<Vector2> raw = new System.Collections.Generic.List<Vector2>();
    static float rawS;

    static void Add(float x, float z)
    {
        if (raw.Count > 0) rawS += Vector2.Distance(raw[raw.Count - 1], new Vector2(x, z));
        raw.Add(new Vector2(x, z));
    }

    static float RawGrade(float s) { return StartY + Mathf.Min(Climb, s * Slope); }

    static Vector2 Here(float phi, float r) { float a = phi * Mathf.Deg2Rad; return new Vector2(Mountain.CX + r * Mathf.Cos(a), Mountain.CZ + r * Mathf.Sin(a)); }

    /// Along the line in towards the top at angle phi, where the natural ground is `height` high: only looked for
    /// within `reach` of the last radius (the line turns smoothly, so it never needs to look further).
    static float RadiusFor(float phi, float height, float near, float reach)
    {
        float a = phi * Mathf.Deg2Rad, ux = Mathf.Cos(a), uz = Mathf.Sin(a);
        System.Func<float, float> above = r => Mountain.NaturalY(Mountain.CX + ux * r, Mountain.CZ + uz * r) - height;   // the ground rises going in
        float rIn = near - reach, rOut = near + reach;
        if (above(rOut) >= 0f) return rOut;
        if (above(rIn) < 0f) return rIn;
        for (int k = 0; k < 12; k++) { float m = (rIn + rOut) * 0.5f; if (above(m) >= 0f) rIn = m; else rOut = m; }
        return (rIn + rOut) * 0.5f;
    }

    static float SmoothStep(float a, float b, float x) { float t = Mathf.Clamp01((x - a) / (b - a)); return t * t * (3f - 2f * t); }

    static void Leg(ref float phi, ref float r, float dirSign, float length, float bStart, float bEnd, bool toTop)
    {
        const int n = 1500;
        const float ramp = 12f;
        const float turnIn = 0.08f;                  // at most this much in or out per step (about 35 degrees off going round)
        float dphi = dirSign * 200f / n, s0 = rawS, rPrev = r;
        for (int i = 0; i <= n; i++)
        {
            float ds = rawS - s0, rem = length - ds;
            float b = Wobble * Mathf.Sin(2f * Mathf.PI * rawS / 26f);
            if (ds < ramp) b = bStart + (b - bStart) * SmoothStep(0f, ramp, ds);
            if (rem < ramp) b = b + (bEnd - b) * SmoothStep(ramp, 0f, rem);
            float rr = i == 0 ? r : RadiusFor(phi, RawGrade(rawS) + b, rPrev, turnIn);
            rPrev = rr;
            Vector2 q = Here(phi, rr);
            Add(q.x, q.y);
            if (toTop ? RawGrade(rawS) >= StartY + Climb : ds >= length) break;
            phi += dphi;
        }
        r = rPrev;
    }

    static float Hairpin(float phi, float rOut, float turn)
    {
        float a = phi * Mathf.Deg2Rad, ux = Mathf.Cos(a), uz = Mathf.Sin(a), tx = -uz * turn, tz = ux * turn;
        float cx = Mountain.CX + (rOut - HairpinR) * ux, cz = Mountain.CZ + (rOut - HairpinR) * uz;
        for (int i = 1; i <= 40; i++)
        {
            float th = Mathf.PI * i / 40f;
            Add(cx + HairpinR * (Mathf.Cos(th) * ux + Mathf.Sin(th) * tx), cz + HairpinR * (Mathf.Cos(th) * uz + Mathf.Sin(th) * tz));
        }
        return rOut - 2f * HairpinR;
    }

    /// The line through `src`, with points `step` apart along it.
    static System.Collections.Generic.List<Vector2> Even(System.Collections.Generic.List<Vector2> src, float step)
    {
        var outPts = new System.Collections.Generic.List<Vector2>();
        float total = 0f;
        var cum = new float[src.Count];
        for (int i = 1; i < src.Count; i++) { total += Vector2.Distance(src[i - 1], src[i]); cum[i] = total; }
        int j = 0;
        for (float s = 0f; s <= total + 1e-4f; s += step)
        {
            while (j + 1 < src.Count - 1 && cum[j + 1] < s) j++;
            float u = Mathf.Clamp01((s - cum[j]) / Mathf.Max(cum[j + 1] - cum[j], 1e-5f));
            outPts.Add(Vector2.Lerp(src[j], src[j + 1], u));
        }
        return outPts;
    }

    public static float BuildMs { get; private set; }

    static void Build()
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        raw.Clear(); rawS = 0f;
        StartY = Mountain.NaturalY(StartAt.x, StartAt.y);
        Add(StartAt.x, StartAt.y);
        float phi = -73f, r = 50f;
        Vector2 h = Here(phi, r);
        Leg(ref phi, ref r, -1f, 60f, Mountain.NaturalY(h.x, h.y) - RawGrade(rawS), -1f, false);   // leg 1, west
        r = Hairpin(phi, r, -1f);
        h = Here(phi, r);
        Leg(ref phi, ref r, 1f, 55f, Mountain.NaturalY(h.x, h.y) - RawGrade(rawS), -1f, false);    // leg 2, back east
        r = Hairpin(phi, r, 1f);
        h = Here(phi, r);
        Leg(ref phi, ref r, -1f, 999f, Mountain.NaturalY(h.x, h.y) - RawGrade(rawS), 0f, true);    // leg 3, west to the top

        // Smooth out the small wiggles from following the ground, then measure it again for real and trim it where it
        // has climbed its 20 m.  The pad carries straight on from there, level.
        var line = Even(raw, 0.25f);
        for (int pass = 0; pass < 12; pass++)
            for (int i = 1; i + 1 < line.Count; i++) line[i] = Vector2.Lerp(line[i], (line[i - 1] + line[i + 1]) * 0.5f, 0.5f);
        float climbLen = Climb / Slope, sum = 0f;
        int cut = line.Count - 1;
        for (int i = 1; i < line.Count; i++) { sum += Vector2.Distance(line[i - 1], line[i]); if (sum >= climbLen) { cut = i; break; } }
        line.RemoveRange(cut + 1, line.Count - cut - 1);
        Vector2 e1 = line[line.Count - 1], dir = (e1 - line[line.Count - 9]).normalized;
        for (int k = 1; k <= Mathf.RoundToInt(PadLength / 0.25f); k++) line.Add(e1 + dir * (0.25f * k));
        var even = Even(line, Step);
        pts = even.ToArray();
        along = new float[pts.Length];
        for (int i = 1; i < pts.Length; i++) along[i] = along[i - 1] + Vector2.Distance(pts[i - 1], pts[i]);
        Length = along[along.Length - 1];
        lo = new Vector2(float.MaxValue, float.MaxValue); hi = new Vector2(float.MinValue, float.MinValue);
        foreach (var q in pts) { lo = Vector2.Min(lo, q); hi = Vector2.Max(hi, q); }
        raw.Clear();
        BuildMs = (float)watch.Elapsed.TotalMilliseconds;
    }
}
