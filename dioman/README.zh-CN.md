# dioman

Dioman 在 Dio 外面统一处理认证、重试、缓存这些请求策略，适用于 Dart 和 Flutter。

web 和 Wasm 仍然支持：原生网络分类器通过条件导入选择。cache/share 的自动 key 现在会带上 `responseType` 和带类型标记的 Map 键（细节见 [Cache](#cache)）；显式 key 和自定义 builder 的输出不变。

请求被取消后，在 `next()` 处直接结束，不会再进入内层插件。`cancelAll(reason)` 和调用方传入的 `CancelToken` 都会把第一次取消的原因放进 `failureOf(result)?.reason`：原因不为空就用 `toString()` 转成字符串，没传原因则仍是 null。打开 debug 后，如果某个选项对应的插件没装，每个客户端只警告一次，值是 false 或 null 也算传入；插件装了但被禁用，不算没装，不会警告。

`Dioman<R>` 里的 `R` 不是 `DiomanResponse<dynamic>` 时，必须传 `response: DiomanResponseFactory<R>(create: ...)`；不传 `create`，构造时会在插件 `setup` 之前抛 `ArgumentError`。

## 定位

如果每个拦截器都要看懂后端的响应外层结构，还要和其他拦截器配合，请求逻辑会越来越难维护。Dioman 给应用一个统一的请求入口，在结果交给插件之前先整理成统一的格式，所有插件看到的结果都一样。认证、重试和熔断按客户端配置（`statusOf`）算出的状态来判断。

管线按固定顺序包住每次尝试。认证刷新 token 或 retry 再次发送时，新的一次尝试和其他尝试一样，会穿过内层的 cache、share、mock。取消始终作用于整个调用，loading 回调在等待期间也始终成对出现。你只需要配置要用的策略，不用自己去接它们的清理和重放逻辑。

要有这些行为，请求必须从 Dioman 客户端发出。底层的 Dio 仍然负责传输，也仍然运行 Dio 拦截器；直接调用 Dio 的话，只会运行它自己的拦截器。

## 安装

```sh
dart pub add dioman
```

需要 Dart ^3.5.0 与 Dio ^5.4.0（唯一的运行时依赖）。

> **0.8.0 有不兼容改动**（管线重写）。从 0.7.x 升级请先读[迁移指南](docs/guides/migrating-to-pipeline.md)和 [CHANGELOG](CHANGELOG.md)。

## 快速开始

这个例子用内联路由，不需要网络；换成真实接口时，去掉 `DiomanMock`。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [
        const DiomanRepath(),
        const DiomanFilter(),
        DiomanMock(routes: {
          'GET:/users/42': (_) => {'code': 0, 'data': {'id': 42}},
          'GET:/health': (_) => {'code': 0, 'data': 'ready'},
        }),
      ]);
  try {
    final data = await api.get<Map<String, dynamic>>('/users/{id}',
        query: {'id': 42});
    print(data);
    final result = await api.send<dynamic>('GET', '/health');
    print('${failureOf(result)?.kind.name}: ${result.status}, code ${result.code}');
  } on DiomanResponse catch (failure) {
    print('${failureOf(failure)?.kind.name}: ${failure.message}');
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

## 结果模型

只要数据，就用 `get`/`post`/`put`/`patch`/`delete`/`head`；还要状态等 `DiomanResponse` 里的信息，就用 `send`。动词方法遇到失败会把失败结果抛出来，由调用方捕获；`send` 则把同一个失败当返回值交给你。程序错误会保留原来的异常和调用栈。如果应用有自己的失败类型，可以用 `reject` 转换动词方法里预期内的失败。

结果字段：`ok`、`status`（只表示 HTTP 状态，没有响应时为 0）、`code`、`message`、`data`、`request`、`raw`、`error`、`callSite`。用 `failureOf(r)` 读取失败的只读 `kind` 和 `reason`；带失败标记的结果，`ok` 一定是 false。判断是否取消，用 `isDiomanCancel(e)` 或 `api.isCancel(e)`。

结果默认不带原生对象，`raw` 和 `error` 都是 null。要读原生数据（包括成功时的响应头），必须显式传 `DiomanCall(raw: true)`。`send` 返回的或预期失败时抛出的那份结果，只带自己这次的传输数据；缓存命中和 share 的跟随者没有。插件可以在结果确定之前读 `ctx.native`。internal 失败的异常和调用栈在 `failureOf(r)?.error` / `failureOf(r)?.errorStack` 里，重抛时始终保留原来的调用栈。

```dart
import 'package:dioman/dioman.dart';
Future<String?> readEtag(Dioman api) async {
  final result = await api.send<Object?>('GET', '/pets',
      call: const DiomanCall(raw: true));
  return result.raw?.headers.value('etag');
}
```

### 业务风格

默认的 `parse` 只在响应体是 Map、含 `code`、并且含 `data` 或 `message` 之一时，才拆掉外面这一层；其他响应体原样放进 `data`。缺 `code` 按 0，缺 `message` 按空字符串，缺 `data` 按 null。默认的成功条件是 HTTP 2xx 且 `code` 为 0 或字符串 `'0'`。协议不同的话，在工厂里配置 `parse`；业务码不会改动 HTTP `status`。要让 retry/auth/breaker 按业务码判断，需要自己给客户端配置 `statusOf`，它们读的是 `ctx.statusOf`。对失败类型做 switch 时，要保留 `null` 分支，它对应没有失败标记的成功、HTTP 失败和业务失败。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(),
      statusOf: (r) => r.status >= 200 && r.status < 300 &&
          r.code is int && r.code != 0 ? r.code as int : r.status);
  try {
    final r = await api.send<Object?>('GET', 'https://api.example.com/items');
    final label = switch (failureOf(r)?.kind) {
      DiomanFailureKind.cancel => 'cancel',
      DiomanFailureKind.timeout => 'timeout',
      DiomanFailureKind.network => 'network',
      DiomanFailureKind.parse => 'parse',
      DiomanFailureKind.auth => 'auth',
      DiomanFailureKind.breaker => 'breaker',
      DiomanFailureKind.offline => 'offline',
      DiomanFailureKind.internal => 'internal',
      null => r.ok ? 'ok' : 'HTTP ${r.status}, code ${r.code}',
    };
    print(label);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### 解码与异步销毁

所有数据方法和 `send` 都可以传一个可选的 `decode`，类型是 `T Function(Object? data)`。它只在成功的结果确定之后执行：数据方法返回 `T`，`send` 返回的结果里 `data` 已解码，其他字段不变。预期内的失败不解码。`decode` 抛出的异常和调用栈原样交给调用方，不经过插件，也不会被改成 parse 失败。share 的每个跟随者各自解码，所以解码器不要修改传入的数据。不传 `decode` 时行为不变。

`DiomanPluginInstance.dispose` 现在返回 `FutureOr<void>`；`Dioman.dispose` 返回 `Future<void>`，按注册的相反顺序等每个实例清理完，每个都会执行，最后带着原来的调用栈抛出第一个异常。重复调用返回同一个 Future。就算不 `await`，在途请求也会立刻取消，新请求也会立刻被拒绝；异步插件用到的资源，要等 `await dispose` 完成后再释放。

`eject(name)` 仍然返回 bool，并立刻开始清理；异步清理由客户端负责跟踪，`await api.dispose()` 也会等已移除的实例清理完，并带着原来的调用栈报告第一个清理错误。销毁开始之后不能再 `eject`，避免重复清理。

打开 debug 时，`retry.jitter` 和 `cache.clone` 的字段类型不对，会在发送前报错，缓存没命中时也会检查。其他不认识的选项值类型，仍然由 `resolveOption` 抛 `ArgumentError`；未安装插件的警告规则不变。

```dart
import 'package:dioman/dioman.dart';

/// 用户请求路径。
const _userPath = '/user';

/// 调用方的数据模型。
class User {
  /// 保存用户编号。
  User(this.id);

  /// 从成功响应的数据构造用户。
  factory User.fromJson(Object? data) => User((data as Map)['id'] as int);

  /// 用户编号。
  final int id;
}

/// 解码仅在成功落定后执行。
Future<User> loadUser(Dioman api) =>
    api.get<User>(_userPath, decode: User.fromJson);

/// send 保留结果字段并转换 data。
Future<DiomanResponse<User>> sendUser(Dioman api) =>
    api.send<User>('GET', _userPath, decode: User.fromJson);

/// 等待插件完成清理。
Future<void> closeClient(Dioman api) async {
  await api.dispose();
}
```

## 插件

阶段固定：outer → prepare → attempt → credential → source → Dio.

先装上应用需要的插件，再用 `DiomanCall(options: {插件.option: 值})` 调整单次请求。值为 `false` 就跳过这个策略，`true` 就照插件的配置来，传选项对象则只覆盖其中不为 null 的字段。每个插件在安装时也有 `enabled` 开关。cache 和 share 要在每次请求里明确开启；其他装了的插件默认都生效。

### Loading

Loading 让整个逻辑调用只显示一次加载状态，期间的 token 刷新、缓存命中、共享请求和离线等待都算在内。即使调用被取消，界面也一定会收到一次显示和一次隐藏。

相等（`==`）的回调跨客户端共用一组 true/false，实例方法的 tear-off 也会合并；`activeCount` 只统计当前客户端。销毁客户端只释放它自己占的那一份，延迟隐藏期间新建的客户端会接手；回调的所属客户端销毁时，会补发最后一个 `false`。

选项：`delay, delayClose`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanLoading(onChanged: (visible) => print(visible))]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanLoading.option: false}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Notify

默认的 `stringify` 对 `failureOf(r)?.kind == DiomanFailureKind.internal` 返回空字符串；想在这种情况下提示，请自己提供 `stringify`。

Notify 等到最终结果出来才决定要不要提示。默认只提示失败，成功、silent 和被取消的调用都不提示。

选项：`notify, stringify`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanNotify(notify: (message, result) => print(message))]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanNotify.option: false}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Repath

路由里有 {id}、:id 或 [id] 时，可以交给 Repath 替换。它先在 query 里找，再在 Map 形式的 data 里找，找到的值会按路径段编码。

选项：`pattern, removeKey`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanRepath()]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanRepath.option: const DiomanRepathOptions(removeKey: false)}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Filter

Filter 在发送前删掉顶层的 null、NaN 和空白字符串。0 和 false 会保留，因为它们是有意义的值。

选项：`predicate, ignoreKeys, ignoreValues`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanFilter()]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanFilter.option: false}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Timeout

Timeout 按你的 `probe` 返回的网络档位设置 Dio 超时。它自己不检测网络，默认配置下也只改连接超时。

选项：`probe, timeouts`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanTimeout(probe: () => NetworkQuality.good)]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanTimeout.option: const DiomanTimeoutOptions(timeouts: {NetworkQuality.good: DiomanTimeouts(receive: Duration(seconds: 5))})}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Retry

行为变化：`retryAfterMax` 现在默认 60 秒。`Retry-After`（秒数或 HTTP 日期）要求等得比这更久时，Retry 不再重试，直接返回本次结果。想完全照服务端说的等，就显式传一个很大的 `Duration`，例如 `retryAfterMax: Duration(days: 36500)`。服务端要求的等待时间仍然不加 jitter，也不受 `delayMax` 限制。流和不透明的请求体最多只发送一次。

Retry 默认最多重试两次，等待时间从 300ms 起按指数增长，`delayMax` 默认 10 秒；设 `max: 0` 可以关掉重试。它先检查请求方法是否在白名单里，再根据 `ctx.statusOf` 算出的状态决定要不要再发一次，再发的请求会重新经过内层插件。

选项：`max, methods, statusCodes, shouldRetry, delay, jitter, delayMax, respectRetryAfter, afterStatusCodes, retryAfterMax, onRetry`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanRetry(max: 2)]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanRetry.option: 2}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Breaker

Breaker 位于 retry 内侧，每次尝试都会计数。熔断打开后，它返回 breaker 结果，retry 也会因此停止发送。

选项：`failureThreshold, resetDuration, halfOpenMaxCalls, shouldTrip, keyBuilder, onStateChange, idleTtl, maxBuckets, clock`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanBreaker()]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanBreaker.option: false}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Auth

插件和 `DiomanAuthOptions` 新增了 `refreshTimeout`，默认 30 秒，用 `DiomanClock` 计时；超时按刷新失败处理，同一个会话里只通知一次过期。刷新失败的同时，如果用户重新登录换了 token，正在等待的调用会用当前的 token 继续。如果 `onRefresh` 用同一个客户端发请求，这次请求必须关掉 auth：`call: DiomanCall(options: {DiomanAuth.option: false})`。已经发送过的流和不透明请求体没法重放，会直接返回本次结果。

Auth 默认保护所有请求，用同一个 `TokenManager` 的客户端共用一次刷新。请在 `onRefresh` 里用另一个独立的客户端获取并保存新 token；下面例子里的 `'renewed'` 只是演示怎么更新存储。

选项：`tokenManager, onRefresh, onAccessExpired, onAccessDenied, onFailure, isProtected, ready, expiresAt, refreshLeeway, refreshTimeout, headerKey, buildHeader`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

class Tokens implements DiomanTokenManager {
  @override
  String? accessToken = 'demo';
  @override
  String? refreshToken;
  @override
  void setTokens({required String accessToken, String? refreshToken}) {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
  @override
  void clear() { accessToken = null; refreshToken = null; }
}

Future<void> main() async {
  final tokens = Tokens();
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanAuth(tokenManager: tokens, onRefresh: (store, result) async { store.setTokens(accessToken: 'renewed'); }, onAccessExpired: (store, result) { store.clear(); })]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanAuth.option: false}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Mock

探测之后要回落到真实接口时，会先检查请求体能不能重放；流和不透明的请求体不会再发一次，直接返回探测的结果。

Mock 在 source 阶段最先执行。内联路由命中就直接返回，不再经过 share、cache 或 offline；探测 mock 服务时，默认只有 HTTP 404 或网络失败才回落到真实接口。

选项：`routes, mockUrl, fallbackWhen`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanMock(routes: {'GET:/items': (request) => {'code': 0, 'data': <String>[]}})]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanMock.option: true}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Share

调用方自己取消或订阅超时，就退出 `end`/`race` 的结果竞争，但它自己仍拿到取消或超时的结果；生成不了安全的自动 key 的请求体不参与共享，详见 Cache。

需要合并并发请求时，在这次调用里开启 Share，再选 `start`、`end`、`race` 或 `retry` 策略。不传就不参与；同一次尝试的订阅者共用一份只读结果。

选项：`policy, retries, interval, methods`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanShare()]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanShare.option: DiomanSharePolicy.start}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Cache

自动 key 在 deep 和 fast 两种模式下都包含 `responseType`；Map 的键带类型标记，所以数字 `1` 和字符串 `'1'` 是两个 key。JSON 数组按内容编码，普通的 `List<int>` 也一样（里面可以有负数和大于 255 的整数）。只有 `Uint8List` 当作原始字节：64 KiB 以内，key 里带内容哈希和完整的 base64。更大的字节体、`FormData`、流、其他对象，以及编码失败的情况，都生成不了 key，所以不走 cache 和 share。命中缓存、返回结果之前，会再检查一次调用方有没有取消。

internal 和 cancel 结果永不缓存，即使 shouldStore 返回 true。

在请求里传一个 `Duration` 作为 TTL，就开启了 Cache。它默认用 `memo`，保存成功的 GET/HEAD 结果。`clear` 还会让所有进行中的写入失效，`remove` 只作废指定的 key。

选项：`persist, cachePolicy, expires, clone, maxEntries, shouldCache, shouldStore, clock`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanCache()]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanCache.option: const Duration(minutes: 1)}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Offline

Offline 在 cache 内侧等待，所以断网时缓存命中的请求仍然能直接返回。队列默认最多放 50 个调用，满了就丢掉最早的那个；容量设成 0 或负数表示不设上限。`shouldQueue` 返回 false 时直接发送。

选项：`isOnline, onConnectivityChanged, shouldQueue, maxQueueSize, maxWait`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanOffline(isOnline: () => true, onConnectivityChanged: const Stream<bool>.empty())]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanOffline.option: const DiomanOfflineOptions(maxWait: Duration(seconds: 10))}));
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

## 扩展与资源生命周期

`api.extend(dio: engine, options: overrides, plugins: replacements)` 返回一个子客户端。不传 `plugins` 就继承父客户端的插件列表，并各自重新 `setup`；`dispose()` 不会关闭调用方传入的 `dio`。

| 资源 | 默认 extend | 显式 dio |
|---|---|---|
| BaseOptions | 克隆一份，里面的 Map 不和父客户端共用 | 使用传入的 dio 自己的配置 |
| options 覆盖 | 安装后合并不为 null、也不是默认值的字段，Map 按顶层键合并 | 同左，直接修改传入的 dio |
| 拦截器、adapter、transformer | 不复制，用新 Dio 的默认值 | 原样保留 |
| 插件实例、进行中的请求、管线 | 子客户端新建 | 同左 |
| auth 会话、loading 显示 | 同一 TokenManager / 相等的回调共用 | 同左 |
| 工厂、key、reject、debug、clock | 继承配置或回调的引用 | 同左 |

BaseOptions 分不出“没填”和“填了默认值”，所以没法用默认值把继承来的非默认值改回去。把父客户端的 `dio` 传进来，就是和父客户端共用同一个可修改的 Dio，options 覆盖也会影响父客户端。

Auth 的刷新、过期和缺 token 通知都跟着 `TokenManager` 走。缺 token 每个会话只通知一次，出现新 token 后重新计数。最后一个持有者销毁时，会话关联解除，之后才到的刷新失败不会清 token，也不会通知；还有其他持有者时，共享的失败只处理一次。

## 环境配置

用 `DiomanEnvs` 在 `setup` 时应用环境配置：它把第一个匹配的 `EnvRule` 合并进 `BaseOptions`。它没有请求级 option，也不在请求链里；移除这个插件后，已经应用的配置仍然保留。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(), plugins: [
    DiomanEnvs([EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://api.example.com'))]),
  ]);
  print(api.inspect());
  api.dispose();
  api.dio.close(force: true);
}
```

## 自定义插件

写插件时，配置放在 `DiomanPlugin` 里，每个客户端自己的状态放在 `setup` 返回的 `DiomanPluginInstance` 里。同一阶段内，`pre` 在内置插件之前执行，`post` 在之后执行，同一组内按注册顺序。

`next(patch)` 会基于本层当前的请求另生成一个请求，不影响同层的其他尝试。`StateKey` 靠对象本身（identity）区分，所以要创建非 const 的实例；需要等待时用 `ctx.wait`，每次 `await` 之后检查 `ctx.cancelled()`。要发送多次的话，先调用 `markReplayable`。Map、List、FormData 会在需要时克隆，单订阅的 Stream 则不能保证能重放。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
class Trace extends DiomanPlugin<DiomanResponse<dynamic>> {
  const Trace();
  @override
  String get name => 'app:trace';
  @override
  DiomanStage get stage => DiomanStage.prepare;
  @override
  DiomanEnforce get enforce => DiomanEnforce.pre;
  @override
  DiomanPluginInstance<DiomanResponse<dynamic>> setup(
      Dioman<DiomanResponse<dynamic>> client) => _Trace();
}
class _Trace extends DiomanPluginInstance<DiomanResponse<dynamic>> {
  final visits = StateKey<int>('visits');
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<DiomanResponse<dynamic>> ctx,
      DiomanNext<DiomanResponse<dynamic>> next) async {
    ctx.set(visits, (ctx.get(visits) ?? 0) + 1);
    await ctx.wait(Future<bool>.value(true));
    final cancelled = ctx.cancelled();
    if (cancelled != null) return cancelled;
    return next(const RequestPatch(headers: {'X-Trace': 'demo'}));
  }
}

void main() {
  final api = Dioman(dio: Dio(), plugins: [const Trace()]);
  print(api.inspect());
  api.dispose();
  api.dio.close(force: true);
}
```

## 测试建议

业务逻辑的测试可以直接用 `DiomanMock` 的内联路由；涉及时间的测试，注入 `DiomanClock` 和一个按脚本返回结果的 Dio 传输层。真实的超时、`Transformer` 和重放行为，要用本地的 `HttpServer` 验证，因为替身的行为不能当成网络的真实表现。要清理缓存之类的管理操作，用 `api.plugin<DiomanCacheApi>()` 拿到对应的接口。销毁客户端之后，记得关掉你自己持有的 Dio。

```sh
dart analyze
dart test
dart run test/accept/bin/matrix.dart gates
```

## 迁移

Dio 的 `unknown` 错误如果是解码时的 `FormatException`，现在归为 `kind: parse`，HTTP 状态取 Dio 给的值。HTML 默认按文本处理；`expectJson: true` 且在 json 模式下，2xx 的非空文本会被判为 parse 失败，不看 MIME 类型；显式指定 `ResponseType.plain`、`bytes`、`stream` 时，不做这个严格的 JSON 检查。

[0.7.x → 0.8.0 pipeline](docs/guides/migrating-to-pipeline.md) · [Architecture](docs/design/architecture.md) · [CHANGELOG](CHANGELOG.md)

运行示例：`dart run example/dioman_example.dart`（离线）；`dart run example/real_run.dart` 会请求一个公共服务，需要网络。

## 逻辑请求截止时间

`Dioman(deadline: ...)` 设置整个请求的默认时间预算，单次请求的 `DiomanCall(deadline: ...)` 不为 null 时优先；两个都是 null 就不设截止时间，零或负数会立即到期。计时从逻辑请求进入客户端时开始，覆盖重试等待、token 刷新排队、离线队列、share 等待，以及完整的传输（包括响应体）。到期后会取消这次请求自己的取消令牌，结果是 `timeout`、`reason: 'deadline'`，判断是否取消时返回 false。计时用 `DiomanClock`，调用无论怎样结束都会清掉计时器。`extend` 继承默认预算。

这个功能和 timeout 插件、Dio 的 connect/send/receive 超时互不相干。share 的订阅者到期只退出它自己，最后一个订阅者离开时才中止共享的传输；`end`/`race` 里，到期的调用方的退出方式和被取消的调用方一样（见 Share），不影响其他调用方。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

/// 默认五秒，本次两秒，覆盖排队、重试和传输。
Future<void> deadlineExample() async {
  final api = Dioman(dio: Dio(), deadline: const Duration(seconds: 5));
  try {
    final result = await api.send<Object?>('GET', 'https://example.com/pets',
        call: const DiomanCall(deadline: Duration(seconds: 2)));
    if (failureOf(result)?.reason == 'deadline') {
      assert(failureOf(result)?.kind == DiomanFailureKind.timeout);
    }
  } finally {
    await api.dispose();
  }
}
```
