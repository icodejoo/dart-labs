# layerman demo / 线上演示

当前版本 / Current version: **1.0.1**，通过 `path: ../` 使用本包。

- 线上 / Live: https://icodejoo.github.io/dart-labs/layerman/
- 中文 / Chinese: https://icodejoo.github.io/dart-labs/layerman/?lang=zh
- English: https://icodejoo.github.io/dart-labs/layerman/?lang=en
- 未指定 `lang` 时跟随浏览器语言；可在页头切换，选择保存在内存。
  Without `lang`, the browser locale selects Chinese or English. Header selection lives in memory.
- 侧栏 / Drawer 支持 `#/pages/<id>`，刷新和浏览器前进、后退恢复当前页。
  Hash navigation restores the selected page across reload and browser history.
- 默认跟随系统亮暗，也可手动切换。卡片按实际内容宽度响应式分列，代码默认折叠、展开占整行。
  System light/dark with manual toggle; responsive equal-height grid rows and full-width collapsible code.

## 页面 / Pages

| ID | 页面 / Page | 演示 / Coverage |
| --- | --- | --- |
| `queue` | 队列与模式 / Queue & modes | FIFO、priority、replace、affix、overlap、独立 slots、blockedBy |
| `timing` | 计时与暂停 / Timing & pause | delay、duration、dismissed + exitDuration、整体/单项暂停、路由免打扰、hold、前后台 |
| `conditions` | 条件与准入 / Conditions & gates | RouteMatcher.exact/anyOf/regex、auth、when、gate pass/waitUntil/drop、dismissWhenUnmet |
| `cooldown` | 冷却与抑制 / Cooldown & suppress | session、total、day/hour/minute、minGap、组合上限、永久/临时 suppress |
| `data` | 数据与结果 / Data & outcomes | resolve/null、beforeClose、dataListenable/update、自动 ID、typed ticket、tags、visible、build 内提交 |
| `presenters` | UI 后端 / UI backends | Material dialog/sheet、GetX dialog/snackbar、bot_toast、shadcn dialog/sheet/toast、跨库序列 |
| `setup` | 接入说明 / Setup | 初始化、路由观察器、生命周期绑定、内存/自定义存储、释放契约 |
| `diagnostics` | 压测：队列诊断 / Benchmarks: Queue diagnostics | expireAfter、maxQueued、dismissTimeout、100 项突发队列 |

40 张引擎卡片通过真实 `Layerman` 和卡片内 `present` 后端运行，9 张 UI 卡片打开真实 UI 库后端。
所有状态演进、加载、计时、淡出与弹层卡片均提供 **重放 / Replay**；3 张静态接入卡片不提供。
每个实例独立持有 manager，重放取消旧计时、结束旧后端、清空队列/数据/冷却，再开始演示。
UI 后端的重放使用外部控制器回调；页面卸载同样清理自己的路由或提示句柄。

40 engine cards use real `Layerman` instances and an inline `present` backend; 9 UI cards use real UI library backends.
Every evolving, loading, timed, fading or overlay example has Replay; the 3 static setup cards do not.
Each card owns its manager. Replay clears timers, backend handles, queues, data and cooldowns before restarting.
Backend cards use the explicit controller reset callback. Leaving the page also cleans owned handles.

所有后端均通过 `OverlayVisibility` 或 `presentRoute` 确认真实首帧。
`duration` 从激活开始，不等待 `visible`；`shown` 事件和冷却计数等待首帧成功确认。
内存冷却在刷新或重放后清空；跨会话持久化需要业务实现 `OverlayCooldownStorage`。

All backends confirm first paint through `OverlayVisibility` or `presentRoute`.
`duration` starts at activation; `shown` events and frequency counts wait for successful visibility confirmation.
Memory cooldown state resets on reload/replay. Cross-session persistence requires an `OverlayCooldownStorage` implementation.

## 迁移审计 / Migration audit

对照当前 `lib/` 导出、1.0.1 CHANGELOG 和包 README 审计原 12 页。
Audited all 12 former pages against current exports, the 1.0.1 changelog and package README.

| 原页面 / Former page | 处理 / Change | 原因 / Reason |
| --- | --- | --- |
| Queue Basics | 合入 `queue` / Rebuilt in `queue` | 修正“高优先级抢占当前项”；现在先展示 A，再比较等待项 B/C。自动 ID 使用真正的 null ID。 / Priority only reorders waiting entries; null ID exercises actual auto generation. |
| Replace & Affix、Overlap | 合入 `queue` / Merged into `queue` | 去掉重复槽位演示和宽屏固定偏移；保留抢占、固定保护、并行及定向关闭。 / Removes duplicate slot previews and fixed offsets while retaining each behavior. |
| Timing、Pause & Resume | 合入 `timing` / Merged into `timing` | 修正 delay/gap、duration、退场契约；操作不会被模态屏障挡住。 / Correct timing and dismissal contracts, with reachable controls. |
| Conditions | 重写 `conditions` / Rebuilt | 保留三种 matcher、auth、when、gate；明确每张卡片模拟自己的 route 上下文。 / Keeps all eligibility APIs with isolated route contexts. |
| Cooldown | 重写 `cooldown` / Rebuilt | 删除“session/minGap 无需等待读取”的错误说明；所有 cooldown 自动等待读取，total 默认内存而非永久存储。 / All cooldown submissions await hydration; default total storage is memory. |
| Lifecycle | 合入 `data` / Merged into `data` | 删除“没有 OverlayPhase”的旧说明；直接展示 payload 通道和 typed outcome。 / Removes outdated phase guidance and demonstrates live data/outcomes. |
| v0.3 Features | 按能力拆分 / Split by capability | 删除旧版本入口；suppress、blockedBy、tags、visible、build 提交回到对应主题。过期、容量及失联后端保留在 `diagnostics`。 / Removes version-based navigation and retains diagnostics. |
| External Presenters、Mixed UI Libraries | 合并 `presenters` / Merged | 同一后端不再重复列多种静态外观；保留 8 种后端与跨库序列。 / Removes repeated styling variants, retaining 8 backend types and a mixed sequence. |
| Setup & Restart | 重写 `setup` / Rebuilt | 删除已移除 scope 的历史叙述；整应用重启改为各卡片独立重放，接入代码只展示当前契约。 / Current setup contract and per-card restart replace historical/global restart guidance. |

未发现原生专用 benchmark 页面；原开发诊断没有丢弃。新增轻量突发队列压测，不引用历史 FPS/耗时数据。
No native-only benchmark pages existed. Existing diagnostics remain available, with an added burst queue and no historical performance claims.

`diagnostics` 的退场超时卡片故意让后端不响应关闭，会报告预期 `TimeoutException`；引擎释放槽位后仍需点击“清理失联视图”。
The dismiss-timeout diagnostic deliberately reports an expected `TimeoutException`; after the engine releases the slot, the owner must clean the stale view.

## 统一组件 / demo_kit

完整复制 countman 试点的自包含 `lib/demo_kit/`，无跨项目依赖、无新增第三方依赖。
本副本增加 `DemoApp.appBuilder` 以接回已有 UI 宿主、`DemoCard.onReplay` 以重置外部控制器，并将中文按钮文案统一为“重放”。
原 demo_kit 无需通用 bug 修复；本项目适配器修复 shadcn 卸载期间 hide 的时机，并让路由后端等待 TransitionRoute.completed，避免队列在退场动画中提前推进。

The complete self-contained countman kit is copied locally, without cross-project or new third-party dependencies.
This copy adds `DemoApp.appBuilder` for the existing UI host and `DemoCard.onReplay` for external controller resets.
The kit needs no generic bug fix. Example adapters defer shadcn hide safely during teardown and await TransitionRoute.completed before advancing the queue.

## 运行与验证 / Run and verify

```powershell
# layerman/
flutter analyze --no-fatal-infos
flutter test

# layerman/example/
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build web --release --base-href /dart-labs/layerman/
flutter run -d chrome
# Optional, requires a real device / 可选，需要真实设备：
flutter test integration_test/orchestration_test.dart -d <device-id>
```

版本 chip 由 `demoVersion` 提供，widget 测试校验其与包 `pubspec.yaml` 同步。
`widget_test.dart` 覆盖全部页面的中英文、亮暗以及 375×667 / 1440×900 布局；
`scenario_demo_test.dart` 覆盖 40 个场景重放与行为；`backend_demo_test.dart` 验证 9 种真实后端重放/切页清理；
保留 README 配方及后端首帧测试，`demo_kit_test.dart` 覆盖公共组件契约。

A widget test checks `demoVersion` against the package pubspec. Tests exercise all pages at 375×667 / 1440×900,
both languages/themes, all 40 engine scenarios, 9 backend replay/teardown paths, README recipes and demo_kit contracts.

部署路径以仓库 `.github/workflows/deploy-layerman.yml` 为准，无需修改 workflow。
若本地手动服务 release 产物，先复制到临时目录 `dart-labs/layerman/`，再从该目录的祖先启动
`python -m http.server`，访问对应子路径；结束后关闭自己启动的服务。

Deployment matches `.github/workflows/deploy-layerman.yml`; no workflow changes are required.
Serve a temporary `dart-labs/layerman/` subtree with `python -m http.server`, then stop the server after testing.

## 本轮验证记录 / Verification record

2026-11-12，Flutter 3.47.0 / Dart 3.13.0：

- 包与 example：`flutter analyze --no-fatal-infos` → `No issues found!`，没有新增或遗留 info。
- 包：`flutter test --reporter expanded` → **1,146 passed**。
- Example：`flutter test --reporter expanded` → **117 passed**；含中英文、亮暗、375×667 / 1440×900、40 个引擎场景重放、9 种 UI 后端及路由实际退场回归。
- `flutter build web --release --base-href /dart-labs/layerman/` → `Built build/web`，Wasm dry run 同样通过；没有修改 workflow。
- `main.dart.js`：2,585,116 B → 2,559,954 B；gzip（Python gzip level 9、mtime=0）：755,877 B → 752,579 B，减少 3,298 B（0.44%）。
- 当前会话无 chrome-devtools MCP，未执行真实浏览器冒烟或浏览器截图；没有操作用户标签页，也没有启动 HTTP 服务。上述尺寸结果来自 widget 实测，不代替真实浏览器验证。
- Windows `generated_plugin*` 已按要求恢复；原有包 README、中文 README 和 example/pubspec.lock 改动保持原样。未提交、推送或发布。

Both analyzers report no issues. All 1,146 package tests and 117 example tests pass; the release web build and Wasm dry run pass.
The gzip comparison uses identical Python gzip level 9 / mtime=0 settings. Browser smoke/screenshots remain unverified because chrome-devtools MCP is unavailable; no existing browser tabs were touched.
