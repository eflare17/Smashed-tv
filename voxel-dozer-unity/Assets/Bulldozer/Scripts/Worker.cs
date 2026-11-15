// The worker: the person you play as on foot.
//
//   Mouse            look about (both views).  Esc frees the mouse; click to take it back.
//   W / S / A / D    walk: forward, back, and step sideways, relative to where you are looking
//   Tab              switch between the view over his shoulder and the view through his eyes
//   1 / 2 / 3        pick / shovel / backpack nozzle
//   Left mouse or Space   use the tool (hold to keep going; the nozzle sucks while you hold it)
//   Q                squirt the backpack's load into the cart (stand near it)
//   Enter            get into the dozer, or out of it
//   E                pick up a dozer part you have dug out, or fit one you are carrying (at the dozer);
//                    at an end of the cart, take hold of it (then W pushes, S pulls back, E lets go)
//   F5 / F6          save the game / load it
//
// The tool works exactly where you aim.  The cross in the middle of the screen is the aim, and a small
// marker sits on the ground at the spot the tool will hit: yellow when it is in reach, red when it is not.
//
// The pick breaks ground into loose rubble.  The shovel digs a load and, used again, throws it.
// The backpack (on his back all the time) sucks up loose dirt and rubble through its nozzle, up to 500 litres,
// and squirts it back out into the cart.  It never takes firm ground or rock: those need the pick first.
// Each use is a real swing: the tool moves through a set of poses, and the dirt comes out of the ground
// (or leaves the shovel) at the moment in the swing when it should.  The tool is held in front of him in
// both views, so you see it working through his eyes as well.
using System.Collections.Generic;
using UnityEngine;

public class Worker : MonoBehaviour
{
    public static Worker Instance { get; private set; }

    public float walkSpeed = 2.6f;           // metres a second
    public float backSpeed = 1.6f;
    public float pushSpeed = 2.0f;           // pushing the cart
    public float turnSpeed = 170f;           // degrees a second, for scripted turning only
    public float mouseSpeed = 2.4f;
    public float reach = 2.4f;               // how far from his chest the tools reach
    public float pickRadius = 0.26f;
    public float scoopRadius = 0.38f;
    public int shovelHolds = 480;            // voxels: about 0.12 cubic metres
    // set by the upgrade tree (Upgrades.cs)
    [System.NonSerialized] public float pickRockFactor = 0.8f;   // how much of the pick's chunk breaks on rock
    [System.NonSerialized] public float shovelSpeed = 1f;        // shovel swings run this much faster
    [System.NonSerialized] public bool backpackOwned = true;      // until the tree says otherwise
    public float throwForward = 5.2f;        // metres a second: how hard a shovelful is thrown
    public float throwUp = 2.8f;
    public int packHolds = 2048;             // voxels: 500 litres, half the hand cart
    public float suckReach = 1.5f;           // metres out from the nozzle
    public float suckRate = 260f;            // voxels a second it lifts off the ground (about 63 litres)
    public float suckSpeed = 7f;             // metres a second the bits fly into the nozzle
    public float pourRate = 900f;            // voxels a second it squirts out (about 220 litres)

    [Header("Driven by script instead of the keyboard (tests and recordings)")]
    public bool useOverride;
    public float overrideWalk, overrideTurn;
    public bool overrideUse;

    public bool InDozer { get; private set; }
    public int HoldingCart { get; private set; }         // 0, or which end of the cart he has hold of (+1 / -1)
    float leanIn;                                        // 0..1: how hard he is leaning into the cart
    public int Tool { get; private set; }                // 0 pick, 1 shovel
    public bool Eyes { get; private set; }               // looking through his eyes
    public int PickHits { get; private set; }
    public int Scoops { get; private set; }
    public int Throws { get; private set; }
    public int Sucked { get; private set; }              // voxels that have gone into the backpack, all told
    public bool Pouring { get; private set; }            // squirting the backpack into the cart

    VoxelWorld world;
    DozerController dozer;
    FollowCamera cam;
    Transform model, legL, legR, armL, armR, hold, pick, shovel, shovelDirt, marker, nozzle, hose;
    readonly Transform[] hoseBits = new Transform[12];
    float suckAcc, pourAcc, hintTimer;
    int pourCartStart, poured;
    Material markerMat;
    float yaw, lookPitch = 14f, stride, sayTimer;
    string say = "";

    // what he is aiming at, worked out every frame
    Vector3 aimPoint, aimDir;
    byte aimMat;
    bool aimFound, aimInReach;

    // a swing in progress
    enum Swing { None, Dig, Throw, Pick }
    Swing swing = Swing.None;
    float swingT;
    bool swingDone;
    bool throwBehind;                                    // this throw goes back over his shoulder
    Vector3 throwAt;                                     // where this throw is meant to land
    bool throwIntoCart;
    bool hitCart;                                        // the last step bumped into the cart

    // ---------------------------------------------------------------- the swings
    // A pose is where the tool is held, relative to his chest (or his eyes): position, then tilt / swing / roll in degrees.
    // The tool's handle runs forward from the hand; tilt points it down.
    struct Pose
    {
        public Vector3 at, turn;
        public Pose(float x, float y, float z, float tilt, float swing, float roll) { at = new Vector3(x, y, z); turn = new Vector3(tilt, swing, roll); }
        public static Pose Mix(Pose a, Pose b, float t)
        {
            t = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01(t));
            return new Pose { at = Vector3.Lerp(a.at, b.at, t), turn = new Vector3(Mathf.LerpAngle(a.turn.x, b.turn.x, t), Mathf.LerpAngle(a.turn.y, b.turn.y, t), Mathf.LerpAngle(a.turn.z, b.turn.z, t)) };
        }
    }
    // shovel
    static readonly Pose ShovelCarry = new Pose(0.26f, -0.50f, 0.10f, 30f, -8f, 0f);     // empty, blade low in front
    static readonly Pose ShovelThrust = new Pose(0.20f, -0.58f, 0.50f, 58f, 0f, 0f);     // driven down into the dirt
    static readonly Pose ShovelLoaded = new Pose(0.24f, -0.46f, 0.22f, 6f, -6f, 0f);     // levered up, blade flat, carrying
    static readonly Pose ShovelBack = new Pose(0.40f, -0.50f, -0.08f, 16f, 42f, -18f);   // wound back to his right
    static readonly Pose ShovelFling = new Pose(0.02f, -0.22f, 0.62f, -38f, -22f, 10f);  // flicked up and out in front
    static readonly Pose ShovelOver = new Pose(-0.12f, 0.20f, -0.02f, -128f, 18f, 0f);   // swung up and back over his shoulder
    const float DigBite = 0.15f, DigTime = 0.36f, ThrowWind = 0.13f, ThrowRelease = 0.22f, ThrowTime = 0.42f;
    // pick
    static readonly Pose PickCarry = new Pose(0.26f, -0.40f, 0.10f, -35f, 0f, 0f);       // head up by his shoulder
    static readonly Pose PickHigh = new Pose(0.24f, -0.02f, -0.12f, -118f, 0f, 0f);      // raised over his head
    static readonly Pose PickStrike = new Pose(0.18f, -0.52f, 0.46f, 44f, 0f, 0f);       // driven into the face
    const float PickRaise = 0.16f, PickBite = 0.25f, PickTime = 0.44f;
    // the backpack's nozzle: held low in front, two hands; it is then turned to point where you aim
    static readonly Pose NozzleHold = new Pose(0.2f, -0.42f, 0.2f, 22f, -6f, 0f);
    static readonly Vector3 NozzleTip = new Vector3(0f, 0f, 0.95f);

    Pose CurrentPose()
    {
        bool loaded = world.ShovelVoxels >= VoxelWorld.ClodVoxels;
        switch (swing)
        {
            case Swing.Dig:
                if (swingT < DigBite) return Pose.Mix(ShovelCarry, ShovelThrust, swingT / DigBite);
                return Pose.Mix(ShovelThrust, ShovelLoaded, (swingT - DigBite) / (DigTime - DigBite));
            case Swing.Throw:
                if (swingT < ThrowWind) return Pose.Mix(ShovelLoaded, ShovelBack, swingT / ThrowWind);
                Pose end = throwBehind ? ShovelOver : ShovelFling;
                if (swingT < ThrowRelease) return Pose.Mix(throwBehind ? ShovelLoaded : ShovelBack, end, (swingT - ThrowWind) / (ThrowRelease - ThrowWind));
                return Pose.Mix(end, ShovelCarry, (swingT - ThrowRelease) / (ThrowTime - ThrowRelease));
            case Swing.Pick:
                if (swingT < PickRaise) return Pose.Mix(PickCarry, PickHigh, swingT / PickRaise);
                if (swingT < PickBite) return Pose.Mix(PickHigh, PickStrike, (swingT - PickRaise) / (PickBite - PickRaise));
                return Pose.Mix(PickStrike, PickCarry, (swingT - PickBite) / (PickTime - PickBite));
        }
        if (Tool == 2) return NozzleHold;
        return Tool == 0 ? PickCarry : (loaded ? ShovelLoaded : ShovelCarry);
    }

    // ---------------------------------------------------------------- building him out of boxes
    // The tools use their own wood (24) and the finds' steel (23), not the scenery's timber and steel (11, 13):
    // scenery colours are cut away between the camera and him, which used to make the tools vanish.
    const byte HiVis = 16, Navy = 17, Skin = 18, Hat = 19, Boot = 20, Timber = 24, Steel = 23, Dirt = 6;
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
        // body: boots to hard hat is about 1.8 m.  Limbs are their own parts, hinged at the hip and shoulder.
        Box(new Vector3(0f, 1.15f, 0f), new Vector3(0.46f, 0.6f, 0.26f), HiVis);
        Box(new Vector3(0f, 1.02f, 0f), new Vector3(0.47f, 0.06f, 0.27f), Hat);          // reflective band
        Box(new Vector3(0f, 0.8f, 0f), new Vector3(0.42f, 0.14f, 0.24f), Navy);
        Box(new Vector3(0f, 1.58f, 0f), new Vector3(0.24f, 0.24f, 0.24f), Skin);
        Box(new Vector3(0f, 1.74f, 0f), new Vector3(0.3f, 0.1f, 0.3f), Hat);
        Box(new Vector3(0f, 1.7f, 0.1f), new Vector3(0.3f, 0.04f, 0.38f), Hat);          // brim
        Part("Body", model, Vector3.zero);
        // the backpack: a dark tank on his back with a steel cap, and the hose outlet low on its right
        Box(new Vector3(0f, 1.18f, -0.25f), new Vector3(0.38f, 0.52f, 0.22f), Boot);
        Box(new Vector3(0f, 1.47f, -0.25f), new Vector3(0.18f, 0.06f, 0.16f), Steel);
        Box(new Vector3(0f, 1.18f, -0.365f), new Vector3(0.3f, 0.06f, 0.02f), HiVis);    // a bright band round it
        Box(new Vector3(0.14f, 0.96f, -0.3f), new Vector3(0.09f, 0.09f, 0.09f), Steel);  // outlet
        Part("Backpack", model, Vector3.zero);
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

        // The tools.  They hang off "hold", a point at his chest (or his eyes, in the eyes view), not off an arm,
        // so they can be posed exactly; the arms then reach for the handle.  A tool's handle runs along +z from the hand.
        hold = new GameObject("Hold").transform;
        hold.SetParent(transform, false);
        Box(new Vector3(0f, 0f, 0.42f), new Vector3(0.05f, 0.05f, 0.9f), Timber);
        Box(new Vector3(0f, 0f, 0.84f), new Vector3(0.07f, 0.56f, 0.08f), Steel);
        Box(new Vector3(0f, 0.3f, 0.8f), new Vector3(0.05f, 0.1f, 0.06f), Steel);
        Box(new Vector3(0f, -0.3f, 0.8f), new Vector3(0.05f, 0.1f, 0.06f), Steel);
        pick = Part("Pick", hold, Vector3.zero);
        Box(new Vector3(0f, 0f, 0.42f), new Vector3(0.045f, 0.045f, 0.9f), Timber);
        Box(new Vector3(0f, 0.035f, 0.02f), new Vector3(0.16f, 0.04f, 0.05f), Timber);    // D handle
        Box(new Vector3(0f, -0.015f, 1.04f), new Vector3(0.26f, 0.025f, 0.34f), Steel);
        Box(new Vector3(0.125f, 0.0f, 1.04f), new Vector3(0.02f, 0.05f, 0.32f), Steel);   // turned-up edges
        Box(new Vector3(-0.125f, 0.0f, 1.04f), new Vector3(0.02f, 0.05f, 0.32f), Steel);
        shovel = Part("Shovel", hold, Vector3.zero);
        // the load of dirt that sits on the blade while he is carrying one
        Box(new Vector3(0f, 0.04f, 1.03f), new Vector3(0.22f, 0.07f, 0.28f), Dirt);
        Box(new Vector3(0.02f, 0.1f, 1.0f), new Vector3(0.15f, 0.07f, 0.2f), Dirt);
        Box(new Vector3(-0.03f, 0.15f, 1.02f), new Vector3(0.08f, 0.05f, 0.1f), Dirt);
        shovelDirt = Part("Shovel load", shovel, Vector3.zero);
        shovelDirt.gameObject.SetActive(false);
        shovel.gameObject.SetActive(false);
        // the nozzle: a steel tube with a grip, and a wider mouth at the end
        Box(new Vector3(0f, 0f, 0.46f), new Vector3(0.07f, 0.07f, 0.84f), Steel);
        Box(new Vector3(0f, -0.07f, 0.16f), new Vector3(0.05f, 0.14f, 0.05f), Timber);    // grip
        Box(new Vector3(0f, 0f, 0.9f), new Vector3(0.17f, 0.12f, 0.1f), Steel);
        Box(new Vector3(0f, 0f, 0.06f), new Vector3(0.1f, 0.1f, 0.1f), Steel);            // where the hose joins
        nozzle = Part("Nozzle", hold, Vector3.zero);
        nozzle.gameObject.SetActive(false);
        // the hose from the backpack to the nozzle, in short pieces laid along a sagging curve each frame
        hose = new GameObject("Hose").transform;
        hose.SetParent(transform, false);
        for (int i = 0; i < hoseBits.Length; i++)
        {
            Box(Vector3.zero, new Vector3(0.05f, 0.05f, 1f), Boot);
            hoseBits[i] = Part("Hose " + i, hose, Vector3.zero);
        }
        hose.gameObject.SetActive(false);

        // the aim marker: a small bright block that sits on whatever the tool will hit
        var m = GameObject.CreatePrimitive(PrimitiveType.Cube);
        m.name = "Aim marker";
        Destroy(m.GetComponent<Collider>());
        marker = m.transform;
        marker.SetParent(transform.parent, false);
        marker.localScale = Vector3.one * 0.11f;
        markerMat = new Material(Shader.Find("Unlit/Color"));
        var mr = m.GetComponent<MeshRenderer>();
        mr.sharedMaterial = markerMat;
        mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        mr.receiveShadows = false;
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
        dozer = FindFirstObjectByType<DozerController>();
        cam = Camera.main != null ? Camera.main.GetComponent<FollowCamera>() : null;
        BuildModel();
        Vector3 start = dozer != null ? dozer.transform.position + new Vector3(-4.5f, 0f, -2.5f) : new Vector3(-4.5f, 0f, -18.5f);
        Teleport(start, 20f);
        OnFootCamera();
        // For now the game starts with you in the dozer, ready to drive.  Enter gets out to go on foot.
        if (dozer != null && !dozer.dead) { GetIn(); Say("Enter gets out of the dozer to go on foot.", 7f); }
        else Say("The mine caved in years ago.  Tab switches view.  1 pick, 2 shovel.", 9f);
    }

    public void Teleport(Vector3 at, float facing)
    {
        at.y = world.FloorAt(at + Vector3.up * 0.6f);
        transform.position = at;
        yaw = facing;
        transform.rotation = Quaternion.Euler(0f, yaw, 0f);
        if (cam != null) { cam.lookYaw = yaw; cam.lookPitch = lookPitch; }
    }

    void OnFootCamera()
    {
        if (cam == null) return;
        cam.Follow(transform, 3.2f, 1.6f, 8f, 1.55f, 18f, 0f);
        cam.firstPerson = Eyes;
        cam.shoulder = !Eyes;
        cam.lookYaw = yaw; cam.lookPitch = lookPitch;
    }

    public void SetEyes(bool on)
    {
        Eyes = on;
        if (cam != null && !InDozer) { cam.firstPerson = on; cam.shoulder = !on; cam.lookYaw = yaw; cam.lookPitch = lookPitch; }
        if (!useOverride) Cursor.lockState = InDozer ? CursorLockMode.None : CursorLockMode.Locked;
        if (model != null) model.gameObject.SetActive(!on && !InDozer);
    }

    public void SetTool(int tool)
    {
        if (tool == 2 && !backpackOwned) tool = 1;
        Tool = tool;
        swing = Swing.None;
        pick.gameObject.SetActive(tool == 0);
        shovel.gameObject.SetActive(tool == 1);
        nozzle.gameObject.SetActive(tool == 2);
    }

    public void Say(string text, float seconds = 4f) { say = text; sayTimer = seconds; }

    public void WriteState(System.IO.BinaryWriter w)
    {
        Vector3 p = transform.position;
        w.Write(p.x); w.Write(p.y); w.Write(p.z);
        w.Write(yaw); w.Write(lookPitch);
        w.Write(Tool); w.Write(Eyes); w.Write(InDozer);
    }

    public void ReadState(System.IO.BinaryReader r)
    {
        Vector3 p = new Vector3(r.ReadSingle(), r.ReadSingle(), r.ReadSingle());
        float y = r.ReadSingle(), pitch = r.ReadSingle();
        int tool = r.ReadInt32();
        bool eyes = r.ReadBoolean(), inDozer = r.ReadBoolean();
        swing = Swing.None;
        LetGo();
        Pouring = false;
        SetTool(tool);
        if (inDozer)
        {
            if (!InDozer) GetIn();
        }
        else
        {
            if (InDozer)
            {
                InDozer = false;
                if (dozer != null) dozer.driven = false;
                hold.gameObject.SetActive(true);
                OnFootCamera();
            }
            transform.position = p;
            yaw = y;
            transform.rotation = Quaternion.Euler(0f, yaw, 0f);
            SetEyes(eyes);
            Look(pitch);
        }
        Eyes = eyes;
    }

    /// Sets how far up or down he is looking (tests and recordings).
    public void Look(float pitch) { lookPitch = pitch; if (cam != null) cam.lookPitch = pitch; }

    public void GetIn()
    {
        if (dozer == null) return;
        LetGo();
        InDozer = true;
        dozer.driven = true;
        model.gameObject.SetActive(false);
        hold.gameObject.SetActive(false);
        if (marker != null) marker.gameObject.SetActive(false);
        Cursor.lockState = CursorLockMode.None;
        if (cam != null) { cam.Follow(dozer.transform, 13f, 6f, 40f, 1.8f, 22f, 25f); cam.turnFollow = 2f; }
    }

    public void GetOut()
    {
        if (dozer == null) return;
        InDozer = false;
        dozer.driven = false;
        hold.gameObject.SetActive(true);
        Teleport(dozer.transform.position - dozer.transform.right * 3.4f, dozer.transform.eulerAngles.y);
        OnFootCamera();
        SetEyes(Eyes);
    }

    void Update()
    {
        if (sayTimer > 0f) sayTimer -= Time.unscaledDeltaTime;
        if (world == null) return;
        if (!useOverride)
        {
            // for trying things out before repairs are in the game: F9 breaks or fixes the dozer
            if (Input.GetKeyDown(KeyCode.F9) && dozer != null)
            {
                dozer.dead = !dozer.dead;
                Say(dozer.dead ? "Dozer set to dead (test key).  Dig its parts out of the mine and fit them." : "Dozer working again (test key).");
            }
            if (Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.KeypadEnter)) { LetGo(); TryDozer(); }
        }
        if (InDozer) { transform.position = dozer.transform.position; return; }

        float dt = Time.deltaTime;
        float walk = useOverride ? overrideWalk : Input.GetAxisRaw("Vertical");
        float side = useOverride ? 0f : Input.GetAxisRaw("Horizontal");
        bool use = useOverride ? overrideUse : (Input.GetMouseButton(0) || Input.GetKey(KeyCode.Space));
        bool treeOpen = !useOverride && Upgrades.Instance != null && Upgrades.Instance.Open;
        if (treeOpen) { walk = 0f; side = 0f; use = false; }
        if (!useOverride && !treeOpen)
        {
            if (Input.GetKeyDown(KeyCode.Tab)) SetEyes(!Eyes);
            if (Input.GetKeyDown(KeyCode.Alpha1)) SetTool(0);
            if (Input.GetKeyDown(KeyCode.Alpha2)) SetTool(1);
            if (Input.GetKeyDown(KeyCode.Alpha3)) { if (backpackOwned) SetTool(2); else Say("No backpack yet.  Max out the shovel, then buy it in the upgrades (U).", 3f); }
            if (Input.GetKeyDown(KeyCode.Q)) { if (backpackOwned) StartPour(); }
            if (Input.GetKeyDown(KeyCode.E)) PressE();
            if (Input.GetKeyDown(KeyCode.T)) TipCart();
            if (Input.GetKeyDown(KeyCode.Escape)) Cursor.lockState = CursorLockMode.None;
            if (Cursor.lockState != CursorLockMode.Locked)
            {
                if (Input.GetMouseButtonDown(0)) Cursor.lockState = CursorLockMode.Locked;   // the first click just takes the mouse back
                if (Input.GetMouseButton(0)) use = Input.GetKey(KeyCode.Space);
            }
            else
            {
                yaw += Input.GetAxis("Mouse X") * mouseSpeed;
                lookPitch = Mathf.Clamp(lookPitch - Input.GetAxis("Mouse Y") * mouseSpeed, Eyes ? -80f : -45f, Eyes ? 80f : 72f);
            }
        }
        else yaw += overrideTurn * turnSpeed * dt;

        if (hintTimer > 0f) hintTimer -= dt;
        if (HoldingCart != 0) { PushCart(dt, walk); return; }

        // ---- moving: he faces where you look, and walks relative to that
        Vector3 move = Quaternion.Euler(0f, yaw, 0f) * new Vector3(side * 0.85f, 0f, walk);
        move *= walk >= 0f ? walkSpeed : backSpeed;
        if (swing != Swing.None) move *= 0.35f;                                            // he plants his feet to swing
        Vector3 pos = transform.position;
        if (move.sqrMagnitude > 0.0001f)
        {
            Vector3 step = move * dt;
            // if the full step is blocked, try sliding along x or z alone, but not when it was the cart that stopped
            // him: he has just pushed it, and pushing it again on each slide would shove it three times as far
            hitCart = false;
            if (!TryStep(ref pos, step) && !hitCart && !TryStep(ref pos, new Vector3(step.x, 0f, 0f)) && !hitCart)
                TryStep(ref pos, new Vector3(0f, 0f, step.z));
            stride += move.magnitude * dt;
        }
        float floor = world.FloorAt(pos + Vector3.up * 0.45f);
        pos.y = floor > pos.y ? floor : Mathf.MoveTowards(pos.y, floor, 6f * dt);       // steps up at once, drops down quickly
        transform.SetPositionAndRotation(pos, Quaternion.Euler(0f, yaw, 0f));
        world.SlumpCentre = pos;
        if (cam != null) { cam.lookYaw = yaw; cam.lookPitch = lookPitch; }

        TakeAim();

        // ---- the backpack: it sucks while you hold the button, and squirts into the cart after Q
        if (Tool == 2)
        {
            if (Pouring) Pour(dt);
            else if (use) Suck(dt);
            else suckAcc = 0f;
            Animate(move.magnitude);
            return;
        }
        Pouring = false;

        // ---- the tools: start a swing, then let it run; the work happens part way through it
        if (swing == Swing.None && use)
        {
            swing = Tool == 0 ? Swing.Pick : (world.ShovelVoxels >= VoxelWorld.ClodVoxels ? Swing.Throw : Swing.Dig);
            swingT = 0f; swingDone = false;
            if (swing == Swing.Throw) PlanThrow();
        }
        if (swing != Swing.None)
        {
            swingT += dt * (swing == Swing.Pick ? 1f : shovelSpeed);
            float bite = swing == Swing.Dig ? DigBite : swing == Swing.Throw ? ThrowRelease : PickBite;
            float length = swing == Swing.Dig ? DigTime : swing == Swing.Throw ? ThrowTime : PickTime;
            if (!swingDone && swingT >= bite) { swingDone = true; Work(); }
            if (swingT >= length) swing = Swing.None;
        }
        Animate(move.magnitude);
    }

    bool TryStep(ref Vector3 pos, Vector3 step)
    {
        if (step.sqrMagnitude < 1e-10f) return false;
        Vector3 next = pos + step;
        float lim = VoxelWorld.NX / 2 * VoxelWorld.Voxel - 1.2f;
        if (Mathf.Abs(next.x) > lim || Mathf.Abs(next.z) > lim) return false;
        if (SiteProps.Blocks(next, 0.3f, true)) return false;
        if (MineCart.Instance != null && MineCart.Instance.BlocksWalker(next)) return false;   // the cart is in the way (E at an end takes hold of it)
        // look a little ahead as well, so he stops at a wall instead of walking his nose into it
        Vector3 ahead = next + step.normalized * 0.22f;
        float floor = Mathf.Max(world.FloorAt(next + Vector3.up * 0.45f), world.FloorAt(ahead + Vector3.up * 0.45f));
        if (floor - pos.y > 0.5f) return false;                                          // too high to step up
        if (world.MaterialAt(new Vector3(next.x, Mathf.Max(floor, pos.y) + 1.5f, next.z)) != VoxelWorld.Air) return false;   // no head room
        pos = next;
        return true;
    }

    /// Works out exactly what the cross in the middle of the screen is on, and whether he can reach it.
    /// The line starts at the camera and runs the way the camera looks, so what you see under the cross is
    /// what the tool hits.  (From over his shoulder, the part of that line behind him is skipped.)
    void TakeAim()
    {
        Vector3 chest = transform.position + Vector3.up * 1.3f;
        Vector3 from, dir;
        if (cam != null && !useOverride) { from = cam.transform.position; dir = cam.transform.forward; }
        else { from = transform.position + Vector3.up * 1.6f; dir = Quaternion.Euler(lookPitch, yaw, 0f) * Vector3.forward; }
        float skip = Mathf.Max(0f, Vector3.Dot(chest - from, dir) - 0.25f);              // start level with him, not behind him
        from += dir * skip;
        aimDir = dir;
        aimFound = world.Raycast(from, dir, reach + 1.2f, out aimPoint, out aimMat);
        aimInReach = aimFound && Vector3.Distance(aimPoint, chest) <= reach;
        if (marker != null)
        {
            marker.gameObject.SetActive(aimFound);
            if (aimFound)
            {
                marker.position = aimPoint - dir * 0.04f;
                marker.rotation = Quaternion.identity;
                markerMat.color = aimInReach ? new Color(1f, 0.9f, 0.2f) : new Color(1f, 0.25f, 0.2f);
            }
        }
    }

    /// Decides where a shovelful goes.  Into the cart if one is close and has room; otherwise onto a pile a
    /// couple of metres behind him, out of the way of what he is digging.
    void PlanThrow()
    {
        Vector3 back = Quaternion.Euler(0f, yaw, 0f) * Vector3.back;
        var cart = MineCart.Instance;
        throwIntoCart = cart != null && cart.HasRoom && cart.Near(transform.position, 7.5f);
        throwAt = throwIntoCart ? cart.Mouth : transform.position + back * 2.6f + Quaternion.Euler(0f, yaw, 0f) * Vector3.right * 0.5f;
        throwBehind = Vector3.Dot(throwAt - transform.position, back) > 0f;
    }

    /// The moment in a swing when the tool does its job, at the spot being aimed at.
    void Work()
    {
        bool rock = aimMat >= VoxelWorld.Rock && aimMat <= VoxelWorld.Gold;
        if (swing == Swing.Pick)
        {
            if (aimInReach && world.Pick(aimPoint + aimDir * 0.1f, rock ? pickRadius * pickRockFactor : pickRadius, -aimDir * 1.3f + Vector3.up * 0.9f) > 0) PickHits++;
            else if (aimFound && !aimInReach) Say("Too far away.  Get closer.", 1.5f);
        }
        else if (swing == Swing.Dig)
        {
            if (!aimInReach) { if (aimFound) Say("Too far away.  Get closer.", 1.5f); return; }
            if (world.Scoop(aimPoint + aimDir * 0.06f, scoopRadius, shovelHolds) > 0) Scoops++;
            else if (rock) Say("Solid rock.  Break it up with the pick first (1).", 2.5f);
        }
        else if (swing == Swing.Throw)
        {
            // It leaves from above his shoulder and is lobbed to land where PlanThrow chose: into the cart,
            // or onto the pile behind him.  The speed is worked out from where it has to come down.
            Vector3 from = transform.position + Vector3.up * 1.75f + Quaternion.Euler(0f, yaw, 0f) * (throwBehind ? new Vector3(-0.1f, 0f, -0.35f) : new Vector3(0.1f, 0f, 0.6f));
            Vector3 gap = throwAt - from;
            // a flat, quick throw: in the mine a high lob would hit the roof
            float time = Mathf.Clamp(new Vector2(gap.x, gap.z).magnitude / 6.8f, 0.5f, 0.95f);
            Vector3 velocity = gap / time + Vector3.up * (0.5f * 9.81f * time);
            world.Throw(from, velocity, throwIntoCart ? 0.3f : 0.8f, time + 0.08f);
            Throws++;
        }
    }

    /// Where the nozzle's mouth is now.
    public Vector3 NozzleMouth { get { return nozzle.TransformPoint(NozzleTip); } }

    void Hint(string text)
    {
        if (hintTimer > 0f) return;
        Say(text, 2.5f);
        hintTimer = 3f;
    }

    /// One frame of sucking: loose dirt where you aim lets go and flies into the nozzle, along with any loose
    /// clods near the line of the nozzle, until the backpack is full.
    void Suck(float dt)
    {
        int room = packHolds - world.PackVoxels;
        if (room < VoxelWorld.ClodVoxels) { suckAcc = 0f; Hint("The backpack is full.  Stand by the cart and press Q to squirt it in."); return; }
        Vector3 mouth = NozzleMouth;
        Vector3 reachTo = aimFound ? aimPoint : mouth + aimDir * suckReach;
        bool inReach = aimFound && Vector3.Distance(aimPoint, mouth) <= suckReach;
        if (inReach)
        {
            suckAcc += suckRate * dt;
            int most = Mathf.Min((int)suckAcc, room);
            if (most >= VoxelWorld.ClodVoxels)
            {
                suckAcc -= most;
                int got = world.SuckLoose(aimPoint + aimDir * 0.05f, 0.3f, most, (mouth - aimPoint).normalized * 3f);
                if (got == 0 && aimMat < VoxelWorld.LooseSoil) Hint("It only sucks up loose dirt.  Break the ground up with the pick (1) first.");
            }
        }
        else
        {
            suckAcc = 0f;
            if (aimFound) Hint("Too far away for the nozzle.  Get closer.");
        }
        int took = world.SuckPull(mouth, reachTo, 0.45f, suckSpeed, dt, room);
        Sucked += took;
    }

    /// Standing at the gold buyer's counter.
    public bool AtGoldShed()
    {
        return !InDozer && SiteProps.GoldShedFront != Vector3.zero
            && Vector3.Distance(new Vector3(transform.position.x, 0f, transform.position.z), new Vector3(SiteProps.GoldShedFront.x, 0f, SiteProps.GoldShedFront.z)) <= 1.8f;
    }

    /// E at the counter: the gold buyer takes all your gold for coins.
    public long SellGold()
    {
        var money = Money.Instance;
        if (money == null) return 0;
        if (money.GoldStore <= 0) { Say("You have no gold to sell.  Gold you dig out is kept when the hopper sorts it.", 3f); return 0; }
        return money.SellGold();
    }

    /// T beside the cart: tip it out.  At the dump that gets paid; anywhere else it is just emptied.
    public void TipCart()
    {
        var cart = MineCart.Instance;
        if (cart == null || InDozer || !cart.Near(transform.position, 3f)) return;
        if (world.CartVoxels < VoxelWorld.ClodVoxels) { Say("The cart is empty.", 2f); return; }
        cart.Tip();
        Say(cart.AtDump ? "Into the hopper: it's sorted and sold as it goes down." : "Tipped here, so no pay.  Push the cart to the end of the rails and press E to tip it into the hopper.", 3.5f);
    }

    /// Q: start squirting the backpack into the cart, if he is near enough to it.
    public void StartPour()
    {
        if (InDozer) return;
        var cart = MineCart.Instance;
        if (world.PackVoxels < VoxelWorld.ClodVoxels) { Say("The backpack is empty.", 2f); return; }
        if (HoldingCart != 0) { Say("Let go of the cart first (E).", 2f); return; }
        if (cart == null || !cart.Near(transform.position, 3.5f)) { Say("Get closer to the cart to squirt the backpack into it.", 2.5f); return; }
        if (!cart.HasRoom) { Say("The cart is full.  T tips it out.", 2.5f); return; }
        SetTool(2);
        Pouring = true;
        pourAcc = 0f; poured = 0; pourCartStart = world.CartVoxels;
        Say("Squirting the backpack into the cart.", 2f);
    }

    /// One frame of squirting: clods leave the nozzle and are lobbed into the cart's tub, where it catches them.
    void Pour(float dt)
    {
        var cart = MineCart.Instance;
        if (cart == null || !cart.Near(transform.position, 4f)) { Pouring = false; Say("Moved away from the cart: stopped.", 2f); return; }
        pourAcc += pourRate * dt;
        Vector3 from = NozzleMouth;
        while (pourAcc >= VoxelWorld.ClodVoxels)
        {
            if (pourCartStart + poured + VoxelWorld.ClodVoxels > cart.capacity) { Pouring = false; Say("The cart is full.  T tips it out.", 2.5f); return; }
            pourAcc -= VoxelWorld.ClodVoxels;
            // somewhere over the middle of the tub, lobbed high enough to clear its rim
            // (aimed at the tub's floor, so it does not keep drifting on past the far side as it drops in)
            Vector3 target = cart.Mouth + Vector3.down * 0.45f + cart.transform.right * Random.Range(-0.22f, 0.22f) + cart.transform.forward * Random.Range(-0.4f, 0.4f);
            Vector3 gap = target - from;
            float time = Mathf.Clamp(new Vector2(gap.x, gap.z).magnitude / 4f, 0.45f, 0.7f);
            Vector3 velocity = gap / time + Vector3.up * (0.5f * 9.81f * time);
            if (!world.PackPour(from, velocity))
            {
                world.PackCrumbsToCart(cart.capacity);
                Pouring = false;
                Say("The backpack is empty.", 2f);
                return;
            }
            poured += VoxelWorld.ClodVoxels;
        }
    }

    void Animate(float speed)
    {
        // where the tool is held: his chest from behind, his eyes in the eyes view; either way it tips with where he looks
        Pose p = CurrentPose();
        if (Eyes)
        {
            hold.localPosition = new Vector3(0f, 1.6f, 0f);
            hold.localRotation = Quaternion.Euler(lookPitch * 0.85f, 0f, 0f);
            p.at += new Vector3(0.05f, -0.02f, 0.12f);                                   // a little further out, so it sits nicely in view
        }
        else
        {
            hold.localPosition = new Vector3(0f, 1.42f, 0.02f);
            hold.localRotation = Quaternion.Euler((lookPitch - 14f) * 0.5f, 0f, 0f);
        }
        Transform tool = Tool == 0 ? pick : Tool == 1 ? shovel : nozzle;
        tool.localPosition = p.at;
        tool.localRotation = Quaternion.Euler(p.turn);
        if (Tool == 2)
        {
            // the nozzle points at what you aim at (or into the cart while it squirts), and shakes a little while it works
            var cart = MineCart.Instance;
            Vector3 target = Pouring && cart != null ? cart.Mouth : aimFound ? aimPoint : tool.position + aimDir * 2f;
            Vector3 look = target - tool.position;
            if (look.sqrMagnitude > 0.01f) tool.rotation = Quaternion.LookRotation(look, Vector3.up);
            bool working = Pouring || (useOverride ? overrideUse : (Input.GetMouseButton(0) || Input.GetKey(KeyCode.Space)));
            if (working) tool.localPosition += new Vector3(Mathf.Sin(Time.time * 71f), Mathf.Sin(Time.time * 53f), 0f) * 0.004f;
        }
        LayHose();
        if (shovelDirt != null) shovelDirt.gameObject.SetActive(Tool == 1 && world.ShovelVoxels >= VoxelWorld.ClodVoxels);

        if (model == null || Eyes) return;
        float s = Mathf.Sin(stride * 4.4f) * Mathf.Clamp01(speed) * 38f;
        legL.localRotation = Quaternion.Euler(s, 0f, 0f);
        legR.localRotation = Quaternion.Euler(-s, 0f, 0f);
        // he leans into a swing
        float lean = swing == Swing.None ? 0f : Mathf.Sin(Mathf.Clamp01(swingT / (swing == Swing.Dig ? DigTime : swing == Swing.Throw ? ThrowTime : PickTime)) * Mathf.PI) * (swing == Swing.Throw ? -6f : 13f);
        model.localRotation = Quaternion.Euler(lean, 0f, 0f);
        // both hands on the handle: right hand low near the head of the tool, left hand at the top
        Reach(armR, tool.TransformPoint(new Vector3(0f, 0f, 0.56f)));
        Reach(armL, tool.TransformPoint(new Vector3(0f, 0f, 0.06f)));
    }

    /// Lays the hose from the backpack's outlet to the back of the nozzle, sagging a little in between.
    void LayHose()
    {
        bool show = Tool == 2 && !Eyes && !InDozer && HoldingCart == 0 && model != null && model.gameObject.activeSelf;
        if (hose.gameObject.activeSelf != show) hose.gameObject.SetActive(show);
        if (!show) return;
        Vector3 a = model.TransformPoint(new Vector3(0.14f, 0.96f, -0.3f)), b = nozzle.TransformPoint(new Vector3(0f, 0f, 0.02f));
        Vector3 c = (a + b) * 0.5f + Vector3.down * 0.35f + transform.right * 0.12f;
        Vector3 last = a;
        for (int i = 0; i < hoseBits.Length; i++)
        {
            float t = (i + 1f) / hoseBits.Length;
            Vector3 next = (1f - t) * (1f - t) * a + 2f * (1f - t) * t * c + t * t * b;
            Vector3 d = next - last;
            float len = d.magnitude;
            if (len > 1e-4f)
            {
                hoseBits[i].SetPositionAndRotation((last + next) * 0.5f, Quaternion.LookRotation(d / len, Vector3.up));
                hoseBits[i].localScale = new Vector3(1f, 1f, len + 0.02f);
            }
            last = next;
        }
    }

    /// Points an arm (which hangs straight down from its shoulder) at a spot.
    void Reach(Transform arm, Vector3 worldTarget)
    {
        Vector3 local = arm.parent.InverseTransformPoint(worldTarget) - arm.localPosition;
        if (local.sqrMagnitude < 1e-6f) return;
        arm.localRotation = Quaternion.FromToRotation(Vector3.down, local.normalized);
    }

    /// E on foot: let go of the cart if holding it; otherwise fit or pick up a part; otherwise take hold of the cart.
    public void PressE()
    {
        var atDump = MineCart.Instance;
        if (atDump != null && atDump.AtDump && atDump.Near(transform.position, 3.2f) && world.CartVoxels >= VoxelWorld.ClodVoxels)
        {
            LetGo();                                                    // let go, and tip it into the hopper
            TipCart();
            return;
        }
        if (HoldingCart != 0) { LetGo(); return; }
        if (AtGoldShed()) { SellGold(); return; }
        if (UsePart() != "none") return;
        if (GrabCart()) return;
        var cart = MineCart.Instance;
        if (cart != null && cart.Near(transform.position, 2.6f)) Say("Stand at an end of the cart and press E to take hold of it.", 2.5f);
    }

    /// Takes hold of the nearer end of the cart, if he is standing at one.  True if he did.
    public bool GrabCart()
    {
        var cart = MineCart.Instance;
        if (cart == null || InDozer) return false;
        int end = cart.EndNear(transform.position);
        if (end == 0) return false;
        HoldingCart = end;
        swing = Swing.None;
        leanIn = 0f;
        hold.gameObject.SetActive(false);                                                // tools away: both hands on the cart
        if (marker != null) marker.gameObject.SetActive(false);
        Say("Holding the cart.  W pushes it, S pulls it back.  E lets go.", 3f);
        return true;
    }

    public void LetGo()
    {
        if (HoldingCart == 0) return;
        HoldingCart = 0;
        if (hold != null) hold.gameObject.SetActive(!InDozer);
    }

    /// One frame of holding the cart: W rolls it away from him, S pulls it back.  He stays at its end,
    /// facing along the track, leaning into it with both hands on the top of the end.
    void PushCart(float dt, float walk)
    {
        var cart = MineCart.Instance;
        if (cart == null) { LetGo(); return; }
        float went = cart.Roll(-HoldingCart * walk * (walk >= 0f ? pushSpeed : backSpeed) * dt);
        leanIn = Mathf.MoveTowards(leanIn, Mathf.Abs(walk) > 0.1f ? 1f : 0.35f, dt * 3f);
        Vector3 at, facing;
        cart.HoldPlace(HoldingCart, out at, out facing);
        yaw = Mathf.Atan2(facing.x, facing.z) * Mathf.Rad2Deg;
        transform.SetPositionAndRotation(at, Quaternion.Euler(0f, yaw, 0f));
        world.SlumpCentre = at;
        if (cam != null) { cam.lookYaw = yaw; cam.lookPitch = lookPitch; }
        stride += Mathf.Abs(went) * 1.3f;                                                // short, heavy steps
        if (model == null || Eyes) return;
        float s = Mathf.Sin(stride * 4.4f) * 30f * (Mathf.Abs(went) > 1e-5f ? 1f : 0f);
        legL.localRotation = Quaternion.Euler(s - 8f * leanIn, 0f, 0f);
        legR.localRotation = Quaternion.Euler(-s - 8f * leanIn, 0f, 0f);
        model.localRotation = Quaternion.Euler(8f + 16f * leanIn, 0f, 0f);             // leans forward into it
        // his right hand on his right of the end, his left on his left
        Reach(armR, cart.HandHold(HoldingCart, -HoldingCart));
        Reach(armL, cart.HandHold(HoldingCart, HoldingCart));
    }

    /// E on foot: fit a carried part when at the dozer, otherwise pick up a part that has been dug out.
    /// Returns what happened, for tests.
    public string UsePart()
    {
        var finds = Finds.Instance;
        if (finds == null || InDozer) return "none";
        int carried = finds.FirstCarried();
        if (carried >= 0 && NearDozer())
        {
            finds.Install(carried);
            Say("Fitted the " + Finds.Names[carried] + "." + (dozer.dead ? "" : "  (The dozer already works.  F9 makes it dead, to try repairs.)"), 4f);
            return "installed " + carried;
        }
        int here = finds.Collectable(transform.position);
        if (here >= 0)
        {
            finds.Collect(here);
            Say("Picked up a " + Finds.Names[here] + ".  Take it to the dozer and press E to fit it.", 4f);
            return "collected " + here;
        }
        return "none";
    }

    /// Close enough to the dozer to climb in.
    public bool NearDozer() { return dozer != null && !InDozer && Vector3.Distance(transform.position, dozer.transform.position) <= 5.5f; }

    public void TryDozer()
    {
        if (dozer == null) return;
        if (InDozer) { GetOut(); return; }
        if (!NearDozer()) { Say("Walk up to the dozer first.", 2f); return; }
        if (dozer.dead && !dozer.CanDrive) { Say("The dozer is dead.  It has sat here for years.  Its tracks part is somewhere in the mine.", 4f); return; }
        GetIn();
    }

    void OnGUI()
    {
        if (world == null) return;
        if (sayTimer > 0f)
        {
            var style = new GUIStyle(GUI.skin.box) { fontSize = 16, alignment = TextAnchor.MiddleCenter, wordWrap = true };
            GUI.Box(new Rect(Screen.width / 2 - 330, Screen.height - 110, 660, 44), say, style);
        }
        if (InDozer) { GUI.Box(new Rect(10, Screen.height - 34, 170, 24), "Enter   get out"); return; }
        if (Tool == 2 && !backpackOwned) SetTool(1);
        string tool = Tool == 0 ? "PICK" : Tool == 1 ? "SHOVEL" : "BACKPACK";
        string load = Tool == 1 ? "   holding " + (world.ShovelVoxels * VoxelWorld.VoxelVolume * 1000f).ToString("F0") + " litres" + (world.ShovelVoxels >= VoxelWorld.ClodVoxels ? " (use again to throw)" : "") : "";
        string text =
            "Mouse   look and aim        W A S D   walk        Tab   view: " + (Eyes ? "eyes" : "over the shoulder") + "\n" +
            "1   pick     2   shovel     3   backpack     Left mouse or Space   use it where you aim (hold)\n" +
            "Esc   free the mouse        Enter   get in the dozer        F5 save   F6 load\n" +
            "Tool: " + tool + load;
        GUI.Box(new Rect(10, 10, 540, 86), text);
        // the backpack gauge, always: a bar that fills, and the litres
        float packL = world.PackVoxels * VoxelWorld.VoxelVolume * 1000f, packMax = packHolds * VoxelWorld.VoxelVolume * 1000f;
        if (backpackOwned) GUI.Box(new Rect(560, 10, 300, 58), "Backpack: " + packL.ToString("F0") + " of " + packMax.ToString("F0") + " litres" + (Pouring ? "   (squirting)" : world.PackVoxels >= packHolds - VoxelWorld.ClodVoxels ? "   FULL" : "") + "\nQ by the cart squirts it in");
        if (backpackOwned)
        {
            GUI.DrawTexture(new Rect(568, 54, 284, 7), Texture2D.grayTexture);
            GUI.DrawTexture(new Rect(568, 54, 284 * Mathf.Clamp01(packL / packMax), 7), Texture2D.whiteTexture);
        }
        var cart = MineCart.Instance;
        if (cart != null && cart.Near(transform.position, 7.5f))
        {
            float litres = world.CartVoxels * VoxelWorld.VoxelVolume * 1000f, holds = cart.capacity * VoxelWorld.VoxelVolume * 1000f;
            string what = cart.AtDump ? "AT THE DUMP: E tips it into the hopper and you get paid."
                        : HoldingCart != 0 ? "W push   S pull back   E let go   T tip   (the dump and hopper are at the end of the rails)"
                        : "Shovelfuls go in it.   Q squirts the backpack in.   E at an end holds it.   T tips it.";
            GUI.Box(new Rect(10, 102, 640, 24), "Cart: " + litres.ToString("F0") + " of " + holds.ToString("F0") + " litres.   " + what);
        }
        // at the hopper with a load: say so, in the middle of the screen
        if (cart != null && cart.AtDump && cart.Near(transform.position, 3.2f) && world.CartVoxels >= VoxelWorld.ClodVoxels && !cart.Tipping)
        {
            var prompt = new GUIStyle(GUI.skin.box) { fontSize = 20, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            GUI.Box(new Rect(Screen.width / 2 - 230, Screen.height * 0.62f, 460, 40), "Press E to tip it into the hopper", prompt);
        }
        // close enough to climb in: say so, in the middle of the screen where it can't be missed
        if (NearDozer())
        {
            var prompt = new GUIStyle(GUI.skin.box) { fontSize = 20, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            string what = dozer.dead && !dozer.CanDrive ? "The dozer is dead (it needs parts)" : "Press ENTER to get in the dozer";
            GUI.Box(new Rect(Screen.width / 2 - 210, Screen.height * 0.62f, 420, 40), what, prompt);
        }
        var finds = Finds.Instance;
        if (finds != null)
        {
            var prompt = new GUIStyle(GUI.skin.box) { fontSize = 20, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            int carried = finds.FirstCarried(), here = finds.Collectable(transform.position);
            string partLine = null;
            if (carried >= 0 && NearDozer()) partLine = "Press E to fit the " + Finds.Names[carried];
            else if (here >= 0) partLine = "Press E to pick up the " + Finds.Names[here];
            if (partLine != null) GUI.Box(new Rect(Screen.width / 2 - 210, Screen.height * 0.70f, 420, 40), partLine, prompt);
            string carrying = "";
            for (int i = 0; i < Finds.Count; i++) if (finds.Carrying(i)) carrying += (carrying.Length > 0 ? ", " : "") + Finds.Names[i];
            if (carrying.Length > 0) GUI.Box(new Rect(10, 132, 540, 24), "Carrying: " + carrying);
        }
        // at the gold buyer's counter: what E does here
        if (AtGoldShed() && Money.Instance != null)
        {
            var prompt = new GUIStyle(GUI.skin.box) { fontSize = 20, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            var m = Money.Instance;
            string what = m.GoldStore > 0 ? "Press E to sell your gold:  " + m.GoldLitres.ToString("F0") + " L for " + m.GoldWorth.ToString("N0") + " coins" : "Gold buyer: you have no gold to sell yet";
            GUI.Box(new Rect(Screen.width / 2 - 280, Screen.height * 0.62f, 560, 40), what, prompt);
        }
        // a label over the gold buyer's shed, and over the dump's sign, so you can find them
        if (Camera.main != null && SiteProps.GoldShedSign != Vector3.zero)
        {
            Vector3 gp = Camera.main.WorldToScreenPoint(SiteProps.GoldShedSign);
            if (gp.z > 0f && Vector3.Distance(Camera.main.transform.position, SiteProps.GoldShedSign) < 70f)
            {
                var tag = new GUIStyle(GUI.skin.box) { fontSize = 16, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
                GUI.Box(new Rect(gp.x - 70, Screen.height - gp.y - 14, 140, 28), "GOLD BUYER", tag);
            }
        }
        if (Camera.main != null && SiteProps.DumpSign != Vector3.zero)
        {
            Vector3 sp = Camera.main.WorldToScreenPoint(SiteProps.DumpSign);
            float far = Vector3.Distance(Camera.main.transform.position, SiteProps.DumpSign);
            if (sp.z > 0f && far < 70f)
            {
                var tag = new GUIStyle(GUI.skin.box) { fontSize = 16, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
                GUI.Box(new Rect(sp.x - 50, Screen.height - sp.y - 14, 100, 28), "DUMP", tag);
            }
        }
        // the cross you aim with
        GUI.Box(new Rect(Screen.width / 2 - 1, Screen.height / 2 - 8, 2, 16), GUIContent.none);
        GUI.Box(new Rect(Screen.width / 2 - 8, Screen.height / 2 - 1, 16, 2), GUIContent.none);
    }
}
