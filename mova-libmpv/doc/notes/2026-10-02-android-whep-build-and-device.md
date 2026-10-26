# Android arm64 带 WHEP 的 libmpv：构建、体积、真机端到端

日期：2026-10-02。WSL `/root/w/t14`（由 `/root/w/t12/ws` 复制，上游 buildscripts 链；只重编 mbedtls/ffmpeg/mpv）。设备 STG-AL00（`7NQBB23606003715`，全程 `isKeyguardShowing=false`）。

## 构建（实测）

- n9.0.2 + `patches/ffmpeg-whep/0001–0009` + mpv v0.41.0（0001–0004）+ mbedtls 3.4.0 开 `MBEDTLS_SSL_DTLS_SRTP`（其余三个宏 X509_CRT_PARSE_C/KEEP_PEER_CERTIFICATE/TIMING_C 3.4.0 默认已开）。
- flavor 加 `--enable-demuxer=...,whep`、`--enable-protocol=...,dtls`（`whep_demuxer_select` 本就隐含 dtls，显式写出无害）；`--enable-mbedtls --enable-version3 --pkg-config-flags=--static` 本来就在。config.h 确认 `CONFIG_WHEP_DEMUXER/DTLS_PROTOCOL/MBEDTLS/UDP_PROTOCOL=1`。
- 复现：`WHEP=1 patches/android-v041/apply-v041.sh <root>`（脚本的 WHEP 分支我是在已构建树上手工等效执行的，**脚本本身未端到端跑过**，仅 sed/grep 逻辑在树上等价验证）。
- 符号（llvm-nm）：`mpv_lavc_set_java_vm`/`mpv_create_weak_client`/`mpv_wait_event` 导出；`ff_{h264,hevc,vp9,av1}_mediacodec_decoder`、`ff_libdav1d_decoder`、`ff_whep_demuxer`、`ff_dtls_protocol` 均在；NEEDED 同无 WHEP 版。

## 体积（stripped，llvm-strip -s）

| 版本 | 字节 |
|---|---:|
| 无 WHEP（同树，既有） | 6,319,792 |
| WHEP（含 0009 修复，sha256 c62f907b...10d9） | 6,349,952（+30,160，+0.48%） |

增量在目标 ≤+30KB 的边缘（30,720 以内）。归因（粗，LTO 位码对象无法单独量）：`whep*` 符号约 16KB；其余约 14KB 为 SRTP/DTLS 相关、mbedtls 开 SRTP、http Link 头等（**推断**，libmbedtls.a 归档 +9.3KB 仅供参考）。

## 真机 WHEP 端到端（实测）

网络：手机 Wi-Fi 未连接（只有移动数据），电脑有线，**没有共同局域网**；adb reverse 只转 TCP。改用 UDP-over-TCP 中继：手机回环 UDP 38189 <-> TCP 38190（adb reverse）<-> WSL `relay.py` <-> MediaMTX v1.21.1（`/root/w/whep-target-d`，38889/38189/38554，`webrtcAdditionalHosts: [127.0.0.1]`，信令 `adb reverse tcp:38889`）。报文是真实 ICE/DTLS/SRTP，**只有 UDP 这一跳换成 TCP，未覆盖真实 UDP 网络丢包/抖动**。
若要真网络验证：手机连上与电脑同网段的 Wi-Fi（或 USB 共享网络），防火墙放行 UDP 38189，`webrtcAdditionalHosts` 填电脑局域网 IP。

页面 `mova/example/lib/main_whep_verify.dart`，`createMovaEngine` 打开 `whep+http://127.0.0.1:38889/test/whep`，release：

- 首帧：`MovaSizeChange 640x360` @1955ms（open 起算，含 ICE+DTLS+等 IDR）；`MovaReady` 34ms；首个 position>0 @2228ms。
- 连播 40s：position 5280/10360/15400/20240/25240/30280/35320/40360ms，推进率≈1.0；`hwdec-current=mediacodec-copy`，acodec=opus，`estimated-vf-fps=25.0`，`frame-drop-count=0`、`decoder-frame-drop-count=0`；size 640x360。
- 中继计数 40s 时 up=43 / down=4884 个数据报。
- 出画：`adb shell screencap` 取到 testsrc2 彩条画面（含时间码），视频区域正常。
- 崩溃：logcat grep `FATAL EXCEPTION|UnsatisfiedLinkError|Fatal signal|SIGSEGV|SIGABRT|ANR` 无命中。
- DTLS/ICE 日志：mpv `v` 级别下没有 whep 握手细节行（成功路径不打），失败路径的日志见下。

## 过程中发现并解决的三个问题

1. **protocol whitelist 拦 dtls（产品侧缺口，未改库代码）**：media_kit `PlayerConfiguration.protocolWhitelist` 默认 `udp,rtp,tcp,tls,data,file,http,https,crypto`，实测报 `Protocol 'dtls' not on whitelist`。验证页自建 Player 并加 `dtls`。**mova 的默认 `Player()`（`MovaMpvKernel`）要在 WHEP 上线时加 dtls，否则 Android 必失败**。
2. **ffmpeg `tls_mbedtls.c` 悬空指针（真 bug，0009 修复）**：见 patches/ffmpeg-whep/README.md 0009。抓包（relay 里 hexdump）确认 ServerHello 无 use_srtp、对端 alert 0x47。Linux 3.6.7 碰巧不触发。
3. 本机 WSL 里 MediaMTX 的 `webrtcAddress: :38889` 只被转发成 Windows 的 `[::1]`，adb reverse 到 127.0.0.1 不通，改为 `0.0.0.0:38889`。

## 其他观察 / 未做

- 起播后 mova 引擎对该直播源触发 3 次 `Cannot seek in this stream`（MovaErrorEvent ×6，约 2.2s 处，播放不受影响）：mova 层对不可 seek 的 WHEP 流做了 seek（疑似 open 后的位置寄存/续播逻辑），**未定位**，WHEP 接入时需处理。
- `Failed to open codec in avformat_find_stream_info` 警告出现一次（随后 mediacodec 正常），原因未查。
- 未测：丢包/抖动、真实 UDP 网络、长时稳定（>40s）、其他三个 ABI、DTLS 重传。
- 本地不提交的 `example/pubspec_overrides.yaml` 已删；fork 包 `packages/media_kit_libs_android_video_slim_v041` 的 libmpv.so 已更新为 WHEP 版（仍未提交）。MediaMTX d 实例已按 PID 停止（别的实例未动）。
