import 'package:dio/dio.dart';

import 'auth_plugin.dart';
import 'breaker_plugin.dart';
import 'key_plugin.dart';
import 'cache_plugin.dart';
import 'cancel_plugin.dart';
import 'dioman_plugin.dart';
import 'envs_plugin.dart';
import 'loading_plugin.dart';
import 'log_plugin.dart';
import 'mock_plugin.dart';
import 'normalize_plugin.dart';
import 'offline_plugin.dart';
import 'filter_plugin.dart';
import 'repath_plugin.dart';
import 'timeout_plugin.dart';
import 'retry_plugin.dart';
import 'share_plugin.dart';

/// One-call wiring for the dioman plugin chain in the **canonical order**.
///
/// The install order is a hard constraint (see the README ordering table):
/// each plugin's request / response / error roles only compose correctly in
/// this sequence. Ordering them by hand is error-prone, so pass the plugins
/// you want and [Dioman.install] slots them in for you — any omitted plugin
/// is simply skipped.
///
/// ```dart
/// final handle = Dioman.install(
///   dio,
///   key: const DiomanKey(),
///   cache: DiomanCache(persist: yourCachePersist),
///   auth: DiomanAuth(tokenManager: tm, onRefresh: ..., onAccessExpired: ...),
///   log: const DiomanLog(),
///   normalize: const DiomanNormalize(), // optional, business-specific — see its own doc
/// );
///
/// // Later — eject every installed plugin and release its resources:
/// handle.dispose();
/// ```
abstract final class Dioman {
  /// Adds the given plugins to [dio] in the canonical order and returns a
  /// [DiomanHandle] for later lookup / teardown. Omitted plugins are skipped.
  static DiomanHandle install(
    Dio dio, {
    DiomanEnvs? envs,
    DiomanTimeout? timeout,
    DiomanRepath? repath,
    DiomanFilter? filter,
    DiomanKey? key,
    DiomanCache? cache,
    DiomanOffline? offline,
    DiomanShare? share,
    DiomanMock? mock,
    DiomanCancel? cancel,
    DiomanLoading? loading,
    DiomanAuth? auth,
    DiomanRetry? retry,
    DiomanBreaker? breaker,
    DiomanLog? log,
    DiomanNormalize? normalize,
  }) {
    // envs → timeout → repath → filter → key → cache → offline → share → mock →
    // cancel → loading → auth → retry → breaker → log → normalize
    //
    // DiomanNormalize is last on purpose (see its own class doc): it's an
    // optional, business-specific envelope-unwrapping convenience, not a
    // transport concern like everything before it. Running it last means
    // every other plugin (cache, share, retry's shouldRetry, ...)
    // sees the response exactly as it came off the wire.
    final ordered = <DiomanPlugin?>[
      envs,
      timeout,
      repath,
      filter,
      key,
      cache,
      offline,
      share,
      mock,
      cancel,
      loading,
      auth,
      retry,
      breaker,
      log,
      normalize,
    ];
    final plugins = <DiomanPlugin>[
      for (final p in ordered)
        if (p != null) p,
    ];
    dio.interceptors.addAll(plugins);

    // Bind the host Dio to the plugins that replay/re-issue requests, so they
    // reuse its transport and hand recovered results to the interceptors after
    // them. Share/cancel settlement hand-off needs no wiring any more: auth /
    // retry register on each request themselves.
    //
    // 把宿主 Dio 绑定给会重放/重新发起请求的插件，让它们复用宿主传输层，并把
    // 恢复成功的结果交给排在它们之后的拦截器。share/cancel 的结算交接不再需要接线：
    // auth/retry 自己在每个请求上登记。
    for (final p in plugins) {
      _bindHost(p, dio);
    }
    // Let DiomanRetry consult the breaker before each re-issue, so an
    // in-progress retry loop stops the instant the breaker trips.
    //
    // 让DiomanRetry在每次重发前查询熔断器，正在进行的重试循环会在熔断器触发的
    // 那一刻立即停止。
    if (breaker != null) {
      retry?.breaker = breaker;
    }

    return DiomanHandle._(dio, plugins);
  }
}

/// 把宿主 [dio] 绑定给会重放请求的插件（share/auth/retry）；其它插件忽略。
void _bindHost(DiomanPlugin p, Dio? dio) {
  if (p is DiomanShare) {
    p.dio = dio;
  } else if (p is DiomanAuth) {
    p.dio = dio;
  } else if (p is DiomanRetry) {
    p.dio = dio;
  }
}

/// Handle to the plugins installed by [Dioman.install] — for lookup and
/// coordinated teardown.
class DiomanHandle {
  DiomanHandle._(this._dio, this._plugins);

  final Dio _dio;
  final List<DiomanPlugin> _plugins;

  /// The plugins installed, in chain order.
  List<DiomanPlugin> get plugins => List.unmodifiable(_plugins);

  /// Returns the installed plugin of type [T], or null if not installed.
  T? plugin<T extends DiomanPlugin>() {
    for (final p in _plugins) {
      if (p is T) return p;
    }
    return null;
  }

  /// Ejects the installed plugin of type [T] from [_dio] and calls its
  /// [DiomanPlugin.dispose] — the single-plugin counterpart to [dispose]'s
  /// teardown-everything. Returns the removed plugin, or null if [T] was
  /// never installed (a no-op in that case).
  T? remove<T extends DiomanPlugin>() {
    final p = plugin<T>();
    if (p == null) return null;
    _dio.interceptors.remove(p);
    _plugins.remove(p);
    _bindHost(p, null);
    p.dispose();
    return p;
  }

  /// Inserts [p] immediately before [anchor] — for slotting a custom plugin
  /// into the canonical chain without hand-managing `dio.interceptors`
  /// indices. [p] becomes managed by this handle (visible to
  /// [plugins]/[plugin]/[remove]/[dispose]). Throws [ArgumentError] if
  /// [anchor] isn't installed on this handle.
  void insertBefore(DiomanPlugin anchor, DiomanPlugin p) {
    _checkAnchor(anchor);
    _plugins.insert(_plugins.indexOf(anchor), p);
    _dio.interceptors.insert(_dio.interceptors.indexOf(anchor), p);
    _bindHost(p, _dio);
  }

  /// Inserts [p] immediately after [anchor] — the counterpart to
  /// [insertBefore]. Throws [ArgumentError] if [anchor] isn't installed on
  /// this handle.
  void insertAfter(DiomanPlugin anchor, DiomanPlugin p) {
    _checkAnchor(anchor);
    _plugins.insert(_plugins.indexOf(anchor) + 1, p);
    _dio.interceptors.insert(_dio.interceptors.indexOf(anchor) + 1, p);
    _bindHost(p, _dio);
  }

  /// Inserts [p] at the very front of the chain — before every plugin and
  /// any other interceptor already on [_dio]. [p] becomes managed by this
  /// handle.
  void prepend(DiomanPlugin p) {
    _plugins.insert(0, p);
    _dio.interceptors.insert(0, p);
    _bindHost(p, _dio);
  }

  /// Inserts [p] at the very end of the chain. [p] becomes managed by this
  /// handle.
  void append(DiomanPlugin p) {
    _plugins.add(p);
    _dio.interceptors.add(p);
    _bindHost(p, _dio);
  }

  void _checkAnchor(DiomanPlugin anchor) {
    if (!_plugins.contains(anchor)) {
      throw ArgumentError.value(
          anchor, 'anchor', 'is not installed on this handle');
    }
  }

  /// Ejects every installed plugin from [_dio] and calls its [DiomanPlugin.dispose]
  /// (which nothing else does automatically) so timers, cancel tokens, shared
  /// refresh windows and reused Dio clients are released. Idempotent.
  void dispose() {
    _dio.interceptors.removeWhere((i) => _plugins.contains(i));
    for (final p in _plugins) {
      _bindHost(p, null);
      p.dispose();
    }
  }
}
