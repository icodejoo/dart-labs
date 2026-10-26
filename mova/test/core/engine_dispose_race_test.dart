import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/interceptor/interceptor.dart';
import 'package:mova/src/core/model/orientation.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/platform/ports.dart';
import 'package:mova/src/core/swap/retirable.dart';

import '../support/fake_kernel.dart';

/// Kernel whose `setRate` suspends until [gate] completes.
///
/// `setRate` 会挂起到 [gate] 完成的假内核。
class _GatedRateKernel extends FakeKernel {
  /// Completer that releases the suspended `setRate`.
  ///
  /// 放行被挂起的 `setRate` 的 completer。
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> setRate(double rate) async {
    await gate.future;
    await super.setRate(rate);
  }
}

/// Hook whose `beforeOpen` suspends until [gate] completes, then allows.
///
/// `beforeOpen` 会挂起到 [gate] 完成再放行的拦截器。
class _GatedOpenHook extends MovaHook {
  /// Completer that releases the suspended `beforeOpen`.
  ///
  /// 放行被挂起的 `beforeOpen` 的 completer。
  final Completer<void> gate = Completer<void>();

  @override
  Future<bool> beforeOpen(MovaSource source) async {
    await gate.future;
    return true;
  }
}

/// Orientation port with a gated `apply` and a `reset` counter.
///
/// `apply` 可挂起、并统计 `reset` 次数的方向端口。
class _GatedOrientationPort implements MovaOrientationPort {
  /// When non-null, `apply` waits on it.
  ///
  /// 非空时 `apply` 会等待它。
  Completer<void>? gate;

  /// How many times `reset` was called.
  ///
  /// `reset` 被调用的次数。
  int resets = 0;

  @override
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
    required MovaOrientation orientation,
  }) async {
    await gate?.future;
  }

  @override
  Future<void> reset() async {
    resets++;
  }
}

void main() {
  test('open() suspended in beforeOpen does not touch kernel after dispose',
      () async {
    final k = FakeKernel();
    final hook = _GatedOpenHook();
    final e = MovaEngine(kernel: k, interceptors: [hook]);
    final pending = e.open(const MovaSource('https://host/a.mp4'));
    await Future<void>.delayed(Duration.zero);
    await e.dispose();
    hook.gate.complete();
    await pending;
    expect(k.calls, isNot(contains('open')));
  });

  test('setRate resuming after dispose does not throw on closed events',
      () async {
    final k = _GatedRateKernel();
    final e = MovaEngine(kernel: k);
    final pending = e.setRate(1.5);
    await Future<void>.delayed(Duration.zero);
    await e.dispose();
    k.gate.complete();
    await pending; // 不应抛 StateError
  });

  test('setFullscreen resuming after dispose does not throw on closed events',
      () async {
    final port = _GatedOrientationPort()..gate = Completer<void>();
    final e = MovaEngine(kernel: FakeKernel(), orientation: port);
    final pending = e.setFullscreen(true);
    await Future<void>.delayed(Duration.zero);
    await e.dispose();
    port.gate!.complete();
    await pending; // 不应抛 StateError
  });

  test('dispose resets orientation port when fullscreen', () async {
    final port = _GatedOrientationPort();
    final e = MovaEngine(kernel: FakeKernel(), orientation: port);
    await e.setFullscreen(true);
    await e.dispose();
    expect(port.resets, 1);
  });

  test('dispose resets orientation port when orientation is forced', () async {
    final port = _GatedOrientationPort();
    final e = MovaEngine(kernel: FakeKernel(), orientation: port);
    await e.setOrientation(MovaOrientation.landscape);
    await e.dispose();
    expect(port.resets, 1);
  });

  test('dispose does not reset orientation port when untouched', () async {
    final port = _GatedOrientationPort();
    final e = MovaEngine(kernel: FakeKernel(), orientation: port);
    await e.dispose();
    expect(port.resets, 0);
  });

  test('retired fullscreen engine dispose skips orientation reset', () async {
    final port = _GatedOrientationPort();
    final e = MovaEngine(kernel: FakeKernel(), orientation: port);
    await e.setFullscreen(true);
    expect(e, isA<MovaHandoffRetirable>());
    (e as MovaHandoffRetirable).markRetired();
    await e.dispose();
    expect(port.resets, 0);
  });
}
