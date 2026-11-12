import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_api.dart';
import 'cutover_operation_test.dart' show OperationRig, settleOperations;

const _source = MovaSource('https://host/next.mp4');

/// Gates settings migration using the existing API fixture.
///
/// 沿用现有 API 夹具，门控设置迁移。
class _SettingsApi extends FakeMovaApi {
  /// Creates an engine with cutover enabled.
  ///
  /// 创建启用切换的引擎。
  _SettingsApi({super.options = const MovaOpts(
    cutover: MovaCutoverConfig(enabled: true, muteWhileWarm: false),
  )});

  Completer<void>? fitGate;
  Completer<void>? rateGate;

  /// Applies rate observations explicitly, as the shared fixture only logs setters.
  ///
  /// 显式更新倍速观测；共享夹具的设置方法仅记录调用。
  @override
  Future<void> setRate(double rate) async {
    await rateGate?.future;
    await super.setRate(rate);
    push(state.copyWith(rate: rate));
  }

  /// Pauses migration after rate inheritance.
  ///
  /// 在倍速继承之后暂停迁移。
  @override
  Future<void> setFit(MovaFit fit) async {
    await fitGate?.future;
    await super.setFit(fit);
    push(state.copyWith(fit: fit));
  }
}

/// Covers low-priority cutover lifecycle, timeout and rate regressions.
///
/// 覆盖切换生命周期、超时与倍速的低优先级回归。
void main() {
  test('C4 dispose releases a claimed shadow before its play hook returns', () async {
    final rig = OperationRig();
    addTearDown(rig.api.dispose);
    final shadow = await rig.warm('claimed');
    final gate = shadow.playGate = Completer<void>();
    final committing = rig.api.commit();
    await settleOperations();
    expect(shadow.calls, contains('play'));
    await rig.api.dispose();
    expect(shadow.disposeCount, 1);
    expect(rig.engines.first.disposeCount, 1);
    gate.complete();
    expect(await committing, isFalse);
    expect(shadow.disposeCount, 1);
  });

  for (final lateError in [false, true]) {
    test('C9 timeout falls back before open returns, late error=$lateError', () async {
      final made = <FakeMovaApi>[];
      final gate = Completer<void>();
      final api = MovaCutoverEngine(engineFactory: () {
        final e = _SettingsApi(options: const MovaOpts(
          cutover: MovaCutoverConfig(enabled: true, muteWhileWarm: false,
            readyTimeout: Duration(milliseconds: 50)),
        ));
        if (made.isNotEmpty) {
          e.openGate = gate;
          if (lateError) e.openThrows = StateError('late open failure');
        }
        made.add(e);
        return e;
      });
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await api.dispose();
      });
      final seamless = await api.cutoverTo(_source, rate: 1.5)
          .timeout(const Duration(seconds: 2));
      expect(seamless, isFalse);
      expect(gate.isCompleted, isFalse);
      expect(made.first.source, _source);
      expect(made.first.state.rate, 1.5);
      await settleOperations();
      expect(made.last.disposeCount, 1);
      gate.complete();
      await settleOperations();
      expect(api.active, same(made.first));
      expect(made.last.disposeCount, 1);
    });
  }

  for (final latePause in [false, true]) {
    test('C11 rate migration honors late rate and pause=$latePause', () async {
      final made = <_SettingsApi>[];
      final api = MovaCutoverEngine(engineFactory: () {
        final e = _SettingsApi();
        made.add(e);
        return e;
      });
      addTearDown(api.dispose);
      await api.play();
      await api.setRate(1.25);
      await api.setFit(MovaFit.cover);
      await api.prepare(_source, plan: const MovaWarmPlan(trigger: MovaEagerWarm()));
      final shadow = made.last;
      const tick = MovaProg(position: Duration(seconds: 1), buffer: Duration(seconds: 10));
      shadow.pushProgress(tick);
      await settleOperations();
      shadow.pushProgress(tick);
      await settleOperations();
      final gate = shadow.fitGate = Completer<void>();
      final committing = api.commit();
      await settleOperations();
      expect(shadow.state.rate, 1.25);
      await api.setRate(2);
      final rateGate = shadow.rateGate = latePause ? Completer<void>() : null;
      gate.complete();
      if (latePause) {
        await settleOperations();
        await api.pause();
        rateGate!.complete();
      }
      expect(await committing, isTrue);
      expect(api.active, same(shadow));
      expect(shadow.state.rate, 2);
      if (latePause) expect(shadow.state.playbackIntent, isFalse);
    });
  }

  for (final accepted in [true, false]) {
    test('C13 disabled cutover fallback applies rate only when accepted=$accepted', () async {
      final engine = _SettingsApi(options: const MovaOpts())
        ..acceptOpens = accepted;
      final api = MovaCutoverEngine(engineFactory: () => engine);
      addTearDown(api.dispose);
      await api.setRate(1.25);
      engine.calls.clear();
      expect(await api.cutoverTo(_source, rate: 1.5), isFalse);
      expect(engine.state.rate, accepted ? 1.5 : 1.25);
      expect(engine.calls.where((call) => call == 'setRate'), hasLength(accepted ? 1 : 0));
    });
  }
}
