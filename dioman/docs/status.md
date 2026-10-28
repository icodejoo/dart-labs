---
title: dioman 当前状态与待办
status: active
updated: 2026-10-28
summary: 测试体系落地进度（P0–P3）、闸门现状、本轮修复与剩余待办，只写现在。
---
## TL;DR

P0–P3 完成，P2 只剩真实侧：G0/G1/G2/G3/G5 清零，基线是 G4 的 10 行 ② 档缺真实用例，外加 INV-11 一格因外部 testkit 改预期而失败。本轮另修了 auth 刷新窗口卡死、retry 恢复上游短路结果两个库 bug，把拦截器版 `DiomanMock` 换成传输层的 `DiomanMockAdapter`（Breaking）。

## 进度

| 阶段 | 状态 | 结果 |
|---|---|---|
| P0 搭账 | 完成 | `test/accept/lib/matrix.dart` + `test/accept/bin/matrix.dart`（sync/gates/evidence/results）；默认运行带静态闸门 `test/integration/matrix_integration_test.dart` |
| P1 定档 | 完成 | 约 440 行全部定档（含 26 条 INV 不变量行）；假设 H1–H8 见 `test/ASSUMPTIONS.md` |
| P2 补测 | 单测完成，真实侧剩 G4 | G3 199→0；执行器 6 处缺口修 4 处（retry/breaker 交回内置判定、share none、cancel.all 走插件），normalize/offline 有约束保留；H5 receive/send 本地真实核对；H6 经 413 注入部分核对 |
| P3 收口 | 完成 | 文档归入 docs/、accept 并入 test/accept/、证据汇总入库 `test/accept/evidence/` |

闸门：`dart run test/accept/bin/matrix.dart gates --lcov=coverage/local.info`（lcov 用 `dart test --coverage-path=coverage/local.info` 生成）。G4 现在也拦结论为 FAIL 的行。

## 本轮库改动（2026-10-28，见 CHANGELOG Unreleased）

- **插件间接线**：`_wireChain`/`_unwire` 统一处理 retry↔breaker、cache↔normalize，安装与每次插拔都重算。
- **DiomanKey**：来源优先级按注释改正；深模式递归排序。
- **DiomanCache**：新增 `shouldStore`；装了 normalize 时跳过业务失败；带 `x-dioman-mock` 标记的响应一律不存。
- **DiomanAuth**：同步抛错的 `onRefresh` 不再永久卡死刷新窗口；会话判定统一按"失败请求携带的 token"，重新登录后旧请求的失败不会清掉新会话，过期通知每个会话一次。
- **DiomanRetry**：只恢复自己放行过的请求，cache 命中等上游短路结果原样交出。
- **Mock**：删除拦截器版 `DiomanMock`，改为传输层 `DiomanMockAdapter`（包住真实 adapter，无顺序约束）。share 会合并相同的并发 mock 请求，retry/auth 重放会再次命中 mock，离线时 mock 请求也会排队，这些是有意的设计。

## 剩余待办

**真实侧**
- G4 的 10 行 ② 档缺真实用例：multipart 401 重放、keep-alive 重放（H4）、breaker 网络分类与半开探测取消、cancel 插件 dispose 在途、retry 网络错误类型、share retry 策略、connect/send 超时生效、INV-18 连接复用。多数要 testkit 新增场景。
- INV-11 FAIL：`plugins.single-auth@business`。外部 testkit `auth.json` 有未提交改动，把预期改成 ok:true；dioman 行为与改动前一致。等那边定稿，再判是改预期还是改执行器（执行器在装 auth 时也启用 EnvelopeTransformer）。
- 外部 testkit 的 `retry.429-retried`、`retry.503-retry-after`、`retry.respects-retry-after-over-delay` 等在场景 JSON 里显式 skip，需要那边去掉；CONTRACT §7 缺 mock/cache/share 组合语义。两段说明已交给用户转给 testkit 的会话。
- 两个 testkit 场景对 dioman 标为"不适用"（mock 在传输层的设计差异）：`combo.cache-mock-fallback-cached-once`、`combo.mock-share-fallback-single-flight`。

**执行器保留的映射**（有约束，未改）：normalize 的 EnvelopeTransformer 受 testkit D14 约束；offline 的 `maxWait=0` 是因为契约里没有排队语义。详见 `docs/reference/testkit-mapping.md`。

**闸门的已知弱点**：拆出来的 `#子点` 行与原行共用 api id，原行的单测会让子行也过 G3。

**库行为建议**（未改）：testkit 中立语义要求 filter 剔除 NaN，`DiomanFilter` 默认不剔除；`jsonEncode(double.nan)` 会抛错，默认剔除更安全。另一个边角：使用者的 `onRefresh` 若先写新 token 再抛错，现在会被当作新会话，不清也不通知。

## 已知问题

- `docs/reports/2026-10-27-*.md` 指向 `test/accept/results/…` 的是本地文件，仓库里没有；入库证据统一看 `test/accept/evidence/`。
