// The bow's arrows (the owner asked for them, 23 Nov 2026): a real flight, and you get them back.
//   - An arrow leaves at up to 45 m/s (a full draw; a quick one goes slower) and flies under gravity, a little air
//     slowing it, always pointing the way it is going.
//   - It sticks where it hits: in a tree trunk (it stays there, at the angle it went in), or in the ground.  A grunt
//     it hits is killed (IShootable, Rifle.cs) and the arrow drops beside it.  It passes through water and gas.
//   - Dig the ground out from under a stuck arrow, or push its tree over with the dozer, and it falls and lies there.
//   - E near an arrow (stuck or lying) pulls it out and puts it back in the quiver.
//   - The quiver holds 12; there are only ever 12.  Not saved: a loaded game has all 12 back in the quiver.
using System.Collections.Generic;
using UnityEngine;

public class Arrows : MonoBehaviour
{
    public const int Total = 12;
    public const float MaxSpeed = 45f, MinSpeed = 14f, DrawTime = 0.9f, Gravity = 9.81f, Drag = 0.012f;
    public const float Length = 0.75f, PickReach = 1.6f;

    public static int InQuiver { get; private set; } = Total;
    public static int Shot { get; private set; }              // (tests) arrows let go
    public static int StuckInTrees { get; private set; }      // (tests)
    public static int StuckInGround { get; private set; }
    public static int HitTargets { get; private set; }
    public static int PickedUp { get; private set; }

    public enum State { Flying, InTree, InGround, Lying }
    public class Arrow
    {
        public Transform t;
        public Vector3 pos, vel, dir;                            // pos: the tip
        public State state;
        public int tree = -1;
        public float age;
    }
    static readonly List<Arrow> out_ = new List<Arrow>();
    public static IList<Arrow> Out { get { return out_; } }
    static Arrows instance;
    static Material shaftMat, headMat, featherMat;

    static Arrows Get()
    {
        if (instance == null) instance = new GameObject("Arrows").AddComponent<Arrows>();
        return instance;
    }
    void OnDestroy() { if (instance == this) { instance = null; out_.Clear(); InQuiver = Total; } }

    /// Every arrow back in the quiver (a load, a new game).
    public static void AllBack()
    {
        foreach (var a in out_) if (a.t != null) Destroy(a.t.gameObject);
        out_.Clear();
        InQuiver = Total;
    }

    /// Lets an arrow go from `from` along `dir` at `speed`.  False if the quiver is empty.
    public static bool Loose(Vector3 from, Vector3 dir, float speed)
    {
        if (InQuiver <= 0) return false;
        var g = Get();
        InQuiver--;
        Shot++;
        dir.Normalize();
        var a = new Arrow { pos = from + dir * Length, vel = dir * speed, dir = dir, state = State.Flying };
        a.t = g.Model();
        Place(a);
        out_.Add(a);
        GameAudio.PlayAt("bow", from, 0.7f, 0.95f + 0.1f * Random.value);
        return true;
    }

    /// Pulls out the nearest arrow within reach of `at` (stuck or lying) and puts it back in the quiver.
    public static bool PickUp(Vector3 at)
    {
        int best = -1; float bestD = PickReach;
        for (int i = 0; i < out_.Count; i++)
        {
            var a = out_[i];
            if (a.state == State.Flying) continue;
            Vector3 mid = a.pos - a.dir * Length * 0.5f;
            Vector3 d = mid - at; d.y *= 0.5f;                   // (one stuck up a trunk is still in reach)
            float l = d.magnitude;
            if (l < bestD) { bestD = l; best = i; }
        }
        if (best < 0) return false;
        Destroy(out_[best].t.gameObject);
        out_.RemoveAt(best);
        InQuiver++;
        PickedUp++;
        GameAudio.PlayAt("pick_dirt", at, 0.3f, 1.8f);
        return true;
    }

    /// Is there an arrow (stuck or lying) within reach?  (For the hint.)
    public static bool NearOne(Vector3 at)
    {
        foreach (var a in out_)
        {
            if (a.state == State.Flying) continue;
            Vector3 d = a.pos - a.dir * Length * 0.5f - at; d.y *= 0.5f;
            if (d.magnitude < PickReach) return true;
        }
        return false;
    }

    Transform Model()
    {
        if (shaftMat == null)
        {
            shaftMat = new Material(Shader.Find("Standard")) { color = new Color(0.62f, 0.47f, 0.3f) };
            headMat = new Material(Shader.Find("Standard")) { color = new Color(0.35f, 0.36f, 0.38f) };
            featherMat = new Material(Shader.Find("Standard")) { color = new Color(0.85f, 0.2f, 0.15f) };
        }
        var root = new GameObject("Arrow").transform;
        root.SetParent(transform, false);
        // modelled pointing +z, the tip at the origin
        Part(root, new Vector3(0f, 0f, -Length * 0.5f), new Vector3(0.03f, 0.03f, Length), shaftMat);
        Part(root, new Vector3(0f, 0f, -0.03f), new Vector3(0.05f, 0.05f, 0.09f), headMat);
        Part(root, new Vector3(0f, 0f, -Length + 0.07f), new Vector3(0.008f, 0.09f, 0.16f), featherMat);
        Part(root, new Vector3(0f, 0f, -Length + 0.07f), new Vector3(0.09f, 0.008f, 0.16f), featherMat);
        return root;
    }
    static void Part(Transform root, Vector3 at, Vector3 size, Material m)
    {
        var g = GameObject.CreatePrimitive(PrimitiveType.Cube);
        Destroy(g.GetComponent<Collider>());
        g.transform.SetParent(root, false);
        g.transform.localPosition = at; g.transform.localScale = size;
        g.GetComponent<MeshRenderer>().sharedMaterial = m;
    }

    static void Place(Arrow a)
    {
        a.t.position = a.pos;
        if (a.dir.sqrMagnitude > 1e-6f) a.t.rotation = Quaternion.LookRotation(a.dir, Vector3.up);
    }

    void Update()
    {
        var w = VoxelWorld.Instance;
        if (w == null) return;
        float dt = Time.deltaTime;
        if (dt <= 0f) return;
        for (int i = 0; i < out_.Count; i++)
        {
            var a = out_[i];
            a.age += dt;
            if (a.state == State.Flying) Fly(a, w, dt);
            else if (a.state == State.InTree)
            {
                // its tree was pushed over: it drops
                if (a.tree >= 0 && !SiteProps.TreeStanding(a.tree)) Drop(a, w);
            }
            else if (a.state == State.InGround)
            {
                // the ground it was in has been dug away: it drops
                if (w.MaterialAt(a.pos - a.dir * 0.05f) == VoxelWorld.Air && w.MaterialAt(a.pos) == VoxelWorld.Air) Drop(a, w);
            }
            else if (a.state == State.Lying)
            {
                float floor = w.FloorAt(a.pos + Vector3.up * 0.3f);
                if (Mathf.Abs(a.pos.y - (floor + 0.02f)) > 0.01f) { a.pos.y = Mathf.MoveTowards(a.pos.y, floor + 0.02f, 4f * dt); Place(a); }
            }
        }
    }

    void Fly(Arrow a, VoxelWorld w, float dt)
    {
        Vector3 v = a.vel;
        v.y -= Gravity * dt;
        v -= v * (Drag * v.magnitude * dt);
        Vector3 step = v * dt;
        float len = step.magnitude;
        if (len < 1e-5f) return;
        Vector3 dir = step / len;
        // what it meets first along this step: a target, a tree, the ground
        float best = len; int what = 0; Vector3 hitAt = a.pos + step; int tree = -1; IShootable target = null;
        foreach (var h in Physics.RaycastAll(a.pos, dir, len))
        {
            if (h.distance >= best) continue;
            var s = h.collider.GetComponentInParent<IShootable>();
            if (s == null) continue;
            best = h.distance; what = 1; hitAt = h.point; target = s;
        }
        Vector3 th; int ti;
        if (SiteProps.TrunkAlong(a.pos, a.pos + dir * best, out th, out ti)) { best = Vector3.Distance(a.pos, th); what = 2; hitAt = th; tree = ti; target = null; }
        Vector3 gh; byte gm;
        if (w.Raycast(a.pos, dir, best, out gh, out gm)) { best = Vector3.Distance(a.pos, gh); what = 3; hitAt = gh; target = null; tree = -1; }
        if (Mathf.Abs(a.pos.x) > VoxelWorld.SiteHalf + 60f || Mathf.Abs(a.pos.z) > VoxelWorld.SiteHalf + 150f || a.pos.y < -10f || a.age > 12f) what = 4;   // gone off into the distance

        a.dir = dir; a.vel = v;
        switch (what)
        {
            case 0: a.pos += step; break;
            case 1:
                target.Shot(hitAt, dir);
                HitTargets++;
                a.pos = hitAt; Drop(a, w);
                break;
            case 2:
                a.pos = hitAt + dir * 0.12f;                     // the head goes into the wood
                a.state = State.InTree; a.tree = tree; a.vel = Vector3.zero;
                StuckInTrees++;
                GameAudio.PlayAt("arrow_thunk", hitAt, 0.7f, 0.9f + 0.2f * Random.value);
                break;
            case 3:
                a.pos = hitAt + dir * 0.15f;                     // in up to the head and a bit
                a.state = State.InGround; a.vel = Vector3.zero;
                StuckInGround++;
                bool hard = gm >= VoxelWorld.Rock && gm <= VoxelWorld.Gold;
                if (hard) { a.pos = hitAt - dir * 0.02f; Drop(a, w); GameAudio.PlayAt("pick_rock", hitAt, 0.3f, 1.6f); }   // rock: it glances off
                else GameAudio.PlayAt("pick_dirt", hitAt, 0.4f, 1.5f);
                break;
            case 4:
                // lost: it comes back to the quiver (so the 12 are never used up for good)
                Destroy(a.t.gameObject); out_.Remove(a); InQuiver++;
                return;
        }
        Place(a);
    }

    /// It falls and lies flat on the ground.
    static void Drop(Arrow a, VoxelWorld w)
    {
        a.state = State.Lying; a.tree = -1; a.vel = Vector3.zero;
        Vector3 flat = a.dir; flat.y = 0f;
        a.dir = flat.sqrMagnitude > 1e-4f ? flat.normalized : Vector3.forward;
        a.pos.y = w.FloorAt(a.pos + Vector3.up * 0.3f) + 0.02f;
        a.pos += a.dir * Length * 0.5f;
        Place(a);
    }
}
