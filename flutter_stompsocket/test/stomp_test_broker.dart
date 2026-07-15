import 'dart:io';
import 'dart:typed_data';

/// 极简 STOMP-over-WebSocket 测试 broker，仅实现客户端用到的帧子集：
/// CONNECT→CONNECTED、SUBSCRIBE/UNSUBSCRIBE、MESSAGE 下推、ACK/NACK 记录、
/// DISCONNECT→RECEIPT。用于集成测试，无任何外部依赖。
class StompTestBroker {
  HttpServer? _server;
  final List<_Conn> _conns = [];
  int _messageId = 0;

  /// 客户端发来的所有帧（按到达顺序），供断言。
  final List<ReceivedFrame> received = [];

  int get port => _server!.port;

  /// 当前所有活动连接上的订阅总数（subId → destination）
  int get subscriptionCount => _conns.fold(0, (s, c) => s + c.subs.length);

  List<ReceivedFrame> framesOf(String command) =>
      received.where((f) => f.command == command).toList(growable: false);

  int subscribeCountFor(String id) => received
      .where((f) => f.command == 'SUBSCRIBE' && f.headers['id'] == id)
      .length;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      final conn = _Conn(ws);
      _conns.add(conn);
      ws.listen(
        (data) => _onData(conn, data),
        onDone: () => _conns.remove(conn),
        onError: (_) => _conns.remove(conn),
      );
    });
  }

  Future<void> stop() async {
    await dropConnections();
    await _server?.close(force: true);
    _server = null;
  }

  /// 强制关闭当前所有连接（模拟网络中断，触发客户端重连）。
  Future<void> dropConnections() async {
    for (final c in _conns.toList()) {
      await c.ws.close();
    }
    _conns.clear();
  }

  /// 向订阅了 [destination] 的所有连接推送一条 MESSAGE，返回投递条数。
  int sendMessage(
    String destination,
    String body, {
    String contentType = 'application/json',
    bool withAck = false,
  }) {
    var delivered = 0;
    for (final c in _conns) {
      c.subs.forEach((subId, dest) {
        if (dest != destination) return;
        final mid = 'msg-${_messageId++}';
        c.send('MESSAGE', {
          'subscription': subId,
          'message-id': mid,
          'destination': destination,
          'content-type': contentType,
          if (withAck) 'ack': 'ack-$mid',
        }, body);
        delivered++;
      });
    }
    return delivered;
  }

  /// 向订阅了 [destination] 的所有连接推送一条 MESSAGE，body 为真正的二进制帧，
  /// 用于测试"收到二进制 body"的场景（stomp_dart_client 对 WS binary 帧产出 binaryBody）。
  int sendBinaryMessage(
    String destination,
    Uint8List body, {
    bool withAck = false,
  }) {
    var delivered = 0;
    for (final c in _conns) {
      c.subs.forEach((subId, dest) {
        if (dest != destination) return;
        final mid = 'msg-${_messageId++}';
        c.sendBinary('MESSAGE', {
          'subscription': subId,
          'message-id': mid,
          'destination': destination,
          'content-length': '${body.length}',
          if (withAck) 'ack': 'ack-$mid',
        }, body);
        delivered++;
      });
    }
    return delivered;
  }

  /// 向所有连接发送一帧 STOMP ERROR。
  void sendError(String message, {String body = ''}) {
    for (final c in _conns) {
      c.send('ERROR', {'message': message, 'content-type': 'text/plain'}, body);
    }
  }

  void _onData(_Conn conn, dynamic data) {
    if (data is! String) return; // 测试中客户端只发文本帧
    final frame = _parse(data);
    if (frame == null) return; // 心跳/空帧
    received.add(ReceivedFrame(frame.command, frame.headers, frame.body));

    switch (frame.command) {
      case 'CONNECT':
      case 'STOMP':
        // 不带 heart-beat 头 → 客户端不会启动心跳定时器
        conn.send('CONNECTED', {'version': '1.2'});
      case 'SUBSCRIBE':
        conn.subs[frame.headers['id']!] = frame.headers['destination']!;
      case 'UNSUBSCRIBE':
        conn.subs.remove(frame.headers['id']);
      case 'DISCONNECT':
        final r = frame.headers['receipt'];
        if (r != null) conn.send('RECEIPT', {'receipt-id': r});
      // ACK / NACK / SEND：已记入 received，供断言
    }
  }

  _Frame? _parse(String raw) {
    var s = raw;
    if (s.endsWith('\x00')) s = s.substring(0, s.length - 1);
    if (s.trim().isEmpty) return null; // 心跳

    final sep = s.indexOf('\n\n');
    final head = sep >= 0 ? s.substring(0, sep) : s;
    final body = sep >= 0 ? s.substring(sep + 2) : '';
    final lines = head.split('\n');
    final headers = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      final c = lines[i].indexOf(':');
      if (c > 0) headers[lines[i].substring(0, c)] = lines[i].substring(c + 1);
    }
    return _Frame(lines.first, headers, body);
  }
}

class ReceivedFrame {
  ReceivedFrame(this.command, this.headers, this.body);
  final String command;
  final Map<String, String> headers;
  final String body;
}

class _Frame {
  _Frame(this.command, this.headers, this.body);
  final String command;
  final Map<String, String> headers;
  final String body;
}

class _Conn {
  _Conn(this.ws);
  final WebSocket ws;
  final Map<String, String> subs = {}; // subId → destination

  /// 序列化并发送一帧（文本 WS 帧）。body 以 NULL 结尾。
  void send(String command, Map<String, String> headers, [String? body]) {
    final sb = StringBuffer(command);
    headers.forEach((k, v) => sb.write('\n$k:$v'));
    sb.write('\n\n');
    if (body != null) sb.write(body);
    sb.write('\x00');
    try {
      ws.add(sb.toString());
    } catch (_) {
      // 连接正在关闭（如测试 teardown 期间），忽略。
    }
  }

  /// 序列化并发送一帧（二进制 WS 帧，stomp_dart_client 收到后产出 binaryBody 非 null）。
  void sendBinary(String command, Map<String, String> headers, Uint8List body) {
    // header 部分是 UTF-8 文本，body 是原始字节，以 0x00 结尾拼成 Uint8List
    final headerStr = StringBuffer(command);
    headers.forEach((k, v) => headerStr.write('\n$k:$v'));
    headerStr.write('\n\n');
    final headerBytes = Uint8List.fromList(headerStr.toString().codeUnits);
    final result = Uint8List(headerBytes.length + body.length + 1);
    result.setRange(0, headerBytes.length, headerBytes);
    result.setRange(headerBytes.length, headerBytes.length + body.length, body);
    result[headerBytes.length + body.length] = 0x00;
    try {
      ws.add(result);
    } catch (_) {}
  }
}
