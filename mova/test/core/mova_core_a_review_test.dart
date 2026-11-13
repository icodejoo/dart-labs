import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/testing/hooks.dart';

import '../support/fake_kernel.dart';

/// Fails selected seeks after an optional asynchronous gate.
///
/// 经过可选异步门闩后令指定 seek 失败。
class _SeekKernel extends FakeKernel {
  Completer<void>? gate;
  Duration? failTarget;

  /// Keeps real fake-kernel recording and fails only [failTarget].
  ///
  /// 保留假内核的调用记录，仅令 [failTarget] 失败。
  @override
  Future<void> seek(Duration position) async {
    await super.seek(position);
    if (position != failTarget) return;
    await gate?.future;
    throw StateError('seek failed');
  }
}

/// Rejects a reentrant open while preserving the currently accepted source.
///
/// 拒绝重入的 open，并保留当前已接受的源。
class _RejectHook extends MovaHook {
  /// Accepts only the original source.
  ///
  /// 只接受原始源。
  @override
  Future<bool> beforeOpen(MovaSource source) async =>
      !source.uri.contains('no');
}

/// Requests an immediate automatic downshift on a buffering rise.
///
/// 缓冲上升沿立即请求自动降档。
class _Abr implements IMovaAbrPolicy {
  /// Returns the buffering flag as the downshift decision.
  ///
  /// 以缓冲标记作为降档决策。
  @override
  bool onBuffering(bool buffering) => buffering;

  /// Has no state to reset.
  ///
  /// 没有需要重置的状态。
  @override
  void reset() {}
}

/// Verifies seek cleanup, pre-frame recovery and background error ownership.
///
/// 验证 seek 清理、首帧前恢复与后台错误归属。
void main() {
  test('coreA3 failed public seek releases position filtering', () async {
    final kernel = _SeekKernel()..failTarget = const Duration(seconds: 40);
    final mova = Mova(
      kernel: kernel,
      fetcher: const MovaTestHttpFetch(),
    );
    addTearDown(mova.dispose);
    await mova.open(const MovaSource('https://h/old.mp4'));
    kernel.emitDuration(const Duration(minutes: 2));
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      mova.seek(const Duration(seconds: 40)),
      throwsStateError,
    );
    kernel.emitPosition(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
    expect(mova.progressValue.position, const Duration(seconds: 3));
  });

  test('coreA3 stale seek failure preserves the newer seek filter', () async {
    final kernel = _SeekKernel()
      ..failTarget = const Duration(seconds: 40)
      ..gate = Completer<void>();
    final mova = Mova(
      kernel: kernel,
      fetcher: const MovaTestHttpFetch(),
    );
    addTearDown(mova.dispose);
    await mova.open(const MovaSource('https://h/old.mp4'));
    kernel.emitDuration(const Duration(minutes: 2));
    await Future<void>.delayed(Duration.zero);
    final failed = expectLater(
      mova.seek(const Duration(seconds: 40)),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    await mova.seek(const Duration(seconds: 60));
    kernel.gate!.complete();
    await failed;
    kernel.emitPosition(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
    expect(mova.progressValue.position, const Duration(seconds: 60));
    kernel.emitPosition(const Duration(seconds: 60));
    await Future<void>.delayed(Duration.zero);
  });

  for (final parked in [false, true]) {
    test(
      'coreA4 rejected reentrant open clears ${parked ? 'parked' : 'pending'} seek',
      () {
        fakeAsync((clock) {
          final kernel = FakeKernel();
          final mova = Mova(
            kernel: kernel,
            fetcher: const MovaTestHttpFetch(),
            interceptors: [_RejectHook()],
          );
          mova.open(const MovaSource('https://h/old.mp4'));
          clock.flushMicrotasks();
          if (!parked) kernel.emitDuration(const Duration(minutes: 2));
          clock.flushMicrotasks();
          mova.events.listen((event) {
            if (event is MovaSeek) {
              unawaited(mova.open(const MovaSource('https://h/no.mp4')));
            }
          });
          mova.seek(const Duration(seconds: 40));
          clock.flushMicrotasks();
          expect(kernel.calls, isNot(contains('seek')));
          kernel.emitDuration(const Duration(minutes: 2));
          kernel.emitPosition(const Duration(seconds: 3));
          clock.flushMicrotasks();
          expect(mova.progressValue.position, const Duration(seconds: 3));
          clock.elapse(const Duration(seconds: 2));
          expect(kernel.calls, isNot(contains('seek')));
          expect(kernel.lastUri, 'https://h/old.mp4');
          mova.dispose();
          clock.flushMicrotasks();
        });
      },
    );
  }

  for (final parked in [false, true]) {
    test(
      'coreA9 pre-frame ${parked ? 'parked' : 'issued'} user seek survives retry',
      () {
        fakeAsync((clock) {
          final kernel = FakeKernel();
          final mova = Mova(
            kernel: kernel,
            fetcher: const MovaTestHttpFetch(),
            options: const MovaOpts(
              recovery: MovaRecoveryOpts(
                enabled: true,
                startTimeout: Duration(seconds: 10),
              ),
            ),
          );
          mova.open(
            const MovaSource('https://h/old.mp4', start: Duration(seconds: 10)),
          );
          clock.flushMicrotasks();
          if (!parked) kernel.emitDuration(const Duration(minutes: 2));
          clock.flushMicrotasks();
          mova.seek(const Duration(seconds: 40));
          clock.flushMicrotasks();
          expect(mova.state.rendered, isFalse);
          clock.elapse(const Duration(seconds: 11));
          expect(kernel.openedUris, hasLength(2));
          kernel.emitDuration(const Duration(minutes: 2));
          kernel.emitBuffering(true);
          kernel.emitBuffering(false);
          clock.flushMicrotasks();
          expect(kernel.lastSeek, const Duration(seconds: 40));
          mova.dispose();
          clock.flushMicrotasks();
        });
      },
    );
  }

  for (final operation in ['downshift', 'live edge']) {
    test(
      'coreA11 automatic $operation reports load failure without uncaught error',
      () {
        fakeAsync((clock) {
          final kernel = FakeKernel();
          final live = operation == 'live edge';
          final mova = Mova(
            kernel: kernel,
            fetcher: const MovaTestHttpFetch(),
            options: MovaOpts(
              abr: MovaAbrOpts(policy: _Abr()),
              live: const MovaLiveOpts(
                seekMode: MovaLiveSeekMode.dvr,
                dvrWindow: Duration(minutes: 2),
                autoBackToLiveOnStall: true,
                backToLive: MovaBackToLive.reopen,
              ),
            ),
          );
          final errors = <MovaErrorEvent>[];
          mova.events
              .where((e) => e is MovaErrorEvent)
              .cast<MovaErrorEvent>()
              .listen(errors.add);
          mova.open(
            MovaSource(
              'https://h/old.mp4',
              type: live ? MovaStreamType.live : MovaStreamType.vod,
            ),
          );
          clock.flushMicrotasks();
          kernel.emitDuration(const Duration(minutes: 2));
          if (live) kernel.emitPosition(const Duration(minutes: 2));
          kernel.emitBuffering(true);
          kernel.emitBuffering(false);
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 11));
          if (!live) {
            const high = MovaQuality(
              label: 'high',
              uri: 'https://h/high.mp4',
              height: 1080,
            );
            const low = MovaQuality(
              label: 'low',
              uri: 'https://h/low.mp4',
              height: 480,
            );
            mova.debugSetQualities(const [high, low], current: high);
          } else {
            kernel.emitPosition(const Duration(seconds: 10));
            clock.flushMicrotasks();
            expect(mova.state.timeshiftBehind, isNotNull);
          }
          kernel.openError = StateError('automatic load failed');
          kernel.emitBuffering(true);
          clock.flushMicrotasks();
          expect(kernel.openedUris, hasLength(2));
          expect(errors.where((e) => e.fatal), hasLength(1));
          expect(mova.state.error, isNotNull);
          mova.dispose();
          clock.flushMicrotasks();
        });
      },
    );
  }
}
