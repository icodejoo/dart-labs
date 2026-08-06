import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/stt/cue.dart';
import 'package:mova/src/core/stt/port.dart';

void main() {
  group('MovaSttCue', () {
    test('covers is inclusive of start and exclusive of end', () {
      const cue = MovaSttCue(text: 'hi', start: Duration(seconds: 1), end: Duration(seconds: 2));
      expect(cue.covers(const Duration(seconds: 1)), isTrue);
      expect(cue.covers(const Duration(milliseconds: 1500)), isTrue);
      expect(cue.covers(const Duration(seconds: 2)), isFalse);
      expect(cue.covers(const Duration(milliseconds: 999)), isFalse);
    });

    test('equality is value-based', () {
      const a = MovaSttCue(text: 'hi', start: Duration.zero, end: Duration(seconds: 1));
      const b = MovaSttCue(text: 'hi', start: Duration.zero, end: Duration(seconds: 1));
      const c = MovaSttCue(text: 'bye', start: Duration.zero, end: Duration(seconds: 1));
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('NoopSttEngine', () {
    test('reports no languages and emits no cues', () async {
      final engine = NoopSttEngine();
      expect(engine.languages, isEmpty);
      await expectLater(engine.cues, emitsDone);
      await engine.start(Duration.zero);
      await engine.stop();
      await engine.dispose();
    });
  });

  group('MovaSttConfig', () {
    test('defaults to disabled with no engine', () {
      const config = MovaSttConfig();
      expect(config.enabled, isFalse);
      expect(config.engine, isNull);
    });

    test('copyWith replaces only given fields', () {
      final engine = NoopSttEngine();
      const config = MovaSttConfig();
      final updated = config.copyWith(enabled: true, engine: engine);
      expect(updated.enabled, isTrue);
      expect(updated.engine, same(engine));
      expect(config.enabled, isFalse, reason: 'original unchanged');
    });

    test('equality compares engine by identity', () {
      final engine = NoopSttEngine();
      final a = MovaSttConfig(enabled: true, engine: engine);
      final b = MovaSttConfig(enabled: true, engine: engine);
      final c = MovaSttConfig(enabled: true, engine: NoopSttEngine());
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('MovaOpts', () {
    test('carries a default MovaSttConfig and includes it in equality', () {
      const options = MovaOpts();
      expect(options.stt, const MovaSttConfig());

      final withStt = options.copyWith(stt: const MovaSttConfig(enabled: true));
      expect(withStt, isNot(options));
      expect(withStt.stt.enabled, isTrue);
    });
  });
}
