// One-off piles of loose dirt at the foot of the mountain road, so there is dirt to push up the road for its first
// fills (the owner asked for them: the first stretch needs filling and there was nothing loose nearby to push).
//   - The first: about 20 m³ (four full blade loads), a rounded heap just short of where the road starts, on its
//     line, so you drive into it and push it straight up the road.
//   - The second (asked for later, "a bit more than the next bit needs"): about 30 m³, beside the road on its left
//     as you face up it, so you push it across onto the road.
//   - Each is dropped once: in a new game as it starts, and in an older save the first time that save is loaded.
//     The save remembers they were dropped (SaveGame), so they never come back once they have been used.
//   - Reset ground puts the ground back as new, and that includes these piles.
//   - Only in the real game (SaveGame.AutoOn): the editor's tests start without them unless they ask (TestAuto).
using UnityEngine;

public class RoadPile : MonoBehaviour
{
    public static RoadPile Instance { get; private set; }

    public const float Volume = 20f;            // m³
    public const float Radius = 3.4f;           // m, from the middle to the edge of the heap
    public const float BackFromStart = 4.6f;    // m: its middle is this far back down the road line from where the road starts

    public const float Volume2 = 30f;           // m³, the second pile
    public const float Radius2 = 4.0f;
    public const float LeftOfRoad = 6.8f;       // m: its middle is this far left of where the road starts...
    public const float Back2 = 1.0f;            // ...and this far back down the road line

    /// Dropped already (in this game).
    public bool Placed { get; set; }
    public bool Placed2 { get; set; }
    public long LastAdded { get; private set; }  // voxels the last drop of the first pile added (tests)
    public long LastAdded2 { get; private set; }

    void Awake() { Instance = this; }
    void OnDestroy() { if (Instance == this) Instance = null; }

    static Vector2 UpRoad()
    {
        Vector2 p0 = MountainRoad.Point(0), p1 = MountainRoad.Point(Mathf.Min(4, MountainRoad.Count - 1));
        return (p1 - p0).normalized;
    }

    /// Where the middle of the first heap goes.
    public static Vector2 Centre() { return MountainRoad.Point(0) - UpRoad() * BackFromStart; }

    /// Where the middle of the second heap goes: on the left as you face up the road.
    public static Vector2 Centre2()
    {
        Vector2 dir = UpRoad(), left = new Vector2(-dir.y, dir.x);
        return MountainRoad.Point(0) + left * LeftOfRoad - dir * Back2;
    }

    void Update()
    {
        if ((Placed && Placed2) || !SaveGame.AutoOn) return;
        var sg = SaveGame.Instance; var w = VoxelWorld.Instance;
        if (sg == null || w == null || !sg.StartupDone) return;      // after the save (if any) has been loaded
        if (!Placed) Drop();
        if (!Placed2) Drop2();
    }

    /// Drops the first pile now (and marks it dropped).
    public void Drop()
    {
        var w = VoxelWorld.Instance;
        if (w == null) return;
        Vector2 c = Centre();
        LastAdded = w.AddLoosePile(c.x, c.y, Radius, Volume);
        Placed = true;
        Vector2 dir = UpRoad();
        MoveAside(c, Radius, c - dir * (Radius + 4f), dir);
    }

    /// Drops the second pile now (and marks it dropped).
    public void Drop2()
    {
        var w = VoxelWorld.Instance;
        if (w == null) return;
        Vector2 c = Centre2();
        LastAdded2 = w.AddLoosePile(c.x, c.y, Radius2, Volume2);
        Placed2 = true;
        Vector2 dir = UpRoad(), toRoad = new Vector2(dir.y, -dir.x);              // facing across, towards the road
        MoveAside(c, Radius2, c - toRoad * (Radius2 + 4f), toRoad);
    }

    /// Anything parked on the spot is moved just behind the heap, facing the way it is to be pushed.
    static void MoveAside(Vector2 c, float radius, Vector2 to, Vector2 face)
    {
        var w = VoxelWorld.Instance;
        float yaw = Mathf.Atan2(face.x, face.y) * Mathf.Rad2Deg;
        float clear = radius + 3f;
        Vector2 side = new Vector2(face.y, -face.x);
        var dozer = FindFirstObjectByType<DozerController>();
        if (dozer != null && Near(dozer.transform.position, c, clear)) dozer.Place(new Vector3(to.x, 0f, to.y), yaw);
        var dingo = Dingo.Instance;
        if (dingo != null && !dingo.Driven && Near(dingo.transform.position, c, clear)) { Vector2 p = to + side * 5f; dingo.Place(new Vector3(p.x, 0f, p.y), yaw); }
        var wk = Worker.Instance;
        if (wk != null && !wk.InDozer && Near(wk.transform.position, c, radius + 1f)) { Vector2 p = c - face * (radius + 1.5f) - side * 3f; wk.Teleport(new Vector3(p.x, w.HeightAt(p.x, p.y), p.y), yaw); }
    }
    static bool Near(Vector3 p, Vector2 c, float r) { return (new Vector2(p.x, p.z) - c).sqrMagnitude < r * r; }
}
