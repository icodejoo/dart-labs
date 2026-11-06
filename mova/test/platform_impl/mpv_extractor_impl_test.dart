import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/platform_impl/mpv_extractor_impl.dart';

/// Provides ready media properties without a native player.
///
/// 无需原生播放器即可提供就绪的媒体属性。
class _Native extends Fake implements NativePlayer {
  Duration position = Duration.zero;

  /// Accepts extraction settings.
  ///
  /// 接受抽帧设置。
  @override
  Future<void> setProperty(
    String name,
    String value, {
    bool waitForInitialization = true,
  }) async {}

  /// Reports duration and the last seek position.
  ///
  /// 报告时长与上次 seek 位置。
  @override
  Future<String> getProperty(
    String name, {
    bool waitForInitialization = true,
  }) async => switch (name) {
    'duration' => '60',
    'seeking' => 'no',
    'time-pos' => '${position.inMilliseconds / 1000}',
    _ => '',
  };
}

/// Records opens and optionally holds an in-flight open.
///
/// 记录打开操作，并可暂停在途的打开操作。
class _Player extends Fake implements Player {
  final native = _Native();
  final opened = Completer<void>();
  final uris = <String>[];
  Completer<void>? openGate;
  int disposals = 0;

  /// Exposes the fake native property interface.
  ///
  /// 暴露原生属性替身接口。
  @override
  NativePlayer get platform => native;

  /// Records the requested media before waiting for the optional gate.
  ///
  /// 记录媒体请求，再等待可选闸门。
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    uris.add((playable as Media).uri);
    if (!opened.isCompleted) opened.complete();
    await openGate?.future;
  }

  /// Makes the requested position immediately observable.
  ///
  /// 让请求位置立即可读。
  @override
  Future<void> seek(Duration position) async => native.position = position;

  /// Returns a distinguishable frame.
  ///
  /// 返回可辨识的帧。
  @override
  Future<Uint8List?> screenshot({
    String? format = 'image/jpeg',
    bool includeLibassSubtitles = true,
  }) async => Uint8List.fromList([42]);

  /// Records native disposal.
  ///
  /// 记录原生资源释放。
  @override
  Future<void> dispose() async => disposals++;
}

/// Verifies request generations across reusable releases.
///
/// 验证可复用释放前后的请求代际。
void main() {
  test(
    'release cancels queued extraction before player creation / release 取消尚未建播放器的抽帧',
    () async {
      final players = <_Player>[];
      final extractor = MovaFrameExtractor(
        settleDelay: Duration.zero,
        playerFactory: () {
          final player = _Player();
          players.add(player);
          return player;
        },
      );
      addTearDown(extractor.dispose);
      final stale = extractor.extract(
        'https://h/old',
        Duration.zero,
        width: 100,
        hwdec: false,
      );
      await extractor.release();
      expect(await stale, isNull);
      expect(players, isEmpty);
      expect(
        await extractor.extractWithHeaders(
          'https://h/new',
          Duration.zero,
          width: 100,
          hwdec: false,
          headers: const {},
        ),
        [42],
      );
      expect(players.single.uris, ['https://h/new']);
    },
  );

  test(
    'release cancels requests behind active extraction and allows fresh work / release 取消在途操作后的旧队列并允许新请求',
    () async {
      final first = _Player()..openGate = Completer<void>();
      final next = _Player();
      var creates = 0;
      final extractor = MovaFrameExtractor(
        settleDelay: Duration.zero,
        playerFactory: () => creates++ == 0 ? first : next,
      );
      addTearDown(extractor.dispose);
      final active = extractor.extract(
        'https://h/active',
        Duration.zero,
        width: 100,
        hwdec: false,
      );
      await first.opened.future;
      final queued = extractor.extractWithHeaders(
        'https://h/stale',
        Duration.zero,
        width: 100,
        hwdec: false,
        headers: const {'Authorization': 'old'},
      );
      await extractor.release();
      final fresh = extractor.extract(
        'https://h/fresh',
        Duration.zero,
        width: 100,
        hwdec: false,
      );
      first.openGate!.complete();
      expect(await active, isNull);
      expect(await queued, isNull);
      expect(await fresh, [42]);
      expect(first.disposals, 1);
      expect(next.uris, ['https://h/fresh']);
      expect(creates, 2);
    },
  );
}
