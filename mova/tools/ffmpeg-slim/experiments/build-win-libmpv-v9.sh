#!/bin/bash
# EXPERIMENT — not the shipped windows flavor (see ../flavors-mova-slim.sh's
# README for that). Validated locally in WSL2/mingw cross-compile (not
# MSYS2), 2026-08-07: ffmpeg n9.0 + mpv v0.41.0 + libplacebo(d3d11+glslang)
# → libmpv-2.dll, 13.60MB stripped. Status: tentative — libplacebo is a hard
# mpv>=0.36 dependency (no more non-libplacebo GPU renderer to fall back to)
# and roughly doubles size vs the shipped pre-libplacebo Android flavor
# (5.87MiB → this stack's Android counterpart came out at 10.62MB). Decision
# on whether to adopt this across platforms is NOT made yet — this script
# exists to keep the validated recipe + its pitfalls reproducible, not as a
# production build. Invoked by .github/workflows/experiment-libmpv-v9.yml.
set -e
set -x

WORK=/tmp/mova-win-libmpv
CROSS=x86_64-w64-mingw32
PREFIX="$WORK/prefix"
mkdir -p "$WORK" "$PREFIX"
cd "$WORK"

export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG="pkg-config --static"
# meson's cxx.find_library() (used by libplacebo for glslang/SPIRV-Tools —
# those don't ship .pc files) does a trial link via the compiler rather than
# pkg-config, so it only sees $PREFIX/lib via the compiler's own search path.
# GCC/mingw-gcc both honor LIBRARY_PATH/CPATH env vars for -L/-I, which is
# the one mechanism that reaches find_library without editing libplacebo's
# meson.build.
export LIBRARY_PATH="$PREFIX/lib"
export CPATH="$PREFIX/include"
# Bisection note: -ffunction-sections/-fdata-sections + --gc-sections
# globally exported here regressed the final stripped DLL 13.75MB -> 16.66MB
# (confirmed by resetting CMAKE_C/CXX_FLAGS for glslang/spirv-cross alone —
# their .a files shrank back but the DLL didn't, proving the regression was
# in ffmpeg/mbedtls/dav1d/etc, not glslang). Left unset deliberately —
# gc-sections without function/data-sections was proven a no-op for this
# dependency set (13.75MB either way), so nothing is being given up.
NPROC=$(nproc)

log() { echo "=== $1 ==="; }

# ---- zlib ----
if [ ! -f "$PREFIX/lib/libz.a" ]; then
  log "zlib"
  [ -d zlib-src ] || git clone --depth 1 -b v1.3.1 https://github.com/madler/zlib.git zlib-src
  cd zlib-src
  CC=$CROSS-gcc AR=$CROSS-ar ./configure --prefix="$PREFIX" --static
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
  cmake -G Ninja \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_C_COMPILER=$CROSS-gcc \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
    ..
  ninja
  ninja install
  cd "$WORK"
fi

# meson cross file — regenerated unconditionally (not gated on any single
# dep's skip-if-built check) since dav1d/fribidi/harfbuzz all reuse it.
cat > mingw-cross.ini <<EOF
[binaries]
c = '$CROSS-gcc'
cpp = '$CROSS-g++'
ar = '$CROSS-ar'
strip = '$CROSS-strip'
pkg-config = 'pkg-config'
windres = '$CROSS-windres'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

# ---- dav1d (meson cross) ----
if [ ! -f "$PREFIX/lib/libdav1d.a" ]; then
  log "dav1d"
  [ -d dav1d-src ] || git clone --depth 1 -b 1.4.3 https://code.videolan.org/videolan/dav1d.git dav1d-src
  cd dav1d-src
  meson setup build --prefix="$PREFIX" --default-library=static --buildtype=release \
    --cross-file "$WORK/mingw-cross.ini" -Denable_tools=false -Denable_tests=false
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
  ./configure --host=$CROSS --prefix="$PREFIX" --enable-static --disable-shared \
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
    --cross-file "$WORK/mingw-cross.ini" -Ddocs=false -Dtests=false
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

# ---- harfbuzz (needs freetype) ----
if [ ! -f "$PREFIX/lib/libharfbuzz.a" ]; then
  log "harfbuzz"
  [ -d harfbuzz-src ] || git clone --depth 1 -b 9.0.0 https://github.com/harfbuzz/harfbuzz.git harfbuzz-src
  cd harfbuzz-src
  meson setup build --prefix="$PREFIX" --default-library=static --buildtype=release \
    --cross-file "$WORK/mingw-cross.ini" -Dfreetype=enabled -Dtests=disabled -Dcairo=disabled -Dglib=disabled -Dicu=disabled
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

# ---- libass (needs freetype+fribidi+harfbuzz) ----
if [ ! -f "$PREFIX/lib/libass.a" ]; then
  log "libass"
  [ -d libass-src ] || git clone --depth 1 -b 0.17.3 https://github.com/libass/libass.git libass-src
  cd libass-src
  ./autogen.sh
  ./configure --host=$CROSS --prefix="$PREFIX" --enable-static --disable-shared --disable-require-system-font-provider
  make -j"$NPROC"
  make install
  cd "$WORK"
fi

log "deps done, building ffmpeg n9.0"

# ---- ffmpeg n9.0, mova slim decoder list, windows hwaccel ----
if [ ! -f "$PREFIX/lib/libavcodec.a" ]; then
  [ -d ffmpeg-src ] || git clone --depth 1 --branch n9.0 https://github.com/FFmpeg/FFmpeg.git ffmpeg-src
  cd ffmpeg-src

  # Same component lists as ../flavors-mova-slim.sh (Android), minus the
  # mediacodec hw decoders (no Android MediaCodec on Windows) plus
  # d3d11va/dxva2 hwaccel entries for the same codec set (h264/hevc/vp9/av1).
  # Base is --disable-everything (blanket: decoders/encoders/hwaccels/muxers/
  # demuxers/parsers/bsfs/protocols/filters/indevs/outdevs all off) instead of
  # per-category --disable-X, so nothing new that ffmpeg adds a default-on
  # component for (e.g. a new hwaccel/bsf) sneaks in unlisted — every enabled
  # piece below is explicit and diffable against the Android list.
  DECODERS_VIDEO="h264,hevc,vp9,libdav1d,png"
  DECODERS_AUDIO="aac,aac_latm,mp3,mp3float,opus,ac3,eac3,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8"
  DECODERS_SUB="ass,ssa,subrip,text,webvtt,movtext"
  DECODERS="$DECODERS_VIDEO,$DECODERS_AUDIO,$DECODERS_SUB"
  ENCODERS="png"
  PARSERS="h264,hevc,vp9,av1,png,aac,aac_latm,ac3,flac,opus,vorbis,mpegaudio"
  DEMUXERS="mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ac3,eac3,ass,srt,webvtt"
  PROTOCOLS="file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp"
  BSFS="null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts"
  HWACCELS="h264_d3d11va,h264_d3d11va2,h264_dxva2,hevc_d3d11va,hevc_d3d11va2,hevc_dxva2,vp9_d3d11va,vp9_d3d11va2,vp9_dxva2,av1_d3d11va,av1_d3d11va2,av1_dxva2"

  # --disable-autodetect is the systemic version of the vulkan/iconv disables
  # below — every [autodetect] library (per configure --help) only links in
  # if this build explicitly --enable's it, so nothing sneaks in just because
  # its headers happen to be reachable from this cross sysroot.
  # Ref: github.com/superuser404notfound/FFmpegBuild's COMMON_FLAGS.
  ./configure \
    --target-os=mingw32 --arch=x86_64 --enable-cross-compile --cross-prefix=$CROSS- \
    --pkg-config=pkg-config \
    \
    --disable-everything \
    \
    --disable-gpl --disable-nonfree --enable-version3 \
    --enable-static --disable-shared --pkg-config-flags=--static \
    --disable-doc --disable-programs --disable-avdevice \
    --disable-vulkan --disable-iconv \
    --disable-autodetect \
    --disable-swscale-alpha --disable-bzlib --disable-symver --disable-debug \
    \
    --enable-small --enable-optimizations \
    \
    --enable-mbedtls --enable-zlib --enable-libdav1d --enable-libass \
    \
    --enable-avutil --enable-avcodec --enable-avfilter --enable-avformat \
    --enable-swscale --enable-swresample \
    \
    --enable-decoder="$DECODERS" \
    --enable-encoder="$ENCODERS" \
    --enable-parser="$PARSERS" \
    --enable-demuxer="$DEMUXERS" \
    --enable-protocol="$PROTOCOLS" \
    --enable-bsf="$BSFS" \
    --enable-hwaccel="$HWACCELS" \
    \
    --enable-network \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib" \
    --extra-libs="-lmbedtls -lmbedx509 -lmbedcrypto -lws2_32 -lbcrypt" \
    --prefix="$PREFIX"
  make -j"$NPROC"
  make install
  cd "$WORK"
fi

# Second cross file, with cpp + wine64 exe_wrapper — mpv's meson build runs
# small compiled test binaries under wine to probe target behavior.
cat > "$WORK/mingw-cross-mpv.ini" <<EOF
[binaries]
c = '$CROSS-gcc'
cpp = '$CROSS-g++'
ar = '$CROSS-ar'
strip = '$CROSS-strip'
pkg-config = 'pkg-config'
windres = '$CROSS-windres'
dlltool = '$CROSS-dlltool'
exe_wrapper = 'wine64'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

MINGW_TOOLCHAIN="$WORK/mingw-toolchain.cmake"
cat > "$MINGW_TOOLCHAIN" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER $CROSS-gcc)
set(CMAKE_CXX_COMPILER $CROSS-g++)
set(CMAKE_RC_COMPILER $CROSS-windres)
set(CMAKE_FIND_ROOT_PATH /usr/$CROSS;$PREFIX)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

# ---- glslang (GLSL->SPIR-V compiler, libplacebo's d3d11 backend needs it) ----
if [ ! -f "$PREFIX/lib/libglslang.a" ]; then
  log "glslang"
  if [ ! -d glslang-src ]; then
    git clone --depth 1 -b 14.3.0 https://github.com/KhronosGroup/glslang.git glslang-src
    (cd glslang-src && python3 update_glslang_sources.py)
  fi
  # ENABLE_OPT=OFF drops the SPIR-V optimizer (SPIRV-Tools-opt, ~9.4MB of the
  # .a — the single biggest non-ffmpeg piece) — libplacebo's shaders are
  # hand-written and small, not codegen output that benefits from an
  # optimization pass, so this is dead weight for our use case.
  # -ffunction-sections/-fdata-sections regressed this specific library hard
  # (libSPIRV.a 1.07MB -> 8.7MB, final DLL +2.9MB) — heavily templated C++
  # like glslang relies on COMDAT/linkonce section folding to dedupe
  # template instantiations across TUs; forcing everything into its own
  # section seems to defeat that on GNU ld (no --icf here, unlike lld/gold),
  # so gc-sections' "drop unreferenced sections" doesn't claw it back.
  # Override CXXFLAGS/CFLAGS back to a plain Release build for this lib only.
  cmake -S glslang-src -B glslang-build -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$MINGW_TOOLCHAIN" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="" -DCMAKE_CXX_FLAGS="" \
    -DBUILD_SHARED_LIBS=OFF -DENABLE_GLSLANG_BINARIES=OFF \
    -DENABLE_SPVREMAPPER=OFF -DENABLE_CTEST=OFF -DENABLE_HLSL=OFF \
    -DALLOW_EXTERNAL_SPIRV_TOOLS=OFF -DENABLE_OPT=OFF
  cmake --build glslang-build -j"$NPROC"
  cmake --install glslang-build
fi

# ---- spirv-cross (SPIR-V->HLSL translator, libplacebo's d3d11 backend) ----
if [ ! -f "$PREFIX/lib/libspirv-cross-c.a" ]; then
  log "spirv-cross"
  [ -d spirv-cross-src ] || git clone --depth 1 -b vulkan-sdk-1.3.296.0 https://github.com/KhronosGroup/SPIRV-Cross.git spirv-cross-src
  # Only the GLSL->HLSL path is used (libplacebo's d3d11 backend translates
  # its GLSL shaders to HLSL). GLSL itself can't be disabled — CompilerHLSL
  # inherits from CompilerGLSL — but MSL/CPP/Reflect/Util are unrelated
  # unused backends/utilities.
  cmake -S spirv-cross-src -B spirv-cross-build -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$MINGW_TOOLCHAIN" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="" -DCMAKE_CXX_FLAGS="" \
    -DSPIRV_CROSS_SHARED=OFF -DSPIRV_CROSS_STATIC=ON \
    -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF \
    -DSPIRV_CROSS_ENABLE_C_API=ON \
    -DSPIRV_CROSS_ENABLE_MSL=OFF -DSPIRV_CROSS_ENABLE_CPP=OFF \
    -DSPIRV_CROSS_ENABLE_REFLECT=OFF -DSPIRV_CROSS_ENABLE_UTIL=OFF \
    -DSPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS=ON
  cmake --build spirv-cross-build -j"$NPROC"
  cmake --install spirv-cross-build
  # libplacebo looks for this via pkg-config; upstream CMake install doesn't
  # generate one, so write it by hand (mirrors what glslang's own CMake
  # export provides via find_package, which meson can't consume directly).
  mkdir -p "$PREFIX/lib/pkgconfig"
  cat > "$PREFIX/lib/pkgconfig/spirv-cross-c-shared.pc" <<EOF2
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: spirv-cross-c-shared
Description: C API for SPIRV-Cross
Version: 0.62.0
Libs: -L\${libdir} -lspirv-cross-c -lspirv-cross-core -lspirv-cross-glsl -lspirv-cross-hlsl
Cflags: -I\${includedir} -I\${includedir}/spirv_cross
EOF2
fi

# ---- libplacebo (mpv >=0.36 hard-requires it as its GPU render abstraction;
#      d3d11-only — no vulkan/opengl — since this is a Windows-native build
#      and d3d11va is already the hwaccel path chosen above. d3d11 backend
#      needs glslang (GLSL->SPIR-V) + spirv-cross (SPIR-V->HLSL) — that's the
#      actual shader translation path, not optional infra like vulkan/opengl.) ----
if [ ! -f "$PREFIX/lib/libplacebo.a" ]; then
  log "libplacebo"
  [ -d libplacebo-src ] || git clone --recursive --depth 1 https://github.com/haasn/libplacebo.git libplacebo-src
  cd libplacebo-src
  # cxx.find_library() for glslang/SPIRV-Tools does a compiler trial-link, not
  # a pkg-config lookup, so PKG_CONFIG_PATH/LIBRARY_PATH don't reach it (mingw
  # gcc here doesn't honor LIBRARY_PATH for cross target search either).
  # -Dvulkan-sdk feeds meson's own vulkan_lib_dirs → dirs: kwarg on exactly
  # those find_library() calls (see src/glsl/meson.build) — repurposing it to
  # point at our prefix instead of patching the source.
  # --prefer-static also matters beyond linking preference here: it flips
  # which find_library() branch in src/glsl/meson.build runs first (static
  # attempt with required:false vs. the required:true fallback, which lacks
  # a dirs: kwarg on its 'glslang' lookup and would hard-fail to find it in
  # our prefix otherwise).
  meson setup build --prefix="$PREFIX" --default-library=static --buildtype=release \
    --cross-file "$WORK/mingw-cross-mpv.ini" --prefer-static \
    -Dvulkan=disabled -Dopengl=disabled -Dd3d11=enabled \
    -Dglslang=enabled -Dshaderc=disabled -Ddemos=false -Dtests=false \
    -Dvulkan-sdk="$PREFIX"
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

log "ffmpeg done, building mpv"

# ---- mpv v0.41.0 (latest release) — NOT the old pre-libplacebo commit that
# ../flavors-mova-slim.sh's Android build (and the original windows job) use:
# that commit's ffmpeg-6.0-era API usage (FF_PROFILE_* macros,
# AVCodec.sample_fmts/ch_layouts) doesn't compile against ffmpeg n9.0
# headers, and the breaks aren't a one-line patch (AVCodec.sample_fmts/
# ch_layouts were removed, replaced by avcodec_get_supported_config() — a
# real API restructure, not a rename). Bumping mpv to fix that is what pulls
# in libplacebo. ----
if [ ! -f "$PREFIX/lib/libmpv.dll.a" ] && [ ! -f "$PREFIX/lib/libmpv-2.dll" ]; then
  [ -d mpv-src ] || git clone --depth 1 --branch v0.41.0 https://github.com/mpv-player/mpv.git mpv-src
  cd mpv-src
  # gl=enabled is mpv's hardcoded default (not auto) — without explicitly
  # disabling it, vo_opengl/win32 gl context/dxinterop compile in alongside
  # d3d11 even though we only want the d3d11 path. Same for manpage/html
  # doc generation, which cplayer=false alone doesn't skip.
  meson setup build --prefix="$PREFIX" --libdir=lib --default-library=shared \
    --cross-file "$WORK/mingw-cross-mpv.ini" --prefer-static \
    -Dc_link_args="-lstdc++ -lole32 -lrpcrt4 -Wl,--gc-sections" \
    -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false \
    -Dgl=disabled -Dplain-gl=disabled -Degl-angle=disabled -Degl-angle-lib=disabled -Degl-angle-win32=disabled \
    -Dmanpage-build=disabled -Dhtml-build=disabled
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

log "ALL DONE"
DLL=$(find "$PREFIX" -iname 'libmpv*.dll' | head -1)
$CROSS-strip -s "$DLL" -o "$WORK/libmpv-2-stripped.dll"
echo "### libmpv-2.dll size (windows x86_64, ffmpeg n9.0 + mpv v0.41.0 + libplacebo)" >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
SIZE_BYTES=$(stat -c%s "$WORK/libmpv-2-stripped.dll")
echo "$SIZE_BYTES bytes ($(numfmt --to=iec-i --suffix=B "$SIZE_BYTES" 2>/dev/null || echo "$SIZE_BYTES B"))" >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
