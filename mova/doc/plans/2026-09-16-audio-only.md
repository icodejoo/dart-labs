# mova 0.4.x：仅音频模式（`audioOnly`）— 实现计划

**Goal:** 让 `MovaKernel` / `MovaEngine` / `createMovaEngine()` 能以 `audioOnly: true` 构造。此时**不建视频管线**（不 `VideoController(_player)`、不注册 Flutter Texture、不落地隐藏抽帧 player），`renderHandle` 为 `null`，UI 层不崩且能渲染占位或宿主自定义 `surface`。默认 `false`，关闭时行为与今天逐字节相同。

**Architecture:** 本计划**不新增任何类、不新增任何配置节、不新增任何文件到 `lib/`**。它的全部内容是：放宽一处返回类型的可空性、给两个构造函数各加一个 `bool` 参数、把它透传一层，外加文档与测试。依据见 `doc/notes/2026-09-16-audio-only-feasibility.md` §2.1 的决定性发现——media_kit 的 `Player()` 默认就是 `--vid=no`，是 `MpvKernel` 构造里那一句无条件的 `VideoController(_player)` 把视频管线打开的。**不建那个对象，libmpv 就已经是纯音频播放器。**

**为什么不加 `MovaAudioConfig`：** 笔记 §2.3 提了"加一个 `MovaAudioConfig` 或直接在 `createMovaEngine()` 上加 `audioOnly` 参数都顺理成章"。结论取后者。`MovaOpts` 的语义是**运行期可 `copyWith` 替换的配置**（12 节全部如此），而 `audioOnly` 是**引擎构造期一次性的资源决策**：`MpvKernel` 的 `VideoController` 是 `late final`、构造期绑死，`copyWith` 一个 `audioOnly: true` 进来无法生效，放进 `MovaOpts` 等于造一个骗人的口子。Task 4 为此留了一条对账测试（`MovaOpts` 的配置节数量必须仍是 12）。

**为什么不加 `MovaStreamType.audio`：** 同笔记 §4 第 3 条的倾向——"音频"是引擎的资源形态，不是源的流类型。同一条 `audioOnly` 引擎可以既放 vod 音频也放 live 音频；同一条纯音频 URL 也完全可以在普通引擎上播（只是白背视频管线）。两者正交，混进 `MovaSource` 会造出 2×2 的无意义组合。

**Tech Stack:** Dart 3.12.2 / Flutter ≥3.3、media_kit ^1.2.6、flutter_test。**本阶段不新增任何依赖。**

**Baseline:** 0.4.0（`MovaSwapEngine` 已落地），**535 项测试全绿**、`flutter analyze` 0 issues。
> 校准说明：笔记与 `doc/plans/2026-09-16-seamless-swap.md` 里的 "289" 是 0.3.0 的旧基线，seamless-swap 计划本身把它推到了 374，而后续改动又继续增长。**本计划以 2026-09-16 实跑的 535 为准。**

**范围排除（明确不做）：**
- **不做 `MovaAudioSkin`**（笔记 §2.4 第二档，6–8 Task）。音频场景的封面/歌词/波形面通过 `MovaPlayer` 已有的 `surface` 参数（`lib/src/ui/player.dart:73`）传入即可，UI 侧一行结构改动都不用。
- **不做完整音频模式的后台/锁屏集成**（第三档，≥15 Task 且大头是四端新原生代码）。笔记 §3.4 已定结论：那一块交给 `just_audio` + `audio_service`，mova 只在文档里写清分流判据。
- **不换 `media_kit_libs_*_audio`**（笔记 §2.3 末条）：编译期二选一，换了 mova 的视频功能会物理失效，与"既要视频又要音频"的目标用户直接冲突。

## Global Constraints

- 包名 `mova`，公开类前缀 `Mova`；`src/` 内文件名不带前缀。
- **`lib/src/core/**` 禁止 `import 'package:flutter/...'`；`test/core/purity_test.dart` 的 `_mediaKitExceptions` 必须恒等于 `{'kernel/mpv_kernel.dart'}`，本阶段任何 Task 都不许改它。** 本计划天然满足：唯一碰 media_kit 的改动就落在 `mpv_kernel.dart` 里。
- 注释规则（`CLAUDE.md`）：每个类/方法/getter/字段都要注释，**先英文一句、空行、后中文**；公开 API 用 `///`，带参数/返回/示例。本计划代码块里的注释按原样抄。
- 校验用 `flutter analyze`（0 issues），不用 `flutter build`。每个 Task 结束 `flutter test` 全绿再 commit，信息用 `type(mova): message`。
- **既有 535 项测试一项都不许删、不许改断言。** 只允许因新增可选参数/放宽可空性而做纯增量修改（Task 1 一处：`test/support/fake_kernel.dart`）。
- **默认关闭是硬约束**：`audioOnly` 默认 `false`；为 `false` 时 `MpvKernel`/`MovaEngine`/`createMovaEngine()` 的行为必须与今天逐字节相同。每个 Task 都要有一条"关闭时行为不变"的测试。
- **不新增公开类**：本计划结束后 `lib/mova.dart` barrel **一行不变**。`MovaKernel`/`MpvKernel` 保持不导出（`MpvKernel` 的构造参数 `Player? player` 会把 media_kit 类型泄进公开 API，这是它一直不导出的原因；`audioOnly` 参数就是留给宿主的那扇门）。

## 现状核实（2026-09-16 重新对行号）

笔记写于同一天，但 `MovaSwapEngine` 刚落地，行号有漂移。**逐条核实结果：**

| 笔记中的定位 | 笔记给的行号 | 实际行号 | 结论 |
|---|---|---|---|
| `MovaKernel.renderHandle`（非空） | `kernel.dart:148` | `kernel.dart:148` | ✅ 准确 |
| `MpvKernel` 构造里的 `VideoController(_player)` | `mpv_kernel.dart:29-30` | `mpv_kernel.dart:29-30` | ✅ 准确 |
| `MpvKernel.renderHandle` | `mpv_kernel.dart:152` | `mpv_kernel.dart:152` | ✅ 准确 |
| `MpvKernel.screenshot()` | `mpv_kernel.dart:117` | `mpv_kernel.dart:117` | ✅ 准确 |
| `MovaApi.renderHandle`（已可空） | `api.dart:71` | `api.dart:71` | ✅ 准确 |
| `MovaEngine.renderHandle` | `engine.dart:74` | `engine.dart:74` | ✅ 准确 |
| `MovaSwapEngine.renderHandle` | `swap_engine.dart:161` | `swap_engine.dart:161` | ✅ 准确 |
| `createMovaEngine()` | `wiring.dart:99` | `wiring.dart:99`（签名起始行） | ✅ 准确 |
| `MovaPlayer.surface` 参数 | `player.dart:73` | `player.dart:73` | ✅ 准确 |
| `_RenderSurface` | `player.dart:191-198` | `player.dart:170-206`（判定三元在 191-198） | ✅ 准确 |
| `MovaOpts` 配置节 | `options.dart:39-98`（10 节） | `options.dart` 现为 **12 节**（多了 `swap`；`ads`/`swap`） | ⚠️ **已过时** |
| 测试替身 `Object? renderHandle` | `fake_api.dart:182` | `fake_api.dart:184` | ⚠️ 偏移 2 行 |
| 测试基线 | "289 可能不准" | **535** | ⚠️ **已过时** |

**笔记漏掉的一项（本计划新增处理）：** `createMovaEngine()` 在 `wiring.dart:122` 无条件传 `extractor ?? MpvFrameExtractor()`。`MpvFrameExtractor` 内部会在首次 `extract()` 时建**第二个** `Player()` **并且 `VideoController(player)`**（`mpv_extractor_impl.dart:93-94`）——这是一条完整的第二路视频管线。它是惰性的，只有拖动预览真正触发抽帧兜底才会落地，但在 `audioOnly` 引擎上它 100% 是无意义开销（音频没有帧）。**Task 3 把它一并关掉**，否则"不建视频管线"这句话在 `createMovaEngine()` 这条路上是半真的。

## 文件结构

**新建：无。**

**修改**

| 文件 | 改动 | 任务 |
|---|---|---|
| `lib/src/core/kernel/kernel.dart` | `Object get renderHandle` → `Object? get renderHandle`（第 148 行）+ 文档补 null 语义 | Task 1 |
| `lib/src/core/kernel/mpv_kernel.dart` | 加 `audioOnly` 构造参数；`_controller` 改可空、`audioOnly` 时不建；`renderHandle`/`screenshot()` 在 `audioOnly` 下返回 `null` | Task 2 |
| `lib/src/core/engine.dart` | 加 `bool audioOnly = false` 构造参数（只影响默认 kernel 的构造）；存 `_extractor` 并加 `debugExtractor` getter | Task 3 |
| `lib/src/platform_impl/wiring.dart` | `createMovaEngine({bool audioOnly = false})` 透传；`audioOnly` 时默认抽帧器为 `null` | Task 3 |
| `test/support/fake_kernel.dart` | `renderHandle` 改为可注入的稳定字段；加 `FakeKernel.audioOnly()` 具名构造 | Task 1/2 |
| `README.md` / `CHANGELOG.md` / `doc/SPEC.md` / `CLAUDE.md` | 文档 + 分流判据 | Task 4 |

**测试**

`test/core/kernel_contract_test.dart`（增补）、`test/core/audio_only_test.dart`（新建）、`test/platform_impl/wiring_test.dart`（增补）、`test/core/engine_test.dart`（增补）、`test/ui/player_test.dart`（增补）、`test/core/swap/swap_engine_test.dart`（增补）、`test/ui/skin_test.dart`（增补）、`test/core/openness_audio_test.dart`（新建）。

**测试数量推进**（基线 **535**）：Task 1 → 539、Task 2 → 544、Task 3 → 550、Task 4 → 559、Task 5 → 559（真机，无单测）。

---

## Task 1: `MovaKernel.renderHandle` 放宽为 `Object?`

整条链路上唯一的**非空**声明就在这里；它的唯一调用者 `MovaEngine.renderHandle`（`engine.dart:74`）早就是 `Object?` 了，UI 侧 `MovaApi.renderHandle`（`api.dart:71`）也是。所以这一行是纯粹的"契约补齐"，先单独做掉，让后面每个 Task 都站在一个已经允许 null 的契约上。

**Files:**
- Modify: `lib/src/core/kernel/kernel.dart`, `test/support/fake_kernel.dart`
- Test: `test/core/kernel_contract_test.dart`（追加 4 项，既有 2 项一条不改）

**Produces:**

```dart
  /// The underlying render handle to be attached to a video widget (e.g. a
  /// `VideoController`). Its concrete type is engine-specific and opaque to
  /// callers outside the core layer.
  ///
  /// `null` means this kernel has no video pipeline at all — the audio-only
  /// case, where no `VideoController` was ever created and no Flutter texture
  /// was ever registered. It is *not* an error state and must not be treated
  /// as one: `MovaPlayer` already renders a placeholder (or the host's own
  /// `surface`) for any handle that is not a `VideoController`.
  ///
  /// 供视频渲染组件使用的底层渲染句柄（如 `VideoController`）。
  /// 其具体类型由引擎决定，对核心层之外的调用者不透明。
  ///
  /// `null` 表示该内核**根本没有视频管线**——即仅音频场景：从未创建过
  /// `VideoController`，也从未注册过 Flutter 纹理。它**不是**错误状态，也不得
  /// 被当作错误处理：对任何非 `VideoController` 的句柄，`MovaPlayer` 本来就会
  /// 渲染占位符（或宿主自己传入的 `surface`）。
  Object? get renderHandle;
```

`test/support/fake_kernel.dart` 的配套改动（把今天每次调用都新建一个 `Object()` 的 `renderHandle` 换成可注入的稳定字段——既有测试没断言过它，这是纯增量）：

```dart
  /// Creates a fake kernel.
  ///
  /// 创建一个假内核。
  ///
  /// - [renderHandle]: the handle this fake reports; defaults to a fresh
  ///   opaque object, pass `null` to emulate an audio-only kernel /
  ///   该假对象对外报告的句柄；默认是一个新建的不透明对象，传 `null` 可模拟
  ///   仅音频内核
  ///
  /// Example / 示例:
  /// ```dart
  /// final k = FakeKernel(renderHandle: null); // audio-only / 仅音频
  /// ```
  FakeKernel({Object? renderHandle}) : _renderHandle = renderHandle;

  /// The stable handle this fake reports; stable identity matters because
  /// `_RenderSurface` keys itself by handle identity.
  ///
  /// 该假对象报告的稳定句柄；身份稳定很重要，因为 `_RenderSurface` 正是按句柄
  /// 身份做 key。
  final Object? _renderHandle;

  @override
  Object? get renderHandle => _renderHandle;
```

> ⚠️ 注意：`FakeKernel({Object? renderHandle})` 无法区分"没传"与"显式传 null"。**故意如此**——本计划里"没传"和"要 null"要分开，所以默认值改为一个**在字段声明处**生成的稳定对象，而 `audioOnly` 那条路走 Task 2 的具名构造 `FakeKernel.audioOnly()`，不靠这个可选参数表达。实现时按下面两条落地：
> - `FakeKernel({Object? renderHandle}) : _renderHandle = renderHandle ?? Object();`
> - `FakeKernel.audioOnly() : _renderHandle = null, _audioOnly = true;`（`_audioOnly` 在 Task 2 引入）

**Steps:**
1. 先写失败测试（见下），确认 `FakeKernel(renderHandle: null)` 今天连编译都过不了（`Object` 不接受 `null`）。
2. 改 `kernel.dart:148` 的返回类型与文档注释。
3. 改 `fake_kernel.dart` 的 `renderHandle` 为稳定字段 + 可注入构造参数。
4. `flutter analyze` 确认无连带破坏——重点看 `MpvKernel`（返回 `Object` 仍满足 `Object?`，不是破坏性改动）与 `MovaEngine.renderHandle`（本就可空）。
5. `flutter test`。

**单测要求（`test/core/kernel_contract_test.dart` 追加 4 项）：**
1. `FakeKernel().renderHandle` 非 null，且**两次读取返回同一实例**（`identical(k.renderHandle, k.renderHandle)` 为 true）——这是对今天 `=> Object()` 每次新建的一次顺手修正，并锁住"句柄身份稳定"这条 `_RenderSurface` 依赖的性质。
2. `FakeKernel(renderHandle: null).renderHandle` 为 `null`，且构造不抛。
3. `MovaEngine(kernel: FakeKernel(renderHandle: null)).renderHandle` 为 `null`，且**引擎构造全程不抛**（证明 `engine.dart` 的 8 条 `late final` 接线不依赖非空句柄）。
4. **关闭态回归护栏**：`MovaEngine(kernel: FakeKernel())` 的 `renderHandle` 与注入 kernel 的 `renderHandle` `identical`（原样透传，未被包装/替换）。

**验收标准：** 539 项全绿；`flutter analyze` 0 issues；`git diff lib/` 只有 `kernel.dart` 一个文件、且只有一处类型变更 + 注释；`test/core/purity_test.dart` 未改。

---

## Task 2: `MpvKernel({bool audioOnly = false})` — 不建视频管线

本计划的核心。改动只有三处：不建 `VideoController`、`renderHandle` 返回 `null`、`screenshot()` 返回 `null`。

**Files:**
- Modify: `lib/src/core/kernel/mpv_kernel.dart`, `test/support/fake_kernel.dart`
- Test: `test/core/audio_only_test.dart`（新建，5 项）

**Produces:**

```dart
  /// Creates the media_kit-backed kernel.
  ///
  /// [player] lets callers inject an existing `Player` (e.g. for testing or
  /// custom configuration); when omitted a new `Player()` is created.
  ///
  /// [audioOnly] skips creating the `VideoController` entirely. media_kit's
  /// `Player` already starts with mpv's `--vid=no` and it is *only*
  /// `VideoController.create()` that flips it back to `vid=auto`
  /// (media_kit 1.2.6, `player/native/player/real.dart` `_create()` and
  /// `video_controller/native_video_controller/real.dart`), so not attaching
  /// one leaves libmpv decoding audio and nothing else: no decoded frame
  /// buffers, no GPU texture, no Flutter `Texture` registration. Those three
  /// are the whole of the video-side memory cost, and in audio-only mode they
  /// are zero rather than merely smaller.
  ///
  /// 创建基于 media_kit 的内核。
  ///
  /// [player] 允许调用者注入一个已存在的 `Player`（如用于测试或自定义配置）；
  /// 省略时会创建一个新的 `Player()`。
  ///
  /// [audioOnly] 表示完全跳过 `VideoController` 的创建。media_kit 的 `Player`
  /// 一创建就是 mpv 的 `--vid=no`，**只有** `VideoController.create()` 会把它
  /// 改回 `vid=auto`（media_kit 1.2.6，见 `player/native/player/real.dart` 的
  /// `_create()` 与 `video_controller/native_video_controller/real.dart`），
  /// 因此不挂接它就等于让 libmpv 只解音频：没有解码帧缓冲、没有 GPU 纹理、
  /// 没有 Flutter `Texture` 注册。这三项就是视频侧内存开销的全部，在仅音频
  /// 模式下它们是 0，而不只是变小。
  MpvKernel({Player? player, this.audioOnly = false}) : _player = player ?? Player() {
    if (!audioOnly) {
      _controller = VideoController(_player);
    }
    _widthSub = _player.stream.width.listen((w) { /* 不变 / unchanged */ });
    _heightSub = _player.stream.height.listen((h) { /* 不变 / unchanged */ });
  }

  /// Whether this kernel was built without a video pipeline.
  ///
  /// 该内核是否在不带视频管线的形态下构造。
  final bool audioOnly;

  /// The video controller used to attach this kernel to a video widget;
  /// `null` when [audioOnly].
  ///
  /// 用于把该内核挂接到视频组件上的控制器；[audioOnly] 时为 `null`。
  VideoController? _controller;

  /// Captures the current video frame as an encoded image, or `null` when
  /// there is no video pipeline to capture from.
  ///
  /// Short-circuiting here rather than letting mpv fail keeps the scrub-preview
  /// frame-extraction fallback (`MovaPrevSource`) on its documented
  /// "extractor returned nothing → degrade gracefully" path instead of
  /// surfacing an mpv error to the host.
  ///
  /// 截取当前视频帧并编码为图片；没有视频管线可截时返回 `null`。
  ///
  /// 在此短路而不是让 mpv 自己失败，可以让拖动预览的抽帧兜底
  /// （`MovaPrevSource`）走它既有的"抽帧器没给结果 → 平滑降级"路径，而不是把
  /// 一个 mpv 错误抛给宿主。
  @override
  Future<Uint8List?> screenshot() async =>
      audioOnly ? null : _player.screenshot(format: 'image/jpeg');

  @override
  Object? get renderHandle => _controller;
```

配套的 `FakeKernel` 具名构造（供 Task 2/3/4 复用；`MpvKernel` 本身需要 libmpv 原生库，无法在 `flutter test` 里构造，见下方"可测性说明"）：

```dart
  /// Creates a fake kernel emulating an audio-only one: no render handle and
  /// no screenshot, every other verb unchanged.
  ///
  /// 创建一个模拟仅音频形态的假内核：无渲染句柄、不支持截图，其余动词行为不变。
  ///
  /// Example / 示例:
  /// ```dart
  /// final engine = MovaEngine(kernel: FakeKernel.audioOnly());
  /// expect(engine.renderHandle, isNull);
  /// ```
  FakeKernel.audioOnly()
      : _renderHandle = null,
        _audioOnly = true;
```

**可测性说明（写进本文档，不是遗漏）：** `MpvKernel` 的构造函数在 `player == null` 时会 `Player()`，需要真实 libmpv 动态库，`flutter test`（纯 Dart VM host）跑不起来；注入 `Player` 同样要原生库。所以**本仓库从来没有、本计划也不新增 `MpvKernel` 的直接单测**（`kernel_contract_test.dart` 测的一直是 `FakeKernel`）。本 Task 的验证因此分两层：
- **契约层**用 `FakeKernel.audioOnly()` 断言"音频内核长什么样"，后续 Task 3/4 全部站在它上面；
- **结构层**加两条源级守卫测试，照 `test/core/purity_test.dart` 的既有先例（那也是读源文件做断言），钉死"`VideoController` 不得再被无条件构造"这一条本计划的立身之本。

源级守卫是次优解，但明确优于没有：它挡得住"某次重构把 `if (!audioOnly)` 顺手删掉"这一类回归，而真正的端到端确认交给 Task 5 的真机 checklist（那里会直接查 mpv 的 `vid` 属性与 `dumpsys meminfo`）。

**Steps:**
1. 先写 `test/core/audio_only_test.dart` 的 5 项，确认第 4/5 项在改动前失败。
2. `_controller` 由 `late final VideoController` 改为 `VideoController?`，构造里加 `if (!audioOnly)` 包裹。
3. `renderHandle` 返回类型随 Task 1 放宽后的契约改为 `Object?`，实现改为 `=> _controller`。
4. `screenshot()` 加 `audioOnly` 短路。
5. `dispose()` **不需要改**：今天就不释放 `_controller`（`VideoController` 的生命周期随 `Player.dispose()`），`null` 时同样无事可做——确认一遍即可。
6. `flutter analyze` + `flutter test`。

**单测要求（`test/core/audio_only_test.dart`，新建 5 项）：**
1. `FakeKernel.audioOnly().renderHandle` 为 `null`。
2. `FakeKernel.audioOnly().screenshot()` 解析为 `null`。
3. `FakeKernel.audioOnly()` 的**全部非视频动词仍然可用**：依次 `open`/`play`/`pause`/`seek`/`setVolume`/`setRate`，断言 `calls` 顺序完整、`lastUri`/`lastSeek` 正确——证明"关掉视频"没有顺手关掉播放能力。
4. **结构守卫**：读 `lib/src/core/kernel/mpv_kernel.dart` 源码，断言 `'VideoController('` 出现次数恰为 1，且该行**处于 `if (!audioOnly)` 块内**（断言紧邻的前一行非空代码行匹配 `RegExp(r'if\s*\(!audioOnly\)')`）。失败原因写进 `reason`：说明这一行就是笔记 §2.1 认定的"打开全部视频侧开销的那一句"。
5. **结构守卫**：断言 `mpv_kernel.dart` 的 `screenshot()` 实现里含 `audioOnly ?` 短路，且 `renderHandle` 的声明是 `Object? get renderHandle`。

**验收标准：** 544 项全绿；`flutter analyze` 0 issues；`test/core/purity_test.dart` 仍以 `{'kernel/mpv_kernel.dart'}` 为唯一 media_kit 例外（未改）；`git diff` 中 `mpv_kernel.dart` 的改动不超过"构造参数 + 一个 `if` + 两处返回值 + 注释"。

---

## Task 3: `MovaEngine` / `createMovaEngine()` 透传 `audioOnly`

两层透传，外加笔记漏掉的那件事：`createMovaEngine()` 在 `audioOnly` 下不再默认注入 `MpvFrameExtractor`。

**Files:**
- Modify: `lib/src/core/engine.dart`, `lib/src/platform_impl/wiring.dart`
- Test: `test/platform_impl/wiring_test.dart`（追加 4 项）、`test/core/engine_test.dart`（追加 2 项）

**Produces（`engine.dart`）：**

```dart
  /// [audioOnly] is forwarded to the default [MpvKernel] so no video pipeline
  /// is built; it has no effect when [kernel] is supplied, since an injected
  /// kernel is used exactly as given. There is deliberately no
  /// `MovaState.audioOnly` and no `MovaOpts` section for it: this is a
  /// construction-time resource decision (the kernel's render handle is bound
  /// once and never re-bound), and the observable runtime signal is simply
  /// `renderHandle == null`.
  ///
  /// [audioOnly] 会透传给默认构造的 [MpvKernel]，使其不建立视频管线；当显式
  /// 传入 [kernel] 时它不起作用——注入的内核一律原样使用。这里刻意不提供
  /// `MovaState.audioOnly`，也不为它新增 `MovaOpts` 配置节：这是构造期的资源
  /// 决策（内核的渲染句柄一次绑定、永不重绑），而运行期可观测的信号就是
  /// `renderHandle == null` 本身。
  MovaEngine({
    MovaKernel? kernel,
    bool audioOnly = false,
    this.options = const MovaOpts(),
    // …其余参数不变 / the rest unchanged
  })  : _kernel = kernel ?? MpvKernel(audioOnly: audioOnly),
        _extractor = extractor,
        // …其余初始化不变 / the rest unchanged
```

```dart
  /// The frame extractor this engine was constructed with (`null` = no
  /// frame-extraction fallback); see [debugBrightnessPort] for why this is
  /// exposed only for tests.
  ///
  /// 该 engine 构造时使用的抽帧器（`null` 表示没有抽帧兜底）；为何只对测试暴露
  /// 见 [debugBrightnessPort]。
  @visibleForTesting
  MovaFramePuller? get debugExtractor => _extractor;
```

**Produces（`wiring.dart`）：**

```dart
/// - [audioOnly]: builds an audio-only engine — the default kernel skips its
///   `VideoController` and the frame-extraction fallback is left unwired,
///   so no video pipeline of any kind is created. `renderHandle` is then
///   `null` and `MovaPlayer` renders its placeholder (or the `surface` you
///   pass it). Ignored when [kernel] is supplied. Hosts should also turn
///   scrub preview off (`MovaPrevConfig(enabled: false)`) — there are no
///   frames to preview /
///   构建仅音频引擎——默认内核跳过 `VideoController`，抽帧兜底也不接线，
///   因此不会创建任何形式的视频管线。此时 `renderHandle` 为 `null`，
///   `MovaPlayer` 渲染占位符（或你传入的 `surface`）。传入 [kernel] 时本参数
///   被忽略。宿主还应关掉拖动预览（`MovaPrevConfig(enabled: false)`）——
///   没有帧可预览
MovaEngine createMovaEngine({
  MovaKernel? kernel,
  bool audioOnly = false,
  MovaOpts options = const MovaOpts(),
  // …其余参数不变 / the rest unchanged
}) {
  return MovaEngine(
    kernel: kernel,
    audioOnly: audioOnly,
    // …
    // An audio-only engine has no frames, and MpvFrameExtractor would open a
    // *second* Player with its own VideoController on first use — a whole
    // extra video pipeline, exactly what audioOnly exists to avoid. Leave it
    // unwired unless the host insists.
    //
    // 仅音频引擎没有帧可抽，而 MpvFrameExtractor 在首次使用时会新开**第二个**
    // Player 并为其建 VideoController——那是一整条额外的视频管线，恰恰是
    // audioOnly 要避免的东西。除非宿主显式指定，否则不接线。
    extractor: extractor ?? (audioOnly ? null : MpvFrameExtractor()),
    // …
  );
}
```

**Steps:**
1. `engine.dart`：加 `bool audioOnly = false` 参数（放在 `kernel` 之后、`options` 之前）、初始化列表改 `MpvKernel(audioOnly: audioOnly)`、新增 `final MovaFramePuller? _extractor` 字段与 `debugExtractor` getter（`_buildPreview` 的调用点改为传 `_extractor`，语义不变）。
2. `wiring.dart`：加 `bool audioOnly = false` 参数并透传；`extractor` 默认值改为条件表达式。
3. 补文档注释（两处 `///`，双语，带参数说明）。
4. `flutter analyze` + `flutter test`。

**单测要求：**

`test/platform_impl/wiring_test.dart` 追加 4 项（复用既有的 `_FakePathProviderPlatform`）：
1. `createMovaEngine(kernel: FakeKernel(), audioOnly: true).debugExtractor` 为 `null`。
2. **关闭态回归护栏**：`createMovaEngine(kernel: FakeKernel()).debugExtractor` 是 `MpvFrameExtractor`（默认不变）。
3. 显式注入的 `extractor` 在 `audioOnly: true` 时**仍然胜出**（宿主想自己接就能接，不被替用户做决定）。
4. `audioOnly: true` 不影响其他端口：`debugBrightnessPort`/`debugPipPort`/`debugOrientationPort` 仍分别是 `ScreenBrightnessPort`/`ChannelPipPort`/`SystemChromeOrientationPort`。

`test/core/engine_test.dart` 追加 2 项：
5. `MovaEngine(kernel: FakeKernel.audioOnly(), audioOnly: true)` 用的是**注入的那个 kernel**（`renderHandle` 为 `null`、未尝试新建 `MpvKernel`——若新建会因缺原生库直接抛，测试能跑过本身即是证明），且 `open`/`play`/`seek` 等动词照常转发到该 kernel。
6. **关闭态回归护栏**：`MovaEngine(kernel: FakeKernel())` 的构造签名变化不影响任何既有行为——`renderHandle` 非 null 且 `identical` 于 kernel 的句柄，`debugExtractor` 为 `null`（裸构造函数的既有默认）。

**验收标准：** 550 项全绿；既有 `wiring_test.dart` 3 项、`engine_test.dart` 全部断言一条未改；`flutter analyze` 0 issues；`lib/mova.dart` 未改。

---

## Task 4: UI 兼容确认、`MovaSwapEngine` 兼容、开放性对账与文档

`_RenderSurface`（`player.dart:170-206`）**结构一行不改**——`null` 天然落进 `handle is VideoController` 的 else 分支，拿到那个本来给 widget 测试留的黑色占位。本 Task 的任务是**把这条"天然兼容"变成有测试护栏的承诺**，并把笔记 §3.4 的分流判据写进文档。

**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `doc/SPEC.md`, `CLAUDE.md`
- Test: `test/ui/player_test.dart`（追加 3 项）、`test/core/swap/swap_engine_test.dart`（追加 2 项）、`test/ui/skin_test.dart`（追加 1 项）、`test/core/openness_audio_test.dart`（新建 3 项）

**`lib/` 下零改动。** 这是本 Task 的验收标准之一：如果写测试时发现 UI 层需要改结构，说明笔记 §2.2 的判断有误，必须先停下来回写笔记再继续。

**Steps:**
1. 写 UI 测试（复用 `player_test.dart` 顶部已有的 `_surfaceKey(WidgetTester)` 辅助，它按 `w.key.runtimeType.toString() == '_RenderHandleKey'` 找占位/视频组件的 key）。
2. 写 `MovaSwapEngine` 兼容测试（工厂返回 `renderHandle` 为 null 的 `FakeMovaApi`）。
3. 写开放性对账测试。
4. 写文档（见下）。
5. `flutter analyze` + `flutter test`。

**单测要求：**

`test/ui/player_test.dart` 追加 3 项（`FakeMovaApi` 的 `renderHandle` 默认就是 `null`，正是音频形态）：
1. `renderHandle` 为 `null` 时 `MovaPlayer` 正常挂载、**不抛**，且 `(_surfaceKey(t) as ValueKey<Object?>).value` 为 `null`——即占位分支确实被走到、且 key 里确实是那个 null 句柄。
2. `renderHandle` 为 `null` **且**传入自定义 `surface`（一个带 `ValueKey('cover')` 的封面组件）时：找得到 `cover`，且 `_surfaceKey(t)` 为 `null`（`_RenderSurface` 根本没被构造）——证明笔记 §2.2 末段"音频场景直接复用 `surface` 这个口子传封面/波形/歌词面"确实成立，无需 `MovaAudioSkin`。
3. **反向路径**：`renderHandle` 由 `null` 改为 `'video-handle'` 并推 `renderEpoch + 1` 后，渲染面重建且读到新句柄（`_surfaceKey` 的 value 变为 `'video-handle'`）——覆盖"同一棵树上从音频引擎换成视频引擎"这条 `MovaSwapEngine` 打开的可能性。

`test/core/swap/swap_engine_test.dart` 追加 2 项：
4. 工厂产出的引擎 `renderHandle` 为 `null` 时，`MovaSwapEngine.renderHandle` 为 `null` 且构造/转发全程不抛（`swap_engine.dart:161` 的 `=> _active.renderHandle` 已可空，本项是回归护栏）。
5. 两个 audio-only 引擎之间 `commit()` 成功后：`renderHandle` 仍为 `null`，但 `renderEpoch` **仍然递增 1**（切换簿记不因没有渲染句柄而被跳过）。

`test/ui/skin_test.dart` 追加 1 项：
6. `renderHandle` 为 `null` 时默认皮肤仍完整装配：控制条、手势层、中央播放键都在树上——证明"没有视频句柄"不会让皮肤退化。

`test/core/openness_audio_test.dart` 新建 3 项（照 `openness_live_test.dart`/`openness_swap_test.dart` 的形式，把"每个替用户做的决策都齐默认值 + 配置项 + 可注入策略"做成可执行测试）：

| 决策 | 默认值 | 配置项 | 可注入 |
|---|---|---|---|
| 是否建视频管线 | 建（`audioOnly: false`） | `createMovaEngine(audioOnly:)` / `MovaEngine(audioOnly:)` | 宿主可直接注入自己的 `MovaKernel` |
| 是否接抽帧兜底 | `audioOnly` 时不接，否则接 | 同上（联动） | `extractor:` 显式注入胜出 |
| 音频下画面渲染什么 | 黑色占位 | — | `MovaPlayer.surface` 任意组件 |

7. 默认值：`createMovaEngine(kernel: FakeKernel())` 的 `debugExtractor` 非 null（即 `audioOnly` 默认 false，行为不变）。
8. 配置项：`createMovaEngine(kernel: FakeKernel.audioOnly(), audioOnly: true)` 的 `renderHandle` 为 null 且 `debugExtractor` 为 null。
9. 可注入 + **反对账**：`MovaOpts` 的配置节数量仍为 **12**（`preview/live/gesture/abr/controls/danmaku/stt/playlist/ads/strings/theme/swap`），断言本特性**没有**偷偷加 `MovaAudioConfig`——理由写进 `reason`：`audioOnly` 是构造期资源决策，`MovaOpts.copyWith` 无法让它生效，放进去是骗人的口子。

**文档要求：**

- **`README.md`**：在「无缝引擎切换（可选）」（第 194 行）之后新增一节「仅音频模式（`audioOnly`）」。必须包含：
  - 三行用法示例：`createMovaEngine(audioOnly: true, options: MovaOpts(preview: MovaPrevConfig(enabled: false)))` + `MovaPlayer(api: engine, surface: CoverArt(...))`。
  - 笔记 §1 的开销结论（内存约两个数量级、CPU/电量一个数量级以上），**并原样保留"这是按编解码参数推算的量级、不是本仓库实测"这条诚实标注**，附一句"实测数字见本计划 Task 5 回写的附录 A"。
  - 笔记 §1.4 的反直觉点：**包体积不随模式变**，只要还链 `media_kit_libs_video`，那 ~11.8 MiB/ABI 的 `libmpv.so` 照样在包里。
  - **分流判据（逐字采用笔记 §3.4）**：
    > 需要熄屏后台常驻 + 系统媒体控制吗？
    > 需要 → `just_audio` + `audio_service`。
    > 不需要（只是前台界面里放一段音频） → mova 的 `audioOnly` 模式，别多引一个插件。
  - 明确列出 mova 在音频模式下**没有**的东西：后台常驻、锁屏/通知栏、耳机线控、音频焦点、gapless、歌单。
- **`doc/SPEC.md`**：新增「仅音频模式」一节，写清三条设计决定及其理由——① 为什么不进 `MovaOpts`（构造期决策 vs 运行期配置）；② 为什么不加 `MovaStreamType.audio`（正交概念，会造出 2×2 无意义组合）；③ 为什么不换 `media_kit_libs_*_audio`（编译期二选一，会让视频功能物理失效）。并记录 `MpvFrameExtractor` 那条"第二路视频管线"的处置。
- **`CHANGELOG.md`**：在 0.4.0 条目下增补一条「仅音频模式（`audioOnly`）」，注明默认关闭、`renderHandle` 契约放宽为可空、`MovaAudioSkin` 与后台/锁屏集成**不在本次范围**、真机验证未进行。
- **`CLAUDE.md`**：「当前状态」加一句 `audioOnly`；「剩余任务」加两条——`MovaAudioSkin`（第二档，若将来需要）与 Task 5 真机验证（未完成）。

**验收标准：** 559 项全绿；**`git diff lib/` 为空**（本 Task 不碰 `lib/`，若非空说明 §2.2 的"UI 层零改动"判断需回写笔记）；`flutter analyze` 0 issues；README 中分流判据与笔记 §3.4 逐字一致。

---

## Task 5: 真机验证（Android 优先，iOS 次之）

**这是唯一能把笔记 §1 的推算变成实测数字的机会**，也是本计划里唯一无法靠单测收敛的部分。笔记自己标注了"以上不是本仓库的实测数字"，本 Task 就是去把那个标注撤掉。

测法沿用 feed 引擎池当年的三阶段 `dumpsys meminfo` 对比（`doc/SPEC.md:324` 记录的那次：`example/lib/spike_dual_engine.dart` + 单引擎基线 / 加一个预热引擎 / 释放后回收）。本次的三阶段换成 **视频引擎 / 音频引擎 / 释放后**，对照同一条素材。

### 前置：example 需要一个开关

在 `example/lib/main.dart` 里加一个 `audioOnly` 开关（与 Task 10 的 `seamless` 开关同形），开时用
`createMovaEngine(audioOnly: true, options: opts.copyWith(preview: const MovaPrevConfig(enabled: false)))`，关时沿用今天的 `createMovaEngine(options: opts)`。**两条路径都要能跑** —— 这是真机来回切的那个开关。

> 这一步在 Task 4 里**没有**做（Task 4 严格零 `lib/` 改动，而 example 不属于 `lib/`）。实际执行时在本 Task 开头顺手加，改动限于 `example/`，不影响测试数。

### A. 功能正确性

- [ ] `audioOnly: true` 播一条**纯音频**源（m4a/aac）：能起播、能 seek、能调速、能调音量、进度条正常走。
- [ ] `audioOnly: true` 播一条**带视频轨**的源（mp4）：**只出声不出画**，且不报错、不卡死——这是 `--vid=no` 的正确语义，也是验证"视频轨被跳过而不是被渲染到别处"。
- [ ] 同一条 mp4 在 `audioOnly: false` 下画面正常——确认开关是双向的。
- [ ] `MovaPlayer` 不传 `surface` 时是黑色占位、不崩；传自定义封面组件时渲染封面。
- [ ] 控制条、手势（音量/进度）、时移、ABR、广告逻辑在音频模式下照常工作——这正是笔记 §3.4 里"换插件反而要把这些再实现一遍"的那条理由是否成立的检验。
- [ ] 全屏/PiP/亮度手势在音频下**不崩**（行为无意义可接受，崩溃不可接受）。若发现崩溃，记录具体组件——那是将来 `MovaAudioSkin`（第二档）的输入，**本次不修结构，只记录**。
- [ ] `MovaState.size` 在音频模式下的实际取值（预期恒 0×0）及其对方向推导 `preferredOrientationsFor(0, 0)` 的影响，记录下来。

### B. 内存 —— 验证"差两个数量级"是否属实

对照组必须严格同条件：**同一台机、同一条 1080p H.264 + AAC 素材、同一网络、同一播放时长（稳定播放 60 秒后采样）**。

- [ ] **阶段 ①（视频基线）**：`audioOnly: false` 播 60 秒后 `adb shell dumpsys meminfo <pkg>`，记录 `TOTAL PSS`、`Native Heap`、`Graphics`、`GL mtrack` 四栏。
- [ ] **阶段 ②（音频）**：同一 App 重启后 `audioOnly: true` 播同一条素材 60 秒，同样四栏采样。
- [ ] **阶段 ③（释放后）**：`dispose()` 引擎、等 3 秒、再采样。**必须回落到接近"App 空闲基线"**，否则是引擎泄漏。
- [ ] 把 ①−② 的差值按栏拆开填进下表，并与笔记 §1.1 的预测逐项对账：

  | 栏目 | 笔记 §1.1 预测 | 视频实测 | 音频实测 | 差值 | 是否吻合 |
  |---|---|---|---|---|---|
  | Native Heap | 帧缓冲 30–80 MB | | | | |
  | Graphics / GL mtrack | Flutter 纹理双缓冲 ≈ 16 MB | | | | |
  | TOTAL PSS | 近百 MB vs MB 级 | | | | |

- [ ] **诚实结论**：若实测**不是**两个数量级（很可能——App 自身、Flutter 引擎、libmpv 常驻本身就占掉相当一块 PSS，"两个数量级"说的是**视频链路增量**而非整机 PSS），**必须把笔记 §1 的表述改写为"视频链路增量约 XX MB，占整机 PSS 的 YY%"**，用实测数字替换推算量级。这条是本 Task 的主要产出，不能因为数字不好看就跳过。
- [ ] 连播 10 条音频，阶段 ③ 的采样值不应逐轮爬升（无累积泄漏）。

### C. 验证 `vid` 属性确实是 `no`（核心机制的直接确认）

Task 2 的全部依据是"media_kit 的 `Player` 默认 `--vid=no`，不挂 `VideoController` 就不会被改回 `auto`"。这是对第三方库**默认值**的依赖，一次 media_kit 升级就可能失效，必须直接验一次。

- [ ] 在 example 里临时加一行 `(player.platform as NativePlayer).getProperty('vid')` 的打印（或用 `--log-file` 抓 mpv 日志），确认 `audioOnly: true` 时为 `no`、`audioOnly: false` 时为 `auto`。
- [ ] `audioOnly: true` 时 `adb shell dumpsys media.player` / `dumpsys SurfaceFlinger` 中**不应出现该进程的视频 Surface/MediaCodec 实例**——这是"没建视频管线"的外部证据，比属性打印更硬。
- [ ] 把确认结果与 media_kit 的确切版本号（1.2.6）一起写进 `mpv_kernel.dart` 的注释与 `doc/SPEC.md`，注明"升级 media_kit 时须重验此条"。

### D. 电量 / CPU（量级抽查，不追求精确）

- [ ] `adb shell dumpsys batterystats --reset` 后，两种模式各连播 10 分钟，对比 `batterystats` 的估算耗电与 `top -H` 的进程 CPU 占用。
- [ ] 记录实测倍数，回写笔记 §1.2/§1.3 的"一个数量级以上"表述。若手上没有稳定的电量测量条件，**明确写"未测"而不是沿用推算**。

### E. 回归（开关关闭态）

- [ ] `audioOnly: false` 时逐条走一遍 example 的全部 demo（点播/直播/feed/广告/seamless），确认与本计划实施前行为无差异。
- [ ] 拖动预览在 `audioOnly: false` 下仍走 `MpvFrameExtractor` 兜底（Task 3 改了它的默认注入条件，必须确认没误伤视频路径）。

### F. 结论回写

- [ ] 把 B/C/D 的实测数字写入本文档「附录 A：真机实测结论」。
- [ ] **回写 `doc/notes/2026-09-16-audio-only-feasibility.md` §1**：用实测数字替换推算量级，并删掉或改写 §1.3 末尾那条"⚠️ 诚实标注"（若某项仍未测，标注保留但缩小范围到具体那一项）。
- [ ] 同步 `README.md` 的开销说明与 `doc/SPEC.md`。
- [ ] `CLAUDE.md` 的「剩余任务」里划掉真机验证。

---

**决策与结论摘要：** 本计划共拆 **5 个 Task**（4 个代码/文档 + 1 个真机验证），测试从 **535** 推进到 **559**。核心改动小到可以一句话概括：**`kernel.dart:148` 的 `Object` 改成 `Object?`，`MpvKernel` 构造里的 `VideoController(_player)` 包一个 `if (!audioOnly)`。** 关键取舍：`audioOnly` **不进 `MovaOpts`**（构造期资源决策，`copyWith` 无法生效，放进去是骗人的口子）、**不加 `MovaStreamType.audio`**（与流类型正交）、**不新增任何公开类、barrel 一行不改**；UI 层 `_RenderSurface` **结构零改动**，音频画面通过已有的 `MovaPlayer.surface` 口子传封面/波形/歌词面，`MovaAudioSkin` 留给将来。相对笔记额外补的一件事：`createMovaEngine()` 在 `audioOnly` 下不再默认注入 `MpvFrameExtractor`——它会在首次抽帧时新开**第二个** `Player` 并为其建 `VideoController`，是一整条被笔记漏掉的视频管线。真机 checklist 六组，其中 B 组的三阶段 `dumpsys meminfo` 对账是把笔记 §1 的推算变成实测数字的唯一机会，且**明确要求即使结论与"两个数量级"不符也必须如实回写笔记**。
