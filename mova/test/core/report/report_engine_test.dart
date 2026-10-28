import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/interceptor/interceptor.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/report/report.dart';

import '../../support/fake_kernel.dart';

void main() {
  group('MovaEngine reporter wiring', () {
    test('reporter: null (default) — no report is ever produced, zero behavior change', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k);
      // report() itself must be a safe no-op with no reporter attached.
      e.report(MovaReportName.play);
      k.emitPlaying(true);
      await Future<void>.delayed(Duration.zero);
      // Nothing to assert on the reporter side — just that this doesn't throw
      // and playback state still flows normally.
      expect(e.state.playing, isTrue);
      await e.dispose();
    });

    test('whitelisted MovaEvents reach the reporter via events, auto-translated', () async {
      final k = FakeKernel();
      final received = <MovaReportEvent>[];
      final e = MovaEngine(kernel: k, reporter: MovaCallbackReporter(received.add));

      await e.open(const MovaSource('https://host/a.mp4'));
      k.emitPlaying(true);
      k.emitPlaying(false);
      k.emitCompleted(true);
      await Future<void>.delayed(Duration.zero);

      final names = received.map((r) => r.name).toList();
      expect(names, contains(MovaReportName.sourceChange));
      expect(names, contains(MovaReportName.play));
      expect(names, contains(MovaReportName.pause));
      expect(names, contains(MovaReportName.done));
      await e.dispose();
    });

    test('non-whitelisted events (e.g. buffering flap) never reach the reporter', () async {
      final k = FakeKernel();
      final received = <MovaReportEvent>[];
      final e = MovaEngine(kernel: k, reporter: MovaCallbackReporter(received.add));

      k.emitBuffering(true);
      k.emitBuffering(false);
      k.emitBuffering(true);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await e.dispose();
    });

    test('report() forwards a MovaReportKind.action event with the given name/params', () async {
      final k = FakeKernel();
      final received = <MovaReportEvent>[];
      final e = MovaEngine(kernel: k, reporter: MovaCallbackReporter(received.add));

      e.report(MovaReportName.qualityChange, params: {'via': 'settingsPanel'});

      expect(received, hasLength(1));
      expect(received.single.kind, MovaReportKind.action);
      expect(received.single.name, MovaReportName.qualityChange);
      expect(received.single.params['via'], 'settingsPanel');
      expect(received.single.priority, MovaReportPriority.batched);
      await e.dispose();
    });

    test('dispose() cancels the report translator without throwing', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k, reporter: MovaCallbackReporter((_) {}));
      await e.dispose();
      // A second dispose-adjacent no-op call must not throw post-dispose.
      expect(() => e.report(MovaReportName.play), returnsNormally);
    });
  });

  group('host reporter that throws', () {
    test('collector path: playback keeps flowing, later reports still arrive, hooks are told', () async {
      final k = FakeKernel();
      final hook = _ErrorSpyHook();
      final received = <MovaReportEvent>[];
      var calls = 0;
      final e = MovaEngine(
        kernel: k,
        interceptors: [hook],
        reporter: MovaCallbackReporter((ev) {
          calls++;
          // Only the first delivery blows up; the rest must still get through.
          // 只有第一次投递抛异常，其余必须照常送达。
          if (calls == 1) throw StateError('host reporter bug');
          received.add(ev);
        }),
      );
      k.emitPlaying(true);
      await Future<void>.delayed(Duration.zero);
      k.emitPlaying(false);
      await Future<void>.delayed(Duration.zero);
      // Engine state flowed regardless of the throwing reporter.
      // 无论上报回调是否抛异常，引擎状态照常流转。
      expect(e.state.playing, isFalse);
      expect(received.map((r) => r.name), contains(MovaReportName.pause));
      expect(hook.errors.whereType<StateError>(), hasLength(1));
      await e.dispose();
    });

    test('report() path: a throwing reporter neither throws nor blocks the next report', () async {
      final hook = _ErrorSpyHook();
      final received = <MovaReportEvent>[];
      var calls = 0;
      final e = MovaEngine(
        kernel: FakeKernel(),
        interceptors: [hook],
        reporter: MovaCallbackReporter((ev) {
          if (calls++ == 0) throw StateError('boom');
          received.add(ev);
        }),
      );
      expect(() => e.report(MovaReportName.play), returnsNormally);
      e.report(MovaReportName.pause);
      expect(received.single.name, MovaReportName.pause);
      expect(hook.errors.whereType<StateError>(), hasLength(1));
      await e.dispose();
    });

    test('a reporter that always throws never loops or breaks playback', () async {
      final k = FakeKernel();
      final hook = _ErrorSpyHook();
      final e = MovaEngine(
        kernel: k,
        interceptors: [hook],
        reporter: MovaCallbackReporter((_) => throw StateError('always')),
      );
      k.emitPlaying(true);
      k.emitCompleted(true);
      await Future<void>.delayed(Duration.zero);
      expect(e.state.playing, isTrue);
      expect(e.state.completed, isTrue);
      expect(hook.errors, isNotEmpty);
      await e.dispose();
    });
  });
}

/// A hook that records every error it is told about.
///
/// 记录所有收到的错误的钩子。
class _ErrorSpyHook extends MovaHook {
  /// Errors received through `onError`, in order.
  ///
  /// 经 `onError` 收到的错误，按顺序。
  final List<Object> errors = <Object>[];

  @override
  void onError(Object error, StackTrace stack) => errors.add(error);
}
