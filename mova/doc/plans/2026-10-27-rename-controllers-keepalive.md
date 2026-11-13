# 改名清单：去掉 *Controller + standby → keepAlive

> 2026-10-27 · **等 Codex 真机覆盖测试结束后再动手**（它的验证页在用旧名）。公开 API 破坏性改名，计划里曾打算旧名留 `@Deprecated` typedef 一个版本；实际 2026-11-12 的全量改名已直接删除所有旧名与 `@Deprecated` 别名（见 CHANGELOG `Unreleased`）。

## 一、Controller 类

| 旧名 | 新名 | 文件 |
|---|---|---|
| `MovaAdController` | `MovaAds` | core/ad/ad_controller.dart |
| `MovaFeedController` | `MovaFeed` | core/feed/feed_controller.dart |
| `MovaPlaylistController` | `MovaPlaylist` | core/playlist/playlist_controller.dart |
| `MovaMiniController` | `MovaMini` | ui/mini/mini_ctl.dart |
| `MovaSwapController` | `IMovaCutover`（接口） | core/swap/ctl.dart |
| `MovaStandbyController` | `IMovaKeepAlive` | core/standby/standby.dart |

## 二、standby → keepAlive（整功能，默认方案）

| 旧名 | 新名 |
|---|---|
| `MovaStandbyController` | `IMovaKeepAlive`（见上） |
| `MovaStandbyConfig` / `MovaOpts.standby` | `MovaKeepAliveOpts` / `MovaOpts.keepAlive` |
| `MovaStandbyPhase`（`MovaState.standby`） | `MovaKeepAlivePhase`（`MovaState.keepAlivePhase`，已定；旧 `standby` 留 `@Deprecated` getter） |
| `MovaStandbyMode` | `MovaKeepAliveMode` |
| `MovaStandbyReason` | `MovaKeepAliveReason` |
| `MovaStandbyEntry` / `MovaStandbyEntryKind` | `MovaKeepAliveEntry` / `MovaKeepAliveEntryKind` |
| `MovaStandbyWake` / `MovaStandbyMedia` | `MovaKeepAliveWake` / `MovaKeepAliveMedia` |
| `MovaStandbyKernel` | `IMovaKeepAliveKernel` |
| `MovaStandbyChange` / `MovaStandbyResume`（事件） | `MovaKeepAliveChange` / `MovaKeepAliveResume` |
| `MovaSilentStandby` | `MovaSilentKeepAlive` |
| `MovaHiddenMode.standby` | `MovaHiddenMode.keepAlive` |
| `setStandby(bool)` | `setKeepAlive(bool)` |
| `standbyCapable`（gate 参数）、`standbyPhase` | `keepAliveCapable`、`keepAlivePhase` |
| 文件 `core/standby/`、`standby_kernel.dart`、`standby_opts.dart` | `core/keep_alive/`、`keep_alive_kernel.dart`、`keep_alive_opts.dart` |

## 二·附、swap → Cutover（整功能）

| 旧名 | 新名 |
|---|---|
| `MovaSwapEngine`（更早叫 `MovaCutoverEngine`） | `MovaCutover` |
| `MovaSwapController` | `IMovaCutover` |
| `MovaSwapConfig` / `MovaOpts.swap` | `MovaCutoverOpts` / `MovaOpts.cutover` |
| `MovaSwapChange`（事件） | `MovaCutoverChange` |
| `swapTo` | `cutoverTo` |
| 目录 `core/swap/` | `core/cutover/` |
| `MovaWarmPlan` / `IMovaWarmTrigger` / `IMovaWarmPolicy` | 保持（"预热"是独立概念） |
| `MovaState.renderEpoch` | 保持 |

## 三、波及范围

- 约 73 个文件含 Controller 旧名，54 个含 standby；合集待落地时用 grep 确认。
- 同步：test 全部、example（含 `main_standby_verify.dart` → `main_keepalive_verify.dart`、`verify_auto/standby_auto.dart`）、README「隐藏时待机」、CHANGELOG、doc/SPEC.md、CLAUDE.md、doc/plans 里的历史文档当时只计划在新增"改名说明"处注明；2026-11-12 改名收尾时已统一改成新名（本文保留旧名到新名的映射）。
- 版本：0.5.0（破坏性），CHANGELOG 记旧→新对照。

## 四、步骤

1. Codex 结束，工作区干净（剔除生成文件）。
2. 先改 Controller 六个类（机械替换 + typedef 旧名别名）。
3. 再改 standby→keepAlive（含文件重命名，用 `git mv`）。
4. `flutter analyze lib test` 0 issues、`flutter test` 全绿（基线 1472）。
5. 更新 CLAUDE.md 测试基线与命名说明，提交 `refactor(mova)!: ...`。
