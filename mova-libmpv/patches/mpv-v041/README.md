# mpv v0.41.0 补丁序列（WHEP flavor 用）

只用于 `*-whep` flavor（ffmpeg n9.0.2 + mpv v0.41.0），默认 flavor 仍是 n6.0.1 + 钉死 mpv，不吃这些补丁。
全部在干净的 v0.41.0（`41f6a64506`）上用 `git apply --check` 验证过，且按下表顺序依次 apply 无冲突。

| 序号 | 文件 | 作用 | 来源 |
|---|---|---|---|
| 0001 | `0001-vo-drop-gpu-next.patch` | 摘掉 `vo_gpu_next`（meson 去 4 个源文件、`vo.c` 去驱动项、`options.c` 去 `gl_next_conf`），省约 640KB | `tools/libplacebo-eval/b3-v041.patch` |
| 0002 | `0002-client-lavc-set-java-vm.patch` | 导出 `mpv_lavc_set_java_vm`（Android MediaCodec 绑 JavaVM 必需；Linux 上只是桩） | `tools/libplacebo-eval/javavm-v041.patch`（手工移植自 media-kit 补丁） |
| 0003 | `0003-stream-lavf-whep-nofile-demuxer.patch` | `stream_lavf.c` 对 `whep:` 照 `rtsp:` 特判（NOFILE demuxer 无 protocol 条目，不加则 `read_header` 到不了），共 17 行 | 本次由 `doc/notes/2026-10-02-t03-whep-feasibility.md` 的片段生成 |
| 0004 | `0004-stream-lavf-whep-http-aliases.patch` | 在 0003 之上让 `whep+http://`、`whep+https://` 也走同一条特判（配合 ffmpeg 的 whep demuxer，`whep://` 默认映射成 https，明文 http 必须用 `whep+http://`） | T1.2 追加 |
| 0005 | `0005-win-drop-mpv-rc.patch` | Windows 专用：`meson.build` 里 `mpv.rc`（exe 图标+manifest）改为仅 `cplayer=true` 时编，libmpv 去掉 ~274KB `.rsrc`。Android 脚本按名单挑补丁不吃它；Linux/Windows 的循环会打上（Linux 上 `if win32` 分支不进，无影响） | `doc/notes/2026-10-02-windows-shrink-research.md` §6.2（修正版） |
| 0006 | `0006-opengl-context-require-swap-buffers-for-fencesync.patch` | `ra_gl_ctx_submit_frame` 仅在 ctx 提供 `swap_buffers` 时才建 GLsync fence（libmpv render API 不提供，原先每帧泄漏一个永不删除的 fence，ANGLE 下约 9.6 MiB/min）。即上游 `f74adc42`（2026-01-23，Fixes #17217），已在 master、不在 v0.41.0（v0.41.0 之后无 0.41.x 补丁版，故只能打补丁） | 上游 cherry-pick，1 行 |
| 0007 | `0007-opengl-common-no-timer-query-on-angle.patch` | `mpgl_load_functions2` 在 `GL_RENDERER` 含 `ANGLE` 时不加载 `GL_EXT_disjoint_timer_query`，mpv 就不建 GPU 计时器（ANGLE+NVIDIA 下每帧 `glBeginQueryEXT` 在驱动堆里泄漏约 10 MiB/min，实测 10.07 -> 0.52）。代价：stats/`vo-passes` 没有逐 pass 耗时；非 ANGLE 的 GL 不受影响 | 自研，8 行 |
| 0008 | `0008-vd-lavc-stop-fallback-when-software-fails.patch` | `vd_lavc.c` 的 `reinit()`/`receive_frame()` 里 `do { force_fallback } while (!avctx)` 在“软解与 hwdec 是同一个解码器且打不开”时永远不退出（如 Android 无硬件 VP8：`vp8_mediacodec` 既是 hwdec 又是唯一解码器，日志 5 秒 4507 次 `Attempting next decoding method`，mpv 核心线程 100% CPU、主线程被同步调用堵死）。加 `&& ctx->use_hwdec`：落到软解（`use_hwdec==false`）仍失败就停，走正常的 “Decoder init failed”。hwdec 列表有限，仍会逐个尝试完。所有平台通用，对能正常打开的流无影响 | 自研，4 行；根因与对照见 2026-10-28 STG-AL00 排查（simpleperf 采样 + 源码逐行对应），**补丁本身未经重编真机验证** |

顺序要求：0001 与 0002 互不冲突，0003 独立，0004 依赖 0003，0005 独立（只动 meson.build 的 mpv.rc 一段）；0006 独立（只动 opengl/context.c，Windows/Android 都要，build-windows.sh 通配自动打，Android 由 apply-v041.sh 显式复制）；0007 独立（只动 opengl/common.c；Windows 通配自动打，Android 同样复制但因不是 ANGLE 而不生效）；0008 独立（只动 video/decode/vd_lavc.c；Windows/Linux 通配自动打，Android 由 apply-v041.sh / local-build-arm64.sh 显式复制，Apple 的 nix 名单未加，iOS/macOS 本轮不改）；按编号依次打即可。0003 的 `whep` 只在 libavformat 里有 whep demuxer 时才生效，没有时 `whep://` 会干净地返回 `err=-13`（实测）。

另一个同类补丁不在本目录：freetype 2.13.3 的 bz2 自动探测见 `../freetype-2.13.3/0001-meson-disable-bzip2-autodetect.patch`
（只有自建静态 libass 依赖链的 Android/iOS 路线需要；Linux 脚本用系统 libass，用不到）。

验证命令（在 mpv v0.41.0 源码目录里）：

```
for p in /path/to/patches/mpv-v041/*.patch; do git apply --check "$p" && git apply "$p"; done
```

升级 mpv 版本时这些补丁要重做，0001/0002 的 hunk 对 `meson.build`/`client.h` 的位置敏感。
