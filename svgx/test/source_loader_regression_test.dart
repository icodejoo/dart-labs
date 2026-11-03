import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/svg_source_loader.dart';

class ImmediateBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(0);
  @override
  Future<String> loadString(String key, {bool cache = true}) async => 'asset';
}

void main() {
  tearDown(SvgSourceLoader.instance.clear);
  for (final oldFinishesFirst in [true, false]) {
    test(
      'clear invalidates in-flight loads (old first: $oldFinishesFirst)',
      () async {
        final loader = SvgSourceLoader.instance;
        final bundle = PendingBundle();
        final old = loader.asset('same.svg', bundle: bundle);
        loader.clear();
        final fresh = loader.asset('same.svg', bundle: bundle);
        expect(bundle.loads, hasLength(2));
        if (oldFinishesFirst) {
          bundle.loads[0].complete('old');
          expect(await old, 'old');
          final joined = loader.asset('same.svg', bundle: bundle);
          expect(bundle.loads, hasLength(2));
          bundle.loads[1].complete('fresh');
          expect(await joined, 'fresh');
        } else {
          bundle.loads[1].complete('fresh');
          expect(await fresh, 'fresh');
          bundle.loads[0].complete('old');
          expect(await old, 'old');
        }
        expect(await fresh, 'fresh');
        expect(await loader.asset('same.svg', bundle: bundle), 'fresh');
      },
    );
  }
  test(
    'network keys include headers by value and merge simultaneous requests',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var count = 0;
      server.listen((request) {
        count++;
        request.response.write(request.headers.value('x-user'));
        unawaited(request.response.close());
      });
      final url = 'http://127.0.0.1:${server.port}/a';
      try {
        final loader = SvgSourceLoader.instance;
        final values = await Future.wait([
          loader.network(url, headers: {'x-user': 'a', 'x-other': '1'}),
          loader.network(url, headers: {'x-other': '1', 'x-user': 'a'}),
          loader.network(url, headers: {'x-user': 'b'}),
        ]);
        expect(values, ['a', 'a', 'b']);
        expect(count, 2);
        expect(await loader.network(url, headers: {'x-user': 'b'}), 'b');
        expect(count, 2);
        expect(await loader.asset(url, bundle: ImmediateBundle()), 'asset');
      } finally {
        await server.close(force: true);
      }
    },
  );
  test('file and asset namespaces do not collide', () async {
    final dir = await Directory.systemTemp.createTemp('svgx-loader');
    final file = File('${dir.path}/source.svg');
    await file.writeAsString('file');
    try {
      final loader = SvgSourceLoader.instance;
      expect(await loader.asset(file.path, bundle: ImmediateBundle()), 'asset');
      expect(await loader.file(file), 'file');
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'malformed UTF8 is a catchable future error and failed requests can retry',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var count = 0;
      server.listen((request) {
        count++;
        request.response.add(count == 1 ? [0xff] : [65]);
        unawaited(request.response.close());
      });
      final url = 'http://127.0.0.1:${server.port}/utf8';
      try {
        await expectLater(
          SvgSourceLoader.instance.network(url),
          throwsFormatException,
        );
        expect(await SvgSourceLoader.instance.network(url), 'A');
      } finally {
        await server.close(force: true);
      }
    },
  );
}

class PendingBundle extends ImmediateBundle {
  final loads = <Completer<String>>[];
  @override
  Future<String> loadString(String key, {bool cache = true}) {
    final result = Completer<String>();
    loads.add(result);
    return result.future;
  }
}
