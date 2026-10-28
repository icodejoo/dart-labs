import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_kernel.dart';
import '../../support/keep_alive_rig.dart';

/// How often the playing kernel reports a position while a test waits.
///
/// 测试等待期间在播内核上报位置的间隔。
const _tick = Duration(milliseconds: 100);

/// Advances the fake clock by [total] in [_tick] steps while the kernel keeps
/// playing (position ticks only), like mpv does after `vid` flips back.
///
/// 在 [total] 内按 [_tick] 步进假时钟，同时让内核继续在播（只有位置回调），
/// 就像 `vid` 切回之后的 mpv。
void _playOn(KeepAliveRig r, FakeKernel k, Duration total) {
  var played = Duration.zero;
  while (played < total) {
    played += _tick;
    k.emitPosition(played);
    r.async.elapse(_tick);
    r.settle();
  }
}

/// H42: on Android and Windows a muted hold's wake-up produces neither a size
/// change nor a native RESTART, so the resume gate never sees a landing signal
/// and ends on `resumeTimeout` with signal `grace` and `elapsed == resumeTimeout`
/// (15/15 on Android, 18/18 on Windows). The fake kernel's default
/// `wakeSignal: none` models that; these tests pin the engine's behavior under it.
///
/// H42：Android 与 Windows 上静音待机唤醒既不产生尺寸变化也没有原生 RESTART，恢复
/// 闸门永远等不到落地信号，只能在 `resumeTimeout` 到点后以 `grace` 收尾，
/// `elapsed == resumeTimeout`（Android 15/15、Windows 18/18）。假内核默认的
/// `wakeSignal: none` 模拟这一点；这里固定引擎在此情形下的行为。
void main() {
  test('H42: with no wake signal at all the resume stays resuming until resumeTimeout, then ends as grace', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      expect(k.wakeSignal, FakeWakeSignal.none, reason: 'the realistic default');
      final r = KeepAliveRig(async, k)..playLive();
      r.land();
      r.keepAlive(true);
      expect(r.keepAlive(false), MovaKeepAlivePhase.resuming);

      _playOn(r, k, const Duration(milliseconds: 4900));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.resuming);
      expect(r.resumes, isEmpty);

      _playOn(r, k, const Duration(milliseconds: 200));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.off);
      expect(r.resumes, hasLength(1));
      expect(r.resumes.single.signal, MovaFirstFrameSignal.grace);
      expect(r.resumes.single.elapsed, const Duration(seconds: 5));
      expect(r.resumes.single.from, MovaKeepAliveMode.muted);
    });
  });

  test('H42: elapsed tracks a custom resumeTimeout, not the measured time to a real picture', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(
        async,
        k,
        keepAlive: const MovaKeepAliveConfig(resumeTimeout: Duration(seconds: 2)),
      )..playLive();
      r.land();
      r.keepAlive(true);
      r.keepAlive(false);
      _playOn(r, k, const Duration(milliseconds: 2100));
      expect(r.resumes.single.signal, MovaFirstFrameSignal.grace);
      expect(r.resumes.single.elapsed, const Duration(seconds: 2));
    });
  });

  test('H42: the silent wake neither re-announces a first frame nor loses the rendered flag', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive();
      r.land();
      final firstFrames = r.events.whereType<MovaFirstFrame>().length;
      r.keepAlive(true);
      r.keepAlive(false);
      _playOn(r, k, const Duration(seconds: 6));
      expect(r.events.whereType<MovaFirstFrame>().length, firstFrames);
      expect(r.engine.state.rendered, isTrue);
      expect(r.engine.state.playing, isTrue);
    });
  });

  test('H42: a late size after the timeout does not produce a second resume', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive();
      r.land();
      r.keepAlive(true);
      r.keepAlive(false);
      _playOn(r, k, const Duration(seconds: 5));
      k.emitSize(1280, 720);
      r.settle();
      expect(r.resumes, hasLength(1));
    });
  });

  test('a kernel that does push a size on wake (reopen path) lands the resume before the timeout', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..wakeSignal = FakeWakeSignal.size;
      final r = KeepAliveRig(async, k)..playLive();
      r.land();
      r.keepAlive(true);
      r.keepAlive(false);
      r.settle();
      expect(r.resumes, hasLength(1));
      expect(r.resumes.single.signal, MovaFirstFrameSignal.size);
      expect(r.resumes.single.elapsed, lessThan(const Duration(seconds: 5)));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.off);
    });
  });

  test('a kernel that pushes a native RESTART on wake lands the resume as restart', () {
    fakeAsync((async) {
      final k = FakeKeepAliveStatsKernel()
        ..nativeRestartAvailable = true
        ..wakeSignal = FakeWakeSignal.restart;
      final r = KeepAliveRig(async, k)..playLive();
      k.emitRestart();
      r.settle();
      r.keepAlive(true);
      r.keepAlive(false);
      r.settle();
      expect(r.resumes.single.signal, MovaFirstFrameSignal.restart);
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.off);
    });
  });
}
