---
title: dioman 洋葱管线 B5b 删除与切换报告
status: active
updated: 2026-10-29
summary: 唯一入口与目录归位、旧实现删除、新 API 执行器和示例、785 项台账和 631 行总账、覆盖率与闸门证据
---

## 结果

- 唯一入口为 `package:dioman/dioman.dart`，新实现平铺至 lib/src（保留 plugins/）。27/27 源码与 B5a 工作区 SHA256 一致，与 895d959 规范化换行后也一致；没有修改库行为。
- 全仓 `dart analyze` 和 `dart analyze example` 均 0 issue；含分支覆盖的全量 `dart test` 5014 条全绿。24 个可执行文件行/分支均 100%；3 个声明文件无执行分母。
- G0/G1/G2/G3/G5 均零缺口，G1 白名单 4 → 0；G4 剩 190 个待 B7 缺口，已逐条分类，包含 connect 超时 BLOCKED。
- API 台账 693 → 785；总账 442 → 631；基线 2 → 190，仅增加 G4。未运行 testkit 全量。
- 无 commit/push/切分支。除要求的 codex review 命令外未转派。临时 bench worktree 已移除，没有修改其它工作区。

## 1. 删除前留存

[旧版 key 原始导出](pipeline-b5b-evidence/key-export-raw.json) 在删除前实际同时调用新旧实现，固定种子 2400 组逐项相等后输出。[固定基准](../../test/support/key_baseline.json) 含全部输入对应结果。409 项包含进程相关 identityHashCode，不能原样跨进程比较，故该数值槽固定为 `<identityHashCode(data)>`；测试只在此槽代入当前请求体身份，其余字节严格对照。这个差异在第一次跨进程全量复跑中发现并修正，原始未替换导出也保留供核对。第二条开关/异常/NaN 用例原本就是新服务规则断言，继续保留。见 [导出时差分](pipeline-b5b-evidence/key-export.txt)、[固定基准复跑](pipeline-b5b-evidence/key-baseline-test.txt)。

旧 bench 改为 `python tool/bench_legacy.py --out <结果.json>`：固定 895d959，用唯一临时目录执行 `git worktree add --detach`，在其中 dioman 子包跑旧 S1–S6，finally 移除且校验移除目录在授权工作区中。Git 根比包高一级，初次探测因目录层级失败后已修正；正式一轮退出 0，六场景完成。新版 `dart run benchmark/pipeline.dart` 也实际跑通一轮。两版共用 runner 格式，只验证可运行，不对性能数字下结论。

[旧结果](pipeline-b5b-evidence/bench-legacy.json)、[旧日志](pipeline-b5b-evidence/bench-legacy-stderr.txt)、[新结果](pipeline-b5b-evidence/bench-pipeline.json)。B6 轮流执行旧命令与新命令各三轮即可交错 A/B。

## 2. 删除清单

删除前已保存 [逐文件清单](pipeline-b5b-evidence/deleted.txt)。fixtures.dart、fake_cache_persist.dart、test_server.dart 均无新代码引用，全部删除；新真实回环用例在各自测试内创建 HttpServer。所有删除均直接删除，未 git rm。

<details>
<summary>删除前全部文件</summary>

```text
lib/src/auth_plugin.dart
lib/src/breaker_plugin.dart
lib/src/cache_plugin.dart
lib/src/cancel_plugin.dart
lib/src/dioman.dart
lib/src/dioman_plugin.dart
lib/src/envs_plugin.dart
lib/src/extra_keys.dart
lib/src/filter_plugin.dart
lib/src/key_plugin.dart
lib/src/loading_plugin.dart
lib/src/log_plugin.dart
lib/src/mock_adapter.dart
lib/src/normalize_plugin.dart
lib/src/notify_plugin.dart
lib/src/offline_plugin.dart
lib/src/plugin_order.dart
lib/src/repath_plugin.dart
lib/src/replay_support.dart
lib/src/request_claims.dart
lib/src/retry_plugin.dart
lib/src/share_plugin.dart
lib/src/timeout_plugin.dart
test_legacy/boundary/auth_concurrent_boundary_test.dart
test_legacy/boundary/auth_replay_boundary_test.dart
test_legacy/boundary/auth_session_boundary_test.dart
test_legacy/boundary/auth_transport_boundary_test.dart
test_legacy/boundary/breaker_boundary_test.dart
test_legacy/boundary/breaker_callbacks_boundary_test.dart
test_legacy/boundary/cache_boundary_test.dart
test_legacy/boundary/cancel_boundary_test.dart
test_legacy/boundary/cancel_dispose_boundary_test.dart
test_legacy/boundary/filter_boundary_test.dart
test_legacy/boundary/key_boundary_test.dart
test_legacy/boundary/loading_boundary_test.dart
test_legacy/boundary/log_boundary_test.dart
test_legacy/boundary/normalize_boundary_test.dart
test_legacy/boundary/offline_boundary_test.dart
test_legacy/boundary/offline_options_boundary_test.dart
test_legacy/boundary/repath_boundary_test.dart
test_legacy/boundary/retry_backoff_boundary_test.dart
test_legacy/boundary/retry_boundary_test.dart
test_legacy/boundary/share_boundary_test.dart
test_legacy/boundary/timeout_boundary_test.dart
test_legacy/boundary/timeout_effective_boundary_test.dart
test_legacy/combo/auth_cache_combo_test.dart
test_legacy/combo/auth_cancel_combo_test.dart
test_legacy/combo/auth_loading_combo_test.dart
test_legacy/combo/auth_normalize_combo_test.dart
test_legacy/combo/auth_retry_cancel_combo_test.dart
test_legacy/combo/auth_retry_combo_test.dart
test_legacy/combo/auth_retry_keep_alive_combo_test.dart
test_legacy/combo/auth_share_combo_test.dart
test_legacy/combo/breaker_retry_combo_test.dart
test_legacy/combo/cache_cancel_combo_test.dart
test_legacy/combo/cache_key_combo_test.dart
test_legacy/combo/cache_loading_combo_test.dart
test_legacy/combo/cache_normalize_combo_test.dart
test_legacy/combo/cache_offline_combo_test.dart
test_legacy/combo/cache_retry_combo_test.dart
test_legacy/combo/cache_share_combo_test.dart
test_legacy/combo/cancel_loading_combo_test.dart
test_legacy/combo/cancel_retry_combo_test.dart
test_legacy/combo/cancel_share_combo_test.dart
test_legacy/combo/cancel_share_takeover_combo_test.dart
test_legacy/combo/full_stack_combo_test.dart
test_legacy/combo/key_share_combo_test.dart
test_legacy/combo/loading_retry_combo_test.dart
test_legacy/combo/loading_share_combo_test.dart
test_legacy/combo/mock_adapter_combo_test.dart
test_legacy/combo/normalize_notify_combo_test.dart
test_legacy/combo/normalize_retry_combo_test.dart
test_legacy/combo/normalize_share_combo_test.dart
test_legacy/combo/powerset_combo_test.dart
test_legacy/combo/retry_share_arbitration_combo_test.dart
test_legacy/combo/retry_share_recovery_combo_test.dart
test_legacy/integration/extra_keys_integration_test.dart
test_legacy/integration/install_integration_test.dart
test_legacy/integration/install_plugins_integration_test.dart
test_legacy/integration/matrix_integration_test.dart
test_legacy/integration/real_service_integration_test.dart
test_legacy/rule/auth_flow_rule_test.dart
test_legacy/rule/auth_options_rule_test.dart
test_legacy/rule/auth_overrides_rule_test.dart
test_legacy/rule/breaker_accounting_rule_test.dart
test_legacy/rule/breaker_options_rule_test.dart
test_legacy/rule/breaker_rule_test.dart
test_legacy/rule/cache_clone_rule_test.dart
test_legacy/rule/cache_options_rule_test.dart
test_legacy/rule/cache_policy_rule_test.dart
test_legacy/rule/cache_store_rule_test.dart
test_legacy/rule/cancel_options_rule_test.dart
test_legacy/rule/cancel_rule_test.dart
test_legacy/rule/envs_options_rule_test.dart
test_legacy/rule/envs_rule_test.dart
test_legacy/rule/filter_names_rule_test.dart
test_legacy/rule/filter_rule_test.dart
test_legacy/rule/key_options_rule_test.dart
test_legacy/rule/key_rule_test.dart
test_legacy/rule/loading_options_rule_test.dart
test_legacy/rule/loading_rule_test.dart
test_legacy/rule/log_flags_rule_test.dart
test_legacy/rule/log_rule_test.dart
test_legacy/rule/log_stages_rule_test.dart
test_legacy/rule/mock_adapter_rule_test.dart
test_legacy/rule/normalize_options_rule_test.dart
test_legacy/rule/normalize_rule_test.dart
test_legacy/rule/notify_rule_test.dart
test_legacy/rule/offline_rule_test.dart
test_legacy/rule/repath_names_rule_test.dart
test_legacy/rule/repath_rule_test.dart
test_legacy/rule/retry_after_rule_test.dart
test_legacy/rule/retry_decision_rule_test.dart
test_legacy/rule/retry_rule_test.dart
test_legacy/rule/share_retry_rule_test.dart
test_legacy/rule/share_rule_test.dart
test_legacy/rule/share_settle_rule_test.dart
test_legacy/rule/timeout_rule_test.dart
test_legacy/rule/timeout_tiers_rule_test.dart
test_legacy/unit/accept_executor_test.dart
test_legacy/unit/exception_test.dart
test_legacy/unit/extra_descriptors_test.dart
test_legacy/unit/extra_keys_test.dart
test_legacy/unit/matrix_test.dart
test_legacy/unit/pairwise_test.dart
test_legacy/unit/plugin_contract_test.dart
test_legacy/unit/plugin_order_test.dart
test_legacy/unit/replay_support_test.dart
test_legacy/unit/request_claims_test.dart
test_legacy/unit/service_guard_test.dart
test/support/fixtures.dart
test/support/fake_cache_persist.dart
test/support/test_server.dart
benchmark/legacy.dart
benchmark/legacy_client.dart
```

</details>

## 3. 目录归位和入口

```text
lib/src/pipeline/cache_store.dart -> lib/src/cache_store.dart
lib/src/pipeline/client.dart -> lib/src/client.dart
lib/src/pipeline/clock.dart -> lib/src/clock.dart
lib/src/pipeline/config.dart -> lib/src/config.dart
lib/src/pipeline/context.dart -> lib/src/context.dart
lib/src/pipeline/key.dart -> lib/src/key.dart
lib/src/pipeline/options.dart -> lib/src/options.dart
lib/src/pipeline/pipeline.dart -> lib/src/pipeline.dart
lib/src/pipeline/plugin.dart -> lib/src/plugin.dart
lib/src/pipeline/plugins -> lib/src/plugins
lib/src/pipeline/request.dart -> lib/src/request.dart
lib/src/pipeline/response.dart -> lib/src/response.dart
lib/src/pipeline/stages.dart -> lib/src/stages.dart
lib/src/pipeline/token_manager.dart -> lib/src/token_manager.dart
lib/src/pipeline/transport.dart -> lib/src/transport.dart
test/support/pipeline/b2_constants.dart -> test/support/b2_constants.dart
test/support/pipeline/b3_helpers.dart -> test/support/b3_helpers.dart
test/support/pipeline/b4_constants.dart -> test/support/b4_constants.dart
test/support/pipeline/b4_helpers.dart -> test/support/b4_helpers.dart
test/support/pipeline/b4_migration_scenarios.dart -> test/support/b4_migration_scenarios.dart
test/support/pipeline/b4_retry_migration_scenarios.dart -> test/support/b4_retry_migration_scenarios.dart
test/support/pipeline/b5_powerset.dart -> test/support/b5_powerset.dart
test/support/pipeline/constants.dart -> test/support/constants.dart
test/support/pipeline/fake_clock.dart -> test/support/fake_clock.dart
test/support/pipeline/fake_network.dart -> test/support/fake_network.dart
test/support/pipeline/helpers.dart -> test/support/helpers.dart
test/support/pipeline/invariant_harness.dart -> test/support/invariant_harness.dart
lib/pipeline.dart -> lib/dioman.dart
```

入口保留原新 barrel 的 `hide cancellationFailure` 和 mock 的 show 限制。测试、benchmark、工具改为唯一入口。覆盖率及变异脚本的 lib/src 路径已归位；B5a 全库脚本的默认产物目录改为 B5b，避免重跑覆盖历史证据。[源码核对](pipeline-b5b-evidence/library-unchanged.txt)、[最终哈希](pipeline-b5b-evidence/source-sha256.json)。

每步都执行全仓 analyze：第 1 步 0 issue；按指定顺序删除后第 2 步 464 项、第 3 步 283 项，均为尚未迁移的调用方失去旧编译对象。第 4 步执行器独立分析 0 issue，全仓仍有 example；第 5–7 步恢复全仓 0 issue。原始 stepN-analyze.txt 均保留，没有将中途错误报作通过。

## 4. 执行器改动

- 删除 EnvelopeTransformer、业务码 shouldRetry/shouldTrip、auth onFailure 信封适配、总预算错误改写拦截器、额外拆包和旧取消插件 track/untrack。失败不再按 extra 标签或 DioException 内容重新解释。
- 被测请求使用 api.send；DiomanCall 与类型化 option 键承担请求配置。归类只读 DiomanResponse.kind/reason/status；刷新回调用独立新客户端拿数据，不替库增加归一化能力。pending_after 读取 api.pending。
- 保留真实网络探测、multipart 构造、限流停止守卫与事件记录。mock-in-chain 已登记；raw-business-code 未声明，requires 指定该能力时输出 `skipped: missing raw-business-code`。testkit 侧补能力名仍留 B7。`total_ms` 无库原生实现，已从接受字段删除并显式拒绝该配置；执行器不再用宿主计时器补能力。
- 未声明网络/风格和场景 skip 从字段读取，原因以“不适用：”开头；没有新增按场景 id 黑名单。原维度排除集合不变，仅统一前缀；两类跳过已有离线执行器回归。
- 旧 API 大探针替换为新客户端真实 ping 与实际字段读取，未执行的 API 不伪报触达，B7 按新台账继续补真实证据。

[执行器独立分析](pipeline-b5b-evidence/accept-analyze.txt)、[执行器和静态总账工具单测](pipeline-b5b-evidence/executor-matrix-tests.txt)。本批只编译/单测，没有连接 testkit 执行全量。

## 5. example

保留 Flutter UI、全部演示入口及控制台；手写 auth/retry 恢复器换成内置插件，日志观察器改透明 handle/next，mock 路由改为返回数据/Response。独立构造器返回 Dioman；real_run 保留缓存、共享、刷新和请求覆盖断言，改用新调用配置。本机使用 `dart analyze example`，最终 0 issue；未运行外部公共服务示例。文案和界面打磨留 B6。

## 6. 台账和总账

公开 API：693 → 785；新增 id 402、删除 id 310、同名 383，净增 92；其中明确命名/管理端口替代 31 对，已含在新增/删除中，不重复相加。沿用原工具的公开声明、构造参数、字段、方法/getter、枚举值统计口径。

[全部增删](pipeline-b5b-evidence/api-diff.json)、[31 对替代名](pipeline-b5b-evidence/api-renames.json)、[310 项删除依据](pipeline-b5b-evidence/api-removals.json)。每项对应原迁移行 keep/change/drop 或插件规格 §9 的 C 编号；删除 API id 不等于删除能力，例如 cache clear/remove 移入管理端口。

总账最终 442 → 631：同 id 224、删除 id 218、新增 id 407。先裁去 219 个旧行，sync 后 DiomanCache.cachePolicy 按新存储策略以同 id 重建；最终删除含 99 drop、107 change、12 keep（后者为管理/时钟/生命周期挂点移动）。[最终逐行差异](pipeline-b5b-evidence/matrix-diff.json)、[处理中删除映射](pipeline-b5b-evidence/matrix-removed.json)。

定档为①450、②171、③10 行：纯配置/算法和契约注入为①；传输、环境假设和代表组合为②；真实弱网/连接复用等无可替逻辑子点为③。失去旧 API 挂点的 153 个真实场景各自登记 INV-REAL 子点，保留场景引用，不用大类 PASS 掩盖单项。旧真实 PASS 不冒充切换后验收，result 清空待 B7；失效 local 路径改指新回环用例或删除。另增加 1 行 INV-example，用本批已实际通过的本地真实 HTTP 示例回归，登记 1 格 PASS。

标题链接经过 AST 提取和审计，[自动候选修正后映射](pipeline-b5b-evidence/title-links.json)、[手工映射](pipeline-b5b-evidence/manual-title-links.json)。声明型触达允许默认测试的显式导出检查；行为型仍须归行并有单测。静态闸门恢复到 test/integration/matrix_integration_test.dart，默认 dart test 直接拒绝任何 G0/G2/G3/G5 单测侧缺口，不靠基线放行。

基线使用显式 `--update-baseline --allow-grow` 从 2 → 190：新增 188 个 G4，静态缺口新增 0，原 connect 两个缺口保留。理由是新库和执行器已切换，必须在 B7 重新实际核对，不能继承旧 PASS。G1 白名单 4 → 0。

## 7. 闸门与覆盖率

```text
G0: 0
G1: 0
G2: 0
G3: 0
G4: 190
G5: 0
```

[完整闸门报告](pipeline-b5b-evidence/gates.md)、[输出](pipeline-b5b-evidence/gates.txt)、[逐条 G4 清单与理由](pipeline-b5b-evidence/g4-gaps.json)。190 = 180 no-result + 10 no-real。按来源：153 项真实场景迁入、18 项新客户端入口（9 行各缺 real/result）、17 项既有场景复验、2 项 connect 环境缺口。connect 原因：netem 用户态不能阻止内核握手，回环连接拒绝只能产生 connectionError；需要 B7 独立可控不可达端点，保持 BLOCKED。

| lib/src 文件 | LF | LH | BRF | BRH |
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

可执行行 1407/1407，分支 672/672。cache_store/token_manager 抽象契约和 stages 枚举/常量表为 0/0，不宣传有分母的 100%。

按 B5a 口径 rglob 全部 27 个源文件，拒绝缺 SF、重复记录、缺 DA/BRDA、未命中和汇总计数不符。[LCOV](pipeline-b5b-evidence/coverage.info)、[计数](pipeline-b5b-evidence/coverage.txt)、[JSON](pipeline-b5b-evidence/coverage.json)。

归位后的变异脚本七项实际跑通，均为运行时断言击中，源码原字节恢复：

| 变异 | powerset 失败 | SHA256 |
|---|---:|---|
| leave-listener | 256 | 一致 |
| loading-close | 2304 | 一致 |
| notify-double | 832 | 一致 |
| auth-singleflight | 256 | 一致 |
| retry-replayable | 192 | 一致 |
| cache-barrier | 2176 | 一致 |
| mock-replayable | 512 | 一致 |

[变异详情](pipeline-b5b-evidence/mutations.json)。没有编译/加载失败冒充击中。

## 8. 迁移公式

```text
tests: 580 = 239 keep + 224 change + 117 drop; doubtful=0; PASS
matrix: 442 = 181 keep + 162 change + 99 drop; doubtful=0; PASS
runtime identities / matrix ids / unique keys / C1-C13 / locations / Markdown rows: PASS
```

固定 [原始总账](../reference/pipeline-migration/raw/matrix-before-pipeline.json)，tool/pipeline_migration.py 继续从原运行时事件和原账独立核对身份、唯一性、C1–C13 与 Markdown 行，避免切换后的新账覆盖基准。

## 9. 文档索引

测试资产速查改为新夹具、真实回环、powerset/pairs、固定 key 基准与唯一入口。补齐分层迁移表、B1–B5b 报告和证据索引；B1–B5a 已终审而元数据仍 review，本批只改为 active，不改正文。根 README、中英文使用文档、architecture.md、SKILL.md、CHANGELOG 均留 B6。

## 终审修复与 codex review

无库行为修复。切换工具修正了 key 身份哈希基准跨进程复跑、bench 临时包层级、常量标题反查和符号扫描泛型吞函数声明；后两项有独立回归。

`codex review --uncommitted` 已正常结束，exit 0，提出 3 个成立 P2，全部修复。完整原文见 [review](pipeline-b5b-evidence/codex-review.txt)。

1. business 429/503 服务停止守卫丢失：只在库工厂已归一化结果上读取 status/data，服务停止时标记 serviceBlocked 并中止；不判定原始业务码，不改响应，不补 retry/breaker 能力。注入 HTTP/business 503 仍交原生重试。回归确认非注入状态只发送一次。
2. total_ms 被接受却不执行：明确拒绝不支持的字段，删除“接受但无效”的配置路径，不恢复宿主总预算计时器。
3. send 不抛预期失败，示例 catch 不可达：要抛错的示例改 request；其它继续读 send 返回值。新增真实回环服务执行完整 CLI 示例，确认预期 404 后继续至 ALL CHECKS PASSED。该回归还发现 debug 不是每次普通请求自动输出日志，示例改为验证失败调用栈及显式诊断输出。

[修复后执行器回归](pipeline-b5b-evidence/review-regressions.txt)、[完整 CLI 回环回归](pipeline-b5b-evidence/example-regression.txt)。[逐项撤掉修复](pipeline-b5b-evidence/review-reverse.json) 均产生 1 条运行时失败，之后恢复最终源码；没有用编译失败冒充回归。

## 最终验证与状态

最终全仓 analyze、example analyze 均 0 issue；默认测试和含分支覆盖测试均 5014 全绿，全部等待到退出 0。完整输出：[analyze](pipeline-b5b-evidence/analyze.txt)、[example](pipeline-b5b-evidence/example-analyze.txt)、[默认测试](pipeline-b5b-evidence/tests.txt)、[覆盖测试](pipeline-b5b-evidence/coverage-tests.txt)。

[旧机制 grep](pipeline-b5b-evidence/legacy-grep.txt) 对 lib/ 和 test/ 全部文件执行（不只 Dart），七种模式均零匹配。旧验收 API 触达清单移到 docs/reference/pipeline-migration/raw/accept-evidence，两个历史 JSON 原样保留，未修改原运行事实；新实现不再读取它们作为声明触达证明。

[范围检查](pipeline-b5b-evidence/scope-check.txt) 确认依赖和 B6 保留文件未改，无 tool/__pycache__ 和 bench 临时目录。SDK 声明仍 ^3.5.0；实际运行 Dart 3.13.0，没有宣称实测最低 SDK。

最终 git status 首 50 行和总行数、git log、worktree 见下方。


```text
Analyzing dioman...
No issues found!

Analyzing example...
No issues found!

00:07 +5014: All tests passed!
00:09 +5014: All tests passed!
```

文档索引检查和 git diff --check 均退出 0。旧两个验收汇总原样移至 docs/reference/pipeline-migration/raw/accept-evidence；JSON 文档示例中的旧源地址同步更新。

`git status --short | head -50`（PowerShell 使用 Select-Object -First 50，同一输出）：

```text
 D benchmark/legacy.dart
 D benchmark/legacy_client.dart
 M benchmark/runner.dart
 M benchmark/scenarios.dart
 M benchmark/summarize.py
 M docs/README.md
 M docs/design/test-matrix-plan.md
 M docs/reports/2026-10-29-pipeline-b1.md
 M docs/reports/2026-10-29-pipeline-b2.md
 M docs/reports/2026-10-29-pipeline-b3.md
 M docs/reports/2026-10-29-pipeline-b4.md
 M docs/reports/2026-10-29-pipeline-b5a.md
 M example/dioman_example.dart
 M example/lib/main.dart
 M example/real_run.dart
 M lib/dioman.dart
 D lib/pipeline.dart
 D lib/src/auth_plugin.dart
 D lib/src/breaker_plugin.dart
 D lib/src/cache_plugin.dart
 D lib/src/cancel_plugin.dart
 D lib/src/dioman.dart
 D lib/src/dioman_plugin.dart
 D lib/src/envs_plugin.dart
 D lib/src/extra_keys.dart
 D lib/src/filter_plugin.dart
 D lib/src/key_plugin.dart
 D lib/src/loading_plugin.dart
 D lib/src/log_plugin.dart
 D lib/src/mock_adapter.dart
 D lib/src/normalize_plugin.dart
 D lib/src/notify_plugin.dart
 D lib/src/offline_plugin.dart
 D lib/src/pipeline/cache_store.dart
 D lib/src/pipeline/client.dart
 D lib/src/pipeline/clock.dart
 D lib/src/pipeline/config.dart
 D lib/src/pipeline/context.dart
 D lib/src/pipeline/key.dart
 D lib/src/pipeline/options.dart
 D lib/src/pipeline/pipeline.dart
 D lib/src/pipeline/plugin.dart
 D lib/src/pipeline/plugins/auth.dart
 D lib/src/pipeline/plugins/breaker.dart
 D lib/src/pipeline/plugins/cache.dart
 D lib/src/pipeline/plugins/envs.dart
 D lib/src/pipeline/plugins/filter.dart
 D lib/src/pipeline/plugins/loading.dart
 D lib/src/pipeline/plugins/mock.dart
 D lib/src/pipeline/plugins/notify.dart
```

总行数：303。完整 [状态](pipeline-b5b-evidence/git-status.txt)。

`git log --oneline -1`：

```text
895d959 test(dioman): B5a powerset 与成对组合补齐
```

`git worktree list`：

```text
E:/workspaces/dart-labs          3715616 [main]
E:/workspaces/dart-labs-pipeline 895d959 [jelon/dioman-pipeline]
```

没有新增提交、推送或分支操作。临时旧版 bench 工作区已移除，现有两个 worktree 均未删除或切换。


## 终审修复：公共面收口（最终口径）

本节取代上文初次 B5b 的“785 项 API / 631 行总账 / 27 文件覆盖率”作为最终发版口径；上文增删公式和初次审查保留为过程记录。

问题：内部取消桥、共享状态和物理表诊断进入公共 barrel 和台账，形成了不应承诺的发布契约。逐项核对原台账全部 785 项，最终保留 744 项、内部化 41 项，无新增公共项。完整逐项决定与理由见 [785 项审计](pipeline-b5b-evidence/final-review-api-audit.json)，最终全部声明、成员和参数见 [744 项公开清单](pipeline-b5b-evidence/final-review-public-api.json)。

修法：`DiomanContextState`、`DiomanCancelLink` 移入未导出的 `src/context_state.dart`。上下文保存私有 `_state`，公开构造器不接收内部状态；内核通过 `DiomanContextInternal.create` 注入状态，派生继续共享。状态访问、传输重放标记读取、内核调用栈落定和诊断位于未直接导出的同库 `context_internal.dart`、`client_internal.dart`、`plugins/cache_internal.dart`、`plugins/share_internal.dart`、`response_internal.dart`，由扩展读取私有字段；测试显式导入未导出的 `package:dioman/src/diagnostics.dart`。缓存公开管理端口仅保留 remove/clear；共享诊断标记与其扩展均不从公共入口导出。无依赖新增，没有使用 @internal/meta。

公共 barrel 对所有源文件使用 show 白名单，执行器注册/校验/排序/编译、内置阶段表和内核传输函数也不再导出。测试仍直接验证 I3 订阅、共享保留状态、屏障、条目和活动表清空；未删行为断言。公开声明可达性测试删去五个内部声明的公共可达性断言，另补公共构造器隔离/取消回归及 SDK 编译级负向用例：17 个内部名称、7 个白盒 getter 均不可经公共 barrel 访问。

### 收口的完整 41 项

- `INV-context-lifecycle`（24 项）：内部取消桥、共享状态及其泄漏入口，只用于内核生命周期与 I3 白盒断言。

`Dioman.cancellationSubscriptions`, `DiomanCancelLink`, `DiomanCancelLink.new`, `DiomanCancelLink.new(source)`, `DiomanCancelLink.new(target)`, `DiomanCancelLink.dispose`, `DiomanContextState`, `DiomanContextState.new`, `DiomanContextState.new(token)`, `DiomanContextState.new(onDispose)`, `DiomanContextState.token`, `DiomanContextState.values`, `DiomanContextState.keys`, `DiomanContextState.listeners`, `DiomanContextState.replayable`, `DiomanContextState.retain`, `DiomanContextState.release`, `DiomanContextState.cancel`, `DiomanContextState.dispose`, `DiomanContext.new(state)`, `DiomanContext.state`, `DiomanContext.cancellationSubscriptions`, `DiomanContext.replayable`, `DiomanResponseFactory.withCallSite`。

- `INV-pipeline-internals`（13 项）：内核执行器实现细节，插件作者通过 setup/handle/next 扩展，不应自行注册、排序或编译内核。

`DiomanRunner`, `DiomanRegistration`, `DiomanRegistration.new`, `DiomanRegistration.new(plugin)`, `DiomanRegistration.new(instance)`, `DiomanRegistration.plugin`, `DiomanRegistration.instance`, `validateDiomanPlugins`, `sortDiomanPipeline`, `compileDiomanPipeline`, `diomanSetupPlugins`, `diomanBuiltinStages`, `diomanTransport`。

- `INV-source-diagnostics`（4 项）：内部表物理大小及屏障回收的白盒诊断，不提供产品管理能力。

`DiomanShareApi`, `DiomanShareApi.activeEntries`, `DiomanCacheApi.pendingWrites`, `DiomanCacheApi.entryCount`。

### 最终公共面与保留理由

`replaceOption` 保留标量覆盖策略；`resolveOption` 保留省略/true 沿用、false 关闭、optIn 及类型化合并/简写校验契约。`DiomanOptionKey` 按实例身份隔离插件选项，`StateKey` 按实例身份隔离逻辑请求状态，插件作者应使用稳定的非 const 键实例。`DiomanContext` 的 get/set、derive、wait、cancelled、markReplayable 等供自定义插件读取、派生、等待和声明重放；`DiomanPlugin`/`DiomanPluginInstance`/`DiomanNext`、阶段枚举与请求/响应工厂保留扩展契约。

`Dioman.pending` 是宿主管理活跃逻辑调用的语义计数；`DiomanLoadingApi.activeCount` 是宿主界面可消费的 loading 参与数；`DiomanOfflineApi.pending/flush` 和 `DiomanBreakerApi.stateOf/reset` 是宿主队列/断路器管理端口，均保留。`DiomanBreakerApi.bucketCount` 是插件规格 §9 明定的宿主桶容量管理指标，保留状态查询、keyOf/retryableAt/isOpen 的调度管理契约。`defaultAuthFailure` 是可复用的默认认证策略。它们与内部物理表大小有明确用途差异，逐项理由已登记到审计文件。

最终顶层公开面如下（其成员和构造参数共 744 项，以 JSON 清单为准）：

- `lib/src/client.dart`：`Dioman`。
- `lib/src/clock.dart`：`DiomanClock`。
- `lib/src/context.dart`：`DiomanLogger`, `StateKey`, `DiomanContext`。
- `lib/src/key.dart`：`DiomanKeyOptions`, `DiomanKeyService`。
- `lib/src/options.dart`：`replaceOption`, `DiomanOptionKey`, `resolveOption`, `DiomanCall`。
- `lib/src/plugin.dart`：`DiomanNext`, `DiomanPlugin`, `DiomanPluginInstance`。
- `lib/src/request.dart`：`DiomanRequest`, `RequestPatch`。
- `lib/src/response.dart`：`DiomanKind`, `Envelope`, `DiomanResponse`, `DiomanFailure`, `DiomanResponseFactory`。
- `lib/src/stages.dart`：`DiomanStage`, `DiomanEnforce`。
- `lib/src/plugins/loading.dart`：`DiomanLoadingOptions`, `DiomanLoadingApi`, `DiomanLoading`。
- `lib/src/plugins/notify.dart`：`DiomanNotify`。
- `lib/src/plugins/repath.dart`：`DiomanRepathOptions`, `DiomanRepath`。
- `lib/src/plugins/filter.dart`：`DiomanFilterPredicate`, `DiomanFilterOptions`, `DiomanFilter`。
- `lib/src/plugins/timeout.dart`：`NetworkQuality`, `DiomanTimeouts`, `DiomanTimeoutOptions`, `DiomanTimeout`。
- `lib/src/plugins/envs.dart`：`EnvRule`, `DiomanEnvsOptions`, `DiomanEnvs`。
- `lib/src/plugins/retry.dart`：`DiomanShouldRetry`, `DiomanRetryDelay`, `DiomanJitter`, `DiomanRetryOptions`, `DiomanRetry`。
- `lib/src/plugins/breaker.dart`：`DiomanBreakerState`, `DiomanShouldTrip`, `DiomanBreakerApi`, `DiomanBreakerOptions`, `DiomanBreaker`。
- `lib/src/plugins/auth.dart`：`DiomanAuthFailureAction`, `DiomanAuthNotice`, `DiomanAuthRefresh`, `DiomanAuthFailure`, `DiomanAuthReady`, `defaultAuthFailure`, `DiomanAuthOptions`, `DiomanAuth`。
- `lib/src/token_manager.dart`：`DiomanTokenManager`。
- `lib/src/cache_store.dart`：`DiomanCachePersist`。
- `lib/src/plugins/mock.dart`：`DiomanMockRoute`, `DiomanMockOptions`, `DiomanMock`。
- `lib/src/plugins/share.dart`：`DiomanSharePolicy`, `DiomanShareOptions`, `DiomanShare`。
- `lib/src/plugins/cache.dart`：`DiomanClonePolicy`, `DiomanCachePolicy`, `DiomanCacheOptions`, `DiomanCacheApi`, `DiomanCache`。
- `lib/src/plugins/offline.dart`：`DiomanOfflineOptions`, `DiomanOfflineApi`, `DiomanOffline`。

### 台账、总账与验证证据

台账 785 → 744，删除 41；总账 631 → 605，删除对应 API 行 29，新增 3 个 INV 行承接原白盒断言。内部化 API 不再有矩阵行或 apis 引用。[删行清单](pipeline-b5b-evidence/final-review-matrix-removed.json)、[重建台账输出](pipeline-b5b-evidence/final-review-inventory.txt)、[matrix sync](pipeline-b5b-evidence/final-review-matrix-sync.txt)。本次不修改基线文件，仍 190 项；G1 白名单仍为空。

[最终 gates](pipeline-b5b-evidence/gates.txt)：G0=0、G1=0、G2=0、G3=0、G4=190、G5=0。默认静态闸门测试继续通过，不使用基线掩盖静态缺口。

覆盖率脚本增加 diagnostics 纯导出文件的声明校验，仍逐一核对磁盘上全部 34 个源文件；五个 part 文件及 context_state 的可执行行/分支均有独立 SF 记录且全部命中，没有因拆分而免计执行代码。纯声明文件记 0/0。最终逐文件计数如下：

| lib/src 文件 | LF | LH | BRF | BRH |
|---|---:|---:|---:|---:|
| cache_store.dart | 0 | 0 | 0 | 0 |
| client.dart | 127 | 127 | 63 | 63 |
| client_internal.dart | 2 | 2 | 2 | 2 |
| clock.dart | 5 | 5 | 3 | 3 |
| config.dart | 36 | 36 | 22 | 22 |
| context.dart | 52 | 52 | 26 | 26 |
| context_internal.dart | 5 | 5 | 4 | 4 |
| context_state.dart | 26 | 26 | 17 | 17 |
| diagnostics.dart | 0 | 0 | 0 | 0 |
| key.dart | 54 | 54 | 27 | 27 |
| options.dart | 10 | 10 | 8 | 8 |
| pipeline.dart | 32 | 32 | 22 | 22 |
| plugin.dart | 5 | 5 | 5 | 5 |
| plugins/auth.dart | 122 | 122 | 59 | 59 |
| plugins/breaker.dart | 112 | 112 | 48 | 48 |
| plugins/cache.dart | 141 | 141 | 61 | 61 |
| plugins/cache_internal.dart | 2 | 2 | 2 | 2 |
| plugins/envs.dart | 11 | 11 | 8 | 8 |
| plugins/filter.dart | 39 | 39 | 19 | 19 |
| plugins/loading.dart | 58 | 58 | 32 | 32 |
| plugins/mock.dart | 44 | 44 | 19 | 19 |
| plugins/notify.dart | 19 | 19 | 12 | 12 |
| plugins/offline.dart | 63 | 63 | 28 | 28 |
| plugins/repath.dart | 50 | 50 | 23 | 23 |
| plugins/retry.dart | 94 | 94 | 39 | 39 |
| plugins/share.dart | 99 | 99 | 47 | 47 |
| plugins/share_internal.dart | 2 | 2 | 2 | 2 |
| plugins/timeout.dart | 22 | 22 | 13 | 13 |
| request.dart | 50 | 50 | 25 | 25 |
| response.dart | 108 | 108 | 27 | 27 |
| response_internal.dart | 2 | 2 | 1 | 1 |
| stages.dart | 0 | 0 | 0 | 0 |
| token_manager.dart | 0 | 0 | 0 | 0 |
| transport.dart | 18 | 18 | 11 | 11 |

合计：行 1410/1410，分支 675/675。[LCOV](pipeline-b5b-evidence/coverage.info)、[逐文件复算](pipeline-b5b-evidence/coverage.txt)、[覆盖测试](pipeline-b5b-evidence/coverage-tests.txt)。

变异脚本的源代码锚点仍有效，无需修改七项变异；重跑 leave-listener=256、loading-close=2304、notify-double=832、auth-singleflight=256、retry-replayable=192、cache-barrier=2176、mock-replayable=512，全部为 powerset 运行时断言失败，无编译/加载失败冒充；每项原字节及 SHA256 均恢复。[结果](pipeline-b5b-evidence/mutations.json)、[汇总](pipeline-b5b-evidence/mutation-summary.txt)。

`codex review --uncommitted` 两轮共发现两项成立 P2，均已修复：[完整审查](pipeline-b5b-evidence/final-review-codex-review.txt)。执行器把省略的 cache/share 请求覆盖映射为 null，遇到 optIn 插件导致场景默认能力被关闭。按原执行器契约映射为 true，显式 false 保留；未改变库插件的请求默认行为。新增实际缓存命中、并发合并及显式关闭回归全部通过；逐项撤掉两处修复产生 2 个运行时断言失败并恢复原字节。[回归](pipeline-b5b-evidence/final-review-executor-regressions.txt)、[逆向证明](pipeline-b5b-evidence/final-review-executor-reverse.txt)、[哈希](pipeline-b5b-evidence/final-review-executor-reverse.json)。

最终全仓 [dart analyze](pipeline-b5b-evidence/analyze.txt) 为 0 issue，含 [example/test/accept/benchmark 独立分析](pipeline-b5b-evidence/final-review-scoped-analyze.txt) 为 0 issue；[dart test](pipeline-b5b-evidence/tests.txt) 和含分支覆盖测试均全绿。最终状态、实际末尾和文件清单见 [收尾记录](pipeline-b5b-evidence/final-review-final-state.txt)。未提交、未 push、未切分支；SDK ^3.5.0 与依赖声明保持原样，无 tool/__pycache__。

复审的第二项成立 P2 是独立 share_prepare_probe 未启用请求级共享、POST 不在默认白名单、附件首发克隆即失败。[复审原文](pipeline-b5b-evidence/final-review-codex-review-after-fix.txt)。修复为显式启用 share 和 POST，首次克隆成功而重放克隆抛 FormatException；新增默认执行的真实回环集成回归运行完整探针，覆盖 HTTP/business 两种风格、首发/跟随者错误交付、每轮实际发送一次、在途数归零和 loading 配对。回归隔离产物写在工作区 .dart_tool 临时目录并清除，不写入外部服务验收的真实 PASS 账。[回环证据](pipeline-b5b-evidence/final-review-share-probe-regression.txt)。

本轮修改路径见 [文件清单](pipeline-b5b-evidence/final-review-files.txt)，包含 13 个库源文件/入口、执行器与探针、白盒测试/夹具、覆盖率复算工具、台账/总账和报告证据。迁移原始恒等式继续通过：[静态迁移闸门](pipeline-b5b-evidence/final-review-migration.txt)。

最终实际末尾：`No issues found!`；默认 `+5014: All tests passed!`；分支覆盖 `+5014: All tests passed!`。最终行 1410/1410、分支 675/675，34 文件全部核对。
