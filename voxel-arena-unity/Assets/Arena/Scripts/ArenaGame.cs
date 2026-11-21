// The round: waves of grunts, your health, the kills, and the HUD.
//
// Waves are Smashed's (godot/arcade/smash/smash_waves.gd), two waves to a "room":
//   wave 1, 2 = room 1;  3, 4 = room 2 ...
//   grunts in a wave:  10 + room x 9 + (1 or 2) x 6        (25, 31, 34, 40, 43 ...)
//   grunt speed:       2.3 + room x 0.22 (+ a little more past room 5, + 0.08 a wave), at most 5 m/s, give or take 15%
//   they come in bursts of 4 to 6 + room x 1.5 from one door at a time, 0.12 s apart, with a short gap between bursts.
// A wave is done when all its grunts are dead; 3 seconds' rest, then the next.
//
// A grunt touching you costs 1 of your 3 health.  As in Smashed, the grunts within 3 m of you go with it, and you
// can't be touched again for 2 seconds.  At 0 the round starts again from wave 1 on fresh ground.
using UnityEngine;

public class ArenaGame : MonoBehaviour
{
    public static ArenaGame Instance { get; private set; }

    public const float Half = 15.5f;                         // the inside faces of the walls, from the middle
    public const float DoorHalf = 1.5f;                      // the doors are 3 m wide, one in the middle of each wall
    public const float WallHeight = 3f;
    public const int StartHealth = 3;
    public const float Rest = 3f, SafeAfterHit = 2f, ClearOnHit = 3f;
    public const int MaxAlive = 60;

    [System.NonSerialized] public int Kills;
    public int Health { get; private set; } = StartHealth;
    public int Wave { get; private set; }
    public int Rounds { get; private set; }
    public int GruntsLeftToSpawn { get; private set; }
    public bool Playing { get { return overT <= 0f; } }
    public bool Resting { get { return restT > 0f; } }
    [Header("Tests")]
    public bool god;                                         // touches don't cost health
    public bool wavesOn = true;
    public int HitsTaken { get; private set; }

    int room, roomWave, burstLeft, burstDoor = -1;
    float spawnT, restT = 2f, overT, safeT, hurtFlash, hintT = 8f;
    int lastWaveKills, bestWave;

    void Awake()
    {
        Instance = this;
        Application.runInBackground = true;                  // (so play doesn't freeze when the window loses focus)
        Application.targetFrameRate = 120;
    }
    void OnDestroy() { if (Instance == this) Instance = null; }

    /// Wave n's room and wave-in-room, as Smashed counts them.
    static void RoomOf(int n, out int room, out int w) { room = (n + 1) / 2; w = (n - 1) % 2 + 1; }
    public static int GruntsInWave(int n) { int r, w; RoomOf(n, out r, out w); return 10 + r * 9 + w * 6; }

    float GruntSpeed()
    {
        return Mathf.Min(2.3f + room * 0.22f + Mathf.Max(0, room - 5) * 0.08f + roomWave * 0.08f, 5f) * Random.Range(0.85f, 1.15f);
    }

    public void StartWave(int n)
    {
        Wave = n;
        RoomOf(n, out room, out roomWave);
        GruntsLeftToSpawn = GruntsInWave(n);
        burstLeft = 0; spawnT = 0.3f; restT = 0f;
    }

    /// Everything back to the start: fresh ground, full health, no grunts, wave 1 in a moment.
    public void Restart()
    {
        var world = VoxelWorld.Instance;
        if (world != null) world.MakeGround();
        if (Grunts.Instance != null) Grunts.Instance.Clear();
        Gibs.Clear();
        if (Weapons.Instance != null) Weapons.Instance.Clear();
        if (ArenaPlayer.Instance != null) ArenaPlayer.Instance.Teleport(new Vector3(0f, 0f, -3f), 0f);
        Health = StartHealth; Kills = 0; Wave = 0; GruntsLeftToSpawn = 0;
        restT = 2f; overT = 0f; safeT = 0f;
        Rounds++;
    }

    int SpawnDoor()
    {
        // a different door from the last burst's, and not the one he is standing right by
        var pl = ArenaPlayer.Instance;
        for (int tries = 0; tries < 8; tries++)
        {
            int d = Random.Range(0, 4);
            if (d == burstDoor) continue;
            if (pl != null)
            {
                Vector2 n = Grunts.DoorN[d];
                Vector2 doorAt = -n * Half;
                if ((new Vector2(pl.transform.position.x, pl.transform.position.z) - doorAt).sqrMagnitude < 25f) continue;
            }
            return d;
        }
        return (burstDoor + 1) % 4;
    }

    void Update()
    {
        float dt = Time.deltaTime;
        var g = Grunts.Instance;
        var pl = ArenaPlayer.Instance;
        if (hintT > 0f) hintT -= dt;
        if (hurtFlash > 0f) hurtFlash -= dt;
        if (overT > 0f)
        {
            overT -= dt;
            if (overT <= 0f) Restart();
            return;
        }
        // ---- the waves
        if (wavesOn && g != null)
        {
            if (restT > 0f)
            {
                restT -= dt;
                if (restT <= 0f) StartWave(Wave + 1);
            }
            else if (Wave > 0)
            {
                spawnT -= dt;
                while (spawnT <= 0f && GruntsLeftToSpawn > 0 && g.Count < MaxAlive)
                {
                    if (burstLeft <= 0) { burstDoor = SpawnDoor(); burstLeft = Random.Range(4, 6 + room * 3 / 2 + 1); }
                    g.Spawn(burstDoor, Random.Range(0.5f, 2.5f), GruntSpeed());
                    GruntsLeftToSpawn--;
                    burstLeft--;
                    spawnT += burstLeft > 0 ? 0.12f : Random.Range(0.5f, 1.1f) / (1f + room * 0.18f);
                }
                if (GruntsLeftToSpawn == 0 && g.Count == 0) { restT = Rest; lastWaveKills = Kills; bestWave = Mathf.Max(bestWave, Wave); }
            }
        }
        // ---- the grunts, and whether one got you
        if (g != null && pl != null)
        {
            if (safeT > 0f) safeT -= dt;
            bool touched = g.Step(dt, pl.transform.position, ArenaPlayer.BodyRadius + Grunts.Radius);
            if (touched && safeT <= 0f)
            {
                HitsTaken++;
                if (!god) Health--;
                safeT = SafeAfterHit;
                hurtFlash = 0.5f;
                g.KillRadius(pl.transform.position + Vector3.up * 0.2f, ClearOnHit);   // whatever got you goes with you
                GameAudio.PlayAt("hurt", pl.transform.position, 1f);
                FollowCamera.Bump(0.25f);
                if (Health <= 0) { overT = 3.5f; bestWave = Mathf.Max(bestWave, Wave); }
            }
        }
    }

    // ---------------------------------------------------------------- the HUD (small and clean, like the Digger Game's)
    GUIStyle big, small, mid;

    void OnGUI()
    {
        Ui.Begin();
        if (big == null)
        {
            big = new GUIStyle(GUI.skin.label) { fontSize = 30, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            mid = new GUIStyle(GUI.skin.label) { fontSize = 22, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            small = new GUIStyle(GUI.skin.label) { fontSize = 18, fontStyle = FontStyle.Bold };
            big.normal.textColor = mid.normal.textColor = small.normal.textColor = new Color(0.95f, 0.95f, 0.95f);
        }
        float W = Ui.W, H = Ui.H;
        // top left: health and kills
        GUI.Box(new Rect(14f, 14f, 196f, 70f), "");
        GUI.Label(new Rect(26f, 20f, 80f, 26f), "Health", small);
        for (int i = 0; i < StartHealth; i++)
        {
            var r = new Rect(104f + i * 32f, 24f, 24f, 18f);
            Ui.Fill(r, i < Health ? new Color(0.9f, 0.18f, 0.14f) : new Color(0.25f, 0.25f, 0.27f));
        }
        GUI.Label(new Rect(26f, 50f, 180f, 26f), "Kills   " + Kills, small);
        // top middle: the wave
        GUI.Box(new Rect(W * 0.5f - 90f, 14f, 180f, 44f), "");
        string wave = Wave == 0 ? "Get ready" : "Wave " + Wave;
        GUI.Label(new Rect(W * 0.5f - 90f, 14f, 180f, 44f), wave, mid);
        if (Resting && Wave > 0 && Playing)
            GUI.Label(new Rect(W * 0.5f - 160f, 62f, 320f, 30f), "Wave " + Wave + " cleared.  Next in " + Mathf.CeilToInt(restT), small.Centered());
        // the cross over the shoulder
        var pl = ArenaPlayer.Instance;
        if (pl != null && !pl.Above && Playing)
        {
            float cx = W * 0.5f, cy = H * 0.5f;
            var c = new Color(1f, 1f, 1f, 0.85f);
            Ui.Fill(new Rect(cx - 10f, cy - 1f, 7f, 2f), c); Ui.Fill(new Rect(cx + 3f, cy - 1f, 7f, 2f), c);
            Ui.Fill(new Rect(cx - 1f, cy - 10f, 2f, 7f), c); Ui.Fill(new Rect(cx - 1f, cy + 3f, 2f, 7f), c);
        }
        if (hintT > 0f && Playing)
            GUI.Label(new Rect(W * 0.5f - 300f, H - 52f, 600f, 30f), Pad.InUse ? "Back  switch view      RT  rifle      LT  rocket" : "Tab  switch view      Left mouse  rifle      Right mouse  rocket", small.Centered());
        if (hurtFlash > 0f) Ui.Fill(new Rect(0f, 0f, W, H), new Color(0.8f, 0.05f, 0.05f, hurtFlash * 0.5f));
        if (!Playing)
        {
            GUI.Box(new Rect(W * 0.5f - 220f, H * 0.5f - 60f, 440f, 110f), "");
            GUI.Label(new Rect(W * 0.5f - 220f, H * 0.5f - 56f, 440f, 50f), "Round over", big);
            GUI.Label(new Rect(W * 0.5f - 220f, H * 0.5f - 8f, 440f, 40f), "Wave " + Wave + "     " + Kills + " kills     Starting again", small.Centered());
        }
    }
}

static class StyleExt
{
    public static GUIStyle Centered(this GUIStyle s) { return new GUIStyle(s) { alignment = TextAnchor.MiddleCenter }; }
}
