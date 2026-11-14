// Diggable ground made of 6.25 cm voxels, the same size as the bulldozer's.
// A 96 m x 96 m site, 14 m tall (4 m below the work floor, 10 m above for the hill and heaps), drawn in 2 m chunks.
// The ground is shaped as a quarry cut into a hillside: see GenerateJob.
// Only chunks that change get rebuilt.  The heavy loops are Burst jobs.
using System.Runtime.InteropServices;
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

public partial class VoxelWorld : MonoBehaviour
{
    public const int NX = 1536, NY = 224, NZ = 1536;        // voxels
    public const int CS = 32, CX = NX / CS, CY = NY / CS, CZ = NZ / CS;
    public const int Ground = 64;                           // voxel layer that sits at world height 0 (4 m to dig down, 10 m of hill and air above)
    public const float Voxel = 0.0625f;
    public const int Rim = 2;                               // untouchable border, so you can't dig out of the patch
    /// How far from the middle a machine may drive (metres), keeping its blade and its dirt inside the patch.
    public const float DriveLimit = NX / 2 * Voxel - 6.5f;   // leaves the heap in front of the blade room to sit

    // materials.  6 and up are loose: they can be pushed, and they slump into heaps
    public const byte Air = 0, Soil = 1, Clay = 2, Rock = 3, Quartz = 4, Gold = 5,
                      LooseSoil = 6, LooseClay = 7, LooseRock = 8, LooseQuartz = 9, LooseGold = 10;

    // Landmarks of the quarry, in metres (x right, z ahead of where the dozer starts facing).
    public const float PortalX = 9f, PortalZ = 11.6f;       // the mine entrance in the north face
    public const float TunnelLength = 15f, TunnelHalfWidth = 1.6f, TunnelHeight = 2.6f;
    public const float RoadX = -4f, RoadHalfWidth = 5.5f;   // the way out to the south
    public const float RockPadX = 16f, RockPadZ = -8f;      // a bare rock patch on the floor, for ripping

    public static VoxelWorld Instance { get; private set; }

    public Material material;
    public int maxRemeshPerFrame = 64;

    // running totals, for the HUD and tests
    public string LossNote;                                  // where dirt was first lost, for tests
    public long TotalCut { get; private set; }               // voxels the blade has moved (counts re-pushes)
    public long TotalLost { get; private set; }              // voxels that had nowhere to go (should stay 0)
    public long TotalRipped { get; private set; }            // voxels broken up by the ripper

    // Volume bookkeeping.  Dirt is never made or destroyed: SolidCount + LoadVoxels always equals StartTotal.
    public long SolidCount { get; private set; }             // voxels of ground in the patch right now (kept up to date)
    public long StartTotal { get; private set; }             // what it was at the start
    public int LoadVoxels { get; private set; }              // dirt that is not ground right now: moving clods plus the blade's small tally
    public int BermVoxels { get; private set; }              // the moving clods on their own
    int carriedOnBlade;                                      // the tally: cut voxels not yet enough to make a whole clod
    public const float VoxelVolume = Voxel * Voxel * Voxel;
    /// Roughly what the blade can push: a wedge as tall and wide as the blade, sloping away at 35 degrees.
    public const int BladeCapacityVoxels = 70 * 28 * 40 / 2;
    public int LastRemeshChunks { get; private set; }
    public float LastRemeshMs { get; private set; }
    public int MaxRemeshChunks { get; private set; }
    public float MaxRemeshMs { get; private set; }

    // How long each part of the dirt work takes, in milliseconds: [0] blade cut, [1] clods, [2] slump, [3] redraw ground, [4] draw clods.
    // Avg is smoothed, Max is the worst seen.
    public readonly float[] MsAvg = new float[5], MsMax = new float[5];
    public static readonly string[] MsNames = { "cut", "clods", "slump", "ground", "draw" };
    readonly System.Diagnostics.Stopwatch watch = new System.Diagnostics.Stopwatch();

    void Tic() { watch.Restart(); }
    void Toc(int i)
    {
        float ms = (float)watch.Elapsed.TotalMilliseconds;
        MsAvg[i] = Mathf.Lerp(MsAvg[i], ms, 0.05f);
        if (ms > MsMax[i]) MsMax[i] = ms;
    }
    public void ResetTimings() { for (int i = 0; i < 5; i++) { MsAvg[i] = 0f; MsMax[i] = 0f; } }

    NativeArray<byte> vox;                                   // index = y + NY * (x + NX * z)
    NativeArray<ushort> top;                                 // per column: highest solid voxel + 1
    NativeArray<byte> dirty;                                 // per chunk
    NativeArray<int> dxs, dzs;                               // neighbour offsets, for the jobs
    NativeArray<int> bladeLoad;                              // cut dirt on the blade, counted per material
    NativeArray<byte> grass;                                 // per column: how grassy the untouched surface is (0 = bare or worked)
    Texture2D grassTex;
    float grassTimer;
    MeshFilter[] chunkFilters;
    Vector3 origin;                                          // world position of the corner of voxel (0, 0, 0)
    int frame;

    public struct SweepResult { public int cut, hard, placed, spilled, berm; }

    [StructLayout(LayoutKind.Sequential)]
    struct VVert { public float3 pos; public float3 normal; public Color32 color; }

    static int Idx(int x, int y, int z) { return y + NY * (x + NX * z); }

    void Awake()
    {
        Instance = this;
        origin = new Vector3(-NX / 2 * Voxel, -Ground * Voxel, -NZ / 2 * Voxel);
        vox = new NativeArray<byte>(NX * NY * NZ, Allocator.Persistent);
        top = new NativeArray<ushort>(NX * NZ, Allocator.Persistent);
        dirty = new NativeArray<byte>(CX * CY * CZ, Allocator.Persistent);
        chunkFilters = new MeshFilter[CX * CY * CZ];
        dxs = new NativeArray<int>(DXs, Allocator.Persistent);
        dzs = new NativeArray<int>(DZs, Allocator.Persistent);
        bladeLoad = new NativeArray<int>(16, Allocator.Persistent);
        grass = new NativeArray<byte>(NX * NZ, Allocator.Persistent);
        InitDirt();
        InitHand();

        new GenerateJob { vox = vox, top = top, grass = grass }.Schedule(NX * NZ, 256).Complete();
        grassTex = new Texture2D(NX, NZ, TextureFormat.R8, false, true) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
        grassTex.LoadRawTextureData(grass);
        grassTex.Apply(false);
        Shader.SetGlobalTexture("_GrassTex", grassTex);
        Shader.SetGlobalVector("_SiteRect", new Vector4(origin.x, origin.z, 1f / (NX * Voxel), 1f / (NZ * Voxel)));
        for (int i = 0; i < dirty.Length; i++) dirty[i] = 1;
        for (int pass = 0; pass < 200; pass++)               // draw the whole patch once, a batch of chunks at a time
        {
            Remesh(512);
            if (LastRemeshChunks == 0) break;
        }
        MaxRemeshChunks = 0; MaxRemeshMs = 0f;
        SolidCount = StartTotal = CountSolid();
        ResetTimings();
        Time.maximumDeltaTime = 0.05f;                       // if a frame runs long, don't pile up catch-up physics steps
    }

    void OnDestroy()
    {
        if (vox.IsCreated) vox.Dispose();
        if (top.IsCreated) top.Dispose();
        if (dirty.IsCreated) dirty.Dispose();
        if (dxs.IsCreated) dxs.Dispose();
        if (dzs.IsCreated) dzs.Dispose();
        if (bladeLoad.IsCreated) bladeLoad.Dispose();
        if (grass.IsCreated) grass.Dispose();
        DisposeDirt();
        DisposeHand();
        if (Instance == this) Instance = null;
    }

    void LateUpdate()
    {
        frame++;
        Tic(); Remesh(maxRemeshPerFrame); Toc(3);
        grassTimer -= Time.unscaledDeltaTime;
        if (grassTimer <= 0f && grassTex != null)             // show where the grass has been worn off, a few times a second
        {
            grassTimer = 0.15f;
            grassTex.LoadRawTextureData(grass);
            grassTex.Apply(false);
        }
        Tic(); DrawDirt(); Toc(4);
    }

    // ------------------------------------------------------------------ queries
    /// Ground height in metres at a world position (average of a small patch). 0 outside the patch.
    public float HeightAt(float wx, float wz)
    {
        int ix = Mathf.FloorToInt((wx - origin.x) / Voxel), iz = Mathf.FloorToInt((wz - origin.z) / Voxel);
        if (ix < 4 || iz < 4 || ix >= NX - 4 || iz >= NZ - 4) return 0f;
        int sum = 0;
        for (int dz = -3; dz <= 3; dz += 3)
            for (int dx = -3; dx <= 3; dx += 3)
                sum += top[(ix + dx) + NX * (iz + dz)];
        return (sum / 9f - Ground) * Voxel;
    }

    /// Highest ground in a box of columns, in metres.  Used by tests to find the heap.
    public float MaxHeightIn(float wx0, float wz0, float wx1, float wz1)
    {
        int x0 = Mathf.Clamp(Mathf.FloorToInt((wx0 - origin.x) / Voxel), 0, NX - 1), x1 = Mathf.Clamp(Mathf.FloorToInt((wx1 - origin.x) / Voxel), 0, NX - 1);
        int z0 = Mathf.Clamp(Mathf.FloorToInt((wz0 - origin.z) / Voxel), 0, NZ - 1), z1 = Mathf.Clamp(Mathf.FloorToInt((wz1 - origin.z) / Voxel), 0, NZ - 1);
        int best = 0;
        for (int z = z0; z <= z1; z++) for (int x = x0; x <= x1; x++) best = Mathf.Max(best, top[x + NX * z]);
        return (best - Ground) * Voxel;
    }

    /// The tallest column in the whole patch: its height in metres and where it is.  For tests.
    public float HighestPoint(out Vector3 where)
    {
        int best = 0, bi = 0;
        for (int i = 0; i < top.Length; i++) if (top[i] > best) { best = top[i]; bi = i; }
        where = new Vector3(origin.x + (bi % NX + 0.5f) * Voxel, (best - Ground) * Voxel, origin.z + (bi / NX + 0.5f) * Voxel);
        return (best - Ground) * Voxel;
    }

    public long CountSolid()
    {
        var result = new NativeArray<long>(1, Allocator.TempJob);
        new CountJob { vox = vox, result = result }.Run();
        long n = result[0];
        result.Dispose();
        return n;
    }

    // ------------------------------------------------------------------ digging
    /// One step of the blade: everything soft or loose inside the blade's box (its real, rotated footprint)
    /// is cut out of the ground and becomes loose clods, right where it was cut.  Nothing is placed anywhere.
    /// What happens to the clods next is up to StepDirt.  Hard rock is left and counted.
    /// boxMin / boxMax are in the blade's own space; travel is how far the blade moved this step.
    public SweepResult BladeSweep(Matrix4x4 bladeToWorld, Vector3 boxMin, Vector3 boxMax, Vector3 travel, float dt)
    {
        Tic();
        var result = new NativeArray<int>(8, Allocator.TempJob);
        new BladeSweepJob
        {
            vox = vox, top = top, dirty = dirty, load = bladeLoad, result = result, grass = grass,
            bladeToWorld = bladeToWorld, worldToBlade = bladeToWorld.inverse,
            boxMin = boxMin, boxMax = boxMax, origin = origin, seed = frame,
            bladeVel = travel / Mathf.Max(dt, 1e-4f),
            cPos = cPos, cVel = cVel, cRot = cRot, cMat = cMat, cCnt = cCnt, cRest = cRest, cAge = cAge, cCount = cCount,
        }.Run();
        var r = new SweepResult { cut = result[0], hard = result[1] };
        int spawned = result[2];
        result.Dispose();
        TotalCut += r.cut;
        SolidCount -= r.cut;
        int carried = 0;
        for (int i = 0; i < bladeLoad.Length; i++) carried += bladeLoad[i];
        carriedOnBlade = carried;
        ClodCount = cCount[0];
        LoadVoxels = carried + ClodVoxelsInFlight + spawned * ClodVoxels + ShovelVoxels + CartVoxels;
        Toc(0);
        return r;
    }

    /// The ripper tears up everything firm within radius of each point: rock, clay and soil alike.
    /// It does not just mark it broken.  The material is ripped out of the ground and thrown up as loose
    /// clods (rubble), leaving a furrow, and anything left hanging over the furrow drops into it.
    /// Returns how many voxels were torn out.
    public int Rip(Vector3[] points, float radius, Vector3 machineVelocity)
    {
        Tic();
        var pts = new NativeArray<float3>(points.Length, Allocator.TempJob);
        for (int i = 0; i < points.Length; i++) pts[i] = points[i];
        var result = new NativeArray<int>(1, Allocator.TempJob);
        new RipJob
        {
            vox = vox, top = top, dirty = dirty, load = bladeLoad, grass = grass, points = pts, radius = radius, origin = origin,
            result = result, seed = frame, machineVel = machineVelocity,
            cPos = cPos, cVel = cVel, cRot = cRot, cMat = cMat, cCnt = cCnt, cRest = cRest, cAge = cAge, cCount = cCount,
        }.Run();
        int n = result[0];
        pts.Dispose(); result.Dispose();
        TotalRipped += n;
        SolidCount -= n;
        int carried = 0;
        for (int i = 0; i < bladeLoad.Length; i++) carried += bladeLoad[i];
        carriedOnBlade = carried;
        ClodCount = cCount[0];
        Toc(0);
        return n;
    }

    /// Lets loose dirt near a point slide down until no slope is steeper than about 45 degrees.
    public void Slump(Vector3 centre, float radius, int iterations)
    {
        int x0 = Mathf.FloorToInt((centre.x - radius - origin.x) / Voxel), x1 = Mathf.FloorToInt((centre.x + radius - origin.x) / Voxel);
        int z0 = Mathf.FloorToInt((centre.z - radius - origin.z) / Voxel), z1 = Mathf.FloorToInt((centre.z + radius - origin.z) / Voxel);
        Tic();
        int edge = Rim + 3;                                   // the job looks three columns out
        new SlumpJob
        {
            vox = vox, top = top, dirty = dirty, grass = grass, iterations = iterations, seed = frame, DX = dxs, DZ = dzs,
            x0 = Mathf.Clamp(x0, edge, NX - 1 - edge), x1 = Mathf.Clamp(x1, edge, NX - 1 - edge),
            z0 = Mathf.Clamp(z0, edge, NZ - 1 - edge), z1 = Mathf.Clamp(z1, edge, NZ - 1 - edge),
        }.Run();
        Toc(2);
    }

    // ------------------------------------------------------------------ drawing
    void Remesh(int budget)
    {
        var list = new NativeList<int>(64, Allocator.Temp);
        for (int i = 0; i < dirty.Length && list.Length < budget; i++)
            if (dirty[i] != 0) { list.Add(i); dirty[i] = 0; }
        LastRemeshChunks = list.Length;
        if (list.Length == 0) { LastRemeshMs = 0f; list.Dispose(); return; }

        float t0 = Time.realtimeSinceStartup;
        int n = list.Length;
        var handles = new NativeArray<JobHandle>(n, Allocator.Temp);
        var verts = new NativeList<VVert>[n];
        var tris = new NativeList<int>[n];
        for (int i = 0; i < n; i++)
        {
            int c = list[i];
            verts[i] = new NativeList<VVert>(1024, Allocator.TempJob);
            tris[i] = new NativeList<int>(1536, Allocator.TempJob);
            handles[i] = new MeshJob
            {
                vox = vox, verts = verts[i], tris = tris[i], origin = origin,
                cx = c % CX, cy = (c / CX) % CY, cz = c / (CX * CY),
            }.Schedule();
        }
        JobHandle.CompleteAll(handles);
        for (int i = 0; i < n; i++)
        {
            ApplyMesh(list[i], verts[i], tris[i]);
            verts[i].Dispose(); tris[i].Dispose();
        }
        handles.Dispose(); list.Dispose();
        LastRemeshMs = (Time.realtimeSinceStartup - t0) * 1000f;
        if (LastRemeshMs > MaxRemeshMs) MaxRemeshMs = LastRemeshMs;
        if (LastRemeshChunks > MaxRemeshChunks) MaxRemeshChunks = LastRemeshChunks;
    }

    static readonly VertexAttributeDescriptor[] Layout =
    {
        new VertexAttributeDescriptor(VertexAttribute.Position, VertexAttributeFormat.Float32, 3),
        new VertexAttributeDescriptor(VertexAttribute.Normal, VertexAttributeFormat.Float32, 3),
        new VertexAttributeDescriptor(VertexAttribute.Color, VertexAttributeFormat.UNorm8, 4),
    };

    void ApplyMesh(int c, NativeList<VVert> verts, NativeList<int> tris)
    {
        var mf = chunkFilters[c];
        if (verts.Length == 0)
        {
            if (mf != null) mf.gameObject.SetActive(false);
            return;
        }
        int cx = c % CX, cy = (c / CX) % CY, cz = c / (CX * CY);
        if (mf == null)
        {
            var go = new GameObject("Chunk " + cx + " " + cy + " " + cz);
            go.transform.SetParent(transform, false);
            mf = go.AddComponent<MeshFilter>();
            go.AddComponent<MeshRenderer>().sharedMaterial = material;
            var m = new Mesh();
            m.MarkDynamic();
            mf.sharedMesh = m;
            chunkFilters[c] = mf;
        }
        mf.gameObject.SetActive(true);
        var mesh = mf.sharedMesh;
        mesh.Clear();
        mesh.SetVertexBufferParams(verts.Length, Layout);
        mesh.SetVertexBufferData(verts.AsArray(), 0, 0, verts.Length);
        mesh.SetIndexBufferParams(tris.Length, IndexFormat.UInt32);
        mesh.SetIndexBufferData(tris.AsArray(), 0, 0, tris.Length);
        mesh.subMeshCount = 1;
        mesh.SetSubMesh(0, new SubMeshDescriptor(0, tris.Length), MeshUpdateFlags.DontRecalculateBounds);
        float size = CS * Voxel;
        mesh.bounds = new Bounds(origin + new Vector3((cx + 0.5f) * size, (cy + 0.5f) * size, (cz + 0.5f) * size), Vector3.one * size);
    }

    // ------------------------------------------------------------------ jobs
    static void Mark(ref NativeArray<byte> dirty, int x, int y, int z)
    {
        int cx = x >> 5, cy = y >> 5, cz = z >> 5;
        dirty[cx + CX * (cy + CY * cz)] = 1;
        int lx = x & 31, ly = y & 31, lz = z & 31;
        if (lx == 0 && cx > 0) dirty[cx - 1 + CX * (cy + CY * cz)] = 1;
        if (lx == 31 && cx < CX - 1) dirty[cx + 1 + CX * (cy + CY * cz)] = 1;
        if (ly == 0 && cy > 0) dirty[cx + CX * (cy - 1 + CY * cz)] = 1;
        if (ly == 31 && cy < CY - 1) dirty[cx + CX * (cy + 1 + CY * cz)] = 1;
        if (lz == 0 && cz > 0) dirty[cx + CX * (cy + CY * (cz - 1))] = 1;
        if (lz == 31 && cz < CZ - 1) dirty[cx + CX * (cy + CY * (cz + 1))] = 1;
    }

    /// How much a column "resists" being piled on, in voxels: clumps of a few blocks share a value,
    /// which is what makes a heap lumpy instead of a smooth ramp.
    static float Lump(int x, int z)
    {
        uint a = math.hash(new int2(x >> 1, z >> 1)) & 255u;
        uint b = math.hash(new int2(x >> 3, z >> 3)) & 255u;
        return a * (1.0f / 255f) + b * (2.0f / 255f);
    }

    static byte Loosen(byte m)
    {
        switch (m)
        {
            case Soil: return LooseSoil;
            case Clay: return LooseClay;
            case Rock: return LooseRock;
            case Quartz: return LooseQuartz;
            case Gold: return LooseGold;
            default: return m;
        }
    }

    /// Builds the starting ground one column at a time, as a quarry cut into a hillside:
    ///  - a hill about 4.5 m high over the northern part of the site, fading to flat ground in the south
    ///    and at the edges (so it meets the plain ground outside);
    ///  - an oval work floor cut into it, with the cut stepping up in benches so each bench shows the layer
    ///    it was cut through: grassed topsoil on top, orange clay under it, grey rock under that;
    ///  - a sheer face where the mine entrance is, with a tunnel running in behind it;
    ///  - a road cut out through the south side;
    ///  - dust and clay laid over the work floor so there is something to push, one bare rock patch for
    ///    ripping, and rock spires standing on the floor;
    ///  - a quartz seam with gold flecks through the rock.
    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct GenerateJob : IJobParallelFor
    {
        [NativeDisableParallelForRestriction] public NativeArray<byte> vox;
        public NativeArray<ushort> top;
        public NativeArray<byte> grass;

        static float Spire(float2 p, float cx, float cz, float r, float h)
        {
            float d = math.distance(p, new float2(cx, cz)) / r;
            return d >= 1f ? 0f : h * math.pow(1f - d, 1.3f);
        }

        public void Execute(int i)
        {
            int x = i % NX, z = i / NX;
            float wx = (x - NX / 2) * Voxel, wz = (z - NZ / 2) * Voxel;
            float2 p = new float2(wx, wz);
            float n1 = noise.snoise(p * 0.035f), n2 = noise.snoise(p * 0.11f), n3 = noise.snoise(p * 0.5f);

            // the hill as it was before anyone dug it
            float inside = math.min(NX / 2 * Voxel - math.abs(wx), NZ / 2 * Voxel - math.abs(wz));
            float fade = math.smoothstep(1.5f, 9f, inside);
            float south = math.smoothstep(-36f, -19f, wz);
            float hill = math.max(0f, (4.5f + 1.1f * n1 + 0.35f * n2) * south * fade);

            // the quarry cut
            float d = (math.length((p - new float2(0f, -6f)) / new float2(24f, 19f)) - 1f) * 20f + n2 * 1.1f;   // metres outside the floor's edge
            bool road = wz < -18f && math.abs(wx - RoadX) < RoadHalfWidth + n2 * 0.5f;
            bool portalFace = math.abs(wx - PortalX) < 3.4f && wz > 0f;
            float cut;
            if (d <= 0f || road) cut = 0f;
            else if (portalFace) cut = 1000f;                                    // a sheer face for the mine entrance
            else cut = (math.floor(d / 3.2f) + 1f) * 1.5f;                       // benches: 1.5 m up, 3.2 m wide
            bool floor = (d <= 0f || road) && hill > 0.05f;
            float ground = math.min(hill, cut) + (floor ? 0.05f * n3 : 0f);

            // rock spires standing on the floor and at the foot of the face
            float spire = 0f;
            spire = math.max(spire, Spire(p, -9f, 8.5f, 2.4f, 3.4f));
            spire = math.max(spire, Spire(p, -3.5f, 10.5f, 1.8f, 2.4f));
            spire = math.max(spire, Spire(p, 2.5f, 9.5f, 2.0f, 2.9f));
            spire = math.max(spire, Spire(p, -17f, 1f, 2.2f, 2.6f));
            spire = math.max(spire, Spire(p, 17.5f, 3f, 1.7f, 1.9f));
            spire = math.max(spire, Spire(p, -13.5f, -13f, 1.5f, 1.3f));
            spire = math.max(spire, Spire(p, 20f, -17f, 1.6f, 1.5f));
            spire *= 0.8f + 0.35f * n3;
            if (spire < 0.12f) spire = 0f;

            int nat = Ground + (int)math.round(hill / Voxel);                    // where the surface was, for the layers
            int baseSurf = math.clamp(Ground + (int)math.round(ground / Voxel), 8, NY - 48);
            int surf = math.clamp(baseSurf + (int)math.round(spire / Voxel), 8, NY - 44);
            float soil = 7f + n3 * 3f;
            float clay = 30f + noise.snoise(p * 0.17f) * 7f;
            bool rockPad = floor && math.distance(p, new float2(RockPadX, RockPadZ)) < 5.5f + n2 * 1.2f;
            bool fill = floor && hill > 0.5f && !rockPad;                         // dust and clay over the cut floor

            // the tunnel behind the mine entrance
            bool tunnel = math.abs(wx - PortalX) < TunnelHalfWidth && wz > PortalZ - 1.2f && wz < PortalZ + TunnelLength;
            int tunnelTop = Ground + (int)(TunnelHeight / Voxel);

            int b = i * NY;
            for (int y = 0; y < NY; y++)
            {
                byte m;
                if (y >= surf) m = Air;
                else if (tunnel && y >= Ground && y < tunnelTop && surf - tunnelTop >= 6)
                {
                    // The cave-in.  A few metres in, the roof came down years ago: rubble slopes up from the floor,
                    // fills the tunnel to the roof for a stretch, and slopes away again on the far side.
                    // It is loose rock and dirt with solid boulders through it.
                    float along = wz - PortalZ;
                    float fillTo = along < 2.6f ? 0f : along < 4.4f ? (along - 2.6f) / 1.8f : along < 8.2f ? 1.2f : along < 9.8f ? (9.8f - along) / 1.6f * 1.2f : 0f;
                    fillTo *= 0.9f + 0.14f * n3;
                    float up = (y - Ground + 0.5f) * Voxel / TunnelHeight;
                    if (up >= fillTo) m = Air;
                    else
                    {
                        float wy2 = (y - Ground) * Voxel;
                        float boulder = noise.snoise(new float3(wx, wy2, wz) * 1.1f);
                        uint r = math.hash(new int3(x >> 1, y >> 1, z >> 1)) % 100u;
                        m = boulder > 0.5f ? Rock : r < 60u ? LooseRock : r < 84u ? LooseClay : LooseSoil;
                    }
                }
                else
                {
                    int dn = nat - y;                                            // how far under the old surface
                    m = dn <= soil ? Soil : dn <= soil + clay ? Clay : Rock;
                    if (y >= baseSurf || rockPad) m = Rock;                      // spires, and the bare rock patch
                    else if (fill)
                    {
                        int dc = baseSurf - y;
                        if (dc <= 6) m = Soil; else if (dc <= 22 && m == Rock) m = Clay;
                    }
                    if (m == Rock)
                    {
                        float wy = (y - Ground) * Voxel;
                        float seam = wx * 0.55f - wy * 0.8f - wz * 0.2f - 8.5f + noise.snoise(new float3(wx, wy, wz) * 0.4f) * 0.25f;
                        if (math.abs(seam) < 0.13f)
                            m = (math.hash(new int3(x, y, z)) % 1000u) < 45u ? Gold : Quartz;
                    }
                }
                vox[b + y] = m;
            }
            top[i] = (ushort)surf;

            // grass grows where the old surface is still there: the hilltop, the top bench and the open ground to the south
            bool untouched = spire == 0f && !floor && baseSurf >= nat - 1;
            bool patchy = noise.snoise(p * 0.07f) > -0.45f || hill > 1f;
            grass[i] = (byte)(untouched && patchy ? 150 + (int)(math.hash(new int2(x >> 1, z >> 1)) % 100u) : 0);
        }
    }

    /// Turns one 32 x 32 x 32 chunk into a mesh, merging flat runs of the same material into big quads.
    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct MeshJob : IJob
    {
        [ReadOnly] public NativeArray<byte> vox;
        public NativeList<VVert> verts;
        public NativeList<int> tris;
        public float3 origin;
        public int cx, cy, cz;

        byte Get(int3 p)
        {
            if (p.y >= NY) return Air;
            if (p.x < 0 || p.y < 0 || p.z < 0 || p.x >= NX || p.z >= NZ) return Rock;   // nothing to see beyond the patch
            return vox[p.y + NY * (p.x + NX * p.z)];
        }

        public void Execute()
        {
            var mask = new NativeArray<byte>(CS * CS, Allocator.Temp);
            int3 b = new int3(cx, cy, cz) * CS;
            for (int d = 0; d < 3; d++)
            {
                int u = (d + 1) % 3, v = (d + 2) % 3;
                for (int side = 0; side < 2; side++)
                {
                    int3 dir = int3.zero; dir[d] = side == 1 ? 1 : -1;
                    float3 normal = dir;
                    for (int i = 0; i < CS; i++)
                    {
                        bool any = false;
                        for (int vv = 0; vv < CS; vv++)
                            for (int uu = 0; uu < CS; uu++)
                            {
                                int3 p = b; p[d] += i; p[u] += uu; p[v] += vv;
                                byte a = vox[p.y + NY * (p.x + NX * p.z)];
                                byte m = (a != Air && Get(p + dir) == Air) ? a : Air;
                                mask[uu + vv * CS] = m;
                                any |= m != Air;
                            }
                        if (!any) continue;
                        for (int vv = 0; vv < CS; vv++)
                            for (int uu = 0; uu < CS;)
                            {
                                byte m = mask[uu + vv * CS];
                                if (m == Air) { uu++; continue; }
                                int w = 1;
                                while (uu + w < CS && mask[uu + w + vv * CS] == m) w++;
                                int h = 1;
                                bool grow = true;
                                while (vv + h < CS && grow)
                                {
                                    for (int k = 0; k < w; k++)
                                        if (mask[uu + k + (vv + h) * CS] != m) { grow = false; break; }
                                    if (grow) h++;
                                }
                                for (int j = 0; j < h; j++)
                                    for (int k = 0; k < w; k++) mask[uu + k + (vv + j) * CS] = Air;

                                float3 p0 = b; p0[d] += i + side; p0[u] += uu; p0[v] += vv;
                                float3 du = float3.zero; du[u] = w;
                                float3 dv = float3.zero; dv[v] = h;
                                int n = verts.Length;
                                var col = new Color32(m, 0, 0, 255);
                                verts.Add(new VVert { pos = origin + p0 * Voxel, normal = normal, color = col });
                                verts.Add(new VVert { pos = origin + (p0 + du) * Voxel, normal = normal, color = col });
                                verts.Add(new VVert { pos = origin + (p0 + du + dv) * Voxel, normal = normal, color = col });
                                verts.Add(new VVert { pos = origin + (p0 + dv) * Voxel, normal = normal, color = col });
                                if (side == 1) { tris.Add(n); tris.Add(n + 1); tris.Add(n + 2); tris.Add(n); tris.Add(n + 2); tris.Add(n + 3); }
                                else { tris.Add(n); tris.Add(n + 2); tris.Add(n + 1); tris.Add(n); tris.Add(n + 3); tris.Add(n + 2); }
                                uu += w;
                            }
                    }
                }
            }
            mask.Dispose();
        }
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct BladeSweepJob : IJob
    {
        public NativeArray<byte> vox;
        public NativeArray<ushort> top;
        public NativeArray<byte> dirty;
        public NativeArray<int> load;                        // cut voxels not yet made into a clod, per material
        public NativeArray<byte> grass;
        public NativeArray<int> result;                      // cut, hard, clods made
        public float4x4 bladeToWorld, worldToBlade;
        public float3 boxMin, boxMax, origin, bladeVel;
        public int seed;
        public NativeArray<float3> cPos, cVel;
        public NativeArray<quaternion> cRot;
        public NativeArray<byte> cMat, cCnt;
        public NativeArray<float> cRest, cAge;
        public NativeArray<int> cCount;
        int made;

        /// One voxel comes out of the ground.  Every eighth one of a material becomes a clod, where it was cut.
        void Cut(byte loose, int x, int y, int z)
        {
            load[loose]++;
            if (load[loose] < ClodVoxels || cCount[0] >= MaxClods) return;
            load[loose] -= ClodVoxels;
            Spawn(origin + (new float3(x, y, z) + 0.5f) * Voxel, loose);
        }

        void Spawn(float3 at, byte loose)
        {
            int n = cCount[0]++;
            uint h = math.hash(new int2(n, seed));
            at += (new float3(h & 255u, (h >> 8) & 255u, (h >> 16) & 255u) / 255f - 0.5f) * (Voxel * 2.5f);
            cPos[n] = at; cVel[n] = bladeVel; cRot[n] = quaternion.identity;
            cMat[n] = loose; cCnt[n] = ClodVoxels; cRest[n] = 0f; cAge[n] = 0f;
            made++;
        }

        public void Execute()
        {
            float3 lo = new float3(1e9f), hi = new float3(-1e9f);
            for (int c = 0; c < 8; c++)
            {
                float3 corner = new float3((c & 1) == 0 ? boxMin.x : boxMax.x, (c & 2) == 0 ? boxMin.y : boxMax.y, (c & 4) == 0 ? boxMin.z : boxMax.z);
                float3 wv = (math.transform(bladeToWorld, corner) - origin) / Voxel;
                lo = math.min(lo, wv); hi = math.max(hi, wv);
            }
            int3 a = math.clamp((int3)math.floor(lo), new int3(Rim, 1, Rim), new int3(NX - 1 - Rim, NY - 1, NZ - 1 - Rim));
            int3 b = math.clamp((int3)math.ceil(hi), new int3(Rim, 1, Rim), new int3(NX - 1 - Rim, NY - 1, NZ - 1 - Rim));
            int cut = 0, hard = 0;
            made = 0;

            for (int z = a.z; z <= b.z; z++)
                for (int x = a.x; x <= b.x; x++)
                {
                    int col = x + NX * z;
                    int colTop = top[col];
                    int yMax = math.min(b.y, colTop - 1);
                    bool changed = false;
                    int firstCut = 0, lastCut = 0;
                    for (int y = a.y; y <= yMax; y++)
                    {
                        byte m = vox[y + NY * col];
                        if (m == Air) continue;
                        float3 l = math.transform(worldToBlade, origin + (new float3(x, y, z) + 0.5f) * Voxel);
                        if (l.x < boxMin.x || l.x > boxMax.x || l.y < boxMin.y || l.y > boxMax.y || l.z < boxMin.z || l.z > boxMax.z) continue;
                        if (m >= Rock && m <= Gold) { hard++; continue; }
                        vox[y + NY * col] = Air;
                        Mark(ref dirty, x, y, z);
                        Cut(Loosen(m), x, y, z);
                        if (!changed) firstCut = y;
                        lastCut = y;
                        changed = true; cut++;
                    }
                    if (!changed) continue;
                    grass[col] = 0;
                    // Whatever sat above the cut is undermined, so it breaks loose too and becomes clods where it is.
                    // Solid rock stays put and holds up what rests on it.
                    for (int y = lastCut + 1; y < colTop; y++)
                    {
                        byte m = vox[y + NY * col];
                        if (m == Air) continue;
                        if (m >= Rock && m <= Gold) break;
                        vox[y + NY * col] = Air;
                        Mark(ref dirty, x, y, z);
                        Cut(Loosen(m), x, y, z);
                        cut++;
                    }
                    int t = colTop;
                    while (t > 0 && vox[t - 1 + NY * col] == Air) t--;
                    top[col] = (ushort)t;
                }

            // any whole clods still owed (the clod limit was reached earlier) appear at the blade face when there is room
            for (int m = LooseSoil; m <= LooseGold; m++)
                while (load[m] >= ClodVoxels && cCount[0] < MaxClods)
                {
                    load[m] -= ClodVoxels;
                    float u = (math.hash(new int2(cCount[0], seed)) & 1023u) / 1023f;
                    Spawn(math.transform(bladeToWorld, new float3(math.lerp(boxMin.x, boxMax.x, u), 0.3f, boxMax.z + 0.15f)), (byte)m);
                }

            result[0] = cut; result[1] = hard; result[2] = made;
        }
    }

    // the eight neighbours: even entries are the four straight directions
    static readonly int[] DXs = { 1, 1, 0, -1, -1, -1, 0, 1 };
    static readonly int[] DZs = { 0, 1, 1, 1, 0, -1, -1, -1 };

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct SlumpJob : IJob
    {
        [ReadOnly] public NativeArray<int> DX, DZ;
        public NativeArray<byte> grass;
        public NativeArray<byte> vox;
        public NativeArray<ushort> top;
        public NativeArray<byte> dirty;
        public int x0, x1, z0, z1, iterations, seed;

        public void Execute()
        {
            for (int it = 0; it < iterations; it++)
                for (int z = z0; z <= z1; z++)
                    for (int x = x0; x <= x1; x++)
                    {
                        int c = x + NX * z;
                        int t = top[c];
                        if (t < 2) continue;
                        byte m = vox[t - 1 + NY * c];
                        if (m < LooseSoil) continue;
                        // 1. Too steep right here: more than one block above a neighbour (any of the eight).
                        //    Roll to the lowest one, starting from a different side each time so heaps stay round.
                        int start = (int)(math.hash(new int3(x, z, it + seed)) & 7u), bestX = 0, bestZ = 0, bestT = t;
                        for (int k = 0; k < 8; k++)
                        {
                            int side = (start + k) & 7;
                            int nx = x + DX[side], nz = z + DZ[side];
                            int nt = top[nx + NX * nz];
                            if (nt < bestT) { bestT = nt; bestX = nx; bestZ = nz; }
                        }
                        bool rubble = m >= LooseRock;                         // broken rock, quartz, gold ore
                        bool move = t - bestT >= (rubble ? 3 : 2);              // rubble holds a rougher, steeper face
                        if (!move && !rubble)
                        {
                            // 2. Dirt will not stand at 45 degrees.  Look three blocks out: a drop of three or more
                            //    over that run is still too steep (it settles at about 34 degrees), so creep one block that way.
                            int bestDrop = 2;
                            for (int k = 0; k < 4; k++)
                            {
                                int side = ((start + k) & 3) * 2;                    // the four straight directions
                                int nt1 = top[x + DX[side] + NX * (z + DZ[side])];
                                int nt3 = top[x + DX[side] * 3 + NX * (z + DZ[side] * 3)];
                                if (nt1 < t && t - nt3 > bestDrop) { bestDrop = t - nt3; bestT = nt1; bestX = x + DX[side]; bestZ = z + DZ[side]; move = true; }
                            }
                        }
                        if (!move) continue;
                        if ((math.hash(new int3(x, z, it * 31 + seed)) % 10u) == 0u) continue;   // the odd clod hangs on a moment
                        int nc = bestX + NX * bestZ;
                        grass[nc] = 0;                                         // dirt has rolled onto it
                        int count = math.clamp((t - bestT) / 3, 1, 2);         // a little at a time, so it flows and doesn't jump
                        for (int n = 0; n < count; n++)
                        {
                            int ty = top[c];
                            if (ty < 1) break;
                            byte mm = vox[ty - 1 + NY * c];
                            if (mm < LooseSoil) break;                           // reached firm ground
                            int by = top[nc];
                            if (by >= NY - 1 || by >= ty - 1) break;
                            vox[ty - 1 + NY * c] = Air;
                            Mark(ref dirty, x, ty - 1, z);
                            int nt2 = ty - 1;
                            while (nt2 > 0 && vox[nt2 - 1 + NY * c] == Air) nt2--;
                            top[c] = (ushort)nt2;
                            vox[by + NY * nc] = mm;
                            top[nc] = (ushort)(by + 1);
                            Mark(ref dirty, bestX, by, bestZ);
                        }
                    }
        }
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct RipJob : IJob
    {
        public NativeArray<byte> vox;
        public NativeArray<ushort> top;
        public NativeArray<byte> dirty;
        public NativeArray<int> load;
        public NativeArray<byte> grass;
        [ReadOnly] public NativeArray<float3> points;
        public NativeArray<int> result;
        public float3 origin, machineVel;
        public float radius;
        public int seed;
        public NativeArray<float3> cPos, cVel;
        public NativeArray<quaternion> cRot;
        public NativeArray<byte> cMat, cCnt;
        public NativeArray<float> cRest, cAge;
        public NativeArray<int> cCount;

        /// One voxel is torn out.  Every eighth of a material is thrown up as a clod from where it was.
        void Tear(byte loose, int x, int y, int z)
        {
            load[loose]++;
            if (load[loose] < ClodVoxels || cCount[0] >= MaxClods) return;
            load[loose] -= ClodVoxels;
            int n = cCount[0]++;
            uint h = math.hash(new int3(n, seed, x));
            float3 r = new float3(h & 255u, (h >> 8) & 255u, (h >> 16) & 255u) / 255f - 0.5f;
            cPos[n] = origin + (new float3(x, y, z) + 0.5f) * Voxel + r * (Voxel * 2f) + new float3(0f, Voxel * 2f, 0f);
            // heaved up and out to the sides of the shank, carried along a little with the machine
            cVel[n] = machineVel * 0.4f + new float3(r.x * 2.4f, 1.0f + (r.y + 0.5f) * 0.9f, r.z * 2.4f);
            cRot[n] = quaternion.identity;
            cMat[n] = loose; cCnt[n] = ClodVoxels; cRest[n] = 0f; cAge[n] = 0f;
        }

        public void Execute()
        {
            int torn = 0;
            float r = radius / Voxel;
            for (int i = 0; i < points.Length; i++)
            {
                float3 c = (points[i] - origin) / Voxel;
                int3 a = math.clamp((int3)math.floor(c - r), new int3(Rim + 6, 1, Rim + 6), new int3(NX - 7 - Rim, NY - 1, NZ - 7 - Rim));
                int3 b = math.clamp((int3)math.ceil(c + r), new int3(Rim + 6, 1, Rim + 6), new int3(NX - 7 - Rim, NY - 1, NZ - 7 - Rim));
                for (int z = a.z; z <= b.z; z++)
                    for (int x = a.x; x <= b.x; x++)
                    {
                        int col = x + NX * z;
                        int colTop = top[col];
                        int first = -1;
                        for (int y = a.y; y <= b.y && y < colTop; y++)
                        {
                            if (math.distancesq(new float3(x, y, z) + 0.5f, c) > r * r) continue;
                            byte m = vox[y + NY * col];
                            if (m == Air || m >= LooseSoil) continue;       // loose rubble is left for the blade
                            vox[y + NY * col] = Air;
                            Mark(ref dirty, x, y, z);
                            Tear(Loosen(m), x, y, z);
                            torn++;
                            if (first < 0) first = y;
                        }
                        if (first < 0) continue;
                        grass[col] = 0;
                        // whatever was left hanging over the furrow is broken too, and drops into it as rubble
                        int wy = first;
                        for (int y = first; y < colTop; y++)
                        {
                            byte m = vox[y + NY * col];
                            if (m == Air) continue;
                            if (y != wy)
                            {
                                vox[wy + NY * col] = Loosen(m);
                                vox[y + NY * col] = Air;
                                Mark(ref dirty, x, wy, z); Mark(ref dirty, x, y, z);
                            }
                            else if (m < LooseSoil) { vox[y + NY * col] = Loosen(m); Mark(ref dirty, x, y, z); }
                            wy++;
                        }
                        top[col] = (ushort)wy;
                    }
            }
            result[0] = torn;
        }
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct CountJob : IJob
    {
        [ReadOnly] public NativeArray<byte> vox;
        public NativeArray<long> result;

        public void Execute()
        {
            long n = 0;
            for (int i = 0; i < vox.Length; i++) if (vox[i] != Air) n++;
            result[0] = n;
        }
    }
}
