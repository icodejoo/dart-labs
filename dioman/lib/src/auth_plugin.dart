// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:dio/dio.dart';
import 'cancel_plugin.dart';
import 'dioman_plugin.dart';
import 'replay_support.dart';
import 'request_claims.dart';
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

  /// No longer needed: [DiomanCancel] now keeps tracking a request for as long
  /// as this plugin still holds it (refresh wait, replay). Kept as a no-op for
  /// compatibility.
  ///
  /// 已不再需要：只要本插件还持有请求（刷新等待、重放期间），[DiomanCancel]
  /// 就会持续追踪它。仅作兼容保留，无效果。
  @Deprecated('Cancel tracking now covers the whole logical request; '
      'this setter has no effect.')
  set cancel(DiomanCancel? value) {}

  /// No longer needed: this plugin now registers its settlement
  /// responsibility on each protected request itself, so [DiomanShare] waits
  /// for the true final outcome. Kept as a no-op for compatibility.
  ///
  /// 已不再需要：本插件现在自己在每个受保护请求上登记结算责任，[DiomanShare]
  /// 因此会等到真正的最终结果。仅作兼容保留，无效果。
  @Deprecated('Settlement responsibility is registered per request now; '
      'this setter has no effect.')
  set share(DiomanShare? value) {}

  Future<bool>? _refreshing; // shared window; bool = success
  /// 同一失效会话只通知一次；获得新令牌后重新允许通知。
  bool _expiredNotified = false;

  /// 所有过期请求共享的稳定错误消息，便于调用方识别。
  static const _expiredMessage = '[auth] session expired';
  // 共享刷新窗口；bool表示是否成功

  // 重放用的传输层：绑定宿主 Dio 后借用其 adapter/transformer（自定义代理、证书、
  // 序列化行为保持一致），未绑定时退回无拦截器的裸 Dio，重放不会重新进入本链路。
  // 在 [dispose] 中释放。
  final _replay = ReplayClient();

  /// Binds the host [Dio] this plugin is installed on, so replays reuse its
  /// adapter/transformer and a recovered result reaches the interceptors after
  /// this plugin (normalize, breaker, ...). [Dioman.install] / [DiomanHandle]
  /// bind it automatically; set it by hand only when wiring the chain
  /// yourself. `null` unbinds.
  ///
  /// 绑定本插件所在的宿主[Dio]，让重放复用它的adapter/transformer，并让恢复成功
  /// 的结果进入排在本插件之后的拦截器（normalize、breaker等）。
  /// [Dioman.install]/[DiomanHandle]会自动绑定，只有自己手动拼链时才需要设置。
  /// 传`null`解绑。
  set dio(Dio? value) => _replay.bind(value);

  static String _defaultBearer(String t) => 'Bearer $t';

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:auth';
  // extra keys — plain strings so they survive Dio's mergeConfig on replay
  //
  // extra key——用纯字符串常量，保证重放时能在Dio的mergeConfig中存活
  static const _kDecision = '$pluginName:decision';
  static const _kProtected = '$pluginName:protected';
  static const _kRefreshed = '$pluginName:refreshed';
  static const _kDenied = '$pluginName:denied';
  static const _kTokenUsed = '$pluginName:tokenUsed';

  @override
  String get name => pluginName;

  // ── Request ───────────────────────────────────────────────────────────────

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    unawaited(_guardRequest(options, handler));
  }

  /// 请求阶段入口的兜底：回调（isProtected/expiresAt/now/buildHeader 等）抛出的
  /// 异常转成 [DioException]，注销认领后走错误链，保证 handler 恰好完成一次，
  /// 不让请求悬挂（部分 dio 版本不观察 async 拦截器返回的 Future）。
  Future<void> _guardRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      // 刷新等待与取消竞争：取消时立刻拒绝并注销认领，共享的刷新本身继续。
      final cancelled = await raceCancel<DioException?>(
        _handleRequest(options, handler).then<DioException?>((_) => null),
        options.cancelToken,
        (e) => e,
      );
      if (cancelled != null && !handler.isCompleted) {
        options.extra[_kDenied] = true;
        handler.reject(cancelled, true);
      }
    } catch (e, s) {
      if (handler.isCompleted) return;
      final err =
          DioException(requestOptions: options, error: e, stackTrace: s);
      // 标记已拒绝：随后本插件的 onError 看到它就注销认领（含 share 结算）。
      options.extra[_kDenied] = true;
      handler.reject(err, true);
    }
  }

  /// 请求阶段的实际逻辑：受保护判定、认领、等刷新、主动刷新、注入 token。
  Future<void> _handleRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (!enabled) return handler.next(options);

    final override = options.extra[name];
    final o = override is DiomanAuthOptions ? override : null;

    final prot = _computeIsProtected(options, o);
    options.extra[_kDecision] = prot;
    if (!prot) return handler.next(options);

    options.extra[_kProtected] = true;
    // 认领这次请求的结算责任：刷新/重放可能改写最终结果，下游的 share 因此等到
    // 真正的最终结果才结算，cancel 因此在整个逻辑请求期间持续追踪 token。
    // 每条出口（onResponse/onError）都会注销。
    claimRequest(options, this);

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
    _expiredNotified = false;
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
    // 原始 500 已经过 auth 错误出口时会清掉临时标记；重试后到来的 401
    // 仍须比较原始裸令牌，不能拿 Bearer 头与裸令牌比较而误判为已刷新。
    final carriedToken = token;
    claimsOf(options)?.recoverAuth = (error) async {
      if (error.response == null) return null;
      options.extra.putIfAbsent(_kTokenUsed, () => carriedToken);
      final action = _decideFailure(error.response!, o);
      if (action == DiomanAuthFailureAction.others) return null;
      return _handleFailure(error.response!, options, o, decision: action);
    };
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
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    final opts = response.requestOptions;
    final bag = opts.extra;
    if (bag[_kProtected] != true) return handler.next(response);

    // 业务级失败（HTTP 200 但业务码非成功）不在这里处理：normalize 装在链条最后，
    // 此时还没运行；业务失败由 retry 恢复，normalize 稍后才把它转成错误。
    // 这里只交出自己的结算责任——后面如果还有 retry 认领着，最终结果由它交出。
    _clearFlags(bag);
    ReplayClient.handOffResponse(opts, this, response, handler);
  }

  // ── Response (error path) ─────────────────────────────────────────────────

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    unawaited(_handleError(err, handler));
  }

  /// 错误阶段：401/403 路由、刷新、重放。无论哪条出口都注销本请求上的认领，
  /// handler 恰好完成一次。
  Future<void> _handleError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final opts = err.requestOptions;
    final bag = opts.extra;
    try {
      if (bag[_kProtected] != true) return handler.next(err);
      final response = err.response;
      if (bag[_kDenied] == true || response == null || isJoined(opts)) {
        _clearFlags(bag);
        return _replay.handOffError(this, opts, err, handler);
      }

      final override = opts.extra[name];
      final o = override is DiomanAuthOptions ? override : null;

      // 刷新/重放等待与取消竞争：取消时立刻交出 handler、注销认领（共享的刷新
      // 本身继续跑）。
      final resolved = await raceCancel<Object?>(
        _handleFailure(response, opts, o),
        opts.cancelToken,
        _Cancelled.new,
      );
      if (resolved is _Cancelled) {
        _clearFlags(bag);
        return _replay.handOffError(this, opts, resolved.error, handler);
      }
      if (resolved is Response<dynamic>) {
        // 重放成功：交给排在本插件之后的拦截器处理（normalize、breaker、
        // retry 的业务判定等），与首次成功语义一致，再终结链路。成功路径沿用旧行为，
        // 不清标志位（同一个 RequestOptions 再次分发时靠它命中"已重放过"保护）。
        return await _replay.finishRecovered(this, opts, resolved, handler);
      }
      // 重放自己的异常（如 500/断网）优先于旧的 401 往后传。
      final failure = resolved is DioException ? resolved : err;
      _replay.handOffError(this, opts, failure, handler);
    } catch (e, s) {
      _clearFlags(bag);
      final failure =
          DioException(requestOptions: opts, error: e, stackTrace: s);
      if (!handler.isCompleted) {
        _replay.handOffError(this, opts, failure, handler);
      }
    }
  }

  // ── Failure routing ───────────────────────────────────────────────────────

  /// 返回值：[Response] 表示重放成功；[DioException] 表示重放本身的失败，应
  /// 取代旧的 401 往后传；null 表示原样传播旧错误。
  Future<Object?> _handleFailure(
    Response<dynamic> response,
    RequestOptions opts,
    DiomanAuthOptions? o, {
    DiomanAuthFailureAction? decision,
  }) async {
    final bag = opts.extra;

    if (bag[_kRefreshed] == true) {
      // Already replayed once — give up. 用 token generation 校验，别让旧请求
      // 清掉别人刚刷新出来的新会话。
      return _expireAndFail(response, o, bag,
          staleToken: bag[_kTokenUsed] as String?);
    }

    final action = decision ??
        await _safe(() async => _decideFailure(response, o)) ??
        DiomanAuthFailureAction.others;

    switch (action) {
      case DiomanAuthFailureAction.refresh:
        final ok = await _startRefresh(response);
        if (!ok) return _expireAndFail(response, o, bag);
        // 等刷新期间请求已被取消：不再重放（调用方早已拿到取消结果）。
        if (opts.cancelToken?.isCancelled == true) return null;
        bag[_kRefreshed] = true;
        // Re-inject with the freshly refreshed token — the replay client has
        // no interceptors, so nothing else will update the header.
        final fresh = _tokenManager.accessToken;
        if (fresh != null && fresh.isNotEmpty) {
          await _injectToken(opts, fresh, o);
        }
        return _settleReplay(await _replayOnce(opts), response, o, bag);

      case DiomanAuthFailureAction.replay:
        bag[_kRefreshed] = true;
        // Someone else's refresh may have landed a new token since this
        // request's header was built — carry the current one on replay.
        final current = _tokenManager.accessToken;
        if (current != null && current.isNotEmpty) {
          await _injectToken(opts, current, o);
        }
        return _settleReplay(await _replayOnce(opts), response, o, bag);

      case DiomanAuthFailureAction.deny:
        final $onDenied = o?.onAccessDenied ?? _onDenied;
        final $onExpired = o?.onAccessExpired ?? _onExpired;
        await _safe(() => ($onDenied ?? $onExpired)(_tokenManager, response));
        _clearFlags(bag);
        return null;

      case DiomanAuthFailureAction.expired:
        return _expireAndFail(response, o, bag);

      case DiomanAuthFailureAction.others:
        _clearFlags(bag);
        return null;
    }
  }

  /// 按请求级或插件级 onFailure 判定失败动作，未配置时用默认规则。
  DiomanAuthFailureAction _decideFailure(
          Response<dynamic> response, DiomanAuthOptions? o) =>
      (o?.onFailure ?? _onFailure)?.call(_tokenManager, response) ??
      defaultAuthFailure(_tokenManager, response, o?.headerKey ?? _headerKey);

  /// 结束会话并清标记，返回给调用方的过期错误；[reported] 为空时用 [response]。
  Future<DioException> _expireAndFail(
    Response<dynamic> response,
    DiomanAuthOptions? o,
    Map<dynamic, dynamic> bag, {
    String? staleToken,
    Response<dynamic>? reported,
  }) async {
    await _expire(response, o, staleToken: staleToken);
    _clearFlags(bag);
    return _expiredError(reported ?? response);
  }

  /// 收尾一次重放：成功给响应；仍是认证失败就结束会话；500、断网等暂时性
  /// 故障不能清掉刚刷新出来的有效 token，原样交出重放错误。
  Future<Object?> _settleReplay(
    ({Response<dynamic>? response, DioException? error}) replayed,
    Response<dynamic> response,
    DiomanAuthOptions? o,
    Map<dynamic, dynamic> bag,
  ) async {
    if (replayed.response != null) return replayed.response;
    final failed = replayed.error?.response;
    if (_isReplayAuthFailure(failed, o)) {
      return _expireAndFail(response, o, bag,
          staleToken: bag[_kTokenUsed] as String?, reported: failed);
    }
    _clearFlags(bag);
    return replayed.error;
  }

  /// 通过重放客户端重放 [opts]，从不抛异常：成功给 response，失败给 error；
  /// 请求体无法重放（Stream 等）时两者都为 null，调用方应原样传播旧错误。
  Future<({Response<dynamic>? response, DioException? error})> _replayOnce(
      RequestOptions opts) async {
    if (!prepareForReplay(opts)) return (response: null, error: null);
    try {
      return (response: await _replay.fetch(opts), error: null);
    } on DioException catch (e) {
      return (response: null, error: e);
    } catch (e, s) {
      return (
        response: null,
        error: DioException(requestOptions: opts, error: e, stackTrace: s),
      );
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

  /// 会话过期：清空 token 并调用过期回调。传入 [staleToken]（失败请求实际用的
  /// token）时先校验 generation——store 里已是别人刷新出的新 token，就不清，
  /// 避免旧请求的失败清掉新会话。
  Future<void> _expire(
    Response<dynamic> resp,
    DiomanAuthOptions? o, {
    String? staleToken,
  }) async {
    if (staleToken != null) {
      final current = _tokenManager.accessToken;
      if (current != null && current.isNotEmpty && current != staleToken) {
        return;
      }
    }
    if (_expiredNotified && _tokenManager.accessToken == null) return;
    _expiredNotified = true;
    _tokenManager.clear();
    final $onExpired = o?.onAccessExpired ?? _onExpired;
    await _safe(() => $onExpired(_tokenManager, resp));
  }

  /// 保留原响应，给每个过期请求提供稳定的失败标识。
  DioException _expiredError(Response<dynamic> response) => DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: _expiredMessage,
      );

  /// HTTP 或自定义业务路由确认重放仍是认证失败时结束会话。
  bool _isReplayAuthFailure(Response<dynamic>? response, DiomanAuthOptions? o) {
    if (response == null) return false;
    if (response.statusCode == 401) return true;
    final action = (o?.onFailure ?? _onFailure)?.call(_tokenManager, response);
    return action == DiomanAuthFailureAction.refresh ||
        action == DiomanAuthFailureAction.replay ||
        action == DiomanAuthFailureAction.expired;
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
    _replay.dispose();
  }
}

/// 刷新/重放等待期间请求被取消的标记（内部用）。
class _Cancelled {
  _Cancelled(this.error);

  /// 取消异常。
  final DioException error;
}
