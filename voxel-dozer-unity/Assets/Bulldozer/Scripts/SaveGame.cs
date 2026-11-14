// F5 saves the game, F6 loads it.  One save slot, in Unity's own folder for this game
// (Application.persistentDataPath).  Everything is gzipped into one file.
//
// What is kept: the ground (only what has changed since the start, see VoxelWorldSave.cs), grass, every dirt
// tally and loose clod, the cart's place and load, the dozer and the worker, and which parts are found and fitted.
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using UnityEngine;

public class SaveGame : MonoBehaviour
{
    public static SaveGame Instance { get; private set; }
    public static string FilePath { get { return Path.Combine(Application.persistentDataPath, "voxel-dozer-save.bin"); } }

    // what the last save or load did, for the message and for tests
    public long LastBytes { get; private set; }
    public float LastMs { get; private set; }

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    void Update()
    {
        if (Worker.Instance != null && Worker.Instance.useOverride) return;     // not while a test is driving
        if (Input.GetKeyDown(KeyCode.F5)) Say(Save());
        if (Input.GetKeyDown(KeyCode.F6)) Say(Load());
    }

    static void Say(string text) { if (Worker.Instance != null) Worker.Instance.Say(text, 3f); }

    public string Save()
    {
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
                    if (cart != null) { cart.spec = spec; cart.SetAlong(along); }
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
