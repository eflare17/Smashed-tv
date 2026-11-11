// Soft dust puffs for the built-in particle system. HDRP draws passes tagged
// "SRPDefaultUnlit", so this simple alpha-blended shader works without Shader Graph.
// Placeholder until the dust moves to a VFX Graph.
Shader "Digger/Dust"
{
    Properties
    {
        _MainTex ("Puff", 2D) = "white" {}
        _Tint ("Tint", Color) = (0.6, 0.52, 0.42, 1)
        _Brightness ("Brightness", Float) = 1.0
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float4 _Tint;
            float _Brightness;

            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; float4 color : COLOR; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; float4 color : COLOR; };

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.color = v.color;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float4 t = tex2D(_MainTex, i.uv);
                float3 rgb = _Tint.rgb * i.color.rgb * _Brightness;
                return float4(rgb, t.a * i.color.a * _Tint.a);
            }
            ENDCG
        }
    }
    Fallback Off
}
