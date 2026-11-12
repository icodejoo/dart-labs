import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_kernel.dart';
import '../support/gated.dart';

/// 拦住播放和跳转，并拒绝指定源的门控钩子。
class _Hook extends MovaHook {
  /// 放行当前用户操作的闸门。
  final gate = Completer<void>();

  /// 共享严格日志，确认交错操作已经进入钩子。
  final log = CommandLog();

  @override
  Future<bool> beforeOpen(MovaSource source) async =>
      !source.uri.endsWith('no.mp4');

  @override
  Future<bool> beforePlay() async {
    log.record(0, 'play');
    await gate.future;
    return true;
  }

  @override
  Future<Duration?> beforeSeek(Duration target) async {
    log.record(0, 'seek');
    await gate.future;
    return target;
  }
}

/// 让流和钩子的微任务完成。
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  for (final verb in ['play', 'seek']) {
    test('A06 rejected open preserves pending $verb', () async {
      final k = FakeKernel();
      final hook = _Hook();
      final e = createMovaEngine(
        kernel: k,
        pip: MovaNoopPipPort(),
        orientation: MovaNoopOrientationPort(),
        brightness: MovaFallbackBrightnessPort(),
        interceptors: [hook],
      );
      addTearDown(e.dispose);
      await e.open(const MovaSource('https://host/a.mp4'), autoPlay: false);
      k.emitDuration(const Duration(minutes: 2));
      await _flush();
      final pending = verb == 'play'
          ? e.play()
          : e.seek(const Duration(seconds: 12));
      await _flush();
      expect(hook.log.entries.single.verb, verb);
      expect(await e.open(const MovaSource('https://host/no.mp4')), isFalse);
      hook.gate.complete();
      await pending;
      expect(k.calls, contains(verb));
      if (verb == 'seek') expect(k.lastSeek, const Duration(seconds: 12));
    });
  }

  test('A06 play during paused load is replayed after open', () async {
    final k = FakeKernel()..openGate = Completer<void>();
    final e = createMovaEngine(
      kernel: k,
      pip: MovaNoopPipPort(),
      orientation: MovaNoopOrientationPort(),
      brightness: MovaFallbackBrightnessPort(),
    );
    addTearDown(e.dispose);
    final pending = e.open(
      const MovaSource('https://host/a.mp4'),
      autoPlay: false,
    );
    await _flush();
    expect(k.lastPlay, isFalse);
    await e.play();
    final before = k.calls.where((v) => v == 'play').length;
    k.openGate!.complete();
    await pending;
    expect(k.calls.where((v) => v == 'play').length, before + 1);
  });

  test('A06 pause during playing load is replayed after open', () async {
    final k = FakeKernel()..openGate = Completer<void>();
    final e = createMovaEngine(
      kernel: k,
      pip: MovaNoopPipPort(),
      orientation: MovaNoopOrientationPort(),
      brightness: MovaFallbackBrightnessPort(),
    );
    addTearDown(e.dispose);
    final pending = e.open(const MovaSource('https://host/a.mp4'));
    await _flush();
    await e.pause();
    final before = k.calls.where((v) => v == 'pause').length;
    k.openGate!.complete();
    await pending;
    expect(k.calls.where((v) => v == 'pause').length, before + 1);
  });

  test(
    'A06 keepAlive requested load remains paused despite play intent',
    () async {
      final k = FakeKernel();
      final e = createMovaEngine(
        kernel: k,
        pip: MovaNoopPipPort(),
        orientation: MovaNoopOrientationPort(),
        brightness: MovaFallbackBrightnessPort(),
      );
      addTearDown(e.dispose);
      await e.setKeepAlive(true);
      await e.open(const MovaSource('https://host/a.mp4'));
      expect(e.state.playbackIntent, isTrue);
      expect(k.lastPlay, isFalse);
      expect(k.calls.where((v) => v == 'play'), isEmpty);
    },
  );
}

