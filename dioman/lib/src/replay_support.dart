// 内部文件：不从 lib/dioman.dart 导出，供 share/auth/retry 的重放共用。
import 'dart:async';
import 'package:dio/dio.dart';
import 'request_claims.dart';

/// dio 的 InterceptorState 类型名（该枚举未导出，只能按名字识别）。
const _kStateResolve = 'resolve';
const _kStateRejectCallFollowing = 'rejectCallFollowing';

/// 下游拦截器在恢复结果上 reject 的结果。
///
/// [callFollowing] 对应 dio 的两种 reject：为 false 是 `handler.reject(e)`，
/// 终止，后续错误拦截器不再执行；为 true 是 `handler.reject(e, true)` 或抛异常，
/// 后续错误拦截器继续执行。
class DownstreamReject implements Exception {
  DownstreamReject(this.error, {required this.callFollowing});

  /// 下游给出的错误。
  final DioException error;

  /// 是否让后续错误拦截器继续处理。
  final bool callFollowing;
}

/// 重放/重试用的传输层持有者：优先借用宿主 [Dio] 的 adapter 与 transformer，
/// 这样自定义代理、证书、序列化行为在重放时保持一致；未绑定宿主时退回一个
/// 无拦截器的裸 Dio（与旧行为一致）。
///
/// 重放走不带拦截器的 Dio，不会重新进入原链路；恢复成功后的结果通过
/// [runDownstream] 手动交给宿主链上排在重放者之后的拦截器处理。
class ReplayClient {
  Dio? _host;
  Dio? _fallback;

  /// 绑定宿主 [Dio]；传 null 解绑。
  void bind(Dio? host) => _host = host;

  /// 当前绑定的宿主，未绑定为 null。
  Dio? get host => _host;

  /// 发起一次重放：借宿主传输层的无拦截器 Dio，未绑定时用兜底裸 Dio。
  Future<Response<dynamic>> fetch(RequestOptions opts) {
    final host = _host;
    if (host == null) return (_fallback ??= Dio()).fetch<dynamic>(opts);
    // 每次新建而不关闭：adapter/transformer 属于宿主，关闭会连带关掉宿主连接。
    final dio = Dio()
      ..httpClientAdapter = host.httpClientAdapter
      ..transformer = host.transformer;
    return dio.fetch<dynamic>(opts);
  }

  /// 把恢复成功的 [response] 依次交给宿主链上排在 [self] 之后的拦截器的
  /// onResponse（normalize、breaker、log 等），使恢复结果与首次成功语义一致。
  ///
  /// 某个拦截器 reject 时抛出 [DownstreamReject]，保留终止/继续两种语义；
  /// 未绑定宿主或找不到 [self] 时原样返回 [response]。
  Future<Response<dynamic>> runDownstream(
    Interceptor self,
    Response<dynamic> response,
  ) async {
    final host = _host;
    if (host == null) return response;
    final all = host.interceptors.toList();
    final index = all.indexOf(self);
    if (index < 0) return response;

    var current = response;
    for (final stage in all.sublist(index + 1)) {
      final handler = ResponseInterceptorHandler();
      try {
        // dynamic 调用：拿回 async 实现返回的 Future，捕获其异步异常。
        final Object? result =
            (stage as dynamic).onResponse(current, handler) as Object?;
        if (result is Future) {
          unawaited(result.then<void>((_) {}, onError: (Object e, StackTrace s) {
            if (!handler.isCompleted) {
              handler.reject(_asDio(e, current.requestOptions, s), true);
            }
          }));
        }
      } catch (e, s) {
        throw DownstreamReject(_asDio(e, current.requestOptions, s),
            callFollowing: true);
      }
      final dynamic state;
      try {
        // future 是 dio 标注的 protected 成员，dynamic 访问绕过静态检查。
        state = await (handler as dynamic).future;
      } catch (e) {
        // reject 时 future 以 InterceptorState 报错：data 是 DioException，
        // type 区分终止（reject）与继续（rejectCallFollowing）。
        final dynamic data = (e is DioException) ? e : (e as dynamic).data;
        final callFollowing = e is DioException ||
            _stateName(e) == _kStateRejectCallFollowing;
        throw DownstreamReject(
          data is DioException
              ? data
              : _asDio(data ?? e, current.requestOptions, StackTrace.current),
          callFollowing: callFollowing,
        );
      }
      current = (state as dynamic).data as Response<dynamic>;
      // 普通 resolve：终结，后面的拦截器不再处理（与 Dio 原语义一致）。
      if (_stateName(state) == _kStateResolve) break;
    }
    return current;
  }

  /// 错误阶段恢复成功后的收尾：把 [response] 交给排在 [self] 之后的拦截器处理
  /// （语义跟首次成功一致），再终结链路。下游 `reject(e)` 终止链路，
  /// `reject(e, true)` 把错误交给后续错误拦截器。
  ///
  /// 共享结算（share）用下游处理之前的快照：先注销 [self] 的认领，此后若没有
  /// 认领者就立刻结算；下游还有认领者（如 retry）则由它们交出结果时结算。这样各
  /// 调用者只各自处理一次，不会把别人处理过的结果再处理一遍。
  /// 若此刻该请求已在 share 仲裁中出局（end 被取代、race 已有胜者），丢弃自己的
  /// 恢复结果，改为交付胜出结果。
  Future<void> finishRecovered(
    Interceptor self,
    RequestOptions opts,
    Response<dynamic> response,
    ErrorInterceptorHandler handler,
  ) async {
    final claims = claimsOf(opts);
    var resp = response;
    final lost = claims?.checkLoser?.call();
    if (lost != null) {
      try {
        resp = await lost;
      } catch (e) {
        final err = _asDio(e, opts, StackTrace.current);
        claims?.finish(error: err);
        return handler.next(err);
      }
    }
    claims?.settle(self, response: resp);

    final Response<dynamic> finalResp;
    try {
      finalResp = await runDownstream(self, resp);
    } on DownstreamReject catch (r) {
      if (r.callFollowing) {
        claims?.settle(self, error: r.error);
        return handler.next(r.error);
      }
      // 终止型 reject：后面的错误阶段不会再跑，直接以该错误结束认领。
      claims?.finish(error: r.error);
      return handler.reject(r.error);
    }
    claims?.finish(response: finalResp);
    handler.resolve(finalResp);
  }

  /// 响应阶段交出 [owner] 的结果：注销认领后 `handler.next`。若该请求在 share
  /// 仲裁中落败，改为交付胜出结果（失败则 `reject(e, true)`）。
  static void handOffResponse(
    RequestOptions opts,
    Object owner,
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final wait = releaseClaimArbitrated(opts, owner, response: response);
    if (wait == null) return handler.next(response);
    wait.then<void>(
      handler.next,
      onError: (Object e, StackTrace s) =>
          handler.reject(_asDio(e, opts, s), true),
    );
  }

  /// 错误阶段交出 [self] 的最终失败：注销认领后 `handler.next(err)`。若该请求在
  /// share 仲裁中落败（race 还有在途请求、end 已被取代），改为等胜出结果，成功则
  /// 走 [finishRecovered]，失败则把胜出方的错误往后传；取消类错误例外，直接交出。
  void handOffError(
    Interceptor self,
    RequestOptions opts,
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    final wait = releaseClaimArbitrated(opts, self, error: err);
    if (wait == null) return handler.next(err);
    if (err.type == DioExceptionType.cancel) {
      // 取消类错误不等胜出结果，直接交出；丢弃的等待不能留未处理异常。
      wait.ignore();
      return handler.next(err);
    }
    wait.then<void>(
      (winner) => finishRecovered(self, opts, winner, handler),
      onError: (Object e, StackTrace s) => handler.next(_asDio(e, opts, s)),
    );
  }

  /// 释放兜底裸 Dio；借用的宿主传输层不归我们管，不关闭。
  void dispose() {
    _host = null;
    _fallback?.close(force: true);
    _fallback = null;
  }
}

/// 取 InterceptorState 的类型名（enum 的 name 是扩展，dynamic 调用不可用）。
String _stateName(Object state) =>
    (state as dynamic).type.toString().split('.').last;

DioException _asDio(Object e, RequestOptions opts, StackTrace s) =>
    e is DioException
        ? e
        : DioException(requestOptions: opts, error: e, stackTrace: s);

/// 重放前整理请求体。返回 false 表示 body 无法重放，调用方不应自动重放：
/// - Stream 只能消费一次；
/// - 已消费的 FormData 需克隆，克隆不了（文件流已消费）同样不可重放。
bool prepareForReplay(RequestOptions opts) {
  final data = opts.data;
  if (data is Stream) return false;
  if (data is FormData && data.isFinalized) {
    try {
      opts.data = data.clone();
    } on StateError {
      return false;
    }
  }
  return true;
}

/// 等 [work]，但 [token] 取消时立刻以 [onCancel] 的返回值结束；[work] 继续在
/// 后台跑，之后的结果或异常被丢弃。[token] 为 null 时等价于直接等 [work]。
///
/// 用于单个请求的长等待（刷新、重放）：取消时能立刻交出 handler、注销认领，
/// 而不必等共享的刷新结束。
Future<T> raceCancel<T>(
  Future<T> work,
  CancelToken? token,
  T Function(DioException cancelError) onCancel,
) {
  if (token == null) return work;
  final done = Completer<T>();
  work.then<void>(
    (v) {
      if (!done.isCompleted) done.complete(v);
    },
    onError: (Object e, StackTrace s) {
      if (!done.isCompleted) done.completeError(e, s);
    },
  );
  token.whenCancel.then<void>((e) {
    if (!done.isCompleted) done.complete(onCancel(e));
  });
  return done.future;
}

/// 可取消的等待：用 [Timer] 计时，[token] 取消时立刻结束并取消计时器。
/// 取消监听无法从 Future 上摘除，故用标志位让回调在结束后失效。
Future<void> cancellableDelay(Duration wait, CancelToken? token) {
  if (wait <= Duration.zero || token?.isCancelled == true) {
    return Future<void>.value();
  }
  final done = Completer<void>();
  final timer = Timer(wait, () {
    if (!done.isCompleted) done.complete();
  });
  token?.whenCancel.then((_) {
    if (done.isCompleted) return;
    timer.cancel();
    done.complete();
  });
  return done.future;
}
