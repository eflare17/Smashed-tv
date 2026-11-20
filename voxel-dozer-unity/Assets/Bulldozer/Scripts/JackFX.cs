// The jackhammer's dust and chips.  Every blow puffs a little dust off the face (more with a bigger bite) and
// sprays a few chips back off it: grey for rock, brown for dirt, white for quartz, and a few gold glints when
// there is gold in what it breaks.  The dust drifts and thins out in a second or two, so the tunnel never fills.
// Made by the worker the first time he uses the jackhammer.
using UnityEngine;

public class JackFX : MonoBehaviour
{
    static JackFX instance;
    ParticleSystem dust, chips, glints;

    public static void Blow(Vector3 at, Vector3 back, byte mat, float biteFrac, bool gold)
    {
        if (instance == null) instance = new GameObject("Jackhammer FX").AddComponent<JackFX>();
        instance.Puff(at, back, mat, biteFrac, gold);
    }

    void Awake()
    {
        var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        Mesh cubeMesh = cube.GetComponent<MeshFilter>().sharedMesh;
        Destroy(cube);
        var dustMat = new Material(Shader.Find("Voxel/FireSmoke"));
        dustMat.SetTexture("_MainTex", PuffTexture());
        var chipMat = new Material(Shader.Find("Voxel/FireSmoke"));          // no puff texture: solid little cubes
        var glintMat = new Material(Shader.Find("Voxel/FireParticle"));
        glintMat.SetFloat("_Boost", 3f);

        dust = MakeSystem("Jack dust", 700, dustMat, null, 0f,
            Grad(new[] { Color.white, Color.white }, new[] { 0f, 0.7f, 0.38f, 0f }),
            AnimationCurve.EaseInOut(0f, 0.6f, 1f, 1f));
        var dr = dust.GetComponent<ParticleSystemRenderer>(); dr.sortMode = ParticleSystemSortMode.Distance;
        var dn = dust.noise; dn.enabled = true; dn.strength = 0.25f; dn.frequency = 0.5f; dn.scrollSpeed = 0.2f;
        var dl = dust.limitVelocityOverLifetime; dl.enabled = true; dl.limit = 0.15f; dl.dampen = 0.12f;   // puffs out, then hangs

        chips = MakeSystem("Jack chips", 500, chipMat, cubeMesh, 1.6f,
            Grad(new[] { Color.white, Color.white }, new[] { 1f, 1f, 1f, 0f }),
            AnimationCurve.Linear(0f, 1f, 1f, 0.8f));
        glints = MakeSystem("Jack glints", 200, glintMat, cubeMesh, 1.2f,
            Grad(new[] { Color.white, new Color(1f, 0.8f, 0.4f) }, new[] { 1f, 1f, 0.8f, 0f }),
            AnimationCurve.Linear(0f, 1f, 1f, 0.4f));
    }

    void Puff(Vector3 at, Vector3 back, byte mat, float biteFrac, bool gold)
    {
        back = back.sqrMagnitude > 0.001f ? back.normalized : Vector3.up;
        Color dc, cc;
        bool quartz = mat == VoxelWorld.Quartz || mat == VoxelWorld.Gold;
        if (quartz) { dc = new Color(0.72f, 0.71f, 0.68f); cc = new Color(0.78f, 0.78f, 0.75f); }
        else if (mat == VoxelWorld.Rock) { dc = new Color(0.52f, 0.5f, 0.47f); cc = new Color(0.36f, 0.36f, 0.38f); }
        else { dc = new Color(0.55f, 0.44f, 0.32f); cc = new Color(0.42f, 0.32f, 0.22f); }   // dirt and clay

        Vector3 from = at + back * 0.06f;
        int puffs = Random.value < 0.65f + 0.35f * biteFrac ? (biteFrac > 0.6f ? 2 : 1) : 0;
        for (int i = 0; i < puffs; i++)
        {
            var e = new ParticleSystem.EmitParams
            {
                position = at + back * Random.Range(0.25f, 0.9f) + Random.insideUnitSphere * 0.08f,   // out along the hole to the face, not stuck down the hole it is boring
                velocity = (back * Random.Range(0.5f, 1.0f) + Random.insideUnitSphere * 0.35f + Vector3.up * 0.2f),
                startSize = Random.Range(0.3f, 0.5f) * (0.8f + 0.6f * biteFrac),
                startLifetime = Random.Range(1.1f, 1.9f),
                startColor = dc * Random.Range(0.9f, 1.1f),
                rotation = Random.Range(0f, 360f)
            };
            dust.Emit(e, 1);
        }
        int n = Random.Range(1, 3) + (biteFrac > 0.5f ? 1 : 0);
        for (int i = 0; i < n; i++)
        {
            var e = new ParticleSystem.EmitParams
            {
                position = from,
                velocity = back * Random.Range(1.2f, 2.6f) + Random.insideUnitSphere * 1.1f + Vector3.up * 0.8f,
                startSize = Random.Range(0.018f, 0.04f),
                startLifetime = Random.Range(0.4f, 0.7f),
                startColor = cc * Random.Range(0.8f, 1.15f),
                rotation3D = new Vector3(Random.Range(0f, 360f), Random.Range(0f, 360f), Random.Range(0f, 360f))
            };
            chips.Emit(e, 1);
        }
        if (gold)
            for (int i = 0, g = Random.Range(1, 4); i < g; i++)
            {
                var e = new ParticleSystem.EmitParams
                {
                    position = from,
                    velocity = back * Random.Range(1f, 2.2f) + Random.insideUnitSphere * 1.2f + Vector3.up * 0.6f,
                    startSize = Random.Range(0.012f, 0.022f),
                    startLifetime = Random.Range(0.3f, 0.5f),
                    startColor = new Color(1f, 0.78f, 0.25f),
                    rotation3D = new Vector3(Random.Range(0f, 360f), Random.Range(0f, 360f), Random.Range(0f, 360f))
                };
                glints.Emit(e, 1);
            }
    }

    /// How many dust puffs, chips and glints are in the air now (for the tests).
    public static int Alive(out int dustN, out int chipN, out int glintN)
    {
        dustN = chipN = glintN = 0;
        if (instance == null) return 0;
        dustN = instance.dust.particleCount; chipN = instance.chips.particleCount; glintN = instance.glints.particleCount;
        return dustN + chipN + glintN;
    }

    /// Where the first dust puff is, its size and colour (for the tests).
    public static string DustInfo()
    {
        if (instance == null || instance.dust.particleCount == 0) return "none";
        var ps = new ParticleSystem.Particle[1];
        instance.dust.GetParticles(ps, 1);
        return "at=" + ps[0].position + " size=" + ps[0].GetCurrentSize(instance.dust).ToString("F2") + " col=" + ps[0].GetCurrentColor(instance.dust);
    }

    ParticleSystem MakeSystem(string name, int max, Material mat, Mesh mesh, float gravity, Gradient colour, AnimationCurve size)
    {
        var go = new GameObject(name);
        go.transform.SetParent(transform, false);
        var ps = go.AddComponent<ParticleSystem>();
        ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        var main = ps.main;
        main.loop = false; main.playOnAwake = false; main.maxParticles = max;
        main.simulationSpace = ParticleSystemSimulationSpace.World;
        main.startRotation3D = mesh != null;
        main.gravityModifier = gravity;
        var em = ps.emission; em.enabled = false;
        var sh = ps.shape; sh.enabled = false;
        var col = ps.colorOverLifetime; col.enabled = true; col.color = colour;
        var sz = ps.sizeOverLifetime; sz.enabled = true; sz.size = new ParticleSystem.MinMaxCurve(1f, size);
        if (mesh != null) { var rot = ps.rotationOverLifetime; rot.enabled = true; rot.separateAxes = true; rot.x = rot.y = rot.z = new ParticleSystem.MinMaxCurve(-6f, 6f); }
        var r = go.GetComponent<ParticleSystemRenderer>();
        r.sharedMaterial = mat;
        r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        r.receiveShadows = false;
        if (mesh != null) { r.renderMode = ParticleSystemRenderMode.Mesh; r.mesh = mesh; }
        else r.renderMode = ParticleSystemRenderMode.Billboard;
        ps.Play();
        return ps;
    }

    // colour keys are evenly spread; alpha keys too
    static Gradient Grad(Color[] c, float[] a)
    {
        var g = new Gradient();
        var ck = new GradientColorKey[c.Length];
        for (int i = 0; i < c.Length; i++) ck[i] = new GradientColorKey(c[i], c.Length == 1 ? 0f : (float)i / (c.Length - 1));
        var ak = new GradientAlphaKey[a.Length];
        for (int i = 0; i < a.Length; i++) ak[i] = new GradientAlphaKey(a[i], a.Length == 1 ? 0f : (float)i / (a.Length - 1));
        g.SetKeys(ck, ak);
        return g;
    }

    /// A soft round puff, see-through at the edges.
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
