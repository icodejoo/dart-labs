# dioman

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/dioman.svg)](https://pub.dev/packages/dioman)
[![Demo](https://img.shields.io/badge/demo-live-brightgreen)](https://icodejoo.github.io/dart-labs/dioman/)

**[▶ 在线演示](https://icodejoo.github.io/dart-labs/dioman/)** —— 交互式请求演练场,无需服务端。

一组**可组合、各自独立**的 [`dio`](https://pub.dev/packages/dio) 拦截器*插件*——鉴权、缓存、重试、并发去重、mock、信封拆包、路径变量、加载态、取消、日志——每个只做一件事；并给出把它们串起来的**正确安装顺序**。

纯 Dart，仅依赖 `dio`——**不依赖 Flutter**。

- [特性](#特性)
- [安装](#安装)
- [快速上手](#快速上手)
- [推荐顺序](#推荐顺序)
- [装配：`Dioman.install`](#装配dioman-install)
- [插件详解](#插件详解)
- [单请求级覆盖](#单请求级覆盖)
- [自定义插件](#自定义插件)

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
| `DiomanNormalize` | *（可选，装在最后）* 拆 `{code,data,message}` 信封；非成功码转成 `DiomanException` 抛出。 |

## 安装

```yaml
dependencies:
  dioman: ^0.6.0
```

```dart
import 'package:dioman/dioman.dart';
```

## 快速上手

把要用的插件传给`Dioman.install`——它会自动按**canonical 顺序**（见[推荐顺序](#推荐顺序)）排位置，
同时传了`share:`/`cancel:`的话，也会自动帮`DiomanRetry`/`DiomanAuth`接好线。

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
  cache: DiomanCache(persist: yourCachePersist),                   // TTL 缓存（GET）
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

一份完整可运行的接线（含内存版 token 管理器）见 [`example/dioman_example.dart`](./example/dioman_example.dart)。

### 各插件 `extra` 参数一览

每个插件的 `name` **就是**它固定的 `extra` key（如 `'dioman:loading'`），同时也是覆盖值的类型判别——单请求覆盖值永远是插件自己的具体类型 `DiomanXxxOptions`。

```dart
await dio.get('/x', options: Options(extra: {
  'dioman:auth':      const DiomanAuthOptions(enabled: false),                       // 本次跳过鉴权
  'dioman:qid':       const DiomanKeyOptions(key: 'my-custom-key'),                  // 覆盖计算出的 key（或 `enabled: false` 跳过生成）
  'dioman:cache':     const DiomanCacheOptions(expires: 5000, clone: CacheClone.shallow),
  'dioman:share':     const DiomanShareOptions(policy: SharePolicy.race),            // 或 `enabled: false` 关闭
  'dioman:mock':      const DiomanMockOptions(mockUrl: 'http://localhost:9999'),      // 或 `enabled: false` 跳过
  'dioman:loading':   const DiomanLoadingOptions(enabled: false),                     // 不计入指示器
  'dioman:retry':     DiomanRetryOptions(max: 1, shouldRetry: (err, r) => false),      // 或 `enabled: false`
  'dioman:filter':    const DiomanFilterOptions(ignoreKeys: ['page']),                // 或 `enabled: false` 跳过
  'dioman:repath':    const DiomanRepathOptions(enabled: false),                      // 跳过 `{id}` 替换
  'dioman:normalize': const DiomanNormalizeOptions(enabled: false),                   // 保留信封不拆包
  'dioman:log':       const DiomanLogOptions(enabled: false),                         // 本次不记日志
}));
```

`DiomanCancel` 与 `DiomanEnvs` 没有单请求级 `extra` 开关——两者改用构造函数级的 `enabled` 开关，控制整个插件是否生效。其余每个插件的构造函数**同样**都带这个 `enabled`（永久关闭整个插件），叠加在各自 `DiomanXxxOptions` 里的单请求级 `enabled` 之上。

每个 `DiomanXxxOptions` 的字段都跟构造函数参数 1:1 对应，且默认值全是 `null`——`null` 代表"继承构造函数当时设的值"。所以 `const DiomanCacheOptions(expires: 5000)` 不会碰 `enabled`/`clone`，也**不会**偷偷把用 `enabled: false` 构造的插件重新打开。`List`/`Map` 字段（`DiomanFilterOptions.ignoreKeys`、`DiomanKeyOptions.ignoreKeys`、`DiomanMockOptions.routes`）是跟插件自身默认值做**合并**（union），不是整体替换。

## 推荐顺序

```
envs → repath → filter → key → cache → share → mock → cancel → loading → auth → retry → log → normalize
```

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

若不走 `Dioman.install`（它已经帮你排好了），手动往 `dio.interceptors` 加插件时要遵守：

- `key` 在 `cache` 与 `share` 之前——它们读 `extra[kRequestKey]`。
- `cache`/`share`/`mock` 在 `cancel` 与 `loading` 之前——避免命中直接短路时，loading 或 cancel 的括号开了却等不到关闭。
- `cancel` 与 `loading` 在 `auth` 与 `retry` 之前——这样 401 或重试把错误 resolve 掉之前，括号的清理已经跑完。
- `normalize` 排最后，在所有插件（包括 `log`）之后——它可选、跟业务相关，其它每个插件都应该看到响应在线路上原本的样子。

## 装配：`Dioman.install`

把要用的插件传进去，会按上面的 canonical 顺序装配（未传的自动跳过）。返回一个 `DiomanHandle` 用于查找（`handle.plugin<DiomanAuth>()`）、单独移除某个插件（`handle.remove<DiomanAuth>()`），以及统一销毁（`handle.dispose()` 摘除所有插件并调用每个插件自己的 `dispose()`）。

需要装一个 `install` 不认识的插件（自定义插件，或想相对 canonical 链条调整顺序）？`handle.insertBefore(anchor, p)`/`handle.insertAfter(anchor, p)` 把 `p` 插到已装好的 `anchor` 插件前/后；`handle.prepend(p)`/`handle.append(p)` 把它插到整条链的最前/最后。这四个方法都会同时把 `p` 接管到 `dio.interceptors` 和 handle 自身上，之后 `plugin<T>()`/`remove<T>()`/`dispose()` 都能看到它。`anchor` 若不是这个 handle 装的插件，`insertBefore`/`insertAfter` 会抛 `ArgumentError`。

`install` 还会在你把同一个 `share:`/`cancel:` 实例也传给 `retry:`/`auth:` 时，自动帮你接好 `DiomanRetry.share`/`.cancel` 跟 `DiomanAuth.share`/`.cancel`（见 [DiomanRetry](#diomanretry)/[DiomanShare](#diomanshare)）。只有自己手动往 `dio.interceptors` 加插件（不走 `install`）时，才需要手动设置那两个 setter。

```dart
final handle = Dioman.install(
  dio,
  key: const DiomanKey(),
  cache: DiomanCache(persist: yourCachePersist),
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

每个插件都提供 `String get name`（用于查找/去重）与 `dispose()`。每个插件的名字也作为类上的 `static const pluginName` 公开（例如 `DiomanCache.pluginName`），无需实例化即可拿到该插件的 `extra` 键。多数支持从 `options.extra` 读单请求级开关（见[单请求级覆盖](#单请求级覆盖)）。

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

`DiomanFilter({bool Function(String, dynamic)? predicate, List<String> ignoreKeys = const [], List<dynamic> ignoreValues = const [], bool enabled = true})`——从 `queryParameters` 与 `Map` body 中剔除"空"字段（`predicate` 默认 `null` 与空白字符串）。用 `ignoreKeys`/`ignoreValues` 保留特定键/值。

### DiomanKey

`DiomanKey({bool fastMode = false, List<String> ignoreKeys = const [], bool enabled = true, String Function(RequestOptions)? builder})`——写入 `extra[kRequestKey]`（固定的跨插件协议 key，值为 `'dioman:key'`）。`fastMode` → `METHOD:path`；默认（`fastMode: false`，deep）还会拼入排序后的 query 与 body——`ignoreKeys` 同时从两者中排除指定名字。可用 `extra['dioman:qid'] = const DiomanKeyOptions(key: '...')` 单请求覆盖（或 `enabled: false` 跳过）。

### DiomanNormalize——可选、跟业务相关，装在最后

不是传输层的事——只是针对**某一种**信封约定（`{code, data, message}`）的便利转换，适合你的 API 就用，不适合就完全不装。正因如此，它被排除在[快速上手](#快速上手)和硬约束顺序表之外——**如果要用，装在最后**，排在 `log` 后面（这也是 `Dioman.install` 放置它的位置，不管参数传在第几个）。

`DiomanNormalize({String dataKey = 'data', String codeKey = 'code', String messageKey = 'message', bool enabled = true, bool Function(dynamic)? isSuccess, bool Function(RequestOptions, Response)? shouldNormalize})`——成功信封时把 `response.data` 换成内层负载；非成功 `code` 则以 `DiomanException` reject。默认仅当 body 是含 `codeKey` **且**含 `dataKey` 或 `messageKey` 的 `Map` 时才处理，`isSuccess` 默认为 `code == 0`。

### DiomanCache

`DiomanCache({required DiomanCachePersist persist, DiomanCachePolicy cachePolicy = DiomanCachePolicy.none, int expires = 60000, CacheClone clone = CacheClone.shallow, int maxEntries = 500, bool enabled = true, bool Function(RequestOptions)? shouldCache, DateTime Function() now = DateTime.now})`——**毫秒**级 TTL 缓存，以 `extra[kRequestKey]` 为键（需 `DiomanKey`）。默认只缓存 `GET`。超过 `maxEntries`（`0` 关闭上限）按 LRU 淘汰（只作用于内存层）。`CacheClone` 控制命中数据的可变安全性：`shallow`（默认，命中方改顶层字段不会污染缓存）、`deep`（嵌套修改也安全）、`none`（只读零拷贝）。`now` 可注入时钟做确定性 TTL 测试。管理接口：`remove(key)`、`clear()`（两者都不管 `cachePolicy` 是什么，永远同时操作内存层和 `persist`）。没有 `removeWhere`/`size`——`DiomanCachePersist` 没有枚举 key 的能力，纯 `persist` 策略下的条目永远无法被批量操作正确覆盖到；需要批量清理就自己在业务层维护 key 列表，逐个调 `remove`。

`persist` **必传**——没有内置的空实现，必须自己实现 `DiomanCachePersist`（`read`/`write`/`remove`/`erase`，接口形状参照 `get_storage` 包的容器 API——`read` 同步，`write`/`remove`/`erase` 异步），接入文件、sqlite、Hive、`get_storage` 或其他任意存储，哪怕你只打算用 `DiomanCachePolicy.memo`。

`cachePolicy`（也可通过 `DiomanCacheOptions.cachePolicy` 按请求覆盖）决定缓存条目存在**哪**，跟是否缓存（仍由 `enabled`/`shouldCache` 决定）是两回事：
- `none`（默认）——完全不缓存该请求，总是直接透传。缓存要显式开启，不会默默生效。
- `memo`——只用内存层 `_store`，和以前行为一样。不持久——重启或 `dispose()` 后丢失，永不读写 `persist`。
- `persist`——只用 `persist`；该请求永不读写内存层。
- `both`——两者同步：写入时 `_store` 和 `persist` 都写；内存未命中时回退读 `persist` 并回填 `_store`，下次同一个 key 就能重新从内存命中。

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

`DiomanLoading({required void Function(bool) onChanged, bool enabled = true})`——第一个请求开始时 `onChanged(true)`，最后一个结束时 `onChanged(false)`。`activeCount` 暴露当前在途数。

### DiomanAuth

`DiomanAuth({required tokenManager, required onRefresh, required onAccessExpired, onAccessDenied, onFailure, ready, isProtected, expiresAt, Duration refreshLeeway = Duration.zero, DateTime Function() now = DateTime.now, String headerKey = 'Authorization', String Function(String)? buildHeader, bool enabled = true})`——`buildHeader` 默认生成 `'Bearer $token'`。注入 token，并在 401/403 时路由到五种 `AuthFailureAction`（`refresh` / `replay` / `deny` / `expired` / `others`），且**共享单个刷新窗口**（并发请求只触发一次刷新，其余等待）。实现 `ITokenManager`（`accessToken`、`refreshToken`、`canRefresh`、`clear()`）来对接。默认保护所有请求；用 `isProtected` 或 `extra['dioman:auth'] = const DiomanAuthOptions(enabled: false)` 排除公开接口。

**主动刷新（可选开启）。** 传入 `expiresAt: (token) => DateTime?`（例如解 JWT 的 `exp`），插件会在发送前刷新已过期的 token（含 `refreshLeeway` 提前量），避免一轮注定失败的 401 往返。并发的过期请求会共享同一个刷新窗口。不传 `expiresAt` 时行为纯被动（只走 401 路径）。适合在 token 带可信过期时间、且遇到 token 边界突发并发、延迟敏感的首个请求、或对 401 噪音敏感的基建时开启；否则被动路径更简单也够用。

### DiomanRetry

`DiomanRetry({int max = 0, List<String>? methods, DiomanShouldRetry? shouldRetry, List<int>? statusCodes, DiomanRetryDelay? delay, Object? jitter, Duration? delayMax, bool enabled = true, bool respectRetryAfter = true, List<int>? afterStatusCodes, Duration? retryAfterMax, void Function(int attempt)? onRetry})`——`methods`（默认`[GET,PUT,HEAD,DELETE,OPTIONS,TRACE]`）最先检查，是`shouldRetry`说了也不算的硬性否决。`delay`默认固定`3000ms`；`jitter`（`true`或`Duration Function(Duration)`）和`delayMax`叠加在其上。`shouldRetry`不设默认值——返回明确的`true`/`false`直接采用，返回`null`退回`statusCodes`（默认`[408,429,500,502,503,504]`），只有完全没有HTTP状态码时（纯网络失败）才进一步退回超时/连接错误判定。`onError`路径以`shouldRetry(err, err.response)`调用（网络级重试），`onResponse`路径以`shouldRetry(null, response)`调用（业务级重试——把body判定为失败的2xx也视为失败，判断的是原始响应体）。响应带`Retry-After`头（数字秒或RFC 1123格式HTTP-date）且状态码在`afterStatusCodes`内（默认`[413,429,503]`）、`respectRetryAfter`为true（默认）时，优先听它而不算`delay`，由`retryAfterMax`封顶。

`share`/`cancel` 是可设置的属性（不是构造参数）——设成链上其它位置装的同一个实例，能让 `DiomanShare` 去重、`cancelAll()` 正确感知到正在重试中的请求；只要同时给 `Dioman.install` 传了 `share:`/`cancel:` 和 `retry:`，会自动帮你设好。`onRetry` 是个轻量的 `(attempt) {}` 钩子，给你自己接日志用。

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
| `dioman:retry` | retry | `int` \| `false` \| `DiomanRetryOptions` | `int`只覆盖`max`；`false`禁用（最高优先级否决）；对象形式覆盖任意字段（`max`/`methods`/`shouldRetry`/`statusCodes`/`delay`/`jitter`/`delayMax`/`respectRetryAfter`/`afterStatusCodes`/`retryAfterMax`/`enabled`）。 |
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

## License

MIT
