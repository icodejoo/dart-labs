# 最低版本验证报告（MIN）

验证日期：2026-11-10（Asia/Shanghai）。本报告只代表本机 Windows 实测，不代表 GitHub Actions、Linux 或真机结果。最低版本非 golden 验证通过；没有需要修改的 lib/test API 或 Dart 语法。含 golden 的最低版本运行有一项独立记录的像素差异。

## 环境与隔离

- 最低 SDK：`C:/f324/flutter`，Flutter 3.24.5，framework `dec2ee5c1f`，engine `a18df97ca5`，Dart 3.5.4，DevTools 2.37.3。本地标签克隆显示 channel `[user-branch]` / unknown source；实际版本及提交如上，没有切换原 SDK。
- 原开发 SDK：`E:/sdk/flutter`，Flutter 3.47.0，framework `4cf2416426`，Dart 3.13.0。
- 短路径副本：`C:/f324/pkg`，复制 lib、test（包含 parity 基线）、tool、docs、pubspec.yaml、analysis_options.yaml、dart_test.yaml，以及测试直接读取的 README.md；没有复制 example。
- 完整夹具副本：`C:/Users/jelon/AppData/Local/Temp/claude/E--workspaces-dart-labs/e3ced25f-603c-40bf-996d-463062b405ea/scratchpad/w-min/luckdraw`（以下称“工作副本”）。此目录原已包含 example 源码；最终完整测试在此执行，未新增复制 example，也未构建或安装 example。
- 依赖镜像：`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、`PUB_HOSTED_URL=https://pub.flutter-io.cn`。每次运行明确设置 `FLUTTER_ROOT`，并将所测 SDK 的 bin 放到进程 PATH 首位，使测试辅助调用的 dart 也来自相同 SDK。
- 原始日志、下载和一次性探针在 `C:/f324/`。没有修改 SDK 源码，没有新增包依赖，没有改公共 API、覆盖率规则、golden 基线或容差。

SDK 克隆命令：

```powershell
git clone --depth 1 --branch 3.24.5 file:///E:/sdk/flutter C:/f324/flutter
```

首次启动确认 Dart 压缩包为 212554381 字节后，停止该次自动单连接下载及其对应 BITS 任务，改用 `aria2c -x16 -s16 -k8M --continue=true --max-tries=0 --retry-wait=3`，同时提供 storage.flutter-io.cn / storage.googleapis.com 下载地址，解压并按 SDK 自带脚本写入 engine-dart-sdk.stamp。Windows 测试引擎包约 28 MiB，亦通过 aria2 下载；随后执行 `flutter precache --universal --no-android --no-ios --no-web --no-windows --no-linux --no-macos --no-fuchsia`。3.24 的 universal 集合仍附带少量 Gradle wrapper / iOS 主机工具，但没有预缓存 Android/iOS 引擎或执行 build。

## 命令与复现

最低版本先在短路径副本安装并分析：

```powershell
cd C:/f324/pkg
$env:FLUTTER_ROOT='C:/f324/flutter'
$env:PATH='C:/f324/flutter/bin;' + $env:PATH
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
& C:/f324/flutter/bin/flutter.bat pub get --no-example
# 紧接上一步逐字节检查 analysis_options.yaml；发生变化立即恢复 §2.3 内容。
& C:/f324/flutter/bin/flutter.bat analyze --no-pub
```

工作副本已有 example 源码。最低版本的 Flutter pub 后处理问题见下一节；使用已实测的 Dart pub 命令避免安装 example：

```powershell
cd <工作副本>
& C:/f324/flutter/bin/dart.bat pub get --no-example
# 紧接上一步检查并恢复分析配置。
& C:/f324/flutter/bin/flutter.bat analyze --no-pub
& C:/f324/flutter/bin/flutter.bat test --no-pub --concurrency=1 --exclude-tags golden --reporter=json
# 上一条结束后，另跑含 golden 的完整测试；不更新基线。
& C:/f324/flutter/bin/flutter.bat test --no-pub --concurrency=1 --reporter=json
```

3.47 回归使用同一工作副本，将 FLUTTER_ROOT / PATH 改为 `E:/sdk/flutter`：

```powershell
& E:/sdk/flutter/bin/flutter.bat pub get --no-example
# 紧接检查并恢复分析配置。
& E:/sdk/flutter/bin/flutter.bat analyze --no-pub
& E:/sdk/flutter/bin/dart.bat format lib test tool
& E:/sdk/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib test tool
& E:/sdk/flutter/bin/flutter.bat test test/core test/compat test/testing --no-pub --concurrency=1 --coverage --coverage-path=coverage/MIN-347-foundation.lcov --reporter=json
& E:/sdk/flutter/bin/flutter.bat test test/wheel test/grid test/slot test/parity --no-pub --concurrency=1 --coverage --coverage-path=coverage/MIN-347-upstream.lcov --reporter=json
& E:/sdk/flutter/bin/flutter.bat test test/capsule test/lots test/lotto test/number_wheel test/tool --no-pub --concurrency=1 --coverage --coverage-path=coverage/MIN-347-additional.lcov --reporter=json
# 每条结束后再运行下一条。使用本次临时聚合脚本校验三个运行均成功、文件集合互斥且覆盖全部主包测试。
python C:/f324/merge_runs.py
& E:/sdk/flutter/bin/dart.bat run tool/coverage.dart --min=100 --lcov=coverage/MIN-347.lcov
& E:/sdk/flutter/bin/dart.bat run tool/check_imports.dart
& E:/sdk/flutter/bin/dart.bat run tool/check_acceptance.dart
& E:/sdk/flutter/bin/dart.bat run tool/check_acceptance.dart --from-json C:/f324/logs/347-final-full.json
```

## 发现、分类与处理

### MIN-P01：短路径最小副本缺 example 源码夹具

初次非 golden 试跑在 `test/tool/run_integration_snippets_test.dart` 有两项 PathNotFoundException：

1. `README snippets > six Dart blocks match the independently compiled example sources`：缺 `example/lib/snippets/readme_wheel.dart`。
2. `README snippets > every example Dart import uses the exported package API`：缺 `example/lib/`。

分类：隔离副本的夹具范围问题，与 Flutter API、Dart 语法或渲染行为无关。保持测试名与断言不变，转到预先存在的工作副本执行完整测试。没有新增 skip，没有降低覆盖率，没有把试跑计作完整通过。

初次试跑另外没有将所测 SDK 加到 PATH 首位，部分工具测试因此启动了原开发 SDK 的 dart。运行至 277.9 秒、854 通过 / 2 失败且尚未结束时主动终止，清理其自有进程树；它没有 done 事件，不能作验收结果。后续统一设置 FLUTTER_ROOT 和 PATH，重新完整运行。

### MIN-P02：Flutter 3.24.5 的 `pub get --no-example` 后处理

短路径副本无 example，命令退出码 0。工作副本有 example/pubspec.yaml 但没有 example/.dart_tool/package_config.json；该命令完成主包依赖解析后仍读取 example 配置，报以下错误并退出 1：

```text
example/.dart_tool/package_config.json does not exist.
Did you run this command from the same directory as your pubspec.yaml file?
```

分类：Flutter 3.24.5 工具行为差异，不是 lib 或测试使用新 API。定位到 SDK 只读源码 `packages/flutter_tools/lib/src/dart/pub.dart` 的 `_updateVersionAndPackageConfig`，其更新 example 配置的条件没有遵守 --no-example。

保守处理：不安装 example、不修改 SDK。在 `C:/f324/pubprobe` 的新鲜配置中，以正确 FLUTTER_ROOT 运行 `C:/f324/flutter/bin/dart.bat pub get --no-example`，实测退出 0、主包配置生成、example 配置仍不存在。最低版本 CI 只将依赖命令改为同一条 Dart pub 命令，保留 3.24.5、分析配置保存恢复、analyze --no-pub 和串行非 golden 测试。其它作业不变。

### 编译与语言兼容

3.24.5 初次 analyze：`No issues found! (ran in 19.8s)`。工作副本正式 analyze：`No issues found! (ran in 28.5s)`。error / warning / info / deprecated 诊断均为 0，没有缺失 API 或 Dart 3.5 不支持的语言特性需要修复。lib/test 兼容代码改动为 0，因而没有 core_patch.diff；不得为没有发生的问题制造兼容分支。

### MIN-P03：最低 SDK 的 s02 图像差异

含 golden 完整运行中，`test/parity/slot_parity_test.dart :: slot parity > case s02 keyframes match upstream within tolerance` 在 `baselines/s02/kf_60.png` 失败，输出 `Pixel test failed, 7.68%, 2488px diff detected.`。随后的 `Expected: true / Actual: <null>` 是同一次 golden 异步比较失败引出的后续断言，不是另一条失败测试。

分类：SDK 版本间的图像行为差异；同一配置的 `case s02 scroll sequence matches upstream` 数值对照在非 golden 及含 golden 运行中均通过。证据只能定位到像素比较，未进一步归因到特定 Skia 实现。按照本批验收约定，该项仅记录，不作为最低版本非 golden 失败依据；不更新图片、不放宽容差、不加入 skip。

### MIN-P04：3.47 整包覆盖率命令的五分钟限制

3.47 最初尝试单条整包覆盖率命令，仍在持续推进且未记录测试失败，但至 296.4 秒仍未结束。遵守单命令五分钟上限，提前终止并清理该命令的自有进程树。原始不完整日志保留为 `C:/f324/logs/347-aborted-full.json`，不计入通过数或覆盖率。

保守处理：按上述三个互不重叠的目录集合重跑；每组串行、各有独立 JSON / lcov。临时聚合脚本先断言每组 done.success=true、测试开始结束记录完整、没有失败、测试文件互斥且并集恰为主包全部 130 个测试文件，然后汇总计数。lcov 记录原样串接，现有 coverage 门禁按 SF / DA 累加，不制造命中、不修改门禁；JSON 只统一 ID 编号与累计时间，合并 done 表示三个真实成功运行的合取，供现有 JSON 矩阵门禁使用。聚合文件明确是分组证据，不声称单条整包命令成功。

原始分组日志、lcov 路径、SHA-256、通过数、文件数和耗时另存 `C:/f324/logs/347-merge-manifest.json`；临时 Python 脚本仅使用标准库，不写入仓库、不改变依赖。

## 最终实测结果

| 检查 | 实际输出 / 结果 |
| --- | --- |
| 3.24.5 短路径 Flutter pub get | 退出 0；分析配置逐字节未变 |
| 3.24.5 工作副本 Dart pub get | `Got dependencies!`，退出 0；分析配置未变 |
| 3.24.5 analyze | `No issues found! (ran in 28.5s)`，退出 0 |
| 3.24.5 非 golden 完整测试 | **951 通过 / 0 失败 / 0 跳过**；done.success=true，243000ms，退出 0 |
| 3.24.5 含 golden 完整测试 | **991 通过 / 1 失败 / 0 跳过**；done.success=false，209442ms，退出 1；唯一失败为 MIN-P03，仅作观察 |
| 3.24.5 import 门禁 | `PASS: 144 lib files; IMP-R1…R12`，退出 0 |
| 3.24.5 阶段静态矩阵门禁 | `PASS: 1367 references resolve; 1013 registered tests all mapped.`，退出 0；分组命令补充及 MIN-06 换行修正后，以最终 1370 条引用为准 |
| 3.47 format | `Formatted 326 files (0 changed)`，写入及只读检查均退出 0 |
| 3.47 analyze | `No issues found! (ran in 11.9s)`，退出 0 |
| 3.47 基础层分组（46 文件） | **454 通过 / 0 失败 / 0 跳过**，163205ms，退出 0 |
| 3.47 上游三玩法与 parity 分组（32 文件） | **261 通过 / 0 失败 / 0 跳过**，103583ms，退出 0；包含最低版本有差异的 s02 golden |
| 3.47 追加玩法与工具分组（52 文件） | **277 通过 / 0 失败 / 0 跳过**，161242ms，退出 0 |
| 3.47 完整回归汇总 | **992 通过 / 0 失败 / 0 跳过**，130 个文件，三组均退出 0，耗时合计 428030ms；测试文件互斥并覆盖全部主包测试 |
| 3.47 最终 format 检查 | `Formatted 326 files (0 changed) in 2.16 seconds.`，退出 0 |
| 3.47 coverage 门禁 | `TOTAL: 6677/6677 (100.00%)`、`PASS: coverage >= 100.0%`，退出 0；新增豁免 0 |
| 3.47 import 门禁 | `PASS: 144 lib files; IMP-R1…R12`，退出 0 |
| 3.47 最终静态矩阵 | `PASS: 1370 references resolve; 1013 registered tests all mapped.`，退出 0 |
| 3.47 最终 JSON 矩阵 | `PASS: 1370 references resolve; 1013 registered tests all mapped.`，退出 0；输入为如上明确标注的分组聚合 JSON |

非 golden 完整测试原始记录：`C:/f324/logs/324-final-nongolden.json`；含 golden 完整测试：`C:/f324/logs/324-final-full.json`；初次不完整运行：`C:/f324/logs/324-initial-nongolden.json`。含 golden 共 992 项，其中 41 项被 golden 标签筛出，最低版本这 41 项为 40 通过 / 1 失败。失败的差异图片另存 `C:/f324/logs/324-golden-failures/`，没有拷回仓库。

JSON 的 testDone 非 hidden 事件统计实际通过数，done 事件确认完整结束，未以静态注册数替代结果。静态矩阵的 1013 个注册测试还包含独立工程，不能与主包运行计数直接比较。

## 交付范围与补丁

本批交付且仅交付以下三处；共享文件重新读取后只追加，CI 仅定点替换最低版本作业中的依赖命令：

1. `luckdraw/docs/MIN_VERSION_REPORT.md`：本报告。
2. `luckdraw/test/ACCEPTANCE.md`：追加 MIN-01…MIN-06，新增测试 0 项，既有测试名称不变。
3. `.github/workflows/luckdraw-ci.yml`：min-sdk 中 `flutter pub get --no-example` 改为 `dart pub get --no-example`，加两行中文原因注释；flutter-version 仍为 3.24.5。

可复核的统一 diff：工作副本的父目录 `../MIN_compat.diff`，仅包含上述 CI 兼容修复；已对真实仓库运行 `git apply --check`，退出 0，没有实际用 git apply 写入或暂存。lib/**、测试 Dart 源码、golden 基线、共享 fixtures、CHANGELOG、pubspec.yaml 均不回拷，没有 core_patch.diff。临时 pubspec.lock、.dart_tool、build、coverage 和差异图均留在副本，不写回真实仓库。

回拷后在真实仓库仅做相关范围复核：

| 命令 / 范围 | 实际结果 |
| --- | --- |
| format 检查 test/tool/run_integration_snippets_test.dart、test/tool/design_invariants_test.dart | `Formatted 2 files (0 changed)`，退出 0 |
| 两文件 flutter test --no-pub --concurrency=1 --reporter=json | **4 通过 / 0 失败 / 0 跳过**，12560ms，退出 0 |
| dart run tool/check_imports.dart | `PASS: 144 lib files; IMP-R1…R12`，退出 0 |
| dart run tool/check_acceptance.dart | `PASS: 1370 references resolve; 1013 registered tests all mapped.`，退出 0 |

六条 MIN 行逐条核对均独立成行且标“已落地”。收尾复核曾发现本批 MIN-06 追加时漏换行、与 MIN-05 拼接，已仅修正本批边界并重新跑过副本静态 / JSON 及真实仓库静态矩阵；最终结果均为上述 1370 条。真实仓库没有跑全包 analyze 或 coverage，遵守并行副本协议，完整结果来自隔离工作副本。

## 文档差异与建议

1. IMPLEMENTATION_GUIDE §2.5、§3.2，以及 TEST_STRATEGY §4.4、§10 仍保留“最低 SDK 待 CI 验证”的历史口径。依 D8 不修改其它并行文档；建议 T4.8 区分“本机 Windows 已实测”与“Linux / 远程 CI 未运行”，引用本报告，不能把本机通过写成远程 CI 通过。
2. “短路径不复制 example”与现有两项 README 源码检查所需夹具有冲突。保守使用已有工作副本补齐运行条件，不删除测试、不修改夹具公共文件。建议文档说明这两项是源码仓库检查，包最小副本与仓库完整测试的夹具范围不同。
3. Flutter 3.24.5 的 --no-example 后处理缺陷应在最低版本 CI 说明中记录；使用 SDK 自带 Dart pub 可避免误读配置，无需新增依赖。
4. 遵守 D1–D8：入口及状态机既有决策不变；覆盖率仍按 D2 严格执行；未改共享 fixtures；MIN-01…MIN-06 只追加，按 D6 标“已落地”；未运行 git add、commit、push。
5. 现有矩阵门禁没有拒绝上述多余表格列，初次拼接行仍返回 PASS；最终通过显式行数复核并修正。建议后续单独补充列数格式校验与回归测试；本批未越权修改 tool 或其测试。

结论：指定的 Flutter 3.24.5 / Dart 3.5.4 下 analyze 无诊断，非 golden 951 项全通过；3.47 的全部 992 项按三组验证全绿，lib 覆盖率 100%。唯一残余差异是最低版本的 s02 golden（MIN-P03），按任务要求保留并记录。Linux、远程 CI、真机，以及另行指定的 3.24.0 / Dart 3.5.0 精确补丁版本没有在本批运行；本报告不将它们写成已验证。没有需要修正的设计骨架或公共 API，建议只在最终文档对齐中补入本机实测结论、源码夹具范围和最低 CI 的 Dart pub 命令。
