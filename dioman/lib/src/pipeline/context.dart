import 'dart:async';
import 'package:dio/dio.dart';
import 'client.dart';
import 'clock.dart';
import 'key.dart';
import 'request.dart';
import 'response.dart';

/// debug 日志回调；关闭 debug 时不会调用。
typedef DiomanLogger = void Function(String message);

/// 逻辑请求状态键；使用非 const 实例保证按身份隔离。
final class StateKey<T> {
  /// 创建键，例如 `final attempt = StateKey<int>('attempt')`。
  const StateKey(this.description);

  /// 调试说明。
  final String description;
}

/// 可解除目标的 Dio 取消桥；Dio Future 自身没有退订接口。
class DiomanCancelLink {
  /// 将 [source] 联动到 [target]，已取消时同步传递。
  DiomanCancelLink(CancelToken source, void Function(Object?) target)
      : _target = target {
    if (source.isCancelled) {
      target(source.cancelError);
    } else {
      source.whenCancel.then(_deliver);
    }
  }

  /// 可清除的订阅目标，清理后不再引用请求状态。
  void Function(Object?)? _target;

  /// 转发用户取消。
  void _deliver(Object? reason) => _target?.call(reason);

  /// 解除逻辑订阅；迟到的取消不再触及请求。
  void dispose() => _target = null;
}

/// 一个逻辑请求的共享状态和取消订阅登记。
class DiomanContextState {
  /// 创建状态并监听内核令牌；测试也可独立构造上下文。
  DiomanContextState(this.token) {
    _link = DiomanCancelLink(token, (_) => _notify());
  }

  /// 内核逻辑取消令牌。
  final CancelToken token;

  /// Dio 到内核订阅表的桥。
  late final DiomanCancelLink _link;

  /// 惰性分配的类型化值。
  Map<Object, Object?>? values;

  /// 按请求身份缓存 key。
  final keys = Map<DiomanRequest, String?>.identity();

  /// 等待取消的订阅表。
  final listeners = <void Function(), CancelToken>{};

  /// 是否需要克隆发送体。
  bool replayable = false;

  /// 通知副本，允许回调在执行中退订。
  void _notify() {
    for (final entry in listeners.entries.toList()) {
      if (identical(entry.value, token)) entry.key();
    }
  }

  /// 同步取消内核请求并通知等待者。
  void cancel([Object? reason]) {
    token.cancel(reason);
    _notify();
  }

  /// 释放桥并结束剩余等待。
  void dispose() {
    _link.dispose();
    for (final listener in listeners.keys.toList()) {
      listener();
    }
    listeners.clear();
  }
}

/// 每层的固定形状上下文；派生请求共享逻辑状态。
class DiomanContext<R extends DiomanResponse<dynamic>> {
  /// 注入内核服务；例如测试可直接构造而不发起请求。
  DiomanContext(
      {required this.id,
      required this.client,
      required this.request,
      required this.state,
      required this.factory,
      required this.keyService,
      required this.clock,
      required this.log});

  /// 请求序号。
  final int id;

  /// 所属客户端。
  final Dioman<R> client;

  /// 本层请求视图。
  final DiomanRequest request;

  /// 共享状态。
  final DiomanContextState state;

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

  /// 当前逻辑请求残留的等待订阅数。
  int get cancellationSubscriptions => state.listeners.length;

  /// 是否保护重放请求体。
  bool get replayable => state.replayable;

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

  /// 经工厂生成结果；坏扩展工厂回退基础 internal，以保证 next 不抛错。
  DiomanResponse<dynamic> fail(DiomanFailure failure) =>
      factory.fail(request, failure);

  /// 声明可能重放；后续每次发送均独立克隆请求体。
  void markReplayable() => state.replayable = true;

  /// 已取消则造 cancel 结果，否则返回 null；每次 await 后应调用。
  DiomanResponse<dynamic>? cancelled() =>
      isCancelled ? fail(const DiomanFailure(kind: DiomanKind.cancel)) : null;

  /// 派生请求视图，保留所有逻辑服务与共享状态。
  DiomanContext<R> derive(RequestPatch patch) => DiomanContext(
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
