// Water, ice and gas in the game (the simulation itself is VoxelWorldFluid.cs).
//
// Water
//   The creek (Creek.cs): a spring in the bush on the hill above the mine, outside the quarry cut; its bed runs west
//   and then south down the outside of the quarry, and off the bottom of the map, where the water drains away.  It
//   runs all the time, at a set rate, and the water goes wherever the ground leads it: down its bed, into holes you
//   dig, along a channel you cut off it.  The ground soaks it up slowly, so it can't flood the site: there is also a cap on all the water there can
//   be at once (the creek stops adding while it's reached).  Fill a hole and the water in it is pushed out;
//   dig a drain and it runs away.
//   Water is drawn as chunky see-through blocks, and water in free fall (off the face, over an edge into a hole)
//   comes down as tumbling cubes that land back as blocks (the drops, at the end of this file).
//   (No rain: the owner tried it on 23 Nov and it looked bad, so it came out.)
//
// Ice
//   Water that freezes is solid ice: you can walk on it, and the pick, the jackhammer or the rifle breaks it into loose
//   bits that melt back to water after a few seconds.  Ice melts back on its own, slowly (about a minute and a half).
//   Two ways to freeze water: the freeze gun (5 on foot, or the bumpers) shoots cold, and blue cold-gas pockets deep
//   in the rock leak cold gas when you break into one: it sinks, and freezes any water it touches.
//
// Gas
//   Green gas pockets in the rock leak a faint green haze when broken into.  It rises and fills the tunnel from the
//   roof down, and slowly thins away.  A rifle shot through it, or a jackhammer blow in it, sets it off: a crater,
//   the dirt thrown out as clods (the dirt books stay exact: it's the pick's own job, VoxelWorld.Pick), and the haze
//   nearby goes off after it.  It never hurts you.  The cold gas doesn't explode.
//
// Nothing here is saved: a loaded game starts dry, and pockets already dug open stay spent.
using System.Collections.Generic;
using UnityEngine;

public class Fluids : MonoBehaviour
{
    public static Fluids Instance { get; private set; }
    public static bool WaterOn = true, GasOn = true;            // (off switches, for tests and if it ever misbehaves)

    // ---- tuning
    public const float CreekPerSecond = 14000f;                 // units of water (255 = one 12.5 cm cell full) the spring gives
    // Set by the Quality setting (Esc > Settings > Quality), each frame:
    //            simulated round you   water cap              falling cubes at once
    //   Low      22 m                  3,500 cells (7 m3)     120
    //   Medium   48 m                  7,000 cells (14 m3)    250     (the numbers it was built with)
    //   High     70 m                 12,000 cells (23 m3)    400
    //   Ultra    the whole site       20,000 cells (39 m3)    600
    static readonly float[] RangeFor = { 22f, 48f, 70f, 1e9f };
    static readonly int[] CapFor = { 3500, 7000, 12000, 20000 };
    static int Tier { get { return Mathf.Clamp(PauseMenu.Quality, 0, 3); } }
    public static int WaterCap { get { return 255 * CapFor[Tier]; } }   // all the water there can be at once
    public const int GreenPocketGas = 255 * 900, ColdPocketGas = 255 * 500;
    public const float PocketLeakPerSecond = 255 * 70f;
    public const float BlastReach = 2f;                         // gas this close goes off with a blast
    public const float IceBitLife = 7f;

    public Vector3 Spring { get { return Creek.Spring; } }    // where the creek's water comes out (Creek.cs)
    public static long Drained { get; private set; }          // water that has run off the map down the creek (tests)
    readonly HashSet<int> creekColumns = new HashSet<int>();
    public static int Blasts { get; private set; }             // (tests)
    public static int IceBroken { get; private set; }
    public static int Frozen { get; private set; }
    public static long CreekGiven { get; private set; }
    /// Something exploded: where, and how far it reaches (enemies listen).
    public static event System.Action<Vector3, float> Exploded;

    public class Pocket { public Vector3 centre; public float radius; public bool cold; public int gas; public bool open, spent; public Vector3 openAt; public AudioSource hiss; }
    public readonly List<Pocket> Pockets = new List<Pocket>();

    AudioSource creekSound;
    VoxelWorld w;

    struct Blast { public Vector3 at; public float when; }
    readonly List<Blast> pending = new List<Blast>();
    float blastBudget = 30f;                                    // chain blasts allowed (it fills back up over time)
    bool blasting;

    class IceBit { public Transform t; public Vector3 v; public float age; public int water; public bool resting; }
    readonly List<IceBit> bits = new List<IceBit>();
    Material iceMat, frostMat;
    Light flash;
    float flashLife;

    void Awake()
    {
        Instance = this;
        w = GetComponent<VoxelWorld>();
    }
    void OnDestroy() { if (Instance == this) Instance = null; Exploded = null; }

    void Start()
    {
        if (w == null) w = VoxelWorld.Instance;
        // (the spring is the creek's, Creek.cs: set up once SiteProps has cut its bed.  No creek sound: the owner found
        // the bubbling loop horrible, 23 Nov.)

        // the pockets, in the walls of the deep tunnel (where the gold is)
        AddPocket(14f, 1, 1.0f, false);
        AddPocket(21f, -1, 1.1f, false);
        AddPocket(26f, 1, 0.8f, false);
        AddPocket(30.5f, -1, 1.3f, false);
        AddPocket(17.5f, -1, 0.9f, true);
        AddPocket(24.5f, 1, 1.2f, true);
        AddPocket(29.5f, 1, 1.4f, true);

        VoxelWorld.Picked += OnPicked;
    }

    void AddPocket(float along, int side, float up, bool cold)
    {
        float half = VoxelWorld.TunnelHalfWidthAt(along);
        var c = new Vector3(VoxelWorld.PortalX + side * (half + 0.55f), up, VoxelWorld.PortalZ + along);
        if (w.MaterialAt(c) == VoxelWorld.Air) return;          // (not in solid rock after all: leave it out)
        Pockets.Add(new Pocket { centre = c, radius = 0.45f, cold = cold, gas = cold ? ColdPocketGas : GreenPocketGas });
    }

    /// After a load: no water or gas, and a pocket that's already dug open is spent.
    public void AfterLoad()
    {
        Creek.Cut(w);                                          // (a save from before the creek: its bed again)
        w.ClearFluids();
        pending.Clear();
        foreach (var p in Pockets)
        {
            StopHiss(p);
            p.open = false; p.spent = false; p.gas = p.cold ? ColdPocketGas : GreenPocketGas;
            if (PocketBroken(p)) p.spent = true;
        }
    }
    /// After the ground is reset: everything as new, every pocket full again.
    public void AfterReset()
    {
        Creek.Cut(w);
        w.ClearFluids();
        pending.Clear();
        foreach (var p in Pockets) { StopHiss(p); p.open = false; p.spent = false; p.gas = p.cold ? ColdPocketGas : GreenPocketGas; }
    }
    bool PocketBroken(Pocket p)
    {
        if (w.MaterialAt(p.centre) == VoxelWorld.Air) return true;
        for (int i = 0; i < 26; i++)
        {
            Vector3 d = new Vector3(i % 3 - 1, (i / 3) % 3 - 1, i / 9 - 1);
            if (d == Vector3.zero) continue;
            if (w.MaterialAt(p.centre + d.normalized * p.radius) == VoxelWorld.Air) return true;
        }
        return false;
    }
    void StopHiss(Pocket p) { if (p.hiss != null) { Destroy(p.hiss); p.hiss = null; } }

    // ------------------------------------------------------------------ the pick, the jackhammer, the rifle, blasts
    /// The ground was broken at `at` (VoxelWorld.Pick): ice there breaks, a pocket there opens, and a jackhammer
    /// blow in strong gas sets it off.
    void OnPicked(Vector3 at, float radius, bool hammer)
    {
        if (blasting) { OpenPockets(at, radius); return; }
        BreakIce(at, radius + 0.08f, Vector3.up * 1.5f);
        OpenPockets(at, radius);
        if (hammer && GasOn && w.GasAt(at) >= VoxelWorld.GasGoesOff) GoOff(at);
        else if (hammer && GasOn)
        {
            // the bit is in the rock face: the gas is in the air just in front of it
            Vector3 gat; int g = StrongestGasNear(at, 0.35f, out gat);
            if (g >= VoxelWorld.GasGoesOff) GoOff(gat);
        }
    }

    void OpenPockets(Vector3 at, float radius)
    {
        foreach (var p in Pockets)
        {
            if (p.open || p.spent) continue;
            if (Vector3.Distance(at, p.centre) > p.radius + radius + 0.12f) continue;
            p.open = true; p.openAt = at;
            var go = new GameObject("Gas leak");
            go.transform.position = at; go.transform.SetParent(transform, true);
            p.hiss = GameAudio.Loop(go, "hiss", 1f, 1.5f, 14f);
            if (Worker.Instance != null) Worker.Instance.Say(p.cold ? "Cold gas!  It freezes any water it touches." : "Gas!  Green gas is leaking out.  A shot or the jackhammer will set it off.", 4f);
        }
    }

    int StrongestGasNear(Vector3 at, float r, out Vector3 where)
    {
        where = at; int best = 0;
        int gx, gy, gz;
        if (!w.FluidCellOf(at, out gx, out gy, out gz)) return 0;
        int n = Mathf.CeilToInt(r / VoxelWorld.FCellSize);
        for (int z = -n; z <= n; z++) for (int y = -n; y <= n; y++) for (int x = -n; x <= n; x++)
        {
            int g = w.GasAt(gx + x, gy + y, gz + z);
            if (g > best) { best = g; where = w.FluidCellCentre(gx + x, gy + y, gz + z); }
        }
        return best;
    }

    /// A rifle shot from `from` along `dir`, reaching `dist`: sets off any strong gas it passes through.
    public bool ShotThrough(Vector3 from, Vector3 dir, float dist)
    {
        if (!GasOn) return false;
        Vector3 at;
        int g = w.GasAlong(from, dir, dist, out at);
        if (g < VoxelWorld.GasGoesOff) return false;
        GoOff(at);
        return true;
    }

    /// The gas at `at` explodes now.
    public void GoOff(Vector3 at)
    {
        if (blastBudget < 1f) return;
        blastBudget -= 1f;
        Blasts++;
        // the gas within reach burns away; how much there was sets the size of the blast
        int gx, gy, gz;
        long burnt = 0;
        if (w.FluidCellOf(at, out gx, out gy, out gz))
        {
            int n = Mathf.CeilToInt(BlastReach / VoxelWorld.FCellSize);
            for (int z = -n; z <= n; z++) for (int y = -n; y <= n; y++) for (int x = -n; x <= n; x++)
            {
                if (x * x + y * y + z * z > n * n) continue;
                burnt += w.TakeGas(gx + x, gy + y, gz + z, false);
            }
        }
        float full = burnt / 255f;                               // in full cells of gas
        float r = Mathf.Clamp(0.45f + 0.09f * Mathf.Sqrt(full), 0.5f, 1.25f);
        // the crater: the ground nearest the blast, broken and thrown out (the pick's own job, so every voxel is kept)
        Vector3 c = at;
        Vector3 hit; byte mat;
        Vector3 down = Vector3.down;
        float best = 99f; Vector3 face = at;
        Vector3[] dirs = { Vector3.down, Vector3.up, Vector3.left, Vector3.right, Vector3.forward, Vector3.back };
        foreach (var d in dirs)
            if (w.Raycast(at, d, r + 0.6f, out hit, out mat)) { float dd = Vector3.Distance(at, hit); if (dd < best) { best = dd; face = hit; down = d; } }
        if (best < 98f) c = Vector3.Lerp(at, face, 0.6f);
        blasting = true;
        w.Pick(c, r * 0.75f, -down * 5.5f + Vector3.up * 2f, 0f, true);
        for (int k = 0; k < 6; k++)
        {
            Vector3 d = dirs[k];
            if (d == down) continue;
            w.Pick(c + d * r * 0.5f, r * 0.55f, d * 5f + Vector3.up * 2.5f, 0f, true);
        }
        blasting = false;
        BreakIce(at, r + 0.4f, Vector3.up * 4f);
        // light, smoke, sound, a shake
        if (flash == null)
        {
            var lg = new GameObject("Blast light");
            lg.transform.SetParent(transform, false);
            flash = lg.AddComponent<Light>();
            flash.type = LightType.Point; flash.color = new Color(1f, 0.75f, 0.4f); flash.shadows = LightShadows.None;
        }
        flash.transform.position = at;
        flash.range = 10f + r * 6f; flash.intensity = 7f; flash.enabled = true; flashLife = 0.35f;
        for (int i = 0; i < 14; i++)
            HeavyFX.Puff(at + Random.insideUnitSphere * r, Random.insideUnitSphere * 2.5f + Vector3.up, 0.5f + r * 0.6f, Random.Range(1.5f, 3f),
                         i < 5 ? new Color(1f, 0.6f, 0.2f, 0.7f) : new Color(0.35f, 0.33f, 0.3f, 0.6f));
        GameAudio.PlayAt("boom", at, 1f, 0.9f + 0.2f * Random.value);
        var wk = Worker.Instance;
        float far = wk != null ? Vector3.Distance(wk.transform.position, at) : 30f;
        FollowCamera.Shake = Mathf.Max(FollowCamera.Shake, Mathf.Lerp(0.06f, 0.005f, Mathf.Clamp01(far / 30f)));
        if (Exploded != null) Exploded(at, r + 2f);
        // the haze nearby goes off after it
        Vector3 next;
        int g2 = StrongestGasNear(at, BlastReach + 1.2f, out next);
        if (g2 >= VoxelWorld.GasGoesOff) pending.Add(new Blast { at = next, when = Time.time + 0.12f });
    }

    // ------------------------------------------------------------------ ice
    /// Breaks the ice within `radius` of `at` into loose bits.  Returns how many cells broke.
    public int BreakIce(Vector3 at, float radius, Vector3 kick)
    {
        int gx, gy, gz;
        if (!w.FluidReady || w.FluidBricks == 0 || !w.FluidCellOf(at, out gx, out gy, out gz)) return 0;
        int n = Mathf.CeilToInt(radius / VoxelWorld.FCellSize), broke = 0;
        for (int z = -n; z <= n; z++) for (int y = -n; y <= n; y++) for (int x = -n; x <= n; x++)
        {
            Vector3 cc = w.FluidCellCentre(gx + x, gy + y, gz + z);
            if ((cc - at).sqrMagnitude > radius * radius) continue;
            int water = w.BreakIceCell(gx + x, gy + y, gz + z);
            if (water <= 0) continue;
            broke++;
            AddBit(cc, kick + Random.insideUnitSphere * 1.2f, water);
        }
        if (broke > 0)
        {
            IceBroken += broke;
            GameAudio.PlayAt("ice_break", at, 0.6f, 0.9f + 0.3f * Random.value);
        }
        return broke;
    }

    void AddBit(Vector3 at, Vector3 v, int water)
    {
        if (bits.Count >= 160)
        {
            // too many lying about: this one just melts where it is
            int gx, gy, gz;
            if (w.FluidCellOf(at, out gx, out gy, out gz)) w.AddWater(gx, gy, gz, water);
            return;
        }
        if (iceMat == null) iceMat = new Material(Shader.Find("Standard")) { color = new Color(0.82f, 0.93f, 1f) };
        var g = GameObject.CreatePrimitive(PrimitiveType.Cube);
        g.name = "Ice bit";
        Destroy(g.GetComponent<Collider>());
        g.GetComponent<MeshRenderer>().sharedMaterial = iceMat;
        g.transform.SetParent(transform, false);
        g.transform.position = at;
        g.transform.rotation = Random.rotation;
        g.transform.localScale = Vector3.one * Random.Range(0.06f, 0.1f);
        bits.Add(new IceBit { t = g.transform, v = v, water = water });
    }

    void StepBits(float dt)
    {
        for (int i = bits.Count - 1; i >= 0; i--)
        {
            var b = bits[i];
            b.age += dt;
            if (!b.resting)
            {
                b.v += Physics.gravity * dt;
                Vector3 p = b.t.position + b.v * dt;
                float floor = Mathf.Max(w.FloorAt(p + Vector3.up * 0.3f), w.IceFloorAt(p + Vector3.up * 0.3f, 1f));
                if (p.y < floor + 0.03f) { p.y = floor + 0.03f; b.v *= 0.3f; if (b.v.magnitude < 0.4f) b.resting = true; b.v.y = Mathf.Abs(b.v.y) * 0.3f; }
                b.t.position = p;
            }
            float left = IceBitLife - b.age;
            if (left < 2f) b.t.localScale = Vector3.one * Mathf.Max(0.01f, 0.08f * left / 2f);
            if (b.age >= IceBitLife)
            {
                int gx, gy, gz;
                if (w.FluidCellOf(b.t.position + Vector3.up * 0.02f, out gx, out gy, out gz)) w.AddWater(gx, gy, gz, b.water);   // melted
                Destroy(b.t.gameObject);
                bits.RemoveAt(i);
            }
        }
    }
    public int IceBits { get { return bits.Count; } }

    // ------------------------------------------------------------------ the freeze gun
    public const float FreezeRange = 25f, FreezeSplash = 0.55f;
    /// One shot of the freeze gun: water it passes through or lands near turns to ice; it leaves a puff of cold gas
    /// where it lands.  Returns how many cells froze.
    public int FreezeShot(Vector3 from, Vector3 dir, Vector3 muzzle)
    {
        dir.Normalize();
        GameAudio.PlayAt("freeze", muzzle, 0.6f, 0.95f + 0.1f * Random.value);
        int froze = 0;
        Vector3 end = from + dir * FreezeRange;
        for (float t = 0.3f; t <= FreezeRange; t += 0.06f)
        {
            Vector3 p = from + dir * t;
            if (w.MaterialAt(p) != VoxelWorld.Air || w.IceAt(p)) { end = p; break; }
            int gx, gy, gz;
            if (w.FluidCellOf(p, out gx, out gy, out gz) && w.WaterAt(gx, gy, gz) > 0 && w.FreezeCell(gx, gy, gz)) froze++;
        }
        Vector3 back = end - dir * 0.08f;
        int cx, cy, cz;
        if (w.FluidCellOf(back, out cx, out cy, out cz))
        {
            int n = Mathf.CeilToInt(FreezeSplash / VoxelWorld.FCellSize);
            for (int z = -n; z <= n; z++) for (int y = -n; y <= n; y++) for (int x = -n; x <= n; x++)
            {
                if (x * x + y * y + z * z > n * n) continue;
                if (w.WaterAt(cx + x, cy + y, cz + z) > 0 && w.FreezeCell(cx + x, cy + y, cz + z)) froze++;
            }
            for (int z = -1; z <= 1; z++) for (int x = -1; x <= 1; x++) w.AddGas(cx + x, cy, cz + z, 14, true);   // a little cold lingers
        }
        Frozen += froze;
        if (frostMat == null) frostMat = new Material(Shader.Find("Unlit/Color")) { color = new Color(0.75f, 0.92f, 1f) };
        StartCoroutine(Beam(muzzle, end));
        for (int i = 0; i < 3; i++) HeavyFX.Puff(back + Random.insideUnitSphere * 0.15f, Random.insideUnitSphere * 0.4f, 0.35f, 1.2f, new Color(0.85f, 0.95f, 1f, 0.5f));
        return froze;
    }

    System.Collections.IEnumerator Beam(Vector3 a, Vector3 b)
    {
        var g = GameObject.CreatePrimitive(PrimitiveType.Cube);
        Destroy(g.GetComponent<Collider>());
        g.GetComponent<MeshRenderer>().sharedMaterial = frostMat;
        g.GetComponent<MeshRenderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        Vector3 d = b - a;
        g.transform.position = a + d * 0.5f;
        if (d.sqrMagnitude > 0.0001f) g.transform.rotation = Quaternion.LookRotation(d);
        g.transform.localScale = new Vector3(0.025f, 0.025f, d.magnitude);
        yield return new WaitForSeconds(0.07f);
        Destroy(g);
    }

    // ------------------------------------------------------------------ every frame
    void Update()
    {
        if (w == null || !w.FluidReady) return;
        float dt = Time.deltaTime;
        if (dt <= 0f) return;
        var wkf = Worker.Instance;
        w.FluidFocus = wkf != null ? wkf.transform.position : Vector3.zero;
        w.FluidRange = RangeFor[Tier];
        var t = w.FluidRoughTotals();
        bool room = t.x < WaterCap;

        // the creek: water wells up at the spring, and drains away where the bed leaves the map.  Its whole length is
        // always worked on (at Medium quality and up), so it keeps running wherever you are.
        if (Creek.Line.Count > 0 && creekColumns.Count == 0)
            foreach (var cp in Creek.Line)
                for (int k = 0; k < 9; k++) creekColumns.Add(w.ChunkColumnOf(cp + new Vector3((k % 3 - 1) * 1.6f, 0f, (k / 3 - 1) * 1.6f)));   // (its banks too)
        w.FluidAlways = Tier >= 1 ? creekColumns : null;
        if (WaterOn && room && Creek.Line.Count > 0)
        {
            float give = CreekPerSecond * dt;
            int gx, gy, gz;
            if (w.FluidCellOf(Spring + Vector3.up * 0.07f, out gx, out gy, out gz))
                for (int k = 0; k < 9 && give > 1f; k++)
                {
                    int x = k % 3 - 1, z = k / 3 - 1;
                    int put = w.AddWater(gx + x, gy, gz + z, Mathf.CeilToInt(give / (9 - k)));
                    if (put == 0) put = w.AddWater(gx + x, gy + 1, gz + z, Mathf.CeilToInt(give / (9 - k)));
                    give -= put; CreekGiven += put;
                }
        }
        if (Creek.Line.Count > 0)
        {
            // off the map: the last metre of the bed
            int gx, gy, gz;
            Vector3 end = Creek.End;
            if (w.FluidCellOf(end + Vector3.up * 0.07f, out gx, out gy, out gz))
                for (int z = -8; z <= 4; z++) for (int x = -12; x <= 12; x++) for (int y = -2; y <= 6; y++)
                    Drained += w.TakeWater(gx + x, gy + y, gz + z);
        }


        // the pockets leak
        foreach (var p in Pockets)
        {
            if (!p.open || p.spent) continue;
            int gx, gy, gz;
            int give = Mathf.Min(p.gas, Mathf.CeilToInt(PocketLeakPerSecond * dt));
            if (give > 0 && (p.cold || GasOn) && w.FluidCellOf(p.openAt, out gx, out gy, out gz))
            {
                // into the open cells at the hole (the nearest first)
                int left = give;
                for (int r = 0; r <= 3 && left > 0; r++)
                    for (int k = 0; k < 27 && left > 0; k++)
                    {
                        int x = (k % 3 - 1) * r, y = ((k / 3) % 3 - 1) * r, z = (k / 9 - 1) * r;
                        if (r == 0 && k > 0) break;
                        left -= w.AddGas(gx + x, gy + y, gz + z, Mathf.Min(left, 120), p.cold);
                    }
                p.gas -= give - left;
            }
            if (p.hiss != null) GameAudio.Steer(p.hiss, p.gas > 0 ? 0.4f : 0f, 1f, dt, 3f);
            if (p.gas <= 0) { p.spent = true; StopHiss(p); }
        }

        // blasts going off after one another through the haze
        blastBudget = Mathf.Min(30f, blastBudget + dt * 3f);
        for (int i = pending.Count - 1; i >= 0; i--)
            if (Time.time >= pending[i].when) { var b = pending[i]; pending.RemoveAt(i); GoOff(b.at); }

        if (flash != null && flashLife > 0f) { flashLife -= dt; flash.intensity = 7f * Mathf.Clamp01(flashLife / 0.35f); if (flashLife <= 0f) flash.enabled = false; }
        StepBits(dt);
        MakeDrops();
        StepDrops(dt);
        w.StepFluid(dt);
        DrawDrops();
    }

    // ------------------------------------------------------------------ falling water: tumbling cubes
    // Water in free fall leaves the grid (VoxelWorldFluid.cs) as a cube the size of its water (a full cell's worth is
    // a 12.5 cm block).  It tumbles down, bounces once off the ground, and goes back into the grid where it stops.
    static readonly int[] DropCapFor = { 120, 250, 400, 600 };  // cubes in the air at once, by Quality
    public static int MaxDrops { get { return DropCapFor[Tier]; } }
    public static int DropsMade { get; private set; }
    public static int DropsLanded { get; private set; }
    public int DropsFlying { get { return drops.Count; } }
    class Drop { public Vector3 p, v, spin; public Quaternion r; public int water, bounces; public float age, size; }
    readonly List<Drop> drops = new List<Drop>();
    Mesh dropMesh;

    void MakeDrops()
    {
        var list = w.NewDrops;
        for (int i = 0; i < list.Count; i++)
        {
            var d = list[i];
            Vector3 c = w.FluidCellCentre(d.x, d.y, d.z);
            if (drops.Count >= MaxDrops)
            {
                // too many in the air: this one falls on in the grid
                if (w.AddWater(d.x, d.y - 1, d.z, d.w) < d.w) w.AddWater(d.x, d.y, d.z, d.w);
                continue;
            }
            DropsMade++;
            drops.Add(new Drop
            {
                p = c, v = new Vector3(Random.Range(-0.25f, 0.25f), -0.6f, Random.Range(-0.25f, 0.25f)),
                r = Random.rotation, spin = Random.insideUnitSphere * 400f, water = d.w,
                size = VoxelWorld.FCellSize * Mathf.Pow(d.w / 255f, 1f / 3f),
            });
        }
        list.Clear();
    }

    bool Blocked(Vector3 p)
    {
        if (w.MaterialAt(p) != VoxelWorld.Air) return true;
        if (w.IceAny && w.IceAt(p)) return true;
        return false;
    }

    void StepDrops(float dt)
    {
        for (int i = drops.Count - 1; i >= 0; i--)
        {
            var d = drops[i];
            d.age += dt;
            d.v += Physics.gravity * dt;
            Vector3 next = d.p + d.v * dt;
            float half = d.size * 0.5f;
            bool land = false;
            // into a wall: it stops going that way
            if (Blocked(new Vector3(next.x, d.p.y, next.z))) { next.x = d.p.x; next.z = d.p.z; d.v.x *= -0.3f; d.v.z *= -0.3f; }
            // onto the ground (or ice), or into standing water
            if (d.v.y < 0f && (Blocked(next - Vector3.up * half) || w.WaterAt(next) >= 160))
            {
                if (d.bounces == 0 && d.v.y < -2.5f && w.WaterAt(next) < 160)
                {
                    d.bounces++;
                    d.v = new Vector3(d.v.x * 0.6f + Random.Range(-0.4f, 0.4f), -d.v.y * 0.22f, d.v.z * 0.6f + Random.Range(-0.4f, 0.4f));
                    d.spin = Random.insideUnitSphere * 600f;
                    next = d.p;
                }
                else land = true;
            }
            if (land || d.age > 4f || Mathf.Abs(next.x) > VoxelWorld.SiteHalf || Mathf.Abs(next.z) > VoxelWorld.SiteHalf)
            {
                PutBack(d);
                drops.RemoveAt(i);
                continue;
            }
            d.p = next;
            d.r = Quaternion.Euler(d.spin * dt) * d.r;
        }
    }

    /// A cube comes to rest: its water goes back into the grid where it is (and spills to the cells round it).
    void PutBack(Drop d)
    {
        DropsLanded++;
        int gx, gy, gz;
        if (!w.FluidCellOf(d.p, out gx, out gy, out gz)) return;
        int left = d.water;
        for (int k = 0; k < 7 && left > 0; k++)
        {
            int x = k == 1 ? 1 : k == 2 ? -1 : 0, z = k == 3 ? 1 : k == 4 ? -1 : 0, y = k == 5 ? 1 : k == 6 ? 2 : 0;
            left -= w.AddWater(gx + x, gy + y, gz + z, left);
        }
    }

    void DrawDrops()
    {
        if (drops.Count == 0) return;
        var mat = w.FluidMaterial;
        if (mat == null) return;
        if (dropMesh == null) dropMesh = MakeDropMesh();
        for (int i = 0; i < drops.Count; i++)
        {
            var d = drops[i];
            Graphics.DrawMesh(dropMesh, Matrix4x4.TRS(d.p, d.r, Vector3.one * d.size), mat, 0, null, 0, null, false, false);
        }
    }

    /// A unit cube, see-through blue, each side shaded (the same look as the water blocks).
    static Mesh MakeDropMesh()
    {
        var v = new List<Vector3>(); var c = new List<Color32>(); var t = new List<int>();
        Color32 top = new Color32(70, 140, 225, 185);
        System.Action<Vector3, Vector3, Vector3, float> face = (n, u, r, shade) =>
        {
            int b = v.Count;
            Vector3 o = n * 0.5f;
            v.Add(o - u * 0.5f - r * 0.5f); v.Add(o + u * 0.5f - r * 0.5f); v.Add(o + u * 0.5f + r * 0.5f); v.Add(o - u * 0.5f + r * 0.5f);
            var col = new Color32((byte)(top.r * shade), (byte)(top.g * shade), (byte)(top.b * shade), top.a);
            for (int k = 0; k < 4; k++) c.Add(col);
            t.Add(b); t.Add(b + 1); t.Add(b + 2); t.Add(b); t.Add(b + 2); t.Add(b + 3);
        };
        face(Vector3.up, Vector3.forward, Vector3.right, 1f);
        face(Vector3.down, Vector3.right, Vector3.forward, 0.55f);
        face(Vector3.right, Vector3.up, Vector3.forward, 0.78f);
        face(Vector3.left, Vector3.forward, Vector3.up, 0.78f);
        face(Vector3.forward, Vector3.right, Vector3.up, 0.68f);
        face(Vector3.back, Vector3.up, Vector3.right, 0.68f);
        var m = new Mesh();
        m.SetVertices(v); m.SetColors(c); m.SetTriangles(t, 0);
        m.RecalculateBounds();
        return m;
    }
}
