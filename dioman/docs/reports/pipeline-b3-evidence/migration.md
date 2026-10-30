| 迁移来源行 | 原 ID | 分类 | 承接用例 | 范围说明 |
|---|---|---|---|---|
| boundary.md:10 | T0001 | change | `test/boundary/b3_options_boundary_test.dart:136` — [DiomanAuth.expiresAt] 并发主动刷新各轮一次，无失败首发；刷新失败等待者同为 expired |  |
| boundary.md:11 | T0002 | change | `test/boundary/b3_options_boundary_test.dart:40` — [defaultAuthFailure] 刷新窗口关闭后旧请求的 401 直接重放，整轮仅刷新一次 |  |
| boundary.md:12 | T0003 | change | `test/boundary/b3_options_boundary_test.dart:40` — [defaultAuthFailure] 刷新窗口关闭后旧请求的 401 直接重放，整轮仅刷新一次 |  |
| boundary.md:13 | T0004 | change | `test/boundary/b3_options_boundary_test.dart:136` — [DiomanAuth.expiresAt] 并发主动刷新各轮一次，无失败首发；刷新失败等待者同为 expired |  |
| boundary.md:14 | T0005 | keep | `test/boundary/b3_options_boundary_test.dart:18` — [DiomanAuth.onAccessExpired] 刷新后仍为 401 的并发请求全部 expired，每会话只通知一次 |  |
| boundary.md:15 | T0006 | keep | `test/boundary/auth_boundary_test.dart:154` — [DiomanAuth.onRefresh] 同步与异步抛错释放窗口，失败清会话只通知一次并可同名重登 |  |
| boundary.md:16 | T0007 | keep | `test/boundary/auth_boundary_test.dart:280` — [DiomanAuth.onFailure] internal cancel 不路由，network timeout parse 仍路由且默认 others |  |
| boundary.md:17 | T0008 | change | `test/rule/auth_rule_test.dart:123` — [DiomanAuth.onFailure] 自定义五动作、仅重放一次和非鉴权结果返回 |  |
| boundary.md:18 | T0009 | change | `test/rule/auth_rule_test.dart:23` — [defaultAuthFailure] 默认判定覆盖无 token、旧 token、逻辑 401 403 与其它失败 |  |
| boundary.md:19 | T0010 | change | `test/boundary/b3_options_boundary_test.dart:180` — [DiomanAuth.ready] buildHeader expiresAt 在首发和重放抛错均原样且收尾 |  |
| boundary.md:20 | T0011 | keep | `test/boundary/auth_boundary_test.dart:235` — [DiomanAuth.onAccessExpired] 旧请求的 expired 与刷新失败均不清新会话，迟到 401 直接 replay |  |
| boundary.md:21 | T0012 | keep | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| boundary.md:22 | T0013 | change | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| boundary.md:23 | T0014 | keep | `test/boundary/auth_boundary_test.dart:235` — [DiomanAuth.onAccessExpired] 旧请求的 expired 与刷新失败均不清新会话，迟到 401 直接 replay |  |
| boundary.md:24 | T0015 | keep | `test/boundary/auth_boundary_test.dart:154` — [DiomanAuth.onRefresh] 同步与异步抛错释放窗口，失败清会话只通知一次并可同名重登 |  |
| boundary.md:25 | T0016 | keep | `test/boundary/auth_boundary_test.dart:154` — [DiomanAuth.onRefresh] 同步与异步抛错释放窗口，失败清会话只通知一次并可同名重登 |  |
| boundary.md:26 | T0017 | keep | `test/boundary/auth_boundary_test.dart:235` — [DiomanAuth.onAccessExpired] 旧请求的 expired 与刷新失败均不清新会话，迟到 401 直接 replay |  |
| boundary.md:27 | T0018 | keep | `test/boundary/auth_boundary_test.dart:154` — [DiomanAuth.onRefresh] 同步与异步抛错释放窗口，失败清会话只通知一次并可同名重登 |  |
| boundary.md:28 | T0019 | keep | `test/boundary/auth_boundary_test.dart:154` — [DiomanAuth.onRefresh] 同步与异步抛错释放窗口，失败清会话只通知一次并可同名重登 |  |
| boundary.md:29 | T0024 | keep | `test/boundary/breaker_boundary_test.dart:61` — [DiomanBreaker.shouldTrip] cancel 只归还名额，不清连续失败也不计失败，半开可继续探测 |  |
| boundary.md:30 | T0025 | keep | `test/boundary/breaker_boundary_test.dart:171` — [DiomanBreaker.idleTtl] TTL 与软上限只淘汰安全桶，保留失败和打开半开在途桶 |  |
| boundary.md:31 | T0026 | keep | `test/boundary/breaker_boundary_test.dart:171` — [DiomanBreaker.idleTtl] TTL 与软上限只淘汰安全桶，保留失败和打开半开在途桶 |  |
| boundary.md:32 | T0027 | keep | `test/boundary/breaker_boundary_test.dart:96` — [DiomanBreaker.halfOpenMaxCalls] 真实取消探测释放槽位，旧窗口结果不污染新窗口 |  |
| boundary.md:33 | T0028 | keep | `test/boundary/b3_options_boundary_test.dart:209` — [DiomanBreaker.idleTtl] open halfOpen 与 closed 在途桶不回收，安全桶回收后同键从 closed 开始 |  |
| boundary.md:34 | T0029 | keep | `test/boundary/breaker_boundary_test.dart:171` — [DiomanBreaker.idleTtl] TTL 与软上限只淘汰安全桶，保留失败和打开半开在途桶 |  |
| boundary.md:35 | T0030 | keep | `test/boundary/breaker_boundary_test.dart:171` — [DiomanBreaker.idleTtl] TTL 与软上限只淘汰安全桶，保留失败和打开半开在途桶 |  |
| boundary.md:36 | T0031 | keep | `test/boundary/b3_options_boundary_test.dart:209` — [DiomanBreaker.idleTtl] open halfOpen 与 closed 在途桶不回收，安全桶回收后同键从 closed 开始 |  |
| boundary.md:37 | T0032 | keep | `test/boundary/b3_options_boundary_test.dart:209` — [DiomanBreaker.idleTtl] open halfOpen 与 closed 在途桶不回收，安全桶回收后同键从 closed 开始 |  |
| boundary.md:38 | T0033 | keep | `test/boundary/breaker_boundary_test.dart:96` — [DiomanBreaker.halfOpenMaxCalls] 真实取消探测释放槽位，旧窗口结果不污染新窗口 |  |
| boundary.md:39 | T0034 | keep | `test/boundary/breaker_boundary_test.dart:96` — [DiomanBreaker.halfOpenMaxCalls] 真实取消探测释放槽位，旧窗口结果不污染新窗口 |  |
| boundary.md:40 | T0035 | change | `test/boundary/b3_options_boundary_test.dart:261` — [DiomanBreaker.shouldTrip] Dio 连接与三种超时只计一次，成功清连续失败且非正数不钳制 |  |
| boundary.md:41 | T0036 | change | `test/boundary/b3_options_boundary_test.dart:261` — [DiomanBreaker.shouldTrip] Dio 连接与三种超时只计一次，成功清连续失败且非正数不钳制 |  |
| boundary.md:42 | T0037 | change | `test/boundary/b3_options_boundary_test.dart:261` — [DiomanBreaker.shouldTrip] Dio 连接与三种超时只计一次，成功清连续失败且非正数不钳制 |  |
| boundary.md:43 | T0038 | change | `test/boundary/b3_options_boundary_test.dart:261` — [DiomanBreaker.shouldTrip] Dio 连接与三种超时只计一次，成功清连续失败且非正数不钳制 |  |
| boundary.md:44 | T0039 | keep | `test/boundary/breaker_boundary_test.dart:96` — [DiomanBreaker.halfOpenMaxCalls] 真实取消探测释放槽位，旧窗口结果不污染新窗口 |  |
| boundary.md:45 | T0040 | change | `test/rule/breaker_rule_test.dart:177` — [DiomanBreaker.onStateChange] 通知异常隔离，判定与 keyBuilder 异常原样落定 |  |
| boundary.md:80 | T0076 | keep | `test/rule/retry_rule_test.dart:55` — [DiomanRetry.shouldRetry] 类别硬否决先于回调，network timeout 默认重试 |  |
| boundary.md:81 | T0077 | change | `test/boundary/retry_boundary_test.dart:111` — [DiomanContext.wait] 退避取消含订阅前取消，禁止再次进入内层 |  |
| boundary.md:82 | T0078 | keep | `test/boundary/retry_boundary_test.dart:111` — [DiomanContext.wait] 退避取消含订阅前取消，禁止再次进入内层 |  |
| boundary.md:83 | T0079 | change | `test/boundary/retry_boundary_test.dart:139` — [DiomanRetry.onRetry] 通知抛错隔离并记日志，通知取消不重发 |  |
| boundary.md:84 | T0080 | change | `test/boundary/retry_boundary_test.dart:175` — [DiomanRetry.shouldRetry] shouldRetry delay jitter 程序错误原样落定，internal 不重试 |  |
| boundary.md:85 | T0081 | keep | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| boundary.md:86 | T0082 | change | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| combo.md:10 | T0102 | keep | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:11 | T0103 | change | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:12 | T0104 | change | `test/combo/b3_outer_combo_test.dart:76` — [DiomanAuth.onAccessDenied] 本地无凭证拒绝也释放 loading 与 pending，最终通知一次 |  |
| combo.md:13 | T0105 | change | `test/boundary/auth_boundary_test.dart:186` — [DiomanAuth.onRefresh] 发起者等待者取消和 cancelAll 不终止刷新，成功写 token 失败清会话 |  |
| combo.md:14 | T0106 | change | `test/combo/b3_outer_combo_test.dart:41` — [Dioman.cancelAll] 重放等待时 cancelAll 完整注销，loading 配对且 notify 不通知 |  |
| combo.md:15 | T0107 | change | `test/combo/b3_outer_combo_test.dart:41` — [Dioman.cancelAll] 重放等待时 cancelAll 完整注销，loading 配对且 notify 不通知 |  |
| combo.md:16 | T0108 | change | `test/boundary/auth_boundary_test.dart:186` — [DiomanAuth.onRefresh] 发起者等待者取消和 cancelAll 不终止刷新，成功写 token 失败清会话 |  |
| combo.md:17 | T0109 | keep | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 |  |
| combo.md:18 | T0110 | change | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 |  |
| combo.md:19 | T0111 | change | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 |  |
| combo.md:20 | T0112 | keep | `test/boundary/auth_boundary_test.dart:186` — [DiomanAuth.onRefresh] 发起者等待者取消和 cancelAll 不终止刷新，成功写 token 失败清会话 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:21 | T0113 | change | `test/boundary/auth_boundary_test.dart:186` — [DiomanAuth.onRefresh] 发起者等待者取消和 cancelAll 不终止刷新，成功写 token 失败清会话 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:22 | T0114 | change | `test/combo/b3_combo_test.dart:28` — [DiomanRetry.max × DiomanAuth.onRefresh] 刷新不占重试预算，isProtected 每次尝试一次，重放不重算 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:23 | T0115 | change | `test/boundary/auth_boundary_test.dart:322` — [DiomanAuth.onAccessExpired] 通知同步异步抛错隔离，判定和 ready 异常原样抛出 |  |
| combo.md:24 | T0116 | keep | `test/combo/b3_combo_test.dart:28` — [DiomanRetry.max × DiomanAuth.onRefresh] 刷新不占重试预算，isProtected 每次尝试一次，重放不重算 |  |
| combo.md:25 | T0118 | change | `test/boundary/b3_options_boundary_test.dart:180` — [DiomanAuth.ready] buildHeader expiresAt 在首发和重放抛错均原样且收尾 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:26 | T0119 | change | `test/boundary/b3_options_boundary_test.dart:180` — [DiomanAuth.ready] buildHeader expiresAt 在首发和重放抛错均原样且收尾 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:27 | T0120 | change | `test/boundary/auth_boundary_test.dart:322` — [DiomanAuth.onAccessExpired] 通知同步异步抛错隔离，判定和 ready 异常原样抛出 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:28 | T0121 | change | `test/boundary/auth_boundary_test.dart:322` — [DiomanAuth.onAccessExpired] 通知同步异步抛错隔离，判定和 ready 异常原样抛出 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:29 | T0122 | keep | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:30 | T0123 | keep | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:31 | T0124 | change | `test/boundary/auth_boundary_test.dart:322` — [DiomanAuth.onAccessExpired] 通知同步异步抛错隔离，判定和 ready 异常原样抛出 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:32 | T0125 | keep | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:33 | T0126 | change | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:34 | T0127 | change | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:35 | T0128 | keep | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:36 | T0129 | change | `test/boundary/auth_boundary_test.dart:186` — [DiomanAuth.onRefresh] 发起者等待者取消和 cancelAll 不终止刷新，成功写 token 失败清会话 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:37 | T0130 | keep | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:38 | T0131 | keep | `test/combo/b3_combo_test.dart:12` — [DiomanRetry.max × DiomanBreaker.failureThreshold] 每次尝试计数，打开返回 breaker 后停止重试，无需接线 |  |
| combo.md:39 | T0132 | keep | `test/combo/b3_combo_test.dart:12` — [DiomanRetry.max × DiomanBreaker.failureThreshold] 每次尝试计数，打开返回 breaker 后停止重试，无需接线 |  |
| combo.md:40 | T0133 | change | `test/combo/b3_combo_test.dart:12` — [DiomanRetry.max × DiomanBreaker.failureThreshold] 每次尝试计数，打开返回 breaker 后停止重试，无需接线 |  |
| combo.md:71 | T0164 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:72 | T0165 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:76 | T0169 | change | `test/boundary/retry_boundary_test.dart:111` — [DiomanContext.wait] 退避取消含订阅前取消，禁止再次进入内层 |  |
| combo.md:77 | T0170 | change | `test/boundary/retry_boundary_test.dart:111` — [DiomanContext.wait] 退避取消含订阅前取消，禁止再次进入内层 |  |
| combo.md:85 | T0178 | change | `test/boundary/auth_boundary_test.dart:186` — [DiomanAuth.onRefresh] 发起者等待者取消和 cancelAll 不终止刷新，成功写 token 失败清会话 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:89 | T0182 | change | `test/boundary/retry_boundary_test.dart:111` — [DiomanContext.wait] 退避取消含订阅前取消，禁止再次进入内层 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:91 | T0184 | change | `test/boundary/retry_boundary_test.dart:111` — [DiomanContext.wait] 退避取消含订阅前取消，禁止再次进入内层 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:93 | T0186 | keep | `test/combo/b3_outer_combo_test.dart:12` — [DiomanLoadingApi.activeCount × DiomanNotify.notify × DiomanRetry.max] 重试全过程 loading 一对，最终失败一次通知成功零次 |  |
| combo.md:101 | T0194 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:102 | T0195 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:103 | T0196 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:104 | T0197 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:105 | T0198 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:106 | T0199 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:108 | T0201 | change | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| combo.md:109 | T0202 | change | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| combo.md:117 | T0210 | keep | `test/boundary/retry_boundary_test.dart:111` — [DiomanContext.wait] 退避取消含订阅前取消，禁止再次进入内层 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:118 | T0211 | keep | `test/boundary/retry_boundary_test.dart:111` — [DiomanContext.wait] 退避取消含订阅前取消，禁止再次进入内层 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:119 | T0212 | change | `test/boundary/retry_boundary_test.dart:139` — [DiomanRetry.onRetry] 通知抛错隔离并记日志，通知取消不重发 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:120 | T0213 | change | `test/boundary/retry_boundary_test.dart:175` — [DiomanRetry.shouldRetry] shouldRetry delay jitter 程序错误原样落定，internal 不重试 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:121 | T0214 | change | `test/boundary/retry_boundary_test.dart:175` — [DiomanRetry.shouldRetry] shouldRetry delay jitter 程序错误原样落定，internal 不重试 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:122 | T0215 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:123 | T0216 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:124 | T0217 | keep | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:125 | T0218 | change | `test/combo/b3_combo_test.dart:171` — [DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| combo.md:126 | T0219 | change | `test/boundary/retry_boundary_test.dart:175` — [DiomanRetry.shouldRetry] shouldRetry delay jitter 程序错误原样落定，internal 不重试 | 已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。 |
| integration.md:10 | T0020 | change | `test/integration/b3_transport_integration_test.dart:151` — [Dioman.use × DiomanBreakerApi.stateOf] 插入移除替换熔断器使用新实例，dispose 拒绝复活 |  |
| integration.md:11 | T0021 | keep | `test/integration/b3_transport_integration_test.dart:22` — [DiomanAuth.setup] 同配置不同客户端刷新窗口隔离，dispose 后新客户端正常刷新 |  |
| integration.md:12 | T0022 | keep | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| integration.md:13 | T0023 | keep | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| integration.md:39 | T0242 | change | `test/integration/b3_transport_integration_test.dart:151` — [Dioman.use × DiomanBreakerApi.stateOf] 插入移除替换熔断器使用新实例，dispose 拒绝复活 |  |
| integration.md:40 | T0243 | change | `test/integration/b3_transport_integration_test.dart:151` — [Dioman.use × DiomanBreakerApi.stateOf] 插入移除替换熔断器使用新实例，dispose 拒绝复活 |  |
| integration.md:41 | T0244 | change | `test/integration/b3_transport_integration_test.dart:151` — [Dioman.use × DiomanBreakerApi.stateOf] 插入移除替换熔断器使用新实例，dispose 拒绝复活 |  |
| integration.md:55 | DiomanAuth.dio#transport-reuse | keep | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| integration.md:89 | DiomanRetry.respectRetryAfter#real-header | keep | `test/integration/b3_transport_integration_test.dart:113` — [DiomanRetry.respectRetryAfter] 真实 429 503 秒数与日期通过 DiomanClock 等待 |  |
| rule.md:10 | T0253 | keep | `test/rule/auth_rule_test.dart:152` — [DiomanAuth.expiresAt] 主动刷新只一次、空过期时间不刷新、提前量请求覆盖 |  |
| rule.md:11 | T0254 | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:12 | T0255 | change | `test/rule/auth_rule_test.dart:152` — [DiomanAuth.expiresAt] 主动刷新只一次、空过期时间不刷新、提前量请求覆盖 |  |
| rule.md:13 | T0256 | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:14 | T0257 | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:15 | T0258 | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:16 | T0259 | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:17 | T0260 | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:18 | T0261 | keep | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:19 | T0262 | keep | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| rule.md:20 | T0263 | keep | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 |  |
| rule.md:21 | T0264 | keep | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:22 | T0265 | keep | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 |  |
| rule.md:23 | T0266 | change | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 |  |
| rule.md:24 | T0267 | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:25 | T0268 | keep | `test/boundary/b3_options_boundary_test.dart:99` — [DiomanAuthOptions.headerKey] 自定义头和格式、ready 优先，过期通知与 expiresAt 请求覆盖 |  |
| rule.md:26 | T0269 | keep | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 |  |
| rule.md:27 | T0270 | keep | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:28 | T0271 | keep | `test/rule/auth_rule_test.dart:152` — [DiomanAuth.expiresAt] 主动刷新只一次、空过期时间不刷新、提前量请求覆盖 |  |
| rule.md:29 | T0272 | keep | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:30 | T0273 | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:31 | T0274 | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:36 | T0279 | keep | `test/boundary/b3_options_boundary_test.dart:99` — [DiomanAuthOptions.headerKey] 自定义头和格式、ready 优先，过期通知与 expiresAt 请求覆盖 |  |
| rule.md:37 | T0280 | keep | `test/boundary/b3_options_boundary_test.dart:99` — [DiomanAuthOptions.headerKey] 自定义头和格式、ready 优先，过期通知与 expiresAt 请求覆盖 |  |
| rule.md:39 | T0282 | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:40 | T0283 | keep | `test/boundary/breaker_boundary_test.dart:61` — [DiomanBreaker.shouldTrip] cancel 只归还名额，不清连续失败也不计失败，半开可继续探测 |  |
| rule.md:41 | T0284 | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:42 | T0285 | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:43 | T0286 | change | `test/rule/breaker_rule_test.dart:40` — [DiomanBreaker.defaultMaxBuckets] 默认回收一小时和一千桶软上限 |  |
| rule.md:44 | T0287 | change | `test/rule/breaker_rule_test.dart:40` — [DiomanBreaker.defaultMaxBuckets] 默认回收一小时和一千桶软上限 |  |
| rule.md:45 | T0288 | change | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:46 | T0289 | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:47 | T0290 | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:48 | T0291 | change | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:49 | T0292 | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:50 | T0293 | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:51 | T0294 | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:52 | T0295 | change | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:53 | T0296 | change | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:54 | T0297 | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:55 | T0298 | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:56 | T0299 | keep | `test/boundary/breaker_boundary_test.dart:171` — [DiomanBreaker.idleTtl] TTL 与软上限只淘汰安全桶，保留失败和打开半开在途桶 |  |
| rule.md:57 | T0300 | keep | `test/boundary/breaker_boundary_test.dart:171` — [DiomanBreaker.idleTtl] TTL 与软上限只淘汰安全桶，保留失败和打开半开在途桶 |  |
| rule.md:58 | T0301 | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:59 | T0302 | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:191 | T0440 | keep | `test/boundary/retry_boundary_test.dart:10` — [DiomanRetry.respectRetryAfter] 秒数、空白、HTTP 日期、无效值和独立封顶 |  |
| rule.md:192 | T0441 | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:193 | T0442 | keep | `test/boundary/retry_boundary_test.dart:10` — [DiomanRetry.respectRetryAfter] 秒数、空白、HTTP 日期、无效值和独立封顶 |  |
| rule.md:194 | T0443 | keep | `test/boundary/retry_boundary_test.dart:10` — [DiomanRetry.respectRetryAfter] 秒数、空白、HTTP 日期、无效值和独立封顶 |  |
| rule.md:195 | T0444 | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:196 | T0445 | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:197 | T0446 | keep | `test/boundary/retry_boundary_test.dart:10` — [DiomanRetry.respectRetryAfter] 秒数、空白、HTTP 日期、无效值和独立封顶 |  |
| rule.md:198 | T0447 | keep | `test/boundary/retry_boundary_test.dart:10` — [DiomanRetry.respectRetryAfter] 秒数、空白、HTTP 日期、无效值和独立封顶 |  |
| rule.md:199 | T0448 | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:200 | T0449 | change | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| rule.md:201 | T0450 | keep | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| rule.md:202 | T0451 | change | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| rule.md:203 | T0452 | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:204 | T0453 | keep | `test/rule/retry_rule_test.dart:91` — [DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关 |  |
| rule.md:205 | T0454 | keep | `test/rule/retry_rule_test.dart:55` — [DiomanRetry.shouldRetry] 类别硬否决先于回调，network timeout 默认重试 |  |
| rule.md:206 | T0455 | keep | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| rule.md:207 | T0456 | keep | `test/rule/retry_rule_test.dart:91` — [DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关 |  |
| rule.md:208 | T0457 | keep | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| rule.md:209 | T0458 | keep | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| rule.md:210 | T0459 | change | `test/rule/retry_rule_test.dart:91` — [DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关 |  |
| rule.md:211 | T0460 | change | `test/rule/retry_rule_test.dart:91` — [DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关 |  |
| rule.md:212 | T0461 | change | `test/rule/retry_rule_test.dart:91` — [DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关 |  |
| rule.md:213 | T0462 | change | `test/boundary/retry_options_boundary_test.dart:100` — [DiomanRetryOptions.shouldRetry] 请求判定覆盖插件判定，状态表与方法按请求替换 |  |
| rule.md:214 | T0463 | keep | `test/boundary/retry_options_boundary_test.dart:100` — [DiomanRetryOptions.shouldRetry] 请求判定覆盖插件判定，状态表与方法按请求替换 |  |
| rule.md:215 | T0464 | keep | `test/boundary/retry_options_boundary_test.dart:100` — [DiomanRetryOptions.shouldRetry] 请求判定覆盖插件判定，状态表与方法按请求替换 |  |
| rule.md:216 | T0465 | keep | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| rule.md:253 | DiomanAuth.enabled | keep | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 |  |
| rule.md:254 | DiomanAuth.name | keep | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:255 | DiomanAuth.new(buildHeader) | keep | `test/boundary/b3_options_boundary_test.dart:99` — [DiomanAuthOptions.headerKey] 自定义头和格式、ready 优先，过期通知与 expiresAt 请求覆盖 |  |
| rule.md:256 | DiomanAuth.new(expiresAt) | keep | `test/rule/auth_rule_test.dart:152` — [DiomanAuth.expiresAt] 主动刷新只一次、空过期时间不刷新、提前量请求覆盖 |  |
| rule.md:257 | DiomanAuth.new(headerKey) | keep | `test/boundary/b3_options_boundary_test.dart:99` — [DiomanAuthOptions.headerKey] 自定义头和格式、ready 优先，过期通知与 expiresAt 请求覆盖 |  |
| rule.md:258 | DiomanAuth.new(isProtected) | keep | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 |  |
| rule.md:259 | DiomanAuth.new(now) | keep | `test/rule/auth_rule_test.dart:152` — [DiomanAuth.expiresAt] 主动刷新只一次、空过期时间不刷新、提前量请求覆盖 |  |
| rule.md:260 | DiomanAuth.new(onAccessDenied) | keep | `test/rule/auth_rule_test.dart:92` — [DiomanAuth.onAccessDenied] 本地无 token 每请求通知一次，空串等价未登录，默认回退 expired |  |
| rule.md:261 | DiomanAuth.new(onAccessExpired) | keep | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:262 | DiomanAuth.new(onFailure) | keep | `test/rule/auth_rule_test.dart:123` — [DiomanAuth.onFailure] 自定义五动作、仅重放一次和非鉴权结果返回 |  |
| rule.md:263 | DiomanAuth.new(onRefresh) | keep | `test/combo/b3_combo_test.dart:61` — [DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次 |  |
| rule.md:264 | DiomanAuth.new(ready) | keep | `test/boundary/auth_boundary_test.dart:322` — [DiomanAuth.onAccessExpired] 通知同步异步抛错隔离，判定和 ready 异常原样抛出 |  |
| rule.md:265 | DiomanAuth.new(refreshLeeway) | keep | `test/rule/auth_rule_test.dart:152` — [DiomanAuth.expiresAt] 主动刷新只一次、空过期时间不刷新、提前量请求覆盖 |  |
| rule.md:266 | DiomanAuth.new(tokenManager) | keep | `test/rule/auth_rule_test.dart:92` — [DiomanAuth.onAccessDenied] 本地无 token 每请求通知一次，空串等价未登录，默认回退 expired |  |
| rule.md:267 | DiomanAuth.onError | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:268 | DiomanAuth.onError#body-replay | change | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| rule.md:269 | DiomanAuth.onError#multipart-replay | change | `test/integration/b3_transport_integration_test.dart:54` — [DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主 |  |
| rule.md:270 | DiomanAuth.onRequest | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:271 | DiomanAuth.onRequest#cancel-refresh | change | `test/boundary/auth_boundary_test.dart:186` — [DiomanAuth.onRefresh] 发起者等待者取消和 cancelAll 不终止刷新，成功写 token 失败清会话 |  |
| rule.md:272 | DiomanAuth.onResponse | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:273 | DiomanAuth.pluginName | change | `test/rule/auth_rule_test.dart:51` — [DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样 |  |
| rule.md:274 | DiomanAuthFailureAction.deny | change | `test/rule/auth_rule_test.dart:123` — [DiomanAuth.onFailure] 自定义五动作、仅重放一次和非鉴权结果返回 |  |
| rule.md:275 | DiomanAuthFailureAction.expired | change | `test/rule/auth_rule_test.dart:123` — [DiomanAuth.onFailure] 自定义五动作、仅重放一次和非鉴权结果返回 |  |
| rule.md:276 | DiomanAuthFailureAction.others | change | `test/rule/auth_rule_test.dart:123` — [DiomanAuth.onFailure] 自定义五动作、仅重放一次和非鉴权结果返回 |  |
| rule.md:277 | DiomanAuthFailureAction.refresh | change | `test/rule/auth_rule_test.dart:123` — [DiomanAuth.onFailure] 自定义五动作、仅重放一次和非鉴权结果返回 |  |
| rule.md:278 | DiomanAuthFailureAction.replay | change | `test/rule/auth_rule_test.dart:123` — [DiomanAuth.onFailure] 自定义五动作、仅重放一次和非鉴权结果返回 |  |
| rule.md:279 | DiomanAuthOptions.buildHeader | keep | `test/boundary/b3_options_boundary_test.dart:99` — [DiomanAuthOptions.headerKey] 自定义头和格式、ready 优先，过期通知与 expiresAt 请求覆盖 |  |
| rule.md:280 | DiomanAuthOptions.enabled | keep | `test/boundary/b3_options_boundary_test.dart:81` — [DiomanAuthOptions.enabled] true 强制保护优先于公开谓词，省略与 call.true 沿用谓词 |  |
| rule.md:281 | DiomanAuthOptions.expiresAt | keep | `test/rule/auth_rule_test.dart:152` — [DiomanAuth.expiresAt] 主动刷新只一次、空过期时间不刷新、提前量请求覆盖 |  |
| rule.md:282 | DiomanAuthOptions.headerKey | keep | `test/boundary/b3_options_boundary_test.dart:99` — [DiomanAuthOptions.headerKey] 自定义头和格式、ready 优先，过期通知与 expiresAt 请求覆盖 |  |
| rule.md:283 | DiomanAuthOptions.isProtected | keep | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 |  |
| rule.md:285 | DiomanAuthOptions.onAccessDenied | keep | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 |  |
| rule.md:286 | DiomanAuthOptions.onAccessExpired | keep | `test/boundary/b3_options_boundary_test.dart:99` — [DiomanAuthOptions.headerKey] 自定义头和格式、ready 优先，过期通知与 expiresAt 请求覆盖 |  |
| rule.md:287 | DiomanAuthOptions.onFailure | keep | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 |  |
| rule.md:288 | DiomanAuthOptions.ready | keep | `test/rule/auth_rule_test.dart:186` — [DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用 |  |
| rule.md:289 | DiomanAuthOptions.refreshLeeway | keep | `test/rule/auth_rule_test.dart:152` — [DiomanAuth.expiresAt] 主动刷新只一次、空过期时间不刷新、提前量请求覆盖 |  |
| rule.md:290 | DiomanTokenManager.accessToken | keep | `test/rule/auth_rule_test.dart:10` — [DiomanTokenManager] setTokens 与 clear 管理原始凭证，不提供 canRefresh |  |
| rule.md:292 | DiomanTokenManager.clear | keep | `test/rule/auth_rule_test.dart:10` — [DiomanTokenManager] setTokens 与 clear 管理原始凭证，不提供 canRefresh |  |
| rule.md:293 | DiomanTokenManager.refreshToken | keep | `test/boundary/b3_options_boundary_test.dart:71` — [DiomanTokenManager.refreshToken] auth 不直接读取刷新凭证，onRefresh 自行决定能否刷新 |  |
| rule.md:294 | defaultAuthFailure | keep | `test/rule/auth_rule_test.dart:23` — [defaultAuthFailure] 默认判定覆盖无 token、旧 token、逻辑 401 403 与其它失败 |  |
| rule.md:296 | DiomanBreaker.bucketCount | change | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:297 | DiomanBreaker.defaultIdleTtl | change | `test/rule/breaker_rule_test.dart:40` — [DiomanBreaker.defaultMaxBuckets] 默认回收一小时和一千桶软上限 |  |
| rule.md:298 | DiomanBreaker.defaultMaxBuckets | change | `test/rule/breaker_rule_test.dart:40` — [DiomanBreaker.defaultMaxBuckets] 默认回收一小时和一千桶软上限 |  |
| rule.md:299 | DiomanBreaker.enabled | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:300 | DiomanBreaker.failureThreshold | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:301 | DiomanBreaker.halfOpenMaxCalls | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:302 | DiomanBreaker.idleTtl | keep | `test/boundary/breaker_boundary_test.dart:171` — [DiomanBreaker.idleTtl] TTL 与软上限只淘汰安全桶，保留失败和打开半开在途桶 |  |
| rule.md:303 | DiomanBreaker.isOpen | change | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:304 | DiomanBreaker.keyBuilder | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:305 | DiomanBreaker.maxBuckets | keep | `test/boundary/breaker_boundary_test.dart:171` — [DiomanBreaker.idleTtl] TTL 与软上限只淘汰安全桶，保留失败和打开半开在途桶 |  |
| rule.md:306 | DiomanBreaker.name | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:307 | DiomanBreaker.new(clock) | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:308 | DiomanBreaker.onError | change | `test/boundary/breaker_boundary_test.dart:61` — [DiomanBreaker.shouldTrip] cancel 只归还名额，不清连续失败也不计失败，半开可继续探测 |  |
| rule.md:309 | DiomanBreaker.onError#cancel-probe | change | `test/boundary/breaker_boundary_test.dart:61` — [DiomanBreaker.shouldTrip] cancel 只归还名额，不清连续失败也不计失败，半开可继续探测 |  |
| rule.md:310 | DiomanBreaker.onError#network-classification | change | `test/rule/breaker_rule_test.dart:102` — [DiomanBreaker.shouldTrip] 默认类别与逻辑状态、自定义 true false null |  |
| rule.md:311 | DiomanBreaker.onRequest | change | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:312 | DiomanBreaker.onResponse | change | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:313 | DiomanBreaker.onStateChange | change | `test/rule/breaker_rule_test.dart:177` — [DiomanBreaker.onStateChange] 通知异常隔离，判定与 keyBuilder 异常原样落定 |  |
| rule.md:314 | DiomanBreaker.pluginName | change | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:317 | DiomanBreaker.reset | keep | `test/boundary/breaker_boundary_test.dart:144` — [DiomanBreakerApi.reset] reset 之后旧请求不写新桶，internal 不计数且释放名额 |  |
| rule.md:318 | DiomanBreaker.resetDuration | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:319 | DiomanBreaker.shouldTrip | change | `test/rule/breaker_rule_test.dart:102` — [DiomanBreaker.shouldTrip] 默认类别与逻辑状态、自定义 true false null |  |
| rule.md:320 | DiomanBreaker.stateOf | change | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:321 | DiomanBreakerOptions.enabled | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:322 | DiomanBreakerOptions.failureThreshold | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:323 | DiomanBreakerOptions.halfOpenMaxCalls | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:324 | DiomanBreakerOptions.keyBuilder | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:325 | DiomanBreakerOptions.resetDuration | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:326 | DiomanBreakerOptions.shouldTrip | keep | `test/rule/breaker_rule_test.dart:131` — [DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭 |  |
| rule.md:327 | DiomanBreakerState.closed | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:328 | DiomanBreakerState.halfOpen | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:329 | DiomanBreakerState.open | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| rule.md:469 | DiomanRetry.afterStatusCodes | keep | `test/boundary/retry_boundary_test.dart:10` — [DiomanRetry.respectRetryAfter] 秒数、空白、HTTP 日期、无效值和独立封顶 |  |
| rule.md:470 | DiomanRetry.delay | keep | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| rule.md:471 | DiomanRetry.delayMax | keep | `test/boundary/retry_boundary_test.dart:10` — [DiomanRetry.respectRetryAfter] 秒数、空白、HTTP 日期、无效值和独立封顶 |  |
| rule.md:472 | DiomanRetry.enabled | keep | `test/rule/retry_rule_test.dart:91` — [DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关 |  |
| rule.md:473 | DiomanRetry.jitter | keep | `test/boundary/retry_boundary_test.dart:80` — [DiomanRetry.delay] 抖动正负、随机、负退避与上限，关闭服务器头 |  |
| rule.md:474 | DiomanRetry.max | keep | `test/rule/retry_rule_test.dart:91` — [DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关 |  |
| rule.md:475 | DiomanRetry.methods | keep | `test/rule/retry_rule_test.dart:31` — [DiomanRetry.shouldRetry] 成功也交判定，自定义布尔优先与方法硬否决 |  |
| rule.md:476 | DiomanRetry.name | keep | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| rule.md:477 | DiomanRetry.onError | change | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| rule.md:478 | DiomanRetry.onRequest | change | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| rule.md:479 | DiomanRetry.onResponse | change | `test/rule/retry_rule_test.dart:31` — [DiomanRetry.shouldRetry] 成功也交判定，自定义布尔优先与方法硬否决 |  |
| rule.md:480 | DiomanRetry.onRetry | keep | `test/boundary/retry_boundary_test.dart:139` — [DiomanRetry.onRetry] 通知抛错隔离并记日志，通知取消不重发 |  |
| rule.md:481 | DiomanRetry.pluginName | change | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| rule.md:482 | DiomanRetry.respectRetryAfter | keep | `test/boundary/retry_boundary_test.dart:10` — [DiomanRetry.respectRetryAfter] 秒数、空白、HTTP 日期、无效值和独立封顶 |  |
| rule.md:483 | DiomanRetry.retryAfterMax | keep | `test/boundary/retry_boundary_test.dart:10` — [DiomanRetry.respectRetryAfter] 秒数、空白、HTTP 日期、无效值和独立封顶 |  |
| rule.md:484 | DiomanRetry.shouldRetry | change | `test/rule/retry_rule_test.dart:31` — [DiomanRetry.shouldRetry] 成功也交判定，自定义布尔优先与方法硬否决 |  |
| rule.md:485 | DiomanRetry.statusCodes | change | `test/rule/retry_rule_test.dart:10` — [DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果 |  |
| rule.md:486 | DiomanRetry.statusCodes#network-type | keep | `test/rule/retry_rule_test.dart:55` — [DiomanRetry.shouldRetry] 类别硬否决先于回调，network timeout 默认重试 |  |
| rule.md:487 | DiomanRetryOptions.afterStatusCodes | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:488 | DiomanRetryOptions.delay | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:489 | DiomanRetryOptions.delayMax | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:490 | DiomanRetryOptions.enabled | keep | `test/rule/retry_rule_test.dart:91` — [DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关 |  |
| rule.md:491 | DiomanRetryOptions.jitter | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:492 | DiomanRetryOptions.max | keep | `test/rule/retry_rule_test.dart:91` — [DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关 |  |
| rule.md:493 | DiomanRetryOptions.methods | keep | `test/rule/retry_rule_test.dart:31` — [DiomanRetry.shouldRetry] 成功也交判定，自定义布尔优先与方法硬否决 |  |
| rule.md:494 | DiomanRetryOptions.respectRetryAfter | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:495 | DiomanRetryOptions.retryAfterMax | keep | `test/boundary/retry_options_boundary_test.dart:19` — [DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效 |  |
| rule.md:496 | DiomanRetryOptions.shouldRetry | keep | `test/boundary/retry_options_boundary_test.dart:100` — [DiomanRetryOptions.shouldRetry] 请求判定覆盖插件判定，状态表与方法按请求替换 |  |
| rule.md:497 | DiomanRetryOptions.statusCodes | keep | `test/rule/retry_rule_test.dart:91` — [DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关 |  |
| unit.md:108 | DiomanAuth.dispose | change | `test/integration/b3_transport_integration_test.dart:22` — [DiomanAuth.setup] 同配置不同客户端刷新窗口隔离，dispose 后新客户端正常刷新 |  |
| unit.md:110 | DiomanBreaker.dispose | keep | `test/rule/breaker_rule_test.dart:44` — [DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致 |  |
| unit.md:111 | DiomanBreaker.ordering | change | `test/combo/b3_combo_test.dart:12` — [DiomanRetry.max × DiomanBreaker.failureThreshold] 每次尝试计数，打开返回 breaker 后停止重试，无需接线 |  |
| unit.md:112 | DiomanBreakerOpenException.bucketKey | change | `test/rule/breaker_rule_test.dart:11` — [DiomanBreakerApi.keyOf] 默认键与请求覆盖只计算桶键，不建桶不改状态 | 终审已裁决：旧 bucketKey 由 DiomanBreakerApi.keyOf(request) 承接；旧 retryableAt 由 retryableAt(key) 承接，保留开启时冷却快照且查询只读。 |
| unit.md:113 | DiomanBreakerOpenException.retryableAt | change | `test/boundary/breaker_boundary_test.dart:11` — [DiomanBreakerApi.retryableAt] 保存开启时请求冷却，查询到期不迁移，半开重开关闭与 reset | 终审已裁决：旧 bucketKey 由 DiomanBreakerApi.keyOf(request) 承接；旧 retryableAt 由 retryableAt(key) 承接，保留开启时冷却快照且查询只读。 |
| unit.md:206 | DiomanRetry.dispose | change | `test/integration/b3_transport_integration_test.dart:151` — [Dioman.use × DiomanBreakerApi.stateOf] 插入移除替换熔断器使用新实例，dispose 拒绝复活 |  |
