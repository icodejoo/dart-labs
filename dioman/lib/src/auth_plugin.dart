// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:dio/dio.dart';
import 'dio_plugin.dart';

// ── TokenManager ─────────────────────────────────────────────────────────────

/// Contract for managing access / refresh tokens.
abstract interface class ITokenManager {
  String? get accessToken;
  String? get refreshToken;
  bool get canRefresh;
  void clear();
}

// ── Failure actions ───────────────────────────────────────────────────────────

/// The five outcomes [AuthPlugin] can route a 401/403 to.
enum AuthFailureAction {
  /// Call [onRefresh], then replay the original request with the new token.
  refresh,

  /// Replay the original request without refreshing (token was already
  /// refreshed concurrently, or the request went out without a token).
  replay,

  /// Call [onAccessDenied]; propagate the error as-is.
  deny,

  /// Clear the token store, call [onAccessExpired]; propagate the error.
  expired,

  /// Unrelated failure — propagate without any auth action.
  others,
}

// ── Default failure router ────────────────────────────────────────────────────

/// Standard OAuth decision logic for 401 / 403 responses.
///
/// Decision order:
/// 1. Non-401/403 → [AuthFailureAction.others]
/// 2. No token in store →  401 ⇒ [expired] / 403 ⇒ [deny]
/// 3. Request carried no token → [replay]
/// 4. Request token == current store token → [refresh] (genuinely expired)
/// 5. Request token ≠ current store token → [replay] (stale; already refreshed)
AuthFailureAction defaultAuthFailure(
  ITokenManager tm,
  Response<dynamic> response,
  String headerKey,
) {
  final status = response.statusCode ?? 0;
  if (status != 401 && status != 403) return AuthFailureAction.others;

  final current = tm.accessToken;
  if (current == null || current.isEmpty) {
    return status == 401 ? AuthFailureAction.expired : AuthFailureAction.deny;
  }

  // Compare the raw token actually used (stashed by AuthPlugin at injection
  // time) rather than the formatted header — buildHeader may wrap it (e.g.
  // 'Bearer $t'), which would never equal the raw store token. Fall back to
  // the header lookup for requests injected via a custom `ready` callback,
  // where the raw token isn't stashed.
  final tokenUsed = response.requestOptions.extra[_kTokenUsed] as String?;
  final carried = tokenUsed ?? response.requestOptions.headers[headerKey]?.toString();
  if (carried == null || carried.isEmpty) return AuthFailureAction.replay;
  return carried == current ? AuthFailureAction.refresh : AuthFailureAction.replay;
}

// ── Plugin ────────────────────────────────────────────────────────────────────

// extra keys — plain strings so they survive Dio's mergeConfig on replay
const _kDecision  = '__auth_decision';
const _kProtected = '__auth_protected';
const _kRefreshed = '__auth_refreshed';
const _kDenied    = '__auth_denied';
const _kTokenUsed = '__auth_token_used';

/// Full-featured auth plugin — token injection, single-window refresh, and
/// five-action failure routing (Refresh / Replay / Deny / Expired / Others).
///
/// Pairs with [BuildKeyPlugin] / other plugins independently.
///
/// ## Ordering
///
/// ```dart
/// dio.interceptors
///   ..add(AuthPlugin(
///     tokenManager: myTM,
///     onRefresh: (tm, _) async { /* refresh */ },
///     onAccessExpired: (tm, _) async { Get.offAllNamed(Routes.login); },
///   ));
/// ```
///
/// ## Per-request opt-out
///
/// ```dart
/// dio.get('/public', options: Options(extra: {'protected': false}));
/// ```
class AuthPlugin extends DioPlugin {
  AuthPlugin({
    required ITokenManager tokenManager,
    required Future<void> Function(ITokenManager tm, Response<dynamic> resp) onRefresh,
    required Future<void> Function(ITokenManager tm, Response<dynamic> resp) onAccessExpired,
    Future<void> Function(ITokenManager tm, Response<dynamic> resp)? onAccessDenied,
    AuthFailureAction Function(ITokenManager tm, Response<dynamic> resp)? onFailure,
    Future<void> Function(ITokenManager tm, RequestOptions config)? ready,
    bool Function(RequestOptions)? isProtected,
    DateTime? Function(String token)? expiresAt,
    Duration refreshLeeway = Duration.zero,
    DateTime Function() now = DateTime.now,
    String headerKey = 'Authorization',
    String Function(String token)? buildHeader,
    this.enable = true,
  })  : _tm = tokenManager,
        _onRefresh = onRefresh,
        _onExpired = onAccessExpired,
        _onDenied = onAccessDenied,
        _onFailure = onFailure,
        _ready = ready,
        _isProtected = isProtected,
        _expiresAt = expiresAt,
        _refreshLeeway = refreshLeeway,
        _now = now,
        _headerKey = headerKey,
        _buildHeader = buildHeader ?? _defaultBearer;

  final ITokenManager _tm;
  final Future<void> Function(ITokenManager, Response<dynamic>) _onRefresh;
  final Future<void> Function(ITokenManager, Response<dynamic>) _onExpired;
  final Future<void> Function(ITokenManager, Response<dynamic>)? _onDenied;
  final AuthFailureAction Function(ITokenManager, Response<dynamic>)? _onFailure;
  final Future<void> Function(ITokenManager, RequestOptions)? _ready;
  final bool Function(RequestOptions)? _isProtected;
  final DateTime? Function(String token)? _expiresAt;
  final Duration _refreshLeeway;
  final DateTime Function() _now;
  final String _headerKey;
  final String Function(String) _buildHeader;

  final bool enable;

  Future<bool>? _refreshing; // shared window; bool = success

  // Bare Dio reused for post-failure replays — no interceptors, so replays
  // never re-enter this chain. Lazily created and reused (rather than a fresh
  // `Dio()` per replay) so the underlying HttpClient / connection pool is not
  // reallocated on every 401. Closed in [dispose].
  Dio? _replayDio;
  Dio get _replay => _replayDio ??= Dio();

  static String _defaultBearer(String t) => 'Bearer $t';

  @override
  String get name => 'auth';

  // ── Request ───────────────────────────────────────────────────────────────

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!enable) return handler.next(options);

    final prot = _computeIsProtected(options);
    options.extra[_kDecision] = prot;
    if (!prot) return handler.next(options);

    options.extra[_kProtected] = true;

    // If refresh is in progress wait for it before proceeding.
    if (_refreshing != null) {
      final ok = await _refreshing!;
      if (!ok) {
        options.extra[_kDenied] = true;
        // callFollowingErrorInterceptor: true — brackets installed before
        // auth (cancel/loading/share) must see this error to release their
        // state; the default false would skip the whole onError chain.
        return handler.reject(
          DioException(requestOptions: options, message: '[auth] refresh failed; aborting'),
          true,
        );
      }
    }

    var token = _tm.accessToken;
    if (token == null || token.isEmpty) {
      options.extra[_kDenied] = true;
      final synthResp = _synthDenied(options);
      await _safe(() => _onDenied?.call(_tm, synthResp) ?? _onExpired(_tm, synthResp));
      return handler.reject(
        DioException(requestOptions: options, message: '[auth] access denied — no token'),
        true,
      );
    }

    // Proactive refresh: if the caller supplied [_expiresAt] and the current
    // token is already expired (within [_refreshLeeway]), refresh BEFORE
    // sending so the request goes out once with a fresh token — no doomed 401
    // round-trip. Concurrent expiring requests all funnel through the same
    // [_startRefresh] shared-future window (the `??=` collapses them to a
    // single refresh), so this needs no QueuedInterceptor / serialization:
    // the first triggers the refresh, the rest await the same future, then
    // every one injects the refreshed token. Opt-in — with no [_expiresAt]
    // callback this branch never runs and behaviour is purely reactive.
    if (_isExpiring(token)) {
      final ok = await _startRefresh(_synthProactive(options));
      if (!ok) {
        options.extra[_kDenied] = true;
        await _expire(_synthProactive(options));
        return handler.reject(
          DioException(
            requestOptions: options,
            message: '[auth] proactive refresh failed; aborting',
          ),
          true,
        );
      }
      final fresh = _tm.accessToken;
      if (fresh != null && fresh.isNotEmpty) token = fresh;
    }

    await _injectToken(options, token);
    handler.next(options);
  }

  /// Whether [token] is expired (or within [_refreshLeeway] of expiring),
  /// per the caller-supplied [_expiresAt]. Returns false when no [_expiresAt]
  /// callback was provided or it can't determine an expiry — the proactive
  /// path is strictly opt-in and never fabricates a refresh.
  bool _isExpiring(String token) {
    final at = _expiresAt?.call(token);
    if (at == null) return false;
    return !at.isAfter(_now().add(_refreshLeeway));
  }

  /// Injects the current [token] into [options] — via [_ready] if provided,
  /// otherwise via [_buildHeader] — and stashes the raw token used so
  /// [defaultAuthFailure] can compare it against the store's current token
  /// directly (see [_kTokenUsed]). Used both for the initial request and to
  /// refresh the header before a post-refresh replay.
  Future<void> _injectToken(RequestOptions options, String token) async {
    if (_ready != null) {
      await _safe(() => _ready(_tm, options));
    } else {
      options.headers[_headerKey] = _buildHeader(token);
    }
    options.extra[_kTokenUsed] = token;
  }

  // ── Response (success path) ───────────────────────────────────────────────

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final bag = response.requestOptions.extra;
    if (bag[_kProtected] != true) return handler.next(response);
    if (bag[_kDenied] == true) { _clearFlags(bag); return handler.next(response); }

    // Treat business-level failures the same as HTTP 401/403 here:
    // the normalize-response plugin will already have converted them to errors,
    // so reaching this point with a successful HTTP code means the response is ok.
    _clearFlags(bag);
    handler.next(response);
  }

  // ── Response (error path) ─────────────────────────────────────────────────

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final bag = opts.extra;
    if (bag[_kProtected] != true) return handler.next(err);
    if (bag[_kDenied] == true) { _clearFlags(bag); return handler.next(err); }

    final response = err.response;
    if (response == null) { _clearFlags(bag); return handler.next(err); }

    final resolved = await _handleFailure(response, opts, err);
    if (resolved is Response) {
      handler.resolve(resolved);
    } else {
      handler.next(err);
    }
  }

  // ── Failure routing ───────────────────────────────────────────────────────

  Future<Object?> _handleFailure(
    Response<dynamic> response,
    RequestOptions opts,
    DioException original,
  ) async {
    final bag = opts.extra;

    if (bag[_kRefreshed] == true) {
      // Already replayed once — give up.
      await _expire(response);
      _clearFlags(bag);
      return null;
    }

    final action = await _safe(
      () async => _onFailure?.call(_tm, response) ?? defaultAuthFailure(_tm, response, _headerKey),
    ) ?? AuthFailureAction.others;

    switch (action) {
      case AuthFailureAction.refresh:
        final ok = await _startRefresh(response);
        if (ok) {
          bag[_kRefreshed] = true;
          // Re-inject with the freshly refreshed token — the throwaway Dio
          // has no interceptors, so nothing else will update the header.
          final fresh = _tm.accessToken;
          if (fresh != null && fresh.isNotEmpty) await _injectToken(opts, fresh);
          try { return await _replay.fetch<dynamic>(opts); } catch (_) {}
        }
        await _expire(response);
        _clearFlags(bag);
        return null;

      case AuthFailureAction.replay:
        bag[_kRefreshed] = true;
        // Someone else's refresh may have landed a new token since this
        // request's header was built — carry the current one on replay.
        final current = _tm.accessToken;
        if (current != null && current.isNotEmpty) await _injectToken(opts, current);
        try { return await _replay.fetch<dynamic>(opts); } catch (_) {}
        _clearFlags(bag);
        return null;

      case AuthFailureAction.deny:
        await _safe(() => (_onDenied ?? _onExpired)(_tm, response));
        _clearFlags(bag);
        return null;

      case AuthFailureAction.expired:
        await _expire(response);
        _clearFlags(bag);
        return null;

      case AuthFailureAction.others:
        _clearFlags(bag);
        return null;
    }
  }

  Future<bool> _startRefresh(Response<dynamic> resp) {
    return _refreshing ??= (() async {
      try {
        await _onRefresh(_tm, resp);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    })();
  }

  Future<void> _expire(Response<dynamic> resp) async {
    _tm.clear();
    await _safe(() => _onExpired(_tm, resp));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _computeIsProtected(RequestOptions opts) {
    final cached = opts.extra[_kDecision];
    if (cached is bool) return cached; // replay: reuse first decision

    final perRequest = opts.extra['protected'];
    if (perRequest is bool) return perRequest;
    if (perRequest is Function) {
      final r = perRequest(opts);
      if (r is bool) return r;
    }

    if (_isProtected != null) {
      return _isProtected(opts);
    }

    return true; // default: protect everything
  }

  Response<dynamic> _synthDenied(RequestOptions opts) => Response<dynamic>(
        requestOptions: opts,
        statusCode: 0,
        statusMessage: 'ACCESS_DENIED',
        data: {'code': 'ACCESS_DENIED', 'message': 'protected request without accessToken'},
      );

  /// Placeholder [Response] handed to [_onRefresh] / [_onExpired] on the
  /// proactive path — there is no server response yet (the token was refreshed
  /// before sending). `onRefresh` implementations normally ignore this and
  /// refresh from the token manager; the `PROACTIVE_REFRESH` marker lets a
  /// caller that does inspect it tell this apart from a reactive 401.
  Response<dynamic> _synthProactive(RequestOptions opts) => Response<dynamic>(
        requestOptions: opts,
        statusCode: null,
        statusMessage: 'PROACTIVE_REFRESH',
      );

  static void _clearFlags(Map<dynamic, dynamic> bag) {
    bag.remove(_kProtected);
    bag.remove(_kRefreshed);
    bag.remove(_kDenied);
    bag.remove(_kTokenUsed);
  }

  static Future<T?> _safe<T>(Future<T> Function() fn) async {
    try { return await fn(); } catch (_) { return null; }
  }

  @override
  void dispose() {
    _refreshing = null;
    _replayDio?.close(force: true);
    _replayDio = null;
  }
}
