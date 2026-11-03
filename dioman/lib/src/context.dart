import 'dart:async';
import 'package:dio/dio.dart';
import 'client.dart';
import 'clock.dart';
import 'context_state.dart';
import 'key.dart';
import 'request.dart';
import 'response.dart';

part 'context_internal.dart';

/// debug 日志回调；关闭 debug 时不会调用。
typedef DiomanLogger = void Function(String message);

/// 生命周期收尾的取消结果覆盖；离线销毁须保留 disposed 原因。
final cancellationFailure =
    StateKey<DiomanResponse<dynamic>>('cancellation outcome');

/// 逻辑请求状态键；使用非 const 实例保证按身份隔离。
final class StateKey<T> {
  /// 创建键，例如 `final attempt = StateKey<int>('attempt')`。
  const StateKey(this.description);

  /// 调试说明。
  final String description;
}

/// 当前结果对应的只读原生视图；仅在逻辑请求落定前可读取。
/// 例如 `ctx.native?.raw?.headers`；缓存与共享跟随者返回 null。
class DiomanNative {
  /// 内核绑定结果及其原生数据。
  const DiomanNative._(this.response, this.raw, this.error);

  /// 与本视图关联的归一化结果。
  final DiomanResponse<dynamic> response;

  /// 本次传输的 Dio 响应，未收到响应时为空。
  final Response<dynamic>? raw;

  /// 本次传输的原始异常，成功时为空。
  final Object? error;
}

/// 每层的固定形状上下文；派生请求共享逻辑状态。
class DiomanContext<R extends DiomanResponse<dynamic>> {
  /// 注入内核服务；例如测试可直接构造而不发起请求。
  DiomanContext(
      {required this.id,
      required this.client,
      required this.request,
      required this.factory,
      required this.keyService,
      required this.clock,
      required this.log})
      : _state = DiomanContextState(CancelToken());

  /// 内核注入共享状态，公开构造器不接受内部类型。
  DiomanContext._internal(
      {required this.id,
      required this.client,
      required this.request,
      required DiomanContextState state,
      required this.factory,
      required this.keyService,
      required this.clock,
      required this.log})
      : _state = state;

  /// 请求序号。
  final int id;

  /// 所属客户端。
  final Dioman<R> client;

  /// 本层请求视图。
  final DiomanRequest request;

  /// 共享状态。
  final DiomanContextState _state;

  /// 读取当前结果对应的自身原生数据，未匹配或已落定时返回 null。
  /// 例如在 `await next()` 后读取 `ctx.native?.raw`。
  DiomanNative? get native {
    final slot = _state.nativeSlot;
    final result = _state.nativeResult;
    if (slot == null || result == null || !identical(slot.response, result)) {
      return null;
    }
    return DiomanNative._(result, slot.raw, slot.error);
  }

  /// 结果服务。
  final DiomanResponseFactory<R> factory;

  /// 构键服务。
  final DiomanKeyService keyService;

  /// 注入时钟。
  final DiomanClock clock;

  /// 受 debug 开关控制的日志器。
  final DiomanLogger log;

  /// 当前传输的取消令牌，补丁可以覆盖。
  CancelToken get cancelToken => request.cancelToken ?? state.token;

  /// 逻辑请求或当前传输是否取消。
  bool get isCancelled => cancelToken.isCancelled;

  /// 惰性构键并按请求身份缓存；false 选项返回 null。
  String? key() {
    if (!state.keys.containsKey(request)) {
      state.keys[request] =
          keyService.build(request.toRequestOptions(), request.call.key);
    }
    return state.keys[request];
  }

  /// 读取 [key] 的类型化值，未设置返回 null。
  T? get<T>(StateKey<T> key) => state.values?[key] as T?;

  /// 写入 [key] 的类型化 [value]，各层共享。
  void set<T>(StateKey<T> key, T value) => (state.values ??= {})[key] = value;

  /// 以 [kind] 和可选 [reason] 生成失败，返回经工厂扩展的响应。
  /// 例如 `ctx.fail(DiomanFailureKind.offline, reason: 'timeout')`。
  DiomanResponse<dynamic> fail(DiomanFailureKind kind, {String? reason}) =>
      factory.fail(request, kind, reason: reason);

  /// 读取客户端有效状态；省略映射时返回 HTTP status。
  /// 例如 `ctx.statusOf(result)`；映射抛错按程序错误处理。
  int statusOf(DiomanResponse<dynamic> result) =>
      client.statusOf?.call(result) ?? result.status;

  /// 声明可能重放；后续每次发送均独立克隆请求体。
  void markReplayable() => state.replayable = true;

  /// 本请求体能否安全重放；不透明对象与流保留身份，不能再次发送。
  bool canReplay() {
    final safe = _canReplay((state.sentRequest ?? request).data);
    if (!safe) log('请求体不能重放，保留本次结果');
    return safe;
  }

  /// JSON 容器递归判定；FormData 由 Dio 克隆。
  static bool _canReplay(Object? value) {
    if (value == null ||
        value is num ||
        value is bool ||
        value is String ||
        value is FormData) {
      return true;
    }
    if (value is Map) return value.values.every(_canReplay);
    if (value is List) return value.every(_canReplay);
    return false;
  }

  /// 已取消返回失败，自身截止到期为 timeout/deadline，否则为 cancel。
  /// 单次令牌与 cancelAll 的首次原因转为字符串；省略时为 null。
  DiomanResponse<dynamic>? cancelled() => isCancelled
      ? (identical(cancelToken, state.token) && state.deadlineExpired
              ? fail(DiomanFailureKind.timeout, reason: 'deadline')
              : get(cancellationFailure)) ??
          fail(DiomanFailureKind.cancel,
              reason: cancelToken.cancelError?.error?.toString())
      : null;

  /// 派生请求视图，保留所有逻辑服务与共享状态。
  DiomanContext<R> derive(RequestPatch patch) => DiomanContext._internal(
      id: id,
      client: client,
      request: request.patch(patch),
      state: state,
      factory: factory,
      keyService: keyService,
      clock: clock,
      log: log);

  /// 等待 [pending]、取消或 [timeout]；后两者返回 null，结束后无订阅及计时器。
  /// 已取消立即返回；迟到的值或异常被消费且不会改变结局。
  Future<T?> wait<T>(Future<T> pending, {Duration? timeout}) {
    final result = Completer<T?>();
    Timer? timer;
    DiomanCancelLink? localLink;
    late void Function() cancel;
    void clean() {
      timer?.cancel();
      localLink?.dispose();
      state.listeners.remove(cancel);
    }

    void finish(T? value) {
      if (result.isCompleted) return;
      clean();
      result.complete(value);
    }

    cancel = () => finish(null);
    // 即使已经取消，也消费输入的迟到异常。
    pending.then((value) => finish(value),
        onError: (Object error, StackTrace stack) {
      if (result.isCompleted) return;
      clean();
      result.completeError(error, stack);
    });
    if (isCancelled) {
      finish(null);
      return result.future;
    }
    state.listeners[cancel] = cancelToken;
    if (!identical(cancelToken, state.token)) {
      localLink = DiomanCancelLink(cancelToken, (_) => cancel());
    }
    if (timeout != null) timer = clock.createTimer(timeout, cancel);
    return result.future;
  }
}
