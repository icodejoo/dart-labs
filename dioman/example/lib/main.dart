// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:flutter/material.dart';
import 'token_manager.dart';

/// 文件内共用的字面量。
const _literalHttpsPlaceholder = "https://placeholder";

/// 文件内共用的字面量。
const _literalHttpsApiDevExample = "https://api.dev.example";

/// 文件内共用的字面量。
const _literalXEnv = "X-Env";

/// 文件内共用的字面量。
const _literalHttpsApiProdExample = "https://api.prod.example";

/// 文件内共用的字面量。
const _literalHttpsApiDemoDev = "https://api.demo.dev";

/// 文件内共用的字面量。
const _literalGET = "GET";

/// 文件内共用的字面量。
const _literalId = "id";

/// 文件内共用的字面量。
const _literalQ = "q";

/// 文件内共用的字面量。
const _literal = "";

/// 文件内共用的字面量。
const _literalPage = "page";

/// 文件内共用的字面量。
const _literalDioman = "dioman";

/// 文件内共用的字面量。
const _literalItems = "/items";

/// 文件内共用的字面量。
const _literalSort = "sort";

/// 文件内共用的字面量。
const _literalAsc = "asc";

/// 文件内共用的字面量。
const _literalGETUsers1 = "GET:/users/1";

/// 文件内共用的字面量。
const _literalUsers1 = "/users/1";

/// 文件内共用的字面量。
const _literalUsers7 = "/users/7";

/// 文件内共用的字面量。
const _literalName = "name";

/// 文件内共用的字面量。
const _literalPets = "/pets";

/// 文件内共用的字面量。
const _literalEnvs = "envs";

/// 文件内共用的字面量。
const _literalRepath = "repath";

/// 文件内共用的字面量。
const _literalMock = "mock";

/// 文件内共用的字面量。
const _literalFilter = "filter";

/// 文件内共用的字面量。
const _literalKey = "key";

/// 文件内共用的字面量。
const _literalCache = "cache";

/// 文件内共用的字面量。
const _literalNormalize = "normalize";

/// 文件内共用的字面量。
const _literalShare = "share";

/// 文件内共用的字面量。
const _literalCancel = "cancel";

/// 文件内共用的字面量。
const _literalLoading = "loading";

/// 文件内共用的字面量。
const _literalAuth = "auth";

/// 文件内共用的字面量。
const _literalRetry = "retry";

/// 文件内共用的字面量。
const _literalLog = "log";

/// 文件内共用的字面量。
const _literalCourierNew = "Courier New";

// ── Palette ───────────────────────────────────────────────────────────────────

const _bg = Color(0xFF0D1117);
const _card = Color(0xFF161B22);
const _border = Color(0xFF30363D);
const _blue = Color(0xFF58A6FF);
const _green = Color(0xFF3FB950);
const _red = Color(0xFFF85149);
const _yellow = Color(0xFFD29922);
const _purple = Color(0xFFD2A8FF);
const _orange = Color(0xFFFF7B72);
const _cyan = Color(0xFF79C0FF);
const _teal = Color(0xFF56D364);
const _text = Color(0xFFE6EDF3);
const _subtle = Color(0xFF8B949E);

// ── Log model ─────────────────────────────────────────────────────────────────

enum _Kind { system, request, response, error }

class _Entry {
  _Entry(this.msg, this.kind, this.ms);
  final String msg;
  final _Kind kind;
  final int ms;
}

typedef _Emit = void Function(String msg, _Kind kind);

/// Minimal in-memory [DiomanCachePersist] for this demo. A real app would
/// back this with a file / sqlite / Hive / get_storage / etc.
class _MemCachePersist implements DiomanCachePersist {
  final _store = <String, dynamic>{};
  @override
  dynamic read(String key) => _store[key];
  @override
  Future<void> write(String key, Map<String, dynamic> value) async =>
      _store[key] = value;
  @override
  Future<void> remove(String key) async => _store.remove(key);
  @override
  Future<void> erase() async => _store.clear();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Fake backend for the demos: answers `'METHOD:path'` routes in-process, as a
/// real server would (so cache / share see ordinary responses). Installed as
/// the Dio `httpClientAdapter`; unknown routes get a 404.
class _FakeServer implements HttpClientAdapter {
  final _routes = <String, Future<ResponseBody> Function(RequestOptions)>{};

  /// Registers a handler for `routeKey` (`'METHOD:path'`).
  void add(String routeKey,
          Future<ResponseBody> Function(RequestOptions) handler) =>
      _routes[routeKey] = handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final handler =
        _routes['${options.method.toUpperCase()}:${options.uri.path}'];
    return handler == null
        ? ResponseBody.fromString('not found', 404)
        : handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, {int code = 200}) => ResponseBody.fromString(
      body,
      code,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    );

void _emitJson(_Emit emit, dynamic data) {
  emit('result:', _Kind.system);
  const enc = JsonEncoder.withIndent('  ');
  for (final line in enc.convert(data).split('\n')) {
    emit('  $line', _Kind.response);
  }
}

/// 示例的透明观察插件，只记录管线进出。
class _Trace extends DiomanPlugin {
  const _Trace(this.emit);
  final _Emit emit;
  @override
  String get name => 'demo:trace';
  @override
  DiomanStage get stage => DiomanStage.outer;
  @override
  DiomanPluginInstance setup(Dioman client) => _TraceInstance(emit);
}

/// 每客户端独立观察器。
class _TraceInstance extends DiomanPluginInstance {
  _TraceInstance(this.emit);
  final _Emit emit;
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext ctx, DiomanNext next) async {
    emit('${ctx.request.method} ${ctx.request.path}', _Kind.request);
    final result = await next();
    emit('${result.kind.name} ${result.status}',
        result.ok ? _Kind.response : _Kind.error);
    return result;
  }
}

DiomanPlugin _logPlugin(_Emit emit) => _Trace(emit);

/// 演示缓存和共享须由调用级显式开启。
final _sourceCall =
    DiomanCall(options: {DiomanCache.option: true, DiomanShare.option: true});

// ── Scenario runners ──────────────────────────────────────────────────────────

// 1. envs ──────────────────────────────────────────────────────────────────────

Future<void> _runEnvs(_Emit emit) async {
  emit(
      'DiomanEnvs applies the first matching rule to dio.options at construction time — no HTTP needed.',
      _Kind.system);

  // Rule 0 matches → dev
  final devDio = Dio(BaseOptions(baseUrl: _literalHttpsPlaceholder));
  final dev = Dioman(dio: devDio, plugins: [
    DiomanEnvs([
      EnvRule(
        rule: () => true,
        config: BaseOptions(
          baseUrl: _literalHttpsApiDevExample,
          headers: {_literalXEnv: 'development'},
        ),
      ),
      EnvRule(
        rule: () => true,
        config: BaseOptions(baseUrl: _literalHttpsApiProdExample),
      ),
    ])
  ]);
  emit('rule[0] matched  →  baseUrl = "${devDio.options.baseUrl}"',
      _Kind.response);
  emit(
      '                    X-Env   = "${devDio.options.headers[_literalXEnv]}"',
      _Kind.response);

  // Rule 0 skipped → prod
  final prodDio = Dio(BaseOptions(baseUrl: _literalHttpsPlaceholder));
  final prod = Dioman(dio: prodDio, plugins: [
    DiomanEnvs([
      EnvRule(
          rule: () => false,
          config: BaseOptions(baseUrl: _literalHttpsApiDevExample)),
      EnvRule(
        rule: () => true,
        config: BaseOptions(
          baseUrl: _literalHttpsApiProdExample,
          headers: {_literalXEnv: 'production'},
        ),
      ),
    ])
  ]);
  emit('rule[1] matched  →  baseUrl = "${prodDio.options.baseUrl}"',
      _Kind.response);
  emit(
      '                    X-Env   = "${prodDio.options.headers[_literalXEnv]}"',
      _Kind.response);
  dev.dispose();
  prod.dispose();
}

// 2. repath ────────────────────────────────────────────────────────────────────

Future<void> _runRepath(_Emit emit) async {
  final paths = <String>[];
  final mock = _FakeServer()
    ..add('GET:/users/42', (o) async {
      paths.add(o.uri.path);
      return _json('{"id":42}');
    })
    ..add('GET:/orgs/dart-labs/repos/dioman', (o) async {
      paths.add(o.uri.path);
      return _json('{"repo":"dioman"}');
    });

  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = mock;
  final api = Dioman(dio: dio, plugins: [DiomanRepath(), _logPlugin(emit)]);

  emit('GET "/users/{id}"  queryParams: {id:42, q:"", page:1}', _Kind.system);
  await api.send<dynamic>(
      _literalGET,
      call: _sourceCall,
      '/users/{id}',
      query: {_literalId: 42, _literalQ: _literal, _literalPage: 1});
  emit('actual path sent → "${paths[0]}"', _Kind.response);

  emit('GET "/orgs/{org}/repos/{repo}"', _Kind.system);
  await api.send<dynamic>(
      _literalGET,
      call: _sourceCall,
      '/orgs/{org}/repos/{repo}',
      query: {'org': 'dart-labs', 'repo': _literalDioman});
  emit('actual path sent → "${paths[1]}"', _Kind.response);
}

// 3. filter ────────────────────────────────────────────────────────────────────

Future<void> _runFilter(_Emit emit) async {
  String? capturedQuery;
  final mock = _FakeServer()
    ..add('GET:/search', (o) async {
      capturedQuery = o.uri.query;
      return _json('{"results":[]}');
    });

  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = mock;
  final api =
      Dioman(dio: dio, plugins: [const DiomanFilter(), _logPlugin(emit)]);

  final raw = {
    _literalQ: _literal,
    _literalPage: 1,
    'limit': null,
    'active': true,
    'tag': _literal
  };
  emit('before filter: $raw', _Kind.system);
  await api.send<dynamic>(
      _literalGET, call: _sourceCall, '/search', query: raw);
  emit('after filter:  ?$capturedQuery', _Kind.response);
  emit('  (empty-string q & tag, null limit stripped)', _Kind.system);
}

// 4. key ───────────────────────────────────────────────────────────────────────

Future<void> _runKey(_Emit emit) async {
  emit(
      'DiomanKey normalises "METHOD:path?sorted-params" — param order is irrelevant.',
      _Kind.system);

  int hits = 0;
  final mock = _FakeServer()
    ..add('GET:/items', (_) async {
      hits++;
      return _json('[1,2,3]');
    });

  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = mock;
  final api = Dioman(
      dio: dio,
      plugins: [DiomanCache(persist: _MemCachePersist()), _logPlugin(emit)]);

  emit('① GET /items?sort=asc&page=1', _Kind.system);
  await api.send<dynamic>(
      _literalGET,
      call: _sourceCall,
      _literalItems,
      query: {_literalSort: _literalAsc, _literalPage: 1});
  emit('   server hits: $hits', _Kind.system);

  emit('② GET /items?page=1&sort=asc  (same params, swapped order)',
      _Kind.system);
  await api.send<dynamic>(
      _literalGET,
      call: _sourceCall,
      _literalItems,
      query: {_literalPage: 1, _literalSort: _literalAsc});
  emit('   server hits: $hits  ← cache hit, same key', _Kind.response);

  emit('③ GET /items?page=2&sort=asc  (different value)', _Kind.system);
  await api.send<dynamic>(
      _literalGET,
      call: _sourceCall,
      _literalItems,
      query: {_literalPage: 2, _literalSort: _literalAsc});
  emit('   server hits: $hits  ← different key, new request', _Kind.response);
}

// 5. normalize ─────────────────────────────────────────────────────────────────

Future<void> _runNormalize(_Emit emit) async {
  final mock = _FakeServer()
    ..add(
        _literalGETUsers1,
        (_) async =>
            _json('{"code":0,"data":{"id":1,"name":"Alice"},"message":"ok"}'))
    ..add(
        'GET:/users/2',
        (_) async =>
            _json('{"code":10001,"data":null,"message":"User not found"}'));

  // ── success: envelope unwrapped
  {
    final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
    dio.httpClientAdapter = mock;
    final api = Dioman(dio: dio, plugins: [_logPlugin(emit)]);

    emit('response: {"code":0,"data":{...},"message":"ok"}', _Kind.system);
    final res =
        await api.send<dynamic>(_literalGET, call: _sourceCall, _literalUsers1);
    emit('res.data (unwrapped): ${jsonEncode(res.data)}', _Kind.response);
  }

  /// 业务失败由结果 kind 与逻辑状态表达。
  {
    final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
    dio.httpClientAdapter = mock;
    final api = Dioman(dio: dio, plugins: [_logPlugin(emit)]);

    emit('response: {"code":10001,"data":null,"message":"User not found"}',
        _Kind.system);
    try {
      await api.request<dynamic>(_literalGET, call: _sourceCall, '/users/2');
    } on DiomanResponse catch (e) {
      emit('${e.kind.name} ${e.status}: ${e.message}', _Kind.error);
    }
  }
}

// 6. cache ─────────────────────────────────────────────────────────────────────

Future<void> _runCache(_Emit emit) async {
  int hits = 0;
  final mock = _FakeServer()
    ..add(_literalGETUsers1, (_) async {
      hits++;
      await Future.delayed(const Duration(milliseconds: 120));
      return _json('{"id":1,"name":"Bob Smith"}');
    });

  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = mock;
  final api = Dioman(
      dio: dio,
      plugins: [DiomanCache(persist: _MemCachePersist()), _logPlugin(emit)]);

  emit('1st GET /users/1  (network)', _Kind.system);
  final t1 = Stopwatch()..start();
  await api.send<dynamic>(_literalGET, call: _sourceCall, _literalUsers1);
  t1.stop();
  emit('   server hits: $hits   ${t1.elapsedMilliseconds} ms', _Kind.system);

  emit('2nd GET /users/1  (same key → cache)', _Kind.system);
  final t2 = Stopwatch()..start();
  final r2 =
      await api.send<dynamic>(_literalGET, call: _sourceCall, _literalUsers1);
  t2.stop();
  emit(
    '   server hits: $hits   ${t2.elapsedMilliseconds} ms'
    '   statusMessage: "${r2.message}"',
    _Kind.response,
  );
}

// 7. share ─────────────────────────────────────────────────────────────────────

Future<void> _runDedup(_Emit emit) async {
  int hits = 0;
  final mock = _FakeServer()
    ..add('GET:/users/7', (_) async {
      hits++;
      emit('mock  actual HTTP call #$hits', _Kind.system);
      await Future.delayed(const Duration(milliseconds: 200));
      return _json('{"id":7,"name":"Carol"}');
    });

  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = mock;
  final api = Dioman(dio: dio, plugins: [DiomanShare(), _logPlugin(emit)]);

  emit('fire 3× GET /users/7 concurrently…', _Kind.system);
  final sw = Stopwatch()..start();
  final results = await Future.wait([
    api.send<dynamic>(_literalGET, call: _sourceCall, _literalUsers7),
    api.send<dynamic>(_literalGET, call: _sourceCall, _literalUsers7),
    api.send<dynamic>(_literalGET, call: _sourceCall, _literalUsers7),
  ]);
  sw.stop();
  emit(
    '${results.length} callers resolved · $hits HTTP call · ${sw.elapsedMilliseconds} ms',
    _Kind.response,
  );
}

// 8. mock ──────────────────────────────────────────────────────────────────────

Future<void> _runMock(_Emit emit) async {
  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  final api = Dioman(dio: dio, plugins: [
    DiomanMock(routes: {
      'GET:/pets': (_) => [
            {_literalId: 1, _literalName: 'Whiskers'},
            {_literalId: 2, _literalName: 'Buddy'}
          ],
      'POST:/pets': (request) => {
            _literalId: 3,
            _literalName: (request.data as Map)[_literalName],
            'created': true
          },
      'DELETE:/pets/1': (request) => Response<dynamic>(
          requestOptions: RequestOptions(path: request.path), statusCode: 204),
    }),
    _logPlugin(emit),
  ]);

  emit('3 routes registered: GET /pets · POST /pets · DELETE /pets/1',
      _Kind.system);

  final list =
      await api.send<dynamic>(_literalGET, call: _sourceCall, _literalPets);
  emit('GET   /pets              → ${list.data}', _Kind.response);

  final created = await api
      .send<dynamic>('POST', _literalPets, data: {_literalName: 'Luna'});
  emit('POST  /pets {name:Luna}  → ${created.data}', _Kind.response);

  final del = await api.send<dynamic>('DELETE', '/pets/1');
  emit('DELETE /pets/1           → ${del.status} No Content', _Kind.response);
}

// 9. cancel ────────────────────────────────────────────────────────────────────

Future<void> _runCancel(_Emit emit) async {
  int done = 0, aborted = 0;

  Future<ResponseBody> slowHandler(RequestOptions opts, String tag) async {
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (opts.cancelToken?.isCancelled ?? false) {
        throw DioException(
          requestOptions: opts,
          type: DioExceptionType.cancel,
          message: 'cancelled by cancelAll()',
        );
      }
    }
    done++;
    return _json('{"tag":"$tag"}');
  }

  final mock = _FakeServer()
    ..add('GET:/slow/a', (o) => slowHandler(o, 'a'))
    ..add('GET:/slow/b', (o) => slowHandler(o, 'b'))
    ..add('GET:/slow/c', (o) => slowHandler(o, 'c'));

  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = mock;
  final api = Dioman(dio: dio, plugins: [_logPlugin(emit)]);

  emit('fire 3 slow requests (500 ms each)…', _Kind.system);

  Future<void> fire(String path, int n) async {
    try {
      await api.request<dynamic>(_literalGET, call: _sourceCall, path);
    } on DiomanResponse catch (e) {
      if (e.kind == DiomanKind.cancel) {
        aborted++;
        emit('  request $n cancelled ✗', _Kind.error);
      }
    }
  }

  final all =
      Future.wait([fire('/slow/a', 1), fire('/slow/b', 2), fire('/slow/c', 3)]);

  await Future.delayed(const Duration(milliseconds: 150));
  emit('cancelAll() — simulating page navigation', _Kind.system);
  api.cancelAll('left page');

  await all;
  emit('cancelled: $aborted · completed: $done', _Kind.system);
}

// 10. loading ──────────────────────────────────────────────────────────────────

Future<void> _runLoading(_Emit emit) async {
  int counter = 0;

  final mock = _FakeServer()
    ..add('GET:/task/a', (_) async {
      await Future.delayed(const Duration(milliseconds: 200));
      return _json('{"task":"a"}');
    })
    ..add('GET:/task/b', (_) async {
      await Future.delayed(const Duration(milliseconds: 320));
      return _json('{"task":"b"}');
    })
    ..add('GET:/task/c', (_) async {
      await Future.delayed(const Duration(milliseconds: 260));
      return _json('{"task":"c"}');
    });

  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = mock;
  final api = Dioman(dio: dio, plugins: [
    DiomanLoading(onChanged: (on) {
      counter += on ? 1 : -1;
      emit('counter = $counter  (${on ? "+1" : "−1"})', _Kind.system);
    }),
    _logPlugin(emit),
  ]);

  emit('fire 3 concurrent requests (/task/a · /task/b · /task/c)…',
      _Kind.system);
  await Future.wait([
    api.send<dynamic>(_literalGET, call: _sourceCall, '/task/a'),
    api.send<dynamic>(_literalGET, call: _sourceCall, '/task/b'),
    api.send<dynamic>(_literalGET, call: _sourceCall, '/task/c'),
  ]);
  emit('all done  counter = $counter', _Kind.response);
}

// 11. auth ─────────────────────────────────────────────────────────────────────

Future<void> _runAuth(_Emit emit) async {
  int calls = 0;
  final mock = _FakeServer()
    ..add('GET:/profile', (opts) async {
      calls++;
      if (calls == 1) {
        emit('mock  → 401  (expired token)', _Kind.system);
        throw DioException(
          requestOptions: opts,
          response: Response(
              requestOptions: opts,
              statusCode: 401,
              statusMessage: 'Unauthorized'),
          type: DioExceptionType.badResponse,
        );
      }
      emit('mock  → 200  (replayed with new token)', _Kind.system);
      return _json('{"id":1,"name":"Alice","role":"admin"}');
    });

  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = mock;
  final api = Dioman(dio: dio, plugins: [
    DiomanAuth(
        tokenManager: InMemoryTokenManager(access: 'demo-access'),
        onRefresh: (tokens, _) => tokens.setTokens(accessToken: 'new-access'),
        onAccessExpired: (_, __) {}),
    _logPlugin(emit)
  ]);

  emit('GET /profile  (token will expire → refresh → replay)', _Kind.system);
  try {
    final res =
        await api.send<dynamic>(_literalGET, call: _sourceCall, '/profile');
    _emitJson(emit, res.data);
  } catch (e) {
    emit('$e', _Kind.error);
  }
}

// 12. retry ────────────────────────────────────────────────────────────────────

Future<void> _runRetry(_Emit emit) async {
  int attempts = 0;
  final mock = _FakeServer()
    ..add('GET:/flaky', (opts) async {
      attempts++;
      if (attempts <= 2) {
        emit('mock  → 500  (attempt $attempts)', _Kind.system);
        throw DioException(
          requestOptions: opts,
          response: Response(
              requestOptions: opts,
              statusCode: 500,
              statusMessage: 'Server Error'),
          type: DioExceptionType.badResponse,
        );
      }
      emit('mock  → 200  (attempt $attempts, success)', _Kind.system);
      return _json('{"status":"ok","attempts":$attempts}');
    });

  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = mock;
  final api = Dioman(dio: dio, plugins: [
    DiomanRetry(
        max: 2,
        delay: (attempt, _, __) => Duration(milliseconds: 300 * attempt)),
    _logPlugin(emit)
  ]);

  emit('GET /flaky  (fails ×2, succeeds on 3rd)', _Kind.system);
  try {
    final res =
        await api.send<dynamic>(_literalGET, call: _sourceCall, '/flaky');
    _emitJson(emit, res.data);
  } catch (e) {
    emit('$e', _Kind.error);
  }
}

// 13. log ──────────────────────────────────────────────────────────────────────

Future<void> _runLog(_Emit emit) async {
  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = _FakeServer()
    ..add('GET:/config', (_) async => _json('{"theme":"dark"}'));
  final api = Dioman(
      dio: dio,
      plugins: [_logPlugin(emit)],
      debug: (String message) => emit(message, _Kind.system));
  try {
    final result = await api.send<dynamic>(_literalGET, '/config');
    _emitJson(emit, result.data);
  } finally {
    api.dispose();
    dio.close(force: true);
  }
}

/// 仅演示配置写入，不将假传输的耗时当作真实网络超时证明。
Future<void> _runTimeout(_Emit emit) async {
  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = _FakeServer()
    ..add('GET:/policy', (request) async {
      emit(
          'connect=${request.connectTimeout}, receive=${request.receiveTimeout}',
          _Kind.request);
      return _json('{"value":1}');
    });
  final api = Dioman(dio: dio, plugins: [
    DiomanTimeout(probe: () => NetworkQuality.good),
  ]);
  try {
    await api.get<dynamic>('/policy',
        call: DiomanCall(options: {
          DiomanTimeout.option: const DiomanTimeoutOptions(timeouts: {
            NetworkQuality.good: DiomanTimeouts(receive: Duration(seconds: 3)),
          }),
        }));
  } finally {
    api.dispose();
    dio.close(force: true);
  }
}

/// 熔断按尝试记账，打开后不再发传输。
Future<void> _runBreaker(_Emit emit) async {
  var sends = 0;
  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = _FakeServer()
    ..add('GET:/policy', (_) async {
      sends++;
      return _json('{}', code: 500);
    });
  final api =
      Dioman(dio: dio, plugins: [const DiomanBreaker(failureThreshold: 1)]);
  try {
    for (var i = 0; i < 2; i++) {
      final result = await api.send<dynamic>('GET', '/policy');
      emit('${result.kind.name}, reason=${result.reason}, sends=$sends',
          _Kind.response);
    }
    emit(
        'buckets=${api.plugin<DiomanBreakerApi>()?.bucketCount}', _Kind.system);
  } finally {
    api.dispose();
    dio.close(force: true);
  }
}

/// 连通事件恢复排队请求；销毁时关闭宿主持有的流。
Future<void> _runOffline(_Emit emit) async {
  var online = false;
  final connectivity = StreamController<bool>.broadcast();
  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = _FakeServer()
    ..add('GET:/policy', (_) async => _json('{"value":1}'));
  final api = Dioman(dio: dio, plugins: [
    DiomanLoading(
        onChanged: (visible) => emit('loading=$visible', _Kind.system)),
    DiomanOffline(
        isOnline: () => online, onConnectivityChanged: connectivity.stream),
  ]);
  final timer = Timer(const Duration(milliseconds: 300), () {
    online = true;
    emit('online event: resume queue', _Kind.system);
    connectivity.add(true);
  });
  try {
    final result = await api.send<dynamic>('GET', '/policy',
        call: DiomanCall(options: {
          DiomanOffline.option:
              const DiomanOfflineOptions(maxWait: Duration(seconds: 2)),
        }));
    emit(
        '${result.kind.name}, pending=${api.plugin<DiomanOfflineApi>()?.pending}',
        _Kind.response);
  } finally {
    timer.cancel();
    api.dispose();
    dio.close(force: true);
    await connectivity.close();
  }
}

/// 默认通知只接收最终失败；silent 抑制下一次通知。
Future<void> _runNotify(_Emit emit) async {
  var notices = 0;
  final dio = Dio(BaseOptions(baseUrl: _literalHttpsApiDemoDev));
  dio.httpClientAdapter = _FakeServer()
    ..add('GET:/policy', (_) async => _json('{}', code: 500));
  final api = Dioman(dio: dio, plugins: [
    DiomanNotify(notify: (message, result) {
      notices++;
      emit('notice: $message (${result.kind.name})', _Kind.error);
    }),
  ]);
  try {
    await api.send<dynamic>('GET', '/policy');
    await api.send<dynamic>('GET', '/policy',
        call: const DiomanCall(silent: true));
    emit(
        '2 failed calls, $notices notice; second call is silent', _Kind.system);
  } finally {
    api.dispose();
    dio.close(force: true);
  }
}

// ── Scenario definitions ──────────────────────────────────────────────────────

typedef _Runner = Future<void> Function(_Emit emit);

class _Scenario {
  const _Scenario({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tags,
    required this.run,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final List<String> tags;
  final _Runner run;
}

final _scenarios = <_Scenario>[
  _Scenario(
      icon: Icons.timer_outlined,
      title: 'Timeout Configuration',
      subtitle:
          'Inspect request-level network-tier settings; no real timeout claim',
      color: _blue,
      tags: ['timeout'],
      run: _runTimeout),
  _Scenario(
      icon: Icons.electrical_services,
      title: 'Circuit Breaker',
      subtitle: 'First 500 opens the circuit; second call returns kind=breaker',
      color: _red,
      tags: ['breaker'],
      run: _runBreaker),
  _Scenario(
      icon: Icons.wifi_off,
      title: 'Offline Queue',
      subtitle: 'Wait for connectivity inside the loading bracket',
      color: _yellow,
      tags: ['offline', 'loading'],
      run: _runOffline),
  _Scenario(
      icon: Icons.notifications_outlined,
      title: 'Final Notification',
      subtitle:
          'One final failure notice; a silent call suppresses the next notice',
      color: _orange,
      tags: ['notify'],
      run: _runNotify),
  _Scenario(
    icon: Icons.tune_rounded,
    title: 'Env Config',
    subtitle: 'Apply env-specific BaseOptions during setup — no HTTP needed',
    color: _blue,
    tags: [_literalEnvs],
    run: _runEnvs,
  ),
  _Scenario(
    icon: Icons.edit_road_rounded,
    title: 'Path Rewrite',
    subtitle: 'Expand {id}, :id and [id] before sending',
    color: _cyan,
    tags: [_literalRepath, _literalMock],
    run: _runRepath,
  ),
  _Scenario(
    icon: Icons.filter_alt_rounded,
    title: 'Param Filter',
    subtitle: 'Remove null, NaN and blank strings; keep zero and false',
    color: _teal,
    tags: [_literalFilter, _literalMock],
    run: _runFilter,
  ),
  _Scenario(
    icon: Icons.vpn_key_rounded,
    title: 'Request Key (kernel)',
    subtitle: 'Canonical key sorts params — swapped order = same cache hit',
    color: _subtle,
    tags: [_literalKey, _literalCache],
    run: _runKey,
  ),
  _Scenario(
    icon: Icons.unarchive_rounded,
    title: 'Result Model (kernel)',
    subtitle:
        'Kernel result model: send returns DiomanResponse with kind and logical status',
    color: _orange,
    tags: [_literalNormalize, _literalMock],
    run: _runNormalize,
  ),
  _Scenario(
    icon: Icons.memory_rounded,
    title: 'Cache',
    subtitle:
        'Same GET twice — 2nd served from in-memory LRU, near-zero latency',
    color: _green,
    tags: [_literalCache, _literalMock],
    run: _runCache,
  ),
  _Scenario(
    icon: Icons.people_rounded,
    title: 'Request Dedup',
    subtitle:
        '3 concurrent identical GETs → only 1 actual HTTP call (DiomanShare)',
    color: _purple,
    tags: [_literalShare, _literalMock],
    run: _runDedup,
  ),
  _Scenario(
    icon: Icons.developer_mode_rounded,
    title: 'Mock Routes',
    subtitle: 'Register inline handlers by METHOD:path — GET · POST · DELETE',
    color: _teal,
    tags: [_literalMock],
    run: _runMock,
  ),
  _Scenario(
    icon: Icons.cancel_rounded,
    title: 'Cancel (kernel)',
    subtitle:
        'cancelAll() aborts all in-flight requests — e.g. on page navigation',
    color: _red,
    tags: [_literalCancel, _literalMock],
    run: _runCancel,
  ),
  _Scenario(
    icon: Icons.hourglass_empty_rounded,
    title: 'Loading Counter',
    subtitle:
        'Ref-counted indicator: 3 concurrent requests → counter 0 → 3 → 0',
    color: _yellow,
    tags: [_literalLoading, _literalMock],
    run: _runLoading,
  ),
  _Scenario(
    icon: Icons.lock_reset_rounded,
    title: '401 Refresh',
    subtitle: 'Token expired → silent refresh → original request auto-replayed',
    color: _yellow,
    tags: [_literalAuth, _literalMock],
    run: _runAuth,
  ),
  _Scenario(
    icon: Icons.refresh_rounded,
    title: 'Network Retry',
    subtitle: '500 ×2 → back-off delay → success on 3rd attempt',
    color: _orange,
    tags: [_literalRetry, _literalMock],
    run: _runRetry,
  ),
  _Scenario(
    icon: Icons.receipt_long_rounded,
    title: 'Debug & Custom Plugin',
    subtitle: 'Kernel debug logger and a custom outer-stage tracing plugin',
    color: _subtle,
    tags: [_literalLog],
    run: _runLog,
  ),
];

// ── App ───────────────────────────────────────────────────────────────────────

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dioman — onion pipeline playground',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          surface: _card,
          primary: _blue,
          onSurface: _text,
        ),
        useMaterial3: true,
      ),
      home: const _HomePage(),
    );
  }
}

// ── Home page ─────────────────────────────────────────────────────────────────

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 28),
                  for (final s in _scenarios) ...[
                    _ScenarioCard(scenario: s),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 8),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const plugins = [
      _literalEnvs,
      _literalRepath,
      _literalFilter,
      _literalKey,
      _literalNormalize,
      _literalCache,
      _literalShare,
      _literalMock,
      _literalCancel,
      _literalLoading,
      _literalAuth,
      _literalRetry,
      _literalLog,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _Chip(_literalDioman, _blue, bold: true, mono: true),
          const SizedBox(width: 10),
          const Text('onion pipeline playground',
              style: TextStyle(color: _subtle, fontSize: 13)),
        ]),
        const SizedBox(height: 16),
        const Text('Request policies powered by Dio',
            style: TextStyle(
                color: _text, fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'One card per plugin — all requests run in-browser, no server needed.\n'
          'An in-process fake backend answers every call. Tap Run to see it work.',
          style: TextStyle(color: _subtle, fontSize: 14, height: 1.65),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: plugins.map((p) => _Chip(p, _subtle)).toList(),
        ),
      ],
    );
  }

  Widget _buildFooter() => const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Pure Dart · no Flutter dep in the lib · dio ^5.0.0  '
          '· github.com/icodejoo/dart-labs',
          style: TextStyle(color: _subtle, fontSize: 11.5),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color, {this.bold = false, this.mono = false});
  final String label;
  final Color color;
  final bool bold;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final isSubtle = color == _subtle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: isSubtle
            ? _border.withValues(alpha: 0.6)
            : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
            color: isSubtle ? _border : color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSubtle ? _subtle : color,
          fontSize: 11.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          fontFamily: mono ? _literalCourierNew : null,
        ),
      ),
    );
  }
}

// ── Scenario card ─────────────────────────────────────────────────────────────

class _ScenarioCard extends StatefulWidget {
  const _ScenarioCard({required this.scenario});
  final _Scenario scenario;

  @override
  State<_ScenarioCard> createState() => _ScenarioCardState();
}

class _ScenarioCardState extends State<_ScenarioCard> {
  bool _running = false;
  final List<_Entry> _log = [];
  int _t0 = 0;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _log.clear();
      _t0 = DateTime.now().millisecondsSinceEpoch;
    });

    void emit(String msg, _Kind kind) {
      if (!mounted) return;
      final ms = DateTime.now().millisecondsSinceEpoch - _t0;
      setState(() => _log.add(_Entry(msg, kind, ms)));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }

    try {
      await widget.scenario.run(emit);
    } catch (e) {
      emit('unhandled: $e', _Kind.error);
    }
    if (mounted) setState(() => _running = false);
  }

  Color _kindColor(_Kind k) => switch (k) {
        _Kind.system => _subtle,
        _Kind.request => _blue,
        _Kind.response => _green,
        _Kind.error => _red,
      };

  @override
  Widget build(BuildContext context) {
    final s = widget.scenario;
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: s.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(s.icon, color: s.color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title,
                          style: const TextStyle(
                              color: _text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(s.subtitle,
                          style: const TextStyle(
                              color: _subtle, fontSize: 12.5, height: 1.4)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children:
                            s.tags.map((t) => _TagChip(t, s.color)).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 78,
                  child: FilledButton(
                    onPressed: _running ? null : _run,
                    style: FilledButton.styleFrom(
                      backgroundColor: _running ? _border : s.color,
                      foregroundColor: _bg,
                      disabledBackgroundColor: _border,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _running
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _text.withValues(alpha: 0.5),
                            ),
                          )
                        : const Text('Run ›',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),

          // ── Log console ────────────────────────────────────────────────
          if (_log.isNotEmpty) ...[
            const Divider(color: _border, height: 1, thickness: 1),
            SizedBox(
              height: 240,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(14),
                itemCount: _log.length,
                itemBuilder: (_, i) {
                  final e = _log[i];
                  final ts = e.ms < 1000
                      ? '+${e.ms}ms '
                      : '+${(e.ms / 1000).toStringAsFixed(1)}s ';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 54,
                          child: Text(ts,
                              style: const TextStyle(
                                  color: _subtle,
                                  fontSize: 10.5,
                                  fontFamily: _literalCourierNew)),
                        ),
                        Expanded(
                          child: Text(e.msg,
                              style: TextStyle(
                                  color: _kindColor(e.kind),
                                  fontSize: 12,
                                  fontFamily: _literalCourierNew,
                                  height: 1.45)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }
}
