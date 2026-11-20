// Drives the bulldozer, works the blade and ripper, and digs the voxel ground when there is one.
//   W / S or up / down     forward / reverse        A / D or left / right   steer (turns on the spot when stopped)
//   R / F                  blade up / down          T / G                   ripper up / down
//   Q / E                  angle the blade left / right     Z / C           tilt the blade     X   straighten it
//   B                      blade auto: Off / Flat / Cut 5 cm / Cut 10 cm.  The blade holds that depth below the tracks
//                          by itself; pressing blade up or down by hand switches it off.  (Pad: A.)
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
    public float bladeDownAngle = 3f;        // about 14 cm below the tracks: a normal cut for one pass
    public float bladeSpeed = 18f;
    public float bladeMaxAngle = 25f;        // how far the blade swings left or right
    public float bladeMaxTilt = 8f;          // how far one end drops
    public float bladeTurnSpeed = 25f;       // degrees a second for angle and tilt
    [Header("Ripper (positive is up)")]
    public float ripperUpAngle = 22f;
    public float ripperDownAngle = -21f;     // tips about 40 cm into the ground
    public float ripperSpeed = 20f;
    [Header("Digging")]
    public float ripRadius = 0.36f;          // how wide each shank tears
    public int hardRockStops = 85;           // this many hard blocks in the blade's way stops the machine
    public bool showHelp = true;
    [Header("Gyro blade (pad: right stick while the gyro button is held)")]
    public float gyroDeadZone = 0.06f;       // stick movement this small is ignored, so the blade doesn't twitch
    public float gyroSmoothing = 12f;        // how quickly the blade catches up with the stick (higher = snappier)
    [Header("State")]
    // Not saved with the prefab on purpose: Unity kept an old stored "dead" and ignored the value written here.
    [System.NonSerialized] public bool dead = false;     // true = it has sat for years and nothing works until repaired (off for now: F9 switches it)
    [System.NonSerialized] public bool driven;           // someone is in the seat
    // Blade auto: the blade holds its edge at a set depth below the tracks by itself.  Not saved.
    public enum BladeAutoMode { Off, Flat, Cut5, Cut10 }
    [System.NonSerialized] public BladeAutoMode bladeAuto = BladeAutoMode.Off;
    public static readonly string[] BladeAutoNames = { "Off", "Flat", "Cut 5 cm", "Cut 10 cm" };
    static readonly float[] BladeAutoDepth = { 0f, 0f, 0.05f, 0.10f };   // metres below the tracks
    public string BladeAutoName { get { return BladeAutoNames[(int)bladeAuto]; } }
    /// The next setting along: Off, Flat, Cut 5 cm, Cut 10 cm, then Off again.
    public void CycleBladeAuto() { bladeAuto = (BladeAutoMode)(((int)bladeAuto + 1) % BladeAutoNames.Length); }

    // What works.  A working dozer (not dead) can do everything.  A dead one gets each back as its part is fitted.
    public bool CanDrive { get { return !dead || Finds.IsInstalled(0); } }
    public bool CanBlade { get { return !dead || Finds.IsInstalled(1); } }
    public bool CanRip { get { return !dead || Finds.IsInstalled(2); } }
    [Header("Driven by script instead of the keyboard (tests, touch buttons, AI)")]
    public bool useOverride;
    public float overrideThrottle, overrideSteer, overrideBlade, overrideRipper, overrideAngle, overrideTilt;

    public float Speed { get; private set; }             // current speed, + forward, - reverse
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
    static readonly Vector3[] RipperTips =
    {
        new Vector3(-1.5f, -1.15f, -0.56f), new Vector3(0f, -1.15f, -0.56f), new Vector3(1.5f, -1.15f, -0.56f),
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
    readonly Vector3[] tipsWorld = new Vector3[6];
    readonly float[] autoAngle = new float[4];          // the lift-arm angle that puts the blade edge at each auto depth (machine level)
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
        for (int m = 1; m < autoAngle.Length; m++)
        {
            // more angle = lower blade.  Halve the gap until it is close enough.
            float lo = bladeUpAngle, hi = bladeDownAngle + 12f, want = -BladeAutoDepth[m];
            for (int i = 0; i < 30; i++)
            {
                float mid = (lo + hi) * 0.5f;
                if (EdgeHeightAt(mid) > want) lo = mid; else hi = mid;
            }
            autoAngle[m] = (lo + hi) * 0.5f;
        }
        BladeDownDepth = -EdgeHeightAt(bladeDownAngle);
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
        float fixedAngle = autoAngle[(int)bladeAuto];
        if (bladeAuto == BladeAutoMode.Flat || world == null || blade == null || edgePerDegree <= 0f) return fixedAngle;
        Vector3 fwd = transform.forward; fwd.y = 0f;
        if (fwd.sqrMagnitude < 0.01f) return fixedAngle;
        fwd.Normalize();
        Vector3 right = new Vector3(fwd.z, 0f, -fwd.x);
        Vector3 edge = blade.TransformPoint(BladeEdge);
        float sum = 0f; int n = 0;
        for (float a = 1.5f; a <= 3.01f; a += 0.75f)
            for (float s = -1f; s <= 1.01f; s += 1f)
            {
                Vector3 p = edge + fwd * a + right * s;
                float h;
                if (world.FirmHeightAt(p.x, p.z, out h)) { sum += h; n++; }
            }
        if (n < 5) return fixedAngle;
        float want = sum / n - BladeAutoDepth[(int)bladeAuto];
        // more arm angle = lower edge, about edgePerDegree metres a degree
        return Mathf.Clamp(bladeAngle + (edge.y - want) / edgePerDegree, bladeUpAngle, bladeDownAngle);
    }

    public float AutoAngle(BladeAutoMode m) { return autoAngle[(int)m]; }
    public float BladeArmAngle { get { return bladeAngle; } }
    public float BladeDownDepth { get; private set; }    // how far below the tracks the edge goes fully down (for the tests)

    void Start()
    {
        world = VoxelWorld.Instance;
        if (world != null && GetComponent<BladeView>() == null) gameObject.AddComponent<BladeView>();
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
        if (!driven) { throttleIn = steerIn = 0f; ApplyAttachments(); return; }
        throttleIn = useOverride ? overrideThrottle : Stronger(Input.GetAxisRaw("Vertical"), Pad.LeftStick.y);
        steerIn = useOverride ? overrideSteer : Stronger(Input.GetAxisRaw("Horizontal"), Pad.LeftStick.x);
        if (!CanDrive) throttleIn = steerIn = 0f;

        float bladeIn = useOverride ? overrideBlade : (Input.GetKey(KeyCode.R) || Pad.LT > 0.3f ? 1f : 0f) - (Input.GetKey(KeyCode.F) || Pad.RT > 0.3f ? 1f : 0f);
        float ripperIn = useOverride ? overrideRipper : (Input.GetKey(KeyCode.T) || Pad.Held(Pad.B.RB) ? 1f : 0f) - (Input.GetKey(KeyCode.G) || Pad.Held(Pad.B.LB) ? 1f : 0f);
        if (!CanBlade) bladeIn = 0f;
        if (!CanRip) ripperIn = 0f;
        bool treeUp = Upgrades.Instance != null && Upgrades.Instance.Open;
        if (!useOverride && CanBlade && !treeUp && (Input.GetKeyDown(KeyCode.B) || Pad.Down(Pad.B.A))) CycleBladeAuto();
        if (bladeIn != 0f || !CanBlade) bladeAuto = BladeAutoMode.Off;       // a hand on the blade lever takes over
        if (bladeAuto != BladeAutoMode.Off) bladeAngle = Mathf.MoveTowards(bladeAngle, AutoWant(), bladeSpeed * Time.deltaTime);
        if (bladeIn != 0f) bladeAngle = Mathf.MoveTowards(bladeAngle, bladeIn > 0f ? bladeUpAngle : bladeDownAngle, bladeSpeed * Time.deltaTime);
        if (ripperIn != 0f) ripperAngle = Mathf.MoveTowards(ripperAngle, ripperIn > 0f ? ripperUpAngle : ripperDownAngle, ripperSpeed * Time.deltaTime);
        float angleIn = useOverride ? overrideAngle : (Input.GetKey(KeyCode.E) || Pad.DX > 0 ? 1f : 0f) - (Input.GetKey(KeyCode.Q) || Pad.DX < 0 ? 1f : 0f);
        float tiltIn = useOverride ? overrideTilt : (Input.GetKey(KeyCode.C) || Pad.DY < 0 ? 1f : 0f) - (Input.GetKey(KeyCode.Z) || Pad.DY > 0 ? 1f : 0f);
        if (!CanBlade) angleIn = tiltIn = 0f;
        BladeYaw = Mathf.Clamp(BladeYaw + angleIn * bladeTurnSpeed * Time.deltaTime, -bladeMaxAngle, bladeMaxAngle);
        BladeTilt = Mathf.Clamp(BladeTilt + tiltIn * bladeTurnSpeed * 0.5f * Time.deltaTime, -bladeMaxTilt, bladeMaxTilt);
        GyroBlade();
        if (!useOverride && CanBlade && (Input.GetKey(KeyCode.X) || Pad.Held(Pad.B.X)))
        {
            BladeYaw = Mathf.MoveTowards(BladeYaw, 0f, bladeTurnSpeed * 2f * Time.deltaTime);
            BladeTilt = Mathf.MoveTowards(BladeTilt, 0f, bladeTurnSpeed * Time.deltaTime);
        }
        ApplyAttachments();
        if (lights != null && !useOverride && (Input.GetKeyDown(KeyCode.L) || Pad.Down(Pad.B.B))) lights.gameObject.SetActive(!lights.gameObject.activeSelf);
        fps = Mathf.Lerp(fps, 1f / Mathf.Max(Time.unscaledDeltaTime, 0.0001f), 0.05f);
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
            if (world != null && blade != null) world.SetBlade(blade.localToWorldMatrix, BladePlateMin, BladePlateMax, false);
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
            if (SiteProps.Blocks(pos, 2.3f)) { pos = before; Speed = 0f; }
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

        if (world != null) Dig(pos, rot);
        if (spray != null)
        {
            var emission = spray.emission;
            emission.rateOverTime = Speed > 0.3f ? Mathf.Clamp(LastCut * 0.25f, 0f, 140f) : 0f;
        }

        if (body != null) { body.MoveRotation(rot); body.MovePosition(pos); }
        else { transform.SetPositionAndRotation(pos, rot); }
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
            UpdateBog(travel.magnitude);
            if (r.hard >= hardRockStops && Speed > 0f) { Speed = 0f; blockedTimer = 0.6f; }
        }
        if (ripper != null && ripperAngle < 4f)
        {
            Matrix4x4 ripperToWorld = root * ripper.localToWorldMatrix;
            for (int i = 0; i < 3; i++)
            {
                tipsWorld[i] = ripperToWorld.MultiplyPoint3x4(RipperTips[i]);
                tipsWorld[i + 3] = ripperToWorld.MultiplyPoint3x4(RipperTips[i] + new Vector3(0f, 0.3f, -0.15f));   // up the shank
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
        if (bladeAuto != BladeAutoMode.Off) down = 1f;                    // blade auto: always hold the depth
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

    void OnGUI()
    {
        if (!showHelp || !driven) return;
        Ui.Begin();
        string text = Pad.InUse ?
            "Left stick   drive and steer          Y   get out          Start   upgrades\n" +
            "Right trigger   blade down     Left trigger   blade up     (lower it into the ground to dig)\n" +
            "RB / LB   ripper up / down    (breaks up hard rock)\n" +
            "D-pad   angle / tilt blade    X   straighten    B   lights    Right stick   look round\n" +
            "A   blade auto: " + BladeAutoName + "    (Off / Flat / Cut 5 cm / Cut 10 cm; a trigger switches it off)\n" +
            "GYRO: hold right stick click (or the grip set up for it) and tilt the controller" + (GyroHeld ? "   [GYRO ON]" : "") + "\n" :
            "W / S   drive          A / D   steer\n" +
            "R / F   blade up / down     (lower it into the ground to dig)\n" +
            "T / G   ripper up / down    (breaks up hard rock)\n" +
            "Q / E   angle blade    Z / C   tilt blade    X   straighten    L   lights    V   blade view\n" +
            "B   blade auto: " + BladeAutoName + "    (Off / Flat / Cut 5 cm / Cut 10 cm; R / F switches it off)\n" +
            "Right mouse drag: look round    Scroll: zoom\n";
        text +=
            "Speed " + (Speed * 3.6f).ToString("F1") + " km/h     " + Mathf.RoundToInt(fps) + " frames a second";
        int lines = 0;
        if (world != null)
        {
            float v = VoxelWorld.VoxelVolume;
            float carried = world.LoadVoxels * v;
            text += "\nLoose dirt moving " + carried.ToString("F2") + " m3   (" + world.ClodCount + " clods)";
            text += "\nGround " + (world.SolidCount * v).ToString("F3") + " m3 + moving " + (world.LoadVoxels * v).ToString("F3")
                  + " = " + ((world.SolidCount + world.LoadVoxels) * v).ToString("F3");
            text += "\nChange since start: " + (((world.SolidCount + world.LoadVoxels) - world.StartTotal) * v).ToString("F3") + " m3";
            string ms = "";
            for (int i = 0; i < 5; i++) ms += VoxelWorld.MsNames[i] + " " + world.MsAvg[i].ToString("F1") + "  ";
            text += "\nWork per step (ms): " + ms;
            lines = 4;
            if (BladeYaw != 0f || BladeTilt != 0f) { text += "\nBlade angle " + BladeYaw.ToString("F0") + "   tilt " + BladeTilt.ToString("F0"); lines++; }
        }
        if (BlockedByRock) text += "\nHARD ROCK: back up and rip it first (" + Pad.Key("G", "LB") + ")";
        if (AtFence) text += MountainRoad.DistanceTo(transform.position.x, transform.position.z) < MountainRoad.CorridorHalf + 1f
                             ? "\nEdge of the road strip: steer back onto the road" : "\nEdge of the work site: turn round";
        if (AtCliff) text += "\nToo steep to climb: cut into it with the blade, or go round";
        // A swung blade sends its dirt off one end (that is what it is for), so the blade never fills.  Easy to do by
        // accident with the d-pad, so say so.
        bool swung = Mathf.Abs(BladeYaw) > 3f;
        if (swung) text += "\nBLADE SWUNG " + Mathf.Abs(BladeYaw).ToString("F0") + " deg " + (BladeYaw > 0f ? "right" : "left") + ": dirt rolls off one end.  X straightens it";
        int extra = lines + 1 + (BlockedByRock ? 1 : 0) + (AtFence ? 1 : 0) + (AtCliff ? 1 : 0) + (swung ? 1 : 0);
        GUI.Box(new Rect(10, 10, 470, 121 + 17 * extra), text);
    }
}
