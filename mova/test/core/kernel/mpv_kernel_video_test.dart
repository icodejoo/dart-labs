import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 记录 setProperty / open 调用顺序、并可模拟 vid 当前值的假播放器。
class _FakePlayer extends Fake implements Player {
  _FakePlayer(this.log, {String vid = 'auto'}) : _native = _FakeNative(log, vid);
  final List<String> log;
  final _FakeNative _native;
  final _stream = _FakeStream();

  @override
  PlatformPlayer get platform => _native;

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> open(Playable playable, {bool play = true}) async => log.add('open');

  @override
  Future<void> dispose() async {}
}

/// 假原生播放器：vid 当前值可控，写入记入日志。
class _FakeNative extends Fake implements NativePlayer {
  _FakeNative(this.log, this.vid);
  final List<String> log;
  String vid;

  @override
  Future<String> getProperty(String name, {bool waitForInitialization = true}) async => name == 'vid' ? vid : '';

  @override
  Future<void> setProperty(String name, String value, {bool waitForInitialization = true}) async {
    log.add('set:$name=$value');
    if (name == 'vid') vid = value;
  }
}

class _FakeStream extends Fake implements PlayerStream {
  @override
  Stream<Tracks> get tracks => const Stream.empty();
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
}

/// 假视频控制器，仅作句柄。
class _FakeController extends Fake implements VideoController {}

void main() {
  /// 让出若干拍，等 unawaited 的收尾逻辑跑完。
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// 构造一个带假播放器与可控就绪信号的 lazy 内核。
  ({MovaMpvKernel kernel, List<String> log, Completer<void> ready}) build({
    String vid = 'auto',
    bool audioOnly = false,
    bool lazy = true,
  }) {
    final log = <String>[];
    final ready = Completer<void>();
    final kernel = MovaMpvKernel(
      player: _FakePlayer(log, vid: vid),
      audioOnly: audioOnly,
      lazyVideo: lazy,
      observeQoeSignals: false,
      mountYield: () => WidgetsBinding.instance.endOfFrame,
      videoControllerFactory: (_) {
        log.add('create');
        return _FakeController();
      },
      videoReady: (_) async {
        await ready.future;
        log.add('ready');
      },
    );
    return (kernel: kernel, log: log, ready: ready);
  }

  group('MovaMpvKernel 视频管线时序', () {
    test('lazy：渲染面就绪后若 vid 被 mpv 打回 no，补一次 vid=auto', () async {
      final t = build(vid: 'no');
      t.kernel.renderHandle;
      t.ready.complete();
      await settle();
      expect(t.log, ['create', 'ready', 'set:vid=no', 'set:vid=auto']);
    });

    test('lazy：渲染面就绪时 vid 已是 auto，不重复下发', () async {
      final t = build(vid: 'auto');
      t.kernel.renderHandle;
      t.ready.complete();
      await settle();
      expect(t.log, ['create', 'ready']);
    });

    test('重复读取 renderHandle 只创建一次控制器、只补选一次', () async {
      final t = build(vid: 'no');
      final a = t.kernel.renderHandle;
      final b = t.kernel.renderHandle;
      t.ready.complete();
      await settle();
      expect(identical(a, b), isTrue);
      expect(t.log.where((e) => e == 'create').length, 1);
      expect(t.log.where((e) => e == 'set:vid=auto').length, 1);
    });

    test('open 会等已创建控制器的渲染面就绪后再开文件', () async {
      final t = build(vid: 'auto');
      t.kernel.renderHandle;
      final opening = t.kernel.open('http://x/a.mp4');
      await settle();
      expect(t.log, ['create']);
      t.ready.complete();
      await opening;
      expect(t.log, ['create', 'ready', 'open']);
    });

    test('open(A) 在等渲染面期间被 open(B) 取代：A 醒来后不再 _player.open', () async {
      final t = build(vid: 'auto');
      t.kernel.renderHandle;
      final a = t.kernel.open('http://x/a.mp4');
      await settle();
      final b = t.kernel.open('http://x/b.mp4');
      await settle();
      t.ready.complete();
      await Future.wait([a, b]);
      expect(t.log.where((e) => e == 'open').length, 1, reason: '只有最新一次 open 真正下发');
    });

    test('lazy 且控制器尚未创建：open 不等待、不创建控制器（保留懒创建初衷）', () async {
      final t = build();
      await t.kernel.open('http://x/a.mp4');
      expect(t.log, ['open']);
      expect(t.log.where((e) => e == 'create'), isEmpty);
    });

    testWidgets('lazy 且控制器尚未创建：open 让出一帧，等同帧挂载的渲染面就绪后再开文件', (tester) async {
      final t = build(vid: 'auto');
      // 模拟 MovaPlayer 在下一帧 build 时读取 renderHandle。
      WidgetsBinding.instance.addPostFrameCallback((_) => t.kernel.renderHandle);
      final opening = t.kernel.open('http://x/a.mp4');
      await tester.idle();
      await tester.pump();
      await tester.idle();
      expect(t.log, ['create'], reason: '渲染面未就绪前不得 open');
      t.ready.complete();
      await tester.pump();
      await opening;
      expect(t.log, ['create', 'ready', 'open']);
    });

    test('渲染面就绪失败不阻塞 open', () async {
      final log = <String>[];
      final k = MovaMpvKernel(
        player: _FakePlayer(log),
        lazyVideo: true,
        observeQoeSignals: false,
        videoControllerFactory: (_) => _FakeController(),
        videoReady: (_) async => throw StateError('boom'),
      );
      k.renderHandle;
      await k.open('http://x/a.mp4');
      expect(log, ['open']);
    });

    test('audioOnly 从不触碰视频管线与 vid', () async {
      final t = build(vid: 'no', audioOnly: true);
      expect(t.kernel.renderHandle, isNull);
      await t.kernel.open('http://x/a.mp4');
      await settle();
      expect(t.log, ['open']);
      expect(t.log.where((e) => e == 'create'), isEmpty);
    });

    test('非 lazy：构造期创建控制器，同样在就绪后补选 vid', () async {
      final t = build(vid: 'no', lazy: false);
      expect(t.log.where((e) => e == 'create').length, 1);
      t.ready.complete();
      await settle();
      expect(t.log, ['create', 'ready', 'set:vid=no', 'set:vid=auto']);
    });
  });
}
