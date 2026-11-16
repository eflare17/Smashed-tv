// Flames and embers: glowing cubes, added onto what's behind them, bright enough for the bloom to catch.
Shader "Voxel/FireParticle"
{
    Properties { _Boost ("Brightness", Float) = 4 }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Blend One One
        ZWrite Off
        Cull Back
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            float _Boost;
            struct appdata { float4 vertex : POSITION; fixed4 color : COLOR; };
            struct v2f { float4 pos : SV_POSITION; fixed4 color : COLOR; };
            v2f vert(appdata v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.color = v.color; return o; }
            fixed4 frag(v2f i) : SV_Target { return float4(i.color.rgb * i.color.a * _Boost, 1); }
            ENDCG
        }
    }
}
