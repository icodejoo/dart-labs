# libmpv 内置 WebRTC 直播拉流（WHEP 接收端）— 落地计划（2026-10-01）

> **执行者说明**：本计划由规划 agent 拆解，交落地 agent 逐 Task 执行，分支 `feat/whep-receiver`。
> **一个 Task = 一次独立 commit（提交信息带实测数字）+ 一次可复现的验证**。遇到本计划没覆盖的判断
> （某步编译报缺依赖、某个 API 与预期不符、许可存疑），**停下来，把原样现象记入文末"执行记录"，
> 不要自行 improvise 换库、加依赖或改已定决策**。
> 所有落地代码与文档都在 `mova-libmpv/` 下（构建链、补丁、flavor、CI）。**mova-libmpv 只做 libmpv 的
> 编译与瘦身，不涉及业务**：URL 映射、低延迟配置落点、UI 降级等 mova 侧工作**不在本计划内**，另行立项。
> 凡本文写"未核实"的，落地前先用阶段 0 的小验证核实，不要当事实用。

## 当前状态与下一步（交接，2026-10-02）

**状态：规划与选型调研已完成，代码一行未动。** 分支 `feat/whep-receiver`（已推送 codeup 与 GitHub），下一步从 **T0.1（建回归基线）** 开始。

已定的关键决策（细节见 §0.1、§8.2、T0.2 修订）：
- ffmpeg 升到 **n9.0.2**；mpv 用 **v0.41.0**（不再钉死旧 commit）+ 最小静态 libplacebo + **摘 `vo_gpu_next`** 补丁；兼容补丁 `pin-n9-compat.patch` 作废。
- 体积是首要目标。实测摘 `vo_gpu_next` 后相对钉死基线只多约 15 万字节（Android 整链 LTO：6,615,960 → 6,768,032）。
- **D3 的实际口径是 Q1=(b)**：用户授权专家决定，默认**不拷** libjuice，只把 NACK 多 FCI 打包按 libdatachannel 的逻辑移植成 C；`whip.c` 的 STUN/ICE 不够再拷 `stun.c`。MPL-2.0 许可义务见 §6 / Task L1。
- mova-libmpv **只做编译与瘦身，不涉及业务**；URL 映射、低延迟参数落点、UI 降级都不在本计划，本计划只"开放参数"。
- iOS/macOS 本期不做 WHEP（securetransport 无 DTLS，无 Mac）；默认 flavor 保持钉死 mpv + n6.0.1，WHEP flavor 单独用 n9 + v0.41.0。

配套资料（都在本分支）：
- 极致瘦身配置：[../notes/2026-10-02-extreme-slim-config.md](../notes/2026-10-02-extreme-slim-config.md)（Linux 同口径极致档 8,754,480 字节 vs 评估基线 9,209,384；Android/Windows/iOS/macOS **未跑**）。
- 评估用补丁与脚本：[../../tools/libplacebo-eval/](../../tools/libplacebo-eval/README.md)（含 `b3-v041.patch`、`javavm-v041.patch`；freetype bz2 改动**未做成补丁**）。
- 旧分支 ffmpeg 9 线存档（对比参考，非现行）：[../../reference/ffmpeg9-zhangfly/](../../reference/ffmpeg9-zhangfly/README.md)。
- WSL 评估机产物在 `/root/w/mpvt/`（换机器就没了）；WSL 已调到 18 核（`~/.wslconfig`）。

**落地前必须先核实的"未核实"项（按优先级）**：
1. Android 上 v0.41.0 + libplacebo(GL) 的真机播放（只在 x86 编过链接过，没跑）；`mpv_lavc_set_java_vm` 补丁对 0.41 是手工移植的。
2. n9.0.2 上 `whip.c`/`tls_*.c` 的行号与结构（文中行号多来自 master `0b01ed76`）；mingw 头是否带 `SECPKG_ATTR_DTLS_MTU`；Android mbedtls 开 DTLS-SRTP 宏的实际机制；`ff_srtp_decrypt` 签名。
3. WHEP 注册成 demuxer 还是 protocol，mpv 如何探测 `AVFMT_NOFILE`（T0.3）。
4. 瘦身配置里的高风险项（去 unwind 表、`-Dauto_features=disabled`、去 dav1d、mbedtls 裁剪、RELR）在 Android/Windows 上的实际收益与回归。
5. MPL-2.0 与 LGPLv3 合并分发的合规复核（我读的是官方原文与 FAQ，**不是法律意见**）。

## 0. 目标与边界

**目标**：libmpv 直接打开 WebRTC 直播流（WHEP 拉流），mova 的 Dart 内核（`MovaKernel`）不改，不引入
`flutter_webrtc`，不引入整套 libwebrtc。

### 0.1 已定决策（用户拍板，本计划不重开）

| # | 决策 | 备注 |
|---|---|---|
| D1 | 落地在 mova-libmpv（构建链/补丁/flavor/CI），**只做编译与瘦身**；mova 侧（URL 映射、低延迟配置落点、UI 降级）不在本计划内，本计划只负责**开放可调参数** | 不碰 `MovaKernel`、不碰 `mova/` |
| D2 | ffmpeg 从 n6.0.1 升到 **n9.0.2**（n9.1-dev 不选） | n9.0.2 已核实含 `whip.c`、`dtls_protocol`、`tls_mbedtls.c`/`tls_schannel.c` 的 DTLS-SRTP 导出；`tls_securetransport.c` 无 DTLS；**无 WHEP demuxer** |
| D3 | 以 `whip.c` 为底新写 WHEP 接收端；NACK 重传检测、ICE 兼容等逻辑**直接拷贝** libdatachannel / libjuice 相关源文件；RTP 解包复用 `rtpdec*.c`、SDP 复用 `rtsp.c`/`sdp` 代码；DTLS 用平台后端：Windows=SChannel，Android=自建 mbedtls（开 `MBEDTLS_SSL_DTLS_SRTP`） | iOS/macOS 无 DTLS 后端，**本期不做，单列待定** |
| D4 | libdatachannel / libjuice 为 MPL-2.0；走 §3.3 Larger Work 以 LGPL 分发；需独立"许可与合规"Task | 见 §6 与 Task L1 |
| D5 | 新协议做成**可选 flavor，默认关闭**，不影响现有产物体积；顺序 WSL(Linux) → Windows → Android；iOS/macOS 待定 | |
| D6 | 不猜用户意图；多方案时列"待决问题"并给推荐（D1–D5 不重开） | 见 §8 |

> **关于 D3 "直接拷贝"的实测发现（必须先读，详见 §5 与 §8 Q1）**：规划阶段实际读了
> libdatachannel v0.24.6 / libjuice 源码，结论与 D3 的预设有出入——**libdatachannel 没有接收端 NACK
> 缺口检测**（只有发送端的 `RtcpNackResponder` 和 NACK 包结构体），且它是 C++17，ffmpeg libavformat
> 是纯 C，**不能直接拷贝编译**。本计划没有擅自改 D3，而是在 §5/§8 把事实摆出来、给推荐，待用户拍板。
> 在 Q1 拍板前，依赖 D3 的 Task（T1.5 的"拷贝"部分、T-L1 的拷贝清单）按"推荐方案"预排，标 **[待 Q1]**。

### 0.2 范围

做：WHEP 拉流（H.264 + Opus 起步；VP8/VP9/AV1 视服务器协商另议，见"不做"）、NACK 重传、PLI、RR、
Linux/Windows/Android 三平台，并通过 demuxer 的 AVOption 与 mpv 现有选项**开放低延迟相关可调参数**（只开放，不替业务定默认策略）。

不做：见 §10。

## 1. 现状与事实基线（引用时保留"实测/未核实"口径）

### 1.1 ffmpeg / TLS 现状（README 记录）

| 平台 | ffmpeg | TLS 后端 | 构建链 |
|---|---|---|---|
| Android 四 ABI | n6.0.x（`libmpv-android-video-build @1ecf510`，NDK r25c） | 自建 mbedtls（3.x，需 `--enable-version3`，产物 LGPLv3） | `flavors-mova-slim.sh` + `libmpv-android-video-build.patch` |
| Linux x86_64 | n6.0.1 | openssl（LGPLv2.1） | CI `linux` job，`ubuntu-22.04`，apt 依赖 |
| Windows x86_64 | n6.0.1 | SChannel；mpv 一步用 clang（规避 gcc 16.2 miscompile） | CI `windows` job，MSYS2 MINGW64 |
| iOS/macOS | `media-kit/libmpv-darwin-build`（Nix+Xcode），`movaslim` flavor patch | securetransport | `libmpv-darwin-build-mova-slim.patch` |

- CI 工作流在 monorepo 根：`C:\workspace\dart-labs\.github\workflows\build-mova-libmpv.yml`（1323 行，规划时读取的版本）；
  jobs：`android-arm64`/`android-other-abi`/`darwin`/`ios`/`linux`/`windows`。
- mpv 固定在 commit `78d43740f52db817d98bcf24fb30a76ab6fa13ff`（workflow 注释：更新的 mpv main 需要更新的
  libavcodec；"meson: found 60.3.100 but need >= 60.31.102"）。**这是升级 n9.0.2 的头号隐患，见 §7 R1。**
- README 记录"v9 线 zhangfly 分支（ffmpeg n9.0 + mpv 0.41）已作废，别复用其代码或数据"——本计划不复用。

### 1.2 规划阶段亲自核实的源码事实

核实环境：WSL `~/w/ffmpeg`（ffmpeg master，HEAD `0b01ed76`，工作区是 nativewaves WHEP 补丁移植版 wp2 分支，
**不是 n9.0.2 tag**——本地仓库只有 1 个 tag；以下行号均为该 master 版本，**落地前需在 n9.0.2 重核行号**）
与 `~/w/ldc`（libdatachannel v0.24.6，commit `6b1e2e620f1e37f0eafeee702eaea0043cb305fd`，含 `deps/libjuice`）。

| 事实 | 位置（版本） | 状态 |
|---|---|---|
| `ff_rtp_demuxer` 是 `AVFMT_NOFILE` 的 demuxer（`.p.flags = AVFMT_NOFILE`） | `libavformat/rtsp.c:2871-2875`（master @0b01ed76） | 已核实 |
| ffmpeg **已有接收端缺口检测 + NACK/PLI 构造**：`find_missing_packets`、`ff_rtp_send_rtcp_feedback`（PLI；NACK 每次只带 1 个 FCI：`first_missing`+16 位 mask；SSRC 用 `s->ssrc+1`） | `libavformat/rtpdec.c:469-530`（master） | 已核实 |
| `RTPDemuxContext` 乱序队列 `queue_size`、`ff_rtp_check_and_send_back_rr` | `rtpdec.c:313`、`:538-553`、`:887-910` | 已核实 |
| `ff_srtp_decrypt(SRTPContext*, uint8_t *buf, int *lenptr)` 按 `RTP_PT_IS_RTCP` 同时处理 RTP/RTCP，**注释 "TODO: Missing replay protection"** | `libavformat/srtp.h:48`、`srtp.c:127-141` | 已核实 |
| `whip.c` 已建 `srtp_recv` 并用 `ff_srtp_decrypt` 解 SRTCP（但没有接收 RTP 路径） | `whip.c:1493`、`:1975` | 已核实 |
| `dtls_protocol_deps_any="openssl schannel gnutls mbedtls"`；schannel 的 DTLS 探测依赖 `SECPKG_ATTR_DTLS_MTU` | `configure:4115`、`:7619`；`tls_schannel.c:1096`（n9.0.2 实测；原 `4096-4097`/`7521`/`1100` 来自 master，`4096-4097` 在 n9.0.2 是 `rtmps_protocol_select`） | 已核实（**mingw-w64 头文件是否带该宏：未核实**，见 R6） |
| `tls_mbedtls.c` 在 `MBEDTLS_SSL_DTLS_SRTP` 下导出 SRTP 密钥材料（`ff_dtls_export_materials`），只配 `MBEDTLS_TLS_SRTP_AES128_CM_HMAC_SHA1_80`；无该宏时报 "DTLS-SRTP is not supported in this mbedtls build" | `tls_mbedtls.c:281-323`、`:515-518`、`:656-664` | 已核实 |
| libdatachannel mbedtls 后端同样只配 AES128_CM_HMAC_SHA1_80；openssl 后端先试 AEAD_GCM 再回退 | `src/impl/dtlstransport.cpp:380-382`、`:421`、`:818-833` | 已核实 |
| libdatachannel **接收端没有 NACK 生成**：`RtcpReceivingSession` 只做 SR→RR、REMB、PLI、序号统计（`initSeq`/`updateSeq`）；`RtcpNackResponder` 是**发送端**（收到 NACK 后重发）；仅 `rtp.cpp:672-720` 有 NACK 包结构（`RtcpNack::preparePacket`/`addMissingPacket`，多 FCI 打包） | `src/rtcpreceivingsession.cpp`（251 行）、`src/rtcpnackresponder.cpp`（113 行）、`src/rtp.cpp:672-720`（v0.24.6） | 已核实（grep "nack"） |
| libjuice 全是 C；`stun.c`（1256 行）依赖 `base64.h/const_time.h/crc32.h/juice.h/log.h/udp.h`；`hmac.c`/`hash.c` 依赖 `picohash.h`；`random.c` 依赖 `log.h/thread.h`；`agent.c` 2799 行，带 conn_poll/conn_thread 线程模型 | `deps/libjuice/src/`（v0.24.6 随附） | 已核实 |
| libdatachannel/libjuice 源文件头：`stun.c`、`hmac.c`、`crc32.c`、`rtcpreceivingsession.cpp`、`rtcpnackresponder.cpp` 均只有标准 MPL-2.0 声明；`picohash.h` 头是 Kazuho Oku 的 public domain 声明（非 MPL）；`include/rtc/version.h` 无许可头 | 同上 | 已核实（抽样 5 个 .c/.cpp + picohash.h + version.h，**非全量逐文件核对**，T-L1 要全量核） |

### 1.3 用户提供的事实（未亲自复核，沿用其口径）

- `whip.c`（master，2218 行）：SDP offer 生成 `:608`、HTTP 信令 `exchange_sdp :772`、`parse_answer :894`（只取
  ice-ufrag/pwd/candidate）、ICE `ice_create_request :1024`/`ice_handle_binding_request :1222`/`udp_connect :1262`、
  DTLS `ice_dtls_handshake :1300`、SRTP `setup_srtp :1419`、发送端 RTP 历史/NACK/RTX
  （`rtp_history_store :1509`、`handle_rtx_packet :1885`、`handle_nack_rtx :1948`）、RTP 打包
  `create_rtp_muxer :1593`。只支持 H264+Opus，payload type 写死（H264=106、Opus=111、rtx=105）。
  **没有**：接收端抖动缓冲/重排序、接收 RTP 的 SRTP 解密、PLI、NACK 触发逻辑、TWCC/REMB、TURN/trickle/ICE restart。
- nativewaves WHEP 补丁系列（6 个补丁，依赖 libdatachannel，demuxer 约 246 行），WSL 已有移植版：`~/w/ffmpeg` 分支 wp2
  （本次所见：`libavformat/webrtc.c` 410 行、`Makefile:624 CONFIG_WHEP_DEMUXER += webrtc.o webrtc_demux.o`、
  `configure:3560 whep_demuxer_deps="libdatachannel sdp_demuxer"`）、补丁 mbox 在 `~/w/wp/mb/{1..6}.mbox`、
  libdatachannel 在 `~/w/ldc`。**仅作 WHEP demuxer 结构参考**；其依赖整套 libdatachannel，不是本方案路线。
- 体积实测见 §4。

### 1.4 未核实项（阶段 0 负责核实）

1. WHEP 注册为 demuxer 还是 protocol，mpv 如何对 `AVFMT_NOFILE` demuxer 取流（是否绕过 mpv 自己的 stream 层、是否受 lavf
   protocol whitelist 限制）。
2. SDP answer → `AVStream` 能否脱离 RTSP 上下文复用（`rtsp.c` 的 `sdp_read_header`/`ff_sdp_parse` 与 `RTSPState`
   的耦合程度）。
3. n6.0.1→n9.0.2 后 mpv `78d43740f5` 能否编译（见 R1）。
4. mingw-w64 是否有 `SECPKG_ATTR_DTLS_MTU`（R6）。
5. Android 自建 mbedtls 打开 `MBEDTLS_SSL_DTLS_SRTP` 后 `use_srtp` 完整性（`tls_mbedtls.c` 里 `mbedtls_ssl_set_export_keys_cb`
   在 mbedtls 3.x 的可用性）。
6. SRS 的 WHEP/whip-play 接口形态（我印象 SRS 有 `/rtc/v1/whip-play/`，**未核实**）。
7. mova 是否对外暴露 mpv 属性注入（`mpv_kernel.dart` 内部有 `setProperty`，`MovaOpts` 层是否有出口：**未核实**）。

## 2. 架构决策表

| # | 决策点 | 选择 | 理由 / 依据 |
|---|---|---|---|
| A1 | 新增文件形态 | 新写 `libavformat/whep.c`（+ 视需要 `whep_*.c`），以补丁形式放 `mova-libmpv/patches/ffmpeg-whep/*.patch` | 不指望上游合并（ffmpeg 官方 LICENSE.md 未提 MPL）；补丁与 ffmpeg tag 绑定，升 tag 时手工 rebase |
| A2 | 是否改 `whip.c` | **不改**；`whep.c` 自带一份所需的 ICE/DTLS/SRTP 代码（先拷后抽公共） | 避免与上游 `whip.c` 演进冲突；抽公共头留作后续（待决 Q6） |
| A3 | 注册方式 | demuxer（`FFInputFormat ff_whep_demuxer`，`AVFMT_NOFILE`，`read_probe` 认 URL 前缀）**预案**；protocol 方案作 plan B | 与 `ff_rtp_demuxer`/nativewaves 同构；但 mpv 取流行为未核实，T0.3 验证后定 |
| A4 | 编译开关 | `--enable-demuxer=whep` 仅在 `*-whep` flavor；默认 flavor 不含 | D5：默认产物体积不变 |
| A5 | 拉流 RTP 解包 | 复用 `rtpdec.c`（含乱序队列）+ `rtpdec_h264.c`/`rtpdec_opus.c` | 用户 D3；§1.2 已核实乱序队列、RR、PLI/NACK 构造均在 |
| A6 | SDP 解析 | 复用 `rtsp.c` 的 `ff_sdp_parse`（视 T0.3 耦合度，必要时抽取最小子集） | D3 |
| A7 | SRTP | 复用 `srtp.c` 的 `ff_srtp_decrypt`/`ff_srtp_set_crypto`；**自补重放保护**（该函数注释标明缺失） | 已核实 |
| A8 | DTLS 后端 | Windows=SChannel；Android=mbedtls+`MBEDTLS_SSL_DTLS_SRTP`；Linux（开发验证）=openssl 或 mbedtls；iOS/macOS 待定 | D3；Linux 仅作"先打通"平台，出货与否见 Q8 |
| A9 | 编解码范围 | H.264 + Opus（对齐 `whip.c`、与现有 flavor 解码器白名单一致） | 现有 flavor 已含 `h264`/`opus` decoder 与 parser |
| A10 | 版本口径 | 先让 `*-whep` flavor 用 n9.0.2；默认 flavor 回归全绿后再切（见 Q3） | 把"升级风险"与"默认产物"解耦，可回滚 |
| A11 | 许可分发 | LGPL 主体 + MPL 拷贝文件保留头；随包附 MPL 全文与源码获取说明 | D4；法务复核见 T-L1 |

## 3. 阶段划分与理由

| 阶段 | 内容 | 为什么这样排 |
|---|---|---|
| 0 | 升级 ffmpeg 到 n9.0.2 + 全量回归 + WHEP 可行性小验证 | 升级是最大的不确定性（R1）；必须先证明"升了不退化、mpv 能配"，否则后面全是空中楼阁。可行性小验证成本低，决定 A3/A6 |
| L | 许可与合规（贯穿，**第一次拷贝文件的 commit 之前**完成登记骨架） | 拷贝一旦入库就产生义务，先建登记表 |
| 1 | Linux(WSL) 打通 WHEP | 构建最快、有 netem/docker，能快速迭代协议；不碰平台 DTLS 差异 |
| 2 | Windows(SChannel) | 真机桌面可直接 `flutter run -d windows` 验证 |
| 3 | Android(mbedtls+DTLS-SRTP) | 最重（自建 mbedtls、NDK、四 ABI、真机），放最后；Android 才是移动端主战场 |
| ~~4~~ | ~~mova 侧 URL 映射/低延迟/UI~~ | **已移出本计划**：mova-libmpv 不涉及业务，mova 侧另立项 |
| 待定 | iOS/macOS | 无 DTLS 后端 + 无 Mac |

## 4. 体积预算表

> 口径：用户在 WSL x86_64 上以 ffmpeg master + mbedtls 3.6.7、strip 后 `.so`、**最小子集（不含 mova 完整解码器白名单）**
> 实测；**不是 mova 真实 flavor 的增量，也不是 Android/Windows 产物**（未核实）。仅作量级参考。

| 配置 | strip 后字节 | 相对 A |
|---|---:|---:|
| A 基线（最小子集） | 2,634,144 | — |
| + whip muxer | 2,741,072 | +106,928 |
| + rtp + sdp demuxer（偏大上界：rtp demuxer 把全部 depacketizer 绑在一起） | 2,938,224 | +304,080（≈297KB） |
| whep.c 新写 1200–2000 行的额外估计 | 未编译 | 推算 +几十 KB（**推算，未编过**） |
| **WHEP flavor 预期增量** | — | **≈0.3–0.35MB** |

| 对照 | 增量 / 体积 | 口径 |
|---|---|---|
| libdatachannel 全套路线 | +1.22MB（动态 libstdc++）/ +1.86MB（静态） | 用户实测，已否决路线 |
| flutter_webrtc arm64 原生库 | 11.38MB | 用户实测，已否决路线 |
| 默认 flavor（WHEP 关闭） | **±0**（验收：与 T0.1 基线逐字节一致或仅随 n9 升级变化，且变化单独记录） | 验收项 |
| 现有基线（供对照，T0.1 重测） | Android arm64 6,050,104（README 多平台表，2026-09-18 CI）；Windows 14,033,920（clang，2026-09-24）；Linux 7,550,784（2026-09-17）；iOS dist 5,741,680 / 6,534,448 两处记录不一致 | README；**各处数字口径不一，T0.1 统一重测** |

预算红线（建议）：任一平台 WHEP flavor 相对"同 n9.0.2、WHEP 关闭"的增量 ≤ 0.5MB；超出须在执行记录里归因（用 Windows 计划 Task 0 的 map 文件归因法）。

## 5. 关于"直接拷贝 libdatachannel / libjuice"——规划阶段的事实核查（须用户拍板，见 Q1）

### 5.1 能直接拷（C，MPL 头完整）的只在 libjuice

| 文件（libjuice v0.24.6 随附） | 作用 | 依赖链（实测 include） | 判断 |
|---|---|---|---|
| `stun.c/.h` | STUN 报文读写、MESSAGE-INTEGRITY、FINGERPRINT | `base64`、`const_time`、`crc32`、`juice.h`、`log`、`udp.h`（后者带出 `addr_record_t`、`addr.c`、socket 抽象） | 可拷但需连带约 8–10 个文件或打桩 |
| `hmac.c`、`hash.c`、`picohash.h` | HMAC-SHA1 | `picohash.h`（public domain，非 MPL） | ffmpeg 已有 `av_hmac`，拷贝无增量 |
| `crc32.c` | STUN FINGERPRINT 的 CRC32 | 无 | ffmpeg 已有 `av_crc` |
| `agent.c`（2799 行）、`conn_*.c`、`turn.c` | 完整 ICE agent（连通性检查、提名、保活、TURN） | 自带线程/poll 模型、socket 抽象 | **不可剥离**；整体引入 ≈ 引入第二套网络 I/O 模型 |

**事实**：`whip.c` 已有自己的 STUN（`ice_create_request`/`ice_handle_binding_request`）和单 host candidate 连通性检查，
功能上与 libjuice `stun.c` 重叠；拷 `stun.c` 的收益只在"更完整的 STUN 属性处理"。

### 5.2 只能改写成 C 的（libdatachannel，C++17）

libdatachannel 的 `rtcp*.cpp`/`rtp.cpp`/`impl/*.cpp` 使用 C++17（`std::shared_ptr`、`message_vector`、`mStorage` 等），
ffmpeg libavformat 是纯 C 且不链接 libstdc++——**无法直接拷贝编译**，只能逐行翻译成 C 或只参考逻辑自写：

| libdatachannel 逻辑 | 位置 | 对我们的价值 |
|---|---|---|
| NACK 包构造（多 FCI 打包 `addMissingPacket`） | `rtp.cpp:712-728` | **有价值**：ffmpeg `ff_rtp_send_rtcp_feedback` 每次只发 1 个 FCI（16 位 mask），突发丢包时不够用；该函数十几行，翻译成 C 很直接 |
| 接收端缺口检测 / 重发请求节奏 | **不存在**（v0.24.6 无此模块） | **无可拷**；ffmpeg `rtpdec.c:find_missing_packets` 已有基础版 |
| `RtcpReceivingSession`（RR/REMB/PLI/序号统计） | `rtcpreceivingsession.cpp` | RR/PLI ffmpeg 已有；REMB 可参考（本期不做，见"不做"） |
| DTLS/SRTP 配置（profile 选择、证书指纹） | `impl/dtlstransport.cpp`、`dtlssrtptransport.cpp` | 仅参考：profile 与 ffmpeg 的 `tls_mbedtls.c` 一致（AES128_CM_SHA1_80） |
| ICE 状态机细节 | `impl/icetransport.cpp`（982 行，封装 libjuice） | 仅参考 |

### 5.3 对 D3"直接拷贝文件"的影响（如实）

1. 对"直接拷贝文件"的字面落地，**只剩 libjuice 的 C 文件**，且其中有价值的（`stun.c`）与 `whip.c` 现有代码重叠，其余要么 ffmpeg 已有等价物，要么不可剥离。
2. **libdatachannel 的 NACK"接收端检测"并不存在**，不是"C++ 改写"问题，而是没有东西可拷。真正可借鉴的只有 NACK 多 FCI 打包的十几行。
3. 逐行翻译 C++→C 的文件，按 MPL 属于派生（Covered Software 的修改），**仍要保留 MPL 头并按文件级 copyleft 公开**；只"读懂算法后自己写"则不继承 MPL。这是我的理解，**不是法律意见，未核实**，交 T-L1 请有资质的人复核。
4. 因此"直接拷贝"决策的实际收益远小于预期，而代价（MPL 登记、双许可分发、法务复核）是确定的。

**推荐（Q1）**：保留 D3 的方向，但把落地口径调为"**按需拷贝/移植**"——默认不拷贝 libjuice；NACK 多 FCI 打包按
`RtcpNack::addMissingPacket` 的逻辑移植到 C（该文件头保留 MPL，按 T-L1 登记）；只有当 T1.3 实测发现
`whip.c` 的 STUN/ICE 对目标服务器（SRS/MediaMTX）不够用时，才拷 libjuice `stun.c` 及其必要依赖。这样合规面最小，
又不放弃 D3 里"逻辑直接来自成熟实现"的意图。若用户坚持字面"拷贝 libjuice 全套"，T1.3 按 §5.1 表连带拷贝并在 T-L1 全量登记。

## 6. Task 清单

> 预估工作量为人天，含验证与文档；**无依据的估算已标"粗估"**。验收标准遵循 mova CLAUDE.md："真机验证前先设计基于
> 真实事件的测量方法"，不用墙钟计时，每次防缓存、多次取平均。

### 阶段 0：升级 ffmpeg 到 n9.0.2 + 可行性验证

#### T0.1 固化回归基线（零功能变化，纯测量）

- **目标**：在改任何东西前，把 n6.0.1 现状的体积、符号、能力清单落成"可重复执行的检查脚本 + 基线表"，作为后续所有 Task 的对照。
- **涉及文件**：新增 `mova-libmpv/tools/regress/`（`check-symbols-linux.sh`、`check-symbols-android.sh`、`check-symbols-windows.sh`、`baseline.md`）；
  CI 的 "Strip and verify" 步骤已有的校验迁移/复用，不重复造。
- **做什么**：
  1. 对 `dist/` 下现有产物（`android arm64-v8a/armeabi-v7a/x86_64/x86`、`windows-x86_64`、`linux-x86_64`、`ios-arm64`、`macos-*`）重测字节数，写入 `baseline.md`；统一 README 里口径不一的数字（见 §4 末行）。
  2. 把 §7 回归清单里"可自动化"的条目写成脚本：符号检查（`mpv_lavc_set_java_vm`、4 个 `*_mediacodec` 硬解符号、`dav1d_*`、VP8/MJPEG 不存在、公开 API 符号）、LGPL 许可 grep、协议列表 grep。
- **验收**：脚本对现有 n6.0.1 产物全绿；`baseline.md` 每个数字带"字节数 + 来源 run id/commit"。
- **工作量**：1.5 人天。

#### T0.2 ffmpeg n9.0.2 与 mpv 配对 spike（WSL，Linux 先行）

- **目标**：回答"n9.0.2 + 哪个 mpv commit 能编译并跑通基本播放"（R1）。**这是整个计划最大的未知，先于一切协议工作。**
- **涉及文件**：`mova-libmpv/doc/notes/`（仅记结论；不改 CI）；临时脚本放 scratch，不入库。
- **做什么**：
  1. WSL 内按 `linux` job 同参数 configure n9.0.2（沿用 `--enable-decoder=...` 白名单，注意 n9 对 configure 选项的变更，逐条记录报错）。
  2. 用现有 mpv commit `78d43740f5` 编译；失败则二分到能配 n9.0.2 的最旧 mpv tag/commit，记录所有被移除的 FFmpeg API 引起的编译错误清单。
  3. 记录 mpv 版本上升带来的 `libmpv` client API/ABI 变化，对照 media_kit 1.2.6 的 FFI 绑定与 mova 的自建弱客户端（`mpv_create_weak_client`、`mpv_wait_event`，见 mova CLAUDE.md）是否仍成立（**未核实**）。
  4. 冒烟：`mpv_create`/`mpv_initialize`/`mpv_terminate_destroy` 连续 5 次 + 本地 mp4/HLS 播放。
- **验收**：产出"可用的 (ffmpeg n9.0.2, mpv commit/tag) 配对"或"不可行及原因"结论；若需升 mpv，列出 Android 四个补丁（`mpv_lavc_set_java_vm`、`hls_mp4_seek`、`dash_base_url_escape`）在新 mpv/ffmpeg 上是否仍能 apply 的结果。
- **工作量**：2–4 人天（粗估，取决于 mpv 需升多少）。
- **上报条件**：若必须升 mpv 到与 media_kit 绑定不兼容的版本，停下来报用户（涉及 media_kit/mova 依赖），不要自行升。

> **T0.2 spike 已于 2026-10-01 在 WSL 提前跑完（Linux x86_64 最小配置，ffmpeg n9.0.2 + mbedtls 3.6.7；不是 mova 真实 flavor，不含 Android/Windows，未跑 5 次冒烟，只各跑 1 次 mp4 播放）。结论如下，落地时仍需按上面 4 步在真实 flavor 上复核：**
>
> | 组合 | 结果 |
> |---|---|
> | 钉死 mpv `78d43740f5`（v0.36.0 之后第 549 个提交）+ n9.0.2，不打补丁 | 编译失败，26 条错误/9 个文件（`AVCodec.sample_fmts/pix_fmts/ch_layouts` 等、`FF_PROFILE_*`、`avcodec_close`、`AVStream.side_data`、`AV_OPT_TYPE_CHANNEL_LAYOUT` 被移除，`avio_alloc_context` 写回调类型变化） |
> | 同上 + 兼容补丁 | 编译链接通过，播放 h264+aac mp4 通过。补丁 9 个文件 +42/−29，另加约 8 行新头文件 `common/av_compat.h`；成品补丁 `pin-n9-compat.patch` 共 342 行 |
> | mpv v0.41.0（2025-12-21）+ n9.0.2，不打补丁 | 编译链接通过，播放通过。但 libplacebo 变成**强制依赖**（≥6.338.2），Linux 最小静态构建 `libplacebo.a` 3,535,090 字节；整体 libmpv strip 后 13,453,032 对 12,712,424 字节（**+740,608，约 +5.8%**，两数只能互相比较） |
>
> - 钉死 mpv 的 meson 只要求 libavcodec ≥ 58.134，并不限定 ffmpeg 6.0；v0.41.0 要求 libavcodec ≥ 60.31.102，即 ffmpeg ≥ 6.1，所以 **n6.0.1 编不过 v0.41.0**。
> - media_kit 1.2.6 / media_kit_video 2.0.1 与 mova 的 FFI 弱客户端只用 libmpv 公开 C API，共 42 个函数，在钉死 mpv 与 v0.41.0 里都能 `nm -D` 到；事件枚举逐行一致；client API 2.2→2.5 仅新增。**未验证**：真实 media_kit 端到端跑 v0.41。
> - Android 补丁：`mpv_lavc_set_java_vm` 补丁在 v0.41 上 `client.h` 带 23 行偏移能打上，`client.c` 的 hunk 打不上、需手工挪（未编译验证）；`hls_mp4_seek`、`dash_base_url_escape` 两个 ffmpeg 补丁在 n9.0.2 上已被上游修复，可删（对 n9.0.2 `git apply` 失败是因为已修，不是冲突）。
> - 兼容补丁的风险：新增的 `mp_st_sd` 使用 ffmpeg 7+ 的 side data 位置，旋转、replaygain、Dolby Vision 这类 side data 行为是否与原来一致**未验证**，要加回归项。
> - **（已被下面的"2026-10-01 修订"取代，保留作历史）** 原决定是钉死 mpv `78d43740f5` + `pin-n9-compat.patch` + n9.0.2、不升 mpv，理由是省约 740KB 与三平台同一 mpv。
>
> **2026-10-01 修订（用户要求用最新 libmpv、接受 libplacebo；实测后）**：
>
> 评估子代理在 WSL 里做了同口径对比（Linux x86_64，gcc 15，`-Os`，`--gc-sections`，version script 只导出 `mpv_*`，ffmpeg n9.0.2 与 libass/harfbuzz/freetype/fribidi/mbedtls 全静态，stripped 字节）：
>
> | 项（Linux） | 字节 | 相对钉死基线 |
> |---|---|---|
> | 钉死 78d43740f5（无 libplacebo） | 9,053,064 | 基线 |
> | v0.41.0 + 最小 libplacebo 7.360.0 | 9,986,608 | +933,544 |
> | v0.41.0 + libplacebo 开 opengl | 10,101,424 | +1,048,360 |
> | **v0.41.0 摘掉 `vo_gpu_next`** | **9,209,384** | **+156,320** |
> | master + 最小 libplacebo 7.360.1 | 10,138,256 | +1,085,192 |
> | master 摘掉 `vo_gpu_next` | 9,356,936 | +303,872 |
>
> | 项（Android arm64 API24，NDK r25c，ffmpeg 按 v6 线清单、去 dav1d，**未做 ffmpeg 整链 LTO**） | 字节 | 相对钉死基线 |
> |---|---|---|
> | 钉死基线（无 libplacebo） | 6,969,304 | 基线 |
> | v0.41.0 + libplacebo(GL) | 7,775,616 | +806,312 |
> | **v0.41.0 摘掉 `vo_gpu_next`** | **7,127,064** | **+157,760** |
> | master + libplacebo | 7,906,336 | +937,032 |
> | master 摘掉 `vo_gpu_next` | 7,255,024 | +285,720 |
>
> **结论：libplacebo 的体积税几乎全是 `vo_gpu_next`（gpu-next 视频输出）这条死代码**——它不在 libmpv render API 的后端表里（`vo_libmpv.c:114` 只有 gpu 和 sw），但在 VO 驱动表里被引用，链接器丢不掉。摘掉后 libplacebo 链接后保留段从约 313KB 降到约 7KB，整体只比钉死基线多约 156–158KB。**老 gpu 不能删**（render API 唯一的渲染后端）。
> - **Android 整链 LTO 补测结果（子代理收尾时补跑）**：钉死基线 6,615,960；v0.41.0 + libplacebo(GL) 7,392,992（+777,032）；**v0.41.0 摘掉 `vo_gpu_next` 6,768,032（+152,072）**。master 的 Android LTO 未测。结论与不开整链 LTO 时一致：摘掉后增量约 15 万字节。
> - 口径限制：上面 Android 表（非整链 LTO）的钉死基线 6.97MB、整链 LTO 的 6.62MB，都比仓库现有 v6 的 6,050,104 字节（含 dav1d、ffmpeg 组件清单与选项不同）还大约 0.57–0.92MB，差距来自 mpv 版本、freetype 模块未裁、编译选项等，**没逐项拆**；**不能直接和 6,050,104 比，只看同口径内的相对增量**；LTO 只对 mpv 本体时仅省约 26–65KB。早期几个 Linux 数字（钉死 9,053,096、B1 9,990,736）受 freetype 自动探测系统 bz2 影响，**作废**，以上表为准。Android 产物只编过、未在 x86 上冒烟；软渲染冒烟（loadfile + 渲染帧）在 Linux 上对钉死、v0.41.0 的 B1/B3、master 的 C1/C3 全部通过。
> - v0.41.0 与 master 对 ffmpeg n9.0.2 **都无需补丁即可编过**；两者 client API 都是 2.5；media_kit/mova 用到的 28 个 libmpv 函数全部仍导出。
> - 评估期间踩出的两个坑（落地时要带上）：①freetype 的 meson 会自动探测系统 bz2，造成 `BZ2_*` 未定义，需关掉；②摘 `vo_gpu_next` 后 `options.c` 仍引用 `gl_next_conf`，补丁里要一并删。mpv 编出的 .so 默认带 `--allow-shlib-undefined`，会掩盖未定义符号，校验时要去掉。
> - 其它体积旁注（只记录）：libass 栈（libass/harfbuzz/freetype/fribidi/libstdc++）约 1.55MB，mpv 硬依赖、无 meson 开关；mbedtls 约 0.55MB；freetype 全模块约 487KB 可裁。
> - **新决定：WHEP flavor 用 mpv v0.41.0（稳定 tag） + 最小静态 libplacebo（OpenGL，关 vulkan/glslang/shaderc/lcms/demos）+ 摘 `vo_gpu_next` 补丁 + ffmpeg n9.0.2。** 兼容补丁 `pin-n9-compat.patch` 作废，不再需要。master 作为后续跟进选项（比 v0.41.0 多约 128–130KB，无稳定 tag，对 libplacebo 要求 ≥ 7.360.1）。理由：用户要求最新 libmpv；体积代价实测仅约 +157KB；免去维护 342 行兼容补丁；拿到 v0.37–v0.41 的上游修复与 Android AAudio 后端（AAudio 对延迟的帮助**未验证**）。
> - 代价与待办：①要维护"摘 vo_gpu_next"补丁（动 `video/out/vo.c`、`meson.build`、`options.c`；每次升 mpv 要重做）；②`mpv_lavc_set_java_vm` 补丁要手工移植到 0.41（`client.h` 带 23 行偏移能打、`client.c` 要手工）；③Android 要 `-lc++_static -lc++abi`（libplacebo 带 C++）、mpv 需 `-Dgl=enabled -Dplain-gl=enabled -Degl-android=enabled`（旧分支真机结论，未在本次复核）；④libplacebo 作为 subproject 需要联网取依赖，CI 要缓存；⑤v0.41.0 要求 ffmpeg ≥ 6.1，**iOS/macOS 若要同步新 mpv 就必须升 ffmpeg**——本期 WHEP flavor 不含 darwin，默认 flavor（钉死 mpv）不动，所以与 Q3(b) 一致，但会出现"WHEP flavor 与默认 flavor 的 mpv 版本不同"的并存期，回归清单要覆盖。
> - Android 整链 LTO 的最终数字、master/B3/C3 在 Android 上的冒烟、真机播放：**未做**，列入 T0.4–T0.6。
> - 补丁与证据位置：WSL `/root/w/mpvt/eval/`（`out-*.stripped.so`、`andout-*.stripped.so`、`runall.out`、`conf-*.log`）；scratchpad `libplacebo-eval/`（`b3-v041.patch`、`c3-head.patch`、`javavm-v041.patch`、`javavm-head.patch`、构建脚本）。落地时把需要的补丁放进 `mova-libmpv/patches/` 并登记。
> - Q9 不触发（media_kit 公开符号在新版里都在，无需 fork）。
> - **旁证（旧分支 `mova-libmpv-winbuild-zhangfly`，与 main 无共同历史，最后提交 2026-08-11，其 README/脚本自述，我未复跑）**：该分支走过「ffmpeg n9.0 + mpv v0.41.0 + libplacebo」的 v9 线，Android arm64 stripped `libmpv.so` 9.30MB（已做过 h264/hevc/av1 软解砍除，仍然）对比 v6 定稿 5.87MiB，自述"libplacebo 是约 1.6 倍的固定体积税"；Windows 13.60→11.91MB，iOS 10.15MiB；它查证 mpv 0.41.0 的 libplacebo 无法关闭（没有 `-Dlibplacebo` 选项）。Huawei 真机上启动、播放、资源占用与 v6 持平。**这与本次"不升 mpv、体积优先"的决定一致，且说明在 Android 真实 flavor 上体积差可能远大于 Linux 最小配置测得的 +740KB**。它记录的三个 v0.41 上的真机坑（`mpv_lavc_set_java_vm` 缺失、libplacebo/glslang 的 C++ 运行时 `__gxx_personality_v0`、`hwdec_aimagereader` 要求 `ra_is_gl`）只在升 v0.41 的备选路线才会遇到。
> - 该分支另一点与本次 spike 不一致：它称 mpv 0.41.0 需要 ffmpeg n9.0 才有的 `avcodec_get_supported_config()`、旧 ffmpeg 头文件编不过；本次读到 v0.41.0 的 `meson.build` 只要求 libavcodec ≥ 60.31.102（ffmpeg ≥ 6.1）。两者谁对**未核实**，不影响本决定（不升 mpv）。
> - 补丁与证据位置：WSL `/root/w/mpvt/`（`pin-n9-compat.patch`、`src-pin/`、`src-v041/`、各构建目录和日志）；Windows 侧副本在 scratchpad `out/`。落地时把 `pin-n9-compat.patch` 放进 `mova-libmpv/patches/`，登记来源与 ffmpeg 版本。

#### T0.3 WHEP 可行性小验证（NOFILE 探测 + SDP 复用 + SRTP 接收 + 平台 DTLS 探测）

- **目标**：核实 §1.4 的 1、2、4、5 项，定 A3（demuxer/protocol）与 A6（SDP 复用方式）。
- **涉及文件**：`mova-libmpv/doc/notes/2026-10-xx-whep-feasibility.md`（结论笔记）；spike 代码不入库。
- **做什么**：
  1. 在 n9.0.2 上写一个最小 `whep` demuxer 桩（`AVFMT_NOFILE`，`read_probe` 认 `whep:` 前缀，`read_header` 里 `avformat_new_stream` 两条流、塞假 extradata），用 mpv 打开 `whep://x`，观察 mpv 是否调用到 `read_header`、是否被 lavf protocol whitelist 拦截、是否绕过 mpv stream 层。
  2. 试用 `ff_sdp_parse` 在无 `RTSPState` 的上下文里解析一段 WHEP answer SDP，看耦合点（需要哪些 `RTSPState`/`RTSPStream` 字段），评估"抽最小子集"的行数。
  2b. （2026-10-02 源码核实）mpv v0.41.0 `stream_lavf.c:376-387` 对 `rtsp:`/`rtsps:` 前缀特判、直接指定 demuxer 为 lavf（注释称 ffmpeg 无 rtsp 的 protocol 条目），`demux_lavf.c:1023` 在 `AVFMT_NOFILE` 时不建自有 AVIO。故 demuxer 路线很可能需要对 `whep:` 照 rtsp 加同样特判——这是一个 **mpv 补丁**（与 T1.x 里"mpv 本体不改"的表述冲突，T0.3 须验证后修正；补丁体量极小，不影响体积）。`ff_srtp_decrypt` 实际在 `srtp.c:127`。
  3. 用 `ff_srtp_decrypt` 解一个 RTP 包（对 `whip.c` 同款密钥材料）确认签名与语义（RTP 路径，非 RTCP）。
  4. Windows（MSYS2 mingw）下 `check_cc dtls_protocol ... SECPKG_ATTR_DTLS_MTU` 能否通过；Android NDK 自建 mbedtls 开 `MBEDTLS_SSL_DTLS_SRTP` 后 `ff_dtls_export_materials` 能否链接。
- **验收**：四项各有"通过/不通过 + 证据（日志片段/编译输出）"。任一项不通过，在"风险表"升级并给替代路径（如 NOFILE 不行→改 protocol+自定义 `rtp` 输入）。
- **工作量**：2–3 人天（粗估）。

#### T0.4 Linux job 升级 n9.0.2 + 全量回归

- **目标**：Linux 产物在 n9.0.2（+ T0.2 定的 mpv）上与 n6.0.1 功能等价、体积差异已归因。
- **涉及文件**：`.github/workflows/build-mova-libmpv.yml`（`linux` job，ffmpeg/mpv ref 参数化为 `FFMPEG_REF`/`MPV_REF` 变量，便于回滚）；`mova-libmpv/tools/regress/`。
- **做什么**：改 ref；按 T0.2 记录处理 configure/API 变更；跑 T0.1 脚本；跑 §7 回归清单里 Linux 条目。
- **验收**：CI `linux` job 绿；T0.1 脚本全绿；体积变化量（字节）与 n6.0.1 对比写入 commit message；`License: LGPL version 2.1` grep 仍通过；`mpv_create` 冒烟 5/5。
- **工作量**：1–2 人天。

#### T0.5 Windows job 升级 + 回归

- **目标**：Windows（SChannel、clang 编译 mpv、D3D11VA）在 n9.0.2 上不退化。
- **涉及文件**：workflow `windows` job；`mova/example` 的验证**只读使用**（不改 mova 文件；`dist/windows-x86_64/libmpv-2.dll` 回填由 CI 完成）。
- **做什么**：同 T0.4；额外确认 D3D11VA 硬解启用（`--enable-d3d11va`）、`libmpv.dll.a` 需要重新生成（见 mova CLAUDE.md：dll 换版本要重新生成）。
- **验收**：CI 绿；`mpv_create` 冒烟（用已有 C 冒烟测试方法）5/5；`flutter run -d windows` 实机画面+声音正常（沿用 2026-09-24 同款验证）；体积变化已归因。
- **工作量**：1.5–3 人天。

#### T0.6 Android 构建链升级 + 回归（四 ABI）

- **目标**：Android 四 ABI 在 n9.0.2 上可构建、硬解/软解/字幕不退化。
- **涉及文件**：`mova-libmpv/flavors-mova-slim.sh`、`mova-libmpv/libmpv-android-video-build.patch`、workflow `android-arm64`/`android-other-abi`（含 `LIBMPV_BUILD_REF` 与 ffmpeg 下载脚本）。
- **做什么**：`libmpv-android-video-build @1ecf510` 把 ffmpeg 固定在 n6.0（`download-deps.sh`）——需改其 ffmpeg ref 并保证 `patches/ffmpeg/*.patch` 仍能 apply；`flavors-mova-slim.sh` 逐条对照 n9 configure 选项；mbedtls 版本是否随之变动（**未核实**，nativewaves/whip 用 3.6.7 测过）。
- **验收**：四 ABI CI 绿；T0.1 的 Android 符号脚本全绿（`mpv_lavc_set_java_vm`、4 个 mediacodec 硬解符号、`dav1d_*` ≥ 19 个符号、VP8/MJPEG 消失）；真机 STG-AL00 回归见 §7。
- **工作量**：3–5 人天（粗估；含 patch rebase）。

#### T0.7 darwin/iOS 去留决策与编译验证

- **目标**：明确 iOS/macOS 是否同步升 n9.0.2，并保证不被 D2 误伤。
- **涉及文件**：`libmpv-darwin-build-mova-slim.patch`、workflow `darwin`/`ios`（本计划**不改**，除非 Q4 拍板同步升级）。
- **做什么**：确认 `media-kit/libmpv-darwin-build` 的 ffmpeg 版本钉在哪（**未核实**）；按 Q4 推荐"本期保持不动，WHEP flavor 不含 darwin"。
- **验收**：执行记录写明"iOS/macOS 保持现状/同步升级"及依据；若保持现状，CI 的 darwin/ios job 在本分支合并后仍绿。
- **工作量**：0.5 人天（决策+确认）；若 Q4 选同步升，另估 3–5 人天且**无 Mac 无法真机验证**（未核实可行性）。

### 阶段 L：许可与合规（贯穿，先于第一个拷贝 commit）

#### T-L1 许可与合规 Task（独立）

- **目标**：把"拷了什么、从哪来、什么许可、怎么分发"落成可审计文件，并请有资质的人复核。**本节不是法律意见。**
- **2026-10-02 原文核实（读的是 libjuice 仓库内的标准 MPL-2.0 文本与 FAQ 转写，非 mozilla.org 页面本身）**：
  - §1.12 次级许可证 = GPL 2.0 / LGPL 2.1 / AGPL 3.0 "或这些许可证的任何更高版本"；原文**未逐字写 LGPL 3.0**，"LGPLv3 算 2.1 的后续版本"是推断，**需复核**。
  - §3.3：是**额外**在次级许可证下分发（接收方自选 MPL 或次级许可证），不是整体改许可证；FAQ Q14 三条件：非 "Incompatible With Secondary Licenses"、是组合作品、额外在 (L)GPL 下分发。
  - §3.1/3.2/3.4：告知源码受 MPL 约束与获取许可证方式；可执行形式须告知如何获取源码（费用不超分发成本）；不得去除许可声明。
  - libjuice `stun.c`、libdatachannel `rtp.cpp` 头均为标准 MPL-2.0 头，无 Exhibit B；libdatachannel 0.18 起才是 MPL-2.0（此前 LGPLv2.1+），须钉具体 tag。
  - **体积优先的结论**：维持 Q1=(b)——不拷 libjuice（连带 8–10 个文件，且 ffmpeg 已有 HMAC/CRC，`whip.c` 自带 STUN），仅移植 NACK 逻辑；移植件按 Modifications 处理并登记 PROVENANCE（"独立重写不继承 MPL"仅有 FAQ Q11 字面推断，不依赖）。
  - **仍未核实**：§3.5/§5.3 完整原文；FAQ 静态链接/改写条目；LGPLv3 §4 对 Windows dll、Android APK 内 so"可替换"的具体要求。
- **2026-10-02 LGPL 初筛（条文取自 SPDX 镜像 + WebFetch 摘要，非 gnu.org 原站，定稿前须对原文再核）**：
  - LGPLv3 §4d：二选一——(0) 交付 Minimal Corresponding Source 并以可重新链接形式交付 Application 代码；(1) 用"合适的共享库机制"（须运行时使用用户系统上**已有**的库副本，且能配合接口兼容的修改版运行）。LGPLv2.1 §6a/§6b 同构。
  - **私有随包分发的 libmpv + 静态链进去的 ffmpeg 不满足 §4d(1)**，保守按 §4d(0)/§6a 准备"可重新链接"材料（完整构建配方 + ffmpeg/mpv 源码 + 补丁），别指望共享库机制；"FFI 加载算不算共享库机制"条文未提及，agy 的"算"是推断，不采信。
  - FFmpeg legal 页：不带 `--enable-gpl/--enable-nonfree`；源码与二进制精确对应、附 configure 说明、改动用 `git diff` 留存；官方建议动态链接（静态链接偏离建议路径，交法务）；about/EULA/下载页声明要求。
  - mpv：`-Dgpl=false` **本身不构成 LGPLv2.1+ 授权**，只是排除 GPL-only 文件，LGPL 口径需逐文件核对（交法务）；mpv 说明预期用途就是配合 libmpv。
  - Apache-2.0 §4（mbedtls）：附许可证副本、保留声明、NOTICE 随包提供；Apache-2.0 与 LGPLv3/v2.1 兼容性、mbedtls 双许可的选择**未读到原文**，agy 的"可能传染"推测不采信。
  - Windows dll 替换、Android APK 重签名/sideload 的可行性：条文未提及，**未读到**，交法务。
- **涉及文件**：
  - `mova-libmpv/third_party/LICENSES/MPL-2.0.txt`（MPL 全文）
  - `mova-libmpv/third_party/PROVENANCE.md`（每个拷贝/移植文件一行：目标路径、来源仓库、**tag + commit**、来源路径、许可、是否修改、修改摘要）
  - `mova-libmpv/third_party/README.md`（源码获取说明：MPL 文件的源码在本仓库哪个路径、对应上游 tag，以及按 LGPL 提供 ffmpeg/mova-libmpv 补丁源码的方式）
  - `mova-libmpv/patches/ffmpeg-whep/` 下每个含 MPL 来源的文件**保留原文件头不得删改**（MPL §3.4）
  - 若产物随包分发：`mova/` 侧的 NOTICE 文件更新属 mova 侧发布工作，不在本计划内，**本 Task 只列清单不改 mova**
- **做什么**：
  1. 建 PROVENANCE 模板；每次拷贝/移植一个文件，**同一个 commit** 里登记。
  2. 全量核对拟拷贝范围内每个文件的头：只允许 libdatachannel、libjuice；MPL 标准声明、无 Exhibit B（"Incompatible With Secondary Licenses"）。规划阶段已抽样核实 5 个文件，**全量核对未做**。
  3. 对**无 MPL 头**的文件单独核来源：`include/rtc/version.h`（无许可头，若拷需查 libdatachannel LICENSE 与其 README 的归属声明）、`deps/libjuice/src/picohash.h`（头为 Kazuho Oku public domain 声明，应保留并登记，**不是 MPL**）。
  4. 登记分发义务：MPL 文件同时以 MPL（源码）与 LGPL（作为 Larger Work 的一部分）提供；修改内容公开；mbedtls 3.x → 需 `--enable-version3` → Android 产物 LGPLv3（本来就是）；Linux/Windows 新增 WHEP flavor 若引入 MPL 文件，需核对其与现有"LGPLv2.1"口径（Linux 当前 grep `License: LGPL version 2.1`）是否冲突（**未核实**：MPL §1.12 把 LGPL 2.1+ 列为 Secondary License，但 ffmpeg 的 configure 许可探测不认识 MPL，CI grep 口径需调整，见下）。
  5. 更新 CI 的许可 grep：`WHEP` flavor 下允许出现的许可字样与默认 flavor 分开断言（默认 flavor 断言不变）。
  6. 请有资质的人（法务/开源合规负责人）复核 PROVENANCE 与分发方式，复核结论记入执行记录。
- **验收**：PROVENANCE 与实际入库的拷贝文件一一对应（CI 加一个脚本：对 `third_party/` 与补丁里含 "Mozilla Public License" 的文件做并集比对，缺登记即失败）；MPL 全文入库；法务复核有记录（含复核人/日期）。
- **工作量**：1.5 人天 + 外部复核等待（不计入）。

### 阶段 1：Linux（WSL）打通 WHEP

#### T1.1 WHEP flavor 骨架与补丁目录

- **目标**：建立"可选 flavor、默认关闭"的工程骨架。
- **涉及文件**：`mova-libmpv/flavors-mova-slim-whep.sh`（在 `flavors-mova-slim.sh` 基础上追加 `--enable-demuxer=whep` 与所需 `--enable-protocol=udp,...`；注意 `dtls_protocol` 需要 `udp_protocol`）、`mova-libmpv/patches/ffmpeg-whep/0001-*.patch`（`libavformat/whep.c`、`Makefile`、`allformats.c`、`configure` 的 `whep_demuxer_deps/select`）、workflow（新增 `linux-whep` job，T1.8）。
- **做什么**：新建 `whep_demuxer_deps="dtls_protocol rtp_demuxer sdp_demuxer"` 一类依赖（具体名以 n9.0.2 实际 configure 为准）；`whep.c` 先放能编译的空壳。
- **验收**：默认 flavor 的 configure 输出与 T0.4 逐行 diff 为零（证明默认关闭不污染）；`--enable-demuxer=whep` 能 configure+编译。
- **工作量**：1.5 人天。

#### T1.2 信令与 SDP（offer/answer）

- **目标**：向 WHEP 端点 POST SDP offer（recvonly，H264+Opus），解析 answer。
- **涉及文件**：`patches/ffmpeg-whep/0002-*.patch`（`whep.c`）。
- **做什么**：参考 `whip.c` 的 `exchange_sdp`（`:772`）、`parse_answer`（`:894`）；offer 里 `a=recvonly`、payload type 不写死而是按 answer 协商；Bearer token 通过选项传入；A6 视 T0.3 结果复用 `ff_sdp_parse` 或抽最小子集生成 `AVStream`。
- **验收**：对 MediaMTX 与 SRS（Q5）各一次，日志可见 offer/answer 完整往返；解析出的 ice-ufrag/pwd/fingerprint/candidate/payload type 与服务器日志一致（真实日志，非猜测）。
- **工作量**：2–3 人天。

#### T1.3 ICE + DTLS + SRTP 接收通路

- **目标**：连通性检查通过、DTLS 握手完成、导出 SRTP 密钥、能解密收到的 RTP。
- **涉及文件**：`patches/ffmpeg-whep/0003-*.patch`；**[待 Q1]** 若需拷 libjuice `stun.c` 则同批入 `third_party/` 并在 T-L1 登记。
- **做什么**：复用 `whip.c` 的 `ice_*`/`udp_connect`/`ice_dtls_handshake`/`setup_srtp`（`:1024-1493`，master 行号）；接收方向用 `srtp_recv` 解 RTP（`ff_srtp_decrypt`，A7 自补重放窗口）；保活/consent freshness 的 STUN binding 周期发送（`whip.c` 是否已有：未核实）。
- **验收**：对 MediaMTX 抓包（`tcpdump`/Wireshark）可见 ICE binding 成功、DTLS Finished、SRTP 包；用 `ffmpeg -loglevel debug` 或自加计数器输出"解密成功包数/失败包数"，失败为 0。
- **工作量**：3–4 人天。

#### T1.4 RTP → AVPacket（复用 rtpdec）

- **目标**：把解密后的 RTP 喂给 `RTPDemuxContext`，输出 H264/Opus 的 `AVPacket`，时间戳正确。
- **涉及文件**：`patches/ffmpeg-whep/0004-*.patch`。
- **做什么**：为每条流建 `RTPDemuxContext`（`ff_rtp_parse_open`，`queue_size` 取小值以保低延迟，`rtpdec.c:538-553`）；SR→NTP 对齐音视频；H264 的 `sprop`/extradata 从 answer 或首个 IDR 获取（需处理无 extradata 起播）。
- **验收**：`ffplay`/mpv 能起播并看到画面+听到声音；`mpv --vo=null --ao=null` 下 `MovaProg` 等价事件（mpv `time-pos`）单调推进；首帧时间（open 到首个 `playback-restart`）记 5 次取平均写入笔记。
- **工作量**：3–5 人天。

#### T1.5 RTCP 反馈：RR / NACK / PLI

- **目标**：丢包时发 NACK 并收到重传（RTX，PT=105 类，按 answer 协商）、丢关键帧时发 PLI、周期发 RR。
- **涉及文件**：`patches/ffmpeg-whep/0005-*.patch`；**[待 Q1]** NACK 多 FCI 打包按 libdatachannel `RtcpNack::addMissingPacket`（`rtp.cpp:712`）移植，登记 T-L1。
- **做什么**：
  1. 复用 `find_missing_packets` + `ff_rtp_send_rtcp_feedback`（`rtpdec.c:469`）的基础版；扩展为多 FCI；
  2. 所有 RTCP 经 `srtp_rtcp_send`（SRTCP）加密发出（`ff_rtp_send_rtcp_feedback` 本身写明文到 `fd/avio`，需包一层）；
  3. RTX 包（`whip.c:handle_rtx_packet` 是发送侧；接收侧需把 RTX 还原到原序号再喂 `rtpdec`）；
  4. 节流：`MIN_FEEDBACK_INTERVAL`（`rtpdec.c`，值未核实）；
  5. 本地 SSRC 不再用 `s->ssrc+1`（WebRTC 要与 SDP 里声明的 SSRC 一致，`rtpdec.c:469` 的做法适用于 RTSP，**不适用于 WebRTC**，需改）。
- **2026-10-02 设计复核（agy 草案 + 复核，详见本节；阈值均为自行设计的起点，须 T1.7 netem 校准）**：
  - 多 FCI 打包可直接移植为约 15 行 C：升序取 PID，后续与 PID 差 1–16 的序号置 BLP 位 `1<<(d-1)`，超出另开 FCI，RTCP length = `2 + fci_count`；Python 复刻对 2 万组随机丢包（含回绕）打包再展开一致。
  - 检测须自写：`find_missing_packets` 只扫 `s->seq+1` 之后 16 个序号（丢包 >17 个窗口外发现不了），且 `s->seq==0` 初始状态要特判；`MIN_FEEDBACK_INTERVAL`=200ms（`rtpdec.c:38`）会让 50ms 重传间隔失效，须改；缺口表要有"首次发现时间"字段。
  - `enqueue_packet` **不会**滤重复包（同序号会入队，`diff==0` 还会被当正常包解析）：重传/RTX 回来的包须自己去重。
  - 必须做 RTX（RFC 4588）还原 OSN；PLI 要限速（建议 ≥1s）；需要按时间放弃缺口的机制。
  - 测试用例清单：丢 1 包、连续丢 17/18 包（18 包应得 `(2,0xFFFF)+(19,0)`）、回绕处丢包、乱序不触发 NACK、重复包丢弃、重传后缺口清除、丢包 >32 触发 PLI、重试 3 次触发 PLI、PLI 限速、RTX 还原。
- **验收**：T1.7 测试台上 `tc netem loss 5%`（及 1%/10%）下：①`whep.c` 计数器"NACK 发出数 / 重传包到达数 / 最终仍丢包数"（真实计数，非推算）；②对比"关闭 NACK"同条件下的花屏/卡顿帧数；③PLI：人为丢 IDR 后 PLI 发出并在 N 秒内恢复，N 以实测为准。
- **工作量**：4–6 人天。

#### T1.6 mpv 集成与开放可调参数

- **目标**：mpv 能用标准 scheme（`whep://`、`whep+http(s)://`，以 T0.3 定的为准）直接开流；把影响延迟与稳定性的参数**开放出来**并写清用法，**不替业务定默认策略**。
- **涉及文件**：`patches/ffmpeg-whep/0006-*.patch`（`read_probe` 前缀）；`whep.c` 的 `AVOption`（如 nack 开关、重排序队列大小、ICE/握手超时，**具体项由 T1.3–T1.5 实现时确定**）；`mova-libmpv/doc/notes/` 参数说明笔记；（mpv 本体：**T0.3 已证明必须加一个约 17 行补丁**——`stream/stream_lavf.c` 的 `get_safe_protocols()` 注册 `whep` 并在 `open_f()` 对 `whep:` 照 `rtsp:` 特判，见 `doc/notes/2026-10-02-t03-whep-feasibility.md`；`whep.c` 还须声明 `tls_verify`/`timeout` 等 AVOption）。
- **做什么**：scheme 只认标准写法（SRS 私有 `webrtc://` 等业务适配**不进 C 补丁**，由使用方转换）；把参数经 mpv 的 `--demuxer-lavf-o=` 传给 demuxer 的方式验证通；实测 `--profile=low-latency`、`--cache=no`、`--demuxer-readahead-secs`、`--audio-buffer`、`--untimed`（**这些选项名未逐一核对，以 mpv 对应版本 `--list-options` 为准**）对端到端延迟的影响，**只记录数据，供使用方选值**。
- **验收**：给出"延迟-稳定性"数据表：同一推流源、`netem` 抖动 0/50/100ms 下的首帧时间、稳态端到端延迟（测量法见 T1.7）、卡顿次数（mpv `paused-for-cache` 真实计数）；产出"参数→效果"说明，列出每个开放参数的名字、取值范围、默认值。
- **工作量**：2–3 人天。

#### T1.7 测试台与测量方法（先于 T1.5/T1.6 的验收）

- **目标**：可复现的服务器+网络损伤+延迟测量环境。
- **涉及文件**：`mova-libmpv/tools/whep-lab/`（`docker-compose.yml`：MediaMTX 与 SRS 各一；`netem.sh`；`push.sh`；`measure.md`）。
- **做什么**：
  1. WSL 起 MediaMTX、SRS（镜像/版本在 compose 里固定，记入笔记）；用 ffmpeg n9.0.2 的 whip muxer（已核实存在）或服务器自带推流源推 H264+Opus。
  2. `tc qdisc add dev <if> root netem loss X% delay Yms Zms`；脚本化、可回滚；WSL 里 `tc` 权限与内核模块可用性**未核实**（先验证，否则改用 docker 网桥接口或 toxiproxy 类 UDP 工具需另议）。
  3. 端到端延迟测量法：推流端烧入当前时间（`drawtext` 毫秒时钟）；接收端用 `--vo=image` 落盘帧，以帧文件系统时间与烧入时钟差计算（同机单时钟避免 NTP 误差；读数用 OCR 或 QR，具体读数方式**待实测选定，候选 tesseract/二维码**，未核实可用性）。
  4. 禁止墙钟 + sleep 当判据；计数全部取自 `whep.c` 日志计数器与 mpv 属性事件。
- **验收**：`measure.md` 写明方法、误差来源、防缓存措施；空载下重复 5 次测量，方差已记录。
- **工作量**：2–3 人天。

#### T1.8 CI：`linux-whep` job

- **目标**：Linux WHEP flavor 可在 CI 复现。
- **涉及文件**：workflow（新 job，`if: true`，产物落 `dist/linux-x86_64-whep/`，**不覆盖默认 `dist/linux-x86_64/`**）。
- **做什么**：复用 `linux` job，改 flavor、打补丁；沿用现有"提交产物回 dist/"重试逻辑（含 `git lfs push`，注意 README 记录的 codeup 双 push-url 坑）。
- **验收**：CI 绿；产物体积相对同 n9.0.2 默认 flavor 的增量（字节）写入 `$GITHUB_STEP_SUMMARY` 并与 §4 预算对照；默认 flavor 产物字节数不变。
- **工作量**：1 人天。

### 阶段 2：Windows（SChannel）

#### T2.1 SChannel DTLS-SRTP 构建

- **目标**：MSYS2 MINGW64 下 `dtls_protocol` 成功启用，WHEP flavor 可编译链接。
- **涉及文件**：workflow `windows` job 的 whep 变体、`flavors-mova-slim-whep.sh`（Windows 分支）。
- **做什么**：处理 R6（`SECPKG_ATTR_DTLS_MTU` 在 mingw-w64 头里缺失时的补丁/宏定义方案）；mpv 一步仍用 clang；`libmpv.dll.a` 重生成。
- **验收**：configure 输出 `dtls_protocol` 为 yes；产物 `nm`/`dumpbin /exports` 公开 API 符号齐全；`License` 输出与 T-L1 断言一致。
- **工作量**：2–4 人天（粗估，取决于 R6）。

#### T2.2 Windows 真机 WHEP 验证

- **目标**：Windows 桌面实机能拉 WHEP 流并通过 netem 等价手段验证 NACK。
- **涉及文件**：`mova-libmpv/tools/whep-lab/`（Windows 侧推流/网络损伤脚本）；mova 只**只读**使用，不改。
- **做什么**：Windows 无 `tc`，用 WSL 侧服务器 + Windows 侧 `clumsy` 一类工具或 WSL 内损伤（**工具可用性未核实**）；用 mova example 或裸 mpv 命令行（优先后者，不动 mova）。
- **验收**：同 T1.5 的计数器口径；经 mova 的 `flutter run -d windows` 路径属 mova 侧验证，不在本计划内。
- **工作量**：2–3 人天。

#### T2.3 Windows 产物接入与回归

- **目标**：WHEP flavor 产物通过现有 `media_kit_libs_windows_video_slim` 路径接入，默认 flavor 不受影响。
- **涉及文件**：`mova-libmpv/dist/windows-x86_64-whep/`（产物目录）；`mova/packages/media_kit_libs_windows_video_slim` 的接线**属 mova 侧，不在本计划内**，本 Task 只交付产物并写一段接线说明。
- **验收**：默认 flavor 回归（§7 Windows 条目）全绿；WHEP flavor 单独目录，开关明确。
- **工作量**：1 人天。

### 阶段 3：Android（mbedtls + DTLS-SRTP）

#### T3.1 自建 mbedtls 开启 DTLS-SRTP

- **目标**：Android mbedtls 带 `MBEDTLS_SSL_DTLS_SRTP`，`ff_dtls_export_materials` 可用。
- **涉及文件**：`libmpv-android-video-build.patch` 中 `scripts/mbedtls.sh` 的 config 改动（mbedtls 默认关闭该宏，需在 `config.h`/`scripts/config.py -s` 里置开，**具体机制未核实**）；四个 ABI。
- **验收**：产物里 `llvm-nm` 能查到 `mbedtls_ssl_conf_dtls_srtp_protection_profiles`；体积增量（mbedtls 开宏部分）单独记录；`tls_mbedtls.c` 不再打印 "DTLS-SRTP is not supported"。
- **工作量**：2–3 人天。

#### T3.2 Android WHEP flavor 构建（四 ABI）

- **目标**：四 ABI 的 WHEP flavor 产物。
- **涉及文件**：`flavors-mova-slim-whep.sh`（Android 分支）、workflow `android-*` 的 whep 变体；产物落 `dist/<abi>-whep/`。
- **验收**：四 ABI CI 绿；`mpv_lavc_set_java_vm` 与 mediacodec 硬解符号仍在；体积增量 ≤ §4 红线；LGPLv3 口径不变。
- **工作量**：2–3 人天。

#### T3.3 Android 真机验证（STG-AL00）

- **目标**：真机拉 WHEP、NACK 生效、硬解正常。
- **涉及文件**：`mova-libmpv/tools/whep-lab/`；不动 mova（用 `adb` + 裸 libmpv 探针放 scratch）。
- **做什么**：遵循 mova CLAUDE.md：先设计基于真实事件的测量（`MovaProg`/`renderEpoch` 等价事件、`paused-for-cache` 计数）；**实验前确认亮屏已解锁**（`dumpsys window | grep isKeyguardShowing`，锁屏时结果作废）；弱网用服务器侧损伤（手机侧无 root 的 netem 未核实）。
- **验收**：H.264 硬解路径起播（logcat 确认 `OMX` 硬解）；5 次首帧时间；NACK 计数；Opus 音频有声（该设备无可用音频采集路径：**只能用 mpv 日志/事件证明有音频解码输出，不能证明"听到"**，如实记录）。
- **工作量**：3–4 人天。

### 移出本计划的 mova 侧工作（另立项，仅留线索）

mova-libmpv 只做 libmpv 编译与瘦身，下列事项属 mova 业务层，**不在本计划内**，待 libmpv 产物稳定后在 `mova/` 另拆计划：

- URL 映射：把 SRS 私有 `webrtc://` 等转换为本计划支持的标准 scheme（推荐放 mova Dart 层，libmpv 只认标准 scheme）。
- 低延迟参数落点：本计划只开放参数（见 T1.6），如何包装进 `MovaLiveConfig` 由 mova 侧决定。
- 直播 UI 降级：我只读过 `mova/lib/src/ui/components/bottom_bar.dart`，现有直播底栏自适应对"不可拖动直播"是否够用**未实机验证**。

> **iOS/macOS（待定，本期不做）**：`tls_securetransport.c` 无 DTLS；没有 Mac 无法验证。可选方向（**均未核实**）：自带 mbedtls/openssl 的静态 DTLS 后端（会引入新依赖，且与 iOS 现行"用系统 securetransport 省体积"的取舍冲突）、Network.framework DTLS（接口与 ffmpeg tls 抽象差距未评估）。需用户在 Mac 到位后再立项。

**Task 总数：22**（阶段 0：7；L：1；阶段 1：8；阶段 2：3；阶段 3：3；原阶段 4 的 3 个 Task 已移出）。

## 7. 阶段 0 回归清单（逐条取自 mova-libmpv README，未编造）

### 7.1 构建期（可自动化，T0.1 脚本化）

| 平台 | 项 | 来源 |
|---|---|---|
| Android | `llvm-nm -D --defined-only libmpv.so \| grep mpv_lavc_set_java_vm` 必须有输出（只有 `av_jni_set_java_vm` 不够） | README"自建时最容易踩的坑" |
| Android | `h264/hevc/vp9/av1_mediacodec_decoder` 四个硬解符号在；`dav1d_*` 符号存在（定稿记录 19 个）；VP8/MJPEG 相关符号消失 | README"验证过关的" |
| Android | **`--enable-libdav1d` 与 `--enable-decoder=libdav1d` 必须同时在**（只写 decoder 会被静默丢弃） | README 踩坑记录 |
| Android | 四 ABI 均产出 `libmpv.so`（x86 曾因共享缓存污染产出静态库，需 `rm -rf deps/mpv/_build-<suffix>`） | README 多平台进度表 |
| Android | 产物体积对 T0.1 基线（6,050,104 为 arm64 当前 CI 值）；APK 内 `.so` sha256 与 `libmpv/<abi>/` 逐字节一致 | README / CLAUDE.md |
| Linux | `License: LGPL version 2.1`；`https/tls/rtmps` 协议在 configure 输出里；`nm -D` 公开 API（`mpv_create/initialize/command/set_option_string/render_context_create/terminate_destroy`）；`dav1d_open` defined 或 `libdav1d` NEEDED | workflow `linux` job |
| Windows | `mpv_create/mpv_initialize/mpv_terminate_destroy` 冒烟连续 5 次零崩溃；mpv 那一步用 clang；dav1d 符号；产物无外部 DLL 依赖（自包含） | README §13、Windows 计划 §7 |
| Windows | `libmpv.dll.a` 针对新 dll 导出表重生成（`gendef`+`dlltool`） | mova CLAUDE.md |
| iOS/macOS | 若 Q4 选同步升：`otool -L` 无外部依赖；公开 API；产物体积 | README iOS 节 |

### 7.2 真机/桌面实测（人工，沿用既有口径）

| 项 | 来源/口径 |
|---|---|
| H.264 点播起播；HEVC 硬解（`OMX-VDEC-1080P`）；VP9 硬解（`OMX.qcom.video.decoder.vp9`）；AV1 硬解失败后 libdav1d 软解兜底 | STG-AL00 Android 12，README"真机测试" |
| 字幕四种格式：SRT/ASS/WebVTT 外挂（`sub-add`）+ mov_text 内封，`sub-text` 轮询命中时间窗 | README，2026-09-28 |
| avfilter 回归：OSD/字幕合成无退化（FILTERS 为空） | README |
| AV1 软解高码率长视频（Windows 桌面：1080p/10.38Mbps/90s，`buffering=true` 次数 0，RSS 稳定） | README，2026-09-28 |
| Windows：`flutter run -d windows` 画面+声音，WASAPI 打开，无崩溃 | README，2026-09-24 |
| mova 验证脚本（`mova/example/lib/`）：`main_qoe_verify.dart`、`main_observe_event_verify2.dart`（FFI 弱客户端：RESTART/END_FILE，**mpv 升版后最容易受影响**）、`main_videocontroller_verify.dart`（抽帧 E5/E11/E12）、无缝切换相关 probe | mova CLAUDE.md；只读运行，不改 |
| **README 标注"未测"的项不得假装已测**：截图（png 编码器）、HLS/FLV 直播起播、后台中断恢复——升级前后均无基线，T0.1 起建议顺带补测并记录，否则升级后无法判断退化 | README"真机测试" |
| mova `flutter test` 基线 **1008 项**（升级不应改变；此测试不加载 libmpv，故不能作为 libmpv 升级的回归依据） | mova CLAUDE.md |

## 8. 风险与待决问题表（每条给推荐）

### 8.1 风险

| # | 风险 | 影响 | 缓解 / 推荐 |
|---|---|---|---|
| **R1** | **n9.0.2 与固定的 mpv `78d43740f5` 大概率不兼容**：workflow 注释已写明该 mpv 对应 libavcodec 60.x（n6.0.x）；n7/n8/n9 移除了大量弃用 API（具体清单未核实）；mpv 升级会牵动 media_kit 1.2.6 的 FFI 绑定、mova 自建弱客户端、Android 三个 mpv/ffmpeg 补丁 | 可能把"升 ffmpeg"变成"升 ffmpeg + mpv + 补丁 rebase"，工作量与风险翻倍 | T0.2 先做、先证；`*-whep` flavor 先用新配对，默认 flavor 保持 n6.0.1 直到回归全绿（A10/Q3）；mpv 版本越过 media_kit 兼容范围时上报用户 |
| R2 | 无 WHEP demuxer，且 `ff_rtp_demuxer` 是 NOFILE——mpv 如何取流未核实 | demuxer 路线可能走不通 | T0.3 验证；plan B：protocol 方案或让 mpv 走 `lavf` 的 `-f whep` 强制格式 |
| R3 | **iOS/macOS 无 DTLS 后端** | 移动端覆盖一半缺失 | 本期单列待定；Android 先行；不要为此在 iOS 引入新 TLS 库（体积与许可冲击大） |
| R4 | Android mbedtls `use_srtp` 完整性未核实；只协商 AES128_CM_SHA1_80（无 GCM） | 某些服务器强制 GCM 时无法握手 | T0.3/T3.1 验证；**2026-10-02 读源码确认** SRS（只设 SHA1_80，`srs_app_rtc_dtls.cpp:159`）、mediasoup、Janus、pion/dtls 支持集均含 SHA1_80，故 profile 本身风险低；MediaMTX/LiveKit 由 Pion 推断、Cloudflare 闭源未查到——**未核实**，须实测；mbedtls 无 GCM 的事实不变。rtcp-fb（只带 nack/nack pli，无 transport-cc/REMB）是否被各服务端接受**未查到原文**，须实测。注：WHEP 仍是 draft-ietf-wish-whep（核到 -03），RFC 9725 是 WHIP |
| R5 | ICE 仅单 host candidate，无 TURN/trickle/ICE restart；无 TWCC/REMB，部分服务器可能降码率 | NAT/防火墙环境失败；画质被服务器压低 | 范围内明确"只支持直连/公网可达服务器"；记录为已知限制；TWCC 后续另立 |
| R6 | mingw-w64 头文件可能缺 `SECPKG_ATTR_DTLS_MTU`（`configure:7619` 的探测会失败） | Windows SChannel DTLS 不可用 | T0.3 先验；缺失则补宏定义补丁（值需来自 Windows SDK，**未核实**），或 Windows 退而用 openssl（体积/许可代价需评估，另议） |
| R7 | `ff_srtp_decrypt` 无重放保护（源码 TODO）；`ff_rtp_send_rtcp_feedback` 用 `ssrc+1` 做本机 SSRC，且写明文 | 安全性/与 WebRTC 服务器不兼容 | T1.3/T1.5 自补；写入"安全限制"一节 |
| R8 | 许可：MPL 文件入库、LGPL 双口径、CI 的 `License: LGPL...` grep 与 MPL 并存 | 合规风险、CI 误判 | T-L1；法务复核；这不是法律意见 |
| R9 | 补丁绑定 ffmpeg tag，升 tag 需手工 rebase；不指望上游 | 维护成本 | 补丁单文件为主（`whep.c` 新增文件，对既有文件仅改 Makefile/allformats/configure 几行） |
| R10 | SRS 的 `webrtc://` 是私有写法，信令实为 HTTP；SRS `whip-play` 接口形态未核实 | 映射层设计 | libmpv 只认标准 scheme，业务适配由使用方做；T1.2 对 SRS 实测 |
| R11 | mpv 默认缓存吃掉亚秒延迟 | 失去 WebRTC 的低延迟意义 | T1.6 开放参数并记录数据，供使用方选值 |
| R12 | 测试台（`tc netem` 在 WSL 可用性、延迟测量读数法）未核实 | 验收不可复现 | T1.7 先验证，不通过则换工具并更新方法 |
| R13 | 体积估计是最小子集上的数字，非 mova 真实 flavor | 预算可能偏差 | 每平台 flavor 增量实测并对照 §4 红线 |
| R14 | Windows gcc 16.2 miscompile 已用 clang 规避；n9.0.2 新代码是否触发同类问题未知 | 真机崩溃 | T2.2 前先跑 `mpv_create` 冒烟与长时播放；沿用"一次一变量"原则 |

### 8.2 待决问题

> **2026-10-01 用户授权专家决定，以"小体积"为首要目标**，结论如下，下表保留选项与理由备查：
> Q1=(b) 按需拷贝/移植（默认不拷 libjuice，只移植 NACK 多 FCI 打包，`whip.c` 的 STUN/ICE 不够再拷 `stun.c`）；
> Q2=libmpv 只认标准 scheme，URL 映射属 mova 侧、不在本计划内；Q3=(b)；Q4=(b)；Q5=(b)；Q6=(a)；
> Q7 作废（mova 侧事项，本计划只开放参数）；Q8=(a)；Q9 不触发（T0.2 修订：mpv v0.41.0 + 最小静态 libplacebo + 摘 `vo_gpu_next` + n9.0.2，见 T0.2）。

| # | 问题 | 选项 | 推荐 |
|---|---|---|---|
| **Q1** | **D3"直接拷贝"的落地口径**（§5 事实：libdatachannel 无接收端 NACK 检测、且为 C++；libjuice 可拷的 C 文件与 `whip.c` 已有功能重叠） | (a) 按 D3 字面：拷 libjuice 相关 C 文件（连带 ~8–10 个依赖文件）+ 把 libdatachannel 的 NACK 包构造翻译成 C；(b) **按需拷贝/移植**：默认不拷 libjuice，只移植 NACK 多 FCI 打包，实测不够再拷 `stun.c` ；(c) 完全不拷，参考算法自写（不继承 MPL） | **(b)**：合规面最小又保留"逻辑来自成熟实现"；若要彻底免 MPL 选 (c)，代价是 NACK 打包要自己写十几行（风险低） |
| Q2 | URL 映射放哪一层 | (a) libmpv 层：demuxer `read_probe` 认 `whep://`、`whep+http(s)://`，并可内部兼容 SRS `webrtc://`；(b) mova Dart 层：把任意输入映射为标准 `whep+https://...`；(c) 两层都做 | **(b) 为主 + (a) 只认标准 scheme**：SRS 私有写法是业务适配，不应固化进 C 补丁；Dart 层易改易测 |
| Q3 | 默认 flavor 何时切 n9.0.2 | (a) 立即全平台切；(b) 仅 `*-whep` flavor 用 n9，默认 flavor 回归全绿（含补测 README 里"未测"项）后再切 | **(b)**：升级风险与默认产物解耦，可回滚；符合 D2（仍升级，只是排期） |
| Q4 | iOS/macOS 在本期是否同步升 ffmpeg | (a) 同步升（无 Mac 无法真机验证）；(b) 保持 n6.0.1，WHEP flavor 不含 darwin | **(b)**：无 DTLS、无 Mac；避免引入无法验证的变更 |
| Q5 | 联调服务器范围 | (a) 仅 MediaMTX；(b) MediaMTX + SRS；(c) 再加 Janus/LiveKit 等 | **(b)**：MediaMTX 标准 WHEP 易验证；SRS 是国内主流且有私有写法 |
| Q6 | `whip.c` 公共代码处理 | (a) `whep.c` 拷一份自带；(b) 抽公共头 `webrtc_common.h` 并改 `whip.c` | **(a)**：不动上游文件，补丁小；公共化留给确认路线稳定后 |
| ~~Q7~~ | ~~mova 是否开放 mpv 属性注入出口~~ | — | **作废**：属 mova 侧业务，本计划只开放参数（T1.6） |
| Q8 | Linux WHEP 产物是否出货 | (a) 仅作开发验证平台；(b) 同样出货 | **(a)**：Linux 在 mova 里用系统 libmpv（`linux` job 的注释），出货价值待确认 |
| Q9 | 若 T0.2 显示必须升 mpv 且与 media_kit 不兼容 | (a) 停 D2，另议；(b) 同时 fork media_kit 绑定 | **已消解**：改用 mpv v0.41.0（对 n9.0.2 无需补丁）+ 最小静态 libplacebo + 摘 `vo_gpu_next`，media_kit 公开符号仍在，无需 fork（见 T0.2 修订） |

## 9. 验证推进表

> mova `flutter test` 当前基线 **1008 项**（mova CLAUDE.md，2026-10-01）。本计划各 Task 均不改 mova，该数字应保持不变。

| Task | 验证手段（真实事件/数字） | 通过判据 | mova 测试基线 |
|---|---|---|---|
| T0.1 | 回归脚本 × 现有产物 | 全绿，基线表入库 | 1008（不变） |
| T0.2 | WSL 编译 + `mpv_create` 冒烟 5/5 | 得出可用配对或不可行结论 | 1008 |
| T0.3 | 四项小验证各有日志证据 | 各项通过/不通过明确 | 1008 |
| T0.4–T0.6 | CI + 回归脚本 + §7.2 真机/桌面 | 与基线等价，体积差异已归因 | 1008 |
| T0.7 | 决策记录 + CI 绿 | 明确 iOS/macOS 去留 | 1008 |
| T-L1 | CI 比对脚本 + 外部复核记录 | PROVENANCE 与入库一致，复核有记录 | 1008 |
| T1.2–T1.5 | MediaMTX/SRS 日志 + 抓包 + `whep.c` 计数器 + netem 5 次取平均 | 握手成功、解密失败 0、NACK 前后对比 | 1008 |
| T1.6 | 首帧时间、稳态延迟、`paused-for-cache` 计数（5 次平均） | 给出可复现数据表与开放参数说明 | 1008 |
| T1.8 | CI 体积增量 | ≤ §4 红线；默认 flavor 字节不变 | 1008 |
| T2.x | Windows 实机 | 同 T1.5 口径 | 1008 |
| T3.x | STG-AL00 真机（亮屏解锁前置） | 硬解起播、NACK 计数、体积≤红线 | 1008 |

## 10. 不做的事

- 不改 mova 的 `MovaKernel`，不引入 `flutter_webrtc`，不引入整套 libwebrtc 或整套 libdatachannel（D1）。
- 不选 ffmpeg n9.1-dev；不复用已作废的 `mova-libmpv-winbuild-zhangfly`（n9.0+mpv 0.41）分支代码/数据（仅作 T0.2 的旁证引用，不拷代码、不引用其体积数字作预算）。
- 不为 iOS/macOS 在本期引入 DTLS 后端；不在 iOS 上为此换掉 securetransport。
- 不做 WHIP 推流产品化（`whip.c` 只作代码参考，不启用 `whip` muxer 进出货 flavor；测试台推流用 ffmpeg 完整版/服务器自带源）。
- 不做 TURN/trickle ICE/ICE restart、TWCC/REMB 拥塞控制、simulcast/SVC、数据通道、多路 bundle 之外的拓扑。
- 不做 VP8/VP9/AV1 的 WebRTC 协商（现有 flavor 已砍 VP8；VP9 仅硬解、AV1 另议）；本期 H.264 + Opus。
- 不向上游 ffmpeg 提交补丁；不修改 `whip.c`。
- 不把"WHEP 不可用"伪装成成功：服务器协商失败时报明确错误（`AVERROR`+日志），不静默降级到其他协议。
- 不使用墙钟 + sleep 做真机判据；不在锁屏/熄屏时做 Android 渲染相关测量。
- 不为"体积"牺牲已验证能力：默认 flavor 的现有解码器/协议清单不变。

## 11. 执行记录

（落地 agent 在此追加：每个 Task 的日期、commit hash、实测字节数/日志摘要、遇到的意外与处理。本文档规划时尚未执行任何 Task。）
