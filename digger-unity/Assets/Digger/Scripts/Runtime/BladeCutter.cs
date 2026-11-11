using UnityEngine;

namespace Digger
{
    /// <summary>
    /// Connects the blade to the ground: every physics step it cuts and pushes soil along
    /// the cutting edge, and pushes back on the blade with the weight of the heap being
    /// shoved and the resistance of the soil being cut, so a loaded blade slows the dozer.
    /// </summary>
    public class BladeCutter : MonoBehaviour
    {
        public DeformableGround ground;
        [Tooltip("Left end of the cutting edge.")]
        public Transform edgeLeft;
        [Tooltip("Right end of the cutting edge.")]
        public Transform edgeRight;
        [Tooltip("The blade's articulation link (the resistance force is applied to it).")]
        public ArticulationBody blade;
        public DustEmitters dust;
        [Tooltip("Height of the moldboard; soil heaped higher than this doesn't add load.")]
        public float bladeHeight = 1.25f;

        [Header("Soil")]
        public float soilDensity = 1650f;
        [Tooltip("Friction of the heap sliding over the ground in front of the blade.")]
        public float heapFriction = 0.6f;
        [Tooltip("Force per square metre of soil face being cut (N/m²).")]
        public float cuttingResistance = 60000f;
        [Tooltip("Upper limit on the soil force, so the machine stalls instead of flipping.")]
        public float maxResistance = 240000f;

        /// <summary>Soil heaped against the blade (m³), smoothed.</summary>
        public float LoadVolume { get; private set; }
        /// <summary>Soil cut per second (m³/s), smoothed.</summary>
        public float CutRate { get; private set; }

        void FixedUpdate()
        {
            if (!ground || !edgeLeft || !edgeRight || !blade) return;
            Vector3 left = edgeLeft.position, right = edgeRight.position;
            Vector3 centre = (left + right) * 0.5f;
            Vector3 v = blade.GetPointVelocity(centre);
            var pass = ground.BladePass(left, right, blade.transform.forward, v, bladeHeight);

            float dt = Time.fixedDeltaTime;
            LoadVolume = Mathf.Lerp(LoadVolume, pass.loadVolume, 0.3f);
            CutRate = Mathf.Lerp(CutRate, pass.cutVolume / dt, 0.2f);

            var vh = new Vector3(v.x, 0f, v.z);
            float speed = vh.magnitude;
            if (speed > 0.02f)
            {
                float heap = LoadVolume * soilDensity * 9.81f * heapFriction;
                float cutFace = (pass.cutVolume / dt) / Mathf.Max(speed, 0.1f);
                float force = Mathf.Min(heap + cutFace * cuttingResistance, maxResistance);
                force *= Mathf.Clamp01(speed / 0.15f);
                blade.AddForceAtPosition(-vh / speed * force, centre);
            }
            if (dust) dust.SetBladeActivity(CutRate, LoadVolume, speed);
        }
    }
}
