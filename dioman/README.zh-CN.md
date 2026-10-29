# dioman

Dioman 把认证、重试、缓存等请求策略放到 Dio 周围统一处理，适用于 Dart 和 Flutter。

## 定位

当每个拦截器都要理解后端信封、还要与其他拦截器协调时，请求逻辑就越来越难维护。Dioman 为应用提供统一的请求入口，在结果交给插件之前完成归一化。认证、重试和缓存因此能使用同一个业务状态，不必各自再拆一次业务码。

管线按固定顺序包住每次尝试。认证刷新 token 或 retry 再次发送时，请求会自然穿过内层的 cache、share、mock，这些策略在每次尝试中都能参与。内核让取消始终跟随整个调用，也保证 loading 回调在等待期间成对结束。你可以专注于配置需要的策略，不必再手工连接它们的清理和重放逻辑。

这些行为从 Dioman 客户端入口生效。底层 Dio 继续负责传输和 Dio 拦截器；直接调用 Dio 时，执行的就是它自己的拦截器。

## 安装

```sh
dart pub add dioman
```

需要 Dart ^3.5.0，运行时只依赖 Dio。

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
    print('${result.kind.name}: ${result.status} / ${result.httpStatus}');
  } on DiomanResponse catch (failure) {
    print('${failure.kind.name}: ${failure.message}');
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

## 结果模型

只需要数据时，用 get/post/put/patch/delete/head；还需要状态等 DiomanResponse 信息时，用 send。动词方法会抛出失败结果，供调用方捕获；send 则把同一失败作为返回值，方便你直接判断。程序错误保留原异常和调用栈。如果应用已有自己的失败类型，可以通过 reject 转换动词方法的可预期失败。

结果字段：`ok`, `kind`, `status` （逻辑状态）, `httpStatus`, `code`, `message`, `data`, `reason`, `request`, `raw`, `error`, `errorStack`, `callSite`.

kind：`ok`, `http`, `biz`, `network`, `timeout`, `cancel`, `parse`, `auth`, `breaker`, `offline`, `internal`.

默认情况下，响应包含 code 且带有 data 或 message 时，会被视为信封，并且只拆一层。后端格式不同时，可以用 Envelope 和 DiomanResponseFactory 调整识别规则、成功码和逻辑状态；单次请求设置 call.envelope=false 就能保留原始数据。

## 插件

阶段固定：outer → prepare → attempt → credential → source → Dio.

先安装应用需要的插件，再通过 DiomanCall(options: {插件.option: 值}) 调整单次请求。值为 false 时跳过该策略，true 时沿用配置，选项对象则只覆盖其中非 null 的字段。每个插件也有安装级 enabled 开关。cache 和 share 需要逐请求明确开启；其他已安装插件默认参与。

### Loading

Loading 为整个逻辑调用维持一个显示周期，包含 token 刷新、缓存命中、共享请求和离线等待。即使调用被取消，界面也会收到成对的开启与关闭回调。

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Notify

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
    print(result.kind);
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
    print(result.kind);
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
    print(result.kind);
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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Retry

需要重试时，请显式设置 max，它的默认值是零。Retry 先检查方法白名单，再根据逻辑状态决定是否让下一次尝试重新经过内层。

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
    print(result.kind);
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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Auth

Auth 默认保护所有请求，同一客户端的并发请求会共享一次刷新。请在 onRefresh 中通过独立客户端获取并保存新 token；下面的 renewed 只演示如何更新存储。

选项：`tokenManager, onRefresh, onAccessExpired, onAccessDenied, onFailure, isProtected, ready, expiresAt, refreshLeeway, headerKey, buildHeader`。完整参数与默认值见[插件规格](docs/design/pipeline-plugin-spec.md)。

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Mock

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Share

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Cache

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
    print(result.kind);
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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

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

[0.7.2 → pipeline](docs/guides/migrating-to-pipeline.md) · [Architecture](docs/design/architecture.md) · [CHANGELOG](CHANGELOG.md)

可运行版本：`dart run example/dioman_example.dart`（离线）；`dart run example/real_run.dart` 使用公共服务，需要网络。
