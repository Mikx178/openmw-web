#ifndef OPENMW_COMPONENTS_NIFOSG_RIGGEOMETRY_H
#define OPENMW_COMPONENTS_NIFOSG_RIGGEOMETRY_H

#include <osg/Geometry>
#include <osg/Image>
#include <osg/Matrixf>
#include <osg/Texture2D>

#include <string_view>

namespace SceneUtil
{
    class Skeleton;
    class Bone;

    // TODO: This class has a lot of issues.
    // - We require too many workarounds to ensure safety.
    // - mSourceGeometry should be const, but can not be const because of a use case in shadervisitor.cpp.
    // - We create useless mGeometry clones in template RigGeometries.
    // - We do not support compileGLObjects.
    // - We duplicate some code in MorphGeometry.

    /// @brief Mesh skinning implementation.
    /// @note A RigGeometry may be attached directly to a Skeleton, or somewhere below a Skeleton.
    /// Note though that the RigGeometry ignores any transforms below the Skeleton, so the attachment point is not that
    /// important.
    /// @note The internal Geometry used for rendering is double buffered, this allows updates to be done in a thread
    /// safe way while not compromising rendering performance. This is crucial when using osg's default threading model
    /// of DrawThreadPerContext.
    class RigGeometry : public osg::Drawable
    {
    public:
        RigGeometry();
        RigGeometry(const RigGeometry& copy, const osg::CopyOp& copyop);

        META_Object(SceneUtil, RigGeometry)

        // Global texture unit for the GPU-skinning bone matrix palette texture (Emscripten only),
        // assigned once at startup by RenderingManager. -1 = GPU skinning disabled (CPU path).
        static int sBoneMatrixTextureUnit;

        // Currently empty as this is difficult to implement. Technically we would need to compile both internal
        // geometries in separate frames but this method is only called once. Alternatively we could compile just the
        // static parts of the model.
        void compileGLObjects(osg::RenderInfo& renderInfo) const override {}

        struct BoneInfo
        {
            std::string mName;
            osg::BoundingSpheref mBoundSphere;
            osg::Matrixf mInvBindMatrix;
        };

        using BoneWeight = std::pair<size_t, float>;
        using BoneWeights = std::vector<BoneWeight>;

        void setBoneInfo(std::vector<BoneInfo>&& bones);
        // Convert influences in bone and weight list per vertex format
        void setInfluences(const std::vector<BoneWeights>& influences);

        /// Initialize this geometry from the source geometry.
        /// @note The source geometry will not be modified.
        void setSourceGeometry(osg::ref_ptr<osg::Geometry> sourceGeom);

        void setTransform(osg::Matrixf&& transform);

        void setRootBone(std::string_view name);

        osg::ref_ptr<osg::Geometry> getSourceGeometry() const;

        void accept(osg::NodeVisitor& nv) override;
        bool supports(const osg::PrimitiveFunctor&) const override { return true; }
        void accept(osg::PrimitiveFunctor&) const override;

        struct CopyBoundingBoxCallback : osg::Drawable::ComputeBoundingBoxCallback
        {
            osg::BoundingBox boundingBox;

            osg::BoundingBox computeBound(const osg::Drawable&) const override { return boundingBox; }
        };

        struct CopyBoundingSphereCallback : osg::Node::ComputeBoundingSphereCallback
        {
            osg::BoundingSphere boundingSphere;

            osg::BoundingSphere computeBound(const osg::Node&) const override { return boundingSphere; }
        };

    private:
        void cull(osg::NodeVisitor* nv);
        void updateBounds(osg::NodeVisitor* nv);

        osg::ref_ptr<osg::Geometry> mGeometry[2];
        osg::Geometry* getGeometry(unsigned int frame) const;

        osg::ref_ptr<osg::Geometry> mSourceGeometry;
        osg::ref_ptr<const osg::Vec4Array> mSourceTangents;
        Skeleton* mSkeleton{ nullptr };

        osg::ref_ptr<osg::RefMatrix> mSkinToSkelMatrix;

        using VertexList = std::vector<unsigned short>;
        struct InfluenceData : public osg::Referenced
        {
            std::vector<BoneInfo> mBones;
            std::vector<std::pair<BoneWeights, VertexList>> mInfluences;
            osg::Matrixf mTransform;
            std::string mRootBone;
            // GPU skinning per-vertex attributes (Emscripten): up to 4 (bone index, weight) per
            // vertex. Built once on the template and shared with all clones via mData.
            osg::ref_ptr<osg::Vec4Array> mBoneIndices;
            osg::ref_ptr<osg::Vec4Array> mBoneWeights;
        };
        osg::ref_ptr<InfluenceData> mData;
        std::vector<Bone*> mNodes;

        // GPU skinning (Emscripten): per-instance bone matrix palette uploaded as an RGBA32F texture
        // (width 4 = the 4 matrix rows, height = bone count) and re-written each frame in cull().
        bool mGpuSkinning{ false };
        osg::ref_ptr<osg::Texture2D> mBoneMatrixTexture;
        osg::ref_ptr<osg::Image> mBoneMatrixImage;
        void setupGpuSkinning();

        unsigned int mLastFrameNumber{ 0 };
        bool mBoundsFirstFrame{ true };

        bool initFromParentSkeleton(osg::NodeVisitor* nv);

        void updateSkinToSkelMatrix(const osg::NodePath& nodePath);
    };

}

#endif
