// What the bushfire looks like in the air: flames, smoke, flying embers, and the sky going red.
// FireSim decides what is burning; this draws it.  Three particle systems, fed by hand each frame from the trees
// and ground squares alight right now, so the fire's look follows the spread exactly:
//   flames  glowing cubes bursting up from burning crowns and along the ground front, gone in about a second
//   smoke   big soft dark puffs rising and drifting with the wind, lingering for 15-20 s
//   embers  tiny glowing specks blown downwind and swirling
// While the fire is big the sun goes red and dim, the haze thickens and browns, and the sky takes an orange tint;
// it all goes back as the fire dies (or stops).
using UnityEngine;

public class FireFX : MonoBehaviour
{
    ParticleSystem flames, smoke, embers;
    FireSim fire;
    System.Random rng = new System.Random(7);
    float Rand(float a, float b) { return a + (float)rng.NextDouble() * (b - a); }

    // what the scene looked like before the fire, to go back to
    Light sun; Color sunColour; float sunIntensity;
    Color fogColour, ambSky, ambEq, ambGround; float fogDensity;
    Material skyOriginal, sky;
    float intensity;                                               // 0..1: how big the fire is, smoothed
    float flameAcc, smokeAcc, emberAcc, groundAcc;

    void Start()
    {
        fire = GetComponent<FireSim>();
        var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        Mesh cubeMesh = cube.GetComponent<MeshFilter>().sharedMesh;
        Destroy(cube);
        var glowMat = new Material(Shader.Find("Voxel/FireParticle"));
        glowMat.SetFloat("_Boost", 2.6f);
        var emberMat = new Material(glowMat); emberMat.SetFloat("_Boost", 5f);
        var smokeMat = new Material(Shader.Find("Voxel/FireSmoke"));
        smokeMat.SetTexture("_MainTex", PuffTexture());

        flames = MakeSystem("Flames", 9000, glowMat, cubeMesh,
            Grad(new[] { new Color(1f, 0.62f, 0.18f), new Color(1f, 0.38f, 0.06f), new Color(0.8f, 0.14f, 0.03f), new Color(0.2f, 0.05f, 0.02f) }, new[] { 1f, 1f, 0.8f, 0f }),
            AnimationCurve.EaseInOut(0f, 1f, 1f, 0.15f));
        embers = MakeSystem("Embers", 6000, emberMat, cubeMesh,
            Grad(new[] { new Color(1f, 0.75f, 0.3f), new Color(1f, 0.45f, 0.1f), new Color(0.7f, 0.15f, 0.03f), new Color(0.3f, 0.05f, 0.01f) }, new[] { 1f, 1f, 0.8f, 0f }),
            AnimationCurve.Linear(0f, 1f, 1f, 0.6f));
        var en = embers.noise; en.enabled = true; en.strength = 1.6f; en.frequency = 0.35f; en.scrollSpeed = 0.4f;
        smoke = MakeSystem("Smoke", 4000, smokeMat, null,
            Grad(new[] { new Color(0.32f, 0.27f, 0.22f), new Color(0.24f, 0.21f, 0.19f), new Color(0.28f, 0.26f, 0.25f), new Color(0.3f, 0.29f, 0.28f) }, new[] { 0f, 0.5f, 0.42f, 0f }),
            AnimationCurve.EaseInOut(0f, 0.35f, 1f, 1f));
        var sn = smoke.noise; sn.enabled = true; sn.strength = 0.8f; sn.frequency = 0.08f; sn.scrollSpeed = 0.1f;
        var sr = smoke.GetComponent<ParticleSystemRenderer>(); sr.sortMode = ParticleSystemSortMode.Distance;

        var lights = FindObjectsByType<Light>(FindObjectsSortMode.None);
        foreach (var l in lights) if (l.type == LightType.Directional) { sun = l; break; }
        if (sun != null) { sunColour = sun.color; sunIntensity = sun.intensity; }
        fogColour = RenderSettings.fogColor; fogDensity = RenderSettings.fogDensity;
        ambSky = RenderSettings.ambientSkyColor; ambEq = RenderSettings.ambientEquatorColor; ambGround = RenderSettings.ambientGroundColor;
        skyOriginal = RenderSettings.skybox;
        if (skyOriginal != null) { sky = new Material(skyOriginal); RenderSettings.skybox = sky; }   // a copy: never change the saved sky
    }

    void OnDestroy() { Restore(); }

    /// Straight back to the normal sky and light, and no smoke or flames left in the air.
    public void RestoreNow()
    {
        intensity = 0f;
        Restore();
        if (sky != null && skyOriginal != null) RenderSettings.skybox = skyOriginal;
        foreach (var ps in new[] { flames, smoke, embers }) if (ps != null) ps.Clear();
    }

    void Restore()
    {
        if (sun != null) { sun.color = sunColour; sun.intensity = sunIntensity; }
        RenderSettings.fogColor = fogColour; RenderSettings.fogDensity = fogDensity;
        RenderSettings.ambientSkyColor = ambSky; RenderSettings.ambientEquatorColor = ambEq; RenderSettings.ambientGroundColor = ambGround;
        if (skyOriginal != null) RenderSettings.skybox = skyOriginal;
    }

    ParticleSystem MakeSystem(string name, int max, Material mat, Mesh mesh, Gradient colour, AnimationCurve size)
    {
        var go = new GameObject(name);
        go.transform.SetParent(transform, false);
        var ps = go.AddComponent<ParticleSystem>();
        ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        var main = ps.main;
        main.loop = false; main.playOnAwake = false; main.maxParticles = max;
        main.simulationSpace = ParticleSystemSimulationSpace.World;
        main.startRotation3D = mesh != null;
        main.gravityModifier = 0f;
        var em = ps.emission; em.enabled = false;
        var sh = ps.shape; sh.enabled = false;
        var col = ps.colorOverLifetime; col.enabled = true; col.color = colour;
        var sz = ps.sizeOverLifetime; sz.enabled = true; sz.size = new ParticleSystem.MinMaxCurve(1f, size);
        var r = go.GetComponent<ParticleSystemRenderer>();
        r.sharedMaterial = mat;
        r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        r.receiveShadows = false;
        if (mesh != null) { r.renderMode = ParticleSystemRenderMode.Mesh; r.mesh = mesh; }
        else r.renderMode = ParticleSystemRenderMode.Billboard;
        ps.Play();
        return ps;
    }

    static Gradient Grad(Color[] c, float[] a)
    {
        var g = new Gradient();
        var ck = new GradientColorKey[c.Length]; var ak = new GradientAlphaKey[a.Length];
        for (int i = 0; i < c.Length; i++) ck[i] = new GradientColorKey(c[i], i / (float)(c.Length - 1));
        for (int i = 0; i < a.Length; i++) ak[i] = new GradientAlphaKey(a[i], i / (float)(a.Length - 1));
        g.SetKeys(ck, ak);
        return g;
    }

    static Texture2D PuffTexture()
    {
        const int N = 64;
        var t = new Texture2D(N, N, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
        var px = new Color32[N * N];
        for (int y = 0; y < N; y++)
            for (int x = 0; x < N; x++)
            {
                float dx = (x + 0.5f) / N * 2f - 1f, dy = (y + 0.5f) / N * 2f - 1f;
                float r = Mathf.Sqrt(dx * dx + dy * dy);
                float n = Mathf.PerlinNoise(x * 0.11f, y * 0.11f) * 0.6f + Mathf.PerlinNoise(x * 0.27f + 9f, y * 0.27f) * 0.4f;
                float a = Mathf.Clamp01(1f - r) * (0.55f + 0.7f * n);
                a = Mathf.Clamp01(a * 1.3f - 0.1f);
                px[x + N * y] = new Color32(255, 255, 255, (byte)(a * 255));
            }
        t.SetPixels32(px); t.Apply();
        return t;
    }

    void Emit(ParticleSystem ps, Vector3 at, Vector3 vel, float size, float life, bool spin)
    {
        var e = new ParticleSystem.EmitParams { position = at, velocity = vel, startSize = size, startLifetime = life, startColor = Color.white };
        if (spin) e.rotation3D = new Vector3(Rand(0f, 360f), Rand(0f, 360f), Rand(0f, 360f));
        else e.rotation = Rand(0f, 360f);
        ps.Emit(e, 1);
    }

    void Update()
    {
        if (fire == null) return;
        float dt = Time.deltaTime * fire.speedUp;
        float now = fire.Now;
        Vector2 w2 = fire.Running ? fire.WindAt(now) : Vector2.zero;
        Vector3 wind = new Vector3(w2.x, 0f, w2.y);

        // what's alight: trees in their first 14 s, ground squares in their first 8 s
        var trees = fire.ActiveTrees;
        int nTrees = 0;
        for (int k = trees.Count - 1; k >= 0; k--) { if (now - fire.TreeIgnite(trees[k]) > 16f) trees.RemoveAt(k); else nTrees++; }
        var cells = fire.BurningCells;
        float want = fire.Running ? Mathf.Clamp01(nTrees / 120f) : 0f;
        intensity = Mathf.MoveTowards(intensity, want, Time.deltaTime * 0.12f);
        Look(intensity);
        if (!fire.Running || dt <= 0f) return;

        // flames and embers from the trees: each tree flares up, then dies down (fewer per tree when many are alight)
        float perTree = Mathf.Min(16f, 5000f / Mathf.Max(1, nTrees));
        float smokePerTree = Mathf.Min(1.4f, 260f / Mathf.Max(1, nTrees));
        float emberPerTree = Mathf.Min(7f, 900f / Mathf.Max(1, nTrees));
        foreach (int t in trees)
        {
            float a = now - fire.TreeIgnite(t);
            if (a < 0f) continue;
            float s = Mathf.SmoothStep(0f, 1f, a) * (1f - Mathf.SmoothStep(0f, 1f, (a - 7f) / 6f));
            var tr = FireSim.Trees[t];
            float h = tr.height;
            flameAcc += perTree * s * dt;
            while (flameAcc >= 1f)
            {
                flameAcc -= 1f;
                bool crown = rng.NextDouble() < 0.75;
                Vector3 p = tr.at + new Vector3(Rand(-1f, 1f) * h * 0.14f, crown ? h * Rand(0.6f, 0.95f) : Rand(0f, 2.5f), Rand(-1f, 1f) * h * 0.14f);
                Emit(flames, p, Vector3.up * Rand(3f, 6.5f) + wind * 0.35f + new Vector3(Rand(-0.6f, 0.6f), 0f, Rand(-0.6f, 0.6f)), Rand(0.4f, 1.1f) * (crown ? 1f : 0.7f), Rand(0.5f, 1.1f), true);
            }
            smokeAcc += smokePerTree * Mathf.Max(s, a < 14f ? 0.35f : 0f) * dt;
            while (smokeAcc >= 1f)
            {
                smokeAcc -= 1f;
                Vector3 p = tr.at + new Vector3(Rand(-2f, 2f), h * Rand(0.7f, 1.05f), Rand(-2f, 2f));
                Emit(smoke, p, Vector3.up * Rand(2f, 3.5f) + wind * 0.75f, Rand(6f, 13f), Rand(14f, 21f), false);
            }
            emberAcc += emberPerTree * s * dt;
            while (emberAcc >= 1f)
            {
                emberAcc -= 1f;
                Vector3 p = tr.at + new Vector3(Rand(-2f, 2f), h * Rand(0.5f, 0.95f), Rand(-2f, 2f));
                Emit(embers, p, Vector3.up * Rand(2f, 5f) + wind * Rand(0.8f, 1.3f), Rand(0.07f, 0.16f), Rand(2f, 5f), true);
            }
        }
        // trees hitting the ground: a burst of sparks, flames and smoke along the trunk
        foreach (int t in fire.Landed)
        {
            var tr = FireSim.Trees[t];
            Vector3 dir = new Vector3(Mathf.Sin(fire.FallAngle(t)), 0f, Mathf.Cos(fire.FallAngle(t)));
            for (int k = 0; k < 60; k++)
            {
                Vector3 p = tr.at + dir * tr.height * Rand(0.1f, 0.9f) + Vector3.up * 0.6f;
                Emit(embers, p, new Vector3(Rand(-3f, 3f), Rand(3f, 9f), Rand(-3f, 3f)) + wind * 0.5f, Rand(0.08f, 0.2f), Rand(1.5f, 4f), true);
                if (k % 3 == 0) Emit(flames, p, Vector3.up * Rand(2f, 5f), Rand(0.5f, 1.2f), Rand(0.5f, 1f), true);
                if (k % 10 == 0) Emit(smoke, p, Vector3.up * Rand(1.5f, 3f) + wind * 0.5f, Rand(5f, 9f), Rand(8f, 14f), false);
            }
        }
        fire.Landed.Clear();

        // low flames along the ground front
        float perCell = Mathf.Min(5f, 2500f / Mathf.Max(1, cells.Count));
        foreach (int c in cells)
        {
            float a = now - fire.CellIgnite(c);
            if (a < 0f || a > 8f) continue;
            float s = 1f - a / 8f;
            groundAcc += perCell * s * dt;
            while (groundAcc >= 1f)
            {
                groundAcc -= 1f;
                Vector3 p = fire.CellCentre(c) + new Vector3(Rand(-1f, 1f), 0f, Rand(-1f, 1f));
                p.y = SiteProps.HillY(p.x, p.z) + 0.1f;
                Emit(flames, p, Vector3.up * Rand(1.5f, 3.5f) + wind * 0.25f, Rand(0.3f, 0.8f), Rand(0.4f, 0.9f), true);
            }
        }
    }

    /// The sky and light for a fire this big (0 = none).
    void Look(float k)
    {
        if (sun != null)
        {
            sun.color = Color.Lerp(sunColour, new Color(1f, 0.42f, 0.18f), k);
            sun.intensity = Mathf.Lerp(sunIntensity, sunIntensity * 0.42f, k);
        }
        RenderSettings.fogColor = Color.Lerp(fogColour, new Color(0.40f, 0.24f, 0.13f), k);
        RenderSettings.fogDensity = Mathf.Lerp(fogDensity, 0.015f, k);
        RenderSettings.ambientSkyColor = Color.Lerp(ambSky, new Color(0.55f, 0.30f, 0.16f), k);
        RenderSettings.ambientEquatorColor = Color.Lerp(ambEq, new Color(0.50f, 0.28f, 0.14f), k);
        RenderSettings.ambientGroundColor = Color.Lerp(ambGround, new Color(0.30f, 0.16f, 0.08f), k);
        if (sky != null && skyOriginal != null)
        {
            // (an orange tint turns this sky green: it goes a smoky grey instead, and the brown haze and smoke colour it)
            if (skyOriginal.HasProperty("_SkyTint")) sky.SetColor("_SkyTint", Color.Lerp(skyOriginal.GetColor("_SkyTint"), new Color(0.22f, 0.21f, 0.2f), k));
            if (skyOriginal.HasProperty("_AtmosphereThickness")) sky.SetFloat("_AtmosphereThickness", Mathf.Lerp(skyOriginal.GetFloat("_AtmosphereThickness"), 2.6f, k));
            if (skyOriginal.HasProperty("_Exposure")) sky.SetFloat("_Exposure", Mathf.Lerp(skyOriginal.GetFloat("_Exposure"), skyOriginal.GetFloat("_Exposure") * 0.35f, k));
        }
    }
}
