## 0.2.0

阶段 A 重构：`core/` + `ui/` 分层架构落地，功能与 0.1.0 保持一致
（无新增可见功能，纯架构收口）。

* **core/ 骨架**：`VmApi`（能力面抽象）+ `VmEngine`（实现，取代 `VmController`）
  + `VmKernel`（内核抽象，唯一 import media_kit 的是 `mpv_kernel.dart`）
  + `VmBus`（事件总线）+ sealed `VmEvent` + `VmState`/`VmProgress`/`VmUiState`
  + `VmInterceptor`（`beforeOpen`/`beforeSeek`/`beforePlay`/`onError` 四个拦截点）。
* **ui/ 组件树 + 皮肤 + 补丁**：0.1.0 的 `VodControls`/`LiveControls`/
  `VmGestureDetector` 拆分为可组合的 `VmComponent` 叶子/组合组件
  （`TopBarComponent`/`BottomBarComponent`/`LiveBarComponent`/`GestureLayerComponent`/
  `HudLayerComponent`/`CenterPlayComponent`/`overlays` 等），由 `VmSkin`
  （默认实现 `VmDefaultSkin`）依据 `VmState` 出树、通过 `VmPatch`
  （`replace`/`remove`/`insertAfter`/`add`）做结构级定制，无需派生子类。
* **文案与主题外置**：`VmStrings`（默认简体中文文案）与 `VmTheme`
  （默认配色/尺寸，ARGB `int` 存储以保持 `core/` 零 Flutter 依赖）
  从 `VmOptions` 注入，替换 0.1.0 硬编码的中文字符串与 `Colors.*`。
* **`VmController` 弃用**：标注 `@Deprecated('Use VmEngine instead. 0.3.0 移除。')`，
  仍在 `lib/src/core/compat.dart` 提供做迁移期兼容门面。
* **开放性对账**：审计并清理了皮肤/组件层残留的硬编码颜色与重复的中文标签函数
  （详见 Task 19 报告）。

### 破坏性变更 / Breaking changes

| 0.1.0 | 0.2.0 |
|---|---|
| `VmController` | `VmEngine`（`VmController` 仍可用但已弃用，0.3.0 移除） |
| `VodControls` | `VmDefaultSkin`（VOD 时出的 `BottomBarComponent` 等组件） |
| `LiveControls` | `VmDefaultSkin`（Live 时出的 `LiveBarComponent` 等组件） |
| `VmGestureDetector` | `VmDefaultSkin` 内的 `GestureLayerComponent` |
| 派生子类定制控制条 | 传入 `VmPatch` 列表给 `VmDefaultSkin(patches: [...])`，或整体替换 `VmSkin` |
| 硬编码中文文案/配色 | `VmOptions.strings`（`VmStrings`）/ `VmOptions.theme`（`VmTheme`）注入替换 |

### 修复 / Fixes

* **补上阶段 A 遗漏的平台适配器接线**：阶段 A 把亮度/画中画/方向拆成
  `VmBrightnessPort`/`VmPipPort`/`VmOrientationPort` 三个可注入端口，并在
  `lib/src/platform_impl/` 下实现了对应的真实适配器
  （`ScreenBrightnessPort`/`ChannelPipPort`/`SystemChromeOrientationPort`），
  但全仓库没有任何地方真正构造过它们——`VmEngine()` 未显式注入时会静默落到
  `FallbackBrightnessPort`/`NoopPipPort`/`NoopOrientationPort`，导致右侧亮度
  手势、`enterPip()`、`setFullscreen()` 的方向/沉浸式系统 UI 在 0.2.0 里全部
  失效（0.1.0 中可用）。新增 `createVmEngine()`（`lib/src/platform_impl/wiring.dart`，
  已从 `lib/videoman.dart` 导出）默认接入三个真实适配器，同时保留
  `VmEngine()` 自身的空/兜底默认值不变（供纯 Dart 单测使用）；`example/lib/main.dart`
  已改用 `createVmEngine()`。

## 0.1.0

首个可用版本 / First usable release.

* 基于 media_kit（libmpv/ffmpeg）的播放内核封装：`VmController` / `VmSource`。
* 手势层：左音量 / 右亮度 / 横滑进度 / 双击快进退 / 双指缩放，带 HUD。
* 点播 / 直播两套控制条；单击切换显隐、自动隐藏。
* 观看模式 contain / cover / fill；锁定/解锁防误触 + 沉浸式。
* 全屏按视频宽高比自动横/竖屏。
* 清晰度：HLS master 解析、手动切换（保位续播）、缓冲卡顿自动降档。
* Android 系统级画中画（iOS/桌面暂不支持）。

## 0.0.1

* 初始脚手架 / Initial scaffold.
