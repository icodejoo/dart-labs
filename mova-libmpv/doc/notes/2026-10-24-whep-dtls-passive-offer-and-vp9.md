# WHEP offer 改 setup:passive（补丁 0012）与 VP9 起播变慢调查

日期：2026-10-24。分支 `feat/whep-receiver`。"实测"是本机/真机跑出来的，"推断"单独标注。证据原件在不入库的 `D:\tmp\mtx\`（m12_*）、`D:\tmp\vp9\`、`D:\tmp\win12\ev\`、WSL `/root/w/t12_*`。

## 结论

- 决策（用户已定）落地为补丁 0012：offer 的 `a=setup` 由 `actpass` 改 `passive`，answer 的 setup 非 `active` 时在解析阶段立刻报清晰错误。**默认配置 SRS 6.0（不配 dtls_role）首次直接出画；MediaMTX 不退化。** Linux(OpenSSL/mbedtls)、Android arm64 真机真实 UDP、Windows(SChannel) 都已测。
- Android 真机对 SRS 的 PLI 复测完成：响应 PLI 的发布端（aiortc WHIP）下首个关键帧 100–147ms（另有一次 706ms），对比 MediaMTX/SRS+RTMP 源的 2.5s。
- NACK 不退化（Android 5%/10%：471/306、696/467；Windows：100/94、208/187）。
- VP9 起播变慢：**复现并定位到现象层，未修**。原因是 v0.41 下 mova 的"先 vo=null 再切 vo=gpu"流程令 mpv 多重建一次视频解码器（mediacodec），在不可 seek 的源上更糟；非 WHEP、非 libmpv 编译问题。见 §4。

## 1. 补丁 0012

- `whep.c`：offer 两个 m 段 `a=setup:passive`；`whep_parse_answer` 里 `strcmp(setup,"active")` 不等即 `Answer a=setup:%s is invalid for our setup:passive offer (RFC 5763 requires active; DTLS client role is not implemented)`，返回 `AVERROR_INVALIDDATA`（原先只校验值属于 active/passive/actpass，passive/actpass 要到 ICE 之后才报 `Unsupported answer setup` 或 `no DTLS from peer`）。`whep_dtls` 里原有的 setup 检查保留不动。二进制 +16B（Android 6,354,032 -> 6,354,048）。
- 更新：`patches/ffmpeg-whep/README.md` 总表与 offer/DTLS 描述；`mock_whep_signal.py`（offer 校验改 passive x2；answer 改 `setup:active`；新增 `/passive` 场景返回 passive answer）；`whep_chunked_regress.sh` 新增负例（passive answer 必须报上述错误）。
- 回归（WSL，ffmpeg n9.0.2 + 0001-0012，两后端）：chunked 回归 http/https x bigcl/big 共 8/8 PASS，负例 2/2 PASS。

## 2. Linux flavor（WSL，`ffprobe -f whep`，各读 60 包以上才算出画）

| 服务端 | 后端 | 结果 |
|---|---|---|
| MediaMTX v1.21.1（Linux 版） | OpenSSL | 出画；首个关键帧 905-913ms（8 轮 8/8；A/B 旧版 0011 二进制同样 8/8，首帧同量级） |
| MediaMTX | mbedtls 3.6.4 | 出画，视频/音频 113/287 包，关键帧 1273ms |
| SRS 6.0.193 默认配置（`dtls_role` 未配，RTMP 推流 rtmp_to_rtc） | OpenSSL | SRS 日志 `DTLS(role=active)`，answer `setup:active`，视频/音频 103/297 包，关键帧 1868ms |
| SRS 默认 | mbedtls | 出画，102/298 包，关键帧 1912ms |

- 注意 1：原 WSL 的 mbedtls 前缀没开 `MBEDTLS_SSL_DTLS_SRTP`（报 `DTLS-SRTP is not supported in this mbedtls build`），所以此前 Linux mbedtls 只测过信令。本次拷一份 mbedtls-src、开该宏装到 `/root/w/mbpfx` 再重配 ff-mb（与 Android 构建同做法）。
- 注意 2：用 SRS+RTMP 推流时 FLV 里音频必须是 AAC（opus 进 FLV 不出音频包，我第一次踩了）。
- 观察到 1 次未复现的偶发：全新起的 MediaMTX 上第一次会话 `ICE connectivity check succeeded ... no DTLS from peer` 超时（OpenSSL，新补丁），之后同条件新起 6 次（旧/新各 3）和连续 16 会话全部正常。无法归因到 0012（pion 在 passive offer 下也回 `setup:active`，抓不到证据），记录在案。

## 3. Android arm64 真机（STG-AL00 7NQBB23606003715，同网段真实 UDP，无 adb reverse、无 UDP 中继）

- 重建：`and.sh`（e2e-arm64.sh，WSL，WHEP=1，含 0012）成功。`libmpv.so`（strip）6,354,048 字节，sha256 `b54e16a0be86aacc16c4287aac2b38107d0bf645f7a303a65b0d5edb70821c43`；`strings` 含 `invalid for our setup:passive`。已替换 `packages/media_kit_libs_android_video_slim_v041/.../arm64-v8a/libmpv.so`（原件备份在 `D:\tmp\mtx\libmpv_prev_0011.so`）。
- 为避免动 example 里别人的 `pubspec_overrides.yaml`/generated 文件，APK 在副本 `D:\tmp\w12\mova` 里构建（`main_whep_verify.dart` + `WHEP_RELAY_ON=false`），APK 内 so 的 sha256 与上面一致。
- **MediaMTX（直连 192.168.254.110:8889，Content-Length 配置）**：出画（见下图证据 `m12_base.png`，色条+时间码正常），`hwdec=mediacodec-copy`，40s 窗口 posDelta 42840ms，首帧 4204ms，关键帧 2613ms。视频 packets=4392，lost=0，nack_seqs_sent=191，rtx_recovered=135，giveup=0。
- **SRS 6.0 默认配置**：SRS 在 WSL（NAT）里，手机直接访问不到。做法：Windows 上用 `whep_tamper_proxy.py`（新增 `BIND/LAN_IP/MEDIA_HOST` 环境变量，LOSS=0 时就是纯转发）监听 `0.0.0.0:18210`，把 answer 候选改写成 `192.168.254.110:18212`，上游 UDP 转到 WSL 的 NAT 地址 `172.31.126.12:8000`（Windows 到 WSL 的 NAT 地址直通，不需要 mirrored 网络、portproxy 也不支持 UDP）。没有新增任何 Windows 防火墙规则（python 入站无需规则，与 10-24 上一轮一致），所以没有需要恢复的防火墙/网络改动。因为媒体面经代理改写，SRS 的 `candidate` 设成 LAN IP 并不起作用（SRS 与 aiortc 联调还必须用 WSL eth0 地址，loopback 候选下 aiortc 发布端不发流），所以本节 SRS 的 `candidate` 实际用 WSL NAT 地址。
  - SRS+RTMP 源：出画，hwdec=mediacodec-copy，首帧 3885ms；视频 packets=8762 lost=88 nack_seqs_sent=358 rtx_recovered=184 giveup=0；音频 lost=133；关键帧 2460ms（pli_sent=2）。
  - **PLI（SRS + aiortc WHIP 发布端，响应 PLI）**：成功的会话首个关键帧 **100.3 / 147.3 / 705.8ms**（`First video key frame out ... since open`，pli_sent=1；发布端日志 `PLI/FIR received` 与会话数对应），app 层首帧 1170/1302/1878ms。对照同机 RTMP/MediaMTX 源 2460-2613ms。WSL 本地同源 77ms，手机上 100-147ms。
  - 失败率：手机 -> 代理 -> SRS 的 aiortc 流连续 7 次里 4 次 `ICE timed out (connectivity check got no valid response)`（成败近似交替），同代理从 WSL 的 ffprobe 连测 6/6 成功，RTMP 源那次也成功。**推断**是 SRS（ice-lite）按源地址/用户名绑定会话，而代理对 SRS 用同一个上游源端口，手机这边在上一会话被 force-stop 后马上重连触发，与客户端无关；未深查，也未在 MediaMTX 直连/经代理上出现。
- **NACK 回归（手机 -> 代理 -> MediaMTX，仅丢包，SEED=777，视频+音频同比例丢）**，括号内为 10-24 同方法的旧值：

| 档位 | 代理丢/总 RTP | 视频 packets | 最终视频 lost | nack_seqs_sent | rtx_recovered | giveup | pli_sent | 音频 lost |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 5% | 465/9225 | 4395 | 14 (11) | **471** (376) | **306** (242) | 26 (13) | 22 (18) | 331 (261) |
| 10% | 908/9349 | 4312 | 11 (14) | **696** (640) | **467** (394) | 28 (32) | 28 (23) | 463 (336) |

  没有退化（丢包注入比例略高于上轮，NACK/恢复数同向增加，最终视频 lost 11/14 与旧值同量级，两档均出画，posDelta≈40s）。任务书里的 522/326、667/451 是另一轮数字，同量级。
- 起播偶发 `h264_mediacodec: Both surface and native_window are NULL` 与 `Failed to open codec in avformat_find_stream_info`：同 10-02/10-24 记录，非新问题。

## 4. VP9 硬解起播变慢（计划第 6 项）

设备同上（STG-AL00，`OMX.qcom.video.decoder.vp9`，`hwdec-current=mediacodec-copy`）。素材：640x360 25fps 30s 合成（testsrc2），H.264/HEVC mp4（faststart）、VP9 webm（libvpx 实时档）、AV1 mkv，本机 HTTP 服务经 `adb reverse tcp:8097`。用 `main_v041_verify.dart` 顺序跑 h264->hevc->vp9（与 10-02 同一测法），v0.41（本次 so）对比 n6 基线（`packages/media_kit_libs_android_video_slim` 的 arm64，6,050,104 B，sha `75e56da5...`，用 `git lfs smudge` 取出）。

首个 position>0（ms，3 轮）：

| 服务端 | 版本 | h264 | hevc | **vp9** | vp9 错误日志条数 |
|---|---|---|---|---|---|
| python http.server（无 Range，不可 seek） | v0.41 | 627/352/550 | 844/942/1042 | **2276/2181/956** | 11/11/5 |
| 同上 | 基线 | 512/283/258 | 641/665/631 | 674/704/650 | 4/4/4 |
| 自写 Range 服务（可 seek） | v0.41 | 657/359/361 | 887/1034/829 | **944/950/854** | 5/5/5 |
| 同上 | 基线 | 611/270/281 | 653/490/627 | 518/700/669 | 4/4/4 |

结论（实测）：
1. 10-02 的现象复现：v0.41 在无 Range 服务上 vp9 出现 ~2.2s 的起播，基线 ~0.7s。
2. 换成可 seek 的服务端，尖刺消失，但 v0.41 仍**系统性比基线慢约 100-350ms，且不限 VP9**（h264 +80ms、hevc +350ms、vp9 +250ms），错误日志恒多 1 条（多一次 `Both surface and native_window are NULL`）。所以"VP9 特别慢"主要是无 Range 服务 + VP9 初始化更重放大出来的。
3. 单独播 720p/360p VP9 或 H.264（单页、同一路径）起播相同（vp9 381ms vs h264 339ms），没有"VP9 解码器本身慢"的证据。

原因（实测日志，`main_whep_verify.dart` 副本里把 mpv 日志全部放行后对比）：
- v0.41（可 seek 源）：播放一次 `Opening decoder vp9_mediacodec` **3 次**，每次后面跟一次 `hr-seek, skipping to 0.0`；触发点是 mpv 日志里的 `Set property: vo="null"`、`android-surface-size=...`（mova 的 `lazyVideo` 流程先 vo=null，视图挂上后再换 vo=gpu），每次视频输出重配都会让 mpv 重建视频解码器链，mediacodec 重新 `MediaCodec started`。基线同流程只重建 **2 次**（opens=2，seeks=2）。
- 不可 seek 的源上（v0.41）还会连环出现 `queuing seek to 0.05 / 0.23 ...` -> `Cannot seek in this stream` -> 再重建，一次 14s 会话里 `Opening decoder` 20 次、seek 15 次，这就是 2s 起播尖刺（**推断**：重建发生在解码器还没出帧时，反复打断出帧）。
- 没有找到 mediacodec 解码器本身失败的证据：`Unsupported or unknown profile`（VP9 profile 初始化时未知，ffmpeg 告警）两版都有，不是慢的原因。

未修、建议：
- 落点不在 mpv 补丁/默认配置：这是 mova 侧 `lazyVideo`（`MovaMpvKernel`）先 `vo=null` 再 `vo=gpu` 的时序 + v0.41 对 vo 重配比旧版更积极地重建解码器。mova 不在 mova-libmpv 范围，所以我没动。建议两条（需用户定）：(a) mova 在 open 之前就把 vo 定下来，避免 null->gpu 的第二次重配（预计省掉 1 次重建）；(b) 若要在 mpv 层做，可评估 mpv 补丁让 `mediacodec-copy` 在 vo 重配时不重建解码器（只有 `mediacodec` 直渲染到 surface 才需要），要先在 v0.41 `video/decode/vd_lavc.c` + `player/video.c` 上做最小验证，风险点是 surface 变化时的正确性，所以不自作主张。
- 对产品的实际影响：可 seek 的源（正常 HTTP Range、HLS）上多约 0.1-0.35s，不再是 2s；只有不可 seek 的源才会遇到秒级尖刺。

## 5. Windows DLL（含 0012）重建与回归

- `build-windows.sh`（MODE=whep，MSYS2 `D:\msys64`，LF 拷贝 `D:\tmp\lf12`，`GIT_CONFIG_*` 绕过 schannel；变量必须在 `bash -l -c` 里 export，从外层带进去会被登录 shell 吃掉，我第一次因此误跑成 base 模式并往 `/c/Users/jelon` 建目录失败，无副作用）。源码缓存拷自上轮 `src`，约 6 分钟。输出新目录 `D:\whep-win\libmpv12\whep\out\libmpv-2.dll`：**10,875,904 字节**（与 0011 版相同，0012 不改变 Windows 体积），sha256 前缀 `afc64742...`。未覆盖 `D:\whep-win\libmpv\whep\out` 与仓库任何 DLL。
- 回归（`smoke-windows.exe`，MediaMTX v1.21.1 Windows 版）：

| 场景 | 结果 |
|---|---|
| Content-Length answer（1309 字节），直连 | answer `setup=active`，DTLS 235ms，视频 737 包 lost=0，12s 内推进 8.04s |
| chunked answer（2205 字节，`Transfer-Encoding: chunked`） | 读到 answer，关键帧 241ms，视频 639 包 lost=0（0011 修复在 0012 下仍有效） |
| 丢包 5%（经代理，30s） | 视频 1816 包 lost=0，nack_seqs_sent=100，rtx_recovered=94，giveup=0（上轮 84/78） |
| 丢包 10% | 视频 1802 包 lost=0，nack_seqs_sent=208，rtx_recovered=187，giveup=0（上轮 212/187） |

## 6. 随手改动（仓库内，未提交）

- 新增 `patches/ffmpeg-whep/0012-...patch`；README 总表/说明。
- `tools/whep-flavor/whep_tamper_proxy.py`：新增环境变量 `BIND`、`LAN_IP`、`MEDIA_HOST`；UDP 上游套接字改绑 `0.0.0.0`（绑 127.0.0.1 时发往非回环上游会失败并让中继线程退出，WSL 的 NAT 地址就是这么踩出来的）；上游给绝对 `Location`（SRS）时去掉主机，保持同源。默认值保持旧行为。
- `mock_whep_signal.py`、`whep_chunked_regress.sh`：见 §1。`build-windows.sh` 头注释 0001-0011 -> 0001-0012。
- `packages/media_kit_libs_android_video_slim_v041/.../libmpv.so` 已换为含 0012 的新件。
- `mova/example/pubspec.lock`、`windows/flutter/generated_*`、`pubspec_overrides.yaml`、`main_win_verify.dart` 是并行任务的改动，我没碰（所有 Flutter 构建都在 `D:\tmp\w12` 副本里）。

## 未解决 / 未做

1. SRS 经代理的手机会话约 4/7 次 ICE 超时（疑似代理单上游源端口 + SRS ice-lite 会话绑定，非客户端），没单独查证；MediaMTX 无此现象。
2. 没有把 SRS 直接放 Windows 跑（SRS 没有 6.0 的 Windows 官方包，且没有再追求"candidate=LAN IP 直连"，代理转发已满足真实 UDP 过 Wi-Fi 的验证）。
3. SRS 上 PLI 的"pli=1 对 pli=0"手机侧 A/B 没做（app 不能传 `rtcp_pli=0`），对照用了 RTMP/MediaMTX 源的关键帧时间。
4. VP9：根因在 mova 侧时序，未改；建议见 §4。
5. 1 次未复现的 MediaMTX 首会话 ICE 后无 DTLS（§2），未归因。
6. 操作失误一条：收尾时用进程名模式停代理/HTTP 服务，误停了并行任务的 `python -m http.server 28080 --bind 127.0.0.1`（需要的话由其所有者重启）；开始时也 `taskkill ffmpeg.exe` 过一次（当时没有别的任务的 ffmpeg 输出在读）。
