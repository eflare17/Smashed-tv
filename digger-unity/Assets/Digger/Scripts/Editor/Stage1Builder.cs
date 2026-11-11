using System;
using System.IO;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;
using Object = UnityEngine.Object;

namespace Digger.EditorTools
{
    /// <summary>
    /// Builds the Stage 1 test yard: a deformable dirt yard, a placeholder 1990s dozer on
    /// articulation-body joints, cameras (chase, cab, blade cam), dust, HDRP sun, shadows
    /// and ambient occlusion. Run it from an HDRP scene that already has a sun and sky
    /// (the template's SampleScene is ideal): it copies that scene's lighting.
    /// Menu: Digger > Build Stage 1 Test Yard.
    /// </summary>
    public static class Stage1Builder
    {
        const string Root = "Assets/Digger";
        const string Gen = Root + "/Generated";
        const string TexDir = Gen + "/Textures";
        const string ScenePath = Root + "/Scenes/Stage1_TestYard.unity";
        const string RootName = "Digger Stage 1";
        const float YardSize = 64f, YardHeight = 16f, YardBase = 4f;   // ground level y=0 is YardBase above the terrain's bottom
        const int HeightRes = 257, AlphaRes = 256;

        [MenuItem("Digger/Build Stage 1 Test Yard", priority = 1)]
        public static void Build()
        {
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
            if (!IsHdrp())
                Debug.LogWarning("Digger: this project isn't using HDRP. The yard will still build, but the brief calls for an HDRP project (High Definition 3D template).");

            EnsureFolder(Root, "Scenes"); EnsureFolder(Root, "Generated"); EnsureFolder(Gen, "Textures");

            var scene = PrepareScene();
            var root = new GameObject(RootName);

            try
            {
                EditorUtility.DisplayProgressBar("Digger", "Textures and materials", 0.1f);
                var mats = new Mats();

                EditorUtility.DisplayProgressBar("Digger", "Test yard", 0.3f);
                var terrain = BuildYard(root.transform, mats);
                var ground = terrain.gameObject.AddComponent<DeformableGround>();

                EditorUtility.DisplayProgressBar("Digger", "Dozer", 0.55f);
                var spawn = new Vector3(0f, YardHeightAt(0f, -15f) + 0.04f, -15f);
                var rig = BuildDozer(root.transform, mats, spawn, ground);

                EditorUtility.DisplayProgressBar("Digger", "Cameras and lighting", 0.8f);
                BuildCamerasAndHud(root.transform, rig);
                SetupLighting(root.transform);

                EditorSceneManager.MarkSceneDirty(scene);
                EditorSceneManager.SaveScene(scene, ScenePath);
                AddToBuildSettings();
                Selection.activeGameObject = rig.dozer.gameObject;
                Debug.Log("Digger: Stage 1 test yard built and saved to " + ScenePath + ". Press Play.");
            }
            finally
            {
                EditorUtility.ClearProgressBar();
            }
        }

        // ------------------------------------------------------------------ scene

        static Scene PrepareScene()
        {
            var scene = SceneManager.GetActiveScene();
            if (scene.path == ScenePath)
            {
                var old = scene.GetRootGameObjects().FirstOrDefault(g => g.name == RootName);
                if (old) Object.DestroyImmediate(old);
                return scene;
            }
            bool hasSun = Object.FindObjectsByType<Light>(FindObjectsSortMode.None).Any(l => l.type == LightType.Directional);
            if (hasSun)
            {
                // Copy the open scene so its HDRP sun, sky and fog come along, then hide its contents.
                EditorSceneManager.SaveScene(scene, ScenePath, true);
                scene = EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
                foreach (var go in scene.GetRootGameObjects())
                {
                    if (go.name == RootName) { Object.DestroyImmediate(go); continue; }
                    if (!KeepForLighting(go)) go.SetActive(false);
                }
                return scene;
            }
            return EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        }

        static bool KeepForLighting(GameObject go)
        {
            if (go.GetComponentsInChildren<Camera>(true).Length > 0) return false;
            if (go.GetComponentsInChildren<Light>(true).Length > 0) return true;
            foreach (var c in go.GetComponentsInChildren<Component>(true))
            {
                if (c == null) continue;
                string n = c.GetType().Name;
                if (n == "Volume" || n.Contains("Probe") || n.Contains("Sky")) return true;
            }
            return false;
        }

        static void AddToBuildSettings()
        {
            var list = EditorBuildSettings.scenes.ToList();
            if (list.Any(s => s.path == ScenePath)) return;
            list.Insert(0, new EditorBuildSettingsScene(ScenePath, true));
            EditorBuildSettings.scenes = list.ToArray();
        }

        static bool IsHdrp()
        {
            var rp = UnityEngine.Rendering.GraphicsSettings.currentRenderPipeline;
            return rp != null && rp.GetType().Name.Contains("HDRenderPipelineAsset");
        }

        static void EnsureFolder(string parent, string name)
        {
            if (!AssetDatabase.IsValidFolder(parent + "/" + name)) AssetDatabase.CreateFolder(parent, name);
        }

        // ------------------------------------------------------------------ materials

        class Mats
        {
            public Material paint, steel, dark, track, edge, seat, lens, rock, log, bark, leaves, grassNS, grassEW, container, dust;

            public Mats()
            {
                var paintTex = Tex("Dozer_Paint", 256, 256, PaintPixel, false);
                var trackTex = Tex("Dozer_Track", 64, 256, TrackPixel, false);
                var puff = Tex("Dust_Puff", 128, 128, PuffPixel, true);
                var grassTex = Tex("Paddock_Grass", 512, 512, (x, y) => GroundPixel(x, y, 512, 2), false);
                var rockTex = Tex("Rock", 256, 256, (x, y) => RockPixel(x, y), false);

                paint = Lit("Dozer Paint", Color.white, paintTex, 0.12f, 0.42f);
                steel = Lit("Dozer Steel", new Color(0.17f, 0.165f, 0.16f), null, 0.55f, 0.45f);
                dark = Lit("Dozer Black", new Color(0.06f, 0.058f, 0.055f), null, 0.2f, 0.3f);
                track = Lit("Dozer Track", Color.white, trackTex, 0.45f, 0.3f);
                track.mainTextureScale = new Vector2(1f, 10f);
                edge = Lit("Dozer Cutting Edge", new Color(0.5f, 0.48f, 0.45f), null, 0.85f, 0.6f);
                seat = Lit("Dozer Seat", new Color(0.09f, 0.085f, 0.08f), null, 0f, 0.2f);
                lens = Lit("Dozer Lens", new Color(1f, 0.97f, 0.88f), null, 0f, 0.9f);
                rock = Lit("Rock", Color.white, rockTex, 0f, 0.25f);
                log = Lit("Log", new Color(0.36f, 0.3f, 0.24f), null, 0f, 0.2f);
                bark = Lit("Tree Bark", new Color(0.62f, 0.6f, 0.55f), null, 0f, 0.2f);
                leaves = Lit("Tree Leaves", new Color(0.22f, 0.27f, 0.14f), null, 0f, 0.15f);
                grassNS = Lit("Paddock Grass NS", Color.white, grassTex, 0f, 0.1f);
                grassNS.mainTextureScale = new Vector2(60f, 25.2f);
                grassEW = Lit("Paddock Grass EW", Color.white, grassTex, 0f, 0.1f);
                grassEW.mainTextureScale = new Vector2(25.2f, 9.6f);
                container = Lit("Shipping Container", new Color(0.45f, 0.17f, 0.1f), null, 0.4f, 0.35f);
                dust = DustMaterial(puff);
            }
        }

        static Material Lit(string name, Color color, Texture2D tex, float metallic, float smoothness)
        {
            var shader = Shader.Find("HDRP/Lit");
            bool hd = shader != null;
            if (!hd) shader = Shader.Find("Standard");
            var m = new Material(shader) { name = name };
            if (hd)
            {
                m.SetColor("_BaseColor", color);
                if (tex) m.SetTexture("_BaseColorMap", tex);
                m.SetFloat("_Metallic", metallic);
                m.SetFloat("_Smoothness", smoothness);
            }
            else
            {
                m.color = color;
                if (tex) m.mainTexture = tex;
                m.SetFloat("_Metallic", metallic);
                m.SetFloat("_Glossiness", smoothness);
            }
            ValidateHdrpMaterial(m);
            return SaveAsset(m, Gen + "/" + name + ".mat");
        }

        static Material DustMaterial(Texture2D puff)
        {
            var shader = Shader.Find("Digger/Dust");
            Material m;
            if (shader != null && shader.isSupported)
            {
                m = new Material(shader) { name = "Dust" };
                m.SetTexture("_MainTex", puff);
            }
            else
            {
                Debug.LogWarning("Digger: dust shader not supported here, using HDRP/Unlit for dust.");
                m = new Material(Shader.Find("HDRP/Unlit") ?? Shader.Find("Unlit/Transparent")) { name = "Dust" };
                m.mainTexture = puff;
                ValidateHdrpMaterial(m);
            }
            return SaveAsset(m, Gen + "/Dust.mat");
        }

        /// <summary>Lets HDRP set the keywords for the properties we filled in (HDMaterial.ValidateMaterial).</summary>
        static void ValidateHdrpMaterial(Material m)
        {
            var t = FindType("UnityEngine.Rendering.HighDefinition.HDMaterial");
            var validate = t != null ? t.GetMethod("ValidateMaterial", BindingFlags.Public | BindingFlags.Static, null, new[] { typeof(Material) }, null) : null;
            if (validate == null) return;
            try { validate.Invoke(null, new object[] { m }); }
            catch (Exception e) { Debug.LogWarning("Digger: HDRP material validation failed for " + m.name + ": " + e.Message); }
        }

        static T SaveAsset<T>(T asset, string path) where T : Object
        {
            if (AssetDatabase.LoadAssetAtPath<Object>(path) != null) AssetDatabase.DeleteAsset(path);
            AssetDatabase.CreateAsset(asset, path);
            return asset;
        }

        // ------------------------------------------------------------------ procedural textures

        static Texture2D Tex(string name, int w, int h, Func<int, int, Color> pixel, bool alpha)
        {
            var t = new Texture2D(w, h, TextureFormat.RGBA32, false);
            var px = new Color[w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    px[y * w + x] = pixel(x, y);
            t.SetPixels(px);
            t.Apply();
            string path = TexDir + "/" + name + ".png";
            File.WriteAllBytes(Path.Combine(Directory.GetCurrentDirectory(), path), t.EncodeToPNG());
            Object.DestroyImmediate(t);
            AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
            var importer = (TextureImporter)AssetImporter.GetAtPath(path);
            importer.wrapMode = alpha ? TextureWrapMode.Clamp : TextureWrapMode.Repeat;
            importer.alphaIsTransparency = alpha;
            importer.sRGBTexture = true;
            importer.mipmapEnabled = true;
            importer.anisoLevel = 4;
            importer.SaveAndReimport();
            return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }

        static float Hash(int x, int y, int seed)
        {
            unchecked
            {
                int h = x * 374761393 + y * 668265263 + seed * 1442695041;
                h = (h ^ (h >> 13)) * 1274126177;
                h ^= h >> 16;
                return (h & 0x7fffffff) / 2147483647f;
            }
        }

        /// <summary>Value noise that tiles every <paramref name="period"/> cells.</summary>
        static float Noise(float x, float y, int period, int seed)
        {
            int xi = Mathf.FloorToInt(x), yi = Mathf.FloorToInt(y);
            float xf = x - xi, yf = y - yi;
            float u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
            int x0 = Mod(xi, period), x1 = Mod(xi + 1, period), y0 = Mod(yi, period), y1 = Mod(yi + 1, period);
            float a = Hash(x0, y0, seed), b = Hash(x1, y0, seed), c = Hash(x0, y1, seed), d = Hash(x1, y1, seed);
            return Mathf.Lerp(Mathf.Lerp(a, b, u), Mathf.Lerp(c, d, u), v);
        }

        static int Mod(int a, int m) { int r = a % m; return r < 0 ? r + m : r; }

        static float Fbm(float x, float y, int period, int seed, int octaves)
        {
            float s = 0, amp = 0.5f, total = 0;
            for (int i = 0; i < octaves; i++)
            {
                s += amp * Noise(x, y, period, seed + i * 17);
                total += amp;
                x *= 2; y *= 2; period *= 2; amp *= 0.5f;
            }
            return s / total;
        }

        static Color GroundPixel(int x, int y, int size, int kind)
        {
            float fx = x * 16f / size, fy = y * 16f / size;
            float n = Fbm(fx, fy, 16, 11 + kind, 5);
            float fine = Noise(x * 0.5f, y * 0.5f, size / 2, 5 + kind);
            float pebble = Hash(x / 3, y / 3, 3 + kind) > 0.965f ? 1f : 0f;
            Color c;
            if (kind == 0)        // dry yard dirt: grey-brown
                c = Color.Lerp(new Color(0.36f, 0.3f, 0.23f), new Color(0.52f, 0.45f, 0.35f), n);
            else if (kind == 1)   // fresh-cut soil: darker, redder, moist
                c = Color.Lerp(new Color(0.24f, 0.16f, 0.1f), new Color(0.4f, 0.27f, 0.17f), n);
            else                  // dry grass with green patches
                c = Color.Lerp(new Color(0.4f, 0.39f, 0.22f), new Color(0.24f, 0.31f, 0.13f), Mathf.SmoothStep(0.35f, 0.7f, n));
            c *= 0.86f + 0.28f * fine;
            if (pebble > 0 && kind != 2) c = Color.Lerp(c, Hash(x, y, 9) > 0.5f ? new Color(0.62f, 0.58f, 0.52f) : new Color(0.2f, 0.18f, 0.16f), 0.7f);
            c.a = 1f;
            return c;
        }

        static Color PaintPixel(int x, int y)
        {
            float n = Fbm(x / 32f, y / 32f, 8, 21, 4);
            var c = Color.Lerp(new Color(0.62f, 0.44f, 0.1f), new Color(0.82f, 0.62f, 0.2f), n);
            float grime = Mathf.SmoothStep(0.55f, 0.85f, Fbm(x / 20f, y / 20f, 13, 23, 3));
            c = Color.Lerp(c, new Color(0.3f, 0.24f, 0.16f), grime * 0.5f);
            float streak = Hash(x / 3, 0, 31) > 0.93f ? Mathf.Clamp01((y % 128) / 128f) * 0.5f : 0f;
            c = Color.Lerp(c, new Color(0.4f, 0.2f, 0.08f), streak);
            float mud = Mathf.SmoothStep(80f, 0f, y);
            c = Color.Lerp(c, new Color(0.36f, 0.27f, 0.18f), mud * 0.6f);
            c.a = 1f;
            return c;
        }

        static Color TrackPixel(int x, int y)
        {
            int k = y % 32;
            var c = k < 9 ? new Color(0.27f, 0.25f, 0.23f) : k < 12 ? new Color(0.06f, 0.06f, 0.055f) : new Color(0.15f, 0.14f, 0.13f);
            c = Color.Lerp(c, new Color(0.3f, 0.23f, 0.15f), Noise(x / 6f, y / 6f, 64, 41) * 0.45f);
            c.a = 1f;
            return c;
        }

        static Color RockPixel(int x, int y)
        {
            float n = Fbm(x / 32f, y / 32f, 8, 51, 5);
            var c = Color.Lerp(new Color(0.33f, 0.32f, 0.3f), new Color(0.56f, 0.53f, 0.48f), n);
            c.a = 1f;
            return c;
        }

        static Color PuffPixel(int x, int y)
        {
            float dx = (x - 63.5f) / 63.5f, dy = (y - 63.5f) / 63.5f;
            float r = Mathf.Sqrt(dx * dx + dy * dy);
            float n = Fbm(x / 16f, y / 16f, 8, 61, 4);
            float a = Mathf.Clamp01(1f - r);
            a = Mathf.Clamp01(Mathf.Pow(a, 1.3f) * (0.55f + 0.8f * n) * 1.2f - 0.06f);
            return new Color(1f, 1f, 1f, a);
        }

        // ------------------------------------------------------------------ yard

        /// <summary>Ground height (m, ground level 0) of the yard as built.</summary>
        static float YardHeightAt(float x, float z)
        {
            float y = 0.06f * (Fbm(x * 0.08f + 50, z * 0.08f + 50, 1024, 71, 4) - 0.5f) * 2f;
            y += Mound(x, z, 2f, 3f, 4.5f, 1.6f);       // pile straight ahead of the dozer
            y += Mound(x, z, -13f, 10f, 5.5f, 2.3f);
            y += Mound(x, z, 13f, -6f, 3.5f, 1.2f);
            y -= Mound(x, z, -12f, -12f, 4f, 0.9f);     // shallow pit
            y += Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(17f, 27f, z)) * 3f;   // bank to cut a bench into
            float edge = Mathf.Min(YardSize * 0.5f - Mathf.Abs(x), YardSize * 0.5f - Mathf.Abs(z));
            return y * Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(0.5f, 5f, edge));
        }

        static float Mound(float x, float z, float cx, float cz, float radius, float height)
        {
            float d = Mathf.Sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz)) / radius;
            if (d >= 1f) return 0f;
            float t = 1f - d * d;
            return height * t * t;
        }

        static Terrain BuildYard(Transform root, Mats mats)
        {
            var dirt = Layer("Dirt", (x, y) => GroundPixel(x, y, 512, 0), 4f);
            var fresh = Layer("Fresh Soil", (x, y) => GroundPixel(x, y, 512, 1), 3f);
            var grassL = Layer("Grass", (x, y) => GroundPixel(x, y, 512, 2), 6f);

            var data = new TerrainData();
            data.heightmapResolution = HeightRes;
            data.size = new Vector3(YardSize, YardHeight, YardSize);
            data.alphamapResolution = AlphaRes;
            data.baseMapResolution = 512;
            data.terrainLayers = new[] { dirt, fresh, grassL };

            var heights = new float[HeightRes, HeightRes];
            float cell = YardSize / (HeightRes - 1);
            for (int z = 0; z < HeightRes; z++)
                for (int x = 0; x < HeightRes; x++)
                {
                    float wx = -YardSize * 0.5f + x * cell, wz = -YardSize * 0.5f + z * cell;
                    heights[z, x] = Mathf.Clamp01((YardHeightAt(wx, wz) + YardBase) / YardHeight);
                }
            data.SetHeights(0, 0, heights);

            var alpha = new float[AlphaRes, AlphaRes, 3];
            for (int z = 0; z < AlphaRes; z++)
                for (int x = 0; x < AlphaRes; x++)
                {
                    float wx = -YardSize * 0.5f + (x + 0.5f) * YardSize / AlphaRes, wz = -YardSize * 0.5f + (z + 0.5f) * YardSize / AlphaRes;
                    float edge = Mathf.Min(YardSize * 0.5f - Mathf.Abs(wx), YardSize * 0.5f - Mathf.Abs(wz));
                    float g = 1f - Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(3f, 7f + 2f * Fbm(wx * 0.2f + 9, wz * 0.2f, 1024, 81, 3), edge));
                    float onPile = Mathf.Clamp01(YardHeightAt(wx, wz) - 0.4f) * 0.35f;
                    alpha[z, x, 2] = g;
                    alpha[z, x, 1] = (1f - g) * onPile;
                    alpha[z, x, 0] = (1f - g) * (1f - onPile);
                }
            data.SetAlphamaps(0, 0, alpha);
            SaveAsset(data, Gen + "/Stage1 Yard.asset");

            var go = Terrain.CreateTerrainGameObject(data);
            go.name = "Yard (deformable)";
            go.transform.SetParent(root, false);
            go.transform.position = new Vector3(-YardSize * 0.5f, -YardBase, -YardSize * 0.5f);
            var terrain = go.GetComponent<Terrain>();
            terrain.heightmapPixelError = 2f;
            terrain.basemapDistance = 400f;
            terrain.drawInstanced = true;
            var terrainMat = TerrainMaterial();
            if (terrainMat) terrain.materialTemplate = terrainMat;

            // Paddock around the yard so it isn't an island. Four strips, none under the yard,
            // so digging below ground level never meets an invisible floor.
            float half = YardSize * 0.5f, outer = 200f, band = outer - half;
            var paddock = new GameObject("Paddock").transform;
            paddock.SetParent(root, false);
            Prim(PrimitiveType.Cube, "Paddock N", paddock, new Vector3(0f, -0.13f, half + band * 0.5f), new Vector3(outer * 2f, 0.2f, band), mats.grassNS, Vector3.zero, true);
            Prim(PrimitiveType.Cube, "Paddock S", paddock, new Vector3(0f, -0.13f, -half - band * 0.5f), new Vector3(outer * 2f, 0.2f, band), mats.grassNS, Vector3.zero, true);
            Prim(PrimitiveType.Cube, "Paddock E", paddock, new Vector3(half + band * 0.5f, -0.13f, 0f), new Vector3(band, 0.2f, YardSize), mats.grassEW, Vector3.zero, true);
            Prim(PrimitiveType.Cube, "Paddock W", paddock, new Vector3(-half - band * 0.5f, -0.13f, 0f), new Vector3(band, 0.2f, YardSize), mats.grassEW, Vector3.zero, true);
            paddock.gameObject.isStatic = true;

            BuildTrees(root, mats);
            BuildProps(root, mats);
            return terrain;
        }

        /// <summary>The pipeline's terrain material (HDRP/TerrainLit), so the yard doesn't render pink.</summary>
        static Material TerrainMaterial()
        {
            var rp = UnityEngine.Rendering.GraphicsSettings.currentRenderPipeline;
            Material mat = null;
            if (rp != null)
            {
                var prop = rp.GetType().GetProperty("defaultTerrainMaterial", BindingFlags.Public | BindingFlags.Instance);
                if (prop != null) { try { mat = prop.GetValue(rp, null) as Material; } catch (Exception) { } }
            }
            if (mat == null)
            {
                var shader = Shader.Find("HDRP/TerrainLit");
                if (shader != null) mat = SaveAsset(new Material(shader) { name = "Yard Terrain" }, Gen + "/Yard Terrain.mat");
            }
            return mat;
        }

        static TerrainLayer Layer(string name, Func<int, int, Color> pixel, float tile)
        {
            var tex = Tex("Ground_" + name.Replace(" ", ""), 512, 512, pixel, false);
            var l = new TerrainLayer { diffuseTexture = tex, tileSize = new Vector2(tile, tile), smoothness = 0.05f, metallic = 0f };
            return SaveAsset(l, Gen + "/Layer " + name + ".terrainlayer");
        }

        static void BuildTrees(Transform root, Mats mats)
        {
            var group = new GameObject("Tree Line").transform;
            group.SetParent(root, false);
            var rng = new System.Random(1998);
            for (int i = 0; i < 70; i++)
            {
                double a = rng.NextDouble() * Math.PI * 2;
                float r = 44f + (float)rng.NextDouble() * 60f;
                var p = new Vector3(Mathf.Cos((float)a) * r, -0.05f, Mathf.Sin((float)a) * r);
                float height = 16f + (float)rng.NextDouble() * 14f;
                float rad = 0.25f + (float)rng.NextDouble() * 0.25f;
                var tree = new GameObject("Tree").transform;
                tree.SetParent(group, false);
                tree.localPosition = p;
                Prim(PrimitiveType.Cylinder, "Trunk", tree, new Vector3(0f, height * 0.5f, 0f), new Vector3(rad * 2f, height * 0.5f, rad * 2f), mats.bark, Vector3.zero, false);
                for (int k = 0; k < 3; k++)
                {
                    var off = new Vector3(((float)rng.NextDouble() - 0.5f) * 3f, height * (0.8f + 0.12f * k), ((float)rng.NextDouble() - 0.5f) * 3f);
                    float s = 3f + (float)rng.NextDouble() * 2.5f;
                    Prim(PrimitiveType.Sphere, "Crown", tree, off, new Vector3(s, s * 0.6f, s), mats.leaves, Vector3.zero, false);
                }
                tree.gameObject.isStatic = true;
            }
        }

        static void BuildProps(Transform root, Mats mats)
        {
            var group = new GameObject("Props").transform;
            group.SetParent(root, false);
            var rng = new System.Random(7);
            Vector3[] rocks = { new Vector3(-5, 0, -4), new Vector3(7, 0, -9), new Vector3(-17, 0, -3), new Vector3(16, 0, 9), new Vector3(-2, 0, 14), new Vector3(10, 0, 3), new Vector3(-8, 0, 20) };
            foreach (var p in rocks)
            {
                float s = 0.6f + (float)rng.NextDouble() * 0.7f;
                var scale = new Vector3(s * 1.25f, s * 0.8f, s);
                var pos = new Vector3(p.x, YardHeightAt(p.x, p.z) + scale.y * 0.5f + 0.05f, p.z);
                var rock = Prim(PrimitiveType.Sphere, "Rock", group, pos, scale, mats.rock, new Vector3(0f, (float)rng.NextDouble() * 360f, 0f), false);
                var mc = rock.AddComponent<MeshCollider>();
                mc.convex = true;
                var rb = rock.AddComponent<Rigidbody>();
                rb.mass = 2600f * (4f / 3f) * Mathf.PI * scale.x * scale.y * scale.z * 0.125f;
            }
            Vector3[] logs = { new Vector3(-6, 0, 6), new Vector3(9, 0, 13), new Vector3(-14, 0, -14) };
            foreach (var p in logs)
            {
                var pos = new Vector3(p.x, YardHeightAt(p.x, p.z) + 0.35f, p.z);
                var log = Prim(PrimitiveType.Cylinder, "Log", group, pos, new Vector3(0.5f, 2.6f, 0.5f), mats.log, new Vector3(0f, (float)rng.NextDouble() * 180f, 90f), true);
                var rb = log.AddComponent<Rigidbody>();
                rb.mass = 650f;
            }
            var container = Prim(PrimitiveType.Cube, "Shipping Container", group, new Vector3(23f, 1.3f, 21f), new Vector3(2.44f, 2.6f, 6.06f), mats.container, new Vector3(0f, 25f, 0f), true);
            container.isStatic = true;
        }

        // ------------------------------------------------------------------ dozer

        class DozerRig
        {
            public DozerController dozer;
            public BladeCutter cutter;
            public Transform cabEye, bladeCamMount;
        }

        static DozerRig BuildDozer(Transform root, Mats m, Vector3 spawn, DeformableGround ground)
        {
            var dozerGo = new GameObject("Dozer (1990s, placeholder model)");
            dozerGo.transform.SetParent(root, false);
            dozerGo.transform.position = spawn;
            var t = dozerGo.transform;

            var body = dozerGo.AddComponent<ArticulationBody>();
            body.mass = 14500f;
            body.linearDamping = 0.05f;
            body.angularDamping = 0.3f;

            // Colliders for the hull (the tracks ride on raycast springs, these only stop it sinking into things).
            ColliderBox("Collider Chassis", t, new Vector3(0f, 1.15f, 0f), new Vector3(1.5f, 1.2f, 3.6f));
            ColliderBox("Collider Track L", t, new Vector3(-0.98f, 0.5f, -0.1f), new Vector3(0.58f, 0.7f, 3.2f));
            ColliderBox("Collider Track R", t, new Vector3(0.98f, 0.5f, -0.1f), new Vector3(0.58f, 0.7f, 3.2f));
            ColliderBox("Collider Cab", t, new Vector3(0f, 2.6f, -0.95f), new Vector3(1.5f, 1f, 1.5f));

            var visual = new GameObject("Body").transform;
            visual.SetParent(t, false);

            // Tracks
            Renderer[][] trackRenderers = new Renderer[2][];
            Transform[][] wheels = new Transform[2][];
            for (int s = 0; s < 2; s++)
            {
                float sx = s == 0 ? -0.98f : 0.98f;
                var tg = new GameObject(s == 0 ? "Track L" : "Track R").transform;
                tg.SetParent(visual, false);
                tg.localPosition = new Vector3(sx, 0f, -0.1f);
                Box("Track Frame", tg, new Vector3(0f, 0.47f, 0f), new Vector3(0.54f, 0.76f, 2.36f), m.steel);
                var top = Box("Track Top", tg, new Vector3(0f, 0.9f, 0f), new Vector3(0.58f, 0.09f, 2.36f), m.track);
                var bottom = Box("Track Bottom", tg, new Vector3(0f, 0.045f, 0f), new Vector3(0.58f, 0.09f, 2.36f), m.track);
                var front = Cyl("Track Front", tg, new Vector3(0f, 0.47f, 1.18f), 0.47f, 0.58f, m.track, 'x');
                var back = Cyl("Track Back", tg, new Vector3(0f, 0.47f, -1.18f), 0.47f, 0.58f, m.track, 'x');
                var idler = Cyl("Idler", tg, new Vector3(0f, 0.47f, 1.18f), 0.33f, 0.62f, m.dark, 'x');
                var sprocket = Cyl("Sprocket", tg, new Vector3(0f, 0.47f, -1.18f), 0.33f, 0.62f, m.dark, 'x');
                var spinning = new System.Collections.Generic.List<Transform> { front.transform, back.transform, idler.transform, sprocket.transform };
                for (int i = 0; i < 4; i++)
                    spinning.Add(Cyl("Roller", tg, new Vector3(0f, 0.17f, -0.75f + i * 0.5f), 0.11f, 0.6f, m.dark, 'x').transform);
                trackRenderers[s] = new[] { top.GetComponent<Renderer>(), bottom.GetComponent<Renderer>() };
                wheels[s] = spinning.ToArray();
            }

            // Hull
            Box("Belly", visual, new Vector3(0f, 0.82f, 0.1f), new Vector3(1.3f, 0.55f, 3.5f), m.steel);
            Box("Engine Bay", visual, new Vector3(0f, 1.12f, 0.62f), new Vector3(1.36f, 0.32f, 2f), m.paint);
            Box("Hood", visual, new Vector3(0f, 1.6f, 0.62f), new Vector3(1.24f, 0.84f, 1.95f), m.paint);
            Box("Hood Top", visual, new Vector3(0f, 2.04f, 0.62f), new Vector3(1.12f, 0.07f, 1.9f), m.paint);
            for (int i = 0; i < 4; i++)
            {
                Box("Louvre", visual, new Vector3(-0.627f, 1.62f, 0.1f + i * 0.16f), new Vector3(0.02f, 0.42f, 0.06f), m.dark);
                Box("Louvre", visual, new Vector3(0.627f, 1.62f, 0.1f + i * 0.16f), new Vector3(0.02f, 0.42f, 0.06f), m.dark);
            }
            Box("Grille", visual, new Vector3(0f, 1.55f, 1.62f), new Vector3(1.2f, 0.95f, 0.12f), m.dark);
            for (int i = 0; i < 7; i++) Box("Grille Bar", visual, new Vector3(0f, 1.15f + i * 0.13f, 1.7f), new Vector3(1.14f, 0.035f, 0.05f), m.paint);
            Box("Fender L", visual, new Vector3(-0.98f, 1.01f, -0.8f), new Vector3(0.66f, 0.06f, 1.75f), m.paint);
            Box("Fender R", visual, new Vector3(0.98f, 1.01f, -0.8f), new Vector3(0.66f, 0.06f, 1.75f), m.paint);
            Box("Floor", visual, new Vector3(0f, 1.22f, -0.85f), new Vector3(1.64f, 0.08f, 1.45f), m.steel);
            Box("Dash", visual, new Vector3(0f, 1.5f, -0.22f), new Vector3(1.1f, 0.48f, 0.24f), m.paint);
            Box("Seat", visual, new Vector3(0f, 1.56f, -0.95f), new Vector3(0.56f, 0.13f, 0.5f), m.seat);
            Box("Seat Back", visual, new Vector3(0f, 1.88f, -1.22f), new Vector3(0.56f, 0.62f, 0.1f), m.seat);
            Cyl("Lever L", visual, new Vector3(-0.3f, 1.72f, -0.5f), 0.02f, 0.5f, m.dark, 'y').transform.localRotation = Quaternion.Euler(-23f, 0f, 0f);
            Cyl("Lever R", visual, new Vector3(0.3f, 1.72f, -0.5f), 0.02f, 0.5f, m.dark, 'y').transform.localRotation = Quaternion.Euler(-23f, 0f, 0f);
            Box("Fuel Tank", visual, new Vector3(0f, 1.45f, -1.74f), new Vector3(1.46f, 0.76f, 0.56f), m.paint);
            foreach (var p in new[] { new Vector3(-0.68f, 2.15f, -0.28f), new Vector3(0.68f, 2.15f, -0.28f), new Vector3(-0.68f, 2.15f, -1.64f), new Vector3(0.68f, 2.15f, -1.64f) })
                Box("ROPS Post", visual, p, new Vector3(0.12f, 1.86f, 0.12f), m.paint);
            Box("ROPS Roof", visual, new Vector3(0f, 3.09f, -0.96f), new Vector3(1.54f, 0.09f, 1.52f), m.paint);
            Box("Roof Rim", visual, new Vector3(0f, 3f, -0.22f), new Vector3(1.5f, 0.06f, 0.08f), m.dark);
            Cyl("Exhaust Stack", visual, new Vector3(0.38f, 2.48f, 1.12f), 0.075f, 0.95f, m.dark, 'y');
            Cyl("Rain Cap", visual, new Vector3(0.38f, 2.97f, 1.12f), 0.1f, 0.08f, m.dark, 'y');
            Cyl("Pre-cleaner", visual, new Vector3(-0.38f, 2.2f, 1f), 0.13f, 0.3f, m.steel, 'y');
            Box("Ripper Frame", visual, new Vector3(0f, 0.95f, -2.05f), new Vector3(1.1f, 0.18f, 0.6f), m.steel);
            Box("Ripper Shank", visual, new Vector3(0f, 0.55f, -2.32f), new Vector3(0.13f, 1.15f, 0.2f), m.steel).transform.localRotation = Quaternion.Euler(16f, 0f, 0f);

            // Work lights on the canopy
            var lights = new System.Collections.Generic.List<Light>();
            var lenses = new System.Collections.Generic.List<Renderer>();
            foreach (float sx in new[] { -0.55f, 0.55f })
            {
                Box("Work Light Housing", visual, new Vector3(sx, 2.98f, -0.16f), new Vector3(0.17f, 0.13f, 0.11f), m.dark);
                lenses.Add(Cyl("Work Light Lens", visual, new Vector3(sx, 2.98f, -0.1f), 0.055f, 0.03f, m.lens, 'z').GetComponent<Renderer>());
                Box("Rear Light Housing", visual, new Vector3(sx, 2.98f, -1.76f), new Vector3(0.17f, 0.13f, 0.11f), m.dark);
                var lgo = new GameObject("Work Light");
                lgo.transform.SetParent(visual, false);
                lgo.transform.localPosition = new Vector3(sx, 2.98f, -0.04f);
                lgo.transform.localRotation = Quaternion.Euler(14f, sx * 10f, 0f);
                var light = lgo.AddComponent<Light>();
                light.type = LightType.Spot;
                light.spotAngle = 70f;
                light.range = 45f;
                light.color = new Color(1f, 0.93f, 0.8f);
                light.shadows = LightShadows.Soft;
                SetLightIntensity(light, 12000f);   // lumens in HDRP
                lights.Add(light);
            }

            // Lift cylinder anchors on the hull
            var baseL = Empty("Cylinder Base L", visual, new Vector3(-0.72f, 1.75f, 1.6f));
            var baseR = Empty("Cylinder Base R", visual, new Vector3(0.72f, 1.75f, 1.6f));
            var cylL = Cyl("Lift Cylinder L", t, Vector3.zero, 0.065f, 1f, m.steel, 'y');
            var cylR = Cyl("Lift Cylinder R", t, Vector3.zero, 0.065f, 1f, m.steel, 'y');

            var cabEye = Empty("Cab Eye", t, new Vector3(0f, 2.35f, -0.9f));
            cabEye.localRotation = Quaternion.Euler(10f, 0f, 0f);

            // Blade: lift (about the trunnions) > angle (swing) > tilt, all revolute articulation joints.
            var lift = Link("Blade Lift", t, new Vector3(0f, 0.55f, 0.2f), Quaternion.identity, 900f, -16f, 9f);
            Box("Push Arm L", lift.transform, new Vector3(-1.02f, -0.02f, 1.5f), new Vector3(0.16f, 0.22f, 3.05f), m.steel);
            Box("Push Arm R", lift.transform, new Vector3(1.02f, -0.02f, 1.5f), new Vector3(0.16f, 0.22f, 3.05f), m.steel);
            var rodL = Empty("Cylinder Rod L", lift.transform, new Vector3(-0.72f, 0.62f, 2.87f));
            var rodR = Empty("Cylinder Rod R", lift.transform, new Vector3(0.72f, 0.62f, 2.87f));

            var angle = Link("Blade Angle", lift.transform, new Vector3(0f, -0.07f, 3f), Quaternion.Euler(0f, 0f, 90f), 250f, -25f, 25f);
            ColliderBox("Collider Angle Pin", angle.transform, Vector3.zero, new Vector3(0.4f, 0.4f, 0.4f));
            var blade = Link("Blade", angle.transform, Vector3.zero, Quaternion.Euler(0f, -90f, 0f), 2300f, -8f, 8f);
            var bt = blade.transform;

            float[,] profile = { { -0.43f, 0.4f }, { -0.13f, 0.2f }, { 0.22f, 0.12f }, { 0.57f, 0.18f }, { 0.83f, 0.36f } };
            for (int i = 0; i < 4; i++)
            {
                float y0 = profile[i, 0], z0 = profile[i, 1], y1 = profile[i + 1, 0], z1 = profile[i + 1, 1];
                float len = Mathf.Sqrt((y1 - y0) * (y1 - y0) + (z1 - z0) * (z1 - z0));
                var slat = Box("Moldboard", bt, new Vector3(0f, (y0 + y1) * 0.5f, (z0 + z1) * 0.5f), new Vector3(3.82f, len + 0.02f, 0.07f), m.paint);
                slat.transform.localRotation = Quaternion.Euler(Mathf.Atan2(z1 - z0, y1 - y0) * Mathf.Rad2Deg, 0f, 0f);
            }
            Box("Cutting Edge", bt, new Vector3(0f, -0.45f, 0.42f), new Vector3(3.82f, 0.12f, 0.09f), m.edge);
            Box("End Bit L", bt, new Vector3(-1.93f, 0.19f, 0.22f), new Vector3(0.06f, 1.15f, 0.48f), m.paint);
            Box("End Bit R", bt, new Vector3(1.93f, 0.19f, 0.22f), new Vector3(0.06f, 1.15f, 0.48f), m.paint);
            Box("Back Plate", bt, new Vector3(0f, 0.17f, 0f), new Vector3(3.6f, 0.9f, 0.1f), m.steel);
            foreach (float rx in new[] { -1.2f, -0.4f, 0.4f, 1.2f })
                Box("Rib", bt, new Vector3(rx, 0.17f, -0.1f), new Vector3(0.08f, 0.9f, 0.22f), m.steel);
            Box("Pivot Block", bt, new Vector3(0f, 0.1f, -0.15f), new Vector3(0.5f, 0.4f, 0.3f), m.steel);
            ColliderBox("Collider Blade", bt, new Vector3(0f, 0.2f, 0.22f), new Vector3(3.85f, 1.3f, 0.32f));
            var edgeL = Empty("Cutting Edge L", bt, new Vector3(-1.91f, -0.47f, 0.44f));
            var edgeR = Empty("Cutting Edge R", bt, new Vector3(1.91f, -0.47f, 0.44f));
            var camMount = Empty("Blade Cam Mount", bt, new Vector3(0f, 0.95f, 0.3f));
            camMount.localRotation = Quaternion.Euler(55f, 0f, 0f);

            // Dust
            var dust = dozerGo.AddComponent<DustEmitters>();
            dust.bladeLeft = DustSystem("Dust Blade L", bt, new Vector3(-1.7f, -0.25f, 0.8f), m.dust, 1.6f, 2.6f);
            dust.bladeRight = DustSystem("Dust Blade R", bt, new Vector3(1.7f, -0.25f, 0.8f), m.dust, 1.6f, 2.6f);
            dust.trackLeft = DustSystem("Dust Track L", t, new Vector3(-0.98f, 0.25f, -1.6f), m.dust, 1.2f, 2f);
            dust.trackRight = DustSystem("Dust Track R", t, new Vector3(0.98f, 0.25f, -1.6f), m.dust, 1.2f, 2f);

            // Controller and blade cutter
            var dozer = dozerGo.AddComponent<DozerController>();
            dozer.ground = ground;
            dozer.liftJoint = lift;
            dozer.angleJoint = angle;
            dozer.tiltJoint = blade;
            dozer.leftTrackRenderers = trackRenderers[0];
            dozer.rightTrackRenderers = trackRenderers[1];
            dozer.leftWheels = wheels[0];
            dozer.rightWheels = wheels[1];
            dozer.liftCylinders = new[] { cylL.transform, cylR.transform };
            dozer.cylinderBases = new[] { baseL, baseR };
            dozer.cylinderRods = new[] { rodL, rodR };
            dozer.workLights = lights.ToArray();
            dozer.lightLenses = lenses.ToArray();
            dozer.dust = dust;

            var cutter = dozerGo.AddComponent<BladeCutter>();
            cutter.ground = ground;
            cutter.edgeLeft = edgeL;
            cutter.edgeRight = edgeR;
            cutter.blade = blade;
            cutter.dust = dust;

            return new DozerRig { dozer = dozer, cutter = cutter, cabEye = cabEye, bladeCamMount = camMount };
        }

        static ArticulationBody Link(string name, Transform parent, Vector3 localPos, Quaternion axisFrame, float mass, float lower, float upper)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            var ab = go.AddComponent<ArticulationBody>();
            ab.mass = mass;
            ab.jointType = ArticulationJointType.RevoluteJoint;
            ab.matchAnchors = true;
            ab.anchorPosition = Vector3.zero;
            ab.anchorRotation = axisFrame;          // the joint turns about this frame's X axis
            ab.twistLock = ArticulationDofLock.LimitedMotion;
            ab.linearDamping = 0.05f;
            ab.angularDamping = 0.5f;
            ab.jointFriction = 0.05f;
            var drive = ab.xDrive;
            drive.lowerLimit = lower;
            drive.upperLimit = upper;
            drive.stiffness = 2e7f;     // hydraulic: stiff, well damped, with a force limit
            drive.damping = 2e6f;
            drive.forceLimit = 6e5f;
            drive.target = 0f;
            ab.xDrive = drive;
            return ab;
        }

        static ParticleSystem DustSystem(string name, Transform parent, Vector3 localPos, Material mat, float size, float life)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.loop = true;
            main.playOnAwake = true;
            main.startLifetime = new ParticleSystem.MinMaxCurve(life * 0.7f, life * 1.3f);
            main.startSpeed = new ParticleSystem.MinMaxCurve(0.3f, 1.2f);
            main.startSize = new ParticleSystem.MinMaxCurve(size * 0.6f, size * 1.2f);
            main.startRotation = new ParticleSystem.MinMaxCurve(0f, Mathf.PI * 2f);
            main.startColor = new Color(0.66f, 0.58f, 0.48f, 0.55f);
            main.gravityModifier = -0.02f;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.maxParticles = 400;
            var emission = ps.emission;
            emission.rateOverTime = 0f;
            var shape = ps.shape;
            shape.shapeType = ParticleSystemShapeType.Sphere;
            shape.radius = 0.45f;
            var sol = ps.sizeOverLifetime;
            sol.enabled = true;
            sol.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0f, 0.5f, 1f, 2.4f));
            var col = ps.colorOverLifetime;
            col.enabled = true;
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) },
                      new[] { new GradientAlphaKey(0f, 0f), new GradientAlphaKey(1f, 0.12f), new GradientAlphaKey(0.55f, 0.5f), new GradientAlphaKey(0f, 1f) });
            col.color = new ParticleSystem.MinMaxGradient(g);
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = mat;
            r.renderMode = ParticleSystemRenderMode.Billboard;
            r.sortMode = ParticleSystemSortMode.Distance;
            return ps;
        }

        // ------------------------------------------------------------------ cameras, HUD, lighting

        static void BuildCamerasAndHud(Transform root, DozerRig rig)
        {
            foreach (var cam in Object.FindObjectsByType<Camera>(FindObjectsInactive.Include, FindObjectsSortMode.None))
                if (cam.gameObject.scene == root.gameObject.scene && !cam.transform.IsChildOf(root)) cam.gameObject.SetActive(false);

            var camGo = new GameObject("Main Camera");
            camGo.transform.SetParent(root, false);
            camGo.tag = "MainCamera";
            var view = camGo.AddComponent<Camera>();
            view.nearClipPlane = 0.1f;
            view.farClipPlane = 2000f;
            camGo.AddComponent<AudioListener>();

            var bladeCamGo = new GameObject("Blade Cam");
            bladeCamGo.transform.SetParent(rig.bladeCamMount, false);
            var bladeCam = bladeCamGo.AddComponent<Camera>();
            bladeCam.depth = 1f;
            bladeCam.fieldOfView = 75f;
            bladeCam.nearClipPlane = 0.05f;
            bladeCam.farClipPlane = 300f;

            var systems = new GameObject("Player");
            systems.transform.SetParent(root, false);
            var input = systems.AddComponent<DozerInput>();
            var cameraRig = systems.AddComponent<DozerCameraRig>();
            cameraRig.dozer = rig.dozer;
            cameraRig.input = input;
            cameraRig.viewCamera = view;
            cameraRig.bladeCamera = bladeCam;
            cameraRig.cabEye = rig.cabEye;
            var hud = systems.AddComponent<DozerHud>();
            hud.dozer = rig.dozer;
            hud.cutter = rig.cutter;
            hud.rig = cameraRig;
            hud.input = input;
            rig.dozer.controlSource = input;
        }

        static void SetupLighting(Transform root)
        {
            var sun = Object.FindObjectsByType<Light>(FindObjectsSortMode.None)
                .FirstOrDefault(l => l.type == LightType.Directional && l.gameObject.activeInHierarchy);
            if (!sun)
            {
                var go = new GameObject("Sun");
                go.transform.SetParent(root, false);
                sun = go.AddComponent<Light>();
                sun.type = LightType.Directional;
                sun.color = new Color(1f, 0.95f, 0.88f);
                SetLightIntensity(sun, 100000f);   // lux, bright Australian afternoon
            }
            sun.shadows = LightShadows.Soft;
            sun.transform.rotation = Quaternion.Euler(38f, 215f, 0f);   // low afternoon sun for long shadows

            AddAmbientOcclusion(root);
        }

        /// <summary>Sets a light's intensity for HDRP whichever way this version stores it.</summary>
        static void SetLightIntensity(Light light, float value)
        {
            light.intensity = value;
            var t = FindType("UnityEngine.Rendering.HighDefinition.HDAdditionalLightData");
            if (t == null) return;
            var data = light.GetComponent(t) ?? light.gameObject.AddComponent(t);
            var set = t.GetMethod("SetIntensity", new[] { typeof(float) });
            if (set == null) return;
            try { set.Invoke(data, new object[] { value }); }
            catch (Exception e) { Debug.LogWarning("Digger: couldn't set HDRP light intensity: " + e.Message); }
        }

        /// <summary>Adds a global volume with screen-space ambient occlusion (HDRP), using reflection so the script compiles on any pipeline.</summary>
        static void AddAmbientOcclusion(Transform root)
        {
            var volumeType = FindType("UnityEngine.Rendering.Volume");
            var profileType = FindType("UnityEngine.Rendering.VolumeProfile");
            var aoType = FindType("UnityEngine.Rendering.HighDefinition.ScreenSpaceAmbientOcclusion")
                      ?? FindType("UnityEngine.Rendering.HighDefinition.AmbientOcclusion");
            if (volumeType == null || profileType == null || aoType == null)
            {
                Debug.LogWarning("Digger: HDRP volume types not found, ambient occlusion not added.");
                return;
            }
            try
            {
                var go = new GameObject("Ambient Occlusion Volume");
                go.transform.SetParent(root, false);
                var volume = go.AddComponent(volumeType);
                SetMember(volume, "isGlobal", true);
                SetMember(volume, "priority", 10f);

                var profile = ScriptableObject.CreateInstance(profileType);
                profile.name = "Stage1 Volume";
                SaveAsset(profile, Gen + "/Stage1 Volume.asset");
                var add = profileType.GetMethod("Add", new[] { typeof(Type), typeof(bool) });
                var ao = add.Invoke(profile, new object[] { aoType, true }) as ScriptableObject;
                if (ao != null)
                {
                    ao.name = aoType.Name;
                    AssetDatabase.AddObjectToAsset(ao, profile);
                    SetParameter(ao, "intensity", 1.2f);
                    SetParameter(ao, "radius", 1.5f);
                }
                SetMember(volume, "sharedProfile", profile);
                EditorUtility.SetDirty(profile);
                AssetDatabase.SaveAssets();
            }
            catch (Exception e)
            {
                Debug.LogWarning("Digger: couldn't add ambient occlusion volume (" + e.Message + "). Add an Ambient Occlusion override to a Volume by hand.");
            }
        }

        static void SetParameter(object component, string name, object value)
        {
            var field = component.GetType().GetField(name, BindingFlags.Public | BindingFlags.Instance);
            if (field == null) return;
            var parameter = field.GetValue(component);
            if (parameter == null) return;
            SetMember(parameter, "overrideState", true);
            SetMember(parameter, "value", value);
        }

        static void SetMember(object target, string name, object value)
        {
            var type = target.GetType();
            var prop = type.GetProperty(name, BindingFlags.Public | BindingFlags.Instance);
            if (prop != null && prop.CanWrite) { prop.SetValue(target, value, null); return; }
            var field = type.GetField(name, BindingFlags.Public | BindingFlags.Instance);
            if (field != null) field.SetValue(target, value);
        }

        static Type FindType(string fullName)
        {
            foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
            {
                var t = asm.GetType(fullName, false);
                if (t != null) return t;
            }
            return null;
        }

        // ------------------------------------------------------------------ primitives

        static GameObject Prim(PrimitiveType type, string name, Transform parent, Vector3 pos, Vector3 scale, Material mat, Vector3 euler, bool keepCollider)
        {
            var go = GameObject.CreatePrimitive(type);
            go.name = name;
            if (!keepCollider) Object.DestroyImmediate(go.GetComponent<Collider>());
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(euler);
            go.transform.localScale = scale;
            go.GetComponent<Renderer>().sharedMaterial = mat;
            return go;
        }

        static GameObject Box(string name, Transform parent, Vector3 pos, Vector3 size, Material mat)
        {
            return Prim(PrimitiveType.Cube, name, parent, pos, size, mat, Vector3.zero, false);
        }

        /// <summary>Cylinder of the given radius and length along local x, y or z.</summary>
        static GameObject Cyl(string name, Transform parent, Vector3 pos, float radius, float length, Material mat, char axis)
        {
            var euler = axis == 'x' ? new Vector3(0f, 0f, 90f) : axis == 'z' ? new Vector3(90f, 0f, 0f) : Vector3.zero;
            return Prim(PrimitiveType.Cylinder, name, parent, pos, new Vector3(radius * 2f, length * 0.5f, radius * 2f), mat, euler, false);
        }

        static Transform Empty(string name, Transform parent, Vector3 pos)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            return go.transform;
        }

        static void ColliderBox(string name, Transform parent, Vector3 center, Vector3 size)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var box = go.AddComponent<BoxCollider>();
            box.center = center;
            box.size = size;
        }
    }
}
