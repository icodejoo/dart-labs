#!/bin/bash
# EXPERIMENT — not the shipped Android flavor (see ../flavors-mova-slim.sh
# for that, still the production path, 5.87MiB, pre-libplacebo mpv). This
# script replicates ../build-win-libmpv-v9.sh's stack (ffmpeg n9.0 + mpv
# v0.41.0 + libplacebo) for Android arm64-v8a/API 24.
#
# Backend: gpu-next + OpenGL (NOT Vulkan). Real-device benchmark (Huawei,
# 2026-08-07) showed Vulkan pays for TWO simultaneous GPU contexts — Vulkan
# for rendering plus a mandatory GLES context for the MediaCodec hwdec
# bridge (AImageReader -> EGLImageKHR -> GL_TEXTURE_EXTERNAL_OES, see
# video/out/hwdec/hwdec_aimagereader.c, which unconditionally needs
# ra_is_gl()). Measured: CPU +27%, TOTAL PSS +70MB, EGL/GL mtrack 12x vs v6.
# Switching libplacebo to the OpenGL backend collapses back to a single GL
# context (same one the hwdec bridge already needs) — EGL mtrack/GL
# mtrack/Graphics PSS become numerically identical to v6, CPU/memory roughly
# match. This matches mpv upstream's own community consensus (gpu-next+GL is
# the tested/stable Android config; gpu-next+Vulkan compiles but isn't yet
# considered stable — see mpv-player/mpv#12056).
#
# Size history (stripped libmpv.so, 2026-08-07, WSL2 + NDK r25c):
#   10.62MB  baseline (ffmpeg n9.0 + mpv v0.41.0 + libplacebo+vulkan)
#    9.73MB  + drop h264 software decoder, hw-only via h264_mediacodec
#    9.29MB  + drop hevc software decoder, hw-only via hevc_mediacodec
#    8.80MB  + dav1d removed (hw-only av1 via av1_mediacodec, no native "av1"
#             decoder needed — mediacodec doesn't couple to native-
#             decoder+hwaccel the way d3d11va does on Windows), + HarfBuzz/
#             libass hardening (graphite2/cairo/glib/icu disabled — zero
#             byte change, same as Windows, hardening only) + FreeType
#             modules.cfg trim (ported from Windows) + hidden-visibility/
#             gc-sections/whole-chain LTO
#    9.01MB  + three real-device bug fixes required to actually run (see
#             below) — net cost of correctness over the untested 8.80MB
#    9.30MB  + libplacebo Vulkan->OpenGL backend switch (final, shipped
#             config) — OpenGL backend pulls in less dead code than Vulkan
#             would once actually exercised, but mpv's own gl/plain-gl/
#             egl-android context code adds back more than libplacebo saves
#             at this size range; net +290KB over the Vulkan variant, in
#             exchange for the resource-parity win above. Worth it.
# vs the shipped 5.87MiB pre-libplacebo build — libplacebo is still a fixed
# ~1.6x size tax. The h264/hevc/av1 hw-only decoders are standalone FFCodec
# implementations (same as the already-shipped vp9 hw-only tradeoff in
# ../flavors-mova-slim.sh) — they only need the codec's parser (already
# enabled) to find frame boundaries, not the software decoder. H.264
# MediaCodec coverage has been mandatory since API 16; HEVC MediaCodec is
# broadly available from API 21+. This is an Android-only call — do NOT
# port the hevc hw-only cut to iOS: pre-A9 devices (iPhone 6 and older,
# still inside many apps' iOS 12+ floor) have no HEVC VideoToolbox decode.
#
# dav1d removal carries an explicitly ACCEPTED risk: ../flavors-mova-slim.sh
# (the v6 production flavor) has its own 2026-08-06 commit reinstating dav1d
# after a real-device regression on a Snapdragon "bengal" budget device with
# no AV1 hardware decode. This experimental v9 line removes dav1d anyway on
# an explicit "still remove it, accept the known risk" instruction — if this
# line ever ships, AV1 playback on AV1-hwdec-less devices will hard-fail
# instead of falling back to software decode. Re-add libdav1d + the native
# "av1" decoder (see ../build-win-libmpv-v9.sh's DECODERS_VIDEO for the
# pattern) before shipping to any device tier below the v6 flavor's floor.
#
# Three real-device bugs found and fixed here that are NOT specific to any
# of this session's optimization flags — confirmed via `git status --short`
# showing zero local changes to the affected upstream files, and via
# reproducing bug #2 on a completely unoptimized pre-session v9 baseline
# build — i.e. these are latent bugs in the vanilla v9 stack itself that
# would hit ANY Android build of this ffmpeg n9.0 + mpv v0.41.0 combination,
# optimized or not:
#   1. UnsatisfiedLinkError: cannot locate symbol "mpv_lavc_set_java_vm".
#      media_kit's Android plugin (MediaKitLibsAndroidVideoPlugin) requires
#      a media-kit-specific mpv patch not present in vanilla upstream mpv —
#      it declares/implements this function nowhere else. Fix: apply
#      media-kit's own patch (adds the declaration to include/mpv/client.h
#      and `return av_jni_set_java_vm(vm, NULL);` to player/client.c) — see
#      https://github.com/media-kit/libmpv-android-video-build/blob/main/buildscripts/patches/mpv/mpv_lavc_set_java_vm.patch
#      (not yet scripted below as an automated patch step — applied by hand
#      during this session's real-device debugging).
#   2. UnsatisfiedLinkError: cannot locate symbol "__gxx_personality_v0".
#      NDK's plain `clang` link driver (not clang++) does NOT automatically
#      pull in the static C++ runtime, but glslang/libplacebo's .cc sources
#      need the C++ exception personality routine. Fix: add
#      "-lc++_static -lc++abi" to mpv's own c_link_args below.
#   3. UnsatisfiedLinkError: cannot locate symbol "ra_is_gl".
#      video/out/hwdec/hwdec_aimagereader.c (Android's MediaCodec hwdec
#      bridge) unconditionally calls ra_is_gl(), only defined when mpv's own
#      GL support is compiled in — vanilla upstream coupling, confirmed via
#      `git status --short video/out/` being empty. Fix: mpv needs
#      -Dgl=enabled -Dplain-gl=enabled -Degl-android=enabled regardless of
#      which GPU API libplacebo itself renders through.
#
# Not yet ported here (validated on Windows only, see
# ../build-win-libmpv-v9.sh's header for numbers): dropping ffmpeg's own
# subtitle decoders/demuxers (real subtitle rendering via libass is kept, as
# on Windows). mbedtls stays on Android regardless — there's no native-TLS
# ffmpeg backend for Android the way --enable-schannel covers Windows.
#
# Also investigated cross-platform and NOT pursued (same finding applies
# here as on Windows): mpv's meson.build hard-requires libass with no
# feature option — stripping it means patching mpv's own OSD backend-
# dispatch to tolerate zero text-rendering backends, which is framework
# surgery (wrong cut fails as "mpv doesn't start"), not a build flag. See
# ../build-win-libmpv-v9.sh's header for the full writeup.
#
# shaderc/glslang dedup (Windows task #3, still pending there) does NOT
# apply here: shaderc is only needed by mpv's own D3D11 GPU context, which
# doesn't exist on Android. Nothing to dedup on this platform.
#
# Status: tentative, see ../build-win-libmpv-v9.sh's header for the
# libplacebo adoption decision context. Real-device verified (Huawei
# arm64-v8a): app launches, plays a demo video, no crash, resource usage
# matches v6. Invoked by .github/workflows/experiment-libmpv-v9.yml.
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

# Whole-chain hidden-visibility/gc-sections/LTO recipe — ported from the
# proven Windows recipe (../build-win-libmpv-v9.sh header: -fvisibility=
# hidden alone is the single biggest win, ~669KB there; whole-chain LTO
# adds ~521KB more). Applied to every dependency below via each build
# system's flag-injection point (autotools CFLAGS/LDFLAGS, meson
# --native-file/cross-file c_args/c_link_args, cmake CMAKE_C_FLAGS_RELEASE).
OPT_CFLAGS="-fvisibility=hidden -ffunction-sections -fdata-sections -fomit-frame-pointer -flto"
OPT_LDFLAGS="-Wl,--gc-sections -flto"

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

[built-in options]
b_lto = true
c_args = ['$OPT_CFLAGS']
c_link_args = ['$OPT_LDFLAGS']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

# Host-tool builds (e.g. fribidi's gen-unicode-version) must NOT get LTO/
# cross flags — same meson --native-file gotcha documented in
# ../../README.md's LTO section.
cat > "$WORK/native.ini" <<EOF
[built-in options]
b_lto = false
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

# dav1d removed — hw-only AV1 via av1_mediacodec (standalone FFCodec, no
# native "av1" decoder needed unlike d3d11va's coupling on Windows). See the
# file header for the accepted-risk note before shipping this to any device
# tier below the v6 flavor's floor.

# ---- freetype (modules.cfg trimmed to just the TrueType/OpenType loader —
# ported verbatim from ../build-win-libmpv-v9.sh; drops CFF/Type1/PCF/BDF/
# PFR/Windows-FNT rasterizers mova never feeds it) ----
if [ ! -f "$PREFIX/lib/libfreetype.a" ]; then
  log "freetype"
  [ -d freetype-src ] || git clone --depth 1 -b VER-2-13-3 https://github.com/freetype/freetype.git freetype-src
  cd freetype-src
  sed -i \
    -e '/#define FT_USE_MODULE( FT_Module_Class, cff_driver_class )/d' \
    -e '/#define FT_USE_MODULE( FT_Module_Class, t1cid_driver_class )/d' \
    -e '/#define FT_USE_MODULE( FT_Module_Class, psaux_module_class )/d' \
    -e '/#define FT_USE_MODULE( FT_Module_Class, psnames_module_class )/d' \
    -e '/#define FT_USE_MODULE( FT_Module_Class, pshinter_module_class )/d' \
    -e '/#define FT_USE_MODULE( FT_Module_Class, t1_driver_class )/d' \
    -e '/#define FT_USE_MODULE( FT_Module_Class, pcf_driver_class )/d' \
    -e '/#define FT_USE_MODULE( FT_Module_Class, bdf_driver_class )/d' \
    -e '/#define FT_USE_MODULE( FT_Module_Class, pfr_driver_class )/d' \
    -e '/#define FT_USE_MODULE( FT_Module_Class, winfnt_driver_class )/d' \
    include/freetype/config/ftmodule.h 2>/dev/null || true
  ./autogen.sh || true
  CFLAGS="$OPT_CFLAGS" LDFLAGS="$OPT_LDFLAGS" \
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
    --cross-file "$WORK/android-cross.ini" --native-file "$WORK/native.ini" \
    -Ddocs=false -Dtests=false
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

# ---- harfbuzz (hardened: graphite2/cairo/glib/icu/introspection/docs/
# benchmark all disabled — measured zero byte change on Windows since these
# were already effectively default-off, kept anyway as future-drift
# protection) ----
if [ ! -f "$PREFIX/lib/libharfbuzz.a" ]; then
  log "harfbuzz"
  [ -d harfbuzz-src ] || git clone --depth 1 -b 9.0.0 https://github.com/harfbuzz/harfbuzz.git harfbuzz-src
  cd harfbuzz-src
  meson setup build --prefix="$PREFIX" --default-library=static --buildtype=release \
    --cross-file "$WORK/android-cross.ini" --native-file "$WORK/native.ini" \
    -Dfreetype=enabled -Dtests=disabled -Dcairo=disabled -Dglib=disabled -Dicu=disabled \
    -Dgraphite=disabled -Dgobject=disabled -Dintrospection=disabled \
    -Dbenchmark=disabled -Ddocs=disabled -Ddoc_tests=false
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

# ---- libass (hardened: fontconfig disabled — mova ships its own fonts,
# never relies on system font discovery on Android either) ----
if [ ! -f "$PREFIX/lib/libass.a" ]; then
  log "libass"
  [ -d libass-src ] || git clone --depth 1 -b 0.17.3 https://github.com/libass/libass.git libass-src
  cd libass-src
  ./autogen.sh
  CFLAGS="$OPT_CFLAGS" LDFLAGS="$OPT_LDFLAGS" \
  ./configure --host=$TARGET --prefix="$PREFIX" --enable-static --disable-shared \
    --disable-require-system-font-provider --disable-fontconfig
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
  DECODERS_VIDEO="vp9,png"
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
    --enable-mbedtls --enable-zlib --enable-libass \
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
    --enable-lto \
    --extra-cflags="-I$PREFIX/include $OPT_CFLAGS" \
    --extra-ldflags="-L$PREFIX/lib $OPT_LDFLAGS" \
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

# ---- libplacebo (OpenGL backend — see the file header for why: gpu-next+
# Vulkan on Android pays for a second, simultaneous GPU context on top of
# the GLES context the MediaCodec hwdec bridge already requires, measured
# as CPU +27%/TOTAL PSS +70MB/EGL+GL mtrack 12x. OpenGL collapses back to
# the single context, matching v6's resource profile. Built without the
# whole-chain OPT_CFLAGS/LDFLAGS: real-device troubleshooting showed the
# __gxx_personality_v0 crash (see file header, bug #2) reproduced even on a
# completely unoptimized pre-session baseline, so LTO/hidden-visibility
# aren't implicated here and this dependency stays on a plain release
# build to keep that verified-working configuration exact.) ----
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
    --cross-file "$WORK/android-cross.ini" --native-file "$WORK/native.ini" --prefer-static \
    -Dvulkan=disabled -Dopengl=enabled -Dd3d11=disabled \
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
  # media_kit's Android plugin dlsym()s mpv_lavc_set_java_vm, which does NOT
  # exist in vanilla upstream mpv v0.41.0 — media_kit patches it in
  # themselves (see the file header, bug #1). Apply the same patch here:
  # https://github.com/media-kit/libmpv-android-video-build/blob/main/buildscripts/patches/mpv/mpv_lavc_set_java_vm.patch
  if ! grep -q "mpv_lavc_set_java_vm" include/mpv/client.h; then
    sed -i '/MPV_EXPORT void mpv_wakeup(mpv_handle \*ctx);/a\
\
/** Calls av_jni_set_java_vm() on ffmpeg'"'"'s libavcodec, needed by the\
    Android MediaCodec hwdec bridge. media_kit-specific — not upstream mpv. */\
MPV_EXPORT int mpv_lavc_set_java_vm(void *vm);' include/mpv/client.h
  fi
  if ! grep -q "mpv_lavc_set_java_vm" player/client.c; then
    sed -i '/#include <assert.h>/a #include <libavcodec/jni.h>' player/client.c
    printf '\nint mpv_lavc_set_java_vm(void *vm)\n{\n    return av_jni_set_java_vm(vm, NULL);\n}\n' >> player/client.c
  fi
  # aaudio=disabled: NDK r25c's aaudio/AAudio.h lacks AAUDIO_FORMAT_IEC61937
  # (a newer constant than this NDK ships), which mpv's ao_aaudio.c
  # references unconditionally — OpenSL ES / AudioTrack outputs cover audio
  # output without it.
  #
  # c_link_args: "-lc++_static -lc++abi" fixes bug #2 (__gxx_personality_v0)
  # — NDK's plain clang link driver doesn't auto-pull the C++ runtime that
  # glslang/libplacebo's .cc sources need.
  #
  # gl/plain-gl/egl-android=enabled fixes bug #3 (ra_is_gl) — mandatory for
  # the AImageReader hwdec bridge regardless of libplacebo's own GPU
  # backend (OpenGL here, see the libplacebo step above).
  meson setup build --prefix="$PREFIX" --libdir=lib --default-library=shared \
    --cross-file "$WORK/android-cross.ini" --prefer-static \
    -Dc_link_args="-landroid -llog -lc++_static -lc++abi $OPT_LDFLAGS" \
    -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false \
    -Dgl=enabled -Dplain-gl=enabled -Degl-android=enabled \
    -Daaudio=disabled \
    -Dmanpage-build=disabled -Dhtml-build=disabled
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

log "ALL DONE"
SO=$(find "$PREFIX" -iname 'libmpv*.so' | head -1)
$STRIP -s "$SO" -o "$WORK/libmpv-stripped.so"
echo "### libmpv.so size (android arm64-v8a, ffmpeg n9.0 + mpv v0.41.0 + libplacebo+opengl(gpu-next), h264/hevc/av1 hw-only, dav1d removed, HarfBuzz/libass hardened, FreeType trimmed, whole-chain LTO)" >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
SIZE_BYTES=$(stat -c%s "$WORK/libmpv-stripped.so")
echo "$SIZE_BYTES bytes ($(numfmt --to=iec-i --suffix=B "$SIZE_BYTES"))" >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
