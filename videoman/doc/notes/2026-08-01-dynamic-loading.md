# 原生库与模型的动态加载可行性（播放器 libmpv / STT 引擎 + 模型）

> 2026-08-01 · 调研笔记 · 起因：讨论「播放器/STT 能否走动态加载以减小安装包」。
> 结论先行：**必须区分「可执行代码」与「数据」两类，二者动态加载性质完全相反。**

## 0. 核心判据：代码 vs 数据

| | 是什么 | iOS | Android | 桌面 |
|---|---|---|---|---|
| **可执行代码**（原生库 .so/.dll/.framework） | libmpv、ffmpeg、whisper.cpp 引擎 | **不能运行时下载执行**（App Store 2.5.2：禁止下载/执行引入或改变功能的代码，明确点名 `dlopen` 远程库） | **可以**（Play Feature Delivery / Dynamic Feature Module 官方按需下载，`SplitInstallManager`） | 可以，无审核 |
| **数据资源**（模型权重、字幕、缩略图…） | ggml 模型 .bin、Core ML 权重 | **可以**（数据不受 2.5.2 约束；有官方机制 On-Demand Resources / Background Assets / BGProcessingTask；Apple DTS 明确答复"从服务器下载/更新模型文件不违规"） | 可以，直接下 | 可以 |

**一句话**：iOS 上「原生库」这条腿是断的（必须随包），但「模型/数据」这条腿是通的（可
运行时下载，且有官方通道）。Android/桌面两条腿都通。

## 1. 应用一：播放器原生库（libmpv/ffmpeg）

- **iOS**：libmpv 是可执行代码，**不能运行时下载**，必须随包 → iOS 减体积只能靠**瘦身**
  （见 [2026-07-31-ffmpeg-slim-build-windows.md](2026-07-31-ffmpeg-slim-build-windows.md)），
  不能靠动态加载。App Thinning 只按设备架构瘦分发，不是"运行时下载"。
- **Android**：可用 DFM 把 `media_kit_libs_android_video` 的 `.so` 放进按需模块，基础包
  几乎不含播放器，首播时下载。代价：首播延迟 + 网络依赖 + 需改 media_kit 的加载接线
  （Android 侧是 `System.loadLibrary` 静态链，不是可替换路径）。
- **桌面**：media_kit 的 `MediaKit.ensureInitialized(libmpv: '<路径>')` 支持指定外部
  libmpv 路径（ffmpeg spike 时即用它指到 `example/build` 下的 dll），下载后指定路径即可。
- **结论**：videoman 作为要发 pub.dev 的通用库，**默认走「瘦身 + 随包」**（全平台受益、
  无副作用）；**动态加载留作宿主可选的高级集成**（videoman 暴露 `ensureInitialized(libmpv:)`
  这类路径注入开放点，宿主自行接 DFM/CDN），不做 videoman 默认行为。跨平台结果本就不
  对称（Android 能按需、iOS 只能随包），不宜做成默认。

## 2. 应用二：STT（whisper.cpp 引擎 + ggml 模型）

拆成两半，结论相反：

- **引擎（whisper.cpp 原生库，约 1–5MB/ABI）= 代码**：iOS **必须随包**（不能运行时下载），
  Android/桌面随包或 DFM 皆可。但它就几 MB，**随包毫无压力，不值得为它搞动态加载**。
- **模型（ggml .bin，base 150MB / large-v3 量化 1.6GB）= 数据**：**全平台可运行时下载，
  iOS 合规**（官方 ODR/Background Assets；DTS 确认下载模型文件不违规；只要当数据用、
  绝不作为代码执行）。`whisper_ggml` 包默认就是「首次使用时下载、缓存、不打进包」。

**这直接化解了 whisper.cpp 之前最大的两个顾虑**（见
[2026-07-31-stt-subtitle-feasibility.md](2026-07-31-stt-subtitle-feasibility.md) §0/§2）：
1. "模型太大不能内置" → 模型本就运行时下载、不进包，**天然满足「不内置模型」的要求**。
2. "引入 whisper.cpp 体积代价" → 真实增量只有**几 MB 引擎随包**，模型合规动态化。

→ **whisper.cpp 的性价比比之前评估时高得多**：引擎小、模型不进包、四端行为统一，还避开
Android 平台原生 ML Kit 那个 alpha/机型限定的坑。**STT 方向判断因此明显偏向 whisper.cpp**
（引擎随包 + 模型运行时下载）。

## 3. 限定 / 待办

- Apple 对"下载的资源是否可能被当作代码执行"较敏感；模型只能**当数据用**（喂给随包引擎
  推理），不能是脚本/字节码/可执行体。具体案例上线前 Apple 建议咨询 DTS。
- **引入 whisper.cpp 作为新第三方依赖仍需用户正式确认**（CLAUDE.md 依赖需同意）——本笔记
  只更新「技术可行性与方向倾向」，不代表已拍板引依赖。确认后再据此拆 STT 落地 Task。

## 参考

- Apple 2.5.2：禁的是下载执行代码，非数据 —— https://developer.apple.com/app-store/review/guidelines/
- Apple 官方：在用户设备上下载并编译模型 —— https://developer.apple.com/documentation/coreml/downloading-and-compiling-a-model-on-the-user-s-device
- Core ML 端侧下发模型实践（ODR/Background Assets） —— https://blakecrosley.com/blog/core-ml-on-device-inference
- Android Play Feature Delivery（按需下载 native 模块） —— https://developer.android.com/guide/playcore/feature-delivery
- whisper.cpp 模型 = ggml 数据文件，运行时下载 —— https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md
- media_kit `ensureInitialized(libmpv:)` 自定义路径 —— https://pub.dev/packages/media_kit
