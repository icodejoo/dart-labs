---
title: testkit 能力字段到 dioman 参数的映射
status: active
updated: 2026-10-28
summary: testkit schema 的插件与请求级字段分别映射到 dioman 哪个参数或宿主职责。
---
# dioman 能力映射

支持 CONTRACT §7 的 17 个插件级能力，加 4 个细分能力（`multipart`、`keep-alive`、`share-retry`、`timeout-send`），共 21 个，adapter 为 io；未声明的能力输出 `skipped: missing <cap>`。
**不声明 `mock-in-chain`**：dioman 的 mock 是传输层 `DiomanMockAdapter`，在 cache/share 之下，依赖它的两个 combo 场景按缺能力跳过。细分能力在 `common.dart` 的 `subCapabilities`，不参与插件矩阵与幂集（`capabilities` 仍是 17 个插件名）。
“已映射”表示执行器有明确实现；不代表该项验收已经通过。运行证据见 `test/accept/results/*.json`（本地，不入库）。
未登记字段、非法类型、非法枚举值必须失败；不以忽略配置代替实现。

| schema pluginOptions 字段 | 状态 | dioman 参数或明确的宿主职责 |
|---|---|---|
| auth.url_pattern | 已映射 | DiomanAuth.isProtected，路径前缀，默认 /t/private |
| auth.refresh | 已映射 | 仅 endpoint；其他值显式报错。onRefresh 用裸 io Dio 经当前网络访问 /t/auth/refresh |
| auth.refresh_query | 已映射 | 刷新请求 queryParameters |
| cache.ttl_ms | 已映射 | DiomanCache.expires，毫秒 |
| cache.max | 已映射 | maxEntries |
| cache.methods（场景扩展字段） | 已映射 | shouldCache 方法白名单，默认 GET |
| retry.max | 已映射 | max |
| retry.delay_ms | 已映射 | delay 回调返回 Duration |
| retry.statuses | 已映射 | DiomanRetry/DiomanRetryOptions.statusCodes，默认 500/502/503/504；shouldRetry 仅判定 HTTP 成功响应中的非零业务码，其余返回 null，交回原生状态码及网络/超时分类 |
| retry.methods | 已映射 | methods，默认 GET/PUT/HEAD/DELETE/OPTIONS |
| retry.respect_retry_after | 已映射 | respectRetryAfter；afterStatusCodes 加入 200 以支持 business 风格 |
| share.policy | 已映射 | 按名称解析 DiomanSharePolicy：start/end/race，加 `retry`（`share-retry` 能力，原生 DiomanSharePolicy.retry：共享同一结果、失败时内部重试、调用方只见最终结果；次数与间隔用 dioman 默认）；请求级另有 none |
| loading.delay_ms | 已映射 | delay |
| loading.delay_close_ms | 已映射 | delayClose，结束后等待 delayClose + 40ms 再读取事件 |
| notify {} | 已映射 | DiomanNotify.notify/stringify；silent 与主动取消不通知，错误消息为空时提供默认文本 |
| normalize {} | 已映射 | DiomanNormalize；传输转换器先将失败信封转换为带原始响应的 DioException。只装 auth 不装 normalize 时，转换器只把业务 401/403 交给 auth，其余业务码原样作为成功响应（testkit D21） |
| key.scope | 已映射 | 仅 user → namespace，其他值显式报错；请求 options.key 才开启 key |
| timeout.connect_ms | 已映射 | DiomanTimeouts.connect |
| timeout.send_ms | 已映射 | DiomanTimeouts.send（Dio sendTimeout，只在写请求体阶段计时；`timeout-send` 能力） |
| timeout.receive_ms | 已映射 | DiomanTimeouts.receive |
| timeout.total_ms | 已映射 | **执行器宿主策略**：逻辑请求硬预算 Timer + CancelToken，进入插件错误链前还原 receiveTimeout；不是 DiomanTimeout 原生总预算 |
| breaker.threshold | 已映射 | failureThreshold，按每次真实尝试计数 |
| breaker.open_ms | 已映射 | resetDuration |
| breaker 失败分类 | 已映射 | HTTP、网络及超时交给内置 shouldTrip 回落；回调仅补充 HTTP 成功响应中的非零业务码（429/5xx 计失败） |
| offline.probe | 已映射 | **执行器宿主职责**：真实 /t/ping 探测提供 isOnline 与 onConnectivityChanged；maxWait=0 将离线队列转成快速失败 |
| mock {} | 已映射 | **传输层 DiomanMockAdapter**，不是插件：执行器在 `Dioman.install` 之前用它包住宿主 adapter，不进插件列表与顺序规则 |
| mock.fallback_on_404 | 已映射 | DiomanMockAdapter.fallbackWhen；基址固定为起始 baseURL/t/mock，仅明确 404 响应才回退（传输异常不回退） |
| repath/filter/cancel/envs/log {} | 已映射 | 对应原生插件；envs 无规则，log 原文采集；filter 只装配，不触发过滤（见请求级 `filter`） |
| 其余字段 | 显式报错 | 构造客户端前检查 pluginFields，绝不静默忽略 |

请求体与结果断言（schema `request.body` / `result`）：

| 字段 | 状态 | 实现 |
|---|---|---|
| request.body.multipart | 已映射 | `common.dart` 的 `requestBody`/`buildMultipart`：先 `fields` 后 `files`，生成 dio `FormData`；文件 `MultipartFile.fromBytes`（`application/octet-stream`），字节由 `seedBytes` 按 CONTRACT §7 的 32 位线性同余生成（`state=state*1664525+1013904223 mod 2^32`，取高 8 位）；FormData 可克隆，auth 重放 / retry / share 内部重试重建请求体 |
| result.same_as `{id, field}` | 已映射 | `runner.dart` checkLocal → `common.dart` 的 `checkSameAs`：双方 ok:true，且 data 的点分路径字段相等；`ok` 不为 true 的结果写 same_as 直接判失败 |
| 服务端控制参数 read_delay_ms 等 | 透传 | 走 `request.query` → `queryParameters`，执行器不解释 |

请求级映射：

| request.options 字段 | 状态 | 实现 |
|---|---|---|
| auth | 已映射 | DiomanAuthOptions.enabled |
| cache true/false/{ttl_ms,key} | 已映射 | DiomanCacheOptions.enabled/expires；key 经 DiomanKeyOptions.key |
| retry | 已映射 | DiomanRetryOptions；对象仅允许 max/delay_ms/statuses/methods/respect_retry_after，支持数值与 false |
| share | 已映射 | false → enabled=false；none → enabled=true、DiomanSharePolicy.none，进入原生独立请求分支；两者在中立语义下均不共享 |
| loading | 已映射 | DiomanLoadingOptions.enabled |
| silent | 已映射 | 宿主 stringify 读取 accept:silent |
| timeout_ms | 已映射 | Dio receiveTimeout（每次尝试）；存在 total_ms 时同时覆盖逻辑总预算 |
| key true/deep/simple/字符串 | 已映射 | enabled/fastMode/key；true 与 deep 包含 query/body；simple 仅 method/origin/path |
| mock | 已映射 | `extra[DiomanMockAdapter.extraKey]` = DiomanMockOptions.enabled |
| normalize | 已映射 | DiomanNormalizeOptions.enabled，同时控制信封转换 |
| breaker | 已映射 | DiomanBreakerOptions.enabled |
| filter | 已映射 | testkit D19（2026-10-28）：仅 `true` 时 DiomanFilterOptions.enabled=true；缺省与 false 显式关闭（DiomanFilter 装上默认开启，与中立语义相反）；非布尔报错。中立语义还要求剔除 NaN，DiomanFilter 默认不剔除，场景未覆盖 |
| cancel_after_ms | 已映射 | 定时取消、总预算、离线探测及 share 场景用外部 CancelToken，并通过原生 track/untrack 纳入 cancelAll；其余安装 cancel 的请求不传外部 token，由插件 onRequest 注入和登记，宿主仅接收 token 维护在途观测 |
| 未登记字段或对象嵌套字段 | 显式报错 | 该场景失败并附字段名 |

完整实现 16 个 step：request、parallel、sequence、fire、repeat、wait、login、set_token、logout、revoke、expire_local、cancel_all、clear_cache、network、server_reset、style。
cancel_all 直接调用已安装的 DiomanCancel.cancelAll；报告 events.cancel_all 保留每次实际取消数量，用于确认登记与取消真正生效。
login/logout/revoke/server_reset/expire_local 走服务器旁路；刷新经过被测网络但不经过插件链。
expire_local 只更换 access，保留原 refresh；previous 在值真实变化时更新。fire 在场景结束前统一等待。
flap 的宿主连通性采样采用 500ms 预算，在 1500ms 离线窗口内完成；避免 Windows TCP 重试跨过恢复时刻而误判初始在线。

| dioman / Dio 错误 | CONTRACT §7 分类 |
|---|---|
| onAccessExpired 标签或稳定 session expired / refresh failed 消息 | expired |
| onAccessDenied：真实 403 / 合成无令牌响应 | denied / unauthenticated |
| DioExceptionType.cancel | canceled（优先于鉴权标签） |
| connectTimeout / receiveTimeout / sendTimeout、宿主预算耗尽 | timeout |
| DioException.error 为 DiomanBreakerOpenException | breaker_open |
| DioException.error 为 DiomanOfflineException | offline |
| HTTP >=400 | http:<status>，优先于业务码 |
| 失败信封或 DiomanException | business:<code> |
| FormatException | parse |
| SocketException / HttpException / connectionError | network |
| 其他 | unknown:<描述>，不会被当成成功 |

status:<n> 根据**该请求**的响应风格匹配 http:n 或 business:n，支持预期 error 数组与 any。
应用期望 JSON 时，HTML 网关页在转换器中抛 FormatException；裸 JSON、空响应与 text 按场景要求透传。
业务信封转换是显式应用协议适配，不宣称库默认能识别所有服务端信封。

mock 的两个组合场景（`combo.cache-mock-fallback-cached-once`、`combo.mock-share-fallback-single-flight`）依赖 `mock-in-chain`：dioman 的 mock 在传输层、位于 cache/share 之下，回落的真实数据会被缓存、相同并发请求先在 share 层合并，计数与场景不同。执行器不声明该能力，这两个场景按 `skipped: missing mock-in-chain` 跳过（CONTRACT §7 明确"不算错误"）；runner 里不再保留单独的设计差异表。

本轮保留两项宿主适配边界：

- normalize：D14 明确要求提前将业务失败转换为错误，让 auth/retry/cache 组合看到同一种失败。DiomanNormalize 安装在链尾；auth.onResponse 不处理业务 401/403，share 的内部 retry 也依赖传输层抛错。直接移除转换器判定会牵连鉴权刷新及共享重试等组合，因此本轮不改，不能将现有 PASS 宣称为 normalize 原生拒绝分支覆盖。建议后续先为这些组合分别接入业务失败判定，再收窄转换器；仅无前置失败消费者的场景可优先交给 normalize，需单独验证。
- offline：CONTRACT §7 只声明能力及 offline 错误，schema 仅定义 probe，没有 maxWait、排队恢复、flush 时序的中立语义；现有场景要求无网快速失败。保留 maxWait=0，不能据此声称覆盖离线恢复重放。应先扩展中立契约与场景，再映射等待时间和恢复事件，不能擅用原生无限等待替换快速失败。

| 客户端事件 | 原始来源 |
|---|---|
| loading | onChanged 布尔值，保留完整序列 |
| notify | notify 回调，保留次数与每条文案，不在执行器去重 |
| refresh | onRefresh 实际发出刷新请求时计数 |
| expired | onAccessExpired 实际回调次数，不在执行器去重 |
| denied | onAccessDenied 实际回调次数；无令牌合成响应只标记 unauthenticated |
| pending_after | 所有逻辑请求 CancelToken 的在途集合大小 |

每项都检查 pending_after=0、loading 成对及服务端 inflight=0，删除本轮代理后再次观测。
报告保留服务端 log（最多 1000 条）与 netem stats。只对自己创建的代理发 DELETE，不操作服务进程。

公开 API 清单由 inventory.dart 从 lib/dioman.dart 的导出 AST 生成；构造参数也单独列项。
probes.dart 显式传入全部公开选项、调用管理方法；probes_fields.dart 实际读取每个公开属性。
metadata/兼容空操作的证据会明确标为 metadata/compatibility，不伪称这些 API 自身会发网络请求。
API 调用覆盖与 lcov 行覆盖分别报告；缺少真实探针结果时不得声称达到 100%。
