// F5 saves the game, F6 loads it.  One save slot, in Unity's own folder for this game
// (Application.persistentDataPath).  Everything is gzipped into one file.
//
// In the built game it also looks after itself: it carries on from the save when the game starts, saves every
// AutoEvery seconds of play and when the game is closed.  "New game" (Esc menu) puts the save aside as a backup
// (".old") and starts the site afresh.  In the editor none of that happens (tests start fresh and must never
// write the owner's save) unless a test switches it on with TestAuto and points PathOverride at a file of its own.
//
// What is kept: the ground (only what has changed since the start, see VoxelWorldSave.cs), grass, every dirt
// tally and loose clod, the cart's place and load, the dozer and the worker, which parts are found and fitted,
// the coins and gold in the pot, the upgrades bought, the mountain road's ticks, the goals, whether the road piles
// have been dropped, and the trees the dozer has pushed over, their wood lying about and the wood collected.
// Each part is written one after the other; a part added later goes on the end, so a save from before it simply
// stops early, and loading it gives that part its old-save start (the goals skip what that save has already done).
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using UnityEngine;

public class SaveGame : MonoBehaviour
{
    public static SaveGame Instance { get; private set; }
    public static string FilePath { get { return PathOverride ?? Path.Combine(Application.persistentDataPath, "voxel-dozer-save.bin"); } }
    public static string PathOverride;                       // tests: save somewhere else
    public static bool TestAuto;                             // tests: do the built game's autosave and carry-on in the editor
    public static float AutoEvery = 300f;                    // seconds of play between autosaves
    static bool freshStart;                                  // New game: don't carry on from a save this once
    public static bool AutoOn { get { return (!Application.isEditor || TestAuto) && !TrailerMode.On; } }   // (trailer mode: a fresh game, never saved)
    public float SinceSave { get; private set; }
    public bool CarriedOn { get; private set; }
    bool triedCarryOn;
    /// The start-up carry-on from the save (if any) has been done.
    public bool StartupDone { get { return triedCarryOn; } }

    // what the last save or load did, for the message and for tests
    public long LastBytes { get; private set; }
    public float LastMs { get; private set; }

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    void Update()
    {
        if (AutoOn && !triedCarryOn && VoxelWorld.Instance != null && Worker.Instance != null && Time.timeSinceLevelLoad > 0.5f)
        {
            triedCarryOn = true;
            if (freshStart) freshStart = false;
            else if (File.Exists(FilePath))
            {
                string said = Load();
                CarriedOn = said.StartsWith("Game loaded");
                Say(CarriedOn ? "Welcome back: carrying on from your saved game." : said);
            }
        }
        if (AutoOn && Time.timeScale > 0f)
        {
            SinceSave += Time.unscaledDeltaTime;
            if (SinceSave >= AutoEvery)
            {
                string said = Save();
                if (!said.StartsWith("Game saved")) Say(said);
                else if (Worker.Instance != null) Worker.Instance.Say("Autosaved", 1.5f);
            }
        }
        if (Worker.Instance != null && Worker.Instance.useOverride) return;     // not while a test is driving
        if (Input.GetKeyDown(KeyCode.F5)) Say(Save());
        if (Input.GetKeyDown(KeyCode.F6)) Say(Load());
    }

    void OnApplicationQuit() { if (AutoOn && VoxelWorld.Instance != null) Save(); }

    /// Starts the site afresh.  The old save is kept beside it as a backup (".old").
    public void NewGame()
    {
        try { if (File.Exists(FilePath)) { string old = FilePath + ".old"; if (File.Exists(old)) File.Delete(old); File.Move(FilePath, old); } }
        catch (System.Exception e) { Say("Could not put the old save aside: " + e.Message); return; }
        freshStart = true;
        Time.timeScale = 1f;
        UnityEngine.SceneManagement.SceneManager.LoadScene(UnityEngine.SceneManagement.SceneManager.GetActiveScene().buildIndex);
    }

    /// Reset ground (Esc menu): the dirt all back as new; coins, upgrades, finds and goals kept.
    public void ResetGround()
    {
        var w = VoxelWorld.Instance;
        if (w == null) return;
        var wk = Worker.Instance; var dingo = Dingo.Instance; var dozer = FindFirstObjectByType<DozerController>(); var cart = MineCart.Instance;
        if (dingo != null && dingo.Driven) dingo.GetOff();
        if (wk != null && wk.RidingCart) wk.GetOffCart();
        w.ResetGround();
        if (RoadPile.Instance != null) { RoadPile.Instance.Placed = false; RoadPile.Instance.Placed2 = false; }   // the road piles are part of the ground as new
        if (dozer != null) dozer.Place(dozer.transform.position, dozer.transform.eulerAngles.y);   // back on top of the ground
        if (dingo != null) dingo.Park();
        if (cart != null) { cart.CancelTrip(); cart.SetAlong(1e6f); }                                                  // out at the tunnel mouth
        if (wk != null && !wk.InDozer) wk.Teleport(dozer != null ? dozer.transform.position + new Vector3(-4.5f, 0f, -2.5f) : wk.transform.position, 20f);
        Say("Ground reset: all the dirt is back as new.  Coins and upgrades kept.");
    }

    static void Say(string text) { if (Worker.Instance != null) Worker.Instance.Say(text, 3f); }

    public string Save()
    {
        SinceSave = 0f;
        var world = VoxelWorld.Instance;
        if (world == null) return "Nothing to save yet.";
        var watch = Stopwatch.StartNew();
        string temp = FilePath + ".tmp";
        try
        {
            using (var file = File.Create(temp))
            using (var zip = new GZipStream(file, System.IO.Compression.CompressionLevel.Fastest))
            using (var w = new BinaryWriter(zip))
            {
                world.WriteSave(w);
                var dozer = FindFirstObjectByType<DozerController>();
                w.Write(dozer != null);
                if (dozer != null) dozer.WriteState(w);
                var cart = MineCart.Instance;
                w.Write(cart != null);
                if (cart != null)
                {
                    w.Write(cart.Along);
                    w.Write(cart.spec.name ?? ""); w.Write(cart.spec.capacity); w.Write(cart.spec.pushFactor);
                    w.Write(cart.spec.tipSeconds); w.Write(cart.spec.pourPerStep);
                }
                var finds = Finds.Instance;
                w.Write(finds != null ? Finds.Count : 0);
                if (finds != null) for (int k = 0; k < Finds.Count; k++) { w.Write(finds.Collected[k]); w.Write(finds.Installed[k]); w.Write(finds.Found[k]); }
                var worker = Worker.Instance;
                w.Write(worker != null);
                if (worker != null) worker.WriteState(w);
                var money = Money.Instance;
                w.Write(money != null);
                if (money != null) money.WriteState(w);
                var upgrades = Upgrades.Instance;
                w.Write(upgrades != null);
                if (upgrades != null) upgrades.WriteState(w);
                var road = MountainRoadJob.Instance;
                w.Write(road != null);
                if (road != null) road.WriteState(w);
                var goals = Goals.Instance;
                w.Write(goals != null);
                if (goals != null) goals.WriteState(w);
                var pile = RoadPile.Instance;
                w.Write(pile != null);
                if (pile != null) w.Write(pile.Placed);
                var fell = TreeFelling.Instance;
                w.Write(fell != null);
                if (fell != null) { w.Write(pile != null && pile.Placed2); fell.WriteState(w); }
                w.Write(worker != null ? worker.PocketGold : 0);
                var ending = Ending.Instance;
                w.Write(ending != null);
                if (ending != null) ending.WriteState(w);
            }
            if (File.Exists(FilePath)) File.Delete(FilePath);
            File.Move(temp, FilePath);                       // only replace the old save once the new one is complete
        }
        catch (System.Exception e)
        {
            UnityEngine.Debug.LogException(e);
            return "Could not save: " + e.Message;
        }
        LastMs = (float)watch.Elapsed.TotalMilliseconds;
        LastBytes = new FileInfo(FilePath).Length;
        return "Game saved (" + (LastBytes / 1048576f).ToString("F1") + " MB).  F6 loads it.";
    }

    public string Load()
    {
        var world = VoxelWorld.Instance;
        if (world == null) return "Not ready to load yet.";
        if (!File.Exists(FilePath)) return "There is no saved game yet.  F5 saves.";
        var watch = Stopwatch.StartNew();
        try
        {
            using (var file = File.OpenRead(FilePath))
            using (var zip = new GZipStream(file, CompressionMode.Decompress))
            using (var r = new BinaryReader(zip))
            {
                world.ReadSave(r);
                var dozer = FindFirstObjectByType<DozerController>();
                if (r.ReadBoolean()) { if (dozer != null) dozer.ReadState(r); else throw new IOException("No dozer in the scene."); }
                var cart = MineCart.Instance;
                if (r.ReadBoolean())
                {
                    float along = r.ReadSingle();
                    var spec = new CartSpec { name = r.ReadString(), capacity = r.ReadInt32(), pushFactor = r.ReadSingle(), tipSeconds = r.ReadSingle(), pourPerStep = r.ReadInt32() };
                    if (cart != null) { cart.CancelTrip(); cart.spec = spec; cart.SetAlong(along); }   // (an automatic cart's trip isn't saved)
                }
                var finds = Finds.Instance;
                int count = r.ReadInt32();
                for (int k = 0; k < count; k++)
                {
                    bool collected = r.ReadBoolean(), installed = r.ReadBoolean(), found = r.ReadBoolean();
                    if (finds != null && k < Finds.Count) finds.SetState(k, collected, installed, found);
                }
                var worker = Worker.Instance;
                if (r.ReadBoolean() && worker != null) worker.ReadState(r);
                var money = Money.Instance;
                bool hasMoney;
                try { hasMoney = r.ReadBoolean(); } catch (EndOfStreamException) { hasMoney = false; }   // saved before there was money
                if (hasMoney) { if (money != null) money.ReadState(r); else { r.ReadInt64(); r.ReadInt64(); r.ReadDouble(); } }
                else if (money != null) money.Clear();
                var upgrades = Upgrades.Instance;
                bool hasUpgrades;
                try { hasUpgrades = hasMoney && r.ReadBoolean(); } catch (EndOfStreamException) { hasUpgrades = false; }   // saved before upgrades
                if (hasUpgrades) { if (upgrades != null) upgrades.ReadState(r); }
                else if (upgrades != null) upgrades.Reset();
                var road = MountainRoadJob.Instance;
                bool hasRoad;
                try { hasRoad = hasUpgrades && r.ReadBoolean(); } catch (EndOfStreamException) { hasRoad = false; }   // saved before the mountain road
                if (hasRoad) { if (road != null) road.ReadState(r); }
                else if (road != null) road.Clear();
                var goals = Goals.Instance;
                bool hasGoals;
                try { hasGoals = hasRoad && r.ReadBoolean(); } catch (EndOfStreamException) { hasGoals = false; }   // saved before the goals
                if (hasGoals) { if (goals != null) goals.ReadState(r); }
                else if (goals != null) goals.FromOldSave();
                var pile = RoadPile.Instance;
                bool hasPile;
                try { hasPile = hasGoals && r.ReadBoolean(); } catch (EndOfStreamException) { hasPile = false; }   // saved before the road pile
                bool placed = hasPile && r.ReadBoolean();
                if (pile != null) pile.Placed = placed;                                     // not dropped yet: RoadPile drops it now
                bool hasFell;
                try { hasFell = hasPile && r.ReadBoolean(); } catch (EndOfStreamException) { hasFell = false; }   // saved before trees could be pushed over
                bool placed2 = hasFell && r.ReadBoolean();
                if (pile != null) pile.Placed2 = placed2;                                   // the second pile (beside the road)
                var fell = TreeFelling.Instance;
                if (hasFell) { if (fell != null) fell.ReadState(r); }
                else if (fell != null) fell.FromOldSave();
                int pockets = 0;
                if (hasFell && fell != null) { try { pockets = r.ReadInt32(); } catch (EndOfStreamException) { pockets = 0; } }   // saved before pockets
                if (worker != null) worker.PocketGold = pockets;
                var ending = Ending.Instance;
                bool hasEnding;
                try { hasEnding = hasFell && r.ReadBoolean(); } catch (EndOfStreamException) { hasEnding = false; }   // saved before the ending
                if (hasEnding) { if (ending != null) ending.ReadState(r); else { r.ReadInt32(); r.ReadBoolean(); r.ReadDouble(); r.ReadDouble(); } }
                else if (ending != null) ending.Clear();
            }
        }
        catch (System.Exception e)
        {
            UnityEngine.Debug.LogException(e);
            return "Could not load: " + e.Message;
        }
        LastMs = (float)watch.Elapsed.TotalMilliseconds;
        LastBytes = new FileInfo(FilePath).Length;
        return "Game loaded.";
    }
}
