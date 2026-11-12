---
title: dioman 第二轮终验与发版前总检
status: active
updated: 2026-11-03
summary: 5708 项测试与全覆盖、112 项变异、6426 格终验零失败，执行器映射修正与发版遗留。
---

## TL;DR

功能终验通过：普通与覆盖测试各 **5708 项通过**，库行 **1698/1698**、分支 **806/806**，**112/112 项变异有效击中**。最终真实矩阵 **6426/6426 已分类，1306 通过、252 缺能力、4868 不适用、0 失败**；方法矩阵 **156/156，138 通过、18 跳过、0 失败**。最终报告均 interrupted=false。

发现并修复一项执行器超时映射问题，另为小文件证据补充 gzip 摘要读写；新增四项单测，原有 5704 项保留。全部 **37 个 lib 文件原字节 SHA256 与 R6b 一致**，没有保留库代码修改。5708 项包含 5120 项 powerset 及既有不变量检查。

闸门退出 0，G0/G1/G2/G3/G5=0，G4 仍为既有 connect 握手超时一项。pana 终验后复跑 **160/160**（含 web、wasm-ready）；`dio` 下限已抬到 `^5.4.0`，降级分析仅余 1 条 warning、无 error。docs-index 已在主会话收录本报告并通过。

全程自行执行，没有转派或启动审查代理；未执行 git add/commit/push、切分支、stash 或整仓库 checkout。HEAD 保持 `fa04fe1a877b2f279f19d19c0ff88b6858416c06`，分支为 `jelon/dioman-round2`。未修改设计文档、0002 或 docs/README.md。

## 本地全检结果

以下采用执行器修正和 gzip 单测落地后的最后一轮结果，全部测试命令显式使用 `--concurrency=1`，与真实验收、变异及 pana 串行错开。

| 检查 | 最终结果 |
|---|---|
| `dart analyze` | 退出 0，0 issue |
| `dart analyze example` | 退出 0，0 issue |
| `dart test --concurrency=1 --reporter=expanded` | 退出 0，5708 项通过 |
| `dart test --concurrency=1 --coverage-path=coverage/round2-final/final.info --branch-coverage --reporter=expanded` | 退出 0，5708 项通过 |
| `python tool/pipeline_b5a_coverage.py coverage/round2-final/final.info --out coverage/round2-final/final-audit` | 退出 0；36 个 lib/src 文件逐一核算，1698/1698 行、806/806 分支 |
| 四份文档 Dart 示例 | 68 个编译单元通过；25 个既有 docs:old 块保持原登记 |
| docs-index，报告生成前 | 退出 0 |
| docs-index，本报告生成后 | 退出 1；唯一问题为 `reports/2026-11-03-round2-final.md` 未收录 |
| `git diff --check -- .` | 退出 0 |

覆盖审计按项目 SKILL 的脚本执行；纯声明文件和 `lib/dioman.dart` 导出入口没有可执行分母。两个条件导入实现均纳入核算，没有新增忽略或白名单。[逐文件覆盖](round2-final-evidence/coverage.json)、[本地检查](round2-final-evidence/local-checks.json)、[库源码 SHA256](round2-final-evidence/lib-sha256.json)、[示例编译统计](round2-final-evidence/documentation-examples.json)。完整日志和 LCOV 仅在 coverage/round2-final/。

### 变异

| 脚本 | 有效击中/应执行 |
|---|---:|
| pipeline_b1_mutations.py | 10/10 |
| pipeline_b2_mutations.py | 9/9 |
| pipeline_b3_mutations.py | 18/18 |
| pipeline_b4_mutations.py | 19/19 |
| pipeline_b5a_mutations.py | 7/7 |
| pipeline_b8_mutations.py | 6/6 |
| round2_r1_mutations.py | 4/4 |
| round2_r2a_mutations.py | 8/8 |
| round2_r2b_mutations.py | 10/10 |
| round2_r3_mutations.py | 15/15 |
| round2_r4_mutations.py | 3/3 |
| round2_r6b_mutations.py | 3/3 |
| 合计 | **112/112** |

B8 首项已改为 `ctx.fail(DiomanFailureKind.cancel)`，实际产生一项测试断言失败。B1/B2/B3/B4/R2a 中过期的失败类型、状态、原生槽和缓存快照锚点同步到现有实现，所有变异名称与意图保留。B3/B4 不再只核对路径，全部实际执行。

原 B3 等待取消、B4 FIFO 淘汰及卸载后晚到请求的用例，在相应变异下会一直 await 到测试超时。为取得有效断言失败，补强三个既有边界用例：先观察取消是否已经落定、最早请求是否已被淘汰、卸载实例的队列是否仍为空，再等待结果；保留原有结果、资源及迟到异常断言。B3 通知等待变异改为目标用例实际经过的无凭证通知分支。没有把超时当作击中。

B5a 一次运行触发 120 秒进程看门狗，源码 finally 恢复，未计作击中；看门狗改为 600 秒后完成验证，**单用例 10 秒超时未变**。七项 powerset 实际失败数依次为 256、2560、1024、256、192、2432、512。旧 B8 缺少新输出目录创建的问题也已修复。输出统一进入 coverage，未覆盖历史报告证据。

每项均检查恢复 SHA256；每组额外核对全部 lib。编译失败、加载失败、空跑与超时均不计入上述 112 项。执行器修正后又重验了 R2a 的执行器分类变异。[变异总表](round2-final-evidence/mutations.json)与同目录各批 `*-mutations.json` 保留逐项恢复哈希；完整失败输出仅在 coverage/round2-final/mutations/。

## 全矩阵真实验收计数与通用断言

### 实例来源与复用

testkit 当前 main 为 `c3b8965f6257f2ea7c5a594c951c11a90fc0a9a2`，启动前与结束后均确认工作区干净。两次验收均先核对二进制 SHA256，直接复用 R6b release 产物，没有重复编译，也未修改 testkit 源码。

产物目录为用户指定的 `C:\Users\jelon\AppData\Local\Temp\claude\E--workspaces-dart-labs-dioman\8e9dd7c7-f80b-4489-8690-3147638feaf4\scratchpad\tk-target-r6\release`。

| 二进制 | SHA256 |
|---|---|
| api-ws-demo.exe | 93e266b640c296be224a85710c77f4245884be088fd06ab9fdd4efbf753849a7 |
| netem.exe | 84d55bfac0f84f91d734a0efc47702a4531282db055509920c466e15c15a0410 |

| 轮次 | 业务端口/PID | netem 端口/PID |
|---|---|---|
| 首轮 | 47480 / 42980 | 47490 / 35320 |
| 修正后终轮 | 47480 / 43764 | 47490 / 44096 |

未操作 47080/47090。全矩阵显式指定七网络 normal、weak、lossy、offline、blackhole、flap、dns，双风格 http/business，jobs=2；定点复验 jobs=1。

### 首轮失败与执行器修正

首轮完整 **6426/6426**，1304 通过、2 失败、5120 跳过，interrupted=false。两个失败格均为 `retry.hang-timeout-retried` 的 normal/http、normal/business：约 512ms 结束且服务端只收到一次请求，原预期为至少 900ms、两次发送。分别 jobs=1 重跑仍失败，约 517/520ms，排除偶发完成顺序波动的解释。

分类为**执行器映射缺陷**：该旧场景只声明 retry，使用每次传输的 500ms 接收超时验证超时重试；R6b 把请求 timeout_ms 无条件改为整体 deadline，使第一次超时即耗尽逻辑预算。现按通用配置区分：声明 timeout-total 或配置 total_ms 时，timeout_ms 映射请求 deadline；其余旧场景保留 receiveTimeout。没有按场景 ID 特判，没有补计时器、重试流程或结果重分类，没有修改 testkit、断言或 skip。

新增两项映射单测。修复前“不声明整体预算”的用例实际失败（期望 deadline=null，实际 500ms）；修复后执行器单测 16 项全绿。原有 total_ms 覆盖测试与新增“只声明 timeout-total”的用例共同保护原生预算映射。真实定点复验两格通过，服务端均收到两次请求，总耗时约 1229/1173ms；随后完整重跑，没有用定点绿灯替代全矩阵。

[两格逐项处置](round2-final-evidence/executor-fix.json)。首轮完整 JSON、独立复验及先红后绿输出保留在 coverage/round2-final/，没有覆盖首轮失败。

### 最终结果与 B8 逐类对账

终轮 **459 场景 × 七网络 × 双风格 = 6426 格**，planned=executed=6426，remaining=0，interrupted=false。这里 executed 包含跳过分类；真正发请求的通过格为 1306。

| 类别 | B8 | 本轮最终 | 增减 |
|---|---:|---:|---:|
| 通过 | 1280 | 1306 | +26 |
| 缺能力 | 420 | 252 | −168 |
| 不适用 | 4726 | 4868 | +142 |
| 失败 | 0 | 0 | 0 |
| 合计 | 6426 | 6426 | 0 |

168 格变化全部来自 R6b 放开的 timeout-total：26 个已声明适用格真实通过，142 格显露原有“网络或风格未声明”的不适用。12 个场景中 11 个只声明 normal，另一个声明 normal、weak，适用数为 `(11+2)×2=26`。不能将 168 格都算真实通过。

其余 6258 格的状态与原因均与 B8 相同。缺能力仅余 raw-business-code 252 格；不适用为未声明维度 4850、场景显式 skip 16、既有 offline 通知差异 2。**本轮新增不适用规则 0**；新增不适用格逐一对照原有场景 networks/styles，预期集合与实得集合完全相同，多跳 0、漏跳 0。不存在新规则上线前失败集合需要掩盖；首轮两个失败最终逐格转为通过。

[最终计数与来源 SHA256](round2-final-evidence/acceptance.json)、[168 格完整转移清单](round2-final-evidence/transitions.json)。跳过项没有计入通过。

### 通用断言与清理

终轮全矩阵 1306 条和方法矩阵 138 条，共 **1444 条实执行记录**逐条审计：pending_after=0、active_cancel_tokens=0、server.inflight=0；loading 严格按 true/false 交替成对，出现显示时最后为 false，未显示时为空。加上首轮 1306 条、两次失败复验和两格修正后复验，合计 **2754 条记录**的上述通用断言违例均为 0。

首轮 1230 个、终轮含定点及方法矩阵 1368 个，共 **2598 个代理**均有创建/删除记录，逐一 GET stats 为 404。四个本轮进程句柄均已退出，47480/47490 不再监听；只清理本轮记录了 id 的代理及自己启动的进程。[实例、监听归属与清理](round2-final-evidence/runtime.json)；完整代理核验在 coverage/round2-final/proxy-checks.json 及 pre-mapping-proxy-checks.json。

## 插件方法矩阵

`dart run test/accept/bin/run_plugin_matrix.dart` 退出 0，planned=executed=156，interrupted=false，与 B8 计数一致。

| 方法 | 通过 | 缺能力 | 不适用 | 失败 |
|---|---:|---:|---:|---:|
| 单体 | 18 | 16 | 0 | 0 |
| 真实 pairwise | 64 | 0 | 0 | 0 |
| 边界 | 52 | 0 | 0 | 0 |
| 全量流程 | 4 | 0 | 2 | 0 |
| 合计 | **138** | **16** | **2** | **0** |

独立 API 探针实际触达 64 项，退出 0。旧 R6b 摘要仍有已经删除的 `DiomanResponse.kind/reason/httpStatus/errorStack` 四个名字；本次没有继承历史触达，摘要仅保留本轮实际记录的 64 项。

## 证据回填与闸门输出

执行 `matrix.dart evidence` 汇总终轮全量与方法报告，459 个场景、64 项实际 API 触达；`results` 回填 **112 行：111 PASS、1 BLOCKED**。

完整汇总未删格，原始展开约 244KB。为满足证据单文件限制，矩阵工具新增透明 gzip JSON 读写和最新摘要发现，补充两项单测；普通 JSON 保持兼容。默认 results/gates 直接读取本次 [压缩摘要](../../test/accept/evidence/2026-11-03-round2-final-summary.json.gz)，大小 **6835 字节**。[归档清单](round2-final-evidence/matrix-evidence.json)记录展开与压缩 SHA256、实际触达来源及被排除的四个历史名字，同目录保存字节相同的归档副本。

最后使用本次 `coverage/round2-final/final.info` 执行 gates，退出码 **0**，没有更新或扩大基线：

```text
G0: 0
G1: 0
G2: 0
G3: 0
G4: 1
  G4:DiomanTimeouts.connect#effective:no-real
G5: 0
```

[原始闸门输出](round2-final-evidence/gates.txt)、[命令与退出码](round2-final-evidence/matrix-commands.json)。G4 仍为原有握手超时环境缺口，未填成 PASS。

## pana 结论

终验批次实测 pana 0.23.16：平台 20/20、静态分析 50/50、文档 20/20，当时总分 140/160（依赖下限降级分析有 20 个 error）。主会话随后处理，见下节。

**主会话跟进（已闭环）**：确认 `dio` 5.2/5.3 仍有 5 个 error、5.4.0 起 lib 无 error，故把下限由 `^5.0.0` 抬到 `^5.4.0`（提交 `50974903`，只改约束）。降级到最低版本后分析只剩 `response.dart` 一条 `unreachable_switch_default` warning（`default` 为新版 dio 枚举值预留，保留）。复跑 pana（锁文件为最新依赖）**160/160**，平台、静态分析、文档、依赖四项均满分；完整测试 5708 项再次全过。注意：降级验证后须 `dart pub upgrade` 还原 pubspec.lock，否则 pana 会按旧锁打出 130 分。

Windows dart.BAT 输出的前导换页符导致本地封装一次 JSON 解析失败；原始 pana 进程退出码已单独保存为 0，随后只剥除前导控制空白解析同一份原始 JSON，没有重跑取优或改写 pana 结论。[平台、评分与扣分摘要](round2-final-evidence/pana.json)，完整 JSON、日志在 coverage/round2-final/pana.json、pana.log。

## 性能抽查

性能门槛未判定，已暂缓；数据见 R4、R4b 报告；稳定性口径（极差 <10% 在干净数据下也达不到）留待恢复性能工作时裁决

## 文档一致性修正

通读 CHANGELOG Unreleased、两份 README 和迁移指南，核对 C19–C32、R5 与 R6b 的最终行为及 Breaking 标注。只修正事实，没有新增章节或示例：

- CHANGELOG：旧顶层 kind/reason 改为 failureOf；auth/retry/breaker 的有效状态与 HTTP status、业务 code 区分清楚，cache 按 ok。
- 两份 README：Auth 已有参数清单补齐 refreshTimeout，章节和行为保持对应。
- 迁移指南：loading 改为回调相等共享；auth 改为同 TokenManager 跨客户端单飞；修正业务状态说明、已删除的失败构造器和顶层 reason 写法。
- testkit-mapping：修正已过期的响应字段、timeout-total 能力和原生预算映射，说明旧场景的每次接收超时与整体预算的区分。

四份示例文档仍为 README 19+19、迁移指南 23、CHANGELOG 7，共 68 个编译单元；历史块 25 个未变。docs/README.md、设计文档与 0002 保持不动。

报告落地后确实再次执行 docs-index，退出 1，唯一问题为本报告未收录。任务明确禁止修改索引，本批保留该问题；没有改检查器或豁免规则。[文档索引最终结果](round2-final-evidence/docs-index.json)。

## 遗留与已知限制

- connect 握手超时仍缺可控真实环境；用户态代理接受连接后的黑洞不能代替丢 SYN。
- raw-business-code 仍不支持，252 格缺能力；timeout-total 另有 142 个未声明适用维度，不推断未定义预期。
- 既有 offline 通知计数差异两格继续不适用，没有新增跳过规则。
- R3 仅完成原生槽与结果瘦身第一步，完整 request 仍可保留请求体和凭证；本轮未扩大此承诺。
- 依赖下限缺陷已修复（`dio ^5.4.0`，pana 160/160）；索引缺口已补。

所有本轮入库证据单文件均小于 50KB，完整测试、变异、验收和工具日志仅保留 coverage。工作区最终状态见 [status.txt](round2-final-evidence/status.txt)。

## 需主会话裁决的问题

1. ~~库兼容缺陷：依赖下限~~ 已处理：下限抬到 `^5.4.0`，见 pana 结论。
2. **索引维护。** 主会话需在允许修改索引的批次收录本报告，解决当前唯一 docs-index 问题。
3. **既有环境与场景口径。** connect 握手环境缺口和 offline 通知两格仍需后续处理，未以本次绿灯消除。
4. **testkit 超时字段的兼容口径。** 本次按 requires/total_ms 通用映射恢复旧 retry 场景，同时保留 R6b 原生整体预算，已完成单测和全矩阵实证；建议主会话后续维护中立契约时明确这两种 timeout_ms 使用范围。本批未修改 testkit 定义或场景。

未发现需要修改库实现的新增运行时缺陷；上述依赖兼容缺陷与未完成的外部口径不能写成已解决。
