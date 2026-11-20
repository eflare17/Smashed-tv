// Diggable ground made of 6.25 cm voxels, the same size as the bulldozer's.
// A 96 m x 96 m site, 14 m tall (4 m below the work floor, 10 m above for the hill and heaps), drawn in 2 m chunks.
// The ground is shaped as a quarry cut into a hillside: see GenerateJob.
// Only chunks that change get rebuilt.  The heavy loops are Burst jobs.
//
// Where the voxels are kept.  The whole area the game knows about (the "grid") is bigger than the site: it runs on
// north and west over the mountain behind the mine, and up to its top.  But voxels are only kept where they are
// needed, in 2 m x 2 m columns of ground ("blocks", one chunk across):
//   - the site: every block, 14 m tall, as it always was;
//   - the road strip up the mountain (MountainRoad): only the blocks along it, each only as tall as it needs;
//   - everywhere else: no voxels.  The ground there is the plain solid mesh of the hillside (SiteProps.Hillside),
//     and top[] holds its height so the dozer and loose dirt still find the ground.
// A block's voxels run from layer lo up to (not including) hi.  Below lo is solid ground that can't be dug; above hi is air.
// blocks[] holds, for each block: where its voxels start in vox[] (-1 = none), lo, hi, and what it is (BlockSite or BlockStrip).
using System.Runtime.InteropServices;
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

public partial class VoxelWorld : MonoBehaviour
{
    public const int NX = 1856, NY = 576, NZ = 2560;        // the grid, in voxels: 116 m x 160 m, 36 m tall (from 4 m below the work floor)
    public const int CS = 32, CX = NX / CS, CY = NY / CS, CZ = NZ / CS;
    public const int SiteNX = 1536, SiteNY = 224, SiteNZ = 1536;   // the site itself: 96 m x 96 m, 14 m tall
    public const int SiteX0 = NX - SiteNX;                  // the grid runs on this far west of the site (20 m); the site starts at column SiteX0, row 0
    public const int Ground = 64;                           // voxel layer that sits at world height 0 (4 m to dig down, 10 m of hill and air above)
    public const float Voxel = 0.0625f;
    public const float SiteHalf = SiteNX / 2 * Voxel;       // 48 m: the site runs from -48 to 48 each way
    public const int Rim = 2;                               // untouchable border, so you can't dig out of the grid
    /// How far from the middle a machine may drive (metres), keeping its blade and its dirt inside the patch.
    /// (On the mountain road it may also drive along the road strip: see DozerController.)
    public const float DriveLimit = SiteHalf - 6.5f;        // leaves the heap in front of the blade room to sit
    public const int BlockSite = 1, BlockStrip = 2;         // what a block of voxels is (blocks[].w)

    // materials.  6 and up are loose: they can be pushed, and they slump into heaps
    public const byte Air = 0, Soil = 1, Clay = 2, Rock = 3, Quartz = 4, Gold = 5,
                      LooseSoil = 6, LooseClay = 7, LooseRock = 8, LooseQuartz = 9, LooseGold = 10;
    /// The grass value that means "leaf litter" (the mountain's forest floor, on the road strip before it is worked).
    public const byte Litter = 60;

    // Landmarks of the quarry, in metres (x right, z ahead of where the dozer starts facing).
    public const float PortalX = 9f, PortalZ = 11.6f;       // the mine entrance in the north face
    public const float TunnelLength = 31f, TunnelHalfWidth = 1.6f, TunnelHeight = 2.6f;
    // The tunnel, metres in from the mouth:
    //   0-3     open, the rails running in
    //   3-7     collapse 1: small, mostly loose dirt and clay (the shovel clears it)
    //   7-13    open: old props still standing
    //   13-19   collapse 2: bigger, rock through it (the pick, or better the jackhammer)
    //   19-23   a small chamber, wider and taller, with a quartz seam in its walls
    //   23-28   collapse 3: the worst, mostly rock
    //   28-31   the end chamber, with a richer seam
    // One dozer part is buried in each collapse.
    public const float Chamber2From = 19.5f, Chamber2To = 22.5f, EndFrom = 28f;
    public static float TunnelHalfWidthAt(float along) { return along >= EndFrom ? 2.6f : along > Chamber2From && along < Chamber2To ? 2.3f : TunnelHalfWidth; }
    public static float TunnelHeightAt(float along) { return along >= EndFrom ? 3.2f : along > Chamber2From && along < Chamber2To ? 3.0f : TunnelHeight; }

    static float Ramp(float a, float s, float f0, float f1, float e) { return a < s || a > e ? 0f : a < f0 ? (a - s) / (f0 - s) : a <= f1 ? 1f : (e - a) / (e - f1); }
    /// How high the rubble of a collapse fills the tunnel (1 = to the roof), and which collapse it is (0, 1, 2).
    static float CollapseFill(float along, out int which)
    {
        which = along < 10f ? 0 : along < 21f ? 1 : 2;
        return 1.2f * math.max(Ramp(along, 3f, 4.2f, 6f, 7f), math.max(Ramp(along, 13f, 14.6f, 17.4f, 19f), Ramp(along, 23f, 24.2f, 26.8f, 28f)));
    }
    public const float RoadX = -4f, RoadHalfWidth = 5.5f;   // the way out to the south
    // The escape track: a ramp up through the benches just east of the mine, then over the hilltop to the north fence
    // and on up the hillside beyond it (SiteProps.Hillside).  It wanders a little either side of TrackX.
    public const float TrackX = 16f, TrackHalf = 2.2f, TrackZ0 = 7f, TrackRampLen = 18f, TrackTop = 4.6f;
    public static float TrackCentreX(float wz) { return TrackX + 1.2f * Mathf.Sin(wz * 0.09f); }
    public const float RockPadX = 16f, RockPadZ = -8f;      // a bare rock patch on the floor, for ripping

    // Where the three dozer parts lie buried in the cave-in (see Finds.cs): across from the tunnel's middle, along from its mouth.
    const float Find0X = -0.7f, Find0Z = 5.0f, Find1X = 0.6f, Find1Z = 16.0f, Find2X = -0.4f, Find2Z = 25.6f;   // one in each collapse
    const float FindHalf = 0.34f, FindTall = 0.5f;

    public static Vector3 FindSpot(int k)
    {
        return k == 0 ? new Vector3(PortalX + Find0X, 0f, PortalZ + Find0Z)
             : k == 1 ? new Vector3(PortalX + Find1X, 0f, PortalZ + Find1Z)
             : new Vector3(PortalX + Find2X, 0f, PortalZ + Find2Z);
    }

    /// True inside the little hollow each find sits in.  wy is height above the tunnel floor.
    static bool InFindHole(float wx, float wy, float wz)
    {
        if (wy < 0f || wy >= FindTall) return false;
        float x = wx - PortalX, z = wz - PortalZ;
        return (math.abs(x - Find0X) < FindHalf && math.abs(z - Find0Z) < FindHalf)
            || (math.abs(x - Find1X) < FindHalf && math.abs(z - Find1Z) < FindHalf)
            || (math.abs(x - Find2X) < FindHalf && math.abs(z - Find2Z) < FindHalf);
    }

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
    // dirty[] per chunk: bit 1 = needs redrawing, bit 2 = changed since the ground was made (so it goes in a save)
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
    public readonly double[] MsTotal = new double[5];        // all the time spent in each, for timing tests
    public readonly int[] Calls = new int[5];
    public static readonly string[] MsNames = { "cut", "clods", "slump", "ground", "draw" };
    readonly System.Diagnostics.Stopwatch watch = new System.Diagnostics.Stopwatch();

    void Tic() { watch.Restart(); }
    void Toc(int i)
    {
        float ms = (float)watch.Elapsed.TotalMilliseconds;
        MsAvg[i] = Mathf.Lerp(MsAvg[i], ms, 0.05f);
        if (ms > MsMax[i]) MsMax[i] = ms;
        MsTotal[i] += ms; Calls[i]++;
    }
    /// How fast the loose clods are moving on average, and how many are moving faster than `over` (for tests).
    public float ClodMeanSpeed(float over, out int fast)
    {
        int n = cCount[0]; fast = 0;
        if (n == 0) return 0f;
        float sum = 0f;
        for (int i = 0; i < n; i++) { float s = Unity.Mathematics.math.length(cVel[i]); sum += s; if (s > over) fast++; }
        return sum / n;
    }

    public void ResetTimings() { for (int i = 0; i < 5; i++) { MsAvg[i] = 0f; MsMax[i] = 0f; MsTotal[i] = 0; Calls[i] = 0; } }

    NativeArray<byte> vox;                                   // the blocks' voxels, one after another; see ColBase
    NativeArray<int4> blocks;                                // per block (x / 32 + CX * (z / 32)): where its voxels start (-1 = none), lo, hi, what it is
    public long VoxelBytes { get { return vox.IsCreated ? vox.Length : 0; } }
    public int StripBlocks { get; private set; }             // blocks of voxels kept along the mountain road
    public long StripVoxels { get; private set; }            // how many voxels those hold
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

    /// Where column (x, z)'s voxels are: vox[ColBase(...) + y] for lo <= y < hi.  -1 if the column has none.
    static int ColBase(NativeArray<int4> blocks, int x, int z, out int lo, out int hi)
    {
        int4 b = blocks[(x >> 5) + CX * (z >> 5)];
        lo = b.y; hi = b.z;
        if (b.x < 0) return -1;
        return b.x + ((x & 31) + 32 * (z & 31)) * (b.z - b.y) - b.y;
    }

    /// What is at voxel (x, y, z), anywhere in the grid: below a block's voxels is solid rock that can't be dug, above
    /// them air; where there are no voxels at all the ground (top[]) is solid and above it is air.
    static byte VoxelAt(NativeArray<byte> vox, NativeArray<int4> blocks, NativeArray<ushort> top, int x, int y, int z)
    {
        if (y >= NY) return Air;
        if (x < 0 || y < 0 || z < 0 || x >= NX || z >= NZ) return Rock;
        int lo, hi;
        int cb = ColBase(blocks, x, z, out lo, out hi);
        if (cb < 0) return y < top[x + NX * z] ? Rock : Air;
        if (y < lo) return Rock;
        if (y >= hi) return Air;
        return vox[cb + y];
    }

    NativeArray<float> shape;                                // MountainRoad's easing of the ground near the road, for the jobs
    float4 shapeRect; int2 shapeSize;

    /// MountainRoad.ShapeDelta, for Burst: bilinear in its grid, 0 outside it.
    static float ShapeAt(NativeArray<float> sh, float4 rect, int2 n, float x, float z)
    {
        float fx = (x - rect.x) * rect.z, fz = (z - rect.y) * rect.z;
        if (fx < 0f || fz < 0f || fx >= n.x - 1 || fz >= n.y - 1) return 0f;
        int ix = (int)fx, iz = (int)fz;
        float u = fx - ix, v = fz - iz;
        int k = ix + n.x * iz;
        return math.lerp(math.lerp(sh[k], sh[k + 1], u), math.lerp(sh[k + n.x], sh[k + n.x + 1], u), v);
    }

    /// Lays out the blocks: the whole site, and the blocks along the mountain road with the height of ground they need.
    /// Returns how many voxels that is.
    long BuildBlocks()
    {
        var b = new int4[CX * CZ];
        long next = 0;
        int strip = 0;
        int sx0 = SiteX0 / CS, sx1 = NX / CS, sz1 = SiteNZ / CS;
        for (int bz = 0; bz < CZ; bz++)
            for (int bx = 0; bx < CX; bx++)
            {
                int k = bx + CX * bz;
                b[k] = new int4(-1, 0, 0, 0);
                if (bx >= sx0 && bx < sx1 && bz < sz1)
                {
                    b[k] = new int4((int)next, 0, SiteNY, BlockSite);
                    next += CS * CS * SiteNY;
                    continue;
                }
                // a block along the road: within a little more than half the strip's width of the line
                float x0 = origin.x + bx * CS * Voxel, z0 = origin.z + bz * CS * Voxel, size = CS * Voxel;
                if (x0 > MountainRoad.Max.x + 8f || z0 > MountainRoad.Max.y + 8f || x0 + size < MountainRoad.Min.x - 8f || z0 + size < MountainRoad.Min.y - 8f) continue;
                if (MountainRoad.DistanceTo(x0 + size * 0.5f, z0 + size * 0.5f) > MountainRoad.VoxelHalf + 0.6f + size * 0.75f) continue;   // nowhere near
                float near = float.MaxValue;
                float lowY = float.MaxValue, highY = float.MinValue;
                for (int j = 0; j <= 4; j++)
                    for (int i = 0; i <= 4; i++)
                    {
                        float x = x0 + size * i / 4f, z = z0 + size * j / 4f, s, off;
                        Vector2 dir;
                        float d = MountainRoad.Nearest(x, z, out s, out off, out dir);
                        near = Mathf.Min(near, d);
                        float nat = Mountain.OutsideY(x, z) + MountainRoad.ShapeDelta(x, z), g = MountainRoad.GradeAt(s);
                        lowY = Mathf.Min(lowY, Mathf.Min(nat, g) - 3f);          // about 3 m of diggable ground under the road
                        highY = Mathf.Max(highY, Mathf.Max(nat, g) + 2.5f);      // and room for a heap on top
                    }
                if (near > MountainRoad.VoxelHalf + 0.6f) continue;
                int lo = Mathf.Clamp(Mathf.FloorToInt((lowY / Voxel + Ground) / CS) * CS, 0, NY - CS);
                int hi = Mathf.Clamp(Mathf.CeilToInt((highY / Voxel + Ground) / CS) * CS, lo + CS, NY);
                b[k] = new int4((int)next, lo, hi, BlockStrip);
                next += CS * CS * (hi - lo);
                StripVoxels += CS * CS * (hi - lo);
                strip++;
            }
        blocks = new NativeArray<int4>(b, Allocator.Persistent);
        StripBlocks = strip;
        return next;
    }

    /// True if chunk c has voxels of its own (its block has voxels at its height).
    bool ChunkReal(int c)
    {
        int cx = c % CX, cy = (c / CX) % CY, cz = c / (CX * CY);
        int4 b = blocks[cx + CX * cz];
        return b.x >= 0 && cy * CS >= b.y && cy * CS < b.z;
    }

    public long GridBytes { get; private set; }              // all the arrays the ground keeps (for the memory report)
    public float BuildMs { get; private set; }               // how long making the ground took at the start
    public float BlocksMs { get; private set; }              //   of which: laying out the blocks (and the road line)
    public float GenerateMs { get; private set; }            //   making the voxels (the rest is drawing them)

    void Awake()
    {
        Instance = this;
        var startWatch = System.Diagnostics.Stopwatch.StartNew();
        origin = new Vector3(-SiteHalf - SiteX0 * Voxel, -Ground * Voxel, -SiteHalf);
        float[] sg; Vector2 smin; float scell; int sw, sh;
        MountainRoad.ShapeGrid(out sg, out smin, out scell, out sw, out sh);
        shape = new NativeArray<float>(sg, Allocator.Persistent);
        shapeRect = new float4(smin.x, smin.y, 1f / scell, 0f); shapeSize = new int2(sw, sh);
        long voxels = BuildBlocks();
        BlocksMs = (float)startWatch.Elapsed.TotalMilliseconds;
        vox = new NativeArray<byte>((int)voxels, Allocator.Persistent);
        top = new NativeArray<ushort>(NX * NZ, Allocator.Persistent);
        dirty = new NativeArray<byte>(CX * CY * CZ, Allocator.Persistent);
        chunkFilters = new MeshFilter[CX * CY * CZ];
        dxs = new NativeArray<int>(DXs, Allocator.Persistent);
        dzs = new NativeArray<int>(DZs, Allocator.Persistent);
        bladeLoad = new NativeArray<int>(16, Allocator.Persistent);
        grass = new NativeArray<byte>(NX * NZ, Allocator.Persistent);
        InitDirt();
        InitHand();

        new GenerateJob { vox = vox, top = top, grass = grass, blocks = blocks, origin = origin, shape = shape, shapeRect = shapeRect, shapeSize = shapeSize }.Schedule(NX * NZ, 256).Complete();
        GenerateMs = (float)startWatch.Elapsed.TotalMilliseconds - BlocksMs;
        GridBytes = vox.Length + top.Length * 2L + grass.Length * 2L + dirty.Length + blocks.Length * 16L;   // (grass twice: the array and its picture)
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
        var stripCount = new NativeArray<long>(1, Allocator.TempJob);
        new CountStripJob { vox = vox, blocks = blocks, result = stripCount }.Run();
        StripSolidAtStart = stripCount[0];
        stripCount.Dispose();
        ResetTimings();
        BuildMs = (float)startWatch.Elapsed.TotalMilliseconds;
        Time.maximumDeltaTime = 0.05f;                       // if a frame runs long, don't pile up catch-up physics steps
    }

    void OnDestroy()
    {
        if (vox.IsCreated) vox.Dispose();
        if (blocks.IsCreated) blocks.Dispose();
        if (shape.IsCreated) shape.Dispose();
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

    /// How grassy the untouched surface is here (0 = bare: worked, dug or scraped).  0 outside the site.
    public byte GrassAt(float wx, float wz)
    {
        int ix = Mathf.FloorToInt((wx - origin.x) / Voxel), iz = Mathf.FloorToInt((wz - origin.z) / Voxel);
        if (ix < 0 || iz < 0 || ix >= NX || iz >= NZ) return 0;
        return grass[ix + NX * iz];
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
        for (int z = 0; z < SiteNZ; z++)                      // (only the site: the mountain's top is not a heap)
            for (int x = SiteX0; x < NX; x++) { int i = x + NX * z; if (top[i] > best) { best = top[i]; bi = i; } }
        where = new Vector3(origin.x + (bi % NX + 0.5f) * Voxel, (best - Ground) * Voxel, origin.z + (bi / NX + 0.5f) * Voxel);
        return (best - Ground) * Voxel;
    }

    /// The ground's height in metres at the middle of one column (no averaging).  0 outside the grid.
    public float TopAt(float wx, float wz)
    {
        int ix = Mathf.FloorToInt((wx - origin.x) / Voxel), iz = Mathf.FloorToInt((wz - origin.z) / Voxel);
        if (ix < 0 || iz < 0 || ix >= NX || iz >= NZ) return 0f;
        return (top[ix + NX * iz] - Ground) * Voxel;
    }

    /// True if the top of the ground here is loose dirt (spoil, a heap), not firm ground.
    public bool LooseOnTop(float wx, float wz)
    {
        int ix = Mathf.FloorToInt((wx - origin.x) / Voxel), iz = Mathf.FloorToInt((wz - origin.z) / Voxel);
        if (ix < 0 || iz < 0 || ix >= NX || iz >= NZ) return false;
        int lo, hi;
        int cb = ColBase(blocks, ix, iz, out lo, out hi);
        int t = top[ix + NX * iz];
        if (cb < 0 || t <= lo || t > hi) return false;
        return vox[cb + t - 1] >= LooseSoil;
    }

    /// The height in metres of the firm ground in one column: loose dirt lying on top (spoil, a heap) is left out.
    /// False where the column has no voxels.  (Blade auto measures its cut from this.)
    public bool FirmHeightAt(float wx, float wz, out float h)
    {
        h = 0f;
        int ix = Mathf.FloorToInt((wx - origin.x) / Voxel), iz = Mathf.FloorToInt((wz - origin.z) / Voxel);
        if (ix < 0 || iz < 0 || ix >= NX || iz >= NZ) return false;
        int lo, hi;
        int cb = ColBase(blocks, ix, iz, out lo, out hi);
        int t = top[ix + NX * iz];
        if (cb < 0 || t <= lo || t > hi) return false;
        while (t > lo + 1 && vox[cb + t - 1] >= LooseSoil) t--;
        h = (t - Ground) * Voxel;
        return true;
    }

    /// What kind of ground the column at (wx, wz) is: 0 = no voxels (the mountain's mesh, or outside), BlockSite, BlockStrip.
    public int KindAt(float wx, float wz)
    {
        int ix = Mathf.FloorToInt((wx - origin.x) / Voxel), iz = Mathf.FloorToInt((wz - origin.z) / Voxel);
        if (ix < 0 || iz < 0 || ix >= NX || iz >= NZ) return 0;
        int4 b = blocks[(ix >> 5) + CX * (iz >> 5)];
        return b.x < 0 ? 0 : b.w;
    }

    /// What material is at a point (metres), with the same rules as the jobs use.
    public byte VoxelAtPoint(Vector3 p)
    {
        int x = Mathf.FloorToInt((p.x - origin.x) / Voxel), y = Mathf.FloorToInt((p.y - origin.y) / Voxel), z = Mathf.FloorToInt((p.z - origin.z) / Voxel);
        return VoxelAt(vox, blocks, top, x, y, z);
    }

    /// The layers a column's voxels cover, in metres (lo, hi).  False where the column has none.
    public bool ColumnRange(float wx, float wz, out float lo, out float hi)
    {
        lo = hi = 0f;
        int ix = Mathf.FloorToInt((wx - origin.x) / Voxel), iz = Mathf.FloorToInt((wz - origin.z) / Voxel);
        if (ix < 0 || iz < 0 || ix >= NX || iz >= NZ) return false;
        int4 b = blocks[(ix >> 5) + CX * (iz >> 5)];
        if (b.x < 0) return false;
        lo = (b.y - Ground) * Voxel; hi = (b.z - Ground) * Voxel;
        return true;
    }

    // the blocks, for the hillside mesh (it leaves a hole over each strip block, and puts a wall round the hole)
    public bool BlockIsStrip(int bx, int bz) { return bx >= 0 && bz >= 0 && bx < CX && bz < CZ && blocks[bx + CX * bz].w == BlockStrip; }
    public bool BlockHasVoxels(int bx, int bz) { return bx >= 0 && bz >= 0 && bx < CX && bz < CZ && blocks[bx + CX * bz].x >= 0; }
    public float BlockLoY(int bx, int bz) { return (blocks[bx + CX * bz].y - Ground) * Voxel; }
    public Vector3 Origin { get { return origin; } }

    /// For tests: makes the ground in one column exactly `height` metres high (soil added, or ground taken away).
    /// Keeps the volume books straight.  Only where the column has voxels.
    public bool TestSetColumn(float wx, float wz, float height)
    {
        int x = Mathf.FloorToInt((wx - origin.x) / Voxel), z = Mathf.FloorToInt((wz - origin.z) / Voxel);
        if (x < Rim || z < Rim || x >= NX - Rim || z >= NZ - Rim) return false;
        int lo, hi;
        int cb = ColBase(blocks, x, z, out lo, out hi);
        if (cb < 0) return false;
        int col = x + NX * z, want = Mathf.Clamp(Ground + Mathf.RoundToInt(height / Voxel), lo + 1, hi - 1), t = top[col];
        if (want == t) return true;
        for (int y = Mathf.Min(t, want); y < Mathf.Max(t, want); y++)
        {
            if (want > t) { if (vox[cb + y] == Air) { vox[cb + y] = Soil; SolidCount++; StartTotal++; } }
            else if (vox[cb + y] != Air) { vox[cb + y] = Air; SolidCount--; StartTotal--; }
            Mark(ref dirty, x, y, z);
        }
        top[col] = (ushort)want;
        grass[col] = 0;
        return true;
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
            vox = vox, blocks = blocks, top = top, dirty = dirty, load = bladeLoad, result = result, grass = grass,
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
        LoadVoxels = carried + ClodVoxelsInFlight + spawned * ClodVoxels + ShovelVoxels + CartVoxels + PackVoxels + SoldVoxels + SpilledVoxels;
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
            vox = vox, blocks = blocks, top = top, dirty = dirty, load = bladeLoad, grass = grass, points = pts, radius = radius, origin = origin,
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
            vox = vox, blocks = blocks, top = top, dirty = dirty, grass = grass, iterations = iterations, seed = frame, DX = dxs, DZ = dzs,
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
            if ((dirty[i] & 1) != 0)
            {
                if (!ChunkReal(i)) { dirty[i] = 0; continue; }                // a chunk with no voxels of its own: nothing to draw or save
                list.Add(i); dirty[i] = (byte)(dirty[i] & 2);                  // bit 1: redraw it.  Bit 2 (touched) stays, for saving
            }
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
                vox = vox, blocks = blocks, top = top, verts = verts[i], tris = tris[i], origin = origin,
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
        dirty[cx + CX * (cy + CY * cz)] = 3;
        int lx = x & 31, ly = y & 31, lz = z & 31;
        if (lx == 0 && cx > 0) dirty[cx - 1 + CX * (cy + CY * cz)] = 3;
        if (lx == 31 && cx < CX - 1) dirty[cx + 1 + CX * (cy + CY * cz)] = 3;
        if (ly == 0 && cy > 0) dirty[cx + CX * (cy - 1 + CY * cz)] = 3;
        if (ly == 31 && cy < CY - 1) dirty[cx + CX * (cy + 1 + CY * cz)] = 3;
        if (lz == 0 && cz > 0) dirty[cx + CX * (cy + CY * (cz - 1))] = 3;
        if (lz == 31 && cz < CZ - 1) dirty[cx + CX * (cy + CY * (cz + 1))] = 3;
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
        [ReadOnly] public NativeArray<int4> blocks;
        public float3 origin;
        [ReadOnly] public NativeArray<float> shape;          // the ground near the mountain road, eased (MountainRoad.ShapeDelta)
        public float4 shapeRect;
        public int2 shapeSize;

        static float Spire(float2 p, float cx, float cz, float r, float h)
        {
            float d = math.distance(p, new float2(cx, cz)) / r;
            return d >= 1f ? 0f : h * math.pow(1f - d, 1.3f);
        }

        public void Execute(int i)
        {
            int gx = i % NX, z = i / NX;
            int lo, hi;
            int cb = ColBase(blocks, gx, z, out lo, out hi);
            if (cb < 0 || blocks[(gx >> 5) + CX * (z >> 5)].w != BlockSite)
            {
                // outside the site: the hillside and the mountain.  Where there are voxels (the road strip) they are
                // natural ground: topsoil over clay, all of it diggable, with leaf litter on top.
                float ox = origin.x + gx * Voxel, oz = origin.z + z * Voxel;
                int natY = Ground + (int)math.round((Mountain.OutsideY(ox, oz) + ShapeAt(shape, shapeRect, shapeSize, ox, oz)) / Voxel);
                if (cb < 0) { top[i] = (ushort)math.clamp(natY, 0, NY - 1); grass[i] = 0; return; }
                int st = math.clamp(natY, lo + 1, hi - 2);
                for (int y = lo; y < hi; y++)
                {
                    int dn = st - y;
                    vox[cb + y] = y >= st ? Air : dn <= 7 ? Soil : Clay;
                }
                top[i] = (ushort)st;
                grass[i] = Litter;
                return;
            }
            int x = gx - SiteX0;                                                 // the site's own columns, counted as they always were
            float wx = (x - SiteNX / 2) * Voxel, wz = (z - SiteNZ / 2) * Voxel;
            float2 p = new float2(wx, wz);
            float n1 = noise.snoise(p * 0.035f), n2 = noise.snoise(p * 0.11f), n3 = noise.snoise(p * 0.5f);

            // the hill as it was before anyone dug it
            // (it does not fade away at the north fence: the hillside carries on past it, as scenery)
            float inside = math.min(SiteNX / 2 * Voxel - math.abs(wx), wz > 0f ? 99f : SiteNZ / 2 * Voxel - math.abs(wz));
            float fade = math.smoothstep(1.5f, 9f, inside);
            float south = math.smoothstep(-36f, -19f, wz);
            float hill = math.max(0f, (4.5f + 1.1f * n1 + 0.35f * n2) * south * fade);
            hill += ShapeAt(shape, shapeRect, shapeSize, wx, wz);                 // (the mountain road's start crosses the hilltop: eased there)

            // the quarry cut
            float d = (math.length((p - new float2(0f, -6f)) / new float2(24f, 19f)) - 1f) * 20f + n2 * 1.1f;   // metres outside the floor's edge
            bool road = wz < -18f && math.abs(wx - RoadX) < RoadHalfWidth + n2 * 0.5f;
            bool portalFace = math.abs(wx - PortalX) < 3.4f && wz > 0f;
            float cut;
            if (d <= 0f || road) cut = 0f;
            else if (portalFace) cut = 1000f;                                    // a sheer face for the mine entrance
            else cut = (math.floor(d / 3.2f) + 1f) * 1.5f;                       // benches: 1.5 m up, 3.2 m wide
            // the escape track: a ramp up through the benches, then level along the hilltop
            float trackOff = math.abs(wx - (TrackX + 1.2f * math.sin(wz * 0.09f)));
            bool onTrack = trackOff < TrackHalf + 1.4f && wz > TrackZ0 - 1f;
            if (onTrack)
            {
                float ramp = math.saturate((wz - TrackZ0) / TrackRampLen) * TrackTop;
                cut = math.lerp(ramp, math.min(cut, 50f), math.smoothstep(TrackHalf, TrackHalf + 1.4f, trackOff));
            }
            bool floor = (d <= 0f || road) && hill > 0.05f;
            float ground = math.min(hill, cut) + (floor ? 0.05f * n3 : 0f);

            // rock spires standing on the floor and at the foot of the face
            float spire = 0f;
            spire = math.max(spire, Spire(p, -9f, 8.5f, 2.4f, 3.4f));
            spire = math.max(spire, Spire(p, -3.5f, 10.5f, 1.8f, 2.4f));
            spire = math.max(spire, Spire(p, 2.5f, 9.5f, 2.0f, 2.9f));
            spire = math.max(spire, Spire(p, -17f, 1f, 2.2f, 2.6f));
            spire = math.max(spire, Spire(p, -13.5f, -13f, 1.5f, 1.3f));
            spire = math.max(spire, Spire(p, 20f, -17f, 1.6f, 1.5f));
            spire *= 0.8f + 0.35f * n3;
            if (spire < 0.12f) spire = 0f;

            int nat = Ground + (int)math.round(hill / Voxel);                    // where the surface was, for the layers
            int baseSurf = math.clamp(Ground + (int)math.round(ground / Voxel), 8, SiteNY - 48);
            int surf = math.clamp(baseSurf + (int)math.round(spire / Voxel), 8, SiteNY - 44);
            float soil = 7f + n3 * 3f;
            float clay = 30f + noise.snoise(p * 0.17f) * 7f;
            bool rockPad = floor && math.distance(p, new float2(RockPadX, RockPadZ)) < 5.5f + n2 * 1.2f;
            bool fill = (floor || (onTrack && trackOff < TrackHalf + 0.6f)) && hill > 0.5f && !rockPad;   // dust and clay over the cut floor, and the track

            // the tunnel behind the mine entrance
            float tAlong = wz - PortalZ;
            bool tunnel = math.abs(wx - PortalX) < TunnelHalfWidthAt(tAlong) && wz > PortalZ - 1.2f && wz < PortalZ + TunnelLength;
            int tunnelTop = Ground + (int)(TunnelHeightAt(tAlong) / Voxel);

            int b = cb;
            for (int y = 0; y < SiteNY; y++)
            {
                byte m;
                if (y >= surf) m = Air;
                else if (tunnel && y >= Ground && y < tunnelTop && surf - tunnelTop >= 6)
                {
                    // The collapses.  In three places the roof came down years ago: rubble slopes up from the floor,
                    // fills the tunnel to the roof for a stretch, and slopes away again on the far side.  Each is
                    // loose dirt and rock with solid boulders through it, rockier the further in.
                    float along = tAlong;
                    int which;
                    float fillTo = CollapseFill(along, out which);
                    fillTo *= 0.9f + 0.14f * n3;
                    float up = (y - Ground + 0.5f) * Voxel / TunnelHeight;
                    if (up >= fillTo || InFindHole(wx, (y - Ground) * Voxel, wz)) m = Air;
                    else
                    {
                        float wy2 = (y - Ground) * Voxel;
                        float boulder = noise.snoise(new float3(wx, wy2, wz) * 1.1f);
                        uint r = math.hash(new int3(x >> 1, y >> 1, z >> 1)) % 100u;
                        float boulderAt = which == 0 ? 0.8f : which == 1 ? 0.45f : 0.1f;
                        uint rockU = which == 0 ? 25u : which == 1 ? 60u : 80u, clayU = which == 0 ? 60u : which == 1 ? 84u : 92u;
                        m = boulder > boulderAt ? Rock : r < rockU ? LooseRock : r < clayU ? LooseClay : LooseSoil;
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
                    // a quartz seam through the walls of the far chambers, at about chest height, richer at the end
                    float sAlong = wz - PortalZ, sx = wx - PortalX;
                    if ((m == Rock || m == Clay) && sAlong > 18.5f && sAlong < TunnelLength + 0.5f && math.abs(sx) < 4.5f)
                    {
                        float wy3 = (y - Ground) * Voxel;
                        float seam2 = wy3 - 1.1f - (sAlong - 18.5f) * 0.05f - sx * 0.12f + noise.snoise(new float3(wx, wy3, wz) * 0.5f) * 0.18f;
                        if (math.abs(seam2) < 0.14f)
                            m = (math.hash(new int3(x, y, z)) % 1000u) < (sAlong > EndFrom - 0.5f ? 150u : 70u) ? Gold : Quartz;
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
            bool bareTrack = trackOff < TrackHalf + 0.3f && wz > TrackZ0;          // the track is bare dirt
            grass[i] = (byte)(untouched && patchy && !bareTrack ? 150 + (int)(math.hash(new int2(x >> 1, z >> 1)) % 100u) : 0);
        }
    }

    /// Turns one 32 x 32 x 32 chunk into a mesh, merging flat runs of the same material into big quads.
    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct MeshJob : IJob
    {
        [ReadOnly] public NativeArray<byte> vox;
        [ReadOnly] public NativeArray<int4> blocks;
        [ReadOnly] public NativeArray<ushort> top;
        public NativeList<VVert> verts;
        public NativeList<int> tris;
        public float3 origin;
        public int cx, cy, cz;

        byte Get(int3 p) { return VoxelAt(vox, blocks, top, p.x, p.y, p.z); }   // (nothing to see beyond the grid: it counts as rock)

        public void Execute()
        {
            var mask = new NativeArray<byte>(CS * CS, Allocator.Temp);
            int3 b = new int3(cx, cy, cz) * CS;
            int4 blk = blocks[cx + CX * cz];
            int stride = blk.z - blk.y, cbase = blk.x - blk.y;                   // the chunk's own voxels: all in one block
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
                                byte a = vox[cbase + ((p.x & 31) + 32 * (p.z & 31)) * stride + p.y];
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
        [ReadOnly] public NativeArray<int4> blocks;
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
                    int vlo, vhi;
                    int cb = ColBase(blocks, x, z, out vlo, out vhi);
                    if (cb < 0) continue;                                       // the mountain's mesh: it can't be dug
                    int colTop = top[col];
                    int yMax = math.min(b.y, colTop - 1);
                    bool changed = false;
                    int firstCut = 0, lastCut = 0;
                    for (int y = math.max(a.y, vlo); y <= yMax; y++)
                    {
                        byte m = vox[cb + y];
                        if (m == Air) continue;
                        float3 l = math.transform(worldToBlade, origin + (new float3(x, y, z) + 0.5f) * Voxel);
                        if (l.x < boxMin.x || l.x > boxMax.x || l.y < boxMin.y || l.y > boxMax.y || l.z < boxMin.z || l.z > boxMax.z) continue;
                        if (m >= Rock && m <= Gold) { hard++; continue; }
                        vox[cb + y] = Air;
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
                        byte m = vox[cb + y];
                        if (m == Air) continue;
                        if (m >= Rock && m <= Gold) break;
                        vox[cb + y] = Air;
                        Mark(ref dirty, x, y, z);
                        Cut(Loosen(m), x, y, z);
                        cut++;
                    }
                    int t = colTop;
                    while (t > vlo && vox[cb + t - 1] == Air) t--;
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
        [ReadOnly] public NativeArray<int4> blocks;
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
                        int lo, hi;
                        int cb = ColBase(blocks, x, z, out lo, out hi);
                        if (cb < 0 || t <= lo) continue;
                        byte m = vox[cb + t - 1];
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
                        int lo2, hi2;
                        int cb2 = ColBase(blocks, bestX, bestZ, out lo2, out hi2);
                        if (cb2 < 0) continue;                                 // (it does not roll off onto the mountain's mesh: the blade pushes it over)
                        grass[nc] = 0;                                         // dirt has rolled onto it
                        int count = math.clamp((t - bestT) / 3, 1, 2);         // a little at a time, so it flows and doesn't jump
                        for (int n = 0; n < count; n++)
                        {
                            int ty = top[c];
                            if (ty <= lo) break;
                            byte mm = vox[cb + ty - 1];
                            if (mm < LooseSoil) break;                           // reached firm ground
                            int by = top[nc];
                            if (by >= hi2 - 1 || by >= ty - 1 || by < lo2) break;
                            vox[cb + ty - 1] = Air;
                            Mark(ref dirty, x, ty - 1, z);
                            int nt2 = ty - 1;
                            while (nt2 > lo && vox[cb + nt2 - 1] == Air) nt2--;
                            top[c] = (ushort)nt2;
                            vox[cb2 + by] = mm;
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
        [ReadOnly] public NativeArray<int4> blocks;
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
                        int lo, hi;
                        int cb = ColBase(blocks, x, z, out lo, out hi);
                        if (cb < 0) continue;
                        int colTop = top[col];
                        int first = -1;
                        for (int y = math.max(a.y, lo); y <= b.y && y < colTop; y++)
                        {
                            if (math.distancesq(new float3(x, y, z) + 0.5f, c) > r * r) continue;
                            byte m = vox[cb + y];
                            if (m == Air || m >= LooseSoil) continue;       // loose rubble is left for the blade
                            vox[cb + y] = Air;
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
                            byte m = vox[cb + y];
                            if (m == Air) continue;
                            if (y != wy)
                            {
                                vox[cb + wy] = Loosen(m);
                                vox[cb + y] = Air;
                                Mark(ref dirty, x, wy, z); Mark(ref dirty, x, y, z);
                            }
                            else if (m < LooseSoil) { vox[cb + y] = Loosen(m); Mark(ref dirty, x, y, z); }
                            wy++;
                        }
                        top[col] = (ushort)wy;
                    }
            }
            result[0] = torn;
        }
    }

    /// The ground in the road strip's blocks (for loading a save made before the road existed).
    public long StripSolidAtStart { get; private set; }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct TopFromVoxelsJob : IJobParallelFor
    {
        [ReadOnly] public NativeArray<byte> vox;
        [ReadOnly] public NativeArray<int4> blocks;
        public NativeArray<ushort> top;
        public void Execute(int i)
        {
            int lo, hi;
            int cb = ColBase(blocks, i % NX, i / NX, out lo, out hi);
            if (cb < 0) return;
            int t = hi;
            while (t > lo && vox[cb + t - 1] == Air) t--;
            top[i] = (ushort)t;
        }
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct CountStripJob : IJob
    {
        [ReadOnly] public NativeArray<byte> vox;
        [ReadOnly] public NativeArray<int4> blocks;
        public NativeArray<long> result;

        public void Execute()
        {
            long n = 0;
            for (int k = 0; k < blocks.Length; k++)
            {
                int4 b = blocks[k];
                if (b.x < 0 || b.w != BlockStrip) continue;
                int end = b.x + CS * CS * (b.z - b.y);
                for (int i = b.x; i < end; i++) if (vox[i] != Air) n++;
            }
            result[0] = n;
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
