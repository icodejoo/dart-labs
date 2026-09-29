import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
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
}
