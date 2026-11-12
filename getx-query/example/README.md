# getx_query demo / 交互演示

A self-contained bilingual demo of the current `getx_query` API. The header
version is read from the package's bundled `../pubspec.yaml` (currently 0.1.1).
All requests are local asynchronous tasks; no JSONPlaceholder account, HTTP
service or network connection is required. Writes last until Replay or navigation.

当前公开 API 的独立双语演示。页头版本从打包的父级 `pubspec.yaml` 读取，
不需要手工同步。请求使用本地异步任务，不依赖外部服务；提交与删除仅在内存生效，
重放或切换页面后恢复初始数据。未新增第三方依赖。

- [Online / 在线](https://icodejoo.github.io/dart-labs/getx-query/)
- [pub.dev](https://pub.dev/packages/getx_query)
- [Source / 源码](https://github.com/icodejoo/dart-labs/tree/main/getx-query)
- [Package README / 包说明](../README.md)
- [demo_kit contract / 骨架约定](lib/demo_kit/README.md)

## Pages / 页面

All five original API pages are retained and rewritten; none are merged or removed.
No benchmark or native-only entry existed in the original example.

保留并重做全部五类页面，没有重复页需要合并，也没有原生专用或开发基准页需要迁移。

| Hash | Page / 页面 | Interactive demos / 交互演示 | Replay / 重放 |
| --- | --- | --- | --- |
| `#/pages/query` | Queries / 查询 | Reactive key, enabled, refetch; error → retry / 响应式查询键、启停、重取；失败重试 | Both cards / 两张卡 |
| `#/pages/mutation` | Mutations / 数据变更 | Create/reset; controlled failure / 创建与重置；可控失败 | Both cards / 两张卡 |
| `#/pages/infinite` | Pagination / 分页加载 | Three finite pages, load more, end state / 三页累积、加载更多与末页 | Feed card / 分页卡 |
| `#/pages/queries` | Parallel queries / 并行查询 | `combine`, `useIsFetching`, invalidate both / 合并结果、在途计数与失效 | Query card / 查询卡 |
| `#/pages/viewmodel` | Lifecycle / 生命周期 | `GetBaseViewModel` delete → invalidate; `QueryScope` / 模型删除后刷新；作用域订阅 | Both cards / 两张卡 |

The eight dynamic cards all use DemoCard Replay to remount local state, including
controllers, input, observers and private caches. Static API notes have no Replay.
Each query explicitly uses `GcDuration.zero` for prompt cleanup on replay; cards
inject isolated clients with `NetworkMode.always` and no automatic retries.
These are demo policies, not QueryService's production defaults.

八张动态卡片都通过重挂载实现重放，覆盖控制器、输入、订阅与独立缓存；静态说明卡不加重放。
查询显式使用零延迟回收，方便观察并验证请求中途重放的释放行为；独立客户端执行本地任务，
关闭自动重试以便稳定演示首次失败。这些是 demo 的配置，不代表 QueryService 的默认策略。

## Controls & layout / 控制与布局

- Language / 语言：`?lang=zh|en` > browser language / 浏览器语言 > English。
  The `EN | 中文` header control updates the page immediately / 页头按钮即时切换。
- Navigation / 导航：sidebar at 900 px, drawer below / 900 像素起使用侧栏，否则抽屉。
  The URL hash survives refresh and supports browser history / hash 支持刷新恢复与前进后退。
- Theme / 主题：system light/dark with a manual toggle / 跟随系统，可手动切换。
- Grid / 网格：available-width breakpoints at 600/1000/1500 px, equal-height rows,
  1200 px content cap / 按可用宽度分列、同排等高、内容最大宽 1200 像素。
- Code / 代码：collapsed initially; expand and copy a full-width snippet / 默认折叠，展开后整行展示并可复制。

Example / 示例：`/dart-labs/getx-query/?lang=zh#/pages/infinite`。

## Audit notes / 过时项与修正

- Replaced external JSONPlaceholder requests and arbitrary remote post text with
  deterministic, translated local data. Its simulated deletes never removed
  remote posts; deletion now updates local storage before invalidating the query.
  / 移除外部请求及不可翻译的远程示例文本；旧模拟删除不会持久化，现改为本地删除后失效查询。
- The old ViewModel used unqualified `useQuery/useMutation`, resolving to global
  functions. Explicit `this.useQuery/this.useMutation` now ensures controller-owned
  tracking and disposal. / 旧写法会调用顶层函数，现显式调用模型成员以保证自动释放。
  Both package README quick-start samples now use the same explicit member calls.
  / 两份包 README 的快速上手也已改为显式调用成员方法。
- Current 0.1.1 foreground behavior is documented: every query follows its own
  `refetchOnResume` policy; no client-wide invalidation on resume.
  / 使用 0.1.1 的逐查询恢复前台策略，不再宣传全客户端批量失效的旧行为。
- Replaced the custom shell and English-only nested Scaffolds with the copied
  demo_kit. Placeholder Flutter web metadata and this starter README are updated.
  / 删除旧自定义导航壳，替换全英文独立 Scaffold、默认网页元信息和入门模板说明。
- The entire countman demo_kit directory was copied locally. Its Replay label was
  adjusted to 重放; no general kit bug was found. / 完整复制骨架，中文 Replay 文案改为“重放”，
  本轮未发现骨架通用 bug；未改动 countman 或其他 worktree。

## Run & verify / 运行与验证

Use Flutter 3.47.0 (Dart 3.13.0). From the package directory / 在包目录执行：

```sh
flutter analyze --no-fatal-infos
flutter test
cd example
flutter analyze --no-fatal-infos
flutter test
flutter run -d chrome
flutter build web --release --base-href /dart-labs/getx-query/
```

The build path matches `.github/workflows/deploy-getx-query.yml`; no workflow
change is required. The parent pubspec is an asset, and the workflow already
watches changes to it. / 构建路径与现有 workflow 一致，无需修改；父级 pubspec
已在 workflow 触发路径中，版本变化会重新构建。

Tests cover the kit's locale precedence, hash/history, theme, responsive columns,
copying, detail dialogs and remounting; application tests cover the five API pages,
eight dynamic cards, writes, failures, counters, unmounting during requests,
external link targets and bundled version. All pages run through English/Chinese,
light/dark switching and code expansion at 375×667 and 1440×900.

测试覆盖骨架语言优先级、导航历史、主题、网格、复制、详情弹窗和重挂载；页面测试覆盖
五类 API、八张动态卡、提交/失败/计数、请求中途卸载、外链与版本，并在两种目标尺寸
检查中英、主题切换和代码展开。Widget 布局测试不代替真实浏览器截图与目视验收。

For a manual subpath smoke test, put `build/web` under
`<temporary root>/dart-labs/getx-query/`, run `python -m http.server` in that root,
then open a new tab at `/dart-labs/getx-query/`. Stop the server after testing.

手动冒烟时，将产物复制到临时根目录的 `dart-labs/getx-query/`，在临时根目录启动
`python -m http.server`，用新标签页访问子路径；完成后关闭自己启动的服务。
不要复用或改动用户原有标签页。

## Verification snapshot / 本轮验证（2026-11-12）

- Flutter 3.47.0 / Dart 3.13.0; package and example analyze: **0 issues**.
- Package tests: **92 passed**; example tests: **27 passed** (13 kit + 14 app).
- Migration: `getx_query 0.2.0` uses `flutter_query ^0.11.1`; plain-value wrappers
  remain compatible, while raw options use `Seed` / `SeedUpdatedAt` / `Placeholder`.
- Release web build with the workflow's base href: **passed**.
- `main.dart.js`: 2,647,267 → 2,673,044 bytes; gzip (level 9):
  778,878 → 787,533 bytes (**+1.11%**).
- chrome-devtools MCP was unavailable; real-browser smoke testing and screenshots
  were not performed. Existing user tabs were untouched. / 未完成真实浏览器冒烟及截图，未操作用户已有标签页。
- Local verification logs / 本地验证日志：`build/analyze-example.log`,
  `build/test-example.log`, `build/web-release.log`; package logs are in `../build/`.
