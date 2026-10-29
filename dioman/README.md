# dioman

Dioman brings authentication, retries, caching and the rest of your request policies together around Dio, for Dart and Flutter.

## Purpose

Request policies get harder to maintain when each interceptor has to understand the backend envelope and coordinate with every other interceptor. Dioman gives your app one request entry point and normalizes results before plugins see them, so auth, retry and cache can work with the same business status instead of each decoding it again.

The pipeline wraps each attempt in a predictable order. When auth refreshes a token or retry sends again, that attempt naturally passes through the inner cache, share and mock layers. The kernel keeps cancellation attached to the whole call and loading callbacks paired through those waits. You configure the policies you need without wiring their cleanup and replay paths together.

Start requests through the Dioman client to get this behavior. Its underlying Dio still handles transport and Dio interceptors; calling Dio directly runs those interceptors alone.

## Installation

```sh
dart pub add dioman
```

Requires Dart ^3.5.0; Dio is the only runtime dependency.

## Quick start

The quick start uses inline routes and runs offline. Remove DiomanMock when connecting to your backend.

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

## Results

Use get/post/put/patch/delete/head when you want the data, or send when you also need the DiomanResponse metadata. Verb methods throw a failed result that you can catch; send lets you inspect the same failure as a return value. Programming errors keep their original exception and stack. If your app has its own failure type, configure reject to map expected verb-method failures.

Result fields: `ok`, `kind`, `status` (logical status), `httpStatus`, `code`, `message`, `data`, `reason`, `request`, `raw`, `error`, `errorStack`, `callSite`.

Kinds: `ok`, `http`, `biz`, `network`, `timeout`, `cancel`, `parse`, `auth`, `breaker`, `offline`, `internal`.

By default, a response is treated as an envelope when it contains code and at least one of data/message, and is unwrapped once. If your backend uses another format, customize detection, success codes and logical status with Envelope and DiomanResponseFactory. Set call.envelope=false to keep the original data for one call.

## Plugins

Fixed stages: outer → prepare → attempt → credential → source → Dio.

Install the plugins your app needs, then adjust a call with DiomanCall(options: {Plugin.option: value}). Set a value to false to skip that policy, true to reuse its configuration, or an options object to override individual non-null fields. Each plugin also has an installation-level enabled switch. Cache and share need an explicit per-call opt-in; the other installed plugins participate by default.

### Loading

Loading keeps one display cycle around a logical call, including token refresh, cache hits, shared requests and offline waits. Your UI receives a paired open and close even when the call is cancelled.

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Notify

Notify waits for the final result before showing a message. By default it reports failures and stays quiet for successful, silent or cancelled calls.

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
    print(result.kind);
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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Filter

Filter removes top-level null, NaN and blank strings before sending. Values such as 0 and false remain, so an empty field does not erase a meaningful choice.

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Timeout

Timeout applies the Dio timeouts for the network tier your probe supplies. It does not detect connectivity itself, and its default configuration changes only the connection timeout.

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Retry

Set max explicitly when you want retries; its default is zero. Retry checks the method allowlist first, then uses logical status to decide whether to send another attempt through the inner layers.

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
    print(result.kind);
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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Auth

Auth protects all requests by default and shares one refresh operation within a client. Implement onRefresh to fetch and save the new token through an independent client. The renewed value below only illustrates updating the store.

Options: `tokenManager, onRefresh, onAccessExpired, onAccessDenied, onFailure, isProtected, ready, expiresAt, refreshLeeway, headerKey, buildHeader`. Full parameters and defaults: [plugin spec](docs/design/pipeline-plugin-spec.md).

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

Mock runs first within the source stage. An inline match returns before share, cache or offline run; a mock-server probe falls back to the real API by default only for HTTP 404 or a network failure.

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Share

Enable Share on calls that should coordinate concurrent requests, then choose start, end, race or retry. It is off when omitted, and subscribers to the same attempt share a read-only result.

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Cache

Enable Cache per call with a Duration TTL. It uses memo by default and stores successful GET/HEAD results. Use clear to invalidate all in-flight writes, or remove to invalidate just one key.

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Offline

Offline waits inside cache, so a cache hit can still answer while the network is down. The queue holds 50 calls by default and evicts the oldest on overflow; a nonpositive capacity removes the limit. Return false from shouldQueue to send immediately.

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
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

## Environment

Use DiomanEnvs to apply environment configuration during setup. It merges the first matching EnvRule into BaseOptions, without a request option or a place in the request chain. Ejecting it leaves the applied configuration in place.

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

Keep configuration in DiomanPlugin and let the DiomanPluginInstance returned by setup hold each client’s state. Within a stage, use pre to run before built-ins or post to run after them; ties retain registration order.

Calling next(patch) derives a request from the current baseline without changing sibling attempts. StateKey uses identity, so create a non-const instance. Use ctx.wait for waits and check ctx.cancelled() after awaiting. Before sending more than once, call markReplayable. Map/List/FormData bodies are cloned on demand; single-subscription Streams cannot be guaranteed replayable.

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

Use inline DiomanMock routes for business tests, and an injected DiomanClock plus scripted Dio transport for timing tests. Verify actual timeout, Transformer and replay behavior with a local HttpServer. Fakes cannot prove network behavior. Obtain management capabilities with api.plugin<DiomanCacheApi>() and similar interfaces. Close the caller-owned Dio after disposing the client.

```sh
dart analyze
dart test
dart run test/accept/bin/matrix.dart gates
```

## Migration

[0.7.2 → pipeline](docs/guides/migrating-to-pipeline.md) · [Architecture](docs/design/architecture.md) · [CHANGELOG](CHANGELOG.md)

Runnable versions: `dart run example/dioman_example.dart` (offline); `dart run example/real_run.dart` uses a public service and requires network.
