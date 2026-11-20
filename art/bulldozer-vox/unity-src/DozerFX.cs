// The dozer's exhaust smoke and the dust where its blade cuts (see HeavyFX).  Added by DozerController.
using UnityEngine;

/// The dozer's exhaust smoke and blade dust (added by DozerController).
[RequireComponent(typeof(DozerController))]
public class DozerFX : MonoBehaviour
{
    DozerController d;
    Transform exhaust;
    Vector3 stackTop;                                  // the top of the exhaust stack, in the exhaust's own space
    float lastRpm, smokeAcc, dustAcc;

    void Start()
    {
        d = GetComponent<DozerController>();
        exhaust = Find(transform, "Exhaust");
        if (exhaust != null)
        {
            var rs = exhaust.GetComponentsInChildren<Renderer>();
            if (rs.Length > 0)
            {
                Bounds b = rs[0].bounds;
                foreach (var r in rs) b.Encapsulate(r.bounds);
                stackTop = exhaust.InverseTransformPoint(new Vector3(b.center.x, b.max.y + 0.05f, b.center.z));
            }
        }
    }

    void Update()
    {
        float dt = Time.deltaTime;
        if (dt <= 0f || d == null) return;
        bool on = d.driven && d.CanDrive && !Prologue.Playing;
        // ---- exhaust
        if (on && exhaust != null)
        {
            Vector3 top = exhaust.TransformPoint(stackTop);
            float rise = (d.Rpm - lastRpm) / dt;
            float rate = 1.5f;                                         // idle: a faint wisp now and then
            if (rise > 0.3f) rate += 25f * Mathf.Clamp01(rise);        // throttle up: a burst of grey
            rate += 16f * d.Labour;                                    // labouring: thick and black
            smokeAcc += rate * dt;
            while (smokeAcc >= 1f)
            {
                smokeAcc -= 1f;
                float black = Mathf.Clamp01(d.Labour * 1.3f);
                Color c = Color.Lerp(new Color(0.6f, 0.6f, 0.62f, 0.55f), new Color(0.05f, 0.05f, 0.05f, 0.95f), black);
                HeavyFX.Puff(top + Random.insideUnitSphere * 0.05f, Vector3.up * Random.Range(0.9f, 1.5f) + Random.insideUnitSphere * 0.25f - transform.forward * d.Speed * 0.4f,
                             Mathf.Lerp(0.4f, 0.85f, black) * Random.Range(0.8f, 1.2f), Mathf.Lerp(1.6f, 3.0f, black), c);
            }
        }
        lastRpm = d.Rpm;
        // ---- dust where the blade cuts
        if (on && d.LastCut > 0 && d.Speed > 0.15f && d.Blade != null)
        {
            var w = VoxelWorld.Instance;
            Vector3 edge = d.Blade.TransformPoint(new Vector3(Random.Range(-2f, 2f), -0.6f, 1.2f));
            byte m = w != null ? w.MaterialAt(edge + Vector3.down * 0.05f) : VoxelWorld.Soil;
            float dry = HeavyFX.Dustiness(m == VoxelWorld.Air ? VoxelWorld.Soil : m);
            dustAcc += dt * dry * Mathf.Clamp(d.LastCut * 0.05f, 0f, 14f);
            while (dustAcc >= 1f)
            {
                dustAcc -= 1f;
                Vector3 at = d.Blade.TransformPoint(new Vector3(Random.Range(-2.2f, 2.2f), Random.Range(0.2f, 1.2f), 1.6f));
                HeavyFX.Puff(at, Vector3.up * Random.Range(0.3f, 0.8f) + transform.forward * d.Speed * 0.6f + Random.insideUnitSphere * 0.3f,
                             Random.Range(0.5f, 0.9f), Random.Range(1.4f, 2.4f), HeavyFX.DustColour(m == VoxelWorld.Air ? VoxelWorld.Soil : m));
            }
        }
    }

    static Transform Find(Transform t, string name)
    {
        if (t.name == name) return t;
        for (int i = 0; i < t.childCount; i++) { var f = Find(t.GetChild(i), name); if (f != null) return f; }
        return null;
    }
}
