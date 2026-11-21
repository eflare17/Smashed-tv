// Diggable ground made of 6.25 cm voxels, copied from the Digger Game and cut down for the arena.
// A 32 m x 32 m square, 8 m tall (4 m below the floor to dig into, 4 m above it for mounds and heaps), drawn in 2 m chunks.
// Soil (0.5 m) over clay (1.5 m) over rock, flat, with three low mounds.  Only chunks that change get rebuilt.
// The heavy loops are Burst jobs.
//
// Every block of 32 x 32 columns has all its voxels (lo = 0, hi = NY): the Digger Game's road strip is gone, but
// the block layout is kept so the jobs stay the same as the Digger Game's.
//
// Volume bookkeeping.  Dirt is never made or destroyed: SolidCount + LoadVoxels always equals StartTotal.
using System.Runtime.InteropServices;
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

public partial class VoxelWorld : MonoBehaviour
{
    public const int NX = 512, NY = 128, NZ = 512;           // 32 m x 32 m, 8 m tall
    public const int CS = 32, CX = NX / CS, CY = NY / CS, CZ = NZ / CS;
    public const int Ground = 64;                           // voxel layer that sits at world height 0 (4 m to dig down)
    public const float Voxel = 0.0625f;
    public const float SiteHalf = NX / 2 * Voxel;           // 16 m: the ground runs from -16 to 16 each way
    public const int Rim = 2;                               // untouchable border, so you can't dig out of the grid
    public const int BlockSite = 1;

    // materials.  6 and up are loose: they can be pushed, and they slump into heaps
    public const byte Air = 0, Soil = 1, Clay = 2, Rock = 3, Quartz = 4, Gold = 5,
                      LooseSoil = 6, LooseClay = 7, LooseRock = 8, LooseQuartz = 9, LooseGold = 10;

    /// The low mounds: x, z, radius, height (metres).
    public static readonly float4[] Mounds = { new float4(-7.5f, 6.5f, 3.2f, 1.1f), new float4(8f, -5.5f, 3.6f, 0.9f), new float4(6.5f, 8.5f, 2.6f, 0.8f) };

    public static VoxelWorld Instance { get; private set; }

    public Material material;
    public int maxRemeshPerFrame = 64;

    public long SolidCount { get; private set; }             // voxels of ground right now (kept up to date)
    public long StartTotal { get; private set; }             // what it was at the start
    public int LoadVoxels { get; private set; }              // dirt that is not ground right now: moving clods plus the small tally
    int carriedOnBlade;                                      // the tally: loosened voxels not yet enough to make a whole clod
    public const float VoxelVolume = Voxel * Voxel * Voxel;
    public int LastRemeshChunks { get; private set; }
    public float LastRemeshMs { get; private set; }

    // How long each part of the dirt work takes, in milliseconds: [0] dig, [1] clods, [2] slump, [3] redraw ground, [4] draw clods.
    public readonly float[] MsAvg = new float[5], MsMax = new float[5];
    readonly System.Diagnostics.Stopwatch watch = new System.Diagnostics.Stopwatch();
    void Tic() { watch.Restart(); }
    void Toc(int i)
    {
        float ms = (float)watch.Elapsed.TotalMilliseconds;
        MsAvg[i] = Mathf.Lerp(MsAvg[i], ms, 0.05f);
        if (ms > MsMax[i]) MsMax[i] = ms;
    }
    public void ResetTimings() { for (int i = 0; i < 5; i++) { MsAvg[i] = 0f; MsMax[i] = 0f; } }

    NativeArray<byte> vox;                                   // the blocks' voxels, one after another; see ColBase
    NativeArray<int4> blocks;                                // per block: where its voxels start, lo, hi, what it is
    public long VoxelBytes { get { return vox.IsCreated ? vox.Length : 0; } }
    NativeArray<ushort> top;                                 // per column: highest solid voxel + 1
    NativeArray<byte> dirty;                                 // per chunk
    NativeArray<int> dxs, dzs;                               // neighbour offsets, for the jobs
    NativeArray<int> bladeLoad;                              // loosened dirt not yet made into a clod, per material
    NativeArray<byte> grass;                                 // per column: how grassy the untouched surface is (0 = bare or worked)
    Texture2D grassTex;
    float grassTimer;
    MeshFilter[] chunkFilters;
    Vector3 origin;                                          // world position of the corner of voxel (0, 0, 0)
    int frame;

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

    /// What is at voxel (x, y, z): outside the grid it is rock (the walls stand there), above it air.
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

    long BuildBlocks()
    {
        var b = new int4[CX * CZ];
        long next = 0;
        for (int k = 0; k < b.Length; k++) { b[k] = new int4((int)next, 0, NY, BlockSite); next += CS * CS * NY; }
        blocks = new NativeArray<int4>(b, Allocator.Persistent);
        return next;
    }

    public long GridBytes { get; private set; }              // all the arrays the ground keeps (for the memory report)
    public float BuildMs { get; private set; }

    void Awake()
    {
        Instance = this;
        var startWatch = System.Diagnostics.Stopwatch.StartNew();
        origin = new Vector3(-SiteHalf, -Ground * Voxel, -SiteHalf);
        long voxels = BuildBlocks();
        vox = new NativeArray<byte>((int)voxels, Allocator.Persistent);
        top = new NativeArray<ushort>(NX * NZ, Allocator.Persistent);
        dirty = new NativeArray<byte>(CX * CY * CZ, Allocator.Persistent);
        chunkFilters = new MeshFilter[CX * CY * CZ];
        dxs = new NativeArray<int>(DXs, Allocator.Persistent);
        dzs = new NativeArray<int>(DZs, Allocator.Persistent);
        bladeLoad = new NativeArray<int>(16, Allocator.Persistent);
        grass = new NativeArray<byte>(NX * NZ, Allocator.Persistent);
        InitDirt();
        GridBytes = vox.Length + top.Length * 2L + grass.Length * 2L + dirty.Length + blocks.Length * 16L;
        grassTex = new Texture2D(NX, NZ, TextureFormat.R8, false, true) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
        Shader.SetGlobalTexture("_GrassTex", grassTex);
        Shader.SetGlobalVector("_SiteRect", new Vector4(origin.x, origin.z, 1f / (NX * Voxel), 1f / (NZ * Voxel)));
        Shader.SetGlobalFloat("_CutRadius", 0f);
        MakeGround();
        BuildMs = (float)startWatch.Elapsed.TotalMilliseconds;
        Time.maximumDeltaTime = 0.05f;                       // if a frame runs long, don't pile up catch-up physics steps
    }

    /// Lays the ground down fresh (at the start, and when a round starts again): every clod and crumb goes.
    public void MakeGround()
    {
        ClearDirt();
        for (int i = 0; i < bladeLoad.Length; i++) bladeLoad[i] = 0;
        carriedOnBlade = 0;
        new GenerateJob { vox = vox, top = top, grass = grass, blocks = blocks }.Schedule(NX * NZ, 256).Complete();
        grassTex.LoadRawTextureData(grass);
        grassTex.Apply(false);
        for (int i = 0; i < dirty.Length; i++) dirty[i] = 1;
        for (int pass = 0; pass < 200; pass++)               // draw the whole patch once, a batch of chunks at a time
        {
            Remesh(512);
            if (LastRemeshChunks == 0) break;
        }
        SolidCount = StartTotal = CountSolid();
        LoadVoxels = 0;
        ResetTimings();
    }

    void OnDestroy()
    {
        if (vox.IsCreated) vox.Dispose();
        if (blocks.IsCreated) blocks.Dispose();
        if (top.IsCreated) top.Dispose();
        if (dirty.IsCreated) dirty.Dispose();
        if (dxs.IsCreated) dxs.Dispose();
        if (dzs.IsCreated) dzs.Dispose();
        if (bladeLoad.IsCreated) bladeLoad.Dispose();
        if (grass.IsCreated) grass.Dispose();
        DisposeDirt();
        if (Instance == this) Instance = null;
    }

    void LateUpdate()
    {
        frame++;
        Tic(); Remesh(maxRemeshPerFrame); Toc(3);
        grassTimer -= Time.unscaledDeltaTime;
        if (grassTimer <= 0f && grassTex != null)             // show where the grass has been blown off, a few times a second
        {
            grassTimer = 0.15f;
            grassTex.LoadRawTextureData(grass);
            grassTex.Apply(false);
        }
        Tic(); DrawDirt(); Toc(4);
    }

    // ------------------------------------------------------------------ queries
    /// Ground height in metres at the middle of one column (no averaging).  0 outside the grid.
    public float TopAt(float wx, float wz)
    {
        int ix = Mathf.FloorToInt((wx - origin.x) / Voxel), iz = Mathf.FloorToInt((wz - origin.z) / Voxel);
        if (ix < 0 || iz < 0 || ix >= NX || iz >= NZ) return 0f;
        return (top[ix + NX * iz] - Ground) * Voxel;
    }

    /// The lowest ground in a box of columns, in metres (tests: how deep a crater is).
    public float MinHeightIn(float wx0, float wz0, float wx1, float wz1)
    {
        int x0 = Mathf.Clamp(Mathf.FloorToInt((wx0 - origin.x) / Voxel), 0, NX - 1), x1 = Mathf.Clamp(Mathf.FloorToInt((wx1 - origin.x) / Voxel), 0, NX - 1);
        int z0 = Mathf.Clamp(Mathf.FloorToInt((wz0 - origin.z) / Voxel), 0, NZ - 1), z1 = Mathf.Clamp(Mathf.FloorToInt((wz1 - origin.z) / Voxel), 0, NZ - 1);
        int best = NY;
        for (int z = z0; z <= z1; z++) for (int x = x0; x <= x1; x++) best = Mathf.Min(best, top[x + NX * z]);
        return (best - Ground) * Voxel;
    }

    public Vector3 Origin { get { return origin; } }

    public long CountSolid()
    {
        var result = new NativeArray<long>(1, Allocator.TempJob);
        new CountJob { vox = vox, result = result }.Run();
        long n = result[0];
        result.Dispose();
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
            if ((dirty[i] & 1) != 0) { list.Add(i); dirty[i] = 0; }
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

    /// The arena floor, one column at a time: flat at height 0 with three low mounds, soil over clay over rock.
    /// The layers follow the surface, so a mound is soil and clay all through, and a crater shows soil, then clay, then rock.
    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct GenerateJob : IJobParallelFor
    {
        [NativeDisableParallelForRestriction] public NativeArray<byte> vox;
        public NativeArray<ushort> top;
        public NativeArray<byte> grass;
        [ReadOnly] public NativeArray<int4> blocks;

        public void Execute(int i)
        {
            int x = i % NX, z = i / NX;
            int lo, hi;
            int cb = ColBase(blocks, x, z, out lo, out hi);
            float wx = (x - NX / 2 + 0.5f) * Voxel, wz = (z - NZ / 2 + 0.5f) * Voxel;
            float2 p = new float2(wx, wz);
            float n2 = noise.snoise(p * 0.11f), n3 = noise.snoise(p * 0.5f);
            float h = 0.03f * n3;
            for (int k = 0; k < 3; k++)
            {
                float4 m = k == 0 ? new float4(-7.5f, 6.5f, 3.2f, 1.1f) : k == 1 ? new float4(8f, -5.5f, 3.6f, 0.9f) : new float4(6.5f, 8.5f, 2.6f, 0.8f);   // (= Mounds)
                float d = math.distance(p, m.xy) / (m.z * (1f + 0.12f * n2));
                if (d < 1f) h += m.w * (0.5f + 0.5f * math.cos(d * math.PI));
            }
            int surf = math.clamp(Ground + (int)math.round(h / Voxel), 8, NY - 40);
            int soil = 8 + (int)math.round(n3 * 1.5f), clay = soil + 24 + (int)math.round(noise.snoise(p * 0.17f) * 4f);
            for (int y = 0; y < NY; y++)
            {
                int dn = surf - 1 - y;
                vox[cb + y] = y >= surf ? Air : dn < soil ? Soil : dn < clay ? Clay : Rock;
            }
            top[i] = (ushort)surf;
            bool patchy = noise.snoise(p * 0.07f) > -0.5f;
            grass[i] = (byte)(patchy ? 150 + (int)(math.hash(new int2(x >> 1, z >> 1)) % 100u) : 0);
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

        byte Get(int3 p)
        {
            if (p.y < 0) return Rock;
            if (p.x < 0 || p.z < 0 || p.x >= NX || p.z >= NZ) return p.y < Ground ? Rock : Air;   // (so the outside edge above the floor is drawn)
            return VoxelAt(vox, blocks, top, p.x, p.y, p.z);
        }

        public void Execute()
        {
            var mask = new NativeArray<byte>(CS * CS, Allocator.Temp);
            int3 b = new int3(cx, cy, cz) * CS;
            int4 blk = blocks[cx + CX * cz];
            int stride = blk.z - blk.y, cbase = blk.x - blk.y;
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
                        int start = (int)(math.hash(new int3(x, z, it + seed)) & 7u), bestX = 0, bestZ = 0, bestT = t;
                        for (int k = 0; k < 8; k++)
                        {
                            int side = (start + k) & 7;
                            int nx = x + DX[side], nz = z + DZ[side];
                            int nt = top[nx + NX * nz];
                            if (nt < bestT) { bestT = nt; bestX = nx; bestZ = nz; }
                        }
                        bool rubble = m >= LooseRock;
                        bool move = t - bestT >= (rubble ? 3 : 2);
                        if (!move && !rubble)
                        {
                            int bestDrop = 2;
                            for (int k = 0; k < 4; k++)
                            {
                                int side = ((start + k) & 3) * 2;
                                int nt1 = top[x + DX[side] + NX * (z + DZ[side])];
                                int nt3 = top[x + DX[side] * 3 + NX * (z + DZ[side] * 3)];
                                if (nt1 < t && t - nt3 > bestDrop) { bestDrop = t - nt3; bestT = nt1; bestX = x + DX[side]; bestZ = z + DZ[side]; move = true; }
                            }
                        }
                        if (!move) continue;
                        if ((math.hash(new int3(x, z, it * 31 + seed)) % 10u) == 0u) continue;
                        int nc = bestX + NX * bestZ;
                        int lo2, hi2;
                        int cb2 = ColBase(blocks, bestX, bestZ, out lo2, out hi2);
                        if (cb2 < 0) continue;
                        grass[nc] = 0;
                        int count = math.clamp((t - bestT) / 3, 1, 2);
                        for (int n = 0; n < count; n++)
                        {
                            int ty = top[c];
                            if (ty <= lo) break;
                            byte mm = vox[cb + ty - 1];
                            if (mm < LooseSoil) break;
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
