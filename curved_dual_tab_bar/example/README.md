# curved_dual_tab_bar example

[中文演示](https://icodejoo.github.io/dart-labs/curved_dual_tab_bar/?lang=zh) ·
[English demo](https://icodejoo.github.io/dart-labs/curved_dual_tab_bar/?lang=en) ·
[pub.dev](https://pub.dev/packages/curved_dual_tab_bar) ·
[Source](https://github.com/icodejoo/dart-labs/tree/main/curved_dual_tab_bar) ·
[README](https://github.com/icodejoo/dart-labs/blob/main/curved_dual_tab_bar/README.md)

当前包版本 **0.2.4**；页头版本由测试与 `../pubspec.yaml` 校验。
Current package version: **0.2.4**; a test checks the header against `../pubspec.yaml`.

## 使用 / Usage

语言优先级为 `?lang=zh|en` → 浏览器语言 → 英语，页头可切换中英与亮暗。
导航保存到 `#/pages/<id>`，宽屏为侧栏，窄屏为抽屉。
Language priority is URL → browser locale → English. Header controls switch
language and theme; navigation restores `#/pages/<id>` on refresh.

复制了 countman 的整个自包含 [demo_kit](lib/demo_kit/README.md)，没有跨项目依赖或新增第三方依赖。
The full standalone countman demo_kit is copied locally, with no cross-project
imports or new third-party dependencies.

## 页面审计 / Page audit

旧 example 只有一个包含 7 个预览的长列表页，没有重复页、废弃 API、旧性能数据或基准入口。
所有原预览均保留；移除模板说明和缺少双语的集中状态摘要，改为卡片内的反馈。
The original example had one long page with seven previews, no duplicate or
benchmark pages, no deprecated API calls and no historical performance claims.
All previews are retained; template prose and the combined monolingual status
line are replaced by per-card feedback.

| 页面 / Page | 内容 / Contents | 原页面对应 / Original mapping |
| --- | --- | --- |
| `styles` — 配色与曲线 / Colors & curves | 主题默认、充值提现三层背景、渐变填充 / Theme, layered payment header, gradient fill | 保留原 3 个配色预览 / Original three color previews |
| `styles` — 曲线与描边 / Curve & borders | 纯色 S 曲线、独立轮廓描边、渐变圆头发光分割线与控制点偏移 / Solid curve, outlines, gradient divider with glow and offsets | 保留原 3 个曲线预览 / Original three curve previews |
| `controllers` — 控制器与滑动 / Controllers & swipes | 原生 TabBar + CurvedTabBackground + TabBarView | 保留并补齐实际滑动联动 / Existing native preview, now with swipeable content |
| `controllers` | DefaultTabController + CurvedDualTabBar + TabBarView | 新增当前共享控制器用法，省略 selectedIndex/onChanged / Added current controller-only API |
| `controllers` | Scaffold.appBar + CurvedDualTabBar | 新增 PreferredSizeWidget 与默认顶部 SafeArea 用法 / Added direct appBar and top SafeArea support |

全部 **9 张卡片**有“重放 / Replay”：状态和控制器都位于重新挂载边界内，
重新开始一次左到右切换，同时重置滑动位置；不影响其他卡片。
减少动态效果开启时不自动切换。
All nine cards replay by remounting their local state/controllers and resetting
swipe position. Other cards keep their state. Reduced motion disables autoplay.

当前文档与库的注意点（仅记录，不修改包文档或公开 API）：包 README 只解释了内部控制器，
没有覆盖共享控制器；`preferredSize` 注释仍写需要外部 SafeArea，而 0.2.4 已默认处理顶部安全区。
The package README omits shared-controller usage. The library's `preferredSize`
comment still asks callers for SafeArea, although 0.2.4 handles the top inset by default.

本地 demo_kit 副本修正长包名页头挤压，以及 compact 密度导致的重放按钮触控区域缩小；
中文按钮统一为“重放”。网格、全宽折叠代码、详情弹窗和链接降级沿用试点。
Local kit fixes keep long project names within the header and preserve replay
touch targets. The Chinese replay label is “重放”.

## 运行与验证 / Run and validate

在包目录运行前两条，在 example 目录运行后面三条：
Run the first two commands in the package directory, then the remaining commands in example:

```sh
flutter analyze --no-fatal-infos
flutter test
cd example
flutter analyze --no-fatal-infos
flutter test
flutter build web --release --base-href /dart-labs/curved_dual_tab_bar/
```

部署路径与 `.github/workflows/deploy-curved_dual_tab_bar.yml` 一致，无需修改 workflow。
The base path matches the existing deployment workflow; no workflow change is needed.

测试覆盖语言优先级、hash 与历史导航、复制、主题、9 张卡片的点击/滑动/逐卡重放，
以及两种语言、亮暗主题下 360–1600 宽度的布局；包含 375×667 和 1440×900。
Tests cover locale priority, hash/history navigation, copy actions, themes,
individual replay and tab/swipe synchronization, with bilingual light/dark
layouts from 360 to 1600px including 375×667 and 1440×900.

本次环境没有 chrome-devtools MCP，未运行浏览器冒烟或获取浏览器截图；未操作已有标签页。
Chrome DevTools MCP is unavailable in this session, so browser smoke tests and
browser screenshots were not performed; existing tabs were left untouched.


## 本次验证记录 / Verification record

Flutter 3.47.0，2026-11-12；包和 example 分别执行分析与测试。
Flutter 3.47.0, 2026-11-12; analysis and tests ran in both directories.

| 检查 / Check | 结果 / Result |
| --- | --- |
| 包 / Package `flutter analyze --no-fatal-infos` | No issues found! |
| example `flutter analyze --no-fatal-infos` | No issues found! |
| 包 / Package `flutter test --reporter expanded` | 5 tests passed |
| example `flutter test --reporter expanded` | 23 tests passed |
| Release web build with the deployment base path | Built build/web; Wasm dry run succeeded |

同一 SDK 与构建参数，gzip 使用 Python 标准库、默认压缩级别 9、mtime=0。
Same SDK/build command; gzip uses Python's default level 9 with mtime=0.

| main.dart.js（字节 / bytes） | 迁移前 / Before | 迁移后 / After |
| --- | ---: | ---: |
| 原始 / Raw | 2055552 | 2272639 |
| gzip | 608143 | 671007 |

未新增依赖；锁文件仅将本包 path 依赖的版本从 0.2.1 同步为 0.2.4。
没有 generated plugin 文件变动，无需还原。
No dependencies were added. The lockfile only synchronizes the local package
version from 0.2.1 to 0.2.4. No generated plugin files changed.
