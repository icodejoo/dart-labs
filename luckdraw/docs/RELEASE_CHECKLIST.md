# 0.1.0 发布检查清单

## DEVFIN 最新真机收尾结果

DEVFIN（2026-11-11）本次仅单台 vivo V2417 / Android 16：grid_steady：失败；slot_raster：失败；lots_shaking：不确定；lotto_draw：失败。冷push首帧增量wheel/grid/slot为38.087/10.520/0.245ms，新标定增量预算41.896/11.572/0.270ms；wheel/grid未达原4ms估算目标。CPU五项目各五次均0有效，不能提供可信百分比；wheel/grid冷帧主机汇总仅2/5、1/5成功，数值来自原始driver响应，失败标记保留。真机采集链路未通过，不把已标定写成达到设计目标。

包含pending入口的profile APK已构建并校验，原脚本实际因有效轮不足退出1；只续跑未启动项目，共53次启动，每项3–5次。四个帧时项目均完成三轮，固定MET2比较器独立复算；原始attempt、恢复值、全部窗口交付和新旧表见[本次报告](../tool/bench/results/pending/REPORT.md)。冷帧增量预算见budgets.status.json.devfin；旧绝对首帧信息字段仅为schema兼容，不得把增量门槛直接比较旧40.378ms。12ms/4ms、稳定性和RSS阈值未放宽。

- [x] 新入口APK、型号/哈希、手机原设置记录与全部原始尝试落盘。
- [x] blank/slot冷帧各3轮driver通过；wheel/grid原始FrameTiming全部保留并计算增量。
- [ ] wheel/grid冷帧driver未各满3轮，主机TimelineSummary缺少完整Raster事件，验收不确定。
- [ ] 五项目CPU均0/5有效，cpuinfo区间滞后/旧PID及top线程表问题，尚未标定。
- [x] 四个帧时场景各3轮完成；结果按失败/不确定/已标定分别保留，不承诺性能全通过。

以下MET2/PEND待真机清单及前三轮门禁均为历史记录，当前状态以本节和第四轮度量说明为准。

> 状态：已按落地事实对齐（第三轮，2026-11-10）。0.1.0候选，尚未发布到pub.dev。

MET2最新性能口径（历史MET/FIN日志保留，当前以本节为准）：

MET2（2026-11-10）纯离线复算：**帧交付完整（全部130个窗口约60fps，59.829927–60.176516，无真实丢帧，按timeline交付口径）；偶发窗口的Raster时间被vsync背压污染且与绘制内容无关（参照方块同样出现）；按真机实测标定了首版回归预算。** 不是性能全部达标：1项满足有效目标（memory，RSS沿用FIN口径）、5场景已标定但未达最初设计目标、3场景失败、1场景不确定、1首帧信息项。首帧与进程级CPU待下次真机会话标定；性能结论基于单台设备vivo V2417（Android 16）三轮数据，不是跨设备保证。PERF五场景与DEV其余场景沿用MET/FIN身份，并非同一APK全量重测。现有timeline不等于独立面板呈现测量；污染窗口无法测量纯绘制成本。

| 场景 | 未污染/总窗口 | UI均值 ms | Raster均值/P90 ms | 结论 |
| --- | --- | --- | --- | --- |
| wheel_steady | 2/3 | 0.9365 | 5.0996/6.7480 | 已按实测标定（未达最初设计目标） |
| wheel_first_frame | 不适用 | — | —/— | 信息项，待标定 |
| grid_steady | 3/3 | 1.0243 | 5.4998/6.5570 | 失败 |
| slot_steady | 2/3 | 1.3576 | 3.4481/3.9580 | 已按实测标定（未达最初设计目标） |
| slot_raster | 3/3 | 1.0641 | 2.7681/3.1630 | 失败 |
| lever_steady | 3/3 | 1.3999 | 3.7137/4.2170 | 已按实测标定（未达最初设计目标） |
| capsule_mixing | 3/3 | 1.6541 | 3.8083/4.3140 | 已按实测标定（未达最初设计目标） |
| number_wheel_spin | 2/3 | 1.1357 | 2.9759/3.3465 | 已按实测标定（未达最初设计目标） |
| lots_shaking | 2/3 | 1.3782 | 3.8951/4.8300 | 不确定，需补跑 |
| lotto_draw | 2/3 | 2.2188 | 4.8241/5.4880 | 失败 |
| memory_cycles | 不适用 | — | —/— | 满足设计目标 |

硬门禁失败：grid合计P99=12.231ms、slot_raster=16.905ms、lotto=12.229ms（上限12ms）；lotto UI P99=4.386ms（上限4ms）。lots的Raster仍不稳定，判不确定、需补跑。未通过项不伪装成达成设计目标。

| 未达最初设计目标的场景 | 指标与差距（实测中位数/最初目标−1） |
| --- | --- |
| wheel_steady | Raster均值 +1.99% |
| grid_steady | UI均值 +70.72%、UI P90 +18.67%、Raster均值 +37.49% |
| slot_steady | UI均值 +35.76% |
| slot_raster | UI均值 +6.41% |
| lever_steady | UI均值 +39.99%、UI P90 +4.80% |
| capsule_mixing | UI均值 +10.27% |
| number_wheel_spin | UI均值 +13.57% |
| lots_shaking | UI均值 +37.82%、UI P90 +1.20% |
| lotto_draw | UI均值 +47.92%、UI P90 +10.75% |

预算清单、CPU指示及全部逐指标差距见[MET2报告](../tool/bench/results/met2/REPORT.md)与[第二轮度量修正说明](METRIC_FIX_REPORT.md)。RSS稳态仍为1.5MiB，首帧信息不计通过；首帧与进程级CPU待下次真机会话标定。

Skia与Impeller阴影为**已知后端差异**：半径差1–2物理像素，扫描线峰值差20.8–23.8/255。主会话决定不在库内按后端调整sigma：Skia与Chrome 1:1已在容差内，Impeller模糊近似不同，按后端分支换算不可靠且难验证。老虎机阴影被视口裁剪，缺少可观察样本，未量化；历史DEVICE_REPORT文字不改。

以下FIN/MET日志为历史证据；当前性能结论以顶部MET2表为准。第一轮MET本地门禁如下，不能把性能比较器预期的失败退出码伪装成通过。

## MET2 本地门禁实际输出

新增MET2-01～10，矩阵仅追加且状态「已落地」（D6），未新增依赖或覆盖率豁免。所有Flutter测试/分析串行，单条命令均少于五分钟；只在真实luckdraw目录离线执行，无设备、adb、Gradle、build、子代理或真实发布。

| 验证 | 实际输出摘要 / 退出码 |
| --- | --- |
| 主包 / bench `flutter pub get --no-example` | 均0；主包配置未变，bench追加exclude后立即恢复 |
| 主包 / bench `flutter analyze --no-pub` | 均`No issues found! (ran in 3.2s)`，0 issue / 0 |
| `dart format lib test tool`及检查 | `Formatted 347 files (0 changed)` / 0 |
| `flutter test test/tool --no-pub --concurrency=1 --reporter=json` | 187通过，0失败/跳过 / 0 |
| bench四文件 + design invariants最终复核 | 52 + 2 = 54通过；新增MET2测试10条 / 0 |
| 四组全量，独立`coverage/met2-{a,b,c,d}.lcov` | 552/130/365/23，共1070通过、140文件、0失败/跳过；各命令84.137/45.971/73.608/10.646秒 / 均0 |
| `dart run tool/coverage.dart --min=100 --lcov=coverage/met2.lcov` | `TOTAL: 6792/6792 (100.00%)`，`PASS: coverage >= 100.0%` / 0 |
| `dart run tool/check_imports.dart` | `PASS: 145 lib files; IMP-R1…R12` / 0 |
| `dart run tool/check_acceptance.dart` | `PASS: 1493 references resolve; 1094 registered tests all mapped.` / 0 |
| `check_acceptance.dart --from-json .../met2/validation/all.tests.jsonl` | 同为1493引用、1094登记测试全部映射 / 0 |
| `dart run tool/parity/generate.dart --verify-manifest` | `PASS: parity manifest 16 cases, 96 artifacts; hashes and frames verified` / 0 |
| `dart pub publish --dry-run` | `Total compressed archive size: 245 KB.`；`Package has 0 warnings.` / 0 |
| 正常冻结性能比较器 | 3硬失败、1不确定、首帧INFO，6场景回归通过但仅memory满足有效目标 / **1（真实未全达标）** |
| 幂等重算 | 连续重算预算及assessment的SHA-256一致，不叠加放宽 / 0 |

[MET2原始命令日志](../tool/bench/results/met2/validation/)、[测试汇总](../tool/bench/results/met2/validation/test_summary.json)、[真实事件合并](../tool/bench/results/met2/validation/all.tests.jsonl)、[来源/链接自检](../tool/bench/results/met2/validation/selfcheck.json)。原33个样本SHA-256及第一轮正文保留均核验，历史报告未改。1094登记与1070执行之差属于独立设备工程，本轮不冒充运行通过。下列MET/FIN表仅为历史门禁证据。

## MET 本地门禁实际输出

新增9个有断言的回归（MET-01～09，仅追加矩阵，状态已落地）；既有测试名保留，未新增覆盖率豁免或依赖。主包`flutter pub get --no-example`退出0，analysis_options未变化；bench同命令退出0，SDK自动追加exclude后立即恢复原配置。主包最终配置与IMPLEMENTATION_GUIDE §2.3逐字核对。

| 命令 | 实际输出摘要 | 退出码 |
| --- | --- | --- |
| `flutter analyze --no-pub`（主包） | `No issues found! (ran in 3.3s)` | 0 |
| `flutter analyze --no-pub`（bench） | `No issues found! (ran in 3.3s)` | 0 |
| `dart format lib test tool` | `Formatted 346 files (0 changed) in 0.76 seconds.` | 0 |
| `dart format --output=none --set-exit-if-changed lib test tool` | `Formatted 346 files (0 changed) in 0.75 seconds.` | 0 |
| `flutter test test/tool --no-pub --concurrency=1 --reporter=json` | 177通过、0跳过、0失败；bench相关三文件42通过，新增9条包含其中 | 0 |
| 四组全量测试（沿用下文FIN路径分组，覆盖率改met前缀） | **1060通过、0跳过、0失败，139文件**；a/b/c/d分别552/130/355/23 | 0 |
| `dart run tool/coverage.dart --min=100 --lcov=coverage/met.lcov` | `TOTAL: 6792/6792 (100.00%)`；`PASS: coverage >= 100.0%` | 0 |
| `dart run tool/check_imports.dart` | `PASS: 145 lib files; IMP-R1…R12` | 0 |
| `dart run tool/check_acceptance.dart` | `PASS: 1483 references resolve; 1084 registered tests all mapped.` | 0 |
| `dart run tool/check_acceptance.dart --from-json tool/bench/results/met/validation/all.tests.jsonl` | 同为1483引用/1084登记测试全部映射；独立设备测试本批未运行 | 0 |
| `dart run tool/parity/generate.dart --verify-manifest` | `PASS: parity manifest 16 cases, 96 artifacts; hashes and frames verified` | 0 |
| `dart pub publish --dry-run` | `Total compressed archive size: 244 KB.`；`Package has 0 warnings.` | 0 |
| MET比较器正式集合 / 全窗口敏感性 | 正式4通过、6失败、1信息项；敏感性9稳态失败、memory通过、首帧信息；全部窗口交付通过 | **1 / 1，成本未完全通过** |

原始日志、逐命令退出码及重放脚本见[MET validation目录](../tool/bench/results/met/validation/)，[测试汇总](../tool/bench/results/met/validation/test_summary.json)、[合并JSON](../tool/bench/results/met/validation/all.tests.jsonl)、[只读自检](../tool/bench/results/met/validation/selfcheck.json)。四组分别输出coverage/met-{a,b,c,d}.lcov，核对每个testStart有testDone、唯一success:true、无跳过失败，139文件无交叉且并集等于全部测试文件；真实事件仅偏移ID/时间，LCOV按行累计合并到coverage/met.lcov。最终只改成本工具常量后复跑c组并重新合并，a/b/d代码未变；不是用不完整组冒充全量。design_invariants_test.dart包含在工具及c组，文档最终编辑后额外复跑两条。

1084登记与1060执行之差是独立工程的设备测试，不把它们计作本批真机运行通过。发布预演仍不能替代服务端真实发布检查。已检查进程命令行，无本批dart/flutter_tester孤儿；两条其它工作区的dart-sass进程保持运行。首尾git log相同（443589a3、f0b64ae1），未add/commit/push。

FIN直接在真实仓库串行执行本地门禁与离线重算，没有手机/adb、flutter build、Gradle或真实发布，也没有git add/commit/push。下述真机、MIN及产物结果引用已保存报告，不冒充本批重测；远程CI成功没有本地替代证据。

| 已验证 | 未验证（需要外部条件） |
| --- | --- |
| 元数据0.1.0、许可证/NOTICE、11入口、中英文README及英文CHANGELOG已核对；依赖声明保持不变 | 发布前核对pub.dev包名、账号、verified publisher和权限；真实发布须用户明确授权 |
| `flutter pub get --no-example`成功，紧接检查主包analysis_options与IMPLEMENTATION_GUIDE §2.3一致；bench安装既有SDK依赖后也立即恢复其配置 | Linux golden与远程CI（含min-sdk、treeshake-apk）实际运行仍需外部环境证据 |
| MIN本地Flutter3.24.5 / Dart3.5.4：analyze零诊断、951个非golden测试通过；[报告](MIN_VERSION_REPORT.md) | MIN报告中独立的golden像素差异尚未闭环，非golden通过不能替代它 |
| Web/APK各十探针真实构建、零无关源码/受检查符号泄漏，十项APK预算回填；CI treeshake-apk已重新启用（目前五项）；[报告](../tool/treeshake/README.md) | 远程APK作业已启用不等于已运行通过 |
| vivo V2417 / Android16：集成11文件×3轮 **33/33通过**；Windows另有33/33；[DEVICE_REPORT](DEVICE_REPORT.md) | MET2为3硬失败、1不确定，首帧及进程级CPU待标定；不能标发布性能已通过 |
| DEV/PERF/AB数据已采集；MET检查全部稳态窗口交付完整，成本剔除背压窗口；RSS沿用FIN全部10场景中位数通过 | 污染窗口无法观测纯绘制成本，仍有超标与未污染轮间不稳定；不能挑轮获得通过 |
| Skia/Impeller阴影各三次已采集：半径差1–2物理像素、扫描线峰值差20.8–23.8/255 | 已知后端差异，不按后端改sigma；老虎机缺少可观察样本，未量化 |
| 示例美化审计含45张自渲染PNG，共1262694 B（约1.26MB），[审计](EXAMPLE_STYLE_AUDIT.md)、[截图](example_audit/) | 没有上游演示真实截图，上游演示逐像素对齐未做；审计只表示风格方向 |
| 两份README各新增八张浅色图，12个Dart代码块SHA-256未变，沿用REL/B17b临时工程零诊断验证 | raw图片需对应仓库main分支文件已发布后才能远程加载，本轮不push；当前未验证远端图片可用性 |
| 本批主包及bench分析均0 issue；1051测试、0跳过、0失败；138文件全覆盖；lib行覆盖6792/6792=100%；详情见下表 | layout/record细分打点与解码字节诊断尚未接线，不能用已有首帧/释放测试冒充 |
| `dart pub publish --dry-run`：退出0，`Package has 0 warnings.`；Pub显示压缩包 **244 KB**，未修改.pubignore | `The server may enforce additional checks.`；预演不能替代实际服务端发布检查 |

## FIN本批全量门禁实际输出

新增6个有断言的工具回归，矩阵只追加FIN-01～FIN-06，按D6标「已落地」；没有覆盖率豁免新增。历史矩阵前缀及各批报告保留原样，以本页和当前正文区分新旧结论。

| 命令 | 实际输出摘要 | 退出码 |
| --- | --- | --- |
| `flutter analyze --no-pub`（包根） | `No issues found! (ran in 3.3s)` | 0 |
| `flutter analyze --no-pub`（tool/bench） | `No issues found! (ran in 3.6s)` | 0 |
| `dart format lib test tool` | `Formatted 345 files (0 changed) in 0.75 seconds.` | 0 |
| `dart format --output=none --set-exit-if-changed lib test tool` | `Formatted 345 files (0 changed) in 0.76 seconds.` | 0 |
| `flutter test test/tool --no-pub --concurrency=1 --reporter=json` | 168通过、0跳过、0失败；独立工具复跑，不与下列分组重复计数 | 0 |
| lutter test test/tool/design_invariants_test.dart --no-pub --concurrency=1 | 最终文档改动后额外复跑2/2通过，不计入1051唯一测试数 | 0 |
| 四组全量测试（每组--no-pub --concurrency=1 --coverage --reporter=json） | **1051通过、0跳过、0失败，138文件**，均有success:true结束事件 | 0 |
| `dart run tool/coverage.dart --min=100 --lcov=coverage/fin.lcov` | `TOTAL: 6792/6792 (100.00%)` / `PASS: coverage >= 100.0%` | 0 |
| `dart run tool/check_imports.dart` | `PASS: 145 lib files; IMP-R1…R12` | 0 |
| `dart run tool/check_acceptance.dart` | `PASS: 1474 references resolve; 1075 registered tests all mapped.` | 0 |
| `dart run tool/check_acceptance.dart --from-json tool/bench/results/fin/validation/all.tests.jsonl` | 同为1474引用/1075登记测试全部映射；设备测试按源码登记核查，本批未运行 | 0 |
| `dart run tool/parity/generate.dart --verify-manifest` | `PASS: parity manifest 16 cases, 96 artifacts; hashes and frames verified` | 0 |
| `dart pub publish --dry-run` | `Total compressed archive size: 244 KB.` / `Package has 0 warnings.` | 0 |
| `dart run tool/bench/compare.dart --input=tool/bench/results/fin/comparison --rss-all-scenes` | 75指标中10项中位数超预算、23项不稳定（有重叠，合计30项未通过）；RSS稳态10场景中位数全通过；完整失败表保留 | **1，性能未完全通过** |

原始门禁日志与退出码：[validation目录](../tool/bench/results/fin/validation/)；[测试汇总](../tool/bench/results/fin/validation/test_summary.json)、[合并JSON](../tool/bench/results/fin/validation/all.tests.jsonl)。新增6条工具测试既有名称均保留。登记1075与执行1051的差额为独立工程的设备测试，不能把登记数写成设备执行通过数。

## 分组复现与合并

在包根串行运行，任何单命令最多五分钟；超过上限先结束本次进程树，再拆小组。FIN四组均无需超时补跑：

| 组 | 测试路径 | 文件数 | 通过数 | 总耗时s（含启动/采集） |
| --- | --- | --- | --- | --- |
| fin-a | `test/capsule test/compat test/core test/grid` | 62 | 552 | 66.881 |
| fin-b | `test/lots test/lotto test/number_wheel test/parity` | 31 | 130 | 36.541 |
| fin-c | `test/slot test/testing test/tool test/wheel` | 41 | 346 | 62.735 |
| fin-d | `test/perf test/example_pages_test.dart` | 4 | 23 | 9.724 |

```powershell
flutter pub get --no-example
# 紧接安装检查/恢复IMPLEMENTATION_GUIDE §2.3分析配置。
flutter analyze --no-pub
dart format lib test tool
dart format --output=none --set-exit-if-changed lib test tool
flutter test --no-pub --concurrency=1 --coverage --coverage-path=coverage/fin-a.lcov --reporter=json test/capsule test/compat test/core test/grid
flutter test --no-pub --concurrency=1 --coverage --coverage-path=coverage/fin-b.lcov --reporter=json test/lots test/lotto test/number_wheel test/parity
flutter test --no-pub --concurrency=1 --coverage --coverage-path=coverage/fin-c.lcov --reporter=json test/slot test/testing test/tool test/wheel
flutter test --no-pub --concurrency=1 --coverage --coverage-path=coverage/fin-d.lcov --reporter=json test/perf test/example_pages_test.dart
```

JSON标准输出分别保存在validation的fin-{a,b,c,d}.stdout.log。合并前验证每组唯一success:true、所有testStart均有testDone、无失败跳过；四组文件不交叉，并集精确等于包内138个*_test.dart。JSON仅偏移ID/时间，保留名称与结果，合并真实成功结束事件；LCOV直接串联真实记录，门禁按文件/行累计命中。输出coverage/fin.lcov及validation/all.tests.jsonl。旧REL三组清单漏掉后加的perf/与example_pages，本批集合校验发现后补第四组，不把前三组称为全量。

## 发布预演与文件

`.pubignore`保持不变，仍排除整个docs、tool、test（含parity基线）、coverage/build、lockfile、SDK/Gradle缓存及生成的插件文件。包内保留lib、example源码和模板、两份README、CHANGELOG、LICENSE、NOTICE、pubspec等；Pub显示244KB（压缩包），没有把1.26MB截图带入发布包。README图片选择raw绝对地址方案，避免依赖被排除的docs文件和pub.dev相对地址重写；需要仓库main分支对应文件可访问，尚未验证远端加载。本轮未改README的Dart代码块，无需重建临时验证工程。

预演实际输出：[publish.stdout.log](../tool/bench/results/fin/validation/publish.stdout.log)；已有约束更新提示只属解析提示，未升级依赖。bench第一次分析因尚未生成package_config导致SDK测试包未解析；安装其既有SDK依赖后立刻恢复分析配置，再分析为0 issue，没有修改依赖声明。

## 文档自检与保守处理

一次性脚本位于系统临时scratchpad（`%TEMP%/luckdraw-fin/selfcheck.py`），未放进仓库；[输出](../tool/bench/results/fin/validation/selfcheck.json)。覆盖docs下94条相对链接，全部有效；1004条正文测试引用全部在矩阵，矩阵再由静态与运行JSON双向校验；两份README引用的16次图片均存在（八种图），单图小于200KB；45张审计图1262694B。

脚本字面扫描发现但已由上下文解释的引用：IMPLEMENTATION_GUIDE中的tool/xxx.dart是路径格式占位，lib/main.dart相对bench/探针临时工程；TEST_STRATEGY中的test/文件.dart是格式示例；ARCHITECTURE中的LuckyFlip为用户扩展示例，LuckyRegistry属于§17.2历史假包实验。它们不是包API/真实缺失文件，不为消除扫描结果而创建假文件或改历史符号。没有未解释的真实测试引用或失效相对链接。

UI预算以主会话指定值为准；“实测×1.1向上取整”未规定统一步长且不严格产生全部批准值：wheel按0.1ms会得1.1却要求保留1.0，capsule/lotto会得1.9/2.4却批准2.0/2.5。保守采用指定值并写入budgets.status.json依据，不改Raster/掉帧。RSS相对极差不作泄漏判据，净增长负差在原值表保留、门禁按零；五次循环和dispose确定性保证保留。

MET修正了FIN的高档解释：证据支持vsync背压，高档参照与主场景不同步，全部130个稳态窗口交付完整。转盘未污染Raster平均中位数5.0996ms；第一轮MET曾判6场景成本或稳定性失败，第二轮MET2按顶部当前结论，首帧与进程级CPU仍待标定。样本有限，不能据此估计总体发生概率。

阴影决定已明确：保留公式，不按后端调整sigma，登记为已知后端差异；老虎机阴影被裁剪且未量化，不能宣称其阴影验收通过。

## 真实发布前

- [x] MIN/APK/DEV最终事实回填，FIN本地全量门禁与发布预演完成。
- [x] 文档正文、默认缓存/RSS/UI口径与README截图及性能说明对齐第三轮。
- [x] MET离线分类与重算、9条回归、1060测试/100%覆盖率及发布预演完成；阴影不按后端调sigma的决定已记录。
- [ ] 闭环MET2三个硬失败场景及lots稳定性不确定；先补blank_first_frame空白冷首帧三轮，再制定增量预算并实测进程CPU；不能把首帧信息项算通过。
- [ ] 主会话统一验收矩阵历史顶部摘要与最终状态（FIN仅追加行，不改前缀）。
- [ ] 解决或由维护者明确接受性能、阴影、最低版本golden与其它外部验证限制。
- [ ] 发布仓库中的图片并确认远端README显示；完成Linux/远程CI证据。
- [ ] 核对pub.dev包名/发布权限，获得用户明确授权后才执行真实发布。

本清单不授权真实发布，本轮仅运行带`--dry-run`的命令。

## PEND：离线根因与待真机收尾（2026-11-11）

PEND-A 已完成事件层定位，代码根因仍无法判定；PEND-B 无充分证据支持可避免的库内工作，保持产品 lib、公共API、parity/MANIFEST、golden与预算不变。16个未污染窗口（含旧DEV）共186个尖峰；MET2正式样本37个（slot5、grid8、lotto24、lots0）。slot/grid的Raster长区间主要在GLES Encode/Submit；UI个别尖峰落在PAINT/COMPOSITING。lots没有12/4ms尖峰但窗口级Raster仍不稳定。详情与逐帧表见[根因报告](PERF_ROOTCAUSE_REPORT.md)。当前仍为三项硬失败、一项不确定，不能写「已达标」或「已修复」。

待真机会话清单（本批未执行）：

- [ ] 准备包含新 `integration_test/pending_bench_test.dart` 入口的profile APK；旧保存APK不包含新增场景，不能直接替代。本批禁止构建，因此APK准备仍为下一次会话前提；脚本自身永远使用 `--use-application-binary`，不隐式触发构建。
- [ ] 保持用户当前亮度/常亮设置，人工保证亮屏未锁屏、设备环境一致；脚本不改设置。记录APK哈希与设备身份，主机FreePhysicalMemory≥4GiB。
- [ ] blank冷push三轮、wheel/grid/slot冷push各三轮；计算相同外壳下玩法与空白中位数之差，维护者再确认增量预算，不能直接把旧40.378ms减新空白。
- [ ] wheel/grid/slot/capsule/lotto五秒稳态CPU各三轮；窗口前后+窗口内五次采样，保存进程及UI/Raster线程数据；CPU无批准预算，采到数据仅为标定。
- [ ] slot_raster、grid_steady、lotto_draw、lots_shaking各三轮复测；至少两个未污染窗口，必要时补到总启动五次；保留全部真实失败/污染窗口，由冻结MET2判定12/4ms余量、成本、稳定性、交付与RSS。
- [ ] 记录下一次真实结果；可能仍失败或不确定，不承诺一次复测必然通过。14项最初设计差距仍保留。

从包根运行（约40–60分钟；手机获得使用权后）：

```powershell
./tool/bench/run_pending_device_checks.ps1 -DeviceSerial <serial> -ApplicationBinary <新入口profile.apk>
```

输出 `tool/bench/results/pending/`，存在旧目录时拒绝混样；`runs.json`含失败尝试与每项≤5次启动，`assessment.json`/`REPORT.md`输出「通过/已标定/失败/不确定」。首帧/CPU「已标定」只是建立实测基线；`compare.dart`正常回归不自动放宽预算。CPU/复测的grid等属于不同测量项目，初始39次独立进程启动。窗口内不做额外adb看护，仅轮前/轮后检查屏幕；中间DIM、驱动等待及热状态仍是实测局限。

PEND-C/D代码、纯函数测试与文档已落地；设备采集分支只写未跑。新增验收PEND-01～16状态「已落地」（D6），不是设备验收完成；D1–D5/D7既有库实现及D2门禁未改，D8按保守做法记录未知根因与旧APK缺新场景的前提。

启动上限解释：CPU与帧时各要求grid/lotto三轮；若将「≤5/项」解释为同玩法两种测量合计，最低六次会冲突。本脚本按独立测量项目计数（13项、每项≤5），CPU与无采样干扰的帧时分开，不合并或遗漏任一要求。APK准备、冷push而非启动首帧、旧外壳不可混减等限制已写明；建议T4.8统一术语与计数口径。

### PEND 本地门禁实际输出

| 命令 / 范围 | 实际输出摘要 / 退出码 |
| --- | --- |
| `flutter pub get --no-example`（主包） | Got dependencies!；立即核实analysis_options.yaml未变，后续自检与§2.3一致 / 0 |
| `flutter analyze --no-pub`（主包 / bench分别串行） | 两工程均No issues found!，含info为0 / 0 |
| `dart format lib test tool`；`dart format --output=none --set-exit-if-changed lib test tool` | 最终353 files (0 changed) / 0 |
| `flutter test test/tool --no-pub --concurrency=1 --reporter=json` | 202通过；最终第三组也覆盖全部202条工具测试 / 0 |
| FIN口径四组串行，见下表 | 1085通过，141文件，0失败/跳过，文件并集精确覆盖全部`test/**/*_test.dart` / 0 |
| `dart run tool/coverage.dart --min=100 --lcov=coverage/pend.lcov` | TOTAL: 6792/6792 (100.00%)；无新增豁免 / 0 |
| `dart run tool/check_imports.dart` | PASS: 145 lib files; IMP-R1…R12 / 0 |
| `dart run tool/check_acceptance.dart` | PASS: 1509 references resolve; 1110 registered tests all mapped / 0 |
| `dart run tool/check_acceptance.dart --from-json tool/bench/results/pend/validation/all.tests.jsonl` | 同为1509引用/1110登记全部映射 / 0 |
| `dart run tool/parity/generate.dart --verify-manifest` | PASS: parity manifest 16 cases, 96 artifacts; hashes and frames verified / 0 |
| `dart pub publish --dry-run` | Package has 0 warnings；压缩归档245KB；未真实发布 / 0 |
| PEND原始证据/配置/文档链接自检 | 33份历史汇总及16份原始trace SHA-256一致，245份产品/基线/配置身份核对，无失效相对链接 / 0 |

| 组 / 路径 | 文件数 | 通过 | 最终运行秒数 |
| --- | --- | --- | --- |
| pend-a：`test/capsule test/compat test/core test/grid` | 62 | 552 | 111.607 |
| pend-b：`test/lots test/lotto test/number_wheel test/parity` | 31 | 130 | 52.493 |
| pend-c：`test/slot test/testing test/tool test/wheel` | 44 | 380 | 109.155 |
| pend-d：`test/perf test/example_pages_test.dart` | 4 | 23 | 12.000 |

四组分别使用`coverage/pend-{a,b,c,d}.lcov`；JSON核对真实success:true、每个testStart都有testDone、无失败跳过，再只偏移事件ID/时间合并。受新增工具导入位置与CPU解析边界调整影响，C组已独立串行复跑并重新合并，其余组源码未受影响；单条命令均未超过五分钟。1085执行与1110登记之差为独立工程的25条设备测试，不能算本批设备通过。

新增15条Flutter工具测试：A关联2条（其中Python事件配对自检另含2例），C关联13条；另登记1条真机路由测试而未执行。B不改产品；D没有额外行为测试，仅文档/配置/链接自检。文件：A的`analyze_frames.py`、`PERF_ROOTCAUSE_REPORT.md`与`results/pend_offline/frames.json`；C的`pending_metrics.dart`、`pending_scene.dart`、`cpu_sampler.dart`、`assess_pending.dart`、`run_pending_device_checks.ps1`、三份`fixtures/*txt`、新`integration_test/pending_bench_test.dart`及调整`bench_support.dart`/`perf_driver.dart`/`compare.dart`、`test/tool/bench_pending_test.dart`、bench README；D更新本清单、TEST_STRATEGY、METRIC_FIX_REPORT、文档索引，矩阵只追加16行。验证辅助脚本/真实日志位于下列证据目录，根README两份和产品lib均未改。

[原始命令、输出与退出码](../tool/bench/results/pend/validation/)、[四组测试汇总](../tool/bench/results/pend/validation/test_summary.json)、[真实运行事件](../tool/bench/results/pend/validation/all.tests.jsonl)、[自检结果](../tool/bench/results/pend/validation/selfcheck.json)。本批未使用子代理、手机、adb、Gradle、build、drive、暂存、提交或push；仅离线语法解析与PlanOnly验证脚本编排。开发期一次误启动的自有flutter_tester子进程已按命令行识别并结束，最终检查无自有残留。

### DEVFIN 本地门禁、收尾与建议

| 命令/核验 | 本次实际输出摘要 |
| --- | --- |
| 主包/bench `flutter pub get --no-example` | 均0；主包analysis_options未变，bench自动追加后立即恢复；pubspec依赖未改 |
| 主包/bench `flutter analyze --no-pub` | 均No issues found，0 issue；输出耗时6.0s/4.3s |
| `dart format lib test tool`及只读检查 | 均Formatted 354 files (0 changed) |
| `flutter test test/tool --no-pub --concurrency=1 --reporter=json` | 206通过，0失败/跳过；包含DEVFIN新增4条 |
| 四组全量、独立coverage/devfin-{a,b,c,d}.lcov | 552/130/384/23，共1089通过、142文件，0失败/跳过；68.782/36.948/73.651/9.632秒 |
| `dart run tool/coverage.dart --min=100 --lcov=coverage/devfin.lcov` | TOTAL: 6792/6792 (100.00%)；PASS |
| `dart run tool/check_imports.dart` | PASS: 145 lib files; IMP-R1…R12 |
| `check_acceptance.dart`静态 / `--from-json .../all.tests.jsonl` | 均PASS: 1528 references resolve; 1114 registered tests all mapped |
| `dart run tool/parity/generate.dart --verify-manifest` | PASS: parity manifest 16 cases, 96 artifacts; hashes and frames verified |
| `dart pub publish --dry-run` | 246 KB；Package has 0 warnings；退出0，没有真实publish |
| 冻结compare（仅四复测场景） | 退出1；grid/lotto硬失败，slot_raster成本失败，lots不确定；不作为本地工具门禁通过 |
| 原始/续跑采集脚本与assess_pending | 退出1；冷帧driver轮次不足，CPU各0/5；独立审计报告不冒充该CLI通过 |
| 数据自检 | 53次启动，每项3–5；33份新汇总、28个原始设备响应、341文件哈希；型号V2417，零fps=0轮，lib145文件哈希未变 |
| 持续窗口交付 | 24/24通过，fps59.962560–60.159200，最低交付比例99.937600%；未独立测量面板呈现 |
| 手机与进程收尾 | 亮屏未锁，stay_on=2、亮度模式0/亮度1；当前用户0无bench包（pm path及包列表为空）；仅结束本轮38476/30904两个Gradle daemon，其它进程保留 |

卸载首次返回DELETE_FAILED_INTERNAL_ERROR，再以当前用户卸载返回not installed for 0；最终包列表/pm path均空，因此记录为当前用户已无安装，不冒充卸载命令退出0。日志汇总脚本一次文本替换将append误改，Flutter工具测试本身已退出0；修正后由原JSON确认206条通过，无需重跑已通过测试。原始采集、比较器失败和上述异常均保留。

建议修正文档/工具：在bench README补完整pending目标与LUCKDRAW_TIMELINE构建命令；冷窗口先无损保存设备response，再容忍SDK无完整Raster事件；CPU采样从当前进程身份出发并验证原生统计区间，支持本机toybox列头，绝不使用陈旧PID替代；run_pending逐项保留失败并继续独立项目、恢复时不重置计数；经维护者批准扩展schema，分别表达空白基线、wheel/grid/slot有符号首帧增量及冻结预算。当前保守做法是在budgets.status.json.devfin冻结有效增量，旧绝对字段保持信息兼容，不把它与增量比较。

D6：矩阵仅追加DEVFIN-01～19，真实通过条目标已落地，失败/不确定如实标原因；D8：不改架构或lib，对采样工具和预算schema缺口保守留证。D1–D5/D7相关库实现及D2门禁未改；没有core_patch.diff、add/commit/push。前三轮METRIC正文及原验收矩阵字节前缀保留。

### DEVFIN 回拷后真实仓库复验

已将本批12个路径回拷到E:/workspaces/dart-labs/luckdraw；共享文档和矩阵逐次重读后定点追加，budgets仅更新reason/devfin/status字段，没有覆盖其它并行改动。新增Dart文件Formatted 1 file (0 changed)；真实仓库flutter test test/tool为206/206通过（38.621s）；check_imports为PASS:145 lib files；check_acceptance为PASS:1528 references resolve、1114 registered tests all mapped，全部退出0。原始日志见results/pending/validation/real_*；完整路径及文件哈希见copy_manifest.json。源lib、依赖、parity/golden未修改，无core_patch.diff。

2026-11-11 01:15:35（北京时间）最终交接实测：V2417内置屏幕state ON/committedState ON、mWakefulness=Awake、isKeyguardShowing=false；USB常亮2、手动亮度模式0、亮度1，设置未修改；当前用户0无bench安装。仅本轮Gradle PID38476/30904已结束，无自有dart/flutter_tester孤儿；两条其它工作区dart-sass进程保留。最近两条git提交仍443589a3/f0b64ae1，没有add/commit/push或真实publish。

## INSTR 第五轮实际结果

INSTR（2026-11-11，副本候选实现）：wheel/grid带打点冷首帧中位数38.412→27.075ms、24.214→12.993ms，精确文字宽度缓存将首帧TextPainter.layout次数276→63、128→22；随机/多语言/emoji/lineClamp等价。减DEVFIN历史空白2.883ms后的增量24.192/10.110ms，新预算26.612/11.121ms，仍未达到原4ms目标，三轮波动大。CPU采用/proc累计节拍差，UI与平台合并标为UI+platform；wheel完整链路仅2/5，不能给三轮中位数；其余场景逐轮数值和有效性见本轮报告，lotto仅搅拌阶段。库改动以补丁交付，未覆盖并行共享lib，待主会话合并。

[逐轮证据、门禁和未完成项](../tool/bench/results/pending2/REPORT.md)；[命令与退出码](../tool/bench/results/pending2/validation/)。不能将副本库修复、已标定或14份有效CPU中的部分成功写成发布性能全部通过。原12ms/4ms、GC、RSS门槛和历史失败保持。

## INSTR 真实仓库回拷复验

共享路径重读后定点追加；真实lib未覆盖。23个库候选文件（核心8、玩法15）和核心等价测试以两份diff交付，两补丁在快照上git apply --check --ignore-space-change均exit0；核心矩阵2行/COV-02见core_acceptance_append.md。真实仓库格式检查7个自有Dart路径exit0；flutter test test/tool为223/223、0失败/跳过（45.310s）；check_imports为145 lib PASS；check_acceptance为1552 references/1131 registered tests PASS。副本四组全量1108/1108（144文件，554/130/401/23），行覆盖6878/6878=100%，主包/bench分析均0 issue，format360文件0改动；矩阵静态与from-json均1554/1133，parity16例/96产物未变，publish --dry-run压缩包248KB、Package has 0 warnings。登记与主包执行计数差25是独立example/bench注册，不冒充全部设备运行。

最终实测 2026-11-10T18:20:04.5409880Z：屏幕ON=True、Awake=True、未锁=True，stay_on=0（要求2，未通过）、亮度模式=0、亮度=1；当前用户bench包列表及pm path为空。卸载命令exit1/DELETE_FAILED_INTERNAL_ERROR，未冒充退出0。常亮变化来源未定位，本批没有执行任何设置写入命令。

进程末检没有自有dart/flutter_tester；两次single-use Gradle已退出，接手前Kotlin PID7968保留，没有按java.exe批杀。首尾git log仍443589a3/f0b64ae1，未add/commit/push。完整路径和共享文件变更见tool/bench/results/pending2/validation/copy_manifest.json，真实复验日志见validation/real_*。CPU完整链路wheel仅2/5，其余四项各三轮；lotto仅搅拌阶段，任务完成状态为PARTIAL。


## STEADY 第六轮本机门禁与收尾

已回滚库候选后的最终实现：新增工具4条，四组覆盖全部145个测试文件，1112/1112通过、零失败跳过；工具单独227通过。实验阶段lotto36条仅为拒绝实验历史，不计作最终新增。

| 命令 | 实际输出摘要 |
| --- | --- |
| analyze | exit=0，7.254s；Analyzing luckdraw...                                            / No issues found! (ran in 5.3s) |
| bench_analyze | exit=0，5.333s；Analyzing bench...                                               / No issues found! (ran in 3.5s) |
| format | exit=0，2.045s；Formatted 361 files (0 changed) in 0.86 seconds. |
| format_check | exit=0，1.892s；Formatted 361 files (0 changed) in 0.85 seconds. |
| tools | exit=0，38.401s；227 passed; failed=0; skipped=0 |
| steady-a | exit=0，71.916s；554 passed; failed=0; skipped=0 |
| steady-b | exit=0，36.24s；130 passed; failed=0; skipped=0 |
| steady-c | exit=0，75.947s；405 passed; failed=0; skipped=0 |
| steady-d | exit=0，9.634s；23 passed; failed=0; skipped=0 |
| coverage | exit=0，1.52s；TOTAL: 6878/6878 (100.00%) / PASS: coverage >= 100.0% |
| imports | exit=0，1.916s；PASS: 145 lib files; IMP-R1…R12 / 依赖图与静态规则通过 |
| acceptance | exit=0，1.528s；PASS: 1564 references resolve; 1137 registered tests all mapped. / 全部测试引用有效且无遗漏 |
| acceptance_json | exit=0，1.425s；PASS: 1564 references resolve; 1137 registered tests all mapped. / 全部测试引用有效且无遗漏 |
| parity | exit=0，10.874s；PASS: parity manifest 16 cases, 96 artifacts; hashes and frames verified |
| publish | exit=0，4.507s； / Package has 0 warnings. |

LCOV独立使用coverage/steady-{a,b,c,d}.lcov，验证四组并集后合并coverage/steady.lcov；JSON仅平移ID/时间合并真实事件，--from-json校验通过。日志与执行元数据见tool/bench/results/steady/validation，逐组真实计数在test_summary.json。

真机A：slot/grid/lots各3/3；lotto4/5、未污染2；wheel CPU3/3。lotto候选复测3/3未污染，但无稳定净收益且UI P99仍失败，已回滚。原实现grid/slot/lotto仍失败，lots本轮通过，不放宽预算。原始时间线57份（含response）无损gzip校验后归档；拒绝实验diff只作历史，不应应用。

手机收尾：stay_on=2、亮度模式0、亮度1，dumpsys display为ON、Awake且未锁；reverse为空。卸载exit1/DELETE_FAILED_INTERNAL_ERROR，但pm list packages与pm path均空，实测无bench包。没有改手机设置或批杀java；自有进程末检在真实仓库复验后追加。

[STEADY完整报告](../tool/bench/results/steady/REPORT.md)，[逐帧归因](../tool/bench/results/steady/ATTRIBUTION.md)。副本完成所有本地门禁，真实库不覆盖，回拷仅工具/测试/文档且共享文件重读定点追加。


## STEADY 真实仓库回拷复验

真实仓库实际输出：format本批3个Dart文件0改动；flutter test test/tool --no-pub --concurrency=1 为227/227，39.389s，零失败/跳过；check_imports为145 lib文件PASS；check_acceptance为1564 references / 1137 registered tests全部映射PASS。源/共享14个路径及全部结果文件见tool/bench/results/steady/validation/copy_manifest.json；没有回拷lib，库哈希在副本已核对恢复同步基线。共享文档与矩阵均即时重读定点追加，无整文件覆盖他人增量。

最终实测2026-11-10T19:15:22.1344383Z：stay_on=2，brightness_mode=0，brightness=1，Display State=ON、Awake且未锁，reverse为空，包列表与pm path均空；卸载原退出1/DELETE_FAILED_INTERNAL_ERROR保留。进程末检仅剩接手前的两个其它工作区Sass Dart PID25880/22908；没有自有dart/flutter_tester/Gradle/Kotlin残留，无需结束进程。首尾git log均443589a3 / f0b64ae1，未add/commit/push。

最终库候选已回滚，无待合并core_patch.diff；steady_lotto_rejected.diff仅拒绝实验历史，不应应用。grid/slot/lotto性能仍失败、lots仅本轮三轮通过；CPU仅单台设备标定。
