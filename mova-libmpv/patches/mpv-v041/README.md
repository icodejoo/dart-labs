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

顺序要求：0001 与 0002 互不冲突，0003 独立，0004 依赖 0003，0005 独立（只动 meson.build 的 mpv.rc 一段）；按编号依次打即可。0003 的 `whep` 只在 libavformat 里有 whep demuxer 时才生效，没有时 `whep://` 会干净地返回 `err=-13`（实测）。

另一个同类补丁不在本目录：freetype 2.13.3 的 bz2 自动探测见 `../freetype-2.13.3/0001-meson-disable-bzip2-autodetect.patch`
（只有自建静态 libass 依赖链的 Android/iOS 路线需要；Linux 脚本用系统 libass，用不到）。

验证命令（在 mpv v0.41.0 源码目录里）：

```
for p in /path/to/patches/mpv-v041/*.patch; do git apply --check "$p" && git apply "$p"; done
```

升级 mpv 版本时这些补丁要重做，0001/0002 的 hunk 对 `meson.build`/`client.h` 的位置敏感。
