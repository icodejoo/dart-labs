---
title: dioman 测试六层分类指南
status: active
updated: 2026-10-29
summary: dioman 测试六层归档规则、三档可信度标注、总账矩阵与闸门的日常用法、Dart 目录命名、标题约定、运行方式。
---

# dioman 测试分层指南

分层以 [洋葱管线测试方案](../design/pipeline-test-plan.md) 为准，目录回答测试范围，可信度另行登记。

一句话：**一个行为只在最低的、能证明它的那一层测一次；按"测什么"分层，不按"从哪轮修复来"命名。**

## 六层

| 层 | 测什么 | 依赖 | 目录 |
|---|---|---|---|
| 单元 `unit` | 单个纯对象/函数：`DiomanResponse`、类型化选项、固定阶段排序、请求补丁与取消原语、pairwise 生成器 | 不装 Dio 插件链 | `test/unit/` |
| 规则 `rule` | **单个插件**对外 API 的声明行为：每个选项、请求级开关、回调的正常路径 | `Dioman(dio: ..., plugins: ...)` + 假传输 / 本地 HttpServer | `test/rule/` |
| 边界 `boundary` | **单个插件**的极端输入、并发时序、取消时机、容量溢出、异常回调 | 同规则层 | `test/boundary/` |
| 组合 `combo` | **两个及以上插件**的语义交互，含全栈冒烟和 powerset 扫描 | 同规则层，装多个插件 | `test/combo/` |
| 集成 `integration` | 装配（固定阶段、动态插拔）、源码/文档一致性、连真实服务 47080/47090 的白盒入口 | 真实 Dio、仓库文件、真实服务 | `test/integration/` |
| 验收 `acceptance` | 黑盒：testkit 场景 × 网络 × 风格，真实服务 + netem | api-ws-demo、netem | `test/accept/`（执行器，无 `_test.dart`，`dart test` 不会跑它）+ testkit 场景 |

`test/support/` 只放夹具，不放用例。

判定顺序（命中即停）：只用一个对象就能证明 → unit；单插件正常行为 → rule；单插件极端/时序 → boundary；多插件 → combo；装配/真实环境 → integration；必须真服务才成立 → acceptance。拿不准放 rule。

## 三档与总账（和六层正交）

六层回答"放哪"，三档回答"这条绿灯能不能信"。完整方案见 [测试体系方案](../design/test-matrix-plan.md)；不变量与 powerset 见 [洋葱管线测试方案](../design/pipeline-test-plan.md)。

| 档 | 判定 | 要做的 |
|---|---|---|
| ① 纯单测 | 把替身全换掉，结论仍成立 | 只写单测 |
| ② 单测 + 真实核对 | 结论依赖替身对真实传输/服务的假设 | 单测穷举分支；矩阵行写上依赖的假设 H（[假设清单](../../test/ASSUMPTIONS.md)），挂一个真实代表用例 |
| ③ 只能真实 | 没有可模拟的逻辑 | 只在 `test/accept/` 跑 |

`TestTokens`、`FakeCachePersist`、`isOnline` 这类**契约替身**模拟的是使用者注入的实现，按 ① 处理。

**加一条用例时**：标题用 `[API id]` 开头，总账就能自动反查到它，不用改 `matrix.json`。

**加一个公开 API 或选项时**：

```powershell
dart run test/accept/bin/inventory.dart          # 刷新台账
dart run test/accept/bin/matrix.dart sync        # 为新 API 生成草稿行（tier 为空）
# 编辑 test/accept/lib/matrix.json：填 capability / tier / assumptions / real
dart test test/integration/matrix_integration_test.dart   # 静态闸门：G0/G2/G3/G5
```

**跑完一轮真实验收后**：

```powershell
dart run test/accept/bin/matrix.dart evidence coverage/accept/normal-http.json coverage/accept/plugin-matrix-final.json
dart run test/accept/bin/matrix.dart results     # 回填每行结论
dart test --coverage-path=coverage/local.info
dart run test/accept/bin/matrix.dart gates --lcov=coverage/local.info --report=docs/reports/<日期>-matrix-gaps.md
```

闸门报"已修复但仍在基线"时，运行 `gates --lcov=… --update-baseline` 把它从基线删掉；基线只减不增。

## 目录与命名（Dart 差异）

Dart 的测试文件必须以 `_test.dart` 结尾，且是 `lower_case_with_underscores`，所以 axp 的 `retry.rule.test.ts`、`auth+retry.combo.test.ts` 在这里写成：

```
test/
├── unit/          <模块>_test.dart                 例：options_unit_test.dart
├── rule/          <插件>_rule_test.dart            例：retry_rule_test.dart
├── boundary/      <插件>_boundary_test.dart        例：cache_boundary_test.dart
├── combo/         <a>_<b>_combo_test.dart          插件名字母序；另有 powerset_combo_test.dart、full_stack_combo_test.dart
├── integration/   <主题>_integration_test.dart     例：source_transport_integration_test.dart
└── support/       夹具（fake_network.dart、fake_clock.dart、invariant_harness.dart、helpers.dart）
```

- 文件名只写主题，不出现 fix / review / coverage / dioman 这类来源字样。
- 单文件约 ≤ 400 行；超了按主题拆，主题写在插件名后面：`cache_policy_rule_test.dart`、`auth_concurrent_boundary_test.dart`、`retry_share_arbitration_combo_test.dart`。
- 历次修复的编号（`#9`、`review2 #6` 等）保留在 `group` 名和用例标题里，用例按内容归层，不单独成"回归"文件。

## 用例标题

标题以 `[API id]` 开头，id 取自 [`test/accept/lib/api-inventory.json`](../../test/accept/lib/api-inventory.json)（744 项公开声明、成员与参数）：

```dart
test('[DiomanRetry.respectRetryAfter] Retry-After 数字、日期……', () async { ... });
```

- 一条用例涉及多个 API 就写多个：`[DiomanCache.maxEntries][DiomanCache.clone]`。
- 组合层用 `×`：`[DiomanAuth.onRefresh × DiomanRetry.max]`。
- unit 层没有台账 id 时写 夹具对应的现有符号或总账 INV 行 id；不要写仓库中不存在的 id。
- 现有标题里的 id 是**按正文自动推荐 + 人工覆盖**出来的，粒度和准确度没有逐条审计；后续补台账缺口时顺手校正。映射里标"无台账 id"的用例见 [迁移映射](../archive/test-migration-2026-10-27.md)。

## 怎么跑

```powershell
dart test                          # 默认：全部本地用例（排除 real 标签），含 powerset，约 8~9 分钟
dart test test/rule                # 只跑一层
dart test test/rule/retry_rule_test.dart
dart test test/combo               # 按层/目录过滤即可，不需要改配置

# 连真实服务（须先确认 47080/47090 已在运行；遇 429/503 或不可达立即停）
dart test -t real --configuration=dart_test.real.yaml
```

`real` 标签的用例（`test/integration/real_service_integration_test.dart`，文件头 `@Tags(['real'])`）默认不跑。

**为什么真实测试要带 `--configuration=dart_test.real.yaml`**：`dart_test.yaml` 里写了 `exclude_tags: real`，当前 test 1.33 把配置和命令行的 `exclude_tags` 取并集、排除优先，单独 `dart test -t real` 会得到 "No tests were selected"（已用探针文件验证）。`dart_test.real.yaml` 不再排除 `real`，并把并发压到 1（真实服务不能被并行冲击）。所以两个配置文件保留，没有合并。

覆盖率：

```powershell
dart test --coverage-path=coverage/local.info     # test 包内置，直接出 lcov，不需要全局 coverage 包
dart run test/accept/bin/matrix.dart gates --lcov=coverage/local.info   # 顺带跑 G1
```

## 去重要点（摘自 §3）

同层 + 同 API id + 同输入 + 同期望 = 重复，删后者；同 id 不同输入是变体，保留。例如请求级 true 与显式选项对象是两种输入，不应只因 API id 相同而合并。跨层重复保留最低层。`drop` 必须在 [迁移映射](../archive/test-migration-2026-10-27.md) 里指向保留者的新位置。

## 相关

- 旧→新映射、基线与核对公式：[迁移映射](../archive/test-migration-2026-10-27.md)
- 验收执行器手册：[验收执行器手册](accept-runner.md)
