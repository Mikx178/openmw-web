# =============================================================================================
# Per-push deploy image for morrowind.virtastic.app.
#  - builder stage: incremental OpenMW→WASM build (fast, FROM the prebaked openmw-builder image).
#  - runtime stage: caddy:alpine serving the web root with the app's serving contract.
# Built + tagged `morrowind:ovh` by .github/workflows/deploy-ovh.yml on the Virtastic self-hosted runner.
# =============================================================================================

# ---- builder ---------------------------------------------------------------------------------
FROM openmw-builder:1 AS builder
ENV ROOT=/build EM_LIBEXEC=/emsdk/upstream/emscripten
WORKDIR /build

# Engine source + build recipe (deps/ already baked into openmw-builder).
COPY openmw            /build/openmw
COPY fsroot            /build/fsroot
COPY wasm-build        /build/wasm-build
COPY configure-openmw.sh /build/configure-openmw.sh
COPY play/index.html play/launcher.html play/streamfs.js /build/play/

# configure → incremental compile → out-of-band link (emits openmw.{js,wasm,data}, preloads fsroot@/)
# → brotli siblings. Mirrors the local build (configure-openmw.sh + wasm-build/{link-openmw.sh,make_br.sh}).
RUN bash configure-openmw.sh \
 && ninja -C build-wasm components openmw-lib \
 && bash wasm-build/link-openmw.sh \
 && cp build-wasm/openmw.js build-wasm/openmw.wasm build-wasm/openmw.data play/ \
 && bash wasm-build/make_br.sh

# ---- runtime ---------------------------------------------------------------------------------
FROM caddy:2-alpine AS runtime
# Web root: the built engine artifacts (raw + .br — both needed; Range uses raw, full GET uses .br)
# plus the tracked HTML/JS. The demo dataset is mounted at /srv/data by docker-compose.prod.yml.
COPY --from=builder /build/play/index.html    /srv/index.html
COPY --from=builder /build/play/launcher.html /srv/launcher.html
COPY --from=builder /build/play/streamfs.js   /srv/streamfs.js
COPY --from=builder /build/play/openmw.js      /build/play/openmw.js.br      /srv/
COPY --from=builder /build/play/openmw.wasm    /build/play/openmw.wasm.br    /srv/
COPY --from=builder /build/play/openmw.data    /build/play/openmw.data.br    /srv/

COPY deploy/Caddyfile /etc/caddy/Caddyfile
EXPOSE 8080
