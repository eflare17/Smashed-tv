// A picture of the new fine grunt (VoxModel.GruntBoxesFine, 6.25 cm blocks) for the owner to look at before it goes in
// the game.  Plays the arena scene with no waves, stands the player and statues of the grunts on the real ground,
// and saves four views to Logs/grunt_pic/:
//   1 front: player and new grunt     2 three-quarter: player and new grunt
//   3 player, new grunt, old 15 cm grunt in a row     4 close up of the new grunt's head and hands, walk frame 1
//   -executeMethod GruntPicture.Make
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class GruntPicture
{
    const int W = 960, H = 720;
    static double t0;
    static int step;
    static float ready;

    public static void Make()
    {
        EditorSceneManager.OpenScene("Assets/Arena/Arena.unity");
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        step = 0;
        t0 = EditorApplication.timeSinceStartup;
        EditorApplication.update += Tick;
        EditorApplication.EnterPlaymode();
    }

    static void Finish(int code)
    {
        EditorApplication.update -= Tick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static GameObject Statue(Mesh m, Vector3 at, float facing)
    {
        var go = new GameObject("statue");
        go.AddComponent<MeshFilter>().sharedMesh = m;
        var mr = go.AddComponent<MeshRenderer>();
        mr.sharedMaterial = new Material(Shader.Find("Arena/VertexColour"));
        at.y = VoxelWorld.Instance.FloorAt(at + Vector3.up * 2f);
        go.transform.SetPositionAndRotation(at, Quaternion.Euler(0f, facing, 0f));
        return go;
    }

    static void Shot(Camera cam, Vector3 pos, Vector3 look, float fov, string file)
    {
        cam.transform.position = pos;
        cam.transform.rotation = Quaternion.LookRotation(look - pos);
        cam.fieldOfView = fov;
        var rt = new RenderTexture(W, H, 24);
        cam.targetTexture = rt;
        cam.Render();
        RenderTexture.active = rt;
        var tex = new Texture2D(W, H, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, W, H), 0, 0);
        tex.Apply();
        cam.targetTexture = null;
        RenderTexture.active = null;
        string dir = Application.dataPath + "/../Logs/grunt_pic";
        System.IO.Directory.CreateDirectory(dir);
        System.IO.File.WriteAllBytes(dir + "/" + file, tex.EncodeToPNG());
    }

    static void Tick()
    {
        if (EditorApplication.timeSinceStartup - t0 > 300) { Debug.LogError("ARENA_PIC_FAILED timed out"); Finish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var game = ArenaGame.Instance; var pl = ArenaPlayer.Instance; var w = VoxelWorld.Instance;
        if (game == null || pl == null || w == null) return;
        game.wavesOn = false; game.god = true;
        pl.useOverride = true; pl.overrideRifle = pl.overrideRocket = false;   // no stray shots before the pictures
        if (Grunts.Instance != null) Grunts.Instance.Clear();
        if (Time.timeSinceLevelLoad < 3f) return;
        var cam = Camera.main;
        if (step == 0)
        {
            var fc = cam.GetComponent<FollowCamera>(); if (fc != null) fc.enabled = false;
            pl.useOverride = true;
            pl.overrideMove = Vector2.zero;
            // everyone faces -Z, towards the camera and the sun
            pl.Teleport(new Vector3(-0.75f, 0f, 2f), 180f);
            pl.overrideAim = new Vector3(-0.75f, 1.2f, -20f);
            float v = VoxelWorld.Voxel;
            var fineA = VoxModel.FromBoxes(VoxModel.GruntBoxesFine(0), new Vector3(7.5f, 0f, 4f), v);
            var fineB = VoxModel.FromBoxes(VoxModel.GruntBoxesFine(1), new Vector3(7.5f, 0f, 4f), v);
            var old = VoxModel.FromBoxes(VoxModel.GruntBoxes(0), new Vector3(3.5f, 0f, 2f), 0.1f * Grunts.Scale);
            Statue(fineA, new Vector3(0.65f, 0f, 2f), 180f);
            Statue(old, new Vector3(2.35f, 0f, 2f), 180f);
            Statue(fineB, new Vector3(5.5f, 0f, -4f), 180f);       // the close up, away from the others
            ready = Time.time; step = 1; return;
        }
        if (Time.time - ready < 1f) return;                        // let the player turn and settle
        float gy = w.FloorAt(new Vector3(0f, 2f, 2f));
        Vector3 mid = new Vector3(-0.05f, gy + 0.85f, 2f);
        Shot(cam, mid + new Vector3(0f, 0.25f, -4.2f), mid, 40f, "1_front.png");
        Shot(cam, mid + new Vector3(3.2f, 0.9f, -3.0f), mid, 40f, "2_three_quarter.png");
        Vector3 row = new Vector3(0.8f, gy + 0.85f, 2f);
        Shot(cam, row + new Vector3(-1.6f, 0.5f, -5.6f), row, 40f, "3_old_and_new.png");
        float gy2 = w.FloorAt(new Vector3(5.5f, 2f, -4f));
        Vector3 head = new Vector3(5.5f, gy2 + 1.05f, -4f);
        Shot(cam, head + new Vector3(1.2f, 0.35f, -1.6f), head, 40f, "4_close_up.png");
        var wp = Weapons.Instance;
        Debug.Log("ARENA_PIC_OK shots=" + (wp != null ? wp.RifleShots + "/" + wp.RocketsFired + "/" + wp.Blasts : "?") + " t=" + Time.timeSinceLevelLoad.ToString("F1"));
        Finish(0);
    }
}
