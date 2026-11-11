using System.Collections.Generic;
using UnityEngine;

namespace Digger
{
    /// <summary>
    /// A tracked bulldozer on PhysX articulation bodies.
    ///
    /// Driving: each track has a row of ground contacts (raycast springs). At every contact
    /// the track pushes the ground toward its target speed, limited by grip (normal force ×
    /// friction) and by engine power, and resists sliding sideways. Steering slows the inside
    /// track; with no throttle the tracks counter-rotate for a pivot turn. Because friction
    /// fights sideways sliding, turning is heavy and the machine bogs down when it pushes a
    /// big load, the way a real dozer does.
    ///
    /// Blade: three revolute articulation joints, lift (about the push-arm trunnions), angle
    /// (swing left/right) and tilt (one corner lower), each driven to a target angle by a
    /// stiff hydraulic-style drive with a force limit.
    /// </summary>
    [RequireComponent(typeof(ArticulationBody))]
    public class DozerController : MonoBehaviour
    {
        [Header("Driver")]
        [Tooltip("Component that implements IDozerControlSource (local input, network, AI).")]
        public MonoBehaviour controlSource;
        public DeformableGround ground;

        [Header("Tracks")]
        public float trackGauge = 1.96f;
        public float trackContactLength = 2.5f;
        public int pointsPerSide = 6;
        [Tooltip("Height of the contact rays' start above the track bottom.")]
        public float rayStartHeight = 0.6f;
        public float restLength = 0.66f;
        public float suspensionTravel = 0.35f;
        public float springRate = 260000f;
        public float damperRate = 24000f;
        [Tooltip("Friction between grousers and soil, along the track.")]
        public float grip = 0.85f;
        [Tooltip("Friction against sliding sideways.")]
        public float sideGrip = 0.8f;
        public float driveResponse = 6f;
        public float sideResponse = 9f;

        [Header("Drivetrain")]
        public float enginePowerKW = 120f;
        public float maxTractiveForce = 140000f;
        [Tooltip("Top speed in each forward gear (m/s).")]
        public float[] forwardGearSpeeds = { 1.1f, 1.9f, 2.9f };
        [Tooltip("Top speed in each reverse gear (m/s).")]
        public float[] reverseGearSpeeds = { 1.4f, 2.4f, 3.6f };
        [Tooltip("Track speed for a pivot turn on the spot (m/s).")]
        public float pivotTrackSpeed = 0.75f;
        [Range(0, 2)] public int gear;

        [Header("Blade joints (degrees)")]
        public ArticulationBody liftJoint;
        public ArticulationBody angleJoint;
        public ArticulationBody tiltJoint;
        public float liftDown = -9f, liftUp = 16f, liftRate = 11f;
        public float tiltLimit = 8f, tiltRate = 8f;
        public float angleLimit = 25f, angleRate = 14f;

        [Header("Visuals")]
        public Renderer[] leftTrackRenderers;
        public Renderer[] rightTrackRenderers;
        [Tooltip("Length of one tile of the track texture along the track (m).")]
        public float trackTileLength = 0.236f;
        public Transform[] leftWheels;
        public Transform[] rightWheels;
        public float wheelRadius = 0.4f;
        public Transform[] liftCylinders;
        public Transform[] cylinderBases;
        public Transform[] cylinderRods;
        public Light[] workLights;
        public Renderer[] lightLenses;
        public Color lensGlow = new Color(1f, 0.93f, 0.78f);
        [Tooltip("HDRP emissive intensity for the lit lenses (nits-ish).")]
        public float lensGlowIntensity = 20000f;
        public DustEmitters dust;

        // Telemetry for the HUD.
        public float SpeedKmh { get; private set; }
        public float EngineLoad { get; private set; }
        public float GroundedFraction { get; private set; }
        public bool Reversing { get; private set; }
        public float LiftDegrees { get { return liftTarget; } }
        public float TiltDegrees { get { return tiltTarget; } }
        public float AngleDegrees { get { return angleTarget; } }
        public bool LightsOn { get { return lightsOn; } }
        public int GearNumber { get { return gear + 1; } }

        ArticulationBody body;
        IDozerControlSource source;
        DozerControls ctl;
        Vector3[] points;
        float[] lastCompression;
        readonly float[] trackSpeed = new float[2];
        readonly float[] trackScroll = new float[2];
        readonly float[] wheelAngle = new float[2];
        readonly RaycastHit[] hits = new RaycastHit[8];
        float liftTarget = 2f, tiltTarget, angleTarget;
        bool lightsOn;
        float machineMass;
        Material[][] trackMaterials;
        Material[] lensMaterials;
        Quaternion[][] wheelBaseRotation;
        Vector3 spawnPosition;
        Quaternion spawnRotation;

        void Awake()
        {
            body = GetComponent<ArticulationBody>();
            source = controlSource as IDozerControlSource;

            int n = pointsPerSide * 2;
            points = new Vector3[n];
            lastCompression = new float[n];
            for (int s = 0; s < 2; s++)
            {
                for (int i = 0; i < pointsPerSide; i++)
                {
                    float t = pointsPerSide == 1 ? 0.5f : i / (float)(pointsPerSide - 1);
                    float z = Mathf.Lerp(-trackContactLength * 0.5f, trackContactLength * 0.5f, t);
                    points[s * pointsPerSide + i] = new Vector3((s == 0 ? -0.5f : 0.5f) * trackGauge, rayStartHeight, z);
                }
            }

            machineMass = 0f;
            foreach (var ab in GetComponentsInChildren<ArticulationBody>()) machineMass += ab.mass;

            trackMaterials = new[] { Instances(leftTrackRenderers), Instances(rightTrackRenderers) };
            lensMaterials = Instances(lightLenses);
            wheelBaseRotation = new[] { BaseRotations(leftWheels), BaseRotations(rightWheels) };
            spawnPosition = transform.position;
            spawnRotation = transform.rotation;
            SetLights(false);
        }

        void Start()
        {
            // The machine's own parts never collide with each other, and the blade digs into
            // the ground (handled by BladeCutter) instead of bouncing off it.
            var own = GetComponentsInChildren<Collider>(true);
            for (int i = 0; i < own.Length; i++)
                for (int j = i + 1; j < own.Length; j++)
                    Physics.IgnoreCollision(own[i], own[j]);
            if (liftJoint)
            {
                var bladeParts = liftJoint.GetComponentsInChildren<Collider>(true);
                foreach (var terrain in Terrain.activeTerrains)
                {
                    var tc = terrain.GetComponent<TerrainCollider>();
                    if (!tc) continue;
                    foreach (var c in bladeParts) Physics.IgnoreCollision(c, tc);
                }
            }
        }

        static Material[] Instances(Renderer[] renderers)
        {
            if (renderers == null) return new Material[0];
            var m = new Material[renderers.Length];
            for (int i = 0; i < renderers.Length; i++) m[i] = renderers[i] ? renderers[i].material : null;
            return m;
        }

        static Quaternion[] BaseRotations(Transform[] ts)
        {
            if (ts == null) return new Quaternion[0];
            var q = new Quaternion[ts.Length];
            for (int i = 0; i < ts.Length; i++) q[i] = ts[i] ? ts[i].localRotation : Quaternion.identity;
            return q;
        }

        void Update()
        {
            if (source == null) source = controlSource as IDozerControlSource;
            ctl = source != null ? source.Read() : default(DozerControls);

            if (ctl.gearDelta != 0) gear = Mathf.Clamp(gear + ctl.gearDelta, 0, forwardGearSpeeds.Length - 1);
            if (ctl.toggleLights) SetLights(!lightsOn);
            if (ctl.resetMachine) ResetMachine();
            if (ctl.resetGround && ground) ground.ResetGround();

            UpdateTrackVisuals(Time.deltaTime);
        }

        void FixedUpdate()
        {
            float dt = Time.fixedDeltaTime;
            liftTarget = Mathf.Clamp(liftTarget + ctl.bladeLift * liftRate * dt, liftDown, liftUp);
            if (ctl.useTiltDirect)
                tiltTarget = Mathf.MoveTowards(tiltTarget, ctl.tiltDirect * tiltLimit, tiltRate * 2f * dt);
            else
                tiltTarget = Mathf.Clamp(tiltTarget + ctl.bladeTilt * tiltRate * dt, -tiltLimit, tiltLimit);
            angleTarget = Mathf.Clamp(angleTarget + ctl.bladeAngle * angleRate * dt, -angleLimit, angleLimit);

            // Positive rotation about the lift joint's axis dips the blade, so raising is negative.
            DriveJoint(liftJoint, -liftTarget);
            DriveJoint(angleJoint, angleTarget);
            DriveJoint(tiltJoint, tiltTarget);

            DriveTracks(dt);
        }

        static void DriveJoint(ArticulationBody joint, float degrees)
        {
            if (!joint) return;
            var drive = joint.xDrive;
            drive.target = degrees;
            joint.xDrive = drive;
        }

        void DriveTracks(float dt)
        {
            Vector3 up = transform.up, fwd = transform.forward;
            float share = machineMass / (pointsPerSide * 2);
            float vf = Vector3.Dot(body.GetPointVelocity(transform.position), fwd);
            SpeedKmh = vf * 3.6f;

            float thr = Mathf.Clamp(ctl.throttle, -1f, 1f);
            float steer = Mathf.Clamp(ctl.steer, -1f, 1f);
            float top = thr >= 0f ? forwardGearSpeeds[gear] : reverseGearSpeeds[gear];
            float v = thr * top;
            float vl, vr;
            if (Mathf.Abs(thr) < 0.08f)
            {
                vl = steer * pivotTrackSpeed;
                vr = -steer * pivotTrackSpeed;
            }
            else
            {
                float inner = v * (1f - Mathf.Abs(steer) * 1.7f);
                if (steer > 0f) { vl = v; vr = inner; } else { vl = inner; vr = v; }
            }
            float brake = Mathf.Clamp01(ctl.brake);
            vl *= 1f - brake;
            vr *= 1f - brake;
            Reversing = v < -0.05f;

            float available = Mathf.Min(maxTractiveForce, enginePowerKW * 1000f / Mathf.Max(Mathf.Abs(vf), 0.35f));
            float enginePerPoint = available / (pointsPerSide * 2);
            float used = 0f;
            int grounded = 0;

            for (int s = 0; s < 2; s++)
            {
                float target = s == 0 ? vl : vr;
                float vSum = 0f;
                int contacts = 0, slipping = 0;
                for (int i = 0; i < pointsPerSide; i++)
                {
                    int k = s * pointsPerSide + i;
                    Vector3 origin = transform.TransformPoint(points[k]);
                    RaycastHit hit;
                    if (!CastDown(origin, -up, restLength + suspensionTravel, out hit)) { lastCompression[k] = 0f; continue; }
                    float compression = restLength - hit.distance;
                    if (compression <= 0f) { lastCompression[k] = 0f; continue; }

                    float compressionSpeed = (compression - lastCompression[k]) / dt;
                    lastCompression[k] = compression;
                    float normal = Mathf.Max(0f, springRate * compression + damperRate * compressionSpeed);

                    Vector3 n = hit.normal;
                    Vector3 along = Vector3.ProjectOnPlane(fwd, n).normalized;
                    Vector3 side = Vector3.Cross(n, along);
                    Vector3 pv = body.GetPointVelocity(hit.point);
                    float vLong = Vector3.Dot(pv, along);
                    float vLat = Vector3.Dot(pv, side);

                    float fLong = driveResponse * share * (target - vLong);
                    bool driving = fLong * target > 0f && Mathf.Abs(target) >= Mathf.Abs(vLong);
                    float cap = driving ? Mathf.Min(grip * normal, enginePerPoint) : grip * normal;
                    if (Mathf.Abs(fLong) >= cap) { fLong = Mathf.Sign(fLong) * cap; slipping++; }
                    float fLat = Mathf.Clamp(-sideResponse * share * vLat, -sideGrip * normal, sideGrip * normal);

                    body.AddForceAtPosition(up * normal + along * fLong + side * fLat, hit.point);

                    used += Mathf.Abs(fLong);
                    vSum += vLong;
                    contacts++;
                    grounded++;
                }
                float groundSpeed = contacts > 0 ? vSum / contacts : target;
                trackSpeed[s] = contacts > 0 && slipping * 2 >= contacts ? target : groundSpeed;
            }

            EngineLoad = Mathf.Lerp(EngineLoad, Mathf.Clamp01(used / Mathf.Max(available, 1f)), 0.1f);
            GroundedFraction = grounded / (float)(pointsPerSide * 2);
            if (dust) dust.SetTrackSpeed(Mathf.Max(Mathf.Abs(trackSpeed[0]), Mathf.Abs(trackSpeed[1])), grounded > 0);
        }

        bool CastDown(Vector3 origin, Vector3 direction, float length, out RaycastHit best)
        {
            int count = Physics.RaycastNonAlloc(origin, direction, hits, length, ~0, QueryTriggerInteraction.Ignore);
            best = default(RaycastHit);
            float bestDistance = float.MaxValue;
            bool found = false;
            for (int i = 0; i < count; i++)
            {
                var h = hits[i];
                if (h.collider.transform.IsChildOf(transform)) continue;
                if (h.distance < bestDistance) { bestDistance = h.distance; best = h; found = true; }
            }
            return found;
        }

        void UpdateTrackVisuals(float dt)
        {
            for (int s = 0; s < 2; s++)
            {
                trackScroll[s] += trackSpeed[s] * dt;
                var mats = trackMaterials[s];
                for (int i = 0; i < mats.Length; i++)
                    if (mats[i]) mats[i].mainTextureOffset = new Vector2(0f, -trackScroll[s] / trackTileLength);

                wheelAngle[s] += trackSpeed[s] * dt / wheelRadius * Mathf.Rad2Deg;
                var wheels = s == 0 ? leftWheels : rightWheels;
                var baseRot = wheelBaseRotation[s];
                if (wheels == null) continue;
                for (int i = 0; i < wheels.Length; i++)
                    if (wheels[i]) wheels[i].localRotation = baseRot[i] * Quaternion.Euler(0f, wheelAngle[s], 0f);
            }
        }

        void LateUpdate()
        {
            if (liftCylinders == null || cylinderBases == null || cylinderRods == null) return;
            for (int i = 0; i < liftCylinders.Length; i++)
            {
                var cyl = liftCylinders[i];
                if (!cyl || i >= cylinderBases.Length || i >= cylinderRods.Length || !cylinderBases[i] || !cylinderRods[i]) continue;
                Vector3 a = cylinderBases[i].position, b = cylinderRods[i].position;
                Vector3 d = b - a;
                float len = d.magnitude;
                if (len < 1e-3f) continue;
                cyl.position = (a + b) * 0.5f;
                cyl.rotation = Quaternion.FromToRotation(Vector3.up, d / len);
                var sc = cyl.localScale;
                sc.y = len * 0.5f;
                cyl.localScale = sc;
            }
        }

        public void SetLights(bool on)
        {
            lightsOn = on;
            if (workLights != null)
                foreach (var l in workLights) if (l) l.enabled = on;
            if (lensMaterials != null)
                foreach (var m in lensMaterials)
                {
                    if (!m) continue;
                    m.SetColor("_EmissiveColor", on ? lensGlow * lensGlowIntensity : Color.black);
                    m.SetColor("_EmissionColor", on ? lensGlow * 4f : Color.black);
                }
        }

        /// <summary>Puts the dozer back where it started, sitting on the ground.</summary>
        public void ResetMachine()
        {
            Vector3 p = spawnPosition;
            if (ground) p.y = ground.WorldHeight(p.x, p.z) + 0.15f;
            body.TeleportRoot(p, spawnRotation);
#if UNITY_6000_0_OR_NEWER
            body.linearVelocity = Vector3.zero;
#else
            body.velocity = Vector3.zero;
#endif
            body.angularVelocity = Vector3.zero;
            liftTarget = 2f;
            tiltTarget = 0f;
            angleTarget = 0f;
        }

        /// <summary>Height of the cutting edge's middle above the ground under it (m).</summary>
        public float BladeHeightAboveGround(Transform edgeLeft, Transform edgeRight)
        {
            if (!ground || !edgeLeft || !edgeRight) return 0f;
            Vector3 c = (edgeLeft.position + edgeRight.position) * 0.5f;
            return c.y - ground.WorldHeight(c.x, c.z);
        }

        public IEnumerable<Collider> OwnColliders()
        {
            return GetComponentsInChildren<Collider>(true);
        }
    }
}
