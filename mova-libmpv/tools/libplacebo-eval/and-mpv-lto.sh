#!/bin/bash
# usage: and-mpv.sh SRC NAME PLCPREFIX|none [meson args]  交叉编译 libmpv.so（arm64 Android API24）
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
set -e
SRC=$1; NAME=$2; PLC=$3; shift 3
E=/root/w/mpvt/eval; W=$E/and-build-lto; P=$E/and-prefix-lto
TC=$E/ndk/android-ndk-r25c/toolchains/llvm/prebuilt/linux-x86_64
B=$E/andblto-$NAME
rm -rf $B
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig
[ "$PLC" != none ] && export PKG_CONFIG_LIBDIR=$PLC/lib/pkgconfig:$P/lib/pkgconfig
cat > $E/mpv.android.ver <<EOV
{ global: mpv_*; local: *; };
EOV
cd $SRC
AT=
grep -qs "option(.audiotrack" meson.options meson_options.txt && AT=-Daudiotrack=enabled
meson setup $B --cross-file $W/cross-mpv.ini --buildtype=minsize -Db_ndebug=true -Dauto_features=disabled -Dgpl=false -Dcplayer=false -Dlibmpv=true -Dbuild-date=false -Dtests=false \
 -Dgl=enabled -Dplain-gl=enabled -Degl-android=enabled -Dandroid-media-ndk=enabled -Dopensles=enabled $AT \
 -Dc_link_args="-landroid -llog -lEGL -lc++_static -lc++abi -Wl,--gc-sections -Wl,-Map=$B/libmpv.map -Wl,--exclude-libs,ALL -Wl,--version-script=$E/mpv.android.ver" \
 "$@" > $E/confandlto-$NAME.log 2>&1 || { tail -15 $E/confand-$NAME.log; exit 1; }
ninja -C $B > $E/buildandlto-$NAME.log 2>&1 || { grep -E "error|undefined|FAILED" $E/buildand-$NAME.log | head -15; exit 2; }
SO=$(readlink -f $B/libmpv.so)
cp $SO $E/andoutlto-$NAME.so
$TC/bin/llvm-strip -s $E/andoutlto-$NAME.so -o $E/andoutlto-$NAME.stripped.so
echo "$NAME unstripped=$(stat -c%s $SO) stripped=$(stat -c%s $E/andoutlto-$NAME.stripped.so)"
$TC/bin/llvm-nm -D --defined-only $E/andoutlto-$NAME.stripped.so | awk "{print \$3}" | sort > $E/andexplto-$NAME.txt
comm -23 <(sort /root/w/mpvt/used-syms.txt) $E/andexplto-$NAME.txt | tr "\n" " " | sed "s/^/missing(types ok): /"; echo
echo "undef: $($TC/bin/llvm-nm -D --undefined-only $E/andoutlto-$NAME.stripped.so | awk "{print \$2}" | grep -v "^_Z" | tr "\n" " " | cut -c1-600)"
echo "exported: $(wc -l < $E/andexplto-$NAME.txt)"
