# syntax=docker/dockerfile:1
# =============================================================================================
# Per-push deploy image for morrowind.virtastic.app.
#  - builder stage: incremental OpenMW→WASM build (fast, FROM the prebaked openmw-builder image).
#  - runtime stage: caddy:alpine serving the web root with the app's serving contract.
# Built + tagged `morrowind:ovh` by .github/workflows/deploy-ovh.yml on the Virtastic self-hosted runner.
# =============================================================================================

# ---- builder ---------------------------------------------------------------------------------
FROM openmw-builder:1 AS builder
# ROOT + EM_LIBEXEC drive configure-openmw.sh; EMSDK_BIN drives link-openmw.sh (emcc/em++ + sysroot).
ENV ROOT=/build EM_LIBEXEC=/emsdk/upstream/emscripten EMSDK_BIN=/emsdk/upstream/emscripten
WORKDIR /build

# Engine source + build recipe (deps/ already baked into openmw-builder).
COPY openmw            /build/openmw
COPY fsroot            /build/fsroot
COPY wasm-build        /build/wasm-build
COPY configure-openmw.sh /build/configure-openmw.sh
# NOTE: the static play/*.html + streamfs.js are copied in the RUNTIME stage (from context), NOT here
# — editing them must not invalidate this compile layer and trigger a full ~13-min recompile.

# configure → incremental compile → out-of-band link (emits openmw.{js,wasm,data}, preloads fsroot@/)
# → brotli siblings. Mirrors the local build (configure-openmw.sh + wasm-build/{link-openmw.sh,make_br.sh}).
# build-wasm is a cache mount so cmake configure + ninja objects persist across builds — a re-run
# (e.g. after a link tweak) is then incremental instead of a full ~13-min recompile.
RUN --mount=type=cache,target=/build/build-wasm \
    bash configure-openmw.sh \
 && ninja -C build-wasm components openmw-lib \
 && bash wasm-build/link-openmw.sh \
 && cp build-wasm/openmw.js build-wasm/openmw.wasm build-wasm/openmw.data play/ \
 && bash wasm-build/make_br.sh

# ---- runtime ---------------------------------------------------------------------------------
FROM caddy:2-alpine AS runtime
# Web root: the built engine artifacts (raw + .br — both needed; Range uses raw, full GET uses .br)
# plus the tracked HTML/JS. The demo dataset is mounted at /srv/data by docker-compose.prod.yml.
# Static web files straight from the build context (editing them = a fast runtime-only rebuild).
COPY play/index.html play/launcher.html play/streamfs.js /srv/
# Built engine artifacts from the builder stage (raw + .br).
COPY --from=builder /build/play/openmw.js      /build/play/openmw.js.br      /srv/
COPY --from=builder /build/play/openmw.wasm    /build/play/openmw.wasm.br    /srv/
COPY --from=builder /build/play/openmw.data    /build/play/openmw.data.br    /srv/

COPY deploy/Caddyfile /etc/caddy/Caddyfile
EXPOSE 8080
