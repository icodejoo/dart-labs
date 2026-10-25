# libmpv GLsync fence 泄漏：证实、上游修复、补丁与实测（结论：fence 泄漏真实存在，但不是 9.6 MiB/min 的来源）

日期：2026-10-25。机器：Windows 11 Pro，RTX 4060 Laptop，真实桌面。证据原件在 `D:\tmp\gl13\`（`fence_evidence.log`、`gbefore/gafter/gafter_nb.csv`，不入库）。"实测"为本机跑出，"推断"单独标注。

## 结论

1. **源码分析的机制被证实**：mpv v0.41.0 的 libmpv render 路径确实每渲染一帧新建一个 GLsync 且永不删除（`num_vsync_fences` 随帧数严格线性增长，`swap_buffers=NULL`）。
2. **上游已修，修复不在 v0.41.0**：提交 `f74adc42`（2026-01-23，"opengl/context: require swap_buffers param for FenceSync"，Fixes mpv#17217），在 master，领先 v0.41.0 113 个提交；v0.41.0 是当前最新 tag，没有 0.41.x 补丁版，只能打补丁（新增 `patches/mpv-v041/0006-*.patch`，与上游同一行改动）。
3. **但它不是 Windows 渲染内存线性增长的主因**：打上 0006 重编 DLL 后，旧 ANGLE v1.0.1 + 硬件渲染 + WHEP 720p30 的私有内存斜率没有下降（17.9 → 19.8 MiB/min，在噪声范围内同量级）。去掉后向缓冲后仍约 10 MiB/min。主因仍是 ANGLE v1.0.1 自身（见 `2026-10-24-windows-render-memory-growth.md`）。
4. 旁证：此前 `whep_emu`（新 ANGLE + **未修补的** v0.41.0 libmpv，每分钟同样新建约 1700 个 fence）930s 私有内存仅 +4 MiB。fence 本身几乎没有驻留成本，换 ANGLE 才是修复。

## 1. fence 数量线性增长（实测）

构建 `D:\whep-win\libmpv13\whepdbg\out\libmpv-2.dll`：0001/0003/0004/0005 + 一个临时调试补丁（在 `ra_gl_ctx_submit_frame` append 之后往文件追加一行 `num_vsync_fences`，**不入库**），不含 0006。最小 app（`D:\tmp\w14\app`，旧 ANGLE v1.0.1，硬件渲染，WHEP 1280x720@30，60s）：

```
DBGFENCE num_vsync_fences=1 swap_buffers=0
DBGFENCE num_vsync_fences=2 swap_buffers=0
DBGFENCE num_vsync_fences=3 swap_buffers=0
...
DBGFENCE num_vsync_fences=1716 swap_buffers=0
DBGFENCE num_vsync_fences=1717 swap_buffers=0
```

1717 行 / 60s，等于 30fps 的渲染帧数；`swap_buffers=0` 即 `p->params.swap_buffers == NULL`，正是 libmpv 路径。

## 2. 上游修复

`f74adc42`（作者说明）：8854c742 与 5ae0e0ff 去掉外部 swapchain API 后，vo_libmpv 原本靠它跳过 `gl->FenceSync`，这个逻辑被漏掉，于是 libmpv 路径泄漏 fence（`ra_gl_ctx_swap_buffers` 从不被调）。修复是一行：`if (gl->FenceSync && p->params.swap_buffers)`。通过 GitHub API 的 commit 页与 compare（v0.41.0...f74adc42：ahead 113）确认；v0.41.0 之后没有新 tag。

## 3. 补丁与构建链

- 新增 `patches/mpv-v041/0006-opengl-context-require-swap-buffers-for-fencesync.patch`（1 行，对 v0.41.0 `git apply --check` 通过），README 总表已更新。
- `build-windows.sh`：`patches/mpv-v041/*.patch` 通配，自动打 0006（只更新了头部注释）。
- Android：`apply-v041.sh` 是显式列表，已把 0006 加进复制命令（0001/0002/0006）；`local-build-arm64.sh` 同步加了 0006。e2e-arm64.sh 经由 apply-v041.sh，自动带上。**Android 没有重编、没有真机验证**（见局限）。
- Windows 重编：`D:\whep-win\libmpv13\whep\out\libmpv-2.dll`，ffmpeg 0001-0012 + mpv 0001/0003/0004/0005/0006，10,875,904 字节（与旧 DLL 同大小；日志确认 12+5 个补丁按序全部打上，约 6 分钟）。未覆盖仓库内任何 DLL。

## 4. 私有内存斜率（实测）

条件：旧 ANGLE v1.0.1（`libEGL 472,904B / libGLESv2 7,414,088B`），硬件渲染，WHEP `whep+http://127.0.0.1:38889/test/whep`（MediaMTX，ffmpeg testsrc2 1280x720@30 1.5Mbps + opus），660s，15s 采样，斜率为 t≥60s 的最小二乘。采样脚本 `D:\tmp\w14\sampler.ps1`。

| 编号 | libmpv-2.dll | 参数 | 私有 65s → 末 (MiB) | 斜率 MiB/min |
|---|---|---|---|---|
| gbefore | 旧 DLL（`D:\tmp\win2\slim_pkg`，无 0006、无 0012） | 默认 | 368.1 → 550.6 | 17.9 |
| gafter | 新 DLL（含 0006、0012） | 默认 | 360.5 → 539.1 | 19.8 |
| gafter_nb | 新 DLL | `demuxer-max-back-bytes=0;demuxer-seekable-cache=no`（594s） | 369.5 → 457.7 | 10.0 |

- 修补前后斜率没有改善，预期的 <1 MiB/min **不成立**，0006 不能作为该泄漏的修复。
- 分解：去掉后向缓冲后约 10 MiB/min 残留，与 10-24 笔记的"ANGLE 约 10 + 后向缓冲 6~7"一致（本次 720p30 总量略高于当时 360p25 的 17）。句柄稳定（1590→1594 / 1722 / 1807），线程稳定。
- 注意：gbefore 与 gafter 的 DLL 除 0006 外还差 0012（DTLS passive），与内存无关；没有单独做"仅差 0006"的对照，但 gafter 本身没降已足以否定。
- 没有做 UMDH/ETW：本机没有 umdh/gflags/windbg，只有 `wpr.exe`；既然已证伪，按任务书停在这里，没有继续试错。

## 5. 未做 / 局限

- Android arm64 重编与真机内存对比：任务书要求"成立才做"，Windows 上不成立所以没做。Android 无 ANGLE，走驱动自带 GLES，fence 在 Adreno/Mali 上的驻留成本未知（**推断**可能与 ANGLE 不同）；0006 对 Android 是无害的正确修复，下次重编 Android 时自动带上，届时可顺手做一次 `dumpsys meminfo` 前后对比。
- 起播/停止 5 轮、截图、chunked 回归：未专门重跑。上面三次长跑里新 DLL 经 MediaMTX（`webrtcIPsFromInterfaces: true`，多候选）全部起播并连续出流 660s/594s 无丢帧；这些不能替代 5 轮起播停止。因为 0006 不会作为 Windows 内存修复进 DLL，没有必要再做。
- 既然 0006 无害且是上游修复，是否随下次重编进库由主会话决定；它对内存问题没有帮助，不要在计划里把它记为修复。

## 6. 建议

回到 ANGLE 方案（`2026-10-24-windows-render-memory-growth.md` 的建议：换 2025-08 之后的 ANGLE，并解决 117+ 不出画的问题），后向缓冲用 `demuxer-max-back-bytes` 限制。
