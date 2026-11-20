// Smoke and dust, to make the machine feel heavy.  One particle system of soft puffs (cheap: a few hundred at most,
// no lights, no shadows), used by:
//   the dozer (DozerFX): grey puffs from the exhaust stack as the throttle opens, thick black puffs while it labours,
//                        dust where the blade cuts (more in dry soil, little in clay)
//   the cart: dust while it is tipped out, and where a shovelful lands
using System.Collections.Generic;
using UnityEngine;

public class HeavyFX : MonoBehaviour
{
    static HeavyFX instance;
    ParticleSystem puffs;
    struct Later { public float at; public Vector3 pos; public float size; public Color col; }
    readonly List<Later> later = new List<Later>();

    public static int Alive { get { return instance != null && instance.puffs != null ? instance.puffs.particleCount : 0; } }
    public static int Emitted { get; private set; }                        // (tests)

    static HeavyFX Get()
    {
        if (instance == null) instance = new GameObject("Smoke and dust").AddComponent<HeavyFX>();
        return instance;
    }

    /// One soft puff: `size` metres across to start with (it grows as it drifts), `life` seconds.
    public static void Puff(Vector3 at, Vector3 velocity, float size, float life, Color col)
    {
        var p = Get().puffs;
        var e = new ParticleSystem.EmitParams { position = at, velocity = velocity, startSize = size, startLifetime = life, startColor = col, rotation = Random.Range(0f, 360f) };
        p.Emit(e, 1);
        Emitted++;
    }

    /// A little cloud of dust where dirt lands or is torn up: `n` puffs round `at`.
    public static void Dust(Vector3 at, int n, float size, Color col, float delay = 0f)
    {
        if (delay > 0f) { Get().later.Add(new Later { at = Time.time + delay, pos = at, size = size * n, col = col }); return; }
        for (int i = 0; i < n; i++)
            Puff(at + Random.insideUnitSphere * size * 0.6f, Random.insideUnitSphere * 0.4f + Vector3.up * Random.Range(0.2f, 0.6f),
                 size * Random.Range(0.7f, 1.2f), Random.Range(1.2f, 2.2f), col * Random.Range(0.9f, 1.1f));
    }

    /// The colour of dust off a material (dry soil pale brown, clay darker, rock grey).
    public static Color DustColour(byte m)
    {
        if (m >= VoxelWorld.LooseSoil) m -= VoxelWorld.LooseSoil - VoxelWorld.Soil;
        Color c = m == VoxelWorld.Clay ? new Color(0.55f, 0.36f, 0.24f) : m == VoxelWorld.Rock ? new Color(0.55f, 0.53f, 0.5f)
                : m == VoxelWorld.Quartz || m == VoxelWorld.Gold ? new Color(0.75f, 0.74f, 0.7f) : new Color(0.66f, 0.55f, 0.4f);
        c.a = 0.55f;
        return c;
    }

    /// How dusty a material is: dry soil the most, clay hardly at all.
    public static float Dustiness(byte m)
    {
        if (m >= VoxelWorld.LooseSoil) m -= VoxelWorld.LooseSoil - VoxelWorld.Soil;
        return m == VoxelWorld.Soil ? 1f : m == VoxelWorld.Clay ? 0.2f : m == VoxelWorld.Rock ? 0.6f : m == VoxelWorld.Air ? 0f : 0.5f;
    }

    void Awake()
    {
        var mat = new Material(Shader.Find("Voxel/FireSmoke"));
        mat.SetTexture("_MainTex", PuffTexture());
        var go = new GameObject("Puffs");
        go.transform.SetParent(transform, false);
        puffs = go.AddComponent<ParticleSystem>();
        puffs.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        var main = puffs.main;
        main.loop = false; main.playOnAwake = false; main.maxParticles = 400;
        main.simulationSpace = ParticleSystemSimulationSpace.World;
        main.gravityModifier = -0.02f;                                     // a little lift: smoke rises
        var em = puffs.emission; em.enabled = false;
        var sh = puffs.shape; sh.enabled = false;
        var g = new Gradient();
        g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) },
                  new[] { new GradientAlphaKey(0f, 0f), new GradientAlphaKey(0.9f, 0.12f), new GradientAlphaKey(0.45f, 0.5f), new GradientAlphaKey(0f, 1f) });
        var col = puffs.colorOverLifetime; col.enabled = true; col.color = g;
        var sz = puffs.sizeOverLifetime; sz.enabled = true; sz.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.EaseInOut(0f, 0.6f, 1f, 2.2f));
        var n = puffs.noise; n.enabled = true; n.strength = 0.3f; n.frequency = 0.4f; n.scrollSpeed = 0.2f;
        var lv = puffs.limitVelocityOverLifetime; lv.enabled = true; lv.limit = 0.4f; lv.dampen = 0.08f;
        var r = go.GetComponent<ParticleSystemRenderer>();
        r.sharedMaterial = mat;
        r.renderMode = ParticleSystemRenderMode.Billboard;
        r.sortMode = ParticleSystemSortMode.Distance;
        r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        r.receiveShadows = false;
        puffs.Play();
    }

    void Update()
    {
        for (int i = later.Count - 1; i >= 0; i--)
            if (Time.time >= later[i].at) { var l = later[i]; later.RemoveAt(i); Dust(l.pos, 3, l.size / 3f, l.col); }
        // the cart being tipped out: dust off the pouring load
        var cart = MineCart.Instance;
        if (cart != null && cart.Tipping && Random.value < Time.deltaTime * 10f)
        {
            Vector3 lip = cart.transform.TransformPoint(new Vector3(-1.2f, 0.2f, Random.Range(-0.6f, 0.6f)));
            Dust(lip, 1, 0.5f, DustColour(VoxelWorld.LooseSoil));
        }
    }

    static Texture2D PuffTexture()
    {
        const int N = 32;
        var t = new Texture2D(N, N, TextureFormat.RGBA32, true);
        var px = new Color32[N * N];
        for (int y = 0; y < N; y++)
            for (int x = 0; x < N; x++)
            {
                float dx = (x + 0.5f) / N * 2f - 1f, dy = (y + 0.5f) / N * 2f - 1f;
                float a = Mathf.Clamp01(1f - Mathf.Sqrt(dx * dx + dy * dy));
                px[y * N + x] = new Color32(255, 255, 255, (byte)(a * a * 255f));
            }
        t.SetPixels32(px); t.Apply(true);
        t.wrapMode = TextureWrapMode.Clamp;
        return t;
    }
}
