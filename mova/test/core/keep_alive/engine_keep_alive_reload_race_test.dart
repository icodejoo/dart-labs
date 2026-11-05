import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_kernel.dart';
import '../../support/gated.dart';

/// 排空流与钩子微任务。
void _settle(FakeAsync clock) => clock.flushMicrotasks();

/// 记录后台错误交给宿主钩子的结果。
class _ErrorHook extends MovaHook {
  /// 收到的原始异常。
  final errors = <Object>[];

  /// 保存引擎上报的异常。
  @override
  void onError(Object error, StackTrace stack) => errors.add(error);
}

/// 无待机能力的内核使直播直接 fallback，便于门控唤醒网络。
class _ReloadRig {
  /// 创建引擎并进入 fallback；[recovery] 控制失败交给恢复策略与否。
  _ReloadRig(this.clock, {bool recovery = false}) {
    e = createMovaEngine(
      kernel: k,
      pip: MovaNoopPipPort(),
      orientation: MovaNoopOrientationPort(),
      brightness: MovaFallbackBrightnessPort(),
      interceptors: [hook],
      options: MovaOpts(
        controls: const MovaCtrlsConfig(autoHide: false),
        live: const MovaLiveConfig(backToLive: MovaBackToLive.reopen),
        recovery: MovaRecoveryConfig(enabled: recovery),
      ),
    );
    final origin = DateTime(2026);
    e.debugClock = () => origin.add(clock.elapsed);
    e.events.listen(events.add);
    e.open(const MovaSource('https://h/a.flv', type: MovaStreamType.live));
    _settle(clock);
    k.emitPlaying(true);
    e.setKeepAlive(true);
    _settle(clock);
    k.emitPlaying(false);
    _settle(clock);
    expect(e.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
  }

  /// 虚拟时钟。
  final FakeAsync clock;
  /// 可门控加载的内核。
  final k = FakeKernel();
  /// 宿主错误接收器。
  final hook = _ErrorHook();
  /// 当前被测引擎。
  late final MovaEngine e;
  /// 公开事件记录。
  final events = <MovaEvent>[];
  /// 共享脚手架记录命令完成顺序。
  final log = CommandLog();

  /// 超过短暂停播宽限，再发起门控的唤醒重开。
  Completer<void> wake() {
    clock.elapse(const Duration(seconds: 30));
    final gate = k.openGate = Completer<void>();
    e.setKeepAlive(false).then((phase) {
      expect(phase, MovaKeepAlivePhase.resuming);
      log.record(0, 'wake returned');
    });
    _settle(clock);
    expect(log.entries.single.verb, 'wake returned');
    expect(gate.isCompleted, isFalse);
    return gate;
  }

  /// 释放引擎与计时器。
  void close() {
    e.dispose();
    _settle(clock);
  }
}

void main() {
  test('F-A hiding again alone invalidates the gated wake', () {
    fakeAsync((clock) {
      final r = _ReloadRig(clock);
      final gate = r.wake();
      r.e.setKeepAlive(true).then((_) => r.log.record(0, 'hidden again'));
      _settle(clock);
      expect(r.log.entries.last.verb, 'hidden again');
      expect(r.e.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      final plays = r.k.calls.where((v) => v == 'play').length;
      final edges = r.events.whereType<MovaLiveEdgeReach>().length;
      gate.complete();
      _settle(clock);
      clock.elapse(const Duration(seconds: 5));
      expect(r.k.calls.where((v) => v == 'play').length, plays);
      expect(r.e.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      expect(r.events.whereType<MovaLiveEdgeReach>().length, edges);
      expect(r.events.whereType<MovaKeepAliveResume>(), isEmpty);
      r.close();
    });
  });

  test('F-A backToLiveEdge in fallback never supplements play', () {
    fakeAsync((clock) {
      final r = _ReloadRig(clock);
      r.k.calls.clear();
      r.e.backToLiveEdge();
      _settle(clock);
      expect(r.k.lastPlay, isFalse);
      expect(r.k.calls, isNot(contains('play')));
      expect(r.e.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      r.close();
    });
  });

  for (final recovery in [false, true]) {
    test('F-C gated wake failure with recovery $recovery', () {
      fakeAsync((clock) {
        final r = _ReloadRig(clock, recovery: recovery);
        final gate = r.wake();
        final error = r.k.openError = StateError('wake failed');
        gate.complete();
        _settle(clock);
        if (recovery) {
          expect(r.events.whereType<MovaPlayFailure>(), hasLength(1));
          expect(r.events.whereType<MovaErrorEvent>(), isEmpty);
          expect(r.hook.errors, isEmpty);
        } else {
          expect(r.events.whereType<MovaErrorEvent>().single.error, same(error));
          expect(r.e.state.error, same(error));
          expect(r.hook.errors, [same(error)]);
          expect(r.e.state.keepAlivePhase, MovaKeepAlivePhase.off);
          clock.elapse(const Duration(seconds: 5));
          _settle(clock);
          expect(r.events.whereType<MovaKeepAliveResume>(), isEmpty);
        }
        r.close();
      });
    });
  }

  for (final failed in [false, true]) {
    for (final action in ['pause', 'replace']) {
      test('A07 ${failed ? "reopen" : "edge"} permits $action during network', () {
        fakeAsync((clock) {
          final k = FakeKeepAliveKernel();
          final e = createMovaEngine(
            kernel: k,
            pip: MovaNoopPipPort(),
            orientation: MovaNoopOrientationPort(),
            brightness: MovaFallbackBrightnessPort(),
            options: const MovaOpts(controls: MovaCtrlsConfig(autoHide: false)),
          );
          final origin = DateTime(2026);
          e.debugClock = () => origin.add(clock.elapsed);
          final events = <MovaEvent>[];
          e.events.listen(events.add);
          e.open(const MovaSource('https://h/a.flv', type: MovaStreamType.live));
          _settle(clock);
          k.emitPlaying(true);
          e.setKeepAlive(true);
          _settle(clock);
          if (failed) {
            k.emitCompleted(true);
            _settle(clock);
          } else {
            clock.elapse(const Duration(seconds: 30));
            _settle(clock);
          }
          expect(e.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
          k.emitPlaying(false);
          _settle(clock);
          final gate = k.openGate = Completer<void>();
          final log = CommandLog();
          e.setKeepAlive(false).then((phase) {
            expect(phase, MovaKeepAlivePhase.resuming);
            log.record(0, 'wake returned');
          });
          _settle(clock);
          expect(log.entries.single.verb, 'wake returned');
          expect(gate.isCompleted, isFalse);
          if (action == 'pause') {
            e.pause().then((_) => log.record(0, 'paused'));
          } else {
            k.openGate = null;
            e.setKeepAlive(true);
            e.open(const MovaSource('https://h/new.flv', type: MovaStreamType.live))
                .then((_) => log.record(0, 'replaced'));
          }
          _settle(clock);
          expect(log.entries, hasLength(2), reason: 'network must not block the queue');
          final plays = k.calls.where((v) => v == 'play').length;
          final edgeEvents = events.whereType<MovaLiveEdgeReach>().length;
          gate.complete();
          _settle(clock);
          expect(k.calls.where((v) => v == 'play').length, plays);
          if (action == 'replace') {
            expect(events.whereType<MovaLiveEdgeReach>().length, edgeEvents);
            expect(k.lastUri, 'https://h/new.flv');
          } else {
            expect(e.state.playbackIntent, isFalse);
            expect(e.state.keepAlivePhase, MovaKeepAlivePhase.off);
          }
          e.dispose();
          _settle(clock);
        });
      });
    }
  }

  test('A07 disposed wake has no late play or edge event', () {
    fakeAsync((clock) {
      final k = FakeKeepAliveKernel();
      final e = createMovaEngine(
        kernel: k,
        pip: MovaNoopPipPort(),
        orientation: MovaNoopOrientationPort(),
        brightness: MovaFallbackBrightnessPort(),
        options: const MovaOpts(controls: MovaCtrlsConfig(autoHide: false)),
      );
      final origin = DateTime(2026);
      e.debugClock = () => origin.add(clock.elapsed);
      e.open(const MovaSource('https://h/a.flv', type: MovaStreamType.live));
      _settle(clock);
      k.emitPlaying(true);
      e.setKeepAlive(true);
      _settle(clock);
      clock.elapse(const Duration(seconds: 30));
      final gate = k.openGate = Completer<void>();
      e.setKeepAlive(false);
      _settle(clock);
      e.dispose();
      _settle(clock);
      gate.complete();
      _settle(clock);
      expect(k.callsAfterDispose, isEmpty);
    });
  });
}

