import 'package:mova/src/core/kernel/restart_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_kernel.dart';

/// 默认关闭恢复和自动探测，只观察失败检测。
MovaEngine _engine(FakeKernel kernel) => createMovaEngine(
  kernel: kernel, brightness: MovaFallbackBrightnessPort(), pip: MovaNoopPipPort(),
  orientation: MovaNoopOrientationPort(),
  options: const MovaOpts(controls: MovaCtrlsConfig(autoHide: false), abr: MovaAbrConfig(probeVariants: false)),
);

/// 抛出原始错误，验证兼容的 Future 失败契约。
class _ThrowKernel extends FakeKernel implements MovaRestartObserver {
  /// 记录真实引擎转发的 RESTART 请求。
  bool observing = false;
  /// 接收精确首帧请求。
  @override
  void observeRestarts() => observing = true;
  /// 原始 open 异常。
  final failure = StateError('open failed');
  /// 打开媒体时抛出固定异常。
  @override
  Future<void> open(String uri, {bool play = true}) async => throw failure;
}

/// 运行默认终结失败检测回归。
void main() {
  test('A14 END_FILE error writes terminal state clears buffering and pauses without recovery', () async {
    final k = FakeStatsKernel();
    final e = _engine(k);
    final events = <MovaEvent>[];
    e.events.listen(events.add);
    await e.open(const MovaSource('https://h/a.mp4'));
    k.emitBuffering(true);
    await pumpEventQueue();
    k.emitEndFile(MovaEndFileReason.error);
    await pumpEventQueue();
    expect(e.state.error, MovaEndFileReason.error);
    expect(e.state.buffering, isFalse);
    expect(events.whereType<MovaErrorEvent>().single.fatal, isTrue);
    expect(events.whereType<MovaBufferChange>().last.buffering, isFalse);
    expect(k.calls.last, 'pause');
    await e.dispose();
  });

  for (final reason in [MovaEndFileReason.stop, MovaEndFileReason.quit, MovaEndFileReason.redirect]) {
    test('A14 $reason is not a playback failure', () async {
      final k = FakeStatsKernel();
      final e = _engine(k);
      await e.open(const MovaSource('https://h/a.mp4'));
      k.emitEndFile(reason);
      await pumpEventQueue();
      expect(e.state.error, isNull);
      expect(k.calls, isNot(contains('pause')));
      await e.dispose();
    });
  }

  test('A14 open still throws original failure and writes fatal state and event', () async {
    final k = _ThrowKernel();
    final e = _engine(k);
    e.observeRestarts();
    expect(k.observing, isTrue);
    final errors = <MovaErrorEvent>[];
    e.events.where((v) => v is MovaErrorEvent).cast<MovaErrorEvent>().listen(errors.add);
    await expectLater(e.open(const MovaSource('https://h/a.mp4')), throwsA(same(k.failure)));
    await pumpEventQueue();
    expect(e.state.error, same(k.failure));
    expect(errors.single.fatal, isTrue);
    await e.dispose();
  });

  test('A14 alternatives require recovery in debug', () async {
    final e = _engine(FakeKernel());
    await expectLater(e.open(const MovaSource('x', alternatives: ['y'])), throwsAssertionError);
    await e.dispose();
  });
}
