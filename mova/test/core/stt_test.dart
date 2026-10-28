import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/stt/cue.dart';
import 'package:mova/src/core/stt/port.dart';
import 'package:mova/src/core/stt/service.dart';

/// An engine whose first `start` throws, later ones succeed.
///
/// 第一次 `start` 抛错、之后成功的引擎。
class _FlakyEngine extends MovaNoopSttEngine {
  /// Number of `start` calls so far.
  ///
  /// 目前为止 `start` 的调用次数。
  int starts = 0;

  @override
  Future<void> start(Duration position) async {
    starts++;
    if (starts == 1) throw StateError('boom');
  }
}

/// A scripted engine: pushes cues on demand and records how it is driven.
///
/// 可编排的引擎：按需推送字幕块，并记录被如何驱动。
class _ScriptedEngine extends MovaNoopSttEngine {
  final StreamController<MovaSttCue> _out = StreamController<MovaSttCue>.broadcast();

  /// The position of every `start` call, in order.
  ///
  /// 每次 `start` 的位置，按顺序。
  final List<Duration> starts = <Duration>[];

  /// How many `stop` calls arrived.
  ///
  /// `stop` 的调用次数。
  int stops = 0;

  /// Whether `dispose` ran.
  ///
  /// `dispose` 是否执行过。
  bool disposed = false;

  @override
  Stream<MovaSttCue> get cues => _out.stream;

  /// Pushes [cue] as if the recognizer produced it.
  ///
  /// 推送 [cue]，仿佛识别器产出了它。
  void say(MovaSttCue cue) => _out.add(cue);

  @override
  Future<void> start(Duration atPosition) async => starts.add(atPosition);

  @override
  Future<void> stop() async => stops++;

  @override
  void feed(Float32List samples, int sampleRateHz) {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _out.close();
  }
}

/// A cue spanning [from]..[to] seconds.
///
/// 跨 [from]..[to] 秒的字幕块。
MovaSttCue _cue(String text, int from, int to) =>
    MovaSttCue(text: text, start: Duration(seconds: from), end: Duration(seconds: to));

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

  group('MovaNoopSttEngine', () {
    test('reports no languages and emits no cues', () async {
      final engine = MovaNoopSttEngine();
      expect(engine.languages, isEmpty);
      await expectLater(engine.cues, emitsDone);
      await engine.start(Duration.zero);
      await engine.stop();
      await engine.dispose();
    });
  });

  group('MovaSttService', () {
    test('a failed engine start is rolled back so start() can be retried', () async {
      final engine = _FlakyEngine();
      final svc = MovaSttService(config: MovaSttConfig(enabled: true, engine: engine))
        ..attach(const MovaSource('https://host/a.mp4'));
      await expectLater(svc.start(), throwsStateError);
      expect(svc.isRunning, isFalse);
      await svc.start();
      expect(engine.starts, 2);
      expect(svc.isRunning, isTrue);
    });
  });

  group('MovaSttService lifecycle', () {
    const src = MovaSource('https://host/a.mp4');

    /// A service over a [_ScriptedEngine], enabled and attached to [src].
    ///
    /// 基于 [_ScriptedEngine] 的服务，已启用并挂到 [src] 上。
    (MovaSttService, _ScriptedEngine) ready() {
      final engine = _ScriptedEngine();
      final svc = MovaSttService(config: MovaSttConfig(enabled: true, engine: engine))..attach(src);
      return (svc, engine);
    }

    test('start hands the engine the latest known position', () async {
      final (svc, engine) = ready();
      svc.updatePosition(const Duration(seconds: 30));
      await svc.start();
      expect(engine.starts, [const Duration(seconds: 30)]);
      expect(svc.isRunning, isTrue);
    });

    test('a second start while running is a no-op', () async {
      final (svc, engine) = ready();
      await svc.start();
      await svc.start();
      expect(engine.starts, hasLength(1));
    });

    test('stop ends the run and stops the engine once; a stop without a run does nothing', () async {
      final (svc, engine) = ready();
      await svc.stop();
      expect(engine.stops, 0);
      await svc.start();
      await svc.stop();
      await svc.stop();
      expect(svc.isRunning, isFalse);
      expect(engine.stops, 1);
    });

    test('start works again after stop, from the then-current position', () async {
      final (svc, engine) = ready();
      await svc.start();
      await svc.stop();
      svc.updatePosition(const Duration(seconds: 90));
      await svc.start();
      expect(engine.starts, [Duration.zero, const Duration(seconds: 90)]);
    });

    test('cues from the engine are forwarded to every subscriber', () async {
      final (svc, engine) = ready();
      final a = <String>[];
      final b = <String>[];
      svc.cues.listen((c) => a.add(c.text));
      svc.cues.listen((c) => b.add(c.text));
      engine.say(_cue('one', 0, 2));
      engine.say(_cue('two', 2, 4));
      await Future<void>.delayed(Duration.zero);
      expect(a, ['one', 'two']);
      expect(b, a);
    });

    test('current is the cue covering the playhead, null in a gap, and follows updatePosition', () async {
      final (svc, engine) = ready();
      engine.say(_cue('one', 0, 2));
      engine.say(_cue('two', 4, 6));
      await Future<void>.delayed(Duration.zero);
      svc.updatePosition(const Duration(seconds: 1));
      expect(svc.current?.text, 'one');
      svc.updatePosition(const Duration(seconds: 3));
      expect(svc.current, isNull);
      svc.updatePosition(const Duration(seconds: 5));
      expect(svc.current?.text, 'two');
    });

    test('with overlapping cues the most recent one wins', () async {
      final (svc, engine) = ready();
      engine.say(_cue('old', 0, 10));
      engine.say(_cue('new', 0, 10));
      await Future<void>.delayed(Duration.zero);
      svc.updatePosition(const Duration(seconds: 5));
      expect(svc.current?.text, 'new');
    });

    test('only the 50 most recent cues are remembered', () async {
      final (svc, engine) = ready();
      for (var i = 0; i < 51; i++) {
        engine.say(_cue('c$i', i * 10, i * 10 + 5));
      }
      await Future<void>.delayed(Duration.zero);
      svc.updatePosition(const Duration(seconds: 1));
      expect(svc.current, isNull, reason: 'cue 0 was evicted by the 51st');
      svc.updatePosition(const Duration(seconds: 11));
      expect(svc.current?.text, 'c1');
      svc.updatePosition(const Duration(seconds: 501));
      expect(svc.current?.text, 'c50');
    });

    test('attach clears the remembered cues and resets the position to zero', () async {
      final (svc, engine) = ready();
      engine.say(_cue('one', 0, 100));
      await Future<void>.delayed(Duration.zero);
      svc.updatePosition(const Duration(seconds: 50));
      expect(svc.current?.text, 'one');
      svc.attach(const MovaSource('https://host/b.mp4'));
      expect(svc.current, isNull);
      // A fresh start after attach begins from zero again.
      // attach 之后重新 start 从零开始。
      await svc.start();
      expect(engine.starts.last, Duration.zero);
    });

    test('blocked reasons: disabled, no engine and no source each report once', () async {
      final reasons = <MovaSttBlockReason>[];
      final disabled = MovaSttService(
        config: MovaSttConfig(enabled: false, engine: _ScriptedEngine()),
        onBlocked: reasons.add,
      )..attach(src);
      await disabled.start();
      final noEngine = MovaSttService(config: const MovaSttConfig(enabled: true), onBlocked: reasons.add)..attach(src);
      await noEngine.start();
      final noSource = MovaSttService(
        config: MovaSttConfig(enabled: true, engine: _ScriptedEngine()),
        onBlocked: reasons.add,
      );
      await noSource.start();
      expect(reasons, [MovaSttBlockReason.disabled, MovaSttBlockReason.noEngine, MovaSttBlockReason.noSource]);
      expect(disabled.isRunning || noEngine.isRunning || noSource.isRunning, isFalse);
    });

    test('languages mirror the engine, empty without one', () {
      expect(MovaSttService(config: const MovaSttConfig()).languages, isEmpty);
      expect(ready().$1.languages, isEmpty);
    });

    test('dispose closes the cue stream, cancels the engine subscription and disposes the engine', () async {
      final (svc, engine) = ready();
      final done = Completer<void>();
      svc.cues.listen((_) {}, onDone: done.complete);
      await svc.dispose();
      await done.future.timeout(const Duration(seconds: 2));
      expect(engine.disposed, isTrue);
    });
  });

  group('MovaSttConfig', () {
    test('defaults to disabled with no engine', () {
      const config = MovaSttConfig();
      expect(config.enabled, isFalse);
      expect(config.engine, isNull);
    });

    test('copyWith replaces only given fields', () {
      final engine = MovaNoopSttEngine();
      const config = MovaSttConfig();
      final updated = config.copyWith(enabled: true, engine: engine);
      expect(updated.enabled, isTrue);
      expect(updated.engine, same(engine));
      expect(config.enabled, isFalse, reason: 'original unchanged');
    });

    test('equality compares engine by identity', () {
      final engine = MovaNoopSttEngine();
      final a = MovaSttConfig(enabled: true, engine: engine);
      final b = MovaSttConfig(enabled: true, engine: engine);
      final c = MovaSttConfig(enabled: true, engine: MovaNoopSttEngine());
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
