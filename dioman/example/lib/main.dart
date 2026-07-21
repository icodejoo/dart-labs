// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:flutter/material.dart';

// ── Palette ───────────────────────────────────────────────────────────────────

const _bg     = Color(0xFF0D1117);
const _card   = Color(0xFF161B22);
const _border = Color(0xFF30363D);
const _blue   = Color(0xFF58A6FF);
const _green  = Color(0xFF3FB950);
const _red    = Color(0xFFF85149);
const _yellow = Color(0xFFD29922);
const _purple = Color(0xFFD2A8FF);
const _orange = Color(0xFFFF7B72);
const _cyan   = Color(0xFF79C0FF);
const _teal   = Color(0xFF56D364);
const _text   = Color(0xFFE6EDF3);
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
  Future<void> write(String key, Map<String, dynamic> value) async => _store[key] = value;
  @override
  Future<void> remove(String key) async => _store.remove(key);
  @override
  Future<void> erase() async => _store.clear();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

ResponseBody _json(String body, {int code = 200}) => ResponseBody.fromString(
  body, code,
  headers: {Headers.contentTypeHeader: ['application/json']},
);

void _emitJson(_Emit emit, dynamic data) {
  emit('result:', _Kind.system);
  const enc = JsonEncoder.withIndent('  ');
  for (final line in enc.convert(data).split('\n')) {
    emit('  $line', _Kind.response);
  }
}

DiomanLog _logPlugin(_Emit emit, {bool headers = false, bool body = true}) =>
    DiomanLog(
      logHeaders: headers,
      logBody: body,
      maxBodyLength: 200,
      writer: (msg, {error}) {
        final m = msg
            .replaceFirst('[dioman:log] ', '')
            .replaceAll('https://api.demo.dev', '');
        final kind = m.startsWith('→')
            ? _Kind.request
            : (error != null || m.startsWith('✗') ? _Kind.error : _Kind.response);
        emit(m, kind);
      },
    );

// ── _DemoAuth — replays via main Dio so mock intercepts the retry ─────────────

class _DemoAuth extends DiomanPlugin {
  _DemoAuth({required Dio dio, required _Emit emit})
      : _dio = dio, _emit = emit;

  final Dio _dio;
  final _Emit _emit;
  String _token = 'demo-access';
  bool _refreshed = false;

  @override
  String get name => 'demo:auth';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = 'Bearer $_token';
    _emit('dioman:auth      inject Bearer $_token', _Kind.system);
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401 || _refreshed) {
      handler.next(err);
      return;
    }
    _refreshed = true;
    _emit('dioman:auth      401 → refreshing token…', _Kind.system);
    await Future.delayed(const Duration(milliseconds: 600));
    _token = 'new-access-${DateTime.now().millisecondsSinceEpoch}';
    _emit('dioman:auth      refreshed ✓ → replaying', _Kind.system);
    err.requestOptions.cancelToken = null;
    err.requestOptions.headers['Authorization'] = 'Bearer $_token';
    try {
      final res = await _dio.fetch<dynamic>(err.requestOptions);
      handler.resolve(res);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

// ── _DemoRetry — retries via main Dio so mock intercepts each attempt ─────────

class _DemoRetry extends DiomanPlugin {
  _DemoRetry({required Dio dio, required _Emit emit})
      : _dio = dio, _emit = emit;

  final Dio _dio;
  final _Emit _emit;
  static const int _max = 2;
  static const int _baseMs = 300;
  static const Set<int> _codes = {500, 502, 503};
  int _attempts = 0;

  @override
  String get name => 'demo:retry';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    if (status == null || !_codes.contains(status) || _attempts >= _max) {
      handler.next(err);
      return;
    }
    _attempts++;
    final delay = Duration(milliseconds: _baseMs * _attempts);
    _emit(
      'dioman:retry     wait ${delay.inMilliseconds} ms → attempt ${_attempts + 1}',
      _Kind.system,
    );
    await Future.delayed(delay);
    err.requestOptions.cancelToken = null;
    try {
      final res = await _dio.fetch<dynamic>(err.requestOptions);
      handler.resolve(res);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

// ── Scenario runners ──────────────────────────────────────────────────────────

// 1. envs ──────────────────────────────────────────────────────────────────────

Future<void> _runEnvs(_Emit emit) async {
  emit('DiomanEnvs applies the first matching rule to dio.options at construction time — no HTTP needed.', _Kind.system);

  // Rule 0 matches → dev
  final devDio = Dio(BaseOptions(baseUrl: 'https://placeholder'));
  DiomanEnvs(dio: devDio, [
    EnvRule(
      rule: () => true,
      config: BaseOptions(
        baseUrl: 'https://api.dev.example',
        headers: {'X-Env': 'development'},
      ),
    ),
    EnvRule(
      rule: () => true,
      config: BaseOptions(baseUrl: 'https://api.prod.example'),
    ),
  ]);
  emit('rule[0] matched  →  baseUrl = "${devDio.options.baseUrl}"', _Kind.response);
  emit('                    X-Env   = "${devDio.options.headers['X-Env']}"', _Kind.response);

  // Rule 0 skipped → prod
  final prodDio = Dio(BaseOptions(baseUrl: 'https://placeholder'));
  DiomanEnvs(dio: prodDio, [
    EnvRule(rule: () => false, config: BaseOptions(baseUrl: 'https://api.dev.example')),
    EnvRule(
      rule: () => true,
      config: BaseOptions(
        baseUrl: 'https://api.prod.example',
        headers: {'X-Env': 'production'},
      ),
    ),
  ]);
  emit('rule[1] matched  →  baseUrl = "${prodDio.options.baseUrl}"', _Kind.response);
  emit('                    X-Env   = "${prodDio.options.headers['X-Env']}"', _Kind.response);
}

// 2. repath ────────────────────────────────────────────────────────────────────

Future<void> _runRepath(_Emit emit) async {
  final paths = <String>[];
  final mock = DiomanMock(enabled: true)
    ..add('GET:/users/42', (o) async {
      paths.add(o.uri.path);
      return _json('{"id":42}');
    })
    ..add('GET:/orgs/dart-labs/repos/dioman', (o) async {
      paths.add(o.uri.path);
      return _json('{"repo":"dioman"}');
    });

  final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
  dio.interceptors.addAll([DiomanRepath(), mock, _logPlugin(emit)]);

  emit('GET "/users/{id}"  queryParams: {id:42, q:"", page:1}', _Kind.system);
  await dio.get('/users/{id}', queryParameters: {'id': 42, 'q': '', 'page': 1});
  emit('actual path sent → "${paths[0]}"', _Kind.response);

  emit('GET "/orgs/{org}/repos/{repo}"', _Kind.system);
  await dio.get('/orgs/{org}/repos/{repo}',
      queryParameters: {'org': 'dart-labs', 'repo': 'dioman'});
  emit('actual path sent → "${paths[1]}"', _Kind.response);
}

// 3. filter ────────────────────────────────────────────────────────────────────

Future<void> _runFilter(_Emit emit) async {
  String? capturedQuery;
  final mock = DiomanMock(enabled: true)
    ..add('GET:/search', (o) async {
      capturedQuery = o.uri.query;
      return _json('{"results":[]}');
    });

  final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
  dio.interceptors.addAll([const DiomanFilter(), mock, _logPlugin(emit)]);

  final raw = {'q': '', 'page': 1, 'limit': null, 'active': true, 'tag': ''};
  emit('before filter: $raw', _Kind.system);
  await dio.get('/search', queryParameters: raw);
  emit('after filter:  ?$capturedQuery', _Kind.response);
  emit('  (empty-string q & tag, null limit stripped)', _Kind.system);
}

// 4. key ───────────────────────────────────────────────────────────────────────

Future<void> _runKey(_Emit emit) async {
  emit('DiomanKey normalises "METHOD:path?sorted-params" — param order is irrelevant.', _Kind.system);

  int hits = 0;
  final mock = DiomanMock(enabled: true)
    ..add('GET:/items', (_) async {
      hits++;
      return _json('[1,2,3]');
    });

  final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
  dio.interceptors.addAll([const DiomanKey(), DiomanCache(persist: _MemCachePersist()), mock, _logPlugin(emit)]);

  emit('① GET /items?sort=asc&page=1', _Kind.system);
  await dio.get('/items', queryParameters: {'sort': 'asc', 'page': 1});
  emit('   server hits: $hits', _Kind.system);

  emit('② GET /items?page=1&sort=asc  (same params, swapped order)', _Kind.system);
  await dio.get('/items', queryParameters: {'page': 1, 'sort': 'asc'});
  emit('   server hits: $hits  ← cache hit, same key', _Kind.response);

  emit('③ GET /items?page=2&sort=asc  (different value)', _Kind.system);
  await dio.get('/items', queryParameters: {'page': 2, 'sort': 'asc'});
  emit('   server hits: $hits  ← different key, new request', _Kind.response);
}

// 5. normalize ─────────────────────────────────────────────────────────────────

Future<void> _runNormalize(_Emit emit) async {
  final mock = DiomanMock(enabled: true)
    ..add('GET:/users/1', (_) async => _json(
        '{"code":0,"data":{"id":1,"name":"Alice"},"message":"ok"}'))
    ..add('GET:/users/2', (_) async => _json(
        '{"code":10001,"data":null,"message":"User not found"}'));

  // ── success: envelope unwrapped
  {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
    dio.interceptors.addAll([mock, const DiomanNormalize(), _logPlugin(emit)]);

    emit('response: {"code":0,"data":{...},"message":"ok"}', _Kind.system);
    final res = await dio.get('/users/1');
    emit('res.data (unwrapped): ${jsonEncode(res.data)}', _Kind.response);
  }

  // ── failure: non-zero code → DiomanException
  {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
    dio.interceptors.addAll([mock, const DiomanNormalize(), _logPlugin(emit)]);

    emit('response: {"code":10001,"data":null,"message":"User not found"}', _Kind.system);
    try {
      await dio.get('/users/2');
    } on DioException catch (e) {
      if (e.error is DiomanException) {
        final ex = e.error as DiomanException;
        emit('DiomanException(code: ${ex.code}, message: "${ex.message}")', _Kind.error);
      } else {
        emit('$e', _Kind.error);
      }
    }
  }
}

// 6. cache ─────────────────────────────────────────────────────────────────────

Future<void> _runCache(_Emit emit) async {
  int hits = 0;
  final mock = DiomanMock(enabled: true)
    ..add('GET:/users/1', (_) async {
      hits++;
      await Future.delayed(const Duration(milliseconds: 120));
      return _json('{"id":1,"name":"Bob Smith"}');
    });

  final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
  dio.interceptors.addAll(
      [const DiomanKey(), DiomanCache(persist: _MemCachePersist()), mock, _logPlugin(emit)]);

  emit('1st GET /users/1  (network)', _Kind.system);
  final t1 = Stopwatch()..start();
  await dio.get('/users/1');
  t1.stop();
  emit('   server hits: $hits   ${t1.elapsedMilliseconds} ms', _Kind.system);

  emit('2nd GET /users/1  (same key → cache)', _Kind.system);
  final t2 = Stopwatch()..start();
  final r2 = await dio.get('/users/1');
  t2.stop();
  emit(
    '   server hits: $hits   ${t2.elapsedMilliseconds} ms'
    '   statusMessage: "${r2.statusMessage}"',
    _Kind.response,
  );
}

// 7. share ─────────────────────────────────────────────────────────────────────

Future<void> _runDedup(_Emit emit) async {
  int hits = 0;
  final mock = DiomanMock(enabled: true)
    ..add('GET:/users/7', (_) async {
      hits++;
      emit('mock  actual HTTP call #$hits', _Kind.system);
      await Future.delayed(const Duration(milliseconds: 200));
      return _json('{"id":7,"name":"Carol"}');
    });

  final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
  dio.interceptors.addAll(
      [const DiomanKey(), DiomanShare(), mock, _logPlugin(emit)]);

  emit('fire 3× GET /users/7 concurrently…', _Kind.system);
  final sw = Stopwatch()..start();
  final results = await Future.wait([
    dio.get<dynamic>('/users/7'),
    dio.get<dynamic>('/users/7'),
    dio.get<dynamic>('/users/7'),
  ]);
  sw.stop();
  emit(
    '${results.length} callers resolved · $hits HTTP call · ${sw.elapsedMilliseconds} ms',
    _Kind.response,
  );
}

// 8. mock ──────────────────────────────────────────────────────────────────────

Future<void> _runMock(_Emit emit) async {
  final mock = DiomanMock(enabled: true)
    ..add('GET:/pets', (_) async =>
        _json('[{"id":1,"name":"Whiskers"},{"id":2,"name":"Buddy"}]'))
    ..add('POST:/pets', (o) async {
      final body = o.data is Map ? o.data as Map : <String, dynamic>{};
      return _json('{"id":3,"name":"${body["name"]}","created":true}', code: 201);
    })
    ..add('DELETE:/pets/1', (_) async =>
        ResponseBody.fromString('', 204,
            headers: {Headers.contentTypeHeader: ['application/json']}));

  final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
  dio.interceptors.addAll([mock, _logPlugin(emit)]);

  emit('3 routes registered: GET /pets · POST /pets · DELETE /pets/1', _Kind.system);

  final list = await dio.get<dynamic>('/pets');
  emit('GET   /pets              → ${list.data}', _Kind.response);

  final created = await dio.post<dynamic>('/pets', data: {'name': 'Luna'});
  emit('POST  /pets {name:Luna}  → ${created.data}', _Kind.response);

  final del = await dio.delete<dynamic>('/pets/1');
  emit('DELETE /pets/1           → ${del.statusCode} No Content', _Kind.response);
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

  final mock = DiomanMock(enabled: true)
    ..add('GET:/slow/a', (o) => slowHandler(o, 'a'))
    ..add('GET:/slow/b', (o) => slowHandler(o, 'b'))
    ..add('GET:/slow/c', (o) => slowHandler(o, 'c'));

  final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
  dio.interceptors.addAll([DiomanCancel(), mock, _logPlugin(emit)]);

  emit('fire 3 slow requests (500 ms each)…', _Kind.system);

  Future<void> fire(String path, int n) async {
    try {
      await dio.get<dynamic>(path);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        aborted++;
        emit('  request $n cancelled ✗', _Kind.error);
      }
    }
  }

  final all = Future.wait([fire('/slow/a', 1), fire('/slow/b', 2), fire('/slow/c', 3)]);

  await Future.delayed(const Duration(milliseconds: 150));
  emit('cancelAll() — simulating page navigation', _Kind.system);
  cancelAll(dio, 'left page');

  await all;
  emit('cancelled: $aborted · completed: $done', _Kind.system);
}

// 10. loading ──────────────────────────────────────────────────────────────────

Future<void> _runLoading(_Emit emit) async {
  int counter = 0;

  final mock = DiomanMock(enabled: true)
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

  final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
  dio.interceptors.addAll([
    mock,
    DiomanLoading(onChanged: (on) {
      counter += on ? 1 : -1;
      emit('counter = $counter  (${on ? "+1" : "−1"})', _Kind.system);
    }),
    _logPlugin(emit),
  ]);

  emit('fire 3 concurrent requests (/task/a · /task/b · /task/c)…', _Kind.system);
  await Future.wait([
    dio.get<dynamic>('/task/a'),
    dio.get<dynamic>('/task/b'),
    dio.get<dynamic>('/task/c'),
  ]);
  emit('all done  counter = $counter', _Kind.response);
}

// 11. auth ─────────────────────────────────────────────────────────────────────

Future<void> _runAuth(_Emit emit) async {
  int calls = 0;
  final mock = DiomanMock(enabled: true)
    ..add('GET:/profile', (opts) async {
      calls++;
      if (calls == 1) {
        emit('mock  → 401  (expired token)', _Kind.system);
        throw DioException(
          requestOptions: opts,
          response: Response(
              requestOptions: opts, statusCode: 401,
              statusMessage: 'Unauthorized'),
          type: DioExceptionType.badResponse,
        );
      }
      emit('mock  → 200  (replayed with new token)', _Kind.system);
      return _json('{"id":1,"name":"Alice","role":"admin"}');
    });

  final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
  dio.interceptors.addAll(
      [mock, DiomanCancel(), _DemoAuth(dio: dio, emit: emit), _logPlugin(emit)]);

  emit('GET /profile  (token will expire → refresh → replay)', _Kind.system);
  try {
    final res = await dio.get<dynamic>('/profile');
    _emitJson(emit, res.data);
  } catch (e) {
    emit('$e', _Kind.error);
  }
}

// 12. retry ────────────────────────────────────────────────────────────────────

Future<void> _runRetry(_Emit emit) async {
  int attempts = 0;
  final mock = DiomanMock(enabled: true)
    ..add('GET:/flaky', (opts) async {
      attempts++;
      if (attempts <= 2) {
        emit('mock  → 500  (attempt $attempts)', _Kind.system);
        throw DioException(
          requestOptions: opts,
          response: Response(
              requestOptions: opts, statusCode: 500,
              statusMessage: 'Server Error'),
          type: DioExceptionType.badResponse,
        );
      }
      emit('mock  → 200  (attempt $attempts, success)', _Kind.system);
      return _json('{"status":"ok","attempts":$attempts}');
    });

  final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
  dio.interceptors.addAll(
      [mock, _DemoRetry(dio: dio, emit: emit), _logPlugin(emit)]);

  emit('GET /flaky  (fails ×2, succeeds on 3rd)', _Kind.system);
  try {
    final res = await dio.get<dynamic>('/flaky');
    _emitJson(emit, res.data);
  } catch (e) {
    emit('$e', _Kind.error);
  }
}

// 13. log ──────────────────────────────────────────────────────────────────────

Future<void> _runLog(_Emit emit) async {
  final mock = DiomanMock(enabled: true)
    ..add('GET:/config', (_) async => _json(
        '{"theme":"dark","lang":"zh","features":{"beta":true}}'));

  emit('── logBody: true (default) ──', _Kind.system);
  {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
    dio.interceptors.addAll([mock, _logPlugin(emit, body: true)]);
    await dio.get<dynamic>('/config');
  }

  emit('── logBody: false ──', _Kind.system);
  {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
    dio.interceptors.addAll([mock, _logPlugin(emit, body: false)]);
    await dio.get<dynamic>('/config');
  }

  emit('── per-request: enabled: false ──', _Kind.system);
  {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.demo.dev'));
    dio.interceptors.addAll([mock, _logPlugin(emit)]);
    await dio.get<dynamic>('/config',
        options: Options(extra: {
          'dioman:log': const DiomanLogOptions(enabled: false),
        }));
    emit('  (nothing logged — per-request disabled)', _Kind.system);
  }

  emit('── custom writer routes to any sink ──', _Kind.system);
  emit('  all other scenario consoles use the same writer pattern', _Kind.system);
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
    icon: Icons.tune_rounded,
    title: 'Env Config',
    subtitle: 'Apply env-specific BaseOptions at install time — no HTTP needed',
    color: _blue,
    tags: ['envs'],
    run: _runEnvs,
  ),
  _Scenario(
    icon: Icons.edit_road_rounded,
    title: 'Path Rewrite',
    subtitle: '{id} / :{id} templates replaced before the request is sent',
    color: _cyan,
    tags: ['repath', 'mock'],
    run: _runRepath,
  ),
  _Scenario(
    icon: Icons.filter_alt_rounded,
    title: 'Param Filter',
    subtitle: 'null & empty-string query params stripped automatically',
    color: _teal,
    tags: ['filter', 'mock'],
    run: _runFilter,
  ),
  _Scenario(
    icon: Icons.vpn_key_rounded,
    title: 'Request Key',
    subtitle: 'Canonical key sorts params — swapped order = same cache hit',
    color: _subtle,
    tags: ['key', 'cache'],
    run: _runKey,
  ),
  _Scenario(
    icon: Icons.unarchive_rounded,
    title: 'Normalize',
    subtitle: 'Unwrap {code, data, message} envelope — throw DiomanException on non-zero code',
    color: _orange,
    tags: ['normalize', 'mock'],
    run: _runNormalize,
  ),
  _Scenario(
    icon: Icons.memory_rounded,
    title: 'Cache',
    subtitle: 'Same GET twice — 2nd served from in-memory LRU, near-zero latency',
    color: _green,
    tags: ['cache', 'mock'],
    run: _runCache,
  ),
  _Scenario(
    icon: Icons.people_rounded,
    title: 'Request Dedup',
    subtitle: '3 concurrent identical GETs → only 1 actual HTTP call (DiomanShare)',
    color: _purple,
    tags: ['share', 'mock'],
    run: _runDedup,
  ),
  _Scenario(
    icon: Icons.developer_mode_rounded,
    title: 'Mock Routes',
    subtitle: 'Register inline handlers by METHOD:path — GET · POST · DELETE',
    color: _teal,
    tags: ['mock'],
    run: _runMock,
  ),
  _Scenario(
    icon: Icons.cancel_rounded,
    title: 'Cancel',
    subtitle: 'cancelAll() aborts all in-flight requests — e.g. on page navigation',
    color: _red,
    tags: ['cancel', 'mock'],
    run: _runCancel,
  ),
  _Scenario(
    icon: Icons.hourglass_empty_rounded,
    title: 'Loading Counter',
    subtitle: 'Ref-counted indicator: 3 concurrent requests → counter 0 → 3 → 0',
    color: _yellow,
    tags: ['loading', 'mock'],
    run: _runLoading,
  ),
  _Scenario(
    icon: Icons.lock_reset_rounded,
    title: '401 Refresh',
    subtitle: 'Token expired → silent refresh → original request auto-replayed',
    color: _yellow,
    tags: ['auth', 'mock'],
    run: _runAuth,
  ),
  _Scenario(
    icon: Icons.refresh_rounded,
    title: 'Network Retry',
    subtitle: '500 ×2 → back-off delay → success on 3rd attempt',
    color: _orange,
    tags: ['retry', 'mock'],
    run: _runRetry,
  ),
  _Scenario(
    icon: Icons.receipt_long_rounded,
    title: 'Log Options',
    subtitle: 'logBody · per-request enabled:false · custom writer to any sink',
    color: _subtle,
    tags: ['log'],
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
      title: 'dioman — interceptor playground',
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
      'envs', 'repath', 'filter', 'key', 'normalize',
      'cache', 'share', 'mock', 'cancel', 'loading',
      'auth', 'retry', 'log',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _Chip('dioman', _blue, bold: true, mono: true),
          const SizedBox(width: 10),
          const Text('interceptor playground',
              style: TextStyle(color: _subtle, fontSize: 13)),
        ]),
        const SizedBox(height: 16),
        const Text('Composable Dio interceptors',
            style: TextStyle(
                color: _text, fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'One card per plugin — all requests run in-browser, no server needed.\n'
          'DiomanMock intercepts every call. Tap Run to see it work.',
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
        color: isSubtle ? _border.withValues(alpha: 0.6) : color.withValues(alpha: 0.14),
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
          fontFamily: mono ? 'Courier New' : null,
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
        _Kind.system   => _subtle,
        _Kind.request  => _blue,
        _Kind.response => _green,
        _Kind.error    => _red,
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
                                  fontFamily: 'Courier New')),
                        ),
                        Expanded(
                          child: Text(e.msg,
                              style: TextStyle(
                                  color: _kindColor(e.kind),
                                  fontSize: 12,
                                  fontFamily: 'Courier New',
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
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w600)),
    );
  }
}
