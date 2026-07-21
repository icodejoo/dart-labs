import 'dart:async';
import 'package:dio/dio.dart';
import 'key_plugin.dart';
import 'dioman_plugin.dart';

/// How concurrent requests sharing the same key are handled.
///
/// 同key并发请求的处理策略。
enum DiomanSharePolicy {
  /// First request proceeds; all other callers wait for its result.
  /// HTTP is issued once.
  ///
  /// 第一个请求真正发出；其余调用方都等它的结果。HTTP只发一次。
  start,

  /// Every new request supersedes the previous one. All callers wait for the
  /// **last** request's result.
  ///
  /// 每个新请求都取代前一个。所有调用方等的是**最后一个**请求的结果。
  end,

  /// All callers issue their own HTTP request; the **first to succeed** wins
  /// and its response is delivered to everyone. If all fail, the last error
  /// propagates.
  ///
  /// 每个调用方都各自发出HTTP请求；**第一个成功**的胜出，结果分发给所有人。
  /// 若全部失败，则传播最后一个错误。
  race,

  /// Shared promise with internal retry on failure. Callers never see retries.
  ///
  /// 共享一个promise，失败时内部自行重试，调用方看不到重试过程。
  retry,

  /// Opt out — request proceeds independently (no sharing).
  ///
  /// 不共享——请求各自独立发出。
  none,
}

class _Entry {
  _Entry() : completer = Completer<Response<dynamic>>() {
    // A lone leader (no followers ever attached) or an already-settled
    // completer under end/race can complete with an error that nobody
    // listens to — that raises an unhandled zone error. `ignore()` only
    // marks this future as intentionally unhandled; real listeners attached
    // elsewhere (via .then) still receive the value/error independently.
    completer.future.ignore();
  }

  /// Settles with the shared result for every caller keyed to this entry.
  ///
  /// 为所有绑定到这个entry的调用方，统一结算出共享结果。
  final Completer<Response<dynamic>> completer;

  /// Sequence counter used by [DiomanSharePolicy.end] to detect the latest caller.
  ///
  /// [DiomanSharePolicy.end]用来识别"最新一个调用方"的序号计数器。
  int seq = 0;

  /// In-flight counter used by [DiomanSharePolicy.race].
  ///
  /// [DiomanSharePolicy.race]用的在途请求计数器。
  int inFlight = 0;
}

/// Per-request override for [DiomanShare], read from `extra['dioman:share']`.
///
/// [DiomanShare]的单请求覆盖，从`extra['dioman:share']`读取。
class DiomanShareOptions {
  const DiomanShareOptions(
      {this.enabled, this.policy, this.retries, this.interval});

  /// `false` opts this request out of sharing entirely (same as
  /// [DiomanSharePolicy.none]). `null` (default) inherits [DiomanShare.enabled].
  ///
  /// `false`表示本次请求完全不参与共享（等价于[DiomanSharePolicy.none]）。
  /// `null`（默认）沿用[DiomanShare.enabled]。
  final bool? enabled;

  /// Overrides the plugin's default policy for this request only.
  ///
  /// 仅本次请求覆盖插件默认的策略。
  final DiomanSharePolicy? policy;

  /// Overrides the plugin's default `retries` — only takes effect when this
  /// call is the one that establishes a new shared entry (the "leader");
  /// followers joining an existing entry inherit whatever the leader
  /// resolved to.
  ///
  /// 覆盖插件默认的`retries`——只在本次调用是新建共享entry的那一个（"leader"）
  /// 时才生效；加入已有entry的follower沿用leader当时解析出的值。
  final int? retries;

  /// Overrides the plugin's default `interval` — same leader-establishes
  /// caveat as [retries].
  ///
  /// 覆盖插件默认的`interval`——跟[retries]一样，只有leader建entry时才生效。
  final Duration? interval;
}

/// Deduplicates or shares concurrent requests with the **same key**
/// (produced by [DiomanKey]) using one of four strategies.
///
/// 用四种策略之一，对**同key**（由[DiomanKey]生成）的并发请求做去重/共享。
///
/// **Install [DiomanKey] first** — without a key, every request
/// is treated as independent (policy = none).
///
/// **须先安装[DiomanKey]**——没有key时每个请求都视为独立（等价policy=none）。
///
/// Per-request override via `options.extra['dioman:share']`:
/// - `const DiomanShareOptions(enabled: false)` → skip sharing
/// - `const DiomanShareOptions(policy: SharePolicy.race)` → use that policy for this request
///
/// ```dart
/// dio.interceptors
///   ..add(DiomanKey())
///   ..add(DiomanShare(policy: SharePolicy.start));
///
/// // Override per request:
/// dio.get('/data', options: Options(extra: {'dioman:share': const DiomanShareOptions(policy: SharePolicy.race)}));
/// dio.get('/data', options: Options(extra: {'dioman:share': const DiomanShareOptions(enabled: false)})); // bypass
/// ```
class DiomanShare extends DiomanPlugin {
  DiomanShare({
    this.policy = DiomanSharePolicy.start,
    this.retries = 3,
    this.interval = Duration.zero,
    this.enabled = true,
  });

  /// `false` disables the plugin entirely — every request passes through
  /// independently, never shared/deduped.
  ///
  /// `false`时插件整体失效——所有请求各自独立通过，永不共享/去重。
  final bool enabled;

  /// Default sharing policy.
  ///
  /// 默认的共享策略。
  final DiomanSharePolicy policy;

  /// Default retry count for [DiomanSharePolicy.retry].
  ///
  /// [DiomanSharePolicy.retry]的默认重试次数。
  final int retries;

  /// Default delay between [DiomanSharePolicy.retry] attempts.
  ///
  /// [DiomanSharePolicy.retry]每次重试之间的默认延迟。
  final Duration interval;

  /// Active shared entries, keyed by request key.
  ///
  /// 当前活跃的共享entry，按请求key索引。
  final _active = <String, _Entry>{};

  // Number of downstream plugins (DiomanRetry / DiomanAuth, via their own
  // `share:` constructor param) that will call [settle] themselves once
  // THEY reach this request's true final outcome. > 0 means this plugin's
  // own onResponse/onError must NOT settle the entry on the first
  // response/error — it would otherwise deliver a pre-retry/pre-refresh
  // result to every waiter, before the downstream plugin ever gets a
  // chance to improve on it (this plugin sits BEFORE DiomanRetry/DiomanAuth
  // in the canonical chain, so its onResponse/onError always runs first).
  int _pendingSettlers = 0;

  /// Registers a downstream plugin that will call [settle] itself instead
  /// of letting this plugin settle automatically. Called by DiomanRetry's /
  /// DiomanAuth's own constructor when given this instance via their
  /// `share:` param — not meant to be called directly.
  ///
  /// 登记一个会自行调用[settle]的下游插件，而不是让本插件自动结算。由
  /// DiomanRetry/DiomanAuth自己的构造函数在收到本实例（通过它们的`share:`
  /// 参数）时调用——不供直接调用。
  void registerDownstreamSettler() => _pendingSettlers++;

  /// Whether more than one downstream plugin is registered. DiomanAuth uses
  /// this to decide whether it must settle on hand-off itself (`false` —
  /// nothing else is registered) or can defer to a later-registered plugin
  /// (`true` — namely DiomanRetry, which always runs after DiomanAuth in the
  /// canonical chain and always settles unconditionally).
  ///
  /// 是否登记了多个下游插件。DiomanAuth用这个来判断交接时是否要自己结算
  /// （`false`——没有其它登记者）还是可以交给后登记的插件（`true`——也就是
  /// canonical链条上总是排在DiomanAuth之后、且总会无条件结算的DiomanRetry）。
  bool get hasMultipleDownstreamSettlers => _pendingSettlers > 1;

  /// Explicitly settles the shared entry for [key] with [response] (success)
  /// or [error] (failure). Called by a downstream plugin (DiomanRetry,
  /// DiomanAuth) once it reaches the request's TRUE final outcome, after
  /// this plugin deferred its own automatic settlement — see
  /// [registerDownstreamSettler]. A no-op if the entry was already settled
  /// by someone else, or if there's no active entry for [key].
  ///
  /// 用[response]（成功）或[error]（失败）显式结算[key]对应的共享entry。
  /// 由下游插件（DiomanRetry、DiomanAuth）在自己拿到请求的**真正**最终结果后
  /// 调用，前提是本插件已经推迟了自动结算——见[registerDownstreamSettler]。
  /// 若entry已被别人结算过，或[key]没有活跃entry，则是no-op。
  void settle(String key, {Response<dynamic>? response, DioException? error}) {
    final entry = _active[key];
    if (entry == null) return;
    _settle(key, entry);
    if (entry.completer.isCompleted) return;
    if (response != null) {
      entry.completer.complete(response);
    } else if (error != null) {
      entry.completer.completeError(error);
    }
  }

  // Bare Dio reused for policy=retry re-issues — no interceptors, so retries
  // never re-enter this chain. Lazily created and reused across retries (and
  // across the retry loop's iterations) instead of a fresh `Dio()` each time,
  // so the HttpClient / connection pool isn't reallocated per attempt. Closed
  // in [dispose].
  Dio? _retryDio;
  Dio get _retry => _retryDio ??= Dio();

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:share';
  static const _kEntry = '$pluginName:entry';
  static const _kSeq = '$pluginName:seq';
  static const _kPolicy = '$pluginName:policy';
  static const _kRetriesLeft = '$pluginName:retriesLeft';
  static const _kInterval = '$pluginName:interval';

  @override
  String get name => pluginName;

  // ── Request side ──────────────────────────────────────────────────────────

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final override = options.extra[name];
    final $resolved = _resolve(override);
    if (!$resolved.enabled) return handler.next(options);

    final key = options.extra[kKey] as String?;
    if (key == null) return handler.next(options); // no key → pass through

    options.extra[_kPolicy] = $resolved.policy;

    switch ($resolved.policy) {
      case DiomanSharePolicy.none:
        return handler.next(options);

      case DiomanSharePolicy.start:
      case DiomanSharePolicy.retry:
        _handleStart(options, handler, key, $resolved);

      case DiomanSharePolicy.end:
        _handleEnd(options, handler, key);

      case DiomanSharePolicy.race:
        _handleRace(options, handler, key);
    }
  }

  // start / retry: first caller proceeds, rest wait
  void _handleStart(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String key,
    ({
      bool enabled,
      DiomanSharePolicy policy,
      int retries,
      Duration interval
    }) $resolved,
  ) {
    final existing = _active[key];
    if (existing == null) {
      final entry = _Entry();
      _active[key] = entry;
      options.extra[_kEntry] = entry;
      if ($resolved.policy == DiomanSharePolicy.retry) {
        options.extra[_kRetriesLeft] = $resolved.retries;
        options.extra[_kInterval] = $resolved.interval;
      }
      handler.next(options);
    } else {
      // callFollowingResponseInterceptor: true — a follower resolving here
      // (onRequest side) must still run onResponse of everything installed
      // after share (mock, cancel, loading, auth, retry, log, normalize),
      // same as the leader's own response does, so e.g. DiomanNormalize
      // still unwraps the envelope for the follower too.
      existing.completer.future.then(
        (r) => handler.resolve(r, true),
        onError: (Object e) => handler.reject(e as DioException, true),
      );
    }
  }

  // end: every caller bumps the sequence. Only the highest-seq response
  // settles the shared promise; every other caller (older or superseded)
  // waits for that settlement instead of returning its own stale result.
  void _handleEnd(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String key,
  ) {
    final entry = _active[key] ?? _Entry();
    _active[key] = entry;
    entry.seq++;
    options.extra[_kSeq] = entry.seq;
    options.extra[_kEntry] = entry;
    handler.next(options); // everyone proceeds; settlement gated by seq match
  }

  // race: everyone proceeds, first success (or last error) wins for all —
  // including callers whose own attempt lost the race.
  void _handleRace(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String key,
  ) {
    final entry = _active[key] ?? _Entry();
    _active[key] = entry;
    entry.inFlight++;
    options.extra[_kSeq] = entry.inFlight; // unique id per in-flight request
    options.extra[_kEntry] = entry;
    handler.next(options);
  }

  // ── Response side ─────────────────────────────────────────────────────────

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    final opts = response.requestOptions;
    // Read the entry directly off this request rather than re-looking it up
    // in `_active` — the shared entry may already have been removed (settled
    // by a sibling) by the time a superseded/losing caller's response lands.
    final entry = opts.extra[_kEntry] as _Entry?;
    if (entry == null) return handler.next(response);

    final key = opts.extra[kKey] as String?;
    final p =
        opts.extra[_kPolicy] as DiomanSharePolicy? ?? DiomanSharePolicy.start;

    switch (p) {
      case DiomanSharePolicy.end:
        final mySeq = opts.extra[_kSeq] as int?;
        if (mySeq == entry.seq) {
          if (_pendingSettlers == 0) {
            _settle(key, entry);
            if (!entry.completer.isCompleted) entry.completer.complete(response);
          }
          return handler.next(response);
        }
        // Superseded by a newer request — deliver the eventual winner's
        // result instead of this stale one.
        return _awaitEntry(entry, handler);

      case DiomanSharePolicy.race:
        if (!entry.completer.isCompleted) {
          if (_pendingSettlers == 0) {
            _settle(key, entry);
            entry.completer.complete(response);
          }
          return handler.next(response);
        }
        // Another in-flight attempt already won the race.
        return _awaitEntry(entry, handler);

      default: // start, retry
        if (_pendingSettlers == 0) {
          _settle(key, entry);
          if (!entry.completer.isCompleted) entry.completer.complete(response);
        }
        handler.next(response);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final entry = opts.extra[_kEntry] as _Entry?;
    if (entry == null) return handler.next(err);

    final key = opts.extra[kKey] as String?;
    final p =
        opts.extra[_kPolicy] as DiomanSharePolicy? ?? DiomanSharePolicy.start;

    switch (p) {
      case DiomanSharePolicy.retry:
        var left = opts.extra[_kRetriesLeft] as int? ?? 0;
        final $interval = opts.extra[_kInterval] as Duration? ?? interval;
        Response<dynamic>? success;
        Object lastError = err;
        while (left > 0) {
          left--;
          opts.extra[_kRetriesLeft] = left;
          if ($interval > Duration.zero) await Future<void>.delayed($interval);
          try {
            success = await _retry.fetch<dynamic>(opts);
            break;
          } catch (e) {
            lastError = e;
          }
        }
        _settle(key, entry);
        if (success != null) {
          if (!entry.completer.isCompleted) entry.completer.complete(success);
          return handler.resolve(success);
        }
        final finalErr = lastError is DioException
            ? lastError
            : DioException(requestOptions: opts, error: lastError);
        if (!entry.completer.isCompleted)
          entry.completer.completeError(finalErr);
        return handler.next(finalErr);

      case DiomanSharePolicy.end:
        final mySeq = opts.extra[_kSeq] as int?;
        if (mySeq == entry.seq) {
          if (_pendingSettlers == 0) {
            _settle(key, entry);
            if (!entry.completer.isCompleted) entry.completer.completeError(err);
          }
          return handler.next(err);
        }
        return _awaitEntry(entry, handler);

      case DiomanSharePolicy.race:
        entry.inFlight--;
        if (!entry.completer.isCompleted && entry.inFlight <= 0) {
          if (_pendingSettlers == 0) {
            _settle(key, entry);
            entry.completer.completeError(err);
          }
          return handler.next(err);
        }
        return _awaitEntry(entry, handler);

      default: // start
        if (_pendingSettlers == 0) {
          _settle(key, entry);
          if (!entry.completer.isCompleted) entry.completer.completeError(err);
        }
        handler.next(err);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Removes [entry] from `_active[key]` — but only if it's still the entry
  /// registered there (a new burst may already have installed a fresh one).
  ///
  /// 把[entry]从`_active[key]`移除——但仅当它还是当前登记的那个entry时才移除
  /// （新一轮请求可能已经装上了一个新entry）。
  void _settle(String? key, _Entry entry) {
    if (key != null && identical(_active[key], entry)) _active.remove(key);
  }

  /// Delivers whatever [entry]'s completer eventually settles with to this
  /// caller, instead of this caller's own (superseded/losing) result.
  ///
  /// 把[entry]的completer最终结算出的结果交给这个调用方，而不是它自己
  /// （被取代/落败）的结果。
  void _awaitEntry(_Entry entry, dynamic handler) {
    entry.completer.future.then(
      (r) => handler.resolve(r),
      onError: (Object e) => handler.reject(e as DioException, true),
    );
  }

  /// Merges the per-request [override] with the plugin's own defaults.
  ///
  /// 把单请求[override]跟插件自身默认值合并。
  ({bool enabled, DiomanSharePolicy policy, int retries, Duration interval})
      _resolve(dynamic override) {
    final o = override is DiomanShareOptions ? override : null;
    return (
      enabled: o?.enabled ?? enabled,
      policy: o?.policy ?? policy,
      retries: o?.retries ?? retries,
      interval: o?.interval ?? interval,
    );
  }

  @override
  void dispose() {
    // Complete any waiters before dropping the entries — a bare `_active.clear()`
    // would leave followers attached to `entry.completer.future` hanging
    // forever, since nothing else ever settles those completers.
    for (final entry in _active.values) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(
          DioException(
            requestOptions: RequestOptions(path: ''),
            message:
                '[share] plugin disposed before the shared request settled',
          ),
        );
      }
    }
    _active.clear();
    _retryDio?.close(force: true);
    _retryDio = null;
  }
}
