#!/bin/bash
# Precompress the big compressible payloads for play/server.py's .br fast path.
# Run after every deploy (openmw.js/wasm/data change); the .esm files never change.
# Skips already-fresh .br files. Audio/video tars (mp3/bik) barely compress — skipped.
set -euo pipefail
ROOT="${ROOT:-/Users/mstavridis/Downloads/CS-Web}"
Q="${Q:-5}"  # quality: 5 is a good speed/ratio tradeoff for 100MB+ files

for f in "$ROOT"/play/openmw.js "$ROOT"/play/openmw.wasm "$ROOT"/play/openmw.data \
         "$ROOT"/play/mwdata/Morrowind.esm "$ROOT"/play/mwdata/Tribunal.esm \
         "$ROOT"/play/mwdata/Bloodmoon.esm "$ROOT"/play/mwdata/mwextra.tar; do
  [ -f "$f" ] || continue
  if [ -f "$f.br" ] && [ "$f.br" -nt "$f" ]; then
    echo "fresh: $f.br"
    continue
  fi
  echo "brotli -q $Q: $f"
  brotli -f -q "$Q" -o "$f.br" "$f"
done
ls -lh "$ROOT"/play/*.br "$ROOT"/play/mwdata/*.br 2>/dev/null | awk '{print $5, $9}'
