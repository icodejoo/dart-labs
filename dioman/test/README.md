---
title: dioman 测试六层分类指南
status: active
updated: 2026-10-27
summary: dioman 测试按单元/规则/边界/组合/集成六层归档的判定规则、Dart 目录命名、标题约定、运行方式。照搬 axp 的分层规范，只做 Dart 适配。
---

# dioman 测试分层指南

分层规则照搬 axp：[`apps/axp/docs/guides/test-layers.md`](../../../codejoo/apps/axp/docs/guides/test-layers.md)（判定顺序、去重规则、映射记录字段都以它为准）。这里只写 Dart 上不一样的地方和 dioman 自己的落地细节。

一句话：**一个行为只在最低的、能证明它的那一层测一次；按"测什么"分层，不按"从哪轮修复来"命名。**

## 六层

| 层 | 测什么 | 依赖 | 目录 |
|---|---|---|---|
| 单元 `unit` | 单个纯对象/函数：`DiomanException`、extra 键注册表、`Dioman.sort/validate`、重放/认领基础设施、pairwise 生成器 | 不装 Dio 插件链 | `test/unit/` |
| 规则 `rule` | **单个插件**对外 API 的声明行为：每个选项、请求级开关、回调的正常路径 | `Dioman.install` + 假 adapter / 本地 `TestServer` | `test/rule/` |
| 边界 `boundary` | **单个插件**的极端输入、并发时序、取消时机、容量溢出、异常回调 | 同规则层 | `test/boundary/` |
| 组合 `combo` | **两个及以上插件**的语义交互，含全栈冒烟和 powerset 扫描 | 同规则层，装多个插件 | `test/combo/` |
| 集成 `integration` | 装配（install 顺序、动态插拔）、源码/文档一致性、连真实服务 47080/47090 的白盒入口 | 真实 Dio、仓库文件、真实服务 | `test/integration/` |
| 验收 `acceptance` | 黑盒：testkit 场景 × 网络 × 风格，真实服务 + netem | api-ws-demo、netem | `accept/` + testkit 场景（不在 `test/` 下） |

`test/support/` 只放夹具，不放用例；`accept/` 与 testkit 本次没动。

判定顺序（命中即停）：只用一个对象就能证明 → unit；单插件正常行为 → rule；单插件极端/时序 → boundary；多插件 → combo；装配/真实环境 → integration；必须真服务才成立 → acceptance。拿不准放 rule。

## 目录与命名（Dart 差异）

Dart 的测试文件必须以 `_test.dart` 结尾，且是 `lower_case_with_underscores`，所以 axp 的 `retry.rule.test.ts`、`auth+retry.combo.test.ts` 在这里写成：

```
test/
├── unit/          <模块>_test.dart                 例：extra_keys_test.dart
├── rule/          <插件>_rule_test.dart            例：retry_rule_test.dart
├── boundary/      <插件>_boundary_test.dart        例：cache_boundary_test.dart
├── combo/         <a>_<b>_combo_test.dart          插件名字母序；另有 powerset_combo_test.dart、full_stack_combo_test.dart
├── integration/   <主题>_integration_test.dart     例：install_integration_test.dart
└── support/       夹具（fixtures.dart、test_server.dart、fake_cache_persist.dart）
```

- 文件名只写主题，不出现 fix / review / coverage / dioman 这类来源字样。
- 单文件约 ≤ 400 行；超了按主题拆，主题写在插件名后面：`cache_policy_rule_test.dart`、`auth_concurrent_boundary_test.dart`、`retry_share_arbitration_combo_test.dart`。
- 历次修复的编号（`#9`、`review2 #6` 等）保留在 `group` 名和用例标题里，用例按内容归层，不单独成"回归"文件。

## 用例标题

标题以 `[API id]` 开头，id 取自 [`accept/lib/api-inventory.json`](../accept/lib/api-inventory.json)（691 项公开 API 台账）：

```dart
test('[DiomanRetry.respectRetryAfter] Retry-After 数字、日期……', () async { ... });
```

- 一条用例涉及多个 API 就写多个：`[DiomanCache.maxEntries][DiomanCache.clone]`。
- 组合层用 `×`：`[DiomanAuth.onRefresh × DiomanRetry.max]`。
- unit 层没有台账 id 时写 `[模块.函数]`，如 `[cancellableDelay]`、`[ReplayClient.finishRecovered]`。
- 现有标题里的 id 是**按正文自动推荐 + 人工覆盖**出来的，粒度和准确度没有逐条审计；后续补台账缺口时顺手校正。映射里标"无台账 id"的用例见 [MIGRATION.md](MIGRATION.md)。

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
dart test --coverage=coverage/local
dart pub global run coverage:format_coverage --lcov --in=coverage/local --out=coverage/local.info --packages=.dart_tool/package_config.json --report-on=lib
```

## 去重要点（摘自 §3）

同层 + 同 API id + 同输入 + 同期望 = 重复，删后者；同 id 不同输入是变体，保留。`DiomanRetry.share` 兼容 setter 接线和自动接线是两种输入，所以不算重复。跨层重复保留最低层。`drop` 必须在 [MIGRATION.md](MIGRATION.md) 里指向保留者的新位置。

## 相关

- 旧→新映射、基线与核对公式：[MIGRATION.md](MIGRATION.md)
- 验收执行器手册：[`accept/docs/README.md`](../accept/docs/README.md)
