---
title: 17 插件五方法真实矩阵（2026-10-27）
status: active
updated: 2026-10-28
summary: 单体/全量/边界/配对/规则五种方法在真实服务上的格子数与结论。
---
# 17 插件五方法矩阵（中文复核）

2026-10-27 测试整理：当前生成清单为 77 场景 / 156 格，真实执行 156 通过、0 失败。两组等价零值边界合并后比原清单少 4 格；按旧→新 id 逐项对比，无缺失、无状态变化。新证据见 `coverage/accept/plugin-matrix-final.json`（本地产物，不入库），迁移说明见 [测试分层](../guides/test-layers.md)。

以下统计、run id 和证据链接保留整理前历史轮次（79 场景 / 160 格）；场景列中的已合并 id 已映射到当前保留 id，不代表这些历史轮次重新运行。

状态：**部分完成，整项验收未完成**。本轮已定义方法场景 79 个、真实格子 160 个，最终全部通过；不把未实现的选项或历史缺声明项统计为通过/不适用。

运行：`dart run test/accept/bin/build_plugin_matrix.dart` → testkit `gen-index`/`validate --check-index` → `dart run test/accept/bin/run_plugin_matrix.dart`。复用47080/47090，每格唯一 X-Test-Run、独立代理；真实日志、事件、服务端统计、规则断言在 `../results/plugin-matrix-final.json`，逐条日志在同名 `.ndjson`。

格子计数为“已定义 / 已执行 / 不适用”，仅表示当前已实现清单，不代表穷尽所有公开选项。配对的关闭状态也属于对应插件的一格；规则复用全量流程6个 run id，不额外虚构HTTP请求。

| 插件 | 单体 | 全量 | 边界 | 配对 | 规则 |
|---|---:|---:|---:|---:|---:|
| auth | 2/2/0（待补） | 6/6/0 | 0/0/0（待补） | 64/64/0 | 6/6/0（待补） |
| breaker | 2/2/0（待补） | 6/6/0 | 10/10/0（待补） | 64/64/0 | 6/6/0（待补） |
| cache | 2/2/0（待补） | 6/6/0 | 16/16/0（待补） | 64/64/0 | 6/6/0（待补） |
| cancel | 2/2/0（待补） | 6/6/0 | 1/0/1 | 64/64/0 | 6/6/0（待补） |
| envs | 2/2/0（待补） | 6/6/0 | 0/0/0（待补） | 64/64/0 | 6/6/0（待补） |
| filter | 2/2/0（待补） | 6/6/0 | 0/0/0（待补） | 64/64/0 | 6/6/0（待补） |
| key | 2/2/0（待补） | 6/6/0 | 0/0/0（待补） | 64/64/0 | 6/6/0（待补） |
| loading | 2/2/0（待补） | 6/6/0 | 8/8/0（待补） | 64/64/0 | 6/6/0（待补） |
| log | 2/2/0（待补） | 6/6/0 | 0/0/0（待补） | 64/64/0 | 6/6/0（待补） |
| mock | 2/2/0（待补） | 6/6/0 | 0/0/0（待补） | 64/64/0 | 6/6/0（待补） |
| normalize | 2/2/0（待补） | 6/6/0 | 1/0/1 | 64/64/0 | 6/6/0（待补） |
| notify | 2/2/0（待补） | 6/6/0 | 1/0/1 | 64/64/0 | 6/6/0（待补） |
| offline | 2/2/0（待补） | 6/6/0 | 0/0/0（待补） | 64/64/0 | 6/6/0（待补） |
| repath | 2/2/0（待补） | 6/6/0 | 1/0/1 | 64/64/0 | 6/6/0（待补） |
| retry | 2/2/0（待补） | 6/6/0 | 14/14/0（待补） | 64/64/0 | 6/6/0（待补） |
| share | 2/2/0（待补） | 6/6/0 | 0/0/0（待补） | 64/64/0 | 6/6/0（待补） |
| timeout | 2/2/0（待补） | 6/6/0 | 8/8/0（待补） | 64/64/0 | 6/6/0（待补） |

## 方法范围与证据

- 单体：17×2风格=34格。每个插件单独安装，检查成功负载、500风格差异和主动取消；**未完成全部选项/触发路径**。
- 全量：17插件同开，normal/weak/flap×http/business=6格。登录、访问、过期刷新、500恢复、缓存命中、share并发、取消、loading成对、notify一次均有断言；flap先经历offline拒绝再等待恢复。
- 边界：28场景×2=56格。目前只有retry、cache、loading、timeout、breaker的部分参数；小连接预算1ms仅验证实际能建立本地TCP，不把服务端处理延迟误称连接超时。
- 配对：32×17二元正交数组，32行×两风格=64格。每对00/01/10/11均由独立单测枚举校验，覆盖136×4=544种二元状态；真实回显核对payload、服务命中与资源释放。全关行是必要基线。
- 规则：`test/accept/lib/plugin_rules.dart`逐条验证排序边反转应报misordered、重复名应报duplicateName、extra唯一/归属/前缀、正常安装无状态键冲突；每个实际请求还检查pending/loading/inflight。缺依赖/环/动态插入见`test/unit/plugin_order_test.dart`，但没有将所有源码不变量逐条列成完整真实矩阵。

先搜索了现有依赖与测试，没有引入pairwise库；最小构造依据[ NIST covering arrays](https://math.nist.gov/coveringarrays/coveringarray.html)。旧136精确双开集合在N≥4时可组合出现每对00/01/10/11，但旧报告只运行http，而且是基础成功流；因此不能代替本轮双风格配对证据。

## 边界不适用与待补

- cancel：不适用——仅 enabled 布尔选项，没有数值、时间或集合选项；取消集合为运行状态，非公开配置。
- notify：不适用——两个回调选项，没有数值、时间或集合选项。
- normalize：不适用——布尔、字符串字段名和回调选项，没有数值、时间或集合选项。
- repath：不适用——布尔和 RegExp 选项，没有数值、时间或集合选项；自定义正则另由单测覆盖。
- auth：待补——refreshLeeway、expiresAt/now 的临界时间及请求级覆盖尚缺真实服务边界。
- envs：待补——rules 空/单条/多条首命中集合边界尚未形成独立真实用例。
- filter：待补——ignoreKeys/ignoreValues 空/单元素/叠加集合尚缺真实服务独立边界。
- key：待补——ignores 空/单元素/超大集合尚缺真实服务边界。
- log：待补——maxBodyLength 的 -1/0/1/大值及请求覆盖尚缺真实服务边界。
- mock：待补——routes 空/单条/优先级、路径集合尚缺真实服务边界。
- offline：待补——maxQueueSize、maxWait 和请求级覆盖尚缺真实队列边界。
- share：待补——retries、interval 及 start/end/race/retry 的边界尚缺完整真实证据。
- retry：待补——已定义 max/delay/methods；statusCodes/afterStatusCodes 集合、delayMax/retryAfterMax/jitter 的全部边界仍缺真实证据。
- cache：待补——已定义 TTL/capacity/methods；持久化与克隆策略交叉边界、负数和请求级覆盖尚未穷尽。
- loading：待补——已定义 0/1ms；极大值、负数和请求级覆盖尚未穷尽。
- timeout：待补——已定义 connect/receive 1ms/大值；send、0、负数、各 NetworkQuality 档位尚未穷尽。
- breaker：待补——已定义 threshold/open_ms；halfOpenMaxCalls、idleTtl、maxBuckets、时钟边界仍缺真实证据。

## 第一阶段结论

历史3547跳过 = 3477纯缺声明 + 56缺声明且注入禁用状态 + 14已声明注入禁用状态；历史缺声明维度是3533。5个注入场景现已对全部7网络写expect.skip，共70格有明确停机约束理由，其中56格补齐了原来缺失的声明。其余3477格仍待设计预期并真实执行，不能称为合法不适用。另拆两个安全子场景8格真实通过，不称替代原429/503测试。完整逐项清单见`../results/skip-review.json`。
本轮库级lcov：1788/1793，99.7211%；逐行缺口见下节。历史基线1683/1793；key删除两个计数行、share修复新增两个计数行，分母恰好相同但行集合已经变化。原110行逐项处置见`COVERAGE-review.md`；兜底分支的Dio源码契约摘录见`../results/coverage-invariants.json`。
七文件diff逐项自审见[源码复核](2026-10-27-library-review.md)，diff保存`../results/review-library.diff`。本轮确认并修复share重放准备异常只结束首发、悬挂跟随者的缺陷；修复前回归明确失败，修复后真实http/business各通过一次，证据见`../results/share-prepare-real.json`。另修正README和breaker类注释的计数说明。公开API探针本轮重新执行691/691，仍不是参数值/路径穷举。

## 本轮未覆盖行（不冒充已覆盖）

| 文件:行 | 代码 | 解释 |
|---|---|---|
| lib\src\auth_plugin.dart:777 | `error: DioException(requestOptions: opts, error: e, stackTrace: s),` | 非 DioException 异常兜底：当前 ReplayClient.fetch 返回 Dio.fetch，Dio 将传输/转换异常包装为 DioException；标准传输路径不能进入该转换。保留防御分支，未删除。 |
| lib\src\share_plugin.dart:485 | `: DioException(requestOptions: opts, error: lastError);` | 非 DioException 异常兜底：当前 ReplayClient.fetch 返回 Dio.fetch，Dio 将传输/转换异常包装为 DioException；标准传输路径不能进入该转换。保留防御分支，未删除。 |
| lib\src\share_plugin.dart:593 | `.completeError(DioException(requestOptions: options, error: error));` | 非 DioException 异常兜底：当前 ReplayClient.fetch 返回 Dio.fetch，Dio 将传输/转换异常包装为 DioException；标准传输路径不能进入该转换。保留防御分支，未删除。 |
| lib\src\retry_plugin.dart:720 | `DioException.requestCancelled(` | 取消错误兜底：唯一调用点先确认 token.isCancelled == true；Dio CancelToken 的该状态由非空 cancelError 定义，故 ?? 右支在此调用链不可达。 |
| lib\src\replay_support.dart:102 | `: _asDio(data ?? e, current.requestOptions, StackTrace.current),` | 非 DioException 的 handler 错误 data 兜底：Dio 的 ResponseInterceptorHandler.reject 参数类型为 DioException；同步/异步抛出已在此前转换。标准 handler 契约下不可达。 |

## 每格真实执行索引

每行run id对应一格。单体/边界归属所列插件；全量归属17插件；配对包含全部17开关（实际开启集合另见JSON计划）。规则列使用下列全量run id。

| 方法 | 场景 | 网络/风格 | run id | 结果 |
|---|---|---|---|---|
| 单体 | plugins.single-auth | normal / http | `dioman-methods-1793104467521921-23456-0` | 通过 |
| 单体 | plugins.single-auth | normal / business | `dioman-methods-1793104467521921-23456-1` | 通过 |
| 单体 | plugins.single-breaker | normal / http | `dioman-methods-1793104467521921-23456-2` | 通过 |
| 单体 | plugins.single-breaker | normal / business | `dioman-methods-1793104467521921-23456-3` | 通过 |
| 单体 | plugins.single-cache | normal / http | `dioman-methods-1793104467521921-23456-4` | 通过 |
| 单体 | plugins.single-cache | normal / business | `dioman-methods-1793104467521921-23456-5` | 通过 |
| 单体 | plugins.single-cancel | normal / http | `dioman-methods-1793104467521921-23456-6` | 通过 |
| 单体 | plugins.single-cancel | normal / business | `dioman-methods-1793104467521921-23456-7` | 通过 |
| 单体 | plugins.single-envs | normal / http | `dioman-methods-1793104467521921-23456-8` | 通过 |
| 单体 | plugins.single-envs | normal / business | `dioman-methods-1793104467521921-23456-9` | 通过 |
| 单体 | plugins.single-filter | normal / http | `dioman-methods-1793104467521921-23456-10` | 通过 |
| 单体 | plugins.single-filter | normal / business | `dioman-methods-1793104467521921-23456-11` | 通过 |
| 单体 | plugins.single-key | normal / http | `dioman-methods-1793104467521921-23456-12` | 通过 |
| 单体 | plugins.single-key | normal / business | `dioman-methods-1793104467521921-23456-13` | 通过 |
| 单体 | plugins.single-loading | normal / http | `dioman-methods-1793104467521921-23456-14` | 通过 |
| 单体 | plugins.single-loading | normal / business | `dioman-methods-1793104467521921-23456-15` | 通过 |
| 单体 | plugins.single-log | normal / http | `dioman-methods-1793104467521921-23456-16` | 通过 |
| 单体 | plugins.single-log | normal / business | `dioman-methods-1793104467521921-23456-17` | 通过 |
| 单体 | plugins.single-mock | normal / http | `dioman-methods-1793104467521921-23456-18` | 通过 |
| 单体 | plugins.single-mock | normal / business | `dioman-methods-1793104467521921-23456-19` | 通过 |
| 单体 | plugins.single-normalize | normal / http | `dioman-methods-1793104467521921-23456-20` | 通过 |
| 单体 | plugins.single-normalize | normal / business | `dioman-methods-1793104467521921-23456-21` | 通过 |
| 单体 | plugins.single-notify | normal / http | `dioman-methods-1793104467521921-23456-22` | 通过 |
| 单体 | plugins.single-notify | normal / business | `dioman-methods-1793104467521921-23456-23` | 通过 |
| 单体 | plugins.single-offline | normal / http | `dioman-methods-1793104467521921-23456-24` | 通过 |
| 单体 | plugins.single-offline | normal / business | `dioman-methods-1793104467521921-23456-25` | 通过 |
| 单体 | plugins.single-repath | normal / http | `dioman-methods-1793104467521921-23456-26` | 通过 |
| 单体 | plugins.single-repath | normal / business | `dioman-methods-1793104467521921-23456-27` | 通过 |
| 单体 | plugins.single-retry | normal / http | `dioman-methods-1793104467521921-23456-28` | 通过 |
| 单体 | plugins.single-retry | normal / business | `dioman-methods-1793104467521921-23456-29` | 通过 |
| 单体 | plugins.single-share | normal / http | `dioman-methods-1793104467521921-23456-30` | 通过 |
| 单体 | plugins.single-share | normal / business | `dioman-methods-1793104467521921-23456-31` | 通过 |
| 单体 | plugins.single-timeout | normal / http | `dioman-methods-1793104467521921-23456-32` | 通过 |
| 单体 | plugins.single-timeout | normal / business | `dioman-methods-1793104467521921-23456-33` | 通过 |
| 配对 | plugins.pair-0 | normal / http | `dioman-methods-1793104467521921-23456-34` | 通过 |
| 配对 | plugins.pair-0 | normal / business | `dioman-methods-1793104467521921-23456-35` | 通过 |
| 配对 | plugins.pair-1 | normal / http | `dioman-methods-1793104467521921-23456-36` | 通过 |
| 配对 | plugins.pair-1 | normal / business | `dioman-methods-1793104467521921-23456-37` | 通过 |
| 配对 | plugins.pair-2 | normal / http | `dioman-methods-1793104467521921-23456-38` | 通过 |
| 配对 | plugins.pair-2 | normal / business | `dioman-methods-1793104467521921-23456-39` | 通过 |
| 配对 | plugins.pair-3 | normal / http | `dioman-methods-1793104467521921-23456-40` | 通过 |
| 配对 | plugins.pair-3 | normal / business | `dioman-methods-1793104467521921-23456-41` | 通过 |
| 配对 | plugins.pair-4 | normal / http | `dioman-methods-1793104467521921-23456-42` | 通过 |
| 配对 | plugins.pair-4 | normal / business | `dioman-methods-1793104467521921-23456-43` | 通过 |
| 配对 | plugins.pair-5 | normal / http | `dioman-methods-1793104467521921-23456-44` | 通过 |
| 配对 | plugins.pair-5 | normal / business | `dioman-methods-1793104467521921-23456-45` | 通过 |
| 配对 | plugins.pair-6 | normal / http | `dioman-methods-1793104467521921-23456-46` | 通过 |
| 配对 | plugins.pair-6 | normal / business | `dioman-methods-1793104467521921-23456-47` | 通过 |
| 配对 | plugins.pair-7 | normal / http | `dioman-methods-1793104467521921-23456-48` | 通过 |
| 配对 | plugins.pair-7 | normal / business | `dioman-methods-1793104467521921-23456-49` | 通过 |
| 配对 | plugins.pair-8 | normal / http | `dioman-methods-1793104467521921-23456-50` | 通过 |
| 配对 | plugins.pair-8 | normal / business | `dioman-methods-1793104467521921-23456-51` | 通过 |
| 配对 | plugins.pair-9 | normal / http | `dioman-methods-1793104467521921-23456-52` | 通过 |
| 配对 | plugins.pair-9 | normal / business | `dioman-methods-1793104467521921-23456-53` | 通过 |
| 配对 | plugins.pair-10 | normal / http | `dioman-methods-1793104467521921-23456-54` | 通过 |
| 配对 | plugins.pair-10 | normal / business | `dioman-methods-1793104467521921-23456-55` | 通过 |
| 配对 | plugins.pair-11 | normal / http | `dioman-methods-1793104467521921-23456-56` | 通过 |
| 配对 | plugins.pair-11 | normal / business | `dioman-methods-1793104467521921-23456-57` | 通过 |
| 配对 | plugins.pair-12 | normal / http | `dioman-methods-1793104467521921-23456-58` | 通过 |
| 配对 | plugins.pair-12 | normal / business | `dioman-methods-1793104467521921-23456-59` | 通过 |
| 配对 | plugins.pair-13 | normal / http | `dioman-methods-1793104467521921-23456-60` | 通过 |
| 配对 | plugins.pair-13 | normal / business | `dioman-methods-1793104467521921-23456-61` | 通过 |
| 配对 | plugins.pair-14 | normal / http | `dioman-methods-1793104467521921-23456-62` | 通过 |
| 配对 | plugins.pair-14 | normal / business | `dioman-methods-1793104467521921-23456-63` | 通过 |
| 配对 | plugins.pair-15 | normal / http | `dioman-methods-1793104467521921-23456-64` | 通过 |
| 配对 | plugins.pair-15 | normal / business | `dioman-methods-1793104467521921-23456-65` | 通过 |
| 配对 | plugins.pair-16 | normal / http | `dioman-methods-1793104467521921-23456-66` | 通过 |
| 配对 | plugins.pair-16 | normal / business | `dioman-methods-1793104467521921-23456-67` | 通过 |
| 配对 | plugins.pair-17 | normal / http | `dioman-methods-1793104467521921-23456-68` | 通过 |
| 配对 | plugins.pair-17 | normal / business | `dioman-methods-1793104467521921-23456-69` | 通过 |
| 配对 | plugins.pair-18 | normal / http | `dioman-methods-1793104467521921-23456-70` | 通过 |
| 配对 | plugins.pair-18 | normal / business | `dioman-methods-1793104467521921-23456-71` | 通过 |
| 配对 | plugins.pair-19 | normal / http | `dioman-methods-1793104467521921-23456-72` | 通过 |
| 配对 | plugins.pair-19 | normal / business | `dioman-methods-1793104467521921-23456-73` | 通过 |
| 配对 | plugins.pair-20 | normal / http | `dioman-methods-1793104467521921-23456-74` | 通过 |
| 配对 | plugins.pair-20 | normal / business | `dioman-methods-1793104467521921-23456-75` | 通过 |
| 配对 | plugins.pair-21 | normal / http | `dioman-methods-1793104467521921-23456-76` | 通过 |
| 配对 | plugins.pair-21 | normal / business | `dioman-methods-1793104467521921-23456-77` | 通过 |
| 配对 | plugins.pair-22 | normal / http | `dioman-methods-1793104467521921-23456-78` | 通过 |
| 配对 | plugins.pair-22 | normal / business | `dioman-methods-1793104467521921-23456-79` | 通过 |
| 配对 | plugins.pair-23 | normal / http | `dioman-methods-1793104467521921-23456-80` | 通过 |
| 配对 | plugins.pair-23 | normal / business | `dioman-methods-1793104467521921-23456-81` | 通过 |
| 配对 | plugins.pair-24 | normal / http | `dioman-methods-1793104467521921-23456-82` | 通过 |
| 配对 | plugins.pair-24 | normal / business | `dioman-methods-1793104467521921-23456-83` | 通过 |
| 配对 | plugins.pair-25 | normal / http | `dioman-methods-1793104467521921-23456-84` | 通过 |
| 配对 | plugins.pair-25 | normal / business | `dioman-methods-1793104467521921-23456-85` | 通过 |
| 配对 | plugins.pair-26 | normal / http | `dioman-methods-1793104467521921-23456-86` | 通过 |
| 配对 | plugins.pair-26 | normal / business | `dioman-methods-1793104467521921-23456-87` | 通过 |
| 配对 | plugins.pair-27 | normal / http | `dioman-methods-1793104467521921-23456-88` | 通过 |
| 配对 | plugins.pair-27 | normal / business | `dioman-methods-1793104467521921-23456-89` | 通过 |
| 配对 | plugins.pair-28 | normal / http | `dioman-methods-1793104467521921-23456-90` | 通过 |
| 配对 | plugins.pair-28 | normal / business | `dioman-methods-1793104467521921-23456-91` | 通过 |
| 配对 | plugins.pair-29 | normal / http | `dioman-methods-1793104467521921-23456-92` | 通过 |
| 配对 | plugins.pair-29 | normal / business | `dioman-methods-1793104467521921-23456-93` | 通过 |
| 配对 | plugins.pair-30 | normal / http | `dioman-methods-1793104467521921-23456-94` | 通过 |
| 配对 | plugins.pair-30 | normal / business | `dioman-methods-1793104467521921-23456-95` | 通过 |
| 配对 | plugins.pair-31 | normal / http | `dioman-methods-1793104467521921-23456-96` | 通过 |
| 配对 | plugins.pair-31 | normal / business | `dioman-methods-1793104467521921-23456-97` | 通过 |
| 边界 | plugins.boundary-retry-max-0 | normal / http | `dioman-methods-1793104467521921-23456-98` | 通过 |
| 边界 | plugins.boundary-retry-max-0 | normal / business | `dioman-methods-1793104467521921-23456-99` | 通过 |
| 边界 | plugins.boundary-retry-max-1 | normal / http | `dioman-methods-1793104467521921-23456-100` | 通过 |
| 边界 | plugins.boundary-retry-max-1 | normal / business | `dioman-methods-1793104467521921-23456-101` | 通过 |
| 边界 | plugins.boundary-retry-max-2 | normal / http | `dioman-methods-1793104467521921-23456-102` | 通过 |
| 边界 | plugins.boundary-retry-max-2 | normal / business | `dioman-methods-1793104467521921-23456-103` | 通过 |
| 边界 | plugins.boundary-retry-max-0（合并前 delay-ms-0 记录） | normal / http | `dioman-methods-1793104467521921-23456-104` | 通过 |
| 边界 | plugins.boundary-retry-max-0（合并前 delay-ms-0 记录） | normal / business | `dioman-methods-1793104467521921-23456-105` | 通过 |
| 边界 | plugins.boundary-retry-delay-ms-1 | normal / http | `dioman-methods-1793104467521921-23456-106` | 通过 |
| 边界 | plugins.boundary-retry-delay-ms-1 | normal / business | `dioman-methods-1793104467521921-23456-107` | 通过 |
| 边界 | plugins.boundary-retry-methods-0 | normal / http | `dioman-methods-1793104467521921-23456-108` | 通过 |
| 边界 | plugins.boundary-retry-methods-0 | normal / business | `dioman-methods-1793104467521921-23456-109` | 通过 |
| 边界 | plugins.boundary-retry-methods-1 | normal / http | `dioman-methods-1793104467521921-23456-110` | 通过 |
| 边界 | plugins.boundary-retry-methods-1 | normal / business | `dioman-methods-1793104467521921-23456-111` | 通过 |
| 边界 | plugins.boundary-cache-ttl-ms-0 | normal / http | `dioman-methods-1793104467521921-23456-112` | 通过 |
| 边界 | plugins.boundary-cache-ttl-ms-0 | normal / business | `dioman-methods-1793104467521921-23456-113` | 通过 |
| 边界 | plugins.boundary-cache-ttl-ms-1 | normal / http | `dioman-methods-1793104467521921-23456-114` | 通过 |
| 边界 | plugins.boundary-cache-ttl-ms-1 | normal / business | `dioman-methods-1793104467521921-23456-115` | 通过 |
| 边界 | plugins.boundary-cache-ttl-ms-2 | normal / http | `dioman-methods-1793104467521921-23456-116` | 通过 |
| 边界 | plugins.boundary-cache-ttl-ms-2 | normal / business | `dioman-methods-1793104467521921-23456-117` | 通过 |
| 边界 | plugins.boundary-cache-max-0 | normal / http | `dioman-methods-1793104467521921-23456-118` | 通过 |
| 边界 | plugins.boundary-cache-max-0 | normal / business | `dioman-methods-1793104467521921-23456-119` | 通过 |
| 边界 | plugins.boundary-cache-max-1 | normal / http | `dioman-methods-1793104467521921-23456-120` | 通过 |
| 边界 | plugins.boundary-cache-max-1 | normal / business | `dioman-methods-1793104467521921-23456-121` | 通过 |
| 边界 | plugins.boundary-cache-max-2 | normal / http | `dioman-methods-1793104467521921-23456-122` | 通过 |
| 边界 | plugins.boundary-cache-max-2 | normal / business | `dioman-methods-1793104467521921-23456-123` | 通过 |
| 边界 | plugins.boundary-cache-methods-0 | normal / http | `dioman-methods-1793104467521921-23456-124` | 通过 |
| 边界 | plugins.boundary-cache-methods-0 | normal / business | `dioman-methods-1793104467521921-23456-125` | 通过 |
| 边界 | plugins.boundary-cache-methods-1 | normal / http | `dioman-methods-1793104467521921-23456-126` | 通过 |
| 边界 | plugins.boundary-cache-methods-1 | normal / business | `dioman-methods-1793104467521921-23456-127` | 通过 |
| 边界 | plugins.boundary-loading-delay-ms-0 | normal / http | `dioman-methods-1793104467521921-23456-128` | 通过 |
| 边界 | plugins.boundary-loading-delay-ms-0 | normal / business | `dioman-methods-1793104467521921-23456-129` | 通过 |
| 边界 | plugins.boundary-loading-delay-ms-1 | normal / http | `dioman-methods-1793104467521921-23456-130` | 通过 |
| 边界 | plugins.boundary-loading-delay-ms-1 | normal / business | `dioman-methods-1793104467521921-23456-131` | 通过 |
| 边界 | plugins.boundary-loading-delay-ms-0（合并前 delay-close-ms-0 记录） | normal / http | `dioman-methods-1793104467521921-23456-132` | 通过 |
| 边界 | plugins.boundary-loading-delay-ms-0（合并前 delay-close-ms-0 记录） | normal / business | `dioman-methods-1793104467521921-23456-133` | 通过 |
| 边界 | plugins.boundary-loading-delay-close-ms-1 | normal / http | `dioman-methods-1793104467521921-23456-134` | 通过 |
| 边界 | plugins.boundary-loading-delay-close-ms-1 | normal / business | `dioman-methods-1793104467521921-23456-135` | 通过 |
| 边界 | plugins.boundary-timeout-connect-ms-0 | normal / http | `dioman-methods-1793104467521921-23456-136` | 通过 |
| 边界 | plugins.boundary-timeout-connect-ms-0 | normal / business | `dioman-methods-1793104467521921-23456-137` | 通过 |
| 边界 | plugins.boundary-timeout-connect-ms-1 | normal / http | `dioman-methods-1793104467521921-23456-138` | 通过 |
| 边界 | plugins.boundary-timeout-connect-ms-1 | normal / business | `dioman-methods-1793104467521921-23456-139` | 通过 |
| 边界 | plugins.boundary-timeout-receive-ms-0 | normal / http | `dioman-methods-1793104467521921-23456-140` | 通过 |
| 边界 | plugins.boundary-timeout-receive-ms-0 | normal / business | `dioman-methods-1793104467521921-23456-141` | 通过 |
| 边界 | plugins.boundary-timeout-receive-ms-1 | normal / http | `dioman-methods-1793104467521921-23456-142` | 通过 |
| 边界 | plugins.boundary-timeout-receive-ms-1 | normal / business | `dioman-methods-1793104467521921-23456-143` | 通过 |
| 边界 | plugins.boundary-breaker-threshold-0 | normal / http | `dioman-methods-1793104467521921-23456-144` | 通过 |
| 边界 | plugins.boundary-breaker-threshold-0 | normal / business | `dioman-methods-1793104467521921-23456-145` | 通过 |
| 边界 | plugins.boundary-breaker-threshold-1 | normal / http | `dioman-methods-1793104467521921-23456-146` | 通过 |
| 边界 | plugins.boundary-breaker-threshold-1 | normal / business | `dioman-methods-1793104467521921-23456-147` | 通过 |
| 边界 | plugins.boundary-breaker-open-ms-0 | normal / http | `dioman-methods-1793104467521921-23456-148` | 通过 |
| 边界 | plugins.boundary-breaker-open-ms-0 | normal / business | `dioman-methods-1793104467521921-23456-149` | 通过 |
| 边界 | plugins.boundary-breaker-open-ms-1 | normal / http | `dioman-methods-1793104467521921-23456-150` | 通过 |
| 边界 | plugins.boundary-breaker-open-ms-1 | normal / business | `dioman-methods-1793104467521921-23456-151` | 通过 |
| 边界 | plugins.boundary-breaker-open-ms-2 | normal / http | `dioman-methods-1793104467521921-23456-152` | 通过 |
| 边界 | plugins.boundary-breaker-open-ms-2 | normal / business | `dioman-methods-1793104467521921-23456-153` | 通过 |
| 全量 | plugins.full-workflow | normal / http | `dioman-methods-1793104467521921-23456-154` | 通过 |
| 全量 | plugins.full-workflow | normal / business | `dioman-methods-1793104467521921-23456-155` | 通过 |
| 全量 | plugins.full-workflow | weak / http | `dioman-methods-1793104467521921-23456-156` | 通过 |
| 全量 | plugins.full-workflow | weak / business | `dioman-methods-1793104467521921-23456-157` | 通过 |
| 全量 | plugins.full-flap-workflow | flap / http | `dioman-methods-1793104467521921-23456-158` | 通过 |
| 全量 | plugins.full-flap-workflow | flap / business | `dioman-methods-1793104467521921-23456-159` | 通过 |

## 规则出处

| 源码位置 | 对应用例 |
|---|---|
| lib/src/breaker_plugin.dart:437 | plugins.full-workflow / plugins.full-flap-workflow 的 rules 字段，逐边正序通过/逆序拒绝 |
| lib/src/cache_plugin.dart:319 | plugins.full-workflow / plugins.full-flap-workflow 的 rules 字段，逐边正序通过/逆序拒绝 |
| lib/src/cancel_plugin.dart:72 | plugins.full-workflow / plugins.full-flap-workflow 的 rules 字段，逐边正序通过/逆序拒绝 |
| lib/src/dioman_plugin.dart:22 | plugins.full-workflow / plugins.full-flap-workflow 的 rules 字段，逐边正序通过/逆序拒绝 |
| lib/src/key_plugin.dart:160 | plugins.full-workflow / plugins.full-flap-workflow 的 rules 字段，逐边正序通过/逆序拒绝 |
| lib/src/loading_plugin.dart:195 | plugins.full-workflow / plugins.full-flap-workflow 的 rules 字段，逐边正序通过/逆序拒绝 |
| lib/src/normalize_plugin.dart:205 | plugins.full-workflow / plugins.full-flap-workflow 的 rules 字段，逐边正序通过/逆序拒绝 |
| lib/src/notify_plugin.dart:39 | plugins.full-workflow / plugins.full-flap-workflow 的 rules 字段，逐边正序通过/逆序拒绝 |
| lib/src/offline_plugin.dart:300 | plugins.full-workflow / plugins.full-flap-workflow 的 rules 字段，逐边正序通过/逆序拒绝 |
| lib/src/plugin_order.dart:16 | plugins.full-workflow / plugins.full-flap-workflow 的 rules 字段，逐边正序通过/逆序拒绝 |
| lib/src/plugin_order.dart：validatePluginOrder / _checkDuplicates / _checkRequires / _sortOrThrow | 真实矩阵规则及 test/unit/plugin_order_test.dart 的重复名/缺依赖/环测试 |
| lib/src/extra_keys.dart：builtIn / findSharedState | 每个真实场景的 rules 字段；test/integration/extra_keys_integration_test.dart 的源码双向检查 |

## 未解决项

- 历史3533个未声明组合中56格已写明禁止注入的合法skip理由，其余3477格尚未补齐逐项预期并真实执行；不得标为合法不适用。
- 单体只覆盖每插件成功/500/取消基础路径，未穷尽全部公开选项和触发路径。
- 边界覆盖只涉及部分数值/时间/集合选项，详见各插件待补清单。
- 规则已覆盖实际排序边、重复名、extra注册和请求资源释放；全部实现不变量未逐条穷尽。
- 未覆盖行中的防御性异常出口保留源码契约说明，没有把它们计为已覆盖；覆盖率未达到100%。
