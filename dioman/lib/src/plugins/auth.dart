import 'dart:async';
import '../client.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../request.dart';
import '../response.dart';
import '../stages.dart';
import '../token_manager.dart';

/// 鉴权失败后的处理动作。
enum DiomanAuthFailureAction {
  /// 加入或发起单飞刷新。
  refresh,

  /// 用当前凭证直接重放。
  replay,

  /// 通知访问拒绝。
  deny,

  /// 结束失败请求所属会话。
  expired,

  /// 原样返回，与鉴权无关。
  others,
}

/// 通知回调，异常隔离；接收存储与失败结果。
typedef DiomanAuthNotice = FutureOr<void> Function(
    DiomanTokenManager tokens, DiomanResponse<dynamic> result);

/// 刷新回调自行调用 setTokens；同步与异步异常均算刷新失败。
typedef DiomanAuthRefresh = FutureOr<void> Function(
    DiomanTokenManager tokens, DiomanResponse<dynamic> result);

/// 判定回调，异常按程序错误落定。
typedef DiomanAuthFailure = FutureOr<DiomanAuthFailureAction> Function(
    DiomanResponse<dynamic> result, DiomanTokenManager tokens);

/// 返回注入补丁；回调需使用传入存储的当前原始凭证。
typedef DiomanAuthReady = FutureOr<RequestPatch> Function(
    DiomanTokenManager tokens, DiomanRequest request);

/// 默认按逻辑状态判定；[injectedToken] 是最后一次调用 ready 前的凭证快照。
/// 例如旧请求携带 a、当前为 b 时返回 replay，保留新会话。
DiomanAuthFailureAction defaultAuthFailure(DiomanResponse<dynamic> result,
    DiomanTokenManager tokens, String? injectedToken) {
  if (result.status == 403) return DiomanAuthFailureAction.deny;
  if (result.status != 401) return DiomanAuthFailureAction.others;
  final current = tokens.accessToken;
  if (current == null || current.isEmpty) {
    return DiomanAuthFailureAction.expired;
  }
  return injectedToken != current
      ? DiomanAuthFailureAction.replay
      : DiomanAuthFailureAction.refresh;
}

/// 请求级覆盖；null 字段继承插件配置。
class DiomanAuthOptions {
  /// 设置本次请求的鉴权选项，例如 `DiomanAuthOptions(enabled: false)`。
  const DiomanAuthOptions(
      {this.enabled,
      this.onAccessDenied,
      this.onAccessExpired,
      this.onFailure,
      this.isProtected,
      this.ready,
      this.expiresAt,
      this.refreshLeeway,
      this.refreshTimeout,
      this.headerKey,
      this.buildHeader});

  /// true 强制保护、false 公开；null 使用 isProtected。
  final bool? enabled;

  /// 本地拒绝与服务端拒绝通知；缺省回退过期通知。
  final DiomanAuthNotice? onAccessDenied;

  /// 会话过期通知；同一失败会话只通知一次。
  final DiomanAuthNotice? onAccessExpired;

  /// 异步失败路由；internal 与 cancel 不参与。
  final DiomanAuthFailure? onFailure;

  /// 每次尝试入口判定一次是否保护。
  final bool Function(DiomanRequest request)? isProtected;

  /// 异步生成凭证补丁；凭证变化时最多重做三次。
  final DiomanAuthReady? ready;

  /// 读取凭证过期时间，null 不主动刷新。
  final DateTime? Function(String token)? expiresAt;

  /// 过期提前量。
  final Duration? refreshLeeway;

  /// 刷新窗口上限，使用客户端时钟计时。
  final Duration? refreshTimeout;

  /// 默认注入的请求头名称。
  final String? headerKey;

  /// 格式化原始凭证。
  final String Function(String token)? buildHeader;
}

/// 凭证注入、会话判定与每客户端单飞刷新。
class DiomanAuth<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// onRefresh 写入新凭证；抛错算刷新失败，通知回调抛错不改变结果。
  /// 示例：`DiomanAuth(tokenManager: store, onRefresh: refresh, onAccessExpired: logout)`。
  const DiomanAuth(
      {required this.tokenManager,
      required this.onRefresh,
      this.enabled = true,
      this.onAccessDenied,
      required this.onAccessExpired,
      this.onFailure,
      this.isProtected,
      this.ready,
      this.expiresAt,
      this.refreshLeeway = Duration.zero,
      this.refreshTimeout = const Duration(seconds: 30),
      this.headerKey = 'Authorization',
      this.buildHeader = defaultBuildHeader});

  /// 凭证存储，由调用方持有。
  final DiomanTokenManager tokenManager;

  /// 刷新操作独立于调用方取消。
  final DiomanAuthRefresh onRefresh;

  /// 安装或请求级开关。
  @override
  final bool enabled;

  /// 本地拒绝与服务端拒绝通知；缺省回退过期通知。
  final DiomanAuthNotice? onAccessDenied;

  /// 会话过期通知；同一失败会话只通知一次。
  final DiomanAuthNotice onAccessExpired;

  /// 异步失败路由；internal 与 cancel 不参与。
  final DiomanAuthFailure? onFailure;

  /// 每次尝试入口判定一次是否保护。
  final bool Function(DiomanRequest request)? isProtected;

  /// 异步生成凭证补丁；凭证变化时最多重做三次。
  final DiomanAuthReady? ready;

  /// 读取凭证过期时间，null 不主动刷新。
  final DateTime? Function(String token)? expiresAt;

  /// 过期提前量。
  final Duration refreshLeeway;

  /// 刷新窗口上限，默认三十秒。
  final Duration refreshTimeout;

  /// 默认注入的请求头名称。
  final String headerKey;

  /// 格式化原始凭证。
  final String Function(String token) buildHeader;

  /// ready 稳定化最多执行次数；超过就以最后一次为准，避免无限追赶。
  static const readyStableAttempts = 3;

  /// 稳定名称。
  static const pluginName = 'dioman:auth';

  /// 请求级选项键，支持 bool 与 DiomanAuthOptions。
  static final option = DiomanOptionKey<DiomanAuthOptions>(pluginName);

  /// 实际注入凭证状态；用于自定义探针，不通过请求头反推。
  static final injectedToken = StateKey<String?>('auth.injectedToken');

  /// 默认 Bearer 格式。
  static String defaultBuildHeader(String token) => 'Bearer $token';

  /// 固定名称。
  @override
  String get name => pluginName;

  /// 凭证阶段。
  @override
  DiomanStage get stage => DiomanStage.credential;

  /// 每次安装新建刷新窗口与过期标记。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) => _Auth<R>(
      this,
      DiomanAuthOptions(
          onAccessDenied: onAccessDenied,
          onAccessExpired: onAccessExpired,
          onFailure: onFailure,
          isProtected: isProtected,
          ready: ready,
          expiresAt: expiresAt,
          refreshLeeway: refreshLeeway,
          refreshTimeout: refreshTimeout,
          headerKey: headerKey,
          buildHeader: buildHeader));
}

/// 合并请求级配置。
DiomanAuthOptions _merge(DiomanAuthOptions a, DiomanAuthOptions b) =>
    DiomanAuthOptions(
        enabled: b.enabled,
        onAccessDenied: b.onAccessDenied ?? a.onAccessDenied,
        onAccessExpired: b.onAccessExpired ?? a.onAccessExpired,
        onFailure: b.onFailure ?? a.onFailure,
        isProtected: b.isProtected ?? a.isProtected,
        ready: b.ready ?? a.ready,
        expiresAt: b.expiresAt ?? a.expiresAt,
        refreshLeeway: b.refreshLeeway ?? a.refreshLeeway,
        refreshTimeout: b.refreshTimeout ?? a.refreshTimeout,
        headerKey: b.headerKey ?? a.headerKey,
        buildHeader: b.buildHeader ?? a.buildHeader);

/// 每客户端的刷新窗口与失败会话标记。
class _Auth<R extends DiomanResponse<dynamic>> extends DiomanPluginInstance<R> {
  /// 保存预合并配置。
  _Auth(this.config, this.base);

  /// 插件配置。
  final DiomanAuth<R> config;

  /// 预合并配置。
  final DiomanAuthOptions base;

  /// 不随调用方取消的刷新窗口。
  Future<bool>? _refreshing;

  /// 已通知过期的会话凭证。
  String? _expiredSession;

  /// 稳定的失败原因。
  static const _expired = 'expired';

  /// 当前存储。
  DiomanTokenManager get _tokens => config.tokenManager;

  /// 当前是否仍有本地凭证。
  bool get _hasToken => _tokens.accessToken?.isNotEmpty == true;

  /// 通知异常隔离，不影响刷新或请求结果。
  Future<void> _notice(DiomanContext<R> ctx, DiomanAuthNotice notice,
      DiomanResponse<dynamic> r) async {
    try {
      await notice(_tokens, r);
    } catch (e, s) {
      ctx.client.logError('[${DiomanAuth.pluginName}] 鉴权通知失败: $e\n$s');
    }
  }

  /// 只结束失败请求所属会话，旧请求不能清新凭证。
  Future<void> _expire(DiomanContext<R> ctx, DiomanAuthOptions o,
      DiomanResponse<dynamic> r, String? session) async {
    final current = _tokens.accessToken;
    if (_hasToken && current != session) return;
    if (!_hasToken && session == _expiredSession) return;
    _expiredSession = session;
    _tokens.clear();
    await _notice(ctx, o.onAccessExpired!, r);
  }

  /// 启动强制异步刷新；窗口发布先于用户回调，同步抛错也必释放。
  Future<bool> _refresh(DiomanContext<R> ctx, DiomanAuthOptions o,
      DiomanResponse<dynamic> r, String? session) {
    return _refreshing ??= (() async {
      final snapshot = _tokens.accessToken;
      try {
        final done = Completer<void>();
        final timer = ctx.clock.createTimer(o.refreshTimeout!, () {
          if (!done.isCompleted) done.completeError(TimeoutException('刷新超时'));
        });
        Future<void>(() => config.onRefresh(_tokens, r)).then((_) {
          if (!done.isCompleted) done.complete();
        }, onError: (Object e, StackTrace s) {
          if (!done.isCompleted) done.completeError(e, s);
        });
        try {
          await done.future;
        } finally {
          timer.cancel();
        }
        return true;
      } catch (e, s) {
        ctx.log('[${DiomanAuth.pluginName}] 刷新失败: $e\n$s');
        if (_tokens.accessToken != snapshot) return true;
        await _expire(ctx, o, r, session);
        return false;
      } finally {
        _refreshing = null;
      }
    })();
  }

  /// 失败载体统一由工厂创建。
  DiomanResponse<dynamic> _fail(DiomanContext<R> ctx, String reason) =>
      ctx.fail(DiomanFailure(kind: DiomanKind.auth, reason: reason));

  /// 加入刷新后立刻重查本调用的取消，不中止共享刷新。
  Future<DiomanResponse<dynamic>?> _join(
      DiomanContext<R> ctx, Future<bool> pending) async {
    final success = await ctx.wait(pending);
    final cancelled = ctx.cancelled();
    return cancelled ?? (success == true ? null : _fail(ctx, _expired));
  }

  /// 每次尝试入口求值保护规则，同一尝试内至多重放一次。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) async {
    final o = resolveOption<DiomanAuthOptions>(
        ctx.request.call.options[DiomanAuth.option],
        base: base,
        merge: _merge);
    if (o == null ||
        o.enabled == false ||
        (o.enabled != true && o.isProtected?.call(ctx.request) == false)) {
      return next();
    }
    ctx.markReplayable();
    final pending = _refreshing;
    if (pending != null) {
      final failure = await _join(ctx, pending);
      final cancelled = ctx.cancelled();
      if (cancelled != null) return cancelled;
      if (failure != null) return failure;
    }
    var replayed = false;
    var proactive = false;
    while (true) {
      // 重放前必须重查凭证，刷新成功也可能已被使用者登出。
      if (!_hasToken) {
        final r = _fail(ctx, 'unauthenticated');
        await ctx.wait(_notice(ctx, o.onAccessDenied ?? o.onAccessExpired!, r));
        return ctx.cancelled() ?? r;
      }
      // 登录（包括拿到同名凭证）之后允许新一轮过期通知。
      _expiredSession = null;
      final at = o.expiresAt?.call(_tokens.accessToken!);
      if (!proactive &&
          at != null &&
          !at.isAfter(ctx.clock.now().add(o.refreshLeeway!))) {
        proactive = true;
        final failure = await _join(
            ctx, _refresh(ctx, o, _fail(ctx, _expired), _tokens.accessToken));
        final cancelled = ctx.cancelled();
        if (cancelled != null) return cancelled;
        if (failure != null) return failure;
        continue;
      }
      RequestPatch? patch;
      String? token;
      for (var i = 0; i < DiomanAuth.readyStableAttempts; i++) {
        token = _tokens.accessToken;
        patch = o.ready == null
            ? RequestPatch(headers: {o.headerKey!: o.buildHeader!(token!)})
            : await ctx.wait(Future<RequestPatch>.sync(
                () => o.ready!(_tokens, ctx.request)));
        final cancelled = ctx.cancelled();
        if (cancelled != null) return cancelled;
        final current = _tokens.accessToken;
        if (current == token) break;
        if (!_hasToken) break;
      }
      if (!_hasToken) continue;
      ctx.set(DiomanAuth.injectedToken, token);
      final r = await next(patch);
      final cancelled = ctx.cancelled();
      if (r.kind == DiomanKind.internal) return r;
      if (cancelled != null) return cancelled;
      if (r.ok || r.kind == DiomanKind.cancel) return r;
      final action = o.onFailure == null
          ? defaultAuthFailure(
              r, _tokens, ctx.get<String?>(DiomanAuth.injectedToken))
          : await ctx.wait(Future<DiomanAuthFailureAction>.sync(
              () => o.onFailure!(r, _tokens)));
      final cancelledAfterFailure = ctx.cancelled();
      if (cancelledAfterFailure != null) return cancelledAfterFailure;
      switch (action!) {
        case DiomanAuthFailureAction.refresh:
        case DiomanAuthFailureAction.replay:
          if (!ctx.canReplay()) return r;
          if (replayed) {
            await ctx.wait(_expire(ctx, o, r, token));
            return ctx.cancelled() ?? _fail(ctx, _expired);
          }
          if (action == DiomanAuthFailureAction.refresh) {
            final failure = await _join(ctx, _refresh(ctx, o, r, token));
            final cancelled = ctx.cancelled();
            if (cancelled != null) return cancelled;
            if (failure != null) return failure;
          }
          replayed = true;
        case DiomanAuthFailureAction.expired:
          await ctx.wait(_expire(ctx, o, r, token));
          return ctx.cancelled() ?? _fail(ctx, _expired);
        case DiomanAuthFailureAction.deny:
          final denied = _fail(ctx, 'denied');
          await ctx.wait(
              _notice(ctx, o.onAccessDenied ?? o.onAccessExpired!, denied));
          return ctx.cancelled() ?? denied;
        case DiomanAuthFailureAction.others:
          return r;
      }
    }
  }
}
