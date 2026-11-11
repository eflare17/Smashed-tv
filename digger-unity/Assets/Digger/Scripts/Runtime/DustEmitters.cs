using UnityEngine;

namespace Digger
{
    /// <summary>Dust while pushing (blade ends) and while driving fast (behind the tracks).</summary>
    public class DustEmitters : MonoBehaviour
    {
        public ParticleSystem bladeLeft, bladeRight, trackLeft, trackRight;
        public float maxBladeRate = 45f;
        public float maxTrackRate = 12f;

        float bladeRate, trackRate;

        public void SetBladeActivity(float cutRate, float load, float speed)
        {
            bladeRate = Mathf.Clamp(cutRate * 70f + load * speed * 6f, 0f, maxBladeRate);
        }

        public void SetTrackSpeed(float speed, bool onGround)
        {
            trackRate = onGround ? Mathf.Clamp01((Mathf.Abs(speed) - 0.4f) / 2.2f) * maxTrackRate : 0f;
        }

        void Update()
        {
            Set(bladeLeft, bladeRate);
            Set(bladeRight, bladeRate);
            Set(trackLeft, trackRate);
            Set(trackRight, trackRate);
        }

        static void Set(ParticleSystem ps, float rate)
        {
            if (!ps) return;
            var emission = ps.emission;
            emission.rateOverTime = rate;
            if (rate > 0f && !ps.isPlaying) ps.Play();
        }
    }
}
