import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/testing/hooks.dart';

import '../support/fake_kernel.dart';
import '../support/fake_api.dart';

/// 模拟首帧信号已到、mpv 当前帧仍不可读的内核。
class _CaptureKernel extends FakeKernel {
  int shots = 0;
  Future<Uint8List?> Function() capture = () async => null;

  @override
  Future<Uint8List?> screenshot() {
    shots++;
    return capture();
  }
}

/// 可控截图的自定义引擎，用于验证真实 cutover 提交边界。
class _CaptureApi extends FakeMovaApi implements MovaFrameCapture {
  _CaptureApi()
    : super(options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
  final gate = Completer<Uint8List?>();
  @override
  Future<Uint8List?> screenshot() => gate.future;
}

/// Exercises bounded capture and cutover ownership.
///
/// 验证有界截图与切换归属。
void main() {
  test('cutover 提交后丢弃旧生效引擎截图，后续截图转发新引擎', () async {
    final made = <_CaptureApi>[];
    final api = MovaCutoverEngine(
      engineFactory: () {
        final engine = _CaptureApi();
        made.add(engine);
        return engine;
      },
    );
    final oldShot = api.screenshot();
    await api.prepare(
      const MovaSource('https://h/new.mp4'),
      cue: const MovaWarmCue(
        remaining: Duration(seconds: 1),
        total: Duration(seconds: 10),
      ),
    );
    expect(made, hasLength(2));
    const signal = MovaProg(
      position: Duration(seconds: 5),
      buffer: Duration(seconds: 6),
    );
    for (var i = 0; i < 2; i++) {
      made.last.pushProgress(signal);
      await Future<void>.delayed(Duration.zero);
    }
    expect(await api.commit(), isTrue);
    expect(api.active, same(made.last));
    made.first.gate.complete(Uint8List.fromList([1]));
    expect(await oldShot, isNull);
    made.last.gate.complete(Uint8List.fromList([2]));
    expect(await api.screenshot(), [2]);
    await api.dispose();
  });

  test('cutover allows the inner two-second deadline to settle', () {
    fakeAsync((clock) {
      final active = _CaptureApi();
      final api = MovaCutoverEngine(engineFactory: () => active);
      Uint8List? result;
      var done = false;
      api.screenshot().then((image) {
        result = image;
        done = true;
      });
      Timer(
        const Duration(seconds: 2),
        () => active.gate.complete(Uint8List.fromList([7])),
      );
      clock.elapse(const Duration(seconds: 2));
      expect(done, isTrue);
      expect(result, [7]);
      api.dispose();
      clock.flushMicrotasks();
    });
  });

  for (final cutover in [false, true]) {
    final name = cutover ? 'cutover' : '普通';
    for (final succeeds in [true, false]) {
      test('$name playing capture retries within total budget: $succeeds', () {
        fakeAsync((clock) {
          final kernel = _CaptureKernel();
          final engine = MovaEngine(
            kernel: kernel,
            fetcher: const MovaTestHttpFetch(),
          );
          final MovaApi api = cutover
              ? MovaCutoverEngine(engineFactory: () => engine)
              : engine;
          final pool = MovaFeedEnginePool(engineFactory: () => api, size: 1);
          pool.bind(0, const MovaSource('https://h/playing.mp4'), autoPlay: true);
          clock.flushMicrotasks();
          kernel.emitPlaying(true);
          clock.flushMicrotasks();
          expect(api.state.playing, isTrue);
          kernel.capture = () async => succeeds && kernel.shots >= 3
              ? Uint8List.fromList([8])
              : null;
          Uint8List? result;
          var done = false;
          (api as MovaFrameCapture).screenshot().then((image) {
            result = image;
            done = true;
          });
          clock.flushMicrotasks();
          expect(done, isFalse);
          clock.elapse(Duration(milliseconds: succeeds ? 150 : 1999));
          expect(done, succeeds);
          if (!succeeds) clock.elapse(const Duration(milliseconds: 1));
          expect(done, isTrue);
          expect(result, succeeds ? [8] : isNull);
          expect(kernel.shots, greaterThan(1));
          final shots = kernel.shots;
          clock.elapse(const Duration(seconds: 3));
          expect(kernel.shots, shots);
          pool.dispose();
          clock.flushMicrotasks();
        });
      });
    }
    for (final window in [100, 350, 700, 1050, -700, -1]) {
      test('$name 真机窗口：$window', () {
        fakeAsync((async) {
          final kernel = _CaptureKernel();
          final engine = MovaEngine(
            kernel: kernel,
            fetcher: const MovaTestHttpFetch(),
          );
          final MovaApi api = cutover
              ? MovaCutoverEngine(engineFactory: () => engine)
              : engine;
          final pool = MovaFeedEnginePool(engineFactory: () => api, size: 1);
          pool.bind(0, const MovaSource('https://h/a.mp4'));
          async.flushMicrotasks();
          if (window > 0) {
            kernel.emitSize(1280, 720);
            async.flushMicrotasks();
            expect(api.state.rendered, isTrue);
          } else if (window == -700) {
            // bind 后首帧信号也会消耗原实现的总预算。
            Timer(const Duration(milliseconds: 600), () {
              kernel.emitSize(1280, 720);
            });
          }
          final start = async.elapsed;
          final readyMs = window > 0 ? window : 700;
          final image = Uint8List.fromList([1, 2, 3]);
          kernel.capture = () async {
            if ((async.elapsed - start).inMilliseconds < readyMs) {
              return null;
            }
            // 原始 CHECK 中成功截图还需数百毫秒才返回编码图片。
            await Future<void>.delayed(const Duration(milliseconds: 350));
            return image;
          };
          Uint8List? result;
          var done = false;
          (api as MovaFrameCapture).screenshot().then((value) {
            result = value;
            done = true;
          });
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 2));
          expect(done, isTrue);
          expect(result, image, reason: '首帧不能替代实际截图成功，编码耗时也须计入预算');
          expect(kernel.shots, greaterThan(1));
          pool.dispose();
          async.flushMicrotasks();
          final shots = kernel.shots;
          async.elapse(const Duration(seconds: 3));
          expect(kernel.shots, shots);
        });
      });
    }
    for (final scenario in ['窗口', '超时', '挂起', '切源', '销毁', '播放', '异常', '空字节']) {
      test('$name 暂停截图：$scenario', () {
        fakeAsync((async) {
          final kernel = _CaptureKernel();
          final engine = MovaEngine(
            kernel: kernel,
            fetcher: const MovaTestHttpFetch(),
          );
          final MovaApi api = cutover
              ? MovaCutoverEngine(engineFactory: () => engine)
              : engine;
          final pool = MovaFeedEnginePool(engineFactory: () => api, size: 1);
          pool.bind(0, const MovaSource('https://h/a.mp4'));
          async.flushMicrotasks();
          expect(pool.slotFor(0)?.ready, isTrue);
          kernel.emitSize(1280, 720);
          async.flushMicrotasks();
          expect(api.state.rendered, isTrue);
          final image = Uint8List.fromList([1, 2, 3]);
          final gate = Completer<Uint8List?>();
          kernel.capture = () async {
            if (scenario == '挂起' || scenario == '切源' || scenario == '销毁') {
              return gate.future;
            }
            if (scenario == '异常') throw StateError('capture failed');
            if (scenario == '超时' || scenario == '播放') return null;
            if (kernel.shots < 3) {
              return scenario == '空字节' ? Uint8List(0) : null;
            }
            return image;
          };
          if (scenario == '播放') {
            kernel.emitPlaying(true);
            async.flushMicrotasks();
          }
          Uint8List? result;
          var done = false;
          (api as MovaFrameCapture).screenshot().then((v) {
            result = v;
            done = true;
          });
          async.flushMicrotasks();
          if (scenario == '切源') {
            api.open(const MovaSource('https://h/b.mp4'), autoPlay: false);
            async.flushMicrotasks();
            gate.complete(image);
          } else if (scenario == '销毁') {
            api.dispose();
            async.flushMicrotasks();
            gate.complete(image);
          }
          async.flushMicrotasks();
          if (['窗口', '空字节'].contains(scenario)) {
            expect(done, isFalse, reason: '首次空帧不能提前宣称失败或就绪');
            async.elapse(const Duration(milliseconds: 150));
            expect(done, isTrue);
            expect(result, image);
            expect(kernel.shots, 3);
          } else {
            if (scenario == '超时' || scenario == '挂起') {
              async.elapse(const Duration(milliseconds: 1999));
              expect(done, isFalse, reason: '不能在旧的 1 秒上限提前结束');
              async.elapse(const Duration(milliseconds: 1));
            } else {
              async.elapse(const Duration(seconds: 2));
            }
            expect(done, isTrue, reason: '总等待不得超过 2 秒');
            expect(result, isNull);
            if (scenario == '挂起' || scenario == '异常') {
              expect(kernel.shots, 1);
            }
          }
          pool.dispose();
          async.flushMicrotasks();
          final shots = kernel.shots;
          async.elapse(const Duration(seconds: 5));
          expect(kernel.shots, shots, reason: '完成后不能继续截图');
        });
      });
    }
  }

  test('cutover 自定义引擎没有截图能力时返回 null', () async {
    final api = MovaCutoverEngine(engineFactory: FakeMovaApi.new);
    expect(await api.screenshot(), isNull);
    await api.dispose();
  });
}
