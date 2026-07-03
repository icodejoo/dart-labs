# dioplus

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/dioplus.svg)](https://pub.dev/packages/dioplus)

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
| `NormalizeRequestPlugin` | 发送前剔除 query 与 body 里的 `null`/空字段。 |
| `BuildKeyPlugin` | 计算稳定的单请求 key（`extra['_key']`），供缓存与去重使用。 |
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
  dioplus: ^0.1.0
```

```dart
import 'package:dioplus/dioplus.dart';
```

## 快速上手

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

dio.interceptors.addAll(<DioPlugin>[
  RepathPlugin(),                 // /users/{id}  → /users/42
  const NormalizeRequestPlugin(), // 剔除空参数
  const BuildKeyPlugin(),         // 缓存/去重的 key
  const NormalizePlugin(),        // {code,data,message} → data
  CachePlugin(),                  // TTL 缓存（GET）
  SharePlugin(),                  // 并发去重
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

一份完整可运行的接线（含内存版 token 管理器，及注释里的完整排序依据）见 [`example/dioplus_example.dart`](./example/dioplus_example.dart)。

## 推荐顺序

因为 Dio 三个阶段**都是正向顺序**，同一个列表要同时满足请求、响应、错误三条链。两条事实决定一切：

1. 短路——`onRequest` 里的 `handler.resolve()`（缓存命中 / share 等待 / mock 命中）会**跳过其后所有响应拦截器**。
2. `onError` 链会正向走完**每个**拦截器，而第一个 `resolve()` 的（auth 的 401 重放、retry）会**终止其余**。

| # | 插件 | 请求阶段职责 | 响应/错误阶段职责 |
|---|---|---|---|
| 1 | `envs` | （安装时套用配置） | — |
| 2 | `repath` | 替换 `{id}`/`:id` 路径 | — |
| 3 | `normalize-request` | 剔除空参数/数据 | — |
| 4 | `build-key` | 计算请求 key | — |
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

- **`build-key` 在 `cache` 与 `share` 之前**——它们读 `extra['_key']`。
- **`normalize` 在 `cache` 之前**——缓存存入、命中返回的都必须是*拆包后*的数据；否则缓存命中的结构会与实时响应不一致（命中是 `resolve(false)`，会跳过 `normalize`）。
- **`normalize` 在 `auth` 之前**——`auth` 假设业务错误此时已是异常。
- **`cache`/`share`/`mock` 在 `cancel` 与 `loading` 之前**——短路会跳过其后的响应拦截器；若把括号类插件放在它们前面，`onRequest` 里 +1/注入了却永远等不到清理。
- **`cancel` 与 `loading` 在 `auth` 与 `retry` 之前**——401（auth）或网络重试时，这两个插件会 `resolve` 错误并中断正向 `onError` 链；括号必须先跑完，才能把计数减回、把 token 释放。

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

`RepathPlugin({bool removeKey = true, RegExp? pattern})`——用 `queryParameters`（再 `data`）里的值替换路径中的 `{id}`、`:id`、`[id]`。默认替换后从源 map 删除该键，避免又被当参数发出去。

### NormalizeRequestPlugin

`NormalizeRequestPlugin({predicate, ignoreKeys, ignoreValues})`——从 `queryParameters` 与 `Map` body 中剔除“空”字段（默认 `null` 与空白字符串）。用 `ignoreKeys`/`ignoreValues` 保留特定键/值。

### BuildKeyPlugin

`BuildKeyPlugin({bool fastMode = false, ignoreParams, ignoreDataKeys, builder})`——写入 `extra['_key']`。`fastMode` → `METHOD:path`；默认（deep）还会拼入排序后的 query 与 body。可用 `extra['key']` 单请求覆盖。

### NormalizePlugin

`NormalizePlugin({dataKey='data', codeKey='code', messageKey='message', isSuccess, shouldNormalize})`——成功信封时把 `response.data` 换成内层负载；非成功 `code` 则以 `ApiException` reject，让错误处理统一到拦截器层。默认仅当 body 是含 `codeKey` 的 `Map` 时才处理，`isSuccess` 默认为 `code == 0`。

### CachePlugin

`CachePlugin({int expires = 60000, CacheClone clone = none, shouldCache})`——**毫秒**级 TTL 缓存，以 `extra['_key']` 为键（需 `BuildKeyPlugin`）。默认只缓存 `GET`。`CacheClone` 控制命中数据的可变安全性（`none`/`shallow`/`deep`）。管理接口：`remove(key)`、`removeWhere(test)`、`clear()`、`size`。

### SharePlugin

`SharePlugin({SharePolicy policy = start, int retries = 3, Duration interval})`——合并同 key 的并发请求。

| 策略 | 行为 |
|---|---|
| `start` | 第一个跑，其余等它的结果（只发一次 HTTP）。 |
| `end` | 后来的取代先前的，所有调用方拿**最后一个**结果。 |
| `race` | 都发，**第一个成功**的胜出并分发给所有人。 |
| `retry` | 共享 promise 且内部重试，调用方看不到重试过程。 |
| `none` | 关闭。 |

### MockPlugin

`MockPlugin({bool enabled = false, mockUrl, fallbackWhen, routes})`——用 `METHOD:path` 匹配内联处理器，否则转发到 `mockUrl`；遇 404/网络错误则**回落到真实 API**。用 `add('GET:/pet', ...)`、`remove`、`reset` 管理路由。

### CancelPlugin

`CancelPlugin()`——为没有 `CancelToken` 的请求注入一个并登记。`cancelAll([reason])` 中断全部在途；顶层 `cancelAll(dio, [reason])` 会在某个 `Dio` 上找到该插件并调用。

### LoadingPlugin

`LoadingPlugin({required void Function(bool) onChanged})`——第一个请求开始时 `onChanged(true)`，最后一个结束时 `onChanged(false)`。`activeCount` 暴露当前在途数。

### AuthPlugin

`AuthPlugin({required tokenManager, required onRefresh, required onAccessExpired, onAccessDenied, onFailure, ready, isProtected, headerKey = 'Authorization', buildHeader, enable = true})`——注入 token，并在 401/403 时路由到五种 `AuthFailureAction`（`refresh` / `replay` / `deny` / `expired` / `others`），且**共享单个刷新窗口**（并发请求只触发一次刷新，其余等待）。实现 `ITokenManager`（`accessToken`、`refreshToken`、`canRefresh`、`clear()`）来对接。默认保护所有请求；用 `isProtected` 或 `extra['protected'] = false` 排除公开接口。

### RetryPlugin

`RetryPlugin({required Dio dio, int max = 0, delay, retryIf, isExceptionRequest})`——在 `onError` 路径重试（默认网络超时、5xx），指数退避（`1s, 2s, 4s`）。可选地把 body 不满足 `isExceptionRequest` 的 2xx 视为失败（业务级重试——见[行为说明](#行为与语义说明)）。

### LogPlugin

`LogPlugin({logRequest, logResponse, logError, logHeaders, logBody, maxBodyLength = 1000, writer})`——默认用 `print`；注入 `writer` 可转发到任意日志框架。

## 单请求级覆盖

在单次调用上传 `options.extra` 即可关闭/重配某插件：

| 键 | 插件 | 效果 |
|---|---|---|
| `protected` | auth | `false` → 本次不需要 token。 |
| `key` | build-key | `String` 覆盖 key；`false` 跳过生成。 |
| `cache` | cache | `false` 跳过；`true` 默认；`{expires, clone}` 单次配置。 |
| `share` | share | `false`/`SharePolicy.none` 关闭；传 `SharePolicy` 覆盖。 |
| `mock` | mock | `false` 跳过；`{mockUrl: ...}` 覆盖目标。 |
| `loading` | loading | `false` → 不计入指示器。 |
| `log` | log | `false` → 本次不记日志。 |
| `retry` | retry | `int` 最大次数；`{max, isException}`；`false` 跳过。 |
| `filter` | normalize-request | `false` 跳过；`{ignoreKeys, ignoreValues}`。 |
| `repath` | repath | `false` 跳过替换。 |
| `normalize` | normalize | `false` 跳过拆信封。 |

```dart
dio.get('/public/config', options: Options(extra: {
  'protected': false, 'cache': false, 'loading': false,
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
- **业务级重试 vs normalize。** 在推荐顺序下，`RetryPlugin.isExceptionRequest`（靠信封 `code` 判断）无法触发，因为 `normalize`（#5）已在 `retry`（#12）看到之前拆了包。网络级重试不受影响。若确需信封级重试，把 `RetryPlugin` 移到 `NormalizePlugin` 前——但这会让被重试的请求重新出现 loading/cancel 泄漏，需对这些调用设 `extra['loading'] = false`。
- **短路会跳过响应拦截器。** cache/share/mock 的 `resolve()`（默认 `false`）直接把结果返回调用方，不再走后续任何 `onResponse`。这正是括号类插件（`cancel`/`loading`）放在它们**之后**的原因——命中时它们根本不会 +1。
- **单刷新窗口。** 并发的 401 只触发一次 `onRefresh`，其余等待后重放。

## License

MIT
