// ignore_for_file: avoid_relative_lib_imports
import '../accept/lib/literals.dart';
// Real dart:io HttpServer harness for dioman's integration tests — replaces
// the hand-rolled FakeAdapter so requests go over a real TCP loopback
// connection, get real DNS/connect/cancel semantics, and let plugins that
// internally re-dispatch via a bare `Dio()` (DiomanAuth's replay,
// DiomanShare's retry policy) actually reach a real server instead of
// hanging/erroring against the real internet.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 封装 TestServer 测试夹具。
/// A real HTTP server bound to loopback on a random free port. Every
/// request is handed to [handler]; uncaught handler exceptions become a 500
/// so a bug in test setup doesn't hang the client waiting for a response.
class TestServer {
  /// 构造独立测试实例。
  TestServer._(this._server, this._sub);

  final HttpServer _server;
  final StreamSubscription<HttpRequest> _sub;

  /// start 的测试实现。
  static Future<TestServer> start(
    FutureOr<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = server.listen((request) async {
      try {
        await handler(request);
      } catch (_) {
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {} // response may already be closed/detached
      }
    });
    return TestServer._(server, sub);
  }

  /// baseUrl 的测试实现。
  /// Base URL requests should be sent to, e.g. `http://127.0.0.1:54321`.
  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  /// close 的测试实现。
  Future<void> close() async {
    await _sub.cancel();
    await _server.close(force: true);
  }
}

/// respondJson 的测试辅助入口。
/// Writes a JSON [data] body with [status] and closes the response.
///
/// Forces `Connection: close` — dio doesn't necessarily drain a non-2xx
/// response body before it's done with the request (it errors out as soon
/// as it sees the status), so a client that then reuses a keep-alive
/// connection for a LATER, unrelated request can read leftover bytes from
/// THIS response instead of the new one. Closing the connection per request
/// sidesteps that entirely — tests don't need connection-pooling
/// performance, just correctness.
Future<void> respondJson(
  HttpRequest request,
  Object? data,
  int status,
) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.headers.set(HttpHeaders.connectionHeader, tkClose);
  request.response.write(jsonEncode(data));
  await request.response.close();
}
