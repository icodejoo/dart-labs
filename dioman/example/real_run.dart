// ignore_for_file: avoid_print
//
// Real-network integration run. Hits a live public API
// (jsonplaceholder.typicode.com) — needs network; expect it to fail offline.
//
//   dart run example/real_run.dart
//
// Exercises: Dioman.install wiring, DiomanCache hit + LRU, DiomanShare dedup,
// DiomanAuth proactive refresh (opt-in via expiresAt), handle.dispose(), AND
// the per-request DiomanXxxOptions override for repath/cache/share/key/retry/
// log/auth.

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

const _base = 'https://jsonplaceholder.typicode.com';

/// Minimal token store whose access token can be swapped by onRefresh.
class _TM implements DiomanTokenManager {
  _TM(this._access);
  String? _access;
  @override
  String? get accessToken => _access;
  @override
  String? get refreshToken => 'refresh';
  @override
  bool get canRefresh => true;
  @override
  void clear() => _access = null;
  void set(String? t) => _access = t;
}

/// Counts requests that reach the END of the request chain = real outbound
/// calls. Cache/share/mock short-circuit earlier in the chain, so those never
/// increment this — making it a truthful network-hit counter.
class _NetCounter extends DiomanPlugin {
  int count = 0;
  @override
  String get name => 'net-counter';
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

  final handle = Dioman.install(
    dio,
    repath: DiomanRepath(),
    key: const DiomanKey(),
    normalize: const DiomanNormalize(),
    cache: DiomanCache(),
    share: DiomanShare(policy: DiomanSharePolicy.start),
    cancel: DiomanCancel(),
    loading: DiomanLoading(onChanged: (l) => print('  [loading=$l]')),
    auth: DiomanAuth(
      tokenManager: tm,
      // Proactive refresh: 'old' is treated as expired, 'new' as fresh.
      expiresAt: (t) => t == 'new'
          ? DateTime.now().add(const Duration(hours: 1))
          : DateTime.now().subtract(const Duration(seconds: 1)),
      onRefresh: (m, _) async {
        refreshCount++;
        (m as _TM).set('new');
        print('  [auth] onRefresh() called → new token');
      },
      onAccessExpired: (_, __) async => print('  [auth] session expired'),
    ),
    retry: DiomanRetry(max: 1),
    log: const DiomanLog(logRequest: false, logResponse: false, logError: true),
  );
  dio.interceptors.add(net); // after log → counts true outbound

  print(
      '=== installed: ${handle.plugins.map((p) => p.name).join(' → ')} ===\n');

  // ── 1. Cache: second identical GET is served from the store ───────────────
  print('[1] DiomanCache hit');
  final c1 = await dio.get<dynamic>('/todos/1');
  final before = net.count;
  final c2 = await dio.get<dynamic>('/todos/1');
  print('  1st: ${c1.statusCode} ${c1.statusMessage}  data=${c1.data}');
  print('  2nd: ${c2.statusCode} ${c2.statusMessage}');
  _check(net.count - before == 0,
      'second identical GET served from cache (0 net calls)');
  print('');

  // ── 2. Share: N concurrent same-key GETs collapse to ONE network call ─────
  print('[2] DiomanShare dedup');
  final n0 = net.count;
  final shared = await Future.wait([
    dio.get<dynamic>('/todos/5'),
    dio.get<dynamic>('/todos/5'),
    dio.get<dynamic>('/todos/5'),
  ]);
  final sharedCalls = net.count - n0;
  final allEqual =
      shared.every((r) => r.data.toString() == shared.first.data.toString());
  print(
      '  3 concurrent callers, net calls added: $sharedCalls, all equal: $allEqual');
  _check(sharedCalls == 1,
      '3 concurrent same-key GETs collapse to 1 network call');
  _check(allEqual, 'every caller receives the same shared result');
  print('');

  // ── 3. Auth proactive refresh: concurrent expired-token requests refresh
  //       exactly once, then all succeed ──────────────────────────────────────
  print('[3] DiomanAuth proactive refresh (token starts expired)');
  final r0 = net.count;
  await Future.wait([
    dio.get<dynamic>('/todos/6'),
    dio.get<dynamic>('/todos/7'),
    dio.get<dynamic>('/todos/8'),
  ]);
  print('  refreshCount=$refreshCount, token now=${tm.accessToken}, '
      'net calls added: ${net.count - r0}');
  _check(refreshCount == 1,
      'concurrent expiring requests collapse to exactly ONE refresh');
  _check(net.count - r0 == 3, 'all 3 requests still went out over the network');
  print('');

  // ── 4. DiomanRepathOptions: default substitutes {id}; enabled:false leaves
  //       the literal placeholder in the path (→ 404) ───────────────────────
  print('[4] DiomanRepathOptions');
  final repathed =
      await dio.get<dynamic>('/todos/{id}', queryParameters: {'id': 9});
  _check(
      repathed.data['id'] == 9, 'default repath substitutes {id} → /todos/9');
  try {
    await dio.get<dynamic>(
      '/todos/{id}',
      queryParameters: {'id': 9},
      options: Options(
          extra: {'dioman:repath': const DiomanRepathOptions(enabled: false)}),
    );
    _check(false,
        'DiomanRepathOptions(enabled:false) should have left a literal, invalid path');
  } on DioException catch (e) {
    _check(e.response?.statusCode == 404,
        'DiomanRepathOptions(enabled:false) leaves the literal placeholder → 404');
  }
  print('');

  // ── 5. DiomanCacheOptions(enabled:false): bypasses the cache hit ───────────
  print('[5] DiomanCacheOptions(enabled: false)');
  await dio.get<dynamic>('/todos/1'); // still a cache hit from step 1
  final beforeBypass = net.count;
  await dio.get<dynamic>(
    '/todos/1',
    options: Options(
        extra: {'dioman:cache': const DiomanCacheOptions(enabled: false)}),
  );
  _check(net.count - beforeBypass == 1,
      'DiomanCacheOptions(enabled:false) bypasses an otherwise-cached hit');
  print('');

  // ── 6. DiomanShareOptions(enabled:false): opts one caller out of dedup ─────
  print('[6] DiomanShareOptions(enabled: false)');
  final n1 = net.count;
  await Future.wait([
    dio.get<dynamic>('/todos/10'),
    dio.get<dynamic>(
      '/todos/10',
      options: Options(
          extra: {'dioman:share': const DiomanShareOptions(enabled: false)}),
    ),
  ]);
  _check(net.count - n1 == 2,
      'the opted-out caller issues its own request instead of joining the shared one');
  print('');

  // ── 7. DiomanKeyOptions: a custom key makes two DIFFERENT endpoints share
  //       one cache entry ────────────────────────────────────────────────────
  print('[7] DiomanKeyOptions(key: ...)');
  const sharedKey = 'dioman-real-run-shared-key';
  final k1 = await dio.get<dynamic>(
    '/todos/11',
    options:
        Options(extra: {'dioman:qid': const DiomanKeyOptions(key: sharedKey)}),
  );
  final beforeKeyed = net.count;
  final k2 = await dio.get<dynamic>(
    '/todos/12', // a DIFFERENT path, but same forced key → same cache entry
    options:
        Options(extra: {'dioman:qid': const DiomanKeyOptions(key: sharedKey)}),
  );
  _check(net.count - beforeKeyed == 0,
      'a forced shared key makes a different path hit the same cache entry');
  _check(k2.data['id'] == k1.data['id'],
      'the second call returns the FIRST call\'s cached payload (id ${k1.data['id']})');
  print('');

  // ── 8. DiomanRetryOptions(shouldRetry: ...): forces a retry on a 404, which
  //       the plugin default (5xx-only) would never retry ───────────────────
  print('[8] DiomanRetryOptions(shouldRetry: ...)');
  final beforeRetry = net.count;
  try {
    await dio.get<dynamic>(
      '/todos/999999', // jsonplaceholder 404s this
      options: Options(
        extra: {
          'dioman:retry': DiomanRetryOptions(shouldRetry: (err, response) => true)
        },
      ),
    );
  } on DioException catch (_) {
    // Expected — jsonplaceholder genuinely 404s; we only care how many times.
  }
  _check(net.count - beforeRetry == 2,
      'shouldRetry:true drives max(1)+1=2 attempts on a 404 the default shouldRetry ignores');
  print('');

  // ── 9. DiomanLogOptions(writer: ...): captures this call's log line ───────
  print('[9] DiomanLogOptions(writer: ...)');
  final captured = <String>[];
  await dio.get<dynamic>(
    '/todos/13',
    options: Options(extra: {
      'dioman:log': DiomanLogOptions(
          logRequest: true, writer: (msg, {error}) => captured.add(msg)),
    }),
  );
  _check(
      captured.isNotEmpty, 'per-request writer received the request log line');
  print('');

  // ── 10. DiomanAuthOptions(enabled:false): request proceeds unprotected ────
  print('[10] DiomanAuthOptions(enabled: false)');
  final authRes = await dio.get<dynamic>(
    '/todos/14',
    options: Options(
        extra: {'dioman:auth': const DiomanAuthOptions(enabled: false)}),
  );
  _check(authRes.statusCode == 200,
      'DiomanAuthOptions(enabled:false) still lets the request through');
  print('');

  // ── 11. cancelAll + handle.dispose teardown ────────────────────────────────
  print('[11] teardown');
  final cancelled = cancelAll(dio);
  print('  cancelAll → $cancelled in-flight cancelled');
  handle.dispose();
  final left = dio.interceptors
      .whereType<DiomanPlugin>()
      .where((p) => p.name != 'net-counter')
      .length;
  _check(left == 0, 'handle.dispose() ejects every installed plugin');

  print('\n=== ALL CHECKS PASSED ===');
}
