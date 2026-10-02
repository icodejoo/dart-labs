#!/bin/bash -e
# 把 v0.41 构建链补丁套到「已打完 libmpv-android-video-build.patch」的上游 buildscripts 上。
# 用法：apply-v041.sh <build-root>     （build-root = 上游 libmpv-android-video-build 的检出目录）
# 作用：
#   1) git apply buildscripts-v041.patch（加 libplacebo、改 mpv.sh/freetype.sh）
#   2) 用 flavors-mova-slim-n9.sh 覆盖 scripts/ffmpeg.sh（取代默认的 flavors-mova-slim.sh）
#   3) 把 patches/mpv-v041/0001/0002 放进 buildscripts/patches/mpv/（取代上游的 javavm 补丁）
# 不改 depinfo.sh 里的 v_ffmpeg/v_mpv；这两个由调用方（CI 的 Override 步骤或本地脚本）覆盖成
# v_ffmpeg=9.0.2、mpv 指向 v0.41.0。
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOVA="$(cd "$HERE/../.." && pwd)"
ROOT="${1:?用法: apply-v041.sh <build-root>}"

git -C "$ROOT" apply "$HERE/buildscripts-v041.patch"
cp "$MOVA/flavors-mova-slim-n9.sh" "$ROOT/buildscripts/scripts/ffmpeg.sh"
# n6 专用的 ffmpeg 补丁（dash/hls）在 n9 上打不上；上游 javavm 补丁换成 v0.41 版
rm -rf "$ROOT/buildscripts/patches/ffmpeg" "$ROOT/buildscripts/patches/mpv/mpv_lavc_set_java_vm.patch"
mkdir -p "$ROOT/buildscripts/patches/mpv"
cp "$MOVA/patches/mpv-v041/0001-vo-drop-gpu-next.patch" "$MOVA/patches/mpv-v041/0002-client-lavc-set-java-vm.patch" "$ROOT/buildscripts/patches/mpv/"
echo "v041 补丁已应用到 $ROOT"
