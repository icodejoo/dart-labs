import 'package:dio/dio.dart';
import 'dioman_plugin.dart';

/// The three states of a circuit breaker bucket.
///
/// 熔断器某个桶的三种状态。
enum DiomanBreakerState {
  /// Normal operation — every request is let through.
  ///
  /// 正常放行——所有请求都通过。
  closed,

  /// Tripped — every request is rejected immediately without hitting the
  /// network, until the cooldown ([DiomanBreaker.resetDuration]) elapses.
  ///
  /// 已熔断——冷却时间（[DiomanBreaker.resetDuration]）走完前，所有请求都被
  /// 立即拒绝、不打网络。
  open,

  /// Probing — a limited number of probe requests
  /// ([DiomanBreaker.halfOpenMaxCalls]) are let through to test whether the
  /// dependency has recovered; one success closes the breaker, one failure
  /// re-opens it.
  ///
  /// 探测中——放行有限个探测请求（[DiomanBreaker.halfOpenMaxCalls]）试探依赖
  /// 是否已恢复；一个成功即关闭熔断器，一个失败即重新熔断。
  halfOpen,
}

/// The `shouldTrip` decision function's shape: `(response?, err?) → bool?`.
/// An exact `true`/`false` decides outright whether the outcome counts as a
/// failure; `null` (including when `shouldTrip` isn't set) falls through to
/// the built-in default (network/timeout errors and HTTP 5xx / 429 count as
/// failures, everything else counts as success).
///
/// `shouldTrip`判定函数的形状：`(response?, err?) → bool?`。返回明确的
/// `true`/`false`直接决定该结果是否算失败；返回`null`（包括没设置
/// `shouldTrip`）退回内置默认判定（网络/超时错误和HTTP 5xx/429算失败，其余
/// 算成功）。
typedef DiomanShouldTrip = bool? Function(
  Response<dynamic>? response,
  DioException? err,
);

/// Thrown (wrapped in [DioException.error]) when the breaker is open and
/// rejects a request without hitting the network.
///
/// The wrapping [DioException] uses [DioExceptionType.unknown] and carries no
/// `response`, so [DiomanRetry]'s default `shouldRetry` never retries it — a
/// fail-fast rejection must stay fast. Catch it (via `e.error is
/// DiomanBreakerOpenException` on the caught [DioException]) to tell a circuit
/// rejection apart from a genuine transport error.
///
/// 熔断器open时拒绝请求（不打网络）所抛，包在[DioException.error]内。
///
/// 外层[DioException]用[DioExceptionType.unknown]且不带`response`，因此
/// [DiomanRetry]的默认`shouldRetry`永不重试它——fail-fast的拒绝必须保持"快"。
/// 通过捕获的[DioException]上的`e.error is DiomanBreakerOpenException`来把
/// 熔断拒绝跟真正的传输错误区分开。
class DiomanBreakerOpenException implements Exception {
  /// Creates a breaker-open marker for the given bucket.
  ///
  /// 为指定的桶创建一个熔断-open标记。
  ///
  /// @param bucketKey The `METHOD:path` bucket that is currently open.
  ///
  ///   当前处于open状态的`METHOD:path`桶键。
  ///
  /// @param retryableAt The wall-clock time the bucket's cooldown ends and a
  ///   probe becomes possible, or `null` if unknown.
  ///
  ///   桶的冷却结束、可以开始探测的墙钟时间；未知则为`null`。
  const DiomanBreakerOpenException({required this.bucketKey, this.retryableAt});

  /// The `METHOD:path` bucket that tripped this rejection.
  ///
  /// 触发本次拒绝的`METHOD:path`桶键。
  final String bucketKey;

  /// When the cooldown ends and the next request may probe the dependency.
  ///
  /// 冷却结束、下一个请求可以探测依赖的时间点。
  final DateTime? retryableAt;

  @override
  String toString() =>
      'DiomanBreakerOpenException(bucket: $bucketKey, retryableAt: $retryableAt)';
}

/// Per-request override for [DiomanBreaker], read from `extra['dioman:breaker']`.
/// Any field left `null` falls back to the plugin-level value of the same name.
///
/// [DiomanBreaker]的单请求覆盖，从`extra['dioman:breaker']`读取。留`null`的字段
/// 各自回退到插件级同名值。
class DiomanBreakerOptions {
  /// Creates a per-request override; every field is optional and `null` means
  /// "inherit the plugin's own value".
  ///
  /// 创建单请求覆盖；每个字段都可选，`null`表示"沿用插件自身的值"。
  const DiomanBreakerOptions({
    this.enabled,
    this.failureThreshold,
    this.resetDuration,
    this.halfOpenMaxCalls,
    this.shouldTrip,
    this.keyBuilder,
  });

  /// `false` skips the breaker for this request entirely — it is neither
  /// rejected when open nor counted toward tripping. `null` (default) inherits
  /// [DiomanBreaker.enabled].
  ///
  /// `false`表示本次请求完全跳过熔断器——open时不拒绝，也不计入熔断计数。
  /// `null`（默认）沿用[DiomanBreaker.enabled]。
  final bool? enabled;

  /// Overrides the plugin's default `failureThreshold` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`failureThreshold`。
  final int? failureThreshold;

  /// Overrides the plugin's default `resetDuration` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`resetDuration`。
  final Duration? resetDuration;

  /// Overrides the plugin's default `halfOpenMaxCalls` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`halfOpenMaxCalls`。
  final int? halfOpenMaxCalls;

  /// Overrides the plugin's default `shouldTrip` decision for this request
  /// only.
  ///
  /// 仅本次请求覆盖插件默认的`shouldTrip`判定。
  final DiomanShouldTrip? shouldTrip;

  /// Overrides the plugin's default `keyBuilder` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`keyBuilder`。
  final String Function(RequestOptions)? keyBuilder;
}

/// Mutable per-bucket state. One instance per distinct bucket key.
///
/// 每个桶的可变状态。每个不同的桶键对应一个实例。
class _Bucket {
  /// Current circuit state. Starts [DiomanBreakerState.closed].
  ///
  /// 当前熔断状态，初始为[DiomanBreakerState.closed]。
  DiomanBreakerState state = DiomanBreakerState.closed;

  /// Consecutive-failure counter while [state] is closed; reset to 0 on any
  /// success. Trips the breaker when it reaches the effective threshold.
  ///
  /// [state]为closed时的连续失败计数；任一成功即清零。达到有效阈值时熔断。
  int consecutiveFailures = 0;

  /// Probe requests already let out while [state] is halfOpen. Additional
  /// concurrent requests beyond the effective `halfOpenMaxCalls` are rejected.
  ///
  /// [state]为halfOpen时已放出的探测请求数。超出有效`halfOpenMaxCalls`的并发
  /// 请求会被拒绝。
  int halfOpenInFlight = 0;

  /// When the breaker last entered [DiomanBreakerState.open] — drives the
  /// cooldown check. `null` while closed.
  ///
  /// 熔断器最近一次进入[DiomanBreakerState.open]的时间——驱动冷却判断。
  /// closed时为`null`。
  DateTime? openedAt;
}

/// Circuit breaker: trips per `METHOD:path` bucket after consecutive failures,
/// then fails fast until a cooldown lets a few probe requests test recovery.
///
/// 熔断器：按`METHOD:path`分桶，连续失败后熔断，随后fail-fast，直到冷却结束
/// 放行少量探测请求试探恢复。
///
/// ## Why this exists alongside [DiomanRetry]
///
/// [DiomanRetry] retries a *single* request's own attempts; its back-off only
/// spaces those attempts apart. It does nothing to coordinate across
/// independent concurrent requests — 20 requests each retrying 3× still land
/// 60 hits on a downed server. This plugin adds the cross-request state
/// [DiomanRetry] structurally lacks: once a dependency is genuinely down it
/// rejects new requests in microseconds (no network, no waiting out a weak-
/// network timeout), and gives the server a cooldown window instead of being
/// hammered.
///
/// ## 为何与[DiomanRetry]并存
///
/// [DiomanRetry]重试的是*单个*请求自己的多次尝试；它的退避只把这些尝试在时间
/// 上拉开，对独立并发请求之间毫无协调——20个请求各重试3次，照样有60次打到已挂
/// 的服务器。本插件补上[DiomanRetry]结构上没有的跨请求状态：依赖一旦真的挂了，
/// 新请求微秒级拒绝（不打网络、不空等弱网超时），并给服务器一个冷却窗口而不是
/// 被持续锤击。
///
/// ## Ordering — install AFTER [DiomanRetry]
///
/// This plugin belongs right after [DiomanRetry] in the canonical chain (`...
/// auth → retry → breaker → log → normalize`). That placement means it counts
/// only the *final* outcome of each top-level request — a request [DiomanRetry]
/// recovers reaches this plugin's [onResponse] as a success and resets the
/// bucket, while only a request that exhausts its retries reaches [onError] as
/// a failure. So the breaker trips on genuinely-failed requests, not on
/// transient blips retry already absorbed. [DiomanRetry]'s own re-issues go
/// through a throwaway interceptor-less `Dio` and never reach this plugin, so
/// each top-level request is counted exactly once.
///
/// ## 顺序——装在[DiomanRetry]之后
///
/// 本插件在canonical链条里紧跟[DiomanRetry]（`... auth → retry → breaker →
/// log → normalize`）。这个位置意味着它只统计每个顶层请求的*最终*结果——被
/// [DiomanRetry]救回来的请求以成功身份到达本插件的[onResponse]并重置桶，只有
/// 重试耗尽的请求才以失败身份到达[onError]。所以熔断器只对真正失败的请求敏感，
/// 不会被重试已经吸收掉的偶发抖动误触发。[DiomanRetry]自己的重发走的是不带
/// 拦截器的裸`Dio`、永不到达本插件，因此每个顶层请求恰好只计一次。
///
/// ## Interaction with [DiomanRetry] (storm cutoff)
///
/// Wire [DiomanRetry.breaker] to this instance (done automatically by
/// [Dioman.install] when both a `retry:` and a `breaker:` are passed) and
/// [DiomanRetry] checks [isOpen] before each re-issue — so a request still
/// looping through its retries stops the moment the breaker trips from other
/// requests, instead of piling more attempts onto a server that just went down.
///
/// ## 与[DiomanRetry]的联动（掐断风暴）
///
/// 把[DiomanRetry.breaker]接到本实例（同时传入`retry:`和`breaker:`时
/// [Dioman.install]会自动完成），[DiomanRetry]会在每次重发前检查[isOpen]——
/// 于是正在重试循环中的请求，会在熔断器因其它请求触发的那一刻立即停止，而不是
/// 继续往刚挂掉的服务器上堆重试。
///
/// ```dart
/// final breaker = DiomanBreaker(
///   failureThreshold: 10,
///   resetDuration: const Duration(seconds: 30),
///   halfOpenMaxCalls: 3,
/// );
/// dio.interceptors.add(breaker); // after DiomanRetry
/// ```
class DiomanBreaker extends DiomanPlugin {
  /// Creates a circuit breaker plugin.
  ///
  /// 创建一个熔断器插件。
  ///
  /// @param failureThreshold Consecutive failures that trip a closed bucket to
  ///   open. Defaults to 10.
  ///
  ///   把一个closed桶熔断为open所需的连续失败次数。默认10。
  ///
  /// @param resetDuration How long a bucket stays open before the next request
  ///   is allowed through as a probe (halfOpen). Defaults to 30 seconds.
  ///
  ///   一个桶保持open多久之后，下一个请求才被作为探测（halfOpen）放行。
  ///   默认30秒。
  ///
  /// @param halfOpenMaxCalls Maximum probe requests let through while halfOpen.
  ///   Defaults to 3.
  ///
  ///   halfOpen期间放行的最大探测请求数。默认3。
  ///
  /// @param shouldTrip Decides whether an outcome counts as a failure; `null`
  ///   falls through to the built-in default. See [DiomanShouldTrip].
  ///
  ///   判定某个结果是否算失败；`null`退回内置默认。见[DiomanShouldTrip]。
  ///
  /// @param keyBuilder Computes the bucket key for a request; `null` uses
  ///   `METHOD:path` (matching [DiomanKey]'s fast-key scheme).
  ///
  ///   计算某请求的桶键；`null`时用`METHOD:path`（与[DiomanKey]的fast-key
  ///   方案一致）。
  ///
  /// @param onStateChange Observational hook fired on every bucket state
  ///   transition. Constructor-level only — not overridable per request.
  ///
  ///   每次桶状态迁移时触发的观察钩子。仅构造级——不支持单请求覆盖。
  ///
  /// @param enabled `false` disables the whole plugin. Defaults to `true`.
  ///
  ///   `false`时整体禁用插件。默认`true`。
  DiomanBreaker({
    this.failureThreshold = 10,
    this.resetDuration = const Duration(seconds: 30),
    this.halfOpenMaxCalls = 3,
    this.shouldTrip,
    this.keyBuilder,
    this.onStateChange,
    this.enabled = true,
  });

  /// Consecutive failures that trip a closed bucket. Overridable per request
  /// via [DiomanBreakerOptions.failureThreshold].
  ///
  /// 熔断一个closed桶所需的连续失败次数。可通过
  /// [DiomanBreakerOptions.failureThreshold]按请求覆盖。
  final int failureThreshold;

  /// Cooldown before an open bucket admits a probe. Overridable per request
  /// via [DiomanBreakerOptions.resetDuration].
  ///
  /// open桶放行探测前的冷却时间。可通过[DiomanBreakerOptions.resetDuration]
  /// 按请求覆盖。
  final Duration resetDuration;

  /// Max probes let through while halfOpen. Overridable per request via
  /// [DiomanBreakerOptions.halfOpenMaxCalls].
  ///
  /// halfOpen期间放行的最大探测数。可通过
  /// [DiomanBreakerOptions.halfOpenMaxCalls]按请求覆盖。
  final int halfOpenMaxCalls;

  /// Decides whether an outcome counts as a failure. `null` uses the built-in
  /// default (see [DiomanShouldTrip]). Overridable per request via
  /// [DiomanBreakerOptions.shouldTrip].
  ///
  /// 判定某结果是否算失败。`null`用内置默认（见[DiomanShouldTrip]）。
  /// 可通过[DiomanBreakerOptions.shouldTrip]按请求覆盖。
  final DiomanShouldTrip? shouldTrip;

  /// Computes the bucket key for a request. `null` uses `METHOD:path`.
  /// Overridable per request via [DiomanBreakerOptions.keyBuilder].
  ///
  /// 计算某请求的桶键。`null`用`METHOD:path`。可通过
  /// [DiomanBreakerOptions.keyBuilder]按请求覆盖。
  final String Function(RequestOptions)? keyBuilder;

  /// Fired on every bucket state transition, with `(bucketKey, from, to)`.
  /// Purely observational — wire it to metrics/logging. Not overridable per
  /// request.
  ///
  /// 每次桶状态迁移时触发，参数`(桶键, from, to)`。纯观察性——可接到监控/日志。
  /// 不支持单请求覆盖。
  final void Function(String key, DiomanBreakerState from, DiomanBreakerState to)?
      onStateChange;

  /// `false` disables the plugin entirely — every request passes through
  /// untouched and no bucket state is ever updated.
  ///
  /// `false`时插件整体失效——所有请求原样通过，永不更新任何桶状态。
  final bool enabled;

  /// Per-bucket state, keyed by the computed bucket key.
  ///
  /// 每个桶的状态，以计算出的桶键索引。
  final _buckets = <String, _Bucket>{};

  /// Public plugin name / extra key for this plugin, accessible without an
  /// instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:breaker';

  // Internal bookkeeping key: marks a request this plugin's onRequest actually
  // admitted, so onResponse/onError only record an outcome for requests that
  // went through onRequest here (a cache/mock short-circuit runs our
  // onResponse without ever running our onRequest — it must not be recorded).
  //
  // 内部记账key：标记本插件onRequest真正放行的请求，让onResponse/onError只对
  // 经过本插件onRequest的请求记录结果（cache/mock短路会在没跑过本插件
  // onRequest的情况下触发本插件onResponse——那种不能记录）。
  static const _kAdmitted = '$pluginName:key';

  @override
  String get name => pluginName;

  // ── Per-request override resolution ─────────────────────────────────────────

  DiomanBreakerOptions? _overrideObject(RequestOptions config) {
    final v = config.extra[name];
    return v is DiomanBreakerOptions ? v : null;
  }

  bool _enabledFor(RequestOptions config) =>
      _overrideObject(config)?.enabled ?? enabled;

  int _resolveThreshold(RequestOptions config) =>
      _overrideObject(config)?.failureThreshold ?? failureThreshold;

  Duration _resolveReset(RequestOptions config) =>
      _overrideObject(config)?.resetDuration ?? resetDuration;

  int _resolveHalfOpenMax(RequestOptions config) =>
      _overrideObject(config)?.halfOpenMaxCalls ?? halfOpenMaxCalls;

  DiomanShouldTrip? _resolveShouldTrip(RequestOptions config) =>
      _overrideObject(config)?.shouldTrip ?? shouldTrip;

  String _keyFor(RequestOptions config) {
    final builder = _overrideObject(config)?.keyBuilder ?? keyBuilder;
    if (builder != null) return builder(config);
    return '${config.method.toUpperCase()}:${config.uri.path}';
  }

  // ── Failure classification ──────────────────────────────────────────────────

  /// Whether [response]/[err] counts as a failure for tripping purposes.
  /// Honours the effective `shouldTrip` first; falls back to the built-in
  /// default (network/timeout errors and HTTP 5xx / 429 are failures).
  ///
  /// 判断[response]/[err]是否算触发熔断的失败。先听生效的`shouldTrip`；退回
  /// 内置默认（网络/超时错误和HTTP 5xx/429算失败）。
  bool _isFailure(
    RequestOptions config,
    Response<dynamic>? response,
    DioException? err,
  ) {
    final custom = _resolveShouldTrip(config)?.call(response, err);
    if (custom != null) return custom;
    final status = response?.statusCode ?? err?.response?.statusCode;
    if (status != null) return status >= 500 || status == 429;
    // No HTTP status at all → transport-level. Only genuine
    // network/timeout failures count; unknown-type errors (auth denial,
    // this plugin's own open-rejection) deliberately do not.
    final t = err?.type;
    return t == DioExceptionType.connectionTimeout ||
        t == DioExceptionType.receiveTimeout ||
        t == DioExceptionType.sendTimeout ||
        t == DioExceptionType.connectionError;
  }

  // ── State transitions ─────────────────────────────────────────────────────

  void _transition(String key, _Bucket b, DiomanBreakerState to) {
    final from = b.state;
    if (from == to) return;
    b.state = to;
    onStateChange?.call(key, from, to);
  }

  void _recordSuccess(String key, RequestOptions config) {
    final b = _buckets[key];
    if (b == null) return;
    if (b.state == DiomanBreakerState.halfOpen) {
      // A probe succeeded → the dependency looks healthy again.
      b.consecutiveFailures = 0;
      b.halfOpenInFlight = 0;
      b.openedAt = null;
      _transition(key, b, DiomanBreakerState.closed);
    } else if (b.state == DiomanBreakerState.closed) {
      b.consecutiveFailures = 0;
    }
    // If open: a straggler admitted before the trip landing a success is
    // ignored — the open state stands until its own cooldown probe.
  }

  void _recordFailure(String key, RequestOptions config) {
    final b = _buckets[key];
    if (b == null) return;
    if (b.state == DiomanBreakerState.halfOpen) {
      // A probe failed → straight back to open, cooldown restarts.
      b.consecutiveFailures = 0;
      b.halfOpenInFlight = 0;
      b.openedAt = DateTime.now();
      _transition(key, b, DiomanBreakerState.open);
    } else if (b.state == DiomanBreakerState.closed) {
      b.consecutiveFailures++;
      if (b.consecutiveFailures >= _resolveThreshold(config)) {
        b.halfOpenInFlight = 0;
        b.openedAt = DateTime.now();
        _transition(key, b, DiomanBreakerState.open);
      }
    }
    // If open: request admitted before the trip that fails now — already open,
    // nothing to do.
  }

  // ── Public query (for DiomanRetry integration) ──────────────────────────────

  /// Whether the breaker would reject a fresh request for [config] right now —
  /// a pure read that never mutates state or fires [onStateChange]. Returns
  /// `false` for a disabled plugin, an unknown bucket, a closed bucket, an
  /// open bucket whose cooldown has already elapsed (the next request would
  /// probe), and a halfOpen bucket still under its probe budget. Used by
  /// [DiomanRetry] to stop retrying the instant the breaker trips.
  ///
  /// 判断熔断器此刻是否会拒绝[config]的新请求——纯读取，绝不改状态、也不触发
  /// [onStateChange]。以下返回`false`：插件被禁用、桶不存在、桶为closed、桶为
  /// open但冷却已到（下个请求会去探测）、桶为halfOpen且探测名额未满。
  /// [DiomanRetry]用它在熔断器触发的瞬间停止重试。
  ///
  /// @param config The request whose bucket to inspect.
  ///
  ///   要检查其所属桶的请求。
  ///
  /// @returns `true` only when a fresh request would be fail-fast rejected.
  ///
  ///   仅当新请求会被fail-fast拒绝时返回`true`。
  bool isOpen(RequestOptions config) {
    if (!_enabledFor(config)) return false;
    final b = _buckets[_keyFor(config)];
    if (b == null) return false;
    switch (b.state) {
      case DiomanBreakerState.closed:
        return false;
      case DiomanBreakerState.open:
        final openedAt = b.openedAt;
        if (openedAt == null) return true;
        // Cooled down → the next request would be admitted as a probe, so it
        // is not "blocking" any more.
        return DateTime.now().difference(openedAt) < _resolveReset(config);
      case DiomanBreakerState.halfOpen:
        return b.halfOpenInFlight >= _resolveHalfOpenMax(config);
    }
  }

  /// Snapshot of a bucket's current state, or [DiomanBreakerState.closed] if
  /// the bucket has never been seen. Read-only, for inspection/testing.
  ///
  /// 某个桶当前状态的快照；从未见过该桶则返回[DiomanBreakerState.closed]。
  /// 只读，供检查/测试用。
  ///
  /// @param key The `METHOD:path` bucket key.
  ///
  ///   `METHOD:path`桶键。
  ///
  /// @returns The bucket's [DiomanBreakerState].
  ///
  ///   该桶的[DiomanBreakerState]。
  DiomanBreakerState stateOf(String key) =>
      _buckets[key]?.state ?? DiomanBreakerState.closed;

  // ── Interceptor hooks ───────────────────────────────────────────────────────

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_enabledFor(options)) return handler.next(options);

    final key = _keyFor(options);
    final b = _buckets.putIfAbsent(key, _Bucket.new);

    // Cooldown elapsed → move open → halfOpen and let this request probe.
    if (b.state == DiomanBreakerState.open) {
      final openedAt = b.openedAt;
      if (openedAt != null &&
          DateTime.now().difference(openedAt) >= _resolveReset(options)) {
        b.halfOpenInFlight = 0;
        _transition(key, b, DiomanBreakerState.halfOpen);
      }
    }

    switch (b.state) {
      case DiomanBreakerState.open:
        return _reject(options, handler, key, b);
      case DiomanBreakerState.halfOpen:
        if (b.halfOpenInFlight >= _resolveHalfOpenMax(options)) {
          return _reject(options, handler, key, b);
        }
        b.halfOpenInFlight++;
      case DiomanBreakerState.closed:
        break;
    }

    // Admitted (closed, or an under-budget halfOpen probe) — mark it so our
    // onResponse/onError record its outcome.
    options.extra[_kAdmitted] = key;
    handler.next(options);
  }

  /// Rejects [options] fast with a [DiomanBreakerOpenException]. Uses
  /// `callFollowingErrorInterceptor: true` so brackets installed before this
  /// plugin (cancel/loading/share) still get their `onError` to release state
  /// — same reasoning as [DiomanAuth]'s onRequest rejections.
  ///
  /// 用[DiomanBreakerOpenException]对[options]快速拒绝。传
  /// `callFollowingErrorInterceptor: true`，让装在本插件之前的bracket
  /// （cancel/loading/share）仍能收到`onError`释放状态——与[DiomanAuth]的
  /// onRequest拒绝同理。
  void _reject(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String key,
    _Bucket b,
  ) {
    final retryableAt = b.openedAt?.add(_resolveReset(options));
    handler.reject(
      DioException(
        requestOptions: options,
        // Default DioExceptionType.unknown + no response ⇒ DiomanRetry's
        // default shouldRetry won't retry this fast-fail rejection.
        error: DiomanBreakerOpenException(bucketKey: key, retryableAt: retryableAt),
        message: '[breaker] circuit open for $key',
      ),
      true,
    );
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    final config = response.requestOptions;
    final key = config.extra[_kAdmitted] as String?;
    // No key ⇒ our onRequest never admitted this request (cache/mock hit, or
    // disabled) ⇒ nothing to record.
    if (key != null) {
      if (_isFailure(config, response, null)) {
        _recordFailure(key, config);
      } else {
        _recordSuccess(key, config);
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Our own fast-fail rejection is not a dependency failure — never count it.
    if (err.error is DiomanBreakerOpenException) return handler.next(err);
    // A user cancellation says nothing about the dependency's health — it is
    // neither a success nor a failure. Recording it (as either) would corrupt
    // the consecutive-failure count: counting it as success would reset a
    // count that is mid-way to tripping, letting a burst of cancels mask a
    // genuinely failing dependency. Skip it entirely.
    //
    // 用户主动取消不反映依赖的健康状况——它既不算成功也不算失败。记录它（无论
    // 记成哪种）都会污染连续失败计数：记成成功会把一个正走向熔断的计数清零，
    // 于是一串取消就能掩盖真正在失败的依赖。直接跳过。
    if (err.type == DioExceptionType.cancel) return handler.next(err);
    final config = err.requestOptions;
    final key = config.extra[_kAdmitted] as String?;
    if (key != null) {
      if (_isFailure(config, err.response, err)) {
        _recordFailure(key, config);
      } else {
        _recordSuccess(key, config);
      }
    }
    handler.next(err);
  }

  /// Resets every bucket to [DiomanBreakerState.closed] and forgets all state.
  ///
  /// 把所有桶重置为[DiomanBreakerState.closed]并清空全部状态。
  void reset() => _buckets.clear();

  @override
  void dispose() => _buckets.clear();
}
