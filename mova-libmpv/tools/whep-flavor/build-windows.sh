#!/usr/bin/env bash
# Windows x86_64 libmpv-2.dll 本地构建脚本（把 .github/workflows/build-mova-libmpv.yml 的 windows job 搬到本机）。
# 在 MSYS2 的 MINGW64 环境里跑（本机 MSYS2 在 C:\tools\msys64）：
#   C:\tools\msys64\usr\bin\env.exe MSYSTEM=MINGW64 CHERE_INVOKING=1 /usr/bin/bash -l tools/whep-flavor/build-windows.sh
#
# 两种模式（MODE）：
#   base  复刻 CI 现状：ffmpeg n6.0.1 + mpv 78d4374 + ksmedia 补丁，不含 WHEP、不含 libplacebo
#   whep  ffmpeg n9.0.2 + patches/ffmpeg-whep/0001-0010 + mpv v0.41.0 + patches/mpv-v041（0001/0003/0004/0005）
#         + 最小静态 libplacebo；TLS 仍是系统 SChannel，另外编进 whep demuxer 与 dtls 协议
#         + S 档瘦身（见 doc/notes/2026-10-02-windows-shrink-research.md）：win-iconv 取代 GNU libiconv、
#           freetype/harfbuzz/libass 钉 tag 源码构建（libass 只用 DirectWrite、无 fontconfig）、
#           mpv 去 mpv.rc 资源、ffmpeg 去 d3d12va/bzlib/lzma。仅 whep 模式；base 模式保持 CI 现状不动
#
# 环境变量（都可选）：
#   MODE     base|whep，默认 base
#   WORK     工作根目录，默认 /c/Users/jelon/whep-win/libmpv（仓库外）
#   JOBS     并行度，默认 nproc
#   TAG      产物目录名，默认等于 MODE；同一模式想并存多份变体时用
#   WITH_WHEP  whep 模式下 0=只打补丁不启用 whep/dtls（体积对照用），默认 1
#   SLIM     whep 模式下 1=启用 S 档瘦身（默认 1）；0=回到未瘦身的 pacman 依赖（体积对照用）
# 用法：build-windows.sh [步骤...]   步骤：fetch dav1d winiconv freetype harfbuzz libass ffmpeg plc mpv finish，默认全做
# 产物：$WORK/$TAG/out/libmpv-2.dll（已 strip）、libmpv-2.unstripped.dll、libmpv.map、size.txt
set -euo pipefail

# ---------- 路径与常量 ----------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES="$(cd "$HERE/../../patches" && pwd)"
MODE="${MODE:-base}"
TAG="${TAG:-$MODE}"
WORK="${WORK:-/c/Users/jelon/whep-win/libmpv}"
JOBS="${JOBS:-$(nproc)}"
SRC="$WORK/src"                 # 只读源码缓存，各模式用 git clone --shared 派生工作副本
B="$WORK/$TAG"                  # 本模式的工作根
PREFIX="$B/prefix"; OUT="$B/out"; LOGS="$B/logs"
FF_BASE_TAG="n6.0.1"; FF_WHEP_TAG="n9.0.2"
MPV_BASE_REV="78d43740f52db817d98bcf24fb30a76ab6fa13ff"; MPV_WHEP_TAG="v0.41.0"
DAV1D_TAG="1.2.1"; PLC_TAG="v7.360.0"
# S 档瘦身依赖（钉死 tag，不跟 runner 当日的 pacman 滚动版本）
WICONV_TAG="v0.0.10"; FT_TAG="VER-2-14-3"; HB_TAG="14.4.0"; ASS_TAG="0.17.5"
# 只有 whep 模式吃 S 档瘦身；base 模式保持 CI 现状
SLIM="${SLIM:-1}"; [ "$MODE" = whep ] || SLIM=0
mkdir -p "$SRC" "$PREFIX" "$OUT" "$LOGS"
# 保留 System32：windres 经 cmd.exe popen 预处理器，PATH 里没有 cmd 会失败
export PATH=/mingw64/bin:/usr/bin:/bin:/c/Windows/System32:/c/Windows
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:/mingw64/lib/pkgconfig"
# meson 的 dependency('iconv') 只走 system 方式、不看 pkg-config；靠这两个变量让头文件/库先命中前缀里的 win-iconv
# （否则 libass/mpv 会悄悄选中 /mingw64 的 GNU libiconv.a，体积不变，看起来像"没生效"）。
# 只在 SLIM=1 时设置：base 模式没有前缀 iconv，设了反而可能让 CPATH 指向空目录（无害，但保持原行为）。
if [ "$SLIM" = 1 ]; then
  export CPATH="$(cygpath -m "$PREFIX")/include" LIBRARY_PATH="$(cygpath -m "$PREFIX")/lib"
fi

case "$MODE" in base|whep) ;; *) echo "MODE 只能是 base 或 whep" >&2; exit 2 ;; esac

# 打印带时间的进度行
say() { echo "[$(date +%H:%M:%S)] $*"; }
# 失败退出并提示
die() { echo "FAIL: $*" >&2; exit 1; }

# ---------- 0. 取源码 ----------
# 浅克隆一个 tag 到只读缓存（已存在则跳过）。参数：目录名 仓库URL tag [额外参数]
clone_tag() {
  local name="$1" url="$2" tag="$3"; shift 3
  [ -d "$SRC/$name/.git" ] && return 0
  say "clone $name@$tag"
  git clone -q --depth 1 --branch "$tag" "$@" "$url" "$SRC/$name"
}

# 取 mpv 基线所用的固定 commit（浅取单个 commit）
fetch_mpv_base() {
  [ -d "$SRC/mpv-base/.git" ] && return 0
  say "fetch mpv@$MPV_BASE_REV"
  mkdir -p "$SRC/mpv-base" && git -C "$SRC/mpv-base" init -q
  git -C "$SRC/mpv-base" fetch -q --depth 1 https://github.com/mpv-player/mpv.git "$MPV_BASE_REV"
  git -C "$SRC/mpv-base" checkout -q FETCH_HEAD
}

# 按当前模式拉齐所有源码
step_fetch() {
  clone_tag dav1d https://code.videolan.org/videolan/dav1d.git "$DAV1D_TAG"
  if [ "$MODE" = base ]; then
    clone_tag ffmpeg-n6.0.1 https://github.com/FFmpeg/FFmpeg.git "$FF_BASE_TAG"
    fetch_mpv_base
  else
    clone_tag ffmpeg-n9.0.2 https://github.com/FFmpeg/FFmpeg.git "$FF_WHEP_TAG"
    clone_tag mpv-v0.41.0 https://github.com/mpv-player/mpv.git "$MPV_WHEP_TAG"
    clone_tag libplacebo https://code.videolan.org/videolan/libplacebo.git "$PLC_TAG" --recurse-submodules --shallow-submodules
  fi
  if [ "$SLIM" = 1 ]; then
    clone_tag win-iconv https://github.com/win-iconv/win-iconv.git "$WICONV_TAG"
    clone_tag freetype https://gitlab.freedesktop.org/freetype/freetype.git "$FT_TAG"
    clone_tag harfbuzz https://github.com/harfbuzz/harfbuzz.git "$HB_TAG"
    clone_tag libass https://github.com/libass/libass.git "$ASS_TAG"
  fi
}

# 从缓存派生一份干净工作副本。参数：缓存目录名 目标目录
work_copy() {
  rm -rf "$2"
  git clone -q --shared "$SRC/$1" "$2"
  git -C "$2" checkout -q -f HEAD
}

# ---------- 1. dav1d（静态、-Os、不拆 section，同 CI） ----------
step_dav1d() {
  say "dav1d $DAV1D_TAG"
  work_copy dav1d "$B/dav1d"
  (cd "$B/dav1d" && meson setup _build --prefix="$PREFIX" --libdir=lib \
    --default-library=static --buildtype=minsize -Ddebug=false -Db_ndebug=true \
    -Denable_tools=false -Denable_tests=false -Denable_examples=false -Dbitdepths=8,16) \
    > "$LOGS/dav1d-conf.log" 2>&1 || { tail -15 "$LOGS/dav1d-conf.log"; die "dav1d configure"; }
  ninja -C "$B/dav1d/_build" install > "$LOGS/dav1d-build.log" 2>&1 || { tail -15 "$LOGS/dav1d-build.log"; die "dav1d build"; }
}

# ---------- 2b. S 档瘦身依赖（仅 SLIM=1）：win-iconv / freetype / harfbuzz / libass ----------
# 为什么：pacman 预编译的 libiconv(1.1MB 码表)、fontconfig+expat+libintl、freetype 的 png/brotli/bz2、
# harfbuzz 的 graphite2/uniscribe 合计约 2.8MB，且都不影响字幕渲染（调研里逐字/逐像素对照过）。
SH_FL="-ffunction-sections -fdata-sections"
SH_M="--default-library=static --buildtype=minsize -Db_ndebug=true -Ddebug=false"

# win-iconv：单文件，用 Windows 代码页 API 实现 iconv，替换 GNU libiconv
step_winiconv() {
  [ "$SLIM" = 1 ] || { say "SLIM=0，跳过 win-iconv"; return 0; }
  say "win-iconv $WICONV_TAG"
  mkdir -p "$PREFIX/include" "$PREFIX/lib/pkgconfig"
  clang -Oz -ffunction-sections -fdata-sections -c "$SRC/win-iconv/win_iconv.c" -o "$B/win_iconv.o" || die "win-iconv 编译"
  rm -f "$PREFIX/lib/libiconv.a"; ar rcs "$PREFIX/lib/libiconv.a" "$B/win_iconv.o"
  cp "$SRC/win-iconv/iconv.h" "$PREFIX/include/iconv.h"
  # pkg-config 入口只给走 pkg-config 的消费者；meson 的 dependency('iconv') 靠 CPATH/LIBRARY_PATH（见文件顶部）
  printf 'prefix=%s\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: iconv\nDescription: win-iconv\nVersion: 1.17\nLibs: -L${libdir} -liconv\nCflags: -I${includedir} -DWINICONV_CONST=\n' \
    "$PREFIX" > "$PREFIX/lib/pkgconfig/iconv.pc"
}

# freetype：只留 zlib；去 png/brotli/bzip2/harfbuzz（后者破 freetype<->harfbuzz 循环依赖，harfbuzz 之后再接 freetype）
step_freetype() {
  [ "$SLIM" = 1 ] || { say "SLIM=0，跳过 freetype"; return 0; }
  say "freetype $FT_TAG"; rm -rf "$B/freetype"; cp -a "$SRC/freetype" "$B/freetype"
  (cd "$B/freetype" && CC=clang CXX=clang++ meson setup _build --prefix="$PREFIX" --libdir=lib $SH_M \
    -Dzlib=enabled -Dbzip2=disabled -Dpng=disabled -Dbrotli=disabled -Dharfbuzz=disabled -Dc_args="$SH_FL") \
    > "$LOGS/ft-conf.log" 2>&1 || { tail -15 "$LOGS/ft-conf.log"; die "freetype configure"; }
  ninja -C "$B/freetype/_build" install > "$LOGS/ft-build.log" 2>&1 || { tail -15 "$LOGS/ft-build.log"; die "freetype build"; }
}

# harfbuzz：去 glib/graphite2/uniscribe/GDI/DirectWrite 等，只留 freetype 后端
step_harfbuzz() {
  [ "$SLIM" = 1 ] || { say "SLIM=0，跳过 harfbuzz"; return 0; }
  say "harfbuzz $HB_TAG"; rm -rf "$B/harfbuzz"; cp -a "$SRC/harfbuzz" "$B/harfbuzz"
  (cd "$B/harfbuzz" && CC=clang CXX=clang++ meson setup _build --prefix="$PREFIX" --libdir=lib $SH_M \
    -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled -Dicu=disabled -Dgraphite2=disabled -Dfreetype=enabled \
    -Dtests=disabled -Ddocs=disabled -Dutilities=disabled -Dbenchmark=disabled -Dintrospection=disabled \
    -Dc_args="$SH_FL" -Dcpp_args="$SH_FL") \
    > "$LOGS/hb-conf.log" 2>&1 || { tail -15 "$LOGS/hb-conf.log"; die "harfbuzz configure"; }
  ninja -C "$B/harfbuzz/_build" install > "$LOGS/hb-build.log" 2>&1 || { tail -15 "$LOGS/hb-build.log"; die "harfbuzz build"; }
}

# libass：只用 DirectWrite 字体后端，去 fontconfig（连带 expat/libintl）；checkasm 关掉，否则换 iconv 后它链接失败
step_libass() {
  [ "$SLIM" = 1 ] || { say "SLIM=0，跳过 libass"; return 0; }
  say "libass $ASS_TAG"; rm -rf "$B/libass"; cp -a "$SRC/libass" "$B/libass"
  (cd "$B/libass" && CC=clang CXX=clang++ meson setup _build --prefix="$PREFIX" --libdir=lib $SH_M \
    -Dfontconfig=disabled -Ddirectwrite=enabled -Dlibunibreak=enabled -Dtest=disabled -Dcompare=disabled -Dprofile=disabled -Dcheckasm=disabled \
    -Dc_args="$SH_FL") \
    > "$LOGS/ass-conf.log" 2>&1 || { tail -15 "$LOGS/ass-conf.log"; die "libass configure"; }
  ninja -C "$B/libass/_build" install > "$LOGS/ass-build.log" 2>&1 || { tail -15 "$LOGS/ass-build.log"; die "libass build"; }
}

# ---------- 2. ffmpeg ----------
# 按序给 ffmpeg 打 patches/ffmpeg-whep/*.patch（先 --check 再 apply）。
# 0007/0009 只改 mbedtls 文件，Windows 用不到，但 0008 的 whep.c 守卫上下文可能依赖 0007，所以全部按序打，无害。
patch_ffmpeg_whep() {
  local p
  for p in "$PATCHES"/ffmpeg-whep/*.patch; do
    git -C "$B/ffmpeg" apply --check "$p" || die "ffmpeg 补丁不能 apply: $p"
    git -C "$B/ffmpeg" apply "$p"
    say "已打补丁 $(basename "$p")"
  done
}

# configure + make + install 静态 ffmpeg（gcc，同 CI；schannel 作 TLS）
step_ffmpeg() {
  say "ffmpeg ($MODE)"
  local demuxers="mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ac3,eac3,ass,srt,webvtt"
  local protos="file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp"
  local extra=()
  if [ "$SLIM" = 1 ]; then
    # S 档：ffmpeg 里 d3d12va 被 n9 自动探测打开但 mpv 不用；bzlib/lzma 只服务极少见的 mkv 头压缩。
    # -DWINICONV_CONST= 是 win-iconv 头文件的 const 约定；-I/-L 指向前缀里的 win-iconv
    extra+=(--disable-d3d12va --disable-bzlib --disable-lzma
            --extra-cflags="-I$PREFIX/include -DWINICONV_CONST=" --extra-ldflags="-L$PREFIX/lib")
  fi
  if [ "$MODE" = base ]; then
    work_copy ffmpeg-n6.0.1 "$B/ffmpeg"
    extra+=(--disable-postproc)
  else
    work_copy ffmpeg-n9.0.2 "$B/ffmpeg"
    patch_ffmpeg_whep
    [ -f "$B/ffmpeg/libavformat/whep.c" ] || die "打完补丁后 whep.c 不存在"
    # WITH_WHEP=0 时只打补丁、不启用 whep/dtls，用来分离"n9 本体差异"与"WHEP 增量"
    if [ "${WITH_WHEP:-1}" = 1 ]; then demuxers="$demuxers,whep"; protos="$protos,dtls"; fi
    extra+=(--disable-iamf)   # n9 新增；n9 没有 --disable-postproc
  fi
  (cd "$B/ffmpeg" && ./configure \
    --target-os=mingw32 --arch=x86_64 \
    --disable-gpl --disable-nonfree \
    --enable-static --disable-shared --pkg-config-flags=--static \
    --disable-doc --disable-programs --disable-avdevice "${extra[@]}" \
    --disable-muxers --disable-decoders --disable-encoders --disable-demuxers \
    --disable-parsers --disable-protocols --disable-devices --disable-filters \
    --enable-small --enable-optimizations \
    --enable-schannel --enable-zlib --enable-libdav1d \
    --enable-d3d11va --enable-dxva2 \
    --enable-avutil --enable-avcodec --enable-avfilter --enable-avformat \
    --enable-swscale --enable-swresample \
    --enable-decoder=h264,hevc,vp9,libdav1d,png,aac,aac_latm,mp3,mp3float,opus,ac3,eac3,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8,ass,ssa,subrip,text,webvtt,movtext \
    --enable-encoder=png \
    --enable-parser=h264,hevc,vp9,av1,png,aac,aac_latm,ac3,flac,opus,vorbis,mpegaudio \
    --enable-demuxer="$demuxers" \
    --enable-protocol="$protos" \
    --disable-bsfs --disable-swscale-alpha \
    --enable-bsf=null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts \
    --enable-network \
    --prefix="$PREFIX") > "$OUT/ffconf.log" 2>&1 || { tail -20 "$OUT/ffconf.log"; die "ffmpeg configure"; }
  grep -q 'License: LGPL version 2.1' "$OUT/ffconf.log" || die "许可证不是 LGPLv2.1"
  for p in https tls rtmps; do grep -qw "$p" "$OUT/ffconf.log" || die "协议 $p 缺失"; done
  if [ "$MODE" = whep ] && [ "${WITH_WHEP:-1}" = 1 ]; then grep -hE "CONFIG_(WHEP_DEMUXER|DTLS_PROTOCOL|SCHANNEL)" "$B/ffmpeg/config_components.h" "$B/ffmpeg/config.h" | tee -a "$OUT/ffconf.log"; fi
  make -C "$B/ffmpeg" -j"$JOBS" > "$LOGS/ffmake.log" 2>&1 || { tail -25 "$LOGS/ffmake.log"; die "ffmpeg make"; }
  make -C "$B/ffmpeg" install > "$LOGS/ffinstall.log" 2>&1 || die "ffmpeg install"
}

# ---------- 3. 最小静态 libplacebo（仅 whep 模式；mpv v0.41 的硬依赖） ----------
# 关掉 vulkan/d3d11/shaderc 等可选项；用 clang 编，与后面 mpv 的编译器一致
step_plc() {
  [ "$MODE" = whep ] || { say "base 模式不需要 libplacebo"; return 0; }
  say "libplacebo $PLC_TAG"
  rm -rf "$B/libplacebo"; cp -a "$SRC/libplacebo" "$B/libplacebo"   # 含子模块，整份复制
  # 静态库默认仍带 -DPL_EXPORT，会让 ~120 个 pl_* 符号被 dllexport 进 libmpv-2.dll 导出表（实测 55 -> 177），
  # 还会让 --gc-sections 保不住这些符号；静态构建改用 -DPL_STATIC，导出表保持只有 mpv_*
  sed -i "s|c_args: \['-DPL_EXPORT'\],|c_args: get_option('default_library') == 'static' ? ['-DPL_STATIC'] : ['-DPL_EXPORT'],|" "$B/libplacebo/src/meson.build"
  grep -q "PL_STATIC'\] : \['-DPL_EXPORT" "$B/libplacebo/src/meson.build" || die "libplacebo meson.build 的 PL_EXPORT 补丁没生效"
  (cd "$B/libplacebo" && CC=clang CXX=clang++ meson setup _build --prefix="$PREFIX" --libdir=lib \
    --default-library=static --buildtype=minsize -Db_ndebug=true \
    -Dvulkan=disabled -Dd3d11=disabled -Dglslang=disabled -Dshaderc=disabled -Dlcms=disabled \
    -Ddovi=disabled -Dlibdovi=disabled -Dxxhash=disabled -Dunwind=disabled \
    -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false \
    -Dc_args="-ffunction-sections -fdata-sections" -Dcpp_args="-ffunction-sections -fdata-sections") \
    > "$LOGS/plc-conf.log" 2>&1 || { tail -15 "$LOGS/plc-conf.log"; die "libplacebo configure"; }
  ninja -C "$B/libplacebo/_build" install > "$LOGS/plc-build.log" 2>&1 || { tail -20 "$LOGS/plc-build.log"; die "libplacebo build"; }
}

# ---------- 4. mpv ----------
# base：给当前 mingw-w64 头文件补 mmreg.h（同 CI 的 sed 补丁）
patch_mpv_base() {
  local files f
  files=$(grep -rl '#include <ksmedia.h>' "$B/mpv/audio" "$B/mpv/osdep" || true)
  [ -n "$files" ] || die "没找到 ksmedia.h include，mpv 布局变了"
  for f in $files; do
    grep -q '^#include <ksguid.h>' "$f" || die "$f 缺 ksguid.h"
    sed -i 's|^#include <ksguid.h>|#include <mmreg.h>\n#include <ksguid.h>\n#include <mmsystem.h>|' "$f"
  done
}

# whep：按序打 patches/mpv-v041（Windows 跳过 0002 javavm 桩；0005 去 mpv.rc 是 Windows 专用，SLIM=0 时跳过）
patch_mpv_whep() {
  local p
  for p in "$PATCHES"/mpv-v041/*.patch; do
    case "$p" in *java-vm*) say "跳过 $(basename "$p")（Android 专用）"; continue ;; esac
    case "$p" in *drop-mpv-rc*) [ "$SLIM" = 1 ] || { say "跳过 $(basename "$p")（SLIM=0）"; continue; } ;; esac
    git -C "$B/mpv" apply --check "$p" || die "mpv 补丁不能 apply: $p"
    git -C "$B/mpv" apply "$p"
    say "已打补丁 $(basename "$p")"
  done
}

# meson 配置 + 编译 mpv（clang，规避 gcc 16.2 miscompile；链接参数同 CI）
step_mpv() {
  say "mpv ($MODE)"
  if [ "$MODE" = base ]; then work_copy mpv-base "$B/mpv"; patch_mpv_base
  else work_copy mpv-v0.41.0 "$B/mpv"; patch_mpv_whep; fi
  local map; map="$(cygpath -m "$OUT")/libmpv.map"
  rm -rf "$B/mpv/build"
  # SLIM：让 mpv 的头文件/库搜索先命中前缀（win-iconv、静态 freetype/harfbuzz/libass）
  local pinc="" plib=""
  if [ "$SLIM" = 1 ]; then pinc="-I$(cygpath -m "$PREFIX")/include"; plib="-L$(cygpath -m "$PREFIX")/lib "; fi
  (cd "$B/mpv" && CC=clang CXX=clang++ meson setup build --prefix="$PREFIX" --libdir=lib --default-library=shared \
    --prefer-static \
    -Dbuildtype=minsize -Ddebug=false -Db_ndebug=true \
    -Dc_args="-ffunction-sections -fdata-sections $pinc" \
    -Dcpp_args="-ffunction-sections -fdata-sections" \
    -Dc_link_args="${plib}-Wl,-Bstatic -lstdc++ -lwinpthread -Wl,-Bdynamic -ldwrite -lole32 -lrpcrt4 -static-libgcc -Wl,--gc-sections -Wl,-Map=$map" \
    -Dcpp_link_args="-Wl,--gc-sections" \
    -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false) \
    > "$LOGS/mpv-conf.log" 2>&1 || { tail -25 "$LOGS/mpv-conf.log"; die "mpv configure"; }
  ninja -C "$B/mpv/build" > "$LOGS/mpv-build.log" 2>&1 || { grep -E "error|undefined|FAILED" "$LOGS/mpv-build.log" | head -20; die "mpv build"; }
  ninja -C "$B/mpv/build" install > "$LOGS/mpv-install.log" 2>&1 || die "mpv install"
}

# ---------- 5. 收尾：体积归因、依赖检查、strip、生成导入库 ----------
step_finish() {
  local dll; dll="$(find "$PREFIX" -iname 'libmpv*.dll' | head -1)"
  [ -n "$dll" ] || die "没找到 libmpv*.dll"
  cp "$dll" "$OUT/libmpv-2.unstripped.dll"
  # 按输入归档汇总链接 map 的字节数（strip 前），同 CI
  awk '
    /^ \.[^ ]+$/ { pending=1; next }
    { if (pending) { line=" x " $0; pending=0 } else line=$0
      n=split(line,f,/[ \t]+/)
      if (n>=5 && f[3] ~ /^0x/ && f[4] ~ /^0x/ && f[5] ~ /\.(a|o)/) { o=f[5]; sub(/\(.*/,"",o); size[o]+=strtonum(f[4]) } }
    END { for (o in size) printf "%12d  %s\n", size[o], o }' "$OUT/libmpv.map" | sort -rn | head -50 > "$OUT/map-by-archive.txt" || true
  # 自包含检查
  objdump -p "$dll" | grep -i 'DLL Name' | sort -u > "$OUT/imports.txt"
  for bad in libstdc++ libgcc_s libwinpthread; do
    if grep -qi "$bad" "$OUT/imports.txt"; then die "产物导入了 $bad，不再自包含"; fi
  done
  if [ "$SLIM" = 1 ]; then
    # S 档判据：被替换/被去掉的依赖不得再出现在链接 map 里（map 是 strip 前的真实输入清单）。
    # 前缀目录名固定为 prefix，$PREFIX/lib 下的才是我们自建的那份（win-iconv 的 libiconv.a 也在其中）。
    local bad hit
    # 只看"真被拉进链接的归档成员"（形如 libxxx.a(member.o)）；LOAD 行只是 ld 列出命令行上的归档，未必有成员被用。
    # 不能写成 `grep | grep -q`：pipefail 下 grep -q 提前退出会让上游 SIGPIPE，判据永远不触发（实际踩过）。
    for bad in libiconv.a libfontconfig libexpat libpng16 libbrotli libgraphite2 libintl libbz2; do
      hit="$(grep -v '/prefix/lib/' "$OUT/libmpv.map" | grep -F "$bad(" | head -3 || true)"
      if [ -n "$hit" ]; then
        echo "$hit"
        die "S 档判据失败：map 里仍链入 $bad 的成员（CPATH/LIBRARY_PATH 没生效或依赖漂移？）"
      fi
    done
    for bad in libiconv.a libass.a libfreetype.a libharfbuzz.a; do
      grep -qF "/prefix/lib/$bad(" "$OUT/libmpv.map" || die "S 档判据失败：map 里没有前缀里的 $bad"
    done
    # mpv.rc 去掉后不应再有 .rsrc 段
    hit="$(objdump -h "$dll" | grep -F '.rsrc' || true)"
    [ -z "$hit" ] || die "S 档判据失败：仍有 .rsrc 段（0005 补丁没生效？）"
  fi
  # 符号检查（strip 前）
  local s fail=0
  for s in mpv_create mpv_initialize mpv_command mpv_set_option_string mpv_render_context_create mpv_terminate_destroy \
           dav1d_open ass_library_init ass_renderer_init ass_set_fonts hb_shape FT_Init_FreeType fribidi_get_par_embedding_levels_ex; do
    nm --defined-only "$dll" 2>/dev/null | grep -qw "$s" || { echo "缺少符号 $s"; fail=1; }
  done
  [ "$fail" = 0 ] || die "符号检查失败"
  strip -s "$dll"
  cp "$dll" "$OUT/libmpv-2.dll"
  # 导入库与 def（给 media_kit_video 链接期用，非必需产物）
  (cd "$OUT" && gendef libmpv-2.dll >/dev/null 2>&1 && dlltool -d libmpv-2.def -l libmpv.dll.a -D libmpv-2.dll) || say "gendef/dlltool 失败（非致命）"
  stat -c%s "$OUT/libmpv-2.unstripped.dll" "$OUT/libmpv-2.dll" | tee "$OUT/size.txt"
  say "完成：$OUT/libmpv-2.dll  $(stat -c%s "$OUT/libmpv-2.dll") 字节"
}

# ---------- 主流程 ----------
STEPS=("$@"); [ ${#STEPS[@]} -gt 0 ] || STEPS=(fetch dav1d winiconv freetype harfbuzz libass ffmpeg plc mpv finish)
for s in "${STEPS[@]}"; do "step_$s"; done
