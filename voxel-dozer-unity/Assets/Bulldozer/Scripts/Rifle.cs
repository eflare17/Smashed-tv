// The rifle (4 on foot, or the bumpers): just for fun, free from the start, not in the upgrades or the money.
// Taken from the Voxel Arena's rifle: 8 shots a second while you hold the button, an instant hit 70 m out with a
// thin tracer line, and a hit on the ground chips out a 15 cm bit (VoxelWorld.Pick, so the bit is loose rubble and
// the ground keeps its books) with a puff of dust.
//
// Enemies to come: anything with a collider and a component that is IShootable gets Shot() when a bullet reaches it
// before the ground does.
// A shot through strong green gas sets it off (Fluids.cs), and a shot at ice breaks it (the ice stops the shot like
// ground does, and VoxelWorld.Pick tells Fluids.cs).
using System.Collections.Generic;
using UnityEngine;

public interface IShootable
{
    void Shot(Vector3 at, Vector3 dir);
}

public class Rifle : MonoBehaviour
{
    public const float Gap = 1f / 8f, Range = 70f, ChipRadius = 0.15f;

    public static int Shots { get; private set; }          // (tests)
    public static int Chips { get; private set; }          // shots that broke some ground (tests)
    public static int TargetHits { get; private set; }     // shots that hit something IShootable (tests)

    static Rifle instance;
    struct Tracer { public Transform t; public float life; }
    readonly List<Tracer> tracers = new List<Tracer>();
    Material tracerMat, flashMat;
    Transform flash;
    float flashLife;

    static Rifle Get()
    {
        if (instance == null) instance = new GameObject("Rifle shots").AddComponent<Rifle>();
        return instance;
    }

    /// One shot along `dir` from `from` (the aim line from the camera); the tracer starts at `muzzle`.
    /// Returns true if it hit something (the ground or a target).
    public static bool Fire(Vector3 from, Vector3 dir, Vector3 muzzle)
    {
        var w = VoxelWorld.Instance;
        Shots++;
        GameAudio.PlayAt("rifle", muzzle, 0.75f, 0.94f + 0.12f * Random.value);
        FollowCamera.Shake = Mathf.Max(FollowCamera.Shake, 0.004f);
        Vector3 hit = Vector3.zero; byte mat = VoxelWorld.Air;
        bool ground = w != null && w.Raycast(from, dir, Range, out hit, out mat);
        if (!ground) { hit = from + dir * Range; mat = VoxelWorld.Air; }
        float groundDist = ground ? Vector3.Distance(from, hit) : Range;

        // a target in front of the ground takes the shot
        IShootable target = null; Vector3 targetAt = Vector3.zero; float best = groundDist;
        foreach (var h in Physics.RaycastAll(from, dir, groundDist))
        {
            if (h.distance >= best) continue;
            var s = h.collider.GetComponentInParent<IShootable>();
            if (s == null) continue;
            target = s; targetAt = h.point; best = h.distance;
        }
        var r = Get();
        r.Flash(muzzle, dir);
        if (Fluids.Instance != null) Fluids.Instance.ShotThrough(from, dir, best);   // green gas on the way goes off (Fluids.cs)
        if (target != null)
        {
            r.AddTracer(muzzle, targetAt);
            target.Shot(targetAt, dir);
            TargetHits++;
            return true;
        }
        r.AddTracer(muzzle, hit);
        if (!ground) return false;
        Vector3 kick = -dir * 1.5f + Vector3.up * 1.2f;
        if (w.Pick(hit + dir * 0.05f, ChipRadius, kick) > 0) Chips++;
        HeavyFX.Dust(hit - dir * 0.05f, 2, 0.12f, HeavyFX.DustColour(mat));
        bool rock = mat >= VoxelWorld.Rock && mat <= VoxelWorld.Gold;
        GameAudio.PlayAt(mat == VoxelWorld.Gold ? "pick_gold" : rock ? "pick_rock" : "pick_dirt", hit, 0.35f, 1.3f + 0.2f * Random.value);
        if (mat == VoxelWorld.Gold || mat == VoxelWorld.LooseGold) Goals.GoldSeen();
        return true;
    }

    Transform Bar(string name, Material m)
    {
        var g = GameObject.CreatePrimitive(PrimitiveType.Cube);
        g.name = name;
        Destroy(g.GetComponent<Collider>());
        g.GetComponent<MeshRenderer>().sharedMaterial = m;
        g.GetComponent<MeshRenderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        g.transform.SetParent(transform, false);
        return g.transform;
    }

    void AddTracer(Vector3 a, Vector3 b)
    {
        if (tracerMat == null) tracerMat = new Material(Shader.Find("Unlit/Color")) { color = new Color(1f, 0.92f, 0.55f) };
        Vector3 d = b - a;
        if (d.sqrMagnitude < 0.01f) return;
        Tracer tr = default(Tracer);
        int free = tracers.FindIndex(x => x.life <= 0f);
        if (free < 0) { tr.t = Bar("Tracer", tracerMat); tracers.Add(tr); free = tracers.Count - 1; }
        tr = tracers[free];
        tr.t.gameObject.SetActive(true);
        tr.t.position = a + d * 0.5f;
        tr.t.rotation = Quaternion.LookRotation(d);
        tr.t.localScale = new Vector3(0.012f, 0.012f, d.magnitude);
        tr.life = 0.05f;
        tracers[free] = tr;
    }

    void Flash(Vector3 at, Vector3 dir)
    {
        if (flashMat == null) flashMat = new Material(Shader.Find("Unlit/Color")) { color = new Color(1f, 0.8f, 0.35f) };
        if (flash == null) flash = Bar("Muzzle flash", flashMat);
        flash.gameObject.SetActive(true);
        flash.position = at + dir * 0.05f;
        flash.rotation = Quaternion.LookRotation(dir) * Quaternion.Euler(0f, 0f, Random.Range(0f, 90f));
        flash.localScale = new Vector3(0.07f, 0.07f, 0.1f) * Random.Range(0.8f, 1.2f);
        flashLife = 0.035f;
    }

    void Update()
    {
        float dt = Time.deltaTime;
        for (int i = 0; i < tracers.Count; i++)
        {
            var tr = tracers[i];
            if (tr.life <= 0f) continue;
            tr.life -= dt;
            if (tr.life <= 0f) tr.t.gameObject.SetActive(false);
            tracers[i] = tr;
        }
        if (flash != null && flashLife > 0f) { flashLife -= dt; if (flashLife <= 0f) flash.gameObject.SetActive(false); }
    }
}
