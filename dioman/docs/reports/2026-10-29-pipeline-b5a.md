---
title: dioman 洋葱管线 B5a powerset、成对组合与全库覆盖率
status: active
updated: 2026-10-29
summary: 九插件 512 子集乘九流程、独立 baseline、78 对组合清单、27 文件全覆盖与七项 powerset 变异证据
---

## TL;DR

- 本批只补 B5a 测试与证据；没有删除旧文件、切换入口、转派、commit/push/切分支。保留会话开始前已有的 `docs/design/pipeline-implementation-plan.md` 修改。
- powerset 为 **512 × 9 = 4,608** 条不变量测试，另有九条 baseline 和三条元测试，共 **4,620** 条。最终独立运行器计时 4 秒，包含启动开销的墙钟 **7.3630882 秒**，低于两分钟。
- 实际源码是 **13 个插件 = 12 个中间件 + setup-only envs**，因此全对表为 78 对：九个交互插件的 36 对由 powerset 覆盖，新增请求整形用例覆盖其余 42 对。按只数中间件的口径则为 66 对；另外 12 对属于 envs。
- 磁盘全部 **27 文件**逐一对账，24 个可执行文件行/分支均 100%；其余三项纯声明明确列出无分母。未加忽略注释、未新增依赖、未修改库实现。
- 七项变异只跑 powerset，全部产生运行期断言失败；每项 finally 恢复原字节，前后 SHA256 一致。

## 文件清单

| 文件 | 内容 |
|---|---|
| `test/combo/powerset_combo_test.dart` | 512 子集 × 九流程、九 baseline、三元测试 |
| `test/support/pipeline/b5_powerset.dart` | 工厂表、独占夹具、假时间驱动、离开时订阅快照、cache/share 内部诊断 |
| `test/combo/prepare_pairs_combo_test.dart` | repath/filter/timeout/envs 与其它插件共 42 对，实际发送配置断言 |
| `tool/pipeline_b5a_coverage.py` | 从磁盘枚举全部新库文件、复算 DA/BRDA、拒绝漏计文件 |
| `tool/pipeline_b5a_mutations.py` | 七项 powerset-only 变异，JSON 事件统计失败条数、逐项恢复哈希 |
| `docs/reports/2026-10-29-pipeline-b5a.md` | 本报告 |
| `docs/reports/pipeline-b5a-evidence/` | 原始命令输出、LCOV、计数、完整组合表、变异 JSON 事件与哈希、审查与范围核对 |

## powerset 与 baseline

九个交互插件按 `interactionNames` 与工厂表生成，每次运行重新创建插件配置、实例、网络、时钟、凭证及广播流。九者均可独立安装，不存在必须先安装其它插件的真实依赖；枚举支持依赖约束，合成表要求第二项依赖第一项，证实掩码 2 不生成。元测试另验证子集互异、包含空/全集、恰好 512。

| 流程 | 不装插件时逐请求 kind |
|---|---|
| 成功并再请求一次 | ok, ok |
| HTTP 500 | http |
| 500 两次后成功 | http |
| business 401：三个并发、两个同 key | biz, biz, biz |
| 网络错误 | network |
| 并发同 key | ok, ok |
| 中途 cancelAll | cancel, cancel |
| 首发取消，跟随者继续 | cancel, ok |
| 离线后恢复 | ok, ok |

baseline 单独核对类别；powerset 正文仅发请求、取消、改变连接状态与推进假时钟，统一收尾调用 `InvariantHarness.assertAll()` 检查 I1–I7。不在 powerset 中按插件组合硬编码返回类别。breaker 阈值 2 会在连续失败时打开，因此 flaky 流程在装 breaker 时可能被熔断，这不改变该层只检查不变量的职责。

mock 探测固定 404 后回落，不消费真实接口失败序号；auth 的 onRefresh 经 refreshInRound 包装，开始轮次先登记零，以便零次或多次刷新均失败。刷新也用假时钟阻塞，保证并发窗口可见。retry max=2、delay=0；请求使用 GET 携带嵌套 Map/List，B3Transformer 原地修改内层 n，以线上编码快照检查 I7，且 retry/mock 各有独立变异证据。

I3 除最终 pending/取消订阅/计时器归零，还保存每个调用方刚离开时的订阅数，抓住最终 state.dispose 清表前的首发监听泄漏。cache 的 pendingWrites/entryCount 与 share 的 activeEntries 读取实际内部诊断；请求收尾后先检查屏障/活动表，cache.clear 后与 api.dispose 后再检查为空。

假传输只使用每次 10ms 的 FakeClock gate；没有真实网络或定时 sleep。事件轮用于排空 Dio 的异步转换与 auth 的强制异步入口，有限 100 轮排空预算防止挂起。

## 成对组合补齐

整形用例故意反向安装两插件，按最终线上配置检查固定阶段顺序：repath 消费 id、filter 清空值、timeout 写三项超时、envs 修改 baseUrl/头。mock 的 probe 和回落都检查；共享底层三超时为零是 B4 已裁决的行为。首轮三条 mock 整形夹具误把未编码花括号作为探测路由，修正为 URI 编码路径；原始失败输出保留在 initial-pairs.txt，没有修改 mock 实现。

以下逐对给出实际生成的用例，完整副本见 [pairs.md](pipeline-b5a-evidence/pairs.md)。

| 插件对 | 覆盖用例 | 范围 / 无时序交互理由 |
|---|---|---|
| loading + notify | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=3` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + retry | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=5` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + breaker | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=9` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + auth | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=17` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + mock | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=33` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=65` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=129` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=257` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] loading+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| loading + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] loading+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| loading + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] loading+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| loading + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] loading+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| notify + retry | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=6` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + breaker | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=10` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + auth | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=18` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + mock | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=34` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=66` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=130` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=258` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] notify+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| notify + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] notify+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| notify + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] notify+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| notify + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] notify+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| retry + breaker | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=12` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + auth | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=20` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + mock | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=36` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=68` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=132` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=260` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] retry+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| retry + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] retry+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| retry + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] retry+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| retry + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] retry+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| breaker + auth | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=24` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| breaker + mock | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=40` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| breaker + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=72` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| breaker + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=136` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| breaker + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=264` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| breaker + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] breaker+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| breaker + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] breaker+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| breaker + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] breaker+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| breaker + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] breaker+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| auth + mock | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=48` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| auth + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=80` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| auth + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=144` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| auth + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=272` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| auth + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] auth+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| auth + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] auth+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| auth + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] auth+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| auth + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] auth+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| mock + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=96` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| mock + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=160` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| mock + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=288` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| mock + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] mock+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| mock + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] mock+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| mock + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] mock+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| mock + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] mock+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| share + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=192` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| share + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=320` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| share + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] share+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| share + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] share+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| share + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] share+timeout 补丁穿透发送` | 遵从 B4：共享底层三超时清零；本用例核对底层值，订阅者独立超时另由 B4 回归覆盖 |
| share + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] share+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| cache + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=384` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| cache + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] cache+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| cache + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] cache+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| cache + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] cache+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| cache + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] cache+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| offline + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] offline+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| offline + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] offline+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| offline + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] offline+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| offline + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] offline+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| repath + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] repath+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| repath + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] repath+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| repath + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] repath+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| filter + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] filter+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| filter + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] filter+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| timeout + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] timeout+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |

## 验收与覆盖率

覆盖率以 `dart test --coverage-path=docs/reports/pipeline-b5a-evidence/coverage.info --branch-coverage --reporter expanded` 生成；`python tool/pipeline_b5a_coverage.py` 从磁盘 rglob 全部源文件，拒绝重复 SF、缺文件、未命中 DA/BRDA，复算计数并与可用汇总核对。所有前批目标仍为 100%，本批同时确认 key/clock/plugin 等此前未列入分批门槛的文件也是 100%。

| 文件（相对 lib/src/pipeline/） | LF | LH | BRF | BRH |
|---|---:|---:|---:|---:|
| cache_store.dart | 0 | 0 | 0 | 0 |
| client.dart | 129 | 129 | 65 | 65 |
| clock.dart | 5 | 5 | 3 | 3 |
| config.dart | 36 | 36 | 22 | 22 |
| context.dart | 78 | 78 | 44 | 44 |
| key.dart | 54 | 54 | 27 | 27 |
| options.dart | 10 | 10 | 8 | 8 |
| pipeline.dart | 32 | 32 | 22 | 22 |
| plugin.dart | 5 | 5 | 5 | 5 |
| plugins/auth.dart | 122 | 122 | 59 | 59 |
| plugins/breaker.dart | 112 | 112 | 48 | 48 |
| plugins/cache.dart | 145 | 145 | 63 | 63 |
| plugins/envs.dart | 11 | 11 | 8 | 8 |
| plugins/filter.dart | 39 | 39 | 19 | 19 |
| plugins/loading.dart | 58 | 58 | 32 | 32 |
| plugins/mock.dart | 44 | 44 | 19 | 19 |
| plugins/notify.dart | 19 | 19 | 12 | 12 |
| plugins/offline.dart | 63 | 63 | 28 | 28 |
| plugins/repath.dart | 50 | 50 | 23 | 23 |
| plugins/retry.dart | 94 | 94 | 39 | 39 |
| plugins/share.dart | 101 | 101 | 49 | 49 |
| plugins/timeout.dart | 22 | 22 | 13 | 13 |
| request.dart | 50 | 50 | 25 | 25 |
| response.dart | 110 | 110 | 28 | 28 |
| stages.dart | 0 | 0 | 0 | 0 |
| token_manager.dart | 0 | 0 | 0 | 0 |
| transport.dart | 18 | 18 | 11 | 11 |

`cache_store.dart`、`token_manager.dart` 是纯抽象接口；`stages.dart` 只有枚举与 const 表，无可执行行/分支，运行器不生成 SF。三者逐一检查源文件存在与声明；0/0 不宣传成有执行分母的 100%。其余每文件均有非零计数。原始 [LCOV](pipeline-b5a-evidence/coverage.info)、[逐文件计数](pipeline-b5a-evidence/coverage.txt)、[JSON](pipeline-b5a-evidence/coverage.json)。

最终命令均等待到完成，完整输出保存在本目录证据文件：

```text
dart analyze
Analyzing dioman...
No issues found!
exit: 0

dart test test/combo/powerset_combo_test.dart --reporter expanded
00:04 +4620: All tests passed!
wall_seconds: 7.3630882
exit: 0

dart test --reporter expanded
00:07 +4928: All tests passed!
wall_seconds: 9.6023759
exit: 0

dart test test_legacy --concurrency=1 --reporter expanded
04:50 +580: All tests passed!
exit: 0

dart test --coverage-path=docs/reports/pipeline-b5a-evidence/coverage.info --branch-coverage --reporter expanded
00:08 +4928: All tests passed!
exit: 0

python tool/pipeline_b5a_coverage.py
27 source files accounted for; all executable lines/branches 100%; PASS
```

总数为原有 266 + powerset 4620 + 整形组合 42 = 4928。[analyze](pipeline-b5a-evidence/analyze.txt)、[powerset](pipeline-b5a-evidence/powerset.txt)、[test](pipeline-b5a-evidence/tests.txt)、[test_legacy](pipeline-b5a-evidence/legacy-tests.txt)、[coverage-test](pipeline-b5a-evidence/coverage-tests.txt)。墙钟计时包含 Dart 命令启动，运行器时间另列；两者均非估算。

## 变异价值证据

命令：`python tool/pipeline_b5a_mutations.py`。七项每次只改新库一处，唯一测试目标是 powerset 文件。按 JSON 的 testDone 失败事件统计，单列 4,608 条组合测试与九 baseline 的失败数；不把同一用例多个断言或 error 事件重复计为多个失败测试。拒绝编译/加载失败与超时作为击中。

| 变异 | powerset 失败条数 | baseline 额外失败 | SHA256 恢复 |
|---|---:|---:|---|
| leave-listener | 256 | 0 | 一致 |
| loading-close | 2304 | 0 | 一致 |
| notify-double | 832 | 0 | 一致 |
| auth-singleflight | 256 | 0 | 一致 |
| retry-replayable | 192 | 0 | 一致 |
| cache-barrier | 2176 | 0 | 一致 |
| mock-replayable | 512 | 0 | 一致 |

leave-listener 删除 ctx.wait 离开时摘监听；loading-close 丢 false 通知；notify-double 对同一逻辑请求通知两次；auth-singleflight 取消刷新合并；retry-replayable 与 mock-replayable 分别撤掉 markReplayable；cache-barrier 不回收 finally 屏障。逐项修改前/恢复后 SHA256、退出与计数见 [mutations.json](pipeline-b5a-evidence/mutations.json)，完整事件在同目录 `mutation-*.jsonl`；[摘要](pipeline-b5a-evidence/mutation-summary.txt)。

## 终审修复

未发现新库真实缺陷，没有修改任何库文件；本批修正限测试夹具与覆盖率验收脚本（自审 P2 的修复及反向证据见下一节）。全部 27 个新库源码与 HEAD 对照一致，七项变异的原字节恢复哈希也与最终源码一致；见 [范围和恢复](pipeline-b5a-evidence/scope-and-restore.txt) 与 [源码哈希](pipeline-b5a-evidence/source-sha256.json)。

## codex review 发现与处理

已运行并等待 `codex review --uncommitted` 正常结束（exit 0），完整原文见 [codex-review.txt](pipeline-b5a-evidence/codex-review.txt)。自审本地额外运行了全部 4662 条新增 Dart 测试并通过，提出 **1 项成立的 P2**：覆盖率 verifier 会把缺少 BRDA 的输入当作分支全覆盖。

修复：对每个可执行文件要求 DA 与 BRDA 都非空，再复算 100%；纯声明三文件仍明确无执行分母。用原始 LCOV 剥除 BRDA/BRF/BRH 制成 [反例](pipeline-b5a-evidence/coverage-without-branches.info)，[修复前](pipeline-b5a-evidence/review-verifier-before.txt) 错误 PASS，[修复后](pipeline-b5a-evidence/review-verifier-after.txt) 明确因 missing line/branch instrumentation 非零退出，[撤掉修复](pipeline-b5a-evidence/review-verifier-reverse.txt) 再次错误 PASS；随后恢复 verifier 原字节，并用真实分支覆盖证据复验通过。该问题在验收工具，未涉及库源码。

## 共存与范围

未修改旧 lib、test_legacy、入口、pubspec/lock；不删除旧文件，B5b 才处理删除与切换。实际 SDK Dart 3.13.0，声明仍为 ^3.5.0，没有使用高于约束的语言特性，没有声称实测 Dart 3.5。axp 仅作只读参考。无 tool/__pycache__。

最终 `git status --short`（首项为进入会话前已有修改）：

```text
 M docs/design/pipeline-implementation-plan.md
?? docs/reports/2026-10-29-pipeline-b5a.md
?? docs/reports/pipeline-b5a-evidence/
?? test/combo/powerset_combo_test.dart
?? test/combo/prepare_pairs_combo_test.dart
?? test/support/pipeline/b5_powerset.dart
?? tool/pipeline_b5a_coverage.py
?? tool/pipeline_b5a_mutations.py
```

`git log --oneline -1`：

```text
a3c73b8 refactor(dioman): B4 结果来源 mock/share/cache/offline
```

没有新增提交或修改分支，未发现误提交。
