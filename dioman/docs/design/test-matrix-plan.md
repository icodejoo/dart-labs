---
title: dioman 测试体系方案：三档 + 总账矩阵 + 五道闸门
status: active
updated: 2026-10-28
summary: 单测、验收矩阵、全量组合测试如何用一张总账互相印证，做到无死角；含分档规则、矩阵格式、闸门定义与分阶段计划。
---
## TL;DR

- 六层目录（unit/rule/boundary/combo/integration/accept）不动，它回答"放哪"；三档（①纯单测 ②单测+真实核对 ③只能真实）是正交维度，回答"绿灯能不能信"。
- `test/accept/lib/matrix.json` 是唯一总账：行 = 能力子点，挂档位、单测、真实用例、假设、最近结论。其余文档都是它的视图。
- 五道闸门 G1–G5 把行覆盖、API 台账、单测、真实验收、反查串成闭环，任一缺口都会被报出来。
- 执行顺序：P0 搭账 → P1 定档 → P2 补测 → P3 收口。进度见 [status.md](../status.md)。

## 1. 为什么要总账

整理前各本账各管各的，互不对齐：

| 账 | 2026-10-28 实测 | 说明不了的事 |
|---|---|---|
| lcov 行覆盖 | 1788/1793，剩 5 行兜底 | 行被执行过 ≠ 被断言过 |
| accept API 触达 | 691/691 | 构造/读取/调用登记，不是行为验证 |
| 单测标题 `[API id]` | 319 条用例只引用 205/691，另有 12 个 id 不在台账 | id 自动推荐，未审计 |
| 插件五方法矩阵 | 156 格全过 | 单体/边界/规则大量"待补"，粒度只到插件 |
| 组合 | 本地 powerset 32767 + 4095；真实 pairwise 64 格 | 两边没对上账 |

"某个选项有没有被断言过""某个假设上没上真实环境核对过"，在任何一本账里都查不到。

## 2. 三档

判定轴不是"依不依赖真实环境"，而是**单测结论依不依赖对真实环境的假设**。

| 档 | 判定 | dioman 里的典型 |
|---|---|---|
| ① 纯单测 | 把替身全换掉，结论仍成立 | 选项默认值/校验、key 生成、排序校验、extra 键注册表、重放/认领基础设施、插件在真实 Dio 管线里的决策逻辑、本地 powerset |
| ② 单测 + 真实核对 | 逻辑能测，但输入或时机来自真实传输/服务 | 取消时机、超时、连接错误分类与重试、请求体可否重放、Retry-After、连接复用、组合在真实传输下的行为 |
| ③ 只能真实 | 没有可模拟的逻辑 | netem 弱网/抖动、真实连接超时计时、真实服务 429/503、长时间运行与内存 |

dioman 的替身分两类，处理方式不同：

- **环境替身**（`BucketAdapter`、`RecordingAdapter`、`TestServer`）：替真实传输和服务端做了假设，依赖它们的结论是 ②。
- **契约替身**（`TestTokens`、`FakeCachePersist`、`isOnline` 回调）：模拟的是**使用者注入的实现**，没有"真实行为"可核对，按 ① 处理，契约写进 API 文档。

一个能力跨档时拆成多行，各挂各的用例，不用一个结论糊过去。

## 3. 假设清单

清单放在 `test/ASSUMPTIONS.md`，格式与规则照搬《测试三档分类指南》§3：

`编号 | 假设（可证伪的一句话） | 出处（文件:行） | 依赖它的单测 | 核对状态 | 核对方法 | 关联矩阵行`

- 核对状态只有四种：已核对（平台、日期、数字）/ 未核对 / 存疑 / 已证伪。
- 被证伪时，假实现和依赖它的单测要一起改。
- 升级 dio、Dart SDK 后，相关假设重新标"未核对"。

初始候选（P1 逐条核实）：

| 编号 | 假设 | 来源 |
|---|---|---|
| H1 | 取消由 Dio 自己判定，适配器不配合 `cancelFuture` 也会按时以取消结束 | 两个假适配器都忽略 `cancelFuture` |
| H2 | 请求体流是否被消费不影响重放 | `BucketAdapter` 不读请求体，真实适配器会读掉 |
| H3 | 真实 socket 报错时 Dio 给出的 `DioExceptionType` 与单测构造的一致 | retry 按类型判定可否重试 |
| H4 | 连接复用不影响结论 | `TestServer` 强制 `Connection: close` |
| H5 | Dio 会按请求级 timeout 真正超时 | timeout 插件只改配置 |
| H6 | 真实服务返回的 Retry-After 格式与单测构造的一致 | retry `respectRetryAfter` |

还要补列替身"默认就做了"的隐含行为：立即返回、事件必达、顺序固定。

## 4. 总账矩阵

文件：`test/accept/lib/matrix.json`（JSON，与 `api-inventory.json` 并列，不引入新依赖）。

```json
{
  "id": "DiomanRetry.respectRetryAfter#date",
  "plugin": "retry",
  "capability": "Retry-After 为 HTTP 日期时按日期等待",
  "tier": 2,
  "apis": ["DiomanRetry.respectRetryAfter", "DiomanRetry.new(respectRetryAfter)"],
  "real": ["retry.503-retry-after"],
  "assumptions": ["H6"],
  "result": {"status": "BLOCKED", "source": "docs/reference/pipeline-migration/raw/accept-evidence/2026-10-27-summary.json", "passed": 0, "total": 28},
  "blocked": "真实侧被执行器跳过……解锁：给注入场景开白名单"
}
```

- 行 key 优先用台账 API id + 可选 `#子点`；没有 API 的不变量用 `INV-xx`（安装顺序、extra 键注册、状态键清理等）。
- 同一能力的 `XxxOptions.new(x)` 与 `XxxOptions.x` 合成一行，`apis` 里都列上。落地后 439 行，按插件分段（另有 `install`、`extra` 两组）。
- 单测到行的链接靠标题里的 `[API id]` 实时反查，不入库，避免每加一条用例都要同步矩阵。
- 例外：没有 API 的 INV 行，单测标题直接写 `[INV-xx]` 即可；也可用可选字段 `unit` 列测试文件（闸门校验文件存在且含用例）。
- `tier` 为 2/3 的行必须有 `real`；BLOCKED 必须写 `blocked`：缺什么、怎么解锁。
- `real` 里可以写 `local:<测试文件>`，表示**本地真实回环核对**：用真实 IO adapter 加本机 socket，不用替身。只用于假设关乎 Dio IO 实现与操作系统 socket 的行，例如 H1b（取消真的中止连接）、H4（keep-alive 复用）、H5（超时真的生效）；网络条件相关的行仍然必须用 testkit 场景。闸门校验该文件存在且含用例；回填时计一格"通过"，依据是这些文件属于默认 `dart test`，任何失败都过不了全量门槛。
- 中立契约表达不了、或者需要 testkit 改契约/服务端才能核对的行，把提议写进 testkit 的 `proposals/`，`blocked` 指向对应章节。testkit 被多个工程共用，场景和理由放在那边，其他执行器才能复用。
- "预期"写现行行为；与设计不一致时开 issue，不让错误预期的用例每轮红。

`docs/reports/2026-10-27-plugin-matrix.md` 的后续版本改为由总账生成的真实验收视图。

## 5. 五道闸门

| 闸门 | 规则 | 方向 | 在哪拦 |
|---|---|---|---|
| G1 行 | lcov 未命中行 ⊆ 白名单（现 4 行，每行有理由）；白名单里已被测到的行报 `stale`，白名单也只减不增 | 代码 → 测试 | `gates` |
| G2 API | 台账里每个行为型 API（参数/字段/方法/getter/setter/枚举值）至少属于一行；声明型（class/typedef/enum 容器）有触达证据即可；枚举值与布尔开关两头都有行 | 台账 → 矩阵 | 默认 `dart test` |
| G3 单测 | 每个 ①② 行至少有 1 条单测 | 矩阵 → 单测 | 默认 `dart test` |
| G4 真实 | 每个 ②③ 行至少有 1 个真实用例，最近结论 PASS 或带原因的 BLOCKED；所依赖的假设不得"已证伪" | 矩阵 → 真实 | `gates` |
| G5 反查 | 每条单测标题 id、每个 accept 场景、每个 pairwise 格都能归到某行；内部模块 id（`[ReplayClient.x]` 等）由源码符号认可 | 测试 → 矩阵 | 默认 `dart test`（单测侧）+ `gates`（真实侧） |

- 闸门逻辑在 `test/accept/lib/matrix.dart`，命令行入口 `dart run test/accept/bin/matrix.dart`：`sync` 补齐矩阵草稿，`gates` 跑 G1–G5 出缺口报告，`evidence` 生成入库证据汇总，`results` 按汇总回填每行结论。原 `audit.dart` 管 testkit 结果汇总，不混用。
- 静态闸门（G2、G3、G5 单测侧）写成 `test/integration/matrix_integration_test.dart`，默认运行即拦截。
- 需要产物的闸门（G1 要 lcov，G4、G5 真实侧要验收证据）只在 `gates` 命令里查。
- **基线棘轮**：已知缺口记在 `test/accept/lib/matrix-baseline.json`。闸门只拦基线之外的新缺口；基线里的缺口修好了却没删，也报错。基线只减不增（扩大须显式 `--allow-grow`：P1 定档拆行、外部 testkit 新增场景各用过一次），P2 结束时清空。
- G1 白名单按"文件 + 源码行文本 + 理由"记录，不记行号，代码挪动不失效。

## 6. 全量组合测试的定位

| 测试 | 档位 | 作用 |
|---|---|---|
| 本地 powerset（32767 成功路径 + 4095 异常路径） | ① | 穷举组合，确定性 |
| 真实 pairwise（64 格） | ② | 核对"组合结论在真实传输下仍成立"，是 powerset 的代表路径核对；**保留** |
| 全量冒烟（17 插件 × 网络 × 风格） | ②③ | 弱网、抖动下整链行为 |

## 7. 证据

- 原始日志、结果 JSON 继续 gitignore（`test/accept/*.log`、`test/accept/results/`、`coverage/`）。
- 每轮跑完提交一份小汇总：`dart run test/accept/bin/matrix.dart evidence <报告…>` 生成 `test/accept/evidence/<日期>-summary.json`（后传入的报告按格覆盖先传入的），再 `results` 回填矩阵。
- 汇总里"场景未声明此网络/风格"的跳过记为**不适用**，不计入结论；其余跳过（如 429/503 策略）计为 BLOCKED。
- 汇总同时带 API 触达清单，G2 声明型检查优先读它，干净检出也能得到一致结果。
- 现有文档里指向 `test/accept/results/…` 的链接统一改指汇总文件。

## 8. 分阶段计划

| 阶段 | 动作 | 完成标准 |
|---|---|---|
| P0 搭账 ✅ | ① `test/accept/bin/matrix.dart`：从台账生成矩阵草稿、合并 Options 构造参数与字段；② G1–G5 与缺口报告；③ `matrix_integration_test.dart`；④ 审计现有标题 id | 工具可跑，第一份缺口报告落在 `docs/reports/` |
| P1 定档 ✅ | 逐行定 tier；核实 H1–H6 并补隐含假设，写 `test/ASSUMPTIONS.md`；五方法矩阵"待补"补成 BLOCKED + 原因；挂上 `real` 与 `result` | 矩阵每行有 tier；G2、G5 全绿 |
| P2 补测 | 先补单测（标题 id 校正 / 新增用例），再补 ② 真实核对与 ③ 真实用例；证伪的假设连同假实现一起改 | G1–G5 全绿 |
| P3 收口 | `docs/guides/test-layers.md` 加三档/总账/闸门；accept 文档改为视图并修失效链接；证据汇总入库 | 文档与工具一致，闸门进默认运行 |

## 9. 相关

- 分层与命名：[测试分层](../guides/test-layers.md)
- 迁移映射：[迁移映射](../archive/test-migration-2026-10-27.md)
- 验收执行器：[验收执行器手册](../guides/accept-runner.md)
- 指南原文：`C:\Users\jelon\Desktop\测试三档分类指南.md`（本机，未入库）
