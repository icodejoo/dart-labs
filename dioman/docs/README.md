# dioman 文档索引

找文档先看这里，再打开目标文件。路径都相对 dioman 根目录。

## 续做

- [当前状态](status.md) — 测试体系进度、闸门现状、待拍板的产品问题、P2 补测清单。active。

## 设计

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
| 给 testkit 的提议（外部仓库，待拍板） | `E:\workspaces\api-ws-demo\testkit\proposals\2026-10-28-dioman-gaps.md` |
| 历史验收日志 / 结果（本地，不入库） | `test/accept/*.log`、`test/accept/results/` |
| 覆盖率与新验收证据（本地产物） | `coverage/` |

## 约束

- 改 `lib/src/` 前必读：`.claude/skills/dioman/SKILL.md`
