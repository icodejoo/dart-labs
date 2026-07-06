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

每个插件都继承 `DioPlugin`（一个带 `name` 与 `dispose()` 的命名 `Interceptor`），可单独使用。

| 插件 | 作用 |
|---|---|
| `EnvsPlugin` | 安装时一次性套用分环境的 `BaseOptions`（baseUrl/超时/头）。 |
| `RepathPlugin` | 用 query/body 里的值替换路径变量 `{id}` / `:id` / `[id]`。 |
| `FilterPlugin` | 发送前剔除 query 与 body 里的 `null`/空字段。 |
| `KeyPlugin` | 计算稳定的单请求 key（`extra[kRequestKey]`），供缓存与去重使用。 |
| `NormalizePlugin` | 拆 `{code,data,message}` 信封；非成功码转成 `ApiException` 抛出。 |
| `CachePlugin` | 带 TTL 的响应缓存，支持 `none`/`shallow`/`deep` 克隆策略。 |
| `SharePlugin` | 同 key 并发请求去重（`start`/`end`/`race`/`retry`）。 |
| `MockPlugin` | 基于路由的 mock（内联处理器或 mock 服务器），失败自动回落真实 API。 |
| `CancelPlugin` | 给每个请求注入 `CancelToken`；`cancelAll()` 一键中断在途请求。 |
| `LoadingPlugin` | 在途请求计数 → 单一 `onChanged(bool)`，驱动全局 loading。 |
| `AuthPlugin` | 注入 token + 单窗口 401/403 刷新重放（5 种失败动作）。 |
| `RetryPlugin` | 按退避重试网络（可选业务）失败。 |
| `LogPlugin` | 零依赖的请求/响应/错误日志，输出方式可注入。 |

## 安装

```yaml
dependencies:
  dioman: ^0.3.0
```

```dart
import 'package:dioman/dioman.dart';
```

## 快速上手

下面按**canonical 顺序**（见[推荐顺序](#推荐顺序)）排列插件——直接复制即已是正确顺序；增删插件时原地改，不用挪动其余的。

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

// envs → repath → filter → key → normalize → cache →
// share → mock → cancel → loading → auth → retry → log
dio.interceptors.addAll(<DioPlugin>[
  EnvsPlugin(dio: dio, [
    EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://api.example.com')),
  ]),
  RepathPlugin(),                 // /users/{id}  → /users/42
  const FilterPlugin(), // 剔除空参数
  const KeyPlugin(),         // 缓存/去重的 key
  const NormalizePlugin(),        // {code,data,message} → data
  CachePlugin(),                  // TTL 缓存（GET）
  SharePlugin(),                  // 并发去重
  MockPlugin(),                   // 默认 enabled: false——仅开发用
  CancelPlugin(),
  LoadingPlugin(onChanged: (busy) => showSpinner(busy)),
  AuthPlugin(
    tokenManager: myTokenManager,
    onRefresh: (tm, _) async { /* 刷新并保存 */ },
    onAccessExpired: (tm, _) async { /* 跳登录 */ },
  ),
  RetryPlugin(dio: dio, max: 2),
  const LogPlugin(),
]);

final res = await dio.get('/users/{id}', queryParameters: {'id': 42});
```

一份完整可运行的接线（含内存版 token 管理器，及注释里的完整排序依据）见 [`example/dioman_example.dart`](./example/dioman_example.dart)。

### 各插件 `extra` 参数一览

每个插件的单请求级开关都来自一个**静态、可覆盖**的 `configProperty` 字段——不是硬编码字符串——这样 key 就不会和其他包的 `extra` 用法撞车，也无需改插件内部就能改名。`extra` 的**值**读法不受影响（依旧是 `dynamic`，运行时按类型判断）；变的只是**键名**。

```dart
await dio.get('/x', options: Options(extra: {
  AuthPlugin.configProperty:      false,                              // dioman:auth  —— 本次跳过鉴权
  KeyPlugin.configProperty:    'my-custom-key',                    // dioman:qid        —— 覆盖计算出的 key（`false` 跳过生成）
  CachePlugin.configProperty:     {'expires': 5000, 'clone': CacheClone.shallow}, // dioman:cache
  SharePlugin.configProperty:     SharePolicy.race,                   // dioman:share      —— 或 `false` 关闭
  MockPlugin.configProperty:      {'mockUrl': 'http://localhost:9999'}, // dioman:mock      —— 或 `false` 跳过
  LoadingPlugin.configProperty:   false,                               // dioman:loading    —— 不计入指示器
  RetryPlugin.configProperty:     {'max': 1, 'isException': (Response r) => false}, // dioman:retry —— 或传 `int` 最大次数，或 `false`
  FilterPlugin.configProperty:  {'ignoreKeys': ['page']},            // dioman:filter     —— 或 `false` 跳过
  RepathPlugin.configProperty:    false,                               // dioman:repath     —— 跳过 `{id}` 替换
  NormalizePlugin.configProperty: false,                               // dioman:normalize  —— 保留信封不拆包
  LogPlugin.configProperty:       false,                               // dioman:log        —— 本次不记日志
}));
```

`CancelPlugin` 与 `EnvsPlugin` 没有单请求级 `extra` 开关（cancel 靠 `cancelAll` 驱动；envs 只在安装时套用一次）。

### 重新映射 key

在任何请求发出**之前**（例如 App 启动时）设置这个静态字段——每个插件都是每次调用时动态读取它：

```dart
LoadingPlugin.configProperty = 'my_app:loading'; // 现在 `extra['my_app:loading'] = false` 才是跳过
```

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
| 5 | `normalize` | — | 拆信封 / 业务错转异常 |
| 6 | `cache` | 命中即返回 | 存**拆包后**的数据 |
| 7 | `share` | 并发去重 | 唤醒等待者 |
| 8 | `mock` | 开发覆盖 / 回落 | — |
| 9 | `cancel` | 注入 `CancelToken` | 释放 token |
| 10 | `loading` | 计数 +1 | 计数 -1（括号） |
| 11 | `auth` | 注入 token / 等刷新 | 401 → 刷新 + 重放 |
| 12 | `retry` | — | 重试网络失败 |
| 13 | `log` | 记录请求 | 记录响应 / 错误 |

**为什么是这些位置（硬约束）：**

- **`key` 在 `cache` 与 `share` 之前**——它们读 `extra[kRequestKey]`。
- **`normalize` 在 `cache` 之前**——缓存存入、命中返回的都必须是*拆包后*的数据；否则缓存命中的结构会与实时响应不一致（命中是 `resolve(false)`，会跳过 `normalize`）。
- **`normalize` 在 `auth` 之前**——`auth` 假设业务错误此时已是异常。
- **`cache`/`share`/`mock` 在 `cancel` 与 `loading` 之前**——短路会跳过其后的响应拦截器；若把括号类插件放在它们前面，`onRequest` 里 +1/注入了却永远等不到清理。
- **`cancel` 与 `loading` 在 `auth` 与 `retry` 之前**——401（auth）或网络重试时，这两个插件会 `resolve` 错误并中断正向 `onError` 链；括号必须先跑完，才能把计数减回、把 token 释放。

## 装配：`Dioman.install`

上面的安装顺序是硬约束。与其手工排序，不如把要用的插件传给 `Dioman.install`，它会按 canonical 顺序装配（未传的自动跳过），并返回一个 `DiomanHandle` 用于查找（`handle.plugin<AuthPlugin>()`）、单独移除某个插件（`handle.remove<AuthPlugin>()` 会把它从 `dio.interceptors` 摘除并调用它自己的 `dispose()`，链上其余插件不受影响；若该类型没装过则是空操作，返回 `null`），以及统一销毁（`handle.dispose()` 会摘除**所有**插件并调用每个插件自己的 `dispose()`——这一步没有别处会自动做）。

```dart
final handle = Dioman.install(
  dio,
  key: const KeyPlugin(),
  normalize: const NormalizePlugin(),
  cache: CachePlugin(),
  auth: AuthPlugin(tokenManager: tm, onRefresh: ..., onAccessExpired: ...),
  log: const LogPlugin(),
);

// 稍后只移除某一个插件（例如登出——只摘 AuthPlugin）：
handle.remove<AuthPlugin>();

// ……或者一次性全部摘除：
handle.dispose();
```

## 插件详解

每个插件都提供 `String get name`（用于查找/去重）与 `dispose()`。多数支持从 `options.extra` 读单请求级开关（见[单请求级覆盖](#单请求级覆盖)）。

### EnvsPlugin

`EnvsPlugin(List<EnvRule> rules, {Dio? dio})`——把**第一条命中**规则的 `BaseOptions` 套到 `dio.options`。仅安装时生效（`onRequest` 为空）。传 `dio:` 则在构造时立即套用，或稍后自行调 `apply(dio)`。

```dart
EnvsPlugin(dio: dio, [
  EnvRule(rule: () => kDebug, config: BaseOptions(baseUrl: 'https://dev.api')),
  EnvRule(rule: () => true,   config: BaseOptions(baseUrl: 'https://api')), // 兜底
]);
```

### RepathPlugin

`RepathPlugin({bool removeKey = true, RegExp? pattern})`——`pattern` 默认匹配路径里的 `{id}`、`:id`、`[id]`；命中后用 `queryParameters`（再 `data`）里的值替换。默认替换后从源 map 删除该键，避免又被当参数发出去。

### FilterPlugin

`FilterPlugin({bool Function(String, dynamic)? predicate, List<String> ignoreKeys = const [], List<dynamic> ignoreValues = const []})`——从 `queryParameters` 与 `Map` body 中剔除“空”字段（`predicate` 默认 `null` 与空白字符串）。用 `ignoreKeys`/`ignoreValues` 保留特定键/值。

### KeyPlugin

`KeyPlugin({bool fastMode = false, List<String> ignoreParams = const [], List<String> ignoreDataKeys = const [], String Function(RequestOptions)? builder})`——写入 `extra[kRequestKey]`（固定的跨插件协议 key，值为 `'dioman:key'`）。`fastMode` → `METHOD:path`；默认（`fastMode: false`，deep）还会拼入排序后的 query 与 body。不可序列化的 body（FormData / bytes / stream）会拼入对象 identity，保证两个不同 body 不会得到相同 key（不会被误去重/误缓存）。可用 `extra[KeyPlugin.configProperty]`（默认 `'dioman:qid'`）单请求覆盖。

### NormalizePlugin

`NormalizePlugin({String dataKey = 'data', String codeKey = 'code', String messageKey = 'message', bool Function(dynamic)? isSuccess, bool Function(RequestOptions, Response)? shouldNormalize})`——成功信封时把 `response.data` 换成内层负载；非成功 `code` 则以 `ApiException` reject，让错误处理统一到拦截器层。默认仅当 body 是含 `codeKey` **且**含 `dataKey` 或 `messageKey` 的 `Map` 时才处理（避免把仅仅带 `code` 字段的普通负载误判成信封），`isSuccess` 默认为 `code == 0`。

### CachePlugin

`CachePlugin({int expires = 60000, CacheClone clone = CacheClone.shallow, int maxEntries = 500, bool Function(RequestOptions)? shouldCache, DateTime Function() now = DateTime.now})`——**毫秒**级 TTL 缓存，以 `extra[kRequestKey]` 为键（需 `KeyPlugin`）。默认只缓存 `GET`。命中会**提升为最近使用**，因此超过 `maxEntries`（`0` 关闭上限）时按真正的 LRU 淘汰。`CacheClone` 控制命中数据的可变安全性，默认 `shallow`（命中方改顶层字段不会污染缓存；嵌套改用 `deep`，只读零拷贝用 `none`）。`now` 可注入时钟做确定性 TTL 测试。管理接口：`remove(key)`、`removeWhere(test)`、`clear()`、`size`。

### SharePlugin

`SharePlugin({SharePolicy policy = SharePolicy.start, int retries = 3, Duration interval = Duration.zero})`——合并同 key 的并发请求。

| 策略 | 行为 |
|---|---|
| `start` | 第一个跑，其余等它的结果（只发一次 HTTP）。 |
| `end` | 后来的取代先前的，所有调用方拿**最后一个**结果。 |
| `race` | 都发，**第一个成功**的胜出并分发给所有人。 |
| `retry` | 共享 promise 且内部重试，调用方看不到重试过程。 |
| `none` | 关闭。 |

### MockPlugin

`MockPlugin({bool enabled = false, String? mockUrl, MockFallbackDecider? fallbackWhen, Map<String, MockHandler>? routes})`——`fallbackWhen` 默认 `defaultFallback`（404 或网络错误，用户主动取消除外）；`routes` 默认为空。用 `METHOD:path` 匹配内联处理器，否则转发到 `mockUrl`；遇 404/网络错误则**回落到真实 API**。用 `add('GET:/pet', ...)`、`remove`、`reset` 管理路由。

### CancelPlugin

`CancelPlugin()`——为没有 `CancelToken` 的请求注入一个并登记。`cancelAll([reason])` 中断全部在途；顶层 `cancelAll(dio, [reason])` 会在某个 `Dio` 上找到该插件并调用。

### LoadingPlugin

`LoadingPlugin({required void Function(bool) onChanged})`——`onChanged` 必填，无默认值。第一个请求开始时 `onChanged(true)`，最后一个结束时 `onChanged(false)`。`activeCount` 暴露当前在途数。

### AuthPlugin

`AuthPlugin({required tokenManager, required onRefresh, required onAccessExpired, onAccessDenied, onFailure, ready, isProtected, expiresAt, Duration refreshLeeway = Duration.zero, DateTime Function() now = DateTime.now, String headerKey = 'Authorization', String Function(String)? buildHeader, bool enable = true})`——`buildHeader` 默认生成 `'Bearer $token'`。注入 token，并在 401/403 时路由到五种 `AuthFailureAction`（`refresh` / `replay` / `deny` / `expired` / `others`），且**共享单个刷新窗口**（并发请求只触发一次刷新，其余等待）。实现 `ITokenManager`（`accessToken`、`refreshToken`、`canRefresh`、`clear()`）来对接。默认保护所有请求；用 `isProtected` 或 `extra[AuthPlugin.configProperty] = false` 排除公开接口。

**主动刷新（可选开启）。** 传入 `expiresAt: (token) => DateTime?`（例如解 JWT 的 `exp`），插件会在**发送前**刷新已过期的 token（含 `refreshLeeway` 提前量），让请求带着新 token 一次发出，省掉一轮 401 往返。并发的过期请求会收敛到同一个共享刷新窗口（只刷一次、其余等待、全部注入新 token），因此**无需 `QueuedInterceptor`/串行化**。不传 `expiresAt` 时行为纯被动（与原来一致）——401 路径仍覆盖客户端无法预判的服务端吊销。对无法判断过期的 token，让 `expiresAt` 返回 `null`。

> **`expiresAt` 是普通运行时开关，不是模式切换。** `AuthPlugin` 始终是普通（并行）`Interceptor`；传 `expiresAt` 只是给 `onRequest` 加一段发送前过期预检，「只刷一次」两种情况下都靠共享 `_refreshing` future 保证——从不靠把拦截器串行化。
>
> **何时开启。** 这是**靶向优化**，不是通用改进——不划算就别开：
> - **仅当**token 带**可信**过期时间（JWT `exp`、时钟正常）**且**命中以下之一才开：token 边界的突发并发（如 App 息屏后恢复，一次并发多请求）、延迟敏感的 idle 后首个请求（省约 1 个 RTT）、对 401 噪音敏感的基建（WAF/限流/告警）。
> - **保持关闭**：opaque/无 `exp` 的 token、低并发应用、或服务端可能提前吊销的 token——被动 401 路径更简单也够用，且它本来就一直在跑。
> - **需权衡的失败模式**：若 `expiresAt` 判「已过期」但服务端其实还认（客户端时钟偏快，或服务端有 grace 期），你会白刷一次 + 该请求被刷新拖慢，而被动路径本可直接成功。`refreshLeeway` 保持小值。

### RetryPlugin

`RetryPlugin({required Dio dio, int max = 0, Duration Function(int attempt)? delay, bool Function(DioException)? retryIf, bool Function(Response)? isExceptionRequest})`——`delay` 默认指数退避（`1s, 2s, 4s`）；`retryIf` 默认网络超时、连接错误、`statusCode >= 500 && != 501`。在 `onError` 路径重试。可选地把 body 不满足 `isExceptionRequest` 的 2xx 视为失败（业务级重试——见[行为说明](#行为与语义说明)）。

### LogPlugin

`LogPlugin({bool logRequest = true, bool logResponse = true, bool logError = true, bool logHeaders = false, bool logBody = true, int maxBodyLength = 1000, LogWriter? writer})`——默认用 `print`；注入 `writer` 可转发到任意日志框架。

## 单请求级覆盖

在单次调用上传 `options.extra` 即可关闭/重配某插件。每个键都是一个**静态、可覆盖**的字段
（`XxxPlugin.configProperty`）——默认值与完整用法见[各插件 `extra` 参数一览](#各插件-extra-参数一览)：

| 静态字段 | 插件 | 默认键 | 效果 |
|---|---|---|---|
| `AuthPlugin.configProperty` | auth | `dioman:auth` | `false` → 本次不需要 token。 |
| `KeyPlugin.configProperty` | key | `dioman:qid` | `String` 覆盖 key；`false` 跳过生成。 |
| `CachePlugin.configProperty` | cache | `dioman:cache` | `false` 跳过；`true` 默认；`{expires, clone}` 单次配置。 |
| `SharePlugin.configProperty` | share | `dioman:share` | `false`/`SharePolicy.none` 关闭；传 `SharePolicy` 覆盖。 |
| `MockPlugin.configProperty` | mock | `dioman:mock` | `false` 跳过；`{mockUrl: ...}` 覆盖目标。 |
| `LoadingPlugin.configProperty` | loading | `dioman:loading` | `false` → 不计入指示器。 |
| `LogPlugin.configProperty` | log | `dioman:log` | `false` → 本次不记日志。 |
| `RetryPlugin.configProperty` | retry | `dioman:retry` | `int` 最大次数；`{max, isException}`；`false` 跳过。 |
| `FilterPlugin.configProperty` | filter | `dioman:filter` | `false` 跳过；`{ignoreKeys, ignoreValues}`。 |
| `RepathPlugin.configProperty` | repath | `dioman:repath` | `false` 跳过替换。 |
| `NormalizePlugin.configProperty` | normalize | `dioman:normalize` | `false` 跳过拆信封。 |

```dart
dio.get('/public/config', options: Options(extra: {
  AuthPlugin.configProperty: false,
  CachePlugin.configProperty: false,
  LoadingPlugin.configProperty: false,
}));
```

## 自定义插件

```dart
class TimingPlugin extends DioPlugin {
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
- **业务级重试 vs normalize。** 在推荐顺序下，`RetryPlugin.isExceptionRequest`（靠信封 `code` 判断）无法触发，因为 `normalize`（#5）已在 `retry`（#12）看到之前拆了包。网络级重试不受影响。若确需信封级重试，把 `RetryPlugin` 移到 `NormalizePlugin` 前——但这会让被重试的请求重新出现 loading/cancel 泄漏，需对这些调用设 `extra[LoadingPlugin.configProperty] = false`。
- **短路会跳过响应拦截器。** cache/share/mock 的 `resolve()`（默认 `false`）直接把结果返回调用方，不再走后续任何 `onResponse`。这正是括号类插件（`cancel`/`loading`）放在它们**之后**的原因——命中时它们根本不会 +1。
- **单刷新窗口。** 并发的 401 只触发一次 `onRefresh`，其余等待后重放。

## License

MIT
