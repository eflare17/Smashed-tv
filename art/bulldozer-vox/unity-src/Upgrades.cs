// The upgrade tree: the team's one shared set of upgrades, bought with the coins (and, for machinery, gold) in
// the shared pot (Money.cs).  U opens it.  Click an upgrade to buy it; it works straight away.  The newest one in
// a branch can be sold back for everything it cost.
//
// Three columns:
//   Breaking      Pick 1-5, then the Jackhammer (coming)
//   Moving dirt   Shovel 1-6, then the Backpack (needs Shovel 6, coins and gold), Backpack 1-8
//   Hauling       Cart 1-2, then the Motor cart, a bigger cart and the Automatic cart (coming)
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
        },
    };
    // shown after a branch, not buyable yet
    static readonly string[][] Coming =
    {
        new[] { "Jackhammer  (coming: needs gold)" },
        new string[0],
        new[] { "Motor cart  (coming: needs gold)", "Bigger cart  (coming)", "Automatic cart  (coming)" },
        new string[0],
    };

    static readonly float[] PickRadius = { 0.26f, 0.29f, 0.32f, 0.36f, 0.40f };
    static readonly float[] PickRock = { 0.8f, 0.84f, 0.88f, 0.94f, 1.0f };
    static readonly int[] ShovelHolds = { 480, 640, 800, 980, 1180, 1400 };
    static readonly float[] ShovelSpeed = { 1.0f, 1.1f, 1.2f, 1.3f, 1.45f, 1.6f };
    static readonly int[] PackHolds = { 819, 1229, 1638, 2048, 2458, 3072, 3584, 4096 };
    static readonly float[] PackRate = { 1.0f, 1.4f, 1.8f, 2.2f, 2.6f, 3.0f, 3.5f, 4.0f };
    static readonly int[] CartHolds = { 4096, 6144 };
    const float SuckBase = 130f;                                // voxels a second at backpack level 1 (about 32 litres)

    readonly int[] level = { 1, 1, 0, 1 };
    readonly string[][] boughtBy = new string[BranchCount][];
    public bool Open { get; private set; }
    string note = ""; float noteTimer;

    public int Level(Branch b) { return level[(int)b]; }
    public int MaxLevel(Branch b) { return Steps[(int)b].Length; }
    public bool HasBackpack { get { return level[(int)Branch.Backpack] > 0; } }

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
            int p = level[0] - 1, sh = level[1] - 1, bp = Mathf.Max(0, level[2] - 1);
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
        if (cart != null) cart.spec.capacity = CartHolds[level[3] - 1];
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
        if (open) Cursor.lockState = CursorLockMode.None;
    }

    void Update()
    {
        if (noteTimer > 0f) noteTimer -= Time.unscaledDeltaTime;
        var wk = Worker.Instance;
        if (wk != null && wk.useOverride) return;                // not while a test is driving
        if (Input.GetKeyDown(KeyCode.U)) SetOpen(!Open);
        if (Open && Input.GetKeyDown(KeyCode.Escape)) SetOpen(false);
        if (Input.GetKeyDown(KeyCode.F8) && Money.Instance != null)
        {
            Money.Instance.TestGrant(10000, GoldVoxels(50f));
            if (wk != null) wk.Say("Test key: +10,000 coins and 50 L of gold.", 3f);
        }
    }

    // ---------------------------------------------------------------- the tree screen
    void OnGUI()
    {
        if (!Open)
        {
            GUI.Box(new Rect(Screen.width - 230, Screen.height - 34, 220, 24), "U   upgrades");
            return;
        }
        var money = Money.Instance;
        float W = Mathf.Min(1180f, Screen.width - 40f), H = Mathf.Min(640f, Screen.height - 40f);
        var area = new Rect((Screen.width - W) / 2f, (Screen.height - H) / 2f, W, H);
        GUI.Box(area, GUIContent.none);
        GUI.Box(area, GUIContent.none);                           // twice, for a darker backing
        var title = new GUIStyle(GUI.skin.label) { fontSize = 24, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleLeft };
        GUI.Label(new Rect(area.x + 16, area.y + 8, 400, 34), "Upgrades", title);
        var info = new GUIStyle(GUI.skin.label) { fontSize = 16, alignment = TextAnchor.MiddleRight };
        if (money != null) GUI.Label(new Rect(area.xMax - 520, area.y + 8, 500, 34), "Coins " + money.Coins.ToString("N0") + "      Gold " + money.GoldLitres.ToString("F0") + " L      U or Esc closes", info);
        if (noteTimer > 0f)
        {
            var n = new GUIStyle(GUI.skin.label) { fontSize = 16, alignment = TextAnchor.MiddleCenter };
            n.normal.textColor = new Color(1f, 0.85f, 0.3f);
            GUI.Label(new Rect(area.x, area.yMax - 34, area.width, 28), note, n);
        }

        float colW = (W - 64f) / 3f, top = area.y + 54f;
        Column(new Rect(area.x + 16f, top, colW, H - 96f), "Breaking", new[] { Branch.Pick }, 0);
        Column(new Rect(area.x + 32f + colW, top, colW, H - 96f), "Moving dirt", new[] { Branch.Shovel, Branch.Backpack }, 1);
        Column(new Rect(area.x + 48f + colW * 2f, top, colW, H - 96f), "Hauling", new[] { Branch.Cart }, 2);
    }

    void Column(Rect r, string heading, Branch[] branches, int comingIndex)
    {
        var head = new GUIStyle(GUI.skin.label) { fontSize = 19, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
        GUI.Label(new Rect(r.x, r.y, r.width, 26), heading, head);
        float y = r.y + 30f, rowH = Mathf.Min(34f, (r.height - 34f) / 15f);
        var owned = new GUIStyle(GUI.skin.box) { fontSize = 13, alignment = TextAnchor.MiddleLeft, wordWrap = false };
        owned.normal.textColor = new Color(0.55f, 1f, 0.55f);
        var next = new GUIStyle(GUI.skin.button) { fontSize = 13, alignment = TextAnchor.MiddleLeft };
        var locked = new GUIStyle(GUI.skin.box) { fontSize = 13, alignment = TextAnchor.MiddleLeft };
        locked.normal.textColor = new Color(0.6f, 0.6f, 0.6f);
        foreach (var b in branches)
        {
            int i = (int)b;
            for (int k = 0; k < Steps[i].Length; k++)
            {
                var s = Steps[i][k];
                var row = new Rect(r.x, y, r.width, rowH - 3f);
                string price = s.coins > 0 ? s.coins.ToString("N0") + " coins" + (s.goldLitres > 0f ? " + " + s.goldLitres.ToString("F0") + " L gold" : "") : "start";
                if (k < level[i])
                {
                    string by = boughtBy[i][k] != null ? "   (" + boughtBy[i][k] + ")" : "";
                    GUI.Box(row, "  ✓ " + s.name + ":  " + s.effect + by, owned);
                    bool newest = k == level[i] - 1 && CantSellBack(b) == null;
                    if (newest && GUI.Button(new Rect(row.xMax - 92f, row.y + 2f, 88f, row.height - 4f), "Sell back")) SellBack(b);
                }
                else if (k == level[i])
                {
                    string why = CantBuy(b);
                    if (why == null)
                    {
                        if (GUI.Button(row, "  BUY " + s.name + ":  " + s.effect + "   [" + price + "]", next)) Buy(b);
                    }
                    else GUI.Box(row, "  " + s.name + ":  " + s.effect + "   [" + price + "]   " + why, locked);
                }
                else GUI.Box(row, "  " + s.name + ":  " + s.effect + "   [" + price + "]", locked);
                y += rowH;
            }
            y += 6f;
        }
        foreach (var c in Coming[comingIndex])
        {
            GUI.Box(new Rect(r.x, y, r.width, rowH - 3f), "  " + c, locked);
            y += rowH;
        }
    }
}
