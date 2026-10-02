# libplacebo 体积评估的补丁与脚本（2026-10-01/02）

「mpv v0.41.0 / master + ffmpeg n9.0.2，带 libplacebo 但摘掉 `vo_gpu_next`」这次体积评估用到的补丁和脚本，
**留作证据，也是落地 T0.2/T0.4 的起点**。结论与数字见
[../../doc/plans/2026-10-01-whep-receiver.md](../../doc/plans/2026-10-01-whep-receiver.md) 的 T0.2 修订一节。

## 补丁

| 文件 | 作用 | 备注 |
|---|---|---|
| `b3-v041.patch` | v0.41.0：从 `video_out_drivers` 摘掉 `vo_gpu_next`，`meson.build` 去掉 4 个源文件，`options.c` 删掉 `gl_next_conf` 引用 | 不删 `gl_next_conf` 会留未定义符号，被 mpv 默认的 `--allow-shlib-undefined` 掩盖 |
| `c3-head.patch` | 同上，针对 master（评估时 HEAD `3186d369f9`） | master 无稳定 tag，每次升要重做 |
| `javavm-v041.patch` | media-kit 的 `mpv_lavc_set_java_vm`（Android 必需），针对 v0.41.0 | 评估时是手工移植的，**未在 Android 真机验证** |
| `javavm-head.patch` | 同上，针对 master | 同上 |
| `pin-n9-compat.patch.obsolete` | 钉死 mpv `78d43740f5` 对 ffmpeg n9.0.2 的兼容补丁（342 行） | **已作废**（决定改用 v0.41.0），仅留作"为什么不走钉死路线"的证据 |

## 脚本

脚本里写死了评估机的路径（`/root/w/mpvt/...`，WSL），**不能原样在别处跑**，落地时要参数化。

| 文件 | 作用 |
|---|---|
| `mk.sh` | 用统一口径编一个 mpv 变体并量 stripped 字节 |
| `plc.sh` | 编最小静态 libplacebo |
| `runall.sh` / `runall.out` | Linux 全部变体的批量脚本与它的输出（数字来源） |
| `and-deps.sh` / `and-plc.sh` / `and-mpv.sh` | Android arm64 API24（NDK r25c）的依赖、libplacebo、mpv 构建 |
| `and-deps-lto.sh` / `and-plc-lto.sh` / `and-mpv-lto.sh` / `runlto.sh` | 同上，整链 LTO 版 |
| `mapsum.py` | 汇总链接 map 文件，看各库实际占用 |
| `smoke2.c` | 软渲染冒烟：loadfile 并渲染帧 |
| `mpv.ver` | version script，只导出 `mpv_*` |

## 没存进来、但落地时要知道的

- **freetype 的 bz2 自动探测**：评估时直接改了 freetype 源码（`meson.build` 里把 bz2 探测段改成 `if false`），
  否则会因系统 bz2 造成 `BZ2_*` 未定义。这个改动**没有做成补丁**，在 WSL `/root/w/mpvt/eval/dl/freetype-VER-2-13-3`。
  落地时要做成补丁或找到正确的 meson 开关（`-Dbzip2=disabled` 被无视）。
- 评估产物与日志在 WSL `/root/w/mpvt/eval/`（`out-*.stripped.so`、`andout-*.stripped.so`、`andoutlto-*.stripped.so`、
  `conf-*.log`、`b-*/libmpv.map`），换机器就没了。
