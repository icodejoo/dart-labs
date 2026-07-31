# 实时语音转文字字幕（STT）可行性研究与方向

> 2026-07-31 · 调研笔记 + ADR 回写 · 对应 [doc/PRD.md](../PRD.md) ADR
> 「实时语音转文字字幕（条件性未来项）」——本文档即该条要求的"后端可行性评估结论"。
>
> 结论先行：**可行，且没有 iOS PiP 那种硬阻断项（不需要 Mac 才能起步）。** 核心思路
> 不是从 libmpv 的实时播放管线里"抠"音频出来，而是**复用阶段 B 已验证过的套路——独立开
> 第二条解码路径**，与主播放解耦。现阶段只出方向、不写实现代码、不加依赖。

## 1. 问题本质与关键转念

字幕要做实时转写，直觉是"从 libmpv 正在播放的音频流里实时抽一份 PCM 出来"。但调研发现
**libmpv 没有干净的实时 PCM 抽头 API**——`ao=pcm` 是把整段音频转储成文件，不是流式接口；
libmpv 的 render API（`MPV_RENDER_API_TYPE_SW` 等）只覆盖视频，不覆盖音频抽头。

**关键转念**：字幕不需要"实时抽头"。参考真实存在的先例
[WhisperSubs](https://github.com/GhostNaN/whisper-subs)（一个 mpv Lua 脚本，边播边跑
whisper.cpp 生成字幕）——它的做法是**独立解码音频到小块 WAV、分块喂给 whisper.cpp、转写
结果按时间戳注入字幕**，完全不touch mpv 的实时播放管线。这与 videoman **阶段 B 拖动预览
缩略图已经验证过的架构**是同一个套路：mpv 的实时管线拿不到某个能力（阶段 B 是"缩放抽帧"，
这里是"音频流"），**解法都是开一条独立的第二解码路径**，而不是硬啃第一条。

于是问题收敛为：**独立解码音频 → 分块转写 → 按时间戳回灌字幕**，这是一个成熟范式（先例
已验证在 mpv 生态跑通），不是要突破的新工程难题。

## 2. 转写引擎选型：whisper.cpp（FFI），非平台原生 STT

调研了三条候选：

### 2.1 whisper.cpp 经 FFI（推荐）

- **MIT 协议**——与 videoman"发布不设限"的立场兼容，也不牵扯 ffmpeg 二期"卡 LGPL"的
  合规顾虑（whisper.cpp 与 ffmpeg 解码器许可完全独立）。
- **跨平台一致**：Windows/Linux x64（AVX2）+ macOS/iOS（Apple 加速）+ Android，**四端
  行为一致**——这正是 videoman 一路的价值取向（当初选 media_kit 而非各平台原生播放器，
  就是为了跨平台一致；STT 引擎选型延续同一个原则，不选平台原生 STT）。
- **生态已验证，非空白地**：pub.dev 已有 `whisper_ggml`（FFI 封装 whisper.cpp v1.8.3+，
  支持 Large-v3-Turbo，跨平台）等现成包，"能不能把 whisper.cpp 接进 Flutter"这件事本身
  没有不确定性，只剩"自己包一层轻量 FFI 还是直接依赖现成包"的工程选择。
- **性能实测数据（有据可查，非猜测）**：`tiny`（75MB/39M 参数）在几乎任何硬件（含树莓派、
  低端手机）上都**快于实时**；`base`（150MB）是"现代手机的实用默认档"，**速度约等于实时**；
  实测延迟约"**落后现场 0.5–2 秒**"（依模型档位）。这个延迟量级，videoman 自己的直播时移
  功能里"落后直播边缘"本就是一个被产品接受的正常态——字幕"迟 1-2 秒"不是新的体验门槛。

### 2.2 平台原生 STT（不推荐做默认，可留作可插拔选项）

- **iOS**：`SFSpeechAudioBufferRecognitionRequest` 明确支持喂**任意音频 buffer**（不限
  麦克风输入），技术上可行。
- **Android**：Google ML Kit 的 GenAI Speech Recognition API 明确支持文件/音频源输入
  （不限麦克风）。
- **不推荐做默认的原因**：两端 API 形状不同、配额/网络依赖不同（部分场景需联网），**桌面
  端（Windows/macOS/Linux）没有对应物**——直接违背 videoman"跨平台一致行为"的既定取向，
  会把"四端一致的能力"重新拆成"移动端一套、桌面端另一套（或没有）"。可以留作**可插拔的
  备选实现**（复用类似 `VmVolumePort`/`CallbackVolumePort` 的注入模式），但不做默认。

### 2.3 云端 STT API（不推荐做默认）

需要联网 + API key + 产生费用，且引入新的外部服务依赖——与"自包含库"定位不符，更适合作为
**可插拔实现之一**（同样走端口抽象），不是默认路径。且新增任何第三方依赖/服务都需按
CLAUDE.md 约定**先取得用户同意**。

## 3. 架构落点（与既有模式对齐，不新开一套范式）

延续 videoman 一路的"抽象端口 + 默认/可选实现 + 可注入覆盖"三件套（对齐 `VmBrightnessPort`/
`VmVolumePort`/`VmFrameExtractor`/`VmNetProbe` 的既有形状）：

- **core 端口抽象**（`lib/src/core/` 新增，暂拟 `VmSttEngine`）：输入一段 PCM/WAV 数据，
  输出时间戳文本片段流。默认实现留空/noop（同 `FallbackBrightnessPort` 的风格），真实实现
  （whisper.cpp FFI）放 `lib/src/platform_impl/`。
- **独立音频解码路径**：仿阶段 B 的"隐藏 `Player` 抽帧"模式——开一个不渲染视频、仅解码
  音频的 media_kit 实例（或未来 ffmpeg 瘦身后自建的轻量解码器，见 §4 协同点），按滚动窗口
  切块（参考 WhisperSubs 的 `CHUNK_SIZE` 调优经验：块太大延迟高，块太小转写质量和上下文
  都会受影响，需要实测调参）。
- **字幕叠层组件**：新增一个类似 `PreviewComponent` 的叠层组件，挂在既有组件树/皮肤/补丁
  机制上，不改变 `VmApi` 之外的契约——这与 SPEC.md 未来项小节原有的猜测一致，本次调研确认
  了这个落点仍然成立。
- **`VmApi` 面**：预计新增 `VmApi.subtitles`（字幕流，同 `preview` 的形状）+
  `VmSubtitleChanged` 一类事件，具体签名留到实现阶段确定。

## 4. 与二期 ffmpeg 瘦身（未开始的遗留任务 #4）的协同点

二期若自建裁剪版 ffmpeg，`CLAUDE.md` 已经记了一笔"顺带导出一个轻量 FFI 抽帧函数替换阶段 B
现在的重量级隐藏 Player 方案"——**同一个自建 ffmpeg，也可以顺带导出一个轻量 PCM 解码函数
供 STT 用**，两个需求（缩略图抽帧、STT 音频解码）用的是同一类底层能力（独立于 mpv 播放管线
的按需解码）。但**STT 不需要等 ffmpeg 瘦身完成**——现在用 media_kit 自带的隐藏 Player 模式
就能起步，跟阶段 B 当年的路径完全一样。

## 5. 结论与建议（回写 PRD ADR）

- **可行性结论**：可行。不存在 iOS PiP 那种硬阻断项，当前环境（无 Mac 限制）即可开始。
- **技术方向**：独立解码路径（仿阶段 B）+ whisper.cpp FFI（跨平台默认引擎，MIT 协议）+
  端口抽象（`VmSttEngine`，可注入平台原生/云端 STT 作为替代实现）+ 字幕叠层组件。
- **不建议做默认的路径**：平台原生 STT、云端 STT——理由见 §2.2/2.3，可留作可插拔选项。
- **待用户决策后才能真正开工的两件事**（不属于"可行性研究"范围，需明确同意）：
  1. **新增第三方依赖**：是依赖现成 `whisper_ggml` 包，还是自己包一层更薄的 FFI 绑定
     （更可控但工作量更大）——按 CLAUDE.md 约定需先取得用户同意。
  2. **默认模型档位与语言**：`tiny`（更快、精度稍低）vs `base`（现代手机的实用默认）；
     默认语言/是否自动语种检测。

## 6. 建议的落地顺序（草案，未排入具体 Task，需用户确认后转为类似
   `doc/plans/2026-07-31-phase-b-preview.md` 的逐 Task 计划）

1. Spike：用 media_kit 隐藏 Player（同阶段 B 手法）独立解码一段音频，验证能拿到可用的
   PCM/WAV 分块。
2. 引入 whisper.cpp FFI（依赖审批后），跑通"分块喂入 → 拿到文本 + 时间戳"的最小闭环。
3. `VmSttEngine` 端口抽象 + noop 默认实现 + whisper.cpp 实现。
4. 字幕叠层组件 + `VmApi.subtitles` 面 + 事件表。
5. 调参：`CHUNK_SIZE`/模型档位/延迟与准确率的取舍，参考 WhisperSubs 的实战经验。
6. 真机验证（含运算量在低端设备上的实际表现——`tiny`/`base` 的实时性因设备而异）。

## 参考

- WhisperSubs（mpv 实时字幕生成先例，独立解码 + 分块 + whisper.cpp）
  https://github.com/GhostNaN/whisper-subs
- whisper.cpp（MIT，跨平台 C/C++ 移植）
  https://github.com/ggml-org/whisper.cpp
- whisper_ggml（Flutter FFI 封装，跨平台，Large-v3-Turbo 支持）
  https://pub.dev/packages/whisper_ggml
- whisper.cpp 实时延迟与模型档位性能数据
  https://weesperneonflow.ai/en/blog/2026-06-23-whisper-cpp-setup-guide-local-speech-recognition-2026/
- iOS `SFSpeechAudioBufferRecognitionRequest`（支持任意音频 buffer，非仅麦克风）
  https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest
- Android ML Kit GenAI Speech Recognition（支持文件/音频源输入）
  https://developers.google.com/ml-kit/genai/speech-recognition/android
- FFmpeg/libavcodec 支持独立解码器实例（音频/视频可各自独立解码）
  https://etiand.re/posts/2025/01/how-to-decode-audio-streams-in-c-cpp-using-libav/
