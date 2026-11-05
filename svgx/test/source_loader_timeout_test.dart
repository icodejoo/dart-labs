import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/svg_source_loader.dart';

class Client extends Fake implements HttpClient {
  Client(this.stallOpen);
  final bool stallOpen;
  bool closed = false;
  @override
  Future<HttpClientRequest> getUrl(Uri url) => stallOpen
      ? Completer<HttpClientRequest>().future
      : Future.value(Request());
  @override
  void close({bool force = false}) {
    closed = true;
  }
}

class Request extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() => Completer<HttpClientResponse>().future;
}

class Overrides extends HttpOverrides {
  Overrides(this.client);
  final HttpClient client;
  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

class RealHttpOverrides extends HttpOverrides {}

void main() {
  final defaultTimeout = SvgSourceLoader.networkTimeout;
  setUp(() {
    SvgSourceLoader.networkTimeout = const Duration(milliseconds: 300);
  });
  tearDown(() {
    SvgSourceLoader.networkTimeout = defaultTimeout;
    SvgSourceLoader.instance.clear();
  });

  test('network timeout defaults to 30 seconds', () {
    expect(defaultTimeout, const Duration(seconds: 30));
  });

  test(
    'network body stalls after headers and uses the configured timeout',
    () => HttpOverrides.runZoned(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final headersSent = Completer<void>();
      server.listen((request) async {
        request.response.write('<svg');
        await request.response.flush();
        headersSent.complete();
        // Keep the body open after sending headers and an initial chunk.
      });
      try {
        final result = SvgSourceLoader.instance.network(
          'http://127.0.0.1:${server.port}/stalled-body',
        );
        final assertion = expectLater(result, throwsA(isA<TimeoutException>()));
        await headersSent.future;
        await assertion.timeout(const Duration(seconds: 5));
      } finally {
        SvgSourceLoader.instance.clear();
        await server.close(force: true);
      }
    }, createHttpClient: RealHttpOverrides().createHttpClient),
  );

  for (final opening in [true, false]) {
    testWidgets(
      'network ${opening ? 'getUrl' : 'close'} uses the configured timeout',
      (tester) async {
        final client = Client(opening);
        Object? error;
        await HttpOverrides.runWithHttpOverrides(() async {
          SvgSourceLoader.instance
              .network('http://timeout/${opening ? 'open' : 'close'}')
              .then(
                (_) {},
                onError: (Object e, StackTrace s) {
                  error = e;
                },
              );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 299));
          expect(error, isNull);
          await tester.pump(const Duration(milliseconds: 1));
          expect(error, isA<TimeoutException>());
        }, Overrides(client));
        expect(client.closed, true);
        SvgSourceLoader.instance.clear();
      },
    );
  }
}
