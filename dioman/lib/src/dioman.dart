import 'package:dio/dio.dart';

import 'auth_plugin.dart';
import 'key_plugin.dart';
import 'cache_plugin.dart';
import 'cancel_plugin.dart';
import 'dioman_plugin.dart';
import 'envs_plugin.dart';
import 'loading_plugin.dart';
import 'log_plugin.dart';
import 'mock_plugin.dart';
import 'normalize_plugin.dart';
import 'filter_plugin.dart';
import 'repath_plugin.dart';
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
///   cache: DiomanCache(),
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
    DiomanRepath? repath,
    DiomanFilter? filter,
    DiomanKey? key,
    DiomanCache? cache,
    DiomanShare? share,
    DiomanMock? mock,
    DiomanCancel? cancel,
    DiomanLoading? loading,
    DiomanAuth? auth,
    DiomanRetry? retry,
    DiomanLog? log,
    DiomanNormalize? normalize,
  }) {
    // envs → repath → filter → key → cache → share → mock → cancel →
    // loading → auth → retry → log → normalize
    //
    // DiomanNormalize is last on purpose (see its own class doc): it's an
    // optional, business-specific envelope-unwrapping convenience, not a
    // transport concern like everything before it. Running it last means
    // every other plugin (cache, share, retry's isExceptionRequest, ...)
    // sees the response exactly as it came off the wire.
    final ordered = <DiomanPlugin?>[
      envs,
      repath,
      filter,
      key,
      cache,
      share,
      mock,
      cancel,
      loading,
      auth,
      retry,
      log,
      normalize,
    ];
    final plugins = <DiomanPlugin>[
      for (final p in ordered)
        if (p != null) p,
    ];
    dio.interceptors.addAll(plugins);

    // Wire the settle-deferral hand-off (see DiomanShare.registerDownstreamSettler)
    // and the cancel-tracking hand-off automatically — the caller no longer
    // needs to pass `share:`/`cancel:` into DiomanRetry/DiomanAuth by hand.
    //
    // 自动完成结算推迟（见DiomanShare.registerDownstreamSettler）和取消追踪
    // 的接线——调用方不用再手动把`share:`/`cancel:`传进DiomanRetry/DiomanAuth。
    if (share != null) {
      retry?.share = share;
      auth?.share = share;
    }
    if (cancel != null) {
      retry?.cancel = cancel;
      auth?.cancel = cancel;
    }

    return DiomanHandle._(dio, plugins);
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
    p.dispose();
    return p;
  }

  /// Ejects every installed plugin from [_dio] and calls its [DiomanPlugin.dispose]
  /// (which nothing else does automatically) so timers, cancel tokens, shared
  /// refresh windows and reused Dio clients are released. Idempotent.
  void dispose() {
    _dio.interceptors.removeWhere((i) => _plugins.contains(i));
    for (final p in _plugins) {
      p.dispose();
    }
  }
}
