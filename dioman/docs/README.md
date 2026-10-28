# dioman 文档索引

找文档先看这里，再打开目标文件。路径都相对 dioman 根目录。

## 续做

- [当前状态](status.md) — 测试体系进度、闸门现状、待拍板的产品问题、P2 补测清单。active。

## 决策

- [0001 洋葱管线重构的决策](decisions/0001-pipeline-redesign.md) — 以 Dio 为引擎的洋葱管线、固定阶段、归一化进内核、错误模型、取消与 key 内核化、mock 回到 source，及推翻的旧约定。active。

## 设计

- [洋葱管线核心架构](design/pipeline-architecture.md) — 内核模块、数据流、阶段排序、上下文与取消原语、归一化响应与落定、插件接口、客户端 API、性能设计。active。
- [洋葱管线插件规格](design/pipeline-plugin-spec.md) — 12 个内置插件与内核服务的选项、行为、内核依赖，行为变化汇总 C1–C12。active。
- [洋葱管线测试方案](design/pipeline-test-plan.md) — 六层、不变量 I1–I7、powerset、覆盖率与总账闸门、性能门槛、验收矩阵、旧用例迁移。active。
- [洋葱管线实施计划](design/pipeline-implementation-plan.md) — B0–B7 分批、完成标准、Codex 派发约束、终审关卡与风险。active。
- [测试体系方案](design/test-matrix-plan.md) — 三档 + 总账矩阵 + 五道闸门 + 分阶段计划。active。
- [架构](design/architecture.md) — 执行模型、插件职责、安装顺序、extra 键表（测试会核对键表）。active。

## 操作手册

- [测试分层](guides/test-layers.md) — unit/rule/boundary/combo/integration/accept 判定、命名、标题 id、怎么跑。active。
- [验收执行器](guides/accept-runner.md) — 连 47080/47090 跑 testkit 场景与插件矩阵、维护工具。active。

## 参考

- [testkit 字段映射](reference/testkit-mapping.md) — testkit schema 字段 → dioman 参数或宿主职责。active。

## 报告

- [总账缺口报告 2026-10-28](reports/2026-10-28-matrix-gaps.md) — G1–G5 当前缺口与按插件分布，P2 补测基线（由 `gates --report` 生成）。active。
- [插件五方法真实矩阵 2026-10-27](reports/2026-10-27-plugin-matrix.md) — 156 格结论，"待补"项将由总账接管。active。
- [行覆盖逐行复核 2026-10-27](reports/2026-10-27-coverage-review.md) — 1788/1793，剩余 5 行兜底理由。active。
- [源码自审 2026-10-27](reports/2026-10-27-library-review.md) — 七文件改动核对与对应回归。active。

## 归档

- [测试迁移映射 2026-10-27](archive/test-migration-2026-10-27.md) — 旧 13 文件 → 六层逐条对应。archived。
- [testkit 中的 dioman 覆盖分析 2026-10-27](archive/2026-10-27-testkit-coverage-dioman.md) — 原在 testkit 的手工静态分析，数据见同名 [.json](archive/2026-10-27-testkit-coverage-dioman.json)；已被总账取代。archived。
- [testkit 手册里的 dioman 复核笔记 2026-10-27](archive/2026-10-27-testkit-agents-dioman-notes.md) — 原在 testkit AGENTS.md 末尾的两节。archived。

## 测试资产速查

总账 = 验收矩阵 = `matrix.json`；台账 = API 清单 = `api-inventory.json`；验收 = accept = 真实服务测试。

| 要找 | 路径 |
|---|---|
| 各层用例 | `test/{unit,rule,boundary,combo,integration}/` |
| 夹具：假适配器、TestTokens、组合安装 | `test/support/fixtures.dart` |
| 本地真实 HTTP 服务夹具 | `test/support/test_server.dart` |
| 本地全量组合（powerset） | `test/combo/powerset_combo_test.dart` |
| 真实服务白盒入口（`real` 标签） | `test/integration/real_service_integration_test.dart` |
| 验收执行器源码 | `test/accept/bin/`（入口）、`test/accept/lib/`（实现） |
| 公开 API 台账（691 项） | `test/accept/lib/api-inventory.json` |
| 真实 pairwise 执行计划 | `test/accept/lib/plugin_matrix_plan.json` |
| 总账矩阵 / 缺口基线 / 行覆盖白名单 | `test/accept/lib/matrix.json`、`matrix-baseline.json`、`matrix-lcov-whitelist.json` |
| 闸门、证据汇总、结论回填 | `dart run test/accept/bin/matrix.dart gates / evidence / results`；静态闸门 `test/integration/matrix_integration_test.dart` |
| 入库的真实验收证据汇总 | `test/accept/evidence/` |
| 假设清单（H 编号） | `test/ASSUMPTIONS.md` |
| 给 testkit 的提议（外部仓库，已落地为 testkit D20–D23，顶部有各节去向） | `E:\workspaces\api-ws-demo\testkit\proposals\2026-10-28-dioman-gaps.md` |
| 历史验收日志 / 结果（本地，不入库） | `test/accept/*.log`、`test/accept/results/` |
| 覆盖率与新验收证据（本地产物） | `coverage/` |

## 约束

- 改 `lib/src/` 前必读：`.claude/skills/dioman/SKILL.md`
