---
title: dioman 当前状态与待办
status: active
updated: 2026-10-28
summary: 测试体系落地进度（P0–P3）、闸门现状、本轮修复与剩余待办，只写现在。
---
## TL;DR

P0–P3 全部完成。闸门 G0/G1/G2/G3/G5 清零，G4 只剩 connect 超时一行（testkit D22 判定黑盒不可测，本地回环也测不到）。总账里没有 FAIL 或 BLOCKED 的行。testkit 已按 dioman 的提议补齐场景与契约（D20–D23），dioman 执行器支持了新能力，并在新服务端实例上实跑通过。

## 进度

| 阶段 | 状态 | 结果 |
|---|---|---|
| P0 搭账 | 完成 | `test/accept/lib/matrix.dart` + `test/accept/bin/matrix.dart`（sync/gates/evidence/results）；默认运行带静态闸门 `test/integration/matrix_integration_test.dart` |
| P1 定档 | 完成 | 约 440 行全部定档（含 26 条 INV 不变量行）；假设 H1–H8 见 `test/ASSUMPTIONS.md` |
| P2 补测 | 完成（剩 connect 超时，不可测） | G3 199→0；G4 真实侧 10 行补到只剩 1 行；执行器修 4 处缺口、对齐 D21；H1b/H4/H5 本地真实回环核对，H2/H4/H6（秒数）经 testkit 新场景真实核对 |
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

- **connect 超时生效**（`DiomanTimeouts.connect#effective`）：testkit D22 判定 netem 在用户态无法阻止内核完成握手，黑盒测不到；本地回环上只会立即拒绝。保持阻塞，只有受控网络环境才能核对。
- **Retry-After 的 HTTP 日期格式**：testkit 服务端目前只能输出整数秒（testkit CONTRACT §3），本地单测覆盖了日期解析，真实侧未核对。
- **testkit 新能力需要新服务端二进制**：47080/47090 上跑的若是旧版，新场景要用新实例跑（`TESTKIT_SERVER`/`TESTKIT_NETEM`，步骤见 `docs/guides/accept-runner.md`）。
- dioman 不具备 `mock-in-chain` 能力（mock 在传输层），`combo.cache-mock-fallback-cached-once`、`combo.mock-share-fallback-single-flight` 按缺能力跳过。

**执行器保留的映射**（有约束，未改）：normalize 的 EnvelopeTransformer 受 testkit D14 约束；offline 的 `maxWait=0` 是因为契约里没有排队语义。详见 `docs/reference/testkit-mapping.md`。

**闸门的已知弱点**：拆出来的 `#子点` 行与原行共用 api id，原行的单测会让子行也过 G3。

**库行为建议**（未改）：testkit 中立语义要求 filter 剔除 NaN，`DiomanFilter` 默认不剔除；`jsonEncode(double.nan)` 会抛错，默认剔除更安全。另一个边角：使用者的 `onRefresh` 若先写新 token 再抛错，现在会被当作新会话，不清也不通知。

## 已知问题

- `docs/reports/2026-10-27-*.md` 指向 `test/accept/results/…` 的是本地文件，仓库里没有；入库证据统一看 `test/accept/evidence/`。
