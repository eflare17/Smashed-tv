// Trailer mode: the game plays itself for filming a trailer (the owner asked for it, 22 Nov 2026).
// Start the game with  -trailer  (DiggerGame.exe -trailer), or press F7 in the game.  (It was F8, which is also the upgrades' test key:
// pressing it for free coins started trailer mode by mistake and stopped the game saving.)
//   - a FRESH game: nothing is loaded and nothing is saved (the owner's save is never touched);
//   - the yellow dozer starts at the foot of the mountain road and drives itself up it with blade auto on Grade,
//     so the pegs, the red / green / blue grade tint and the stretch ticks are all there to see;
//   - a slow cinematic camera swings round it; every on-screen panel (HUD, help, blade views) is hidden;
//   - about 80 s of driving, then it stops and the camera keeps slowly circling.  Esc still quits as usual.
// Other shots, each on a fixed camera path, timed from when the shot starts (about 1.5 s after the world appears):
//   -trailer mine      0-5 s the son swings the pick at the quartz seam in the first chamber (the gold glints);
//                      5-13 s outside the mouth: he pushes a loaded cart out of the mouth into daylight, 13-15 s it tips.
//   -trailer restore   0-3 s the rusted old dozer, still; 3-5 s the engine catches with a burst of black smoke;
//                      at 5.0 s exactly it becomes the restored yellow dozer, same framing, idling, to 10 s.
//   -trailer wide      the whole road graded and ticked; a slow 12 s pull-back from above the switchbacks to wide.
// (-trailer road, or -trailer alone, is the drive up the road.)  Each shot then holds its last frame.
// The road drive with other cameras (for the road clip, 22 Nov 2026); an optional number starts it that many metres up the road:
//   -trailer low [m]   low and close at the front corner of the blade, the dirt spraying off it, creeping round slowly;
//   -trailer side [m]  three-quarters front, a bit higher, the whole dozer and its blade load;
//   -trailer high [m]  high and wide over the switchbacks and the forest, the road behind it already graded (green).
//   -trailer pull [m]  starts close behind the blade and rises slowly away to high and wide, the graded road below.
// Add  -tall  for a tall (phone, 9:16) window: the cameras frame the blade and its dirt for a narrow picture.
// Add  -recordaudio <file.wav>  to record the game's own sound while filming (TrailerAudio).
using UnityEngine;

public class TrailerMode : MonoBehaviour
{
    public static bool On { get; set; }
    public enum ShotKind { Road, Mine, Restore, Wide }
    public static ShotKind Shot = ShotKind.Road;
    public enum RoadCamKind { Swing, Low, Side, High, Pull }
    public static bool Tall;
    public static RoadCamKind RoadCam = RoadCamKind.Swing;
    public static float StartAlong = 0f;
    public static TrailerMode Instance { get; private set; }
    public const float DriveFor = 80f;

    float t0, stuckClock, liftUntil = -1f;
    Vector3 lastPos;
    DozerController d;
    FollowCamera follow;
    bool started;

    /// Called as the game starts (SiteProps): is the game to play itself?
    public static void CheckCommandLine()
    {
        var args = System.Environment.GetCommandLineArgs();
        foreach (var a in args) if (a.ToLowerInvariant() == "-tall") Tall = true;
        for (int i = 0; i < args.Length; i++)
            if (args[i].ToLowerInvariant() == "-trailer")
            {
                On = true;
                string k = i + 1 < args.Length ? args[i + 1].ToLowerInvariant() : "";
                Shot = k == "mine" ? ShotKind.Mine : k == "restore" ? ShotKind.Restore : k == "wide" ? ShotKind.Wide : ShotKind.Road;
                RoadCam = k == "low" ? RoadCamKind.Low : k == "side" ? RoadCamKind.Side : k == "high" ? RoadCamKind.High : k == "pull" ? RoadCamKind.Pull : RoadCamKind.Swing;
                float m;
                if (i + 2 < args.Length && float.TryParse(args[i + 2], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out m)) StartAlong = Mathf.Max(0f, m);
            }
    }

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    void Update()
    {
        if (!On && PauseMenu.TestKeys && Input.GetKeyDown(KeyCode.F7)) On = true;               // (mid-game: from where the dozer is, the save is no longer written)
        if (!On) return;
        if (!started) { if (Time.timeSinceLevelLoad > 1.5f) { if (Shot == ShotKind.Road) Begin(); else BeginShot(); } return; }
        if (Shot != ShotKind.Road) { UpdateShot(); return; }
        Drive();
        Camera();
    }

    void Begin()
    {
        d = FindFirstObjectByType<DozerController>();
        var wk = Worker.Instance;
        if (d == null || wk == null) return;
        started = true;
        wk.useOverride = true;
        if (!wk.InDozer) wk.GetIn();
        d.dead = false;
        d.useOverride = true;
        Vector2 p0 = MountainRoad.Point(0), p1 = MountainRoad.Point(Mathf.Min(3, MountainRoad.Count - 1)), dir = (p1 - p0).normalized;
        Vector2 at = p0 - dir * 3f;
        if (StartAlong > 0f)
        {
            at = PointAlong(StartAlong);
            dir = (PointAlong(StartAlong + 2f) - at).normalized;
        }
        if ((RoadCam == RoadCamKind.High || RoadCam == RoadCamKind.Pull) && StartAlong > 0f)
        {
            // the stretches it has already done are graded (green) behind it
            var job = MountainRoadJob.Instance;
            int upTo = MountainRoad.StretchOf(StartAlong);
            if (job != null) for (int k = 0; k < upTo; k++) job.TestGradeStretch(k);
        }
        d.Place(new Vector3(at.x, 0f, at.y), Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg);
        d.SetGradeAuto(0);
        d.overrideBlade = 0f; d.overrideRipper = 1f; d.overrideSteer = 0f; d.overrideThrottle = 0f;
        var cam = UnityEngine.Camera.main;
        follow = cam != null ? cam.GetComponent<FollowCamera>() : null;
        t0 = Time.time; lastPos = d.transform.position;
        TrailerAudio.Attach();
        if (RoadCam != RoadCamKind.Swing)
        {
            if (follow != null) follow.enabled = false;
            camHeading = d.transform.eulerAngles.y;
            camSnap = true;
            RoadCamera();
        }
    }

    void Drive()
    {
        if (d == null) return;
        float t = Time.time - t0;
        Vector3 pos = d.transform.position;
        float s, off; Vector2 rd;
        MountainRoad.Nearest(pos.x, pos.z, out s, out off, out rd);
        if (t < 1.5f || t > DriveFor || s > MountainRoad.Length - 4f) { d.overrideThrottle = 0f; d.overrideSteer = 0f; return; }
        // aim at a point a few metres further up the road's line
        Vector2 aim = PointAlong(s + 5f);
        Vector2 here = new Vector2(pos.x, pos.z), to = aim - here;
        float want = Mathf.Atan2(to.x, to.y) * Mathf.Rad2Deg;
        float diff = Mathf.DeltaAngle(d.transform.eulerAngles.y, want);
        d.overrideSteer = Mathf.Clamp(diff / 25f, -1f, 1f);
        d.overrideThrottle = Mathf.Abs(diff) > 45f ? 0.25f : 0.7f;           // slow right down round the switchbacks
        // held up (a big heap on the blade): lift it a little for a moment, then back to grade
        stuckClock += Time.deltaTime;
        if (stuckClock > 3f)
        {
            if ((pos - lastPos).magnitude < 0.4f) { d.SetGradeAuto(25); liftUntil = t + 2f; }
            stuckClock = 0f; lastPos = pos;
        }
        if (liftUntil > 0f && t > liftUntil) { d.SetGradeAuto(0); liftUntil = -1f; }
    }

    static Vector2 PointAlong(float s)
    {
        int n = MountainRoad.Count;
        s = Mathf.Clamp(s, 0f, MountainRoad.Length);
        for (int i = 1; i < n; i++)
            if (MountainRoad.AlongAt(i) >= s)
                return Vector2.Lerp(MountainRoad.Point(i - 1), MountainRoad.Point(i), Mathf.InverseLerp(MountainRoad.AlongAt(i - 1), MountainRoad.AlongAt(i), s));
        return MountainRoad.Point(n - 1);
    }

    void Camera()
    {
        if (RoadCam != RoadCamKind.Swing) { RoadCamera(); return; }
        if (follow == null) return;
        float t = Time.time - t0;
        // a slow swing from one side to the other and back (about 40 s each way), drifting in and out a little
        follow.yawOffset = 55f * Mathf.Sin(t * Mathf.PI * 2f / 80f) + 20f;
        follow.distance = 13f + 3f * Mathf.Sin(t * Mathf.PI * 2f / 47f);
        follow.pitch = 21f + 5f * Mathf.Sin(t * Mathf.PI * 2f / 61f + 1f);
    }
    // the road drive's other cameras: placed round the dozer by a slowly following heading, so the switchbacks become slow orbits
    float camHeading;
    bool camSnap;
    void RoadCamera()
    {
        if (d == null) return;
        float t = Time.time - t0, dt = Time.deltaTime;
        camHeading = Mathf.MoveTowardsAngle(camHeading, d.transform.eulerAngles.y, Mathf.Max(4f, Mathf.Abs(Mathf.DeltaAngle(camHeading, d.transform.eulerAngles.y)) * 0.5f) * dt);
        Vector3 p = d.transform.position;
        Vector3 fwd = Quaternion.Euler(0f, camHeading, 0f) * Vector3.forward;
        float ang, dist, up; Vector3 look;
        if (Tall && RoadCam == RoadCamKind.Low)
        {
            ang = -28f + 14f * Mathf.Clamp01(t / 40f);                         // nearer head-on: the blade and the dirt it spills fit a narrow picture
            dist = 13.5f; up = 4.2f;
            look = p + fwd * 3.2f + Vector3.up * 0.4f;
        }
        else if (Tall && RoadCam == RoadCamKind.Side)
        {
            ang = 30f + 20f * Mathf.Clamp01(t / 30f);
            dist = 17f; up = 9f;
            look = p + fwd * 2f;
        }
        else if (RoadCam == RoadCamKind.Pull)
        {
            float u = Mathf.Clamp01(t / 14f); u = u * u * (3f - 2f * u);     // eased
            ang = 165f - 25f * u;                                               // from just behind, swinging a little to the side
            dist = Mathf.Lerp(9f, 34f, u); up = Mathf.Lerp(5f, 34f, u);
            look = p + fwd * Mathf.Lerp(3f, 0f, u);
        }
        else if (RoadCam == RoadCamKind.Low)
        {
            ang = -46f + 20f * Mathf.Clamp01(t / 40f);                         // front-left corner of the blade, creeping round
            dist = 13f; up = 3.6f;
            look = p + fwd * 2.2f + Vector3.up * 1.0f;
        }
        else if (RoadCam == RoadCamKind.Side)
        {
            ang = 38f + 30f * Mathf.Clamp01(t / 30f);                          // three-quarters front-right
            dist = 16f; up = 7.5f;
            look = p + fwd * 1.2f + Vector3.up * 1.1f;
        }
        else
        {
            ang = 140f + 1.2f * t;                                             // high, behind and to the side, the graded road below
            dist = 30f; up = 26f;
            look = p + fwd * 4f;
        }
        Vector3 dir = Quaternion.Euler(0f, camHeading + ang, 0f) * Vector3.forward;
        Vector3 want = p + dir * dist + Vector3.up * up;
        var w = VoxelWorld.Instance;
        if (w != null) want.y = Mathf.Max(want.y, w.HeightAt(want.x, want.z) + 1.3f);    // never inside the hillside
        if (camSnap) { camPos = want; camLook = look; camSnap = false; }
        else
        {
            camPos = Vector3.Lerp(camPos, want, 1f - Mathf.Exp(-dt * 1.6f));
            camLook = Vector3.Lerp(camLook, look, 1f - Mathf.Exp(-dt * 2.5f));
        }
    }

    // ================================================================== the other shots
    float shotT { get { return Time.time - t0; } }
    Vector3 camPos, camLook;
    Worker wk;
    MineCart cart;
    bool shotFlag1, shotFlag2;
    float cartFrom;

    void BeginShot()
    {
        d = FindFirstObjectByType<DozerController>();
        wk = Worker.Instance;
        if (d == null || wk == null || VoxelWorld.Instance == null) return;
        started = true;
        var cam = UnityEngine.Camera.main;
        follow = cam != null ? cam.GetComponent<FollowCamera>() : null;
        if (follow != null) follow.enabled = false;                       // the shots move the camera themselves
        wk.useOverride = true;
        d.useOverride = true; d.dead = false;
        d.overrideThrottle = 0f; d.overrideSteer = 0f; d.overrideBlade = 0f; d.overrideRipper = 0f;
        t0 = Time.time;
        TrailerAudio.Attach();
        if (Shot == ShotKind.Mine) BeginMine();
        else if (Shot == ShotKind.Restore) BeginRestore();
        else BeginWide();
    }

    void UpdateShot()
    {
        if (Shot == ShotKind.Mine) UpdateMine();
        else if (Shot == ShotKind.Restore) UpdateRestore();
        else UpdateWide();
    }

    void LateUpdate()
    {
        if (!On || !started || (Shot == ShotKind.Road && RoadCam == RoadCamKind.Swing)) return;
        var cam = UnityEngine.Camera.main;
        if (cam == null) return;
        cam.transform.position = camPos;
        cam.transform.rotation = Quaternion.LookRotation(camLook - camPos, Vector3.up);
    }

    // ---- the mine: the pick at the seam, then the cart out into daylight
    const float MineAlong = 20.6f;                                          // metres in: the first chamber, with the quartz seam
    void BeginMine()
    {
        if (wk.InDozer) wk.GetOut();
        wk.SetTool(0);
        var w = VoxelWorld.Instance;
        // he stands in the chamber, side on to its east wall (the seam is at chest height in it)
        Vector3 at = new Vector3(VoxelWorld.PortalX + 0.7f, 0f, VoxelWorld.PortalZ + MineAlong);
        wk.Teleport(at, 90f);
        wk.overrideWalk = 0f; wk.overrideTurn = 0f; wk.overrideUse = true;
        float fy = w.FloorAt(at + Vector3.up * 0.6f);
        camLook = new Vector3(VoxelWorld.PortalX + 1.5f, fy + 1.2f, at.z);
        camPos = new Vector3(VoxelWorld.PortalX - 1.0f, fy + 1.75f, at.z - 2.2f);
        cart = MineCart.Instance;
    }
    void UpdateMine()
    {
        var w = VoxelWorld.Instance;
        float t = shotT;
        if (t < 5f)
        {
            wk.overrideUse = true;
            camPos += new Vector3(0.05f, 0f, 0.06f) * Time.deltaTime;      // a slow creep in
            return;
        }
        if (!shotFlag1 && cart != null)
        {
            // cut: outside the mouth.  The cart, nearly full, a few metres inside; he walks it out.
            shotFlag1 = true;
            wk.overrideUse = false;
            float inside = 0f;
            for (float a = 0f; a < 60f; a += 0.25f) { cart.SetAlong(a); if (cart.transform.position.z < VoxelWorld.PortalZ + 1.1f) { inside = a; break; } }   // just inside the mouth (the first cave-in starts 3 m in)
            cart.SetAlong(inside);
            cartFrom = inside;
            w.TrailerFillCart(Mathf.RoundToInt(cart.capacity * 0.85f));
            Vector3 cp = cart.transform.position, outward = new Vector3(0f, 0f, -1f);
            // behind it, at its inner end, facing out; he takes hold (as E does) so walking pushes it
            for (float back = 1.0f; back <= 2.2f; back += 0.15f)
            {
                wk.Teleport(cp - outward * back, 180f);
                if (wk.GrabCart()) break;
            }
            float fy = w.FloorAt(new Vector3(VoxelWorld.PortalX, 3f, VoxelWorld.PortalZ - 3f));
            camPos = new Vector3(VoxelWorld.PortalX + 3.2f, fy + 1.6f, VoxelWorld.PortalZ - 6.5f);
            camLook = new Vector3(VoxelWorld.PortalX, fy + 1.1f, VoxelWorld.PortalZ + 2.5f);
        }
        if (t < 13f)
        {
            wk.overrideWalk = 0.8f;                                            // walking into the cart's end pushes it
            camLook = Vector3.Lerp(camLook, cart != null ? cart.transform.position + Vector3.up * 0.8f : camLook, Time.deltaTime * 0.8f);
            return;
        }
        wk.overrideWalk = 0f;
        if (!shotFlag2 && cart != null) { shotFlag2 = true; cart.Tip(); }
    }

    // ---- the restoration: rusted, the engine catches, then yellow
    MeshRenderer[] dozerParts;
    void BeginRestore()
    {
        if (!wk.InDozer) wk.GetIn();
        dozerParts = d.GetComponentsInChildren<MeshRenderer>();
        var block = new MaterialPropertyBlock();
        block.SetColor("_Color", new Color(0.55f, 0.33f, 0.22f));          // rust over the old yellow (as in the prologue)
        foreach (var r in dozerParts) r.SetPropertyBlock(block);
        Vector3 p = d.transform.position, f = d.transform.forward, rt = d.transform.right;
        camLook = p + Vector3.up * 1.6f + f * 0.6f;
        camPos = p + f * 8.5f + rt * 5.5f + Vector3.up * 2.6f;              // three-quarters front, a little low
    }
    void UpdateRestore()
    {
        float t = shotT;
        Vector3 top = ExhaustTop();
        if (t >= 3f && t < 4.6f)
        {
            // the engine catches: a cough, then a thick black burst
            int n = t < 3.4f ? 2 : 5;
            for (int i = 0; i < n; i++)
                HeavyFX.Puff(top + Random.insideUnitSphere * 0.08f, Vector3.up * Random.Range(1.2f, 2.2f) + Random.insideUnitSphere * 0.35f,
                             Random.Range(0.9f, 1.6f), Random.Range(2.5f, 4.0f), new Color(0.06f, 0.06f, 0.06f, 0.95f));
            if (!shotFlag1) { shotFlag1 = true; GameAudio.PlayAt("clunk", top, 1f, 0.7f); }
        }
        if (t >= 5f && !shotFlag2)
        {
            shotFlag2 = true;
            foreach (var r in dozerParts) if (r != null) r.SetPropertyBlock(null);   // restored: its own yellow
        }
        camPos += (camLook - camPos).normalized * 0.12f * Time.deltaTime;  // the slightest push in
    }
    Vector3 ExhaustTop()
    {
        Transform ex = null;
        foreach (var tr in d.GetComponentsInChildren<Transform>()) if (tr.name == "Exhaust") { ex = tr; break; }
        if (ex == null) return d.transform.position + Vector3.up * 3.4f;
        var b = new Bounds(ex.position, Vector3.zero);
        foreach (var r in ex.GetComponentsInChildren<Renderer>()) b.Encapsulate(r.bounds);
        return new Vector3(b.center.x, b.max.y + 0.05f, b.center.z);
    }

    // ---- wide: the finished road, pulling back
    Vector3 wideLook, wideDir;
    void BeginWide()
    {
        var job = MountainRoadJob.Instance;
        if (job != null) for (int k = 0; k < MountainRoad.Stretches; k++) job.TestGradeStretch(k);
        // the dozer parked up on the top pad
        Vector2 top = MountainRoad.Point(MountainRoad.Count - 1), before = MountainRoad.Point(Mathf.Max(0, MountainRoad.Count - 4));
        Vector2 dv = (top - before).normalized;
        if (!wk.InDozer) wk.GetIn();
        d.Place(new Vector3(top.x - dv.x * 3f, 0f, top.y - dv.y * 3f), Mathf.Atan2(dv.x, dv.y) * Mathf.Rad2Deg);
        wideLook = new Vector3(Mountain.CX + 6f, MountainRoad.StartY + 10f, Mountain.CZ - 22f);
        wideDir = new Vector3(0.45f, 0.55f, -0.70f).normalized;              // from the south-east, above
        camLook = wideLook; camPos = wideLook + wideDir * 45f + Vector3.up * 8f;
    }
    void UpdateWide()
    {
        float u = Mathf.Clamp01(shotT / 12f);
        u = u * u * (3f - 2f * u);
        camPos = wideLook + wideDir * Mathf.Lerp(45f, 125f, u) + Vector3.up * Mathf.Lerp(8f, 16f, u);   // (starting above the tree tops)
        camLook = wideLook + Vector3.up * Mathf.Lerp(0f, 4f, u);
    }
}
