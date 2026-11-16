// Flames, drawn live: each flame is a soft upright quad, and the fire in it is worked out per pixel every frame
// from noise that streams upward and is warped sideways, so it ripples, splits and licks like real fire.
// White-hot core low down, orange body, red then dark at the ragged tips.  Every flame has its own random seed
// (from the particle system), so no two look or move alike.  Added onto what's behind, bright enough for the bloom.
Shader "Voxel/FireFlame"
{
    Properties { _Boost ("Brightness", Float) = 2.6 _Speed ("Rise speed", Float) = 2.4 }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Blend One One
        ZWrite Off
        Cull Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            float _Boost, _Speed;
            struct appdata { float4 vertex : POSITION; fixed4 color : COLOR; float4 uv : TEXCOORD0; };   // uv.z: the flame's random seed
            struct v2f { float4 pos : SV_POSITION; fixed4 color : COLOR; float3 uv : TEXCOORD0; };
            v2f vert(appdata v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.color = v.color; o.uv = v.uv.xyz; return o; }

            float hash(float2 p) { p = frac(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return frac(p.x * p.y); }
            float noise(float2 p)
            {
                float2 i = floor(p), f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(hash(i), hash(i + float2(1, 0)), f.x), lerp(hash(i + float2(0, 1)), hash(i + float2(1, 1)), f.x), f.y);
            }
            float fbm(float2 p) { float s = 0, a = 0.5; for (int k = 0; k < 4; k++) { s += a * noise(p); p *= 2.07; a *= 0.5; } return s; }

            fixed4 frag(v2f i) : SV_Target
            {
                float seed = i.uv.z * 97.0;
                float t = _Time.y * _Speed + seed;
                float x = i.uv.x * 2.0 - 1.0, y = i.uv.y;                     // x: -1..1 across, y: 0 root .. 1 tip
                // turbulence streaming upward, and a slower wobble, bend the flame sideways more the higher it goes
                float n1 = fbm(float2(x * 1.6 + seed, y * 2.2 - t));
                float n2 = fbm(float2(x * 3.4 - seed, y * 4.5 - t * 1.7));
                x += (n1 - 0.5) * 1.7 * (0.25 + y) + sin(t * 0.9 + y * 3.0) * 0.1 * y;
                // the body: a broad base narrowing upward, split into separate licking tongues by a third noise,
                // and its edges eaten away by the fine noise
                float width = 0.95 * pow(saturate(1.0 - y), 0.45) + 0.04;
                float body = saturate(1.0 - abs(x) / width);
                float licks = fbm(float2(x * 2.6 + seed * 3.0, y * 1.4 - t * 1.25));
                float f = body * 1.5 - (1.0 - n2) * (0.3 + 1.0 * y) - (1.0 - licks) * y * 0.9 - y * 0.2;
                f *= smoothstep(0.0, 0.12, y);                                 // soft where it meets the ground
                f = saturate(f);
                // colour from heat: dark red, red, orange, yellow, white
                float3 c = lerp(float3(0.3, 0.02, 0.0), float3(0.9, 0.16, 0.01), smoothstep(0.0, 0.35, f));
                c = lerp(c, float3(1.0, 0.45, 0.05), smoothstep(0.3, 0.65, f));
                c = lerp(c, float3(1.0, 0.75, 0.25), smoothstep(0.6, 0.9, f));
                c = lerp(c, float3(1.0, 0.95, 0.75), smoothstep(0.9, 1.0, f) * 0.8);
                float a = smoothstep(0.02, 0.25, f);
                return float4(c * a * i.color.rgb * i.color.a * _Boost, 1);
            }
            ENDCG
        }
    }
}
