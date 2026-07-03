import 'dart:async';
import 'package:dio/dio.dart';
import 'build_key_plugin.dart';
import 'dio_plugin.dart';

/// How concurrent requests sharing the same key are handled.
enum SharePolicy {
  /// First request proceeds; all other callers wait for its result.
  /// HTTP is issued once.
  start,

  /// Every new request supersedes the previous one. All callers wait for the
  /// **last** request's result.
  end,

  /// All callers issue their own HTTP request; the **first to succeed** wins
  /// and its response is delivered to everyone. If all fail, the last error
  /// propagates.
  race,

  /// Shared promise with internal retry on failure. Callers never see retries.
  retry,

  /// Opt out — request proceeds independently (no sharing).
  none,
}

class _Entry {
  _Entry() : completer = Completer<Response<dynamic>>();
  final Completer<Response<dynamic>> completer;
  int seq = 0;       // used by [end]
  int inFlight = 0;  // used by [race]
}

/// Deduplicates or shares concurrent requests with the **same key**
/// (produced by [BuildKeyPlugin]) using one of four strategies.
///
/// **Install [BuildKeyPlugin] first** — without a key, every request
/// is treated as independent (policy = none).
///
/// Per-request override via `options.extra['share']`:
/// - `false` / `SharePolicy.none` → skip sharing
/// - A [SharePolicy] value → use that policy for this request
///
/// ```dart
/// dio.interceptors
///   ..add(BuildKeyPlugin())
///   ..add(SharePlugin(policy: SharePolicy.start));
///
/// // Override per request:
/// dio.get('/data', options: Options(extra: {'share': SharePolicy.race}));
/// dio.get('/data', options: Options(extra: {'share': false})); // bypass
/// ```
class SharePlugin extends DioPlugin {
  SharePlugin({
    this.policy = SharePolicy.start,
    this.retries = 3,
    this.interval = Duration.zero,
  });

  final SharePolicy policy;
  final int retries;
  final Duration interval;

  final _active = <String, _Entry>{};

  static const _kLeader = '_share_leader';
  static const _kSeq    = '_share_seq';
  static const _kPolicy = '_share_policy';

  @override
  String get name => 'share';

  // ── Request side ──────────────────────────────────────────────────────────

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final key = options.extra[kRequestKey] as String?;
    if (key == null) return handler.next(options); // no key → pass through

    final p = _resolvePolicy(options);
    options.extra[_kPolicy] = p;

    switch (p) {
      case SharePolicy.none:
        return handler.next(options);

      case SharePolicy.start:
      case SharePolicy.retry:
        _handleStart(options, handler, key, p);

      case SharePolicy.end:
        _handleEnd(options, handler, key);

      case SharePolicy.race:
        _handleRace(options, handler, key);
    }
  }

  // start / retry: first caller proceeds, rest wait
  void _handleStart(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String key,
    SharePolicy p,
  ) {
    if (!_active.containsKey(key)) {
      final entry = _Entry();
      _active[key] = entry;
      options.extra[_kLeader] = true;
      if (p == SharePolicy.retry) {
        options.extra['_share_retries_left'] = retries;
      }
      handler.next(options);
    } else {
      _active[key]!.completer.future.then(
        (r) => handler.resolve(r),
        onError: (Object e) => handler.reject(e as DioException),
      );
    }
  }

  // end: every caller bumps the sequence; only the last one settles
  void _handleEnd(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String key,
  ) {
    final entry = _active[key] ?? _Entry();
    _active[key] = entry;
    entry.seq++;
    options.extra[_kSeq] = entry.seq;
    options.extra[_kLeader] = true;
    handler.next(options); // everyone proceeds
    // Settle is gated by seq match in onResponse/onError
  }

  // race: everyone proceeds, first success wins
  void _handleRace(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String key,
  ) {
    final entry = _active[key] ?? _Entry();
    _active[key] = entry;
    entry.inFlight++;
    options.extra[_kLeader] = true;
    options.extra[_kSeq] = entry.inFlight; // unique id per in-flight request
    handler.next(options);
  }

  // ── Response side ─────────────────────────────────────────────────────────

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final opts = response.requestOptions;
    final key = opts.extra[kRequestKey] as String?;
    final isLeader = opts.extra[_kLeader] == true;

    if (key == null || !isLeader) return handler.next(response);

    final p = opts.extra[_kPolicy] as SharePolicy? ?? SharePolicy.start;
    final entry = _active[key];
    if (entry == null) return handler.next(response);

    switch (p) {
      case SharePolicy.end:
        final mySeq = opts.extra[_kSeq] as int?;
        if (mySeq == entry.seq) {
          // Last request: settle and clean up
          _active.remove(key);
          entry.completer.complete(response);
        }
        // Older requests: response goes to caller but doesn't settle shared promise

      case SharePolicy.race:
        // First success settles
        if (!entry.completer.isCompleted) {
          _active.remove(key);
          entry.completer.complete(response);
        }
        // Subsequent successes are silently discarded

      default: // start, retry
        _active.remove(key);
        entry.completer.complete(response);
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final key = opts.extra[kRequestKey] as String?;
    final isLeader = opts.extra[_kLeader] == true;

    if (key == null || !isLeader) return handler.next(err);

    final p = opts.extra[_kPolicy] as SharePolicy? ?? SharePolicy.start;
    final entry = _active[key];
    if (entry == null) return handler.next(err);

    switch (p) {
      case SharePolicy.retry:
        final left = (opts.extra['_share_retries_left'] as int? ?? 0) - 1;
        if (left >= 0) {
          opts.extra['_share_retries_left'] = left;
          if (interval > Duration.zero) await Future<void>.delayed(interval);
          try {
            handler.resolve(await Dio().fetch<dynamic>(opts));
          } catch (e) {
            _active.remove(key);
            entry.completer.completeError(err);
            handler.next(err);
          }
          return;
        }
        _active.remove(key);
        entry.completer.completeError(err);

      case SharePolicy.end:
        final mySeq = opts.extra[_kSeq] as int?;
        if (mySeq == entry.seq) {
          _active.remove(key);
          entry.completer.completeError(err);
        }

      case SharePolicy.race:
        entry.inFlight--;
        if (entry.inFlight <= 0 && !entry.completer.isCompleted) {
          _active.remove(key);
          entry.completer.completeError(err);
        }

      default: // start
        _active.remove(key);
        entry.completer.completeError(err);
    }

    handler.next(err);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  SharePolicy _resolvePolicy(RequestOptions opts) {
    final v = opts.extra['share'];
    if (v == false) return SharePolicy.none;
    if (v is SharePolicy) return v;
    return policy;
  }

  @override
  void dispose() => _active.clear();
}
