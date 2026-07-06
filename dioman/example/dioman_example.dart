// ignore_for_file: avoid_print

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

/// A minimal in-memory [ITokenManager] for the example.
/// In a real app back this with secure storage / your auth service.
class InMemoryTokenManager implements ITokenManager {
  InMemoryTokenManager({String? access, String? refresh})
      : _access = access,
        _refresh = refresh;

  String? _access;
  String? _refresh;

  @override
  String? get accessToken => _access;

  @override
  String? get refreshToken => _refresh;

  @override
  bool get canRefresh => _refresh != null && _refresh!.isNotEmpty;

  @override
  void clear() {
    _access = null;
    _refresh = null;
  }

  void save({required String access, required String refresh}) {
    _access = access;
    _refresh = refresh;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Plugin ORDER — the single most important thing when composing these plugins.
//
// Dio invokes onRequest / onResponse / onError of every interceptor in the SAME
// forward order they were added (Dio is NOT an onion model). Two facts drive the
// order below:
//
//   1. A short-circuit — `handler.resolve()` from onRequest (cache hit / share
//      wait / mock hit) — SKIPS every following response interceptor.
//   2. The onError chain always runs forward through EVERY interceptor, and the
//      first one to `resolve()` (auth-401-replay, retry) stops the rest.
//
// Resulting hard constraints:
//   • reqkey ─ before cache & share               (they read `extra['_key']`)
//   • normalize ─ before cache                     (cache must store, and a hit
//                                                    must return, the UNWRAPPED
//                                                    payload — else cached vs
//                                                    live responses differ)
//   • normalize ─ before auth                      (auth assumes business errors
//                                                    are already exceptions)
//   • cache/share/mock ─ before cancel & loading   (so a short-circuit doesn't
//                                                    leak a token / counter)
//   • cancel & loading ─ before auth & retry       (on a 401 or a network retry,
//                                                    auth/retry RESOLVE the error
//                                                    and halt the onError chain;
//                                                    the brackets must have run
//                                                    FIRST to release / decrement)
//
//  #   plugin              request role            response/error role
//  ── ──────────────────  ─────────────────────   ────────────────────────────
//  1  envs                (install-time apply)     —
//  2  repath              rewrite {id}/:id path    —
//  3  reqclean            strip empty params/data  —
//  4  reqkey              compute request key      —
//  5  normalize           —                        unwrap envelope / reject biz-err
//  6  cache               serve from cache         store unwrapped payload
//  7  share               dedup concurrent         settle waiters
//  8  mock                dev override / fallback   —
//  9  cancel              inject CancelToken        release token
//  10 loading             count++                  count-- (bracket)
//  11 auth                inject token / wait       401 → refresh + replay
//  12 retry               —                        retry network failures
//  13 log                 log request              log response / error
//
// Known trade-off: business-level retry (RetryPlugin.isExceptionRequest, which
// inspects the envelope `code`) is unavailable here because normalize (#5) has
// already unwrapped the body before retry (#12) sees it. Network-level retry is
// unaffected. If you need envelope-based retry, move RetryPlugin ahead of
// NormalizePlugin — but be aware that reintroduces the loading/cancel leak on a
// retried request, so pair it with `extra['loading'] = false` on those calls.
// ═════════════════════════════════════════════════════════════════════════════

/// Builds a fully-wired [Dio] instance with every plugin installed in order.
Dio createHttp({
  String baseUrl = 'https://api.example.com',
  Duration connectTimeout = const Duration(seconds: 15),
  Duration receiveTimeout = const Duration(seconds: 15),
  required ITokenManager tokenManager,
  void Function(bool loading)? onLoading,
  Future<void> Function()? onSessionExpired,
  bool enableMock = false,
  String? mockUrl,
  int retryMax = 2,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ),
  );

  // 1. envs — resolved once at install time; passing `dio` applies the matching
  //    rule to dio.options right here in the constructor.
  final envs = EnvsPlugin(dio: dio, [
    EnvRule(
      rule: () => const bool.fromEnvironment('dart.vm.product') == false,
      config: BaseOptions(baseUrl: baseUrl), // dev
    ),
    EnvRule(
      rule: () => true, // release fallback
      config: BaseOptions(baseUrl: baseUrl),
    ),
  ]);

  dio.interceptors.addAll(<DioPlugin>[
    // ── request pre-processing ────────────────────────────────────────────
    envs, //                                                              (1)
    RepathPlugin(), //                                                    (2)
    const ReqcleanPlugin(), //                                            (3)
    const ReqkeyPlugin(), //                                              (4)
    // ── response shaping / caching / dedup ────────────────────────────────
    const NormalizePlugin(), //                                           (5)
    CachePlugin(), //                                                     (6)
    SharePlugin(), //                                                     (7)
    MockPlugin(enabled: enableMock, mockUrl: mockUrl), //                 (8)
    // ── lifecycle brackets (must precede auth & retry) ────────────────────
    CancelPlugin(), //                                                    (9)
    LoadingPlugin(onChanged: onLoading ?? (l) => print('[http] loading=$l')),
    // ── auth & retry (may resolve the error chain) ────────────────────────
    AuthPlugin(
      tokenManager: tokenManager,
      isProtected: (o) => !o.path.contains('/auth/'), // public auth endpoints
      onRefresh: (tm, _) async {
        // Refresh with a bare Dio (no interceptors → no recursion).
        final res = await Dio(BaseOptions(baseUrl: baseUrl)).post<Map<String, dynamic>>(
          '/auth/refresh-token',
          data: {'refreshToken': tm.refreshToken},
        );
        final data = res.data ?? const {};
        (tm as InMemoryTokenManager).save(
          access: data['accessToken'] as String,
          refresh: data['refreshToken'] as String,
        );
      },
      onAccessExpired: (_, __) async => onSessionExpired?.call(),
    ), //                                                                 (11)
    RetryPlugin(dio: dio, max: retryMax), //                             (12)
    // ── observability (last: sees the fully-processed request) ────────────
    const LogPlugin(logHeaders: true), //                               (13)
  ]);

  return dio;
}

Future<void> main() async {
  final tokens = InMemoryTokenManager(access: 'demo-access', refresh: 'demo-refresh');

  final http = createHttp(
    baseUrl: 'https://api.example.com',
    tokenManager: tokens,
    onLoading: (active) => print('loading: $active'),
    onSessionExpired: () async => print('session expired → go to login'),
  );

  // Path variables via RepathPlugin; empty params stripped by ReqcleanPlugin;
  // GET is cached (CachePlugin) and deduped (SharePlugin); token injected (AuthPlugin).
  try {
    final res = await http.get(
      '/users/{id}',
      queryParameters: {'id': 42, 'q': '', 'page': 1},
    );
    print('user: ${res.data}');
  } on DioException catch (e) {
    print('request failed: ${e.message}');
  }

  // Per-request opt-outs live in `options.extra`:
  await http.get(
    '/public/config',
    options: Options(extra: {
      'protected': false, // AuthPlugin: no token required
      'cache': false, //    CachePlugin: skip cache
      'loading': false, //  LoadingPlugin: don't count toward the indicator
    }),
  );

  // Cancel everything in flight (e.g. on navigation):
  cancelAll(http, 'left page');
}
