import 'package:dio/dio.dart';
import 'dioman_plugin.dart';
import 'retry_plugin.dart';
import 'plugin_order.dart';

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
  /// 当前恢复窗口的身份，状态迁移时更新。
  Object generation = Object();

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

  /// 已放行但尚未出结果的请求数（含 closed 与探测）；大于 0 时桶不可回收。
  int inFlight = 0;

  /// 最近一次被访问（请求进入或结果记录）的时间，用于空闲回收。
  DateTime lastUsed;

  /// 创建桶，[lastUsed]初始为创建时间。
  _Bucket(this.lastUsed);

  /// 可安全丢弃：closed、连续失败为 0、无在途请求，丢弃后等价于新桶。
  bool get isDisposable =>
      state == DiomanBreakerState.closed &&
      consecutiveFailures == 0 &&
      inFlight == 0;
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
/// auth → retry → breaker → log → normalize`). When connected by [Dioman.install],
/// [DiomanRetry] reports every failed transport attempt to this plugin and
/// acquires a fresh admission ticket before re-issuing a request. An open
/// circuit stops the retry loop. A recovered response reaches [onResponse]
/// as a success and resets the bucket; admission tickets ensure that a final
/// error is not counted twice. The retry transport itself has no interceptors,
/// so this per-attempt accounting is performed explicitly by [DiomanRetry].
/// Without that connection, this plugin observes only the host chain's outcomes.
///
/// ## 顺序——装在[DiomanRetry]之后
///
/// 本插件在canonical链条里紧跟[DiomanRetry]（`... auth → retry → breaker →
/// log → normalize`）。由[Dioman.install]接线后，[DiomanRetry]显式报告每次
/// 传输失败，并在每次重发前领取新的入场凭据；熔断一旦打开就停止继续重试。
/// 恢复成功的响应仍经[onResponse]清零失败计数；凭据消费确保最终错误不重复记账。
/// 重发本身走没有拦截器的传输层，所以逐次记账由[DiomanRetry]显式调用完成。
/// 若没有连接[DiomanRetry.breaker]，本插件只观察宿主拦截链实际交出的结果。
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
  ///
  /// @param idleTtl A bucket that is closed, has no recorded failures, has no
  ///   in-flight request and has been untouched for longer than this is
  ///   discarded lazily (when a new bucket is created). Discarding is
  ///   behaviour-neutral: the key simply restarts from closed. Defaults to
  ///   1 hour.
  ///
  ///   closed、无失败计数、无在途请求且闲置超过该时长的桶，会在创建新桶时被惰性
  ///   丢弃；丢弃不改变行为（同键重新从closed开始）。默认1小时。
  ///
  /// @param maxBuckets Soft cap on the bucket count. When creating a new bucket
  ///   would reach it, the least-recently-used disposable buckets are evicted;
  ///   open/halfOpen/in-flight/failing buckets are never evicted, so the count
  ///   may temporarily exceed the cap. Defaults to 1000.
  ///
  ///   桶数量的软上限。新建桶将达到上限时，淘汰最久未用的可丢弃桶；
  ///   open/halfOpen/在途/有失败计数的桶永不淘汰，因此数量可能暂时超出。默认1000。
  ///
  /// @param clock Time source, for tests. Defaults to [DateTime.now].
  ///
  ///   时间源，供测试注入。默认[DateTime.now]。
  DiomanBreaker({
    this.failureThreshold = 10,
    this.resetDuration = const Duration(seconds: 30),
    this.halfOpenMaxCalls = 3,
    this.shouldTrip,
    this.keyBuilder,
    this.onStateChange,
    this.enabled = true,
    this.idleTtl = defaultIdleTtl,
    this.maxBuckets = defaultMaxBuckets,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 默认空闲回收时长。
  static const defaultIdleTtl = Duration(hours: 1);

  /// 默认桶数量软上限。
  static const defaultMaxBuckets = 1000;

  /// 可丢弃桶的空闲回收时长，见构造参数`idleTtl`。
  final Duration idleTtl;

  /// 桶数量软上限，见构造参数`maxBuckets`。
  final int maxBuckets;

  /// 时间源。
  final DateTime Function() _clock;

  /// 当前时间。
  DateTime _now() => _clock();

  /// 当前持有的桶数量，只读，供检查/测试用。
  int get bucketCount => _buckets.length;

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
  final void Function(
          String key, DiomanBreakerState from, DiomanBreakerState to)?
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
  // went through onRequest here (a cache short-circuit runs our
  // onResponse without ever running our onRequest — it must not be recorded).
  //
  // 内部记账key：标记本插件onRequest真正放行的请求，让onResponse/onError只对
  // 经过本插件onRequest的请求记录结果（cache短路会在没跑过本插件
  // onRequest的情况下触发本插件onResponse——那种不能记录）。
  static const _kAdmitted = '$pluginName:key';

  /// 插件的公开协议名称。
  @override
  String get name => pluginName;

  /// 顺序声明：breaker在retry之后：只统计每个请求的最终结果。
  @override
  DiomanPluginOrder get ordering => const DiomanPluginOrder(
        after: {DiomanRetry.pluginName},
      );

  // ── Per-request override resolution ─────────────────────────────────────────

  /// 读取具有正确类型的单请求覆盖。
  DiomanBreakerOptions? _overrideObject(RequestOptions config) {
    final v = config.extra[name];
    return v is DiomanBreakerOptions ? v : null;
  }

  /// 判断本请求是否启用熔断。
  bool _enabledFor(RequestOptions config) =>
      _overrideObject(config)?.enabled ?? enabled;

  /// 读取本请求的失败阈值。
  int _resolveThreshold(RequestOptions config) =>
      _overrideObject(config)?.failureThreshold ?? failureThreshold;

  /// 读取本请求的冷却时间。
  Duration _resolveReset(RequestOptions config) =>
      _overrideObject(config)?.resetDuration ?? resetDuration;

  /// 读取本请求的探测上限。
  int _resolveHalfOpenMax(RequestOptions config) =>
      _overrideObject(config)?.halfOpenMaxCalls ?? halfOpenMaxCalls;

  /// 读取本请求的失败判定。
  DiomanShouldTrip? _resolveShouldTrip(RequestOptions config) =>
      _overrideObject(config)?.shouldTrip ?? shouldTrip;

  /// 计算本请求的熔断桶键。
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

  /// 状态迁移时更新窗口身份并通知观察者。
  void _transition(String key, _Bucket b, DiomanBreakerState to) {
    final from = b.state;
    if (from == to) return;
    b.generation = Object();
    b.state = to;
    onStateChange?.call(key, from, to);
  }

  /// 成功探测关闭当前窗口，普通成功重置失败计数。
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

  /// 记录失败并按阈值切换熔断状态。
  void _recordFailure(String key, RequestOptions config) {
    final b = _buckets[key];
    if (b == null) return;
    if (b.state == DiomanBreakerState.halfOpen) {
      // A probe failed → straight back to open, cooldown restarts.
      b.consecutiveFailures = 0;
      b.halfOpenInFlight = 0;
      b.openedAt = _now();
      _transition(key, b, DiomanBreakerState.open);
    } else if (b.state == DiomanBreakerState.closed) {
      b.consecutiveFailures++;
      if (b.consecutiveFailures >= _resolveThreshold(config)) {
        b.halfOpenInFlight = 0;
        b.openedAt = _now();
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
        return _now().difference(openedAt) < _resolveReset(config);
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

  /// 惰性回收：先丢弃闲置超过[idleTtl]的可丢弃桶；若新建一个桶会达到
  /// [maxBuckets]，再按最久未用顺序淘汰可丢弃桶。open/halfOpen/在途/有失败计数
  /// 的桶一律保留。
  void _collectGarbage(DateTime now) {
    _buckets.removeWhere(
        (_, b) => b.isDisposable && now.difference(b.lastUsed) > idleTtl);
    final excess = _buckets.length - maxBuckets + 1;
    if (excess <= 0) return;
    final victims = _buckets.entries.where((e) => e.value.isDisposable).toList()
      ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    for (final e in victims.take(excess)) {
      _buckets.remove(e.key);
    }
  }

  /// 处理请求并完成当前请求出口。
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final denied = _admitOrDeny(options);
    if (denied != null) {
      return _reject(options, handler, denied.key, denied.bucket);
    }
    handler.next(options);
  }

  /// Asks the circuit to admit one more transport attempt of [options], without
  /// going through the interceptor chain. Used by [DiomanRetry] before each
  /// re-issue; the outcome must then be reported via [recordResponse] or
  /// [recordError] so the admission is returned.
  ///
  /// 不经拦截链，为 [options] 的又一次传输尝试申请放行。供 [DiomanRetry] 在每次
  /// 重发前调用；之后须用 [recordResponse] 或 [recordError] 报告结果以归还凭据。
  ///
  /// - [options]：要放行的请求。
  /// - 返回：放行（或本请求未启用熔断）为 true；熔断打开或半开探测已满为 false。
  ///
  /// ```dart
  /// if (!breaker.admit(options)) return; // 熔断中，不再重发
  /// ```
  bool admit(RequestOptions options) => _admitOrDeny(options) == null;

  /// 放行时登记凭据并返回 null；拒绝时返回拒绝所需的桶键与桶。
  ({String key, _Bucket bucket})? _admitOrDeny(RequestOptions options) {
    if (!_enabledFor(options)) return null;

    final key = _keyFor(options);
    final now = _now();
    var b = _buckets[key];
    if (b == null) {
      _collectGarbage(now);
      b = _buckets[key] = _Bucket(now);
    }
    b.lastUsed = now;

    // Cooldown elapsed → move open → halfOpen and let this request probe.
    if (b.state == DiomanBreakerState.open) {
      final openedAt = b.openedAt;
      if (openedAt != null &&
          now.difference(openedAt) >= _resolveReset(options)) {
        b.halfOpenInFlight = 0;
        _transition(key, b, DiomanBreakerState.halfOpen);
      }
    }

    switch (b.state) {
      case DiomanBreakerState.open:
        return (key: key, bucket: b);
      case DiomanBreakerState.halfOpen:
        if (b.halfOpenInFlight >= _resolveHalfOpenMax(options)) {
          return (key: key, bucket: b);
        }
        b.halfOpenInFlight++;
      case DiomanBreakerState.closed:
        break;
    }

    // Admitted (closed, or an under-budget halfOpen probe) — mark it so our
    // onResponse/onError record its outcome.
    b.inFlight++;
    options.extra[_kAdmitted] = (
      key: key,
      bucket: b,
      generation: b.generation,
      probe: b.state == DiomanBreakerState.halfOpen
    );
    return null;
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
        error: DiomanBreakerOpenException(
            bucketKey: key, retryableAt: retryableAt),
        message: '[breaker] circuit open for $key',
      ),
      true,
    );
  }

  /// 消费当前窗口的凭据，归还探测槽位；旧窗口结果不改变新窗口。
  String? _takeAdmission(RequestOptions config) {
    final ticket = config.extra.remove(_kAdmitted);
    if (ticket is! ({
      String key,
      _Bucket bucket,
      Object generation,
      bool probe
    })) {
      return null;
    }
    // 无论窗口是否过期，在途计数都要归还（桶对象由凭据持有，不会被回收）。
    final held = ticket.bucket;
    if (held.inFlight > 0) held.inFlight--;
    held.lastUsed = _now();
    final b = _buckets[ticket.key];
    if (!identical(b, ticket.bucket) ||
        !identical(b?.generation, ticket.generation)) {
      return null;
    }
    if (ticket.probe && b!.halfOpenInFlight > 0) {
      b.halfOpenInFlight--;
    }
    return ticket.key;
  }

  /// 处理响应并完成当前响应出口。
  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    recordResponse(response);
    handler.next(response);
  }

  /// Records [response] as the outcome of its admitted attempt (a business
  /// failure per `isFailure` counts as a failure, anything else as a success).
  /// No-op when the request holds no admission, so a final outcome already
  /// recorded is never counted twice.
  ///
  /// 把 [response] 记为其已放行尝试的结果（按 `isFailure` 判为业务失败则计失败，
  /// 否则计成功）。请求没有凭据时什么也不做，已记过账的最终结果不会重复计数。
  ///
  /// - [response]：一次传输尝试拿到的响应。
  ///
  /// ```dart
  /// breaker.recordResponse(await transport.fetch(options));
  /// ```
  void recordResponse(Response<dynamic> response) {
    final config = response.requestOptions;
    final key = _takeAdmission(config);
    // No key ⇒ our onRequest never admitted this request (cache hit, or
    // disabled) ⇒ nothing to record.
    if (key != null) {
      if (_isFailure(config, response, null)) {
        _recordFailure(key, config);
      } else {
        _recordSuccess(key, config);
      }
    }
  }

  /// 处理失败并完成当前错误出口。
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    recordError(err);
    handler.next(err);
  }

  /// Records [err] as the outcome of its admitted attempt. The breaker's own
  /// fast-fail rejection is ignored, and a cancellation only returns the
  /// admission without counting either way. No-op without an admission.
  ///
  /// 把 [err] 记为其已放行尝试的结果。本插件自己的快速拒绝不计；取消只归还凭据、
  /// 不计成败。请求没有凭据时什么也不做。
  ///
  /// - [err]：一次传输尝试的失败。
  ///
  /// ```dart
  /// try {
  ///   await transport.fetch(options);
  /// } on DioException catch (e) {
  ///   breaker.recordError(e);
  /// }
  /// ```
  void recordError(DioException err) {
    // Our own fast-fail rejection is not a dependency failure — never count it.
    if (err.error is DiomanBreakerOpenException) return;
    // A user cancellation says nothing about the dependency's health — it is
    // neither a success nor a failure. Recording it (as either) would corrupt
    // the consecutive-failure count: counting it as success would reset a
    // count that is mid-way to tripping, letting a burst of cancels mask a
    // genuinely failing dependency. Skip it entirely.
    //
    // 用户主动取消不反映依赖的健康状况——它既不算成功也不算失败。记录它（无论
    // 记成哪种）都会污染连续失败计数：记成成功会把一个正走向熔断的计数清零，
    // 于是一串取消就能掩盖真正在失败的依赖。直接跳过。
    if (err.type == DioExceptionType.cancel) {
      _takeAdmission(err.requestOptions);
      return;
    }
    final config = err.requestOptions;
    final key = _takeAdmission(config);
    if (key != null) {
      if (_isFailure(config, err.response, err)) {
        _recordFailure(key, config);
      } else {
        _recordSuccess(key, config);
      }
    }
  }

  /// Resets every bucket to [DiomanBreakerState.closed] and forgets all state.
  ///
  /// 把所有桶重置为[DiomanBreakerState.closed]并清空全部状态。
  void reset() => _buckets.clear();

  /// 释放本插件持有的状态和资源。
  @override
  void dispose() => _buckets.clear();
}
