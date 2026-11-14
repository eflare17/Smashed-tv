// Drives the bulldozer, works the blade and ripper, and digs the voxel ground when there is one.
//   W / S or up / down     forward / reverse        A / D or left / right   steer (turns on the spot when stopped)
//   R / F                  blade up / down          T / G                   ripper up / down
//   Q / E                  angle the blade left / right     Z / C           tilt the blade     X   straighten it
// A gamepad's left stick drives too.  The numbers below can be changed on the prefab in the Inspector.
using UnityEngine;

public class DozerController : MonoBehaviour
{
    [Header("Driving")]
    public float maxSpeed = 3.0f;            // metres a second forward (about 11 km/h)
    public float reverseSpeed = 2.5f;
    public float acceleration = 2.5f;
    public float turnSpeed = 38f;            // degrees a second
    [Header("Blade (angle of the lift arms; positive is down)")]
    public float bladeUpAngle = -16f;
    public float bladeDownAngle = 3f;        // about 14 cm below the tracks: a normal cut for one pass
    public float bladeSpeed = 12f;
    public float bladeMaxAngle = 25f;        // how far the blade swings left or right
    public float bladeMaxTilt = 8f;          // how far one end drops
    public float bladeTurnSpeed = 25f;       // degrees a second for angle and tilt
    [Header("Ripper (positive is up)")]
    public float ripperUpAngle = 22f;
    public float ripperDownAngle = -21f;     // tips about 40 cm into the ground
    public float ripperSpeed = 20f;
    [Header("Digging")]
    public float ripRadius = 0.36f;          // how wide each shank tears
    public int hardRockStops = 60;           // this many hard blocks in the blade's way stops the machine
    public bool showHelp = true;
    [Header("Driven by script instead of the keyboard (tests, touch buttons, AI)")]
    public bool useOverride;
    public float overrideThrottle, overrideSteer, overrideBlade, overrideRipper, overrideAngle, overrideTilt;

    public float Speed { get; private set; }             // current speed, + forward, - reverse
    public float BladeHeight01 { get; private set; }     // 0 = down, 1 = fully up
    public float RipperHeight01 { get; private set; }
    public bool BlockedByRock { get; private set; }
    public bool AtFence { get; private set; }            // pushing against the edge of the work site
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

    Transform bladeMount, rearMount, blade, ripper, bladeHinge;
    Vector3 lastBladePos;
    bool haveLastBladePos;
    TrackAnimator trackLeft, trackRight;
    ParticleSystem spray;
    const float HalfTrackGauge = 1.4f;                   // metres from the middle of the machine to each track
    Rigidbody body;
    VoxelWorld world;
    float turn, bladeAngle, ripperAngle, throttleIn, steerIn;
    float yaw, pitch, roll, height, blockedTimer, fps;
    readonly Vector3[] tipsWorld = new Vector3[6];

    void Awake()
    {
        bladeMount = FindDeep(transform, "Mount_BladeLift");
        rearMount = FindDeep(transform, "Mount_Rear");
        blade = FindDeep(transform, "Blade");
        bladeHinge = FindDeep(transform, "Mount_Blade");
        ripper = FindDeep(transform, "Ripper");
        body = GetComponent<Rigidbody>();
        var tl = FindDeep(transform, "Track_Left"); if (tl != null) trackLeft = tl.GetComponent<TrackAnimator>();
        var tr = FindDeep(transform, "Track_Right"); if (tr != null) trackRight = tr.GetComponent<TrackAnimator>();
        yaw = transform.eulerAngles.y;
        height = transform.position.y;
        bladeAngle = Mathf.Lerp(0f, bladeUpAngle, 0.35f);                 // start with the blade just off the ground
        ripperAngle = ripperUpAngle;                                      // and the ripper up
        ApplyAttachments();
    }

    void Start()
    {
        world = VoxelWorld.Instance;
        // (the old "spray" of fake clods is not used any more: the loose dirt is real clods now)
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
        throttleIn = useOverride ? overrideThrottle : Input.GetAxisRaw("Vertical");
        steerIn = useOverride ? overrideSteer : Input.GetAxisRaw("Horizontal");

        float bladeIn = useOverride ? overrideBlade : (Input.GetKey(KeyCode.R) ? 1f : 0f) - (Input.GetKey(KeyCode.F) ? 1f : 0f);
        float ripperIn = useOverride ? overrideRipper : (Input.GetKey(KeyCode.T) ? 1f : 0f) - (Input.GetKey(KeyCode.G) ? 1f : 0f);
        if (bladeIn != 0f) bladeAngle = Mathf.MoveTowards(bladeAngle, bladeIn > 0f ? bladeUpAngle : bladeDownAngle, bladeSpeed * Time.deltaTime);
        if (ripperIn != 0f) ripperAngle = Mathf.MoveTowards(ripperAngle, ripperIn > 0f ? ripperUpAngle : ripperDownAngle, ripperSpeed * Time.deltaTime);
        float angleIn = useOverride ? overrideAngle : (Input.GetKey(KeyCode.E) ? 1f : 0f) - (Input.GetKey(KeyCode.Q) ? 1f : 0f);
        float tiltIn = useOverride ? overrideTilt : (Input.GetKey(KeyCode.C) ? 1f : 0f) - (Input.GetKey(KeyCode.Z) ? 1f : 0f);
        BladeYaw = Mathf.Clamp(BladeYaw + angleIn * bladeTurnSpeed * Time.deltaTime, -bladeMaxAngle, bladeMaxAngle);
        BladeTilt = Mathf.Clamp(BladeTilt + tiltIn * bladeTurnSpeed * 0.5f * Time.deltaTime, -bladeMaxTilt, bladeMaxTilt);
        if (!useOverride && Input.GetKey(KeyCode.X))
        {
            BladeYaw = Mathf.MoveTowards(BladeYaw, 0f, bladeTurnSpeed * 2f * Time.deltaTime);
            BladeTilt = Mathf.MoveTowards(BladeTilt, 0f, bladeTurnSpeed * Time.deltaTime);
        }
        ApplyAttachments();
        fps = Mathf.Lerp(fps, 1f / Mathf.Max(Time.unscaledDeltaTime, 0.0001f), 0.05f);
    }

    void FixedUpdate()
    {
        float dt = Time.fixedDeltaTime;
        float want = throttleIn > 0f ? throttleIn * maxSpeed : throttleIn * reverseSpeed;
        want *= 1f - 0.35f * Mathf.Abs(steerIn);                         // tracks lose a little speed in a turn
        if (blockedTimer > 0f) { blockedTimer -= dt; if (want > 0f) want = 0f; }
        BlockedByRock = blockedTimer > 0f;
        Speed = Mathf.MoveTowards(Speed, want, acceleration * dt);
        turn = Mathf.MoveTowards(turn, steerIn * turnSpeed, turnSpeed * 3f * dt);

        // in a turn the outside track runs faster and the inside one slower (or backwards, turning on the spot)
        float slew = turn * Mathf.Deg2Rad * HalfTrackGauge;
        if (trackLeft != null) trackLeft.speed = Speed + slew;
        if (trackRight != null) trackRight.speed = Speed - slew;

        yaw += turn * dt;
        Quaternion yawRot = Quaternion.Euler(0f, yaw, 0f);
        Vector3 pos = body != null ? body.position : transform.position;
        pos += yawRot * Vector3.forward * (Speed * dt);

        if (world != null)
        {
            // stay on the work site: the ground outside the fence can't be dug
            float lim = VoxelWorld.DriveLimit;
            AtFence = Mathf.Abs(pos.x) > lim || Mathf.Abs(pos.z) > lim;
            pos.x = Mathf.Clamp(pos.x, -lim, lim); pos.z = Mathf.Clamp(pos.z, -lim, lim);
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
            var r = world.BladeSweep(bladeToWorld, BladeBoxMin, BladeBoxMax, travel, Time.fixedDeltaTime);
            world.StepDirt(bladeToWorld, BladePlateMin, BladePlateMax, true, Time.fixedDeltaTime);
            LastCut = r.cut;
            if (r.hard >= hardRockStops && Speed > 0f) { Speed = 0f; blockedTimer = 0.6f; }
            world.Slump(bladeToWorld.MultiplyPoint3x4(new Vector3(0f, 0f, -1.5f)), 9f, 4);
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

    void ApplyAttachments()
    {
        // The blade holds its depth below the tracks even when the machine tips into its own cut:
        // as the nose drops, the arms lift by the matching amount (the blade is further out than the arms are long).
        float held = Mathf.Clamp(bladeAngle - pitch * 1.46f, bladeUpAngle - 8f, bladeDownAngle + 12f);
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
        if (!showHelp) return;
        string text =
            "W / S   drive          A / D   steer\n" +
            "R / F   blade up / down     (lower it into the ground to dig)\n" +
            "T / G   ripper up / down    (breaks up hard rock)\n" +
            "Q / E   angle blade    Z / C   tilt blade    X   straighten\n" +
            "Right mouse drag: look round    Scroll: zoom\n" +
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
        if (BlockedByRock) text += "\nHARD ROCK: back up and rip it first (G)";
        if (AtFence) text += "\nEdge of the work site: turn round";
        int extra = lines + 1 + (BlockedByRock ? 1 : 0) + (AtFence ? 1 : 0);
        GUI.Box(new Rect(10, 10, 470, 104 + 17 * extra), text);
    }
}
