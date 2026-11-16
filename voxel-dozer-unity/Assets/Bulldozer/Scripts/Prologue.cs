// The prologue (rough cut): the bushfire that took the old mine, played in the real game.
//
//   0-7 s    over the hill and the mine, smoke far off                "The high country, Victoria..."
//   7-17     Dad cuts a firebreak across the hilltop with the dozer   (the real blade scrapes it bare: the fire can't cross it)
//   17-28    the fire front arrives beyond the break; it holds
//   28-38    the wind changes: embers jump the break, spot fires start behind him
//   38-50    he turns up the escape track; a burning tree falls across it and he shoves it aside;
//            two or three more come down in front and behind, and he's trapped
//   50-57    "Dad!", then red, then black
//   57-62    "Twenty years later"
//   62-80    the son walks up the track to the rusted dozer, among the black trunks and fallen logs
//
// Start it with Prologue.Play().  It drives the dozer, the worker, the fire and the camera itself, hides the game's
// HUD, and draws its own captions and the red and black (RecordPrologue films the same thing).
using UnityEngine;

public class Prologue : MonoBehaviour
{
    public static Prologue Instance { get; private set; }
    public static bool Playing { get { return Instance != null && Instance.playing; } }
    public const float Length = 80f;

    // what's on screen besides the picture (read by the recorder too)
    public string Caption = "", CaptionStyle = "Big", Caption2 = "";
    public Color Tint = Color.clear;
    public float T { get; private set; }

    bool playing;
    float t0;
    DozerController dozer; Worker wk; FireSim fire; Camera cam; FollowCamera follow;
    int pushTree = -1, behindTree = -1;
    float pushFrom, pushStart = -1f;
    bool cutCleared, settled, changed, felled, felled2;
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
            Tint = new Color(0f, 0f, 0f, 1f - Ease(62f, 63.6f, t));
            Caption = t > 74f ? "Prologue  (rough cut)" : ""; CaptionStyle = "Small";
            // the son walks up the track to the dozer
            Vector3 sp = wk.transform.position, to = dp - sp; to.y = 0f;
            bool there = to.magnitude < 5.5f;
            wk.overrideWalk = there ? 0f : 1f;
            if (!there) wk.Teleport(sp, Mathf.Atan2(to.x, to.z) * Mathf.Rad2Deg);
            Vector3 dir = to.sqrMagnitude > 0.01f ? to.normalized : Vector3.forward;
            if (t < 71f) Shot(sp - dir * 3.6f + Vector3.up * 1.75f + Vector3.Cross(Vector3.up, dir) * 0.7f, sp + dir * 8f + Vector3.up * 1.3f);
            else
            {
                Vector3 mid = (sp + dp) * 0.5f;
                float ang = Mathf.Atan2(-dir.x, -dir.z) - Ease(71f, Length, t) * 1.3f;
                Shot(mid + new Vector3(Mathf.Sin(ang), 0f, Mathf.Cos(ang)) * 5.5f + Vector3.up * 2.8f, mid + Vector3.up * 1.2f);
            }
        }
        else
        {
            playing = false;
            wk.overrideWalk = 0f;
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
        var fx = fire.GetComponent<FireFX>(); if (fx != null) fx.RestoreNow();
        dozer.overrideThrottle = 0f; dozer.overrideSteer = 0f; dozer.overrideBlade = 0f;
        var block = new MaterialPropertyBlock();
        block.SetColor("_Color", new Color(0.55f, 0.33f, 0.22f));    // rust over the old yellow
        foreach (var r in dozer.GetComponentsInChildren<MeshRenderer>()) r.SetPropertyBlock(block);
        wk.GetOut();
        wk.useOverride = true;
        Vector3 start = new Vector3(VoxelWorld.TrackCentreX(26f), 0f, 26f);
        wk.Teleport(start, 0f);
        wk.SetEyes(false);
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
