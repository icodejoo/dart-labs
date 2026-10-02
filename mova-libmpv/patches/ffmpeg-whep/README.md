# ffmpeg n9.0.2 WHEP 补丁序列

只用于 `*-whep` flavor（ffmpeg n9.0.2 + mpv v0.41.0），默认 flavor 不吃这些补丁、行为不变。
补丁基于 ffmpeg 官方 `n9.0.2`（`946fcce`），用 `git apply` 按编号依次打，`build-linux.sh` 在 `WITH_WHEP=1` 时自动执行。

| 序号 | 文件 | 作用 |
|---|---|---|
| 0001 | `0001-avformat-register-whep-demuxer-off-by-default.patch` | `allformats.c`/`Makefile`/`configure` 注册 `whep` demuxer；configure 里 `disable whep_demuxer` 使其**默认关闭**，只有 `--enable-demuxer=whep` 才开；`whep_demuxer_select="dtls_protocol http_protocol srtp"` |
| 0002 | `0002-avformat-http-expose-Link-response-headers.patch` | `http.c` 记录响应里的 `Link` 头，新增内部函数 `ff_http_get_link_headers()`；WHEP 靠它读 `rel="ice-server"`（n9.0.2 的 http 层不暴露任意响应头） |
| 0003 | `0003-avformat-whep-add-WHEP-demuxer-signalling-and-SDP-T1.patch` | 新增 `libavformat/whep.c`：T1.2 的信令与 SDP（见下） |
| 0004 | `0004-avformat-whep-ICE-DTLS-SRTP-key-export-T1.3-stage-A.patch` | T1.3 阶段 A：`whep.c` 加 ICE 连通性检查 + DTLS(server) 握手 + 指纹校验 + SRTP 密钥导出；`tls_openssl.c`/`tls.h` 加 `ff_dtls_get_peer_fingerprint()`、DTLS server 请求客户端证书、握手循环响应中断回调 |

编号说明：0003 依赖 0002 的 `ff_http_get_link_headers`，所以 http 补丁排在 whep.c 前面。

## whep.c 当前能力（T1.2）

- URL：`whep+http://`、`whep+https://`、`whep://`（`whep://` 默认走 **https**，明文 http 必须显式写 `whep+http://`）。
- offer：`o=` 行 sess-id 为 `AV_RB64(随机)&INT64_MAX` 的**十进制**（RFC 4566；十六进制会被 MediaMTX/pion 以 400 拒绝）；recvonly、opus + H264（三档 profile，各带 RTX）、`rtcp-fb nack` / `nack pli`、`setup:actpass`、`sha-256` 指纹、随机 ice-ufrag/pwd。payload type 只是提议，**以 answer 为准**。
- 信令：`POST`（`Content-Type: application/sdp`，可选 `Authorization: Bearer`），读 201 的 `Location`（相对地址会被 http 层解析成绝对地址）、`Link: rel="ice-server"`；关闭时 `DELETE`。read_header 失败（例如 answer 无指纹）也会 `DELETE` 已建立的会话（`FF_INFMT_FLAG_INIT_CLEANUP`）。
- answer 解析：自写最小子集（不复用 `rtsp.c` 的 `ff_sdp_parse`）。必填 ice-ufrag/pwd、格式合法的 sha-256 指纹、`a=setup`、一个 UDP 候选、至少一条 opus/H264。缺指纹、算法不是 sha-256、格式不对一律拒绝。
- 建流：按 answer 的 m= 行顺序挑 codec，建 H264（取 profile/level）与 Opus（48k）两条 AVStream。
- **未实现**：SRTP 解密与 STUN 保活（T1.3 阶段 B）、RTP 解包（T1.4）、RTCP 反馈（T1.5）。`read_packet` 当前仍是桩，直接返回 `AVERROR_EOF`。

## 媒体通路（T1.3 阶段 A，0004）

流程：POST 得 answer -> 单 UDP socket `connect` 到 answer 首个 host 候选 -> ICE -> DTLS -> 导出 SRTP 材料。

- **ICE**（自写最小 STUN，沿用 `whip.c` 的报文布局思路，HMAC/CRC 用 ffmpeg 自带，无第三方库）：我方 controlling、带 USE-CANDIDATE（激进提名）；请求每 200ms 重发（同一事务 ID），USERNAME=`对端ufrag:本端ufrag`，MESSAGE-INTEGRITY 用对端 pwd，带 FINGERPRINT。服务端发来的检查请求会校验 USERNAME 与 MESSAGE-INTEGRITY（本端 pwd）后再回成功响应（含 XOR-MAPPED-ADDRESS，来自已 connect socket 的对端地址）；收到的成功响应要校验事务 ID 与 HMAC（对端 pwd）。单 socket、单 host 候选，不做 trickle/TURN/多候选。
- **探测 DTLS 不丢包**：ICE 循环用 `recv(MSG_PEEK)` 看到 ClientHello 就停，不消费它，再把 socket 交给 dtls 协议（whip 的做法会吞掉第一个 ClientHello，要等对端重传）。
- **DTLS**：answer 为 `setup:active` 时我方是 DTLS server（`listen=1`、`external_sock=1`、`use_srtp=1`、`mtu=1200`）。`setup` 不是 `active` 目前返回 `AVERROR_PATCHWELCOME`。握手后**必须**取到对端证书，其 SHA-256 与 answer 的 `a=fingerprint` 不一致即 `AVERROR(EACCES)` 拒绝；非 OpenSSL 后端（还没有 `ff_dtls_get_peer_fingerprint`）一律拒绝，不放行未验证的对端。
- **SRTP 材料**：`ff_dtls_export_materials` 导出 60 字节（`client_key|server_key|client_salt|server_salt`，profile `SRTP_AES128_CM_HMAC_SHA1_80`）存进 `WHEPContext.srtp_materials`，关闭时清零；日志只打长度与 profile，不打密钥。
- **tls 层改动**（影响所有 DTLS-SRTP server 用户，包括 whip 作 passive 时）：DTLS server 现在会发 CertificateRequest（WebRTC 双向证书要求；用接受任意证书的校验回调，信任只来自指纹比对）；`dtls_handshake` 的轮询循环检查 `interrupt_callback` 且单次等待不超过 100ms，使 `handshake_timeout` 能打断握手。
- **超时/错误**：整个 ICE + DTLS 受 `handshake_timeout` 约束；任何失败 `read_header` 返回负值，`read_close` 仍会 DELETE 已建立的会话。

### 阶段 B 必须接着做（未做）

握手结束后 `whep_media_read` 仍是桩，ICE 保活没人应答：MediaMTX（pion）的 ICE 检查请求在握手之后还会周期性到来（**推断**，阶段 A 的探测会话只存活几十毫秒，未观察到），阶段 B 的读循环必须继续应答 STUN（`whep_stun_verify` + `whep_ice_build_response` 已可复用），否则服务端 consent 可能超时断开。另外 SRTP 解密、重放窗口、RTP/RTCP 分流都在阶段 B。

## AVOption

| 名字 | 默认 | 说明 |
|---|---|---|
| `token` | 无 | Bearer token（含 CR/LF 会被拒绝） |
| `timeout` | 10000000 | 信令 HTTP 的 I/O 超时，**微秒**（与 mpv 注入、rtsp 的 `timeout` 约定一致，mpv 会注入 `60000000`），`-1` 不限，上限 `INT_MAX` |
| `tls_verify` | 0 | https 是否校验服务端证书（透传给 tls 层；mpv 会自动注入 `tls_verify`） |
| `ca_file` | 无 | `tls_verify=1` 时用的 CA 文件 |
| `user_agent` | 无 | 信令请求的 User-Agent（mpv 会自动注入） |
| `handshake_timeout` | 10000000 | ICE + DTLS 握手总期限，**微秒**，`-1` 不限；与 `timeout`（只管 HTTP 信令）相互独立 |

## 已知限制 / 注意

- 信令阶段超时（服务端已建会话但响应没回来）时客户端拿不到 `Location`，无法 `DELETE`，只能等服务端自己回收。
- mpv 侧目前只认 `whep:`（`patches/mpv-v041/0003`）；`whep+http(s)://` 要在 mpv 里使用，需要额外的 mpv 补丁，见 `../mpv-v041/README.md`。
- mpv 的协议白名单：2026-10-02 用 whep flavor 的 libmpv（`tools/whep-flavor/build-linux.sh` 产物）loadfile `whep+http://127.0.0.1:8889/test/whep`，握手通过、`Opening done`，说明 `udp`/`dtls` 没被白名单挡；`srtp` 协议阶段 A 还没用到。
- 真实服务端（MediaMTX）仅验证了信令；它的 answer 是 `setup:active`、无 RTX、无 `Link: ice-server`，T1.3 需据此实现（我方当 DTLS server）。ffprobe 因媒体是桩会报 `Could not find codec parameters for stream 1`（无 SPS/分辨率），属预期。
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

## 升级 ffmpeg 版本时

0001 的 `configure`/`allformats.c`/`Makefile` hunk 对上下文敏感；0002 依赖 `http.c` 的 `process_line` 与 `HTTPContext` 布局；0003 用到的内部 API：`ff_ssl_gen_key_cert`、`ff_http_get_new_location`、`ff_data_to_hex`、`FF_INFMT_FLAG_INIT_CLEANUP`，换版本要逐个确认。
