#!/bin/bash
# EXPERIMENT — not the shipped Android flavor (see ../flavors-mova-slim.sh
# for that, still the production path, 5.87MiB, pre-libplacebo mpv). This
# script replicates ../build-win-libmpv-v9.sh's stack (ffmpeg n9.0 + mpv
# v0.41.0 + libplacebo) for Android arm64-v8a/API 24 to get an
# apples-to-apples cross-platform size comparison. libplacebo uses the
# Vulkan backend here (not d3d11 — Android's native GPU API), so no
# spirv-cross is needed: Vulkan consumes SPIR-V directly.
#
# Size history (stripped libmpv.so, 2026-08-07, WSL2 + NDK r25c):
#   10.62MB  baseline (ffmpeg n9.0 + mpv v0.41.0 + libplacebo)
#    9.73MB  + drop h264 software decoder, hw-only via h264_mediacodec
#    9.29MB  + drop hevc software decoder, hw-only via hevc_mediacodec
# vs the shipped 5.87MiB pre-libplacebo build — libplacebo is still a fixed
# ~1.6x tax after both hw-only cuts (same order of magnitude as Windows'
# 13.60MB equivalent). The h264/hevc hw-only decoders are standalone FFCodec
# implementations (same as the already-shipped vp9/av1 hw-only tradeoff in
# ../flavors-mova-slim.sh) — they only need the codec's parser (already
# enabled) to find frame boundaries, not the software decoder. H.264
# MediaCodec coverage has been mandatory since API 16; HEVC MediaCodec is
# broadly available from API 21+. This is an Android-only call — do NOT
# port the hevc hw-only cut to iOS: pre-A9 devices (iPhone 6 and older,
# still inside many apps' iOS 12+ floor) have no HEVC VideoToolbox decode.
#
# Not yet ported here (validated on Windows only, see
# ../build-win-libmpv-v9.sh's header for numbers): the FreeType modules.cfg
# trim and dropping ffmpeg's own subtitle decoders/demuxers. mbedtls stays
# on Android regardless — there's no native-TLS ffmpeg backend for Android
# the way --enable-schannel covers Windows.
#
# Also investigated cross-platform and NOT pursued (same finding applies
# here as on Windows): mpv's meson.build hard-requires libass with no
# feature option — stripping it means patching mpv's own OSD backend-
# dispatch to tolerate zero text-rendering backends, which is framework
# surgery (wrong cut fails as "mpv doesn't start"), not a build flag. See
# ../build-win-libmpv-v9.sh's header for the full writeup.
#
# Status: tentative, see ../build-win-libmpv-v9.sh's header for the
# libplacebo adoption decision context. Invoked by
# .github/workflows/experiment-libmpv-v9.yml.
set -e
set -x

WORK=/tmp/mova-android-libmpv
NDK=/tmp/android-ndk-r25c
TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64
API=24
TARGET=aarch64-linux-android
CROSS=$TARGET$API
PREFIX="$WORK/prefix"
mkdir -p "$WORK" "$PREFIX"
cd "$WORK"

export AR=$TOOLCHAIN/bin/llvm-ar
export CC=$TOOLCHAIN/bin/$CROSS-clang
export CXX=$TOOLCHAIN/bin/$CROSS-clang++
export STRIP=$TOOLCHAIN/bin/llvm-strip
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export NM=$TOOLCHAIN/bin/llvm-nm

export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG="pkg-config --static"
# libplacebo's glsl/*.c(c) source files that #include <glslang/...> headers
# don't get an -I from meson's dependency wiring (find_library() calls carry
# no include dirs, only the has_header() check below got patched) — clang
# still honors CPATH for implicit -I search, which is what silently covered
# this same gap on the Windows build (it exports this for find_library/
# LIBRARY_PATH reasons and never hit this failure as a result).
export CPATH="$PREFIX/include"
NPROC=$(nproc)

log() { echo "=== $1 ==="; }

ANDROID_TOOLCHAIN="$WORK/android-toolchain.cmake"
cat > "$ANDROID_TOOLCHAIN" <<EOF
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION $API)
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a)
set(CMAKE_ANDROID_NDK $NDK)
set(CMAKE_ANDROID_STL_TYPE c++_static)
set(CMAKE_FIND_ROOT_PATH "$PREFIX")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

cat > "$WORK/android-cross.ini" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
pkg-config = 'pkg-config'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

# ---- Vulkan-Headers (header-only) — NDK r25c bundles an older vulkan.h with
# no Vulkan Video extension types (VkVideoCodecOperationFlagBitsKHR etc.),
# which libavutil/hwcontext_vulkan.h references unconditionally (it's a
# public header, installed regardless of ffmpeg's own --disable-vulkan, and
# libplacebo's utils/libav.h includes it for AVFrame<->vulkan interop). A
# newer standalone copy in $PREFIX/include shadows the NDK one since our -I
# comes first in every subsequent build's include search order. ----
if [ ! -f "$PREFIX/include/vulkan/vulkan_core.h.new" ]; then
  log "Vulkan-Headers"
  [ -d vulkan-headers-src ] || git clone --depth 1 -b v1.3.296 https://github.com/KhronosGroup/Vulkan-Headers.git vulkan-headers-src
  mkdir -p "$PREFIX/include"
  cp -r vulkan-headers-src/include/vulkan "$PREFIX/include/"
  cp -r vulkan-headers-src/include/vk_video "$PREFIX/include/" 2>/dev/null || true
  touch "$PREFIX/include/vulkan/vulkan_core.h.new"
fi

# ---- zlib ----
if [ ! -f "$PREFIX/lib/libz.a" ]; then
  log "zlib"
  [ -d zlib-src ] || git clone --depth 1 -b v1.3.1 https://github.com/madler/zlib.git zlib-src
  cd zlib-src
  CC="$CC" AR="$AR" AR_FLAGS=rcs ./configure --prefix="$PREFIX" --static
  make -j"$NPROC"
  make install
  cd "$WORK"
fi

# ---- mbedtls ----
if [ ! -f "$PREFIX/lib/libmbedtls.a" ]; then
  log "mbedtls"
  [ -d mbedtls-src ] || git clone --depth 1 -b v3.6.2 https://github.com/Mbed-TLS/mbedtls.git mbedtls-src
  cd mbedtls-src
  git submodule update --init --depth 1 2>/dev/null || true
  mkdir -p build && cd build
  # NDK's android.toolchain.cmake blanks CMAKE_C_FLAGS_RELEASE/CXX_FLAGS_RELEASE
  # (confirmed empty in CMakeCache.txt, vs "-O3 -DNDEBUG" on a plain desktop
  # toolchain file) — every CMake dep cross-compiled through it defaults to
  # clang's bare -O0 unless we force these back explicitly. This is what
  # blew libMachineIndependent.a up to 42.8MB (unoptimized) vs 4.5MB on
  # Windows for the identical glslang source/config (raw archive size only —
  # it doesn't survive into the final stripped .so either way since dead
  # code gets discarded at link time, but unoptimized code that IS reachable
  # does matter and did show up in the final binary before this fix).
  cmake -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG" -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG" \
    -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
    ..
  ninja
  ninja install
  cd "$WORK"
fi

# ---- dav1d ----
if [ ! -f "$PREFIX/lib/libdav1d.a" ]; then
  log "dav1d"
  [ -d dav1d-src ] || git clone --depth 1 -b 1.4.3 https://code.videolan.org/videolan/dav1d.git dav1d-src
  cd dav1d-src
  meson setup build --prefix="$PREFIX" --default-library=static --buildtype=release \
    --cross-file "$WORK/android-cross.ini" -Denable_tools=false -Denable_tests=false
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

# ---- freetype ----
if [ ! -f "$PREFIX/lib/libfreetype.a" ]; then
  log "freetype"
  [ -d freetype-src ] || git clone --depth 1 -b VER-2-13-3 https://github.com/freetype/freetype.git freetype-src
  cd freetype-src
  ./autogen.sh || true
  ./configure --host=$TARGET --prefix="$PREFIX" --enable-static --disable-shared \
    --with-harfbuzz=no --with-bzip2=no --with-png=no --with-brotli=no
  make -j"$NPROC"
  make install
  cd "$WORK"
fi

# ---- fribidi ----
if [ ! -f "$PREFIX/lib/libfribidi.a" ]; then
  log "fribidi"
  [ -d fribidi-src ] || git clone --depth 1 -b v1.0.16 https://github.com/fribidi/fribidi.git fribidi-src
  cd fribidi-src
  meson setup build --prefix="$PREFIX" --default-library=static --buildtype=release \
    --cross-file "$WORK/android-cross.ini" -Ddocs=false -Dtests=false
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

# ---- harfbuzz ----
if [ ! -f "$PREFIX/lib/libharfbuzz.a" ]; then
  log "harfbuzz"
  [ -d harfbuzz-src ] || git clone --depth 1 -b 9.0.0 https://github.com/harfbuzz/harfbuzz.git harfbuzz-src
  cd harfbuzz-src
  meson setup build --prefix="$PREFIX" --default-library=static --buildtype=release \
    --cross-file "$WORK/android-cross.ini" -Dfreetype=enabled -Dtests=disabled -Dcairo=disabled -Dglib=disabled -Dicu=disabled
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

# ---- libass ----
if [ ! -f "$PREFIX/lib/libass.a" ]; then
  log "libass"
  [ -d libass-src ] || git clone --depth 1 -b 0.17.3 https://github.com/libass/libass.git libass-src
  cd libass-src
  ./autogen.sh
  ./configure --host=$TARGET --prefix="$PREFIX" --enable-static --disable-shared --disable-require-system-font-provider
  make -j"$NPROC"
  make install
  cd "$WORK"
fi

log "deps done, building ffmpeg n9.0"

# ---- ffmpeg n9.0 — same slim decoder list as ../flavors-mova-slim.sh ----
if [ ! -f "$PREFIX/lib/libavcodec.a" ]; then
  [ -d ffmpeg-src ] || git clone --depth 1 --branch n9.0 https://github.com/FFmpeg/FFmpeg.git ffmpeg-src
  cd ffmpeg-src

  # h264/hevc software decoders dropped, hw-only via *_mediacodec — see the
  # file header for the size numbers and the coverage rationale.
  DECODERS_VIDEO="vp9,libdav1d,png"
  DECODERS_AUDIO="aac,aac_latm,mp3,mp3float,opus,ac3,eac3,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8"
  DECODERS_SUB="ass,ssa,subrip,text,webvtt,movtext"
  DECODERS="$DECODERS_VIDEO,$DECODERS_AUDIO,$DECODERS_SUB"
  ENCODERS="png"
  PARSERS="h264,hevc,vp9,av1,png,aac,aac_latm,ac3,flac,opus,vorbis,mpegaudio"
  DEMUXERS="mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ac3,eac3,ass,srt,webvtt"
  PROTOCOLS="file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp"
  BSFS="null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts"

  ./configure \
    --target-os=android --enable-cross-compile --cross-prefix="$TOOLCHAIN/bin/$TARGET-" \
    --cc="$CC" --cxx="$CXX" --ar="$AR" --nm="$NM" --ranlib="$RANLIB" --strip="$STRIP" \
    --arch=aarch64 --cpu=armv8-a --pkg-config=pkg-config \
    \
    --disable-everything \
    --disable-autodetect \
    --disable-swscale-alpha --disable-bzlib --disable-symver --disable-debug \
    \
    --disable-gpl --disable-nonfree --enable-version3 \
    --enable-static --disable-shared --pkg-config-flags=--static \
    --disable-doc --disable-programs --disable-avdevice \
    --disable-vulkan --disable-iconv \
    \
    --enable-small --enable-optimizations --disable-runtime-cpudetect \
    \
    --enable-jni \
    --enable-mediacodec --enable-hwaccel=h264_mediacodec,hevc_mediacodec,vp9_mediacodec,av1_mediacodec \
    \
    --enable-mbedtls --enable-zlib --enable-libdav1d --enable-libass \
    \
    --enable-avutil --enable-avcodec --enable-avfilter --enable-avformat \
    --enable-swscale --enable-swresample \
    \
    --enable-decoder="$DECODERS,h264_mediacodec,hevc_mediacodec,vp9_mediacodec,av1_mediacodec" \
    --enable-encoder="$ENCODERS" \
    --enable-parser="$PARSERS" \
    --enable-demuxer="$DEMUXERS" \
    --enable-protocol="$PROTOCOLS" \
    --enable-bsf="$BSFS" \
    \
    --enable-network \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib" \
    --extra-libs="-lmbedtls -lmbedx509 -lmbedcrypto" \
    --prefix="$PREFIX"
  make -j"$NPROC"
  make install
  cd "$WORK"
fi

log "ffmpeg done, building libplacebo (vulkan backend)"

# ---- glslang ----
if [ ! -f "$PREFIX/lib/libglslang.a" ]; then
  log "glslang"
  if [ ! -d glslang-src ]; then
    git clone --depth 1 -b 14.3.0 https://github.com/KhronosGroup/glslang.git glslang-src
    (cd glslang-src && python3 update_glslang_sources.py)
  fi
  cmake -S glslang-src -B glslang-build -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG" -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG" \
    -DBUILD_SHARED_LIBS=OFF -DENABLE_GLSLANG_BINARIES=OFF \
    -DENABLE_SPVREMAPPER=OFF -DENABLE_CTEST=OFF -DENABLE_HLSL=OFF \
    -DALLOW_EXTERNAL_SPIRV_TOOLS=OFF -DENABLE_OPT=OFF
  cmake --build glslang-build -j"$NPROC"
  cmake --install glslang-build
fi

# ---- libplacebo (vulkan backend — Android's native GPU API for mpv's
# render context, unlike windows' d3d11. spirv-cross isn't needed here:
# vulkan consumes SPIR-V directly, no SPIR-V->HLSL translation step.) ----
if [ ! -f "$PREFIX/lib/libplacebo.a" ]; then
  log "libplacebo"
  [ -d libplacebo-src ] || git clone --recursive --depth 1 https://github.com/haasn/libplacebo.git libplacebo-src
  cd libplacebo-src
  # cc.has_header('glslang/build_info.h') below is called with no -I args,
  # so it can't see our $PREFIX/include even though the header is right
  # there (find_library's dirs: kwarg via -Dvulkan-sdk doesn't cover
  # has_header checks) — this is why "Library glslang found: NO" happened
  # despite SPIRV/MachineIndependent/OSDependent/GenericCodeGen all
  # resolving fine. Patch the one call site to pass -I explicitly.
  if ! grep -q "args: \['-I' + get_option" src/glsl/meson.build; then
    sed -i "s|cc.has_header('glslang/build_info.h')|cc.has_header('glslang/build_info.h', args: ['-I' + get_option('vulkan-sdk') / 'include'])|" src/glsl/meson.build
  fi
  meson setup build --prefix="$PREFIX" --default-library=static --buildtype=release \
    --cross-file "$WORK/android-cross.ini" --prefer-static \
    -Dvulkan=enabled -Dopengl=disabled -Dd3d11=disabled \
    -Dglslang=enabled -Dshaderc=disabled -Ddemos=false -Dtests=false \
    -Dvulkan-sdk="$PREFIX"
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

log "libplacebo done, building mpv"

# ---- mpv v0.41.0 ----
if [ ! -f "$PREFIX/lib/libmpv.so" ]; then
  [ -d mpv-src ] || git clone --depth 1 --branch v0.41.0 https://github.com/mpv-player/mpv.git mpv-src
  cd mpv-src
  # aaudio=disabled: NDK r25c's aaudio/AAudio.h lacks AAUDIO_FORMAT_IEC61937
  # (a newer constant than this NDK ships), which mpv's ao_aaudio.c
  # references unconditionally — OpenSL ES / AudioTrack outputs cover audio
  # output without it.
  meson setup build --prefix="$PREFIX" --libdir=lib --default-library=shared \
    --cross-file "$WORK/android-cross.ini" --prefer-static \
    -Dc_link_args="-landroid -llog" \
    -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false \
    -Dgl=disabled -Dplain-gl=disabled \
    -Daaudio=disabled \
    -Dmanpage-build=disabled -Dhtml-build=disabled
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

log "ALL DONE"
SO=$(find "$PREFIX" -iname 'libmpv*.so' | head -1)
$STRIP -s "$SO" -o "$WORK/libmpv-stripped.so"
echo "### libmpv.so size (android arm64-v8a, ffmpeg n9.0 + mpv v0.41.0 + libplacebo, h264/hevc hw-only)" >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
SIZE_BYTES=$(stat -c%s "$WORK/libmpv-stripped.so")
echo "$SIZE_BYTES bytes ($(numfmt --to=iec-i --suffix=B "$SIZE_BYTES"))" >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
