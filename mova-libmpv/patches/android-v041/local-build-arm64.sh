#!/bin/bash
# 用法: build06.sh LTO(0/1)  n9.0.2(瘦身+dav1d)+mpv v0.41.0(摘gpu_next+javavm补丁)+libplacebo
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
set -ex
L=$1
E=/root/w/mpvt/eval; M=/root/w/t06; PATCHES=/mnt/c/workspace/dart-labs/mova-libmpv/patches/mpv-v041
NDK=$E/ndk/android-ndk-r25c; TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64
TARGET=aarch64-linux-android; CROSS=${TARGET}24
if [ $L = 1 ]; then SRCP=$E/and-prefix-lto; SRCW=$E/and-build-lto; LF="-flto"; LTOOPT="--enable-lto"; PLC=$E/and-prefix-lto-v360-gl; else SRCP=$E/and-prefix; SRCW=$E/and-build; LF=""; LTOOPT=""; PLC=$E/and-prefix-v360-gl; fi
P=$M/p-$L; W=$M/w-$L
rm -rf $P $W; mkdir -p $W
cp -a $SRCP $P; sed -i "s,$SRCP,$P,g" $P/lib/pkgconfig/*.pc
cp -a $M/dav1d-inst-$L/. $P/; sed -i "s,$M/dav1d-inst-$L,$P,g" $P/lib/pkgconfig/dav1d.pc
sed "s#$SRCP#$P#g" $SRCW/cross-mpv.ini > $W/cross-mpv.ini
export AR=$TC/bin/llvm-ar CC=$TC/bin/$CROSS-clang CXX=$TC/bin/$CROSS-clang++ STRIP=$TC/bin/llvm-strip RANLIB=$TC/bin/llvm-ranlib NM=$TC/bin/llvm-nm
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig PKG_CONFIG_PATH=$P/lib/pkgconfig PKG_CONFIG="pkg-config --static"
git clone -q /root/w/ff902 $W/ff; cd $W/ff; git checkout -q n9.0.2
DEC="hevc,libdav1d,png,aac,aac_latm,mp3float,opus,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8,ass,ssa,subrip,text,webvtt,movtext,h264_mediacodec,hevc_mediacodec,vp9_mediacodec,av1_mediacodec"
PAR="h264,hevc,vp9,av1,png,aac,aac_latm,flac,opus,vorbis,mpegaudio"
DEM="mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ass,srt,webvtt"
PRO="file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp"
BSF="null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts"
./configure --target-os=android --enable-cross-compile --cross-prefix=$TC/bin/$TARGET- --cc=$CC --cxx=$CXX --ar=$AR --nm=$NM --ranlib=$RANLIB --strip=$STRIP --arch=aarch64 --cpu=armv8-a --pkg-config=pkg-config \
 --extra-cflags="-I$P/include -ffunction-sections -fdata-sections -fvisibility=hidden $LF" --extra-ldflags="-L$P/lib -Wl,--gc-sections $LF" $LTOOPT \
 --disable-gpl --disable-nonfree --enable-version3 --enable-static --disable-shared --disable-vulkan --disable-iconv --disable-stripping --pkg-config-flags=--static \
 --disable-muxers --disable-decoders --disable-encoders --disable-demuxers --disable-parsers --disable-protocols --disable-devices --disable-filters --disable-doc --disable-avdevice --disable-iamf --disable-programs --disable-gray --disable-swscale-alpha \
 --enable-jni --enable-mediacodec --enable-hwaccels --disable-dxva2 --disable-vaapi --disable-vdpau --disable-bzlib --disable-linux-perf --disable-videotoolbox --disable-audiotoolbox \
 --enable-small --enable-optimizations --disable-runtime-cpudetect --enable-mbedtls --enable-libdav1d --enable-zlib --enable-avutil --enable-avcodec --enable-avfilter --enable-avformat --enable-swscale --enable-swresample \
 --enable-decoder="$DEC" --enable-encoder=png --enable-parser="$PAR" --enable-demuxer="$DEM" --enable-protocol="$PRO" --disable-bsfs --enable-bsf="$BSF" --enable-network --prefix=$P > $M/conf-$L.log 2>&1
make -j8 > $M/ffmake-$L.log 2>&1 && make install >> $M/ffmake-$L.log 2>&1
grep -m1 FFMPEG_VERSION $P/include/libavutil/ffversion.h
rm -rf $W/mpv; git clone -q /root/w/mpvt/src-v041 $W/mpv; cd $W/mpv; git checkout -q v0.41.0 2>/dev/null || true; git describe --tags 2>&1 | head -1; git status --short | head -3
for p in $PATCHES/0001-*.patch $PATCHES/0002-*.patch; do git apply --check $p && git apply $p; echo applied $p; done
B=$M/b-$L; rm -rf $B
export PKG_CONFIG_LIBDIR=$PLC/lib/pkgconfig:$P/lib/pkgconfig
LT=; [ $L = 1 ] && LT=-Db_lto=true
meson setup $B --cross-file $W/cross-mpv.ini --buildtype=minsize -Db_ndebug=true -Dauto_features=disabled -Dgpl=false -Dcplayer=false -Dlibmpv=true -Dbuild-date=false -Dtests=false \
 -Dgl=enabled -Dplain-gl=enabled -Degl-android=enabled -Dandroid-media-ndk=enabled -Dopensles=enabled -Daudiotrack=enabled \
 -Dc_link_args="-landroid -llog -lEGL -lc++_static -lc++abi -Wl,--gc-sections -Wl,--exclude-libs,ALL -Wl,--version-script=$E/mpv.android.ver" $LT > $M/mconf-$L.log 2>&1 || { tail -20 $M/mconf-$L.log; exit 1; }
ninja -C $B > $M/mbuild-$L.log 2>&1 || { grep -E "error|FAILED" $M/mbuild-$L.log | head; exit 2; }
SO=$(readlink -f $B/libmpv.so); $TC/bin/llvm-strip -s $SO -o $M/t06-$L.stripped.so; cp $SO $M/t06-$L.unstripped.so
echo "RESULT LTO=$L unstripped=$(stat -c%s $SO) stripped=$(stat -c%s $M/t06-$L.stripped.so)"
