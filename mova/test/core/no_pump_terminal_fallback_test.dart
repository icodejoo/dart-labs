import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/attempt_event_kernel.dart';
import 'package:mova/src/core/kernel/classified_error_kernel.dart';
import 'package:mova/src/core/model/playback_error.dart';

import '../support/fake_kernel.dart';
import '../support/keep_alive_rig.dart';

/// 提供错误级日志，保留子系统及地址供兜底判断。
mixin _Logs implements MovaClassifiedErrorKernel {
  /// 原始日志错误流。
  final classifiedErrors = StreamController<MovaKernelError>.broadcast();

  /// 供引擎读取的分级错误端口。
  @override
  Stream<MovaKernelError> get kernelErrors => classifiedErrors.stream;

  /// 注入一行错误级日志。
  void fail(String text, [String prefix = 'stream']) =>
      classifiedErrors.add(MovaKernelError(text, prefix));
}

/// 不具备 StatsProbe，模拟直接构造引擎时没有原生事件端口。
class _NoProbeKernel extends FakeKernel with _Logs {
  /// 关闭注入日志及普通内核流。
  @override
  Future<void> dispose() async {
    await classifiedErrors.close();
    await super.dispose();
  }
}

/// 可在打开后改变泵状态，END_FILE 独立于 RESTART 可用性。
class _PumpKernel extends FakeStatsKernel with _Logs implements MovaAttemptEventKernel {
  /// 当前加载尝试编号。
  int attempt = 0;

  /// 模拟异步注册或泵失效。
  @override
  bool endFileAvailable = false;

  /// 沿用假内核的结束流，投递时附上当前尝试。
  @override
  Stream<MovaAttemptEnd> get attemptEnds =>
      endFiles.map((reason) => (attempt: attempt, reason: reason));

  /// 记录即将打开的尝试。
  @override
  void prepareAttempt(int value) => attempt = value;

  /// 关闭注入日志及统计流。
  @override
  Future<void> dispose() async {
    await classifiedErrors.close();
    await super.dispose();
  }
}

/// 待机能力结合无泵日志，验证兜底也保持静默。
class _KeepAliveKernel extends FakeKeepAliveStatsKernel with _Logs {
  /// 关闭注入日志及待机内核流。
  @override
  Future<void> dispose() async {
    await classifiedErrors.close();
    await super.dispose();
  }
}

/// 收集错误事件，验证诊断与终结的次数。
List<MovaErrorEvent> _errors(MovaEngine engine) {
  final result = <MovaErrorEvent>[];
  engine.events.where((v) => v is MovaErrorEvent).cast<MovaErrorEvent>().listen(result.add);
  return result;
}

/// 无平台端口的引擎，关闭自动隐藏和网络探测。
MovaEngine _engine(FakeKernel kernel, {bool recovery = false}) => MovaEngine(
  kernel: kernel,
  options: MovaOpts(
    controls: const MovaCtrlsConfig(autoHide: false),
    abr: const MovaAbrConfig(probeVariants: false),
    recovery: MovaRecoveryConfig(enabled: recovery, policy: const MovaFailoverOnly()),
  ),
);

/// 验证无泵的主文件地址兜底及其排除边界。
void main() {
  const mainUri = 'https://h/main.m3u8';
  for (final prefix in ['stream', 'cplayer', 'ffmpeg']) {
    test('F-I no StatsProbe main open error terminates prefix=$prefix', () async {
      final k = _NoProbeKernel();
      final e = _engine(k);
      final errors = _errors(e);
      await e.open(const MovaSource(mainUri));
      k.fail('Failed to open $mainUri: 404 / connection refused / certificate error', prefix);
      await pumpEventQueue();
      expect(e.state.error, isNotNull);
      expect(errors.single.fatal, isTrue);
      expect(k.calls.where((v) => v == 'pause'), hasLength(1));
      k.fail('Failed to open $mainUri', prefix);
      await pumpEventQueue();
      expect(errors.map((v) => v.fatal), [true, false]);
      await e.dispose();
    });
  }

  for (final address in ['https://h/captions.srt', 'https://h/audio.m4a', 'https://h/segment-1.ts']) {
    test('F-I auxiliary address remains diagnostic $address', () async {
      final k = _NoProbeKernel();
      final e = _engine(k);
      final errors = _errors(e);
      await e.open(const MovaSource(mainUri));
      k.fail('Failed to open $address');
      await pumpEventQueue();
      expect(e.state.error, isNull);
      expect(errors.single.fatal, isFalse);
      expect(k.calls, isNot(contains('pause')));
      await e.dispose();
    });
  }

  for (final availableAtError in [true, false]) {
    test('F-I checks pump at error delivery available=$availableAtError', () async {
      final k = _PumpKernel()..endFileAvailable = !availableAtError;
      final e = _engine(k);
      final errors = _errors(e);
      await e.open(const MovaSource(mainUri));
      k.endFileAvailable = availableAtError;
      // RESTART 默认不可用，不能据此误判 END_FILE 也不可用。
      expect(k.nativeRestartAvailable, isFalse);
      k.fail('Failed to open $mainUri');
      await pumpEventQueue();
      expect(errors.single.fatal, !availableAtError);
      if (availableAtError) {
        expect(e.state.error, isNull);
        k.emitEndFile(MovaEndFileReason.error);
        await pumpEventQueue();
        expect(errors.map((v) => v.fatal), [false, true]);
      }
      expect(e.state.error, isNotNull);
      await e.dispose();
    });
  }

  test('F-I missing local main file terminates without a pump', () async {
    final k = _NoProbeKernel();
    final e = _engine(k);
    await e.open(const MovaSource('file:///missing.mp4'));
    k.fail('Failed to open file:///missing.mp4');
    await pumpEventQueue();
    expect(e.state.error, isNotNull);
    await e.dispose();
  });

  test('F-I unrelated prefix and empty active URI cannot terminate', () async {
    final k = _NoProbeKernel();
    final e = _engine(k);
    final errors = _errors(e);
    k.fail('Failed to open $mainUri');
    await pumpEventQueue();
    await e.open(const MovaSource(mainUri));
    k.fail('Failed to open $mainUri', 'vd');
    await pumpEventQueue();
    expect(errors.every((v) => !v.fatal), isTrue);
    expect(e.state.error, isNull);
    await e.dispose();
  });

  test('F-I legacy error with explicit stream prefix terminates', () async {
    final k = FakeKernel();
    final e = _engine(k);
    await e.open(const MovaSource(mainUri));
    k.emitError('stream: Failed to open $mainUri');
    await pumpEventQueue();
    expect(e.state.error, isNotNull);
    await e.dispose();
  });

  test('F-I main error during open defers terminal pause and keeps prefix', () async {
    final k = _NoProbeKernel()..openGate = Completer<void>();
    final e = _engine(k);
    final errors = _errors(e);
    final opening = e.open(const MovaSource(mainUri));
    await pumpEventQueue();
    k.fail('Failed to open $mainUri');
    await pumpEventQueue();
    expect(e.state.error, isNull);
    expect(k.calls, isNot(contains('pause')));
    k.openGate!.complete();
    await opening;
    await pumpEventQueue();
    expect(errors.single.fatal, isTrue);
    expect(errors.single.code, 'stream');
    expect(e.state.error, isNotNull);
    await e.dispose();
  });

  test('F-I no pump main error uses recovery giveUp when enabled', () async {
    final k = _PumpKernel();
    final e = _engine(k, recovery: true);
    final errors = _errors(e);
    await e.open(const MovaSource(mainUri));
    k.fail('Failed to open $mainUri');
    await pumpEventQueue();
    expect(errors.single.fatal, isTrue);
    expect(e.state.error, isA<MovaGiveUpError>());
    await e.dispose();
  });

  test('F-I no pump holding main error is quiet and wake reopens', () {
    fakeAsync((async) {
      final k = _KeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive(uri: mainUri)..land();
      r.keepAlive(true);
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.holding);
      final opens = k.openedUris.length;
      k.fail('Failed to open $mainUri');
      r.settle();
      expect(r.events.whereType<MovaErrorEvent>(), isEmpty);
      expect(r.engine.state.error, isNull);
      expect(r.changes.last.reason, MovaKeepAliveReason.failed);
      r.keepAlive(false);
      expect(k.openedUris.length, opens + 1);
      r.engine.dispose();
      r.settle();
    });
  });
}
