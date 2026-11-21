// Picture settings that have to be set while the game runs: shadow quality and how many lights can shine at once.
// The sun, sky, haze and colour grade themselves are saved in the scene by the builder.
using UnityEngine;

public class SceneLook : MonoBehaviour
{
    public float shadowDistance = 110f;

    void Awake()
    {
        QualitySettings.shadows = ShadowQuality.All;
        QualitySettings.shadowResolution = ShadowResolution.VeryHigh;
        QualitySettings.shadowProjection = ShadowProjection.StableFit;
        QualitySettings.shadowCascades = 4;
        QualitySettings.shadowDistance = shadowDistance;
        QualitySettings.pixelLightCount = 8;
    }
}
