#version 120

#if @useGPUShader4
    #extension GL_EXT_gpu_shader4: require
#endif

#define PER_PIXEL_LIGHTING 1

#include "lib/core/vertex.h.glsl"

#if @diffuseMap
varying vec2 diffuseMapUV;
#endif

#if @emissiveMap
varying vec2 emissiveMapUV;
#endif

#if @normalMap
varying vec2 normalMapUV;
varying vec4 passTangent;
#endif

varying float euclideanDepth;
varying float linearDepth;

varying vec3 passViewPos;
varying vec3 passNormal;
#if @useGLES
varying float passClipDist; // water reflection/refraction clip (see objects.vert)
uniform vec4 clipPlane;
uniform mat4 osg_ViewMatrixInverse;
#endif

#include "lib/view/depth.glsl"

#include "compatibility/vertexcolors.glsl"
#include "compatibility/shadows_vertex.glsl"
#include "compatibility/normals.glsl"
#include "lib/skinning.glsl"

void main(void)
{
#if @useGLES
    mat4 skinMat = mat4(1.0);
#endif
    vec4 skinnedVertex = gl_Vertex;
    vec3 skinnedNormal = gl_Normal.xyz;
#if @useGLES
    if (useSkinning && hasSkin())
    {
        skinMat = skinMatrix();
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
    passColor = gl_Color;
    passViewPos = viewPos.xyz;
    passNormal = skinnedNormal;
    normalToViewMatrix = gl_NormalMatrix;

#if @normalMap
    vec4 skinnedTangent = gl_MultiTexCoord7.xyzw;
#if @useGLES
    if (useSkinning && hasSkin())
        skinnedTangent.xyz = mat3(skinMat) * skinnedTangent.xyz;
#endif
    normalToViewMatrix *= generateTangentSpace(skinnedTangent, passNormal);
#endif

#if @diffuseMap
    diffuseMapUV = (gl_TextureMatrix[@diffuseMapUV] * gl_MultiTexCoord@diffuseMapUV).xy;
#endif

#if @emissiveMap
    emissiveMapUV = (gl_TextureMatrix[@emissiveMapUV] * gl_MultiTexCoord@emissiveMapUV).xy;
#endif

#if @normalMap
    normalMapUV = (gl_TextureMatrix[@normalMapUV] * gl_MultiTexCoord@normalMapUV).xy;
#endif


#if @shadows_enabled
    vec3 viewNormal = normalize(gl_NormalMatrix * passNormal);
    setupShadowCoords(viewPos, viewNormal);
#endif
}
