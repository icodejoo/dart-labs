# Windows 带 WHEP 的 libmpv-2.dll 本地构建与验证

日期：2026-10-02。除标"推断"的以外都是本机实测。未改 `dist/`、未改 CI。

## 结论

- 做出了带 WHEP 的 Windows `libmpv-2.dll`：ffmpeg n9.0.2 + whep 补丁 0001–0010 + mpv v0.41.0（补丁 0001/0003/0004）+ 最小静态 libplacebo，TLS 用系统 SChannel，没有新增 TLS 库。
- **WHEP 自身增量 +28,160 字节（27.5 KiB）**，在 30KB 目标内。增量几乎全在 `libavformat.a`（whep.c + dtls 协议，+27,648 字节）。
- 与 dist 现行 14,075,392 比：WHEP 版 14,510,592，**+435,200（+3.1%）**。其中真正属于 WHEP 的只有 28KB，其余 ~407KB 来自 ffmpeg n6.0.1→n9.0.2 与 mpv 升到 v0.41 本身（见下），不是 WHEP 带来的。
- libmpv 端到端（Windows 版 MediaMTX）实测通过：开播 10s+ position 正常推进，RTCP（RR/PLI/NACK）在工作，3% 丢包中继下视频 lost=0。

## 产物与体积（strip 后）

| 构建 | 字节 | 说明 |
|---|---|---|
| dist 现行（CI 2026-09-25） | 14,075,392 | |
| 本地 base（复刻 CI：n6.0.1 + mpv 78d4374） | 13,740,032 | 比 dist 小 335,360（-2.4%） |
| 本地 n9plain（n9.0.2 + 补丁 0001-0010 但不启用 whep/dtls + mpv v0.41.0 + libplacebo） | 14,482,432 | 比 base +742,400 |
| 本地 whep（同上，启用 `--enable-demuxer=whep --enable-protocol=dtls`） | **14,510,592** | 比 n9plain **+28,160** |

产物目录（仓库外）：`C:\Users\jelon\whep-win\libmpv\{base,n9plain,whep}\out\`（`libmpv-2.dll`、`libmpv-2.unstripped.dll`、`libmpv.map`、`libmpv.dll.a`、`ffconf.log`）。

### 基线复现差异（本地 base 13,740,032 vs dist 14,075,392）

本地 MSYS2 是最新滚动快照（clang 22.1.8、gcc 16.2.0-3、binutils 2.47、freetype 2.14.3、harfbuzz 14.4.0、libass 0.17.5），CI 当时用的 `windows-latest` MSYS2 快照版本我没拿到记录。差异分布（`objdump -h`）：`.text` 少 266KB、`.rdata` 少 58KB、`.pdata`/`.xdata` 少约 9KB。导入表逐项相同，导出 55 个 `mpv_*`（dist 同）。**推断**：差异来自工具链/依赖版本漂移（同一套 configure、同一 ffmpeg/mpv 源码，配方一字不差），没有证据表明是配方问题。想把基线对齐到字节级需要锁 MSYS2 快照，没做。

### 体积归因（链接 map，只统计非 debug 段；字节为链接期输入段大小，与 strip 后 DLL 总差不会逐项相加）

n9plain → whep（只差 WHEP）：`libavformat.a` +27,648，其余库每个 +16（对齐噪声）。即 WHEP 增量 = whep.c + dtls 协议 + 注册表，约 27KB，符合预期。

base → n9plain（"n9.0.2 与 mpv v0.41 本体差异"，单列）：

| 项 | 变化（字节） |
|---|---|
| libswscale.a | +345,196 |
| libavcodec.a | +152,200 |
| mpv 自身对象（v0.41 vs 78d4374，已摘 vo_gpu_next） | +157,809 |
| libavformat.a（n9 本体，不含 whep） | +72,696 |
| libplacebo.a（gc-sections 后只剩 24KB） | +24,501 |
| libavfilter.a | +13,216 |
| libswresample.a | -3,176 |
| libavutil.a | base 的 map 里 avutil 项异常（17MB，疑似 map 解析把非 alloc 段算进来），**不可归因** |

加总约 +762KB，实际 DLL 差 +742KB，二者差 ~20KB 在 avutil 不可归因项内。n9 的 libswscale 为什么涨 345KB 没有深查（**推断**：n9 swscale 的 x86 asm/新增路径；若要压体积，这是 n9 本体里最大的单项，值得单独评估 `--disable-swscale` 相关或精简像素格式，本次不做）。

### 构建中发现并处理的坑

1. **libplacebo 静态库把 ~120 个 `pl_*` 符号 dllexport 进 libmpv 导出表**（55 → 177）。原因：libplacebo 的 `meson.build` 给库本身无条件加 `-DPL_EXPORT`。脚本里对静态构建改成 `-DPL_STATIC`（sed 改 `src/meson.build`，带自检）。修后导出恢复 55，DLL 变小 5KB（14,515,712 → 14,510,592）。Linux/Android 用 `visibility`，没有这个问题，Windows 才有。
2. `windres` 经 `cmd.exe` popen 预处理器，`PATH` 里没有 `System32` 会报 `can't popen gcc -E`；脚本保留了 System32。
3. 环境变量不能靠 `VAR=x env.exe ... bash -l` 前缀传给登录 shell（本机实测会丢），要放在 `env.exe` 的参数里；`/c/Users/jelon/whep-win/libmpv/run.sh` 是我用的包装。
4. 新增导入 DLL（相对 base）：`api-ms-win-core-path-l1-1-0.dll`、`CRYPT32`、`ncrypt`、`ntdll`、`IMM32`、`SHCORE`（SChannel 证书/SRTP、mpv v0.41 用到）。**推断**：`api-ms-win-core-path` 是 Win8+ API set，Win10 无碍；不支持 Win7。`WINMM` 不再导入。

## 符号与依赖检查（`tools/regress/check-symbols-windows.sh`，对 whep 产物）

```
[PASS] 存在，14510592 字节
[PASS] 公开 API 符号齐全（10 个）
[PASS] 导入表无 libstdc++ / libgcc_s / libwinpthread
[PASS] 无外部 mpv/ffmpeg/dav1d/ass DLL 依赖
[PASS] libdav1d 解码器名存在 / configure 串含 --disable-gpl --disable-nonfree
[PASS] configure 协议白名单含 https tls rtmps tcp http / TLS 后端为 schannel
[PASS] ffconf.log: License: LGPL version 2.1
汇总：PASS=15 FAIL=0 SKIP=2
```

- 导出表：55 个，全是 `mpv_*`（含 `mpv_create`、`mpv_initialize`、`mpv_terminate_destroy`、`mpv_render_context_create`）；`mpv_lavc_set_java_vm` 不在，Windows 不需要（脚本跳过 mpv 补丁 0002）。
- strip 前 `nm` 检查 dav1d/libass/harfbuzz/freetype/fribidi 符号：脚本内置，构建时通过。
- 脚本自带的 `check-symbols-windows.sh` 的"导出符号数"那行（输出 108）数的是 objdump 里别的 `[ n]` 行（含 dist 本身也是 108），不是真实导出数；真实导出数用 `objdump -p` 的 Ordinal/Name Pointer 表数，是 55。这是该脚本的小缺陷，没改。

## 冒烟与播放（`tools/whep-flavor/smoke-windows.c`，gcc 编，链接 `libmpv.dll.a`）

- `smoke.exe init`：mpv_create/initialize/terminate_destroy 连续 5 次，全部 ok（whep 版、两次不同构建都是）。
- 本地 mp4（H.264+AAC，vo=null）：time-pos 推进，`estimated-frame-number` 约 25 fps 增长，丢帧 0。
- 本地 HLS（`python -m http.server`，H.264+AAC）：5s 内 position 推进 3.16s（含启动），5.0s 窗口里 25fps，丢帧 0。
- `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`（SChannel HTTPS）：4.08s 推进，丢帧 0。
- 注意：以上 `vo=null`、`ao=null`，没验证画面输出和声音（本机验证过的是 demux/解码/时钟）；渲染面（OpenGL/ANGLE）链路未在本次验证。

## WHEP 端到端（Windows 版 MediaMTX v1.21.1，端口 18889/18189/18554，ffmpeg 推 H264 baseline 400k + Opus）

最终 whep 产物，`whep+http://127.0.0.1:18889/test/whep`，打开 12s：

```
DTLS done, peer fingerprint verified; SRTP keying material exported: 60 bytes, profile SRTP_AES128_CM_HMAC_SHA1_80, elapsed=151.0ms
First RTP packet (audio) at 185.5ms since open
First video key frame out at 584.9ms since open (pli_sent=1)
RTP audio: packets=593 auth_fail=0 late/dup=0 lost=0 frames=593
RTP video: packets=745 auth_fail=0 late/dup=0 lost=0 frames=286 before_keyframe=10
RTCP audio: rr_sent=11            RTCP video: rr_sent=11 pli_sent=2 nack=1 pli_on=1
time-pos 0.760 -> 9.800（advanced 9.04s），estimated-frame-number 245 @ t=11s，decoder/vo 丢帧 0
```

- 起播耗时有波动：三次实测首帧（key frame out）584.9ms / 1193ms / 1668ms，对应 file-loaded 在 t≈1–3s；这与 pli_sent 次数有关（1 次 vs 2 次）。**推断**：首个 IDR 的到达取决于推流端 GOP 与 PLI 往返，不是 libmpv/SChannel 引起（Linux 同源同服务端也有类似波动，未专门对比）。
- RTCP 确实在工作（日志计数，不是推断）：RR 周期发送、PLI 起播发送；NACK/重传见下。

丢包中继（`whep_tamper_proxy.py` lossy，`LOSS=3 SWAP=2 DUP=1 CORRUPT=1`，种子固定，URL `whep+http://127.0.0.1:18888/lossy/test/whep`），最终 whep 产物 12s：

```
relay {'rtp': 1368, 'drop': 56, 'swap': 19, 'dup': 18, 'corrupt': 8}
RTP video: packets=746 auth_fail=4 late/dup=10 lost=0 frames=273 dropped_frames=0
RTCP video: nack_seqs_sent=35 nack_msgs=33 nack_giveup=0 rtx_recovered=35 pli_sent=2 rr_sent=11
RTP audio: packets=573 auth_fail=4 late/dup=8 lost=28 （音频不发 NACK，设计如此，Opus 靠 PLC）
position 1.84 -> 9.24（advanced 7.40s）
```

即视频丢包全部靠 NACK 补回（35 个序号请求，35 个恢复，lost=0），`auth_fail=4` 对应注入的 4 个损坏包被 SRTP 认证拒掉。更早一次同配置运行（同样的 ffmpeg 代码，导出修复前的 DLL）：NACK 45 发、43 恢复，lost=0。

指纹篡改（`/fp/test/whep`）：`DTLS peer certificate fingerprint does not match the answer; refusing`，播放失败 `error=-17`，SChannel 的对端证书指纹比对在 libmpv 链路上有效。

## 局限 / 未验证

- 仅 Win10 19045；Win11/Server 未测（同 `2026-10-02-windows-schannel-whep-verify.md`）。
- 渲染输出（`vo=gpu` 到 ANGLE/OpenGL 的实际画面）和音频设备输出本次没测，只测 demux→解码→时钟。
- `whep_tamper_proxy.py` 在 Windows 上有缺陷：第一个会话结束后 `c2s` 线程因 UDP `WSAECONNRESET`（10054）崩溃，之后同一进程的新会话 ICE 超时。我每次测试前重启代理绕过，**没改代理**。
- 基线与 dist 的字节差（-335KB）未能精确归因到具体包版本。
- 没在 CI 上跑；`build-windows.sh` 只在本机验证。CI 要采用这套（n9.0.2/v0.41/libplacebo）需要另改 workflow。
- 只测了单会话；本次未做 whep 播放期间反复 create/destroy 的泄漏压测（冒烟的 5 次循环不含 WHEP）。
- `auto_features=disabled` 方案没做：v0.41 在本机 auto 模式下启用的特性只有 `d3d-hwaccel d3d9-hwaccel gl gl-dxinterop gl-win32 glob iconv libass libplacebo wasapi win32-desktop zlib` 等，几乎没有可再砍的项，预计收益很小（推断，未实测）。

## 交付清单

- `mova-libmpv/tools/whep-flavor/build-windows.sh`（LF，中文注释）：`MODE=base|whep`，步骤 `fetch dav1d ffmpeg plc mpv finish`，`WITH_WHEP=0` 可只打补丁不启用 whep（体积对照）。
- `mova-libmpv/tools/whep-flavor/smoke-windows.c`：`init` 循环与 `play <url> <秒>` 播放，打印 position、帧数与 WHEP/RTCP 日志。
- 补丁：ffmpeg `patches/ffmpeg-whep/0001–0010` 全部 apply（0007/0009 只改 mbedtls，Windows 不用，但不跳过，避免 0008 上下文依赖风险，无害）；mpv `patches/mpv-v041/0001/0003/0004`，0002（java vm）在 Windows 跳过。
- libplacebo：v7.360.0 最小静态（vulkan/d3d11/shaderc/lcms 等全关，clang 编），脚本对其 `meson.build` 改 `PL_STATIC`。
- 运行方式：`C:\tools\msys64\usr\bin\env.exe MSYSTEM=MINGW64 CHERE_INVOKING=1 MODE=whep TAG=whep WITH_WHEP=1 /usr/bin/bash -l tools/whep-flavor/build-windows.sh`（在 `mova-libmpv` 目录）。全量约 12 分钟（ffmpeg 占大头，20 核）。
