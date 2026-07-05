import 'package:dio/dio.dart';

import 'auth_plugin.dart';
import 'build_key_plugin.dart';
import 'cache_plugin.dart';
import 'cancel_plugin.dart';
import 'dio_plugin.dart';
import 'envs_plugin.dart';
import 'loading_plugin.dart';
import 'log_plugin.dart';
import 'mock_plugin.dart';
import 'normalize_plugin.dart';
import 'normalize_request_plugin.dart';
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
///   buildKey: const BuildKeyPlugin(),
///   normalize: const NormalizePlugin(),
///   cache: CachePlugin(),
///   auth: AuthPlugin(tokenManager: tm, onRefresh: ..., onAccessExpired: ...),
///   log: const LogPlugin(),
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
    EnvsPlugin? envs,
    RepathPlugin? repath,
    NormalizeRequestPlugin? normalizeRequest,
    BuildKeyPlugin? buildKey,
    NormalizePlugin? normalize,
    CachePlugin? cache,
    SharePlugin? share,
    MockPlugin? mock,
    CancelPlugin? cancel,
    LoadingPlugin? loading,
    AuthPlugin? auth,
    RetryPlugin? retry,
    LogPlugin? log,
  }) {
    // envs → repath → normalize-request → build-key → normalize → cache →
    // share → mock → cancel → loading → auth → retry → log
    final ordered = <DioPlugin?>[
      envs,
      repath,
      normalizeRequest,
      buildKey,
      normalize,
      cache,
      share,
      mock,
      cancel,
      loading,
      auth,
      retry,
      log,
    ];
    final plugins = <DioPlugin>[
      for (final p in ordered)
        if (p != null) p,
    ];
    dio.interceptors.addAll(plugins);
    return DiomanHandle._(dio, plugins);
  }
}

/// Handle to the plugins installed by [Dioman.install] — for lookup and
/// coordinated teardown.
class DiomanHandle {
  DiomanHandle._(this._dio, this._plugins);

  final Dio _dio;
  final List<DioPlugin> _plugins;

  /// The plugins installed, in chain order.
  List<DioPlugin> get plugins => List.unmodifiable(_plugins);

  /// Returns the installed plugin of type [T], or null if not installed.
  T? plugin<T extends DioPlugin>() {
    for (final p in _plugins) {
      if (p is T) return p;
    }
    return null;
  }

  /// Ejects every installed plugin from [_dio] and calls its [DioPlugin.dispose]
  /// (which nothing else does automatically) so timers, cancel tokens, shared
  /// refresh windows and reused Dio clients are released. Idempotent.
  void dispose() {
    _dio.interceptors.removeWhere((i) => _plugins.contains(i));
    for (final p in _plugins) {
      p.dispose();
    }
  }
}
