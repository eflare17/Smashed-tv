// Money: the team's one shared pot of coins.
//
// Dirt that goes down the hopper at the dump (the end of the rails, 8 m out of the mine door) is sorted:
//   - soil, clay, rock and quartz are sold on the spot: 1 coin for every 10 litres;
//   - gold ore is kept, in the team's gold store.  The gold buyer's shed by the mine entrance buys it, at 50
//     times the price of dirt (E there sells all of it).  Gold you keep is for buying machinery later.
// A panel shows what the load was sorted into and what it fetched.  Tipping anywhere else pays nothing.
//
// Every change to the pot goes through Pay and Spend here, and nowhere else, so that when multiplayer comes
// the host can make each change and send it to the other players.
using UnityEngine;

public class Money : MonoBehaviour
{
    public static Money Instance { get; private set; }

    public const float CoinsPerLitre = 0.1f;              // 1 coin per 10 litres
    public const float GoldTimes = 50f;                   // gold ore is worth this many times as much

    public long Coins { get; private set; }               // in the pot now
    public long Earned { get; private set; }              // all ever paid in, for tests and later stats
    public int GoldStore { get; private set; }            // gold ore kept, in voxels, waiting to be sold (or spent on machinery)
    public float GoldLitres { get { return GoldStore * VoxelWorld.VoxelVolume * 1000f; } }
    public long GoldWorth { get { return (long)System.Math.Floor(ValueOf(VoxelWorld.LooseGold, GoldStore)); } }
    double fraction;                                      // part coins not yet paid out (a clod is only 2 litres)

    // the "+87 coins" that pops up while a load is being paid for
    long popCoins;
    float popTimer, sellTimer;
    string sellText = "";
    readonly double[] popLitres = new double[16];       // what the load being paid for was sorted into
    static readonly string[] SortNames = { "", "", "", "", "", "", "Soil", "Clay", "Rock", "Quartz", "Gold" };

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    /// What `voxels` of loose `material` are worth, in coins (with the fraction).
    public static double ValueOf(int material, int voxels)
    {
        double litres = voxels * VoxelWorld.VoxelVolume * 1000.0;
        double coins = litres * CoinsPerLitre;
        return material == VoxelWorld.LooseGold ? coins * GoldTimes : coins;
    }

    /// The hopper's sorting: `voxelsByMaterial[m]` is how much of loose material m went down it.  The dirt is
    /// sold for coins straight away; the gold goes into the gold store.  Returns the whole coins added.
    public long Pay(int[] voxelsByMaterial)
    {
        double value = 0;
        for (int m = VoxelWorld.LooseSoil; m <= VoxelWorld.LooseGold && m < voxelsByMaterial.Length; m++)
        {
            if (voxelsByMaterial[m] <= 0) continue;
            if (m == VoxelWorld.LooseGold) { GoldStore += voxelsByMaterial[m]; continue; }   // kept, not sold here
            value += ValueOf(m, voxelsByMaterial[m]);
        }
        if (popTimer <= 0f) { popCoins = 0; System.Array.Clear(popLitres, 0, popLitres.Length); }
        for (int m = VoxelWorld.LooseSoil; m <= VoxelWorld.LooseGold && m < voxelsByMaterial.Length; m++)
            popLitres[m] += voxelsByMaterial[m] * VoxelWorld.VoxelVolume * 1000.0;
        popTimer = 4f;
        if (value <= 0) return 0;
        fraction += value;
        long whole = (long)System.Math.Floor(fraction);
        fraction -= whole;
        Coins += whole;
        Earned += whole;
        popCoins += whole;
        if (whole > 0) GameAudio.Cash();
        return whole;
    }

    /// The gold buyer's shed: sells everything in the gold store.  Returns the coins it fetched.
    public long SellGold()
    {
        if (GoldStore <= 0) return 0;
        float litres = GoldLitres;
        fraction += ValueOf(VoxelWorld.LooseGold, GoldStore);
        GoldStore = 0;
        long whole = (long)System.Math.Floor(fraction);
        fraction -= whole;
        Coins += whole;
        Earned += whole;
        sellText = "Sold " + litres.ToString("F0") + " L of gold:  +" + whole.ToString("N0") + " coins";
        GameAudio.Cash();
        sellTimer = 4f;
        return whole;
    }

    /// Gives back what an upgrade cost, when it is sold back.  (Not counted as earned.)
    /// A job's pay: coins straight into the pot, with a note saying what for.
    public void Reward(long coins, string why)
    {
        if (coins <= 0) return;
        Coins += coins; Earned += coins;
        if (popTimer <= 0f) { popCoins = 0; System.Array.Clear(popLitres, 0, popLitres.Length); }
        popCoins += coins; popTimer = 4f;
        sellText = why; sellTimer = 5f;
    }

    public void Refund(long coins, int goldVoxels) { if (coins > 0) Coins += coins; if (goldVoxels > 0) GoldStore += goldVoxels; }

    /// The F8 test key: free coins and gold, to try upgrades without digging for them.
    public void TestGrant(long coins, int goldVoxels) { Coins += coins; GoldStore += goldVoxels; }

    /// Takes gold out of the store (machinery).  False, and nothing taken, if there is not enough.
    public bool SpendGold(int voxels)
    {
        if (voxels < 0 || voxels > GoldStore) return false;
        GoldStore -= voxels;
        return true;
    }

    /// Takes coins out of the pot (upgrades).  False, and nothing taken, if there are not enough.
    public bool Spend(long coins)
    {
        if (coins < 0 || coins > Coins) return false;
        Coins -= coins;
        return true;
    }

    public void WriteState(System.IO.BinaryWriter w) { w.Write(Coins); w.Write(Earned); w.Write(fraction); w.Write(GoldStore); }
    public void ReadState(System.IO.BinaryReader r)
    {
        Coins = r.ReadInt64(); Earned = r.ReadInt64(); fraction = r.ReadDouble(); popTimer = 0f; sellTimer = 0f;
        try { GoldStore = r.ReadInt32(); } catch (System.IO.EndOfStreamException) { GoldStore = 0; }   // saved before the gold store
    }
    public void Clear() { Coins = 0; Earned = 0; fraction = 0; GoldStore = 0; popTimer = 0f; sellTimer = 0f; }

    void Update()
    {
        if (popTimer > 0f) popTimer -= Time.unscaledDeltaTime;
        if (sellTimer > 0f) sellTimer -= Time.unscaledDeltaTime;
    }

    void OnGUI()
    {
        Ui.Begin();
        if (Prologue.Playing) return;
        // top left, small: coins and gold
        var big = new GUIStyle(GUI.skin.box) { fontSize = 22, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
        var coinStyle = new GUIStyle(GUI.skin.label) { fontSize = 20, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleLeft };
        var goldStyle = new GUIStyle(coinStyle) { fontSize = 16 };
        goldStyle.normal.textColor = new Color(1f, 0.82f, 0.2f);
        GUI.Box(new Rect(Hud.Margin, 10, 200, 54), GUIContent.none);
        GUI.Label(new Rect(Hud.Margin + 10, 11, 190, 28), Coins.ToString("N0") + " coins", coinStyle);
        GUI.Label(new Rect(Hud.Margin + 10, 37, 190, 24), "Gold " + GoldLitres.ToString("F0") + " L", goldStyle);
        var pop = new GUIStyle(big) { fontSize = 20 };
        pop.normal.textColor = new Color(1f, 0.85f, 0.25f);
        if (popTimer > 0f)
        {
            if (popCoins > 0) GUI.Box(new Rect(Hud.Margin + 206, 10, 140, 34), "+" + popCoins.ToString("N0"), pop);
            // the hopper's sorting: what the load was, in litres; the gold goes to the gold store
            string sorted = "";
            for (int m = VoxelWorld.LooseSoil; m < VoxelWorld.LooseGold; m++)
                if (popLitres[m] >= 0.5) sorted += (sorted.Length > 0 ? "     " : "") + SortNames[m] + " " + popLitres[m].ToString("F0") + " L";
            string line = (sorted.Length > 0 ? sorted + "     =  +" + popCoins.ToString("N0") + " coins" : "");
            if (popLitres[VoxelWorld.LooseGold] >= 0.5) line += (line.Length > 0 ? "\n" : "") + "Gold " + popLitres[VoxelWorld.LooseGold].ToString("F0") + " L  ->  your gold store (sell it at the gold buyer's shed)";
            if (line.Length > 0)
            {
                var panel = new GUIStyle(GUI.skin.box) { fontSize = 18, alignment = TextAnchor.MiddleCenter };
                GUI.Box(new Rect(Ui.W / 2 - 360, 104, 720, 78), "Hopper sorted it:\n" + line, panel);
            }
        }
        if (sellTimer > 0f)
        {
            var sold = new GUIStyle(big) { fontSize = 22 };
            sold.normal.textColor = new Color(1f, 0.85f, 0.25f);
            GUI.Box(new Rect(Ui.W / 2 - 260, 104, 520, 44), sellText, sold);
        }
    }
}
