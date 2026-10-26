# WHEP 联调目标（真实服务端）搭建记录

日期：2026-10-02。目的：T1.3（ICE + DTLS-SRTP + SRTP）联调用的真实 WHEP 服务端，不是 mock。
目标放在 WSL `/root/w/whep-target`，**不入库**。

## 环境结论（实测）

- WSL 无 docker（`docker: command not found`），改用 MediaMTX 单文件二进制。
- MediaMTX **v1.21.1** linux_amd64（GitHub release，curl 直连可下，27MB 压缩包，未用 aria2）。
- 推流：WSL 自带 ffmpeg（libx264 + libopus），RTSP/TCP 推到 `rtsp://127.0.0.1:8554/test`。

## 端口

| 端口 | 用途 |
|---|---|
| 8889/tcp | WHEP 信令（HTTP） |
| 8189/udp | ICE / 媒体（所有会话共用一个 UDP 端口） |
| 8554/tcp | RTSP（推流入口） |
| 其余 | 8888 HLS、1935 RTMP、8890 SRT、8892/8893 MoQ，用不到 |

## 使用方法

```
# WSL 内
/root/w/whep-target/start.sh    # 起 mediamtx + ffmpeg 推流（testsrc2 640x360@25 + sine 440Hz，
                                # h264 baseline 400k + opus 32k，-re 实时无限循环）
/root/w/whep-target/stop.sh
# 日志：mtx.log、push.log；replay.py 是用真实 answer 回放的最小信令服务（端口 18095，仅验解析用）

# 信令探测（含 whep flavor 的 ffprobe，非 asan 版）
/root/w/t11/bprobe/ffprobe -v verbose -f whep -i whep+http://127.0.0.1:8889/test/whep
```

WSL2 到 Windows 侧端口转发未验证；T1.3 的客户端在 WSL 内跑即可用 127.0.0.1。
answer 里的候选含 `172.21.26.245`（WSL eth0）与 `127.0.0.1`，均为 host 候选。

## 真实 answer（201 Created，脱敏：ufrag/pwd/指纹/ssrc 为一次性值）

响应头：`Location: /test/whep/<uuid>`（相对路径）、`Accept-Patch: application/trickle-ice-sdpfrag`、
`ETag: *`、`ID: <uuid>`。**没有 `Link: rel=ice-server`**（未配置 STUN/TURN）。

```
v=0
o=- 530954905440926212 1790928303 IN IP4 0.0.0.0
s=-
t=0 0
a=msid-semantic:WMS *
a=fingerprint:sha-256 <redacted>
a=group:BUNDLE 0 1
m=audio 9 UDP/TLS/RTP/SAVPF 111
c=IN IP4 0.0.0.0
a=setup:active
a=mid:0
a=ice-ufrag:<redacted>
a=ice-pwd:<redacted>
a=rtcp-mux
a=rtcp-rsize
a=rtpmap:111 opus/48000/2
a=fmtp:111 minptime=10;useinbandfec=1
a=ssrc:<n> cname:mediamtx   (另有 msid/mslabel/label)
a=msid:mediamtx audio
a=sendonly
a=candidate:2878742611 1 udp 2130706431 127.0.0.1 8189 typ host ufrag <ufrag>
a=candidate:2878742611 2 udp 2130706431 127.0.0.1 8189 typ host ufrag <ufrag>
a=candidate:2827470259 1 udp 2130706431 172.21.26.245 8189 typ host ufrag <ufrag>
a=candidate:2827470259 2 udp 2130706431 172.21.26.245 8189 typ host ufrag <ufrag>
a=end-of-candidates
m=video 9 UDP/TLS/RTP/SAVPF 102
c=IN IP4 0.0.0.0
（同样的 setup/mid:1/ice/rtcp-mux/rtcp-rsize）
a=rtpmap:102 H264/90000
a=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f
a=rtcp-fb:102 nack
a=rtcp-fb:102 nack pli
a=ssrc:<n> cname:mediamtx ...
a=msid:mediamtx video
a=sendonly
```

## 对 T1.3 有影响的关键属性

- **`a=setup:active`**：服务端是 DTLS **client**，我们（offer 是 actpass）必须当 DTLS **server**，等对端 ClientHello。
- **不是 ice-lite**：服务端是完整 ICE agent（pion），会主动发 STUN 连通性检查，我们要回应并发自己的检查。ICE 角色：offerer 为 controlling。
- 候选：全是 host/udp，两个 component（1 和 2，**虽然 rtcp-mux**，component 2 候选应忽略），所有会话共用 8189/udp；候选行末带非标准 `ufrag <x>` 扩展（解析要容忍）。
- **rtcp-mux + rtcp-rsize**：RTP/RTCP 同端口。BUNDLE 0 1：音视频共用一条传输。
- **无 RTX**（offer 里的 112/113/114 被丢弃，只留 102）；有 `nack` 与 `nack pli`；**没有 transport-cc / REMB / goog-remb**。T1.5 的 NACK 重传在该服务端上只能靠 nack 回应（无 RTX 则是原 PT 重发，需实测服务端是否真重发）。
- 只选了 offer 的第一档 H264（42e01f，packetization-mode=1），opus 111 `useinbandfec=1`。
- 只有一个 sha-256 指纹（session 级）。

## 对 T1.2 的反馈（实测）

1. **缺陷（真实服务端暴露，仓库未改）：offer 的 `o=` 行 session id 用了 16 位十六进制**
   （`o=FFmpeg 8ccad5cda3211c80 2 IN IP4 127.0.0.1`）。RFC 4566 要求 sess-id 为十进制数字串，
   MediaMTX（pion）直接返回 `400 {"error":"failed to unmarshal SDP: sdp: syntax error at pos 15: \"c\""}`。
   定位方法：把 id 换成纯数字，同一份 offer 立刻得到 201。需要改 whep.c 生成 offer 的地方（建议 `%"PRIu64"` 十进制，且 ≤ 2^63-1 以防别的实现按有符号解析）。mock 不会校验所以没暴露。
2. 解析 answer：把真实 answer 用 `replay.py` 回放给 whep.c，**解析通过**：
   `ufrag=… pwd=32B fp=sha-256 setup=active ice_lite=0 cand=127.0.0.1:8189 streams=2`，
   Stream0 opus/48000 rtx=-1 nack=0 pli=0，Stream1 H264 pt=102 nack=1 pli=1；候选的 `ufrag` 尾巴、component 2、
   `a=ssrc` 多行均被容忍；关闭时发 DELETE，通过。
3. 注意：whep.c 现在拿到的是**回放**的 answer（因为真实服务端被 bug 1 挡在 offer 阶段），所以"对真实服务端端到端信令"要等 bug 1 修了才算过；answer 解析本身用的是真实文本。
4. `Location` 为相对路径，回放服务验证了 http 层能解析成绝对地址并 DELETE 成功（真实 MediaMTX 的 DELETE 未测）。
