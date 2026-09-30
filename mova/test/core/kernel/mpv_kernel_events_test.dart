import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/core/kernel/mpv_event_backend.dart';
import 'package:mova/src/core/report/stats_probe.dart';

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

  @override
  Future<void> dispose() async {
    callLog.add('player.dispose');
  }
}

class _FakePlatformPlayer extends Fake implements PlatformPlayer {
  final List<String> callLog;
  _FakePlatformPlayer(this.callLog);
}

class _FakeNative extends Fake implements NativePlayer {
  final List<String> callLog;
  _FakeNative(this.callLog);

  @override
  Future<int> get handle async {
    callLog.add('native.handle');
    return 12345;
  }

  @override
  Future<void> observeProperty(String name, Future<void> Function(String) callback, {bool waitForInitialization = true}) async {
    callLog.add('native.observeProperty:$name');
  }
}

class _FakeStream extends Fake implements PlayerStream {
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
  Stream<PlayerLog> get log => const Stream.empty();
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
        
        // immediately dispose
        await kernel.dispose();
        await pumpEventQueue();
        
        final destroyIndex = callLog.indexOf('backend.destroy');
        final playerDisposeIndex = callLog.indexOf('player.dispose');
        if (destroyIndex != -1) {
          expect(destroyIndex, lessThan(playerDisposeIndex));
        }
      }
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
