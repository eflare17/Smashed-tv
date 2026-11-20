#!/usr/bin/env python3
"""
Exports the clean bulldozer for Unity: one mesh per part plus a colour strip,
a part list, and an editor script that assembles the Bulldozer prefab.

    python make_unity_export.py                      -> unity-export/Bulldozer
    python make_unity_export.py "<project>/Assets"   -> <project>/Assets/Bulldozer

What lands in the Bulldozer folder:
    Models/<part>.obj          one mesh per part, in metres, pivot at its mount
    bulldozer_palette.png      colour strip the meshes look their colours up in
    bulldozer_parts.json       the parts, their parents and where each one sits
    Editor/BulldozerBuilder.cs builds Bulldozer.prefab and a demo scene in Unity
    Scripts/DozerController.cs driving, blade and ripper controls, digging (from unity-src/)
    Scripts/VoxelWorld.cs      diggable voxel ground (from unity-src/)
    Scripts/VoxelTerrain.shader draws the voxel ground (from unity-src/)
    Scripts/FollowCamera.cs    chase camera for the demo scene

Unity axes: X right, Y up, Z forward (the blade end), metres, ground at Y = 0.
"""

import json
import os
import shutil
import sys

import make_bulldozer_vox as dozer

VOXEL = 0.0625                      # metres per voxel (16 voxels to the metre)
CX, CY = dozer.W / 2.0, dozer.L / 2.0
PAL_CELLS, PAL_CELL_PX = 32, 8      # palette strip: 32 colours, 8 px each

DIRS = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
QUAD = (                            # corners of each face, anticlockwise seen from outside
    ((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)),
    ((0, 0, 1), (0, 1, 1), (0, 1, 0), (0, 0, 0)),
    ((0, 1, 1), (1, 1, 1), (1, 1, 0), (0, 1, 0)),
    ((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)),
    ((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)),
    ((0, 1, 0), (1, 1, 0), (1, 0, 0), (0, 0, 0)),
)

t, r = dozer.TRUNNION, dozer.REAR_PLATE
TRUNNION_Y = (t["y0"] + t["y1"] + 1) / 2.0
TRUNNION_Z = (t["z0"] + t["z1"] + 1) / 2.0
(rx0, rx1) = dozer.TRACK_R_X
TRACK_Y = (dozer.IDLER[0] + dozer.SPROCKET[0]) / 2.0 + 0.5
TRACK_Z = 13.0
TRACK_XR = (rx0 + rx1 + 1) / 2.0
TRACK_XL = dozer.W - TRACK_XR
SPROCKET_C = (dozer.SPROCKET[0] + 0.5, dozer.SPROCKET[1] + 0.5)     # axle centres (length, height)
IDLER_C = (dozer.IDLER[0] + 0.5, dozer.IDLER[1] + 0.5)

# name, mesh (part name or ""), parent, pivot in voxel-grid coordinates
NODES = [
    ("Body", "body", "", (CX, CY, 0.0)),
    ("Cab", "cab", "", (CX, (dozer.CAB["y0"] + dozer.CAB["y1"] + 1) / 2.0, float(dozer.CAB["z0"]))),
    ("Exhaust", "exhaust", "", (dozer.EXHAUST["cx"] + 0.5, dozer.EXHAUST["cy"] + 0.5, dozer.HOOD["z1"] + 1.0)),
    # Each track is a fixed frame plus a spinning sprocket and idler, and one pad that
    # TrackAnimator copies round the loop.
    ("Track_Left", "track_left_frame", "", (TRACK_XL, TRACK_Y, TRACK_Z)),
    ("Sprocket_Left", "track_sprocket", "Track_Left", (TRACK_XL, SPROCKET_C[0], SPROCKET_C[1])),
    ("Idler_Left", "track_idler", "Track_Left", (TRACK_XL, IDLER_C[0], IDLER_C[1])),
    ("Pad_Left", "track_pad", "Track_Left", (TRACK_XL, TRACK_Y, TRACK_Z)),
    ("Track_Right", "track_right_frame", "", (TRACK_XR, TRACK_Y, TRACK_Z)),
    ("Sprocket_Right", "track_sprocket", "Track_Right", (TRACK_XR, SPROCKET_C[0], SPROCKET_C[1])),
    ("Idler_Right", "track_idler", "Track_Right", (TRACK_XR, IDLER_C[0], IDLER_C[1])),
    ("Pad_Right", "track_pad", "Track_Right", (TRACK_XR, TRACK_Y, TRACK_Z)),
    # the lift arms pivot on the trunnion bar: turn Mount_BladeLift about X to raise the blade
    ("Mount_BladeLift", "", "", (CX, TRUNNION_Y, TRUNNION_Z)),
    ("BladeLift", "blade_lift", "Mount_BladeLift", (CX, TRUNNION_Y, TRUNNION_Z)),
    ("Mount_Blade", "", "BladeLift", (CX, dozer.BLADE_LUG_Y[1] + 1.0, 12.0)),
    ("Blade", "blade", "Mount_Blade", (CX, dozer.BLADE_LUG_Y[1] + 1.0, 12.0)),
    ("Mount_Rear", "", "", (CX, r["y1"] + 1.0, (r["z0"] + r["z1"] + 1) / 2.0)),
    ("Ripper", "ripper", "Mount_Rear", (CX, r["y1"] + 1.0, (r["z0"] + r["z1"] + 1) / 2.0)),
]


def to_unity(x, y, z):
    """Voxel-grid position -> Unity metres (X right, Y up, Z forward)."""
    return (-(x - CX) * VOXEL, z * VOXEL, -(y - CY) * VOXEL)


def split_track(track, name):
    """Splits a solid track into its fixed frame, drive sprocket and front idler.
    The outer belt is dropped: in Unity it is made of moving pads instead."""
    import math
    (fy, fz, fr), (ry, rz, rr) = dozer.IDLER, dozer.SPROCKET
    seg2 = (ry - fy) ** 2 + (rz - fz) ** 2
    frame, sprocket, idler = dozer.Part(name + "_frame"), dozer.Part("track_sprocket"), dozer.Part("track_idler")
    for (x, y, z), c in track.v.items():
        t = min(1.0, max(0.0, ((y - fy) * (ry - fy) + (z - fz) * (rz - fz)) / seg2))
        depth = fr + t * (rr - fr) - math.hypot(y - (fy + t * (ry - fy)), z - (fz + t * (rz - fz)))
        if depth < 3.2:
            continue                                      # belt and grousers
        if math.hypot(y - ry, z - rz) <= 9.6:
            sprocket.v[(x, y, z)] = c
        elif math.hypot(y - fy, z - fz) <= 8.6 and y < 40:
            idler.v[(x, y, z)] = c
        else:
            frame.v[(x, y, z)] = c
    return frame, sprocket, idler


def make_pad():
    """One track pad: a plate 4 long, the full width of the track, with a grouser bar on the outside.
    Grid x = across the track, y = along the travel, z = outwards."""
    p = dozer.Part("track_pad")
    p.box(0, 14, 0, 3, 0, 1, dozer.DGR)
    p.box(0, 14, 0, 0, 0, 1, dozer.BLK)                   # joint between pads
    p.box(0, 14, 1, 2, 2, 2, dozer.DGR)                   # grouser
    for x in (0, 14):
        p.box(x, x, 1, 2, 2, 2, dozer.DGR2)
    return p


PAD_PIVOT = (7.5, 2.0, 2.0)                               # middle of the pad, on the plate's outer face


def write_obj(path, part, pivot):
    """Unity's OBJ importer mirrors X on import, so X is written mirrored here."""
    px, py, pz = to_unity(*pivot)
    lines = ["# %s  (voxel bulldozer part, metres)" % part.name, "o " + part.name]
    for i in range(PAL_CELLS):
        lines.append("vt %.5f 0.5" % ((i + 0.5) / PAL_CELLS))
    for dx, dy, dz in DIRS:
        lines.append("vn %d %d %d" % (dx, dz, -dy))
    faces, nv = [], 0
    for (x, y, z), c in sorted(part.v.items()):
        for d, (dx, dy, dz) in enumerate(DIRS):
            if (x + dx, y + dy, z + dz) in part.v:
                continue                                # hidden inside this part
            for ox, oy, oz in QUAD[d]:
                ux, uy, uz = to_unity(x + ox, y + oy, z + oz)
                lines.append("v %.4f %.4f %.4f" % (-(ux - px), uy - py, uz - pz))
            faces.append("f " + " ".join("%d/%d/%d" % (nv + k, c + 1, d + 1) for k in (1, 2, 3, 4)))
            nv += 4
    with open(path, "w") as f:
        f.write("\n".join(lines + faces) + "\n")
    return len(faces)


BUILDER_CS = r'''// Generated by make_unity_export.py.  Builds Assets/Bulldozer/Bulldozer.prefab from the part meshes.
// It runs by itself the first time the folder is imported; after that use Tools > Bulldozer > Rebuild prefab.
using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.PostProcessing;

public class BulldozerImportSettings : AssetPostprocessor
{
    void OnPreprocessTexture()
    {
        if (!assetPath.EndsWith("Bulldozer/bulldozer_palette.png")) return;
        var ti = (TextureImporter)assetImporter;
        ti.filterMode = FilterMode.Point;
        ti.mipmapEnabled = false;
        ti.textureCompression = TextureImporterCompression.Uncompressed;
        ti.wrapMode = TextureWrapMode.Clamp;
    }

    void OnPreprocessModel()
    {
        if (!assetPath.Contains("Bulldozer/Models/")) return;
        var mi = (ModelImporter)assetImporter;
        mi.globalScale = 1f;
        mi.useFileScale = false;
        mi.materialImportMode = ModelImporterMaterialImportMode.None;
        mi.importNormals = ModelImporterNormals.Import;
        mi.meshCompression = ModelImporterMeshCompression.Off;
        mi.isReadable = true;            // so game code can read the mesh later (dirt, wash)
        mi.weldVertices = true;
    }
}

[InitializeOnLoad]
public static class BulldozerBuilder
{
    const string Dir = "Assets/Bulldozer";
    const string PrefabPath = Dir + "/Bulldozer.prefab";
    const string ScenePath = Dir + "/BulldozerDemo.unity";

    [Serializable] class Node { public string name; public string mesh; public string parent; public float[] pos; }
    [Serializable] class PartList { public float voxelSize; public Node[] nodes; }

    static BulldozerBuilder()
    {
        EditorApplication.delayCall += () =>
        {
            EnsurePadAxes();                                              // the game pad's axes (does nothing once they're there)
            if (!Application.isBatchMode && AssetDatabase.LoadAssetAtPath<GameObject>(PrefabPath) == null) Build();
        };
    }

    // Used from the command line:  -executeMethod BulldozerBuilder.BuildFromCommandLine
    public static void BuildFromCommandLine()
    {
        AssetDatabase.Refresh();
        Build();
    }

    // Used from the command line:  -executeMethod BulldozerBuilder.OpenDemoScene
    [MenuItem("Tools/Bulldozer/Open demo scene")]
    public static void OpenDemoScene()
    {
        EditorSceneManager.OpenScene(ScenePath);
        var dozer = GameObject.Find("Bulldozer");
        if (dozer != null) { Selection.activeGameObject = dozer; EditorApplication.delayCall += () => SceneView.FrameLastActiveSceneView(); }
    }

    // Opens the demo scene and presses Play:  -executeMethod BulldozerBuilder.PlayDemo
    [MenuItem("Tools/Bulldozer/Play demo")]
    public static void PlayDemo()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorApplication.delayCall += () =>
        {
            EditorApplication.ExecuteMenuItem("Window/General/Game");
            var gameView = EditorWindow.focusedWindow;
            if (gameView != null) gameView.maximized = true;                // the game fills the whole editor window
            EditorApplication.EnterPlaymode();
        };
    }

    [MenuItem("Tools/Bulldozer/Rebuild prefab")]
    public static void Build()
    {
        var json = AssetDatabase.LoadAssetAtPath<TextAsset>(Dir + "/bulldozer_parts.json");
        if (json == null) { Debug.LogError("BULLDOZER_BUILD_FAILED bulldozer_parts.json not found"); return; }
        var list = JsonUtility.FromJson<PartList>(json.text);

        bool srp = GraphicsSettings.currentRenderPipeline != null;
        var shader = Shader.Find(srp ? "Universal Render Pipeline/Lit" : "Standard");
        var palette = AssetDatabase.LoadAssetAtPath<Texture2D>(Dir + "/bulldozer_palette.png");

        var paint = MakeMaterial(Dir + "/BulldozerPaint.mat", shader, palette, Color.white);
        var ground = MakeMaterial(Dir + "/DemoGround.mat", shader, null, new Color(0.74f, 0.60f, 0.42f));

        var root = new GameObject("Bulldozer");
        var made = new Dictionary<string, Transform>();
        int meshes = 0, verts = 0;
        foreach (var n in list.nodes)
        {
            var go = new GameObject(n.name);
            Transform parent = root.transform;
            if (!string.IsNullOrEmpty(n.parent) && made.ContainsKey(n.parent)) parent = made[n.parent];
            go.transform.SetParent(parent, false);
            go.transform.position = root.transform.TransformPoint(new Vector3(n.pos[0], n.pos[1], n.pos[2]));
            made[n.name] = go.transform;
            if (string.IsNullOrEmpty(n.mesh)) continue;

            Mesh mesh = null;
            foreach (var o in AssetDatabase.LoadAllAssetsAtPath(Dir + "/Models/" + n.mesh + ".obj"))
                if (o is Mesh m) { mesh = m; break; }
            if (mesh == null) { Debug.LogError("BULLDOZER_BUILD_FAILED no mesh for " + n.mesh); continue; }
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>().sharedMaterial = paint;
            // simple box colliders so the machine can shove things; the arms and exhaust don't need one
            if (n.mesh == "body" || n.mesh == "cab" || n.mesh == "blade" || n.mesh == "ripper" || n.mesh.EndsWith("_frame"))
                go.AddComponent<BoxCollider>();
            if (n.name.StartsWith("Track_")) go.AddComponent<TrackAnimator>();
            meshes++; verts += mesh.vertexCount;
        }

        // work lights: two headlights low at the front, two on the back of the cab roof.  L switches them on.
        var lights = new GameObject("Lights");
        lights.transform.SetParent(root.transform, false);
        MakeSpot(lights.transform, new Vector3(-1.05f, 2.85f, 2.35f), new Vector3(14f, -4f, 0f), true);
        MakeSpot(lights.transform, new Vector3(1.05f, 2.85f, 2.35f), new Vector3(14f, 4f, 0f), false);
        MakeSpot(lights.transform, new Vector3(-0.8f, 4.25f, -1.75f), new Vector3(28f, 176f, 0f), false);
        MakeSpot(lights.transform, new Vector3(0.8f, 4.25f, -1.75f), new Vector3(28f, 184f, 0f), false);
        lights.SetActive(false);

        // driven by DozerController: a kinematic body, moved by the script, that pushes loose objects
        var body = root.AddComponent<Rigidbody>();
        body.isKinematic = true;
        body.interpolation = RigidbodyInterpolation.Interpolate;
        root.AddComponent<DozerController>();

        var b = new Bounds(Vector3.zero, Vector3.zero);
        bool first = true;
        foreach (var r in root.GetComponentsInChildren<MeshRenderer>())
        {
            if (first) { b = r.bounds; first = false; } else b.Encapsulate(r.bounds);
        }

        PrefabUtility.SaveAsPrefabAsset(root, PrefabPath);
        UnityEngine.Object.DestroyImmediate(root);

        // a small scene to look at it in
        var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);
        var dozer = (GameObject)PrefabUtility.InstantiatePrefab(AssetDatabase.LoadAssetAtPath<GameObject>(PrefabPath));
        dozer.transform.position = Vector3.zero;
        dozer.transform.position = new Vector3(0f, 0f, -16f);

        // diggable voxel ground: a 48 m square patch centred on the origin
        var voxelShader = Shader.Find("Voxel/Terrain");
        if (voxelShader == null) { Debug.LogError("BULLDOZER_BUILD_FAILED Voxel/Terrain shader not found"); return; }
        var voxelMat = MakeMaterial(Dir + "/VoxelGround.mat", voxelShader, null, Color.white);
        voxelMat.SetFloat("_FixedMat", -1f);
        var worldGo = new GameObject("VoxelWorld");
        worldGo.AddComponent<VoxelWorld>().material = voxelMat;

        // plain ground round the patch, drawn with the same blocky topsoil
        ground.shader = voxelShader;
        ground.SetFloat("_FixedMat", 1f);
        EditorUtility.SetDirty(ground);
        var surround = new GameObject("Surround").transform;
        float half = VoxelWorld.SiteHalf, far = 150f;
        MakeGroundPlane(surround, ground, -far, far, half, far);            // north
        MakeGroundPlane(surround, ground, -far, far, -far, -half);          // south
        MakeGroundPlane(surround, ground, half, far, -half, half);          // east
        MakeGroundPlane(surround, ground, -far, -half, -half, half);        // west

        // a fence round the work site, so the edge of the diggable ground is plain to see
        var fenceMat = MakeMaterial(Dir + "/DemoFence.mat", shader, null, new Color(0.93f, 0.45f, 0.10f));
        var fence = new GameObject("Site fence").transform;
        for (int side = 0; side < 4; side++)
        {
            bool alongX = side < 2;
            float at = (side % 2 == 0) ? half - 1.5f : -(half - 1.5f);   // just inside the edge of the diggable ground
            for (float t = -(half - 1.5f); t <= half - 1.49f; t += 4.5f)
                MakeBox(fence, fenceMat, alongX ? new Vector3(t, 0.6f, at) : new Vector3(at, 0.6f, t), new Vector3(0.14f, 1.2f, 0.14f));
            foreach (float h in new[] { 1.05f, 0.6f })
                MakeBox(fence, fenceMat, alongX ? new Vector3(0f, h, at) : new Vector3(at, h, 0f),
                        alongX ? new Vector3(half * 2f - 3f, 0.07f, 0.05f) : new Vector3(0.05f, 0.07f, half * 2f - 3f));
        }

        // ---- the look: a low warm sun, hazy air, soft shadows, a gentle colour grade ----
        worldGo.AddComponent<SceneLook>();
        var sunGo = GameObject.Find("Directional Light");
        Light sun = sunGo != null ? sunGo.GetComponent<Light>() : null;
        if (sun != null)
        {
            sunGo.transform.rotation = Quaternion.Euler(33f, -40f, 0f);        // late afternoon
            sun.color = new Color(1f, 0.95f, 0.85f);
            sun.intensity = 1.3f;
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.85f;
            sun.shadowBias = 0.03f;
            sun.shadowNormalBias = 0.5f;
        }
        AssetDatabase.DeleteAsset(Dir + "/DemoSky.mat");
        var sky = new Material(Shader.Find("Skybox/Procedural"));
        sky.SetFloat("_SunSize", 0.045f);
        sky.SetFloat("_AtmosphereThickness", 0.95f);
        sky.SetFloat("_Exposure", 1.15f);
        sky.SetColor("_SkyTint", new Color(0.40f, 0.50f, 0.66f));
        sky.SetColor("_GroundColor", new Color(0.55f, 0.46f, 0.36f));
        AssetDatabase.CreateAsset(sky, Dir + "/DemoSky.mat");
        RenderSettings.skybox = sky;
        RenderSettings.sun = sun;
        RenderSettings.ambientMode = AmbientMode.Trilight;
        RenderSettings.ambientSkyColor = new Color(0.62f, 0.70f, 0.84f);
        RenderSettings.ambientEquatorColor = new Color(0.60f, 0.56f, 0.50f);
        RenderSettings.ambientGroundColor = new Color(0.36f, 0.31f, 0.26f);
        RenderSettings.fog = true;
        RenderSettings.fogMode = FogMode.ExponentialSquared;
        RenderSettings.fogColor = new Color(0.82f, 0.78f, 0.70f);
        RenderSettings.fogDensity = 0.0065f;                                  // dusty air: far ground fades into the haze

        var cam = Camera.main;
        SetUpPostProcessing(cam);
        if (cam != null)
        {
            var follow = cam.gameObject.AddComponent<FollowCamera>();
            follow.target = dozer.transform;
            cam.transform.position = new Vector3(-5f, 6f, -28f);
            cam.transform.LookAt(new Vector3(0f, 1.8f, -16f));
            cam.farClipPlane = 400f;
        }
        EditorSceneManager.SaveScene(scene, ScenePath);
        AssetDatabase.SaveAssets();

        Debug.Log("BULLDOZER_BUILD_OK meshes=" + meshes + " verts=" + verts + " size=" + b.size.ToString("F2")
                  + " min=" + b.min.ToString("F2") + " pipeline=" + (srp ? "URP" : "built-in"));
    }

    // Scripted dig test:  -executeMethod BulldozerBuilder.SelfTest
    // Presses Play, drives forward with the blade down, then with the ripper down, and logs what happened.
    static double testStart;
    static int testPhase, testFrames;
    static long testSolid0;
    static float testFrameSum, testFrameMax;
    static Vector3 testPos0;
    static float testEdgeZ, testLostAt;
    static int testMaxLoad, testMaxCarried;
    static float testSettledAt; static string testLoadLog = "";

    public static void SelfTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        testPhase = 0; testFrames = 0; testFrameSum = 0f; testFrameMax = 0f; testLostAt = -1f; testMaxLoad = 0; testMaxCarried = 0; testSettledAt = -1f; testLoadLog = "";
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += TestTick;
        EditorApplication.EnterPlaymode();
    }

    static void TestTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 240) { Debug.LogError("BULLDOZER_DIG_FAILED timed out"); TestFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var d = UnityEngine.Object.FindFirstObjectByType<DozerController>();
        var w = VoxelWorld.Instance;
        if (d == null || w == null) return;
        float t = Time.time;
        if (Worker.Instance == null) return;
        if (testPhase == 0)
        {
            testPhase = 1;
            // getting out of the dozer and back in, the way the Enter key does it
            var wk0 = Worker.Instance;
            string log = "startedInDozer=" + wk0.InDozer + " dead=" + d.dead;
            if (wk0.InDozer) wk0.TryDozer();
            log += " afterOut:inDozer=" + wk0.InDozer + " near=" + wk0.NearDozer() + " dist=" + Vector3.Distance(wk0.transform.position, d.transform.position).ToString("F2");
            wk0.TryDozer();
            log += " afterIn:inDozer=" + wk0.InDozer + " driven=" + d.driven;
            Debug.Log("BULLDOZER_ENTER_TEST " + log);
            d.dead = false;
            Worker.Instance.useOverride = true;
            if (!Worker.Instance.InDozer) Worker.Instance.GetIn();
            d.useOverride = true;
            testPos0 = d.transform.position;
            testSolid0 = w.CountSolid();
        }
        if (t > 1f && t < 1.1f) w.ResetTimings();                                          // ignore start-up
        testMaxLoad = Mathf.Max(testMaxLoad, w.LoadVoxels);
        testMaxCarried = Mathf.Max(testMaxCarried, w.ClodCount);
        if (t < 1f) { d.overrideBlade = -1f; }                                             // lower the blade
        else if (t < 7f)                                                                    // dig forward, angling the blade part way
        {
            d.overrideThrottle = 1f; d.overrideBlade = -1f; d.overrideRipper = 0f;
            d.overrideAngle = (t > 3.5f && t < 5f) ? 1f : 0f;
            testFrames++; testFrameSum += Time.unscaledDeltaTime; testFrameMax = Mathf.Max(testFrameMax, Time.unscaledDeltaTime);
            if (t > 3f && testLoadLog.Length < 10 * 0 + 2000 && Mathf.Repeat(t, 1f) < Time.deltaTime) testLoadLog += " t" + t.ToString("F0") + "[" + d.BladeLoadInfo() + "]";
            if (t > 5.8f && testLoadLog.IndexOf("sidePic") < 0 && d.Blade != null)
            {
                Vector3 bp = d.Blade.position, side = d.transform.right;
                HillShot(bp - side * 7f + Vector3.up * 1.5f + d.transform.forward * 1.5f, bp + d.transform.forward * 1f, "dig_test_side.png");
                testLoadLog += " sidePic";
            }
            if (t > 6.5f && testPhase == 1) { testPhase = 2; TestCapture("dig_test_digging.png"); }
        }
        else if (t < 10f) { d.overrideThrottle = 1f; d.overrideBlade = 1f; d.overrideRipper = -1f; }
        else if (t < 19f) { d.overrideThrottle = 1f; d.overrideBlade = -1f; d.overrideRipper = 1f; testEdgeZ = d.transform.position.z; }   // on into the fence, digging   // blade up, rip
        else if (t < 25f)                                                                   // park, blade up, and wait for the dirt to settle
        {
            d.overrideThrottle = 0f; d.overrideBlade = 1f; d.overrideRipper = 1f; d.overrideAngle = 0f;
            if (testSettledAt < 0f && w.ClodCount == 0) testSettledAt = t - 19f;
        }
        else
        {
            Vector3 p = d.transform.position;
            long solid1 = w.CountSolid();
            float heap = w.MaxHeightIn(p.x - 3f, testPos0.z, p.x + 3f, p.z + 8f);
            float cutFloor = w.HeightAt(testPos0.x, testPos0.z + 6f);
            Debug.Log("BULLDOZER_DIG_RESULT drove=" + (p.z - testPos0.z).ToString("F1") + "m"
                + " bladeMoved=" + w.TotalCut + " ripped=" + w.TotalRipped
                + " notGroundNow=" + w.LoadVoxels + " trackedGround=" + w.SolidCount
                + " volumeChange=" + ((solid1 + w.LoadVoxels) - testSolid0) + " trackingError=" + (w.SolidCount - solid1)
                + " bladeAngle=" + d.BladeYaw.ToString("F0")
                + " maxLooseMoving=" + (testMaxLoad * VoxelWorld.VoxelVolume).ToString("F2") + "m3"
                + " maxClods=" + testMaxCarried + " clodsLeftAfterParking=" + w.ClodCount
                + " allSettledAfter=" + (testSettledAt < 0f ? "never" : testSettledAt.ToString("F1") + "s")
                + " solidBefore=" + testSolid0 + " solidAfter=" + solid1
                + " pushing:" + testLoadLog + " heapHeight=" + heap.ToString("F2") + "m cutFloor=" + cutFloor.ToString("F2") + "m"
                + " machineHeight=" + p.y.ToString("F2") + "m"
                + " stoppedAtZ=" + testEdgeZ.ToString("F1") + "m (fence at " + (VoxelWorld.SiteHalf - 1.5f).ToString("F1") + "m)"
                + " trackPads=" + (d.GetComponentInChildren<TrackAnimator>() != null ? d.GetComponentInChildren<TrackAnimator>().PadCount : 0)
                + " trackRan=" + (d.GetComponentInChildren<TrackAnimator>() != null ? d.GetComponentInChildren<TrackAnimator>().Travel : 0f).ToString("F1") + "m"
                + " ms(avg/max) cut=" + w.MsAvg[0].ToString("F2") + "/" + w.MsMax[0].ToString("F1")
                + " clods=" + w.MsAvg[1].ToString("F2") + "/" + w.MsMax[1].ToString("F1")
                + " slump=" + w.MsAvg[2].ToString("F2") + "/" + w.MsMax[2].ToString("F1")
                + " ground=" + w.MsAvg[3].ToString("F2") + "/" + w.MsMax[3].ToString("F1")
                + " draw=" + w.MsAvg[4].ToString("F2") + "/" + w.MsMax[4].ToString("F1")
                + " avgFrameMs=" + (testFrameSum / Mathf.Max(1, testFrames) * 1000f).ToString("F1")
                + " worstFrameMs=" + (testFrameMax * 1000f).ToString("F1")
                + " worstRemeshMs=" + w.MaxRemeshMs.ToString("F1") + " worstRemeshChunks=" + w.MaxRemeshChunks);
            TestCapture("dig_test_after.png");
            // a close look at one track from the side
            var cam = Camera.main;
            if (cam != null)
            {
                cam.transform.position = d.transform.position + d.transform.right * 6.5f + Vector3.up * 1.6f;
                cam.transform.LookAt(d.transform.position + Vector3.up * 0.9f);
                TestCapture("dig_test_track.png");
            }
            TestFinish(0);
        }
    }

    // saves what the game camera sees to the project's Logs folder, so the look can be checked without the editor window
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

    // Finds and repairs:  -executeMethod BulldozerBuilder.FindsTest
    // Digs the first part out of the cave-in by script, picks it up and fits it, then checks each part brings back
    // its one job on a dead dozer.  Prints BULLDOZER_FINDS_RESULT and BULLDOZER_REPAIR_RESULT.
    static int fPhase, fTarget;
    static float fNext, fPhaseStart, fExposedAt;
    static long fVolume0;
    static string fLog;
    static Vector3 fDozerPos;
    static float fBlade0, fRip0;

    public static void FindsTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        fPhase = 0; fLog = ""; fExposedAt = -1f;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += FindsTick;
        EditorApplication.EnterPlaymode();
    }

    static void FindsFinish(int code)
    {
        EditorApplication.update -= FindsTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static void FindsTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_FINDS_FAILED timed out in phase " + fPhase + " " + fLog); FindsFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var wk = Worker.Instance; var finds = Finds.Instance;
        var d = UnityEngine.Object.FindFirstObjectByType<DozerController>();
        if (w == null || wk == null || finds == null || d == null) return;
        float t = Time.time;
        if (fPhase == 0)
        {
            if (wk.InDozer) wk.GetOut();
            wk.useOverride = true;
            fVolume0 = w.CountSolid() + w.LoadVoxels;
            fLog += "exposedAtStart=" + finds.Exposed(0);
            fPhase = 1; fPhaseStart = t; fNext = t; fTarget = 0;
            return;
        }
        if (fPhase == 1)
        {
            // dig it out: break up and shovel away the rubble over and in front of part 0, a bit at a time,
            // throwing each load well outside the mine
            if (finds.Exposed(0)) { fExposedAt = t - fPhaseStart; fPhase = 2; return; }
            if (t - fPhaseStart > 60f) { fLog += " neverExposed"; fPhase = 2; return; }
            if (t < fNext) return;
            fNext = t + 0.05f;
            Vector3 c = finds.Spot[0];
            int n = fTarget++;
            float h = 0.6f + (n % 7) * 0.3f, x = -0.45f + ((n / 7) % 4) * 0.3f, z = -1.5f + ((n / 28) % 6) * 0.35f;
            Vector3 at = c + new Vector3(x, h, z);
            w.Pick(at, 0.3f, Vector3.zero);
            w.Scoop(at, 0.55f, 4000);
            if (w.ShovelVoxels >= VoxelVorldClod())
                w.Throw(new Vector3(VoxelWorld.PortalX + 5f, 2f, VoxelWorld.PortalZ - 9f), Vector3.zero, 1f, 0.2f);
            return;
        }
        if (fPhase == 2)
        {
            // walk up to it (placed there by script), look at it, pick it up
            wk.Teleport(finds.Spot[0] + new Vector3(0f, 0f, -1.6f), 0f);
            fPhase = 21; fPhaseStart = t;
            return;
        }
        if (fPhase == 21)
        {
            if (t - fPhaseStart < 6f) return;                                    // long enough for loose rubble to slide back
            TestCapture("finds_exposed.png");
            wk.SetEyes(true); wk.Look(42f);
            fPhase = 22; fPhaseStart = t;
            return;
        }
        if (fPhase == 22)
        {
            if (t - fPhaseStart < 0.4f) return;
            TestCapture("finds_eyes.png");
            finds.testGlintPhase = 0.22f;                                          // every glint at its brightest
            finds.SendMessage("Update");
            TestCapture("finds_glint.png");
            finds.testGlintPhase = -1f;
            wk.SetEyes(false); wk.Look(14f);
            wk.Teleport(finds.Spot[0] + new Vector3(0f, 0f, -1.1f), 0f);
            bool could = finds.CanCollect(0, wk.transform.position);
            string r = wk.UsePart();
            fLog += " exposedAfter=" + (fExposedAt < 0f ? "never" : fExposedAt.ToString("F1") + "s") + " stillExposedAfter6s=" + finds.Exposed(0) + " found=" + finds.Found[0] + " couldPickUp=" + could + " pickUp=[" + r + "] carrying=" + finds.Carrying(0);
            // the other two parts must still be buried
            fLog += " part1Buried=" + !finds.Exposed(1) + " part2Buried=" + !finds.Exposed(2);
            Debug.Log("BULLDOZER_FINDS_RESULT " + fLog);
            fLog = "";
            fPhase = 3; fPhaseStart = t;
            return;
        }
        if (fPhase == 3)
        {
            // a dead dozer, driven with nothing fitted: it must not move
            d.dead = true;
            wk.GetIn();
            d.useOverride = true; d.overrideThrottle = 1f;
            fDozerPos = d.transform.position;
            fBlade0 = d.BladeHeight01; fRip0 = d.RipperHeight01;
            d.overrideBlade = 1f; d.overrideRipper = 1f;
            fPhase = 4; fPhaseStart = t;
            return;
        }
        if (fPhase == 4)
        {
            if (t - fPhaseStart < 1.6f) return;
            float moved = Vector3.Distance(d.transform.position, fDozerPos);
            fLog += "deadMoved=" + moved.ToString("F2") + "m deadBladeMoved=" + (d.BladeHeight01 != fBlade0) + " deadRipperMoved=" + (d.RipperHeight01 != fRip0);
            // fit the tracks part the way a player does: get out by the dozer and press E
            d.overrideThrottle = 0f; d.overrideBlade = 0f; d.overrideRipper = 0f;
            wk.GetOut();
            string r = wk.UsePart();
            fLog += " fit=[" + r + "] canDrive=" + d.CanDrive + " canBlade=" + d.CanBlade + " canRip=" + d.CanRip;
            wk.GetIn();
            d.overrideThrottle = 1f; d.overrideBlade = 1f; d.overrideRipper = 1f;
            fDozerPos = d.transform.position; fBlade0 = d.BladeHeight01; fRip0 = d.RipperHeight01;
            fPhase = 5; fPhaseStart = t;
            return;
        }
        if (fPhase == 5)
        {
            if (t - fPhaseStart < 1.6f) return;
            fLog += " tracksMoved=" + Vector3.Distance(d.transform.position, fDozerPos).ToString("F2") + "m bladeStillStuck=" + (d.BladeHeight01 == fBlade0) + " ripperStillStuck=" + (d.RipperHeight01 == fRip0);
            finds.Install(1); finds.Install(2);                                    // the other two, as if dug out too
            fBlade0 = d.BladeHeight01; fRip0 = d.RipperHeight01;
            d.overrideThrottle = 0f;
            fPhase = 6; fPhaseStart = t;
            return;
        }
        if (fPhase == 6)
        {
            if (t - fPhaseStart < 1.2f) return;
            fLog += " bladeWorksWithPart=" + (d.BladeHeight01 != fBlade0) + " ripperWorksWithPart=" + (d.RipperHeight01 != fRip0);
            d.overrideBlade = 0f; d.overrideRipper = 0f;
            d.dead = false;
            fLog += " notDeadCanAll=" + (d.CanDrive && d.CanBlade && d.CanRip);
            fPhase = 7; fPhaseStart = t;
            return;
        }
        if (fPhase == 7)
        {
            if (t - fPhaseStart < 5f) return;                                    // let loose dirt settle before counting
            fLog += " volumeChange=" + ((w.CountSolid() + w.LoadVoxels) - fVolume0);
            Debug.Log("BULLDOZER_REPAIR_RESULT " + fLog);
            FindsFinish(0);
        }
    }

    static int VoxelVorldClod() { return VoxelWorld.ClodVoxels; }

    // The cart:  -executeMethod BulldozerBuilder.CartTest
    // Pushes it into the mine until the cave-in stops it, pushes it to the far end of the line, fills it, tips it.
    // Prints BULLDOZER_CART_RESULT.
    static int cPhase, cFillSteps;
    static float cPhaseStart, cNext, cAlong0, cLastAlong, cStillFor;
    static int cThrows0, cScoops0, cCart0;
    static bool cGrabbed;
    static float cNoGrabFrom;
    static long cVolume0;
    static string cLog;

    public static void CartTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        cPhase = 0; cLog = "";
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += CartTick;
        EditorApplication.EnterPlaymode();
    }

    static void CartFinish(int code)
    {
        EditorApplication.update -= CartTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static float Facing(Vector3 dir) { return Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg; }

    // The bushfire:  -executeMethod BulldozerBuilder.FireTest   A line of fire high on the hillside, the wind blowing
    // it down towards the mine, a firebreak strip past the fence that holds until the wind changes and strengthens.
    // Pictures as it burns.  Prints BULLDOZER_FIRE_RESULT.
    static int frPhase, frShot, frFrames;
    static float frRealStart, frMaxMs, frSumMs;
    static string frLog;
    static bool frClose;
    static readonly float[] FrShots = { 12f, 30f, 50f, 70f, 90f, 120f, 150f };
    const float FrBreakZ0 = 54f, FrBreakZ1 = 60f, FrChange = 60f;

    public static void FireTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        frPhase = 0; frShot = 0; frLog = ""; frClose = false; frFrames = 0; frMaxMs = 0f; frSumMs = 0f;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += FireTick;
        EditorApplication.EnterPlaymode();
    }

    static void FireFinish(int code)
    {
        EditorApplication.update -= FireTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static int FrBurntBelow(float z)
    {
        int n = 0;
        for (float x = -100f; x < 100f; x += 2f) for (float zz = 49f; zz < z; zz += 2f) if (FireSim.Instance.CellBurnt(new Vector3(x, 0f, zz))) n++;
        return n;
    }

    static void FireTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 400) { Debug.LogError("BULLDOZER_FIRE_FAILED timed out in phase " + frPhase + " " + frLog); FireFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var fire = FireSim.Instance; var wk = Worker.Instance;
        if (fire == null || wk == null || Camera.main == null || FireSim.Trees.Count == 0) return;
        if (frPhase == 0)
        {
            if (Time.time < 2f) return;
            wk.useOverride = true;
            var follow = Camera.main.GetComponent<FollowCamera>(); if (follow != null) follow.enabled = false;
            fire.SetWind(new Vector2(0.6f, -5f), new Vector2(2.5f, -11f), FrChange);
            fire.ClearFuel(-110f, FrBreakZ0, 110f, FrBreakZ1);
            fire.speedUp = 3f;
            fire.Begin();
            fire.Ignite(new Vector3(-100f, 0f, 160f), new Vector3(100f, 0f, 160f));
            frLog += "trees=" + FireSim.Trees.Count;
            frPhase = 1; frRealStart = Time.realtimeSinceStartup;
            return;
        }
        float ms = Time.unscaledDeltaTime * 1000f;
        frFrames++; frSumMs += ms; if (frFrames > 10) frMaxMs = Mathf.Max(frMaxMs, ms);
        float t = fire.Now;
        if (frPhase == 1 && t > FrChange - 0.5f)
        {
            frLog += " beforeChange:cells=" + fire.CellsBurnt + " trees=" + fire.TreesBurnt + " crossedBreak=" + FrBurntBelow(FrBreakZ0);
            frPhase = 2;
        }
        if (!frClose && t >= 56f)
        {
            // close, on the track past the fence, as the front comes down through the trees
            frClose = true;
            Vector3 at = new Vector3(VoxelWorld.TrackCentreX(52f) - 1f, SiteProps.HillY(VoxelWorld.TrackCentreX(52f), 52f) + 2.4f, 52f);
            Vector3 look = new Vector3(VoxelWorld.TrackCentreX(72f), SiteProps.HillY(VoxelWorld.TrackCentreX(72f), 72f) + 7f, 72f);
            Camera.main.transform.SetPositionAndRotation(at, Quaternion.LookRotation(look - at));
            TestCapture("fire_close.png");
            return;
        }
        if (frShot < FrShots.Length && t >= FrShots[frShot])
        {
            var cam = Camera.main;
            // wide, from high over the quarry, looking up the hill; and the last two from inside the forest
            if (frShot < 4) cam.transform.SetPositionAndRotation(new Vector3(-14f, 26f, -26f), Quaternion.LookRotation(new Vector3(VoxelWorld.TrackX + 6f, 12f, 90f) - new Vector3(-14f, 26f, -26f)));
            else if (frShot == 6)
            {
                Vector3 at = new Vector3(VoxelWorld.TrackX - 16f, 16f, 22f), look = new Vector3(VoxelWorld.TrackX + 2f, 4f, 52f);   // over the burnt hilltop
                cam.transform.SetPositionAndRotation(at, Quaternion.LookRotation(look - at));
            }
            else
            {
                Vector3 at = new Vector3(VoxelWorld.TrackCentreX(36f) - 1f, 5.9f, 36f), look = new Vector3(VoxelWorld.TrackCentreX(70f), 12f, 70f);
                cam.transform.SetPositionAndRotation(at, Quaternion.LookRotation(look - at));
            }
            TestCapture("fire_" + frShot + "_" + Mathf.RoundToInt(FrShots[frShot]) + "s.png");
            frShot++;
            return;
        }
        if (frShot < FrShots.Length) return;
        // a fallen trunk must be solid: the middle of the first one blocks a dozer
        string solid = "none";
        for (int ft = 0; ft < FireSim.Trees.Count; ft++)
            if (fire.HasFallen(ft))
            {
                var tr = FireSim.Trees[ft];
                Vector3 mid = tr.at + new Vector3(Mathf.Sin(fire.FallAngle(ft)), 0f, Mathf.Cos(fire.FallAngle(ft))) * tr.height * 0.5f;
                solid = SiteProps.Blocks(mid, 1f).ToString();
                break;
            }
        frLog += " fallen=" + fire.TreesFallen + " logs=" + SiteProps.FallenCount + " fallenIsSolid=" + solid;
        frLog += " end:cells=" + fire.CellsBurnt + " trees=" + fire.TreesBurnt + " crossedBreakAfterChange=" + FrBurntBelow(FrBreakZ0)
              + " reachedHilltop=" + fire.CellBurnt(new Vector3(-20f, 0f, 30f)) + " avgMs=" + (frSumMs / Mathf.Max(1, frFrames)).ToString("F1") + " worstMs=" + frMaxMs.ToString("F1");
        Debug.Log("BULLDOZER_FIRE_RESULT " + frLog);
        FireFinish(0);
    }

    // The hill behind the mine:  -executeMethod BulldozerBuilder.HillTest   Pictures, and the dozer driving up the ramp
    // onto the hilltop track.  Prints BULLDOZER_HILL_RESULT.
    static int hPhase;
    static float hT0, hMaxY, hMaxZ;
    static string hLog;
    static Camera hCam;

    public static void HillTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        hPhase = 0; hLog = ""; hMaxY = -9f; hMaxZ = -99f;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += HillTick;
        EditorApplication.EnterPlaymode();
    }

    static void HillFinish(int code)
    {
        EditorApplication.update -= HillTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static void HillShot(Vector3 pos, Vector3 look, string file)
    {
        var cam = Camera.main;
        var follow = cam.GetComponent<FollowCamera>();
        if (follow != null) follow.enabled = false;
        cam.transform.SetPositionAndRotation(pos, Quaternion.LookRotation(look - pos));
        TestCapture(file);
    }

    static void HillTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_HILL_FAILED timed out in phase " + hPhase + " " + hLog); HillFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var d = UnityEngine.Object.FindFirstObjectByType<DozerController>();
        var w = VoxelWorld.Instance; var wk = Worker.Instance;
        if (d == null || w == null || wk == null || Camera.main == null) return;
        float t = Time.time;
        float tx = VoxelWorld.TrackX;
        if (hPhase == 0)
        {
            if (t < 2f) return;
            hLog += "gums=" + SiteProps.TrackGumCount + "/" + SiteProps.HillGumCount + "/" + SiteProps.FarGumCount + " rampFoot=" + w.HeightAt(tx, VoxelWorld.TrackZ0).ToString("F2") + " rampTop=" + w.HeightAt(VoxelWorld.TrackCentreX(22f), 22f).ToString("F2")
                  + " hilltopTrack=" + w.HeightAt(VoxelWorld.TrackCentreX(40f), 40f).ToString("F2") + " pastFence=" + SiteProps.HillY(VoxelWorld.TrackCentreX(80f), 80f).ToString("F1");
            // 1. from the quarry floor, looking up the ramp and the hill behind the mine
            HillShot(new Vector3(tx - 4f, 2.2f, -8f), new Vector3(tx + 1f, 4f, 22f), "hill_from_floor.png");
            hPhase = 1; hT0 = t;
            return;
        }
        if (hPhase == 1)
        {
            if (t - hT0 < 0.5f) return;
            // 2. high, from the quarry, the whole hillside
            HillShot(new Vector3(-10f, 22f, -30f), new Vector3(tx, 8f, 45f), "hill_wide.png");
            // 3. on the hilltop track, looking up into the forest
            HillShot(new Vector3(VoxelWorld.TrackCentreX(30f), 6.6f, 30f), new Vector3(VoxelWorld.TrackCentreX(70f), 14f, 70f), "hill_track.png");
            Camera.main.GetComponent<FollowCamera>().enabled = true;
            // the dozer at the foot of the ramp, facing up it, driven
            wk.useOverride = true;
            d.dead = false;
            if (!wk.InDozer) wk.GetIn();
            d.useOverride = true;
            Vector3 start = new Vector3(VoxelWorld.TrackCentreX(1f), 0.2f, 1f);
            hLog += " startBlocked=" + SiteProps.Blocks(start, 2.3f) + " rampBlocked=" + SiteProps.Blocks(new Vector3(VoxelWorld.TrackCentreX(12f), 2f, 12f), 2.3f)
                  + " shedFront=" + SiteProps.GoldShedFront.ToString("F1") + " dozerWas=" + d.transform.position.ToString("F1");
            d.transform.position = start;
            var rb = d.GetComponent<Rigidbody>(); if (rb != null) rb.position = start;
            hPhase = 2; hT0 = t;
            return;
        }
        if (hPhase == 2)
        {
            float k = t - hT0;
            d.overrideBlade = 1f; d.overrideRipper = 1f;
            d.overrideThrottle = k < 1f ? 0f : 1f;
            // keep it on the track
            float want = VoxelWorld.TrackCentreX(d.transform.position.z + 3f) - d.transform.position.x;
            d.overrideSteer = Mathf.Clamp(want * 0.6f, -1f, 1f);
            hMaxY = Mathf.Max(hMaxY, d.transform.position.y); hMaxZ = Mathf.Max(hMaxZ, d.transform.position.z);
            if (k > 6f && hLog.IndexOf("climbPic") < 0) { TestCapture("hill_dozer_climb.png"); hLog += " climbPic"; }
            if (k > 3f && hLog.IndexOf("at3s") < 0) hLog += " at3s=" + d.transform.position.ToString("F1") + " speed=" + d.Speed.ToString("F2") + " driven=" + d.driven;
            if (k < 16f) return;
            d.overrideThrottle = 0f;
            hLog += " dozerReachedZ=" + hMaxZ.ToString("F1") + " dozerMaxY=" + hMaxY.ToString("F2") + " onHilltop=" + (hMaxY > 3.5f) + " atCliff=" + d.AtCliff;
            Debug.Log("BULLDOZER_HILL_RESULT " + hLog);
            HillFinish(0);
        }
    }

    // The mountain road:  -executeMethod BulldozerBuilder.MountainRoadTest      Prints BULLDOZER_ROAD_RESULT.
    // Checks the road strip is there and can be dug, the dozer can drive from the site up onto it, the pegs' and the
    // tint's CUT / FILL match the ground, grading one stretch ticks it (and only it), and grading them all pays.
    // Measures the memory the ground takes and the frame time on the road.  Pictures in Logs/road_*.png.
    static long mrCut0; static string mrPushLog = ""; const float MrPushS = 2f;
    static int mrPhase, mrSide, mrEdgeOut, mrEdgeFrames; static long mrSpill0;
    static float mrT0, mrMaxS, mrMaxY, mrFrameSum, mrFrameMax;
    static int mrFrames, mrUpCut, mrCliff, mrFence, mrOnStrip;
    static string mrLog;
    static long mrCoins0;
    static bool mrFail;

    public static void MountainRoadTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        mrPhase = 0; mrLog = ""; rcLog = ""; mrMaxS = 0f; mrMaxY = -9f; mrFrames = 0; mrFrameSum = 0f; mrFrameMax = 0f; mrCliff = mrFence = mrOnStrip = mrUpCut = 0; mrFail = false;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += RoadTick;
        EditorApplication.EnterPlaymode();
    }

    static void RoadFinish(int code)
    {
        EditorApplication.update -= RoadTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static void RoadCheck(bool ok, string what) { mrLog += " " + what + "=" + (ok ? "ok" : "FAIL"); if (!ok) mrFail = true; }

    static Vector2 RoadPoint(float s, float off, out Vector2 dir)
    {
        int n = MountainRoad.Count;
        int i = Mathf.Clamp(Mathf.FloorToInt(s / MountainRoad.Step), 0, n - 2);
        float u = Mathf.Clamp01((s - MountainRoad.AlongAt(i)) / MountainRoad.Step);
        Vector2 a = MountainRoad.Point(i), b = MountainRoad.Point(i + 1);
        dir = (b - a).normalized;
        return Vector2.Lerp(a, b, u) + new Vector2(-dir.y, dir.x) * off;
    }

    static void RoadTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 600) { Debug.LogError("BULLDOZER_ROAD_FAILED timed out in phase " + mrPhase + " " + mrLog); RoadFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var d = UnityEngine.Object.FindFirstObjectByType<DozerController>();
        var w = VoxelWorld.Instance; var wk = Worker.Instance; var job = MountainRoadJob.Instance;
        if (d == null || w == null || wk == null || job == null || Camera.main == null || Money.Instance == null) return;
        float t = Time.time;
        Vector2 dir;
        if (mrPhase == 0)
        {
            if (t < 2f) return;
            // ---- the strip, and the memory it takes
            float mb = 1f / (1024f * 1024f);
            long oldGround = 1536L * 224 * 1536 + 1536L * 1536 * 2 + 1536L * 1536 * 2 + 48L * 7 * 48;   // before: voxels, heights, grass (array + picture), chunk flags
            mrLog += "length=" + MountainRoad.Length.ToString("F1") + "m start=" + MountainRoad.StartY.ToString("F2") + " top=" + MountainRoad.TopY.ToString("F2")
                   + " stripBlocks=" + w.StripBlocks + " stripVoxelsMB=" + (w.StripVoxels * mb).ToString("F1") + " allVoxelsMB=" + (w.VoxelBytes * mb).ToString("F1")
                   + " groundMB=" + (w.GridBytes * mb).ToString("F1") + " groundBeforeMB=" + (oldGround * mb).ToString("F1")
                   + " unityAllocatedMB=" + (UnityEngine.Profiling.Profiler.GetTotalAllocatedMemoryLong() * mb).ToString("F0")
                   + " groundBuildMs=" + w.BuildMs.ToString("F0") + " (road line " + MountainRoad.BuildMs.ToString("F0") + ", blocks " + w.BlocksMs.ToString("F0") + ", voxels " + w.GenerateMs.ToString("F0") + ", the rest drawing)"
                   + " roadGuidesSetupMs=" + job.SetupMs.ToString("F0")
                   + " hillsideHoles=" + SiteProps.HillsideHoles + " walls=" + SiteProps.HillsideWalls + " roadSquares=" + job.SquareCount + " pegs=" + job.PegCount;
            // every point of the road and the strip has voxels under it
            int missing = 0, roadPts = 0;
            float worst = 0f, sumAbs = 0f, cutShare = 0f, fillShare = 0f; int nCF = 0;
            for (float s = 0f; s <= MountainRoad.Length; s += 1f)
                for (float off = -MountainRoad.StripHalf + 0.2f; off <= MountainRoad.StripHalf - 0.19f; off += 0.95f)
                {
                    Vector2 p = RoadPoint(s, off, out dir);
                    roadPts++;
                    if (w.KindAt(p.x, p.y) == 0) { missing++; continue; }
                    if (Mathf.Abs(off) > MountainRoad.RoadHalf) continue;
                    float cf = w.TopAt(p.x, p.y) - MountainRoad.GradeAt(s);
                    worst = Mathf.Max(worst, Mathf.Abs(cf)); sumAbs += Mathf.Abs(cf); nCF++;
                    if (cf > MountainRoadJob.OnGrade) cutShare++; else if (cf < -MountainRoadJob.OnGrade) fillShare++;
                }
            mrLog += " stripPoints=" + roadPts + " withoutVoxels=" + missing
                   + " startCutFill: worst=" + worst.ToString("F2") + "m mean=" + (sumAbs / Mathf.Max(1, nCF)).ToString("F2") + "m cut=" + (cutShare / Mathf.Max(1, nCF) * 100f).ToString("F0") + "% fill=" + (fillShare / Mathf.Max(1, nCF) * 100f).ToString("F0") + "%";
            // how much cut and fill each stretch starts with (on the road: + cut, - fill)
            string per = "";
            for (int k = 0; k < MountainRoad.Stretches; k++)
            {
                float s0 = k * MountainRoad.Length / MountainRoad.Stretches, s1 = (k + 1) * MountainRoad.Length / MountainRoad.Stretches, lo = 99f, hi = -99f, sum = 0f; int n = 0;
                for (float s = s0; s < s1; s += 0.5f)
                    for (float off = -1.9f; off <= 1.91f; off += 0.95f)
                    {
                        Vector2 p = RoadPoint(s, off, out dir);
                        float cf = w.TopAt(p.x, p.y) - MountainRoad.GradeAt(s);
                        lo = Mathf.Min(lo, cf); hi = Mathf.Max(hi, cf); sum += cf; n++;
                    }
                per += " " + (k + 1) + ":" + (sum / n).ToString("+0.0;-0.0") + "[" + lo.ToString("+0.0;-0.0") + "," + hi.ToString("+0.0;-0.0") + "]";
            }
            mrLog += " perStretch(mean[min,max])" + per;
            // no sudden steps in the starting ground: the biggest rise between neighbouring points 0.25 m apart on a square
            // grid over the strip (and where the strip meets the mountain's mesh)
            float maxStep = 0f; Vector2 stepAt = Vector2.zero;
            for (float z = MountainRoad.Min.y - 5f; z < MountainRoad.Max.y + 5f; z += 0.25f)
                for (float x = MountainRoad.Min.x - 5f; x < MountainRoad.Max.x + 5f; x += 0.25f)
                {
                    if (w.KindAt(x, z) != VoxelWorld.BlockStrip) continue;
                    float h0 = w.TopAt(x, z), st = Mathf.Max(Mathf.Abs(w.TopAt(x + 0.25f, z) - h0), Mathf.Abs(w.TopAt(x, z + 0.25f) - h0));
                    if (st > maxStep) { maxStep = st; stepAt = new Vector2(x, z); }
                }
            mrLog += " biggestStep=" + maxStep.ToString("F2") + "m at " + stepAt.ToString("F1");
            if (maxStep >= 0.45f)
                for (float dz = -0.25f; dz <= 0.26f; dz += 0.25f)
                {
                    mrLog += " |   z+" + dz.ToString("F2") + ":";
                    for (float dx = -0.25f; dx <= 0.51f; dx += 0.25f)
                    {
                        float x = stepAt.x + dx, z = stepAt.y + dz, ss, so, clo, chi; Vector2 sd;
                        float dd = MountainRoad.Nearest(x, z, out ss, out so, out sd);
                        w.ColumnRange(x, z, out clo, out chi);
                        mrLog += " [" + w.TopAt(x, z).ToString("F2") + " k" + w.KindAt(x, z) + " win" + clo.ToString("F1") + "-" + chi.ToString("F1") + " raw" + Mountain.OutsideY(x, z).ToString("F2")
                               + " sh" + MountainRoad.ShapeDelta(x, z).ToString("F2") + " d" + dd.ToString("F1") + " s" + ss.ToString("F0") + "]";
                    }
                }
            // how much dirt each stretch makes: the cut and the fill on the 4 m road, in cubic metres
            string vol = ""; float cutAll = 0f, fillAll = 0f;
            for (int k = 0; k < MountainRoad.Stretches; k++)
            {
                float s0 = k * MountainRoad.Length / MountainRoad.Stretches, s1 = (k + 1) * MountainRoad.Length / MountainRoad.Stretches, vc = 0f, vf = 0f;
                for (float s = s0 + 0.125f; s < s1; s += 0.25f)
                    for (float off = -MountainRoad.RoadHalf + 0.125f; off < MountainRoad.RoadHalf; off += 0.25f)
                    {
                        Vector2 p = RoadPoint(s, off, out dir);
                        float cf = w.TopAt(p.x, p.y) - MountainRoad.GradeAt(s);
                        if (cf > 0f) vc += cf * 0.0625f; else vf -= cf * 0.0625f;
                    }
                vol += " " + (k + 1) + ":" + vc.ToString("F0") + "/" + vf.ToString("F0");
                cutAll += vc; fillAll += vf;
            }
            mrLog += " dirtPerStretch(cut/fill m3)" + vol + " total cut=" + cutAll.ToString("F0") + " fill=" + fillAll.ToString("F0");
            RoadCheck(worst <= MountainRoad.MaxStart + 0.1f, "startCutFillUnderMax");
            RoadCheck(maxStep < 0.45f, "noSuddenSteps");
            RoadCheck(missing == 0, "stripCovered");
            RoadCheck(Mathf.Abs(MountainRoad.TopY - MountainRoad.StartY - 20f) < 0.01f && MountainRoad.Length > 150f && MountainRoad.Length < 185f, "climbs20m");
            // it can be dug: firm diggable ground under the road, and the pick takes it out
            Vector2 q = RoadPoint(80f, 0f, out dir);
            float gy = w.TopAt(q.x, q.y);
            byte under = w.VoxelAtPoint(new Vector3(q.x, gy - 0.3f, q.y)), deep = w.VoxelAtPoint(new Vector3(q.x, gy - 2.5f, q.y));
            long solid0 = w.CountSolid();
            int picked = w.Pick(new Vector3(q.x, gy - 0.1f, q.y), 0.35f, Vector3.zero);
            mrLog += " under=" + under + " deep=" + deep + " picked=" + picked + " countDrop=" + (solid0 - w.CountSolid());
            RoadCheck((under == VoxelWorld.Soil || under == VoxelWorld.Clay) && (deep == VoxelWorld.Soil || deep == VoxelWorld.Clay) && picked > 100 && solid0 - w.CountSolid() == picked, "diggable");
            int ticked0 = job.TickedCount;
            mrLog += " tickedAtStart=" + ticked0; for (int k = 0; k < MountainRoad.Stretches; k++) mrLog += (k == 0 ? " share%:" : ",") + (k + 1) + "=" + (job.StretchShare(k) * 100f).ToString("F0") + (job.Ticked(k) ? "T" : "");
            RoadCheck(ticked0 == 0, "noFreeTicks");
            // 1. the mountain from the quarry floor
            HillShot(new Vector3(8f, 26f, -14f), new Vector3(-30f, 14f, 80f), "road_mountain_from_site.png");
            HillShot(new Vector3(-10f, 40f, 20f), new Vector3(-32f, 12f, 75f), "road_from_above.png");
            mrPhase = 1; mrT0 = t;
            return;
        }
        if (mrPhase == 1)
        {
            if (t - mrT0 < 0.5f) return;
            // ---- the guides match the ground
            job.Refresh();
            int bad = 0, cuts = 0, fills = 0, onGrade = 0; float worstPeg = 0f;
            for (int i = 0; i < job.PegCount; i++)
            {
                Vector2 p = job.PegAt(i);
                float want = w.HeightAt(p.x, p.y) - MountainRoad.GradeAt(job.PegAlong(i));
                string txt = job.PegText(i);
                float shown = txt == "ON GRADE" ? 0f : float.Parse(txt.Substring(txt.IndexOf(' ') + 1), System.Globalization.CultureInfo.InvariantCulture) * (txt.StartsWith("CUT") ? 1f : -1f);
                if (txt.StartsWith("CUT")) cuts++; else if (txt.StartsWith("FILL")) fills++; else onGrade++;
                float err = txt == "ON GRADE" ? (Mathf.Abs(want) <= MountainRoadJob.OnGrade ? 0f : 1f) : Mathf.Abs(shown - want);
                worstPeg = Mathf.Max(worstPeg, err);
                if (err > 0.051f || (want > MountainRoadJob.OnGrade && !txt.StartsWith("CUT")) || (want < -MountainRoadJob.OnGrade && !txt.StartsWith("FILL"))) bad++;
            }
            int tintBad = 0, tintN = 0;
            for (float s = 1f; s < MountainRoad.Length; s += 2.3f)
                for (float off = -1.6f; off <= 1.61f; off += 0.8f)
                {
                    Vector2 p = RoadPoint(s, off, out dir);
                    int tc = job.TintAt(p.x, p.y);
                    if (tc == 99) continue;
                    // the square's own middle is what it was worked out from
                    float cx = Mathf.Floor((p.x - (MountainRoad.Min.x - 3f)) / 0.25f) * 0.25f + (MountainRoad.Min.x - 3f) + 0.125f;
                    float cz = Mathf.Floor((p.y - (MountainRoad.Min.y - 3f)) / 0.25f) * 0.25f + (MountainRoad.Min.y - 3f) + 0.125f;
                    float ss, so; Vector2 sd;
                    MountainRoad.Nearest(cx, cz, out ss, out so, out sd);
                    float cf = w.TopAt(cx, cz) - MountainRoad.GradeAt(ss);
                    int want = cf > MountainRoadJob.OnGrade ? 1 : cf < -MountainRoadJob.OnGrade ? -1 : 0;
                    tintN++; if (tc != want) tintBad++;
                }
            mrLog += " pegs: cut=" + cuts + " fill=" + fills + " onGrade=" + onGrade + " wrong=" + bad + " worstError=" + worstPeg.ToString("F3") + "m tintChecked=" + tintN + " tintWrong=" + tintBad;
            RoadCheck(bad == 0 && cuts > 0 && fills > 0, "pegsMatchGround");
            RoadCheck(tintBad == 0 && tintN > 100, "tintMatchesGround");
            // 2. the tint and the pegs, low down on the first leg, looking up the road
            Vector2 a = RoadPoint(22f, -6f, out dir), b = RoadPoint(40f, 0f, out dir);
            HillShot(new Vector3(a.x, w.HeightAt(a.x, a.y) + 4.5f, a.y), new Vector3(b.x, w.HeightAt(b.x, b.y), b.y), "road_tint_pegs.png");
            Vector2 c = RoadPoint(95f, 9f, out dir), e = RoadPoint(95f, 0f, out dir);
            HillShot(new Vector3(c.x, w.HeightAt(e.x, e.y) + 7f, c.y), new Vector3(e.x, w.HeightAt(e.x, e.y), e.y), "road_tint_pegs_2.png");
            Camera.main.GetComponent<FollowCamera>().enabled = true;
            // ---- the dozer: on the hilltop just short of the road's start, facing up it
            wk.useOverride = true;
            d.dead = false;
            if (!wk.InDozer) wk.GetIn();
            d.useOverride = true;
            Vector2 st = RoadPoint(0f, 0f, out dir);
            Vector2 back = st - dir * 4f;
            mrLog += " startInSite=" + (Mathf.Abs(back.x) <= VoxelWorld.DriveLimit && Mathf.Abs(back.y) <= VoxelWorld.DriveLimit) + " startBlocked=" + SiteProps.Blocks(new Vector3(back.x, 0f, back.y), 2.3f);
            int blockedAlong = 0;
            for (float s = 0f; s < MountainRoad.Length; s += 1f) { Vector2 p = RoadPoint(s, 0f, out dir); if (SiteProps.Blocks(new Vector3(p.x, 0f, p.y), 2.3f)) blockedAlong++; }
            mrLog += " solidThingsOnRoad=" + blockedAlong;
            var way = RcFindWay(new Vector2(VoxelWorld.TrackCentreX(27f), 27f), RoadPoint(3f, 0f, out dir));
            bool reach = rcLog.IndexOf("noClearWay") < 0;
            mrLog += " fromEscapeTrack=" + (reach ? "clear way, " + way.Count + " points" : "NO WAY");
            RoadCheck(reach, "reachableFromTrack");
            RoadPoint(0f, 0f, out dir);
            d.Place(new Vector3(back.x, 0f, back.y), Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg);
            mrPhase = 2; mrT0 = t;
            return;
        }
        if (mrPhase == 2)
        {
            // drive up the road, blade up, steering at a point 4 m further along
            float k = t - mrT0;
            Vector3 pos = d.transform.position;
            float s, off;
            float dist = MountainRoad.Nearest(pos.x, pos.z, out s, out off, out dir);
            Vector2 aim = RoadPoint(s + 4.5f, 0f, out dir);
            Vector3 to = new Vector3(aim.x - pos.x, 0f, aim.y - pos.z);
            float ang = Vector3.SignedAngle(Vector3.ProjectOnPlane(d.transform.forward, Vector3.up), to, Vector3.up);
            d.overrideSteer = Mathf.Clamp(ang / 25f, -1f, 1f);
            d.overrideThrottle = k < 0.5f ? 0f : Mathf.Abs(ang) > 50f ? 0.15f : 1f;
            d.overrideBlade = 1f; d.overrideRipper = 1f;
            if (k > 1f)
            {
                mrFrames++; mrFrameSum += Time.unscaledDeltaTime; mrFrameMax = Mathf.Max(mrFrameMax, Time.unscaledDeltaTime);
                if (d.AtCliff) mrCliff++;
                mrUpCut += d.LastCut;
                if (d.AtFence) mrFence++;
                if (w.KindAt(pos.x, pos.z) == VoxelWorld.BlockStrip) mrOnStrip++;
            }
            if (dist < MountainRoad.CorridorHalf + 0.3f) mrMaxS = Mathf.Max(mrMaxS, s);
            mrMaxY = Mathf.Max(mrMaxY, pos.y);
            if (k > 12f && mrLog.IndexOf("drivePic") < 0) { TestCapture("road_dozer_climbing.png"); mrLog += " drivePic"; }
            if (k < 45f && mrMaxS < 60f) return;
            d.overrideThrottle = 0f; d.overrideSteer = 0f;
            mrLog += " drove: reachedS=" + mrMaxS.ToString("F1") + "m in " + k.ToString("F0") + "s maxY=" + mrMaxY.ToString("F2") + " stepsOnMountainStrip=" + mrOnStrip + " bladeUpScraped=" + mrUpCut + " atCliffSteps=" + mrCliff + " atEdgeSteps=" + mrFence
                   + " frameMs(avg/worst)=" + (mrFrameSum / Mathf.Max(1, mrFrames) * 1000f).ToString("F1") + "/" + (mrFrameMax * 1000f).ToString("F1")
                   + " guideRefreshMs=" + job.LastRefreshMs.ToString("F2")
                   + " ms(avg/max) cut=" + w.MsAvg[0].ToString("F2") + "/" + w.MsMax[0].ToString("F1") + " clods=" + w.MsAvg[1].ToString("F2") + "/" + w.MsMax[1].ToString("F1")
                   + " slump=" + w.MsAvg[2].ToString("F2") + "/" + w.MsMax[2].ToString("F1") + " ground=" + w.MsAvg[3].ToString("F2") + "/" + w.MsMax[3].ToString("F1");
            RoadCheck(mrMaxS > 30f && mrOnStrip > 50 && mrMaxY > MountainRoad.StartY + 2.5f, "drivesOntoStrip");
            RoadCheck(mrUpCut < 400, "bladeUpClearsHill");
            mrPhase = 20; mrT0 = t; mrSide = 1; mrEdgeOut = mrEdgeFrames = 0; mrSpill0 = w.SpilledVoxels;
            return;
        }
        if (mrPhase == 20)
        {
            // cutting along the very edge of where the dozer may drive, blade down and swung right over, each side in
            // turn: the blade's ends must stay over diggable ground, and the dirt it pushes must not be thrown away
            float k = t - mrT0;
            const float S0 = 16f, Off = 3.1f;
            if (k < 0.1f)
            {
                Vector2 st = RoadPoint(S0, mrSide * Off, out dir);
                d.Place(new Vector3(st.x, 0f, st.y), Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg);
                return;
            }
            Vector3 pos = d.transform.position;
            float s, off;
            MountainRoad.Nearest(pos.x, pos.z, out s, out off, out dir);
            Vector2 aim = RoadPoint(s + 4.5f, mrSide * Off, out dir);
            Vector3 to = new Vector3(aim.x - pos.x, 0f, aim.y - pos.z);
            float ang = Vector3.SignedAngle(Vector3.ProjectOnPlane(d.transform.forward, Vector3.up), to, Vector3.up);
            d.overrideSteer = Mathf.Clamp(ang / 25f, -1f, 1f);
            d.overrideBlade = k < 2f ? -1f : 0f;
            d.overrideAngle = k < 2f ? mrSide : 0f;
            d.overrideThrottle = k < 1f ? 0f : 1f;
            if (k > 2f && d.Blade != null)
            {
                foreach (float e in new[] { -2.25f, 2.25f })
                {
                    Vector3 p = d.Blade.TransformPoint(new Vector3(e, -0.6f, 0.8f));
                    mrEdgeFrames++;
                    if (w.KindAt(p.x, p.z) == 0) mrEdgeOut++;
                }
            }
            if (k < 10f) return;
            d.overrideThrottle = 0f; d.overrideSteer = 0f; d.overrideAngle = 0f;
            if (mrSide == 1) { mrSide = -1; mrT0 = t; return; }
            if (k < 16f) return;                                  // let the pushed dirt settle
            long spilled = w.SpilledVoxels - mrSpill0;
            mrLog += " edgeCut: bladeEndOffDiggable=" + mrEdgeOut + "/" + mrEdgeFrames + " dirtThrownAway=" + (spilled * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + "L";
            RoadCheck(mrEdgeOut == 0, "bladeStaysOverDiggable");
            RoadCheck(spilled * VoxelWorld.VoxelVolume < 0.02f, "dirtKept");
            d.overrideBlade = 1f;
            mrPhase = 21; mrT0 = t; mrCut0 = w.TotalCut; mrSpill0 = w.SpilledVoxels; mrPushLog = "";
            return;
        }
        if (mrPhase == 21)
        {
            // a plain push up the middle of the road from its start, blade down: where does the cut dirt go?
            float k = t - mrT0;
            if (k < 0.1f)
            {
                Vector2 st = RoadPoint(MrPushS, 0f, out dir);
                d.Place(new Vector3(st.x, 0f, st.y), Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg);
                return;
            }
            Vector3 pos = d.transform.position;
            float s, off;
            MountainRoad.Nearest(pos.x, pos.z, out s, out off, out dir);
            Vector2 aim = RoadPoint(s + 4.5f, 0f, out dir);
            Vector3 to = new Vector3(aim.x - pos.x, 0f, aim.y - pos.z);
            d.overrideSteer = Mathf.Clamp(Vector3.SignedAngle(Vector3.ProjectOnPlane(d.transform.forward, Vector3.up), to, Vector3.up) / 25f, -1f, 1f);
            d.overrideBlade = k < 2f ? -1f : 0f; d.overrideAngle = 0f;
            d.overrideThrottle = k < 1f ? 0f : 1f;
            if (k > 2f && Mathf.Repeat(k, 1f) < Time.deltaTime)
                mrPushLog += " t" + k.ToString("F0") + "[s=" + s.ToString("F1") + " kind=" + w.KindAt(pos.x, pos.z) + " blade01=" + d.BladeHeight01.ToString("F2") + " cutNow=" + d.LastCut + " cutSoFar=" + (w.TotalCut - mrCut0) + " clods=" + w.ClodCount + " " + d.BladeLoadInfo() + "]";
            if (k > 6f && mrPushLog.IndexOf("pic") < 0 && d.Blade != null)
            {
                Vector3 bp = d.Blade.position;
                HillShot(bp - d.transform.right * 7f + Vector3.up * 1.5f + d.transform.forward * 1.5f, bp + d.transform.forward * 1f, "road_push_side.png");
                mrPushLog += " pic";
            }
            if (k < 9f) return;
            d.overrideThrottle = 0f; d.overrideSteer = 0f;
            mrLog += " centrePush:" + mrPushLog + " spilledL=" + ((w.SpilledVoxels - mrSpill0) * VoxelWorld.VoxelVolume * 1000f).ToString("F0");
            d.overrideBlade = 1f;
            mrPhase = 3; mrT0 = t;
            return;
        }
        if (mrPhase == 3)
        {
            // the cab readout, with the blade down a little
            float k = t - mrT0;
            d.overrideBlade = k < 0.6f ? -1f : 0f; d.overrideThrottle = 0f;
            if (k < 1.5f) return;
            mrLog += " cab=[" + job.CabText.Replace("\n", " | ") + "] arrow=" + job.CabArrow + " legend=" + job.LegendShown;
            RoadCheck(job.CabText.Length > 0 && job.CabText.Contains("Blade edge") && job.CabText.Contains("Road slope") && job.LegendShown, "cabReadout");
            ScreenCapture.CaptureScreenshot(Application.dataPath + "/../Logs/road_cab.png");
            mrPhase = 4; mrT0 = t;
            return;
        }
        if (mrPhase == 4)
        {
            if (t - mrT0 < 0.6f) return;
            d.overrideBlade = 1f;
            // ---- one stretch to grade: it alone gets its tick
            const int K = 4;
            job.Refresh();
            float before = job.StretchShare(K);
            job.TestGradeStretch(K);
            job.Refresh();
            mrLog += " stretch" + (K + 1) + ": before=" + (before * 100f).ToString("F0") + "% after=" + (job.StretchShare(K) * 100f).ToString("F0") + "% ticked=" + job.Ticked(K) + " tickedNow=" + job.TickedCount;
            RoadCheck(!(before >= MountainRoadJob.TickShare) && job.Ticked(K) && job.TickedCount == 1, "gradeTicks");
            RoadCheck(!job.Paid, "notPaidYet");
            mrCoins0 = Money.Instance.Coins;
            mrPhase = 5; mrT0 = t;
            return;
        }
        if (mrPhase == 5)
        {
            if (t - mrT0 < 0.5f) return;
            // ---- the rest to grade: the job pays, once
            for (int k = 0; k < MountainRoad.Stretches; k++) job.TestGradeStretch(k);
            job.Refresh();
            long paid = Money.Instance.Coins - mrCoins0;
            job.Refresh();
            long paidAgain = Money.Instance.Coins - mrCoins0 - paid;
            long solid = w.CountSolid();
            mrLog += " allTicked=" + job.TickedCount + " paid=" + paid + " paidAgain=" + paidAgain + " volumeBooks=" + ((w.SolidCount + w.LoadVoxels) - w.StartTotal) + " trackingError=" + (w.SolidCount - solid);
            RoadCheck(job.TickedCount == MountainRoad.Stretches && job.Paid && paid == MountainRoadJob.Reward && paidAgain == 0, "allTickedPays");
            mrPhase = 6; mrT0 = t;
            return;
        }
        if (mrPhase == 6)
        {
            if (t - mrT0 < 1.2f) return;                 // let the redrawn ground show
            Vector2 a = RoadPoint(22f, -6f, out dir), b = RoadPoint(40f, 0f, out dir);
            HillShot(new Vector3(a.x, w.HeightAt(a.x, a.y) + 4.5f, a.y), new Vector3(b.x, w.HeightAt(b.x, b.y), b.y), "road_graded.png");
            HillShot(new Vector3(-10f, 40f, 20f), new Vector3(-32f, 12f, 75f), "road_graded_above.png");
            Debug.Log((mrFail ? "BULLDOZER_ROAD_FAILED " : "BULLDOZER_ROAD_RESULT ") + mrLog);
            RoadFinish(mrFail ? 1 : 0);
        }
    }

    // A save made before the mountain road loads into the bigger grid:  -executeMethod BulldozerBuilder.RoadOldSaveTest
    // Loads the save that is already there (read only) and checks the ground's books.  Prints BULLDOZER_OLDSAVE_RESULT.
    static int osPhase;
    public static void RoadOldSaveTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        osPhase = 0;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += OldSaveTick;
        EditorApplication.EnterPlaymode();
    }

    static void OldSaveTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_OLDSAVE_FAILED timed out"); EditorApplication.update -= OldSaveTick; EditorApplication.Exit(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var sg = SaveGame.Instance; var job = MountainRoadJob.Instance;
        if (w == null || sg == null || job == null || Worker.Instance == null || Time.time < 2f) return;
        if (osPhase == 0)
        {
            osPhase = 1;
            int version = -1;
            try { using (var f = System.IO.File.OpenRead(SaveGame.FilePath)) using (var z = new System.IO.Compression.GZipStream(f, System.IO.Compression.CompressionMode.Decompress)) using (var r = new System.IO.BinaryReader(z)) version = r.ReadInt32(); }
            catch (Exception e) { Debug.Log("no save to read: " + e.Message); }
            string said = sg.Load();
            long solid = w.CountSolid();
            Vector2 road = MountainRoad.Point(200);
            bool ok = said == "Game loaded." && solid == w.SolidCount && solid + w.LooseTotal() == w.StartTotal && w.KindAt(road.x, road.y) == VoxelWorld.BlockStrip && job.TickedCount == 0;
            Debug.Log((ok ? "BULLDOZER_OLDSAVE_RESULT " : "BULLDOZER_OLDSAVE_FAILED ") + "saveVersion=" + version + " said=[" + said + "] trackingError=" + (w.SolidCount - solid)
                      + " books=" + (solid + w.LooseTotal() - w.StartTotal) + " touchedChunks=" + w.TouchedChunks() + " roadStripThere=" + (w.KindAt(road.x, road.y) == VoxelWorld.BlockStrip) + " ticks=" + job.TickedCount + " loadMs=" + sg.LastMs.ToString("F0"));
            TestCapture("road_oldsave_loaded.png");
            EditorApplication.update -= OldSaveTick;
            EditorSettings.enterPlayModeOptionsEnabled = false;
            EditorApplication.Exit(ok ? 0 : 1);
        }
    }

    // Why the dozer stalls on the mountain road:  -executeMethod BulldozerBuilder.RoadStallTest     Prints BULLDOZER_STALL_RESULT.
    // Cuts up a stretch the way a driver would (thin layers, blade angled), logging the tracks, the blade and the load; when it
    // stalls it tries reversing, then lifting the blade, and logs whether either frees it.
    static int stPhase;
    static float stT0, stNext, stStallAt;
    static string stLog;

    public static void RoadStallTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        stPhase = 0; stLog = ""; stStallAt = -1f;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += StallTick;
        EditorApplication.EnterPlaymode();
    }

    static string StallState(DozerController d, VoxelWorld w)
    {
        Vector3 p = d.transform.position;
        Quaternion yr = Quaternion.Euler(0f, d.transform.eulerAngles.y, 0f);
        System.Func<float, float, float> h = (x, z) => { Vector3 q = p + yr * new Vector3(x, 0f, z); return w.HeightAt(q.x, q.z); };
        float front = (h(-1.4f, 2.2f) + h(1.4f, 2.2f)) * 0.5f, mid = (h(-1.4f, 0.1f) + h(1.4f, 0.1f)) * 0.5f, rear = (h(-1.4f, -2.0f) + h(1.4f, -2.0f)) * 0.5f;
        float ahead = h(0f, 3.0f), left = h(-1.4f, 1.2f), right = h(1.4f, 1.2f);
        Vector3 fl = p + yr * new Vector3(-1.4f, 0f, 2.2f);
        byte under = w.VoxelAtPoint(new Vector3(fl.x, w.TopAt(fl.x, fl.z) - 0.03f, fl.z));
        float s, off; Vector2 dir;
        MountainRoad.Nearest(p.x, p.z, out s, out off, out dir);
        return "s=" + s.ToString("F1") + " off=" + off.ToString("F1") + " v=" + d.Speed.ToString("F2") + " cliff=" + d.AtCliff + " rock=" + d.BlockedByRock + " fence=" + d.AtFence
             + " y=" + p.y.ToString("F2") + " tracks f/m/r=" + front.ToString("F2") + "/" + mid.ToString("F2") + "/" + rear.ToString("F2") + " (f-m " + (front - mid).ToString("F2") + ")"
             + " between=" + ahead.ToString("F2") + " sideL/R=" + left.ToString("F2") + "/" + right.ToString("F2") + " underFront=" + under
             + " pitch=" + (-d.transform.eulerAngles.x > -180f ? Mathf.DeltaAngle(0f, -d.transform.eulerAngles.x) : 0f).ToString("F1")
             + " bladeUp01=" + d.BladeHeight01.ToString("F2") + " cut=" + d.LastCut + " loadL=" + (w.LoadVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + " clods=" + w.ClodCount
             + " grade=" + (p.y - MountainRoad.GradeAt(s)).ToString("F2");
    }

    static void StallTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 400) { Debug.LogError("BULLDOZER_STALL_FAILED timed out " + stLog); EditorApplication.update -= StallTick; EditorApplication.Exit(1); return; }
        if (!EditorApplication.isPlaying) return;
        var d = UnityEngine.Object.FindFirstObjectByType<DozerController>();
        var w = VoxelWorld.Instance; var wk = Worker.Instance;
        if (d == null || w == null || wk == null || MountainRoadJob.Instance == null || Time.time < 2f) return;
        float t = Time.time;
        Vector2 dir;
        if (stPhase == 0)
        {
            wk.useOverride = true; d.dead = false;
            if (!wk.InDozer) wk.GetIn();
            d.useOverride = true;
            float s0 = 9 * MountainRoad.Length / MountainRoad.Stretches - 4f;
            Vector2 st = RoadPoint(s0, 0f, out dir);
            d.Place(new Vector3(st.x, 0f, st.y), Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg);
            stPhase = 1; stT0 = t; stNext = t;
            return;
        }
        float k = t - stT0;
        Vector3 pos = d.transform.position;
        float s, off;
        MountainRoad.Nearest(pos.x, pos.z, out s, out off, out dir);
        var blade = d.Blade;
        Vector3 edge = (blade.TransformPoint(new Vector3(-2.25f, -0.75f, 1.1f)) + blade.TransformPoint(new Vector3(2.25f, -0.75f, 1.1f))) * 0.5f;
        float es, eo; Vector2 ed;
        MountainRoad.Nearest(edge.x, edge.z, out es, out eo, out ed);
        float edgeOff = edge.y - MountainRoad.GradeAt(es);
        if (t >= stNext) { stNext = t + 0.5f; stLog += "\n  " + stPhase + " k=" + k.ToString("F1") + " " + StallState(d, w) + " edge=" + edgeOff.ToString("F2"); }
        if (stPhase == 1)
        {
            // cutting up the road: thin layers, the blade angled to the downhill side
            Vector3 outw = pos - new Vector3(Mountain.CX, pos.y, Mountain.CZ);
            float wy = Vector3.Dot(d.transform.right, outw) > 0f ? d.bladeMaxAngle : -d.bladeMaxAngle;
            d.overrideAngle = Mathf.Abs(d.BladeYaw - wy) < 1f ? 0f : Mathf.Sign(wy - d.BladeYaw);
            float thin = (pos.y - 0.15f) - (MountainRoad.GradeAt(s) + edgeOff);
            float aim = Mathf.Min(edgeOff, -thin);
            d.overrideBlade = aim > 0.03f ? -1f : aim < -0.03f ? 1f : 0f;
            RcSteer(d, RoadPoint(s + 4.5f, 0f, out dir), false, 0.6f);
            if (k > 1f && Mathf.Abs(d.Speed) < 0.05f) { if (stStallAt < 0f) stStallAt = t; } else stStallAt = -1f;
            if ((stStallAt > 0f && t - stStallAt > 2f) || k > 40f)
            {
                stLog += "\n  STALLED (or 40 s) at k=" + k.ToString("F1") + ": " + StallState(d, w) + " -> reversing 3 s, blade still down";
                stPhase = 2; stT0 = t;
            }
            return;
        }
        if (stPhase == 2)
        {
            d.overrideBlade = 0f; d.overrideSteer = 0f; d.overrideThrottle = -1f;
            if (k < 3f) return;
            stLog += "\n  after reversing: " + StallState(d, w) + " -> lift the blade fully and drive on 4 s";
            stPhase = 3; stT0 = t;
            return;
        }
        if (stPhase == 3)
        {
            d.overrideBlade = 1f;
            RcSteer(d, RoadPoint(s + 4.5f, 0f, out dir), false, 0.6f);
            if (k < 4f) return;
            stLog += "\n  after blade up and forward: " + StallState(d, w);
            Debug.Log("BULLDOZER_STALL_RESULT" + stLog);
            EditorApplication.update -= StallTick;
            EditorSettings.enterPlayModeOptionsEnabled = false;
            EditorApplication.Exit(0);
        }
    }

    // The upgrade tree:  -executeMethod BulldozerBuilder.UpgradeTest      Prints BULLDOZER_UPGRADE_RESULT.
    static int uPhase, uMaxShovel;
    static float uPhaseStart;
    static string uLog;
    static Vector3 uStand;

    public static void UpgradeTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        uPhase = 0; uLog = ""; uMaxShovel = 0;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += UpgradeTick;
        EditorApplication.EnterPlaymode();
    }

    static void UpgradeFinish(int code)
    {
        EditorApplication.update -= UpgradeTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static void UpgradeTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_UPGRADE_FAILED timed out in phase " + uPhase + " " + uLog); UpgradeFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var wk = Worker.Instance; var cart = MineCart.Instance; var money = Money.Instance; var up = Upgrades.Instance;
        if (w == null || wk == null || cart == null || money == null || up == null || cart.Length <= 0f) return;
        float t = Time.time;
        if (uPhase == 0)
        {
            if (t < 1f) return;                                                  // let everything start
            if (wk.InDozer) wk.GetOut();
            wk.useOverride = true;
            up.Reset(); money.Clear();
            uLog += "start=P" + up.Level(Upgrades.Branch.Pick) + "/S" + up.Level(Upgrades.Branch.Shovel) + "/B" + up.Level(Upgrades.Branch.Backpack) + "/C" + up.Level(Upgrades.Branch.Cart);
            wk.SetTool(2);
            uLog += " backpackLocked=" + (!wk.backpackOwned && wk.Tool != 2) + " shovelHolds=" + wk.shovelHolds + " cartHolds=" + cart.capacity;
            uLog += " buyBroke=" + up.Buy(Upgrades.Branch.Shovel) + "(" + up.CantBuy(Upgrades.Branch.Shovel) + ")";
            money.TestGrant(10000, Mathf.CeilToInt(50f / (VoxelWorld.VoxelVolume * 1000f)));
            long c0 = money.Coins;
            uLog += " backpackBeforeShovel6=" + up.Buy(Upgrades.Branch.Backpack) + "(" + up.CantBuy(Upgrades.Branch.Backpack) + ")";
            for (int k = 0; k < 5; k++) up.Buy(Upgrades.Branch.Shovel);
            uLog += " shovel=" + up.Level(Upgrades.Branch.Shovel) + " holds=" + wk.shovelHolds + " speed=" + wk.shovelSpeed.ToString("F2") + " paid=" + (c0 - money.Coins) + "(want 632)";
            int g0 = money.GoldStore; c0 = money.Coins;
            uLog += " buyBackpack=" + up.Buy(Upgrades.Branch.Backpack) + " owned=" + wk.backpackOwned + " packHolds=" + wk.packHolds + " goldTaken=" + (g0 - money.GoldStore) + " coinsTaken=" + (c0 - money.Coins);
            uLog += " sellShovel6WithPack=" + up.SellBack(Upgrades.Branch.Shovel) + "(" + up.CantSellBack(Upgrades.Branch.Shovel) + ")";
            uLog += " sellBackpack=" + up.SellBack(Upgrades.Branch.Backpack) + " refunded=" + (money.Coins == c0 && money.GoldStore == g0) + " ownedAfter=" + wk.backpackOwned;
            up.Buy(Upgrades.Branch.Backpack);
            for (int k = 0; k < 7; k++) up.Buy(Upgrades.Branch.Backpack);
            uLog += " backpackMax=" + up.Level(Upgrades.Branch.Backpack) + " packHolds=" + wk.packHolds + " suck=" + wk.suckRate.ToString("F0");
            up.Buy(Upgrades.Branch.Cart);
            uLog += " cart2Holds=" + cart.capacity;
            for (int k = 0; k < 4; k++) up.Buy(Upgrades.Branch.Pick);
            uLog += " pick=" + up.Level(Upgrades.Branch.Pick) + " radius=" + wk.pickRadius.ToString("F2") + " maxedRefused=" + !up.Buy(Upgrades.Branch.Pick);
            // keep and bring back
            var ms = new System.IO.MemoryStream(); var bw = new System.IO.BinaryWriter(ms); up.WriteState(bw); bw.Flush();
            up.Reset();
            bool resetOk = up.Level(Upgrades.Branch.Shovel) == 1 && wk.shovelHolds == 480;
            ms.Position = 0; up.ReadState(new System.IO.BinaryReader(ms));
            uLog += " resetOk=" + resetOk + " afterLoad=P" + up.Level(Upgrades.Branch.Pick) + "/S" + up.Level(Upgrades.Branch.Shovel) + "/B" + up.Level(Upgrades.Branch.Backpack) + "/C" + up.Level(Upgrades.Branch.Cart) + " holdsBack=" + wk.shovelHolds;
            // a real shovelful with Shovel 6: break up a patch beside the cart, then dig it
            Vector3 side = cart.transform.right; side.y = 0f; side.Normalize();
            uStand = cart.transform.position + side * 1.5f;
            Vector3 patch = cart.transform.position + side * 2.8f;
            for (int i = 0; i < 8; i++)
            {
                Vector3 at = patch + cart.transform.forward * (-0.6f + (i % 3) * 0.6f) + side * ((i / 3) * 0.4f);
                at.y = w.FloorAt(at + Vector3.up) + 0.05f;
                w.Pick(at, 0.45f, Vector3.zero);
            }
            Vector3 aim = patch; aim.y = w.FloorAt(aim + Vector3.up);
            Vector3 eye = uStand + Vector3.up * 1.6f, dd = aim - eye, flat = new Vector3(dd.x, 0f, dd.z);
            wk.Teleport(uStand, Facing(flat));
            wk.Look(Mathf.Atan2(-dd.y, flat.magnitude) * Mathf.Rad2Deg);
            wk.SetTool(1);
            uPhase = 1; uPhaseStart = t;
            return;
        }
        if (uPhase == 1)
        {
            if (t - uPhaseStart < 4f) return;                                    // let the broken ground settle
            wk.overrideUse = true;
            uPhase = 2; uPhaseStart = t;
            return;
        }
        if (uPhase == 2)
        {
            uMaxShovel = Mathf.Max(uMaxShovel, w.ShovelVoxels);
            if (t - uPhaseStart < 0.8f) return;
            wk.overrideUse = false;
            uLog += " realScoop=" + (uMaxShovel * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + "L(level1 max 117L)";
            Debug.Log("BULLDOZER_UPGRADE_RESULT " + uLog);
            UpgradeFinish(0);
        }
    }

    // The dump and money:  -executeMethod BulldozerBuilder.DumpTest
    // Fills the cart and tips it by the mine (must pay nothing), fills it again, takes it to the dump and tips it
    // (must pay what the load was worth), checks the coins survive a save and load, and that no dirt was lost.
    // Prints BULLDOZER_DUMP_RESULT.
    static int dPhase, dSteps;
    static float dPhaseStart, dNext;
    static long dVolume0, dCoins0;
    static int dSold0, dCartV0;
    static long dPoured0;
    static float dTipEnd;
    static double dExpected;
    static string dLog;

    public static void DumpTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        dPhase = 0; dLog = "";
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += DumpTick;
        EditorApplication.EnterPlaymode();
    }

    static void DumpFinish(int code)
    {
        EditorApplication.update -= DumpTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    /// Digs the ground beside the cart and drops each load into its tub, as CartTest does.  True when done.
    static bool FillCart(VoxelWorld w, MineCart cart, float t, int want)
    {
        if (w.CartVoxels >= want) return true;
        if (t < dNext) return false;
        dNext = t + 0.08f;
        Vector3 side = cart.transform.right;
        Vector3 at = cart.transform.position + side * 2.4f + cart.transform.forward * (-1f + (dSteps % 9) * 0.25f) + Vector3.up * (0.1f - (dSteps / 9) * 0.12f);
        dSteps++;
        w.Pick(at, 0.35f, Vector3.zero);
        w.Scoop(at, 0.5f, 4000);
        if (w.ShovelVoxels >= VoxelWorld.ClodVoxels) w.Throw(cart.Mouth + Vector3.up * 0.7f, Vector3.zero, 0.25f, 0.4f);
        return false;
    }

    static double CartWorth(VoxelWorld w)
    {
        double v = 0;
        for (int m = VoxelWorld.LooseSoil; m <= VoxelWorld.LooseGold; m++) v += Money.ValueOf(m, w.CartLoadOf(m));
        return v;
    }

    static void DumpTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_DUMP_FAILED timed out in phase " + dPhase + " " + dLog); DumpFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var wk = Worker.Instance; var cart = MineCart.Instance; var money = Money.Instance;
        if (w == null || wk == null || cart == null || money == null || cart.Length <= 0f) return;
        float t = Time.time;
        if (dPhase == 0)
        {
            if (wk.InDozer) wk.GetOut();
            wk.useOverride = true;
            dVolume0 = w.CountSolid() + w.LoadVoxels;
            dCoins0 = money.Coins;
            dLog += "coinsAtStart=" + dCoins0 + " cartAtDumpAtStart=" + cart.AtDump;
            wk.Teleport(cart.transform.position + cart.transform.right * 3.2f, Facing(-cart.transform.right));
            dSteps = 0; dNext = t;
            dPhase = 1; dPhaseStart = t;
            return;
        }
        if (dPhase == 1)
        {
            // fill it a little by the mine and tip it there: no pay
            if (!FillCart(w, cart, t, 1200) && t - dPhaseStart < 15f) return;
            if (t - dPhaseStart < 1.5f) return;
            wk.Teleport(cart.transform.position - cart.transform.right * 1.6f, Facing(cart.transform.right));
            wk.TipCart();
            dPhase = 2; dPhaseStart = t;
            return;
        }
        if (dPhase == 2)
        {
            if (cart.Tipping && t - dPhaseStart < 12f) return;
            if (t - dPhaseStart < 1f) return;
            dLog += " tippedByMine=" + (money.Earned - 0) + "coinsPaid(wantZero) leftInCart=" + w.CartVoxels;
            wk.Teleport(cart.transform.position + cart.transform.right * 3.2f, Facing(-cart.transform.right));
            dSteps = 0; dNext = t;
            dPhase = 3; dPhaseStart = t;
            return;
        }
        if (dPhase == 3)
        {
            // fill it properly, then roll it to the end of the line
            if (!FillCart(w, cart, t, 3000) && t - dPhaseStart < 20f) return;
            if (t - dPhaseStart < 2f) return;                                   // let the last clods land in it
            dExpected = CartWorth(w);
            dLog += " loaded=" + (w.CartVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + "L worth=" + dExpected.ToString("F1");
            cart.SetAlong(cart.EndLimit);
            dLog += " atDumpNow=" + cart.AtDump;
            wk.Teleport(cart.transform.position + cart.transform.right * 1.5f - cart.transform.forward * 1.2f, Facing(-cart.transform.right * 0.8f + cart.transform.forward * 0.6f));
            wk.Look(22f);
            dCoins0 = money.Coins; dSold0 = w.SoldVoxels; dPoured0 = w.PouredFromCart; dCartV0 = w.CartVoxels;
            wk.PressE();                                                      // E at the dump: into the hopper
            dLog += " tippingAfterE=" + cart.Tipping;
            dPhase = 4; dPhaseStart = t;
            return;
        }
        if (dPhase == 4)
        {
            if (t - dPhaseStart > 0.5f && dLog.IndexOf("tipPic") < 0)
            {
                // over his shoulder from behind the cart, looking along the track at the hopper
                Vector3 back = cart.transform.position - cart.transform.forward * 3.4f + cart.transform.right * 0.9f;
                wk.Teleport(back, Facing(cart.transform.forward - cart.transform.right * 0.45f));
                wk.Look(30f);
                dLog += " tipPicWait";
            }
            if (t - dPhaseStart > 0.9f && dLog.IndexOf("tipPic ") < 0 && dLog.IndexOf("tipPicWait") >= 0) { TestCapture("dump_tip.png"); dLog += " tipPic "; }
            if (cart.Tipping && t - dPhaseStart < 12f) { dTipEnd = t; return; }
            if (t - dTipEnd < 3.5f) return;                                    // the last of the stream is still falling in
            dLog += " cartVoxelsAtTip=" + dCartV0 + " pouredAsClods=" + (w.PouredFromCart - dPoured0) + " soldVoxels=" + (w.SoldVoxels - dSold0);
            long paid = money.Coins - dCoins0;
            dLog += " paid=" + paid + " matches=" + (System.Math.Abs(paid - dExpected) < 1.01) + " intoHopper=" + ((w.SoldVoxels - dSold0) * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + "L"
                  + " paidShare=" + (paid / System.Math.Max(1e-6, dExpected) * 100).ToString("F0") + "%" + " leftInCart=" + w.CartVoxels;
            // the coins in a save and back
            var ms = new System.IO.MemoryStream();
            var bw = new System.IO.BinaryWriter(ms);
            money.WriteState(bw); bw.Flush();
            long had = money.Coins;
            money.Clear();
            ms.Position = 0;
            money.ReadState(new System.IO.BinaryReader(ms));
            dLog += " coinsAfterLoad=" + (money.Coins == had);
            // spending: too much is refused, a little is taken
            dLog += " overspendRefused=" + !money.Spend(money.Coins + 1) + " spendOk=" + money.Spend(1) + " coinsNow=" + money.Coins;
            dPhase = 5; dPhaseStart = t;
            return;
        }
        if (dPhase == 5)
        {
            if (t - dPhaseStart < 1.5f) return;
            // gold: the hopper keeps it in the gold store and pays only for the dirt; the shed buys the gold
            int store0 = money.GoldStore; long c0 = money.Coins;
            var load = new int[16]; load[VoxelWorld.LooseSoil] = 400; load[VoxelWorld.LooseGold] = 80;
            money.Pay(load);
            dLog += " goldKept=" + (money.GoldStore - store0 == 80) + " dirtPaid=" + (money.Coins - c0) + "(want~" + Money.ValueOf(VoxelWorld.LooseSoil, 400).ToString("F1") + ")";
            var gm = new System.IO.MemoryStream(); var gw = new System.IO.BinaryWriter(gm); money.WriteState(gw); gw.Flush();
            int storeHad = money.GoldStore; money.Clear(); gm.Position = 0; money.ReadState(new System.IO.BinaryReader(gm));
            dLog += " goldAfterLoad=" + (money.GoldStore == storeHad);
            Vector3 front = SiteProps.GoldShedFront;
            wk.Teleport(front, Facing(Vector3.right));
            long worth = money.GoldWorth; c0 = money.Coins;
            dLog += " atShed=" + wk.AtGoldShed() + " shedAt=(" + front.x.ToString("F1") + "," + front.y.ToString("F2") + "," + front.z.ToString("F1") + ")";
            wk.PressE();
            dLog += " goldSoldFor=" + (money.Coins - c0) + "(worth " + worth + ") goldLeft=" + money.GoldStore;
            wk.PressE();                                                       // nothing left: sells nothing
            dLog += " secondSellAdded=" + (money.Coins - c0 - worth);
            // a look at the shed from out by the rails
            wk.Teleport(front + new Vector3(-6.5f, 0f, -3.5f), Facing(new Vector3(6.5f, 0f, 3.5f)));
            wk.Look(8f);
            dPhase = 8; dPhaseStart = t;
            return;
        }
        if (dPhase == 8)
        {
            if (t - dPhaseStart < 1.5f) return;
            TestCapture("gold_shed.png");
            dPhase = 9; dPhaseStart = t;
            return;
        }
        if (dPhase == 9)
        {
            Vector3 sign = SiteProps.DumpSign;
            wk.Teleport(sign + new Vector3(0f, 0f, 0f) - Vector3.up * 2f + (cart.transform.position - sign).normalized * 9f, Facing(sign - cart.transform.position) );
            wk.Look(10f);
            dPhase = 6; dPhaseStart = t;
            return;
        }
        if (dPhase == 6)
        {
            if (t - dPhaseStart < 1.5f) return;
            TestCapture("dump_sign.png");
            dPhase = 7; dPhaseStart = t;
            return;
        }
        if (dPhase == 7)
        {
            if (t - dPhaseStart < 6f) return;                                      // let the tipped dirt settle
            dLog += " clodsStillLoose=" + w.ClodCount + " volumeChange=" + ((w.CountSolid() + w.LoadVoxels) - dVolume0);
            Debug.Log("BULLDOZER_DUMP_RESULT " + dLog);
            DumpFinish(0);
        }
    }

    // How smooth pushing a big heap is:  -executeMethod BulldozerBuilder.PushPerfTest
    // Drives the dozer forward with the blade dug in for 14 seconds, building and pushing a heap, and logs the
    // frame times (median, 95th, 99th, worst) and where the time goes.  Prints BULLDOZER_PERF_RESULT.
    static int pPhase, pPeakClods;
    static float pStart;
    static readonly List<float> pFrames = new List<float>();
    static long pVolume0;

    public static void PushPerfTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        pPhase = 0; pPeakClods = 0; pFrames.Clear();
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += PerfTick;
        EditorApplication.EnterPlaymode();
    }

    static void PerfFinish(int code)
    {
        EditorApplication.update -= PerfTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static float Pct(List<float> sorted, float q) { return sorted.Count == 0 ? 0f : sorted[Mathf.Clamp(Mathf.RoundToInt(q * (sorted.Count - 1)), 0, sorted.Count - 1)]; }

    static void PerfTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 240) { Debug.LogError("BULLDOZER_PERF_FAILED timed out"); PerfFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var d = UnityEngine.Object.FindFirstObjectByType<DozerController>();
        var w = VoxelWorld.Instance;
        if (d == null || w == null || Worker.Instance == null) return;
        float t = Time.time;
        if (pPhase == 0)
        {
            d.dead = false;
            Worker.Instance.useOverride = true;
            if (!Worker.Instance.InDozer) Worker.Instance.GetIn();
            d.useOverride = true;
            pVolume0 = w.CountSolid() + w.LoadVoxels;
            pStart = t; pPhase = 1;
            return;
        }
        float k = t - pStart;
        if (k < 1.2f) { d.overrideBlade = -1f; d.overrideThrottle = 0f; return; }       // blade down
        if (pPhase == 1) { w.ResetTimings(); pPhase = 2; }
        if (k < 15.2f)
        {
            // push on, the blade held well down so the heap keeps growing; ease it up a little part way
            d.overrideThrottle = 1f; d.overrideBlade = (k > 6f && k < 6.6f) ? 1f : (k < 3.5f ? -1f : 0f); d.overrideRipper = 0f;
            pFrames.Add(Time.unscaledDeltaTime * 1000f);
            pPeakClods = Mathf.Max(pPeakClods, w.ClodCount);
            if (pPhase == 2 && k > 10f) { pPhase = 3; TestCapture("push_heap.png"); }
            return;
        }
        if (pPhase < 4)
        {
            d.overrideThrottle = 0f;
            int n = pFrames.Count;
            float sum = 0f; foreach (var f in pFrames) sum += f;
            var sorted = new List<float>(pFrames); sorted.Sort();
            string parts = "";
            for (int i = 0; i < 5; i++)
                parts += " " + VoxelWorld.MsNames[i] + "=" + (w.MsTotal[i] / Mathf.Max(1, n)).ToString("F2") + "ms/frame(" + (w.Calls[i] > 0 ? (w.MsTotal[i] / w.Calls[i]).ToString("F2") : "0") + "x" + w.Calls[i] + ")";
            Debug.Log("BULLDOZER_PERF_RESULT frames=" + n + " avgMs=" + (sum / Mathf.Max(1, n)).ToString("F1")
                + " p50=" + Pct(sorted, 0.5f).ToString("F1") + " p95=" + Pct(sorted, 0.95f).ToString("F1") + " p99=" + Pct(sorted, 0.99f).ToString("F1")
                + " worst=" + Pct(sorted, 1f).ToString("F1") + " peakClods=" + pPeakClods + " drove=" + (d.transform.position - testPos0).magnitude.ToString("F1")
                + parts + " worstRemeshMs=" + w.MaxRemeshMs.ToString("F1") + "/" + w.MaxRemeshChunks + "chunks"
                + " volumeChange=" + ((w.CountSolid() + w.LoadVoxels) - pVolume0));
            pPhase = 4;
            return;
        }
        // stopped, blade still down against the heap: the clods should settle and go still
        if (pPhase == 4 && k > 17.2f) { int f; float sp = w.ClodMeanSpeed(0.05f, out f); Debug.Log("BULLDOZER_STOP_A clods=" + w.ClodCount + " meanSpeed=" + sp.ToString("F3") + " moving=" + f); pPhase = 5; }
        if (pPhase == 5 && k > 21.2f)
        {
            int f; float sp = w.ClodMeanSpeed(0.05f, out f);
            Debug.Log("BULLDOZER_STOP_RESULT after6s clods=" + w.ClodCount + " meanSpeed=" + sp.ToString("F3") + " moving=" + f + " volumeChange=" + ((w.CountSolid() + w.LoadVoxels) - pVolume0));
            pPhase = 6;
            PerfFinish(0);
        }
    }

    // The mine tunnel:  -executeMethod BulldozerBuilder.TunnelTest
    // Counts what is in each collapse and the seams in the far chambers, pictures each stretch (tunnel_*.png), and
    // stands him with the jackhammer at the chamber seam to check the gold warning comes up (tunnel_warning.png is a
    // screenshot with the HUD).  Prints BULLDOZER_TUNNEL_RESULT.
    static int dustSeam, chipsSeam, glintsSeam; static float tPitch;
    static int tPhase; static string tLog; static float tStart; static int tShot;

    public static void TunnelTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        tPhase = 0; tLog = ""; tShot = 0;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += TunnelTick;
        EditorApplication.EnterPlaymode();
    }

    static void TunnelFinish(int code)
    {
        EditorApplication.update -= TunnelTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    /// What fills a stretch of the tunnel: loose rubble, solid rock, quartz and gold voxels.
    static string TunnelStretch(VoxelWorld w, float a0, float a1, float halfW, float tall, out int loose, out int rock, out int gold)
    {
        loose = rock = gold = 0; int quartz = 0;
        for (float z = a0; z < a1; z += VoxelWorld.Voxel)
            for (float x = -halfW; x < halfW; x += VoxelWorld.Voxel)
                for (float y = 0.03f; y < tall; y += VoxelWorld.Voxel)
                {
                    byte m = w.MaterialAt(new Vector3(VoxelWorld.PortalX + x, y, VoxelWorld.PortalZ + z));
                    if (m >= VoxelWorld.LooseSoil) loose++;
                    else if (m == VoxelWorld.Rock) rock++;
                    else if (m == VoxelWorld.Quartz) quartz++;
                    else if (m == VoxelWorld.Gold) gold++;
                }
        return "loose=" + loose + " rock=" + rock + " quartz=" + quartz + " gold=" + gold;
    }

    static void TunnelShot(Vector3 at, Vector3 look, string file)
    {
        var cam = Camera.main;
        cam.transform.SetPositionAndRotation(at, Quaternion.LookRotation(look - at));
        TestCapture(file);
    }

    static void TunnelTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_TUNNEL_FAILED timed out in phase " + tPhase + " " + tLog); TunnelFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var wk = Worker.Instance; var up = Upgrades.Instance;
        if (w == null || wk == null || up == null) return;
        float t = Time.time;
        float px = VoxelWorld.PortalX, pz = VoxelWorld.PortalZ;
        if (tPhase == 0)
        {
            if (t < 1.5f) return;
            int l0, r0, g0, l1, r1, g1, l2, r2, g2, lo, ro, go;
            tLog += "collapse1[" + TunnelStretch(w, 3f, 7f, 1.5f, 2.6f, out l0, out r0, out g0) + "]";
            tLog += " collapse2[" + TunnelStretch(w, 13f, 19f, 1.5f, 2.6f, out l1, out r1, out g1) + "]";
            tLog += " collapse3[" + TunnelStretch(w, 23f, 28f, 1.5f, 2.6f, out l2, out r2, out g2) + "]";
            tLog += " openStretch[" + TunnelStretch(w, 8f, 12.5f, 1.5f, 2.5f, out lo, out ro, out go) + "]";
            int sl, sr, sg, el, er, eg;
            tLog += " chamber2Walls[" + TunnelStretch(w, 19.5f, 22.5f, 3.2f, 3.0f, out sl, out sr, out sg) + "]";
            tLog += " endWalls[" + TunnelStretch(w, 28f, 31f, 3.5f, 3.2f, out el, out er, out eg) + "]";
            for (int k = 0; k < 3; k++) tLog += " find" + k + "=" + VoxelWorld.FindSpot(k).z.ToString("F1");
            bool rockier = (float)r0 / Mathf.Max(1, l0 + r0) < (float)r1 / Mathf.Max(1, l1 + r1) && (float)r1 / Mathf.Max(1, l1 + r1) < (float)r2 / Mathf.Max(1, l2 + r2);
            tLog += " eachRockier=" + rockier + " openIsOpen=" + (lo + ro < 200) + " seamGold=" + (sg + eg);
            if (!rockier || lo + ro >= 200 || sg + eg == 0 || l0 < 1000 || l1 < 1000 || l2 < 500) { Debug.LogError("BULLDOZER_TUNNEL_FAILED " + tLog); TunnelFinish(1); return; }
            if (wk.InDozer) wk.GetOut();
            wk.useOverride = true;
            tPhase = 1; tStart = t;
            return;
        }
        if (tPhase == 1)
        {
            // pictures: from the mouth, the open stretch, the seam chamber, the end chamber
            if (tShot == 0) { wk.Teleport(new Vector3(px - 4f, 0f, pz - 8f), 0f); TunnelShot(new Vector3(px - 0.6f, 1.6f, pz - 3f), new Vector3(px, 1.0f, pz + 6f), "tunnel_mouth.png"); }
            if (tShot == 1) TunnelShot(new Vector3(px - 0.8f, 1.7f, pz + 8f), new Vector3(px, 1.0f, pz + 15f), "tunnel_open.png");
            if (tShot == 2) TunnelShot(new Vector3(px + 1.4f, 1.6f, pz + 19.8f), new Vector3(px - 2.3f, 1.3f, pz + 22f), "tunnel_seam.png");
            if (tShot == 3) TunnelShot(new Vector3(px - 1.8f, 1.8f, pz + 28.4f), new Vector3(px + 1.5f, 1.2f, pz + 30.8f), "tunnel_end.png");
            tShot++;
            if (tShot < 4) return;
            // the jackhammer at the chamber seam, biggest bite: the warning should be up
            up.SetLevel(Upgrades.Branch.Pick, 6);
            wk.SetTool(0);
            wk.SetJackSize(1f);
            wk.Teleport(new Vector3(px - 1.0f, 0f, pz + 21f), -90f);   // within reach of the west wall
            tPhase = 2; tStart = t;
            return;
        }
        if (tPhase == 2)
        {
            // find a pitch that puts the aim on the seam (quartz or gold) in the west wall
            float best = 0f; bool on = false;
            for (float pitch = -20f; pitch <= 30f && !on; pitch += 1f)
            {
                wk.Look(pitch);
                if (wk.AimingAtSeam) { best = pitch; on = true; }
            }
            if (!on) { if (t - tStart > 3f) { Debug.LogError("BULLDOZER_TUNNEL_FAILED never aimed at the seam " + tLog); TunnelFinish(1); } return; }
            wk.Look(best); tPitch = best;
            tPhase = 3; tStart = t;
            return;
        }
        if (tPhase == 3)
        {
            if (t - tStart < 0.6f) return;
            bool warnBig = wk.GoldWarning;
            ScreenCapture.CaptureScreenshot(Application.dataPath + "/../Logs/tunnel_warning.png");
            tLog += " warningAtBigBite=" + warnBig;
            tPhase = 4; tStart = t;
            return;
        }
        if (tPhase == 4)
        {
            if (t - tStart < 0.6f) return;
            wk.SetJackSize(0f);
            tPhase = 5; tStart = t;
            return;
        }
        if (tPhase == 5)
        {
            if (t - tStart < 0.6f) return;
            bool warnSmall = wk.GoldWarning;
            tLog += " warningAtSmallBite=" + warnSmall;
            if (!tLog.Contains("warningAtBigBite=True") || warnSmall) { Debug.LogError("BULLDOZER_TUNNEL_FAILED " + tLog); TunnelFinish(1); return; }
            // close up on the seam beside him, under the lantern: a few blocks of it twinkle (he is within 4 m)
            TunnelShot(new Vector3(px - 1.2f, 1.5f, pz + 19.9f), new Vector3(px - 2.3f, 1.2f, pz + 20.7f), "tunnel_sparkle.png");
            wk.SetJackSize(0.25f);              // still safe for gold, a bit more dust than the smallest
            wk.overrideUse = true;
            tPhase = 6; tStart = t;
            return;
        }
        if (tPhase == 6)
        {
            // a still aim bores straight in (about a metre in half a second), so sweep it up and down the seam the
            // way a player does, and take the picture after a second and a half of work
            wk.Look(tPitch + Mathf.Sin((t - tStart) * 4f) * 7f);
            if (t - tStart < 1.5f) return;
            TunnelShot(new Vector3(px - 0.6f, 1.75f, pz + 19.7f), new Vector3(px - 2.2f, 1.1f, pz + 21.0f), "tunnel_dust.png");
            int dN, cN, gN; JackFX.Alive(out dN, out cN, out gN);
            tPhase = 7; tStart = t;
            tLog += " hammering=" + wk.Hammering + " " + wk.AimInfo + " dust " + JackFX.DustInfo() + " cam=" + Camera.main.transform.position;
            dustSeam = dN; chipsSeam = cN; glintsSeam = gN;
            return;
        }
        if (tPhase == 7)
        {
            if (t - tStart < 0.3f) return;
            wk.overrideUse = false;
            int dN = dustSeam, cN = chipsSeam, gN = glintsSeam;
            tLog += " dustAtSeam=" + dN + " chipsAtSeam=" + cN + " glintsAtSeam=" + gN;
            bool ok = dN + cN > 0;      // a fifth of a second in: a few chips, maybe a puff (the smallest bite puffs less)
            if (ok) Debug.Log("BULLDOZER_TUNNEL_RESULT " + tLog); else Debug.LogError("BULLDOZER_TUNNEL_FAILED " + tLog);
            TunnelFinish(ok ? 0 : 1);
        }
    }

    // ---------------------------------------------------------------- the game pad
    // The pad's sticks, triggers and d-pad, by name, in the Input Manager (Pad.cs reads them).  Adds any that are
    // missing; leaves everything else as it is.  Axis numbers are Unity's for an Xbox-style pad on Windows, which is
    // what Steam makes of the Steam Controller.
    [MenuItem("Tools/Bulldozer/Add game pad axes")]
    public static void EnsurePadAxes()
    {
        var assets = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/InputManager.asset");
        if (assets == null || assets.Length == 0) { Debug.LogWarning("Pad axes: no InputManager.asset"); return; }
        var so = new SerializedObject(assets[0]);
        var axes = so.FindProperty("m_Axes");
        int added = 0;
        for (int a = 0; a < Pad.AxisNames.Length; a++)
        {
            bool have = false;
            for (int i = 0; i < axes.arraySize && !have; i++)
                have = axes.GetArrayElementAtIndex(i).FindPropertyRelative("m_Name").stringValue == Pad.AxisNames[a];
            if (have) continue;
            axes.arraySize++;
            var e = axes.GetArrayElementAtIndex(axes.arraySize - 1);
            e.FindPropertyRelative("m_Name").stringValue = Pad.AxisNames[a];
            e.FindPropertyRelative("descriptiveName").stringValue = "";
            e.FindPropertyRelative("descriptiveNegativeName").stringValue = "";
            e.FindPropertyRelative("negativeButton").stringValue = "";
            e.FindPropertyRelative("positiveButton").stringValue = "";
            e.FindPropertyRelative("altNegativeButton").stringValue = "";
            e.FindPropertyRelative("altPositiveButton").stringValue = "";
            e.FindPropertyRelative("gravity").floatValue = 0f;
            e.FindPropertyRelative("dead").floatValue = 0.02f;            // Pad.cs takes out its own dead zones
            e.FindPropertyRelative("sensitivity").floatValue = 1f;
            e.FindPropertyRelative("snap").boolValue = false;
            e.FindPropertyRelative("invert").boolValue = Pad.AxisInvert[a];
            e.FindPropertyRelative("type").intValue = 2;                  // joystick axis
            e.FindPropertyRelative("axis").intValue = Pad.AxisNumbers[a];
            e.FindPropertyRelative("joyNum").intValue = 0;                // any pad
            added++;
        }
        if (added == 0) return;
        so.ApplyModifiedPropertiesWithoutUndo();
        AssetDatabase.SaveAssets();
        Debug.Log("Pad axes: added " + added + " to the Input Manager");
    }

    // The game pad path:  -executeMethod BulldozerBuilder.PadTest
    // Drives everything through Pad's override (as if a pad were plugged in), with the dozer's and worker's own
    // overrides off.  In the dozer: the left stick drives, the left trigger raises the blade, and with the gyro button
    // (right stick click) held the right stick's position sets the blade's tilt and angle; let go and the blade stays.
    // Then Y gets out, and on foot: RB changes tool, the left stick walks, the right stick turns him, the right trigger
    // swings the tool.  Prints BULLDOZER_PAD_RESULT.
    static int padPhase; static float padStart; static string padLog; static Vector3 padPos; static float padHeight, padYaw, padTilt, padAngle;
    static int padTool; static bool padSwung;

    public static void PadTest()
    {
        EnsurePadAxes();
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        padPhase = 0; padLog = ""; padSwung = false;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += PadTick;
        EditorApplication.EnterPlaymode();
    }

    static void PadFinish(bool ok)
    {
        if (ok) Debug.Log("BULLDOZER_PAD_RESULT " + padLog);
        else Debug.LogError("BULLDOZER_PAD_FAILED phase " + padPhase + " " + padLog);
        Pad.overrideOn = false; Pad.ClearOverride();
        EditorApplication.update -= PadTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(ok ? 0 : 1);
    }

    static void PadTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { padLog += " timed out"; PadFinish(false); return; }
        if (!EditorApplication.isPlaying) return;
        var wk = Worker.Instance; var d = UnityEngine.Object.FindFirstObjectByType<DozerController>();
        if (wk == null || d == null || VoxelWorld.Instance == null) return;
        float t = Time.time, since = t - padStart;
        switch (padPhase)
        {
            case 0:                                              // in the dozer: drive forward and raise the blade
                if (t < 1f) return;
                wk.useOverride = false; d.useOverride = false;
                if (!wk.InDozer) wk.TryDozer();
                if (!wk.InDozer) { padLog += "could not get in the dozer"; PadFinish(false); return; }
                Pad.ClearOverride(); Pad.overrideOn = true;
                padPos = d.transform.position; padHeight = d.BladeHeight01;
                Pad.oLY = 1f; Pad.oLT = 1f;
                padPhase = 1; padStart = t; return;
            case 1:
                if (since < 1.5f) return;
                float drove = Vector3.Distance(padPos, d.transform.position);
                padLog += "drove=" + drove.ToString("F2") + " bladeUp " + padHeight.ToString("F2") + "->" + d.BladeHeight01.ToString("F2") + " padInUse=" + Pad.InUse;
                if (drove < 0.5f || d.BladeHeight01 < padHeight + 0.2f || !Pad.InUse) { PadFinish(false); return; }
                Pad.oLY = 0f; Pad.oLT = 0f;
                padTilt = d.BladeTilt; padAngle = d.BladeYaw;
                Pad.Hold(Pad.B.RS, true);                        // the gyro button, stick in the middle
                padPhase = 2; padStart = t; return;
            case 2:
                if (since < 0.3f) return;
                Pad.oRX = 0.5f; Pad.oRY = -0.4f;                 // tip the controller: half right, a bit back
                padPhase = 3; padStart = t; return;
            case 3:
                if (since < 1.2f) return;
                {
                    float dz = d.gyroDeadZone;
                    float wantTilt = padTilt + (0.5f - dz) / (1f - dz) * d.bladeMaxTilt;
                    float wantAngle = padAngle - (0.4f - dz) / (1f - dz) * d.bladeMaxAngle;
                    padLog += " gyroTilt=" + d.BladeTilt.ToString("F2") + "(want " + wantTilt.ToString("F2") + ") gyroAngle=" + d.BladeYaw.ToString("F2") + "(want " + wantAngle.ToString("F2") + ") gyroHeld=" + d.GyroHeld;
                    if (!d.GyroHeld || Mathf.Abs(d.BladeTilt - wantTilt) > 0.3f || Mathf.Abs(d.BladeYaw - wantAngle) > 0.8f) { PadFinish(false); return; }
                }
                Pad.Hold(Pad.B.RS, false);                       // let go of the gyro button ...
                padTilt = d.BladeTilt; padAngle = d.BladeYaw;
                Pad.oRX = -1f; Pad.oRY = 1f;                     // ... and wave the stick about: the blade must stay
                padPhase = 4; padStart = t; return;
            case 4:
                if (since < 1f) return;
                padLog += " afterRelease tilt=" + d.BladeTilt.ToString("F2") + " angle=" + d.BladeYaw.ToString("F2");
                if (Mathf.Abs(d.BladeTilt - padTilt) > 0.01f || Mathf.Abs(d.BladeYaw - padAngle) > 0.01f) { PadFinish(false); return; }
                Pad.oRX = 0f; Pad.oRY = 0f;
                Pad.Hold(Pad.B.Y, true);                         // Y: get out
                padPhase = 5; padStart = t; return;
            case 5:
                if (since < 0.4f) return;
                Pad.Hold(Pad.B.Y, false);
                padLog += " outWithY=" + !wk.InDozer;
                if (wk.InDozer) { PadFinish(false); return; }
                padTool = wk.Tool;
                Pad.Hold(Pad.B.RB, true);                        // RB: next tool
                padPhase = 6; padStart = t; return;
            case 6:
                if (since < 0.3f) return;
                Pad.Hold(Pad.B.RB, false);
                padLog += " tool " + padTool + "->" + wk.Tool;
                if (wk.Tool == padTool) { PadFinish(false); return; }
                padPos = wk.transform.position; padYaw = wk.transform.eulerAngles.y;
                Pad.oLY = 1f; Pad.oRX = 0.7f;                    // walk on, turning right
                padPhase = 7; padStart = t; return;
            case 7:
                if (since < 1.2f) return;
                {
                    float walked = Vector3.Distance(new Vector3(padPos.x, 0f, padPos.z), new Vector3(wk.transform.position.x, 0f, wk.transform.position.z));
                    float turned = Mathf.Abs(Mathf.DeltaAngle(padYaw, wk.transform.eulerAngles.y));
                    padLog += " walked=" + walked.ToString("F2") + " turned=" + turned.ToString("F0");
                    if (walked < 0.5f || turned < 20f) { PadFinish(false); return; }
                }
                Pad.oLY = 0f; Pad.oRX = 0f; Pad.oRT = 1f;        // right trigger: use the tool
                padPhase = 8; padStart = t; return;
            case 8:
                if (wk.SwingNow != "None") padSwung = true;
                if (since < 0.8f) return;
                Pad.oRT = 0f;
                padLog += " swungWithRT=" + padSwung;
                PadFinish(padSwung);
                return;
        }
    }

    // ---------------------------------------------------------------- the Windows game
    // Builds the game on its own, for adding to Steam as a non-Steam game (so Steam Input works on it).
    //   -executeMethod BulldozerBuilder.BuildWindowsFromCommandLine     (or Tools > Bulldozer > Build Windows game)
    // Lands in voxel-dozer-unity/Builds/DiggerGame/DiggerGame.exe.  Prints BULLDOZER_WINBUILD_RESULT.
    const string WindowsExe = "Builds/DiggerGame/DiggerGame.exe";

    [MenuItem("Tools/Bulldozer/Build Windows game")]
    public static void BuildWindows() { BuildWindowsGame(); }

    public static void BuildWindowsFromCommandLine() { EditorApplication.Exit(BuildWindowsGame() ? 0 : 1); }

    static bool BuildWindowsGame()
    {
        EnsurePadAxes();
        // shaders the scripts look up by name at run time, which no material in the scene points at
        IncludeShaders("Voxel/FireFlame", "Voxel/FireParticle", "Voxel/FireSmoke", "Voxel/Terrain", "Unlit/Color", "Sprites/Default", "Standard");
        KeepInstancingShaders();
        var opts = new BuildPlayerOptions
        {
            scenes = new[] { ScenePath },
            locationPathName = WindowsExe,
            target = BuildTarget.StandaloneWindows64,
            options = BuildOptions.None,                           // not a Development build
        };
        var report = BuildPipeline.BuildPlayer(opts);
        bool ok = report.summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded;
        if (ok) Debug.Log("BULLDOZER_WINBUILD_RESULT " + System.IO.Path.GetFullPath(WindowsExe) + " " + (report.summary.totalSize / (1024 * 1024)) + " MB in " + report.summary.totalTime.TotalSeconds.ToString("F0") + " s");
        else Debug.LogError("BULLDOZER_WINBUILD_FAILED " + report.summary.result + " errors=" + report.summary.totalErrors);
        return ok;
    }

    // The loose dirt (clods) is drawn many at a time with instancing, from materials made in code.  No material saved
    // in the project uses instancing, so the build threw the shaders' instancing versions away and the dirt in the
    // built game was drawn as nothing (in the editor everything is kept, so it showed there).  Keep them all.
    static void KeepInstancingShaders()
    {
        var gs = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset");
        if (gs == null || gs.Length == 0) return;
        var so = new SerializedObject(gs[0]);
        var p = so.FindProperty("m_InstancingStripping");
        if (p == null || p.intValue == 2) return;
        p.intValue = 2;                                            // 0 strip unused, 1 strip all, 2 keep all
        so.ApplyModifiedPropertiesWithoutUndo(); AssetDatabase.SaveAssets();
    }

    static void IncludeShaders(params string[] names)
    {
        var gs = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset");
        if (gs == null || gs.Length == 0) return;
        var so = new SerializedObject(gs[0]);
        var list = so.FindProperty("m_AlwaysIncludedShaders");
        bool changed = false;
        foreach (var n in names)
        {
            var sh = Shader.Find(n);
            if (sh == null) { Debug.LogWarning("Build: shader " + n + " not found"); continue; }
            bool have = false;
            for (int i = 0; i < list.arraySize && !have; i++) have = list.GetArrayElementAtIndex(i).objectReferenceValue == sh;
            if (have) continue;
            list.arraySize++;
            list.GetArrayElementAtIndex(list.arraySize - 1).objectReferenceValue = sh;
            changed = true;
        }
        if (changed) { so.ApplyModifiedPropertiesWithoutUndo(); AssetDatabase.SaveAssets(); }
    }

    // The jackhammer:  -executeMethod BulldozerBuilder.JackTest
    // Picks rock at Pick 5 for 4 s, then jackhammers rock (Jackhammer 1, biggest bite) for 4 s: it must break much
    // more.  Then breaks gold in the quartz seam with a big bite (some is smashed) and a small one (none is).
    // Prints BULLDOZER_JACK_RESULT.
    static int jPhase; static string jLog; static float jStart; static Vector3 jSpot, jStand; static int jFirm0, jPickBroke; static bool jSawHammer;
    static int jMaxDust, jMaxChips; static float jMaxShake; static bool jAimSteady = true; static Vector3 jAim0;

    public static void JackTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        jPhase = 0; jLog = ""; jSawHammer = false; jMaxDust = jMaxChips = 0; jMaxShake = 0f; jAimSteady = true;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += JackTick;
        EditorApplication.EnterPlaymode();
    }

    static void JackFinish(int code)
    {
        EditorApplication.update -= JackTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    /// Firm rock (rock, quartz, gold) in a 1.8 m box round a spot.
    static int FirmNear(VoxelWorld w, Vector3 c)
    {
        int n = 0;
        for (float x = -0.9f; x <= 0.9f; x += VoxelWorld.Voxel)
            for (float y = -0.9f; y <= 0.9f; y += VoxelWorld.Voxel)
                for (float z = -0.9f; z <= 0.9f; z += VoxelWorld.Voxel)
                {
                    byte m = w.MaterialAt(c + new Vector3(x, y, z));
                    if (m >= VoxelWorld.Rock && m <= VoxelWorld.Gold) n++;
                }
        return n;
    }

    /// Bare rock on top, with flat ground to stand on 1.3 m south of it.  Stands him there aiming at it.
    static bool StandAtRock(VoxelWorld w, Worker wk, Vector3 avoid)
    {
        for (float x = -30f; x <= 30f; x += 0.5f)
            for (float z = -30f; z <= 30f; z += 0.5f)
            {
                var p = new Vector3(x, 0f, z);
                if ((p - new Vector3(avoid.x, 0f, avoid.z)).sqrMagnitude < 16f) continue;
                float f = w.FloorAt(p + Vector3.up * 8f);
                if (w.MaterialAt(new Vector3(x, f - 0.03f, z)) != VoxelWorld.Rock) continue;
                if (w.MaterialAt(new Vector3(x, f - 0.6f, z)) != VoxelWorld.Rock) continue;
                var st = new Vector3(x, 0f, z - 1.3f);
                float fs = w.FloorAt(st + Vector3.up * 8f);
                if (Mathf.Abs(fs - f) > 0.25f || SiteProps.Blocks(st, 0.4f, true)) continue;
                jSpot = new Vector3(x, f, z); jStand = new Vector3(st.x, fs, st.z);
                Vector3 eye = new Vector3(st.x, fs + 1.6f, st.z), d = jSpot - eye, flat = new Vector3(d.x, 0f, d.z);
                wk.Teleport(new Vector3(st.x, fs, st.z), Facing(flat));
                wk.Look(Mathf.Atan2(-d.y, flat.magnitude) * Mathf.Rad2Deg);
                return true;
            }
        return false;
    }

    static void JackTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_JACK_FAILED timed out in phase " + jPhase + " " + jLog); JackFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var wk = Worker.Instance; var up = Upgrades.Instance;
        if (w == null || wk == null || up == null) return;
        float t = Time.time;
        if (wk.Hammering) jSawHammer = true;
        if (jPhase == 1 || jPhase == 2)
        {
            // work across a patch of the rock, as a player would, not one spot
            int k = Mathf.FloorToInt((t - jStart) / 0.45f);
            var target = jSpot + new Vector3((k % 4) * 0.33f - 0.5f, 0f, ((k / 4) % 4) * 0.33f - 0.5f);
            target.y = w.FloorAt(target + Vector3.up * 3f);
            Vector3 eye = jStand + Vector3.up * 1.6f, d = target - eye, flat = new Vector3(d.x, 0f, d.z);
            wk.Teleport(jStand, Facing(flat));
            wk.Look(Mathf.Atan2(-d.y, flat.magnitude) * Mathf.Rad2Deg);
        }
        if (jPhase == 0)
        {
            if (t < 1f) return;
            if (wk.InDozer) wk.GetOut();
            wk.useOverride = true;
            up.SetLevel(Upgrades.Branch.Pick, 5);
            wk.SetTool(0);
            if (!StandAtRock(w, wk, new Vector3(999f, 0f, 999f))) { Debug.LogError("BULLDOZER_JACK_FAILED no bare rock found"); JackFinish(1); return; }
            jFirm0 = FirmNear(w, jSpot);
            wk.overrideUse = true;
            jPhase = 1; jStart = t;
            return;
        }
        if (jPhase == 1)
        {
            if (t - jStart < 4f) return;
            wk.overrideUse = false;
            jPickBroke = jFirm0 - FirmNear(w, jSpot);
            jLog += "pickAt=" + jSpot + " pickBroke=" + jPickBroke;
            Vector3 first = jSpot;
            up.SetLevel(Upgrades.Branch.Pick, 6);
            wk.SetJackSize(1f);
            wk.SetTool(0);
            if (!StandAtRock(w, wk, first)) { Debug.LogError("BULLDOZER_JACK_FAILED no second rock found " + jLog); JackFinish(1); return; }
            jFirm0 = FirmNear(w, jSpot);
            wk.overrideUse = true;
            jPhase = 2; jStart = t;
            return;
        }
        if (jPhase == 2)
        {
            int dN, cN, gN; JackFX.Alive(out dN, out cN, out gN);
            jMaxDust = Mathf.Max(jMaxDust, dN); jMaxChips = Mathf.Max(jMaxChips, cN);
            jMaxShake = Mathf.Max(jMaxShake, FollowCamera.LastShake);
            if (t - jStart < 4f) return;
            wk.overrideUse = false;
            jLog += " dust=" + jMaxDust + " chips=" + jMaxChips + " shake=" + jMaxShake.ToString("F3") + "m";
            int jackBroke = jFirm0 - FirmNear(w, jSpot);
            jLog += " jackAt=" + jSpot + " jackBroke=" + jackBroke + " hammered=" + jSawHammer + " goldShatteredWhileTesting=" + wk.GoldShattered;
            float bigShatter = wk.JackShatter; wk.SetJackSize(0f); float smallShatter = wk.JackShatter;
            jLog += " shatterBigBite=" + bigShatter.ToString("F2") + " shatterSmallBite=" + smallShatter.ToString("F2");
            // gold in the seam: break half of it with a big bite and half with a small one
            var gold = new System.Collections.Generic.List<Vector3>();
            for (float x = -40f; x <= 40f && gold.Count < 300; x += 0.5f)
                for (float z = -40f; z <= 40f && gold.Count < 300; z += 0.5f)
                {
                    float f = w.FloorAt(new Vector3(x, 8f, z));
                    for (float y = f - 4f; y < f; y += VoxelWorld.Voxel)
                        if (w.MaterialAt(new Vector3(x, y, z)) == VoxelWorld.Gold) { gold.Add(new Vector3(x, y, z)); break; }
                }
            int smashedBig = 0, smashedSmall = 0;
            for (int i = 0; i < gold.Count; i++)
            {
                w.Pick(gold[i], 0.1f, Vector3.zero, i % 2 == 0 ? 0.4f : 0f);
                if (i % 2 == 0) smashedBig += w.LastShattered; else smashedSmall += w.LastShattered;
            }
            jLog += " goldSpots=" + gold.Count + " smashedBigBite=" + smashedBig + " smashedSmallBite=" + smashedSmall;
            bool ok = jSawHammer && jackBroke > jPickBroke * 1.3f && jPickBroke > 0 && bigShatter > 0f && smallShatter == 0f && gold.Count > 10 && smashedBig > 0 && smashedSmall == 0
                && jMaxDust > 5 && jMaxChips > 5 && jMaxShake > 0.004f && jMaxShake < 0.02f;
            if (!ok) { Debug.LogError("BULLDOZER_JACK_FAILED " + jLog); JackFinish(1); return; }
            jPhase = 3; jStart = t;
            return;
        }
        if (jPhase == 3)
        {
            // let go: no shake next frame, and the dust thins out within a few seconds
            if (t - jStart < 0.3f) return;
            if (FollowCamera.LastShake > 0f) { Debug.LogError("BULLDOZER_JACK_FAILED still shaking after letting go " + jLog); JackFinish(1); return; }
            if (t - jStart < 3f) return;
            int dN, cN, gN; JackFX.Alive(out dN, out cN, out gN);
            jLog += " dustAfter3s=" + dN + " chipsAfter3s=" + cN;
            bool ok = dN < jMaxDust / 3 + 2 && cN == 0;
            if (ok) Debug.Log("BULLDOZER_JACK_RESULT " + jLog);
            else Debug.LogError("BULLDOZER_JACK_FAILED " + jLog);
            JackFinish(ok ? 0 : 1);
        }
    }

    // The backpack:  -executeMethod BulldozerBuilder.BackpackTest
    // Beside the cart: sucks at firm ground (must take nothing), picks a patch loose, sucks it up (must stop at
    // 500 litres), saves and loads (the load must come back), then squirts it into the cart with Q.
    // Volume must not change.  Prints BULLDOZER_PACK_RESULT.
    static int bPhase, bAimStep, bMaxPack, bPackSaved, bCart0;
    static float bPhaseStart, bNext;
    static long bVolume0;
    static string bLog;
    static Vector3 bStand, bSide, bPatch;

    public static void BackpackTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        bPhase = 0; bLog = ""; bMaxPack = 0;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += BackpackTick;
        EditorApplication.EnterPlaymode();
    }

    static void BackpackFinish(int code)
    {
        EditorApplication.update -= BackpackTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    /// Turns him (standing at bStand) to aim at a spot on the ground.
    static void AimAt(Worker wk, Vector3 target)
    {
        Vector3 eye = bStand + Vector3.up * 1.6f, d = target - eye;
        Vector3 flat = new Vector3(d.x, 0f, d.z);
        wk.Teleport(bStand, Facing(flat));
        wk.Look(Mathf.Atan2(-d.y, flat.magnitude) * Mathf.Rad2Deg);
    }

    static float Litres(int voxels) { return voxels * VoxelWorld.VoxelVolume * 1000f; }

    static void BackpackTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_PACK_FAILED timed out in phase " + bPhase + " " + bLog); BackpackFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var wk = Worker.Instance; var cart = MineCart.Instance;
        if (w == null || wk == null || cart == null || cart.Length <= 0f) return;
        float t = Time.time;
        if (w.PackVoxels > bMaxPack) bMaxPack = w.PackVoxels;
        if (bPhase == 0)
        {
            if (wk.InDozer) wk.GetOut();
            wk.useOverride = true;
            bSide = cart.transform.right; bSide.y = 0f; bSide.Normalize();
            bStand = cart.transform.position + bSide * 1.5f;
            bPatch = cart.transform.position + bSide * 2.8f;
            bVolume0 = w.CountSolid() + w.LoadVoxels;
            if (Upgrades.Instance != null) Upgrades.Instance.SetLevel(Upgrades.Branch.Backpack, 4);   // 500 litres
            wk.SetTool(2);
            AimAt(wk, new Vector3(bPatch.x, w.FloorAt(bPatch + Vector3.up), bPatch.z));
            wk.overrideUse = true;                               // suck at firm ground: nothing should come
            bPhase = 1; bPhaseStart = t;
            return;
        }
        if (bPhase == 1)
        {
            if (t - bPhaseStart < 2.5f) return;
            wk.overrideUse = false;
            bLog += "firmGroundTaken=" + w.PackVoxels + "voxels";
            // break a patch of ground loose with the pick, as he would, and let it settle into loose rubble
            for (int i = 0; i < 12; i++)
            {
                Vector3 at = bPatch + cart.transform.forward * (-0.8f + (i % 3) * 0.8f) + bSide * (((i / 3) % 2) * 0.6f);
                at.y = w.FloorAt(at + Vector3.up) + (i < 6 ? 0.05f : -0.3f);
                w.Pick(at, 0.42f, Vector3.up * 0.3f);
            }
            bPhase = 2; bPhaseStart = t;
            return;
        }
        if (bPhase == 2)
        {
            if (t - bPhaseStart < 5f) return;
            bLog += " looseMade=" + (w.ClodCount) + "clodsStillMoving";
            wk.overrideUse = true;
            bAimStep = 0; bNext = t;
            bPhase = 3; bPhaseStart = t;
            return;
        }
        if (bPhase == 3)
        {
            // sweep the nozzle over the loose patch until the backpack is full
            if (t >= bNext)
            {
                bNext = t + 0.6f;
                Vector3 at = bPatch + cart.transform.forward * (-0.9f + (bAimStep % 4) * 0.6f) + bSide * (((bAimStep / 4) % 3) * 0.35f);
                at.y = w.FloorAt(at + Vector3.up);
                AimAt(wk, at);
                bAimStep++;
            }
            if (t - bPhaseStart > 3f && bLog.IndexOf("suckPic") < 0) { TestCapture("backpack_suck.png"); bLog += " suckPic"; }
            bool full = w.PackVoxels >= wk.packHolds - VoxelWorld.ClodVoxels;
            if (!full && t - bPhaseStart < 25f) return;
            wk.overrideUse = false;
            bLog += " packFull=" + full + " packLitres=" + Litres(w.PackVoxels).ToString("F0") + " suckTook=" + (t - bPhaseStart).ToString("F1") + "s"
                  + " sucked=" + Litres(wk.Sucked).ToString("F0") + "L";
            // keep sucking a while longer: nothing more may go in
            wk.overrideUse = true;
            bPhase = 4; bPhaseStart = t;
            return;
        }
        if (bPhase == 4)
        {
            if (t - bPhaseStart < 2f) return;
            wk.overrideUse = false;
            bLog += " maxPack=" + bMaxPack + "/" + wk.packHolds + " neverOver=" + (bMaxPack <= wk.packHolds);
            // save and load: the backpack's load must come back
            bPackSaved = w.PackVoxels;
            var ms = new System.IO.MemoryStream();
            var bw = new System.IO.BinaryWriter(ms);
            w.WriteSave(bw); bw.Flush();
            ms.Position = 0;
            w.ReadSave(new System.IO.BinaryReader(ms));
            bLog += " packAfterLoad=" + (w.PackVoxels == bPackSaved);
            // to the cart, and Q
            bCart0 = w.CartVoxels;
            AimAt(wk, cart.Mouth);
            wk.StartPour();
            bLog += " pourStarted=" + wk.Pouring;
            bPhase = 5; bPhaseStart = t;
            return;
        }
        if (bPhase == 5)
        {
            if (t - bPhaseStart > 0.8f && bLog.IndexOf("pourPic") < 0) { TestCapture("backpack_pour.png"); bLog += " pourPic"; }
            if (wk.Pouring && t - bPhaseStart < 15f) return;
            bLog += " pourTook=" + (t - bPhaseStart).ToString("F1") + "s";
            bPhase = 6; bPhaseStart = t;
            return;
        }
        if (bPhase == 6)
        {
            if (t - bPhaseStart < 3f) return;                       // let the last of it land in the tub
            bLog += " packLeft=" + Litres(w.PackVoxels).ToString("F0") + "L intoCart=" + Litres(w.CartVoxels - bCart0).ToString("F0") + "L of " + Litres(bPackSaved).ToString("F0") + "L"
                  + " missedCart=" + Litres(bPackSaved - (w.CartVoxels - bCart0) - w.PackVoxels).ToString("F0") + "L";
            bPhase = 7; bPhaseStart = t;
            return;
        }
        if (bPhase == 7)
        {
            if (t - bPhaseStart < 7f) return;
            bLog += " volumeChange=" + ((w.CountSolid() + w.LoadVoxels) - bVolume0);
            Debug.Log("BULLDOZER_PACK_RESULT " + bLog);
            BackpackFinish(0);
        }
    }

    // The motor cart:  -executeMethod BulldozerBuilder.MotorCartTest
    // Without the motor he can't ride.  Buys the Motor cart (Upgrades.SetLevel), fills the cart by the mine mouth,
    // rides it out to the dump under power (W), tips it with E while still on it and checks it pays what the load
    // was worth (as the hand cart does), drives back into the mine (S) until it stops, then gets off.
    // Prints BULLDOZER_MOTORCART_RESULT, or BULLDOZER_MOTORCART_FAILED if a check didn't hold.
    static int mPhase;
    static float mPhaseStart, mAlong0, mTopSpeed, mTipEnd;
    static long mCoins0;
    static double mExpected;
    static bool mOk;
    static string mLog;

    public static void MotorCartTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        mPhase = 0; mLog = ""; mOk = true; mTopSpeed = 0f;
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += MotorCartTick;
        EditorApplication.EnterPlaymode();
    }

    static void MotorCartFinish(int code)
    {
        EditorApplication.update -= MotorCartTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static void MCheck(string name, bool good) { mLog += " " + name + "=" + good; if (!good) mOk = false; }

    static void MotorCartTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_MOTORCART_FAILED timed out in phase " + mPhase + " " + mLog); MotorCartFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var wk = Worker.Instance; var cart = MineCart.Instance; var money = Money.Instance; var up = Upgrades.Instance;
        if (w == null || wk == null || cart == null || money == null || up == null || cart.Length <= 0f) return;
        float t = Time.time;
        if (mPhase == 0)
        {
            if (t < 1f) return;                                                  // let everything start
            if (wk.InDozer) wk.GetOut();
            wk.useOverride = true;
            up.Reset(); money.Clear();
            Vector3 at, f;
            cart.HoldPlace(-1, out at, out f);
            wk.Teleport(at, Facing(f));
            MCheck("noRideWithoutMotor", !wk.RideCart() && !wk.RidingCart);
            up.SetLevel(Upgrades.Branch.Cart, Upgrades.MotorCartLevel);
            MCheck("motorOwned", cart.spec.motor && up.HasMotorCart);
            mLog += " speed=" + cart.spec.motorSpeed + " holdsL=" + (cart.capacity * VoxelWorld.VoxelVolume * 1000f).ToString("F0");
            wk.Teleport(cart.transform.position + cart.transform.right * 3.2f, Facing(-cart.transform.right));
            dSteps = 0; dNext = t;
            mPhase = 1; mPhaseStart = t;
            return;
        }
        if (mPhase == 1)
        {
            if (!FillCart(w, cart, t, 3000) && t - mPhaseStart < 20f) return;
            if (t - mPhaseStart < 2f) return;                                   // let the last clods land in it
            mExpected = CartWorth(w);
            mLog += " loaded=" + (w.CartVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + "L worth=" + mExpected.ToString("F1");
            var box = cart.transform.Find("Motor");
            MCheck("motorBoxShown", box != null && box.gameObject.activeSelf);
            mAlong0 = cart.Along;
            MCheck("startsAwayFromDump", !cart.AtDump);
            Vector3 at, f;
            cart.HoldPlace(-1, out at, out f);
            wk.Teleport(at, Facing(f));
            MCheck("getsOn", wk.RideCart() && wk.RidingCart);
            wk.overrideWalk = 1f;                                               // W: drive out
            mPhase = 2; mPhaseStart = t;
            return;
        }
        if (mPhase == 2)
        {
            mTopSpeed = Mathf.Max(mTopSpeed, cart.MotorSpeedNow);
            if (t - mPhaseStart > 1.5f && mLog.IndexOf("ridePic") < 0) { TestCapture("motor_cart_ride.png"); mLog += " ridePic"; }
            bool stopped = t - mPhaseStart > 1f && Mathf.Abs(cart.MotorSpeedNow) < 1e-3f;
            if (!stopped && t - mPhaseStart < 60f) return;
            float took = t - mPhaseStart;
            mLog += " rode=" + (cart.Along - mAlong0).ToString("F1") + "m in " + took.ToString("F1") + "s topSpeed=" + mTopSpeed.ToString("F2");
            MCheck("reachedDump", cart.AtDump);
            MCheck("atEndOfLine", cart.Along >= cart.EndLimit - 0.05f);
            MCheck("topSpeedOk", mTopSpeed > cart.spec.motorSpeed * 0.95f);
            Vector3 at, f;
            cart.RidePlace(out at, out f);
            MCheck("onFootboard", wk.RidingCart && Vector3.Distance(wk.transform.position, at) < 0.05f);
            wk.overrideWalk = 0f;
            mCoins0 = money.Coins;
            wk.PressE();                                                        // E at the dump: tip it, stay on
            MCheck("tipsAtDump", cart.Tipping);
            MCheck("staysOn", wk.RidingCart);
            mPhase = 3; mPhaseStart = t;
            return;
        }
        if (mPhase == 3)
        {
            if (t - mPhaseStart > 0.8f && mLog.IndexOf("tipPic") < 0) { TestCapture("motor_cart_tip.png"); mLog += " tipPic"; }
            if (cart.Tipping && t - mPhaseStart < 12f) { mTipEnd = t; return; }
            if (t - mTipEnd < 3.5f) return;                                    // the last of the stream is still falling in
            long paid = money.Coins - mCoins0;
            mLog += " paid=" + paid + " paidShare=" + (paid / System.Math.Max(1e-6, mExpected) * 100).ToString("F0") + "% leftInCart=" + w.CartVoxels;
            MCheck("paysLikeHandCart", System.Math.Abs(paid - mExpected) < 1.01 && paid > 0);
            up.SetLevel(Upgrades.Branch.Cart, Upgrades.MotorCartLevel + 2);
            mLog += " motor3Speed=" + cart.spec.motorSpeed;
            mAlong0 = cart.Along; mTopSpeed = 0f;
            wk.overrideWalk = -1f;                                              // S: back into the mine
            mPhase = 4; mPhaseStart = t;
            return;
        }
        if (mPhase == 4)
        {
            mTopSpeed = Mathf.Max(mTopSpeed, -cart.MotorSpeedNow);
            bool stopped = t - mPhaseStart > 1f && Mathf.Abs(cart.MotorSpeedNow) < 1e-3f;
            if (!stopped && t - mPhaseStart < 60f) return;
            wk.overrideWalk = 0f;
            mLog += " backIn=" + (mAlong0 - cart.Along).ToString("F1") + "m in " + (t - mPhaseStart).ToString("F1") + "s topSpeed=" + mTopSpeed.ToString("F2") + " along=" + cart.Along.ToString("F1") + " start=" + cart.StartLimit.ToString("F1");
            MCheck("droveBackIn", mAlong0 - cart.Along > 5f);
            MCheck("stoppedAtRubbleOrEnd", cart.Along <= cart.StartLimit + 0.05f || cart.RoomAhead(-1f) < 1.5f);
            TestCapture("motor_cart_back_in.png");
            wk.PressE();                                                        // E away from the dump: get off
            MCheck("getsOff", !wk.RidingCart && !cart.BlocksWalker(wk.transform.position));
            up.SetLevel(Upgrades.Branch.Cart, 2);
            MCheck("sellBackRemovesMotor", !cart.spec.motor);
            Debug.Log((mOk ? "BULLDOZER_MOTORCART_RESULT" : "BULLDOZER_MOTORCART_FAILED") + mLog);
            MotorCartFinish(mOk ? 0 : 1);
        }
    }

    // Save and load:  -executeMethod BulldozerBuilder.SaveTest
    // Digs, saves, digs more and changes things, loads, and checks everything came back exactly as saved.
    // Prints BULLDOZER_SAVE_RESULT.
    static int sPhase;
    static float sPhaseStart, sAlongSaved;
    static long sVolume0, sSolidSaved, sLooseSaved;
    static ulong sTopSaved;
    static int sClodsSaved, sTouchedSaved;
    static Vector3 sDozerSaved;
    static string sLog;

    public static void SaveTest()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        sPhase = 0; sLog = "";
        testStart = EditorApplication.timeSinceStartup;
        EditorApplication.update += SaveTick;
        EditorApplication.EnterPlaymode();
    }

    static void SaveFinish(int code)
    {
        EditorApplication.update -= SaveTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static void SaveTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_SAVE_FAILED timed out in phase " + sPhase + " " + sLog); SaveFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var wk = Worker.Instance; var cart = MineCart.Instance; var finds = Finds.Instance; var sg = SaveGame.Instance;
        var d = UnityEngine.Object.FindFirstObjectByType<DozerController>();
        if (w == null || wk == null || cart == null || finds == null || sg == null || d == null || cart.Length <= 0f) return;
        float t = Time.time;
        if (sPhase == 0)
        {
            wk.useOverride = true;
            if (!wk.InDozer) wk.GetIn();
            sVolume0 = w.CountSolid() + w.LooseTotal();
            d.useOverride = true; d.overrideBlade = -1f; d.overrideThrottle = 1f;      // dig a pass
            sPhase = 1; sPhaseStart = t;
            return;
        }
        if (sPhase == 1)
        {
            if (t - sPhaseStart < 5f) return;
            d.overrideThrottle = 0f;                                               // stop, with loose dirt still moving
            cart.SetAlong(cart.Along - 2f);
            finds.Collect(1);
            string msg = sg.Save();
            sSolidSaved = w.CountSolid(); sLooseSaved = w.LooseTotal(); sTopSaved = w.TopHash();
            sClodsSaved = w.ClodCount; sTouchedSaved = w.TouchedChunks();
            sDozerSaved = d.transform.position; sAlongSaved = cart.Along;
            sLog += "save=[" + msg + "] bytes=" + sg.LastBytes + " saveMs=" + sg.LastMs.ToString("F0") + " touchedChunks=" + sTouchedSaved + " clodsAtSave=" + sClodsSaved;
            // now change everything: dig on, turn, move the cart, fit a part
            d.overrideThrottle = 1f; d.overrideSteer = 0.6f; d.overrideAngle = 1f;
            cart.SetAlong(cart.Along + 6f);
            finds.Install(2);
            sPhase = 2; sPhaseStart = t;
            return;
        }
        if (sPhase == 2)
        {
            if (t - sPhaseStart < 4f) return;
            d.overrideThrottle = 0f; d.overrideSteer = 0f; d.overrideAngle = 0f;
            sLog += " changedBeforeLoad=" + (w.TopHash() != sTopSaved);
            string msg = sg.Load();
            sLog += " load=[" + msg + "] loadMs=" + sg.LastMs.ToString("F0")
                  + " solidSame=" + (w.CountSolid() == sSolidSaved) + " looseSame=" + (w.LooseTotal() == sLooseSaved)
                  + " groundSame=" + (w.TopHash() == sTopSaved) + " clodsSame=" + (w.ClodCount == sClodsSaved)
                  + " touchedSame=" + (w.TouchedChunks() == sTouchedSaved)
                  + " dozerBack=" + (Vector3.Distance(d.transform.position, sDozerSaved) < 0.01f)
                  + " cartBack=" + (Mathf.Abs(cart.Along - sAlongSaved) < 0.001f)
                  + " findsBack=" + (finds.Collected[1] && !finds.Installed[1] && !finds.Collected[2] && !finds.Installed[2])
                  + " stillInDozer=" + wk.InDozer;
            sPhase = 3; sPhaseStart = t;
            return;
        }
        if (sPhase == 3)
        {
            if (t - sPhaseStart < 5f) return;                                    // play on a little after the load
            sLog += " volumeChangeOverall=" + ((w.CountSolid() + w.LooseTotal()) - sVolume0);
            Debug.Log("BULLDOZER_SAVE_RESULT " + sLog);
            SaveFinish(0);
        }
    }

    /// Puts the worker just off one end of the cart, facing along the track, walking into it.
    static void StandAtEnd(Worker wk, MineCart cart, bool front)
    {
        Vector3 f = cart.transform.forward; f.y = 0f; f.Normalize();
        Vector3 at = cart.transform.position + f * (front ? 1.45f : -1.45f);
        wk.Teleport(at, Facing(front ? -f : f));
        cGrabbed = wk.GrabCart();
        wk.overrideWalk = 1f;
    }

    static void CartTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 300) { Debug.LogError("BULLDOZER_CART_FAILED timed out in phase " + cPhase + " gameTime=" + Time.time + " frames=" + Time.frameCount + " clods=" + (VoxelWorld.Instance != null ? VoxelWorld.Instance.ClodCount : -1) + " " + cLog); CartFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var w = VoxelWorld.Instance; var wk = Worker.Instance; var cart = MineCart.Instance;
        if (w == null || wk == null || cart == null || cart.Length <= 0f) return;
        float t = Time.time;
        if (cPhase == 0)
        {
            // first a picture of the mine entrance from beside the cart, as the owner sees it on foot
            if (wk.InDozer) wk.GetOut();
            wk.useOverride = true;
            Vector3 inward = -cart.transform.forward; inward.y = 0f; inward.Normalize();
            wk.Teleport(cart.transform.position + cart.transform.right * 1.3f - inward * 1.2f, Facing(inward));
            wk.Look(8f);
            cPhase = 20; cPhaseStart = t;
            return;
        }
        if (cPhase == 20)
        {
            if (t - cPhaseStart < 1.5f) return;
            TestCapture("entrance.png");
            wk.transform.Find("Model").gameObject.SetActive(false);
            wk.transform.Find("Hold").gameObject.SetActive(false);
            TestCapture("entrance_nobody.png");
            wk.transform.Find("Model").gameObject.SetActive(true);
            wk.transform.Find("Hold").gameObject.SetActive(true);
            cPhase = 21;
            return;
        }
        if (cPhase == 21)
        {
            cVolume0 = w.CountSolid() + w.LoadVoxels;
            cAlong0 = cart.Along;
            cLog += "spec=" + cart.spec.name + "/" + cart.capacity + " startAlong=" + cAlong0.ToString("F1") + "m";
            StandAtEnd(wk, cart, true);                         // the front end faces out of the mine: push it back in
            cLastAlong = cart.Along; cStillFor = 0f;
            cPhase = 1; cPhaseStart = t;
            return;
        }
        if (cPhase == 1)
        {
            // pushed into the mine: it should roll in, then stop at the cave-in and stay stopped
            float dt = Time.deltaTime;
            if (Mathf.Abs(cart.Along - cLastAlong) < 0.001f) cStillFor += dt; else cStillFor = 0f;
            cLastAlong = cart.Along;
            if (t - cPhaseStart < 9f) return;
            Vector3 front = cart.transform.position - cart.transform.forward * 1.05f + Vector3.up * 0.55f;
            cLog += " grabbed=" + cGrabbed + " leaning=" + (wk.HoldingCart != 0) + " pushedIn=" + (cAlong0 - cart.Along).ToString("F2") + "m stoppedFor=" + cStillFor.ToString("F1") + "s"
                  + " stopsAtRubble=" + cart.Blocked(cart.Along - 0.03f, -1f)
                  + " cartZ=" + cart.transform.position.z.ToString("F1") + " caveInStartsZ=" + (VoxelWorld.PortalZ + 2.6f).ToString("F1")
                  + " gapToFace=" + cart.RoomAhead(-1f).ToString("F2") + "m";
            TestCapture("cart_push.png");
            wk.overrideWalk = 0f;
            wk.LetGo();
            // stand beside the cart at the face and dig it with real shovel swings: each load should go in the cart
            Vector3 inward = -cart.transform.forward;
            wk.Teleport(cart.transform.position + cart.transform.right * 1.0f + inward * 0.7f, Facing(inward));
            wk.Look(28f);
            wk.SetTool(1);
            cThrows0 = wk.Throws; cScoops0 = wk.Scoops; cCart0 = w.CartVoxels;
            wk.overrideUse = true;
            cPhase = 10; cPhaseStart = t;
            return;
        }
        if (cPhase == 10)
        {
            // swap to the pick now and then, to loosen the face
            float k = t - cPhaseStart;
            int want = (k % 4f) < 0.9f ? 0 : 1;
            if (wk.Tool != want) wk.SetTool(want);
            if (k < 14f) return;
            wk.overrideUse = false;
            cLog += " faceScoops=" + (wk.Scoops - cScoops0) + " faceThrows=" + (wk.Throws - cThrows0)
                  + " intoCart=" + ((w.CartVoxels - cCart0) * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + "L"
                  + " workerAt=" + (wk.transform.position - cart.transform.position).magnitude.ToString("F2") + "m";
            // step back out of the face, beside the cart and a little behind it, to picture the load in it
            wk.SetTool(1);
            wk.Teleport(cart.transform.position + cart.transform.right * 1.0f + cart.transform.forward * 2.2f, Facing(-cart.transform.forward) - 15f);
            wk.Look(35f);
            cPhase = 11; cPhaseStart = t;
            return;
        }
        if (cPhase == 11)
        {
            if (t - cPhaseStart < 2f) return;
            TestCapture("cart_load.png");
            // now the far end of the line
            cart.SetAlong(cart.EndLimit - 3f);
            StandAtEnd(wk, cart, false);
            cPhase = 2; cPhaseStart = t;
            return;
        }
        if (cPhase == 2)
        {
            if (t - cPhaseStart < 6f) return;
            cLog += " grabbed2=" + cGrabbed + " atEndOfLine=" + (Mathf.Abs(cart.Along - cart.EndLimit) < 0.02f) + " neverPast=" + (cart.Along <= cart.EndLimit + 0.001f);
            wk.overrideWalk = 0f;
            wk.LetGo();
            // walking into it without holding it: it must not move
            cNoGrabFrom = cart.Along;
            StandAtEnd(wk, cart, true); wk.LetGo(); wk.overrideWalk = 1f;
            cPhase = 12; cPhaseStart = t;
            return;
        }
        if (cPhase == 12)
        {
            if (t - cPhaseStart < 2f) return;
            cLog += " walkIntoItMoved=" + Mathf.Abs(cart.Along - cNoGrabFrom).ToString("F2") + "m";
            wk.overrideWalk = 0f;
            // back by the mine entrance, then fill it
            cart.SetAlong(cAlong0);
            wk.Teleport(cart.transform.position + cart.transform.right * 3.2f, Facing(-cart.transform.right));
            cFillSteps = 0; cNext = t;
            cPhase = 3; cPhaseStart = t;
            return;
        }
        if (cPhase == 3)
        {
            // dig the ground beside it and drop each load into the tub
            if (w.CartVoxels >= 2400 || t - cPhaseStart > 15f) { cLog += " filled=" + (w.CartVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + "L"; cPhase = 4; cPhaseStart = t; return; }
            if (t < cNext) return;
            cNext = t + 0.08f;
            Vector3 side = cart.transform.right;
            Vector3 at = cart.transform.position + side * 2.4f + cart.transform.forward * (-1f + (cFillSteps % 9) * 0.25f) + Vector3.up * (0.1f - (cFillSteps / 9) * 0.12f);
            cFillSteps++;
            w.Pick(at, 0.35f, Vector3.zero);
            w.Scoop(at, 0.5f, 4000);
            if (w.ShovelVoxels >= VoxelWorld.ClodVoxels) w.Throw(cart.Mouth + Vector3.up * 0.7f, Vector3.zero, 0.25f, 0.4f);
            return;
        }
        if (cPhase == 4)
        {
            if (t - cPhaseStart < 2f) return;                                  // let the last of it land
            if (cPhase == 4 && cNext >= 0f)
            {
                // a close look down into the full cart, in daylight
                wk.Teleport(cart.transform.position + cart.transform.right * 1.6f - cart.transform.forward * 1.6f, Facing(cart.transform.position - wk.transform.position));
                wk.Look(38f);
                cNext = -1f; cPhaseStart = t - 1f;
                return;
            }
            TestCapture("cart_full.png");
            cLog += " loadShown=" + (cart.transform.Find("Load") != null && cart.transform.Find("Load").gameObject.activeSelf)
                  + " loadTop=" + (cart.transform.Find("Load").localPosition.y + cart.transform.Find("Load").localScale.y * 0.5f).ToString("F2") + "m";
            cLog += " beforeTip=" + (w.CartVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + "L";
            cart.Tip();
            cPhase = 5; cPhaseStart = t;
            return;
        }
        if (cPhase == 5)
        {
            if (cart.Tipping && t - cPhaseStart < 15f) return;
            cLog += " tipTook=" + (t - cPhaseStart).ToString("F1") + "s leftInCart=" + w.CartVoxels + "voxels";
            cPhase = 6; cPhaseStart = t;
            return;
        }
        if (cPhase == 6)
        {
            if (t - cPhaseStart < 7f) return;                                  // let it all settle into ground
            cLog += " clodsStillLoose=" + w.ClodCount + " volumeChange=" + ((w.CountSolid() + w.LoadVoxels) - cVolume0);
            Debug.Log("BULLDOZER_CART_RESULT " + cLog);
            CartFinish(0);
        }
    }

    static void TestFinish(int code)
    {
        EditorApplication.update -= TestTick;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    // Records a short clip of the dozer digging:  -executeMethod BulldozerBuilder.RecordClip
    // Frames go to the project's Logs/clip folder at 30 a second; ffmpeg turns them into a video.
    static int clipFrame, clipLastGameFrame;
    static long clipSolid0;
    static float clipStart;
    static RenderTexture clipRT;
    static Texture2D clipTex;

    static int clipMode;                                    // 0 = blade digging, 1 = ripping the rock

    // The same, but on the rock outcrop with the ripper down:  -executeMethod BulldozerBuilder.RecordRipClip
    public static void RecordRipClip() { clipMode = 1; StartClip(); }

    // On foot at the mine: walk in, pick at the cave-in, shovel it out:  -executeMethod BulldozerBuilder.RecordWalkClip
    public static void RecordWalkClip() { clipMode = 2; StartClip(); }

    public static void RecordClip() { clipMode = 0; StartClip(); }

    // A trailer of the game so far: -executeMethod BulldozerBuilder.RecordTrailer   Frames and overlay.ass go to Logs/clip.
    // The bushfire, sped up:  -executeMethod BulldozerBuilder.RecordFireClip
    public static void RecordFireClip() { clipMode = 7; sPh = 0; sOverlay.Clear(); trCaps.Clear(); trCap = ""; StartClip(); }
    static bool clipSkip, prBreakHeld;                                   // a frame not to record (the fire warming up)

    // The prologue (rough cut), filmed:  -executeMethod BulldozerBuilder.RecordPrologue
    public static void RecordPrologue() { clipMode = 8; sPh = 0; sOverlay.Clear(); trCaps.Clear(); trCap = ""; StartClip(); }

    static string AssColour(Color c) { return "&H" + ((int)(c.b * 255)).ToString("X2") + ((int)(c.g * 255)).ToString("X2") + ((int)(c.r * 255)).ToString("X2") + "&"; }

    /// The prologue's captions and its red and black, over this frame.
    static void PrologueOverlay(Prologue pr)
    {
        float a = clipFrame / 30f, b = (clipFrame + 1) / 30f;
        string at = AssTime(a) + "," + AssTime(b);
        if (pr.Tint.a > 0.004f)
            sOverlay.Add("Dialogue: 0," + at + ",Shade,,0,0,0,,{\\1c" + AssColour(pr.Tint) + "\\1a&H" + ((int)((1f - pr.Tint.a) * 255)).ToString("X2") + "&\\p1}m 0 0 l 1280 0 1280 720 0 720{\\p0}");
        if (pr.Caption.Length == 0) return;
        string style = pr.CaptionStyle == "Place" ? "Place" : pr.CaptionStyle == "Shout" ? "Shout" : pr.CaptionStyle == "Card" ? "Card" : pr.CaptionStyle == "Small" ? "Caption" : "Big";
        string text = AssEsc(pr.Caption);
        if (pr.CaptionStyle == "Place" && pr.Caption2.Length > 0) text = AssEsc(pr.Caption).ToUpper() + "\\N{\\fs22\\b0}" + AssEsc(pr.Caption2);
        if (pr.CaptionStyle == "Shout" && pr.Caption2.Length > 0) text = "{\\fs22\\i1\\b0}" + AssEsc(pr.Caption2) + "{\\fs52\\i0\\b1}\\N" + text;
        sOverlay.Add("Dialogue: 1," + at + "," + style + ",,0,0,0,," + text);
    }

    public static void RecordTrailer() { clipMode = 6; sPh = 0; sOverlay.Clear(); trCaps.Clear(); trCap = ""; StartClip(); }
    static readonly List<string> trCaps = new List<string>();
    static string trCap = "", trCapStyle = "";
    static float trCapStart;
    static Vector3 trCamFrom, trCamTo, trLookFrom, trLookTo;
    static bool trCustom;
    static float trCamT0, trCamLen;

    // A short clip of the upgrade tree at work: Shovel 1 digging, buying Shovel 2-6, Shovel 6 digging, buying the
    // backpack and sucking.  -executeMethod BulldozerBuilder.RecordUpgradeClip
    public static void RecordUpgradeClip() { clipMode = 5; sPh = 0; sOverlay.Clear(); StartClip(); }
    static int uScoopMax, uScoopsSeen, uLastScoops;
    static string uPanel = "";

    // A showcase: pushing a big heap (with the real frame time on screen), then the backpack, the hopper and the
    // gold buyer.  -executeMethod BulldozerBuilder.RecordShowcase   Frames and overlay.ass go to Logs/clip.
    public static void RecordShowcase() { clipMode = 4; sPh = 0; sOverlay.Clear(); sCaptureMs = 0f; sWorst = 0f; sSum = 0f; sN = 0; StartClip(); }
    static int sPh, sStep, sN, sCoins0;
    static float sT0, sNext, sCaptureMs, sWorst, sSum, sRealSmooth;
    static double sDirt0;
    static Vector3 sStand, sPatch, sSide;
    static string sCaption = "", sPop = "", sTitle = "";
    static float sPopUntil;
    static readonly List<string> sOverlay = new List<string>();
    static readonly double[] sLoadL = new double[16];

    // What the overnight work added: dig a part out, the dead dozer and a repair, the cart, save and load.
    //   -executeMethod BulldozerBuilder.RecordNightClip      Prints BULLDOZER_NIGHT_OK with the frame each part starts at.
    public static void RecordNightClip() { clipMode = 3; nPhase = 0; nGlint = nVisible = nCheck = 0; nMarks = ""; StartClip(); }
    static int nPhase, nStep, nGlint, nVisible, nCheck;
    static float nT0, nNext;
    static string nMarks;
    static void NightMark(string name) { nMarks += " " + name + "=" + clipFrame; }

    // The motor cart, filmed: a full cart at the mine mouth, buying the Motor cart, riding it out to the dump,
    // tipping it from the footboard, Motor cart 2 and 3, and driving back in to the rubble.
    //   -executeMethod BulldozerBuilder.RecordMotorCartClip     Frames and overlay.ass go to Logs/clip.
    public static void RecordMotorCartClip() { clipMode = 9; sPh = 0; sOverlay.Clear(); uPanel = ""; sTitle = ""; sCaption = ""; sPop = ""; mcSnap = true; StartClip(); }
    static Vector3 mcOff, mcLookOff;                      // the camera, relative to the cart (eased from shot to shot)
    static bool mcSnap;
    static long mcCoins0;
    static float mcAlong0;

    /// Puts the camera at `off` from the cart (in the cart's own axes), looking at `lookOff`, easing towards it.
    static void McShot(Camera cam, MineCart cart, Vector3 off, Vector3 lookOff, float ease)
    {
        if (mcSnap) { mcOff = off; mcLookOff = lookOff; mcSnap = false; }
        mcOff = Vector3.Lerp(mcOff, off, ease); mcLookOff = Vector3.Lerp(mcLookOff, lookOff, ease);
        Vector3 pos = cart.transform.TransformPoint(mcOff), look = cart.transform.TransformPoint(mcLookOff);
        float floor = VoxelWorld.Instance.FloorAt(pos + Vector3.up * 0.5f) + 0.5f;
        if (pos.y < floor) pos.y = floor;
        cam.transform.SetPositionAndRotation(pos, Quaternion.LookRotation(look - pos, Vector3.up));
    }

    /// One step of the motor cart clip.  Returns false when it has finished.
    static bool MotorClipStep(DozerController d, float t, FollowCamera follow, Camera cam)
    {
        var wk = Worker.Instance; var w = VoxelWorld.Instance; var cart = MineCart.Instance; var money = Money.Instance; var up = Upgrades.Instance;
        if (cart == null || money == null || up == null || cart.Length <= 0f) { clipSkip = true; return true; }
        if (sPh == 0)
        {
            // set up, unrecorded: Cart 2, an empty pot, and the cart filled by the mine mouth
            clipSkip = true;
            d.overrideThrottle = 0f;
            if (wk.InDozer) wk.GetOut();
            if (follow != null) follow.enabled = false;
            up.Reset(); money.Clear();
            up.SetLevel(Upgrades.Branch.Cart, 2);
            wk.Teleport(cart.transform.position - cart.transform.forward * 2.2f, Facing(cart.transform.forward));
            dSteps = 0; dNext = t; sStep = 0;
            sPh = 1; sT0 = t;
            return true;
        }
        float k = t - sT0;
        if (sPh == 1)
        {
            clipSkip = true;
            if (!FillCart(w, cart, t, 5200) && k < 30f) return true;
            if (k < 32f && w.ClodCount > 0) return true;                        // let the last of it land
            Vector3 at, f;
            cart.HoldPlace(-1, out at, out f);
            wk.Teleport(at, Facing(f));
            wk.Look(12f);
            clipSkip = false;
            sTitle = "The motor cart"; sCaption = "A full cart at the mine mouth.  Pushing it out by hand is slow work...";
            sPh = 2; sT0 = t;
            return true;
        }
        if (sPh == 2)
        {
            McShot(cam, cart, new Vector3(3.0f - k * 0.2f, 3.0f, 4.8f), new Vector3(0f, 0.8f, 0f), 0.05f);     // outside, from the front, looking back at the mouth
            if (k < 4f) return true;
            money.TestGrant(1000, Mathf.CeilToInt(12f / (VoxelWorld.VoxelVolume * 1000f)));
            sTitle = "The upgrades (U)"; sCaption = "Motor cart:  800 coins + 10 L of gold  (test coins)";
            uPanel = up.Describe(Upgrades.Branch.Cart);
            sPh = 3; sT0 = t;
            return true;
        }
        if (sPh == 3)
        {
            McShot(cam, cart, new Vector3(2.4f, 1.6f, 3.6f), new Vector3(0f, 0.6f, 0.6f), 0.04f);   // round to the front, where the motor goes
            if (k > 1.6f && !up.HasMotorCart) { up.Buy(Upgrades.Branch.Cart); uPanel = up.Describe(Upgrades.Branch.Cart); }
            if (k > 3.2f && uPanel.Length > 0) { uPanel = ""; sTitle = "Motor cart"; sCaption = "A motor box on the front, a footboard on the back"; }
            if (k < 6f) return true;
            wk.RideCart();
            sTitle = ""; sCaption = "R at an end:  he gets on";
            sPh = 4; sT0 = t;
            return true;
        }
        if (sPh == 4)
        {
            McShot(cam, cart, new Vector3(1.0f, 2.3f, -4.6f), new Vector3(0f, 1.2f, 3f), 0.05f);      // behind him
            if (k < 2f) return true;
            wk.overrideWalk = 1f;
            mcAlong0 = cart.Along;
            sCaption = "W drives it out to the dump, 8 m out of the mine door  (3 m/s)";
            sPh = 5; sT0 = t;
            return true;
        }
        if (sPh == 5)
        {
            // behind him, then out to the side for a while, then behind again for the run in to the hopper
            bool side = k > 5f && k < 11f;
            McShot(cam, cart, side ? new Vector3(4.6f, 2.6f, 1.2f) : new Vector3(1.0f, 2.3f, -4.6f), side ? new Vector3(0f, 0.9f, 0.5f) : new Vector3(0f, 1.2f, 3f), 0.035f);
            bool stopped = k > 1f && Mathf.Abs(cart.MotorSpeedNow) < 1e-3f;
            if (!stopped && k < 40f) return true;
            wk.overrideWalk = 0f;
            sCaption = "At the dump:  E tips it into the hopper, and he stays on";
            sPh = 6; sT0 = t;
            return true;
        }
        if (sPh == 6)
        {
            McShot(cam, cart, new Vector3(-4.5f, 3.6f, 7.5f), new Vector3(-0.4f, 0.8f, -5f), 0.04f);  // past the hopper, looking back at it and the mine door
            if (k < 1.2f) return true;
            if (sStep != -6) { sStep = -6; mcCoins0 = money.Coins; wk.PressE(); }
            if (cart.Tipping) { sNext = t; return true; }
            if (t - sNext < 3f) return true;
            sPop = "+" + (money.Coins - mcCoins0) + " coins"; sPopUntil = Time.time + 3.5f;
            sPh = 7; sT0 = t; sStep = 0;
            return true;
        }
        if (sPh == 7)
        {
            McShot(cam, cart, new Vector3(-4.6f, 2.6f, -2.6f), new Vector3(-1.2f, 0.5f, 0f), 0.04f);
            if (k < 2f) return true;
            if (uPanel.Length == 0) { money.TestGrant(1500, 0); sTitle = "The upgrades (U)"; sCaption = "Motor cart 2 and 3:  4 m/s, then 5 m/s"; uPanel = up.Describe(Upgrades.Branch.Cart); }
            if (k > 2.8f && sStep == 0) { up.Buy(Upgrades.Branch.Cart); sStep = 1; uPanel = up.Describe(Upgrades.Branch.Cart); }
            if (k > 3.6f && sStep == 1) { up.Buy(Upgrades.Branch.Cart); sStep = 2; uPanel = up.Describe(Upgrades.Branch.Cart); }
            if (k < 5.5f) return true;
            uPanel = ""; sTitle = "";
            sCaption = "S drives it back into the mine, at 5 m/s.  It stops at the rubble.";
            wk.overrideWalk = -1f;
            sPh = 8; sT0 = t;
            return true;
        }
        if (sPh == 8)
        {
            // ahead of the cart, looking back over it and him into the mine
            McShot(cam, cart, new Vector3(0.6f, 2.2f, 4.2f), new Vector3(0f, 1.0f, -4f), 0.05f);
            bool stopped = k > 1f && Mathf.Abs(cart.MotorSpeedNow) < 1e-3f;
            if (!stopped && k < 40f) return true;
            wk.overrideWalk = 0f;
            sPh = 9; sT0 = t;
            return true;
        }
        if (sPh == 9)
        {
            McShot(cam, cart, new Vector3(0.6f, 1.75f, 4.2f), new Vector3(0f, 1.0f, -4f), 0.05f);
            if (k > 1.5f && wk.RidingCart) { wk.GetOffCart(); sCaption = "R gets off.  Shovel it full again!"; }
            if (k < 4.5f) return true;
            return false;
        }
        return true;
    }

    static void MotorOverlay()
    {
        var w = VoxelWorld.Instance; var money = Money.Instance; var cart = MineCart.Instance;
        float a = clipFrame / 30f, b = (clipFrame + 1) / 30f;
        string at = AssTime(a) + "," + AssTime(b);
        if (cart != null)
            sOverlay.Add("Dialogue: 0," + at + ",Perf,,0,0,0,,Cart " + (w.CartVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + " of " + (cart.capacity * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + " L"
                       + (cart.spec.motor ? "\\NSpeed " + Mathf.Abs(cart.MotorSpeedNow).ToString("F1") + " m/s" : ""));
        sOverlay.Add("Dialogue: 0," + at + ",Hud,,0,0,0,,Coins " + money.Coins.ToString("N0") + "\\NGold " + money.GoldLitres.ToString("F0") + " L");
        if (sTitle.Length > 0) sOverlay.Add("Dialogue: 0," + at + ",Title,,0,0,0,," + AssEsc(sTitle));
        if (sCaption.Length > 0) sOverlay.Add("Dialogue: 0," + at + ",Caption,,0,0,0,," + AssEsc(sCaption));
        if (uPanel.Length > 0) sOverlay.Add("Dialogue: 0," + at + ",Panel,,0,0,0,," + AssEsc(uPanel.TrimEnd('\n').Replace("\n", "\\N")));
        if (sPop.Length > 0 && Time.time < sPopUntil) sOverlay.Add("Dialogue: 0," + at + ",Pop,,0,0,0,," + AssEsc(sPop));
    }

    // The mountain road: a high shot of the mountain, the dozer driving from the quarry up the escape track and along the
    // firebreak onto the road, the pegs and the tint with the key, and then a stretch worked to grade with the cab
    // readout, ending with its green tick.  The blade there follows the cab's arrows by itself (what a driver would do).
    //   -executeMethod BulldozerBuilder.RecordRoadClip     Frames and overlay.ass go to Logs/clip.
    public static void RecordRoadClip() { rcCutOnly = false; clipMode = 10; sPh = 0; sOverlay.Clear(); sTitle = ""; sCaption = ""; sPop = ""; rcLog = ""; rcWays.Clear(); StartClip(); }
    // 30 s of the dozer cutting stretch 13 at normal speed, close up: a side view, a peg close-up, then from behind.
    //   -executeMethod BulldozerBuilder.RecordRoadCutClip     Frames and overlay.ass go to Logs/clip.
    // The same run, filmed from in front of the dozer looking back at the blade:  -executeMethod BulldozerBuilder.RecordRoadCutFrontClip
    public static void RecordRoadCutFrontClip() { rcFrontView = true; rcSwing = false; RecordRoadCutClipStart(); }
    public static void RecordRoadCutClip() { rcFrontView = false; rcSwing = false; RecordRoadCutClipStart(); }
    // One continuous run up stretch 7 and on: from in front, then swinging round the downhill side to behind.
    //   -executeMethod BulldozerBuilder.RecordRoadCutSwingClip
    public static void RecordRoadCutSwingClip() { rcFrontView = true; rcSwing = true; RecordRoadCutClipStart(); }
    static bool rcSwing;
    const float SwingFrom = 9f, SwingTo = 16f;
    static bool rcFrontView;
    static void RecordRoadCutClipStart() { rcCutOnly = true; clipMode = 10; sPh = 0; sOverlay.Clear(); sTitle = ""; sCaption = ""; sPop = ""; rcLog = ""; rcWays.Clear(); StartClip(); }
    static bool rcCutOnly;
    const int RcCutStretch = 12;                            // stretch 13: all cut (up to about 0.9 m once eased)
    const int RcSecondStretch = 6;                          // then stretch 7: all cut too
    const float RcSecondAt = 14f;                           // when the clip cuts to it (stretch 13's cut is done by then)
    static Vector3 rcLastPos;
    static float rcTickAt = -1f, rcTickAt7 = -1f;
    static int rcPeg = -1;
    const float RcCutLength = 30f;

    /// The cutting clip's camera: beside the blade, then a peg close-up, then from behind and above.
    static void RcCutCam(DozerController d, Camera cam, float k, float s, Vector2 roadDir)
    {
        Vector3 rd = new Vector3(roadDir.x, 0f, roadDir.y).normalized, rr = Vector3.Cross(Vector3.up, rd);
        var w = VoxelWorld.Instance; var job = MountainRoadJob.Instance;
        Vector3 bladeAt = d.Blade != null ? d.Blade.TransformPoint(new Vector3(0f, 0f, 1.1f)) : d.transform.position;
        Vector3 pos, look;
        float ease = 0.08f;
        if (rcFrontView && rcSwing)
        {
            // front, then round the downhill side, then behind: an angle round the machine, 0 = in front, 180 = behind
            Vector3 ahead = bladeAt - d.transform.position; ahead.y = 0f; ahead.Normalize();
            Vector3 outSide = new Vector3(bladeAt.x - Mountain.CX, 0f, bladeAt.z - Mountain.CZ).normalized;
            Vector3 side = Vector3.Dot(Vector3.Cross(Vector3.up, ahead), outSide) >= 0f ? Vector3.Cross(Vector3.up, ahead) : -Vector3.Cross(Vector3.up, ahead);
            float u = Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(SwingFrom, SwingTo, k));
            float ang = u * Mathf.PI;
            Vector3 centre = (d.transform.position + bladeAt) * 0.5f;
            float radius = Mathf.Lerp(7.5f, 9.5f, u);
            Vector3 dirOut = ahead * Mathf.Cos(ang) + side * Mathf.Sin(ang);
            pos = centre + dirOut * radius;
            float lift = Mathf.Sin(ang) * 1.2f;                                                // a little higher going round the side
            float gyS = Mathf.Max(w.HeightAt(pos.x, pos.z), w.HeightAt(Vector3.Lerp(pos, centre, 0.3f).x, Vector3.Lerp(pos, centre, 0.3f).z));
            pos.y = Mathf.Max(centre.y + Mathf.Lerp(1.6f, 3.4f, u) + lift, gyS + 1.6f);
            look = Vector3.Lerp(bladeAt + Vector3.up * 0.2f, centre + ahead * 3f, u);        // the blade at first, the road it leaves at the end
            if (k < 0.1f || rcPeg != -6) { rcPeg = -6; ease = 1f; } else ease = 0.15f;
            RcCam(cam, pos, look, ease);
            return;
        }
        if (rcFrontView)
        {
            // in front of the blade, low, looking back at it and the dirt rolling up in front of it; a little to the
            // downhill side, so the cut bank on the uphill side is not in the way
            Vector3 ahead = bladeAt - d.transform.position; ahead.y = 0f; ahead.Normalize();
            Vector3 outSide = new Vector3(bladeAt.x - Mountain.CX, 0f, bladeAt.z - Mountain.CZ).normalized;
            pos = bladeAt + ahead * 6.0f + outSide * 1.2f;
            float gy = Mathf.Max(w.HeightAt(pos.x, pos.z), w.HeightAt(pos.x - ahead.x * 2f, pos.z - ahead.z * 2f));
            pos.y = Mathf.Max(bladeAt.y + 1.4f, gy + 1.6f);                                   // about 2 m up, and always clear of the ground
            look = bladeAt + Vector3.up * 0.2f;
            if (k < 0.1f || rcPeg != -6) { rcPeg = -6; ease = 1f; } else ease = 0.15f;
            RcCam(cam, pos, look, ease);
            return;
        }
        if (k > 9f && k < 13.5f && job.PegCount > 0)
        {
            if (rcPeg < 0)
            {
                // the next peg up the road on the camera's side, a little ahead of the machine
                float best = float.MaxValue;
                for (int i = 0; i < job.PegCount; i++)
                {
                    float a = job.PegAlong(i) - s;
                    if (a < 3f || a > 14f) continue;
                    if (a < best) { best = a; rcPeg = i; }
                }
                if (rcPeg < 0) rcPeg = 0;
                ease = 1f;
            }
            Vector2 p = job.PegAt(rcPeg);
            float gy = w.HeightAt(p.x, p.y);
            Vector3 peg = new Vector3(p.x, gy + 1.0f, p.y);
            Vector3 away = new Vector3(p.x - Mountain.CX, 0f, p.y - Mountain.CZ).normalized;     // out from the mountain, over the road
            Vector3 toDozer = (d.transform.position - peg); toDozer.y = 0f; toDozer.Normalize();
            pos = peg - toDozer * 2.2f + away * 1.2f + Vector3.up * 0.5f;
            look = Vector3.Lerp(peg, d.transform.position + Vector3.up * 1.2f, 0.25f);
            if (ease < 1f) ease = 0.12f;
        }
        else if (k <= 9f || (k >= RcSecondAt && k < RcSecondAt + 7f))
        {
            if (k >= RcSecondAt && rcPeg != -4) { rcPeg = -4; ease = 1f; }
            Vector3 outSide = new Vector3(d.transform.position.x - Mountain.CX, 0f, d.transform.position.z - Mountain.CZ).normalized;
            pos = d.transform.position + rd * 0.8f + outSide * 8.8f + Vector3.up * 3.6f;      // beside the blade, on the downhill side, where the spoil goes
            look = bladeAt - Vector3.up * 0.4f;
            if (k < 0.1f) ease = 1f;
        }
        else if (true)
        {
            if (rcPeg >= 0 && k >= 13.5f) { rcPeg = -2; ease = 1f; }
            if (rcPeg == -4) { rcPeg = -5; ease = 1f; }
            pos = d.transform.position - rd * 6.8f + rr * 1.8f + Vector3.up * 3.4f;          // behind and above, looking up the road
            look = bladeAt + rd * 2f - Vector3.up * 0.3f;
        }
        else
        {
            if (rcPeg != -3) { rcPeg = -3; ease = 1f; }
            Vector3 outSide = new Vector3(d.transform.position.x - Mountain.CX, 0f, d.transform.position.z - Mountain.CZ).normalized;
            pos = d.transform.position + rd * 8.5f + outSide * 4.5f + Vector3.up * 3.2f;      // ahead, looking back down the road at it and the tick
            look = d.transform.position - rd * 3f + Vector3.up * 0.6f;
        }
        float floor = w.HeightAt(pos.x, pos.z) + 0.8f;
        if (pos.y < floor) pos.y = floor;
        RcCam(cam, pos, look, ease);
    }
    static int rcWay, rcStride = 1, rcPass, rcStuckFrames;
    static float rcS0, rcS1, rcLastProgress;
    static bool rcForward, rcShowKey, rcShowCab;
    static string rcLog = "";
    static Vector3 rcCamPos, rcCamLook;
    static readonly List<Vector2> rcWays = new List<Vector2>();
    const int RcStretch = 12;                               // the stretch worked in the clip (shown as stretch 13: all cut, no fill)

    static void RcCam(Camera cam, Vector3 pos, Vector3 look, float ease)
    {
        if (ease >= 1f) { rcCamPos = pos; rcCamLook = look; }
        rcCamPos = Vector3.Lerp(rcCamPos, pos, ease); rcCamLook = Vector3.Lerp(rcCamLook, look, ease);
        cam.transform.SetPositionAndRotation(rcCamPos, Quaternion.LookRotation(rcCamLook - rcCamPos, Vector3.up));
    }

    static Vector3 RcRoad(float s, float off, float up)
    {
        Vector2 dir;
        Vector2 p = RoadPoint(s, off, out dir);
        return new Vector3(p.x, VoxelWorld.Instance.HeightAt(p.x, p.y) + up, p.y);
    }

    /// Steers the dozer at a point on the ground; going backwards if `back`.  Returns how far it is from it.
    static float RcSteer(DozerController d, Vector2 aim, bool back, float throttle)
    {
        Vector3 pos = d.transform.position;
        Vector3 to = new Vector3(aim.x - pos.x, 0f, aim.y - pos.z);
        Vector3 fwd = Vector3.ProjectOnPlane(d.transform.forward, Vector3.up);
        float ang = Vector3.SignedAngle(back ? -fwd : fwd, to, Vector3.up);
        d.overrideSteer = Mathf.Clamp(ang / 25f, -1f, 1f);       // (the machine turns on the spot: reversing, turning the same way swings its back the same way)
        d.overrideThrottle = (Mathf.Abs(ang) > 55f ? 0.15f : 1f) * throttle * (back ? -1f : 1f);
        return to.magnitude;
    }

    /// A clear way for the dozer across the hilltop, from `from` to `to`: a search over a 1 m grid that keeps clear of
    /// anything solid (trees, fallen trunks) and of steps too tall to drive.  Returns points about 3 m apart.
    static List<Vector2> RcFindWay(Vector2 from, Vector2 to)
    {
        var w = VoxelWorld.Instance;
        const float x0 = -24f, z0 = 14f, cell = 1f;
        const int nx = 48, nz = 34;
        System.Func<int, int, bool> open = (i, j) =>
        {
            float x = x0 + i * cell, z = z0 + j * cell;
            bool inside = (Mathf.Abs(x) <= VoxelWorld.DriveLimit && Mathf.Abs(z) <= VoxelWorld.DriveLimit) || MountainRoad.DistanceTo(x, z) <= MountainRoad.CorridorHalf;
            return inside && !SiteProps.Blocks(new Vector3(x, w.HeightAt(x, z), z), 2.45f);
        };
        var prev = new int[nx * nz];
        for (int k = 0; k < prev.Length; k++) prev[k] = -2;
        int si = Mathf.Clamp(Mathf.RoundToInt((from.x - x0) / cell), 0, nx - 1), sj = Mathf.Clamp(Mathf.RoundToInt((from.y - z0) / cell), 0, nz - 1);
        int gi = Mathf.Clamp(Mathf.RoundToInt((to.x - x0) / cell), 0, nx - 1), gj = Mathf.Clamp(Mathf.RoundToInt((to.y - z0) / cell), 0, nz - 1);
        var q = new Queue<int>();
        q.Enqueue(si + nx * sj); prev[si + nx * sj] = -1;
        while (q.Count > 0)
        {
            int c = q.Dequeue(), ci = c % nx, cj = c / nx;
            if (ci == gi && cj == gj) break;
            float h = w.HeightAt(x0 + ci * cell, z0 + cj * cell);
            for (int dj = -1; dj <= 1; dj++)
                for (int di = -1; di <= 1; di++)
                {
                    int ni = ci + di, nj = cj + dj;
                    if ((di == 0 && dj == 0) || ni < 0 || nj < 0 || ni >= nx || nj >= nz || prev[ni + nx * nj] != -2) continue;
                    if (!open(ni, nj) || Mathf.Abs(w.HeightAt(x0 + ni * cell, z0 + nj * cell) - h) > 0.5f) continue;
                    prev[ni + nx * nj] = c; q.Enqueue(ni + nx * nj);
                }
        }
        var path = new List<Vector2>();
        if (prev[gi + nx * gj] == -2) { rcLog += " noClearWay!"; path.Add(to); return path; }
        for (int c = gi + nx * gj; c >= 0; c = prev[c]) path.Add(new Vector2(x0 + (c % nx) * cell, z0 + (c / nx) * cell));
        path.Reverse();
        var outPts = new List<Vector2>();
        for (int k = 0; k < path.Count; k += 2) outPts.Add(path[k]);
        outPts.Add(path[path.Count - 1]);
        rcLog += " clearWay=" + path.Count + "m via " + outPts[outPts.Count / 2].ToString("F1");
        return outPts;
    }

    static bool RoadClipStep(DozerController d, float t, FollowCamera follow, Camera cam)
    {
        var wk = Worker.Instance; var w = VoxelWorld.Instance; var job = MountainRoadJob.Instance;
        if (job == null) { clipSkip = true; return true; }
        float k = t - sT0;
        Vector2 dir;
        if (sPh == 0)
        {
            // set up: the dozer at the foot of the escape track, facing up it
            clipSkip = true;
            if (follow != null) follow.enabled = false;
            if (!wk.InDozer) wk.GetIn();
            d.dead = false;
            d.Place(new Vector3(VoxelWorld.TrackCentreX(1f), 0f, 1f), 0f);
            d.overrideBlade = 1f; d.overrideRipper = 1f; d.overrideThrottle = 0f;
            if (rcWays.Count == 0)
            {
                foreach (float z in new[] { 6f, 12f, 18f, 24f }) rcWays.Add(new Vector2(VoxelWorld.TrackCentreX(z), z));
                rcWays.AddRange(RcFindWay(new Vector2(VoxelWorld.TrackCentreX(27f), 27f), RoadPoint(3f, 0f, out dir)));
                for (float s = 3f; s <= 14f; s += 2f) rcWays.Add(RoadPoint(s, 0f, out dir));
            }
            rcWay = 0;
            if (rcCutOnly)
            {
                int first = rcSwing ? RcSecondStretch : RcCutStretch;
                rcS0 = first * MountainRoad.Length / MountainRoad.Stretches; rcS1 = (first + 1) * MountainRoad.Length / MountainRoad.Stretches;
                Vector2 st = RoadPoint(rcS0 - 3f, 0f, out dir);
                d.Place(new Vector3(st.x, 0f, st.y), Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg);   // (the set-up above puts it at the track every frame: move it here, every frame too)
                if (k < 2f) return true;
                clipSkip = false;
                rcPass = 0; rcForward = true; rcShowCab = true; rcShowKey = true; rcStride = 1; rcPeg = -1;
                sTitle = rcSwing ? "Cutting stretch 7" : "Cutting stretch 13"; sCaption = "Normal speed.  The blade follows the cab readout down to grade.";
                rcLastPos = d.transform.position; rcTickAt = -1f; rcTickAt7 = -1f;
                rcLog += " stretch13Before=" + (job.StretchShare(RcStretch) * 100f).ToString("F0") + "%";
                sPh = 4; sT0 = t;
                return true;
            }
            if (k < 1.5f) return true;
            string blocked = "";
            for (int i = 0; i + 1 < rcWays.Count; i++)
                for (float u = 0f; u < 1f; u += 0.1f)
                {
                    Vector2 q = Vector2.Lerp(rcWays[i], rcWays[i + 1], u);
                    if (SiteProps.Blocks(new Vector3(q.x, 0f, q.y), 2.3f)) blocked += " " + q.ToString("F1");
                }
            rcLog += " routeBlockedAt:" + (blocked.Length > 0 ? blocked : " none");
            clipSkip = false;
            sTitle = "The mountain road"; sCaption = "20 m up the mountain behind the mine, at 1 in 8, with two switchbacks";
            RcCam(cam, new Vector3(20f, 46f, 8f), new Vector3(-30f, 12f, 78f), 1f);
            sPh = 1; sT0 = t;
            return true;
        }
        if (sPh == 1)
        {
            // high over the quarry, drifting west to look along the mountain's face
            RcCam(cam, new Vector3(20f - k * 3.2f, 46f - k * 1.5f, 8f + k * 1.2f), new Vector3(-30f, 12f, 78f), 0.2f);
            if (k > 3.5f) sCaption = "The road is the bare strip.  The rest of the mountain can't be dug.";
            if (k < 7f) return true;
            sTitle = ""; sCaption = "From the quarry: up the escape track, across the hilltop, onto the road   (3x speed)";
            if (follow != null) { follow.enabled = true; follow.yawOffset = 20f; }
            rcStride = 3; rcStuckFrames = 0; rcLastProgress = t;
            sPh = 2; sT0 = t;
            return true;
        }
        if (sPh == 2)
        {
            // drive the way points
            if (Mathf.FloorToInt(k / 3f) != Mathf.FloorToInt((k - Time.deltaTime) / 3f))
                rcLog += "\n  drive k=" + k.ToString("F0") + " way=" + rcWay + " pos=" + d.transform.position.ToString("F1") + " yaw=" + d.transform.eulerAngles.y.ToString("F0")
                       + " speed=" + d.Speed.ToString("F1") + " cliff=" + d.AtCliff + " fence=" + d.AtFence + " blockedHere=" + SiteProps.Blocks(d.transform.position + d.transform.forward * 0.3f, 2.3f)
                       + " cut=" + d.LastCut + " steer=" + d.overrideSteer.ToString("F2");
            Vector2 aim = rcWays[Mathf.Min(rcWay, rcWays.Count - 1)];
            float dist = RcSteer(d, aim, false, 1f);
            if (dist < 1.8f) { rcWay++; rcLastProgress = t; }
            if (t - rcLastProgress > 8f)
            {
                rcLog += " stuckAtWay" + rcWay + "=" + d.transform.position.ToString("F1");
                rcWay++; rcLastProgress = t;                       // (should not happen: logged if it does)
            }
            if (rcWay < rcWays.Count && k < 60f) return true;
            rcLog += " droveOnToRoad=" + (rcWay >= rcWays.Count) + " in " + k.ToString("F0") + "s at " + d.transform.position.ToString("F1") + " strip=" + (w.KindAt(d.transform.position.x, d.transform.position.z) == VoxelWorld.BlockStrip);
            d.overrideThrottle = 0f; d.overrideSteer = 0f;
            rcStride = 1;
            if (follow != null) follow.enabled = false;
            rcShowKey = true;
            sCaption = "Survey pegs every 5 m:  CUT or FILL = metres to grade.  The road is tinted to match.";
            RcCam(cam, RcRoad(12f, -5.5f, 3.2f), RcRoad(24f, 0f, 0f), 1f);
            sPh = 3; sT0 = t;
            return true;
        }
        if (sPh == 3)
        {
            // along the first leg, beside the road, looking up it at the pegs and the tint
            float s = 12f + k * 3.2f;
            RcCam(cam, RcRoad(s, -5.5f, 3.2f), RcRoad(s + 12f, 0.5f, 0.3f), 0.08f);
            if (k > 5f) sCaption = "Red = too high, cut it down.   Blue = too low, fill it.   Green = on grade.";
            if (k < 10f) return true;
            // later, on stretch 14, near the top: the dozer at its start, blade down a little
            rcS0 = RcStretch * MountainRoad.Length / MountainRoad.Stretches; rcS1 = (RcStretch + 1) * MountainRoad.Length / MountainRoad.Stretches;
            Vector2 p = RoadPoint(rcS0 - 5f, 0f, out dir);
            d.Place(new Vector3(p.x, 0f, p.y), Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg);
            rcPass = 0; rcForward = true; rcShowCab = true;
            if (follow != null) { follow.enabled = true; follow.yawOffset = 35f; }
            sTitle = "Stretch 13 of 15"; sCaption = "Working it to grade.  The cab says how far the blade is from grade:  lower or raise it.";
            rcLog += " stretch13Before=" + (job.StretchShare(RcStretch) * 100f).ToString("F0") + "%";
            sPh = 4; sT0 = t;
            return true;
        }
        if (sPh == 4)
        {
            if (k > 4f) sTitle = "";
            if (rcCutOnly)
            {
                if (rcSwing)
                {
                    if ((k > 4f && k < SwingTo) || k > SwingTo + 4f) sTitle = "";
                    sCaption = rcLog.IndexOf("TICK 7") >= 0 && k < rcTickAt7 + 3f ? "Half of stretch 7 is within 25 cm:  its green tick."
                             : k < SwingFrom ? "Red: too high.  Green: within 25 cm of grade."
                             : k < SwingTo ? "Blade angled, so the spoil rolls off the downhill edge."
                             : rcTickAt >= 0f && k < rcTickAt + 3f ? "Half of stretch 13 is within 25 cm:  its green tick."
                             : "Behind it: the cut floor, on grade, turning green.";
                }
                else if (k >= RcSecondAt) { if (k > RcSecondAt + 4f) sTitle = ""; sCaption = k < RcSecondAt + 10f ? "Blade angled, so the spoil rolls off the downhill edge." : "Red turning green as the blade takes it down to grade."; }
                else if (rcTickAt >= 0f && k < rcTickAt + 3f) sCaption = "Half of stretch 13 is within 25 cm:  its green tick.";
                else if (k >= 9f && !rcFrontView) sCaption = "The peg beside the road: how much is left to cut there.";
                else if (k >= 9f) sCaption = "The blade on grade: the cut floor behind it turns green.";
                else if (k > 4f) sCaption = "Red: too high.  Green: within 25 cm of grade.";
            }
            if (!rcCutOnly && k > 2f && sCaption.StartsWith("Working")) sCaption = "Pass after pass, following the arrows, blade angled to cast the spoil off the edge   (6x speed)";
            // the blade follows the cab readout: lower it while the edge is above grade, raise it while below
            int arrow = job.CabArrow;
            var blade = d.Blade;
            float edgeOff = 0f;
            if (blade != null)
            {
                Vector3 edge = (blade.TransformPoint(new Vector3(-2.25f, -0.75f, 1.1f)) + blade.TransformPoint(new Vector3(2.25f, -0.75f, 1.1f))) * 0.5f;
                float es, eo; Vector2 ed;
                MountainRoad.Nearest(edge.x, edge.z, out es, out eo, out ed);
                edgeOff = edge.y - MountainRoad.GradeAt(es);
            }
            Vector3 pos = d.transform.position;
            float s, off;
            MountainRoad.Nearest(pos.x, pos.z, out s, out off, out dir);
            if (rcCutOnly)
            {
                // the cutting clip: one steady run up the road, cutting a thin layer at a time, the blade angled to
                // cast the spoil off the downhill edge.  If it stalls against its load it lifts the blade a moment.
                rcStride = 1;
                float jumpAt = rcSwing ? SwingTo : RcSecondAt;
                if (k >= jumpAt && k < jumpAt + 0.5f)
                {
                    // cut to the next stretch (not filmed while it is put there): stretch 7 in the first clip, 13 in the swing clip
                    clipSkip = true;
                    float s7 = (rcSwing ? RcCutStretch : RcSecondStretch) * MountainRoad.Length / MountainRoad.Stretches - 3f;
                    Vector2 st = RoadPoint(s7, 0f, out dir);
                    d.Place(new Vector3(st.x, 0f, st.y), Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg);
                    rcLastPos = d.transform.position;
                    sTitle = rcSwing ? "Stretch 13" : "Stretch 7"; sPop = ""; if (rcFrontView) rcPeg = -7;   // (the front camera jumps with it)
                    return true;
                }
                clipSkip = false;
                Vector3 outw = pos - new Vector3(Mountain.CX, pos.y, Mountain.CZ);
                float wy = Vector3.Dot(d.transform.right, outw) > 0f ? d.bladeMaxAngle : -d.bladeMaxAngle;
                d.overrideAngle = Mathf.Abs(d.BladeYaw - wy) < 1f ? 0f : Mathf.Sign(wy - d.BladeYaw);
                if (Mathf.Abs(d.Speed) > 0.25f || k < 2f) rcStuckFrames = 0; else rcStuckFrames++;
                if (rcStuckFrames == 45) rcLog += " lift@" + k.ToString("F0");
                bool lift = rcStuckFrames > 45;
                if (rcStuckFrames > 95) rcStuckFrames = 0;
                float thin = (pos.y - 0.25f) - (MountainRoad.GradeAt(s) + edgeOff);
                float aimC = Mathf.Min(edgeOff, -thin);
                d.overrideBlade = lift ? 1f : aimC > 0.03f ? -1f : aimC < -0.03f ? 1f : 0f;
                Vector2 roadDir = dir;
                RcSteer(d, RoadPoint(s + 4.5f, 0f, out dir), false, 0.45f);
                if ((!rcSwing || k > SwingTo + 0.5f) && rcTickAt < 0f && job.Ticked(RcCutStretch)) { rcTickAt = k; sPop = "Stretch 13:  green tick!"; sPopUntil = Time.time + 3f; rcLog += " | TICK 13 at k=" + k.ToString("F1"); }
                if ((rcSwing || k > RcSecondAt) && job.Ticked(RcSecondStretch) && rcLog.IndexOf("TICK 7") < 0) { sPop = "Stretch 7:  green tick!"; sPopUntil = Time.time + 3f; rcTickAt7 = k; rcLog += " | TICK 7 at k=" + k.ToString("F1"); }
                RcCutCam(d, cam, k, s, roadDir);
                // once a second: how far the machine went, and how much dirt is on the move (for checking the clip has no still part)
                if (Mathf.FloorToInt(k) != Mathf.FloorToInt(k - Time.deltaTime))
                {
                    rcLog += " | k=" + Mathf.FloorToInt(k) + " moved=" + Vector3.Distance(pos, rcLastPos).ToString("F2") + "m cut=" + d.LastCut + " clods=" + w.ClodCount
                           + " s=" + s.ToString("F1") + (d.AtCliff ? " CLIFF" : "") + (d.Climbing ? " climbing" : "");
                    rcLastPos = pos;
                }
                if (k < RcCutLength) return true;
                Debug.Log("BULLDOZER_ROADCUTCLIP_OK frames=" + clipFrame + " reachedS=" + s.ToString("F1") + " (from " + (rcS0 - 3f).ToString("F1") + ") share=" + (job.StretchShare(RcCutStretch) * 100f).ToString("F0") + "% ticked=" + job.Ticked(RcCutStretch) + rcLog);
                return false;
            }
            if (Mathf.FloorToInt(k / 4f) != Mathf.FloorToInt((k - Time.deltaTime) / 4f))
                rcLog += "\n  work k=" + k.ToString("F0") + " fwd=" + rcForward + " pass=" + rcPass + " s=" + s.ToString("F1") + " off=" + off.ToString("F1") + " edge=" + edgeOff.ToString("F2")
                       + " speed=" + d.Speed.ToString("F1") + " cliff=" + d.AtCliff + " fence=" + d.AtFence + " rock=" + d.BlockedByRock + " cut=" + d.LastCut + " clods=" + w.ClodCount
                       + " share=" + (job.StretchShare(RcStretch) * 100f).ToString("F0") + "%";
            float lane = (rcPass % 3 == 0) ? 0f : (rcPass % 3 == 1) ? 0.55f : -0.55f;   // each pass a little to one side, so the blade covers the whole road
            if (Mathf.Abs(d.Speed) > 0.3f) rcStuckFrames = 0; else rcStuckFrames++;
            if (rcStuckFrames > 90) { rcForward = !rcForward; rcStuckFrames = 0; rcLog += " unstuck@" + k.ToString("F0"); }   // stalled 3 s: go the other way
            // the blade angled so the spoil runs off its downhill end, over the edge of the road (side-casting)
            Vector3 outward = pos - new Vector3(Mountain.CX, pos.y, Mountain.CZ);
            float wantYaw = Vector3.Dot(d.transform.right, outward) > 0f ? d.bladeMaxAngle : -d.bladeMaxAngle;   // + swings the right end back
            d.overrideAngle = Mathf.Abs(d.BladeYaw - wantYaw) < 1f ? 0f : Mathf.Sign(wantYaw - d.BladeYaw);
            if (rcForward)
            {
                rcStride = 6;
                // down to grade, but in layers: never more than 0.3 m under the tracks in one pass, or the cut face
                // gets too tall for the machine to climb back over
                float layer = (pos.y - 0.3f) - (MountainRoad.GradeAt(s) + edgeOff);    // how far the edge is below the layer's floor (+ = too deep)
                float aim = Mathf.Min(edgeOff, -layer);                                   // above the higher of the two: lower it
                d.overrideBlade = aim > 0.03f ? -1f : aim < -0.03f ? 1f : 0f;
                RcSteer(d, RoadPoint(s + 4.5f, lane, out dir), false, 0.7f);
                if (s > rcS1 + 3f) { rcForward = false; rcPass++; }
            }
            else
            {
                rcStride = 10;
                d.overrideBlade = 1f;                              // back down the road, blade up
                RcSteer(d, RoadPoint(s - 4.5f, lane, out dir), true, 1f);
                if (s < rcS0 - 1.5f) rcForward = true;
            }
            if (k < 3f) rcStride = 1;                              // (the first seconds at normal speed, with the readout)
            if (rcCutOnly)
            {
                rcStride = 1;
                if (k < RcCutLength) return true;
                Debug.Log("BULLDOZER_ROADCUTCLIP_OK frames=" + clipFrame + " passes=" + rcPass + " share=" + (job.StretchShare(RcStretch) * 100f).ToString("F0") + "%" + rcLog);
                return false;
            }
            if (!job.Ticked(RcStretch) && k < 240f && rcPass < 14) return true;
            rcLog += " ticked=" + job.Ticked(RcStretch) + " after " + rcPass + " passes, " + k.ToString("F0") + "s share=" + (job.StretchShare(RcStretch) * 100f).ToString("F0") + "%";
            d.overrideThrottle = 0f; d.overrideSteer = 0f; d.overrideBlade = 1f;
            rcStride = 1; rcShowCab = false;
            if (follow != null) follow.enabled = false;
            float mid = (rcS0 + rcS1) * 0.5f;
            RcCam(cam, RcRoad(mid - 3f, MountainRoad.RoadHalf + 6f, 3.0f), RcRoad(mid, MountainRoad.RoadHalf + 1.1f, 1.2f), 1f);
            sCaption = job.Ticked(RcStretch) ? "7 in 10 of it within 15 cm of grade:  a green tick.   (All 15 ticked pays 500 coins.)"
                                             : "Not ticked yet: " + (job.StretchShare(RcStretch) * 100f).ToString("F0") + "% of it on grade";
            if (job.Ticked(RcStretch)) { sPop = "Stretch 13:  green tick!"; sPopUntil = Time.time + 3.5f; }
            sPh = 5; sT0 = t;
            return true;
        }
        if (sPh == 5)
        {
            float mid = (rcS0 + rcS1) * 0.5f;
            RcCam(cam, RcRoad(mid - 3f - k * 0.5f, MountainRoad.RoadHalf + 6f + k * 0.4f, 3.0f + k * 0.3f), RcRoad(mid, MountainRoad.RoadHalf + 1.1f, 1.2f), 0.1f);
            if (k < 5f) return true;
            rcShowKey = false;
            Debug.Log("BULLDOZER_ROADCLIP_OK frames=" + clipFrame + rcLog);
            return false;
        }
        return true;
    }

    static string AssCol32(Color32 c) { return "&H" + c.b.ToString("X2") + c.g.ToString("X2") + c.r.ToString("X2") + "&"; }

    static void RoadOverlay()
    {
        var job = MountainRoadJob.Instance;
        float a = clipFrame / 30f, b = (clipFrame + 1) / 30f;
        string at = AssTime(a) + "," + AssTime(b);
        if (sTitle.Length > 0) sOverlay.Add("Dialogue: 0," + at + ",Title,,0,0,0,," + AssEsc(sTitle));
        if (sCaption.Length > 0) sOverlay.Add("Dialogue: 0," + at + ",Caption,,0,0,0,," + AssEsc(sCaption));
        if (sPop.Length > 0 && Time.time < sPopUntil) sOverlay.Add("Dialogue: 0," + at + ",Pop,,0,0,0,," + AssEsc(sPop));
        if (job == null) return;
        string sq = "\u25A0";
        if (rcShowKey)
        {
            string key = "{\\b1}MOUNTAIN ROAD   " + job.TickedCount + " / " + MountainRoad.Stretches + " ticked{\\b0}\\N"
                + "{\\c" + AssCol32(new Color32(220, 40, 30, 255)) + "}" + sq + "{\\c&HFFFFFF&} RED: too high.  Cut it down.\\N"
                + "{\\c" + AssCol32(new Color32(40, 90, 230, 255)) + "}" + sq + "{\\c&HFFFFFF&} BLUE: too low.  Fill it.\\N"
                + "{\\c" + AssCol32(new Color32(40, 200, 60, 255)) + "}" + sq + "{\\c&HFFFFFF&} GREEN: on grade (within " + Mathf.RoundToInt(MountainRoadJob.OnGrade * 100f) + " cm)\\N"
                + "Pegs: CUT 1.2 = cut 1.2 m.  FILL 0.4 = fill 0.4 m.\\N"
                + "{\\c" + AssCol32(new Color32(40, 215, 65, 255)) + "}\u2714{\\c&HFFFFFF&} Tick: stretch done (half of it within " + Mathf.RoundToInt(MountainRoadJob.TickTolerance * 100f) + " cm)";
            sOverlay.Add("Dialogue: 0," + at + ",Key,,0,0,0,," + key);
        }
        if (rcShowCab && job.CabText.Length > 0)
        {
            string[] lines = job.CabText.Split('\n');
            string col = job.CabArrow < 0 ? AssCol32(new Color32(255, 100, 80, 255)) : job.CabArrow > 0 ? AssCol32(new Color32(130, 180, 255, 255)) : AssCol32(new Color32(100, 255, 115, 255));
            string arrow = job.CabArrow < 0 ? "\u25BC " : job.CabArrow > 0 ? "\u25B2 " : "\u25AC ";
            string cab = "{\\b1}" + lines[0] + "{\\b0}";
            for (int i = 1; i < lines.Length - 1; i++) cab += "\\N" + AssEsc(lines[i]);
            cab += "\\N{\\c" + col + "\\b1\\fs26}" + arrow + AssEsc(lines[lines.Length - 1]);
            sOverlay.Add("Dialogue: 0," + at + ",Cab,,0,0,0,," + cab);
        }
    }

    static void StartClip()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        clipFrame = 0; clipLastGameFrame = -1;
        testStart = EditorApplication.timeSinceStartup;
        string dir = Application.dataPath + "/../Logs/clip";
        if (System.IO.Directory.Exists(dir)) System.IO.Directory.Delete(dir, true);
        System.IO.Directory.CreateDirectory(dir);
        EditorApplication.update += ClipTick;
        EditorApplication.EnterPlaymode();
    }

    static void ClipTick()
    {
        if (EditorApplication.timeSinceStartup - testStart > 500) { Debug.LogError("BULLDOZER_CLIP_FAILED timed out"); ClipFinish(1); return; }
        if (!EditorApplication.isPlaying) return;
        var d = UnityEngine.Object.FindFirstObjectByType<DozerController>();
        var cam = Camera.main;
        if (d == null || cam == null || VoxelWorld.Instance == null) return;
        if (Time.frameCount == clipLastGameFrame) return;                 // one picture per game frame
        clipLastGameFrame = Time.frameCount;
        if (Worker.Instance == null) return;
        if (clipFrame == 0 && (clipMode < 9 || clipRT == null))          // (the motor and road clips skip their set-up frames: set up once)
        {
            Worker.Instance.useOverride = true;
            if (clipMode != 2 && clipMode < 9) { d.dead = false; Worker.Instance.GetIn(); }
            Time.captureFramerate = 30;                                    // game time steps 1/30 s a frame, however long drawing takes
            clipStart = Time.time;
            d.useOverride = true;
            if (clipRT == null) clipRT = new RenderTexture(1280, 720, 24);
            clipTex = new Texture2D(1280, 720, TextureFormat.RGB24, false);
        }
        float t = Time.time - clipStart;

        var follow = cam.GetComponent<FollowCamera>();
        if (clipMode == 3) { if (!NightStep(d, t)) return; }
        else if (clipMode == 9)
        {
            if (!MotorClipStep(d, t, follow, cam))
            {
                WriteOverlay();
                Debug.Log("BULLDOZER_MOTORCLIP_OK frames=" + clipFrame + " coins=" + Money.Instance.Coins + " cartAt=" + MineCart.Instance.Along.ToString("F1"));
                if (follow != null) follow.enabled = true;
                ClipFinish(0); return;
            }
            if (clipSkip) return;
        }
        else if (clipMode == 10)
        {
            if (!RoadClipStep(d, t, follow, cam))
            {
                WriteOverlay();
                if (follow != null) follow.enabled = true;
                ClipFinish(0); return;
            }
            if (clipSkip) return;
            if (rcStride > 1 && (Time.frameCount % rcStride) != 0) return;   // a sped-up part: only every few frames go in the clip
        }
        else if (clipMode == 8)
        {
            if (sPh == 0) { Prologue.Play(); sPh = 1; }
            var pr = Prologue.Instance;
            if (pr == null || !Prologue.Playing)
            {
                WriteOverlay();
                Debug.Log("BULLDOZER_PROLOGUE_OK frames=" + clipFrame + " fallen=" + FireSim.Instance.TreesFallen + " dozerAt=" + d.transform.position.ToString("F1")
                          + " breakHeldBeforeChange=" + prBreakHeld + " sonAt=" + Worker.Instance.transform.position.ToString("F1"));
                ClipFinish(0); return;
            }
            if (pr.T > 27.5f && pr.T < 27.6f) prBreakHeld = !FireSim.Instance.CellBurnt(new Vector3(0f, 0f, Prologue.LaneZ - 4f)) && FireSim.Instance.CellBurnt(new Vector3(0f, 0f, Prologue.LaneZ + 6f));
            PrologueOverlay(pr);
        }
        else if (clipMode == 7)
        {
            if (!FireClipStep(d, t, follow))
            {
                WriteOverlay();
                Debug.Log("BULLDOZER_FIRECLIP_OK frames=" + clipFrame + " fireTime=" + FireSim.Instance.Now.ToString("F0") + " fallen=" + FireSim.Instance.TreesFallen);
                if (follow != null) follow.enabled = true;
                ClipFinish(0); return;
            }
            TrCamera(cam, t);
            if (clipSkip) return;
        }
        else if (clipMode == 6)
        {
            if (!TrailerStep(d, t, follow))
            {
                WriteOverlay();
                Debug.Log("BULLDOZER_TRAILER_OK frames=" + clipFrame + " coins=" + Money.Instance.Coins + " clods=" + VoxelWorld.Instance.ClodCount);
                if (follow != null) follow.enabled = true;
                ClipFinish(0); return;
            }
            TrCamera(cam, t);
        }
        else if (clipMode == 5)
        {
            if (!UpgradeClipStep(d, t, follow))
            {
                WriteOverlay();
                Debug.Log("BULLDOZER_UPCLIP_OK frames=" + clipFrame + " shovel=" + Upgrades.Instance.Level(Upgrades.Branch.Shovel) + " backpack=" + Upgrades.Instance.Level(Upgrades.Branch.Backpack));
                ClipFinish(0); return;
            }
        }
        else if (clipMode == 4)
        {
            if (!ShowStep(d, t, follow))
            {
                WriteOverlay();
                Debug.Log("BULLDOZER_SHOW_OK frames=" + clipFrame + " avgRealMs=" + (sSum / Mathf.Max(1, sN)).ToString("F1") + " worstRealMs=" + sWorst.ToString("F1") + " coins=" + Money.Instance.Coins);
                ClipFinish(0); return;
            }
        }
        else if (clipMode == 2)
        {
            var wk = Worker.Instance;
            var vw = VoxelWorld.Instance;
            if (clipFrame == 0)
            {
                clipSolid0 = vw.SolidCount + vw.LoadVoxels;
                if (wk.InDozer) wk.GetOut();                                        // the game starts in the dozer
                wk.Teleport(new Vector3(VoxelWorld.PortalX - 1.15f, 0f, VoxelWorld.PortalZ - 7f), 0f);   // beside the track, so he walks past the cart
            }
            wk.overrideTurn = 0f;
            if (t < 3.6f) { wk.overrideWalk = 1f; wk.overrideUse = false; }                    // walk up and into the mine, seen from behind
            else if (t < 6f) { wk.overrideWalk = 0f; if (wk.Tool != 0) wk.SetTool(0); wk.overrideUse = true; }      // pick at the rubble
            else if (t < 6.3f) { wk.overrideUse = false; if (wk.Tool != 1) wk.SetTool(1); }
            else if (t < 10.5f) { wk.overrideUse = true; }                                                           // shovel, over his shoulder
            else if (t < 10.8f) { wk.overrideUse = false; if (!wk.Eyes) wk.SetEyes(true); }                        // then through his eyes
            else if (t < 15f) { wk.overrideWalk = 0f; wk.overrideUse = true; wk.overrideTurn = Mathf.Sin(t * 2.2f) * 0.25f; }
            else
            {
                Debug.Log("BULLDOZER_WALK_OK frames=" + clipFrame + " walkedTo=" + wk.transform.position.ToString("F1")
                    + " pickHits=" + wk.PickHits + " scoops=" + wk.Scoops + " throws=" + wk.Throws + " clods=" + vw.ClodCount
                    + " inCartLitres=" + (vw.CartVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0")
                    + " cartAt=" + (MineCart.Instance != null ? MineCart.Instance.transform.position.ToString("F1") : "none")
                    + " volumeChange=" + ((vw.CountSolid() + vw.LoadVoxels) - clipSolid0));
                ClipFinish(0); return;
            }
        }
        else if (clipMode == 1)
        {
            // on the grey rock: ripper down, a slow pass, then stop and let the rubble settle
            if (clipFrame == 0)
            {
                var start = new Vector3(16f, 0.2f, -13f);
                d.transform.position = start;
                var rb = d.GetComponent<Rigidbody>();
                if (rb != null) rb.position = start;
            }
            if (t < 1.4f) { d.overrideThrottle = 0f; d.overrideBlade = 1f; d.overrideRipper = -1f; }
            else if (t < 9f) { d.overrideThrottle = 0.7f; d.overrideBlade = 1f; d.overrideRipper = -1f; }
            else if (t < 12f) { d.overrideThrottle = 0f; d.overrideRipper = 1f; }
            else { Debug.Log("BULLDOZER_CLIP_OK frames=" + clipFrame + " ripped=" + VoxelWorld.Instance.TotalRipped); ClipFinish(0); return; }
            if (follow != null)
            {
                follow.yawOffset = Mathf.Lerp(35f, -45f, Mathf.SmoothStep(0f, 1f, t / 11f));
                follow.distance = 10f;
                follow.pitch = 30f;
            }
        }
        else
        {
            // the drive: lower the blade, cut a long pass, then lift the blade and swing away
            if (t < 1.2f) { d.overrideThrottle = 0f; d.overrideSteer = 0f; d.overrideBlade = -1f; }
            else if (t < 9.5f) { d.overrideThrottle = 1f; d.overrideSteer = 0f; d.overrideBlade = -1f; d.overrideAngle = t > 5f ? 1f : 0f; }   // angle the blade half way along
            else if (t < 13f) { d.overrideThrottle = 1f; d.overrideSteer = -1f; d.overrideBlade = 1f; }
            else { Debug.Log("BULLDOZER_CLIP_OK frames=" + clipFrame); ClipFinish(0); return; }

            // the camera swings from behind round to the side as it goes
            if (follow != null)
            {
                follow.yawOffset = Mathf.Lerp(20f, 118f, Mathf.SmoothStep(0f, 1f, t / 11f));
                follow.distance = Mathf.Lerp(13f, 9.5f, Mathf.Clamp01(t / 11f));
                follow.pitch = 19f;
            }
        }

        if (clipMode == 4)
        {
            float realMs = Mathf.Max(0f, Time.unscaledDeltaTime * 1000f - sCaptureMs);
            var vw = VoxelWorld.Instance;
            double dirt = vw.MsTotal[1] + vw.MsTotal[2];
            double dirtMs = clipFrame == 0 ? 0 : dirt - sDirt0;
            sDirt0 = dirt;
            if (clipFrame > 5) { sSum += realMs; sN++; sWorst = Mathf.Max(sWorst, realMs); }
            ShowOverlay(realMs, dirtMs);
        }
        if (clipMode == 5) UpgradeOverlay();
        if (clipMode == 9) MotorOverlay();
        if (clipMode == 10) RoadOverlay();
        var capWatch = System.Diagnostics.Stopwatch.StartNew();
        cam.targetTexture = clipRT;
        cam.Render();
        RenderTexture.active = clipRT;
        var bv = d.GetComponent<BladeView>();
        if (bv != null && clipMode < 6) bv.DrawInto(1280, 720);                                // the blade view is normally drawn straight to the screen
        clipTex.ReadPixels(new Rect(0, 0, 1280, 720), 0, 0);
        clipTex.Apply();
        cam.targetTexture = null;
        RenderTexture.active = null;
        System.IO.File.WriteAllBytes(Application.dataPath + "/../Logs/clip/frame_" + clipFrame.ToString("D4") + ".jpg", clipTex.EncodeToJPG(93));
        clipFrame++;
        sCaptureMs = (float)capWatch.Elapsed.TotalMilliseconds;
    }

    /// One step of the upgrade clip.  Returns false when it has finished.
    static bool UpgradeClipStep(DozerController d, float t, FollowCamera follow)
    {
        var wk = Worker.Instance; var w = VoxelWorld.Instance; var cart = MineCart.Instance; var money = Money.Instance; var up = Upgrades.Instance;
        if (cart == null || money == null || up == null) return true;
        if (sPh == 0)
        {
            d.overrideThrottle = 0f;
            if (wk.InDozer) wk.GetOut();
            if (follow != null) follow.yawOffset = 0f;
            up.Reset(); money.Clear();
            sSide = cart.transform.right; sSide.y = 0f; sSide.Normalize();
            sStand = cart.transform.position + sSide * 1.3f - cart.transform.forward * 0.6f;
            sPatch = cart.transform.position + sSide * 3.1f;
            // a good patch of loose ground to dig, broken up before the clip starts
            for (int i = 0; i < 18; i++)
            {
                Vector3 at = sPatch + cart.transform.forward * (-1.2f + (i % 3) * 0.9f) + sSide * (((i / 3) % 2) * 0.7f);
                at.y = w.FloorAt(at + Vector3.up) + (i < 6 ? 0.05f : i < 12 ? -0.35f : -0.75f);
                w.Pick(at, 0.5f, Vector3.zero);
            }
            Vector3 aim = sPatch - cart.transform.forward * 0.3f; aim.y = w.FloorAt(aim + Vector3.up);
            ShowAim(wk, aim);
            wk.SetTool(1);
            sTitle = ""; sCaption = "";
            sPh = 1; sT0 = t;
            return true;
        }
        float k = t - sT0;
        if (sPh == 1)
        {
            if (k < 3f) return true;                                             // the broken ground settles
            sTitle = "Shovel 1"; sCaption = "Starting shovel: about 117 litres a scoop.  Every scoop goes in the cart.";
            uScoopMax = 0; uLastScoops = wk.Scoops;
            wk.overrideUse = true;
            sPh = 2; sT0 = t;
            return true;
        }
        if (sPh == 2)
        {
            uScoopMax = Mathf.Max(uScoopMax, w.ShovelVoxels);
            if (k < 6.5f) return true;
            wk.overrideUse = false;
            sPop = "Shovel 1:  " + (wk.Scoops - uLastScoops) + " scoops in 6.5 s,  biggest " + (uScoopMax * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + " L"; sPopUntil = Time.time + 4f;
            // into the tree (test coins, so the clip doesn't need ten minutes of digging)
            money.TestGrant(2000, 0);
            sTitle = "The upgrades (U)"; sCaption = "Buying Shovel 2, 3, 4, 5 and 6  (coins from the F8 test key)";
            uPanel = up.Describe(Upgrades.Branch.Shovel);
            sPh = 3; sT0 = t; sStep = 0;
            return true;
        }
        if (sPh == 3)
        {
            // one level every 0.6 s, so you see the ticks go down the list
            if (k > 0.8f + sStep * 0.6f && sStep < 5) { up.Buy(Upgrades.Branch.Shovel); sStep++; uPanel = up.Describe(Upgrades.Branch.Shovel); }
            if (k < 5f) return true;
            uPanel = "";
            sTitle = "Shovel 6"; sCaption = "Bigger scoops and 60% faster swings";
            uScoopMax = 0; uLastScoops = wk.Scoops;
            // a fresh part of the patch, further along the cart, with him moved along to match
            sStand = cart.transform.position + sSide * 1.8f + cart.transform.forward * 0.6f;   // close: the patch is a pit by now
            Vector3 aim = sPatch + cart.transform.forward * 0.6f; aim.y = w.FloorAt(aim + Vector3.up);
            ShowAim(wk, aim);
            wk.overrideUse = true;
            sPh = 4; sT0 = t;
            return true;
        }
        if (sPh == 4)
        {
            uScoopMax = Mathf.Max(uScoopMax, w.ShovelVoxels);
            if (k < 6.5f) return true;
            wk.overrideUse = false;
            if (wk.Scoops == uLastScoops) Debug.LogError("BULLDOZER_UPCLIP_FAILED no scoops at Shovel 6");
            sPop = "Shovel 6:  " + (wk.Scoops - uLastScoops) + " scoops in 6.5 s,  biggest " + (uScoopMax * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + " L"; sPopUntil = Time.time + 4f;
            money.TestGrant(0, Mathf.CeilToInt(5f / (VoxelWorld.VoxelVolume * 1000f)));
            sTitle = "The upgrades (U)"; sCaption = "Shovel maxed, so the backpack unlocks: 400 coins and 5 L of gold";
            uPanel = up.Describe(Upgrades.Branch.Backpack);
            sPh = 5; sT0 = t;
            return true;
        }
        if (sPh == 5)
        {
            if (k > 1.5f && !up.HasBackpack) { up.Buy(Upgrades.Branch.Backpack); uPanel = up.Describe(Upgrades.Branch.Backpack); }
            if (k < 4f) return true;
            uPanel = "";
            wk.SetTool(2);
            sTitle = "Backpack 1"; sCaption = "3 for the backpack: it starts small and slow, and gets 7 more levels";
            Vector3 aim = sPatch - cart.transform.forward * 0.6f; aim.y = w.FloorAt(aim + Vector3.up);
            ShowAim(wk, aim);
            wk.overrideUse = true;
            sPh = 6; sT0 = t; sStep = 0; sNext = t;
            return true;
        }
        if (sPh == 6)
        {
            if (t >= sNext)
            {
                sNext = t + 0.7f;
                Vector3 at = sPatch + cart.transform.forward * (-0.9f + (sStep % 4) * 0.6f) + sSide * (((sStep / 4) % 2) * 0.4f);
                at.y = w.FloorAt(at + Vector3.up);
                ShowAim(wk, at);
                sStep++;
            }
            if (k < 5f) return true;
            wk.overrideUse = false;
            return false;
        }
        return true;
    }

    static void UpgradeOverlay()
    {
        var w = VoxelWorld.Instance; var money = Money.Instance; var wk = Worker.Instance;
        float a = clipFrame / 30f, b = (clipFrame + 1) / 30f;
        string at = AssTime(a) + "," + AssTime(b);
        string tool = wk.Tool == 2 ? "Backpack " + (w.PackVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + " of " + (wk.packHolds * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + " L"
                    : "On the shovel " + (w.ShovelVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + " L";
        sOverlay.Add("Dialogue: 0," + at + ",Perf,,0,0,0,," + tool + "\\NCart " + (w.CartVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + " L");
        sOverlay.Add("Dialogue: 0," + at + ",Hud,,0,0,0,,Coins " + money.Coins.ToString("N0") + "\\NGold " + money.GoldLitres.ToString("F0") + " L");
        if (sTitle.Length > 0) sOverlay.Add("Dialogue: 0," + at + ",Title,,0,0,0,," + AssEsc(sTitle));
        if (sCaption.Length > 0) sOverlay.Add("Dialogue: 0," + at + ",Caption,,0,0,0,," + AssEsc(sCaption));
        if (uPanel.Length > 0) sOverlay.Add("Dialogue: 0," + at + ",Panel,,0,0,0,," + AssEsc(uPanel.TrimEnd('\n').Replace("\n", "\\N")));
        if (sPop.Length > 0 && Time.time < sPopUntil) sOverlay.Add("Dialogue: 0," + at + ",Pop,,0,0,0,," + AssEsc(sPop));
    }

    /// A caption that stays up until the next one (with a fade in and out).  style: Big, Card, Small.
    static void TrCaption(string text, string style = "Big")
    {
        float now = clipFrame / 30f;
        if (trCap.Length > 0 && now - trCapStart > 0.05f)
            trCaps.Add("Dialogue: 0," + AssTime(trCapStart) + "," + AssTime(now) + "," + trCapStyle + ",,0,0,0,,{\\fad(350,300)}" + AssEsc(trCap));
        trCap = text; trCapStyle = style; trCapStart = now;
    }

    /// A camera move, from one place (looking at one point) to another, over `len` seconds of the clip.
    static void TrMove(FollowCamera follow, float t, Vector3 from, Vector3 lookFrom, Vector3 to, Vector3 lookTo, float len)
    {
        if (follow != null) follow.enabled = false;              // (its OnDisable turns off the see-through cut)
        trCustom = true;
        trCamFrom = from; trLookFrom = lookFrom; trCamTo = to; trLookTo = lookTo; trCamT0 = t; trCamLen = len;
    }

    static void TrFollow(FollowCamera follow)
    {
        trCustom = false;
        if (follow != null) follow.enabled = true;
    }

    static void TrCamera(Camera cam, float t)
    {
        if (!trCustom) return;
        float u = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01((t - trCamT0) / Mathf.Max(0.01f, trCamLen)));
        Vector3 pos = Vector3.Lerp(trCamFrom, trCamTo, u), look = Vector3.Lerp(trLookFrom, trLookTo, u);
        cam.transform.SetPositionAndRotation(pos, Quaternion.LookRotation(look - pos, Vector3.up));
    }

    /// One step of the fire clip.  Returns false when it has finished.
    static bool FireClipStep(DozerController d, float t, FollowCamera follow)
    {
        var fire = FireSim.Instance; var wk = Worker.Instance;
        if (fire == null || FireSim.Trees.Count == 0) { clipSkip = true; return true; }
        clipSkip = false;
        Vector3 portal = new Vector3(VoxelWorld.PortalX, 0f, VoxelWorld.PortalZ);
        if (sPh == 0)
        {
            if (wk.InDozer) wk.GetOut();
            wk.Teleport(portal + new Vector3(-30f, 0f, -30f), 0f);
            fire.SetWind(new Vector2(0.6f, -5f), new Vector2(2.5f, -11f), 60f);
            fire.ClearFuel(-110f, FrBreakZ0, 110f, FrBreakZ1);
            fire.Begin();
            fire.Ignite(new Vector3(-100f, 0f, 160f), new Vector3(100f, 0f, 160f));
            fire.speedUp = 10f;                                   // warm up unrecorded to 15 s of fire
            sPh = 1;
        }
        if (sPh == 1)
        {
            if (fire.Now < 15f) { clipSkip = true; return true; }
            fire.speedUp = 2.2f;
            TrMove(follow, t, new Vector3(-14f, 26f, -26f), new Vector3(VoxelWorld.TrackX + 6f, 12f, 90f),
                              new Vector3(-6f, 22f, -14f), new Vector3(VoxelWorld.TrackX + 4f, 12f, 92f), 9f);
            TrCaption("Fire test (work in progress): the front comes down the hill");
            sPh = 2; sT0 = t;
            return true;
        }
        float k = t - sT0;
        if (sPh == 2)
        {
            if (k < 9f) return true;
            // on the track, looking up into the forest as the front arrives; two trees beside it will come down across it
            fire.speedUp = 1.2f;
            float cz = 64f;
            Vector3 at = new Vector3(VoxelWorld.TrackCentreX(cz) - 1.2f, SiteProps.HillY(VoxelWorld.TrackCentreX(cz), cz) + 2.2f, cz);
            Vector3 look = new Vector3(VoxelWorld.TrackCentreX(cz + 30f), SiteProps.HillY(VoxelWorld.TrackCentreX(cz + 30f), cz + 30f) + 6f, cz + 30f);
            TrMove(follow, t, at, look, at + new Vector3(0f, 0.6f, -2f), look + new Vector3(0f, -1f, 0f), 12f);
            for (int side = -1; side <= 1; side += 2)
            {
                float tz = side < 0 ? 76f : 83f;
                int tr = FireSim.TreeNear(new Vector3(VoxelWorld.TrackCentreX(tz) + side * 6f, 0f, tz), 4f);
                if (tr >= 0) fire.FellTree(tr, fire.Now + (side < 0 ? 5f : 8f), Mathf.Atan2(-side, -0.35f));
            }
            TrCaption("Trees burn through and fall");
            sPh = 3; sT0 = t;
            return true;
        }
        if (sPh == 3)
        {
            if (k < 12f) return true;
            // at the firebreak: it holds, then the wind changes and carries the fire over
            fire.speedUp = 2.4f;
            TrMove(follow, t, new Vector3(VoxelWorld.TrackX - 38f, 46f, 18f), new Vector3(VoxelWorld.TrackX - 4f, 10f, 64f),
                              new Vector3(VoxelWorld.TrackX - 30f, 42f, 22f), new Vector3(VoxelWorld.TrackX, 8f, 60f), 13f);   // high over the canopy
            TrCaption("The firebreak holds...");
            sPh = 4; sT0 = t;
            return true;
        }
        if (sPh == 4)
        {
            if (fire.Now > 61f && trCap == "The firebreak holds...") TrCaption("...until the wind changes, and embers carry it over");
            if (k < 13f) return true;
            TrCaption("");
            return false;
        }
        return true;
    }

    /// One step of the trailer.  Returns false when it has finished.
    static bool TrailerStep(DozerController d, float t, FollowCamera follow)
    {
        var wk = Worker.Instance; var w = VoxelWorld.Instance; var cart = MineCart.Instance; var money = Money.Instance; var up = Upgrades.Instance;
        if (cart == null || money == null || up == null) return true;
        Vector3 portal = new Vector3(VoxelWorld.PortalX, 0f, VoxelWorld.PortalZ);
        if (sPh == 0)
        {
            up.Reset(); money.Clear();
            d.overrideThrottle = 0f;
            if (wk.InDozer) wk.GetOut();
            wk.Teleport(portal + new Vector3(-30f, 0f, -30f), 0f);                 // out of the first shot
            // 1. high over the quarry, drifting in towards the old mine entrance
            TrMove(follow, t, portal + new Vector3(-26f, 22f, -34f), portal + new Vector3(0f, 0f, -4f), portal + new Vector3(-12f, 9f, -17f), portal + new Vector3(0f, 1.5f, 1f), 7f);
            TrCaption("An old gold mine.\\NCaved in years ago.", "Card");
            sPh = 1; sT0 = t;
            return true;
        }
        float k = t - sT0;
        if (sPh == 1)
        {
            if (k < 7f) return true;
            // 2. he walks up to the entrance
            wk.Teleport(new Vector3(VoxelWorld.PortalX - 1.15f, 0f, VoxelWorld.PortalZ - 8f), 0f);
            wk.Look(10f);
            wk.overrideWalk = 1f;
            TrMove(follow, t, portal + new Vector3(3.5f, 1.4f, -11f), portal + new Vector3(-1f, 1.2f, -6f), portal + new Vector3(2.5f, 1.8f, -6.5f), portal + new Vector3(-0.8f, 1.4f, -1f), 4f);
            TrCaption("Dig it out by hand.");
            sPh = 2; sT0 = t;
            return true;
        }
        if (sPh == 2)
        {
            if (k < 4f) return true;
            wk.overrideWalk = 0f;
            // 3. in at the cave-in: the cart up against the rubble, and him working the face beside it
            cart.SetAlong(cart.Along - cart.RoomAhead(-1f));
            Vector3 inward = -cart.transform.forward;
            wk.Teleport(cart.transform.position + cart.transform.right * 1.0f + inward * 0.7f, Facing(inward));
            wk.Look(28f);
            wk.SetTool(0);
            wk.overrideUse = true;
            {
                Vector3 c = cart.transform.position, fo = cart.transform.forward, ri = cart.transform.right;
                TrMove(follow, t, c + fo * 3.4f + ri * 0.5f + Vector3.up * 1.9f, c - fo * 1.6f + ri * 0.7f + Vector3.up * 0.9f,
                                  c + fo * 2.4f + ri * 0.2f + Vector3.up * 1.7f, c - fo * 1.8f + ri * 0.8f + Vector3.up * 0.8f, 7f);
            }
            TrCaption("Break the rubble.  Shovel it into the cart.");
            sPh = 3; sT0 = t;
            return true;
        }
        if (sPh == 3)
        {
            int want = (k % 3f) < 0.9f ? 0 : 1;                                     // the pick now and then, the shovel the rest
            if (wk.Tool != want) wk.SetTool(want);
            if (k < 7f) return true;
            wk.overrideUse = false;
            // 4. take hold of the inner end and push it back out
            Vector3 f = cart.transform.forward; f.y = 0f; f.Normalize();
            wk.Teleport(cart.transform.position - f * 1.45f, Facing(f));
            wk.GrabCart();
            wk.overrideWalk = 1f;
            {
                Vector3 c = cart.transform.position, ri = cart.transform.right;
                TrMove(follow, t, c + f * 11f + ri * 1.4f + Vector3.up * 1.6f, c + Vector3.up * 0.9f,
                                  c + f * 12.5f + ri * 2.2f + Vector3.up * 1.8f, c + f * 7.5f + Vector3.up * 0.9f, 4f);
            }
            TrCaption("Push it out.");
            sPh = 4; sT0 = t;
            return true;
        }
        if (sPh == 4)
        {
            if (k < 4f) return true;
            wk.overrideWalk = 0f; wk.LetGo();
            // 5. at the dump: E tips it into the hopper
            cart.SetAlong(cart.EndLimit);
            Vector3 f = cart.transform.forward, r = cart.transform.right;
            wk.Teleport(cart.transform.position - f * 2.4f + r * 0.9f, Facing(f - r * 0.45f));
            TrMove(follow, t, cart.transform.position + r * 4.2f - f * 3.2f + Vector3.up * 2.6f, cart.transform.position - r * 1.2f,
                              cart.transform.position + r * 3.0f - f * 1.8f + Vector3.up * 2.2f, cart.transform.position - r * 1.6f, 5f);
            TrCaption("Tip it into the hopper.");
            sCoins0 = (int)money.Coins;
            sPh = 5; sT0 = t;
            return true;
        }
        if (sPh == 5)
        {
            if (k > 0.8f && !cart.Tipping && sStep != 55) { wk.PressE(); sStep = 55; }
            if (k > 3.8f && trCap == "Tip it into the hopper.") TrCaption("Sorted and sold:  +" + (money.Coins - sCoins0) + " coins");
            if (k < 5f) return true;
            // 6. the gold buyer (with gold added for the demo)
            var demo = new int[16]; demo[VoxelWorld.LooseGold] = 120;
            money.Pay(demo);
            Vector3 front = SiteProps.GoldShedFront;
            wk.Teleport(front, Facing(Vector3.right));
            wk.Look(12f);
            TrMove(follow, t, front + new Vector3(-3.2f, 1.7f, -3.4f), front + new Vector3(1.2f, 1.2f, 0f), front + new Vector3(-2.4f, 1.6f, -1.6f), front + new Vector3(1.4f, 1.3f, 0f), 4f);
            TrCaption("Keep the gold...  or sell it.");
            sPh = 6; sT0 = t; sStep = 0;
            return true;
        }
        if (sPh == 6)
        {
            if (k > 1.6f && sStep == 0)
            {
                long c0 = money.Coins; wk.PressE(); sStep = 1;
                TrCaption("Gold sells for 50 times dirt:  +" + (money.Coins - c0) + " coins   (demo gold)");
            }
            if (k < 4.5f) return true;
            // 7. upgrades: a maxed shovel, then the backpack
            money.TestGrant(5000, 40);
            for (int i = 0; i < 5; i++) up.Buy(Upgrades.Branch.Shovel);
            up.Buy(Upgrades.Branch.Backpack); up.Buy(Upgrades.Branch.Backpack); up.Buy(Upgrades.Branch.Backpack);
            // a fresh patch of broken ground by the mine, beside the rails
            sSide = Vector3.right;
            sPatch = portal + new Vector3(-4.5f, 0f, -9f);
            for (int i = 0; i < 12; i++)
            {
                Vector3 at = sPatch + new Vector3((i % 3) * 0.8f - 0.8f, 0f, ((i / 3) % 2) * 0.7f);
                at.y = w.FloorAt(at + Vector3.up) + (i < 6 ? 0.05f : -0.35f);
                w.Pick(at, 0.48f, Vector3.zero);
            }
            sStand = sPatch + new Vector3(1.9f, 0f, -0.2f);
            Vector3 aim = sPatch; aim.y = w.FloorAt(aim + Vector3.up);
            ShowAim(wk, aim);
            wk.SetTool(2);
            TrMove(follow, t, sPatch + new Vector3(3.4f, 1.3f, -3.4f), sPatch + new Vector3(0.9f, 0.6f, 0f),
                              sPatch + new Vector3(2.6f, 1.2f, -3.0f), sPatch + new Vector3(0.8f, 0.6f, 0.1f), 6f);
            TrCaption("Upgrade everything.");
            sPh = 7; sT0 = t; sStep = 0; sNext = t + 1.5f;
            return true;
        }
        if (sPh == 7)
        {
            if (k > 1.5f) wk.overrideUse = true;                                   // the broken ground settles first
            if (t >= sNext)
            {
                sNext = t + 0.6f;
                Vector3 at = sPatch + new Vector3((sStep % 4) * 0.5f - 0.75f, 0f, ((sStep / 4) % 2) * 0.5f);
                at.y = w.FloorAt(at + Vector3.up);
                ShowAim(wk, at);
                sStep++;
            }
            if (k > 2.5f && trCap == "Upgrade everything.") TrCaption("The suction backpack.");
            if (k < 6f) return true;
            wk.overrideUse = false;
            // 8. the dozer: lower the blade and push a big heap
            wk.GetIn();
            d.useOverride = true;
            Vector3 dp = d.transform.position, df = d.transform.forward, dr = d.transform.right;
            TrMove(follow, t, dp + df * 9f + dr * 4.5f + Vector3.up * 1.1f, dp + Vector3.up * 1.2f, dp + df * 16f + dr * 6f + Vector3.up * 2.4f, dp + df * 9f + Vector3.up * 0.8f, 11f);
            TrCaption("And bring in the machinery.");
            sPh = 8; sT0 = t;
            return true;
        }
        if (sPh == 8)
        {
            if (k < 1.2f) { d.overrideThrottle = 0f; d.overrideBlade = -1f; }
            else { d.overrideThrottle = 1f; d.overrideBlade = k < 4f ? -1f : 0f; }
            if (k > 5.5f && trCap == "And bring in the machinery.") TrCaption("Every clod of dirt is simulated.");
            if (k < 11f) return true;
            d.overrideThrottle = 0f;
            TrCaption("Work in progress\\N\\NComing:  the jackhammer  ·  motor carts  ·  play with up to 4 friends", "Card");
            sPh = 9; sT0 = t;
            return true;
        }
        if (sPh == 9)
        {
            if (k < 5f) return true;
            TrCaption("");
            return false;
        }
        return true;
    }

    static void ShowAim(Worker wk, Vector3 target)
    {
        Vector3 eye = sStand + Vector3.up * 1.6f, d = target - eye;
        Vector3 flat = new Vector3(d.x, 0f, d.z);
        wk.Teleport(sStand, Facing(flat));
        wk.Look(Mathf.Atan2(-d.y, flat.magnitude) * Mathf.Rad2Deg);
    }

    /// One step of the showcase.  Returns false when it has finished.
    static bool ShowStep(DozerController d, float t, FollowCamera follow)
    {
        var wk = Worker.Instance; var w = VoxelWorld.Instance; var cart = MineCart.Instance; var money = Money.Instance;
        if (cart == null || money == null) return true;
        if (sPh == 0)
        {
            if (Upgrades.Instance != null) Upgrades.Instance.SetLevel(Upgrades.Branch.Backpack, 4);
            sTitle = "1.  Pushing a big heap"; sCaption = "Blade dug in, pushing: thousands of loose clods, each one simulated";
            sT0 = t; sPh = 1;
        }
        float k = t - sT0;
        if (sPh == 1)
        {
            // lower the blade, then push on with it dug in so the heap keeps growing
            if (k < 1.2f) { d.overrideThrottle = 0f; d.overrideBlade = -1f; }
            else if (k < 15f) { d.overrideThrottle = 1f; d.overrideBlade = k < 4f ? -1f : 0f; d.overrideSteer = (k > 9f && k < 11f) ? 0.4f : 0f; }
            else { sPh = 2; sT0 = t; d.overrideThrottle = 0f; sCaption = "Stopped: the loose dirt settles back into ground within a couple of seconds"; }
            if (follow != null) { follow.yawOffset = Mathf.Lerp(25f, 110f, Mathf.SmoothStep(0f, 1f, k / 15f)); follow.distance = Mathf.Lerp(12f, 9f, Mathf.Clamp01(k / 15f)); follow.pitch = 22f; }
            return true;
        }
        if (sPh == 2)
        {
            if (follow != null) { follow.yawOffset = 110f; follow.distance = 9f; follow.pitch = 26f; }
            if (k < 4f) return true;
            // out of the dozer, beside the cart by the mine entrance
            d.overrideThrottle = 0f;
            wk.GetOut();
            if (follow != null) follow.yawOffset = 0f;                         // back to the view over his shoulder
            sSide = cart.transform.right; sSide.y = 0f; sSide.Normalize();
            sStand = cart.transform.position + sSide * 1.5f;
            sPatch = cart.transform.position + sSide * 2.8f;
            wk.SetTool(0);
            Vector3 aim = sPatch; aim.y = w.FloorAt(aim + Vector3.up);
            ShowAim(wk, aim);
            wk.overrideUse = true;
            sTitle = "2.  The suction backpack"; sCaption = "Break the ground up with the pick (1)...";
            sStep = 0; sNext = t; sPh = 3; sT0 = t;
            return true;
        }
        if (sPh == 3)
        {
            // he swings the pick at the patch, and the patch breaks up around where he hits
            if (t >= sNext && sStep < 12)
            {
                sNext = t + 0.35f;
                Vector3 at = sPatch + cart.transform.forward * (-0.8f + (sStep % 3) * 0.8f) + sSide * (((sStep / 3) % 2) * 0.6f);
                at.y = w.FloorAt(at + Vector3.up) + (sStep < 6 ? 0.05f : -0.3f);
                w.Pick(at, 0.42f, Vector3.up * 0.3f);
                sStep++;
            }
            if (k < 4.5f) return true;
            wk.overrideUse = false;
            wk.SetTool(2);
            sCaption = "...then 3 for the backpack: hold the button and loose dirt flies into the nozzle (500 litres)";
            sStep = 0; sNext = t; sPh = 4; sT0 = t;
            wk.overrideUse = true;
            return true;
        }
        if (sPh == 4)
        {
            if (t >= sNext)
            {
                sNext = t + 0.6f;
                Vector3 at = sPatch + cart.transform.forward * (-0.9f + (sStep % 4) * 0.6f) + sSide * (((sStep / 4) % 3) * 0.35f);
                at.y = w.FloorAt(at + Vector3.up);
                ShowAim(wk, at);
                sStep++;
            }
            if (k < 7f && w.PackVoxels < wk.packHolds - VoxelWorld.ClodVoxels) return true;
            wk.overrideUse = false;
            ShowAim(wk, cart.Mouth);
            wk.StartPour();
            sCaption = "Q by the cart squirts the backpack into it";
            sPh = 5; sT0 = t;
            return true;
        }
        if (sPh == 5)
        {
            if (k < 3.5f) return true;
            // to the dump.  (The 50 m push is skipped.)
            cart.SetAlong(cart.EndLimit);
            wk.Teleport(cart.transform.position - cart.transform.forward * 2.6f + cart.transform.right * 0.9f, Facing(cart.transform.forward - cart.transform.right * 0.45f));
            wk.Look(30f);
            sTitle = "3.  The hopper at the dump"; sCaption = "(skipping the 50 m push out to the end of the rails)";
            sPh = 6; sT0 = t;
            return true;
        }
        if (sPh == 6)
        {
            if (k < 2f) return true;
            for (int m = 0; m < 16; m++) sLoadL[m] = w.CartLoadOf(m) * VoxelWorld.VoxelVolume * 1000.0;
            sCoins0 = (int)money.Coins;
            wk.PressE();
            if (!cart.Tipping) Debug.LogError("BULLDOZER_SHOW_FAILED the cart did not tip at the dump");
            sCaption = "E at the end of the rails tips the cart into the hopper: it's sorted and sold as it goes down";
            sPh = 7; sT0 = t;
            return true;
        }
        if (sPh == 7)
        {
            if (k < 3.5f) return true;
            string sorted = "";
            string[] names = { "", "", "", "", "", "", "Soil", "Clay", "Rock", "Quartz", "Gold" };
            for (int m = VoxelWorld.LooseSoil; m <= VoxelWorld.LooseGold; m++) if (sLoadL[m] >= 0.5) sorted += (sorted.Length > 0 ? "   " : "") + names[m] + " " + sLoadL[m].ToString("F0") + " L";
            sPop = "Hopper sorted it:  " + sorted + "   =  +" + (money.Coins - sCoins0) + " coins"; sPopUntil = Time.time + 4.5f;
            if (k < 7.5f) return true;
            // gold: real gold is rare flecks in the quartz, so some is added for the demo
            var demo = new int[16]; demo[VoxelWorld.LooseGold] = 120;
            money.Pay(demo);
            Vector3 front = SiteProps.GoldShedFront;
            sStand = front + new Vector3(-2.6f, 0f, 0.9f);
            wk.Teleport(sStand, Facing(Vector3.right * 0.9f - Vector3.forward * 0.3f));
            wk.Look(12f);
            sTitle = "4.  The gold buyer's shed"; sCaption = "Gold isn't sold at the hopper: it goes to your gold store  (" + money.GoldLitres.ToString("F0") + " L added for this demo)";
            sPh = 8; sT0 = t;
            return true;
        }
        if (sPh == 8)
        {
            // walk up to the counter
            wk.overrideWalk = k < 1.6f ? 1f : 0f;
            if (k < 3f) return true;
            wk.Teleport(SiteProps.GoldShedFront, Facing(Vector3.right));
            wk.Look(14f);
            long c0 = money.Coins; float litres = money.GoldLitres;
            wk.PressE();
            sPop = "Sold " + litres.ToString("F0") + " L of gold:  +" + (money.Coins - c0).ToString("N0") + " coins"; sPopUntil = Time.time + 5f;
            sCaption = "E at the counter sells all your gold.  Gold you keep is for buying machinery later.";
            sPh = 9; sT0 = t;
            return true;
        }
        if (sPh == 9)
        {
            if (k < 5f) return true;
            return false;
        }
        return true;
    }

    static string AssTime(float sec) { int cs = Mathf.RoundToInt(sec * 100f); return (cs / 360000) + ":" + ((cs / 6000) % 60).ToString("D2") + ":" + ((cs / 100) % 60).ToString("D2") + "." + (cs % 100).ToString("D2"); }
    static string AssEsc(string x) { return x.Replace("{", "(").Replace("}", ")"); }

    /// What goes on screen over this frame (written as one subtitle event per frame).
    static void ShowOverlay(float realMs, double dirtMs)
    {
        var w = VoxelWorld.Instance; var money = Money.Instance;
        float a = clipFrame / 30f, b = (clipFrame + 1) / 30f;
        string at = AssTime(a) + "," + AssTime(b);
        sRealSmooth = sRealSmooth <= 0f ? realMs : Mathf.Lerp(sRealSmooth, realMs, 0.25f);
        string perf = "Frame time " + sRealSmooth.ToString("F1") + " ms  (" + (1000f / Mathf.Max(0.1f, sRealSmooth)).ToString("F0") + " fps)\\N"
                    + "Dirt work " + dirtMs.ToString("F2") + " ms     Clods moving " + w.ClodCount.ToString("N0");
        sOverlay.Add("Dialogue: 0," + at + ",Perf,,0,0,0,," + perf);
        sOverlay.Add("Dialogue: 0," + at + ",Hud,,0,0,0,,Coins " + money.Coins.ToString("N0") + "\\NGold " + money.GoldLitres.ToString("F0") + " L");
        if (sTitle.Length > 0) sOverlay.Add("Dialogue: 0," + at + ",Title,,0,0,0,," + AssEsc(sTitle));
        if (sCaption.Length > 0) sOverlay.Add("Dialogue: 0," + at + ",Caption,,0,0,0,," + AssEsc(sCaption));
        if (sPop.Length > 0 && Time.time < sPopUntil) sOverlay.Add("Dialogue: 0," + at + ",Pop,,0,0,0,," + AssEsc(sPop));
    }

    static void WriteOverlay()
    {
        var head = new List<string>
        {
            "[Script Info]", "ScriptType: v4.00+", "PlayResX: 1280", "PlayResY: 720", "",
            "[V4+ Styles]",
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
            "Style: Perf,Consolas,22,&H00FFFFFF,&H000000FF,&H00000000,&H90000000,1,0,0,0,100,100,0,0,3,6,0,7,18,18,16,1",
            "Style: Hud,Arial,26,&H0040D8FF,&H000000FF,&H00000000,&H90000000,1,0,0,0,100,100,0,0,3,6,0,9,18,18,16,1",
            "Style: Title,Arial,34,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,1,0,0,0,100,100,0,0,1,3,1,8,20,20,78,1",
            "Style: Caption,Arial,26,&H00FFFFFF,&H000000FF,&H00000000,&H90000000,0,0,0,0,100,100,0,0,3,6,0,2,30,30,28,1",
            "Style: Pop,Arial,28,&H0040D8FF,&H000000FF,&H00000000,&HA0000000,1,0,0,0,100,100,0,0,3,8,0,5,30,30,0,1",
            "Style: Big,Arial,40,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,1,0,0,0,100,100,1,0,1,3,2,2,40,40,70,1",
            "Style: Card,Arial,46,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,1,0,0,0,100,100,1,0,1,3,2,5,60,60,0,1",
            "Style: Place,Arial,30,&H00F0F0F0,&H000000FF,&H00000000,&H00000000,1,0,0,0,100,100,4,0,1,2,2,1,80,40,90,1",
            "Style: Shout,Arial,52,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,1,0,0,0,100,100,0,0,1,3,2,2,40,40,90,1",
            "Style: Shade,Arial,20,&H00000000,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1",
            "Style: Panel,Consolas,22,&H00FFFFFF,&H000000FF,&H00000000,&HC0101010,0,0,0,0,100,100,0,0,3,10,0,5,30,30,0,1",
            "Style: Key,Arial,19,&H00FFFFFF,&H000000FF,&H00000000,&H90101010,0,0,0,0,100,100,0,0,3,8,0,7,20,20,20,1",
            "Style: Cab,Consolas,20,&H00FFFFFF,&H000000FF,&H00000000,&H90101010,0,0,0,0,100,100,0,0,3,8,0,9,20,20,20,1",
            "", "[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
        };
        head.AddRange(sOverlay);
        foreach (var c in trCaps)
        {
            if (c.Contains(",Card,"))
            {
                // a dark wash over the frame behind a card, faded with it
                string[] parts = c.Split(',');
                head.Add("Dialogue: 0," + parts[1] + "," + parts[2] + ",Shade,,0,0,0,,{\\fad(350,300)\\1a&H60&\\p1}m 0 0 l 1280 0 1280 720 0 720{\\p0}");
            }
            head.Add(c.Replace("Dialogue: 0,", "Dialogue: 1,"));
        }
        System.IO.File.WriteAllLines(Application.dataPath + "/../Logs/clip/overlay.ass", head.ToArray());
    }

    // One step of the overnight clip.  Returns false when it has finished.
    static bool NightStep(DozerController d, float t)
    {
        var wk = Worker.Instance; var w = VoxelWorld.Instance; var finds = Finds.Instance; var cart = MineCart.Instance; var sg = SaveGame.Instance;
        if (finds == null || cart == null || sg == null) return true;
        string save = SaveGame.FilePath, keep = SaveGame.FilePath + ".clipkeep";
        if (nPhase == 0)
        {
            if (System.IO.File.Exists(save)) System.IO.File.Copy(save, keep, true);     // the owner's own save is put back afterwards
            if (wk.InDozer) wk.GetOut();
            wk.Teleport(finds.Spot[0] + new Vector3(0.9f, 0f, -2.6f), -18f);   // off to one side, so he does not hide the part
            wk.Look(22f);
            wk.SetTool(0);
            nPhase = 1; nT0 = t; nNext = t; nStep = 0; NightMark("dig");
        }
        if (nPhase >= 1 && nPhase <= 2) { if (finds.GlintShowing(0)) nGlint++; if (finds.Visible(0)) nVisible++; nCheck++; }
        if (nPhase == 1)
        {
            // he swings at the rubble while it is cleared from round the part; each load is thrown out of the mine
            wk.overrideUse = true;
            if (t - nT0 > 3f && wk.Tool != 1) wk.SetTool(1);
            if (finds.Exposed(0) || t - nT0 > 30f) { wk.overrideUse = false; nPhase = 2; nT0 = t; NightMark("exposed"); }
            else if (t >= nNext)
            {
                nNext = t + 0.05f;
                Vector3 c = finds.Spot[0];
                int n = nStep++;
                Vector3 at = c + new Vector3(-0.45f + ((n / 7) % 4) * 0.3f, 0.6f + (n % 7) * 0.3f, -1.5f + ((n / 28) % 6) * 0.35f);
                w.Pick(at, 0.3f, Vector3.zero);
                w.Scoop(at, 0.55f, 4000);
                if (w.ShovelVoxels >= VoxelWorld.ClodVoxels)
                    w.Throw(new Vector3(VoxelWorld.PortalX + 5f, 2f, VoxelWorld.PortalZ - 9f), Vector3.zero, 1f, 0.2f);
            }
        }
        else if (nPhase == 2)
        {
            // walk up to it and look down at it, then pick it up
            if (t - nT0 < 0.1f) { wk.Teleport(finds.Spot[0] + new Vector3(0f, 0f, -1.4f), 0f); wk.SetEyes(true); wk.Look(40f); }
            if (t - nT0 > 3.5f)
            {
                wk.SetEyes(false); wk.Look(14f);
                wk.Teleport(finds.Spot[0] + new Vector3(0f, 0f, -1.1f), 0f);
                nMarks += " workerAt=" + wk.transform.position.ToString("F2") + " spot=" + finds.Spot[0].ToString("F2") + " exposedNow=" + finds.Exposed(0) + " found=" + finds.Found[0] + " use=[" + wk.UsePart() + "]";
                NightMark("pickedUp"); nPhase = 3; nT0 = t;
            }
        }
        else if (nPhase == 3)
        {
            if (t - nT0 < 1.5f) return true;
            // the dozer, dead: full throttle and it does not move
            d.dead = true;
            wk.GetIn();
            d.useOverride = true; d.overrideThrottle = 1f; d.overrideBlade = 0f;
            nPhase = 4; nT0 = t; NightMark("dead");
        }
        else if (nPhase == 4)
        {
            if (t - nT0 < 3.5f) return true;
            d.overrideThrottle = 0f;
            wk.GetOut();
            nMarks += " fit=[" + wk.UsePart() + "] canDrive=" + d.CanDrive;         // fit the tracks part
            wk.GetIn();
            d.overrideThrottle = 1f; d.overrideSteer = 0.35f;
            nPhase = 5; nT0 = t; NightMark("fitted");
        }
        else if (nPhase == 5)
        {
            if (t - nT0 < 5f) return true;
            d.overrideThrottle = 0f; d.overrideSteer = 0f;
            d.dead = false;
            // the cart, by the mine entrance: dig beside it and throw each shovelful in
            wk.GetOut();
            wk.SetTool(1);
            wk.Teleport(cart.transform.position + cart.transform.right * 3.4f - cart.transform.forward * 1.2f, Facing(-cart.transform.right) - 25f);
            wk.Look(18f);
            nPhase = 6; nT0 = t; nNext = t; nStep = 0; NightMark("cart");
        }
        else if (nPhase == 6)
        {
            wk.overrideUse = true;
            if (w.CartVoxels >= 2600 || t - nT0 > 9f) { wk.overrideUse = false; nPhase = 7; nT0 = t; }
            else if (t >= nNext)
            {
                nNext = t + 0.12f;
                Vector3 at = cart.transform.position + cart.transform.right * 2.4f + cart.transform.forward * (-1f + (nStep % 9) * 0.25f) + Vector3.up * (0.1f - (nStep / 9) * 0.12f);
                nStep++;
                w.Pick(at, 0.35f, Vector3.zero);
                w.Scoop(at, 0.5f, 4000);
                if (w.ShovelVoxels >= VoxelWorld.ClodVoxels) w.Throw(cart.Mouth + Vector3.up * 0.7f, Vector3.zero, 0.25f, 0.4f);
            }
        }
        else if (nPhase == 7)
        {
            if (t - nT0 < 1.5f) return true;
            cart.Tip();
            nPhase = 8; nT0 = t; NightMark("tip");
        }
        else if (nPhase == 8)
        {
            if (t - nT0 < 5f) return true;
            // save, dig a fresh cut, then load: the cut is gone and everything is back where it was saved
            wk.GetIn();
            d.overrideThrottle = 0f; d.overrideBlade = -1f;
            nPhase = 9; nT0 = t;
        }
        else if (nPhase == 9)
        {
            if (t - nT0 < 1.2f) return true;
            sg.Save();
            d.overrideThrottle = 1f; d.overrideSteer = -0.3f;
            nPhase = 10; nT0 = t; NightMark("saved");
        }
        else if (nPhase == 10)
        {
            if (t - nT0 < 4.5f) return true;
            d.overrideThrottle = 0f; d.overrideSteer = 0f;
            nPhase = 11; nT0 = t; NightMark("beforeLoad");
        }
        else if (nPhase == 11)
        {
            if (t - nT0 < 1.2f) return true;
            sg.Load();
            d.overrideBlade = 0f;
            nPhase = 12; nT0 = t; NightMark("loaded");
        }
        else if (nPhase == 12)
        {
            if (t - nT0 < 3f) return true;
            if (System.IO.File.Exists(keep)) { System.IO.File.Copy(keep, save, true); System.IO.File.Delete(keep); }
            else if (System.IO.File.Exists(save)) System.IO.File.Delete(save);
            Debug.Log("BULLDOZER_NIGHT_OK frames=" + clipFrame + nMarks + " glintFrames=" + nGlint + " visibleFrames=" + nVisible + "/" + nCheck + " partCarried=" + finds.Carrying(0) + " installed0=" + finds.Installed[0]
                + " cartLeft=" + w.CartVoxels);
            ClipFinish(0);
            return false;
        }
        return true;
    }

    static void ClipFinish(int code)
    {
        EditorApplication.update -= ClipTick;
        Time.captureFramerate = 0;
        EditorSettings.enterPlayModeOptionsEnabled = false;
        EditorApplication.Exit(code);
    }

    static void MakeSpot(Transform parent, Vector3 pos, Vector3 euler, bool shadows)
    {
        var go = new GameObject("Work light");
        go.transform.SetParent(parent, false);
        go.transform.localPosition = pos;
        go.transform.localRotation = Quaternion.Euler(euler);
        var l = go.AddComponent<Light>();
        l.type = LightType.Spot;
        l.color = new Color(1f, 0.93f, 0.78f);
        l.intensity = 3.2f;
        l.range = 32f;
        l.spotAngle = 78f;
        l.shadows = shadows ? LightShadows.Soft : LightShadows.None;
        l.renderMode = LightRenderMode.ForcePixel;
    }

    // Bloom on bright things, soft shading in corners and crevices, film-style tone mapping and a slight warm grade.
    static void SetUpPostProcessing(Camera cam)
    {
        if (cam == null) return;
        cam.allowHDR = true;
        cam.allowMSAA = false;
        var layer = cam.gameObject.AddComponent<PostProcessLayer>();
        string[] found = AssetDatabase.FindAssets("t:PostProcessResources");
        if (found.Length == 0) { Debug.LogError("BULLDOZER_BUILD_FAILED post-processing resources not found"); return; }
        layer.Init(AssetDatabase.LoadAssetAtPath<PostProcessResources>(AssetDatabase.GUIDToAssetPath(found[0])));
        layer.volumeLayer = 1;                                                 // the Default layer
        layer.volumeTrigger = cam.transform;
        layer.antialiasingMode = PostProcessLayer.Antialiasing.SubpixelMorphologicalAntialiasing;

        const string path = Dir + "/DemoLook.asset";
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
        grade.saturation.Override(-6f);
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

    static void MakeBox(Transform parent, Material mat, Vector3 pos, Vector3 size)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
        go.name = "Fence";
        go.transform.SetParent(parent, false);
        go.transform.position = pos;
        go.transform.localScale = size;
        go.GetComponent<MeshRenderer>().sharedMaterial = mat;
        UnityEngine.Object.DestroyImmediate(go.GetComponent<Collider>());
    }

    static void MakeGroundPlane(Transform parent, Material mat, float x0, float x1, float z0, float z1)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Plane);                 // a plane is 10 x 10
        go.name = "Ground";
        go.transform.SetParent(parent, false);
        go.transform.position = new Vector3((x0 + x1) * 0.5f, 0f, (z0 + z1) * 0.5f);
        go.transform.localScale = new Vector3((x1 - x0) / 10f, 1f, (z1 - z0) / 10f);
        go.GetComponent<MeshRenderer>().sharedMaterial = mat;
    }

    static void MakeProp(Transform parent, Material mat, Vector3 pos, float size, float turn)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
        go.name = "Loose";
        go.transform.SetParent(parent, false);
        go.transform.position = pos;
        go.transform.rotation = Quaternion.Euler(0f, turn, 0f);
        go.transform.localScale = Vector3.one * size;
        go.GetComponent<MeshRenderer>().sharedMaterial = mat;
        go.AddComponent<Rigidbody>().mass = 600f * size * size * size;
    }

    // blocky dusty ground, so you can see the machine moving over it
    static Texture2D MakeGroundTexture()
    {
        const string path = Dir + "/DemoGroundTex.asset";
        AssetDatabase.DeleteAsset(path);
        var tex = new Texture2D(64, 64, TextureFormat.RGB24, false);
        tex.filterMode = FilterMode.Point;
        tex.wrapMode = TextureWrapMode.Repeat;
        var rng = new System.Random(3);
        for (int y = 0; y < 64; y++)
            for (int x = 0; x < 64; x++)
            {
                float v = 0.86f + (float)rng.NextDouble() * 0.2f;
                if (rng.Next(40) == 0) v *= 0.8f;                       // the odd darker stone
                tex.SetPixel(x, y, new Color(0.74f * v, 0.60f * v, 0.42f * v));
            }
        tex.Apply();
        AssetDatabase.CreateAsset(tex, path);
        return tex;
    }

    static Material MakeMaterial(string path, Shader shader, Texture2D tex, Color colour)
    {
        var mat = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (mat == null) { mat = new Material(shader); AssetDatabase.CreateAsset(mat, path); }
        mat.shader = shader;
        if (tex != null) { mat.mainTexture = tex; if (mat.HasProperty("_BaseMap")) mat.SetTexture("_BaseMap", tex); }
        mat.color = colour;
        if (mat.HasProperty("_BaseColor")) mat.SetColor("_BaseColor", colour);
        if (mat.HasProperty("_Glossiness")) mat.SetFloat("_Glossiness", 0.15f);
        if (mat.HasProperty("_Smoothness")) mat.SetFloat("_Smoothness", 0.15f);
        EditorUtility.SetDirty(mat);
        return mat;
    }
}
'''


CAMERA_CS = r'''// Generated by make_unity_export.py.  Chase camera: follows behind the target and swings round with it.
// Hold the right mouse button and drag to look round; scroll to zoom.
using UnityEngine;

public class FollowCamera : MonoBehaviour
{
    public Transform target;
    public float distance = 13f;
    public float lookHeight = 1.8f;
    public float pitch = 22f;
    public float yawOffset = 25f;            // a little to one side, so the blade is in view
    public float turnFollow = 2f;

    float heading;

    void Start() { if (target != null) heading = target.eulerAngles.y; }

    void LateUpdate()
    {
        if (target == null) return;
        if (Input.GetMouseButton(1))
        {
            yawOffset += Input.GetAxis("Mouse X") * 4f;
            pitch = Mathf.Clamp(pitch - Input.GetAxis("Mouse Y") * 3f, 5f, 75f);
        }
        distance = Mathf.Clamp(distance * (1f - Input.GetAxis("Mouse ScrollWheel")), 6f, 40f);
        heading = Mathf.LerpAngle(heading, target.eulerAngles.y, turnFollow * Time.deltaTime);

        Vector3 focus = target.position + Vector3.up * lookHeight;
        Quaternion rot = Quaternion.Euler(pitch, heading + yawOffset, 0f);
        transform.position = focus - rot * Vector3.forward * distance;
        transform.rotation = rot;
    }
}
'''


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    base = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "unity-export")
    out = os.path.join(base, "Bulldozer")
    os.makedirs(os.path.join(out, "Models"), exist_ok=True)
    os.makedirs(os.path.join(out, "Editor"), exist_ok=True)
    os.makedirs(os.path.join(out, "Scripts"), exist_ok=True)

    parts = {p.name: p for p in dozer.build_all()}       # clean machine
    for side in ("track_left", "track_right"):
        frame, sprocket, idler = split_track(parts[side], side)
        parts[frame.name] = frame
        if side == "track_left":                          # both sides are the same shape, so one mesh each
            # (taken from the left track, because the left nodes come first and set the mesh's pivot)
            parts["track_sprocket"], parts["track_idler"] = sprocket, idler
    parts["track_pad"] = make_pad()
    for old in ("track_left.obj", "track_right.obj"):     # from before the tracks were split up
        for stale in (old, old + ".meta"):
            if os.path.exists(os.path.join(out, "Models", stale)):
                os.remove(os.path.join(out, "Models", stale))

    total = 0
    written = set()
    for name, mesh, parent, pivot in NODES:
        if mesh and mesh not in written:
            written.add(mesh)
            if mesh == "track_pad":
                pivot = PAD_PIVOT                         # the pad is modelled in its own little grid
            n = write_obj(os.path.join(out, "Models", mesh + ".obj"), parts[mesh], pivot)
            total += n
            print("  %-12s %6d faces" % (mesh, n))

    # palette strip
    width, height = PAL_CELLS * PAL_CELL_PX, PAL_CELL_PX
    row = bytearray()
    for i in range(PAL_CELLS):
        row += bytes(dozer.PALETTE.get(i, (255, 0, 255))) * PAL_CELL_PX
    dozer._write_png(os.path.join(out, "bulldozer_palette.png"), width, height, bytearray(bytes(row) * height))

    nodes = [{"name": n, "mesh": m, "parent": p, "pos": [round(v, 5) for v in to_unity(*piv)]}
             for n, m, p, piv in NODES]
    with open(os.path.join(out, "bulldozer_parts.json"), "w") as f:
        json.dump({"voxelSize": VOXEL, "nodes": nodes}, f, indent=2)
    with open(os.path.join(out, "Editor", "BulldozerBuilder.cs"), "w", newline="\n") as f:
        f.write(BUILDER_CS)
    src = os.path.join(here, "unity-src")                 # hand-written scripts and shaders
    for name in sorted(os.listdir(src)):
        shutil.copyfile(os.path.join(src, name), os.path.join(out, "Scripts", name))
    # (FollowCamera.cs now lives in unity-src with the other hand-written scripts)

    size = [dozer.W * VOXEL, dozer.H * VOXEL, dozer.L * VOXEL]
    print("Wrote %s  (%d faces; machine is %.2f m wide, %.2f m tall, %.2f m long)" % (out, total, *size))


if __name__ == "__main__":
    main()
