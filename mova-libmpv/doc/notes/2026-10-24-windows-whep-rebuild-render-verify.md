# Windows 重建（含 0011）与渲染/稳定性实测

日期：2026-10-24。机器：Windows 11 Pro 10.0.26100，真实桌面（1707x1067 显示器，RTX 4060 Laptop，Realtek 声卡）。分支 `feat/whep-receiver`。
"实测"是本机跑出来的，"推断"单独标注。证据原件在 `D:\tmp\win\ev\`（不入库）。

## 结论

- 带 0011 的 Windows `libmpv-2.dll` 在本机 MSYS2 重建成功：**10,875,904 字节**（strip 后）。0011 对 chunked answer 在 Windows(SChannel) 上实锤有效，Content-Length 不退化，NACK 不退化。
- Windows `vo=gpu`（OpenGL 4.6 / RTX 4060）+ `ao=wasapi` 真实出画出声，截图与端点峰值为证。
- 稳定性：5 轮起播/停止 + 660s 长跑，无崩溃、无内存/句柄增长、0 丢帧。
- 修了 `whep_tamper_proxy.py` 在 Windows 上第一个会话后 `WSAECONNRESET` 崩溃的缺陷。
- **没做成**：mova/example 的 Flutter Windows 端（media_kit render API / ANGLE 路径）没能构建（见"未解决"），所以产品实际用的 ANGLE 渲染路径仍未测。

## 1. 重建

- 本机原先没有 MSYS2（上次的 `C:\tools\msys64` 是另一台机器）。装在 `D:\msys64`（msys2 nightly sfx，aria2 3.7MiB/s），`pacman -Syu` 后装 CI 同款包 + `meson`/`lld`/`libunibreak`。
- 工作树是 CRLF：拷 `patches/`、`tools/` 到 `D:\tmp\lf\mova-libmpv\` 并 `sed 's/\r$//'`，在拷贝里跑 `MODE=whep WORK=/d/whep-win/libmpv bash tools/whep-flavor/build-windows.sh`，仓库文件行尾未动。
- 坑：Windows 全局 git 配 `http.sslBackend=schannel`，MSYS git 不认，clone 直接失败。构建时设 `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1` 解决。
- 0001–0011 全部按序 `apply` 成功；`finish` 的 S 档判据、符号检查、自包含检查全过（这也补上了 2026-10-03 笔记里"S 档判据没在全新环境跑通"的缺口）；`gendef` 不在默认包里，导入库步骤"非致命失败"，不影响产物。全程约 14 分钟（含源码克隆）。
- 体积：

| 构建 | 字节 |
|---|---|
| 2026-10-02 pre-S 档 whep（任务书里的"上次"） | 14,510,592 |
| 2026-10-03 本机落地 S 档 | 10,871,808 |
| 仓库现有 `mova/libmpv/windows-x86_64-whep`（CI，**不含 0011**） | 10,873,856 |
| **本次（S 档 + 0011）** | **10,875,904** |

  相对 14,510,592 是 -3,634,688（-25.0%），这是 S 档瘦身的效果而不是 0011 的。相对 CI 现有 DLL +2,048（**推断**：MSYS2 滚动快照版本差异；0011 本身只加一个 http 选项，增量应在几十字节量级，没单独拆）。sha256 前缀：新 `25d621eb…`，CI 旧 `9be386b4…`。产物：`D:\whep-win\libmpv\whep\out\libmpv-2.dll`。**没有替换仓库里的任何 DLL**，等主会话决定。

## 2. 信令与 NACK 回归（libmpv 经 `smoke-windows.exe`，MediaMTX v1.21.1 Windows 版 + 同一推流源）

| 场景 | 配置 | 结果（实测） |
|---|---|---|
| chunked 大 answer | 默认 `webrtcIPsFromInterfaces: true`，`curl -i` 确认 `Transfer-Encoding: chunked` | **新 DLL**：`Got answer (2205 bytes)`，出流，视频 packets=736 lost=0，音频 591 lost=0 |
| Content-Length | `webrtcIPsFromInterfaces: false`，`Content-Length: 1218` | **新 DLL**：`Got answer (1301 bytes)`，DTLS 407ms，视频 747 包 lost=0 |
| A/B：CI 旧 DLL（无 0011）打 chunked | 同上 | `Reading WHEP answer failed: I/O error`，`end-file error=-17`（原样复现 0011 修的缺陷） |

NACK/丢包（经修好的代理 lossy 模式，Content-Length 配置，视频+音频同比例丢，种子固定）：

| 档位 | 时长 | 视频 packets | 最终视频 lost | nack_seqs_sent | rtx_recovered | giveup | pli_sent | 音频 lost |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 10-02 基线 3/2/1/1（LOSS/SWAP/DUP/CORRUPT）| 12s | 746 | 0 | 35 | 35 | 0 | 2 | 28 |
| 本次同配置 | 12s（窗口 ~10s） | 731 | 0 | 31 | 31 | 0 | 3 | 29 |
| 纯 5% 丢 | 30s | 1786 | 0 | 84 | 78 | 0 | 3 | 63 |
| 纯 10% 丢 | 30s | 1863 | 0 | 212 | 187 | 0 | 2 | 150 |

视频最终 lost 全为 0，与 10-02 基线（lost=0）一致，无退化；音频不发 NACK 属设计。`auth_fail=6` 对应注入的损坏包。（10-02 没有 5%/10% 纯丢的 Windows 数字，这两档仅作新增参考。）

## 3. 渲染链路（`vo=gpu` + `ao=wasapi`，mpv 自带窗口，`smoke-windows.exe play … gpu`）

- 日志：`Detected desktop OpenGL 4.6`、`d3d11va_vld` 可用（本次 `hwdec-current=no`，软解 h264），`AO: [wasapi] 48000Hz stereo 2ch float`；`current-vo=gpu`，`current-ao=wasapi`，`audio-codec-name=opus`，640x360，`avsync=0.000004`，播 9s time-pos 推进 9.0s。
- 画面：`mpv_window_shot.png`（`screenshot-to-file … window`，640x360 testsrc2 色条正确，角上叠加的时间码/帧号）和 `desktop_shot.png`（桌面截图，可见标题 `whep - mpv` 的真实窗口在显示器上）。
- 声音：WASAPI 默认渲染端点峰值计（IAudioMeterInformation，`peak.ps1`）空闲 2.3e-10，播放时 **0.116**（推流是 440Hz 正弦），即确实在往声卡送数据。（耳朵听没法在无人值守时做，峰值计是替代证据。）
- 没发现渲染/音频问题，无需改补丁或配置。

## 4. `whep_tamper_proxy.py` 缺陷修复

- 复现：旧代理（`proxy_old.py`）跑 2 个会话，第 1 个 OK，第 2 个无任何出流，代理 `c2s` 线程以 `ConnectionResetError: [WinError 10054]` 退出（`cli.recvfrom`）。根因：Windows 上 UDP 套接字对发往已关闭端口的包会把 ICMP 不可达变成下一次 `recvfrom` 的 WSAECONNRESET。
- 修复（`tools/whep-flavor/whep_tamper_proxy.py`）：`c2s`/`s2c` 的 `recvfrom` 和 `sendto` 包 `try/except (ConnectionResetError, ConnectionAbortedError)`，吞掉后 `continue`，保持服务。另加：每个会话 DELETE 时打印一行 `relay FINAL {...}`（Windows 上收不到 SIGTERM 处理器，原来的 FINAL 拿不到）。没有用 `SIO_UDP_CONNRESET`（Python `socket.ioctl` 不支持这个控制码，试过报 `ValueError`）。
- 验证：同一代理进程连续 3 个会话（0% 丢）全部出流；连续 5 个会话（2% 丢）全部出流；`lossy → fp → lossy → ok → lossy` 混合序列：fp 被 `DTLS peer certificate fingerprint does not match the answer; refusing` 拒绝，其余 4 个全部出流，代理全程存活。
- 备注：PowerShell 里 `Start-Process python`（WindowsApps 别名）起的是 stub，`Kill()` 杀不掉真正的 `python3.13.exe` 子进程，残留进程占着 18100/18201/18199 会让下一个代理起不来或静默用旧代理（我中途踩到一次，现象是所有会话 POST EOF）。测试脚本改用真实 exe 路径。

## 5. 稳定性（`smoke-windows.exe stress`，同一 mpv 句柄；`vo=gpu` + `ao=wasapi`，chunked 配置的 MediaMTX）

5 轮起播/停止（每轮 8s）：5/5 轮 time-pos 推进，decoder/vo 丢帧 0，每轮视频 lost=0；停止后：

| 轮 | after-stop 私有内存 | 句柄 |
|---|---:|---:|
| 1 | 105.4 MiB | 411 |
| 2 | 105.9 | 411 |
| 3 | 106.1 | 411 |
| 4 | 104.4 | 409 |
| 5 | 104.3 | 409 |
| destroy 后 | 102.3 | 405 |

起播中峰值 150–157 MiB 每轮一致。无增长趋势。

660s（11 分钟）长跑，单会话：time-pos 657.7，decoder/vo 丢帧 **0**、vo-delayed 0；视频 41,414 包 lost=0 frames=16,444 dropped_frames=0 auth_fail=0；RR 发送 647 次，pli_sent=3，无 NACK（无丢包）。21 个 30s 采样点：私有内存 153.1 → 152.6~155.0 → 153.1 MiB（持平），句柄 537 → 523（略降），stop 后 103.4 MiB/404 句柄。无崩溃无泄漏。

## 6. 随手改动（仓库内）

- `tools/whep-flavor/whep_tamper_proxy.py`：见 §4。
- `tools/whep-flavor/smoke-windows.c`：新增 `SMOKE_AO`（选 ao，缺省 null）、起播 6s 后一次性打印 vo/ao/解码属性并可按 `SMOKE_SHOT=路径` 截图、新模式 `stress <url> <轮数> <每轮秒数> [vo]`（输出丢帧与进程私有内存/句柄），日志关键词增加 wasapi/d3d11/OpenGL 等。编译需加 `-lpsapi`。
- 未提交，未改计划文档，未替换任何二进制。

## 未解决 / 未做

1. **Flutter 路径未测**：想用 `mova/example`（fvm flutter 3.47.1）在拷贝里换入新 DLL 构建 Windows 桌面端，`flutter build windows` 在 CMake 阶段失败：`.plugin_symlinks/*/windows` "not an existing directory"。原因是 Dart 在本机创建的目录符号链接目标被写成 `\\?\C:\…\` 形式，`cmd /c dir` 通过它也报找不到路径（`fsutil reparsepoint query` 可见）；手工改成 junction 后 flutter 自己重建 `.plugin_symlinks` 时又删除失败。未深究（时间盒），已清掉 `D:\tmp\mc` 拷贝。所以 media_kit `Video` 控件、ANGLE 的 OpenGL ES 渲染路径（含上次瘦身掉的 ANGLE dll 是否够用）依然是"未测"。
2. 只测了 `vo=gpu`（桌面 OpenGL + wgl 互操作），`hwdec=no`；d3d11va 硬解在这条链路上本次没开（`hwdec` 选项没传），未测。
3. 音频只有峰值计证据，没做音画同步的主观判断（`avsync` 数值 ~0 可参考）。
4. 仓库里 CI 注入的 Windows DLL（10,873,856）**不含 0011**，chunked 默认配置的 MediaMTX 下会直接失败（本次 A/B 已证）；需要重新触发 CI 或按主会话决定替换。
5. https 信令（TLS 层 chunked）仍未测，同上轮结论。
6. 只测 Win11 26100 一台；Win10 之前 19045 的结论没重跑。
