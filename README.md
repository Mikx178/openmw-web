# openmw-wasm

[OpenMW](https://openmw.org/) (the open-source Morrowind engine) cross-compiled to
**WebAssembly** and run in the browser via Emscripten.

The `openmw/` tree is based on upstream
[`OpenMW/openmw`](https://github.com/OpenMW/openmw) at commit
`bc1d9c97a3881bb961a0b74e6e49bbba772b86a1` (recorded in
[`.openmw-base-commit.txt`](.openmw-base-commit.txt)) with local modifications for
the WASM target.

## What's in this repo

This is a **code-only** repo. Large binaries — game assets, dependency source
caches, and build artifacts — are intentionally excluded via
[`.gitignore`](.gitignore) and must be provided/rebuilt locally.

| Path | Purpose |
|------|---------|
| `openmw/` | OpenMW engine source (upstream + local WASM changes) |
| `configure-openmw.sh` | Emscripten/CMake configure step for the WASM build |
| `wasm-build/link-openmw.sh` | **Canonical final link step** (runtime flags + preload FS) |
| `wasm-build/build-osg.sh` | OpenSceneGraph→WASM configure/build (the hardest dep) |
| `wasm-build/x11_stubs.c` | Signature-exact X11 no-op stubs osgViewer links against |
| `wasm-build/patches/osg-emscripten.patch` | All OSG source fixes for WebGL2/emscripten |
| `play/` | Browser front-end: `index.html`, `openmw.js` loader, `server.py` dev server |
| `fsroot/` | Virtual filesystem config + test game data mounted into the WASM runtime |

### Not included (kept local)

- `source-mw/`, `archive/`, `content/`, `fsroot/gamedata/`, `play/mwdata/` — copyrighted Morrowind game data
- `deps/` — cross-compiled dependency stack and its source tarballs (boost, bullet3, OSG, MyGUI, SDL2, …)
- `build-wasm/` and all `*.wasm` / `*.data` build outputs

## Building

Requires **Emscripten 6.0.1** (Homebrew paths assumed; adjust `EMSDK_BIN`), **CMake**,
and **Ninja**, plus the cross-compiled dependency stack under `deps/wasm` (not in this
repo — see *Dependency stack* below).

```bash
export ROOT=$PWD                      # repo root

# 1. Configure (compiles fine from CMake; final LINK is done out-of-band in step 3)
./configure-openmw.sh

# 2. Compile everything
ninja -C build-wasm components openmw-lib

# 3. Link with the runtime flags (WebGL2, pthreads, preload FS, IDBFS...)
./wasm-build/link-openmw.sh

# 4. Deploy
cp build-wasm/openmw.js build-wasm/openmw.wasm build-wasm/openmw.data play/
```

Build gotchas (why the link is scripted, learned the hard way):

- `main.cpp.o` is passed directly on the link line; `ninja components openmw-lib`
  does **not** rebuild it (the script does).
- The whole stack uses `-fwasm-exceptions` (legacy wasm EH). Do **not** add `-flto`
  (wasm-ld crashes / miscompiles boot) or `-sWASM_LEGACY_EXCEPTIONS=0`.
- Hand-built deps must be compiled `-pthread`; ICU uses the sysroot `-mt` variants.
- Killing the link mid-run leaves a mismatched `openmw.js`/`openmw.wasm` pair —
  verify both mtimes match before deploying.

### Dependency stack

All deps are cross-compiled to static libs in `deps/wasm/lib` (+ headers in
`deps/wasm/include`): OSG 3.6.5, Bullet (double-precision), MyGUI, FFmpeg 5
(with `--enable-decoder=bink,binkaudio`), Boost (program_options+iostreams),
Lua 5.4, LZ4, RecastNavigation. SDL2/FreeType/HarfBuzz/png/jpeg/zlib/ogg/vorbis
come from emscripten ports at link time; OpenAL is emscripten's built-in.

OSG is the hardest one and is fully scripted: apply
`wasm-build/patches/osg-emscripten.patch` to an `OpenSceneGraph-3.6.5` checkout at
`deps/src/osg`, then run `./wasm-build/build-osg.sh`. The patch carries critical
fixes — most importantly the RTT `drawBuffers` fix in `FrameBufferObject.cpp`
(without it every render-to-texture camera silently discards its color output).

## Running

The runtime needs SharedArrayBuffer, so it must be served with cross-origin
isolation headers. `play/server.py` sets them (COOP/COEP) and also serves the
precompressed `.br` artifacts and range requests:

```bash
cd play
python3 server.py        # serves on http://localhost:8795 (override with PORT=...)
```

Then open the printed URL.

### Browser requirement

**Desktop Chrome / Chromium only.** The build relies on features that, in
practice, only desktop Chrome provides together reliably:

- **SharedArrayBuffer + WebAssembly threads** (the engine runs multi-threaded).
- **WebGL2 / GLES3** via ANGLE.
- **`EXT_clip_control`** for the reverse-Z depth buffer (Chrome-only).

Firefox and Safari are **not supported or tested** — several GLES workarounds are
gated specifically to Chrome's ANGLE behavior. Mobile / touch is out of scope
(no on-screen controls). Use a recent desktop Chrome or Chromium.

### Hosting on a real server

For production, serve `play/` over **HTTPS** (cross-origin isolation is only
granted on secure origins; `http://localhost` also counts) and set these headers
on **every** response so the page is cross-origin isolated:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

Because COEP is `require-corp`, every subresource must also be allowed — either
same-origin, or served with `Cross-Origin-Resource-Policy: cross-origin` (what
`server.py` does). Serve the precompressed siblings (`openmw.wasm.br`,
`openmw.js.br`) with `Content-Encoding: br` when the client accepts it — this
turns the ~42 MB wasm into ~11 MB over the wire.

nginx example:

```nginx
location /play/ {
    add_header Cross-Origin-Opener-Policy   same-origin   always;
    add_header Cross-Origin-Embedder-Policy require-corp   always;
    add_header Cross-Origin-Resource-Policy cross-origin   always;
    gzip_static on;   # or brotli_static on; to serve the .br siblings
    types { application/wasm wasm; }
}
```

On static hosts (Netlify, Cloudflare Pages, GitHub Pages via a proxy, …) set the
same three headers via the host's headers config (e.g. Netlify `_headers`). The
first load downloads ~800 MB of Morrowind assets **once** — they are cached in
the browser (Cache API + IDBFS), so subsequent loads are fast. The in-page HUD
shows live per-file download progress during that first load.

## License

Engine code inherits OpenMW's **GPLv3**. Morrowind game data is **not** included and
is not covered by this repository — you must supply your own legally-obtained copy.
