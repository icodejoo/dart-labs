# Windows S 档瘦身落地（build-windows.sh + ANGLE 随包清单）

日期：2026-10-03。把 `2026-10-02-windows-shrink-research.md` 的 S 档和 `2026-10-02-windows-angle-shrink.md` 的 ANGLE 裁剪落进仓库。**均未提交、未触发 CI。** 约定：**实测** = 本机跑出来的；**推断** = 没测的判断。

## 1. 改动

| 文件 | 改动 |
|---|---|
| `tools/whep-flavor/build-windows.sh` | 新增 `SLIM`（whep 模式默认 1，base 恒 0）；新步骤 `winiconv freetype harfbuzz libass`（钉 tag：win-iconv v0.0.10 / freetype VER-2-14-3 / harfbuzz 14.4.0 / libass 0.17.5）；ffmpeg 加 `--disable-d3d12va --disable-bzlib --disable-lzma` 与 `-DWINICONV_CONST=`；`CPATH`/`LIBRARY_PATH` 指向前缀；mpv 加 `-I/-L` 前缀；补丁循环自动吃 0005；`finish` 里加 S 档判据（见 §4）。**没加 gcc `-Oz`，mpv 仍用 clang。** |
| `patches/mpv-v041/0005-win-drop-mpv-rc.patch` | mpv.rc 仅 `cplayer=true` 才编。实测在干净 v0.41.0 上 `git apply --check` 通过（LF 工作树与 autocrlf=true 的 CRLF 工作树都通过），构建里在 0001/0003/0004 之后打上无冲突 |
| `patches/mpv-v041/README.md` | 加 0005 一行 |
| `.github/workflows/build-mova-libmpv-whep.yml`（windows-whep） | pacman 去掉 libass/freetype/harfbuzz，加 `libunibreak`（libass 必需、此前由 libass 包带入）；加依赖说明注释 |
| `mova/packages/media_kit_libs_windows_video_slim/windows/CMakeLists.txt` | 随包清单去掉 zlib/vk_swiftshader/vulkan-1 **和 d3dcompiler_47**（用户已拍板最低 Win10），只留 libmpv-2、libEGL、libGLESv2；注释写了依据、前提、风险 |

## 2. 实测字节

| 版本 | 字节 |
|---|---:|
| whep 基线（本机，未瘦身） | 14,510,592 |
| 调研 S 档（只含 d3d12va） | 10,936,320 |
| **本次落地（S + bzlib/lzma，无 -Oz）** | **10,871,808**（相对基线 −3,638,784，−25.1%；比调研 S 档小 64,512） |

与调研的差异：多了 `--disable-bzlib --disable-lzma`（调研估约 −64KB，吻合）；没有 `-Oz`；预期值"约 10.87MB"（调研 §4 的推断）与实测一致。导出符号 54 个（`check-symbols-windows.sh` 之外用 Export Table 计数），与基线相同。无 `.rsrc` 段（基线有）。

## 3. 回归（实测，本机 Windows 10 19045）

- `check-symbols-windows.sh`：PASS=15 FAIL=0 SKIP=2（脚本的"导出符号数 3495"仍是旧缺陷，不可信）。
- `smoke-windows.c`：create/initialize/terminate_destroy ×5 fails=0。
- mp4(h264+aac)、HLS(本地 http)、AV1 8bit/10bit、HEVC 10bit、VP9+Opus：time-pos 推进正常（3.0–3.7s），`hwdec=d3d11va-copy` 下 h264/hevc10 生效。
- 字幕：外挂 8 种编码（big5/sjis/cp1251/euckr/cp1252/gb18030/utf16le/utf8bom）sub-text 全部正确；GBK、ASS 文本正确；中日韩阿拉伯 ASS 经 `vo=image` 渲染的 PNG md5 = `82a224fd545a83890bc69b2e3d24c6ee`，**与调研基线/S 档的 md5 相同**。
- WHEP（Windows 版 MediaMTX，18889/18189/18554；只按自己 PID 停）：直拉 12s，time-pos 到 10.36s、约 259 帧、drop=0；经 `whep_tamper_proxy.py` lossy（LOSS3/SWAP2/DUP1/CORRUPT1，端口 18888/18201）12s，time-pos 到 10.2s、255 帧、drop=0，中继计数 `rtp 1349, drop 55, swap 18, dup 18, corrupt 8`（真的丢了 55 个包仍继续播）。**没抓 RTCP/NACK 的逐行日志**（smoke 的日志过滤在本次输出里没出现这些行），所以只能说"丢包下仍正常出帧"，不声称 NACK 次数。代理结束时报了已知的 WinError 10054（笔记 windows-libmpv-whep-build 记过的缺陷），未改代理。
- ANGLE（变体 E，真实 example 构建）：`flutter build windows --release` 后用 `cmake --install` 的 DESTDIR 方式装到 `C:\Users\jelon\whep-win\angle-test\E2\`，目录里 DLL 只有 libmpv-2/libEGL/libGLESv2（无 d3dcompiler/zlib/vulkan/swiftshader）；进程模块里 `d3dcompiler_47.dll` 从 `C:\Windows\SYSTEM32` 加载。内嵌/全屏/App 内小窗三阶段截屏饱和色占比 0.678/0.678/0.659，与基线变体 A 的 0.677 同量级，肉眼看小窗截图画面正常；日志里 SizeChange 640x360、position 推进、fs/mini 状态位正确。临时 verify 入口 `example/lib/main_angle_shrink_verify.dart` 已删。

## 4. CI 上要注意的点

- **S 档判据的一个坑（本次踩到并修了）**：最初写的 `grep -v prefix | grep -q libiconv.a` 在 `set -o pipefail` 下会因 `grep -q` 提前退出导致上游 SIGPIPE，判据永远不触发。现在改成先取变量再判空，并且只看**归档成员**行（`libxxx.a(`），因为 map 里还有一行 `LOAD C:/.../mingw64/lib/libiconv.a`，只是 ld 列了命令行归档、没有成员被链入，按文件名 grep 会误报。离线对这份真实 map 复核：被禁依赖成员数全为 0，win-iconv 成员 488 个；对未瘦身基线 map 同判据命中 25 处（判据确实能触发）。**修复后的 `finish` 没能在本机再完整跑通一遍**：重跑时 `finish` 的 `find $PREFIX -iname libmpv*.dll` 找到的是上一次已被 `strip` 的文件，符号检查报缺 `FT_Init_FreeType`/`fribidi_...`（strip 后不可见，是重跑假象，不是产物问题），同时把 `libmpv-2.unstripped.dll` 覆盖成了已 strip 的副本。结论：判据代码只做了离线逻辑复核，**需要 CI 全新跑一遍确认**。
- **CPATH 判据**：meson 的 `dependency('iconv')` 不看 pkg-config，全靠 `CPATH/LIBRARY_PATH`；若 runner 上这两个变量被覆盖或路径形式变了，libass/mpv 会悄悄选 `/mingw64` 的 GNU libiconv，体积不报错只是变大，由上面的判据兜底（会 exit 1）。
- **MSYS2 版本漂移**：剩下 fribidi/libunibreak/zlib 仍随 runner pacman 滚动；基线 CI 与本机差 32KB（14,542,848 vs 14,510,592），预期新档位同样有几十 KB 漂移。`pip meson==1.3.2` 对 freetype 2.14.3/harfbuzz 14.4.0/libass 0.17.5 的 meson.build 是否够新：**本机用的是 MSYS2 自带 meson**，未用 1.3.2 验证（推断有风险，CI 首跑若 configure 报 meson 版本过低要先看这里）。
- 源码构建需联网：win-iconv(GitHub)、freetype(gitlab.freedesktop.org)、harfbuzz、libass；本机构建时源码是从调研目录拷贝进缓存的（`s-tier/src`），**脚本里的 `clone_tag` 联网路径本次没有真跑**。CI 额外耗时未测。
- 本次本机构建没有 `libmpv-2.def`/`libmpv.dll.a` 的重新生成核对：`out/` 里有，但是否与现 `windows-devlib/libmpv.dll.a` 一致未比。

## 5. 其他
- 验证中把 `cmake --install` 不带 DESTDIR 运行了一次，**覆盖了 `C:\Program Files\mova_example`**（装进去的是临时 verify 构建；该目录此前就已被上一轮验证构建覆盖过）。之后改用 DESTDIR 隔离。
