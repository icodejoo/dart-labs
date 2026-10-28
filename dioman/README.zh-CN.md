# dioman

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/dioman.svg)](https://pub.dev/packages/dioman)
[![Demo](https://img.shields.io/badge/demo-live-brightgreen)](https://icodejoo.github.io/dart-labs/dioman/)

**[▶ 在线演示](https://icodejoo.github.io/dart-labs/dioman/)** —— 交互式请求演练场,无需服务端。

一组**可组合、各自独立**的 [`dio`](https://pub.dev/packages/dio) 拦截器*插件*——鉴权、缓存、重试、熔断、动态超时、断网队列、并发去重、mock、信封拆包、路径变量、加载态、取消、日志——每个只做一件事；并给出把它们串起来的**正确安装顺序**。

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
| `DiomanTimeout` | 按注入的网络质量档位，per-request 设置 connect/receive/send 超时。 |
| `DiomanRepath` | 用 query/body 里的值替换路径变量 `{id}` / `:id` / `[id]`。 |
| `DiomanFilter` | 发送前剔除 query 与 body 里的 `null`/空字段。 |
| `DiomanKey` | 计算稳定的单请求 key（`extra[kKey]`），供缓存与去重使用。 |
| `DiomanCache` | 带 TTL 的响应缓存，支持 `none`/`shallow`/`deep` 克隆策略。 |
| `DiomanOffline` | 断网时请求入队，联网恢复后重放。 |
| `DiomanShare` | 同 key 并发请求去重（`start`/`end`/`race`/`retry`）。 |
| `DiomanMockAdapter` | 传输层 mock（仅开发/测试）：内联路由或 mock 服务器，失败自动回落真实 API。包装 `dio.httpClientAdapter`，不是插件，没有安装顺序。 |
| `DiomanCancel` | 给每个请求注入 `CancelToken`；`cancelAll()` 一键中断在途请求。 |
| `DiomanLoading` | 在途请求计数 → 单一 `onChanged(bool)`，驱动全局 loading。 |
| `DiomanAuth` | 注入 token + 单窗口 401/403 刷新重放（5 种失败动作）。 |
| `DiomanRetry` | 按退避重试网络（可选业务）失败。 |
| `DiomanBreaker` | 熔断器：按 `METHOD:path` 连续失败后熔断、fail-fast，冷却后探测恢复。 |
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
同时会把宿主`Dio`绑定给会重放请求的`DiomanShare`/`DiomanAuth`/`DiomanRetry`。

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
  'dioman:cache':     const DiomanCacheOptions(expires: 5000, clone: DiomanClonePolicy.shallow),
  'dioman:offline':   const DiomanOfflineOptions(enabled: false),                      // 断网时本次不入队
  'dioman:share':     const DiomanShareOptions(policy: SharePolicy.race),            // 或 `enabled: false` 关闭
  'dioman:mock':      const DiomanMockOptions(mockUrl: 'http://localhost:9999'),      // 由 DiomanMockAdapter 读取；或 `enabled: false` 跳过
  'dioman:loading':   const DiomanLoadingOptions(enabled: false),                     // 不计入指示器
  'dioman:retry':     DiomanRetryOptions(max: 1, shouldRetry: (err, r) => false),      // 或 `enabled: false`
  'dioman:breaker':   const DiomanBreakerOptions(enabled: false),                      // 本次跳过熔断器
  'dioman:filter':    const DiomanFilterOptions(ignoreKeys: ['page']),                // 由 DiomanMockAdapter 读取；或 `enabled: false` 跳过
  'dioman:repath':    const DiomanRepathOptions(enabled: false),                      // 跳过 `{id}` 替换
  'dioman:timeout':   const DiomanTimeoutOptions(enabled: false),                     // 本次保留原有超时
  'dioman:normalize': const DiomanNormalizeOptions(enabled: false),                   // 保留信封不拆包
  'dioman:log':       const DiomanLogOptions(enabled: false),                         // 本次不记日志
}));
```

`DiomanCancel` 与 `DiomanEnvs` 没有单请求级 `extra` 开关——两者改用构造函数级的 `enabled` 开关，控制整个插件是否生效。其余每个插件的构造函数**同样**都带这个 `enabled`（永久关闭整个插件），叠加在各自 `DiomanXxxOptions` 里的单请求级 `enabled` 之上。

每个 `DiomanXxxOptions` 的字段都跟构造函数参数 1:1 对应，且默认值全是 `null`——`null` 代表"继承构造函数当时设的值"。所以 `const DiomanCacheOptions(expires: 5000)` 不会碰 `enabled`/`clone`，也**不会**偷偷把用 `enabled: false` 构造的插件重新打开。`List`/`Map` 字段（`DiomanFilterOptions.ignoreKeys`、`DiomanKeyOptions.ignores`、`DiomanMockOptions.routes`）是跟插件自身默认值做**合并**（union），不是整体替换。

## 推荐顺序

```
envs → timeout → repath → filter → key → cache → offline → share → cancel → loading → auth → retry → breaker → log → normalize
```

| # | 插件 | 请求阶段职责 | 响应/错误阶段职责 |
|---|---|---|---|
| 1 | `envs` | （安装时套用配置） | — |
| 2 | `timeout` | 按网络档位设超时 | — |
| 3 | `repath` | 替换 `{id}`/`:id` 路径 | — |
| 4 | `filter` | 剔除空参数/数据 | — |
| 5 | `key` | 计算请求 key | — |
| 6 | `cache` | 命中即返回 | 存原始数据 |
| 7 | `offline` | 断网时入队 | （恢复后重放） |
| 8 | `share` | 并发去重 | 唤醒等待者 |
| 9 | `cancel` | 注入 `CancelToken` | 释放 token |
| 11 | `loading` | 计数 +1 | 计数 -1（括号） |
| 12 | `auth` | 注入 token / 等刷新 | 401 → 刷新 + 重放 |
| 13 | `retry` | — | 重试网络/业务失败 |
| 14 | `breaker` | 熔断开启时 fail-fast | 统计结果，熔断 / 恢复 |
| 15 | `log` | 记录请求 | 记录响应 / 错误 |
| 16 | `normalize` *（可选）* | — | 拆信封 / 业务错转异常 |

若不走 `Dioman.install`（它已经帮你排好了），手动往 `dio.interceptors` 加插件时要遵守：

- `key` 在 `cache` 与 `share` 之前——它们读 `extra[kKey]`。
- `cache` 在 `offline` 之前——断网读命中缓存会在入队前短路（读优先用 stale 缓存）。
- `offline` 在 `share`/`cancel`/`loading` 之前——挂起（入队）的请求绝不能建过 share entry 或开过 cancel/loading 括号，否则等待期间会泄漏。
- `cache`/`share` 在 `cancel` 与 `loading` 之前——避免命中直接短路时，loading 或 cancel 的括号开了却等不到关闭。
- `cancel` 与 `loading` 在 `auth` 与 `retry` 之前——这样 401 或重试把错误 resolve 掉之前，括号的清理已经跑完。
- `breaker` 在 `retry` 之后——这样它只统计每个请求的*最终*结果（被重试救回的算成功，只有重试耗尽的才算失败），不会被重试已吸收的偶发抖动误触发。
- `normalize` 排最后，在所有插件（包括 `log`）之后——它可选、跟业务相关，其它每个插件都应该看到响应在线路上原本的样子。

## 装配：`Dioman.install`

把要用的插件传进去，会按上面的 canonical 顺序装配（未传的自动跳过）。返回一个 `DiomanHandle` 用于查找（`handle.plugin<DiomanAuth>()`）、单独移除某个插件（`handle.remove<DiomanAuth>()`），以及统一销毁（`handle.dispose()` 摘除所有插件并调用每个插件自己的 `dispose()`）。

需要装一个 `install` 不认识的插件（自定义插件，或想相对 canonical 链条调整顺序）？`handle.insertBefore(anchor, p)`/`handle.insertAfter(anchor, p)` 把 `p` 插到已装好的 `anchor` 插件前/后；`handle.prepend(p)`/`handle.append(p)` 把它插到整条链的最前/最后。这四个方法都会同时把 `p` 接管到 `dio.interceptors` 和 handle 自身上，之后 `plugin<T>()`/`remove<T>()`/`dispose()` 都能看到它。`anchor` 若不是这个 handle 装的插件，`insertBefore`/`insertAfter` 会抛 `ArgumentError`。

`install` 还会把宿主 `Dio` 绑定（`.dio`）给 `DiomanShare`/`DiomanAuth`/`DiomanRetry`——重放因此复用宿主的 `httpClientAdapter`/`transformer`，恢复成功的结果也会进入排在它们之后的拦截器（normalize、breaker……）——并在同时传了 `breaker:` 和 `retry:` 时接好 `DiomanRetry.breaker`（见 [DiomanRetry](#diomanretry)/[DiomanShare](#diomanshare)/[DiomanBreaker](#diomanbreaker)）。`DiomanShare`/`DiomanCancel` 的结算交接**不再需要接线**：`DiomanAuth`/`DiomanRetry` 自己在每个请求上登记（旧的 `.share`/`.cancel` setter 已弃用，调用无效果）。只有自己手动往 `dio.interceptors` 加插件（不走 `install`）时，才需要手动设置 `.dio`/`.breaker`；`handle.insertBefore/insertAfter/prepend/append/remove` 会替你绑定和解绑。

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

### 声明式顺序

每个插件可以覆写 `ordering` 声明顺序约束，`Dioman` 对插件集合做稳定拓扑排序并校验。
`Dioman.install` 仍按规范顺序安装：内置插件只声明上表里的硬约束，所以结果与之前完全一致。

```dart
class TimingPlugin extends DiomanPlugin {
  @override
  String get name => 'timing';

  @override
  DiomanPluginOrder get ordering => DiomanPluginOrder(
        after: {DiomanKey.pluginName},    // 必须在 key 之后
        before: {DiomanCache.pluginName}, // 必须在 cache 之前
        requires: {DiomanKey.pluginName}, // key 也必须安装
      );
}

// 把自定义插件混进 install，或只靠约束安装任意一组：
final handle = Dioman.install(dio, key: const DiomanKey(), plugins: [TimingPlugin()]);
final handle2 = Dioman.installPlugins(dio2, [TimingPlugin(), const DiomanKey()]);
final ordered = Dioman.sort(plugins); // 纯函数：返回新列表
```

- `before`/`after` 指向未安装的插件会被忽略（可选依赖）；`requires` 必须存在。
- 无约束的插件保持你给的顺序，被需要的前驱只会提前到刚好满足约束的位置。
- 重复名、环、缺失的 `requires`、以及给定顺序违反约束，都会抛 `DiomanPluginOrderException`
  （带 `issue` 和涉及的插件名）。`install`/`installPlugins` 在改动 `dio` 之前抛出；
  `insertBefore/insertAfter/prepend/append` 先校验，失败时 handle 原样不动；
  `remove` 拒绝移除被其它插件 `requires` 的插件。
- 自己手动管理 `dio.interceptors` 的写法照旧可用，那里不做任何校验。

### `extra` 键注册表

`DiomanExtraKeys` 登记所有 `RequestOptions.extra` 键的所属插件、类别（`config` 公开配置 /
`protocol` 跨插件协议 / `state` 内部状态）和值类型。

```dart
DiomanExtraKeys.lookup('dioman:cache:key');                 // 所属插件、类别、值类型
DiomanExtraKeys.findSharedState(dio.interceptors);          // 重复实例共享状态键的诊断
handle.diagnoseSharedStateKeys();                           // 同上，针对 handle 的 Dio
DiomanExtraKeys.assertNoSharedState(dio.interceptors);      // 仅 debug 生效的断言
DiomanExtraKeys.register(myKey);                            // 自定义插件登记自己的键
```

现有键名和运行时行为都不变。完整键表在 `docs/design/architecture.md`（由 `DiomanExtraKeys.toMarkdown()`
生成，有测试保证同步）。

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

### DiomanTimeout

`DiomanTimeout({required NetworkQuality Function() probe, Map<NetworkQuality, DiomanTimeouts> timeouts = <默认>, bool enabled = true})`——按当前网络档位设置每个请求的 `connect`/`receive`/`send` 超时。纯 Dart：它自己从不检测连通性——由宿主把连接分类成 `NetworkQuality`（`excellent`/`good`/`poor`/`none`）从 `probe` 返回，`probe` 每请求调用一次。每档映射到一个 `DiomanTimeouts(connect?, receive?, send?)`；**只有命中档的非 null 字段才写入**，所以部分配置的档会让其它超时保持 `BaseOptions` 的设定，映射里没有的档对该请求不做任何处理。默认映射随质量下降拉长 connect 超时（`10s`/`15s`/`30s`/`10s`），receive/send 不动。装在最前（紧跟 `DiomanEnvs`）——它是纯 per-request 配置。`none` 这里只是普通一档；fail-fast/断网入队不在范围内。

```dart
final timeout = DiomanTimeout(
  probe: () => myConnectivity.quality, // 你自己的 NetworkQuality 来源
  timeouts: {
    NetworkQuality.poor: const DiomanTimeouts(
      connect: Duration(seconds: 30), receive: Duration(seconds: 30)),
  },
);
```

### DiomanRepath

`DiomanRepath({bool removeKey = true, bool enabled = true, RegExp? pattern})`——`pattern` 默认匹配路径里的 `{id}`、`:id`、`[id]`；命中后用 `queryParameters`（再 `data`）里的值替换。默认替换后从源 map 删除该键，避免又被当参数发出去。

路径替换先快照取值、完成替换后再移除字段，每个值按路径段编码；修改 Map body 前先复制。

### DiomanFilter

`DiomanFilter({bool Function(String, dynamic)? predicate, List<String> ignoreKeys = const [], List<dynamic> ignoreValues = const [], bool enabled = true})`——从 `queryParameters` 与 `Map` body 中剔除"空"字段（`predicate` 默认 `null` 与空白字符串）。用 `ignoreKeys`/`ignoreValues` 保留特定键/值。

### DiomanKey

`DiomanKey({bool fastMode = false, List<String> ignores = const [], bool enabled = true, String Function(RequestOptions)? builder, String? Function()? namespace})`——写入 `extra[kKey]`（固定的跨插件协议 key，值为 `'dioman:key'`）。`fastMode` → `METHOD:origin/path`；默认（`fastMode: false`，deep）还会拼入排序后的 query 与 body——`ignores` 同时从两者中排除指定名字。可用 `extra['dioman:qid'] = const DiomanKeyOptions(key: '...')` 单请求覆盖（或 `enabled: false` 跳过）。

键来源优先级：请求级 `builder` > 请求级非空 `key` > 插件级 `builder` > fast/deep 计算。

deep key 合并 URL 内 query 与 `queryParameters` 后规范化，包含 origin，并分字段编码 query/body，各层 Map 键都排序（List 保持顺序）；非结构化 body 保留对象身份。

同一个 Dio 复用到不同账号时，可通过 `namespace` 隔离缓存与去重。每个启用的请求生成键时调用一次；非空返回值作为独立 JSON 字段与原键字段一起编码，快速模式、指定 key 和自定义 builder 也适用。未设置、返回 `null` 或空串时，键与旧版本完全一致；回调抛异常时以 `DioException` 拒绝请求。

```dart
// 使用非敏感账号标识或不透明会话标识，不要返回明文 token。
String? currentAccountId = 'account-a';
dio.interceptors.add(DiomanKey(namespace: () => currentAccountId));
// cache/share 装在 key 后面；切换账号后，后续请求自然生成不同的键。
currentAccountId = 'account-b';
```

`DiomanKeyOptions` 不新增 namespace 覆盖：通过插件回调统一提供该 Dio 的账号作用域，单请求的 `key`/`builder` 覆盖仍受作用域隔离。切换账号后，旧缓存与在途请求保留原键，不会自动清空或取消。若匿名请求也需隔离，请返回非空的访客作用域。

### DiomanNormalize——可选、跟业务相关，装在最后

不是传输层的事——只是针对**某一种**信封约定（`{code, data, message}`）的便利转换，适合你的 API 就用，不适合就完全不装。正因如此，它被排除在[快速上手](#快速上手)和硬约束顺序表之外——**如果要用，装在最后**，排在 `log` 后面（这也是 `Dioman.install` 放置它的位置，不管参数传在第几个）。

`DiomanNormalize({String dataKey = 'data', String codeKey = 'code', String messageKey = 'message', bool enabled = true, bool Function(dynamic)? isSuccess, bool Function(RequestOptions, Response)? shouldNormalize})`——成功信封时把 `response.data` 换成内层负载；非成功 `code` 则以 `DiomanException` reject。默认仅当 body 是含 `codeKey` **且**含 `dataKey` 或 `messageKey` 的 `Map` 时才处理，`isSuccess` 默认为 `code == 0`。

### DiomanCache

`DiomanCache({required DiomanCachePersist persist, DiomanCachePolicy cachePolicy = DiomanCachePolicy.none, int expires = 60000, DiomanClonePolicy clone = DiomanClonePolicy.shallow, int maxEntries = 500, bool enabled = true, bool Function(RequestOptions)? shouldCache, bool Function(Response<dynamic>)? shouldStore, DateTime Function() now = DateTime.now})`——**毫秒**级 TTL 缓存，以 `extra[kKey]` 为键（需 `DiomanKey`）。默认只缓存 `GET`。超过 `maxEntries`（`0` 关闭上限）按 LRU 淘汰（只作用于内存层）。`DiomanClonePolicy` 控制命中数据的可变安全性：`shallow`（默认，命中方改顶层字段不会污染缓存）、`deep`（嵌套修改也安全）、`none`（只读零拷贝）。`now` 可注入时钟做确定性 TTL 测试。管理接口：`await remove(key)`、`await clear()`（两者都不管 `cachePolicy` 是什么，永远同时操作内存层和 `persist`）。没有 `removeWhere`/`size`——`DiomanCachePersist` 没有枚举 key 的能力，纯 `persist` 策略下的条目永远无法被批量操作正确覆盖到；需要批量清理就自己在业务层维护 key 列表，逐个调 `remove`。`shouldStore(response)` 决定哪些响应写入：只有 HTTP 2xx 且它返回 true 才存（可用 `DiomanCacheOptions.shouldStore` 按请求覆盖）。不设时，若同一 Dio 装了 `DiomanNormalize`，缓存会自动跳过 normalize 判为业务失败的信封。

`persist` **必传**——没有内置的空实现，必须自己实现 `DiomanCachePersist`（`read`/`write`/`remove`/`erase`，接口形状参照 `get_storage` 包的容器 API——`read` 可以同步也可以异步（`FutureOr`），`write`/`remove`/`erase` 永远异步），接入文件、sqlite、Hive、`get_storage` 或其他任意存储，哪怕你只打算用 `DiomanCachePolicy.memo`。

`cachePolicy`（也可通过 `DiomanCacheOptions.cachePolicy` 按请求覆盖）决定缓存条目存在**哪**，跟是否缓存（仍由 `enabled`/`shouldCache` 决定）是两回事：
- `none`（默认）——完全不缓存该请求，总是直接透传。缓存要显式开启，不会默默生效。
- `memo`——只用内存层 `_store`，和以前行为一样。不持久——重启或 `dispose()` 后丢失，永不读写 `persist`。
- `persist`——只用 `persist`；该请求永不读写内存层。
- `both`——两者同步：写入时 `_store` 和 `persist` 都写；内存未命中时回退读 `persist` 并回填 `_store`，下次同一个 key 就能重新从内存命中。

持久化变更按调用顺序执行并等待完成；读写失败通过 `DioException` 返回请求，管理 Future 返回删除和清空错误。清空会使旧读取和旧响应失效。deep 策略在入库和命中时均复制数据。`DiomanCacheOptions.maxEntries` 已弃用，请在 `DiomanCache` 上配置容量。

### DiomanOffline

`DiomanOffline({required bool Function() isOnline, required Stream<bool> onConnectivityChanged, bool Function(RequestOptions)? shouldQueue, int maxQueueSize = 50, Duration? maxWait, bool enabled = true})`——断网时挂起请求入队，联网恢复后重放。纯 Dart：它自己从不检测连通性——由宿主通过 `isOnline`（每请求查一次，决定是否入队）和 `onConnectivityChanged`（`true` 事件自动 flush；也可手动调 `flush()`）上报。挂起请求会捕获它的 handler、单纯不推进；flush 时用 `handler.next(options)` 恢复到剩下的链上（不用 throwaway `Dio`）。`shouldQueue` 决定谁入队（`null`=全部）；读请求通常不该入队——让它失败、改由 `DiomanCache` 兜。`maxQueueSize`（默认 50，`0`=不封顶）满了挤出**最早**的。`maxWait`（默认 `null`=不限）限制单个请求最长等待，到时拒绝。

被拒的入队请求抛出的 `DioException`，其 `.error` 是 **`DiomanOfflineException`**（`reason`：`queueFull` / `timeout` / `disposed`）——不带 `response` 且类型 `DioExceptionType.unknown`，因此配套的 `DiomanRetry` 不会重试它。装在 **`DiomanCache` 之后、`DiomanShare` 之前**（见[推荐顺序](#推荐顺序)）：缓存命中会在入队前短路，且挂起请求绝不会开 share/cancel/loading 括号。`dispose()` 会拒绝所有挂起请求（`disposed`）并取消 stream 订阅——不留任何悬挂。

> `maxWait` 默认关，所以入队请求可能无限等（直到恢复、被挤出或 dispose）。需要对 spinner 设硬上限就开它。

```dart
final offline = DiomanOffline(
  isOnline: () => connectivity.isOnline,
  onConnectivityChanged: connectivity.onlineStream, // Stream<bool>
  shouldQueue: (o) => o.method != 'GET',            // 例：只队写请求
);
dio.interceptors.add(offline); // 在 DiomanCache 之后、DiomanShare 之前
```

排队请求取消时立即出队并取消定时器；flush 在恢复请求前再次检查取消状态。

### DiomanShare

`DiomanShare({SharePolicy policy = SharePolicy.start, int retries = 3, Duration interval = Duration.zero, bool enabled = true})`——合并同 key 的并发请求。

| 策略 | 行为 |
|---|---|
| `start` | 第一个跑，其余等它的结果（只发一次 HTTP）。 |
| `end` | 后来的取代先前的，所有调用方拿**最后一个**结果。 |
| `race` | 都发，**第一个成功**的胜出并分发给所有人。 |
| `retry` | 共享 promise 且内部重试，调用方看不到重试过程。 |
| `none` | 关闭。 |

### DiomanMockAdapter

mock 在传输层：`DiomanMockAdapter` 直接包装 `dio.httpClientAdapter`，不经过 `Dioman.install`。它不是插件，没有安装顺序可排错。**只在开发/测试 flavor 中安装**；纯 Dart 库无法替应用判断 release。

```dart
// Development/test flavor bootstrap only:
dio.httpClientAdapter = DiomanMockAdapter(
  inner: dio.httpClientAdapter,
  routes: {
    'GET:/pets': (_) async => ResponseBody.fromString('[]', 200,
      headers: {Headers.contentTypeHeader: ['application/json']}),
  },
  // mockUrl: 'http://localhost:4523', // optional fallback mock server
);
```

构造参数：必传 `inner`；`routes = const {}`、`mockUrl`、`fallbackWhen = defaultFallback`、`enabled = true`。按 `METHOD:uri.path` 匹配内联路由，未命中时转发至 `mockUrl`（保留路径和查询串），否则透传真实接口。内联结果不回落；转发的 404 响应或非取消传输异常默认回落。adapter 返回原始响应，由 Dio 统一解码与校验状态：`fallbackWhen(response:)` 的 `data` 为 `ResponseBody`，HTTP 500 默认交给 Dio，可自定义回落条件。转发需要回落时，请求体在内存缓冲后分别重放。

按请求覆盖用 `extra[DiomanMockAdapter.extraKey]`（即 `'dioman:mock'`）：传 `DiomanMockOptions` 可覆盖 enabled/routes/mockUrl/fallbackWhen（routes 合并、同键以请求级为准）；传 `false` 或 `DiomanMockOptions(enabled: false)` 则本次关闭 mock。

与插件链的关系：adapter 在所有插件**之下**，贴着传输层。所以 `share` 会在请求到达它之前就把相同的并发请求合并（只发一次 mock 探测，而不是 N 次）；`auth`/`retry` 重放会再次经过它（mock 的 500 也按 retry 配置重试，每次重放都重新探测 mock）；`cache` 命中或 `offline` 排队时请求根本到不了 adapter，真实回落的响应则像普通真实响应一样被缓存。

内联与不回落的转发响应带 `DiomanMockAdapter.markerHeader`（`x-dioman-mock: 1`）。`DiomanCache` 发现该头即禁止写入，先于 `shouldStore` 且不能放开；真实回落响应不添加标记，照常缓存。同 key 先 mock 再关闭 mock 不会读到被 mock 污染的缓存；已有真实缓存仍可命中。

### DiomanCancel

`DiomanCancel({bool enabled = true})`——为没有 `CancelToken` 的请求注入一个并登记。`cancelAll([reason])` 中断全部在途；顶层 `cancelAll(dio, [reason])` 会在某个 `Dio` 上找到该插件并调用。`enabled: false` 彻底关闭注入/追踪。

### DiomanLoading

`DiomanLoading({required void Function(bool) onChanged, bool enabled = true})`——第一个请求开始时 `onChanged(true)`，最后一个结束时 `onChanged(false)`。`activeCount` 暴露当前在途数。同一显示周期由开启时选择的回调关闭，包括延迟隐藏和释放插件。

### DiomanAuth

`DiomanAuth({required tokenManager, required onRefresh, required onAccessExpired, onAccessDenied, onFailure, ready, isProtected, expiresAt, Duration refreshLeeway = Duration.zero, DateTime Function() now = DateTime.now, String headerKey = 'Authorization', String Function(String)? buildHeader, bool enabled = true})`——`buildHeader` 默认生成 `'Bearer $token'`。注入 token，并在 401/403 时路由到五种 `AuthFailureAction`（`refresh` / `replay` / `deny` / `expired` / `others`），且**共享单个刷新窗口**（并发请求只触发一次刷新，其余等待）。实现 `ITokenManager`（`accessToken`、`refreshToken`、`canRefresh`、`clear()`）来对接。默认保护所有请求；用 `isProtected` 或 `extra['dioman:auth'] = const DiomanAuthOptions(enabled: false)` 排除公开接口。

**主动刷新（可选开启）。** 传入 `expiresAt: (token) => DateTime?`（例如解 JWT 的 `exp`），插件会在发送前刷新已过期的 token（含 `refreshLeeway` 提前量），避免一轮注定失败的 401 往返。并发的过期请求会共享同一个刷新窗口。不传 `expiresAt` 时行为纯被动（只走 401 路径）。适合在 token 带可信过期时间、且遇到 token 边界突发并发、延迟敏感的首个请求、或对 401 噪音敏感的基建时开启；否则被动路径更简单也够用。

### DiomanRetry

`DiomanRetry({int max = 0, List<String>? methods, DiomanShouldRetry? shouldRetry, List<int>? statusCodes, DiomanRetryDelay? delay, Object? jitter, Duration? delayMax, bool enabled = true, bool respectRetryAfter = true, List<int>? afterStatusCodes, Duration? retryAfterMax, void Function(int attempt)? onRetry})`——`methods`（默认`[GET,PUT,HEAD,DELETE,OPTIONS,TRACE]`）最先检查，是`shouldRetry`说了也不算的硬性否决。`delay`默认固定`3000ms`；`jitter`（`true`或`Duration Function(Duration)`）和`delayMax`叠加在其上。`shouldRetry`不设默认值——返回明确的`true`/`false`直接采用，返回`null`退回`statusCodes`（默认`[408,429,500,502,503,504]`），只有完全没有HTTP状态码时（纯网络失败）才进一步退回超时/连接错误判定。`onError`路径以`shouldRetry(err, err.response)`调用（网络级重试），`onResponse`路径以`shouldRetry(null, response)`调用（业务级重试——把body判定为失败的2xx也视为失败，判断的是原始响应体）。响应带`Retry-After`头（数字秒或RFC 1123格式HTTP-date）且状态码在`afterStatusCodes`内（默认`[413,429,503]`）、`respectRetryAfter`为true（默认）时，优先听它而不算`delay`，由`retryAfterMax`封顶。

`breaker` 是可设置的属性（不是构造参数）——设成同一条链上的 `DiomanBreaker`，它触发的那一刻就停止重试；`Dioman.install` 会自动设好。`DiomanShare` 去重和 `cancelAll()` 都不需要接线：插件在每个请求上自己登记，退避等待期间也持续被追踪。重试走一个复用宿主 `Dio` 的 `httpClientAdapter`/`transformer` 的客户端；恢复成功的结果会流过装在它之后的拦截器（normalize、breaker、log），语义与首次成功一致。`FormData` 请求体每次尝试前克隆；`Stream` 请求体无法重发，永不重试。回调（`shouldRetry`/`delay`/`onRetry`）抛异常会转成 `DioException`。`onRetry` 是个轻量的 `(attempt) {}` 钩子，给你自己接日志用。

### DiomanBreaker

`DiomanBreaker({int failureThreshold = 10, Duration resetDuration = const Duration(seconds: 30), int halfOpenMaxCalls = 3, DiomanShouldTrip? shouldTrip, String Function(RequestOptions)? keyBuilder, void Function(String key, DiomanBreakerState from, DiomanBreakerState to)? onStateChange, bool enabled = true})`——按 `METHOD:path` 分桶的熔断器（可用 `keyBuilder` 覆盖）。每个桶：`closed` 连续失败达 `failureThreshold` 次后 → `open`（任一成功清零计数）；`open` 期间**不打网络**直接拒绝所有请求（fail-fast），直到 `resetDuration` 走完，才放行至多 `halfOpenMaxCalls` 个探测请求——一个探测成功即关闭，一个探测失败即重新熔断。`shouldTrip(response?, err?) → bool?` 判定什么算失败（明确的 `true`/`false` 直接采用，`null` 退回默认：网络/超时错误和 HTTP 5xx / 429）。`onStateChange` 是观察性的 `(key, from, to)` 钩子，可接监控。

`open` 桶抛出的 `DioException`，其 `.error` 是 **`DiomanBreakerOpenException`**（含 `bucketKey`、`retryableAt`）——不带 `response` 且类型为 `DioExceptionType.unknown`，因此配套的 `DiomanRetry` 永不重试这个 fail-fast 拒绝。装在 `DiomanRetry` **之后**（见[推荐顺序](#推荐顺序)）；用 `Dioman.install(dio, retry: ..., breaker: ...)` 把两者配套，`DiomanRetry` 在每次重发前也会查询熔断器，于是正在进行的重试循环会在熔断触发的那一刻停止。

**为何要和 `DiomanRetry` 并存？** 重试拉开的是*单个*请求自己的多次尝试，对独立请求之间毫无协调——20 个请求各重试 3 次，照样有 60 次打到已挂的服务器。熔断器补上重试缺的跨请求状态：依赖一旦真挂了，新请求微秒级拒绝（不空等弱网超时），并给服务器一个冷却窗口而不是被持续锤击。

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
| `dioman:offline` | offline | `DiomanOfflineOptions` | `enabled: false` 跳过（断网也直接放行）；`shouldQueue`/`maxQueueSize`/`maxWait` 单次配置。 |
| `dioman:share` | share | `DiomanShareOptions` | `enabled: false` 关闭；`policy` 覆盖。 |
| `dioman:mock` | `DiomanMockAdapter`（非插件） | `DiomanMockOptions` \| `false` | `false` / `enabled: false` 跳过；`mockUrl` 覆盖目标。键常量：`DiomanMockAdapter.extraKey`。 |
| `dioman:loading` | loading | `DiomanLoadingOptions` | `enabled: false` → 不计入指示器。 |
| `dioman:log` | log | `DiomanLogOptions` | `enabled: false` → 本次不记日志。 |
| `dioman:retry` | retry | `int` \| `false` \| `DiomanRetryOptions` | `int`只覆盖`max`；`false`禁用（最高优先级否决）；对象形式覆盖任意字段（`max`/`methods`/`shouldRetry`/`statusCodes`/`delay`/`jitter`/`delayMax`/`respectRetryAfter`/`afterStatusCodes`/`retryAfterMax`/`enabled`）。 |
| `dioman:breaker` | breaker | `DiomanBreakerOptions` | `enabled: false` 跳过（open 时不拒绝、也不计数）；`failureThreshold`/`resetDuration`/`halfOpenMaxCalls`/`shouldTrip`/`keyBuilder` 按次覆盖。 |
| `dioman:filter` | filter | `DiomanFilterOptions` | `enabled: false` 跳过；`ignoreKeys`/`ignoreValues` 单次配置。 |
| `dioman:repath` | repath | `DiomanRepathOptions` | `enabled: false` 跳过替换。 |
| `dioman:timeout` | timeout | `DiomanTimeoutOptions` | `enabled: false` 跳过（保留本来的超时）；`timeouts` 按档合并/覆盖。 |
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
