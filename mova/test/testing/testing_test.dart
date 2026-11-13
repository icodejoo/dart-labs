// Deliberately never calls MediaKit.ensureInitialized(): that this whole file
// runs is itself the evidence that package:mova/testing.dart keeps hosts away
// from media_kit.
//
// 刻意从不调用 MediaKit.ensureInitialized()：整个文件能跑通，本身就是
// package:mova/testing.dart 让宿主远离 media_kit 的证据。

import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/ui/poster.dart' show MovaPosterLayer;
import 'package:mova/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../support/fake_kernel.dart';

/// Lets the explicit-kernel path (which still wires the real thumbnail cache)
/// dispose cleanly without a real path_provider channel.
///
/// 让显式传内核的路径（仍会接真实缩略图缓存）在没有真实 path_provider 通道时也能干净
/// dispose。
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

const _noAutoHide = MovaOpts(controls: MovaCtrlsOpts(autoHide: false));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  setUp(MovaTesting.useTestKernels);
  tearDown(MovaTesting.reset);

  test('1. createMova() with no arguments works and hands out the scripted kernel', () async {
    final mova = createMova();
    addTearDown(mova.dispose);
    expect(MovaTesting.kernels, hasLength(1));
    await mova.open(const MovaSource('https://h/a.m3u8'));
    expect(MovaTesting.lastKernel!.lastUri, 'https://h/a.m3u8');
    expect(MovaTesting.lastKernel!.calls, contains('open'));
  });

  test('2. platform ports are the player no-ops, never the real adapters', () {
    final mova = createMova();
    addTearDown(mova.dispose);
    expect(mova.debugBrightness, isA<MovaFallbackBrightness>());
    expect(mova.debugPip, isA<MovaNoopPip>());
    expect(mova.debugOrient, isA<MovaNoopOrient>());
    expect(mova.debugVolume, isNull);
  });

  test('3. an explicitly passed kernel still wins over the test kernels', () {
    final mova = createMova(kernel: FakeKernel());
    addTearDown(mova.dispose);
    expect(MovaTesting.kernels, isEmpty);
  });

  test('4. reset() uninstalls and forgets every kernel', () {
    createMova().dispose();
    expect(MovaTesting.active, isTrue);
    expect(MovaTesting.kernels, isNotEmpty);
    MovaTesting.reset();
    expect(MovaTesting.active, isFalse);
    expect(MovaTesting.kernels, isEmpty);
    expect(MovaTesting.lastKernel, isNull);
  });

  test('5. restart and the buffering edge both land rendered, leaving no pending timer', () {
    fakeAsync((async) {
      final a = createMova(options: _noAutoHide);
      a.open(const MovaSource('https://h/a.m3u8'));
      async.flushMicrotasks();
      expect(a.state.rendered, isFalse);
      MovaTesting.lastKernel!.emitRestart();
      async.flushMicrotasks();
      expect(a.state.rendered, isTrue);

      final b = createMova(options: _noAutoHide);
      b.open(const MovaSource('https://h/b.m3u8'));
      async.flushMicrotasks();
      MovaTesting.lastKernel!
        ..emitBuffering(true)
        ..emitBuffering(false);
      async.flushMicrotasks();
      expect(b.state.rendered, isTrue);
      expect(async.pendingTimers, isEmpty, reason: 'a test kernel never starts the 1.5s grace wait');
    });
  });

  testWidgets('6. MovaView with a poster and recovery on pumps on the default factory and fades the poster out', (t) async {
    const poster = SizedBox(key: ValueKey('poster'), width: 10, height: 10);
    Widget view(Widget? p) => MaterialApp(
          home: MovaView(
            source: const MovaSource('https://h/live.flv', type: MovaStreamType.live),
            poster: p,
            options: _noAutoHide.copyWith(recovery: const MovaRecoveryOpts(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true)),
          ),
        );
    await t.pumpWidget(view(poster));
    await t.pump();
    final k = MovaTesting.lastKernel!;
    AnimatedOpacity fade() => t.widget<AnimatedOpacity>(find.descendant(of: find.byType(MovaPosterLayer), matching: find.byType(AnimatedOpacity)));
    expect(fade().opacity, 1);
    k.emitSize(1280, 720);
    k.emitRestart();
    await t.pump();
    await t.pump();
    expect(fade().opacity, 0);

    // Tear down while a fresh player's start deadline is still running: the
    // watchdog timer must already be gone when the test framework checks.
    //
    // 在新播放器的起播期限还在计时时拆树：测试框架检查时看门狗计时器必须已经不在了。
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(view(poster));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });

  test('7b. the test kernel records the per-source mpv options the player stages', () async {
    final mova = createMova();
    addTearDown(mova.dispose);
    await mova.open(
      const MovaSource(
        'whep+http://h:8889/x/whep',
        type: MovaStreamType.live,
        whepMediaTimeout: Duration(seconds: 3),
      ),
    );
    await mova.open(const MovaSource('https://h/b.m3u8'));
    expect(MovaTesting.lastKernel!.stagedSourceOptions, [
      {'demuxer-lavf-o': 'media_timeout=3000000'},
      <String, String>{},
    ]);
  });

  test('7. the main barrel exports nothing from the testing entry', () {
    final barrel = File('lib/mova.dart').readAsStringSync();
    expect(barrel, isNot(contains('testing')));
    expect(barrel, isNot(contains('MovaTestKernel')));
  });

  /// A live `MovaView` whose guard holds in keepAlive when hidden.
  ///
  /// 隐藏时由守卫待机的直播 `MovaView`。
  Widget keepAliveView(bool on) => MaterialApp(
        home: TickerMode(
          enabled: on,
          child: MovaView(
            source: const MovaSource('https://h/live.flv', type: MovaStreamType.live),
            autoPause: const MovaAutoPauseOpts(hiddenMode: MovaHiddenMode.keepAlive),
            options: _noAutoHide,
          ),
        ),
      );

  testWidgets('8. with scripted audio, a hidden live MovaView holds in keepAlive', (t) async {
    await t.pumpWidget(keepAliveView(true));
    await t.pump();
    final k = MovaTesting.lastKernel!..hasAudio = true;
    k.emitPlaying(true);
    await t.pump();
    await t.pumpWidget(keepAliveView(false));
    await t.pump();
    await t.pump();
    expect(k.calls, contains('enterKeepAlive:muted'));
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });

  testWidgets('9. without scripted audio the media is unknown, so a hidden live MovaView pauses', (t) async {
    await t.pumpWidget(keepAliveView(true));
    await t.pump();
    final k = MovaTesting.lastKernel!;
    expect(k.hasAudio, isNull);
    k.emitPlaying(true);
    await t.pump();
    await t.pumpWidget(keepAliveView(false));
    await t.pump();
    await t.pump();
    expect(k.calls, contains('pause'));
    expect(k.calls, isNot(contains('enterKeepAlive:muted')));
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });
}
