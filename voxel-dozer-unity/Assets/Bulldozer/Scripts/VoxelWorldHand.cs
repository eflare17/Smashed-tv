// What a person on foot needs from the ground: where the floor is (including under a roof, in the mine),
// what a pick or shovel would hit, and the pick, scoop and throw themselves.
//
// The hand tools work anywhere, underground included.  They never assume open sky above:
//   - the pick breaks a small ball of ground into loose clods;
//   - the shovel takes loose dirt (and a little firm soil) onto its load, and takes loose clods lying there;
//   - anything loose that was resting on what got removed lets go and falls as clods;
//   - a throw turns the shovel's load back into clods, in the air.
//   - the backpack sucks up loose dirt: it lets go of the ground as clods that fly into the nozzle, and
//     squirts its load back out as clods (into the cart).
// Volume is conserved through all of it: what is on the shovel or in the backpack is counted with the dirt in motion.
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;

public partial class VoxelWorld
{
    public int ShovelVoxels { get; private set; }           // what the shovel is holding
    public int CartVoxels { get; private set; }             // what the mine cart is holding
    public int PackVoxels { get; private set; }             // what the worker's backpack is holding
    NativeArray<int> shovelLoad, cartLoad, packLoad;         // per material

    // the blade as a solid plate for the clods, and where loose dirt is being smoothed; set by whoever is working
    Matrix4x4 plateToWorld = Matrix4x4.identity;
    Vector3 plateMin, plateMax;
    bool havePlate, plateMoving;
    [System.NonSerialized] public Vector3 SlumpCentre;

    /// The blade as a solid plate for the clods.  `moving`: whether it moved this step.  Only a moving blade
    /// keeps the clods it touches stirred up; against a still one they settle into ground like any other.
    public void SetBlade(Matrix4x4 bladeToWorld, Vector3 min, Vector3 max, bool moving = true) { plateToWorld = bladeToWorld; plateMin = min; plateMax = max; havePlate = true; plateMoving = moving; }

    void InitHand() { shovelLoad = new NativeArray<int>(16, Allocator.Persistent); cartLoad = new NativeArray<int>(16, Allocator.Persistent); packLoad = new NativeArray<int>(16, Allocator.Persistent); }
    void DisposeHand() { if (shovelLoad.IsCreated) shovelLoad.Dispose(); if (cartLoad.IsCreated) cartLoad.Dispose(); if (packLoad.IsCreated) packLoad.Dispose(); }

    /// How much of one material the cart holds (voxels), so its load can be drawn in the right colours.
    public int CartLoadOf(int m) { return m >= 0 && m < cartLoad.Length ? cartLoad[m] : 0; }
    public int PackLoadOf(int m) { return m >= 0 && m < packLoad.Length ? packLoad[m] : 0; }

    /// The backpack's nozzle at work on the ground: loose dirt in a ball at `at` (never firm ground or rock)
    /// lets go as clods, flying off with `kick`, at most `most` voxels of it.  SuckPull then draws them in.
    /// Returns how many voxels came loose.
    public int SuckLoose(Vector3 at, float radius, int most, Vector3 kick)
    {
        if (most <= 0) return 0;
        var result = new NativeArray<int>(2, Allocator.TempJob);
        new HandJob
        {
            vox = vox, top = top, dirty = dirty, grass = grass, tally = bladeLoad, shovel = shovelLoad, result = result,
            centre = (at - origin) / Voxel, radius = radius / Voxel, kick = kick, origin = origin, seed = frame, mode = 2, most = most,
            cPos = cPos, cVel = cVel, cRot = cRot, cMat = cMat, cCnt = cCnt, cRest = cRest, cAge = cAge, cCount = cCount,
        }.Run();
        int outOfGround = result[0];
        result.Dispose();
        SolidCount -= outOfGround;
        Recount();
        return outOfGround;
    }

    /// The suction: clods near the line from the nozzle out to `aim` (and just past it) are drawn to the
    /// nozzle at `speed`; those that reach it go into the backpack while it has room (`room` voxels).
    /// When it is full nothing more is drawn in.  Returns how many voxels went in.
    public int SuckPull(Vector3 nozzle, Vector3 aim, float width, float speed, float dt, int room)
    {
        int n = cCount[0], took = 0;
        if (n == 0 || room < ClodVoxels) return 0;
        float3 a = nozzle, seg = (float3)aim - a;
        float segLen2 = math.max(math.lengthsq(seg), 1e-6f);
        float step = speed * dt;
        for (int i = n - 1; i >= 0; i--)
        {
            float3 p = cPos[i];
            float k = math.clamp(math.dot(p - a, seg) / segLen2, 0f, 1.15f);
            float3 near = a + seg * k;
            if (math.distancesq(p, near) > width * width) continue;
            float3 toNozzle = a - p;
            float d = math.length(toNozzle);
            if (d < 0.16f)
            {
                if (took + cCnt[i] > room) continue;                 // full: it stays where it is and drops
                packLoad[cMat[i]] += cCnt[i];
                took += cCnt[i];
                n--;
                cPos[i] = cPos[n]; cVel[i] = cVel[n]; cRot[i] = cRot[n]; cMat[i] = cMat[n]; cCnt[i] = cCnt[n]; cRest[i] = cRest[n]; cAge[i] = cAge[n];
                continue;
            }
            float3 dir = toNozzle / d;
            cPos[i] = p + dir * math.min(step, d - 0.1f);
            cVel[i] = dir * speed + new float3(0f, 9.81f * Time.fixedDeltaTime, 0f);   // gravity is cancelled while it is being sucked
            cRest[i] = 0f;
            cAge[i] = -0.15f;                                         // flying: it does not jostle the other clods
        }
        cCount[0] = n;
        if (took > 0) Recount();
        return took;
    }

    /// One clod's worth squirts out of the backpack at `at` with `velocity`.  False when the backpack has
    /// less than a clod of anything left (or no clod can be made).
    public bool PackPour(Vector3 at, Vector3 velocity)
    {
        for (int m = LooseSoil; m <= LooseGold; m++)
        {
            if (packLoad[m] < ClodVoxels || cCount[0] >= MaxClods) continue;
            packLoad[m] -= ClodVoxels;
            int n = cCount[0]++;
            cPos[n] = at; cVel[n] = velocity; cRot[n] = quaternion.identity;
            cMat[n] = (byte)m; cCnt[n] = ClodVoxels; cRest[n] = 0f; cAge[n] = -0.4f;
            Recount();
            return true;
        }
        return false;
    }

    /// The last crumbs in the backpack (less than a clod of each material) go straight into the cart, if it has room.
    public void PackCrumbsToCart(int capacity)
    {
        int crumbs = 0;
        for (int m = LooseSoil; m <= LooseGold; m++) crumbs += packLoad[m];
        if (crumbs == 0 || CartVoxels + crumbs > capacity) return;
        for (int m = LooseSoil; m <= LooseGold; m++) { cartLoad[m] += packLoad[m]; packLoad[m] = 0; }
        Recount();
    }

    /// Loose clods inside the cart's tub (a box in the cart's own space) go into its load, while there is room.
    public void CartCollect(Matrix4x4 worldToCart, Vector3 min, Vector3 max, int capacity)
    {
        int n = cCount[0], held = CartVoxels;
        bool took = false;
        for (int i = n - 1; i >= 0 && held + cCnt[i] <= capacity; i--)
        {
            Vector3 l = worldToCart.MultiplyPoint3x4(cPos[i]);
            if (l.x < min.x || l.x > max.x || l.y < min.y || l.y > max.y || l.z < min.z || l.z > max.z) continue;
            cartLoad[cMat[i]] += cCnt[i];
            held += cCnt[i];
            n--;
            cPos[i] = cPos[n]; cVel[i] = cVel[n]; cRot[i] = cRot[n]; cMat[i] = cMat[n]; cCnt[i] = cCnt[n]; cRest[i] = cRest[n]; cAge[i] = cAge[n];
            took = true;
        }
        if (!took) return;
        cCount[0] = n;
        Recount();
    }

    /// One clod's worth leaves the cart at `at` with `velocity`.  False when the cart is empty (or no clod can be made).
    public bool CartPour(Vector3 at, Vector3 velocity)
    {
        for (int m = LooseSoil; m <= LooseGold; m++)
        {
            if (cartLoad[m] < ClodVoxels || cCount[0] >= MaxClods) continue;
            cartLoad[m] -= ClodVoxels;
            int n = cCount[0]++;
            cPos[n] = at; cVel[n] = velocity; cRot[n] = quaternion.identity;
            cMat[n] = (byte)m; cCnt[n] = ClodVoxels; cRest[n] = 0f; cAge[n] = 0f;
            Recount();
            return true;
        }
        // only crumbs left (less than one clod of any material): they join the general tally
        for (int m = LooseSoil; m <= LooseGold; m++) { bladeLoad[m] += cartLoad[m]; cartLoad[m] = 0; }
        Recount();
        return false;
    }

    void FixedUpdate()
    {
        StepDirt(plateToWorld, plateMin, plateMax, havePlate, Time.fixedDeltaTime);
        Slump(SlumpCentre, 6.5f, 4);
    }

    bool Cell(Vector3 p, out int x, out int y, out int z)
    {
        x = Mathf.FloorToInt((p.x - origin.x) / Voxel); y = Mathf.FloorToInt((p.y - origin.y) / Voxel); z = Mathf.FloorToInt((p.z - origin.z) / Voxel);
        return x >= 0 && z >= 0 && x < NX && z < NZ && y >= 0 && y < NY;
    }

    /// What is at this point: 0 for air.  Outside the site the plain ground is solid below height 0.
    public byte MaterialAt(Vector3 p)
    {
        int x, y, z;
        if (!Cell(p, out x, out y, out z)) return p.y < 0f ? Soil : Air;
        return vox[y + NY * (x + NX * z)];
    }

    /// The height of the surface a person at p would stand on: the first solid ground at or below about knee
    /// height.  Works under a roof.  If p is inside the ground it looks up a little for free space instead.
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
        if (vox[y + NY * col] != Air)
        {
            for (int k = 0; k < 14 && y < NY - 1 && vox[y + NY * col] != Air; k++) y++;
            return origin.y + y * Voxel;
        }
        while (y > 0 && vox[y - 1 + NY * col] == Air) y--;
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
        int carried = 0, onShovel = 0, inCart = 0, inPack = 0;
        for (int i = 0; i < bladeLoad.Length; i++) carried += bladeLoad[i];
        for (int i = 0; i < shovelLoad.Length; i++) onShovel += shovelLoad[i];
        for (int i = 0; i < cartLoad.Length; i++) inCart += cartLoad[i];
        for (int i = 0; i < packLoad.Length; i++) inPack += packLoad[i];
        carriedOnBlade = carried;
        ShovelVoxels = onShovel;
        CartVoxels = inCart;
        PackVoxels = inPack;
        ClodCount = cCount[0];
    }

    /// The pick: breaks a ball of ground at `at` into loose clods that fly off with `kick`.  Rock only gives
    /// way close to the point.  Returns how many voxels came out of the ground.
    public int Pick(Vector3 at, float radius, Vector3 kick)
    {
        var result = new NativeArray<int>(2, Allocator.TempJob);
        new HandJob
        {
            vox = vox, top = top, dirty = dirty, grass = grass, tally = bladeLoad, shovel = shovelLoad, result = result,
            centre = (at - origin) / Voxel, radius = radius / Voxel, kick = kick, origin = origin, seed = frame, mode = 0, most = 0,
            cPos = cPos, cVel = cVel, cRot = cRot, cMat = cMat, cCnt = cCnt, cRest = cRest, cAge = cAge, cCount = cCount,
        }.Run();
        int outOfGround = result[0];
        result.Dispose();
        SolidCount -= outOfGround;
        Recount();
        return outOfGround;
    }

    /// The shovel: takes up to `most` voxels of loose dirt (and a little firm soil or clay) from a ball at `at`,
    /// along with loose clods lying in it.  Returns how much went onto the shovel.
    public int Scoop(Vector3 at, float radius, int most)
    {
        int before = ShovelVoxels;
        var result = new NativeArray<int>(2, Allocator.TempJob);
        new HandJob
        {
            vox = vox, top = top, dirty = dirty, grass = grass, tally = bladeLoad, shovel = shovelLoad, result = result,
            centre = (at - origin) / Voxel, radius = radius / Voxel, kick = Vector3.zero, origin = origin, seed = frame, mode = 1, most = most,
            cPos = cPos, cVel = cVel, cRot = cRot, cMat = cMat, cCnt = cCnt, cRest = cRest, cAge = cAge, cCount = cCount,
        }.Run();
        int outOfGround = result[0];
        result.Dispose();
        SolidCount -= outOfGround;
        Recount();
        return ShovelVoxels - before;
    }

    /// Throws what is on the shovel: it leaves as clods from `from` at `velocity`.
    /// `flight` is roughly how long the load is in the air: for that long its clods fly together as one bunch.
    public int Throw(Vector3 from, Vector3 velocity, float spread = 1f, float flight = 0.7f)
    {
        int thrown = 0;
        var rng = new Unity.Mathematics.Random((uint)(frame * 7919 + 17));
        for (int m = LooseSoil; m <= LooseGold; m++)
        {
            while (shovelLoad[m] >= ClodVoxels && cCount[0] < MaxClods)
            {
                shovelLoad[m] -= ClodVoxels;
                int n = cCount[0]++;
                // the load leaves the blade as a loose bunch that strings out a little along the throw
                float3 jitter = rng.NextFloat3() - 0.5f;
                cPos[n] = (float3)from + jitter * new float3(0.26f, 0.12f, 0.3f) * math.max(spread, 0.5f);
                cVel[n] = (float3)velocity * (1f + (rng.NextFloat() - 0.5f) * 0.36f * spread) + jitter * new float3(1.3f, 0.7f, 1.3f) * spread;
                cRot[n] = rng.NextQuaternionRotation();
                cMat[n] = (byte)m; cCnt[n] = ClodVoxels; cRest[n] = 0f; cAge[n] = -flight;     // negative: in free flight
                thrown += ClodVoxels;
            }
            bladeLoad[m] += shovelLoad[m];                   // the crumbs (less than one clod) join the general tally
            shovelLoad[m] = 0;
        }
        Recount();
        return thrown;
    }

    /// mode 0 = pick, mode 1 = shovel, mode 2 = the backpack's nozzle (loose dirt only, `most` at a time, as clods).
    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct HandJob : IJob
    {
        public NativeArray<byte> vox;
        public NativeArray<ushort> top;
        public NativeArray<byte> dirty, grass;
        public NativeArray<int> tally, shovel, result;
        public float3 centre, kick, origin;
        public float radius;
        public int seed, mode, most;
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
            uint h = math.hash(new int3(n, seed, y));
            float3 r = new float3(h & 255u, (h >> 8) & 255u, (h >> 16) & 255u) / 255f - 0.5f;
            cPos[n] = origin + (new float3(x, y, z) + 0.5f) * Voxel + r * Voxel;
            cVel[n] = vel + r * 1.4f;
            cRot[n] = quaternion.identity;
            cMat[n] = loose; cCnt[n] = ClodVoxels; cRest[n] = 0f; cAge[n] = 0f;
        }

        public void Execute()
        {
            int outOfGround = 0, taken = 0, firmTaken = 0;
            for (int i = 0; i < shovel.Length; i++) taken += shovel[i];
            int3 a = math.clamp((int3)math.floor(centre - radius), new int3(Rim + 6, 1, Rim + 6), new int3(NX - 7 - Rim, NY - 2, NZ - 7 - Rim));
            int3 b = math.clamp((int3)math.ceil(centre + radius), new int3(Rim + 6, 1, Rim + 6), new int3(NX - 7 - Rim, NY - 2, NZ - 7 - Rim));
            for (int z = a.z; z <= b.z; z++)
                for (int x = a.x; x <= b.x; x++)
                {
                    int col = x + NX * z;
                    int highest = -1;
                    for (int y = b.y; y >= a.y; y--)                      // from the top down, so a shovel takes the top of a heap first
                    {
                        float d2 = math.distancesq(new float3(x, y, z) + 0.5f, centre);
                        if (d2 > radius * radius) continue;
                        byte m = vox[y + NY * col];
                        if (m == Air) continue;
                        bool hard = m >= Rock && m <= Gold;
                        if (mode != 1)
                        {
                            if (mode == 2 && (m < LooseSoil || outOfGround >= most)) continue;   // the nozzle only lifts loose dirt
                            if (hard && d2 > radius * radius * 0.42f) continue;      // rock only breaks near the point of the pick
                            vox[y + NY * col] = Air;
                            Mark(ref dirty, x, y, z);
                            Loose(Loosen(m), x, y, z, kick);
                            outOfGround++;
                        }
                        else
                        {
                            if (hard || taken >= most) continue;
                            if (m < LooseSoil) { if (firmTaken >= most / 4) continue; firmTaken++; }   // firm ground only gives a little
                            vox[y + NY * col] = Air;
                            Mark(ref dirty, x, y, z);
                            shovel[Loosen(m)]++;
                            taken++; outOfGround++;
                        }
                        if (highest < 0) highest = y;
                    }
                    if (highest < 0) continue;
                    // loose dirt that was sitting on what just went has nothing under it now: it falls as clods
                    for (int y = highest + 1; y < NY - 1; y++)
                    {
                        byte m = vox[y + NY * col];
                        if (m < LooseSoil) break;
                        vox[y + NY * col] = Air;
                        Mark(ref dirty, x, y, z);
                        Loose(m, x, y, z, float3.zero);
                        outOfGround++;
                    }
                    int t = top[col];
                    if (t > 0 && vox[t - 1 + NY * col] == Air)
                    {
                        while (t > 0 && vox[t - 1 + NY * col] == Air) t--;
                        top[col] = (ushort)t;
                        grass[col] = 0;
                    }
                }

            if (mode == 1)
            {
                // loose clods lying within reach go onto the shovel too
                float3 c = origin + centre * Voxel;
                float reach = radius * Voxel + ClodRadius;
                int n = cCount[0];
                for (int i = n - 1; i >= 0 && taken < most; i--)
                {
                    if (math.distancesq(cPos[i], c) > reach * reach) continue;
                    shovel[cMat[i]] += cCnt[i];
                    taken += cCnt[i];
                    n--;
                    cPos[i] = cPos[n]; cVel[i] = cVel[n]; cRot[i] = cRot[n]; cMat[i] = cMat[n]; cCnt[i] = cCnt[n]; cRest[i] = cRest[n]; cAge[i] = cAge[n];
                }
                cCount[0] = n;
            }
            result[0] = outOfGround;
        }
    }
}
