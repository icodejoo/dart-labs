# libmpv/ffmpeg 瘦身：mpv 构建选项完整盘点

> 2026-07-31 · 调研笔记 · 对应遗留任务 #4「二期 ffmpeg 瘦身」（[CLAUDE.md](../../../mova/CLAUDE.md)
> 未开始项）。选项来源：mpv 官方仓库 `master` 分支的
> [`meson.options`](https://github.com/mpv-player/mpv/blob/master/meson.options)
> （2026-07-31 拉取，逐条核对）。本文档只做**盘点与分类**，不是可执行的瘦身计划——真正
> 动手瘦身时，本清单是起点，仍需逐项实测验证（尤其"需要先验证"一档）。

## 0. 现状基线（实测，非估算）

当前 mova 依赖官方 `media_kit_libs_video`（完整包，未瘦身）。实测本项目 Windows 桌面
已编译产物：

```
example/build/windows/x64/runner/Debug/libmpv-2.dll = 29,764,622 字节（约 29.76 MB）
```

这是"瘦身能省多少"的参照基线。瘦身构建实际能到多小，**必须真编译一版才有准数**，本文档的
分类是"哪些选项该关/该留/该验证"，不代替实测。

## 1. 明确可关——mova 完全用不到，可直接禁用

| 选项 | 类型 | 官方描述 | 为什么 mova 用不到 |
|---|---|---|---|
| `lua` | combo（`lua`/`lua52`/`luajit`/…/`auto`/`enabled`/`disabled`） | Lua 脚本支持 | mpv 自带的脚本引擎，用来跑 OSD 脚本/用户插件（如 mpv 生态里那些 `.lua` 脚本，包括本次调研查到的 WhisperSubs 就是一个 Lua 脚本）。mova 的界面/交互全在 Flutter 侧实现，**从不加载任何 mpv 脚本**，整个 Lua 解释器运行时可以整块砍掉。 |
| `javascript` | feature | Javascript (MuJS backend) | 同上，mpv 的另一套脚本引擎（MuJS 实现的 JS），同样场景——mova 不用 mpv 脚本，可砍。 |
| `cdda` | feature | cdda support (libcdio) | CD 音频（Compact Disc Digital Audio）播放支持。mova 只播网络点播/直播视频，不存在"播放光盘"的场景。 |
| `dvbin` | feature | DVB input module | DVB（欧洲数字电视广播标准）调谐器输入模块，用于接收电视信号源。mova 的源都是 HTTP(S)/HLS 网络地址，不接硬件调谐器。 |
| `dvdnav` | feature | dvdnav support | DVD 光盘的菜单导航支持（`dvdnav://` 协议，处理 DVD 的章节菜单结构）。mova 不播放 DVD 光盘镜像。 |
| `libbluray` | feature | Bluray support | 蓝光光盘播放支持（`bluray://` 协议）。同上，不适用。 |
| `cplugins` | feature | C plugins | 允许 mpv 加载外部编译好的 C 语言插件（`.so`/`.dll`）来扩展行为。mova 不提供也不加载这类插件，扩展能力走的是 Dart/Flutter 侧的 `MovaHook`/组件树/补丁机制。 |
| `vapoursynth` | feature | VapourSynth filter bridge | 桥接 VapourSynth（一个专业视频处理脚本框架）滤镜链的接口，供高级用户做自定义画面滤镜。mova 不暴露、也不需要这类专业滤镜链能力。 |
| `libarchive` | feature | libarchive wrapper for reading zip files and more | 让 mpv 能直接从 zip 压缩包内部读取媒体文件（例如把一堆视频打包进 zip 直接播放里面某个文件）。mova 的源都是独立的网络地址，不存在"从压缩包里播放"的场景。 |
| `lcms2` | feature | LCMS2 support | 专业色彩管理（ICC 色彩配置文件）支持，用于色彩精确还原（广电/后期场景）。mova 是普通消费级视频播放器，不做专业色彩管理。 |
| `x11-clipboard` | feature | X11 clipboard backend | Linux X11 桌面环境下与系统剪贴板交互（例如 mpv 命令行播放器里粘贴 URL）。mova 是内嵌进 Flutter App 的播放器组件，不需要这类桌面剪贴板集成，即便未来做 Linux 也不需要。 |
| `caca` | feature | CACA | 把视频画面渲染成"字符画"（文字终端里用色块字符模拟画面）的输出后端，纯粹是给无图形界面终端用的猎奇功能。mova 是图形界面播放器，不适用。 |
| `sixel` | feature | Sixel video output | 一种终端图形协议（把画面编码成终端可显示的色块序列），同样是给命令行终端用的输出方式，不适用。 |
| `vdpau` | feature | VDPAU acceleration | NVIDIA 显卡在 Linux 上的老一代专有硬解加速接口（已被更通用的 VAAPI/Vulkan 取代）。mova 用纹理内嵌渲染路径，不需要这条老接口。 |
| `vdpau-gl-x11` | feature | VDPAU with OpenGL/X11 | 上面 VDPAU 配合 OpenGL/X11 的联动模式，同样不适用。 |

## 2. 需要按平台精确取舍——只保留该平台实际用到的那一项

以下几类选项本身"有用"，但 mpv 支持的是好几种平台/技术路线的**并集**，mova 每个平台
实际只走其中一条（详见本仓库此前调研的分平台渲染路径：Android 是 `--vo=mediacodec_embed
--hwdec=mediacodec` 直绘 Surface；iOS/macOS 是 GL 渲进 IOSurface/`CVPixelBuffer`；Windows
是 GL/ANGLE/EGL），其余分支应在对应平台的瘦身构建里关闭：

**音频输出后端**（保留该平台实际输出设备对应的一项，其余关闭）：

| 选项 | 描述 | 说明 |
|---|---|---|
| `alsa` | ALSA audio output | Linux 传统音频子系统，仅 Linux 保留（若做 Linux 构建） |
| `pulse` | PulseAudio audio output | Linux 主流音频服务，视 Linux 目标发行版决定要不要 |
| `pipewire` | PipeWire audio output | 新一代 Linux 音频服务（渐成主流），同上视目标而定 |
| `jack` | JACK audio output | 专业音频制作场景用的低延迟音频服务器，mova 面向消费级播放，不需要 |
| `sndio` | sndio audio output | OpenBSD/极少数 Linux 发行版的音频系统，不适用 |
| `oss-audio` | OSSv4 audio output | 更老旧的 Unix 音频接口，已被上述几种取代，不适用 |
| `audiotrack` | Android AudioTrack audio output | Android 传统音频输出 API，与 `aaudio` 二选一或并存 |
| `aaudio` | Android AAudio audio output | Android 现代低延迟音频 API（Android 8+），Android 平台应保留这条 |
| `opensles` | Android OpenSL ES audio output | Android 更老的音频 API，若已用 AAudio 可考虑关闭 |
| `coreaudio` | CoreAudio audio output | macOS 音频输出，macOS 平台保留 |
| `avfoundation` | AVFoundation audio output | iOS/macOS 音频输出（新一代 API），iOS/macOS 平台保留 |
| `audiounit` | AudioUnit output (iOS) | iOS 另一条音频输出路径，与 avfoundation 视实际选型二选一 |
| `wasapi` | WASAPI audio output | Windows 现代音频 API，Windows 平台保留，这是当前应该在用的那条 |

**视频输出/硬解相关**（保留该平台实际渲染路径用到的一项）：

| 选项 | 描述 | 说明 |
|---|---|---|
| `egl` / `egl-android` / `plain-gl` | OpenGL 相关上下文与 Android EGL 支持 | Android 的 GL 相关支持，若走 `mediacodec_embed` 直绘 Surface（非 GL 纹理路径）需要确认这几项是否还是必需依赖，需要实测 |
| `egl-angle` / `egl-angle-lib` / `egl-angle-win32` | Windows 上用 ANGLE 把 GL 调用转译到 D3D | Windows 平台当前渲染路径依赖（已在本仓库 Windows 构建产物里看到 ANGLE 相关 DLL），应保留 |
| `d3d11` / `direct3d` / `d3d-hwaccel` | Direct3D 11 视频输出与硬解 | Windows 平台硬解路径，应保留 |
| `d3d9-hwaccel` / `gl-dxinterop` / `gl-dxinterop-d3d9` | 更老的 D3D9 硬解与 GL/D3D 互操作 | 若 Windows 目标只认 D3D11 一条新路径，这些老 D3D9 相关分支可关闭（需实测确认不影响现有兼容性） |
| `ios-gl` / `videotoolbox-gl` / `videotoolbox-pl` | iOS OpenGL ES 互操作、VideoToolbox 硬解（配 OpenGL 或 libplacebo） | iOS/macOS 平台硬解路径，应保留其一（视具体渲染管线走 GL 还是 libplacebo 决定留哪个） |
| `android-media-ndk` | Android Media APIs | Android 硬解相关 NDK 接口，Android 平台应保留 |
| `cuda-hwaccel` / `cuda-interop` | NVIDIA CUDA 硬解及图形互操作 | 面向独立 NVIDIA 显卡的桌面硬解路径，mova 目标平台（移动端 + 常规桌面渲染）用不到，可关 |
| `vaapi` / `vaapi-drm` / `vaapi-wayland` / `vaapi-win32` / `vaapi-x11` | VAAPI（主要是 Linux Intel/AMD 显卡）硬解 | 若不做 Linux 硬解适配或 Linux 只走软解，可关；做 Linux 时需按目标显卡决定 |
| `wayland` / `x11` / `xv` / `drm` / `gbm` / `dmabuf-wayland` / `egl-wayland` / `egl-x11` / `egl-drm` / `gl-x11`（已默认 disabled） | Linux 桌面窗口系统相关的显示后端集合 | 只有做 Linux 支持时才相关，且应按目标桌面环境（X11 还是 Wayland）精确选择，不要囫囵全开 |
| `cocoa` / `gl-cocoa` / `macos-cocoa-cb` | macOS 原生窗口系统集成 | macOS 平台需要，但**mova 目前没有 macOS 原生插件**（此前调研已确认），要等 macOS 插件落地时才需要精确取舍这几项 |
| `amf` | AMD AMF（硬解） | AMD 独立显卡专有硬解接口，mova 目标平台用不到 |

## 3. 需要先验证/实测才能决定——不能盲目关

| 选项 | 描述 | 为什么不能直接关 |
|---|---|---|
| `rubberband` | librubberband 支持（变速不变调的时间拉伸算法） | media_kit 的 `Player.setRate()`/`setPitch()` 是否依赖它来实现"变速播放但音调不变"待确认——mova 的 `MovaApi.setRate()` 目前没有独立暴露 `setPitch`，但底层 mpv 默认变速行为可能仍受它影响。**关掉前必须实测**：变速播放（如 1.5x/2x）的声音音调是否仍然正常，不能想当然认为用不到。 |
| `libcurl` | libcurl-based stream backend | mpv 的网络流可以走 libcurl，也可以走 ffmpeg 自带的 HTTP/HTTPS/HLS 协议实现。mova 现在大概率吃的是 ffmpeg 那条内建协议路径，libcurl 应该是冗余的，但**关闭前必须实测 HLS 联网播放、慢速网络场景下不受影响**，不能直接假设。 |
| `iconv` | 字符编码转换 | 部分容器/字幕元数据的字符集转换可能依赖它（例如非 UTF-8 编码的文件名/元信息）。体积一般不大，但涉及正确性而非纯粹的性能优化，关闭前需要评估是否有实际使用路径依赖它。 |
| `zlib` | 压缩库 | 部分网络协议（如支持 gzip 压缩的 HTTP 响应）与容器格式解析可能依赖它，属于比较基础的公共依赖，误关有正确性风险，不建议轻易动。 |

## 4. 产品取舍——不是纯技术瘦身问题，需要用户决策

| 选项 | 描述 | 取舍点 |
|---|---|---|
| `win32-smtc` | Windows Media Control support（系统媒体传输控制，即锁屏/任务栏媒体控制中心的播放器卡片） | 关掉省体积，但会丢失"Windows 锁屏/媒体键控制 mova 播放"这个真实的用户体验点。是否要这个系统集成功能，是产品决策，不是单纯的技术瘦身判断。 |
| `macos-media-player` | macOS Now Playing/媒体中心集成 | 同上，macOS 系统级"正在播放"卡片与媒体键联动。mova 目前没有 macOS 插件，这个决策可以留到真正搭建 macOS 插件时再做。 |
| `macos-touchbar` | macOS Touch Bar 支持 | Touch Bar 是逐渐被苹果自己淘汰的旧硬件特性（新款 Mac 已不带 Touch Bar），关掉的实际影响面很小，但仍是"要不要支持这个老硬件"的产品判断，非纯技术问题。 |

## 5. 字幕相关——保留待定，不纳入"可关"清单

**用户明确要求（2026-07-31）：字幕功能先保留、不要删，等瘦身构建实测出实际体积数字后再
权衡；用户认为该功能有用。** 因此以下几项**不划入第 1 类"明确可关"**，单独记录、维持现状：

| 选项 | 描述 | 与字幕功能的关系 |
|---|---|---|
| `libass` | ASS/SSA 字幕高质量渲染库（依赖 freetype/harfbuzz/fribidi） | mpv 原生字幕渲染的核心依赖。本次调研讨论过"STT 生成的字幕走 mpv 原生渲染（喂进 `sub-add`/字幕轨）还是 Flutter 侧自绘叠层组件"这个开放问题（详见 [2026-07-31-stt-subtitle-feasibility.md](2026-07-31-stt-subtitle-feasibility.md)）——目前**倾向** Flutter 侧方案（避免破坏组件化/主题化架构、避免被 `Transform.scale`/裁剪影响），但用户认为原生字幕渲染路径仍可能有用，**暂不关闭 libass，留待瘦身构建实测出体积数字后再综合权衡**。 |
| `subrandr` | SRV3/WebVTT 字幕渲染器（另一套内置字幕渲染后端，独立于 libass） | 同样服务于"mpv 原生字幕渲染"这条路径，与 libass 是同一决策的一部分，一并保留待定。 |
| `uchardet` | 字幕文件字符集自动检测 | 只有加载外部字幕文件（如非 UTF-8 编码的 `.srt`）时才用得上。若最终决定走 mpv 原生字幕渲染路径（尤其涉及加载外部字幕文件场景），这项也需要保留；若最终决定 Flutter 侧方案完全不用 mpv 加载字幕文件，则可关。与上面两项归为同一个未决问题。 |

## 6. 待办

- 真正启动瘦身工作时，按本清单逐项配置 `meson setup`，实测编译产物体积（对照 §0 的
  29.76MB 基线），并回填本文档的"现状基线"一节。
- 第 3 类（`rubberband`/`libcurl`/`iconv`/`zlib`）逐项验证功能不受影响后，再决定是否关闭。
- 第 5 类（字幕相关）待瘦身构建实测出"关闭 libass 能省多少体积"的具体数字后，与
  [2026-07-31-stt-subtitle-feasibility.md](2026-07-31-stt-subtitle-feasibility.md) 里
  "Flutter 侧字幕组件 vs mpv 原生字幕渲染"的架构决策一并拍板。
- 第 4 类（`win32-smtc`/`macos-media-player`/`macos-touchbar`）需要用户就产品体验做决策，
  不是技术判断。

## 参考

- 相关调研：[2026-07-31-ffmpeg-slimming-options.md](2026-07-31-ffmpeg-slimming-options.md)
  （libmpv 底下包的 ffmpeg 本身的解码器/容器/协议盘点，现代主流点播+直播范围）
- mpv 官方构建选项定义（`meson.options`，2026-07-31 拉取自 `master` 分支）
  https://github.com/mpv-player/mpv/blob/master/meson.options
- 相关调研：[2026-07-31-stt-subtitle-feasibility.md](2026-07-31-stt-subtitle-feasibility.md)
  （字幕功能架构方向，含"Flutter 侧组件 vs mpv 原生渲染"的讨论）
