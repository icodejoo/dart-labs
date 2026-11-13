# CP2 第四轮离线收口校验

2026-11-05；工作树 `E:\workspaces\wt-mova-cp2\mova`，起点 `552f21cf8eb46f72e29dbde667e23ab20b696198`。本人执行，未转派；只写 example 与 doc。只读交接依据为 `E:\workspaces\wt-mova-cp2fix\mova\doc\plans\2026-11-05-cp2-r4-offline-triage.md`，未写入该 worktree。未使用真机、adb、Gradle，未构建/安装 APK。

|校验|命令与工作目录|结果|
|---|---|---|
|example 分析基线及修改后对比|example：`flutter analyze`，修改前后各一次；修正格式产生的 3 个 lint 后再次校验|前后均 41 个既有 issue；按 info/warning/error 诊断逐行比较完全相同，未新增 issue。全量 analyze 因既有 issue 仍返回非零，不能声称全量 0 issue|
|矩阵静态检查|example/tool：`python run_matrix.py --check`|PASS；78 batches / 135 IDs / 6 manual；无设备操作|
|指定 Python 单测|example/tool：`python -m unittest test_run_matrix test_win_policy test_win_job`|77 tests OK：63 + 11 + 3；无跳过/失败|
|单文件无设备测试|example：`flutter test test/cp2_criteria_test.dart --reporter expanded`|9/9 PASS；包含 5 条原始 slot FAIL 的 Dart reducer 回放及命令延迟、缺首帧/边沿/completed 的诊断|
|离线重算|mova：`python example/tool/cp2_r4_offline.py`|逐条读取 3 个原始 run JSON，核对 FAIL ID、旧 CHECK 数字、首帧归属、原生 path/mova、playing 边沿及暂停样本；15/15 限定 PASS|
|历史保护|用 `git show 552f21cf:mova/doc/plans/2026-11-04-cp2-results.json` 与新 JSON 比较；旧 Markdown 与新文件前缀比较|除 latestRound/latestStatus 指向新节外，原有 JSON 字段及 fourthRound 全部值保持一致；旧 Markdown 全文逐字保留为前缀|
|原始证据保护|原始 JSON SHA-256 见结果报告；重算脚本只读 evidence|没有修改 coverage_evidence 中的日志/JSON，也没有伪造 run-id 或设备记录|
|范围与格式|`git diff --check`；逐项检查提交文件清单|通过；仅 example/doc，无根 lib/test、generated_plugin*、doc/notes、svgx、dioman|

本地输出保存在 `example/.dart_tool/cp2-offline-{analyze-before,analyze-after,python-tests,flutter-test}.log`，不入提交。Python 作业单测输出 unclosed stdout ResourceWarning，但 77 项均通过；没有修改这些指定单测或扩大测试范围。既有 generated_plugin* 工作区改动保留，不入提交。

离线重判前后：第四轮原新执行口径 **124 PASS / 15 FAIL / 0 BLOCKED → 139 / 0 / 0**；合并历史正式 ID **174 / 15 / 1 → 189 / 0 / 1**。15 条均标 **PASS（判据修正，离线重判）**；其中 slot 的 5 条有效墙钟误差为 **+0.225、+1.469、+40.074、+0.789、−0.012ms**，门槛保持绝对值 ≤300ms。详细首帧、边沿、累计区间、原误差及证据摘要见 [结果 JSON](2026-11-04-cp2-results.json) 的 `fourthRoundOfflineRejudgment`。

总计划 10 行逐行对账后的自动证据为 **8 PASS / 0 FAIL / 2 BLOCKED**，含人工要求的最终结论为 **4 PASS / 0 FAIL / 6 BLOCKED**。QoE 缺 `CP2.qoe.manual720.4` 原始 CHECK，仍为 9 PASS/1 BLOCKED。听音、视觉和 PiP 系统交互单列 BLOCKED；Windows 无本轮设备证据且本轮禁止运行被测应用。

偏差与边界：按本次要求仅修正旧证据的判据，未执行交接建议的新 run-id 真机复验。夹具已修改 Dart 代码，但第四轮 APK 中是旧夹具；这次重判不是新设备证据，不能证明新 APK 上的夹具实际正确采集或通过。pod2 wait/nowait、adpause/adbg 的新夹具仍需新包真机复验；人工项与 QoE 缺口仍须补证。因此 CP2 整体为 BLOCKED。
