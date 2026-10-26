# Windows SChannel 作 DTLS-SRTP server 的 WHEP 真握手验证

日期：2026-10-02。结论先行：**SChannel 可行**，唯一的坑是 SRTP profile 字节序（要写 `0x0100`，不是 `0x0001`）。下文"实测"均为本机真实输出，"推断"单独标注。

## 结论

| 问题 | 结果（实测） |
|---|---|
| SChannel 作 DTLS server 能否握手 | 能。对真实 MediaMTX v1.21.1（pion 作 DTLS client）握手完成，约 170–190ms |
| 能否协商 use_srtp | 能，但 profile 字节序必须是 `0x0100`（即线上字节 `00 01`，SChannel 按网络字节序读缓冲区）。写 `0x0001` 时 ServerHello 根本不带 use_srtp，pion 回 fatal alert 0x47 |
| 能否导出 SRTP 材料 | 能，`ff_dtls_export_materials` 返回 60 字节，profile `SRTP_AES128_CM_HMAC_SHA1_80` |
| 材料对不对 | 对。SRTP 解密 `auth_fail=0`，`ffmpeg -t 10 -f null -`：音频 505 包 503 帧、视频 242 包 231 帧，**0 decode errors**，退出码 0 |
| 对端证书指纹 | `SECPKG_ATTR_REMOTE_CERT_CONTEXT` + `ASC_REQ_MUTUAL_AUTH` 可取到对端证书，指纹比对通过 |
| 关闭 | 草稿的 `tls_shutdown_client` 在 server 侧会无限循环（见下"草稿的第二个 bug"），已修 |

## 环境

- 机器：Windows 10 Pro 10.0.19045.6456。
- MSYS2 在 `C:\tools\msys64`（不是 `C:\msys64`）。mingw64 gcc 16.2.0、make、nasm、pkgconf、git、patch 均已齐；`openssl` 包（libssl.a/libcrypto.a，3.x）也已装，没有 pacman 安装动作。
- ffmpeg：从 WSL `/root/w/ff902`（n9.0.2，`946fcce`）`git archive` 拷到 `C:\Users\jelon\whep-win\ff`（仓库外），依次 `git apply` 0001–0006（全部 ok），再叠 SChannel 草稿修改，再手工把 `whep.c` 的指纹守卫 `#if CONFIG_OPENSSL` 改成 `#if CONFIG_OPENSSL || CONFIG_SCHANNEL`。
- MediaMTX v1.21.1 `windows_amd64.zip`（27.7MB，curl 直连 GitHub 成功）解到 `C:\Users\jelon\whep-win\mediamtx`。WSL 里的 MediaMTX 占着 `[::1]:8554/8889`（WSL 转发），所以 Windows 版配置改端口：RTSP `127.0.0.1:18554`、WebRTC HTTP `127.0.0.1:18889`、ICE UDP `127.0.0.1:18189`，`webrtcEncryption: no`，HLS/RTMP/SRT/API 全关（配置在 `mediamtx\mtx.yml`）。
- 推流：用 Windows 上现成的 `C:\ProgramData\chocolatey\bin\ffmpeg`（带 libx264/libopus），参数同 WSL `start.sh`，推到 `rtsp://127.0.0.1:18554/test`。MediaMTX 日志确认 `2 tracks (H264, Opus)`。

## 构建命令（MSYS2 mingw64 原生 configure）

```
../ff/configure --disable-gpl --disable-nonfree --enable-static --disable-shared --disable-doc \
 --disable-avdevice --disable-muxers --disable-encoders --disable-demuxers --disable-decoders \
 --disable-parsers --disable-protocols --disable-devices --disable-bsfs --disable-iamf \
 --disable-bzlib --disable-lzma --disable-iconv --disable-sdl2 --enable-small --enable-optimizations \
 --disable-symver --enable-muxer=null,framecrc --enable-encoder=wrapped_avframe,pcm_s16le \
 --enable-decoder=h264,opus --enable-parser=h264,opus --enable-demuxer=whep \
 --enable-protocol=dtls,tls,udp,tcp,http,https,file,pipe,crypto,srtp \
 --enable-bsf=h264_mp4toannexb --enable-network  --enable-schannel --disable-openssl
```

`config.h` 里 `CONFIG_SCHANNEL 1`、`CONFIG_OPENSSL 0`、`HAVE_SECPKGCONTEXT_KEYINGMATERIALINFO 1`、`CONFIG_DTLS_PROTOCOL`/`CONFIG_WHEP_DEMUXER` 均启用。（保留了默认的 filters，只为让 ffmpeg 能跑 `-f null`；与 build-linux.sh 的"全禁 filters"不同，不影响结论。）

## 握手过程（实测，`SCH_DUMP` 临时十六进制转储）

写 `0x0001`（草稿原样）：

1. 收 149 字节 ClientHello（无 cookie）→ `0x90312 SEC_I_CONTINUE_NEEDED`，发 HelloVerifyRequest（60 字节）。
2. 收 181 字节 ClientHello（带 cookie，**含 use_srtp：扩展 `000e 0009 0006 0008 0007 0001 00`**，即 pion 提议 AEAD_AES_256_GCM / AEAD_AES_128_GCM / AES128_CM_SHA1_80）→ `0x90364 SEC_I_MESSAGE_FRAGMENT`，发出 ServerHello(681 字节，ECDSA P-256 自签证书，套件 `c02c`) + CertificateRequest(57) + ServerHelloDone(25)。
3. **ServerHello 的扩展只有 `0017 0000`（EMS）和 `ff01 0001 00`（renegotiation_info），没有 use_srtp。**
4. 收到 15 字节记录 `15 fefd ... 0002 02 47`：DTLS fatal alert，描述 71（insufficient_security），pion 因为没协商到 SRTP profile 拒绝。随后循环在等对端下一包，直到 `handshake_timeout` 触发 `Immediate exit requested`。MediaMTX 日志：`peer connection state: failed`。

写 `0x0100`：ServerHello 变成 690 字节，扩展里多出 `000e 0005 0002 0001 00`（use_srtp，profile = 0x0001 = SRTP_AES128_CM_HMAC_SHA1_80）；随后收到客户端的 Certificate(618 字节)/ClientKeyExchange/Finished，`AcceptSecurityContext` 返回 `SEC_E_OK`，`Handshake completed`；`DTLS done, peer fingerprint verified; SRTP keying material exported: 60 bytes, profile SRTP_AES128_CM_HMAC_SHA1_80`。

原始日志（草稿同目录）：`schannel_profile_0001_fail.log`、`schannel_0100_serverhello_dump.log`、`schannel_profile_0100_ok.log`。

## 媒体层结果（0x0100，SChannel 构建，真实 MediaMTX）

```
ffprobe -f whep -i whep+http://127.0.0.1:18889/test/whep -show_streams
  -> opus 48000 stereo；h264 640x360，RTP 计数 auth_fail=0 late/dup=0 lost=0
ffmpeg  -f whep -i ... -t 10 -f null -        (退出码 0，约 9.2s 墙钟)
  Input stream #0:0 (audio): 505 packets read; 503 frames decoded; 0 decode errors (482880 samples)
  Input stream #0:1 (video): 242 packets read; 231 frames decoded; 0 decode errors
  RTP audio packets=534 auth_fail=0 lost=0；RTP video packets=654 auth_fail=0 lost=0
  STUN: server checks answered=6 consent responses=4
```

视频帧数少于 250 是 0005 已记录的"起播等 IDR"。结果与 Linux+OpenSSL 一致（同一推流源、同一服务端）。

## 草稿里发现并修掉的两个问题

1. **SRTP profile 字节序**（上面的主发现）：`SEC_SRTP_PROTECTION_PROFILES srtp_profiles = { 2, { 0x0001 } }` 要改成 `{ 2, { 0x0100 } }`。含义是 SChannel 把缓冲区里的 profile 当网络字节序读；对 `SRTP_AES128_CM_HMAC_SHA1_80`（0x0001）小端机上要写 `0x0100`。**推断**：以后若加 `SRTP_AEAD_AES_128_GCM`（0x0007）要写 `0x0700`；`ProfilesSize`（字节数）按主机序，写 2 没问题（实测）。
2. **`tls_shutdown_client` 在 server 侧死循环**（原因：对 DTLS server 的 `AcceptSecurityContext(NULL 输入)` 反复返回 `SEC_I_CONTINUE_NEEDED`，`do..while` 无出口）。现象：握手、取流都正常，但 `ffprobe` 在 `read_close` 里永远不返回（用 gdb 抓栈：`whep_media_close -> tls_close -> tls_shutdown_client -> AcceptSecurityContext`）。修法：循环最多 8 次，且 `SEC_I_CONTINUE_NEEDED` 只在 client 侧继续。修后关闭 `Close session result: 0x90312`，随即 `DELETE` 200，进程正常退出（整次 ffprobe 约 2.7s）。**这个 bug 的根因在 n9.0.2 上游 `tls_shutdown_client` 对 server 侧的假设，不是草稿新增的。**

修好的版本在 `scratchpad\agy-schannel\`：`tls_schannel.fixed.c`（完整文件）、`tls_schannel.fixed.diff`（对 n9.0.2 原 `libavformat/tls_schannel.c` 的 `git apply --check` 通过）。`whep.c` 的守卫同步改动只有一行（`CONFIG_OPENSSL || CONFIG_SCHANNEL`），0007 里已含，不要重复。注意 0007 是在 `whep.c` 加 `CONFIG_MBEDTLS`，三者合起来要 `CONFIG_OPENSSL || CONFIG_MBEDTLS || CONFIG_SCHANNEL`。

## 未验证 / 局限

- 只在 Win10 19045（22H2）验证。Win11/Server 2022 行为**未测**；`SECBUFFER_SRTP_PROTECTION_PROFILES` 是较新的 SSPI 能力，更老的 Windows（如 Win10 1809 以前）**推断**可能不支持，需要时先测。
- 只验证了 `SRTP_AES128_CM_HMAC_SHA1_80`；SChannel 是否会在 profile 列表更长时选 GCM 未测（当前只提交一个 profile）。
- 握手期没有主动驱动服务端重传（草稿已注明），丢包握手未测。
- 对端是 pion（MediaMTX），浏览器类对端（Chrome 等）未测。
- 只跑了本机回环；没跑 `whep_tamper_proxy.py` 的 fp/dead/silent/lossy 场景，也没跑 mpv（libmpv）侧。
- `ASC_REQ_MUTUAL_AUTH` 在没有 `use_srtp` 的 DTLS server 里不会触发（条件是 `is_dtls && use_srtp`），与 whip 作 DTLS server 的行为是否一致**未测**。

## 退路评估：Windows 改用 OpenSSL 后端的体积代价（实测，非必需）

SChannel 已可行，所以这只是对照数据。同一份源码、同一 configure（仅 `--enable-openssl --disable-schannel` 与 `--enable-schannel --disable-openssl` 之差），`ffprobe.exe` 静态链接（`-static -Wl,--gc-sections`），stripped：

| 后端 | ffprobe.exe 字节 |
|---|---|
| SChannel | 9,302,528 |
| OpenSSL（MSYS2 官方 libssl.a 1.68MB + libcrypto.a 9.74MB，未裁剪） | 14,862,336 |
| 差 | **+5,559,808（+5.3 MiB，+60%）** |

注意：这是整个 ffprobe 可执行文件（含 libstdc++、avfilter 等），差值才是后端带来的；用的是 MSYS2 通用 OpenSSL，不是裁剪过的最小 OpenSSL（最小化 OpenSSL 的体积**未测**）。不静态链接时 OpenSSL 版要带 `libcrypto-3-x64.dll`/`libssl-3-x64.dll`。此外 Windows 上不用 OpenSSL 还免掉一个第三方依赖与 LGPL/Apache 合规面（**推断**）。结论：Windows 用 SChannel，不必退到 OpenSSL。

## 复现

```
# 构建目录与产物（仓库外）：C:\Users\jelon\whep-win\bld-sch\{ffprobe,ffmpeg}.exe  /  bld-ossl（OpenSSL 对照）
# MediaMTX：C:\Users\jelon\whep-win\mediamtx\mediamtx.exe mtx.yml
# 推流：ffmpeg -re -f lavfi -i testsrc2=size=640x360:rate=25 -f lavfi -i sine=frequency=440:sample_rate=48000 \
#   -c:v libx264 -preset ultrafast -tune zerolatency -profile:v baseline -pix_fmt yuv420p -b:v 400k -g 50 -bf 0 \
#   -c:a libopus -b:a 32k -ar 48000 -ac 2 -f rtsp -rtsp_transport tcp rtsp://127.0.0.1:18554/test
ffprobe.exe -v verbose -f whep -i whep+http://127.0.0.1:18889/test/whep
ffmpeg.exe  -v verbose -f whep -i whep+http://127.0.0.1:18889/test/whep -t 10 -f null -
```

踩坑：MSYS2 下并行起两个 `make`（后台一个 + 手动一个）会写坏 `libavformat.a`，表现为 `ar: @libavformat.a.objs: No such file` 和满屏 `undefined reference to avio_*`；删掉所有 `.a`/`.a.objs` 重编即可。
