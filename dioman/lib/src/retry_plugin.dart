// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:dio/dio.dart';
import 'cache_plugin.dart';
import 'dioman_plugin.dart';
import 'key_plugin.dart';
import 'share_plugin.dart';

/// Per-request override for [DiomanRetry], read from `extra['dioman:retry']`.
///
/// [DiomanRetry]的单请求覆盖，从`extra['dioman:retry']`读取。
class DiomanRetryOptions {
  const DiomanRetryOptions({this.enabled, this.max, this.isException, this.delay, this.retryIf});

  /// `false` skips retry for this request. `null` (default) inherits
  /// [DiomanRetry.enabled].
  ///
  /// `false`表示本次请求跳过重试。`null`（默认）沿用[DiomanRetry.enabled]。
  final bool? enabled;

  /// Overrides the plugin's default max retry count for this request only.
  ///
  /// 仅本次请求覆盖插件默认的最大重试次数。
  final int? max;

  /// Overrides the plugin's default business-exception check for this
  /// request only.
  ///
  /// 仅本次请求覆盖插件默认的业务异常判定函数。
  final bool Function(Response<dynamic>)? isException;

  /// Overrides the plugin's default back-off `delay` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的退避延迟函数`delay`。
  final Duration Function(int attempt)? delay;

  /// Overrides the plugin's default network-error `retryIf` for this
  /// request only.
  ///
  /// 仅本次请求覆盖插件默认的网络错误判定函数`retryIf`。
  final bool Function(DioException)? retryIf;
}

/// Retries failed requests with configurable back-off.
///
/// 按可配置的退避策略重试失败的请求。
///
/// Supports two failure modes:
/// - **HTTP / network errors** (`onError` path) — network timeouts, 5xx, etc.
/// - **Business-level errors** (`isExceptionRequest`) — treat a 200 response
///   as a failure based on the response body (e.g. `code != 0`).
///
/// 支持两种失败模式：
/// - **HTTP/网络错误**（`onError`路径）——网络超时、5xx等。
/// - **业务级错误**（`isExceptionRequest`）——根据响应body把一个200响应
///   视为失败（比如`code != 0`）。
///
/// Per-request configuration via `options.extra['dioman:retry']`:
/// - `const DiomanRetryOptions(max: 1)` → override max retry count
/// - `const DiomanRetryOptions(enabled: false)` → skip retry for this request
///
/// ```dart
/// final retry = DiomanRetry(
///   dio: dio,
///   max: 3,
///   isExceptionRequest: (r) => r.data['code'] != 0,
/// );
/// dio.interceptors.add(retry);
/// ```
class DiomanRetry extends DiomanPlugin {
  DiomanRetry({
    required Dio dio,
    this.max = 0,
    this.delay,
    this.enabled = true,
    this.isExceptionRequest,
    DiomanCache? cache,
    DiomanShare? share,
    bool Function(DioException)? retryIf,
  })  : _dio = dio,
        _cache = cache,
        _share = share,
        retryIf = retryIf ?? _defaultRetryIf {
    share?.registerDownstreamSettler();
  }

  /// The [Dio] instance re-fetches are issued through (re-enters the full
  /// interceptor chain). Core dependency — deliberately NOT overridable per
  /// request.
  ///
  /// 重新发起请求所用的[Dio]实例（会重新经过完整拦截器链）。核心依赖——
  /// 刻意不允许单请求覆盖。
  final Dio _dio;

  /// The [DiomanCache] instance installed on the same [Dio], if any. Pass
  /// this whenever [DiomanCache] and [DiomanRetry] are combined —
  /// [DiomanCache] sits BEFORE [DiomanRetry] in the canonical chain and only
  /// understands HTTP status, not [isExceptionRequest]'s business-level
  /// concept, so a 2xx response [isExceptionRequest] rejects still gets
  /// written to the cache before this plugin ever sees it. Without this
  /// reference, the retry's own re-dispatch would then read that poisoned
  /// entry straight back instead of hitting the network, and the failure
  /// would stick for every caller until the entry's TTL expires. Providing
  /// [cache] evicts that poisoned entry right before retrying.
  ///
  /// 同一个[Dio]上安装的[DiomanCache]实例（如果有）。[DiomanCache]和
  /// [DiomanRetry]搭配使用时务必传入——[DiomanCache]在canonical链条上排在
  /// [DiomanRetry]前面，只认HTTP状态码，不认[isExceptionRequest]的业务级
  /// 概念，所以一个被[isExceptionRequest]判定为失败的2xx响应，在本插件看到
  /// 之前就已经被写入缓存了。没有这个引用，重试自己的重新分发会直接读到这条
  /// 被污染的缓存条目而不会真正打到网络，这个失败会一直粘着，直到条目TTL
  /// 过期为止。传入[cache]后，重试前会先把这条被污染的条目清掉。
  final DiomanCache? _cache;

  /// The [DiomanShare] instance installed on the same [Dio], if any. Pass
  /// this whenever [DiomanShare] and [DiomanRetry] are combined —
  /// [DiomanShare] sits BEFORE [DiomanRetry] in the canonical chain, so its
  /// own onResponse/onError would otherwise settle the shared entry with
  /// the FIRST attempt's outcome, before this plugin ever gets a chance to
  /// retry — meaning any concurrent caller dedup'd via [DiomanShare] would
  /// be stuck with a pre-retry failure even if the retry goes on to
  /// succeed. Providing [share] here registers this plugin as the one
  /// responsible for settling the entry instead (see
  /// [DiomanShare.registerDownstreamSettler] / [DiomanShare.settle]) —
  /// [DiomanShare] then defers, and this plugin explicitly settles at every
  /// point it hands off a TRUE final outcome.
  ///
  /// 同一个[Dio]上安装的[DiomanShare]实例（如果有）。[DiomanShare]和
  /// [DiomanRetry]搭配使用时务必传入——[DiomanShare]在canonical链条上排在
  /// [DiomanRetry]前面，它自己的onResponse/onError原本会用第一次尝试的结果
  /// 结算共享entry，本插件还没来得及重试——意味着任何通过[DiomanShare]去重
  /// 的并发调用方，即便重试最终成功了，也只能拿到重试前的失败结果。传入
  /// [share]会把结算责任登记给本插件（见[DiomanShare.registerDownstreamSettler]/
  /// [DiomanShare.settle]）——[DiomanShare]随之推迟结算，本插件在每一个交出
  /// **真正**最终结果的地方显式结算。
  final DiomanShare? _share;

  /// `false` disables the plugin entirely — no request is ever retried.
  ///
  /// `false`时插件整体失效——永不重试任何请求。
  final bool enabled;

  /// Default max retries (0 = no retry unless overridden per request).
  /// Overridable per request via [DiomanRetryOptions.max].
  ///
  /// 默认最大重试次数（0表示不重试，除非单请求覆盖）。可通过
  /// [DiomanRetryOptions.max]按请求覆盖。
  final int max;

  /// Delay before each attempt. Defaults to exponential back-off: 1s, 2s, 4s.
  /// Overridable per request via [DiomanRetryOptions.delay].
  ///
  /// 每次重试前的延迟，默认指数退避：1s、2s、4s。可通过
  /// [DiomanRetryOptions.delay]按请求覆盖。
  final Duration Function(int attempt)? delay;

  /// Decides whether a [DioException] should trigger a network-level retry.
  /// Overridable per request via [DiomanRetryOptions.retryIf].
  ///
  /// 判断某个[DioException]是否该触发网络级重试。可通过
  /// [DiomanRetryOptions.retryIf]按请求覆盖。
  final bool Function(DioException) retryIf;

  /// If provided, a 2xx response for which this returns `true` is treated as
  /// a failure and retried (business-level exception). Overridable per
  /// request via [DiomanRetryOptions.isException].
  ///
  /// 若提供，2xx响应只要它返回`true`就视为失败并重试（业务级异常）。
  /// 可通过[DiomanRetryOptions.isException]按请求覆盖。
  final bool Function(Response<dynamic>)? isExceptionRequest;

  static bool _defaultRetryIf(DioException e) {
    final s = e.response?.statusCode;
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError ||
        (s != null && s >= 500 && s != 501);
  }

  Duration _resolveDelay(Duration Function(int)? $delay, int attempt) =>
      $delay?.call(attempt) ?? Duration(milliseconds: 1000 * (1 << attempt));

  static const _name = 'dioman:retry';
  static const _kCount = '$_name:count';

  // Mirrors the same-named constant in share_plugin.dart — must stay in
  // sync. Marks a re-dispatch as this plugin's own, so DiomanShare's
  // onRequest skips its dedup decision for it (see that constant's doc for
  // why).
  static const _kRetryReentry = 'dioman:retry:reentry';

  @override
  String get name => _name;

  // ── Business-level failure (onResponse) ───────────────────────────────────

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final config = response.requestOptions;
    final override = config.extra[name];
    final o = override is DiomanRetryOptions ? override : null;
    final $enabled = o?.enabled ?? enabled;
    if (!$enabled) return handler.next(response);
    final $isException = o?.isException ?? isExceptionRequest;
    if ($isException == null || !$isException(response)) {
      _settleShare(config, response: response);
      return handler.next(response);
    }

    // Business failure: attempt retry.
    final $max = o?.max ?? max;
    final $delay = o?.delay ?? delay;
    final count = (config.extra[_kCount] as int? ?? 0);
    if (count >= $max) {
      config.extra[_kCount] = 0;
      _settleShare(config, response: response);
      return handler.next(response);
    }
    config.extra[_kCount] = count + 1;
    await Future<void>.delayed(_resolveDelay($delay, count));
    if (config.cancelToken?.isCancelled == true) {
      _settleShare(config, response: response);
      return handler.next(response);
    }
    // This exact business-failure response was just written to the cache
    // (DiomanCache only checks HTTP status, not isExceptionRequest) — evict
    // it so the re-dispatch below actually reaches the network instead of
    // reading its own failure straight back.
    final key = config.extra[kKey] as String?;
    if (_cache != null && key != null) _cache.remove(key);
    config.extra[_kRetryReentry] = true;
    try {
      final retried = await _dio.fetch<dynamic>(config);
      _settleShare(config, response: retried);
      handler.resolve(retried);
    } catch (_) {
      _settleShare(config, response: response);
      handler.next(response);
    }
  }

  // ── HTTP / network failure (onError) ──────────────────────────────────────

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final config = err.requestOptions;
    final override = config.extra[name];
    final o = override is DiomanRetryOptions ? override : null;
    final $enabled = o?.enabled ?? enabled;
    if (!$enabled) return handler.next(err);
    final $retryIf = o?.retryIf ?? retryIf;
    if (!$retryIf(err)) {
      _settleShare(config, error: err);
      return handler.next(err);
    }

    final $max = o?.max ?? max;
    final $delay = o?.delay ?? delay;
    final count = (config.extra[_kCount] as int? ?? 0);
    if (count >= $max) {
      config.extra[_kCount] = 0;
      _settleShare(config, error: err);
      return handler.next(err);
    }
    config.extra[_kCount] = count + 1;
    await Future<void>.delayed(_resolveDelay($delay, count));
    if (config.cancelToken?.isCancelled == true) {
      _settleShare(config, error: err);
      return handler.next(err);
    }
    config.extra[_kRetryReentry] = true;
    try {
      final retried = await _dio.fetch<dynamic>(config);
      _settleShare(config, response: retried);
      handler.resolve(retried);
    } catch (_) {
      _settleShare(config, error: err);
      handler.next(err);
    }
  }

  void _settleShare(
    RequestOptions config, {
    Response<dynamic>? response,
    DioException? error,
  }) {
    if (_share == null) return;
    final key = config.extra[kKey] as String?;
    if (key == null) return;
    _share.settle(key, response: response, error: error);
  }
}
