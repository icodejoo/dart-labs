# dioman

Dioman brings authentication, retries, caching and the rest of your request policies together around Dio, for Dart and Flutter.

R2b preserves web and Wasm support through a conditional native network classifier. Automatic keys include responseType in both deep and fast modes; Map keys carry type tags, so numeric 1 differs from string '1'. Byte keys retain the content hash and full base64 payload. Explicit keys and custom builders keep their output.

Cancellation short-circuits at next() before entering inner plugins. cancelAll(reason) and a caller CancelToken preserve the first cancellation reason as failureOf(result)?.reason, converting non-null reasons with toString(); omitted reasons remain null. Debug logs report each option key whose plugin is absent once per client, including false/null options; installed but disabled plugins count as installed.

For Dioman<R> where R is not DiomanResponse<dynamic>, supply response: DiomanResponseFactory<R>(create: ...). Missing create throws ArgumentError during construction, before plugin setup.

## Purpose

Request policies get harder to maintain when each interceptor has to understand the backend envelope and coordinate with every other interceptor. Dioman gives your app one request entry point and normalizes results before plugins see them, so plugins share one result contract. Auth, retry and breaker read the effective status chosen by your client configuration.

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

Use get/post/put/patch/delete/head when you want the data, or send when you also need the DiomanResponse metadata. Verb methods throw a failed result that you can catch; send lets you inspect the same failure as a return value. Programming errors keep their original exception and stack. If your app has its own failure type, configure reject to map expected verb-method failures.

Result fields: `ok`, `status` (HTTP only; 0 without a response), `code`, `message`, `data`, `request`, `raw`, `error`, `errorStack`, `callSite`. Read the kernel's readonly kind/reason through `failureOf(r)`; a marked result always has ok=false. Use `isDiomanCancel(e)` or `api.isCancel(e)` to recognize cancellation.

### Business style

Default parse unwraps one level only when a Map contains code and at least one of data/message; other bodies remain whole in data. Defaults are code=0, message='', data=null. Success requires HTTP 2xx and code=0 or '0'. Configure factory parse for other protocols. Business codes never rewrite HTTP status. Configure client statusOf explicitly for business style; retry/auth/breaker read ctx.statusOf. An exhaustive failure switch includes null for unmarked success, HTTP failure and business failure.

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

## Plugins

Fixed stages: outer → prepare → attempt → credential → source → Dio.

Install the plugins your app needs, then adjust a call with DiomanCall(options: {Plugin.option: value}). Set a value to false to skip that policy, true to reuse its configuration, or an options object to override individual non-null fields. Each plugin also has an installation-level enabled switch. Cache and share need an explicit per-call opt-in; the other installed plugins participate by default.

### Loading

Loading keeps one display cycle around a logical call, including token refresh, cache hits, shared requests and offline waits. Your UI receives a paired open and close even when the call is cancelled.

Equal (`==`) display callbacks share one true/false cycle across clients, including instance method tear-offs. `activeCount` counts only the current client. Disposal releases its own occupancy; a new client takes over a pending hide window, and disposing its owner sends the final false.

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

The default `stringify` returns an empty string for `failureOf(r)?.kind == DiomanFailureKind.internal`; custom formatting can opt in to a message.

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
    print(failureOf(result)?.kind);
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
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Retry

Behavior change: `retryAfterMax` defaults to 60 seconds. A Retry-After value (seconds or HTTP date) above that limit returns the current result without retrying. To honor practically unlimited waits, explicitly supply a very large Duration, such as `retryAfterMax: Duration(days: 36500)`. Server waits still receive no jitter and ignore `delayMax`. Streams and opaque bodies are sent at most once.

Retry defaults to two retries, with exponential waits starting at 300ms and a 10s delayMax. Set max: 0 to disable retries. Retry checks the method allowlist first, then uses ctx.statusOf to decide whether to send another attempt through the inner layers.

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

`refreshTimeout` is available on the plugin and `DiomanAuthOptions` (default 30 seconds, measured with `DiomanClock`). Timeout follows the refresh failure path and notifies expiration once per session. If a new login replaces the token while refresh fails, waiting calls continue with the current token. When `onRefresh` sends through the same client, disable auth for that call: `call: DiomanCall(options: {DiomanAuth.option: false})`. A consumed stream or opaque body cannot be replayed; the original result is returned.

Auth protects all requests by default and shares one refresh operation across clients using the same TokenManager. Implement onRefresh to fetch and save the new token through an independent client. The renewed value below only illustrates updating the store.

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
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Mock

Probe fallback does not resend a stream or opaque body; it returns the probe result when the body cannot be replayed.

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
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Share

Caller cancellation or subscription timeout withdraws that participant from end/race selection; the caller keeps its own cancellation/timeout result. Unsafe automatic keys bypass sharing (see Cache).

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
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

### Cache

Automatic keys now include responseType and typed Map keys, encode JSON arrays by content and encode byte lists up to 64 KiB with a content hash plus full base64. Larger byte bodies, FormData, streams, other objects and encoding failures produce no key and bypass cache/share. Cache hits recheck caller cancellation before returning.

Internal and cancel results are never cached, even when shouldStore returns true.

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
    print(failureOf(result)?.kind);
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
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

## Extension and resource lifetimes

`api.extend(dio: engine, options: overrides, plugins: replacements)` returns a child client. Omitting `plugins` inherits the configuration list and runs setup again. `dispose()` leaves the caller's engine open.

| Resource | Default extend | Explicit dio |
|---|---|---|
| BaseOptions | Cloned with separate Map containers | Uses the supplied engine options |
| options override | Merges non-null, non-default fields after setup; Maps merge by top-level key | Same merge, mutating the supplied engine |
| Interceptors, adapter, transformer | Omitted; new Dio defaults apply | Preserved |
| Instances, pending requests, pipeline | Created for the child | Same |
| Auth session, loading display | Shared by TokenManager / equal callback | Same |
| Factory, key, reject, debug, clock | Configuration or callback references inherited | Same |

BaseOptions cannot distinguish omitted fields from defaults, so defaults cannot reset inherited non-default values. Passing the parent's `dio` shares a mutable engine; option overrides also affect the parent.

Auth refresh, expiration and missing-token notices follow the TokenManager. Missing credentials notify once per session, resetting when a new token is observed. The last owner releases the association: late refresh failures then leave tokens and notices untouched. With remaining owners, the shared failure is handled once.

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

Dio unknown errors caused by decoding `FormatException` now return `kind: parse` with the HTTP status (when supplied by Dio). HTML remains text by default; `expectJson: true` rejects nonempty 2xx text in json mode regardless of MIME type. Explicit ResponseType.plain, bytes and stream bypass this strict JSON check.

[0.7.2 → pipeline](docs/guides/migrating-to-pipeline.md) · [Architecture](docs/design/architecture.md) · [CHANGELOG](CHANGELOG.md)

Runnable versions: `dart run example/dioman_example.dart` (offline); `dart run example/real_run.dart` uses a public service and requires network.
