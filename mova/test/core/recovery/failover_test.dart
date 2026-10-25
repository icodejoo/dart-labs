import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/recovery/fail.dart';

import '../../support/fake_kernel.dart';

const _a = 'https://h/a.m3u8';
const _b = 'https://h/b.m3u8';
const _c = 'https://h/c.m3u8';

/// An engine over [kernel] that fails over without retrying; control-bar
/// auto-hide is off so only recovery timers can be pending.
///
/// 基于 [kernel]、只切换不重试的引擎；关掉控制条自动隐藏，使挂起计时器只可能来自
/// recovery。
class _Rig {
  _Rig(this.kernel, {bool enabled = true, MovaLiveConfig live = const MovaLiveConfig()})
      : engine = MovaEngine(
          kernel: kernel,
          options: MovaOpts(
            recovery: MovaRecoveryConfig(enabled: enabled, policy: const MovaFailoverOnly()),
            controls: const MovaCtrlsConfig(autoHide: false),
            live: live,
          ),
        ) {
    engine.events.listen(events.add);
  }

  final FakeKernel kernel;
  final MovaEngine engine;
  final List<MovaEvent> events = [];

  void open(FakeAsync async, MovaSource src) {
    engine.open(src);
    async.flushMicrotasks();
  }
}

void main() {
  const tenSeconds = Duration(seconds: 10);

  test('start timeout on the primary fails over to the alternative and says so', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      r.open(async, const MovaSource(_a, alternatives: [_b]));
      expect(r.engine.state.sourceIndex, 0);
      async.elapse(tenSeconds);
      expect(k.openedUris, [_a, _b]);
      expect(r.engine.state.sourceIndex, 1);
      final f = r.events.whereType<MovaFailover>().single;
      expect((f.from, f.to, f.uri), (0, 1, _b));
      expect(r.events.whereType<MovaPlayFailure>().single.action, MovaRecoveryAction.failover);
    });
  });

  test('switching address clears the quality list that belonged to the old master playlist', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      r.open(async, const MovaSource(_a, alternatives: [_b]));
      r.engine.debugSetQualities(
        [MovaQuality.auto(), const MovaQuality(label: '720p', uri: 'https://h/720.m3u8')],
        current: MovaQuality.auto(),
      );
      expect(r.engine.state.qualities, isNotEmpty);
      async.elapse(tenSeconds);
      expect(r.engine.state.qualities, isEmpty);
      expect(r.engine.state.currentQuality, isNull);
    });
  });

  test('after failing over, back-to-live (reopen) opens the alternative, not the primary', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k, live: const MovaLiveConfig(backToLive: MovaBackToLive.reopen));
      r.open(async, const MovaSource(_a, type: MovaStreamType.live, alternatives: [_b]));
      async.elapse(tenSeconds);
      expect(r.engine.state.sourceIndex, 1);
      r.engine.backToLiveEdge();
      async.flushMicrotasks();
      expect(k.openedUris.last, _b);
    });
  });

  test('switchQuality(auto) reloads the alternative address', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      r.open(async, const MovaSource(_a, alternatives: [_b]));
      async.elapse(tenSeconds);
      r.engine.switchQuality(MovaQuality.auto());
      async.flushMicrotasks();
      expect(k.openedUris.last, _b);
    });
  });

  test('a new open() starts back at the primary address', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      r.open(async, const MovaSource(_a, alternatives: [_b]));
      async.elapse(tenSeconds);
      expect(r.engine.state.sourceIndex, 1);
      r.open(async, const MovaSource(_a, alternatives: [_b]));
      expect(r.engine.state.sourceIndex, 0);
      expect(k.openedUris.last, _a);
    });
  });

  test('recovery disabled: alternatives are never used, however long we wait', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k, enabled: false);
      r.open(async, const MovaSource(_a, alternatives: [_b]));
      async.elapse(const Duration(minutes: 10));
      expect(k.openedUris, [_a]);
      expect(r.engine.state.sourceIndex, 0);
      expect(r.events.whereType<MovaFailover>(), isEmpty);
    });
  });

  test('the last alternative failing too gives up, and the error names the last index', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      r.open(async, const MovaSource(_a, alternatives: [_b, _c]));
      async.elapse(tenSeconds * 3);
      expect(k.openedUris, [_a, _b, _c]);
      final err = r.engine.state.error;
      expect(err, isA<MovaGiveUpError>());
      expect((err as MovaGiveUpError).last.sourceIndex, 2);
      expect(err.last.uri, _c);
      expect(r.events.whereType<MovaPlayFailure>().last.action, MovaRecoveryAction.giveUp);
    });
  });
}
