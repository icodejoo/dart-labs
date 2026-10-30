---
title: dioman 洋葱管线实施计划
status: active
updated: 2026-10-29
summary: B0–B8 分批、每批的完成标准、Codex 派发约束、终审关卡与风险
---
## TL;DR

- 在 `jelon/dioman-pipeline` 分支、独立 worktree（`E:\workspaces\dart-labs-pipeline`）上分 9 批推进。每批结束时全量 `dart test` 全绿；**Codex 写代码并自测，Opus 只做终审**；终审通过后由主会话提交。
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
- **B8 对照 axp 终审补修**（axp 报告 `E:\workspaces\codejoo\apps\axp\docs\reports\2026-10-29-final-review.md` §2、§8；B7 交回后开工）：
  1. share end/race 撤回：调用方自己取消（或自身超时）的结果不落定共享条目，end 回退到仍在途或最近完成的请求，race 回退到上一个非撤回结果（P1）。
  2. key：非 Map/String 请求体不再用 `identityHashCode`；JSON List 按内容编码，字节体在大小上限内按内容哈希，超过或无法编码（含 `_encode` 的 `toString()` 回退）就不生成 key（P2）。
  3. auth：新增 `refreshTimeout`（默认 30s，超时按刷新失败）；刷新失败时若 token 已被替换（重新登录），等待者按当前 token 继续，不返回 expired；README 写明 onRefresh 经同一客户端发请求必须本次关闭 auth，否则重入等待自己（P1）。
  4. retry：`retryAfterMax` 默认 60s，服务端要求的等待超过上限就不再重试、直接返回本次结果；`null` 改为不封顶需显式传值（语义变化，写进 CHANGELOG；与 axp D1 一致，B8 用户已裁决）。
  5. cache：内存命中返回前重查取消（P2）。
  6. 一次性请求体（Stream 等无法克隆的）：内核提供可否重放的判断，retry、auth、mock 在重放前检查，不能重放就把原结果交给调用方（P2）。
  7. notify：默认 stringify 不给 internal 弹提示（P3）。
  8. 测试：新增不变量 I8 结果归属（一个调用方的取消或超时不改变其他调用方结果的类别）、I9 来源一致（回显的实际请求等于调用方发出的请求）；powerset 补一条带体重发流程（PUT + retry，请求级开 cache/share）；share 三策略 ×｛首发、跟随者、最新者、最后完成者｝×｛取消、超时｝撤回矩阵；每项一条回归。
  9. testkit：share 单一整体预算补 requires: timeout-total（实际为一个场景的两种风格格）；D24 追加裁决，校验与 cargo test。share end/race 参与者取消、超大 Retry-After 等协调后另做，本批不新增。
  10. B7 的 4 类"需终审裁决"：① 非 400–599 业务码（23 格）——场景要 `error: "business:<code>"`，执行器按 `kind == biz` 输出 `business:${r.code}` 即可，这是读库的结果字段，不算替库判业务码；② 坏 JSON（16 格）——库缺陷：解码抛出的 `FormatException` 应归 `parse`（现在落到 internal 被当程序错误抛出），同时核对 HTML 用例在 `expectJson` 下的口径；③ share 单一请求预算（2 格）——本质是整体超时，场景补 `requires: timeout-total`（testkit，按缺能力跳过）；④ offline 早期失败的通知计数（2 格）——维持 dioman 语义（notify 覆盖 offline 失败），"不适用"成立。①②③ 修完后重跑对应格并回填总账。
- **B5b 终审留给 B7 的两件事**：① 执行器对 `total_ms`（整体预算）现在直接拒绝；testkit 侧要登记对应能力名，dioman 不具备时按 `skipped: missing <cap>` 跳过，不能报错，也不能由执行器补计时器。② B5b 把失去旧 API 挂点的 153 个真实场景暂挂在 `INV-REAL` 子行上；B7 回填证据时，能对应到新 API 行的改挂到 API 行，只有确实没有 API 的不变量才留在 INV 行。
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
