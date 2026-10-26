#!/usr/bin/env bash
#
# videoman ffmpeg slim build configuration - FINAL, mobile-first
# videoman ffmpeg 瘦身构建配置 - 终稿，移动端优先
# ---------------------------------------------------------------------------
# Builds an LGPL, decode-only ffmpeg carrying modern mainstream VOD + live
# formats, optimized for size. Mobile (Android/iOS) is the target; desktop is
# explicitly out of scope for this configuration.
#
# 构建一个 LGPL、纯解码、只保留现代主流点播+直播格式、体积优先的 ffmpeg。
# 目标平台是移动端（Android/iOS）；桌面端明确不在本配置的考虑范围内。
#
# Measured on the real media_kit build chain - libmpv-android-video-build
# @1ecf510, ffmpeg 6.0, NDK r25c, arm64-v8a, ffmpeg linked statically into
# libmpv.so, llvm-strip --strip-all:
#
# 在真实的 media_kit 构建链上实测 —— libmpv-android-video-build @1ecf510、
# ffmpeg 6.0、NDK r25c、arm64-v8a、ffmpeg 静态链入 libmpv.so、
# llvm-strip --strip-all 之后：
#
#   full     (all decoders/demuxers/parsers)  16,111,168 B  15.37 MiB
#   default  (what media_kit ships today)     12,369,664 B  11.80 MiB
#   FINAL    (this configuration)              8,356,744 B   7.97 MiB  -32.4%
#
# The saving comes from dropping 115 legacy decoders and 54 legacy demuxers,
# NOT from removing encoders: media_kit's shipped build already has 0 muxers
# and only 6 image encoders. See README.md for the full breakdown.
#
# 收益来自砍掉 115 个遗留解码器和 54 个遗留 demuxer，而**不是**来自去掉编码器：
# media_kit 现在发布的构建本身就是 0 个 muxer、只有 6 个图像编码器。
# 完整拆解见 README.md。
#
# What this configuration deliberately keeps, and why mobile needs it:
#   - MediaCodec hardware decoders: on a phone these decide battery, heat and
#     whether 4K HEVC/AV1 plays at all. Each wrapper is a few KB.
#   - Software decoders alongside them: MediaCodec fails on unusual profiles,
#     odd resolutions and on emulators, so the fallback must exist.
#   - libdav1d for AV1: hardware AV1 is rare on mobile SoCs, and ffmpeg's own
#     av1 decoder is an order of magnitude slower on arm64.
#   - Full subtitle support: libass/freetype/harfbuzz/fribidi get linked by
#     libmpv regardless, so dropping subtitle decoders means carrying roughly
#     2 MB of font stack for nothing.
#
# 本配置刻意保留的东西，以及移动端为什么需要：
#   - MediaCodec 硬解：在手机上它直接决定耗电、发热，以及 4K HEVC/AV1 能不能播。
#     每个包装器只有几 KB。
#   - 与之并存的软解：MediaCodec 在冷门 profile、异常分辨率和模拟器上会失败，
#     所以 fallback 必须存在。
#   - AV1 用 libdav1d：移动 SoC 上 AV1 硬解很少见，而 ffmpeg 自带的 av1 解码器
#     在 arm64 上慢一个量级。
#   - 完整字幕支持：libass/freetype/harfbuzz/fribidi 无论如何都会被 libmpv 链入，
#     砍掉字幕解码器等于白背约 2 MB 的字体栈。
#
# Source origins / 源码母版下载来源（详见 README.md「源码母版」一节）：
#   ffmpeg  https://git.ffmpeg.org/ffmpeg.git
#           mirror / 镜像: https://github.com/FFmpeg/FFmpeg.git
#   dav1d   https://code.videolan.org/videolan/dav1d.git
#           mirror / 镜像: https://github.com/videolan/dav1d.git
#   mpv     https://github.com/mpv-player/mpv.git
#
# usage / 用法：
#   ./configure-ffmpeg-slim.sh <ffmpeg-src> [prefix] [optflags] [options...]
#
#   options / 选项：
#     --build          run make && make install after a successful configure
#                      configure 成功后自动 make && make install
#     --android        add the Android-only flags: --enable-jni,
#                      --enable-mediacodec, the *_mediacodec decoders and
#                      --disable-vulkan
#                      加入 Android 专有开关：--enable-jni、--enable-mediacodec、
#                      *_mediacodec 解码器，以及 --disable-vulkan
#     --with-dav1d     add --enable-libdav1d and the libdav1d decoder
#                      (dav1d must be visible to pkg-config)
#                      加入 --enable-libdav1d 与 libdav1d 解码器
#                      （dav1d 需能被 pkg-config 找到）
#     --with-tls       add --enable-mbedtls. Required on Android, which has no
#                      system TLS backend - without it https/tls/rtmps are
#                      silently configured out. Implies --enable-version3,
#                      because mbedtls 3.x is Apache-2.0/GPL-2.0 dual-licensed
#                      and ffmpeg classifies that as version3, so the result is
#                      LGPLv3 rather than LGPLv2.1.
#                      加入 --enable-mbedtls。Android 必须加，因为系统没有 TLS
#                      后端——不加的话 https/tls/rtmps 会被 configure 静默裁掉。
#                      它会连带 --enable-version3，因为 mbedtls 3.x 是
#                      Apache-2.0/GPL-2.0 双授权、ffmpeg 归类为 version3，
#                      所以结果是 LGPLv3 而非 LGPLv2.1。
#     --strict-decode  drop the png encoder, giving a build with zero encoders.
#                      Screenshots stop working.
#                      去掉 png 编码器，得到零编码器的构建。截图功能会失效。
#
#   env / 环境变量：
#     EXTRA_CONFIGURE  extra flags appended verbatim - this is where the
#                      cross-compilation setup goes (--target-os, --arch,
#                      --cross-prefix, --cc, --extra-cflags ...). This script
#                      does not invent a toolchain.
#                      原样追加的额外参数——交叉编译设置放这里
#                      （--target-os、--arch、--cross-prefix、--cc、
#                      --extra-cflags 等）。本脚本不自造工具链。
#
# example / 例：
#   # host build, just to check the component set holds together
#   # 宿主机构建，只为验证组件集合能成立
#   ./configure-ffmpeg-slim.sh ~/src/ffmpeg ~/out/ffmpeg-slim '-Os' --build
#
#   # Android arm64; the caller supplies the cross-compilation flags
#   # Android arm64；交叉编译参数由调用方提供
#   EXTRA_CONFIGURE="--target-os=android --enable-cross-compile \
#     --arch=aarch64 --cross-prefix=aarch64-linux-android- \
#     --cc=aarch64-linux-android21-clang" \
#   ./configure-ffmpeg-slim.sh ~/src/ffmpeg ~/out/arm64 '-Os' \
#     --android --with-dav1d --with-tls --build
#
# ---------------------------------------------------------------------------
# !!! For a real Android artifact, do NOT stop at this script !!!
# !!! 出真正的 Android 产物时，不要止步于本脚本 !!!
# ---------------------------------------------------------------------------
# videoman ships libmpv (with ffmpeg statically linked inside), not standalone
# ffmpeg libraries. The Android artifact must be produced through
# media-kit/libmpv-android-video-build with these component lists dropped into
# buildscripts/flavors/, and that build MUST run ./patch.sh first.
#
# The repo carries three patches that the official releases are built with:
#   patches/mpv/mpv_lavc_set_java_vm.patch   <- critical
#   patches/ffmpeg/hls_mp4_seek.patch
#   patches/ffmpeg/dash_base_url_escape.patch
#
# Skipping ./patch.sh produces a libmpv.so that looks fine and plays video, but
# with MediaCodec hardware decoding permanently off: media_kit reaches the
# JavaVM through mpv_lavc_set_java_vm (added by that patch) because a
# statically linked libavcodec exposes no libavcodec.so to open. When the symbol
# is missing, media_kit's AndroidHelper throws UnsupportedError, its own
# `catch (_) {}` swallows it, and the app silently falls back to software
# decoding. Verify with:
#   llvm-nm -D --defined-only libmpv.so | grep mpv_lavc_set_java_vm
#
# videoman 出货的是 libmpv（ffmpeg 静态链在里面），不是独立的 ffmpeg 库。
# Android 产物必须走 media-kit/libmpv-android-video-build，把这里的组件清单
# 搬进 buildscripts/flavors/，并且那次构建**必须先跑 ./patch.sh**。
#
# 该仓库自带三个补丁，官方 release 就是带着它们构建的：
#   patches/mpv/mpv_lavc_set_java_vm.patch   <- 关键
#   patches/ffmpeg/hls_mp4_seek.patch
#   patches/ffmpeg/dash_base_url_escape.patch
#
# 漏跑 ./patch.sh 会得到一个「看起来正常、视频也能播」的 libmpv.so，
# 但 MediaCodec 硬解永久关闭：ffmpeg 静态链接后没有 libavcodec.so 可打开，
# media_kit 只能通过该补丁新增的 mpv_lavc_set_java_vm 拿到 JavaVM。
# 符号缺失时 media_kit 的 AndroidHelper 抛 UnsupportedError，
# 又被它自己的 `catch (_) {}` 吞掉，应用就静默退回软解。核验方法：
#   llvm-nm -D --defined-only libmpv.so | grep mpv_lavc_set_java_vm
set -euo pipefail

SRC="${1:?需要传入 ffmpeg 源码目录 / ffmpeg source directory required}"
PREFIX="${2:-$SRC/_slim_install}"
OPTFLAGS="${3:--Os}"
DO_BUILD=0
WITH_ANDROID=0
WITH_DAV1D=0
WITH_TLS=0
STRICT_DECODE=0
for a in "$@"; do
  case "$a" in
    --build)         DO_BUILD=1 ;;
    --android)       WITH_ANDROID=1 ;;
    --with-dav1d)    WITH_DAV1D=1 ;;
    --with-tls)      WITH_TLS=1 ;;
    --strict-decode) STRICT_DECODE=1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Component lists / 组件清单
# ---------------------------------------------------------------------------

# Video decoders: the modern four (h264/hevc/vp9/av1) plus vp8 for legacy WebM.
# av1 is served by libdav1d only, and only with --with-dav1d; ffmpeg's built-in
# av1 decoder is deliberately never enabled because it is far slower on arm64.
# mjpeg and png decode the attached pictures (cover art) inside mp3/mp4/mkv.
#
# 视频解码器：现代四件套（h264/hevc/vp9/av1）+ vp8（存量 WebM）。
# av1 只由 libdav1d 提供，且只在传 --with-dav1d 时启用；ffmpeg 内置的 av1
# 解码器刻意永不启用，因为它在 arm64 上慢得多。
# mjpeg 和 png 用来解 mp3/mp4/mkv 里的封面图（attached picture）。
DECODERS_VIDEO="h264,hevc,vp9,vp8,mjpeg,png"

# Audio decoders: aac (+latm for HLS/TS), mp3, opus, ac3/eac3 (Dolby), flac,
# vorbis, plus the raw PCM layouts that actually occur inside mkv/mov.
#
# 音频解码器：aac（+latm，HLS/TS 用）、mp3、opus、ac3/eac3（Dolby）、flac、
# vorbis，以及 mkv/mov 里真实会出现的那几种 PCM 裸流布局。
DECODERS_AUDIO="aac,aac_latm,mp3,mp3float,opus,ac3,eac3,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8"

# Subtitle decoders: ass/ssa (styled), subrip/text (plain), webvtt (HLS),
# movtext (embedded in mp4).
#
# 字幕解码器：ass/ssa（带样式）、subrip/text（纯文本）、webvtt（HLS）、
# movtext（mp4 内封）。
DECODERS_SUB="ass,ssa,subrip,text,webvtt,movtext"

# MediaCodec hardware decoders, Android only.
#
# MediaCodec 硬件解码器，仅 Android。
DECODERS_MEDIACODEC="h264_mediacodec,hevc_mediacodec,vp8_mediacodec,vp9_mediacodec,av1_mediacodec"

# The only encoder in the build: mpv's `screenshot` command needs an image
# encoder. png alone - not mjpeg/ljpeg/jpegls/jpeg2000, which is what
# media_kit's own build carries. Pass --strict-decode to drop it.
#
# 整个构建里唯一的编码器：mpv 的 `screenshot` 命令需要图像编码器。
# 只要 png，不要 mjpeg/ljpeg/jpegls/jpeg2000（media_kit 自己的构建带的是那一套）。
# 传 --strict-decode 可以去掉它。
ENCODERS="png"

# Frame parsers, matching the decoders above (mpegaudio is mp3's implicit
# dependency).
#
# 帧解析器，与上面的解码器对应（mpegaudio 是 mp3 的隐式依赖）。
PARSERS="h264,hevc,vp9,vp8,av1,mjpeg,png,aac,aac_latm,ac3,flac,opus,vorbis,mpegaudio"

# Containers. mov = the whole MP4 family; matroska = MKV + WebM;
# mpegts + hls = HLS; flv + live_flv = FLV including live; the bare audio
# streams; and the standalone subtitle files.
#
# DASH is NOT enabled. Its demuxer needs external libxml2, and on mobile HLS
# already covers streaming. Leaving it out keeps libxml2's static library
# (~740 KB) out of the final binary entirely - this is why the FINAL build is
# smaller than the same configuration with DASH, despite adding the png encoder
# and the whole live protocol stack.
#
# RTSP is NOT enabled either. ffmpeg's rtsp demuxer selects rdt, which drags in
# the rm, asf, ivr and kux demuxers - a pile of legacy containers pulled in for
# one protocol. Add it only when a product requirement actually needs RTSP.
#
# 容器。mov = MP4 全家桶；matroska = MKV + WebM；mpegts + hls = HLS；
# flv + live_flv = FLV 含直播；裸音频流；以及外挂字幕文件。
#
# 不启用 DASH。它的 demuxer 依赖外部 libxml2，而移动端 HLS 已覆盖流媒体。
# 不带它，libxml2 的静态库（约 740 KB）就完全不会进最终产物——这也是终稿
# 明明加了 png 编码器和整套直播协议、体积却比带 DASH 的同配置还小的原因。
#
# 也不启用 RTSP。ffmpeg 的 rtsp demuxer 会 select rdt，而 rdt 又拖进
# rm、asf、ivr、kux 四个老容器——为一个协议背一堆遗留格式。
# 只有产品确实需要 RTSP 时再加。
DEMUXERS="mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ac3,eac3,ass,srt,webvtt"

# Protocols. Local + http(s)/tls; crypto = HLS AES-128 encrypted segments;
# the rtmp family = live ingest (ffrtmpcrypt/ffrtmphttp are its ffmpeg-internal
# dependencies, not external libraries); udp feeding the mpegts demuxer is the
# IPTV multicast path; fd and pipe let the app hand ffmpeg a descriptor it has
# already opened, which is how Android content:// URIs are consumed.
#
# rtmpe/rtmpte (proprietary RTMP encryption, rare) need an external crypto
# backend and are left out.
#
# 协议。本地 + http(s)/tls；crypto = HLS AES-128 加密分片；
# rtmp 全家 = 直播拉流（ffrtmpcrypt/ffrtmphttp 是它的 ffmpeg 内部依赖，
# 不是外部库）；udp 喂给 mpegts demuxer 就是 IPTV 组播路径；
# fd 和 pipe 让上层把已经打开的描述符交给 ffmpeg——Android 的 content:// URI
# 就是这样消费的。
#
# rtmpe/rtmpte（RTMP 私有加密，冷门）需要外部 crypto 后端，不纳入。
PROTOCOLS="file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp"

# Bitstream filters. The mp4toannexb pair is mandatory for MediaCodec playback
# of mp4 sources; aac_adtstoasc for AAC inside HLS/TS; extract_extradata and
# the vp9/av1 frame splitters are required by the corresponding decoders;
# mov2textsub for mp4-embedded subtitles.
#
# 比特流过滤器。mp4 源走 MediaCodec 硬解时 mp4toannexb 这两个是必需的；
# aac_adtstoasc 用于 HLS/TS 里的 AAC；extract_extradata 和 vp9/av1 的帧拆分器
# 是对应解码器要求的；mov2textsub 用于 mp4 内封字幕。
BSFS="null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts"

# Filters. libavfilter is a hard dependency of mpv but almost none of its
# filters are: mpv scales and resamples through libswscale and libswresample
# directly. overlay and equalizer match what media_kit's own build enables.
#
# 滤镜。libavfilter 是 mpv 的硬依赖，但它的滤镜几乎都不是：mpv 直接用
# libswscale 和 libswresample 做缩放与重采样。overlay 与 equalizer 与
# media_kit 自己的构建保持一致。
FILTERS="overlay,equalizer"

# ---------------------------------------------------------------------------
# configure
# ---------------------------------------------------------------------------
# Notes:
#  - LGPL is the default in current ffmpeg (the --enable-lgpl flag was removed);
#    passing neither --enable-gpl nor --enable-nonfree is what makes it LGPL.
#    --with-tls moves the result to LGPLv3, see above.
#  - --disable-everything followed by per-category --enable is the official
#    minimal-build recipe.
#  - --disable-programs/-doc: libraries only, no ffmpeg/ffprobe binaries.
#  - decode only: no --enable-muxer anywhere, and at most the single png encoder.
#  - --enable-small sits on top of $OPTFLAGS and also shrinks ffmpeg's built-in
#    tables. On clang it maps the optimization level to -Oz, which is stronger
#    than the -Os passed via --optflags.
#
# 说明：
#  - 当前 ffmpeg 里 LGPL 已是默认（--enable-lgpl 已移除）；不传 --enable-gpl
#    也不传 --enable-nonfree 即为 LGPL。--with-tls 会把结果变成 LGPLv3，见上文。
#  - --disable-everything 后逐类 --enable，是官方推荐的最小化构建法。
#  - --disable-programs/-doc：只出库，不出 ffmpeg/ffprobe 可执行文件。
#  - 纯解码：全程不 --enable-muxer，编码器最多只有 png 那一个。
#  - --enable-small 叠在 $OPTFLAGS 之上，还会压缩 ffmpeg 的内置表。
#    在 clang 下它把优化级别映射为 -Oz，比 --optflags 传的 -Os 更激进。
cd "$SRC"

DECODERS="$DECODERS_VIDEO,$DECODERS_AUDIO,$DECODERS_SUB"

args=(
  --prefix="$PREFIX"
  --enable-shared
  --disable-static
  --disable-programs
  --disable-doc
  --disable-avdevice
  --disable-postproc
  --disable-gray
  --disable-swscale-alpha
  --disable-everything
  # zlib is requested explicitly, not left to autodetection, because the png
  # decoder needs inflate and the png encoder needs deflate. Without zlib
  # ffmpeg only prints "WARNING: Disabled png_decoder ... inflate_wrapper" and
  # silently drops both - cover art and screenshots would just be missing, with
  # a successful build. Asking for it turns that into a hard configure error.
  #
  # zlib 显式要求、不交给自动探测：png 解码器需要 inflate，png 编码器需要 deflate。
  # 缺 zlib 时 ffmpeg 只打印 "WARNING: Disabled png_decoder ... inflate_wrapper"
  # 就静默砍掉两者——构建照样成功，但封面图和截图会直接消失。
  # 显式要求可以把它变成 configure 硬错误。
  --enable-zlib
  --enable-small
  --enable-optimizations
  --enable-runtime-cpudetect
  --enable-network
  --optflags="$OPTFLAGS"
)

if [ "$WITH_ANDROID" = "1" ]; then
  DECODERS="$DECODERS,$DECODERS_MEDIACODEC"
  args+=(--enable-jni --enable-mediacodec --enable-hwaccels)
  # ffmpeg autodetects Vulkan from the NDK sysroot, but the NDK ships vulkan.h
  # without vulkan_beta.h, so hwcontext_vulkan.c fails to compile.
  #
  # ffmpeg 会从 NDK sysroot 自动探测 Vulkan，但 NDK 只带了 vulkan.h、
  # 没带 vulkan_beta.h，hwcontext_vulkan.c 会编译失败。
  args+=(--disable-vulkan)
fi

if [ "$WITH_DAV1D" = "1" ]; then
  DECODERS="$DECODERS,libdav1d"
  args+=(--enable-libdav1d)
fi

if [ "$WITH_TLS" = "1" ]; then
  args+=(--enable-mbedtls --enable-version3)
fi

args+=(
  --enable-decoder="$DECODERS"
  --enable-parser="$PARSERS"
  --enable-demuxer="$DEMUXERS"
  --enable-protocol="$PROTOCOLS"
  --enable-bsf="$BSFS"
  --enable-filter="$FILTERS"
)

[ "$STRICT_DECODE" = "0" ] && args+=(--enable-encoder="$ENCODERS")

# EXTRA_CONFIGURE is intentionally word-split: it carries multiple flags.
#
# EXTRA_CONFIGURE 刻意按空格拆分：它携带的是多个参数。
# shellcheck disable=SC2206
[ -n "${EXTRA_CONFIGURE:-}" ] && args+=(${EXTRA_CONFIGURE})

echo ">>> configure（优化标志：$OPTFLAGS，安装前缀：$PREFIX）"
echo ">>> android=$WITH_ANDROID dav1d=$WITH_DAV1D tls=$WITH_TLS strict-decode=$STRICT_DECODE"
./configure "${args[@]}"

# License readout. configure prints "License: ..." to stdout only - it never
# reaches ffbuild/config.log - so derive it from the recorded config instead.
#
# 许可核对。configure 只把 "License: ..." 打到 stdout，从不写进 ffbuild/config.log，
# 所以改为从记录下来的配置反推。
echo ">>> configure 成功。许可核对："
if grep -q '^CONFIG_NONFREE=yes' ffbuild/config.mak 2>/dev/null; then
  echo "    License: nonfree and unredistributable"
elif grep -q '^CONFIG_GPL=yes' ffbuild/config.mak 2>/dev/null; then
  grep -q '^CONFIG_VERSION3=yes' ffbuild/config.mak \
    && echo "    License: GPL version 3 or later" \
    || echo "    License: GPL version 2 or later"
else
  grep -q '^CONFIG_VERSION3=yes' ffbuild/config.mak \
    && echo "    License: LGPL version 3 or later" \
    || echo "    License: LGPL version 2.1 or later"
fi

if [ "$DO_BUILD" = "1" ]; then
  echo ">>> make -j && make install"
  make -j"$(nproc 2>/dev/null || echo 4)"
  make install
  echo ">>> 完成。产物在 $PREFIX/（Windows 下 bin/，*nix 下 lib/）"
  echo ">>> 库体积："
  find "$PREFIX" \( -name 'libav*.so*' -o -name 'libsw*.so*' -o -name 'av*.dll' -o -name 'sw*.dll' -o -name 'libav*.dylib' -o -name 'libsw*.dylib' \) -exec ls -l {} \; 2>/dev/null || true
else
  echo ">>> 未传 --build。手动继续：make -j\$(nproc) && make install"
fi
