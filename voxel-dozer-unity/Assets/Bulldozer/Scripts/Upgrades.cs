// The upgrade tree: the team's one shared set of upgrades, bought with the coins (and, for machinery, gold) in
// the shared pot (Money.cs).  U (or Start on the pad) opens it.  It is drawn as a tree of round nodes, one column
// per branch, deeper down the tree going down the screen.  Click a node (or move to it with the d-pad or the arrow
// keys) and a card at the bottom shows it; Buy (A, Enter) buys it and it works straight away.  The newest one in a
// branch can be sold back for everything it cost (X).
//
// Three columns:
//   Breaking      Pick 1-5, then the Jackhammer (needs coins and gold), Jackhammer 2-5.  (One branch: levels 6-10
//                 of the pick are the jackhammer, so saves didn't need to change.)
//   Moving dirt   Shovel 1-6, then the Backpack (needs Shovel 6, coins and gold), Backpack 1-8
//   Hauling       Cart 1-2, then the Motor cart (needs coins and gold), Motor cart 2-3 (faster); a bigger cart and
//                 the Automatic cart are coming.  (Levels 3-5 of the cart are the motor cart, as with the jackhammer.)
//
// Every purchase and sell-back goes through Buy and SellBack here, so multiplayer can send them later.
// F8 is a test key: it adds 10,000 coins and 50 litres of gold.
//
// The numbers (prices, sizes, speeds) are starting points, to be tuned once it's played.
using UnityEngine;

public class Upgrades : MonoBehaviour
{
    public static Upgrades Instance { get; private set; }

    public enum Branch { Pick = 0, Shovel = 1, Backpack = 2, Cart = 3 }
    const int BranchCount = 4;

    struct Step
    {
        public string name, effect;
        public long coins;
        public float goldLitres;
        public Step(string n, string e, long c, float g = 0f) { name = n; effect = e; coins = c; goldLitres = g; }
    }

    // Steps[branch][i] is level i+1.  Level 1 of the pick, shovel and cart is what you start with (free).
    // The backpack starts at level 0 (not owned): its level 1 is the unlock.
    static readonly Step[][] Steps =
    {
        new[] {   // pick: chunk radius 0.26 -> 0.40 m, rock from 80% to 100% of that
            new Step("Pick 1", "Breaks a small chunk", 0),
            new Step("Pick 2", "Bigger chunk each hit", 50),
            new Step("Pick 3", "Bigger again, better on rock", 80),
            new Step("Pick 4", "Big chunks, good on rock", 128),
            new Step("Pick 5", "Biggest chunk, full strength on rock", 205),
            new Step("Jackhammer", "Unlock: hold to hammer.  Shift+wheel or [ ] sets the bite", 600, 8f),
            new Step("Jackhammer 2", "Bigger bite, faster blows", 260),
            new Step("Jackhammer 3", "Bigger bite, faster blows", 420),
            new Step("Jackhammer 4", "Bigger bite, faster blows", 670),
            new Step("Jackhammer 5", "Biggest bite, fastest", 1070),
        },
        new[] {   // shovel: load 117 -> 342 litres, swing speed 1.0 -> 1.6
            new Step("Shovel 1", "117 L a scoop", 0),
            new Step("Shovel 2", "156 L a scoop, 10% faster", 40),
            new Step("Shovel 3", "195 L a scoop, 20% faster", 64),
            new Step("Shovel 4", "239 L a scoop, 30% faster", 102),
            new Step("Shovel 5", "288 L a scoop, 45% faster", 164),
            new Step("Shovel 6", "342 L a scoop, 60% faster", 262),
        },
        new[] {   // backpack: 200 -> 1000 litres, suction 1x -> 4x
            new Step("Backpack", "Unlock: sucks up loose dirt.  200 L, slow", 400, 5f),
            new Step("Backpack 2", "300 L, 1.4x suction", 150),
            new Step("Backpack 3", "400 L, 1.8x suction", 240),
            new Step("Backpack 4", "500 L, 2.2x suction", 384),
            new Step("Backpack 5", "600 L, 2.6x suction", 614),
            new Step("Backpack 6", "750 L, 3x suction", 983),
            new Step("Backpack 7", "875 L, 3.5x suction", 1573),
            new Step("Backpack 8", "1000 L, 4x suction", 2516),
        },
        new[] {   // cart: 1000 -> 1500 litres
            new Step("Cart 1", "Hand cart, 1000 L", 0),
            new Step("Cart 2", "Bigger tub, 1500 L", 300),
            new Step("Motor cart", "Unlock: R at an end rides it, W out, S back in.  3 m/s", 800, 10f),
            new Step("Motor cart 2", "Faster: 4 m/s", 400),
            new Step("Motor cart 3", "Fastest: 5 m/s", 640),
        },
    };
    // shown after a branch, not buyable yet
    static readonly string[][] Coming =
    {
        new string[0],
        new string[0],
        new[] { "Bigger cart  (coming)", "Automatic cart  (coming)" },
        new string[0],
    };

    static readonly float[] PickRadius = { 0.26f, 0.29f, 0.32f, 0.36f, 0.40f };
    static readonly float[] JackMax = { 0.26f, 0.29f, 0.32f, 0.35f, 0.38f };       // the jackhammer's biggest bite, metres
    static readonly float[] JackInterval = { 0.09f, 0.085f, 0.08f, 0.075f, 0.07f }; // seconds between blows
    static readonly float[] PickRock = { 0.8f, 0.84f, 0.88f, 0.94f, 1.0f };
    static readonly int[] ShovelHolds = { 480, 640, 800, 980, 1180, 1400 };
    static readonly float[] ShovelSpeed = { 1.0f, 1.1f, 1.2f, 1.3f, 1.45f, 1.6f };
    static readonly int[] PackHolds = { 819, 1229, 1638, 2048, 2458, 3072, 3584, 4096 };
    static readonly float[] PackRate = { 1.0f, 1.4f, 1.8f, 2.2f, 2.6f, 3.0f, 3.5f, 4.0f };
    static readonly int[] CartHolds = { 4096, 6144, 6144, 6144, 6144 };      // the motor cart keeps the Cart 2 tub
    public const int MotorCartLevel = 3;                        // the cart level that is the motor cart
    static readonly float[] MotorSpeed = { 3f, 4f, 5f };        // metres a second, Motor cart 1-3 (pushing is 2)
    const float SuckBase = 130f;                                // voxels a second at backpack level 1 (about 32 litres)

    readonly int[] level = { 1, 1, 0, 1 };
    readonly string[][] boughtBy = new string[BranchCount][];
    public bool Open { get; private set; }
    string note = ""; float noteTimer;

    public int Level(Branch b) { return level[(int)b]; }
    public int MaxLevel(Branch b) { return Steps[(int)b].Length; }
    public bool HasBackpack { get { return level[(int)Branch.Backpack] > 0; } }
    public bool HasMotorCart { get { return level[(int)Branch.Cart] >= MotorCartLevel; } }

    void Awake()
    {
        Instance = this;
        for (int b = 0; b < BranchCount; b++) boughtBy[b] = new string[Steps[b].Length];
    }
    void OnDestroy() { if (Instance == this) Instance = null; }
    void Start() { Apply(); }

    static int GoldVoxels(float litres) { return Mathf.CeilToInt(litres / (VoxelWorld.VoxelVolume * 1000f)); }

    /// Why the next level of a branch can't be bought now, or null if it can.
    public string CantBuy(Branch b)
    {
        int i = (int)b, next = level[i];                         // index of the next step
        if (next >= Steps[i].Length) return "Maxed";
        if (b == Branch.Backpack && level[(int)Branch.Shovel] < MaxLevel(Branch.Shovel)) return "Needs Shovel 6";
        var money = Money.Instance;
        if (money == null) return "No money yet";
        var s = Steps[i][next];
        if (money.Coins < s.coins) return "Needs " + s.coins.ToString("N0") + " coins";
        if (s.goldLitres > 0f && money.GoldStore < GoldVoxels(s.goldLitres)) return "Needs " + s.goldLitres.ToString("F0") + " L of gold";
        return null;
    }

    /// Buys the next level of a branch.  True if it was bought.
    public bool Buy(Branch b, string who = "Player 1")
    {
        if (CantBuy(b) != null) return false;
        int i = (int)b, next = level[i];
        var s = Steps[i][next];
        var money = Money.Instance;
        if (!money.Spend(s.coins)) return false;
        if (s.goldLitres > 0f && !money.SpendGold(GoldVoxels(s.goldLitres))) { money.Refund(s.coins, 0); return false; }
        level[i] = next + 1;
        boughtBy[i][next] = who;
        Apply();
        Note("Bought " + s.name + ".");
        GameAudio.Play("upgrade", 0.8f);
        return true;
    }

    /// Why the newest level of a branch can't be sold back, or null if it can.
    public string CantSellBack(Branch b)
    {
        int i = (int)b, have = level[i];
        int first = b == Branch.Backpack ? 1 : 2;                // the starting level can't be sold
        if (have < first) return "Nothing to sell back";
        if (b == Branch.Shovel && have == MaxLevel(Branch.Shovel) && HasBackpack) return "The backpack needs Shovel 6";
        return null;
    }

    /// Sells back the newest level of a branch, for everything it cost.
    public bool SellBack(Branch b)
    {
        if (CantSellBack(b) != null) return false;
        int i = (int)b, idx = level[i] - 1;
        var s = Steps[i][idx];
        Money.Instance.Refund(s.coins, s.goldLitres > 0f ? GoldVoxels(s.goldLitres) : 0);
        level[i] = idx;
        boughtBy[i][idx] = null;
        Apply();
        Note("Sold back " + s.name + " for " + s.coins.ToString("N0") + " coins" + (s.goldLitres > 0f ? " and " + s.goldLitres.ToString("F0") + " L of gold" : "") + ".");
        return true;
    }

    /// Puts the current levels into the tools and the cart.
    public void Apply()
    {
        var wk = Worker.Instance;
        if (wk != null)
        {
            int p = Mathf.Min(level[0], 5) - 1, sh = level[1] - 1, bp = Mathf.Max(0, level[2] - 1);
            wk.jackOwned = level[0] >= 6;
            if (wk.jackOwned) { wk.jackMax = JackMax[level[0] - 6]; wk.jackInterval = JackInterval[level[0] - 6]; }
            wk.pickRadius = PickRadius[p];
            wk.pickRockFactor = PickRock[p];
            wk.shovelHolds = ShovelHolds[sh];
            wk.scoopRadius = 0.38f * Mathf.Pow(ShovelHolds[sh] / 480f, 1f / 3f);
            wk.shovelSpeed = ShovelSpeed[sh];
            wk.packHolds = PackHolds[bp];
            wk.suckRate = SuckBase * PackRate[bp];
            wk.backpackOwned = HasBackpack;
        }
        var cart = MineCart.Instance;
        if (cart != null)
        {
            int c = level[3];
            cart.spec.capacity = CartHolds[c - 1];
            cart.spec.motor = c >= MotorCartLevel;
            if (cart.spec.motor) cart.spec.motorSpeed = MotorSpeed[c - MotorCartLevel];
            else if (wk != null && wk.RidingCart) wk.GetOffCart();       // sold back while riding it
        }
    }

    void Note(string text) { note = text; noteTimer = 3f; }

    public void WriteState(System.IO.BinaryWriter w)
    {
        w.Write(BranchCount);
        for (int b = 0; b < BranchCount; b++)
        {
            w.Write(level[b]);
            for (int k = 0; k < level[b]; k++) w.Write(boughtBy[b][k] ?? "");
        }
    }

    public void ReadState(System.IO.BinaryReader r)
    {
        int n = r.ReadInt32();
        for (int b = 0; b < n; b++)
        {
            int lv = r.ReadInt32();
            var names = new string[lv];
            for (int k = 0; k < lv; k++) names[k] = r.ReadString();
            if (b >= BranchCount) continue;
            level[b] = Mathf.Clamp(lv, b == (int)Branch.Backpack ? 0 : 1, Steps[b].Length);
            for (int k = 0; k < Steps[b].Length; k++) boughtBy[b][k] = k < names.Length && names[k].Length > 0 ? names[k] : null;
        }
        Apply();
    }

    /// The tree as it is at the start of a new game (and for a save from before upgrades).
    public void Reset()
    {
        level[0] = 1; level[1] = 1; level[2] = 0; level[3] = 1;
        for (int b = 0; b < BranchCount; b++) System.Array.Clear(boughtBy[b], 0, boughtBy[b].Length);
        Apply();
    }

    /// The tree as plain text, one line per upgrade (for videos, where the screen itself isn't recorded).
    public string Describe(Branch b)
    {
        int i = (int)b;
        var sb = new System.Text.StringBuilder();
        for (int k = 0; k < Steps[i].Length; k++)
        {
            var st = Steps[i][k];
            string mark = k < level[i] ? "[x]" : k == level[i] ? "[ ]" : "   ";
            string price = k < level[i] ? "" : "  " + st.coins.ToString("N0") + "c" + (st.goldLitres > 0f ? " + " + st.goldLitres.ToString("F0") + " L gold" : "");
            sb.Append(mark + " " + st.name + ":  " + st.effect + price + "\n");
        }
        return sb.ToString();
    }

    /// Sets a branch's level directly (tests).
    public void SetLevel(Branch b, int lv) { level[(int)b] = lv; Apply(); }

    public void SetOpen(bool open)
    {
        Open = open;
        if (open)
        {
            Cursor.lockState = CursorLockMode.None;
            if (sel < 0 || sel >= Nodes.Length) sel = DefaultSelection();
        }
    }

    void Update()
    {
        if (noteTimer > 0f) noteTimer -= Time.unscaledDeltaTime;
        var wk = Worker.Instance;
        if (wk != null && wk.useOverride) return;                // not while a test is driving
        if (PauseMenu.Blocking) return;                          // the pause menu is up (it also does Esc)
        if (Input.GetKeyDown(KeyCode.U) || Pad.Down(Pad.B.Start)) SetOpen(!Open);
        else if (Open)
        {
            // the d-pad or the arrow keys move between the nodes, A or Enter buys the picked one, X sells back the
            // newest one in the picked branch
            int dx = (Pad.DRightDown || Input.GetKeyDown(KeyCode.RightArrow) ? 1 : 0) - (Pad.DLeftDown || Input.GetKeyDown(KeyCode.LeftArrow) ? 1 : 0);
            int dy = (Pad.DDownDown || Input.GetKeyDown(KeyCode.DownArrow) ? 1 : 0) - (Pad.DUpDown || Input.GetKeyDown(KeyCode.UpArrow) ? 1 : 0);
            if (dx != 0 || dy != 0) MoveSelection(dx, dy);
            if (Pad.Down(Pad.B.A) || Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.KeypadEnter)) BuySelected();
            if (Pad.Down(Pad.B.X)) SellBackSelected();
        }
        if (Input.GetKeyDown(KeyCode.F8) && Money.Instance != null)
        {
            Money.Instance.TestGrant(10000, GoldVoxels(50f));
            if (wk != null) wk.Say("Test key: +10,000 coins and 50 L of gold.", 3f);
        }
    }

    // ---------------------------------------------------------------- the tree: nodes, and which one is picked
    // Four columns of round nodes under three headings, top to bottom is deeper down the tree:
    //   Breaking      the pick, then the jackhammer under it
    //   Moving dirt   the shovel, and beside it the backpack, hanging off Shovel 6 (it needs Shovel 6)
    //   Hauling       the cart, the motor cart under it, then the ones that are coming
    public enum NodeState { Owned, CanBuy, TooDear, Locked, Coming }
    struct Node { public int branch, step, col, row; public string coming; }   // branch -1: a "coming" one
    const int TreeCols = 4, BackpackRow0 = 6;
    static Node[] nodes;
    static int treeRows;

    static Node[] Nodes
    {
        get
        {
            if (nodes != null) return nodes;
            var list = new System.Collections.Generic.List<Node>();
            for (int c = 0; c < TreeCols; c++)
            {
                int b = c, row0 = b == (int)Branch.Backpack ? BackpackRow0 : 0;
                for (int k = 0; k < Steps[b].Length; k++) list.Add(new Node { branch = b, step = k, col = c, row = row0 + k });
                if (b == (int)Branch.Cart)
                    for (int k = 0; k < Coming[2].Length; k++)
                        list.Add(new Node { branch = -1, step = k, col = c, row = Steps[b].Length + k, coming = Coming[2][k].Replace("  (coming)", "") });
            }
            nodes = list.ToArray();
            treeRows = 0;
            foreach (var n in nodes) treeRows = Mathf.Max(treeRows, n.row + 1);
            return nodes;
        }
    }

    int sel = -1;                                            // the picked node (an index into Nodes)

    /// For tests and the screen: the picked node.
    public int SelectedIndex { get { return sel; } }
    public string SelectedName { get { return sel < 0 ? "" : NodeName(Nodes[sel]); } }
    public NodeState SelectedState { get { return sel < 0 ? NodeState.Locked : StateOf(sel); } }
    public int SelectedColumn { get { return sel < 0 ? -1 : Nodes[sel].col; } }
    public int SelectedRow { get { return sel < 0 ? -1 : Nodes[sel].row; } }

    /// Picks the node for a branch's level step+1 (step 0 is level 1).
    public void Select(Branch b, int step)
    {
        for (int i = 0; i < Nodes.Length; i++) if (Nodes[i].branch == (int)b && Nodes[i].step == step) { sel = i; return; }
    }

    static string NodeName(Node n) { return n.branch < 0 ? n.coming : Steps[n.branch][n.step].name; }

    /// What a node is now: owned, can be bought now, the next one but short of coins or gold, locked, or coming.
    public NodeState StateOf(int i)
    {
        var n = Nodes[i];
        if (n.branch < 0) return NodeState.Coming;
        int have = level[n.branch];
        if (n.step < have) return NodeState.Owned;
        if (n.step > have) return NodeState.Locked;
        if (n.branch == (int)Branch.Backpack && level[(int)Branch.Shovel] < MaxLevel(Branch.Shovel)) return NodeState.Locked;
        return CantBuy((Branch)n.branch) == null ? NodeState.CanBuy : NodeState.TooDear;
    }

    // to start with: the first one that can be bought now, else the next pick
    int DefaultSelection()
    {
        for (int i = 0; i < Nodes.Length; i++) if (StateOf(i) == NodeState.CanBuy) return i;
        for (int i = 0; i < Nodes.Length; i++) if (Nodes[i].branch == 0 && Nodes[i].step == Mathf.Min(level[0], Steps[0].Length - 1)) return i;
        return 0;
    }

    /// Moves the pick: dy up and down its column, dx to the next column along (the nearest node in it).
    public void MoveSelection(int dx, int dy)
    {
        if (sel < 0) { sel = DefaultSelection(); return; }
        var at = Nodes[sel];
        if (dy != 0)
        {
            int best = -1;
            for (int i = 0; i < Nodes.Length; i++)
            {
                var n = Nodes[i];
                if (n.col != at.col || (n.row - at.row) * dy <= 0) continue;
                if (best < 0 || Mathf.Abs(n.row - at.row) < Mathf.Abs(Nodes[best].row - at.row)) best = i;
            }
            if (best >= 0) { sel = best; at = Nodes[sel]; }
        }
        if (dx != 0)
        {
            int col = at.col + dx;
            if (col < 0 || col >= TreeCols) return;
            int best = -1;
            for (int i = 0; i < Nodes.Length; i++)
            {
                var n = Nodes[i];
                if (n.col != col) continue;
                if (best < 0 || Mathf.Abs(n.row - at.row) < Mathf.Abs(Nodes[best].row - at.row)) best = i;
            }
            if (best >= 0) sel = best;
        }
    }

    /// Why a node is locked, in words.
    string LockedWhy(Node n)
    {
        if (n.branch < 0) return "Coming later";
        if (n.step > level[n.branch]) return "Needs " + Steps[n.branch][n.step - 1].name + " first";
        if (n.branch == (int)Branch.Backpack) return "Needs Shovel 6 first";
        return "";
    }

    /// Buys the picked node, if it is the one that can be bought now; otherwise says why not.  True if bought.
    public bool BuySelected()
    {
        if (sel < 0) return false;
        var n = Nodes[sel];
        switch (StateOf(sel))
        {
            case NodeState.Coming: Note(n.coming + " is coming later."); return false;
            case NodeState.Owned: Note("You already have " + NodeName(n) + "."); return false;
            case NodeState.Locked: Note("Locked.  " + LockedWhy(n) + "."); return false;
            case NodeState.TooDear: Note(CantBuy((Branch)n.branch) + "."); return false;
        }
        return Buy((Branch)n.branch);
    }

    /// Sells back the newest level in the picked node's branch.  True if sold.
    public bool SellBackSelected()
    {
        if (sel < 0 || Nodes[sel].branch < 0) return false;
        var b = (Branch)Nodes[sel].branch;
        string why = CantSellBack(b);
        if (why != null) { Note(why + "."); return false; }
        return SellBack(b);
    }

    // ---------------------------------------------------------------- the tree screen
    // laid out in 1080-high units (Ui.cs scales it to the screen)
    const float PW = 1240f, PH = 1000f, CardH = 170f;
    static Texture2D discTex, ringTex, lockTex;
    GUIStyle sName, sSub, sTick, sCardTitle, sCardText, sNote, sHead, sTitle, sInfo, sBigButton;

    static Texture2D MakeRound(bool ring)
    {
        const int n = 64;
        var t = new Texture2D(n, n, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, hideFlags = HideFlags.DontSave };
        var px = new Color[n * n];
        float c = (n - 1) * 0.5f, outer = n * 0.5f - 1f, inner = outer - 6f;
        for (int y = 0; y < n; y++)
            for (int x = 0; x < n; x++)
            {
                float d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
                float a = Mathf.Clamp01(outer - d + 0.5f);
                if (ring) a *= Mathf.Clamp01(d - inner + 0.5f);
                px[y * n + x] = new Color(1f, 1f, 1f, a);
            }
        t.SetPixels(px); t.Apply();
        return t;
    }

    // a padlock: a round shackle over a square body, white (tinted when drawn)
    static Texture2D MakeLock()
    {
        const int n = 32;
        var t = new Texture2D(n, n, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, hideFlags = HideFlags.DontSave };
        var px = new Color[n * n];
        for (int y = 0; y < n; y++)                               // (y up)
            for (int x = 0; x < n; x++)
            {
                float a = 0f;
                if (x >= 6 && x <= 25 && y >= 2 && y <= 16) a = 1f;                                   // body
                if (x >= 14 && x <= 17 && y >= 6 && y <= 11) a = 0f;                                 // keyhole
                float dx = x - 15.5f, dy = y - 17f, d = Mathf.Sqrt(dx * dx + dy * dy);
                if (y > 16 && d <= 8f && d >= 4.5f) a = 1f;                                          // shackle
                px[y * n + x] = new Color(1f, 1f, 1f, a);
            }
        t.SetPixels(px); t.Apply();
        return t;
    }

    void Styles()
    {
        if (sName != null) return;
        sName = new GUIStyle(GUI.skin.label) { fontSize = 15, fontStyle = FontStyle.Bold, alignment = TextAnchor.LowerLeft, wordWrap = false, clipping = TextClipping.Clip };
        sSub = new GUIStyle(GUI.skin.label) { fontSize = 13, alignment = TextAnchor.UpperLeft, wordWrap = false, clipping = TextClipping.Clip };
        sTick = new GUIStyle(GUI.skin.label) { fontSize = 22, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
        sTick.normal.textColor = Color.white;
        sCardTitle = new GUIStyle(GUI.skin.label) { fontSize = 26, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleLeft };
        sCardText = new GUIStyle(GUI.skin.label) { fontSize = 17, alignment = TextAnchor.MiddleLeft, richText = true, wordWrap = false };
        sNote = new GUIStyle(GUI.skin.label) { fontSize = 17, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
        sNote.normal.textColor = new Color(1f, 0.85f, 0.3f);
        sHead = new GUIStyle(GUI.skin.label) { fontSize = 20, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
        sHead.normal.textColor = new Color(0.95f, 0.88f, 0.7f);
        sTitle = new GUIStyle(GUI.skin.label) { fontSize = 28, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleLeft };
        sInfo = new GUIStyle(GUI.skin.label) { fontSize = 16, alignment = TextAnchor.MiddleRight, richText = true };
        sBigButton = new GUIStyle(GUI.skin.button) { fontSize = 22, fontStyle = FontStyle.Bold };
    }

    static readonly Color Lit = new Color(0.36f, 0.85f, 0.42f), Gold = new Color(1f, 0.82f, 0.28f), Dim = new Color(0.34f, 0.35f, 0.38f);

    static void Tint(Rect r, Texture t, Color c) { var old = GUI.color; GUI.color = c; GUI.DrawTexture(r, t); GUI.color = old; }

    void DrawNode(Rect r, NodeState st, bool picked, float pulse)
    {
        if (picked) Tint(new Rect(r.x - 7f, r.y - 7f, r.width + 14f, r.height + 14f), ringTex, Color.white);
        switch (st)
        {
            case NodeState.Owned:
                Tint(r, discTex, new Color(0.18f, 0.55f, 0.24f));
                Tint(r, ringTex, Lit);
                GUI.Label(r, "✓", sTick);
                break;
            case NodeState.CanBuy:
                Tint(new Rect(r.x - 9f, r.y - 9f, r.width + 18f, r.height + 18f), discTex, new Color(Gold.r, Gold.g, Gold.b, 0.18f + 0.22f * pulse));
                Tint(r, discTex, new Color(0.2f, 0.17f, 0.08f));
                Tint(r, ringTex, new Color(Gold.r, Gold.g, Gold.b, 0.75f + 0.25f * pulse));
                break;
            case NodeState.TooDear:
                Tint(r, discTex, new Color(0.15f, 0.15f, 0.16f));
                Tint(r, ringTex, new Color(0.5f, 0.5f, 0.53f));
                break;
            case NodeState.Locked:
                Tint(r, discTex, new Color(0.10f, 0.10f, 0.11f));
                Tint(r, ringTex, new Color(0.3f, 0.3f, 0.32f));
                Tint(new Rect(r.center.x - r.width * 0.28f, r.center.y - r.height * 0.3f, r.width * 0.56f, r.height * 0.56f), lockTex, new Color(0.62f, 0.62f, 0.66f));
                break;
            default:
                Tint(r, discTex, new Color(0.10f, 0.10f, 0.11f, 0.6f));
                Tint(r, ringTex, new Color(0.3f, 0.3f, 0.32f, 0.55f));
                var dots = new GUIStyle(sTick) { fontSize = 16 };
                dots.normal.textColor = new Color(0.5f, 0.5f, 0.5f);
                GUI.Label(r, "...", dots);
                break;
        }
    }

    static string Price(Step s)
    {
        return s.coins.ToString("N0") + " coins" + (s.goldLitres > 0f ? " + " + s.goldLitres.ToString("F0") + " L gold" : "");
    }

    void OnGUI()
    {
        if (Prologue.Playing) return;
        if (!Open)
        {
            return;                                                // (U / Start is in the help, H)
        }
        GUI.depth = -5;                                           // over the help, the prompts and the labels
        Ui.Begin(PW + 40f, PH + 40f);                             // a big UI size is held down so the tree still fits
        if (discTex == null) { discTex = MakeRound(false); ringTex = MakeRound(true); lockTex = MakeLock(); }
        Styles();
        if (sel < 0 || sel >= Nodes.Length) sel = DefaultSelection();
        var money = Money.Instance;
        float pulse = 0.5f + 0.5f * Mathf.Sin(Time.unscaledTime * 4f);
        var area = new Rect((Ui.W - PW) / 2f, (Ui.H - PH) / 2f, PW, PH);
        GUI.Box(area, GUIContent.none);
        GUI.Label(new Rect(area.x + 20, area.y + 10, 300, 40), "Upgrades", sTitle);
        string help = Pad.InUse ? "D-pad move   A buy   X sell back   Start closes   Back menu" : "Click or arrow keys to pick   Enter buys   U or Esc closes";
        if (money != null)
            GUI.Label(new Rect(area.xMax - 900, area.y + 10, 880, 40),
                "<b>Coins " + money.Coins.ToString("N0") + "</b>      <b><color=#ffd147>Gold " + money.GoldLitres.ToString("F0") + " L</color></b>        <color=#aaaaaa>" + help + "</color>", sInfo);

        // ---- the columns
        float colW = (PW - 40f) / TreeCols, left = area.x + 20f;
        float headY = area.y + 58f, treeTop = area.y + 98f;
        float cardTop = area.yMax - 16f - CardH, treeBottom = cardTop - 40f;
        int rows = treeRows;
        float rowH = (treeBottom - treeTop) / rows, D = Mathf.Min(40f, rowH - 8f);
        GUI.Label(new Rect(left, headY, colW, 30), "Breaking", sHead);
        GUI.Label(new Rect(left + colW, headY, colW * 2f, 30), "Moving dirt", sHead);
        GUI.Label(new Rect(left + colW * 3f, headY, colW, 30), "Hauling", sHead);
        Ui.Fill(new Rect(left + colW - 1f, headY, 2f, treeBottom - headY), new Color(1f, 1f, 1f, 0.07f));
        Ui.Fill(new Rect(left + colW * 3f - 1f, headY, 2f, treeBottom - headY), new Color(1f, 1f, 1f, 0.07f));

        var nodeList = Nodes;
        var centre = new Vector2[nodeList.Length];
        for (int i = 0; i < nodeList.Length; i++)
            centre[i] = new Vector2(left + nodeList[i].col * colW + 24f + D * 0.5f, treeTop + (nodeList[i].row + 0.5f) * rowH);

        // the lines first, so the nodes sit on top: each node joins the one above it in its branch, lit once it
        // is owned; the backpack's line comes across from Shovel 6 (what it needs)
        const float LW = 4f;
        for (int i = 1; i < nodeList.Length; i++)
        {
            var n = nodeList[i];
            if (nodeList[i - 1].col != n.col || n.step == 0 && n.branch >= 0) continue;
            var st = StateOf(i);
            Color c = st == NodeState.Owned ? Lit : st == NodeState.CanBuy ? Gold * 0.85f : st == NodeState.Coming ? new Color(0.25f, 0.25f, 0.27f) : Dim;
            Ui.Fill(new Rect(centre[i].x - LW / 2f, centre[i - 1].y, LW, centre[i].y - centre[i - 1].y), c);
        }
        int shovel6 = -1, pack1 = -1;
        for (int i = 0; i < nodeList.Length; i++)
        {
            if (nodeList[i].branch == (int)Branch.Shovel && nodeList[i].step == Steps[1].Length - 1) shovel6 = i;
            if (nodeList[i].branch == (int)Branch.Backpack && nodeList[i].step == 0) pack1 = i;
        }
        if (shovel6 >= 0 && pack1 >= 0)
        {
            var st = StateOf(pack1);
            Color c = st == NodeState.Owned ? Lit : st == NodeState.CanBuy ? Gold * 0.85f : StateOf(shovel6) == NodeState.Owned ? Lit * 0.7f : Dim;
            Vector2 a = centre[shovel6], b = centre[pack1];
            float midY = (a.y + b.y) * 0.5f;
            Ui.Fill(new Rect(a.x - LW / 2f, a.y, LW, midY - a.y + LW / 2f), c);
            Ui.Fill(new Rect(a.x, midY - LW / 2f, b.x - a.x, LW), c);
            Ui.Fill(new Rect(b.x - LW / 2f, midY - LW / 2f, LW, b.y - midY + LW / 2f), c);
        }

        // the nodes, each with its name and price beside it; a click picks it
        for (int i = 0; i < nodeList.Length; i++)
        {
            var n = nodeList[i];
            var st = StateOf(i);
            var r = new Rect(centre[i].x - D / 2f, centre[i].y - D / 2f, D, D);
            DrawNode(r, st, i == sel, pulse);
            float lx = r.xMax + 10f, lw = colW - D - 44f;
            Color nameC = st == NodeState.Owned ? new Color(0.65f, 1f, 0.65f) : st == NodeState.CanBuy ? Gold : st == NodeState.TooDear ? new Color(0.8f, 0.8f, 0.8f) : new Color(0.5f, 0.5f, 0.52f);
            if (i == sel) nameC = Color.white;
            sName.normal.textColor = nameC;
            GUI.Label(new Rect(lx, centre[i].y - 22f, lw, 22f), NodeName(n), sName);
            string sub; Color subC;
            if (st == NodeState.Owned) { sub = "owned"; subC = new Color(0.45f, 0.75f, 0.45f); }
            else if (st == NodeState.Coming) { sub = "coming"; subC = new Color(0.42f, 0.42f, 0.44f); }
            else if (st == NodeState.Locked) { sub = "locked   " + Price(Steps[n.branch][n.step]); subC = new Color(0.42f, 0.42f, 0.44f); }
            else { sub = Price(Steps[n.branch][n.step]); subC = st == NodeState.CanBuy ? new Color(1f, 0.9f, 0.55f) : new Color(0.85f, 0.5f, 0.45f); }
            sSub.normal.textColor = subC;
            GUI.Label(new Rect(lx, centre[i].y, lw, 20f), sub, sSub);
            if (GUI.Button(new Rect(r.x - 4f, r.y - 4f, colW - 30f, D + 8f), GUIContent.none, GUIStyle.none)) sel = i;
        }

        if (noteTimer > 0f) GUI.Label(new Rect(area.x, cardTop - 36f, area.width, 30), note, sNote);
        Card(new Rect(area.x + 16f, cardTop, area.width - 32f, CardH), pulse);
    }

    // the picked node, bigger, at the bottom: what it is, what it does, what it costs, what it needs, and Buy / Sell back
    void Card(Rect r, float pulse)
    {
        GUI.Box(r, GUIContent.none);
        if (sel < 0) return;
        var n = Nodes[sel];
        var st = StateOf(sel);
        DrawNode(new Rect(r.x + 26f, r.y + (r.height - 84f) / 2f, 84f, 84f), st, false, pulse);
        float x = r.x + 136f, w = r.width - 136f - 260f;
        GUI.Label(new Rect(x, r.y + 10f, w, 36f), NodeName(n), sCardTitle);
        if (n.branch < 0)
        {
            GUI.Label(new Rect(x, r.y + 50f, w, 26f), "Coming later.  Not in the game yet.", sCardText);
            return;
        }
        var s = Steps[n.branch][n.step];
        var b = (Branch)n.branch;
        GUI.Label(new Rect(x, r.y + 48f, w, 26f), s.effect, sCardText);
        string priceLine, needs = "";
        var money = Money.Instance;
        if (st == NodeState.Owned)
        {
            string by = boughtBy[n.branch][n.step];
            priceLine = s.coins == 0 && s.goldLitres <= 0f ? "<color=#8fe08f>You start with this.</color>" : "<color=#8fe08f>Owned" + (by != null ? "  (bought by " + by + ")" : "") + ".</color>   Sells back for " + Price(s) + ".";
        }
        else
        {
            priceLine = "Price:  <b>" + Price(s) + "</b>";
            // what it needs, each with a tick or a cross
            var parts = new System.Collections.Generic.List<string>();
            if (n.step > 0) parts.Add(Need(Steps[n.branch][n.step - 1].name, level[n.branch] >= n.step));
            if (b == Branch.Backpack && n.step == 0) parts.Add(Need("Shovel 6", level[(int)Branch.Shovel] >= MaxLevel(Branch.Shovel)));
            if (money != null)
            {
                parts.Add(Need(s.coins.ToString("N0") + " coins", money.Coins >= s.coins));
                if (s.goldLitres > 0f) parts.Add(Need(s.goldLitres.ToString("F0") + " L gold", money.GoldStore >= GoldVoxels(s.goldLitres)));
            }
            needs = "Needs:   " + string.Join("      ", parts.ToArray());
        }
        GUI.Label(new Rect(x, r.y + 80f, w, 26f), priceLine, sCardText);
        if (needs.Length > 0) GUI.Label(new Rect(x, r.y + 110f, w, 26f), needs, sCardText);

        // the buttons
        float bx = r.xMax - 240f;
        if (st == NodeState.CanBuy)
        {
            if (GUI.Button(new Rect(bx, r.y + 20f, 220f, 60f), Pad.InUse ? "A   Buy" : "Buy", sBigButton)) BuySelected();
        }
        else
        {
            string why = st == NodeState.Owned ? "Owned" : st == NodeState.Locked ? "Locked" : "Can't afford yet";
            var dim = new GUIStyle(sBigButton) { fontSize = 18 };
            dim.normal.textColor = dim.hover.textColor = new Color(0.55f, 0.55f, 0.55f);
            GUI.enabled = false;
            GUI.Button(new Rect(bx, r.y + 20f, 220f, 60f), why, dim);
            GUI.enabled = true;
        }
        bool newest = st == NodeState.Owned && n.step == level[n.branch] - 1 && CantSellBack(b) == null;
        if (newest && GUI.Button(new Rect(bx, r.y + 94f, 220f, 44f), Pad.InUse ? "X   Sell back" : "Sell back")) SellBack(b);
    }

    static string Need(string what, bool ok)
    {
        return ok ? "<color=#8fe08f>✓ " + what + "</color>" : "<color=#ff8a70>✗ " + what + "</color>";
    }
}
