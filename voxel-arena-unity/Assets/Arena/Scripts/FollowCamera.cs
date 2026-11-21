// The arena camera (the Digger Game's, cut down).  Two views, Tab (pad: Back) flips between them (ArenaPlayer):
//   shoulder: behind and a little to the right of the player, looking where he looks (lookYaw / lookPitch, set by
//             ArenaPlayer).  The cross in the middle of the screen is the aim.  It never sits inside the ground.
//   above:    high over the arena looking down at him, north always up, like Smashed: you move with the keys or the
//             left stick and aim with the mouse or the right stick.
// Bump and Shake knock it about for a moment (a rocket going off).
using UnityEngine;

public class FollowCamera : MonoBehaviour
{
    public Transform target;
    public bool above;
    public float lookYaw, lookPitch;
    public float shoulderDistance = 3.6f, lookHeight = 1.7f;
    public float aboveHeight = 19f, abovePitch = 62f;

    /// Set each frame something is shaking the camera (metres): it shakes that much this frame, then it is cleared.
    public static float Shake;
    public static float LastShake { get; private set; }
    static float bump;
    /// A one-off knock (metres) that dies away in a fraction of a second: a rocket going off.
    public static void Bump(float metres) { bump = Mathf.Max(bump, metres); }
    static bool shaken; static Vector3 calmPos, calmFwd;

    /// Where the camera is and looks, without this frame's shake.
    public static void Unshaken(Transform cam, out Vector3 pos, out Vector3 fwd)
    {
        if (shaken) { pos = calmPos; fwd = calmFwd; }
        else { pos = cam.position; fwd = cam.forward; }
    }

    Vector3 aboveFocus;

    void Start()
    {
        var cam = GetComponent<Camera>();
        if (cam != null) cam.nearClipPlane = 0.08f;
        if (target != null) aboveFocus = target.position;
        Shader.SetGlobalFloat("_CutRadius", 0f);
    }

    void LateUpdate()
    {
        Place();
        bump *= Mathf.Exp(-9f * Time.deltaTime);
        float s = Mathf.Max(Shake, bump); Shake = 0f; LastShake = s;
        shaken = false;
        if (s <= 0f || target == null) return;
        calmPos = transform.position; calmFwd = transform.forward; shaken = true;
        float t = Time.time * 37f;
        Vector3 off = new Vector3(Mathf.PerlinNoise(t, 0.3f) - 0.5f, Mathf.PerlinNoise(1.7f, t) - 0.5f, 0f) * 2f * s;
        transform.position += transform.rotation * off;
        transform.rotation *= Quaternion.Euler(off.y * 25f, off.x * 25f, 0f);
    }

    public void Place()
    {
        if (target == null) return;
        if (above)
        {
            // eases after him a little, so the view doesn't jerk with every step
            aboveFocus = Vector3.Lerp(aboveFocus, target.position, 1f - Mathf.Exp(-8f * Time.deltaTime));
            Quaternion look = Quaternion.Euler(abovePitch, 0f, 0f);
            float back = aboveHeight / Mathf.Sin(abovePitch * Mathf.Deg2Rad);
            transform.position = aboveFocus + Vector3.up * 1f - look * Vector3.forward * back;
            transform.rotation = look;
            return;
        }
        aboveFocus = target.position;
        Quaternion q = Quaternion.Euler(lookPitch, lookYaw, 0f);
        Vector3 pivot = target.position + Vector3.up * lookHeight + q * Vector3.right * 0.6f;
        float d = shoulderDistance;
        var world = VoxelWorld.Instance;
        if (world != null)
        {
            Vector3 hitAt; byte hitMat;
            if (world.Raycast(pivot, q * Vector3.back, d, out hitAt, out hitMat))
                d = Mathf.Max(0.35f, Vector3.Distance(pivot, hitAt) - 0.25f);
        }
        transform.position = pivot - q * Vector3.forward * d;
        transform.rotation = q;
    }
}
