// Money: the team's one shared pot of coins.
//
// Dirt that goes down the hopper at the dump (the end of the rails, out by the road) is sorted and sold:
//   1 coin for every 10 litres of soil, clay, rock or quartz, and 50 times that for gold ore.
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
    double fraction;                                      // part coins not yet paid out (a clod is only 2 litres)

    // the "+87 coins" that pops up while a load is being paid for
    long popCoins, popGold;
    float popTimer;
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

    /// Pays for dirt tipped at the dump.  `voxelsByMaterial[m]` is how much of loose material m went out.
    /// Returns the whole coins added this time.
    public long Pay(int[] voxelsByMaterial)
    {
        double value = 0, gold = 0;
        for (int m = VoxelWorld.LooseSoil; m <= VoxelWorld.LooseGold && m < voxelsByMaterial.Length; m++)
        {
            if (voxelsByMaterial[m] <= 0) continue;
            double v = ValueOf(m, voxelsByMaterial[m]);
            value += v;
            if (m == VoxelWorld.LooseGold) gold += v;
        }
        if (value <= 0) return 0;
        fraction += value;
        long whole = (long)System.Math.Floor(fraction);
        fraction -= whole;
        Coins += whole;
        Earned += whole;
        if (popTimer <= 0f) { popCoins = 0; popGold = 0; System.Array.Clear(popLitres, 0, popLitres.Length); }
        for (int m = VoxelWorld.LooseSoil; m <= VoxelWorld.LooseGold && m < voxelsByMaterial.Length; m++)
            popLitres[m] += voxelsByMaterial[m] * VoxelWorld.VoxelVolume * 1000.0;
        popCoins += whole;
        popGold += (long)System.Math.Round(gold);
        popTimer = 4f;
        return whole;
    }

    /// Takes coins out of the pot (upgrades).  False, and nothing taken, if there are not enough.
    public bool Spend(long coins)
    {
        if (coins < 0 || coins > Coins) return false;
        Coins -= coins;
        return true;
    }

    public void WriteState(System.IO.BinaryWriter w) { w.Write(Coins); w.Write(Earned); w.Write(fraction); }
    public void ReadState(System.IO.BinaryReader r) { Coins = r.ReadInt64(); Earned = r.ReadInt64(); fraction = r.ReadDouble(); popTimer = 0f; }
    public void Clear() { Coins = 0; Earned = 0; fraction = 0; popTimer = 0f; }

    void Update() { if (popTimer > 0f) popTimer -= Time.unscaledDeltaTime; }

    void OnGUI()
    {
        var big = new GUIStyle(GUI.skin.box) { fontSize = 22, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
        GUI.Box(new Rect(Screen.width - 230, 10, 220, 40), "Coins: " + Coins.ToString("N0"), big);
        if (popTimer > 0f && (popCoins > 0 || popLitres[VoxelWorld.LooseSoil] + popLitres[VoxelWorld.LooseRock] > 0))
        {
            var pop = new GUIStyle(big) { fontSize = 20 };
            pop.normal.textColor = new Color(1f, 0.85f, 0.25f);
            GUI.Box(new Rect(Screen.width - 230, 54, 220, 34), "+" + popCoins.ToString("N0") + (popGold > 0 ? "   (gold +" + popGold.ToString("N0") + ")" : ""), pop);
            // the hopper's sorting: what the load was, in litres
            string sorted = "";
            for (int m = VoxelWorld.LooseSoil; m <= VoxelWorld.LooseGold; m++)
                if (popLitres[m] >= 0.5) sorted += (sorted.Length > 0 ? "     " : "") + SortNames[m] + " " + popLitres[m].ToString("F0") + " L";
            var panel = new GUIStyle(GUI.skin.box) { fontSize = 18, alignment = TextAnchor.MiddleCenter };
            GUI.Box(new Rect(Screen.width / 2 - 330, 104, 660, 58), "Hopper sorted it:\n" + sorted + "     =  +" + popCoins.ToString("N0") + " coins", panel);
        }
    }
}
