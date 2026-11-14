// A hand cart on the mine rails.
//   - It catches whatever is thrown or falls into it, up to its capacity.
//   - Walk into either end of it and you push it along the track.  It stops at the end of the rails and at
//     anything solid on the track (the cave-in, say).
//   - T, standing beside it, tips the load out over its left side.
// What is in the cart is still counted with the dirt, so volume stays exact.
using System.Collections.Generic;
using UnityEngine;

/// Everything an upgrade might change about a cart.  Upgrades are not designed yet: when they are, they
/// swap in a different CartSpec (a bigger tub, a motor, and so on) and nothing else needs to change.
[System.Serializable]
public struct CartSpec
{
    public string name;
    public int capacity;            // voxels it holds (4096 is one cubic metre)
    public float pushFactor;        // how far it rolls for each metre it is pushed (1 = keeps pace with the worker)
    public float tipSeconds;        // the longest a tip takes
    public int pourPerStep;         // clods that leave per physics step while tipping

    public static CartSpec HandCart
    {
        get { return new CartSpec { name = "hand cart", capacity = 4096, pushFactor = 1f, tipSeconds = 6f, pourPerStep = 6 }; }
    }
}

public class MineCart : MonoBehaviour
{
    public static MineCart Instance { get; private set; }

    [System.NonSerialized] public CartSpec spec = CartSpec.HandCart;
    public int capacity { get { return spec.capacity; } }
    public float Along { get; private set; }             // metres along the track from its start, deep in the tunnel

    const float HalfLength = 0.85f, HalfWidth = 0.55f, FloorHeight = 0.42f, TubTop = 1.1f;
    const byte Timber = 11, DarkTimber = 12, Steel = 13, Dirt = 6;

    VoxelWorld world;
    List<Vector3> path;
    float[] distanceAt;
    float length, tipLeft;
    Transform dirtLevel;
    bool tipping;

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
            for (int k = 0; k < 4; k++)
            {
                float su = (k == 1 || k == 2) ? 1f : -1f, sv = k >= 2 ? 1f : -1f;
                verts.Add(centre + Vector3.Scale(n + u * su + v * sv, size * 0.5f));
                normals.Add(n); colours.Add(col);
            }
            tris.Add(start); tris.Add(start + 2); tris.Add(start + 1);
            tris.Add(start); tris.Add(start + 3); tris.Add(start + 2);
        }
    }

    Transform Part(string name)
    {
        var go = new GameObject(name);
        go.transform.SetParent(transform, false);
        var mesh = new Mesh();
        mesh.SetVertices(verts); mesh.SetNormals(normals); mesh.SetColors(colours); mesh.SetTriangles(tris, 0);
        mesh.RecalculateBounds();
        go.AddComponent<MeshFilter>().sharedMesh = mesh;
        go.AddComponent<MeshRenderer>().sharedMaterial = world.material;
        verts.Clear(); normals.Clear(); colours.Clear(); tris.Clear();
        return go.transform;
    }

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    void Start()
    {
        world = VoxelWorld.Instance;
        path = SiteProps.RailPath;
        if (world == null || path == null || path.Count < 2) { enabled = false; return; }
        distanceAt = new float[path.Count];
        for (int i = 1; i < path.Count; i++) distanceAt[i] = distanceAt[i - 1] + Vector3.Distance(path[i - 1], path[i]);
        length = distanceAt[path.Count - 1];

        // the tub: plank sides on a timber frame, steel straps and four small wheels
        Box(new Vector3(0f, FloorHeight, 0f), new Vector3(HalfWidth * 2f, 0.08f, HalfLength * 2f), DarkTimber);
        Box(new Vector3(-HalfWidth, 0.78f, 0f), new Vector3(0.07f, 0.66f, HalfLength * 2f), Timber);
        Box(new Vector3(HalfWidth, 0.78f, 0f), new Vector3(0.07f, 0.66f, HalfLength * 2f), Timber);
        Box(new Vector3(0f, 0.78f, -HalfLength), new Vector3(HalfWidth * 2f, 0.66f, 0.07f), Timber);
        Box(new Vector3(0f, 0.78f, HalfLength), new Vector3(HalfWidth * 2f, 0.66f, 0.07f), Timber);
        foreach (float z in new[] { -0.5f, 0.5f })
        {
            Box(new Vector3(-HalfWidth - 0.04f, 0.78f, z), new Vector3(0.03f, 0.7f, 0.08f), Steel);
            Box(new Vector3(HalfWidth + 0.04f, 0.78f, z), new Vector3(0.03f, 0.7f, 0.08f), Steel);
            Box(new Vector3(0f, 0.3f, z), new Vector3(1.0f, 0.08f, 0.1f), Steel);                    // axle
            Box(new Vector3(-0.45f, 0.3f, z), new Vector3(0.07f, 0.3f, 0.3f), Steel);                // wheels
            Box(new Vector3(0.45f, 0.3f, z), new Vector3(0.07f, 0.3f, 0.3f), Steel);
        }
        Box(new Vector3(0f, TubTop + 0.02f, -HalfLength - 0.12f), new Vector3(0.8f, 0.05f, 0.05f), Steel);   // push bar
        Part("Tub");
        Box(Vector3.zero, new Vector3(HalfWidth * 2f - 0.1f, 1f, HalfLength * 2f - 0.1f), Dirt);
        dirtLevel = Part("Load");

        // parked just outside the mine entrance
        Along = 0f;
        for (int i = 0; i < path.Count; i++) if (path[i].z <= VoxelWorld.PortalZ - 2.2f) { Along = distanceAt[i]; break; }
        Place();
    }

    void Sample(float s, out Vector3 at, out Vector3 dir)
    {
        s = Mathf.Clamp(s, 0f, length);
        int i = 1;
        while (i < path.Count - 1 && distanceAt[i] < s) i++;
        float t = Mathf.InverseLerp(distanceAt[i - 1], distanceAt[i], s);
        at = Vector3.Lerp(path[i - 1], path[i], t);
        dir = (path[i] - path[i - 1]).normalized;
    }

    void Place()
    {
        Vector3 at, dir;
        Sample(Along, out at, out dir);
        at.y = world.FloorAt(at + Vector3.up * 0.5f);
        dir.y = 0f;
        transform.SetPositionAndRotation(at, Quaternion.LookRotation(dir.sqrMagnitude > 0.001f ? dir.normalized : Vector3.forward));
        float fill = Mathf.Clamp01(world.CartVoxels / (float)capacity);
        float depth = Mathf.Max(0.02f, fill * (TubTop - FloorHeight - 0.08f));
        dirtLevel.gameObject.SetActive(world.CartVoxels > 0);
        dirtLevel.localPosition = new Vector3(0f, FloorHeight + 0.04f + depth * 0.5f, 0f);
        dirtLevel.localScale = new Vector3(1f, depth, 1f);
    }

    void FixedUpdate()
    {
        // whatever loose dirt is inside the tub joins the load
        world.CartCollect(transform.worldToLocalMatrix, new Vector3(-HalfWidth, FloorHeight, -HalfLength), new Vector3(HalfWidth, TubTop + 0.25f, HalfLength), capacity);
        if (tipping)
        {
            // pour out over the left side, a bit at a time
            Vector3 lip = transform.TransformPoint(new Vector3(-HalfWidth - 0.25f, TubTop - 0.1f, Random.Range(-0.6f, 0.6f)));
            for (int k = 0; k < spec.pourPerStep; k++)
                if (!world.CartPour(lip + Random.insideUnitSphere * 0.15f, -transform.right * Random.Range(1.2f, 2.4f) + Vector3.up * 0.4f)) { tipping = false; break; }
            tipLeft -= Time.fixedDeltaTime;
            if (tipLeft <= 0f || world.CartVoxels < VoxelWorld.ClodVoxels) tipping = false;
        }
        Place();
    }

    public bool Near(Vector3 pos, float within) { return Vector3.Distance(new Vector3(pos.x, transform.position.y, pos.z), transform.position) <= within; }

    public void Tip() { if (world.CartVoxels >= VoxelWorld.ClodVoxels) { tipping = true; tipLeft = spec.tipSeconds; } }
    public bool Tipping { get { return tipping; } }

    // for tests and saved games
    public float Length { get { return length; } }
    public float EndLimit { get { return length - HalfLength; } }
    public float StartLimit { get { return HalfLength; } }
    public void SetAlong(float s) { Along = Mathf.Clamp(s, HalfLength, length - HalfLength); if (world != null) Place(); }

    /// Called as the worker tries to step to `next`.  If that would put him inside the cart he is stopped,
    /// and the cart is shoved along the track by however much of his step was along it.  True = he is blocked.
    public bool PushedBy(Vector3 next, Vector3 step)
    {
        Vector3 local = transform.InverseTransformPoint(next);
        if (Mathf.Abs(local.x) > HalfWidth + 0.32f || Mathf.Abs(local.z) > HalfLength + 0.34f) return false;
        float along = Vector3.Dot(step, transform.forward);
        // only a push on an end moves it: from behind it goes forward, from in front it goes back
        bool onEnd = Mathf.Abs(local.z) > HalfLength - 0.05f;
        if (onEnd && Mathf.Abs(along) > 1e-5f && Mathf.Sign(along) == -Mathf.Sign(local.z))
        {
            float to = Mathf.Clamp(Along + along * spec.pushFactor, HalfLength, length - HalfLength);
            Vector3 lead, dir;
            Sample(to + Mathf.Sign(along) * (HalfLength + 0.12f), out lead, out dir);
            lead.y = transform.position.y + 0.55f;
            if (world.MaterialAt(lead) == VoxelWorld.Air) Along = to;
        }
        return true;
    }

    public Vector3 Mouth { get { return transform.position + Vector3.up * (TubTop - 0.15f); } }
    public bool HasRoom { get { return world != null && world.CartVoxels < capacity - VoxelWorld.ClodVoxels; } }
}
