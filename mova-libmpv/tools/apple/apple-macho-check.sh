#!/bin/bash
# Apple 版 libmpv 二进制体检（在 macOS runner 上跑，要 otool/lipo/vtool/nm/strings）。
# 用法：apple-macho-check.sh <dylib> <platform> <archs> [id]
#   platform  macos | ios | iossimulator
#   archs     期望的架构集合，空格分隔且按字母序，如 "arm64" 或 "arm64 x86_64"
#   id        期望的 install name；缺省不检查（Nix 出来的是 @rpath/libmpv.dylib，重写后应为 @rpath/Mpv.framework/Mpv）
# 环境变量：
#   STRICT_EXPORTS=1  导出表里出现非 mpv_ 符号时判失败（缺省只告警）
#   VERSION_CHECK=1   检查版本串与 WHEP 字串（缺省开启；对 strip 过的二进制同样有效，字符串不会被 strip）
# 退出码：0 通过；非 0 有硬失败。
set -u
LIB="${1:?dylib}"; PLAT="${2:?platform}"; WANT_ARCHS="${3:?archs}"; WANT_ID="${4:-}"
fail=0
bad() { echo "::error::$*"; fail=1; }
ok()  { echo "OK  $*"; }

case "$PLAT" in
  macos) VT_PLAT=MACOS; MIN_OK='10.15|11.0|12.0|13.0|14.0' ;;
  ios) VT_PLAT=IOS; MIN_OK='13.0' ;;
  iossimulator) VT_PLAT=IOSSIMULATOR; MIN_OK='13.0|14.0' ;;   # arm64 模拟器的硬件下限是 14.0，链接器会自动抬高
  *) echo "bad platform $PLAT"; exit 2 ;;
esac

# 1. 架构
GOT_ARCHS="$(lipo -archs "$LIB" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
[ "$GOT_ARCHS" = "$WANT_ARCHS" ] && ok "archs = $GOT_ARCHS" || bad "archs: got '$GOT_ARCHS' want '$WANT_ARCHS'"

for ARCH in $WANT_ARCHS; do
  echo "--- slice $ARCH ---"
  # 2. 依赖白名单：只允许系统库；第一行是自身 install name
  OT="$(otool -arch "$ARCH" -L "$LIB")"
  SELF="$(echo "$OT" | sed -n '2p' | awk '{print $1}')"
  echo "$OT" | sed -n '2,$p' | awk '{print "    " $1}'
  if [ -n "$WANT_ID" ]; then
    ID="$(otool -arch "$ARCH" -D "$LIB" | sed -n '2p')"
    [ "$ID" = "$WANT_ID" ] && ok "[$ARCH] install name = $ID" || bad "[$ARCH] install name '$ID' != '$WANT_ID'"
  fi
  while read -r dep; do
    [ -z "$dep" ] && continue
    case "$dep" in
      /System/Library/*|/usr/lib/*) ;;
      "$SELF") ;;                                   # 自身（旧 otool 会把 id 也列进依赖）
      *) bad "[$ARCH] 非系统依赖: $dep" ;;
    esac
  done < <(echo "$OT" | sed -n '3,$p' | awk '{print $1}')
  # 3. 平台与最低系统版本
  BUILD="$(vtool -arch "$ARCH" -show-build "$LIB")"
  P="$(echo "$BUILD" | awk '/platform/ {print $2; exit}')"
  M="$(echo "$BUILD" | awk '/minos/ {print $2; exit}')"
  echo "    platform=$P minos=$M"
  [ "$P" = "$VT_PLAT" ] && ok "[$ARCH] platform $P" || bad "[$ARCH] platform '$P' != $VT_PLAT"
  if [ "$PLAT" = macos ] && [ "$ARCH" = arm64 ]; then
    # arm64 的 macOS 切片最低只能是 11.0（硬件下限），10.15 的目标由 x86_64 切片承担
    [ "$M" = 11.0 ] && ok "[$ARCH] minos $M" || bad "[$ARCH] minos '$M' != 11.0"
  else
    echo "$M" | grep -Eq "^($MIN_OK)$" && ok "[$ARCH] minos $M" || bad "[$ARCH] minos '$M' 不在 ($MIN_OK)"
  fi
done

# 4. 导出表：mpv_* 必须在；其余符号数量报告
for sym in mpv_create mpv_initialize mpv_command mpv_command_async mpv_set_option mpv_observe_property \
           mpv_render_context_create mpv_render_context_render mpv_wait_event mpv_terminate_destroy mpv_create_weak_client; do
  nm -gU "$LIB" 2>/dev/null | grep -q " T _${sym}\$" && ok "export $sym" || bad "缺少导出符号 $sym"
done
OTHER="$(nm -gU "$LIB" 2>/dev/null | awk '$2 ~ /^[TDSBt]$/ {print $3}' | grep -v '^_mpv_' | grep -v '^__mh_dylib_header$' | sort -u || true)"
NOTHER="$(echo -n "$OTHER" | grep -c . || true)"
echo "非 mpv_ 导出符号: $NOTHER"
if [ "$NOTHER" -gt 0 ]; then
  echo "$OTHER" | head -20 | sed 's/^/    /'
  if [ "${STRICT_EXPORTS:-0}" = 1 ]; then bad "导出表混入 $NOTHER 个非 mpv_ 符号"; else echo "::warning::导出表混入 $NOTHER 个非 mpv_ 符号"; fi
fi

# 5. 版本串与功能字串
if [ "${VERSION_CHECK:-1}" = 1 ]; then
  STR="$(strings -a "$LIB")"
  grep -q 'n9\.0\.2' <<<"$STR" && ok "ffmpeg 版本串含 n9.0.2" || bad "未找到 ffmpeg n9.0.2 版本串"
  grep -Eq '(^|[^0-9])v?0\.41\.0' <<<"$STR" && ok "mpv 版本串含 0.41.0" || bad "未找到 mpv 0.41.0 版本串"
  grep -q 'whep' <<<"$STR" && ok "含 whep 字串" || bad "未找到 whep 字串（WHEP demuxer 未编入）"
  grep -q 'first_frame_timeout' <<<"$STR" && ok "含 first_frame_timeout 选项（ffmpeg-whep 0013）" || bad "未找到 first_frame_timeout（0013 未编入）"
  grep -q ' plc=' <<<"$STR" && ok "含 plc= 统计字串（ffmpeg-whep 0014）" || bad "未找到 plc= 统计字串（0014 未编入）"
  grep -qi 'dtls' <<<"$STR" && ok "含 dtls 字串" || bad "未找到 dtls 字串"
  grep -Eq 'mbedtls|mbed TLS' <<<"$STR" && ok "含 mbedtls 字串" || bad "未找到 mbedtls 字串"
  grep -q 'gpu-next' <<<"$STR" && bad "仍含 gpu-next（vo_gpu_next 补丁未生效）" || ok "无 gpu-next"
fi
ls -l "$LIB"
exit $fail
