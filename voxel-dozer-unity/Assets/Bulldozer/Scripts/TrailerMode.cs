// Trailer mode: the game plays itself for filming a trailer (the owner asked for it, 22 Nov 2026).
// Start the game with  -trailer  (DiggerGame.exe -trailer), or press F8 in the game.
//   - a FRESH game: nothing is loaded and nothing is saved (the owner's save is never touched);
//   - the yellow dozer starts at the foot of the mountain road and drives itself up it with blade auto on Grade,
//     so the pegs, the red / green / blue grade tint and the stretch ticks are all there to see;
//   - a slow cinematic camera swings round it; every on-screen panel (HUD, help, blade views) is hidden;
//   - about 80 s of driving, then it stops and the camera keeps slowly circling.  Esc still quits as usual.
using UnityEngine;

public class TrailerMode : MonoBehaviour
{
    public static bool On { get; set; }
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
        foreach (var a in System.Environment.GetCommandLineArgs())
            if (a.ToLowerInvariant() == "-trailer") On = true;
    }

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    void Update()
    {
        if (!On && Input.GetKeyDown(KeyCode.F8)) On = true;               // (mid-game: from where the dozer is, the save is no longer written)
        if (!On) return;
        if (!started) { if (Time.timeSinceLevelLoad > 1.5f) Begin(); return; }
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
        d.Place(new Vector3(at.x, 0f, at.y), Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg);
        d.SetGradeAuto(0);
        d.overrideBlade = 0f; d.overrideRipper = 1f; d.overrideSteer = 0f; d.overrideThrottle = 0f;
        var cam = UnityEngine.Camera.main;
        follow = cam != null ? cam.GetComponent<FollowCamera>() : null;
        t0 = Time.time; lastPos = d.transform.position;
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
        if (follow == null) return;
        float t = Time.time - t0;
        // a slow swing from one side to the other and back (about 40 s each way), drifting in and out a little
        follow.yawOffset = 55f * Mathf.Sin(t * Mathf.PI * 2f / 80f) + 20f;
        follow.distance = 13f + 3f * Mathf.Sin(t * Mathf.PI * 2f / 47f);
        follow.pitch = 21f + 5f * Mathf.Sin(t * Mathf.PI * 2f / 61f + 1f);
    }
}
