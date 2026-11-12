# dioman

Dioman runs your request policies (auth, retry, cache and so on) around Dio, for Dart and Flutter.

Web and Wasm are still supported: the native network classifier is chosen with a conditional import. Automatic cache/share keys now include `responseType` and type-tagged Map keys (details in [Cache](#cache)). Explicit keys and custom builders keep their output.

A cancelled call stops at `next()` and never reaches the inner plugins. `cancelAll(reason)` and a caller's `CancelToken` both keep the first cancellation reason in `failureOf(result)?.reason`: a non-null reason is converted with `toString()`, and an omitted reason stays null. With debug on, an option for a plugin that is not installed is logged once per client, even when its value is false or null. A plugin that is installed but disabled counts as installed.

If `R` in `Dioman<R>` is not `DiomanResponse<dynamic>`, pass `response: DiomanResponseFactory<R>(create: ...)`. Without `create`, the constructor throws `ArgumentError` before any plugin is set up.

## Purpose

Request policies are hard to maintain when every interceptor has to understand the backend response envelope and coordinate with every other interceptor. Dioman gives your app one request entry point and normalizes each result before plugins see it, so all plugins work with the same result shape. Auth, retry and breaker read the status that your client configuration picks (`statusOf`).

The pipeline wraps each attempt in a fixed order. When auth refreshes a token or retry sends again, the new attempt passes through the inner cache, share and mock layers like any other. Cancellation stays attached to the whole call, and loading callbacks stay paired across the waits. You turn on the policies you need and don't have to wire up their cleanup and replay yourself.

Send requests through the Dioman client to get all this. The Dio underneath still does the transport and runs Dio interceptors; if you call Dio directly, only those interceptors run.

## Installation

```sh
dart pub add dioman
```

Requires Dart ^3.5.0 and Dio ^5.4.0 (the only runtime dependency).

> **0.8.0 is a breaking release** (pipeline rewrite). Upgrading from 0.7.x: see the [migration guide](docs/guides/migrating-to-pipeline.md) and the [CHANGELOG](CHANGELOG.md).

## Quick start

This example uses inline routes and runs offline. Remove `DiomanMock` when you connect to your real backend.

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

## Results

Use `get`/`post`/`put`/`patch`/`delete`/`head` when you only want the data, and `send` when you also need the `DiomanResponse` fields. The verb methods throw a failed result for you to catch; `send` returns the same failure as a value. Programming errors keep their original exception and stack. If your app has its own failure type, use `reject` to convert the expected failures of the verb methods.

Result fields: `ok`, `status` (HTTP only; 0 without a response), `code`, `message`, `data`, `request`, `raw`, `error`, `callSite`. Read a failure's read-only `kind` and `reason` with `failureOf(r)`; a result that carries a failure marker always has `ok == false`. To check for cancellation, use `isDiomanCancel(e)` or `api.isCancel(e)`.

By default `raw` and `error` are null. To read native data, including response headers on a successful call, pass `DiomanCall(raw: true)`. The result you get (returned or thrown) carries only its own transport data; cache hits and share followers have none. Plugins can read `ctx.native` before the result is settled. Internal errors and their stacks are in `failureOf(r)?.error` / `failureOf(r)?.errorStack`, and are always rethrown with the original stack.

```dart
import 'package:dioman/dioman.dart';
Future<String?> readEtag(Dioman api) async {
  final result = await api.send<Object?>('GET', '/pets',
      call: const DiomanCall(raw: true));
  return result.raw?.headers.value('etag');
}
```

### Business style

The default `parse` unwraps one level only when the body is a Map with `code` and at least one of `data`/`message`; any other body goes into `data` as is. Missing fields default to `code` = 0, `message` = `''` and `data` = null. A call succeeds when HTTP is 2xx and `code` is 0 or `'0'`. For other protocols, set the factory's `parse`. Business codes never change the HTTP `status`. To make retry, auth and breaker react to business codes, set the client's `statusOf` yourself; they read `ctx.statusOf`. When you switch over failure kinds, keep a `null` case: it covers success without a failure marker, HTTP failures and business failures.

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

### Decoding and disposal

Every data method and `send` takes an optional `decode`, a `T Function(Object? data)`. It runs only after a successful result is settled. Data methods return `T`; `send` returns a response whose `data` is decoded. Expected failures skip `decode`. If the decoder throws, the original exception and stack go straight to the caller: plugins never see it, and it is never turned into a parse failure. Each share follower decodes on its own, so the decoder should not modify its input. Without `decode`, nothing changes.

`DiomanPluginInstance.dispose` now returns `FutureOr<void>`. `Dioman.dispose` returns `Future<void>` and waits for each instance in reverse registration order. It runs every cleanup, then rethrows the first error with its original stack. Calling it again returns the same Future. In-flight requests are cancelled and new requests are refused right away, even if you don't `await`; `await` it before you release resources that async plugins use.

`eject(name)` still returns a bool and starts cleanup at once. The client keeps track of async cleanup: `await api.dispose()` also waits for ejected instances and reports the first cleanup error with its original stack. Once disposal has started, `eject` is refused.

With debug on, a wrongly typed `retry.jitter` or `cache.clone` is rejected before the request is sent, including on cache misses. Option values of unknown types still throw `ArgumentError`. The warning for options of missing plugins is unchanged.

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

## Plugins

Fixed stages: outer → prepare → attempt → credential → source → Dio.

Install the plugins your app needs, then adjust a single call with `DiomanCall(options: {Plugin.option: value})`. `false` skips that policy for the call, `true` uses the plugin's configuration as is, and an options object overrides only its non-null fields. Each plugin also has an `enabled` switch at install time. Cache and share must be switched on per call; the other installed plugins apply by default.

### Loading

Loading shows one loading state for the whole logical call, including token refresh, cache hits, shared requests and offline waits. Your UI always gets a matching show and hide, even if the call is cancelled.

Callbacks that are equal (`==`) share one true/false cycle across clients, including instance-method tear-offs. `activeCount` counts only the current client. Disposing a client releases only its own share; a new client takes over a pending hide delay, and disposing its owner sends the final `false`.

Options: `delay, delayClose`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

The default `stringify` returns an empty string for `failureOf(r)?.kind == DiomanFailureKind.internal`. Provide your own `stringify` if you want a message there.

Notify waits for the final result before it shows anything. By default it reports failures only; successful, silent and cancelled calls show nothing.

Options: `notify, stringify`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

Use Repath when your routes contain {id}, :id or [id]. It looks in query first, then Map data, and encodes the value as a path segment.

Options: `pattern, removeKey`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

Filter drops top-level null, NaN and blank strings before sending. `0` and `false` stay, because they are real values.

Options: `predicate, ignoreKeys, ignoreValues`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

Timeout sets the Dio timeouts for the network tier that your `probe` returns. It does not detect the network itself, and with the default configuration it only changes the connect timeout.

Options: `probe, timeouts`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

Behavior change: `retryAfterMax` now defaults to 60 seconds. If a `Retry-After` header (seconds or HTTP date) asks for a longer wait, Retry returns the current result and does not retry. To honor very long waits, pass a very large `Duration`, for example `retryAfterMax: Duration(days: 36500)`. Waits requested by the server still get no jitter and ignore `delayMax`. Streams and opaque bodies are sent at most once.

By default Retry retries twice, with exponential backoff starting at 300 ms and a `delayMax` of 10 s. Set `max: 0` to turn retries off. It checks the method allowlist first, then uses `ctx.statusOf` to decide whether to send another attempt through the inner layers.

Options: `max, methods, statusCodes, shouldRetry, delay, jitter, delayMax, respectRetryAfter, afterStatusCodes, retryAfterMax, onRetry`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

Breaker sits inside retry and counts each attempt. Once the circuit opens, it returns a breaker result that also stops retry from sending again.

Options: `failureThreshold, resetDuration, halfOpenMaxCalls, shouldTrip, keyBuilder, onStateChange, idleTtl, maxBuckets, clock`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

`refreshTimeout` is an option on the plugin and on `DiomanAuthOptions` (default 30 seconds, timed with `DiomanClock`). A timeout is handled like any refresh failure and reports expiry once per session. If the user logs in again and replaces the token while a refresh is failing, the waiting calls continue with the current token. If `onRefresh` sends its request through the same client, turn auth off for that request: `call: DiomanCall(options: {DiomanAuth.option: false})`. A stream or opaque body that has already been sent cannot be replayed, so the original result is returned.

By default Auth protects every request, and clients that use the same `TokenManager` share one refresh. In `onRefresh`, fetch and save the new token with a separate client. The `'renewed'` value in the example only shows how to update the store.

Options: `tokenManager, onRefresh, onAccessExpired, onAccessDenied, onFailure, isProtected, ready, expiresAt, refreshLeeway, refreshTimeout, headerKey, buildHeader`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

When falling back after a probe, a stream or opaque body is not sent again; the probe result is returned instead.

Mock runs first in the source stage. An inline route that matches returns before share, cache or offline run. When probing a mock server, the default is to fall back to the real API only on HTTP 404 or a network failure.

Options: `routes, mockUrl, fallbackWhen`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

If a caller cancels or its subscription times out, that caller drops out of the `end`/`race` choice and keeps its own cancel or timeout result. Requests whose automatic key cannot be built safely skip sharing (see Cache).

Turn Share on for calls that should coordinate concurrent requests, then pick `start`, `end`, `race` or `retry`. It is off unless you enable it, and subscribers of the same attempt share one read-only result.

Options: `policy, retries, interval, methods`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

Automatic keys include `responseType` (in both deep and fast modes) and type-tagged Map keys, so `1` and `'1'` differ. JSON arrays are encoded by content, including a plain `List<int>` that may hold negative numbers or values above 255. Only `Uint8List` counts as raw bytes: up to 64 KiB, keyed by a content hash plus the full base64. Bigger byte bodies, `FormData`, streams, other objects and encoding failures produce no key, so they skip cache and share. A cache hit checks again whether the caller has cancelled before it returns.

Internal and cancel results are never cached, even when shouldStore returns true.

Turn Cache on per call by passing a `Duration` as the TTL. It uses `memo` by default and stores successful GET/HEAD results. `clear` also invalidates every write still in flight; `remove` invalidates just one key.

Options: `persist, cachePolicy, expires, clone, maxEntries, shouldCache, shouldStore, clock`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

Offline waits inside cache, so a cache hit can still answer while the network is down. The queue holds 50 calls by default and drops the oldest call when it is full; a capacity of 0 or less means no limit. Return false from `shouldQueue` to send immediately.

Options: `isOnline, onConnectivityChanged, shouldQueue, maxQueueSize, maxWait`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

## Extension and resource lifetimes

`api.extend(dio: engine, options: overrides, plugins: replacements)` returns a child client. If you omit `plugins`, the child inherits the plugin list and runs `setup` again. `dispose()` leaves the caller's engine open.

| Resource | Default extend | Explicit dio |
|---|---|---|
| BaseOptions | Cloned with separate Map containers | Uses the supplied engine options |
| options override | Merges non-null, non-default fields after setup; Maps merge by top-level key | Same merge, mutating the supplied engine |
| Interceptors, adapter, transformer | Omitted; new Dio defaults apply | Preserved |
| Instances, pending requests, pipeline | Created for the child | Same |
| Auth session, loading display | Shared by TokenManager / equal callback | Same |
| Factory, key, reject, debug, clock | Configuration or callback references inherited | Same |

BaseOptions cannot distinguish omitted fields from defaults, so defaults cannot reset inherited non-default values. Passing the parent's `dio` shares a mutable engine; option overrides also affect the parent.

Auth's refresh, expiry and missing-token notices are tied to the `TokenManager`. A missing token is reported once per session, and this resets when a new token appears. When the last owner is disposed, the link to the session is released, so a refresh failure that arrives late leaves tokens and notices alone. While other owners remain, the shared failure is handled once.

## Environment

Use `DiomanEnvs` to apply environment settings during setup. It merges the first matching `EnvRule` into `BaseOptions`. It has no per-request option and is not part of the request chain. Ejecting it keeps the settings it already applied.

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

## Custom plugins

Keep configuration in `DiomanPlugin`, and let the `DiomanPluginInstance` returned by `setup` hold each client's state. Within a stage, `pre` runs before the built-in plugins and `post` after them; plugins in the same group keep their registration order.

`next(patch)` builds a request from this layer's current baseline and does not affect sibling attempts. `StateKey` compares by identity, so create it as a non-const instance. Wait with `ctx.wait`, and check `ctx.cancelled()` after each `await`. Call `markReplayable` before sending more than once. Map, List and FormData bodies are cloned when needed; a single-subscription Stream cannot be guaranteed replayable.

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

## Testing

For business logic tests, use inline `DiomanMock` routes. For timing tests, inject a `DiomanClock` and a scripted Dio transport. Check real timeout, `Transformer` and replay behavior against a local `HttpServer`, because fakes cannot prove network behavior. Get management interfaces such as `DiomanCacheApi` with `api.plugin<DiomanCacheApi>()`. After disposing the client, close the Dio you own.

```sh
dart analyze
dart test
dart run test/accept/bin/matrix.dart gates
```

## Migration

A Dio `unknown` error caused by a decoding `FormatException` now returns `kind: parse`, with the HTTP status when Dio provides one. HTML is still treated as text by default. With `expectJson: true` in json mode, a non-empty 2xx text body is treated as a parse failure whatever its MIME type. An explicit `ResponseType.plain`, `bytes` or `stream` skips this strict JSON check.

[0.7.2 → pipeline](docs/guides/migrating-to-pipeline.md) · [Architecture](docs/design/architecture.md) · [CHANGELOG](CHANGELOG.md)

To run the examples: `dart run example/dioman_example.dart` works offline; `dart run example/real_run.dart` calls a public service and needs network.

## Logical request deadline

`Dioman(deadline: ...)` sets a default time budget for a whole request; a non-null `DiomanCall(deadline: ...)` overrides it. If both are null there is no deadline, and a zero or negative duration expires immediately. The clock starts when the logical request enters the client and covers retry delays, token-refresh queues, offline queues, share waits and the whole transfer, including the response body. When it runs out, the result is `timeout` with `reason: 'deadline'`; it is not treated as a cancellation. Timers use `DiomanClock` and are cleared when the call settles. `extend` inherits the default.

This is separate from the Timeout plugin and from Dio's connect/send/receive timeouts. A share subscriber whose deadline expires leaves on its own; the shared transfer is cancelled only when the last subscriber leaves. With `end` and `race`, that caller drops out the same way a cancelled caller does (see Share).

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
