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

  for (final cutover in [false, true]) {
    final name = cutover ? 'cutover' : '普通';
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
            async.elapse(const Duration(milliseconds: 50));
            expect(done, isTrue);
            expect(result, image);
            expect(kernel.shots, 3);
          } else {
            async.elapse(const Duration(seconds: 1));
            expect(done, isTrue, reason: '总等待不得超过 1 秒');
            expect(result, isNull);
            if (scenario == '挂起' || scenario == '播放' || scenario == '异常') {
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
