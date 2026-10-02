# ffmpeg n9.0.2 WHEP 补丁序列

只用于 `*-whep` flavor（ffmpeg n9.0.2 + mpv v0.41.0），默认 flavor 不吃这些补丁、行为不变。
补丁基于 ffmpeg 官方 `n9.0.2`（`946fcce`），用 `git apply` 按编号依次打，`build-linux.sh` 在 `WITH_WHEP=1` 时自动执行。

| 序号 | 文件 | 作用 |
|---|---|---|
| 0001 | `0001-avformat-register-whep-demuxer-off-by-default.patch` | `allformats.c`/`Makefile`/`configure` 注册 `whep` demuxer；configure 里 `disable whep_demuxer` 使其**默认关闭**，只有 `--enable-demuxer=whep` 才开；`whep_demuxer_select="dtls_protocol http_protocol srtp"` |
| 0002 | `0002-avformat-http-expose-Link-response-headers.patch` | `http.c` 记录响应里的 `Link` 头，新增内部函数 `ff_http_get_link_headers()`；WHEP 靠它读 `rel="ice-server"`（n9.0.2 的 http 层不暴露任意响应头） |
| 0003 | `0003-avformat-whep-add-WHEP-demuxer-signalling-and-SDP-T1.patch` | 新增 `libavformat/whep.c`：T1.2 的信令与 SDP（见下） |
| 0004 | `0004-avformat-whep-ICE-DTLS-SRTP-key-export-T1.3-stage-A.patch` | T1.3 阶段 A：`whep.c` 加 ICE 连通性检查 + DTLS(server) 握手 + 指纹校验 + SRTP 密钥导出；`tls_openssl.c`/`tls.h` 加 `ff_dtls_get_peer_fingerprint()`、DTLS server 请求客户端证书、握手循环响应中断回调 |
| 0005 | `0005-avformat-whep-SRTP-decrypt-and-RTP-depacketize-T1.3-stage-B.patch` | T1.3 阶段 B：只改 `whep.c`。握手后真正收媒体：UDP 分流（STUN/DTLS/RTP/RTCP）、SRTP 解密、RTP 重排、H.264/Opus 解包出 AVPacket，周期 consent 检查与存活检测，新增 `media_timeout` 选项 |
| 0007 | `0007-avformat-tls-mbedtls-dtls-srtp-peer-fingerprint.patch` | mbedTLS 后端（Android）：`ff_dtls_get_peer_fingerprint`、DTLS server 请求客户端证书、可中断握手、EAGAIN 修正；`whep.c` 指纹分支守卫改为 `CONFIG_OPENSSL \|\| CONFIG_MBEDTLS \|\| CONFIG_SCHANNEL`（只改这一行，避免与 0006 冲突） |
| 0008 | `0008-avformat-tls-schannel-dtls-srtp-peer-fingerprint.patch` | SChannel 后端（Windows）：同上，外加 SRTP profile 协商缓冲（0x0100）、`ASC_REQ_MUTUAL_AUTH`、有界 shutdown；`tls.h` 注释更新 |
| 0009 | `0009-avformat-tls-mbedtls-srtp-profile-list-static.patch` | mbedtls SRTP profile 数组改 static const（悬空指针修复，见下） |
| 0006 | `0006-avformat-whep-security-hardening.patch` | 安全加固，只改 `whep.c`：Location 同源校验、带 token 不跟随 3xx、指纹长度严格检查、STUN HMAC 常量时间比较、ICE 连续 socket 错误上限、关闭时清零 DTLS 私钥与 SRTP 材料（见下「信任模型与安全加固」） |
| 0010 | `0010-avformat-whep-RTCP-feedback-PLI-RR-NACK.patch` | T1.5：只改 `whep.c`。SRTCP 加密发 RTCP：周期 RR、NACK（缺口表 + 多 FCI 打包 + 重试/放弃）、PLI（起播 + 不可恢复丢包，限速 1/s）；新增 `rtcp_nack`/`rtcp_pli`/`rtcp_interval`；**仅无 RTX 路径**（见「RTCP 反馈」） |

补丁须按文件名顺序依次 apply（0001 到 0010，已在干净 n9.0.2 上逐个 `git apply --check` 并 apply 通过）。0006 为安全修复；0007/0008/0009 只改各 TLS 后端；0010 只改 `whep.c`。

编号说明：0003 依赖 0002 的 `ff_http_get_link_headers`，所以 http 补丁排在 whep.c 前面。

## 信任模型与安全加固（0006）

- **指纹的可信度取决于 answer 信道**：DTLS 对端身份只靠 answer 里的 `a=fingerprint` 比对。`whep+https` 且 `tls_verify=1` 时 answer 走经校验的 TLS，指纹可信；`tls_verify=0`（默认，mpv 也默认注入 0）时，能篡改信令的中间人可以连指纹一起换掉，DTLS 校验就只能防媒体面的第三方，防不了信令面的主动中间人。要抗主动中间人，请用 `whep+https` 并开 `tls_verify=1`（可配 `ca_file`）。
- **Location 必须与信令 URL 同源**（scheme、host、port 全一致，端口缺省按 scheme 归一）：201 的 `Location` 不同源时丢弃并告警，**不对它发 `DELETE`**（该请求带 `Authorization: Bearer`，否则恶意/被劫持的服务端能借此把 token 发往别的 host，或把 https 降级成 http）。代价：这种会话不会被主动释放，只能等服务端回收。
- **设了 `token` 就不跟随 3xx**（`max_redirects=0`）：ffmpeg 的 http 层跟随重定向时会把 `Authorization` 带给目标地址。信令端点若依赖重定向，请直接填最终地址。未设 `token` 时行为不变。
- 指纹长度必须恰好是 SHA-256 的形式（此前超长串会被 `av_strlcpy` 截断后误通过）；STUN `MESSAGE-INTEGRITY` 常量时间比较；ICE 阶段连续 50 次 socket 错误（约 10s 的发送周期，例如对端 ICMP 不可达）返回 `ECONNREFUSED`，`handshake_timeout=-1` 时不再无限重试；`read_close` 用 volatile 写清零 DTLS 私钥与 SRTP 材料（本树没有 `av_explicit_bzero`）。tls 层内部另有一份私钥 PEM 副本，由 tls 层自己释放，这里管不到。
- **0004 里 `tls_openssl.c` 改动的影响面**：DTLS + `use_srtp` + `listen` 的 server 路径现在无条件发 CertificateRequest 并接受任意证书（信任由调用方比对指纹）。同一路径的另一个使用者是 `whip.c` 作 DTLS server 时：握手多一条客户端证书请求，浏览器类对端照常回证书；whip 本身不比对指纹，所以安全性不增不减。为省体积没加开关（加条件要在 `TLSShared` 加字段和 AVOption）；如需只对 whep 生效，可加 `dtls_request_client_cert` 选项并由 `whep.c` 置 1。
- 回归：`tools/whep-flavor/whep_origin_regress.py`（跨 host 的 Location / 307 跳转，evil 端必须收到 0 个请求）。

## whep.c 当前能力（T1.2）

- URL：`whep+http://`、`whep+https://`、`whep://`（`whep://` 默认走 **https**，明文 http 必须显式写 `whep+http://`）。
- offer：`o=` 行 sess-id 为 `AV_RB64(随机)&INT64_MAX` 的**十进制**（RFC 4566；十六进制会被 MediaMTX/pion 以 400 拒绝）；recvonly、opus + H264（三档 profile，各带 RTX）、`rtcp-fb nack` / `nack pli`、`setup:actpass`、`sha-256` 指纹、随机 ice-ufrag/pwd。payload type 只是提议，**以 answer 为准**。
- 信令：`POST`（`Content-Type: application/sdp`，可选 `Authorization: Bearer`），读 201 的 `Location`（相对地址会被 http 层解析成绝对地址）、`Link: rel="ice-server"`；关闭时 `DELETE`。read_header 失败（例如 answer 无指纹）也会 `DELETE` 已建立的会话（`FF_INFMT_FLAG_INIT_CLEANUP`）。
- answer 解析：自写最小子集（不复用 `rtsp.c` 的 `ff_sdp_parse`）。必填 ice-ufrag/pwd、格式合法的 sha-256 指纹、`a=setup`、一个 UDP 候选、至少一条 opus/H264。缺指纹、算法不是 sha-256、格式不对一律拒绝。
- 建流：按 answer 的 m= 行顺序挑 codec，建 H264（取 profile/level）与 Opus（48k）两条 AVStream。
- 媒体接收见下文「T1.3 阶段 B」；RTCP 反馈（RR/NACK/PLI）见下文「RTCP 反馈（T1.5，0009）」；**未实现**：RTX、TWCC。

## 媒体通路（T1.3 阶段 A，0004）

流程：POST 得 answer -> 单 UDP socket `connect` 到 answer 首个 host 候选 -> ICE -> DTLS -> 导出 SRTP 材料。

- **ICE**（自写最小 STUN，沿用 `whip.c` 的报文布局思路，HMAC/CRC 用 ffmpeg 自带，无第三方库）：我方 controlling、带 USE-CANDIDATE（激进提名）；请求每 200ms 重发（同一事务 ID），USERNAME=`对端ufrag:本端ufrag`，MESSAGE-INTEGRITY 用对端 pwd，带 FINGERPRINT。服务端发来的检查请求会校验 USERNAME 与 MESSAGE-INTEGRITY（本端 pwd）后再回成功响应（含 XOR-MAPPED-ADDRESS，来自已 connect socket 的对端地址）；收到的成功响应要校验事务 ID 与 HMAC（对端 pwd）。单 socket、单 host 候选，不做 trickle/TURN/多候选。
- **探测 DTLS 不丢包**：ICE 循环用 `recv(MSG_PEEK)` 看到 ClientHello 就停，不消费它，再把 socket 交给 dtls 协议（whip 的做法会吞掉第一个 ClientHello，要等对端重传）。
- **DTLS**：answer 为 `setup:active` 时我方是 DTLS server（`listen=1`、`external_sock=1`、`use_srtp=1`、`mtu=1200`）。`setup` 不是 `active` 目前返回 `AVERROR_PATCHWELCOME`。握手后**必须**取到对端证书，其 SHA-256 与 answer 的 `a=fingerprint` 不一致即 `AVERROR(EACCES)` 拒绝；非 OpenSSL 后端（还没有 `ff_dtls_get_peer_fingerprint`）一律拒绝，不放行未验证的对端。
- **SRTP 材料**：`ff_dtls_export_materials` 导出 60 字节（`client_key|server_key|client_salt|server_salt`，profile `SRTP_AES128_CM_HMAC_SHA1_80`）存进 `WHEPContext.srtp_materials`，关闭时清零；日志只打长度与 profile，不打密钥。
- **tls 层改动**（影响所有 DTLS-SRTP server 用户，包括 whip 作 passive 时）：DTLS server 现在会发 CertificateRequest（WebRTC 双向证书要求；用接受任意证书的校验回调，信任只来自指纹比对）；`dtls_handshake` 的轮询循环检查 `interrupt_callback` 且单次等待不超过 100ms，使 `handshake_timeout` 能打断握手。
- **超时/错误**：整个 ICE + DTLS 受 `handshake_timeout` 约束；任何失败 `read_header` 返回负值，`read_close` 仍会 DELETE 已建立的会话。

## 媒体接收（T1.3 阶段 B，0005）

`read_packet` 阻塞在 UDP 上（每 20ms 一轮：查中断回调、做周期事务、再收包），一个数据报的处理流程：

1. **分流**（RFC 7983/5761）：首字节 0..3 为 STUN，20..63 为 DTLS，128..191 为 RTP/RTCP；RTCP 以第二字节 192..223 判断（rtcp-mux）。STUN 复用阶段 A 的 `whep_stun_verify` / `whep_ice_build_response`（抽成 `whep_stun_input`，ICE 阶段与媒体阶段共用）。握手后收到的 DTLS 记录（含 alert）**直接忽略**，不据此断流（未经认证的 alert 不能让流被伪造中断），断线靠存活检测。
2. **SRTP**：材料布局 `client_key|server_key|client_salt|server_salt`。我方是 DTLS server，对端（client）用 **client 写密钥**加密，所以接收解密用 `client_key + client_salt`（与 `whip.c` 被动端约定一致；server 密钥是我方发送用的，WHEP 不发 SRTP 故不用；以后发 RTCP 反馈时才用到）。每路媒体一个独立 `SRTPContext`——`ff_srtp_decrypt` 只有一份 seq/ROC 状态，音视频共用会互相污染。认证失败的包丢弃并计数（日志按 2 的幂次限频）；SRTP 层本身无重放窗口，重复/过旧包由下面的序号重排丢弃。套件只有 `SRTP_AES128_CM_HMAC_SHA1_80`。
3. **RTP 重排**：每路 32 包的乱序缓存，缺口最多等 80ms，等不到就跳过并记丢包；序号跳变 ≥32 直接重新对齐。过旧/重复/非首个 SSRC 的包计入 `late/dup`。
4. **解包**：自写，不用 ffmpeg 的 `rtpdec`（原因见下）。H.264：单 NAL、STAP-A、FU-A，转 Annex B，marker 位或时间戳变化结束一帧，输出整帧 AVPacket；**第一个 IDR 之前的帧丢弃**；不完整的帧（FU-A 缺片/缺口）丢弃。Opus：载荷即包，按 TOC 填 duration，extradata 在建流时写 OpusHead。
5. **时间戳**：各流以首包为 0 展开 32 位回绕，再叠加"该流首包相对全局首包的到达时间差"以对齐音视频；还没有用 RTCP SR 校准（T1.5）。pts 单位为各流 clock（H.264 90k，Opus 48k）。
6. **consent / 存活**：每 2.5s 向对端发一次 STUN 检查（同阶段 A 的请求格式）；任何经认证的对端数据（RTP、RTCP、STUN 请求/响应）都刷新存活时间，`media_timeout`（默认 5s）内没有就返回 `ETIMEDOUT`。服务端自己也每约 2s 发检查，我们都应答。
7. **RTCP**：解密校验后处理 BYE（该路标记结束，所有路都 BYE 则 `EOF`）；0010 起还读 SR 的 NTP 中间 32 位（回填 RR 的 LSR/DLSR）。阶段 B 本身不发 RTCP，0010 补上。
8. **中断**：阻塞等待，但每 20ms 检查 `interrupt_callback`，返回 `AVERROR_EXIT`。**刻意不返回 `EAGAIN`**：mpv 的 `demux_lavf` 把连续 10 次读包错误（包括 EAGAIN）当致命错误，实测 `EAGAIN` 方案会在直播源停流约 0.5s 后误杀播放；阻塞读 + 中断回调实测 mpv 销毁耗时 20–39ms。
9. 关闭仍 `DELETE`；verbose 日志在关闭时打印每路计数（packets/auth_fail/late/lost/frames/dropped_frames/before_keyframe）与 STUN 计数。

**为什么不用 `rtpdec`**（实测）：`rtpdec.c` 里有一张列出全部 payload handler 的静态表，只要链接 `rtpdec.o` 就会把 asf/rm/qt/mpegts 等 handler 全部拖进来，configure 的 `rtpdec_select` 还会强制启用 `asf_demuxer`/`rm_demuxer`。对照构建（同参数、`-Os` + `--gc-sections` 的 ffprobe，仅 `whep` 与 `whep,sdp` 之差，后者经 `sdp_demuxer_select="rtpdec"` 引入 rtpdec）：stripped 1,501,376 -> 1,845,696 字节，**+344,320（+23%）**，而自写解包只让 `whep.o` 的 text 从 14,939 增到 20,743（+5.8KB）。另外 `rtpdec` 的 SRTP 认证失败不可计数、重排队列需要缓冲区所有权约定，收益不抵代价。

### 阶段 B 的已知限制 / 未做

- **起播等 IDR**（0009 起会发 PLI，但 MediaMTX 不响应，见下）：首帧要等下一个 IDR（测试源 GOP=50 帧即最多 2s）。ffprobe 约 1.9s，mpv 约 2–3s 出画面。T1.5 的 PLI（连接后立刻请求关键帧）可以消掉这段等待——这是 T1.5 的第一项。
- **丢包后画面**：不完整的帧被丢弃，但后续 P 帧仍会送给解码器，会有花屏直到下一个 IDR（没有 NACK/PLI 就无法修复）。丢包时音频靠解码器 PLC。
- **不发 RR**：实测 MediaMTX v1.21.1 在不发任何 RTCP 的情况下连续播 40s 不断流、帧率满 25fps（只验证了 40s，更长时间或其他服务端未验证）。
- 只支持 `SRTP_AES128_CM_HMAC_SHA1_80`；只处理 H.264（packetization-mode 0/1 的单 NAL/STAP-A/FU-A，不支持 STAP-B/MTAP/FU-B）和 Opus；RTX 包（未协商的 PT）直接丢弃并计数。
- DTLS 握手后的 alert 被忽略；对端异常消失靠 `media_timeout`。
- 时间线对齐只用到达时间，A/V 同步精度约为两路首包到达的间隔（本机实测可忽略），不是 RTCP SR 级精度。
- 对端若改变 SSRC（发布端重连），之后的包会被当作"非首个 SSRC"丢弃，需要重新连接。

## AVOption

| 名字 | 默认 | 说明 |
|---|---|---|
| `token` | 无 | Bearer token（含 CR/LF 会被拒绝） |
| `timeout` | 10000000 | 信令 HTTP 的 I/O 超时，**微秒**（与 mpv 注入、rtsp 的 `timeout` 约定一致，mpv 会注入 `60000000`），`-1` 不限，上限 `INT_MAX` |
| `tls_verify` | 0 | https 是否校验服务端证书（透传给 tls 层；mpv 会自动注入 `tls_verify`） |
| `ca_file` | 无 | `tls_verify=1` 时用的 CA 文件 |
| `user_agent` | 无 | 信令请求的 User-Agent（mpv 会自动注入） |
| `handshake_timeout` | 10000000 | ICE + DTLS 握手总期限，**微秒**，`-1` 不限；与 `timeout`（只管 HTTP 信令）相互独立 |
| `rtcp_nack` | 1 | answer 协商了 `nack` 且该路没有协商 RTX 时才发 NACK，`0` 关闭 |
| `rtcp_pli` | 1 | answer 协商了 `nack pli` 的视频路才发 PLI，`0` 关闭 |
| `rtcp_interval` | 1000000 | 周期 Receiver Report 的间隔，**微秒**，`0` 不发周期 RR（此时 NACK/PLI 仍会带一个空 RR 头作为复合包开头） |
| `media_timeout` | 5000000 | 握手后连续多久没有任何经认证的对端数据（RTP/RTCP/STUN）就判定连接已死并返回 `ETIMEDOUT`，**微秒**，`-1` 不限 |

## 已知限制 / 注意

- 信令阶段超时（服务端已建会话但响应没回来）时客户端拿不到 `Location`，无法 `DELETE`，只能等服务端自己回收。
- mpv 侧目前只认 `whep:`（`patches/mpv-v041/0003`）；`whep+http(s)://` 要在 mpv 里使用，需要额外的 mpv 补丁，见 `../mpv-v041/README.md`。
- mpv 的协议白名单：2026-10-02 用 whep flavor 的 libmpv（`tools/whep-flavor/build-linux.sh` 产物）loadfile `whep+http://127.0.0.1:8889/test/whep`，握手通过、`Opening done`，说明 `udp`/`dtls` 没被白名单挡；`srtp` 协议阶段 A 还没用到。
- 真实服务端（MediaMTX）的 answer 是 `setup:active`、无 RTX、无 `Link: ice-server`，我方当 DTLS server。
- 只在 Linux + OpenSSL 上编译验证过；Windows（SChannel）、Android（mbedtls）未编，且这两个后端还没有对端指纹接口，需各补一个 `ff_dtls_get_peer_fingerprint`，在此之前 whep 在这两个平台会因“取不到指纹”而拒绝连接（失败即关闭，设计如此）。
- DTLS 握手内部的等待由 `handshake_timeout` 打断，最坏超出期限约 100ms。
- 没有对“ICE 已通但服务端不发 DTLS”和“握手中途对端消失”做专门的故障注入（前者与无响应走同一超时分支，后者靠同一中断回调，均**未单独实测**）。

## 验证

```
# 1) 起信令 mock（仅标准库）
python3 tools/whep-flavor/mock_whep_signal.py --port 18090 --token tok123
# 2) 用带 whep 的 ffprobe 打开（-v verbose 能看到 offer / answer / 流 / DELETE）
ffprobe -v verbose -f whep -token tok123 -i whep+http://127.0.0.1:18090/x
```

mock 会校验 offer 的 `o=` 行 sess-id/version 为 ≤2^63-1 的纯十进制（旧版 mock 漏检，已补）。

真实服务端（MediaMTX v1.21.1，WSL `/root/w/whep-target`，见 `doc/notes/2026-10-02-whep-target-setup.md`）：
```
ffprobe -v verbose -f whep -i whep+http://127.0.0.1:8889/test/whep
```
2026-10-02 实测：201、相对 `Location` 被解析为绝对地址、answer 解析成功、建出 opus+h264 两条流、关闭时 DELETE 到达（再 DELETE 同一资源返回 404）；通过 mpv（libmpv smoke）打开 `whep+http://` 同样信令通过，随后因媒体桩 EOF 结束（`no audio or video data played`）。

### T1.3 阶段 A 验证（2026-10-02，Linux + OpenSSL 3.5.5，MediaMTX v1.21.1）

```
# 真实服务端：客户端打印 ICE/DTLS/指纹/材料；MediaMTX 日志出现 "peer connection established"
ffprobe -v verbose -f whep -i whep+http://127.0.0.1:8889/test/whep
# 篡改/不可达场景：起代理（转发到真实 MediaMTX，按路径前缀改写 answer）
python3 tools/whep-flavor/whep_tamper_proxy.py 18100
ffprobe -v verbose -handshake_timeout 3000000 -f whep -i whep+http://127.0.0.1:18100/<mode>/test/whep   # mode: ok|fp|dead|silent
```

实测结果（ASan 构建与普通构建均无报错/泄漏）：真实 MediaMTX 20/20 握手并导出材料，ICE 检查成功约 5–40ms、握手完成约 14–80ms；`fp`（指纹被改一个字节）握手后被拒绝，退出码非 0，随后 DELETE；`dead`（候选端口不可达）与 `silent`（候选只收不回）在 3s 期限时返回，实测 3.11s，随后 DELETE（200）。体积：whep flavor stripped libmpv.so 6,812,008 -> 6,816,136 字节（+4,128）。

mock 的错误场景路径：`/nf`(404) `/unauth`(401) `/nofp` `/badfp` `/sha1` `/nocand` `/bad` `/empty` `/slow`，正常变体 `/remap`（payload type 换成 97/99/100）。详见 `tools/whep-flavor/mock_whep_signal.py` 文件头。

### T1.3 阶段 B 验证（2026-10-02，Linux + OpenSSL 3.5.5，MediaMTX v1.21.1，推流 H264 baseline 640x360@25 + opus）

下列均为实测（未标"推断"）：

- `ffprobe -f whep -i whep+http://127.0.0.1:8889/test/whep -show_streams`：h264 Constrained Baseline level 30 **640x360**，opus 48000 Hz 2ch；耗时约 1.9s（含等 IDR）；普通与 ASan 构建一致。
- `ffmpeg -f whep -i ... -t 10 -f null -`：音频 505 包 / 482,880 采样（≈10.06s）、0 解码错误；视频 251 包 / 236 帧解码、0 解码错误（起播等 IDR，窗口内帧数 = 25fps × (10 - 等待)，等待 0.6–2s 不等，所以 10s 窗口里是 200–250 帧；40s 一次 1006 个视频包 ≈ 25.15fps、2005 个音频包）。auth_fail/late/lost 全 0。
- `-f framecrc`：视频 `#dimensions 0: 640x360`、h264；音频 opus 48000 stereo，extradata 19 字节。截图（ffmpeg `-frames:v 1`）与 mpv 抽帧（`vo=image` 的第 100 帧）都是 testsrc2 彩条 + 计时器。
- mpv（libmpv smoke，`vo=image` + `ao=null`）播放 12.8s：`time-pos` 每秒 +1.0（4.24→5.24→…→13.28），`estimated-frame-number` 106→332（25fps），vo/解码丢帧均为 0；12.8s 落盘 322 张 PNG；起播约 2–3.3s。mpv 提示的 `Could not set AVOption icy` 无害。
- **服务端被 `kill -9`**：ffmpeg 在 5.0s 后报 `No data from peer for 5.0s` / `Connection timed out` 并退出；mpv 5s 后结束（`END`），均不挂死。
- **发布端停流 4s**（`SIGSTOP` 推流进程）：连接不断，恢复后继续，25s 任务正常跑完。
- **不发 RR**：MediaMTX 在 40s 会话里没有因缺 RTCP 断流（见上）。
- **故障注入**（`whep_tamper_proxy.py` 的 `lossy` 模式：UDP 中继，对服务端到客户端的 RTP 注入 2% 丢包 / 2% 相邻交换 / 1% 重复 / 1% 翻转载荷字节，种子固定）：30s 会话中继共处理 3478 个 RTP，丢 75、坏 35、重复 29、交换 71；客户端 `auth_fail` 合计 35、`late/dup` 29（与注入的损坏数、重复数一一对应）、`lost` 109（≈ 丢 75 + 坏 35），交换的包被重排队列救回没有算丢；解码 0 错误，视频丢弃 35 个不完整帧（另有 82 帧因首个 IDR 被损坏而等下一个 IDR，属随机）。ASan（含 LeakSanitizer）跑同样场景 20s×3 次与干净场景 12s、ffprobe，**无任何报告**。
- 体积：whep flavor stripped `libmpv.so` 6,816,136（阶段 A）-> **6,824,328（+8,192 字节）**；`whep.o` 的 text 14,939 -> 20,743（+5,804）。目标 ≤ +20KB，达成。

`whep_tamper_proxy.py` 新增 `lossy` 模式：`python3 tools/whep-flavor/whep_tamper_proxy.py 18100`，客户端 URL `whep+http://127.0.0.1:18100/lossy/test/whep`；环境变量 `LOSS/SWAP/DUP/CORRUPT` 调比例（百分数），每 5s 打印中继计数。

### whep+https 与丢包基线（2026-10-02，Linux + OpenSSL 3.5.5，MediaMTX v1.21.1 `webrtcEncryption: yes`，自签证书）

完整命令、日志与表格见 `doc/notes/2026-10-02-whep-https-and-loss-baseline.md`。以下均为实测（标"推断"的除外）：

- **https 信令**（`whep+https://127.0.0.1:18889/test/whep`，`ffmpeg -t 10 -f null -`）：`tls_verify=0` 成功，音频 505 包 / 482,880 采样、0 解码错误、auth_fail/late/lost 全 0；`tls_verify=1` 无 `ca_file` 干净失败（`certificate verify failed`，退出码 251）；`tls_verify=1` + `ca_file=自签证书` 成功；换成无关证书当 CA 同样干净失败。普通与 ASan 构建一致，ASan 无报告。
- **https 同源/降级**：`whep_origin_regress.py --https --cert C --key K` 6 个场景（same / host / redir / downgrade / dg_other / redir_http）全 PASS（普通与 ASan）：evil 与明文监听器的 TCP 连接数均为 0，降级时 POST 之后不再建任何连接，token 未出现在任何明文字节里；http 模式三场景回归 3/3 PASS。
- **无重传丢包基线（NACK/PLI 未实现）**，`whep_loss_baseline.py`，30s×每档 3 次（0% 对照 1 次），纯丢包，种子记录在 result.json：

  | 丢包 | 客户端 `lost`（视频/音频） | 丢弃不完整帧 | 解码器 "decode errors" | `corrupt`/`concealing` 行 | 视频 pts 停顿累计 | 音频 20ms 洞数 / 累计 | 花屏累计（推断） | 花屏单次平均 / 最长（推断） |
  |---|---|---|---|---|---|---|---|---|
  | 0.5% | 10.7 / 7.7 | 7.7 | 0 | 3.0 / 3.0 | 0.28s | 7.3 / 0.15s | 9.3s | 1.28s / 4.0s |
  | 2% | 41.7 / 30.0 | 22.7 | 0 | 18.0 / 18.7 | 0.83s | 29 / 0.59s | 21.5s | 1.85s / 5.5s |
  | 5% | 104.3 / 75.0 | 57.7 | 0 | 35.7 / 39.0 | 2.29s | 70 / 1.44s | 27.8s | 4.04s / 12.0s |

  - `lost` 与注入数逐次相等；混合故障（2% 丢 / 2% 交换 / 1% 重复 / 1% 翻转）下 `auth_fail` = 注入的翻转数（视频 27/19/22、音频 16/13/20 全等），`late/dup` = 注入的重复数（仅音频一次多 1），交换的包全被重排救回；`lost` = 丢 + 翻转（仅音频一次差 1，结束瞬间）。
  - **发现**：ffmpeg 的 "decode errors" 全程为 0，损伤只在 `corrupt decoded frame` / `concealing` 日志行里；`dropped_frames` 低估损伤——缺口落在帧**开头**且后续为完整 NAL 时该帧不被标 `au_bad`，带缺失地进了解码器（有丢包帧 − `dropped_frames` ≈ `concealing` 行数：3.0/3.0、18.7/18.7、41.7/39.0）。T1.5 引入重传时应一并修这个口径。
  - 音频不连续但每个洞只有 20ms（无 PLC、不补静音，最长连续缺 2 包）；IDR 约 10 个包，5% 丢包时 IDR 带损约 8/16，花屏要多拖一个 GOP（2s）。花屏窗口是按 trace 的帧大小识别 IDR 推算的，不是像素级实测。
  - ASan（5% 与 mix 各 2 次×20s）无报告。
  - 局限：回环上的随机独立丢包，无突发/延迟/抖动；每档 3 次波动大；仅 MediaMTX 一种服务端。

## RTCP 反馈（T1.5，0009）

只改 `whep.c`，不引第三方库。全部 RTCP 经 `ff_srtp_encrypt` 做 SRTCP（带 E 位与 SRTCP 索引、HMAC-SHA1-80 标签）从媒体 UDP socket 发出。**发送用 DTLS-SRTP 材料里的 server 写密钥**（我方是 DTLS server；接收解密用的是 client 写密钥），发送上下文独立于各路接收上下文。

- **本端 SSRC**：随机 32 位非零数，RTCP 里作 sender SSRC。recvonly 的 offer 不需要声明 `a=ssrc`（RFC 8829），所以 offer 没动；RTSP 那套 `ssrc+1` 的做法不适用，没有沿用。
- **复合包结构**：RR（到点带 report block，否则空 RR 头）+ 每路 NACK + 每路 PLI。没有 SDES CNAME（pion/MediaMTX 实测接受；严格的 RFC 3550 对端可能挑剔，未验证）。
- **RR**：每 `rtcp_interval`（默认 1s）一次；每个已见到 SSRC 的路一个 report block：fraction lost（本周期）、cumulative lost（24 位有符号，含重传补回）、extended highest seq（含回绕）、RFC 3550 A.8 的 jitter，LSR/DLSR 取自最近收到的 SR（没收到过则 0）。没收到过 SR 时 LSR/DLSR 为 0（SR 在本测试里是否到达未单独统计）。
- **NACK（RFC 4585 §6.2.1）**：重排队列旁边加了 32 项缺口表（序号、重试次数、首次发现时间、上次 NACK 时间）。新高序号到达时把中间空出的序号登记为缺口；乱序/重传补上就划掉。首次发现 10ms 后发第一次 NACK，之后每 40ms 重发，最多 3 次，用尽则放弃并降级为 PLI。多个序号打包成多个 FCI（PID + BLP，升序，与 PID 差 1–16 并入同一 FCI，RTCP length = 2 + FCI 数）；打包函数对 2 万组随机丢包（含回绕）做过"打包再展开"一致性检查，18 个连续序号得 `(2,0xFFFF)+(19,0)`。NACK 的计时是自己的（与 libavformat rtpdec 的 `MIN_FEEDBACK_INTERVAL` 无关）。开 NACK 时重排缺口的最长等待由 80ms 增至 200ms（容纳 3 次重试），所以最坏情况下恢复期间会多 ≤200ms 的缓冲延迟。
- **重传识别**：补上缺口的包（同序号、原 SSRC/PT）按"重传恢复"计数，不算 `late/dup`；缺口已被放弃后才到的重传单独计 `rtx_late`，也不算 `late/dup`。缺口表满（突发丢包超过 32）时不 NACK，等重排窗口放弃后走 PLI。
- **PLI（§6.3.1）**：视频路在第一个媒体包收到后就发（需要知道对端 SSRC，所以不能更早），直到见到第一个关键帧为止每秒重试；之后任何**不可恢复**的视频丢包（NACK 重试用尽 / 重排窗口放弃 / 跳变）再发。全程限速 ≥1s。
- **协商**：只有 answer 声明了 `nack` / `nack pli` 才发。**RTX 未实现**：answer 里该路协商了 RTX（`rtx_pt >= 0`）时我们不发 NACK（对端会用 RTX 包重传，而我们还不会还原 OSN；RTX 留 TODO，需要在 `whep_rx_datagram` 里按 `apt` 映射并还原原序号）。MediaMTX 的 answer 实测无 RTX，重传使用原 SSRC/PT/序号，正是本补丁处理的路径。
- **音频**：MediaMTX 的 answer 里 Opus 没有 `nack`，音频路不发 NACK（音频丢包行为同基线）。
- 新增 verbose 日志：`First RTP packet (...) at Xms since open`、`First video key frame out at Xms since open (pli_sent=N)`、每路 `RTCP video|audio: nack=… nack_seqs_sent=… nack_msgs=… nack_giveup=… rtx_recovered=… rtx_late=… pli_sent=… rr_sent=…`（`nack_seqs_sent` 按序号计，重发也各算一次）。

### T1.5 验证（2026-10-02，Linux + OpenSSL 3.5.5，MediaMTX v1.21.1，回环）

命令同上节基线（`whep_loss_baseline.py`，新增 `--ffopts` 传 `-rtcp_nack 0 -rtcp_pli 0` 等输入选项，汇总表多一张 RTCP 计数表）；30s × 每档 3 次（0% 为 1 次），种子与基线相同，客户端日志里的真实计数器，均值。丢包由 `whep_tamper_proxy.py lossy` 只对服务端→客户端的 RTP 注入（NACK 和重传包都经过它，重传包同样可能被丢）。

| 丢包 | NACK 关：视频 `lost` / 丢弃不完整帧 / `concealing` 行 / 视频 pts 空洞 | NACK 开：同四项 | NACK 序号数（含重发）| 重传恢复 | 放弃 |
|---|---|---|---|---|---|
| 0.5% | 11.3 / 7.3 / 4.0 / 7.0（0.28s） | **0 / 0 / 0 / 0** | 10.0 | 10.0 | 0 |
| 2% | 40.7 / 23.0 / 16.3 / 20.0（0.85s） | **0 / 0 / 0 / 0** | 42.0 | 42.0 | 0 |
| 5% | 117.0 / 64.0 / 40.3 / 45.7（2.00s） | **0 / 0 / 0 / 0** | 111.3 | 108.0 | 0 |
| mix（2% 丢 + 2% 交换 + 1% 重复 + 1% 翻转） | 54.7 / 31.0 / 22.7 / 28.7（1.19s） | **0 / 0 / 0 / 0** | 57.7 | 57.0 | 0 |

- **③ `rtcp_nack=0 rtcp_pli=0` 与基线一致**：上表左列与 0.5% 节的无重传基线同量级（如 2%：基线 `lost` 41.7、丢弃 22.7、`concealing` 18.7；本次 40.7 / 23.0 / 16.3），`late/dup`、`auth_fail` 对应关系不变。
- **late/dup 未被误计**：mix 档 NACK 开 `late/dup` 34.3，NACK 关 34.0（注入的重复包数），交换的包没有计入。5% 档 `rtx_late`=0（3 次重试内都赶上了）。
- 音频不受影响（没协商 nack）：5% 档音频 `lost` 与基线同量级（75–83）。
- 解码器侧 `corrupt decoded frame` / `concealing` 行 NACK 开全为 0，视频 pts 无空洞；**基线的"花屏窗口"推断模型按 trace 里的丢包算，不适用于有重传的 trace（会把已恢复的丢包也算进去），所以 NACK 开的汇总表里那几列忽略，以客户端计数与解码器日志为准**。
- ④ **服务端收到 RR/NACK 的证据**：MediaMTX 会话 API（`/v3/webrtcsessions/list`）的 `inboundRTCPPackets` / `rtcpPacketsReceived` 在 5s 的直连会话里为 14（SRTCP 解密失败的包 pion 会丢弃，计数增长说明密钥/索引/标签正确；**该计数的具体构成未拆**）。NACK 被响应的**实测**证据：中继 trace 里视频序号"重复出现"的次数（即服务端重发，包含被中继再次丢弃的）与客户端发出的 NACK 序号数在 12 次丢包运行里**逐次相等**（如 5% 档 110/110、119/119、105/105；mix 档含中继自己注入的重复，仍 63/63、48/48、62/62）。
- ⑤ ASan：主路径 0% 2 次（20s）+ 5% 2 次 + mix 2 次（各 20s），退出码 0，日志无 `Sanitizer` / `ERROR` / leak。
- ① **PLI 起播（负面结果）**：实测起播仍要等下一个 IDR；**推断**原因是 MediaMTX 不把 PLI 转给 RTSP 推流源、也不自己生成 IDR（未读其源码确认）。同一构建 PLI 开/关各 14 次（随机错开推流相位）"首个 RTP 包 → 首个关键帧"均值 **724ms vs 638ms**（无改善，差异在相位噪声内）；仅开 PLI 不开 NACK 的 5% 档：PLI 发 31.7 次/30s（限速生效）、花屏累计 25.7s（推断）与基线 27.8s 无差别。**PLI 的包格式与 SRTCP 通路由 MediaMTX 接受，但它对 PLI 无动作，因此"缩短起播等 IDR"的收益没有被验证**，需换一个会响应 PLI 的服务端（如 SRS、浏览器 SFU）才能测。
- 体积：whep flavor stripped `libmpv.so` 6,824,328（0008）-> **6,832,520（+8,192 字节）**，达到目标上限（≤ +8KB）；`whep.o` text 21,352 -> 25,056（+3,704），data +192。.so 的 +8,192 是页对齐的一档，真实代码增量约 3.9KB。
- **未做 / 限制**：RTX（见上）；TWCC；SDES CNAME；RR 的 DLSR 依赖收到过 SR；只测回环 + 随机独立丢包（无突发、无 RTT），重试间隔 40ms / 等待 200ms 是自拟起点，真实网络要按 RTT 校准；Windows/Android 后端没有重测 RTCP（0007/0008 的 DTLS 路径相同，RTCP 走同一个 `ff_srtp_encrypt`）。

## 升级 ffmpeg 版本时

0001 的 `configure`/`allformats.c`/`Makefile` hunk 对上下文敏感；0002 依赖 `http.c` 的 `process_line` 与 `HTTPContext` 布局；0003 用到的内部 API：`ff_ssl_gen_key_cert`、`ff_http_get_new_location`、`ff_data_to_hex`、`FF_INFMT_FLAG_INIT_CLEANUP`，换版本要逐个确认；0005 另用到 `ff_srtp_set_crypto`/`ff_srtp_decrypt`/`ff_srtp_free`（`srtp.h`）、`ff_packet_list_put/get/free`（`packet_internal.h`）、`ff_alloc_extradata`。

## mbedTLS / SChannel 后端（0007 / 0008）

两个后端都补齐了 whep 需要的三件事：`ff_dtls_get_peer_fingerprint`（SHA-256 指纹，格式 `AA:BB:..` 大写）、DTLS server 向对端要证书且**不做链校验**（信任只来自 SDP 指纹比对）、握手可被 `interrupt_callback` 打断（非阻塞读 + 最长 100ms 的 poll）。

### mbedTLS（Android，0007）——已端到端实测

- **mbedtls 宏集**（3.6.7，在默认 `mbedtls_config.h` 上）：`MBEDTLS_X509_CRT_PARSE_C`、`MBEDTLS_SSL_KEEP_PEER_CERTIFICATE`（取对端证书做指纹）、`MBEDTLS_SSL_DTLS_SRTP`（**默认关闭，必须手开**，否则 SRTP 密钥导出不可用）、`MBEDTLS_TIMING_C`（DTLS 重传计时器）。
- **configure**：mbedtls 3.x 是 Apache-2.0，ffmpeg 要求同时 `--enable-version3`；静态链接要 `--pkg-config-flags=--static`，否则只链 `-lmbedtls`、缺 x509/crypto。
- **实测**（Linux x86_64，非 OpenSSL，对真实 MediaMTX）：`ffprobe` 取到 h264 640x360 + opus 48k；`ffmpeg -t 10 -f null -` 解码 250 帧、exit 0、日志无 error/corrupt。DTLS 握手 + 指纹校验 + 60 字节 SRTP 材料导出约 56ms。
- **补丁里改掉的坑**：SRTP 密钥导出回调只认 TLS1.2 master secret 类型；`ffurl_read` 返回 EAGAIN 要映射成 `MBEDTLS_ERR_SSL_WANT_READ`（原先被当成缓冲区过小）。
- **未验证**：丢包重传（没造丢包测过）；Android 真机未跑。

### SChannel（Windows，0008）——Win10 19045 真机握手已实测

- 用 `SECPKG_ATTR_REMOTE_CERT_CONTEXT` 取对端证书；server 侧加 `ASC_REQ_MUTUAL_AUTH` 触发 CertificateRequest，凭据本来就是 `SCH_CRED_NO_SYSTEM_MAPPER | SCH_CRED_MANUAL_CRED_VALIDATION`（不做系统映射与链校验）。
- 通过 `SECBUFFER_SRTP_PROTECTION_PROFILES` 提交 `SRTP_AES128_CM_HMAC_SHA1_80`。**profile 常量必须写 `0x0100`**（SChannel 按网络字节序读，小端机上 `0x0001` 会让握手失败，实测），补丁注释里已写明。
- **shutdown 修复**：`tls_shutdown_client` 在 server 侧不能死循环，改为最多 8 次，`CONTINUE_NEEDED` 只在 client 侧继续（gdb 栈证实）。
- **实测**：Win10 19045 上作 DTLS server 对真实 MediaMTX（pion 作 client）握手完成，约 170–190ms。体积对照（静态链接产物）：SChannel 9,302,528 vs OpenSSL 14,862,336 字节。详见 `doc/notes/2026-10-02-windows-schannel-whep-verify.md`。
- **局限**：
  - 仅在 Win10 19045 上验证；其他 Windows 版本未测。
  - 只提交了一个 profile，GCM 系列（如 `0x0700`）未测。
  - 握手循环里没有主动驱动服务端重传，丢包要靠对端重发。

### 0009：mbedtls SRTP profile 列表改 static（Android 真机暴露）

`tls_open()` 里 `profiles[]` 是栈数组，而 `mbedtls_ssl_conf_dtls_srtp_protection_profiles()` 只存指针不拷贝，握手在之后进行，读到悬空指针。Linux（mbedtls 3.6.7）碰巧没事；Android arm64（mbedtls 3.4.0）ServerHello 缺 `use_srtp` 扩展，MediaMTX 回 alert 71（insufficient_security）。改成 `static const` 后真机握手通过。
