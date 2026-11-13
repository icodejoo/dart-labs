import 'package:mova/mova.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/core/kernel/mpv_event_backend.dart';

import '../../support/fake_mpv_event_backend.dart';

class _FakePlayer extends Fake implements Player {
  final _FakeNative? _platform;
  final _FakeStream _stream = _FakeStream();
  final List<String> callLog;

  _FakePlayer(this.callLog, {bool hasNative = true})
      : _platform = hasNative ? _FakeNative(callLog) : null;

  @override
  PlatformPlayer get platform => _platform ?? _FakePlatformPlayer(callLog);

  @override
  PlayerStream get stream => _stream;

  /// 暂停只记调用，验证旧结束通知不会暂停新源。
  @override
  Future<void> pause() async => callLog.add('player.pause');

  /// 模拟打开，不产生真实原生资源。
  @override
  Future<void> open(Playable playable, {bool play = true}) async {}

  @override
  Future<void> dispose() async {
    callLog.add('player.dispose');
    await _stream.logs.close();
  }
}

class _FakePlatformPlayer extends Fake implements PlatformPlayer {
  final List<String> callLog;
  _FakePlatformPlayer(this.callLog);
}

class _FakeNative extends Fake implements NativePlayer {
  final List<String> callLog;
  _FakeNative(this.callLog);

  /// Optional setup barriers for bounded teardown tests.
  ///
  /// 用于有界销毁测试的可选准备阻塞点。
  Completer<int>? handleBarrier;
  Completer<void>? observeBarrier;

  /// 原生属性操作为空实现，支持首次 open 的准备阶段。
  @override
  Future<String> getProperty(String name, {bool waitForInitialization = true}) async => '';

  /// 记录路径无需触碰 FFI。
  @override
  Future<void> setProperty(String name, String value, {bool waitForInitialization = true}) async {}

  @override
  Future<int> get handle async {
    callLog.add('native.handle');
    return handleBarrier == null ? 12345 : await handleBarrier!.future;
  }

  @override
  Future<void> observeProperty(String name, Future<void> Function(String) callback, {bool waitForInitialization = true}) async {
    callLog.add('native.observeProperty:$name');
    await observeBarrier?.future;
  }
}

class _FakeStream extends Fake implements PlayerStream {
  /// 原始错误级日志，可验证适配器的 ffmpeg 过滤。
  final logs = StreamController<PlayerLog>.broadcast();
  @override
  Stream<Tracks> get tracks => const Stream.empty();
  @override
  Stream<int?> get width => const Stream.empty();
  
  @override
  Stream<int?> get height => const Stream.empty();

  @override
  Stream<bool> get playing => const Stream.empty();

  @override
  Stream<bool> get buffering => const Stream.empty();

  @override
  Stream<bool> get completed => const Stream.empty();

  @override
  Stream<Duration> get position => const Stream.empty();

  @override
  Stream<Duration> get duration => const Stream.empty();

  @override
  Stream<Duration> get buffer => const Stream.empty();

  @override
  Stream<String> get error => const Stream.empty();

  @override
  Stream<PlayerLog> get log => logs.stream;
}

class _SharedLogBackend extends FakeMpvEventBackend {
  final List<String> sharedLog;
  final void Function() onCreate;
  final void Function() onDestroy;

  _SharedLogBackend(this.sharedLog, this.onCreate, this.onDestroy);

  @override
  bool createClient(String name) {
    sharedLog.add('backend.createClient');
    final res = super.createClient(name);
    if (res) onCreate();
    return res;
  }

  @override
  void destroy() {
    sharedLog.add('backend.destroy');
    super.destroy();
    onDestroy();
  }
}

void main() {
  group('MovaMpvKernel Events', () {
    for (final createFail in [true, false]) {
      test('F-I ffmpeg main error fallback only when client unavailable createFail=$createFail', () async {
        final player = _FakePlayer([]);
        final backend = FakeMpvEventBackend()..createFail = createFail;
        final kernel = MovaMpvKernel(
          player: player, audioOnly: true, observeNativeEvents: true,
          observeRestarts: false, backendFactory: (_, _) => backend,
        );
        final e = Mova(kernel: kernel, options: const MovaOpts(
          controls: MovaCtrlsOpts(autoHide: false),
        ));
        final errors = <MovaErrorEvent>[];
        e.events.where((v) => v is MovaErrorEvent).cast<MovaErrorEvent>().listen(errors.add);
        const uri = 'https://h/main.mp4';
        await e.open(const MovaSource(uri));
        expect(kernel.endFileAvailable, !createFail);
        expect(kernel.nativeRestartAvailable, isFalse);
        player._stream.logs.add(const PlayerLog(prefix: 'ffmpeg', level: 'warn', text: 'Failed to open $uri'));
        await pumpEventQueue();
        expect(errors, isEmpty);
        player._stream.logs.add(const PlayerLog(prefix: 'ffmpeg', level: 'error', text: 'Failed to open $uri'));
        await pumpEventQueue();
        if (createFail) {
          expect(errors.single.fatal, isTrue);
          expect(errors.single.code, 'network');
          expect(e.state.error, isNotNull);
        } else {
          expect(errors, isEmpty, reason: '泵可用时保留原有非 tcp ffmpeg 过滤');
          player._stream.logs.add(const PlayerLog(prefix: 'stream', level: 'error', text: 'Failed to open $uri'));
          await pumpEventQueue();
          expect(errors.single.fatal, isFalse);
          expect(e.state.error, isNull);
          backend.events.add(const MovaRawEvent(7, endFileReason: 4));
          backend.wake();
          await pumpEventQueue();
          expect(errors.map((v) => v.fatal), [false, true]);
        }
        await e.dispose();
      });
    }

    test('F-J queued A END_FILE after open B cannot terminate or pause B', () async {
      final calls = <String>[];
      final backend = FakeMpvEventBackend();
      final kernel = MovaMpvKernel(
        player: _FakePlayer(calls), audioOnly: true, observeNativeEvents: true,
        backendFactory: (_, _) => backend,
      );
      final mova = Mova(kernel: kernel, options: const MovaOpts(
        controls: MovaCtrlsOpts(autoHide: false),
      ));
      await mova.open(const MovaSource('https://h/A.mp4'));
      backend.events.add(const MovaRawEvent(7, endFileReason: 4));
      await mova.open(const MovaSource('https://h/B.mp4'));
      backend.wake();
      await pumpEventQueue();
      expect(mova.state.error, isNull);
      expect(calls, isNot(contains('player.pause')));
      backend.events.add(const MovaRawEvent(7, endFileReason: 4));
      backend.wake();
      await pumpEventQueue();
      expect(mova.state.error, MovaEndFileReason.error);
      expect(calls.where((v) => v == 'player.pause'), hasLength(1));
      await mova.dispose();
    });

    test('A14 pump stays absent until first open and repeated opens share one client', () async {
      var created = 0;
      final kernel = MovaMpvKernel(
        player: _FakePlayer([]), audioOnly: true, observeNativeEvents: true,
        backendFactory: (_, _) { created++; return FakeMpvEventBackend(); },
      );
      await pumpEventQueue();
      expect(created, 0);
      await kernel.open('https://h/1.mp4');
      await kernel.open('https://h/2.mp4');
      expect(created, 1);
      await kernel.dispose();
    });

    test('A14 observeRestarts enables an already opened END_FILE only pump', () async {
      final backend = FakeMpvEventBackend();
      final kernel = MovaMpvKernel(
        player: _FakePlayer([]), audioOnly: true, observeNativeEvents: true,
        observeRestarts: false, backendFactory: (_, _) => backend,
      );
      await kernel.open('https://h/1.mp4');
      expect(kernel.nativeRestartAvailable, isFalse);
      kernel.observeRestarts();
      expect(kernel.nativeRestartAvailable, isTrue);
      final events = <void>[];
      kernel.playbackRestarts.listen(events.add);
      backend.events.add(MovaRawEvent(generated.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART));
      backend.wake();
      await pumpEventQueue();
      expect(events, hasLength(1));
      await kernel.dispose();
    });

    test('observeQoeSignals=false never calls backendFactory', () {
      final callLog = <String>[];
      final player = _FakePlayer(callLog);
      var factoryCalled = false;
      
      final kernel = MovaMpvKernel(
        player: player,
        audioOnly: true,
        observeQoeSignals: false,
        backendFactory: (native, addr) {
          factoryCalled = true;
          return FakeMpvEventBackend();
        }
      );
      
      expect(factoryCalled, isFalse);
      kernel.dispose();
    });
    
    test('platform not NativePlayer never calls backendFactory', () {
      final callLog = <String>[];
      final player = _FakePlayer(callLog, hasNative: false);
      var factoryCalled = false;
      
      final kernel = MovaMpvKernel(
        player: player,
        audioOnly: true,
        observeQoeSignals: true,
        backendFactory: (native, addr) {
          factoryCalled = true;
          return FakeMpvEventBackend();
        }
      );
      
      expect(factoryCalled, isFalse);
      kernel.dispose();
    });

    test('observeNativeEvents=true without QoE builds the pump but skips paused-for-cache', () async {
      final callLog = <String>[];
      var factoryCalled = false;
      final kernel = MovaMpvKernel(
        player: _FakePlayer(callLog),
        audioOnly: true,
        observeQoeSignals: false,
        observeNativeEvents: true,
        backendFactory: (native, addr) {
          factoryCalled = true;
          return FakeMpvEventBackend();
        },
      );
      await kernel.open('https://h/a.mp4');
      await pumpEventQueue();
      expect(factoryCalled, isTrue);
      expect(callLog, isNot(contains('native.observeProperty:paused-for-cache')));
      await kernel.dispose();
    });

    test('observeRestarts=false: END_FILE still forwarded, PLAYBACK_RESTART dropped', () async {
      final backend = FakeMpvEventBackend();
      final kernel = MovaMpvKernel(
        player: _FakePlayer(<String>[]),
        audioOnly: true,
        observeQoeSignals: false,
        observeNativeEvents: true,
        observeRestarts: false,
        backendFactory: (native, addr) => backend,
      );
      await kernel.open('https://h/a.mp4');
      await pumpEventQueue();
      final restarts = <void>[];
      final ends = <MovaEndFileReason>[];
      kernel.playbackRestarts.listen(restarts.add);
      kernel.endFiles.listen(ends.add);
      backend.events.addAll([
        MovaRawEvent(generated.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART),
        MovaRawEvent(generated.mpv_event_id.MPV_EVENT_END_FILE, endFileReason: generated.mpv_end_file_reason.MPV_END_FILE_REASON_ERROR),
      ]);
      backend.wake();
      await pumpEventQueue();
      expect(restarts, isEmpty);
      expect(ends, [MovaEndFileReason.error]);
      expect(kernel.nativeRestartAvailable, isFalse, reason: '不转发 RESTART，首帧闸门不能等它');
      await kernel.dispose();
    });

    test('默认转发 RESTART：泵活跃时 nativeRestartAvailable 为 true', () async {
      final kernel = MovaMpvKernel(
        player: _FakePlayer(<String>[]),
        audioOnly: true,
        observeQoeSignals: false,
        observeNativeEvents: true,
        backendFactory: (native, addr) => FakeMpvEventBackend(),
      );
      await kernel.open('https://h/a.mp4');
      await pumpEventQueue();
      expect(kernel.nativeRestartAvailable, isTrue);
      await kernel.dispose();
    });

    test('observeNativeEvents=false with QoE observes paused-for-cache but never builds the pump', () async {
      final callLog = <String>[];
      var factoryCalled = false;
      final kernel = MovaMpvKernel(
        player: _FakePlayer(callLog),
        audioOnly: true,
        observeQoeSignals: true,
        observeNativeEvents: false,
        backendFactory: (native, addr) {
          factoryCalled = true;
          return FakeMpvEventBackend();
        },
      );
      await pumpEventQueue();
      expect(factoryCalled, isFalse);
      expect(callLog, contains('native.observeProperty:paused-for-cache'));
      await kernel.dispose();
    });

    test('omitting observeNativeEvents follows observeQoeSignals, paused-for-cache first', () async {
      final callLog = <String>[];
      final kernel = MovaMpvKernel(
        player: _FakePlayer(callLog),
        audioOnly: true,
        observeQoeSignals: true,
        backendFactory: (native, addr) => _SharedLogBackend(callLog, () {}, () {}),
      );
      await kernel.open('https://h/a.mp4');
      await pumpEventQueue();
      final observe = callLog.indexOf('native.observeProperty:paused-for-cache');
      final create = callLog.indexOf('backend.createClient');
      expect(observe, isNonNegative);
      expect(create, greaterThan(observe));
      await kernel.dispose();
    });

    test('observeNativeEvents=true on a non-NativePlayer platform neither builds the pump nor throws', () async {
      final callLog = <String>[];
      var factoryCalled = false;
      final kernel = MovaMpvKernel(
        player: _FakePlayer(callLog, hasNative: false),
        audioOnly: true,
        observeQoeSignals: false,
        observeNativeEvents: true,
        backendFactory: (native, addr) {
          factoryCalled = true;
          return FakeMpvEventBackend();
        },
      );
      await pumpEventQueue();
      expect(factoryCalled, isFalse);
      await kernel.dispose();
    });

    for (final blockObserver in [true, false]) {
      test('B4 dispose bounds native setup and rejects late registration observer=$blockObserver', () async {
        final calls = <String>[];
        final player = _FakePlayer(calls);
        final native = player._platform!;
        if (blockObserver) {
          native.observeBarrier = Completer<void>();
        } else {
          native.handleBarrier = Completer<int>();
        }
        var created = 0;
        final kernel = MovaMpvKernel(
          player: player,
          audioOnly: true,
          observeQoeSignals: true,
          observeNativeEvents: true,
          backendFactory: (_, _) {
            created++;
            return FakeMpvEventBackend();
          },
        );
        var opened = false;
        kernel.open('https://h/late.mp4').then((_) => opened = true);
        await pumpEventQueue();
        var disposed = false;
        kernel.dispose().then((_) => disposed = true);
        await pumpEventQueue();
        expect(disposed, isFalse);
        await Future<void>.delayed(const Duration(seconds: 5));
        await pumpEventQueue();
        expect(disposed, isTrue);
        expect(calls.where((v) => v == 'player.dispose'), hasLength(1));
        expect(created, 0);
        native.observeBarrier?.complete();
        native.handleBarrier?.complete(12345);
        await pumpEventQueue();
        expect(opened, isTrue);
        expect(created, 0);
        expect(kernel.endFileAvailable, isFalse);
      });
    }

    test('immediate dispose race loop', () async {
      int createSum = 0;
      int destroySum = 0;
      for (var i = 0; i < 200; i++) {
        final callLog = <String>[];
        final player = _FakePlayer(callLog);
        
        final kernel = MovaMpvKernel(
          player: player,
          audioOnly: true,
          observeQoeSignals: true,
          backendFactory: (native, addr) {
            return _SharedLogBackend(
              callLog,
              () => createSum++,
              () => destroySum++,
            );
          }
        );
        
        // 发起加载后立即销毁，覆盖建泵准备与销毁交错。
        final opening = kernel.open('https://h/race.mp4');
        // 一半覆盖注册前销毁，一半确保真实创建客户端后立即销毁。
        if (i.isOdd) await opening;
        await kernel.dispose();
        await opening;
        await pumpEventQueue();
        
        final destroyIndex = callLog.indexOf('backend.destroy');
        final playerDisposeIndex = callLog.indexOf('player.dispose');
        if (destroyIndex != -1) {
          expect(destroyIndex, lessThan(playerDisposeIndex));
        }
      }
      expect(createSum, greaterThan(0));
      expect(createSum, equals(destroySum));
    });

    test('streams complete on dispose', () async {
      final callLog = <String>[];
      final player = _FakePlayer(callLog);
      
      final kernel = MovaMpvKernel(
        player: player,
        audioOnly: true,
        observeQoeSignals: true,
        backendFactory: (native, addr) => FakeMpvEventBackend(),
      );
      
      var restartsDone = false;
      var endFilesDone = false;
      
      kernel.playbackRestarts.listen((_) {}, onDone: () => restartsDone = true);
      kernel.endFiles.listen((_) {}, onDone: () => endFilesDone = true);
      
      await kernel.dispose();
      await pumpEventQueue();
      
      expect(restartsDone, isTrue);
      expect(endFilesDone, isTrue);
    });

    for (final streamName in ['size', 'stalling', 'playbackRestarts', 'endFiles', 'attemptEnds']) {
      test('dispose releases native resources with paused $streamName listener', () async {
        final calls = <String>[];
        final kernel = MovaMpvKernel(
          player: _FakePlayer(calls),
          audioOnly: true,
          backendFactory: (_, _) => _SharedLogBackend(calls, () {}, () {}),
        );
        await kernel.open('https://h/a.mp4');
        final Stream<dynamic> stream = switch (streamName) {
          'size' => kernel.size,
          'stalling' => kernel.stalling,
          'playbackRestarts' => kernel.playbackRestarts,
          'endFiles' => kernel.endFiles,
          _ => kernel.attemptEnds,
        };
        var done = false;
        final sub = stream.listen((_) {}, onDone: () => done = true)..pause();
        try {
          await kernel.dispose().timeout(const Duration(seconds: 1));
          expect(calls, contains('backend.destroy'));
          expect(calls, contains('player.dispose'));
          expect(calls.indexOf('backend.destroy'), lessThan(calls.indexOf('player.dispose')));
          expect(done, isFalse);
          sub.resume();
          await pumpEventQueue();
          expect(done, isTrue);
        } finally {
          await sub.cancel();
        }
      });
    }

    test('reason mappings', () async {
      final callLog = <String>[];
      final player = _FakePlayer(callLog);
      
      final backend = FakeMpvEventBackend();
      
      final kernel = MovaMpvKernel(
        player: player,
        audioOnly: true,
        observeQoeSignals: true,
        backendFactory: (native, addr) => backend,
      );
      
      await kernel.open('https://h/a.mp4');
      await pumpEventQueue(); // ensure pump is started
      
      final restarts = <void>[];
      final endFileReasons = <MovaEndFileReason>[];
      
      kernel.playbackRestarts.listen(restarts.add);
      kernel.endFiles.listen(endFileReasons.add);
      
      // RESTART
      backend.events.add(MovaRawEvent(generated.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART));
      backend.wake();
      await pumpEventQueue();
      expect(restarts.length, 1);
      
      // END_FILE reasons
      backend.events.addAll([
        MovaRawEvent(generated.mpv_event_id.MPV_EVENT_END_FILE, endFileReason: generated.mpv_end_file_reason.MPV_END_FILE_REASON_STOP),
        MovaRawEvent(generated.mpv_event_id.MPV_EVENT_END_FILE, endFileReason: generated.mpv_end_file_reason.MPV_END_FILE_REASON_QUIT),
        MovaRawEvent(generated.mpv_event_id.MPV_EVENT_END_FILE, endFileReason: generated.mpv_end_file_reason.MPV_END_FILE_REASON_ERROR),
        MovaRawEvent(generated.mpv_event_id.MPV_EVENT_END_FILE, endFileReason: generated.mpv_end_file_reason.MPV_END_FILE_REASON_REDIRECT),
        MovaRawEvent(generated.mpv_event_id.MPV_EVENT_END_FILE, endFileReason: generated.mpv_end_file_reason.MPV_END_FILE_REASON_EOF),
        MovaRawEvent(generated.mpv_event_id.MPV_EVENT_END_FILE, endFileReason: 999), // unknown
      ]);
      backend.wake();
      await pumpEventQueue();
      
      expect(endFileReasons, [
        MovaEndFileReason.stop,
        MovaEndFileReason.quit,
        MovaEndFileReason.error,
        MovaEndFileReason.redirect,
      ]);
      
      await kernel.dispose();
    });
  });
}
