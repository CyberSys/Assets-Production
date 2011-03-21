#version 130

// Default precision qualifier - make pedantic drivers happy,
// since OpenGL specs clearly specify they have no meaning except in OpenGL ES
precision mediump float;

#include "gas_giants_params.h"
#include "../config.h"
#include "../stdlib.h"
#include "../fplod.h"

#define inCloudCoord gl_TexCoord[0]
#define inGroundCoord gl_TexCoord[1]
#define inShadowCoord gl_TexCoord[2]
#define inNoiseCoord gl_TexCoord[3]

varying vec3 varTSLight;
varying vec3 varTSView;
varying vec3 varWSNormal;

uniform sampler2D cosAngleToDepth_20;
uniform sampler2D cloudMap_20;
uniform sampler2D noiseMap_20;
uniform samplerCube envMap;

float expandPrecision(vec4 src)
{
   return dot(src,(vec4(1.0,256.0,65536.0,0.0)/131072.0));
}

float cosAngleToDepth(float fNDotV)
{
   vec2 res = vec2(1.0) / vec2(1024.0,128.0);
   vec2 mn = res * 0.5;
   vec2 mx = vec2(1.0)-res * 0.5;
   return expandPrecision(texture2DLod(cosAngleToDepth_20,clamp(vec2(fNDotV,fAtmosphereType),mn,mx),0.0)) * fAtmosphereThickness;
}

float cosAngleToAlpha(float fNDotV)
{
   vec2 res = vec2(1.0) / vec2(1024.0,128.0);
   vec2 mn = res * 0.5;
   vec2 mx = vec2(1.0)-res * 0.5;
   vec2 tc = clamp(vec2(fNDotV,fAtmosphereType),mn,mx);
   return textureGrad(cosAngleToDepth_20,tc,dFdx(vec2(0.0,tc.y)),dFdy(vec2(0.0,tc.y))).a;
}

float  atmosphereLighting(float fNDotL) { return saturatef(soft_min(1.0,2.0*fAtmosphereContrast*sqr(fNDotL))); }
float  groundLighting(float fNDotL) { return saturatef(soft_min(1.0,2.0*fGroundContrast*fNDotL)); }

float reyleighShadow(float fNDotV) {
    return pow(1.0-fNDotV, 6.0);
}

vec3 reyleigh(float fNDotV, float fVDotL, float ldepth, vec3 fAtmosphereScatterColor, float saturation)
{
    if (ldepth > 0.0 && fVDotL < 0.0) {
        vec3 scatter = lerp(gl_LightSource[0].diffuse.rgb * luma(fAtmosphereScatterColor.rgb), fAtmosphereScatterColor.rgb, saturation);
        float rfactor = fVDotL*pow(saturatef(-fVDotL),64.0/(fReyleighAmount*fReyleighRate*ldepth));
        return degamma(fReyleighAmount*rfactor*scatter) * reyleighShadow(fNDotV);
    } else {
        return vec3(0.0);
    }
}

vec4 atmosphericScatter(vec3 atmo, vec3 amb, vec4 dif, float fNDotV, float fNDotL, float fVDotL)
{
   float  vdepth     = cosAngleToDepth(fNDotV) * sqr(saturatef(1.0-fShadowRelHeight.x));
   float  ldepth     = cosAngleToDepth(fNDotL+fAtmosphereAbsorptionOffset*6.0) * sqr(saturatef(1.0-fShadowRelHeight.x));
   float  alpha      = cosAngleToAlpha(saturatef(fNDotV * 0.95 - 0.05));
   
   vec3 lvabsorption = pow(fAtmosphereAbsorptionColor.rgb,vec3(fAtmosphereAbsorptionColor.a*(ldepth+vdepth*2.0)));
   
   vec4 rv;
   rv.rgb = regamma( amb + dif.rgb*lvabsorption
                  + atmosphereLighting(fNDotL)
                    *reyleigh(fNDotV, fVDotL, ldepth*alpha, atmo, 0.2) );
   rv.a = saturatef(dif.a) * alpha;
   return rv;
}

vec3 ambientMapping( in vec3 direction )
{
   return degamma_env(textureCubeLod(envMap, direction, 8.0)).rgb;
}


void main()
{    
   vec2 CloudCoord = inCloudCoord.xy;
   vec2 GroundCoord = inGroundCoord.xy;
   vec2 ShadowCoord = inShadowCoord.xy;
   vec2 NoiseCoord = inNoiseCoord.xy;

   vec3 L = normalize(varTSLight);
   vec3 V = normalize(varTSView);
   vec3 N = varWSNormal;
   
   float  fNDotL           = saturatef( L.z ); 
   float  fNDotV           = saturatef( V.z );
   float  fVDotL           = dot(L, V);

   // Drift noise
   vec4 cnoise       = texture2D(noiseMap_20,NoiseCoord);
   vec4 hcnoise      = texture2D(noiseMap_20,NoiseCoord*7.0);
   vec3 noise        = /*hcnoise.xyz * vec3(0.025,0.025,0.20)
                     + */cnoise.xyz * 0.25 
                     + cnoise.aaa * 0.75;
   vec3 fvDrift      = fvCloudLayerDrift.zzw*(noise - vec3(0.0,0.0,0.5)) + vec3(0.0,0.0,1.0);
   
   CloudCoord       += fvDrift.xy;
   GroundCoord      += fvDrift.xy;
   ShadowCoord      += fvDrift.xy;
   
   // Sample cloudmap
   vec2 gc1              =      CloudCoord                                         ;
   vec2 gc2              = lerp(CloudCoord,GroundCoord,0.25 * fCloudLayerThickness);
   vec2 gc3              = lerp(CloudCoord,GroundCoord,0.50 * fCloudLayerThickness);
   vec2 gc4              = lerp(CloudCoord,GroundCoord,0.75 * fCloudLayerThickness);
   vec2 gc5              = lerp(CloudCoord,GroundCoord,       fCloudLayerThickness);
   vec4 fvCloud1         = texture2D( cloudMap_20, gc1 );
   vec4 fvCloud2         = texture2D( cloudMap_20, gc2 );
   vec4 fvCloud3         = texture2D( cloudMap_20, gc3 );
   vec4 fvCloud4         = texture2D( cloudMap_20, gc4 );
   vec4 H;
   
   // Mask heights
   H                     = vec4(fvCloud1.a, fvCloud2.a, fvCloud3.a, fvCloud4.a);
   fvCloud1.a            = saturatef((fvCloud1.a*fvDrift.z-fvCloudLayers.x)*fvCloudLayerScales.x); // 0.5000 - 1.0000 (default)
   fvCloud2.a            = saturatef((fvCloud2.a*fvDrift.z-fvCloudLayers.y)*fvCloudLayerScales.y); // 0.2500 - 0.5000 (default)
   fvCloud3.a            = saturatef((fvCloud3.a*fvDrift.z-fvCloudLayers.z)*fvCloudLayerScales.z); // 0.1250 - 0.2500 (default)
   fvCloud4.a            = saturatef((fvCloud4.a*fvDrift.z-fvCloudLayers.w)*fvCloudLayerScales.w); // 0.0000 - 0.1250 (default)
   
   // Parallax - offset coords by relative displacement and resample
   #if (PARALLAX != 0)
   gc1                   = lerp(gc2,gc1,fvCloud1.a);
   gc2                   = lerp(gc3,gc2,fvCloud2.a);
   gc3                   = lerp(gc4,gc3,fvCloud3.a);
   gc4                   = lerp(gc5,gc4,fvCloud4.a);
   fvCloud1              = texture2D( cloudMap_20, gc1 );
   fvCloud2              = texture2D( cloudMap_20, gc2 );
   fvCloud3              = texture2D( cloudMap_20, gc3 );
   fvCloud4              = texture2D( cloudMap_20, gc4 );
   
   // Re-Mask heights
   H                     = vec4(fvCloud1.a, fvCloud2.a, fvCloud3.a, fvCloud4.a);
   fvCloud1.a            = saturatef((fvCloud1.a*fvDrift.z-fvCloudLayers.x)*fvCloudLayerScales.x); // 0.5000 - 1.0000 (default)
   fvCloud2.a            = saturatef((fvCloud2.a*fvDrift.z-fvCloudLayers.y)*fvCloudLayerScales.y); // 0.2500 - 0.5000 (default)
   fvCloud3.a            = saturatef((fvCloud3.a*fvDrift.z-fvCloudLayers.z)*fvCloudLayerScales.z); // 0.1250 - 0.2500 (default)
   fvCloud4.a            = saturatef((fvCloud4.a*fvDrift.z-fvCloudLayers.w)*fvCloudLayerScales.w); // 0.0000 - 0.1250 (default)
   #endif
   
   if (fvCloud4.a < 0.01) discard;
   
   // degamma cloud colors
   fvCloud1.rgb          = degamma_tex(fvCloud1.rgb);
   fvCloud2.rgb          = degamma_tex(fvCloud2.rgb);
   fvCloud3.rgb          = degamma_tex(fvCloud3.rgb);
   fvCloud4.rgb          = degamma_tex(fvCloud4.rgb);
   
   vec2 sc1              =      gc1;
   vec2 sc2              = lerp(gc2,ShadowCoord,0.10 * fCloudLayerThickness);
   vec2 sc3              = lerp(gc3,ShadowCoord,0.20 * fCloudLayerThickness);
   vec2 sc4              = lerp(gc4,ShadowCoord,0.50 * fCloudLayerThickness);
   vec4 scbias           = (vec4(1.0) - fvCloudLayers) * 3.0;
   
   /* Gradient sampling is just too expensive here... and not worth it
   float  fCloudShadow1  = textureGrad( cloudMap_20, sc1, dFdx(sc1)*scbias.w+1.5*(sc2-sc1), dFdy(sc1) * scbias.w).a;
   float  fCloudShadow2  = textureGrad( cloudMap_20, sc2, dFdx(sc2)*scbias.z+1.5*(sc2-sc1), dFdy(sc2) * scbias.z).a;
   float  fCloudShadow3  = textureGrad( cloudMap_20, sc3, dFdx(sc3)*scbias.y+1.5*(sc3-sc2), dFdy(sc3) * scbias.y).a;
   float  fCloudShadow4  = textureGrad( cloudMap_20, sc4, dFdx(sc4)*scbias.x+1.5*(sc4-sc3), dFdy(sc4) * scbias.x).a;
   */
   float  fCloudShadow1  = texture2D( cloudMap_20, sc1, scbias.w+0.5).a;
   float  fCloudShadow2  = texture2D( cloudMap_20, sc2, scbias.z+0.5).a;
   float  fCloudShadow3  = texture2D( cloudMap_20, sc3, scbias.y+0.5).a;
   float  fCloudShadow4  = texture2D( cloudMap_20, sc4, scbias.x+0.5).a;
   
   
   // Simplified for ps2.a
   const vec4 shadowStairs = vec4(0.000, 0.25, 0.50, 0.70);
   vec4 shadowStep1 = vec4(fvCloudLayers.x) + shadowStairs * vec4(1.0 - fvCloudLayers.x);
   vec4 shadowStep2 = vec4(fvCloudLayers.y) + shadowStairs * vec4(1.0 - fvCloudLayers.y);
   vec4 shadowStep3 = vec4(fvCloudLayers.z) + shadowStairs * vec4(1.0 - fvCloudLayers.z);
   vec4 shadowStep4 = vec4(fvCloudLayers.w) + shadowStairs * vec4(1.0 - fvCloudLayers.w);
   vec4 directSteps = vec4(H.x)             + shadowStairs * vec4(1.0 - H.x);
   vec4 fvCloudShadow    = vec4(fCloudShadow1,fCloudShadow2,fCloudShadow3,fCloudShadow4) * fvDrift.zzzz;
   fCloudShadow1         = dot(saturate(fvCloudShadow - shadowStep1), vec4(0.5));
   fCloudShadow2         = dot(saturate(fvCloudShadow - shadowStep2), vec4(0.5));
   fCloudShadow3         = dot(saturate(fvCloudShadow - shadowStep3), vec4(0.5));
   fCloudShadow4         = dot(saturate(fvCloudShadow - shadowStep4), vec4(0.5));
   fvCloudShadow         = vec4(fCloudShadow1,fCloudShadow2,fCloudShadow3,fCloudShadow4);
   fvCloudShadow        += vec4(dot(saturate(fvCloudShadow - directSteps), vec4(0.5)));
   
   // Attack angle density adjustment   
   vec2 CloudLayerDensitySVC;
   float  fCloudLayerDensityL = fCloudLayerDensity / (abs(L.z)+0.01);
   float  fCloudLayerDensityV = fCloudLayerDensity / (abs(V.z)+0.01);
   CloudLayerDensitySVC.x     = fCloudLayerDensityL * fCloudSelfShadowFactor;
   CloudLayerDensitySVC.y     = fCloudLayerDensityV;
  
   // Compute self-shadowed cloud color
   vec3 fvAmbient         = gl_Color.rgb * fvCloud1.rgb * ambientMapping(varWSNormal) * 0.5;
   vec4 fvBaseColor       = vec4(gl_Color.rgb * atmosphereLighting(fNDotL), gl_Color.a);
   vec3 fvCloud1s,fvCloud2s,fvCloud3s,fvCloud4s;
   vec4 fvCloud, fvCloudE;
   fvCloudShadow           = saturate(fvCloudShadow * CloudLayerDensitySVC.xxxx);
   fvCloud1s               = fvCloud1.rgb*lerp(vec3(1.0),fvCloudSelfShadowColor.rgb,fvCloudShadow.x);
   fvCloud2s               = fvCloud2.rgb*lerp(vec3(1.0),fvCloudSelfShadowColor.rgb,fvCloudShadow.y);
   fvCloud3s               = fvCloud3.rgb*lerp(vec3(1.0),fvCloudSelfShadowColor.rgb,fvCloudShadow.z);
   fvCloud4s               = fvCloud4.rgb*lerp(vec3(1.0),fvCloudSelfShadowColor.rgb,fvCloudShadow.w);
   fvCloud.a               = dot(fvCloudLayerMix,vec4(fvCloud1.a,fvCloud2.a,fvCloud3.a,fvCloud4.a));
   fvCloud.rgb             = fvCloud4s;
   fvCloud.rgb             = lerp(fvCloud.rgb,fvCloud3s,saturatef(fvCloud3.a*CloudLayerDensitySVC.y));
   fvCloud.rgb             = lerp(fvCloud.rgb,fvCloud2s,saturatef(fvCloud2.a*CloudLayerDensitySVC.y));
   fvCloud.rgb             = lerp(fvCloud.rgb,fvCloud1s,saturatef(fvCloud1.a*CloudLayerDensitySVC.y));
   fvCloud.rgb            *= fvBaseColor.rgb;

   gl_FragColor = atmosphericScatter( fvCloud1.rgb, fvAmbient, fvCloud, fNDotV, fNDotL, fVDotL );
}

