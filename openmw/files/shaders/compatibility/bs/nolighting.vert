#version 120

#if @useGPUShader4
    #extension GL_EXT_gpu_shader4: require
#endif

#include "lib/core/vertex.h.glsl"

#if @diffuseMap
varying vec2 diffuseMapUV;
#endif

varying vec3 passNormal;
varying vec3 passViewPos;
varying float euclideanDepth;
varying float linearDepth;
varying float passFalloff;
#if @useGLES
varying float passClipDist; // water reflection/refraction clip (see objects.vert)
uniform vec4 clipPlane;
uniform mat4 osg_ViewMatrixInverse;
#endif

uniform bool useFalloff;
uniform vec4 falloffParams;

#include "lib/view/depth.glsl"

#include "compatibility/vertexcolors.glsl"
#include "compatibility/shadows_vertex.glsl"
#include "lib/skinning.glsl"

void main(void)
{
    vec4 skinnedVertex = gl_Vertex;
    vec3 skinnedNormal = gl_Normal.xyz;
#if @useGLES
    if (useSkinning && hasSkin())
    {
        mat4 skinMat = skinMatrix();
        skinnedVertex = skinMat * gl_Vertex;
        skinnedNormal = mat3(skinMat) * gl_Normal.xyz;
    }
#endif

    gl_Position = modelToClip(skinnedVertex);

    vec4 viewPos = modelToView(skinnedVertex);
#if @useGLES
    passClipDist = dot((osg_ViewMatrixInverse * viewPos).xyz, clipPlane.xyz) + clipPlane.w;
#else
    gl_ClipVertex = viewPos;
#endif
    euclideanDepth = length(viewPos.xyz);
    linearDepth = getLinearDepth(gl_Position.z, viewPos.z);

#if @diffuseMap
    diffuseMapUV = (gl_TextureMatrix[@diffuseMapUV] * gl_MultiTexCoord@diffuseMapUV).xy;
#endif

    passColor = gl_Color;
    passViewPos = viewPos.xyz;
    passNormal = skinnedNormal;

    if (useFalloff)
    {
        vec3 viewNormal = gl_NormalMatrix * normalize(skinnedNormal);
        vec3 viewDir = normalize(viewPos.xyz);
        float viewAngle = abs(dot(viewNormal, viewDir));
        passFalloff = smoothstep(falloffParams.x, falloffParams.y, viewAngle);

        float startOpacity = min(falloffParams.z, 1.0);
        float stopOpacity = max(falloffParams.w, 0.0);

        passFalloff = mix(startOpacity, stopOpacity, passFalloff);
    }
    else
    {
        passFalloff = 1.0;
    }

#if @shadows_enabled
    vec3 viewNormal = normalize(gl_NormalMatrix * passNormal);
    setupShadowCoords(viewPos, viewNormal);
#endif
}
