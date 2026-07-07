// Real dart:io HttpServer harness for dioman's integration tests — replaces
// the hand-rolled FakeAdapter so requests go over a real TCP loopback
// connection, get real DNS/connect/cancel semantics, and let plugins that
// internally re-dispatch via a bare `Dio()` (DiomanAuth's replay,
// DiomanShare's retry policy) actually reach a real server instead of
// hanging/erroring against the real internet.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A real HTTP server bound to loopback on a random free port. Every
/// request is handed to [handler]; uncaught handler exceptions become a 500
/// so a bug in test setup doesn't hang the client waiting for a response.
class TestServer {
  TestServer._(this._server, this._sub);

  final HttpServer _server;
  final StreamSubscription<HttpRequest> _sub;

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

  /// Base URL requests should be sent to, e.g. `http://127.0.0.1:54321`.
  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> close() async {
    await _sub.cancel();
    await _server.close(force: true);
  }
}

/// Writes a JSON [data] body with [status] and closes the response.
Future<void> respondJson(
  HttpRequest request,
  Object? data,
  int status,
) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(data));
  await request.response.close();
}
