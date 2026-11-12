import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/classified_error_kernel.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/core/model/playback_error.dart';

import '../support/fake_kernel.dart';

/// 与两条错误流同时发送一行日志的 media_kit 替身。
class _Player extends Fake implements Player {
  /// 流集合。
  final channels = _Streams();

  @override
  PlayerStream get stream => channels;

  @override
  Future<void> dispose() async {
    await channels.logs.close();
    await channels.errors.close();
  }
}

/// mpv 适配器所需的原始日志、错误和尺寸流。
class _Streams extends Fake implements PlayerStream {
  /// 同一行日志的前缀入口。
  final logs = StreamController<PlayerLog>.broadcast();

  /// media_kit 从同一行派生的旧错误入口。
  final errors = StreamController<String>.broadcast();

  @override
  Stream<PlayerLog> get log => logs.stream;

  @override
  Stream<String> get error => errors.stream;

  @override
  Stream<int?> get width => const Stream.empty();

  @override
  Stream<int?> get height => const Stream.empty();
}

/// 实现可选能力的内核，允许检测引擎有没有读取旧 error 入口。
class _ClassifiedKernel extends FakeKernel implements MovaClassifiedErrorKernel {
  /// 分级流，默认异步广播以模拟真实内核。
  final classified = StreamController<MovaKernelError>.broadcast();

  /// 对旧入口的读取次数，应一直为零。
  int legacyReads = 0;

  @override
  Stream<Object> get error {
    legacyReads++;
    return super.error;
  }

  @override
  Stream<MovaKernelError> get kernelErrors => classified.stream;

  @override
  Future<void> dispose() async {
    await classified.close();
    await super.dispose();
  }
}

/// 核对分级前后错误钩子仍收到原对象。
class _Hook extends MovaHook {
  /// 钩子收到的原始错误。
  final errors = <Object>[];

  @override
  void onError(Object error, StackTrace stack) => errors.add(error);
}

/// 创建真实引擎，默认关闭与错误分级无关的计时器。
MovaEngine _engine(FakeKernel kernel, {_Hook? hook, bool recovery = false}) => createMovaEngine(
  kernel: kernel, ownsKernel: true,
  brightness: MovaFallbackBrightnessPort(),
  pip: MovaNoopPipPort(),
  orientation: MovaNoopOrientationPort(),
  interceptors: [?hook],
  options: MovaOpts(
    controls: const MovaCtrlsConfig(autoHide: false),
    recovery: MovaRecoveryConfig(enabled: recovery, policy: const MovaFailoverOnly()),
  ),
);

/// 构建恢复放弃的输入，不依赖引擎或网络。
const _fail = MovaPlayFail(
  kind: MovaPlayFailKind.nativeEndError, sourceIndex: 0, uri: 'https://h/a.mp4',
  sourceCount: 1, attempt: 1, streak: 1,
);

void main() {
  test('A13 classification covers full prefix code table without QoE fatal policy', () {
    const codes = <String?, String>{
      'stream': 'stream', 'file': 'file', 'ffmpeg': 'network',
      'vd': 'decode.video', 'ad': 'decode.audio', 'cplayer': 'player',
      null: 'unknown', 'other': 'unknown',
    };
    for (final after in [false, true]) {
      for (final entry in codes.entries) {
        final result = classifyMovaPlaybackError('transient',
          subsystem: entry.key, afterFirstFrame: after);
        expect(result.fatal, isFalse, reason: '${entry.key}, after=$after');
        expect(result.code, entry.value);
        expect(result.code, const MovaPrefixError().classify('transient',
          subsystem: entry.key, afterFirstFrame: after).code);
      }
    }
  });

  test('A13 known terminal text is narrow and decoder attempts remain nonterminal', () {
    const cases = {
      'Failed to initialize a decoder for codec h264': true,
      '  Failed to initialize a decoder for codec hevc.\n': true,
      'Failed to recognize file format.': true,
      '  Failed to recognize file format.\n': true,
      'Could not open codec.': false,
      'Cannot seek in this stream': false,
      'You can force it with \'--force-seekable=yes\'.': false,
      'Failed to initialize video output': false,
      'HTTP error 404 Not Found': false,
      'tcp: connection reset': false,
      'prefix Failed to initialize a decoder': false,
    };
    for (final after in [false, true]) {
      for (final entry in cases.entries) {
        expect(classifyMovaPlaybackError(entry.key,
          subsystem: 'cplayer', afterFirstFrame: after).fatal,
          entry.value, reason: entry.key);
      }
    }
  });

  test('A13 END_FILE error and recovery exhaustion are terminal structured inputs', () {
    for (final after in [false, true]) {
      for (final error in [MovaEndFileReason.error, const MovaGiveUpError(_fail)]) {
        final verdict = classifyMovaPlaybackError(error, afterFirstFrame: after);
        expect(verdict.fatal, isTrue);
        expect(verdict.code, 'unknown');
      }
      for (final reason in [MovaEndFileReason.stop, MovaEndFileReason.quit, MovaEndFileReason.redirect]) {
        expect(classifyMovaPlaybackError(reason, afterFirstFrame: after).fatal, isFalse);
      }
    }
  });

  test('A13 event constructors preserve positional stack and add classified fields', () {
    final stack = StackTrace.current;
    const legacy = MovaErrorEvent('old');
    final withStack = MovaErrorEvent('old', stack);
    const classified = MovaErrorEvent.classified('new', fatal: false, code: 'network');
    final classifiedStack = MovaErrorEvent.classified('new', stack: stack, fatal: true);
    expect(legacy.fatal, isTrue);
    expect(legacy.code, isNull);
    expect(legacy.stack, isNull);
    expect(withStack.error, 'old');
    expect(withStack.stack, same(stack));
    expect(withStack.fatal, isTrue);
    expect(withStack.code, isNull);
    expect(classified.error, 'new');
    expect(classified.fatal, isFalse);
    expect(classified.code, 'network');
    expect(classifiedStack.stack, same(stack));
    expect(classifiedStack.fatal, isTrue);
    expect(classifiedStack.code, isNull);
    const raw = MovaKernelError('error');
    expect(raw.error, 'error');
    expect(raw.subsystem, isNull);
  });

  test('A13 log filtering matches media_kit 1.2.6 plus existing benign filter', () {
    for (final level in ['error', 'warn', 'fatal', 'info']) {
      for (final prefix in ['file', 'vd', 'ad', 'cplayer', 'stream', 'ffmpeg', 'ao', 'demux']) {
        for (final text in ['broken', 'tcp: reset', 'http: failed']) {
          final expected = level == 'error' &&
              (['file', 'vd', 'ad', 'cplayer', 'stream'].contains(prefix) ||
                (prefix == 'ffmpeg' && text.startsWith('tcp:')));
          expect(isMovaMpvErrorLog(prefix: prefix, level: level, text: text),
            expected, reason: '$level/$prefix/$text');
        }
      }
    }
    for (final text in ['Cannot seek in this stream',
      "You can force it with '--force-seekable=yes'.", 'Could not open codec.']) {
      expect(isMovaMpvErrorLog(prefix: 'cplayer', level: 'error', text: text), isFalse);
    }
    expect(isMovaMpvErrorLog(prefix: 'vd', level: 'error',
      text: 'Failed to initialize a decoder for codec h264'), isTrue);
  });

  test('A13 mpv optional stream carries original prefix with legacy stream parity', () async {
    final player = _Player();
    final kernel = MovaMpvKernel(player: player, audioOnly: true, observeQoeSignals: false);
    final classified = <MovaKernelError>[];
    final legacy = <Object>[];
    final first = kernel.kernelErrors.listen(classified.add);
    final second = kernel.error.listen(legacy.add);
    for (final (prefix, text) in [('vd', 'damaged frame'),
      ('ffmpeg', 'tcp: reset'), ('cplayer', 'Could not open codec.')]) {
      player.channels.logs.add(PlayerLog(prefix: prefix, level: 'error', text: text));
      player.channels.errors.add(text);
    }
    player.channels.logs.add(const PlayerLog(prefix: 'ffmpeg', level: 'error', text: 'http: not a stream.error'));
    await Future<void>.delayed(Duration.zero);
    expect(classified.map((v) => v.error), legacy);
    expect(classified.map((v) => v.subsystem), ['vd', 'ffmpeg']);
    expect(classified.map((v) => v.error), ['damaged frame', 'tcp: reset']);
    await first.cancel();
    await second.cancel();
    await kernel.dispose();
  });

  test('A13 engine prefers classified stream and does not subscribe duplicate legacy error', () {
    fakeAsync((clock) {
      final kernel = _ClassifiedKernel();
      final hook = _Hook();
      final engine = _engine(kernel, hook: hook);
      final events = <MovaErrorEvent>[];
      engine.events.where((e) => e is MovaErrorEvent).cast<MovaErrorEvent>().listen(events.add);
      kernel.emitError('duplicate');
      kernel.classified.add(const MovaKernelError('tcp: reset', 'ffmpeg'));
      clock.flushMicrotasks();
      expect(kernel.legacyReads, 0);
      expect(events, hasLength(1));
      expect(events.single.fatal, isFalse);
      expect(events.single.code, 'network');
      expect(engine.state.error, isNull);
      expect(hook.errors, ['tcp: reset']);
      engine.dispose();
      clock.flushMicrotasks();
    });
  });

  test('A13 old kernels fall back to raw error with unknown code without nonterminal state', () {
    fakeAsync((clock) {
      final kernel = FakeKernel();
      final hook = _Hook();
      final engine = _engine(kernel, hook: hook);
      final events = <MovaErrorEvent>[];
      engine.events.where((e) => e is MovaErrorEvent).cast<MovaErrorEvent>().listen(events.add);
      final error = StateError('recoverable diagnostic');
      kernel.emitError(error);
      clock.flushMicrotasks();
      expect(events.single.error, same(error));
      expect(events.single.fatal, isFalse);
      expect(events.single.code, 'unknown');
      expect(engine.state.error, isNull);
      expect(hook.errors.single, same(error));
      engine.dispose();
      clock.flushMicrotasks();
    });
  });

  test('A13 recovery give up event is classified terminal while cleanup is unchanged', () {
    fakeAsync((clock) {
      final kernel = FakeStatsKernel();
      final engine = _engine(kernel, recovery: true);
      final events = <MovaErrorEvent>[];
      engine.events.where((e) => e is MovaErrorEvent).cast<MovaErrorEvent>().listen(events.add);
      engine.open(const MovaSource('https://h/a.mp4'));
      clock.flushMicrotasks();
      kernel.emitBuffering(true);
      kernel.emitEndFile(MovaEndFileReason.error);
      clock.flushMicrotasks();
      expect(events.single.error, isA<MovaGiveUpError>());
      expect(events.single.fatal, isTrue);
      expect(events.single.code, 'unknown');
      expect(engine.state.error, same(events.single.error));
      expect(engine.state.buffering, isFalse);
      expect(kernel.calls.last, 'pause');
      engine.dispose();
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('A13 after first frame diagnostics leave state clear and terminal decoder errors remain fatal', () async {
      final kernel = _ClassifiedKernel();
      final engine = _engine(kernel);
      final events = <MovaErrorEvent>[];
      engine.events.where((e) => e is MovaErrorEvent).cast<MovaErrorEvent>().listen(events.add);
      engine.open(const MovaSource('https://h/a.mp4'));
      await Future<void>.delayed(Duration.zero);
      kernel.emitBuffering(true);
      kernel.emitBuffering(false);
      await Future<void>.delayed(Duration.zero);
      expect(engine.state.rendered, isTrue);
      kernel.classified.add(const MovaKernelError('damaged frame', 'vd'));
      await Future<void>.delayed(Duration.zero);
      expect(events.single.fatal, isFalse);
      expect(events.single.code, 'decode.video');
      expect(engine.state.error, isNull);
      kernel.classified.add(const MovaKernelError('Failed to initialize a decoder for codec h264', 'vd'));
      await Future<void>.delayed(Duration.zero);
      expect(events.last.fatal, isTrue);
      expect(events.last.code, 'decode.video');
      expect(engine.state.error, events.last.error);
      await engine.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(kernel.classified.hasListener, isFalse);
      expect(kernel.isDisposed, isTrue);
  });
}
