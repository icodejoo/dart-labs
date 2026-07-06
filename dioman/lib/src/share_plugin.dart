import 'dart:async';
import 'package:dio/dio.dart';
import 'key_plugin.dart';
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
  _Entry() : completer = Completer<Response<dynamic>>() {
    // A lone leader (no followers ever attached) or an already-settled
    // completer under end/race can complete with an error that nobody
    // listens to — that raises an unhandled zone error. `ignore()` only
    // marks this future as intentionally unhandled; real listeners attached
    // elsewhere (via .then) still receive the value/error independently.
    completer.future.ignore();
  }
  final Completer<Response<dynamic>> completer;
  int seq = 0;       // used by [end]
  int inFlight = 0;  // used by [race]
}

/// Deduplicates or shares concurrent requests with the **same key**
/// (produced by [KeyPlugin]) using one of four strategies.
///
/// **Install [KeyPlugin] first** — without a key, every request
/// is treated as independent (policy = none).
///
/// Per-request override via `options.extra[SharePlugin.configProperty]`:
/// - `false` / `SharePolicy.none` → skip sharing
/// - A [SharePolicy] value → use that policy for this request
///
/// ```dart
/// dio.interceptors
///   ..add(KeyPlugin())
///   ..add(SharePlugin(policy: SharePolicy.start));
///
/// // Override per request:
/// dio.get('/data', options: Options(extra: {SharePlugin.configProperty: SharePolicy.race}));
/// dio.get('/data', options: Options(extra: {SharePlugin.configProperty: false})); // bypass
/// ```
class SharePlugin extends DioPlugin {
  /// The `extra` key callers use to opt out of / override the sharing policy
  /// for a single request. Change this to remap it.
  static String configProperty = 'dioman:share';

  SharePlugin({
    this.policy = SharePolicy.start,
    this.retries = 3,
    this.interval = Duration.zero,
  });

  final SharePolicy policy;
  final int retries;
  final Duration interval;

  final _active = <String, _Entry>{};

  // Bare Dio reused for policy=retry re-issues — no interceptors, so retries
  // never re-enter this chain. Lazily created and reused across retries (and
  // across the retry loop's iterations) instead of a fresh `Dio()` each time,
  // so the HttpClient / connection pool isn't reallocated per attempt. Closed
  // in [dispose].
  Dio? _retryDio;
  Dio get _retry => _retryDio ??= Dio();

  static const _kEntry  = 'dioman:share:entry';
  static const _kSeq    = 'dioman:share:seq';
  static const _kPolicy = 'dioman:share:policy';
  static const _kRetriesLeft = 'dioman:share:retriesLeft';

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
    final existing = _active[key];
    if (existing == null) {
      final entry = _Entry();
      _active[key] = entry;
      options.extra[_kEntry] = entry;
      if (p == SharePolicy.retry) {
        options.extra[_kRetriesLeft] = retries;
      }
      handler.next(options);
    } else {
      existing.completer.future.then(
        (r) => handler.resolve(r),
        onError: (Object e) => handler.reject(e as DioException),
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
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final opts = response.requestOptions;
    // Read the entry directly off this request rather than re-looking it up
    // in `_active` — the shared entry may already have been removed (settled
    // by a sibling) by the time a superseded/losing caller's response lands.
    final entry = opts.extra[_kEntry] as _Entry?;
    if (entry == null) return handler.next(response);

    final key = opts.extra[kRequestKey] as String?;
    final p = opts.extra[_kPolicy] as SharePolicy? ?? SharePolicy.start;

    switch (p) {
      case SharePolicy.end:
        final mySeq = opts.extra[_kSeq] as int?;
        if (mySeq == entry.seq) {
          _settle(key, entry);
          if (!entry.completer.isCompleted) entry.completer.complete(response);
          return handler.next(response);
        }
        // Superseded by a newer request — deliver the eventual winner's
        // result instead of this stale one.
        return _awaitEntry(entry, handler);

      case SharePolicy.race:
        if (!entry.completer.isCompleted) {
          _settle(key, entry);
          entry.completer.complete(response);
          return handler.next(response);
        }
        // Another in-flight attempt already won the race.
        return _awaitEntry(entry, handler);

      default: // start, retry
        _settle(key, entry);
        if (!entry.completer.isCompleted) entry.completer.complete(response);
        handler.next(response);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final entry = opts.extra[_kEntry] as _Entry?;
    if (entry == null) return handler.next(err);

    final key = opts.extra[kRequestKey] as String?;
    final p = opts.extra[_kPolicy] as SharePolicy? ?? SharePolicy.start;

    switch (p) {
      case SharePolicy.retry:
        var left = opts.extra[_kRetriesLeft] as int? ?? 0;
        Response<dynamic>? success;
        Object lastError = err;
        while (left > 0) {
          left--;
          opts.extra[_kRetriesLeft] = left;
          if (interval > Duration.zero) await Future<void>.delayed(interval);
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
        if (!entry.completer.isCompleted) entry.completer.completeError(finalErr);
        return handler.next(finalErr);

      case SharePolicy.end:
        final mySeq = opts.extra[_kSeq] as int?;
        if (mySeq == entry.seq) {
          _settle(key, entry);
          if (!entry.completer.isCompleted) entry.completer.completeError(err);
          return handler.next(err);
        }
        return _awaitEntry(entry, handler);

      case SharePolicy.race:
        entry.inFlight--;
        if (!entry.completer.isCompleted && entry.inFlight <= 0) {
          _settle(key, entry);
          entry.completer.completeError(err);
          return handler.next(err);
        }
        return _awaitEntry(entry, handler);

      default: // start
        _settle(key, entry);
        if (!entry.completer.isCompleted) entry.completer.completeError(err);
        handler.next(err);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Removes [entry] from `_active[key]` — but only if it's still the entry
  /// registered there (a new burst may already have installed a fresh one).
  void _settle(String? key, _Entry entry) {
    if (key != null && identical(_active[key], entry)) _active.remove(key);
  }

  /// Delivers whatever [entry]'s completer eventually settles with to this
  /// caller, instead of this caller's own (superseded/losing) result.
  void _awaitEntry(_Entry entry, dynamic handler) {
    entry.completer.future.then(
      (r) => handler.resolve(r),
      onError: (Object e) => handler.reject(e as DioException),
    );
  }

  SharePolicy _resolvePolicy(RequestOptions opts) {
    final v = opts.extra[SharePlugin.configProperty];
    if (v == false) return SharePolicy.none;
    if (v is SharePolicy) return v;
    return policy;
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
            message: '[share] plugin disposed before the shared request settled',
          ),
        );
      }
    }
    _active.clear();
    _retryDio?.close(force: true);
    _retryDio = null;
  }
}
