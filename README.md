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
| `play/` | Browser front-end: `index.html`, `openmw.js` loader, `server.py` dev server |
| `fsroot/` | Virtual filesystem config + test game data mounted into the WASM runtime |

### Not included (kept local)

- `source-mw/`, `archive/`, `content/`, `fsroot/gamedata/`, `play/mwdata/` — copyrighted Morrowind game data
- `deps/` — cross-compiled dependency stack and its source tarballs (boost, bullet3, OSG, MyGUI, SDL2, …)
- `build-wasm/` and all `*.wasm` / `*.data` build outputs

## Building

Requires **Emscripten** (built against 6.0.1), **CMake**, and **Ninja**, plus the
cross-compiled dependency stack under `deps/wasm` (not in this repo).

```bash
# 1. Configure (paths in the script are absolute — adjust ROOT for your machine)
./configure-openmw.sh

# 2. Build
ninja -C build-wasm

# 3. Stage the outputs into play/ (openmw.js, openmw.wasm, openmw.data)
```

> Note: `configure-openmw.sh` currently hard-codes `ROOT=/Users/mstavridis/Downloads/CS-Web`
> and Homebrew Emscripten paths. Update these for a different environment.

## Running

The runtime needs SharedArrayBuffer, so it must be served with cross-origin
isolation headers. `play/server.py` sets them (COOP/COEP):

```bash
cd play
python3 server.py        # serves on http://localhost:8795 (override with PORT=...)
```

Then open the printed URL in a browser that supports WebAssembly threads.

## License

Engine code inherits OpenMW's **GPLv3**. Morrowind game data is **not** included and
is not covered by this repository — you must supply your own legally-obtained copy.
