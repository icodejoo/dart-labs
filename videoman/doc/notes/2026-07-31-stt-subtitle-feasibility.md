# 实时语音转文字字幕（STT）可行性研究与方向

> 2026-07-31 起 · 调研笔记 + ADR 回写。
>
> **⚠️ 方向已在 2026-08-01 第三版调整——先读这条**：动态加载调研（见
> [2026-08-01-dynamic-loading.md](2026-08-01-dynamic-loading.md)）厘清了「引擎=代码 /
> 模型=数据」的区别，**化解了 whisper.cpp 之前"新依赖 + 模型太大"的两个顾虑**（引擎仅
> 几 MB 随包；模型是数据、运行时下载、全平台合规、天然满足"不内置模型"）。因此 STT 方向
> **由"平台原生优先、否则关闭"调整为倾向 whisper.cpp（引擎随包 + 模型运行时下载，四端
> 行为统一，避开 Android ML Kit alpha 的坑）**。下文 §0–§6 是 2026-07-31 第二版原文
> （主张平台原生优先），**部分结论已被上述调整覆盖**，独立解码路径、MCP 否决、字幕渲染
> 路径待定等其余结论仍有效。
> **引入 whisper.cpp 作为新第三方依赖仍需用户正式确认后才拆落地 Task**（CLAUDE.md 依赖需同意）。
>
> ——以下为 2026-07-31 第二版原文——
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

**关键转念**：不需要"实时抽头"，只需要"按滚动窗口分块取一段音频"。参考真实存在的先例
[WhisperSubs](https://github.com/GhostNaN/whisper-subs)（一个 mpv Lua 脚本，边播边转写
字幕）——做法是**独立解码音频到小块、分块喂给转写引擎、结果按时间戳注入字幕**，完全不碰
mpv 的实时播放管线。

**抽取分块用谁来解码——不用第二个 media_kit `Player`（用户已否决，CPU/内存翻倍），改用
各平台原生的轻量音频抽取 API**：不是播放器（不渲染、不建播放状态机），只做"定位到某段
时间范围 + 硬解一条音轨"，比再起一个完整 libmpv 实例轻得多：

- **Android**：`MediaExtractor`（`selectTrack` 选中音轨 + `seekTo(startUs,
  SEEK_TO_CLOSEST_SYNC)`）+ `MediaCodec`（硬件解码），循环读到目标结束时间戳为止，
  输出即 PCM。是官方文档与社区实践里"抽某段音轨"的标准写法。
- **iOS**：`AVAssetReader` + `AVAssetReaderTrackOutput`（`outputSettings` 指定
  `kAudioFormatLinearPCM`），设置 `reader.timeRange = CMTimeRange(start:, duration:)`
  后循环 `copyNextSampleBuffer`。是苹果官方文档给的标准范式。
- **风险点（未验证）**：有资料提示 `AVAssetReader` "频繁重建实例来做 seek 很慢"，但那是
  给"拖动条实时取帧"这种高频场景踩的坑；字幕是按固定滚动窗口周期性取一段，频率低得多，
  影响应有限，但需要后续 spike 实测确认，不能想当然。
- 这两个 API 都装在**已有的原生插件**里（Kotlin/Swift，和加 PiP/音量方法同一量级的工作
  量），Dart 侧只需要传 URI + 时间范围，原生侧一次调用内完成"抽取 PCM → 喂 STT 引擎 →
  回文本"，不需要把 PCM 字节整块传回 Dart，减少一次 FFI/Channel 大数据搬运。
- **v0 spike（media_kit 隐藏 `Player` + `ao=pcm`）已作废，仅留存工程教训**：见附录 A——
  已验证过 `Media(start:, end:)` + `stream.completed` 能正确圈定分块边界（不能靠
  wall-clock `pause()`），但因为会同时跑两个播放器（CPU/内存翻倍）被否决，不采用。
  按滚动窗口切块参数（块太大延迟高，块太小转写质量和上下文都会受影响）需要在原生抽取
  路线下重新调参实测，附录 A 的字节数结论对新路线不再适用。

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

- **core 端口抽象**（`lib/src/core/`，暂拟 `VmSttEngine`）：输入"URI + 时间范围"，输出
  带时间戳的文本片段流（**抽 PCM 这一步下沉到原生实现内部**，不在 core/Dart 侧过一遍字节，
  见 §1）。默认实现按平台探测原生能力，探测不到则 noop/关闭（同 `FallbackBrightnessPort`
  的风格）；真实原生实现放 `lib/src/platform_impl/`（`NativeSttEngine` 之类，
  Android/iOS/macOS/Windows 分别实现，Linux 无实现即关闭）。
- **音频抽取路径**：见 §1，走各平台原生轻量抽取 API（Android `MediaExtractor`+
  `MediaCodec`、iOS `AVAssetReader`），**不额外起 media_kit `Player`**，抽取与 STT 调用
  在同一次原生方法调用内完成。
- **字幕渲染路径——待定，非已拍板**：倾向 Flutter 侧叠层组件（新增一个类似
  `PreviewComponent` 的叠层组件，挂在既有组件树/皮肤/补丁机制上，不改变 `VmApi` 之外的
  契约）——理由是避免破坏组件化/`VmTheme` 主题化架构、避免被画面的 `Transform.scale`/
  裁剪连带影响。但用户认为 mpv 原生字幕渲染（`libass`，喂 `sub-add`/字幕轨）路径仍可能
  有用，**要求先保留 `libass`、等瘦身构建实测出体积数字后再综合权衡**，不要现在就删。
  两条路的取舍详见
  [2026-07-31-libmpv-slimming-options.md](2026-07-31-libmpv-slimming-options.md) §5。
  下文（`VmApi.subtitles`、字幕叠层组件）按 Flutter 侧方案描述，**若最终改走 mpv 原生
  渲染，这部分需要重新设计**。
- **`VmApi` 面**（若走 Flutter 侧方案）：预计新增 `VmApi.subtitles`（字幕流，同 `preview`
  的形状）+ `VmSubtitleChanged` 一类事件，具体签名留到实现阶段确定。

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

1. **Spike：用 media_kit 隐藏 Player 独立解码一段音频——已完成（2026-07-31），结论见
   附录 A：可行，但机制与最初设想不同**（要用 `Media(start:, end:)` 圈定范围 + 等
   `stream.completed`，不能靠 wall-clock `pause()`）。
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

## 附录 A：音频抽取分块 spike 实测结论

实测于 2026-07-31，Windows 桌面（`dart run`，直接用 `example/build` 下已编译好的
`libmpv-2.dll`），片源为 example 已用的 GitHub 示例 mp4（时长 60s），目标分块为
`[5s, 8s)`（3 秒）。脚本跑完即删（`spike_audio_extract.dart`，两版思路见下），不进
package 正式代码。

**v1（`ao=pcm` + wall-clock `pause()`）——FAILED，且是静默失败**：`native.setProperty`
设好 `ao=pcm`/`ao-pcm-file`/`ao-pcm-waveheader` 后 `seek(5s)` → `play()` → 按真实时钟
`await Future.delayed(3.5s)` → `pause()`。产物文件头合法（`PASS` 通过了"有没有写出 WAV"
的粗检），但用 `ffprobe` 复核实际时长发现是 **60.07 秒**（几乎是整条音轨），不是预期的
3.5 秒。**根因**：`ao=pcm` 这个输出驱动没有真实设备可同步，mpv 不会把解码/写入速率锁定
到 wall-clock 实时——它是"能多快写多快"，我们基于真实时间设的 `pause()` 定时器完全管不住
它，实际观测到的现象是 pcm 落盘几乎瞬间跑完了整段解码。**这是本次调研新发现的一个坑**，
提醒以后任何"靠 wall-clock 定时器卡 mpv 输出边界"的设计都不可靠，必须用 mpv 自己的边界
机制。

**v2（`Media(uri, start:, end:)` + `stream.completed`）——PASS**：改用 media_kit 的
`Media` 构造参数 `start`/`end`（内部映射到 mpv 原生的 `--start`/`--end` 选项，在解码层面
就圈定范围，不依赖任何外部计时），配合监听 `player.stream.completed` 判断分块解码完成
（而不是自己算等多久），其余 `ao=pcm` 系配置不变。产物实测：

```
预期: 44100Hz × 2ch × 4B(float32) × 3s = 1,058,400 字节
实测: 1,058,468 字节（含 WAV 头开销，几乎完全吻合）
ffprobe 复核: Duration: 00:00:03.00 / duration=3.000000（精确到毫秒级）
```

**结论**：

- **可行，机制已定位**：分块抽取音频必须走「一次性 `Media(start:, end:)` + 等待
  `stream.completed`」，**不能**靠"seek 后 wall-clock 定时器 + pause()"（v1 的坑）。
  实现时每个分块要么开一个新的隐藏 `Player`，要么复用一个隐藏 `Player` 反复 `open()`
  新的 `Media(start:, end:)`（后者更省资源，待实现阶段实测切换开销）。
- **解码速度远快于实时**：v1 意外证实了这点——一次 `play()`+短暂等待就能把整条 60s
  音轨解码完，说明按滚动窗口分块抽取音频、喂给转写引擎，产能上完全跟得上主播放进度，
  不会成为瓶颈。
- **本 spike 只验证了"边界正确 + 数据非空"，未验证时间戳对齐精度**（即分块起点是否
  精确对应源媒体的真实播放位置，`hr-seek` 等精确 seek 选项在实现阶段需要专门测）；
  §6 步骤 5（字幕叠层组件联调）阶段需要补一次真机/精确对齐验证。
- 不影响 §5 的结论与两个待用户决策点——本 spike 只解决"抽取机制选型"这一个工程细节，
  不改变"可行、走平台原生 STT"的整体方向。
