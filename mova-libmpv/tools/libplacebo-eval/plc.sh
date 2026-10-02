#!/bin/bash
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
# usage: plc.sh SRC NAME [extra meson args]
set -e
SRC=$1; NAME=$2; shift 2
E=/root/w/mpvt/eval
rm -rf $E/bplc-$NAME $E/plc-$NAME
cd $SRC
meson setup $E/bplc-$NAME --prefix=$E/plc-$NAME --default-library=static --buildtype=minsize -Db_ndebug=true \
 -Dvulkan=disabled -Dd3d11=disabled -Dglslang=disabled -Dshaderc=disabled -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled -Dxxhash=disabled -Dunwind=disabled \
 -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false \
 -Dc_args="-ffunction-sections -fdata-sections -fPIC" -Dcpp_args="-ffunction-sections -fdata-sections -fPIC" "$@" > $E/confplc-$NAME.log 2>&1 || { tail -8 $E/confplc-$NAME.log; exit 1; }
ninja -C $E/bplc-$NAME install > $E/buildplc-$NAME.log 2>&1 || { tail -15 $E/buildplc-$NAME.log; exit 2; }
find $E/plc-$NAME -name "libplacebo*.a" | xargs ls -la
