# B11b / T4.6 验证与拷回清单

以下结论为指定 w-bench/luckdraw 副本的实际执行结果；未运行任何真机、模拟器、flutter build 或 Gradle 命令。

| 验证 | 实际结果 |
| --- | --- |
| bench/flutter analyze --no-pub | No issues found! |
| flutter analyze --no-pub test/tool | No issues found! |
| 主包 flutter analyze --no-pub | 2 info：capsule_motion_test.dart:8、lotto_contract_test.dart:7 的 unnecessary_import；既有路径，未修改 |
| dart format --output=none --set-exit-if-changed lib test tool | 279 files (0 changed) |
| 本批 flutter test test/tool/bench_metrics_test.dart test/tool/bench_compare_test.dart --no-pub --concurrency=1 | 25 passed |
| 全包 flutter test --no-pub --concurrency=1 --coverage --coverage-path=coverage/B11b.lcov | 791 passed，2 既有 skip，3m19s |
| dart run tool/coverage.dart --min=100 | TOTAL: 5722/5722 (100.00%)；PASS；先将隔离采集复制到 coverage/lcov.info |
| dart run tool/check_imports.dart | PASS: 136 lib files; IMP-R1…R12 |
| dart run tool/check_acceptance.dart | PASS: 1073 references resolve; 801 registered tests all mapped |

无新增覆盖率豁免。10 条真机基准只注册、静态分析并登记矩阵，没有执行；8 条保留任务卡原名，追加 slot raster 与 lots 两条。

原始证据位于副本 coverage/B11b-test.log、B11b.lcov、B11b-coverage.log、B11b-coverage-default.log、B11b-analyze.log。

D6：矩阵新行标已落地，注明真机未验。D8：文档缺口见 README 的当前文档缺口与保守处理。未修改 lib 或其它玩法目录；没有 core_patch.diff；未修改 CHANGELOG；无 add、commit 或 push。

## 拷回清单

除 test/ACCEPTANCE.md 为重新读取真实当前内容后单次追加外，下列均为不存在冲突的新文件。忽略 .dart_tool/.idea/build/pubspec.lock/local.properties/Gradle 包装器缓存与生成注册器。

- test/ACCEPTANCE.md（仅追加 B11b 章节）
- test/tool/bench_compare_test.dart
- test/tool/bench_metrics_test.dart
- tool/bench/.gitignore
- tool/bench/.metadata
- tool/bench/analysis_options.yaml
- tool/bench/android/.gitignore
- tool/bench/android/app/build.gradle.kts
- tool/bench/android/app/src/debug/AndroidManifest.xml
- tool/bench/android/app/src/main/AndroidManifest.xml
- tool/bench/android/app/src/main/kotlin/com/example/luckdraw_bench/MainActivity.kt
- tool/bench/android/app/src/main/res/drawable-v21/launch_background.xml
- tool/bench/android/app/src/main/res/drawable/launch_background.xml
- tool/bench/android/app/src/main/res/mipmap-hdpi/ic_launcher.png
- tool/bench/android/app/src/main/res/mipmap-mdpi/ic_launcher.png
- tool/bench/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
- tool/bench/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
- tool/bench/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
- tool/bench/android/app/src/main/res/values-night/styles.xml
- tool/bench/android/app/src/main/res/values/styles.xml
- tool/bench/android/app/src/profile/AndroidManifest.xml
- tool/bench/android/build.gradle.kts
- tool/bench/android/gradle.properties
- tool/bench/android/gradle/wrapper/gradle-wrapper.properties
- tool/bench/android/settings.gradle.kts
- tool/bench/budgets.json
- tool/bench/budgets.status.json
- tool/bench/compare.dart
- tool/bench/integration_test/bench_support.dart
- tool/bench/integration_test/capsule_bench_test.dart
- tool/bench/integration_test/grid_bench_test.dart
- tool/bench/integration_test/lots_bench_test.dart
- tool/bench/integration_test/lotto_bench_test.dart
- tool/bench/integration_test/memory_bench_test.dart
- tool/bench/integration_test/number_wheel_bench_test.dart
- tool/bench/integration_test/slot_bench_test.dart
- tool/bench/integration_test/wheel_bench_test.dart
- tool/bench/lib/main.dart
- tool/bench/metrics.dart
- tool/bench/pubspec.yaml
- tool/bench/README.md
- tool/bench/test_driver/perf_driver.dart
- tool/bench/VALIDATION.md
