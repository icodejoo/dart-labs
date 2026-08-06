import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

void main() {
  group('NetworkWarmFeedPrefetcher', () {
    test('requests only a byte range, not the whole body', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? rangeSeen;
      server.listen((request) {
        rangeSeen = request.headers.value(HttpHeaders.rangeHeader);
        request.response
          ..statusCode = HttpStatus.partialContent
          ..write('x' * 100);
        request.response.close();
      });
      addTearDown(() => server.close(force: true));

      const prefetcher = NetworkWarmFeedPrefetcher(rangeBytes: 1024);
      await prefetcher.prime(MovaSource('http://127.0.0.1:${server.port}/video.mp4'));

      expect(rangeSeen, 'bytes=0-1024');
    });

    test('is a no-op for an unparseable uri', () async {
      const prefetcher = NetworkWarmFeedPrefetcher();
      await expectLater(prefetcher.prime(const MovaSource('::: not a uri')), completes);
    });

    test('swallows connection failures without throwing', () async {
      const prefetcher = NetworkWarmFeedPrefetcher(timeout: Duration(milliseconds: 200));
      // Port 1 is a reserved, always-refused port on loopback.
      await expectLater(prefetcher.prime(const MovaSource('http://127.0.0.1:1/x.mp4')), completes);
    });
  });
}
