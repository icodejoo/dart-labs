#!/bin/bash
# usage: and-plc.sh SRC NAME [meson args]  交叉编译 libplacebo（arm64 Android，最小，无 vulkan）
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
set -e
SRC=$1; NAME=$2; shift 2
E=/root/w/mpvt/eval; W=$E/and-build-lto; P=$E/and-prefix-lto-$NAME
rm -rf $E/andplc-lto-$NAME $P; mkdir -p $P
cd $SRC
meson setup $E/andplc-lto-$NAME --prefix=$P --libdir=lib --cross-file $W/cross-plc.ini --default-library=static --buildtype=minsize -Db_ndebug=true \
 -Dvulkan=disabled -Dd3d11=disabled -Dglslang=disabled -Dshaderc=disabled -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled -Dxxhash=disabled -Dunwind=disabled \
 -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false "$@" > $E/confandplc-lto-lto-$NAME.log 2>&1 || { tail -8 $E/confandplc-lto-$NAME.log; exit 1; }
ninja -C $E/andplc-lto-$NAME install > $E/buildandplc-lto-lto-$NAME.log 2>&1 || { tail -15 $E/buildandplc-lto-$NAME.log; exit 2; }
ls -la $P/lib/libplacebo.a
