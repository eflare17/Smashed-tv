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
    /// Trailer mode only (nothing is saved there): fills the cart for the camera; the dirt books are not kept straight.
    public void TrailerFillCart(int voxels) { CartVoxels = voxels; }
    public int PackVoxels { get; private set; }             // what the worker's backpack is holding
    public int SoldVoxels { get; private set; }             // what has gone down the hopper and been sold (it has left the site)
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
    public Vector3 ClodPosition(int i) { return cPos[i]; }                // (tests)
    [System.NonSerialized] public long PouredFromCart;                      // (tests)
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
            vox = vox, blocks = blocks, top = top, dirty = dirty, grass = grass, tally = bladeLoad, shovel = shovelLoad, result = result,
            centre = (at - origin) / Voxel, radius = radius / Voxel, kick = kick, origin = origin, seed = frame, mode = 2, most = most,
            cPos = cPos, cVel = cVel, cRot = cRot, cMat = cMat, cCnt = cCnt, cRest = cRest, cAge = cAge, cCount = cCount,
        }.Run();
        int outOfGround = result[0];
        result.Dispose();
        SolidCount -= outOfGround;
        Recount();
        return outOfGround;
    }

    /// E by hand: loose gold round `at` (lumps lying there, and loose gold on top of the ground) goes into the son's
    /// pockets, up to `most` voxels.  Only gold, and only gold that's on top: nothing else is moved.  What he takes
    /// leaves the site's tally the way the hopper's does (SoldVoxels).  Returns the voxels taken.
    public int PickGold(Vector3 at, float radius, int most)
    {
        if (most <= 0) return 0;
        var result = new NativeArray<int>(2, Allocator.TempJob);
        var got = new NativeArray<int>(16, Allocator.TempJob);
        new HandJob
        {
            vox = vox, blocks = blocks, top = top, dirty = dirty, grass = grass, tally = bladeLoad, shovel = got, result = result,
            centre = (at - origin) / Voxel, radius = radius / Voxel, kick = Vector3.zero, origin = origin, seed = frame, mode = 3, most = most,
            cPos = cPos, cVel = cVel, cRot = cRot, cMat = cMat, cCnt = cCnt, cRest = cRest, cAge = cAge, cCount = cCount,
        }.Run();
        int outOfGround = result[0], fromClods = result[1], took = got[LooseGold];
        result.Dispose(); got.Dispose();
        if (took == 0) return 0;
        SolidCount -= outOfGround;
        ClodVoxelsInFlight -= fromClods;                        // (StepDirt recounts these each step anyway)
        SoldVoxels += took;
        Recount();
        RecountLoad();
        return took;
    }

    /// Is there loose gold he could pick up round `at` (a gold lump lying there, or loose gold with nothing on it)?
    public bool LooseGoldNear(Vector3 at, float radius)
    {
        float reach = radius + ClodRadius + 0.3f;
        for (int i = 0; i < cCount[0]; i++) if (cMat[i] == LooseGold && Vector3.Distance(cPos[i], at) <= reach) return true;
        Vector3 c = (at - origin) / Voxel;
        float r = radius / Voxel;
        int x0 = Mathf.Max(Rim, Mathf.FloorToInt(c.x - r)), x1 = Mathf.Min(NX - Rim - 1, Mathf.CeilToInt(c.x + r));
        int z0 = Mathf.Max(Rim, Mathf.FloorToInt(c.z - r)), z1 = Mathf.Min(NZ - Rim - 1, Mathf.CeilToInt(c.z + r));
        int y0 = Mathf.FloorToInt(c.y - r), y1 = Mathf.CeilToInt(c.y + r);
        for (int z = z0; z <= z1; z++)
            for (int x = x0; x <= x1; x++)
            {
                int lo, hi;
                int cb = ColBase(blocks, x, z, out lo, out hi);
                if (cb < 0) continue;
                for (int y = Mathf.Max(y0, lo); y <= Mathf.Min(y1, hi - 2); y++)
                    if (vox[cb + y] == LooseGold && vox[cb + y + 1] == Air && (new Vector3(x, y, z) + Vector3.one * 0.5f - c).sqrMagnitude <= r * r) return true;
            }
        return false;
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

    /// Loose clods inside a box (in the box's own space) go down the hopper: they leave the site and are sold.
    /// `byMaterial[m]` gets how much of each went.  Returns the voxels taken.
    public int HopperCollect(Matrix4x4 worldToBox, Vector3 min, Vector3 max, int[] byMaterial)
    {
        int n = cCount[0], took = 0;
        for (int i = n - 1; i >= 0; i--)
        {
            Vector3 l = worldToBox.MultiplyPoint3x4(cPos[i]);
            if (l.x < min.x || l.x > max.x || l.y < min.y || l.y > max.y || l.z < min.z || l.z > max.z) continue;
            byMaterial[cMat[i]] += cCnt[i];
            took += cCnt[i];
            n--;
            cPos[i] = cPos[n]; cVel[i] = cVel[n]; cRot[i] = cRot[n]; cMat[i] = cMat[n]; cCnt[i] = cCnt[n]; cRest[i] = cRest[n]; cAge[i] = cAge[n];
        }
        if (took == 0) return 0;
        cCount[0] = n;
        SoldVoxels += took;
        ClodVoxelsInFlight -= took;                             // (StepDirt recounts these each step anyway)
        Recount();
        return took;
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
            cMat[n] = (byte)m; cCnt[n] = ClodVoxels; cRest[n] = 0f; cAge[n] = -0.6f;   // pours out as one stream: clods don't shove each other apart in the air
            PouredFromCart += ClodVoxels;
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
        return VoxelAt(vox, blocks, top, x, y, z);
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
    /// How many gold voxels the last Pick smashed (a big jackhammer bite: they come out as worthless quartz).
    public int LastShattered { get; private set; }

    /// A well-mixed random number for a voxel and a frame.  (math.hash of the position is only a weighted sum, so for
    /// all the voxels of one hit its rolls moved together: one swing smashed all its gold, the next none.)
    static uint Roll(int x, int y, int z, int seed)
    {
        uint h = (uint)x * 73856093u ^ (uint)y * 19349663u ^ (uint)z * 83492791u ^ (uint)seed * 2654435761u;
        h ^= h >> 16; h *= 0x7feb352du; h ^= h >> 15; h *= 0x846ca68bu; h ^= h >> 16;
        return h;
    }

    public int Pick(Vector3 at, float radius, Vector3 kick, float shatter = 0f, bool fullRock = false)
    {
        var result = new NativeArray<int>(2, Allocator.TempJob);
        new HandJob
        {
            vox = vox, blocks = blocks, top = top, dirty = dirty, grass = grass, tally = bladeLoad, shovel = shovelLoad, result = result,
            centre = (at - origin) / Voxel, radius = radius / Voxel, kick = kick, origin = origin, seed = frame, mode = 0, most = 0, shatter = shatter, fullRock = fullRock,
            cPos = cPos, cVel = cVel, cRot = cRot, cMat = cMat, cCnt = cCnt, cRest = cRest, cAge = cAge, cCount = cCount,
        }.Run();
        int outOfGround = result[0];
        LastShattered = result[1];
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
            vox = vox, blocks = blocks, top = top, dirty = dirty, grass = grass, tally = bladeLoad, shovel = shovelLoad, result = result,
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

    /// mode 0 = pick, mode 1 = shovel, mode 2 = the backpack's nozzle (loose dirt only, `most` at a time, as clods),
    /// mode 3 = picking up gold by hand (loose gold on top of the ground, and gold lumps, into `shovel`; result[1] = from lumps).
    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct HandJob : IJob
    {
        public NativeArray<byte> vox;
        [ReadOnly] public NativeArray<int4> blocks;
        public NativeArray<ushort> top;
        public NativeArray<byte> dirty, grass;
        public NativeArray<int> tally, shovel, result;
        public float3 centre, kick, origin;
        public float radius;
        public int seed, mode, most;
        public float shatter;
        public bool fullRock;          // the jackhammer: rock breaks across the whole bite, not just at the point          // the pick/jackhammer: the chance a gold voxel it breaks is smashed to quartz grit
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
                    int lo, hi;
                    int cb = ColBase(blocks, x, z, out lo, out hi);
                    if (cb < 0) continue;
                    int highest = -1;
                    for (int y = math.min(b.y, hi - 2); y >= math.max(a.y, lo + 1); y--)   // from the top down, so a shovel takes the top of a heap first
                    {
                        float d2 = math.distancesq(new float3(x, y, z) + 0.5f, centre);
                        if (mode == 3 && vox[cb + y] != Air && d2 > radius * radius) break;   // by hand: never from under anything
                        if (d2 > radius * radius) continue;
                        byte m = vox[cb + y];
                        if (m == Air) continue;
                        bool hard = m >= Rock && m <= Gold;
                        if (mode == 3)
                        {
                            if (m != LooseGold || taken >= most) break;      // only the gold on top: stop at anything else
                            vox[cb + y] = Air;
                            Mark(ref dirty, x, y, z);
                            shovel[LooseGold]++;
                            taken++; outOfGround++;
                            highest = y;
                            continue;
                        }
                        if (mode != 1)
                        {
                            if (mode == 2 && (m < LooseSoil || outOfGround >= most)) continue;   // the nozzle only lifts loose dirt
                            if (hard && !fullRock && d2 > radius * radius * 0.42f) continue;      // rock only breaks near the point of the pick
                            vox[cb + y] = Air;
                            Mark(ref dirty, x, y, z);
                            byte lm = Loosen(m);
                            if (m == Gold && shatter > 0f && (Roll(x, y, z, seed) % 1000u) < (uint)(shatter * 1000f))
                            {
                                lm = LooseQuartz;                                    // smashed: the gold is lost in the grit
                                result[1] = result[1] + 1;
                            }
                            Loose(lm, x, y, z, kick);
                            outOfGround++;
                        }
                        else
                        {
                            if (hard || taken >= most) continue;
                            if (m < LooseSoil) { if (firmTaken >= most / 4) continue; firmTaken++; }   // firm ground only gives a little
                            vox[cb + y] = Air;
                            Mark(ref dirty, x, y, z);
                            shovel[Loosen(m)]++;
                            taken++; outOfGround++;
                        }
                        if (highest < 0) highest = y;
                    }
                    if (highest < 0) continue;
                    if (mode == 3) { FixTop(col, lo, cb); continue; }   // nothing was on top of the gold
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
                    FixTop(col, lo, cb);
                }

            if (mode == 3)
            {
                // gold lumps lying within reach go into his pockets too
                float3 c = origin + centre * Voxel;
                float reach = radius * Voxel + ClodRadius + 0.3f;
                int n = cCount[0], fromClods = 0;
                for (int i = n - 1; i >= 0; i--)
                {
                    if (cMat[i] != LooseGold || taken + cCnt[i] > most || math.distancesq(cPos[i], c) > reach * reach) continue;
                    shovel[LooseGold] += cCnt[i];
                    taken += cCnt[i]; fromClods += cCnt[i];
                    n--;
                    cPos[i] = cPos[n]; cVel[i] = cVel[n]; cRot[i] = cRot[n]; cMat[i] = cMat[n]; cCnt[i] = cCnt[n]; cRest[i] = cRest[n]; cAge[i] = cAge[n];
                }
                cCount[0] = n;
                result[1] = fromClods;
            }
            if (mode == 1)
            {
                // loose clods lying within reach go onto the shovel too
                float3 c = origin + centre * Voxel;
                float reach = radius * Voxel + ClodRadius + 0.4f;          // a bit wider: it gathers up the bits lying round the spot
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

        /// The column's top after voxels came out of it.
        void FixTop(int col, int lo, int cb)
        {
            int t = top[col];
            if (t > lo && vox[cb + t - 1] == Air)
            {
                while (t > lo && vox[cb + t - 1] == Air) t--;
                top[col] = (ushort)t;
                grass[col] = 0;
            }
        }
    }
}
