---
title: dioman 洋葱管线实施计划
status: active
updated: 2026-10-29
summary: B0–B7 分批、每批的完成标准、Codex 派发约束、终审关卡与风险
---
## TL;DR

- 在 `jelon/dioman-pipeline` 分支、独立 worktree（`E:\workspaces\dart-labs-pipeline`）上分 8 批推进。每批结束时全量 `dart test` 全绿；**Codex 写代码并自测，Opus 只做终审**；终审通过后由主会话提交。
- 顺序：基线 → 内核 → 无状态插件 → retry/breaker/auth → source 四件套 → 测试收尾与切换 → 文档 → 验收。
- 依据：[决策 0001](../decisions/0001-pipeline-redesign.md)、[核心架构](pipeline-architecture.md)、[插件规格](pipeline-plugin-spec.md)、[测试方案](pipeline-test-plan.md)。axp 的同类做法与教训见 `E:\workspaces\codejoo\apps\axp\docs\design\implementation-plan.md` 与各批报告。

## 1. 批次

| 批 | 内容 | 完成标准 |
|---|---|---|
| B0 基线 | 旧版 bench（S1–S6，三轮稳定口径）；旧用例与总账的 keep/change/drop 清单；旧测试移到 `test_legacy/` | 清单公式成立；bench 数据留档；`dart test` 仍全绿（此时只剩不受影响的用例与新目录骨架） |
| B1 内核 | `clock`、`request`、`response`、`context`（含取消原语）、`pipeline`、`transport`、`client`、`key`、`options`；`FakeNetwork`、`FakeClock`、`InvariantHarness` 夹具 | 测试方案 §3 的 unit；client 与取消的 rule/boundary；I1、I3、I6、I7 生效；**内核 6 个文件行覆盖与分支覆盖 100%** |
| B2 无状态插件 | loading、notify、repath、filter、timeout、envs | 各插件 rule/boundary；I2、I4 |
| B3 重试与鉴权 | retry、breaker、auth、TokenManager | rule/boundary；retry+breaker、retry+auth、loading+auth、notify+auth；I5 |
| B4 结果来源 | mock、share、cache、offline | rule/boundary；source 内部及与 retry/auth 的组合 |
| B5 收尾与切换 | powerset；成对组合补齐；删除旧源码与 `test_legacy/`；`lib/dioman.dart` 切到新导出；台账重建、矩阵 sync 与重新定档 | 全库行覆盖 ≥ 95%；闸门 G0–G3、G5 全绿；I1–I7 全部生效；迁移公式成立 |
| B6 文档 | README 中英文、`docs/design/architecture.md` 重写、CHANGELOG（Breaking + 迁移指南 `docs/guides/migrating-to-pipeline.md`）、SKILL.md、example | 文档里的示例都能编译（integration 层有用例抽取并编译文档示例）；bench 与旧版交错对比写进报告 |
| B7 验收 | 执行器改用新 API；testkit 侧补 `raw-business-code` 能力名与 axp 反馈的两处（`basic.status-matrix` blackhole 档缺超时、`cancel_after_ms` 未声明 `cancel`）；新服务端实例全量跑；证据回填总账 | 测试方案 §7 的通过标准；G4 只剩 connect 超时；验收报告 |

- 批次线性推进，不并行：B2–B4 共用 `test/support/` 夹具和组合用例。
- **B5 拆成两次派发**（B4 终审后定）：B5a 做 powerset、成对组合补齐与 `lib/src/pipeline/` 逐文件覆盖，不删任何文件；B5b 做删除与切换。删除旧源码会让执行器、example、key 对照测试、旧版 bench 失去编译对象，所以 **执行器改用新 API 从 B7 提前到 B5b**；key 对照测试先导出旧版结果作固定基准；旧版 bench 改从旧提交的临时 worktree 运行，供 B6 交错对比。B7 只剩 testkit 侧补能力与全量验收。
- 每批报告放 `docs/reports/2026-10-29-pipeline-b<n>.md`，结构：TL;DR → 文件清单 → 验收（逐条命令与输出摘要、覆盖率逐文件计数）→ 本批 API id → 迁移清单对账 → 规格不清与保守取舍（需终审确认的单列）→ 终审修复（问题、修法、回归用例；撤掉修复后回归用例会失败）。

## 2. 每批工作方式

1. 主会话把本批范围、相关文档章节、上一批终审结论写进派发说明，派给 Codex。
2. Codex 实现，跑 `dart analyze`（0 issue）、本批测试与全量 `dart test`、覆盖率命令，然后 `codex review --uncommitted` 自审一轮，修掉成立的问题，写批次报告。
3. 主会话终审：对照文档逐条核对行为；检查有没有偷偷保留旧机制（`extra[...]` 字符串状态、`handler.next/resolve`、`claimRequest`、`DioException` 作为失败载体）；检查注释规范（中文简短，公共 API 写契约、参数、返回、示例）；检查新增函数都有单测；抽查变异验证。
4. 终审通过后由主会话提交：`refactor(dioman): …` / `test(dioman): …`。不通过先写清理由，再决定自己改还是退回重做。

## 3. Codex 派发约束（每份说明都写）

- 自己执行，不转派；不得 `git commit/push`、切分支；误提交不回滚，只汇报 hash。
- 每一步开始前先说在做什么、为什么；跑测试要等最终结果再汇报。
- 不新增依赖，需要时停下说明；最低 SDK `^3.5.0`，不用更高版本才有的语言特性。
- 注释规范见 CLAUDE.md；同一字面量出现 2 次以上提取常量；沿用项目命名（`Dioman` 前缀）。
- 改动范围只限 `E:\workspaces\dart-labs-pipeline\dioman\`（B7 另有说明）。
- 全量 `dart test` 与真实验收不要同时跑（本地端口会互相抢）。

## 4. 风险

| 风险 | 应对 |
|---|---|
| 一次重写面太大 | 小批次加每批终审；B0 清单先行 |
| 取消原语在 Dart 里失真（`CancelToken` 不能摘监听、`Future.delayed` 不能取消） | B1 先做取消原语与 `FakeClock`，I3 从 B1 起断言没有残留订阅和计时器 |
| 请求体重放（FormData 只能 finalize 一次、Stream 无法重放） | B1 的 `markReplayable` 按类型分支；I7 用嵌套结构并做变异验证 |
| 行为变化在验收里出意外 | 逐条归因：实现 bug 就修；方案问题回到文档改，并同步 §9 行为变化表与 CHANGELOG |
| 性能不达标 | 先用 bench 定位热点；优化不得破坏不变量；门槛调整要用户批准，原文保留 |
| Codex 不可用 | 不死磕重试，改派 sonnet 子代理接手，说明沿用 |
