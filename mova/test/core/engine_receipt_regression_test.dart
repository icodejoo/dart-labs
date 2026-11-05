import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/testing/hooks.dart';
import 'package:mova/src/core/kernel/kernel.dart';

import '../support/fake_kernel.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

// 原生属性适配器可同步连发宽、高变化，不能靠假内核的异步间隔掩盖问题。
class SynchronousSizeKernel extends FakeKernel {
  final sizes = StreamController<MovaSize>.broadcast(sync: true);
  @override
  Stream<MovaSize> get size => sizes.stream;
  @override
  void emitSize(int width, int height) =>
      sizes.add(MovaSize(width: width, height: height));
  @override
  Future<void> dispose() async {
    await sizes.close();
    await super.dispose();
  }
}

class MasterFetch implements MovaHttpFetch {
  @override
  Future<Uint8List?> get(Uri url) async => Uint8List.fromList(
    utf8.encode(
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360\n360.m3u8\n',
    ),
  );
  @override
  Future<void> close() async {}
}

void main() {
  test('连续尺寸更新的事件载荷与接收时 getter 一致', () async {
    final kernel = SynchronousSizeKernel();
    final engine = MovaEngine(
      kernel: kernel,
      fetcher: const MovaTestHttpFetch(),
    );
    addTearDown(engine.dispose);
    await engine.open(const MovaSource('https://h/a.mp4'));
    final seen = <(int, int, int, int)>[];
    engine.events.listen((event) {
      if (event is MovaSizeChange) {
        seen.add((
          event.width,
          event.height,
          engine.state.width,
          engine.state.height,
        ));
      }
    });
    // 模拟 mpv 宽高独立通知与关闭归零，无需在每次通知之间等待事件流。
    kernel.emitSize(640, 360);
    kernel.emitSize(640, 0);
    kernel.emitSize(0, 0);
    await flush();
    expect(seen, [(640, 360, 640, 360), (640, 0, 640, 0), (0, 0, 0, 0)]);
  });

  test('探测返回后立即手选时自动档事件仍与接收时状态一致', () async {
    final engine = MovaEngine(kernel: FakeKernel(), fetcher: MasterFetch());
    addTearDown(engine.dispose);
    await engine.open(const MovaSource('https://h/master.m3u8'));
    final seen = <(MovaQuality, MovaQuality?)>[];
    engine.events.listen((event) {
      if (event is MovaQualityChange) {
        seen.add((event.quality, engine.state.currentQuality));
      }
    });
    await engine.loadQualities();
    await engine.switchQuality(
      engine.state.qualities.firstWhere((q) => !q.isAuto),
    );
    await flush();
    expect(seen, isNotEmpty);
    expect(seen.every((pair) => pair.$1 == pair.$2), isTrue);
  });

  test('被后续换档取代的在途加载不再发出旧清晰度事件', () async {
    final kernel = FakeKernel();
    final engine = MovaEngine(
      kernel: kernel,
      fetcher: const MovaTestHttpFetch(),
    );
    addTearDown(engine.dispose);
    await engine.open(const MovaSource('https://h/a.mp4'));
    const auto = MovaQuality(label: '自动', uri: '', isAuto: true);
    const manual = MovaQuality(label: '360p', uri: 'https://h/360.m3u8');
    final seen = <(MovaQuality, MovaQuality?)>[];
    engine.events.listen((event) {
      if (event is MovaQualityChange) {
        seen.add((event.quality, engine.state.currentQuality));
      }
    });
    final gate = Completer<void>();
    kernel.openGate = gate;
    final first = engine.switchQuality(auto);
    await flush();
    kernel.openGate = null;
    await engine.switchQuality(manual);
    gate.complete();
    await first;
    await flush();
    expect(seen, [(manual, manual)]);
    expect(engine.state.currentQuality, manual);
  });

  test('事件回调内产生的新事件排队且不会重入同步控制器', () async {
    final engine = MovaEngine(
      kernel: FakeKernel(),
      fetcher: const MovaTestHttpFetch(),
    );
    addTearDown(engine.dispose);
    final seen = <String>[];
    engine.events.listen((event) {
      if (event is MovaFitChange) {
        seen.add('fit');
        unawaited(engine.setZoom(2));
      } else if (event is MovaZoomChange) {
        seen.add('zoom');
      }
    });
    await engine.setFit(MovaFit.cover);
    await flush();
    expect(seen, ['fit', 'zoom']);
    expect(engine.state.zoom, 2);
  });
}
