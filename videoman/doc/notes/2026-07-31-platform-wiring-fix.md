# 2026-07-31 — 平台适配器接线缺失修复

## 根因（Root cause）

阶段 A 重构把亮度/画中画/方向能力拆成三个可注入端口
（`VmBrightnessPort`/`VmPipPort`/`VmOrientationPort`，定义于
`lib/src/core/platform/ports.dart`），并在 `lib/src/platform_impl/` 下实现了
对应的真实适配器：

- `ScreenBrightnessPort`（`lib/src/platform_impl/brightness_impl.dart`）
- `ChannelPipPort`（`lib/src/platform_impl/pip_impl.dart`）
- `SystemChromeOrientationPort`（`lib/src/platform_impl/orientation_impl.dart`）

但全仓库没有任何地方真正 `new` 过这三个类
（`grep -rn "ScreenBrightnessPort()\|ChannelPipPort()\|SystemChromeOrientationPort()" lib/ example/ test/`
零命中）。`VmEngine` 构造函数（`lib/src/core/engine.dart`）在端口未显式注入时
落到零依赖兜底实现：

```dart
_brightness = brightness ?? FallbackBrightnessPort(),
_pip = pip ?? NoopPipPort(),
_orientation = orientation ?? NoopOrientationPort()
```

而 `example/lib/main.dart` 一直构造裸 `VmEngine()`。净效果：0.1.0 里可用的
三个功能在 0.2.0 里全部失效——

1. 右侧竖向拖拽（亮度手势）：`FallbackBrightnessPort` 恒报 1.0 并丢弃写入，
   屏幕亮度永不变化。
2. `enterPip()`：`NoopPipPort` 恒返回 `false`，Android 上 PiP 按钮无反应。
3. `setFullscreen()`：`NoopOrientationPort` 什么都不做，既不切换设备方向，
   也不进入沉浸式系统 UI。

这违反了阶段 A 自身声明的"功能零变化"验收口径，且因为"漏调用一个构造"在
diff review 里完全不可见，才会被漏检。

## 修改内容（What changed）

1. **新增 `lib/src/platform_impl/wiring.dart`**：导出工厂函数 `createVmEngine(...)`，
   参数与 `VmEngine` 构造函数一一对应（`kernel`/`options`/`interceptors`/
   `brightness`/`pip`/`orientation`），三个端口参数默认使用真实适配器
   （`ScreenBrightnessPort()`/`ChannelPipPort()`/`SystemChromeOrientationPort()`），
   同时仍允许调用方逐个覆盖（例如测试里传入 fake）。`VmEngine` 自身构造函数
   保持完全不变（默认仍是 noop/兜底），因为 `lib/src/core/**` 不允许引入
   `package:flutter/*` 或 `platform_impl/*`（由 `test/core/purity_test.dart`
   强制检查）——所以接线逻辑必须放在 `platform_impl/` 里，而不是塞进
   `VmEngine` 构造函数。

2. **`lib/src/core/engine.dart`**：新增三个 `@visibleForTesting` getter
   （`debugBrightnessPort`/`debugPipPort`/`debugOrientationPort`），仅暴露
   已注入端口的运行时类型供测试断言，不改变任何生产行为。

3. **`lib/videoman.dart`**：新增 `export 'src/platform_impl/wiring.dart';`，
   使消费方可以 `import 'package:videoman/videoman.dart'` 直接拿到
   `createVmEngine`。（该 export 只导出 `createVmEngine` 这一个符号——
   `wiring.dart` 内部用的是 `import` 而非 `export` 引入三个具体适配器类，
   所以它们不会被间接公开为公共 API。）

4. **`example/lib/main.dart`**：`_engine = VmEngine();` 改为
   `_engine = createVmEngine();`。

5. **平台防护性检查**：逐一读了三个适配器的源码，确认无需额外加平台判断——
   - `ScreenBrightnessPort`：`get()`/`set()` 内部已 try/catch，异常时分别兜底
     为 `1.0` / 静默忽略，桌面等不支持 `screen_brightness` 的平台上安全。
   - `ChannelPipPort`：纯转发到 `VmPlatform.instance`，本身不做 IO。
   - `SystemChromeOrientationPort`：只调用 Flutter 自带的 `SystemChrome`
     API，跨平台可用（不支持的平台上是无操作，不会抛异常）。
   三者构造函数本身都不触碰任何原生通道，`createVmEngine()` 无条件构造它们
   是安全的。

6. **CHANGELOG.md**：在既有的 `## 0.2.0` 小节下新增"修复 / Fixes"子小节，
   说明这是对阶段 A 重构自身遗漏的补丁（0.2.0 尚未发布，按惯例直接并入
   0.2.0 而非另起版本号）。

## 新增测试

`test/platform_impl/wiring_test.dart`（3 个用例）：

1. `createVmEngine defaults every port to the real platform adapter` ——
   用 `FakeKernel` 构造 `createVmEngine(kernel: FakeKernel())`，断言
   `debugBrightnessPort`/`debugPipPort`/`debugOrientationPort` 的运行时类型
   分别是 `ScreenBrightnessPort`/`ChannelPipPort`/`SystemChromeOrientationPort`。
   这是本次修复的核心回归测试：只检查类型而不检查行为，就是为了在"某处
   忘记调用真实构造函数"这类问题上不依赖人工评审。
2. `createVmEngine an explicitly injected port overrides the real-adapter default` ——
   传入一个自定义 `_FakeBrightnessPort`，断言 `debugBrightnessPort` 与传入
   实例 `same()`，同时未覆盖的 `pip`/`orientation` 仍是真实适配器，证明
   "显式注入优先于默认值"且默认值是逐端口独立生效的。
3. `VmEngine() itself still defaults to the noop/fallback ports` —— 契约的
   另一半：确认没有改动 `VmEngine` 自身的默认行为，纯 Dart 单测（无法触达
   平台通道）仍然可以安全使用裸 `VmEngine()`。

## 验证命令与完整输出

### `flutter analyze`（repo 根目录）

```
Analyzing videoman...
No issues found! (ran in 3.6s)
```

### `flutter test`

```
00:00 +0: loading D:/workspaces/dart-labs/videoman/test/core/api_test.dart
00:00 +0: D:/workspaces/dart-labs/videoman/test/core/api_test.dart: FakeVmApi replays the current state to late subscribers
00:00 +1: D:/workspaces/dart-labs/videoman/test/core/api_test.dart: FakeVmApi records capability calls
00:00 +2: D:/workspaces/dart-labs/videoman/test/core/bus_test.dart: VmBus emits current value to new listeners
00:00 +3: D:/workspaces/dart-labs/videoman/test/core/bus_test.dart: VmBus skips duplicate values
00:00 +4: D:/workspaces/dart-labs/videoman/test/core/bus_test.dart: VmBus.select only emits when the picked field changes
00:00 +5: D:/workspaces/dart-labs/videoman/test/core/bus_test.dart: throttleStream keeps the first and the last value in a window
00:00 +6: D:/workspaces/dart-labs/videoman/test/core/compat_test.dart: VmController forwards to the engine it wraps
00:00 +7: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: open emits VmSourceChanged then forwards to the kernel
00:00 +8: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: kernel state is reduced into VmState
00:00 +9: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: position is exposed on the throttled progress stream, not states
00:00 +10: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: seek is ignored for live sources when seekMode is off
00:00 +11: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: seek is allowed for live sources in dvr mode and clamped to the window
00:00 +12: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: beforeSeek can cancel a seek
00:00 +13: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: beforePlay can veto playback
00:00 +14: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: kernel errors surface on state and events
00:00 +15: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: showHud/hideControls drive VmUiState
00:00 +16: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: setDragging carries the preview position and clears it on release
00:00 +17: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: ABR downshifts after the configured number of stalls
00:00 +18: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: rapid sequential stall-cycles each produce exactly one downshift without corrupting currentQuality
00:00 +19: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: setFullscreen re-applies orientation when size arrives later while fullscreen
00:00 +20: D:/workspaces/dart-labs/videoman/test/core/engine_test.dart: size changes while NOT fullscreen do not re-apply orientation
00:00 +21: D:/workspaces/dart-labs/videoman/test/core/interceptor_test.dart: empty chain allows everything
00:00 +22: D:/workspaces/dart-labs/videoman/test/core/interceptor_test.dart: a denying interceptor short-circuits beforeOpen
00:00 +23: D:/workspaces/dart-labs/videoman/test/core/interceptor_test.dart: beforeSeek rewrites are threaded through the chain
00:00 +24: D:/workspaces/dart-labs/videoman/test/core/interceptor_test.dart: a null from beforeSeek cancels and stops the chain
00:00 +25: D:/workspaces/dart-labs/videoman/test/core/kernel_contract_test.dart: FakeKernel records calls and replays pushed state
00:00 +26: D:/workspaces/dart-labs/videoman/test/core/kernel_contract_test.dart: VmSize compares by value
00:01 +27: D:/workspaces/dart-labs/videoman/test/core/model_test.dart: parseHlsMasterPlaylist lists auto first, then variants highest-first
00:01 +28: D:/workspaces/dart-labs/videoman/test/core/model_test.dart: parseHlsMasterPlaylist resolves relative variant URIs against the base
00:01 +29: D:/workspaces/dart-labs/videoman/test/core/model_test.dart: parseHlsMasterPlaylist returns empty for a non-master media playlist
00:01 +30: D:/workspaces/dart-labs/videoman/test/core/model_test.dart: VmBufferingAbr signals a downshift after `threshold` stalls (rising edges only)
00:01 +31: D:/workspaces/dart-labs/videoman/test/core/model_test.dart: VmBufferingAbr reset clears the counter and edge state
00:01 +32: D:/workspaces/dart-labs/videoman/test/core/model_test.dart: VmFit cycles contain → cover → fill → contain
00:01 +33: D:/workspaces/dart-labs/videoman/test/core/model_test.dart: VmFit every mode has a non-empty labelKey
00:01 +34: D:/workspaces/dart-labs/videoman/test/core/options_test.dart: VmOptions defaults are const-constructible and preserve 0.1.0 gesture behaviour
00:01 +35: D:/workspaces/dart-labs/videoman/test/core/options_test.dart: VmStrings.fitLabel covers every VmFit value
00:01 +36: D:/workspaces/dart-labs/videoman/test/core/options_test.dart: VmStrings can be replaced wholesale for localisation
00:01 +37: D:/workspaces/dart-labs/videoman/test/core/options_test.dart: VmOptions.copyWith replaces one section only
00:01 +38: D:/workspaces/dart-labs/videoman/test/core/ports_test.dart: fallback brightness port reports full brightness and ignores writes
00:01 +39: D:/workspaces/dart-labs/videoman/test/core/ports_test.dart: noop pip port is unsupported
00:01 +40: D:/workspaces/dart-labs/videoman/test/core/purity_test.dart: core never imports flutter, and only the declared exceptions import media_kit
00:01 +41: D:/workspaces/dart-labs/videoman/test/core/state_test.dart: VmState.copyWith changes only the given field
00:01 +42: D:/workspaces/dart-labs/videoman/test/core/state_test.dart: VmState equality is by value so the bus can dedupe
00:01 +43: D:/workspaces/dart-labs/videoman/test/core/state_test.dart: VmState defaults match 0.1.0 behaviour
00:01 +44: D:/workspaces/dart-labs/videoman/test/core/state_test.dart: VmProgress and VmUiState compare by value
00:01 +45: D:/workspaces/dart-labs/videoman/test/core/state_test.dart: VmUiState.copyWith can clear previewAt
00:01 +46: D:/workspaces/dart-labs/videoman/test/method_channel_test.dart: getPlatformVersion
00:01 +47: D:/workspaces/dart-labs/videoman/test/platform_impl/wiring_test.dart: createVmEngine defaults every port to the real platform adapter
00:02 +48: D:/workspaces/dart-labs/videoman/test/platform_impl/wiring_test.dart: createVmEngine an explicitly injected port overrides the real-adapter default
00:02 +49: D:/workspaces/dart-labs/videoman/test/platform_impl/wiring_test.dart: VmEngine() itself still defaults to the noop/fallback ports
00:02 +50: D:/workspaces/dart-labs/videoman/test/ui/bottom_bar_test.dart: seek bar commits the dragged position on release
00:02 +51: D:/workspaces/dart-labs/videoman/test/ui/bottom_bar_test.dart: seek bar commits the dragged position on release
00:02 +52: D:/workspaces/dart-labs/videoman/test/ui/bottom_bar_test.dart: seek bar commits the dragged position on release
00:02 +53: D:/workspaces/dart-labs/videoman/test/ui/bottom_bar_test.dart: seek bar commits the dragged position on release
00:02 +54: D:/workspaces/dart-labs/videoman/test/ui/bottom_bar_test.dart: seek bar commits the dragged position on release
00:02 +55: D:/workspaces/dart-labs/videoman/test/ui/gesture_test.dart: left vertical drag raises volume, not brightness
00:02 +56: D:/workspaces/dart-labs/videoman/test/ui/gesture_test.dart: left vertical drag raises volume, not brightness
00:02 +57: D:/workspaces/dart-labs/videoman/test/ui/gesture_test.dart: left vertical drag raises volume, not brightness
00:02 +58: D:/workspaces/dart-labs/videoman/test/ui/gesture_test.dart: left vertical drag raises volume, not brightness
00:02 +59: D:/workspaces/dart-labs/videoman/test/ui/gesture_test.dart: left vertical drag raises volume, not brightness
00:02 +60: D:/workspaces/dart-labs/videoman/test/ui/gesture_test.dart: left vertical drag raises volume, not brightness
00:02 +61: D:/workspaces/dart-labs/videoman/test/ui/live_bar_test.dart: live bar shows the LIVE badge and no seek bar by default
00:03 +62: D:/workspaces/dart-labs/videoman/test/ui/live_bar_test.dart: live bar shows the LIVE badge and no seek bar by default
00:03 +63: D:/workspaces/dart-labs/videoman/test/ui/live_bar_test.dart: live bar shows the LIVE badge and no seek bar by default
00:03 +64: D:/workspaces/dart-labs/videoman/test/ui/live_bar_test.dart: live bar shows the LIVE badge and no seek bar by default
00:03 +65: D:/workspaces/dart-labs/videoman/test/ui/live_bar_test.dart: live bar shows the LIVE badge and no seek bar by default
00:03 +66: D:/workspaces/dart-labs/videoman/test/ui/overlays_test.dart: buffering overlay shows only while buffering
00:03 +67: D:/workspaces/dart-labs/videoman/test/ui/overlays_test.dart: buffering overlay shows only while buffering
00:03 +68: D:/workspaces/dart-labs/videoman/test/ui/player_test.dart: VmPlayer provides its api down the tree and renders the skin
00:03 +69: D:/workspaces/dart-labs/videoman/test/ui/player_test.dart: VmPlayer provides its api down the tree and renders the skin
00:03 +70: D:/workspaces/dart-labs/videoman/test/ui/player_test.dart: VmPlayer provides its api down the tree and renders the skin
00:03 +71: D:/workspaces/dart-labs/videoman/test/ui/player_test.dart: VmPlayer provides its api down the tree and renders the skin
00:03 +72: D:/workspaces/dart-labs/videoman/test/ui/player_test.dart: VmPlayer provides its api down the tree and renders the skin
00:03 +73: D:/workspaces/dart-labs/videoman/test/ui/player_test.dart: VmPlayer provides its api down the tree and renders the skin
00:03 +74: D:/workspaces/dart-labs/videoman/test/ui/player_test.dart: VmPlayer provides its api down the tree and renders the skin
00:03 +75: D:/workspaces/dart-labs/videoman/test/ui/player_test.dart: VmPlayer provides its api down the tree and renders the skin
00:03 +76: D:/workspaces/dart-labs/videoman/test/ui/player_test.dart: VmPlayer provides its api down the tree and renders the skin
00:03 +77: D:/workspaces/dart-labs/videoman/test/ui/player_test.dart: VmPlayer provides its api down the tree and renders the skin
00:03 +78: D:/workspaces/dart-labs/videoman/test/ui/skin_test.dart: assemble stacks video at the bottom and overlays on top
00:03 +79: D:/workspaces/dart-labs/videoman/test/ui/skin_test.dart: assemble stacks video at the bottom and overlays on top
00:03 +80: D:/workspaces/dart-labs/videoman/test/ui/skin_test.dart: assemble stacks video at the bottom and overlays on top
00:03 +81: D:/workspaces/dart-labs/videoman/test/ui/skin_test.dart: assemble stacks video at the bottom and overlays on top
00:03 +82: D:/workspaces/dart-labs/videoman/test/ui/skin_test.dart: assemble stacks video at the bottom and overlays on top
00:03 +83: D:/workspaces/dart-labs/videoman/test/ui/skin_test.dart: assemble stacks video at the bottom and overlays on top
00:03 +84: D:/workspaces/dart-labs/videoman/test/ui/skin_test.dart: assemble stacks video at the bottom and overlays on top
00:03 +85: D:/workspaces/dart-labs/videoman/test/ui/skin_test.dart: assemble stacks video at the bottom and overlays on top
00:03 +86: D:/workspaces/dart-labs/videoman/test/ui/skin_test.dart: assemble stacks video at the bottom and overlays on top
00:03 +87: D:/workspaces/dart-labs/videoman/test/ui/top_bar_test.dart: fit button cycles the fill mode and shows the configured label
00:04 +88: D:/workspaces/dart-labs/videoman/test/ui/tree_test.dart: buildSlots groups widgets by slot and sorts by order
00:04 +89: D:/workspaces/dart-labs/videoman/test/ui/tree_test.dart: buildSlots groups widgets by slot and sorts by order
00:04 +90: D:/workspaces/dart-labs/videoman/test/ui/tree_test.dart: buildSlots groups widgets by slot and sorts by order
00:04 +91: D:/workspaces/dart-labs/videoman/test/ui/top_bar_test.dart: replacing VmStrings changes the fit label without touching components
00:04 +92: D:/workspaces/dart-labs/videoman/test/ui/top_bar_test.dart: title shows the current source title, empty when none
00:04 +93: D:/workspaces/dart-labs/videoman/test/ui/top_bar_test.dart: title updates when re-opening a different source of the same stream type
00:04 +94: All tests passed!
```

94/94 通过（基线 91 + 本次新增的 `test/platform_impl/wiring_test.dart` 3 个用例）。

### `cd example && flutter analyze`

```
Analyzing example...
No issues found! (ran in 2.6s)
```

## 涉及文件

- `lib/src/platform_impl/wiring.dart`（新增）
- `lib/src/core/engine.dart`（新增 3 个 `@visibleForTesting` getter）
- `lib/videoman.dart`（新增一行 export）
- `example/lib/main.dart`（`VmEngine()` → `createVmEngine()`）
- `test/platform_impl/wiring_test.dart`（新增，3 个用例）
- `CHANGELOG.md`（0.2.0 小节追加"修复"条目）
