// Loose dirt as real moving clods (copied from the Digger Game; the blade, cart and backpack parts are gone).
//
// When ground is blown or chipped out, the dirt becomes clods: small bodies that fly, fall under gravity, rest on
// the ground and on each other.  A clod that has come to rest turns back into ground (voxels).
//
// Each clod stands for 8 voxels of one material, so volume is exactly conserved:
//     ground voxels + voxels on the small tally + 8 x clods  =  constant.
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

public partial class VoxelWorld
{
    public const int MaxClods = 40000;
    public const int ClodVoxels = 8;                        // a clod is two voxels across
    public const float ClodRadius = Voxel;                  // so its radius is one voxel

    public int ClodCount { get; private set; }
    public int ClodVoxelsInFlight { get; private set; }     // (set by StepDirt and Recount)
    /// Dirt that left the ground for good (none can, in the arena: kept so the books read the same as the Digger Game's).
    public int SpilledVoxels { get; private set; }

    NativeArray<float3> cPos, cVel, cPrev, cDelta;
    NativeArray<quaternion> cRot;
    NativeArray<byte> cMat, cCnt, cGround;
    NativeArray<float> cRest, cAge;
    NativeArray<int> cContacts, cCount, cellStart, cellFill, cSorted;
    NativeArray<Matrix4x4>[] drawMats;
    NativeArray<int> drawCounts;
    Material[] clodMaterials;
    Mesh clodMesh;
    const int HashSize = 1 << 16;

    static readonly Color[] ClodColours =
    {
        new Color(0.74f, 0.60f, 0.42f), new Color(0.82f, 0.52f, 0.24f), new Color(0.74f, 0.72f, 0.68f),
        new Color(0.80f, 0.80f, 0.78f), new Color(0.92f, 0.68f, 0.10f),
    };

    void InitDirt()
    {
        cPos = new NativeArray<float3>(MaxClods, Allocator.Persistent);
        cVel = new NativeArray<float3>(MaxClods, Allocator.Persistent);
        cPrev = new NativeArray<float3>(MaxClods, Allocator.Persistent);
        cDelta = new NativeArray<float3>(MaxClods, Allocator.Persistent);
        cRot = new NativeArray<quaternion>(MaxClods, Allocator.Persistent);
        cMat = new NativeArray<byte>(MaxClods, Allocator.Persistent);
        cCnt = new NativeArray<byte>(MaxClods, Allocator.Persistent);
        cGround = new NativeArray<byte>(MaxClods, Allocator.Persistent);
        cRest = new NativeArray<float>(MaxClods, Allocator.Persistent);
        cAge = new NativeArray<float>(MaxClods, Allocator.Persistent);
        cContacts = new NativeArray<int>(MaxClods, Allocator.Persistent);
        cSorted = new NativeArray<int>(MaxClods, Allocator.Persistent);
        cCount = new NativeArray<int>(1, Allocator.Persistent);
        cellStart = new NativeArray<int>(HashSize + 1, Allocator.Persistent);
        cellFill = new NativeArray<int>(HashSize, Allocator.Persistent);
        drawCounts = new NativeArray<int>(5, Allocator.Persistent);
        drawMats = new NativeArray<Matrix4x4>[5];
        clodMaterials = new Material[5];
        var shader = Shader.Find("Standard");
        for (int i = 0; i < 5; i++)
        {
            drawMats[i] = new NativeArray<Matrix4x4>(MaxClods, Allocator.Persistent);
            clodMaterials[i] = new Material(shader) { color = ClodColours[i], enableInstancing = true };
            clodMaterials[i].SetFloat("_Glossiness", 0.05f);
        }
        var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        clodMesh = cube.GetComponent<MeshFilter>().sharedMesh;
        Destroy(cube);
    }

    /// Every clod goes (a fresh round).
    void ClearDirt()
    {
        cCount[0] = 0; ClodCount = 0; ClodVoxelsInFlight = 0; SpilledVoxels = 0;
    }

    void DisposeDirt()
    {
        if (!cPos.IsCreated) return;
        cPos.Dispose(); cVel.Dispose(); cPrev.Dispose(); cDelta.Dispose(); cRot.Dispose();
        cMat.Dispose(); cCnt.Dispose(); cGround.Dispose(); cRest.Dispose(); cAge.Dispose(); cContacts.Dispose(); cSorted.Dispose();
        cCount.Dispose(); cellStart.Dispose(); cellFill.Dispose(); drawCounts.Dispose();
        for (int i = 0; i < 5; i++) drawMats[i].Dispose();
    }

    /// Moves every clod on by one physics step.
    public void StepDirt(float dt)
    {
        Tic();
        var result = new NativeArray<int>(4, Allocator.TempJob);
        int n = cCount[0];
        JobHandle h = default;
        if (n > 0)
        {
            int subs = n > 6000 ? DirtSub - 1 : DirtSub;              // a very big heap gets coarser steps to keep the game smooth
            int passes = n > 7000 ? DirtIter - 1 : DirtIter;
            float sdt = dt / subs;
            for (int sub = 0; sub < subs; sub++)
            {
                h = new ClodMoveJob { pos = cPos, vel = cVel, prev = cPrev, contacts = cContacts, ground = cGround, origin = origin, sdt = sdt }.Schedule(n, 256, h);
                h = new ClodGridJob { pos = cPos, cellStart = cellStart, cellFill = cellFill, sorted = cSorted, n = n }.Schedule(h);
                for (int it = 0; it < passes; it++)
                {
                    h = new ClodPushJob { pos = cPos, age = cAge, cellStart = cellStart, sorted = cSorted, delta = cDelta, contacts = cContacts }.Schedule(n, 128, h);
                    h = new ClodSolveJob { vox = vox, blocks = blocks, top = top, pos = cPos, prev = cPrev, delta = cDelta, ground = cGround, origin = origin }.Schedule(n, 256, h);
                }
                h = new ClodSpeedJob { pos = cPos, prev = cPrev, vel = cVel, age = cAge, contacts = cContacts, ground = cGround, sdt = sdt, passes = passes }.Schedule(n, 256, h);
            }
        }
        h = new DirtStepJob
        {
            vox = vox, blocks = blocks, top = top, dirty = dirty, grass = grass,
            pos = cPos, vel = cVel, rot = cRot, mat = cMat, cnt = cCnt, ground = cGround,
            rest = cRest, age = cAge, contacts = cContacts, count = cCount,
            origin = origin, dt = dt, result = result, seed = frame,
        }.Schedule(h);
        h.Complete();
        SolidCount += result[0];
        ClodVoxelsInFlight = result[1];
        SpilledVoxels += result[2];
        ClodCount = cCount[0];
        LoadVoxels = carriedOnBlade + ClodVoxelsInFlight + SpilledVoxels;
        result.Dispose();
        Toc(1);
    }

    void DrawDirt()
    {
        int n = cCount[0];
        if (n == 0) return;
        new DirtDrawJob { pos = cPos, rot = cRot, mat = cMat, n = n, counts = drawCounts,
                          m0 = drawMats[0], m1 = drawMats[1], m2 = drawMats[2], m3 = drawMats[3], m4 = drawMats[4] }.Run();
        var bounds = new Bounds(origin + new Vector3(NX, NY, NZ) * (Voxel * 0.5f), new Vector3(NX * Voxel, NY * Voxel + 10f, NZ * Voxel));
        for (int i = 0; i < 5; i++)
        {
            var rp = new RenderParams(clodMaterials[i]) { worldBounds = bounds, shadowCastingMode = ShadowCastingMode.On, receiveShadows = true };
            for (int start = 0; start < drawCounts[i]; start += 1023)
                Graphics.RenderMeshInstanced(rp, clodMesh, 0, drawMats[i], Mathf.Min(1023, drawCounts[i] - start), start);
        }
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct DirtDrawJob : IJob
    {
        [ReadOnly] public NativeArray<float3> pos;
        [ReadOnly] public NativeArray<quaternion> rot;
        [ReadOnly] public NativeArray<byte> mat;
        public NativeArray<int> counts;
        public NativeArray<Matrix4x4> m0, m1, m2, m3, m4;
        public int n;

        public void Execute()
        {
            for (int i = 0; i < 5; i++) counts[i] = 0;
            float size = ClodRadius * 1.9f;
            for (int i = 0; i < n; i++)
            {
                int b = math.clamp(mat[i] - LooseSoil, 0, 4);
                Matrix4x4 m = float4x4.TRS(pos[i], rot[i], new float3(size));
                int k = counts[b]++;
                switch (b) { case 0: m0[k] = m; break; case 1: m1[k] = m; break; case 2: m2[k] = m; break; case 3: m3[k] = m; break; default: m4[k] = m; break; }
            }
        }
    }

    // ---- the clods' small steps, each spread over the CPU's cores
    const int DirtSub = 3;
    const int DirtIter = 3;
    const float WallStep = 0.2f;                             // a rise taller than this is a wall, not a bump
    const float GroundFriction = 0.72f;                      // sideways speed kept each small step while on the ground
    const float ClodFriction = 0.93f;                        // and while rubbing against other clods
    const float StickSpeed = 0.11f;                          // slower than this while held up, and it stays put
    const float MaxSpeed = 5.0f;
    const float MaxRise = 1.2f;
    const int DirtLo = Rim + 6;

    static int CellKey(int3 c) { return (int)(math.hash(c) & (HashSize - 1)); }

    /// The voxel layer a clod at p would come to rest on: the top of the first solid ground at or below it.
    static int FloorIndexOf(NativeArray<byte> vox, NativeArray<int4> blocks, NativeArray<ushort> top, float3 origin, float3 p)
    {
        int ix = (int)math.floor((p.x - origin.x) / Voxel), iz = (int)math.floor((p.z - origin.z) / Voxel);
        if (ix < 0 || iz < 0 || ix >= NX || iz >= NZ) return Ground;
        int col = ix + NX * iz;
        int t = top[col];
        int y = (int)math.floor((p.y - origin.y) / Voxel) + 1;
        if (y >= t) return t;
        int lo, hi;
        int cb = ColBase(blocks, ix, iz, out lo, out hi);
        if (cb < 0) return t;
        if (y < lo + 1) y = lo + 1;
        if (vox[cb + y] != Air)
        {
            for (int k = 0; k < 10 && y < hi - 1 && vox[cb + y] != Air; k++) y++;
            return y;
        }
        while (y > lo && vox[cb + y - 1] == Air) y--;
        return y;
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct ClodMoveJob : IJobParallelFor
    {
        public NativeArray<float3> pos, vel, prev;
        public NativeArray<int> contacts;
        public NativeArray<byte> ground;
        public float3 origin;
        public float sdt;
        public void Execute(int i)
        {
            float xMin = origin.x + DirtLo * Voxel, xMax = origin.x + (NX - DirtLo) * Voxel;
            float zMin = origin.z + DirtLo * Voxel, zMax = origin.z + (NZ - DirtLo) * Voxel;
            prev[i] = pos[i];
            float3 v = vel[i];
            v.y -= 9.81f * sdt;
            float3 p = pos[i] + v * sdt;
            p.x = math.clamp(p.x, xMin, xMax); p.z = math.clamp(p.z, zMin, zMax);   // clods stay inside the walls
            pos[i] = p;
            contacts[i] = 0; ground[i] = 0;
        }
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct ClodGridJob : IJob
    {
        [ReadOnly] public NativeArray<float3> pos;
        public NativeArray<int> cellStart, cellFill, sorted;
        public int n;
        public unsafe void Execute()
        {
            float inv = 1f / (2f * ClodRadius);
            Unity.Collections.LowLevel.Unsafe.UnsafeUtility.MemClear(
                Unity.Collections.LowLevel.Unsafe.NativeArrayUnsafeUtility.GetUnsafePtr(cellStart), (long)cellStart.Length * 4);
            for (int i = 0; i < n; i++) cellStart[CellKey((int3)math.floor(pos[i] * inv)) + 1]++;
            for (int k = 0; k < HashSize; k++) { cellStart[k + 1] += cellStart[k]; cellFill[k] = cellStart[k]; }
            for (int i = 0; i < n; i++) sorted[cellFill[CellKey((int3)math.floor(pos[i] * inv))]++] = i;
        }
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct ClodPushJob : IJobParallelFor
    {
        [ReadOnly] public NativeArray<float3> pos;
        [ReadOnly] public NativeArray<float> age;
        [ReadOnly] public NativeArray<int> cellStart, sorted;
        public NativeArray<float3> delta;
        public NativeArray<int> contacts;
        public void Execute(int i)
        {
            const float R = ClodRadius;
            float inv = 1f / (2f * R);
            float3 p = pos[i], push = float3.zero;
            int touching = 0;
            if (age[i] >= 0f)                                        // a thrown bunch flies together: its clods don't shove each other apart in the air
            {
                int3 c = (int3)math.floor(p * inv);
                int budget = 28;
                for (int dz = -1; dz <= 1 && budget > 0; dz++)
                    for (int dy = -1; dy <= 1; dy++)
                        for (int dx = -1; dx <= 1; dx++)
                        {
                            int key = CellKey(c + new int3(dx, dy, dz));
                            for (int a = cellStart[key]; a < cellStart[key + 1]; a++)
                            {
                                int j = sorted[a];
                                if (j == i || age[j] < 0f) continue;
                                float3 d = pos[j] - p;
                                float d2 = math.lengthsq(d);
                                if (d2 >= 4f * R * R || d2 < 1e-10f) continue;
                                float dist = math.sqrt(d2);
                                push -= d / dist * ((2f * R - dist) * 0.5f);
                                touching++;
                                if (--budget <= 0) break;
                            }
                        }
            }
            delta[i] = push;
            contacts[i] = contacts[i] + touching;
        }
    }

    /// Each clod takes its push and rests on the ground (a tall rise is a wall).
    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct ClodSolveJob : IJobParallelFor
    {
        [ReadOnly] public NativeArray<byte> vox;
        [ReadOnly] public NativeArray<int4> blocks;
        [ReadOnly] public NativeArray<ushort> top;
        [ReadOnly] public NativeArray<float3> prev, delta;
        public NativeArray<float3> pos;
        public NativeArray<byte> ground;
        public float3 origin;
        public void Execute(int i)
        {
            const float R = ClodRadius;
            float xMin = origin.x + DirtLo * Voxel, xMax = origin.x + (NX - DirtLo) * Voxel;
            float zMin = origin.z + DirtLo * Voxel, zMax = origin.z + (NZ - DirtLo) * Voxel;
            float3 p = pos[i] + delta[i] * 0.7f;
            p.x = math.clamp(p.x, xMin, xMax); p.z = math.clamp(p.z, zMin, zMax);
            float h = origin.y + FloorIndexOf(vox, blocks, top, origin, p) * Voxel;
            if (p.y - R < h)
            {
                if (h + R - p.y > WallStep)
                {
                    float hp = origin.y + FloorIndexOf(vox, blocks, top, origin, new float3(prev[i].x, p.y, prev[i].z)) * Voxel;
                    if (hp < h) { p.x = prev[i].x; p.z = prev[i].z; h = hp; }
                }
                if (p.y - R < h) { p.y = h + R; ground[i] = 1; }
            }
            pos[i] = p;
        }
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct ClodSpeedJob : IJobParallelFor
    {
        [ReadOnly] public NativeArray<float3> prev;
        [ReadOnly] public NativeArray<float> age;
        [ReadOnly] public NativeArray<int> contacts;
        [ReadOnly] public NativeArray<byte> ground;
        public NativeArray<float3> pos, vel;
        public float sdt;
        public int passes;
        public void Execute(int i)
        {
            float3 v = (pos[i] - prev[i]) / sdt;
            bool thrown = age[i] < 0f;                                  // blown out by a blast: it flies free for a moment
            float sp = math.length(v), most = thrown ? 16f : MaxSpeed;
            if (sp > most) v *= most / sp;
            if (v.y > (thrown ? 10f : MaxRise)) v.y = thrown ? 10f : MaxRise;
            bool held = ground[i] != 0 || contacts[i] >= 2 * passes;
            if (ground[i] != 0) { v.x *= GroundFriction; v.z *= GroundFriction; }
            else if (contacts[i] > 0) { v *= ClodFriction; }
            if (held && math.lengthsq(v) < StickSpeed * StickSpeed)
            {
                v = float3.zero;
                pos[i] = new float3(prev[i].x, pos[i].y, prev[i].z);
            }
            vel[i] = v;
        }
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct DirtStepJob : IJob
    {
        public NativeArray<byte> vox;
        [ReadOnly] public NativeArray<int4> blocks;
        public NativeArray<ushort> top;
        public NativeArray<byte> dirty;
        public NativeArray<byte> grass;
        public NativeArray<float3> pos, vel;
        public NativeArray<quaternion> rot;
        public NativeArray<byte> mat, cnt, ground;
        public NativeArray<float> rest, age;
        public NativeArray<int> contacts, count, result;
        public float3 origin;
        public float dt;
        public int seed;

        const float R = ClodRadius;
        const float RestTime = 0.35f;                         // seconds at rest before a clod becomes ground again
        const float SettleAfter = 2.5f;                       // at the latest this long after it came loose, moving or not
        const int Lo = Rim + 6;

        int FloorIndex(float3 p) { return FloorIndexOf(vox, blocks, top, origin, p); }

        public void Execute()
        {
            int n = count[0];
            int placed = 0, spilled = 0;
            if (n > 0)
            {
                for (int i = n - 1; i >= 0; i--)
                {
                    float3 v = vel[i];
                    float speed = math.length(v);
                    if (speed > 0.05f)
                    {
                        float3 axis = math.cross(new float3(0f, 1f, 0f), v / speed);
                        if (math.lengthsq(axis) > 1e-6f)
                            rot[i] = math.mul(quaternion.AxisAngle(math.normalize(axis), speed * dt / R * 0.6f), rot[i]);
                    }
                    bool held = ground[i] != 0 || contacts[i] >= 2;
                    rest[i] = (held && speed < 0.3f) ? rest[i] + dt : 0f;
                    age[i] += dt;
                    bool timeUp = age[i] > SettleAfter && (held || speed < 1.5f || age[i] > SettleAfter * 2f);
                    if (rest[i] < RestTime && !timeUp) continue;

                    // put its voxels down on the four columns under it
                    int cx = math.clamp((int)math.floor((pos[i].x - origin.x) / Voxel - 0.5f), Lo, NX - 2 - Lo);
                    int cz = math.clamp((int)math.floor((pos[i].z - origin.z) / Voxel - 0.5f), Lo, NZ - 2 - Lo);
                    int left = cnt[i], start = (i + seed) & 3;
                    for (int q = 0; q < 16 && left > 0; q++)
                    {
                        int k = (start + q) & 3;
                        int x = cx + (k & 1), z = cz + (k >> 1);
                        int col = x + NX * z;
                        int lo, hi;
                        int cb = ColBase(blocks, x, z, out lo, out hi);
                        if (cb < 0) { left--; spilled++; continue; }
                        int t = FloorIndex(new float3(origin.x + (x + 0.5f) * Voxel, pos[i].y, origin.z + (z + 0.5f) * Voxel));
                        if (t >= hi - 1 || t < lo || vox[cb + t] != Air) continue;
                        vox[cb + t] = mat[i];
                        if (t >= top[col]) { top[col] = (ushort)(t + 1); grass[col] = 0; }
                        Mark(ref dirty, x, t, z);
                        left--; placed++;
                    }
                    if (left > 0) { cnt[i] = (byte)left; rest[i] = 0f; continue; }
                    n--;
                    pos[i] = pos[n]; vel[i] = vel[n]; rot[i] = rot[n]; mat[i] = mat[n]; cnt[i] = cnt[n]; rest[i] = rest[n]; age[i] = age[n];
                    ground[i] = ground[n]; contacts[i] = contacts[n];
                }
            }
            int flying = 0;
            for (int i = 0; i < n; i++) flying += cnt[i];
            count[0] = n;
            result[0] = placed; result[1] = flying; result[2] = spilled; result[3] = 0;
        }
    }
}
