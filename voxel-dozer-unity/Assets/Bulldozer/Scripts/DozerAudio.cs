// The dozer's sounds, following what the machine is doing (GameAudio adds this to the dozer):
//   engine      idles while someone is in the seat, revs with the throttle; as it bogs down under load the
//               labouring layer (engine_lug) comes in, deeper and rougher
//   tracks      the clank rate follows the tracks' speed, slipping included
//   dirt        the heap rumbling in front of the blade, louder as the heap grows
//   hydraulic   the whine while the blade or ripper is moving
//   ripper      the grind while the ripper is in the ground and the machine is moving
//   clunk       once, when the blade hits hard rock
// The engine and tracks follow the Engine volume, the rest Effects.
using UnityEngine;

[RequireComponent(typeof(DozerController))]
public class DozerAudio : MonoBehaviour
{
    DozerController d;
    AudioSource engine, lug, tracks, dirt, hydraulic, ripper;
    float rpm, labour, run, lastBlade, lastRipper, lastYaw, lastTilt;
    bool wasBlocked;

    /// How hard the engine is working right now, 0..1 (for tests and the exhaust smoke).
    public float Labour { get { return labour; } }
    public float Rpm { get { return rpm; } }
    public float EngineVolume { get { return engine != null ? engine.volume : 0f; } }

    void Start()
    {
        d = GetComponent<DozerController>();
        engine = GameAudio.Loop(gameObject, "engine", 0.6f, 6f, 90f);
        lug = GameAudio.Loop(gameObject, "engine_lug", 0.6f, 6f, 90f);
        tracks = GameAudio.Loop(gameObject, "tracks", 0.6f, 5f, 70f);
        dirt = GameAudio.Loop(gameObject, "dirt", 0.6f, 5f, 60f);
        hydraulic = GameAudio.Loop(gameObject, "hydraulic", 0.6f, 4f, 40f);
        ripper = GameAudio.Loop(gameObject, "ripper", 0.6f, 5f, 60f);
        lastBlade = d.BladeHeight01; lastRipper = d.RipperHeight01;
    }

    void Update()
    {
        float dt = Time.deltaTime;
        if (dt <= 0f || d == null) return;
        bool on = d.driven && d.CanDrive && !Prologue.Playing;
        float eng = GameAudio.Engine, fx = GameAudio.Effects;
        float throttle = Mathf.Abs(d.Throttle);

        // the engine: revs follow the throttle; labour is how much the load is holding it back
        float wantRpm = on ? Mathf.Clamp01(throttle * 0.85f + Mathf.Abs(d.Speed) * 0.04f) : 0f;
        rpm = Mathf.MoveTowards(rpm, wantRpm, dt * (wantRpm > rpm ? 1.2f : 0.8f));
        float wantLabour = on && throttle > 0.2f ? Mathf.Clamp01((1f - d.Bog) * 1.5f + (d.Climbing ? 0.4f : 0f) + (d.BlockedByRock ? 0.7f : 0f)) : 0f;
        labour = Mathf.MoveTowards(labour, wantLabour, dt * 1.5f);
        GameAudio.Steer(engine, on ? (0.5f + 0.35f * rpm) * (1f - 0.35f * labour) * eng : 0f, 0.8f + 0.7f * rpm - 0.22f * labour, dt, on ? 6f : 2f);
        GameAudio.Steer(lug, on ? labour * 0.85f * eng : 0f, 0.85f + 0.35f * rpm - 0.15f * labour, dt, 5f);

        // the tracks
        run = Mathf.Lerp(run, d.TrackSpeed, 1f - Mathf.Exp(-8f * dt));
        GameAudio.Steer(tracks, Mathf.Clamp01(run / 1.2f) * 0.55f * eng, 0.35f + 0.3f * run, dt, 10f);

        // the heap in front of the blade
        float heap = Mathf.Clamp01(d.BladeLoadM3 / DozerController.FullLoadM3);
        float moving = Mathf.Clamp01(Mathf.Abs(d.Speed) / 0.6f);
        GameAudio.Steer(dirt, heap * moving * 0.8f * fx, 0.8f + 0.15f * Mathf.Abs(d.Speed), dt, 6f);

        // the hydraulics: any ram moving
        float rams = Mathf.Abs(d.BladeHeight01 - lastBlade) + Mathf.Abs(d.RipperHeight01 - lastRipper)
                   + (Mathf.Abs(d.BladeYaw - lastYaw) + Mathf.Abs(d.BladeTilt - lastTilt)) * 0.02f;
        lastBlade = d.BladeHeight01; lastRipper = d.RipperHeight01; lastYaw = d.BladeYaw; lastTilt = d.BladeTilt;
        bool working = on && rams / dt > 0.05f;
        GameAudio.Steer(hydraulic, working ? 0.35f * fx : 0f, 0.95f + 0.15f * rpm, dt, 14f);

        // the ripper in the ground
        float rip = on && d.RipperIn ? Mathf.Clamp01(Mathf.Abs(d.Speed) / 0.8f) : 0f;
        GameAudio.Steer(ripper, rip * 0.75f * fx, 0.85f + 0.2f * Mathf.Abs(d.Speed), dt, 8f);

        // hard rock: one clunk as it hits
        if (d.BlockedByRock && !wasBlocked && d.Blade != null) GameAudio.PlayAt("clunk", d.Blade.position, 1f, 0.9f + 0.2f * Random.value);
        wasBlocked = d.BlockedByRock;
    }
}
