#!/bin/bash
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
# Android arm64 API24 依赖交叉编译：zlib mbedtls freetype fribidi harfbuzz libass ffmpeg n9.0.2
set -ex
E=/root/w/mpvt/eval
NDK=$E/ndk/android-ndk-r25c
TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64
API=24; TARGET=aarch64-linux-android; CROSS=$TARGET$API
P=$E/and-prefix
W=$E/and-build
mkdir -p $P $W
export AR=$TC/bin/llvm-ar CC=$TC/bin/$CROSS-clang CXX=$TC/bin/$CROSS-clang++ STRIP=$TC/bin/llvm-strip RANLIB=$TC/bin/llvm-ranlib NM=$TC/bin/llvm-nm
OPT="-Os -fPIC -ffunction-sections -fdata-sections"
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig PKG_CONFIG_PATH=$P/lib/pkgconfig
export PKG_CONFIG="pkg-config --static"
cat > $W/cross.ini <<EOT
[binaries]
c = "$CC"
cpp = "$CXX"
ar = "$AR"
strip = "$STRIP"
pkg-config = ["pkg-config", "--static"]
[built-in options]
c_args = ["-Os","-fPIC","-ffunction-sections","-fdata-sections"]
cpp_args = ["-Os","-fPIC","-ffunction-sections","-fdata-sections","-fno-exceptions","-fno-rtti"]
[host_machine]
system = "android"
cpu_family = "aarch64"
cpu = "aarch64"
endian = "little"
EOT
sed -i "s/\"/'/g" $W/cross.ini
D=$E/dl
# zlib
if [ ! -f $P/lib/libz.a ]; then rm -rf $W/zlib; cp -r $D/zlib-1.3.1 $W/zlib; cd $W/zlib; CFLAGS="$OPT" ./configure --prefix=$P --static; make -j16 libz.a; make install; fi
# mbedtls 3.6.7 (源码在 /root/w/mbedtls)
if [ ! -f $P/lib/libmbedtls.a ]; then rm -rf $W/mbed; mkdir -p $W/mbed; cd $W/mbed
 cmake -G Ninja -S /root/w/mbedtls -B . -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API \
  -DCMAKE_INSTALL_PREFIX=$P -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE="-Os -DNDEBUG -ffunction-sections -fdata-sections -fPIC" \
  -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=OFF
 ninja && ninja install; fi
cd $W
# freetype
if [ ! -f $P/lib/libfreetype.a ]; then rm -rf $W/ft; cp -r $D/freetype-VER-2-13-3 $W/ft; cd $W/ft; rm -rf bld
 meson setup bld --prefix=$P --libdir=lib --cross-file $W/cross.ini --default-library=static --buildtype=plain -Dzlib=disabled -Dbzip2=disabled -Dpng=disabled -Dbrotli=disabled -Dharfbuzz=disabled -Dtests=disabled
 ninja -C bld install; fi
cd $W
if [ ! -f $P/lib/libfribidi.a ]; then rm -rf $W/fb; cp -r $D/fribidi-1.0.16 $W/fb; cd $W/fb; rm -rf bld
 meson setup bld --prefix=$P --libdir=lib --cross-file $W/cross.ini --default-library=static --buildtype=plain -Ddocs=false -Dtests=false -Dbin=false
 ninja -C bld install; fi
cd $W
if [ ! -f $P/lib/libharfbuzz.a ]; then rm -rf $W/hb; cp -r $D/harfbuzz-10.4.0 $W/hb; cd $W/hb; rm -rf bld
 meson setup bld --prefix=$P --libdir=lib --cross-file $W/cross.ini --default-library=static --buildtype=plain -Dglib=disabled -Dgobject=disabled -Dicu=disabled -Dfreetype=disabled -Dcairo=disabled -Dgraphite=disabled -Dtests=disabled -Ddocs=disabled -Dbenchmark=disabled -Dutilities=disabled
 ninja -C bld install; fi
cd $W
if [ ! -f $P/lib/libass.a ]; then rm -rf $W/ass; cp -a $D/libass-0.17.4 $W/ass; cd $W/ass; touch aclocal.m4; sleep 1; touch configure Makefile.in config.h.in; sleep 1; make distclean >/dev/null 2>&1 || true
 CFLAGS="$OPT" ./configure --host=$TARGET --prefix=$P --enable-static --disable-shared --disable-require-system-font-provider --disable-fontconfig --disable-libunibreak
 make -j16 && make install; fi
cd $W
# ffmpeg n9.0.2：组件清单取自 v6 线 flavors-mova-slim.sh（去掉 libdav1d）
if [ ! -f $P/lib/libavcodec.a ]; then rm -rf $W/ff; git clone -q /root/w/ff902 $W/ff; cd $W/ff; git checkout -q n9.0.2
 DEC="hevc,png,aac,aac_latm,mp3float,opus,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8,ass,ssa,subrip,text,webvtt,movtext,h264_mediacodec,hevc_mediacodec,vp9_mediacodec,av1_mediacodec"
 PAR="h264,hevc,vp9,av1,png,aac,aac_latm,flac,opus,vorbis,mpegaudio"
 DEM="mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ass,srt,webvtt"
 PRO="file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp"
 BSF="null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts"
 ./configure --target-os=android --enable-cross-compile --cross-prefix=$TC/bin/$TARGET- --cc=$CC --cxx=$CXX --ar=$AR --nm=$NM --ranlib=$RANLIB --strip=$STRIP --arch=aarch64 --cpu=armv8-a --pkg-config=pkg-config \
  --extra-cflags="-I$P/include -ffunction-sections -fdata-sections -fvisibility=hidden" --extra-ldflags="-L$P/lib -Wl,--gc-sections" \
  --disable-gpl --disable-nonfree --enable-version3 --enable-static --disable-shared --disable-vulkan --disable-iconv --disable-stripping --pkg-config-flags=--static \
  --disable-muxers --disable-decoders --disable-encoders --disable-demuxers --disable-parsers --disable-protocols --disable-devices --disable-filters --disable-doc --disable-avdevice --disable-programs --disable-gray --disable-swscale-alpha \
  --enable-jni --enable-bsfs --enable-mediacodec --enable-hwaccels --disable-dxva2 --disable-vaapi --disable-vdpau --disable-bzlib --disable-linux-perf --disable-videotoolbox --disable-audiotoolbox \
  --enable-small --enable-optimizations --disable-runtime-cpudetect --enable-mbedtls --enable-zlib --enable-avutil --enable-avcodec --enable-avfilter --enable-avformat --enable-swscale --enable-swresample \
  --enable-decoder="$DEC" --enable-encoder=png --enable-parser="$PAR" --enable-demuxer="$DEM" --enable-protocol="$PRO" --enable-bsf="$BSF" --enable-network --prefix=$P
 make -j16 && make install; fi
echo ANDDEPS_DONE
