# ffuzzy demo / ffuzzy 交互演示

Self-contained Flutter demo for the current package API. Uses a complete local copy of [demo_kit](lib/demo_kit/README.md); no extra dependencies.

当前包公开 API 的独立 Flutter 演示，完整复制统一 demo_kit，不新增依赖。版本 chip 来自包 pubspec 的同步常量，widget 测试会检查一致性。

- Live demo / 在线演示：[ffuzzy](https://icodejoo.github.io/dart-labs/ffuzzy/)
- Package / 包：[pub.dev](https://pub.dev/packages/ffuzzy)
- Source / 源码：[GitHub](https://github.com/icodejoo/dart-labs/tree/main/ffuzzy)
- API guide / 使用说明：[README](../README.md)

## Run / 运行

```sh
flutter pub get
flutter run -d chrome
flutter build web --release --base-href /dart-labs/ffuzzy/
```

`web/ffuzzy.mjs` is the matching engine from `../wasm/src/ffz.mjs`, loaded via `ffuzzyInit(webUrl: './ffuzzy.mjs')`. The deployment workflow syncs it before building. Serve the release under `/dart-labs/ffuzzy/`, not the server root.

`web/ffuzzy.mjs` 与包内 WASM 引擎配套，部署 workflow 会在构建前同步。发布产物需放在服务器的 `/dart-labs/ffuzzy/` 子路径，不能直接挂在根路径。

Open `?lang=zh` or `?lang=en`; otherwise browser language decides (Chinese → zh, others → en). The header switches language and theme. URL hashes such as `#/pages/lifecycle` restore the selected page. Layout uses a sidebar or drawer and responsive equal-height grid rows. Code starts collapsed and can be copied.

可用 `?lang=zh|en` 指定语言，默认跟随浏览器。页头可切换语言、亮暗和访问外链。hash 恢复当前页面；宽屏侧栏、窄屏抽屉；响应式等高网格；代码默认折叠并支持复制。

## Pages & audit / 页面与审计

| Current page / 当前页 | Previous content / 原内容 | Decision / 处理 |
| --- | --- | --- |
| Search / 搜索 | Search modes, Raws variants, async search mirrors | Merge duplicate pages. Each method offers hits/raws/async variants where available; retain all four SearchStrategy values and the valid suffix alias. / 合并重复页，保留全部四种策略和有效 suffix 别名。 |
| Corpus lifecycle / 语料生命周期 | Mutation, three async lifecycle cards | Retain nine mutations and asyncBuild/asyncAddAll/asyncDispose, with independent ownership and replay. / 保留九种变更与三个异步生命周期 API。 |
| Constructors & highlights / 构造与高亮 | Static ctors, Utilities | Merge three factories and UTF-16 utility; add real Unicode highlights and autoMaxDistance. / 合并工厂与工具页，补充实际 Unicode 高亮及自动距离阈值。 |
| Benchmarks / 压测 → Async build / 异步构建 | 3000-item build stopwatch inside the async tab | Preserve as an on-demand local measurement, no historical timing claims. / 保留为按需本机测量，不展示历史性能数据。 |

Removed the old fixed-three-column shell and numbered tab/card counts. Replaced the obsolete `packages/ffz/...` sample path and development-day CDN comments. Fixed input controllers recreated during build, futures recreated during rendering, missing error states and approximate-highlight surrogate handling. No public library API changed.

删除旧固定三列骨架和易过期的 Tab/卡片数量文案；更新旧 ffz 路径，移除开发当天 CDN 说明。修正每次构建创建控制器、渲染时重复发起 Future、错误状态缺失及近似匹配窗口截断代理对的问题。未修改 lib 公开 API。

Every interactive search, factory, mutation and async build/dispose card has Replay / 重放. Replay remounts its own body, restores input/variant/corpus and safely retires in-flight work. The static Unicode conversion card has no Replay. This package has no animation-specific demo to preserve.

所有交互搜索、工厂、变更和异步构建/释放卡片都带重放，恢复各自输入、变体及语料，并安全回收在途任务。静态 Unicode 转换卡不加重放；原示例没有独立动画页。

Web async yields a microtask but still runs WASM on the main thread; native searches use worker isolates. Approximate queries accept at most 64 codepoints and maxDistance 0–10. Pinyin keys must be supplied by the host. Native corpus-vs-Dart benchmarks remain at `../test/bench_native_test.dart`, outside web imports.

Web 异步让出微任务后仍在主线程运行 WASM；原生异步搜索使用 isolate。近似查询最多 64 码点，距离范围 0–10。拼音键由宿主提供。原生语料与 Dart 对照基准保留在包 test 中，不进入 Web 导入链。

## Verify / 验证

```sh
# From the package / 包目录
flutter analyze --no-fatal-infos
flutter analyze lib --no-fatal-infos
flutter test
# From example / example 目录
flutter analyze --no-fatal-infos
flutter test
flutter build web --release --base-href /dart-labs/ffuzzy/
```

Windows tests require `ffz.dll` on PATH (and in the package root for existing package tests). Build the existing C/FFI source list with MSVC, adding `/DFFZ_TRACK_ALLOC` for the package OOM regression test. The checked-in `build_test_dll.bat` omits this flag; no library source changes are needed.

Windows 测试需让 PATH 能找到 ffz.dll；包既有测试还需包根目录同名文件。用 MSVC 编译现有 C/FFI 源码列表，并加 `/DFFZ_TRACK_ALLOC` 以运行包内 OOM 回归测试。原 build_test_dll.bat 缺少该选项，无需修改库源码。

Widget tests cover language/URL precedence, navigation/history/theme, code copy, responsive grids, all four pages at 375×667 and 1440×900 in both languages, every search variant, mutation replay, async unmount and intact emoji highlights. Browser screenshots require a separate browser smoke run.

Widget 测试覆盖语言优先级、导航历史、主题、代码复制、网格、四页两种语言下的手机/桌面尺寸、所有搜索变体、变更重放、异步卸载及完整 emoji 高亮。浏览器截图仍需独立冒烟验证。

The package-wide analyzer currently reports 18 existing lint infos in scripts/tests; package lib and example can be checked independently with zero issues. Flutter may rewrite generated platform registrants on pub get; restore only those generated files after validation.

全包分析现有 scripts/test 共 18 条既存 lint info；包 lib 与 example 可独立检查为 0 问题。pub get 可能改写平台插件注册文件，验证后只还原这些自动生成文件。

## Latest local validation / 本次本机验证

Flutter 3.47.0 / Dart 3.13.0 (Windows): package tests **128 passed**, example tests **51 passed**. Example analyzer and package `lib` analyzer: **No issues found**. Full package analyzer: **0 errors, 0 warnings, 18 existing infos** in unchanged scripts/tests. Release web build with the deployment base path passed (including WASM dry run).

本次本机验证：包测试 128 个、example 测试 51 个通过；example 与包 lib 分析 0 问题；全包分析的 18 条既存 info 位于未改动的 scripts/test。部署路径 release 构建及 WASM dry run 通过。

| main.dart.js | Before / 迁移前 | After / 迁移后 |
| --- | ---: | ---: |
| Uncompressed / 原始字节 | 2,493,888 | 2,624,052 |
| gzip / 压缩字节 | 734,065 | 774,804 |

gzip measured with Python gzip level 9, mtime=0: +40,739 bytes (+5.55%). Logs and size JSON are local build artifacts in `build/`: `demo_test.log`, `package_test.log`, `demo_analyze.log`, `package_analyze.log`, `demo_web_build.log`, `demo_sizes.json`.

gzip 采用 Python level 9、mtime=0。测试、分析、构建与体积证据保存在 example/build 的上述文件中，不提交构建产物。chrome-devtools MCP 不可用，未执行浏览器冒烟和浏览器截图，未操作用户标签页。375×667 / 1440×900 的布局由真实 widget 测试验证。

Known issue outside this task: the native benchmark's gameId row compares a Dart gameId filter with a gameName-indexed corpus, so that row is not a valid parity/performance comparison. No benchmark or library source was changed.

范围外既存问题：原生基准 gameId 行将 Dart gameId 筛选与按 gameName 建索引的语料比较，该行不能用于等价性或性能结论；保留原文件，不改库或基准源码。
