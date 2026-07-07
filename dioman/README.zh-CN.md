# dioman

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/dioman.svg)](https://pub.dev/packages/dioman)

一组**可组合、各自独立**的 [`dio`](https://pub.dev/packages/dio) 拦截器*插件*——鉴权、缓存、重试、并发去重、mock、信封拆包、路径变量、加载态、取消、日志——每个只做一件事；并给出把它们串起来的**正确安装顺序**。

> 关键认知：**Dio 对每个拦截器的 `onRequest` / `onResponse` / `onError` 都按添加的正向顺序执行**——它**不是**洋葱模型。所以“添加顺序”就是全部：顺序错了，一次缓存命中会漏掉 loading 的关闭，或者 `auth` 收到一个它认不出来的业务错误。本包既给你插件，也给你一份有据可循的顺序（见[推荐顺序](#推荐顺序)）。

纯 Dart，仅依赖 `dio`——**不依赖 Flutter**。

- [特性](#特性)
- [安装](#安装)
- [快速上手](#快速上手)
- [推荐顺序](#推荐顺序)
- [插件详解](#插件详解)
- [单请求级覆盖](#单请求级覆盖)
- [自定义插件](#自定义插件)
- [行为与语义说明](#行为与语义说明)

## 特性

每个插件都继承 `DiomanPlugin`（一个带 `name` 与 `dispose()` 的命名 `Interceptor`），可单独使用。

| 插件 | 作用 |
|---|---|
| `DiomanEnvs` | 安装时一次性套用分环境的 `BaseOptions`（baseUrl/超时/头）。 |
| `DiomanRepath` | 用 query/body 里的值替换路径变量 `{id}` / `:id` / `[id]`。 |
| `DiomanFilter` | 发送前剔除 query 与 body 里的 `null`/空字段。 |
| `DiomanKey` | 计算稳定的单请求 key（`extra[kRequestKey]`），供缓存与去重使用。 |
| `DiomanCache` | 带 TTL 的响应缓存，支持 `none`/`shallow`/`deep` 克隆策略。 |
| `DiomanShare` | 同 key 并发请求去重（`start`/`end`/`race`/`retry`）。 |
| `DiomanMock` | 基于路由的 mock（内联处理器或 mock 服务器），失败自动回落真实 API。 |
| `DiomanCancel` | 给每个请求注入 `CancelToken`；`cancelAll()` 一键中断在途请求。 |
| `DiomanLoading` | 在途请求计数 → 单一 `onChanged(bool)`，驱动全局 loading。 |
| `DiomanAuth` | 注入 token + 单窗口 401/403 刷新重放（5 种失败动作）。 |
| `DiomanRetry` | 按退避重试网络（可选业务）失败。 |
| `DiomanLog` | 零依赖的请求/响应/错误日志，输出方式可注入。 |
| `DiomanNormalize` | *（可选，装在最后）* 拆 `{code,data,message}` 信封；非成功码转成 `ApiException` 抛出。 |

## 安装

```yaml
dependencies:
  dioman: ^0.4.0
```

```dart
import 'package:dioman/dioman.dart';
```

## 快速上手

把要用的插件传给`Dioman.install`——它会自动按**canonical 顺序**（见[推荐顺序](#推荐顺序)）排位置，
不用自己操心顺序；同时传了`share:`/`cancel:`的话，也会自动帮`DiomanRetry`/`DiomanAuth`接好线
（见[装配：`Dioman.install`](#装配dioman-install)）。

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

final handle = Dioman.install(
  dio,
  envs: DiomanEnvs(dio: dio, [
    EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://api.example.com')),
  ]),
  repath: DiomanRepath(),                 // /users/{id}  → /users/42
  filter: const DiomanFilter(),           // 剔除空参数
  key: const DiomanKey(),                 // 缓存/去重的 key
  cache: DiomanCache(),                   // TTL 缓存（GET）
  share: DiomanShare(),                   // 并发去重
  mock: DiomanMock(),                     // 默认 enabled: false——仅开发用
  cancel: DiomanCancel(),
  loading: DiomanLoading(onChanged: (busy) => showSpinner(busy)),
  auth: DiomanAuth(
    tokenManager: myTokenManager,
    onRefresh: (tokenManager, _) async { /* 刷新并保存 */ },
    onAccessExpired: (tokenManager, _) async { /* 跳登录 */ },
  ),
  retry: DiomanRetry(max: 2),
  log: const DiomanLog(),
  // normalize: const DiomanNormalize(), // 可选、跟业务相关——见下面单独一节。
  // install()不管你在这些具名参数里传在第几个，都会把它放最后。
);

final res = await dio.get('/users/{id}', queryParameters: {'id': 42});

// 稍后——摘除所有已安装插件并释放资源：
// handle.dispose();
```

一份完整可运行的接线（含内存版 token 管理器，及注释里的完整排序依据）见 [`example/dioman_example.dart`](./example/dioman_example.dart)。

### 各插件 `extra` 参数一览

每个插件的 `name` **就是**它固定的 `extra` key（如 `'dioman:loading'`，不可改名），同时也是覆盖值的类型判别——单请求覆盖值永远是插件自己的具体类型 `DiomanXxxOptions`，不再是插件内部用 `is` 一个个判断的 `dynamic` bool/Map。

```dart
await dio.get('/x', options: Options(extra: {
  'dioman:auth':      const DiomanAuthOptions(enabled: false),                       // 本次跳过鉴权
  'dioman:qid':       const DiomanKeyOptions(key: 'my-custom-key'),                  // 覆盖计算出的 key（或 `enabled: false` 跳过生成）
  'dioman:cache':     const DiomanCacheOptions(expires: 5000, clone: CacheClone.shallow),
  'dioman:share':     const DiomanShareOptions(policy: SharePolicy.race),            // 或 `enabled: false` 关闭
  'dioman:mock':      const DiomanMockOptions(mockUrl: 'http://localhost:9999'),      // 或 `enabled: false` 跳过
  'dioman:loading':   const DiomanLoadingOptions(enabled: false),                     // 不计入指示器
  'dioman:retry':     DiomanRetryOptions(max: 1, isException: (Response r) => false), // 或 `enabled: false`
  'dioman:filter':    const DiomanFilterOptions(ignoreKeys: ['page']),                // 或 `enabled: false` 跳过
  'dioman:repath':    const DiomanRepathOptions(enabled: false),                      // 跳过 `{id}` 替换
  'dioman:normalize': const DiomanNormalizeOptions(enabled: false),                   // 保留信封不拆包
  'dioman:log':       const DiomanLogOptions(enabled: false),                         // 本次不记日志
}));
```

`DiomanCancel` 与 `DiomanEnvs` 没有单请求级 `extra` 开关（cancel 靠 `cancelAll` 驱动；envs 只在安装时套用一次）——两者改用构造函数级的 `enabled` 开关，控制整个插件是否生效。其余每个插件的构造函数**同样**都带这个 `enabled`（永久关闭整个插件），叠加在各自 `DiomanXxxOptions` 里的单请求级 `enabled` 之上。

每个 `DiomanXxxOptions` 的字段都跟构造函数参数 1:1 对应（`tokenManager`/`onRefresh`/`dio` 这类构造专属依赖除外，单次调用没法有意义地覆盖它们），且默认值全是 `null`——`null` 代表"继承构造函数当时设的值"，不是隐式回落到 `true` 或别的默认值。所以 `const DiomanCacheOptions(expires: 5000)` 不会碰 `enabled`/`clone`，也**不会**偷偷把用 `enabled: false` 构造的插件重新打开。**`List`/`Map` 字段是跟插件自身默认值做合并（union），不是整体替换**——比如 `DiomanFilter(ignoreKeys: ['a'])` 配合单请求 `DiomanFilterOptions(ignoreKeys: ['b'])`，`'a'` 和 `'b'` 会**同时**保留；`DiomanKeyOptions.ignoreKeys` 和 `DiomanMockOptions.routes` 也是同样的合并语义。

## 推荐顺序

因为 Dio 三个阶段**都是正向顺序**，同一个列表要同时满足请求、响应、错误三条链。两条事实决定一切：

1. 短路——`onRequest` 里的 `handler.resolve()`（缓存命中 / share 等待 / mock 命中）会**跳过其后所有响应拦截器**。
2. `onError` 链会正向走完**每个**拦截器，而第一个 `resolve()` 的（auth 的 401 重放、retry）会**终止其余**。

| # | 插件 | 请求阶段职责 | 响应/错误阶段职责 |
|---|---|---|---|
| 1 | `envs` | （安装时套用配置） | — |
| 2 | `repath` | 替换 `{id}`/`:id` 路径 | — |
| 3 | `filter` | 剔除空参数/数据 | — |
| 4 | `key` | 计算请求 key | — |
| 5 | `cache` | 命中即返回 | 存原始数据 |
| 6 | `share` | 并发去重 | 唤醒等待者 |
| 7 | `mock` | 开发覆盖 / 回落 | — |
| 8 | `cancel` | 注入 `CancelToken` | 释放 token |
| 9 | `loading` | 计数 +1 | 计数 -1（括号） |
| 10 | `auth` | 注入 token / 等刷新 | 401 → 刷新 + 重放 |
| 11 | `retry` | — | 重试网络/业务失败 |
| 12 | `log` | 记录请求 | 记录响应 / 错误 |
| 13 | `normalize` *（可选）* | — | 拆信封 / 业务错转异常 |

**为什么是这些位置（硬约束）：**

- **`key` 在 `cache` 与 `share` 之前**——它们读 `extra[kRequestKey]`。
- **`cache`/`share`/`mock` 在 `cancel` 与 `loading` 之前**——短路会跳过其后的响应拦截器；若把括号类插件放在它们前面，`onRequest` 里 +1/注入了却永远等不到清理。
- **`cancel` 与 `loading` 在 `auth` 与 `retry` 之前**——401（auth）或网络重试时，这两个插件会 `resolve` 错误并中断正向 `onError` 链；括号必须先跑完，才能把计数减回、把 token 释放。
- **`normalize` 排最后，在所有插件（包括 `log`）之后**——它可选、跟业务相关（见下面单独一节），不是传输层的事。放最后意味着其它每个插件——`cache`存的数据、`retry`的`isExceptionRequest`、`log`的dump——看到的永远是响应在线路上原本的样子，不管有没有装`normalize`。`DiomanRetry`自己的重新发起（见它那一节）走的是绕开整条链的裸Dio，所以它的`isExceptionRequest`本来就永远看到原始body。

## 装配：`Dioman.install`

上面的安装顺序是硬约束。与其手工排序，不如把要用的插件传给 `Dioman.install`，它会按 canonical 顺序装配（未传的自动跳过），并返回一个 `DiomanHandle` 用于查找（`handle.plugin<DiomanAuth>()`）、单独移除某个插件（`handle.remove<DiomanAuth>()` 会把它从 `dio.interceptors` 摘除并调用它自己的 `dispose()`，链上其余插件不受影响；若该类型没装过则是空操作，返回 `null`），以及统一销毁（`handle.dispose()` 会摘除**所有**插件并调用每个插件自己的 `dispose()`——这一步没有别处会自动做）。

`install`还会自动帮你接好`DiomanRetry.share`/`.cancel`跟`DiomanAuth.share`/`.cancel`——把跟`retry:`/`auth:`同一个`share:`/`cancel:`实例传进去，`install`装完所有插件后会自动去设那两个属性——为什么这个引用重要见[DiomanRetry](#diomanretry)那一节。只有自己手动往`dio.interceptors`加插件（不走`install`）时，才需要手动设置（`retry.share = share`这样）。

```dart
final handle = Dioman.install(
  dio,
  key: const DiomanKey(),
  cache: DiomanCache(),
  auth: DiomanAuth(tokenManager: tm, onRefresh: ..., onAccessExpired: ...),
  log: const DiomanLog(),
  normalize: const DiomanNormalize(), // 可选——install不管参数顺序，都会把它放最后
);

// 稍后只移除某一个插件（例如登出——只摘 DiomanAuth）：
handle.remove<DiomanAuth>();

// ……或者一次性全部摘除：
handle.dispose();
```

## 插件详解

每个插件都提供 `String get name`（用于查找/去重）与 `dispose()`。多数支持从 `options.extra` 读单请求级开关（见[单请求级覆盖](#单请求级覆盖)）。

### DiomanEnvs

`DiomanEnvs(List<EnvRule> rules, {Dio? dio, bool enabled = true})`——把**第一条命中**规则的 `BaseOptions` 套到 `dio.options`。仅安装时生效（`onRequest` 为空）。传 `dio:` 则在构造时立即套用，或稍后自行调 `apply(dio)`。`enabled: false` 让 `apply` 永久失效。

```dart
DiomanEnvs(dio: dio, [
  EnvRule(rule: () => kDebug, config: BaseOptions(baseUrl: 'https://dev.api')),
  EnvRule(rule: () => true,   config: BaseOptions(baseUrl: 'https://api')), // 兜底
]);
```

### DiomanRepath

`DiomanRepath({bool removeKey = true, bool enabled = true, RegExp? pattern})`——`pattern` 默认匹配路径里的 `{id}`、`:id`、`[id]`；命中后用 `queryParameters`（再 `data`）里的值替换。默认替换后从源 map 删除该键，避免又被当参数发出去。

### DiomanFilter

`DiomanFilter({bool Function(String, dynamic)? predicate, List<String> ignoreKeys = const [], List<dynamic> ignoreValues = const [], bool enabled = true})`——从 `queryParameters` 与 `Map` body 中剔除“空”字段（`predicate` 默认 `null` 与空白字符串）。用 `ignoreKeys`/`ignoreValues` 保留特定键/值。

### DiomanKey

`DiomanKey({bool fastMode = false, List<String> ignoreKeys = const [], bool enabled = true, String Function(RequestOptions)? builder})`——写入 `extra[kRequestKey]`（固定的跨插件协议 key，值为 `'dioman:key'`）。`fastMode` → `METHOD:path`；默认（`fastMode: false`，deep）还会拼入排序后的 query 与 body——`ignoreKeys` 同时从两者中排除指定名字。不可序列化的 body（FormData / bytes / stream）会拼入对象 identity，保证两个不同 body 不会得到相同 key（不会被误去重/误缓存）。可用 `extra['dioman:qid'] = const DiomanKeyOptions(key: '...')` 单请求覆盖（或 `enabled: false` 跳过）。

### DiomanNormalize——可选、跟业务相关，装在最后

跟本包其它插件不一样，`DiomanNormalize` 不是传输层的事——它只是针对**某一种**信封约定（`{code, data, message}`）的便利转换，不是每个 API 都这么包。适合就用，不适合（后端不封装，或者封装方式不一样、想自己手动拆）就完全不装。正因如此，它被刻意排除在[快速上手](#快速上手)和[推荐顺序](#推荐顺序)的硬约束列表之外。

**如果要用，装在最后**——排在 `log` 后面，整条链的最末尾（这也是 `Dioman.install` 放置它的位置，不管你在 `normalize:` 这个具名参数传在调用的第几个）。这样其它所有插件看到的都是响应在线路上原本的样子，不是已经被解包过的。

`DiomanNormalize({String dataKey = 'data', String codeKey = 'code', String messageKey = 'message', bool enabled = true, bool Function(dynamic)? isSuccess, bool Function(RequestOptions, Response)? shouldNormalize})`——成功信封时把 `response.data` 换成内层负载；非成功 `code` 则以 `ApiException` reject，让错误处理统一到拦截器层。默认仅当 body 是含 `codeKey` **且**含 `dataKey` 或 `messageKey` 的 `Map` 时才处理（避免把仅仅带 `code` 字段的普通负载误判成信封），`isSuccess` 默认为 `code == 0`。

### DiomanCache

`DiomanCache({int expires = 60000, CacheClone clone = CacheClone.shallow, int maxEntries = 500, bool enabled = true, bool Function(RequestOptions)? shouldCache, DateTime Function() now = DateTime.now})`——**毫秒**级 TTL 缓存，以 `extra[kRequestKey]` 为键（需 `DiomanKey`）。默认只缓存 `GET`。命中会**提升为最近使用**，因此超过 `maxEntries`（`0` 关闭上限）时按真正的 LRU 淘汰。`CacheClone` 控制命中数据的可变安全性，默认 `shallow`（命中方改顶层字段不会污染缓存；嵌套改用 `deep`，只读零拷贝用 `none`）。`now` 可注入时钟做确定性 TTL 测试。管理接口：`remove(key)`、`removeWhere(test)`、`clear()`、`size`。

### DiomanShare

`DiomanShare({SharePolicy policy = SharePolicy.start, int retries = 3, Duration interval = Duration.zero, bool enabled = true})`——合并同 key 的并发请求。

| 策略 | 行为 |
|---|---|
| `start` | 第一个跑，其余等它的结果（只发一次 HTTP）。 |
| `end` | 后来的取代先前的，所有调用方拿**最后一个**结果。 |
| `race` | 都发，**第一个成功**的胜出并分发给所有人。 |
| `retry` | 共享 promise 且内部重试，调用方看不到重试过程。 |
| `none` | 关闭。 |

### DiomanMock

`DiomanMock({bool enabled = false, String? mockUrl, MockFallbackDecider? fallbackWhen, Map<String, MockHandler>? routes})`——`fallbackWhen` 默认 `defaultFallback`（404 或网络错误，用户主动取消除外）；`routes` 默认为空。用 `METHOD:path` 匹配内联处理器，否则转发到 `mockUrl`；遇 404/网络错误则**回落到真实 API**。用 `add('GET:/pet', ...)`、`remove`、`reset` 管理路由。

### DiomanCancel

`DiomanCancel({bool enabled = true})`——为没有 `CancelToken` 的请求注入一个并登记。`cancelAll([reason])` 中断全部在途；顶层 `cancelAll(dio, [reason])` 会在某个 `Dio` 上找到该插件并调用。`enabled: false` 彻底关闭注入/追踪。

### DiomanLoading

`DiomanLoading({required void Function(bool) onChanged, bool enabled = true})`——`onChanged` 必填，无默认值。第一个请求开始时 `onChanged(true)`，最后一个结束时 `onChanged(false)`。`activeCount` 暴露当前在途数。（`DiomanLoadingOptions` 也带一个 `onChanged` 字段镜像这个构造参数，纯粹结构对称——单请求覆盖时不会读它，因为单次调用换掉共享计数器的回调会打乱加/减配对。）

### DiomanAuth

`DiomanAuth({required tokenManager, required onRefresh, required onAccessExpired, onAccessDenied, onFailure, ready, isProtected, expiresAt, Duration refreshLeeway = Duration.zero, DateTime Function() now = DateTime.now, String headerKey = 'Authorization', String Function(String)? buildHeader, bool enabled = true})`——`buildHeader` 默认生成 `'Bearer $token'`。注入 token，并在 401/403 时路由到五种 `AuthFailureAction`（`refresh` / `replay` / `deny` / `expired` / `others`），且**共享单个刷新窗口**（并发请求只触发一次刷新，其余等待）。实现 `ITokenManager`（`accessToken`、`refreshToken`、`canRefresh`、`clear()`）来对接。默认保护所有请求；用 `isProtected` 或 `extra['dioman:auth'] = const DiomanAuthOptions(enabled: false)` 排除公开接口。

**主动刷新（可选开启）。** 传入 `expiresAt: (token) => DateTime?`（例如解 JWT 的 `exp`），插件会在**发送前**刷新已过期的 token（含 `refreshLeeway` 提前量），让请求带着新 token 一次发出，省掉一轮 401 往返。并发的过期请求会收敛到同一个共享刷新窗口（只刷一次、其余等待、全部注入新 token），因此**无需 `QueuedInterceptor`/串行化**。不传 `expiresAt` 时行为纯被动（与原来一致）——401 路径仍覆盖客户端无法预判的服务端吊销。对无法判断过期的 token，让 `expiresAt` 返回 `null`。

> **`expiresAt` 是普通运行时开关，不是模式切换。** `DiomanAuth` 始终是普通（并行）`Interceptor`；传 `expiresAt` 只是给 `onRequest` 加一段发送前过期预检，「只刷一次」两种情况下都靠共享 `_refreshing` future 保证——从不靠把拦截器串行化。
>
> **何时开启。** 这是**靶向优化**，不是通用改进——不划算就别开：
> - **仅当**token 带**可信**过期时间（JWT `exp`、时钟正常）**且**命中以下之一才开：token 边界的突发并发（如 App 息屏后恢复，一次并发多请求）、延迟敏感的 idle 后首个请求（省约 1 个 RTT）、对 401 噪音敏感的基建（WAF/限流/告警）。
> - **保持关闭**：opaque/无 `exp` 的 token、低并发应用、或服务端可能提前吊销的 token——被动 401 路径更简单也够用，且它本来就一直在跑。
> - **需权衡的失败模式**：若 `expiresAt` 判「已过期」但服务端其实还认（客户端时钟偏快，或服务端有 grace 期），你会白刷一次 + 该请求被刷新拖慢，而被动路径本可直接成功。`refreshLeeway` 保持小值。

### DiomanRetry

`DiomanRetry({int max = 0, Duration Function(int attempt)? delay, bool enabled = true, bool Function(DioException)? retryIf, bool Function(Response)? isExceptionRequest, void Function(int attempt)? onRetry})`——`delay` 默认指数退避（`1s, 2s, 4s`）；`retryIf` 默认网络超时、连接错误、`statusCode >= 500 && != 501`。在 `onError` 路径重试，也可选地把 body 不满足 `isExceptionRequest` 的 2xx 视为失败（业务级重试，判断的是**原始**响应体——见[DiomanNormalize](#diomannormalize可选跟业务相关装在最后)）。

重新发起走的是一个一次性、不带拦截器的裸 `Dio()`——跟 `DiomanAuth` 的重放、`DiomanShare` 自己的 `policy=retry` 是同一套模式。它永远不会重新进入这条链，所以重试出来的响应**不会**被重新缓存、去重、或重新 normalize，`DiomanAuth` 也没机会为它再刷新一次 token。`share`/`cancel` 是可设置的属性（不是构造参数）——设成链上其它位置装的同一个实例，能让 `DiomanShare` 去重、`cancelAll()` 正确感知到正在重试中的请求；只要同时给 `Dioman.install` 传了 `share:`/`cancel:` 和 `retry:`，`install` 会自动帮你设好，只有自己手动接线时才需要手动调这两个 setter。`onRetry` 是个轻量的 `(attempt) {}` 钩子，给你自己接日志用的，因为重新发起根本不会经过 `DiomanLog`。

### DiomanLog

`DiomanLog({bool logRequest = true, bool logResponse = true, bool logError = true, bool logHeaders = false, bool logBody = true, int maxBodyLength = 1000, bool enabled = true, LogWriter? writer})`——默认用 `print`；注入 `writer` 可转发到任意日志框架。

## 单请求级覆盖

在单次调用上传 `options.extra` 即可关闭/重配某插件。每个插件的 `name` **就是**它固定的
`extra` key，值永远是该插件自己的 `DiomanXxxOptions` 类型——完整用法见[各插件 `extra`
参数一览](#各插件-extra-参数一览)：

| `extra` key（`= name`） | 插件 | Options 类型 | 效果 |
|---|---|---|---|
| `dioman:auth` | auth | `DiomanAuthOptions` | `enabled: false` → 本次不需要 token。 |
| `dioman:qid` | key | `DiomanKeyOptions` | `key: '...'` 覆盖 key；`enabled: false` 跳过生成。 |
| `dioman:cache` | cache | `DiomanCacheOptions` | `enabled: false` 跳过；`expires`/`clone` 单次配置。 |
| `dioman:share` | share | `DiomanShareOptions` | `enabled: false` 关闭；`policy` 覆盖。 |
| `dioman:mock` | mock | `DiomanMockOptions` | `enabled: false` 跳过；`mockUrl` 覆盖目标。 |
| `dioman:loading` | loading | `DiomanLoadingOptions` | `enabled: false` → 不计入指示器。 |
| `dioman:log` | log | `DiomanLogOptions` | `enabled: false` → 本次不记日志。 |
| `dioman:retry` | retry | `DiomanRetryOptions` | `max`/`isException` 单次配置；`enabled: false` 跳过。 |
| `dioman:filter` | filter | `DiomanFilterOptions` | `enabled: false` 跳过；`ignoreKeys`/`ignoreValues` 单次配置。 |
| `dioman:repath` | repath | `DiomanRepathOptions` | `enabled: false` 跳过替换。 |
| `dioman:normalize` | normalize | `DiomanNormalizeOptions` | `enabled: false` 跳过拆信封。 |

```dart
dio.get('/public/config', options: Options(extra: {
  'dioman:auth': const DiomanAuthOptions(enabled: false),
  'dioman:cache': const DiomanCacheOptions(enabled: false),
  'dioman:loading': const DiomanLoadingOptions(enabled: false),
}));
```

## 自定义插件

```dart
class TimingPlugin extends DiomanPlugin {
  @override
  String get name => 'timing';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_t0'] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final t0 = response.requestOptions.extra['_t0'] as int?;
    if (t0 != null) print('${response.requestOptions.uri} took '
        '${DateTime.now().millisecondsSinceEpoch - t0}ms');
    handler.next(response);
  }
}
```

然后按它的请求/响应职责，插到列表中对应的位置（见[推荐顺序](#推荐顺序)）。

## 行为与语义说明

- **Dio 是正向顺序，不是洋葱。** `onRequest`、`onResponse`、`onError` 都按添加顺序遍历。整份[推荐顺序](#推荐顺序)都由这一点加上上面的“短路 / 错误 resolve”规则推导而来。
- **`DiomanRetry` 的重新发起是裸Dio，不是重入。** 它永远不会重新进入这条链——具体对`DiomanCache`/`DiomanShare`/`DiomanAuth`/`DiomanLog`意味着什么、以及为什么`isExceptionRequest`永远看到的是原始（未经`DiomanNormalize`处理的）body，见它自己那一节。
- **短路会跳过响应拦截器。** cache/share/mock 的 `resolve()`（默认 `false`）直接把结果返回调用方，不再走后续任何 `onResponse`。这正是括号类插件（`cancel`/`loading`）放在它们**之后**的原因——命中时它们根本不会 +1。
- **单刷新窗口。** 并发的 401 只触发一次 `onRefresh`，其余等待后重放。

## License

MIT
