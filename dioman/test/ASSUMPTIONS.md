# 假设清单（第 ② 档的前提）

单测里的替身替真实传输、真实服务做了假设。这里把每条假设写成能被证伪的一句话，配上真实核对方法。规则见 [测试体系方案 §3](../docs/design/test-matrix-plan.md)。

- 核对状态只有四种：**已核对**（注明平台、日期、数字）/ **未核对** / **存疑** / **已证伪**。
- 被证伪时，假实现和依赖它的单测一起改，不能只改产品代码。
- 升级 dio、Dart SDK 后，把相关条目改回"未核对"。当前基准：dio 5.11.1。
- 矩阵行通过 `assumptions` 字段引用这里的编号；闸门 G4 会拦截引用"已证伪"假设的行。
- 契约替身（`TestTokens`、`FakeCachePersist`、`AsyncOnlyCachePersist`、`isOnline` 回调）模拟的是使用者注入的实现，不在本清单里，契约写在 API 文档。

| 编号 | 假设（可证伪的一句话） | 出处 | 依赖它的单测 | 核对状态 | 核对方法 | 关联矩阵行 |
|---|---|---|---|---|---|---|
| H1 | 适配器不理会 `cancelFuture` 时，Dio 仍会在 CancelToken 取消时立即以 `DioExceptionType.cancel` 结束请求 | `test/support/fixtures.dart` `BucketAdapter.fetch`、`RecordingAdapter.fetch` 均忽略 `cancelFuture` | `rule/cancel_rule_test`、`boundary/retry_boundary_test`、`boundary/share_boundary_test`、`combo/auth_cancel_combo_test`、`combo/cancel_share_combo_test`、`combo/cancel_retry_combo_test`、`combo/auth_share_combo_test`、`combo/loading_share_combo_test`、`combo/retry_share_*` 中用假适配器的取消用例 | 已核对（源码，dio 5.11.1，2026-10-28）：`dio_mixin.dart:781` `listenCancelForAsyncTask` 用 `Future.any` 让 `whenCancel` 与拦截器/派发赛跑；真实侧 `cancel.single` normal/weak/offline × 双风格 6/6 通过（2026-10-27） | 读源码；真实服务上取消在途请求，读回错误类型与耗时 | 取消相关行（P1 回填） |
| H1b | 取消后底层请求被中止，服务端不再继续处理、连接被释放 | 假适配器在取消后 fetch 仍继续运行，只是结果被丢弃（`CancelableOperation.cancel`） | 断言"取消后服务端命中数/资源释放"的用例（P1 逐条标注） | 未核对 | 真实服务上取消在途请求，读服务端 `X-Test-Run` 命中计数与代理连接数 | 同上 |
| H2 | 请求体流是否已被适配器消费，不影响插件重放（retry/auth/share 重发） | `BucketAdapter.fetch` 不读 `requestStream`；`RecordingAdapter.fetch` 会 drain | `unit/replay_support_test`（`prepareForReplay`）、`boundary/auth_replay_boundary_test`、`boundary/retry_boundary_test`、`combo/cancel_share_takeover_combo_test` | 已核对（真实服务，2026-10-27）：`share_prepare_probe` multipart 重放准备失败，http/business 2/2 通过 | `dart run test/accept/bin/share_prepare_probe.dart`；补一条 multipart 正常重放成功的真实用例 | 重放相关行（P1 回填） |
| H3 | 真实网络故障（连接拒绝、DNS 失败、连接中断）时，Dio 报出的 `DioExceptionType` 与单测直接构造的 `connectionError` 一致 | `rule/breaker_rule_test:315`、`boundary/share_boundary_test:185,264` 直接构造 `DioExceptionType.connectionError` | 上述用例，及 retry/breaker 按错误类型判定的用例 | 未核对 | 真实环境分别制造连接拒绝（关端口）、DNS 失败、中途断开（netem flap），记录 `type` 与 `error` 运行时类型 | retry/breaker 错误分类行（P1 回填） |
| H4 | 连接复用（keep-alive）不改变插件的结论 | `test/support/test_server.dart` `respondJson` 强制 `Connection: close` | 所有走 `TestServer` 的用例 | 存疑：强制短连接本身就是为了规避 Dio 不读完非 2xx 响应体、复用连接时读到残留字节的问题（见夹具注释），说明真实复用场景有已知风险 | 真实服务上开 keep-alive，连续发"非 2xx → 2xx"请求，核对第二个响应体 | 待定 |
| H5 | `DiomanTimeout` 改写的请求级 `connectTimeout`/`receiveTimeout`/`sendTimeout` 会被 Dio 真正执行，超时后报对应类型 | timeout 插件只改 `RequestOptions`，单测断言配置值 | `rule/timeout_rule_test`、`boundary/timeout_boundary_test` | 未核对（真实矩阵 timeout 边界 8/8 通过，但需逐格确认断言的是错误类型与耗时，而不只是配置值） | 真实服务慢响应 + netem 黑洞，记录错误类型与实际耗时（≥3 次取全部样本） | timeout 行（P1 回填） |
| H6 | 真实服务返回的 `Retry-After`（秒数、HTTP 日期）能被 retry 正确解析并按它等待 | `rule/retry_rule_test:166-177` 由本地 `TestServer` 设置响应头 | `rule/retry_rule_test` 的 Retry-After 用例 | **部分已核对**（normal@http，2026-10-28）：`retry.single-retry-after-honored` 用 413 注入 `Retry-After: 2`，delay=50ms 时确实等够 2s；`ignored`/`override` 两条也通过。HTTP 日期格式与 429/503 路径仍未核对：执行器已改为放行注入的 429/503（按响应体 `reason: injected` 区分真实过载），但 testkit 的 `retry.503-retry-after` 等场景在场景 JSON 里显式写了 skip | 解锁剩余部分：去掉 testkit `scenarios/retry.json` 等处的显式 skip（外部仓库） | `DiomanRetry.respectRetryAfter` 等 |
| H7 | 假适配器返回的响应在下一个微任务内就到达，不会和计时器（loading 延迟、share 窗口、retry 退避）交错出现真实环境才有的顺序 | 两个假适配器都是 `async` 直接返回 | `rule/loading_rule_test`、`boundary/loading_boundary_test`、`combo/*_loading_*`、`combo/*share*` 中用假适配器的用例 | 未核对 | 真实弱网（netem weak）下跑 loading/share 代表场景，核对事件顺序 | loading/share 时序行（P1 回填） |
| H8 | 请求在适配器层不会被静默丢弃：每次 fetch 要么返回、要么抛错 | 假适配器的 fetch 永远会完成（`gates` 卡住时由测试主动放行） | 计数类断言（`calls == n`）的用例 | 未核对 | 真实丢包网络（netem lossy）下核对请求最终都有结局，无悬挂 | 待定 |

## 变更记录

- 2026-10-28：H6 经 413 注入场景部分核对；执行器放行注入的 429/503。
- 2026-10-28：H5 扩到 sendTimeout（P1 定档时发现）。
- 2026-10-28：初版，H1–H6 来自方案初稿，补 H1b、H7、H8；H1 源码核对，H2 引用 share 专项真实结果，H6 发现真实侧一直跳过。
