// Water, ice and gas in the game (the simulation itself is VoxelWorldFluid.cs).
//
// Water
//   The creek: a spring seeps out of the sheer face beside the mine door, 2 m up: the water falls down the face and
//   lands by the door.  It runs all the time, at a set
//   rate, and the water goes wherever the ground leads it: into holes you dig, along a channel you cut, in at the mine
//   door.  The ground soaks it up slowly, so it can't flood the site: there is also a cap on all the water there can
//   be at once (the creek and the rain stop adding while it's reached).  Fill a hole and the water in it is pushed out;
//   dig a drain and it runs away.
//   Rain: now and then (every 5 to 9 minutes, the first after about 3) it rains for a minute near you.  The creek runs
//   twice as hard while it rains.
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
    public const float CreekPerSecond = 9000f;                 // units of water (255 = one 12.5 cm cell full) the spring gives
    // Set by the Quality setting (Esc > Settings > Quality), each frame:
    //            simulated round you   water cap         rain lands within
    //   Low      22 m                  3,500 cells (7 m3)   7 m
    //   Medium   48 m                  7,000 cells (14 m3) 10 m     (the numbers it was built with)
    //   High     70 m                 12,000 cells (23 m3) 13 m
    //   Ultra    the whole site       20,000 cells (39 m3) 16 m
    static readonly float[] RangeFor = { 22f, 48f, 70f, 1e9f };
    static readonly int[] CapFor = { 3500, 7000, 12000, 20000 };
    static readonly float[] RainFor = { 7f, 10f, 13f, 16f };
    static int Tier { get { return Mathf.Clamp(PauseMenu.Quality, 0, 3); } }
    public static int WaterCap { get { return 255 * CapFor[Tier]; } }   // all the water there can be at once
    public const float RainEvery = 420f, RainEveryJitter = 120f, RainFirst = 180f, RainLasts = 60f;
    public static float RainRadius { get { return RainFor[Tier]; } }
    public const int GreenPocketGas = 255 * 900, ColdPocketGas = 255 * 500;
    public const float PocketLeakPerSecond = 255 * 70f;
    public const float BlastReach = 2f;                         // gas this close goes off with a blast
    public const float IceBitLife = 7f;

    public Vector3 Spring { get; private set; }               // where the water comes out of the face
    public const float SpringUp = 2f;
    public bool Raining { get { return rainLeft > 0f; } }
    public float RainIn { get { return rainIn; } }
    public static int Blasts { get; private set; }             // (tests)
    public static int IceBroken { get; private set; }
    public static int Frozen { get; private set; }
    public static long CreekGiven { get; private set; }
    /// Something exploded: where, and how far it reaches (enemies listen).
    public static event System.Action<Vector3, float> Exploded;

    public class Pocket { public Vector3 centre; public float radius; public bool cold; public int gas; public bool open, spent; public Vector3 openAt; public AudioSource hiss; }
    public readonly List<Pocket> Pockets = new List<Pocket>();

    float rainIn, rainLeft;
    ParticleSystem rain;
    AudioSource rainSound, creekSound;
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
        rainIn = RainFirst;
    }
    void OnDestroy() { if (Instance == this) Instance = null; Exploded = null; }

    void Start()
    {
        if (w == null) w = VoxelWorld.Instance;
        // the spring: it seeps out of the sheer face beside the mine door, 2 m up.  The water falls down the face and
        // lands at its foot, by the door: some runs into the mine, the rest out over the floor.
        Vector3 s = new Vector3(VoxelWorld.PortalX - 2.4f, SpringUp, 8f);
        for (float z = 8f; z < 16f; z += 0.03f)
        {
            if (w.MaterialAt(new Vector3(s.x, s.y, z)) != VoxelWorld.Air) break;
            s.z = z;
        }
        s.z -= 0.08f;
        Spring = s;
        var springGo = new GameObject("Creek spring");
        springGo.transform.position = Spring;
        springGo.transform.SetParent(transform, true);
        creekSound = GameAudio.Loop(springGo, "creek", 1f, 2f, 18f);

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

        // the creek
        if (WaterOn && room)
        {
            float give = CreekPerSecond * (Raining ? 2f : 1f) * dt;
            int gx, gy, gz;
            if (w.FluidCellOf(Spring, out gx, out gy, out gz))
                for (int k = 0; k < 6 && give > 1f; k++)
                {
                    // out of a slot in the face a few cells wide (and a cell or two high when it backs up)
                    int x = k % 3 - 1, y = k / 3;
                    int put = w.AddWater(gx + x, gy + y, gz, Mathf.CeilToInt(give / (6 - k)));
                    give -= put; CreekGiven += put;
                }
        }
        if (creekSound != null) GameAudio.Steer(creekSound, WaterOn ? 0.35f : 0f, 1f, dt, 2f);

        // the rain
        if (WaterOn && !TrailerMode.On && !Ending.Playing && !Prologue.Playing)
        {
            if (rainLeft > 0f)
            {
                rainLeft -= dt;
                if (rainLeft <= 0f) rainIn = RainEvery + Random.Range(-RainEveryJitter, RainEveryJitter);
            }
            else
            {
                rainIn -= dt;
                if (rainIn <= 0f)
                {
                    StartRain();
                    if (Worker.Instance != null) Worker.Instance.Say("Rain!  For a minute: it runs into your holes, and the creek runs harder.", 3.5f);
                }
            }
        }
        else rainLeft = 0f;
        StepRain(dt, room);

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
        w.StepFluid(dt);
    }

    public void StartRain() { rainLeft = RainLasts; }
    public void StopRain() { rainLeft = 0f; rainIn = RainEvery; }

    void StepRain(float dt, bool room)
    {
        var cam = Camera.main;
        var wk = Worker.Instance;
        Vector3 centre = wk != null ? wk.transform.position : cam != null ? cam.transform.position : Vector3.zero;
        if (rain == null)
        {
            var go = new GameObject("Rain");
            go.transform.SetParent(transform, false);
            rain = go.AddComponent<ParticleSystem>();
            rain.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = rain.main;
            main.loop = true; main.startLifetime = 1.1f; main.startSpeed = 0f; main.startSize = 0.025f;
            main.startColor = new Color(0.75f, 0.82f, 0.95f, 0.45f);
            main.maxParticles = 4000; main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.gravityModifier = 0f;
            var vel = rain.velocityOverLifetime; vel.enabled = true; vel.space = ParticleSystemSimulationSpace.World;
            vel.x = new ParticleSystem.MinMaxCurve(-0.8f); vel.y = new ParticleSystem.MinMaxCurve(-11f); vel.z = new ParticleSystem.MinMaxCurve(0.4f);
            var em = rain.emission; em.rateOverTime = 2600f;
            var shape = rain.shape; shape.shapeType = ParticleSystemShapeType.Box; shape.scale = new Vector3(26f, 0.5f, 26f);
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.renderMode = ParticleSystemRenderMode.Stretch; r.velocityScale = 0.025f; r.lengthScale = 1f;
            var m = new Material(Shader.Find("Sprites/Default"));
            r.sharedMaterial = m;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            rainSound = GameAudio.Loop(gameObject, "rain", 0f);
        }
        rain.transform.position = centre + Vector3.up * 9f;
        if (Raining && !rain.isEmitting) rain.Play();
        if (!Raining && rain.isEmitting) rain.Stop(true, ParticleSystemStopBehavior.StopEmitting);
        bool inMine = wk != null && GameAudio.InMine(wk.transform.position);
        if (rainSound != null) GameAudio.Steer(rainSound, Raining ? (inMine ? 0.12f : 0.45f) : 0f, 1f, dt, 1.5f);
        if (!Raining || !room) return;
        // drops landing near you: each a little water on the ground where it falls
        int drops = Mathf.CeilToInt(350f * dt);
        for (int i = 0; i < drops; i++)
        {
            Vector2 o = Random.insideUnitCircle * RainRadius;
            Vector3 p = new Vector3(centre.x + o.x, 0f, centre.z + o.y);
            if (Mathf.Abs(p.x) > VoxelWorld.SiteHalf - 1f || Mathf.Abs(p.z) > VoxelWorld.SiteHalf - 1f) continue;
            float h = w.TopAt(p.x, p.z);
            int gx, gy, gz;
            if (!w.FluidCellOf(new Vector3(p.x, h + 0.03f, p.z), out gx, out gy, out gz)) continue;
            if (w.AddWater(gx, gy, gz, 30) == 0) w.AddWater(gx, gy + 1, gz, 30);
        }
    }
}
