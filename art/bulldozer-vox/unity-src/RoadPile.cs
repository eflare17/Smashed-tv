// A one-off pile of loose dirt at the foot of the mountain road, so there is dirt to push up the road for its first
// fills (the owner asked for it: the first stretch needs filling and there was nothing loose nearby to push).
//   - About 20 m³ (four full blade loads), a rounded heap just short of where the road starts, on its line, so you
//     drive into it and push it straight up the road.
//   - It is dropped once: in a new game as it starts, and in an older save the first time that save is loaded.
//     The save remembers it was dropped (SaveGame), so it never comes back once it has been used.
//   - Reset ground puts the ground back as new, and that includes this pile.
//   - Only in the real game (SaveGame.AutoOn): the editor's tests start without it unless they ask (TestAuto).
using UnityEngine;

public class RoadPile : MonoBehaviour
{
    public static RoadPile Instance { get; private set; }

    public const float Volume = 20f;            // m³
    public const float Radius = 3.4f;           // m, from the middle to the edge of the heap
    public const float BackFromStart = 4.6f;    // m: its middle is this far back down the road line from where the road starts

    /// Dropped already (in this game).
    public bool Placed { get; set; }
    public long LastAdded { get; private set; }  // voxels the last drop added (tests)

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    /// Where the middle of the heap goes.
    public static Vector2 Centre()
    {
        Vector2 p0 = MountainRoad.Point(0), p1 = MountainRoad.Point(Mathf.Min(4, MountainRoad.Count - 1));
        Vector2 dir = (p1 - p0).normalized;
        return p0 - dir * BackFromStart;
    }

    void Update()
    {
        if (Placed || !SaveGame.AutoOn) return;
        var sg = SaveGame.Instance; var w = VoxelWorld.Instance;
        if (sg == null || w == null || !sg.StartupDone) return;      // after the save (if any) has been loaded
        Drop();
    }

    /// Drops the pile now (and marks it dropped).
    public void Drop()
    {
        var w = VoxelWorld.Instance;
        if (w == null) return;
        Vector2 c = Centre();
        LastAdded = w.AddLoosePile(c.x, c.y, Radius, Volume);
        Placed = true;
        // anything parked on the spot is moved just behind the heap, facing up the road (ready to push it)
        Vector2 dir = (MountainRoad.Point(Mathf.Min(4, MountainRoad.Count - 1)) - MountainRoad.Point(0)).normalized;
        float yaw = Mathf.Atan2(dir.x, dir.y) * Mathf.Rad2Deg;
        float clear = Radius + 3f;
        var dozer = FindFirstObjectByType<DozerController>();
        if (dozer != null && Near(dozer.transform.position, c, clear)) { Vector2 p = c - dir * (Radius + 4f); dozer.Place(new Vector3(p.x, 0f, p.y), yaw); }
        var dingo = Dingo.Instance;
        if (dingo != null && !dingo.Driven && Near(dingo.transform.position, c, clear)) { Vector2 p = c - dir * (Radius + 4f) + new Vector2(dir.y, -dir.x) * 5f; dingo.Place(new Vector3(p.x, 0f, p.y), yaw); }
        var wk = Worker.Instance;
        if (wk != null && !wk.InDozer && Near(wk.transform.position, c, Radius + 1f)) { Vector2 p = c - dir * (Radius + 1.5f) - new Vector2(dir.y, -dir.x) * 3f; wk.Teleport(new Vector3(p.x, w.HeightAt(p.x, p.y), p.y), yaw); }
    }
    static bool Near(Vector3 p, Vector2 c, float r) { return (new Vector2(p.x, p.z) - c).sqrMagnitude < r * r; }
}
