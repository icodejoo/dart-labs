# dioman demo / 双语演示

Self-contained Flutter demo of the current dioman request pipeline. No third-party
dependencies were added. The complete `lib/demo_kit/` directory was copied from
the countman pilot; it has no cross-project imports.

当前请求管线的自包含 Flutter 演示。未新增第三方依赖；`lib/demo_kit/` 整目录复制自
countman 试点，没有跨项目导入。

- Language / 语言：`?lang=zh|en` > browser language / 浏览器语言 > English。
  The header switch updates existing logs without restarting requests.
  页头切换语言时，已有日志同步翻译，不重启请求。
- Navigation / 导航：`#/pages/requests`、`policies`、`lifecycle`、`pipeline`。
  Wide screens use a sidebar; phones use a drawer. Refresh and history restore
  the selected page. 宽屏侧栏、窄屏抽屉，支持刷新和历史恢复。
- Theme / 主题：system light/dark with a header toggle / 默认跟随系统，可手动切换。
- Version / 版本：`lib/main.dart` 的 `demoVersion` 来自当前包 `../pubspec.yaml`，
  widget 测试校验完全一致；升级包时同步该值。
- Transport / 传输：Dio memory adapter, no public service or credentials needed.
  Dioman runs its real pipeline; inline Mock is used only in the Mock card.
  使用内存 Dio adapter 和真实 Dioman 管线，不需要公网或真实凭证；仅 Mock 卡片使用内联路由。
- Layout / 布局：responsive equal-height grid, compact scrollable logs, full-width
  collapsed copyable code / 响应式等高网格、紧凑滚动日志、整行折叠复制代码。

## Inventory / 页面与过时项审计

The original example had one scrolling page with 17 scenarios. The replacement
has four pages and 18 cards; capabilities are retained, with one duplicate merged
and two current APIs added. 原单页共 17 个场景；现为四页 18 张卡片，保留能力、合并一项重复、
新增两项当前 API。

| Page / 页面 | Cards / 场景 | Audit / 审计处理 |
| --- | --- | --- |
| Requests & results / 请求与结果 | Path rewrite、Query filter、Inline mock、HTTP & business result、Decode & raw | 保留路径三种占位符、过滤和三种 Mock 方法；改正 `status` 为 HTTP、业务码为 `code`、内核失败用 `failureOf`；新增成功后 decode 和按需 raw。 |
| Request policies / 请求策略 | Cache & canonical keys、Concurrent sharing、Retry attempts、401 token refresh | 合并 Request Key 与 Cache，展示参数乱序命中、改值重发和 clear；显式按调用开启 Cache/Share；删除“近零延迟”宣传；区分演示自定义等待与 Retry 当前默认 300ms 指数退避、10s 上限、Retry-After 60s 上限。 |
| Request lifecycle / 请求生命周期 | Shared loading、Cancel all、Offline queue、Whole-request deadline | loading 是一次 true→false 显示周期，活跃数通过 `activeCount` 观察，并非三个显示回调；保留取消/离线，新增调用预算覆盖默认 deadline、timeout/deadline 及默认预算下成功的对照。 |
| Pipeline & diagnostics / 管线与诊断 | Environment setup、Timeout configuration、Circuit breaker、Final notification、Custom trace & debug | 保留五项；Envs 仅首条匹配且只在 setup 应用；Timeout 仅展示配置，不声称证明真实网络超时；HTTP/业务失败与内核失败分别呈现。 |

Removed / 删除：旧 `_App`、`_HomePage`、定制暗色长列表和旧卡片/日志 UI；被统一骨架替换。
没有删除功能入口。包内 `benchmark/` 不属于 example 页面，原样保留；没有把原生压测导入 web。

Native CLI entries / 原生入口保持原样：

```sh
# From the dioman package directory / 在 dioman 包目录运行
dart run example/dioman_example.dart
dart run example/real_run.dart # Public network required / 需要公网
```

## Replay & resources / 重放与资源

All 17 request/state scenarios use the DemoCard Replay / 重放 control. Only the
static Environment setup card has no replay. Requests start on mounting a card;
Replay remounts only that card with fresh clients, counters, tokens and logs.
Language/theme changes preserve the current run. Leaving or replaying cancels
old requests, clears demo timers, awaits client disposal, closes owned Dio engines
and releases the offline connectivity stream. Late results cannot enter a new log.

17 个请求或状态演进场景均使用 DemoCard 的“重放/Replay”；静态环境配置不加重放。
挂载时运行，重放仅重新挂载当前卡片，重置客户端、计数、凭证和日志。
语言/主题切换保留当前轮次。离页或重放取消旧请求，清理计时器，等待客户端释放并关闭 Dio；
离线连通流也会关闭，迟到输出不会污染新日志。

Code blocks are current API snippets assuming an already configured `api` and
the plugins noted in comments. See `lib/scenarios.dart` for the complete runnable
implementations. Always `await api.dispose()` and close the Dio engine you own.

代码为当前 API 调用片段，假设已有 `api` 和注释所列插件；完整可运行实现见
`lib/scenarios.dart`。结束后等待 `api.dispose()` 并关闭自己持有的 Dio。

## Validation / 验证

Flutter 3.47.0 / Dart 3.13.0; package language floor remains Dart 3.5.
原语言下限未改。试点复制测试中的重复 `_` 参数改为具名参数以兼容该下限；骨架仅将
Replay 中文提示由“重播”改为“重放”，未修改其他 worktree。

```sh
# Package / 包目录
flutter analyze --no-fatal-infos
flutter test --reporter expanded
dart test --reporter expanded

# Example / example 目录
flutter analyze --no-fatal-infos
flutter test --reporter expanded
flutter build web --release --base-href /dart-labs/dioman/
```

Package and example analysis: zero issues. All 47 example widget tests pass and cover all 18
scenario outcomes, 17 replays, rapid replay/disposal, language/theme, links,
clipboard, navigation/history, equal rows and widths 360–1600, including 375×667
and 1440×900 in both languages. Pure-Dart package `dart test`: 5708 passed.

包与 example 分析均为 0 问题。example widget 测试覆盖全部场景结果、17 个重放、快速重放/离页、
双语/主题、链接、复制、导航/历史、等高网格和 360–1600 宽度；含 375×667 与 1440×900 双语布局。
包 `dart test` 5708 项全过。

Release build / 发布构建：上述 base href 命令通过，Wasm dry run 通过。
gzip 使用 Python `gzip.compress(data, mtime=0)` 的默认压缩级别，两次使用同一 Flutter SDK。

| main.dart.js | Before / 迁移前 | After / 迁移后 | Change / 变化 |
| --- | ---: | ---: | ---: |
| Uncompressed / 原始字节 | 2,210,457 B | 2,422,806 B | +212,349 B |
| gzip | 653,269 B | 718,313 B | +65,044 B / +9.96% |

Known runner limitation / 已知运行器限制：包 `flutter test` 实跑为 5704 通过、4 超时。
四个既有测试通过 `Platform.resolvedExecutable` 启动 `run`/`analyze`，Flutter runner 下实际
启动的是 `flutter_tester.exe`，不是 Dart CLI。失败项为 `example_integration_test`、
`share_prepare_probe_integration_test`、`documentation_examples_integration_test` 和
`public_exports_test`。没有修改包测试或 lib；用包现有文档指定的 `dart test` 已全部验证通过。

Browser smoke was skipped because chrome-devtools MCP was unavailable; no existing
browser tabs were touched. Widget layout checks are not browser screenshots.
chrome-devtools MCP 不可用，浏览器冒烟与截图未做；没有操作用户已有标签页。
widget 布局验证不冒充浏览器截图。

Deployment / 部署：本 worktree 没有 `.github/`，已只读核对 main 分支
`.github/workflows/deploy-dioman.yml`，构建参数正是上述 base href，workflow 无需修改。
若未来单独改 web 配置，现有 workflow 的 paths 不包含 `example/web/**`，需手动运行或补 paths；
本次 lib 改动会触发现有部署规则。
