#!/usr/bin/env bash
# Recompile the ffz C engine to a single-file WASM ES module.
# Both algorithms (subsequence + edit-distance) are always compiled together.
# Output: src/ffz.mjs  (WASM inlined as base64, self-contained)
#
# After building, run `npm run build` to produce dist/ffuzzy.mjs.
# Requires Emscripten (source emsdk_env.sh, or set EMSDK).
set -euo pipefail

WASM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # wasm/
ROOT="$(cd "$WASM/.." && pwd)"                          # repo root
OPT="${OPT:--Oz}"

if ! command -v emcc >/dev/null 2>&1; then
  for env in "${EMSDK:-}/emsdk_env.sh" /c/sdk/emsdk/emsdk_env.sh \
             /d/sdk/emsdk/emsdk_env.sh ~/emsdk/emsdk_env.sh; do
    [ -f "$env" ] && { source "$env" >/dev/null 2>&1 || true; break; }
  done
  if ! command -v emcc >/dev/null 2>&1 && [ -d /c/sdk/emsdk/upstream/emscripten ]; then
    export PATH="/c/sdk/emsdk/python/3.13.3_64bit:/c/sdk/emsdk/upstream/emscripten:/c/sdk/emsdk/upstream/bin:/c/sdk/emsdk/node/22.16.0_64bit:$PATH"
  fi
fi
command -v emcc >/dev/null 2>&1 || { echo "error: emcc not found; source emsdk_env.sh" >&2; exit 1; }
echo "Using $(emcc --version | head -1)"

# All FFI symbols except the crash handler (not available in WASM).
# Scoped to `FFZ_API` definition lines so comments (e.g. "ffz_ffi_results_*")
# can't leak a truncated, nonexistent symbol into the export list.
mapfile -t SYMS < <(grep '^FFZ_API' "$ROOT/ffi/ffz_ffi.c" \
                    | grep -oE 'ffz_ffi_[a-z_0-9]+' \
                    | grep -v 'install_crash_handler' | sort -u)
EXPORTS="_malloc,_free"
for s in "${SYMS[@]}"; do EXPORTS+=",_$s"; done
RUNTIME="ccall,cwrap,UTF8ToString,stringToUTF8,lengthBytesUTF8,getValue,setValue,HEAPU8,HEAP32,HEAPU32"

OUT="$WASM/src/ffz.mjs"

# Wipe stale non-.ts build output before recompiling — src/ should only ever
# hold the current ffz.mjs (this script's output) plus hand-written .ts.
find "$WASM/src" -type f ! -name '*.ts' -delete

echo "--- compiling → $OUT ($OPT) ---"
emcc $OPT \
  -std=c11 -DFFZ_NO_THREADS -I"$ROOT/include" \
  -sMODULARIZE=1 -sEXPORT_ES6=1 -sSINGLE_FILE=1 \
  -sENVIRONMENT=web,worker -sALLOW_MEMORY_GROWTH=1 -sFILESYSTEM=0 \
  -sEXPORTED_FUNCTIONS="$EXPORTS" -sEXPORTED_RUNTIME_METHODS="$RUNTIME" \
  -sEXPORT_NAME=ffuzzyModule \
  "$ROOT"/src/ffz_alloc.c "$ROOT"/src/ffz_chars.c "$ROOT"/src/ffz_class_table.c \
  "$ROOT"/src/ffz_corpus.c "$ROOT"/src/ffz_edit.c \
  "$ROOT"/src/ffz_fuzzy.c "$ROOT"/src/ffz_match.c "$ROOT"/src/ffz_pattern.c \
  "$ROOT"/src/ffz_prefilter.c "$ROOT"/src/ffz_score.c \
  "$ROOT"/src/ffz_string.c "$ROOT"/src/ffz_unicode_tables.c \
  "$ROOT/ffi/ffz_ffi.c" \
  -o "$OUT"

ls -lh "$OUT"
echo "done. Run: npm run build"
