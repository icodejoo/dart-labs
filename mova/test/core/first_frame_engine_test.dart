import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/render/first_frame.dart';

import '../support/fake_kernel.dart';

/// Small harness: an engine over [kernel] plus a recorder for first-frame events.
///
/// 小型夹具：基于 [kernel] 的引擎，加一个首帧事件记录器。
class _Rig {
  _Rig(this.kernel) : engine = MovaEngine(kernel: kernel) {
    engine.events.listen((e) {
      if (e is MovaFirstFrame) frames.add(e);
    });
  }

  final FakeKernel kernel;
  final MovaEngine engine;
  final List<MovaFirstFrame> frames = [];

  void open(FakeAsync async, {bool autoPlay = true, String uri = 'https://h/a.mp4'}) {
    engine.open(MovaSource(uri), autoPlay: autoPlay);
    async.flushMicrotasks();
  }
}

void main() {
  test('open() zeroes rendered and the previous source frame size', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      k.emitSize(1280, 720);
      async.flushMicrotasks();
      expect(r.engine.state.width, 1280);
      r.open(async);
      expect(r.engine.state.rendered, isFalse);
      expect(r.engine.state.width, 0);
      expect(r.engine.state.height, 0);
    });
  });

  test('native restart lands rendered with exactly one MovaFirstFrame', () {
    fakeAsync((async) {
      final k = FakeStatsKernel()..nativeRestartAvailable = true;
      final r = _Rig(k);
      r.open(async);
      k.emitRestart();
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isTrue);
      expect(r.frames, hasLength(1));
      expect(r.frames.single.signal, MovaFirstFrameSignal.restart);
      expect(r.frames.single.sinceOpen, greaterThanOrEqualTo(Duration.zero));
    });
  });

  test('native live: buffering edge alone waits, then grace lands after 1500ms', () {
    fakeAsync((async) {
      final k = FakeStatsKernel()..nativeRestartAvailable = true;
      final r = _Rig(k);
      r.open(async);
      k.emitBuffering(true);
      k.emitBuffering(false);
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isFalse);
      async.elapse(const Duration(milliseconds: 1499));
      expect(r.engine.state.rendered, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isTrue);
      expect(r.frames.single.signal, MovaFirstFrameSignal.grace);
    });
  });

  test('native live: restart within the grace window wins and no second event follows', () {
    fakeAsync((async) {
      final k = FakeStatsKernel()..nativeRestartAvailable = true;
      final r = _Rig(k);
      r.open(async);
      k.emitBuffering(true);
      k.emitBuffering(false);
      async.elapse(const Duration(milliseconds: 500));
      k.emitRestart();
      async.flushMicrotasks();
      expect(r.frames.single.signal, MovaFirstFrameSignal.restart);
      async.elapse(const Duration(milliseconds: 1500));
      async.flushMicrotasks();
      expect(r.frames, hasLength(1));
    });
  });

  test('plain kernel: buffering true to false lands as buffering', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      r.open(async);
      k.emitBuffering(true);
      k.emitBuffering(false);
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isTrue);
      expect(r.frames.single.signal, MovaFirstFrameSignal.buffering);
    });
  });

  test('only an initial buffering=false does not render', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      r.open(async);
      k.emitBuffering(false);
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isFalse);
      expect(r.frames, isEmpty);
    });
  });

  test('two increasing positions land as progress', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      r.open(async);
      k.emitPosition(const Duration(milliseconds: 40));
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isFalse);
      k.emitPosition(const Duration(milliseconds: 80));
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isTrue);
      expect(r.frames.single.signal, MovaFirstFrameSignal.progress);
    });
  });

  test('size lands only for a paused open', () {
    fakeAsync((async) {
      final paused = _Rig(FakeKernel());
      paused.open(async, autoPlay: false);
      paused.kernel.emitSize(1280, 720);
      async.flushMicrotasks();
      expect(paused.engine.state.rendered, isTrue);
      expect(paused.frames.single.signal, MovaFirstFrameSignal.size);

      final playing = _Rig(FakeKernel());
      playing.open(async);
      playing.kernel.emitSize(1280, 720);
      async.flushMicrotasks();
      expect(playing.engine.state.rendered, isFalse);
    });
  });

  test('a second open() resets rendered and fires a second MovaFirstFrame', () {
    fakeAsync((async) {
      final k = FakeStatsKernel();
      final r = _Rig(k);
      r.open(async);
      k.emitRestart();
      async.flushMicrotasks();
      expect(r.frames, hasLength(1));
      r.open(async, uri: 'https://h/b.mp4');
      expect(r.engine.state.rendered, isFalse);
      k.emitRestart();
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isTrue);
      expect(r.frames, hasLength(2));
    });
  });

  test('observations are dropped while the kernel open() is in flight', () {
    fakeAsync((async) {
      final k = FakeStatsKernel();
      k.openGate = Completer<void>();
      final r = _Rig(k);
      r.open(async);
      k.emitRestart();
      k.emitBuffering(true);
      k.emitBuffering(false);
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isFalse);
      k.openGate!.complete();
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isFalse);
      k.emitRestart();
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isTrue);
    });
  });

  test('switchQuality keeps rendered and fires no new MovaFirstFrame', () {
    fakeAsync((async) {
      final k = FakeStatsKernel();
      final r = _Rig(k);
      r.open(async);
      k.emitRestart();
      async.flushMicrotasks();
      expect(r.frames, hasLength(1));
      r.engine.switchQuality(const MovaQuality(label: '720p', uri: 'https://h/720.m3u8'));
      async.flushMicrotasks();
      k.emitRestart();
      async.flushMicrotasks();
      expect(r.engine.state.rendered, isTrue);
      expect(r.frames, hasLength(1));
    });
  });

  test('dispose() during the grace window leaves no grace timer and emits nothing', () {
    fakeAsync((async) {
      final k = FakeStatsKernel()..nativeRestartAvailable = true;
      final r = _Rig(k);
      r.open(async);
      k.emitBuffering(true);
      k.emitBuffering(false);
      async.flushMicrotasks();
      r.engine.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers.where((t) => t.duration == const Duration(milliseconds: 1500)), isEmpty);
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(r.frames, isEmpty);
    });
  });
}
