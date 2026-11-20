// The Dingo: a small stand-on tracked loader, the first machine that fits in the mine tunnel.  An upgrade
// (Upgrades.cs, Moving dirt, after Shovel 6); until it's bought it sits parked and locked by the mine entrance.
//
//   Enter (pad Y) beside it    get on / off              W / S (left stick)   drive        A / D   turn on the spot
//   R / F (left / right trigger)  arms up / down          Q / E (LB / RB)      curl / tip the bucket
//   L   work lights            V   bucket view
//
// The bucket digs by being driven into the ground: low and flat it scrapes and fills, tipped down (lip low) it dives
// in and bogs, curled back (lip high) it rides up and skims.  Soil, clay and loose rubble go into the bucket; past
// full they spill out ahead of it as clods it pushes along.  Rubble resting on what it digs out falls as clods
// (VoxelWorldBucket.cs), so a cave-in face comes down as you dig its foot.  Solid rock stops the edge with a clank.
// The bucket keeps its angle to the machine as the arms go up (it doesn't spill on the way to the cart), and snaps
// flat as it's lowered to the ground.  Tip it with the arms up to pour (into the cart: while the bucket is up the cart
// catches a little wider); tap tip again to shake out the last clods.  Bump the cart to push it along the rails.
//
// The model is built here from voxels (1/16 m, the dozer's scale and palette), not from a .vox file.
// Driven in FixedUpdate; ground under a roof is found with VoxelWorld.FloorAt, the walls and roof by looking for
// solid voxels round two circles (rounded, so it slides past timbers and corners).  It never tips over: its lean
// is worked out from the ground under the tracks and kept within limits.
using System.Collections.Generic;
using UnityEngine;

[DefaultExecutionOrder(-10)]                                  // before VoxelWorld: its bucket is the plate the clods meet this step
public class Dingo : MonoBehaviour
{
    public static Dingo Instance { get; private set; }
    /// Someone is on it, driving.
    public static bool Working { get { return Instance != null && Instance.Driven; } }

    // ---- the numbers (starting points, to be tuned once it's played)
    public const float BucketLitres = 500f;                   // heaped (2 to 3 loads fill the cart): the big jump over the shovel
    public static int Capacity { get { return Mathf.RoundToInt(BucketLitres / 1000f / VoxelWorld.VoxelVolume); } }
    public float maxSpeed = 1.7f, reverseSpeed = 1.4f, acceleration = 3f, turnSpeed = 75f;
    public float armSpeed = 42f;                              // degrees a second (fixed, full or empty)
    public float bucketSpeed = 70f;
    const float ArmMin = -8f, ArmMax = 70f;                   // arm raise: below 0 the bucket goes under the tracks
    const float BucketMin = -45f, BucketMax = 80f;            // bucket angle to the machine: - curled back, + tipped
    const float PourFrom = 32f;                               // tipped further than this, it pours
    const float MaxCutRate = 900f;                            // voxels a second it can dig before it slows (about 220 L)
    const int HardStop = 45;                                  // this much solid rock in the bucket's way stops it
    const float OverFill = 1.2f;                              // ploughing on when full heaps it up to this much
    const float CatchWider = 0.12f;                           // with the bucket up, how much wider the cart catches

    [System.NonSerialized] public bool owned;
    public bool Driven { get; private set; }
    [Header("Driven by script (tests, recordings)")]
    public bool useOverride;
    public float overrideThrottle, overrideSteer, overrideArms, overrideBucket;

    public float Speed { get; private set; }
    public float ArmRaise { get; private set; }
    public float BucketAngle { get; private set; }            // to the machine; + is tipped (lip down)
    public float Bog { get; private set; } = 1f;              // share of full speed left (1 = free)
    public float CutRate { get; private set; }                // voxels a second it is digging
    public bool HitRock { get; private set; }                 // the edge stopped on solid rock just now
    public int RockHits { get; private set; }
    public float Fill01 { get { return world == null ? 0f : Mathf.Clamp01(world.BucketVoxels / (float)Capacity); } }
    public float Fill { get { return world == null ? 0f : world.BucketVoxels / (float)Capacity; } }   // over 1 when heaped past full
    public int BumpSpills { get; private set; }
    public float Litres { get { return world == null ? 0f : world.BucketVoxels * VoxelWorld.VoxelVolume * 1000f; } }
    public bool Pouring { get; private set; }
    public float BoardSeconds { get; private set; }           // how long the last step on took (tests)
    public int CartPushes { get; private set; }               // physics steps it moved the cart
    public float CartPushed { get; private set; }             // metres it has moved the cart, all told
    public bool Blocked { get; private set; }                 // the last step was held up by a wall, prop or the cart
    public string LastBlock { get; private set; } = "";
    /// How much of the body is inside something where it stands (tests): 0 = free.
    public int OverlapNow { get { return Overlap(transform.position, transform.eulerAngles.y, true); } }

    VoxelWorld world;
    Rigidbody body;
    Transform armMount, bucketMount, bucket, driverPivot, cleatsL, cleatsR, lights, loadHeap;
    Material paint;
    float lastPitch, lastRoll;
    float yaw, pitch, roll, height, turn, throttleIn, steerIn, armIn, bucketIn, trackRunL, trackRunR;
    bool tapTip;
    float hardTimer, boardT = 1f, shakeT, jiggleT, offAtSec;
    Vector3 lastLip; bool haveLip;
    float camExtra, camBase = -1f;

    // where things are, in the machine's own space (metres; +z forward, y up from the bottom of the tracks)
    static readonly Vector3 ArmPivot = new Vector3(0f, 1.22f, -0.32f);
    static readonly Vector3 ArmToHinge = new Vector3(0f, -0.92f, 1.12f);    // with the arms down (raise 0)
    // the bucket, in its own space (origin at its hinge, +z out of the mouth)
    // The bucket: 1.2 m wide inside, its floor 0.32 m under the hinge, the lip 0.70 m out, the back 0.56 m tall, the sides
    // sloping down to 0.28 m at the lip.  About 360 L to the rim; heaped, it carries BucketLitres.
    const float BW = 0.58f, BLip = 0.70f, BFloor = -0.32f, BBack = 0.24f, BSideLip = -0.04f;
    static readonly Vector3 CutMin = new Vector3(-BW, BFloor + 0.02f, 0.02f), CutMax = new Vector3(BW, 0.10f, BLip + 0.02f);
    static readonly Vector3 CatchMin = new Vector3(-BW, BFloor + 0.01f, -0.02f), CatchMax = new Vector3(BW, BBack + 0.12f, BLip - 0.03f);
    static readonly Vector3 PlateMin = new Vector3(-BW - 0.04f, BFloor, -0.06f), PlateMax = new Vector3(BW + 0.04f, BBack, BLip);
    // the body, for bumping into things: two circles (rounded ends)
    static readonly float[] CircleZ = { 0.15f, -0.55f };
    static readonly float[] CircleR = { 0.52f, 0.45f };
    static readonly float[] WallHeights = { 0.45f, 0.95f, 1.45f };
    static readonly Vector3[] TrackPts = { new Vector3(-0.39f, 0f, 0.45f), new Vector3(0.39f, 0f, 0.45f), new Vector3(-0.39f, 0f, -0.45f), new Vector3(0.39f, 0f, -0.45f) };
    // the timber props in the tunnel's open stretches (as SiteProps.MineEntrance places them), metres in from the mouth
    static readonly float[] PropsAlong = { 8.2f, 11.6f, 20.0f, 22.2f, 28.6f, 30.4f };
    // the cart's tub (MineCart's HalfWidth, HalfLength, TubTop)
    const float CartHalfW = 0.55f, CartHalfL = 0.85f, CartTop = 1.1f;

    void Awake()
    {
        Instance = this;
        BuildModel();
        body = gameObject.AddComponent<Rigidbody>();
        body.isKinematic = true;
        body.interpolation = RigidbodyInterpolation.Interpolate;
        ApplyParts();
    }

    void OnDestroy() { if (Instance == this) Instance = null; }

    void Start()
    {
        world = VoxelWorld.Instance;
        if (Upgrades.Instance != null) owned = Upgrades.Instance.HasDingo;
        Park();
    }

    /// Parks it by the mine entrance, on a free bit of ground.
    public void Park()
    {
        if (world == null) world = VoxelWorld.Instance;
        Vector3 want = new Vector3(VoxelWorld.PortalX - 3.6f, 0f, VoxelWorld.PortalZ - 3.2f);
        Vector3 at = want;
        float bestD = 1e9f;
        for (int ring = 0; ring < 8 && bestD > 1e8f; ring++)
            for (int k = 0; k < 12; k++)
            {
                Vector3 p = want + Quaternion.Euler(0f, k * 30f, 0f) * Vector3.forward * (ring * 0.8f);
                if (world != null) p.y = world.FloorAt(p + Vector3.up * 1f);
                bool free = true;
                for (int yv = 0; yv < 360 && free; yv += 30) free = Overlap(p, yv, false) == 0;   // room to turn round there
                if (free) { at = p; bestD = ring; break; }
            }
        Place(at, 20f);
    }

    /// Puts it at a spot, facing yawDeg, still.  (Tests.)
    public void Place(Vector3 p, float yawDeg)
    {
        if (world == null) world = VoxelWorld.Instance;
        yaw = yawDeg; pitch = roll = 0f; Speed = 0f; turn = 0f; haveLip = false;
        if (world != null) p.y = world.FloorAt(p + Vector3.up * 0.8f);
        height = p.y;
        Quaternion r = Quaternion.Euler(0f, yaw, 0f);
        transform.SetPositionAndRotation(p, r);
        if (body != null) { body.position = p; body.rotation = r; }
    }

    public void SetOwned(bool on)
    {
        owned = on;
        if (!on && Driven) GetOff();
    }

    // ---------------------------------------------------------------- getting on and off
    /// Enter / Y from the worker: gets on or off the Dingo if he is at it (true), else leaves it to the dozer (false).
    public static bool TryBoard(Worker wk)
    {
        var d = Instance;
        if (d == null || wk == null || wk.InDozer || wk.RidingCart) return false;
        if (d.Driven) { d.GetOff(); return true; }
        if (!d.Near(wk.transform.position)) return false;
        if (!d.owned) { wk.Say("The Dingo isn't yours yet.  Buy it in the upgrades (" + Pad.Key("U", "Start") + "): Moving dirt, after Shovel 6.", 4f); return true; }
        d.Board(wk);
        return true;
    }

    public bool Near(Vector3 p) { Vector3 d = p - transform.position; d.y = 0f; return d.magnitude < 2.3f; }

    public void Board(Worker wk)
    {
        if (wk == null || !owned) return;
        wk.OnMachine(true, Vector3.zero, 0f);
        Driven = true;
        boardT = 0f;                                          // the step on: a squat and a clunk, 0.35 s
        BoardSeconds = 0.35f;
        Sound("clunk", transform.position + Vector3.up * 0.3f, 0.55f, 1.35f);   // the hydraulic clunk as he steps on
        if (lights != null) lights.gameObject.SetActive(true);
        var cam = Camera.main != null ? Camera.main.GetComponent<FollowCamera>() : null;
        if (cam != null) { cam.Follow(transform, 6.5f, 2.5f, 22f, 1.1f, 20f, 18f); cam.turnFollow = 2.5f; camBase = cam.lookHeight; camExtra = 0f; }
        haveLip = false;
        Worker.Instance.Say("On the Dingo.  W/S drive, A/D turn, R/F arms, Q/E bucket, V bucket view.", 4f);
    }

    public void GetOff()
    {
        if (!Driven) return;
        Driven = false;
        Speed = 0f; turn = 0f; Pouring = false;
        throttleIn = steerIn = armIn = bucketIn = 0f;
        Sound("clunk", transform.position + Vector3.up * 0.3f, 0.35f, 1.5f);
        var wk = Worker.Instance;
        if (wk == null) return;
        // step off to the left, else the right, else behind
        Vector3[] tries = { -transform.right * 1.0f, transform.right * 1.0f, -transform.forward * 1.45f, transform.forward * 1.9f };
        Vector3 at = transform.position + tries[0];
        foreach (var t in tries)
        {
            Vector3 p = transform.position + t;
            if (world == null || (world.MaterialAt(p + Vector3.up * 1.0f) == VoxelWorld.Air && world.MaterialAt(p + Vector3.up * 1.6f) == VoxelWorld.Air)) { at = p; break; }
        }
        wk.OnMachine(false, at, yaw);
    }

    // ---------------------------------------------------------------- controls
    MeshRenderer[] renderers;
    void Update()
    {
        if (renderers == null) renderers = GetComponentsInChildren<MeshRenderer>(true);
        bool show = !Prologue.Playing;                        // (not in the prologue: it isn't there yet)
        if (renderers.Length > 0 && renderers[0].enabled != show) foreach (var r in renderers) r.enabled = show;
        if (boardT < 1f) boardT += Time.deltaTime / 0.35f;
        if (!Driven)
        {
            throttleIn = steerIn = armIn = bucketIn = 0f;
            ApplyParts();
            UpdateSound(Time.deltaTime);
            return;
        }
        bool menu = (Upgrades.Instance != null && Upgrades.Instance.Open) || PauseMenu.Blocking;
        if (useOverride)
        {
            throttleIn = overrideThrottle; steerIn = overrideSteer; armIn = overrideArms; bucketIn = overrideBucket;
        }
        else if (menu) { throttleIn = steerIn = armIn = bucketIn = 0f; }
        else
        {
            throttleIn = Stronger(Input.GetAxisRaw("Vertical"), Pad.LeftStick.y);
            steerIn = Stronger(Input.GetAxisRaw("Horizontal"), Pad.LeftStick.x);
            armIn = (Input.GetKey(KeyCode.R) || Pad.LT > 0.3f ? 1f : 0f) - (Input.GetKey(KeyCode.F) || Pad.RT > 0.3f ? 1f : 0f);
            bucketIn = (Input.GetKey(KeyCode.E) || Pad.Held(Pad.B.RB) ? 1f : 0f) - (Input.GetKey(KeyCode.Q) || Pad.Held(Pad.B.LB) ? 1f : 0f);
            if (Input.GetKeyDown(KeyCode.E) || Pad.Down(Pad.B.RB)) TapTip();
            if (Input.GetKeyDown(KeyCode.L) || Pad.Down(Pad.B.B)) { if (lights != null) lights.gameObject.SetActive(!lights.gameObject.activeSelf); }
            if (Input.GetKeyDown(KeyCode.V)) showView = !showView;
        }
        float dt = Time.deltaTime;
        float armWas = ArmRaise, bucketWas = BucketAngle;
        if (armIn != 0f) ArmRaise = Mathf.Clamp(ArmRaise + armIn * armSpeed * dt, ArmMin, ArmMax);
        if (bucketIn != 0f) BucketAngle = Mathf.Clamp(BucketAngle + bucketIn * bucketSpeed * dt, BucketMin, BucketMax);
        // a clunk as a ram runs into its end stop
        bool armStop = armIn != 0f && ArmRaise != armWas && (ArmRaise == ArmMin || ArmRaise == ArmMax);
        bool bucketStop = bucketIn != 0f && BucketAngle != bucketWas && (BucketAngle == BucketMin || BucketAngle == BucketMax);
        if (armStop || bucketStop) { EndStops++; Sound("clunk", bucketMount.position, 0.45f, 1.25f + 0.1f * Random.value); }
        // auto-level, a soft assist: lowered near the ground (and Q / E not held) the bucket settles flat.  Q / E always wins.
        if (bucketIn != 0f) { }
        else if (armIn < 0f && ArmRaise < 6f && Mathf.Abs(BucketAngle) < 14f) BucketAngle = Mathf.MoveTowards(BucketAngle, 0f, 90f * dt);
        // the arms can't push the bucket up through the roof
        if (ArmRaise > armWas && world != null && BucketTopHits()) ArmRaise = armWas;
        ApplyParts();
        UpdateSound(dt);
        UpdateCamera(dt);
    }

    /// Tip pressed while the bucket is already tipped: a shake that throws out the last clods.
    public void TapTip() { if (BucketAngle > PourFrom + 10f) tapTip = true; }

    static float Stronger(float a, float b) { return Mathf.Abs(b) > Mathf.Abs(a) ? b : a; }

    bool BucketTopHits()
    {
        for (int i = -1; i <= 1; i++)
        {
            Vector3 p = bucket.TransformPoint(new Vector3(i * (BW - 0.06f), BBack + 0.04f, 0.1f));
            if (world.MaterialAt(p + Vector3.up * 0.06f) != VoxelWorld.Air) return true;
            Vector3 q = bucket.TransformPoint(new Vector3(i * (BW - 0.06f), BSideLip - 0.06f, BLip));
            if (world.MaterialAt(q + Vector3.up * 0.1f) != VoxelWorld.Air && world.MaterialAt(q + Vector3.up * 0.1f) <= VoxelWorld.Gold && q.y > transform.position.y + 1.2f) return true;
        }
        return false;
    }

    // ---------------------------------------------------------------- the camera: follows; pulls back reversing, rises with the bucket
    void UpdateCamera(float dt)
    {
        var camGo = Camera.main;
        if (camGo == null) return;
        var cam = camGo.GetComponent<FollowCamera>();
        if (cam == null || cam.target != transform) return;
        if (camBase < 0f) camBase = cam.lookHeight;
        float up01 = Mathf.InverseLerp(0f, ArmMax, ArmRaise);
        // only a small rise, so the cutting edge and the tunnel roof stay in sight
        cam.lookHeight = Mathf.Lerp(cam.lookHeight, camBase + 0.35f * up01, 1f - Mathf.Exp(-3f * dt));
        float wantExtra = Speed < -0.15f ? 1.0f : 0f;
        float next = Mathf.MoveTowards(camExtra, wantExtra, 1.4f * dt);
        cam.distance += next - camExtra;
        camExtra = next;
        if (shakeT > 0f) { shakeT -= dt; FollowCamera.Shake = Mathf.Max(FollowCamera.Shake, 0.05f * Mathf.Clamp01(shakeT / 0.18f)); }
        else if (Bog < 0.7f && Speed > 0.05f) FollowCamera.Shake = Mathf.Max(FollowCamera.Shake, 0.006f * (1f - Bog));   // labouring
    }

    // ---------------------------------------------------------------- driving and digging
    void FixedUpdate()
    {
        if (world == null) { world = VoxelWorld.Instance; if (world == null) return; }
        float dt = Time.fixedDeltaTime;
        if (!Driven)
        {
            Speed = 0f; turn = 0f; Bog = 1f; CutRate = 0f;
            return;
        }
        // ---- speed and turning
        float want = throttleIn > 0f ? throttleIn * maxSpeed : throttleIn * reverseSpeed;
        float wantFree = want;
        if (want > 0f) want *= Bog;
        if (hardTimer > 0f) { hardTimer -= dt; if (want > 0f) want = 0f; }
        Speed = Mathf.MoveTowards(Speed, want, acceleration * dt);
        turn = Mathf.MoveTowards(turn, steerIn * turnSpeed * (Mathf.Abs(throttleIn) > 0.1f ? 0.7f : 1f), turnSpeed * 4f * dt);

        Vector3 before = body.position;
        float yawBefore = yaw;
        Vector3 fwd = Quaternion.Euler(0f, yaw, 0f) * Vector3.forward;
        Vector3 move = fwd * (Speed * dt);
        Blocked = false;

        // turn on the spot, if the body fits turned
        float newYaw = yaw + turn * dt;
        Vector3 fwdNow = fwd, rightNow = new Vector3(fwd.z, 0f, -fwd.x);
        if (Mathf.Abs(turn) > 0.01f)
        {
            int was = Overlap(before, yaw, true), now = Overlap(before, newYaw, true);
            if (now > was)
            {
                // a corner caught: shuffle a few centimetres (as the tracks would) and turn from there, if that fits
                bool done = false;
                foreach (Vector3 nudge in new[] { fwdNow * 0.03f, -fwdNow * 0.03f, rightNow * 0.03f, -rightNow * 0.03f })
                    if (Overlap(before + nudge, newYaw, true) <= was) { before += nudge; done = true; break; }
                if (!done) { newYaw = yaw; turn = 0f; Blocked = true; LastBlock = "turn"; }
            }
        }
        yaw = newYaw;

        // ---- the move: slide along whatever is in the way, push the cart if it's what we bumped
        Vector3 pos = before;
        if (move.sqrMagnitude > 1e-10f)
        {
            Vector3 got = TryMove(before, move);
            pos = got;
            if ((got - before).magnitude < move.magnitude * 0.5f) { Blocked = true; Speed *= 0.5f; }
        }

        // ---- sit on the ground under the tracks, and lean with it (never more than it could take without tipping)
        Quaternion yawRot = Quaternion.Euler(0f, yaw, 0f);
        float fl = 0f, fr = 0f, rl = 0f, rr = 0f;
        float[] h = new float[4];
        for (int i = 0; i < 4; i++)
        {
            Vector3 p = pos + yawRot * TrackPts[i];
            h[i] = world.FloorAt(new Vector3(p.x, height + 0.4f, p.z));
        }
        fl = h[0]; fr = h[1]; rl = h[2]; rr = h[3];
        // a track point over a hole far below (the edge of a dug trench) doesn't drag the machine down into it
        float top = Mathf.Max(Mathf.Max(fl, fr), Mathf.Max(rl, rr));
        for (int i = 0; i < 4; i++) h[i] = Mathf.Max(h[i], top - 0.45f);
        float avg = (h[0] + h[1] + h[2] + h[3]) / 4f;
        float k = 1f - Mathf.Exp(-12f * dt);
        height = Mathf.Lerp(height, avg, k);
        float wantPitch = Mathf.Clamp(Mathf.Atan2(((h[2] + h[3]) - (h[0] + h[1])) * 0.5f, 0.9f) * Mathf.Rad2Deg, -22f, 22f);
        float wantRoll = Mathf.Clamp(Mathf.Atan2(((h[1] + h[3]) - (h[0] + h[2])) * 0.5f, 0.78f) * Mathf.Rad2Deg, -16f, 16f);
        pitch = Mathf.Lerp(pitch, wantPitch, k);
        roll = Mathf.Lerp(roll, wantRoll, k);
        // the squat as he steps on: the back end dips
        float squat = boardT < 1f ? Mathf.Sin(boardT * Mathf.PI) : 0f;
        pos.y = height - 0.02f * squat;
        Quaternion rot = yawRot * Quaternion.Euler(pitch - 2.5f * squat, 0f, roll);

        // ---- the bucket
        Matrix4x4 root = Matrix4x4.TRS(pos, rot, Vector3.one) * transform.worldToLocalMatrix;
        Matrix4x4 b2w = root * bucket.localToWorldMatrix;
        world.BucketMouth = b2w.MultiplyPoint3x4(new Vector3(0f, 0f, BLip + 0.3f));
        Vector3 lip = b2w.MultiplyPoint3x4(new Vector3(0f, BFloor + 0.1f, BLip - 0.1f));
        Vector3 travel = haveLip ? lip - lastLip : Vector3.zero;
        lastLip = lip; haveLip = true;
        HitRock = false;
        bool digging = BucketAngle < PourFrom;
        int cutNow = 0;
        if (digging)
        {
            // full and still ploughing on, the heap in front rides up into the bucket: it ends up badly overfilled
            bool ploughing = Speed > 0.1f && Bog < 0.95f && world.BucketVoxels >= Capacity - VoxelWorld.ClodVoxels;
            world.BucketCollect(b2w.inverse, CatchMin, CatchMax, ploughing ? Mathf.RoundToInt(Capacity * OverFill) : Capacity);
            if (travel.sqrMagnitude > 0.0008f * 0.0008f)
            {
                var r = world.BucketCut(b2w, CutMin, CutMax, Capacity - world.BucketVoxels, travel / dt);
                cutNow = r.took + r.spilled;
                // firm ground and full-bucket ploughing are harder work than loose rubble
                float effort = r.took + r.spilled * 1.6f + r.firm * 1.5f;
                CutRate = Mathf.Lerp(CutRate, effort / dt, 1f - Mathf.Exp(-8f * dt));
                if (r.hard >= HardStop && Vector3.Dot(travel, fwd) > 0f)
                {
                    // the edge stops on rock: clank, sparks, a jolt and a little recoil
                    HitRock = true; RockHits++;
                    pos = new Vector3(before.x, pos.y, before.z);
                    Speed = -0.45f; hardTimer = 0.5f; shakeT = 0.18f;
                    Sound("clunk", lip, 1f, 1.6f + 0.2f * Random.value);   // steel on rock
                    JackFX.Blow(lip + fwd * 0.12f, -fwd, VoxelWorld.Rock, 1f, true);
                    ArmRaise = Mathf.Min(ArmMax, ArmRaise + 1.5f);
                    haveLip = false;
                }
                else if (r.hard >= HardStop / 2 && travel.y < -0.0005f)
                    ArmRaise = Mathf.Min(ArmMax, ArmRaise + Mathf.Abs(travel.y) / 0.02f);   // lowering onto rock: it stops there
            }
            else CutRate = Mathf.Lerp(CutRate, 0f, 1f - Mathf.Exp(-8f * dt));
            // the angle of attack, while it is pushing into the ground with the bucket low:
            //   flat, it skims along the surface;  tipped a little (lip down), it pulls itself in to a cut about 1 cm
            //   deeper for each degree;  tipped steeply it dives as deep as it goes and bogs;  curled back, it rides up
            if (cutNow > 0 && Speed > 0.1f && armIn == 0f && ArmRaise < 12f)
            {
                float attack = Mathf.Abs(BucketAngle) < 3f ? 0f : Mathf.Clamp(BucketAngle, -15f, 30f);
                float wantRaise = Mathf.Clamp(-attack * 0.01f / 0.0195f, ArmMin, 12f);         // (the lip drops about 2 cm a degree of arm)
                ArmRaise = Mathf.MoveTowards(ArmRaise, wantRaise, 9f * Speed * dt);
            }
            world.SetBlade(b2w, PlateMin, PlateMax, travel.sqrMagnitude > 1e-8f);
        }
        else
        {
            CutRate = Mathf.Lerp(CutRate, 0f, 1f - Mathf.Exp(-8f * dt));
            world.SetBlade(b2w, PlateMin, new Vector3(PlateMax.x, PlateMax.y, -0.02f), false);   // tipped: only its back is solid
        }
        world.SlumpCentre = lip;
        float target = CutRate > MaxCutRate ? Mathf.Max(0.22f, MaxCutRate / CutRate) : 1f;
        Bog = Mathf.MoveTowards(Bog, target, (target < Bog ? 2f : 0.9f) * dt);

        // ---- heaped well above the rim, a bump shakes a few clods off the top (a normally full bucket never loses any)
        float bump = (Mathf.Abs(pitch - lastPitch) + Mathf.Abs(roll - lastRoll)) / dt;
        lastPitch = pitch; lastRoll = roll;
        if (digging && Fill > 1.08f && bump > 10f && Random.value < Mathf.Clamp01(bump / 40f))
        {
            float side = Random.value < 0.5f ? -1f : 1f;
            Vector3 at = b2w.MultiplyPoint3x4(new Vector3(side * (BW + 0.12f), BBack + 0.22f, Random.Range(0.1f, BLip - 0.1f)));
            if (world.BucketPour(at, b2w.MultiplyVector(new Vector3(side * 0.8f, 0.3f, 0f)) + fwd * Speed)) BumpSpills++;
        }

        // ---- pouring
        Pouring = false;
        if (BucketAngle > PourFrom && world.BucketVoxels > 0)
        {
            float tip01 = Mathf.InverseLerp(PourFrom, BucketMax, BucketAngle);
            // a full bucket pours freely; the last few clods cling until it is shaken
            float stick = Mathf.Lerp(0.35f, 1f, Fill01);
            pourAcc += (1f + 5f * tip01) * stick;
            int n = Mathf.FloorToInt(pourAcc);
            pourAcc -= n;
            if (tapTip) { n += 8; jiggleT = 0.25f; }
            Vector3 vel = b2w.MultiplyVector(new Vector3(0f, 0f, 1f)) * 0.7f + fwd * Speed;
            for (int i = 0; i < n; i++)
            {
                Vector3 at = b2w.MultiplyPoint3x4(new Vector3(Random.Range(-BW + 0.1f, BW - 0.1f), BFloor + 0.12f + Random.Range(0f, 0.1f), BLip + 0.08f));
                if (!world.BucketPour(at, vel + Random.insideUnitSphere * 0.25f)) break;
                Pouring = true;
            }
        }
        tapTip = false;
        // while the bucket is up, the cart catches a little wider: 12 cm past its sides and ends, no higher than its rim
        // (clods that fall wider than that land on the ground, as they should)
        var cart = MineCart.Instance;
        if (cart != null && ArmRaise > 25f && cart.Near(pos, 3.5f) && !cart.Tipping)
            world.CartCollect(cart.transform.worldToLocalMatrix, new Vector3(-CartHalfW - CatchWider, 0.3f, -CartHalfL - CatchWider), new Vector3(CartHalfW + CatchWider, CartTop + 0.05f, CartHalfL + CatchWider), cart.capacity);

        // ---- tracks: they run a little faster than it goes when it bogs (they slip)
        float slew = turn * Mathf.Deg2Rad * 0.39f;
        float run = Speed > 0f && wantFree > Speed ? Mathf.Lerp(Speed, wantFree, Mathf.Clamp01((1f - Bog) * 1.3f)) : Speed;
        trackRunL += (run + slew) * dt; trackRunR += (run - slew) * dt;

        body.MoveRotation(rot);
        body.MovePosition(pos);
    }
    float pourAcc;

    /// Moves from `from` by `move` as far as it can: straight, else slid along the obstacle, pushing the cart if that's it.
    Vector3 TryMove(Vector3 from, Vector3 move)
    {
        int was = Overlap(from, yaw, true);
        Vector3 to = from + move;
        if (PushCart(from, ref to)) return to;
        int now = Overlap(to, yaw, true);
        if (now == 0 || now < was || (was > 0 && now == was)) return to;
        // slide: try the move turned a little either way, shortened by how far it turns
        foreach (float a in new[] { 25f, -25f, 50f, -50f, 75f, -75f })
        {
            Vector3 m = Quaternion.Euler(0f, a, 0f) * move * Mathf.Cos(a * Mathf.Deg2Rad);
            Vector3 p = from + m;
            int o = Overlap(p, yaw, true);
            if (o == 0 || o < was || (was > 0 && o == was)) return p;
        }
        return from;
    }

    /// If this step runs the machine (or its lowered bucket) into the cart, push the cart along its rails.  True if it
    /// dealt with the cart (to is then where the machine ends up).
    bool PushCart(Vector3 from, ref Vector3 to)
    {
        var cart = MineCart.Instance;
        if (cart == null || !CartHit(to, cart)) return false;
        Vector3 move = to - from;
        Vector3 toCart = cart.transform.position - from; toCart.y = 0f;
        if (Vector3.Dot(move, toCart) <= 0f) return false;          // backing away from it: never pulls it along
        Vector3 rail = cart.transform.forward; rail.y = 0f; rail.Normalize();
        float along = Vector3.Dot(move, rail);
        if (Mathf.Abs(along) < move.magnitude * 0.5f) { to = from; LastBlock = "cart side"; return true; }
        float went = cart.Roll(along);
        if (Mathf.Abs(went) > 1e-5f) { CartPushes++; CartPushed += Mathf.Abs(went); }
        to = from + rail * went;
        if (CartHit(to, cart) && CartHit(from, cart) == false) { to = from; LastBlock = "cart stuck"; }
        if (Mathf.Abs(went) < 1e-5f) LastBlock = "cart stuck";
        return true;
    }

    bool CartHit(Vector3 p, MineCart cart)
    {
        Quaternion r = Quaternion.Euler(0f, yaw, 0f);
        Matrix4x4 w2c = cart.transform.worldToLocalMatrix;
        for (int i = 0; i < 2; i++)
            if (CircleBox(w2c.MultiplyPoint3x4(p + r * new Vector3(0f, 0f, CircleZ[i])), CircleR[i], CartHalfW + 0.04f, CartHalfL + 0.06f)) return true;
        // the bucket, unless it is up over the tub
        if (bucket != null)
        {
            Vector3 c = p + r * (BucketOffset() + new Vector3(0f, 0f, 0.36f));
            float bottom = p.y + BucketOffset().y - 0.32f;
            if (bottom < cart.transform.position.y + CartTop + 0.05f && CircleBox(w2c.MultiplyPoint3x4(c), 0.62f, CartHalfW + 0.04f, CartHalfL + 0.06f)) return true;
        }
        return false;
    }

    static bool CircleBox(Vector3 local, float r, float hx, float hz)
    {
        float dx = Mathf.Max(0f, Mathf.Abs(local.x) - hx), dz = Mathf.Max(0f, Mathf.Abs(local.z) - hz);
        return dx * dx + dz * dz < r * r;
    }

    /// Where the bucket's hinge is, in the machine's space (level machine), for the arms as they are.
    Vector3 BucketOffset() { return ArmPivot + Quaternion.Euler(-ArmRaise, 0f, 0f) * ArmToHinge; }

    /// How much of the body would be inside something at p, facing yawDeg: solid voxels round its two circles at
    /// knee, waist and head height, the scenery (posts, logs, trees) and the tunnel's timber props.  0 = free.
    /// `withCart`: the cart is left to PushCart.
    /// What Overlap is finding, in words (tests).
    public string OverlapWhy(float yawDeg)
    {
        why = ""; int n = Overlap(transform.position, yawDeg, true); string s = why; why = null; return n + ":" + s;
    }
    string why;

    int Overlap(Vector3 p, float yawDeg, bool driving)
    {
        if (world == null) return 0;
        Quaternion r = Quaternion.Euler(0f, yawDeg, 0f);
        int n = 0;
        float baseY = driving ? height : p.y;
        for (int c = 0; c < 2; c++)
        {
            Vector3 centre = p + r * new Vector3(0f, 0f, CircleZ[c]);
            if (SiteProps.Blocks(new Vector3(centre.x, baseY + 0.3f, centre.z), CircleR[c] - 0.05f, true)) { n += 4; if (why != null) why += " scenery" + c; }
            if (InProp(centre, CircleR[c])) { n += 4; if (why != null) why += " prop" + c; }
            for (int a = 0; a < 12; a++)
            {
                Vector3 off = Quaternion.Euler(0f, a * 30f, 0f) * Vector3.forward * CircleR[c];
                for (int hgt = 0; hgt < WallHeights.Length; hgt++)
                {
                    Vector3 q = new Vector3(centre.x + off.x, baseY + WallHeights[hgt], centre.z + off.z);
                    if (world.MaterialAt(q) != VoxelWorld.Air) { n++; if (why != null) why += " v" + c + "/" + a + "/" + hgt + "=" + world.MaterialAt(q); }
                }
            }
        }
        // the dump: the hopper and the buffer stop at the end of the rails are solid
        if (SiteProps.HopperToWorld.m33 != 0f)
        {
            Matrix4x4 w2h = SiteProps.HopperToWorld.inverse;
            var hh = SiteProps.HopperHalf;
            for (int c = 0; c < 2; c++)
                if (CircleBox(w2h.MultiplyPoint3x4(p + r * new Vector3(0f, 0f, CircleZ[c])), CircleR[c], hh.x + 0.15f, hh.z + 0.15f)) { n += 6; if (why != null) why += " hopper"; }
        }
        var rails = SiteProps.RailPath;
        if (rails.Count > 1)
        {
            Vector3 end = rails[rails.Count - 1];
            for (int c = 0; c < 2; c++)
            {
                Vector3 cc = p + r * new Vector3(0f, 0f, CircleZ[c]);
                if (new Vector2(cc.x - end.x, cc.z - end.z).magnitude < CircleR[c] + 0.9f) { n += 6; if (why != null) why += " bufferstop"; }
            }
        }
        // the edge of the work site
        float lim = VoxelWorld.DriveLimit;
        if (Mathf.Abs(p.x) > lim || Mathf.Abs(p.z) > lim) n += 10;
        return n;
    }

    static bool InProp(Vector3 c, float r)
    {
        float along = c.z - VoxelWorld.PortalZ;
        if (along < 0f || along > VoxelWorld.TunnelLength + 1f || Mathf.Abs(c.x - VoxelWorld.PortalX) > 4f) return false;
        foreach (float a in PropsAlong)
        {
            if (Mathf.Abs(along - a) > r + 0.2f) continue;
            float w = VoxelWorld.TunnelHalfWidthAt(a) + 0.25f;
            for (int s = -1; s <= 1; s += 2)
            {
                Vector2 post = new Vector2(VoxelWorld.PortalX + s * (w - 0.3f), VoxelWorld.PortalZ + a);
                if ((new Vector2(c.x, c.z) - post).sqrMagnitude < (r + 0.13f) * (r + 0.13f)) return true;
            }
        }
        return false;
    }

    // ---------------------------------------------------------------- the moving parts
    void ApplyParts()
    {
        if (armMount != null) armMount.localRotation = Quaternion.Euler(-ArmRaise, 0f, 0f);
        float jig = jiggleT > 0f ? Mathf.Sin(jiggleT * 90f) * 7f * (jiggleT / 0.25f) : 0f;
        if (jiggleT > 0f) jiggleT -= Time.deltaTime;
        if (bucketMount != null) bucketMount.localRotation = Quaternion.Euler(BucketAngle + ArmRaise + jig, 0f, 0f);
        if (driverPivot != null)
        {
            float lean = turnSpeed > 0f ? Mathf.Clamp(turn / turnSpeed, -1f, 1f) : 0f;
            float squat = boardT < 1f ? Mathf.Sin(boardT * Mathf.PI) : 0f;
            driverPivot.localPosition = new Vector3(0f, 0.22f - 0.09f * squat, -0.74f);
            driverPivot.localRotation = Quaternion.Euler(Speed * 3f + 6f * squat, lean * 4f, -lean * 9f);
            driverPivot.gameObject.SetActive(Driven || boardT < 1f);
        }
        if (cleatsL != null) cleatsL.localPosition = new Vector3(0f, 0f, -Mod(trackRunL, 0.125f));
        if (cleatsR != null) cleatsR.localPosition = new Vector3(0f, 0f, -Mod(trackRunR, 0.125f));
        DrawHeap();
    }

    static float Mod(float a, float m) { float r = a % m; return r < 0f ? r + m : r; }

    // ---------------------------------------------------------------- sounds
    // The sounds come from the game's sound system (SoundBank / GameAudio).  The hook points, for anyone changing them:
    //   EngineLoad 0..1 (how hard the engine is working, labour included), Labour 0..1, HydraulicsMoving,
    //   and the one-shots: Sound("clunk") stepping on / off and at an end stop, Sound("clunk") high on solid rock.
    public float EngineLoad { get; private set; }
    public float Labour { get; private set; }
    public bool HydraulicsMoving { get; private set; }
    public int EndStops { get; private set; }                 // end-stop clunks so far (tests)
    AudioSource sEngine, sLug, sTracks, sHydraulic;

    void Sound(string name, Vector3 at, float volume, float pitch) { GameAudio.PlayAt(name, at, volume, pitch); }

    void UpdateSound(float dt)
    {
        if (GameAudio.Instance == null) return;
        if (sEngine == null)
        {
            sEngine = GameAudio.Loop(gameObject, "engine", 0.6f, 4f, 60f);
            sLug = GameAudio.Loop(gameObject, "engine_lug", 0.6f, 4f, 60f);
            sTracks = GameAudio.Loop(gameObject, "tracks", 0.6f, 3f, 40f);
            sHydraulic = GameAudio.Loop(gameObject, "hydraulic", 0.6f, 3f, 30f);
        }
        bool on = Driven && !Prologue.Playing;
        float eng = GameAudio.Engine, fx = GameAudio.Effects;
        float want = on ? Mathf.Clamp01(Mathf.Abs(throttleIn) * 0.85f + Mathf.Abs(armIn) * 0.35f + Mathf.Abs(bucketIn) * 0.2f) : 0f;
        EngineLoad = Mathf.MoveTowards(EngineLoad, want, dt * (want > EngineLoad ? 1.4f : 0.9f));
        float wantLabour = on && throttleIn > 0.2f ? Mathf.Clamp01((1f - Bog) * 1.6f + (hardTimer > 0f ? 0.6f : 0f)) : 0f;
        Labour = Mathf.MoveTowards(Labour, wantLabour, dt * 1.5f);
        // a small engine: the dozer's sounds, pitched up
        GameAudio.Steer(sEngine, on ? (0.4f + 0.3f * EngineLoad) * (1f - 0.3f * Labour) * eng : 0f, 1.25f + 0.6f * EngineLoad - 0.2f * Labour, dt, on ? 6f : 2f);
        GameAudio.Steer(sLug, on ? Labour * 0.7f * eng : 0f, 1.15f + 0.3f * EngineLoad - 0.15f * Labour, dt, 5f);
        float run = Mathf.Abs(Speed) + Mathf.Abs(turn) * 0.01f;
        GameAudio.Steer(sTracks, on ? Mathf.Clamp01(run / 1.2f) * 0.35f * eng : 0f, 0.6f + 0.35f * run, dt, 10f);
        HydraulicsMoving = on && (armIn != 0f || bucketIn != 0f);
        GameAudio.Steer(sHydraulic, HydraulicsMoving ? 0.3f * fx : 0f, 1.1f + 0.15f * EngineLoad, dt, 14f);
    }

    // ---------------------------------------------------------------- the model, in voxels
    // Palette numbers are the dozer's (make_bulldozer_vox.py): 1 yellow, 2 amber, 5 dark grey, 6 near black, 7 steel,
    // 8 light steel, 11 lamp, 12 red, 13 worn yellow, 16 worn dark grey.  The driver uses the ground's own colours
    // (VoxelTerrain.shader: 16 hi-vis, 17 navy, 18 skin, 19 hard hat, 20 boots), like the worker.
    const byte YEL = 1, AMB = 2, DGR = 5, BLK = 6, STL = 7, LST = 8, LAMP = 11, RED = 12, YEL2 = 13, DGR2 = 16;

    class Vox
    {
        public readonly Dictionary<Vector3Int, byte> v = new Dictionary<Vector3Int, byte>();
        const float S = VoxelWorld.Voxel;
        /// Fills the voxels whose middles lie inside the box (metres).
        public void Box(float x0, float y0, float z0, float x1, float y1, float z1, byte c)
        {
            for (int x = Mathf.RoundToInt(x0 / S); x < Mathf.RoundToInt(x1 / S); x++)
                for (int y = Mathf.RoundToInt(y0 / S); y < Mathf.RoundToInt(y1 / S); y++)
                    for (int z = Mathf.RoundToInt(z0 / S); z < Mathf.RoundToInt(z1 / S); z++)
                        v[new Vector3Int(x, y, z)] = c;
        }
        /// A beam from a to b (metres), `r` thick across in y/z and `hx` either side in x.
        public void Beam(Vector3 a, Vector3 b, float r, float hx, byte c)
        {
            Vector3 lo = Vector3.Min(a, b) - Vector3.one * (r + hx), hi = Vector3.Max(a, b) + Vector3.one * (r + hx);
            for (int x = Mathf.FloorToInt(lo.x / S); x <= Mathf.CeilToInt(hi.x / S); x++)
                for (int y = Mathf.FloorToInt(lo.y / S); y <= Mathf.CeilToInt(hi.y / S); y++)
                    for (int z = Mathf.FloorToInt(lo.z / S); z <= Mathf.CeilToInt(hi.z / S); z++)
                    {
                        Vector3 p = (new Vector3(x, y, z) + Vector3.one * 0.5f) * S;
                        if (Mathf.Abs(p.x - a.x) > hx) continue;
                        Vector2 pa = new Vector2(p.y - a.y, p.z - a.z), ab = new Vector2(b.y - a.y, b.z - a.z);
                        float t = Mathf.Clamp01(Vector2.Dot(pa, ab) / Mathf.Max(ab.sqrMagnitude, 1e-6f));
                        if ((pa - ab * t).magnitude <= r) v[new Vector3Int(x, y, z)] = c;
                    }
        }
        public void Clear(float x0, float y0, float z0, float x1, float y1, float z1)
        {
            var kill = new List<Vector3Int>();
            foreach (var k in v.Keys)
            {
                Vector3 p = (new Vector3(k.x, k.y, k.z) + Vector3.one * 0.5f) * S;
                if (p.x > x0 && p.x < x1 && p.y > y0 && p.y < y1 && p.z > z0 && p.z < z1) kill.Add(k);
            }
            foreach (var k in kill) v.Remove(k);
        }

        static readonly Vector3Int[] N = { new Vector3Int(1, 0, 0), new Vector3Int(-1, 0, 0), new Vector3Int(0, 1, 0), new Vector3Int(0, -1, 0), new Vector3Int(0, 0, 1), new Vector3Int(0, 0, -1) };
        /// The mesh: one quad per open face.  `terrain`: colours for the ground's shader; else UVs into the dozer's palette.
        public Mesh Build(Vector3 pivot, bool terrain)
        {
            var verts = new List<Vector3>(); var norms = new List<Vector3>(); var uvs = new List<Vector2>(); var cols = new List<Color32>(); var tris = new List<int>();
            foreach (var kv in v)
            {
                var p = kv.Key;
                for (int f = 0; f < 6; f++)
                {
                    if (v.ContainsKey(p + N[f])) continue;
                    Vector3 n = N[f], u = f < 4 ? Vector3.forward : Vector3.right, w = Vector3.Cross(n, u);
                    Vector3 c = (new Vector3(p.x, p.y, p.z) + Vector3.one * 0.5f + n * 0.5f) * S - pivot;
                    int s0 = verts.Count;
                    verts.Add(c + (-u - w) * S * 0.5f); verts.Add(c + (u - w) * S * 0.5f); verts.Add(c + (u + w) * S * 0.5f); verts.Add(c + (-u + w) * S * 0.5f);
                    for (int k = 0; k < 4; k++)
                    {
                        norms.Add(n);
                        uvs.Add(new Vector2((kv.Value + 0.5f) / 32f, 0.5f));
                        cols.Add(terrain ? new Color32(kv.Value, 255, 0, 255) : new Color32(255, 255, 255, 255));
                    }
                    // wind so the face looks out along n
                    if (Vector3.Dot(Vector3.Cross(u, w), n) > 0f) { tris.Add(s0); tris.Add(s0 + 2); tris.Add(s0 + 1); tris.Add(s0); tris.Add(s0 + 3); tris.Add(s0 + 2); }
                    else { tris.Add(s0); tris.Add(s0 + 1); tris.Add(s0 + 2); tris.Add(s0); tris.Add(s0 + 2); tris.Add(s0 + 3); }
                }
            }
            var m = new Mesh { indexFormat = UnityEngine.Rendering.IndexFormat.UInt32 };
            m.SetVertices(verts); m.SetNormals(norms); m.SetUVs(0, uvs); m.SetColors(cols); m.SetTriangles(tris, 0);
            m.RecalculateBounds();
            return m;
        }
    }

    Transform Part(string name, Transform parent, Vector3 localPos, Vox vx, Vector3 pivot, bool terrain)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent, false);
        go.transform.localPosition = localPos;
        if (vx != null)
        {
            go.AddComponent<MeshFilter>().sharedMesh = vx.Build(pivot, terrain);
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = terrain ? TerrainMat() : paint;
        }
        return go.transform;
    }

    static Material TerrainMat() { var w = VoxelWorld.Instance; return w != null ? w.material : null; }

    Material MakePaint()
    {
        // the dozer's own paint (its palette), so the two machines look alike; else a palette strip made here
        var dozer = FindFirstObjectByType<DozerController>();
        if (dozer != null)
            foreach (var mr in dozer.GetComponentsInChildren<MeshRenderer>())
                if (mr.sharedMaterial != null && mr.sharedMaterial.mainTexture != null) return mr.sharedMaterial;
        var cols = new Color32[32];
        var pal = new[] { "000000", "F6BA06", "E29804", "D67A0C", "AC5C0C", "3C3E44", "202126", "7A7E84", "B6BAC0", "1E4052", "40748C", "FFF0BE", "CE3C1E", "EAAC04", "FCCA2C", "C66C0A", "4A4C52" };
        for (int i = 0; i < 32; i++) { Color c; cols[i] = i < pal.Length && ColorUtility.TryParseHtmlString("#" + pal[i], out c) ? (Color32)c : new Color32(255, 0, 255, 255); }
        var tex = new Texture2D(32, 1, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
        tex.SetPixels32(cols); tex.Apply();
        var m = new Material(Shader.Find("Standard")) { mainTexture = tex };
        m.SetFloat("_Glossiness", 0.3f);
        return m;
    }

    void BuildModel()
    {
        paint = MakePaint();
        // ---- the body: tracks, chassis, engine box, control tower, arm towers, rear platform
        var b = new Vox();
        for (int s = -1; s <= 1; s += 2)
        {
            float xa = s < 0 ? -0.50f : 0.28f, xb = s < 0 ? -0.28f : 0.50f;
            b.Box(xa, 0.0f, -0.52f, xb, 0.06f, 0.52f, BLK);                 // the rubber track: bottom run
            b.Box(xa, 0.24f, -0.52f, xb, 0.30f, 0.52f, BLK);                // top run
            b.Box(xa, 0.04f, -0.58f, xb, 0.26f, -0.50f, BLK);               // round the ends
            b.Box(xa, 0.04f, 0.50f, xb, 0.26f, 0.58f, BLK);
            float ia = s < 0 ? -0.46f : 0.30f, ib = s < 0 ? -0.30f : 0.46f;
            b.Box(ia, 0.06f, -0.50f, ib, 0.24f, 0.50f, DGR);                // the frame inside the loop
            float ha = s < 0 ? -0.5f : 0.46f, hb = s < 0 ? -0.46f : 0.5f;
            b.Box(ha, 0.10f, -0.48f, hb, 0.20f, -0.36f, STL);               // drive sprocket hub at the back
            b.Box(ha, 0.10f, 0.38f, hb, 0.20f, 0.48f, STL);                 // idler at the front
            for (float z = -0.25f; z < 0.3f; z += 0.25f) b.Box(ha, 0.08f, z - 0.05f, hb, 0.14f, z + 0.05f, DGR2);   // rollers
        }
        b.Box(-0.28f, 0.10f, -0.56f, 0.28f, 0.44f, 0.50f, DGR);             // chassis between the tracks
        b.Box(-0.40f, 0.42f, -0.30f, 0.40f, 0.94f, 0.48f, YEL);             // engine box
        b.Box(-0.36f, 0.94f, -0.26f, 0.36f, 1.00f, 0.44f, YEL);             // its rounded top
        b.Box(-0.40f, 0.42f, 0.42f, 0.40f, 0.50f, 0.48f, AMB);              // a darker band along the bottom front
        b.Box(-0.28f, 0.52f, 0.48f, 0.28f, 0.84f, 0.52f, BLK);              // front grille
        for (float y = 0.56f; y < 0.82f; y += 0.0625f * 2f) b.Box(-0.26f, y, 0.50f, 0.26f, y + 0.0625f, 0.54f, DGR);
        for (int s = -1; s <= 1; s += 2)
            for (float z = 0.04f; z < 0.36f; z += 0.125f)
                b.Box(s < 0 ? -0.44f : 0.40f, 0.56f, z, s < 0 ? -0.40f : 0.44f, 0.82f, z + 0.0625f, BLK);   // side vents
        b.Box(0.22f, 1.00f, 0.22f, 0.30f, 1.20f, 0.30f, BLK);               // exhaust
        b.Box(0.20f, 1.18f, 0.20f, 0.32f, 1.22f, 0.32f, DGR);
        b.Box(-0.20f, 0.96f, 0.10f, 0.0f, 1.02f, 0.30f, YEL2);              // filler cap plate
        // the control tower at the back of the engine: the panel he stands at, with its levers
        b.Box(-0.36f, 0.94f, -0.34f, 0.36f, 1.14f, -0.18f, YEL);
        b.Box(-0.36f, 1.14f, -0.36f, 0.36f, 1.20f, -0.16f, DGR);
        for (int i = 0; i < 4; i++)
        {
            float x = -0.19f + i * 0.125f;
            b.Box(x, 1.20f, -0.30f, x + 0.0625f, 1.40f, -0.24f, BLK);
            b.Box(x - 0.01f, 1.38f, -0.31f, x + 0.07f, 1.46f, -0.23f, i == 0 || i == 3 ? RED : BLK);
        }
        b.Box(-0.30f, 1.20f, -0.20f, -0.22f, 1.26f, -0.16f, LAMP);          // a little gauge light
        // the uprights the arms hinge on, either side at the back, with the work lights on their fronts
        for (int s = -1; s <= 1; s += 2)
        {
            b.Box(s < 0 ? -0.50f : 0.40f, 0.42f, -0.44f, s < 0 ? -0.40f : 0.50f, 1.30f, -0.20f, YEL);
            b.Box(s < 0 ? -0.56f : 0.50f, 1.16f, -0.38f, s < 0 ? -0.50f : 0.56f, 1.28f, -0.26f, STL);   // pin
            b.Box(s < 0 ? -0.50f : 0.40f, 1.30f, -0.30f, s < 0 ? -0.40f : 0.50f, 1.40f, -0.18f, DGR);   // light housing
            b.Box(s < 0 ? -0.48f : 0.42f, 1.32f, -0.18f, s < 0 ? -0.42f : 0.48f, 1.38f, -0.14f, LAMP);
        }
        // the rear platform he stands on: checker plate, with a bumper and grab posts
        for (float x = -0.34f; x < 0.34f; x += 0.0625f)
            for (float z = -0.96f; z < -0.56f; z += 0.0625f)
            {
                int ix = Mathf.RoundToInt(x / 0.0625f), iz = Mathf.RoundToInt(z / 0.0625f);
                b.Box(x, 0.16f, z, x + 0.0625f, 0.22f, z + 0.0625f, ((ix + iz) & 1) == 0 ? STL : LST);
            }
        b.Box(-0.38f, 0.10f, -1.00f, 0.38f, 0.22f, -0.96f, BLK);
        for (int s = -1; s <= 1; s += 2) b.Box(s < 0 ? -0.38f : 0.32f, 0.22f, -0.62f, s < 0 ? -0.32f : 0.38f, 0.98f, -0.56f, YEL2);
        Part("Body", transform, Vector3.zero, b, Vector3.zero, false);

        // ---- the track cleats (they run round as it drives)
        for (int s = -1; s <= 1; s += 2)
        {
            var c = new Vox();
            for (float z = -0.5f; z < 0.5f; z += 0.125f) c.Box(s < 0 ? -0.50f : 0.28f, 0.30f, z, s < 0 ? -0.28f : 0.50f, 0.3125f + 0.0f + 0.0625f * 0.5f, z + 0.0625f, DGR2);
            var t = Part(s < 0 ? "Cleats_Left" : "Cleats_Right", transform, Vector3.zero, c, Vector3.zero, false);
            if (s < 0) cleatsL = t; else cleatsR = t;
        }

        // ---- the arms: hinge at the top of the uprights, down past the engine to the bucket
        armMount = Part("Mount_Arms", transform, ArmPivot, null, Vector3.zero, false);
        var a = new Vox();
        Vector3 hinge = ArmToHinge;
        for (int s = -1; s <= 1; s += 2)
        {
            float x = s * 0.505f;
            Vector3 p0 = new Vector3(x, 0f, 0f), p1 = new Vector3(x, hinge.y, hinge.z), bend = new Vector3(x, -0.30f, 0.62f);
            a.Beam(p0, bend, 0.075f, 0.045f, YEL);
            a.Beam(bend, p1, 0.075f, 0.045f, YEL);
            a.Beam(new Vector3(x, -0.12f, 0.12f), new Vector3(x, -0.40f, 0.70f), 0.03f, 0.03f, LST);   // the lift ram's chrome rod
        }
        a.Beam(new Vector3(-0.5f, hinge.y + 0.16f, hinge.z - 0.2f), new Vector3(0.5f, hinge.y + 0.16f, hinge.z - 0.2f), 0.05f, 0.5f, YEL);   // cross tube
        // the arms' mesh is modelled in the pivot's space, so offset it by the pivot
        var am = Part("Arms", armMount, Vector3.zero, null, Vector3.zero, false);
        am.gameObject.AddComponent<MeshFilter>().sharedMesh = a.Build(Vector3.zero, false);
        am.gameObject.AddComponent<MeshRenderer>().sharedMaterial = paint;

        // ---- the bucket, hinged at the arms' front ends
        bucketMount = Part("Mount_Bucket", armMount, ArmToHinge, null, Vector3.zero, false);
        var k = new Vox();
        k.Box(-BW, BFloor, -0.02f, BW, BFloor + 0.06f, BLip - 0.06f, YEL);          // floor
        k.Box(-BW, BFloor, BLip - 0.06f, BW, BFloor + 0.04f, BLip, LST);            // the steel cutting edge
        k.Box(-BW, BFloor, -0.06f, BW, BBack, 0.00f, YEL);                          // back
        k.Box(-BW, BFloor + 0.04f, 0.00f, BW, BFloor + 0.12f, 0.06f, YEL);          // the curve where they meet
        k.Box(-BW - 0.02f, BBack - 0.04f, -0.08f, BW + 0.02f, BBack + 0.02f, 0.04f, AMB);   // top of the back
        k.Box(-0.30f, BFloor + 0.10f, -0.12f, 0.30f, BBack - 0.06f, -0.06f, DGR);   // the hitch plate behind
        for (int s = -1; s <= 1; s += 2)
            for (float z = -0.06f; z < BLip - 0.02f; z += 0.0625f)
            {
                float topY = BBack - (Mathf.Max(0f, z) / (BLip - 0.04f)) * (BBack - BSideLip);
                k.Box(s < 0 ? -BW - 0.04f : BW, BFloor, z, s < 0 ? -BW : BW + 0.04f, topY, z + 0.0625f, YEL);   // sides, sloping down to the lip
            }
        // the marker rod on the back corner: painted bands, red tip.  Its lean shows the bucket's angle.
        for (int i = 0; i < 8; i++) k.Box(BW - 0.08f, BBack + 0.02f + i * 0.0625f, -0.06f, BW - 0.02f, BBack + 0.02f + (i + 1) * 0.0625f, 0.0f, (i & 1) == 0 ? BLK : YEL);
        k.Box(BW - 0.09f, BBack + 0.52f, -0.07f, BW - 0.01f, BBack + 0.58f, 0.01f, RED);
        bucket = Part("Bucket", bucketMount, Vector3.zero, k, Vector3.zero, false);
        loadHeap = new GameObject("Load").transform;
        loadHeap.SetParent(bucket, false);
        loadHeap.gameObject.AddComponent<MeshFilter>().sharedMesh = new Mesh();
        loadHeap.gameObject.AddComponent<MeshRenderer>();

        // ---- the driver, on the platform, hands on the levers
        driverPivot = new GameObject("Driver").transform;
        driverPivot.SetParent(transform, false);
        driverPivot.localPosition = new Vector3(0f, 0.22f, -0.74f);
        var d = new Vox();
        for (int s = -1; s <= 1; s += 2)
        {
            float xa = s < 0 ? -0.16f : 0.04f, xb = s < 0 ? -0.04f : 0.16f;
            d.Box(xa, 0.0f, -0.08f, xb, 0.10f, 0.12f, 20);                  // boots
            d.Box(xa, 0.10f, -0.06f, xb, 0.84f, 0.06f, 17);                 // legs
            d.Beam(new Vector3(s * 0.21f, 1.34f, 0f), new Vector3(s * 0.15f, 1.12f, 0.36f), 0.05f, 0.05f, 16);   // arms out to the levers
            d.Box(s * 0.15f - 0.05f, 1.06f, 0.36f, s * 0.15f + 0.05f, 1.16f, 0.46f, 18);                      // hands
        }
        d.Box(-0.18f, 0.84f, -0.11f, 0.18f, 1.40f, 0.11f, 16);              // hi-vis shirt
        d.Box(-0.18f, 0.84f, -0.11f, 0.18f, 0.90f, 0.11f, 17);              // belt
        d.Box(-0.09f, 1.40f, -0.08f, 0.09f, 1.62f, 0.10f, 18);              // head
        d.Box(-0.12f, 1.60f, -0.12f, 0.12f, 1.70f, 0.13f, 19);              // hard hat
        d.Box(-0.12f, 1.60f, 0.13f, 0.12f, 1.64f, 0.19f, 19);               // its brim
        var dm = new GameObject("Driver body");
        dm.transform.SetParent(driverPivot, false);
        dm.AddComponent<MeshFilter>().sharedMesh = d.Build(Vector3.zero, true);
        driverMr = dm.AddComponent<MeshRenderer>();
        driverPivot.gameObject.SetActive(false);

        // ---- two work lights on the uprights, aimed ahead and a little down
        lights = new GameObject("Lights").transform;
        lights.SetParent(transform, false);
        for (int s = -1; s <= 1; s += 2)
        {
            var go = new GameObject("Work light");
            go.transform.SetParent(lights, false);
            go.transform.localPosition = new Vector3(s * 0.45f, 1.35f, -0.12f);
            go.transform.localRotation = Quaternion.Euler(14f, s * 6f, 0f);
            var l = go.AddComponent<Light>();
            l.type = LightType.Spot; l.color = new Color(1f, 0.93f, 0.78f); l.intensity = 2.6f; l.range = 18f; l.spotAngle = 80f;
            l.shadows = s < 0 ? LightShadows.Soft : LightShadows.None;
            l.renderMode = LightRenderMode.ForcePixel;
        }
        lights.gameObject.SetActive(false);
    }
    MeshRenderer driverMr;

    // ---- the load in the bucket: a lumpy heap, in the colours of what went in, rising as it fills
    int drawnVoxels = -1;
    void DrawHeap()
    {
        if (world == null || loadHeap == null) return;
        var mr = loadHeap.GetComponent<MeshRenderer>();
        if (mr.sharedMaterial == null) mr.sharedMaterial = world.material;
        if (driverMr != null && driverMr.sharedMaterial == null) driverMr.sharedMaterial = world.material;
        int have = world.BucketVoxels;
        if (Mathf.Abs(have - drawnVoxels) < 8 && !(have == 0 && drawnVoxels != 0)) return;
        drawnVoxels = have;
        loadHeap.gameObject.SetActive(have > 0);
        if (have <= 0) return;
        int[] mats = { VoxelWorld.LooseSoil, VoxelWorld.LooseClay, VoxelWorld.LooseRock, VoxelWorld.LooseQuartz, VoxelWorld.LooseGold };
        float total = 0f;
        foreach (int m in mats) total += world.BucketLoadOf(m);
        float fill = Mathf.Min(have / (float)Capacity, OverFill);
        var verts = new List<Vector3>(); var norms = new List<Vector3>(); var cols = new List<Color32>(); var tris = new List<int>();
        // the load as clods (each a clod's size, 1/8 m), stacked in columns: up to the rim, then heaped in the middle.
        // Each clod is the colour of one of the materials in it, in proportion; the top of each column is a lumpy part-clod.
        const float C = VoxelWorld.ClodRadius * 2f;
        int nx = Mathf.FloorToInt(BW * 2f / C), nz = Mathf.FloorToInt((BLip - 0.06f) / C);
        float x0 = -nx * C * 0.5f;
        // how tall each column would be full (to the rim, plus the heap), scaled so the clods add up to the load
        var full = new float[nx, nz];
        float sum = 0f;
        for (int x = 0; x < nx; x++)
            for (int z = 0; z < nz; z++)
            {
                float u = (x + 0.5f) / nx * 2f - 1f, w = (z + 0.5f) / nz;
                float rim = (BBack - BFloor) - (BBack - BSideLip) * w;
                float heap = 0.24f * (1f - u * u) * (1f - 0.6f * w);
                full[x, z] = rim + heap;
                sum += full[x, z];
            }
        float wantVol = have * VoxelWorld.VoxelVolume, scale = sum > 0f ? wantVol / (sum * C * C) : 0f;
        for (int x = 0; x < nx; x++)
            for (int z = 0; z < nz; z++)
            {
                float hgt = full[x, z] * scale;
                int whole = Mathf.FloorToInt(hgt / C);
                for (int y = 0; y <= whole; y++)
                {
                    float hy = y < whole ? C : hgt - whole * C;
                    if (hy < 0.015f) continue;
                    float jx = (Noise(x, z * 31 + y, 4) - 0.5f) * 0.03f, jz = (Noise(x, z * 31 + y, 5) - 0.5f) * 0.03f;
                    float pick = Noise(x, z * 31 + y, 2) * total, acc = 0f;
                    byte mat = (byte)VoxelWorld.LooseSoil;
                    foreach (int m in mats) { acc += world.BucketLoadOf(m); if (pick <= acc && world.BucketLoadOf(m) > 0) { mat = (byte)m; break; } }
                    float sz = C * (0.86f + 0.14f * Noise(x, z * 31 + y, 6));
                    Vector3 c = new Vector3(x0 + (x + 0.5f) * C + jx, BFloor + 0.06f + y * C + hy * 0.5f, 0.02f + (z + 0.5f) * C + jz);
                    Cube(verts, norms, cols, tris, c, new Vector3(sz, hy, sz), mat);
                }
            }
        var mesh = loadHeap.GetComponent<MeshFilter>().sharedMesh;
        mesh.Clear();
        mesh.SetVertices(verts); mesh.SetNormals(norms); mesh.SetColors(cols); mesh.SetTriangles(tris, 0);
        mesh.RecalculateBounds();
    }

    static float Noise(int x, int z, int salt)
    {
        uint h = (uint)(x * 73856093) ^ (uint)(z * 19349663) ^ (uint)(salt * 83492791);
        h ^= h >> 13; h *= 0x5bd1e995; h ^= h >> 15;
        return (h & 0xffff) / 65535f;
    }

    static readonly Vector3[] FaceN = { Vector3.right, Vector3.left, Vector3.up, Vector3.down, Vector3.forward, Vector3.back };
    static readonly Vector3[] FaceU = { Vector3.forward, Vector3.back, Vector3.right, Vector3.left, Vector3.left, Vector3.right };
    static void Cube(List<Vector3> verts, List<Vector3> norms, List<Color32> cols, List<int> tris, Vector3 centre, Vector3 size, byte mat)
    {
        var col = new Color32(mat, 255, 0, 255);
        for (int f = 0; f < 6; f++)
        {
            Vector3 n = FaceN[f], u = FaceU[f], v = Vector3.Cross(n, u);
            int start = verts.Count;
            for (int k = 0; k < 4; k++)
            {
                float su = (k == 1 || k == 2) ? 1f : -1f, sv = k >= 2 ? 1f : -1f;
                verts.Add(centre + Vector3.Scale(n + u * su + v * sv, size * 0.5f));
                norms.Add(n); cols.Add(col);
            }
            tris.Add(start); tris.Add(start + 2); tris.Add(start + 1);
            tris.Add(start); tris.Add(start + 3); tris.Add(start + 2);
        }
    }

    // ---------------------------------------------------------------- what's on screen
    bool showView = true;
    Texture2D viewTex; Color32[] viewPx;
    const int VW = 112, VH = 72, VZoom = 3;
    float viewTimer;
    GUIStyle viewLabel;

    /// The bucket's angle to level ground (degrees, + tipped), as the view and the help show it.
    public float BucketToGround { get { return bucket == null ? 0f : -Mathf.Asin(Mathf.Clamp(bucket.forward.y, -1f, 1f)) * Mathf.Rad2Deg; } }

    void RedrawView()
    {
        if (viewTex == null) { viewTex = new Texture2D(VW, VH, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp }; viewPx = new Color32[VW * VH]; }
        Vector3 fwd = transform.forward; fwd.y = 0f; fwd.Normalize();
        Vector3 right = new Vector3(fwd.z, 0f, -fwd.x);
        Vector3 centre = transform.position + fwd * 0.9f + Vector3.up * 1.6f;
        const float mpp = VoxelWorld.Voxel;
        world.RenderSlice(viewPx, VW, VH, centre, fwd, Vector3.up, mpp, right, 0.6f);
        System.Func<Vector3, Vector2> toPx = p => { Vector3 dd = p - centre; return new Vector2(Vector3.Dot(dd, fwd) / mpp + VW * 0.5f, Vector3.Dot(dd, Vector3.up) / mpp + VH * 0.5f); };
        var dark = new Color32(40, 42, 48, 255); var yel = new Color32(246, 186, 6, 255); var steel = new Color32(200, 204, 210, 255); var red = new Color32(220, 60, 30, 255);
        // tracks and body
        ViewLine(toPx(transform.TransformPoint(0f, 0.15f, -0.55f)), toPx(transform.TransformPoint(0f, 0.15f, 0.55f)), dark, 4);
        ViewLine(toPx(transform.TransformPoint(0f, 0.7f, -0.3f)), toPx(transform.TransformPoint(0f, 0.7f, 0.45f)), yel, 7);
        ViewLine(toPx(transform.TransformPoint(0f, 0.19f, -0.95f)), toPx(transform.TransformPoint(0f, 0.19f, -0.56f)), steel, 1);
        // arm and bucket
        ViewLine(toPx(armMount.position), toPx(bucketMount.position), yel, 2);
        Vector2 b0 = toPx(bucket.TransformPoint(0f, BBack, -0.03f)), b1 = toPx(bucket.TransformPoint(0f, BFloor, -0.03f)), b2 = toPx(bucket.TransformPoint(0f, BFloor, BLip)), b3 = toPx(bucket.TransformPoint(0f, BSideLip, BLip - 0.04f));
        if (Fill01 > 0f)
            for (float t = 0f; t <= 1f; t += 0.08f)
                ViewLine(Vector2.Lerp(b1, b2, t * 0.9f), Vector2.Lerp(b1, b2, t * 0.9f) + (b0 - b1).normalized * (0.62f - 0.3f * t) * Mathf.Min(Fill, OverFill) / mpp, new Color32(153, 117, 77, 255), 1);
        ViewLine(b0, b1, yel, 2); ViewLine(b1, b2, yel, 2); ViewLine(b2, b3, steel, 1);
        ViewLine(toPx(bucket.TransformPoint(BW - 0.05f, BBack + 0.02f, -0.03f)), toPx(bucket.TransformPoint(BW - 0.05f, BBack + 0.58f, -0.03f)), red, 1);   // the marker rod
        viewTex.SetPixels32(viewPx); viewTex.Apply(false);
    }

    void ViewLine(Vector2 p, Vector2 q, Color32 c, int thick)
    {
        int steps = Mathf.Max(1, Mathf.CeilToInt(Vector2.Distance(p, q) * 1.5f));
        for (int i = 0; i <= steps; i++)
        {
            Vector2 m = Vector2.Lerp(p, q, i / (float)steps);
            int x0 = Mathf.RoundToInt(m.x - thick * 0.5f), y0 = Mathf.RoundToInt(m.y - thick * 0.5f);
            for (int dy = 0; dy < thick; dy++) for (int dx = 0; dx < thick; dx++)
                {
                    int x = x0 + dx, y = y0 + dy;
                    if (x >= 0 && y >= 0 && x < VW && y < VH) viewPx[x + y * VW] = c;
                }
        }
    }

    public string AngleText
    {
        get
        {
            float a = BucketToGround;
            return Mathf.Abs(a) < 3f ? "flat" : a > 0f ? "tipped " + Mathf.RoundToInt(a) + "°" : "curled " + Mathf.RoundToInt(-a) + "°";
        }
    }

    void OnGUI()
    {
        if (Prologue.Playing || world == null) return;
        Ui.Begin();
        var wk = Worker.Instance;
        if (!Driven)
        {
            // walking up to it: say what Enter does
            if (wk != null && !wk.InDozer && !wk.RidingCart && Near(wk.transform.position))
            {
                var prompt = new GUIStyle(GUI.skin.box) { fontSize = 20, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
                string what = owned ? "Press " + Pad.Key("ENTER", "Y") + " to get on the Dingo" : "Dingo: locked.  Buy it in the upgrades (" + Pad.Key("U", "Start") + "), after Shovel 6";
                GUI.Box(new Rect(Ui.W / 2 - 290, Ui.H * 0.56f, 580, 40), what, prompt);
            }
            return;
        }
        string help = Pad.InUse ?
            "Left stick   drive and turn          Y   get off          Start   upgrades\n" +
            "Left trigger / right trigger   arms up / down\n" +
            "LB / RB   curl / tip the bucket   (tap RB again to shake it out)\n" +
            "B   lights          Right stick   look round" :
            "W / S   drive          A / D   turn on the spot          Enter   get off\n" +
            "R / F   arms up / down\n" +
            "Q / E   curl / tip the bucket   (tap E again to shake it out)\n" +
            "L   lights      V   bucket view      Right mouse drag   look round";
        help += "\nBucket " + Litres.ToString("F0") + " of " + BucketLitres.ToString("F0") + " L  (" + Mathf.RoundToInt(Fill * 100f) + "%)" + (Fill > 1.08f ? "  OVERFILLED: it drops clods on bumps" : "") + "    " + AngleText + "    Speed " + (Speed * 3.6f).ToString("F1") + " km/h";
        int lines = 5;
        if (Bog < 0.75f && Speed > 0.02f) { help += "\nLabouring: ease off, or curl and lift to break the bite"; lines++; }
        if (HitRock || hardTimer > 0f) { help += "\nSOLID ROCK: the bucket won't cut it.  Break it with the jackhammer"; lines++; }
        if (Blocked && Mathf.Abs(throttleIn) > 0.1f) { help += "\nIn the way: back off and steer round"; lines++; }
        GUI.Box(new Rect(10, 10, 520, 16 + 18 * lines), help);
        if (wk != null) GUI.Box(new Rect(10, Ui.H - 34, 190, 24), Pad.Key("Enter", "Y") + "   get off");

        // the bucket view, top right
        if (!showView) { GUI.Box(new Rect(Ui.W - 160, 10, 150, 24), "V   bucket view"); return; }
        viewTimer -= Time.unscaledDeltaTime;
        if (viewTimer <= 0f || viewTex == null) { viewTimer = 1f / 12f; RedrawView(); }
        if (viewLabel == null) viewLabel = new GUIStyle(GUI.skin.label) { fontSize = 14, fontStyle = FontStyle.Bold };
        int w = VW * VZoom, h = VH * VZoom;
        float x = Ui.W - w - 14;
        GUI.Box(new Rect(x - 6, 6, w + 12, h + 54), GUIContent.none);
        GUI.Label(new Rect(x, 8, w, 20), "Bucket   " + AngleText + "     " + Mathf.RoundToInt(Fill * 100f) + "% full   " + Litres.ToString("F0") + " L", viewLabel);
        GUI.DrawTexture(new Rect(x, 30, w, h), viewTex);
        GUI.Label(new Rect(x, 32 + h, w, 20), "(V hides)", viewLabel);
    }

    /// Draws the bucket view into whatever is being rendered (clips: the normal on-screen drawing isn't recorded).
    public void DrawInto(int width, int height)
    {
        if (!Driven || !showView || world == null) return;
        RedrawView();
        GL.PushMatrix();
        GL.LoadPixelMatrix(0, width, height, 0);
        int w = VW * VZoom, h = VH * VZoom;
        Graphics.DrawTexture(new Rect(width - w - 14, 30, w, h), viewTex);
        GL.PopMatrix();
    }
}
