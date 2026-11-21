// The two guns.
//   Rifle:   8 shots a second.  Instant hit with a tracer line.  One hit kills a grunt; a hit on the ground chips out
//            a 15 cm bit (VoxelWorld.Pick) with a puff of dust.
//   Rocket:  one every 0.8 s, flying at 25 m/s with a smoke trail.  On impact (ground, wall or a grunt) it blows a
//            1.2 m crater, throwing the dirt out as clods that fall back and settle (the ground keeps its books, so
//            no dirt is made or lost), kills every grunt within 2.5 m, with dust, a flash, a camera bump and a bang.
//            Rockets don't hurt you (as in Smashed).
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class Weapons : MonoBehaviour
{
    public static Weapons Instance { get; private set; }

    public const float RifleGap = 1f / 8f, RifleRange = 70f, ChipRadius = 0.15f;
    public const float RocketGap = 0.8f, RocketSpeed = 25f, CraterRadius = 1.2f, BlastRadius = 2.5f, BlastThrow = 7.5f;

    public int RifleShots { get; private set; }
    public int RocketsFired { get; private set; }
    public int Blasts { get; private set; }
    public Vector3 LastBlast { get; private set; }
    public int LastBlastVoxels { get; private set; }

    struct Rocket { public Vector3 pos, vel; public float age, puff; public bool live; }
    readonly List<Rocket> rockets = new List<Rocket>();
    Mesh rocketMesh;
    Material rocketMat;

    // tracers: a small pool of thin lines that flash and fade
    const int Tracers = 16;
    readonly LineRenderer[] tracer = new LineRenderer[Tracers];
    readonly float[] tracerT = new float[Tracers];
    int nextTracer;
    Light flash;
    float flashT;

    void Awake()
    {
        Instance = this;
        rocketMesh = VoxModel.FromBoxes(VoxModel.RocketBoxes(), new Vector3(1f, 1f, 2f), 0.1f);
        rocketMat = new Material(Shader.Find("Arena/VertexColour"));
        rocketMat.SetFloat("_Glow", 0.25f);
        var tm = new Material(Shader.Find("Sprites/Default"));
        for (int i = 0; i < Tracers; i++)
        {
            var go = new GameObject("Tracer " + i);
            go.transform.SetParent(transform, false);
            var lr = go.AddComponent<LineRenderer>();
            lr.sharedMaterial = tm;
            lr.positionCount = 2;
            lr.widthMultiplier = 0.035f;
            lr.shadowCastingMode = ShadowCastingMode.Off; lr.receiveShadows = false;
            lr.enabled = false;
            tracer[i] = lr;
        }
        var fl = new GameObject("Blast flash");
        fl.transform.SetParent(transform, false);
        flash = fl.AddComponent<Light>();
        flash.type = LightType.Point; flash.range = 12f; flash.color = new Color(1f, 0.7f, 0.35f); flash.intensity = 0f; flash.shadows = LightShadows.None;
    }
    void OnDestroy() { if (Instance == this) Instance = null; }

    public void Clear() { rockets.Clear(); }

    /// Where the walls stop a line (metres along it), or `max`.  The walls stand 3 m tall round the arena; the
    /// doorways are open.
    public static float WallDistance(Vector3 from, Vector3 dir, float max)
    {
        float best = max, h = ArenaGame.Half;
        for (int axis = 0; axis < 2; axis++)
        {
            float o = axis == 0 ? from.x : from.z, d = axis == 0 ? dir.x : dir.z;
            if (Mathf.Abs(d) < 1e-5f) continue;
            float t = ((d > 0f ? h : -h) - o) / d;
            if (t < 0f || t >= best) continue;
            Vector3 p = from + dir * t;
            float across = axis == 0 ? p.z : p.x;
            if (p.y < ArenaGame.WallHeight && Mathf.Abs(across) > ArenaGame.DoorHalf) best = t;
        }
        return best;
    }

    /// One rifle shot from `muzzle` towards `aim`.
    public void FireRifle(Vector3 muzzle, Vector3 aim)
    {
        var world = VoxelWorld.Instance;
        Vector3 dir = aim - muzzle;
        if (dir.sqrMagnitude < 1e-4f) return;
        dir.Normalize();
        RifleShots++;
        float max = WallDistance(muzzle, dir, RifleRange);
        Vector3 hit = muzzle + dir * max; byte mat = VoxelWorld.Air;
        bool ground = world != null && world.Raycast(muzzle, dir, max, out hit, out mat);
        if (!ground) { hit = muzzle + dir * max; mat = VoxelWorld.Air; }
        float along = 1f;
        var g = Grunts.Instance;
        int who = g != null ? g.HitLine(muzzle, hit, 0.05f, out along) : -1;
        if (who >= 0)
        {
            hit = muzzle + (hit - muzzle) * along;
            g.Kill(who, muzzle);
        }
        else if (ground)
        {
            // a chip out of the ground, kicked back towards the shooter and up
            world.Pick(hit - dir * 0.04f, ChipRadius, -dir * 1.6f + Vector3.up * 1.8f);
            HeavyFX.Dust(hit - dir * 0.1f, 2, 0.22f, HeavyFX.DustColour(mat));
        }
        else if (max < RifleRange) HeavyFX.Dust(hit - dir * 0.1f, 1, 0.18f, new Color(0.6f, 0.6f, 0.6f, 0.5f));   // the wall
        var lr = tracer[nextTracer];
        tracerT[nextTracer] = 0.06f;
        nextTracer = (nextTracer + 1) % Tracers;
        lr.SetPosition(0, muzzle); lr.SetPosition(1, hit);
        lr.enabled = true;
        GameAudio.PlayAt("rifle", muzzle, 0.55f, 0.93f + 0.14f * Random.value);
    }

    /// One rocket from `muzzle` towards `aim`.
    public void FireRocket(Vector3 muzzle, Vector3 aim)
    {
        Vector3 dir = aim - muzzle;
        if (dir.sqrMagnitude < 1e-4f) return;
        rockets.Add(new Rocket { pos = muzzle, vel = dir.normalized * RocketSpeed, live = true });
        RocketsFired++;
        GameAudio.PlayAt("rocket_launch", muzzle, 0.8f, 0.95f + 0.1f * Random.value);
    }

    void Update()
    {
        float dt = Time.deltaTime;
        for (int i = 0; i < Tracers; i++)
        {
            if (!tracer[i].enabled) continue;
            tracerT[i] -= dt;
            float a = Mathf.Clamp01(tracerT[i] / 0.06f);
            var c = new Color(1f, 0.92f, 0.55f, a);
            tracer[i].startColor = c; tracer[i].endColor = new Color(1f, 0.8f, 0.4f, a * 0.4f);
            if (tracerT[i] <= 0f) tracer[i].enabled = false;
        }
        if (flashT > 0f) { flashT -= dt; flash.intensity = Mathf.Max(0f, flashT / 0.18f) * 6f; }

        var world = VoxelWorld.Instance;
        var g = Grunts.Instance;
        for (int i = 0; i < rockets.Count; i++)
        {
            var r = rockets[i];
            r.age += dt;
            Vector3 step = r.vel * dt;
            int n = Mathf.Max(1, Mathf.CeilToInt(step.magnitude / 0.1f));
            bool boom = false;
            Vector3 p = r.pos, at = p;
            for (int k = 0; k < n && !boom; k++)
            {
                Vector3 q = p + step / n;
                float along;
                if (g != null && g.HitLine(p, q, 0.15f, out along) >= 0) { at = Vector3.Lerp(p, q, along); boom = true; }
                else if (world != null && world.MaterialAt(q) != VoxelWorld.Air) { at = p; boom = true; }
                else if (WallDistance(p, (q - p).normalized, (q - p).magnitude + 1e-4f) < (q - p).magnitude) { at = p; boom = true; }
                p = q;
            }
            if (!boom && r.age > 4f) { boom = true; at = p; }
            if (boom) { Explode(at); rockets.RemoveAt(i); i--; continue; }
            r.pos = p;
            // the smoke trail
            r.puff -= dt;
            while (r.puff <= 0f)
            {
                r.puff += 0.018f;
                HeavyFX.Puff(r.pos - r.vel.normalized * 0.25f + Random.insideUnitSphere * 0.04f, Random.insideUnitSphere * 0.15f, 0.22f, Random.Range(0.8f, 1.3f), new Color(0.82f, 0.8f, 0.78f, 0.5f));
            }
            rockets[i] = r;
        }
        var rp = new RenderParams(rocketMat) { worldBounds = new Bounds(Vector3.zero, Vector3.one * 80f), shadowCastingMode = ShadowCastingMode.On };
        foreach (var r in rockets) Graphics.RenderMesh(rp, rocketMesh, 0, Matrix4x4.TRS(r.pos, Quaternion.LookRotation(r.vel), Vector3.one * 1.4f));
    }

    /// A rocket going off at `at`.
    public void Explode(Vector3 at)
    {
        var world = VoxelWorld.Instance;
        Blasts++;
        LastBlast = at;
        LastBlastVoxels = world != null ? world.Pick(at, CraterRadius, Vector3.zero, true, BlastThrow) : 0;
        if (Grunts.Instance != null) Grunts.Instance.KillRadius(at, BlastRadius);
        // dust thrown up, a quick fireball, a flash
        byte m = world != null ? world.MaterialAt(at + Vector3.down * 0.3f) : VoxelWorld.Soil;
        Color dust = HeavyFX.DustColour(m == VoxelWorld.Air ? VoxelWorld.Soil : m);
        for (int i = 0; i < 26; i++)
        {
            Vector3 d = Random.insideUnitSphere; d.y = Mathf.Abs(d.y) + 0.3f;
            HeavyFX.Puff(at + d * 0.6f, d * Random.Range(1.5f, 4.5f), Random.Range(0.6f, 1.1f), Random.Range(1.6f, 3f), dust * Random.Range(0.85f, 1.1f));
        }
        for (int i = 0; i < 10; i++)
        {
            Vector3 d = Random.insideUnitSphere;
            HeavyFX.Puff(at + d * 0.4f + Vector3.up * 0.3f, d * 2.5f + Vector3.up, Random.Range(0.5f, 0.9f), Random.Range(0.25f, 0.45f), new Color(1f, Random.Range(0.45f, 0.7f), 0.15f, 0.9f));
        }
        flash.transform.position = at + Vector3.up * 0.8f;
        flashT = 0.18f; flash.intensity = 6f;
        float near = ArenaPlayer.Instance != null ? Vector3.Distance(ArenaPlayer.Instance.transform.position, at) : 10f;
        FollowCamera.Bump(Mathf.Lerp(0.32f, 0.06f, Mathf.Clamp01(near / 25f)));
        GameAudio.PlayAt("explosion", at, 1f, 0.92f + 0.12f * Random.value);
    }
}
