// A hand cart on the mine rails.
//   - It catches whatever is thrown or falls into it, up to its capacity.
//   - E at either end takes hold of it (Worker.cs); then W pushes it along the track and S pulls it back.  It stops at the end of the rails and where
//     the rubble on the track is as high as its tub (the cave-in face).  Lower spill it rolls over.
//   - T, standing beside it, tips the load out over its left side.  At the dump (the end of the rails, 8 m out of
//     the mine door) E does it too, and the load pours into the hopper beside the track: what goes down it is sorted,
//     sold and paid for, into the shared pot (Money.cs).
//   - The motor cart (an upgrade, Upgrades.cs) has a motor box on its front end and a footboard on its back end.
//     R at an end gets on (Worker.cs); W drives it out towards the dump, S back into the mine.  It stops where
//     pushing would stop: rubble on the track and the ends of the rails.
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
    public bool motor;              // the motor cart: he can ride it and drive it (Upgrades.cs sets this)
    public float motorSpeed;        // metres a second under power, flat out

    public static CartSpec HandCart
    {
        get { return new CartSpec { name = "hand cart", capacity = 4096, pushFactor = 1f, tipSeconds = 6f, pourPerStep = 6, motor = false, motorSpeed = 3f }; }
    }
}

public class MineCart : MonoBehaviour
{
    public static MineCart Instance { get; private set; }

    [System.NonSerialized] public CartSpec spec = CartSpec.HandCart;
    public int capacity { get { return spec.capacity; } }
    public float Along { get; private set; }             // metres along the track from its start, deep in the tunnel

    const float HalfLength = 0.85f, HalfWidth = 0.55f, FloorHeight = 0.42f, TubTop = 1.1f;
    const byte Timber = 11, DarkTimber = 12, Steel = 13, Dirt = 6, HiVis = 16, Dark = 20;
    /// How fast the motor cart gets up to speed and slows down, metres a second each second.
    public const float MotorAccel = 4f;
    const float FootboardOut = 0.42f, FootboardHeight = 0.3f;   // the footboard he rides on: past the back end, and how high

    VoxelWorld world;
    List<Vector3> path;
    float[] distanceAt;
    float length, tipLeft;
    Transform dirtLevel, motorBox;
    float motorVel;
    bool tipping;
    readonly int[] sold = new int[16];

    /// How far back from the end of the line the cart still counts as at the dump (beside the hopper).
    public const float DumpLength = 0.45f;
    /// True when the cart is at the dump, where tipping it pays.
    public bool AtDump { get { return length > 0f && Along >= EndLimit - DumpLength; } }

    readonly List<Vector3> verts = new List<Vector3>();
    readonly List<Vector3> normals = new List<Vector3>();
    readonly List<Color32> colours = new List<Color32>();
    readonly List<int> tris = new List<int>();
    static readonly Vector3[] FaceN = { Vector3.right, Vector3.left, Vector3.up, Vector3.down, Vector3.forward, Vector3.back };
    static readonly Vector3[] FaceU = { Vector3.forward, Vector3.back, Vector3.right, Vector3.left, Vector3.left, Vector3.right };

    void Box(Vector3 centre, Vector3 size, byte mat)
    {
        var col = new Color32(mat, 255, 0, 255);           // green 255: the see-through cut never hides the cart
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
        dirtLevel = Part("Load");                                       // its mesh is the heap, built in DrawLoad

        // the motor cart's extras, shown only once it's bought: an orange motor box on the front end (with a dark
        // exhaust stub and cooling fins) and a steel footboard on the back end, under the push bar, to stand on
        Box(new Vector3(0f, 0.62f, HalfLength + 0.2f), new Vector3(0.62f, 0.42f, 0.32f), HiVis);
        Box(new Vector3(0f, 0.86f, HalfLength + 0.2f), new Vector3(0.5f, 0.05f, 0.26f), Dark);
        for (int f = 0; f < 3; f++) Box(new Vector3(-0.2f + f * 0.2f, 0.62f, HalfLength + 0.37f), new Vector3(0.05f, 0.3f, 0.03f), Dark);
        Box(new Vector3(0.24f, 0.98f, HalfLength + 0.26f), new Vector3(0.06f, 0.2f, 0.06f), Dark);
        Box(new Vector3(0f, 0.36f, HalfLength + 0.06f), new Vector3(0.3f, 0.1f, 0.14f), Steel);            // its drive down to the axle
        Box(new Vector3(0f, FootboardHeight - 0.03f, -HalfLength - FootboardOut), new Vector3(0.86f, 0.05f, 0.42f), Steel);
        foreach (float x in new[] { -0.38f, 0.38f }) Box(new Vector3(x, FootboardHeight + 0.05f, -HalfLength - 0.22f), new Vector3(0.05f, 0.16f, 0.44f), Steel);
        motorBox = Part("Motor");
        motorBox.gameObject.SetActive(spec.motor);

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
        DrawLoad();
    }

    // ---- the load: a lumpy heap of rubble in the tub, in the colours of what went in, rising as it fills
    const int LoadCellsX = 6, LoadCellsZ = 10;
    int drawnVoxels = -1;
    float loadTop;                                       // height of the heap's middle above the cart's base

    /// The depth of dirt (averaged over the tub floor) for what the cart holds.
    float LoadDepth { get { return Mathf.Clamp01(world.CartVoxels / (float)capacity) * (TubTop - FloorHeight - 0.08f); } }

    static float CellNoise(int x, int z, int salt)
    {
        uint h = (uint)(x * 73856093) ^ (uint)(z * 19349663) ^ (uint)(salt * 83492791);
        h ^= h >> 13; h *= 0x5bd1e995; h ^= h >> 15;
        return (h & 0xffff) / 65535f;
    }

    void DrawLoad()
    {
        int have = world.CartVoxels;
        if (Mathf.Abs(have - drawnVoxels) < 24 && !(have == 0 && drawnVoxels != 0)) return;   // only when it has changed enough to see
        drawnVoxels = have;
        dirtLevel.gameObject.SetActive(have > 0);
        float depth = LoadDepth;
        loadTop = FloorHeight + 0.04f + depth * 1.25f;
        if (have <= 0) return;
        // which colours: each cell picks a material in proportion to what the cart holds
        int[] mats = { VoxelWorld.LooseSoil, VoxelWorld.LooseClay, VoxelWorld.LooseRock, VoxelWorld.LooseQuartz, VoxelWorld.LooseGold };
        float total = 0f;
        foreach (int m in mats) total += world.CartLoadOf(m);
        float sx = (HalfWidth * 2f - 0.1f) / LoadCellsX, sz = (HalfLength * 2f - 0.1f) / LoadCellsZ;
        for (int x = 0; x < LoadCellsX; x++)
            for (int z = 0; z < LoadCellsZ; z++)
            {
                // heaped up in the middle, lower at the sides, with a lump or dip in each cell
                float u = (x + 0.5f) / LoadCellsX * 2f - 1f, v = (z + 0.5f) / LoadCellsZ * 2f - 1f;
                float mound = 1.25f - 0.55f * (u * u * 0.8f + v * v);
                float h = depth * mound + (CellNoise(x, z, 1) - 0.5f) * Mathf.Min(0.12f, depth * 0.8f + 0.03f);
                h = Mathf.Clamp(h, 0.025f, TubTop - FloorHeight + 0.1f);
                float pick = CellNoise(x, z, 2) * total, acc = 0f;
                byte mat = (byte)VoxelWorld.LooseSoil;
                foreach (int m in mats) { acc += world.CartLoadOf(m); if (pick <= acc && world.CartLoadOf(m) > 0) { mat = (byte)m; break; } }
                Vector3 c = new Vector3(-HalfWidth + 0.05f + (x + 0.5f) * sx, FloorHeight + 0.04f + h * 0.5f, -HalfLength + 0.05f + (z + 0.5f) * sz);
                Box(c, new Vector3(sx, h, sz), mat);
                // the odd clod sitting on top
                if (CellNoise(x, z, 3) > 0.7f) Box(c + new Vector3((CellNoise(x, z, 4) - 0.5f) * sx * 0.5f, h * 0.5f + 0.04f, (CellNoise(x, z, 5) - 0.5f) * sz * 0.5f), new Vector3(0.09f, 0.08f, 0.1f), mat);
            }
        var mesh = dirtLevel.GetComponent<MeshFilter>().sharedMesh;
        mesh.Clear();
        mesh.SetVertices(verts); mesh.SetNormals(normals); mesh.SetColors(colours); mesh.SetTriangles(tris, 0);
        mesh.RecalculateBounds();
        verts.Clear(); normals.Clear(); colours.Clear(); tris.Clear();
        dirtLevel.localPosition = Vector3.zero;
        dirtLevel.localScale = Vector3.one;
    }

    void FixedUpdate()
    {
        if (motorBox != null && motorBox.gameObject.activeSelf != spec.motor) motorBox.gameObject.SetActive(spec.motor);
        // whatever loose dirt is inside the tub joins the load
        // (only once it has dropped in and reached the heap, so you see each shovelful land in the tub)
        float catchAt = Mathf.Min(TubTop + 0.05f, Mathf.Max(FloorHeight + 0.12f, FloorHeight + 0.04f + LoadDepth * 1.25f + 0.1f));
        // (not while it is tipping: the heap it pours out piles up against it, and must not be caught again)
        if (!tipping) world.CartCollect(transform.worldToLocalMatrix, new Vector3(-HalfWidth, 0.05f, -HalfLength), new Vector3(HalfWidth, catchAt, HalfLength), capacity);   // down to near the rails, so a fast clod cannot drop straight through
        if (tipping)
        {
            // pour out over the left side, a bit at a time
            Vector3 lip = transform.TransformPoint(new Vector3(-HalfWidth - 0.25f, TubTop - 0.1f, Random.Range(-0.6f, 0.6f)));
            for (int k = 0; k < spec.pourPerStep; k++)
                if (!world.CartPour(lip + Random.insideUnitSphere * 0.15f, -transform.right * Random.Range(2.2f, 3.1f) + Vector3.up * 0.9f)) { tipping = false; break; }
            tipLeft -= Time.fixedDeltaTime;
            if (tipLeft <= 0f || world.CartVoxels < VoxelWorld.ClodVoxels) tipping = false;
        }
        if (SiteProps.HopperToWorld.m33 != 0f)
        {
            var half = SiteProps.HopperHalf;
            System.Array.Clear(sold, 0, sold.Length);
            if (world.HopperCollect(SiteProps.HopperToWorld.inverse, new Vector3(-half.x - 0.1f, -1f, -half.z - 0.1f), new Vector3(half.x + 0.1f, half.y + 0.05f, half.z + 0.1f), sold) > 0 && Money.Instance != null)
                Money.Instance.Pay(sold);
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

    /// True if a step to `next` would put the worker inside the cart.  Walking into it no longer moves it:
    /// he has to take hold of an end (E) and push.
    public bool BlocksWalker(Vector3 next)
    {
        Vector3 local = transform.InverseTransformPoint(next);
        return Mathf.Abs(local.x) <= HalfWidth + 0.32f && Mathf.Abs(local.z) <= HalfLength + 0.34f;
    }

    // ---- being held and pushed.  An end is +1 (the end facing out of the mine) or -1 (the end facing in).
    const float StandOff = 0.85f;                      // how far off the end he stands, from the end, while holding it

    /// The end of the cart he could take hold of from here, or 0 if he is not close to either end.
    public int EndNear(Vector3 pos)
    {
        Vector3 local = transform.InverseTransformPoint(pos);
        if (Mathf.Abs(local.x) > HalfWidth + 0.6f) return 0;
        if (Mathf.Abs(local.z) < HalfLength - 0.1f || Mathf.Abs(local.z) > HalfLength + 1.6f) return 0;
        return local.z > 0f ? 1 : -1;
    }

    /// Where he stands to hold an end, and which way he then faces (towards the cart, along the track).
    public void HoldPlace(int end, out Vector3 at, out Vector3 facing)
    {
        Vector3 dir;
        Sample(Along + end * (HalfLength + StandOff), out at, out dir);
        dir.y = 0f;
        facing = -end * dir.normalized;
        at.y = world.FloorAt(at + Vector3.up * 0.5f);
    }

    /// The top of the end he is holding, where his hands go.
    public Vector3 HandHold(int end, float side) { return transform.TransformPoint(new Vector3(side * 0.3f, TubTop - 0.02f, end * (HalfLength + 0.03f))); }

    /// Rolls the cart along the track by up to `metres` (positive = more along the line, out of the mine).
    /// Returns how far it really went: it stops at the ends of the rails and at the cave-in face.
    public float Roll(float metres)
    {
        if (Mathf.Abs(metres) < 1e-6f) return 0f;
        float to = Mathf.Clamp(Along + metres * spec.pushFactor, HalfLength, length - HalfLength);
        if (Blocked(to, Mathf.Sign(metres))) return 0f;
        float went = to - Along;
        Along = to;
        Place();
        return went;
    }

    /// Would the cart, standing at `s`, have its leading end in something?  It rolls over low spill on the
    /// rails and only stops where the rubble is about as high as its tub (0.75 m), right at its end: so it
    /// goes all the way up to the cave-in face.
    public bool Blocked(float s, float way)
    {
        Vector3 lead, dir;
        Sample(s + way * (HalfLength + 0.04f), out lead, out dir);
        Vector3 here, d2;
        Sample(s, out here, out d2);
        lead.y = world.FloorAt(here + Vector3.up * 0.5f) + 0.75f;
        return world.MaterialAt(lead) != VoxelWorld.Air;
    }

    /// How far the cart could still roll that way before it stops (tests).
    public float RoomAhead(float way)
    {
        float s = Along;
        for (int i = 0; i < 400; i++)
        {
            float next = s + way * 0.02f;
            if (next < HalfLength || next > length - HalfLength || Blocked(next, way)) break;
            s = next;
        }
        return Mathf.Abs(s - Along);
    }

    // ---- the motor cart: riding and driving
    /// Drives the motor cart for one frame.  `throttle` is -1 (back into the mine) to +1 (out towards the dump).
    /// It speeds up and slows down at MotorAccel, and stops dead where pushing would stop.  Returns how far it went.
    public float Drive(float throttle, float dt)
    {
        if (!spec.motor || tipping) { motorVel = 0f; return 0f; }
        motorVel = Mathf.MoveTowards(motorVel, Mathf.Clamp(throttle, -1f, 1f) * spec.motorSpeed, MotorAccel * dt);
        if (Mathf.Abs(motorVel) < 1e-4f) return 0f;
        // backing in, he is on the footboard behind it: stop with room for him too, not just for the cart
        if (motorVel < 0f && Blocked(Along + motorVel * dt - (FootboardOut + 0.3f), -1f)) { motorVel = 0f; return 0f; }
        float went = Roll(motorVel * dt);
        if (Mathf.Abs(went) < 1e-6f) motorVel = 0f;                          // ran into something, or the end of the line
        return went;
    }

    /// How fast it is going under power now, metres a second (+ is out of the mine).
    public float MotorSpeedNow { get { return motorVel; } }
    public void StopMotor() { motorVel = 0f; }

    /// Where he stands while riding (on the footboard at the back end) and which way he faces (out of the mine).
    public void RidePlace(out Vector3 at, out Vector3 facing)
    {
        at = transform.TransformPoint(new Vector3(0f, FootboardHeight, -HalfLength - FootboardOut));
        facing = transform.forward;
    }

    /// Where his hands go while riding: on the push bar in front of him.
    public Vector3 RideHold(float side) { return transform.TransformPoint(new Vector3(side * 0.3f, TubTop + 0.02f, -HalfLength - 0.12f)); }

    public Vector3 Mouth { get { return transform.position + Vector3.up * (TubTop - 0.15f); } }
    public bool HasRoom { get { return world != null && world.CartVoxels < capacity - VoxelWorld.ClodVoxels; } }
}
