#!/bin/bash -e
# mova ffmpeg slim flavor — derived from tools/ffmpeg-slim/configure-ffmpeg-slim.sh's
# component lists, adapted to this repo's static-link-into-libmpv build shape
# (mirrors flavors/default.sh's mechanics, not configure-ffmpeg-slim.sh's
# --enable-shared spike variant).

. ../../include/depinfo.sh
. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf _build$ndk_suffix
	exit 0
else
	exit 255
fi

mkdir -p _build$ndk_suffix
cd _build$ndk_suffix

cpu=armv7-a
[[ "$ndk_triple" == "aarch64"* ]] && cpu=armv8-a
[[ "$ndk_triple" == "x86_64"* ]] && cpu=generic
[[ "$ndk_triple" == "i686"* ]] && cpu="i686 --disable-asm"

cpuflags=
[[ "$ndk_triple" == "arm"* ]] && cpuflags="$cpuflags -mfpu=neon -mcpu=cortex-a8"

# VP8 dropped entirely (legacy, no mediacodec wrapper, superseded by VP9/AV1).
# VP9 software decode dropped — vp9_mediacodec (hw) only. Devices/content that
# can't use the hw path (no VP9 hwdec, emulators, exotic profiles) will fail
# to play VP9 outright rather than falling back to software; accepted tradeoff
# given VP9 hw decode is near-universal on Android 7.0+/2016+ SoCs.
# AV1 software decode (libdav1d, +671KB) kept deliberately — real-device testing
# on a Snapdragon "bengal"-tier phone (Android 12, budget segment, not an old/EOL
# device) hit "Could not open codec." for AV1 hw. AV1 hwdec coverage on the
# actual mid/low-tier Android install base still isn't there (unlike h264/hevc),
# so this stays sw+hw even though the 2026-08-11 baseline is Android 10+.
# H264 software decode dropped 2026-08-11 (baseline narrowed to Android 10+,
# no low-end devices) — h264_mediacodec (hw) only. H264 hw decode is CDD-
# mandated, so hw-only carries far less risk than the VP9 precedent. Still
# NEEDS REAL-DEVICE REGRESSION TEST before shipping (untested) — the CDD
# mandate doesn't cover every profile/level/concurrent-session/malformed-
# stream edge case, which is why the previous sw+hw stance existed in the
# first place (see README "多平台进度" decoder table).
# HEVC software decode KEPT (2026-08-11 re-evaluated, not dropped) — hw
# decode coverage is ~65% and NOT CDD-mandated (per README's decoder table),
# so unlike h264/VP9, narrowing the baseline to Android 10+ alone doesn't
# make hw-only safe; dropping this needs real usage-share data first, not
# just an OS-version floor.
# MJPEG dropped entirely — png decoder/encoder stays (cover art + screenshot).
DECODERS_VIDEO="hevc,libdav1d,png"
# AC3/EAC3 (Dolby) dropped 2026-08-11 — mova's actual content is AAC/Opus,
# never Dolby; unrelated to device age, purely "unused by this project".
# mp3 (fixed-point) dropped in favor of mp3float (floating-point) — ffmpeg
# ships both as alternate implementations of the same format, only one is
# needed.
DECODERS_AUDIO="aac,aac_latm,mp3float,opus,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8"
DECODERS_SUB="ass,ssa,subrip,text,webvtt,movtext"
DECODERS_MEDIACODEC="h264_mediacodec,hevc_mediacodec,vp9_mediacodec,av1_mediacodec"
DECODERS="$DECODERS_VIDEO,$DECODERS_AUDIO,$DECODERS_SUB,$DECODERS_MEDIACODEC"

ENCODERS="png"
# h264/hevc/vp9/av1 parsers kept even without (or without needing) their
# software decoders — mpv/ffmpeg still needs them to find frame boundaries
# before handing frames to the *_mediacodec hw decoders.
PARSERS="h264,hevc,vp9,av1,png,aac,aac_latm,flac,opus,vorbis,mpegaudio"
DEMUXERS="mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ass,srt,webvtt"
PROTOCOLS="file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp"
BSFS="null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts"
# Testing zero filters (was "overlay,equalizer", matching media_kit's own
# enabled set) — mpv's own scale/format conversion goes through swscale/
# swresample directly, not lavfi, so this MAY be safe, but needs real-device
# playback verification before shipping (untested regression risk).
FILTERS=""

# NEON is mandatory in the AArch64 baseline ISA, so on arm64 specifically it's
# safe to assume it's always present and skip ffmpeg's runtime CPU-feature
# detection/dispatch. NOT safe to apply blanket to armv7l (NEON optional on
# some ARMv7 chips) or x86/x86_64 (AVX2 etc. not guaranteed) — keep runtime
# detection there.
cpudetect_flag="--enable-runtime-cpudetect"
[[ "$ndk_triple" == "aarch64"* ]] && cpudetect_flag="--disable-runtime-cpudetect"

../configure \
	--target-os=android --enable-cross-compile --cross-prefix=$ndk_triple- --ar=$AR --cc=$CC --nm=llvm-nm --ranlib=$RANLIB \
	--arch=${ndk_triple%%-*} --cpu=$cpu --pkg-config=pkg-config \
	--enable-lto \
	--extra-cflags="-I$prefix_dir/include $cpuflags -ffunction-sections -fdata-sections -fvisibility=hidden -flto -fomit-frame-pointer" \
	--extra-ldflags="-L$prefix_dir/lib -Wl,--gc-sections -flto" \
	\
	--disable-gpl \
	--disable-nonfree \
	--enable-version3 \
	--enable-static \
	--disable-shared \
	--disable-vulkan \
	--disable-iconv \
	--disable-stripping \
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
	--enable-jni \
	--enable-bsfs \
	--enable-mediacodec \
	--enable-hwaccels \
	\
	--disable-dxva2 \
	--disable-vaapi \
	--disable-vdpau \
	--disable-bzlib \
	--disable-linux-perf \
	--disable-videotoolbox \
	--disable-audiotoolbox \
	\
	--enable-small \
	--enable-optimizations \
	$cpudetect_flag \
	\
	--enable-mbedtls \
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
	\
	--enable-network \

make -j$cores
make DESTDIR="$prefix_dir" install
