# ffmpeg n9.0.2 WHEP 补丁序列

只用于 `*-whep` flavor（ffmpeg n9.0.2 + mpv v0.41.0），默认 flavor 不吃这些补丁、行为不变。
补丁基于 ffmpeg 官方 `n9.0.2`（`946fcce`），用 `git apply` 按编号依次打，`build-linux.sh` 在 `WITH_WHEP=1` 时自动执行。

| 序号 | 文件 | 作用 |
|---|---|---|
| 0001 | `0001-avformat-register-whep-demuxer-off-by-default.patch` | `allformats.c`/`Makefile`/`configure` 注册 `whep` demuxer；configure 里 `disable whep_demuxer` 使其**默认关闭**，只有 `--enable-demuxer=whep` 才开；`whep_demuxer_select="dtls_protocol http_protocol srtp"` |
| 0002 | `0002-avformat-http-expose-Link-response-headers.patch` | `http.c` 记录响应里的 `Link` 头，新增内部函数 `ff_http_get_link_headers()`；WHEP 靠它读 `rel="ice-server"`（n9.0.2 的 http 层不暴露任意响应头） |
| 0003 | `0003-avformat-whep-add-WHEP-demuxer-signalling-and-SDP-T1.patch` | 新增 `libavformat/whep.c`：T1.2 的信令与 SDP（见下） |

编号说明：0003 依赖 0002 的 `ff_http_get_link_headers`，所以 http 补丁排在 whep.c 前面。

## whep.c 当前能力（T1.2）

- URL：`whep+http://`、`whep+https://`、`whep://`（`whep://` 默认走 **https**，明文 http 必须显式写 `whep+http://`）。
- offer：recvonly、opus + H264（三档 profile，各带 RTX）、`rtcp-fb nack` / `nack pli`、`setup:actpass`、`sha-256` 指纹、随机 ice-ufrag/pwd。payload type 只是提议，**以 answer 为准**。
- 信令：`POST`（`Content-Type: application/sdp`，可选 `Authorization: Bearer`），读 201 的 `Location`（相对地址会被 http 层解析成绝对地址）、`Link: rel="ice-server"`；关闭时 `DELETE`。read_header 失败（例如 answer 无指纹）也会 `DELETE` 已建立的会话（`FF_INFMT_FLAG_INIT_CLEANUP`）。
- answer 解析：自写最小子集（不复用 `rtsp.c` 的 `ff_sdp_parse`）。必填 ice-ufrag/pwd、格式合法的 sha-256 指纹、`a=setup`、一个 UDP 候选、至少一条 opus/H264。缺指纹、算法不是 sha-256、格式不对一律拒绝。
- 建流：按 answer 的 m= 行顺序挑 codec，建 H264（取 profile/level）与 Opus（48k）两条 AVStream。
- **未实现**：ICE/DTLS/SRTP（T1.3）、RTP 解包（T1.4）、RTCP 反馈（T1.5）。`read_packet` 当前是桩，直接返回 `AVERROR_EOF`；代码里 `whep_media_open/read/close` 三个函数是给 T1.3 留的接口。

## AVOption

| 名字 | 默认 | 说明 |
|---|---|---|
| `token` | 无 | Bearer token（含 CR/LF 会被拒绝） |
| `timeout` | 10000000 | 信令 HTTP 的 I/O 超时，**微秒**（与 mpv 注入、rtsp 的 `timeout` 约定一致，mpv 会注入 `60000000`），`-1` 不限，上限 `INT_MAX` |
| `tls_verify` | 0 | https 是否校验服务端证书（透传给 tls 层；mpv 会自动注入 `tls_verify`） |
| `ca_file` | 无 | `tls_verify=1` 时用的 CA 文件 |
| `user_agent` | 无 | 信令请求的 User-Agent（mpv 会自动注入） |

## 已知限制 / 注意

- 信令阶段超时（服务端已建会话但响应没回来）时客户端拿不到 `Location`，无法 `DELETE`，只能等服务端自己回收。
- mpv 侧目前只认 `whep:`（`patches/mpv-v041/0003`）；`whep+http(s)://` 要在 mpv 里使用，需要额外的 mpv 补丁，见 `../mpv-v041/README.md`。
- T1.3 需要 mpv 的协议白名单放行 `udp`、`dtls`、`srtp`（`stream_lavf.c` 的 `get_safe_protocols()` 会按 ffmpeg 实际编进去的协议过滤，**未验证**）。
- 只在 Linux + OpenSSL 上编译验证过；Windows（SChannel）、Android（mbedtls）未编。

## 验证

```
# 1) 起信令 mock（仅标准库）
python3 tools/whep-flavor/mock_whep_signal.py --port 18090 --token tok123
# 2) 用带 whep 的 ffprobe 打开（-v verbose 能看到 offer / answer / 流 / DELETE）
ffprobe -v verbose -f whep -token tok123 -i whep+http://127.0.0.1:18090/x
```

mock 的错误场景路径：`/nf`(404) `/unauth`(401) `/nofp` `/badfp` `/sha1` `/nocand` `/bad` `/empty` `/slow`，正常变体 `/remap`（payload type 换成 97/99/100）。详见 `tools/whep-flavor/mock_whep_signal.py` 文件头。

## 升级 ffmpeg 版本时

0001 的 `configure`/`allformats.c`/`Makefile` hunk 对上下文敏感；0002 依赖 `http.c` 的 `process_line` 与 `HTTPContext` 布局；0003 用到的内部 API：`ff_ssl_gen_key_cert`、`ff_http_get_new_location`、`ff_data_to_hex`、`FF_INFMT_FLAG_INIT_CLEANUP`，换版本要逐个确认。
