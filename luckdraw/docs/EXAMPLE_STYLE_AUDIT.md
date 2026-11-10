# example 样式审计与美化（STYLE）

## 参考来源与限制

审计对象为首页及十个玩法页。先核对旧页面、公开配置 API 和 11 个集成测试文件，再调整示例；不修改包的 `lib/`、运动算法和公开导出，不增加依赖、网络图或打包字体。

- [官方站](https://100px.net/)可通过云端网页抓取；[JS 使用示例](https://100px.net/usage/js.html)明确给出蓝色外圈 `#617df2`、交替扇区 `#e9e8fe / #b8c5f2`、六扇区及百分比文字定位。
- [上游 README](https://github.com/buuing/lucky-canvas)确认三玩法及独立配置的定位。当前抓取结果主要为文本，不把 README 当作已获得的逐像素游戏截图。
- 本机受限域名清单未列出 100px.net。尝试指定独立用户目录的无头 Chrome 截图时，执行被自动审批策略拒绝；没有浏览器截图，也没有启动或关闭用户的 Chrome。`/api/wheel.html`、`/api/grid.html`、`/api/slot.html` 抓取不可用，不视为已验证内容。
- 本机上游克隆 `lc/src/packages/react/example/react18.0.html` 提供分层圆形按钮；`packages/core/examples/grid.html` 提供格子布局与背景配置；`packages/core/examples/slot.html` 提供两层外框、圆角奖品、图文格子及行列间距。`website/src` 在当前克隆中主要是介绍站组件，并无完整的三玩法设计稿。

因此这里的“对齐”指配色、构图和配置能力的对齐，**不宣称与线上全部演示逐像素一致**。程序化礼盒、宝石、星章为本批自行绘制，没有复制上游奖品图片。仓库内只保存自己的 Flutter 渲染图，没有上游截图或图片素材。

## 截图口径

`test/example_pages_test.dart` 在无设备环境渲染；逻辑尺寸 390×844、DPR 3，截图原始尺寸 1170×2532，报告副本缩小为 390×844 PNG。SDK Roboto 由原有全局配置加载；MaterialIcons 与本机中文字体仅在本测试中补充加载，不打包、复制或分发字体。为兼容缺省／固定字体族的 Canvas，中文字体在测试内另注册为字体别名；因此不把截图中的中文字形当作 Roboto 字形或产品字体承诺。美化前使用原页面源码快照，临时副本仅补字体选择，不改颜色、几何和布局；前后使用相同视口，浅深主题均生成。原始大图只保存在仓库外的审计 scratchpad，整个交付截图目录小于 3 MB。图像仅为审计产物，不是跨平台像素 golden 门禁；布局与控件使用明确 widget 断言。

以下每页均可查看浅色前后与美化后的深色画面；同目录另有美化前深色图。首页是可滚动页面，截图展示首屏。

## 逐页审计

### 首页

[之前](example_audit/before/home-light.png) · [之后](example_audit/after/home-light.png) · [深色](example_audit/after/home-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| 页面结构 | 玩法清楚、内容有视觉重心 | 默认 ListTile 列表 | 缺少入口吸引力和玩法介绍 | 蓝紫渐变主视觉，图标、标题、说明组成卡片网格 |
| 导航 | 三玩法分类 | 全部入口混排 | 不易区分新增玩法和技术示例 | 上游三玩法／新增玩法／迁移与叠加三组；保留 README 和调用方的额外路由 |
| 深浅色 | 上游未取得完整深色证据 | 仅浅色默认主题 | 没有夜间主题 | 跟随系统切换墨蓝表面与浅紫页面 |

### 转盘

[之前](example_audit/before/wheel-light.png) · [之后](example_audit/after/wheel-light.png) · [深色](example_audit/after/wheel-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| 外圈 | 蓝圈、分层构图，可配置装饰 | 无 blocks | 缺少机器质感 | 三层 blocks：蓝紫渐变、金边、暖白内沿；24 颗静态灯珠 |
| 扇区 | 六等分、浅紫和蓝紫交替 | 两个半圆、默认文字 | 大片空白 | 六扇区交替色，文字外缘定位，礼盒／宝石／星章矢量图标 |
| 按钮与指针 | 同心圆按钮、中心指针 | 单色圆与三角 | 主次不清 | 金色底托与渐变中心按钮，保留原生指针和命中 |
| 结果 | 可配置业务回调 | 裸 Text | 缺少反馈层次 | 结果摘要卡、liveRegion、点击查看结果底部弹层 |

### 九宫格

[之前](example_audit/before/grid-light.png) · [之后](example_audit/after/grid-light.png) · [深色](example_audit/after/grid-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| 布局 | 明确格子、边距与背景配置 | 无外框、默认格子 | 格子边界和视觉密度弱 | 蓝紫圆角外框，8px 格距、12px 格子圆角 |
| 图文 | 奖品内容与中心按钮分离 | A–H 纯文字 | 奖品不具象 | 保留字母标识，增加中文短名与原创矢量奖品 |
| 阴影与激活 | 可配置背景、高亮和圆角 | 单一杏色高亮 | 缺少立体层次 | 3px 下沉阴影；金色激活底、白描边和柔光；中心金色按钮 |

### 老虎机

[之前](example_audit/before/slot-light.png) · [之后](example_audit/after/slot-light.png) · [深色](example_audit/after/slot-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| 外框与窗口 | 源码有多层 blocks、圆角格子 | 无外框、三列文字 | 像普通文本栏 | 蓝紫／金色／墨蓝三层外框，暖白窗口 |
| 列分隔与奖品 | 行列间距、图片奖品 | A/B/C 纯文字 | 滚动缺乏辨识度 | 5px 列分隔、8px 行距，三个矢量奖品与短名 |
| 控制语义 | 多列滚动和指定停点 | 三轮独立目标 | 功能完整、观感弱 | 保留 `[0,1,2]` 服务端目标与反向第三轮，只调整视觉 |

### 拉霸机

[之前](example_audit/before/lever-light.png) · [之后](example_audit/after/lever-light.png) · [深色](example_audit/after/lever-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| 整体 | 上游老虎机构图；无独立拉杆玩法 | 默认老虎机和手柄 | 没有与老虎机共享的视觉体系 | 共用窗口、矢量奖品与蓝紫外框；手柄仍由公开组件绘制 |
| 交互 | 不适用 | 拖动、错峰停轮、onPull | 样式调整必须保护命中 | 不叠加拦截手势的装饰；保留 0/300/600ms 错峰与回调 |

### 扭蛋机

[之前](example_audit/before/capsule-light.png) · [之后](example_audit/after/capsule-light.png) · [深色](example_audit/after/capsule-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| 机身 | 上游无该玩法，沿用三玩法视觉语言 | 默认红机身、两种胶囊 | 与其余页面不一致 | 蓝紫渐变机身、金色旋钮、淡蓝球罩、四种胶囊配色 |
| 结果 | 统一业务反馈 | 开蛋后裸文字 | 奖品卡缺少统一配色 | 暖白开蛋卡与深墨文字，保留旋钮和掉落过程 |

### 数字转盘

[之前](example_audit/before/number_wheel-light.png) · [之后](example_audit/after/number_wheel-light.png) · [深色](example_audit/after/number_wheel-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| 圆盘与轨道 | 上游无小球数字玩法 | 默认棕金、红黑号码 | 与主转盘风格脱节 | 金白外圈、墨蓝轨道、蓝紫号码格与渐变中心 |
| 号码与结果 | 统一对比度与反馈 | 默认号码和文本 | 风格不统一 | 保留 0–12 和目标号码 8；金白标签环使用深墨数字与显式字体，暖白小球，统一结果卡 |

### 抽签

[之前](example_audit/before/lots-light.png) · [之后](example_audit/after/lots-light.png) · [深色](example_audit/after/lots-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| 签筒与签文 | 上游无抽签玩法 | 默认红木签筒 | 与其他页面割裂 | 蓝紫筒身、金色签条、暖白签文卡、深墨文字 |
| 布局和控件 | 同一舞台和按钮语言 | 裸画布 | 缺少内容层级 | 统一描述、舞台、控制区和结果卡；保留签文与抽取目标 |

### 大乐透

[之前](example_audit/before/lotto-light.png) · [之后](example_audit/after/lotto-light.png) · [深色](example_audit/after/lotto-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| 机身和结果槽 | 上游无摇奖玩法 | 默认浅灰、黄色开始按钮 | 与蓝紫页面不一致 | 淡紫滚筒、蓝色外沿、蓝紫结果槽、金色 GO 按钮；控制面板保留中文“开始” |
| 彩球语义 | 独立玩法信息必须可辨 | 红色前区／蓝色后区 | 色彩不同具有业务含义 | 有意保留红蓝号码池与原始七球顺序，框体和页面统一 |

### compat 迁移

[之前](example_audit/before/compat-light.png) · [之后](example_audit/after/compat-light.png) · [深色](example_audit/after/compat-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| JSON 展示效果 | 官方六扇区与蓝紫交替色 | 两扇区、无外圈 | 与类型化转盘外观相差大 | JSON 添加 blocks、六扇区、同心按钮、文字位置和配色 |
| 迁移边界 | 上游 JSON 配置能力 | strictUpstream 转换 | 不应混入 Dart 绘图回调冒充迁移 | 保留严格转换与告警；不向 JSON 注入矢量 painter，奖品有意只用文字 |

### Widget 叠加层

[之前](example_audit/before/overlay-light.png) · [之后](example_audit/after/overlay-light.png) · [深色](example_audit/after/overlay-dark.png)

| 项目 | 上游参照 | 我们之前 | 差距 | 本批改法 |
| --- | --- | --- | --- | --- |
| 舞台与奖品 | 沿用上游转盘构图；叠加为 Flutter 扩展 | 两扇区和大号紫色礼物 | 图标与背景没有统一主题 | 共用美化转盘与灯珠；叠加图标缩为 20px 并统一深蓝色 |
| 动画和资源 | 无可直接等同的上游实现 | 每个礼物独立旋转 | 必须防止离页 ticker 泄漏 | 保留独立动画与 IgnorePointer；离页测试检查零待执行动画回调 |

## 共同设计决策与对齐结论

- 主视觉对齐官方使用示例的蓝紫配色、交替奖品区和分层按钮；格子与滚轮对齐“外框／窗口／奖品图文”的结构。没有取得完整浏览器参考帧，灯珠数量、原创插画、阴影深度和页面容器属于本批设计，不能当作上游精确参数。
- 页面使用 8/12/16/24px 间距，18px 卡片圆角、28px 舞台圆角；页面说明、玩法舞台、阶段与控制区、结果区按同一顺序排列。深色使用墨蓝表面，玩法窗口仍保留暖白和高对比文字，避免简单反色破坏奖品辨识。
- 主按钮用深蓝与白字，浅色奖品用深墨文字。按 sRGB 相对亮度计算，深蓝／白为 6.05:1，深墨／暖白为 11.82:1，深墨／蓝紫为 7.15:1，深墨／金色为 8.86:1，深色卡片／蓝紫为 8.36:1；这些基础正文组合超过 4.5:1。转盘中心按钮有意比官方基础蓝更深，渐变采用深蓝至深墨，使白字覆盖范围的对比度至少为 6.05:1。金色仅作为装饰／高亮及深墨文字的底色，不用金色小字承载信息。这不是对所有系统字体和全部状态的自动无障碍认证。
- 新增重置按钮只调用公开 controller.reset 并清空页面结果；开始、服务端返回、指定停点、onStart、onEnd、onBallDrawn 与 onPull 保留。开始／服务端返回／result 的 Key 保留，所有既有集成测试名与断言语义保留。
- 结果先以卡片稳定展示，点击展开底部弹层。采用主动展开以免自动弹层覆盖既有触控流程；语义 liveRegion 播报状态变化。不新增会影响 idle 稳定性和测试等待的装饰动画。
- Material 图标来自 Flutter SDK，Canvas 奖品来自本批矢量绘制。零新增图片／字体资源、零网络素材、零新增依赖。未修改包本体。

## 验证记录

全部副本验证在 `C:\lds\luckdraw` 执行，最终结果如下。原始日志及原始 DPR 3 图片保存在仓库外 `C:\lds\style_report`，不复制构建产物回仓库。

| 命令／范围 | 实际输出摘要 |
| --- | --- |
| `flutter analyze --no-pub`（主包） | No issues found，21.4s，0 issue |
| `flutter analyze --no-pub`（example 目录） | No issues found，5.1s，0 issue |
| `dart format lib test tool example/lib`，随后同目录 `--output=none --set-exit-if-changed` | Formatted 350 files (0 changed)，两条均通过 |
| 全包组 1：`test/core test/testing test/tool` | 574 个通过；JSON done.success=true；124858ms |
| 全包组 2：`test/wheel test/grid test/slot test/compat` | 265 个通过；JSON done.success=true；129602ms |
| 全包组 3：`test/capsule test/number_wheel test/lots test/lotto test/parity test/example_pages_test.dart` | 186 个通过；JSON done.success=true；282130ms，未超过 5 分钟 |
| 最终页面复核：`flutter test test/example_pages_test.dart --no-pub --concurrency=1 --coverage --coverage-path=coverage/style-ui.lcov --reporter=json` | 12/12 通过；含两主题、关键 Key、无溢出、无兼容告警、结果弹层及重置；22630ms |
| `dart run tool/coverage.dart --min=100 --lcov=coverage/style.lcov` | TOTAL: 6677/6677 (100.00%)；PASS；没有新增豁免 |
| `dart run tool/check_imports.dart` | PASS: 144 lib files；IMP-R1…R12 通过 |
| `dart run tool/check_acceptance.dart` | PASS: 1416 references resolve；1046 registered tests all mapped |
| `dart run tool/check_acceptance.dart --from-json C:\lds\style_report\all.ndjson` | 同为 1416 引用、1046 注册测试全部有效；真实 root suite 用最后一次页面复核替换旧页面 suite |
| 截图体积与尺寸 | 45 张 PNG、1,262,694 字节（1.20 MiB）；390×844 报告预览，256 色调色板压缩；原始 1170×2532 图片仍在 scratchpad |

三组全包命令均使用 `flutter test <上述路径> --no-pub --concurrency=1 --coverage --coverage-path=coverage/style-<组号>.lcov --reporter=json`。合并覆盖率只累计真实 DA 命中；没有覆盖包本体文件。全包唯一用例共 **1025 个通过**，最终另复核新增的 12 个页面用例；1046 是静态注册总数，包含独立的集成／bench 工程，不能当作本轮全包运行数或真机通过数。

Windows 集成逐文件运行 `dart run tool/run_integration.dart --device=windows --repeat=1 --file=<文件名>`，每次构建前检查 FreePhysicalMemory ≥4GB，设置 `LUCKDRAW_TEST_WINDOW=1`；没有执行独立 flutter build，也没有使用手机／adb。既有 11 个集成测试文件及测试名均未修改。

| 文件 | 结果 | 构建＋执行毫秒 |
| --- | --- | --- |
| capsule_flow_test.dart | 1/1 | 213550 |
| grid_flow_test.dart | 1/1 | 104103 |
| lever_flow_test.dart | 1/1 | 30771 |
| lifecycle_test.dart | 1/1 | 48894 |
| lots_flow_test.dart | 1/1 | 151677 |
| lotto_flow_test.dart | 1/1 | 141595 |
| number_wheel_flow_test.dart | 1/1 | 87318 |
| resize_test.dart | 1/1，含 280px 窗口与非前台断言 | 57617 |
| route_test.dart | 1/1，含进出页面 20 次、Ticker 释放断言 | 90402 |
| slot_flow_test.dart | 1/1 | 28941 |
| wheel_flow_test.dart | 1/1 | 30834 |

总计 **11/11 文件通过，一轮，985702ms**。最后的纯视觉修正（中心按钮色阶、JSON 字体字段、GO 文案）由最终页面复核覆盖，没有重复整套 Windows 三轮运行。

真实仓库 `E:\workspaces\dart-labs\luckdraw` 已回拷并完成定点验证：`dart format --output=none --set-exit-if-changed example/lib/main.dart example/lib/demo_shell.dart example/lib/pages example/lib/theme test/example_pages_test.dart` 输出 **Formatted 16 files (0 changed)**；`flutter test test/example_pages_test.dart --no-pub --concurrency=1 --reporter=expanded` 输出 **12/12 All tests passed（约 7 秒测试时间）**；`check_imports` 为 **144 lib files PASS**，`check_acceptance` 为 **1416 引用／1046 注册测试 PASS**。没有其它并行路径导致的失败。

回拷前核对既有页面哈希，没有发现并行冲突；main.dart 重新读取后仅定点合并主题、导入与首页构建块，原有 11 个路由全部保留；矩阵重新读取后一次性追加 EXM-01–EXM-12。未修改任何 DEV 阴影页面或集成夹具。最后按命令行检查，未发现本副本遗留的 dart／flutter_tester／example 进程。没有 git add、commit 或 push；最终 `git log --oneline -2` 仍为 `443589a3`、`f0b64ae1`。

## 交付文件清单

| 操作 | 路径 |
| --- | --- |
| 定点合并主题与首页，不覆盖路由表 | `example/lib/main.dart` |
| 修改公共页面骨架、按钮、结果卡与重置入口 | `example/lib/demo_shell.dart` |
| 新增首页网格 | `example/lib/pages/home_page.dart` |
| 修改转盘配置 | `example/lib/pages/wheel_page.dart` |
| 修改九宫格配置 | `example/lib/pages/grid_page.dart` |
| 修改老虎机配置 | `example/lib/pages/slot_page.dart` |
| 修改拉霸机控制区接入 | `example/lib/pages/lever_page.dart` |
| 修改扭蛋机配置 | `example/lib/pages/capsule_page.dart` |
| 修改数字转盘配置 | `example/lib/pages/number_wheel_page.dart` |
| 修改抽签配置 | `example/lib/pages/lots_page.dart` |
| 修改大乐透配置 | `example/lib/pages/lotto_page.dart` |
| 修改 JSON 示例 | `example/lib/pages/compat_page.dart` |
| 修改叠加图标与控制区接入 | `example/lib/pages/overlay_page.dart` |
| 新增共享主题、配色、卡片与结果弹层 | `example/lib/theme/demo_theme.dart` |
| 新增原创矢量奖品与静态灯珠 | `example/lib/theme/prize_art.dart` |
| 新增 12 个测试 | `test/example_pages_test.dart` |
| 只追加 EXM-01–EXM-12，状态已落地 | `test/ACCEPTANCE.md` |
| 新增本审计文档 | `docs/EXAMPLE_STYLE_AUDIT.md` |
| 新增自己的前后浅深色画面 | `docs/example_audit/{before,after}/{home,wheel,grid,slot,lever,capsule,number_wheel,lots,lotto,compat,overlay}-{light,dark}.png` |
| 新增结果弹层画面 | `docs/example_audit/after/result-sheet-light.png` |

上述截图路径按花括号展开，前后各 22 张，加结果弹层共 45 张。没有复制 `example/integration_test/`、README 片段、DEV 阴影页面、pubspec 或工具文件。共享文件仅定点合并 main.dart 和追加矩阵；没有 core 补丁，不产生 `core_patch.diff`。

## 冲突、保守处理与建议

1. 通用规则禁止 `flutter build`，本批明确要求 Windows 集成构建：只通过指定集成执行器运行 Windows 测试，不执行独立 `flutter build`，不使用安卓／adb。
2. 任务允许主包 `test/example_pages_test.dart`，而末尾路径清单只列了 example 下新增测试；选择前者才能被现有 check_acceptance 扫描，不改工具扫描范围，也不新增工程依赖。测试对独立 example 源码采用相对引用，并只对这一不可避免的 lint 注明原因。
3. Flutter widget 测试没有设备系统字库；截图测试加载本机中文字体与 SDK 图标字体，Roboto 仍由已有全局配置加载。应用不携带字体资源，其他系统使用系统字体回退。Linux 等无该本机字体时不将中文像素 golden 作为门禁。
4. T4.5 文档要求每文件三轮，本批明确只需一次：本批执行一次冒烟，不改历史三轮证据，也不宣称已重新完成安卓验收。
5. D1、D2、D3、D7 涉及包导出、运动／覆盖率语义，本批不触碰；D5 不修改共享夹具；D6 新增 EXM 行标“已落地”；D8 对冲突保守继续并在此记录。
6. 建议最终文档统一“官方风格对齐”与“逐帧上游 fidelity”的区别；示例六奖品属于展示配置，不改变业务默认。TEST_STRATEGY §4.2 如希望独立 example/test 进入门禁，应在后续统一扩展扫描与 JSON 工程归属，不能在本批临时绕过扫描。
7. 目检修正（实现错误，不是设计冲突）：compat 的原生 JSON 字体字段应为 `fontStyle`，不能写成 Dart 模型的 `fontFamily`。已改正并增加“无兼容告警”断言。建议迁移示例显式提醒这两个字段名的区别。
8. 大乐透公开样式允许修改按钮文字，但画布文字固定使用 Roboto、没有字体族／回退参数；本批不改 lib，内置按钮采用 GO，避免截图字库缺字，外部“开始”与交互保留。后续可在统一设计评审后考虑为 LottoStyle 增加字体配置，不在本批扩大 API。
9. 分组日志不能直接串接：现有 JSON 校验器只接受单个最终 done 事件。本批在仓库外保留所有原始日志，合并时给 suite/group/test 编号添加独立前缀，并汇总为一个最终成功事件；最终页面复核替换旧页面 suite，保留其它真实测试结果。没有修改门禁脚本或伪造测试通过记录。建议后续为工具增加原生多日志输入。
