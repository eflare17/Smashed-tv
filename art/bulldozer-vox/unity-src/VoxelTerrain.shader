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
        #pragma surface surf Voxel vertex:vert fullforwardshadows addshadow
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
        static const float3 MATS[32] =
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
            float3(0.44, 0.34, 0.22),       // 26 track dirt
            float3(0.36, 0.43, 0.50),       // 27 the son's plain shirt
            float3(0.20, 0.25, 0.37),       // 28 jeans
            float3(0.16, 0.15, 0.14),       // 29 dark cap
            float3(0.30, 0.44, 0.13),       // 30 bracken: the green that comes back after a fire
            float3(0.45, 0.78, 0.98)        // 31 ice blue: the freeze gun
        };

        sampler2D _GrassTex;
        float4 _SiteRect;
        // the mountain road's guide tint (MountainRoadJob): a picture over the road, red / blue / green, alpha = how strongly
        sampler2D _RoadTint;
        float4 _RoadRect;
        float _RoadTintOn;
        // scenery is cut away where it stands between the camera and what the camera is following
        // (but not things that carry vertex colour green: the cart, which you need to see into)
        float4 _CutFrom, _CutTo;
        float _CutRadius;
        // the bushfire (FireSim): seconds since it started, and when each tree and each 2 m square caught
        float _FireTime;
        float _Regrowth;        // 1: years after the fire.  About half the burnt gums have resprouted, the rest are grey dead spars, the burnt ground is green bracken
        sampler2D _TreeFire, _GroundFire, _TreeBase;
        float4 _TreeFireSize, _GroundFireRect;
        // trees the dozer pushes over (TreeFelling): per tree r = when it started to fall (on _FellClock; huge = standing),
        // g = which way it falls, b = how far it leans while being pushed, a = which way it leans.  _FellOn 0: none yet.
        sampler2D _TreeFell;
        float _FellClock, _FellOn;

        // Quartz and gold catch the light up close: within about 4 m of him (_SparkleFrom), a few blocks of the seam
        // twinkle with a tiny bright point where a light falls on them.  Gold twinkles more.  Further off they look
        // as they always did.  surf puts the twinkle's strength in Specular and the block's own timing in Gloss.
        float4 _SparkleFrom;     // xyz where he is, w 1 when it is on
        inline fixed4 LightingVoxel(SurfaceOutput s, half3 viewDir, UnityGI gi)
        {
            fixed4 c = LightingLambert(s, gi);
            if (s.Specular > 0.0)
            {
                float tw = saturate(sin(_Time.y * (1.3 + 2.4 * s.Gloss) + s.Gloss * 62.83));
                tw = tw * tw; tw = tw * tw;                                     // short bright flashes
                float lit = saturate(dot(s.Normal, gi.light.dir));
                c.rgb += gi.light.color * (lit * tw * s.Specular * 1.8);
            }
            return c;
        }
        inline void LightingVoxel_GI(SurfaceOutput s, UnityGIInput data, inout UnityGI gi) { LightingLambert_GI(s, data, gi); }

        float hash3(float3 p)
        {
            p = frac(p * 0.3183099 + 0.1);
            p *= 17.0;
            return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
        }

        // a burnt tree falling: tipped over from its foot towards its fall angle, slow at first, then a small bounce
        float3 RotateAbout(float3 p, float3 axis, float a)
        {
            float c = cos(a), s = sin(a);
            return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
        }

        void vert(inout appdata_full v)
        {
            if (v.color.a > 0.99) return;
            if (_FireTime < -1000.0 && _FellOn < 0.5) return;
            float m = round(v.color.r * 255.0);
            if (m != 14.0 && m != 15.0) return;
            float tid = round(v.color.b * 255.0) + round(v.color.a * 255.0) * 256.0;
            float4 tuv = float4((fmod(tid, 256.0) + 0.5) * _TreeFireSize.z, (floor(tid / 256.0) + 0.5) * _TreeFireSize.w, 0, 0);
            float4 f = tex2Dlod(_TreeFire, tuv);
            float2 b = tex2Dlod(_TreeBase, tuv).rg;
            float3 pivot = float3(b.x, f.g, b.y);
            float ang = 0.0, way = 0.0;
            float4 fl = _FellOn > 0.5 ? tex2Dlod(_TreeFell, tuv) : float4(1e9, 0, 0, 0);
            float tp = _FellClock - fl.r;
            if (tp > 0.0)
            {
                // pushed over: it falls like a burnt one, and once down it has broken up into wood (TreeFelling): gone
                if (tp > 2.75) { v.vertex.xyz = mul(unity_WorldToObject, float4(pivot - float3(0, 60, 0), 1)).xyz; return; }
                float u = saturate(tp / 2.6);
                ang = max(fl.b, u * u * 1.53); way = fl.g;
            }
            else if (fl.b > 0.0) { ang = fl.b; way = fl.a; }                                // leaning under the blade
            else
            {
                if (_FireTime < -1000.0) return;
                float tf = _FireTime - f.b;
                if (tf <= 0.0) return;
                float u = saturate(tf / 2.6);
                ang = u * u * 1.53;
                if (tf > 2.6) ang = 1.53 - 0.07 * sin(min((tf - 2.6) * 7.0, 3.14159)) * exp(-(tf - 2.6) * 2.5);
                way = f.a;
            }
            float3 dir = float3(sin(way), 0, cos(way));
            float3 axis = normalize(cross(float3(0, 1, 0), dir));
            float3 wp = mul(unity_ObjectToWorld, v.vertex).xyz - pivot;
            wp = RotateAbout(wp, axis, ang) + pivot;
            v.vertex.xyz = mul(unity_WorldToObject, float4(wp, 1)).xyz;
            float3 wn = mul((float3x3)unity_ObjectToWorld, v.normal);
            v.normal = mul((float3x3)unity_WorldToObject, RotateAbout(wn, axis, ang));
        }

        void surf(Input IN, inout SurfaceOutput o)
        {
            int m = _FixedMat >= 0 ? (int)_FixedMat : (int)round(IN.color.r * 255.0);
            m = clamp(m, 0, 30);
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
            if (m == 1 && IN.worldNormal.y <= 0.5)
            {
                // the side of a step of untouched leaf litter (the mountain road's strip): dark like the forest floor too
                float2 suv = (IN.worldPos.xz - IN.worldNormal.xz * 0.5 * _VoxelSize - _SiteRect.xy) * _SiteRect.zw;
                float sg = (suv.x > 0.0 && suv.y > 0.0 && suv.x < 1.0 && suv.y < 1.0) ? tex2Dlod(_GrassTex, float4(suv, 0, 0)).r : 0.0;
                if (sg > 0.15 && sg < 0.3) c = lerp(c, MATS[25] * 0.8 * (0.84 + 0.30 * h), 0.9);
            }
            if (m == 1 && IN.worldNormal.y > 0.5)
            {
                float2 uv = (IN.worldPos.xz - _SiteRect.xy) * _SiteRect.zw;
                float g = (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) ? tex2Dlod(_GrassTex, float4(uv, 0, 0)).r : 0.0;
                if (g > 0.3)
                {
                    float3 grassC = lerp(float3(0.36, 0.40, 0.16), float3(0.52, 0.50, 0.22), hash3(floor(v / 2.0) + 1.3));
                    c = lerp(c, grassC * (0.8 + 0.4 * h), 0.9);
                }
                else if (g > 0.15)
                {
                    // leaf litter: the mountain's forest floor, on the road strip before it is worked (VoxelWorld.Litter)
                    c = lerp(c, MATS[25] * (0.84 + 0.30 * h), 0.9);
                }
            }
            // the road guide: red where the ground is too high, blue too low, green on grade (top faces of the ground only)
            if (_RoadTintOn > 0.5 && m <= 10 && IN.worldNormal.y > 0.5)
            {
                float2 ruv = (IN.worldPos.xz - _RoadRect.xy) * _RoadRect.zw;
                if (ruv.x > 0.0 && ruv.y > 0.0 && ruv.x < 1.0 && ruv.y < 1.0)
                {
                    float4 rt = tex2Dlod(_RoadTint, float4(ruv, 0, 0));
                    c = lerp(c, rt.rgb * (0.9 + 0.2 * h), rt.a);
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
                    float4 tf = tex2Dlod(_TreeFire, float4(tuv, 0, 0));
                    float tb = _FireTime - tf.r;                                              // seconds this tree has been burning
                    float above = IN.worldPos.y - tf.g;                                       // metres up the trunk
                    if (tb > 0.0 && _Regrowth > 0.5)
                    {
                        // years on: the fallen are dead logs; of those still standing about half have put out fresh
                        // leaves (gums do, from buds under the bark), the rest are bare grey spars
                        bool fallen = _FireTime > tf.b + 3.0;
                        bool lives = !fallen && frac(sin(tid * 12.9898 + 4.1) * 43758.5453) < 0.45;
                        if (m == 14)
                        {
                            clip(lives ? 0.58 - hash3(floor(v / 3.0) + 5.5) : -1.0);
                            c = lerp(c, float3(0.34, 0.50, 0.17), 0.5);
                        }
                        else c = lives ? lerp(c, float3(0.07, 0.06, 0.05), 0.6) : float3(0.50, 0.48, 0.45) * (0.78 + 0.36 * h);
                    }
                    else if (tb > 0.0)
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
                else if (m <= 10 || m == 25 || m == 26)
                {
                    float2 guv = (IN.worldPos.xz - _GroundFireRect.xy) * _GroundFireRect.zw;
                    if (guv.x > 0.0 && guv.y > 0.0 && guv.x < 1.0 && guv.y < 1.0)
                    {
                        float tg = _FireTime - tex2Dlod(_GroundFire, float4(guv, 0, 0)).r + (h - 0.5) * 3.0;   // ragged edges
                        if (tg > 0.0 && _Regrowth > 0.5)
                        {
                            float3 br = lerp(float3(0.25, 0.34, 0.11), float3(0.42, 0.47, 0.19), hash3(floor(v / 2.0) + 4.4)) * (0.8 + 0.4 * h);
                            c = lerp(c, br, m == 26 ? 0.35 * step(0.5, h2) : 0.85);
                        }
                        else if (tg > 0.0)
                        {
                            c = lerp(c, float3(0.05, 0.045, 0.04) * (0.8 + 0.4 * h), smoothstep(0.0, 6.0, tg));
                            if (h2 > 0.72) c = lerp(c, float3(0.30, 0.29, 0.27), smoothstep(12.0, 40.0, tg));   // white ash
                            glow = float3(2.4, 0.5, 0.06) * (1.0 - smoothstep(1.5, 9.0, tg)) * step(0.55, h) * (0.6 + 0.4 * sin(_Time.y * 9.0 + h2 * 30.0));
                        }
                    }
                }
            }
            if ((m == 4 || m == 5 || m == 10) && _SparkleFrom.w > 0.5)        // the seam and loose gold; not loose quartz (a heap of it in the sun was all glare)
            {
                float near = saturate((4.5 - distance(IN.worldPos, _SparkleFrom.xyz)) / 1.0);
                bool gold = (m == 5 || m == 10);
                float pick = hash3(v + 19.7);
                if (near > 0.0 && pick < (gold ? 0.35 : 0.08))
                {
                    // a point in the middle of the block's face, not the whole face
                    float3 f = frac(IN.worldPos / _VoxelSize) - 0.5;
                    float3 n = IN.worldNormal;
                    f -= n * dot(f, n);
                    float star = saturate(1.0 - length(f) / 0.16);      // a small point: in the sun a bigger one turned whole faces white
                    o.Specular = near * star * star * (gold ? 1.6 : 1.0);
                    o.Gloss = hash3(v + 41.3);
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
