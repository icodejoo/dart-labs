// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:dio/dio.dart';
import 'cancel_plugin.dart';
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
/// The re-dispatch is issued through a throwaway, interceptor-less `Dio()` —
/// same pattern as [DiomanAuth]'s post-failure replay and [DiomanShare]'s own
/// `policy=retry` re-issues. It never re-enters this chain, so it never
/// re-triggers cache writes, share dedup, mock, cancel/loading brackets, auth
/// injection, or logging for the retry attempt itself. Two consequences to
/// know:
/// - [isExceptionRequest] always sees the RAW response body — [DiomanNormalize]
///   (if used at all) belongs LAST in the chain, after this plugin (see its
///   own class doc), so it never runs before [isExceptionRequest] does.
/// - A response this plugin resolves directly — either a successfully
///   retried one, or a business failure it retried into success — does NOT
///   reach [DiomanCache] or [DiomanNormalize] even when they're installed
///   AFTER this plugin: resolving from inside `onResponse`/`onError` skips
///   every remaining response stage, same as it always has for any
///   interceptor. A plain response this plugin decides NOT to touch
///   (`isExceptionRequest` says no, or `retryIf` says no) is unaffected —
///   it flows on to whatever's next completely normally.
///
/// 重新发起请求走的是一个一次性、不带拦截器的裸`Dio()`——跟[DiomanAuth]失败后
/// 重放、[DiomanShare]自己的`policy=retry`重发用的是同一套模式。它永远不会
/// 重新进入这条链，所以重试这次尝试本身永远不会重新触发缓存写入、share去重、
/// mock、cancel/loading的计数、auth注入，或者日志记录。有两点需要知道：
/// - [isExceptionRequest]看到的永远是**原始**响应体——[DiomanNormalize]
///   （如果用的话）本来就该装在链条最后、排在本插件之后（见它自己的类文档），
///   所以它永远不会跑在[isExceptionRequest]前面。
/// - 本插件直接resolve掉的响应——不管是重试成功的，还是被本插件重试成功
///   的业务失败——即便[DiomanCache]/[DiomanNormalize]装在本插件**之后**，
///   也不会被它们看到：在`onResponse`/`onError`内部resolve会跳过后面所有
///   response阶段，这跟任何拦截器的行为都一致。本插件决定不碰的普通响应
///   （`isExceptionRequest`判否，或`retryIf`判否）不受影响——正常往后流转。
///
/// Per-request configuration via `options.extra['dioman:retry']`:
/// - `const DiomanRetryOptions(max: 1)` → override max retry count
/// - `const DiomanRetryOptions(enabled: false)` → skip retry for this request
///
/// ```dart
/// final retry = DiomanRetry(
///   max: 3,
///   isExceptionRequest: (r) => r.data['code'] != 0,
/// );
/// dio.interceptors.add(retry);
/// ```
class DiomanRetry extends DiomanPlugin {
  DiomanRetry({
    this.max = 0,
    this.delay,
    this.enabled = true,
    this.isExceptionRequest,
    this.onRetry,
    bool Function(DioException)? retryIf,
  }) : retryIf = retryIf ?? _defaultRetryIf;

  // Throwaway Dio reused for re-issues — no interceptors, so retries never
  // re-enter this chain (see the class doc for why). Lazily created and
  // reused across attempts instead of a fresh `Dio()` each time, so the
  // underlying HttpClient / connection pool isn't reallocated per attempt.
  // Closed in [dispose].
  //
  // 复用一个无拦截器的裸Dio做重新发起，避免重新进入本拦截器链（原因见类文档）。
  // 惰性创建并复用（而非每次重试新建一个`Dio()`），避免每次重试都重新分配
  // HttpClient/连接池。在[dispose]中关闭。
  Dio? _retryDio;
  Dio get _retry => _retryDio ??= Dio();

  /// The [DiomanShare] instance installed on the same [Dio], if any. Set
  /// this whenever [DiomanShare] and [DiomanRetry] are combined —
  /// [DiomanShare] sits BEFORE [DiomanRetry] in the canonical chain, so its
  /// own onResponse/onError would otherwise settle the shared entry with
  /// the FIRST attempt's outcome, before this plugin ever gets a chance to
  /// retry — meaning any concurrent caller dedup'd via [DiomanShare] would
  /// be stuck with a pre-retry failure even if the retry goes on to
  /// succeed. Setting [share] registers this plugin as the one responsible
  /// for settling the entry instead (see
  /// [DiomanShare.registerDownstreamSettler] / [DiomanShare.settle]) —
  /// [DiomanShare] then defers, and this plugin explicitly settles at every
  /// point it hands off a TRUE final outcome.
  ///
  /// [Dioman.install] wires this automatically when both a `share:` and a
  /// `retry:` plugin are passed to it — set it by hand only when wiring the
  /// chain yourself instead of going through `install`.
  ///
  /// 同一个[Dio]上安装的[DiomanShare]实例（如果有）。[DiomanShare]和
  /// [DiomanRetry]搭配使用时务必设置——[DiomanShare]在canonical链条上排在
  /// [DiomanRetry]前面，它自己的onResponse/onError原本会用第一次尝试的结果
  /// 结算共享entry，本插件还没来得及重试——意味着任何通过[DiomanShare]去重
  /// 的并发调用方，即便重试最终成功了，也只能拿到重试前的失败结果。设置
  /// [share]会把结算责任登记给本插件（见[DiomanShare.registerDownstreamSettler]/
  /// [DiomanShare.settle]）——[DiomanShare]随之推迟结算，本插件在每一个交出
  /// **真正**最终结果的地方显式结算。
  ///
  /// [Dioman.install]同时收到`share:`和`retry:`时会自动完成这层接线——只有
  /// 自己手动拼接拦截器链（不走`install`）时才需要手动设置。
  DiomanShare? _share;

  set share(DiomanShare? value) {
    _share = value;
    value?.registerDownstreamSettler();
  }

  /// The [DiomanCancel] instance installed on the same [Dio], if any. Set
  /// this whenever [DiomanCancel] and [DiomanRetry] are combined — the retry
  /// re-issue goes through a throwaway Dio with no interceptors, so it never
  /// re-enters [DiomanCancel]'s onRequest (which is what would otherwise
  /// re-register the token). Without this reference, `cancelAll()` can't
  /// abort a request currently being retried.
  ///
  /// [Dioman.install] wires this automatically when both a `cancel:` and a
  /// `retry:` plugin are passed to it.
  ///
  /// 同一个[Dio]上安装的[DiomanCancel]实例（如果有）。[DiomanCancel]和
  /// [DiomanRetry]搭配使用时务必设置——重试的重新发起走的是不带拦截器的裸
  /// Dio，永远不会重新进入[DiomanCancel]的onRequest（那本该是重新登记token
  /// 的地方）。没有这个引用，`cancelAll()`中断不了正在重试中的请求。
  ///
  /// [Dioman.install]同时收到`cancel:`和`retry:`时会自动完成这层接线。
  DiomanCancel? _cancel;

  set cancel(DiomanCancel? value) => _cancel = value;

  /// Called right before each retry attempt is actually issued, with the
  /// 1-based attempt number. Purely observational — e.g. wire it to your own
  /// logger to record how many retries happened, without needing the retry
  /// re-issue itself to pass through [DiomanLog].
  ///
  /// 每次真正发起重试之前调用，参数是从1开始的尝试序号。纯观察性——比如接到
  /// 你自己的日志器上记录发生了几次重试，而不需要让重试的重新发起本身
  /// 经过[DiomanLog]。
  final void Function(int attempt)? onRetry;

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

    // Business failure: retry up to $max times. Unlike the old same-dio
    // design (where each re-dispatch recursed back through this same
    // onResponse via the full chain), the re-issue is a bare Dio with no
    // interceptors — so the whole retry loop has to live in THIS one
    // invocation, explicitly re-checking $isException after every attempt.
    final $max = o?.max ?? max;
    final $delay = o?.delay ?? delay;
    var current = response;
    for (var attempt = 0; attempt < $max; attempt++) {
      if (config.cancelToken?.isCancelled == true) break;
      await Future<void>.delayed(_resolveDelay($delay, attempt));
      onRetry?.call(attempt + 1);
      try {
        current = await _reissue(config);
      } catch (_) {
        // The re-issue failed outright (network/HTTP level) rather than
        // landing another business failure — give up, propagate the
        // original business failure rather than a transport error the
        // caller never asked about.
        break;
      }
      if (!$isException(current)) {
        _settleShare(config, response: current);
        return handler.resolve(current);
      }
    }
    _settleShare(config, response: current);
    handler.next(current);
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

    // Retry up to $max times, same reasoning as onResponse above: the whole
    // loop lives in this one invocation, explicitly re-checking $retryIf
    // against every subsequent failure (a re-issue can fail with a
    // DIFFERENT, non-retryable error — that stops the loop early, matching
    // what a fresh onError call would have decided under the old design).
    final $max = o?.max ?? max;
    final $delay = o?.delay ?? delay;
    var lastError = err;
    for (var attempt = 0; attempt < $max; attempt++) {
      if (config.cancelToken?.isCancelled == true) break;
      await Future<void>.delayed(_resolveDelay($delay, attempt));
      onRetry?.call(attempt + 1);
      try {
        final retried = await _reissue(config);
        _settleShare(config, response: retried);
        return handler.resolve(retried);
      } catch (e) {
        lastError =
            e is DioException ? e : DioException(requestOptions: config, error: e);
        if (!$retryIf(lastError)) break;
      }
    }
    _settleShare(config, error: lastError);
    handler.next(lastError);
  }

  /// Issues the retry via [_retry], tracking [config]'s cancel token with
  /// [_cancel] for the duration so `cancelAll()` can see (and abort) it —
  /// see [_cancel]'s doc for why that tracking doesn't happen on its own.
  Future<Response<dynamic>> _reissue(RequestOptions config) async {
    final token = config.cancelToken;
    if (token != null) _cancel?.track(token);
    try {
      return await _retry.fetch<dynamic>(config);
    } finally {
      if (token != null) _cancel?.untrack(token);
    }
  }

  void _settleShare(
    RequestOptions config, {
    Response<dynamic>? response,
    DioException? error,
  }) {
    final share = _share;
    if (share == null) return;
    final key = config.extra[kKey] as String?;
    if (key == null) return;
    share.settle(key, response: response, error: error);
  }

  @override
  void dispose() {
    _retryDio?.close(force: true);
    _retryDio = null;
  }
}
