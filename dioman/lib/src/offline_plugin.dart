import 'dart:async';
import 'package:dio/dio.dart';
import 'dioman_plugin.dart';

/// Why a queued request was rejected instead of eventually replayed.
///
/// 一个入队请求最终被拒绝（而非重放）的原因。
enum DiomanOfflineReason {
  /// The queue was full and this (oldest) request was evicted to make room.
  ///
  /// 队列已满，这个（最早的）请求被挤出以腾空间。
  queueFull,

  /// The request's `maxWait` elapsed before connectivity was restored.
  ///
  /// 连接恢复前，请求的`maxWait`已经到时。
  timeout,

  /// The plugin was disposed while the request was still queued.
  ///
  /// 请求还在队列里时，插件被dispose了。
  disposed,
}

/// Thrown (wrapped in [DioException.error]) when a queued offline request is
/// rejected rather than replayed. The wrapping [DioException] uses
/// [DioExceptionType.unknown] and carries no `response`, so a paired
/// [DiomanRetry] never retries it (retrying an offline-rejected request while
/// still offline would just fail again). Catch it via `e.error is
/// DiomanOfflineException` on the caught [DioException].
///
/// 入队的离线请求被拒绝（而非重放）时抛出，包在[DioException.error]内。外层
/// [DioException]用[DioExceptionType.unknown]且不带`response`，因此配套的
/// [DiomanRetry]永不重试它（离线时重试一个离线被拒的请求只会再次失败）。
/// 通过捕获的[DioException]上的`e.error is DiomanOfflineException`来捕获。
class DiomanOfflineException implements Exception {
  /// Creates an offline-rejection marker with its [reason].
  ///
  /// 用[reason]创建一个离线拒绝标记。
  ///
  /// @param reason Why the queued request was rejected.
  ///
  ///   入队请求被拒绝的原因。
  const DiomanOfflineException(this.reason);

  /// Why the queued request was rejected.
  ///
  /// 入队请求被拒绝的原因。
  final DiomanOfflineReason reason;

  @override
  String toString() => 'DiomanOfflineException(${reason.name})';
}

/// Per-request override for [DiomanOffline], read from `extra['dioman:offline']`.
/// Any field left `null` falls back to the plugin-level value of the same name.
///
/// [DiomanOffline]的单请求覆盖，从`extra['dioman:offline']`读取。留`null`的字段
/// 各自回退到插件级同名值。
class DiomanOfflineOptions {
  /// Creates a per-request override; every field is optional.
  ///
  /// 创建单请求覆盖；每个字段都可选。
  const DiomanOfflineOptions({
    this.enabled,
    this.shouldQueue,
    this.maxQueueSize,
    this.maxWait,
  });

  /// `false` skips offline queueing for this request — it passes straight
  /// through even when offline. `null` (default) inherits
  /// [DiomanOffline.enabled].
  ///
  /// `false`表示本次请求跳过离线入队——即使离线也直接放行。`null`（默认）沿用
  /// [DiomanOffline.enabled]。
  final bool? enabled;

  /// Overrides the plugin's `shouldQueue` decision for this request only.
  ///
  /// 仅本次请求覆盖插件的`shouldQueue`判定。
  final bool Function(RequestOptions)? shouldQueue;

  /// Overrides the plugin's default `maxQueueSize` for this request only
  /// (evaluated when this request enqueues).
  ///
  /// 仅本次请求覆盖插件默认的`maxQueueSize`（在本请求入队时求值）。
  final int? maxQueueSize;

  /// Overrides the plugin's default `maxWait` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`maxWait`。
  final Duration? maxWait;
}

/// One parked request: its captured [handler] and [options], plus an optional
/// `maxWait` timer. Exactly one of `handler.next` / `handler.reject` is called
/// per entry, at whichever exit fires first (flush / eviction / timeout /
/// dispose).
///
/// 一个挂起的请求：捕获的[handler]和[options]，外加可选的`maxWait`定时器。
/// 每个条目在最先触发的出口（flush/挤出/超时/dispose）恰好调用一次
/// `handler.next`或`handler.reject`。
class _Queued {
  _Queued(this.handler, this.options);

  /// The captured request handler — completed exactly once at some exit.
  ///
  /// 捕获的请求handler——在某个出口恰好完成一次。
  final RequestInterceptorHandler handler;

  /// The request that was parked.
  ///
  /// 被挂起的请求。
  final RequestOptions options;

  /// Optional per-entry `maxWait` timer; cancelled at whichever exit fires.
  ///
  /// 可选的每条目`maxWait`定时器；在任一出口触发时取消。
  Timer? timer;
}

/// Queues requests while offline and replays them when connectivity returns.
///
/// 断网时把请求入队，联网恢复后重放。
///
/// Pure Dart: this plugin never detects connectivity itself. The host reports
/// it — [isOnline] is checked in [onRequest] to decide whether to queue, and
/// [onConnectivityChanged] is subscribed so a `true` event automatically
/// [flush]es the queue (you can also call [flush] by hand).
///
/// 纯Dart：本插件自己从不检测连通性。由宿主上报——[onRequest]里查[isOnline]
/// 决定是否入队，并订阅[onConnectivityChanged]，收到`true`事件自动[flush]队列
/// （也可手动调[flush]）。
///
/// **Parking mechanism.** A queued request has its interceptor handler captured
/// and simply isn't advanced — [onRequest] returns WITHOUT calling `next`, so
/// the request hangs at this plugin. On [flush] each parked request is resumed
/// with `handler.next(options)`, continuing down the rest of the chain (and to
/// the network) exactly as if it had never paused — no throwaway `Dio`, and no
/// re-entry into this plugin's [onRequest].
///
/// **挂起机制。** 入队请求的拦截器handler被捕获、单纯不推进——[onRequest]返回时
/// **不调**`next`，请求就停在本插件。[flush]时每个挂起请求用`handler.next(options)`
/// 恢复，像从没暂停过一样继续走完剩下的链（直到网络）——不用throwaway `Dio`，
/// 也不会重进本插件的[onRequest]。
///
/// **Ordering — install AFTER [DiomanCache], BEFORE [DiomanShare].** Cache
/// first means an offline read that hits the cache short-circuits and never
/// queues (stale-cache-over-queue for reads). Sitting before share/cancel/
/// loading means a parked request never created a share entry or opened a
/// cancel/loading bracket — so there is nothing to leak while it waits.
///
/// **顺序——装在[DiomanCache]之后、[DiomanShare]之前。** cache在前意味着离线读
/// 命中缓存会短路、永不入队（读优先用stale缓存）。排在share/cancel/loading之前
/// 意味着挂起的请求没建过share entry、没开过cancel/loading括号——等待期间没有
/// 任何东西会泄漏。
///
/// **`maxWait` is off by default.** With no `maxWait`, a queued request waits
/// until connectivity returns (or the queue evicts it / the plugin is
/// disposed) — potentially a long-spinning request if offline persists. Set
/// `maxWait` if the host needs a hard upper bound.
///
/// **`maxWait`默认关。** 不设`maxWait`时，入队请求会一直等到连接恢复（或被队列
/// 挤出/插件被dispose）——若持续断网可能是个久转的请求。宿主需要硬上限就设
/// `maxWait`。
///
/// ```dart
/// final offline = DiomanOffline(
///   isOnline: () => connectivity.isOnline,
///   onConnectivityChanged: connectivity.onlineStream, // Stream<bool>
///   shouldQueue: (o) => o.method != 'GET', // e.g. only queue writes
/// );
/// dio.interceptors.add(offline); // after DiomanCache, before DiomanShare
/// ```
class DiomanOffline extends DiomanPlugin {
  /// Creates an offline-queue plugin and subscribes to [onConnectivityChanged].
  ///
  /// 创建一个离线队列插件并订阅[onConnectivityChanged]。
  ///
  /// @param isOnline Returns whether the app currently has connectivity;
  ///   checked once per request. Constructor-level only.
  ///
  ///   返回app当前是否有连接；每请求查一次。仅构造级。
  ///
  /// @param onConnectivityChanged Connectivity stream; a `true` event flushes
  ///   the queue. Subscribed in the constructor, cancelled in [dispose].
  ///   Constructor-level only.
  ///
  ///   连通性流；`true`事件触发flush。构造时订阅，[dispose]时取消。仅构造级。
  ///
  /// @param shouldQueue Decides whether an offline request is queued; `null`
  ///   queues every request. Overridable per request.
  ///
  ///   判断某个离线请求是否入队；`null`则全部入队。可按请求覆盖。
  ///
  /// @param maxQueueSize Max parked requests; when full the OLDEST is evicted
  ///   (rejected with [DiomanOfflineReason.queueFull]). `0` disables the cap.
  ///   Defaults to 50. Overridable per request.
  ///
  ///   最大挂起请求数；满了挤出**最早**的（以[DiomanOfflineReason.queueFull]
  ///   拒绝）。`0`关闭上限。默认50。可按请求覆盖。
  ///
  /// @param maxWait Hard upper bound a request waits while queued; on timeout
  ///   it is rejected with [DiomanOfflineReason.timeout]. `null` (default) =
  ///   no bound. Overridable per request.
  ///
  ///   请求入队等待的硬上限；到时以[DiomanOfflineReason.timeout]拒绝。
  ///   `null`（默认）=不限。可按请求覆盖。
  ///
  /// @param enabled `false` disables the whole plugin. Defaults to `true`.
  ///
  ///   `false`时整体禁用插件。默认`true`。
  DiomanOffline({
    required bool Function() isOnline,
    required Stream<bool> onConnectivityChanged,
    bool Function(RequestOptions)? shouldQueue,
    this.maxQueueSize = 50,
    this.maxWait,
    this.enabled = true,
  })  : _isOnline = isOnline,
        _shouldQueue = shouldQueue {
    _sub = onConnectivityChanged.listen((online) {
      if (online) flush();
    });
  }

  /// Reports current connectivity; checked once per request. Not overridable
  /// per request — connectivity is ambient.
  ///
  /// 上报当前连通性；每请求查一次。不支持单请求覆盖——连通性是环境属性。
  final bool Function() _isOnline;

  /// Decides whether an offline request is queued. `null` queues everything.
  /// Overridable per request via [DiomanOfflineOptions.shouldQueue].
  ///
  /// 判断某离线请求是否入队。`null`则全入队。可通过
  /// [DiomanOfflineOptions.shouldQueue]按请求覆盖。
  final bool Function(RequestOptions)? _shouldQueue;

  /// Max parked requests; the oldest is evicted when full. `0` disables the
  /// cap. Overridable per request via [DiomanOfflineOptions.maxQueueSize].
  ///
  /// 最大挂起请求数，满了挤出最早的。`0`关闭上限。可通过
  /// [DiomanOfflineOptions.maxQueueSize]按请求覆盖。
  final int maxQueueSize;

  /// Hard upper bound a queued request waits; `null` = no bound. Overridable
  /// per request via [DiomanOfflineOptions.maxWait].
  ///
  /// 入队请求等待的硬上限；`null`=不限。可通过[DiomanOfflineOptions.maxWait]
  /// 按请求覆盖。
  final Duration? maxWait;

  /// `false` disables the plugin entirely — every request passes through
  /// regardless of connectivity.
  ///
  /// `false`时插件整体失效——无论连通性如何所有请求都直接放行。
  final bool enabled;

  /// FIFO queue of parked requests.
  ///
  /// 挂起请求的FIFO队列。
  final _queue = <_Queued>[];

  /// Subscription to the connectivity stream; cancelled in [dispose].
  ///
  /// 连通性流的订阅；[dispose]时取消。
  StreamSubscription<bool>? _sub;

  /// Public plugin name / extra key for this plugin, accessible without an
  /// instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:offline';

  @override
  String get name => pluginName;

  /// Number of requests currently parked in the queue. Read-only, for
  /// inspection/testing.
  ///
  /// 当前挂在队列里的请求数。只读，供检查/测试用。
  int get pending => _queue.length;

  // ── Per-request override resolution ─────────────────────────────────────────

  DiomanOfflineOptions? _overrideObject(RequestOptions config) {
    final v = config.extra[name];
    return v is DiomanOfflineOptions ? v : null;
  }

  DioException _reject(DiomanOfflineReason reason, RequestOptions options) =>
      DioException(
        requestOptions: options,
        // Default DioExceptionType.unknown + no response ⇒ DiomanRetry's
        // default shouldRetry won't retry an offline rejection.
        error: DiomanOfflineException(reason),
        message: '[offline] ${reason.name}',
      );

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final o = _overrideObject(options);

    final $enabled = o?.enabled ?? enabled;
    if (!$enabled) return handler.next(options);

    final $shouldQueue = o?.shouldQueue ?? _shouldQueue;
    if ($shouldQueue != null && !$shouldQueue(options)) {
      return handler.next(options);
    }

    // Online → nothing to queue; let it fly.
    if (_isOnline()) return handler.next(options);

    // Offline → park it. Evict the oldest first if the queue is full.
    final $maxSize = o?.maxQueueSize ?? maxQueueSize;
    if ($maxSize > 0) {
      while (_queue.length >= $maxSize) {
        final oldest = _queue.removeAt(0);
        oldest.timer?.cancel();
        oldest.handler.reject(_reject(DiomanOfflineReason.queueFull, oldest.options));
      }
    }

    final entry = _Queued(handler, options);
    final $maxWait = o?.maxWait ?? maxWait;
    if ($maxWait != null) {
      entry.timer = Timer($maxWait, () {
        // Remove-then-reject, guarded by the remove: if flush/eviction already
        // took this entry, `remove` returns false and we do nothing.
        if (_queue.remove(entry)) {
          entry.handler.reject(_reject(DiomanOfflineReason.timeout, options));
        }
      });
    }
    _queue.add(entry);
    // Deliberately NOT calling handler.next — the request is now parked.
  }

  /// Replays every queued request by resuming it down the rest of the chain
  /// (`handler.next`), then clears the queue. Called automatically on a `true`
  /// connectivity event; safe to call by hand. A request that fails on replay
  /// (still-flaky network) simply errors to its caller — it already passed
  /// this plugin, so it is not re-queued.
  ///
  /// 重放所有入队请求：用`handler.next`把每个请求恢复到剩下的链上，然后清空
  /// 队列。收到`true`连通性事件时自动调用；也可手动调用。重放时失败（网络还抖）
  /// 的请求会正常把错误抛给调用方——它已过本插件，不会再入队。
  void flush() {
    if (_queue.isEmpty) return;
    final drained = List<_Queued>.of(_queue);
    _queue.clear();
    for (final entry in drained) {
      entry.timer?.cancel();
      entry.handler.next(entry.options);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    final drained = List<_Queued>.of(_queue);
    _queue.clear();
    for (final entry in drained) {
      entry.timer?.cancel();
      entry.handler.reject(_reject(DiomanOfflineReason.disposed, entry.options));
    }
  }
}
