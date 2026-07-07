// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:dio/dio.dart';
import 'cancel_plugin.dart';
import 'dioman_plugin.dart';
import 'key_plugin.dart';
import 'share_plugin.dart';

// ── TokenManager ─────────────────────────────────────────────────────────────

/// Contract for managing access / refresh tokens.
///
/// 管理access/refresh token的接口约定。
abstract interface class DiomanTokenManager {
  /// The current access token, or null if none.
  ///
  /// 当前access token，没有则为null。
  String? get accessToken;

  /// The current refresh token, or null if none.
  ///
  /// 当前refresh token，没有则为null。
  String? get refreshToken;

  /// Whether a refresh is currently possible (e.g. refresh token present).
  ///
  /// 当前是否可以执行刷新（例如refresh token是否存在）。
  bool get canRefresh;

  /// Clears the stored tokens (called on expiry/denial).
  ///
  /// 清空已存储的token（在过期/拒绝时调用）。
  void clear();
}

// ── Failure actions ───────────────────────────────────────────────────────────

/// The five outcomes [DiomanAuth] can route a 401/403 to.
///
/// [DiomanAuth]处理401/403时可路由到的五种结果。
enum DiomanAuthFailureAction {
  /// Call [DiomanAuth]'s refresh callback, then replay the original request with the new token.
  ///
  /// 调用刷新回调，然后用新token重放原始请求。
  refresh,

  /// Replay the original request without refreshing (token was already
  /// refreshed concurrently, or the request went out without a token).
  ///
  /// 不刷新直接重放原始请求（token已被并发刷新过，或请求当时没带token）。
  replay,

  /// Call the denied callback; propagate the error as-is.
  ///
  /// 调用拒绝回调；原样向上传播错误。
  deny,

  /// Clear the token store, call the expired callback; propagate the error.
  ///
  /// 清空token存储，调用过期回调；向上传播错误。
  expired,

  /// Unrelated failure — propagate without any auth action.
  ///
  /// 与鉴权无关的失败——不做任何鉴权动作，直接传播。
  others,
}

// ── Default failure router ────────────────────────────────────────────────────

/// Standard OAuth decision logic for 401 / 403 responses.
///
/// 针对401/403响应的标准OAuth决策逻辑。
///
/// Decision order:
/// 1. Non-401/403 → [DiomanAuthFailureAction.others]
/// 2. No token in store →  401 ⇒ [expired] / 403 ⇒ [deny]
/// 3. Request carried no token → [replay]
/// 4. Request token == current store token → [refresh] (genuinely expired)
/// 5. Request token ≠ current store token → [replay] (stale; already refreshed)
DiomanAuthFailureAction defaultAuthFailure(
  DiomanTokenManager tokenManager,
  Response<dynamic> response,
  String headerKey,
) {
  final status = response.statusCode ?? 0;
  if (status != 401 && status != 403) return DiomanAuthFailureAction.others;

  final current = tokenManager.accessToken;
  if (current == null || current.isEmpty) {
    return status == 401
        ? DiomanAuthFailureAction.expired
        : DiomanAuthFailureAction.deny;
  }

  // Compare the raw token actually used (stashed by DiomanAuth at injection
  // time) rather than the formatted header — buildHeader may wrap it (e.g.
  // 'Bearer $t'), which would never equal the raw store token. Fall back to
  // the header lookup for requests injected via a custom `ready` callback,
  // where the raw token isn't stashed.
  final tokenUsed =
      response.requestOptions.extra[DiomanAuth._kTokenUsed] as String?;
  final carried =
      tokenUsed ?? response.requestOptions.headers[headerKey]?.toString();
  if (carried == null || carried.isEmpty) return DiomanAuthFailureAction.replay;
  return carried == current
      ? DiomanAuthFailureAction.refresh
      : DiomanAuthFailureAction.replay;
}

// ── Plugin ────────────────────────────────────────────────────────────────────

/// Per-request override for [DiomanAuth], read from `extra['dioman:auth']`.
///
/// [DiomanAuth]的单请求覆盖，从`extra['dioman:auth']`读取。
///
/// Every field mirrors a [DiomanAuth] constructor parameter and is merged as
/// `override ?? constructorValue` — `null` means "inherit the plugin's own
/// setting", not an implicit default. Excluded on purpose: `tokenManager` and
/// `onRefresh`, because the single shared refresh window (`_refreshing`) is
/// keyed to one token manager / one refresh implementation — swapping either
/// per single call would break that invariant for every concurrent caller.
///
/// 每个字段都镜像[DiomanAuth]的构造参数，解析方式统一为`override ?? 构造函数的值`——
/// `null`代表"沿用插件自身设置"，不是隐式默认值。故意排除`tokenManager`和`onRefresh`：
/// 单一共享刷新窗口（`_refreshing`）绑定的是同一个token manager/同一套刷新实现，
/// 单次请求换掉其中任一个都会破坏所有并发请求共享的这个不变量。
class DiomanAuthOptions {
  const DiomanAuthOptions({
    this.enabled,
    this.onAccessDenied,
    this.onAccessExpired,
    this.onFailure,
    this.ready,
    this.isProtected,
    this.expiresAt,
    this.refreshLeeway,
    this.now,
    this.headerKey,
    this.buildHeader,
  });

  /// `false` marks this request as unprotected — no token required. `null`
  /// (default) falls through to `isProtected`, then to "protect everything".
  ///
  /// `false`表示本次请求不受保护——不需要token。`null`（默认）则回落到
  /// `isProtected`，再回落到"默认保护所有请求"。
  final bool? enabled;

  /// Overrides the plugin's `onAccessDenied` for this request only.
  ///
  /// 仅本次请求覆盖插件的`onAccessDenied`。
  final Future<void> Function(
      DiomanTokenManager tokenManager, Response<dynamic> resp)? onAccessDenied;

  /// Overrides the plugin's `onAccessExpired` for this request only.
  ///
  /// 仅本次请求覆盖插件的`onAccessExpired`。
  final Future<void> Function(
      DiomanTokenManager tokenManager, Response<dynamic> resp)? onAccessExpired;

  /// Overrides the plugin's `onFailure` router for this request only.
  ///
  /// 仅本次请求覆盖插件的失败路由函数`onFailure`。
  final DiomanAuthFailureAction Function(
      DiomanTokenManager tokenManager, Response<dynamic> resp)? onFailure;

  /// Overrides the plugin's `ready` injection callback for this request only.
  ///
  /// 仅本次请求覆盖插件的token注入回调`ready`。
  final Future<void> Function(
      DiomanTokenManager tokenManager, RequestOptions config)? ready;

  /// Overrides the plugin's `isProtected` callback for this request only
  /// (used only when [enabled] on this override is left `null`).
  ///
  /// 仅本次请求覆盖插件的`isProtected`回调（只在本覆盖的[enabled]为`null`时才生效）。
  final bool Function(RequestOptions)? isProtected;

  /// Overrides the plugin's `expiresAt` callback for this request only.
  ///
  /// 仅本次请求覆盖插件的`expiresAt`回调。
  final DateTime? Function(String token)? expiresAt;

  /// Overrides the plugin's default `refreshLeeway` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`refreshLeeway`提前量。
  final Duration? refreshLeeway;

  /// Overrides the plugin's `now` clock for this request only.
  ///
  /// 仅本次请求覆盖插件的时钟函数`now`。
  final DateTime Function()? now;

  /// Overrides the plugin's default `headerKey` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的头部字段名`headerKey`。
  final String? headerKey;

  /// Overrides the plugin's `buildHeader` for this request only.
  ///
  /// 仅本次请求覆盖插件的`buildHeader`。
  final String Function(String token)? buildHeader;
}

/// Full-featured auth plugin — token injection, single-window refresh, and
/// five-action failure routing (Refresh / Replay / Deny / Expired / Others).
///
/// 全功能鉴权插件——token注入、单窗口刷新、五种失败路由（刷新/重放/拒绝/过期/其它）。
///
/// Pairs with [DiomanKey] / other plugins independently.
///
/// ## Ordering
///
/// ```dart
/// dio.interceptors
///   ..add(DiomanAuth(
///     tokenManager: myTokenManager,
///     onRefresh: (tokenManager, _) async { /* refresh */ },
///     onAccessExpired: (tokenManager, _) async { Get.offAllNamed(Routes.login); },
///   ));
/// ```
///
/// ## Per-request opt-out
///
/// ```dart
/// dio.get('/public', options: Options(extra: {'dioman:auth': const DiomanAuthOptions(enabled: false)}));
/// ```
class DiomanAuth extends DiomanPlugin {
  DiomanAuth({
    required DiomanTokenManager tokenManager,
    required Future<void> Function(
            DiomanTokenManager tokenManager, Response<dynamic> resp)
        onRefresh,
    required Future<void> Function(
            DiomanTokenManager tokenManager, Response<dynamic> resp)
        onAccessExpired,
    Future<void> Function(
            DiomanTokenManager tokenManager, Response<dynamic> resp)?
        onAccessDenied,
    DiomanAuthFailureAction Function(
            DiomanTokenManager tokenManager, Response<dynamic> resp)?
        onFailure,
    Future<void> Function(
            DiomanTokenManager tokenManager, RequestOptions config)?
        ready,
    bool Function(RequestOptions)? isProtected,
    DateTime? Function(String token)? expiresAt,
    Duration refreshLeeway = Duration.zero,
    DateTime Function() now = DateTime.now,
    String headerKey = 'Authorization',
    String Function(String token)? buildHeader,
    this.enabled = true,
  })  : _tokenManager = tokenManager,
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

  // Core dependency — deliberately NOT overridable per request; see
  // [DiomanAuthOptions] doc for why.
  //
  // 核心依赖——刻意不允许单请求覆盖，原因见[DiomanAuthOptions]的文档。
  final DiomanTokenManager _tokenManager;

  // Drives the single shared refresh window (`_refreshing`) — deliberately
  // NOT overridable per request; see [DiomanAuthOptions] doc for why.
  //
  // 驱动单一共享刷新窗口（`_refreshing`）——刻意不允许单请求覆盖，原因见
  // [DiomanAuthOptions]的文档。
  final Future<void> Function(DiomanTokenManager, Response<dynamic>) _onRefresh;

  /// Called on session expiry (token cleared) or as the fallback for denial.
  /// Overridable per request via [DiomanAuthOptions.onAccessExpired].
  ///
  /// 会话过期（token被清空）时调用，或作为拒绝场景的兜底回调。
  /// 可通过[DiomanAuthOptions.onAccessExpired]按请求覆盖。
  final Future<void> Function(DiomanTokenManager, Response<dynamic>) _onExpired;

  /// Called when a protected request has no token to send. Falls back to
  /// [_onExpired] when not provided. Overridable per request via
  /// [DiomanAuthOptions.onAccessDenied].
  ///
  /// 受保护请求没有token可发时调用；未提供时回落到[_onExpired]。
  /// 可通过[DiomanAuthOptions.onAccessDenied]按请求覆盖。
  final Future<void> Function(DiomanTokenManager, Response<dynamic>)? _onDenied;

  /// Custom 401/403 failure router. Falls back to [defaultAuthFailure] when
  /// not provided. Overridable per request via [DiomanAuthOptions.onFailure].
  ///
  /// 自定义401/403失败路由函数；未提供时回落到[defaultAuthFailure]。
  /// 可通过[DiomanAuthOptions.onFailure]按请求覆盖。
  final DiomanAuthFailureAction Function(DiomanTokenManager, Response<dynamic>)?
      _onFailure;

  /// Custom token-injection callback, used instead of [_buildHeader]/
  /// [_headerKey] when provided. Overridable per request via
  /// [DiomanAuthOptions.ready].
  ///
  /// 自定义token注入回调，提供时替代[_buildHeader]/[_headerKey]。
  /// 可通过[DiomanAuthOptions.ready]按请求覆盖。
  final Future<void> Function(DiomanTokenManager, RequestOptions)? _ready;

  /// Decides whether a request is protected, when a per-request
  /// [DiomanAuthOptions.enabled] isn't set. Overridable per request via
  /// [DiomanAuthOptions.isProtected].
  ///
  /// 在单请求[DiomanAuthOptions.enabled]未设置时，决定该请求是否受保护。
  /// 可通过[DiomanAuthOptions.isProtected]按请求覆盖。
  final bool Function(RequestOptions)? _isProtected;

  /// Decodes a token's expiry (e.g. JWT `exp`) to drive proactive refresh.
  /// Opt-in — `null` means the proactive path never runs. Overridable per
  /// request via [DiomanAuthOptions.expiresAt].
  ///
  /// 解析token的过期时间（如JWT的`exp`）以驱动主动刷新，选择性开启——`null`表示
  /// 主动刷新路径永不触发。可通过[DiomanAuthOptions.expiresAt]按请求覆盖。
  final DateTime? Function(String token)? _expiresAt;

  /// How far ahead of the real expiry a token is treated as "already
  /// expiring" for the proactive-refresh check. Overridable per request via
  /// [DiomanAuthOptions.refreshLeeway].
  ///
  /// 主动刷新检查中，提前多久把token视为"已经要过期"。
  /// 可通过[DiomanAuthOptions.refreshLeeway]按请求覆盖。
  final Duration _refreshLeeway;

  /// Clock used for the proactive-expiry check (injectable for tests).
  /// Overridable per request via [DiomanAuthOptions.now].
  ///
  /// 主动过期检查用的时钟（可注入以便测试）。可通过[DiomanAuthOptions.now]按请求覆盖。
  final DateTime Function() _now;

  /// The header name the token is written to (default `'Authorization'`).
  /// Overridable per request via [DiomanAuthOptions.headerKey].
  ///
  /// 写入token的头部字段名（默认`'Authorization'`）。
  /// 可通过[DiomanAuthOptions.headerKey]按请求覆盖。
  final String _headerKey;

  /// Formats the raw token into the header value (default `'Bearer $token'`).
  /// Overridable per request via [DiomanAuthOptions.buildHeader].
  ///
  /// 把原始token格式化为头部值（默认`'Bearer $token'`）。
  /// 可通过[DiomanAuthOptions.buildHeader]按请求覆盖。
  final String Function(String) _buildHeader;

  /// `false` disables the plugin entirely — every request passes through
  /// untouched, unprotected.
  ///
  /// `false`时插件整体失效——所有请求原样通过，不受保护。
  final bool enabled;

  /// The [DiomanCancel] instance installed on the same [Dio], if any. Set
  /// this whenever [DiomanCancel] and [DiomanAuth] are combined —
  /// [_replay] is a bare, interceptor-less Dio, so a replay never re-enters
  /// [DiomanCancel]'s onRequest (which is what re-registers a token across a
  /// [DiomanRetry] re-dispatch). Without this reference, `cancelAll()` can't
  /// see — let alone abort — a request currently being replayed.
  ///
  /// [Dioman.install] wires this automatically when both a `cancel:` and an
  /// `auth:` plugin are passed to it.
  ///
  /// 同一个[Dio]上安装的[DiomanCancel]实例（如果有）。[DiomanCancel]和
  /// [DiomanAuth]搭配使用时务必设置——[_replay]是个不带拦截器的裸Dio，重放
  /// 永远不会重新进入[DiomanCancel]的onRequest（那正是[DiomanRetry]重新分发时
  /// 用来重新登记token的地方）。没有这个引用，`cancelAll()`根本看不到、
  /// 更谈不上中断一个正在重放中的请求。
  ///
  /// [Dioman.install]同时收到`cancel:`和`auth:`时会自动完成这层接线。
  DiomanCancel? _cancel;

  set cancel(DiomanCancel? value) => _cancel = value;

  /// The [DiomanShare] instance installed on the same [Dio], if any. Set
  /// this whenever [DiomanShare] and [DiomanAuth] are combined — [DiomanShare]
  /// sits BEFORE [DiomanAuth] in the canonical chain, so its own
  /// onResponse/onError would otherwise settle the shared entry with the
  /// pre-refresh failure, before this plugin ever gets a chance to
  /// refresh+replay. Setting [share] registers this plugin as (one of)
  /// the settler(s) instead — see [DiomanShare.registerDownstreamSettler] /
  /// [DiomanShare.settle].
  ///
  /// [Dioman.install] wires this automatically when both a `share:` and an
  /// `auth:` plugin are passed to it.
  ///
  /// 同一个[Dio]上安装的[DiomanShare]实例（如果有）。[DiomanShare]和
  /// [DiomanAuth]搭配使用时务必设置——[DiomanShare]在canonical链条上排在
  /// [DiomanAuth]前面，它自己的onResponse/onError原本会用刷新前的失败结算
  /// 共享entry，本插件还没来得及刷新+重放。设置[share]会把本插件登记为
  /// （其中一个）结算者——见[DiomanShare.registerDownstreamSettler]/
  /// [DiomanShare.settle]。
  ///
  /// [Dioman.install]同时收到`share:`和`auth:`时会自动完成这层接线。
  DiomanShare? _share;

  set share(DiomanShare? value) {
    _share = value;
    value?.registerDownstreamSettler();
  }

  Future<bool>? _refreshing; // shared window; bool = success
  // 共享刷新窗口；bool表示是否成功

  // Bare Dio reused for post-failure replays — no interceptors, so replays
  // never re-enter this chain. Lazily created and reused (rather than a fresh
  // `Dio()` per replay) so the underlying HttpClient / connection pool is not
  // reallocated on every 401. Closed in [dispose].
  //
  // 复用一个无拦截器的裸Dio做失败后重放，避免重新进入本拦截器链。惰性创建并复用
  // （而非每次重放新建一个`Dio()`），避免每次401都重新分配HttpClient/连接池。
  // 在[dispose]中关闭。
  Dio? _replayDio;
  Dio get _replay => _replayDio ??= Dio();

  static String _defaultBearer(String t) => 'Bearer $t';

  static const _name = 'dioman:auth';
  // extra keys — plain strings so they survive Dio's mergeConfig on replay
  //
  // extra key——用纯字符串常量，保证重放时能在Dio的mergeConfig中存活
  static const _kDecision = '$_name:decision';
  static const _kProtected = '$_name:protected';
  static const _kRefreshed = '$_name:refreshed';
  static const _kDenied = '$_name:denied';
  static const _kTokenUsed = '$_name:tokenUsed';

  @override
  String get name => _name;

  // ── Request ───────────────────────────────────────────────────────────────

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (!enabled) return handler.next(options);

    final override = options.extra[name];
    final o = override is DiomanAuthOptions ? override : null;

    final prot = _computeIsProtected(options, o);
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
          DioException(
              requestOptions: options,
              message: '[auth] refresh failed; aborting'),
          true,
        );
      }
    }

    var token = _tokenManager.accessToken;
    if (token == null || token.isEmpty) {
      options.extra[_kDenied] = true;
      final synthResp = _synthDenied(options);
      final $onDenied = o?.onAccessDenied ?? _onDenied;
      final $onExpired = o?.onAccessExpired ?? _onExpired;
      await _safe(() =>
          $onDenied?.call(_tokenManager, synthResp) ??
          $onExpired(_tokenManager, synthResp));
      return handler.reject(
        DioException(
            requestOptions: options,
            message: '[auth] access denied — no token'),
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
    if (_isExpiring(token, o)) {
      final ok = await _startRefresh(_synthProactive(options));
      if (!ok) {
        options.extra[_kDenied] = true;
        await _expire(_synthProactive(options), o);
        return handler.reject(
          DioException(
            requestOptions: options,
            message: '[auth] proactive refresh failed; aborting',
          ),
          true,
        );
      }
      final fresh = _tokenManager.accessToken;
      if (fresh != null && fresh.isNotEmpty) token = fresh;
    }

    await _injectToken(options, token, o);
    handler.next(options);
  }

  /// Whether [token] is expired (or within the effective leeway of expiring),
  /// per the effective `expiresAt` (constructor default, or [o]'s override).
  /// Returns false when no `expiresAt` callback is available or it can't
  /// determine an expiry — the proactive path is strictly opt-in and never
  /// fabricates a refresh.
  ///
  /// 判断[token]是否已过期（或在有效提前量内即将过期），依据生效的`expiresAt`
  /// （构造函数默认值，或[o]里的覆盖值）。没有`expiresAt`回调或无法判断过期时间
  /// 时返回false——主动刷新路径是纯选择性开启的，绝不会臆造一次刷新。
  bool _isExpiring(String token, DiomanAuthOptions? o) {
    final $expiresAt = o?.expiresAt ?? _expiresAt;
    final at = $expiresAt?.call(token);
    if (at == null) return false;
    final $now = o?.now ?? _now;
    final $refreshLeeway = o?.refreshLeeway ?? _refreshLeeway;
    return !at.isAfter($now().add($refreshLeeway));
  }

  /// Injects the current [token] into [options] — via the effective `ready`
  /// callback if provided, otherwise via the effective `buildHeader`/
  /// `headerKey` — and stashes the raw token used so [defaultAuthFailure] can
  /// compare it against the store's current token directly (see
  /// [_kTokenUsed]). Used both for the initial request and to refresh the
  /// header before a post-refresh replay.
  ///
  /// 把当前[token]注入[options]——若有生效的`ready`回调则用它，否则用生效的
  /// `buildHeader`/`headerKey`——并暂存实际用到的原始token，供
  /// [defaultAuthFailure]直接跟store里的当前token比较（见[_kTokenUsed]）。
  /// 既用于首次请求注入，也用于刷新后重放前更新头部。
  Future<void> _injectToken(
      RequestOptions options, String token, DiomanAuthOptions? o) async {
    final $ready = o?.ready ?? _ready;
    if ($ready != null) {
      await _safe(() => $ready(_tokenManager, options));
    } else {
      final $headerKey = o?.headerKey ?? _headerKey;
      final $buildHeader = o?.buildHeader ?? _buildHeader;
      options.headers[$headerKey] = $buildHeader(token);
    }
    options.extra[_kTokenUsed] = token;
  }

  // ── Response (success path) ───────────────────────────────────────────────

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final opts = response.requestOptions;
    final bag = opts.extra;
    if (bag[_kProtected] != true) return handler.next(response);
    if (bag[_kDenied] == true) {
      _clearFlags(bag);
      _settleShare(opts, response: response);
      return handler.next(response);
    }

    // Treat business-level failures the same as HTTP 401/403 here:
    // the normalize-response plugin will already have converted them to errors,
    // so reaching this point with a successful HTTP code means the response is ok.
    _clearFlags(bag);
    // Always settle on a genuinely successful response — unlike the error
    // path, a plain success flows through every `.then()` stage in order
    // (no skip-on-resolve), so DiomanRetry's own onResponse (if also
    // registered) gets exactly the same response right after this and
    // would settle redundantly-but-harmlessly (settle() is idempotent).
    _settleShare(opts, response: response);
    handler.next(response);
  }

  // ── Response (error path) ─────────────────────────────────────────────────

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final bag = opts.extra;
    if (bag[_kProtected] != true) return handler.next(err);
    if (bag[_kDenied] == true) {
      _clearFlags(bag);
      _settleIfLastWord(opts, error: err);
      return handler.next(err);
    }

    final response = err.response;
    if (response == null) {
      _clearFlags(bag);
      _settleIfLastWord(opts, error: err);
      return handler.next(err);
    }

    final override = opts.extra[name];
    final o = override is DiomanAuthOptions ? override : null;

    final resolved = await _handleFailure(response, opts, err, o);
    if (resolved is Response) {
      // A DioException resolved into a Response bypasses every later
      // interceptor's onError (including DiomanRetry's, even if it's also
      // registered) — dio never re-runs a `.then()` response stage once the
      // flow already went through `.catchError()`. So THIS plugin must
      // settle here unconditionally; nothing downstream ever will.
      _settleShare(opts, response: resolved);
      handler.resolve(resolved);
    } else {
      _settleIfLastWord(opts, error: err);
      handler.next(err);
    }
  }

  /// Settles the shared [DiomanShare] entry for [opts] with [error] — but
  /// only if this plugin is the ONLY registered settler. If
  /// [DiomanRetry] is ALSO registered (via its own `share` setter), it
  /// always runs after this plugin in the canonical chain and always
  /// settles unconditionally, so deferring to it here avoids delivering a
  /// pre-retry outcome to a caller dedup'd via [DiomanShare].
  void _settleIfLastWord(RequestOptions opts, {required DioException error}) {
    if (_share?.hasMultipleDownstreamSettlers ?? false) return;
    _settleShare(opts, error: error);
  }

  void _settleShare(
    RequestOptions opts, {
    Response<dynamic>? response,
    DioException? error,
  }) {
    final share = _share;
    if (share == null) return;
    final key = opts.extra[kKey] as String?;
    if (key == null) return;
    share.settle(key, response: response, error: error);
  }

  // ── Failure routing ───────────────────────────────────────────────────────

  Future<Object?> _handleFailure(
    Response<dynamic> response,
    RequestOptions opts,
    DioException original,
    DiomanAuthOptions? o,
  ) async {
    final bag = opts.extra;

    if (bag[_kRefreshed] == true) {
      // Already replayed once — give up.
      await _expire(response, o);
      _clearFlags(bag);
      return null;
    }

    final $onFailure = o?.onFailure ?? _onFailure;
    final $headerKey = o?.headerKey ?? _headerKey;
    final action = await _safe(
          () async =>
              $onFailure?.call(_tokenManager, response) ??
              defaultAuthFailure(_tokenManager, response, $headerKey),
        ) ??
        DiomanAuthFailureAction.others;

    switch (action) {
      case DiomanAuthFailureAction.refresh:
        final ok = await _startRefresh(response);
        if (ok) {
          bag[_kRefreshed] = true;
          // Re-inject with the freshly refreshed token — the throwaway Dio
          // has no interceptors, so nothing else will update the header.
          final fresh = _tokenManager.accessToken;
          if (fresh != null && fresh.isNotEmpty)
            await _injectToken(opts, fresh, o);
          final replayed = await _fetchReplay(opts);
          if (replayed != null) return replayed;
        }
        await _expire(response, o);
        _clearFlags(bag);
        return null;

      case DiomanAuthFailureAction.replay:
        bag[_kRefreshed] = true;
        // Someone else's refresh may have landed a new token since this
        // request's header was built — carry the current one on replay.
        final current = _tokenManager.accessToken;
        if (current != null && current.isNotEmpty)
          await _injectToken(opts, current, o);
        final replayed = await _fetchReplay(opts);
        if (replayed != null) return replayed;
        _clearFlags(bag);
        return null;

      case DiomanAuthFailureAction.deny:
        final $onDenied = o?.onAccessDenied ?? _onDenied;
        final $onExpired = o?.onAccessExpired ?? _onExpired;
        await _safe(() => ($onDenied ?? $onExpired)(_tokenManager, response));
        _clearFlags(bag);
        return null;

      case DiomanAuthFailureAction.expired:
        await _expire(response, o);
        _clearFlags(bag);
        return null;

      case DiomanAuthFailureAction.others:
        _clearFlags(bag);
        return null;
    }
  }

  /// Issues the replay via [_replay], tracking [opts]'s cancel token with
  /// [_cancel] for the duration so `cancelAll()` can see (and abort) it —
  /// see [_cancel]'s doc for why that tracking doesn't happen on its own.
  /// Returns `null` on any failure (mirrors the original bare
  /// `try { ... } catch (_) {}` this replaces).
  Future<Response<dynamic>?> _fetchReplay(RequestOptions opts) async {
    final token = opts.cancelToken;
    if (token != null) _cancel?.track(token);
    try {
      return await _replay.fetch<dynamic>(opts);
    } catch (_) {
      return null;
    } finally {
      if (token != null) _cancel?.untrack(token);
    }
  }

  Future<bool> _startRefresh(Response<dynamic> resp) {
    return _refreshing ??= (() async {
      try {
        await _onRefresh(_tokenManager, resp);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    })();
  }

  Future<void> _expire(Response<dynamic> resp, DiomanAuthOptions? o) async {
    _tokenManager.clear();
    final $onExpired = o?.onAccessExpired ?? _onExpired;
    await _safe(() => $onExpired(_tokenManager, resp));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _computeIsProtected(RequestOptions opts, DiomanAuthOptions? o) {
    final cached = opts.extra[_kDecision];
    if (cached is bool) return cached; // replay: reuse first decision

    if (o?.enabled != null) return o!.enabled!;

    final $isProtected = o?.isProtected ?? _isProtected;
    if ($isProtected != null) {
      return $isProtected(opts);
    }

    return true; // default: protect everything
  }

  Response<dynamic> _synthDenied(RequestOptions opts) => Response<dynamic>(
        requestOptions: opts,
        statusCode: 0,
        statusMessage: 'ACCESS_DENIED',
        data: {
          'code': 'ACCESS_DENIED',
          'message': 'protected request without accessToken'
        },
      );

  /// Placeholder [Response] handed to [_onRefresh] / [_onExpired] on the
  /// proactive path — there is no server response yet (the token was refreshed
  /// before sending). `onRefresh` implementations normally ignore this and
  /// refresh from the token manager; the `PROACTIVE_REFRESH` marker lets a
  /// caller that does inspect it tell this apart from a reactive 401.
  ///
  /// 主动刷新路径上传给[_onRefresh]/[_onExpired]的占位[Response]——此时还没有
  /// 真实服务端响应（token在发送前就已刷新）。`onRefresh`实现通常会忽略它，
  /// 直接从token manager刷新；`PROACTIVE_REFRESH`标记方便想区分的调用方
  /// 把它跟被动401区分开来。
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
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _refreshing = null;
    _replayDio?.close(force: true);
    _replayDio = null;
  }
}
