// Lit, coloured by the mesh's vertex colours (the grunts, the rocket).  Instanced, so a crowd draws in a few calls.
Shader "Arena/VertexColour"
{
    Properties
    {
        _Color ("Tint", Color) = (1, 1, 1, 1)
        _Glow ("Glow", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 200
        CGPROGRAM
        #pragma surface surf Lambert fullforwardshadows addshadow
        #pragma multi_compile_instancing
        #pragma target 3.0
        struct Input { float4 color : COLOR; };
        fixed4 _Color;
        float _Glow;
        void surf(Input IN, inout SurfaceOutput o)
        {
            o.Albedo = IN.color.rgb * _Color.rgb;
            o.Emission = IN.color.rgb * _Glow;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
