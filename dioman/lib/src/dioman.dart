import 'package:dio/dio.dart';

import 'auth_plugin.dart';
import 'breaker_plugin.dart';
import 'key_plugin.dart';
import 'cache_plugin.dart';
import 'cancel_plugin.dart';
import 'dioman_plugin.dart';
import 'envs_plugin.dart';
import 'extra_keys.dart';
import 'loading_plugin.dart';
import 'log_plugin.dart';
import 'mock_plugin.dart';
import 'normalize_plugin.dart';
import 'offline_plugin.dart';
import 'plugin_order.dart';
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
  ///
  /// [plugins] 可额外混入自定义插件：它们排在内置插件之后参与稳定拓扑排序，
  /// 靠各自的 [DiomanPlugin.ordering] 声明想要的位置（无声明则留在末尾）；
  /// 重复名/环/缺失依赖抛 [DiomanPluginOrderException]。
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
    List<DiomanPlugin> plugins = const [],
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
    return installPlugins(dio, [
      for (final p in ordered)
        if (p != null) p,
      ...plugins,
    ]);
  }

  /// 对 [plugins] 做稳定拓扑排序（见 [sort]）后装进 [dio]，返回 [DiomanHandle]。
  ///
  /// 与 [install] 共用同一条装配路径（绑定宿主 Dio、接线 retry 与 breaker），
  /// 区别是顺序由插件各自的 [DiomanPlugin.ordering] 声明决定，且可混入自定义
  /// 插件。重复名、环、缺失依赖会在修改 [dio] 之前抛 [DiomanPluginOrderException]。
  ///
  /// 参数：[dio] 宿主；[plugins] 要安装的插件（无约束者保持给定顺序）。
  /// 返回：管理这些插件的 [DiomanHandle]。
  ///
  /// ```dart
  /// final handle = Dioman.installPlugins(dio, [myPlugin, const DiomanKey()]);
  /// ```
  static DiomanHandle installPlugins(Dio dio, Iterable<DiomanPlugin> plugins) {
    final sorted = sort(plugins);
    dio.interceptors.addAll(sorted);

    // Bind the host Dio to the plugins that replay/re-issue requests, so they
    // reuse its transport and hand recovered results to the interceptors after
    // them. Share/cancel settlement hand-off needs no wiring any more: auth /
    // retry register on each request themselves.
    //
    // 把宿主 Dio 绑定给会重放/重新发起请求的插件，让它们复用宿主传输层，并把
    // 恢复成功的结果交给排在它们之后的拦截器。share/cancel 的结算交接不再需要接线：
    // auth/retry 自己在每个请求上登记。
    for (final p in sorted) {
      _bindHost(p, dio);
    }
    _wireChain(sorted);

    return DiomanHandle._(dio, sorted);
  }

  /// 对 [plugins] 做稳定拓扑排序并返回新列表，不修改入参。
  ///
  /// 依据每个插件的 [DiomanPlugin.ordering]：无约束的插件保持给定顺序，被
  /// 需要的前驱会提前到刚好满足约束的位置；指向未安装插件的 before/after 被忽略。重复名、
  /// 缺失依赖、环会抛 [DiomanPluginOrderException]。
  ///
  /// 参数：[plugins] 待排序的插件。返回：满足全部约束的新顺序。
  ///
  /// ```dart
  /// final ordered = Dioman.sort([log, cache, key]); // key, cache, log
  /// ```
  static List<DiomanPlugin> sort(Iterable<DiomanPlugin> plugins) =>
      sortPlugins(plugins);

  /// 校验按链顺序给出的 [ordered]：无重复名、依赖齐全、无环，且满足每条
  /// before/after 约束。失败抛 [DiomanPluginOrderException]，通过则无返回。
  ///
  /// ```dart
  /// Dioman.validate(handle.plugins);
  /// ```
  static void validate(List<DiomanPlugin> ordered) =>
      validatePluginOrder(ordered);
}

/// 按 [plugins] 当前内容重算插件间接线；安装与每次插拔后都调用。
///
/// - retry ↔ breaker：有 [DiomanBreaker] 就接给 [DiomanRetry]（重试循环在熔断
///   触发时立即停止）；没有时不动，保留用户手动接的外部实例。移除时的清理
///   交给 [_unwire]。
/// - cache ↔ normalize：有 [DiomanNormalize] 就把"normalize 会判为业务失败"的
///   取反接给 [DiomanCache] 的写入判定（HTTP 200 + 业务失败不入缓存），没有就
///   撤销（这是内部接线字段，不影响用户的 shouldStore）。
void _wireChain(Iterable<DiomanPlugin> plugins) {
  DiomanRetry? retry;
  DiomanBreaker? breaker;
  DiomanCache? cache;
  DiomanNormalize? normalize;
  for (final p in plugins) {
    if (p is DiomanRetry) retry = p;
    if (p is DiomanBreaker) breaker = p;
    if (p is DiomanCache) cache = p;
    if (p is DiomanNormalize) normalize = p;
  }
  if (breaker != null) retry?.breaker = breaker;
  if (cache != null) {
    final failed =
        normalize == null ? null : diomanNormalizeFailureProbe(normalize);
    diomanCacheWireStoreJudge(
        cache, failed == null ? null : (response) => !failed(response));
  }
}

/// 撤销被摘除的 [removed] 与 [remaining] 之间由本库建立的接线。
///
/// 只清指向 [removed] 本身的引用：移除 breaker 时，只把还指着它的 retry 置空；
/// 移除 retry 时，只在它接的是同一链上的 breaker 时置空；移除 cache 时撤掉
/// normalize 接线。用户手动接的外部 breaker 不受影响。
void _unwire(DiomanPlugin removed, Iterable<DiomanPlugin> remaining) {
  if (removed is DiomanBreaker) {
    for (final p in remaining) {
      if (p is DiomanRetry && identical(p.breaker, removed)) p.breaker = null;
    }
  }
  if (removed is DiomanRetry && remaining.contains(removed.breaker)) {
    removed.breaker = null;
  }
  if (removed is DiomanCache) diomanCacheWireStoreJudge(removed, null);
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
    checkRemovable(_plugins, p);
    _dio.interceptors.remove(p);
    _plugins.remove(p);
    _bindHost(p, null);
    _unwire(p, _plugins);
    _wireChain(_plugins);
    p.dispose();
    return p;
  }

  /// Inserts [p] immediately before [anchor] — for slotting a custom plugin
  /// into the canonical chain without hand-managing `dio.interceptors`
  /// indices. [p] becomes managed by this handle (visible to
  /// [plugins]/[plugin]/[remove]/[dispose]). Throws [ArgumentError] if
  /// [anchor] isn't installed on this handle.
  ///
  /// 插入前会校验重复名、必需依赖与 before/after 约束，违反时抛
  /// [DiomanPluginOrderException]，handle 与 dio 保持原状。
  void insertBefore(DiomanPlugin anchor, DiomanPlugin p) {
    _checkAnchor(anchor);
    _checkInsert(_plugins.indexOf(anchor), p);
    _plugins.insert(_plugins.indexOf(anchor), p);
    _dio.interceptors.insert(_dio.interceptors.indexOf(anchor), p);
    _bindHost(p, _dio);
    _wireChain(_plugins);
  }

  /// Inserts [p] immediately after [anchor] — the counterpart to
  /// [insertBefore]. Throws [ArgumentError] if [anchor] isn't installed on
  /// this handle. 校验规则同 [insertBefore]。
  void insertAfter(DiomanPlugin anchor, DiomanPlugin p) {
    _checkAnchor(anchor);
    _checkInsert(_plugins.indexOf(anchor) + 1, p);
    _plugins.insert(_plugins.indexOf(anchor) + 1, p);
    _dio.interceptors.insert(_dio.interceptors.indexOf(anchor) + 1, p);
    _bindHost(p, _dio);
    _wireChain(_plugins);
  }

  /// Inserts [p] at the very front of the chain — before every plugin and
  /// any other interceptor already on [_dio]. [p] becomes managed by this
  /// handle. 校验规则同 [insertBefore]。
  void prepend(DiomanPlugin p) {
    _checkInsert(0, p);
    _plugins.insert(0, p);
    _dio.interceptors.insert(0, p);
    _bindHost(p, _dio);
    _wireChain(_plugins);
  }

  /// Inserts [p] at the very end of the chain. [p] becomes managed by this
  /// handle. 校验规则同 [insertBefore]。
  void append(DiomanPlugin p) {
    _checkInsert(_plugins.length, p);
    _plugins.add(p);
    _dio.interceptors.add(p);
    _bindHost(p, _dio);
    _wireChain(_plugins);
  }

  /// 校验把 [p] 插到 [index] 后的链是否合法（不修改状态）。
  void _checkInsert(int index, DiomanPlugin p) {
    validatePluginOrder([..._plugins]..insert(index, p));
  }

  /// 诊断：检查宿主 `dio.interceptors` 上是否有同名插件实例共享状态键。
  ///
  /// 比 handle 自身的重复名校验更广：能发现绕过 handle、直接往
  /// `dio.interceptors` 里重复添加的实例。返回冲突列表，无冲突为空；详见
  /// [DiomanExtraKeys.findSharedState]。
  ///
  /// ```dart
  /// assert(handle.diagnoseSharedStateKeys().isEmpty);
  /// ```
  List<DiomanSharedStateKey> diagnoseSharedStateKeys() =>
      DiomanExtraKeys.findSharedState(_dio.interceptors);

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
      _unwire(p, _plugins);
      p.dispose();
    }
  }
}
