# T0.2 真实 flavor 复核（Linux x86_64，WSL）

日期：2026-10-02。计划：[../plans/2026-10-01-whep-receiver.md](../plans/2026-10-01-whep-receiver.md) T0.2。
只记结论与证据，spike 代码不入库（目录 WSL `/root/w/t02`，换机器即失）。

## 0. 口径（先看这个）

- 「真实 flavor」= `.github/workflows/build-mova-libmpv.yml` 的 `linux` job 的 ffmpeg configure 参数原样
  （openssl、dav1d、白名单 decoder/demuxer/protocol/bsf/parser、`-fvisibility=hidden`、`--gc-sections`），
  mpv 参数取该 job 的 meson 参数再加 `-Dgl=enabled -Dplain-gl=enabled`。
- **不是** Android/Windows/iOS flavor（`flavors-mova-slim.sh` 是 Android 交叉编译脚本，本机无 NDK，未跑）。
  Android 的 `--disable-vulkan`、mediacodec、`--enable-lto` 等差异本次**未复核**。
- 环境：WSL Ubuntu、gcc 15.2、meson、ffmpeg 与 mpv 全是本次从 `n9.0.2` / `v0.41.0` tag 现编；
  libass/dav1d/openssl/zlib 用系统动态库（和 linux job 一样），libplacebo 7.360.0 静态自编。
- 体积全部是 `strip --strip-all` 后的 `libmpv.so.2.x` 字节数，**只能在本表内互相比较**，不能和仓库里 Android/iOS 的数字比。

## 1. n9.0.2 configure：被改名/移除的选项（实测）

用 linux job 的整条 configure 参数跑 n9.0.2，**只报 1 条错**：

| 选项 | n9 的反应 | 处理 |
|---|---|---|
| `--disable-postproc` | `Unknown option "--disable-postproc"`，configure 直接退出 | 删掉这一项（libpostproc 在 n8 移除） |

其余参数（`--disable-symver`、`--enable-small`、白名单 decoder/encoder/parser/demuxer/protocol/bsf、`--enable-libdav1d` 等）原样通过。
删掉后 configure rc=0，`License: LGPL version 2.1 or later`（job 里 `grep 'License: LGPL version 2.1'` 的检查仍能过）。
`make -j8` rc=0，约 55 秒，25 条 warning，无 error。
（`--enable-bsf` 在 n9 下实际启用的 bsf 比 n6 多几个，是因为这些 bsf 不是靠白名单关的，非选项问题。）

## 2. mpv v0.41.0 编译与体积（实测）

mpv v0.41.0 + n9.0.2 不打任何补丁就能配、能编、能链（client API 2.5）。
摘 `vo_gpu_next` 用 `tools/libplacebo-eval/b3-v041.patch`，在干净 v0.41.0 上 `git apply` 成功（改 `meson.build`、`options/options.c`、`video/out/vo.c`）。

### 2.1 linux job 原样（带 `--enable-vaapi --enable-vdpau`）

| 组合 | 字节 |
|---|---|
| n6.0.1 + 钉死 mpv `78d43740f5`（无 libplacebo） | 7,546,616 |
| n9.0.2 + 钉死 mpv + 兼容补丁（旧 342 行那个） | 8,628,264 |
| n9.0.2 + v0.41.0 + 静态 libplacebo，**不摘** vo_gpu_next | 9,450,760 |
| n9.0.2 + v0.41.0 + 静态 libplacebo，**摘** vo_gpu_next | 8,813,288 |

这套里 n9 的 hwaccel 会顺带把 vvc、vc1、vp8、mpeg4 等 decoder 拉进来（n6 没有 vvc），所以 n9 的增量被放大了，
**不能当作升级 ffmpeg 的纯代价**，见 2.2。

### 2.2 去掉 vaapi/vdpau/vulkan（更接近 Android 的 decoder 集合，两边 decoder 列表一致）

| 组合 | 字节 | 相对 n6 基线 |
|---|---|---|
| n6.0.1 + 钉死 mpv（无 libplacebo） | 6,721,272 | 基线 |
| n9.0.2 + 钉死 mpv + 兼容补丁 | 7,221,160 | +499,888（+7.4%） |
| n9.0.2 + v0.41.0 + libplacebo，摘 vo_gpu_next | **7,406,184** | **+684,912（+10.2%）** |
| n9.0.2 + v0.41.0 + libplacebo，不摘 | 8,047,752 | +1,326,480（+19.7%） |

- 摘补丁省 641,568 字节；v0.41.0+libplacebo 相对「钉死 mpv 同在 n9」多 184,976 字节（和计划里「约 +157KB」同量级）。
- **关键差异**：计划里的「+157KB」是 mpv 版本/libplacebo 的增量，**两边都用 n9.0.2**。本次把 ffmpeg 版本也算进去，
  同口径下 n6.0.1→n9.0.2 单这一项约 +500KB，合计 +685KB。Android 上这个 ffmpeg 增量是否同样存在**未测**。
- n9 增量的来源**没拆**。看到 `film_grain_db`（`libavcodec/h274.c`，692,248 字节）是 n9 新增的静态符号，
  但它是零初始化的静态变量，多半在 .bss，不占文件体积（**推断，没用 `size` 核实**），所以不能直接算成那 500KB。
- 不摘补丁时 libmpv.so 带未解析的 libplacebo C++ 符号（`std::to_chars`/`std::from_chars`），
  调用方链接时要补 `-lstdc++`（实测：不补则 `gcc smoke.c -lmpv` 链接失败）。摘补丁后该问题消失。
- 系统库 `bz2`：ffmpeg configure 会自动探测系统 `libbz2-dev`，产物里出现 `BZ2_*` 未解析符号。
  linux job 本就没关 bzlib，这不是 n9 引入的，但 Android flavor 已有 `--disable-bzlib`，Linux 侧顺手也该关。

## 3. 冒烟（实测）

最终产物（n9.0.2 + v0.41.0 + 静态 libplacebo + 摘 vo_gpu_next，去 vaapi/vdpau 那份）：

- `mpv_create` / `mpv_initialize` / `mpv_terminate_destroy` 连续 5 轮：5/5 `init=0`，`mpv_client_api_version=131077`（即 2.5）。
- 播放（vo=libmpv + 软件渲染后端，ao=null，每次一遍）：
  - 本地 h264+aac mp4（2 秒）：`END_FILE reason=0 err=0`，渲染 23 帧，`ffmpeg-version=n9.0.2`。
  - 本地文件 HLS（4 段 mpegts，8 秒）：reason=0，渲染 83 帧。
  - HTTP HLS（`python3 -m http.server`，127.0.0.1）：reason=0，渲染 84 帧。
- 弱客户端运行时：每次播放都 `mpv_create_weak_client` 建一个、`mpv_request_event` 订阅 `PLAYBACK_RESTART`/`END_FILE`、
  用 `mpv_wait_event(weak, 0)` 排空，三次播放里弱客户端都收到 1 次 RESTART、1 次 END_FILE。
- 不摘 vo_gpu_next 的版本（补 `-lstdc++` 链接后）同样 5/5 + mp4 播放通过。
- **没测**：带 `VideoController` 的真实 GPU 渲染、音频输出、真实 media_kit 端到端、直播/WHEP、Android/Windows 任何运行。
  视频只有 320x240 h264 小样本，HLS 是用 ffmpeg 把它循环切出来的。

## 4. libmpv client API 在 v0.41.0 的情况（实测 + 读头文件）

对象：mova `platform_impl/mpv_event_backend_ffi.dart` 用到的 `mpv_create_weak_client`、`mpv_destroy`、`mpv_request_event`、
`mpv_set_wakeup_callback`、`mpv_wait_event`，以及 media_kit 常用的 `mpv_create_client`、`mpv_wakeup`、`mpv_terminate_destroy`、
`mpv_observe_property`、`mpv_free_node_contents`、`mpv_request_log_messages`。

- 钉死 mpv（`libmpv/client.h`，API 2.2）与 v0.41.0（`include/mpv/client.h`，API 2.5）逐个对比上述函数的 `MPV_EXPORT` 原型：**11 个全部一字不差**。
- `struct mpv_event`、`struct mpv_event_end_file`、`enum mpv_end_file_reason`、`enum mpv_event_id` 的定义（去注释后）逐行 diff：**一致**，FFI struct 布局不变。
- 对 `/root/w/mpvt/used-syms.txt`（media_kit 1.2.6/media_kit_video 2.0.1 与 mova 用到的 42 个名字）在最终产物 `nm -D`：
  函数全部导出；缺的 14 个都是类型名（`mpv_event`、`mpv_format`、`mpv_node` 等，不是函数符号）。
- 注意：头文件目录结构变了（`libmpv/` → `include/mpv/`），任何手写 `-I`/打补丁的脚本要跟着改。
- 未验证：真实 media_kit 的 Dart FFI 在 v0.41 上端到端跑通。

## 5. Android 三个补丁（实测 `git apply --check`）

来源 `media-kit/libmpv-android-video-build`（本次 clone 的是 HEAD `1ecf510`，2026-01-27）的
`buildscripts/patches/`：

| 补丁 | 目标 | 结果 |
|---|---|---|
| `mpv/mpv_lavc_set_java_vm.patch` | 钉死 mpv | 能 apply |
| 同上 | **v0.41.0**（干净） | **失败**：`libmpv/client.h` 不存在（现为 `include/mpv/client.h`），`player/client.c` 的 hunk 对不上 |
| `tools/libplacebo-eval/javavm-v041.patch`（手工移植版） | v0.41.0 干净 | 能 apply |
| 同上 | v0.41.0 + b3（摘 vo_gpu_next） | 能 apply，两个补丁不冲突 |
| `ffmpeg/hls_mp4_seek.patch` | n6.0.1 | 能 apply |
| 同上 | **n9.0.2** | 失败，原因是上游已修：`hls_read_seek` 里已有 `pls->cur_init_section = NULL`（读源码确认） |
| `ffmpeg/dash_base_url_escape.patch` | n6.0.1 | 能 apply |
| 同上 | **n9.0.2** | 失败，原因是上游已修：`dashdec.c` 已有 `xmlEncodeSpecialChars`（读源码确认） |

- 结论：升到 n9.0.2 + v0.41.0 后，两个 ffmpeg 补丁**可以删**；mpv 补丁**必须用手工移植版**（`javavm-v041.patch`）。
- 手工移植版叠上 b3 后，在 Linux 上编译、链接通过，`mpv_lavc_set_java_vm` 出现在导出表（`nm -D` 为 `T`）；
  产物体积与不叠它时相同（7,406,184）。这是 **Linux 编译验证**，av_jni_set_java_vm 在无 `--enable-jni` 时只是返回错误的桩，
  **Android 上能否真让 MediaCodec 绑定 JavaVM 没验证**，要在 Android 构建和真机上验。

## 6. 结论与风险

1. **可用配对：ffmpeg n9.0.2 + mpv v0.41.0 + 静态 libplacebo + 摘 vo_gpu_next**，Linux 真实 flavor 编、链、冒烟（5/5、mp4、HLS 文件与 HTTP）通过。
   与计划的 T0.2 修订一致，**不需要升 mpv 到与 media_kit 不兼容的版本**：client API 函数、事件枚举、struct 布局没变，不触发上报条件。
2. **体积代价比计划里写的大**：计划只量了「mpv 版本+libplacebo」的 +157KB；加上 ffmpeg n6.0.1→n9.0.2 后，Linux 同口径总增量约 **+685KB（+10.2%）**，
   其中 ffmpeg 版本一项约 +500KB。Android 上的对应数字未测，T0.4 要用真实 Android flavor 重量一遍。
3. 要落地的补丁：b3（摘 vo_gpu_next）、javavm-v041（Android）、freetype 的 bz2 自动探测（评估时手改了源码，未做成补丁，见 `tools/libplacebo-eval/README.md`）。
4. 一个新注意点：不摘 vo_gpu_next 时 libmpv 对 libstdc++ 有隐式依赖，Linux 链接要补 `-lstdc++`；摘了就没这个问题。
5. 本次没覆盖：Android/Windows flavor、LTO、真实 GPU 渲染、真实 media_kit 端到端、音频输出。
