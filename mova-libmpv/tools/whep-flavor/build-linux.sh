#!/usr/bin/env bash
# WHEP flavor 底座构建（Linux x86_64，在 WSL/Ubuntu 里跑）。
# 组合：ffmpeg n9.0.2 + mpv v0.41.0（打 patches/mpv-v041/*）+ 最小静态 libplacebo（摘 vo_gpu_next）。
# 不动默认 flavor；设 WITH_WHEP=1 会先给 ffmpeg 打 patches/ffmpeg-whep/*.patch，再把 whep demuxer 一并编进去。
#
# 用法：build-linux.sh            （默认工作目录 $HOME/w/t04-build，可用 WORK 覆盖）
# 环境变量（都可选）：
#   WORK       工作/输出根目录
#   JOBS       并行度，默认 8
#   FF_SRC     已有的 ffmpeg n9.0.2 源码目录（只读复制，省得再 clone）
#   MPV_SRC    已有的 mpv v0.41.0 干净源码目录（会 git clone --shared 到工作区再打补丁）
#   PLC_SRC    已有的 libplacebo v7.360.0（含子模块）源码目录
#   WITH_WHEP  1=打 ffmpeg-whep 补丁并把 whep demuxer 编进 ffmpeg，默认 0
#   APPLY_WHEP_PATCHES  1=只打 ffmpeg-whep 补丁但不启用 whep（用来验证"补丁不污染默认 configure"），默认 0
#   APPLY_JAVAVM  1=打 javavm 补丁（Android 用，Linux 上只是桩），默认 1
# 产物：$WORK/out/linux-x86_64/libmpv.so（已 strip）、$WORK/out/ffconf.log、$WORK/out/include/（头文件）
set -euo pipefail

# ---------- 路径与常量 ----------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES="$(cd "$HERE/../../patches" && pwd)"
WORK="${WORK:-$HOME/w/t04-build}"
JOBS="${JOBS:-8}"
WITH_WHEP="${WITH_WHEP:-0}"
APPLY_WHEP_PATCHES="${APPLY_WHEP_PATCHES:-0}"
APPLY_JAVAVM="${APPLY_JAVAVM:-1}"
FF_TAG="n9.0.2"; MPV_TAG="v0.41.0"; PLC_TAG="v7.360.0"
OUT="$WORK/out"; PREFIX="$WORK/prefix"; LOGS="$WORK/logs"
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$WORK" "$OUT/linux-x86_64" "$LOGS" "$PREFIX"

# 打印带时间的进度行
say() { echo "[$(date +%H:%M:%S)] $*"; }
# 失败时给出日志位置
die() { echo "FAIL: $*" >&2; exit 1; }

# ---------- 取源码 ----------
# 取得一份指定 tag 的源码：优先从本地目录 git clone（快），否则走网络。参数：目标目录 本地源 远程URL tag 额外clone参数
fetch_src() {
  local dst="$1" local_src="$2" url="$3" tag="$4"; shift 4
  [ -d "$dst/.git" ] && { git -C "$dst" checkout -q -f "$tag" && git -C "$dst" clean -fdxq; return; }
  rm -rf "$dst"
  if [ -n "$local_src" ] && [ -d "$local_src" ]; then
    git clone -q --shared "$local_src" "$dst"
  else
    git clone -q "$@" "$url" "$dst"
  fi
  git -C "$dst" checkout -q -f "$tag"
}

# ---------- 1. ffmpeg n9.0.2 ----------
# 按序给 ffmpeg 打 patches/ffmpeg-whep/*.patch（先 --check 再 apply），失败即停
patch_ffmpeg_whep() {
  local p
  for p in "$PATCHES"/ffmpeg-whep/*.patch; do
    git -C "$WORK/ffmpeg" apply --check "$p" || die "ffmpeg 补丁不能 apply: $p"
    git -C "$WORK/ffmpeg" apply "$p"
    say "已打补丁 $(basename "$p")"
  done
}

# 按 n9.0.2 瘦身调研的推荐参数 configure + 安装（只静态库）
build_ffmpeg() {
  say "ffmpeg $FF_TAG"
  fetch_src "$WORK/ffmpeg" "${FF_SRC:-}" https://github.com/FFmpeg/FFmpeg.git "$FF_TAG" --depth 1 --branch "$FF_TAG"
  local demuxers="mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ac3,eac3,ass,srt,webvtt"
  local protos="file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp"
  if [ "$WITH_WHEP" = 1 ] || [ "$APPLY_WHEP_PATCHES" = 1 ]; then
    patch_ffmpeg_whep
    [ -f "$WORK/ffmpeg/libavformat/whep.c" ] || die "打完补丁后 libavformat/whep.c 仍不存在"
  fi
  if [ "$WITH_WHEP" = 1 ]; then
    demuxers="$demuxers,whep"
    # whep 需要 dtls 协议（whep_demuxer_select 也会自动选上，这里显式列出以免被后续改动漏掉）
    case ",$protos," in *,dtls,*) ;; *) protos="$protos,dtls" ;; esac
  fi
  # 注意：--disable-bsfs 必须在 --enable-bsf 之前；n9 没有 --disable-postproc
  (cd "$WORK/ffmpeg" && ./configure \
    --prefix="$PREFIX" \
    --disable-gpl --disable-nonfree \
    --enable-static --disable-shared --pkg-config-flags=--static \
    --disable-doc --disable-programs --disable-avdevice \
    --disable-muxers --disable-decoders --disable-encoders --disable-demuxers \
    --disable-parsers --disable-protocols --disable-devices --disable-filters \
    --disable-bsfs --disable-iamf --disable-swscale-alpha \
    --disable-bzlib --disable-lzma --disable-iconv --disable-xlib --disable-libxcb --disable-sdl2 --disable-alsa \
    --enable-small --enable-optimizations --disable-symver \
    --extra-cflags="-fvisibility=hidden -ffunction-sections -fdata-sections" \
    --extra-ldflags="-Wl,--gc-sections" \
    --enable-openssl --enable-zlib --enable-libdav1d \
    --disable-vaapi --disable-vdpau --disable-vulkan \
    --enable-avutil --enable-avcodec --enable-avfilter --enable-avformat \
    --enable-swscale --enable-swresample \
    --enable-decoder=h264,hevc,vp9,libdav1d,png,aac,aac_latm,mp3,mp3float,opus,ac3,eac3,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8,ass,ssa,subrip,text,webvtt,movtext \
    --enable-encoder=png \
    --enable-parser=h264,hevc,vp9,av1,png,aac,aac_latm,ac3,flac,opus,vorbis,mpegaudio \
    --enable-demuxer="$demuxers" \
    --enable-protocol="$protos" \
    --enable-bsf=null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts \
    --enable-network) > "$OUT/ffconf.log" 2>&1 || { tail -20 "$OUT/ffconf.log"; die "ffmpeg configure"; }
  make -C "$WORK/ffmpeg" -j"$JOBS" > "$LOGS/ffmake.log" 2>&1 || { tail -20 "$LOGS/ffmake.log"; die "ffmpeg make"; }
  make -C "$WORK/ffmpeg" install > "$LOGS/ffinstall.log" 2>&1 || die "ffmpeg install"
}

# ---------- 2. 最小静态 libplacebo ----------
# 关掉 vulkan/d3d11/shaderc 等一切可选项，只编 .a 供 mpv 的 gpu 渲染后端链接
build_libplacebo() {
  say "libplacebo $PLC_TAG"
  if [ -n "${PLC_SRC:-}" ] && [ -d "$PLC_SRC" ]; then
    # 本地源码带子模块，整份复制（git clone --shared 不带子模块）
    [ -d "$WORK/libplacebo" ] || cp -a "$PLC_SRC" "$WORK/libplacebo"
  else
    fetch_src "$WORK/libplacebo" "" https://code.videolan.org/videolan/libplacebo.git "$PLC_TAG" --recurse-submodules
    git -C "$WORK/libplacebo" submodule update --init --recursive -q
  fi
  rm -rf "$WORK/bplc"
  (cd "$WORK/libplacebo" && meson setup "$WORK/bplc" --prefix="$PREFIX" --libdir=lib \
    --default-library=static --buildtype=minsize -Db_ndebug=true \
    -Dvulkan=disabled -Dd3d11=disabled -Dglslang=disabled -Dshaderc=disabled -Dlcms=disabled \
    -Ddovi=disabled -Dlibdovi=disabled -Dxxhash=disabled -Dunwind=disabled \
    -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false \
    -Dc_args="-ffunction-sections -fdata-sections -fPIC" -Dcpp_args="-ffunction-sections -fdata-sections -fPIC") \
    > "$LOGS/confplc.log" 2>&1 || { tail -10 "$LOGS/confplc.log"; die "libplacebo configure"; }
  ninja -C "$WORK/bplc" install > "$LOGS/buildplc.log" 2>&1 || { tail -15 "$LOGS/buildplc.log"; die "libplacebo build"; }
}

# ---------- 3. mpv v0.41.0 + 补丁 ----------
# 按序打 patches/mpv-v041/*.patch（先 --check 再 apply），失败即停
patch_mpv() {
  fetch_src "$WORK/mpv" "${MPV_SRC:-}" https://github.com/mpv-player/mpv.git "$MPV_TAG" --depth 1 --branch "$MPV_TAG"
  local p
  for p in "$PATCHES"/mpv-v041/*.patch; do
    case "$p" in *java-vm*) [ "$APPLY_JAVAVM" = 1 ] || { say "跳过 $(basename "$p")"; continue; } ;; esac
    git -C "$WORK/mpv" apply --check "$p" || die "补丁不能 apply: $p"
    git -C "$WORK/mpv" apply "$p"
    say "已打补丁 $(basename "$p")"
  done
}

# 编 libmpv：只导出 mpv_*（version script），gc-sections，之后 strip
build_mpv() {
  say "mpv $MPV_TAG"
  patch_mpv
  echo '{ global: mpv_*; local: *; };' > "$WORK/mpv.ver"
  rm -rf "$WORK/bmpv"
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
  (cd "$WORK/mpv" && meson setup "$WORK/bmpv" --buildtype=minsize -Db_ndebug=true \
    -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false -Dbuild-date=false \
    -Dgl=enabled -Dplain-gl=enabled \
    -Dc_args="-fvisibility=hidden -ffunction-sections -fdata-sections" \
    -Dc_link_args="-Wl,--gc-sections -Wl,--exclude-libs,ALL -Wl,--version-script=$WORK/mpv.ver -Wl,--as-needed") \
    > "$LOGS/confmpv.log" 2>&1 || { tail -15 "$LOGS/confmpv.log"; die "mpv configure"; }
  ninja -C "$WORK/bmpv" > "$LOGS/buildmpv.log" 2>&1 || { grep -E "error|undefined|FAILED" "$LOGS/buildmpv.log" | head; die "mpv build"; }
  local so; so="$(ls "$WORK"/bmpv/libmpv.so.2.*.* | head -1)"
  cp "$so" "$OUT/linux-x86_64/libmpv.unstripped.so"
  strip --strip-all "$so" -o "$OUT/linux-x86_64/libmpv.so"
  mkdir -p "$OUT/include" && cp -r "$WORK/mpv/include/mpv" "$OUT/include/"
}

# ---------- 主流程 ----------
build_ffmpeg
build_libplacebo
build_mpv
say "完成"
echo "stripped libmpv.so = $(stat -c%s "$OUT/linux-x86_64/libmpv.so") bytes"
echo "unstripped         = $(stat -c%s "$OUT/linux-x86_64/libmpv.unstripped.so") bytes"
echo "产物: $OUT/linux-x86_64/libmpv.so   configure 日志: $OUT/ffconf.log"
