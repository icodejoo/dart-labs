#!/bin/bash
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
# usage: mk.sh SRC BUILDNAME PLCINST [extra meson args...]
set -e
SRC=$1; NAME=$2; PLC=$3; shift 3
E=/root/w/mpvt/eval
B=$E/b-$NAME
rm -rf $B
export PKG_CONFIG_PATH=$E/pc:$PLC/lib/pkgconfig:$PLC/lib/x86_64-linux-gnu/pkgconfig
export PKG_CONFIG_LIBDIR=$E/pc:$PLC/lib/pkgconfig:$PLC/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig
cd $SRC
meson setup $B --buildtype=minsize -Db_ndebug=true -Dauto_features=disabled -Dgpl=false -Dcplayer=false -Dlibmpv=true -Dbuild-date=false \
  -Dgl=enabled -Dplain-gl=enabled \
  -Dc_args="-ffunction-sections -fdata-sections" \
  -Dc_link_args="-Wl,--gc-sections -Wl,-Map=$B/libmpv.map -Wl,--exclude-libs,ALL -Wl,--version-script=$E/mpv.ver -Wl,--as-needed -static-libstdc++ -static-libgcc" \
  "$@" > $E/conf-$NAME.log 2>&1 || { tail -15 $E/conf-$NAME.log; exit 1; }
ninja -C $B > $E/build-$NAME.log 2>&1 || { grep -E "error|undefined|FAILED" $E/build-$NAME.log | head -15; exit 2; }
SO=$(ls $B/libmpv.so.2.*.* | head -1)
cp $SO $E/out-$NAME.so
strip -s $E/out-$NAME.so -o $E/out-$NAME.stripped.so
echo "$NAME unstripped=$(stat -c%s $SO) stripped=$(stat -c%s $E/out-$NAME.stripped.so)"
nm -D --defined-only $E/out-$NAME.stripped.so | awk "{print \$3}" | sort > $E/exp-$NAME.txt
comm -23 <(sort /root/w/mpvt/used-syms.txt) $E/exp-$NAME.txt | tr "\n" " " | sed "s/^/missing(types ok to ignore): /"; echo
echo "undef(unversioned): $(nm -D --undefined-only $E/out-$NAME.stripped.so | grep -v GLIBC | grep -v " w " | awk "{print \$2}" | tr "\n" " ")"
echo "exported: $(wc -l < $E/exp-$NAME.txt)"
