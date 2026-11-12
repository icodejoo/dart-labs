import 'package:flutter/foundation.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';
import 'package:flutter_stompsocket_example/demo_settings.dart';

/// 记录公开 API 调用，底层缓冲与引用计数仍使用真实实现。
class RecordingSocket extends Stompsocket {
  /// 创建不会连接网络的客户端。
  RecordingSocket()
    : super(url: DemoSettings.brokerUrl, resumeOnForeground: false);

  /// 替代网络驱动的状态。
  final states = ValueNotifier(StompConnectionState.idle);

  /// 捕获的注册回调。
  final List<JsonCallback> callbacks = [];

  /// 实际交给 send 的载荷。
  final List<Object?> bodies = [];

  /// 启动次数。
  int activations = 0;

  /// 强制重连次数。
  int reconnects = 0;

  /// 停止次数。
  int stops = 0;

  /// 清理全部订阅的次数。
  int clears = 0;

  /// 测试设置的当前状态。
  @override
  StompConnectionState get state => states.value;

  /// 测试驱动的响应式状态。
  @override
  ValueListenable<StompConnectionState> get stateListenable => states;

  /// 记录启动并模拟成功连接。
  @override
  void activate() {
    activations++;
    states.value = StompConnectionState.connected;
  }

  /// 记录强制重连请求。
  @override
  void forceReconnect() => reconnects++;

  /// 捕获载荷并调用真实的离线缓冲实现。
  @override
  void send(String destination, {Object? body, Map<String, String>? headers}) {
    bodies.add(body);
    super.send(destination, body: body, headers: headers);
  }

  /// 捕获消息回调并保留真实引用计数句柄。
  @override
  StompSubscription subscribe(
    String destination,
    JsonCallback callback, {
    String? id,
    bool ordered = true,
    AckMode ack = AckMode.auto,
    ParseFailureAck onParseError = ParseFailureAck.nack,
  }) {
    callbacks.add(callback);
    return super.subscribe(
      destination,
      callback,
      id: id,
      ordered: ordered,
      ack: ack,
      onParseError: onParseError,
    );
  }

  /// 记录全部清理请求。
  @override
  void clear() {
    clears++;
    super.clear();
  }

  /// 停止真实底层资源并同步测试状态。
  @override
  void dispose({bool keepSubscriptions = false}) {
    stops++;
    super.dispose(keepSubscriptions: keepSubscriptions);
    states.value = StompConnectionState.disconnected;
  }
}

/// 分别记录手动 ACK 和 NACK，用于验证连续收件不覆盖句柄。
class RecordingAck implements AckControl {
  /// 已确认次数。
  int accepted = 0;

  /// 已拒绝次数。
  int rejected = 0;

  /// 记录确认。
  @override
  void ack() => accepted++;

  /// 记录拒绝。
  @override
  void nack() => rejected++;
}
