import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import 'stomp_test_broker.dart';

/// 顶层二进制解码器（可被 compute 发送到后台 isolate）：utf8 → json。
Dictional _decodeUtf8Json(Uint8List bytes) => jsonDecode(utf8.decode(bytes)) as Dictional;

void main() {
  // AppLifecycleListener（resumeOnForeground 默认 true 时创建）需要已初始化的 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  late StompTestBroker broker;
  late Stompsocket client;

  /// 轮询等待条件成立，超时抛异常。用于等待真实的异步网络交互。
  Future<void> pump(
    bool Function() cond, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final sw = Stopwatch()..start();
    while (!cond()) {
      if (sw.elapsed > timeout) {
        throw TimeoutException('条件在 $timeout 内未成立');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() async {
    broker = StompTestBroker();
    await broker.start();
    client = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      reconnectDelay: const Duration(milliseconds: 80),
    );
  });

  tearDown(() async {
    client.dispose();
    await pump(() => !client.connected).catchError((_) {});
    await broker.stop();
  });

  test('subscribe: 收到并解析 JSON 消息', () async {
    client.activate();
    await pump(() => client.connected);

    final got = <Dictional>[];
    client.subscribe('/topic/a', (j, _) => got.add(j));
    await pump(() => broker.subscriptionCount == 1);

    broker.sendMessage('/topic/a', '{"v":1}');
    await pump(() => got.isNotEmpty);
    expect(got.single['v'], 1);
  });

  test('subscribe: 相同 id 多回调共享同一份解析数据，且只订阅一次', () async {
    client.activate();
    await pump(() => client.connected);

    Dictional? a, b;
    client.subscribe('/topic/a', (j, _) => a = j, id: 'S');
    client.subscribe('/topic/a', (j, _) => b = j, id: 'S');
    await pump(() => broker.subscriptionCount == 1);

    expect(broker.subscribeCountFor('S'), 1); // 只发了一次 SUBSCRIBE
    broker.sendMessage('/topic/a', '{"v":2}');
    await pump(() => a != null && b != null);
    expect(identical(a, b), isTrue); // 两个回调拿到同一个对象
  });

  test('unsubscribe: 按 id 取消单个订阅', () async {
    client.activate();
    await pump(() => client.connected);

    final sub = client.subscribe('/topic/a', (_, _) {});
    await pump(() => broker.subscriptionCount == 1);

    expect(client.unsubscribe(id: sub.id), 1);
    await pump(() => broker.subscriptionCount == 0);
    expect(broker.framesOf('UNSUBSCRIBE').single.headers['id'], sub.id);
  });

  test('unsubscribe: 按 destination 批量取消同一 topic', () async {
    client.activate();
    await pump(() => client.connected);

    client.subscribe('/topic/a', (_, _) {}, id: 'a1');
    client.subscribe('/topic/a', (_, _) {}, id: 'a2');
    client.subscribe('/topic/b', (_, _) {}, id: 'b1');
    await pump(() => broker.subscriptionCount == 3);

    expect(client.unsubscribe(destination: '/topic/a'), 2);
    await pump(() => broker.subscriptionCount == 1);
  });

  test('clear: 取消所有订阅', () async {
    client.activate();
    await pump(() => client.connected);

    client.subscribe('/topic/a', (_, _) {}, id: 'a1');
    client.subscribe('/topic/b', (_, _) {}, id: 'b1');
    await pump(() => broker.subscriptionCount == 2);

    client.clear();
    await pump(() => broker.subscriptionCount == 0);
  });

  test('未连接时订阅，连接建立后自动重放', () async {
    final got = <Dictional>[];
    client.subscribe('/topic/a', (j, _) => got.add(j)); // activate 之前订阅
    client.activate();

    await pump(() => broker.subscriptionCount == 1); // 连上后才发出 SUBSCRIBE
    broker.sendMessage('/topic/a', '{"v":9}');
    await pump(() => got.isNotEmpty);
    expect(got.single['v'], 9);
  });

  test('断线重连后自动重新订阅（无需 deactivate/activate）', () async {
    client.activate();
    await pump(() => client.connected);

    final got = <Dictional>[];
    client.subscribe('/topic/a', (j, _) => got.add(j));
    await pump(() => broker.subscriptionCount == 1);

    await broker.dropConnections(); // 模拟断网
    await pump(() => !client.connected, timeout: const Duration(seconds: 5));
    await pump(() => client.connected, timeout: const Duration(seconds: 5));
    await pump(() => broker.subscriptionCount == 1); // 新连接上自动重订阅

    broker.sendMessage('/topic/a', '{"v":7}');
    await pump(() => got.isNotEmpty);
    expect(got.single['v'], 7);
  });

  test('smart: 处理成功自动发 ACK', () async {
    client.activate();
    await pump(() => client.connected);

    client.subscribe('/topic/a', (_, _) {}, ack: AckMode.smart);
    await pump(() => broker.subscriptionCount == 1);
    expect(broker.framesOf('SUBSCRIBE').last.headers['ack'], 'client-individual');

    broker.sendMessage('/topic/a', '{"v":1}', withAck: true);
    await pump(() => broker.framesOf('ACK').isNotEmpty);
    expect(broker.framesOf('ACK').single.headers['id'], startsWith('ack-'));
    expect(broker.framesOf('NACK'), isEmpty);
  });

  test('auto-ack: 回调抛异常自动发 NACK', () async {
    client.activate();
    await pump(() => client.connected);

    client.subscribe('/topic/a', (_, _) => throw Exception('boom'),
        ack: AckMode.smart);
    await pump(() => broker.subscriptionCount == 1);

    broker.sendMessage('/topic/a', '{"v":1}', withAck: true);
    await pump(() => broker.framesOf('NACK').isNotEmpty);
    expect(broker.framesOf('ACK'), isEmpty);
  });

  test('auto-ack: 解析失败（二进制无 binaryDecoder）默认 NACK', () async {
    // 真正的解析失败：二进制帧但没配 binaryDecoder。
    // 非 JSON 纯文本已不是解析失败——会原样传给回调，不走 onParseError 路径。
    client.activate();
    await pump(() => client.connected);

    client.subscribe('/topic/a', (_, _) {}, ack: AckMode.smart);
    await pump(() => broker.subscriptionCount == 1);

    broker.sendBinaryMessage('/topic/a', Uint8List.fromList([0x1f, 0x8b]), withAck: true);
    await pump(() => broker.framesOf('NACK').isNotEmpty);
    expect(broker.framesOf('ACK'), isEmpty);
  });

  test('auto-ack: 解析失败 onParseError=ack 时 ACK 丢弃', () async {
    client.activate();
    await pump(() => client.connected);

    client.subscribe('/topic/a', (_, _) {},
        ack: AckMode.smart, onParseError: ParseFailureAck.ack);
    await pump(() => broker.subscriptionCount == 1);

    broker.sendBinaryMessage('/topic/a', Uint8List.fromList([0x1f, 0x8b]), withAck: true);
    await pump(() => broker.framesOf('ACK').isNotEmpty);
    expect(broker.framesOf('NACK'), isEmpty);
  });

  test('body 是非 JSON 纯文本：原样传给回调，不当成解析失败', () async {
    client.activate();
    await pump(() => client.connected);

    dynamic got;
    client.subscribe('/topic/text', (j, _) => got = j, ack: AckMode.smart);
    await pump(() => broker.subscriptionCount == 1);

    broker.sendMessage('/topic/text', 'hello world', withAck: true);
    await pump(() => got != null);
    expect(got, 'hello world');
    await pump(() => broker.framesOf('ACK').isNotEmpty); // 回调成功 → ACK
  });

  test('JSON 顶层是数组/数字：能解析就给解析结果，不是文本', () async {
    client.activate();
    await pump(() => client.connected);

    dynamic got;
    client.subscribe('/topic/arr', (j, _) => got = j);
    await pump(() => broker.subscriptionCount == 1);

    broker.sendMessage('/topic/arr', '[1,2,3]');
    await pump(() => got != null);
    expect(got, [1, 2, 3]);
  });

  test('大 JSON（>32KB）经 compute 后台解析仍正确', () async {
    client.activate();
    await pump(() => client.connected);

    Dictional? got;
    client.subscribe('/topic/big', (j, _) => got = j);
    await pump(() => broker.subscriptionCount == 1);

    final body = jsonEncode({'data': List.generate(5000, (i) => 'item-$i')});
    expect(body.length, greaterThan(32 * 1024));

    broker.sendMessage('/topic/big', body);
    await pump(() => got != null, timeout: const Duration(seconds: 5));
    expect((got!['data'] as List).length, 5000);
    expect((got!['data'] as List).last, 'item-4999');
  });

  test('dispose 后可再次 activate 并重新订阅', () async {
    client.activate();
    await pump(() => client.connected);
    client.subscribe('/topic/a', (_, _) {});
    await pump(() => broker.subscriptionCount == 1);

    client.dispose(); // 默认清空订阅
    await pump(() => !client.connected);

    client.activate(); // 复用实例
    await pump(() => client.connected, timeout: const Duration(seconds: 5));

    final got = <Dictional>[];
    client.subscribe('/topic/a', (j, _) => got.add(j));
    await pump(() => broker.subscriptionCount == 1);
    broker.sendMessage('/topic/a', '{"v":1}');
    await pump(() => got.isNotEmpty);
    expect(got.single['v'], 1);
  });

  test('dispose(keepSubscriptions:true) 后 activate 自动恢复订阅', () async {
    client.activate();
    await pump(() => client.connected);

    final got = <Dictional>[];
    client.subscribe('/topic/a', (j, _) => got.add(j));
    await pump(() => broker.subscriptionCount == 1);

    client.dispose(keepSubscriptions: true); // 保留订阅
    await pump(() => !client.connected);

    client.activate();
    // 无需重新 subscribe，连上后自动重放
    await pump(() => broker.subscriptionCount == 1,
        timeout: const Duration(seconds: 5));

    broker.sendMessage('/topic/a', '{"v":42}');
    await pump(() => got.isNotEmpty);
    expect(got.single['v'], 42);
  });

  test('auto(默认): 不发送任何 ACK/NACK', () async {
    client.activate();
    await pump(() => client.connected);

    client.subscribe('/topic/a', (_, _) {}); // 默认 AckMode.auto
    await pump(() => broker.subscriptionCount == 1);
    // 默认不带 ack 头（STOMP auto，服务端自动确认）
    expect(broker.framesOf('SUBSCRIBE').last.headers.containsKey('ack'), isFalse);

    broker.sendMessage('/topic/a', '{"v":1}', withAck: true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(broker.framesOf('ACK'), isEmpty);
    expect(broker.framesOf('NACK'), isEmpty);
  });

  test('manual: 通过 ctrl 手动 ACK（可在回调外调用），且幂等', () async {
    client.activate();
    await pump(() => client.connected);

    AckControl? saved;
    Dictional? got;
    client.subscribe('/topic/m', (j, ack) {
      got = j;
      saved = ack;
    }, ack: AckMode.manual);
    await pump(() => broker.subscriptionCount == 1);
    expect(broker.framesOf('SUBSCRIBE').last.headers['ack'], 'client-individual');

    broker.sendMessage('/topic/m', '{"v":1}', withAck: true);
    await pump(() => saved != null);
    expect(got!['v'], 1);

    // manual 下本封装不自动应答
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(broker.framesOf('ACK'), isEmpty);

    // 回调外部手动 ack
    saved!.ack();
    await pump(() => broker.framesOf('ACK').isNotEmpty);
    saved!.ack(); // 幂等
    expect(broker.framesOf('ACK').length, 1);
  });

  test('manual: 重连后旧 ctrl 失效（no-op）', () async {
    client.activate();
    await pump(() => client.connected);

    AckControl? saved;
    client.subscribe('/topic/m', (_, ack) => saved = ack, ack: AckMode.manual);
    await pump(() => broker.subscriptionCount == 1);
    broker.sendMessage('/topic/m', '{"v":1}', withAck: true);
    await pump(() => saved != null);

    await broker.dropConnections();
    await pump(() => !client.connected, timeout: const Duration(seconds: 5));
    await pump(() => client.connected, timeout: const Duration(seconds: 5));

    // 旧会话的句柄失效，ack 应为 no-op
    saved!.ack();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(broker.framesOf('ACK'), isEmpty);
  });

  test('ordered=true: 大包(异步)后紧跟小包(同步)仍按到达顺序分发', () async {
    client.activate();
    await pump(() => client.connected);

    final order = <String>[];
    client.subscribe('/topic/x', (j, _) => order.add(j['tag'] as String));
    await pump(() => broker.subscriptionCount == 1);

    // 先发 >32KB 大包（走 compute 异步），紧接一个小包（同步）
    final big = jsonEncode(
        {'tag': 'big', 'pad': List.generate(5000, (i) => 'x$i')});
    expect(big.length, greaterThan(32 * 1024));
    broker.sendMessage('/topic/x', big);
    broker.sendMessage('/topic/x', '{"tag":"small"}');

    await pump(() => order.length == 2, timeout: const Duration(seconds: 5));
    expect(order, ['big', 'small']); // 顺序保持，未被异步解析打乱
  });

  test('返回句柄 unsubscribe(): 自动 id 订阅直接取消并 UNSUBSCRIBE', () async {
    client.activate();
    await pump(() => client.connected);

    final sub = client.subscribe('/topic/a', (_, _) {});
    await pump(() => broker.subscriptionCount == 1);

    sub.unsubscribe();
    await pump(() => broker.subscriptionCount == 0);
    expect(broker.framesOf('UNSUBSCRIBE').single.headers['id'], sub.id);

    sub.unsubscribe(); // 幂等，重复调用无副作用
    expect(broker.framesOf('UNSUBSCRIBE').length, 1);
  });

  test('引用计数: 同 id 两回调，取消一个仍在线，取消最后一个才 UNSUBSCRIBE', () async {
    client.activate();
    await pump(() => client.connected);

    final got1 = <Dictional>[];
    final got2 = <Dictional>[];
    final s1 = client.subscribe('/topic/a', (j, _) => got1.add(j), id: 'S');
    final s2 = client.subscribe('/topic/a', (j, _) => got2.add(j), id: 'S');
    await pump(() => broker.subscriptionCount == 1);

    // 取消第一个回调：订阅仍在，服务端未收到 UNSUBSCRIBE
    s1.unsubscribe();
    broker.sendMessage('/topic/a', '{"v":1}');
    await pump(() => got2.isNotEmpty);
    expect(got1, isEmpty); // 已取消，收不到
    expect(broker.subscriptionCount, 1);
    expect(broker.framesOf('UNSUBSCRIBE'), isEmpty);

    // 取消最后一个回调：真正 UNSUBSCRIBE
    s2.unsubscribe();
    await pump(() => broker.subscriptionCount == 0);
    expect(broker.framesOf('UNSUBSCRIBE').single.headers['id'], 'S');
  });

  test('同一 topic 独立订阅（显式不同 id）: 各自 SUBSCRIBE、各自收到', () async {
    // 需要独立订阅时显式传不同 id（逃生门）
    client.activate();
    await pump(() => client.connected);

    final got1 = <dynamic>[];
    final got2 = <dynamic>[];
    client.subscribe('/topic/a', (j, _) => got1.add(j), id: 'sub-1');
    client.subscribe('/topic/a', (j, _) => got2.add(j), id: 'sub-2');
    await pump(() => broker.subscriptionCount == 2);
    expect(broker.framesOf('SUBSCRIBE').length, 2);

    broker.sendMessage('/topic/a', '{"v":5}'); // 投递给 2 条订阅
    await pump(() => got1.isNotEmpty && got2.isNotEmpty);
    expect((got1.single as Map)['v'], 5);
    expect((got2.single as Map)['v'], 5);
    // 独立订阅：不共享对象
    expect(identical(got1.single, got2.single), isFalse);
  });

  test('subscribe（不传 id）：同 destination + 同选项自动归并，消息只解析一次', () async {
    client.activate();
    await pump(() => client.connected);

    dynamic a;
    dynamic b;
    client.subscribe('/topic/merge', (j, _) => a = j);
    client.subscribe('/topic/merge', (j, _) => b = j);
    await pump(() => broker.subscriptionCount == 1); // 只产生一条 wire 订阅

    broker.sendMessage('/topic/merge', '{"v":9}');
    await pump(() => a != null && b != null);
    expect(identical(a, b), isTrue); // 同一对象引用（只解析一次）
  });

  test('subscribe（不传 id）：同 destination 但 ack 不同时独立订阅', () async {
    client.activate();
    await pump(() => client.connected);

    client.subscribe('/topic/split', (_, _) {}, ack: AckMode.auto);
    client.subscribe('/topic/split', (_, _) {}, ack: AckMode.smart);
    await pump(() => broker.subscriptionCount == 2); // 两条独立的 wire 订阅
  });

  test('subscribe（不传 id）：引用计数——两个订阅者都取消后才发 UNSUBSCRIBE', () async {
    client.activate();
    await pump(() => client.connected);

    final s1 = client.subscribe('/topic/rc', (_, _) {});
    final s2 = client.subscribe('/topic/rc', (_, _) {});
    await pump(() => broker.subscriptionCount == 1);

    s1.unsubscribe();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(broker.subscriptionCount, 1); // s2 还在，不发 UNSUBSCRIBE
    expect(broker.framesOf('UNSUBSCRIBE'), isEmpty);

    s2.unsubscribe();
    await pump(() => broker.subscriptionCount == 0);
    expect(broker.framesOf('UNSUBSCRIBE').length, 1);
  });

  test('subscribe（传 id）：显式 id 与自动归并键完全独立', () async {
    client.activate();
    await pump(() => client.connected);

    // 一个自动归并、一个显式 id——即使 destination 相同也是两条独立订阅
    client.subscribe('/topic/explicit', (_, _) {});
    client.subscribe('/topic/explicit', (_, _) {}, id: 'my-id');
    await pump(() => broker.subscriptionCount == 2);
  });

  test('自动归并键不含 NUL：SUBSCRIBE 的 id 头 wire 安全', () async {
    // 回归：曾用 \x00 作分隔符，NUL 是 STOMP 帧终止符，放进 id 头会把帧从中间截断。
    client.activate();
    await pump(() => client.connected);
    client.subscribe('/topic/nulcheck', (_, _) {});
    await pump(() => broker.subscriptionCount == 1);

    final id = broker.framesOf('SUBSCRIBE').last.headers['id'] ?? '';
    expect(id.contains('\x00'), isFalse);
    expect(id.contains('/topic/nulcheck'), isTrue);
  });

  test('content-type 缺失 + UTF-8 JSON 字节：按文本解析，不走 binaryDecoder', () async {
    // stomp_dart 对 content-type 缺失的帧也产出 binaryBody（ActiveMQ 常见）；
    // 严格 UTF-8 探测应把它救回文本路径。
    client.activate();
    await pump(() => client.connected);

    dynamic got;
    client.subscribe('/topic/nohdr', (j, _) => got = j);
    await pump(() => broker.subscriptionCount == 1);

    broker.sendBinaryMessage('/topic/nohdr',
        Uint8List.fromList(utf8.encode('{"n":1}'))); // 无 content-type
    await pump(() => got != null);
    expect((got as Map)['n'], 1);
  });

  test('content-type 显式 octet-stream：直接走 binaryDecoder（快路径）', () async {
    // 即使内容恰好是合法 UTF-8，显式声明了二进制就不做文本探测
    final c = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      binaryDecoder: _decodeUtf8Json,
    );
    addTearDown(c.dispose);
    c.activate();
    await pump(() => c.connected);

    dynamic got;
    c.subscribe('/topic/explicit-bin', (j, _) => got = j);
    await pump(() => broker.subscriptionCount == 1);

    broker.sendMessage('/topic/explicit-bin', '{"b":true}',
        contentType: 'application/octet-stream');
    await pump(() => got != null);
    expect((got as Map)['b'], true);
  });

  test('onParseFailure：二进制解析失败时业务可观测', () async {
    String? failedError;
    final c = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      onParseFailure: (_, error) => failedError = error,
    );
    c.activate();
    await pump(() => c.connected);
    c.subscribe('/topic/pf', (_, _) {});
    await pump(() => broker.subscriptionCount == 1);

    broker.sendBinaryMessage('/topic/pf', Uint8List.fromList([0x1f, 0x8b]));
    await pump(() => failedError != null);
    expect(failedError, contains('binaryDecoder'));
    c.dispose();
  });

  test('send: 已连接时 Map body 自动 json 编码并发出 SEND', () async {
    client.activate();
    await pump(() => client.connected);

    client.send('/app/order', body: {'sku': 'A', 'qty': 2});
    await pump(() => broker.framesOf('SEND').isNotEmpty);

    final f = broker.framesOf('SEND').single;
    expect(f.headers['destination'], '/app/order');
    expect(f.headers['content-type'], 'application/json');
    expect(jsonDecode(f.body), {'sku': 'A', 'qty': 2});
  });

  test('send: 未连接时缓冲，连接后按序补发', () async {
    // activate 之前发送 → 入缓冲
    client.send('/app/x', body: 'first');
    client.send('/app/x', body: 'second');

    client.activate();
    await pump(() => broker.framesOf('SEND').length == 2,
        timeout: const Duration(seconds: 5));

    final sends = broker.framesOf('SEND');
    expect(sends.map((f) => f.body), ['first', 'second']); // 顺序保持
  });

  test('状态: idle → connecting → connected，且 stateListenable 响应式通知', () async {
    expect(client.state, StompConnectionState.idle);

    final seen = <StompConnectionState>[];
    client.stateListenable.addListener(() => seen.add(client.state));

    client.activate();
    expect(client.state, StompConnectionState.connecting); // 同步进入 connecting
    await pump(() => client.connected);

    expect(client.state, StompConnectionState.connected);
    expect(seen, containsAllInOrder(
        [StompConnectionState.connecting, StompConnectionState.connected]));

    client.dispose();
    expect(client.state, StompConnectionState.disconnected);
  });

  test('beforeConnect: 连接前刷新 token 并带入 CONNECT 头', () async {
    var calls = 0;
    final c = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      beforeConnect: () async {
        calls++;
        return {'Authorization': 'Bearer token-$calls'};
      },
    );
    addTearDown(c.dispose);

    c.activate();
    await pump(() => c.connected);

    final connect = broker.framesOf('CONNECT').single;
    expect(connect.headers['Authorization'], 'Bearer token-1');
    expect(calls, 1);
  });

  test('断线重连时重新执行 beforeConnect（token 可刷新）', () async {
    var calls = 0;
    final c = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      reconnectDelay: const Duration(milliseconds: 80),
      beforeConnect: () async {
        calls++;
        return {'Authorization': 'Bearer token-$calls'};
      },
    );
    addTearDown(c.dispose);

    c.activate();
    await pump(() => c.connected);
    await broker.dropConnections();
    await pump(() => !c.connected, timeout: const Duration(seconds: 5));
    await pump(() => c.connected, timeout: const Duration(seconds: 5));

    // 重连用的是刷新后的第二个 token
    expect(calls, greaterThanOrEqualTo(2));
    expect(broker.framesOf('CONNECT').last.headers['Authorization'],
        'Bearer token-$calls');
  });

  test('binaryDecoder: 使用方自定义二进制解码策略', () async {
    final c = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      binaryDecoder: _decodeUtf8Json,
    );
    addTearDown(c.dispose);
    c.activate();
    await pump(() => c.connected);

    Dictional? got;
    c.subscribe('/topic/bin', (j, _) => got = j);
    await pump(() => broker.subscriptionCount == 1);

    // content-type=octet-stream → 客户端将 body 归入 binaryBody
    broker.sendMessage('/topic/bin', '{"b":true}',
        contentType: 'application/octet-stream');
    await pump(() => got != null);
    expect(got!['b'], true);
  });

  test('未配置 binaryDecoder 时二进制消息按解析失败处理（NACK）', () async {
    client.activate();
    await pump(() => client.connected);

    client.subscribe('/topic/bin', (_, _) {}, ack: AckMode.smart);
    await pump(() => broker.subscriptionCount == 1);

    broker.sendMessage('/topic/bin', 'anything', withAck: true,
        contentType: 'application/octet-stream');
    await pump(() => broker.framesOf('NACK').isNotEmpty);
  });

  test('debug + onLog: 日志走使用方回调（含帧级流水）', () async {
    final logs = <String>[];
    final c = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      debug: true,
      onLog: (m, {error, stackTrace}) => logs.add(m),
    );
    addTearDown(c.dispose);
    c.activate();
    await pump(() => c.connected);

    expect(logs, isNotEmpty);
    expect(logs.any((l) => l.contains('CONNECT')), isTrue); // 捕获到帧流水
  });

  test('debug=false: 不产生任何日志（onLog 不被调用）', () async {
    final logs = <String>[];
    final c = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      onLog: (m, {error, stackTrace}) => logs.add(m),
    );
    addTearDown(c.dispose);
    c.activate();
    await pump(() => c.connected);

    expect(logs, isEmpty);
  });

  test('onStompError: 服务端 ERROR 帧回调透出（新暴露的原生回调）', () async {
    StompFrame? err;
    final c = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      onStompError: (f) => err = f,
    );
    addTearDown(c.dispose);
    c.activate();
    await pump(() => c.connected);

    broker.sendError('bad-destination');
    await pump(() => err != null);
    expect(err!.headers['message'], 'bad-destination');
  });

  test('forceReconnect: 跳过 reconnectDelay 立即重连', () async {
    final c = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      reconnectDelay: const Duration(seconds: 30), // 故意很长，证明不是自动重连生效
    );
    addTearDown(c.dispose);
    c.activate();
    await pump(() => c.connected);

    await broker.dropConnections();
    await pump(() => !c.connected, timeout: const Duration(seconds: 5));

    // 30s 内库不会自动重连；forceReconnect 应立即重连
    c.forceReconnect();
    await pump(() => c.connected, timeout: const Duration(seconds: 5));
  });

  test('copyWith: 覆盖提供的参数，未提供的继承，且是独立可用的新实例', () async {
    final base = Stompsocket(
      url: 'ws://127.0.0.1:${broker.port}',
      reconnectDelay: const Duration(milliseconds: 80),
      maxQueuedMessages: 7,
    );
    addTearDown(base.dispose);

    final derived = base.copyWith(maxQueuedMessages: 99);
    addTearDown(derived.dispose);

    expect(derived.maxQueuedMessages, 99); // 覆盖
    expect(derived.reconnectDelay, const Duration(milliseconds: 80)); // 继承
    expect(identical(derived, base), isFalse); // 是新实例

    // 新实例能独立连接
    derived.activate();
    await pump(() => derived.connected);
    final got = <Dictional>[];
    derived.subscribe('/topic/copy', (j, _) => got.add(j));
    await pump(() => broker.subscriptionCount == 1);
    broker.sendMessage('/topic/copy', '{"v":1}');
    await pump(() => got.isNotEmpty);
    expect(got.single['v'], 1);
  });
}
