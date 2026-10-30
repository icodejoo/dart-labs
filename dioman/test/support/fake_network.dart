import 'constants.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

/// 不变量请求标记头。
const invariantRequestHeader = 'x-invariant-request';

/// 一次可脚本化的网络回复。
class FakeReply {
  /// 创建响应，可用 gate 阻塞，也可抛出 error。
  const FakeReply(
      {this.status = 200,
      this.body = const {pipelineTestCode: 0, pipelineTestData: pipelineTestOk},
      this.error,
      this.gate});

  /// HTTP 状态。
  final int status;

  /// 原始 JSON 载荷。
  final Object? body;

  /// 指定失败异常。
  final Object? error;

  /// 人工控制响应时机。
  final Future<void>? gate;
}

/// 捕获发送时快照，避免 Transformer 后续原地修改记录。
class FakeSend {
  /// 捕获实际有效配置与线上请求体。
  FakeSend(this.options, this.body, this.invariant);

  /// 实际 Dio 请求配置。
  final RequestOptions options;

  /// 发送时解码后的请求体。
  final Object? body;

  /// 逻辑请求标记。
  final Object? invariant;
}

/// 按方法路径路由、序列和第 n 次失败的假 adapter。
class FakeNetwork implements HttpClientAdapter {
  /// 创建空路由 adapter，缺省返回成功信封。
  FakeNetwork({this.onSend});

  /// 发送已记录时通知测试，避免猜测微任务次数。
  final void Function(FakeSend send)? onSend;

  /// 路由表，例如 GET:/pets。
  final routes = <String, List<FakeReply>>{};

  /// 每个路由的已发送次数。
  final counts = <String, int>{};

  /// 第 n 次发送覆盖脚本。
  final failOn = <int, Object>{};

  /// 所有实际发送。
  final sends = <FakeSend>[];

  /// 是否已关闭。
  bool closed = false;

  /// 执行假网络发送，读取 Dio 已转换的线上请求体。
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = requestStream == null
        ? <int>[]
        : await requestStream.expand((b) => b).toList();
    Object? body;
    if (bytes.isNotEmpty) {
      final text = utf8.decode(bytes, allowMalformed: true);
      try {
        body = jsonDecode(text);
      } catch (_) {
        body = text;
      }
    }
    sends.add(FakeSend(options, body, options.headers[invariantRequestHeader]));
    final sendIndex = sends.length;
    onSend?.call(sends.last);
    final route = '${options.method}:${options.path}';
    final index = counts.update(route, (n) => n + 1, ifAbsent: () => 1) - 1;
    final replies = routes[route] ?? const [FakeReply()];
    final reply = replies[index < replies.length ? index : replies.length - 1];
    if (reply.gate != null) await reply.gate;
    final error = failOn[sendIndex] ?? reply.error;
    if (error != null) throw error;
    return ResponseBody.fromString(jsonEncode(reply.body), reply.status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  /// 记录 adapter 被关闭。
  @override
  void close({bool force = false}) => closed = true;
}
