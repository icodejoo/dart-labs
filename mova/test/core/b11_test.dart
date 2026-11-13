import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';

/// B11 的拒绝、失败恢复、完整规格与在途绑定回归。
void main() {
  test('拒绝 open 撤销复用播放器的绑定，不 ready、不播放旧素材', () async {
    final api = FakeMovaApi();
    final pool = MovaFeedPool(movaFactory: () => api, size: 1);
    addTearDown(pool.dispose);
    await pool.bind(0, const MovaSource('old'));
    api.acceptOpens = false;
    api.calls.clear();
    await pool.bind(1, const MovaSource('new'), autoPlay: true);
    expect(pool.slotFor(0), isNull);
    expect(pool.slotFor(1), isNull);
    await pool.focus(1);
    expect(api.calls, isNot(contains('play')));
    expect(api.calls, contains('pause'));
    expect(pool.movaCount, 1);
  });
  test('首次 open 抛错撤销绑定，同源重试复用原播放器成功', () async {
    final api = FakeMovaApi()
      ..openThrows = StateError('open')
      ..openThrowsOnce = true;
    var creates = 0;
    final pool = MovaFeedPool(
      movaFactory: () {
        creates++;
        return api;
      },
    );
    addTearDown(pool.dispose);
    await expectLater(pool.bind(0, const MovaSource('a')), throwsStateError);
    expect(pool.slotFor(0), isNull);
    await pool.bind(0, const MovaSource('a'));
    expect(pool.slotFor(0)?.ready, isTrue);
    expect(creates, 1);
    expect(api.openCalls, 2);
  });
  test('同 URL 修改 mpv、demuxer、类型或备选源均重新打开', () async {
    final api = FakeMovaApi();
    final pool = MovaFeedPool(movaFactory: () => api, size: 1);
    addTearDown(pool.dispose);
    final sources = [
      const MovaSource('a'),
      const MovaSource('a', mpvOptions: {'cache': 'no'}),
      const MovaSource(
        'a',
        mpvOptions: {'cache': 'no'},
        demuxerOptions: {'x': 'y'},
      ),
      const MovaSource('a', type: MovaStreamType.live),
      const MovaSource('a', alternatives: ['b']),
    ];
    for (final source in sources) {
      await pool.bind(0, source);
    }
    expect(api.openCalls, sources.length);
    expect(pool.slotFor(0)?.ready, isTrue);
  });
  test('sameAs 相同仅元数据变化时复用，不重新 open', () async {
    final api = FakeMovaApi();
    final pool = MovaFeedPool(movaFactory: () => api);
    addTearDown(pool.dispose);
    await pool.bind(
      0,
      const MovaSource('a', title: 'first', mpvOptions: {'cache': 'no'}),
    );
    await pool.bind(
      0,
      const MovaSource('a', title: 'second', mpvOptions: {'cache': 'no'}),
      autoPlay: true,
    );
    expect(api.openCalls, 1);
    expect(api.calls.where((call) => call == 'play'), hasLength(1));
  });
  test('重复绑定在途同源必须等接受结果，focus 不提前播放', () async {
    for (final accepted in [true, false]) {
      final gate = Completer<void>();
      final api = FakeMovaApi()
        ..openGate = gate
        ..acceptOpens = accepted;
      final pool = MovaFeedPool(movaFactory: () => api);
      final first = pool.bind(0, const MovaSource('a'));
      var settled = false;
      final repeated = pool
          .bind(0, const MovaSource('a'), autoPlay: true)
          .then((_) => settled = true);
      await pool.focus(0);
      expect(settled, isFalse);
      expect(api.calls, isNot(contains('play')));
      gate.complete();
      await Future.wait([first, repeated]);
      expect(api.openCalls, 1);
      expect(pool.slotFor(0)?.ready, accepted ? isTrue : isNull);
      expect(
        api.calls.where((call) => call == 'play'),
        hasLength(accepted ? 1 : 0),
      );
      await pool.dispose();
    }
  });
  test('旧绑定迟到的拒绝或异常不撤销、不暂停已替换的新绑定', () async {
    for (final throws in [false, true]) {
      final gate = Completer<void>();
      final api = FakeMovaApi()..openGate = gate;
      final pool = MovaFeedPool(movaFactory: () => api, size: 1);
      final stale = pool.bind(0, const MovaSource('old'));
      final checked = expectLater(stale, throws ? throwsStateError : completes);
      api.openGate = null;
      await pool.bind(0, const MovaSource('new'));
      api.calls.clear();
      if (throws) {
        api.openThrows = StateError('late');
      } else {
        api.acceptOpens = false;
      }
      gate.complete();
      await checked;
      expect(pool.slotFor(0)?.ready, isTrue);
      expect(api.calls, isNot(contains('pause')));
      await pool.dispose();
    }
  });
}
