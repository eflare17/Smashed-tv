using UnityEngine;

namespace Digger
{
    /// <summary>
    /// One frame of driver commands for a dozer. Kept separate from input devices so a
    /// network player, an AI or a replay can drive the same machine later (multiplayer is
    /// planned from Stage 1, switched on later).
    /// </summary>
    [System.Serializable]
    public struct DozerControls
    {
        /// <summary>-1 full reverse .. 1 full forward, scaled by the selected gear.</summary>
        public float throttle;
        /// <summary>-1 left .. 1 right. With no throttle the tracks counter-rotate (pivot turn).</summary>
        public float steer;
        /// <summary>0..1 brakes both tracks.</summary>
        public float brake;
        /// <summary>Blade lift rate: -1 lower .. 1 raise.</summary>
        public float bladeLift;
        /// <summary>Blade tilt rate: -1 left corner up .. 1 right corner up.</summary>
        public float bladeTilt;
        /// <summary>Blade angle (swing) rate: -1 swing left .. 1 swing right.</summary>
        public float bladeAngle;
        /// <summary>Absolute tilt -1..1, used when <see cref="useTiltDirect"/> is set (controller gyro).</summary>
        public float tiltDirect;
        public bool useTiltDirect;

        // One-shot events for this frame.
        public int gearDelta;
        public bool toggleLights;
        public bool resetMachine;
        public bool resetGround;
    }

    /// <summary>Anything that can drive a dozer: local input, network, AI.</summary>
    public interface IDozerControlSource
    {
        DozerControls Read();
    }
}
