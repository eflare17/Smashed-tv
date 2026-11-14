// The game camera.  Two ways of looking:
//   behind:  follows a target (the worker or the machine) from behind and swings round with it.
//            Hold the right mouse button and drag to look round; scroll to zoom.
//   eyes:    sits at the worker's eye height and looks where he looks (lookYaw / lookPitch, set by Worker).
// From behind it never sits inside the ground: if rock is in the way (in the mine, say) it moves in closer.
using UnityEngine;

public class FollowCamera : MonoBehaviour
{
    public Transform target;
    public float distance = 13f;
    public float minDistance = 6f, maxDistance = 40f;
    public float lookHeight = 1.8f;
    public float pitch = 22f;
    public float yawOffset = 25f;            // a little to one side, so the blade is in view
    public float turnFollow = 2f;

    public bool firstPerson;
    public bool shoulder;                    // over the worker's shoulder, looking where he looks (lookYaw / lookPitch)
    public float eyeHeight = 1.6f;
    public float lookYaw, lookPitch;

    float heading;

    void Start()
    {
        if (target != null) heading = target.eulerAngles.y;
        var cam = GetComponent<Camera>();
        if (cam != null) cam.nearClipPlane = 0.08f;
    }

    /// Start following something else from behind.
    public void Follow(Transform t, float dist, float min, float max, float look, float tilt, float side)
    {
        target = t; distance = dist; minDistance = min; maxDistance = max; lookHeight = look; pitch = tilt; yawOffset = side;
        heading = t.eulerAngles.y;
        firstPerson = false;
        shoulder = false;
    }

    /// Tells the scenery shader to open a clear tunnel of sight from the camera to a point.
    void ClearLineTo(Vector3 subject, float radius)
    {
        Shader.SetGlobalVector("_CutFrom", transform.position);
        Shader.SetGlobalVector("_CutTo", subject);
        Shader.SetGlobalFloat("_CutRadius", radius);
    }

    void OnDisable() { Shader.SetGlobalFloat("_CutRadius", 0f); }

    void LateUpdate()
    {
        if (target == null) return;
        if (firstPerson)
        {
            transform.position = target.position + Vector3.up * eyeHeight;
            transform.rotation = Quaternion.Euler(lookPitch, lookYaw, 0f);
            ClearLineTo(transform.position, 0f);
            return;
        }
        if (shoulder)
        {
            // Behind and a little to the right of him, turning with the mouse, so the cross in the middle of
            // the screen is a clear line past his shoulder to what he is working on.
            distance = Mathf.Clamp(distance * (1f - Input.GetAxis("Mouse ScrollWheel")), minDistance, maxDistance);
            Quaternion look = Quaternion.Euler(lookPitch, lookYaw, 0f);
            Vector3 pivot = target.position + Vector3.up * lookHeight + look * Vector3.right * 0.55f;
            float back = distance;
            var site = VoxelWorld.Instance;
            if (site != null)
            {
                Vector3 hitAt; byte hitMat;
                if (site.Raycast(pivot, look * Vector3.back, distance, out hitAt, out hitMat))
                    back = Mathf.Max(0.35f, Vector3.Distance(pivot, hitAt) - 0.25f);
            }
            transform.position = pivot - look * Vector3.forward * back;
            transform.rotation = look;
            // posts, beams and branches between the camera and him are cut away, and a little way past him
            ClearLineTo(target.position + Vector3.up * 1.2f + look * Vector3.forward * 1.2f, 1.05f);
            return;
        }
        if (Input.GetMouseButton(1))
        {
            yawOffset += Input.GetAxis("Mouse X") * 4f;
            pitch = Mathf.Clamp(pitch - Input.GetAxis("Mouse Y") * 3f, 5f, 75f);
        }
        distance = Mathf.Clamp(distance * (1f - Input.GetAxis("Mouse ScrollWheel")), minDistance, maxDistance);
        heading = Mathf.LerpAngle(heading, target.eulerAngles.y, turnFollow * Time.deltaTime);

        Vector3 focus = target.position + Vector3.up * lookHeight;
        Quaternion rot = Quaternion.Euler(pitch, heading + yawOffset, 0f);
        float d = distance;
        var world = VoxelWorld.Instance;
        if (world != null)
        {
            Vector3 hit; byte mat;
            if (world.Raycast(focus, rot * Vector3.back, distance, out hit, out mat))
                d = Mathf.Max(0.6f, Vector3.Distance(focus, hit) - 0.25f);
        }
        transform.position = focus - rot * Vector3.forward * d;
        transform.rotation = rot;
        ClearLineTo(focus, 2.6f);                             // trees and timber between the camera and the machine
    }
}
