// The prologue (rough cut): the bushfire that took the old mine, played in the real game.
//
//   0-7 s    over the hill and the mine, smoke far off                "The high country, Victoria..."
//   7-17     Dad cuts a firebreak across the hilltop with the dozer   (the real blade scrapes it bare: the fire can't cross it)
//   17-28    the fire front arrives beyond the break; it holds
//   28-38    the wind changes: embers jump the break, spot fires start behind him
//   38-50    he turns up the escape track, and the bush either side of it goes up around him; a burning tree falls across it and he shoves it aside;
//            two or three more come down in front and behind, and he's trapped
//   50-57    "Dad!", then red, then black
//   57-62    "Twenty years later"
//   62-85    the son walks up the track through the regrowth to the rusted dozer, stops beside it, looks up at the cab
//            and puts his hand on it; the camera comes in over his shoulder, then rises above the trees, and black
//
// Start it with Prologue.Play().  It drives the dozer, the worker, the fire and the camera itself, hides the game's
// HUD, and draws its own captions and the red and black (RecordPrologue films the same thing).
using UnityEngine;

public class Prologue : MonoBehaviour
{
    public static Prologue Instance { get; private set; }
    public static bool Playing { get { return Instance != null && Instance.playing; } }
    public const float Length = 85f;

    // what's on screen besides the picture (read by the recorder too)
    public string Caption = "", CaptionStyle = "Big", Caption2 = "";
    public Color Tint = Color.clear;
    public float T { get; private set; }

    bool playing;
    float t0;
    DozerController dozer; Worker wk; FireSim fire; Camera cam; FollowCamera follow;
    int pushTree = -1, behindTree = -1;
    float pushFrom, pushStart = -1f;
    bool cutCleared, settled, changed, felled, felled2, released;
    Vector3 standAt, handAt, waypoint, toDozer;            // the ending: where the son stops, where his hand goes
    float arriveT = -1f, craneT;
    bool pastWaypoint;
    Vector3 camPos, camLook;

    public const float LaneZ = 32f, LaneX0 = -12f;                 // the firebreak: across the hilltop to the escape track
    public static float LaneX1 { get { return VoxelWorld.TrackX - 1f; } }

    public static Prologue Play()
    {
        var go = new GameObject("Prologue");
        var p = go.AddComponent<Prologue>();
        p.Begin();
        return p;
    }

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    void Begin()
    {
        dozer = FindFirstObjectByType<DozerController>();
        wk = Worker.Instance; fire = FireSim.Instance; cam = Camera.main;
        follow = cam != null ? cam.GetComponent<FollowCamera>() : null;
        if (follow != null) follow.enabled = false;
        wk.useOverride = true;
        dozer.dead = false;
        if (!wk.InDozer) wk.GetIn();
        dozer.useOverride = true;
        dozer.Place(new Vector3(LaneX0, 0f, LaneZ), 90f);         // at the west end of the break, facing east
        fire.SetWind(new Vector2(0.4f, -5f), new Vector2(0.4f, -5f), 1e9f);
        fire.Begin();
        fire.Ignite(new Vector3(-100f, 0f, 150f), new Vector3(100f, 0f, 150f));   // far off: just smoke at first
        fire.speedUp = 3f;
        fire.HoldTrack(34f, 80f, 9f);                             // the bush by the escape track waits for him
        t0 = Time.time; playing = true;
    }

    float Steer(Vector3 target)
    {
        Vector3 d = target - dozer.transform.position; d.y = 0f;
        float want = Mathf.Atan2(d.x, d.z) * Mathf.Rad2Deg, have = dozer.transform.eulerAngles.y;
        return Mathf.Clamp(Mathf.DeltaAngle(have, want) / 25f, -1f, 1f);
    }

    float HeadingTo(float wantDeg) { return Mathf.Clamp(Mathf.DeltaAngle(dozer.transform.eulerAngles.y, wantDeg) / 25f, -1f, 1f); }

    void Shot(Vector3 pos, Vector3 look) { camPos = pos; camLook = look; }

    static float Ease(float a, float b, float t) { return Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(a, b, t)); }

    void Update()
    {
        if (!playing) return;
        float t = T = Time.time - t0;
        Vector3 dp = dozer.transform.position, df = dozer.transform.forward, dr = dozer.transform.right;
        Caption2 = "";
        if (t < 7f)
        {
            float u = Ease(0f, 7f, t);
            Shot(Vector3.Lerp(new Vector3(-44f, 42f, -34f), new Vector3(-28f, 30f, -16f), u), Vector3.Lerp(new Vector3(0f, 6f, 40f), new Vector3(4f, 6f, 46f), u));
            Caption = "The high country, Victoria"; Caption2 = "Late summer. The old mine."; CaptionStyle = "Place";
            dozer.overrideThrottle = 0f; dozer.overrideBlade = 0f;
        }
        else if (t < 17f)
        {
            if (t - Time.deltaTime < 10f && t >= 10f) { fire.Ignite(new Vector3(-100f, 0f, 63f), new Vector3(100f, 0f, 63f)); fire.speedUp = 1.8f; }
            // cut the break: blade down a little, then along the hilltop to the track
            bool done = dp.x >= LaneX1 - 0.5f;
            dozer.overrideBlade = t < 7.7f ? -1f : 0f;
            dozer.overrideThrottle = done ? 0f : 0.85f;
            dozer.overrideSteer = done ? 0f : Steer(new Vector3(LaneX1 + 4f, 0f, LaneZ));
            Shot(dp + new Vector3(-9f, 3.2f, -3f), dp + new Vector3(5f, 1.4f, 1f));              // along the cleared lane, behind him
            Caption = "Dad cuts a firebreak with the old dozer."; CaptionStyle = "Big";
        }
        else if (t < 28f)
        {
            if (!cutCleared) { cutCleared = true; fire.ClearFuel(LaneX0 - 1f, LaneZ - 2.2f, LaneX1 + 1f, LaneZ + 2.2f); }   // what the blade scraped bare
            dozer.overrideThrottle = 0f; dozer.overrideSteer = 0f;
            dozer.overrideBlade = t < 18.2f ? 1f : 0f;
            float u = Ease(17f, 28f, t);
            Shot(new Vector3(Mathf.Lerp(-4f, 0f, u), SiteProps.HillY(0f, LaneZ - 3f) + 2.2f, LaneZ - 3f), new Vector3(Mathf.Lerp(-1f, 3f, u), 8f, 58f));   // in the lane, looking over the break
            Caption = "The fire front arrives.  The break holds."; CaptionStyle = "Big";
        }
        else if (t < 38f)
        {
            if (!changed) { changed = true; fire.SetWind(fire.WindAt(fire.Now), new Vector2(3f, -11f), fire.Now); fire.speedUp = 2f; }
            float u = Ease(28f, 38f, t);
            Shot(Vector3.Lerp(new Vector3(VoxelWorld.TrackX + 16f, 38f, 62f), new Vector3(VoxelWorld.TrackX + 12f, 34f, 58f), u), new Vector3(-2f, 3f, 22f));   // above the canopy, back over the break
            Caption = "Then the wind changes."; CaptionStyle = "Big";
        }
        else if (t < 50f)
        {
            fire.speedUp = 1f;
            if (!released)
            {
                // the bush either side of the track goes up as he drives into it, and the sky stays red till the end
                released = true;
                fire.ReleaseHeld(dp.z + 3f);
                var fx = fire.GetComponent<FireFX>(); if (fx != null) fx.minIntensity = 1f;
            }
            // up the escape track
            float trackZ = dp.z + 4f;
            Vector3 aim = new Vector3(VoxelWorld.TrackCentreX(trackZ), 0f, trackZ);
            bool facingNorth = Mathf.Abs(Mathf.DeltaAngle(dozer.transform.eulerAngles.y, 0f)) < 20f;
            dozer.overrideSteer = facingNorth ? Steer(aim) : HeadingTo(0f);
            dozer.overrideBlade = 0f;
            float throttle = facingNorth ? 1f : 0.15f;
            // the first tree comes down across the track ahead of him; he shoves it aside
            if (!felled)
            {
                felled = true;
                int a = FireSim.TreeNear(new Vector3(VoxelWorld.TrackCentreX(39.5f) + 6f, 0f, 39.5f), 5f);
                if (a >= 0) { pushTree = a; fire.FellTree(a, fire.Now + 0.6f, Mathf.Atan2(-1f, -0.15f), false); }
                int c = FireSim.TreeNear(new Vector3(VoxelWorld.TrackCentreX(35f) - 6f, 0f, 35f), 5f);
                if (c >= 0) { behindTree = c; fire.FellTree(c, fire.Now + 6.5f, Mathf.Atan2(1f, 0.2f)); }
            }
            if (pushTree >= 0 && fire.HasFallen(pushTree))
            {
                Vector3 tp = FireSim.Trees[pushTree].at;
                if (pushStart < 0f && dp.z > tp.z - 4.5f) { pushStart = t; pushFrom = fire.FallAngle(pushTree); fire.Landed.Add(pushTree); }   // sparks as the blade hits it
                if (pushStart >= 0f)
                {
                    float k = Ease(pushStart, pushStart + 1.4f, t);
                    fire.SetFallAngle(pushTree, pushFrom - 1.2f * k);        // swung round, off the track
                    throttle = Mathf.Min(throttle, 0.45f + 0.55f * k);
                }
            }
            // then more come down in front of him and he's trapped
            if (!felled2 && t > 43.4f)
            {
                felled2 = true;
                int b1 = FireSim.TreeNear(new Vector3(VoxelWorld.TrackCentreX(46f) - 6f, 0f, 46f), 5f);
                if (b1 >= 0) fire.FellTree(b1, fire.Now, Mathf.Atan2(1f, 0.1f));
                int b2 = FireSim.TreeNear(new Vector3(VoxelWorld.TrackCentreX(44.5f) + 6f, 0f, 44.5f), 5f);
                if (b2 >= 0) fire.FellTree(b2, fire.Now + 1.1f, Mathf.Atan2(-1f, 0.15f));
            }
            dozer.overrideThrottle = throttle;
            if (t < 44.5f) Shot(dp - df * 9f + Vector3.up * 4.4f + dr * 1.5f, dp + df * 7f + Vector3.up * 1.4f);
            else Shot(dp + df * 10f + dr * 1.2f + Vector3.up * 2.6f, dp + Vector3.up * 1.6f);
            Caption = ""; CaptionStyle = "Big";
        }
        else if (t < 57f)
        {
            dozer.overrideThrottle = 0f; dozer.overrideSteer = 0f;
            Shot(dp + df * 11f + dr * 4f + Vector3.up * 2.4f, dp + Vector3.up * 1.6f);
            if (t < 53.5f) { Caption = "Dad!"; Caption2 = "a boy, somewhere in the smoke"; CaptionStyle = "Shout"; }
            else Caption = "";
            float red = Ease(52f, 54.5f, t), black = Ease(54.5f, 56.2f, t);
            Tint = Color.Lerp(new Color(0.55f, 0.02f, 0f, red * 0.85f), new Color(0f, 0f, 0f, 1f), black);
        }
        else if (t < 62f)
        {
            Tint = Color.black;
            Caption = "Twenty years later"; CaptionStyle = "Card";
            if (!settled) { settled = true; TwentyYearsOn(); }
        }
        else if (t < Length)
        {
            float fade = Ease(Length - 3.6f, Length - 1.6f, t);
            Tint = new Color(0f, 0f, 0f, Mathf.Max(1f - Ease(62f, 63.6f, t), fade));
            Caption = t > Length - 1.8f ? "Prologue  (rough cut)" : ""; CaptionStyle = "Small";
            // the son walks up the track, slowing as he comes up beside the dozer, and stops there
            Vector3 sp = wk.transform.position;
            if (!pastWaypoint && (new Vector2(waypoint.x - sp.x, waypoint.z - sp.z)).magnitude < 0.8f) pastWaypoint = true;
            Vector3 goal = pastWaypoint ? standAt : waypoint;
            Vector3 to = goal - sp; to.y = 0f;
            float dist = (new Vector2(standAt.x - sp.x, standAt.z - sp.z)).magnitude;
            float faceDozer = Mathf.Atan2(toDozer.x, toDozer.z) * Mathf.Rad2Deg;
            if (arriveT < 0f && pastWaypoint && to.magnitude < 0.25f) arriveT = t;
            if (arriveT < 0f)
            {
                wk.overrideWalk = Mathf.Lerp(0.3f, 0.6f, Mathf.InverseLerp(0.6f, 5f, dist));
                wk.Teleport(sp, Mathf.Atan2(to.x, to.z) * Mathf.Rad2Deg);
            }
            else
            {
                wk.overrideWalk = 0f;
                wk.Teleport(sp, Mathf.MoveTowardsAngle(wk.transform.eulerAngles.y, faceDozer, Time.deltaTime * 70f));
            }
            wk.handPoint = handAt;
            wk.handOn = arriveT >= 0f && t > arriveT + 1.8f;            // a moment looking up at the cab, then his hand on it
            Vector3 dir = to.sqrMagnitude > 0.01f ? to.normalized : Vector3.forward;
            Vector3 cab = dp + Vector3.up * 2.3f - df * 0.4f;
            if (arriveT < 0f && dist > 6f)
                Shot(sp - dir * 3.6f + Vector3.up * 1.75f + Vector3.Cross(Vector3.up, dir) * 0.7f, sp + dir * 8f + Vector3.up * 1.3f);   // behind him, walking
            else if (arriveT < 0f || t < arriveT + 1.2f)
                Shot(standAt - toDozer * 1.3f - df * 3.0f + Vector3.up * 1.2f, cab);                                       // low, behind him, up at the cab
            else
            {
                if (craneT <= 0f) craneT = Mathf.Clamp(arriveT + 5f, 75f, Length - 6.5f);
                // in over his shoulder to his hand on the dozer, then up above the trees
                float push = Ease(arriveT + 1.2f, craneT, t), up = Ease(craneT, Length - 1.6f, t);
                Vector3 right = new Vector3(toDozer.z, 0f, -toDozer.x);                // his right hand side
                Vector3 shoulder = Vector3.Lerp(sp - toDozer * 2.2f + right * 1.4f + Vector3.up * 1.9f, sp - toDozer * 1.5f + right * 0.85f + Vector3.up * 1.95f, push);
                Vector3 high = dp - df * 20f + Vector3.up * 22f;                       // up and back along the open track
                Vector3 look = Vector3.Lerp(Vector3.Lerp(handAt + Vector3.up * 0.3f, cab, 0.5f), dp + Vector3.up * 1.2f, up);
                Shot(Vector3.Lerp(shoulder, high, up), look);
            }
        }
        else
        {
            playing = false;
            wk.overrideWalk = 0f;
            wk.Civilian(false);
            if (follow != null) follow.enabled = true;
        }
    }

    void LateUpdate()
    {
        if (!playing || cam == null) return;
        cam.transform.SetPositionAndRotation(camPos, Quaternion.LookRotation(camLook - camPos, Vector3.up));
    }

    /// The world twenty years on: the fire long out (the burnt trees and fallen logs stay), the dozer rusted where it
    /// stopped, and the son at the foot of the track.
    void TwentyYearsOn()
    {
        fire.Settle();
        var fx = fire.GetComponent<FireFX>(); if (fx != null) { fx.minIntensity = 0f; fx.RestoreNow(); }
        // the bush has come back: resprouted gums and grey spars (the shader), bracken and young trees on the burnt
        // ground, and a clear morning a little brighter than before
        Shader.SetGlobalFloat("_Regrowth", 1f);
        SiteProps.ClearFallen();                                   // (the logs stay where they fell, but don't stop him)
        var props = FindFirstObjectByType<SiteProps>(); if (props != null) props.BuildRegrowth(fire, dozer.transform.position);
        var sun = RenderSettings.sun; if (sun != null) sun.intensity *= 1.12f;
        dozer.overrideThrottle = 0f; dozer.overrideSteer = 0f; dozer.overrideBlade = 0f;
        var block = new MaterialPropertyBlock();
        block.SetColor("_Color", new Color(0.55f, 0.33f, 0.22f));    // rust over the old yellow
        foreach (var r in dozer.GetComponentsInChildren<MeshRenderer>()) r.SetPropertyBlock(block);
        wk.GetOut();
        wk.useOverride = true;
        Vector3 start = new Vector3(VoxelWorld.TrackCentreX(26f), 0f, 26f);
        wk.Teleport(start, 0f);
        wk.SetEyes(false);
        wk.Civilian(true);
        // where he'll stop: beside the dozer, on whichever side has the flatter ground, level with the cab
        Vector3 dp = dozer.transform.position, df = dozer.transform.forward, dr = dozer.transform.right;
        var b = new Bounds(dp, Vector3.zero);
        foreach (var r in dozer.GetComponentsInChildren<MeshRenderer>()) b.Encapsulate(r.bounds);
        float halfW = Mathf.Clamp(Mathf.Abs(dr.x) * b.extents.x + Mathf.Abs(dr.z) * b.extents.z, 1.1f, 2.2f);
        var world = VoxelWorld.Instance;
        float best = 1e9f; int side = 1;
        for (int s2 = -1; s2 <= 1; s2 += 2)
        {
            Vector3 q = dp + dr * s2 * (halfW + 0.5f);
            float dy = world != null ? Mathf.Abs(world.FloorAt(q + Vector3.up * 2f) - dp.y) : 0f;
            if (dy < best - 0.05f) { best = dy; side = s2; }
        }
        toDozer = -dr * side;
        standAt = dp + dr * side * (halfW + 0.5f) - df * 0.4f;
        waypoint = standAt - df * 4f;
        handAt = standAt + toDozer * 0.75f + Vector3.up * 1.3f;
        if (world != null) { standAt.y = world.FloorAt(standAt + Vector3.up * 2f); handAt.y = standAt.y + 1.3f; }
    }

    void OnGUI()
    {
        if (!playing) return;
        if (Tint.a > 0.001f)
        {
            GUI.color = Tint;
            GUI.DrawTexture(new Rect(0, 0, Screen.width, Screen.height), Texture2D.whiteTexture);
            GUI.color = Color.white;
        }
        if (Caption.Length == 0) return;
        var big = new GUIStyle(GUI.skin.label) { fontSize = CaptionStyle == "Card" ? 40 : CaptionStyle == "Shout" ? 46 : CaptionStyle == "Small" ? 18 : 28, alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold };
        big.normal.textColor = Color.white;
        float y = CaptionStyle == "Card" ? Screen.height * 0.45f : CaptionStyle == "Place" ? Screen.height * 0.7f : Screen.height * 0.82f;
        if (Caption2.Length > 0 && CaptionStyle == "Shout")
        {
            var small = new GUIStyle(big) { fontSize = 18, fontStyle = FontStyle.Italic };
            GUI.Label(new Rect(0, y - 40, Screen.width, 30), Caption2, small);
        }
        GUI.Label(new Rect(0, y, Screen.width, 50), Caption, big);
        if (Caption2.Length > 0 && CaptionStyle == "Place")
        {
            var small = new GUIStyle(big) { fontSize = 20, fontStyle = FontStyle.Normal };
            GUI.Label(new Rect(0, y + 44, Screen.width, 30), Caption2, small);
        }
    }
}
