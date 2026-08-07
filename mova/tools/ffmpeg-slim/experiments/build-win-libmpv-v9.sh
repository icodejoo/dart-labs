#!/bin/bash
# EXPERIMENT — not the shipped windows flavor (see ../flavors-mova-slim.sh's
# README for that). Validated locally in WSL2/mingw cross-compile (not
# MSYS2). Status: tentative — libplacebo is a hard mpv>=0.36 dependency (no
# more non-libplacebo GPU renderer to fall back to) and roughly doubles size
# vs the shipped pre-libplacebo Android flavor (5.87MiB → this stack's
# Android counterpart lands at 9.29MB after its own hw-only cuts). Decision
# on whether to adopt this across platforms is NOT made yet — this script
# exists to keep the validated recipe + its pitfalls reproducible, not as a
# production build. Invoked by .github/workflows/experiment-libmpv-v9.yml.
#
# Size history (stripped libmpv-2.dll, 2026-08-07):
#   13.60MB  baseline (ffmpeg n9.0 + mpv v0.41.0 + libplacebo(d3d11+glslang))
#   12.04MB  + mbedtls -> --enable-schannel (Windows' native TLS backend —
#            zero extra build, just -lsecur32/-lncrypt/-lcrypt32, always
#            present; mbedtls conflicts with schannel so it's fully dropped)
#   11.91MB  + trim FreeType's modules.cfg (drop type1/cid/pfr/type42/
#            winfonts/pcf/bdf font-format drivers, svg/sdf rasterizers,
#            lzw/bzip2 compressed-font-stream support — none of it is
#            reachable for the TTF/OTF fonts mova actually renders; gzip
#            stays, sfnt's WOFF/OT-SVG decompression path needs it)
#   (not adopted, superseded below) dropping ffmpeg's own subtitle decoders/
#            demuxers/--enable-libass was tried and measured a ~22KB win,
#            but real-device verification (see the D3D11/shaderc/subtitle
#            work below) confirmed mova can drive real time-synced SRT/ASS
#            rendering through mpv's own sub-add + libass pipeline, so this
#            cut is reverted — subtitle decode/demux and libass are back.
#
# D3D11 hwdec + real subtitle rendering (2026-08-07, real-device verified on
# Windows, not just a size measurement — see mova/tools/ffmpeg-slim/
# experiments/ session notes for the screenshot-verified sub-add/seek/hwdec
# checks):
#   - --enable-d3d11va --enable-dxva2 were MISSING from ffmpeg's configure
#     despite --enable-hwaccel=h264_d3d11va,... being set. Root cause:
#     --disable-autodetect (below) silently disables these too — they're
#     [autodetect]-tagged platform-API switches, a separate gate from the
#     per-codec --enable-hwaccel list. Without them ffmpeg's decoders never
#     advertise AV_HWDEVICE_TYPE_D3D11VA, so mpv's hwdec=auto finds nothing
#     and silently falls back to software — no error, just not accelerated.
#     Verified fix via mpv -v log showing "Using hardware decoding
#     (d3d11va)" (zero-copy) after re-adding them explicitly.
#   - mpv's OWN d3d11 GPU context (video/out/d3d11/*, separate from
#     libplacebo's d3d11 backend) needs shaderc specifically — glslang alone
#     (which libplacebo's d3d11 backend uses) is NOT enough. shaderc vendors
#     its own copy of glslang+SPIRV-Tools (via its git-sync-deps), which is
#     NOT shareable with the standalone glslang/SPIRV-Cross build above
#     without patching shaderc's CMake dependency discovery — real
#     duplication exists here, tracked as a follow-up (not done in this
#     script yet). shaderc's own CMake install also overwrites the shared
#     prefix's glslang cmake-config exports, which is why the final mpv link
#     needs an explicit -lglslang-default-resource-limits (see below) rather
#     than picking it up via meson's normal dependency resolution.
#   - CPU/memory benchmark (h264 hw decode, 720p): D3D11+hwdec 3%CPU/153MB
#     vs GL+dxinterop-hwdec-copy 7.6%/264MB vs D3D11+software 14%/201MB vs
#     GL+software 12.8%/189MB — D3D11 kept on Windows on this basis.
#   - Real subtitle support restored: DECODERS_SUB/ass,srt,webvtt demuxers +
#     --enable-libass are back (see "not adopted, superseded" above).
#     Verified: sub-add loads a real SRT file and auto-syncs to playback PTS
#     across seeks (screenshot-confirmed at multiple seek points), distinct
#     from osd-overlay's immediate/non-time-synced overlay (also verified
#     working, useful for streaming-STT-style incremental captions).
#   - libass itself was prototyped fully removable (patched out of mpv's
#     OSD backend, compiled, linked, real-device tested) — that decision is
#     explicitly NOT made yet, kept as an open question, not adopted here.
#
# HarfBuzz/libass dependency hardening + AV1 hw-only (2026-08-07):
#   - Audited HarfBuzz for accidentally-enabled optional backends
#     (graphite2/gobject/introspection/benchmark/docs/ICU) — none were
#     actually being picked up by the cross-compile pkg-config search (lib
#     size identical bit-for-bit before/after), but pinned them disabled
#     explicitly so a future CI image change (e.g. one that happens to ship
#     fontconfig-dev/graphite2-dev) can't silently pull them back in.
#   - Same audit for libass + fontconfig: default is autodetect-via-pkg-config
#     ("check"), already resolving to off in this cross environment (lib
#     size identical before/after --disable-fontconfig) — made explicit for
#     the same future-drift reason. libass's actual Windows font fallback is
#     DirectWrite, unaffected.
#   - dav1d (external AV1 software decoder) dropped entirely — AV1 now goes
#     through ffmpeg's native "av1" decoder + the av1_d3d11va/av1_d3d11va2/
#     av1_dxva2 hwaccel entries only (those were already listed in HWACCELS
#     but orphaned, since libdav1d has no hwaccel hook at all — hw decode
#     wasn't actually reachable for AV1 before this). Same hw-only pattern
#     already used for h264/hevc/vp9 on Windows. Verified: dropping
#     libdav1d.a (3.29MB static lib) shrank the final unstripped libmpv-2.dll
#     from 40,507,664 to 37,657,104 bytes (~2.78MB) in a like-for-like
#     relink. No AV1 test clip was available to screenshot-verify the hw
#     decode path itself; the hwaccel registration mechanism is identical to
#     h264/hevc/vp9's, which WAS screenshot/log verified in this session.
#
# Still open / not done in this script:
#   - shaderc vendoring its own glslang+SPIRV-Tools copy (see above) —
#     biggest remaining size win, needs shaderc CMake surgery, real risk of
#     API drift against shaderc's pinned glslang revision.
#   - LTO — not attempted here, flagged as a separate higher-risk experiment
#     (mingw cross-compile + LTO has real potential for new breakage).
#   - libass removal from mpv itself — prototyped, works, decision pending.
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

# mbedtls dropped — TLS goes through Windows' native SChannel instead (see
# the --enable-schannel flag in ffmpeg's configure below), which needs zero
# build steps and zero extra size (just three always-present system DLLs).

# meson cross file — regenerated unconditionally (not gated on any single
# dep's skip-if-built check) since fribidi/harfbuzz all reuse it.
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

# dav1d (external AV1 software decoder) intentionally dropped — AV1 now goes
# through ffmpeg's own native "av1" decoder + d3d11va/dxva2 hwaccel only,
# same hw-only pattern already used for h264/hevc/vp9 on Windows.

# ---- freetype ----
if [ ! -f "$PREFIX/lib/libfreetype.a" ]; then
  log "freetype"
  [ -d freetype-src ] || git clone --depth 1 -b VER-2-13-3 https://github.com/freetype/freetype.git freetype-src
  cd freetype-src
  # Drop font-format drivers/rasterizers/compression mova never feeds it —
  # fonts reaching libass here are TTF/OTF (sfnt+truetype+cff), never the
  # legacy PostScript Type1/CID/PFR/Type42, old Windows FNT, or X11
  # PCF/BDF bitmap formats, and never OT-SVG/SDF glyphs or LZW/bzip2-
  # compressed font streams. gzip stays: sfnt's own WOFF and OT-SVG paths
  # (ttsvg.c/sfwoff.c) call FT_Gzip_Uncompress unconditionally, so removing
  # it is a hard link failure, not a soft feature drop.
  sed -i \
    -e '/^FONT_MODULES += type1$/d' \
    -e '/^FONT_MODULES += cid$/d' \
    -e '/^FONT_MODULES += pfr$/d' \
    -e '/^FONT_MODULES += type42$/d' \
    -e '/^FONT_MODULES += winfonts$/d' \
    -e '/^FONT_MODULES += pcf$/d' \
    -e '/^FONT_MODULES += bdf$/d' \
    -e '/^RASTER_MODULES += raster$/d' \
    -e '/^RASTER_MODULES += svg$/d' \
    -e '/^RASTER_MODULES += sdf$/d' \
    -e '/^AUX_MODULES += lzw$/d' \
    -e '/^AUX_MODULES += bzip2$/d' \
    modules.cfg
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
  # cairo/glib/icu were already the ones actually excludable via configure
  # (icu especially — pulls in a large Unicode data table if it sneaks in).
  # graphite/gobject/introspection/benchmark/docs/doc_tests are all disabled
  # by upstream default already in this cross environment (verified: lib
  # size identical bit-for-bit with/without these flags) — pinned explicit
  # anyway so a CI image change can't silently re-enable them.
  meson setup build --prefix="$PREFIX" --default-library=static --buildtype=release \
    --cross-file "$WORK/mingw-cross.ini" -Dfreetype=enabled -Dtests=disabled -Dcairo=disabled -Dglib=disabled -Dicu=disabled \
    -Dgraphite=disabled -Dgobject=disabled -Dintrospection=disabled -Dbenchmark=disabled -Ddocs=disabled -Ddoc_tests=false
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
  # --disable-fontconfig: libass's Windows font fallback is DirectWrite, not
  # fontconfig. Default is autodetect-via-pkg-config ("check"), which was
  # already resolving to off in this cross environment (lib size identical
  # before/after) — made explicit for the same future-drift reason as
  # harfbuzz above.
  ./configure --host=$CROSS --prefix="$PREFIX" --enable-static --disable-shared --disable-require-system-font-provider --disable-fontconfig
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
  # Subtitle decoders/demuxers + libass ARE enabled — real-device verified
  # (sub-add auto-syncs SRT to playback PTS across seeks); see header.
  DECODERS_VIDEO="h264,hevc,vp9,av1,png"
  DECODERS_AUDIO="aac,aac_latm,mp3,mp3float,opus,ac3,eac3,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8"
  DECODERS_SUB="ass,ssa,subrip,text,webvtt,movtext"
  DECODERS="$DECODERS_VIDEO,$DECODERS_AUDIO,$DECODERS_SUB"
  ENCODERS="png"
  PARSERS="h264,hevc,vp9,av1,png,aac,aac_latm,ac3,flac,opus,vorbis,mpegaudio"
  DEMUXERS="mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ac3,eac3,ass,srt,webvtt"
  PROTOCOLS="file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp"
  BSFS="null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,dump_extradata,setts"
  HWACCELS="h264_d3d11va,h264_d3d11va2,h264_dxva2,hevc_d3d11va,hevc_d3d11va2,hevc_dxva2,vp9_d3d11va,vp9_d3d11va2,vp9_dxva2,av1_d3d11va,av1_d3d11va2,av1_dxva2"

  # --disable-autodetect is the systemic version of the vulkan/iconv disables
  # below — every [autodetect] library (per configure --help) only links in
  # if this build explicitly --enable's it, so nothing sneaks in just because
  # its headers happen to be reachable from this cross sysroot.
  # Ref: github.com/superuser404notfound/FFmpegBuild's COMMON_FLAGS.
  # Gotcha this caught: --enable-d3d11va/--enable-dxva2 are ALSO
  # [autodetect] flags (platform-API-level switches, separate from
  # --enable-hwaccel=h264_d3d11va,... below which only registers per-codec
  # hwaccel entries) — --disable-autodetect silently swallowed them too.
  # Without them, ffmpeg's h264 decoder never advertises
  # AV_HWDEVICE_TYPE_D3D11VA in its hw_configs, so mpv's hwdec_autoprobe
  # finds nothing to try and quietly falls back to software — no error,
  # just silently not hardware-accelerated. Explicitly re-enabled below.
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
    --enable-d3d11va --enable-dxva2 \
    --enable-schannel --enable-zlib --enable-libass \
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
    --extra-libs="-lws2_32" \
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

# ---- shaderc (mpv's OWN d3d11 GPU context needs this specifically — see
#      header. Vendors its own glslang+SPIRV-Tools copy via git-sync-deps;
#      NOT deduped against the standalone glslang/spirv-cross build above,
#      tracked as a follow-up.) ----
if [ ! -f "$PREFIX/lib/libshaderc_combined.a" ]; then
  log "shaderc"
  [ -d shaderc-src ] || git clone --depth 1 -b v2024.3 https://github.com/google/shaderc.git shaderc-src
  cd shaderc-src
  [ -d third_party/glslang ] || python3 utils/git-sync-deps
  cmake -S . -B build -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$MINGW_TOOLCHAIN" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="" -DCMAKE_CXX_FLAGS="" \
    -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
    -DSHADERC_ENABLE_SHARED_CRT=OFF -DBUILD_SHARED_LIBS=OFF
  cmake --build build -j"$NPROC"
  cmake --install build
  cd "$WORK"
fi

# ---- libplacebo (mpv >=0.36 hard-requires it as its GPU render abstraction;
#      d3d11-only — no vulkan/opengl — since this is a Windows-native build
#      and d3d11va is already the hwaccel path chosen above. d3d11 backend
#      needs glslang (GLSL->SPIR-V) + spirv-cross (SPIR-V->HLSL) — that's the
#      actual shader translation path, not optional infra like vulkan/opengl.
#      shaderc stays disabled here — only mpv's own d3d11 context (below)
#      needs it, libplacebo's d3d11 backend uses glslang directly.) ----
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
  # -Dd3d11=enabled -Dshaderc=enabled: mpv's OWN GPU context module (not
  # libplacebo's), real-device verified to actually render + hw-decode (see
  # header). shaderc's CMake install overwrites the shared prefix's glslang
  # cmake-config exports, so meson's normal dependency() resolution can't
  # find glslang::glslang-default-resource-limits on its own — the explicit
  # -lglslang-default-resource-limits link arg below is that workaround.
  # cplayer stays false: production only ships libmpv-2.dll, not a
  # standalone mpv.exe/mpv.com CLI player.
  meson setup build --prefix="$PREFIX" --libdir=lib --default-library=shared \
    --cross-file "$WORK/mingw-cross-mpv.ini" --prefer-static \
    -Dc_link_args="-lstdc++ -lole32 -lrpcrt4 -Wl,--gc-sections -L$PREFIX/lib -lglslang-default-resource-limits" \
    -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false \
    -Dgl=disabled -Dplain-gl=disabled -Degl-angle=disabled -Degl-angle-lib=disabled -Degl-angle-win32=disabled \
    -Dd3d11=enabled -Dshaderc=enabled \
    -Dmanpage-build=disabled -Dhtml-build=disabled
  ninja -C build
  ninja -C build install
  cd "$WORK"
fi

log "ALL DONE"
DLL=$(find "$PREFIX" -iname 'libmpv*.dll' | head -1)
$CROSS-strip -s "$DLL" -o "$WORK/libmpv-2-stripped.dll"
echo "### libmpv-2.dll size (windows x86_64, ffmpeg n9.0 + mpv v0.41.0 + libplacebo+d3d11/shaderc hwdec, schannel, trimmed freetype, real libass/subtitles, av1 hw-only)" >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
SIZE_BYTES=$(stat -c%s "$WORK/libmpv-2-stripped.dll")
echo "$SIZE_BYTES bytes ($(numfmt --to=iec-i --suffix=B "$SIZE_BYTES" 2>/dev/null || echo "$SIZE_BYTES B"))" >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
