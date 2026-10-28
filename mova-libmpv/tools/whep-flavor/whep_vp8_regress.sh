#!/usr/bin/env bash
# Offline VP8 tests / 参数：已 configure/build 的 ffmpeg 目录；无需网络或推流服务。
# Optional FF_BASELINE_SOURCE + FF_BASELINE_BUILD compare the original offer byte-for-byte.
# Uses the real patched whep.c with static archives and section GC.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$(realpath "${1:?usage: whep_vp8_regress.sh <ffmpeg-build-dir> [output-dir]}")"
OUT="${2:-$BUILD/vp8-tests}"
mkdir -p "$OUT/guard"
compile_test() {
  local build="$1" source="$2" target="$3"; shift 3
  cc -std=c17 -D_GNU_SOURCE -DHAVE_AV_CONFIG_H -O1 -g -Wall -Wno-pointer-sign \
    -ffunction-sections -fdata-sections "$@" -I"$build" -I"$source" \
    "$HERE/whep_vp8_test.c" -Wl,--gc-sections \
    -L"$build/libavformat" -L"$build/libavcodec" -L"$build/libswresample" -L"$build/libavutil" \
    -lavformat -lavcodec -lswresample -lavutil $(pkg-config --libs --static openssl dav1d zlib) \
    -lm -lpthread -o "$target"
}
compile_test "$BUILD" "${FF_SOURCE:-$BUILD}" "$OUT/test-vp8"
"$OUT/test-vp8" "$OUT/offer.sdp"
# Compile the actual new source with both VP8 decoder guards off / 模拟 Apple 配置。
cat > "$OUT/guard/config_components.h" <<EOF
#include "$BUILD/config_components.h"
#undef CONFIG_VP8_DECODER
#undef CONFIG_VP8_MEDIACODEC_DECODER
#define CONFIG_VP8_DECODER 0
#define CONFIG_VP8_MEDIACODEC_DECODER 0
EOF
compile_test "$BUILD" "${FF_SOURCE:-$BUILD}" "$OUT/test-no-vp8" -I"$OUT/guard"
"$OUT/test-no-vp8" "$OUT/offer-no-vp8.sdp"
mkdir -p "$OUT/mediacodec-guard"
sed 's/#define CONFIG_VP8_MEDIACODEC_DECODER 0/#define CONFIG_VP8_MEDIACODEC_DECODER 1/' \
  "$OUT/guard/config_components.h" > "$OUT/mediacodec-guard/config_components.h"
compile_test "$BUILD" "${FF_SOURCE:-$BUILD}" "$OUT/test-mediacodec-guard" -I"$OUT/mediacodec-guard"
"$OUT/test-mediacodec-guard" "$OUT/offer-mediacodec.sdp"
cmp "$OUT/offer.sdp" "$OUT/offer-mediacodec.sdp"
echo "PASS MediaCodec-only VP8 guard advertises the same VP8 offer"
if [ -n "${FF_BASELINE_BUILD:-}" ]; then
  compile_test "$FF_BASELINE_BUILD" "${FF_BASELINE_SOURCE:?}" "$OUT/test-baseline"
  "$OUT/test-baseline" "$OUT/offer-baseline.sdp"
  cmp "$OUT/offer-baseline.sdp" "$OUT/offer-no-vp8.sdp"
  echo "PASS no-VP8 offer is byte-identical to baseline"
fi
