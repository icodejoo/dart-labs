import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/recovery/fail.dart';
import 'package:mova/src/core/report/stats_probe.dart';

import '../../support/fake_kernel.dart';

/// 恢复层修复回归：恢复后清错误、放弃后清缓冲、确定性失败快速重试。
///
/// 引擎 + FakeStatsKernel，关掉控制条自动隐藏，使挂起计时器只来自恢复层。
class _Rig {
  _Rig({MovaRecoveryConfig recovery = const MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true)})
    : kernel = FakeStatsKernel() {
    engine = MovaEngine(
      kernel: kernel,
      options: MovaOpts(recovery: recovery, controls: const MovaCtrlsConfig(autoHide: false)),
    );
    engine.events.listen(events.add);
  }

  final FakeStatsKernel kernel;
  late final MovaEngine engine;
  final List<MovaEvent> events = [];

  List<MovaPlayFailure> get failures => events.whereType<MovaPlayFailure>().toList();

  void open(FakeAsync async, {MovaStreamType type = MovaStreamType.vod}) {
    engine.open(MovaSource('https://h/a.m3u8', type: type));
    async.flushMicrotasks();
  }

  /// 经 buffering 下降沿让首帧落地。
  void land(FakeAsync async) {
    kernel.emitBuffering(true);
    kernel.emitBuffering(false);
    async.flushMicrotasks();
  }
}

void main() {
  const tenSeconds = Duration(seconds: 10);
  const oneSecond = Duration(seconds: 1);

  group('1. 恢复成功后清掉旧错误', () {
    test('MovaRecovered 之后 state.error 为空', () {
      fakeAsync((async) {
        final r = _Rig();
        r.open(async);
        r.kernel.emitError('Failed to recognize file format');
        async.flushMicrotasks();
        expect(r.engine.state.error, isNotNull, reason: '失败期间错误可见');
        async.elapse(tenSeconds + oneSecond);
        r.land(async);
        expect(r.events.whereType<MovaRecovered>(), hasLength(1));
        expect(r.engine.state.error, isNull);
      });
    });

    test('没经历过失败的正常起播不受影响（不误清宿主关心的错误）', () {
      fakeAsync((async) {
        final r = _Rig();
        r.open(async);
        r.land(async);
        expect(r.events.whereType<MovaRecovered>(), isEmpty);
        expect(r.engine.state.error, isNull);
      });
    });
  });

  group('2. 放弃后缓冲标志归零', () {
    test('giveUp 后 state.buffering 为 false，并补发一次 MovaBufferChange(false)', () {
      fakeAsync((async) {
        final r = _Rig(recovery: const MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true, policy: MovaFailoverOnly()));
        r.open(async);
        r.kernel.emitBuffering(true);
        async.flushMicrotasks();
        expect(r.engine.state.buffering, isTrue);
        async.elapse(tenSeconds);
        expect(r.engine.state.error, isA<MovaGiveUpError>());
        expect(r.engine.state.buffering, isFalse);
        final changes = r.events.whereType<MovaBufferChange>().toList();
        expect(changes.last.buffering, isFalse);
      });
    });

    test('放弃时本来就不在缓冲：不多发 MovaBufferChange', () {
      fakeAsync((async) {
        final r = _Rig(recovery: const MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true, policy: MovaFailoverOnly()));
        r.open(async);
        async.elapse(tenSeconds);
        expect(r.engine.state.error, isA<MovaGiveUpError>());
        expect(r.events.whereType<MovaBufferChange>(), isEmpty);
      });
    });
  });

  group('3. 确定性失败不必等满 startTimeout', () {
    const patient = MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), 
      enabled: true,
      policy: MovaRetryThenFailover(maxRetries: 5),
    );

    test('重试加载在途时收到 END_FILE(error)：加载返回后立刻判失败并按退避重试', () {
      fakeAsync((async) {
        final r = _Rig(recovery: patient);
        r.open(async);
        async.elapse(tenSeconds); // 起播超时 -> 判失败，1s 后重试
        expect(r.failures, hasLength(1));
        r.kernel.openGate = Completer<void>(); // 让重试的那次加载挂在途
        async.elapse(oneSecond);
        expect(r.kernel.openedUris, hasLength(2));
        // 加载仍在途时，服务端 404 的 END_FILE(error) 已到。
        r.kernel.emitEndFile(MovaEndFileReason.error);
        async.flushMicrotasks();
        r.kernel.openGate!.complete();
        r.kernel.openGate = null;
        async.flushMicrotasks();
        expect(r.failures, hasLength(2), reason: '加载返回即处理，无需等 10s');
        expect(r.failures.last.fail.kind, MovaPlayFailKind.nativeEndError);
        async.elapse(oneSecond);
        expect(r.kernel.openedUris, hasLength(3), reason: '退避 1s 后立即进入下一次尝试');
      });
    });

    test('首次 open() 在途时收到 END_FILE(error)：同样不会被吞掉', () {
      fakeAsync((async) {
        final r = _Rig(recovery: patient);
        r.kernel.openGate = Completer<void>();
        r.engine.open(const MovaSource('https://h/a.m3u8'));
        async.flushMicrotasks();
        r.kernel.emitEndFile(MovaEndFileReason.error);
        async.flushMicrotasks();
        r.kernel.openGate!.complete();
        r.kernel.openGate = null;
        async.flushMicrotasks();
        expect(r.failures, hasLength(1));
        expect(r.failures.single.fail.kind, MovaPlayFailKind.nativeEndError);
        async.elapse(oneSecond);
        expect(r.kernel.openedUris, hasLength(2));
      });
    });

    test('加载在途期间的失败被新的一次 open() 取代时丢弃，不污染新会话', () {
      fakeAsync((async) {
        final r = _Rig(recovery: patient);
        r.kernel.openGate = Completer<void>();
        r.engine.open(const MovaSource('https://h/a.m3u8'));
        async.flushMicrotasks();
        r.kernel.emitEndFile(MovaEndFileReason.error);
        async.flushMicrotasks();
        final gate = r.kernel.openGate!;
        r.kernel.openGate = null;
        r.engine.open(const MovaSource('https://h/b.m3u8'));
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        expect(r.failures, isEmpty);
      });
    });
  });
}
