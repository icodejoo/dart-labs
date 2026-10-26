#!/bin/bash
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
cd /root/w/mpvt/eval
P360=/root/w/mpvt/eval/plc-v360-min; P360G=/root/w/mpvt/eval/plc-v360-gl; P361=/root/w/mpvt/eval/plc-v361-min
./plc.sh /root/w/mpvt/libplacebo-361 v361-gl -Dopengl=enabled
./mk.sh /root/w/mpvt/src-pin pin /root/w/mpvt/plc-inst -Dlibplacebo=disabled
./mk.sh /root/w/mpvt/src-v041 v041-B1 $P360
./mk.sh /root/w/mpvt/src-v041 v041-B2 $P360G
./mk.sh /root/w/mpvt/src-v041-B3 v041-B3 $P360
./mk.sh /root/w/mpvt/mpv-src head-C1 $P361
./mk.sh /root/w/mpvt/mpv-src head-C2 /root/w/mpvt/eval/plc-v361-gl
./mk.sh /root/w/mpvt/mpv-src-C3 head-C3 $P361
./mk.sh /root/w/mpvt/src-pin pin-lto /root/w/mpvt/plc-inst -Dlibplacebo=disabled -Db_lto=true
./mk.sh /root/w/mpvt/src-v041 v041-B1-lto $P360 -Db_lto=true
./mk.sh /root/w/mpvt/src-v041-B3 v041-B3-lto $P360 -Db_lto=true
./mk.sh /root/w/mpvt/mpv-src head-C1-lto $P361 -Db_lto=true
./mk.sh /root/w/mpvt/mpv-src-C3 head-C3-lto $P361 -Db_lto=true
echo ALLDONE
