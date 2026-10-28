# mova 支持纯血鸿蒙（HarmonyOS NEXT）可行性评估 · 第 1 步：Dart/Flutter 版本与依赖兼容性

> 日期 2026-10-28。只读调研，未改 mova 任何代码。
> 范围：Flutter-OH 版本与 Dart 对应、mova 代码的语言特性兼容、依赖适配、FFI/纹理、media_kit 与 fvp 鸿蒙现状。
> 不在范围：libmpv 移植、ArkTS 插件实现、真机验证（见末尾 spike 第 2 步）。
> 符号：**[实测]** 本机跑出来的；**[源码]** 读过仓库源码/清单；**[待验证]** 只有间接证据或推断。

## 0. 结论摘要

1. **Flutter-OH 现状**：稳定档最新是 `3.41.9+ohos-1.0.2`（Dart **3.11.5**）；3.44（Dart 3.12.2）只有 beta/canary；3.47（Dart 3.13.5）是 preview。
2. **mova 的 `sdk: ^3.12.2` 与鸿蒙稳定档不兼容，但差距极小**：实测整个 `lib/`+`test/` 只有一处 Dart 3.12 特性（私有命名参数，`cutover_engine.dart:75`）。改一行后，在 Flutter 3.41.9（Dart 3.11.5）上 `analyze` 0 问题、**1744 项单测全过**；再改 3 处 Flutter API，3.35.7（Dart 3.9.2）同样全过。
3. **依赖层面没有硬阻塞**：`screen_brightness`、`path_provider`、`connectivity_plus` 都有鸿蒙实现；mova 自己的原生插件只有 5 个通道调用，且 Dart 侧全部兜住了 `MissingPluginException`，零 ArkTS 也能降级跑起来。
4. **真正的难点在内核**：media_kit 官方不支持鸿蒙，社区有两个 fork（CPF-Flutter 官方适配版：纯软解；Predidit 版：真机硬解，MatePad mini API 26 验证过）。mova 自建的 libmpv（n9.0.2 + WHEP）没有鸿蒙产物。
5. **FFI 与外部纹理都有出处**，但 mova 用到的 `NativeCallable.listener` + `mpv_create_weak_client` 在鸿蒙上没人验证过，是 spike 第一优先项。

## 1. 鸿蒙版 Flutter 与 Dart 版本

仓库：`gitcode.com/openharmony-sig/flutter_flutter` 已迁到 `gitcode.com/CPF-Flutter/flutter_flutter`（旧仓库不再维护，README 公告）。本机 `git` 协议被重置，数据取自 `api.gitcode.com` / `raw.gitcode.com`。

| Flutter-OH | 对应上游 | Dart | 最新 tag（日期） | 分支 | 成熟度 |
|---|---|---|---|---|---|
| 3.22 | 3.22.3 | 3.4.x | `3.22.3+ohos-1.1.6`（2026-09-24） | `oh-3.22.3-release` | 稳定 |
| 3.27 | 3.27.4 | 3.6.2 | `3.27.4+ohos-1.0.9`（2026-09-24） | `oh-3.27.0-release` | 稳定 |
| 3.35 | 3.35.7 | **3.9.2** [实测] | `3.35.7+ohos-1.0.5`（2026-09-24） | `oh-3.35.7-release` | 稳定 |
| 3.41 | 3.41.9 | **3.11.5** [实测] | `3.41.9+ohos-1.0.2`（2026-09-24）；另有 `3.41.10-ohos-1.0.1` | `oh-3.41.9-release` | 稳定（1.0.x） |
| 3.44 | 3.44.9 | **3.12.2** [实测] | `3.44.9+ohos-0.0.1-canary1`（2026-08-21） | `oh-3.44.9-beta`（2026-10-26 仍在提交） | **beta/canary** |
| 3.47 | 3.47.7 | 3.13.5 | `3.47.7+ohos-0.0.1-pre`（2026-10-21） | `oh-3.47.7-preview` | **preview** |

- **对应关系如何确认的**：`oh-3.35.7/3.41.9/3.44.9/3.47.7` 各分支的 `bin/internal/engine.version` 与上游同版本 tag 的 hash **逐一相同** [源码]；上游版本→Dart 版本取自 Flutter 官方 `releases_windows.json`，3.35.7/3.41.9/3.44.9 另在本机装了官方 SDK，`bin/cache/dart-sdk/version` 实读为 3.9.2 / 3.11.5 / 3.12.2 [实测]。
- **发版节奏**（README 版本规划表，标注"预估"）：3.44 → 2026/09，3.47 → 2026/12。截至今天 3.44 还没有 `1.0.x` 稳定 tag，节奏已略滑。
- **tag 命名**有两种并存（`3.41.10-ohos-X` 与 `3.41.9+ohos-X`），README 说 `3.41.10-ohos-*` 基于上游 3.41.9。接入时以仓库 tag 页为准。
- 出处：
  - 分支：`https://api.gitcode.com/api/v5/repos/openharmony-sig/flutter_flutter/branches`
  - tag：`https://api.gitcode.com/api/v5/repos/CPF-Flutter/flutter_flutter/tags`
  - README：`https://raw.gitcode.com/openharmony-sig/flutter_flutter/raw/oh-3.41.9-release/README.md`
  - Dart 版本表：`https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json`

**对 mova 的含义**：mova 现在声明 `sdk: ^3.12.2`，只有 3.44+ 的鸿蒙版满足，而那还是 beta。要用稳定档，必须降下限（见 §2）。**这会改动 mova 包的 SDK 约束（pubspec 现为 0.4.0），需要你拍板**，我没动。

## 2. mova 代码用到的高版本语言特性 / API（实测）

方法：把 `lib/` + `test/` 复制到 scratchpad，只改 `pubspec.yaml` 的 sdk 下限，分别用 (a) 本机 Flutter 3.47（Dart 3.13）降低语言版本，(b) **真实的 Flutter 3.44.9 / 3.41.9 / 3.35.7 SDK**（装在 `E:\sdk\flutter-<ver>`）跑 `flutter analyze lib test` 与 `flutter test`。

### 2.1 语言特性（降低语言版本，分析器逐项报错）

| 特性 | 引入版本 | 出现处 | 降级改写 |
|---|---|---|---|
| 私有命名参数 `{required this._x}` | **Dart 3.12** | `lib/src/core/cutover/cutover_engine.dart:75`（1 处；测试里 34 处报错都是它的连锁，调用点不用改） | 简单，改成 `{required MovaEngineFactory engineFactory}) : _engineFactory = engineFactory`，**对外签名不变** |
| 通配符变量 `(_, _, _) =>` | Dart 3.7 | `lib/src/ui/components/next_up.dart:171`；`test/ui/auto_pause_test.dart:144`；example 3 个文件 5 处 | 简单，只有目标 Dart < 3.7（Flutter-OH 3.27 及以下）才需要改成 `_, __, ___` |
| null-aware elements `[?x]` | Dart 3.8 | 仅 `example/lib/verify_auto/keep_alive_auto.dart:108`（验证脚本） | 简单，仅 example，仅 Dart < 3.8 |
| dot shorthands / extension type / 模式新特性 | 3.10 / 3.3 / 3.0 | **未出现**（降到 3.6 也不报错） | — |

`example/lib`：降到 3.11 为 0 错误；降到 3.6 才出现上表后两行。

### 2.2 Flutter 框架 API（真实 SDK 分析）

| 目标 SDK | 结果 | 需要的改动 |
|---|---|---|
| Flutter 3.44.9 / Dart 3.12.2 | `analyze` 0 问题，**1744 项测试全过** [实测] | 无，原样可用 |
| Flutter 3.41.9 / Dart 3.11.5 | 原样 35 个错（全是私有命名参数连锁）；改 §2.1 第一行后 **0 问题、1744 项全过** [实测] | 1 处（cutover_engine.dart） |
| Flutter 3.35.7 / Dart 3.9.2 | 在上一步基础上还有 2 个错：`TickerModeData` 类型、`TickerMode.getValuesNotifier`；改后 **0 问题、1744 项全过** [实测] | `lib/src/ui/guard/auto_pause.dart` 3 处：`ValueListenable<bool>? _ticker`、`TickerMode.getNotifier(context)`、`!(_ticker?.value ?? true)` |
| Flutter 3.27.4 / Dart 3.6.2 | **未装 SDK**，仅语言层推断：再加 §2.1 第二行（lib 1 处）；Flutter API 缺口未知 [待验证] | — |

- 注：测试数是 1744（拷贝的是当前工作区，含未提交改动），与 `CLAUDE.md` 基线里的 1519 不一致，基线数字已过期，我没去改。
- Kazumi（鸿蒙真实应用）记录 Flutter-OH 3.41 缺 `appBuildName`、`MenuAnchor.animated`、`ReorderableListView.onReorderItem`；mova 都没用到，与上面的分析结果一致。
- Flutter-OH 的 `TargetPlatform` 多一个 `ohos` 枚举值 [源码：`oh-3.41.9-release/packages/flutter/lib/src/foundation/platform.dart:85`]；mova 里唯一对它 `switch` 的地方（`wiring.dart:42`）有 `default`，不受影响。

**建议下限**：改一行就够，拿到 `^3.11.0`（3.41.9+ohos-1.0.2 稳定档）；要兼容 3.35 稳定档再多改 3 行，拿到 `^3.9.0`。是否降、降到哪，需你决定（见 §6 B1）。

## 3. 依赖逐个核对

### 3.1 mova 主包直接依赖

| 依赖（mova 约束） | 鸿蒙适配 | 版本/状态 | 备注 |
|---|---|---|---|
| `media_kit ^1.2.6` | 有两个 fork，见 §5 | CPF `br_3.35`：media_kit **1.2.6**（与约束吻合）；Predidit `main`：**1.1.11**（不吻合，需 override） | 官方 media_kit 无 ohos |
| `media_kit_video ^2.0.1` | 同上 | CPF `br_3.35`：**2.0.1**（吻合）；Predidit：1.2.5（不吻合） | pub.dev 声明的平台里无 ohos |
| `media_kit_libs_video ^1.0.7` | CPF 仓内有 `media_kit_libs_ohos_video`，**不在 pub.dev**；Predidit 用 native assets 自带 libmpv，"不再依赖任何 media_kit_libs_* 插件" | 保留该依赖在鸿蒙上应无害（它只拉 android/ios/… 子包）[待验证] | 软解/硬解取决于 libmpv 产物，见 §5 |
| `connectivity_plus ^6.1.5` | CPF `flutter_plus_plugins` tag `connectivity_plus-7.0.0-ohos.1.0.0`（2026-08-04） | **7.0.0 与 mova 的 ^6.1.5 冲突**；pub.dev 上的 `connectivity_plus_ohos 0.0.3` 是 2024-05 的 Dart2 时代产物，不可用 | 仅 `net_probe_impl.dart`/`wiring.dart`/`preview_config.dart` 用到；可 override、升 `^7`（API 差异未核）或抽成可选端口 |
| `screen_brightness ^2.1.11` | **pub.dev 的 2.1.11 已声明 ohos**，联邦实现 `screen_brightness_ohos 2.1.4`（2026-06-14，要求 `flutter >=3.27.4-ohos-1.0.5`） | Flutter 3.41.9 下 `pub get` 实测自动解析进 lock [实测] | 无需额外工作 |
| `path_provider ^2.1.5` | pub.dev 上 `path_provider_ohos 2.2.1`（2026-08-19） | 非 endorsed，**宿主需显式依赖 `path_provider_ohos`** | 仅 `mpv_audio_extractor_impl.dart` 与两个目录端口的默认实现用到 |
| `plugin_platform_interface`、`meta ^1.16.0` | 纯 Dart | Flutter-OH 3.41 固定 `meta 1.17.0`，在 mova 范围内 [实测：3.41.9 lock 为 meta 1.17.0] | 无问题 |
| dev：`flutter_test`/`fake_async`/`flutter_lints`/`path_provider_platform_interface` | 纯 Dart/测试 | — | 1744 项测试已在 3.41.9/3.35.7 通过 |

### 3.2 example 额外依赖（不影响 mova 主包）

| 依赖 | 鸿蒙 | 处理 |
|---|---|---|
| `sherpa_onnx`（经 `mova_stt`） | pub.dev 平台里无 ohos，CPF 适配清单未见 | 鸿蒙 example 里去掉 `mova_stt` |
| `file_picker` | CPF `fluttertpc_file_picker` 已适配（3.35 列 ✓） | 可用 |
| `just_audio` | CPF `fluttertpc_just_audio` 已适配 | 仅 perf probe，可不带 |
| `cupertino_icons` | 纯字体 | 可用 |

出处：pub.dev API（各包 `latest.pubspec.flutter.plugin.platforms`）；CPF 适配清单 `https://raw.gitcode.com/CPF-Flutter/docs/raw/main/ThirdpartyLibrarites.md`（表头列为 3.35/3.27/3.22/3.7 推荐版本，**没有 3.41/3.44 列**）。

### 3.3 mova 原生插件在鸿蒙需要用 ArkTS 重写的接口

现有实现：Android `MovaPlugin.kt`（173 行）、iOS 仅 `getPlatformVersion`（19 行）、Windows 59 行。MethodChannel 名 `mova`：

| 方法 | 入参 → 返回 | 用途 | Dart 侧缺插件时 |
|---|---|---|---|
| `isPipSupported` | — → `bool` | PiP 按钮是否显示 | `MissingPluginException` → `false`（按钮自动隐藏） |
| `enterPip` | `{width,height}` → `bool` | 进入系统画中画 | → `false` |
| `getSystemVolume` | — → `double?`（0–100） | 系统媒体音量读取 | → `null`，引擎改走播放器音量路径 |
| `setSystemVolume` | `{percent}` → `bool` | 系统媒体音量设置 | → `false` |
| `pipChanged`（原生→Dart 推送） | `bool` | PiP 状态回传 | 不推送则 `state.pip` 不变 |
| `getPlatformVersion` | — → `String?` | 脚手架遗留，无业务用途 | — |

- **结论**：可以**零 ArkTS 起步**（PiP 不可用、音量走播放器音量，其余照常）；音量和 PiP 作为后续增强再补。鸿蒙 PiP 对象是 mpv 的 XComponent/纹理，可行性未调研 [待验证]。
- 亮度走 `screen_brightness_ohos`，方向/沉浸式走 Flutter 的 `SystemChrome`：Flutter-OH 3.41.9 的 `PlatformPlugin.ets` 实现了 `setPreferredOrientations` 与 `SystemUiMode`（immersive / immersiveSticky / leanBack / edgeToEdge）[源码]，真机行为 [待验证]（Kazumi 全屏/系统栏是另走 ArkTS 接的，原因未说明）。
- 需新增的工程结构（参考 fvp 的 ohos 目录）：`ohos/` HAR 模块（`build-profile.json5`、`hvigorfile.ts`、`index.ets`、`oh-package.json5`、`src/main/module.json5`、插件类 `.ets`），以及 `pubspec.yaml` 的 `flutter.plugin.platforms.ohos: {package, pluginClass}`。

### 3.4 代码里的平台分支（鸿蒙行为）

| 位置 | 现状 | 鸿蒙上的结果 |
|---|---|---|
| `core/preview/platform_kind.dart` | `Platform.isAndroid/isIOS/…`，其余 `other` | 落到 `other`；`MovaPreviewConfig.extractPlatforms` 默认集合已含 `other`，预览抽帧不被禁用 |
| `ui/components/top_bar.dart:326` | 方向按钮仅 `android/iOS` | 鸿蒙隐藏，要显示需加 `TargetPlatform.ohos`（1 行） |
| `platform_impl/wiring.dart:42` | `switch(defaultTargetPlatform)` 有 `default` | 系统音量端口为 `null` |

## 4. dart:ffi 与外部纹理

| 项目 | 结论 | 出处 |
|---|---|---|
| `dart:ffi` 可用 | **可用**。Flutter-OH 支持 `flutter create -t plugin_ffi --platforms ohos`；Predidit 版 media_kit 全部依赖 FFI，在 MatePad mini（API 26）真机跑通 | [源码] Flutter-OH README 指令表；Predidit PR #43 |
| libmpv 如何进包 | Predidit：Flutter native assets 构建钩子（`media_kit/hook/src/ohos.dart`）按 OHOS SDK 识别目标，打包 arm64 `libmpv.so` + `libmedia_kit_event_loop.so` + `libc++_shared.so`；注意 Flutter-OH 以 **Linux 目标**向钩子上报 OHOS 编译器。CPF：随包 `media_kit_libs_ohos_video` | [源码] |
| 外部纹理 | 引擎有 `ohos_external_texture_gl.cpp` / `ohos_external_texture_vulkan.cpp`；ArkTS 侧 `TextureRegistry` → `SurfaceTextureEntry.getTextureId()/getSurfaceId()`，surfaceId 即 `OHNativeWindow` 句柄交给打了补丁的 mpv（`vo=gpu-next`，属性 `ohos-surface-size`，EGL 上下文 `ra_ctx_openharmony`） | [源码] Flutter-OH `engine/src/flutter/shell/platform/ohos/`；Predidit `media_kit_video/ohos/.../VideoOutput.ets` 与 `ohos_video_controller/real.dart` |
| mova 用到的 FFI 构造 | `NativeCallable<…>.listener` + `mpv_set_wakeup_callback` + `mpv_create_weak_client` + `mpv_wait_event`，依赖 `package:media_kit/generated/libmpv/bindings.dart` 与 `NativePlayer.handle`（`mpv_event_backend_ffi.dart`）。debug 下走 100ms 轮询，**release 才用原生回调** | [源码] mova |
| 风险 | CPF 仓库里有过一次"Flutter 3.38+/Dart 3.10+ 的 FFI 回调崩溃"修复被回滚（Android 侧，上游 #1350）；`NativeCallable.listener` 在 Flutter-OH 的 release AOT 上**无人验证** | [待验证] spike 第一优先项 |
| 模拟器 | Predidit 的 `OhosVideoController.create` 在模拟器上**直接抛 `UnsupportedError`**；libmpv 产物仅 arm64；Flutter-OH FAQ 称模拟器不支持 vulkan | [源码] |

## 5. media_kit 鸿蒙 fork 与 fvp 现状

| 项 | CPF-Flutter `fluttertpc_flutter_media_kit` | Predidit/media-kit（Kazumi 作者体系） | fvp（wang-bin） |
|---|---|---|---|
| 地址 | `gitcode.com/CPF-Flutter/fluttertpc_flutter_media_kit` | `github.com/Predidit/media-kit` | `github.com/wang-bin/fvp`，pub.dev `fvp 0.39.1`（2026-10-15）声明 `ohos` |
| 最近活动 | main 2026-07-10；`br_3.35` 2026-08-05；tag `1.2.6-ohos-1.0.0`（2026-08-04） | **2026-10-18** 仍在提交；10-17 `feat(ohos): support native assets builds (#43)`，08-11 `improve hardware decode performance (#40)` | 2026-10-25 仍在提交；鸿蒙专属 PR 仅 #344（4 月，重构为 HAR 插件 + NAPI）、#347（4 月，修播放失败） |
| 版本与 mova 约束 | `br_3.35`：media_kit 1.2.6 / video 2.0.1，**吻合** | media_kit 1.1.11 / video 1.2.5，**需 override** | 不是 libmpv，是 libmdk；实现 `video_player` 接口 |
| Flutter-OH | README 仅声明在 3.27.0 / SDK 5.0.0(12) 测过；有 3.35 tag | Kazumi 用 **3.41.9+ohos-1.0.2 / Dart 3.11.5** 真机验证；media_kit pubspec `sdk >=3.10.0` | `flutter >=3.22.0`，Dart `^3.4.0`，HarmonyOS 5.0+，仅 arm64-v8a |
| 解码 | **纯软解**：随包 libmpv 为 FFmpeg n6.1 + mpv 0.40，无 `--enable-ohcodec`（issue #27 自述）；硬解在 #27/#12 跟踪，状态 open | **软解 + `ohcodec` 硬解**，MatePad mini（API 26）真机 24 次播放/销毁全过，纹理画面截图确认（PR #43 描述 + Kazumi `OHOS_BUILD.md`） | 硬解由 libmdk 负责 |
| 已知问题 | #11：`Platform.isOhos` 在 Android/iOS 上 `NoSuchMethodError`；#21：iOS 无声；#23：请求适配 3.44.9（open） | 仅 arm64 真机；不支持模拟器及其他架构 | 82 个 open issue（含非鸿蒙），鸿蒙相关未细查 |
| 授权 | MIT | MIT（上游 media_kit） | libmdk 为预编译二进制，条款**未核** [待验证] |

出处：gitcode API（`repos/CPF-Flutter/fluttertpc_flutter_media_kit/{branches,tags,commits,issues}`）；GitHub API（`repos/Predidit/media-kit`、`repos/wang-bin/fvp`）；Kazumi 构建说明 `https://github.com/tignioj/Kazumi/blob/e6b9f7d65b9791a2d31798ced8ed9450a820d117/static/doc/OHOS_BUILD.md`。

## 6. 阻塞项清单

工作量为经验估计，未经验证。

| # | 阻塞项 | 严重度 | 解法 | 工作量 |
|---|---|---|---|---|
| B1 | mova `sdk: ^3.12.2` > 鸿蒙稳定档 Dart 3.11.5（3.44 仅 beta） | **高（决策项）** | 三选一：①等 3.44 稳定；②降到 `^3.11.0` + 改 1 行；③降到 `^3.9.0` + 改 4 行。②③会改动 mova 的 SDK 约束，需你定 | ②约 0.5h；③约 1–2h；都已有实测验证 |
| B2 | media_kit 无官方鸿蒙支持，宿主要用 git fork + `dependency_overrides`（发布到 pub.dev 的包不能带 git 依赖） | 高 | 选 CPF `br_3.35`（版本号吻合、软解）或 Predidit（硬解、版本号不吻合）。mova 本体仍依赖 pub.dev 的 media_kit，由宿主 override | spike 1–2 天 |
| B3 | mova 自建 libmpv（n9.0.2 + mpv 0.41 + WHEP，瘦身）**没有鸿蒙产物**；现有 fork 的 libmpv 分别是 n6.1 软解 / Predidit 带 ohcodec | 高（仅路线 A） | 路线 A 需在 OH NDK 上构建：`--enable-ohcodec` + 鸿蒙 mpv 补丁（EGL 上下文、surface-size）；或先借用 Predidit 产物验证 mova 逻辑 | 借用产物：1–2 天；自建：以周计 |
| B4 | FFI 事件泵在鸿蒙未验证（`NativeCallable.listener` + weak client，release 才走回调） | 中 | spike 真机验证；失败时 `createMovaEngine` 退化为 100ms 轮询（debug 已有） | 0.5–1 天 |
| B5 | 仅 arm64 真机，模拟器不可用 | 中 | 准备真机；CI 无法跑真机用例 | 环境问题 |
| B6 | `connectivity_plus ^6.1.5` 与鸿蒙适配版 7.0.0 冲突 | 低 | override，或升 `^7`（需核 API），或把网络探测改成可选端口 | 0.5 天 |
| B7 | `path_provider_ohos` 非 endorsed | 低 | 文档要求宿主显式依赖 | 0.1 天 |
| B8 | 原生插件：PiP、系统音量 | 低（可降级） | 先零 ArkTS 起步；音量用 `@ohos.multimedia.audio`，PiP 用 `@ohos.PiPWindow`（API 名与可行性未核） | 音量约 0.5 天；PiP 不确定，对象是 mpv 纹理 |
| B9 | `SystemChrome` 全屏/方向的真机行为；`top_bar` 方向按钮平台判断 | 低 | 源码已实现，真机验证；加 `TargetPlatform.ohos` | 0.5 天 |
| B10 | `media_kit_libs_video` 在鸿蒙无 pub.dev 对应 | 低 | 保留依赖应无害；Predidit 路线不需要它 | 验证 0.2 天 |
| B11 | 发布：`flutter.plugin.platforms` 加 `ohos`；`ohos/` HAR 模块骨架 | 低 | 参考 fvp 的 ohos 目录 | 0.5 天 |

## 7. 三条路线在兼容性层面的影响

| | A 移植 libmpv（沿用 media_kit） | B 系统 AVPlayer 内核 | C fvp（libmdk） |
|---|---|---|---|
| Dart/Flutter 下限 | 同 B1（media_kit fork 要 Dart ≥3.10 / 3.1） | **最宽松**，只取决于 mova 自身约束 | 最宽松（`^3.4.0`，`flutter >=3.22.0`） |
| 依赖 | media_kit git fork + libmpv 产物 + native assets 钩子 | 不需 media_kit/FFI；但 mova 主包 `pubspec` 仍依赖 media_kit，鸿蒙构建会触发其钩子，**需把 mpv 内核拆出主包或做条件依赖** | 新增 `fvp`；需实现新 `MovaKernel` |
| mova 代码改动 | **几乎为零**（`MovaMpvKernel`、FFI 事件泵、cutover、keepAlive、QoE、WHEP 全保留） | 新写 `MovaKernel`；丢失依赖 mpv 的能力：keepAlive（`vid`/`mute`）、抽帧预览、cutover 双引擎的 `renderHandle` 路径、原生事件泵与 `MovaStatsProbe`、WHEP | 同 B，且能力更少（无 mpv 属性）；授权与二进制分发需核 |
| 硬解 | 取决于 libmpv 产物（Predidit 已有；CPF 无） | 系统自带 | libmdk 自带 |
| 主要风险 | B3、B4（libmpv 产物与 FFI 回调） | 功能面缩水与行为差异（seek/缓冲/直播时移语义不同于 mpv） | 闭源二进制、鸿蒙 PR 少（2 个）、成熟度待测 |
| 参考实现 | Predidit PR #40/#43、Kazumi | `openharmony-sig/flutter_packages` 的 `video_player` ohos 版（tag `video_player-v2.11.1-ohos-1.0.1`）[源码，仅看 tag 未读代码] | fvp `ohos/` 目录 |

在兼容性层面，**路线 A 对 mova 代码侵入最小**，难点集中在 libmpv 产物与 FFI 回调；B/C 对 Dart 版本最友好，但要新写内核并接受能力缩水。路线取舍留给你。

## 8. spike 第 2 步（DevEco 上跑最小 libmpv）所需环境

| 类别 | 需要 | 备注 |
|---|---|---|
| 设备 | **HarmonyOS 真机（arm64）** | 模拟器不可用（见 §4）；Kazumi 验证机型 MatePad mini，API 26；CPF 测试环境为 SDK 5.0.0(12) |
| 开发机 | DevEco Studio、HarmonyOS SDK（Kazumi 用 26.0.0.105）、JDK 17、`HOS_SDK_HOME`、`DEVECO_NODE_HOME`、`hdc`、`ohpm`、`~/.npmrc`（华为仓库 registry）、`git` 在 PATH（Flutter-OH FAQ 第 13 条） | 本机均**未确认**已装，需先查 |
| 签名 | 调试签名证书 + 设备 Profile | Kazumi 用 CLI signer 复用已有材料 |
| Flutter-OH | 建议先上 **`3.41.9+ohos-1.0.2`**（提交 `62357a93`，Dart 3.11.5），备选 3.44.9 beta；设 `FLUTTER_STORAGE_BASE_URL=https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com`，换源后清 `bin/cache` | 本机 `git` 协议连 gitcode 被重置，clone 需代理/镜像；`api.gitcode.com`、`raw.gitcode.com` 可用；官方版 3.35.7/3.41.9/3.44.9 已装在 `E:\sdk\flutter-<ver>`，可用于上游对照，不是 Flutter-OH |
| mova 侧 | 按 B1 选一种降下限方案（或直接用 3.44.9 beta 免改）；example 去掉 `mova_stt`/`sherpa_onnx`；`dependency_overrides` 指 media_kit fork | — |
| libmpv | 路线 A 验证：先用 Predidit 的 arm64 产物（native assets）；自建则需 OH NDK + 鸿蒙 mpv 补丁 + ffmpeg `--enable-ohcodec` | — |
| 验证项（按优先级） | ① 3.41.9-ohos + mova + fork 最小播放；② release 下 FFI 事件泵（`NativeCallable.listener`）；③ 首帧/纹理/`rendered`；④ `hwdec-current`；⑤ `SystemChrome` 全屏/方向；⑥ keepAlive 的 `vid` 切换、cutover 双引擎 | 用基于真实事件的测量，不用墙钟 |

## 附：未能核实 / 没做的事

- 未装 Flutter-OH 本体（gitcode git 协议不通），所有"鸿蒙版"结论来自分支/tag 元数据、`engine.version` 对账、源码阅读与第三方真机记录，**没有在 Flutter-OH 上编译过 mova**；§2 的实测是用**对应版本的官方上游 SDK**。
- 3.27.4（Dart 3.6.2）及以下没装 SDK 实测。
- PiP、系统音量的鸿蒙 API 名与可行性未核；iOS/鸿蒙对比未做。
- `connectivity_plus` 6→7 的 API 差异、libmdk 授权条款、fvp 鸿蒙 issue 细节未核。
- CPF 适配清单的表头只有 3.35/3.27/3.22/3.7 列，3.41/3.44 的第三方库适配状态**清单里没有**，上面依赖结论里 3.41 的部分来自 `pub get` 实测与 Kazumi 的真机记录。
- 临时分析副本在 scratchpad（`...\scratchpad\ohos\work\`），不在仓库内，未修改 mova 任何文件。
