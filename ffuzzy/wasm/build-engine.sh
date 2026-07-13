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
# can't leak a truncated, nonexistent symbol into the export list. Joins a
# FFZ_API line to what follows until a "(" is seen, so a declaration split
# across lines (e.g. `FFZ_API\nffz_results *ffz_ffi_x(...)`) is still caught.
#
# 所有 FFI 符号（崩溃处理器除外，WASM 下不可用）。
# 只扫描 `FFZ_API` 定义行，避免注释（如 "ffz_ffi_results_*"）泄漏出截断的假符号。
# 遇到 FFZ_API 后持续拼接后续行直到出现"("，因此跨行声明
#（如 `FFZ_API\nffz_results *ffz_ffi_x(...)`）也能正确识别。
mapfile -t SYMS < <(awk '
  /^FFZ_API/ { buf=$0; while (buf !~ /\(/) { getline nl; buf = buf " " nl } print buf; next }
' "$ROOT/ffi/ffz_ffi.c" \
                    | grep -oE 'ffz_ffi_[a-z_0-9]+' \
                    | grep -v 'install_crash_handler' | sort -u)
EXPORTS="_malloc,_free"
for s in "${SYMS[@]}"; do EXPORTS+=",_$s"; done
RUNTIME="ccall,cwrap,UTF8ToString,stringToUTF8,lengthBytesUTF8,getValue,setValue,HEAPU8,HEAP32,HEAPU32"

# Sanity check: every Emscripten HEAP* view the TS wrapper touches must be in
# RUNTIME, or it's `undefined` on the Module object at runtime with no build
# error (this is exactly the bug HEAPU8/HEAP32/HEAPU32 above were added for).
#
# 保护性检查：TS 胶水代码里用到的每个 Emscripten HEAP* 视图都必须出现在
# RUNTIME 里，否则运行时 Module 对象上是 undefined 且构建期不会报错
#（上面补的 HEAPU8/HEAP32/HEAPU32 就是在修这个类型的问题）。
for prop in $(grep -oE '\bM\.HEAP[A-Z0-9_]+' "$WASM/src/ffuzzy-corpus.ts" 2>/dev/null \
              | sed 's/^M\.//' | sort -u); do
  case ",$RUNTIME," in
    *",$prop,"*) ;;
    *) echo "warning: ffuzzy-corpus.ts uses Module.$prop but RUNTIME does not export it" >&2 ;;
  esac
done

OUT="$WASM/src/ffz.mjs"

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

# Only wipe stale non-.ts leftovers (old build variants, etc.) once the fresh
# $OUT above has already compiled successfully — never delete the tracked
# output before a new one is known-good, or a failed build leaves the repo
# with no ffz.mjs at all until the next successful run.
#
# 只在上面的新 $OUT 已编译成功后，才清理非 .ts 的过期残留（旧构建变体等）——
# 绝不能在新产物就绪前删掉已跟踪的旧产物，否则一次失败的构建会让仓库里
# 彻底没有 ffz.mjs，直到下次构建成功为止。
find "$WASM/src" -type f ! -name '*.ts' ! -name "$(basename "$OUT")" -delete

ls -lh "$OUT"
echo "done. Run: npm run build"
