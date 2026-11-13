import 'dart:convert';
import 'dart:typed_data';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_kernel.dart';

/// 内存 master：真实探测入口按码率生成从高到低的三个具体档位。
class _Fetch implements IMovaHttpFetch {
  /// 真实探测请求次数，验证不额外探测。
  int requests = 0;
  /// 直接返回内存内容，无连接或定时器。
  @override
  Future<Uint8List?> get(Uri url) async {
    requests++;
    return Uint8List.fromList(utf8.encode('#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080\nhigh.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\nmid.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360\nlow.m3u8\n'));
  }
  /// 关闭内存端口，无返回资源。
  @override
  Future<void> close() async {}
}

/// 基于 A12 自探测和 A11 租约的真实播放器夹具。
class _Rig {
  /// [manage] 启用实验接管，[enabled] 控制 ABR 总开关。
  _Rig(this.clock, {bool manage = false, bool enabled = true}) {
    e = createMova(
      kernel: k, fetcher: fetch, brightness: MovaFallbackBrightness(),
      pip: MovaNoopPip(), orient: MovaNoopOrient(),
      options: MovaOpts(preview: MovaPreviewOpts(cache: MovaMemoryThumbCache()), controls: const MovaCtrlsOpts(autoHide: false),
        abr: MovaAbrOpts(manageAuto: manage, enabled: enabled, stallThreshold: 1)),
    );
    e.events.listen(events.add);
    e.open(const MovaSource('https://h/master.m3u8'));
    clock.flushMicrotasks();
    k.emitDuration(const Duration(minutes: 5));
    k.emitPosition(const Duration(seconds: 41));
    k.emitPosition(const Duration(seconds: 42));
    clock.flushMicrotasks();
    expect(e.state.currentQuality?.isAuto, isTrue);
    expect(e.state.qualities, hasLength(4));
    expect(fetch.requests, 1);
  }
  /// 虚拟时钟。
  final FakeAsync clock;
  /// 可控制回声的内核。
  final k = FakeKernel();
  /// 不触网的探测输入。
  final fetch = _Fetch();
  /// 真实播放器。
  late final Mova e;
  /// 包括 ABR 降档的完整事件。
  final events = <MovaEvent>[];
  /// 发一轮缓冲并等待换档完成。
  void buffer() {
    k.emitBuffering(true);
    k.emitBuffering(false);
    clock.flushMicrotasks();
  }
  /// 关闭播放器并验证没有遗留定时器。
  void close() {
    e.dispose();
    clock.flushMicrotasks();
    clock.elapse(Duration.zero);
    clock.flushMicrotasks();
    expect(clock.pendingTimers, isEmpty);
  }
}

/// 运行实验性 auto 接管回归，不推断 mpv 真机选档。
void main() {
  test('A16 manageAuto defaults off and participates in opts equality', () {
    const defaults = MovaAbrOpts();
    const same = MovaAbrOpts(manageAuto: false);
    const managed = MovaAbrOpts(manageAuto: true);
    expect(defaults.manageAuto, isFalse);
    expect(defaults, same);
    expect(defaults.hashCode, same.hashCode);
    expect(defaults, isNot(managed));
    expect(managed.probeVariants, isTrue);
  });

  test('A16 default auto keeps kernel selection despite stalls', () {
    fakeAsync((clock) {
      final r = _Rig(clock);
      r.buffer();
      r.buffer();
      expect(r.e.state.currentQuality?.isAuto, isTrue);
      expect(r.k.openedUris, ['https://h/master.m3u8']);
      expect(r.events.whereType<MovaAbrDownShift>(), isEmpty);
      r.close();
    });
  });

  test('A16 opt-in uses probed list to leave auto once and preserves load semantics', () {
    fakeAsync((clock) {
      final r = _Rig(clock, manage: true);
      final auto = r.e.state.currentQuality;
      r.buffer();
      expect(r.k.openedUris, ['https://h/master.m3u8', 'https://h/mid.m3u8']);
      expect(r.e.state.currentQuality?.label, '720p');
      final down = r.events.whereType<MovaAbrDownShift>().single;
      expect(down.from, same(auto));
      expect(down.to, same(r.e.state.currentQuality));
      expect(r.events.whereType<MovaSourceChange>(), hasLength(1));
      expect(r.events.whereType<MovaReady>(), hasLength(1));
      expect(r.fetch.requests, 1);
      r.buffer();
      expect(r.k.openedUris, hasLength(2), reason: '换档租约阻止新加载自己的缓冲再次降档');
      r.close();
    });
  });

  test('A16 disabled ABR and insufficient variants do not take over auto', () {
    fakeAsync((clock) {
      final disabled = _Rig(clock, manage: true, enabled: false);
      disabled.buffer();
      expect(disabled.e.state.currentQuality?.isAuto, isTrue);
      expect(disabled.k.openedUris, hasLength(1));
      disabled.close();
      for (final count in [0, 1]) {
        final r = _Rig(clock, manage: true);
        final auto = r.e.state.currentQuality!;
        r.e.debugSetQualities([auto, ...r.e.state.qualities.where((q) => !q.isAuto).take(count)], current: auto);
        r.buffer();
        expect(r.e.state.currentQuality, same(auto));
        expect(r.events.whereType<MovaAbrDownShift>(), isEmpty);
        r.close();
      }
    });
  });

  test('A16 auto takeover honors user seek lease until unchanged ten second cap', () {
    fakeAsync((clock) {
      final r = _Rig(clock, manage: true);
      r.e.seek(const Duration(seconds: 80));
      clock.flushMicrotasks();
      r.buffer();
      expect(r.e.state.currentQuality?.isAuto, isTrue);
      expect(r.events.whereType<MovaAbrDownShift>(), isEmpty);
      clock.elapse(const Duration(seconds: 10));
      r.buffer();
      expect(r.e.state.currentQuality?.label, '720p');
      expect(r.events.whereType<MovaAbrDownShift>(), hasLength(1));
      r.close();
    });
  });
}
