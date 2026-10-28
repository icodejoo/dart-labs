import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/orientation.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/report/report.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/ui_state.dart';

import '../support/fake_kernel.dart';

/// A VOD source shared by every case.
///
/// 各用例共用的点播源。
const _vod = MovaSource('https://host/a.mp4');

/// Lets pending stream deliveries and microtasks run.
///
/// 让挂起的流投递与微任务跑完。
Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// The verbs a host can still call after `dispose()`, each as a closure over [e].
///
/// 宿主在 `dispose()` 之后仍可能调用的动词，每个都是对 [e] 的闭包。
Map<String, Future<Object?> Function()> _verbsAfterDispose(MovaEngine e) => {
  'open': () => e.open(_vod),
  'play': e.play,
  'pause': e.pause,
  'playOrPause': e.playOrPause,
  'seek': () => e.seek(const Duration(seconds: 5)),
  'seekBy': () => e.seekBy(const Duration(seconds: 5)),
  'setVolume': () => e.setVolume(40),
  'setBrightness': () => e.setBrightness(0.5),
  'setRate': () => e.setRate(2),
  'setFit': () => e.setFit(MovaFit.cover),
  'setZoom': () => e.setZoom(2),
  'setLocked': () => e.setLocked(true),
  'setFullscreen': () => e.setFullscreen(true),
  'setOrientation': () => e.setOrientation(MovaOrientation.landscape),
  'loadQualities': e.loadQualities,
  'switchQuality': () => e.switchQuality(const MovaQuality(label: 'x', uri: 'https://host/x.m3u8')),
  'reload': e.reload,
  'backToLiveEdge': e.backToLiveEdge,
  'showControls': () async => e.showControls(),
  'hideControls': () async => e.hideControls(),
  'showHud': () async => e.showHud(MovaHud.volume),
  'setDragging': () async => e.setDragging(true),
  'report': () async => e.report(MovaReportName.play),
  'setMini': () => e.setMini(true),
  'enterPip': e.enterPip,
  'setKeepAlive': () => e.setKeepAlive(true),
  'setWarmMute': () => e.setWarmMute(true),
  'downshiftQuality': e.downshiftQuality,
};

void main() {
  group('A1 several subscribers see the same stream', () {
    test('events: two listeners receive the same sequence', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k);
      final a = <Type>[];
      final b = <Type>[];
      e.events.listen((x) => a.add(x.runtimeType));
      e.events.listen((x) => b.add(x.runtimeType));
      // Separate kernel streams give no cross-stream ordering, so settle each.
      // 内核的各条流之间没有跨流顺序保证，逐个落定。
      k.emitPlaying(true);
      await _flush();
      k.emitPlaying(false);
      await _flush();
      k.emitCompleted(true);
      await _flush();
      expect(a, [MovaPlay, MovaPause, MovaDone]);
      expect(b, a);
      await e.dispose();
    });

    test('states: two listeners both replay the current value and then follow', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k);
      final a = <bool>[];
      final b = <bool>[];
      e.states.listen((s) => a.add(s.playing));
      e.states.listen((s) => b.add(s.playing));
      k.emitPlaying(true);
      await _flush();
      expect(a, [false, true]);
      expect(b, a);
      await e.dispose();
    });

    test('a late states subscriber starts from the current value, not from history', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k);
      k.emitPlaying(true);
      await _flush();
      final late = <bool>[];
      e.states.listen((s) => late.add(s.playing));
      await _flush();
      expect(late, [true]);
      await e.dispose();
    });

    test('uiStates: two listeners receive the same visibility changes', () async {
      final e = MovaEngine(kernel: FakeKernel());
      final a = <bool>[];
      final b = <bool>[];
      e.uiStates.listen((s) => a.add(s.controlsVisible));
      e.uiStates.listen((s) => b.add(s.controlsVisible));
      e.hideControls();
      e.showControls(sticky: true);
      await _flush();
      expect(a, [true, false, true]);
      expect(b, a);
      await e.dispose();
    });

    test('progress: two listeners receive the same values and each position arrives in order', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k);
      await e.open(_vod);
      k.emitDuration(const Duration(minutes: 5));
      await _flush();
      final a = <Duration>[];
      final b = <Duration>[];
      e.progress.listen((p) => a.add(p.position));
      e.progress.listen((p) => b.add(p.position));
      for (final s in [1, 2, 3]) {
        k.emitPosition(Duration(seconds: s));
        // Longer than the 200ms throttle window so each one is delivered.
        // 比 200ms 的限流窗口长，让每一个都送达。
        await Future<void>.delayed(const Duration(milliseconds: 260));
      }
      expect(a, [const Duration(seconds: 1), const Duration(seconds: 2), const Duration(seconds: 3)]);
      expect(b, a);
      await e.dispose();
    });

    test('a subscriber that cancels does not disturb the others', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k);
      final kept = <Type>[];
      final dropped = <Type>[];
      e.events.listen((x) => kept.add(x.runtimeType));
      final sub = e.events.listen((x) => dropped.add(x.runtimeType));
      k.emitPlaying(true);
      await _flush();
      await sub.cancel();
      k.emitPlaying(false);
      await _flush();
      expect(kept, [MovaPlay, MovaPause]);
      expect(dropped, [MovaPlay]);
      await e.dispose();
    });
  });

  group('A23 dispose closes the streams', () {
    test('events, states, uiStates and progress all finish', () async {
      final e = MovaEngine(kernel: FakeKernel());
      final done = <String, Completer<void>>{
        for (final n in ['events', 'states', 'uiStates', 'progress']) n: Completer<void>(),
      };
      // Progress is throttled behind a lazily attached source; seed it first.
      // 进度流挂在惰性接入的源后面；先给它一个值。
      e.events.listen((_) {}, onDone: done['events']!.complete);
      e.states.listen((_) {}, onDone: done['states']!.complete);
      e.uiStates.listen((_) {}, onDone: done['uiStates']!.complete);
      e.progress.listen((_) {}, onDone: done['progress']!.complete);
      await e.dispose();
      for (final entry in done.entries) {
        await entry.value.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('${entry.key} never finished after dispose()'),
        );
      }
    });

    test('a subscriber that arrives after dispose gets done instead of hanging', () async {
      final e = MovaEngine(kernel: FakeKernel());
      await e.dispose();
      await expectLater(e.events, emitsDone);
      await expectLater(e.states, emitsThrough(emitsDone));
      await expectLater(e.uiStates, emitsThrough(emitsDone));
    });

    test('every verb is callable after dispose without throwing', () async {
      final e = MovaEngine(kernel: FakeKernel());
      await e.dispose();
      for (final entry in _verbsAfterDispose(e).entries) {
        await expectLater(
          entry.value(),
          completes,
          reason: '${entry.key}() threw after dispose()',
        );
      }
    });

    test('no event is produced by a verb called after dispose', () async {
      final e = MovaEngine(kernel: FakeKernel());
      final seen = <MovaEvent>[];
      e.events.listen(seen.add);
      await e.dispose();
      final before = seen.length;
      for (final call in _verbsAfterDispose(e).values) {
        await call();
      }
      await _flush();
      expect(seen.length, before);
    });

    test('a verb called after dispose never opens a new source on the kernel', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k);
      await e.dispose();
      await e.open(_vod);
      await e.reload();
      expect(k.openedUris, isEmpty);
    });

    // pause/setVolume/setRate etc. used to forward to the disposed kernel; a real
    // media_kit Player throws AssertionError('has been disposed') there.
    // pause/setVolume/setRate 等曾在 dispose 之后仍转发给已销毁的内核；真实 media_kit
    // Player 在那里会抛 AssertionError('has been disposed')。
    test('verbs called after dispose do not reach the disposed kernel', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k);
      await e.dispose();
      final before = k.calls.length;
      for (final call in _verbsAfterDispose(e).values) {
        await call();
      }
      expect(k.calls.sublist(before), isEmpty);
    });

    // One case per verb, over a kernel that throws like media_kit once disposed,
    // and one with the keepAlive capability so those verbs are checked as well.
    // 每个动词一条用例，内核销毁后像 media_kit 那样抛异常；另用带待机能力的内核，
    // 使待机相关动词一并被检查。
    final names = _verbsAfterDispose(MovaEngine(kernel: FakeKernel())).keys.toList();
    for (final name in names) {
      test('$name() after dispose never touches the kernel (and does not throw)', () async {
        final k = FakeKeepAliveKernel()..throwWhenDisposed = true;
        final e = MovaEngine(kernel: k);
        await e.dispose();
        await _verbsAfterDispose(e)[name]!();
        await _flush();
        expect(k.callsAfterDispose, isEmpty);
      });
    }

    test('a switchQuality whose kernel load outlives dispose() issues nothing afterwards', () async {
      final k = FakeKernel()..throwWhenDisposed = true;
      final e = MovaEngine(kernel: k);
      await e.open(_vod);
      k.emitDuration(const Duration(minutes: 5));
      k.emitPosition(const Duration(seconds: 30));
      await _flush();
      const high = MovaQuality(label: '1080p', uri: 'https://host/1080.m3u8', height: 1080);
      const low = MovaQuality(label: '480p', uri: 'https://host/480.m3u8', height: 480);
      e.debugSetQualities(const [high, low], current: high);
      k.openGate = Completer<void>();
      final switching = e.switchQuality(low);
      await _flush();
      await e.dispose();
      k.openGate!.complete();
      await expectLater(switching, completes);
      await _flush();
      expect(k.callsAfterDispose, isEmpty);
    });

    test('a play() that was queued behind a keepAlive request does not outlive dispose()', () async {
      final k = FakeKeepAliveKernel()..throwWhenDisposed = true;
      final e = MovaEngine(kernel: k);
      await e.open(_vod);
      final request = e.setKeepAlive(true);
      final playing = e.play();
      await e.dispose();
      await expectLater(Future.wait<Object?>([request, playing]), completes);
      await _flush();
      expect(k.callsAfterDispose, isEmpty);
    });
  });

  group('MovaProg value type', () {
    test('progress carries the buffer the kernel last reported', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k);
      await e.open(_vod);
      k.emitDuration(const Duration(minutes: 5));
      await _flush();
      final seen = <MovaProg>[];
      e.progress.listen(seen.add);
      k.emitBuffer(const Duration(seconds: 20));
      await _flush();
      expect(seen.last.buffer, const Duration(seconds: 20));
      await e.dispose();
    });
  });
}
