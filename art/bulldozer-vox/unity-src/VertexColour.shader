// Lit, coloured by the mesh's vertex colours: the grunts (Grunts.cs, from the Voxel Arena's Arena/VertexColour).
Shader "Voxel/VertexColour"
{
    Properties
    {
        _Color ("Tint", Color) = (1, 1, 1, 1)
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 200
        CGPROGRAM
        #pragma surface surf Lambert fullforwardshadows addshadow
        #pragma target 3.0
        struct Input { float4 color : COLOR; };
        fixed4 _Color;
        void surf(Input IN, inout SurfaceOutput o)
        {
            o.Albedo = IN.color.rgb * _Color.rgb;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
