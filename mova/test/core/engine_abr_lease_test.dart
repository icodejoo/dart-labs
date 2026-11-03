import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_kernel.dart';
import '../support/gated.dart';

/// 记录 ABR 实际收到的缓冲，直接验证 seek 和换档的屏蔽边界。
class _Policy implements MovaAbrPolicy {
  /// 已交给策略的观测。
  final values = <bool>[];

  @override
  bool onBuffering(bool buffering) {
    values.add(buffering);
    return false;
  }

  @override
  void reset() {}
}

/// ABR 租约测试的真实引擎夹具。
class _Rig {
  /// 使用 [clock] 的假时钟，并注入不触网的测试端口。
  _Rig(this.clock, {bool recovery = false, bool live = false}) {
    e = createMovaEngine(
      kernel: k,
      brightness: MovaFallbackBrightnessPort(),
      pip: MovaNoopPipPort(),
      orientation: MovaNoopOrientationPort(),
      options: MovaOpts(
        controls: const MovaCtrlsConfig(autoHide: false),
        abr: MovaAbrConfig(policy: policy),
        recovery: MovaRecoveryConfig(enabled: recovery),
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.timeshift,
          dvrWindow: const Duration(minutes: 10),
          urlBuilder: (uri, behind, now) => '$uri?behind=${behind.inSeconds}',
        ),
      ),
    );
    e.open(MovaSource('https://h/video.mp4',
        type: live ? MovaStreamType.live : MovaStreamType.vod));
    clock.flushMicrotasks();
    k.emitDuration(const Duration(minutes: 5));
    k.emitPosition(const Duration(seconds: 41));
    k.emitPosition(const Duration(seconds: 42));
    clock.flushMicrotasks();
    policy.values.clear();
  }

  /// 虚拟时钟。
  final FakeAsync clock;

  /// 可门控加载的内核。
  final k = FakeKernel();

  /// 可观察的策略。
  final policy = _Policy();

  /// 被测引擎。
  late final MovaEngine e;

  /// 严格动作日志。
  final log = CommandLog();

  /// 向策略入口推入一轮缓冲。
  void buffer() {
    k.emitBuffering(true);
    k.emitBuffering(false);
    clock.flushMicrotasks();
  }

  /// 发起 [label] 档加载并记录完成顺序。
  void quality(String label) {
    e.switchQuality(MovaQuality(label: label, uri: 'https://h/$label.mp4'))
        .then((_) => log.record(0, label),
          onError: (Object error) => log.record(0, 'failed:$label'));
    clock.flushMicrotasks();
  }

  /// 销毁全部异步资源。
  void close() {
    e.dispose();
    clock.flushMicrotasks();
    expect(clock.pendingTimers, isEmpty);
  }
}

void main() {
  for (final quality in [false, true]) {
    test('F-E live ${quality ? "quality" : "timeshift"} ignores stop false until true then false', () {
      fakeAsync((clock) {
        final r = _Rig(clock, live: true);
        if (quality) {
          r.quality('live');
        } else {
          r.e.seek(const Duration(minutes: 7));
          clock.flushMicrotasks();
        }
        r.k.emitBuffering(false);
        clock.flushMicrotasks();
        expect(r.policy.values, isEmpty);
        r.k.emitBuffering(true);
        clock.flushMicrotasks();
        expect(r.policy.values, isEmpty);
        r.k.emitBuffering(false);
        clock.flushMicrotasks();
        expect(r.policy.values, isEmpty);
        r.buffer();
        expect(r.policy.values, [true, false]);
        r.close();
      });
    });

    test('F-E live ${quality ? "quality" : "timeshift"} without true releases at ten seconds', () {
      fakeAsync((clock) {
        final r = _Rig(clock, live: true);
        if (quality) {
          r.quality('live');
        } else {
          r.e.seek(const Duration(minutes: 7));
          clock.flushMicrotasks();
        }
        r.k.emitBuffering(false);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 9));
        r.k.emitBuffering(false);
        clock.flushMicrotasks();
        expect(r.policy.values, isEmpty);
        clock.elapse(const Duration(seconds: 1));
        r.buffer();
        expect(r.policy.values, [true, false]);
        r.close();
      });
    });
  }

  test('A11 old successful quality completion cannot release newer lease', () {
    fakeAsync((clock) {
      final r = _Rig(clock);
      final first = r.k.openGate = Completer<void>();
      r.quality('first');
      r.k.openGate = null;
      r.quality('second');
      first.complete();
      clock.flushMicrotasks();
      expect(r.log.entries.map((v) => v.verb), ['second', 'first']);
      r.buffer();
      expect(r.policy.values, isEmpty);
      r.close();
    });
  });

  test('A11 old failed quality cleanup cannot release newer lease', () {
    fakeAsync((clock) {
      final r = _Rig(clock, recovery: true);
      final first = r.k.openGate = Completer<void>();
      r.quality('first');
      r.k.openGate = null;
      r.quality('second');
      r.k.openError = StateError('old failed');
      first.complete();
      clock.flushMicrotasks();
      r.k.openError = null;
      r.buffer();
      expect(r.policy.values, isEmpty);
      expect(r.e.state.currentQuality!.label, 'second');
      r.close();
    });
  });

  test('A11 user seek buffering is excluded until verification settles', () {
    fakeAsync((clock) {
      final r = _Rig(clock);
      r.k.echoSeeks = true;
      r.e.seek(const Duration(seconds: 80));
      clock.flushMicrotasks();
      r.buffer();
      expect(r.policy.values, isEmpty);
      clock.elapse(r.e.debugResumeVerifyDelay);
      r.buffer();
      expect(r.policy.values, [true, false]);
      r.close();
    });
  });

  test('A11 parked user seek also excludes buffering before duration arrives', () {
    fakeAsync((clock) {
      final r = _Rig(clock);
      r.e.open(const MovaSource('https://h/new.mp4'));
      clock.flushMicrotasks();
      r.e.seek(const Duration(seconds: 80));
      clock.flushMicrotasks();
      r.buffer();
      expect(r.policy.values, isEmpty);
      r.close();
    });
  });

  test('A11 renewed lease retains its own unchanged ten second cap', () {
    fakeAsync((clock) {
      final r = _Rig(clock);
      r.quality('first');
      clock.elapse(const Duration(seconds: 6));
      r.quality('second');
      clock.elapse(const Duration(seconds: 4));
      r.buffer();
      expect(r.policy.values, isEmpty);
      clock.elapse(const Duration(seconds: 6));
      r.buffer();
      expect(r.policy.values, [true, false]);
      r.close();
    });
  });

  test('A11 new source revokes old lease and late cleanup leaves new seek held', () {
    fakeAsync((clock) {
      final r = _Rig(clock);
      final old = r.k.openGate = Completer<void>();
      r.quality('old');
      r.k.openGate = null;
      r.e.open(const MovaSource('https://h/new.mp4'));
      clock.flushMicrotasks();
      r.buffer();
      expect(r.policy.values, [true, false]);
      r.policy.values.clear();
      r.e.seek(const Duration(seconds: 80));
      clock.flushMicrotasks();
      old.complete();
      clock.flushMicrotasks();
      r.buffer();
      expect(r.policy.values, isEmpty);
      r.close();
    });
  });
}
