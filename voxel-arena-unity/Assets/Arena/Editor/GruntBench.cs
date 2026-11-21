// Frame time with a big crowd, the old 15 cm grunt against the new 6.25 cm one (same run, same ground, same seed).
// For each: 120 grunts (twice the most the game lets on the field) run in from a ring, 4 s timed while they walk,
// then 8 rockets go into the crowd and 4 s more are timed with the gibs flying.  Logs ARENA_BENCH lines.
//   -executeMethod GruntBench.Run
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class GruntBench
{
    const int N = 120;
    static double t0;
    static int phase, model, frames, rockets;
    static float start, sum, worst;
    static string log = "";

    public static void Run()
    {
        EditorSceneManager.OpenScene("Assets/Arena/Arena.unity");
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        phase = 0; model = 0; log = "";
        t0 = EditorApplication.timeSinceStartup;
        EditorApplication.update += Tick;
        EditorApplication.EnterPlaymode();
    }

    static void Finish(int code)
    {
        EditorApplication.update -= Tick;
        Grunts.OldModel = false;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        Debug.Log("ARENA_BENCH_DONE" + log);
        EditorApplication.Exit(code);
    }

    static void Tick()
    {
        if (EditorApplication.timeSinceStartup - t0 > 400) { Debug.LogError("ARENA_BENCH_FAILED timed out"); Finish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var game = ArenaGame.Instance; var pl = ArenaPlayer.Instance; var g = Grunts.Instance; var w = VoxelWorld.Instance;
        if (game == null || pl == null || g == null || w == null) return;
        game.wavesOn = false; game.god = true;
        pl.useOverride = true; pl.overrideRifle = pl.overrideRocket = false; pl.overrideMove = Vector2.zero;
        if (Time.timeSinceLevelLoad < 3f) return;
        float t = Time.realtimeSinceStartup;
        if (phase == 0)
        {
            // set up one model's run
            Grunts.OldModel = model == 0;
            g.MakeMeshes();
            g.Clear(); Gibs.Clear();
            pl.Teleport(Vector3.zero, 0f);
            pl.SetAbove(true);
            Random.InitState(7);
            for (int i = 0; i < N; i++)
            {
                float a = i * Mathf.PI * 2f / N, r = 9f + (i % 4) * 1.4f;
                g.SpawnInside(new Vector3(Mathf.Cos(a) * r, 0f, Mathf.Sin(a) * r), 0.9f);
            }
            start = t; frames = 0; sum = 0f; worst = 0f; rockets = 0;
            phase = 1; return;
        }
        float ms = Time.unscaledDeltaTime * 1000f;
        if (t - start > 0.5f) { frames++; sum += ms; worst = Mathf.Max(worst, ms); }   // skip the first half second
        if (phase == 1 && t - start > 4.5f)
        {
            Report("walking", g.Count);
            start = t; frames = 0; sum = 0f; worst = 0f;
            phase = 2; return;
        }
        if (phase == 2)
        {
            // rockets into the crowd, one every 0.4 s
            if (rockets < 8 && t - start > rockets * 0.4f)
            {
                float a = rockets * 0.785f;
                pl.overrideAim = new Vector3(Mathf.Cos(a) * 7f, 0f, Mathf.Sin(a) * 7f);
                pl.queuedRockets = 1; rockets++;
            }
            if (t - start > 4.5f)
            {
                Report("rockets+gibs", g.Count, " gibsMade=" + Gibs.Made + " gibsLive=" + Gibs.Count);
                if (++model == 2) { Finish(0); return; }
                phase = 0;
            }
        }
    }

    static void Report(string what, int alive, string extra = "")
    {
        float avg = sum / Mathf.Max(1, frames);
        string m = model == 0 ? "old15cm" : "new625cm";
        string line = " | " + m + " " + what + ": alive=" + alive + " avgMs=" + avg.ToString("F1") + " fps=" + (1000f / Mathf.Max(0.01f, avg)).ToString("F0") + " worstMs=" + worst.ToString("F1") + extra;
        log += line;
        Debug.Log("ARENA_BENCH" + line);
    }
}
