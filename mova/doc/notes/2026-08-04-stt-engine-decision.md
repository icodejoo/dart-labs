# STT 引擎选型定案（2026-08-04）

承接 [2026-07-31-stt-subtitle-feasibility.md](2026-07-31-stt-subtitle-feasibility.md) 与
[2026-08-01-dynamic-loading.md](2026-08-01-dynamic-loading.md)，本篇记录实机测试后的最终决策。

## 结论

**当前只接入 sherpa-onnx 的离线双语 Zipformer（`zipformer-zh-en-2023-11-22`，int8 约
75MB：encoder+decoder+joiner+tokens），只覆盖中文/英文（含中英混说）。不引入多语言/
LID 网关/兜底模型——架构上预留扩展点，但不在本期实现。**

## 决策依据（实测，非文献）

用 sherpa-onnx 官方 GitHub Releases 模型 + 本地真实音频样本（zh/en/ja/ko 纯净样本 +
3 条中英混说样本，含 2 条自然口语化样本），对比过的候选：

- **Moonshine**：中文 CER 29-36%，淘汰。
- **SenseVoice-Small**（234M，int8 ~237MB）：中英尚可，但英文拼写常错乱
  （"TRIVAL"/"CHIEFTHIN" 这类），日韩输出是汉字乱码堆砌（不是它宣称支持的日韩水平），
  内置语种标签（`result.lang`）经实测完全不可靠（zh/ja/ko/en 全部返回 `<|yue|>`）。
- **paraformer-zh-small**（79MB）：与全量 Paraformer 近似持平，但仍不敌 Zipformer。
- **Zipformer-zh-en-2023-11-22**（本次定案）：8 个样本里中文/中英混说全面胜出，
  纯英文与其他方案打平。**唯一缺点：默认繁体输出**，简体需要额外接 OpenCC 转换
  （待办，未实现）。
- **whisper-tiny/small**：作为"大而全"候选测试过，small（int8 ~375MB）中英文本身
  可用，且自带 LID（`language=""` 自动模式），但**纯中文场景明显不如 Zipformer**
  （常年掉字），**中英混说会崩**（所有模型的通病，不限于 whisper）。
- **8 语言 Zipformer**（`ar_en_id_ja_ru_th_vi_zh`，PengChengStarling 项目训练，
  ~2000 小时/语言，共 ~1.6 万小时，int8 ~339MB）：不含韩语/西班牙语；中英混说场景
  明显劣于专用双语模型（英文部分整段听错）。
- 曾评估的语言识别（LID）网关方案（whisper-tiny 独立 LID 接口
  `SpokenLanguageIdentification`，纯语种识别 5/5 全对）**已搁置**——因为"一个大而全
  模型自带 LID + 自动路由"这条思路（whisper-small）本身在中文准确率上就不够，且额外
  引入 whisper-tiny 只做 LID 会多背 ~103MB，性价比不如直接不做多语言。

## 本期范围

- 只接入 zh-en Zipformer 一个模型，覆盖中文/英文/中英混说。
- 其他语种（日/韩/西/其他）**明确不支持**，不做兜底、不做占位 UI。
- 中文默认繁体输出——**待办**：接 OpenCC 转简体（尚未实现，不阻塞本期）。

## 架构预留（供后续扩展，不在本期实现）

若未来要加语种，已验证的可行路径（不要重新调研，直接照做）：

1. **多模型不做"检测失败再补"**——已实测两种失败检测信号均不可靠（SenseVoice 的
   `lang` 标签、Zipformer transducer 的 `ys_log_probs` 置信度，遇到分布外语言都会
   给出自信的错误输出，不会低置信度报警）。
2. **应采用"LID 前置网关"架构**：音频先过专用语言识别（whisper-tiny 的
   `SpokenLanguageIdentification` API，实测 5/5 准确；建议窗口 5-6 秒并按静音边界
   切分，3 秒窗口在混说场景下实测出现误判），拿到语种标签后再路由到对应转写模型。
   路由在转写之前完成，因此**不存在多模型输出合并问题**——各窗口按时间顺序拼接即可。
3. 若某语种没有专用小模型，**whisper-small 可作兜底**（自带 LID，可省去专用 LID
   模型），但纯中文场景仍应优先路由到 Zipformer，不能让 whisper 顶替。
4. 模型分发：**默认 GitHub Releases 源，宿主可自定义源**（已定案，见下）；多文件模型
   （Zipformer 是 encoder+decoder+joiner+tokens 四个文件）需要 `MovaSttModelProv`
   逐文件下载校验，不是单文件下载就完事。

## 模型分发架构（已落地一版，见下）

- 模型体积大，**不随包发布，运行时按需下载**（iOS 用 On-Demand
  Resources/Background Assets 语义即可，Google Play 之外的安卓渠道也没有限制，因为
  这是"数据"不是"代码"，参见 [2026-08-01-dynamic-loading.md](2026-08-01-dynamic-loading.md)）。
- **⚠️ 2026-08-04 修正**：sherpa-onnx 官方 GitHub Releases 发布的是
  `.tar.bz2` 压缩包（内含 encoder/decoder/joiner/tokens 多个文件），**不是可逐个
  直链下载的裸文件**。曾评估"端上解压 bzip2"，但 Dart 标准库没有 bzip2 解码器，
  唯一选项是引入三方包 `archive`——**已否决**，改为**本机手动解压一次，把解出来的
  裸文件重新托管**（自己的 GitHub Release 或 CDN），`MovaSttModelProv` 只管逐个
  下载裸文件，不做任何解压。也就是说"默认 GitHub Releases 源"实际指
  **mova 自己重新托管的 Release**，不是 `k2-fsa/sherpa-onnx` 官方仓库的
  Release（那边下的是压缩包）。**待办**：把 zh-en Zipformer 的四个文件解压后
  重新上传到 mova 自己的 GitHub Release，产出实际下载地址。
- 复用阶段 B 预览缩略图的下载/缓存基础设施模式，**已实现**：
  `lib/src/core/stt/model_spec.dart`（`MovaSttModelFile`/`MovaSttModelSpec`/
  `MovaSttModelFiles`，每个文件独立 URL + 可选 `sizeBytes`/`sha256`）、
  `lib/src/core/stt/model_dir_provider.dart`（`MovaSttModelDirProv` 端口，
  镜像 `MovaThumbDirProv`）、`lib/src/core/stt/model_provider.dart`
  （`MovaSttModelProv`/`MovaSttModelLoader`：按模型 id 分子目录、按已缓存
  文件大小跳过重复下载、逐文件进度流、任一文件失败即抛
  `MovaSttModelLoadError`——**不像预览缓存那样静默降级**，因为缺一个模型
  文件会直接挡住整个 STT 功能）、`lib/src/platform_impl/stt_model_dir_impl.dart`
  （`TempSttModelDirProvider`，落在应用支持目录而非临时目录，避免被系统清理）。
  复用 `IoHttpFetcher`（已在 core 里，无新依赖）。**`sha256` 字段目前只是占位**
  ——校验逻辑只做了"文件已存在且大小匹配 `sizeBytes`"这一层廉价检查，真正的哈希
  校验需要 `crypto` 包（又是一个新依赖，未评估，待定）。**磁盘按字节预算淘汰
  （同 `MovaDiskThumbCache` 的做法）尚未实现**——当前 `MovaSttModelLoader` 只有
  `remove(modelId)` 手动删除，没有自动淘汰旧模型，留作后续任务。

## UI（已定案，待实现）

- 内置一个"语言/模型目录" widget：展示当前支持的语言与各自使用的模型（本期只有
  一行：中/英 → Zipformer），预留多行扩展。
- 播放器顶栏字幕按钮 → 弹出语言选择（本期单选，因为只有一个模型；UI 组件按多选
  设计，为未来多语种铺路，但本期实际只会有一个可选项）。

## Native 引擎绑定（已落地一版，见下）

- **拆成独立包 `mova_stt`**（monorepo 内，`dart-labs/mova_stt/`）——原因：
  官方 `sherpa_onnx` Flutter 插件会拉入各平台原生二进制子包
  （`sherpa_onnx_android_arm64`/`sherpa_onnx_ios` 等），而 Flutter 的插件原生
  依赖是**构建期静态绑定**，不是运行时按开关决定要不要打包；若把它塞进
  `mova` 主包，所有用 mova 的 App 都会背上这部分体积，不管有没有用
  字幕功能。`mova` 主包**零依赖 `sherpa_onnx`**，只暴露 `MovaSttConfig.engine`
  抽象接口；`mova_stt` 依赖 `mova`（monorepo 内 path 依赖）+
  `sherpa_onnx`，实现具体的 `ZipformerSttEngine`。想要字幕功能的宿主自己额外加
  一个 `mova_stt` 依赖，不需要的宿主完全不受影响。
- **接口补了一个漏洞**：`MovaSttEngine.start()` 原来不带参数——但引擎自己并不
  知道 `feed()` 喂进来的音频对应播放器哪个时间点，没法给 `MovaSttCue` 打对
  时间戳。改成 `start(Duration atPosition)`，引擎从这个基准点按累计采样数
  （采样数/采样率）推算每条字幕的 `start`/`end`。`MovaSttSvc` 已同步改造
  （用它本来就在维护的 `_position`）。
- `ZipformerSttEngine`（`mova_stt/lib/src/zipformer_engine.dart`）：包住
  `sherpa_onnx` 的 `OfflineRecognizer`/`OfflineStream`（`createStream`→
  `acceptWaveform`→`decode`→`getResult().text`），**API 形状已对照
  `sherpa_onnx` 1.13.4 包源码逐字核实**（不是凭记忆猜的）——`initBindings()`
  必须先调一次、`OfflineModelConfig(transducer:, tokens:, numThreads:,
  debug:, modelType: 'transducer')`、`OfflineRecognizerConfig(model:)` 等字段
  名全部核对过。
- **分段策略是占位方案，非 VAD 门控**：Zipformer 用的是**离线（非流式）**
  transducer，一次解码一整句，不能增量识别。当前实现是固定窗口
  （`flushIntervalSamples`，默认约 16000×6 = 6 秒，对应本次会话实测出的
  "3 秒窗口在中英混说场景会误判、6 秒窗口没问题"这一结论）——分段点可能切在
  句子中间，比按静音（VAD）对齐的分段粗糙。换成 VAD 门控分段
  （`silero-vad`，sherpa-onnx 生态里已有现成模型）是后续任务，本次未做。
- **✅ 2026-08-05 已验证：`ZipformerSttEngine` 本身跑通，识别效果正确**——
  用 sherpa-onnx 官方 release 资产里的真实模型文件（从
  `k2-fsa/sherpa-onnx` release `asr-models` 下载解压
  `sherpa-onnx-zipformer-zh-en-2023-11-22.tar.bz2` 得到）+ 官方测试 wav
  （`test_wavs/0.wav`），直接调 `ZipformerSttEngine.transcribeWavFile`，
  在 **Windows 桌面**（`flutter run -d windows`，example 新增的
  `spike_stt_engine.dart`）上识别出正确的中英混说文本
  `"SPEND ON 在什么上面花费 它不光是时间也可以是金钱"`（0:00:00.00 →
  0:00:03.38）——sherpa_onnx 原生绑定加载、`OfflineRecognizer` 构造、
  `start`/`feed`/`getResult` 整条链路确认可用。**Android 真机上同样的验证
  第一次踩到两个坑**：① `flutter install` 卸载旧版会清空
  `Android/data/<pkg>/files/` 下 seed 好的模型文件，需要每次重装后重新
  `adb push`；② 原生库报过一次 `tokens: '...' does not exist`（即使
  `adb shell ls` 显示文件存在、大小正确），怀疑是 Android FUSE 存储层的
  瞬时缓存问题，**未复测确认是否真的解决**，Windows 验证通过不能直接
  代表 Android 也稳定——下次有真机时应该把同一个 spike 在 Android 上完整
  跑一遍确认。
- **⚠️ 仍然缺失：从"正在播放的视频"实时喂音频给 `feed()` 这条链路完全没有
  实现**（2026-08-05 发现）——`MovaSttEngine.feed()` 在整个仓库（`mova` +
  `mova_stt`）没有任何调用点，`MovaSttSvc.start()` 只转发调用
  `engine.start(position)`，之后谁来持续调 `feed()` 喂音频没人做。已验证的
  是"引擎本身能不能正确识别一段音频"，不是"打开视频、开字幕，实时出字幕"这个
  端到端场景——后者需要先把音频抽取管线接上（`MovaAudioPuller`/
  `mpv_audio_extractor_impl.dart` 是唯一相关实现，但自己文档标注"未验证
  spike，没有代码依赖它"），是独立的、更大的一块工作，本次未做。
- **模型分发地址仍是占位**：`mova_stt/lib/src/model_specs.dart` 里
  `zipformerZhEnModelSpec()` 的默认 `baseUrl` 是假地址
  （`REPLACE-ME.example.com`），需要先完成"本机解压四个文件、重新托管"这一步
  （见上文模型分发架构一节）才有真实可用的下载地址。
- **✅ 2026-08-05 真机（Windows 桌面）实测抓出并修复了两个真 bug，均在
  `ZipformerSttEngine`（`mova_stt/lib/src/zipformer_engine.dart`）**——
  用真实课程视频（约 11 小时，ffmpeg 提取音频，`-vn -ac 1 -ar 16000
  -acodec pcm_s16le`，耗时仅数十秒、可忽略不计）批量转写时发现：
  1. **`feed()` 分段判断只检查一次，没有循环**：`if (_pending.length >=
     flushIntervalSamples) _flush()` 只触发一次，而 `_flush()` 把
     `_pending` 全部（不管多大）当一句话整体解码——一次性喂入超过一个窗口
     的音频（如 `transcribeWavFile` 整文件一次性 `feed()`）会把全部采样
     当成一句巨长的话，超出离线 transducer 解码设计范围。已改成 `feed()`
     用 `while` 循环持续切出 `flushIntervalSamples` 大小的窗口，`_flush`
     加 `windowed` 参数区分"只切一个窗口"（`feed` 循环用）与"收尾清空剩余"
     （`stop()` 用）。
  2. **收尾零头喂进识别器会让原生进程直接 `abort()`**：真实录音长度几乎
     不可能是 `flushIntervalSamples` 的整数倍，`stop()` 的收尾 flush 经常
     会喂一个不到 1 秒的零头——喂给 sherpa-onnx 后触发
     `onnxruntime ... Conv node ... Invalid input shape: {1,39}`（特征帧
     数太少，撑不住 Zipformer 下采样卷积层），原生库直接 `abort()`
     ——**这是本次最难查的一个坑**：先用纯静音跑 300 次 create→decode→
     free 循环排除了"单纯迭代次数/资源泄漏"的可能（全程无异常），再对
     真实内容做二分定位（15 分钟整体崩→拆两个 7.5 分钟段各测一次→确认
     是收尾零头，不是内容本身某处的问题），才定位到根因。修复：`_flush`
     解码前把过短的 chunk 补零垫到 `_minDecodeSamples`（16000，即 16kHz
     下 1 秒），垫的静音在上报的 cue `end` 之后，不污染时间戳。
  修复后完整 11 小时音频批量转写跑通，无崩溃，`formatSrt` 产出真实 `.srt`
  文件；真实讲课片段识别质量可用（示例：`"技术的深度还有管度比如说做一个
  简单的单点登陆功能"`，语义基本正确，个别字词有误——与文档里"固定窗口非
  VAD、分段较粗糙"的已知局限一致）。

## UI（已落地一版，见下）

- `SubtitleOverlayComponent`（`MovaSlot.overlay`）：渲染覆盖当前播放位置的字幕；
  没有配置引擎时（`api.stt.languages` 为空）整体不渲染，对应
  `PipButtonComponent` 的"不渲染死控件"约定。同时监听 `api.stt.cues`（新字幕
  产出）与 `api.progress`（位置推进）——因为字幕可能在没有新字幕产出的情况下
  就因为 `end` 已过去而不再覆盖当前位置，只监听 `cues` 会漏掉这种情况。
- `SubtitleButtonComponent`（`TopBarComponent` 的子组件）：同样在无引擎时不
  渲染。点击弹出底部选择器，本版本只有两行——"语言联合入口"（本版本只有
  一个引擎，所以是一整条 `zh/en` 而非每语言一行）与"关闭字幕"
  （`MovaStrs.subtitleOff`，新增字段，避免组件里出现字面量中文）。是否已
  开启是组件本地状态（`MovaApi.stt` 没有暴露"是否在运行"的字段），后续如果
  要在多处入口保持同步，需要把这个状态提升到 `MovaState`。
- 新增 `test/ui/subtitle_test.dart`，7 个测试覆盖：无引擎时两个组件均不渲染、
  开关字幕的完整交互、字幕随 cue 到达显示、随 progress tick 越过 `end` 消失。

## 批量预转写（点播专用，已落地一版，见下）

**背景**：点播（非直播）场景下，整段音频在开始转写前就已完整存在，没必要
用直播那套"边播边喂固定窗口"的实时循环——可以一次性转写、缓存成字幕文件，
之后重播只读文件，不用模型常驻。

- `core/stt/srt.dart`：`parseSrt`/`formatSrt`——纯 Dart，SRT 格式读写，
  容忍常见变体（CRLF、BOM、块间空行），畸形块跳过而非抛异常。9 个测试
  （含 round-trip）。
- `core/stt/subtitle_dir_provider.dart` + `platform_impl/stt_subtitle_dir_impl.dart`：
  `MovaSttSubDirProv`/`TempSttSubtitleDirProvider`——与
  `MovaSttModelDirProv` 是**两个独立端口**（虽然默认都落在应用支持目录下的
  子文件夹），因为缓存的东西生命周期不同：字幕文件按来源 key、模型文件按
  模型 id key，宿主可能想分别清理。
- `core/stt/subtitle_store.dart`：`MovaSttSubStore`/`MovaFileSttSubStore`——
  按来源 URI 的 `fnv1a64` 哈希命名 `.srt` 文件（复用预览缓存同一套 key 命名
  约定），损坏文件降级为"未缓存"而非崩溃。7 个测试。
- `mova_stt`：`ZipformerSttEngine.transcribeWavFile(wavPath)`——复用引擎
  自己的 `start`/`feed`/`stop` 循环，用 `sherpa_onnx` 自带的 `readWave()`
  读整个 WAV，一次性喂完，收集期间产出的全部字幕返回。**分段逻辑与直播路径
  完全一样**（还是固定 6 秒窗口，未接 VAD），批量模式唯一的优势是不用按
  实时节拍走——所以 API 形状核实过（`readWave` 返回 `WaveData(samples,
  sampleRate)`），逻辑复用现成的，但同样**未在真机跑过**。
- `core/stt/audio_extractor.dart` + `platform_impl/mpv_audio_extractor_impl.dart`：
  要批量转写，得先把视频的完整音轨解出来。候选方案是 mpv 的 `ao=pcm`/
  `ao-pcm-file` 音频输出驱动（借第二个无头 media_kit `Player`，跟
  `MpvFrameExtractor` 抽帧同一套打法）。

  **⚠️ 2026-08-04 真机实测：方案不成立，`MpvAudioExtractor` 现有写法确认
  失败。** 用 Android 真机（`STG AL00`，Android 12）跑了
  `example/lib/spike_audio_extract.dart`（10 秒测试片段
  `BigBuckBunny.mp4`）：`player.stream.completed` 60 秒内从未触发；用 `adb`
  查设备缓存目录，**连一个部分写入的 WAV 文件都没有生成**——不是"解码了一半
  没收到完成信号"，是整条管道从头就没跑起来。说明构造 `Player()` 之后再用
  `NativePlayer.setProperty` 设置 `ao`/`ao-pcm-file`/`vid`/`untimed`
  这几个属性**没有生效**，印证了文档原先标注的疑点之一：这几个大概率是 mpv
  的**启动选项**，不是能在运行时通过 `setProperty` 补设的属性。

  **结论**：`platform_impl/mpv_audio_extractor_impl.dart` 现在的实现是**已知
  不可用**，不要在此基础上继续叠代码。

  **⚠️ 2026-08-04 两条替代路线并行调研，结论：都没有捷径**：

  1. **`ao=pcm`/`ao-pcm-file` 本身就是不可靠的老驱动，不是参数没调对**——
     mpv 官方 issue 里有完全相同症状的历史记录（mpv-player/mpv#7833：
     "静默地什么文件都不生成"，0.32.0 版本），说明这个驱动本身不稳定、
     会静默失败，即使调对了参数组合也不该拿来做正式功能依赖。这条路
     **判死刑**，不要再往这个方向调试。
  2. **绕开 media_kit、直接 FFI 调 ffmpeg 也没有现成的路**：`ffipeg`
     （dra11y/ffipeg-dart）是唯一真正的 `dart:ffi` 直接绑定（不是命令行
     包装），支持 Android/iOS/桌面，但**自己不带 ffmpeg 构建产物**，需要
     自己提供/链接一份 ffmpeg 动态库；发布已 22 个月，活跃度存疑。
     `ffmpeg_kit_flutter` 及分支**已确认死亡**（官方 2025-01 正式停止维护、
     仓库归档、二进制包撤下），而且它本来就是命令行子进程包装，iOS 不允许
     执行任意二进制，架构上就不适用。"蹭 media_kit 已打包的 ffmpeg 省一份"
     理论上可能（`DynamicLibrary.process()`），但无人验证过的先例、
     Windows 不支持、media_kit 的 libmpv 是否导出公开符号也不确定——本身
     还需要单独一次 spike。

  **最终结论：批量预转写这条功能线，依赖"自己构建/链接一份 ffmpeg + 自己写
  FFI 绑定"，跟已规划的"二期 ffmpeg 瘦身"是同一项工程，没有绕过去的捷径。
  在二期 ffmpeg 瘦身完成、有了自建 ffmpeg + FFI 绑定之前，批量预转写功能线
  暂停迭代，不再零敲碎打——`core/stt/audio_extractor.dart` 端口保留（抽象
  本身没问题），但 `platform_impl/mpv_audio_extractor_impl.dart` 这个实现
  应视为废弃，等有了自建 ffmpeg 再重新实现，不要修补。**

## 授权注意

sherpa-onnx 是 Apache-2.0，模型权重各自协议不同但目前用到的
（Zipformer/whisper/SenseVoice/paraformer）均可商用分发，无 GPL 冲突。
