// ignore_for_file: avoid_print
//
// Real-network smoke run for the recent changes. Hits a live public API
// (jsonplaceholder.typicode.com) — needs network; expect it to fail offline.
//
//   dart run example/real_run.dart
//
// Exercises: Dioman.install wiring, CachePlugin hit + LRU, SharePlugin dedup,
// AuthPlugin proactive refresh (opt-in via expiresAt), and handle.dispose().

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

const _base = 'https://jsonplaceholder.typicode.com';

/// Minimal token store whose access token can be swapped by onRefresh.
class _TM implements ITokenManager {
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
class _NetCounter extends DioPlugin {
  int count = 0;
  @override
  String get name => 'net-counter';
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    count++;
    h.next(o);
  }
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
    key: const KeyPlugin(),
    normalize: const NormalizePlugin(),
    cache: CachePlugin(),
    share: SharePlugin(policy: SharePolicy.start),
    cancel: CancelPlugin(),
    loading: LoadingPlugin(onChanged: (l) => print('  [loading=$l]')),
    auth: AuthPlugin(
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
    log: const LogPlugin(logRequest: false, logResponse: false, logError: true),
  );
  dio.interceptors.add(net); // after log → counts true outbound

  print('=== installed: ${handle.plugins.map((p) => p.name).join(' → ')} ===\n');

  // ── 1. Cache: second identical GET is served from the store ───────────────
  print('[1] CachePlugin hit');
  final c1 = await dio.get<dynamic>('/todos/1');
  final before = net.count;
  final c2 = await dio.get<dynamic>('/todos/1');
  print('  1st: ${c1.statusCode} ${c1.statusMessage}  data=${c1.data}');
  print('  2nd: ${c2.statusCode} ${c2.statusMessage}  (net calls added: '
      '${net.count - before} — 0 means served from cache)\n');

  // ── 2. Share: N concurrent same-key GETs collapse to ONE network call ─────
  print('[2] SharePlugin dedup');
  final n0 = net.count;
  final shared = await Future.wait([
    dio.get<dynamic>('/todos/5'),
    dio.get<dynamic>('/todos/5'),
    dio.get<dynamic>('/todos/5'),
  ]);
  print('  3 concurrent callers, net calls added: ${net.count - n0} '
      '(expect 1) — all equal: '
      '${shared.every((r) => r.data.toString() == shared.first.data.toString())}\n');

  // ── 3. Auth proactive refresh: concurrent expired-token requests refresh
  //       exactly once, then all succeed ──────────────────────────────────────
  print('[3] AuthPlugin proactive refresh (token starts expired)');
  final r0 = net.count;
  await Future.wait([
    dio.get<dynamic>('/todos/6'),
    dio.get<dynamic>('/todos/7'),
    dio.get<dynamic>('/todos/8'),
  ]);
  print('  refreshCount=$refreshCount (expect 1), token now=${tm.accessToken}, '
      'net calls added: ${net.count - r0} (expect 3)\n');

  // ── 4. cancelAll + handle.dispose teardown ────────────────────────────────
  print('[4] teardown');
  print('  cancelAll → ${cancelAll(dio)} in-flight cancelled');
  handle.dispose();
  print('  handle.dispose() → interceptors left: '
      '${dio.interceptors.whereType<DioPlugin>().where((p) => p.name != 'net-counter').length} '
      '(expect 0)');

  print('\n=== DONE ===');
}
