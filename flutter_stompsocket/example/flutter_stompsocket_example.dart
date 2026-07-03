// ignore_for_file: avoid_print

import 'package:flutter_stompsocket/flutter_stompsocket.dart';

Future<void> main() async {
  final ws = Stompsocket(
    url: 'wss://example.com/ws',
    // 每次连接前刷新 token（含重连）
    beforeConnect: () async => {'Authorization': 'Bearer <token>'},
    // 每次（重）连成功后：重放订阅之后触发，可在此重拉快照
    onConnected: (_) => print('connected'),
    // 连接状态变化（也可用 ws.stateListenable 做响应式 UI）
    onStateChanged: (s) => print('state: $s'),
  );

  ws.activate();

  // 订阅；相同 id 的多个回调共用同一份解析数据
  final sub = ws.subscribe('/topic/quote', (json, ack) {
    print('quote: $json');
  });

  // 手动确认模式：处理完自己 ack（可存到回调外异步再调）
  ws.subscribe('/queue/tasks', (json, ack) {
    // ... 处理 ...
    ack.ack();
  }, ack: AckMode.manual);

  // 发送（object 自动 JSON 编码；未连接时会缓冲、连上后补发）
  ws.send('/app/order', body: {'sku': 'A', 'qty': 2});

  // 取消单个回调（引用计数）/ 关闭
  sub.unsubscribe();
  await Future<void>.delayed(const Duration(seconds: 1));
  ws.dispose();
}
