// You: the Digger Game's worker (same body, built from the same boxes and colours), with no tools, just a rifle
// that also fires rockets.
//
//   Tab (pad: Back)        flip between the two views
//   Over the shoulder:     mouse looks, W A S D walk relative to where you look, the cross in the middle is the aim
//   From above:            W A S D (left stick) move: W is always up the screen; the mouse (right stick) aims,
//                          and he shoots where you aim
//   Left mouse / right trigger    rifle (hold)
//   Right mouse / left trigger    rocket
//   Esc frees the mouse; click to take it back (over the shoulder).
//
// He runs at 6.5 m/s (Smashed's player speed), steps up anything under half a metre and drops down quickly, so he
// can run in and out of craters.
using System.Collections.Generic;
using UnityEngine;

public class ArenaPlayer : MonoBehaviour
{
    public static ArenaPlayer Instance { get; private set; }

    public float runSpeed = 6.5f;
    public float mouseSpeed = 2.4f;
    public float padAimSpeed = 160f;
    public const float BodyRadius = 0.3f;                    // Smashed's PLAYER_RADIUS

    [Header("Driven by script instead of the keyboard (tests and recordings)")]
    public bool useOverride;
    public Vector2 overrideMove;                             // x right, y ahead (shoulder) or up the screen (above)
    public Vector3 overrideAim;                              // a point in the world to aim at
    public bool overrideRifle, overrideRocket;
    [System.NonSerialized] public int queuedRifle, queuedRockets;   // shots asked for by a script: each fires once, on the next frame

    public bool Above { get; private set; }
    public float Stride { get; private set; }
    public Vector3 AimPoint { get; private set; }
    public Vector3 Muzzle { get { return gun != null ? gun.TransformPoint(new Vector3(0f, 0.03f, 0.78f)) : transform.position + Vector3.up * 1.35f; } }

    VoxelWorld world;
    FollowCamera cam;
    Transform model, legL, legR, armL, armR, gun, marker;
    float yaw, pitch = 8f, rifleT, rocketT;

    // ---------------------------------------------------------------- building him out of boxes (as Worker.cs does)
    const byte HiVis = 16, Navy = 17, Skin = 18, Hat = 19, Boot = 20, Steel = 23, Timber = 24;
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

    Transform Part(string name, Transform parent, Vector3 at)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent, false);
        go.transform.localPosition = at;
        var mesh = new Mesh();
        mesh.SetVertices(verts); mesh.SetNormals(normals); mesh.SetColors(colours); mesh.SetTriangles(tris, 0);
        mesh.RecalculateBounds();
        go.AddComponent<MeshFilter>().sharedMesh = mesh;
        go.AddComponent<MeshRenderer>().sharedMaterial = world.material;
        verts.Clear(); normals.Clear(); colours.Clear(); tris.Clear();
        return go.transform;
    }

    void BuildModel()
    {
        model = new GameObject("Model").transform;
        model.SetParent(transform, false);
        // the worker's body: boots to hard hat is about 1.8 m
        Box(new Vector3(0f, 1.15f, 0f), new Vector3(0.46f, 0.6f, 0.26f), HiVis);
        Box(new Vector3(0f, 1.02f, 0f), new Vector3(0.47f, 0.06f, 0.27f), Hat);          // reflective band
        Box(new Vector3(0f, 0.8f, 0f), new Vector3(0.42f, 0.14f, 0.24f), Navy);
        Box(new Vector3(0f, 1.58f, 0f), new Vector3(0.24f, 0.24f, 0.24f), Skin);
        Box(new Vector3(0f, 1.74f, 0f), new Vector3(0.3f, 0.1f, 0.3f), Hat);
        Box(new Vector3(0f, 1.7f, 0.1f), new Vector3(0.3f, 0.04f, 0.38f), Hat);          // brim
        Part("Body", model, Vector3.zero);
        for (int side = -1; side <= 1; side += 2)
        {
            Box(new Vector3(0f, -0.3f, 0f), new Vector3(0.18f, 0.6f, 0.2f), Navy);
            Box(new Vector3(0f, -0.67f, 0.03f), new Vector3(0.19f, 0.14f, 0.28f), Boot);
            var leg = Part(side < 0 ? "Leg L" : "Leg R", model, new Vector3(side * 0.12f, 0.74f, 0f));
            if (side < 0) legL = leg; else legR = leg;
            Box(new Vector3(0f, -0.2f, 0f), new Vector3(0.13f, 0.4f, 0.15f), HiVis);
            Box(new Vector3(0f, -0.48f, 0f), new Vector3(0.11f, 0.2f, 0.12f), Skin);
            var arm = Part(side < 0 ? "Arm L" : "Arm R", model, new Vector3(side * 0.3f, 1.4f, 0f));
            if (side < 0) armL = arm; else armR = arm;
        }
        // the gun: a steel body and barrel, a wooden stock, and a fat tube under it for the rockets
        Box(new Vector3(0f, 0f, 0.25f), new Vector3(0.08f, 0.12f, 0.42f), Steel);
        Box(new Vector3(0f, 0.03f, 0.6f), new Vector3(0.04f, 0.04f, 0.34f), Steel);
        Box(new Vector3(0f, -0.04f, -0.08f), new Vector3(0.07f, 0.14f, 0.26f), Timber);
        Box(new Vector3(0f, -0.1f, 0.45f), new Vector3(0.1f, 0.1f, 0.42f), Boot);
        Box(new Vector3(0f, -0.1f, 0.67f), new Vector3(0.12f, 0.12f, 0.04f), Steel);
        gun = Part("Gun", transform, new Vector3(0.18f, 1.32f, 0.2f));

        // where he is aiming, from above: a small bright block on the ground
        var m = GameObject.CreatePrimitive(PrimitiveType.Cube);
        m.name = "Aim marker";
        Destroy(m.GetComponent<Collider>());
        marker = m.transform;
        marker.localScale = new Vector3(0.3f, 0.06f, 0.3f);
        var mr = m.GetComponent<MeshRenderer>();
        mr.sharedMaterial = new Material(Shader.Find("Unlit/Color")) { color = new Color(1f, 0.85f, 0.2f) };
        mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        mr.receiveShadows = false;
        marker.gameObject.SetActive(false);
    }

    // ---------------------------------------------------------------- life
    void Awake() { Instance = this; }
    void OnDestroy()
    {
        if (Instance == this) Instance = null;
        if (Cursor.lockState != CursorLockMode.None) Cursor.lockState = CursorLockMode.None;
        if (marker != null) Destroy(marker.gameObject);
    }

    void Start()
    {
        world = VoxelWorld.Instance;
        cam = Camera.main != null ? Camera.main.GetComponent<FollowCamera>() : null;
        if (cam != null) cam.target = transform;
        BuildModel();
        Teleport(new Vector3(0f, 0f, -3f), 0f);
        SetAbove(false);
    }

    public void Teleport(Vector3 at, float facing)
    {
        at.y = world != null ? world.FloorAt(at + Vector3.up * 2f) : 0f;
        transform.SetPositionAndRotation(at, Quaternion.Euler(0f, facing, 0f));
        yaw = facing;
    }

    public void SetAbove(bool on)
    {
        Above = on;
        if (cam != null) cam.above = on;
        if (!useOverride) Cursor.lockState = on ? CursorLockMode.None : CursorLockMode.Locked;
        Cursor.visible = on || Cursor.lockState != CursorLockMode.Locked;
    }

    public void Look(float yawDeg, float pitchDeg) { yaw = yawDeg; pitch = pitchDeg; }

    static float Stronger(float a, float b) { return Mathf.Abs(b) > Mathf.Abs(a) ? b : a; }

    void Update()
    {
        if (world == null) return;
        float dt = Time.deltaTime;
        var game = ArenaGame.Instance;
        bool playing = game == null || game.Playing;
        Vector2 move;
        bool rifle, rocket;
        if (useOverride) { move = overrideMove; rifle = overrideRifle; rocket = overrideRocket; }
        else
        {
            move = new Vector2(Stronger(Input.GetAxisRaw("Horizontal"), Pad.LeftStick.x), Stronger(Input.GetAxisRaw("Vertical"), Pad.LeftStick.y));
            rifle = Input.GetMouseButton(0) || Pad.RT > 0.3f;
            rocket = Input.GetMouseButton(1) || Pad.LT > 0.3f;
            if (Input.GetKeyDown(KeyCode.Tab) || Pad.Down(Pad.B.Back)) SetAbove(!Above);
            if (Input.GetKeyDown(KeyCode.Escape)) { Cursor.lockState = CursorLockMode.None; Cursor.visible = true; }
            if (!Above && Cursor.lockState != CursorLockMode.Locked)
            {
                if (Input.GetMouseButtonDown(0)) { Cursor.lockState = CursorLockMode.Locked; Cursor.visible = false; }   // the first click just takes the mouse back
                rifle = rocket = false;
            }
        }
        if (move.sqrMagnitude > 1f) move.Normalize();
        if (!playing) { move = Vector2.zero; rifle = rocket = false; }

        // ---- aim
        Vector3 chest = transform.position + Vector3.up * 1.3f;
        if (useOverride) AimPoint = overrideAim;
        else if (Above) AimPoint = AboveAim(chest);
        else
        {
            Vector2 stick = Pad.RightStick;
            if (stick.magnitude > 0.12f) { stick *= stick.magnitude; yaw += stick.x * padAimSpeed * dt; pitch = Mathf.Clamp(pitch - stick.y * padAimSpeed * 0.7f * dt, -40f, 60f); }
            if (Cursor.lockState == CursorLockMode.Locked)
            {
                yaw += Input.GetAxis("Mouse X") * mouseSpeed;
                pitch = Mathf.Clamp(pitch - Input.GetAxis("Mouse Y") * mouseSpeed, -40f, 60f);
            }
            AimPoint = ShoulderAim(chest);
        }
        if (useOverride || Above)
        {
            Vector3 d = AimPoint - chest;
            if (new Vector2(d.x, d.z).sqrMagnitude > 0.04f)
            {
                yaw = Mathf.Atan2(d.x, d.z) * Mathf.Rad2Deg;
                pitch = Mathf.Clamp(-Mathf.Atan2(d.y, new Vector2(d.x, d.z).magnitude) * Mathf.Rad2Deg, -40f, 60f);
            }
        }

        // ---- moving: over the shoulder relative to where he looks, from above relative to the screen
        Vector3 mv = Above ? new Vector3(move.x, 0f, move.y) : Quaternion.Euler(0f, yaw, 0f) * new Vector3(move.x, 0f, move.y);
        mv *= runSpeed;
        Vector3 pos = transform.position;
        if (mv.sqrMagnitude > 0.0001f)
        {
            Vector3 step = mv * dt;
            if (!TryStep(ref pos, step) && !TryStep(ref pos, new Vector3(step.x, 0f, 0f))) TryStep(ref pos, new Vector3(0f, 0f, step.z));
            Stride += mv.magnitude * dt;
        }
        float floor = world.FloorAt(pos + Vector3.up * 0.45f);
        pos.y = floor > pos.y ? floor : Mathf.MoveTowards(pos.y, floor, 7f * dt);
        transform.SetPositionAndRotation(pos, Quaternion.Euler(0f, yaw, 0f));
        world.SlumpCentre = pos;
        if (cam != null) { cam.lookYaw = yaw; cam.lookPitch = pitch; }

        // ---- the gun points where he aims
        gun.localPosition = new Vector3(0.18f, 1.32f, 0.2f);
        Vector3 aimFrom = transform.TransformPoint(gun.localPosition);
        Vector3 look = AimPoint - aimFrom;
        if (look.sqrMagnitude > 0.25f) gun.rotation = Quaternion.LookRotation(look, Vector3.up);
        else gun.localRotation = Quaternion.Euler(pitch, 0f, 0f);

        // ---- shooting
        rifleT -= dt; rocketT -= dt;
        var w = Weapons.Instance;
        if (w != null)
        {
            if (rifle && rifleT <= 0f) { rifleT = Mathf.Max(rifleT + Weapons.RifleGap, 0f); w.FireRifle(Muzzle, AimPoint); gun.position -= gun.forward * 0.03f; }
            if (!rifle) rifleT = Mathf.Max(rifleT, 0f);
            if (queuedRifle > 0) { queuedRifle--; w.FireRifle(Muzzle, AimPoint); }
            if (queuedRockets > 0) { queuedRockets--; rocketT = Weapons.RocketGap; w.FireRocket(Muzzle + gun.up * -0.1f, AimPoint); }
            if (rocket && rocketT <= 0f) { rocketT = Weapons.RocketGap; w.FireRocket(Muzzle + gun.up * -0.1f, AimPoint); gun.position -= gun.forward * 0.08f; }
        }
        if (marker != null)
        {
            marker.gameObject.SetActive(Above && playing);
            if (Above) marker.position = AimPoint + Vector3.up * 0.04f;
        }
        Animate(mv.magnitude);
    }

    /// Over the shoulder: what the cross in the middle of the screen is on (ground, wall or a grunt).
    Vector3 ShoulderAim(Vector3 chest)
    {
        Vector3 from, dir;
        if (cam != null) { FollowCamera.Unshaken(cam.transform, out from, out dir); }
        else { from = transform.position + Vector3.up * 1.6f; dir = Quaternion.Euler(pitch, yaw, 0f) * Vector3.forward; }
        float skip = Mathf.Max(0f, Vector3.Dot(chest - from, dir) + 0.4f);   // start level with him, not behind him
        from += dir * skip;
        float max = Weapons.WallDistance(from, dir, Weapons.RifleRange);
        Vector3 hit; byte m;
        if (!world.Raycast(from, dir, max, out hit, out m)) hit = from + dir * max;
        float along;
        var g = Grunts.Instance;
        if (g != null && g.HitLine(from, hit, 0f, out along) >= 0) hit = from + (hit - from) * along;
        return hit;
    }

    /// From above: the point on the ground under the mouse (a grunt's chest if one is under it), or, on a pad, out
    /// along the right stick (or straight ahead when it is let go).
    Vector3 AboveAim(Vector3 chest)
    {
        Vector2 stick = Pad.RightStick;
        Vector3 from, dir;
        if (stick.magnitude > 0.25f || (Pad.InUse && cam != null))
        {
            Vector3 flat = stick.magnitude > 0.25f ? new Vector3(stick.x, 0f, stick.y).normalized : transform.forward;
            Vector3 at = transform.position + flat * 9f;
            at.y = world.FloorAt(at + Vector3.up * 2f) + 0.9f;
            return at;
        }
        var c = cam != null ? cam.GetComponent<Camera>() : Camera.main;
        if (c == null) return chest + transform.forward * 5f;
        Ray ray = c.ScreenPointToRay(Input.mousePosition);
        from = ray.origin; dir = ray.direction;
        Vector3 hit; byte m;
        if (!world.Raycast(from, dir, 80f, out hit, out m))
        {
            float t = dir.y < -1e-3f ? (transform.position.y - from.y) / dir.y : 30f;   // (off the ground: the floor's height round him)
            hit = from + dir * t;
        }
        float along;
        var g = Grunts.Instance;
        int who = g != null ? g.HitLine(from, hit, 0.1f, out along) : -1;
        if (who >= 0) return g.Position(who) + Vector3.up * 1f;
        return hit;
    }

    bool TryStep(ref Vector3 pos, Vector3 step)
    {
        if (step.sqrMagnitude < 1e-10f) return false;
        Vector3 next = pos + step;
        float lim = ArenaGame.Half - BodyRadius - 0.05f;
        if (Mathf.Abs(next.x) > lim || Mathf.Abs(next.z) > lim) return false;
        Vector3 ahead = next + step.normalized * 0.22f;
        float floor = Mathf.Max(world.FloorAt(next + Vector3.up * 0.45f), world.FloorAt(ahead + Vector3.up * 0.45f));
        if (floor - pos.y > 0.5f) return false;                                          // too high to step up
        pos = next;
        return true;
    }

    void Animate(float speed)
    {
        if (model == null) return;
        float s = Mathf.Sin(Stride * 2.6f) * Mathf.Clamp01(speed / 3f) * 40f;
        legL.localRotation = Quaternion.Euler(s, 0f, 0f);
        legR.localRotation = Quaternion.Euler(-s, 0f, 0f);
        // both hands on the gun: right on the grip, left out on the fore-end
        Reach(armR, gun.TransformPoint(new Vector3(0f, -0.05f, 0.02f)));
        Reach(armL, gun.TransformPoint(new Vector3(0f, -0.06f, 0.42f)));
        // in the shoulder view he would fill the screen when the camera tucks in close: hide him then
        if (cam != null && !Above)
        {
            bool close = Vector3.Distance(cam.transform.position, transform.position + Vector3.up * 1.4f) < 0.9f;
            if (model.gameObject.activeSelf == close) model.gameObject.SetActive(!close);
        }
        else if (!model.gameObject.activeSelf) model.gameObject.SetActive(true);
    }

    void Reach(Transform arm, Vector3 worldTarget)
    {
        Vector3 local = arm.parent.InverseTransformPoint(worldTarget) - arm.localPosition;
        if (local.sqrMagnitude > 1e-6f) arm.localRotation = Quaternion.FromToRotation(Vector3.down, local.normalized);
    }
}
