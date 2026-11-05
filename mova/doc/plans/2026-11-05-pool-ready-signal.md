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
