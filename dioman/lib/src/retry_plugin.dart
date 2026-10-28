// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'breaker_plugin.dart';
import 'cancel_plugin.dart';
import 'dioman_plugin.dart';
import 'replay_support.dart';
import 'request_claims.dart';
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
/// The re-dispatch is issued through an interceptor-less `Dio` that borrows
/// the host client's `httpClientAdapter`/`transformer` (bound by
/// [Dioman.install] via [dio]; a bare `Dio()` otherwise) — same pattern as
/// [DiomanAuth]'s post-failure replay and [DiomanShare]'s own `policy=retry`
/// re-issues. It never re-enters this chain, so it never re-triggers cache
/// writes, share dedup, mock, cancel/loading brackets, auth injection, or
/// logging for the retry attempt itself. Consequences to know:
/// - [shouldRetry] always sees the RAW response body — [DiomanNormalize]
///   (if used at all) belongs LAST in the chain, after this plugin (see its
///   own class doc), so it never runs before [shouldRetry] does.
/// - A recovered result is handed to the interceptors installed AFTER this
///   plugin (breaker, log, normalize, ...) exactly like a first-time success,
///   so it is normalized the same way. Interceptors installed BEFORE it
///   (cache, ...) are not re-run for it.
/// - A request body that cannot be re-sent (a `Stream`, or a consumed
///   multipart file stream) is never retried; a `FormData` is cloned per
///   attempt.
/// - For [DiomanShare] / [DiomanCancel], this plugin registers itself on the
///   request in onRequest and hands off only when the request's true final
///   outcome is known, so shared callers never see a pre-retry result and
///   `cancelAll()` covers the whole logical request, including back-off waits.
///
/// 重新发起走一个不带拦截器、借用宿主客户端`httpClientAdapter`/`transformer`的
/// `Dio`（由[Dioman.install]通过[dio]绑定；未绑定则是裸`Dio()`）——跟[DiomanAuth]
/// 的失败后重放、[DiomanShare]自己的`policy=retry`重新发起是同一套做法。它永远
/// 不会重新进入本拦截器链，所以重试本身不会重新触发缓存写入、share去重、mock、
/// cancel/loading括号、鉴权注入或日志。需要知道的几点：
/// - [shouldRetry]看到的永远是**原始**响应体——[DiomanNormalize]（如果用的话）
///   应当装在链条**最后**、本插件之后（见它自己的类文档），所以它不会先于
///   [shouldRetry]运行。
/// - 恢复成功的结果会交给装在本插件**之后**的拦截器（breaker、log、normalize…）
///   处理，语义跟首次成功一致，所以同样会被规范化；装在它**之前**的拦截器
///   （cache等）不会为它重新运行。
/// - 无法重发的请求体（`Stream`，或文件流已消费的multipart）永远不重试；
///   `FormData`每次尝试前克隆。
/// - 对[DiomanShare]/[DiomanCancel]，本插件在onRequest里把自己登记到请求上，
///   只在请求的真正最终结果确定后才交接，因此共享调用方不会看到重试前的结果，
///   `cancelAll()`覆盖整个逻辑请求，包括退避等待期间。
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

  // 重试用的传输层：绑定宿主 Dio 后借用其 adapter/transformer，未绑定时退回
  // 无拦截器的裸 Dio，重试不会重新进入本拦截器链（原因见类文档）。在 [dispose]
  // 中释放。
  final _replay = ReplayClient();

  /// Binds the host [Dio] this plugin is installed on, so retries reuse its
  /// adapter/transformer and a recovered result reaches the interceptors after
  /// this plugin. [Dioman.install] / [DiomanHandle] bind it automatically; set
  /// it by hand only when wiring the chain yourself. `null` unbinds.
  ///
  /// 绑定本插件所在的宿主[Dio]，让重试复用它的adapter/transformer，并让恢复成功
  /// 的结果进入排在本插件之后的拦截器。[Dioman.install]/[DiomanHandle]会自动
  /// 绑定，只有自己手动拼链时才需要设置。传`null`解绑。
  set dio(Dio? value) => _replay.bind(value);

  /// No longer needed: this plugin now registers its settlement
  /// responsibility on each request itself. Kept as a no-op for compatibility.
  ///
  /// 已不再需要：本插件现在自己在每个请求上登记结算责任。仅作兼容保留，无效果。
  @Deprecated('Settlement responsibility is registered per request now; '
      'this setter has no effect.')
  set share(DiomanShare? value) {}

  /// No longer needed: [DiomanCancel] now keeps tracking a request for as long
  /// as this plugin still holds it (back-off, replay). Kept as a no-op for
  /// compatibility.
  ///
  /// 已不再需要：只要本插件还持有请求（退避、重放期间），[DiomanCancel]就会
  /// 持续追踪它。仅作兼容保留，无效果。
  @Deprecated('Cancel tracking now covers the whole logical request; '
      'this setter has no effect.')
  set cancel(DiomanCancel? value) {}

  /// The [DiomanBreaker] instance installed on the same [Dio], if any. Set
  /// this whenever [DiomanBreaker] and [DiomanRetry] are combined — before
  /// each re-issue this plugin checks [DiomanBreaker.isOpen], so a request
  /// still looping through its retries stops the instant the breaker trips
  /// from OTHER requests, instead of piling more attempts onto a server that
  /// just went down. Without it, retries run to exhaustion regardless of the
  /// breaker's state.
  ///
  /// [Dioman.install] wires this automatically when both a `breaker:` and a
  /// `retry:` plugin are passed to it — set it by hand only when wiring the
  /// chain yourself instead of going through `install`.
  ///
  /// 同一个[Dio]上安装的[DiomanBreaker]实例（如果有）。[DiomanBreaker]和
  /// [DiomanRetry]搭配使用时设置它——本插件在每次重发前检查
  /// [DiomanBreaker.isOpen]，于是正在重试循环中的请求，会在熔断器因**其它**
  /// 请求触发的那一刻立即停止，而不是继续往刚挂掉的服务器上堆重试。不设置时，
  /// 无论熔断器状态如何，重试都会跑到耗尽为止。
  ///
  /// [Dioman.install]同时收到`breaker:`和`retry:`时会自动完成这层接线——只有
  /// 自己手动拼接拦截器链（不走`install`）时才需要手动设置。
  DiomanBreaker? _breaker;

  set breaker(DiomanBreaker? value) => _breaker = value;

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

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:retry';

  /// extra 键：本请求的某个用户回调（shouldRetry/delay 等）在响应阶段抛过异常，
  /// 错误阶段据此不再重复调用回调。
  static const _kCallbackFailed = '$pluginName:callbackFailed';

  @override
  String get name => pluginName;

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
      _overrideObject(config)?.statusCodes ??
      statusCodes ??
      _defaultStatusCodes;

  List<int> _resolveAfterStatusCodes(RequestOptions config) =>
      _overrideObject(config)?.afterStatusCodes ??
      afterStatusCodes ??
      _defaultAfterStatusCodes;

  DiomanRetryDelay _resolveDelay(RequestOptions config) =>
      _overrideObject(config)?.delay ??
      delay ??
      ((_, __, ___, ____) => _defaultDelay);

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
    // 取消是调用方的明确意图，永不重试。
    if (err?.type == DioExceptionType.cancel) return false;
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
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
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

  // ── Claim (onRequest) ─────────────────────────────────────────────────────

  /// 这次请求有机会被本插件重试时（未禁用、方法在白名单、最大次数>0），把结算
  /// 责任登记到请求上：下游的 share 因此等到最终结果才结算，cancel 因此在整个
  /// 逻辑请求（含退避等待）期间持续追踪 token。每条出口都会注销，见
  /// [_handleResponse]/[_handleError]。
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_mayRetry(options)) claimRequest(options, this);
    handler.next(options);
  }

  /// 请求是否已进入结算登记簿（share 参与）而本插件没有认领。说明 onRequest 被
  /// 上游短路（如 mock），share 已按"无认领"当场结算，此时再恢复会让 leader 与
  /// follower 结果不一致。没有登记簿（无 share）时保持原行为，仍可恢复。
  bool _unclaimedUnderShare(RequestOptions config) {
    final claims = claimsOf(config);
    return claims != null && !claims.has(this);
  }

  /// 该请求按配置是否可能被本插件重试。
  bool _mayRetry(RequestOptions config) =>
      !_isDisabled(config) &&
      _resolveMax(config) > 0 &&
      _resolveMethods(config)
          .any((m) => m.toUpperCase() == config.method.toUpperCase());

  // ── Business-level failure (onResponse) ───────────────────────────────────

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    unawaited(_handleResponse(response, handler));
  }

  /// 响应阶段的业务级失败恢复。任何回调抛出的异常都转成 [DioException]，
  /// handler 恰好完成一次。
  Future<void> _handleResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final config = response.requestOptions;
    try {
      if (isJoined(config) ||
          _unclaimedUnderShare(config) ||
          !_shouldRetry(config, null, response)) {
        return ReplayClient.handOffResponse(config, this, response, handler);
      }

      // Business failure: retry up to $max times. The re-issue is an
      // interceptor-less client, so the whole retry loop lives in THIS one
      // invocation, explicitly re-checking $shouldRetry after every attempt.
      final $max = _resolveMax(config);
      final token = config.cancelToken;
      var current = response;
      _breaker?.recordResponse(current);
      for (var attempt = 1; attempt <= $max; attempt++) {
        // Breaker tripped (by this or other requests) → stop piling retries on a
        // downed server; propagate the last outcome instead.
        if (_breaker?.isOpen(config) == true) break;
        final wait = _resolveWait(config, attempt, $max, current, null);
        await cancellableDelay(wait, token);
        if (token?.isCancelled == true) return _failCanceled(config, handler);
        if (_breaker?.isOpen(config) == true) break;
        // 先确认 body 可重放再领熔断凭据，否则 break 后凭据被最终错误再记一次。
        if (!prepareForReplay(config)) break; // body 无法重放
        _breaker?.admit(config);
        onRetry?.call(attempt);
        try {
          current = await _reissue(config);
        } catch (_) {
          // 认证恢复等待期间被取消：以取消结束，不交出原业务失败。
          if (token?.isCancelled == true) return _failCanceled(config, handler);
          // The re-issue failed outright (network/HTTP level) rather than
          // landing another business failure — give up, propagate the
          // original business failure rather than a transport error the
          // caller never asked about.
          break;
        }
        if (!_shouldRetry(config, null, current)) break;
        _breaker?.recordResponse(current);
      }
      // 恢复成功与否都用 next 往后走：后续的 normalize、breaker 等照常处理，
      // 与首次成功语义一致。
      ReplayClient.handOffResponse(config, this, current, handler);
    } catch (e, s) {
      // 回调（shouldRetry/delay/onRetry/jitter）抛异常：标记后走错误阶段，
      // 本插件的 onError 看到标记不再重复调用回调。
      final err = DioException(requestOptions: config, error: e, stackTrace: s);
      config.extra[_kCallbackFailed] = true;
      if (!handler.isCompleted) {
        ReplayClient.handOffResponseError(config, this, err, handler);
      }
    }
  }

  /// 响应阶段发现请求已被取消：以取消异常结束，而不是返回重试前的业务失败。
  void _failCanceled(
      RequestOptions config, ResponseInterceptorHandler handler) {
    final err = _cancelErrorOf(config);
    releaseClaim(config, this, error: err);
    handler.reject(err, true);
  }

  // ── HTTP / network failure (onError) ──────────────────────────────────────

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    unawaited(_handleError(err, handler));
  }

  /// 错误阶段的重试。任何回调抛出的异常都转成 [DioException]，handler 恰好
  /// 完成一次。
  Future<void> _handleError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final config = err.requestOptions;
    try {
      if (isJoined(config) ||
          _unclaimedUnderShare(config) ||
          config.extra.remove(_kCallbackFailed) == true ||
          !_shouldRetry(config, err, err.response)) {
        return _replay.handOffError(this, config, err, handler);
      }

      // Retry up to $max times, same reasoning as the response path: the whole
      // loop lives in this one invocation, explicitly re-checking $shouldRetry
      // against every subsequent failure (a re-issue can fail with a
      // DIFFERENT, non-retryable error — that stops the loop early).
      final $max = _resolveMax(config);
      final token = config.cancelToken;
      var lastError = err;
      _breaker?.recordError(lastError);
      for (var attempt = 1; attempt <= $max; attempt++) {
        // Breaker tripped (by this or other requests) → stop piling retries on a
        // downed server; propagate the last error instead.
        if (_breaker?.isOpen(config) == true) break;
        final wait =
            _resolveWait(config, attempt, $max, lastError.response, lastError);
        await cancellableDelay(wait, token);
        if (token?.isCancelled == true) {
          lastError = token!.cancelError ?? lastError;
          break;
        }
        if (_breaker?.isOpen(config) == true) break;
        // 先确认 body 可重放再领熔断凭据，否则 break 后凭据被最终错误再记一次。
        if (!prepareForReplay(config)) break; // body 无法重放
        _breaker?.admit(config);
        onRetry?.call(attempt);
        Response<dynamic> retried;
        try {
          retried = await _reissue(config);
        } catch (e) {
          lastError = e is DioException
              ? e
              : DioException(requestOptions: config, error: e);
          _breaker?.recordError(lastError);
          if (!_shouldRetry(config, lastError, lastError.response)) break;
          continue;
        }
        return await _replay.finishRecovered(this, config, retried, handler);
      }
      _replay.handOffError(this, config, lastError, handler);
    } catch (e, s) {
      final failure =
          DioException(requestOptions: config, error: e, stackTrace: s);
      if (!handler.isCompleted) {
        _replay.handOffError(this, config, failure, handler);
      }
    }
  }

  /// Issues the retry through the replay client (host transport when bound).
  ///
  /// 通过重放客户端发起重试（已绑定宿主时用宿主的传输层）。
  Future<Response<dynamic>> _reissue(RequestOptions config) async {
    try {
      return await _replay.fetch(config);
    } on DioException catch (error) {
      final recovered = await claimsOf(config)?.recoverAuth?.call(error);
      if (recovered is Response<dynamic>) return recovered;
      if (recovered is DioException) throw recovered;
      // 等待认证刷新期间请求被取消：抛取消错误，而不是把原 401 当最终结果。
      if (config.cancelToken?.isCancelled == true) throw _cancelErrorOf(config);
      rethrow;
    }
  }

  /// [config] 已取消时交出的取消错误。
  static DioException _cancelErrorOf(RequestOptions config) =>
      config.cancelToken?.cancelError ??
      DioException.requestCancelled(
          requestOptions: config, reason: 'cancelled');

  @override
  void dispose() {
    _replay.dispose();
  }
}
