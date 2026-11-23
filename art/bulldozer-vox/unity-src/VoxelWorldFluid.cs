// Water, ice and gas: the fluids.  They are NOT dirt: they live in their own grid beside the voxels, so the dirt's
// books (CountSolid + LoadVoxels) never see them.
//
// The fluid grid is made of 12.5 cm cells (2 x 2 x 2 voxels).  It is kept only where something is going on, in
// "bricks" of 16 x 16 x 16 cells, one brick per 2 m chunk of the ground.  A brick is made when fluid reaches it and
// thrown away a while after it is empty.  Only bricks with something in them, or where something moved lately
// ("awake"), are worked on: the rest of the site costs nothing.
//
// Each cell holds, 0..255 each:
//   water   how full of water it is (255 = full).  Ice is water that froze: the same number, with the ice flag.
//   gas     the green gas (it explodes), how strong
//   cold    the blue cold gas (it freezes water)
//   flag    1 = solid (most of its 8 voxels are ground), 2 = ice
//
// How water looks (23 Nov, the owner's call): chunky blocks.  A cell with a fair bit of water in it that sits on
// something (ground, ice, more water) is drawn as a whole see-through blue cube; thin films aren't drawn at all.
// Water in free fall (open air under it, two cells down) leaves the grid as a tumbling cube (Fluids.cs: drops) that
// lands back in the grid where it comes to rest.
//
// One step (20 a second), a Burst job over the awake bricks:
//   water in free fall goes out as a drop (above); otherwise it falls into the cell below if it can, then spreads sideways to level out (a cell with very little stays put,
//   so water stops as a film instead of spreading thinner for ever).  Water lying on ground soaks away slowly.
//   Green gas rises, cold gas sinks; both spread out and slowly thin away.  Gas that reaches the open sky is gone.
//   Water touching cold gas freezes; ice melts back, slowly.
// When the ground changes (digging, dirt landing), the chunk's bricks work out again which cells are solid; water
// and gas in a cell that dirt filled are pushed up, or lost (that is how filling a hole fixes a flood).
using System.Collections.Generic;
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

public partial class VoxelWorld
{
    public const int FCell = 2;                              // voxels per fluid cell, each way (12.5 cm)
    public const int FB = 16;                                // cells per brick, each way (one chunk)
    const int FBC = FB * FB * FB;
    public const int FNX = NX / FCell, FNY = NY / FCell, FNZ = NZ / FCell;
    public const float FCellSize = Voxel * FCell;
    public int FluidSlots { get; private set; }               // bricks kept at once, at most: 2048 (32 MB), 4096 at High and Ultra quality
    /// Only bricks within FluidRange metres (across) of FluidFocus are worked on; the rest wait, still (Fluids.cs sets
    /// these from the Quality setting and where you are).
    [System.NonSerialized] public Vector3 FluidFocus;
    [System.NonSerialized] public float FluidRange = 1e9f;
    /// Columns of chunks (ChunkColumnOf) always worked on, wherever you are: the creek's (Fluids.cs).  Null for none.
    [System.NonSerialized] public HashSet<int> FluidAlways;
    public int ChunkColumnOf(Vector3 p) { return Mathf.FloorToInt((p.x - origin.x) / (FB * FCellSize)) + CX * Mathf.FloorToInt((p.z - origin.z) / (FB * FCellSize)); }
    public const byte FSolid = 1, FIce = 2;
    /// A cell of the creek's bed (Creek.cs): its water has a current, pushed downstream each step, so the creek runs
    /// instead of spreading out slowly like a puddle; and the bed doesn't soak it up.  Bit 0x10: downstream is -x (else
    /// +x); 0x20: -z (else +z); 0x40: push along x first (else z first).  The other way is tried when the first is blocked.
    public const byte FCurrent = 0x80, FDirShift = 4;
    /// The creek's middle line (x, bed height, z), for marking its cells as bricks are made.  Null for none.
    [System.NonSerialized] public List<Vector3> CurrentLine;
    public const int GasGoesOff = 20;                        // green gas this strong (or more) explodes when set off
    public const int WaterStill = 80;                        // water this little in a cell doesn't spread any further (so it lies in chunky blocks, not films)
    public const int WaterShows = 40;                        // a cell with this much water or more is drawn (as a whole block)
    public const int DropMin = 64;                           // water in free fall this much or more goes out as a tumbling cube
    /// Water that went into free fall this step: cell (x, y, z) and how much (Fluids.cs turns each into a falling cube).
    public readonly List<int4> NewDrops = new List<int4>();
    public static bool DropsOn = true;
    public Material FluidMaterial { get { return fMat; } }
    const int AwakeSteps = 30;                               // a brick nothing happened in sleeps after this many steps (1.5 s)
    public const float FluidStep = 0.05f;

    /// Tuning (Fluids.cs sets these).
    [System.NonSerialized] public float SoakPerSecond = 3f;      // units of water a wet cell lying on the ground loses each second
    [System.NonSerialized] public float MeltSeconds = 100f;      // ice melts back to water after about this long (on average)
    [System.NonSerialized] public float GasFadeSeconds = 1.6f;   // gas loses one unit (of 255) every this many seconds

    NativeArray<int> fSlot;                                  // per chunk: its brick, or -1
    NativeArray<int> fChunk;                                 // per brick: its chunk, or -1 (free)
    NativeArray<byte> fWater, fGas, fCold, fFlag;
    NativeArray<byte> fAwake, fMeshDirty;
    NativeArray<int4> fSum;                                  // per brick: water, green gas, cold gas (units) and ice cells
    NativeQueue<int4> fDropQ;
    readonly Stack<int> fFree = new Stack<int>();
    float[] fEmpty;                                          // per brick: seconds it has had nothing in it
    MeshFilter[] fMeshes;
    Material fMat;
    Transform fRoot;
    readonly HashSet<int> fGroundChanged = new HashSet<int>();
    float fAcc, fFreeTimer;
    int fStepN;
    public int FluidBricks { get { return FluidSlots - fFree.Count; } }
    public int FluidAwake { get; private set; }
    public float FluidMs { get; private set; }               // the last step's cost, for the debug box and tests
    public float FluidMaxMs { get; private set; }
    public bool FluidReady { get { return fSlot.IsCreated; } }
    public bool IceAny { get; private set; }                 // any ice anywhere (so the ray and floor checks can skip it)

    void InitFluid()
    {
        FluidSlots = PlayerPrefs.GetInt("set.quality", 1) >= 2 ? 4096 : 2048;   // (fixed for the game: the Quality when it started)
        fSlot = new NativeArray<int>(CX * CY * CZ, Allocator.Persistent);
        for (int i = 0; i < fSlot.Length; i++) fSlot[i] = -1;
        fChunk = new NativeArray<int>(FluidSlots, Allocator.Persistent);
        for (int i = 0; i < FluidSlots; i++) fChunk[i] = -1;
        fWater = new NativeArray<byte>(FluidSlots * FBC, Allocator.Persistent);
        fGas = new NativeArray<byte>(FluidSlots * FBC, Allocator.Persistent);
        fCold = new NativeArray<byte>(FluidSlots * FBC, Allocator.Persistent);
        fFlag = new NativeArray<byte>(FluidSlots * FBC, Allocator.Persistent);
        fAwake = new NativeArray<byte>(FluidSlots, Allocator.Persistent);
        fMeshDirty = new NativeArray<byte>(FluidSlots, Allocator.Persistent);
        fSum = new NativeArray<int4>(FluidSlots, Allocator.Persistent);
        fDropQ = new NativeQueue<int4>(Allocator.Persistent);
        for (int i = FluidSlots - 1; i >= 0; i--) fFree.Push(i);
        fEmpty = new float[FluidSlots];
        fMeshes = new MeshFilter[FluidSlots];
        var sh = Shader.Find("Voxel/Fluid");
        fMat = new Material(sh != null ? sh : Shader.Find("Sprites/Default")) { renderQueue = 3010 };
        fRoot = new GameObject("Fluids (water, ice, gas)").transform;
        fRoot.SetParent(transform, false);
    }

    void DisposeFluid()
    {
        if (fSlot.IsCreated) fSlot.Dispose();
        if (fChunk.IsCreated) fChunk.Dispose();
        if (fWater.IsCreated) fWater.Dispose();
        if (fGas.IsCreated) fGas.Dispose();
        if (fCold.IsCreated) fCold.Dispose();
        if (fFlag.IsCreated) fFlag.Dispose();
        if (fAwake.IsCreated) fAwake.Dispose();
        if (fMeshDirty.IsCreated) fMeshDirty.Dispose();
        if (fSum.IsCreated) fSum.Dispose();
        if (fDropQ.IsCreated) fDropQ.Dispose();
    }

    /// Called when a chunk of the ground is redrawn (it changed): its brick works out its solid cells again.
    void FluidGroundChanged(int chunk)
    {
        if (fSlot.IsCreated && fSlot[chunk] >= 0) fGroundChanged.Add(chunk);
    }

    // ------------------------------------------------------------------ cells
    public bool FluidCellOf(Vector3 p, out int gx, out int gy, out int gz)
    {
        Vector3 q = (p - origin) / FCellSize;
        gx = Mathf.FloorToInt(q.x); gy = Mathf.FloorToInt(q.y); gz = Mathf.FloorToInt(q.z);
        return gx >= 1 && gy >= 1 && gz >= 1 && gx < FNX - 1 && gy < FNY - 1 && gz < FNZ - 1;
    }
    public Vector3 FluidCellCentre(int gx, int gy, int gz) { return origin + new Vector3(gx + 0.5f, gy + 0.5f, gz + 0.5f) * FCellSize; }
    static int ChunkOfCell(int gx, int gy, int gz) { return (gx >> 4) + CX * ((gy >> 4) + CY * (gz >> 4)); }
    static int InBrick(int gx, int gy, int gz) { return (gx & 15) + FB * ((gy & 15) + FB * (gz & 15)); }

    /// The cell's index in the fluid arrays, making its brick if need be.  -1 if there is no room (or it's off the grid).
    int FluidIndex(int gx, int gy, int gz, bool make)
    {
        if (gx < 0 || gy < 0 || gz < 0 || gx >= FNX || gy >= FNY || gz >= FNZ) return -1;
        int c = ChunkOfCell(gx, gy, gz);
        int s = fSlot[c];
        if (s < 0)
        {
            if (!make) return -1;
            s = MakeBrick(c);
            if (s < 0) return -1;
        }
        return s * FBC + InBrick(gx, gy, gz);
    }

    int MakeBrick(int c, bool solidNow = true)
    {
        if (fFree.Count == 0) return -1;
        int s = fFree.Pop();
        fSlot[c] = s; fChunk[s] = c;
        fEmpty[s] = 0f;
        fAwake[s] = AwakeSteps; fMeshDirty[s] = 1;
        fSum[s] = int4.zero;
        int b = s * FBC;
        for (int i = 0; i < FBC; i++) { fWater[b + i] = 0; fGas[b + i] = 0; fCold[b + i] = 0; fFlag[b + i] = 0; }
        MarkCurrent(s, c);
        if (!solidNow) return s;
        var list = new NativeArray<int>(1, Allocator.TempJob);
        list[0] = s;
        new FluidSolidJob { vox = vox, blocks = blocks, top = top, chunk = fChunk, water = fWater, gas = fGas, cold = fCold, flag = fFlag, list = list }.Run(1);
        list.Dispose();
        return s;
    }

    /// Marks the creek's bed cells in a new brick with their current (the way down the creek from there).
    void MarkCurrent(int s, int c)
    {
        var line = CurrentLine;
        if (line == null || line.Count < 2) return;
        int bx = c % CX, by = (c / CX) % CY, bz = c / (CX * CY);
        float size = FB * FCellSize;
        Vector3 lo = origin + new Vector3(bx, by, bz) * size, hi = lo + Vector3.one * size;
        const float half = 0.75f;                            // the bed's half width, and a little up its banks
        int b = s * FBC;
        for (int i = 0; i < line.Count - 1; i++)
        {
            Vector3 p = line[i];
            if (p.x < lo.x - 1f || p.x > hi.x + 1f || p.z < lo.z - 1f || p.z > hi.z + 1f || p.y < lo.y - 1.2f || p.y > hi.y + 1.8f) continue;
            Vector3 t = line[Mathf.Min(line.Count - 1, i + 2)] - line[Mathf.Max(0, i - 2)];
            float ax = Mathf.Abs(t.x), az = Mathf.Abs(t.z);
            if (ax + az < 1e-4f) continue;
            for (float dz = -half; dz <= half; dz += FCellSize * 0.5f)
                for (float dx = -half; dx <= half; dx += FCellSize * 0.5f)
                {
                    if (dx * dx + dz * dz > half * half) continue;
                    for (float dy = -1.6f; dy <= 1.0f; dy += FCellSize)          // (from well under the line: where the hill bumps up, the bed is cut deeper)
                    {
                        Vector3 q = new Vector3(p.x + dx, p.y + dy, p.z + dz);
                        if (q.x < lo.x || q.y < lo.y || q.z < lo.z || q.x >= hi.x || q.y >= hi.y || q.z >= hi.z) continue;
                        int gx = Mathf.FloorToInt((q.x - origin.x) / FCellSize), gy = Mathf.FloorToInt((q.y - origin.y) / FCellSize), gz = Mathf.FloorToInt((q.z - origin.z) / FCellSize);
                        // a slanting creek: each cell pushes along x or z, mixed in proportion, so it zig-zags the right way
                        uint hsh = (uint)(gx * 73856093 ^ gz * 19349663);
                        hsh ^= hsh >> 13; hsh *= 0x5bd1e995u; hsh ^= hsh >> 15;
                        bool alongX = (hsh % 1000u) < (uint)(1000f * ax / (ax + az));
                        int bits = (t.x < 0f ? 0x10 : 0) | (t.z < 0f ? 0x20 : 0) | (alongX ? 0x40 : 0);
                        int k = b + InBrick(gx, gy, gz);
                        fFlag[k] = (byte)((fFlag[k] & 0x0F) | FCurrent | bits);
                    }
                }
        }
    }

    void FreeBrick(int s)
    {
        int c = fChunk[s];
        if (c < 0) return;
        fSlot[c] = -1; fChunk[s] = -1; fAwake[s] = 0; fSum[s] = int4.zero;
        if (fMeshes[s] != null) { var m = fMeshes[s].sharedMesh; if (m != null) m.Clear(); fMeshes[s].gameObject.SetActive(false); }
        fFree.Push(s);
    }

    void Wake(int index) { if (index >= 0) { fAwake[index / FBC] = AwakeSteps; fMeshDirty[index / FBC] = 1; } }

    public bool FluidOpen(int gx, int gy, int gz)
    {
        int i = FluidIndex(gx, gy, gz, true);
        return i >= 0 && (fFlag[i] & (FSolid | FIce)) == 0;
    }

    /// Puts water into the cell (as much as fits).  Returns how much went in.
    public int AddWater(int gx, int gy, int gz, int amount)
    {
        int i = FluidIndex(gx, gy, gz, true);
        if (i < 0 || (fFlag[i] & (FSolid | FIce)) != 0) return 0;
        int put = math.min(amount, 255 - fWater[i]);
        if (put <= 0) return 0;
        fWater[i] = (byte)(fWater[i] + put);
        Wake(i);
        return put;
    }
    public int AddGas(int gx, int gy, int gz, int amount, bool cold)
    {
        int i = FluidIndex(gx, gy, gz, true);
        if (i < 0 || (fFlag[i] & (FSolid | FIce)) != 0) return 0;
        var a = cold ? fCold : fGas;
        int put = math.min(amount, 255 - a[i]);
        if (put <= 0) return 0;
        a[i] = (byte)(a[i] + put);
        Wake(i);
        return put;
    }

    public int WaterAt(int gx, int gy, int gz) { int i = FluidIndex(gx, gy, gz, false); return i < 0 || (fFlag[i] & FIce) != 0 ? 0 : fWater[i]; }
    public int GasAt(int gx, int gy, int gz) { int i = FluidIndex(gx, gy, gz, false); return i < 0 ? 0 : fGas[i]; }
    public int ColdAt(int gx, int gy, int gz) { int i = FluidIndex(gx, gy, gz, false); return i < 0 ? 0 : fCold[i]; }
    public bool IceAt(int gx, int gy, int gz) { int i = FluidIndex(gx, gy, gz, false); return i >= 0 && (fFlag[i] & FIce) != 0; }
    public bool FluidSolidAt(int gx, int gy, int gz) { int i = FluidIndex(gx, gy, gz, false); return i >= 0 && (fFlag[i] & FSolid) != 0; }
    public int WaterAt(Vector3 p) { int x, y, z; return FluidCellOf(p, out x, out y, out z) ? WaterAt(x, y, z) : 0; }
    public int GasAt(Vector3 p) { int x, y, z; return FluidCellOf(p, out x, out y, out z) ? GasAt(x, y, z) : 0; }
    public bool IceAt(Vector3 p) { int x, y, z; return FluidCellOf(p, out x, out y, out z) && IceAt(x, y, z); }

    /// Freezes the water in a cell (the freeze gun).  True if there was water to freeze.
    public bool FreezeCell(int gx, int gy, int gz)
    {
        int i = FluidIndex(gx, gy, gz, false);
        if (i < 0 || (fFlag[i] & (FSolid | FIce)) != 0 || fWater[i] < 4) return false;
        fFlag[i] |= FIce;
        IceAny = true;
        if (fWater[i] < 40) fWater[i] = 40;                   // a thin film freezes into a crust you can stand on
        Wake(i);
        return true;
    }

    /// Breaks the ice in a cell: it is gone (it comes out as loose bits, Fluids.cs).  Returns how much water it held.
    public int BreakIceCell(int gx, int gy, int gz)
    {
        int i = FluidIndex(gx, gy, gz, false);
        if (i < 0 || (fFlag[i] & FIce) == 0) return 0;
        int w = fWater[i];
        fFlag[i] = (byte)(fFlag[i] & ~FIce);
        fWater[i] = 0;
        Wake(i);
        return w;
    }

    /// Takes the gas out of a cell (it exploded).  Returns how strong it was.
    public int TakeGas(int gx, int gy, int gz, bool cold)
    {
        int i = FluidIndex(gx, gy, gz, false);
        if (i < 0) return 0;
        var a = cold ? fCold : fGas;
        int g = a[i];
        if (g > 0) { a[i] = 0; Wake(i); }
        return g;
    }
    public int TakeWater(int gx, int gy, int gz)
    {
        int i = FluidIndex(gx, gy, gz, false);
        if (i < 0 || (fFlag[i] & FIce) != 0) return 0;
        int w = fWater[i];
        if (w > 0) { fWater[i] = 0; Wake(i); }
        return w;
    }

    /// The highest ice top in the column under p (at or below p.y), or -infinity.  For walking on ice.
    public float IceFloorAt(Vector3 p, float below)
    {
        int gx, gy, gz;
        if (!fSlot.IsCreated || !FluidCellOf(p, out gx, out gy, out gz)) return float.NegativeInfinity;
        int lowest = math.max(1, gy - Mathf.CeilToInt(below / FCellSize));
        // inside ice: climb up out of it (a little way)
        if (IceAt(gx, gy, gz))
        {
            int y = gy;
            for (int k = 0; k < 6 && IceAt(gx, y + 1, gz); k++) y++;
            return IceTop(gx, y, gz);
        }
        for (int y = gy - 1; y >= lowest; y--)
        {
            int i = FluidIndex(gx, y, gz, false);
            if (i < 0) continue;
            if ((fFlag[i] & FIce) != 0) return IceTop(gx, y, gz);
            if ((fFlag[i] & FSolid) != 0) break;
        }
        return float.NegativeInfinity;
    }
    float IceTop(int gx, int gy, int gz)
    {
        int i = FluidIndex(gx, gy, gz, false);
        float h = i >= 0 ? math.max(fWater[i], 40) / 255f : 1f;
        return origin.y + (gy + h) * FCellSize;
    }

    /// Walks a line and returns the first ice cell on it, if it comes before `max`.
    public bool RaycastIce(Vector3 from, Vector3 dir, float max, out Vector3 hit)
    {
        hit = from;
        if (!fSlot.IsCreated || FluidBricks == 0) return false;
        dir.Normalize();
        for (float t = 0f; t <= max; t += 0.04f)
        {
            Vector3 p = from + dir * t;
            if (IceAt(p)) { hit = p; return true; }
        }
        return false;
    }

    /// The strongest green gas along a line (up to `max`), and where.
    public int GasAlong(Vector3 from, Vector3 dir, float max, out Vector3 at)
    {
        at = from;
        if (!fSlot.IsCreated || FluidBricks == 0) return 0;
        dir.Normalize();
        int best = 0;
        for (float t = 0f; t <= max; t += 0.1f)
        {
            Vector3 p = from + dir * t;
            int g = GasAt(p);
            if (g > best) { best = g; at = p; }
        }
        return best;
    }

    /// All the fluid there is right now (exact, for tests and the debug box): water, green gas, cold gas, ice cells.
    public int4 FluidTotals()
    {
        int4 t = int4.zero;
        if (!fSlot.IsCreated) return t;
        for (int s = 0; s < FluidSlots; s++)
        {
            if (fChunk[s] < 0) continue;
            int b = s * FBC;
            for (int i = 0; i < FBC; i++)
            {
                if ((fFlag[b + i] & FIce) != 0) t.w++; else t.x += fWater[b + i];
                t.y += fGas[b + i]; t.z += fCold[b + i];
            }
        }
        return t;
    }
    /// The same, as kept by the step (cheap, close enough for caps).
    public int4 FluidRoughTotals()
    {
        int4 t = int4.zero;
        if (!fSlot.IsCreated) return t;
        for (int s = 0; s < FluidSlots; s++) if (fChunk[s] >= 0) t += fSum[s];
        return t;
    }

    /// Throws away every drop of water, gas and ice (a new game, a load).
    public void ClearFluids()
    {
        if (!fSlot.IsCreated) return;
        for (int s = 0; s < FluidSlots; s++) if (fChunk[s] >= 0) FreeBrick(s);
        fGroundChanged.Clear();
        NewDrops.Clear();
        IceAny = false;
    }

    // ------------------------------------------------------------------ the step
    public void StepFluid(float dt)
    {
        if (!fSlot.IsCreated) return;
        fAcc += dt;
        if (fAcc > FluidStep * 3f) fAcc = FluidStep * 3f;      // never more than a few steps to catch up
        int steps = 0;
        while (fAcc >= FluidStep && steps < 2)
        {
            fAcc -= FluidStep; steps++;
            var watch = System.Diagnostics.Stopwatch.StartNew();
            OneFluidStep();
            FluidMs = (float)watch.Elapsed.TotalMilliseconds;
            if (FluidMs > FluidMaxMs) FluidMaxMs = FluidMs;
        }
        fFreeTimer += dt;
        if (fFreeTimer >= 1f) { FreeEmptyBricks(fFreeTimer); fFreeTimer = 0f; }
        RemeshFluid(10);
    }
    public void ResetFluidTiming() { FluidMaxMs = 0f; }

    readonly List<int> fNew = new List<int>();
    void OneFluidStep()
    {
        fStepN++;
        // 1. the ground changed under some bricks: which cells are solid now
        if (fGroundChanged.Count > 0)
        {
            var list = new NativeArray<int>(fGroundChanged.Count, Allocator.TempJob);
            int n = 0;
            foreach (int c in fGroundChanged) { int s = fSlot[c]; if (s >= 0) { list[n++] = s; fAwake[s] = AwakeSteps; fMeshDirty[s] = 1; } }
            fGroundChanged.Clear();
            new FluidSolidJob { vox = vox, blocks = blocks, top = top, chunk = fChunk, water = fWater, gas = fGas, cold = fCold, flag = fFlag, list = list }.Schedule(n, 1).Complete();
            list.Dispose();
        }
        // 2. awake bricks with something in them get their neighbours made, so the fluid can move on into them
        int awake = 0;
        fNew.Clear();
        for (int s = 0; s < FluidSlots; s++)
        {
            int c = fChunk[s];
            if (c < 0 || fAwake[s] == 0 || !InRange(c)) continue;
            awake++;
            int4 sum = fSum[s];
            if (sum.x == 0 && sum.y == 0 && sum.z == 0 && fStepN > 1) continue;
            int bx = c % CX, by = (c / CX) % CY, bz = c / (CX * CY);
            for (int k = 0; k < 6; k++)
            {
                int nx = bx + (k == 0 ? 1 : k == 1 ? -1 : 0), ny = by + (k == 2 ? 1 : k == 3 ? -1 : 0), nz = bz + (k == 4 ? 1 : k == 5 ? -1 : 0);
                if (nx < 0 || ny < 0 || nz < 0 || nx >= CX || ny >= CY || nz >= CZ) continue;
                int nc = nx + CX * (ny + CY * nz);
                if (fSlot[nc] < 0 && fFree.Count > 0 && fNew.Count < 48) fNew.Add(MakeBrick(nc, false));   // (at most 48 new a step: no hitch in a flood)
            }
        }
        if (fNew.Count > 0)
        {
            var list = new NativeArray<int>(fNew.Count, Allocator.TempJob);
            for (int i = 0; i < fNew.Count; i++) list[i] = fNew[i];
            new FluidSolidJob { vox = vox, blocks = blocks, top = top, chunk = fChunk, water = fWater, gas = fGas, cold = fCold, flag = fFlag, list = list }.Schedule(fNew.Count, 1).Complete();
            list.Dispose();
        }
        FluidAwake = awake;
        if (awake == 0) return;
        // 3. move it all.  The bricks go in 8 batches by where they sit (odd or even each way), so no two bricks
        //    worked on at the same time touch the same cell: each batch runs on all the cores.
        var lists = new NativeList<int>[8];
        for (int k = 0; k < 8; k++) lists[k] = new NativeList<int>(64, Allocator.TempJob);
        for (int s = 0; s < FluidSlots; s++)
        {
            int c = fChunk[s];
            if (c < 0 || fAwake[s] == 0 || !InRange(c)) continue;
            int bx = c % CX, by = (c / CX) % CY, bz = c / (CX * CY);
            lists[(bx & 1) + 2 * (by & 1) + 4 * (bz & 1)].Add(s);
        }
        JobHandle h = default(JobHandle);
        for (int k = 0; k < 8; k++)
        {
            if (lists[k].Length == 0) continue;
            h = new FluidJob
            {
                list = lists[k].AsArray(),
                slot = fSlot, chunk = fChunk, water = fWater, gas = fGas, cold = fCold, flag = fFlag,
                awake = fAwake, meshDirty = fMeshDirty, sum = fSum, step = fStepN,
                drops = fDropQ.AsParallelWriter(), makeDrops = DropsOn,
                soak = (uint)math.clamp(SoakPerSecond * FluidStep * 65536f, 0f, 65535f),
                melt = (uint)math.clamp(FluidStep / math.max(1f, MeltSeconds) * 65536f * 4f, 1f, 65535f),     // (checked every 4th step)
                fade = (uint)math.clamp(FluidStep / math.max(0.05f, GasFadeSeconds) * 65536f, 1f, 65535f),
            }.Schedule(lists[k].Length, 1, h);
        }
        h.Complete();
        for (int k = 0; k < 8; k++) lists[k].Dispose();
        int4 d;
        while (fDropQ.TryDequeue(out d)) NewDrops.Add(d);
        bool ice = false;
        for (int s = 0; s < FluidSlots && !ice; s++) if (fChunk[s] >= 0 && fSum[s].w > 0) ice = true;
        IceAny = ice;
    }

    /// Is the chunk's brick within FluidRange of FluidFocus (across the ground)?
    bool InRange(int c)
    {
        if (FluidRange >= 1e8f) return true;
        int bx = c % CX, bz = c / (CX * CY);
        if (FluidAlways != null && FluidAlways.Contains(bx + CX * bz)) return true;
        float x = origin.x + (bx + 0.5f) * FB * FCellSize - FluidFocus.x, z = origin.z + (bz + 0.5f) * FB * FCellSize - FluidFocus.z;
        return x * x + z * z <= FluidRange * FluidRange;
    }

    void FreeEmptyBricks(float dt)
    {
        for (int s = 0; s < FluidSlots; s++)
        {
            if (fChunk[s] < 0) continue;
            int4 sum = fSum[s];
            if (fAwake[s] > 0 || sum.x != 0 || sum.y != 0 || sum.z != 0 || sum.w != 0) { fEmpty[s] = 0f; continue; }
            fEmpty[s] += dt;
            if (fEmpty[s] < 6f) continue;
            // a neighbour still busy keeps it
            int c = fChunk[s];
            int bx = c % CX, by = (c / CX) % CY, bz = c / (CX * CY);
            bool busy = false;
            for (int k = 0; k < 6 && !busy; k++)
            {
                int nx = bx + (k == 0 ? 1 : k == 1 ? -1 : 0), ny = by + (k == 2 ? 1 : k == 3 ? -1 : 0), nz = bz + (k == 4 ? 1 : k == 5 ? -1 : 0);
                if (nx < 0 || ny < 0 || nz < 0 || nx >= CX || ny >= CY || nz >= CZ) continue;
                int ns = fSlot[nx + CX * (ny + CY * nz)];
                if (ns >= 0 && fAwake[ns] > 0) busy = true;
            }
            if (!busy) FreeBrick(s);
        }
    }

    /// Which cells of the listed bricks are solid ground.  Fluid in a cell that has just been filled is pushed up a cell
    /// (if there's room in the brick) or lost.
    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct FluidSolidJob : IJobParallelFor
    {
        [ReadOnly] public NativeArray<byte> vox;
        [ReadOnly] public NativeArray<int4> blocks;
        [ReadOnly] public NativeArray<ushort> top;
        [ReadOnly] public NativeArray<int> chunk;
        [ReadOnly] public NativeArray<int> list;
        [NativeDisableParallelForRestriction] public NativeArray<byte> water, gas, cold, flag;

        public void Execute(int li)
        {
            int s = list[li];
            int c = chunk[s];
            if (c < 0) return;
            int bx = c % CX, by = (c / CX) % CY, bz = c / (CX * CY);
            int b = s * FBC;
            for (int lz = 0; lz < FB; lz++)
                for (int lx = 0; lx < FB; lx++)
                {
                    int vx = (bx * FB + lx) * FCell, vz = (bz * FB + lz) * FCell;
                    for (int ly = 0; ly < FB; ly++)
                    {
                        int vy = (by * FB + ly) * FCell;
                        int n = 0;
                        for (int k = 0; k < 8; k++)
                            if (VoxelAt(vox, blocks, top, vx + (k & 1), vy + ((k >> 1) & 1), vz + (k >> 2)) != Air) n++;
                        int i = b + lx + FB * (ly + FB * lz);
                        bool solid = n >= 5;
                        byte f = flag[i];
                        if (solid && (f & FSolid) == 0)
                        {
                            // filled in: what was here goes up a cell, or is lost
                            int up = ly < FB - 1 ? i + FB : -1;
                            if (up >= 0 && (flag[up] & (FSolid | FIce)) == 0)
                            {
                                water[up] = (byte)math.min(255, water[up] + water[i]);
                                gas[up] = (byte)math.min(255, gas[up] + gas[i]);
                                cold[up] = (byte)math.min(255, cold[up] + cold[i]);
                            }
                            water[i] = 0; gas[i] = 0; cold[i] = 0;
                            f = (byte)(FSolid | (f & 0xF0));                 // (ice in a filled cell is crushed out too; the creek's current mark stays)
                        }
                        else if (!solid) f = (byte)(f & ~FSolid);
                        flag[i] = f;
                    }
                }
        }
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct FluidJob : IJobParallelFor
    {
        [ReadOnly] public NativeArray<int> list;
        [ReadOnly] public NativeArray<int> slot, chunk;
        [NativeDisableParallelForRestriction] public NativeArray<byte> water, gas, cold, flag, awake, meshDirty;
        [NativeDisableParallelForRestriction] public NativeArray<int4> sum;
        public NativeQueue<int4>.ParallelWriter drops;
        public bool makeDrops;
        public int step;
        public uint soak, melt, fade;                        // chances per step, out of 65536

        static uint Hash(int a, int b, int c, int d)
        {
            uint h = (uint)a * 73856093u ^ (uint)b * 19349663u ^ (uint)c * 83492791u ^ (uint)d * 2654435761u;
            h ^= h >> 16; h *= 0x7feb352du; h ^= h >> 15; h *= 0x846ca68bu; h ^= h >> 16;
            return h;
        }

        int Index(int gx, int gy, int gz)
        {
            if (gx < 0 || gy < 0 || gz < 0 || gx >= FNX || gy >= FNY || gz >= FNZ) return -2;   // off the grid
            int s = slot[ChunkOfCell(gx, gy, gz)];
            if (s < 0) return -1;
            return s * FBC + InBrick(gx, gy, gz);
        }
        bool Open(int i) { return i >= 0 && (flag[i] & (FSolid | FIce)) == 0; }
        void Touch(int i) { int s = i / FBC; awake[s] = AwakeSteps; meshDirty[s] = 1; }

        public void Execute(int li)
        {
            int s = list[li];
            int c = chunk[s];
            if (c < 0 || awake[s] == 0) return;
            awake[s] = (byte)(awake[s] - 1);
            StepBrick(s, c);
        }

        void StepBrick(int s, int c)
        {
            int bx = c % CX, by = (c / CX) % CY, bz = c / (CX * CY);
            int b = s * FBC;
            int4 total = int4.zero;
            int rot = step & 3;
            for (int ly = 0; ly < FB; ly++)                  // from the bottom up: water falls a cell per step
                for (int lz = 0; lz < FB; lz++)
                    for (int lx = 0; lx < FB; lx++)
                    {
                        int i = b + lx + FB * (ly + FB * lz);
                        byte f = flag[i];
                        int w = water[i], g = gas[i], k = cold[i];
                        if (w == 0 && g == 0 && k == 0) continue;
                        if ((f & FSolid) != 0) { water[i] = 0; gas[i] = 0; cold[i] = 0; continue; }
                        int gx = bx * FB + lx, gy = by * FB + ly, gz = bz * FB + lz;
                        uint h = Hash(gx, gy, gz, step);
                        bool changed = false;

                        if ((f & FIce) != 0)
                        {
                            // ice: melts back, slowly (not while cold gas is on it)
                            if ((step & 3) == 0 && k < 4 && (h & 65535u) < melt) { flag[i] = (byte)(f & ~FIce); changed = true; }
                            total.w++;
                            w = 0;                                   // (its water isn't loose water)
                        }
                        else if (w > 0)
                        {
                            // freezes if cold gas is here or right next to it
                            int coldAt = k >= 12 ? i : -1;
                            if (coldAt < 0)
                            {
                                for (int d = 0; d < 6 && coldAt < 0; d++)
                                {
                                    int n = Index(gx + (d == 0 ? 1 : d == 1 ? -1 : 0), gy + (d == 2 ? 1 : d == 3 ? -1 : 0), gz + (d == 4 ? 1 : d == 5 ? -1 : 0));
                                    if (n >= 0 && cold[n] >= 12) coldAt = n;
                                }
                            }
                            if (coldAt >= 0 && w >= 4)
                            {
                                flag[i] = (byte)(f | FIce);
                                if (w < 40) { w = 40; water[i] = 40; }
                                cold[coldAt] = (byte)(cold[coldAt] - 12);
                                if (coldAt == i) k = cold[i];
                                Touch(coldAt);
                                Touch(i);
                                total.w++;
                                w = 0;
                                goto Gases;
                            }
                            int below = Index(gx, gy - 1, gz);
                            // free fall (open air under it, two cells down): out it goes as a tumbling cube.  A small
                            // amount waits a little to gather first (so a trickle comes down as small cubes, not mist).
                            if (makeDrops && w >= 16 && Open(below) && water[below] == 0)
                            {
                                int below2 = Index(gx, gy - 2, gz);
                                if (Open(below2) && water[below2] == 0)
                                {
                                    if (w >= DropMin || ((h >> 12) & 7u) == 0)
                                    {
                                        drops.Enqueue(new int4(gx, gy, gz, w));
                                        w = 0; water[i] = 0; changed = true;
                                    }
                                    else total.x += w;                       // (gathering)
                                    goto Gases;
                                }
                            }
                            if (Open(below))
                            {
                                int room = 255 - water[below];
                                int m = math.min(w, room);
                                if (m > 0) { water[below] = (byte)(water[below] + m); w -= m; Touch(below); changed = true; }
                            }
                            bool resting = below >= 0 && !Open(below) || below >= 0 && water[below] >= 250;
                            if ((f & FCurrent) != 0 && w > 0 && resting)
                            {
                                // the creek's current: most of it moves on downstream (along x or z, whichever is open)
                                int sx = (f & 0x10) != 0 ? -1 : 1, sz = (f & 0x20) != 0 ? -1 : 1;
                                bool xFirst = (f & 0x40) != 0;
                                for (int tryk = 0; tryk < 2 && w > 0; tryk++)
                                {
                                    bool alongX = xFirst ^ (tryk == 1);
                                    int n = Index(gx + (alongX ? sx : 0), gy, gz + (alongX ? 0 : sz));
                                    if (!Open(n)) continue;
                                    int m = math.min((w * 3 + 3) / 4, 255 - water[n]);
                                    if (m > 0) { water[n] = (byte)(water[n] + m); w -= m; Touch(n); changed = true; break; }
                                }
                            }
                            if (w > WaterStill && resting)
                            {
                                for (int d0 = 0; d0 < 4; d0++)
                                {
                                    int d = (d0 + rot) & 3;
                                    int n = Index(gx + (d == 0 ? 1 : d == 1 ? -1 : 0), gy, gz + (d == 2 ? 1 : d == 3 ? -1 : 0));
                                    if (!Open(n)) continue;
                                    int wn = water[n];
                                    int diff = w - wn;
                                    if (diff < 2) continue;
                                    int fl = math.max(1, diff / 4);
                                    if (w - fl < WaterStill / 2) fl = math.max(0, w - WaterStill / 2);
                                    if (fl <= 0) continue;
                                    water[n] = (byte)(wn + fl); w -= fl; Touch(n); changed = true;
                                }
                            }
                            // soaks into the ground it lies on (a little at a time, at random so it's even)
                            if (w > 0 && (f & FCurrent) == 0 && below >= 0 && (flag[below] & FSolid) != 0 && ((h >> 8) & 65535u) < soak) { w--; changed = true; }   // (not the creek's bed)
                            if (w > 0 && w <= 2 && ((h >> 3) & 31u) == 0) { w = 0; changed = true; }   // a few drops: dried up
                            // off the grid's edge: gone
                            if (below == -2) { w = 0; changed = true; }
                            water[i] = (byte)w;
                            total.x += w;
                        }

                    Gases:
                        // water filling the cell pushes the gas out of it
                        if ((g > 0 || k > 0) && (w > 200 || (flag[i] & FIce) != 0))
                        {
                            int up = Index(gx, gy + 1, gz);
                            if (Open(up)) { gas[up] = (byte)math.min(255, gas[up] + g); cold[up] = (byte)math.min(255, cold[up] + k); Touch(up); }
                            g = 0; k = 0; gas[i] = 0; cold[i] = 0; changed = true;
                        }
                        if (g > 0) { g = MoveGas(gas, i, g, gx, gy, gz, 1, h, rot, ref changed); gas[i] = (byte)g; total.y += g; }
                        if (k > 0) { k = MoveGas(cold, i, k, gx, gy, gz, -1, h >> 4, rot, ref changed); cold[i] = (byte)k; total.z += k; }
                        if (changed) Touch(i);
                    }
            sum[s] = total;
            // a brick with anything in it stays awake: water soaks away, ice melts and gas thins even when nothing moves
            if (total.x != 0 || total.y != 0 || total.z != 0 || total.w != 0) awake[s] = AwakeSteps;
        }

        /// One cell of gas: drifts up (green) or down (cold), spreads out, thins away.
        int MoveGas(NativeArray<byte> a, int i, int g, int gx, int gy, int gz, int vertical, uint h, int rot, ref bool changed)
        {
            int t = Index(gx, gy + vertical, gz);
            if (t == -1 || t == -2)
            {
                // the open sky (nothing kept up there), or the grid's edge: it drifts off
                if (vertical > 0 || t == -2) { int lose = math.max(1, g / 3); g -= lose; changed = true; }
            }
            else if (Open(t))
            {
                int m = math.min(g * 3 / 4, 255 - a[t]);
                if (m > 0) { a[t] = (byte)(a[t] + m); g -= m; Touch(t); changed = true; }
            }
            // spreads to the sides
            for (int d0 = 0; d0 < 4 && g > 1; d0++)
            {
                int d = (d0 + rot) & 3;
                int n = Index(gx + (d == 0 ? 1 : d == 1 ? -1 : 0), gy, gz + (d == 2 ? 1 : d == 3 ? -1 : 0));
                if (!Open(n)) continue;
                int diff = g - a[n];
                if (diff < 2) continue;
                int fl = math.max(1, diff / 6);
                a[n] = (byte)(a[n] + fl); g -= fl; Touch(n); changed = true;
            }
            // and a little the other way (so a tunnel fills down from its roof)
            int o = Index(gx, gy - vertical, gz);
            if (Open(o) && g > 2)
            {
                int diff = g - a[o];
                if (diff > 6) { int fl = diff / 8; a[o] = (byte)(a[o] + fl); g -= fl; Touch(o); changed = true; }
            }
            if (g > 0 && (h & 65535u) < fade) { g--; changed = true; }
            if (g > 0 && g <= 2 && ((h >> 20) & 15u) == 0) { g = 0; changed = true; }
            return g;
        }
    }

    // ------------------------------------------------------------------ drawing
    struct FVert { public float3 pos; public Color32 color; }
    static readonly VertexAttributeDescriptor[] FLayout =
    {
        new VertexAttributeDescriptor(VertexAttribute.Position, VertexAttributeFormat.Float32, 3),
        new VertexAttributeDescriptor(VertexAttribute.Color, VertexAttributeFormat.UNorm8, 4),
    };

    void RemeshFluid(int budget)
    {
        var list = new List<int>();
        for (int s = 0; s < FluidSlots && list.Count < budget; s++)
            if (fMeshDirty[s] != 0 && fChunk[s] >= 0) { list.Add(s); fMeshDirty[s] = 0; }
        if (list.Count == 0) return;
        int n = list.Count;
        var handles = new NativeArray<JobHandle>(n, Allocator.Temp);
        var verts = new NativeList<FVert>[n];
        var tris = new NativeList<int>[n];
        for (int i = 0; i < n; i++)
        {
            verts[i] = new NativeList<FVert>(256, Allocator.TempJob);
            tris[i] = new NativeList<int>(384, Allocator.TempJob);
            handles[i] = new FluidMeshJob
            {
                vox = vox, blocks = blocks, top = top, slot = fSlot, water = fWater, gas = fGas, cold = fCold, flag = fFlag,
                verts = verts[i], tris = tris[i], origin = origin, s = list[i], c = fChunk[list[i]],
            }.Schedule();
        }
        JobHandle.CompleteAll(handles);
        for (int i = 0; i < n; i++)
        {
            int s = list[i];
            var mf = fMeshes[s];
            if (verts[i].Length == 0)
            {
                if (mf != null) { mf.sharedMesh.Clear(); mf.gameObject.SetActive(false); }
            }
            else
            {
                if (mf == null)
                {
                    var go = new GameObject("Fluid brick");
                    go.transform.SetParent(fRoot, false);
                    mf = go.AddComponent<MeshFilter>();
                    var mr = go.AddComponent<MeshRenderer>();
                    mr.sharedMaterial = fMat;
                    mr.shadowCastingMode = ShadowCastingMode.Off;
                    mr.receiveShadows = false;
                    mf.sharedMesh = new Mesh { indexFormat = IndexFormat.UInt32 };
                    fMeshes[s] = mf;
                }
                mf.gameObject.SetActive(true);
                var mesh = mf.sharedMesh;
                mesh.Clear();
                mesh.SetVertexBufferParams(verts[i].Length, FLayout);
                mesh.SetVertexBufferData(verts[i].AsArray(), 0, 0, verts[i].Length);
                mesh.SetIndexBufferParams(tris[i].Length, IndexFormat.UInt32);
                mesh.SetIndexBufferData(tris[i].AsArray(), 0, 0, tris[i].Length);
                mesh.SetSubMesh(0, new SubMeshDescriptor(0, tris[i].Length), MeshUpdateFlags.DontRecalculateBounds);
                int c = fChunk[s];
                int bx = c % CX, by = (c / CX) % CY, bz = c / (CX * CY);
                Vector3 lo = origin + new Vector3(bx, by, bz) * (FB * FCellSize);
                mesh.bounds = new Bounds(lo + Vector3.one * (FB * FCellSize * 0.5f), Vector3.one * (FB * FCellSize + 0.5f));
            }
            verts[i].Dispose(); tris[i].Dispose();
        }
        handles.Dispose();
    }

    [BurstCompile(CompileSynchronously = true, DisableSafetyChecks = true)]
    struct FluidMeshJob : IJob
    {
        [ReadOnly] public NativeArray<byte> vox;
        [ReadOnly] public NativeArray<int4> blocks;
        [ReadOnly] public NativeArray<ushort> top;
        [ReadOnly] public NativeArray<int> slot;
        [ReadOnly] public NativeArray<byte> water, gas, cold, flag;
        public NativeList<FVert> verts;
        public NativeList<int> tris;
        public float3 origin;
        public int s, c;

        int Index(int gx, int gy, int gz)
        {
            if (gx < 0 || gy < 0 || gz < 0 || gx >= FNX || gy >= FNY || gz >= FNZ) return -1;
            int sl = slot[ChunkOfCell(gx, gy, gz)];
            return sl < 0 ? -1 : sl * FBC + InBrick(gx, gy, gz);
        }

        /// Where the cell's floor is: its bottom, or a voxel up when its bottom layer is mostly ground.
        float FloorIn(int gx, int gy, int gz)
        {
            int vx = gx * FCell, vy = gy * FCell, vz = gz * FCell, n = 0;
            for (int k = 0; k < 4; k++) if (VoxelAt(vox, blocks, top, vx + (k & 1), vy, vz + (k >> 1)) != Air) n++;
            return n >= 2 ? Voxel : 0f;
        }

        void Quad(float3 a, float3 b, float3 cc, float3 d, Color32 col)
        {
            int v = verts.Length;
            verts.Add(new FVert { pos = a, color = col }); verts.Add(new FVert { pos = b, color = col });
            verts.Add(new FVert { pos = cc, color = col }); verts.Add(new FVert { pos = d, color = col });
            tris.Add(v); tris.Add(v + 1); tris.Add(v + 2); tris.Add(v); tris.Add(v + 2); tris.Add(v + 3);
        }

        /// A box from y0 to y1 in the cell, with only the faces the `show` mask allows (+x -x +y -y +z -z).
        void Box(float3 lo, float y0, float y1, int show, Color32 col)
        {
            float e = FCellSize;
            float3 p000 = lo + new float3(0, y0, 0), p100 = lo + new float3(e, y0, 0), p010 = lo + new float3(0, y1, 0), p110 = lo + new float3(e, y1, 0);
            float3 p001 = lo + new float3(0, y0, e), p101 = lo + new float3(e, y0, e), p011 = lo + new float3(0, y1, e), p111 = lo + new float3(e, y1, e);
            Color32 side = Shade(col, 0.78f), side2 = Shade(col, 0.68f), under = Shade(col, 0.55f);
            if ((show & 1) != 0) Quad(p100, p110, p111, p101, side);
            if ((show & 2) != 0) Quad(p000, p001, p011, p010, side);
            if ((show & 4) != 0) Quad(p010, p011, p111, p110, col);
            if ((show & 8) != 0) Quad(p000, p100, p101, p001, under);
            if ((show & 16) != 0) Quad(p001, p101, p111, p011, side2);
            if ((show & 32) != 0) Quad(p000, p010, p110, p100, side2);
        }
        static Color32 Shade(Color32 c, float f) { return new Color32((byte)(c.r * f), (byte)(c.g * f), (byte)(c.b * f), c.a); }

        public void Execute()
        {
            int bx = c % CX, by = (c / CX) % CY, bz = c / (CX * CY);
            int b = s * FBC;
            for (int lz = 0; lz < FB; lz++)
                for (int lx = 0; lx < FB; lx++)
                {
                    int gx = bx * FB + lx, gz = bz * FB + lz;
                    int colTop = top[gx * FCell + NX * gz * FCell];
                    for (int ly = 0; ly < FB; ly++)
                    {
                        int i = b + lx + FB * (ly + FB * lz);
                        byte f = flag[i];
                        if ((f & FSolid) != 0) continue;
                        int w = water[i], g = gas[i], k = cold[i];
                        if (w == 0 && g < 3 && k < 3) continue;
                        int gy = by * FB + ly;
                        float3 lo = origin + new float3(gx, gy, gz) * FCellSize;
                        // under a roof (the mine): darker
                        float dark = colTop > gy * FCell + 24 ? 0.45f : 1f;
                        bool ice = (f & FIce) != 0;
                        if (!ice && w > 0)
                        {
                            // water: a whole block, if there's a fair bit and it sits on something
                            int under = Index(gx, gy - 1, gz);
                            bool sits = under < 0 ? gy * FCell <= colTop : (flag[under] & (FSolid | FIce)) != 0 || water[under] >= WaterShows;
                            if (w >= WaterShows && sits)
                            {
                                int show = 0;
                                for (int d = 0; d < 6; d++)
                                {
                                    int n = Index(gx + (d == 0 ? 1 : d == 1 ? -1 : 0), gy + (d == 2 ? 1 : d == 3 ? -1 : 0), gz + (d == 4 ? 1 : d == 5 ? -1 : 0));
                                    bool hide = n >= 0 && ((flag[n] & FSolid) != 0 || (flag[n] & FIce) == 0 && water[n] >= WaterShows && d != 3);
                                    if (d == 3) hide = n < 0 || (flag[n] & (FSolid | FIce)) != 0 || water[n] >= WaterShows;
                                    if (!hide) show |= 1 << d;
                                }
                                if (show != 0)
                                {
                                    uint hh = (uint)(gx * 73856093) ^ (uint)(gy * 19349663) ^ (uint)(gz * 83492791);
                                    float v = 0.9f + ((hh >> 7) & 15u) / 15f * 0.2f;           // each block a touch different, like the dirt
                                    Color32 col = new Color32((byte)math.min(255f, 55 * dark * v), (byte)math.min(255f, 125 * dark * v), (byte)math.min(255f, 215 * dark * v), 175);
                                    Box(lo, 0f, FCellSize, show, col);
                                }
                            }
                        }
                        if (ice)
                        {
                            float floor = FloorIn(gx, gy, gz);
                            float depth = math.max(w, 40) / 255f * FCellSize;
                            float y1 = math.min(FCellSize, floor + depth);
                            int show = 0;
                            for (int d = 0; d < 6; d++)
                            {
                                int n = Index(gx + (d == 0 ? 1 : d == 1 ? -1 : 0), gy + (d == 2 ? 1 : d == 3 ? -1 : 0), gz + (d == 4 ? 1 : d == 5 ? -1 : 0));
                                bool hide;
                                if (n < 0) hide = d != 2;
                                else if ((flag[n] & FSolid) != 0) hide = true;
                                else if (ice) hide = (flag[n] & FIce) != 0 && (d != 2 || water[i] >= 250);
                                else if ((flag[n] & FIce) != 0) hide = d != 2;
                                else if (d == 2) hide = water[n] > 0 && w >= 250;       // water above a full cell: no surface between
                                else if (d == 3) hide = true;                            // the underside of water never shows
                                else hide = water[n] >= w;                              // a deeper or equal neighbour hides this side
                                if (!hide) show |= 1 << d;
                            }
                            if (show != 0)
                            {
                                Color32 col = new Color32((byte)(225 * dark), (byte)(242 * dark), (byte)(255 * dark), 235);
                                Box(lo, floor, y1, show, col);
                            }
                        }
                        if (g >= 3) GasBox(lo, gx, gy, gz, g, true, dark);
                        if (k >= 3) GasBox(lo, gx, gy, gz, k, false, dark);
                    }
                }
        }

        void GasBox(float3 lo, int gx, int gy, int gz, int g, bool green, float dark)
        {
            int show = 0;
            for (int d = 0; d < 6; d++)
            {
                int n = Index(gx + (d == 0 ? 1 : d == 1 ? -1 : 0), gy + (d == 2 ? 1 : d == 3 ? -1 : 0), gz + (d == 4 ? 1 : d == 5 ? -1 : 0));
                bool hide = n < 0 ? false : (flag[n] & FSolid) != 0 || (green ? gas[n] : cold[n]) >= 3;
                if (!hide) show |= 1 << d;
            }
            if (show == 0) return;
            float a = math.min(0.42f, 0.08f + g / 255f * 0.6f);
            dark = math.max(dark, 0.7f);                        // the haze glows a little: it shows in the dark
            Color32 col = green ? new Color32((byte)(70 * dark), (byte)(230 * dark), (byte)(40 * dark), (byte)(a * 255f))
                                : new Color32((byte)(170 * dark), (byte)(220 * dark), (byte)(255 * dark), (byte)(a * 255f));
            Box(lo, 0f, FCellSize, show, col);
        }
    }
}
