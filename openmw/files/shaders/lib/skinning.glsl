#ifndef LIB_SKINNING
#define LIB_SKINNING

// GPU linear-blend skinning (Emscripten / GLES only). On desktop, RigGeometry transforms skinned
// vertices on the CPU and this file compiles to nothing. On the web the CPU leaves the vertices in
// bind pose and the skinning happens here.
//
// The per-instance bone matrix palette is uploaded as an RGBA32F texture (see
// components/sceneutil/riggeometry.cpp): texture row `bone` holds that bone's osg::Matrixf as its 4
// rows, one per RGBA texel. Reconstructing mat4(row0,row1,row2,row3) yields a matrix M for which
// GLSL `M * v` reproduces osg::Matrixf::preMult(v) — exactly the math the CPU rig path uses (the
// row-major/column-major transpose cancels). Weights are normalised at setup so the blend of affine
// bone matrices stays affine.

#if @useGLES
uniform bool useSkinning;
uniform sampler2D boneMatrixTex;
layout(location = 6) in vec4 aBoneIndex;
layout(location = 7) in vec4 aBoneWeight;

mat4 readBoneMatrix(int bone)
{
    return mat4(
        texelFetch(boneMatrixTex, ivec2(0, bone), 0),
        texelFetch(boneMatrixTex, ivec2(1, bone), 0),
        texelFetch(boneMatrixTex, ivec2(2, bone), 0),
        texelFetch(boneMatrixTex, ivec2(3, bone), 0));
}

mat4 skinMatrix()
{
    mat4 m = aBoneWeight.x * readBoneMatrix(int(aBoneIndex.x));
    m += aBoneWeight.y * readBoneMatrix(int(aBoneIndex.y));
    m += aBoneWeight.z * readBoneMatrix(int(aBoneIndex.z));
    m += aBoneWeight.w * readBoneMatrix(int(aBoneIndex.w));
    return m;
}

// True only for vertices that actually have (normalised) influences. Guards against collapsing
// unweighted vertices to the origin — including the degenerate case where the bone attributes
// failed to bind (weights read 0), which then degrades to bind pose rather than an invisible mesh.
bool hasSkin()
{
    return (aBoneWeight.x + aBoneWeight.y + aBoneWeight.z + aBoneWeight.w) > 0.0001;
}
#endif

#endif
