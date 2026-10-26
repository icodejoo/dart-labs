# T0.3 WHEP 可行性小验证结论（2026-10-02）

对应计划 `doc/plans/2026-10-01-whep-receiver.md` T0.3。环境：WSL，ffmpeg n9.0.2 + mpv v0.41.0（libmpv 2.5.0），均为本机实编。
spike 代码在 WSL `/root/w/t03/`（不入库）：`ff/`（带 whep 桩的 n9.0.2 副本）、`mpv/`（打了补丁的 v0.41.0）、`ffm/`（带 mbedtls 的 ffmpeg 副本）、`sdp_proto.c`、`srtp_test.c`、`srtp_ref.py`、`mbed/`+`mb{0,1,2}`+`mbi{0,1,2}`。

标注约定：**实测** = 本机跑出来的输出；**推断** = 由源码/实测外推，未直接跑过。

## 总表

| 项 | 结论 | 说明 |
|---|---|---|
| 1 NOFILE demuxer + mpv | **通过（需 2 处 mpv 补丁）** | 无补丁：被 stream_lavf 拦截，read_probe/read_header 都到不了；加补丁后 `read_header` 到达，两条流被 mpv 选中并打开 h264/opus 解码器 |
| 2 最小 SDP 解析 | **通过** | `ff_sdp_parse` 不可复用（耦合 RTSPState）；自写原型 43 行解析函数（全文件 78 行含测试）解析 SRS 风格 answer 全部必填字段 |
| 3 `ff_srtp_decrypt` | **通过** | 密钥派生与 RFC 3711 B.3 向量一致；密文与独立 Python 实现逐字节相同；解密还原明文；篡改被拒 |
| 4a mingw `SECPKG_ATTR_DTLS_MTU` | **通过** | 本机 MSYS2 mingw64 头文件（mingw-w64 v15.0）里有定义，configure 同款探测代码编译通过 |
| 4b Android mbedtls `DTLS_SRTP` | **通过（Linux 近似）** | 只需加一个宏 `MBEDTLS_SSL_DTLS_SRTP`；`MBEDTLS_TIMING_C` 必须保留；体积 +4,128 B（最终 .so，strip 后） |

---

## 1. NOFILE demuxer 桩 + mpv 取流路径

### 做法（实测）
- `libavformat/whep.c` 桩：`.p.flags = AVFMT_NOFILE`，`read_probe` 认 `whep:` 前缀（返回 `AVPROBE_SCORE_MAX`），`read_header` 里 `avformat_new_stream` x2（H264 640x360、Opus 48k 2ch），`read_packet` 恒返回 `AVERROR_EOF`。
- 注册：`allformats.c` 加一行 extern、`Makefile` 加 `OBJS-$(CONFIG_WHEP_DEMUXER) += whep.o`，configure 带 `--enable-demuxer=whep,...`（configure 会自动从 allformats.c 识别，不用改 configure 本体）。配置沿用 t02 的 `ffconfN9.sh`（LGPL，`License: LGPL version 2.1 or later`）。
- mpv：`meson setup -Dauto_features=disabled -Dbuildtype=minsize -Dcplayer=false -Dlibmpv=true -Dgl=disabled -Dgpl=false`，用 t02 的 `smoke.c`（加 verbose 日志）跑 `loadfile whep://x`。

### 无补丁（实测）
```
[stream_callback] Opening whep://x
No protocol handler found to open URL whep://x
Opening failed or was aborted: whep://x   (end reason=4 err=-13)
```
`read_probe` / `read_header` 一次都没被调用：mpv 在 stream 层先走 `avio_open2`，`whep` 不是 protocol。**R2 成立。**

### 打补丁后（实测）
```
[ffmpeg] Opening whep://x
[lavf] Found 'whep' at score=100 size=0 (forced).
[ffmpeg/demuxer] whep: [whep] read_header REACHED url='whep://x' pb=(nil)
[demux] Detected file format: whep (libavformat)
[lavf] select track 0 / select track 1
● Video --vid=1 (h264 640x360)   ● Audio --aid=1 (opus 2ch 48000 Hz)
[vd] Opening decoder h264 ... [ad] Opening decoder opus
```
`pb=(nil)` 证实 NOFILE 下 mpv 不建自有 AVIO（与 `demux_lavf.c:1023` 的判断一致）。桩 `read_packet` 返 EOF，所以后面是正常 EOF 收尾，不影响结论。
没有触发 protocol whitelist 拦截（走的是 demuxer，不是 protocol）。

### 最小 mpv 补丁（`stream/stream_lavf.c`，实测有效，两处缺一不可）
实测事实：只有 `open_f` 里的特判 + 没有注册 scheme 时，仍然落到上面的 "No protocol handler"（第一次补丁尝试即如此）；补上 scheme 注册后才通。（反过来"只有注册、没有 open_f 特判"没有单独测，**推断**会走到 `avio_open2` 同样失败。）

```diff
@@ get_safe_protocols()  (rtsp 注册段之后)
+    // whep is likewise a NOFILE demuxer, not a protocol.
+    for (int i = 0; ffmpeg_demuxers[i]; i++) {
+        if (strcmp("whep", ffmpeg_demuxers[i]) == 0) {
+            MP_TARRAY_APPEND(NULL, protocols, num, talloc_strdup(protocols, "whep"));
+            break;
+        }
+    }
@@ open_f()  (紧跟 rtsp: 特判之后)
+    if (!strncmp(filename, "whep:", 5)) {
+        /* WHEP is an AVFMT_NOFILE demuxer in libavformat (no protocol entry),
+         * handled like rtsp: demux_lavf does the work without a stream layer. */
+        stream->demuxer = "lavf";
+        stream->lavf_type = "whep";
+        talloc_free(temp);
+        return STREAM_OK;
+    }
```
共 +17 行，不影响体积。`lavf_type="whep"` 让 `demux_lavf.c:448` 用 `av_find_input_format("whep")` 强制格式（日志里 `(forced)`）。

### 额外发现
- mpv 的 `mp_setup_av_network_options` 会往 demuxer 选项里塞 `user_agent`、`tls_verify`、`icy`、`timeout`，桩因没声明这些 AVOption，日志里是 `Could not set AVOption user_agent='libmpv'` 等 4 条（实测，无害）。**正式 whep.c 需要自己声明 `tls_verify`（以及 `timeout`、`user_agent` 如需），否则 mpv 的 TLS 校验开关传不进 WHEP 信令**——与 `extreme-slim-config.md` 里 `tls_verify` 默认值的迁移坑同一件事。
- 计划里 A3 采用 demuxer 路线可行；T1.x 里"mpv 本体不改"的表述需改为"mpv 加 17 行补丁（stream_lavf.c）"。`whep+http(s)://` 之类的别名 scheme 我没有加（补丁只认 `whep:`），要加就得在 `get_safe_protocols` 和 `open_f` 各补一处。
- Plan B（protocol 方案 / `--demuxer-lavf-format=whep`）**未测**；因为 stream 层先于 demuxer，后者**推断**同样会被 `avio_open2` 拦住，不是免补丁的出路。

---

## 2. 最小自写 SDP 解析

### 为什么不复用 `ff_sdp_parse`（实测读源码）
- `rtsp.c:751 ff_sdp_parse` → `sdp_parse_line`（448–750，约 300 行）开头就是 `RTSPState *rt = s->priv_data;`，m= 行里 `rtsp_st = av_mallocz(RTSPStream)`、`rt->rtsp_streams[]` 追加、`ff_rtp_parse_open`、`rtp_handler` 查找；`rtsp.c` 448–800 区间含 `rt->`/`rtsp_st` 引用 78 处。
- 必须有 `RTSPState` 做 priv_data，且它会按 RTP/AVP 语义建 RTP 解包器；WebRTC 的 `UDP/TLS/RTP/SAVPF` + BUNDLE 用不上，还得塞满 RTSPState。**不可取，结论成立。**

### 自写评估（实测原型）
`/root/w/t03/sdp_proto.c`：无 ffmpeg 依赖的纯 C，解析函数 43 行，整文件 78 行（含结构体和测试 main）。覆盖 `m=`、`a=rtpmap`、`a=fmtp`、`a=ice-ufrag/ice-pwd/ice-lite`、`a=fingerprint`、`a=setup`、`a=mid`、`a=rtcp-fb`（nack / nack pli）、`a=candidate`（只取第一个 udp host，和 whip.c `parse_answer` 同策略）。
放进 ffmpeg 风格（AVDictionary/av_log/错误码、候选多条、`a=group:BUNDLE`、多 payload 选择）预计 **150–250 行**（**推断**）。

输出（实测，输入是 SRS 风格 answer，audio=opus/111、video=H264/106）：
```
ret=0 lite=1 ufrag=u1x9 pwd=pw0123456789abcdefghij fp=sha-256 AA:BB:CC:DD setup=passive cand=192.168.1.10:8000 nb=2
m[0] audio mid=0 pt=111 opus/48000/2 nack=0 pli=0 fmtp=minptime=10;useinbandfec=1
m[1] video mid=1 pt=106 H264/90000/1 nack=1 pli=1 fmtp=level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f
missing-fp ret=-1
```
缺 fingerprint 返回 -1，对齐 whip.c "无 fingerprint 拒绝"的安全要求。

### 关键片段
```c
typedef struct { char type[8], mid[16], codec[16], fmtp[256]; int pt, clock, channels, nack, pli; } WMedia;
typedef struct { char ufrag[64], pwd[256], fp_algo[16], fp[160], setup[16];
                 char cand_host[129]; int cand_port, ice_lite; int nb; WMedia m[4]; } WSdp;

static int whep_sdp_parse(const char *sdp, WSdp *o) {
    /* 逐行：m= 开新媒体段（sscanf "%7s %*d %*s %d" 取 type 与首个 pt），
       a=ice-ufrag / ice-pwd / fingerprint / setup / candidate 取首个（会话级或首个媒体级均可），
       a=rtpmap:<pt> <name>/<clock>[/<ch>]，a=fmtp:<pt> ...，a=rtcp-fb:<pt> nack [pli] 只认当前媒体段 pt */
    ...
    if (!o->ufrag[0] || !o->pwd[0] || !o->fp[0] || !o->cand_host[0]) return -1;
}
```
注意：WHEP 的 ICE 参数可能在媒体级而非会话级（bundle 下常见），原型"取首个"已覆盖；多候选/tcp 候选/IPv6 未处理。

---

## 3. `ff_srtp_decrypt`（`srtp.c:127`）

### 方法（实测）
`srtp_test.c` 直接编译 `libavformat/srtp.c` + 链 `libavutil.a`；套件 `SRTP_AES128_CM_HMAC_SHA1_80`（whip.c 同款），主密钥/盐用 RFC 3711 附录 B.3：key `E1F97A0D3E018BE0D64FA32C06DE4139`，salt `0EC675AD498AFEEBB6960B3AABE6`。RTP 包：seq 0x1234、ssrc 0xdeadbeef、20 字节明文。

### 结果（实测）
```
rtp_key=c61e7a93744f39ee10734afe3ff7a087        (RFC 3711 B.3: C61E7A93744F39EE10734AFE3FF7A087 ✔)
rtp_salt=30cbbc08863d8c85d49db34a9ae1           (RFC: 30CBBC08863D8C85D49DB34A9AE1 ✔)
rtp_auth=cebe321f6ff7716b6fd4ab49af256a156d38baa4  (RFC: CEBE321F6FF7716B6FD4AB49AF256A15 6D38BAA4 ✔)
enc_len=42 cipher=806f123400001000deadbeef5f556caa...ee4a
decrypt r=0 len=32 match=1
external r=0 len=32 match=1      # 用独立 Python(cryptography) 实现造的密文喂给 ff_srtp_decrypt
tamper r=-1094995529 (HMAC mismatch, 预期 <0)
```
Python 参考实现（`srtp_ref.py`，自己按 RFC 3711 写的 KDF + AES-CTR + HMAC-SHA1-80）输出的密文与 `ff_srtp_encrypt` **逐字节相同**，并且能被 `ff_srtp_decrypt` 还原。语义确认：RTP 路径 `len` 入参含 10 字节 tag，成功后 `*lenptr` 变为去 tag 后长度，原地解密。

### 接收端需要注意（读源码，推断）
- 源码自带 `// TODO: Missing replay protection`：无重放防护，WHEP 接收端可接受（接收端更看重不崩），但要知道。
- ROC/seq 翻转处理在 `:150` 一带按 RFC 3711 附录 A 写了，没有对乱序大跳变做更多保护（未测）。
- 只支持 AES_CM + HMAC_SHA1_80/32，无 GCM（R4 的 GCM 风险仍在）。

---

## 4a. mingw 头里的 `SECPKG_ATTR_DTLS_MTU`

- 本机有 MSYS2：`C:\tools\msys64\mingw64\include`（mingw-w64 v15.0，`_mingw_mac.h`）。`sspi.h:539: #define SECPKG_ATTR_DTLS_MTU 34`；`schannel.h:86-88` 有 `SECPKG_ATTR_KEYING_MATERIAL_INFO/KEYING_MATERIAL/SRTP_PARAMETERS`；`sspi.h` 有 `SEC_SRTP_PROTECTION_PROFILES` 等结构。
- 用 configure `:7619` 同款探测（实测编译通过，输出 `COMPILE_OK`）：
```c
#define SECURITY_WIN32
#include <windows.h>
#include <security.h>
#include <schnlsp.h>
int main(void){ int i = SECPKG_ATTR_DTLS_MTU; int j = SECPKG_ATTR_KEYING_MATERIAL; int k = SECPKG_ATTR_KEYING_MATERIAL_INFO; return i+j+k; }
```
`PATH=/c/tools/msys64/mingw64/bin:$PATH gcc -c t.c` 成功。ucrt64 头与 mingw64 同包同版本（grep 结果一致）。
- 没测到的：`clang64` 环境本机没装（`include/sspi.h` 不存在），CI 若用 clang64 的头，**推断**与 mingw64 同源（同一 mingw-w64-headers 版本）但没实测；WSL 的 Ubuntu apt 包 `mingw-w64-x86-64-dev 13.0.0` 可下载，但解出来头文件不全（符号链接包），没用它做结论。
- 没跑真 SChannel DTLS 握手，只证明了编译期符号可用。R6 的"缺宏需补丁"在 v15 头下**不触发**；更老的头版本（<某版本）**未核实**。

## 4b. Android mbedtls `MBEDTLS_SSL_DTLS_SRTP`（Linux 近似，mbedtls 3.6.7 + ffmpeg n9.0.2）

### 做法（实测）
- 同一份 mbedtls 3.6.7 源码，三套配置（`MinSizeRel -Os`、`-ffunction-sections -fdata-sections`、`-fPIC`、静态库）：
  - cfg0：默认配置（`DTLS_SRTP` 默认注释掉）
  - cfg1：`scripts/config.py set MBEDTLS_SSL_DTLS_SRTP`
  - cfg2：cfg1 再 `unset MBEDTLS_TIMING_C`
- ffmpeg n9.0.2 带 `--enable-mbedtls --enable-version3 --enable-muxer=whip --enable-protocol=dtls,srtp,...`（whip 只是为了把 dtls/srtp/`ff_dtls_export_materials` 拉进链接，三个变体一致），`CONFIG_MBEDTLS/DTLS_PROTOCOL/SRTP_PROTOCOL/WHIP_MUXER=yes` 已确认。
- 对每个变体单独重编 `tls_mbedtls.c`（`-DMBEDTLS_CONFIG_FILE=cfgN.h`，因为 `#if defined(MBEDTLS_SSL_DTLS_SRTP)` 在该文件里），替换进 `libavformat.a`，链成 `-shared -Wl,--gc-sections` 的 probe `.so` 再 strip。

### 最小宏集（实测）
- **只需加 `MBEDTLS_SSL_DTLS_SRTP`**（3.6.7 默认配置里 `MBEDTLS_SSL_PROTO_DTLS`、`MBEDTLS_SSL_EXPORT_KEYS` 是内建/默认开的；`config.h` 里 EXPORT_KEYS 在 3.6 已不是可选项，没有可 grep 的 define）。
- **`MBEDTLS_TIMING_C` 必须保留（实测）**：`tls_mbedtls.c:687` 无条件用 `mbedtls_timing_set_delay/get_delay` 做 DTLS 重传定时器；cfg2 下 `.so` 带 `-Wl,--no-undefined` 链接直接报 `undefined reference to mbedtls_timing_*`（计 2 处）。不开 TIMING_C 想省的 2.1KB 不能省。
- 链接符号（实测）：cfg1 链接带 `--no-undefined` 后 0 个 mbedtls/dtls 未定义符号（仅有与本题无关的 `BZ2_*`，加 `-lbz2` 即清零），`ff_dtls_export_materials`、`dtls_srtp_key_derivation`、`mbedtls_ssl_tls_prf`、`mbedtls_ssl_conf_dtls_srtp_protection_profiles`、`mbedtls_ssl_get_dtls_srtp_negotiation_result` 均在。cfg0 编译链接也过，但 `.so` 里没有 `dtls_srtp_key_derivation`——走 `#else` 的 "DTLS-SRTP is not supported in this mbedtls build" 报错路径（与 extreme-slim-config 笔记的说法一致）。

### 体积（实测）
| 量 | cfg0 默认 | cfg1 +SRTP | 差 |
|---|---|---|---|
| `libmbedtls.a`（归档） | 584,256 | 590,866 | **+6,610** |
| `libmbedcrypto.a`（归档） | 1,238,340 | 1,238,388 | +48 |
| 最终 probe `.so`（strip，gc-sections） | 6,069,392 | 6,073,520 | **+4,128** |
cfg2（+SRTP −TIMING_C）归档 crypto −2,154 B，但链接不过，作废。
体积代价可忽略（约 4KB），不影响体积第一的目标。

### 没验证的（诚实）
- **没有真跑 DTLS 握手**（没服务器），所以"协商出 `SRTP_AES128_CM_SHA1_80`、`mbedtls_ssl_tls_prf` 导出的 60 字节材料能被 `ff_srtp_set_crypto` 吃下"只是读源码推断，不是实测。
- 是 Linux x86_64 + gcc，不是 Android NDK clang/arm64；宏集是平台无关的，**推断**一致。
- 服务器强制 GCM 套件的情况（R4）仍未覆盖；mbedtls 3.6.7 `ssl.h:1236-1239` 的 `MBEDTLS_TLS_SRTP_*` 只有 AES128_CM_HMAC_SHA1_80/32 与 NULL_HMAC_SHA1_80/32 四个，无 GCM（读头文件实证），所以 R4 的"服务器只给 GCM 就握不上"在 Android 路径上没有软件出路，只能靠服务器默认接受 SHA1_80（SRS/MediaMTX 是否默认接受 **仍未核实**）。

---

## 风险表更新建议（R2/R4/R6）

- **R2**：由"未核实"改为"已核实，需 mpv 补丁"。补丁 17 行（上文），A3 维持 demuxer 预案；`whep.c` 要声明 `tls_verify`/`timeout`/`user_agent` 选项以接住 mpv 注入的参数。T1.x 里"mpv 本体不改"改为"mpv 仅加 `stream_lavf.c` 17 行补丁，补丁放 `mova-libmpv/patches/` 并随 mpv 升级回归"。替代路径 Plan B（protocol 或强制 `-f whep`）实测上不比补丁省事，不建议。
- **R4**：宏集已确认只需 `MBEDTLS_SSL_DTLS_SRTP` + 保留 `MBEDTLS_TIMING_C`，编译链接通过，+4KB。剩余风险是 GCM 与真实握手互通，需在 T3.1 里对 SRS/MediaMTX 实测；无软件替代，只能服务端配置规避。
- **R6**：mingw-w64 v15 头已有 `SECPKG_ATTR_DTLS_MTU`，探测通过，可降级风险；CI 如锁了老版本 MSYS2 头，需单独验。
- A6：改为"自写最小 SDP 解析（约 150–250 行）"，不抽 `ff_sdp_parse`。
- `ff_srtp_decrypt` 可直接用（已与独立实现互验），注意无重放防护、仅 CM+SHA1。
