#!/bin/bash
cd /root/w/mpvt/eval
./and-plc-lto.sh /root/w/mpvt/libplacebo v360-gl -Dopengl=enabled -Db_lto=true
PL=/root/w/mpvt/eval/and-prefix-lto-v360-gl
./and-mpv-lto.sh /root/w/mpvt/src-pin-and pin none -Dlibplacebo=disabled -Db_lto=true
./and-mpv-lto.sh /root/w/mpvt/src-v041-and v041-B1 $PL -Db_lto=true
./and-mpv-lto.sh /root/w/mpvt/src-v041-B3-and v041-B3 $PL -Db_lto=true
echo LTODONE
