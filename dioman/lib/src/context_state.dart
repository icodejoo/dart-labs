import 'package:dio/dio.dart';
import 'request.dart';

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
  DiomanContextState(this.token, {void Function()? onDispose})
      : _onDispose = onDispose {
    _link = DiomanCancelLink(token, (_) => _notify());
  }

  /// 最后一个传输释放时通知客户端摘除取消登记。
  final void Function()? _onDispose;

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

  /// 已发送的不可重放载荷，按身份记录，防止补丁视图绕过保护。
  final consumedBodies = Set<Object>.identity();

  /// 最近实际交给传输的请求视图，重放方不能只检查入口请求体。
  DiomanRequest? sentRequest;

  /// 脱离首发调用方但仍在执行的共享传输数。
  int _retained = 0;

  /// 逻辑调用方是否已完成。
  bool _released = false;

  /// 保持共享传输使用的状态；每次调用必须对应一次 release。
  void retain() => _retained++;

  /// 共享传输完成后释放；最后一个持有者负责最终清理。
  void release() {
    _retained--;
    if (_released && _retained == 0) dispose();
  }

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
    _released = true;
    if (_retained > 0) return;
    _link.dispose();
    for (final listener in listeners.keys.toList()) {
      listener();
    }
    listeners.clear();
    _onDispose?.call();
  }
}
