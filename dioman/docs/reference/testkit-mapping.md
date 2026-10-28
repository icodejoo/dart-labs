---
title: testkit 能力字段到 dioman 参数的映射
status: active
updated: 2026-10-28
summary: testkit schema 的插件与请求级字段分别映射到 dioman 哪个参数或宿主职责。
---
# dioman 能力映射

支持 CONTRACT §7 的全部 17 个能力，adapter 为 io；未知能力输出 `skipped: missing <cap>`。
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
| retry.statuses | 已映射 | shouldRetry 使用逻辑状态，默认 500/502/503/504；429 场景显式配置 |
| retry.methods | 已映射 | methods，默认 GET/PUT/HEAD/DELETE/OPTIONS |
| retry.respect_retry_after | 已映射 | respectRetryAfter；afterStatusCodes 加入 200 以支持 business 风格 |
| share.policy | 已映射 | DiomanSharePolicy.start/end/race；未知值显式报错 |
| loading.delay_ms | 已映射 | delay |
| loading.delay_close_ms | 已映射 | delayClose，结束后等待 delayClose + 40ms 再读取事件 |
| notify {} | 已映射 | DiomanNotify.notify/stringify；silent 与主动取消不通知，错误消息为空时提供默认文本 |
| normalize {} | 已映射 | DiomanNormalize；传输转换器先将失败信封转换为带原始响应的 DioException |
| key.scope | 已映射 | 仅 user → namespace，其他值显式报错；请求 options.key 才开启 key |
| timeout.connect_ms | 已映射 | DiomanTimeouts.connect |
| timeout.receive_ms | 已映射 | DiomanTimeouts.receive |
| timeout.total_ms | 已映射 | **执行器宿主策略**：逻辑请求硬预算 Timer + CancelToken，进入插件错误链前还原 receiveTimeout；不是 DiomanTimeout 原生总预算 |
| breaker.threshold | 已映射 | failureThreshold，按每次真实尝试计数 |
| breaker.open_ms | 已映射 | resetDuration |
| offline.probe | 已映射 | **执行器宿主职责**：真实 /t/ping 探测提供 isOnline 与 onConnectivityChanged；maxWait=0 将离线队列转成快速失败 |
| mock.fallback_on_404 | 已映射 | fallbackWhen；基址固定为起始 baseURL/t/mock，仅明确 404 才回退 |
| repath/filter/cancel/envs/log {} | 已映射 | 对应原生插件；envs 无规则，log 原文采集 |
| 其余字段 | 显式报错 | 构造客户端前检查 pluginFields，绝不静默忽略 |

请求级映射：

| request.options 字段 | 状态 | 实现 |
|---|---|---|
| auth | 已映射 | DiomanAuthOptions.enabled |
| cache true/false/{ttl_ms,key} | 已映射 | DiomanCacheOptions.enabled/expires；key 经 DiomanKeyOptions.key |
| retry | 已映射 | DiomanRetryOptions；对象仅允许 max/delay_ms/statuses/methods/respect_retry_after，支持数值与 false |
| share | 已映射 | DiomanShareOptions.enabled/policy；none 与 false 关闭 |
| loading | 已映射 | DiomanLoadingOptions.enabled |
| silent | 已映射 | 宿主 stringify 读取 accept:silent |
| timeout_ms | 已映射 | Dio receiveTimeout（每次尝试）；存在 total_ms 时同时覆盖逻辑总预算 |
| key true/deep/simple/字符串 | 已映射 | enabled/fastMode/key；true 与 deep 包含 query/body；simple 仅 method/origin/path |
| mock | 已映射 | DiomanMockOptions.enabled |
| normalize | 已映射 | DiomanNormalizeOptions.enabled，同时控制信封转换 |
| breaker | 已映射 | DiomanBreakerOptions.enabled |
| cancel_after_ms | 已映射 | 外部 CancelToken；用原生 track/untrack 纳入 cancelAll |
| 未登记字段或对象嵌套字段 | 显式报错 | 该场景失败并附字段名 |

完整实现 16 个 step：request、parallel、sequence、fire、repeat、wait、login、set_token、logout、revoke、expire_local、cancel_all、clear_cache、network、server_reset、style。
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
