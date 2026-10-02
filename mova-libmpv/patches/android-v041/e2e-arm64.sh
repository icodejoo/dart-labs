#!/bin/bash -e
# 从零端到端构建 Android arm64 libmpv（v0.41 + ffmpeg n9.0.2，可选 WHEP），顺序对齐 CI workflow 的 android-arm64 job。
# 用法：WHEP=1 e2e-arm64.sh <新建的空工作目录> [NDK r25c 目录]
#   WHEP=1 带 WHEP 变体（默认不带）；JOBS 控制并行（默认 8）。
# 本机网络差异（仅本地需要，CI 不用）：videolan/gnome/freedesktop 的 git 源在 WSL 有 CA 问题，
# 用 git 的 url.insteadOf 重定向到 GitHub 镜像，不改脚本、不绕过证书校验。
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOVA="$(cd "$HERE/../.." && pwd)"
WORK="${1:?用法: e2e-arm64.sh <空工作目录> [NDK目录]}"
NDK_SRC="${2:-/root/w/mpvt/eval/ndk/android-ndk-r25c}"
NDK_VERSION=25.2.9519653
UPSTREAM_REF=1ecf510
export WHEP="${WHEP:-0}"

[ -e "$WORK/ws" ] && { echo "工作目录 $WORK/ws 已存在，要求干净状态" >&2; exit 1; }
mkdir -p "$WORK"

# GitHub 镜像重定向（环境变量方式，只影响本脚本及子进程）
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0="url.https://github.com/videolan/dav1d.git.insteadOf"
export GIT_CONFIG_VALUE_0="https://code.videolan.org/videolan/dav1d.git"
export GIT_CONFIG_KEY_1="url.https://github.com/GNOME/libxml2.git.insteadOf"
export GIT_CONFIG_VALUE_1="https://gitlab.gnome.org/GNOME/libxml2.git"
export GIT_CONFIG_KEY_2="url.https://github.com/freetype/freetype.git.insteadOf"
export GIT_CONFIG_VALUE_2="https://gitlab.freedesktop.org/freetype/freetype.git"

# 1) clone + 现有 mova 补丁 + flavor（与 workflow 同序）
git clone https://github.com/media-kit/libmpv-android-video-build "$WORK/ws"
git -C "$WORK/ws" checkout "$UPSTREAM_REF"
git -C "$WORK/ws" apply "$MOVA/libmpv-android-video-build.patch"
cp "$MOVA/flavors-mova-slim.sh" "$WORK/ws/buildscripts/scripts/ffmpeg.sh"

# 2) v0.41/n9（+WHEP）全部改动，全由脚本完成
"$HERE/apply-v041.sh" "$WORK/ws"

# 3) NDK r25c 放到 build.sh 期望的位置
BS="$WORK/ws/buildscripts"
mkdir -p "$BS/sdk/android-sdk-linux/ndk"
ln -sfn "$NDK_SRC" "$BS/sdk/android-sdk-linux/ndk/$NDK_VERSION"

# 4) 下载依赖、打上游补丁、清 stale 目录、构建
cd "$BS"
# 网络偶发失败（如 libplacebo 子模块 checkout 中断）：清掉可能半成品的 libplacebo 后重试，最多 3 次
for i in 1 2 3; do
	./include/download-deps.sh && break
	[ "$i" = 3 ] && { echo "download-deps 重试 3 次仍失败" >&2; exit 1; }
	rm -rf deps/libplacebo
done
./patch.sh
rm -rf deps/mpv/_build-arm64
export cores="${JOBS:-8}"
./build.sh --arch arm64 mpv

# 5) strip + 符号检查
TC=$(echo "$BS"/sdk/android-sdk-linux/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/*)
SO="$BS/prefix/arm64-v8a/usr/local/lib/libmpv.so"
cp "$SO" "$WORK/libmpv.unstripped.so"
"$TC/bin/llvm-strip" --strip-all "$SO"
cp "$SO" "$WORK/libmpv.stripped.so"
stat -c '%s bytes  %n' "$WORK/libmpv.unstripped.so" "$WORK/libmpv.stripped.so"
sha256sum "$WORK/libmpv.stripped.so"
echo "E2E_DONE"
