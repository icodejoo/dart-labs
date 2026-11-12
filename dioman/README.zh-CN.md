# dioman

Dioman 把认证、重试、缓存等请求策略放到 Dio 周围统一处理，适用于 Dart 和 Flutter。

R2b 通过条件导入原生网络分类器保留 web 和 Wasm 支持。自动 key 的变化同时作用于 cache/share，显式 key 与自定义 builder 输出保持不变。

next() 入口遇取消直接短路，不再进入内层插件。cancelAll(reason) 与调用方 CancelToken 都将首次取消原因写入 failureOf(result)?.reason；非空原因用 toString() 转换，省略原因仍为 null。debug 对每个未安装插件的选项键每客户端告警一次，false/null 也算传入；已安装但禁用的插件不误报。

Dioman<R> 的 R 不是 DiomanResponse<dynamic> 时，必须提供 response: DiomanResponseFactory<R>(create: ...)，否则构造期抛 ArgumentError，在插件 setup 前指出修法。

## 定位

当每个拦截器都要理解后端信封、还要与其他拦截器协调时，请求逻辑就越来越难维护。Dioman 为应用提供统一的请求入口，在结果交给插件之前完成归一化。插件因此能使用同一份结果契约；认证、重试和熔断通过客户端配置的有效状态判定。

管线按固定顺序包住每次尝试。认证刷新 token 或 retry 再次发送时，请求会自然穿过内层的 cache、share、mock，这些策略在每次尝试中都能参与。内核让取消始终跟随整个调用，也保证 loading 回调在等待期间成对结束。你可以专注于配置需要的策略，不必再手工连接它们的清理和重放逻辑。

这些行为从 Dioman 客户端入口生效。底层 Dio 继续负责传输和 Dio 拦截器；直接调用 Dio 时，执行的就是它自己的拦截器。

## 安装

```sh
dart pub add dioman
```

需要 Dart ^3.5.0，运行时只依赖 Dio。

> **0.8.0 为破坏性版本**（洋葱管线重写）。从 0.7.x 升级请先读[迁移指南](docs/guides/migrating-to-pipeline.md)与 [CHANGELOG](CHANGELOG.md)。

## 快速开始

快速开始使用内联路由，无需网络；替换为真实接口时移除 DiomanMock。

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

只需要数据时，用 get/post/put/patch/delete/head；还需要状态等 DiomanResponse 信息时，用 send。动词方法会抛出失败结果，供调用方捕获；send 则把同一失败作为返回值，方便你直接判断。程序错误保留原异常和调用栈。如果应用已有自己的失败类型，可以通过 reject 转换动词方法的可预期失败。

结果字段：`ok`、`status`（仅 HTTP，无响应为 0）、`code`、`message`、`data`、`request`、`raw`、`error`、`callSite`。内核失败用 `failureOf(r)` 读取只读 kind/reason；有标记时 ok 必为 false。取消可用 `isDiomanCancel(e)` 或 `api.isCancel(e)`。

R3：结果默认不带原生对象（raw/error 为 null）。成功时读取响应头等原生数据，也必须显式传入 `DiomanCall(raw: true)`；send 返回或可预期失败抛出的副本只带自身数据。缓存命中、share 跟随者没有自身原生数据。插件可在落定前读 `ctx.native`；internal 的异常与栈位于 `failureOf(r)?.error` / `failureOf(r)?.errorStack`，始终原栈重抛。

```dart
import 'package:dioman/dioman.dart';
Future<String?> readEtag(Dioman api) async {
  final result = await api.send<Object?>('GET', '/pets',
      call: const DiomanCall(raw: true));
  return result.raw?.headers.value('etag');
}
```

### 业务风格

默认 parse 仅在 Map 含 code 且含 data/message 之一时拆一层信封；其余整个作为 data。缺 code 为 0，缺 message 为空串，缺 data 为 null。默认成功为 HTTP 2xx 且 code 为 0 或字符串 '0'。协议不同可配置工厂 parse；业务码不会自动改写 HTTP status。业务风格需要显式配置客户端 statusOf，retry/auth/breaker 通过 ctx.statusOf 读取有效状态。穷举失败类别时保留 null 分支，处理没有标记的成功、HTTP 和业务失败。

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

所有数据方法和 send 均接受可选的 T Function(Object? data) decode。只在成功落定后执行：数据方法返回 T，send 返回 data 已解码的结果，其余字段保持。可预期失败不解码。decode 抛出的原异常和栈直接交给调用方，不经过插件，也不改写成 parse 失败。share 跟随者各自解码；解码器应只读输入数据。不传 decode 时行为不变。

DiomanPluginInstance.dispose 现在返回 FutureOr<void>；Dioman.dispose 返回 Future<void>，逆注册顺序等待每个实例清理，尽力全部执行，最后原栈抛出首个异常。重复调用返回同一完成信号。不 await 也会同步取消在途请求并拒绝新请求；异步插件使用的宿主资源应在 await dispose 后释放。

eject(name) 仍返回 bool 并立即启动清理；客户端继续拥有异步清理，await api.dispose() 也会等待已移除实例，并原栈报告首个观测到的清理错误。销毁开始后拒绝 eject，防止重复清理。

开启 debug 时，retry.jitter 与 cache.clone 的非法字段类型在发送前报错，缓存首次未命中也会检查。未知选项值类型仍由 resolveOption 抛 ArgumentError，未安装插件告警保持原规则。

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

先安装应用需要的插件，再通过 DiomanCall(options: {插件.option: 值}) 调整单次请求。值为 false 时跳过该策略，true 时沿用配置，选项对象则只覆盖其中非 null 的字段。每个插件也有安装级 enabled 开关。cache 和 share 需要逐请求明确开启；其他已安装插件默认参与。

### Loading

Loading 为整个逻辑调用维持一个显示周期，包含 token 刷新、缓存命中、共享请求和离线等待。即使调用被取消，界面也会收到成对的开启与关闭回调。

相等（`==`）的显示回调跨客户端共享一对 true/false，实例方法 tear-off 也会合并；`activeCount` 只统计本客户端占用。卸载只释放自身占用，延迟隐藏窗口由接入的新客户端接管；归属方卸载会补齐 false。

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

默认 `stringify` 对 `failureOf(r)?.kind == DiomanFailureKind.internal` 返回空串；需要通知时可自行提供 stringify。

Notify 等到最终结果才决定是否提示。默认只提示失败，成功、silent 或被取消的调用都不会打扰用户。

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

路由里有 {id}、:id 或 [id] 时，可以交给 Repath 替换。它先从 query 查找，再查 Map data，并把找到的值编码为路径段。

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

Filter 在发送前移除顶层的 null、NaN 和空白字符串，同时保留 0 和 false，避免把有意义的选择当成空值删掉。

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

Timeout 根据你提供的 probe 档位设置 Dio 超时。它不自行探测网络，默认配置也只调整连接超时。

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

行为变化：`retryAfterMax` 默认 60 秒。Retry-After 秒数或 HTTP 日期要求的等待超过上限时，不再重试，直接返回本次结果。需要近似无限遵守时显式传很大的 Duration，例如 `retryAfterMax: Duration(days: 36500)`。服务端等待仍不叠 jitter、不受 `delayMax` 限制。一次性流及不透明体最多发送一次。

Retry 默认最多重试两次，从 300ms 起指数退避，delayMax 默认 10 秒；设置 max: 0 可关闭重试。Retry 先检查方法白名单，再根据 ctx.statusOf 的有效状态决定是否让下一次尝试重新经过内层。

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

插件与 `DiomanAuthOptions` 新增 `refreshTimeout`，默认 30 秒，使用 `DiomanClock` 计时；超时走刷新失败路径，同一失败会话只通知一次。刷新期间重新登录替换了 token 时，失败等待者按当前 token 继续。`onRefresh` 经同一客户端请求时必须本次关闭 auth：`call: DiomanCall(options: {DiomanAuth.option: false})`。一次性流及不透明体不能重放，返回本次结果。

Auth 默认保护所有请求，使用同一 TokenManager 的客户端共享一次刷新。请在 onRefresh 中通过独立客户端获取并保存新 token；下面的 renewed 只演示如何更新存储。

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

探测后回落前检查请求体是否可重放；一次性流及不透明体返回探测结果，不再次发送。

Mock 在 source 阶段最先执行。内联命中会直接返回，不进入 share、cache 或 offline；探测 mock 服务时，默认只有 HTTP 404 或网络失败才回落到真实接口。

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

调用方自身取消或订阅超时撤回 end/race 的结果资格，调用方仍保留自己的取消或超时结果；无法安全构键的请求体不参与共享，详见 Cache。

需要协调并发请求时，在该次调用中开启 Share，再选择 start、end、race 或 retry 策略。省略时它不参与；同一次尝试的订阅者共享一份只读结果。

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

深模式和快速模式的自动 key 都包含 responseType，Map 键带类型标签以区分数字 1 与字符串 '1'；JSON 数组按内容编码，64 KiB 内字节列表保留内容哈希与完整 base64；超大字节体、FormData、Stream、其他对象或编码失败返回 null，不再参与 cache/share。命中返回前重查调用方取消。

internal 和 cancel 结果永不缓存，即使 shouldStore 返回 true。

按请求开启 Cache，并用 Duration 设置 TTL。它默认使用 memo，保存成功的 GET/HEAD 结果。clear 会作废所有在途旧写入，remove 则只影响指定 key。

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

Offline 在 cache 内侧等待，因此断网时缓存命中仍能直接回答。队列默认容纳 50 个调用，满时淘汰最早的一个；容量设为非正数则不设上限。shouldQueue 返回 false 时直接发送。

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

`api.extend(dio: engine, options: overrides, plugins: replacements)` 返回子客户端。省略 `plugins` 时继承配置列表，各自重新 setup；`dispose()` 不关闭调用方引擎。

| 资源 | 默认 extend | 显式 dio |
|---|---|---|
| BaseOptions | 克隆，Map 容器不共用 | 使用传入引擎的配置 |
| options 覆盖 | 安装后合并非空、非默认字段，Map 按顶层键合并 | 同左，直接修改传入引擎 |
| 拦截器、adapter、transformer | 不复制，使用新 Dio 默认值 | 原样保留 |
| 实例、在途请求、链 | 子客户端新建 | 同左 |
| auth 会话、loading 显示 | 同 TokenManager / 相等回调按资源共享 | 同左 |
| 工厂、key、reject、debug、clock | 继承配置或回调引用 | 同左 |

BaseOptions 无法区分省略和默认值，因此不能用默认值重置继承的非默认值。传入父客户端的 `dio` 会共享可变引擎，options 覆盖也影响父客户端。

Auth 的刷新、过期和无 token 通知状态跟随 TokenManager。无 token 每轮只通知一次，观察到新 token 后复位。最后一个持有者卸载时解除会话关联，迟到刷新失败不清 token、不通知；仍有持有者时按共享会话处理一次。

## 环境配置

用 DiomanEnvs 在 setup 时应用环境配置：它将首个匹配的 EnvRule 合并到 BaseOptions。它没有请求级 option，也不进入请求链；移除插件后，已经应用的配置会保留。

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

编写插件时，把配置放在 DiomanPlugin 中，让 setup 返回的 DiomanPluginInstance 保存每个客户端自己的状态。阶段内可以通过 pre 在内置插件前执行，或通过 post 在其后执行，同组仍保留注册顺序。

调用 next(patch) 会从本层基准派生请求，不会影响兄弟尝试。StateKey 按身份隔离，请创建非 const 实例；需要等待时使用 ctx.wait，并在 await 后检查 ctx.cancelled()。如果要多次发送，先调用 markReplayable。Map/List/FormData 会按需克隆，单订阅 Stream 则无法保证重放。

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

业务单测可以先用 DiomanMock 内联路由，时序测试则注入 DiomanClock 和脚本化 Dio 传输。涉及真实超时、Transformer 或重放时，再用本地 HttpServer 验证，避免把替身的行为当成网络保证。需要清理缓存等管理操作时，通过 api.plugin<DiomanCacheApi>() 获取对应能力。销毁客户端后，记得关闭自己持有的 Dio。

```sh
dart analyze
dart test
dart run test/accept/bin/matrix.dart gates
```

## 迁移

Dio unknown 的解码 `FormatException` 现归 `kind: parse`，保留 Dio 提供的 HTTP 状态。HTML 默认按文本；`expectJson: true` 在 json 模式下将 2xx 非空文本判为 parse，不依赖 MIME 声明；显式 ResponseType.plain、bytes、stream 不受严格 JSON 判定约束。

[0.7.x → 0.8.0 pipeline](docs/guides/migrating-to-pipeline.md) · [Architecture](docs/design/architecture.md) · [CHANGELOG](CHANGELOG.md)

可运行版本：`dart run example/dioman_example.dart`（离线）；`dart run example/real_run.dart` 使用公共服务，需要网络。

## 逻辑请求截止时间

`Dioman(deadline: ...)` 设置默认整体预算，请求级 `DiomanCall(deadline: ...)` 非空值优先；均为 null 时不设截止，零或负值立即到期。预算从逻辑请求入口开始，覆盖重试等待、token 刷新排队、离线队列、share 等待和完整传输（含响应体）。到期取消自身内核令牌，结果为 `timeout`、`reason: 'deadline'`，取消判别返回 false。计时使用 `DiomanClock`，所有落定出口均清理计时器。`extend` 继承默认预算。

该能力与 timeout 插件和 Dio connect/send/receive 阶段超时独立。share 订阅者到期只退出自身，最后一人离开才中止共享传输；end/race 按 B8 自身条件撤回，不污染其他调用方。

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
