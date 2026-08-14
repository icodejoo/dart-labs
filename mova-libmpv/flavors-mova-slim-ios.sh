#!/bin/bash -e
# mova ffmpeg slim flavor — iOS (device, arm64). Component lists (decoders/
# demuxers/protocols/bsfs) mirror flavors-mova-slim.sh (Android) as closely as
# the platform allows; hwaccel is VideoToolbox instead of MediaCodec.
#
# ⚠️ This is a CONFIG, not a proven build pipeline (unlike the Android flavor,
# which has a real CI run + real-device playback behind it). Two things are
# still open and must be resolved before this can produce a real artifact:
#
#   1. ffmpeg's VideoToolbox support is a *hwaccel*, not separate decoder names
#      like Android's *_mediacodec. --enable-videotoolbox + --enable-hwaccels
#      lets the existing h264/hevc software decoders opportunistically hand
#      frames to VTDecompressionSession at runtime — there is no
#      "h264_videotoolbox" name to put in --enable-decoder. ffmpeg n6.0 (the
#      version pinned for the v6 line, see README) has no VideoToolbox hwaccel
#      for VP9 or AV1 at all, so unlike Android those two are software-only
#      here — this is a real capability gap versus Android, not an oversight.
#   2. Cross-building libass/freetype/harfbuzz/fribidi/dav1d *for iOS* (arm64,
#      not the host mac's arch) from source needs a meson cross file + xcrun
#      toolchain — see the `ios` CI job in build-mova-libmpv.yml for the
#      known-good recipe (all five ship meson build files, so one shared
#      cross file covers all of them). TLS uses Apple's own securetransport
#      backend instead of vendoring mbedtls, so that one dependency Android
#      needs, iOS doesn't.
#
# Meant to be dropped next to Android's flavors-mova-slim.sh once an iOS build
# harness exists to drive it (see README's iOS section for current status).
#
# Usage: cwd = ffmpeg source tree, PREFIX env var set, dav1d already
# cross-built for iOS with its .pc file on PKG_CONFIG_PATH.
#   PREFIX=/path/to/out ./flavors-mova-slim-ios.sh

PREFIX="${PREFIX:?PREFIX env var required (install prefix for make install)}"
target_arch="${MOVA_IOS_ARCH:-arm64}"          # arm64 = device; can be overridden for simulator work
ios_min_version="${MOVA_IOS_MIN_VERSION:-13.0}"
sdk="${MOVA_IOS_SDK:-iphoneos}"                 # iphoneos (device) or iphonesimulator
sysroot=$(xcrun --sdk "$sdk" --show-sdk-path)
cc=$(xcrun --sdk "$sdk" --find clang)

# Same rationale as Android's h264 note (2026-08-11 flavor): keep both hw+sw
# for h264/hevc rather than assuming hw-only is safe — that call needed a real
# device to overturn (see README's VP9/AV1 real-device pivot), and iOS has had
# zero real-device testing so far. vp9/av1 are software-only: no VideoToolbox
# hwaccel exists for them in ffmpeg n6.0, so there is no hw channel to add.
DECODERS_VIDEO="h264,hevc,vp9,libdav1d,png"
# Same set as Android — content mix (AAC/Opus, no Dolby) doesn't change per platform.
DECODERS_AUDIO="aac,aac_latm,mp3float,opus,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8"
DECODERS_SUB="ass,ssa,subrip,text,webvtt,movtext"
DECODERS="$DECODERS_VIDEO,$DECODERS_AUDIO,$DECODERS_SUB"

ENCODERS="png"
PARSERS="h264,hevc,vp9,av1,png,aac,aac_latm,flac,opus,vorbis,mpegaudio"
DEMUXERS="mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ass,srt,webvtt"
PROTOCOLS="file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp"
BSFS="null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts"
# Same "untested, needs real-device regression" caveat as Android's FILTERS="".
FILTERS=""

# ffmpeg's configure defaults to `enable debug` (bakes -g into every object
# file) unless told otherwise — --disable-debug stops that at the source,
# same fix as the meson deps' `debug = false` cross-file override.
#
# securetransport (Apple's Security.framework), not mbedtls: iOS/macOS ship a
# real system TLS stack, so there is no reason to vendor and statically link
# a TLS library the way Android has to (no system TLS backend there).
# ffmpeg's check_lib auto-adds -framework Security -framework CoreFoundation,
# both system frameworks — this also drops the --enable-version3 requirement
# mbedtls's dual Apache/GPL-2.0 licensing forced (see Android's README note),
# so this build stays plain LGPLv2.1 instead of LGPLv3.
./configure \
	--target-os=darwin --arch="$target_arch" --cc="$cc" \
	--sysroot="$sysroot" \
	--extra-cflags="-arch $target_arch -mios-version-min=$ios_min_version -ffunction-sections -fdata-sections -fvisibility=hidden -flto -fomit-frame-pointer ${MOVA_EXTRA_CFLAGS:-}" \
	--extra-ldflags="-arch $target_arch -mios-version-min=$ios_min_version -Wl,-dead_strip -flto ${MOVA_EXTRA_LDFLAGS:-}" \
	--enable-cross-compile \
	--enable-lto \
	\
	--disable-gpl \
	--disable-nonfree \
	--enable-static \
	--disable-shared \
	--disable-iconv \
	--disable-stripping \
	--disable-debug \
	--pkg-config-flags=--static \
	\
	--disable-muxers \
	--disable-decoders \
	--disable-encoders \
	--disable-demuxers \
	--disable-parsers \
	--disable-protocols \
	--disable-devices \
	--disable-filters \
	--disable-doc \
	--disable-avdevice \
	--disable-postproc \
	--disable-programs \
	--disable-gray \
	--disable-swscale-alpha \
	\
	--enable-videotoolbox \
	--enable-hwaccels \
	--disable-audiotoolbox \
	--disable-vulkan \
	--disable-vaapi \
	--disable-vdpau \
	--disable-dxva2 \
	--disable-bzlib \
	\
	--enable-small \
	--enable-optimizations \
	--enable-runtime-cpudetect \
	\
	--enable-securetransport \
	\
	--enable-libdav1d \
	\
	--enable-zlib \
	\
	--enable-avutil \
	--enable-avcodec \
	--enable-avfilter \
	--enable-avformat \
	--enable-swscale \
	--enable-swresample \
	\
	--enable-decoder="$DECODERS" \
	--enable-encoder="$ENCODERS" \
	--enable-parser="$PARSERS" \
	--enable-demuxer="$DEMUXERS" \
	--enable-protocol="$PROTOCOLS" \
	--enable-bsf="$BSFS" \
	--enable-filter="$FILTERS" \
	\
	--enable-network \
	--prefix="$PREFIX"

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install
