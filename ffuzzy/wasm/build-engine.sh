#!/usr/bin/env bash
# Recompile the ffz C engine to a single-file WASM ES module.
#
# Engine variants (src/):
#   ffz-fzf.mjs    — subsequence only (default)
#   ffz-approx.mjs — edit-distance only  (FFZ_SUBSEQUENCE=0 FFZ_EDIT_DISTANCE=1)
#   ffz-full.mjs   — both algorithms     (FFZ_EDIT_DISTANCE=1)
#
# After building, run `npm run build` to produce matching dist/ bundles.
#
# Requires Emscripten (source emsdk_env.sh, or set EMSDK).
# Optional: set WASM_OPT=1 to run wasm-opt -O4 for extra ~5-10% savings.
set -euo pipefail

WASM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # wasm/
ROOT="$(cd "$WASM/.." && pwd)"                          # repo root
OPT="${OPT:--Oz}"
EDIT_FLAG="${FFZ_EDIT_DISTANCE:+"-DFFZ_EDIT_DISTANCE"}"
SEQ="${FFZ_SUBSEQUENCE:-1}"
SEQ_FLAG="${SEQ:+"-DFFZ_SUBSEQUENCE"}"
[ "$SEQ" = "0" ] && SEQ_FLAG=""

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

# Exclude crash handler + symbols not compiled for this variant.
EXCL="install_crash_handler"
[ -z "${FFZ_EDIT_DISTANCE:-}" ] && EXCL="${EXCL}|filter_edit"
[ "$SEQ" = "0" ] && EXCL="${EXCL}|filter_ex|filter_raws|ffi_filter$"
mapfile -t SYMS < <(grep -oE 'ffz_ffi_[a-z_0-9]+' "$ROOT/ffi/ffz_ffi.c" \
                    | grep -vE "$EXCL" | sort -u)
EXPORTS="_malloc,_free"
for s in "${SYMS[@]}"; do EXPORTS+=",_$s"; done
RUNTIME="ccall,cwrap,UTF8ToString,stringToUTF8,lengthBytesUTF8,getValue,setValue"

# Output file name: ffz-fzf / ffz-approx / ffz-full
if [ "$SEQ" = "0" ] && [ -n "${FFZ_EDIT_DISTANCE:-}" ]; then
  VARIANT="approx"
elif [ -n "${FFZ_EDIT_DISTANCE:-}" ]; then
  VARIANT="full"
else
  VARIANT="fzf"
fi
OUT="$WASM/src/ffz-${VARIANT}.mjs"

echo "--- compiling → $OUT ($OPT) [variant: $VARIANT] ---"
emcc $OPT \
  -std=c11 -DFFZ_NO_THREADS ${SEQ_FLAG} ${EDIT_FLAG} -I"$ROOT/include" \
  -sMODULARIZE=1 -sEXPORT_ES6=1 -sSINGLE_FILE=1 \
  -sENVIRONMENT=web,worker -sALLOW_MEMORY_GROWTH=1 -sFILESYSTEM=0 \
  -sEXPORTED_FUNCTIONS="$EXPORTS" -sEXPORTED_RUNTIME_METHODS="$RUNTIME" \
  -sEXPORT_NAME=ffuzzyModule \
  "$ROOT"/src/ffz_alloc.c "$ROOT"/src/ffz_chars.c "$ROOT"/src/ffz_class_table.c \
  "$ROOT"/src/ffz_corpus.c "$ROOT"/src/ffz_string.c "$ROOT"/src/ffz_unicode_tables.c \
  ${SEQ:+$([ "$SEQ" != "0" ] && echo \
    "$ROOT/src/ffz_fuzzy.c $ROOT/src/ffz_match.c $ROOT/src/ffz_pattern.c $ROOT/src/ffz_prefilter.c $ROOT/src/ffz_score.c")} \
  ${FFZ_EDIT_DISTANCE:+"$ROOT/src/ffz_edit.c"} \
  "$ROOT/ffi/ffz_ffi.c" \
  -o "$OUT"

# Optional wasm-opt post-processing (WASM_OPT=1 to enable).
# With -sSINGLE_FILE the WASM is base64-inlined; wasm-opt needs a temp file.
if [ "${WASM_OPT:-0}" = "1" ]; then
  WASM_OPT_BIN="${WASM_OPT_BIN:-$(dirname "$(command -v emcc)")/wasm-opt}"
  if command -v "$WASM_OPT_BIN" >/dev/null 2>&1; then
    echo "--- wasm-opt pass ---"
    TMP_WASM="$(mktemp).wasm"
    TMP_MJS="$(mktemp).mjs"
    # Extract base64 WASM, optimize, re-embed
    node - "$OUT" "$TMP_WASM" "$TMP_MJS" "$WASM_OPT_BIN" <<'EOF'
const [,, src, tmpWasm, tmpMjs, optBin] = process.argv;
const { execFileSync } = require('child_process');
const fs = require('fs');
const text = fs.readFileSync(src, 'utf8');
const m = text.match(/base64,([A-Za-z0-9+/=]+)/);
if (!m) { process.exit(0); }
fs.writeFileSync(tmpWasm, Buffer.from(m[1], 'base64'));
execFileSync(optBin, ['-O4', '--strip-debug', tmpWasm, '-o', tmpWasm]);
const opt = fs.readFileSync(tmpWasm).toString('base64');
fs.writeFileSync(tmpMjs, text.replace(m[1], opt));
EOF
    if [ -s "$TMP_MJS" ]; then
      mv "$TMP_MJS" "$OUT"
      echo "wasm-opt applied"
    fi
    rm -f "$TMP_WASM" "$TMP_MJS" 2>/dev/null || true
  else
    echo "wasm-opt not found, skipping (set WASM_OPT_BIN= to specify path)"
  fi
fi

ls -lh "$OUT"
echo "done. Run: npm run build"
