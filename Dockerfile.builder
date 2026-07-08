# =============================================================================================
# openmw-builder — one-time builder image. Bakes the emscripten toolchain + the FULL wasm dep stack
# COMPILED FROM SOURCE (wasm-build/build-deps.sh), so the per-push deploy build (Dockerfile) is just
# the fast incremental OpenMW compile+link, and the whole stack is reproducible from source — no
# dependency on any machine's prebuilt artifacts.
#
# BUILD IT ONCE, on the VPS, with the dep SOURCE present in the build context:
#   # rsync Mike's deps/src/ (gitignored source trees: osg, bullet3, recast, mygui, ffmpeg-6.1.2,
#   # boost_1_85_0, lua-5.4.7, lz4-1.10.0) into the repo checkout first, then:
#   docker build -t openmw-builder:1 -f Dockerfile.builder .
# Rebuild only when a dep version or the emscripten toolchain changes. (Expect a long first build —
# OSG + FFmpeg + Boost are the slow ones; that cost is paid once and cached in this image.)
#
# ### TODO before first build: pin the emscripten tag matching what the deps target (Mike: `emcc
#     --version`). Homebrew reported "6.0.1"; set the corresponding emscripten/emsdk tag below.
# =============================================================================================
FROM emscripten/emsdk:3.1.74
# ^ TODO: replace with the tag matching Mike's emscripten toolchain.

# Build tooling beyond what the emsdk image ships (node/python3/cmake are already present).
# autoconf/pkg-config for FFmpeg's configure; ninja for the cmake deps; brotli for make_br.sh later.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ninja-build brotli git rsync ca-certificates autoconf automake pkg-config \
 && rm -rf /var/lib/apt/lists/*

ENV ROOT=/build EM_LIBEXEC=/emsdk/upstream/emscripten
WORKDIR /build

# Dependency SOURCE + the build recipe. deps/src is gitignored (rsync'd into context).
COPY deps/src         /build/deps/src
COPY wasm-build       /build/wasm-build
COPY configure-openmw.sh /build/configure-openmw.sh

# Apply the OSG emscripten patch to the pristine OSG checkout (build-deps.sh -> build-osg.sh expects it),
# then compile the entire stack from source into /build/deps/wasm.
RUN git -C /build/deps/src/osg apply /build/wasm-build/patches/osg-emscripten.patch \
 && bash /build/wasm-build/build-deps.sh

# Sanity: toolchain + the staged stack.
RUN emcc --version && ls /build/deps/wasm/lib/*.a | wc -l
