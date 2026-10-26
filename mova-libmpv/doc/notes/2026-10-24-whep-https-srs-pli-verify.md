# WHEP：https 信令 / .so 差异 / SRS 与 PLI / 音频丢包 / RTX·TWCC 评估

日期：2026-10-24。分支 `feat/whep-receiver`。环境：WSL Ubuntu，ffmpeg n9.0.2 + 补丁 0001-0011（只编 ffprobe，`--disable-everything` + whep），OpenSSL 3 与 mbedtls 3.6.4（`/root/mova-ffmpeg-v9-slim/prefix`，静态）两个后端。证据在 WSL `/root/w/`（pli_*.txt、aud*.pcap、*.log，不入库）。

## 1. https 信令下的 chunked answer（补丁 0011）：通过，无需改补丁

- `mock_whep_signal.py` 新增 `--tls-cert/--tls-key`（自签证书，监听 HTTPS）；`whep_chunked_regress.sh` 改为接受多个 ffprobe，对每个都跑 http/https x bigcl/big 四种组合（openssl 临时生成证书，客户端 `-tls_verify 0`）。
- 实测（answer 2136 字节）：OpenSSL 与 mbedtls 各 4/4 PASS，https+chunked 均读到 answer。
- 注意：mbedtls 必须 3.x（系统 apt 的 2.28.8 编不过 0007 的 tls_mbedtls.c），且 configure 要 `--enable-version3`；ffmpeg 要把 `https` 写进 `--enable-protocol`（n9 的 https 协议需显式启用，Linux 只开 `tls` 时 `whep+https` 不可用）。
- 未做：未对 https 单独做"不带 0011"的失败对照（http 版 A/B 已在 chunked-answer-fix 笔记里）。

## 2. 新旧 Android libmpv.so 差 240 字节：来源已查清，与 0011 无关的部分是构建环境

旧 6,354,272（sha 3692f701）、新 6,354,032（sha c8de73be）。逐 section 对比：

| 项 | 旧 - 新 | 原因 |
|---|---|---|
| `.dynstr` | +178 B | 旧件带 `DT_RUNPATH`，值为 CI 的 NDK sysroot 绝对路径 `/home/runner/work/_temp/whep-android/ws/.../aarch64-linux-android/21`；新件（WSL 构建）没有该条目 |
| `.dynamic` | +16 B | 少一条 DT_RUNPATH 项 |
| `.rodata` | +64 B | mpv `Configuration:` 字符串：构建根路径 `/home/runner/work/_temp/whep-android/ws` vs `/root/w/andbuild/ws`（短 20 字符 x 2 处），并且 meson 参数顺序/大小写不同（`prefer_static=True` vs `true`，`buildtype` 位置） |
| `.text` | -28 B（新比旧多 28 B） | 7 条 aarch64 指令，吻合 0011 多出的一次 `av_dict_set_int(&opts,"multiple_requests",1,0)` |
| 其余 section（eh_frame、data.rel.ro、bss、符号表） | 0 | `--dyn-syms` 符号集完全一致，build-id/.comment 都没有 |

结论：+28 字节 `.text` 是 0011 的真实代码增量，其余 -268 字节全是构建路径/RUNPATH 差异（CI vs 本地 WSL），没有其他功能差异。

## 3. SRS 与 PLI 起播收益

### 3.1 SRS 可跑，但默认配置与当前客户端不兼容（**计划未覆盖，原样记录，未改补丁**）

- SRS v6.0-r2 CentOS7 静态包（GitHub release，aria2 下载），WSL 里直接运行，不需要 docker（WSL 没有 docker）。
- WHEP 接口形态（计划标"未核实"，现已核实）：`POST /rtc/v1/whep/?app=live&stream=<s>`（以及 `/rtc/v1/whip-play/`）均可，`Content-Type: application/sdp`，返回 201 + SDP，`Location: http://.../rtc/v1/whip/?action=delete&token=..&app=..&stream=..&session=..`（DELETE 可用）。answer 带 `a=ice-lite`，媒体：opus pt111、H264 pt102，**无 RTX**，视频 `nack`/`nack pli`，音频无 nack。
- **默认 `dtls_role passive`：SRS 对我们的 `setup:actpass` offer 回 `setup:passive`**，即要求客户端当 DTLS client；`whep.c` 只实现了"answer 为 setup:active（我方 DTLS server）"（`whep_dtls` 里 `Unsupported answer setup`），于是表现为 `ICE timed out (connectivity check succeeded, no DTLS from peer)`。
- 两条出路都实测：(a) 服务端配 `rtc { dtls_role active; }` 立即通；(b) 客户端 offer 改成 `setup:passive`（RFC 5763 允许，临时副本验证）后，**默认配置 SRS** 回 `setup:active`，也通（首个关键帧 710ms）。未对 MediaMTX 及其他服务端验证 (b)，且这是协议层决策，**需要决定**：改 offer（一词）还是实现 DTLS client 角色。
- SRS 要求 `candidate` 为可达地址（loopback 下 `127.0.0.1` 可用；与 aiortc 推流联调需用 WSL eth0 IP）。

### 3.2 SRS 对 PLI 的响应取决于推流源

测法：同一台机、Linux flavor（OpenSSL）ffprobe，`-rtcp_pli 1/0`，随机错开起播相位，指标 = "First video key frame out ... since open"（自 open 起首个关键帧输出的毫秒数）。推流 640x360@25 H264 baseline，`-g 50`（2s GOP）。

| 服务端 / 推流源 | PLI | n | 均值 ms | 中位 ms | <800ms 占比 |
|---|---|---:|---:|---:|---:|
| MediaMTX v1.21.1（RTSP/TCP 推流） | 开 | 40 | 1027 | 1121 | 45% |
| MediaMTX | 关 | 40 | 1084 | 1112 | 32% |
| SRS 6.0-r2（RTMP 推流，rtmp_to_rtc） | 开 | 40 | 1019 | 1081 | 38% |
| SRS（RTMP） | 关 | 40 | 980 | 1001 | 38% |
| SRS（aiortc WHIP 推流，响应 PLI） | 开 | 20 | **68** | 68 | **100%** |
| SRS（aiortc WHIP） | 关 | 20 | 1248 | 1061 | 35% |
| SRS（aiortc WHIP，GOP=250 参数） | 开 | 20 | **74**（51-84） | 74 | 100% |
| SRS（aiortc WHIP，GOP=250 参数） | 关 | 20 | 1564 | 1545 | 10% |

- 结论：**MediaMTX 与 SRS 都不会为 RTMP/RTSP 推流源产生 PLI 响应**（两者桥接源没有向编码器请求关键帧的通路），PLI 开关与否分布一致（n=12 的小样本曾出现假象，n=40 后消失）。
- **只有推流端自己是能响应 PLI 的 WebRTC 发布者时才有收益**：SRS 把播放端 PLI 转发给发布者（aiortc 日志每次试验一条 `PLI/FIR received`，20/20），首个关键帧 **68-74ms vs 无 PLI 1.2-1.6s**，且稳定（min-max 51-85ms）。
- 说明：aiortc 的 x264 GOP 通过环境变量改 keyint，"GOP=250" 组在 pli=0 时均值只有 1.5s，说明该 keyint 覆盖并未真正生效（实际 GOP 仍 ~2-3s），故 GOP 变量不可当作有效对照；PLI 效果本身（68-74ms）不受影响。aiortc 与测试脚本只在 WSL venv，不入库（pip 安装 aiortc/aiohttp/numpy，仅作测试工具）。
- 起播首个 RTP 包：SRS 平均 12-23ms，MediaMTX 53-149ms（loopback，信令后）。
- **未做**：真机 7NQBB23606003715 复测。SRS 跑在 WSL（NAT 网络），手机同网段 192.168.254.x 访问不到；需在 Windows 上起 SRS 或做端口映射（需放行入站，之前记录 PC 防火墙不能新增规则）。未做长时稳定性。

## 4. 音频丢包 130-149 的来源：不是服务端序号间隙，也不是客户端统计缺陷

- Linux loopback（无 Wi-Fi），MediaMTX v1.21.1 Linux，ffmpeg RTSP 推流（opus+H264），tcpdump 抓 lo 上 UDP 8189，用脚本解析 SRTP 头（序号明文）：30s 会话，音频 SSRC 服务端发出 1502 包、序号**零缺口**；客户端统计 `packets=1501 lost=0`；视频 1871 包零缺口。MediaMTX 对音频不产生序号间隙（0/1502）。
- 客户端统计准确性：经 `whep_tamper_proxy.py lossy`（5%）丢包，服务端抓包音频发出 1500 包，客户端 `packets=1433 lost=67`，1500-1433=67，一致；视频 NACK 恢复 `rtx_recovered=93/nack_seqs_sent=100`。
- 因此手机上直连也稳定 130-149 的音频 lost（约 5%）只剩真实网络丢包（Wi-Fi，音频无 NACK 不重传）一种解释。**无需修客户端**。未做：在手机/Wi-Fi 侧抓包做逐包对账（PC 无抓包工具/权限）。

## 5. RTX / TWCC 可行性评估（只评估，未实现）

### RTX（RFC 4588）

- 现状：offer 已带 rtx 的 rtpmap/apt；`whep.c` 里 `nack_on = rtcp_nack && nack && rtx_pt < 0`，即**answer 一旦协商 RTX，客户端会整路关闭 NACK**（代码 TODO 已注明）。MediaMTX、SRS 都不协商 RTX（原 PT 重发），所以当前实测不受影响；mediasoup/Janus/LiveKit/libwebrtc 系服务端会协商 RTX，此时我们实际退化为"只靠 PLI"。
- 做法：BUNDLE 下以 PT 区分，rtx_pt 的包 = 2 字节 OSN + 原载荷，SSRC 独立；还原成 `seq=OSN, pt=主 PT` 后走现有 `whep_rx_push`/`whep_gap_find`（计数 `rtx_recovered` 已有）。要点：RTX SSRC 有独立的序号空间，**需要独立的 SRTP 解密上下文**（同密钥，`ff_srtp_set_crypto` 再建一份，否则 ROC 混乱）；NACK 请求里的序号仍是主流序号。
- 规模估计：约 80-120 行 C，二进制 +约 1KB；与平台/TLS 后端无关。
- 验证难点：本地没有会发 RTX 的服务端。可行方案：用 aiortc 写一个最小 WHEP 服务端（aiortc 支持协商 RTX 并响应 NACK 重传，约 60 行信令代码，仅测试用），在 loopback 加 `whep_tamper_proxy` 丢包，对比 NACK 恢复率。风险低，价值取决于目标服务端：若业务只用 MediaMTX/SRS 则收益为零。**建议：先不做，确认目标服务端后再排**。

### TWCC（transport-wide congestion control）

- 需要：offer 加 `a=extmap:N http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01` 与各 PT 的 `a=rtcp-fb:PT transport-cc`；RTP 头扩展解析（取 16 位传输序号，音视频共用一个序号空间）；记录每包到达时间；按约 50-100ms 发 RTCP 传输层反馈（PT 205/FMT 15：base seq、状态数、参考时间、packet status chunk、recv delta，单位 250µs）。
- 规模估计：约 200-300 行 C，二进制 +3-4KB，须小心 chunk 编码（run-length/status vector）与回绕。
- 价值：只有发送端做 BWE/自适应（libwebrtc 系 SFU、LiveKit、mediasoup 的 simulcast 选层与 pacing）才用到；MediaMTX、SRS 对播放端是直转/不做拥塞自适应，**对它们没有收益**；且我们没有码率切换的消费侧逻辑。
- 验证难点同 RTX（缺能用 TWCC 的本地服务端，aiortc 不实现 TWCC 发送侧；可行验证手段只有抓包对比 libwebrtc 格式或 mediasoup/LiveKit 实测）。
- **建议：不做**，除非目标服务端明确需要。若服务端只想要接收反馈作拥塞检测，替代最小方案是 RR（已有，1/秒）。

## 未解决 / 需要决策

1. SRS 默认 `dtls_role passive` 与客户端不兼容：改 offer 为 `setup:passive`（一词，SRS 默认配置已实测通过，但未验证其他服务端）还是实现 DTLS client 角色。**未改补丁**。
2. 真机复测 SRS+PLI 未做（网络可达性，见 3.2）。
3. 不带 0011 的 https 失败对照未做；Windows(SChannel) https 未测。
4. aiortc keyint 覆盖未生效，GOP=250 对照不可用。
