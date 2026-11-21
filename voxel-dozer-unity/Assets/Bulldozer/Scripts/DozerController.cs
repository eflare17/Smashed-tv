// Drives the bulldozer, works the blade and ripper, and digs the voxel ground when there is one.
//   W / S or up / down     forward / reverse        A / D or left / right   steer (turns on the spot when stopped)
//   R / F                  blade up / down          T / G                   ripper up / down
//   Q / E                  angle the blade left / right     Z / C           tilt the blade     X   straighten it
//   B                      blade auto on / off (Pad: A).  The blade holds a height by itself; while it is on, R / F
//                          (the triggers) move that height 5 cm a tap, from fully down (Cut 90 cm) to fully up (Fill).
// Game pad (see Pad.cs and CONTROLLER.md): left stick drives, right trigger lowers the blade, left trigger raises it,
// bumpers move the ripper, d-pad angles / tilts the blade, X straightens it, B lights, A blade auto, right stick looks round.
// Gyro blade: while the gyro button (right stick click; on the Steam Controller a back grip bound to it) is held,
// the right stick's POSITION is the blade's: left-right = tilt, up-down = angle.  Let go and the blade stays.
// The numbers below can be changed on the prefab in the Inspector.
using UnityEngine;

public class DozerController : MonoBehaviour
{
    [Header("Driving")]
    public float maxSpeed = 3.7f;            // metres a second forward (about 13 km/h)
    public float reverseSpeed = 3.0f;
    public float acceleration = 3.6f;
    public float turnSpeed = 44f;            // degrees a second
    [Header("Blade (angle of the lift arms; positive is down)")]
    public float bladeUpAngle = -26f;          // high enough to clear the ground going up a steep hill
    public float bladeDownAngle = 3f;        // worked out at the start from bladeDigDepth
    [System.NonSerialized] public float bladeDigDepth = 0.90f;      // fully down, the edge goes this far below the tracks (cuts into a hill)
    [System.NonSerialized] public float bladeSpeed = 24f;      // (not kept in the scene, so a change here always counts)
    public float bladeMaxAngle = 25f;        // how far the blade swings left or right
    [System.NonSerialized] public float bladeMaxTilt = 15f;         // how far one end drops (enough to cut level on any side slope you can drive)
    public float bladeTurnSpeed = 25f;       // degrees a second for angle and tilt
    [Header("Ripper (positive is up)")]
    public float ripperUpAngle = 22f;
    public float ripperDownAngle = -21f;     // tips about 40 cm into the ground
    public float ripperSpeed = 20f;
    [Header("Digging")]
    public float ripRadius = 0.36f;
    const float RipFrom = -3f;                 // the ripper tears ground once it is lowered past this (degrees; parked is 0)          // how wide each shank tears
    public int hardRockStops = 85;           // this many hard blocks in the blade's way stops the machine
    public bool showHelp = true;
    [Header("Gyro blade (pad: right stick while the gyro button is held)")]
    public float gyroDeadZone = 0.06f;       // stick movement this small is ignored, so the blade doesn't twitch
    public float gyroSmoothing = 12f;        // how quickly the blade catches up with the stick (higher = snappier)
    [Header("State")]
    // Not saved with the prefab on purpose: Unity kept an old stored "dead" and ignored the value written here.
    [System.NonSerialized] public bool dead = false;     // true = it has sat for years and nothing works until repaired (off for now: F9 switches it)
    [System.NonSerialized] public bool driven;           // someone is in the seat
    // Blade auto: the blade holds its edge at a set height by itself, anywhere from fully down to fully up.
    //   B / A turns it on (at the height used last) and off.
    //   While it is on, the blade lever (R / F, the triggers) moves the height it holds, 5 cm a tap (hold to keep
    //   stepping): "Cut 25 cm" holds the edge 25 cm into the firm ground ahead, "Flat" level with the bottom of the
    //   tracks, "Fill 10 cm" 10 cm above them (for spreading dirt in layers).  Settings > Auto height off: the lever
    //   moves the blade by hand as before.  Moving the blade's angle or tilt by hand pauses just that part; the next
    //   press of B / A brings it back.  The height is remembered (between games too).
    // (The named settings below are kept for the tests and for older code: Flat and Cut 5..20 cm.)
    public enum BladeAutoMode { Off, Flat, Cut5, Cut10, Cut15, Cut20, Other }
    static readonly int[] ModeCm = { 0, 0, -5, -10, -15, -20, 0 };
    public const int AutoStepCm = 5;
    bool autoOn;
    int autoCm;                                          // the height it holds, cm: - = cut into the ground, + = above the tracks
    /// The setting, as one of the named ones (Other: a height that has no name of its own).  Setting it picks that height.
    public BladeAutoMode bladeAuto
    {
        get
        {
            if (!autoOn) return BladeAutoMode.Off;
            for (int m = 1; m <= 5; m++) if (ModeCm[m] == autoCm) return (BladeAutoMode)m;
            return BladeAutoMode.Other;
        }
        set
        {
            if (value == BladeAutoMode.Off) { autoOn = false; return; }
            autoOn = true;
            if (value != BladeAutoMode.Other) autoCm = ModeCm[(int)value];
            heightPaused = levelPaused = straightPaused = false;
        }
    }
    /// The height blade auto holds (cm, - = cut).  Kept within what the blade can reach.
    public int AutoCm { get { return autoCm; } set { autoCm = Mathf.Clamp(value, -MaxCutCm, MaxFillCm); LastCm = autoCm; } }
    public int MaxCutCm { get { return Mathf.FloorToInt(bladeDigDepth * 100f / AutoStepCm + 0.01f) * AutoStepCm; } }
    public int MaxFillCm { get { return Mathf.Max(0, Mathf.FloorToInt((BladeUpHeight * 100f - 2f) / AutoStepCm) * AutoStepCm); } }
    public static string NameOfCm(int cm) { return cm == 0 ? "Flat" : cm < 0 ? "Cut " + (-cm) + " cm" : "Fill " + cm + " cm"; }
    public string BladeAutoName { get { return autoOn ? NameOfCm(autoCm) : "Off"; } }
    public const string BladeAutoPref = "set.bladeAuto";
    /// The height used last: what B brings back when it turns auto on.
    public static int LastCm = 0;
    /// (older name for the last setting, for the tests: picks a named height)
    public static BladeAutoMode LastAuto
    {
        get { for (int m = 1; m <= 5; m++) if (ModeCm[m] == LastCm) return (BladeAutoMode)m; return BladeAutoMode.Other; }
        set { if (value != BladeAutoMode.Off && value != BladeAutoMode.Other) LastCm = ModeCm[(int)value]; }
    }
    // Full auto: three parts, each with its own switch in Settings (all on to start with).  B / A turns auto on.
    // Moving the angle or tilt by hand pauses just that part; the next press of B / A brings them all back.
    public static bool AutoHeight = true, AutoLevel = true, AutoStraight = true;
    bool heightPaused, levelPaused, straightPaused;
    bool autoPaused { get { return heightPaused || levelPaused || straightPaused; } }
    bool AutoOn { get { return autoOn; } }
    bool HeightActive { get { return AutoOn && AutoHeight && !heightPaused; } }
    bool LevelActive { get { return AutoOn && AutoLevel && !levelPaused; } }
    bool StraightActive { get { return AutoOn && AutoStraight && !straightPaused; } }
    // moving the blade by hand starts slow and speeds up the longer you hold it: a tap is a nudge
    float holdLift, holdAngle, holdTilt, stepHeld;
    const float NudgeSpeed = 0.2f, FullSpeedAfter = 0.7f;
    static float Ramp(ref float held, float input, float dt)
    {
        if (input == 0f) { held = 0f; return 0f; }
        held += dt;
        return input * Mathf.Lerp(NudgeSpeed, 1f, Mathf.Clamp01(held / FullSpeedAfter));
    }
    /// B / A: paused, it carries on; otherwise it turns auto on (at the last height) or off.
    public void CycleBladeAuto()
    {
        if (autoPaused && AutoOn) heightPaused = levelPaused = straightPaused = false;
        else if (autoOn) autoOn = false;
        else { autoOn = true; autoCm = Mathf.Clamp(LastCm, -MaxCutCm, MaxFillCm); heightPaused = levelPaused = straightPaused = false; }
        SaveAutoPrefs();
    }
    /// The lever while auto is on: the height it holds goes up (+1) or down (-1) one step.
    public void StepAutoHeight(int dir)
    {
        AutoCm = autoCm + dir * AutoStepCm;
        SaveAutoPrefs();
    }
    void SaveAutoPrefs()
    {
        if (autoOn) LastCm = autoCm;
        PlayerPrefs.SetInt(BladeAutoPref + ".on", autoOn ? 1 : 0);
        PlayerPrefs.SetInt(BladeAutoPref + ".cm", LastCm);
        PlayerPrefs.Save();
    }
    /// The remembered setting, as the game starts.
    void LoadBladeAuto()
    {
        if (PlayerPrefs.HasKey(BladeAutoPref + ".on"))
        {
            autoOn = PlayerPrefs.GetInt(BladeAutoPref + ".on", 0) == 1;
            LastCm = autoCm = PlayerPrefs.GetInt(BladeAutoPref + ".cm", 0);
        }
        else
        {
            // remembered from before there were free heights: Off, Flat, Cut 5, 10, 15, 20 cm
            int was = Mathf.Clamp(PlayerPrefs.GetInt(BladeAutoPref, 0), 0, 5), last = Mathf.Clamp(PlayerPrefs.GetInt(BladeAutoPref + ".last", 1), 1, 5);
            autoOn = was != 0;
            LastCm = autoCm = ModeCm[was != 0 ? was : last];
        }
        heightPaused = levelPaused = straightPaused = false;
        AutoHeight = PlayerPrefs.GetInt("set.autoHeight", 1) == 1;
        AutoLevel = PlayerPrefs.GetInt("set.autoLevel", 1) == 1;
        AutoStraight = PlayerPrefs.GetInt("set.autoStraight", 1) == 1;
    }

    // What works.  A working dozer (not dead) can do everything.  A dead one gets each back as its part is fitted.
    public bool CanDrive { get { return !dead || Finds.IsInstalled(0); } }
    public bool CanBlade { get { return !dead || Finds.IsInstalled(1); } }
    public bool CanRip { get { return !dead || Finds.IsInstalled(2); } }
    [Header("Driven by script instead of the keyboard (tests, touch buttons, AI)")]
    public bool useOverride;
    public float overrideThrottle, overrideSteer, overrideBlade, overrideRipper, overrideAngle, overrideTilt;

    public float Speed { get; private set; }             // current speed, + forward, - reverse
    public float Throttle { get { return throttleIn; } }  // the driver's throttle, -1..1 (the sound and the exhaust)
    /// How fast the faster track is running, metres a second (slipping included).
    public float TrackSpeed { get { return Mathf.Max(trackLeft != null ? Mathf.Abs(trackLeft.speed) : 0f, trackRight != null ? Mathf.Abs(trackRight.speed) : 0f); } }
    public bool RipperIn { get { return ripperAngle < RipFrom; } }   // lowered into the ground, tearing it
    /// The engine: Rpm 0 (idle) .. 1 (flat out), and Labour 0..1, how hard the load is holding it back.
    /// (The sound and the exhaust smoke follow these.)
    public float Rpm { get; private set; }
    public float Labour { get; private set; }
    void UpdateEngine(float dt)
    {
        bool on = driven && CanDrive;
        float throttle = Mathf.Abs(throttleIn);
        float wantRpm = on ? Mathf.Clamp01(throttle * 0.85f + Mathf.Abs(Speed) * 0.04f) : 0f;
        Rpm = Mathf.MoveTowards(Rpm, wantRpm, dt * (wantRpm > Rpm ? 1.2f : 0.8f));
        float wantLabour = on && throttle > 0.2f ? Mathf.Clamp01((1f - Bog) * 1.5f + (Climbing ? 0.4f : 0f) + (BlockedByRock ? 0.7f : 0f)) : 0f;
        Labour = Mathf.MoveTowards(Labour, wantLabour, dt * 1.5f);
    }

    // ---- Heavy feel.  Looks only: the body lifts its nose a little as the blade fills, jolts forward on a hard hit
    // and rocks as it climbs over a heap.  The digging and blade auto use the machine without this (Unfelt).
    Quaternion felt = Quaternion.identity;
    float feltLift, jolt, joltVel, rockAmt, rockT;
    public float FeltPitch { get { return felt.eulerAngles.x > 180f ? felt.eulerAngles.x - 360f : felt.eulerAngles.x; } }   // (tests)
    Quaternion Feel(float dt)
    {
        float load = Mathf.Clamp01(BladeLoadM3 / FullLoad);
        feltLift = Mathf.Lerp(feltLift, -0.8f * load * (Speed > 0.05f ? 1f : 0.5f), 1f - Mathf.Exp(-2f * dt));   // - is nose up
        joltVel += (-70f * jolt - 10f * joltVel) * dt;                                                          // a spring, kicked by a hard hit
        jolt += joltVel * dt;
        rockAmt = Mathf.MoveTowards(rockAmt, Climbing ? 0.6f : 0f, dt * 2f);
        rockT += dt * (1.5f + Mathf.Abs(Speed) * 4f);
        float rp = rockAmt * (Mathf.PerlinNoise(rockT, 0.37f) - 0.5f) * 2f, rr = rockAmt * (Mathf.PerlinNoise(0.71f, rockT) - 0.5f) * 2f;
        return Quaternion.Euler(feltLift + jolt + rp, 0f, rr);
    }
    /// A point on the machine as it would be without the heavy-feel tilt.
    Vector3 Unfelt(Vector3 p)
    {
        Vector3 o = transform.position;
        return o + transform.rotation * (Quaternion.Inverse(felt) * (Quaternion.Inverse(transform.rotation) * (p - o)));
    }
    public float BladeHeight01 { get; private set; }     // 0 = down, 1 = fully up
    public float RipperHeight01 { get; private set; }
    public bool GyroHeld { get; private set; }           // the gyro button is down: the right stick is the blade
    public bool BlockedByRock { get; private set; }
    public bool AtFence { get; private set; }            // pushing against the edge of the work site
    public bool OnRoadStrip { get; private set; }
    public string BladeLoadInfo() { return world != null && blade != null ? world.ClodSpread(blade.localToWorldMatrix, BladePlateMin, BladePlateMax) : "no blade"; }
    public Transform Blade { get { return blade; } }     // the blade itself (its cutting edge is along its bottom, see BladeView)        // out on the mountain road's strip (past the site's own limits)
    public bool AtCliff { get; private set; }            // up against a face too steep to climb
    public bool Climbing { get; private set; }           // crawling over loose spoil, or into a face with the blade cutting it
    const float ClimbSpeed = 0.8f;                       // metres a second while doing that
    // ---- Resistance.  An empty blade drives at full speed.  The heap in front of it slows it: a full blade (about
    // FullLoad m3) to about a third.  A deep bite slows it too: the engine can only cut about MaxCutRate m3 a second,
    // so a bite that would cut more than that at full speed slows it until it doesn't.  Bog is the share of full
    // speed that is left (1 = free), eased so it doesn't judder.
    const float FullLoad = 5f, LoadSlowest = 0.33f, MaxCutRate = 1.3f, CutSlowest = 0.22f;
    public float Bog { get; private set; } = 1f;
    public float BladeLoadM3 { get; private set; }
    public float CutRateM3 { get; private set; }               // what the blade would be cutting per second at full speed
    void UpdateBog(float moved)
    {
        float dt = Time.fixedDeltaTime;
        BladeLoadM3 = world.BladeLoadVoxels * VoxelWorld.VoxelVolume;
        float loadK = Mathf.Lerp(1f, LoadSlowest, Mathf.Clamp01(BladeLoadM3 / FullLoad));
        float atFull = moved > 0.0005f ? LastCut * VoxelWorld.VoxelVolume * (maxSpeed * dt / moved) / dt : 0f;
        CutRateM3 = Mathf.Lerp(CutRateM3, atFull, 1f - Mathf.Exp(-6f * dt));
        float cutK = CutRateM3 > MaxCutRate ? Mathf.Max(CutSlowest, MaxCutRate / CutRateM3) : 1f;
        float target = Mathf.Min(loadK, cutK);
        Bog = Mathf.MoveTowards(Bog, target, (target < Bog ? 1.5f : 0.8f) * dt);
    }
    public int LastCut { get; private set; }             // blocks the blade moved in the last step
    public float BladeYaw { get; private set; }          // degrees; + swings the right-hand end back
    public float BladeTilt { get; private set; }         // degrees; + drops the right-hand end

    // the blade's working box and the ripper tips, in their own parts' space (from the voxel model)
    // Only the front slab of the blade pushes.  Dirt that comes down over the top lands behind it and is left there.
    static readonly Vector3 BladeBoxMin = new Vector3(-2.2f, -0.75f, 0.85f);
    static readonly Vector3 BladeBoxMax = new Vector3(2.2f, 1.25f, 1.15f);
    // the blade as a solid plate, for shoving loose clods
    static readonly Vector3 BladePlateMin = new Vector3(-2.25f, -0.8f, 0.5f);
    static readonly Vector3 BladePlateMax = new Vector3(2.25f, 1.32f, 1.15f);
    // Where the ripper breaks the ground: under its three shanks, and the rock between them, which the shanks crack
    // as they go (every half metre across, so the broken balls overlap).  Ripping only under the shanks used to leave
    // ridges of solid rock between the furrows, right at blade depth, and the blade then stopped dead on "hard rock"
    // in ground that had been ripped.
    static readonly Vector3[] RipperTips =
    {
        new Vector3(-1.5f, -1.15f, -0.56f), new Vector3(-1f, -1.15f, -0.56f), new Vector3(-0.5f, -1.15f, -0.56f), new Vector3(0f, -1.15f, -0.56f),
        new Vector3(0.5f, -1.15f, -0.56f), new Vector3(1f, -1.15f, -0.56f), new Vector3(1.5f, -1.15f, -0.56f),
    };
    // where the tracks touch the ground, in the machine's space
    static readonly Vector3[] TrackPoints =
    {
        new Vector3(-1.4f, 0f, 2.2f), new Vector3(1.4f, 0f, 2.2f),
        new Vector3(-1.4f, 0f, 0.1f), new Vector3(1.4f, 0f, 0.1f),
        new Vector3(-1.4f, 0f, -2.0f), new Vector3(1.4f, 0f, -2.0f),
    };

    Transform bladeMount, rearMount, blade, ripper, bladeHinge, lights;
    Vector3 lastBladePos;
    bool haveLastBladePos;
    TrackAnimator trackLeft, trackRight;
    ParticleSystem spray;
    const float HalfTrackGauge = 1.4f;                   // metres from the middle of the machine to each track
    Rigidbody body;
    VoxelWorld world;
    float turn, bladeAngle, ripperAngle, throttleIn, steerIn;
    float yaw, pitch, roll, height, blockedTimer, fps;
    Vector2 gyroGrabStick;                               // the stick, and the blade, at the moment the gyro button went down
    float gyroGrabTilt, gyroGrabYaw;
    readonly Vector3[] tipsWorld = new Vector3[14];
    float[] autoAngle = new float[1];                   // the lift-arm angle that puts the blade edge at each auto height, every 5 cm from fully down (machine level)
    float AngleForCm(int cm) { int i = Mathf.Clamp((cm + MaxCutCm) / AutoStepCm, 0, autoAngle.Length - 1); return autoAngle[i]; }
    float edgePerDegree;                                // how far the edge drops for each degree the arms go down
    static readonly Vector3 BladeEdge = new Vector3(0f, -0.75f, 1.125f);   // middle of the cutting edge, in the blade's space

    void Awake()
    {
        bladeMount = FindDeep(transform, "Mount_BladeLift");
        rearMount = FindDeep(transform, "Mount_Rear");
        blade = FindDeep(transform, "Blade");
        bladeHinge = FindDeep(transform, "Mount_Blade");
        lights = FindDeep(transform, "Lights");
        ripper = FindDeep(transform, "Ripper");
        body = GetComponent<Rigidbody>();
        var tl = FindDeep(transform, "Track_Left"); if (tl != null) trackLeft = tl.GetComponent<TrackAnimator>();
        var tr = FindDeep(transform, "Track_Right"); if (tr != null) trackRight = tr.GetComponent<TrackAnimator>();
        yaw = transform.eulerAngles.y;
        height = transform.position.y;
        bladeAngle = 0f;                                                  // parked: blade and ripper resting on the ground
        ripperAngle = 0f;
        WorkOutAutoAngles();
        if (!Application.isEditor) LoadBladeAuto();                      // (tests start with it off)
        ApplyAttachments();
    }

    /// How high the middle of the blade's cutting edge sits above the bottom of the tracks with the lift arms at
    /// `angle` and the machine level.  (Moves the arms to look; the caller puts them back.)
    float EdgeHeightAt(float angle)
    {
        bladeMount.localRotation = Quaternion.Euler(angle, 0f, 0f);
        return transform.InverseTransformPoint(blade.TransformPoint(BladeEdge)).y;
    }

    /// For each auto setting, the arm angle that puts the edge at that depth below the tracks.
    void WorkOutAutoAngles()
    {
        if (bladeMount == null || blade == null) return;
        Quaternion was = bladeMount.localRotation, hingeWas = bladeHinge != null ? bladeHinge.localRotation : Quaternion.identity;
        if (bladeHinge != null) bladeHinge.localRotation = Quaternion.identity;
        {
            // fully down: the arm angle that puts the edge bladeDigDepth below the tracks
            float lo = bladeUpAngle, hi = 70f;
            for (int i = 0; i < 30; i++)
            {
                float mid = (lo + hi) * 0.5f;
                if (EdgeHeightAt(mid) > -bladeDigDepth) lo = mid; else hi = mid;
            }
            bladeDownAngle = (lo + hi) * 0.5f;
        }
        BladeDownDepth = -EdgeHeightAt(bladeDownAngle);
        BladeUpHeight = EdgeHeightAt(bladeUpAngle);
        autoAngle = new float[(MaxCutCm + MaxFillCm) / AutoStepCm + 1];
        for (int k = 0; k < autoAngle.Length; k++)
        {
            // more angle = lower blade.  Halve the gap until it is close enough.
            float lo = bladeUpAngle, hi = bladeDownAngle + 12f, want = (k * AutoStepCm - MaxCutCm) / 100f;
            for (int i = 0; i < 30; i++)
            {
                float mid = (lo + hi) * 0.5f;
                if (EdgeHeightAt(mid) > want) lo = mid; else hi = mid;
            }
            autoAngle[k] = (lo + hi) * 0.5f;
        }
        autoCm = Mathf.Clamp(autoCm, -MaxCutCm, MaxFillCm);
        edgePerDegree = (EdgeHeightAt(0f) - EdgeHeightAt(bladeDownAngle)) / Mathf.Max(0.1f, bladeDownAngle);
        bladeMount.localRotation = was;
        if (bladeHinge != null) bladeHinge.localRotation = hingeWas;
    }

    /// Where blade auto wants the lift arms.
    /// Flat: the edge level with the bottom of the tracks.  The machine then rides on what it has levelled, so it stays level.
    /// Cut: the edge `depth` below the firm ground just ahead of the blade (not yet cut; loose dirt in front of the blade
    /// is left out).  Measuring from the tracks would not do here: they drop into the cut, the machine sinks with them,
    /// and the cut would keep getting deeper.
    float AutoWant()
    {
        float fixedAngle = AngleForCm(autoCm);
        if (autoCm >= 0 || world == null || blade == null || edgePerDegree <= 0f) return fixedAngle;
        Vector3 fwd = transform.forward; fwd.y = 0f;
        if (fwd.sqrMagnitude < 0.01f) return fixedAngle;
        fwd.Normalize();
        Vector3 right = new Vector3(fwd.z, 0f, -fwd.x);
        Vector3 edge = Unfelt(blade.TransformPoint(BladeEdge));
        float sum = 0f; int n = 0;
        for (float a = 1.5f; a <= 3.01f; a += 0.75f)
            for (float s = -1f; s <= 1.01f; s += 1f)
            {
                Vector3 p = edge + fwd * a + right * s;
                float h;
                if (world.FirmHeightAt(p.x, p.z, out h)) { sum += h; n++; }
            }
        if (n < 5) return fixedAngle;
        float want = sum / n + autoCm / 100f;
        // more arm angle = lower edge, about edgePerDegree metres a degree
        return Mathf.Clamp(bladeAngle + (edge.y - want) / edgePerDegree, bladeUpAngle, bladeDownAngle);
    }

    public float AutoAngle(BladeAutoMode m) { return AngleForCm(ModeCm[(int)m]); }
    public float AutoAngleCm(int cm) { return AngleForCm(cm); }

    /// How much higher the right end of the cutting edge is than the left (metres, in the world).
    public float EdgeEndsGap()
    {
        if (blade == null) return 0f;
        Vector3 r = Unfelt(blade.TransformPoint(new Vector3(2.25f, BladeEdge.y, BladeEdge.z)));
        Vector3 l = Unfelt(blade.TransformPoint(new Vector3(-2.25f, BladeEdge.y, BladeEdge.z)));
        return r.y - l.y;
    }
    /// The tilt that makes the cutting edge level side to side (+ tilt drops the right end; 4.5 m of edge, about 7.9 cm a degree).
    float LevelTilt() { return Mathf.Clamp(BladeTilt + EdgeEndsGap() / 0.0785f, -bladeMaxTilt, bladeMaxTilt); }
    /// (tests) Lean the machine `lean` degrees, let auto level settle, and give the edge's end-to-end gap; then put it back.
    public static float TestLevelTilt, TestLevelRaw;
    public float TestLevelGap(float lean)
    {
        float r0 = roll, t0 = BladeTilt; Quaternion q0 = transform.rotation;
        roll = lean;
        transform.rotation = Quaternion.Euler(0f, yaw, 0f) * Quaternion.Euler(pitch, 0f, roll) * felt;   // as the game shows it
        ApplyAttachments();
        for (int i = 0; i < 60; i++) { BladeTilt = LevelTilt(); ApplyAttachments(); }   // (about one second of play)
        float gap = EdgeEndsGap(); TestLevelTilt = BladeTilt; BladeTilt = 0f; ApplyAttachments(); TestLevelRaw = EdgeEndsGap();
        roll = r0; BladeTilt = t0; transform.rotation = q0; ApplyAttachments();
        return gap;
    }
    string AutoHelp { get { return autoPaused && AutoOn ? BladeAutoName + ", paused (press to carry on)" : BladeAutoName; } }
    public bool HeightAutoActive { get { return HeightActive; } }
    public float BladeArmAngle { get { return bladeAngle; } }
    public float BladeUpHeight { get; private set; }     // how high the edge is above the tracks fully up (the height bar's top)
    public float BladeDownDepth { get; private set; }    // how far below the tracks the edge goes fully down (for the tests)

    void Start()
    {
        world = VoxelWorld.Instance;
        if (world != null && GetComponent<BladeView>() == null) gameObject.AddComponent<BladeView>();
        if (world != null && GetComponent<DozerFX>() == null) gameObject.AddComponent<DozerFX>();
    }

    // Clods tumbling off the top of the heap while the blade is cutting.  Looks only: they are not counted as dirt.
    void SetUpSpray()
    {
        var go = new GameObject("Dirt spray");
        go.transform.SetParent(blade, false);
        go.transform.localPosition = new Vector3(0f, 0.1f, 1.5f);
        go.transform.localRotation = Quaternion.Euler(-50f, 0f, 0f);       // up and forward
        spray = go.AddComponent<ParticleSystem>();
        spray.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        var main = spray.main;
        main.loop = true;
        main.startLifetime = new ParticleSystem.MinMaxCurve(0.45f, 1.0f);
        main.startSpeed = new ParticleSystem.MinMaxCurve(0.6f, 2.4f);
        main.startSize = new ParticleSystem.MinMaxCurve(0.0625f, 0.125f);
        main.startRotation3D = true;
        main.startRotationX = main.startRotationY = main.startRotationZ = new ParticleSystem.MinMaxCurve(0f, 6.28f);
        main.gravityModifier = 1.3f;
        main.simulationSpace = ParticleSystemSimulationSpace.World;
        main.maxParticles = 700;
        main.startColor = Color.white;
        var emission = spray.emission;
        emission.rateOverTime = 0f;
        var shape = spray.shape;
        shape.shapeType = ParticleSystemShapeType.Box;
        shape.scale = new Vector3(4.0f, 0.5f, 0.3f);
        var spin = spray.rotationOverLifetime;
        spin.enabled = true;
        spin.separateAxes = true;
        spin.x = spin.y = spin.z = new ParticleSystem.MinMaxCurve(-7f, 7f);
        var rend = go.GetComponent<ParticleSystemRenderer>();
        rend.renderMode = ParticleSystemRenderMode.Mesh;
        var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        rend.mesh = cube.GetComponent<MeshFilter>().sharedMesh;
        Destroy(cube);
        var clodMat = new Material(Shader.Find("Standard")) { color = new Color(0.50f, 0.36f, 0.22f) };
        clodMat.SetFloat("_Glossiness", 0.05f);
        rend.sharedMaterial = clodMat;
        spray.Play();
    }

    void Update()
    {
        if (!driven) { throttleIn = steerIn = 0f; UpdateEngine(Time.deltaTime); ApplyAttachments(); return; }
        throttleIn = useOverride ? overrideThrottle : Stronger(Input.GetAxisRaw("Vertical"), Pad.LeftStick.y);
        steerIn = useOverride ? overrideSteer : Stronger(Input.GetAxisRaw("Horizontal"), Pad.LeftStick.x);
        if (!CanDrive) throttleIn = steerIn = 0f;

        float bladeIn = useOverride ? overrideBlade : Ramp(ref holdLift, (Input.GetKey(KeyCode.R) || Pad.LT > 0.3f ? 1f : 0f) - (Input.GetKey(KeyCode.F) || Pad.RT > 0.3f ? 1f : 0f), Time.deltaTime);
        float ripperIn = useOverride ? overrideRipper : (Input.GetKey(KeyCode.T) || Pad.Held(Pad.B.RB) ? 1f : 0f) - (Input.GetKey(KeyCode.G) || Pad.Held(Pad.B.LB) ? 1f : 0f);
        if (!CanBlade) bladeIn = 0f;
        if (!CanRip) ripperIn = 0f;
        bool treeUp = Upgrades.Instance != null && Upgrades.Instance.Open;
        if (!useOverride && CanBlade && !treeUp && !(PauseMenu.Instance != null && PauseMenu.Instance.Open) && (Input.GetKeyDown(KeyCode.B) || Pad.Down(Pad.B.A))) CycleBladeAuto();
        if (AutoOn && !CanBlade) heightPaused = levelPaused = straightPaused = true;
        if (bladeIn != 0f && AutoOn && AutoHeight)
        {
            if (useOverride) heightPaused = true;                          // (the tests' hand on the lever takes over the height, as it used to)
            else
            {
                // the lever moves the height auto holds: a step as it is pressed, then a step every 0.15 s while held
                int dir = bladeIn > 0f ? 1 : -1;
                if (stepHeld == 0f || (stepHeld >= 0.4f && Mathf.Repeat(stepHeld - 0.4f, 0.15f) < Time.deltaTime)) StepAutoHeight(dir);
                stepHeld += Time.deltaTime;
                heightPaused = false;
                bladeIn = 0f;
            }
        }
        else stepHeld = 0f;
        if (HeightActive) bladeAngle = Mathf.MoveTowards(bladeAngle, AutoWant(), bladeSpeed * Time.deltaTime);
        if (bladeIn != 0f) bladeAngle = Mathf.MoveTowards(bladeAngle, bladeIn > 0f ? bladeUpAngle : bladeDownAngle, bladeSpeed * Mathf.Abs(bladeIn) * Time.deltaTime);
        if (ripperIn != 0f) ripperAngle = Mathf.MoveTowards(ripperAngle, ripperIn > 0f ? ripperUpAngle : ripperDownAngle, ripperSpeed * Time.deltaTime);
        float angleIn = useOverride ? overrideAngle : (Input.GetKey(KeyCode.E) || Pad.DX > 0 ? 1f : 0f) - (Input.GetKey(KeyCode.Q) || Pad.DX < 0 ? 1f : 0f);
        float tiltIn = useOverride ? overrideTilt : (Input.GetKey(KeyCode.C) || Pad.DY < 0 ? 1f : 0f) - (Input.GetKey(KeyCode.Z) || Pad.DY > 0 ? 1f : 0f);
        if (!CanBlade) angleIn = tiltIn = 0f;
        if (treeUp || (PauseMenu.Instance != null && PauseMenu.Instance.Open)) angleIn = tiltIn = 0f;   // the d-pad is moving round the upgrades or the menu, not the blade
        if (!useOverride) { angleIn = Ramp(ref holdAngle, angleIn, Time.deltaTime); tiltIn = Ramp(ref holdTilt, tiltIn, Time.deltaTime); }
        BladeYaw = Mathf.Clamp(BladeYaw + angleIn * bladeTurnSpeed * Time.deltaTime, -bladeMaxAngle, bladeMaxAngle);
        BladeTilt = Mathf.Clamp(BladeTilt + tiltIn * bladeTurnSpeed * Time.deltaTime, -bladeMaxTilt, bladeMaxTilt);
        GyroBlade();
        if ((tiltIn != 0f || GyroHeld) && AutoOn && AutoLevel) levelPaused = true;          // tilting by hand pauses the levelling
        if ((angleIn != 0f || GyroHeld) && AutoOn && AutoStraight) straightPaused = true;   // swinging by hand pauses the straightening
        if (!useOverride && CanBlade && (Input.GetKey(KeyCode.X) || Pad.Held(Pad.B.X)))
        {
            BladeYaw = Mathf.MoveTowards(BladeYaw, 0f, bladeTurnSpeed * 2f * Time.deltaTime);
            if (!LevelActive) BladeTilt = Mathf.MoveTowards(BladeTilt, 0f, bladeTurnSpeed * Time.deltaTime);
        }
        // auto level: the blade level side to side, however the machine leans.  Auto straight: swung back square.
        if (LevelActive) BladeTilt = Mathf.MoveTowards(BladeTilt, LevelTilt(), bladeTurnSpeed * Time.deltaTime);
        if (StraightActive) BladeYaw = Mathf.MoveTowards(BladeYaw, 0f, bladeTurnSpeed * Time.deltaTime);
        ApplyAttachments();
        if (lights != null && !useOverride && (Input.GetKeyDown(KeyCode.L) || Pad.Down(Pad.B.B))) lights.gameObject.SetActive(!lights.gameObject.activeSelf);
        fps = Mathf.Lerp(fps, 1f / Mathf.Max(Time.unscaledDeltaTime, 0.0001f), 0.05f);
        UpdateEngine(Time.deltaTime);
        // a faint steady shudder through the seat while the ripper tears the ground
        if (RipperIn && Mathf.Abs(Speed) > 0.1f) FollowCamera.Shake = Mathf.Max(FollowCamera.Shake, 0.004f + 0.003f * Mathf.Abs(Speed));
    }

    static float Stronger(float a, float b) { return Mathf.Abs(b) > Mathf.Abs(a) ? b : a; }

    /// The gyro blade.  While the gyro button is held, the right stick's position sets the blade: left-right tilts it
    /// (full over = bladeMaxTilt), up-down angles it (full = bladeMaxAngle).  It counts from where the blade and the
    /// stick were when the button went down, so the blade never jumps on the press.  Let go and the blade stays put.
    void GyroBlade()
    {
        bool held = !useOverride && CanBlade && Pad.Held(Pad.B.RS);
        Vector2 stick = Pad.RightStick;
        if (held && !GyroHeld) { gyroGrabStick = stick; gyroGrabTilt = BladeTilt; gyroGrabYaw = BladeYaw; }
        GyroHeld = held;
        if (!held) return;
        Vector2 moved = stick - gyroGrabStick;
        moved.x = GyroDead(moved.x); moved.y = GyroDead(moved.y);
        float wantTilt = Mathf.Clamp(gyroGrabTilt + moved.x * bladeMaxTilt, -bladeMaxTilt, bladeMaxTilt);
        float wantYaw = Mathf.Clamp(gyroGrabYaw + moved.y * bladeMaxAngle, -bladeMaxAngle, bladeMaxAngle);
        float k = 1f - Mathf.Exp(-gyroSmoothing * Time.deltaTime);
        BladeTilt = Mathf.Lerp(BladeTilt, wantTilt, k);
        BladeYaw = Mathf.Lerp(BladeYaw, wantYaw, k);
    }

    float GyroDead(float v)
    {
        float a = Mathf.Abs(v);
        return a <= gyroDeadZone ? 0f : Mathf.Sign(v) * (a - gyroDeadZone) / (1f - gyroDeadZone);
    }

    void FixedUpdate()
    {
        float dt = Time.fixedDeltaTime;
        if (!driven)
        {
            // parked.  The blade is still a solid thing for loose dirt to pile against.
            Speed = 0f; turn = 0f;
            if (trackLeft != null) trackLeft.speed = 0f;
            if (trackRight != null) trackRight.speed = 0f;
            if (world != null && blade != null && !Dingo.Working) world.SetBlade(blade.localToWorldMatrix, BladePlateMin, BladePlateMax, false);   // (the Dingo's bucket is the plate while it works)
            return;
        }
        float want = throttleIn > 0f ? throttleIn * maxSpeed : throttleIn * reverseSpeed;
        want *= 1f - 0.35f * Mathf.Abs(steerIn);                         // tracks lose a little speed in a turn
        // Pushing is hard work: a big heap on the blade, or a deep bite, slows the machine (see Bog).
        float wantFree = want;
        if (want > 0f) want *= Bog;
        if (blockedTimer > 0f) { blockedTimer -= dt; if (want > 0f) want = 0f; }
        BlockedByRock = blockedTimer > 0f;
        Speed = Mathf.MoveTowards(Speed, want, acceleration * dt);
        turn = Mathf.MoveTowards(turn, steerIn * turnSpeed, turnSpeed * 3f * dt);

        // in a turn the outside track runs faster and the inside one slower (or backwards, turning on the spot)
        float slew = turn * Mathf.Deg2Rad * HalfTrackGauge;
        // bogged down, the tracks turn faster than the machine goes: they slip
        float trackRun = Speed > 0f && wantFree > Speed ? Mathf.Lerp(Speed, wantFree, Mathf.Clamp01((1f - Bog) * 1.2f)) : Speed;
        if (trackLeft != null) trackLeft.speed = trackRun + slew;
        if (trackRight != null) trackRight.speed = trackRun - slew;

        yaw += turn * dt;
        Quaternion yawRot = Quaternion.Euler(0f, yaw, 0f);
        Vector3 pos = body != null ? body.position : transform.position;
        Vector3 before = pos;
        pos += yawRot * Vector3.forward * (Speed * dt);

        if (world != null)
        {
            // stay on the work site: the ground outside the fence can't be dug.  The one way out is the mountain
            // road: along it the machine may drive anywhere within CorridorHalf of the line (the strip is wider, so
            // its blade and its dirt stay over diggable ground).
            float lim = VoxelWorld.DriveLimit;
            bool inSite = Mathf.Abs(pos.x) <= lim && Mathf.Abs(pos.z) <= lim;
            OnRoadStrip = false;
            AtFence = false;
            if (!inSite)
            {
                float s, off; Vector2 dir;
                float d = MountainRoad.Nearest(pos.x, pos.z, out s, out off, out dir);
                OnRoadStrip = d <= MountainRoad.CorridorHalf;
                if (!OnRoadStrip)
                {
                    bool wasOnRoad = MountainRoad.DistanceTo(before.x, before.z) <= MountainRoad.CorridorHalf + 0.05f
                                     && !(Mathf.Abs(before.x) <= lim && Mathf.Abs(before.z) <= lim);
                    if (wasOnRoad && s > 0.01f)
                    {
                        // slide along the edge of the road strip
                        Vector2 side = new Vector2(-dir.y, dir.x);
                        float back = off - Mathf.Sign(off) * MountainRoad.CorridorHalf;
                        pos.x -= side.x * back; pos.z -= side.y * back;
                    }
                    else if (wasOnRoad) { pos.x = before.x; pos.z = before.z; }
                    else { pos.x = Mathf.Clamp(pos.x, -lim, lim); pos.z = Mathf.Clamp(pos.z, -lim, lim); }
                    AtFence = true;
                }
            }
            // the scenery: trees, crates and the mine entrance are solid
            if (SiteProps.Blocks(pos, 2.3f))
            {
                // driving into a tree: push it (it leans, then goes over; TreeFelling).  Only head on, going forward.
                int tree = TreeFelling.Instance != null && throttleIn > 0.2f ? SiteProps.TreeBlocking(pos, 2.3f) : -1;
                if (tree >= 0)
                {
                    Vector3 fwd = yawRot * Vector3.forward, to = FireSim.Trees[tree].at - before;
                    to.y = 0f;
                    if (Vector3.Dot(fwd, to.normalized) > 0.35f) TreeFelling.Instance.Push(tree, fwd, dt);
                }
                pos = before; Speed = 0f;
            }
            // sit on the ground under the tracks, and lean with it
            float front = 0f, rear = 0f, left = 0f, right = 0f, all = 0f;
            for (int i = 0; i < TrackPoints.Length; i++)
            {
                Vector3 p = pos + yawRot * TrackPoints[i];
                float h = world.HeightAt(p.x, p.z);
                all += h;
                if (i < 2) front += h; else if (i >= 4) rear += h;
                if (i % 2 == 0) left += h; else right += h;
            }
            // A dozer cannot climb a wall.  If the ground under the leading end of the tracks is much higher
            // than under the middle, it is up against a face: stop there.  But not a dead stop it can't get out of:
            //   - loose dirt (its own spoil, a heap) it climbs over, slowly: the tracks press it down;
            //   - going forward with the blade down it creeps into the face, so the blade cuts it away.
            float mid = (all - front - rear) / 2f;
            float lead = Speed >= 0f ? front / 2f : rear / 2f;
            AtCliff = lead - mid > 0.8f;
            Climbing = false;
            if (AtCliff)
            {
                bool loose = false;
                for (int i = 0; i < TrackPoints.Length; i++)
                {
                    if (Speed >= 0f ? i >= 2 : i < 4) continue;          // the leading pair only
                    Vector3 p = pos + yawRot * TrackPoints[i];
                    loose |= world.LooseOnTop(p.x, p.z);
                }
                bool bladeIn = Speed > 0f && BladeHeight01 < 0.35f && CanBlade;
                if (loose || bladeIn)
                {
                    AtCliff = false; Climbing = true;
                    float most = ClimbSpeed * dt, moved = new Vector2(pos.x - before.x, pos.z - before.z).magnitude;
                    if (moved > most) { float k2 = most / moved; pos.x = before.x + (pos.x - before.x) * k2; pos.z = before.z + (pos.z - before.z) * k2; }
                    Speed = Mathf.Clamp(Speed, -ClimbSpeed, ClimbSpeed);
                }
            }
            if (AtCliff)
            {
                pos.x = before.x; pos.z = before.z;
                Speed = 0f;
                front = rear = left = right = all = 0f;
                for (int i = 0; i < TrackPoints.Length; i++)
                {
                    Vector3 p = pos + yawRot * TrackPoints[i];
                    float h = world.HeightAt(p.x, p.z);
                    all += h;
                    if (i < 2) front += h; else if (i >= 4) rear += h;
                    if (i % 2 == 0) left += h; else right += h;
                }
            }
            float k = 1f - Mathf.Exp(-9f * dt);
            height = Mathf.Lerp(height, all / 6f, k);
            pitch = Mathf.Lerp(pitch, Mathf.Atan2((rear - front) / 2f, 4.2f) * Mathf.Rad2Deg, k);
            roll = Mathf.Lerp(roll, Mathf.Atan2((right - left) / 3f, 2.8f) * Mathf.Rad2Deg, k);
            pos.y = height;
        }
        Quaternion rot = yawRot * Quaternion.Euler(pitch, 0f, roll);

        if (world != null)
        {
            glance = 0f;
            Dig(pos, rot);
            if (glance != 0f)
            {
                // a raised blade caught rock at one end only: slide away from it and turn off it a little
                pos += yawRot * Vector3.right * (glance * GlanceSlide * dt);
                yaw += glance * GlanceTurn * dt;
                Glanced = true;
            }
        }
        if (spray != null)
        {
            var emission = spray.emission;
            emission.rateOverTime = Speed > 0.3f ? Mathf.Clamp(LastCut * 0.25f, 0f, 140f) : 0f;
        }

        felt = Feel(dt);
        Quaternion shown = rot * felt;
        if (body != null) { body.MoveRotation(shown); body.MovePosition(pos); }
        else { transform.SetPositionAndRotation(pos, shown); }
    }

    // ---- glancing off rock with a raised blade (see Dig)
    const float GlanceSlide = 0.6f, GlanceTurn = 14f;  // metres a second sideways, degrees a second of turn
    float glance;                                      // -1 slide left, +1 slide right, 0 none (this step)
    public bool Glanced { get; private set; }          // it has glanced off rock at some point (tests)

    /// Where hard rock is in the blade's box: -1 only in the left end, +1 only in the right end, 0 elsewhere or none.
    int RockAtOneEnd(Matrix4x4 bladeToWorld)
    {
        int left = 0, mid = 0, right = 0;
        for (float x = BladeBoxMin.x; x <= BladeBoxMax.x + 0.01f; x += 0.25f)
            for (float y = BladeBoxMin.y; y <= BladeBoxMax.y + 0.01f; y += 0.2f)
                for (float z = BladeBoxMin.z; z <= BladeBoxMax.z + 0.01f; z += 0.15f)
                {
                    byte m = world.MaterialAt(bladeToWorld.MultiplyPoint3x4(new Vector3(x, y, z)));
                    if (m < VoxelWorld.Rock || m > VoxelWorld.Gold) continue;
                    if (x < -1.2f) left++; else if (x > 1.2f) right++; else mid++;
                }
        if (mid > 0 || (left > 0) == (right > 0)) return 0;
        return left > 0 ? -1 : 1;
    }

    void Dig(Vector3 pos, Quaternion rot)
    {
        // where the parts will be once the machine has moved this step
        Matrix4x4 root = Matrix4x4.TRS(pos, rot, Vector3.one) * transform.worldToLocalMatrix;
        LastCut = 0;
        if (blade != null)
        {
            Matrix4x4 bladeToWorld = root * blade.localToWorldMatrix;
            Vector3 bladePos = bladeToWorld.MultiplyPoint3x4(new Vector3(0f, 0f, 1f));
            Vector3 travel = haveLastBladePos ? bladePos - lastBladePos : Vector3.zero;
            lastBladePos = bladePos; haveLastBladePos = true;
            // A blade that has not moved (parked, or stopped against a heap) cuts nothing new, so dirt that has
            // come to rest against it stays put instead of being cut up and stirred again every step.
            bool moved = travel.sqrMagnitude > 0.0015f * 0.0015f;
            var r = moved ? world.BladeSweep(bladeToWorld, BladeBoxMin, BladeBoxMax, travel, Time.fixedDeltaTime) : default(VoxelWorld.SweepResult);
            world.SetBlade(bladeToWorld, BladePlateMin, BladePlateMax, moved);
            world.SlumpCentre = bladeToWorld.MultiplyPoint3x4(new Vector3(0f, 0f, -1.5f));
            LastCut = r.cut;
            if (Speed > 0.05f) Goals.Pushed(r.cut);
            UpdateBog(travel.magnitude);
            if (r.hard >= hardRockStops && Speed > 0f && BladeHeight01 > 0.6f)
            {
                // Raised, the blade isn't working: if it is only one end catching a rock wall (driving past a bench,
                // turning into the ramp), glance off it instead of stopping dead.  Rock across the middle still stops it.
                int side = RockAtOneEnd(bladeToWorld);
                if (side != 0) { glance = -side; Speed *= 0.97f; r.hard = 0; }
            }
            if (r.hard >= hardRockStops && Speed > 0f)
            {
                if (blockedTimer <= 0f) { joltVel += 9f + 6f * Speed; FollowCamera.Bump(0.05f + 0.02f * Speed); }   // a hard hit: the body jolts, the camera bumps
                Speed = 0f; blockedTimer = 0.6f;
            }
        }
        // Only when it has been lowered into the ground.  Parked (0) its tips rest on the surface: it used to rip from
        // there too, so driving along tore up a strip of loose dirt behind the machine without anyone asking.
        if (ripper != null && ripperAngle < RipFrom)
        {
            Matrix4x4 ripperToWorld = root * ripper.localToWorldMatrix;
            int n = RipperTips.Length;
            for (int i = 0; i < n; i++)
            {
                tipsWorld[i] = ripperToWorld.MultiplyPoint3x4(RipperTips[i]);
                tipsWorld[i + n] = ripperToWorld.MultiplyPoint3x4(RipperTips[i] + new Vector3(0f, 0.3f, -0.15f));   // up the shank
            }
            world.Rip(tipsWorld, ripRadius, rot * Vector3.forward * Speed);
        }
    }

    public void WriteState(System.IO.BinaryWriter w)
    {
        Vector3 p = transform.position;
        w.Write(p.x); w.Write(p.y); w.Write(p.z);
        w.Write(yaw); w.Write(pitch); w.Write(roll); w.Write(height);
        w.Write(bladeAngle); w.Write(ripperAngle); w.Write(BladeYaw); w.Write(BladeTilt);
        w.Write(dead);
        w.Write(lights != null && lights.gameObject.activeSelf);
    }

    /// Puts the dozer at a spot on the ground, facing `yawDeg` (0 = +z), standing still.  (The prologue.)
    public void Place(Vector3 p, float yawDeg)
    {
        yaw = yawDeg; pitch = 0f; roll = 0f;
        p.y = height = SiteProps.HillY(p.x, p.z);
        Speed = 0f; turn = 0f; blockedTimer = 0f; haveLastBladePos = false;
        Quaternion rot = Quaternion.Euler(0f, yaw, 0f);
        transform.SetPositionAndRotation(p, rot);
        if (body != null) { body.position = p; body.rotation = rot; }
    }

    public void ReadState(System.IO.BinaryReader r)
    {
        Vector3 p = new Vector3(r.ReadSingle(), r.ReadSingle(), r.ReadSingle());
        yaw = r.ReadSingle(); pitch = r.ReadSingle(); roll = r.ReadSingle(); height = r.ReadSingle();
        bladeAngle = r.ReadSingle(); ripperAngle = r.ReadSingle(); BladeYaw = r.ReadSingle(); BladeTilt = r.ReadSingle();
        dead = r.ReadBoolean();
        bool lightsOn = r.ReadBoolean();
        if (lights != null) lights.gameObject.SetActive(lightsOn);
        Speed = 0f; turn = 0f; blockedTimer = 0f; haveLastBladePos = false;
        Quaternion rot = Quaternion.Euler(0f, yaw, 0f) * Quaternion.Euler(pitch, 0f, roll);
        transform.SetPositionAndRotation(p, rot);
        if (body != null) { body.position = p; body.rotation = rot; }
        ApplyAttachments();
    }

    void ApplyAttachments()
    {
        // The blade holds its depth below the tracks even when the machine tips into its own cut:
        // as the nose drops, the arms lift by the matching amount (the blade is further out than the arms are long).
        // Only while the blade is down working, though: lifted, it stays up with the machine, so going up a hill
        // with the blade raised it clears the ground instead of dropping into it.
        float down = 1f - Mathf.Clamp01(Mathf.InverseLerp(bladeDownAngle, bladeUpAngle, bladeAngle) / 0.6f);
        if (HeightActive) down = 1f;                                       // auto height: always hold the depth
        float held = Mathf.Clamp(bladeAngle - pitch * 1.46f * down, bladeUpAngle - 8f, bladeDownAngle + 12f);
        if (bladeMount != null) bladeMount.localRotation = Quaternion.Euler(held, 0f, 0f);
        if (rearMount != null) rearMount.localRotation = Quaternion.Euler(ripperAngle, 0f, 0f);
        // angle swings the blade about its upright; tilt drops one end.  Digging uses the blade exactly as it sits.
        if (bladeHinge != null) bladeHinge.localRotation = Quaternion.Euler(0f, BladeYaw, -BladeTilt);
        BladeHeight01 = Mathf.InverseLerp(bladeDownAngle, bladeUpAngle, bladeAngle);
        RipperHeight01 = Mathf.InverseLerp(ripperDownAngle, ripperUpAngle, ripperAngle);
    }

    static Transform FindDeep(Transform t, string name)
    {
        if (t.name == name) return t;
        for (int i = 0; i < t.childCount; i++)
        {
            var found = FindDeep(t.GetChild(i), name);
            if (found != null) return found;
        }
        return null;
    }

    /// How high the middle of the blade's edge is above the bottom of the tracks, in metres (- = cutting in).
    /// (The lower end of the edge, against where the tracks ride: the same as the blade view's number.)
    public float EdgeAboveTracks
    {
        get
        {
            if (blade == null) return 0f;
            return Mathf.Min(Unfelt(blade.TransformPoint(new Vector3(-2.25f, -0.75f, 1.1f))).y, Unfelt(blade.TransformPoint(new Vector3(2.25f, -0.75f, 1.1f))).y) - transform.position.y;
        }
    }
    public bool AutoPaused { get { return autoPaused; } }
    public static float FullLoadM3 { get { return FullLoad; } }

    /// The blade's depth line for the screen: "Blade 12 cm down", "Auto: Cut 10 cm", "Auto paused ...".
    public string DepthLine()
    {
        if (HeightActive) return "Auto: " + BladeAutoName;
        int cm = Mathf.RoundToInt(EdgeAboveTracks * 100f);
        string hand = cm < 0 ? "Blade " + (-cm) + " cm down" : cm == 0 ? "Blade level with the tracks" : "Blade " + cm + " cm up";
        return autoPaused ? hand + "   (Auto paused: " + Pad.Key("B", "A") + ")" : hand;
    }

    /// The warnings that apply right now (empty if none), one a line.
    public string Warnings()
    {
        string w = "";
        if (BlockedByRock) w += "HARD ROCK: back up and rip it first (" + Pad.Key("G", "LB") + ")\n";
        if (Mathf.Abs(BladeYaw) > 3f)          // a swung blade sends its dirt off one end, so it never fills: easy to do by accident
            w += "BLADE SWUNG " + Mathf.Abs(BladeYaw).ToString("F0") + " deg " + (BladeYaw > 0f ? "right" : "left") + ": dirt rolls off.  " + Pad.Key("X", "X") + " straightens it\n";
        if (AtFence) w += (MountainRoad.DistanceTo(transform.position.x, transform.position.z) < MountainRoad.CorridorHalf + 1f
                           ? "Edge of the road strip: steer back onto the road" : "Edge of the work site: turn round") + "\n";
        if (AtCliff) w += "Too steep to climb: cut into it with the blade, or go round\n";
        if (dead && !CanDrive) w += "The dozer needs its parts\n";
        return w.TrimEnd('\n');
    }

    /// The lower end of the cutting edge against the bottom of the tracks (metres; minus = cutting into the ground).
    public float EdgeBelowTracks()
    {
        if (blade == null) return 0f;
        Vector3 r = Unfelt(blade.TransformPoint(new Vector3(2.25f, BladeEdge.y, BladeEdge.z)));
        Vector3 l = Unfelt(blade.TransformPoint(new Vector3(-2.25f, BladeEdge.y, BladeEdge.z)));
        return Mathf.Min(r.y, l.y) - transform.position.y;
    }

    // The blade bars, bottom middle: a tall bar for the blade's height (ground line at the tracks, a green tick where
    // blade auto is aiming) and a wide bar for side to side (the middle is level with the world, the marker goes to
    // the low end).  Both markers turn green when the blade is where it should be.
    static readonly Color BarBack = new Color(0f, 0f, 0f, 0.6f), BarLine = new Color(1f, 1f, 1f, 0.5f);
    static readonly Color MarkOn = new Color(0.35f, 0.95f, 0.4f), MarkOff = new Color(1f, 0.8f, 0.2f);
    GUIStyle barText;
    void DrawBladeBars()
    {
        if (blade == null) return;
        if (barText == null) { barText = new GUIStyle(GUI.skin.label) { fontSize = 14, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter }; barText.normal.textColor = Color.white; }
        const float tallH = 150f, tallW = 22f, wideW = 220f, wideH = 18f;
        float baseY = Ui.H - Hud.Margin - 26f;
        float cx = Ui.W * 0.5f;

        // height: top = fully up, bottom = fully down
        float hi = Mathf.Max(0.2f, BladeUpHeight), lo = -Mathf.Max(0.1f, BladeDownDepth);
        float edge = EdgeBelowTracks();
        Rect tall = new Rect(cx + wideW * 0.5f + 40f, baseY - tallH, tallW, tallH);
        System.Func<float, float> yOf = v => tall.yMax - Mathf.InverseLerp(lo, hi, v) * tall.height;
        Ui.Fill(tall, BarBack);
        Ui.Fill(new Rect(tall.x - 6f, yOf(0f) - 1f, tallW + 12f, 2f), BarLine);                     // the ground (bottom of the tracks)
        Ui.Fill(new Rect(tall.x + 1f, yOf(0f), tallW - 2f, tall.yMax - yOf(0f) - 1f), new Color(0.45f, 0.3f, 0.15f, 0.55f));   // below ground
        bool onTarget = false;
        if (HeightActive)
        {
            float want = autoCm / 100f;
            Ui.Fill(new Rect(tall.x - 10f, yOf(want) - 2f, tallW + 20f, 4f), MarkOn);
            onTarget = Mathf.Abs(edge - want) < 0.03f;
        }
        float my = Mathf.Clamp(yOf(edge), tall.y, tall.yMax);
        Ui.Fill(new Rect(tall.x - 3f, my - 4f, tallW + 6f, 8f), onTarget ? MarkOn : MarkOff);
        string ht = edge < -0.01f ? Mathf.RoundToInt(-edge * 100f) + " cm deep" : Mathf.RoundToInt(edge * 100f) + " cm up";
        GUI.Label(new Rect(tall.xMax + 6f, my - 11f, 110f, 22f), ht, barText);
        GUI.Label(new Rect(tall.x - 40f, baseY + 2f, tallW + 80f, 20f), "Height", barText);

        // side to side: the marker goes to the low end
        float gap = EdgeEndsGap();                       // + = right end higher, so the left end is low
        const float range = 0.5f;
        Rect wide = new Rect(cx - wideW * 0.5f, baseY - wideH, wideW, wideH);
        Ui.Fill(wide, BarBack);
        Ui.Fill(new Rect(wide.center.x - 1f, wide.y - 5f, 2f, wideH + 10f), MarkOn);                  // level
        float mx = wide.center.x - Mathf.Clamp(gap / range, -1f, 1f) * wideW * 0.5f;
        bool level = Mathf.Abs(gap) < 0.02f;
        Ui.Fill(new Rect(mx - 4f, wide.y - 3f, 8f, wideH + 6f), level ? MarkOn : MarkOff);
        string lt = level ? "Level" : (gap > 0f ? "Left" : "Right") + " end " + Mathf.RoundToInt(Mathf.Abs(gap) * 100f) + " cm low";
        GUI.Label(new Rect(wide.x, wide.y - 26f, wideW, 22f), lt, barText);
        GUI.Label(new Rect(wide.x, baseY + 2f, wideW, 20f), "Side to side", barText);
    }

    void OnGUI()
    {
        if (!showHelp || !driven || Prologue.Playing) return;
        Ui.Begin();
        DrawBladeBars();
        float below = Hud.TopLeftBottom;
        if (Hud.HelpOn)
        {
            string text = Pad.InUse ?
                "Left stick   drive and steer          Y   get out          Start   upgrades\n" +
                "Right trigger   blade down     Left trigger   blade up     (lower it into the ground to dig)\n" +
                "RB / LB   ripper up / down    (breaks up hard rock)\n" +
                "D-pad   angle / tilt blade    X   straighten    B   lights    Right stick   look round\n" +
                "A   blade auto on / off: " + AutoHelp + "    (holds height, level and straight; while on, the triggers move the height 5 cm a tap: Cut " + MaxCutCm + " cm to Fill " + MaxFillCm + " cm)\n" +
                "GYRO: hold right stick click (or the grip set up for it) and tilt the controller" + (GyroHeld ? "   [GYRO ON]" : "") + "\n" +
                "Back   menu     Left stick click   hide this help" :
                "W / S   drive          A / D   steer          Enter   get out\n" +
                "R / F   blade up / down     (lower it into the ground to dig)\n" +
                "T / G   ripper up / down    (breaks up hard rock)\n" +
                "Q / E   angle blade    Z / C   tilt blade    X   straighten    L   lights    V   blade view\n" +
                "B   blade auto on / off: " + AutoHelp + "    (holds height, level and straight; while on, R / F move the height 5 cm a tap: Cut " + MaxCutCm + " cm to Fill " + MaxFillCm + " cm)\n" +
                "Right mouse drag: look round    Scroll: zoom\n" +
                "U   upgrades     Esc   menu     F5 save   F6 load     F3   debug     F11   fps     H   hide this help";
            below = Hud.HelpBox(text, 560f);
        }
        if (Hud.DebugOn)
        {
            string dbg = "Speed " + (Speed * 3.6f).ToString("F1") + " km/h     " + Mathf.RoundToInt(fps) + " frames a second     Bog " + Bog.ToString("F2");
            dbg += "\nBlade load " + BladeLoadM3.ToString("F2") + " m3   cut rate " + CutRateM3.ToString("F2") + " m3/s   last cut " + LastCut;
            if (world != null)
            {
                float v = VoxelWorld.VoxelVolume;
                dbg += "\nLoose dirt moving " + (world.LoadVoxels * v).ToString("F2") + " m3   (" + world.ClodCount + " clods)";
                dbg += "\nGround " + (world.SolidCount * v).ToString("F3") + " m3 + moving " + (world.LoadVoxels * v).ToString("F3")
                     + " = " + ((world.SolidCount + world.LoadVoxels) * v).ToString("F3");
                dbg += "\nChange since start: " + (((world.SolidCount + world.LoadVoxels) - world.StartTotal) * v).ToString("F3") + " m3";
                string ms = "";
                for (int i = 0; i < 5; i++) ms += VoxelWorld.MsNames[i] + " " + world.MsAvg[i].ToString("F1") + "  ";
                dbg += "\nWork per step (ms): " + ms;
            }
            dbg += "\nBlade angle " + BladeYaw.ToString("F0") + "   tilt " + BladeTilt.ToString("F0") + "   arms " + bladeAngle.ToString("F1");
            Hud.DebugBox(dbg, below);
        }

        // bottom right: over the blade view, how full the blade is, its depth, and the warnings that apply
        string warn = Warnings();
        float warnH = warn.Length == 0 ? 0f : Hud.Warn.CalcHeight(new GUIContent(warn), Hud.RightW - 20f) + 4f;
        float h = 58f + warnH;
        float bottom = Ui.H - Hud.Margin - BladeView.PanelHeight(this) - (BladeView.PanelHeight(this) > 0f ? 6f : 0f);
        Rect r = Hud.RightPanel(bottom, h);
        float x = r.x + 10f, y = r.y + 6f, wdt = r.width - 20f;
        float load = BladeLoadM3 / FullLoad;
        y = Hud.BarLine(x, y, wdt, "Blade", load, BladeLoadM3.ToString("F1") + " of " + FullLoad.ToString("F0") + " m3",
                        Color.Lerp(new Color(0.85f, 0.6f, 0.25f), new Color(1f, 0.35f, 0.2f), Mathf.Clamp01(load - 0.6f) * 2.5f));
        GUI.Label(new Rect(x, y, wdt, 22), DepthLine(), Hud.Small);
        y += 24f;
        if (warnH > 0f) GUI.Label(new Rect(x, y, wdt, warnH), warn, Hud.Warn);
    }
}
