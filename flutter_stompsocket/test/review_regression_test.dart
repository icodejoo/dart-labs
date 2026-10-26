import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

import 'stomp_test_broker.dart';

/// 慢速顶层解码器，让生命周期操作稳定落在后台解析期间。
int _slowDecode(Uint8List bytes) {
  sleep(const Duration(milliseconds: 300));
  return bytes.length;
}

/// 等待真实网络事件，失败时给出明确超时。
Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('等待条件超时');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// 验证审查发现的边界和生命周期竞态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StompTestBroker broker;
  late Stompsocket client;

  /// 创建测试客户端并登记自动清理。
  Stompsocket create({
    int maxQueuedMessages = 100,
    bool queueWhileDisconnected = true,
    Duration reconnectDelay = const Duration(milliseconds: 80),
    Future<Map<String, String>?> Function()? beforeConnect,
    void Function(StompConnectionState)? onStateChanged,
    void Function()? onConnected,
    void Function()? onParseFailure,
    bool slowDecoder = false,
    void Function(String)? onDebugMessage,
  }) {
    final result = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      resumeOnForeground: false,
      maxQueuedMessages: maxQueuedMessages,
      queueWhileDisconnected: queueWhileDisconnected,
      reconnectDelay: reconnectDelay,
      beforeConnect: beforeConnect,
      onStateChanged: onStateChanged,
      onConnected: (_) => onConnected?.call(),
      onParseFailure: (_, _) => onParseFailure?.call(),
      binaryDecoder: slowDecoder ? _slowDecode : null,
      onDebugMessage: onDebugMessage,
    );
    addTearDown(result.dispose);
    return result;
  }

  setUp(() async {
    broker = StompTestBroker();
    await broker.start();
    client = create();
  });

  tearDown(() async {
    client.dispose();
    await broker.stop();
  });

  for (final mode in AckMode.values) {
    test('JSON null 仍投递给 $mode 回调，manual 可拒绝且幂等', () async {
      final values = <dynamic>[];
      client.subscribe('/null', (value, ack) {
        values.add(value);
        ack.nack();
        ack.ack();
      }, ack: mode);
      client.activate();
      await _waitFor(() => broker.subscriptionCount == 1);
      broker.sendMessage('/null', 'null', withAck: true);
      await _waitFor(() => values.isNotEmpty);
      expect(values, [null]);
      if (mode == AckMode.auto) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(broker.framesOf('ACK'), isEmpty);
        expect(broker.framesOf('NACK'), isEmpty);
      } else {
        final command = mode == AckMode.manual ? 'NACK' : 'ACK';
        await _waitFor(() => broker.framesOf(command).isNotEmpty);
        expect(broker.framesOf(command), hasLength(1));
        expect(broker.framesOf(command == 'ACK' ? 'NACK' : 'ACK'), isEmpty);
      }
    });
  }

  test('重复 activate 不改变 connected 状态或重复连接', () async {
    final states = <StompConnectionState>[];
    client.stateListenable.addListener(() => states.add(client.state));
    client.activate();
    client.activate();
    await _waitFor(() => client.connected);
    client.activate();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(client.state, StompConnectionState.connected);
    expect(states, [
      StompConnectionState.connecting,
      StompConnectionState.connected,
    ]);
    expect(broker.framesOf('CONNECT'), hasLength(1));
  });

  for (final capacity in [0, -1, 2]) {
    test('缓冲上限 $capacity 不越界，满时保留最新消息', () async {
      client = create(maxQueuedMessages: capacity);
      for (var i = 0; i < 4; i++) {
        client.send('/send', body: '$i');
      }
      client.activate();
      await _waitFor(() => client.connected);
      if (capacity > 0) {
        await _waitFor(() => broker.framesOf('SEND').length == capacity);
        expect(broker.framesOf('SEND').map((frame) => frame.body), ['2', '3']);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(broker.framesOf('SEND'), isEmpty);
      }
    });
  }

  test('禁用离线缓冲时丢弃消息', () async {
    client = create(queueWhileDisconnected: false);
    client.send('/send', body: 'dropped');
    client.activate();
    await _waitFor(() => client.connected);
    client.send('/send', body: 'online');
    await _waitFor(() => broker.framesOf('SEND').isNotEmpty);
    expect(broker.framesOf('SEND').single.body, 'online');
  });

  for (final mode in [AckMode.smart, AckMode.manual]) {
    for (final policy in ParseFailureAck.values) {
      test('解析失败监控抛异常不阻断 $mode/$policy 确认策略', () async {
        client = create(onParseFailure: () => throw StateError('监控故障'));
        var calls = 0;
        client.subscribe(
          '/bad',
          (_, _) => calls++,
          ack: mode,
          onParseError: policy,
        );
        client.activate();
        await _waitFor(() => broker.subscriptionCount == 1);
        broker.sendMessage(
          '/bad',
          'binary',
          contentType: 'application/octet-stream',
          withAck: true,
        );
        final command = policy == ParseFailureAck.ack ? 'ACK' : 'NACK';
        await _waitFor(() => broker.framesOf(command).isNotEmpty);
        expect(calls, 0);
      });
    }
  }

  test('connecting 监听者同步 dispose 后不启动传输或报告旧状态', () async {
    final states = <StompConnectionState>[];
    client = create(onStateChanged: states.add);
    client.stateListenable.addListener(() {
      if (client.state == StompConnectionState.connecting) client.dispose();
    });
    client.activate();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(client.state, StompConnectionState.disconnected);
    expect(states, [StompConnectionState.disconnected]);
    expect(broker.framesOf('CONNECT'), isEmpty);
  });

  test('connected 监听者 dispose 后不再调用 onConnected', () async {
    var calls = 0;
    client = create(onConnected: () => calls++);
    client.stateListenable.addListener(() {
      if (client.state == StompConnectionState.connected) client.dispose();
    });
    client.activate();
    await _waitFor(() => client.state == StompConnectionState.disconnected);
    expect(calls, 0);
  });

  test('beforeConnect 尚未完成时 dispose/activate 只建立新连接', () async {
    final first = Completer<Map<String, String>?>();
    var calls = 0;
    client = create(
      beforeConnect: () {
        calls++;
        return calls == 1 ? first.future : Future.value({'token': 'fresh'});
      },
    );
    client.activate();
    await _waitFor(() => calls == 1);
    client.dispose();
    client.activate();
    first.complete({'token': 'stale'});
    await _waitFor(() => client.connected);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(calls, 2);
    expect(broker.framesOf('CONNECT'), hasLength(1));
    expect(broker.framesOf('CONNECT').single.headers['token'], 'fresh');
  });

  for (final ordered in [true, false]) {
    test('解析期间停止保留订阅：不投递旧消息或发送确认 ordered=$ordered', () async {
      var incoming = false;
      client = create(
        slowDecoder: true,
        onDebugMessage: (message) {
          if (message.startsWith('<<<') && message.contains('MESSAGE')) {
            incoming = true;
          }
        },
      );
      final values = <dynamic>[];
      client.subscribe(
        '/slow',
        (value, _) => values.add(value),
        ordered: ordered,
        ack: AckMode.smart,
      );
      client.activate();
      await _waitFor(() => broker.subscriptionCount == 1);
      broker.sendMessage(
        '/slow',
        'x' * (40 * 1024),
        contentType: 'application/octet-stream',
        withAck: true,
      );
      await _waitFor(() => incoming);
      client.dispose(keepSubscriptions: true);
      client.activate();
      await _waitFor(() => client.connected);
      broker.sendMessage('/slow', '42', withAck: true);
      await _waitFor(() => values.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(values, [42]);
      expect(broker.framesOf('ACK'), hasLength(1));
      expect(broker.framesOf('NACK'), isEmpty);
      expect(client.state, StompConnectionState.connected);
    });
  }

  test('旧订阅句柄不能取消同 id 的新订阅', () async {
    final old = client.subscribe('/old', (_, _) {}, id: 'same');
    client.unsubscribe(id: 'same');
    final values = <dynamic>[];
    client.subscribe('/new', (value, _) => values.add(value), id: 'same');
    old.unsubscribe();
    client.activate();
    await _waitFor(() => broker.subscriptionCount == 1);
    broker.sendMessage('/new', 'true');
    await _waitFor(() => values.isNotEmpty);
    expect(values, [true]);
  });

  test('旧连接延迟断开时，其 MESSAGE 不能混入新会话', () async {
    broker.acknowledgeDisconnect = false;
    final values = <dynamic>[];
    client.subscribe(
      '/overlap',
      (value, _) => values.add(value),
      ack: AckMode.smart,
    );
    client.activate();
    await _waitFor(() => broker.subscriptionCount == 1);
    client.dispose(keepSubscriptions: true);
    client.activate();
    await _waitFor(() => broker.subscriptionCount == 2);
    expect(broker.sendMessage('/overlap', '7', withAck: true), 2);
    await _waitFor(() => broker.framesOf('ACK').isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(values, [7]);
    expect(broker.framesOf('ACK'), hasLength(1));
  });

  test('补发中途失败且新增离线消息时，回退队列仍受容量约束', () async {
    var fail = true;
    client = create(
      maxQueuedMessages: 2,
      onDebugMessage: (message) {
        if (!fail || !message.startsWith('>>> SEND')) return;
        fail = false;
        client.dispose(keepSubscriptions: true);
        client.send('/send', body: 'new-1');
        client.send('/send', body: 'new-2');
        throw StateError('模拟发送失败');
      },
    );
    client.send('/send', body: 'old-1');
    client.send('/send', body: 'old-2');
    client.activate();
    await _waitFor(
      () => !fail && client.state == StompConnectionState.disconnected,
    );
    client.activate();
    await _waitFor(() => broker.framesOf('SEND').length == 2);
    expect(broker.framesOf('SEND').map((frame) => frame.body), [
      'new-1',
      'new-2',
    ]);
  });

  test('禁用自动重连时首次连接错误进入 disconnected', () {
    client = create(reconnectDelay: Duration.zero);
    client.activate();
    client.client.config.onWebSocketError(StateError('模拟连接失败'));
    expect(client.state, StompConnectionState.disconnected);
  });

  test('共享回调中停止实例后，不再投递其余回调或确认', () async {
    var later = 0;
    client.subscribe(
      '/stop',
      (_, _) => client.dispose(keepSubscriptions: true),
      ack: AckMode.smart,
    );
    client.subscribe('/stop', (_, _) => later++, ack: AckMode.smart);
    client.activate();
    await _waitFor(() => broker.subscriptionCount == 1);
    broker.sendMessage('/stop', '1', withAck: true);
    await _waitFor(() => client.state == StompConnectionState.disconnected);
    expect(later, 0);
    expect(broker.framesOf('ACK'), isEmpty);
    expect(broker.framesOf('NACK'), isEmpty);
  });

  test('解析失败监控可同步取消订阅，后续消息仍正常分发', () async {
    client = create(
      onParseFailure: () => client.unsubscribe(destination: '/bad'),
    );
    client.subscribe('/bad', (_, _) => fail('不应投递解析失败消息'), ack: AckMode.smart);
    final values = <dynamic>[];
    client.subscribe(
      '/good',
      (value, _) => values.add(value),
      ack: AckMode.smart,
    );
    client.activate();
    await _waitFor(() => broker.subscriptionCount == 2);
    broker.sendMessage(
      '/bad',
      'binary',
      contentType: 'application/octet-stream',
      withAck: true,
    );
    await _waitFor(() => broker.subscriptionCount == 1);
    broker.sendMessage('/good', 'true', withAck: true);
    await _waitFor(() => broker.framesOf('ACK').isNotEmpty);
    expect(values, [true]);
    expect(broker.framesOf('NACK'), isEmpty);
  });
}
