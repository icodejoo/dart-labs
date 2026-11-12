import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

import 'demo_kit/demo_kit.dart';
import 'demo_settings.dart';

/// 单条双语日志，技术数据单独保存以便切换语言后重新呈现。
class DemoEvent {
  /// 保存双语说明及可选原始数据。
  const DemoEvent(this.en, this.zh, [this.data = '']);

  /// 英文说明。
  final String en;

  /// 中文说明。
  final String zh;

  /// 不翻译的目的地或原始消息内容。
  final String data;
}

/// 接收消息后的确认状态。
enum DeliveryStatus {
  /// 等待接收。
  waiting,

  /// 已由服务端或 smart 模式确认。
  delivered,

  /// 等待业务确认。
  pending,

  /// 业务已确认。
  acked,

  /// 业务已拒绝。
  nacked,
}

/// 一次回调注册及其最新消息；确认模式在注册时固定。
class DemoSubscription {
  /// 保存注册参数。
  DemoSubscription(this.destination, this.mode);

  /// 消息目的地。
  final String destination;

  /// 注册时的确认模式。
  final AckMode mode;

  /// 真实连接返回的引用计数句柄。
  StompSubscription? handle;

  /// 尚未确认的消息句柄，避免连续收件时覆盖旧句柄。
  final List<AckControl> pending = [];

  /// 离线预览中尚未确认的消息数。
  int previewPending = 0;

  /// 已收到的消息数。
  int received = 0;

  /// 最新消息的可读内容。
  String payload = '';

  /// 最新确认状态。
  DeliveryStatus status = DeliveryStatus.waiting;
}

/// 管理跨页演示会话；离线预览不创建网络连接。
class DemoSession extends ChangeNotifier {
  /// 创建可在测试中注入客户端工厂的会话。
  DemoSession({this.socketFactory});

  /// 测试替身工厂；正常运行始终使用当前公开构造器。
  final Stompsocket Function(String url, Map<String, String> headers)?
  socketFactory;

  /// 当前是否使用真实 broker。
  bool realMode = false;

  /// 当前连接状态。
  StompConnectionState connection = StompConnectionState.idle;

  /// 当前客户端，停止后仍保留以便离线发送与恢复。
  Stompsocket? socket;

  /// 受界面上限约束的回调注册列表。
  final List<DemoSubscription> subscriptions = [];

  /// 最近的双语事件。
  final List<DemoEvent> events = [];

  /// 离线预览的待发数量；真实缓冲没有公开计数 API。
  int previewQueued = 0;

  /// 当前演示发起的发送次数，不代表 broker 已确认收件。
  int sendAttempts = 0;

  /// 可取消的预览连接定时器。
  Timer? _timer;

  /// 当前真实客户端的状态监听器。
  VoidCallback? _stateListener;

  /// 以当前语言呈现连接状态。
  String stateLabel(BuildContext context) => switch (connection) {
    StompConnectionState.idle => tr(context, 'Idle', '未启动'),
    StompConnectionState.connecting => tr(context, 'Connecting', '连接中'),
    StompConnectionState.connected => tr(context, 'Connected', '已连接'),
    StompConnectionState.reconnecting => tr(context, 'Reconnecting', '重连中'),
    StompConnectionState.disconnected => tr(context, 'Disconnected', '已停止'),
  };

  /// 记录事件并限制日志长度。
  void record(String en, String zh, [String data = '']) {
    events.insert(0, DemoEvent(en, zh, data));
    if (events.length > DemoSettings.logLimit) events.removeLast();
    notifyListeners();
  }

  /// 切换模式前销毁整个旧会话，避免混用真实与预览句柄。
  void changeMode(bool real) {
    if (real == realMode) return;
    reset();
    realMode = real;
    notifyListeners();
  }

  /// 释放网络与计时资源，并移除旧监听器。
  void _close() {
    _timer?.cancel();
    _timer = null;
    final previous = socket;
    socket = null;
    if (previous != null) {
      if (_stateListener != null) {
        previous.stateListenable.removeListener(_stateListener!);
      }
      previous.dispose();
    }
    _stateListener = null;
  }

  /// 重放连接或发送示例：建立全新会话并丢弃旧缓冲。
  void reset() {
    _close();
    subscriptions.clear();
    events.clear();
    previewQueued = 0;
    sendAttempts = 0;
    connection = StompConnectionState.idle;
    notifyListeners();
  }

  /// 启动离线预览或用户指定的真实 broker；停止后的客户端可直接恢复。
  void connect(String url, {String login = '', String passcode = ''}) {
    if (!realMode) {
      _previewTransition(
        StompConnectionState.connecting,
        DemoSettings.previewDelay,
      );
      return;
    }
    if (socket != null) {
      socket!.activate();
      return;
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !const ['ws', 'wss'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      record('Enter a valid ws:// or wss:// URL.', '请输入有效的 ws:// 或 wss:// 地址。');
      return;
    }
    final headers = <String, String>{
      if (login.isNotEmpty) 'login': login,
      if (passcode.isNotEmpty) 'passcode': passcode,
    };
    late final Stompsocket next;
    next =
        socketFactory?.call(url.trim(), headers) ??
        Stompsocket(
          url: url.trim(),
          connectHeaders: headers,
          connectionTimeout: DemoSettings.connectionTimeout,
          onConnected: (_) {
            if (identical(socket, next)) {
              record(
                'Connected; subscriptions restored and outbox flushed.',
                '连接成功；已恢复订阅并补发缓冲。',
              );
            }
          },
          onStompError: (_) {
            if (identical(socket, next)) {
              record('Broker returned STOMP ERROR.', 'Broker 返回 STOMP ERROR。');
            }
          },
          onWebSocketError: (_) {
            if (identical(socket, next)) {
              record(
                'WebSocket error; check endpoint and broker access.',
                'WebSocket 错误，请检查地址与 broker 访问配置。',
              );
            }
          },
          onParseFailure: (_, _) {
            if (identical(socket, next)) {
              record('Binary decoding failed.', '二进制解码失败。');
            }
          },
        );
    socket = next;
    _stateListener = () {
      if (!identical(socket, next)) return;
      connection = next.state;
      notifyListeners();
    };
    next.stateListenable.addListener(_stateListener!);
    next.activate();
  }

  /// 播放预览状态变化，完成后模拟补发待发消息。
  void _previewTransition(StompConnectionState state, Duration delay) {
    _timer?.cancel();
    connection = state;
    record('Preview: connection attempt.', '预览：开始连接。');
    _timer = Timer(delay, () {
      connection = StompConnectionState.connected;
      final flushed = previewQueued;
      previewQueued = 0;
      record(
        'Preview: connected; buffered messages flushed.',
        '预览：已连接，已补发缓冲消息。',
        '$flushed',
      );
    });
  }

  /// 可逆停止，保留订阅；再次连接将调用 activate。
  void stop() {
    _timer?.cancel();
    if (realMode) socket?.dispose(keepSubscriptions: true);
    connection = StompConnectionState.disconnected;
    record('Stopped; subscriptions and outbox retained.', '已停止；保留订阅与缓冲。');
  }

  /// 演示丢线后的重连；真实连接只在未连接且仍期望连接时生效。
  void reconnect() {
    if (realMode) {
      socket?.forceReconnect();
      record(
        'forceReconnect requested; only acts while awaiting connection.',
        '已请求 forceReconnect；仅在等待连接时生效。',
      );
    } else if (connection == StompConnectionState.connected) {
      _previewTransition(
        StompConnectionState.reconnecting,
        DemoSettings.previewReconnectDelay,
      );
    }
  }

  /// 登记一次回调，真实模式使用库的引用计数订阅。
  void subscribe(String destination, AckMode mode) {
    final target = _validatedTarget(destination);
    if (target == null) return;
    if (subscriptions.length >= DemoSettings.subscriptionLimit) {
      record(
        'Demo limit reached; remove a callback first.',
        '已达演示上限，请先取消一个回调。',
      );
      return;
    }
    final entry = DemoSubscription(target, mode);
    final owner = socket;
    entry.handle = owner?.subscribe(target, (payload, ack) {
      if (!identical(socket, owner) || !subscriptions.contains(entry)) return;
      entry.received++;
      entry.payload = '$payload';
      if (mode == AckMode.manual) entry.pending.add(ack);
      entry.status = mode == AckMode.manual
          ? DeliveryStatus.pending
          : DeliveryStatus.delivered;
      record('Received message.', '收到消息。', entry.payload);
    }, ack: mode);
    subscriptions.add(entry);
    record('Callback registered.', '已登记回调。', target);
  }

  /// 为离线预览分发一条消息，不伪装成真实服务器返回。
  void deliverPreview() {
    if (realMode) return;
    for (final entry in subscriptions) {
      entry.received++;
      entry.payload = DemoSettings.jsonBody;
      if (entry.mode == AckMode.manual) entry.previewPending++;
      entry.status = entry.mode == AckMode.manual
          ? DeliveryStatus.pending
          : DeliveryStatus.delivered;
    }
    record(
      'Preview message delivered to registered callbacks.',
      '预览消息已分发给登记的回调。',
    );
  }

  /// 在回调外按接收顺序确认或拒绝一条待处理消息。
  void acknowledge(DemoSubscription entry, {required bool accept}) {
    if (!subscriptions.contains(entry) ||
        entry.status != DeliveryStatus.pending) {
      return;
    }
    final ack = entry.pending.isEmpty ? null : entry.pending.removeAt(0);
    if (accept) {
      ack?.ack();
    } else {
      ack?.nack();
    }
    if (entry.previewPending > 0) entry.previewPending--;
    entry.status = entry.pending.isNotEmpty || entry.previewPending > 0
        ? DeliveryStatus.pending
        : (accept ? DeliveryStatus.acked : DeliveryStatus.nacked);
    record(
      accept ? 'Manual ACK requested.' : 'Manual NACK requested.',
      accept ? '已请求手动 ACK。' : '已请求手动 NACK。',
    );
  }

  /// 精确取消一次回调，不误删共享 wire 订阅中的其他回调。
  void unsubscribe(DemoSubscription entry) {
    entry.handle?.unsubscribe();
    subscriptions.remove(entry);
    record('Callback removed.', '已取消回调。', entry.destination);
  }

  /// 重放订阅示例时同时清理本地列表和库内的全部登记。
  void clearSubscriptions() {
    socket?.clear();
    subscriptions.clear();
    record('All subscriptions cleared.', '已清空全部订阅。');
  }

  /// 统一校验目的地与真实连接是否已创建。
  String? _validatedTarget(String destination) {
    final target = destination.trim();
    if (target.isEmpty) {
      record('Destination is required.', '请填写目的地。');
      return null;
    }
    if (realMode && socket == null) {
      record('Create a real connection first.', '请先创建真实连接。');
      return null;
    }
    return target;
  }

  /// 始终调用真实客户端的 send，包括断开期间，由库决定缓冲与丢弃。
  void send(String destination, Object? body) {
    final target = _validatedTarget(destination);
    if (target == null) return;
    if (realMode) {
      socket!.send(target, body: body);
    } else if (connection != StompConnectionState.connected) {
      if (previewQueued < DemoSettings.queueLimit) previewQueued++;
    }
    sendAttempts++;
    record(
      'Send requested; delivery is not broker-confirmed.',
      '已请求发送；不代表 broker 已确认收件。',
      target,
    );
  }

  /// 清空演示日志。
  void clearLog() {
    events.clear();
    notifyListeners();
  }

  /// 应用销毁时停止计时、取消订阅并断开连接。
  @override
  void dispose() {
    _close();
    subscriptions.clear();
    super.dispose();
  }
}

/// 向各页提供同一个可观察会话。
class DemoSessionScope extends InheritedNotifier<DemoSession> {
  /// 创建会话作用域，生命周期由宿主负责。
  const DemoSessionScope({
    super.key,
    required DemoSession session,
    required super.child,
  }) : super(notifier: session);

  /// 读取会话并在变化时重建当前页面。
  static DemoSession of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoSessionScope>()!.notifier!;
}
