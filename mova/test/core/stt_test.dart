import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/stt/cue.dart';
import 'package:mova/src/core/stt/stt.dart';
import 'package:mova/src/core/stt/service.dart';

/// A recognizer whose first `start` throws, later ones succeed.
///
/// 第一次 `start` 抛错、之后成功的识别器。
class _FlakyRecognizer extends MovaNoopStt {
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

/// A scripted recognizer: pushes cues on demand and records how it is driven.
///
/// 可编排的识别器：按需推送字幕块，并记录被如何驱动。
class _ScriptedRecognizer extends MovaNoopStt {
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

/// Holds the first start until a newer run has succeeded.
///
/// 挂起第一次启动，直到新一轮启动成功。
class _DelayedFailureRecognizer extends _ScriptedRecognizer {
  final first = Completer<void>();

  @override
  Future<void> start(Duration position) {
    starts.add(position);
    return starts.length == 1 ? first.future : Future<void>.value();
  }
}

void main() {
  test('D2 stale start failure cannot stop a newer successful run', () async {
    final recognizer = _DelayedFailureRecognizer();
    final svc = MovaSttService(opts: MovaSttOpts(enabled: true, recognizer: recognizer))
      ..attach(const MovaSource('https://host/a.mp4'));
    final oldStart = svc.start();
    await svc.stop();
    await svc.start();
    recognizer.first.completeError(StateError('old start failed'));
    await oldStart;
    expect(svc.isRunning, isTrue);
    await svc.stop();
    expect(svc.isRunning, isFalse);
    expect(recognizer.stops, 2);
    await svc.dispose();
    await recognizer.dispose();
  });

  test('C02 missing recognizer warns once and remains stopped', () async {
    final messages = <String>[];
    final reasons = <MovaSttBlockReason>[];
    await runZoned(() async {
      final service = MovaSttService(opts: const MovaSttOpts(enabled: true), onBlocked: reasons.add);
      expect(messages, isEmpty);
      await service.start();
      await service.start();
      expect(service.opts.hasRecognizer, isFalse);
      expect(service.isRunning, isFalse);
      expect(reasons, [MovaSttBlockReason.noRecognizer, MovaSttBlockReason.noRecognizer]);
      expect(messages.where((m) => m.contains('stt.recognizer')), hasLength(1));
      await service.dispose();
    }, zoneSpecification: ZoneSpecification(print: (_, _, _, m) => messages.add(m)));
  });

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

  group('MovaNoopStt', () {
    test('reports no languages and emits no cues', () async {
      final recognizer = MovaNoopStt();
      expect(recognizer.languages, isEmpty);
      await expectLater(recognizer.cues, emitsDone);
      await recognizer.start(Duration.zero);
      await recognizer.stop();
      await recognizer.dispose();
    });
  });

  group('MovaSttService', () {
    test('a failed recognizer start is rolled back so start() can be retried', () async {
      final recognizer = _FlakyRecognizer();
      final svc = MovaSttService(opts: MovaSttOpts(enabled: true, recognizer: recognizer))
        ..attach(const MovaSource('https://host/a.mp4'));
      // 旧断言要求 rethrow，会让可选识别故障泄漏到播放链；失败现在仅回滚。
      await svc.start();
      expect(svc.isRunning, isFalse);
      await svc.start();
      expect(recognizer.starts, 2);
      expect(svc.isRunning, isTrue);
    });
  });

  group('MovaSttService lifecycle', () {
    const src = MovaSource('https://host/a.mp4');

    /// A service over a [_ScriptedRecognizer], enabled and attached to [src].
    ///
    /// 基于 [_ScriptedRecognizer] 的服务，已启用并挂到 [src] 上。
    (MovaSttService, _ScriptedRecognizer) ready() {
      final recognizer = _ScriptedRecognizer();
      final svc = MovaSttService(opts: MovaSttOpts(enabled: true, recognizer: recognizer))..attach(src);
      return (svc, recognizer);
    }

    test('start hands the recognizer the latest known position', () async {
      final (svc, recognizer) = ready();
      svc.updatePosition(const Duration(seconds: 30));
      await svc.start();
      expect(recognizer.starts, [const Duration(seconds: 30)]);
      expect(svc.isRunning, isTrue);
    });

    test('a second start while running is a no-op', () async {
      final (svc, recognizer) = ready();
      await svc.start();
      await svc.start();
      expect(recognizer.starts, hasLength(1));
    });

    test('stop ends the run and stops the recognizer once; a stop without a run does nothing', () async {
      final (svc, recognizer) = ready();
      await svc.stop();
      expect(recognizer.stops, 0);
      await svc.start();
      await svc.stop();
      await svc.stop();
      expect(svc.isRunning, isFalse);
      expect(recognizer.stops, 1);
    });

    test('start works again after stop, from the then-current position', () async {
      final (svc, recognizer) = ready();
      await svc.start();
      await svc.stop();
      svc.updatePosition(const Duration(seconds: 90));
      await svc.start();
      expect(recognizer.starts, [Duration.zero, const Duration(seconds: 90)]);
    });

    test('cues from the recognizer are forwarded to every subscriber', () async {
      final (svc, recognizer) = ready();
      final a = <String>[];
      final b = <String>[];
      svc.cues.listen((c) => a.add(c.text));
      svc.cues.listen((c) => b.add(c.text));
      recognizer.say(_cue('one', 0, 2));
      recognizer.say(_cue('two', 2, 4));
      await Future<void>.delayed(Duration.zero);
      expect(a, ['one', 'two']);
      expect(b, a);
    });

    test('current is the cue covering the playhead, null in a gap, and follows updatePosition', () async {
      final (svc, recognizer) = ready();
      recognizer.say(_cue('one', 0, 2));
      recognizer.say(_cue('two', 4, 6));
      await Future<void>.delayed(Duration.zero);
      svc.updatePosition(const Duration(seconds: 1));
      expect(svc.current?.text, 'one');
      svc.updatePosition(const Duration(seconds: 3));
      expect(svc.current, isNull);
      svc.updatePosition(const Duration(seconds: 5));
      expect(svc.current?.text, 'two');
    });

    test('with overlapping cues the most recent one wins', () async {
      final (svc, recognizer) = ready();
      recognizer.say(_cue('old', 0, 10));
      recognizer.say(_cue('new', 0, 10));
      await Future<void>.delayed(Duration.zero);
      svc.updatePosition(const Duration(seconds: 5));
      expect(svc.current?.text, 'new');
    });

    test('only the 50 most recent cues are remembered', () async {
      final (svc, recognizer) = ready();
      for (var i = 0; i < 51; i++) {
        recognizer.say(_cue('c$i', i * 10, i * 10 + 5));
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
      final (svc, recognizer) = ready();
      recognizer.say(_cue('one', 0, 100));
      await Future<void>.delayed(Duration.zero);
      svc.updatePosition(const Duration(seconds: 50));
      expect(svc.current?.text, 'one');
      svc.attach(const MovaSource('https://host/b.mp4'));
      expect(svc.current, isNull);
      // A fresh start after attach begins from zero again.
      // attach 之后重新 start 从零开始。
      await svc.start();
      expect(recognizer.starts.last, Duration.zero);
    });

    test('blocked reasons: disabled, no recognizer and no source each report once', () async {
      final reasons = <MovaSttBlockReason>[];
      final disabled = MovaSttService(
        opts: MovaSttOpts(enabled: false, recognizer: _ScriptedRecognizer()),
        onBlocked: reasons.add,
      )..attach(src);
      await disabled.start();
      final noRecognizer = MovaSttService(opts: const MovaSttOpts(enabled: true), onBlocked: reasons.add)..attach(src);
      await noRecognizer.start();
      final noSource = MovaSttService(
        opts: MovaSttOpts(enabled: true, recognizer: _ScriptedRecognizer()),
        onBlocked: reasons.add,
      );
      await noSource.start();
      expect(reasons, [MovaSttBlockReason.disabled, MovaSttBlockReason.noRecognizer, MovaSttBlockReason.noSource]);
      expect(disabled.isRunning || noRecognizer.isRunning || noSource.isRunning, isFalse);
    });

    test('languages mirror the recognizer, empty without one', () {
      expect(MovaSttService(opts: const MovaSttOpts()).languages, isEmpty);
      expect(ready().$1.languages, isEmpty);
    });

    test('dispose closes the cue stream and cancels subscriptions while borrowing the recognizer', () async {
      final (svc, recognizer) = ready();
      final done = Completer<void>();
      svc.cues.listen((_) {}, onDone: done.complete);
      await svc.dispose();
      await done.future.timeout(const Duration(seconds: 2));
      // 旧断言销毁宿主对象，违背借用关系。
      expect(recognizer.disposed, isFalse);
      await recognizer.dispose();
    });
  });

  group('MovaSttOpts', () {
    test('defaults to disabled with no recognizer', () {
      const opts = MovaSttOpts();
      expect(opts.enabled, isFalse);
      expect(opts.recognizer, isNull);
    });

    test('copyWith replaces only given fields', () {
      final recognizer = MovaNoopStt();
      const opts = MovaSttOpts();
      final updated = opts.copyWith(enabled: true, recognizer: recognizer);
      expect(updated.enabled, isTrue);
      expect(updated.recognizer, same(recognizer));
      expect(opts.enabled, isFalse, reason: 'original unchanged');
    });

    test('equality compares recognizer by identity', () {
      final recognizer = MovaNoopStt();
      final a = MovaSttOpts(enabled: true, recognizer: recognizer);
      final b = MovaSttOpts(enabled: true, recognizer: recognizer);
      final c = MovaSttOpts(enabled: true, recognizer: MovaNoopStt());
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('MovaOpts', () {
    test('carries a default MovaSttOpts and includes it in equality', () {
      const options = MovaOpts();
      expect(options.stt, const MovaSttOpts());

      final withStt = options.copyWith(stt: const MovaSttOpts(enabled: true));
      expect(withStt, isNot(options));
      expect(withStt.stt.enabled, isTrue);
    });
  });
}
