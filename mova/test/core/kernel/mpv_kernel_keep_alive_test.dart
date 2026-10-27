import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/core/kernel/keep_alive_kernel.dart';
import 'package:mova/src/core/keep_alive/keep_alive.dart';

/// Fake native player: records `get:`/`set:` calls, serves scripted property
/// values, and can throw or hang on demand.
///
/// 假的原生播放器：记录 `get:`/`set:` 调用，按脚本返回属性值，可按需抛错或永不完成。
class _FakeNative extends Fake implements NativePlayer {
  _FakeNative(this.log);
  final List<String> log;
  final Map<String, String> props = {'mute': 'no', 'vid': 'auto', 'file-format': 'flv'};
  final Set<String> throwOnSet = {};
  final Set<String> hangOnGet = {};

  @override
  Future<String> getProperty(String name, {bool waitForInitialization = true}) {
    log.add('get:$name');
    if (hangOnGet.contains(name)) return Completer<String>().future;
    return Future<String>.value(props[name] ?? '');
  }

  @override
  Future<void> setProperty(String name, String value, {bool waitForInitialization = true}) async {
    log.add('set:$name=$value');
    if (throwOnSet.contains('$name=$value')) throw StateError('boom');
    props[name] = value;
  }
}

class _FakeStream extends Fake implements PlayerStream {
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
}

class _FakePlayer extends Fake implements Player {
  _FakePlayer(this.native, {this.useNative = true, PlayerState? state})
      : _state = state ?? const PlayerState();
  final _FakeNative native;
  final bool useNative;
  final PlayerState _state;

  @override
  PlatformPlayer get platform => useNative ? native : _NotNative();

  @override
  PlayerStream get stream => _FakeStream();

  @override
  PlayerState get state => _state;

  @override
  Future<void> dispose() async {}
}

class _NotNative extends Fake implements PlatformPlayer {}

MovaMpvKernel _kernel(_FakePlayer p, {bool lazyVideo = false}) =>
    MovaMpvKernel(player: p, audioOnly: !lazyVideo, lazyVideo: lazyVideo, observeQoeSignals: false);

/// Calls that touched keepAlive properties only (drops the reads of `file-format`).
///
/// 只保留触及待机属性的调用（去掉对 `file-format` 的读取）。
List<String> _keepAliveCalls(List<String> log) =>
    log.where((c) => !c.contains('file-format')).toList();

void main() {
  group('warm mute and keepAlive ownership', () {
    test('queued warm mute and keepAlive operations never interleave', () async {
      final native = _FakeNative([]);
      final k = _kernel(_FakePlayer(native));
      addTearDown(k.dispose);
      final warm = k.setWarmMute(true);
      final keepAlive = k.enterKeepAlive(MovaKeepAliveMode.muted);
      final release = k.setWarmMute(false);
      expect(await warm, isTrue);
      expect(await keepAlive, isTrue);
      expect(await release, isTrue);
      expect(native.props['mute'], 'yes');
      expect(native.props['vid'], 'no');
      await k.exitKeepAlive();
      expect(native.props['mute'], 'no');
      expect(native.props['vid'], 'auto');
    });
    test('warm mute alone is idempotent and restores the exact property', () async {
      final log = <String>[];
      final native = _FakeNative(log);
      final k = _kernel(_FakePlayer(native));
      addTearDown(k.dispose);
      expect(await k.setWarmMute(true), isTrue);
      expect(await k.setWarmMute(true), isTrue);
      expect(native.props['mute'], 'yes');
      expect(native.props['vid'], 'auto');
      expect(await k.setWarmMute(false), isTrue);
      expect(await k.setWarmMute(false), isTrue);
      expect(log, ['get:mute', 'set:mute=yes', 'set:mute=no']);
    });
    test('failed warm mute writes preserve ownership for retry', () async {
      final native = _FakeNative([])..throwOnSet.add('mute=yes');
      final k = _kernel(_FakePlayer(native));
      addTearDown(k.dispose);
      expect(await k.setWarmMute(true), isFalse);
      expect(native.props['mute'], 'no');
      native.throwOnSet.clear();
      expect(await k.setWarmMute(true), isTrue);
      native.throwOnSet.add('mute=no');
      expect(await k.setWarmMute(false), isFalse);
      expect(native.props['mute'], 'yes');
      native.throwOnSet.clear();
      expect(await k.setWarmMute(false), isTrue);
      expect(native.props['mute'], 'no');
    });
    for (final original in ['no', 'yes']) {
      for (final warmFirst in [true, false]) {
        for (final releaseWarmFirst in [true, false]) {
          test('restores $original: warmFirst=$warmFirst releaseWarmFirst=$releaseWarmFirst', () async {
            final native = _FakeNative([])..props['mute'] = original;
            final k = _kernel(_FakePlayer(native));
            addTearDown(k.dispose);
            if (warmFirst) {
              expect(await k.setWarmMute(true), isTrue);
              expect(await k.enterKeepAlive(MovaKeepAliveMode.muted), isTrue);
            } else {
              expect(await k.enterKeepAlive(MovaKeepAliveMode.muted), isTrue);
              expect(await k.setWarmMute(true), isTrue);
            }
            expect(native.props['mute'], 'yes');
            expect(native.props['vid'], 'no');
            if (releaseWarmFirst) {
              expect(await k.setWarmMute(false), isTrue);
              expect(native.props['mute'], 'yes');
              expect(native.props['vid'], 'no');
              await k.exitKeepAlive();
            } else {
              await k.exitKeepAlive();
              expect(native.props['mute'], 'yes');
              expect(native.props['vid'], 'auto');
              expect(await k.setWarmMute(false), isTrue);
            }
            expect(native.props['mute'], original);
            expect(native.props['vid'], 'auto');
            expect(await k.setWarmMute(false), isTrue);
          });
        }
      }
    }
  });
  group('MovaMpvKernel keepAlive', () {
    test('inspectKeepAlive maps tracks, audio params and file-format', () async {
      final log = <String>[];
      final native = _FakeNative(log);
      final state = PlayerState(
        tracks: const Tracks(
          video: [VideoTrack('auto', null, null), VideoTrack('no', null, null), VideoTrack('1', null, null)],
          audio: [AudioTrack('auto', null, null), AudioTrack('no', null, null), AudioTrack('1', null, null)],
        ),
        track: const Track(audio: AudioTrack('1', null, null)),
        audioParams: const AudioParams(sampleRate: 44100),
      );
      final k = _kernel(_FakePlayer(native, state: state));
      final media = await k.inspectKeepAlive();
      expect(media.audio, MovaAudioPresence.present);
      expect(media.format, 'flv');
    });

    test('enterKeepAlive(muted) saves then writes mute and vid in order', () async {
      final log = <String>[];
      final k = _kernel(_FakePlayer(_FakeNative(log)));
      expect(await k.enterKeepAlive(MovaKeepAliveMode.muted), isTrue);
      expect(log, ['get:mute', 'get:vid', 'set:mute=yes', 'set:vid=no']);
    });

    test('exitKeepAlive restores vid then mute, returns true once, then is a no-op', () async {
      final log = <String>[];
      final k = _kernel(_FakePlayer(_FakeNative(log)));
      await k.enterKeepAlive(MovaKeepAliveMode.muted);
      log.clear();
      expect(await k.exitKeepAlive(), isTrue);
      expect(log, ['set:vid=auto', 'set:mute=no']);
      log.clear();
      expect(await k.exitKeepAlive(), isFalse);
      expect(log, isEmpty);
    });

    test('a vid that was already no is left alone and exit reports no restart', () async {
      final log = <String>[];
      final native = _FakeNative(log)..props['vid'] = 'no';
      final k = _kernel(_FakePlayer(native));
      expect(await k.enterKeepAlive(MovaKeepAliveMode.muted), isTrue);
      expect(log, ['get:mute', 'get:vid', 'set:mute=yes']);
      log.clear();
      expect(await k.exitKeepAlive(), isFalse);
      expect(log, ['set:mute=no']);
    });

    test('decodeOnly only touches mute and never reads or writes vid', () async {
      final log = <String>[];
      final k = _kernel(_FakePlayer(_FakeNative(log)));
      expect(await k.enterKeepAlive(MovaKeepAliveMode.decodeOnly), isTrue);
      expect(log, ['get:mute', 'set:mute=yes']);
      log.clear();
      expect(await k.exitKeepAlive(), isFalse);
      expect(log, ['set:mute=no']);
    });

    test('entering twice is idempotent', () async {
      final log = <String>[];
      final k = _kernel(_FakePlayer(_FakeNative(log)));
      expect(await k.enterKeepAlive(MovaKeepAliveMode.muted), isTrue);
      final once = List<String>.of(log);
      expect(await k.enterKeepAlive(MovaKeepAliveMode.muted), isTrue);
      expect(log, once);
    });

    test('a failed vid write rolls back and reports false', () async {
      final log = <String>[];
      final native = _FakeNative(log)..throwOnSet.add('vid=no');
      final k = _kernel(_FakePlayer(native));
      expect(await k.enterKeepAlive(MovaKeepAliveMode.muted), isFalse);
      expect(log.last, 'set:mute=no');
      expect(native.props['mute'], 'no');
    });

    test('a read that never completes times out after 2s and reports false', () {
      fakeAsync((fa) {
        final log = <String>[];
        final native = _FakeNative(log)..hangOnGet.add('mute');
        final k = _kernel(_FakePlayer(native));
        bool? result;
        k.enterKeepAlive(MovaKeepAliveMode.muted).then((v) => result = v);
        fa.flushMicrotasks();
        expect(result, isNull);
        fa.elapse(const Duration(seconds: 2));
        fa.flushMicrotasks();
        expect(result, isFalse);
      });
    });

    test('a non-native platform degrades, never builds a VideoController, and dispose blocks writes', () async {
      final log = <String>[];
      final native = _FakeNative(log);
      final plain = _kernel(_FakePlayer(native, useNative: false));
      expect(await plain.enterKeepAlive(MovaKeepAliveMode.muted), isFalse);
      expect((await plain.inspectKeepAlive()).format, isNull);

      final disposable = _kernel(_FakePlayer(native));
      final lazyKernel = MovaMpvKernel(
        player: _FakePlayer(native),
        lazyVideo: true,
        observeQoeSignals: false,
      );
      await lazyKernel.enterKeepAlive(MovaKeepAliveMode.muted);
      await lazyKernel.exitKeepAlive();
      expect(await lazyKernel.screenshot(), isNull);

      log.clear();
      await disposable.dispose();
      expect(await disposable.enterKeepAlive(MovaKeepAliveMode.muted), isFalse);
      expect(await disposable.exitKeepAlive(), isFalse);
      expect(_keepAliveCalls(log), isEmpty);
    });
  });
}
