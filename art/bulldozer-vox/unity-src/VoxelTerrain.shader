// Voxel ground.  The mesh is merged into big flat quads, so the per-block look is done here:
// each 6.25 cm block gets its own shade from its position.  The material id rides in vertex colour red.
Shader "Voxel/Terrain"
{
    Properties
    {
        _VoxelSize ("Voxel size", Float) = 0.0625
        _FixedMat ("Fixed material (-1 = from mesh)", Float) = -1
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 200

        CGPROGRAM
        #pragma surface surf Lambert fullforwardshadows addshadow
        #pragma target 3.5

        struct Input
        {
            float3 worldPos;
            float3 worldNormal;
            fixed4 color : COLOR;
        };

        float _VoxelSize;
        float _FixedMat;

        // 0 air, 1 soil, 2 clay, 3 rock, 4 quartz, 5 gold, 6 loose soil, 7 loose clay, 8 loose rock, 9 loose quartz, 10 loose gold
        // 11 timber, 12 dark timber, 13 steel, 14 gum leaves, 15 gum bark: used by the scenery, not by ground
        // 16 hi-vis shirt, 17 navy, 18 skin, 19 hard hat, 20 boots: the worker.  21 rust, 22 old yellow paint, 23 steel: the finds
        // 24 tool handle wood: the worker's pick and shovel (its own colour so the see-through cut never hides them)
        static const float3 MATS[27] =
        {
            float3(1.00, 0.00, 1.00),
            float3(0.74, 0.60, 0.42),
            float3(0.80, 0.47, 0.16),
            float3(0.44, 0.45, 0.48),
            float3(0.90, 0.90, 0.88),
            float3(0.98, 0.76, 0.12),
            float3(0.60, 0.46, 0.30),
            float3(0.70, 0.38, 0.13),
            float3(0.63, 0.61, 0.57),
            float3(0.80, 0.80, 0.78),
            float3(0.92, 0.68, 0.10),
            float3(0.50, 0.31, 0.17),
            float3(0.34, 0.21, 0.12),
            float3(0.42, 0.40, 0.40),
            float3(0.37, 0.42, 0.17),
            float3(0.80, 0.74, 0.64),
            float3(0.95, 0.45, 0.08),
            float3(0.13, 0.18, 0.30),
            float3(0.80, 0.60, 0.46),
            float3(0.96, 0.92, 0.80),
            float3(0.20, 0.16, 0.13),
            float3(0.46, 0.22, 0.10),
            float3(0.74, 0.58, 0.16),
            float3(0.50, 0.49, 0.48),
            float3(0.56, 0.38, 0.22),
            float3(0.20, 0.16, 0.10),       // 25 forest floor: dark leaf litter (the hillside past the fence)
            float3(0.44, 0.34, 0.22)        // 26 track dirt
        };

        sampler2D _GrassTex;
        float4 _SiteRect;
        // scenery is cut away where it stands between the camera and what the camera is following
        // (but not things that carry vertex colour green: the cart, which you need to see into)
        float4 _CutFrom, _CutTo;
        float _CutRadius;
        // the bushfire (FireSim): seconds since it started, and when each tree and each 2 m square caught
        float _FireTime;
        sampler2D _TreeFire, _GroundFire;
        float4 _TreeFireSize, _GroundFireRect;

        float hash3(float3 p)
        {
            p = frac(p * 0.3183099 + 0.1);
            p *= 17.0;
            return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
        }

        void surf(Input IN, inout SurfaceOutput o)
        {
            int m = _FixedMat >= 0 ? (int)_FixedMat : (int)round(IN.color.r * 255.0);
            m = clamp(m, 0, 26);
            if (m >= 11 && m <= 15 && _CutRadius > 0.0 && IN.color.g < 0.5)   // green set = never cut (the cart)
            {
                // how far this point is from the line between the camera and its subject
                float3 ab = _CutTo.xyz - _CutFrom.xyz;
                float t = dot(IN.worldPos - _CutFrom.xyz, ab) / max(dot(ab, ab), 0.0001);
                if (t > 0.0 && t < 1.0)
                {
                    float3 nearest = _CutFrom.xyz + ab * t;
                    clip(distance(IN.worldPos, nearest) - _CutRadius);
                }
            }
            // which block this pixel belongs to
            float3 v = floor((IN.worldPos - IN.worldNormal * 0.5 * _VoxelSize) / _VoxelSize);
            float h = hash3(v);
            float h2 = hash3(v.zxy + 7.31);
            float3 c = MATS[m];
            bool shiny = (m == 5 || m == 10);
            c *= shiny ? (0.9 + 0.2 * h) : (0.84 + 0.30 * h);
            if (!shiny && h2 > 0.92) c *= 0.78;          // the odd darker block
            if (!shiny && h2 < 0.05) c *= 1.12;          // and the odd paler one
            if (m >= 6 && !shiny)                        // loose dirt: clods of a few blocks, darker or lighter
            {
                float clod = hash3(floor(v / 3.0) + 3.7);
                c *= (m >= 8) ? (0.68 + 0.52 * clod) : (0.84 + 0.30 * clod);   // rubble varies more, lump to lump
            }
            // untouched topsoil carries dry grass on its top face; the dozer wears it off
            if (m == 1 && IN.worldNormal.y > 0.5)
            {
                float2 uv = (IN.worldPos.xz - _SiteRect.xy) * _SiteRect.zw;
                float g = (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) ? tex2Dlod(_GrassTex, float4(uv, 0, 0)).r : 0.0;
                if (g > 0.3)
                {
                    float3 grassC = lerp(float3(0.36, 0.40, 0.16), float3(0.52, 0.50, 0.22), hash3(floor(v / 2.0) + 1.3));
                    c = lerp(c, grassC * (0.8 + 0.4 * h), 0.9);
                }
            }
            if (m == 14) c *= 0.7 + 0.6 * hash3(floor(v / 4.0) + 9.1);          // leaves: clumps of light and shade
            if (m == 15 && h2 > 0.7) c = float3(0.62, 0.42, 0.30) * (0.8 + 0.3 * h);   // bark: patches where it has peeled

            // ---- the bushfire
            float3 glow = 0;
            if (_FireTime > -1000.0)
            {
                bool isTree = IN.color.a < 0.99 && (m == 14 || m == 15);
                if (isTree)
                {
                    float tid = round(IN.color.b * 255.0) + round(IN.color.a * 255.0) * 256.0;
                    float2 tuv = float2((fmod(tid, 256.0) + 0.5) * _TreeFireSize.z, (floor(tid / 256.0) + 0.5) * _TreeFireSize.w);
                    float2 tf = tex2Dlod(_TreeFire, float4(tuv, 0, 0)).rg;
                    float tb = _FireTime - tf.r;                                              // seconds this tree has been burning
                    float above = IN.worldPos.y - tf.g;                                       // metres up the trunk
                    if (tb > 0.0)
                    {
                        float flick = 0.6 + 0.4 * sin(_Time.y * 13.0 + h * 40.0) * sin(_Time.y * 5.3 + h2 * 20.0);
                        if (m == 14)
                        {
                            float scorch = smoothstep(0.0, 2.5, tb), charL = smoothstep(5.0, 18.0, tb);
                            c = lerp(c, float3(0.52, 0.19, 0.05), scorch * (1.0 - charL));
                            c = lerp(c, float3(0.05, 0.04, 0.035), charL);
                            clip((1.0 - smoothstep(4.0, 24.0, tb) * 0.88) - hash3(floor(v / 3.0) + 5.5));   // the leaves burn away
                            glow = float3(1.5, 0.45, 0.08) * (1.0 - smoothstep(5.0, 13.0, tb)) * smoothstep(0.0, 1.0, tb) * flick * step(0.35, h);
                        }
                        else
                        {
                            c = lerp(c, float3(0.045, 0.04, 0.035), smoothstep(2.0, 14.0, tb) * 0.93);
                            // embers: patches near the foot of the trunk, a few higher up, dying down over half a minute
                            float low = 1.0 - smoothstep(0.5, 3.0, above), high = 1.0 - smoothstep(3.0, 9.0, above);
                            float patch = step(1.0 - (0.35 * low + 0.06 * high), hash3(floor(v / 3.0) + 2.2));
                            glow = float3(1.6, 0.3, 0.05) * patch * smoothstep(1.0, 4.0, tb) * (1.0 - smoothstep(10.0, 40.0, tb)) * flick;
                        }
                    }
                }
                else if (m <= 10 || m >= 25)
                {
                    float2 guv = (IN.worldPos.xz - _GroundFireRect.xy) * _GroundFireRect.zw;
                    if (guv.x > 0.0 && guv.y > 0.0 && guv.x < 1.0 && guv.y < 1.0)
                    {
                        float tg = _FireTime - tex2Dlod(_GroundFire, float4(guv, 0, 0)).r + (h - 0.5) * 3.0;   // ragged edges
                        if (tg > 0.0)
                        {
                            c = lerp(c, float3(0.05, 0.045, 0.04) * (0.8 + 0.4 * h), smoothstep(0.0, 6.0, tg));
                            if (h2 > 0.72) c = lerp(c, float3(0.30, 0.29, 0.27), smoothstep(12.0, 40.0, tg));   // white ash
                            glow = float3(2.4, 0.5, 0.06) * (1.0 - smoothstep(1.5, 9.0, tg)) * step(0.55, h) * (0.6 + 0.4 * sin(_Time.y * 9.0 + h2 * 30.0));
                        }
                    }
                }
            }
            #ifndef UNITY_COLORSPACE_GAMMA
            c = GammaToLinearSpace(c);
            #endif
            o.Albedo = c;
            o.Emission = glow;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
