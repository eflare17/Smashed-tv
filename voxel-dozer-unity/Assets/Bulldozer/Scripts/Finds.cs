// Dozer parts buried in the mine's cave-in.  Dig one out, pick it up (E), carry it to the dozer and fit it (E).
//
// Each find brings back one thing the dozer does, but only matters while the dozer is set to dead (F9):
//   0 tracks part  -> it can drive
//   1 blade part   -> the blade works (lift, angle, tilt)
//   2 ripper part  -> the ripper works
// What the parts really are and what they look like is not decided yet (see OVERNIGHT.md, questions):
// these are placeholders built from boxes.
//
// A find is an object, not ground.  It sits in a small hollow left in the rubble when the ground is made
// (VoxelWorld.InFindHole), so picks and shovels never touch it: they only clear the dirt round it.
//
// Once a part has been uncovered it stays found: loose rubble sliding back over it does not bury it again, you can
// still reach in and pick it up.  While any of it can be seen from the camera it glints now and then, so it can be
// spotted while digging.
using System.Collections.Generic;
using UnityEngine;

public class Finds : MonoBehaviour
{
    public static Finds Instance { get; private set; }
    public static readonly string[] Names = { "tracks part", "blade part", "ripper part" };
    public const int Count = 3;

    public readonly Vector3[] Spot = new Vector3[Count];
    public readonly bool[] Collected = new bool[Count];
    public readonly bool[] Installed = new bool[Count];
    public readonly bool[] Found = new bool[Count];          // uncovered at some point: stays pick-up-able for good
    readonly Transform[] objects = new Transform[Count];
    readonly Transform[] glints = new Transform[Count];
    // where each part's glint sits, on its steel bit
    static readonly Vector3[] GlintAt = { new Vector3(0f, 0.3f, 0f), new Vector3(0f, 0.17f, 0.3f), new Vector3(0f, 0.12f, 0.32f) };
    const float GlintEvery = 2.4f, GlintFor = 0.45f, GlintSeen = 16f;
    [System.NonSerialized] public float testGlintPhase = -1f;   // tests: hold every glint at this point of its flash, seen or not
    VoxelWorld world;

    public static bool IsInstalled(int k) { return Instance != null && Instance.Installed[k]; }

    /// Picked up and not yet fitted: the worker has it with him.
    public bool Carrying(int k) { return Collected[k] && !Installed[k]; }

    public int FirstCarried()
    {
        for (int k = 0; k < Count; k++) if (Carrying(k)) return k;
        return -1;
    }

    // their own colour ids, so the camera's cut-away (which removes scenery: ids 11-15) never hides a find
    const byte Rust = 21, OldPaint = 22, Steel = 23, DarkTimber = 21;

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    void Start()
    {
        world = VoxelWorld.Instance;
        for (int k = 0; k < Count; k++)
        {
            Spot[k] = VoxelWorld.FindSpot(k);
            objects[k] = Build(k);
            objects[k].position = Spot[k];
            glints[k] = BuildGlint(k);
        }
    }

    void Update()
    {
        if (world == null) return;
        var cam = Camera.main;
        for (int k = 0; k < Count; k++)
        {
            if (Collected[k]) { glints[k].gameObject.SetActive(false); continue; }
            if (!Found[k] && Exposed(k)) Found[k] = true;
            // a short star-shaped flash every couple of seconds, only if the camera can see that bit of it
            float phase = (Time.time + k * 0.8f) % GlintEvery;
            bool show = cam != null && phase < GlintFor && CanSee(cam.transform.position, Spot[k] + GlintAt[k]);
            if (testGlintPhase >= 0f) { phase = testGlintPhase; show = cam != null; }
            glints[k].gameObject.SetActive(show);
            if (show)
            {
                Transform g = glints[k];
                g.rotation = Quaternion.LookRotation(g.position - cam.transform.position) * Quaternion.Euler(0f, 0f, 45f + phase * 60f);
                float d = Vector3.Distance(cam.transform.position, g.position);
                g.localScale = Vector3.one * Mathf.Sin(phase / GlintFor * Mathf.PI) * Mathf.Clamp(d * 0.12f, 0.8f, 2f);
            }
        }
    }

    public bool GlintShowing(int k) { return glints[k] != null && glints[k].gameObject.activeSelf; }
    public bool Visible(int k) { var cam = Camera.main; return cam != null && CanSee(cam.transform.position, Spot[k] + GlintAt[k]); }

    bool CanSee(Vector3 eye, Vector3 at)
    {
        Vector3 d = at - eye;
        float dist = d.magnitude;
        if (dist > GlintSeen || dist < 0.01f) return false;
        if (!world.Raycast(eye, d / dist, dist, out Vector3 hit, out byte mat)) return true;
        return Vector3.Distance(hit, eye) >= dist - 0.12f;                     // nothing solid before the glint itself
    }

    static Material glintMat;

    Transform BuildGlint(int k)
    {
        if (glintMat == null)
        {
            var sh = Shader.Find("Unlit/Color");
            glintMat = new Material(sh != null ? sh : Shader.Find("Sprites/Default"));
            glintMat.color = new Color(5f, 4.4f, 3.2f);                        // brighter than white, so the bloom catches it
        }
        var g = new GameObject("Glint").transform;
        g.SetParent(objects[k], false);
        g.localPosition = GlintAt[k];
        for (int i = 0; i < 2; i++)
        {
            var bar = GameObject.CreatePrimitive(PrimitiveType.Cube);
            Destroy(bar.GetComponent<Collider>());
            bar.transform.SetParent(g, false);
            bar.transform.localScale = i == 0 ? new Vector3(0.5f, 0.035f, 0.01f) : new Vector3(0.035f, 0.5f, 0.01f);
            var r = bar.GetComponent<MeshRenderer>();
            r.sharedMaterial = glintMat;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
        }
        g.gameObject.SetActive(false);
        return g;
    }

    // ---------------------------------------------------------------- placeholders, built from boxes
    readonly List<Vector3> verts = new List<Vector3>();
    readonly List<Vector3> normals = new List<Vector3>();
    readonly List<Color32> colours = new List<Color32>();
    readonly List<int> tris = new List<int>();
    static readonly Vector3[] FaceN = { Vector3.right, Vector3.left, Vector3.up, Vector3.down, Vector3.forward, Vector3.back };
    static readonly Vector3[] FaceU = { Vector3.forward, Vector3.back, Vector3.right, Vector3.left, Vector3.left, Vector3.right };

    void Box(Vector3 centre, Vector3 size, byte mat)
    {
        var col = new Color32(mat, 0, 0, 255);
        for (int f = 0; f < 6; f++)
        {
            Vector3 n = FaceN[f], u = FaceU[f], v = Vector3.Cross(n, u);
            int start = verts.Count;
            for (int i = 0; i < 4; i++)
            {
                float su = (i == 1 || i == 2) ? 1f : -1f, sv = i >= 2 ? 1f : -1f;
                verts.Add(centre + Vector3.Scale(n + u * su + v * sv, size * 0.5f));
                normals.Add(n); colours.Add(col);
            }
            tris.Add(start); tris.Add(start + 2); tris.Add(start + 1);
            tris.Add(start); tris.Add(start + 3); tris.Add(start + 2);
        }
    }

    Transform Build(int k)
    {
        // all three fit inside the hollow: 0.6 m square, 0.45 m tall
        if (k == 0)
        {
            // a short run of track pads with a sprocket hub
            for (int i = 0; i < 4; i++) Box(new Vector3(0f, 0.05f, -0.22f + i * 0.15f), new Vector3(0.5f, 0.08f, 0.12f), i % 2 == 0 ? Steel : Rust);
            Box(new Vector3(0f, 0.2f, 0f), new Vector3(0.14f, 0.26f, 0.26f), Rust);
            Box(new Vector3(0f, 0.2f, 0f), new Vector3(0.2f, 0.12f, 0.12f), Steel);
        }
        else if (k == 1)
        {
            // a hydraulic ram: faded yellow barrel and a steel rod, lying down
            Box(new Vector3(0f, 0.11f, -0.05f), new Vector3(0.16f, 0.16f, 0.38f), OldPaint);
            Box(new Vector3(0f, 0.11f, 0.2f), new Vector3(0.07f, 0.07f, 0.18f), Steel);
            Box(new Vector3(0f, 0.11f, -0.27f), new Vector3(0.1f, 0.12f, 0.06f), Rust);
        }
        else
        {
            // a ripper tooth on a short length of shank
            Box(new Vector3(0f, 0.06f, 0f), new Vector3(0.12f, 0.1f, 0.5f), Rust);
            Box(new Vector3(0f, 0.06f, 0.27f), new Vector3(0.1f, 0.08f, 0.08f), Steel);
            Box(new Vector3(0f, 0.18f, -0.18f), new Vector3(0.12f, 0.16f, 0.12f), DarkTimber);
        }
        var go = new GameObject("Find: " + Names[k]);
        go.transform.SetParent(transform, false);
        var mesh = new Mesh();
        mesh.SetVertices(verts); mesh.SetNormals(normals); mesh.SetColors(colours); mesh.SetTriangles(tris, 0);
        mesh.RecalculateBounds();
        go.AddComponent<MeshFilter>().sharedMesh = mesh;
        go.AddComponent<MeshRenderer>().sharedMaterial = world.material;
        verts.Clear(); normals.Clear(); colours.Clear(); tris.Clear();
        return go.transform;
    }

    // ---------------------------------------------------------------- digging out, picking up, fitting
    /// Dug out enough to pick up: little left on top of it, or an open side to reach in from.
    public bool Exposed(int k)
    {
        Vector3 c = Spot[k];
        int topSolid = 0, sideAir = 0;
        for (int i = -1; i <= 1; i++)
            for (int j = -1; j <= 1; j++)
                if (world.MaterialAt(c + new Vector3(i * 0.25f, 0.56f, j * 0.25f)) != VoxelWorld.Air) topSolid++;
        Vector3[] sides = { new Vector3(0.5f, 0.25f, 0f), new Vector3(-0.5f, 0.25f, 0f), new Vector3(0f, 0.25f, 0.5f), new Vector3(0f, 0.25f, -0.5f) };
        foreach (var s in sides) if (world.MaterialAt(c + s) == VoxelWorld.Air) sideAir++;
        return topSolid <= 3 || (sideAir >= 1 && topSolid <= 6);
    }

    public bool CanCollect(int k, Vector3 worker)
    {
        if (Collected[k]) return false;
        Vector3 d = Spot[k] - worker;
        return new Vector2(d.x, d.z).magnitude < 1.7f && Mathf.Abs(d.y) < 1.5f && (Found[k] || Exposed(k));
    }

    /// The find the worker could pick up from where he stands, or -1.
    public int Collectable(Vector3 worker)
    {
        for (int k = 0; k < Count; k++) if (CanCollect(k, worker)) return k;
        return -1;
    }

    public void Collect(int k)
    {
        Collected[k] = true;
        objects[k].gameObject.SetActive(false);
    }

    public void Install(int k)
    {
        if (!Collected[k]) Collect(k);
        Installed[k] = true;
    }

    /// For loading a saved game.
    public void SetState(int k, bool collected, bool installed, bool found)
    {
        Found[k] = found;
        Collected[k] = collected || installed;
        Installed[k] = installed;
        objects[k].gameObject.SetActive(!Collected[k]);
    }
}
