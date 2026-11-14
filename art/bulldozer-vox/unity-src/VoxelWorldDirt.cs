// Loose dirt as real moving clods.
//
// When the blade cuts ground, the dirt does not get placed anywhere by rule.  It becomes clods: small
// bodies that fall under gravity, rest on the ground and on each other, and get shoved by the blade.
// Nothing tells them where to go.  A heap in front of the blade, dirt rolling off the ends of it, a
// rounded top, a ridge left along the cut: all of that comes from clods pushing on clods.
//
// A clod that has come to rest turns back into ground (voxels), so the pile it was part of stays as
// terrain.  When the blade reaches that ground again, it becomes clods again.
//
// Each clod stands for 8 voxels of one material, so volume is exactly conserved:
//     ground voxels + voxels on the blade's tally + 8 x clods  =  constant.
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
    public int ClodVoxelsInFlight { get; private set; }

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
        if (GetComponent<SiteProps>() == null) gameObject.AddComponent<SiteProps>();   // the scenery: mine entrance, rails, trees
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

    void DisposeDirt()
    {
        if (!cPos.IsCreated) return;
        cPos.Dispose(); cVel.Dispose(); cPrev.Dispose(); cDelta.Dispose(); cRot.Dispose();
        cMat.Dispose(); cCnt.Dispose(); cGround.Dispose(); cRest.Dispose(); cAge.Dispose(); cContacts.Dispose(); cSorted.Dispose();
        cCount.Dispose(); cellStart.Dispose(); cellFill.Dispose(); drawCounts.Dispose();
        for (int i = 0; i < 5; i++) drawMats[i].Dispose();
    }

    /// Moves every clod on by one physics step.  The blade is a solid plate (plateMin / plateMax in its own space).
    public void StepDirt(Matrix4x4 bladeToWorld, Vector3 plateMin, Vector3 plateMax, bool hasBlade, float dt)
    {
        Tic();
        var result = new NativeArray<int>(2, Allocator.TempJob);
        new DirtStepJob
        {
            vox = vox, top = top, dirty = dirty, grass = grass,
            pos = cPos, vel = cVel, prev = cPrev, delta = cDelta, rot = cRot, mat = cMat, cnt = cCnt, ground = cGround,
            rest = cRest, age = cAge, contacts = cContacts, count = cCount, cellStart = cellStart, cellFill = cellFill, sorted = cSorted,
            bladeToWorld = bladeToWorld, worldToBlade = bladeToWorld.inverse, plateMin = plateMin, plateMax = plateMax,
            hasBlade = hasBlade, origin = origin, dt = dt, result = result, seed = frame,
        }.Run();
        SolidCount += result[0];
        ClodVoxelsInFlight = result[1];
        ClodCount = cCount[0];
        BermVoxels = ClodVoxelsInFlight;
        LoadVoxels = carriedOnBlade + ClodVoxelsInFlight + ShovelVoxels + CartVoxels;
        result.Dispose();
        Toc(1);
    }

    // colours for the blade-view pictures: air is handled separately, then soil, clay, rock, quartz, gold and their loose forms
    static readonly Color32[] SliceColours =
    {
        new Color32(0, 0, 0, 255),
        new Color32(189, 153, 107, 255), new Color32(204, 120, 41, 255), new Color32(112, 115, 122, 255),
        new Color32(230, 230, 224, 255), new Color32(250, 194, 31, 255),
        new Color32(153, 117, 77, 255), new Color32(179, 97, 33, 255), new Color32(161, 156, 145, 255),
        new Color32(204, 204, 199, 255), new Color32(235, 173, 26, 255),
    };

    /// Paints a flat slice through the ground into a picture, one voxel per pixel: what material is at each
    /// point of a plane (centre, with axisU across the picture and axisV up it), then the loose clods that
    /// lie within clodDepth either side of that plane.  Used by the blade view.
    public void RenderSlice(Color32[] px, int w, int h, Vector3 centre, Vector3 axisU, Vector3 axisV, float mpp, Vector3 normal, float clodDepth)
    {
        for (int j = 0; j < h; j++)
        {
            float t = j / (float)h;
            var sky = new Color32((byte)(70 + 60 * t), (byte)(100 + 60 * t), (byte)(140 + 60 * t), 255);
            for (int i = 0; i < w; i++)
            {
                Vector3 p = centre + axisU * ((i - w * 0.5f + 0.5f) * mpp) + axisV * ((j - h * 0.5f + 0.5f) * mpp);
                int x = Mathf.FloorToInt((p.x - origin.x) / Voxel), y = Mathf.FloorToInt((p.y - origin.y) / Voxel), z = Mathf.FloorToInt((p.z - origin.z) / Voxel);
                byte m;
                if (y >= NY) m = Air;
                else if (x < 0 || z < 0 || x >= NX || z >= NZ || y < 0) m = y < Ground ? Soil : Air;       // plain ground outside the site
                else m = vox[y + NY * (x + NX * z)];
                Color32 c = m == Air ? sky : SliceColours[m];
                if (m != Air && ((x * 7 + y * 13 + z * 5) & 3) == 0) { c.r = (byte)(c.r * 0.88f); c.g = (byte)(c.g * 0.88f); c.b = (byte)(c.b * 0.88f); }
                px[i + j * w] = c;
            }
        }
        int n = cCount[0];
        for (int k = 0; k < n; k++)
        {
            Vector3 d = (Vector3)cPos[k] - centre;
            if (Mathf.Abs(Vector3.Dot(d, normal)) > clodDepth) continue;
            int u = Mathf.RoundToInt(Vector3.Dot(d, axisU) / mpp + w * 0.5f - 1f), v = Mathf.RoundToInt(Vector3.Dot(d, axisV) / mpp + h * 0.5f - 1f);
            Color32 c = SliceColours[Mathf.Clamp(cMat[k], LooseSoil, LooseGold)];
            for (int dv = 0; dv < 2; dv++)
                for (int du = 0; du < 2; du++)
                    if (u + du >= 0 && v + dv >= 0 && u + du < w && v + dv < h) px[u + du + (v + dv) * w] = c;
        }
    }

    void DrawDirt()
    {
        int n = cCount[0];
        if (n == 0) return;
        new DirtDrawJob { pos = cPos, rot = cRot, mat = cMat, n = n, counts = drawCounts,
                          m0 = drawMats[0], m1 = drawMats[1], m2 = drawMats[2], m3 = drawMats[3], m4 = drawMats[4] }.Run();
        var bounds = new Bounds(Vector3.zero, new Vector3(NX * Voxel, 40f, NZ * Voxel));
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

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct DirtStepJob : IJob
    {
        public NativeArray<byte> vox;
        public NativeArray<ushort> top;
        public NativeArray<byte> dirty;
        public NativeArray<byte> grass;
        public NativeArray<float3> pos, vel, prev, delta;
        public NativeArray<quaternion> rot;
        public NativeArray<byte> mat, cnt, ground;
        public NativeArray<float> rest, age;
        public NativeArray<int> contacts, count, cellStart, cellFill, sorted, result;
        public float4x4 bladeToWorld, worldToBlade;
        public float3 plateMin, plateMax, origin;
        public bool hasBlade;
        public float dt;
        public int seed;

        const int Sub = 3;                                   // small steps keep a pushed heap from squashing
        const int Iter = 3;
        const float R = ClodRadius;
        const float WallStep = 0.2f;                         // a rise taller than this is a wall, not a bump
        const float GroundFriction = 0.72f;                  // sideways speed kept each small step while on the ground
        const float ClodFriction = 0.93f;                    // and while rubbing against other clods
        const float StickSpeed = 0.11f;                      // slower than this while held up, and it stays put (this sets how steep a heap stands)
        const float MaxSpeed = 4.2f;                          // metres a second (the dozer does 3)
        const float MaxRise = 1.2f;
        const float RestTime = 0.35f;
        const float SettleAfter = 2.5f;                       // seconds since the blade last touched it: then it settles, moving or not                        // seconds at rest before a clod becomes ground again
        const int Lo = Rim + 6;

        /// The voxel layer a clod at p would come to rest on: the top of the first solid ground at or below it.
        /// Under open sky that is just the column's top.  Under a roof (in the mine) it looks down from the clod.
        int FloorIndex(float3 p)
        {
            int ix = (int)math.floor((p.x - origin.x) / Voxel), iz = (int)math.floor((p.z - origin.z) / Voxel);
            if (ix < 0 || iz < 0 || ix >= NX || iz >= NZ) return Ground;
            int col = ix + NX * iz;
            int t = top[col];
            int y = (int)math.floor((p.y - origin.y) / Voxel) + 1;
            if (y >= t) return t;
            if (y < 1) y = 1;
            if (vox[y + NY * col] != Air)
            {
                for (int k = 0; k < 10 && y < NY - 1 && vox[y + NY * col] != Air; k++) y++;   // inside the ground: up to free space
                return y;
            }
            while (y > 0 && vox[y - 1 + NY * col] == Air) y--;
            return y;
        }

        float Floor(float3 p) { return origin.y + FloorIndex(p) * Voxel; }

        int Key(int3 c) { return (int)(math.hash(c) & (HashSize - 1)); }

        static unsafe void UnsafeClear(NativeArray<int> a)
        {
            Unity.Collections.LowLevel.Unsafe.UnsafeUtility.MemClear(
                Unity.Collections.LowLevel.Unsafe.NativeArrayUnsafeUtility.GetUnsafePtr(a), (long)a.Length * 4);
        }

        public void Execute()
        {
            int n = count[0];
            int placed = 0;
            if (n > 0)
            {
                int subs = n > 6000 ? Sub - 1 : Sub;                  // a very big heap gets coarser steps to keep the game smooth
                float sdt = dt / subs;
                float inv = 1f / (2f * R);
                float xMin = origin.x + Lo * Voxel, xMax = origin.x + (NX - Lo) * Voxel;
                float zMin = origin.z + Lo * Voxel, zMax = origin.z + (NZ - Lo) * Voxel;
                for (int s = 0; s < subs; s++)
                {
                    // fall and move
                    for (int i = 0; i < n; i++)
                    {
                        prev[i] = pos[i];
                        float3 v = vel[i];
                        v.y -= 9.81f * sdt;
                        float3 p = pos[i] + v * sdt;
                        p.x = math.clamp(p.x, xMin, xMax); p.z = math.clamp(p.z, zMin, zMax);   // clods stay on the work site
                        pos[i] = p;
                        contacts[i] = 0; ground[i] = 0;
                    }
                    // sort the clods into a grid so each only looks at its neighbours
                    UnsafeClear(cellStart);
                    for (int i = 0; i < n; i++) cellStart[Key((int3)math.floor(pos[i] * inv)) + 1]++;
                    for (int k = 0; k < HashSize; k++) { cellStart[k + 1] += cellStart[k]; cellFill[k] = cellStart[k]; }
                    for (int i = 0; i < n; i++) sorted[cellFill[Key((int3)math.floor(pos[i] * inv))]++] = i;

                    int passes = n > 7000 ? Iter - 1 : Iter;
                    for (int it = 0; it < passes; it++)
                    {
                        // clods push each other apart
                        for (int i = 0; i < n; i++) delta[i] = float3.zero;
                        for (int i = 0; i < n; i++)
                        {
                            float3 p = pos[i];
                            int3 c = (int3)math.floor(p * inv);
                            int budget = 14;                              // touching neighbours handled per clod per pass
                            for (int dz = -1; dz <= 1 && budget > 0; dz++)
                                for (int dy = -1; dy <= 1; dy++)
                                    for (int dx = -1; dx <= 1; dx++)
                                    {
                                        int key = Key(c + new int3(dx, dy, dz));
                                        for (int a = cellStart[key]; a < cellStart[key + 1]; a++)
                                        {
                                            int j = sorted[a];
                                            if (j <= i || age[i] < 0f || age[j] < 0f) continue;   // a thrown load flies as a bunch: its clods don't shove each other apart in the air
                                            float3 d = pos[j] - p;
                                            float d2 = math.lengthsq(d);
                                            if (d2 >= 4f * R * R || d2 < 1e-10f) continue;
                                            float dist = math.sqrt(d2);
                                            float3 corr = d / dist * ((2f * R - dist) * 0.5f);
                                            delta[i] -= corr; delta[j] += corr;
                                            contacts[i]++; contacts[j]++;
                                            if (--budget <= 0) break;
                                        }
                                    }
                        }
                        for (int i = 0; i < n; i++)
                        {
                            float3 p = pos[i] + delta[i] * 0.7f;

                            // the blade is a solid plate: anything inside it is shoved out of its front face
                            if (hasBlade)
                            {
                                float3 l = math.transform(worldToBlade, p);
                                if (l.x > plateMin.x - R && l.x < plateMax.x + R && l.y > plateMin.y - R && l.y < plateMax.y + R
                                    && l.z > plateMin.z - R && l.z < plateMax.z + R)
                                {
                                    l.z = plateMax.z + R;
                                    p = math.transform(bladeToWorld, l);
                                    contacts[i]++;
                                    age[i] = 0f;                          // touched by the blade: live again
                                }
                            }

                            // the ground: rest on it, and treat a tall rise as a wall
                            p.x = math.clamp(p.x, xMin, xMax); p.z = math.clamp(p.z, zMin, zMax);
                            float h = Floor(p);
                            if (p.y - R < h)
                            {
                                if (h + R - p.y > WallStep)
                                {
                                    float hp = Floor(new float3(prev[i].x, p.y, prev[i].z));
                                    if (hp < h) { p.x = prev[i].x; p.z = prev[i].z; h = hp; }
                                }
                                if (p.y - R < h) { p.y = h + R; ground[i] = 1; }
                            }
                            pos[i] = p;
                        }
                    }

                    // work out speeds from how far each clod actually got, then friction
                    for (int i = 0; i < n; i++)
                    {
                        float3 v = (pos[i] - prev[i]) / sdt;
                        // Being shoved out of the blade or out of another clod moves a clod, but must not fling it:
                        // nothing here goes faster than a brisk shove, and nothing is thrown upwards.
                        bool thrown = age[i] < 0f;                                  // just thrown from a shovel
                        float sp = math.length(v), most = thrown ? 11f : MaxSpeed;
                        if (sp > most) v *= most / sp;
                        if (v.y > (thrown ? 6f : MaxRise)) v.y = thrown ? 6f : MaxRise;
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

                // tumble, and turn clods that have come to rest back into ground
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
                    // A clod settles into the ground when it has come to rest, or, at the latest, a few seconds
                    // after the blade last touched it.  Clods in a heap jostle each other and would otherwise
                    // never quite count as stopped.  One still falling through the air is given a little longer.
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
                        // it lands on the floor under it, which in the mine is not the top of the hill above
                        int t = FloorIndex(new float3(origin.x + (x + 0.5f) * Voxel, pos[i].y, origin.z + (z + 0.5f) * Voxel));
                        if (t >= NY - 1 || vox[t + NY * col] != Air) continue;
                        vox[t + NY * col] = mat[i];
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
            result[0] = placed; result[1] = flying;
        }
    }
}
