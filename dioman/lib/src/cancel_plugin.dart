import 'package:dio/dio.dart';
import 'dioman_plugin.dart';
import 'request_claims.dart';
import 'auth_plugin.dart';
import 'cache_plugin.dart';
import 'mock_plugin.dart';
import 'retry_plugin.dart';
import 'share_plugin.dart';
import 'plugin_order.dart';

/// Construction-time options for [DiomanCancel]. Cancel has no per-request
/// behavior (it's driven by [cancelAll]), so this only controls whether the
/// plugin is enabled at all.
///
/// [DiomanCancel]的构造期选项。cancel没有单请求级行为（靠[cancelAll]驱动），
/// 这里只控制插件整体是否生效。
class DiomanCancelOptions {
  const DiomanCancelOptions({this.enabled = true});

  /// `false` disables the plugin entirely — it stops injecting/tracking
  /// [CancelToken]s and passes every request through untouched.
  ///
  /// `false`时插件整体失效——不再注入/追踪[CancelToken]，所有请求原样通过。
  final bool enabled;
}

/// Injects a [CancelToken] into every request that does not already
/// have one, and maintains a registry so [cancelAll] can abort all
/// in-flight requests for a given [Dio] instance.
///
/// 给还没有[CancelToken]的请求注入一个，并维护一份登记表，供[cancelAll]
/// 中断某个[Dio]实例上所有在途请求。
///
/// Requests that supply their own [CancelToken] via `options.cancelToken`
/// are left untouched.
///
/// 请求若自带[CancelToken]（通过`options.cancelToken`），则原样不动。
///
/// ```dart
/// final cancelPlugin = DiomanCancel();
/// dio.interceptors.add(cancelPlugin);
///
/// // Later, abort everything (e.g. page navigation):
/// cancelAll(dio, 'page left');
/// ```
class DiomanCancel extends DiomanPlugin {
  DiomanCancel({bool enabled = true})
      : _tokens = {},
        config = DiomanCancelOptions(enabled: enabled);

  /// Tokens this plugin instance currently tracks.
  ///
  /// 本插件实例当前追踪的token集合。
  final Set<CancelToken> _tokens;

  /// This plugin's resolved construction-time options.
  ///
  /// 本插件解析后的构造期选项。
  final DiomanCancelOptions config;

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:cancel';
  static const _kToken = '$pluginName:token';

  @override
  String get name => pluginName;

  /// 顺序声明：cancel在cache/share/mock之后（命中时不遗留括号），在auth/retry之前（401或重试前清理已完成）。
  @override
  DiomanPluginOrder get ordering => const DiomanPluginOrder(
        after: {
          DiomanCache.pluginName,
          DiomanShare.pluginName,
          DiomanMock.pluginName,
        },
        before: {DiomanAuth.pluginName, DiomanRetry.pluginName},
      );

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!config.enabled) return handler.next(options);

    final existing = options.cancelToken;
    if (existing != null) {
      // Covers a RequestOptions object re-entering this onRequest a second
      // time still carrying the token this plugin injected on an earlier
      // pass (e.g. a caller manually re-dispatching the same RequestOptions
      // through this same Dio). _release already deregistered it after that
      // earlier pass's response/error, so without this it would stay
      // untracked — and uncancellable via cancelAll — from here on. Only
      // re-register tokens this plugin itself injected (never a
      // caller-supplied one) and that aren't already spent. DiomanRetry/
      // DiomanAuth/DiomanShare's internal re-issues never reach this branch
      // (they use an interceptor-less client); they stay trackable because
      // they hold the request via its claims, which defers [_release].
      //
      // 应对同一个RequestOptions对象第二次进到这个onRequest，且身上还带着
      // 本插件上一轮注入的token（比如调用方手动把同一个RequestOptions再次
      // 通过这同一个Dio分发一次）。_release已经在上一轮响应/错误之后把它
      // 注销了，若不这样重新注册，从此它就会一直处于未被追踪、无法被
      // cancelAll中断的状态。只重新注册本插件自己注入过的token（绝不是
      // 调用方自带的），且必须还没被用掉。DiomanRetry/DiomanAuth/DiomanShare
      // 自己内部的重新发起不会走到这个分支（它们用的是不带拦截器的客户端）；
      // 它们靠认领登记簿持有请求，从而推迟[_release]，保持可追踪。
      if (options.extra[_kToken] == existing && !existing.isCancelled) {
        _tokens.add(existing);
      }
      return handler.next(options);
    }

    final token = CancelToken();
    options.cancelToken = token;
    // dio's own `Options.compose` only wires `cancelToken.requestOptions`
    // for a token the CALLER already attached before compose runs (see
    // options.dart). A token this plugin attaches afterwards, here in
    // onRequest, never gets that backfilled — so without this line,
    // `CancelToken.cancel()` falls back to a brand-new, empty
    // `RequestOptions()` for the resulting DioException (cancel_token.dart),
    // wiping out every other plugin's per-request `extra` state (share's
    // entry key, loading's bracket flag, retry's counter, ...) on
    // cancellation.
    token.requestOptions = options;
    options.extra[_kToken] = token;
    _tokens.add(token);
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _release(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _release(err.requestOptions);
    handler.next(err);
  }

  /// 结束对本请求 token 的追踪。下游（auth/retry）还认领着这次逻辑请求时
  /// （退避、刷新等待、重放期间）先不注销，等它们交出最终结果、登记簿清空后
  /// 再注销，这样整个逻辑请求期间 [cancelAll] 都能看到它。
  void _release(RequestOptions options) {
    final token = options.extra[_kToken] as CancelToken?;
    if (token == null) return;
    final claims = claimsOf(options);
    if (claims != null && claims.hasOwners) {
      claims.whenDrained(() => _untrackAfter(claims.loser, token));
    } else {
      _untrackAfter(claims?.loser, token);
    }
  }

  /// 注销 [token]；若该请求在 share 仲裁中落败、仍在等胜出结果 [wait]，则持续
  /// 追踪到结果交付，这样 [cancelAll] 仍能取消这个等待中的调用者。
  void _untrackAfter(Future<Response<dynamic>>? wait, CancelToken token) {
    if (wait == null) {
      _tokens.remove(token);
    } else {
      wait.then<void>((_) => _tokens.remove(token),
          onError: (Object _) => _tokens.remove(token));
    }
  }

  /// Manually registers [token] so it's included in a later [cancelAll] — for
  /// a custom plugin that re-dispatches a request through an interceptor-less
  /// client. [DiomanAuth]/[DiomanRetry]/[DiomanShare] no longer need it: they
  /// hold the request so this plugin keeps tracking it for the whole logical
  /// request. No-op if the plugin is disabled.
  ///
  /// 手动登记[token]，让后续的[cancelAll]能追踪到它——供自定义插件通过不带
  /// 拦截器的客户端重新分发请求时使用。[DiomanAuth]/[DiomanRetry]/
  /// [DiomanShare]已不再需要它：它们会持有请求，本插件因此在整个逻辑请求期间
  /// 持续追踪。插件被禁用时是no-op。
  void track(CancelToken token) {
    if (config.enabled) _tokens.add(token);
  }

  /// Removes [token] from tracking — the counterpart to [track], called once
  /// whatever bypassed onRequest has settled (so it isn't left registered
  /// forever after it's no longer in flight).
  ///
  /// 从追踪列表移除[token]——[track]的对应操作，在绕开onRequest的那次调用
  /// 结算完毕后调用（否则它会在不再在途之后依然被永久登记着）。
  void untrack(CancelToken token) => _tokens.remove(token);

  /// Cancel all in-flight requests managed by this plugin instance.
  /// Returns the number of tokens cancelled.
  ///
  /// 中断本插件实例管理的所有在途请求，返回被中断的token数量。
  int cancelAll([String? reason]) {
    final n = _tokens.length;
    for (final t in _tokens) {
      t.cancel(reason ?? 'cancelAll');
    }
    _tokens.clear();
    return n;
  }

  @override
  void dispose() {
    cancelAll('plugin ejected');
  }
}

/// Convenience top-level helper.
/// Finds [DiomanCancel] by name on [dio] and calls [DiomanCancel.cancelAll].
/// Returns the count, or 0 if the plugin is not installed.
///
/// 便捷的顶层辅助函数。在[dio]上找到[DiomanCancel]并调用
/// [DiomanCancel.cancelAll]。若插件未安装则返回0。
int cancelAll(Dio dio, [String? reason]) {
  final plugin = dio.interceptors
      .whereType<DiomanCancel>()
      .firstOrNull;
  return plugin?.cancelAll(reason) ?? 0;
}
