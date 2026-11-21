// Gib cubes: what a grunt bursts into (like Smashed's smash_gibs.gd).  Each one is thrown out, tumbles, bounces on
// the voxel ground (FloorAt), lies there a few seconds and sinks away.  Drawn instanced, one batch per colour.
using UnityEngine;
using UnityEngine.Rendering;

public class Gibs : MonoBehaviour
{
    static Gibs instance;
    const int Max = 4000;
    const float Life = 6f;

    readonly Vector3[] pos = new Vector3[Max], vel = new Vector3[Max], spin = new Vector3[Max];
    readonly Quaternion[] rot = new Quaternion[Max];
    readonly float[] age = new float[Max], size = new float[Max];
    readonly int[] colour = new int[Max];
    int count;
    Color[] colours = new Color[0];
    Material[] mats = new Material[0];
    Matrix4x4[][] bufs = new Matrix4x4[0][];
    int[] fill = new int[0];
    Mesh cube;

    public static int Count { get { return instance != null ? instance.count : 0; } }
    public static int Made { get; private set; }

    void Awake()
    {
        instance = this;
        var c = GameObject.CreatePrimitive(PrimitiveType.Cube);
        cube = c.GetComponent<MeshFilter>().sharedMesh;
        Destroy(c);
    }
    void OnDestroy() { if (instance == this) instance = null; }

    public static void Clear() { if (instance != null) instance.count = 0; }

    int ColourIndex(Color c)
    {
        for (int i = 0; i < colours.Length; i++) if (colours[i] == c) return i;
        int n = colours.Length;
        System.Array.Resize(ref colours, n + 1); System.Array.Resize(ref mats, n + 1); System.Array.Resize(ref bufs, n + 1); System.Array.Resize(ref fill, n + 1);
        colours[n] = c;
        mats[n] = new Material(Shader.Find("Standard")) { color = c, enableInstancing = true };
        mats[n].SetFloat("_Glossiness", c.r > 0.5f && c.g < 0.1f ? 0.45f : 0.1f);   // blood has a little shine
        bufs[n] = new Matrix4x4[Max];
        return n;
    }

    /// `n` chunks from `at`, thrown mostly along `dir` and up, coloured from `palette`.  `cubeSize` > 0: every chunk that
    /// size (the grunt's 6.25 cm voxels); otherwise 13 to 24 cm.
    public static void Burst(Vector3 at, Vector3 dir, Color[] palette, int n, float cubeSize = 0f)
    {
        if (instance == null) return;
        instance.DoBurst(at, dir, palette, n, cubeSize);
    }

    void DoBurst(Vector3 at, Vector3 dir, Color[] palette, int n, float cubeSize)
    {
        for (int k = 0; k < n; k++)
        {
            int i = count < Max ? count++ : Random.Range(0, Max);
            pos[i] = at + Vector3.Scale(Random.insideUnitSphere, new Vector3(0.35f, 0.6f, 0.35f));   // spread through the body
            vel[i] = dir * Random.Range(2f, 5.5f) + Random.insideUnitSphere * 2.5f + Vector3.up * Random.Range(2.5f, 5f);
            spin[i] = Random.insideUnitSphere * 720f;
            rot[i] = Random.rotation;
            age[i] = 0f;
            size[i] = cubeSize > 0f ? cubeSize : Random.Range(0.13f, 0.24f);
            colour[i] = ColourIndex(palette[Random.Range(0, palette.Length)]);
            Made++;
        }
    }

    void Update()
    {
        float dt = Time.deltaTime;
        var world = VoxelWorld.Instance;
        for (int i = 0; i < count; i++)
        {
            age[i] += dt;
            if (age[i] > Life) { count--; pos[i] = pos[count]; vel[i] = vel[count]; spin[i] = spin[count]; rot[i] = rot[count]; age[i] = age[count]; size[i] = size[count]; colour[i] = colour[count]; i--; continue; }
            Vector3 v = vel[i];
            v.y -= 9.81f * dt;
            Vector3 p = pos[i] + v * dt;
            float lim = ArenaGame.Half - 0.15f;
            if (Mathf.Abs(p.x) > lim) { p.x = Mathf.Sign(p.x) * lim; v.x *= -0.4f; }
            if (Mathf.Abs(p.z) > lim) { p.z = Mathf.Sign(p.z) * lim; v.z *= -0.4f; }
            float floor = world != null ? world.FloorAt(p + Vector3.up * 0.3f) : 0f;
            float r = size[i] * 0.5f;
            if (age[i] > Life - 1.2f) floor -= (age[i] - (Life - 1.2f)) * 0.3f;   // the last moment: it sinks into the ground
            if (p.y - r < floor)
            {
                p.y = floor + r;
                if (v.y < -1.5f) { v.y = -v.y * 0.3f; v.x *= 0.6f; v.z *= 0.6f; spin[i] *= 0.5f; }
                else { v.y = 0f; v.x *= Mathf.Exp(-8f * dt); v.z *= Mathf.Exp(-8f * dt); spin[i] *= Mathf.Exp(-6f * dt); }
            }
            pos[i] = p; vel[i] = v;
            rot[i] = Quaternion.Euler(spin[i] * dt) * rot[i];
        }
        for (int c = 0; c < fill.Length; c++) fill[c] = 0;
        for (int i = 0; i < count; i++) { int c = colour[i]; bufs[c][fill[c]++] = Matrix4x4.TRS(pos[i], rot[i], Vector3.one * size[i]); }
        var bounds = new Bounds(Vector3.zero, Vector3.one * 80f);
        for (int c = 0; c < fill.Length; c++)
            if (fill[c] > 0)
                Graphics.RenderMeshInstanced(new RenderParams(mats[c]) { worldBounds = bounds, shadowCastingMode = ShadowCastingMode.On, receiveShadows = true }, cube, 0, bufs[c], fill[c]);
    }
}
