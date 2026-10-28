---
title: dioman 洋葱管线测试方案
status: active
updated: 2026-10-29
summary: 六层测试、不变量 I1–I7 与夹具、powerset、覆盖率与总账闸门、性能门槛、验收矩阵、旧用例迁移
---
## TL;DR

- 沿用六层（unit / rule / boundary / combo / integration / acceptance）和标题 `[API id]` 约定，**按新 API 重写，不搬旧断言**。
- 不变量 I1–I7 做成夹具，从内核批次起生效；powerset 枚举 9 个有交互的插件（512 个子集）× 9 条流程，只断言不变量。
- 门槛：内核 6 个文件行覆盖与分支覆盖 100%；全库行 ≥ 95%；总账闸门 G0–G5 全绿；每批做变异验证。
- 性能用 `Stopwatch` 自写 bench，和旧版交错对比；验收用 testkit 全量场景在新服务端实例上跑。

## 1. 六层

层的判定、命名与去重规则沿用 [测试分层](../guides/test-layers.md)。洋葱模型下的补充：

| 层 | 测什么 | 用什么 |
|---|---|---|
| unit | 纯函数与纯类：工厂判定、`resolveOption`、key 算法、patch 合并、阶段排序、时钟与取消原语 | 不建 `Dioman` |
| rule | 单个插件文档写明的行为 | `Dioman` + 假传输（见 §2） |
| boundary | 单个插件的极端输入与时序 | 同上 + 假时钟 |
| combo | 两个及以上插件的交互、powerset | 同上 |
| integration | 装配（inspect、use、eject、extend、dispose）、真实 IO（本地回环 HttpServer）、文档与源码一致性、总账闸门 | 真实 Dio |
| acceptance | testkit 场景 × 网络 × 风格 | `test/accept/` 执行器 + 真实服务 |

约束：
- **假传输优先**：rule、boundary、combo 用替换 Dio `httpClientAdapter` 的假 adapter（夹具 `FakeNetwork`：按路由返回状态码、延迟、业务码，记录每次发送的请求体），不起真服务器。
- **时间用假时钟**：内核与插件都通过 `DiomanClock` 取时间、建计时器；测试注入 `FakeClock`（`elapse`、`pendingTimers`），不 sleep。`DiomanClock` 由 B1 实现，B1 同时交付 `FakeClock` 夹具。
- 单文件 ≤ 约 400 行，标题以 `[API id]` 开头，id 取自重新生成的台账。

## 2. 夹具（`test/support/`）

| 夹具 | 作用 |
|---|---|
| `FakeNetwork` | 假 adapter：路由表、可脚本化的响应序列、`fail_on` 式的第 n 次失败、业务码信封、记录每次发送（含请求体与 `x-invariant-request` 标记） |
| `FakeClock` | 可推进的时钟与计时器，`pendingTimers` 供 I3 断言 |
| `InvariantHarness` | 每个逻辑请求登记、最外层与每阶段的直通探针、发送记录、取消订阅追踪；`assertAll()` 一次检查 I1–I7 |
| `TestTokens` | 可变 token 管理器（沿用） |

## 3. 不变量

| # | 内容 | 测法 |
|---|---|---|
| I1 | 每个逻辑请求恰好落定一次 | harness 记录调用方侧的完成次数，以及最外层探针按 `ctx.id` 记录的进出次数，都必须为 1 |
| I2 | loading 回调成对，最后一个是 false | 按回调记录序列，长度为偶数，且奇偶位依次为 true、false |
| I3 | 结束后 `api.pending == 0`，没有残留的取消订阅和计时器 | 内核取消订阅登记数为 0；`FakeClock.pendingTimers` 为 0 |
| I4 | 每个逻辑请求最多通知一次 | stringify 里以 `ctx.id` 标记，notify 里按它计数（share 跟随者拿到的是同一个 R，所以不能按响应对象区分） |
| I5 | 并发 401 只调用一次 `onRefresh` | 按"刷新轮"计数，每轮恰好 1 次 |
| I6 | `next()` 从不出错 | 每个阶段的 pre 与 post 位置各挂一个直通探针，捕获到异常即失败；受控流程里不许出现 internal 结果 |
| I7 | 同一逻辑请求的每次发送，请求体一致 | 按 `x-invariant-request` 标记分组比较各次发送的请求体。**用嵌套结构**（如 `{'items': [{'n': 0}]}`）并让 Transformer 原地改它，确认去掉 `markReplayable()` 时用例会失败（axp B3 的教训：浅对象会被浅拷贝掩盖） |

## 4. powerset（`test/combo/powerset_combo_test.dart`）

- **插件表驱动**：9 个有交互的插件——loading、notify、retry、breaker、auth、mock、share、cache、offline。repath、filter、timeout 只做请求整形，和其余插件没有时序交互，放在成对组合里测，不进 powerset。
- 位掩码枚举 512 个子集，跳过依赖不满足的组合。
- **9 条流程**：成功（并再命中一次）、HTTP 500、500 两次后成功、business 401 刷新（3 个并发、其中 2 个同 key）、网络错误、并发同 key、中途 `cancelAll`、首发取消（看 share 跟随者）、离线后恢复。每条流程只发请求、推进假时钟，最后统一 `assertAll()`。
- 每条流程有 baseline（不装插件时每个请求应得到的 kind），单独一组用例核对它，防止脚本空转。
- 每次运行用全新的插件对象和全新的夹具。规模 512 × 9 = 4608 条，目标在 2 分钟内跑完（powerset 用假传输，不受本地端口限制）。
- 另外保留 3 条元测试：子集互不相同、包含空集与全集；恰好 512 个；依赖缺失的子集不生成。

## 5. 覆盖率与总账

- **内核 6 个文件**（`pipeline`、`context`、`request`、`response`、`transport`、`client`）：行覆盖与分支覆盖 100%（`dart test --coverage-path … --branch-coverage`）。从 B1 起生效。
- **全库**：行覆盖 ≥ 95%，B5 起生效。走不到的防御分支要么删掉，要么在终审时说明理由并登记进 G1 白名单，不加忽略注释。
- **总账**：B5 重新生成台账、`sync` 矩阵、重新定档；闸门 G0–G5 全绿后才能切换入口。G4 的真实证据来自 B7 的验收。
- **变异验证**：每批改坏 `lib/src` 的若干处，确认有用例失败，再原样恢复；报告里列出变异项与结果。

## 6. 性能

- 不新增依赖，用 `Stopwatch` 自写 bench（`benchmark/`，不进 `test/`）：每个场景预热 500ms，至少测 2s，连续独立跑 3 轮，取中位数；稳定口径是三轮的最大值与最小值相差不到 10%。
- 假 adapter 立即返回一个新信封，不用 `FakeNetwork`（它带路由表开销）。
- 场景与门槛（相对裸 Dio 的额外开销，和**旧版 dioman 交错 A/B** 对比，不和裸 Dio 的绝对值直接相减）：

| 场景 | 门槛 |
|---|---|
| S1 裸 Dio + 假 adapter | 参照值 |
| S2 dioman 无插件 | 额外开销 ≤ 旧版 `Dioman.install` 无插件的额外开销 |
| S3 全插件、缓存未命中 | 额外开销比旧版降低 ≥ 20% |
| S4 缓存命中 | 不低于旧版 |
| S5 100 并发同 key share | 不低于旧版 |
| S6 带 data 的 POST + retry 装上但不触发 | 不低于旧版（验证请求体按需克隆） |

- 机器有外部负载时，三轮离散度不达标的数字只留档、不下结论。

## 7. 验收矩阵

- 执行器 `test/accept/` 改用新 API。**执行器里不许有任何替库补能力的代码**：业务码判定、retry/breaker 的 `shouldRetry`/`shouldTrip` 适配、信封转换器都删掉，归类只读 `DiomanResponse` 的 `kind`、`reason`、`status`。
- 能力名按实际能力登记：新增 `mock-in-chain`；`raw-business-code`（D21 的"未装 normalize 时业务码透传"）dioman 不具备，相关场景按缺能力跳过——testkit 侧要先加这个能力名（见实施计划 B7）。
- 跳过分两类：缺能力（`skipped: missing <cap>`）与不适用（原因以"不适用："开头，从场景字段通用识别，不靠场景 id 清单）。新增的不适用规则上线前，要和规则出现之前的失败格逐格对账，多跳 0、漏跳 0。
- 通过标准：可执行格全部通过；每格的通用断言成立（`pending_after == 0`、loading 成对且最后为 false、服务端 `inflight == 0`）；报告写明通过、跳过的数量与理由。
- 新服务端二进制在独立端口起实例运行（`TESTKIT_SERVER`/`TESTKIT_NETEM`），不动 47080/47090。

## 8. 旧用例迁移

- B0 把旧的 580 条用例和总账 440 行逐条登记为 keep（行为不变，按新 API 重写）、change（行为有意改变，对应 §9 的 C 编号）、drop（能力删除，写明替代）。公式 `旧总数 = keep + change + drop` 必须成立。用语法树或运行时事件统计用例数，不用文本计数（axp B0 的教训）。
- 迁移期旧用例移到 `test_legacy/`（不在 `test/` 下，`dart test` 不会扫到），对应插件迁完就删；B5 结束时目录清空。
