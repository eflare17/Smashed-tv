// The grunts: Smashed's grunt (godot/arcade/smash/smash_horde.gd), brought onto the voxel ground.
//   - They come in from the four doors, one burst at a time (ArenaGame does the waves), walk down the short
//     corridor and run straight at the player, veering a little while more than 3 m away (each its own way), and
//     push apart so they don't stack.  Smashed's look redrawn in the ground's 6.25 cm blocks (VoxModel.GruntBoxesFine,
//     1.5 m tall), two walk frames, same speeds as Smashed.
//   - On the ground they follow FloorAt, so they climb down into craters and back out (slower going up).
//   - One bullet kills one; a rocket kills every grunt in its blast.  On death they burst into 6.25 cm gib cubes
//     (the size of a voxel of dirt) in the grunt's colours.
// Kept in plain arrays and drawn instanced (two meshes, one per walk frame), like Smashed's MultiMesh.
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class Grunts : MonoBehaviour
{
    public static Grunts Instance { get; private set; }

    public const int Max = 400;
    public const float Scale = 1.5f;                         // the OLD grunt: Smashed's 0.1 m voxels drawn at 0.15 m
    public const float Radius = 0.44f;                       // Smashed's RADIUS to body width (0.33 of 0.7 m), on the new 0.94 m wide model
    public const float Height = 24 * VoxelWorld.Voxel;       // 1.5 m
    public const int GibsEach = 40;                          // 6.25 cm cubes per grunt
    public static bool OldModel;                             // (the fps test only) draw the old 15 cm grunt and its gibs
    public static readonly Vector2[] DoorN = { new Vector2(0, 1), new Vector2(0, -1), new Vector2(1, 0), new Vector2(-1, 0) };   // into the arena: from the south, north, west, east doors
    const int Inside = 255;

    public int Count { get; private set; }
    public int KilledTotal { get; private set; }
    public float LastStepMs { get; private set; }
    public float LowestY { get; private set; } = 99f;       // (tests) the lowest any grunt has walked since ResetLowest
    public void ResetLowest() { LowestY = 99f; }

    readonly Vector3[] pos = new Vector3[Max];
    readonly Vector2[] facing = new Vector2[Max], veer = new Vector2[Max];
    readonly float[] speed = new float[Max], phase = new float[Max];
    readonly byte[] door = new byte[Max], dead = new byte[Max];
    readonly Matrix4x4[] bufA = new Matrix4x4[Max], bufB = new Matrix4x4[Max];
    Mesh meshA, meshB;
    Material mat;
    readonly System.Diagnostics.Stopwatch watch = new System.Diagnostics.Stopwatch();

    void Awake()
    {
        Instance = this;
        MakeMeshes();
        mat = new Material(Shader.Find("Arena/VertexColour")) { enableInstancing = true };
    }
    void OnDestroy() { if (Instance == this) Instance = null; }

    public void MakeMeshes()
    {
        if (OldModel)
        {
            meshA = VoxModel.FromBoxes(VoxModel.GruntBoxes(0), new Vector3(3.5f, 0f, 2f), 0.1f * Scale);
            meshB = VoxModel.FromBoxes(VoxModel.GruntBoxes(1), new Vector3(3.5f, 0f, 2f), 0.1f * Scale);
        }
        else
        {
            meshA = VoxModel.FromBoxes(VoxModel.GruntBoxesFine(0), new Vector3(7.5f, 0f, 4f), VoxelWorld.Voxel);
            meshB = VoxModel.FromBoxes(VoxModel.GruntBoxesFine(1), new Vector3(7.5f, 0f, 4f), VoxelWorld.Voxel);
        }
    }

    public Vector3 Position(int i) { return pos[i]; }

    public void Clear() { Count = 0; }

    /// Puts a grunt in the corridor behind door `d`, `depth` metres back from the wall.  False if the pool is full.
    public bool Spawn(int d, float depth, float spd)
    {
        if (Count >= Max) return false;
        float half = ArenaGame.Half, dh = ArenaGame.DoorHalf;
        Vector2 n = DoorN[d], t = new Vector2(n.y, -n.x);
        int i = Count++;
        Vector2 p = -n * (half + depth) + t * Random.Range(-dh + Radius, dh - Radius);
        pos[i] = new Vector3(p.x, 0f, p.y);
        facing[i] = n;
        speed[i] = spd;
        phase[i] = Random.value * Mathf.PI * 2f;
        float a = Random.Range(-0.45f, 0.45f);
        veer[i] = new Vector2(Mathf.Cos(a), Mathf.Sin(a));
        door[i] = (byte)d;
        dead[i] = 0;
        return true;
    }

    /// A grunt already inside the arena (tests).  `straight`: no veer, it runs dead straight at the player.
    public bool SpawnInside(Vector3 p, float spd, bool straight = false)
    {
        if (!Spawn(0, 1f, spd)) return false;
        int i = Count - 1;
        pos[i] = new Vector3(p.x, VoxelWorld.Instance != null ? VoxelWorld.Instance.FloorAt(p + Vector3.up * 0.45f) : 0f, p.z);
        door[i] = Inside;
        if (straight) veer[i] = new Vector2(1f, 0f);
        return true;
    }

    /// Moves every grunt toward `target` and pushes them apart.  True if one touched the target (within `touch` metres).
    public bool Step(float dt, Vector3 target, float touch)
    {
        watch.Restart();
        var world = VoxelWorld.Instance;
        bool touched = false;
        float touch2 = touch * touch, r2 = (Radius * 2f) * (Radius * 2f);
        float lim = ArenaGame.Half - Radius, lat = ArenaGame.DoorHalf - Radius, half = ArenaGame.Half;
        Vector2 tgt = new Vector2(target.x, target.z);
        for (int i = 0; i < Count; i++)
        {
            Vector2 p = new Vector2(pos[i].x, pos[i].z);
            int d = door[i];
            Vector2 dir;
            if (d == Inside)
            {
                Vector2 to = tgt - p;
                float l2 = to.sqrMagnitude;
                if (l2 > 0.0001f)
                {
                    dir = to / Mathf.Sqrt(l2);
                    if (l2 > 9f) { Vector2 v = veer[i]; dir = new Vector2(dir.x * v.x - dir.y * v.y, dir.x * v.y + dir.y * v.x); }
                }
                else dir = facing[i];
            }
            else dir = DoorN[d];
            // up a crater wall is slow going; down it they jog
            float y = pos[i].y;
            float sp = speed[i];
            if (world != null && d == Inside)
            {
                Vector2 ahead = p + dir * 0.35f;
                float fa = world.FloorAt(new Vector3(ahead.x, y + 0.45f, ahead.y));
                if (fa > y + 0.08f) sp *= 0.55f;
            }
            p += dir * (sp * dt);
            // push apart from the others
            Vector2 push = Vector2.zero;
            int seen = 0;
            for (int j = 0; j < Count && seen < 8; j++)
            {
                if (j == i) continue;
                float dx = p.x - pos[j].x, dz = p.y - pos[j].z;
                float l2 = dx * dx + dz * dz;
                if (l2 < r2 && l2 > 1e-6f)
                {
                    float l = Mathf.Sqrt(l2);
                    push += new Vector2(dx, dz) * ((Radius * 2f - l) / l);
                    seen++;
                }
            }
            p += push * 0.9f;
            if (d == Inside)
            {
                p = new Vector2(Mathf.Clamp(p.x, -lim, lim), Mathf.Clamp(p.y, -lim, lim));
                if ((p - tgt).sqrMagnitude < touch2 && Mathf.Abs(target.y - y) < 1.4f) touched = true;
            }
            else
            {
                // still in the corridor: keep within the door's width until clear of the wall
                Vector2 n = DoorN[d], t = new Vector2(n.y, -n.x);
                float depth = Vector2.Dot(p, n) + half;
                float side = Mathf.Clamp(Vector2.Dot(p, t), -lat, lat);
                p = n * (depth - half) + t * side;
                if (depth > Radius + 0.6f) door[i] = Inside;
            }
            // the ground: steps up at once (slowly, above), drops quickly
            float floor = world != null ? world.FloorAt(new Vector3(p.x, y + 0.45f, p.y)) : 0f;
            y = floor > y ? Mathf.MoveTowards(y, floor, 3.5f * dt + 0.02f) : Mathf.MoveTowards(y, floor, 7f * dt);
            if (floor - y > 0.6f) y = floor - 0.6f;
            if (d == Inside && y < LowestY) LowestY = y;
            pos[i] = new Vector3(p.x, y, p.y);
            facing[i] = dir;
            phase[i] += dt * speed[i] * 2.4f;
        }
        Compact();
        LastStepMs = (float)watch.Elapsed.TotalMilliseconds;
        return touched;
    }

    /// The first live grunt the line from `from` to `to` passes through (a standing cylinder each).  -1 for none.
    /// `along` is how far along the line (0..1) it was hit.
    public int HitLine(Vector3 from, Vector3 to, float extra, out float along)
    {
        along = 1f;
        int best = -1;
        Vector3 seg = to - from;
        float sx = seg.x, sz = seg.z, len2 = sx * sx + sz * sz;
        float rr = (Radius + extra) * (Radius + extra);
        for (int i = 0; i < Count; i++)
        {
            if (dead[i] != 0) continue;
            float px = pos[i].x - from.x, pz = pos[i].z - from.z;
            float t = len2 > 1e-8f ? Mathf.Clamp01((px * sx + pz * sz) / len2) : 0f;
            float dx = px - sx * t, dz = pz - sz * t;
            if (dx * dx + dz * dz > rr) continue;
            // a little before the closest point is where it enters the body; check the height there and at the middle
            float back = len2 > 1e-8f ? Mathf.Sqrt(Mathf.Max(0f, rr - dx * dx - dz * dz) / len2) : 0f;
            float t0 = Mathf.Max(0f, t - back);
            float y0 = from.y + seg.y * t0 - pos[i].y, y1 = from.y + seg.y * t - pos[i].y;
            float tt = y0 > -0.05f && y0 < Height + 0.05f ? t0 : y1 > -0.05f && y1 < Height + 0.05f ? t : -1f;
            if (tt >= 0f && tt < along) { along = tt; best = i; }
        }
        return best;
    }

    /// Kills grunt i (burst into gibs, thrown away from `from`).
    public void Kill(int i, Vector3 from)
    {
        if (i < 0 || i >= Count || dead[i] != 0) return;
        dead[i] = 1;
        KilledTotal++;
        Vector3 away = pos[i] - from; away.y = 0f;
        if (away.sqrMagnitude < 1e-4f) away = Vector3.forward;
        if (OldModel) Gibs.Burst(pos[i] + Vector3.up * Height * 0.55f, away.normalized, VoxModel.GruntGibs, 5);
        else Gibs.Burst(pos[i] + Vector3.up * Height * 0.55f, away.normalized, VoxModel.GruntGibsFine, GibsEach, VoxelWorld.Voxel);
        HeavyFX.Dust(pos[i] + Vector3.up * 0.9f, 2, 0.35f, new Color(0.55f, 0.06f, 0.05f, 0.55f));
        GameAudio.PlayAt("grunt_die", pos[i], 0.7f, 0.9f + 0.25f * Random.value);
        if (ArenaGame.Instance != null) ArenaGame.Instance.Kills++;
    }

    /// Kills every grunt within `r` metres of `p` (a rocket's blast, or the ones that just got you).  Returns how many.
    public int KillRadius(Vector3 p, float r)
    {
        int n = 0;
        for (int i = 0; i < Count; i++)
        {
            if (dead[i] != 0) continue;
            Vector3 d = pos[i] + Vector3.up * 0.8f - p;
            if (new Vector2(d.x, d.z).sqrMagnitude < r * r && Mathf.Abs(d.y) < r + 0.8f) { Kill(i, p); n++; }
        }
        return n;
    }

    /// Removes the dead (swap with the last live one).
    void Compact()
    {
        int i = 0;
        while (i < Count)
        {
            if (dead[i] != 0)
            {
                Count--;
                pos[i] = pos[Count]; facing[i] = facing[Count]; speed[i] = speed[Count]; phase[i] = phase[Count];
                veer[i] = veer[Count]; door[i] = door[Count]; dead[i] = dead[Count];
            }
            else i++;
        }
    }

    void LateUpdate()
    {
        int na = 0, nb = 0;
        for (int i = 0; i < Count; i++)
        {
            if (dead[i] != 0) continue;
            float ph = phase[i];
            float bob = Mathf.Abs(Mathf.Sin(ph)) * 0.08f;
            var m = Matrix4x4.TRS(pos[i] + Vector3.up * bob, Quaternion.LookRotation(new Vector3(facing[i].x, 0f, facing[i].y)), Vector3.one);
            if (((int)(ph / Mathf.PI) & 1) == 0) bufA[na++] = m; else bufB[nb++] = m;
        }
        var rp = new RenderParams(mat) { worldBounds = new Bounds(Vector3.zero, Vector3.one * 80f), shadowCastingMode = ShadowCastingMode.On, receiveShadows = true };
        if (na > 0) Graphics.RenderMeshInstanced(rp, meshA, 0, bufA, na);
        if (nb > 0) Graphics.RenderMeshInstanced(rp, meshB, 0, bufB, nb);
    }
}
