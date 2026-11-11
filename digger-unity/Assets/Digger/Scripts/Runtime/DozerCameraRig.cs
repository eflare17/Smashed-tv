using UnityEngine;

namespace Digger
{
    /// <summary>
    /// Chase camera that orbits and follows the dozer (hold right mouse to orbit, wheel to
    /// zoom), a cab view (V), and the blade cam: a second camera mounted on the blade whose
    /// picture shows in a small box in the corner, like a reversing camera (B).
    /// </summary>
    public class DozerCameraRig : MonoBehaviour
    {
        public DozerController dozer;
        public DozerInput input;
        public Camera viewCamera;
        public Camera bladeCamera;
        public Transform cabEye;

        [Header("Chase camera")]
        public float distance = 12f;
        public float minDistance = 4f;
        public float maxDistance = 35f;
        public float focusHeight = 1.6f;
        public float pitch = 16f;
        public float yawOffset = -28f;
        public float followSharpness = 6f;

        [Header("Blade cam box")]
        [Range(0.1f, 0.5f)] public float bladeCamWidth = 0.27f;
        public bool bladeCamOn = true;
        public bool cabView;

        /// <summary>The blade cam box in GUI pixels (top-left origin), for the HUD frame.</summary>
        public Rect BladeCamGuiRect { get; private set; }

        float smoothYaw, cabYaw, cabPitch;
        readonly RaycastHit[] hits = new RaycastHit[8];

        void Start()
        {
            if (!viewCamera) viewCamera = Camera.main;
            if (dozer) smoothYaw = dozer.transform.eulerAngles.y;
            if (viewCamera) SnapChase();
        }

        void SnapChase()
        {
            Vector3 focus, want;
            ChasePose(out focus, out want);
            viewCamera.transform.position = want;
            viewCamera.transform.rotation = Quaternion.LookRotation(focus - want);
        }

        void ChasePose(out Vector3 focus, out Vector3 want)
        {
            Transform t = dozer.transform;
            var rot = Quaternion.Euler(pitch, smoothYaw + yawOffset, 0f);
            focus = t.position + Vector3.up * focusHeight + t.forward * 1.2f;
            want = focus - rot * Vector3.forward * distance;

            // Keep the camera out of the dirt and on the near side of anything in the way.
            Vector3 dir = want - focus;
            float len = dir.magnitude;
            int count = Physics.RaycastNonAlloc(focus, dir / len, hits, len, ~0, QueryTriggerInteraction.Ignore);
            float nearest = len;
            for (int i = 0; i < count; i++)
            {
                if (hits[i].collider.transform.IsChildOf(t)) continue;
                if (hits[i].distance < nearest) nearest = hits[i].distance;
            }
            if (nearest < len) want = focus + dir / len * Mathf.Max(nearest - 0.4f, 1.5f);
        }

        void LateUpdate()
        {
            if (!dozer || !viewCamera) return;
            if (input)
            {
                if (input.CameraTogglePressed) cabView = !cabView;
                if (input.BladeCamPressed) bladeCamOn = !bladeCamOn;
            }
            Vector2 look = input ? input.Look : Vector2.zero;
            float zoom = input ? input.Zoom : 0f;
            float k = 1f - Mathf.Exp(-followSharpness * Time.deltaTime);

            if (cabView && cabEye)
            {
                cabYaw = Mathf.Clamp(cabYaw + look.x, -120f, 120f);
                cabPitch = Mathf.Clamp(cabPitch - look.y, -50f, 60f);
                viewCamera.transform.position = cabEye.position;
                viewCamera.transform.rotation = cabEye.rotation * Quaternion.Euler(cabPitch, cabYaw, 0f);
                viewCamera.fieldOfView = 70f;
            }
            else
            {
                yawOffset += look.x;
                pitch = Mathf.Clamp(pitch - look.y, 3f, 75f);
                distance = Mathf.Clamp(distance * (1f - zoom * 0.12f), minDistance, maxDistance);
                smoothYaw = Mathf.LerpAngle(smoothYaw, dozer.transform.eulerAngles.y, 1f - Mathf.Exp(-2.5f * Time.deltaTime));
                Vector3 focus, want;
                ChasePose(out focus, out want);
                viewCamera.transform.position = Vector3.Lerp(viewCamera.transform.position, want, k);
                viewCamera.transform.rotation = Quaternion.LookRotation(focus - viewCamera.transform.position);
                viewCamera.fieldOfView = 55f;
            }

            if (bladeCamera)
            {
                bladeCamera.enabled = bladeCamOn;
                float w = bladeCamWidth;
                float hgt = w * Screen.width / Mathf.Max(1f, Screen.height) * 9f / 16f;
                var rect = new Rect(1f - w - 0.015f, 0.03f, w, hgt);
                bladeCamera.rect = rect;
                BladeCamGuiRect = new Rect(rect.x * Screen.width, (1f - rect.y - rect.height) * Screen.height,
                                           rect.width * Screen.width, rect.height * Screen.height);
            }
        }
    }
}
