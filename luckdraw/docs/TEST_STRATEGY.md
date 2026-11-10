# luckdraw 测试与验收策略

> 状态：已按落地事实对齐（第三轮，2026-11-10）。真机集成、最低版本与 Web/APK 摇树已取得本地证据；真机性能验收未完全通过，Linux/远程 CI 与真实发布仍待验证。
> 配套：[ARCHITECTURE.md](ARCHITECTURE.md)、[FIDELITY.md](FIDELITY.md)、[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)。
> 本文定义：测试分层、覆盖率门禁、验收矩阵与校验、首版矩阵草稿、1:1 对照、性能基准、摇树验证、集成测试规矩、CI。
> 任务卡保留逐字测试名；§5.3 是设计草稿编号到实现的追踪索引，实际注册及追加回归以 `test/ACCEPTANCE.md` 和运行 JSON 为准。

---

## 1. 原则

1. **门禁先行**：T0.1 先落地覆盖率、验收矩阵、import 依赖三个门禁脚本，之后每张任务卡都要过门禁。
2. **测试名即契约**：矩阵引用"文件 :: group > test"的全名，`tool/check_acceptance.dart` 双向校验（引用必须存在；注册的测试必须被引用）。
3. **逐位算法用逐位断言**：缓动、求解、选奖、splitText、动画逐帧数值，期望值在测试里按 FIDELITY 公式独立计算或来自上游基线，不调用被测函数自证。
4. **渲染用结构断言 + golden + 对照**：结构断言（`TestRecordingCanvas` 记录的调用序列：无 `saveLayer`、save/restore 平衡、帧内只回放不录制）防性能回退；golden 防视觉回退；1:1 对照防语义漂移。
5. **性能只在真机 profile 量**：不做桌面性能冒烟；基准不计入覆盖率，但在矩阵中有条目（类型"基准"）。
6. **可复现**：所有随机都经注入的 `Random`；所有时间都经 `ManualLuckyClock` 或 `tester.pump(Duration)`；golden/对照使用同一份 Roboto 字体。

---

## 2. 测试分层

### 2.1 金字塔

| 层 | 范围 | 工具 | 运行位置 | 计入覆盖率 |
| --- | --- | --- | --- | --- |
| 单元 | foundation、geometry、text、easing、motion、picker、kinematics、各玩法 layout/motion/controller、compat 解析与转换、testing 辅助 | `flutter test`（纯 Dart 逻辑也用 flutter_test，因为依赖 dart:ui） | 本地 + CI + min-sdk | 是 |
| widget | `LuckyGameView` 宿主、各玩法 Widget、渲染器（`TestRecordingCanvas` 结构断言）、图片解析、叠加层 | `testWidgets` | 本地 + CI + min-sdk | 是 |
| golden | 各玩法典型画面 | `matchesGoldenFile` + `LuckyToleranceComparator`，`@Tags(['golden'])` | 本地 + CI（stable） | 是 |
| 1:1 对照 | 上游 lucky-canvas 逐帧数值 + 关键帧图像 | `test/parity/*`（数值部分无标签；图像部分 `@Tags(['golden'])`） | 本地 + CI（stable） | 是 |
| 工具 | 门禁脚本、摇树解析器、golden 比较器 | `test/tool/*` | 本地 + CI | 否（tool/ 不在 lib/） |
| 集成 | 真实设备上的完整流程、生命周期、resize、路由泄漏 | `integration_test`（example 工程） | Windows 桌面 + 安卓真机，每项 3 次 | 否 |
| 基准 | 帧耗时、掉帧、首帧、RSS、GC | `integration_test` + `flutter drive --profile`（tool/bench 工程） | 安卓真机 profile | 否 |
| 静态 | import 依赖图、摇树产物 | `tool/check_imports.dart`、`tool/treeshake/check_treeshake.dart` | 本地 + CI | 否 |

原设计规模为 107 个文件、693 条测试，不能当作落地运行结果。主会话提供的当前真实仓库基线为 analyze 0 issue、954 测试通过（s03/s05 golden 已启用）、覆盖率 100%、imports 及静态/JSON acceptance 通过；本次文档批不重新运行全包测试。各批真实结果见 `test/ACCEPTANCE.md` 追加记录，不能相加副本和真实仓库计数，也不能用静态注册数代替通过数。下表为设计清单及后续补充，文件数/测试数不作为当前运行统计。

### 2.2 测试文件清单

下表保留最终范围：现有文件的数量以源码展开注册数为准；未存在的行是待落地验证的目标测试，不得登记为已通过。各玩法独立夹具在 `test/support/<玩法>_fixtures.dart`，转盘沿用 fixtures 并派生渲染夹具。
| 文件 | 类型 | 测试数（展开后） |
| --- | --- | --- |
| `test/core/foundation/length_test.dart` | 单元 | 4 |
| `test/core/foundation/edge_insets_test.dart` | 单元 | 6 |
| `test/core/foundation/fill_test.dart` | 单元 | 24 |
| `test/core/foundation/shadow_test.dart` | 单元 | 6 |
| `test/core/foundation/color_utils_test.dart` | 单元 | 2 |
| `test/core/foundation/models_test.dart` | 单元 | 6 |
| `test/core/geometry/canvas_arc_test.dart` | 单元 | 3 |
| `test/core/geometry/fan_path_test.dart` | 单元 | 5 |
| `test/core/geometry/round_rect_test.dart` | 单元 | 5 |
| `test/core/geometry/image_box_test.dart` | 单元 | 6 |
| `test/core/text/split_text_test.dart` | 单元 | 10 |
| `test/core/text/text_measurer_test.dart` | 单元 | 7 |
| `test/core/easing/easing_test.dart` | 单元 | 18 |
| `test/core/motion/timeline_test.dart` | 单元 | 6 |
| `test/core/motion/motion_options_test.dart` | 单元 | 7 |
| `test/core/motion/stop_solver_test.dart` | 单元 | 10 |
| `test/core/motion/phase_test.dart` | 单元 | 2 |
| `test/core/picker/prize_picker_test.dart` | 单元 | 7 |
| `test/core/image/image_resolver_test.dart` | widget | 13 |
| `test/core/render/picture_cache_test.dart` | 单元 | 6 |
| `test/core/render/layer_test.dart` | widget | 6 |
| `test/core/game/registry_test.dart` | widget | 3 |
| `test/core/widgets/game_view_test.dart` | widget | 40 |
| `test/core/widgets/item_overlay_test.dart` | widget | 3 |
| `test/core/control/state_machine_test.dart` | 单元 | 175 |
| `test/wheel/wheel_layout_test.dart` | 单元 | 18 |
| `test/wheel/wheel_motion_test.dart` | 单元 | 24 |
| `test/wheel/wheel_controller_test.dart` | 单元 | 9 |
| `test/wheel/wheel_widget_test.dart` | widget | 16 |
| `test/wheel/wheel_painter_test.dart` | widget | 12 |
| `test/wheel/wheel_golden_test.dart` | golden | 4 |
| `test/grid/grid_layout_test.dart` | 单元 | 13 |
| `test/grid/grid_motion_test.dart` | 单元 | 13 |
| `test/grid/grid_controller_test.dart` | widget | 6 |
| `test/grid/grid_widget_test.dart` | widget | 4 |
| `test/grid/grid_painter_test.dart` | widget | 7 |
| `test/grid/grid_golden_test.dart` | golden | 3 |
| `test/slot/slot_layout_test.dart` | 单元 | 11 |
| `test/slot/slot_motion_test.dart` | 单元 | 12 |
| `test/slot/slot_controller_test.dart` | 单元 | 8 |
| `test/slot/slot_painter_test.dart` | widget | 7 |
| `test/slot/slot_widget_test.dart` | widget | 3 |
| `test/slot/slot_golden_test.dart` | golden | 4 |
| `test/compat/css_length_test.dart` | 单元 | 6 |
| `test/compat/css_color_test.dart` | 单元 | 4 |
| `test/compat/css_gradient_test.dart` | 单元 | 5 |
| `test/compat/css_shadow_test.dart` | 单元 | 3 |
| `test/compat/css_misc_test.dart` | 单元 | 5 |
| `test/compat/wheel_compat_test.dart` | 单元 | 6 |
| `test/compat/grid_compat_test.dart` | 单元 | 4 |
| `test/compat/slot_compat_test.dart` | 单元 | 3 |
| `test/slot/lever_test.dart` | widget | 7 |
| `test/slot/slot_stagger_test.dart` | 单元 | 3 |
| `test/slot/payline_test.dart` | 单元 | 4 |
| `test/capsule/capsule_layout_test.dart` | 单元 | 7 |
| `test/capsule/capsule_motion_test.dart` | 单元 | 13 |
| `test/capsule/capsule_controller_test.dart` | 单元 | 5 |
| `test/capsule/capsule_widget_test.dart` | widget | 5 |
| `test/capsule/capsule_painter_test.dart` | widget | 6 |
| `test/capsule/capsule_golden_test.dart` | golden | 3 |
| `test/number_wheel/number_wheel_layout_test.dart` | 单元 | 4 |
| `test/number_wheel/number_wheel_motion_test.dart` | 单元 | 7 |
| `test/number_wheel/number_wheel_controller_test.dart` | 单元 | 3 |
| `test/number_wheel/number_wheel_widget_test.dart` | widget | 3 |
| `test/number_wheel/number_wheel_painter_test.dart` | widget | 3 |
| `test/number_wheel/number_wheel_golden_test.dart` | golden | 3 |
| `test/lots/lots_layout_test.dart` | 单元 | 4 |
| `test/lots/lots_motion_test.dart` | 单元 | 5 |
| `test/lots/lots_controller_test.dart` | 单元 | 3 |
| `test/lots/lots_widget_test.dart` | widget | 3 |
| `test/lots/lots_painter_test.dart` | widget | 3 |
| `test/lots/lots_golden_test.dart` | golden | 3 |
| `test/core/kinematics/swirl_mixer_test.dart` | 单元 | 4 |
| `test/lotto/lotto_config_test.dart` | 单元 | 3 |
| `test/lotto/lotto_layout_test.dart` | 单元 | 3 |
| `test/lotto/lotto_motion_test.dart` | 单元 | 6 |
| `test/lotto/lotto_controller_test.dart` | 单元 | 4 |
| `test/lotto/lotto_widget_test.dart` | widget | 3 |
| `test/lotto/lotto_painter_test.dart` | widget | 5 |
| `test/lotto/lotto_golden_test.dart` | golden | 3 |
| `test/parity/wheel_parity_test.dart` | 1:1 对照 | 12 + 4 条容差保护，无跳过 |
| `test/parity/grid_parity_test.dart` | 1:1 对照 | 10，无跳过 |
| `test/parity/slot_parity_test.dart` | 1:1 对照 | 10，无跳过 |
| `test/testing/testing_helpers_test.dart` | 单元 | 3 |
| `test/tool/check_imports_test.dart` | 工具 | 15 |
| `test/tool/check_acceptance_test.dart` | 工具 | 8 |
| `test/tool/coverage_test.dart` | 工具 | 15 |
| `test/tool/golden_comparator_test.dart` | 工具 | 5 |
| `test/tool/treeshake_parser_test.dart` | 工具 | 20 |
| `example/integration_test/wheel_flow_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `example/integration_test/grid_flow_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `example/integration_test/slot_flow_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `example/integration_test/lifecycle_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `example/integration_test/resize_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `example/integration_test/route_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `tool/bench/integration_test/wheel_bench_test.dart` | 基准 | 2 |
| `tool/bench/integration_test/grid_bench_test.dart` | 基准 | 1 |
| `tool/bench/integration_test/slot_bench_test.dart` | 基准 | 2 |
| `tool/bench/integration_test/capsule_bench_test.dart` | 基准 | 1 |
| `example/integration_test/capsule_flow_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `example/integration_test/lever_flow_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `tool/bench/integration_test/number_wheel_bench_test.dart` | 基准 | 1 |
| `example/integration_test/lots_flow_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `example/integration_test/number_wheel_flow_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `tool/bench/integration_test/lotto_bench_test.dart` | 基准 | 1 |
| `example/integration_test/lotto_flow_test.dart` | 集成 | 1；Windows三轮通过，安卓待验 |
| `tool/bench/integration_test/memory_bench_test.dart` | 基准 | 1 |
| `test/compat/compat_options_test.dart` | 单元 / widget | 2 |
| `test/compat/json_reader_test.dart` | 单元 / widget | 2 |
| `test/core/motion/result_test.dart` | 单元 / widget | 2 |
| `test/core/text/text_line_test.dart` | 单元 / widget | 2 |
| `test/grid/grid_item_geometry_test.dart` | 单元 / widget | 2 |
| `test/lots/lots_boundary_test.dart` | 单元 / widget | 2 |
| `test/lots/lots_model_test.dart` | 单元 / widget | 1 |
| `test/lotto/lotto_contract_test.dart` | 单元 / widget | 5 |
| `test/number_wheel/number_wheel_boundary_test.dart` | 单元 / widget | 2 |
| `test/number_wheel/number_wheel_model_test.dart` | 单元 / widget | 1 |
| `test/slot/slot_atlas_test.dart` | 单元 / widget | 3 |
| `test/slot/slot_item_geometry_test.dart` | 单元 / widget | 4 |
| `test/tool/bench_compare_test.dart` | 工具 | 13 |
| `test/tool/bench_metrics_test.dart` | 工具 | 12 |
| `test/tool/parity_generate_test.dart` | 工具 | 10 |
| `test/tool/support_test.dart` | 工具 | 3 |
| `test/tool/treeshake_runner_test.dart` | 工具 | 9 |
| `test/wheel/wheel_item_geometry_test.dart` | 单元 / widget | 3 |
| `test/wheel/wheel_models_test.dart` | 单元 / widget | 3 |
| `tool/bench/integration_test/lots_bench_test.dart` | 基准 | 1 |
| `test/core/easing/f1_curve_test.dart` | 单元 / widget | 1 |
| `test/core/foundation/f1_fill_test.dart` | 单元 / widget | 1 |
| `test/core/text/f1_text_render_test.dart` | 单元 / widget | 2 |
| `test/tool/f1_gate_test.dart` | 工具 | 6 |
| `test/tool/treeshake_measurement_test.dart` | 工具 | 3 |

---

## 3. 覆盖率门禁（`tool/coverage.dart`）

| 项 | 规定 |
| --- | --- |
| 输入 | 默认 `coverage/lcov.info`；并行批次须用 `flutter test --coverage --coverage-path=coverage/<批次>.lcov`，门禁显式 `--lcov=coverage/<批次>.lcov`；另读 `lib/**/*.dart` 与验收矩阵豁免表 |
| 统计口径 | 只统计 lib 的 DA 行。D2：仅注释/指令、顶层 const、纯 typedef、无成员普通枚举（允许只有分隔分号）等无可执行行文件不要求记录，0/0 计 100%；其它可执行实现缺记录仍失败，含字段/构造/方法的枚举不能放行，不能用总行覆盖率掩盖缺采集错误 |
| 阈值 | `--min=100` |
| 豁免标记 | 行尾 `// coverage:ignore-line COV-NN`；块 `// coverage:ignore-start COV-NN` … `// coverage:ignore-end`。**编号必填** |
| 豁免登记 | `test/ACCEPTANCE.md` 的"## 覆盖率豁免"表：`\| COV-NN \| 文件 \| 位置 \| 原因 \|`，每个编号对应唯一文件 |
| 失败条件 | 缺采集记录；标记缺编号；编号未登记；登记的文件与标记所在文件不符；登记了但源码里没有对应标记；覆盖率 < min |
| 输出 | 每个文件 `path: hit/total (xx.xx%)` 与未覆盖行号；末行 `TOTAL` 与 `PASS`/`FAIL` |

F1（R3-06/07）补充：词法器支持嵌套块注释、原始串、转义及插值；无法可靠解析时保守要求采集，不能误判为无可执行行。豁免登记保留位置/范围，并逐一核对源码标记位置；编号和文件相符但实际标记超出登记位置也失败，不允许在同文件扩用豁免。

终审变异抽查以 F1 前 snap1 为基线：175 个变异、133 被杀、40 存活（12 等价、28 行为缺口），原得分76.88%，剔除等价后82.61%。它是测试质量的历史证据，不能用100%行覆盖率抹去行为缺口；终审提出 F1 后补 H1 并重施28个变异，本批来源未提供重施结果，不宣称该计划已验收。F1/F2 已有具体回归按各自追加记录追踪。

失败信息（中英并列，便于 grep）：

```text
MISSING coverage record / 缺少采集记录: lib/src/core/render/perf_trace.dart
MARKER WITHOUT ID / 豁免标记缺编号: lib/src/core/render/perf_trace.dart:21
UNREGISTERED exemption / 未登记的豁免: COV-07 at lib/src/wheel/render/wheel_painter.dart:88
FILE MISMATCH / 豁免文件不符: COV-02 登记 lib/a.dart，实际 lib/b.dart
UNUSED exemption / 登记未使用: COV-03
FAIL: coverage 99.12% < 100% / 覆盖率未达标
```

豁免只允许以下类别，其它一律写测试：(a) `bool.fromEnvironment` 常量开关下的分支（如 `perf_trace.dart` 的 Timeline 打点）；(b) 只在 release/profile 才可达的分支；(c) 平台通道失败等测试环境无法构造的防御分支（需说明为何不能注入）。预计首版豁免 ≤ 3 条，模板：

```markdown
## 覆盖率豁免

| 编号 | 文件 | 位置 | 原因 |
| --- | --- | --- | --- |
| COV-01 | lib/src/core/render/perf_trace.dart | `luckyTraceStart` 中 Timeline.startSync 一行 | 仅 `--dart-define=LUCKDRAW_TIMELINE=true` 时可达，单测不开启 |
```

---

## 4. 验收矩阵与校验

### 4.1 `test/ACCEPTANCE.md` 结构（沿用 cacheman 格式）

1. 标题与复现命令块（§10.1 的命令）。
2. "最近一次运行"摘要：测试数、覆盖率（含豁免数）、引用数、生成日期、commit 基线。
3. 名称格式说明：`test/文件.dart :: group > test`；参数化名称列出实际展开值；集成测试与基准测试路径分别以 `example/integration_test/`、`tool/bench/integration_test/` 开头；命令型验收写 `` `cmd: …` ``。
4. "## 需求和不变量"表：列为 `ID | 需求 / 不变量 | 来源 | 用例 | 类型 | 结果`（首版草稿见 §5）。
5. "## 覆盖率豁免"表（§3）。

D6：落地期追加行状态写「已落地」，T4.8 才统一最终状态；工具夹具通过、真实产物未测、跨平台/人工留项分别记录。历史 B02/B03 缺 const/枚举记录的阻塞已由 B03/B04 的静态判定扩展解决，不应继续当作当前门禁结论。B14 回拷时缺 mixer 是历史阻塞，源码现已存在；B16 有接入真实 mixer 的最终复核，B14 自身真实仓库复跑证据仍待落地验证。

### 4.2 `tool/check_acceptance.dart` 规则

| 规则 | 说明 |
| --- | --- |
| A1 | 扫描 `test/**/*_test.dart`、`example/integration_test/**/*_test.dart`、`tool/bench/integration_test/**/*_test.dart`（目录存在才扫） |
| A2 | 用 cacheman 的轻量词法器提取 `group/test/testWidgets` 的字面量名称，跟踪 group 嵌套；非字面量名称直接报错 |
| A3 | `for (final x in [ … ])` 字面量列表参数化：字符串元素去引号后代入 `$x`/`${x}`；同一文件内变量名唯一 |
| A4 | 带 `skip:`（非 `null`/`false`）的测试计为"跳过"：不要求被引用，且**不得**被引用 |
| A5 | 矩阵中 `` `path :: name` `` 引用必须存在于注册集合；注册集合中的每个测试至少被引用一次 |
| A6 | `` `cmd: …` `` 引用：命令中出现的 `tool/…dart` 路径必须存在 |
| A7 | 矩阵第一列 ID 唯一；"类型"为"人工"的行允许无引用，其它行至少一个引用 |

F1（R3-09）：静态模式是快速路径，只接受 main/group 注册作用域内的调用，拒绝未调用函数里的 phantom test。正式验收及 CI 默认使用 `--from-json <flutter test --reporter=json 输出>`，与真实运行注册名交叉校验；独立工程仍按其矩阵范围处理，不把主包运行当作真机运行证据。静态 PASS 不能替代 JSON 模式。
| A8 | 输出 `MISSING / 不存在`、`UNMAPPED / 矩阵未引用`、`DUPLICATE ID / 编号重复`、`EMPTY ROW / 无引用`、`BAD CMD / 命令脚本不存在`，任一出现则 exitCode=1 |

当前词法器会把普通 `for (final x in [字面量列表])` 也纳入参数扫描；测试可先绑定列表变量再遍历，识别范围改进待落地验证。不能以扫描器局限为由忽略真实缺登记。

### 4.3 `tool/check_imports.dart` 规则

F1（R3-08）：Dart URI 字符串须按转义规则解码后检查；字符串插值中的表达式也参与规则校验，纯文本示例仍忽略。词法器支持嵌套块注释，不能靠转义 import 或插值隐藏违规依赖。

实现 ARCHITECTURE §4.3 的 IMP-R1…R11，外加 IMP-R12：`pubspec.yaml` 的 `flutter:` 段不得出现 `assets:`/`fonts:`。逐行正则，无 analyzer 依赖。测试 `test/tool/check_imports_test.dart` 用内存中的小型虚拟源码树（`Map<String, String>`）覆盖每条规则的通过与失败样例。

B13a 已补 core 常量实现映射表检查；字符串缓动表仍只允许在 compat。typedef 等号误判的说明标记保留，后续精化扫描器待落地验证。

### 4.4 golden 比较器（`test/support/golden_comparator.dart`）

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| 像素差阈值 | 32 | 任一通道差 > 32 记为"差异像素" |
| `maxDiffRatio` | 0.005（普通 golden）/ 0.018（1:1 标准层） | 差异像素占比上限；特例见 §6.5 |
| `maxMeanError` | 1.5（普通 golden）/ 1.8（1:1 标准层） | 全图每通道平均绝对误差上限；1:1 特例仅限 §6.5 逐帧白名单 |

当前各玩法 golden 首轮在 Windows 生成并目视检查，使用 Roboto 英文标签及独立派生夹具；Linux基线仍待验证；MIN非golden已通过，最低SDK golden另有像素差异待闭环。普通 golden 的跨平台校准待两端实测，确认后取实测最大值×1.5与普通门槛较小者并说明理由；上游 parity 已完成分层校准，不能再写成待首测。

golden 测试标注 `@Tags(['golden'])`，已在 `dart_test.yaml` 注册 `tags: {golden: {}}`。字体查找失败须显式抛错，不能跳过。比较器对 getGoldenBytes 的 List<int> 先 Uint8List.fromList 再解码。普通 Flutter golden 的 0.5% / 1.5 与上游 parity 容差分开，不能互换；真机 Skia/Impeller 阴影截图仍未做。

---

## 5. 首版验收矩阵草稿

> 已落地部分在 `test/ACCEPTANCE.md` 登记，下面仍保留未落地的最终范围；不要整表覆盖现有追加记录。编号体系：R1…R7 需求、SM-E* 状态机、ISS-* 上游问题、FID-* 行为对照、IMP/DEV 改进与偏离。
> 状态机边按七玩法展开。结果按 D6 写「已落地」或「部分已落地；其余待落地验证」，尚无用例/命令/人工证据的写「待落地验证」。测试存在不等于运行通过，以各批验证记录及 T4.8 最终复跑为准。

### 5.1 不需要单独测试的 FIDELITY 条目

`FID-L06`、`FID-L07`、`FID-L09`、`FID-L10`、`FID-L11`、`FID-L18`、`FID-L19`、`FID-L20`、`FID-U03`、`FID-U09`、`FID-U11`、`FID-U14`、`FID-U20`、`FID-U21`、`FID-W14`、`FID-G12` 均为"不支持（N/A）"；`FID-U08a`–`FID-U08g` 统一以 `FID-U08` 验收。

### 5.2 状态机边与玩法的适配

harness 以 `test/core/control/state_machine_test.dart` 的 verifyEdge 与各玩法独立适配器执行七玩法边测试。大乐透无下标语义：有效 stop 映射到 stopWith(固定号码)，负数映射到 cancel，picker null 映射到 LottoSampler 返回 null；老虎机的作废断言无 onEnd（SM-E25）。扭蛋机/抽签/大乐透的 decelerating 包含掉落/升签/出球等完整子阶段，推进 settled 须等待尾段和通知全部结束。

D7：SM-E09 的 wheel/grid 提前 stop 直接 decelerating，slot 上游路径含 cruising 帧，追加玩法以各自 motion 为准；不得强插 cruising。现存测试名的 E09 片段仍写 cruising one tick，本轮保留以对上代码，协调改名待 T4.8。

ISS-120HZ：最终停点一致、加速段中间相位差 ≤6°，历史测试名不变。ISS-205：半周期速度差上界只对未触发方向修正的 nearest 搜索成立，另有反例断言。DEV-07/IMP-18 的零位移对齐例外仅为 frame + UpstreamStopSolver 组合。T3.4 的 one drawAtlas call per frame 历史名实际验每帧每页一次 drawRawAtlas；T5.0 caller-provided buffers 历史名实际验构造器公开缓冲引用跨帧复用。

### 5.3 矩阵

本节 R1–R7、SM-E、ISS、FID、IMP/DEV 编号是设计草稿的追踪键，带具体引用的行表示已映射到落地测试，不是另一份运行报告。`test/ACCEPTANCE.md` 是实现侧唯一完整登记表：保留设计键并追加 F1/F2、DIAG/DIAG2、B13C、B15 等回归/证据编号。终审的 R1-01…R6-07 属评审命名空间，与本节同形需求编号不可混用；实现侧以 ISS-R*、F2-* 等追加行区分。未执行的真机基准即使测试已注册仍是待验证，D6「已落地」不升级为通过。

结构更新的验收按 F2：accelerating/cruising/decelerating/idleSpinning 均排队；R3-01 的连续更新不丢待应用身份，motion configure 的缩减/空列表防御另验。SM-E09/g05 已直接减速；E03 的抽签振幅按 T5.7 公式，保留历史测试名。新增回归的逐字名称从 ACCEPTANCE 追加行追踪，本节不复制整份追加表。

B17b 自检：草稿中71个编号没有作为 ACCEPTANCE 的原样 ID 出现，其中69个可按批次前后缀、相同测试引用或命令证据对应（如 FID-G01→B07-FID-G01、IMP-05→IMP-05-B08、R4-07→R4-07-B15）；剩余 R1-08（人工设计评审）、R5-01（文档交叉引用最终验收）仍无独立矩阵行，由 T4.8 统一整理，本批不修改矩阵。R5-03 原样 ID 虽未单列，命令验收由当前主会话 analyze 0 issue 支持。测试引用不存在或漏登记与编号别名是两种问题，不能混为失败。

| ID | 需求 / 不变量 | 来源 | 用例（文件 :: group > 测试名，或 cmd） | 类型 | 结果 |
| --- | --- | --- | --- | --- | --- |
| R1-01 | core 不依赖玩法；玩法互不依赖；玩法不依赖 compat（IMP-R1…R5） | 需求1/6 | `test/tool/check_imports_test.dart :: check_imports > accepts the allowed dependency graph`<br>`test/tool/check_imports_test.dart :: check_imports > rejects core importing a game`<br>`test/tool/check_imports_test.dart :: check_imports > rejects a game importing another game or compat`<br>`cmd: dart run tool/check_imports.dart` | 命令、工具 | 已落地 |
| R1-02 | 新玩法只用 extend.dart 即可接入 LuckyGameView，不改 core | 需求1 | `test/core/widgets/game_view_test.dart :: LuckyGameView > hosts a custom game defined outside the package (plugin seam)` | widget | 已落地 |
| R1-03 | 渲染后端可经 renderer 参数替换 | 需求1 | `test/wheel/wheel_widget_test.dart :: LuckyWheel > a custom renderer replaces the canvas renderer`<br>`test/capsule/capsule_widget_test.dart :: LuckyCapsuleMachine > a custom renderer receives capsule layout and frame` | widget | 已落地 |
| R1-04 | 缓动、停止求解、选奖、时钟、随机数均可显式注入 | 需求1/3 | `test/wheel/wheel_controller_test.dart :: WheelController > controller works headless with a ManualLuckyClock (#342)` | 单元 | 已落地 |
| R1-05 | LuckyGameRegistry 为实例级、默认为空、只含用户 add 的项 | 需求1/6 | `test/core/game/registry_test.dart :: LuckyGameRegistry > is empty by default and only contains explicitly added builders`<br>`test/core/game/registry_test.dart :: LuckyGameRegistry > builds a widget from a registered builder by key`<br>`test/core/game/registry_test.dart :: LuckyGameRegistry > unknown key returns null` | widget | 已落地 |
| R1-06 | LuckyLayer 可在 4 个位置插入静态/动态绘制 | 需求1/3 | `test/core/render/layer_test.dart :: LuckyLayer > static layers are recorded into the cache and not repainted per frame`<br>`test/core/render/layer_test.dart :: LuckyLayer > dynamic layers paint every frame in position order` | widget | 已落地 |
| R1-07 | LuckyItemOverlay 可用 Widget 作为奖品内容 | 需求1/3 | `test/core/widgets/item_overlay_test.dart :: LuckyItemOverlay > places one child per item using the game item geometry`<br>`test/core/widgets/item_overlay_test.dart :: LuckyItemOverlay > repaints child transforms without rebuilding children` | widget | 已落地 |
| R1-08 | 布局/帧类型不含 Canvas/Picture，3D 后端可复用（设计评审） | 需求1 | （人工评审，无测试） | 人工 | 待落地验证 |
| R2-01 | 稳态动画中 luckdraw 子树零 rebuild | 需求2 | `test/core/widgets/game_view_test.dart :: LuckyGameView > steady spin triggers no widget rebuilds`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > repaints through the frame listenable without rebuilding` | widget | 已落地 |
| R2-02 | 静态段只录制一次，帧内只回放 | 需求2 | `test/core/render/picture_cache_test.dart :: LuckyPictureCache > records once and reuses the picture until invalidated`<br>`test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > static segments are recorded once while spinning`<br>`test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > rotating segments are replayed with one rotation per frame`<br>`test/grid/grid_painter_test.dart :: GridCanvasRenderer > each cell has cached normal and active pictures`<br>`test/capsule/capsule_painter_test.dart :: CapsuleCanvasRenderer > capsule pictures are recorded once per color pair`<br>`test/number_wheel/number_wheel_painter_test.dart :: NumberWheelCanvasRenderer > a 200 pocket disc records its static segments once`<br>`test/lots/lots_painter_test.dart :: LotsCanvasRenderer > stick pictures are recorded once per style`<br>`test/lotto/lotto_painter_test.dart :: LottoCanvasRenderer > ball pictures are recorded once per number` | widget、单元 | 已落地 |
| R2-03 | Ticker 只在运动阶段运行 | 需求2 | `test/core/widgets/game_view_test.dart :: LuckyGameView > ticker runs only while the controller is moving` | widget | 已落地 |
| R2-04 | App 隐藏/暂停时冻结有效时间，用户暂停与生命周期暂停分开记账 | 需求2 | `test/core/motion/timeline_test.dart :: LuckyTimeline > user pause and lifecycle pause are tracked separately`<br>`test/core/widgets/game_view_test.dart :: LuckyGameView > pauses when the app is hidden and resumes on resumed` | widget、单元 | 已落地 |
| R2-05 | 绘制路径不调用 saveLayer | 需求2 | `test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > image opacity is applied without saveLayer`<br>`test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > painting never calls saveLayer and keeps save count balanced (#176)`<br>`test/grid/grid_painter_test.dart :: GridCanvasRenderer > painting never calls saveLayer and keeps save count balanced`<br>`test/slot/slot_painter_test.dart :: SlotCanvasRenderer > painting never calls saveLayer and keeps save count balanced`<br>`test/capsule/capsule_painter_test.dart :: CapsuleCanvasRenderer > painting never calls saveLayer and keeps save count balanced`<br>`test/number_wheel/number_wheel_painter_test.dart :: NumberWheelCanvasRenderer > painting never calls saveLayer and keeps save count balanced`<br>`test/lots/lots_painter_test.dart :: LotsCanvasRenderer > painting never calls saveLayer and keeps save count balanced`<br>`test/lotto/lotto_painter_test.dart :: LottoCanvasRenderer > painting never calls saveLayer and keeps save count balanced` | widget | 已落地 |
| R2-06 | 九宫格仅在高亮变化时请求重绘 | 需求2 | `test/grid/grid_motion_test.dart :: GridMotion > repaint notifier fires only when the active index changes` | 单元 | 已落地 |
| R2-07 | 任何位图纹理边长 ≤ maxRasterSide；老虎机不拼长图 | 需求2/#297 | `test/core/render/picture_cache_test.dart :: LuckyPictureCache > raster mode falls back to picture when side times dpr exceeds maxRasterSide`<br>`test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > raster cache mode keeps every texture within maxRasterSide`<br>`test/slot/slot_layout_test.dart :: computeSlotLayout > fifty prizes need no texture taller than maxRasterSide (#297)`<br>`test/slot/slot_painter_test.dart :: SlotCanvasRenderer > raster mode draws visible cells with one drawAtlas call per frame` | widget、单元 | 已落地 |
| R2-08 | 图片按绘制尺寸×dpr 解码；自然尺寸按 ImageInfo.scale | 需求2 | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > decodes at draw size times device pixel ratio when a size is specified`<br>`test/core/image/image_resolver_test.dart :: LuckyImageResolver > natural size uses image width divided by ImageInfo.scale` | widget | 已落地 |
| R2-09 | dispose 释放 Ticker、ImageStream 监听、图片、Picture、TextPainter | 需求2 | `test/core/text/text_measurer_test.dart :: TextPainterMeasurer > reuses one TextPainter per style and disposes them`<br>`test/core/image/image_resolver_test.dart :: LuckyImageResolver > dispose removes all ImageStream listeners and disposes held images`<br>`test/core/render/picture_cache_test.dart :: LuckyPictureCache > invalidate disposes the previous picture`<br>`test/core/render/picture_cache_test.dart :: LuckyPictureCache > dispose releases pictures and images`<br>`test/core/widgets/game_view_test.dart :: LuckyGameView > dispose stops the ticker and completes pending playUntil as cancelled`<br>`test/slot/lever_test.dart :: LuckyLeverSlotMachine > lever spring-back animation stops its ticker when done`<br>`example/integration_test/route_test.dart :: route > push and pop 20 times leaves no active ticker` | widget、单元、集成 | 已落地；Windows/安卓集成各33/33 |
| R2-10 | 真机 profile 帧耗时/掉帧/首帧预算（不计入覆盖率门禁） | 需求2 | `tool/bench/integration_test/wheel_bench_test.dart :: bench > wheel 12 prizes steady spin`<br>`tool/bench/integration_test/wheel_bench_test.dart :: bench > wheel first frame layout and record time`<br>`tool/bench/integration_test/grid_bench_test.dart :: bench > grid 3x3 steady walk`<br>`tool/bench/integration_test/slot_bench_test.dart :: bench > slot 3 reels 10 prizes steady scroll`<br>`tool/bench/integration_test/capsule_bench_test.dart :: bench > capsule 30 capsules mixing`<br>`tool/bench/integration_test/number_wheel_bench_test.dart :: bench > number wheel 37 pockets ball spin`<br>`tool/bench/integration_test/lotto_bench_test.dart :: bench > lotto 47 balls mixing and drawing`<br>`cmd: dart run tool/bench/compare.dart` | 命令、基准 | 已采集三轮；真机性能未完全通过 |
| R2-11 | 停止求解对非有限输入有迭代上限，不死循环 | 需求2/U-05 | `test/core/motion/stop_solver_test.dart :: MonotonicStopSolver > falls back after maxIterations with non-finite inputs instead of hanging` | 单元 | 已落地 |
| R2-12 | RSS 增量与 push/pop 泄漏预算 | 需求2 | `tool/bench/integration_test/memory_bench_test.dart :: bench > rss after 5 push pop cycles`<br>`cmd: dart run tool/bench/compare.dart` | 命令、基准 | 已采集三轮；FIN稳态RSS中位数通过，不能据RSS证明无泄漏 |
| R2-13 | 九宫格/老虎机每帧只回放缓存 Picture，不录制 | 需求2 | `test/grid/grid_painter_test.dart :: GridCanvasRenderer > per frame paint replays one cached picture per cell without recording`<br>`test/slot/slot_painter_test.dart :: SlotCanvasRenderer > per frame paint replays cached cell pictures without recording`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > capsule positions are written into reused Float64List buffers`<br>`test/capsule/capsule_painter_test.dart :: CapsuleCanvasRenderer > per frame paint replays cached pictures without recording`<br>`test/number_wheel/number_wheel_painter_test.dart :: NumberWheelCanvasRenderer > per frame paint replays the disc and ball pictures without recording`<br>`test/lots/lots_motion_test.dart :: LotsMotion > shake angle is written into the reused frame without allocation`<br>`test/lots/lots_painter_test.dart :: LotsCanvasRenderer > per frame paint replays cached pictures without recording`<br>`test/core/kinematics/swirl_mixer_test.dart :: LuckySwirlMixer > writes positions into caller-provided Float64List buffers`<br>`test/lotto/lotto_motion_test.dart :: LottoMotion > positions are written into reused buffers without allocation`<br>`test/lotto/lotto_painter_test.dart :: LottoCanvasRenderer > per frame paint replays cached pictures without recording` | widget、单元 | 已落地 |
| R3-01 | LuckyLength px/percent 语义与值相等 | 需求3 | `test/core/foundation/length_test.dart :: LuckyLength > px resolves to its value regardless of base`<br>`test/core/foundation/length_test.dart :: LuckyLength > percent resolves as value * (base / 100) like upstream changeUnits`<br>`test/core/foundation/length_test.dart :: LuckyLength > equality and hashCode are value based`<br>`test/core/foundation/length_test.dart :: LuckyLength > zero constant resolves to 0` | 单元 | 已落地 |
| R3-02 | LuckyEdgeInsets 1~4 值 CSS 简写 | 需求3 | `test/core/foundation/edge_insets_test.dart :: LuckyEdgeInsets > css shorthand with 1 value applies to all sides`<br>`test/core/foundation/edge_insets_test.dart :: LuckyEdgeInsets > css shorthand with 2 values is vertical then horizontal`<br>`test/core/foundation/edge_insets_test.dart :: LuckyEdgeInsets > css shorthand with 3 values is top, horizontal, bottom`<br>`test/core/foundation/edge_insets_test.dart :: LuckyEdgeInsets > css shorthand with 4 values follows CSS top-right-bottom-left order`<br>`test/core/foundation/edge_insets_test.dart :: LuckyEdgeInsets > css shorthand rejects empty or more than 4 values` | 单元 | 已落地 |
| R3-03 | LuckyFill 纯色/Flutter Gradient；颜色透明度工具 | 需求3 | `test/core/foundation/fill_test.dart :: LuckyFill > color fill creates a solid paint`<br>`test/core/foundation/fill_test.dart :: LuckyFill > gradient fill creates a shader for the given rect`<br>`test/core/foundation/color_utils_test.dart :: colorAlpha8 > reads alpha of opaque and translucent colors`<br>`test/core/foundation/color_utils_test.dart :: colorAlpha8 > colorWithAlphaFactor multiplies alpha and rounds` | 单元 | 已落地 |
| R3-04 | LuckyFill.legacyLinear 复刻上游渐变端点 | 需求3 | `test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 0 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 30 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 45 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 60 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 90 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 120 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 135 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 150 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 180 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 200 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 225 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 250 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 270 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 300 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 315 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 340 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient keywords top bottom left right map to upstream endpoints`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient truncates endpoints toward zero like >> 0`<br>`test/core/foundation/fill_test.dart :: LuckyFill > negative angle is normalized into 0..360 (IMP-20)` | 单元 | 已落地 |
| R3-05 | LuckyShadow sigma 换算与 alpha 规则 | 需求3 | `test/core/foundation/shadow_test.dart :: LuckyShadow > logical blur converts to sigma blur / 2`<br>`test/core/foundation/shadow_test.dart :: LuckyShadow > device blur converts to sigma blur / (2 * dpr)`<br>`test/core/foundation/shadow_test.dart :: LuckyShadow > zero blur produces no mask filter`<br>`test/core/foundation/shadow_test.dart :: LuckyShadow > shadow alpha is multiplied by solid fill alpha only` | 单元 | 已落地 |
| R3-06 | 7 个上游缓动 + CurveEasing，按需引用 | 需求3 | `test/core/easing/easing_test.dart :: LuckyEasings > quad easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > cubic easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > quart easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > quint easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > sine easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > expo easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > circ easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > quad easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > cubic easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > quart easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > quint easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > sine easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > expo easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > circ easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > CurveEasing maps Curve.transform onto t b c d`<br>`test/core/easing/easing_test.dart :: LuckyEasings > easing aliases are const and identical across accesses` | 单元 | 已落地 |
| R3-07 | LuckyTimeline 有效时间语义 | 需求3 | `test/core/motion/timeline_test.dart :: LuckyTimeline > first tick after start has zero delta`<br>`test/core/motion/timeline_test.dart :: LuckyTimeline > raw delta above maxFrameDelta is clamped`<br>`test/core/motion/timeline_test.dart :: LuckyTimeline > paused timeline does not advance and resumes without a jump`<br>`test/core/motion/timeline_test.dart :: LuckyTimeline > negative raw delta is treated as zero` | 单元 | 已落地 |
| R3-08 | WeightedPrizePicker 语义（含 null=作废、disabled） | 需求3 | `test/core/picker/prize_picker_test.dart :: WeightedPrizePicker > matches upstream computeRange on a recorded random sequence`<br>`test/core/picker/prize_picker_test.dart :: WeightedPrizePicker > returns null when all weights are absent (upstream -1 cancels)`<br>`test/core/picker/prize_picker_test.dart :: WeightedPrizePicker > disabled prizes are excluded when honorDisabled is true (IMP-13)` | 单元 | 已落地 |
| R3-09 | GuaranteedPrizePicker 保底 | 需求3 | `test/core/picker/prize_picker_test.dart :: GuaranteedPrizePicker > forces the guaranteed index after the configured number of misses`<br>`test/core/picker/prize_picker_test.dart :: GuaranteedPrizePicker > resets the miss counter after a hit` | 单元 | 已落地 |
| R3-10 | LuckyImageFormatter 语义与所有权 | 需求3 | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > formatter output replaces the image and is disposed on eviction` | widget | 已落地 |
| R3-11 | LuckyHooks 全部钩子按上游顺序触发 | 需求3 | `test/core/render/layer_test.dart :: LuckyLayer > hooks beforeDraw and afterDraw wrap all layers`<br>`test/core/widgets/game_view_test.dart :: LuckyGameView > lifecycle hooks fire in upstream order`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > afterStart beforeDraw and afterDraw hooks are invoked` | widget | 已落地 |
| R3-12 | Widget 回调（onStart/onButtonTap/onEnd）与 Controller 挂接 | 需求3 | `test/core/widgets/game_view_test.dart :: LuckyGameView > swapping controllers detaches the old one`<br>`test/wheel/wheel_controller_test.dart :: WheelController > a controller attached to two views asserts`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > tap inside the button radius calls onStart only in idle-like phases`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > onEnd receives the prize at the target index`<br>`test/grid/grid_widget_test.dart :: LuckyGrid > renders blocks cells and the active highlight`<br>`test/number_wheel/number_wheel_widget_test.dart :: LuckyNumberWheel > tapping the center calls onStart only in idle-like phases`<br>`test/lotto/lotto_widget_test.dart :: LuckyLotto > tapping the start button calls onStart only in idle-like phases` | widget、单元 | 已落地 |
| R3-13 | playUntil 异步等服务端结果、minSpinDuration、额外圈数 | 需求3 | `test/wheel/wheel_motion_test.dart :: WheelMotion edges > extra revolutions add whole turns to the final angle`<br>`test/wheel/wheel_controller_test.dart :: WheelController > playUntil stops with the async index after minSpinDuration`<br>`test/wheel/wheel_controller_test.dart :: WheelController > playUntil with a null index cancels`<br>`test/wheel/wheel_controller_test.dart :: WheelController > playUntil propagates resolver errors after cancelling`<br>`test/capsule/capsule_controller_test.dart :: CapsuleController > playUntil waits for the async index`<br>`test/number_wheel/number_wheel_controller_test.dart :: NumberWheelController > playUntil waits for the server number`<br>`test/lots/lots_controller_test.dart :: LotsController > playUntil waits for the async index`<br>`test/lotto/lotto_controller_test.dart :: LottoController > playUntil waits for the server draw`<br>`example/integration_test/wheel_flow_test.dart :: wheel flow > tap start then server result settles on the target` | 单元、集成 | 已落地；安卓真机流程33/33 |
| R3-14 | 九宫格格子点击与合并格命中 | 需求3 | `test/grid/grid_controller_test.dart :: GridController > tapping a prize cell calls onCellTap`<br>`test/grid/grid_controller_test.dart :: GridController > merged cells are hit across their whole span` | widget | 已落地 |
| R3-15 | 老虎机 stop/stopEach/无参 stop | 需求3 | `test/slot/slot_controller_test.dart :: SlotController > stop() without index uses the picker for all reels`<br>`test/slot/slot_widget_test.dart :: LuckySlotMachine > renders reels and settles on the requested indices` | widget、单元 | 已落地 |
| R3-16 | 老虎机负数 index 取消 | 需求3 | `test/slot/slot_controller_test.dart :: SlotController > any negative index cancels like upstream -1` | 单元 | 已落地 |
| R3-17 | alignment 参数 | 需求3 | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > alignment center moves the wheel into the box middle` | 单元 | 已落地 |
| R3-18 | LuckyPhase 状态流（ValueListenable + Stream） | 需求3 | `test/core/motion/phase_test.dart :: LuckyPhase > isMoving is true only for moving phases`<br>`test/core/motion/phase_test.dart :: LuckyPhase > canPlay is true for idle settled and idleSpinning`<br>`test/wheel/wheel_controller_test.dart :: WheelController > phase listenable and phaseChanges stream emit every transition in order` | 单元 | 已落地 |
| R3-19 | 无障碍语义：标签、点按动作、结果 liveRegion | 需求3 | `test/core/widgets/game_view_test.dart :: LuckyGameView > semantics exposes label, tap action and live result value`<br>`test/slot/lever_test.dart :: LuckyLeverSlotMachine > tapping the lever knob is an accessible alternative to dragging` | widget | 已落地 |
| R3-20 | 文字缩放与文字方向取舍 | 需求3 | `test/core/text/text_measurer_test.dart :: TextPainterMeasurer > measures with family weight and no text scaling by default`<br>`test/core/text/text_measurer_test.dart :: TextPainterMeasurer > system text scaling multiplies font size when enabled`<br>`test/core/text/text_measurer_test.dart :: TextPainterMeasurer > text direction follows the ambient direction for shaping only` | 单元 | 已落地 |
| R3-21 | 奖品/列为空时拒绝 play，不产生 NaN | 需求3 | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > empty prizes produce no sectors and no NaN`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion edges > zero prizes refuses to play`<br>`test/grid/grid_motion_test.dart :: GridMotion > zero prizes refuses to play and activates nothing`<br>`test/slot/slot_controller_test.dart :: SlotController > no reels or no prizes refuses to play` | 单元 | 已落地 |
| R3-22 | stopEach 长度不符抛 ArgumentError | 需求3 | `test/slot/slot_controller_test.dart :: SlotController > stopEach requires one index per reel`<br>`test/number_wheel/number_wheel_controller_test.dart :: NumberWheelController > stopNumber maps a number to its pocket and rejects unknown numbers`<br>`test/lotto/lotto_controller_test.dart :: LottoController > stopWith validates counts ranges and duplicates` | 单元 | 已落地 |
| R3-23 | 尺寸为 0 不绘制不抛；无界约束给出指导性错误 | 需求3 | `test/core/widgets/game_view_test.dart :: LuckyGameView > zero size paints nothing and does not throw`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > unbounded constraints without width or height throw a FlutterError with guidance`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > zero rows cols or size does not throw`<br>`test/slot/slot_layout_test.dart :: computeSlotLayout > zero size yields an empty layout without throwing`<br>`test/capsule/capsule_layout_test.dart :: computeCapsuleLayout > zero size yields an empty layout without throwing`<br>`test/number_wheel/number_wheel_layout_test.dart :: computeNumberWheelLayout > zero size yields an empty layout without throwing`<br>`test/lots/lots_layout_test.dart :: computeLotsLayout > zero size yields an empty layout without throwing`<br>`test/lotto/lotto_layout_test.dart :: computeLottoLayout > zero size yields an empty layout without throwing` | widget、单元 | 已落地 |
| R3-24 | 热重载 reassemble 失效缓存 | 需求3 | `test/core/widgets/game_view_test.dart :: LuckyGameView > reassemble invalidates render caches (hot reload)` | widget | 已落地 |
| R3-25 | 时长参数断言与运行期保护 | 需求3 | `test/core/motion/motion_options_test.dart :: LuckyMotionOptions > asserts positive durations and runtime treats non-positive as 1ms` | 单元 | 已落地 |
| R3-26 | 字体动态加载后重新布局 | 需求3 | `test/core/widgets/game_view_test.dart :: LuckyGameView > system font change invalidates text layout` | widget | 已落地 |
| R3-27 | compat 解析失败给 warning 不抛异常 | 需求3 | `test/compat/css_length_test.dart :: parseCssLength > px number and unitless values parse as px`<br>`test/compat/css_length_test.dart :: parseCssLength > malformed values return null with a warning (DEV-16)`<br>`test/compat/css_color_test.dart :: parseCssColor > hex 3 4 6 and 8 digit forms`<br>`test/compat/css_color_test.dart :: parseCssColor > rgb rgba hsl and hsla forms`<br>`test/compat/css_color_test.dart :: parseCssColor > named colors and transparent`<br>`test/compat/css_color_test.dart :: parseCssColor > invalid colors return null and add a warning`<br>`test/compat/css_gradient_test.dart :: parseCssFill > plain colors parse as color fills`<br>`test/compat/css_misc_test.dart :: compat misc parsers > parseCssFontWeight maps keywords and numbers`<br>`test/compat/wheel_compat_test.dart :: wheelFromLuckyCanvasConfig > unknown keys and callbacks produce warnings not errors`<br>`test/compat/grid_compat_test.dart :: gridFromLuckyCanvasConfig > button callbacks are dropped with a warning` | 单元 | 已落地 |
| R3-28 | fromLuckyCanvasConfig 三个入口完整映射上游配置 | 需求3 | `test/compat/css_misc_test.dart :: compat misc parsers > image src maps to Network Memory or Asset providers`<br>`test/compat/wheel_compat_test.dart :: wheelFromLuckyCanvasConfig > maps blocks prizes buttons defaultConfig and defaultStyle with upstream defaults`<br>`test/compat/wheel_compat_test.dart :: wheelFromLuckyCanvasConfig > strictUpstream selects frame timebase and upstream solver`<br>`test/compat/grid_compat_test.dart :: gridFromLuckyCanvasConfig > maps rows cols cells activeStyle and the legacy button field`<br>`test/compat/slot_compat_test.dart :: slotFromLuckyCanvasConfig > maps slots order speed direction and mode` | 单元 | 已落地 |
| R3-29 | 注入 Random 可复现、无头时钟可测 | 需求3 | `test/core/picker/prize_picker_test.dart :: WeightedPrizePicker > uses the injected Random for reproducible picks`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > stopRange draws exactly one random number per stop in upstream order`<br>`test/wheel/wheel_controller_test.dart :: WheelController > controller works headless with a ManualLuckyClock (#342)`<br>`test/lotto/lotto_controller_test.dart :: LottoController > stop() samples without replacement using the injected Random` | 单元 | 已落地 |
| R3-30 | speedFunction 名称映射只在 compat | 需求3/6 | `test/compat/wheel_compat_test.dart :: wheelFromLuckyCanvasConfig > speedFunction is ignored unless honorSpeedFunction is set`<br>`test/compat/wheel_compat_test.dart :: wheelFromLuckyCanvasConfig > kLuckyCanvasEasingNames covers all seven upstream easings` | 单元 | 已落地 |
| R3-31 | 自定义绘制层 API | 需求3 | `test/core/render/layer_test.dart :: LuckyLayer > static layers are recorded into the cache and not repainted per frame`<br>`test/core/render/layer_test.dart :: LuckyLayer > dynamic layers paint every frame in position order`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > layers receive wheel layout and frame`<br>`test/slot/payline_test.dart :: SlotPayline > winning paylines are reported in SlotResult and highlighted by SlotPaylineLayer` | widget、单元 | 已落地 |
| R3-32 | testing.dart 测试辅助 | 需求3 | `test/testing/testing_helpers_test.dart :: testing helpers > ManualLuckyClock ticks only while started`<br>`test/testing/testing_helpers_test.dart :: testing helpers > SequenceRandom replays values and throws when exhausted`<br>`test/testing/testing_helpers_test.dart :: testing helpers > LuckyFrameRecorder records one entry per tick` | 单元 | 已落地 |
| R3-34 | 配置对象不可变、const 友好、copyWith、值相等 | 需求3 | `test/core/foundation/length_test.dart :: LuckyLength > equality and hashCode are value based`<br>`test/core/foundation/models_test.dart :: core models > LuckyText LuckyImage LuckyCellStyle and LuckyBoxBlock are const and value-equal`<br>`test/core/foundation/models_test.dart :: core models > copyWith replaces only the given fields`<br>`test/core/motion/motion_options_test.dart :: LuckyMotionOptions > equality and copyWith are value based` | 单元 | 已落地 |
| R3-35 | 经过回调（onSectorPassed/onActiveChanged/onCellPassed） | 需求3/#265 | `test/wheel/wheel_motion_test.dart :: WheelMotion edges > onSectorPassed fires once per boundary crossing`<br>`test/grid/grid_motion_test.dart :: GridMotion > onActiveChanged fires for every index step`<br>`test/slot/slot_motion_test.dart :: SlotMotion > onCellPassed fires per reel per cell boundary (#265)`<br>`test/number_wheel/number_wheel_widget_test.dart :: LuckyNumberWheel > onPocketPassed fires as the ball passes pockets`<br>`test/lotto/lotto_widget_test.dart :: LuckyLotto > onBallDrawn fires once per drawn ball` | widget、单元 | 已落地 |
| R4-01 | lib/ 行覆盖率 100% 门禁 | 需求4 | `test/tool/coverage_test.dart :: coverage gate > uninstrumented implementation files fail the gate`<br>`cmd: dart run tool/coverage.dart --min=100` | 命令、工具 | 已落地 |
| R4-02 | 覆盖率豁免逐行登记编号与原因 | 需求4 | `test/tool/coverage_test.dart :: coverage gate > ignore markers require a registered exemption id`<br>`test/tool/coverage_test.dart :: coverage gate > unused registered exemptions fail the gate` | 工具 | 已落地 |
| R4-03 | 验收矩阵引用与注册测试双向一致 | 需求4 | `test/tool/check_acceptance_test.dart :: check_acceptance > expands string literal list parameters without quotes`<br>`test/tool/check_acceptance_test.dart :: check_acceptance > reports missing and unmapped references`<br>`test/tool/check_acceptance_test.dart :: check_acceptance > scans integration_test and bench directories`<br>`test/tool/check_acceptance_test.dart :: check_acceptance > validates cmd references point at existing scripts`<br>`cmd: dart run tool/check_acceptance.dart` | 命令、工具 | 已落地 |
| R4-04 | import 依赖图静态校验 | 需求4/6 | `test/tool/check_imports_test.dart :: check_imports > accepts the allowed dependency graph`<br>`cmd: dart run tool/check_imports.dart` | 命令、工具 | 已落地 |
| R4-05 | golden 测试（容差比较器） | 需求4 | `test/wheel/wheel_golden_test.dart :: wheel goldens > default six prize wheel at rest`<br>`test/wheel/wheel_golden_test.dart :: wheel goldens > wheel rotated 37 degrees mid spin`<br>`test/wheel/wheel_golden_test.dart :: wheel goldens > wheel with gutter blocks pointer and wrapped text`<br>`test/wheel/wheel_golden_test.dart :: wheel goldens > wheel with weighted sectors`<br>`test/grid/grid_golden_test.dart :: grid goldens > default 3x3 grid with center button`<br>`test/grid/grid_golden_test.dart :: grid goldens > grid with active cell shadow and gradient`<br>`test/grid/grid_golden_test.dart :: grid goldens > grid with merged cells and border`<br>`test/slot/slot_golden_test.dart :: slot goldens > vertical three reel slot at rest`<br>`test/slot/slot_golden_test.dart :: slot goldens > horizontal slot mid scroll`<br>`test/slot/slot_golden_test.dart :: slot goldens > non-square cells`<br>`test/slot/slot_golden_test.dart :: slot goldens > lever slot machine with a winning payline`<br>`test/capsule/capsule_golden_test.dart :: capsule goldens > capsule machine at rest`<br>`test/capsule/capsule_golden_test.dart :: capsule goldens > capsule machine mixing`<br>`test/capsule/capsule_golden_test.dart :: capsule goldens > capsule revealed in the tray`<br>`test/number_wheel/number_wheel_golden_test.dart :: number wheel goldens > number wheel 0 to 36 at rest`<br>`test/number_wheel/number_wheel_golden_test.dart :: number wheel goldens > number wheel ball on the track`<br>`test/number_wheel/number_wheel_golden_test.dart :: number wheel goldens > number wheel ball in the target pocket`<br>`test/lots/lots_golden_test.dart :: lots goldens > lots cylinder at rest`<br>`test/lots/lots_golden_test.dart :: lots goldens > lots shaking`<br>`test/lots/lots_golden_test.dart :: lots goldens > lots revealed stick`<br>`test/lotto/lotto_golden_test.dart :: lotto goldens > super lotto machine at rest`<br>`test/lotto/lotto_golden_test.dart :: lotto goldens > super lotto mixing`<br>`test/lotto/lotto_golden_test.dart :: lotto goldens > super lotto with all balls drawn`<br>`test/tool/golden_comparator_test.dart :: LuckyToleranceComparator > passes within the pixel tolerance and fails beyond it`<br>`test/tool/golden_comparator_test.dart :: LuckyToleranceComparator > writes a diff image on failure` | golden、工具 | 已落地 |
| R4-06 | 与上游 1:1 对照（数值逐帧 + 关键帧图像） | 需求4 | `test/parity/wheel_parity_test.dart :: wheel parity > case w01 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w02 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w03 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w04 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w05 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w06 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w01 keyframes match upstream within tolerance`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w02 keyframes match upstream within tolerance`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w03 keyframes match upstream within tolerance`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w04 keyframes match upstream within tolerance`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w05 keyframes match upstream within tolerance`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w06 keyframes match upstream within tolerance`<br>`test/parity/grid_parity_test.dart :: grid parity > case g01 currIndex sequence matches upstream`<br>`test/parity/grid_parity_test.dart :: grid parity > case g02 currIndex sequence matches upstream`<br>`test/parity/grid_parity_test.dart :: grid parity > case g03 currIndex sequence matches upstream`<br>`test/parity/grid_parity_test.dart :: grid parity > case g04 currIndex sequence matches upstream`<br>`test/parity/grid_parity_test.dart :: grid parity > case g05 currIndex sequence matches upstream`<br>`test/parity/grid_parity_test.dart :: grid parity > case g01 keyframes match upstream within tolerance`<br>`test/parity/grid_parity_test.dart :: grid parity > case g02 keyframes match upstream within tolerance`<br>`test/parity/grid_parity_test.dart :: grid parity > case g03 keyframes match upstream within tolerance`<br>`test/parity/grid_parity_test.dart :: grid parity > case g04 keyframes match upstream within tolerance`<br>`test/parity/grid_parity_test.dart :: grid parity > case g05 keyframes match upstream within tolerance`<br>`test/parity/slot_parity_test.dart :: slot parity > case s01 scroll sequence matches upstream`<br>`test/parity/slot_parity_test.dart :: slot parity > case s02 scroll sequence matches upstream`<br>`test/parity/slot_parity_test.dart :: slot parity > case s03 scroll sequence matches upstream`<br>`test/parity/slot_parity_test.dart :: slot parity > case s04 scroll sequence matches upstream`<br>`test/parity/slot_parity_test.dart :: slot parity > case s05 scroll sequence matches upstream`<br>`test/parity/slot_parity_test.dart :: slot parity > case s01 keyframes match upstream within tolerance`<br>`test/parity/slot_parity_test.dart :: slot parity > case s02 keyframes match upstream within tolerance`<br>`test/parity/slot_parity_test.dart :: slot parity > case s03 keyframes match upstream within tolerance`<br>`test/parity/slot_parity_test.dart :: slot parity > case s04 keyframes match upstream within tolerance`<br>`test/parity/slot_parity_test.dart :: slot parity > case s05 keyframes match upstream within tolerance`<br>`cmd: dart run tool/parity/generate.dart --verify-manifest` | 1:1 对照、命令 | 已落地 |
| R4-07 | 集成测试（真机/桌面，每项 3 次） | 需求4 | `example/integration_test/wheel_flow_test.dart :: wheel flow > tap start then server result settles on the target`<br>`example/integration_test/grid_flow_test.dart :: grid flow > highlight walks and settles on the target`<br>`example/integration_test/slot_flow_test.dart :: slot flow > three reels settle on stopEach indices`<br>`example/integration_test/lifecycle_test.dart :: lifecycle > background for 10 seconds then resume keeps state bounded`<br>`example/integration_test/resize_test.dart :: resize > window resize mid spin keeps phase and angle`<br>`example/integration_test/route_test.dart :: route > push and pop 20 times leaves no active ticker`<br>`example/integration_test/capsule_flow_test.dart :: capsule flow > knob tap then server result drops and reveals the target capsule`<br>`example/integration_test/lever_flow_test.dart :: lever flow > drag the lever then reels stop one by one on the targets`<br>`example/integration_test/lots_flow_test.dart :: lots flow > tap then server result lifts and reveals the target stick`<br>`example/integration_test/number_wheel_flow_test.dart :: number wheel flow > stopNumber on a server number lands the ball in that pocket`<br>`example/integration_test/lotto_flow_test.dart :: lotto flow > server draw lands seven balls in order` | 集成 | Windows/安卓各33/33 |
| R5-01 | 五份设计文档齐全且交叉引用一致（人工评审） | 需求5 | （人工评审，无测试） | 人工 | 待落地验证 |
| R5-02 | README 与 example 代码可编译 | 需求5 | `cmd: flutter analyze example` | 命令 | README 12块分析0 issue；发布项待验证 |
| R5-03 | 公共 API 有中文文档注释（public_member_api_docs） | 需求5 | `cmd: flutter analyze` | 命令 | 已落地（主会话全量 analyze 0 issue） |
| R6-01 | 无库级注册表/顶层副作用/part/runtimeType 分派 | 需求6 | `test/core/game/registry_test.dart :: LuckyGameRegistry > is empty by default and only contains explicitly added builders`<br>`test/tool/check_imports_test.dart :: check_imports > rejects top-level side-effect initializers and part directives`<br>`test/tool/check_imports_test.dart :: check_imports > rejects runtimeType dispatch mirrors and material imports`<br>`cmd: dart run tool/check_imports.dart` | widget、命令、工具 | 本地Web/APK各十探针零泄漏、预算回填；远程CI待验 |
| R6-02 | 只用转盘的产物不含 grid/slot/compat 源文件与符号 | 需求6 | `test/tool/treeshake_parser_test.dart :: treeshake parsers > sourcemap parser lists retained luckdraw source files`<br>`test/tool/treeshake_parser_test.dart :: treeshake parsers > apk size json parser finds package:luckdraw libraries`<br>`test/tool/treeshake_parser_test.dart :: treeshake parsers > probe assertions report forbidden files and symbols`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=wheel_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=wheel_only` | 命令、工具 | 本地Web/APK各十探针零泄漏、预算回填；远程CI待验 |
| R6-03 | 只用九宫格/只用老虎机同理 | 需求6 | `cmd: dart run tool/treeshake/check_treeshake.dart --probe=grid_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=slot_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=capsule_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=lots_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=lotto_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=number_wheel_only` | 命令 | 本地Web/APK各十探针零泄漏、预算回填；远程CI待验 |
| R6-04 | 只调用 wheelFromLuckyCanvasConfig 时不含 grid/slot | 需求6 | `cmd: dart run tool/treeshake/check_treeshake.dart --probe=compat_wheel` | 命令 | 本地Web/APK各十探针零泄漏、预算回填；远程CI待验 |
| R6-05 | 未引用的缓动类不进产物 | 需求6 | `test/core/easing/easing_test.dart :: LuckyEasings > easing aliases are const and identical across accesses`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=wheel_only` | 单元、命令 | 本地Web/APK各十探针零泄漏、预算回填；远程CI待验 |
| R6-06 | 产物体积回归预算 | 需求6 | `cmd: dart run tool/treeshake/check_treeshake.dart --probe=all_games`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=wheel_only` | 命令 | 本地Web/APK各十探针零泄漏、预算回填；远程CI待验 |
| R6-07 | 包内不声明 assets/fonts | 需求6 | `test/tool/check_imports_test.dart :: check_imports > rejects asset or font declarations in pubspec`<br>`cmd: dart run tool/check_imports.dart` | 命令、工具 | 本地Web/APK各十探针零泄漏、预算回填；远程CI待验 |
| SM-E01 | 状态机迁移边 E01（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > grid E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > slot E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > lots E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E01 idle play() -> accelerating and returns true` | 单元 | 已落地 |
| SM-E02 | 状态机迁移边 E02（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E02 settled play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > grid E02 settled play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > slot E02 settled play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E02 settled play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > lots E02 settled play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E02 settled play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E02 settled play() -> accelerating and returns true`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > next play restores the dropped capsule to the pile` | 单元 | 已落地 |
| SM-E03 | 状态机迁移边 E03（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > grid E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > slot E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > lots E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E03 idleSpinning play() -> accelerating from idle speed`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion edges > idle spin rotates at idleSpinSpeed and play accelerates from it` | 单元 | 已落地 |
| SM-E04 | 状态机迁移边 E04（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E04 idle idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > grid E04 idle idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > slot E04 idle idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E04 idle idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > lots E04 idle idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E04 idle idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E04 idle idleSpin() -> idleSpinning` | 单元 | 已落地 |
| SM-E05 | 状态机迁移边 E05（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E05 settled idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > grid E05 settled idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > slot E05 settled idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E05 settled idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > lots E05 settled idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E05 settled idleSpin() -> idleSpinning`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E05 settled idleSpin() -> idleSpinning` | 单元 | 已落地 |
| SM-E06 | 状态机迁移边 E06（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E06 idleSpinning cancel() -> idle without end callback`<br>`test/core/control/state_machine_test.dart :: state machine > grid E06 idleSpinning cancel() -> idle without end callback`<br>`test/core/control/state_machine_test.dart :: state machine > slot E06 idleSpinning cancel() -> idle without end callback`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E06 idleSpinning cancel() -> idle without end callback`<br>`test/core/control/state_machine_test.dart :: state machine > lots E06 idleSpinning cancel() -> idle without end callback`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E06 idleSpinning cancel() -> idle without end callback`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E06 idleSpinning cancel() -> idle without end callback` | 单元 | 已落地 |
| SM-E07 | 状态机迁移边 E07（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E07 accelerating past accelerationTime -> cruising`<br>`test/core/control/state_machine_test.dart :: state machine > grid E07 accelerating past accelerationTime -> cruising`<br>`test/core/control/state_machine_test.dart :: state machine > slot E07 accelerating past accelerationTime -> cruising`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E07 accelerating past accelerationTime -> cruising`<br>`test/core/control/state_machine_test.dart :: state machine > lots E07 accelerating past accelerationTime -> cruising`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E07 accelerating past accelerationTime -> cruising`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E07 accelerating past accelerationTime -> cruising` | 单元 | 已落地 |
| SM-E08 | 状态机迁移边 E08（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E08 accelerating stop(i) stays accelerating with stop pending`<br>`test/core/control/state_machine_test.dart :: state machine > grid E08 accelerating stop(i) stays accelerating with stop pending`<br>`test/core/control/state_machine_test.dart :: state machine > slot E08 accelerating stop(i) stays accelerating with stop pending`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E08 accelerating stop(i) stays accelerating with stop pending`<br>`test/core/control/state_machine_test.dart :: state machine > lots E08 accelerating stop(i) stays accelerating with stop pending`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E08 accelerating stop(i) stays accelerating with stop pending`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E08 accelerating stop(i) stays accelerating with stop pending`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > stop during acceleration keeps accelerating until accelerationTime` | 单元 | 已落地 |
| SM-E09 | 提前 stop：wheel/grid 直接减速，slot 含 cruising 帧（历史名保留，见 §5.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E09 pending stop at end of acceleration -> cruising one tick -> decelerating`<br>`test/core/control/state_machine_test.dart :: state machine > grid E09 pending stop at end of acceleration -> cruising one tick -> decelerating`<br>`test/core/control/state_machine_test.dart :: state machine > slot E09 pending stop at end of acceleration -> cruising one tick -> decelerating`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E09 pending stop at end of acceleration -> cruising one tick -> decelerating`<br>`test/core/control/state_machine_test.dart :: state machine > lots E09 pending stop at end of acceleration -> cruising one tick -> decelerating`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E09 pending stop at end of acceleration -> cruising one tick -> decelerating`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E09 pending stop at end of acceleration -> cruising one tick -> decelerating` | 单元 | 已落地 |
| SM-E10 | 状态机迁移边 E10（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E10 cruising stop(i) -> decelerating on the next tick`<br>`test/core/control/state_machine_test.dart :: state machine > grid E10 cruising stop(i) -> decelerating on the next tick`<br>`test/core/control/state_machine_test.dart :: state machine > slot E10 cruising stop(i) -> decelerating on the next tick`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E10 cruising stop(i) -> decelerating on the next tick`<br>`test/core/control/state_machine_test.dart :: state machine > lots E10 cruising stop(i) -> decelerating on the next tick`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E10 cruising stop(i) -> decelerating on the next tick`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E10 cruising stop(i) -> decelerating on the next tick` | 单元 | 已落地 |
| SM-E11 | 状态机迁移边 E11（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > grid E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > slot E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > lots E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E11 decelerating past decelerationTime -> settled with result` | 单元 | 已落地 |
| SM-E12 | 状态机迁移边 E12（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E12 accelerating cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > grid E12 accelerating cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > slot E12 accelerating cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E12 accelerating cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > lots E12 accelerating cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E12 accelerating cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E12 accelerating cancel() -> idle cancelled` | 单元 | 已落地 |
| SM-E13 | 状态机迁移边 E13（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E13 cruising cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > grid E13 cruising cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > slot E13 cruising cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E13 cruising cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > lots E13 cruising cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E13 cruising cancel() -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E13 cruising cancel() -> idle cancelled` | 单元 | 已落地 |
| SM-E14 | 状态机迁移边 E14（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E14 cruising stop(negative) -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > grid E14 cruising stop(negative) -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > slot E14 cruising stop(negative) -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E14 cruising stop(negative) -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > lots E14 cruising stop(negative) -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E14 cruising stop(negative) -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E14 cruising stop(negative) -> idle cancelled` | 单元 | 已落地 |
| SM-E15 | 状态机迁移边 E15（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E15 stop() with picker returning null -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > grid E15 stop() with picker returning null -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > slot E15 stop() with picker returning null -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E15 stop() with picker returning null -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > lots E15 stop() with picker returning null -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E15 stop() with picker returning null -> idle cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E15 stop() with picker returning null -> idle cancelled`<br>`test/wheel/wheel_controller_test.dart :: WheelController > playUntil with a null index cancels` | 单元 | 已落地 |
| SM-E16 | 状态机迁移边 E16（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E16 decelerating ignores stop() and cancel()`<br>`test/core/control/state_machine_test.dart :: state machine > grid E16 decelerating ignores stop() and cancel()`<br>`test/core/control/state_machine_test.dart :: state machine > slot E16 decelerating ignores stop() and cancel()`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E16 decelerating ignores stop() and cancel()`<br>`test/core/control/state_machine_test.dart :: state machine > lots E16 decelerating ignores stop() and cancel()`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E16 decelerating ignores stop() and cancel()`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E16 decelerating ignores stop() and cancel()`<br>`test/lotto/lotto_controller_test.dart :: LottoController > cancel during drawing is ignored like other decelerating phases` | 单元 | 已落地 |
| SM-E17 | 状态机迁移边 E17（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E17 idle and settled ignore stop()`<br>`test/core/control/state_machine_test.dart :: state machine > grid E17 idle and settled ignore stop()`<br>`test/core/control/state_machine_test.dart :: state machine > slot E17 idle and settled ignore stop()`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E17 idle and settled ignore stop()`<br>`test/core/control/state_machine_test.dart :: state machine > lots E17 idle and settled ignore stop()`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E17 idle and settled ignore stop()`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E17 idle and settled ignore stop()` | 单元 | 已落地 |
| SM-E18 | 状态机迁移边 E18（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > grid E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > slot E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > lots E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E18 moving ignores play() (#370)`<br>`test/slot/lever_test.dart :: LuckyLeverSlotMachine > pulling while moving calls onPull but does not play again` | widget、单元 | 已落地 |
| SM-E19 | 状态机迁移边 E19（ARCHITECTURE §9.2） | 需求3/4 | `test/core/motion/timeline_test.dart :: LuckyTimeline > paused timeline does not advance and resumes without a jump`<br>`test/core/control/state_machine_test.dart :: state machine > wheel E19 pause() freezes and resume() continues without a jump`<br>`test/core/control/state_machine_test.dart :: state machine > grid E19 pause() freezes and resume() continues without a jump`<br>`test/core/control/state_machine_test.dart :: state machine > slot E19 pause() freezes and resume() continues without a jump`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E19 pause() freezes and resume() continues without a jump`<br>`test/core/control/state_machine_test.dart :: state machine > lots E19 pause() freezes and resume() continues without a jump`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E19 pause() freezes and resume() continues without a jump`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E19 pause() freezes and resume() continues without a jump` | 单元 | 已落地 |
| SM-E20 | 状态机迁移边 E20（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > grid E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > slot E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > lots E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E20 reset() from any phase -> idle at origin` | 单元 | 已落地 |
| SM-E21 | 状态机迁移边 E21（ARCHITECTURE §9.2） | 需求3/4 | `test/core/widgets/game_view_test.dart :: LuckyGameView > dispose stops the ticker and completes pending playUntil as cancelled`<br>`test/core/control/state_machine_test.dart :: state machine > wheel E21 dispose while moving emits no further callbacks`<br>`test/core/control/state_machine_test.dart :: state machine > grid E21 dispose while moving emits no further callbacks`<br>`test/core/control/state_machine_test.dart :: state machine > slot E21 dispose while moving emits no further callbacks`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E21 dispose while moving emits no further callbacks`<br>`test/core/control/state_machine_test.dart :: state machine > lots E21 dispose while moving emits no further callbacks`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E21 dispose while moving emits no further callbacks`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E21 dispose while moving emits no further callbacks` | widget、单元 | 已落地 |
| SM-E22 | 状态机迁移边 E22（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E22 idleSpinning ignores stop()`<br>`test/core/control/state_machine_test.dart :: state machine > grid E22 idleSpinning ignores stop()`<br>`test/core/control/state_machine_test.dart :: state machine > slot E22 idleSpinning ignores stop()`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E22 idleSpinning ignores stop()`<br>`test/core/control/state_machine_test.dart :: state machine > lots E22 idleSpinning ignores stop()`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E22 idleSpinning ignores stop()`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E22 idleSpinning ignores stop()` | 单元 | 已落地 |
| SM-E23 | 状态机迁移边 E23（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E23 100 consecutive draws return to settled (#175)`<br>`test/core/control/state_machine_test.dart :: state machine > grid E23 100 consecutive draws return to settled (#175)`<br>`test/core/control/state_machine_test.dart :: state machine > slot E23 100 consecutive draws return to settled (#175)`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E23 100 consecutive draws return to settled (#175)`<br>`test/core/control/state_machine_test.dart :: state machine > lots E23 100 consecutive draws return to settled (#175)`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E23 100 consecutive draws return to settled (#175)`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E23 100 consecutive draws return to settled (#175)` | 单元 | 已落地 |
| SM-E24 | 状态机迁移边 E24（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E24 stop() without index uses the picker and still decelerates (#355)`<br>`test/core/control/state_machine_test.dart :: state machine > grid E24 stop() without index uses the picker and still decelerates (#355)`<br>`test/core/control/state_machine_test.dart :: state machine > slot E24 stop() without index uses the picker and still decelerates (#355)`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E24 stop() without index uses the picker and still decelerates (#355)`<br>`test/core/control/state_machine_test.dart :: state machine > lots E24 stop() without index uses the picker and still decelerates (#355)`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E24 stop() without index uses the picker and still decelerates (#355)`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E24 stop() without index uses the picker and still decelerates (#355)`<br>`test/capsule/capsule_controller_test.dart :: CapsuleController > stop() without index uses the picker`<br>`test/number_wheel/number_wheel_controller_test.dart :: NumberWheelController > stop() without index uses the picker`<br>`test/lots/lots_controller_test.dart :: LotsController > stop() without index uses the picker` | 单元 | 已落地 |
| SM-E25 | 老虎机取消不发 onEnd（ARCHITECTURE §9.2） | 上游 slot.ts | `test/slot/slot_controller_test.dart :: SlotController > E25 cancel emits no end callback like upstream` | 单元 | 已落地 |
| SM-E26 | 状态机迁移边 E26（ARCHITECTURE §9.2） | 需求3/4 | `test/core/control/state_machine_test.dart :: state machine > wheel E26 pause() is ignored when idle or settled`<br>`test/core/control/state_machine_test.dart :: state machine > grid E26 pause() is ignored when idle or settled`<br>`test/core/control/state_machine_test.dart :: state machine > slot E26 pause() is ignored when idle or settled`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E26 pause() is ignored when idle or settled`<br>`test/core/control/state_machine_test.dart :: state machine > lots E26 pause() is ignored when idle or settled`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E26 pause() is ignored when idle or settled`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E26 pause() is ignored when idle or settled` | 单元 | 已落地 |
| ISS-120HZ | 最终停点一致，加速段中间相位差 ≤6°（保留历史测试名） | C5 | `test/wheel/wheel_motion_test.dart :: WheelMotion time timebase > covers the same angle at 60Hz and 120Hz within 0.5 degrees` | 单元 | 已落地 |
| ISS-146 | 旋转中 resize 不丢状态 | #146 | `test/core/widgets/game_view_test.dart :: LuckyGameView > resize keeps motion state and only recomputes layout (#146)`<br>`test/slot/slot_motion_test.dart :: SlotMotion > resize mid-spin rescales scroll by the cellAndSpacing ratio`<br>`example/integration_test/resize_test.dart :: resize > window resize mid spin keeps phase and angle` | widget、单元、集成 | 部分已落地；其余待落地验证 |
| ISS-150 | 停点落在扇区中线 ± stopRange | #150 | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > uniform sector middles start at -90 + prizeDeg / 2 + offsetDegree`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > final angle puts the target sector middle under the pointer plus stopRange` | 单元 | 已落地 |
| ISS-151 | 扇区不等分 | #151 | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > sector weights produce proportional sweeps (#151)`<br>`test/wheel/wheel_golden_test.dart :: wheel goldens > wheel with weighted sectors` | golden、单元 | 已落地 |
| ISS-153 | 按钮纯展示 | #153 | `test/core/widgets/game_view_test.dart :: LuckyGameView > without tap callbacks no gesture recognizer is attached (#153)` | widget | 已落地 |
| ISS-176 | 每帧 save/restore 平衡 | #176 | `test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > painting never calls saveLayer and keeps save count balanced (#176)`<br>`test/grid/grid_painter_test.dart :: GridCanvasRenderer > painting never calls saveLayer and keeps save count balanced` | widget | 已落地 |
| ISS-182 | 老虎机多列结果与可替换判定 | #182 | `test/slot/slot_motion_test.dart :: SlotMotion > a custom win predicate decides the prize (#182)`<br>`test/slot/slot_controller_test.dart :: SlotController > stopEach result carries indices and the winning prize`<br>`test/slot/slot_widget_test.dart :: LuckySlotMachine > onEnd receives a SlotResult with indices and prize` | widget、单元 | 已落地 |
| ISS-205 | 未触发方向修正的 nearest 搜索满足半周期上界；自由停速度连续 | #205 | `test/core/motion/stop_solver_test.dart :: MonotonicStopSolver > decel first-frame speed differs from cruise by at most half a period increment (#205)`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > deceleration starts at cruise speed without a jump` | 单元 | 已落地 |
| ISS-227 | 指示器叠加层 | #227 | `test/core/render/layer_test.dart :: LuckyLayer > foreground layer draws above items for indicators (#227)`<br>`test/slot/slot_widget_test.dart :: LuckySlotMachine > foreground indicator layer paints above reels (#227)` | widget | 已落地 |
| ISS-233 | 单列老虎机 | #233 | `test/slot/slot_layout_test.dart :: computeSlotLayout > a single reel lays out (#233)` | 单元 | 已落地 |
| ISS-254 | 图片圆角 | #254 | `test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > image borderRadius clips the image (#254)` | widget | 已落地 |
| ISS-264 | 加载竞态：迟到结果被丢弃 | #264 | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > changing sources drops late results from stale generations (#264)` | widget | 已落地 |
| ISS-265 | 老虎机非正方形格 + 经过回调 | #265 | `test/slot/slot_layout_test.dart :: computeSlotLayout > cellAspectRatio produces non-square cells (#265)`<br>`test/slot/slot_motion_test.dart :: SlotMotion > onCellPassed fires per reel per cell boundary (#265)`<br>`test/slot/slot_golden_test.dart :: slot goldens > non-square cells` | golden、单元 | 已落地 |
| ISS-287 | 回调总取最新 | #287 | `test/core/widgets/game_view_test.dart :: LuckyGameView > didUpdateWidget always uses the latest callbacks (#287)` | widget | 已落地 |
| ISS-297 | 奖品数 50 仍可渲染且无超限纹理 | #297 | `test/core/render/picture_cache_test.dart :: LuckyPictureCache > raster mode falls back to picture when side times dpr exceeds maxRasterSide`<br>`test/slot/slot_layout_test.dart :: computeSlotLayout > fifty prizes need no texture taller than maxRasterSide (#297)`<br>`tool/bench/integration_test/slot_bench_test.dart :: bench > slot 3 reels 10 prizes steady scroll` | 单元、基准 | 已落地 |
| ISS-304 | activeStyle 同构 + border/foreground | #304 | `test/grid/grid_layout_test.dart :: computeGridLayout > active style replaces background and shadow and overrides text fields`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > border and foreground are laid out for normal and active styles (#304 #347)`<br>`test/grid/grid_golden_test.dart :: grid goldens > grid with merged cells and border` | golden、单元 | 已落地 |
| ISS-308 | 一帧跳 10 分钟后状态有界且收敛；后台暂停 | #308 | `test/core/motion/timeline_test.dart :: LuckyTimeline > a single 10 minute jump advances effective time by at most maxFrameDelta`<br>`test/core/widgets/game_view_test.dart :: LuckyGameView > pauses when the app is hidden and resumes on resumed`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion edges > a 10 minute frame gap keeps the angle finite and still settles (#308)`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > a 10 minute frame gap keeps positions finite and still settles`<br>`test/number_wheel/number_wheel_motion_test.dart :: NumberWheelMotion > a 10 minute frame gap keeps angles finite and still settles`<br>`test/lots/lots_motion_test.dart :: LotsMotion > a 10 minute frame gap keeps the angle finite and still settles`<br>`test/lotto/lotto_motion_test.dart :: LottoMotion > a 10 minute frame gap keeps positions finite and still settles`<br>`example/integration_test/lifecycle_test.dart :: lifecycle > background for 10 seconds then resume keeps state bounded` | widget、单元、集成 | 部分已落地；其余待落地验证 |
| ISS-327 | 缓动可定制 | #327 | `test/core/easing/easing_test.dart :: LuckyEasings > CurveEasing maps Curve.transform onto t b c d` | 单元 | 已落地 |
| ISS-335 | GIF 只取首帧；叠加层可放动图 | #335 | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > only the first frame of an animated image is kept`<br>`test/core/widgets/item_overlay_test.dart :: LuckyItemOverlay > repaints child transforms without rebuilding children` | widget | 已落地 |
| ISS-336 | 宽高为 0/负 padding 不抛异常 | #336 | `test/core/geometry/fan_path_test.dart :: buildFanPath > non-positive outer radius yields an empty path`<br>`test/core/geometry/round_rect_test.dart :: buildRoundRectPath > non-positive width or height yields an empty path`<br>`test/core/geometry/round_rect_test.dart :: buildRoundRectPath > negative radius is treated as zero`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > padding larger than the radius clamps to zero without throwing (#336)` | 单元 | 已落地 |
| ISS-342 | 纯动画 API / 自定义渲染 | #342 | `test/wheel/wheel_controller_test.dart :: WheelController > controller works headless with a ManualLuckyClock (#342)`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > a custom renderer replaces the canvas renderer` | widget、单元 | 已落地 |
| ISS-354 | 文字方向 v2；v1 用 prize painter 自绘 | #354 | `test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > prize painter paints in sector-local coordinates (#354 workaround)` | widget | 已落地 |
| ISS-370 | 运动中按钮仍上报 onButtonTap；idleSpin | #370 | `test/core/control/state_machine_test.dart :: state machine > wheel E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > grid E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > slot E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > lots E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E03 idleSpinning play() -> accelerating from idle speed`<br>`test/core/control/state_machine_test.dart :: state machine > wheel E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > grid E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > slot E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > lots E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E18 moving ignores play() (#370)`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E18 moving ignores play() (#370)`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion edges > idle spin rotates at idleSpinSpeed and play accelerates from it`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > onButtonTap fires in every phase with the current phase (#370)` | widget、单元 | 已落地 |
| ISS-382 | 运行中改配置不重置动画 | #382 | `test/wheel/wheel_motion_test.dart :: WheelMotion edges > structural config change during deceleration is deferred until settled`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > prize count change while cruising applies immediately keeping the angle (#382)`<br>`test/grid/grid_widget_test.dart :: LuckyGrid > activeStyle change repaints without restarting motion` | widget、单元 | 已落地 |
| ISS-402 | 渐变背景 | #402 | `test/core/foundation/fill_test.dart :: LuckyFill > gradient fill creates a shader for the given rect`<br>`test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > gradient backgrounds are supported on prizes and blocks (#402)` | widget、单元 | 已落地 |
| ISS-417 | 图片失败不阻塞首帧并触发 onImageError | #417 | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > image arrivals bump the generation and notify listeners`<br>`test/core/image/image_resolver_test.dart :: LuckyImageResolver > failure calls onImageError and does not block other images (#417)`<br>`test/core/image/image_resolver_test.dart :: LuckyImageResolver > fallback provider is used when the primary fails`<br>`test/core/image/image_resolver_test.dart :: LuckyImageResolver > onReady fires once after every image settled including failures`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > onReady fires after images settle and onImageError reports failures (#417)`<br>`test/grid/grid_widget_test.dart :: LuckyGrid > images load progressively and failures use the fallback` | widget | 已落地 |
| ISS-419 | 停止求解单调，不倒转 | #419 | `test/core/motion/stop_solver_test.dart :: UpstreamStopSolver > reproduces negative displacement when deceleration is short (#419)`<br>`test/core/motion/stop_solver_test.dart :: MonotonicStopSolver > equals upstream whenever the upstream displacement is positive`<br>`test/core/motion/stop_solver_test.dart :: MonotonicStopSolver > never returns a displacement against the direction across the parameter grid`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion edges > monotonic solver never rotates backwards on the #419 grid`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion edges > upstream solver reproduces backward rotation on the #419 grid`<br>`test/grid/grid_motion_test.dart :: GridMotion > monotonic solver never decreases currIndex on a short deceleration grid`<br>`test/number_wheel/number_wheel_motion_test.dart :: NumberWheelMotion > ball relative angle uses the monotonic stop solver and never reverses` | 单元 | 已落地 |
| ISS-448 | 结果 index 与指针下扇区一致 | #448 | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > sectorAtPointer inverts the final angle to the target sector`<br>`test/wheel/wheel_controller_test.dart :: WheelController > settled result index equals the sector under the pointer (#448)` | 单元 | 已落地 |
| FID-G01 | 上游对照：九宫格字段映射 | FIDELITY | `test/grid/grid_motion_test.dart :: GridMotion > acceleration uses easeIn(t, 0.1, speed - 0.1) with speed = config.speed / 40` | 单元 | 已落地 |
| FID-G02 | 上游对照：九宫格初始无高亮 | FIDELITY | `test/grid/grid_motion_test.dart :: GridMotion > no cell is active before the first play and after cancel` | 单元 | 已落地 |
| FID-G03 | 上游对照：九宫格默认值与 speed/40 | FIDELITY | `test/grid/grid_motion_test.dart :: GridMotion > acceleration uses easeIn(t, 0.1, speed - 0.1) with speed = config.speed / 40`<br>`test/compat/grid_compat_test.dart :: gridFromLuckyCanvasConfig > maps rows cols cells activeStyle and the legacy button field` | 单元 | 已落地 |
| FID-G04 | 上游对照：九宫格 watch | FIDELITY | `test/grid/grid_widget_test.dart :: LuckyGrid > activeStyle change repaints without restarting motion` | widget | 已落地 |
| FID-G05 | 上游对照：九宫格点击命中 | FIDELITY | `test/grid/grid_layout_test.dart :: computeGridLayout > cell geometry supports col and row spans`<br>`test/grid/grid_controller_test.dart :: GridController > tapping a button calls onStart only in idle-like phases and onButtonTap always`<br>`test/grid/grid_controller_test.dart :: GridController > hit test ignores the shadow shrink like getGeometricProperty`<br>`test/grid/grid_controller_test.dart :: GridController > overlapping buttons all fire like upstream forEach` | widget、单元 | 已落地 |
| FID-G06 | 上游对照：activeSrc | FIDELITY | `test/grid/grid_layout_test.dart :: computeGridLayout > activeImage is used only when active and the base image is loaded` | 单元 | 已落地 |
| FID-G07 | 上游对照：九宫格 draw 几何 | FIDELITY | `test/grid/grid_layout_test.dart :: computeGridLayout > prize area shrinks by each block padding`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > cell size subtracts gutters`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > shadow shrinks the cell rect by its offsets like upstream`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > shadow applies only when the cell has a background`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > active style replaces background and shadow and overrides text fields`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > active line height ignores the active fontSize like upstream`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > texts wrap to lengthLimit of the cell width and keep empty lines`<br>`test/compat/css_shadow_test.dart :: parseCssShadow > only the first of multiple shadows is used`<br>`test/compat/css_shadow_test.dart :: parseCssShadow > shadows without exactly four parts are ignored like upstream`<br>`test/parity/grid_parity_test.dart :: grid parity > case g01 keyframes match upstream within tolerance`<br>`test/parity/grid_parity_test.dart :: grid parity > case g02 keyframes match upstream within tolerance`<br>`test/parity/grid_parity_test.dart :: grid parity > case g03 keyframes match upstream within tolerance`<br>`test/parity/grid_parity_test.dart :: grid parity > case g04 keyframes match upstream within tolerance`<br>`test/parity/grid_parity_test.dart :: grid parity > case g05 keyframes match upstream within tolerance` | 1:1 对照、单元 | 已落地 |
| FID-G08 | 上游对照：handleBackground | FIDELITY | `test/grid/grid_painter_test.dart :: GridCanvasRenderer > gradient background uses legacy endpoints on the shrunk rect` | widget | 已落地 |
| FID-G09 | 上游对照：九宫格停止求解 | FIDELITY | `test/grid/grid_motion_test.dart :: GridMotion > final currIndex lands on prizes.length * i + target` | 单元 | 已落地 |
| FID-G10 | 上游对照：九宫格 run 逐帧 | FIDELITY | `test/grid/grid_motion_test.dart :: GridMotion > acceleration uses easeIn(t, 0.1, speed - 0.1) with speed = config.speed / 40`<br>`test/grid/grid_motion_test.dart :: GridMotion > active index is the truncated currIndex remainder prizes length`<br>`test/grid/grid_motion_test.dart :: GridMotion > the active cell stays highlighted after settling`<br>`test/parity/grid_parity_test.dart :: grid parity > case g01 currIndex sequence matches upstream`<br>`test/parity/grid_parity_test.dart :: grid parity > case g02 currIndex sequence matches upstream`<br>`test/parity/grid_parity_test.dart :: grid parity > case g03 currIndex sequence matches upstream`<br>`test/parity/grid_parity_test.dart :: grid parity > case g04 currIndex sequence matches upstream`<br>`test/parity/grid_parity_test.dart :: grid parity > case g05 currIndex sequence matches upstream` | 1:1 对照、单元 | 已落地 |
| FID-G11 | 上游对照：getGeometricProperty | FIDELITY | `test/grid/grid_layout_test.dart :: computeGridLayout > cell size subtracts gutters`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > cell geometry supports col and row spans` | 单元 | 已落地 |
| FID-L01 | 上游对照：构造与尺寸监听 | FIDELITY | `test/core/widgets/game_view_test.dart :: LuckyGameView > resize keeps motion state and only recomputes layout (#146)` | widget | 已落地 |
| FID-L02 | 上游对照：resize 流程 | FIDELITY | `test/core/widgets/game_view_test.dart :: LuckyGameView > resize keeps motion state and only recomputes layout (#146)` | widget | 已落地 |
| FID-L03 | 上游对照：0 尺寸 | FIDELITY | `test/core/widgets/game_view_test.dart :: LuckyGameView > zero size paints nothing and does not throw` | widget | 已落地 |
| FID-L04 | 上游对照：handleClick | FIDELITY | `test/wheel/wheel_widget_test.dart :: LuckyWheel > tap inside the button radius calls onStart only in idle-like phases` | widget | 已落地 |
| FID-L05 | 上游对照：rem 基准 | FIDELITY | `test/compat/css_length_test.dart :: parseCssLength > rem uses remBase and vw uses viewportWidth` | 单元 | 已落地 |
| FID-L08 | 上游对照：宽高来源 | FIDELITY | `test/wheel/wheel_widget_test.dart :: LuckyWheel > unbounded constraints without width or height throw a FlutterError with guidance` | widget | 已落地 |
| FID-L12 | 上游对照：loadImg | FIDELITY | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > image arrivals bump the generation and notify listeners` | widget | 已落地 |
| FID-L13 | 上游对照：drawImage 平滑 | FIDELITY | `test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > images are drawn with FilterQuality.low like canvas smoothing` | widget | 已落地 |
| FID-L14 | 上游对照：computedWidthAndHeight | FIDELITY | `test/core/geometry/image_box_test.dart :: computeImageBox > no width and height uses natural size`<br>`test/core/geometry/image_box_test.dart :: computeImageBox > only width scales height proportionally`<br>`test/core/geometry/image_box_test.dart :: computeImageBox > only height scales width proportionally`<br>`test/core/geometry/image_box_test.dart :: computeImageBox > both width and height are used as given`<br>`test/core/geometry/image_box_test.dart :: computeImageBox > percent sizes resolve against the provided max box` | 单元 | 已落地 |
| FID-L15 | 上游对照：changeUnits | FIDELITY | `test/core/foundation/length_test.dart :: LuckyLength > percent resolves as value * (base / 100) like upstream changeUnits`<br>`test/compat/css_length_test.dart :: parseCssLength > px number and unitless values parse as px`<br>`test/compat/css_length_test.dart :: parseCssLength > percent parses as LuckyPercent`<br>`test/compat/css_length_test.dart :: parseCssLength > rem uses remBase and vw uses viewportWidth`<br>`test/compat/css_length_test.dart :: parseCssLength > unknown units go to handleCssUnit or fall back to the number` | 单元 | 已落地 |
| FID-L16 | 上游对照：getLength | FIDELITY | `test/core/foundation/length_test.dart :: LuckyLength > px resolves to its value regardless of base`<br>`test/compat/css_length_test.dart :: parseCssLength > base-less percent resolves as n / 100 px like getLength without maxLength` | 单元 | 已落地 |
| FID-L17 | 上游对照：getOffsetX | FIDELITY | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > block image is centered and offset by top - radius` | 单元 | 已落地 |
| FID-L21 | 上游对照：生命周期钩子 | FIDELITY | `test/core/widgets/game_view_test.dart :: LuckyGameView > lifecycle hooks fire in upstream order` | widget | 已落地 |
| FID-S01 | 上游对照：老虎机字段映射 | FIDELITY | `test/slot/slot_motion_test.dart :: SlotMotion > scroll advances with remainder semantics for negative direction` | 单元 | 已落地 |
| FID-S02 | 上游对照：老虎机 initLucky | FIDELITY | `test/core/control/state_machine_test.dart :: state machine > wheel E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > grid E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > slot E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > lots E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E20 reset() from any phase -> idle at origin` | 单元 | 已落地 |
| FID-S03 | 上游对照：老虎机默认值 | FIDELITY | `test/compat/slot_compat_test.dart :: slotFromLuckyCanvasConfig > maps slots order speed direction and mode` | 单元 | 已落地 |
| FID-S04 | 上游对照：老虎机 watch | FIDELITY | `test/slot/slot_motion_test.dart :: SlotMotion > reel order change during deceleration is deferred until settled` | 单元 | 已落地 |
| FID-S05 | 上游对照：老虎机格子绘制 | FIDELITY | `test/compat/slot_compat_test.dart :: slotFromLuckyCanvasConfig > slot prize borderRadius 0 is kept like has()` | 单元 | 已落地 |
| FID-S06 | 上游对照：老虎机 drawBlocks | FIDELITY | `test/slot/slot_layout_test.dart :: computeSlotLayout > slot blocks fall back to the default style background` | 单元 | 已落地 |
| FID-S07 | 上游对照：老虎机可见窗口 | FIDELITY | `test/slot/slot_layout_test.dart :: computeSlotLayout > visible window start is -(h - heightAndSpacing) / 2`<br>`test/slot/slot_motion_test.dart :: SlotMotion > final scroll centers the target prize in the window`<br>`test/slot/slot_painter_test.dart :: SlotCanvasRenderer > draws only visible cells per reel clipped to the reel rect`<br>`test/slot/slot_painter_test.dart :: SlotCanvasRenderer > wrap-around draws the first prizes after the last`<br>`test/parity/slot_parity_test.dart :: slot parity > case s01 keyframes match upstream within tolerance`<br>`test/parity/slot_parity_test.dart :: slot parity > case s02 keyframes match upstream within tolerance`<br>`test/parity/slot_parity_test.dart :: slot parity > case s03 keyframes match upstream within tolerance`<br>`test/parity/slot_parity_test.dart :: slot parity > case s04 keyframes match upstream within tolerance`<br>`test/parity/slot_parity_test.dart :: slot parity > case s05 keyframes match upstream within tolerance` | 1:1 对照、widget、单元 | 已落地 |
| FID-S08 | 上游对照：老虎机停止求解 | FIDELITY | `test/core/motion/stop_solver_test.dart :: UpstreamStopSolver > firstExceeding selection matches the upstream slot carve for both directions`<br>`test/slot/slot_motion_test.dart :: SlotMotion > carve picks the first candidate whose speed magnitude exceeds the reel speed`<br>`test/slot/slot_motion_test.dart :: SlotMotion > final scroll centers the target prize in the window`<br>`test/slot/slot_stagger_test.dart :: SlotMotion stagger > staggered reels still land on their targets` | 单元 | 已落地 |
| FID-S09 | 上游对照：老虎机 play | FIDELITY | `test/core/control/state_machine_test.dart :: state machine > wheel E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > grid E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > slot E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > lots E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E01 idle play() -> accelerating and returns true` | 单元 | 已落地 |
| FID-S10 | 上游对照：老虎机 stop | FIDELITY | `test/slot/slot_controller_test.dart :: SlotController > stop(index) fills every reel` | 单元 | 已落地 |
| FID-S11 | 上游对照：老虎机 run 逐帧 | FIDELITY | `test/slot/slot_motion_test.dart :: SlotMotion > scroll advances with remainder semantics for negative direction`<br>`test/slot/slot_motion_test.dart :: SlotMotion > acceleration and cruising use per-reel speed and direction`<br>`test/slot/slot_motion_test.dart :: SlotMotion > default win predicate requires equal indices contained in every order`<br>`test/compat/slot_compat_test.dart :: slotFromLuckyCanvasConfig > zero speed or direction falls back to defaults`<br>`test/slot/slot_stagger_test.dart :: SlotMotion stagger > zero stopDelay keeps all reels identical to upstream`<br>`test/parity/slot_parity_test.dart :: slot parity > case s01 scroll sequence matches upstream`<br>`test/parity/slot_parity_test.dart :: slot parity > case s02 scroll sequence matches upstream`<br>`test/parity/slot_parity_test.dart :: slot parity > case s03 scroll sequence matches upstream`<br>`test/parity/slot_parity_test.dart :: slot parity > case s04 scroll sequence matches upstream`<br>`test/parity/slot_parity_test.dart :: slot parity > case s05 scroll sequence matches upstream` | 1:1 对照、单元 | 已落地 |
| FID-S12 | 上游对照：老虎机格子尺寸 | FIDELITY | `test/slot/slot_layout_test.dart :: computeSlotLayout > vertical mode cell width is (w - colSpacing * (n - 1)) / n and square`<br>`test/slot/slot_layout_test.dart :: computeSlotLayout > horizontal mode cell height is (h - rowSpacing * (n - 1)) / n and square`<br>`test/slot/slot_layout_test.dart :: computeSlotLayout > cellAndSpacing follows the mode` | 单元 | 已落地 |
| FID-U01 | 上游对照：getAngle | FIDELITY | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > uniform sector middles start at -90 + prizeDeg / 2 + offsetDegree` | 单元 | 已落地 |
| FID-U02 | 上游对照：getArcPointerByDeg | FIDELITY | `test/core/geometry/fan_path_test.dart :: buildFanPath > apex lies on the bisector at gutter / 2 / abs(sin(half sweep))` | 单元 | 已落地 |
| FID-U04 | 上游对照：fanShapedByArc | FIDELITY | `test/core/geometry/canvas_arc_test.dart :: canvasArcSweep > positive clockwise sweep is end minus start`<br>`test/core/geometry/canvas_arc_test.dart :: canvasArcSweep > negative clockwise sweep wraps modulo 2pi like the canvas spec`<br>`test/core/geometry/canvas_arc_test.dart :: canvasArcSweep > sweep of 2pi or more becomes a full circle`<br>`test/core/geometry/fan_path_test.dart :: buildFanPath > zero gutter fan apex is the center`<br>`test/core/geometry/fan_path_test.dart :: buildFanPath > gutter shrinks the outer arc by gutter / (2 * radius) radians on each side`<br>`test/core/geometry/fan_path_test.dart :: buildFanPath > apex lies on the bisector at gutter / 2 / abs(sin(half sweep))` | 单元 | 已落地 |
| FID-U05 | 上游对照：roundRectByArc | FIDELITY | `test/core/geometry/round_rect_test.dart :: buildRoundRectPath > radius is clamped to half of the shorter side`<br>`test/core/geometry/round_rect_test.dart :: buildRoundRectPath > zero radius produces a plain rectangle` | 单元 | 已落地 |
| FID-U06 | 上游对照：getLinearGradient 端点 | FIDELITY | `test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 0 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 30 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 45 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 60 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 90 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 120 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 135 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 150 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 180 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 200 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 225 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 250 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 270 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 300 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 315 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient endpoints match upstream at 340 deg`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient keywords top bottom left right map to upstream endpoints`<br>`test/core/foundation/fill_test.dart :: LuckyFill > legacy linear gradient truncates endpoints toward zero like >> 0`<br>`test/compat/css_gradient_test.dart :: parseCssFill > angle and keyword directions map to legacy linear fills` | 单元 | 已落地 |
| FID-U08 | 上游对照：7 组缓动公式 | FIDELITY | `test/core/easing/easing_test.dart :: LuckyEasings > quad easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > cubic easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > quart easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > quint easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > sine easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > expo easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > circ easeIn matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > quad easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > cubic easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > quart easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > quint easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > sine easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > expo easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > circ easeOut matches the upstream formula on a sample grid`<br>`test/core/easing/easing_test.dart :: LuckyEasings > every easing clamps t to d before evaluating`<br>`test/core/easing/easing_test.dart :: LuckyEasings > expo special-cases t == 0 and t == d like upstream` | 单元 | 已落地 |
| FID-U10 | 上游对照：removeEnter | FIDELITY | `test/core/text/split_text_test.dart :: splitLuckyText > removeLineBreaks strips only newline characters` | 单元 | 已落地 |
| FID-U12 | 上游对照：hasBackground | FIDELITY | `test/core/foundation/fill_test.dart :: LuckyFill > hasBackground semantics: only null means no background`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > shadow applies only when the cell has a background`<br>`test/compat/css_color_test.dart :: parseCssColor > named colors and transparent` | 单元 | 已落地 |
| FID-U13 | 上游对照：computePadding | FIDELITY | `test/compat/css_misc_test.dart :: compat misc parsers > parseCssPadding uses the upstream top-bottom-left-right order for four values`<br>`test/compat/css_misc_test.dart :: compat misc parsers > parseCssPadding ignores individual padding fields with a warning (U-01)` | 单元 | 已落地 |
| FID-U15 | 上游对照：computeRange | FIDELITY | `test/core/picker/prize_picker_test.dart :: WeightedPrizePicker > matches upstream computeRange on a recorded random sequence`<br>`test/core/picker/prize_picker_test.dart :: WeightedPrizePicker > zero negative and null weights are never picked`<br>`test/core/picker/prize_picker_test.dart :: WeightedPrizePicker > returns null when all weights are absent (upstream -1 cancels)` | 单元 | 已落地 |
| FID-U16 | 上游对照：splitText | FIDELITY | `test/core/text/split_text_test.dart :: splitLuckyText > returns the whole text as one line when it fits`<br>`test/core/text/split_text_test.dart :: splitLuckyText > breaks lines exactly when measured width exceeds max width`<br>`test/core/text/split_text_test.dart :: splitLuckyText > maxWidthOf receives the number of finished lines`<br>`test/core/text/split_text_test.dart :: splitLuckyText > lineClamp appends ellipsis and counts its width on the last line`<br>`test/core/text/split_text_test.dart :: splitLuckyText > lineClamp of zero or negative means unlimited`<br>`test/core/text/split_text_test.dart :: splitLuckyText > negative max width returns the lines collected so far`<br>`test/core/text/split_text_test.dart :: splitLuckyText > empty text yields a single empty line`<br>`test/core/text/split_text_test.dart :: splitLuckyText > a first character wider than max width produces a leading empty line like upstream` | 单元 | 已落地 |
| FID-U17 | 上游对照：getSortedArrayByIndex | FIDELITY | `test/slot/slot_layout_test.dart :: computeSlotLayout > reel order defaults to prize order and keeps holes for invalid indices` | 单元 | 已落地 |
| FID-U18 | 上游对照：cutRound → borderRadius | FIDELITY | `test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > image borderRadius clips the image (#254)` | widget | 已落地 |
| FID-U19 | 上游对照：opacity | FIDELITY | `test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > image opacity is applied without saveLayer` | widget | 已落地 |
| FID-W01 | 上游对照：转盘字段映射 | FIDELITY | `test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > first tick after play has zero interval and does not move` | 单元 | 已落地 |
| FID-W02 | 上游对照：转盘半径与圆心 | FIDELITY | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > radius is half the shorter side and center is (R, R) for topLeft alignment` | 单元 | 已落地 |
| FID-W03 | 上游对照：转盘 initLucky | FIDELITY | `test/core/control/state_machine_test.dart :: state machine > wheel E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > grid E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > slot E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > lots E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E20 reset() from any phase -> idle at origin`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E20 reset() from any phase -> idle at origin` | 单元 | 已落地 |
| FID-W04 | 上游对照：转盘默认值 | FIDELITY | `test/core/foundation/models_test.dart :: core models > LuckyTextDefaults match upstream defaultStyle`<br>`test/core/motion/motion_options_test.dart :: LuckyMotionOptions > defaults match upstream defaultConfig`<br>`test/compat/wheel_compat_test.dart :: wheelFromLuckyCanvasConfig > maps blocks prizes buttons defaultConfig and defaultStyle with upstream defaults` | 单元 | 已落地 |
| FID-W05 | 上游对照：转盘 watch → didUpdateWidget | FIDELITY | `test/wheel/wheel_motion_test.dart :: WheelMotion edges > structural config change during deceleration is deferred until settled` | 单元 | 已落地 |
| FID-W06 | 上游对照：转盘 init 流程 | FIDELITY | `test/core/widgets/game_view_test.dart :: LuckyGameView > lifecycle hooks fire in upstream order` | widget | 已落地 |
| FID-W07 | 上游对照：转盘图片加载 | FIDELITY | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > image arrivals bump the generation and notify listeners` | widget | 已落地 |
| FID-W08 | 上游对照：转盘点击命中 | FIDELITY | `test/wheel/wheel_widget_test.dart :: LuckyWheel > tap inside the button radius calls onStart only in idle-like phases`<br>`test/wheel/wheel_widget_test.dart :: LuckyWheel > tap outside the buttons does nothing` | widget | 已落地 |
| FID-W09 | 上游对照：drawBlock | FIDELITY | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > blocks shrink prize radius by the first padding token`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > block image is centered and offset by top - radius`<br>`test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > block images with rotate true rotate with the wheel and keep z-order`<br>`test/compat/wheel_compat_test.dart :: wheelFromLuckyCanvasConfig > block padding uses only the first token` | widget、单元 | 已落地 |
| FID-W10 | 上游对照：转盘 draw 几何 | FIDELITY | `test/core/text/text_measurer_test.dart :: TextPainterMeasurer > font size is truncated toward zero like fontSize >> 0`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > uniform sector middles start at -90 + prizeDeg / 2 + offsetDegree`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > button radius resolves percent against prize radius and maxBtnRadius is computed upfront`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > prize text wraps with the per-line upstream width formula`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > prize text without wordWrap splits on newlines and drops empty lines`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > button text splits on newlines without wrapping and keeps empty lines`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > text baseline y is top + (lineIndex + 1) * lineHeight`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > line height falls back lineHeight -> default lineHeight -> fontSize -> default fontSize`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > button text left offset resolves against the prize chord like upstream`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > prize image box uses arc length and prize height as max box`<br>`test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > pointer triangle is drawn only when the button has a background`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w01 keyframes match upstream within tolerance`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w02 keyframes match upstream within tolerance`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w03 keyframes match upstream within tolerance`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w04 keyframes match upstream within tolerance`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w05 keyframes match upstream within tolerance`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w06 keyframes match upstream within tolerance` | 1:1 对照、widget、单元 | 已落地 |
| FID-W11 | 上游对照：转盘停止求解 | FIDELITY | `test/core/motion/stop_solver_test.dart :: UpstreamStopSolver > picks the first candidate whose first-frame speed exceeds cruise speed or the closer previous one`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > final angle puts the target sector middle under the pointer plus stopRange`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > stopRange draws exactly one random number per stop in upstream order` | 单元 | 已落地 |
| FID-W12 | 上游对照：转盘 play/stop | FIDELITY | `test/core/control/state_machine_test.dart :: state machine > wheel E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > grid E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > slot E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > lots E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E01 idle play() -> accelerating and returns true`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E01 idle play() -> accelerating and returns true`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > stop during acceleration keeps accelerating until accelerationTime`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > index beyond prize count wraps modulo prize count` | 单元 | 已落地 |
| FID-W13 | 上游对照：转盘 run 逐帧 | FIDELITY | `test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > first tick after play has zero interval and does not move`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > acceleration adds easeIn(startInterval) remainder 360 per tick`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > measures fps as startInterval / frame count after the first tick`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > enters cruising after accelerationTime and adds speed per tick`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > deceleration follows easeOut from stopDeg by endDeg`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w01 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w02 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w03 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w04 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w05 rotateDeg sequence matches upstream`<br>`test/parity/wheel_parity_test.dart :: wheel parity > case w06 rotateDeg sequence matches upstream` | 1:1 对照、单元 | 已落地 |
| IMP-01 | 有意改进 IMP-01（FIDELITY §8.1） | FIDELITY | `test/core/motion/stop_solver_test.dart :: MonotonicStopSolver > equals upstream whenever the upstream displacement is positive`<br>`test/core/motion/stop_solver_test.dart :: MonotonicStopSolver > never returns a displacement against the direction across the parameter grid`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion edges > monotonic solver never rotates backwards on the #419 grid`<br>`test/grid/grid_motion_test.dart :: GridMotion > monotonic solver never decreases currIndex on a short deceleration grid`<br>`test/compat/wheel_compat_test.dart :: wheelFromLuckyCanvasConfig > strictUpstream selects frame timebase and upstream solver` | 单元 | 已落地 |
| IMP-02 | 有意改进 IMP-02（FIDELITY §8.1） | FIDELITY | `test/core/motion/timeline_test.dart :: LuckyTimeline > raw delta above maxFrameDelta is clamped`<br>`test/core/motion/timeline_test.dart :: LuckyTimeline > a single 10 minute jump advances effective time by at most maxFrameDelta` | 单元 | 已落地 |
| IMP-03 | 有意改进 IMP-03（FIDELITY §8.1） | FIDELITY | `test/wheel/wheel_motion_test.dart :: WheelMotion time timebase > covers the same angle at 60Hz and 120Hz within 0.5 degrees`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion time timebase > matches frame timebase within 1e-6 degrees at 1000/60 ms steps`<br>`test/compat/wheel_compat_test.dart :: wheelFromLuckyCanvasConfig > strictUpstream selects frame timebase and upstream solver` | 单元 | 已落地 |
| IMP-04 | 有意改进 IMP-04（FIDELITY §8.1） | FIDELITY | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > failure calls onImageError and does not block other images (#417)`<br>`test/core/image/image_resolver_test.dart :: LuckyImageResolver > onReady fires once after every image settled including failures` | widget | 已落地 |
| IMP-05 | 有意改进 IMP-05（FIDELITY §8.1） | FIDELITY | `test/slot/slot_motion_test.dart :: SlotMotion > first deceleration tick holds stopScroll instead of jumping to 0 (IMP-05)` | 单元 | 已落地 |
| IMP-06 | 有意改进 IMP-06（FIDELITY §8.1） | FIDELITY | `test/core/text/split_text_test.dart :: splitLuckyText > iterates by code point so surrogate pairs are never split (IMP-06)` | 单元 | 已落地 |
| IMP-07 | 有意改进 IMP-07（FIDELITY §8.1） | FIDELITY | `test/core/widgets/game_view_test.dart :: LuckyGameView > resize keeps motion state and only recomputes layout (#146)`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion edges > structural config change during deceleration is deferred until settled`<br>`test/slot/slot_motion_test.dart :: SlotMotion > resize mid-spin rescales scroll by the cellAndSpacing ratio`<br>`test/slot/slot_motion_test.dart :: SlotMotion > reel order change during deceleration is deferred until settled` | widget、单元 | 已落地 |
| IMP-08 | 有意改进 IMP-08（FIDELITY §8.1） | FIDELITY | `test/core/motion/motion_options_test.dart :: LuckyMotionOptions > asserts positive durations and runtime treats non-positive as 1ms`<br>`test/core/motion/stop_solver_test.dart :: MonotonicStopSolver > falls back after maxIterations with non-finite inputs instead of hanging`<br>`test/wheel/wheel_motion_test.dart :: WheelMotion edges > zero prizes refuses to play` | 单元 | 已落地 |
| IMP-09 | 有意改进 IMP-09（FIDELITY §8.1） | FIDELITY | `test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > gradient backgrounds are supported on prizes and blocks (#402)`<br>`test/compat/css_gradient_test.dart :: parseCssFill > upstream pos-color and CSS color-pos stops are both accepted`<br>`test/compat/css_gradient_test.dart :: parseCssFill > commas inside rgb() are not split`<br>`test/compat/css_gradient_test.dart :: parseCssFill > more than two stops without positions spread evenly` | widget、单元 | 已落地 |
| IMP-10 | 有意改进 IMP-10（FIDELITY §8.1） | FIDELITY | `test/core/geometry/fan_path_test.dart :: buildFanPath > non-positive outer radius yields an empty path`<br>`test/core/geometry/round_rect_test.dart :: buildRoundRectPath > non-positive width or height yields an empty path`<br>`test/core/geometry/round_rect_test.dart :: buildRoundRectPath > negative radius is treated as zero`<br>`test/wheel/wheel_layout_test.dart :: computeWheelLayout > padding larger than the radius clamps to zero without throwing (#336)`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > zero rows cols or size does not throw` | 单元 | 已落地 |
| IMP-11 | 有意改进 IMP-11（FIDELITY §8.1） | FIDELITY | `test/grid/grid_layout_test.dart :: computeGridLayout > cell borderRadius zero is honored in the typed API`<br>`test/compat/grid_compat_test.dart :: gridFromLuckyCanvasConfig > cell borderRadius 0 falls back to the default like upstream` | 单元 | 已落地 |
| IMP-12 | 有意改进 IMP-12（FIDELITY §8.1） | FIDELITY | `test/wheel/wheel_widget_test.dart :: LuckyWheel > onButtonTap fires in every phase with the current phase (#370)`<br>`test/grid/grid_controller_test.dart :: GridController > tapping a button calls onStart only in idle-like phases and onButtonTap always` | widget | 已落地 |
| IMP-13 | 有意改进 IMP-13（FIDELITY §8.1） | FIDELITY | `test/core/picker/prize_picker_test.dart :: WeightedPrizePicker > disabled prizes are excluded when honorDisabled is true (IMP-13)`<br>`test/compat/grid_compat_test.dart :: gridFromLuckyCanvasConfig > disabled is ignored unless honorDisabled is set` | 单元 | 已落地 |
| IMP-14 | 有意改进 IMP-14（FIDELITY §8.1） | FIDELITY | `test/compat/wheel_compat_test.dart :: wheelFromLuckyCanvasConfig > speedFunction is ignored unless honorSpeedFunction is set` | 单元 | 已落地 |
| IMP-15 | 有意改进 IMP-15（FIDELITY §8.1） | FIDELITY | `test/slot/slot_controller_test.dart :: SlotController > stop() without index uses the picker for all reels` | 单元 | 已落地 |
| IMP-16 | 有意改进 IMP-16（FIDELITY §8.1） | FIDELITY | `test/core/motion/stop_solver_test.dart :: MonotonicStopSolver > never returns a displacement against the direction across the parameter grid`<br>`test/slot/slot_motion_test.dart :: SlotMotion > monotonic solver never scrolls against the reel direction` | 单元 | 已落地 |
| IMP-17 | 有意改进 IMP-17（FIDELITY §8.1） | FIDELITY | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > sector weights produce proportional sweeps (#151)`<br>`test/grid/grid_layout_test.dart :: computeGridLayout > border and foreground are laid out for normal and active styles (#304 #347)`<br>`test/slot/slot_layout_test.dart :: computeSlotLayout > cellAspectRatio produces non-square cells (#265)` | 单元 | 已落地 |
| IMP-18 | 有意改进 IMP-18（FIDELITY §8.1） | FIDELITY | `test/wheel/wheel_controller_test.dart :: WheelController > settled result index equals the sector under the pointer (#448)` | 单元 | 已落地 |
| IMP-19 | 有意改进 IMP-19（FIDELITY §8.1） | FIDELITY | `test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > painting never calls saveLayer and keeps save count balanced (#176)` | widget | 已落地 |
| IMP-20 | 有意改进 IMP-20（FIDELITY §8.1） | FIDELITY | `test/core/foundation/fill_test.dart :: LuckyFill > negative angle is normalized into 0..360 (IMP-20)` | 单元 | 已落地 |
| IMP-21 | 有意改进 IMP-21（FIDELITY §8.1） | FIDELITY | `test/slot/slot_controller_test.dart :: SlotController > any negative index cancels like upstream -1` | 单元 | 已落地 |
| DEV-01 | 有意偏离 DEV-01（FIDELITY §8.2） | FIDELITY | `test/core/text/text_measurer_test.dart :: TextPainterMeasurer > font size is truncated toward zero like fontSize >> 0`<br>`test/core/text/text_measurer_test.dart :: TextPainterMeasurer > measures with family weight and no text scaling by default`<br>`test/core/text/text_measurer_test.dart :: TextPainterMeasurer > trailing spaces are included in measured width like canvas measureText`<br>`test/core/text/text_measurer_test.dart :: TextPainterMeasurer > baseline offset converts a canvas baseline y into a paint offset`<br>`test/compat/css_misc_test.dart :: compat misc parsers > fontStyle splits into family and fallback with sans-serif as null` | 单元 | 已落地 |
| DEV-02 | 有意偏离 DEV-02（FIDELITY §8.2） | FIDELITY | `test/wheel/wheel_painter_test.dart :: WheelCanvasRenderer > static segments are recorded once while spinning` | widget | 已落地 |
| DEV-03 | 有意偏离 DEV-03（FIDELITY §8.2） | FIDELITY | `test/core/foundation/shadow_test.dart :: LuckyShadow > logical blur converts to sigma blur / 2`<br>`test/core/foundation/shadow_test.dart :: LuckyShadow > device blur converts to sigma blur / (2 * dpr)`<br>`test/compat/css_shadow_test.dart :: parseCssShadow > x y blur color with px stripped and device blur space` | 单元 | 已落地 |
| DEV-04 | 有意偏离 DEV-04（FIDELITY §8.2） | FIDELITY | `test/core/foundation/shadow_test.dart :: LuckyShadow > shadow alpha is multiplied by solid fill alpha only` | 单元 | 已落地 |
| DEV-05 | 有意偏离 DEV-05（FIDELITY §8.2） | FIDELITY | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > formatter output replaces the image and is disposed on eviction` | widget | 已落地 |
| DEV-06 | 有意偏离 DEV-06（FIDELITY §8.2） | FIDELITY | `test/core/control/state_machine_test.dart :: state machine > wheel E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > grid E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > slot E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > capsule E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > lots E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > lotto E11 decelerating past decelerationTime -> settled with result`<br>`test/core/control/state_machine_test.dart :: state machine > numberWheel E11 decelerating past decelerationTime -> settled with result` | 单元 | 已落地 |
| DEV-07 | 有意偏离 DEV-07（FIDELITY §8.2） | FIDELITY | `test/wheel/wheel_motion_test.dart :: WheelMotion edges > upstream solver with zero displacement still settles (DEV-07)` | 单元 | 已落地 |
| DEV-08 | 有意偏离 DEV-08（FIDELITY §8.2） | FIDELITY | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > button radius resolves percent against prize radius and maxBtnRadius is computed upfront` | 单元 | 已落地 |
| DEV-09 | 有意偏离 DEV-09（FIDELITY §8.2） | FIDELITY | `test/slot/slot_layout_test.dart :: computeSlotLayout > fifty prizes need no texture taller than maxRasterSide (#297)` | 单元 | 已落地 |
| DEV-10 | 有意偏离 DEV-10（FIDELITY §8.2） | FIDELITY | `test/slot/slot_painter_test.dart :: SlotCanvasRenderer > draws only visible cells per reel clipped to the reel rect` | widget | 已落地 |
| DEV-11 | 有意偏离 DEV-11（FIDELITY §8.2） | FIDELITY | `test/wheel/wheel_layout_test.dart :: computeWheelLayout > alignment center moves the wheel into the box middle` | 单元 | 已落地 |
| DEV-12 | 有意偏离 DEV-12（FIDELITY §8.2） | FIDELITY | `test/wheel/wheel_motion_test.dart :: WheelMotion frame timebase > measures fps as startInterval / frame count after the first tick` | 单元 | 已落地 |
| DEV-13 | 有意偏离 DEV-13（FIDELITY §8.2） | FIDELITY | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > decodes at draw size times device pixel ratio when a size is specified`<br>`test/core/image/image_resolver_test.dart :: LuckyImageResolver > natural size uses image width divided by ImageInfo.scale` | widget | 已落地 |
| DEV-14 | 有意偏离 DEV-14（FIDELITY §8.2） | FIDELITY | `test/core/image/image_resolver_test.dart :: LuckyImageResolver > image arrivals bump the generation and notify listeners`<br>`test/grid/grid_widget_test.dart :: LuckyGrid > images load progressively and failures use the fallback` | widget | 已落地 |
| DEV-15 | 有意偏离 DEV-15（FIDELITY §8.2） | FIDELITY | `test/slot/slot_controller_test.dart :: SlotController > stopEach requires one index per reel` | 单元 | 已落地 |
| DEV-16 | 有意偏离 DEV-16（FIDELITY §8.2） | FIDELITY | `test/compat/css_length_test.dart :: parseCssLength > malformed values return null with a warning (DEV-16)` | 单元 | 已落地 |
| R7-01 | 拉霸机：拉杆过阈值触发 play 与 onPull，未过阈值回弹；点按可替代拖动 | 用户追加 | `test/slot/lever_test.dart :: LuckyLeverSlotMachine > pulling past the threshold plays and calls onPull`<br>`test/slot/lever_test.dart :: LuckyLeverSlotMachine > releasing below the threshold springs back without playing`<br>`test/slot/lever_test.dart :: LuckyLeverSlotMachine > tapping the lever knob is an accessible alternative to dragging`<br>`test/slot/lever_test.dart :: LuckyLeverSlotMachine > pulling while moving calls onPull but does not play again`<br>`test/slot/lever_test.dart :: LuckyLeverSlotMachine > lever spring-back animation stops its ticker when done`<br>`example/integration_test/lever_flow_test.dart :: lever flow > drag the lever then reels stop one by one on the targets` | widget、集成 | 部分已落地；其余待落地验证 |
| R7-02 | 错峰停轮 stopDelay；默认 0 时与上游逐位一致 | 用户追加 | `test/slot/slot_stagger_test.dart :: SlotMotion stagger > zero stopDelay keeps all reels identical to upstream`<br>`test/slot/slot_stagger_test.dart :: SlotMotion stagger > stopDelay starts each reel deceleration later and settles after the last reel`<br>`test/slot/slot_stagger_test.dart :: SlotMotion stagger > staggered reels still land on their targets`<br>`example/integration_test/lever_flow_test.dart :: lever flow > drag the lever then reels stop one by one on the targets` | 单元、集成 | 部分已落地；其余待落地验证 |
| R7-03 | 多赔付线：可见符号推导、判定、结果与高亮 | 用户追加 | `test/slot/slot_golden_test.dart :: slot goldens > lever slot machine with a winning payline`<br>`test/slot/payline_test.dart :: SlotPayline > visible symbols per row follow each reel order around the target`<br>`test/slot/payline_test.dart :: SlotPayline > default payline predicate wins when all symbols on the line match`<br>`test/slot/payline_test.dart :: SlotPayline > winning paylines are reported in SlotResult and highlighted by SlotPaylineLayer` | golden、单元 | 已落地 |
| R7-04 | 扭蛋机复用通用状态机与 Controller 命令面 | 用户追加 | `test/capsule/capsule_controller_test.dart :: CapsuleController > stop() without index uses the picker`<br>`test/capsule/capsule_controller_test.dart :: CapsuleController > negative index cancels and capsules return to rest`<br>`test/capsule/capsule_controller_test.dart :: CapsuleController > playUntil waits for the async index`<br>`test/capsule/capsule_widget_test.dart :: LuckyCapsuleMachine > a custom renderer receives capsule layout and frame` | widget、单元 | 已落地 |
| R7-05 | 扭蛋机：搅拌→减速（速度连续）→掉落→开蛋，结果为选中奖品 | 用户追加 | `test/capsule/capsule_layout_test.dart :: computeCapsuleLayout > drop path starts at the globe exit and ends in the tray`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > mix intensity follows the swirl speed ratio`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > deceleration starts at cruise speed without a jump`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > drop starts only after the swirl settles and follows the precomputed path`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > the dropped capsule belongs to the target prize and is the closest to the exit`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > reveal scales the card from 0 to 1 then settles`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > revealOnSettle false settles right after the drop`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > next play restores the dropped capsule to the pile`<br>`test/capsule/capsule_motion_test.dart :: CapsuleMotion > a 10 minute frame gap keeps positions finite and still settles`<br>`test/capsule/capsule_widget_test.dart :: LuckyCapsuleMachine > onEnd receives the prize of the dropped capsule`<br>`test/capsule/capsule_golden_test.dart :: capsule goldens > capsule machine mixing`<br>`test/capsule/capsule_golden_test.dart :: capsule goldens > capsule revealed in the tray`<br>`example/integration_test/capsule_flow_test.dart :: capsule flow > knob tap then server result drops and reveals the target capsule` | golden、widget、单元、集成 | 部分已落地；其余待落地验证 |
| R7-06 | 扭蛋机：每帧只回放缓存、位置写入复用缓冲区 | 用户追加/需求2 | `test/capsule/capsule_motion_test.dart :: CapsuleMotion > capsule positions are written into reused Float64List buffers`<br>`test/capsule/capsule_painter_test.dart :: CapsuleCanvasRenderer > capsule pictures are recorded once per color pair`<br>`test/capsule/capsule_painter_test.dart :: CapsuleCanvasRenderer > per frame paint replays cached pictures without recording`<br>`test/capsule/capsule_painter_test.dart :: CapsuleCanvasRenderer > painting never calls saveLayer and keeps save count balanced`<br>`tool/bench/integration_test/capsule_bench_test.dart :: bench > capsule 30 capsules mixing` | widget、单元、基准 | 已落地 |
| R7-07 | 扭蛋机：旋钮与托盘胶囊命中 | 用户追加 | `test/capsule/capsule_widget_test.dart :: LuckyCapsuleMachine > tapping the knob calls onStart only in idle-like phases`<br>`test/capsule/capsule_widget_test.dart :: LuckyCapsuleMachine > tapping the capsule in the tray calls onItemTap after settling` | widget | 已落地 |
| R7-08 | 扭蛋机：布局确定、尺寸为 0 不抛 | 用户追加 | `test/capsule/capsule_layout_test.dart :: computeCapsuleLayout > globe body knob chute and tray fit inside the box`<br>`test/capsule/capsule_layout_test.dart :: computeCapsuleLayout > rest pile is deterministic for the same config`<br>`test/capsule/capsule_layout_test.dart :: computeCapsuleLayout > capsule list defaults to capsulesPerPrize copies of each prize`<br>`test/capsule/capsule_layout_test.dart :: computeCapsuleLayout > capsule radius scales with the globe radius`<br>`test/capsule/capsule_layout_test.dart :: computeCapsuleLayout > zero size yields an empty layout without throwing`<br>`test/capsule/capsule_golden_test.dart :: capsule goldens > capsule machine at rest` | golden、单元 | 已落地 |
| R7-09 | 摇树：每个新玩法的 *_only 探针不含其它玩法；slot_only 不含拉霸机文件 | 用户追加/需求6 | `cmd: dart run tool/treeshake/check_treeshake.dart --probe=wheel_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=slot_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=capsule_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=lots_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=lotto_only`<br>`cmd: dart run tool/treeshake/check_treeshake.dart --probe=number_wheel_only` | 命令 | Web已落地；真实APK待验证 |
| R7-10 | 数字转盘：区间或自定义号码生成外缘刻度格，结果为号码，stopNumber 校验 | 用户追加 | `test/number_wheel/number_wheel_layout_test.dart :: computeNumberWheelLayout > range min max step generates one pocket per number on the rim`<br>`test/number_wheel/number_wheel_motion_test.dart :: NumberWheelMotion > result number is the label of the target pocket`<br>`test/number_wheel/number_wheel_controller_test.dart :: NumberWheelController > stopNumber maps a number to its pocket and rejects unknown numbers`<br>`test/number_wheel/number_wheel_controller_test.dart :: NumberWheelController > stop() without index uses the picker`<br>`test/number_wheel/number_wheel_controller_test.dart :: NumberWheelController > playUntil waits for the server number`<br>`test/number_wheel/number_wheel_widget_test.dart :: LuckyNumberWheel > onEnd receives the number of the target pocket`<br>`test/number_wheel/number_wheel_widget_test.dart :: LuckyNumberWheel > tapping the center calls onStart only in idle-like phases`<br>`test/number_wheel/number_wheel_golden_test.dart :: number wheel goldens > number wheel 0 to 36 at rest`<br>`example/integration_test/number_wheel_flow_test.dart :: number wheel flow > stopNumber on a server number lands the ball in that pocket` | golden、widget、单元、集成 | 部分已落地；其余待落地验证 |
| R7-11 | 数字转盘：圆盘与小球反向旋转；小球相对角单调求解，末段落袋 + 衰减弹跳，最终随盘停在目标格 | 用户追加 | `test/number_wheel/number_wheel_layout_test.dart :: computeNumberWheelLayout > ball track lies outside the pockets and pocket radius inside`<br>`test/number_wheel/number_wheel_motion_test.dart :: NumberWheelMotion > disc and ball spin in opposite directions while cruising`<br>`test/number_wheel/number_wheel_motion_test.dart :: NumberWheelMotion > ball relative angle uses the monotonic stop solver and never reverses`<br>`test/number_wheel/number_wheel_motion_test.dart :: NumberWheelMotion > ball drops from the track to the pocket radius in the last phase of deceleration`<br>`test/number_wheel/number_wheel_motion_test.dart :: NumberWheelMotion > bounce is damped and deterministic`<br>`test/number_wheel/number_wheel_motion_test.dart :: NumberWheelMotion > settled ball sits in the target pocket and moves with the disc`<br>`test/number_wheel/number_wheel_motion_test.dart :: NumberWheelMotion > a 10 minute frame gap keeps angles finite and still settles`<br>`test/number_wheel/number_wheel_widget_test.dart :: LuckyNumberWheel > onPocketPassed fires as the ball passes pockets`<br>`test/number_wheel/number_wheel_golden_test.dart :: number wheel goldens > number wheel ball on the track`<br>`test/number_wheel/number_wheel_golden_test.dart :: number wheel goldens > number wheel ball in the target pocket`<br>`example/integration_test/number_wheel_flow_test.dart :: number wheel flow > stopNumber on a server number lands the ball in that pocket` | golden、widget、单元、集成 | 部分已落地；其余待落地验证 |
| R7-12 | 数字转盘：多格标签抽稀；静态段录制一次；每帧只回放盘面与小球 | 用户追加/需求2 | `test/number_wheel/number_wheel_layout_test.dart :: computeNumberWheelLayout > rim labels are decimated so they never overlap for 200 pockets`<br>`test/number_wheel/number_wheel_layout_test.dart :: computeNumberWheelLayout > zero size yields an empty layout without throwing`<br>`test/number_wheel/number_wheel_painter_test.dart :: NumberWheelCanvasRenderer > a 200 pocket disc records its static segments once`<br>`test/number_wheel/number_wheel_painter_test.dart :: NumberWheelCanvasRenderer > per frame paint replays the disc and ball pictures without recording`<br>`test/number_wheel/number_wheel_painter_test.dart :: NumberWheelCanvasRenderer > painting never calls saveLayer and keeps save count balanced`<br>`tool/bench/integration_test/number_wheel_bench_test.dart :: bench > number wheel 37 pockets ball spin` | widget、单元、基准 | 已落地 |
| R7-13 | 抽签：摇动（加速增幅→匀速→阻尼）→目标签升起→展示签文，结果为选中签 | 用户追加 | `test/lots/lots_layout_test.dart :: computeLotsLayout > rise path lifts the target stick above the cylinder`<br>`test/lots/lots_motion_test.dart :: LotsMotion > shake amplitude grows during acceleration and holds while cruising`<br>`test/lots/lots_motion_test.dart :: LotsMotion > deceleration damps the shake to zero and lifts the target stick`<br>`test/lots/lots_motion_test.dart :: LotsMotion > reveal shows the target stick text then settles`<br>`test/lots/lots_motion_test.dart :: LotsMotion > a 10 minute frame gap keeps the angle finite and still settles`<br>`test/lots/lots_widget_test.dart :: LuckyLots > onEnd receives the drawn stick`<br>`test/lots/lots_golden_test.dart :: lots goldens > lots shaking`<br>`test/lots/lots_golden_test.dart :: lots goldens > lots revealed stick`<br>`example/integration_test/lots_flow_test.dart :: lots flow > tap then server result lifts and reveals the target stick` | golden、widget、单元、集成 | 部分已落地；其余待落地验证 |
| R7-14 | 抽签复用通用状态机与 Controller 命令面 | 用户追加 | `test/lots/lots_controller_test.dart :: LotsController > stop() without index uses the picker`<br>`test/lots/lots_controller_test.dart :: LotsController > negative index cancels and sticks return to rest`<br>`test/lots/lots_controller_test.dart :: LotsController > playUntil waits for the async index` | 单元 | 已落地 |
| R7-15 | 抽签：每帧只回放缓存、帧对象复用 | 用户追加/需求2 | `test/lots/lots_motion_test.dart :: LotsMotion > shake angle is written into the reused frame without allocation`<br>`test/lots/lots_painter_test.dart :: LotsCanvasRenderer > stick pictures are recorded once per style`<br>`test/lots/lots_painter_test.dart :: LotsCanvasRenderer > per frame paint replays cached pictures without recording`<br>`test/lots/lots_painter_test.dart :: LotsCanvasRenderer > painting never calls saveLayer and keeps save count balanced` | widget、单元 | 已落地 |
| R7-16 | 抽签：布局确定、尺寸为 0 不抛 | 用户追加 | `test/lots/lots_layout_test.dart :: computeLotsLayout > cylinder and sticks fit inside the box`<br>`test/lots/lots_layout_test.dart :: computeLotsLayout > stick fan arrangement is deterministic for the same config`<br>`test/lots/lots_layout_test.dart :: computeLotsLayout > zero size yields an empty layout without throwing`<br>`test/lots/lots_golden_test.dart :: lots goldens > lots cylinder at rest` | golden、单元 | 已落地 |
| R7-17 | 抽签：签筒与升起签的命中 | 用户追加 | `test/lots/lots_widget_test.dart :: LuckyLots > tapping the cylinder calls onStart only in idle-like phases`<br>`test/lots/lots_widget_test.dart :: LuckyLots > tapping the raised stick calls onItemTap after settling` | widget | 已落地 |
| R7-18 | 大乐透：号码池配置与 superLotto 预设（前区 35 选 5 + 后区 12 选 2） | 用户追加 | `test/lotto/lotto_config_test.dart :: LottoConfig > superLotto preset is 5 of 35 front and 2 of 12 back`<br>`test/lotto/lotto_config_test.dart :: LottoConfig > pools validate min max and count` | 单元 | 已落地 |
| R7-19 | 大乐透：指定号码校验（数量/范围/不重复）与注入 Random 的无放回抽样 | 用户追加 | `test/lotto/lotto_controller_test.dart :: LottoController > stopWith validates counts ranges and duplicates`<br>`test/lotto/lotto_controller_test.dart :: LottoController > stop() samples without replacement using the injected Random`<br>`test/lotto/lotto_controller_test.dart :: LottoController > playUntil waits for the server draw`<br>`test/lotto/lotto_controller_test.dart :: LottoController > cancel during drawing is ignored like other decelerating phases` | 单元 | 已落地 |
| R7-20 | 大乐透：逐个出球、落入结果槽、可排序展示、结果对象与 onBallDrawn | 用户追加 | `test/lotto/lotto_motion_test.dart :: LottoMotion > balls are drawn one by one at drawInterval in pool order`<br>`test/lotto/lotto_motion_test.dart :: LottoMotion > each drawn ball lands in its result slot`<br>`test/lotto/lotto_motion_test.dart :: LottoMotion > sortResults orders each pool after the last ball lands`<br>`test/lotto/lotto_motion_test.dart :: LottoMotion > settles after the last ball and the drum stops mixing`<br>`test/lotto/lotto_motion_test.dart :: LottoMotion > a 10 minute frame gap keeps positions finite and still settles`<br>`test/lotto/lotto_widget_test.dart :: LuckyLotto > onEnd receives the drawn front and back numbers`<br>`test/lotto/lotto_widget_test.dart :: LuckyLotto > onBallDrawn fires once per drawn ball`<br>`test/lotto/lotto_widget_test.dart :: LuckyLotto > tapping the start button calls onStart only in idle-like phases`<br>`test/lotto/lotto_golden_test.dart :: lotto goldens > super lotto mixing`<br>`test/lotto/lotto_golden_test.dart :: lotto goldens > super lotto with all balls drawn`<br>`example/integration_test/lotto_flow_test.dart :: lotto flow > server draw lands seven balls in order` | golden、widget、单元、集成 | 部分已落地；其余待落地验证 |
| R7-21 | 大乐透：每帧只回放号码球缓存、复用缓冲区 | 用户追加/需求2 | `test/lotto/lotto_motion_test.dart :: LottoMotion > positions are written into reused buffers without allocation`<br>`test/lotto/lotto_painter_test.dart :: LottoCanvasRenderer > ball pictures are recorded once per number`<br>`test/lotto/lotto_painter_test.dart :: LottoCanvasRenderer > per frame paint replays cached pictures without recording`<br>`test/lotto/lotto_painter_test.dart :: LottoCanvasRenderer > painting never calls saveLayer and keeps save count balanced`<br>`tool/bench/integration_test/lotto_bench_test.dart :: bench > lotto 47 balls mixing and drawing` | widget、单元、基准 | 已落地 |
| R7-22 | 大乐透：布局确定、尺寸为 0 不抛 | 用户追加 | `test/lotto/lotto_layout_test.dart :: computeLottoLayout > drums balls and result slots fit inside the box`<br>`test/lotto/lotto_layout_test.dart :: computeLottoLayout > one ball per number in every pool`<br>`test/lotto/lotto_layout_test.dart :: computeLottoLayout > zero size yields an empty layout without throwing`<br>`test/lotto/lotto_golden_test.dart :: lotto goldens > super lotto machine at rest` | golden、单元 | 已落地 |
| R7-23 | core 搅拌运动学 LuckySwirlMixer（扭蛋机与大乐透共用）确定、有界、零分配 | 用户追加/需求1 | `test/core/kinematics/swirl_mixer_test.dart :: LuckySwirlMixer > rest packing is deterministic and keeps bodies inside the container`<br>`test/core/kinematics/swirl_mixer_test.dart :: LuckySwirlMixer > zero mix leaves bodies at rest positions`<br>`test/core/kinematics/swirl_mixer_test.dart :: LuckySwirlMixer > positions stay inside the container for any swirl angle and mix`<br>`test/core/kinematics/swirl_mixer_test.dart :: LuckySwirlMixer > writes positions into caller-provided Float64List buffers` | 单元 | 已落地 |


---

## 6. 1:1 对照测试（上游 lucky-canvas）

### 6.1 目标与范围

现状：npm lucky-canvas@1.7.26 的基线由 MANIFEST 锁定 SHA-256，16 用例 / 96 产物（6720 帧、80 PNG），两轮生成摘要一致。F2 修复 g05 阶段及接缝，DIAG/DIAG2/DIAG3 完成残余图像分类；w04、g05、s01–s05 早期跳过已全部解除，三玩法数值及关键帧通过。最终结果及容差见 §6.5，`test/parity/FINDINGS.md` 的旧 skip/失败段落保留为历史证据。
- 数值：`frame` 时间基准 + `UpstreamStopSolver` + 相同随机序列下，逐帧 `rotateDeg`（转盘）/`currIndex`（九宫格）/`scroll[]`（老虎机）与上游一致，相对误差 ≤ 1e-9（`|a − b| ≤ 1e-9 × max(1, |b|)`）。
- 图像：关键帧（开始前、加速中、匀速中、减速中、settled）在 §4.4 的 1:1 容差内一致。
- 只覆盖上游有的三种玩法；新增玩法（拉霸机、扭蛋机、数字转盘、抽签、大乐透）无上游，不做对照。
- 只覆盖"上游没出问题"的参数区间（生成器断言转盘/九宫格上游序列单调不减）；上游问题区间由 `ISS-419` 等测试单独覆盖。

### 6.2 用例（`tool/parity/cases/<id>.json`）

```json
{
  "id": "w01",
  "game": "wheel",
  "size": {"width": 300, "height": 300},
  "dpr": 2,
  "config": { "blocks": [...], "prizes": [...], "buttons": [...], "defaultConfig": {...}, "defaultStyle": {...} },
  "script": [{"frame": 0, "action": "play"}, {"frame": 180, "action": "stop", "index": 2}],
  "random": [0.4170220047, 0.7203244934, 0.0001143748, 0.3023325726],
  "frames": 420,
  "keyframes": [0, 60, 170, 240, "settled"]
}
```

| id | 玩法 | 场景 | 覆盖的对照项 |
| --- | --- | --- | --- |
| w01 | 转盘 | 6 奖品、默认参数、匀速期 `stop(2)` | FID-W10、FID-W11、FID-W13 |
| w02 | 转盘 | `stopRange: 0.8`、`offsetDegree: 30`、带 range 权重、`stop()` 无参 | FID-U15、FID-W11 |
| w03 | 转盘 | 加速期（第 30 帧）`stop(4)` | FID-W12、SM-E08/E09 |
| w04 | 转盘 | `gutter: '4px'`、3 层 blocks、按钮 pointer、多行换行 + lineClamp、图片（data: PNG） | FID-W09、FID-W10、FID-U16 |
| w05 | 转盘 | `decelerationTime: 1200`、`speed: 10`（仍在单调区间） | FID-W11 |
| w06 | 转盘 | 匀速期 `stop(-1)`（作废，end 收到 `{}`） | SM-E14 |
| g01 | 九宫格 | 默认 3×3、中心按钮、`stop(5)` | FID-G07、FID-G09、FID-G10 |
| g02 | 九宫格 | 合并格（col/row）、2 个按钮、旧字段 `button` | FID-G05、FID-G11 |
| g03 | 九宫格 | 格子阴影、两色无位置渐变、activeStyle 字体覆盖 | FID-G07、FID-G08、FID-U06 |
| g04 | 九宫格 | 4×4、`speed: 30`、`gutter: 8` | FID-G03、FID-G10 |
| g05 | 九宫格 | 加速期 `stop(0)` | FID-G10 |
| s01 | 老虎机 | 纵向 3 列默认 order、`stop(1)` | FID-S07、FID-S08、FID-S11 |
| s02 | 老虎机 | 每列不同 order、列速度、`direction: -1` | FID-S11 |
| s03 | 老虎机 | 横向模式 | FID-S12 |
| s04 | 老虎机 | `stop([0, 1, 2])`（未中奖） | FID-S10 |
| s05 | 老虎机 | `stop(-1)`（取消，无 end 回调） | SM-E25 |

所有用例文字只用 ASCII，字体族指定为 `Roboto`（两端加载同一个 TTF），图片用内嵌 data: PNG（避免网络）。

默认加速 2500ms，第 120 帧为 1920ms，仍在加速；匀速 stop 用第 180 帧（2880ms），w03/g05 仍第 30 帧提前停。实际 JSON 使用 180×180 逻辑尺寸、dpr=1；上例 size 只示意结构，真实参数以 cases 文件为准。

### 6.3 基线生成与伪时钟映射

见 IMPLEMENTATION_GUIDE T4.3。关键映射：

| 上游（harness） | luckdraw（parity_support） |
| --- | --- |
| `play()` 在伪时间 T 同步执行 `run(0)` | `controller.play()` 后立即 `clock.tick(T)`（首 tick 设定 startTime 并以 num=0 处理） |
| 第 k 次 rAF：伪时间 `T + 16k`，执行 `run(k)` | `clock.tick(T + 16k)` |
| 脚本在第 f 帧开始前执行 `stop(i)` | 在第 f 次 tick 之前调用 `controller.stop(i)` |
| `Math.random` 依序返回 `random[]` | `SequenceRandom(random)` 注入 controller |
| `end` 回调在置 0 后的下一帧 | luckdraw 在置 0 当帧回调（DEV-06）：对照时把上游 end 帧号减 1 后比较 |
| 老虎机减速首帧 `scroll = 0`（U-06） | 断言等于 `stopScroll`（IMP-05），不与上游比较 |

### 6.4 版本化

- 第 0 帧只执行同步 run(0)，不得再消费一次 rAF。数值帧 0 为 play 后，PNG 关键帧 0 为 play 前；f>0 时先动作再消费一个 rAF，新增回调留到下帧。正常结束回调的 DEV-06 归一化不应机械套用取消路径：w06 在 stop 当帧回调，s05 无 end。
- 基线存 `test/parity/baselines/<id>/{frames.json, kf_<n>.png}` 并提交；`.pubignore` 排除，不随包发布。
- `MANIFEST.json`：`upstream`（`lucky-canvas@1.7.26`）、`tarballSha256`、`referenceCommit`（`7a8c0bbcb992a297b390e3a2ebaa1a3385c1f2f9`）、`chrome`（版本号）、`fontSha256`、`generatedAt`、`cases`（id → 用例 JSON 的 sha256）。
- 需要重新生成的情形：用例 JSON 变化（CI 的 `--verify-manifest` 会拦下）、升级上游参照版本、更换 Chrome 大版本后关键帧对比失败。数值 `frames.json` 不应随 Chrome 版本变化；若变化，说明上游行为依赖浏览器，需在 FIDELITY 记录。
- 上游 npm 产物与参照 commit 的一致性：首次生成时人工把 `dist/index.umd.js` 中 `carveOnGunwaleOfAMovingBoat`、`splitText`、`computeRange` 的实现与参照 commit 的 TS 源码比对，结论写进 `tool/parity/README.md`（ARCHITECTURE §19 风险项）。

B12a 已抽查 wheel/grid 停止求解、splitText、computeRange 一致；slot npm 在 initSlot 中补默认 order，而参照 TS 在求解时回退。当前五个非空有效 order 用例等价，s01 覆盖 npm 默认补齐；不能推断整个 npm 文件与 TS 完全一致。生成器使用 curl 下载，Windows Chrome 版本读 exe ProductVersion，保持原 npm 产物不改。

### 6.5 容差与已知差异

依据为 `test/parity/FINDINGS.md` 的 DIAG/DIAG2/DIAG3 和 `tool/parity/README.md`。s03/s05 残余定位为文字光栅化加 reel 列边界1像素抗锯齿采样，几何位置无误；s03/240 去文字后差异为0，s05取消截图去文字后仅0.006173%。白名单按标签逐一登记，s05/settled 与 s05/240 虽图像相同仍分别比较；取消标签不表示正常中奖。s01/s02/s04及其它帧保持标准层，保护测试禁止悄悄扩大名单。DIAG2 的拉霸机 raster/Picture 临时文字探针为0.558824%/0.233407，略超普通golden 0.5%门槛，仅保留诊断证据，不宣称两个缓存模式整图逐像素一致。

| 维度 | 容差 | 理由 |
| --- | --- | --- |
| 逐帧数值 | 门限相对 1e-9；最终经既定映射全部精确相等 | 转盘 6 例 2520 帧；九宫格 5 例 2100 帧；老虎机 5 例 2100 帧（U-06 首减速帧按 IMP-05 映射） |
| 图像 standard | 差异像素 ≤1.8%、RGBA 均误 ≤1.8 | 通道差阈值 32；除下列逐帧白名单外全部适用 |
| 图像 text-heavy | 仅 w04/60：2.274691358% / 1.505047840 | 实测 ×1.1；670 个差异像素 100% 位于文字区，去文字后零差异 |
| 图像 edge-aa | 仅 s03/60、s03/240、s05/settled、s05/240：各帧实测 ×1.1 | 分别约 2.631%/1.525、2.489%/2.123、2.166%/1.662、2.166%/1.662；均 ≤4%/2.5，精确值以 parityImageTolerance 为准 |
| 结果回调帧 | 上游帧号 − 1 | DEV-06 |
| 老虎机列间溢出 | 用例避免文字溢出格子 | DEV-10 |

---

## 7. 性能基准（真机 profile）

### 7.1 场景

DEV完整采集11报告场景，各三轮：wheel_steady、wheel_first_frame、grid_steady、slot_steady、slot_raster、lever_steady、capsule_mixing、number_wheel_spin、lots_shaking、lotto_draw、memory_cycles。旋转/滚动窗口5秒，大乐透包含完整开奖；GC参照为同轮reference_spin。全部运动玩法附带五次push/pop RSS，memory_cycles单独测转盘；每次页面及返回空白页稳定2秒。真实测试名为 `bench > rss after 5 push pop cycles`。

### 7.2 指标与采集

UI/Raster均值、P90与P99来自保存的FrameTiming；合计P99来自同帧build+raster，绝不相加两个线程的独立P99。`dropped_frame_ratio`仍是线程耗时预算代理，不是未呈现帧计数。GC沿用同轮参照、预算0；layout/record细分和解码字节仍待接线，不伪造数据。

比例类（`dropped_frame_ratio`及同类0–1比例）稳定性采用绝对极差≤0.01（1个百分点），避免近零中位数放大相对误差；时间类中位数<0.5ms时绝对极差≤0.15ms，其余时间/字节相对极差≤30%。RSS仍只按FIN绝对上限，不做相对稳定性门禁。成本至少2个未污染窗口，偶数取中间两项平均；不足或不稳定均为「不确定，需补跑」。所有稳态窗口必须fps≥59且帧数≥期望98%，否则失败；污染判定仍追加Raster P90≥15.5ms，阈值与窗口规则不变。

显式首版标定仅用于稳定时间指标：`max(实测中位数×1.1向上取整到0.001ms, 有来源且不高于FIN/MET既有批准值的历史标定下限)`；未标定的设计估算不能充当下限，比例/GC/RSS不重标。正常`compare.dart`只比较冻结后的`budgets.json`，不得每次回归自动放宽；`--calibrate`仅输出建议。最初`design_target`来自DEV保存的设计快照，MET前目标（含FIN批准值）另存`target`，`gap_to_design=实测中位数/design_target−1`，零目标差距无定义。历史标定下限及来源在`budgets.status.json.met2`冻结，重复重算不叠加。原设计目标达成与回归门禁通过分开列示。

新增硬门禁独立检查**每一个未污染窗口**：同帧build+raster合计P99≤12.0ms（16.67ms至少预留4.5ms），且UI P99≤4ms。任一超标直接失败，优先于不确定，不能用跨窗口中位数掩盖。保存数据中grid=12.231ms、slot_raster=16.905ms、lotto=12.229ms超合计上限，lotto UI P99还达4.386ms；不调整阈值。lots的Raster均值/P90相对极差41.69%/53.75%，仍不稳定，需下次同配置调查补跑，不能挑好窗口。

冷首帧40.378ms仅信息（历史估算4ms不门禁）。PEND已实现blank/wheel/grid/slot统一外壳的冷push入口，尚未执行；下次各三轮采样后按玩法与空白中位数之差建立增量基线。旧40.378ms的外壳不同，不直接减新空白；详见§7.6与[bench README](../tool/bench/README.md)。

RSS保留`kRssCycles=5`；`max(0,rss_blank[0]−rss_baseline)`仅预热信息，`max(0,rss_blank[4]−rss_blank[0])`稳态增长≤1572864B，页面峰值≤5622989B，原数组及负差完整保留，全部三轮取中位数；不受污染分类过滤。

### 7.3 运行规程

1. 下次仅真机profile采样；固定正常手动亮度、USB常亮且避免DIM，保存设备/后端/配置/APK身份，窗口内暂停看护轮询。Windows仅功能测试。
2. 同配置先三轮；未污染不足两轮可补到总启动≤5，仍不足或仍不稳定均不确定。补跑不得挑选好轮替换坏轮；PEND新脚本已实现有界补样，采集分支待真机验证，不将历史设备脚本冒充为已支持自动补样。
3. 本轮纯离线，未连接手机、adb、Gradle或build。比较：`dart run tool/bench/compare.dart --input=tool/bench/results/met2/comparison --rss-all-scenes`，真实退出1。
4. 首版标定重放：`python tool/bench/recalculate_met2.py`；正常compare固定预算，真实卡顿、硬余量失败、成本超预算或不确定均退出1。INFO不作通过。

### 7.4 预算与实测（MET2，2026-11-10）

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

当前回归预算如下，比例各场景0.005（lever=0）、GC=0；不稳定指标保留原预算，首帧仅信息，RSS按上文。

| 场景 | UI均值/P90 ms | Raster均值/P90 ms |
| --- | --- | --- |
| wheel_steady | 1.031/1.660 | 5.610/7.423 |
| grid_steady | 1.200/1.958 | 4.000/7.000 |
| slot_steady | 1.494/2.093 | 3.793/4.354 |
| slot_raster | 1.000/2.000 | 5.000/8.000 |
| lever_steady | 1.540/2.306 | 4.086/4.639 |
| capsule_mixing | 2.000/3.000 | 4.190/7.503 |
| number_wheel_spin | 1.300/1.959 | 3.274/3.682 |
| lots_shaking | 1.517/2.227 | 5.000/8.000 |
| lotto_draw | 2.500/3.655 | 5.307/7.083 |

未达最初设计目标完整清单：

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

硬门禁结果：

| 场景 | 未污染合计P99最大 ms / 12 | UI P99最大 ms / 4 | 帧预算余量门禁 |
| --- | --- | --- | --- |
| wheel_steady | 10.081 | 1.850 | 通过 |
| grid_steady | 12.231 | 2.434 | 失败 |
| slot_steady | 6.578 | 2.527 | 通过 |
| slot_raster | 16.905 | 2.190 | 失败 |
| lever_steady | 7.340 | 2.963 | 通过 |
| capsule_mixing | 8.508 | 3.241 | 通过 |
| number_wheel_spin | 5.528 | 2.180 | 通过 |
| lots_shaking | 8.864 | 2.780 | 通过 |
| lotto_draw | 12.229 | 4.386 | 失败 |

完整每场景每指标中位数、design_target、预算、gap_to_design与状态见[MET2报告](../tool/bench/results/met2/REPORT.md)与[第二轮度量说明](METRIC_FIX_REPORT.md#第二轮预算标定与稳定性规则)。新增10条离线回归MET2-01～10已追加矩阵（D6「已落地」），保留历史测试名。

### 7.5 CPU占用指示（不是进程CPU实测）

UI线程忙占比≈`avg_build_ms×fps/1000`，取全部主窗口的推算中位数；Raster线程忙占比≈`avg_raster_ms×fps/1000`，仅取未污染窗口的推算中位数。**由帧耗时推算，未做进程级CPU实测（`dumpsys cpuinfo`/`top`），进程级CPU实测待下次真机会话。** 两线程比例不能相加当进程CPU，Raster墙钟耗时也不等于执行CPU指令的时间。

| 场景 | UI忙占比（全部窗口中位数） | Raster忙占比（未污染窗口中位数） |
| --- | --- | --- |
| wheel_steady | 5.74% | 30.62% |
| wheel_first_frame | 不适用（非稳态） | 不适用（非稳态） |
| grid_steady | 6.14% | 32.99% |
| slot_steady | 8.13% | 20.71% |
| slot_raster | 6.40% | 16.61% |
| lever_steady | 8.40% | 22.28% |
| capsule_mixing | 9.92% | 22.85% |
| number_wheel_spin | 6.80% | 17.86% |
| lots_shaking | 7.95% | 23.39% |
| lotto_draw | 13.02% | 28.97% |
| memory_cycles | 不适用（非稳态） | 不适用（非稳态） |

---
### 7.6 PEND 离线根因与待真机会话

PEND 仅读取原始 trace：四场景全部16个未污染窗口，按引擎帧号关联 UI/Raster 并核对 SDK 时长数组；旧 DEV 与 MET2 正式 PERF 分列。正式样本尖峰并集为 slot 5、grid 8、lotto 24、lots 0；这些是 trace 单帧超过12/4ms的计数，与 FrameTiming P99 硬门禁分开。Raster 尖峰主要在 GLES Encode/Submit；部分 UI 尖峰在 PAINT/COMPOSITING，缺少库函数采样栈，无法判定可避免的 luckdraw 工作。没有证据支持的产品优化不做；库、parity 与 golden 基线均不变。逐帧证据见 [PERF_ROOTCAUSE_REPORT](PERF_ROOTCAUSE_REPORT.md)。

下一次真机用包含 `pending_bench_test.dart` 的已构建 profile APK，一条命令运行：

```powershell
./tool/bench/run_pending_device_checks.ps1 -DeviceSerial <serial> -ApplicationBinary <新入口profile.apk>
```

顺序为 blank_first_frame×3、wheel/grid/slot 冷首帧各3轮、wheel/grid/slot/capsule/lotto CPU各3轮、slot_raster/grid_steady/lotto_draw/lots_shaking 各3轮。首帧均用同一 Scaffold 冷push及完整 FrameTiming UI，报告三轮中位数与「玩法−空白」的有符号差；不把它解释为纯 layout/record 或启动首帧，也不自动制定合格预算。旧wheel冷push仍保留原有注册名及测法；新组的空白与三个玩法均使用相同 MaterialApp/Scaffold 外壳，不能直接与旧40.378ms相减。

CPU 会话通过窗口外建立的 localhost adb reverse + TCP before/start/end 握手：窗口前/后各采一次，窗口内第0/1/2/3/4秒各采一次 `dumpsys cpuinfo` 与 `top -b -n 1 -H -p <pid>`；五次都须在对应一秒内完成，否则失败。保留七组原文、PID、UI/Raster及其它线程、时间与跨度；cpuinfo/top 原生统计时间区间以原文为准，不将两线程墙钟忙占比求和当进程CPU。CPU 的 lotto 是五秒稳态搅拌，完整开奖另有帧时复测。

脚本先核实在线实体设备、亮屏未锁屏（最长等待15分钟）及主机空闲物理内存≥4GiB；每轮force-stop、始终复用相同APK、每项最多5次启动，不改手机设置。测量期间没有本脚本的其它adb轮询；只能核实轮前/轮后锁屏状态，无法独立证明窗口中间完全没有DIM或其它系统干扰。结果写 `tool/bench/results/pending/`，四项帧时由 `compare.dart --scenarios=slot_raster,grid_steady,lotto_draw,lots_shaking --rss-all-scenes`按冻结MET2规则评估；缺样/解析失败显式失败，不足两个未污染样本可补到五次，仍不足或不稳定为不确定。CPU/首帧仅标定，无批准阈值时不宣称达标。

PEND-01～16 追加到 [验收矩阵](../test/ACCEPTANCE.md)，包含解析边界、时序、冷页面结构、离线trace关联、脚本PlanOnly及合成采集的CLI评估。PlanOnly只验证编排，不是设备执行；真实协议、帧时改善及APK仍待下一次真机会话，本批不运行设备脚本的采集分支。

### 7.7 DEVFIN 本次真机事实与有效增量预算

DEVFIN（2026-11-11）本次仅单台 vivo V2417 / Android 16：grid_steady：失败；slot_raster：失败；lots_shaking：不确定；lotto_draw：失败。冷push首帧增量wheel/grid/slot为38.087/10.520/0.245ms，新标定增量预算41.896/11.572/0.270ms；wheel/grid未达原4ms估算目标。CPU五项目各五次均0有效，不能提供可信百分比；wheel/grid冷帧主机汇总仅2/5、1/5成功，数值来自原始driver响应，失败标记保留。真机采集链路未通过，不把已标定写成达到设计目标。

本次按原脚本每轮核对亮屏未锁屏、不修改设置；原脚本提前退出后只续跑未启动项目，不清零计数。完整原始文件、主机失败、CPU统计区间、每窗口交付和新旧结果见[DEVFIN报告](../tool/bench/results/pending/REPORT.md)。有效首帧度量由绝对信息项转为同Scaffold外壳的玩法中位数−空白中位数；按前三份完整设备FrameTiming固定顺序计算，不挑耗时；其×1.1向上取整到0.001ms为冻结增量预算。现有MET2 schema不能表达grid/slot及空白差值，预算暂存budgets.status.json.devfin并由DEVFIN测试核验；budgets.json旧绝对信息字段保留兼容。CPU缺测没有预算通过结论。硬门禁仍为每未污染窗口合计P99≤12ms、UI P99≤4ms，至少两个未污染窗口；正常compare不自动放宽预算。以上§7.4–7.6保留历史身份，不冒充本次全部采样通过。


### 7.8 INSTR：函数级时间线与 /proc 差分

INSTR（2026-11-11，副本候选实现）：wheel/grid带打点冷首帧中位数38.412→27.075ms、24.214→12.993ms，精确文字宽度缓存将首帧TextPainter.layout次数276→63、128→22；随机/多语言/emoji/lineClamp等价。减DEVFIN历史空白2.883ms后的增量24.192/10.110ms，新预算26.612/11.121ms，仍未达到原4ms目标，三轮波动大。CPU采用/proc累计节拍差，UI与平台合并标为UI+platform；wheel完整链路仅2/5，不能给三轮中位数；其余场景逐轮数值和有效性见本轮报告，lotto仅搅拌阶段。库改动以补丁交付，未覆盖并行共享lib，待主会话合并。

[报告](../tool/bench/results/pending2/REPORT.md)。每个同步事件成对、所有TextPainter.layout调用记录arguments.layouts=1；首帧各阶段按区间并集/差集统计，逐事件绝对起止保留attribution.json。CPU窗口只读两次adb，pidof和权限探测在窗口前；主机单调时刻差作分母；解析LF/CRLF、空格/括号comm、PID复用与计数倒退显式失败。driver先落盘原始响应，冷Raster缺失不伪造Raster指标；CPU未测GC参照单列。新增INSTR矩阵代码19条、设备7条，正式轮不足状态按实际；不降低覆盖、导入、矩阵、parity或发布预演门禁。

### 7.9 STEADY：带打点稳态尖峰归因与补齐CPU

STEADY（2026-11-11）仅单台 vivo V2417 / Android16：四场景带luckdraw打点，slot/grid/lots各3/3，lotto4/5（2个污染、1个安装后VM连接超时，未污染2）。轮前后核对未锁，窗口内无额外adb轮询。按引擎帧号配对并校验SDK数组，trace尖峰与FrameTiming P99独立，12ms/4ms和MET2规则均未放宽。

slot/grid尖峰主要在框架编码/提交；lotto结算重复准备已定位，但复用painter候选三轮没有稳定净收益，已回滚。lots本轮三轮稳定且通过，不能解释历史不稳定。wheel /proc CPU已补齐3/3；仅标定，不外推跨设备。

原APK启用LUCKDRAW_TIMELINE=true与LUCKDRAW_STEADY_ENTRY=true，slot mount在独立entry_reference窗口捕获，不混进稳态或GC参照。按frame_number配对、核对SDK数组；每个尖峰保存luckdraw完整起止与框架包含耗时，区间并集避免重复计时。没有分配栈或GPU上传关联的内容明确无法判定。污染轮、启动超时、失败命令原样保留；最多5次启动，不选好轮替换旧记录。

最终四场景为grid/slot/lotto失败，lots本轮通过；CPU进程/UI+platform/Raster中位数39.291465%/14.930757%/18.299352%，无批准CPU阈值，仅标定。候选lotto准备复用三轮未获稳定净收益，已回滚，不更新冻结预算。所有结论仅针对本设备及本批数据。STEADY-01～09/12追加矩阵，10/11是已回滚实验测试，不纳入最终注册。

[完整报告](../tool/bench/results/steady/REPORT.md)、[逐帧证据](../tool/bench/results/steady/ATTRIBUTION.md)；工具入口run_steady_device_checks.ps1，离线analyze_steady.py。旧§7.5～7.8保留历史身份，CPU当前方法为/proc首尾两次累计差，不再把历史cpuinfo/top采样当当前方案。


## 8. 摇树验证（需求 6）

### 8.1 探针

`tool/treeshake/probes/<name>/main.dart`（每个都调用 `runApp` 并真正使用所列 API，避免被整体优化掉）：

| 探针 | import | 使用 |
| --- | --- | --- |
| baseline | 无 luckdraw | 一个 `Text` |
| wheel_only | `wheel.dart` | `LuckyWheel` + `WheelController.stop`，缓动只用默认 quad |
| grid_only | `grid.dart` | `LuckyGrid` |
| slot_only | `slot.dart` | `LuckySlotMachine`（不用拉霸机） |
| capsule_only | `capsule.dart` | `LuckyCapsuleMachine` |
| number_wheel_only | `number_wheel.dart` | `LuckyNumberWheel` |
| lots_only | `lots.dart` | `LuckyLots` |
| lotto_only | `lotto.dart` | `LuckyLotto(config: LottoConfig.superLotto())` |
| compat_wheel | `compat.dart` + `wheel.dart` | `wheelFromLuckyCanvasConfig(jsonDecode(...))` |
| all_games | 全部玩法入口 | 每个玩法一个 Widget |

### 8.2 断言规则（web 后端：sourcemap `sources` 路径 + `names` 符号）

禁符号规则已统一为「受检查符号全集 − 当前探针允许集」；下表“同上”均须减去该探针实际允许的缓动（`lotto_only` 允许 `CubicEasing`）。compat 可达的字符串缓动表不影响无关玩法隔离检查。

| 探针 | 必须出现 | 禁止出现的源文件路径片段 | 禁止出现的符号 |
| --- | --- | --- | --- |
| wheel_only | `/lib/src/core/`、`/lib/src/wheel/` | `/lib/src/grid/`、`/lib/src/slot/`、`/lib/src/capsule/`、`/lib/src/number_wheel/`、`/lib/src/lots/`、`/lib/src/lotto/`、`/lib/src/compat/`、`/lib/src/testing/`、`/lib/src/core/kinematics/` | `CubicEasing`、`QuartEasing`、`QuintEasing`、`SineEasing`、`ExpoEasing`、`CircEasing`、`LuckyGameRegistry`、`kLuckyCanvasEasingNames` |
| grid_only / capsule_only / number_wheel_only / lots_only / lotto_only | `core` + 自己的区 | 其它全部玩法区、compat、testing；（kinematics 只允许出现在 capsule_only、lotto_only） | 同上（缓动、注册表、名称表） |
| slot_only | `core`、`slot` | 其它玩法区、compat、testing、`/lib/src/slot/lever/` | 同上 + `LuckyLeverSlotMachine` |
| compat_wheel | `core`、`wheel`、`compat` | `/lib/src/grid/`、`/lib/src/slot/`、新玩法区、`/lib/src/compat/grid_compat.dart`、`/lib/src/compat/slot_compat.dart` | — |
| all_games | 全部玩法区 | `/lib/src/compat/`、`/lib/src/testing/` | `kLuckyCanvasEasingNames` |

注意（实测结论，ARCHITECTURE §17.2）：极小的类可能被 dart2js 整体内联，"必须出现"只检查**区目录**，符号只做"禁止出现"检查。apk 后端按同一张表检查 `--analyze-size` JSON 中 `package:luckdraw/src/...` 库路径。

B13c 已修正 B16 的通用 cubic 禁令冲突：lotto_only 允许 CubicEasing，wheel_only 继续拒绝。B13b/B13c 累计十个探针全部成功 Web 构建，源码/符号检查全部通过、无泄漏（含纯 slot 不保留 lever）；这是跨批证据集合，不是同一源码快照重跑十项。证据为 `tool/treeshake/first_measurement.json`、`recheck_measurement.json`，早期 compat 缺失失败已由 B13c 补测闭环。

B13a解析器夹具已验；APK/APK2随后完成真实APK自动构建与十探针检查，全部零泄漏。也可传 `--size-json=<已有报告>`复核；完整证据见 [摇树报告](../tool/treeshake/README.md)。Web与APK各十探针均为真实构建证据，仍区分跨批累计与单次重跑。

### 8.3 体积预算

`tool/treeshake/budgets.json` 的十项 Web 预算均已按实测增量 ×1.1 向上取整回填；APK十项也已按实测×1.1向上取整回填，全部零泄漏。CLI 的 `maxDeltaGzipBytes` 使用 Dart `GZipCodec(level: 9)`；GNU `gzip -9 -n` 的 `maxGnuDeltaGzipBytes` 为独立记录，不能混用压缩器上限。

F2 合理增加大乐透代码后，主会话按 B13c 复测重定 lotto_only：Dart 增量 4417 B → 上限 4859 B，GNU 3889 B → 4278 B；旧 README 的 4294/3739 B 超预算结论保留为历史，不代表当前预算。compat_wheel 的 Dart/GNU 上限为 29653/29101 B。其余值见预算文件；旧设计“任一 *_only < all_games 的60%”是规划关系，当前工具按各探针实测增量预算验收，不能将该关系冒充已执行门禁。

APK后端支持自动构建及已有报告；CI treeshake-apk已重新启用，目前选择五项探针，十项本地成功不能冒充远程作业成功。

---

## 9. 集成测试规矩（真机 / Windows 桌面）

B15 example与11个集成文件在Windows真实运行三轮共**33/33、100%**，累计913606ms，证据为`example/validation/windows_integration_report.json`及README；`LUCKDRAW_TEST_WINDOW=1`，resize真实调整HWND并断言foreground=false。长路径触发MSBuild `.tlog`的MSB6003/DirectoryNotFoundException，需要同工程短路径入口。安卓vivo V2417 / Android16另完成**33/33通过**、累计1595498ms，见[DEVICE_REPORT.md](DEVICE_REPORT.md)。Skia/Impeller阴影半径差1–2物理像素、扫描线峰值差20.8–23.8/255，已决定记为已知后端差异，不按后端调sigma；老虎机视口裁剪缺样本，未量化，依据见ARCHITECTURE §8.6。示例45张自渲染图约1.26MB，没有上游演示真实截图，未做上游逐像素对齐。

1. 在 `example/integration_test/` 编写；用 `dart run tool/run_integration.dart --device=<windows|serial> --repeat=3` 运行：**每个文件跑 3 次**，任一失败即失败。
2. Windows：设置 `LUCKDRAW_TEST_WINDOW=1`，example 的 Windows runner 以 480×720 小窗口、`SW_SHOWNOACTIVATE` 启动，不调用 `SetForegroundWindow`，**后台运行不抢焦点**；用户本机是双显示器桌面，不要求窗口位置。
3. 安卓先用 `adb devices` 确认真机。生命周期状态按 `resumed → inactive → hidden → inactive → resumed`，hidden 期间真实等待 10s 且不 pump，恢复后再 pump；直接 resumed→hidden 会触发 Flutter 迁移断言。不要在 paused 时调用 tester.pump（帧已关闭）。此序列已在 Windows 和安卓真机验证。
4. 集成测试不计入覆盖率，但每条测试必须在矩阵中登记（类型"集成"）。
5. 报告 `build/integration_report.json`（每个文件 3 次的结果与耗时）附在 PR 描述里。

---

## 10. CI（`.github/workflows/luckdraw-ci.yml`）

仓库根 `.github/workflows/luckdraw-ci.yml` 是实际配置；本节说明当前行为和待验证边界，不复制一份易过期的完整 YAML。只在 PR、main 推送、手动触发运行，排除仅文档改动；远程作业仍待验证；本地最低SDK Flutter3.24.5/Dart3.5.4 analyze零诊断、非golden951通过，见 [MIN_VERSION_REPORT.md](MIN_VERSION_REPORT.md)，该报告另记最低版本golden像素差异。

| 作业 | 已落地的配置 | 验收边界 |
| --- | --- | --- |
| gate | stable；pub get 后立即恢复分析配置；串行 analyze/test，覆盖率路径 coverage/ci.lcov；coverage、acceptance、imports；parity 工具存在时核验 manifest | 本机批次结果见 ACCEPTANCE；不等同 GitHub 作业通过 |
| example | 只在 example/pubspec.yaml、tool/bench/pubspec.yaml 各自存在时安装并分析独立工程 | 文件存在条件不能替代集成测试或真机 profile |
| min-sdk | Flutter 3.24.5；保留分析配置；字体存在检查；analyze、串行非 golden 测试 | 当前未取得本批远程运行证据，待落地验证 |
| treeshake-web | 工具存在时执行 --backend=web | 本地累计十探针成功，预算已回填；远程作业仍需运行证据 |
| treeshake-apk | 已重新启用，自动构建五项探针 | 本地十项零泄漏且预算已回填；远程结果待验 |

T0.1 对后续工具与独立工程设置文件存在条件，逐阶段启用；B13a 的解析器/构建流程夹具通过不能替代真实产物。字体路径先检查，必要时 precache 后再检查；缺字体显式抛错。golden 标签已注册；Linux golden与远程min-sdk作业尚无成功证据；本地3.24.5非golden验证已通过，不能代替这两项。

pub get 后保存/检查/恢复 analysis_options 的动作必须紧接依赖安装，不能等到交付前才发现规则被改；规范内容以 IMPLEMENTATION_GUIDE §2.3 为准，包含 tool/treeshake/probes/**。远程还须核验 FLUTTER_ROOT 及字体回退逻辑、3.24.5 analyze 零诊断，不从 YAML 静态存在推导成功。

### 10.1 本地全量门禁（每张任务卡、合并前、发布前）

```powershell
flutter pub get --no-example
# 紧接上一步核对并恢复 IMPLEMENTATION_GUIDE §2.3 的分析配置。
flutter analyze --no-pub
dart format lib test tool
dart format --output=none --set-exit-if-changed lib test tool
flutter test --no-pub --concurrency=1 --coverage --coverage-path=coverage/<批次>.lcov --reporter=json > coverage/<批次>.tests.jsonl
dart run tool/coverage.dart --min=100 --lcov=coverage/<批次>.lcov
dart run tool/check_acceptance.dart
dart run tool/check_acceptance.dart --from-json coverage/<批次>.tests.jsonl
dart run tool/check_imports.dart
dart run tool/parity/generate.dart --verify-manifest
```

M4 之后追加：`cd example; flutter analyze`、`dart run tool/treeshake/check_treeshake.dart --backend=web`（串行、单独跑，内存紧张时不与其它构建并行）。

内存紧张时按 [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) 的FIN四组串行执行并验证文件并集：旧REL三组缺少后来新增的test/perf和test/example_pages_test.dart，不能漏跑。合并真实成功JSON及LCOV后再执行覆盖率与--from-json门禁。

将命令中的 `<批次>` 替换成实际批次名；analyze 与 flutter test 同一时刻只跑一个，单命令 5 分钟无结果视为挂起，终止后缩小范围重试。文档专批 B17a 不运行本节 pub get、Flutter 测试或构建，仅进行只读引用与文本自检；不得自报未运行的 analyze/coverage 结果。
