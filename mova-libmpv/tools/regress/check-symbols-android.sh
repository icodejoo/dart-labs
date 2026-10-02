#!/usr/bin/env bash
# Android 产物回归检查（四 ABI）。用法：check-symbols-android.sh [abi ...]
# 环境变量：LIBMPV_DIR 产物根目录；LLVM_NM 指定 nm；FFCONF_LOG 可选 configure 日志
# 判据来自 build-mova-libmpv.yml 的 android job "Strip and verify" 与 README"验证过关的"。
set -u
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

ABIS="${*:-arm64-v8a armeabi-v7a x86_64 x86}"

# 找 nm：优先 LLVM_NM，其次 NDK 里的 llvm-nm，最后系统 llvm-nm/nm（GNU nm 也能读各架构 ELF 的 dynsym）
find_nm() {
  [ -n "${LLVM_NM:-}" ] && { echo "$LLVM_NM"; return; }
  local n b
  for n in "${ANDROID_NDK_ROOT:-}" "${ANDROID_NDK_HOME:-}" /e/sdk/android/ndk/*; do
    [ -n "$n" ] || continue
    for b in "$n"/toolchains/llvm/prebuilt/*/bin/llvm-nm*; do [ -x "$b" ] && { echo "$b"; return; }; done
  done
  first_cmd llvm-nm nm
}
NM="$(find_nm)"
echo "nm 工具: ${NM:-未找到}"
if [ -z "$NM" ]; then bad "找不到 llvm-nm/nm"; finish; exit 1; fi

# 检查单个 ABI 的产物
check_abi() {
  local abi="$1" so syms strs d f
  so="$LIBMPV_DIR/$abi/libmpv.so"
  section "android $abi"
  [ -f "$so" ] || { bad "产物不存在: $so"; return; }
  is_lfs_pointer "$so" && { bad "是 LFS 指针不是真实文件，先 git lfs pull"; return; }
  ok "存在，$(size_of "$so") 字节"
  if head -c4 "$so" | grep -aq 'ELF'; then ok "ELF 头正确"; else bad "不是 ELF"; fi

  syms="$(mktemp)"; _TMPS+=("$syms")
  "$NM" -D --defined-only "$so" > "$syms" 2>/dev/null
  # 关键：只有 av_jni_set_java_vm 不够，必须有 mpv_lavc_set_java_vm（缺了 MediaCodec 静默回落软解）
  if has_sym "$syms" mpv_lavc_set_java_vm; then ok "mpv_lavc_set_java_vm 已导出"; else bad "mpv_lavc_set_java_vm 缺失（MediaCodec JavaVM 绑定失效）"; fi
  # dav1d 静态内嵌：dav1d_open 必须在；dav1d_* 总数记录下来（README 定稿记录 19 个）
  if has_sym "$syms" dav1d_open; then ok "dav1d_open 已导出（AV1 软解兜底在）"; else bad "dav1d_open 缺失（AV1 软解被静默丢弃）"; fi
  echo "  [INFO] dav1d_* 导出数: $(grep -c ' dav1d_' "$syms")（README 定稿记录 19）"
  check_public_api "$syms"

  strs="$(strs_file "$so")"
  # 四个 *_mediacodec 解码器：strip 后不在 dynsym，只能用解码器名字符串代理（CI 里这项也只是 warning）
  for d in h264 hevc vp9 av1; do
    if grep -axq "${d}_mediacodec" "$strs"; then ok "${d}_mediacodec 解码器名存在（字符串代理）"; else bad "${d}_mediacodec 解码器名缺失"; fi
  done
  if grep -axq libdav1d "$strs"; then ok "libdav1d 解码器名存在（需 --enable-libdav1d 与 --enable-decoder=libdav1d 同时开）"; else bad "libdav1d 解码器名缺失"; fi
  # VP8/MJPEG 解码器已裁：dynsym 里本来就没有，改用 ffmpeg 源文件路径断言串代理（字符串代理，非符号级证据）
  for f in vp8.c mjpegdec.c; do
    if grep -aq "libavcodec/$f" "$strs"; then bad "libavcodec/$f 仍在产物里（VP8/MJPEG 解码器未裁干净）"; else ok "libavcodec/$f 不在产物里（VP8/MJPEG 已裁，字符串代理）"; fi
  done
  check_protocols_strs "$strs" https tls rtmps tcp http
  check_license "$strs" "${FFCONF_LOG:-}"
}

for a in $ABIS; do check_abi "$a"; done
finish
