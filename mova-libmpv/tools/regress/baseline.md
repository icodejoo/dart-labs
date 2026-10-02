# 回归基线（T0.1，n6.0.1 现状，2026-10-02 实测）

> 纯测量，未改任何产物/CI/业务代码。测量对象是工作区 `mova/libmpv/` 下的真实文件
> （`git lfs ls-files` 标 `*`，即 LFS 内容已落地，不是指针）。测量时仓库 HEAD `7927f45`。
> 字节数用 `stat -c%s` 实测；"来源 commit"是该目录最后一次改动产物的 commit（`git log -1 -- <dir>`）。
> "来源 CI run"README 里只对部分产物有明确记载，查不到的写"未知"，没有推断。

## 1. 产物体积（实测）

| 产物 | 实测字节数 | sha256（前 16 位） | 来源 commit | 来源 CI run |
|---|---:|---|---|---|
| android arm64-v8a `libmpv.so` | **6,050,104** | 4026f0d798b347af | `83633e4`（2026-09-25） | 未知（README 称"2026-09-18 CI"产物，未给 run id） |
| android armeabi-v7a `libmpv.so` | 5,677,832 | 2cb067a062494496 | `cea74e1`（2026-09-25） | 未知 |
| android x86_64 `libmpv.so` | 7,732,664 | b6f0d2372d018a03 | `8898ced`（2026-09-25） | 未知 |
| android x86 `libmpv.so` | 6,190,732 | dac8ba947e4c0537 | `8750b1e`（2026-09-25） | 未知（README 称 run `35948800700`（2026-09-24）起 x86 产出真实 .so，未核实该 run 即本文件来源） |
| windows-x86_64 `libmpv-2.dll` | **14,075,392** | af5d571436236898 | `d070625`（2026-09-25） | 未知 |
| linux-x86_64 `libmpv.so` | **7,550,784** | d04c361527c68cd2 | `b5727d7`（2026-09-25） | 未知（README 称 2026-09-17 CI） |
| ios-arm64 `libmpv.dylib` | **5,741,680** | f69f53db9ea7b92f | `3972105`（目录改名提交；内容首次入库 `2403cc5`，2026-09-18） | `35312415642` 的 `ios` job（README 记载） |
| macos-arm64 `libmpv.dylib` | 7,398,112 | ef85656ac279aa3d | `3972105`（内容首次入库 `2403cc5`） | `35312415642`（README 记载 macOS movaslim 三架构） |
| macos-amd64 `libmpv.dylib` | 7,957,944 | 57bed05f4572ae5a | 同上 | 同上 |
| macos-universal `libmpv.dylib` | 15,377,120 | 2644ef306d915a85 | 同上 | 同上 |

完整 sha256 可用 `sha256sum mova/libmpv/*/libmpv*` 复算。

## 2. 与 README / 计划 §4 末行口径对照

| 项 | 文档里的数字 | 实测 | 差异与说明 |
|---|---:|---:|---|
| Android arm64 | 6,050,104（README 多平台表，2026-09-18 CI） | 6,050,104 | **一致** |
| Windows | 14,033,920（README 第 73/79 行，clang，2026-09-24） | 14,075,392 | **差 +41,472 字节**。README 数字是 2026-09-24 记录，仓库产物是 2026-09-25 的 `d070625` 入库，两者不是同一次构建；两次间具体改了什么**未核实** |
| Linux | 7,550,784（README，2026-09-17） | 7,550,784 | **一致** |
| iOS | README 两处：6,534,448（第 44 行，audio/protocol 白名单收窄后）与 5,741,680（第 45 行，落进 dist/） | dist 实测 **5,741,680** | dist 里的是 5,741,680，与第 45 行一致。6,534,448 是更早一次 run 的记录（该处未写 run id），之后产物更小。两个数字来自不同 run，较小者是当前 dist；"为何更小"推测是后续继续瘦身，**未核实**。**建议以 dist 实测 5,741,680 作为 iOS 基线**；CLAUDE.md 里"6,534,448，反超 Android 6.52MiB"那句已过期 |
| iOS 对 Android 的比较 | CLAUDE.md："iOS 6,534,448 ≈ 6.23MiB 反超 Android 6.52MiB" | iOS 5,741,680 vs Android arm64 6,050,104 | 结论方向不变（iOS 更小），但数字应更新；注意 Android 的 6.52MiB 是 2026-08-06 旧定稿，现为 6,050,104 ≈ 5.77MiB |

## 3. 检查脚本（本目录）

| 脚本 | 覆盖 | 运行方式 | 对现有产物结果（2026-10-02） |
|---|---|---|---|
| `check-symbols-android.sh` | 四 ABI：`mpv_lavc_set_java_vm`、`dav1d_open`、dav1d_* 计数、公开 API、4 个 `*_mediacodec` 解码器名、libdav1d 名、VP8/MJPEG 缺席、协议名、许可 | Git Bash（自动找 NDK `llvm-nm`）或 WSL（GNU nm），两种都跑过 | PASS=52 FAIL=0 SKIP=4（SKIP 为许可串，见下） |
| `check-symbols-linux.sh` | 公开 API、libdav1d（定义或 NEEDED）、协议名、许可 | WSL | PASS=4 FAIL=0 SKIP=1 |
| `check-symbols-windows.sh` | 导出表公开 API、导入表自包含、configure 串（许可/协议白名单/schannel）、libdav1d 名 | WSL（需 objdump） | PASS=15 FAIL=0 SKIP=2 |

公共函数在 `_common.sh`。判据复用 `build-mova-libmpv.yml` 各 job 的 "Strip and verify"（公开 API 清单、`dav1d_open` 或 NEEDED、导入表禁 `libstdc++/libgcc_s/libwinpthread`、`License: LGPL version 2.1`、`https/tls/rtmps`）。

### 3.1 脚本的已知局限（如实）

- **`*_mediacodec` 与 VP8/MJPEG 是字符串代理，不是符号证据**。已发布产物 strip 后这些符号不在 dynsym 里（CI 对 `*_mediacodec` 本来也只是 warning）。脚本改用解码器名字符串（`h264_mediacodec` 等）和 ffmpeg 源路径断言串（`libavcodec/vp8.c`、`mjpegdec.c` 不存在）判断。`mjpeg`、`vp8` 这类裸字串在产物里仍存在（mkv 的 `V_MJPEG`/`V_VP8` codec id、`mjpeg2jpeg` bsf 等），所以**不能**用裸字串判缺席。
- **许可检查**：Windows 产物内嵌了 configure 串与 `license: LGPL version 2.1 or later`，可直接核对；**Android/Linux 产物没有内嵌许可串，脚本标 SKIP（未验证）**，需构建时的 `ffconf.log`（传 `FFCONF_LOG=<路径>`，严格按 CI 的 `License: LGPL version 2.1` grep）。本机找不到任何 `ffconf.log`。
- **协议列表**：Windows 查 configure 串里的 `--enable-protocol` 白名单（较可靠）；Android/Linux 只能查协议名字符串是否存在（代理，不等于已注册）。Linux 产物里 `tls/tcp/http` 不作独立字串，只断言 `https/rtmps/rtmp`，原因**未深究**。
- **Windows 内部符号**（`dav1d_open`/`ass_*`/`hb_shape`/`FT_Init_FreeType`）：CI 是 strip 前检查，已发布 dll 已 strip，脚本标 SKIP，**未验证**。若要验证，需在 CI strip 前或对未 strip 构建产物跑。
- **Windows 的 "mpv 用 clang"、"冒烟连续 5 次零崩溃"、`libmpv.dll.a` 重生成**：不是产物静态属性，脚本不覆盖，**未验证**。
- Android 的"APK 内 `.so` sha256 与 `libmpv/<abi>/` 一致"、"x86 非静态库"需要 APK/构建过程，脚本仅用 ELF 头 + 导出符号侧面保证 x86 是动态库（静态库没有 dynsym，`mpv_lavc_set_java_vm` 检查会失败）。
- iOS/macOS（§7.1 末行）**脚本未写**：没有 Mac，`otool -L` 不可用，计划里也标"若 Q4 选同步升"才需要；本基线仅记录字节数。
- 本机 Windows 没有 `nm`/`objdump`（Git Bash PATH 里没有）。Android 脚本用 NDK 28.2.13676358 的 `llvm-nm.exe`，Linux/Windows 脚本用 WSL 里的 GNU binutils（`nm`/`readelf`/`objdump`，WSL2 Linux 6.18，x86_64）。

## 4. 关键数字速查（升级 n9.0.2 后对照用）

- Android arm64 6,050,104 / armv7 5,677,832 / x86_64 7,732,664 / x86 6,190,732
- Windows 14,075,392；Linux 7,550,784；iOS 5,741,680
- Android 每个 ABI 导出符号数：arm64 451、armv7 441、x86_64/x86 各 292；其中 `dav1d_*` 均为 19 个（与 README 定稿记录 19 一致）
- Windows 导出符号 108；Linux dynsym 54（均含 10 个公开 API）；Linux NEEDED 15 个（动态依赖系统库，非自包含）
- Windows 导入 DLL 18 个，无 MinGW 运行时
