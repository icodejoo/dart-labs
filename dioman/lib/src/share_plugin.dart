import 'dart:async';
import 'package:dio/dio.dart';
import 'key_plugin.dart';
import 'dioman_plugin.dart';
import 'replay_support.dart';
import 'request_claims.dart';

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

/// start 策略下登记等待的 follower：保存它的 options 和请求阶段 handler，
/// 首发取消时可让它带着自己的 options 重新走下游整条链。
class _Follower {
  _Follower(this.options, this.handler);

  /// follower 自己的请求选项（未经下游插件处理，body 未消费）。
  final RequestOptions options;

  /// follower 停在 share 处的请求阶段 handler。
  final RequestInterceptorHandler handler;

  /// 是否已被提升为新首发；提升后不再由共享结果的回调完成 [handler]。
  bool promoted = false;
}

class _Entry {
  _Entry(this.key, this._detach) : completer = Completer<Response<dynamic>>() {
    // A lone leader (no followers ever attached) or an already-settled
    // completer under end/race can complete with an error that nobody
    // listens to — that raises an unhandled zone error. `ignore()` only
    // marks this future as intentionally unhandled; real listeners attached
    // elsewhere (via .then) still receive the value/error independently.
    completer.future.ignore();
  }

  /// 请求key，结算时据此从活跃表摘除。
  ///
  /// Request key, used to detach this entry from the active table on settle.
  final String key;

  /// 结算后把自己从活跃表摘除的回调。
  ///
  /// Callback that detaches this entry from the active table once settled.
  final void Function(_Entry entry) _detach;

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

  /// start 策略仍等待结果的 follower，用于首发取消后让其中一个重新入链接手。
  final followers = <_Follower>[];

  /// 是否已结算。
  bool get isSettled => completer.isCompleted;

  /// 以成功响应结算。存一份脱离 leader 后续改动的快照，已结算则忽略。
  void complete(Response<dynamic> response) {
    _detach(this);
    if (isSettled) return;
    completer.complete(copyResponse(response, response.requestOptions));
  }

  /// 以失败结算，已结算则忽略。
  void completeError(DioException error) {
    _detach(this);
    if (isSettled) return;
    completer.completeError(error);
  }
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

  // policy=retry 内部重试用的传输层：绑定宿主 Dio 后借用其 adapter/transformer，
  // 未绑定时退回无拦截器的裸 Dio，重试不会重新进入本链路。在 [dispose] 中释放。
  final _replay = ReplayClient();

  /// Binds the host [Dio] this plugin is installed on, so `policy: retry`
  /// re-issues reuse its adapter/transformer and hand a recovered result to
  /// the interceptors after this plugin. [Dioman.install] / [DiomanHandle] bind
  /// it automatically; set it by hand only when wiring the chain yourself.
  /// `null` unbinds.
  ///
  /// 绑定本插件所在的宿主[Dio]，让`policy: retry`的内部重试复用它的
  /// adapter/transformer，并把恢复成功的结果交给排在本插件之后的拦截器。
  /// [Dioman.install]/[DiomanHandle]会自动绑定，只有自己手动拼链时才需要设置。
  /// 传`null`解绑。
  set dio(Dio? value) => _replay.bind(value);

  // 旧接线接口的兼容计数：结算责任现在按请求登记（见 RequestClaims），这个
  // 计数不再影响任何结算行为。
  int _legacySettlers = 0;

  /// No longer needed: settlement responsibility is now registered per
  /// request by [DiomanAuth]/[DiomanRetry] themselves. Kept as a compatibility
  /// no-op counter that no longer influences settlement.
  ///
  /// 已不再需要：结算责任现在由[DiomanAuth]/[DiomanRetry]按请求自行登记。
  /// 仅作兼容保留，计数不再影响任何结算行为。
  @Deprecated('Settlement responsibility is registered per request now; '
      'this call has no effect.')
  void registerDownstreamSettler() => _legacySettlers++;

  /// Compatibility counterpart of [registerDownstreamSettler]; no longer
  /// influences settlement.
  ///
  /// [registerDownstreamSettler]的兼容配套，不再影响任何结算行为。
  @Deprecated('Settlement responsibility is registered per request now; '
      'this getter has no effect on behavior.')
  bool get hasMultipleDownstreamSettlers => _legacySettlers > 1;

  /// Explicitly settles the shared entry for [key] with [response] (success)
  /// or [error] (failure), regardless of policy or outstanding downstream
  /// claims, and detaches it so a later caller for [key] starts fresh. A no-op
  /// if there's no active entry for [key] or it was already settled.
  ///
  /// 用[response]（成功）或[error]（失败）显式结算[key]对应的共享entry，不管
  /// 策略和下游是否还有未交出的认领，并把它摘除，之后同key的调用方重新开始。
  /// 没有活跃entry或已结算时是no-op。
  void settle(String key, {Response<dynamic>? response, DioException? error}) {
    final entry = _active[key];
    if (entry == null) return;
    if (response != null) {
      entry.complete(response);
    } else if (error != null) {
      entry.completeError(error);
    } else {
      _detach(entry);
    }
  }

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

    // 同一个 RequestOptions 重新分发时，清掉上一轮的 follower 标记。
    options.extra.remove(kJoinedKey);
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

  /// 新建并登记一个共享entry。
  _Entry _newEntry(String key) {
    final entry = _Entry(key, _detach);
    _active[key] = entry;
    return entry;
  }

  /// 让 [options] 成为 [entry] 的参与者：挂上entry，并建立结算认领登记簿——
  /// 下游（auth/retry）认领后，最终结果由登记簿清空时统一结算。
  void _adopt(RequestOptions options, _Entry entry) {
    options.extra[_kEntry] = entry;
    options.extra[kClaimsKey] = RequestClaims()
      ..onFinal = ((response, error) => _offer(entry, options, response, error))
      ..checkLoser = (() => _loserOf(entry, options));
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
      final entry = _newEntry(key);
      _adopt(options, entry);
      if ($resolved.policy == DiomanSharePolicy.retry) {
        options.extra[_kRetriesLeft] = $resolved.retries;
        options.extra[_kInterval] = $resolved.interval;
      }
      handler.next(options);
    } else {
      // callFollowingResponseInterceptor: true — a follower resolving here
      // (onRequest side) must still run onResponse of everything installed
      // after share (cancel, loading, auth, retry, log, normalize),
      // same as the leader's own response does, so e.g. DiomanNormalize
      // still unwraps the envelope for the follower too.
      _markJoined(options);
      final follower = _Follower(options, handler);
      existing.followers.add(follower);
      // 被提升为新首发后 handler 由下游链路完成，这里不能再完成一次。
      existing.completer.future.then(
        (r) {
          if (!follower.promoted) {
            handler.resolve(copyResponse(r, options), true);
          }
        },
        onError: (Object e) {
          if (!follower.promoted) {
            handler.reject(copyError(e, options), true);
          }
        },
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
    final entry = _active[key] ?? _newEntry(key);
    entry.seq++;
    options.extra[_kSeq] = entry.seq;
    _adopt(options, entry);
    handler.next(options); // everyone proceeds; settlement gated by seq match
  }

  // race: everyone proceeds, first success (or last error) wins for all —
  // including callers whose own attempt lost the race.
  void _handleRace(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String key,
  ) {
    final entry = _active[key] ?? _newEntry(key);
    entry.inFlight++;
    options.extra[_kSeq] = entry.inFlight; // unique id per in-flight request
    _adopt(options, entry);
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

    switch (_policyOf(opts)) {
      case DiomanSharePolicy.end:
        // Superseded by a newer request — deliver the eventual winner's
        // result instead of this stale one.
        if (opts.extra[_kSeq] != entry.seq) {
          return _joinFromResponse(entry, opts, handler);
        }
      case DiomanSharePolicy.race:
        // Another in-flight attempt already won the race.
        if (entry.isSettled) return _joinFromResponse(entry, opts, handler);
      default: // start, retry
    }
    _finishOrDefer(entry, opts, response: response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final opts = err.requestOptions;
    final entry = opts.extra[_kEntry] as _Entry?;
    if (entry == null) return handler.next(err);

    // 落败者被取消：不等胜出结果，直接以取消错误退出（Dio 对 cancel 类错误
    // 不再套取消竞争，等待会让调用者取消后一直不返回）。
    if (err.type == DioExceptionType.cancel && _leaveOnCancel(entry, opts)) {
      return handler.next(err);
    }

    switch (_policyOf(opts)) {
      case DiomanSharePolicy.retry:
        // 内部重试是异步的，自己负责 handler 恰好完成一次。
        unawaited(_retryPolicyError(err, opts, entry, handler));
        return;

      case DiomanSharePolicy.end:
        if (opts.extra[_kSeq] != entry.seq) {
          return _joinFromError(entry, opts, handler);
        }

      case DiomanSharePolicy.race:
        if (entry.isSettled) return _joinFromError(entry, opts, handler);
        // 没有下游认领时当场判断是不是最后一个失败的在途请求；有认领则等最终
        // 结果确定后由 [_offer] 计数。
        if (!_hasClaims(opts) && entry.inFlight > 1) {
          entry.inFlight--;
          return _joinFromError(entry, opts, handler);
        }

      default: // start
    }
    _finishOrDefer(entry, opts, error: err);
    handler.next(err);
  }

  /// policy=retry 的内部重试：调用方看不到重试过程。成功后把结果交给排在本
  /// 插件之后的拦截器（见 [ReplayClient.runDownstream]），再终结链路。
  Future<void> _retryPolicyError(
    DioException err,
    RequestOptions opts,
    _Entry entry,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      var left = opts.extra[_kRetriesLeft] as int? ?? 0;
      final $interval = opts.extra[_kInterval] as Duration? ?? interval;
      final token = opts.cancelToken;
      Response<dynamic>? success;
      Object lastError = err;
      // 取消类错误不重试；循环里每一轮都检查取消，等待也可被取消打断。
      while (left > 0 && err.type != DioExceptionType.cancel) {
        if (token?.isCancelled == true) {
          lastError = token!.cancelError ?? lastError;
          break;
        }
        left--;
        opts.extra[_kRetriesLeft] = left;
        await cancellableDelay($interval, token);
        if (token?.isCancelled == true) {
          lastError = token!.cancelError ?? lastError;
          break;
        }
        if (!prepareForReplay(opts)) break; // body 无法重放
        try {
          success = await _replay.fetch(opts);
          break;
        } catch (e) {
          lastError = e;
        }
      }

      if (success != null) {
        // 恢复成功：结算用下游处理之前的快照，再让下游处理并终结链路。
        return await _replay.finishRecovered(this, opts, success, handler);
      }
      final finalErr = lastError is DioException
          ? lastError
          : DioException(requestOptions: opts, error: lastError);
      _finishOrDefer(entry, opts, error: finalErr);
      handler.next(finalErr);
    } catch (e, s) {
      // 重放准备或下游异常也要结算共享结果，避免只结束首发而悬挂跟随者。
      if (!handler.isCompleted) {
        final failure =
            DioException(requestOptions: opts, error: e, stackTrace: s);
        _finishOrDefer(entry, opts, error: failure);
        handler.next(failure);
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// 把 [entry] 从活跃表摘除——仅当它还是当前登记的那个entry时才摘除
  /// （新一轮请求可能已经装上了一个新entry）。
  void _detach(_Entry entry) {
    if (identical(_active[entry.key], entry)) _active.remove(entry.key);
  }

  /// 本请求的策略，缺省按 start。
  DiomanSharePolicy _policyOf(RequestOptions opts) =>
      opts.extra[_kPolicy] as DiomanSharePolicy? ?? DiomanSharePolicy.start;

  /// 本请求上是否还有下游认领者没交出结果。
  bool _hasClaims(RequestOptions opts) => claimsOf(opts)?.hasOwners ?? false;

  /// 本请求在 share 这一层拿到了结果：没有下游认领者就当场结算；有则推迟，
  /// 由认领者交出最终结果时经登记簿结算。[force] 为 true 时无视认领者直接结算
  /// （本插件自己终结链路时用）。
  void _finishOrDefer(
    _Entry entry,
    RequestOptions opts, {
    Response<dynamic>? response,
    DioException? error,
    bool force = false,
  }) {
    final claims = claimsOf(opts);
    if (claims == null) {
      _offer(entry, opts, response, error);
    } else if (force || !claims.hasOwners) {
      claims.finish(response: response, error: error);
    }
  }

  /// 请求的最终结果确定后，按策略决定是否用它结算 [entry]：
  /// end 只认最新序号；race 已有胜者或失败尚有在途请求时不结算；其余直接结算。
  /// 返回非 null 表示该请求落败，值是等待胜出结果的 Future（已绑定 [opts]）。
  Future<Response<dynamic>>? _offer(
    _Entry entry,
    RequestOptions opts,
    Response<dynamic>? response,
    DioException? error,
  ) {
    if (error?.type == DioExceptionType.cancel &&
        _policyOf(opts) == DiomanSharePolicy.start &&
        _promoteFollower(entry)) {
      return null;
    }
    switch (_policyOf(opts)) {
      case DiomanSharePolicy.end:
        if (opts.extra[_kSeq] != entry.seq) return _yieldToWinner(entry, opts);
      case DiomanSharePolicy.race:
        if (entry.isSettled) return _yieldToWinner(entry, opts);
        if (error != null && --entry.inFlight > 0) {
          return _yieldToWinner(entry, opts);
        }
      default:
    }
    if (response != null) {
      entry.complete(response);
    } else if (error != null) {
      entry.completeError(error);
    }
    return null;
  }

  /// 首发取消后，选第一个 cancelToken 未取消的 follower 成为新首发：清掉它的
  /// joined 标记、重新挂上 [entry]，再 `next` 让它带着自己的 options 走完下游整条
  /// 链（cancel/auth/retry 照常生效）。它的最终结果经登记簿回到 [_offer] 结算；
  /// 若它也被取消则递归接手下一个。返回 false 表示没有存活的 follower。
  bool _promoteFollower(_Entry entry) {
    final live = entry.followers
        .where((f) => f.options.cancelToken?.isCancelled != true)
        .firstOrNull;
    if (live == null) return false;
    entry.followers.remove(live);
    live.promoted = true;
    live.options.extra.remove(kJoinedKey);
    _adopt(live.options, entry);
    live.handler.next(live.options);
    return true;
  }

  /// 被取消的 [opts] 若在仲裁中已落败（end 被取代、race 已有胜者或仍有其它在途
  /// 请求），就脱离 [entry]（race 补扣在途计数）并返回 true；否则返回 false，
  /// 仍按普通失败结算。
  bool _leaveOnCancel(_Entry entry, RequestOptions opts) {
    switch (_policyOf(opts)) {
      case DiomanSharePolicy.end:
        if (opts.extra[_kSeq] == entry.seq) return false;
      case DiomanSharePolicy.race:
        if (!entry.isSettled) {
          if (entry.inFlight <= 1) return false;
          entry.inFlight--;
        }
      default:
        return false;
    }
    _markJoined(opts);
    return true;
  }

  /// 预检 [opts] 是否已出局：end 被取代、race 已有胜者时返回胜出结果的 Future。
  Future<Response<dynamic>>? _loserOf(_Entry entry, RequestOptions opts) {
    switch (_policyOf(opts)) {
      case DiomanSharePolicy.end:
        if (opts.extra[_kSeq] != entry.seq) return _yieldToWinner(entry, opts);
      case DiomanSharePolicy.race:
        if (entry.isSettled) return _yieldToWinner(entry, opts);
      default:
    }
    return null;
  }

  /// 让落败的 [own] 改为等待 [entry] 的最终共享结果，得到绑定 [own] 的独立副本
  /// （失败则以绑定 [own] 的异常完成）。
  Future<Response<dynamic>> _yieldToWinner(_Entry entry, RequestOptions own) {
    _markJoined(own);
    return entry.completer.future.then(
      (r) => copyResponse(r, own),
      onError: (Object e) => throw copyError(e, own),
    );
  }

  /// 标记 [own] 为 follower / 落败者：结果由 leader 结算，下游不得再自行恢复，
  /// 也不再被当作 entry 的参与者。
  void _markJoined(RequestOptions own) {
    own.extra[kJoinedKey] = true;
    own.extra.remove(_kEntry);
    // 落败者不再向entry提交结果（其认领登记簿照常注销，只是不再结算）。
    claimsOf(own)
      ?..onFinal = null
      ..checkLoser = null;
  }

  /// 响应阶段：把 [entry] 最终的共享结果转交给 [handler]，每个调用方拿到
  /// 绑定自己 RequestOptions 的独立 Response / 异常。
  ///
  /// 成功 next 继续跑后面的响应阶段（normalize 等照常处理这份独立副本）；
  /// 失败 reject(callFollowing) 继续跑错误阶段。
  void _joinFromResponse(
    _Entry entry,
    RequestOptions own,
    ResponseInterceptorHandler handler,
  ) {
    _markJoined(own);
    entry.completer.future.then(
      (r) => handler.next(copyResponse(r, own)),
      onError: (Object e) => handler.reject(copyError(e, own), true),
    );
  }

  /// 错误阶段：同 [_joinFromResponse]，但错误阶段的 handler 签名不同——
  /// 成功经 [ReplayClient.finishRecovered] 收尾（下游照常清理再终结），失败用
  /// next 交给后续错误阶段。
  void _joinFromError(
    _Entry entry,
    RequestOptions own,
    ErrorInterceptorHandler handler,
  ) {
    _markJoined(own);
    entry.completer.future.then(
      // 走与首次成功一致的收尾：下游的 onResponse 照常清理（loading、cancel、
      // auth 认领等），再终结。
      (r) => _replay.finishRecovered(this, own, copyResponse(r, own), handler),
      onError: (Object e) => handler.next(copyError(e, own)),
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
    for (final entry in _active.values.toList()) {
      if (!entry.isSettled) {
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
    _replay.dispose();
  }
}
