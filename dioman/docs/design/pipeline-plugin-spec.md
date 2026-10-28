---
title: dioman 内置插件与内核服务规格（洋葱管线）
status: active
updated: 2026-10-29
summary: 12 个内置插件和内核服务在 next() 模型下的选项、默认值、行为、内核依赖，以及相对 0.7 的行为变化汇总
---
## TL;DR

- 12 个内置插件：outer 阶段 loading、notify；prepare 阶段 repath、filter、timeout；attempt 阶段 retry、breaker；credential 阶段 auth；source 阶段 mock、share、cache、offline。envs 只有 `setup`，不进链。
- key、cancel、normalize、log 降为内核能力（见[核心架构](pipeline-architecture.md)）。
- 现有功能全部保留，只改写法；行为变化集中列在 §9，CHANGELOG 和迁移指南按它写。

## 0. 插件约定

1. 工厂即类：`DiomanRetry(…)` 等，`name` 为 `dioman:<名字>`。插件对象只放配置，可以是 const；状态建在 `setup` 返回的实例里。
2. **插件级 `enabled: false`**：内核在编译链时直接跳过，不调 `setup`，`inspect()` 不列出。
3. **请求级选项统一四种写法**，由 `resolveOption` 一个函数解析：省略、`true`（用插件级配置）、`false`（本次关闭）、插件自己的选项对象（字段为 null 的沿用插件级）。部分插件另有一种简写（retry 的整数 = `max`，cache 的 `Duration` = `expires`，share 的策略枚举）。不认识的类型按 bug 抛 `ArgumentError`。插件级配置在 `setup` 时预合并；请求级 `true` 或省略时复用同一份。
4. **装上即生效**，只有改变数据新鲜度的 **cache、share 要在请求级开启**（optIn）。
5. **改请求只用 `next(patch)`**，不改 `ctx.request`。
6. 用户回调抛错：通知类隔离并输出错误日志；判定类按 bug 处理；`onRefresh` 抛错算刷新失败（见核心架构 §7）。
7. **每个 await 之后用 `ctx.cancelled()` 重查取消**；等待一律用 `ctx.wait`。
8. 会重发请求的插件（retry、auth、mock、share 的 retry 策略）在第一次 `next()` 之前调用 `ctx.markReplayable()`。

## 1. outer

### loading
- 选项：`onChanged(bool visible)` 必填；`delay`（0→1 之后延迟显示，期间回落就不显示）、`delayClose`（1→0 之后延迟隐藏，期间有新请求就不隐藏），默认都是 `Duration.zero`。请求级：`false`、`true`、`DiomanLoadingOptions`。
- 模型：计数加一；`try { return await next(); } finally { 计数减一 }`。一个逻辑请求恰好一对，重试和重放都包在里面。按回调身份分开计数：请求级换了回调的请求，计入自己那个回调。
- `dispose`：取消未触发的计时器；对已显示的回调立即发一次 `false`；在途请求不再通知。
- 内核依赖：outer 阶段位置、`DiomanClock`。

### notify
- 选项：`notify(String message, R r)` 必填；`stringify(R r, DiomanContext ctx)`，默认在 `r.ok`、`kind == cancel`、`ctx.request.silent` 时返回空串，否则返回 `r.message`，为空时返回 `'<kind> <status>'`。空串表示不通知。请求级只有开关。
- 模型：`final r = await next(); 通知; return r;`。每个逻辑请求最多一次，天然只在最终失败时通知，刷新成功不通知。
- 内核依赖：outer 阶段、`request.silent`。

## 2. prepare

### repath
- 选项不变：`pattern`（默认匹配 `{id}`、`:id`、`[id]`）、`removeKey`（默认 true）。只处理路径部分，先找 query（含 BaseOptions 的 queryParameters）再找 Map 形式的 data；值按路径段编码；同名占位符多次出现全部替换。算出新的 path/query/data 后 `next(patch)`；没有变化直接 `next()`。

### filter
- 选项：`predicate(key, value)`，默认剔除 null、NaN、空白字符串，保留 0 与 false；`ignoreKeys`、`ignoreValues`。剥 query 和 Map 形式的 data 的顶层字段；FormData、Stream 原样。没有可剔除的字段时不打补丁。
- 变化：**装上即生效**（0.7 也是），默认谓词新增剔除 NaN（testkit 中立语义，且 `jsonEncode(double.nan)` 会抛错）。

### timeout
- 选项不变：`timeouts`（按 `NetworkQuality` 档位的 connect/receive/send）、`probe`（返回当前网络档位）。请求级：`false`、`DiomanTimeoutOptions`。
- 模型：读出本次档位对应的超时，`next(patch)` 写入请求的超时字段。只改配置，真正计时由 Dio 执行（假设 H5，已在本地回环核对）。

## 3. attempt

### retry
- 选项沿用 0.7：`max`、`methods`（硬否决）、`statusCodes`（默认 408/429/500/502/503/504，读**逻辑状态** `r.status`）、`shouldRetry(R r, int attempt)`、`delay`、`jitter`、`delayMax`、`respectRetryAfter`（默认 true，命中 `afterStatusCodes` 默认 413/429/503 时按 `Retry-After` 的秒数或 HTTP 日期等待，上限 `retryAfterMax`，不叠 jitter、不受 delayMax 限制）、`onRetry(attempt)`。请求级：整数 = max、`false`、`true`、`DiomanRetryOptions`。
- 判定顺序：请求级关闭 → 方法不在白名单 → `kind` 属于 cancel、auth、internal、parse、breaker、offline 时不重试 → `shouldRetry` 返回布尔就采用 → network、timeout 重试 → `statusCodes` 包含 `r.status` 时重试。
- 模型：`markReplayable()`；`var r = await next(); for (attempt = 1..max) { 判定; 等待 ctx.wait(delay); 取消则返回; r = await next(); } return r;`。次数用完返回最后一次结果，由落定决定抛不抛。每次尝试都会穿过 breaker、auth 和 source 阶段。
- 删除：重放交接、认领判断（`_notAdmitted`）、`share`/`cancel` 兼容 setter、`breaker` 字段。

### breaker
- 选项沿用 0.7：`failureThreshold`、`resetDuration`、`halfOpenMaxCalls`、`shouldTrip(R r)`（默认：`kind` 是 network/timeout，或逻辑状态 ≥500 或 429 时计失败；cancel、internal 不计）、`keyBuilder(request)`（默认 `METHOD:path`）、`onStateChange`、`idleTtl`、`maxBuckets`、`clock`。
- 模型：先申请放行；熔断打开或半开名额已满时，直接返回 `ctx.fail(kind: breaker, reason: 'open')`。放行后 `r = await next()`；按 `shouldTrip` 记一次成或败；cancel 只归还名额、不计成败。在 retry 之内，所以每次尝试都会计数；熔断打开时 retry 遇到 `kind: breaker` 不再重试，不需要接线。
- 删除：`admit/recordResponse/recordError` 公开方法（原本只为 retry 接线而存在）、`DiomanBreakerOpenException`（改为 `kind: breaker`）。

## 4. credential：auth

- 选项沿用 0.7：`tokenManager`、`onRefresh`、`onAccessExpired` 必填；`onAccessDenied`（缺省回退 expired）；`onFailure(R r, tokenManager)`，默认见下；`isProtected(request)`；`ready(tokenManager, request)` 返回 `RequestPatch`，默认写 `Authorization: Bearer <token>`（`headerKey`、`buildHeader` 保留为便捷写法）；`expiresAt`、`refreshLeeway`、`clock` 用于主动刷新。请求级：`false`、`DiomanAuthOptions`。
- 默认失败判定（读逻辑状态，所以 business 风格里的业务 401 自动适用）：`r.status == 401` 时，本地没有 token → expired；**本次注入的 token 不等于当前 token → replay**（说明已被并发刷新）；否则 refresh。`403` → deny；其余 → others。本次注入的 token 记在状态键里，不去解析请求头。
- 模型：
  1. 不受保护，直接 `return next()`；`markReplayable()`。
  2. 如果正在刷新，`ctx.wait` 等刷新结果；取消就返回；刷新失败返回 `ctx.fail(kind: auth, reason: 'expired')`。
  3. 循环：本地没有 token → 通知 denied，返回 `reason: 'unauthenticated'`；即将过期且配了 `expiresAt` → 先主动刷新；注入 token 并 `r = await next(patch)`；ok、internal、cancel 直接返回；`action = await onFailure(r)`，回来**先查取消**；refresh/replay：已经重放过一次就按 expired 处理（防止循环），否则 refresh 时加入或发起单飞刷新，然后再循环一次；deny → 通知并返回 `reason: 'denied'`；expired → 清会话、通知、返回 `reason: 'expired'`；others → 原样返回。
- **会话判定**沿用 2026-10-28 的修复：按失败请求实际携带的 token 判断属于哪个会话，旧请求的失败不清新会话，每个会话只通知一次过期；单飞刷新以 `Future(() => onRefresh(…))` 强制异步发起，同步抛错也不会卡死刷新窗口。
- **重放前重查本地凭证**：刷新成功后、重放之前使用者登出，就不再重放（axp B3 抓到的缺陷）。
- 删除：重放交接、认领结算、`DiomanAuth.dio`/`share` setter。

## 5. source：mock → share → cache → offline

### mock
- 选项：`enabled`（默认 true，装上即生效）、`routes`（`METHOD:path` → 处理函数，内联 mock）、`mockUrl`（转发到 mock 服务）、`fallbackWhen(R r)`，默认 `r.httpStatus == 404 || r.kind == network`。请求级：`false`、`true`、`DiomanMockOptions`。
- 模型：命中内联路由 → 用处理函数的结果经工厂造 `R`，直接返回。配了 `mockUrl` → `markReplayable()`，`probe = await next(patch: 改写到 mockUrl，并带"不走 cache、不参与 share"的状态标记)`；`fallbackWhen(probe)` 为真时再 `next()` 打真实接口。
- 变化：从传输层 adapter（2026-10-28）回到 source 阶段，`DiomanMockAdapter` 删除，cache 的 `x-dioman-mock` 规则删除。具备 testkit 的 `mock-in-chain` 能力。

### share
- 选项：`policy`（start、end、race、retry，默认 start）、`retries`、`interval`（retry 策略用）、`methods`（默认 GET、HEAD）。请求级（optIn）：`true`、策略枚举、`DiomanShareOptions`、`false`。`ctx.key()` 为 null 时直接放行。
- 模型：
  - start：首发 `next(patch: cancelToken = 共享 token，并去掉 Dio 层超时)`；每个订阅者用 `ctx.wait(共享结果, timeout: 自己的超时)`，各自离开只结束自己；最后一个订阅者离开时才取消共享请求。首发取消不连累跟随者。
  - end：每次都发，只有序号最新的结果落定。
  - race：每次都发，第一个 `r.ok` 的结果胜出，全部失败时用最后一个。
  - retry：共享同一个结果，失败时在内部按 `retries`、`interval` 重试，调用方只看到最终一次。
- 跟随者拿到同一个只读的 `R`。共享以"一次尝试"为单位；retry 在外层，每次重试都会重新进入 share。共享表按策略分开存放。
- 删除：结算登记簿、`hasMultipleDownstreamSettlers`、`registerDownstreamSettler`、`isJoined`。

### cache
- 选项沿用 0.7：`persist`（存储接口）、`cachePolicy`（memo、persist、both）、`expires`、`clone`、`maxEntries`、`shouldCache(request)`（默认 GET、HEAD）、`shouldStore(R r)`（默认 `r.ok`）、`clock`。请求级（optIn）：`true`、`Duration` = expires、`DiomanCacheOptions`、`false`。
- 模型：方法不允许、key 为 null、或带 mock 探测标记时直接放行；命中（惰性检查过期）直接返回，不触网；未命中时登记新鲜度屏障，`r = await next()`，屏障允许且 `shouldStore(r)` 才写入，`finally` 回收屏障记录。管理操作 `api.plugin<DiomanCacheApi>()` 提供 `remove`、`clear`；`clear()` 会作废在途的写入。
- 变化：`shouldStore` 默认就是 `r.ok`（归一化之后业务失败天然不会进缓存），不再需要和 normalize 接线。

### offline
- 选项沿用 0.7：`isOnline()`、`onConnectivityChanged`、`shouldQueue(request)`、`maxQueueSize`、`maxWait`。请求级：`false`、`DiomanOfflineOptions`。
- 模型：在线 → `next()`。离线：不排队或队列已满 → `ctx.fail(kind: offline, reason: …)`；排队 → `ctx.wait(恢复在线, timeout: maxWait)`，恢复后 `next()`，超时返回 `kind: offline, reason: 'timeout'`，取消返回 cancel。位于 source 最内层，所以缓存命中在离线时照常返回。
- 删除：`DiomanOfflineException`（改为 `kind: offline`）。

## 6. envs

只有 `setup`，不进链：按 `rules` 选第一个命中的配置写进 `client.dio.options`（写入前克隆，不与规则模板共享容器）。

## 7. 内核服务

- **key**：算法沿用 0.7（深模式递归排序 Map、List 保序、`ignores`、`namespace`），由客户端级 `DiomanKeyOptions` 配置。请求级 `call.key`：省略为自动；字符串为显式 key；`false` 表示不参与 cache/share。在 prepare 阶段之后惰性求值。
- **取消**：`api.cancelAll(reason)` 返回本次中止的逻辑请求数；`api.pending`。
- **debug**：`Dioman(debug: true)` 使用默认日志器；记录调用点、插件告警（例如请求体无法克隆、mock 缺少 `mockUrl`）。

## 8. TokenManager

保留 `DiomanTokenManager` 接口（`accessToken`、`refreshToken`、`setTokens`、`clear` 等），删除 `canRefresh`：是否已判过期的状态收进 auth 的实例内部。

## 8.1 B0 终审裁决（2026-10-29，补规格缺口）

B0 迁移清单标出 54 条存疑，归为下列规格缺口，按"现有功能能保留就保留"裁决：

| 缺口 | 裁决 |
|---|---|
| 请求级时钟覆盖（`DiomanAuthOptions.now`、`DiomanCacheOptions.now`） | 删除；时钟统一由客户端 `DiomanClock` 注入。auth 的 `expiresAt`、`refreshLeeway` 请求级覆盖保留 |
| key 细粒度选项 | 客户端 `DiomanKeyOptions(fastMode, ignores, builder, namespace)` 全部保留；请求级 `call.key` 接受 `String`、`false` 或 `DiomanKeyOptions`（ignores 与客户端取并集）；优先级：请求级 builder > 请求级 key > 客户端 builder > 计算 |
| 插件状态与管理 API | 保留，经 `api.plugin<…Api>()` 取得：`DiomanBreakerApi`（`stateOf`、`isOpen`、`bucketCount`）、`DiomanLoadingApi`（`activeCount`）、`DiomanOfflineApi`（`pending`、`flush`）、`DiomanCacheApi`（`remove`、`clear`）；默认值常量（如 `DiomanBreaker.defaultIdleTtl`、`defaultMaxBuckets`）放在插件类上。offline 在 dispose 时让排队请求以 `kind: offline, reason: disposed` 结束 |
| `onRetry` 抛错 | 归通知类：隔离并记日志，不影响请求结果 |
| 信封识别 | 沿用旧规则：Map 含 `code`，且含 `data` 或 `message` 之一即为信封；工厂另提供 `isEnvelope(Map)` 钩子；请求级 `call.envelope: false` 表示本次按非信封处理（替代旧的 `shouldNormalize`） |
| offline 队列满 | 沿用旧语义：挤出最早的请求（`reason: queueFull`）；`maxQueueSize` 为 0 表示不限，默认 50；`shouldQueue` 返回 false 的请求直接放行 |
| cache `cachePolicy.none`、`DiomanCacheOptions.maxEntries` 占位字段 | 删除：cache 已按请求开启，`none` 多余，默认策略改为 memo；占位字段本来不被读取 |
| `DiomanSharePolicy.none` | 删除：关闭共享用请求级 `false` |
| loading 请求级回调的触发、envs 合并 | 按新规格：按回调身份分开计数；envs 合并时克隆容器 |

B2 终审补充：

| 缺口 | 裁决 |
|---|---|
| `BaseOptions` 分不清"省略"与"显式写了默认值" | envs 与 `extend` 共用"非空、非默认字段覆盖"合并，三个 Map 容器深克隆后按顶层键合并。已继承的非默认值**不能**靠写默认值重置回去，此限制写进 `extend` 契约；确有需要再加显式重置 API，不预做 |
| timeout 的真实连接计时 | 单测注入 `connectionTimeout` 只证明归类正确；真实计时归 B7，按 testkit D22 结论 connect 档仍不可黑盒验证，G4 留作唯一缺口 |
| 旧套件首轮并发跑出两处 RangeError（loading_share/end、retry_share/race） | 不归因 B2：B2 没碰旧源码与 `test_legacy/`，串行复验 580 全绿；旧套件在 B5 删除，不再投入 |

B3 终审补充：

| 缺口 | 裁决 |
|---|---|
| auth 的 `ready` 连续 3 次期间 token 都在变 | 不抛错（token 轮换是正常竞态，不是使用者 bug）。与 axp 一致，以最后一次为准：注入最后一次 ready 的补丁，状态键记最后一次调用前的快照；之后若 401，默认判定发现注入值与当前值不同，走 replay 自行纠正 |
| breaker 清桶 | `DiomanBreakerApi` 额外保留 `reset()`（旧版能力）；清表不取消已放行的传输，旧窗口的结算不写进新桶 |
| 旧 `DiomanBreakerOpenException` 的 `retryableAt`、`bucketKey` | 失败载体仍是 `kind: breaker, reason: 'open'`；两项信息改由 `DiomanBreakerApi.keyOf(request)` 与 `retryableAt(key)` 提供，只读，不触发状态迁移 |
| 依赖 share/cache/mock 的 39 条组合迁移行 | B3 只验证自己这一侧的边界，真实组合由 B4 承接，B4 报告逐行关闭 |

B4 终审补充：

| 缺口 | 裁决 |
|---|---|
| share start 订阅者的"自己的超时"怎么由 Dio 三个阶段超时合成 | 上限 = connect + receive，请求带请求体时再加 send；参与计算的任一项为 null 或 ≤0 就不设上限（与 Dio 对 null/零的语义一致）。不取最小值：connect 5s、receive 30s 时，最小值会把正常的慢下载判成超时 |
| cache 的时钟 | 插件级 `clock` 保留，只管 TTL，省略时用客户端时钟；请求级 `now` 仍删除 |
| cache `remove(key)` 的失效范围 | 只作废该 key 的在途读写，`clear()` 才作废全部；旧版提升全局代次，属行为变化 |
| 持久化条目格式 | 写入时增加 result 元信息（`shouldStore` 允许存失败结果时要保留分类），旧的两字段格式仍可读 |
| offline 判定顺序 | 选项关闭 → 在线直接放行 → 再调用 `shouldQueue`，在线时不调用判定回调 |
| 迁移承接用例 | 标题写 `[API id]` 加行为，不写迁移行号；行号对应只留在报告证据里 |

## 9. 行为变化汇总（写进 CHANGELOG 与迁移指南）

| # | 变化 | 原因 |
|---|---|---|
| C1 | 入口改为 `Dioman` 客户端，插件不再是 Dio 拦截器，裸调 `dio.get` 不经过插件 | D1 |
| C2 | 可预期的失败抛 `DiomanResponse`（不再是 `DioException`），bug 原样抛出 | D6 |
| C3 | `DiomanNormalize`、`DiomanKey`、`DiomanCancel`、`DiomanLog` 删除，能力进内核或改用 Dio 自带的 `LogInterceptor` | D3、D7 |
| C4 | 顺序由固定阶段决定，`DiomanPluginOrder`、`Dioman.sort/validate`、`install` 删除 | D2 |
| C5 | 请求级选项改为类型化的键，`extra[...]` 协议删除 | D8 |
| C6 | `DiomanException`、`DiomanBreakerOpenException`、`DiomanOfflineException` 删除，改为 `kind` 与 `reason` | D5 |
| C7 | mock 回到 source 阶段，`DiomanMockAdapter` 删除 | D9 |
| C8 | retry、breaker、auth、cache 一律读逻辑状态，business 风格自动适用 | D3 |
| C9 | filter 默认谓词新增剔除 NaN | testkit 中立语义 |
| C10 | loading 从逻辑请求一开始就显示，包括等待 token 刷新的时间 | 洋葱最外层的自然结果 |
| C11 | `DiomanTokenManager.canRefresh` 删除 | §8 |
| C12 | 判定类回调抛错按 bug 原样抛出（0.7 部分被吞掉）；`onRetry` 归通知类，抛错不再变成请求失败 | 核心架构 §7、§8.1 |
| C13 | 删除请求级时钟覆盖、cache `cachePolicy.none` 与 `maxEntries` 占位字段、`DiomanSharePolicy.none`；cache 默认策略改为 memo | §8.1 |
