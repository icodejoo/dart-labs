# WHEP 信令 answer 为 chunked 时 EIO：根因与修复（补丁 0011）

日期：2026-10-24。分支 `feat/whep-receiver`。承接 [android-udp-pli-nack-verify](2026-10-24-android-udp-pli-nack-verify.md) 的"新发现缺陷"。

## 根因（已复现，A/B 证实）

触发条件是**响应用 `Transfer-Encoding: chunked`**，与 answer 大小本身无关（MediaMTX 只是在 >2KB 时才分块）。上轮"推测 `ffurl_read` 读 chunked 报 EIO"方向对，机制如下（n9.0.2 `libavformat/http.c`）：

1. `http_buf_read()`：读到末块（size 0）且未开 `multiple_requests` 时，`ffurl_closep(&s->hd)` 并 `return 0`（约 1749 行）。
2. `ffurl_read` 对返回 0 会继续重试，再进 `http_read_stream()` 开头：`if (!s->hd) return s->off < s->filesize ? AVERROR(EIO) : AVERROR_EOF;`
3. chunked 响应头处理里 `s->filesize = UINT64_MAX`，`off < filesize` 恒成立，于是返回 **EIO**，而不是 EOF。
4. `whep_exchange_sdp` 的读循环把 EIO 当错误：`Reading WHEP answer failed: I/O error`。Content-Length 响应走 `off >= file_end -> AVERROR_EOF`，不触发。

复现证据（WSL Ubuntu，ffmpeg n9.0.2 + 补丁 0001-0010，OpenSSL，`ffprobe -f whep`，mock 新场景 `/big` chunked / `/bigcl` Content-Length，answer 均 2136 字节，12 条候选的真实 MediaMTX 同理）：

| 版本 | /bigcl | /big |
|---|---|---|
| 0001-0010 | `Got answer (2136 bytes)` | `Reading WHEP answer failed: Input/output error`（trace 里先出现 `Last chunk received, closing conn`） |
| +0011 | `Got answer (2136 bytes)` | `Got answer (2136 bytes)` |

另：对真实 MediaMTX v1.21.1（默认 `webrtcIPsFromInterfaces: true`，answer 带 12 条候选）`curl -i` 确认 `Transfer-Encoding: chunked`。

## 修复

`patches/ffmpeg-whep/0011-...patch`：`whep_exchange_sdp` 打开 POST 时加 `multiple_requests=1`。该选项让末块走 `chunkend=1; return 0` 分支，下一次读干净返回 EOF。只改 `whep.c` 一处，DELETE 路径本来忽略读结果，不动。

## 回归

- 自动化：`tools/whep-flavor/mock_whep_signal.py` 新增 `/big`（chunked，分 512 字节块）与 `/bigcl`；`tools/whep-flavor/whep_chunked_regress.sh <ffprobe>`，两者都要读到 answer，实测 PASS/PASS（未修复版本 big 为 FAIL）。
- Android 真机（STG-AL00 `7NQBB23606003715`，同网段真实 UDP，MediaMTX **默认配置**即 `webrtcIPsFromInterfaces: true`，不再用绕过）：
  - 新 `libmpv.so`（`patches/android-v041/e2e-arm64.sh` WHEP=1，在 WSL 重建，NDK r25c 重新下载；stripped 6,354,032 字节，sha256 `c8de73be...fbee9`，旧 6,354,272）已替换 `packages/media_kit_libs_android_video_slim_v041` 内产物。
  - 直连：信令成功，出画，40s `pos` 推进 39880ms，hwdec=mediacodec-copy，640x360@25，首个 IDR 605ms（since open）；视频 packets 4218 lost 0，`nack_seqs_sent=45 rtx_recovered=35`，音频 lost 153（同上轮口径，未区分 Wi-Fi 丢包与 seq 间隙）。
  - NACK 回归（经代理人工丢包，同上轮方法，视频+音频同比例丢；本轮代理 FINAL 计数未取到，档位按 LOSS 参数）：

| 档位 | 视频 packets | late/dup | 最终视频 lost | dropped_frames | nack_seqs_sent | rtx_recovered | giveup | pli_sent |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 5%（本轮） | 4363 | 131 | 16 | 6 | 522 | 326 | 21 | 18 |
| 10%（本轮） | 4343 | 128 | 10 | 6 | 667 | 451 | 21 | 28 |
| 5%（上轮） | 3362 | 105 | 11 | 5 | 376 | 242 | 13 | 18 |
| 10%（上轮） | 3273 | 158 | 14 | 7 | 640 | 394 | 32 | 23 |

  结论：NACK 行为同量级未退化（每次会话本身有 Wi-Fi 随机丢包，且本轮会话更长，不能逐项比；`packets` 更大因为 tail 时间不同）。
- 起播中 `h264_mediacodec: Both surface and native_window are NULL` 等旧现象未变。

## 未解决 / 未做

- Windows 版（SChannel）**未重建**：0011 只改 `whep.c` 的 http 选项，与 TLS 后端、平台无关，`build-windows.sh` 用 `ffmpeg-whep/*.patch` 通配会自动带上（已把脚本注释改为 0001-0011）；上述 Linux 复现用的是同一份 http.c。如需实锤需在 Windows 版上跑 `whep_chunked_regress.sh` 的等价命令。
- 未针对 https 信令（TLS 层 chunked）单独测；逻辑同源。
- 新 `.so` 与旧 `.so` 只在 0011 之外还有构建环境差异（-240 字节，未逐项确认来源，应来自 mbedtls/依赖拉取版本或 LTO 噪声）。
- 复现构建需把 `mova-libmpv` 脚本/补丁转 LF（Windows 工作树是 CRLF，`git apply` 会失败），本轮是在 WSL 里拷贝后 `sed -i 's/\r$//'`。
