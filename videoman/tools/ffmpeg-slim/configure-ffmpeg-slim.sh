#!/usr/bin/env bash
#
# videoman ffmpeg 瘦身构建配置（方案：主流点播+直播格式 + -Os）
# ---------------------------------------------------------------------------
# 用途：为 videoman（媒体内核 media_kit/libmpv）二期瘦身，构建一个只保留现代主流
#      点播+直播格式、用 -Os 优化体积的 LGPL ffmpeg 共享库。经 2026-07-31 Windows
#      spike 实测验证（见 ../../doc/plans/2026-07-31-ffmpeg-slim-build-windows.md）。
#
# 实测参考（Windows/x86，同工具链，install strip 后，仅 ffmpeg 7 库）：
#   完整版(-O3)  = 29.8 MB
#   本方案(-Os)  =  6.26 MB   ← 相对完整版省 ~79%，相对 -O3 主流瘦身(11.0MB)省 ~43%
#   解码性能代价：480p h264，真实多线程播放约慢 2%（单线程约 7%）。
#   ⚠️ 上述为 Windows/x86 数字，真机 ARM+NEON 的百分比会有出入，需真机复测。
#
# 源码母版下载来源（详见同目录 README.md「源码母版」一节）：
#   ffmpeg  官方 git : https://git.ffmpeg.org/ffmpeg.git
#           GitHub 镜像: https://github.com/FFmpeg/FFmpeg.git
#           spike 实测用 commit: ad53728984531cebdb027e70e78d7165a6bdfe20（master，约 8.0 线）
#           拉取: git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git ffmpeg
#   libmpv  官方 git : https://github.com/mpv-player/mpv.git
#           （本脚本只构建 ffmpeg；libmpv 瘦身另见 README「与 libmpv 的关系」）
#
# 用法：
#   ./configure-ffmpeg-slim.sh <ffmpeg源码目录> [安装前缀] [优化标志] [--build]
# 例：
#   ./configure-ffmpeg-slim.sh ~/src/ffmpeg ~/out/ffmpeg-slim '-Os' --build
#
# 参数：
#   $1 ffmpeg 源码目录（必填，须含 ./configure）
#   $2 安装前缀（默认 <源码目录>/_slim_install）
#   $3 优化标志（默认 '-Os'；想对比可传 '-O3'）
#   --build 传入时，configure 成功后自动 make -j && make install
#
# 环境要求：见同目录 README.md（各平台工具链准备；核心是 C 编译器 + nasm/yasm + make）。
set -euo pipefail

SRC="${1:?需要传入 ffmpeg 源码目录}"
PREFIX="${2:-$SRC/_slim_install}"
OPTFLAGS="${3:--Os}"
DO_BUILD=0
for a in "$@"; do [ "$a" = "--build" ] && DO_BUILD=1; done

# ---------------------------------------------------------------------------
# 组件清单（可按需增删；对应 ../../doc/notes/2026-07-31-ffmpeg-slimming-options.md）
# ---------------------------------------------------------------------------

# 视频解码器：现代主流四件套 h264/hevc/vp9/av1 + vp8（存量 WebM）。
# 音频解码器：aac(+latm，HLS/TS)/mp3/opus/ac3+eac3(Dolby)/flac/vorbis。
#   如需极致体积，可去 vp8/ac3/eac3/flac/vorbis（实测仅省 ~0.36MB，性价比低）。
DECODERS="h264,hevc,vp9,vp8,av1,aac,aac_latm,mp3,mp3float,opus,ac3,eac3,flac,vorbis"

# 帧解析器：与解码器对应（含 mpegaudio = mp3 的隐式依赖）。
PARSERS="h264,hevc,vp9,vp8,av1,aac,aac_latm,ac3,flac,opus,vorbis,mpegaudio"

# 容器（demuxer）：mov=MP4全家桶；matroska=MKV+WebM；mpegts+hls=HLS；flv+live_flv=直播；
#   rtsp=摄像头实时流；aac/mp3/flac/ogg=裸音频流。
#   ⚠️ DASH（dash demuxer）依赖外部 libxml2，未列入——需要时加 --enable-libxml2 +
#      系统装 libxml2，再往 DEMUXERS 补 ',dash'（LGPL 兼容）。
DEMUXERS="mov,matroska,mpegts,hls,flv,live_flv,rtsp,aac,mp3,flac,ogg,webm_dash_manifest"

# 协议：本地/http(s)/tls；crypto=HLS AES-128 加密分片；rtmp 全家=直播；rtsp+rtp+udp=实时流。
#   ffrtmpcrypt/ffrtmphttp = rtmp 变体的 ffmpeg 内部依赖（非外部库）。
#   ⚠️ rtmpe/rtmpte（RTMP 私有加密，冷门）需外部 crypto 后端（openssl/gnutls/mbedtls）；
#      若构建环境有其一并 --enable-openssl 之类，会自动可用；否则被禁，不影响主流 rtmp。
PROTOCOLS="file,http,https,tls,crypto,data,async,cache,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,rtp,udp,tcp"

# 比特流过滤器：MP4↔AnnexB（H.264/HEVC）、HLS/TS 里的 AAC 转封装。
BSFS="h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc"

# ---------------------------------------------------------------------------
# configure
# ---------------------------------------------------------------------------
# 说明：
#  - 不传 --enable-lgpl：当前 ffmpeg 里 LGPL 已是默认（该 flag 已移除），只要不传
#    --enable-gpl / --enable-nonfree 即为 LGPL。老版本 ffmpeg 若仍有该 flag 可自行补。
#  - --disable-everything 后逐类 --enable，是官方推荐的最小化构建法。
#  - --disable-programs/-doc：只出库（libav*/libsw*），不出 ffmpeg.exe/文档。
#  - 只解码、不编码：全程不 --enable-encoder / --enable-muxer（编码器/封装器均为 0）。
cd "$SRC"

echo ">>> configure（优化标志：$OPTFLAGS，安装前缀：$PREFIX）"
./configure \
  --prefix="$PREFIX" \
  --enable-shared \
  --disable-static \
  --disable-programs \
  --disable-doc \
  --disable-everything \
  --enable-decoder="$DECODERS" \
  --enable-parser="$PARSERS" \
  --enable-demuxer="$DEMUXERS" \
  --enable-protocol="$PROTOCOLS" \
  --enable-bsf="$BSFS" \
  --enable-network \
  --optflags="$OPTFLAGS"

echo ">>> configure 成功。许可核对："
grep -i "License:" ffbuild/config.log 2>/dev/null | tail -1 || true

if [ "$DO_BUILD" = "1" ]; then
  echo ">>> make -j && make install"
  make -j"$(nproc 2>/dev/null || echo 4)"
  make install
  echo ">>> 完成。产物在 $PREFIX/（Windows 下 bin/，*nix 下 lib/）"
  echo ">>> 库体积（strip 后）："
  find "$PREFIX" \( -name 'libav*.so*' -o -name 'libsw*.so*' -o -name 'av*.dll' -o -name 'sw*.dll' -o -name 'libav*.dylib' -o -name 'libsw*.dylib' \) -exec ls -l {} \; 2>/dev/null || true
else
  echo ">>> 未传 --build。手动继续：make -j\$(nproc) && make install"
fi
