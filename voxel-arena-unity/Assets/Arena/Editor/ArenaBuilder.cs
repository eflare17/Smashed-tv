// Builds the arena scene, runs its tests, records its clip, builds the Windows game.
//   -executeMethod ArenaBuilder.BuildScene      the scene (Assets/Arena/Arena.unity)
//   -executeMethod ArenaBuilder.Test            the checks (exit 0 when they all pass, 1 when any fails)
//   -executeMethod ArenaBuilder.RecordClip      frames, captions and sound into Logs/clip (ffmpeg makes the video)
//   -executeMethod ArenaBuilder.BuildWindows    Builds/VoxelArena3/VoxelArena.exe
// (Copied in spirit from the Digger Game's BulldozerBuilder; nothing here touches the Digger Game.)
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.PostProcessing;

[InitializeOnLoad]
public static class ArenaBuilder
{
    const string Dir = "Assets/Arena";
    const string ScenePath = Dir + "/Arena.unity";

    static ArenaBuilder()
    {
        EditorApplication.delayCall += () =>
        {
            if (!Application.isBatchMode && AssetDatabase.LoadAssetAtPath<SceneAsset>(ScenePath) == null) BuildScene();
        };
    }

    public static void BuildSceneFromCommandLine() { AssetDatabase.Refresh(); bool ok = BuildScene(); EditorApplication.Exit(ok ? 0 : 1); }

    [MenuItem("Tools/Arena/Rebuild scene")]
    public static bool BuildScene()
    {
        var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);
        var voxelShader = Shader.Find("Voxel/Terrain");
        if (voxelShader == null) { Debug.LogError("ARENA_BUILD_FAILED Voxel/Terrain shader not found"); return false; }
        var standard = Shader.Find("Standard");
        var voxelMat = MakeMaterial(Dir + "/VoxelGround.mat", voxelShader, Color.white);
        voxelMat.SetFloat("_FixedMat", -1f);
        var worldGo = new GameObject("VoxelWorld");
        worldGo.AddComponent<VoxelWorld>().material = voxelMat;
        worldGo.AddComponent<SceneLook>().shadowDistance = 70f;

        // plain ground round the voxel square (the corridors behind the doors stand on it), drawn as topsoil
        var groundMat = MakeMaterial(Dir + "/OutsideGround.mat", voxelShader, Color.white);
        groundMat.SetFloat("_FixedMat", 1f);
        var surround = new GameObject("Outside ground").transform;
        float g = VoxelWorld.SiteHalf, far = 120f;
        MakeGroundPlane(surround, groundMat, -far, far, g, far);
        MakeGroundPlane(surround, groundMat, -far, far, -far, -g);
        MakeGroundPlane(surround, groundMat, g, far, -g, g);
        MakeGroundPlane(surround, groundMat, -far, -g, -g, g);

        // the walls: 3 m high, 1 m thick, a 3 m door in the middle of each, and a short corridor behind each door
        var wallMat = MakeMaterial(Dir + "/Wall.mat", standard, new Color(0.56f, 0.55f, 0.53f));
        var capMat = MakeMaterial(Dir + "/WallCap.mat", standard, new Color(0.78f, 0.36f, 0.12f));
        var walls = new GameObject("Walls").transform;
        float h = ArenaGame.Half, dh = ArenaGame.DoorHalf, wh = ArenaGame.WallHeight, t = 1f, corridor = 4f;
        for (int side = 0; side < 4; side++)
        {
            // side 0 south (z = -h), 1 north, 2 west (x = -h), 3 east
            float s = side % 2 == 0 ? -1f : 1f;
            bool alongX = side < 2;
            float lineAt = s * (h + t * 0.5f);
            float segLen = h + t - dh, segMid = dh + segLen * 0.5f;
            for (int k = -1; k <= 1; k += 2)
            {
                Vector3 c = alongX ? new Vector3(k * segMid, wh * 0.5f, lineAt) : new Vector3(lineAt, wh * 0.5f, k * segMid);
                Vector3 size = alongX ? new Vector3(segLen, wh, t) : new Vector3(t, wh, segLen);
                MakeBox(walls, wallMat, c, size, "Wall");
                MakeBox(walls, capMat, c + Vector3.up * (wh * 0.5f + 0.06f), size + new Vector3(0.06f, 0.12f, 0.06f) - Vector3.up * (wh - 0.0f), "Cap");
                // the corridor's side walls
                float across = k * (dh + 0.25f), outMid = s * (h + t + corridor * 0.5f);
                Vector3 cc = alongX ? new Vector3(across, wh * 0.5f, outMid) : new Vector3(outMid, wh * 0.5f, across);
                Vector3 cs = alongX ? new Vector3(0.5f, wh, corridor) : new Vector3(corridor, wh, 0.5f);
                MakeBox(walls, wallMat, cc, cs, "Corridor");
            }
            // the corridor's end wall
            float endAt = s * (h + t + corridor + 0.25f);
            MakeBox(walls, wallMat, alongX ? new Vector3(0f, wh * 0.5f, endAt) : new Vector3(endAt, wh * 0.5f, 0f), alongX ? new Vector3(dh * 2f + 1f, wh, 0.5f) : new Vector3(0.5f, wh, dh * 2f + 1f), "Corridor end");
        }

        // ---- daylight: a high sun, clear sky, light haze (the Digger Game's look, at midday)
        var sunGo = GameObject.Find("Directional Light");
        Light sun = sunGo != null ? sunGo.GetComponent<Light>() : null;
        if (sun != null)
        {
            sunGo.transform.rotation = Quaternion.Euler(52f, -35f, 0f);
            sun.color = new Color(1f, 0.96f, 0.88f);
            sun.intensity = 1.25f;
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.8f;
            sun.shadowBias = 0.03f;
            sun.shadowNormalBias = 0.5f;
        }
        AssetDatabase.DeleteAsset(Dir + "/Sky.mat");
        var sky = new Material(Shader.Find("Skybox/Procedural"));
        sky.SetFloat("_SunSize", 0.04f);
        sky.SetFloat("_AtmosphereThickness", 0.9f);
        sky.SetFloat("_Exposure", 1.2f);
        sky.SetColor("_SkyTint", new Color(0.40f, 0.52f, 0.70f));
        sky.SetColor("_GroundColor", new Color(0.55f, 0.46f, 0.36f));
        AssetDatabase.CreateAsset(sky, Dir + "/Sky.mat");
        RenderSettings.skybox = sky;
        RenderSettings.sun = sun;
        RenderSettings.ambientMode = AmbientMode.Trilight;
        RenderSettings.ambientSkyColor = new Color(0.62f, 0.70f, 0.84f);
        RenderSettings.ambientEquatorColor = new Color(0.60f, 0.56f, 0.50f);
        RenderSettings.ambientGroundColor = new Color(0.36f, 0.31f, 0.26f);
        RenderSettings.fog = true;
        RenderSettings.fogMode = FogMode.ExponentialSquared;
        RenderSettings.fogColor = new Color(0.82f, 0.80f, 0.74f);
        RenderSettings.fogDensity = 0.006f;

        var cam = Camera.main;
        if (cam == null) { Debug.LogError("ARENA_BUILD_FAILED no camera"); return false; }
        SetUpPostProcessing(cam);
        cam.gameObject.AddComponent<FollowCamera>();
        cam.transform.position = new Vector3(0f, 3f, -8f);
        cam.farClipPlane = 300f;

        var game = new GameObject("Arena");
        game.AddComponent<ArenaGame>();
        game.AddComponent<GameAudio>();
        game.AddComponent<Grunts>();
        game.AddComponent<Gibs>();
        game.AddComponent<Weapons>();
        var player = new GameObject("Player");
        player.AddComponent<ArenaPlayer>();
        player.transform.position = new Vector3(0f, 0f, -3f);

        EditorSceneManager.SaveScene(scene, ScenePath);
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
        AssetDatabase.SaveAssets();
        Debug.Log("ARENA_BUILD_OK");
        return true;
    }

    [MenuItem("Tools/Arena/Play")]
    public static void Play()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorApplication.delayCall += () =>
        {
            EditorApplication.ExecuteMenuItem("Window/General/Game");
            var gv = EditorWindow.focusedWindow;
            if (gv != null) gv.maximized = true;
            EditorApplication.EnterPlaymode();
        };
    }

    // ================================================================== the tests
    // Each check is logged as name=ok or name=FAIL; the editor exits 1 if any failed (or it timed out).
    static int tPhase; static float tT0; static double tStart; static string tLog; static bool tOk;
    static long tBooks0, tSolidBefore; static int tMaxClods, tKills0, tHits0, tFrames; static float tFrameSum, tFrameMax, tStepSum;
    static Vector3 tCrater; static int tShots0, tRounds0;

    public static void Test()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        tPhase = 0; tLog = ""; tOk = true; tMaxClods = 0;
        tStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += TestTick;
        EditorApplication.EnterPlaymode();
    }

    static void Check(bool ok, string what) { tLog += " " + what + "=" + (ok ? "ok" : "FAIL"); if (!ok) tOk = false; Debug.Log("ARENA_CHECK " + what + " " + (ok ? "ok" : "FAIL")); }

    static void TestFinish()
    {
        EditorApplication.update -= TestTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        if (tOk) Debug.Log("ARENA_TEST_RESULT" + tLog); else Debug.LogError("ARENA_TEST_FAILED phase " + tPhase + tLog);
        EditorApplication.Exit(tOk ? 0 : 1);
    }

    static long Books(VoxelWorld w) { return w.SolidCount + w.LoadVoxels; }
    static void Next(int p) { tPhase = p; tT0 = Time.time; }

    static void TestTick()
    {
        if (EditorApplication.timeSinceStartup - tStart > 420) { Check(false, "timedOut"); TestFinish(); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var game = ArenaGame.Instance; var pl = ArenaPlayer.Instance; var g = Grunts.Instance; var wp = Weapons.Instance;
        if (w == null || game == null || pl == null || g == null || wp == null) return;
        float t = Time.time, k = t - tT0;
        tMaxClods = Mathf.Max(tMaxClods, w.ClodCount);
        switch (tPhase)
        {
            case 0:
                game.wavesOn = false; game.god = true;               // (from the first frame, so wave 1 doesn't start by itself)
                if (t < 2f) return;
                g.Clear();
                pl.useOverride = true; pl.overrideMove = Vector2.zero;
                pl.Teleport(new Vector3(0f, 0f, -3f), 0f);
                tLog += " groundMB=" + (w.GridBytes / 1048576f).ToString("F1");
                Check(w.GridBytes < 100L * 1048576L, "groundUnder100MB");
                Check(Books(w) == w.StartTotal, "booksAtStart");
                Next(1); return;

            // ---- 1. a rocket makes a crater, and no dirt is made or lost
            case 1:
                pl.overrideAim = new Vector3(0f, 0f, 4f);
                if (k < 0.5f) return;
                tBooks0 = Books(w); tSolidBefore = w.SolidCount; tMaxClods = 0;
                pl.queuedRockets = 1;
                Next(2); return;
            case 2:
                pl.overrideAim = new Vector3(0f, 0f, 4f);
                if (wp.Blasts < 1) { if (k > 3f) { Check(false, "rocketWentOff"); TestFinish(); } return; }
                if (k < 9f && w.ClodCount > 0) return;                  // the dirt flies, lands, settles
                tCrater = wp.LastBlast;
                float deep = w.MinHeightIn(tCrater.x - 0.4f, tCrater.z - 0.4f, tCrater.x + 0.4f, tCrater.z + 0.4f);
                tLog += " blastAt=" + tCrater.ToString("F1") + " voxelsBlown=" + wp.LastBlastVoxels + " peakClods=" + tMaxClods + " craterBottom=" + deep.ToString("F2") + "m clodsLeft=" + w.ClodCount;
                Check(wp.LastBlastVoxels > 8000, "rocketBlewOutGround");
                Check(tMaxClods > 500, "dirtThrownAsClods");
                Check(deep < -0.5f, "craterDeeperThanHalfMetre");
                long now = Books(w), recount = w.CountSolid() + w.LoadVoxels;
                tLog += " books=" + tBooks0 + "->" + now + " recount=" + recount;
                Check(now == tBooks0 && recount == w.StartTotal, "dirtVolumeExact");
                Next(3); return;

            // ---- 2. bullets: one kills a grunt; shots at the ground chip it (books still exact)
            case 3:
                if (k < 0.05f) { g.Clear(); tFrames = 0; tKills0 = game.Kills; tShots0 = wp.RifleShots; g.SpawnInside(new Vector3(7f, 0f, -3f), 0f, true); return; }
                if (g.Count > 0) pl.overrideAim = g.Position(0) + Vector3.up * 1f;
                if (k > 0.3f && tFrames == 0) { pl.queuedRifle = 1; tFrames = 1; }   // one shot
                if (k < 1.2f) return;
                tLog += " gruntsLeft=" + g.Count + " kills=" + (game.Kills - tKills0) + " gibs=" + Gibs.Made;
                Check(g.Count == 0 && game.Kills - tKills0 == 1 && wp.RifleShots - tShots0 == 1, "oneBulletKillsAGrunt");
                Check(Gibs.Made >= Grunts.GibsEach, "gruntBurstIntoGibs");
                tSolidBefore = w.SolidCount;
                Next(4); return;
            case 4:
                pl.overrideAim = new Vector3(-5f, 0f, -7f);
                pl.overrideRifle = k < 1.3f;
                if (k < 5f) return;
                pl.overrideRifle = false;
                tLog += " rifleShots=" + wp.RifleShots + " chipped=" + (tSolidBefore - w.SolidCount);
                Check(wp.RifleShots >= 9, "rifleFiresAbout8ASecond");
                Check(w.MinHeightIn(-5.3f, -7.3f, -4.7f, -6.7f) < -0.05f, "bulletsChipTheGround");
                Check(Books(w) == w.StartTotal && w.CountSolid() + w.LoadVoxels == w.StartTotal, "dirtVolumeExactAfterChips");
                Next(5); return;

            // ---- 3. a grunt runs through the crater (down in and out again) to reach him
            case 5:
                if (k < 0.05f)
                {
                    pl.Teleport(new Vector3(tCrater.x, 0f, tCrater.z + 6f), 180f);
                    g.Clear(); g.ResetLowest(); tHits0 = game.HitsTaken;
                    g.SpawnInside(new Vector3(tCrater.x, 0f, tCrater.z - 6f), 2.6f, true);
                    return;
                }
                pl.overrideAim = pl.transform.position + Vector3.forward * -5f;
                if (game.HitsTaken == tHits0 && k < 15f) return;
                tLog += " gruntLowestY=" + g.LowestY.ToString("F2") + " reachedIn=" + k.ToString("F1") + "s";
                Check(g.LowestY < -0.4f, "gruntWentDownIntoCrater");
                Check(game.HitsTaken > tHits0, "gruntClimbedOutAndReachedHim");
                Next(6); return;

            // ---- 4. a real wave: grunts come in the doors and reach him (it costs health)
            case 6:
                if (k < 0.05f) { game.god = false; game.Restart(); game.wavesOn = true; tHits0 = game.HitsTaken; pl.overrideAim = new Vector3(0f, 1f, 10f); return; }
                if (game.HitsTaken == tHits0 && k < 40f) return;
                tLog += " wave=" + game.Wave + " health=" + game.Health + " firstTouchAt=" + k.ToString("F1") + "s";
                Check(game.Wave == 1 && game.HitsTaken > tHits0, "waveReachesPlayer");
                Check(game.Health == ArenaGame.StartHealth - 1, "touchCostsOneHealth");
                Next(7); return;
            case 7:
                // let him be touched until the round restarts
                if (k < 0.05f) { tRounds0 = game.Rounds; return; }
                if (game.Rounds == tRounds0 && k < 90f) return;
                tLog += " rounds=" + game.Rounds + " hits=" + game.HitsTaken + " healthAfter=" + game.Health + " waveAfter=" + game.Wave + " after=" + k.ToString("F1") + "s";
                Check(game.Rounds > tRounds0 && game.Health == ArenaGame.StartHealth && game.Wave <= 1, "roundRestartsAtZeroHealth");
                Next(8); return;

            // ---- 5. frame time with 30 grunts on the field
            case 8:
                if (k < 0.05f)
                {
                    game.wavesOn = false; game.god = true;
                    g.Clear();
                    pl.Teleport(Vector3.zero, 0f);
                    for (int i = 0; i < 30; i++)
                    {
                        float a = i / 30f * Mathf.PI * 2f;
                        g.SpawnInside(new Vector3(Mathf.Sin(a) * 13.5f, 0f, Mathf.Cos(a) * 13.5f), 2.6f);
                    }
                    tFrames = 0; tFrameSum = 0f; tFrameMax = 0f; tStepSum = 0f;
                    return;
                }
                if (k < 0.5f) return;
                pl.overrideAim = new Vector3(0f, 0f, 6f);
                tFrames++; tFrameSum += Time.unscaledDeltaTime * 1000f; tFrameMax = Mathf.Max(tFrameMax, Time.unscaledDeltaTime * 1000f); tStepSum += g.LastStepMs;
                if (k < 3.5f) return;
                float avg = tFrameSum / Mathf.Max(1, tFrames);
                tLog += " gruntsOnField=" + g.Count + " frames=" + tFrames + " avgFrameMs=" + avg.ToString("F1") + " maxFrameMs=" + tFrameMax.ToString("F1") + " gruntStepMs=" + (tStepSum / Mathf.Max(1, tFrames)).ToString("F3");
                Check(avg < 25f, "frameTimeOkWith30Grunts");
                Check(tStepSum / Mathf.Max(1, tFrames) < 1f, "gruntUpdateUnder1ms");
                Next(9); return;
            case 9:
                if (k < 0.3f) return;
                TestCapture("arena_test.png");
                TestFinish(); return;
        }
    }

    static void TestCapture(string file)
    {
        var cam = Camera.main;
        if (cam == null) return;
        var rt = new RenderTexture(1280, 720, 24);
        cam.targetTexture = rt;
        cam.Render();
        RenderTexture.active = rt;
        var tex = new Texture2D(1280, 720, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, 1280, 720), 0, 0);
        tex.Apply();
        cam.targetTexture = null;
        RenderTexture.active = null;
        System.IO.Directory.CreateDirectory(Application.dataPath + "/../Logs");
        System.IO.File.WriteAllBytes(Application.dataPath + "/../Logs/" + file, tex.EncodeToPNG());
    }

    // ================================================================== the clip
    // Frames to Logs/clip at 30 a second, captions to Logs/clip/overlay.ass, the sound to Logs/clip/sound.wav
    // (Unity's AudioRenderer, in step with the frames).  ffmpeg puts them together.
    static int cSeg, cSegFrame, cFrame, cEnd, cLastGameFrame;
    static readonly List<float> cSound = new List<float>();
    static readonly List<string> cOverlay = new List<string>();
    static float cStrafe; static int cShots;

    public static void RecordClip()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        cSeg = -1; cShots = 0; cFrame = 0; cEnd = 0; cSound.Clear(); cOverlay.Clear(); cLastGameFrame = -1;
        string dir = Application.dataPath + "/../Logs/clip";
        System.IO.Directory.CreateDirectory(dir);
        foreach (var f in System.IO.Directory.GetFiles(dir)) { try { System.IO.File.Delete(f); } catch (System.Exception) { } }
        tStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += ClipTick;
        EditorApplication.EnterPlaymode();
    }

    static void ClipFinish(int code)
    {
        EditorApplication.update -= ClipTick;
        Time.captureFramerate = 0;
        try { AudioRenderer.Stop(); } catch (System.Exception) { }
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static void Seg(int s) { cSeg = s; cSegFrame = cFrame; }

    /// The bot: the nearest grunt, and how many stand close round it.
    static int Nearest(Grunts g, Vector3 from, out int crowd)
    {
        int best = -1; float bd = 1e9f; crowd = 0;
        for (int i = 0; i < g.Count; i++) { float d = (g.Position(i) - from).sqrMagnitude; if (d < bd) { bd = d; best = i; } }
        if (best >= 0) for (int i = 0; i < g.Count; i++) if ((g.Position(i) - g.Position(best)).sqrMagnitude < 9f) crowd++;
        return best;
    }

    static void ClipTick()
    {
        if (EditorApplication.timeSinceStartup - tStart > 900) { Debug.LogError("ARENA_CLIP_FAILED timed out in " + cSeg); ClipFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var game = ArenaGame.Instance; var pl = ArenaPlayer.Instance; var g = Grunts.Instance; var wp = Weapons.Instance;
        if (w == null || game == null || pl == null || g == null || wp == null) return;
        if (Time.frameCount == cLastGameFrame) return;
        cLastGameFrame = Time.frameCount;
        if (cEnd > 0)
        {
            if (--cEnd == 0)
            {
                WriteOverlay();
                int ch = AudioSettings.speakerMode == AudioSpeakerMode.Mono ? 1 : 2;
                WriteWav(Application.dataPath + "/../Logs/clip/sound.wav", cSound, AudioSettings.outputSampleRate, ch);
                Debug.Log("ARENA_CLIP_OK frames=" + cFrame + " soundSeconds=" + (cSound.Count / (float)ch / AudioSettings.outputSampleRate).ToString("F1"));
                ClipFinish(0);
            }
            return;
        }
        if (cSeg == -1)
        {
            game.wavesOn = false;                                // (from the first frame: the clip starts wave 1 itself)
            if (Time.realtimeSinceStartup < 3f || Time.timeSinceLevelLoad < 2.5f) return;
            GameViewSize(1280, 720);
            game.wavesOn = false; game.god = true;
            pl.useOverride = true;
            pl.Teleport(new Vector3(-2f, 0f, -9f), 20f);
            for (int i = 0; i < 4; i++) g.SpawnInside(new Vector3(-1f + i * 2.2f, 0f, 9f + (i % 2) * 2f), 1.6f);
            Time.captureFramerate = 30;
            AudioRenderer.Start();
            Seg(0);
            return;
        }
        float k = (cFrame - cSegFrame) / 30f;
        string title = "", cap = "";
        pl.overrideRifle = pl.overrideRocket = false;
        pl.overrideMove = Vector2.zero;
        int crowd;
        if (cSeg == 0)
        {
            // over the shoulder: chip the ground, then pick off the grunts walking in
            title = "Over the shoulder";
            if (k < 2.2f)
            {
                cap = "The rifle chips the ground: every hit takes out a bit of dirt";
                pl.overrideAim = new Vector3(-1.2f + Mathf.Sin(k * 3f) * 1.5f, 0f, -3.5f + k * 1.2f);
                pl.overrideRifle = true;
            }
            else
            {
                cap = "Smashed's grunts: one bullet each";
                int n = Nearest(g, pl.transform.position, out crowd);
                pl.overrideAim = n >= 0 ? g.Position(n) + Vector3.up * 1.0f : new Vector3(0f, 1f, 6f);
                pl.overrideRifle = n >= 0 && k > 2.6f;
            }
            if (k > 6f) { g.Clear(); Seg(1); }
        }
        else if (cSeg == 1)
        {
            title = "Rockets blow real holes";
            cap = k < 3f ? "Right mouse: a rocket, a crater, the dirt thrown out" : "It lands, rolls and settles. Not a crumb is made or lost";
            pl.overrideAim = k < 2.5f ? new Vector3(0.5f, 0f, -2f) : new Vector3(3.5f, 0f, -1.5f);
            if (k > 0.4f && cShots == 0) { pl.queuedRockets = 1; cShots = 1; }
            if (k > 2.6f && cShots == 1) { pl.queuedRockets = 1; cShots = 2; }
            if (k > 6.5f) { pl.SetAbove(true); game.wavesOn = true; game.StartWave(1); Seg(2); }
        }
        else if (cSeg == 2)
        {
            // from above, like Smashed: wave 1 comes through the doors; the bot strafes and fights
            title = "Tab: from above, like Smashed";
            cap = k < 5f ? "Wave 1: 25 grunts in bursts through the four doors" : k < 11f ? "They run at you over the dug-up ground, down into craters and out" : "Rockets for the crowds, the rifle for the rest";
            int n = Nearest(g, pl.transform.position, out crowd);
            cStrafe += 1f / 30f;
            Vector3 p = pl.transform.position;
            Vector2 toMid = new Vector2(-p.x, -p.z) * 0.08f;
            pl.overrideMove = new Vector2(Mathf.Cos(cStrafe * 0.9f), Mathf.Sin(cStrafe * 0.9f)) * 0.6f + toMid;
            if (n >= 0)
            {
                Vector3 at = g.Position(n);
                pl.overrideAim = at + Vector3.up * 1.0f;
                float dist = Vector3.Distance(at, p);
                pl.overrideRifle = dist < 14f;
                pl.overrideRocket = crowd >= 4 && dist > 4.5f && dist < 13f;
                if (pl.overrideRocket) pl.overrideAim = new Vector3(at.x, w.FloorAt(at + Vector3.up), at.z);
            }
            else pl.overrideAim = p + Vector3.forward * 5f;
            if (k > 20f) { cEnd = 3; return; }
        }
        // the sound for this frame
        int ns = AudioRenderer.GetSampleCountForCaptureFrame();
        int chs = AudioSettings.speakerMode == AudioSpeakerMode.Mono ? 1 : 2;
        if (ns > 0)
        {
            var buf = new Unity.Collections.NativeArray<float>(ns * chs, Unity.Collections.Allocator.Temp);
            if (AudioRenderer.Render(buf)) for (int i = 0; i < buf.Length; i++) cSound.Add(buf[i]);
            buf.Dispose();
        }
        string at2 = AssTime(cFrame / 30f) + "," + AssTime((cFrame + 1) / 30f);
        if (title.Length > 0) cOverlay.Add("Dialogue: 0," + at2 + ",Title,,0,0,0,," + title);
        if (cap.Length > 0) cOverlay.Add("Dialogue: 0," + at2 + ",Caption,,0,0,0,," + cap);
        ScreenCapture.CaptureScreenshot(Application.dataPath + "/../Logs/clip/frame_" + cFrame.ToString("D4") + ".png");
        cFrame++;
    }

    static string AssTime(float sec) { int cs = Mathf.RoundToInt(sec * 100f); return (cs / 360000) + ":" + ((cs / 6000) % 60).ToString("D2") + ":" + ((cs / 100) % 60).ToString("D2") + "." + (cs % 100).ToString("D2"); }

    static void WriteOverlay()
    {
        var head = new List<string>
        {
            "[Script Info]", "ScriptType: v4.00+", "PlayResX: 1280", "PlayResY: 720", "",
            "[V4+ Styles]",
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
            "Style: Title,Arial,34,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,1,0,0,0,100,100,0,0,1,3,1,8,20,20,78,1",
            "Style: Caption,Arial,26,&H00FFFFFF,&H000000FF,&H00000000,&H90000000,0,0,0,0,100,100,0,0,3,6,0,2,30,30,28,1",
            "", "[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
        };
        head.AddRange(cOverlay);
        System.IO.File.WriteAllLines(Application.dataPath + "/../Logs/clip/overlay.ass", head.ToArray());
    }

    static void WriteWav(string path, List<float> s, int rate, int ch)
    {
        using (var f = new System.IO.BinaryWriter(System.IO.File.Create(path)))
        {
            int bytes = s.Count * 2;
            f.Write(System.Text.Encoding.ASCII.GetBytes("RIFF")); f.Write(36 + bytes); f.Write(System.Text.Encoding.ASCII.GetBytes("WAVE"));
            f.Write(System.Text.Encoding.ASCII.GetBytes("fmt ")); f.Write(16); f.Write((short)1); f.Write((short)ch); f.Write(rate); f.Write(rate * ch * 2); f.Write((short)(ch * 2)); f.Write((short)16);
            f.Write(System.Text.Encoding.ASCII.GetBytes("data")); f.Write(bytes);
            foreach (float v in s) f.Write((short)Mathf.Clamp(Mathf.RoundToInt(v * 32767f), -32768, 32767));
        }
    }

    // ---- the game view's size (so the frames come out 1280 x 720), as the Digger Game's builder does it
    static bool GameViewSize(int wdt, int hgt)
    {
        try
        {
            var asm = typeof(Editor).Assembly;
            var sizesType = asm.GetType("UnityEditor.GameViewSizes");
            var single = typeof(ScriptableSingleton<>).MakeGenericType(sizesType);
            var inst = single.GetProperty("instance").GetValue(null, null);
            var group = sizesType.GetProperty("currentGroup").GetValue(inst, null);
            var groupType = group.GetType();
            int total = (int)groupType.GetMethod("GetTotalCount").Invoke(group, null);
            int index = -1;
            for (int i = 0; i < total; i++)
            {
                var sz = groupType.GetMethod("GetGameViewSize").Invoke(group, new object[] { i });
                var st = sz.GetType();
                if ((int)st.GetProperty("width").GetValue(sz, null) == wdt && (int)st.GetProperty("height").GetValue(sz, null) == hgt
                    && st.GetProperty("sizeType").GetValue(sz, null).ToString() == "FixedResolution") { index = i; break; }
            }
            if (index < 0)
            {
                var sizeType = asm.GetType("UnityEditor.GameViewSize");
                var kind = asm.GetType("UnityEditor.GameViewSizeType");
                var ctor = sizeType.GetConstructor(new[] { kind, typeof(int), typeof(int), typeof(string) });
                var size = ctor.Invoke(new object[] { System.Enum.Parse(kind, "FixedResolution"), wdt, hgt, "Clip " + wdt + "x" + hgt });
                groupType.GetMethod("AddCustomSize").Invoke(group, new[] { size });
                index = total;
            }
            var gv = EditorWindow.GetWindow(asm.GetType("UnityEditor.GameView"), false, null, false);
            var p = gv.GetType().GetProperty("selectedSizeIndex", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic);
            if (p != null) p.SetValue(gv, index, null);
            gv.Repaint();
            return true;
        }
        catch (System.Exception e) { Debug.LogWarning("couldn't set the game view size: " + e.Message); return false; }
    }

    // ================================================================== the Windows game
    public static void BuildWindows()
    {
        var opts = new BuildPlayerOptions
        {
            scenes = new[] { ScenePath },
            locationPathName = "Builds/VoxelArena3/VoxelArena.exe",
            target = BuildTarget.StandaloneWindows64,
            options = BuildOptions.None,
        };
        // the shaders made only in code must go in the build
        IncludeShaders("Arena/VertexColour", "Voxel/FireSmoke", "Voxel/Terrain", "Standard", "Unlit/Color", "Sprites/Default", "Skybox/Procedural");
        var report = BuildPipeline.BuildPlayer(opts);
        bool ok = report.summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded;
        Debug.Log(ok ? "ARENA_WINDOWS_OK " + report.summary.totalSize : "ARENA_WINDOWS_FAILED " + report.summary.result);
        if (Application.isBatchMode || System.Environment.CommandLine.Contains("-executeMethod")) EditorApplication.Exit(ok ? 0 : 1);
    }

    static void IncludeShaders(params string[] names)
    {
        var gs = AssetDatabase.LoadAssetAtPath<GraphicsSettings>("ProjectSettings/GraphicsSettings.asset");
        var so = new SerializedObject(gs);
        var arr = so.FindProperty("m_AlwaysIncludedShaders");
        foreach (var n in names)
        {
            var sh = Shader.Find(n);
            if (sh == null) continue;
            bool have = false;
            for (int i = 0; i < arr.arraySize; i++) if (arr.GetArrayElementAtIndex(i).objectReferenceValue == sh) have = true;
            if (have) continue;
            arr.InsertArrayElementAtIndex(arr.arraySize);
            arr.GetArrayElementAtIndex(arr.arraySize - 1).objectReferenceValue = sh;
        }
        so.ApplyModifiedProperties();
        AssetDatabase.SaveAssets();
    }

    // ================================================================== bits
    static void SetUpPostProcessing(Camera cam)
    {
        cam.allowHDR = true;
        cam.allowMSAA = false;
        var layer = cam.gameObject.AddComponent<PostProcessLayer>();
        string[] found = AssetDatabase.FindAssets("t:PostProcessResources");
        if (found.Length == 0) { Debug.LogError("ARENA_BUILD_FAILED post-processing resources not found"); return; }
        layer.Init(AssetDatabase.LoadAssetAtPath<PostProcessResources>(AssetDatabase.GUIDToAssetPath(found[0])));
        layer.volumeLayer = 1;
        layer.volumeTrigger = cam.transform;
        layer.antialiasingMode = PostProcessLayer.Antialiasing.SubpixelMorphologicalAntialiasing;

        const string path = Dir + "/Look.asset";
        AssetDatabase.DeleteAsset(path);
        var profile = ScriptableObject.CreateInstance<PostProcessProfile>();
        AssetDatabase.CreateAsset(profile, path);
        var ao = profile.AddSettings<AmbientOcclusion>();
        ao.enabled.Override(true);
        ao.mode.Override(AmbientOcclusionMode.MultiScaleVolumetricObscurance);
        ao.intensity.Override(0.6f);
        ao.thicknessModifier.Override(1.3f);
        var bloom = profile.AddSettings<Bloom>();
        bloom.enabled.Override(true);
        bloom.intensity.Override(1.3f);
        bloom.threshold.Override(1.1f);
        bloom.softKnee.Override(0.6f);
        var grade = profile.AddSettings<ColorGrading>();
        grade.enabled.Override(true);
        grade.tonemapper.Override(Tonemapper.ACES);
        grade.postExposure.Override(0.6f);
        grade.temperature.Override(2f);
        grade.contrast.Override(8f);
        grade.saturation.Override(-2f);
        var vignette = profile.AddSettings<Vignette>();
        vignette.enabled.Override(true);
        vignette.intensity.Override(0.2f);
        vignette.smoothness.Override(0.5f);
        foreach (var setting in profile.settings) AssetDatabase.AddObjectToAsset(setting, profile);
        EditorUtility.SetDirty(profile);
        var volume = new GameObject("Look").AddComponent<PostProcessVolume>();
        volume.isGlobal = true;
        volume.sharedProfile = profile;
    }

    static void MakeBox(Transform parent, Material mat, Vector3 pos, Vector3 size, string name)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
        go.name = name;
        go.transform.SetParent(parent, false);
        go.transform.position = pos;
        go.transform.localScale = size;
        go.GetComponent<MeshRenderer>().sharedMaterial = mat;
        Object.DestroyImmediate(go.GetComponent<Collider>());
    }

    static void MakeGroundPlane(Transform parent, Material mat, float x0, float x1, float z0, float z1)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Plane);
        go.name = "Ground";
        go.transform.SetParent(parent, false);
        go.transform.position = new Vector3((x0 + x1) * 0.5f, 0f, (z0 + z1) * 0.5f);
        go.transform.localScale = new Vector3((x1 - x0) / 10f, 1f, (z1 - z0) / 10f);
        go.GetComponent<MeshRenderer>().sharedMaterial = mat;
        Object.DestroyImmediate(go.GetComponent<Collider>());
    }

    static Material MakeMaterial(string path, Shader shader, Color colour)
    {
        var mat = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (mat == null) { mat = new Material(shader); AssetDatabase.CreateAsset(mat, path); }
        mat.shader = shader;
        mat.color = colour;
        if (mat.HasProperty("_Glossiness")) mat.SetFloat("_Glossiness", 0.1f);
        EditorUtility.SetDirty(mat);
        return mat;
    }
}
