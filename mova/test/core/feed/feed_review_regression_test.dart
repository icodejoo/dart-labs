import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_api.dart';
import '../cutover/cutover_operation_test.dart' show settleOperations;

/// Exercises activation failures and the network prefetch byte budget.
///
/// 验证激活失败恢复与网络预取字节预算。
void main() {
  test('coreA10 failed adjacent activation silences the retained old page', () async {
    final movas = <FakeMovaApi>[];
    final pool = MovaFeedPool(size: 3, movaFactory: () {
      final api = FakeMovaApi()..pushPlayingOnVerbs = true;
      movas.add(api);
      return api;
    });
    final feed = MovaFeed(
      pool: pool,
      prefetchDepth: 1,
      loader: (index) async => MovaFeedItem(source: MovaSource('$index')),
    );
    addTearDown(() async {
      feed.dispose();
      await pool.dispose();
    });
    await feed.activate(0);
    await settleOperations();
    final old = pool.slotFor(0)!.api as FakeMovaApi;
    expect(old.state.playing, isTrue);
    final next = pool.slotFor(1)!.api as FakeMovaApi;
    next.openThrows = StateError('next page failed');
    // Force a fresh binding so the adjacent page fails at open, not at play.
    //
    // 强制重新绑定，使相邻页在 open 处失败，而非在 play 处失败。
    pool.retain({0, 2});
    for (final mova in movas.where((mova) => !identical(mova, old))) {
      mova.openThrows = StateError('next page failed');
    }
    await expectLater(feed.activate(1), throwsStateError);
    expect(feed.activeIndex, 1);
    expect(pool.slotFor(0)?.api, same(old));
    expect(old.state.playbackIntent, isFalse);
    expect(old.state.playing, isFalse);
  });

  for (final failAt in ['loader', 'bind']) {
    test('C12 stale $failAt failure still activates the latest page', () async {
      final gate = Completer<void>();
      final movas = <FakeMovaApi>[];
      final pool = MovaFeedPool(
        size: 1,
        movaFactory: () {
          final api = FakeMovaApi();
          if (failAt == 'bind') {
            api.openGate = gate;
            api.openThrows = StateError('stale bind');
            api.openThrowsFor = '0';
            api.openThrowsOnce = true;
          }
          movas.add(api);
          return api;
        },
      );
      final feed = MovaFeed(
        pool: pool,
        prefetchDepth: 0,
        loader: (index) async {
          if (index == 0 && failAt == 'loader') {
            await gate.future;
            throw StateError('stale loader');
          }
          return MovaFeedItem(source: MovaSource('$index'));
        },
      );
      addTearDown(() async {
        feed.dispose();
        await pool.dispose();
      });
      final first = feed.activate(0);
      await settleOperations();
      final latest = feed.activate(1);
      gate.complete();
      await Future.wait([first, latest]);
      expect(feed.activeIndex, 1);
      expect(pool.slotFor(1)?.api, same(movas.last));
      expect(movas.last.source?.uri, '1');
      expect(movas.last.state.playbackIntent, isTrue);
    });
  }

  test(
    'C12 latest activation failure is returned and a later request can retry',
    () async {
      var fail = true;
      final pool = MovaFeedPool(size: 1, movaFactory: FakeMovaApi.new);
      final feed = MovaFeed(
        pool: pool,
        prefetchDepth: 0,
        loader: (index) async {
          if (fail) throw StateError('latest loader');
          return MovaFeedItem(source: MovaSource('$index'));
        },
      );
      addTearDown(() async {
        feed.dispose();
        await pool.dispose();
      });
      await expectLater(feed.activate(0), throwsStateError);
      fail = false;
      await feed.activate(1);
      expect(feed.activeIndex, 1);
      expect(pool.slotFor(1), isNotNull);
    },
  );

  for (final status in [HttpStatus.ok, HttpStatus.partialContent]) {
    test(
      'C15 status $status stops at the byte budget before response EOF',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final responseReady = Completer<HttpResponse>();
        server.listen((request) async {
          final response = request.response;
          response.statusCode = status;
          response.bufferOutput = false;
          response.add(List<int>.filled(2048, 1));
          await response.flush();
          responseReady.complete(response);
        });
        addTearDown(() => server.close(force: true));
        const prefetcher = MovaNetworkWarmFeedPrefetcher(
          rangeBytes: 1024,
          timeout: Duration(seconds: 10),
        );
        await prefetcher
            .prime(MovaSource('http://127.0.0.1:${server.port}/video'))
            .timeout(const Duration(seconds: 2));
        final response = await responseReady.future;
        await response.close();
      },
    );
  }
}
