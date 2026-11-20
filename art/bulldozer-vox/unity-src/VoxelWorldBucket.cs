// The Dingo's bucket (Dingo.cs) and the ground.  Works under a roof, in the mine, like the hand tools:
//   - BucketCut: the bucket's front slab goes through the ground.  Soil, clay and loose rubble inside it go into the
//     bucket while it has room; past that they spill out in front as clods.  Solid rock (boulders, the walls) stops it
//     and is counted.  Loose dirt that was resting on what was cut out falls as clods (a rubble face caves in as its
//     foot is dug away), stopping at air or firm ground, so the tunnel roof is never touched.
//   - BucketCollect: loose clods that end up inside the bucket go into its load.
//   - BucketPour: one clod's worth leaves the bucket (tipping).
// What is in the bucket is counted with the dirt in motion, so volume stays exact.
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;

public partial class VoxelWorld
{
    readonly int[] bucketLoad = new int[16];                 // per material (loose kinds only)
    public int BucketVoxels { get; private set; }            // what the Dingo's bucket is holding
    public int BucketLoadOf(int m) { return m >= 0 && m < bucketLoad.Length ? bucketLoad[m] : 0; }

    /// Just in front of the bucket's lip (Dingo.cs keeps it up to date): where its load goes if it has to be emptied at once.
    [System.NonSerialized] public Vector3 BucketMouth;

    public struct BucketResult { public int took, spilled, hard, firm, fell; }

    void SumBucket()
    {
        int s = 0;
        for (int i = 0; i < bucketLoad.Length; i++) s += bucketLoad[i];
        BucketVoxels = s;
    }

    /// One step of the bucket through the ground.  boxMin / boxMax: the slab that cuts, in the bucket's own space.
    /// `room`: how many more voxels the bucket takes.  `vel`: the bucket's speed (spilled clods leave with it).
    public BucketResult BucketCut(Matrix4x4 bucketToWorld, Vector3 boxMin, Vector3 boxMax, int room, Vector3 vel)
    {
        var result = new NativeArray<int>(5, Allocator.TempJob);
        var into = new NativeArray<int>(16, Allocator.TempJob);
        new BucketCutJob
        {
            vox = vox, blocks = blocks, top = top, dirty = dirty, grass = grass, tally = bladeLoad, into = into, result = result,
            toWorld = bucketToWorld, toBucket = bucketToWorld.inverse, boxMin = boxMin, boxMax = boxMax,
            origin = origin, vel = vel, room = math.max(0, room), seed = frame,
            cPos = cPos, cVel = cVel, cRot = cRot, cMat = cMat, cCnt = cCnt, cRest = cRest, cAge = cAge, cCount = cCount,
        }.Run();
        var r = new BucketResult { took = result[0], spilled = result[1], hard = result[2], firm = result[3], fell = result[4] };
        for (int m = 0; m < 16; m++) bucketLoad[m] += into[m];
        into.Dispose();
        result.Dispose();
        SolidCount -= r.took + r.spilled + r.fell;
        SumBucket();
        Recount();                                           // (LoadVoxels: StepDirt counts the new clods)
        return r;
    }

    /// Loose clods inside a box (in the bucket's own space) go into the bucket, while it has room.  Returns voxels taken.
    public int BucketCollect(Matrix4x4 worldToBucket, Vector3 min, Vector3 max, int capacity)
    {
        int n = cCount[0], took = 0;
        for (int i = n - 1; i >= 0; i--)
        {
            if (BucketVoxels + took + cCnt[i] > capacity) continue;
            Vector3 l = worldToBucket.MultiplyPoint3x4(cPos[i]);
            if (l.x < min.x || l.x > max.x || l.y < min.y || l.y > max.y || l.z < min.z || l.z > max.z) continue;
            bucketLoad[cMat[i]] += cCnt[i];
            took += cCnt[i];
            n--;
            cPos[i] = cPos[n]; cVel[i] = cVel[n]; cRot[i] = cRot[n]; cMat[i] = cMat[n]; cCnt[i] = cCnt[n]; cRest[i] = cRest[n]; cAge[i] = cAge[n];
        }
        if (took == 0) return 0;
        cCount[0] = n;
        ClodVoxelsInFlight -= took;                          // (StepDirt recounts these each step anyway)
        SumBucket();
        Recount();
        RecountLoad();
        return took;
    }

    /// One clod's worth leaves the bucket at `at` with `velocity`.  False when there is less than a clod of anything
    /// left: those last crumbs join the general tally (so nothing is lost) and the bucket reads empty.
    public bool BucketPour(Vector3 at, Vector3 velocity)
    {
        for (int m = LooseSoil; m <= LooseGold; m++)
        {
            if (bucketLoad[m] < ClodVoxels || cCount[0] >= MaxClods) continue;
            bucketLoad[m] -= ClodVoxels;
            int n = cCount[0]++;
            cPos[n] = at; cVel[n] = velocity; cRot[n] = quaternion.identity;
            cMat[n] = (byte)m; cCnt[n] = ClodVoxels; cRest[n] = 0f; cAge[n] = -0.5f;   // in free flight: the stream doesn't shove itself apart
            ClodVoxelsInFlight += ClodVoxels;
            SumBucket();
            Recount();
            RecountLoad();
            return true;
        }
        if (cCount[0] >= MaxClods) return false;
        for (int m = LooseSoil; m <= LooseGold; m++) { bladeLoad[m] += bucketLoad[m]; bucketLoad[m] = 0; }
        SumBucket();
        Recount();
        RecountLoad();
        return false;
    }

    /// Everything in the bucket pours out at once (before a save: the bucket isn't saved, its dirt is).
    public void BucketEmptyAll(Vector3 at, Vector3 velocity)
    {
        for (int k = 0; k < 100000 && BucketVoxels > 0; k++)
            if (!BucketPour(at + (Vector3)(UnityEngine.Random.insideUnitSphere * 0.2f), velocity)) break;
        if (BucketVoxels > 0) { for (int m = 0; m < 16; m++) { bladeLoad[m] += bucketLoad[m]; bucketLoad[m] = 0; } SumBucket(); Recount(); RecountLoad(); }
    }

    /// A loaded game replaces all the dirt, so whatever was in the bucket is gone with the old game.
    public void ForgetBucket() { System.Array.Clear(bucketLoad, 0, bucketLoad.Length); BucketVoxels = 0; }

    void RecountLoad()
    {
        LoadVoxels = carriedOnBlade + ClodVoxelsInFlight + ShovelVoxels + CartVoxels + PackVoxels + SoldVoxels + SpilledVoxels + BucketVoxels;
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct BucketCutJob : IJob
    {
        public NativeArray<byte> vox;
        [ReadOnly] public NativeArray<int4> blocks;
        public NativeArray<ushort> top;
        public NativeArray<byte> dirty, grass;
        public NativeArray<int> tally, into, result;
        public float4x4 toWorld, toBucket;
        public float3 boxMin, boxMax, origin, vel;
        public int room, seed;
        public NativeArray<float3> cPos, cVel;
        public NativeArray<quaternion> cRot;
        public NativeArray<byte> cMat, cCnt;
        public NativeArray<float> cRest, cAge;
        public NativeArray<int> cCount;

        void Loose(byte loose, int x, int y, int z, float3 v)
        {
            tally[loose]++;
            if (tally[loose] < ClodVoxels || cCount[0] >= MaxClods) return;
            tally[loose] -= ClodVoxels;
            int n = cCount[0]++;
            uint h = math.hash(new int3(n, seed, y));
            float3 r = new float3(h & 255u, (h >> 8) & 255u, (h >> 16) & 255u) / 255f - 0.5f;
            cPos[n] = origin + (new float3(x, y, z) + 0.5f) * Voxel + r * Voxel;
            cVel[n] = v + r * 0.8f;
            cRot[n] = quaternion.identity;
            cMat[n] = loose; cCnt[n] = ClodVoxels; cRest[n] = 0f; cAge[n] = 0f;
        }

        public void Execute()
        {
            float3 lo = new float3(1e9f), hi = new float3(-1e9f);
            for (int c = 0; c < 8; c++)
            {
                float3 corner = new float3((c & 1) == 0 ? boxMin.x : boxMax.x, (c & 2) == 0 ? boxMin.y : boxMax.y, (c & 4) == 0 ? boxMin.z : boxMax.z);
                float3 wv = (math.transform(toWorld, corner) - origin) / Voxel;
                lo = math.min(lo, wv); hi = math.max(hi, wv);
            }
            int3 a = math.clamp((int3)math.floor(lo), new int3(Rim + 6, 1, Rim + 6), new int3(NX - 7 - Rim, NY - 2, NZ - 7 - Rim));
            int3 b = math.clamp((int3)math.ceil(hi), new int3(Rim + 6, 1, Rim + 6), new int3(NX - 7 - Rim, NY - 2, NZ - 7 - Rim));
            int took = 0, spilled = 0, hard = 0, firm = 0, fell = 0;
            for (int z = a.z; z <= b.z; z++)
                for (int x = a.x; x <= b.x; x++)
                {
                    int col = x + NX * z;
                    int vlo, vhi;
                    int cb = ColBase(blocks, x, z, out vlo, out vhi);
                    if (cb < 0) continue;
                    int highest = -1;
                    for (int y = math.max(a.y, vlo + 1); y <= math.min(b.y, vhi - 2); y++)
                    {
                        byte m = vox[cb + y];
                        if (m == Air) continue;
                        float3 l = math.transform(toBucket, origin + (new float3(x, y, z) + 0.5f) * Voxel);
                        if (l.x < boxMin.x || l.x > boxMax.x || l.y < boxMin.y || l.y > boxMax.y || l.z < boxMin.z || l.z > boxMax.z) continue;
                        if (m >= Rock && m <= Gold) { hard++; continue; }
                        vox[cb + y] = Air;
                        Mark(ref dirty, x, y, z);
                        byte lm = Loosen(m);
                        if (m < LooseSoil) firm++;
                        if (took < room) { into[lm] = into[lm] + 1; took++; }
                        else { Loose(lm, x, y, z, vel); spilled++; }
                        highest = math.max(highest, y);
                    }
                    if (highest < 0) continue;
                    grass[col] = 0;
                    // loose dirt that sat on what was dug out has nothing under it now: it falls as clods
                    for (int y = highest + 1; y < vhi - 1; y++)
                    {
                        byte m = vox[cb + y];
                        if (m < LooseSoil) break;                    // air, or firm ground: stop (never the roof)
                        vox[cb + y] = Air;
                        Mark(ref dirty, x, y, z);
                        Loose(m, x, y, z, float3.zero);
                        fell++;
                    }
                    int t = top[col];
                    if (t > vlo && vox[cb + t - 1] == Air)
                    {
                        while (t > vlo && vox[cb + t - 1] == Air) t--;
                        top[col] = (ushort)t;
                    }
                }
            result[0] = took; result[1] = spilled; result[2] = hard; result[3] = firm; result[4] = fell;
        }
    }
}
