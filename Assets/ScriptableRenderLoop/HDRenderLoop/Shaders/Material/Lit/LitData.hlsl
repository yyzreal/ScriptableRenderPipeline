//-------------------------------------------------------------------------------------
// FragInput
// This structure gather all possible varying/interpolator for this shader.
//-------------------------------------------------------------------------------------

struct FragInput
{
    float4 unPositionSS; // This is the position return by VPOS, only xy is use
    float3 positionWS;
    float2 texCoord0;
    float2 texCoord1;
    float2 texCoord2;
    float3 tangentToWorld[3];
    bool isFrontFace;
};

//-------------------------------------------------------------------------------------
// Fill SurfaceData/Builtin data function
//-------------------------------------------------------------------------------------

// Should SH (light probe / ambient) calculations be performed?
// - Presence of *either* of static or dynamic lightmaps means that diffuse indirect ambient is already in them, so no need for SH.
// - Passes that don't do ambient (additive, shadowcaster etc.) should not do SH either.
#define UNITY_SHOULD_SAMPLE_SH (!defined(LIGHTMAP_ON) && !defined(DYNAMICLIGHTMAP_ON) && !defined(UNITY_PASS_FORWARDADD) && !defined(UNITY_PASS_PREPASSBASE) && !defined(UNITY_PASS_SHADOWCASTER) && !defined(UNITY_PASS_META))

//Check that it is always the case
// UNITY_SAMPLE_FULL_SH_PER_PIXEL

float3 SampleBakedGI(float3 positionWS, float3 normalWS)
{
#if UNITY_SHOULD_SAMPLE_SH
	#if UNITY_LIGHT_PROBE_PROXY_VOLUME
	if (unity_ProbeVolumeParams.x == 1.0)
	{
		// TODO: Move all this to C++!
		float4x4 identity = 0;
		identity._m00_m11_m22_m33 = 1.0;
		float4x4 WorldToTexture = (unity_ProbeVolumeParams.y == 1.0f) ? unity_ProbeVolumeWorldToObject : identity;

		float4x4 translation = identity;
		translation._m30_m31_m32 = -unity_ProbeVolumeMin.xyz;
		
		float4x4 scale = 0;
		scale._m00_m11_m22_m33 = float4(unity_ProbeVolumeSizeInv.xyz, 1.0);

		WorldToTexture = mul(mul(scale, translation), WorldToTexture);
		return SampleProbeVolumeL0L1(TEXTURE3D_PASS(unity_ProbeVolumeSH, samplerunity_ProbeVolumeSH), positionWS, normalWS, WorldToTexture, unity_ProbeVolumeParams.z);
	}
	#else

	// TODO: pass a tab of coefficient instead!
	float4 SHCoefficients[7];
	SHCoefficients[0] = unity_SHAr;
	SHCoefficients[1] = unity_SHAg;
	SHCoefficients[2] = unity_SHAb;
	SHCoefficients[3] = unity_SHBr;
	SHCoefficients[4] = unity_SHBg;
	SHCoefficients[5] = unity_SHBb;
	SHCoefficients[6] = unity_SHC;
	
	return SampleSH9(SHCoefficients, normalWS);

	#endif
#elif defined(LIGHTMAP_ON)

	/*
	float2 = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
	.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;

	// Baked lightmaps
	half4 bakedColorTex = UNITY_SAMPLE_TEX2D(unity_Lightmap, data.lightmapUV.xy);
	half3 bakedColor = DecodeLightmap(bakedColorTex);

#ifdef DIRLIGHTMAP_COMBINED
	fixed4 bakedDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_LightmapInd, unity_Lightmap, data.lightmapUV.xy);
	o_gi.indirect.diffuse = DecodeDirectionalLightmap(bakedColor, bakedDirTex, normalWorld);
#else // not directional lightmap
	o_gi.indirect.diffuse = bakedColor;
#endif
#endif

#ifdef DYNAMICLIGHTMAP_ON
	// Dynamic lightmaps
	fixed4 realtimeColorTex = UNITY_SAMPLE_TEX2D(unity_DynamicLightmap, data.lightmapUV.zw);
	half3 realtimeColor = DecodeRealtimeLightmap(realtimeColorTex);

#ifdef DIRLIGHTMAP_COMBINED
	half4 realtimeDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicDirectionality, unity_DynamicLightmap, data.lightmapUV.zw);
	o_gi.indirect.diffuse += DecodeDirectionalLightmap(realtimeColor, realtimeDirTex, normalWorld);
#else
	o_gi.indirect.diffuse += realtimeColor;
#endif
#endif
*/

#else
	return float3(0.0, 0.0, 0.0);
#endif
}

void GetSurfaceAndBuiltinData(FragInput input, out SurfaceData surfaceData, out BuiltinData builtinData)
{    
#ifdef _HEIGHTMAP
    // TODO: in case of shader graph, a node like parallax must be nullify if use to generate code for Meta pass
    #ifndef _HEIGHTMAP_AS_DISPLACEMENT
    float3 V = GetWorldSpaceNormalizeViewDir(input.positionWS); // This should be remove by the compiler as we usually cal it before.
    float height = UNITY_SAMPLE_TEX2D(_HeightMap, input.texCoord0).r * _HeightScale + _HeightBias;
    // Transform view vector in tangent space
    TransformWorldToTangent(V, input.tangentToWorld);
    float2 offset = ParallaxOffset(viewDirTS, height);
    input.texCoord0 += offset;
    input.texCoord1 += offset;
    #endif
#endif

    surfaceData.baseColor = UNITY_SAMPLE_TEX2D(_BaseColorMap, input.texCoord0).rgb * _BaseColor.rgb;
#ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
    float alpha = _BaseColor.a;
#else
    float alpha = UNITY_SAMPLE_TEX2D(_BaseColorMap, input.texCoord0).a * _BaseColor.a;
#endif

#ifdef _ALPHATEST_ON
    clip(alpha - _AlphaCutoff);
#endif

#ifdef _SPECULAROCCLUSIONMAP
    // TODO: Do something. For now just take alpha channel
    surfaceData.specularOcclusion = UNITY_SAMPLE_TEX2D(_SpecularOcclusionMap, input.texCoord0).a;
#else
    // Horizon Occlusion for Normal Mapped Reflections: http://marmosetco.tumblr.com/post/81245981087
    //surfaceData.specularOcclusion = saturate(1.0 + horizonFade * dot(r, input.tangentToWorld[2].xyz);
    // smooth it
    //surfaceData.specularOcclusion *= surfaceData.specularOcclusion;
    surfaceData.specularOcclusion = 1.0;
#endif

    // TODO: think about using BC5
    float3 vertexNormalWS = input.tangentToWorld[2].xyz;

#ifdef _NORMALMAP
    #ifdef _NORMALMAP_TANGENT_SPACE
    float3 normalTS = UnpackNormalAG(UNITY_SAMPLE_TEX2D(_NormalMap, input.texCoord0));
    surfaceData.normalWS = TransformTangentToWorld(normalTS, input.tangentToWorld);
    #else // Object space (TODO: We need to apply the world rotation here! - Require to pass world transform)
    surfaceData.normalWS = UNITY_SAMPLE_TEX2D(_NormalMap, input.texCoord0).rgb;
    #endif
#else
    surfaceData.normalWS = vertexNormalWS;
#endif

#if defined(_DOUBLESIDED_LIGHTING_FLIP) || defined(_DOUBLESIDED_LIGHTING_MIRROR)
    #ifdef _DOUBLESIDED_LIGHTING_FLIP
    float3 oppositeNormalWS = -surfaceData.normalWS;
    #else
    // Mirror the normal with the plane define by vertex normal
    float3 oppositeNormalWS = reflect(surfaceData.normalWS, vertexNormalWS);
#endif
    // TODO : Test if GetOdddNegativeScale() is necessary here in case of normal map, as GetOdddNegativeScale is take into account in CreateTangentToWorld();
    surfaceData.normalWS =  input.isFrontFace ? 
                                (GetOdddNegativeScale() >= 0.0 ? surfaceData.normalWS : oppositeNormalWS) :
                                (-GetOdddNegativeScale() >= 0.0 ? surfaceData.normalWS : oppositeNormalWS);
#endif

#ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
    surfaceData.perceptualSmoothness = UNITY_SAMPLE_TEX2D(_BaseColorMap, input.texCoord0).a;
#elif defined(_MASKMAP)
    surfaceData.perceptualSmoothness = UNITY_SAMPLE_TEX2D(_MaskMap, input.texCoord0).a;
#else
    surfaceData.perceptualSmoothness = 1.0;
#endif
    surfaceData.perceptualSmoothness *= _Smoothness;

    surfaceData.materialId = 0;

    // MaskMap is Metallic, Ambient Occlusion, (Optional) - emissive Mask, Optional - Smoothness (in alpha)
#ifdef _MASKMAP
    surfaceData.metallic = UNITY_SAMPLE_TEX2D(_MaskMap, input.texCoord0).r;
    surfaceData.ambientOcclusion = UNITY_SAMPLE_TEX2D(_MaskMap, input.texCoord0).g;
#else
    surfaceData.metallic = 1.0;
    surfaceData.ambientOcclusion = 1.0;
#endif
    surfaceData.metallic *= _Metallic;


    surfaceData.tangentWS = input.tangentToWorld[0].xyz; // TODO: do with tangent same as with normal, sample into texture etc...
    surfaceData.anisotropy = 0;
    surfaceData.specular = 0.04;

    surfaceData.subSurfaceRadius = 1.0;
    surfaceData.thickness = 0.0;
    surfaceData.subSurfaceProfile = 0;

    surfaceData.coatNormalWS = float3(1.0, 0.0, 0.0);
    surfaceData.coatPerceptualSmoothness = 1.0;
    surfaceData.specularColor = float3(0.0, 0.0, 0.0);


    // Builtin Data
    builtinData.opacity = alpha;

    // TODO: Sample lightmap/lightprobe/volume proxy
    // This should also handle projective lightmap
    // Note that data input above can be use to sample into lightmap (like normal)
	builtinData.bakeDiffuseLighting = SampleBakedGI(input.positionWS, surfaceData.normalWS);

    // If we chose an emissive color, we have a dedicated texture for it and don't use MaskMap
#ifdef _EMISSIVE_COLOR
    #ifdef _EMISSIVE_COLOR_MAP
    builtinData.emissiveColor = UNITY_SAMPLE_TEX2D(_EmissiveColorMap, input.texCoord0).rgb * _EmissiveColor;
    #else
    builtinData.emissiveColor = _EmissiveColor;
    #endif
#elif defined(_MASKMAP) // If we have a MaskMap, use emissive slot as a mask on baseColor
    builtinData.emissiveColor = surfaceData.baseColor * UNITY_SAMPLE_TEX2D(_MaskMap, input.texCoord0).bbb;
#else
    builtinData.emissiveColor = float3(0.0, 0.0, 0.0);
#endif

    builtinData.emissiveIntensity = _EmissiveIntensity;

    builtinData.velocity = float2(0.0, 0.0);

    builtinData.distortion = float2(0.0, 0.0);
    builtinData.distortionBlur = 0.0;
}