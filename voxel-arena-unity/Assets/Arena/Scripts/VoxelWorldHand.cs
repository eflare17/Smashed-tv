// What a person on foot (and a grunt, and a bullet) needs from the ground: where the floor is, what a shot would hit,
// and Pick: a ball of ground broken into loose clods.  A bullet picks a small ball; a rocket a big one, thrown outwards
// (Blast).  Copied from the Digger Game; its shovel, cart and backpack are gone.
// Volume is conserved through all of it: everything that leaves the ground is a clod or on the small tally.
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;

public partial class VoxelWorld
{
    [System.NonSerialized] public Vector3 SlumpCentre;

    void FixedUpdate()
    {
        StepDirt(Time.fixedDeltaTime);
        Slump(SlumpCentre, 6.5f, 4);
        for (int i = 0; i < blastSlumps.Count; i++)              // let the dirt round fresh craters settle too, for a few seconds
        {
            var b = blastSlumps[i];
            Slump(new Vector3(b.x, 0f, b.z), 3f, 2);
            b.y -= Time.fixedDeltaTime;
            if (b.y <= 0f) { blastSlumps.RemoveAt(i); i--; } else blastSlumps[i] = b;
        }
    }
    readonly System.Collections.Generic.List<Vector3> blastSlumps = new System.Collections.Generic.List<Vector3>();   // x, seconds left, z

    bool Cell(Vector3 p, out int x, out int y, out int z)
    {
        x = Mathf.FloorToInt((p.x - origin.x) / Voxel); y = Mathf.FloorToInt((p.y - origin.y) / Voxel); z = Mathf.FloorToInt((p.z - origin.z) / Voxel);
        return x >= 0 && z >= 0 && x < NX && z < NZ && y >= 0 && y < NY;
    }

    /// What is at this point: 0 for air.  Outside the ground the plain floor is solid below height 0.
    public byte MaterialAt(Vector3 p)
    {
        int x, y, z;
        if (!Cell(p, out x, out y, out z)) return p.y < 0f ? Soil : Air;
        return VoxelAt(vox, blocks, top, x, y, z);
    }

    /// The height of the surface a person at p would stand on: the first solid ground at or below about knee
    /// height.  If p is inside the ground it looks up a little for free space instead.  0 outside the ground.
    public float FloorAt(Vector3 p)
    {
        int x, y, z;
        if (!Cell(p, out x, out y, out z))
        {
            if (p.y >= 0f || x < 0 || z < 0 || x >= NX || z >= NZ) return 0f;
            y = 0;
        }
        int col = x + NX * z;
        if (y >= top[col]) return origin.y + top[col] * Voxel;
        int lo, hi;
        int cb = ColBase(blocks, x, z, out lo, out hi);
        if (cb < 0) return origin.y + top[col] * Voxel;
        if (y < lo) y = lo;
        if (vox[cb + y] != Air)
        {
            for (int k = 0; k < 14 && y < hi - 1 && vox[cb + y] != Air; k++) y++;
            return origin.y + y * Voxel;
        }
        while (y > lo && vox[cb + y - 1] == Air) y--;
        return origin.y + y * Voxel;
    }

    /// Walks a line through the ground and reports the first solid thing on it.
    public bool Raycast(Vector3 from, Vector3 dir, float max, out Vector3 hit, out byte mat)
    {
        dir.Normalize();
        for (float t = 0f; t <= max; t += 0.03f)
        {
            Vector3 p = from + dir * t;
            byte m = MaterialAt(p);
            if (m != Air) { hit = p; mat = m; return true; }
        }
        hit = from + dir * max; mat = Air;
        return false;
    }

    void Recount()
    {
        int carried = 0, flying = 0, n = cCount[0];
        for (int i = 0; i < bladeLoad.Length; i++) carried += bladeLoad[i];
        for (int i = 0; i < n; i++) flying += cCnt[i];
        carriedOnBlade = carried;
        ClodCount = n;
        ClodVoxelsInFlight = flying;
        LoadVoxels = carriedOnBlade + ClodVoxelsInFlight + SpilledVoxels;
    }

    /// A well-mixed random number for a voxel and a frame.
    static uint Roll(int x, int y, int z, int seed)
    {
        uint h = (uint)x * 73856093u ^ (uint)y * 19349663u ^ (uint)z * 83492791u ^ (uint)seed * 2654435761u;
        h ^= h >> 16; h *= 0x7feb352du; h ^= h >> 15; h *= 0x846ca68bu; h ^= h >> 16;
        return h;
    }

    int pickSeed;

    /// Breaks a ball of ground at `at` into loose clods that fly off with `kick`.  Rock only gives way close to the
    /// point unless `fullRock`.  `blast` (metres a second) throws each clod outwards from the middle as well, and it
    /// flies free for a moment (a rocket).  Returns how many voxels came out of the ground.
    public int Pick(Vector3 at, float radius, Vector3 kick, bool fullRock = false, float blast = 0f)
    {
        Tic();
        var result = new NativeArray<int>(2, Allocator.TempJob);
        new HandJob
        {
            vox = vox, blocks = blocks, top = top, dirty = dirty, grass = grass, tally = bladeLoad, result = result,
            centre = (at - origin) / Voxel, radius = radius / Voxel, kick = kick, origin = origin, seed = frame * 31 + (pickSeed++), fullRock = fullRock, blast = blast,
            cPos = cPos, cVel = cVel, cRot = cRot, cMat = cMat, cCnt = cCnt, cRest = cRest, cAge = cAge, cCount = cCount,
        }.Run();
        int outOfGround = result[0];
        result.Dispose();
        SolidCount -= outOfGround;
        Recount();
        if (blast > 0f) blastSlumps.Add(new Vector3(at.x, 6f, at.z));
        Toc(0);
        return outOfGround;
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct HandJob : IJob
    {
        public NativeArray<byte> vox;
        [ReadOnly] public NativeArray<int4> blocks;
        public NativeArray<ushort> top;
        public NativeArray<byte> dirty, grass;
        public NativeArray<int> tally, result;
        public float3 centre, kick, origin;
        public float radius, blast;
        public int seed;
        public bool fullRock;
        public NativeArray<float3> cPos, cVel;
        public NativeArray<quaternion> cRot;
        public NativeArray<byte> cMat, cCnt;
        public NativeArray<float> cRest, cAge;
        public NativeArray<int> cCount;

        /// A voxel comes out of the ground and joins the tally; every eighth of a material becomes a clod there.
        void Loose(byte loose, int x, int y, int z, float3 vel)
        {
            tally[loose]++;
            if (tally[loose] < ClodVoxels || cCount[0] >= MaxClods) return;
            tally[loose] -= ClodVoxels;
            int n = cCount[0]++;
            uint h = Roll(n, y, x + z, seed);
            float3 r = new float3(h & 255u, (h >> 8) & 255u, (h >> 16) & 255u) / 255f - 0.5f;
            float3 p = (new float3(x, y, z) + 0.5f);
            cPos[n] = origin + p * Voxel + r * Voxel;
            float3 v = vel + r * 1.4f;
            if (blast > 0f)
            {
                // thrown out of the crater: away from the middle and up, harder the nearer the middle it was
                float3 away = p - centre;
                float d = math.length(away);
                float3 dir = d > 1e-3f ? away / d : new float3(0f, 1f, 0f);
                dir.y = math.abs(dir.y) * 0.6f + 0.55f;
                float k = 1f - 0.55f * math.saturate(d / math.max(radius, 1f));
                float s = blast * k * (0.55f + 0.45f * (((h >> 24) & 255u) / 255f));
                v = math.normalize(dir) * s + r * 1.2f;
                cAge[n] = -0.35f;                                      // flying free: it doesn't jostle the others yet
            }
            else cAge[n] = 0f;
            cVel[n] = v;
            cRot[n] = quaternion.identity;
            cMat[n] = loose; cCnt[n] = ClodVoxels; cRest[n] = 0f;
        }

        public void Execute()
        {
            int outOfGround = 0;
            int3 a = math.clamp((int3)math.floor(centre - radius), new int3(Rim + 6, 1, Rim + 6), new int3(NX - 7 - Rim, NY - 2, NZ - 7 - Rim));
            int3 b = math.clamp((int3)math.ceil(centre + radius), new int3(Rim + 6, 1, Rim + 6), new int3(NX - 7 - Rim, NY - 2, NZ - 7 - Rim));
            for (int z = a.z; z <= b.z; z++)
                for (int x = a.x; x <= b.x; x++)
                {
                    int col = x + NX * z;
                    int lo, hi;
                    int cb = ColBase(blocks, x, z, out lo, out hi);
                    if (cb < 0) continue;
                    int highest = -1;
                    for (int y = math.min(b.y, hi - 2); y >= math.max(a.y, lo + 1); y--)
                    {
                        float d2 = math.distancesq(new float3(x, y, z) + 0.5f, centre);
                        if (d2 > radius * radius) continue;
                        byte m = vox[cb + y];
                        if (m == Air) continue;
                        bool hard = m >= Rock && m <= Gold;
                        if (hard && !fullRock && d2 > radius * radius * 0.42f) continue;      // rock only breaks near the point
                        vox[cb + y] = Air;
                        Mark(ref dirty, x, y, z);
                        Loose(Loosen(m), x, y, z, kick);
                        outOfGround++;
                        if (highest < 0) highest = y;
                    }
                    if (highest < 0) continue;
                    // loose dirt that was sitting on what just went has nothing under it now: it falls as clods
                    for (int y = highest + 1; y < hi - 1; y++)
                    {
                        byte m = vox[cb + y];
                        if (m < LooseSoil) break;
                        vox[cb + y] = Air;
                        Mark(ref dirty, x, y, z);
                        Loose(m, x, y, z, float3.zero);
                        outOfGround++;
                    }
                    int t = top[col];
                    if (t > lo && vox[cb + t - 1] == Air)
                    {
                        while (t > lo && vox[cb + t - 1] == Air) t--;
                        top[col] = (ushort)t;
                    }
                    grass[col] = 0;
                }
            result[0] = outOfGround;
        }
    }
}
