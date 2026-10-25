# Android 真机：真实 UDP + 0010 的 PLI/NACK 验证

日期：2026-10-24。设备 STG-AL00（华为畅享 60X，`7NQBB23606003715`，全程亮屏解锁）。分支 `feat/whep-receiver`。

## 环境（实测）

- 同网段：手机 `wlan0 192.168.254.136/24`，PC WLAN `192.168.254.110`，同一 Wi-Fi（GlobeAtHome），**不经 adb reverse、不经中继**，媒体面是真实 UDP。ICMP ping 不通（PC 防火墙），但 TCP 8889/UDP 8189 通。
- PC 防火墙三档均开，无法新建入站规则（Access denied，非提权进程）；MediaMTX/python 无需规则即可入站（实测通）。
- 服务端：MediaMTX v1.21.1 windows_amd64（aria2 下载到 `D:\tmp\mtx`，不入库）。`rtspAddress` 改 `:18554`（8554 在 Windows 排除端口段 8497-8596 内，bind 报 forbidden）；关 rtmp/hls/srt。推流：Windows ffmpeg 9.0.2，testsrc2 640x360@25 + sine，h264 baseline 400k `-g 50`，opus 32k，RTSP/TCP 推 `rtsp://127.0.0.1:18554/test`。
- 客户端：`packages/media_kit_libs_android_video_slim_v041` 的 arm64 `libmpv.so`（6,354,272 字节，sha256 `3692f701...636d`，strings 确认含 0010 的 `RTCP %s: nack=...`、`First video key frame out`）。example 临时 `pubspec_overrides.yaml`（已删）指向该包，`flutter build apk --release --target-platform android-arm64 -t lib/main_whep_verify.dart --dart-define=WHEP_RELAY_ON=false`（fvm 3.47.1，首次 535s，增量 ~35s）。
- 对 `mova/example/lib/main_whep_verify.dart` 的改动（未提交，默认行为不变）：`WHEP_RELAY_ON` 开关（false 则不起 UDP-over-TCP 中继）；`/data/local/tmp/whep_url.txt` 运行时覆盖信令地址；`WHEP_TAIL`；结束时 `player.stop()`，并用 mpv `log-file` 落盘后读回打印 RTP/RTCP 汇总（demuxer 关闭时 mpv 事件流已断，logcat 里拿不到汇总，这是第一轮拿不到统计的原因）。
- 丢包工具：`tools/whep-flavor/whep_tamper_proxy.py` 的临时副本（改 0.0.0.0 绑定、候选改写为 PC 局域网 IP、吞 `ConnectionResetError`，副本在会话 scratchpad，未入库），模式 `lossy`，只丢包（SWAP/DUP/CORRUPT=0，SEED=777），丢的是服务端->手机的 RTP（音视频都丢）。信令 `http://192.168.254.110:18100/lossy/test/whep`，MediaMTX 在 127.0.0.1:8189。
- 证据目录（不入库）：`D:\tmp\mtx\`：`base1.txt`/`base2.txt`（直连）、`L0/L5/L10.txt`（经代理，`*.full.log` 为完整 logcat，`*.png` 为 25s 处截屏）、`proxy_L*.log`、`trace_L*.csv`、`bigans_*.txt`、`big_resp.txt`。

## 结果一：真实 UDP 出画（直连 MediaMTX，无代理）

- 出画：40s 观察期 `pos` 推进率 ≈1.0（40049ms 内 posDelta 40040ms），`hwdec-current=mediacodec-copy`，acodec=opus，fps=25.0，`frame-drop-count` 0/0 到 5/0（偶发 vo 丢 5 帧，一次 `Audio device underrun`）。25s 处 `screencap`（`base2.txt.png`）见 testsrc2 彩条+时间码，画面正常。
- 首帧（`MovaSizeChange` 宽高>0，自 open 起）：3981 / 3081 / 1476 / 2015 ms（四轮；含 `First video key frame out at 201.6 / 760.7 ms since open`，即 demuxer 内部从 open 到出首个 IDR 的耗时，其余是 mova/mediacodec 初始化）。
- logcat grep `FATAL EXCEPTION|UnsatisfiedLinkError|Fatal signal|SIGSEGV|SIGABRT|ANR`：未做全量 grep，仅见到 4 轮均无崩溃表现（进程存活、持续出帧）。

## 结果二：0010 的 NACK/PLI/RR 统计（demuxer 关闭时的汇总，mpv log-file 取得）

直连（手机到 PC 的 Wi-Fi 自带丢包，无人工注入），约 50s 会话：

| 轮 | 视频 packets | late/dup | 最终 lost | nack_seqs_sent | nack_msgs | rtx_recovered | rtx_late | giveup | pli_sent | rr_sent | before_keyframe |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| base1 | 3129 | 35 | 0 | 162 | 68 | 127 | 0 | 0 | 2 | 49 | 0 |
| base2 | 3129 | 15 | 2 | 46 | 40 | 29 | 2 | 2 | 4 | 49 | 6 |

经代理人工注入丢包（视频+音频 RTP 同比例丢；代理实际丢包计数取自 `relay FINAL` 末次打印）：

| 档位 | 代理丢/总 RTP | 视频 packets | late/dup | 最终视频 lost | dropped_frames | nack_seqs_sent | nack_msgs | rtx_recovered | rtx_late | giveup | pli_sent | rr_sent | before_keyframe | 音频 lost |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| L0（仅代理） | 0/6575 | 3212 | 17 | 0 | 0 | 60 | 41 | 43 | 0 | 0 | 3 | 50 | 27 | 130 |
| L5 | 347/6702 (5.2%) | 3362 | 105 | 11 | 5 | 376 | 247 | 242 | 11 | 13 | 18 | 51 | 38 | 261 |
| L10 | 686/7069 (9.7%) | 3273 | 158 | 14 | 7 | 640 | 418 | 394 | 14 | 32 | 23 | 49 | 0 | 336 |

三档 40s `pos` 推进均 ≈1.0（L0 41320、L5 42040、L10 40440 ms / 40s 观察窗），均出画，无崩溃表现。

结论（只下实测能支持的）：
1. 真实 UDP 下 0010 的 NACK 生效：视频 `nack_seqs_sent` 随丢包率单调升高（60 -> 376 -> 640），`rtx_recovered` 同升（43 -> 242 -> 394），**即服务端（MediaMTX，无 RTX，原 PT 重发）确实响应 NACK 并重发**，恢复率约 72%/60%/62%（rtx_recovered / nack_seqs_sent，包含重复请求，口径粗）。仍有放弃（giveup 13/32）与晚到（rtx_late），最终视频 lost 11/14、dropped_frames 5/7，**10% 丢包下并非零丢**，与 2026-10-02 回环 5% 随机丢包"视频最终丢包降为 0"的结果不同（那次是回环、低时延；这次 Wi-Fi + 叠加自带丢包）。
2. PLI：起播发 1 次（`First video key frame out ... pli_sent=1`）；丢包档 `pli_sent` 随丢包升高（3 -> 18 -> 23），是 NACK 放弃后补发的恢复性 PLI。**MediaMTX 不响应 PLI（计划已记），所以没有测到 PLI 的起播收益**，只证明客户端会发。
3. RR：约 1 次/秒（`rr_sent` 49-51 / ~50s），符合预期。
4. 音频无 NACK（SDP 里 opus 无 `rtcp-fb nack`，`nack=0`），丢多少是多少（L5 261、L10 336）。
5. 手机到 PC 的 Wi-Fi 本身就有明显丢包：不经代理也有 NACK（base1 162 个），且四轮直连/L0 的音频 `lost` 都在 130-149（几乎一致，是否为 Wi-Fi 真丢包还是 MediaMTX 侧 seq 间隙**未区分**，未解决）。

## 失败现象（原样记录，未修）

**服务端 answer 较大时 WHEP 信令必败**：`whep: Reading WHEP answer failed: I/O error` -> `avformat_open_input() failed` -> `Failed to recognize file format.`，@~200ms。
- 触发：MediaMTX 默认 `webrtcIPsFromInterfaces: true`，PC 有多块网卡（含 Hyper-V/WSL 虚拟网卡），answer 带 8+ 条候选，约 2.4KB。
- 实测：同一 MediaMTX，answer 响应头 `Transfer-Encoding: chunked`（Go 在响应 >2KB 时不带 Content-Length）时，手机失败；把 `webrtcIPsFromInterfaces` 关掉、`webrtcAdditionalHosts: [192.168.254.110]`（answer ~1992 字节，带 `Content-Length`）后成功。经 `whep_tamper_proxy` 的 `ok` 模式转发同样的大 SDP（代理重新用 `Content-Length` 回包）也成功。经 `adb reverse` 走回环 127.0.0.1 同样失败，所以与 Wi-Fi/网络无关。
- 推断（**未验证**）：`whep.c` 的 POST 后读 answer（`whep_exchange_sdp`，`ffurl_read` 循环）在 ffmpeg n9.0.2 http 协议读 chunked 响应时报 EIO；2026-10-02 在 WSL 上能通是因为 answer 小，走的是 Content-Length。这是 WHEP 核心的缺陷（任何返回 chunked answer 的服务端都会触发），按计划不自行 improvise，留待决策与修复；可在 Linux 上用多候选/强制 chunked 的 answer 复现。
- 本轮用的是绕开办法（关 IPsFromInterfaces），所有上表数据均在该配置下取得。

## 其他

- 首轮 logcat 里 mpv 的 verbose 级 whep 日志（`First RTP packet`、RTP/RTCP 汇总）看不到：过滤正则漏词 + demuxer 关闭时事件流已断，改用 `log-file` 解决。
- 起播仍有 `h264_mediacodec: Both surface and native_window are NULL` 重试与 `Failed to open codec in avformat_find_stream_info`（与 10-02 记录一致，非本轮新问题）。
- 未测：SRS 等响应 PLI 的服务端；RTX/TWCC；长时（>40s）稳定性；其他 ABI。
- 收尾：MediaMTX/ffmpeg/代理进程已停，手机 `/data/local/tmp/whep_url.txt` 已删，`adb reverse` 已清，临时 `pubspec_overrides.yaml` 已删，被 pub get 改动的 `pubspec.lock` 与 windows generated 文件已还原。没有提交。

## 复现

1. PC：`D:\tmp\mtx\mediamtx.exe`（`rtspAddress: :18554`，`webrtcIPsFromInterfaces: false`，`webrtcAdditionalHosts: [<PC局域网IP>]`），再用 ffmpeg 推流（命令见上）。
2. `example/pubspec_overrides.yaml` 指向 `../packages/media_kit_libs_android_video_slim_v041`，构建命令见上，`adb install -r`。
3. `adb shell "echo whep+http://<PC IP>:8889/test/whep > /data/local/tmp/whep_url.txt"`，启动 `com.icodejoo.mova.mova_example/.MainActivity`，约 60s 后 `adb logcat -d | grep "WHEP FILELOG"`。
4. 丢包：`LAN_IP=<PC IP> LOSS=5 SWAP=0 DUP=0 CORRUPT=0 UP_URL=http://127.0.0.1:8889 MEDIA_PORT=8189 python whep_tamper_proxy_lan.py 18100`，URL 改 `http://<PC IP>:18100/lossy/test/whep`。
