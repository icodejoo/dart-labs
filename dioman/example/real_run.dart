// ignore_for_file: avoid_print
//
// Real-network integration run. Hits a live public API
// (jsonplaceholder.typicode.com) — needs network; expect it to fail offline.
//
//   dart run example/real_run.dart
//
// 验证新客户端的缓存、共享、主动刷新、请求级覆盖和资源释放。
// 使用 --define=DIOMAN_EXAMPLE_BASE=<地址> 可由集成测试提供回环服务。

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

/// 文件内共用的字面量。
const _literalNew = "new";

/// 文件内共用的字面量。
const _literalGET = "GET";

/// 文件内共用的字面量。
const _literalTodos1 = "/todos/1";

/// 文件内共用的字面量。
const _literal = "";

/// 文件内共用的字面量。
const _literalTodos5 = "/todos/5";

/// 文件内共用的字面量。
const _literalTodosId = "/todos/{id}";

/// 文件内共用的字面量。
const _literalId = "id";

/// 文件内共用的字面量。
const _literalTodos10 = "/todos/10";

/// 默认真实服务；本地集成验证可用 --define 指向自建回环服务。
const _missingTodo = '/todos/999999';
const _base = String.fromEnvironment('DIOMAN_EXAMPLE_BASE',
    defaultValue: 'https://jsonplaceholder.typicode.com');

/// Minimal token store whose access token can be swapped by onRefresh.
class _TM implements DiomanTokenManager {
  _TM(this._access);
  String? _access;
  @override
  String? get accessToken => _access;
  @override
  String? get refreshToken => 'refresh';
  @override
  void setTokens({required String accessToken, String? refreshToken}) =>
      _access = accessToken;
  @override
  void clear() => _access = null;
  void set(String? t) => _access = t;
}

/// Minimal in-memory [DiomanCachePersist] for this script.
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

/// Counts requests that reach the END of the request chain = real outbound
/// calls. Cache/share/mock short-circuit earlier in the chain, so those never
/// increment this — making it a truthful network-hit counter.
class _NetCounter extends Interceptor {
  int count = 0;
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    count++;
    h.next(o);
  }
}

/// Fails the run with a clear message instead of limping on with a wrong
/// exit code — every assertion below is meant to be load-bearing evidence,
/// not a printed "expect N" that nobody checks.
void _check(bool ok, String label) {
  print('  ${ok ? 'OK ' : 'FAIL'} — $label');
  if (!ok) throw StateError('assertion failed: $label');
}

Future<void> main() async {
  final tm = _TM('old');
  var refreshCount = 0;
  final net = _NetCounter();

  final dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  final api = Dioman(dio: dio, plugins: [
    const DiomanRepath(),
    DiomanCache(persist: _MemCachePersist()),
    const DiomanShare(policy: DiomanSharePolicy.start),
    DiomanLoading(onChanged: (loading) => print('loading=$loading')),
    DiomanAuth(
        tokenManager: tm,
        expiresAt: (token) => token == _literalNew
            ? DateTime.now().add(const Duration(hours: 1))
            : DateTime.now().subtract(const Duration(seconds: 1)),
        onRefresh: (tokens, _) {
          refreshCount++;
          tokens.setTokens(accessToken: _literalNew);
        },
        onAccessExpired: (_, __) => print('session expired')),
    const DiomanRetry(max: 1),
  ]);
  try {
    dio.interceptors.add(net); // after log → counts true outbound

    print('=== installed: ${api.inspect().map((p) => p.$2).join(' → ')} ===\n');

    // ── 1. Cache: second identical GET is served from the store ───────────────
    print('[1] DiomanCache hit');
    final c1 = await api.send<dynamic>(_literalGET, _literalTodos1,
        call: DiomanCall(
            options: {DiomanCache.option: true, DiomanShare.option: true}));
    final before = net.count;
    final c2 = await api.send<dynamic>(_literalGET, _literalTodos1,
        call: DiomanCall(
            options: {DiomanCache.option: true, DiomanShare.option: true}));
    print('  1st: ${c1.status} ${c1.message}  data=${c1.data}');
    print('  2nd: ${c2.status} ${c2.message}');
    _check(net.count - before == 0,
        'second identical GET served from cache (0 net calls)');
    print(_literal);

    // ── 2. Share: N concurrent same-key GETs collapse to ONE network call ─────
    print('[2] DiomanShare dedup');
    final n0 = net.count;
    final shared = await Future.wait([
      api.send<dynamic>(_literalGET, _literalTodos5,
          call: DiomanCall(
              options: {DiomanCache.option: true, DiomanShare.option: true})),
      api.send<dynamic>(_literalGET, _literalTodos5,
          call: DiomanCall(
              options: {DiomanCache.option: true, DiomanShare.option: true})),
      api.send<dynamic>(_literalGET, _literalTodos5,
          call: DiomanCall(
              options: {DiomanCache.option: true, DiomanShare.option: true})),
    ]);
    final sharedCalls = net.count - n0;
    final allEqual =
        shared.every((r) => r.data.toString() == shared.first.data.toString());
    print(
        '  3 concurrent callers, net calls added: $sharedCalls, all equal: $allEqual');
    _check(sharedCalls == 1,
        '3 concurrent same-key GETs collapse to 1 network call');
    _check(allEqual, 'every caller receives the same shared result');
    print(_literal);

    // ── 3. Auth proactive refresh: concurrent expired-token requests refresh
    //       exactly once, then all succeed ──────────────────────────────────────
    print('[3] DiomanAuth proactive refresh (token starts expired)');
    final r0 = net.count;
    await Future.wait([
      api.send<dynamic>(_literalGET, '/todos/6',
          call: DiomanCall(
              options: {DiomanCache.option: true, DiomanShare.option: true})),
      api.send<dynamic>(_literalGET, '/todos/7',
          call: DiomanCall(
              options: {DiomanCache.option: true, DiomanShare.option: true})),
      api.send<dynamic>(_literalGET, '/todos/8',
          call: DiomanCall(
              options: {DiomanCache.option: true, DiomanShare.option: true})),
    ]);
    print('  refreshCount=$refreshCount, token now=${tm.accessToken}, '
        'net calls added: ${net.count - r0}');
    _check(refreshCount == 1,
        'concurrent expiring requests collapse to exactly ONE refresh');
    _check(
        net.count - r0 == 3, 'all 3 requests still went out over the network');
    print(_literal);

    // ── 4. DiomanRepathOptions: default substitutes {id}; enabled:false leaves
    //       the literal placeholder in the path (→ 404) ───────────────────────
    print('[4] DiomanRepathOptions');
    final repathed = await api
        .send<dynamic>(_literalGET, _literalTodosId, query: {_literalId: 9});
    _check(repathed.data[_literalId] == 9,
        'default repath substitutes {id} → /todos/9');
    try {
      await api.request<dynamic>(
        _literalGET,
        _literalTodosId,
        query: {_literalId: 9},
        call: DiomanCall(options: {DiomanRepath.option: false}),
      );
      _check(false,
          'DiomanRepathOptions(enabled:false) should have left a literal, invalid path');
    } on DiomanResponse catch (e) {
      _check(e.status == 404,
          'DiomanRepathOptions(enabled:false) leaves the literal placeholder → 404');
    }
    print(_literal);

    // ── 5. DiomanCacheOptions(enabled:false): bypasses the cache hit ───────────
    print('[5] DiomanCacheOptions(enabled: false)');
    await api.send<dynamic>(_literalGET, _literalTodos1,
        call: DiomanCall(options: {
          DiomanCache.option: true,
          DiomanShare.option: true
        })); // still a cache hit from step 1
    final beforeBypass = net.count;
    await api.send<dynamic>(
      _literalGET,
      _literalTodos1,
      call: DiomanCall(options: {DiomanCache.option: false}),
    );
    _check(net.count - beforeBypass == 1,
        'DiomanCacheOptions(enabled:false) bypasses an otherwise-cached hit');
    print(_literal);

    // ── 6. DiomanShareOptions(enabled:false): opts one caller out of dedup ─────
    print('[6] DiomanShareOptions(enabled: false)');
    final n1 = net.count;
    await Future.wait([
      api.send<dynamic>(_literalGET, _literalTodos10,
          call: DiomanCall(
              options: {DiomanCache.option: true, DiomanShare.option: true})),
      api.send<dynamic>(
        _literalGET,
        _literalTodos10,
        call: DiomanCall(options: {DiomanShare.option: false}),
      ),
    ]);
    _check(net.count - n1 == 2,
        'the opted-out caller issues its own request instead of joining the shared one');
    print(_literal);

    // ── 7. DiomanKeyOptions: a custom key makes two DIFFERENT endpoints share
    //       one cache entry ────────────────────────────────────────────────────
    print('[7] DiomanKeyOptions(key: ...)');
    const sharedKey = 'dioman-real-run-shared-key';
    final k1 = await api.send<dynamic>(
      _literalGET,
      '/todos/11',
      call: DiomanCall(key: sharedKey, options: {DiomanCache.option: true}),
    );
    final beforeKeyed = net.count;
    final k2 = await api.send<dynamic>(
      _literalGET,
      '/todos/12', // a DIFFERENT path, but same forced key → same cache entry
      call: DiomanCall(key: sharedKey, options: {DiomanCache.option: true}),
    );
    _check(net.count - beforeKeyed == 0,
        'a forced shared key makes a different path hit the same cache entry');
    _check(k2.data[_literalId] == k1.data[_literalId],
        'the second call returns the FIRST call\'s cached payload (id ${k1.data[_literalId]})');
    print(_literal);

    // ── 8. DiomanRetryOptions(shouldRetry: ...): forces a retry on a 404, which
    //       the plugin default (408/429/500/502/503/504) would never retry ──────
    print('[8] DiomanRetryOptions(shouldRetry: ...)');
    final beforeRetry = net.count;
    try {
      await api.send<dynamic>(
        _literalGET,
        _missingTodo, // jsonplaceholder 404s this
        call: DiomanCall(options: {
          DiomanRetry.option: DiomanRetryOptions(shouldRetry: (_, __) => true)
        }),
      );
    } on DiomanResponse catch (_) {
      // Expected — jsonplaceholder genuinely 404s; we only care how many times.
    }
    _check(net.count - beforeRetry == 2,
        'shouldRetry:true drives max(1)+1=2 attempts on a 404 the default shouldRetry ignores');
    print(_literal);

    // debug 现在属于客户端配置。
    final captured = <String>[];
    final debugApi =
        Dioman(dio: Dio(BaseOptions(baseUrl: _base)), debug: captured.add);
    try {
      final result = await debugApi.send<dynamic>(_literalGET, _missingTodo);
      _check(!result.ok && result.callSite != null, 'debug 为失败保留调用栈');
      debugApi.logError('示例诊断日志');
      _check(captured.isNotEmpty, 'debug 收到诊断日志');
    } finally {
      debugApi.dispose();
      debugApi.dio.close(force: true);
    }

    // ── 10. DiomanAuthOptions(enabled:false): request proceeds unprotected ────
    print('[10] DiomanAuthOptions(enabled: false)');
    final authRes = await api.send<dynamic>(
      _literalGET,
      '/todos/14',
      call: DiomanCall(options: {DiomanAuth.option: false}),
    );
    _check(authRes.status == 200,
        'DiomanAuthOptions(enabled:false) still lets the request through');
    print(_literal);

    _check(api.pending == 0, '所有逻辑请求释放');
    print('=== ALL CHECKS PASSED ===');
  } finally {
    api.cancelAll();
    api.dispose();
    dio.close(force: true);
  }
}
