# 暂停池画面可读信号（2026-11-05）

## 成因与证据边界

基线 HEAD `faf84715`，2418 项测试。只读参照 CP3 结果文档第三/四轮与 example/tool/coverage_evidence，未运行真机、adb 或 Gradle。第四轮原始直截 17/30 null，renderer future 后仍 8/30，额外 100ms 后 0/30；首次成功在 bind 返回后 562–730ms。

- `MovaFeedEnginePool._openBinding` 的 ready 只认 open 接受；不是首帧、VO 提交或截图就绪。bind 不应变成强制建面/截图，否则拖慢所有池用户，破坏 lazyVideo 收益。
- `MovaFirstFrameGate` 可从暂停尺寸、buffering、progress、grace 或 PLAYBACK_RESTART 落地。RESTART 未携带截图命令完成确认；这些信号保持原来的加载语义。
- `MovaMpvKernel` 在 lazyVideo 模式下由 renderHandle 创建 VideoController；open 等已有控制器的 platform 准备、补选 vid，但没有等待一帧成为 screenshot-raw 的可读输入。无控制器时 screenshot 明确返回 null，不为截图隐式创建纹理。
- 本机锁定的 media_kit_video 2.0.1 AndroidVideoController：videoParams 尺寸回调中 await SetSurfaceSize，然后完成 waitUntilFirstFrameRenderedCompleter；widListener 另经锁先设 vo=null，再设置 surface/wid/vo，并 seek 当前点。这个一次性 completer 不是每个池源的纹理上传/VO 提交 fence。
- media_kit 1.2.6 NativePlayer.screenshot 经 isolate 执行 mpv screenshot-raw，只有返回节点包含有效图片才编码成功。MovaMpvKernel 之前只是单次透传。

因此已证明的是“首帧/尺寸准备早于实际截图成功”的窗口；不能仅由 Dart 信号断言每次空帧究竟在解码、VO 重配置、GPU 上传哪一步。暂停态通常最终有可读帧（本次 17/17 后续恢复），但在首帧事件时不能确认已提交到 VO。新判据直接确认实际截图结果，不臆造原生属性的保证。

另一个关键事实：修复前仓库**没有 MovaEngine.screenshot**。只有 MovaKernel.screenshot，夹具直接访问 VideoController.player，绕过内核及引擎。

## 方案与取舍

增加可选能力 `MovaFrameCapture.screenshot()`，MovaEngine 和 MovaCutoverEngine 实现，主入口导出。**MovaApi、MovaKernel、MovaState 与事件均无新增成员**。自定义 MovaApi 不必适配；宿主用 is 探测。

```dart
await pool.bind(index, source); // 默认暂停预热
final api = pool.slotFor(index)?.api;
final image = api is MovaFrameCapture
    ? await (api as MovaFrameCapture).screenshot()
    : null;
// image 非空即本次可读画面证据；null 必须作为未就绪/失败处理。
```

暂停时等待原 rendered 信号，随后每 25ms 再尝试内核截图。null/空字节不能完成为成功；真实非空编码图片即完成。整个调用含原生截图最多等待 1 秒，异常、超时明确返回 null，不播放、不 seek、不改意图。播放态单次尝试，不增加重试。open/加载尝试变更或 dispose 后丢弃结果；cutover 额外捕获 active 与 renderEpoch，防止旧画面跨提交返回。

没有修改 MovaMpvKernel 的单次截图契约。重试放在持有 rendered、播放状态和加载代际的引擎层，避免复制首帧状态机；普通与 cutover 共用同一实现。超时无法取消已经发出的 media_kit 原生命令，迟到结果丢弃且停止后续重试。

为何仍增加可选公开面：仅修内核无法让宿主通过 MovaApi 确定地取帧，现有路径只能越层取 controller.player；池 bind 的 void Future 也无法明确返回截图失败。可选接口是最小可用入口，不扩充既定禁止增加成员的 MovaApi。既有 bind、ready、rendered、事件、直接 player 截图的默认行为不变，只有显式调用新能力才有等待成本。

未选 video-reconfig/vo-configured/estimated-frame-number：事件与可读帧之间没有已证实的 fence 关系，而且暂停态可能没有下一事件。也未缓存永久 ready=true：切源、seek、VO 重配置都会令缓存过期。信号是本次 Future 的非空结果，不保证下一次原始截图或 Flutter 已合成显示。

## 自动验证

新增假内核回归，均通过真实 pool.bind 预热后调用；普通/cutover 两侧覆盖首帧已到但前两次 null、空字节恢复、永久 null、原生命令挂起、切源、销毁、播放态单次与异常；另外覆盖自定义引擎不支持可选能力，以及真实 cutover 提交后丢弃旧帧、后续转发新引擎。合计新增 18 项。

临时仅回退“首次空帧后继续等待”为“首次空帧立即返回”，保留接口以使测试可编译，17 项中 **4 项变红，13 项通过**；恢复实现后全绿。此为行为回退，不是拿旧代码缺少新符号的编译失败充数。既有行为断言均未改写；仅 test/public_api/snapshots/mova.txt 增加一条新能力导出。旧快照作为历史导出集合没有错，但新增可选公开面后再要求集合完全不变已不符合本次契约；保留所有原有条目和 show/hide 约束。

- `flutter analyze --no-pub lib test`：0 issues。
- example `flutter analyze --no-pub`：修改前后均 41 issues；新改动文件无诊断。
- `python example/tool/run_matrix.py --check`：92 batches / 135 IDs / 6 manual，PASS，无设备操作。
- `test_run_matrix.py`：66 项通过；`test_cp3*.py`：12 项通过。
- 额外 Python 全目录 discover：164 项，1 个既有失败、2 个平台 skip；失败为 test_shot_guard 的历史脚本静态扫描，基线已跟踪的 example/tool/shot_run.py 含裸 screencap。该脚本及守卫测试本轮未修改，未执行脚本/adb。此额外检查不冒充全绿。
- 最终 `flutter test --no-pub --concurrency=3 --reporter expanded`：2436 项全绿（2418 + 18），用时 1:49。首次全量曾仅因新增导出未同步快照失败；补快照并加 cutover 提交边界回归后，最终完整运行全绿。

## 新 APK 复验口径

夹具新增 `CP3_HEADERS_READY=true` 构建开关，建议与 `CP3_HEADERS_R4=true` 同时启用。必须重新构建 APK；旧 APK 不含产品能力和新判据。本轮不构建、不上机。

headers 保留原始 extract/pool 检查与 R4 renderer/timed 对照；增加 pool-ready（普通）和 pool-ready-cutover（cutover 门面）独立实例，每个 quality 检查各 6 次，共每侧 30 次授权、30 次拒绝。每次真实挂载，bind 返回后立即调用新能力，不先等待原始截图或额外 sleep。保存 bindReturnedMs、captureAtMs/ReturnedMs/WaitMs、null、字节数、实际图片解码结果、暂停状态、首帧来源与鉴权 HTTP 回执。

验收：每侧授权截图 null=0/30，图片可解码=30/30，保持暂停；拒绝对照解码成功=0/30且回执403；记录耗时分布，API 总等待上限1秒（设备调度耗时单列，不能以宽松计时替代产品单测）。超时/null 必须保留失败，不能再加 sleep 重试覆盖。原始路径仍可能 null，不能用新增组成功抹去旧原始证据。新组通过代表可选截图入口解决可读窗口，不代表旧 renderer future 被升级成合成器 fence，也不代表 CP3 整体通过。


## 第五轮无效的原因与修正

本节替代上文的 25ms、rendered 门控及 1 秒上限描述；历史验证记录保留。此次仅离线读取第五轮原始 CHECK，不运行真机、adb 或 Gradle。

### 原始时序与候选排查

只读证据：`example/tool/coverage_evidence/matrix-cp3-headers-r5-20261105-111319/matrix-cp3-headers-r5-20261105-111319-cp3-headers.json` 的 CHECK → numbers.nativePaths → samples.observations.authorized。完整首批普通 null=16/30、cutover null=11/30；27 次失败全部等待约 1 秒才返回（普通 1001–1085ms，cutover 1001–1024ms），返回时均 rendered=true、firstFrameSignals=[restart]。成功组也紧贴预算：普通 792–999ms，cutover 854–1029ms，后者包含设备调度延迟。

旧路径 quality.0 的第 5 个样本（samples[4]）：bind 32ms 返回；581ms 发起原始截图，612ms 返回 null；renderer gate 已完成，612ms 再截、633ms 仍 null；额外等 100ms 后于 734ms 下发，1117ms 才返回 81259 字节。另一样本 bind 57ms，647→685ms null，685→697ms null，798→1059ms 成功。因此“再等 100ms 能截到”包含随后数百毫秒的截图/编码耗时，不能推导为 bind 后 100ms 即可取得编码图片。第四轮 562–730ms 的首次成功窗口也不能代替第五轮调用到编码返回的总预算。

定性：旧实现已重试实际截图，但其从 screenshot 调用开始的 1 秒预算同时覆盖等待 rendered、内核初始化/锁、截图与编码；bind 后立即调用约在 9–92ms，较旧路径更早开始计时，剩余预算不足。cutover 外层另有同样 1 秒截断。失败与预算耗尽吻合，不能宣称首帧信号后已经截图就绪。

- a：排除 Dart 层缓存同一个失败 Future。循环每次调用 `_kernel.screenshot()`，MovaMpvKernel 每次透传 player.screenshot；锁定 media_kit 1.2.6 的 NativePlayer 每次通过 lock.synchronized 执行 function、compute(_screenshot)，没有截图结果缓存。
- b：25ms 间隔并不长；计时也没有在 bind 返回前启动。问题是总预算从紧接 bind 的新入口开始，未留足信号等待和成功图片返回的共同耗时。
- c：旧代码并非首帧信号一到就成功退出，null 后确实重试；但 rendered 是下发截图的必要门槛，额外消耗预算且不是可读 fence。本次直接移除门槛。
- d：代码在 `_kernelOpening != 0` 时确会立即返回 null，但第五轮授权失败均等待约 1 秒，不支持这一机制是该批失败主因；bind/open 代际保护仍保留。
- e：旧代码只有非空字节才返回图片，null/空字节不会当成功；夹具还实际解码图片。本批不存在“空结果被认成功”的证据。

原始 CHECK 没有记录新入口内部每次底层截图的起止，不能进一步断言每个 null 是哪条 mpv 命令或 GPU 阶段造成；本次修正针对已经证实的总预算及门控问题，不冒充原生根因的逐命令追踪。

### 产品修正与回归

普通引擎在有效源/代际内立即调用内核截图，以非空图片为唯一成功判据；空结果按 50、100、150、200、250ms，之后保持 250ms 的间隔重新下发截图。总计 2 秒包含所有等待与截图/编码，超时仍明确返回 null；挂起命令不会并发重发，迟到结果丢弃，完成后无后台重试。异常仍明确返回 null。播放态保留单次尝试，不播放、不 seek、不新增 MovaApi 成员。cutover 外层上限同步为 2 秒，保持 active/epoch/销毁检查。

假内核新增 12 条测试，普通/cutover 各 6 条：首帧已到但前 N 次截图为 null（100、350、700、1050ms 后可读），成功编码另需 350ms；以及首帧迟到 600ms、首帧未通知但 700ms 已可读。直接在原产品实现上运行，新旧合计 30 条中 **8 红、22 绿**，均为行为断言失败，无编译失败。修正后专项 30 条全绿。700ms 与 1050ms 两侧、迟到首帧两侧、未通知首帧两侧合计 8 条由红转绿。原有永久 null/挂起测试同时断言 1999ms 尚未完成、2000ms 返回 null；保留空字节恢复、切源、销毁、播放、异常及 cutover 提交边界测试。

### 新 APK 复验要求

重新构建包含本修正的 APK，同时开启 `CP3_HEADERS_READY=true` 与 `CP3_HEADERS_R4=true`。夹具代码和验收判据不变：普通与 cutover 分别完整授权 30 次，null=0/30、实际解码成功=30/30且保持暂停；各自拒绝对照 30 次解码成功=0/30且 HTTP403。仍从 bind 返回立即调用，不加夹具 sleep 或外层重试。保留原始路径、renderer gate、额外 100ms 对照及所有失败记录。分析 captureWaitMs 分布是否越过原 1 秒但在新 2 秒内成功；设备调度延迟单列，不能放宽产品单测的 2 秒总上限。若仍 null，下一步需逐次底层调用时序证据，不能将本次离线全绿当成真机验收通过。


本次最终离线验证：

- `flutter analyze --no-pub lib test`：No issues found，0 issues。
- `flutter test --no-pub --concurrency=3 --reporter expanded`：仅运行一次全量，2448 项全绿（2436 + 12），用时 2:07。
- `git diff --check` 通过。未修改夹具、CLAUDE.md 或 MovaApi；未运行真机、adb、Gradle，未构建 APK。
