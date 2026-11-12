# 摇树验证

从 luckdraw 包根目录执行：

```powershell
dart run tool/treeshake/check_treeshake.dart --backend=web
dart run tool/treeshake/check_treeshake.dart --backend=web --probe=wheel_only
```

无 `--probe` 时按 `kTreeshakeProbes` 顺序串行构建十个探针；指定单个玩法时先额外构建 baseline。工程建立在系统临时目录 `ldts/ts_*/probe`，通过 path 依赖当前包；每个探针结束后立即删除工程。禁止并行构建。构建前执行 `(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory`，低于 3145728 KiB 时等待内存回升。单条 Flutter 命令限时五分钟，仅清理该命令的后代进程。

实际构建计划：

```powershell
flutter create --platforms=web --empty --no-pub --project-name=luckdraw_treeshake_probe <临时目录>
flutter pub get --offline --no-example
# 离线失败时重试 flutter pub get --no-example
flutter build web --release --source-maps --no-pub
```

`checkProbe` 按 TEST_STRATEGY §8.2 的源码目录规则及下列 B13c 符号规则检查产物，`checkSizeRelations` 检查每个单玩法的 gzip 增量严格小于 all_games 增量的 60%。脚本任何断言失败均以非零状态退出，不应通过放宽规则掩盖失败。


### 按探针配置符号（B13c）

`_checkedSymbols` 是有限的受检查符号全集：七个玩法的公开类型、拉杆类型、三个转换函数、缓动类型、注册表和 compat 缓动名称表。`_allowedSymbols` 为每个探针显式声明允许集，禁符号统一通过 `全集.difference(允许集)` 得到；baseline、compat_wheel、all_games 也执行此规则。玩法增加类型时同步维护对应的 `_*Symbols` 集合，不扫描应用和 Flutter 的任意符号。

| 探针 | 允许的受检查符号 |
| --- | --- |
| baseline | 无 |
| wheel_only / grid_only / capsule_only / number_wheel_only / lots_only | 自己的玩法类型、QuadEasing |
| slot_only | 自己的普通老虎机类型、QuadEasing；不含拉杆类型 |
| lotto_only | 自己的玩法类型、QuadEasing、CubicEasing |
| compat_wheel | 转盘类型、wheelFromLuckyCanvasConfig、上游七种缓动类型及 kLuckyCanvasEasingNames；禁止其它玩法类型及两个转换函数 |
| all_games | 七玩法及拉杆类型、QuadEasing、CubicEasing |

符号匹配保留标识符边界，允许 `CubicEasing.easeOut` 等限定名，避免误匹配 `NotCubicEasing`。不要求类名必须出现：dart2js 可能内联极小类；源码目录检查同时执行。lotto 允许 cubic 是对已有合法依赖的准确描述，wheel 仍禁止 cubic，未放宽其它玩法/未引用缓动的规则。新增解析器测试分别验证这两种情况，并独立验证无关玩法/转换符号及 baseline 禁符号。

`budgets.json` 的 Web 上限字段为 `maxDeltaGzipBytes`，表示 Dart `GZipCodec(level: 9)` 压缩后减去 baseline 的增量；baseline 的增量与预算均为 0。`--update-budgets` 使用该增量乘 1.1、向上取整。首轮额外使用 GNU `gzip -9` 测量，记录独立的 `maxGnuDeltaGzipBytes`（GNU 实测增量 × 1.1，向上取整），避免混用两种压缩器的预算。

`measuredRawBytes`、`measuredGzipBytes`、`measuredDeltaGzipBytes` 分别记录原始字节、GNU gzip 字节与 GNU 增量；`measuredDartGzipBytes`、`measuredDeltaDartGzipBytes` 记录现有门禁采用的 Dart 字节与增量。现有 CLI 继续强制执行 Dart 上限；GNU 上限保留为本轮测量证据并由快照一致性测试校验，CLI 后续构建不会调用外部 gzip。这是保留 B13a 工具契约的保守处理，不能把 GNU 上限当作已经接入 CLI 的新增门禁。

APK 后端现在会自动创建独立 Android 工程并串行构建 arm64 release。无需设备，也无需手动查找报告：

```powershell
dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=baseline,wheel_only,grid_only,slot_only,all_games
```

不传 `--probe` 时运行全部十个探针；逗号列表必须是已知且不重复的名称，baseline 始终只构建一次。Web 也支持同样的选择语法。APK 实际构建命令是 `flutter build apk --release --analyze-size --target-platform=android-arm64 --no-pub`，沿用 Web 的 release 及默认 icon 摇树口径，没有额外关闭摇树。每条 Flutter 命令最多五分钟，探针之间串行。

本机 Flutter 3.47 把最终报告写入 `~/.flutter-devtools/apk-code-size-analysis_*.json`；工具比较构建前后快照，同时搜索独立工程 `build/`，只接受唯一新报告，零个或多个都失败，不使用历史报告。报告会复制到本包 `build/treeshake-apk/<probe>.json`，逐探针摘要写入同目录 `measurements.json`。随后删除本次外部报告和临时工程；历史报告保持原样。

结构自检要求 `type=apk`、`Root/lib/arm64-v8a/libapp.so (Dart AOT)`、单架构及非空 AOT 树。解析器支持真实的 `k=p` 分层目录及具有尖括号类型名、`k=s,t=D` 和非负整数字节数的 VM 数据叶节点，并保留旧夹具的完整 URI/相对库路径支持；库缺失、目录未落到库、不符合上述数据标记的节点和非法字节数均失败。只有已完整校验结构的 baseline 可以不含 luckdraw 包，旧 `parseApkSizeJson` 的缺包拒绝契约保持不变。

`maxLuckdrawBytes` 直接约束 package:luckdraw 的叶节点字节和，包含包归属的代码与数据，不减 baseline；父节点 value 不重复累计。AOT 总量是 arm64 AOT 子树叶节点和。Flutter 的 `Root.value` 实测为 0，不能拿它当总大小；另记录的压缩条目合计不含 ZIP 目录，也不等于可归属 AOT 大小。

Windows 每次真实构建前检查 `FreePhysicalMemory >= 4194304 KiB`。临时 Gradle 工程通过 `org.gradle.workers.max=2`（等价于 Gradle `--max-workers=2`）限制最多两个 worker、1536 MiB heap、512 MiB metaspace、256 MiB code cache，并设置 `org.gradle.daemon=false`、Kotlin 同进程编译。用唯一的 `-XX:HeapDumpPath=luckdraw_treeshake_<owner>.hprof` 标记识别自有 Gradle/Kotlin 命令行（没有开启 heap dump），加上 Flutter 命令后代清理；不会按 java 进程名结束进程。普通 `-D` 属性实测会被 Gradle 从 daemon 命令行移除，因此没有用它来判断所有权。

仍可显式复核本次保存的报告，`--size-json` 模式要求单个 `--probe`：

```powershell
dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=wheel_only --size-json=build/treeshake-apk/wheel_only.json
```

下文 B13b/B13c 的“APK 未运行/未校准”等是当时的历史结论；本批当前事实见末尾「APK 实测记录」。Web 的实测及双压缩器预算没有改动。

## 首轮实测记录（B13b 历史）

日期：2026-11-10（Asia/Shanghai）。Flutter 3.47.0 stable，framework 4cf24164269a5ebf0c16a028a00727d0e77bbb05；Dart 3.13.0。使用 B13b 指定的 w-ts2 副本，通过现有 `buildWebProbe` 串行尝试全部 10 个探针，注入构建前内存检查、命令五分钟超时与 GNU gzip 实测；没有修改 `lib/`。所有临时工程均已删除。

构建命令：`flutter build web --release --source-maps --no-pub`。每次构建完成、删除工程之前，实际执行 `gzip -9 -n -c build/web/main.dart.js`；`-n` 去掉文件名和时间戳头，固定字节统计口径。原始体积只统计 main.dart.js，不含 sourcemap、CanvasKit 和其它 Web 资源。

| 探针 | main.dart.js / B | GNU gzip -9 / B | GNU 增量 / B | GNU 增量预算 / B | Dart 增量预算 / B | 构建耗时 / s | 源码/符号检查 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| baseline | 1181712 | 359912 | 0 | 0 | 0 | 39.520 | 通过 |
| wheel_only | 1319121 | 403405 | 43493 | 47843 | 48528 | 53.958 | 通过 |
| grid_only | 1129484 | 365539 | 5627 | 6190 | 6005 | 56.849 | 通过 |
| slot_only | 1133269 | 366609 | 6697 | 7367 | 7572 | 32.512 | 通过 |
| capsule_only | 1133143 | 366771 | 6859 | 7545 | 7408 | 46.747 | 通过 |
| number_wheel_only | 1120318 | 362130 | 2218 | 2440 | 2935 | 62.066 | 通过 |
| lots_only | 1126151 | 364099 | 4187 | 4606 | 4873 | 45.831 | 通过 |
| lotto_only | 1123683 | 363311 | 3399 | 3739 | 4294 | 67.491 | 通过 |
| compat_wheel | — | — | — | 未校准 | 未校准 | 40.9（Flutter 日志） | 构建失败，未检查 |
| all_games | 1353784 | 435892 | 75980 | 83578 | 83831 | 33.181 | 通过 |

9 个成功构建的源码/符号违规总数：0。baseline 不含 luckdraw 源文件；七个单玩法没有其它玩法/compat/testing；slot_only 没有 lever 文件与符号。**compat_wheel 未通过构建，不能声明十个探针全部通过**。

GNU gzip 的单玩法 < all_games × 60% 关系检查：通过。Dart codec 同一关系检查：通过。这是额外的体积关系门禁，不能以预算校准替代。

完整证据见 [first_measurement.json](first_measurement.json)：包含每个成功探针的保留源码清单、被检查的符号、违规列表、两种压缩器的字节数、构建时间、构建前可用内存；失败探针单独保存失败原因，不伪造源码清单和体积。表中成功构建耗时为 Flutter build 命令的实测墙钟时间，含命令启动、不含工程创建、pub get、进程清理和 gzip；失败耗时来自 Flutter 的 40.9s 日志。

### B13b 当时的未完成与口径冲突（当前进展见 B13c）

- compat_wheel：副本以及检查时的真实仓库均缺少 `lib/src/compat/wheel_compat.dart`，`lib/compat.dart` 未导出 `wheelFromLuckyCanvasConfig`；编译报 `lib/main.dart:9:18: Error: Method not found: 'wheelFromLuckyCanvasConfig'.`。这是前置实现缺失，尚未进入 sourcemap 摇树检查，不能据此推断 import 泄漏。保留其 Web 预算 null，等待主会话落地 T4.2 后补测；本批未改 lib。
- 压缩器：IMPLEMENTATION_GUIDE T4.7 使用 Dart `GZipCodec(level: 9)`；B13b 要求 GNU `gzip -9`。二者输出不等长，number_wheel_only 的 GNU 增量为 2218 B、Dart 增量为 2668 B，GNU 预算 2440 B 不能直接用于现有 Dart 门禁。保守保留原 CLI 契约，分别按各自实测 × 1.1 校准；未修改脚本或放宽乘数。建议文档明确预算绑定的压缩器，后续如统一到 GNU，再单独修改 CLI 与跨平台执行策略。
- B13b 当时记录：IMPLEMENTATION_GUIDE §2.3 没列 `tool/treeshake/probes/**` 的分析排除项，已验收 B13a 配置及 runner 测试依赖该项。pub get 后核对配置未发生变化，本批保留该项，不回拷 analysis_options.yaml；建议主会话在 T4.8 文档对齐时补录。
- APK 未执行，全部 APK 预算仍为 null；CI 工作流不属本批拥有路径，本批未改。

### B13b 当时的门禁复核

指定副本的真实输出（2026-11-10）：

- `flutter test --no-pub --concurrency=1 --coverage --coverage-path=coverage/B13b.lcov --reporter=expanded`：788/788，通过，耗时 3 分 34 秒。本批相关测试 32 条（解析器 20、runner 9、实测记录 3），其中新增 3 条，任务卡规定的三个解析器测试名保持不变。
- 将本批独立 lcov 复制到副本的 `coverage/lcov.info` 后，`dart run tool/coverage.dart --min=100`：`TOTAL: 6026/6026 (100.00%)`，`PASS: coverage >= 100.0%`。无新增豁免，未改覆盖率工具。
- `dart format lib test tool` 及 `dart format --output=none --set-exit-if-changed lib test tool`：`Formatted 274 files (0 changed)`。
- `dart run tool/check_imports.dart`：`PASS: 141 lib files; IMP-R1…R12`。
- `dart run tool/check_acceptance.dart`：`PASS: 1063 references resolve; 788 registered tests all mapped`；矩阵只追加本批六个需求编号行，依 D6 标“已落地”，compat 行明确注明未验收。
- `flutter analyze --no-pub tool/treeshake test/tool/treeshake_parser_test.dart test/tool/treeshake_runner_test.dart test/tool/treeshake_measurement_test.dart`：`No issues found!`。
- 全包 `flutter analyze --no-pub`：**2 issues found，未达到全包 0 issue**。均为既有、非本批路径的 `unnecessary_import`：`test/capsule/capsule_motion_test.dart:8:8`、`test/lotto/lotto_contract_test.dart:7:8`，因为 extend.dart 已导出 swirl_mixer 的符号，额外的私有源码 import 多余。本批未修改这两个文件；建议对应负责人删除冗余 import。此问题与 compat 探针的编译失败分别记录。

哈希核对确认本批未改副本 `lib/`、pubspec.yaml、analysis_options.yaml，也未改 check_treeshake.dart；没有 core_patch.diff。所有探针工程逐一清理，没有并行启动本批构建。

## B13c 真实 Web 补测（2026-11-10）

本批基于 w-ts3 副本（包含三个 compat 转换函数），没有修改 lib 或 pubspec，也未执行 APK/Gradle。仍用上述命令，调用现有 `buildWebProbe` 的 command 注入点执行真实命令并采集内存、GNU gzip；真实解析结果完整传给 `checkProbe` 后再记录检查符号子集。baseline 与 B13b 完全相同（GNU 359912 B、Dart 360350 B），三项复验可直接核对增量。每个工程构建后立即删除；以下耗时含 Flutter 命令启动与其后代进程清理，不含工程创建/pub get。

| 探针 | main.dart.js / B | GNU gzip -9 / B | GNU 增量 / B | Dart gzip / B | Dart 增量 / B | 构建耗时 / s | 构建前空闲 / KiB | 源码/符号检查 | Dart 预算 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 1181712 | 359912 | 0 | 360350 | 0 | 18.754 | 9743384 | 通过 | 通过 |
| compat_wheel | 1197019 | 386367 | 26455 | 387307 | 26957 | 22.327 | 9915688 | 通过 | 通过 |
| lotto_only | 1124941 | 363801 | 3889 | 364767 | 4417 | 23.291 | 9174984 | 通过 | 超旧预算 123 B |
| wheel_only | 1323903 | 405082 | 45170 | 405853 | 45503 | 19.329 | 10679120 | 通过 | 通过 |

- compat_wheel 保留 49 个包内源文件，且包含 core、wheel、compat；不存在 grid/slot/capsule/number_wheel/lots/lotto 源文件，也无对应受检查类型或两个无关转换函数。预算已按增量 ×1.1 向上取整：Dart `ceil(26957 × 1.1) = 29653 B`、GNU `ceil(26455 × 1.1) = 29101 B`。
- wheel_only 保留 42 个包内源文件，没有 lotto 源码或 lotto/cubic 相关受检查符号。Dart 增量 45503 B，小于原预算 48528 B；GNU 增量 45170 B，小于原预算 47843 B。
- lotto_only 保留 32 个包内源文件，没有其它玩法源码/符号；合法 cubic 即使被内联而未留名字也不影响规则正确性。但 **Dart 增量 4417 B 超过原预算 4294 B（123 B）**，GNU 增量 3889 B 也超过旧独立预算 3739 B（150 B）。这是当前源码相对 B13b 的真实体积回归，本批只校准 compat，保留 lotto 旧上限并如实记录失败；不能宣称 lotto 的整个 CLI/体积门禁通过。
- 四次构建前 FreePhysicalMemory 均 ≥3145728 KiB。构建、工程创建和 pub get 都串行执行；每条命令限时五分钟，pub get 后立即检查/恢复分析配置。工程清理已逐项记录，按命令 PID 清理后代，无批量按进程名结束操作。

当前十个探针都有成功 Web 构建证据（B13b 九个 + B13c compat），并有 B13c wheel/lotto 复验；这不是十个探针在同一源码快照上重新验收。保留 [first_measurement.json](first_measurement.json) 的原始失败记录，补测见 [recheck_measurement.json](recheck_measurement.json)。当前预算的 compat 项指向补测记录，wheel/lotto 仍使用首轮预算。测试验证真实记录的源码/符号结论与预算结果可复现，包括 lotto 的已知超预算；通过该测试不会隐藏 CLI 的失败。

### 文档与 CI 待主会话对齐

- TEST_STRATEGY §8.2 的通用 cubic 禁符号表及 B16 冲突说明、IMPLEMENTATION_GUIDE T4.7 与 ARCHITECTURE §17.4 的待实测描述已落后于本批事实。本批授权只改工具/测试/矩阵，保留这些设计文档，建议同步为按探针允许集、compat 已补测、lotto 仍超旧预算。
- TEST_STRATEGY §8.3 的“全部预算 null”已过时；Web 十项均有预算，APK 仍全部 null。建议同时明确 Dart 与 GNU 两种压缩器分别校准，避免把 GNU 预算误用于 Dart CLI。
- 当前 IMPLEMENTATION_GUIDE §2.3 已包含 `tool/treeshake/probes/**`；B13b 历史段落的缺排除项问题现已解决。本批 pub get 后检查配置一致，未回拷分析配置。
- 已只读核对真实仓库 `.github/workflows/luckdraw-ci.yml`：treeshake-apk 的 Probes 仍调用 `dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=wheel_only`，确实缺 `--size-json=<真实报告路径>`。建议 F1 先生成/取得真实 wheel_only analyze-size JSON，再显式传该参数；已有报告解析不能替代真实 APK 构建。本批未改 workflow，未执行 APK/Gradle。

### B13c 副本最终门禁

- `flutter analyze`：`No issues found! (ran in 5.1s)`，0 issue。
- `dart format lib test tool` 与 `dart format --output=none --set-exit-if-changed lib test tool`：均 `Formatted 317 files (0 changed)`。
- `flutter test --no-pub --concurrency=1 --coverage --coverage-path=coverage/B13c.lcov --reporter=expanded`：`02:57 +959 ~2: All tests passed!`，959 条通过、2 条既有 skip；本批 37 条（解析器 24、runner 9、实测记录 4），新增 5 条。任务卡三个既有解析器测试名称原样保留。
- `dart run tool/coverage.dart --min=100 --lcov=coverage/B13c.lcov`：`TOTAL: 6677/6677 (100.00%)`，`PASS: coverage >= 100.0%`；没有新增豁免。
- `dart run tool/check_imports.dart`：`PASS: 144 lib files; IMP-R1…R12`。
- `dart run tool/check_acceptance.dart`：`PASS: 1287 references resolve; 969 registered tests all mapped`。静态登记数与上面的真实执行统计分别保留，不拿静态扫描数替代真实测试通过数。
- 首轮测试中本批引入的变量误引用、预算说明文字断言失败及一条 analyze info 均已修正；以上为修正后的最终完整复跑。lotto 的真实预算失败独立保留，未改 lib、未放宽它的旧预算。

按 D6 仅追加三条 B13C 验收行，状态为“已落地”；覆盖 R6-02/R6-04/R6-05/R6-06/R7-09 的本批用例与真实产物证据。遵循 D8，把旧文档描述与实测偏差留给主会话对齐。没有 core_patch.diff；未改 lib/core、其它玩法、workflow，也未 add/commit/push。

## APK 实测记录

日期：2026-11-10T16:52:13+08:00（Asia/Shanghai）。Flutter 3.47.0 / Dart 3.13.0、JDK 21.0.5、Gradle 9.3.1。全部来自 w-apk 副本同一 lib 快照，SHA-256 为 `ade1833d34cae2c4c3634b125ace45e6cd83131b10aa882eb2967d5e5dc22760`；没有修改 lib 或依赖。

本机及 CI 的命令完全一致：

```powershell
dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=baseline,wheel_only,grid_only,slot_only,all_games
```

本次命令真实返回 `PASS: treeshake apk (5 probes)`；五次 arm64 release 构建全部成功，源码/符号违规总数为0。包字节数包含包归属的代码与VM数据，AOT总量包含全部包；两者都不是APK文件大小。

| 探针 | package:luckdraw / B | arm64 AOT总量 / B | 包预算 / B | 保留源文件 | 构建前空闲 / KiB | 全流程 / ms | 隔离检查 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| baseline | 0 | 1678480 | 0 | 0 | 7084108 | 129645 | 通过 |
| wheel_only | 59255 | 1880720 | 65181 | 43 | 7686312 | 110211 | 通过 |
| grid_only | 49040 | 1701696 | 53944 | 42 | 9631604 | 82576 | 通过 |
| slot_only | 61273 | 1723904 | 67401 | 46 | 8294420 | 90834 | 通过 |
| all_games | 243766 | 2271152 | 268143 | 109 | 8765544 | 121188 | 通过 |

所有预算使用精确 `ceil(bytes × 11 / 10)`；例如 grid 的49040 B对应53944 B，避免二进制浮点的额外1 B。baseline包大小与预算为0。首批当时其余五个APK探针未单独构建；后续逐项补测见下文 APK2 实测记录，不能以 all_games 成功代替单玩法隔离验收。

完整摘要见 [apk_measurement.json](apk_measurement.json)：保存所有保留源文件/包内节点名称、零违规列表、AOT大小、内存、耗时与原始报告SHA-256。副本 `build/treeshake-apk/` 保留五份完整原始报告；临时Android工程、Gradle/Kotlin自有进程及本次外部报告均在返回前清理，历史DevTools报告保留。

真实报告校准中，旧解析器先后拒绝了分层目录与VM数据叶节点；这些属于已取证的报告结构差异，没有当作代码泄漏，也没有修改lib。最终解析器按节点标记与类型名形状验证数据叶，`<CodeSourceMap>`属于有效VM数据类型；字段/类型/字节不符仍显式失败。[apk_wheel_tree.json](fixtures/apk_wheel_tree.json)是从真实wheel报告裁剪的回归夹具：保留目录/VM数据结构，库实现及其它包只折叠为原叶节点和，注释明确了裁剪范围。

CI仅修改treeshake-apk作业，恢复非PR条件、JDK21并执行上面的五探针命令；YAML语法通过本机PyYAML解析。远程GitHub作业尚未执行。

文档对齐建议：ARCHITECTURE §17.4、IMPLEMENTATION_GUIDE T4.7、TEST_STRATEGY §8/§10仍描述APK只解析已有报告，应同步自动流程、五项已测/五项未测及真实目录/VM数据结构。既有Web实测测试名中的“apk remains uncalibrated”按只追加矩阵约束保留历史名称，已移除全APK必须null的过时断言；当前APK预算由独立实测测试严格验证，建议T4.8统一改名并同步旧矩阵引用。


### APK 批次门禁

副本串行分组运行：core 411、玩法403、工具/parity/testing 194、实测证据3，共1011条通过、0跳过；各命令耗时分别123536/276722/98385/2083ms。首次全包命令超过五分钟后终止，未把中断结果计入最终通过数。覆盖率使用独立文件，按SF/DA合并各组命中数；`dart run tool/coverage.dart --min=100 --lcov=coverage/APK.lcov`实际输出 `TOTAL: 6677/6677 (100.00%)`、`PASS: coverage >= 100.0%`，没有新增豁免。

`flutter analyze --no-pub`输出 `No issues found!`；格式检查 `Formatted 329 files (0 changed)`。`check_imports.dart`输出 `PASS: 144 lib files; IMP-R1…R12`。`check_acceptance.dart`静态模式及`--from-json coverage/APK.tests.jsonl`均输出 `PASS: 1378 references resolve; 1032 registered tests all mapped`；分组JSON合并时只重编号ID并合并成功done，保留真实测试名和结果，1032含21个独立工程的静态登记，不拿它替代1011条本包真实测试。

本批新增19条测试（APK runner 16、实测证据3），相关五文件最终复跑56/56通过。矩阵仅追加APK-01～APK-20，依D6标“已落地”。保留历史Web测试名是D8保守做法，建议随文档/矩阵统一对齐。未改lib、pubspec或覆盖率工具，没有core_patch.diff。

## APK2 实测记录

日期：2026-11-10（Asia/Shanghai）；最后完成时间：2026-11-10T17:17:53.8665631+08:00。在真实仓库 `E:\workspaces\dart-labs\luckdraw` 逐项执行剩余五个探针，Flutter/Dart/JDK/Gradle 版本与首批相同。源码 SHA-256 仍为 `ade1833d34cae2c4c3634b125ace45e6cd83131b10aa882eb2967d5e5dc22760`，与首批一致；未修改 lib 或依赖。

以下五条命令各自真实返回 `PASS: treeshake apk (2 probes)`。每次只选择一个待补测探针，工具另构建一次 baseline，因此本批实际串行完成十次 arm64 release 构建，没有重建首批 wheel/grid/slot/all_games。

```powershell
dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=capsule_only --update-budgets
dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=number_wheel_only --update-budgets
dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=lots_only --update-budgets
dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=lotto_only --update-budgets
dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=compat_wheel --update-budgets
```

`--update-budgets` 先执行源码/符号隔离检查，成功后只回填 APK 数字上限；实测字节、日期和报告来源同步补入预算记录。所有上限仍使用整数公式 `(bytes * 11 + 9) ~/ 10`。十个探针的 APK 预算现在全部非 null，baseline 为 0；Web 预算未改。

| 探针 | package:luckdraw / B | arm64 AOT 总量 / B | 包预算 / B | 源文件数 | 构建前空闲 / KiB | 全流程 / ms | 测量批次 | 隔离检查 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 0 | 1678480 | 0 | 0 | 7084108 | 129645 | APK（首批） | 通过 |
| wheel_only | 59255 | 1880720 | 65181 | 43 | 7686312 | 110211 | APK（首批） | 通过 |
| grid_only | 49040 | 1701696 | 53944 | 42 | 9631604 | 82576 | APK（首批） | 通过 |
| slot_only | 61273 | 1723904 | 67401 | 46 | 8294420 | 90834 | APK（首批） | 通过 |
| capsule_only | 61045 | 1721296 | 67150 | 41 | 8650540 | 82141 | APK2 | 通过 |
| number_wheel_only | 51517 | 1721120 | 56669 | 37 | 8901364 | 93475 | APK2 | 通过 |
| lots_only | 46658 | 1715088 | 51324 | 38 | 10333500 | 97364 | APK2 | 通过 |
| lotto_only | 60034 | 1732976 | 66038 | 36 | 9775492 | 103004 | APK2 | 通过 |
| compat_wheel | 125073 | 2203808 | 137581 | 51 | 12090668 | 87551 | APK2 | 通过 |
| all_games | 243766 | 2271152 | 268143 | 109 | 8765544 | 121188 | APK（首批） | 通过 |

本批十次构建前可用内存最低为 8588032 KiB，均满足 4194304 KiB 门槛。Gradle 使用 `org.gradle.workers.max=2`（等价于 `--max-workers=2`），每次只有一个自有 Gradle 构建；与 `C:\ldd` 的真机任务并行时未触碰其进程。五次 baseline 的 luckdraw 均为 0 B，arm64 AOT 总量均为 1678480 B。

新增五项包子树的无关源码/受检查符号违规总数为 0。lotto_only 按既有允许集允许 CubicEasing；compat_wheel 确实含 wheel 与 compat，只保留 core/wheel/compat 三个源码区，不含其它六个玩法。

[apk_measurement.json](apk_measurement.json) 顶层保留首批来源；新增探针逐项记录 measuredAt、invocation、libSha256，supplement 保存五次命令与五份 baselineRechecks，避免把补测写成首批同一次调用。每项均保存完整包源码与节点名、零违规、内存及原始报告 SHA-256。新增五份完整原始报告在本工作目录 `build/treeshake-apk/<probe>.json`，逐次 baseline、命令输出和测量摘要保留在 `build/treeshake-apk/APK2/`。临时工程与本次外部 DevTools 报告已由工具逐项清理。

设计文档对齐建议（D8）：ARCHITECTURE §17.4、IMPLEMENTATION_GUIDE T4.7、TEST_STRATEGY §8/§10 中 APK 仅解析已有报告、预算全部 null、CI 停用等描述已过时，应由主会话对齐自动构建、十项实测及当前 CI 状态。本批未改 docs 或 workflow；CI 当前仍选择首批五项，建议后续将新增五项纳入。历史测试名中的 apk remains uncalibrated 按本批要求保留，断言已禁止十项 APK 预算为空，建议 T4.8 统一改名与矩阵引用。

### APK2 批次门禁

- `flutter pub get --no-example` 成功；紧接着核对 analysis_options.yaml，前后 SHA-256 均为 `30b28094d68b7139051b32786a999fe657467c5c1c6c85856dbb323b3afbc214`，无需恢复。
- `flutter analyze --no-pub`：`No issues found! (ran in 16.8s)`，0 issue。
- `dart format lib test tool`：`Formatted 329 files (0 changed) in 2.56 seconds.`；`dart format --output=none --set-exit-if-changed lib test tool`：`Formatted 329 files (0 changed) in 1.77 seconds.`。
- `flutter test test/tool --no-pub --concurrency=1 --reporter=expanded`：`00:29 +160: All tests passed!`，160 条通过、0 跳过。摇树相关 58 条：APK 实测 5、APK runner 16、Web 实测 4、解析器 24、Web runner 9；新增 2 条实测回归，既有测试名称全部保留。
- `dart run tool/check_imports.dart`：`PASS: 144 lib files; IMP-R1…R12`。
- `dart run tool/check_acceptance.dart`（静态）：`PASS: 1404 references resolve; 1034 registered tests all mapped`；矩阵仅追加 APK2-01～APK2-13，按 D6 标「已落地」。登记数不替代真实测试执行数。
- 五项真实 CLI 命令各输出 `PASS: treeshake apk (2 probes)`；随后分别用 `--size-json=build/treeshake-apk/<probe>.json` 复验，每项均输出 `PASS: treeshake apk (1 probes)`，实际执行了非更新模式的预算检查。
- 十份原始报告（新增五项及其五次 baseline）的 SHA-256 均与记录相符。146 个文件（lib 下 144 个 Dart 文件、pubspec.yaml、analysis_options.yaml）的前后哈希完全一致。临时 ldts 工程为空；按命令行核查未发现本批遗留的 Dart/flutter_tester 或 Gradle/Kotlin 进程，保留其它任务进程。
- 按 APK2 分工未运行全包测试和覆盖率门禁，由主会话负责；没有新增覆盖率豁免。未改 lib、依赖、其它工具或 workflow，未 add/commit/push；结束核对仓库最近两条提交仍为 `443589a3`、`f0b64ae1`。
