import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_kernel.dart';
import '../../support/gated.dart';

/// 排空流与钩子微任务。
void _settle(FakeAsync clock) => clock.flushMicrotasks();

void main() {
  for (final failed in [false, true]) {
    for (final action in ['pause', 'replace']) {
      test('A07 ${failed ? "reopen" : "edge"} permits $action during network', () {
        fakeAsync((clock) {
          final k = FakeKeepAliveKernel();
          final e = createMovaEngine(
            kernel: k,
            pip: MovaNoopPipPort(),
            orientation: MovaNoopOrientationPort(),
            brightness: MovaFallbackBrightnessPort(),
            options: const MovaOpts(controls: MovaCtrlsConfig(autoHide: false)),
          );
          final origin = DateTime(2026);
          e.debugClock = () => origin.add(clock.elapsed);
          final events = <MovaEvent>[];
          e.events.listen(events.add);
          e.open(const MovaSource('https://h/a.flv', type: MovaStreamType.live));
          _settle(clock);
          k.emitPlaying(true);
          e.setKeepAlive(true);
          _settle(clock);
          if (failed) {
            k.emitCompleted(true);
            _settle(clock);
          } else {
            clock.elapse(const Duration(seconds: 30));
            _settle(clock);
          }
          expect(e.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
          k.emitPlaying(false);
          _settle(clock);
          final gate = k.openGate = Completer<void>();
          final log = CommandLog();
          e.setKeepAlive(false).then((phase) {
            expect(phase, MovaKeepAlivePhase.resuming);
            log.record(0, 'wake returned');
          });
          _settle(clock);
          expect(log.entries.single.verb, 'wake returned');
          expect(gate.isCompleted, isFalse);
          if (action == 'pause') {
            e.pause().then((_) => log.record(0, 'paused'));
          } else {
            k.openGate = null;
            e.setKeepAlive(true);
            e.open(const MovaSource('https://h/new.flv', type: MovaStreamType.live))
                .then((_) => log.record(0, 'replaced'));
          }
          _settle(clock);
          expect(log.entries, hasLength(2), reason: 'network must not block the queue');
          final plays = k.calls.where((v) => v == 'play').length;
          final edgeEvents = events.whereType<MovaLiveEdgeReach>().length;
          gate.complete();
          _settle(clock);
          expect(k.calls.where((v) => v == 'play').length, plays);
          if (action == 'replace') {
            expect(events.whereType<MovaLiveEdgeReach>().length, edgeEvents);
            expect(k.lastUri, 'https://h/new.flv');
          } else {
            expect(e.state.playbackIntent, isFalse);
            expect(e.state.keepAlivePhase, MovaKeepAlivePhase.off);
          }
          e.dispose();
          _settle(clock);
        });
      });
    }
  }

  test('A07 disposed wake has no late play or edge event', () {
    fakeAsync((clock) {
      final k = FakeKeepAliveKernel();
      final e = createMovaEngine(
        kernel: k,
        pip: MovaNoopPipPort(),
        orientation: MovaNoopOrientationPort(),
        brightness: MovaFallbackBrightnessPort(),
        options: const MovaOpts(controls: MovaCtrlsConfig(autoHide: false)),
      );
      final origin = DateTime(2026);
      e.debugClock = () => origin.add(clock.elapsed);
      e.open(const MovaSource('https://h/a.flv', type: MovaStreamType.live));
      _settle(clock);
      k.emitPlaying(true);
      e.setKeepAlive(true);
      _settle(clock);
      clock.elapse(const Duration(seconds: 30));
      final gate = k.openGate = Completer<void>();
      e.setKeepAlive(false);
      _settle(clock);
      e.dispose();
      _settle(clock);
      gate.complete();
      _settle(clock);
      expect(k.callsAfterDispose, isEmpty);
    });
  });
}

