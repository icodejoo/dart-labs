# 实时语音转文字字幕（STT）可行性研究与方向

> 2026-07-31 · 调研笔记 + ADR 回写（第二版，推翻第一版"默认用 whisper.cpp"的结论）·
> 对应 [doc/PRD.md](../PRD.md) ADR「实时语音转文字字幕（条件性未来项）」——本文档即
> 该条要求的"后端可行性评估结论"。
>
> 结论先行：**可行，且不需要新增任何第三方依赖。** 优先级：**平台原生 STT（有就用）→
> 否则关闭**；不做 MCP 兜底（理由见 §4，已明确否决）；给宿主留一个通用的可注入端口，
> 想接什么后端（云端/自建模型/自己的 MCP 调用）都行，但那是宿主的选择，不是 videoman
> 默认链路的一环。现阶段只出方向、不写实现代码、不加依赖。

## 0. 与第一版的关系

第一版（同日更早）结论是"默认依赖 whisper.cpp（FFI）跨平台统一转写"。复盘后推翻，理由：

- whisper.cpp 是**新增第三方依赖**（FFI + 原生库 + 打包），需要 CLAUDE.md 约定的用户审批；
  而**平台原生 STT 是操作系统自带能力**，通过原生代码（Swift/Kotlin/C++）调用，跟现有
  PiP/音量/方向那套原生代码是同一类东西——**不算引入新依赖**。两条路优先级不该一样。
- 不内置模型文件（用户明确要求）：whisper.cpp 路线要么打包模型进产物、要么设计"宿主自行
  下载模型"的旁路，平台原生 STT 完全没有这个负担——模型是操作系统自己管的。
- §1 的核心工程问题（如何拿到与视频音轨对应的实时 PCM）**在两个方案下是同一个问题**，
  与选哪个转写引擎无关——所以这部分研究结论原样保留，不因为推翻引擎选型而作废。

## 1. 核心工程问题：libmpv 没有实时 PCM 抽头 API，但有绕过的成熟范式

无论最终转写引擎是谁，都要先解决"怎么拿到与视频音轨同步的 PCM"。调研发现
**libmpv 没有干净的实时 PCM 抽头 API**——`ao=pcm` 是把整段音频转储成文件，不是流式接口；
libmpv 的 render API（`MPV_RENDER_API_TYPE_SW` 等）只覆盖视频，不覆盖音频抽头。

**关键转念**：不需要"实时抽头"。参考真实存在的先例
[WhisperSubs](https://github.com/GhostNaN/whisper-subs)（一个 mpv Lua 脚本，边播边转写
字幕）——做法是**独立解码音频到小块、分块喂给转写引擎、结果按时间戳注入字幕**，完全不碰
mpv 的实时播放管线。这与 videoman **阶段 B 拖动预览缩略图已经验证过的架构**是同一个套路：
mpv 的实时管线拿不到某个能力（阶段 B 是"缩放抽帧"，这里是"音频流"），**解法都是开一条
独立的第二解码路径**，而不是硬啃第一条。仿阶段 B 用一个不渲染视频、仅解码音频的隐藏
media_kit 实例，按滚动窗口切块（参考 WhisperSubs 的 `CHUNK_SIZE` 调优经验：块太大延迟高，
块太小转写质量和上下文都会受影响，需要实测调参），喂给下面选定的转写引擎。

## 2. 转写引擎优先级：平台原生 STT 优先，否则关闭

### 2.1 平台原生 STT——分平台盘点（有的能力不对称，如实记录）

| 平台 | 系统自带能力 | 是否支持喂任意 buffer（非仅麦克风） | 现状 |
|---|---|---|---|
| Android | ML Kit GenAI Speech Recognition | 支持，明确支持文件/音频源输入 | 原生插件已存在（Kotlin，已有 PiP/音量代码），加方法即可，量级与本次加音量相当 |
| iOS | `SFSpeechRecognizer`/`SFSpeechAudioBufferRecognitionRequest` | 支持，`SFSpeechAudioBufferRecognitionRequest` 明确接受任意 buffer | 原生插件已存在（Swift），加方法即可 |
| macOS | 与 iOS **同一套** Apple Speech Framework | 同上 | ⚠️ **videoman 目前没有 macOS 原生插件**（`macos/` 目录不存在）——要从零搭一个平台插件骨架，比"加个 case"重，但 STT 逻辑可照抄 iOS 那份 |
| Windows | `System.Speech`/底层 SAPI（`ISpRecognizer`） | 支持，`SetInputToAudioStream`/`ISpStream` 明确支持任意音频流 | 插件骨架已存在但目前基本是空壳；SAPI 是 COM 接口，要在 C++ 里手写 COM 生命周期 + 自定义 `ISpStream` 喂数据——真正的原生工作量，项目里无先例可抄 |
| Linux | **不存在**——没有 freedesktop 标准 STT API，只有第三方开源方案（不算"系统自带"） | — | 该平台默认无字幕，是预期行为，非缺陷 |

- **不追求"四端行为完全一致"**：这是本次调整对既有价值取向的一次明确背离——videoman
  一路的原则是"跨平台统一行为"（当初选 media_kit 而非各平台原生播放器就是这个原因），但
  用户已明确拍板"优先系统自带，没有就关闭"，接受桌面端（尤其 Linux）体验不对称。这是
  用户已知且接受的取舍，不是需要"修"的缺口。
- iOS/macOS 的 Apple Speech Framework 部分场景可能需要联网（`requiresOnDeviceRecognition`
  未强制时），实现时要显式选择强制端上识别，避免"字幕功能"隐式产生网络依赖。

### 2.2 MCP 兜底——已否决，不纳入默认链路

调研后判断意义不大，理由：

1. **解决不了真正的空白**（Linux 桌面）。MCP 是**请求/响应协议，不是为实时音频流设计
   的**——查证结果明确指出"MCP does not handle real-time audio streaming"。用它做字幕，
   现实体验是"发一段音频→等一次工具调用往返→收到文本"，延迟可能是几秒到几十秒，字幕这
   个场景下延迟到这个量级基本等于不可用——是另一种不可用，不是可接受的降级体验。
2. **前提条件太窄**：要吃到这条路，宿主 App 得恰好接了一个能做语音转写的 MCP agent，是
   很特殊的场景，不是"装个包就有"的通用能力；为这么窄的交集写一整套"音频分块→MCP 工具
   调用→异步收文本→按时间戳回灌字幕"的管线，投入产出不成比例。
3. **混淆了 MCP 钩子本来的定位**：PRD 里 MCP 钩子的原始设计是"播放器向 MCP agent 暴露
   只读上下文（字幕文本、播放状态），或接收其下发的指令"——是**被动暴露/接受控制**的
   角色；拿它做"主动请求转写服务"是完全不同的集成形状，会让以后真正做 MCP 钩子时更纠结。

**PRD 里的 AI MCP 集成钩子作为独立的、纯前瞻性的未来项保留不变**（context 暴露/接受指令），
与字幕这件事解耦，不受本次否决影响。

### 2.3 通用注入口子——不是"MCP 专用"，是复用既有模式

砍掉 MCP 专项之后，缺口不需要专门补：延续 `VmVolumePort`/`CallbackVolumePort` 那套
"抽象端口 + 默认实现 + 可注入覆盖"模式，宿主想在 Linux 上或想覆盖平台原生实现时，可以
自己实现 `VmSttEngine`（内部想接什么后端都行——云端 API、自建模型、自己的 MCP 调用），
经 `createVmEngine(stt: MyEngine())` 注入。这个口子**通用性比"专门集成 MCP"更强**（不
锁定某一种后端形状），且不需要额外设计，是既有套路的直接复用，零增量成本。

## 3. 架构落点

- **core 端口抽象**（`lib/src/core/`，暂拟 `VmSttEngine`）：输入 PCM 分块，输出带时间戳
  的文本片段流。默认实现按平台探测原生能力，探测不到则 noop/关闭（同
  `FallbackBrightnessPort` 的风格）；真实原生实现放 `lib/src/platform_impl/`
  （`NativeSttEngine` 之类，Android/iOS/macOS/Windows 分别实现，Linux 无实现即关闭）。
- **独立音频解码路径**：见 §1，仿阶段 B 的隐藏 `Player` 模式。
- **字幕叠层组件**：新增一个类似 `PreviewComponent` 的叠层组件，挂在既有组件树/皮肤/补丁
  机制上，不改变 `VmApi` 之外的契约。
- **`VmApi` 面**：预计新增 `VmApi.subtitles`（字幕流，同 `preview` 的形状）+
  `VmSubtitleChanged` 一类事件，具体签名留到实现阶段确定。

## 4. 与二期 ffmpeg 瘦身（未开始的遗留任务 #4）的协同点

二期若自建裁剪版 ffmpeg，可顺带导出一个轻量 PCM 解码函数供 STT 用（与阶段 B 计划中"顺带
导出轻量抽帧函数"是同一类底层能力）。但**STT 不需要等 ffmpeg 瘦身完成**——现在用
media_kit 自带的隐藏 Player 模式就能起步。

## 5. 结论与建议（回写 PRD ADR）

- **可行性结论**：可行，**不需要新增任何第三方依赖**——全部走操作系统自带能力 + 现有
  平台原生插件的自然扩展。
- **技术方向**：独立解码路径（仿阶段 B）+ **平台原生 STT 优先、否则关闭** + 通用
  `VmSttEngine` 注入口子（非 MCP 专用）+ 字幕叠层组件。
- **已否决**：whisper.cpp 作为默认引擎（推翻第一版结论，理由见 §0）；MCP 作为专项兜底
  （理由见 §2.2）。
- **待用户决策后才能转化为逐 Task 计划的点**：
  1. macOS 原生插件从零搭建——是否现在就投入（本身是一块不小的新增工程），还是先只做
     Android/iOS（已有插件、量级小）。
  2. Windows SAPI/COM 实现的优先级——真实原生工作量，是否值得在字幕这个"未排期"功能上
     先投入。
  3. 桌面端体验不对称（尤其 Linux 默认无字幕）是否需要在文档/README 里对用户显式声明。

## 6. 建议的落地顺序（草案，未排入具体 Task）

1. Spike：用 media_kit 隐藏 Player（同阶段 B 手法）独立解码一段音频，验证能拿到可用的
   PCM 分块，并验证与主播放位置的时间戳对齐精度。
2. `VmSttEngine` 端口抽象 + noop 默认实现。
3. Android 原生实现（ML Kit GenAI Speech Recognition）——现有插件基础上扩展，风险最低，
   优先做通。
4. iOS 原生实现（`SFSpeechAudioBufferRecognitionRequest`）——现有插件基础上扩展。
5. 字幕叠层组件 + `VmApi.subtitles` 面 + 事件表，先在 Android/iOS 跑通闭环。
6. 视 §5 待决点决定是否/何时投入 macOS 新插件与 Windows SAPI 实现。
7. 真机验证（含识别延迟、准确率、CPU/电量开销的实测）。

## 参考

- WhisperSubs（mpv 实时字幕生成先例，独立解码 + 分块转写）
  https://github.com/GhostNaN/whisper-subs
- iOS/macOS `SFSpeechAudioBufferRecognitionRequest`（支持任意音频 buffer，非仅麦克风）
  https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest
- Apple SpeechAnalyzer/SpeechTranscriber（更新的长音频转写框架）
  https://developer.apple.com/videos/play/wwdc2025/277/
- Android ML Kit GenAI Speech Recognition（支持文件/音频源输入）
  https://developers.google.com/ml-kit/genai/speech-recognition/android
- Windows `System.Speech.Recognition.SpeechRecognitionEngine`（`SetInputToAudioStream`
  等，支持任意音频流输入）
  https://learn.microsoft.com/en-us/dotnet/api/system.speech.recognition.speechrecognitionengine
- Linux 无标准 freedesktop STT API 的现状
  https://weesperneonflow.ai/en/blog/2026-06-18-voice-dictation-linux-open-source-tools-2026/
- MCP 不为实时音频流设计（请求/响应模型，非低延迟流式）
  https://github.com/microsoft/mcp-for-beginners/blob/main/translations/pcm/05-AdvancedTopics/mcp-realtimestreaming/README.md
- FFmpeg/libavcodec 支持独立解码器实例（音频/视频可各自独立解码）
  https://etiand.re/posts/2025/01/how-to-decode-audio-streams-in-c-cpp-using-libav/
