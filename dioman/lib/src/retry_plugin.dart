// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'cancel_plugin.dart';
import 'dioman_plugin.dart';
import 'key_plugin.dart';
import 'share_plugin.dart';

/// The `jitter` field's function form: takes the raw computed delay, returns
/// the jittered delay. Pass `true` instead for uniform-random jitter in
/// `[Duration.zero, delay)`.
///
/// `jitter`字段的函数形式：接收原始算出来的delay，返回抖动后的delay。传
/// `true`则在`[Duration.zero, delay)`内均匀随机抖动。
typedef DiomanJitter = Duration Function(Duration delay);

/// The `delay` field's function form: `(current attempt, max, response?,
/// err?) → wait duration`. `current` is 1-based.
///
/// `delay`字段的函数形式：`(当前次数, 最大次数, 响应?, 错误?) → 等待时长`。
/// `current`从1开始。
typedef DiomanRetryDelay = Duration Function(
  int current,
  int max,
  Response<dynamic>? response,
  DioException? err,
);

/// The `shouldRetry` field's shape: an exact `true`/`false` decides outright;
/// `null` (no decision) falls through to `statusCodes`.
///
/// `shouldRetry`字段的形状：返回明确的`true`/`false`直接采用；返回`null`
/// （没给出判断）退回`statusCodes`表。
typedef DiomanShouldRetry = bool? Function(
  DioException? err,
  Response<dynamic>? response,
);

/// Per-request override for [DiomanRetry], read from `extra['dioman:retry']`.
/// Any field left `null` falls back to the plugin-level default of the same
/// name.
///
/// Besides this full object form, `extra['dioman:retry']` also accepts:
/// - `int` → overrides [DiomanRetry.max] only
/// - `false` → disables retry for this request (highest-priority veto,
///   equivalent to `DiomanRetryOptions(enabled: false)`)
/// - `true` (or omitted) → no override, respects every plugin-level default
///
/// [DiomanRetry]的单请求覆盖，从`extra['dioman:retry']`读取。留`null`的字段
/// 各自回退到插件级同名默认值。
///
/// 除了这种完整对象形式，`extra['dioman:retry']`还接受：
/// - `int` → 只覆盖[DiomanRetry.max]
/// - `false` → 本次请求禁用重试（最高优先级否决，等价于
///   `DiomanRetryOptions(enabled: false)`）
/// - `true`（或不设置）→ 不覆盖，尊重插件级所有默认值
class DiomanRetryOptions {
  const DiomanRetryOptions({
    this.enabled,
    this.max,
    this.methods,
    this.shouldRetry,
    this.statusCodes,
    this.delay,
    this.jitter,
    this.delayMax,
    this.respectRetryAfter,
    this.afterStatusCodes,
    this.retryAfterMax,
  });

  /// `false` skips retry for this request. `null` (default) inherits
  /// [DiomanRetry.enabled].
  ///
  /// `false`表示本次请求跳过重试。`null`（默认）沿用[DiomanRetry.enabled]。
  final bool? enabled;

  /// Overrides the plugin's default max retry count for this request only.
  ///
  /// 仅本次请求覆盖插件默认的最大重试次数。
  final int? max;

  /// Overrides the plugin's default method whitelist for this request only.
  ///
  /// 仅本次请求覆盖插件默认的方法白名单。
  final List<String>? methods;

  /// Overrides the plugin's default retry decision for this request only.
  /// See [DiomanRetry.shouldRetry] for the call convention (`err`/`response`
  /// on each path).
  ///
  /// 仅本次请求覆盖插件默认的重试判定函数。调用约定（各路径下`err`/
  /// `response`如何传入）见[DiomanRetry.shouldRetry]。
  final DiomanShouldRetry? shouldRetry;

  /// Overrides the plugin's default status-code table for this request only.
  ///
  /// 仅本次请求覆盖插件默认的状态码表。
  final List<int>? statusCodes;

  /// Overrides the plugin's default back-off `delay` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的退避延迟函数`delay`。
  final DiomanRetryDelay? delay;

  /// Overrides the plugin's default `jitter` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`jitter`。
  final Object? jitter;

  /// Overrides the plugin's default `delayMax` cap for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`delayMax`封顶值。
  final Duration? delayMax;

  /// Overrides the plugin's default `respectRetryAfter` for this request
  /// only.
  ///
  /// 仅本次请求覆盖插件默认的`respectRetryAfter`。
  final bool? respectRetryAfter;

  /// Overrides the plugin's default `afterStatusCodes` for this request
  /// only.
  ///
  /// 仅本次请求覆盖插件默认的`afterStatusCodes`。
  final List<int>? afterStatusCodes;

  /// Overrides the plugin's default `retryAfterMax` cap for this request
  /// only.
  ///
  /// 仅本次请求覆盖插件默认的`retryAfterMax`封顶值。
  final Duration? retryAfterMax;
}

const _defaultMethods = ['GET', 'PUT', 'HEAD', 'DELETE', 'OPTIONS', 'TRACE'];
const _defaultStatusCodes = [408, 429, 500, 502, 503, 504];
const _defaultAfterStatusCodes = [413, 429, 503];
const _defaultDelay = Duration(milliseconds: 3000);
// Sentinel "uncapped" value — Duration has no infinite constant.
const _uncapped = Duration(days: 36500);

final _random = Random();

/// Retries failed requests with configurable back-off.
///
/// 按可配置的退避策略重试失败的请求。
///
/// Supports two failure modes through a single [shouldRetry] decision
/// function:
/// - **HTTP / network errors** (`onError` path) — called as `shouldRetry(err,
///   err.response)`.
/// - **Business-level errors** (`onResponse` path) — called as
///   `shouldRetry(null, response)`, to treat a 200 response as a failure
///   based on the response body (e.g. `code != 0`).
///
/// [shouldRetry] has no built-in default: an exact `true`/`false` it returns
/// wins outright; `null` (including when [shouldRetry] itself isn't set)
/// falls through to [statusCodes] (default `[408,429,500,502,503,504]`), and
/// — only when there's no HTTP status at all (a pure network failure) —
/// further falls back to retrying known transient [DioExceptionType]s
/// (`connectionTimeout`/`receiveTimeout`/`sendTimeout`/`connectionError`).
/// [methods] is checked FIRST and is a hard veto [shouldRetry] cannot
/// override (default idempotent verbs, excluding post/patch).
///
/// 通过统一的[shouldRetry]判定函数支持两种失败模式：
/// - **HTTP/网络错误**（`onError`路径）——以`shouldRetry(err, err.response)`调用。
/// - **业务级错误**（`onResponse`路径）——以`shouldRetry(null, response)`调用，
///   根据响应body把一个200响应视为失败（比如`code != 0`）。
///
/// [shouldRetry]不设默认值：返回明确的`true`/`false`直接采用；返回`null`
/// （包括没设置[shouldRetry]）退回[statusCodes]（默认
/// `[408,429,500,502,503,504]`）——只有在完全没有HTTP状态码时（纯网络失败），
/// 才进一步退回按已知的瞬时性[DioExceptionType]判定
/// （`connectionTimeout`/`receiveTimeout`/`sendTimeout`/`connectionError`）。
/// [methods]最先检查，是[shouldRetry]无法覆盖的硬性否决（默认幂等动词，
/// 不含post/patch）。
///
/// The re-dispatch is issued through a throwaway, interceptor-less `Dio()` —
/// same pattern as [DiomanAuth]'s post-failure replay and [DiomanShare]'s own
/// `policy=retry` re-issues. It never re-enters this chain, so it never
/// re-triggers cache writes, share dedup, mock, cancel/loading brackets, auth
/// injection, or logging for the retry attempt itself. Two consequences to
/// know:
/// - [shouldRetry] always sees the RAW response body — [DiomanNormalize]
///   (if used at all) belongs LAST in the chain, after this plugin (see its
///   own class doc), so it never runs before [shouldRetry] does.
/// - A response this plugin resolves directly — either a successfully
///   retried one, or a business failure it retried into success — does NOT
///   reach [DiomanCache] or [DiomanNormalize] even when they're installed
///   AFTER this plugin: resolving from inside `onResponse`/`onError` skips
///   every remaining response stage, same as it always has for any
///   interceptor. A plain response this plugin decides NOT to touch
///   (`shouldRetry` says no) is unaffected — it flows on to whatever's next
///   completely normally.
///
/// While waiting out a `delay`, the wait races [RequestOptions.cancelToken]'s
/// `whenCancel` — cancelling mid-wait stops it immediately instead of idling
/// until the timer fires only to discover the request was already canceled.
/// A response's `Retry-After` header (seconds, or an RFC 1123 HTTP-date)
/// wins over the computed `delay`, but only when its status is covered by
/// [afterStatusCodes] (default `[413,429,503]`) and [respectRetryAfter] is
/// true; the result is capped by [retryAfterMax] and skips [jitter]/
/// [delayMax] (those only apply to this plugin's own computed delay).
///
/// 等待`delay`期间，等待会跟[RequestOptions.cancelToken]的`whenCancel`赛跑——
/// 中途取消会立刻停止等待，不会空等到定时器触发才发现请求已经被取消。响应带
/// `Retry-After`头（数字秒或RFC 1123格式的HTTP-date）时，只要状态码落在
/// [afterStatusCodes]内（默认`[413,429,503]`）且[respectRetryAfter]为true，
/// 就优先听它而不算`delay`；换算出的等待由[retryAfterMax]封顶，且不叠加
/// [jitter]/[delayMax]（这两个只管本插件自己算出来的delay）。
///
/// Per-request configuration via `options.extra['dioman:retry']` — see
/// [DiomanRetryOptions] for the full `int`/`bool`/object shape.
///
/// ```dart
/// final retry = DiomanRetry(
///   max: 3,
///   shouldRetry: (err, response) => response?.data['code'] != 0,
///   jitter: true,
///   delayMax: Duration(seconds: 10),
/// );
/// dio.interceptors.add(retry);
/// ```
class DiomanRetry extends DiomanPlugin {
  DiomanRetry({
    this.max = 0,
    this.methods,
    this.shouldRetry,
    this.statusCodes,
    this.delay,
    this.jitter,
    this.delayMax,
    this.enabled = true,
    this.respectRetryAfter = true,
    this.afterStatusCodes,
    this.retryAfterMax,
    this.onRetry,
  });

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

  /// Whitelist of methods eligible for retry (case-insensitive) — a hard
  /// veto [shouldRetry] cannot override. Defaults to idempotent verbs,
  /// excluding post/patch: `[GET,PUT,HEAD,DELETE,OPTIONS,TRACE]`.
  /// Overridable per request via [DiomanRetryOptions.methods].
  ///
  /// 允许重试的方法白名单（不区分大小写）——[shouldRetry]说了也不算的硬性
  /// 否决。默认幂等动词，不含post/patch：`[GET,PUT,HEAD,DELETE,OPTIONS,TRACE]`。
  /// 可通过[DiomanRetryOptions.methods]按请求覆盖。
  final List<String>? methods;

  /// Decides whether a failure should be retried. Called as
  /// `shouldRetry(null, response)` on the `onResponse` path (business-level
  /// check against a 2xx response) and as `shouldRetry(err, err.response)`
  /// on the `onError` path (HTTP / network-level check). An exact
  /// `true`/`false` wins outright; `null` falls through to [statusCodes].
  /// Overridable per request via [DiomanRetryOptions.shouldRetry].
  ///
  /// 判断某次失败是否该重试。`onResponse`路径下以`shouldRetry(null, response)`
  /// 调用（针对2xx响应的业务级判定），`onError`路径下以
  /// `shouldRetry(err, err.response)`调用（HTTP/网络级判定）。返回明确的
  /// `true`/`false`直接采用；返回`null`退回[statusCodes]。可通过
  /// [DiomanRetryOptions.shouldRetry]按请求覆盖。
  final DiomanShouldRetry? shouldRetry;

  /// Status codes used when [shouldRetry] doesn't give an exact result.
  /// Defaults to `[408,429,500,502,503,504]`. Overridable per request via
  /// [DiomanRetryOptions.statusCodes].
  ///
  /// [shouldRetry]未给出明确结果时用的状态码表。默认
  /// `[408,429,500,502,503,504]`。可通过[DiomanRetryOptions.statusCodes]按
  /// 请求覆盖。
  final List<int>? statusCodes;

  /// Wait duration before a retry, defaults to a flat 3000ms. Overridable
  /// per request via [DiomanRetryOptions.delay].
  ///
  /// 重试前的等待时长，默认固定3000ms。可通过[DiomanRetryOptions.delay]按
  /// 请求覆盖。
  final DiomanRetryDelay? delay;

  /// Jitter strategy applied to [delay]: `true` for uniform-random jitter in
  /// `[Duration.zero, delay)`, or a [DiomanJitter] function to compute it
  /// yourself. No jitter by default. Never applies to a `Retry-After`-derived
  /// wait. Overridable per request via [DiomanRetryOptions.jitter].
  ///
  /// 给[delay]加抖动的策略：`true`在`[Duration.zero, delay)`内均匀随机，或
  /// 传[DiomanJitter]函数自己算。默认不抖动。从不作用于`Retry-After`换算出的
  /// 等待。可通过[DiomanRetryOptions.jitter]按请求覆盖。
  final Object? jitter;

  /// Cap on [delay] (after jitter), uncapped by default. Never applies to a
  /// `Retry-After`-derived wait. Overridable per request via
  /// [DiomanRetryOptions.delayMax].
  ///
  /// [delay]（含抖动后）的封顶值，默认不封顶。从不作用于`Retry-After`换算出
  /// 的等待。可通过[DiomanRetryOptions.delayMax]按请求覆盖。
  final Duration? delayMax;

  /// Whether to respect a response's `Retry-After` header (seconds or an
  /// RFC 1123 HTTP-date), defaults to true. Overridable per request via
  /// [DiomanRetryOptions.respectRetryAfter].
  ///
  /// 是否尊重响应的`Retry-After`头（数字秒或RFC 1123格式的HTTP-date），默认
  /// true。可通过[DiomanRetryOptions.respectRetryAfter]按请求覆盖。
  final bool respectRetryAfter;

  /// Only trusts the `Retry-After` header for these statuses (others ignore
  /// it even if present, falling back to the computed [delay]). Defaults to
  /// `[413,429,503]`. Overridable per request via
  /// [DiomanRetryOptions.afterStatusCodes].
  ///
  /// 只在这些状态码上信`Retry-After`头（其它状态码即使带了也不认，照样走
  /// 计算出的[delay]）。默认`[413,429,503]`。可通过
  /// [DiomanRetryOptions.afterStatusCodes]按请求覆盖。
  final List<int>? afterStatusCodes;

  /// Cap on a `Retry-After`-derived wait, uncapped by default. Overridable
  /// per request via [DiomanRetryOptions.retryAfterMax].
  ///
  /// `Retry-After`换算出的等待上限，默认不封顶。可通过
  /// [DiomanRetryOptions.retryAfterMax]按请求覆盖。
  final Duration? retryAfterMax;

  static const _name = 'dioman:retry';

  @override
  String get name => _name;

  // ── Per-request override resolution ───────────────────────────────────────

  Object? _override(RequestOptions config) => config.extra[name];

  DiomanRetryOptions? _overrideObject(RequestOptions config) {
    final v = _override(config);
    return v is DiomanRetryOptions ? v : null;
  }

  bool _isDisabled(RequestOptions config) {
    final v = _override(config);
    if (v == false) return true;
    final o = _overrideObject(config);
    return !(o?.enabled ?? enabled);
  }

  int _resolveMax(RequestOptions config) {
    final v = _override(config);
    if (v is int) return v;
    return _overrideObject(config)?.max ?? max;
  }

  List<String> _resolveMethods(RequestOptions config) =>
      _overrideObject(config)?.methods ?? methods ?? _defaultMethods;

  DiomanShouldRetry? _resolveShouldRetry(RequestOptions config) =>
      _overrideObject(config)?.shouldRetry ?? shouldRetry;

  List<int> _resolveStatusCodes(RequestOptions config) =>
      _overrideObject(config)?.statusCodes ?? statusCodes ?? _defaultStatusCodes;

  List<int> _resolveAfterStatusCodes(RequestOptions config) =>
      _overrideObject(config)?.afterStatusCodes ??
      afterStatusCodes ??
      _defaultAfterStatusCodes;

  DiomanRetryDelay _resolveDelay(RequestOptions config) =>
      _overrideObject(config)?.delay ?? delay ?? ((_, __, ___, ____) => _defaultDelay);

  Object? _resolveJitter(RequestOptions config) =>
      _overrideObject(config)?.jitter ?? jitter;

  Duration _resolveDelayMax(RequestOptions config) =>
      _overrideObject(config)?.delayMax ?? delayMax ?? _uncapped;

  bool _resolveRespectRetryAfter(RequestOptions config) =>
      _overrideObject(config)?.respectRetryAfter ?? respectRetryAfter;

  Duration _resolveRetryAfterMax(RequestOptions config) =>
      _overrideObject(config)?.retryAfterMax ?? retryAfterMax ?? _uncapped;

  // ── Retry decision ─────────────────────────────────────────────────────────

  /// Priority, each level can veto early: (1) a per-request disable; (2) the
  /// [methods] whitelist; (3) `shouldRetry?.(err, response) ??
  /// statusCodes.includes(status) ?? (timeout/connection-error type)`.
  ///
  /// 优先级从高到低、每一级都能提前否决：（1）单请求禁用；（2）[methods]白
  /// 名单；（3）`shouldRetry?.(err, response) ??
  /// statusCodes.includes(status) ?? (超时/连接错误类型)`。
  bool _shouldRetry(
    RequestOptions config,
    DioException? err,
    Response<dynamic>? response,
  ) {
    if (_isDisabled(config)) return false;
    final method = config.method.toUpperCase();
    if (!_resolveMethods(config).map((m) => m.toUpperCase()).contains(method)) {
      return false;
    }
    final custom = _resolveShouldRetry(config)?.call(err, response);
    if (custom != null) return custom;
    final status = response?.statusCode ?? err?.response?.statusCode;
    if (status != null) return _resolveStatusCodes(config).contains(status);
    final t = err?.type;
    return t == DioExceptionType.connectionTimeout ||
        t == DioExceptionType.receiveTimeout ||
        t == DioExceptionType.sendTimeout ||
        t == DioExceptionType.connectionError;
  }

  Duration _capped(Duration d, Duration cap) {
    if (d.isNegative) return Duration.zero;
    return d > cap ? cap : d;
  }

  Duration _applyJitter(Duration raw, Object? jitter, Duration cap) {
    var jittered = raw;
    if (jitter == true) {
      jittered = Duration(
        microseconds: (raw.inMicroseconds * _random.nextDouble()).round(),
      );
    } else if (jitter is DiomanJitter) {
      final r = jitter(raw);
      jittered = r.isNegative ? raw : r;
    }
    return _capped(jittered, cap);
  }

  static final _httpDate =
      RegExp(r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$');
  static const _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  /// Parses an RFC 1123 HTTP-date (e.g. `Wed, 21 Oct 2026 07:28:00 GMT`) —
  /// `DateTime.parse` doesn't understand this format. Mirrors axp's
  /// `Retry-After` support; doesn't replicate legacy RFC 850/asctime
  /// fallbacks (too narrow a use case here).
  ///
  /// 解析RFC 1123格式的HTTP-date（如`Wed, 21 Oct 2026 07:28:00 GMT`）——
  /// `DateTime.parse`不认这种格式。对齐axp的`Retry-After`支持，不复刻过时的
  /// RFC 850/asctime兜底（场景太窄）。
  static DateTime? _parseHttpDate(String raw) {
    final m = _httpDate.firstMatch(raw.trim());
    if (m == null) return null;
    final month = _months[m.group(2)];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }

  Duration? _retryAfter(Response<dynamic>? response, Duration cap) {
    final raw = response?.headers.value('retry-after');
    if (raw == null) return null;
    final seconds = num.tryParse(raw);
    if (seconds != null) {
      return _capped(
        Duration(milliseconds: (seconds * 1000).round()),
        cap,
      );
    }
    final date = _parseHttpDate(raw);
    if (date == null) return null;
    return _capped(date.difference(DateTime.now().toUtc()), cap);
  }

  /// Resolves the actual wait before the given attempt — a `Retry-After`
  /// header wins over the computed `delay` when eligible (see the class
  /// doc), otherwise the computed `delay` with jitter/delayMax applied.
  ///
  /// 算出某次尝试前实际要等的时长——符合条件时`Retry-After`头优先于算出来
  /// 的`delay`（见类文档），否则用算出来的`delay`叠加jitter/delayMax。
  Duration _resolveWait(
    RequestOptions config,
    int current,
    int max,
    Response<dynamic>? response,
    DioException? err,
  ) {
    final respStatus = response?.statusCode ?? err?.response?.statusCode;
    final headerEligible = _resolveRespectRetryAfter(config) &&
        respStatus != null &&
        _resolveAfterStatusCodes(config).contains(respStatus);
    final fromHeader = headerEligible
        ? _retryAfter(response ?? err?.response, _resolveRetryAfterMax(config))
        : null;
    if (fromHeader != null) return fromHeader;
    final raw = _resolveDelay(config)(current, max, response, err);
    return _applyJitter(raw, _resolveJitter(config), _resolveDelayMax(config));
  }

  /// Cancel-aware wait: races the delay against
  /// [RequestOptions.cancelToken]'s `whenCancel` so a cancel mid-wait stops
  /// it immediately instead of idling until the timer fires.
  ///
  /// 可取消的等待：跟[RequestOptions.cancelToken]的`whenCancel`赛跑，中途
  /// 取消会立刻停止等待，不会空等到定时器触发。
  Future<void> _delay(Duration wait, CancelToken? token) async {
    if (wait <= Duration.zero) return;
    if (token?.isCancelled == true) return;
    if (token == null) {
      await Future<void>.delayed(wait);
      return;
    }
    await Future.any<void>([
      Future<void>.delayed(wait),
      token.whenCancel.then((_) {}),
    ]);
  }

  // ── Business-level failure (onResponse) ───────────────────────────────────

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final config = response.requestOptions;
    if (!_shouldRetry(config, null, response)) {
      _settleShare(config, response: response);
      return handler.next(response);
    }

    // Business failure: retry up to $max times. Unlike the old same-dio
    // design (where each re-dispatch recursed back through this same
    // onResponse via the full chain), the re-issue is a bare Dio with no
    // interceptors — so the whole retry loop has to live in THIS one
    // invocation, explicitly re-checking $shouldRetry after every attempt.
    final $max = _resolveMax(config);
    var current = response;
    for (var attempt = 1; attempt <= $max; attempt++) {
      if (config.cancelToken?.isCancelled == true) break;
      final wait = _resolveWait(config, attempt, $max, current, null);
      await _delay(wait, config.cancelToken);
      if (config.cancelToken?.isCancelled == true) break;
      onRetry?.call(attempt);
      try {
        current = await _reissue(config);
      } catch (_) {
        // The re-issue failed outright (network/HTTP level) rather than
        // landing another business failure — give up, propagate the
        // original business failure rather than a transport error the
        // caller never asked about.
        break;
      }
      if (!_shouldRetry(config, null, current)) {
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
    if (!_shouldRetry(config, err, err.response)) {
      _settleShare(config, error: err);
      return handler.next(err);
    }

    // Retry up to $max times, same reasoning as onResponse above: the whole
    // loop lives in this one invocation, explicitly re-checking $shouldRetry
    // against every subsequent failure (a re-issue can fail with a
    // DIFFERENT, non-retryable error — that stops the loop early, matching
    // what a fresh onError call would have decided under the old design).
    final $max = _resolveMax(config);
    var lastError = err;
    for (var attempt = 1; attempt <= $max; attempt++) {
      if (config.cancelToken?.isCancelled == true) break;
      final wait = _resolveWait(config, attempt, $max, lastError.response, lastError);
      await _delay(wait, config.cancelToken);
      if (config.cancelToken?.isCancelled == true) break;
      onRetry?.call(attempt);
      try {
        final retried = await _reissue(config);
        _settleShare(config, response: retried);
        return handler.resolve(retried);
      } catch (e) {
        lastError =
            e is DioException ? e : DioException(requestOptions: config, error: e);
        if (!_shouldRetry(config, lastError, lastError.response)) break;
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
