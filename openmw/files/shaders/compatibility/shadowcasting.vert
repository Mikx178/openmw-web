#version 120

varying vec2 diffuseMapUV;

varying float alphaPassthrough;

uniform int colorMode;
uniform bool useTreeAnim;
uniform bool useDiffuseMapForShadowAlpha = true;
uniform bool alphaTestShadows = true;

#include "lib/skinning.glsl"

void main(void)
{
    vec4 skinnedVertex = gl_Vertex;
#if @useGLES
    // Skin the shadow caster to match the skinned scene geometry, or character shadows detach.
    if (useSkinning && hasSkin())
        skinnedVertex = skinMatrix() * gl_Vertex;
#endif

    gl_Position = gl_ModelViewProjectionMatrix * skinnedVertex;

    vec4 viewPos = (gl_ModelViewMatrix * skinnedVertex);
    gl_ClipVertex = viewPos;

    if (useDiffuseMapForShadowAlpha)
        diffuseMapUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    else
        diffuseMapUV = vec2(0.0); // Avoid undefined behaviour if running on hardware predating the concept of dynamically uniform expressions
    if (colorMode == 2)
        alphaPassthrough = useTreeAnim ? 1.0 : gl_Color.a;
    else
        // This is uniform, so if it's too low, we might be able to put the position/clip vertex outside the view frustum and skip the fragment shader and rasteriser
        alphaPassthrough = gl_FrontMaterial.diffuse.a;
}
