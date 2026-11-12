# DEVFIN 真机收尾复测（2026-11-11）

仅一台 vivo V2417 / Android 16，APK 与首次会话身份见 session.json、validation/apk.json。原始脚本未通过：转盘冷帧五次仅两次 driver 成功即提前退出；续跑只执行未启动项目，不清零计数、不覆盖 runs.json，不超过每项五次。CPU 五项目均缺少有效轮。首帧数值可从原始 driver 响应恢复，但不把 driver 失败改写为通过。所有正式成本预算、RSS 与 12ms/4ms 硬门禁均未放宽。

## APK 与测量身份

APK SHA-256：`E92CFEB2366540F4FCFEE28BEB67F7899976A254BDE3048FB83C04408D17F14C`。构建指定 integration_test/pending_bench_test.dart 与 LUCKDRAW_TIMELINE=true；arm64 libapp.so 检出 pending 测试名和新增路由。首轮因 Maven JVM 证书链失败（56.372s），使用 Windows 证书库重试成功（33.427s），Gradle workers=2。没有升级依赖或关闭证书校验；临时 Gradle 属性已恢复。

## 冷 push 首帧 UI（ms）

固定取启动顺序前3份完整设备 FrameTiming；全部额外轮仍在 audit.json。计时为 FrameTiming.buildDuration，不是启动时间或纯 layout/record。wheel/grid 的 driver 汇总失败来自冷窗口缺少完整 Raster timeline 事件，恢复值来自原始 Flutter driver JSON 响应，原 valid=false 保留。

| 场景 | 前三次原值 | 中位数 | 极差 | 玩法−空白 | 增量预算 | 与原4ms差距 | driver成功/启动 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| blank_first_frame | 2.883 / 2.835 / 3.469 | 2.883 | 0.634 | — | — | — | 3/3 |
| wheel_first_frame | 47.238 / 40.970 / 37.118 | 40.970 | 10.120 | 38.087 | 41.896 | +852.175% | 2/5 |
| grid_first_frame | 10.024 / 13.403 / 31.592 | 13.403 | 21.568 | 10.520 | 11.572 | +163.000% | 1/5 |
| slot_first_frame | 3.128 / 2.577 / 7.338 | 3.128 | 4.761 | 0.245 | 0.270 | -93.875% | 3/3 |

有效增量预算为实测中位数差×1.1向上取整到0.001ms，冻结在 `budgets.status.json.devfin.first_frame_increment_budgets_ms`。wheel 比4ms多34.087ms，grid多6.520ms；不能写成达到设计目标。九宫格、老虎机三轮极差明显，标定不是稳定性或跨设备保证。既有 MET2 schema 只支持 wheel 的绝对 first_frame_ui_millis，无法表达空白基线及 grid/slot 有符号增量；因此 budgets.json 保留旧绝对信息字段并写明兼容原因，本轮有效增量预算由 DEVFIN 审计测试检查。不得将增量阈值套到旧绝对40.378ms；建议维护者另行扩展比较器 schema。

## 原生进程/线程 CPU（%）

协议为 before/start/end TCP 握手，计划五秒窗口第0/1/2/3/4秒各一次 cpuinfo+top，窗口前后各一次。每轮应取五次样本的角色/进程中位数，再取三轮中位数；单核100%，多核进程可超过100%。本次全部在 before 阶段失败，没有任何有效五秒 CPU 窗口。cpuinfo 是系统原生历史统计，不覆盖本次五秒；部分返回区间结束于采样前数分钟，匹配不到当前PID或命中旧PID。top 随后返回0线程/不被当前解析器识别的列头。不能用旧PID、框架墙钟或零值填空。

| 场景 | UI三轮 / 中位数 | Raster三轮 / 中位数 | 总进程三轮 / 中位数 | 有效/启动 | 结论 |
| --- | --- | --- | --- | --- | --- |
| cpu_wheel_steady | 缺测 / 缺测 | 缺测 / 缺测 | 缺测 / 缺测 | 0/5 | 不确定（采样链路失败） |
| cpu_grid_steady | 缺测 / 缺测 | 缺测 / 缺测 | 缺测 / 缺测 | 0/5 | 不确定（采样链路失败） |
| cpu_slot_steady | 缺测 / 缺测 | 缺测 / 缺测 | 缺测 / 缺测 | 0/5 | 不确定（采样链路失败） |
| cpu_capsule_mixing | 缺测 / 缺测 | 缺测 / 缺测 | 缺测 / 缺测 | 0/5 | 不确定（采样链路失败） |
| cpu_lotto_draw | 缺测 / 缺测 | 缺测 / 缺测 | 缺测 / 缺测 | 0/5 | 不确定（采样链路失败） |

全部25次失败原文与错误保留在各 cpu_*/cpu/；错误分类与完整轮次见 audit.json。没有统计区间足够新且进程身份正确的完整样本，不宣称完成CPU标定。

## 四场景：MET2 与本次并排

| 场景 | MET2结论；合计/UI P99最大ms | 本次未污染/总窗口 | 每轮合计P99 ms | 每轮UI P99 ms | 稳定性 | 本次结论 |
| --- | --- | --- | --- | --- | --- | --- |
| slot_raster | 失败；16.905/2.190 | 3/3 | 5.352 / 5.114 / 5.397 | 2.093 / 1.985 / 2.068 | 稳定 | 失败 |
| grid_steady | 失败；12.231/2.434 | 2/3 | 14.039 / 9.348 / 20.420（污染） | 2.222 / 2.119 / 2.193 | 稳定 | 失败 |
| lotto_draw | 失败；12.229/4.386 | 3/3 | 9.593 / 11.224 / 12.331 | 4.570 / 3.814 / 4.445 | 稳定 | 失败 |
| lots_shaking | 不确定；8.864/2.780 | 3/3 | 6.321 / 10.919 / 6.271 | 2.611 / 2.152 / 2.682 | 不稳定：average_frame_rasterizer_time_millis, 90th_percentile_frame_rasterizer_time_millis | 不确定 |

所有未污染窗口独立检查 build+raster 同帧P99≤12ms且UI P99≤4ms，至少两个未污染窗口才评估成本；失败优先于不确定。冻结时间预算不因本次更慢而重标；比例、GC、RSS继续原门槛。各指标原值、中位数、原设计差距、硬门禁与RSS见 frame_assessment.json。


补充：冻结成本与波动（不能只看硬余量）

| 场景 | UI均值中位数ms | Raster均值/P90中位数ms | 未通过指标 |
| --- | --- | --- | --- |
| grid_steady | 1.062244 | 5.752400/7.333000 | average_frame_rasterizer_time_millis: 5.752400332225915 / 上限4.0, 状态FAIL, 极差比0.07572340883265483；90th_percentile_frame_rasterizer_time_millis: 7.333 / 上限7.0, 状态FAIL, 极差比0.0684576571662348 |
| slot_raster | 1.090628 | 2.896249/3.295000 | average_frame_build_time_millis: 1.0906279069767444 / 上限1.0, 状态FAIL, 极差比0.03513779437612421 |
| lots_shaking | 1.232439 | 3.059010/3.478000 | average_frame_rasterizer_time_millis: 3.0590099667774124 / 上限5.0, 状态UNCERTAIN, 极差比0.5805018017685337；90th_percentile_frame_rasterizer_time_millis: 3.478 / 上限8.0, 状态UNCERTAIN, 极差比0.6403105232892466 |
| lotto_draw | 2.208983 | 5.225883/5.945000 | 成本指标通过，硬余量另验 |

slot_raster旧硬余量失败本轮未重现，但UI均值1.090627907ms>冻结1.0ms，仍失败。grid的Raster均值5.752400332ms>4ms、P90 7.333ms>7ms；lotto硬余量最大12.331ms/UI4.570ms；lots均值/P90相对极差58.050%/64.031%，保持不确定。

## 全部持续动画窗口交付

| 场景/轮 | 主/参照 | fps | 帧数/期望 | 交付比例 | fps≥59且≥98% |
| --- | --- | --- | --- | --- | --- |
| grid_steady_1 | 主场景 | 60.004362 | 301/300.978 | 100.007270% | 通过 |
| grid_steady_1 | 参照 | 60.072682 | 301/300.636 | 100.121137% | 通过 |
| grid_steady_2 | 主场景 | 60.050726 | 301/300.746 | 100.084543% | 通过 |
| grid_steady_2 | 参照 | 60.044928 | 301/300.775 | 100.074880% | 通过 |
| grid_steady_3 | 主场景 | 59.962560 | 301/301.188 | 99.937600% | 通过 |
| grid_steady_3 | 参照 | 60.089339 | 301/300.552 | 100.148899% | 通过 |
| slot_raster_1 | 主场景 | 60.093526 | 301/300.532 | 100.155877% | 通过 |
| slot_raster_1 | 参照 | 60.101242 | 301/300.493 | 100.168736% | 通过 |
| slot_raster_2 | 主场景 | 59.995834 | 301/301.021 | 99.993057% | 通过 |
| slot_raster_2 | 参照 | 60.026547 | 301/300.867 | 100.044245% | 通过 |
| slot_raster_3 | 主场景 | 60.002986 | 301/300.985 | 100.004977% | 通过 |
| slot_raster_3 | 参照 | 60.159200 | 301/300.203 | 100.265333% | 通过 |
| lots_shaking_1 | 主场景 | 60.024919 | 301/300.875 | 100.041532% | 通过 |
| lots_shaking_1 | 参照 | 60.053709 | 301/300.731 | 100.089515% | 通过 |
| lots_shaking_2 | 主场景 | 60.010391 | 301/300.948 | 100.017319% | 通过 |
| lots_shaking_2 | 参照 | 60.117087 | 301/300.414 | 100.195144% | 通过 |
| lots_shaking_3 | 主场景 | 60.033012 | 301/300.834 | 100.055020% | 通过 |
| lots_shaking_3 | 参照 | 60.089843 | 301/300.550 | 100.149739% | 通过 |
| lotto_draw_1 | 主场景 | 60.061381 | 579/578.408 | 100.102301% | 通过 |
| lotto_draw_1 | 参照 | 60.008226 | 301/300.959 | 100.013710% | 通过 |
| lotto_draw_2 | 主场景 | 59.991906 | 579/579.078 | 99.986510% | 通过 |
| lotto_draw_2 | 参照 | 60.107951 | 301/300.459 | 100.179918% | 通过 |
| lotto_draw_3 | 主场景 | 60.036009 | 579/578.653 | 100.060015% | 通过 |
| lotto_draw_3 | 参照 | 60.008405 | 301/300.958 | 100.014009% | 通过 |

24/24个持续动画窗口交付通过；fps=59.962560–60.159200；fps=0轮数=0。冷push事件窗不按持续60fps验收；CPU项目没有有效窗口。这是timeline交付检查，不是独立面板呈现测量。

## 异常、根因与边界

1. 原脚本在首个项目有效轮不足时全局退出；本次续跑脚本位于 validation/resume_pending.ps1，只执行未启动项目，保留首次session和所有启动次数。原始脚本与产品lib未改。
2. 冷窗口的 SDK TimelineSummary 因 Raster 事件未闭合而失败；设备测试与FrameTiming仍有原始响应，恢复数据单独保存为 device_response.original.json，并保留driver失败。wheel/grid设备用例验收仍不确定。
3. CPU五项目0/5有效；统计区间/PID/线程列不符合协议。CPU未完成，不提供伪造百分比。
4. 本轮首帧仅增量预算标定，原4ms设计目标差距及波动不抹去；历史40.378ms外壳不同。
5. 本轮亮度按用户要求保持最低1、手动0、USB常亮2；主会话每120秒有锁屏看护。本脚本没有额外窗口内adb轮询；不能独立排除系统抢占、DIM或外部看护影响。
6. 若本次仍有硬失败，库代码根因为「无法判定」；没有可靠线程CPU或luckdraw函数采样栈，不将引擎GLES等待解释成可避免的库内工作，不改lib。

本报告由validation/summarize.py及finalize.py对本次原始响应、runs.json与冻结compare输出生成；所有失败保留。完整采集链路未通过不影响离线工具回归可以通过，两者分别报告。

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
