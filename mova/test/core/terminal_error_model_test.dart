import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';
import '../support/fake_kernel.dart';
import '../support/pump.dart';

/// 记录所有错误，证明非终结日志仍可诊断。
class _Hook extends MovaHook {
  /// 收到的原始错误。
  final errors = <Object>[];
  /// 保存钩子通知。
  @override
  void onError(Object error, StackTrace stack) => errors.add(error);
}

/// 使用显式端口和关闭探测的真实播放器，避免平台及网络副作用。
Mova _mova(FakeKernel k, _Hook hook) => createMova(
  kernel: k, interceptors: [hook], brightness: MovaFallbackBrightness(),
  pip: MovaNoopPip(), orient: MovaNoopOrient(),
  options: const MovaOpts(controls: MovaCtrlsOpts(autoHide: false), abr: MovaAbrOpts(probeVariants: false)),
);

/// 运行终结状态与用户文案的回归测试。
void main() {
  for (final rendered in [false, true]) {
    test('A14b nonterminal diagnostic rendered=$rendered keeps state clear and notifies event and hook', () async {
      final k = FakeKernel();
      final hook = _Hook();
      final e = _mova(k, hook);
      final events = <MovaErrorEvent>[];
      e.events.where((v) => v is MovaErrorEvent).cast<MovaErrorEvent>().listen(events.add);
      await e.open(const MovaSource('https://h/a.mp4'));
      if (rendered) {
        k.emitBuffering(true);
        k.emitBuffering(false);
        await pumpEventQueue();
        expect(e.state.rendered, isTrue);
      }
      final error = StateError('temporary diagnostic');
      k.emitError(error);
      await pumpEventQueue();
      expect(e.state.error, isNull);
      expect(events.single.error, same(error));
      expect(events.single.fatal, isFalse);
      expect(hook.errors.single, same(error));
      await e.dispose();
    });
  }

  test('A14b nonterminal logs cannot overwrite an existing terminal failure', () async {
    final k = FakeStatsKernel();
    final e = _mova(k, _Hook());
    await e.open(const MovaSource('https://h/a.mp4'));
    k.emitEndFile(MovaEndFileReason.error);
    await pumpEventQueue();
    k.emitError('tcp: delayed diagnostic');
    await pumpEventQueue();
    expect(e.state.error, MovaEndFileReason.error);
    await e.dispose();
  });

  for (final error in ['Failed to recognize file format.', 'Failed to initialize a decoder for codec h264']) {
    test('A14b known terminal $error still writes state', () async {
      final k = FakeKernel();
      final hook = _Hook();
      final e = _mova(k, hook);
      final events = <MovaErrorEvent>[];
      e.events.where((v) => v is MovaErrorEvent).cast<MovaErrorEvent>().listen(events.add);
      k.emitError(error);
      await pumpEventQueue();
      expect(e.state.error, error);
      expect(events.single.fatal, isTrue);
      expect(hook.errors, [error]);
      await e.dispose();
    });
  }

  testWidgets('A14b overlay uses configured user copy and retry tooltip with debug-only raw text', (t) async {
    final api = FakeMovaApi(options: const MovaOpts(strings: MovaStrs(playbackError: 'Cannot play', retry: 'Try again')));
    api.push(const MovaState(error: 'raw backend detail'));
    await pumpComponent(t, api, MovaErrorComponent());
    expect(find.text('Cannot play'), findsOneWidget);
    expect(find.byTooltip('Try again'), findsOneWidget);
    expect(find.text('raw backend detail'), kDebugMode ? findsOneWidget : findsNothing);
    await t.tap(find.byIcon(Icons.refresh_rounded));
    expect(api.calls, contains('reload'));
    await api.dispose();
  });

  testWidgets('A14b actual nonterminal kernel event never raises overlay', (t) async {
    final k = FakeKernel();
    final e = (await t.runAsync(() async => _mova(k, _Hook())))!;
    await pumpComponent(t, e, MovaErrorComponent());
    await t.runAsync(() async {
      k.emitError('damaged frame');
      await pumpEventQueue();
    });
    await t.pump();
    await t.pump();
    expect(find.text(const MovaStrs().playbackError), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    await t.runAsync(() async {
      k.emitError('Failed to recognize file format.');
      await pumpEventQueue();
    });
    await t.pump();
    await t.pump();
    expect(find.text(const MovaStrs().playbackError), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(e.dispose);
  });

  test('A14b error strings participate in value equality and keep all existing defaults', () {
    const defaults = MovaStrs();
    expect(defaults.playbackError, '播放失败，请重试');
    expect(defaults.retry, '重试');
    const same = MovaStrs();
    expect(defaults, same);
    expect(defaults.hashCode, same.hashCode);
    expect(defaults, isNot(const MovaStrs(playbackError: 'Other')));
    expect(defaults, isNot(const MovaStrs(retry: 'Again')));
    expect(defaults.live, 'LIVE');
    expect(defaults.auto, '自动');
  });
}
