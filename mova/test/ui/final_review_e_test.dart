import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:mova/mova.dart';
import 'package:mova/src/testing/hooks.dart';

import '../support/fake_api.dart';
import '../support/fake_kernel.dart';
import '../support/pump.dart';

/// Holds native setup at an asynchronous boundary without loading libmpv.
///
/// 在异步边界阻塞原生初始化，无需加载 libmpv。
class _Native extends Fake implements mk.NativePlayer {
  final gate = Completer<void>();
  bool fail = false;

  /// Waits for setup and optionally simulates a native property failure.
  ///
  /// 等待初始化，并可模拟原生属性设置失败。
  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    await gate.future;
    if (fail) throw StateError('setup failed');
  }
}

/// Records player ownership independently of native initialization.
///
/// 独立于原生初始化记录播放器所有权。
class _Player extends Fake implements mk.Player {
  @override
  final _Native platform = _Native();
  int disposals = 0;
  int opens = 0;

  /// Records release of the owned player.
  ///
  /// 记录持有播放器的释放。
  @override
  Future<void> dispose() async {
    disposals++;
  }

  /// Records attempts to open media after setup.
  ///
  /// 记录初始化后的媒体打开请求。
  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    opens++;
  }
}

/// Delays mini entry to reproduce cancellation during fullscreen exit.
///
/// 延迟进入小窗以复现退出全屏期间的取消。
class _MiniApi extends FakeMovaApi {
  /// Enables mini mode with a gated entry.
  ///
  /// 启用小窗并设置进入门闩。
  _MiniApi()
    : super(options: const MovaOpts(mini: MovaMiniConfig(enabled: true)));
  final gate = Completer<void>();

  /// Blocks entry while allowing immediate cancellation.
  ///
  /// 阻塞进入，同时允许立即取消。
  @override
  Future<void> setMini(bool value) async {
    if (value) await gate.future;
    await super.setMini(value);
  }
}

/// Supplies a renamed replacement for composite layout tests.
///
/// 为组合布局测试提供改名的替换节点。
class _Marker extends MovaComponent {
  static const String componentName = 'customSeek';
  @override
  String get name => componentName;
  @override
  MovaSlot get slot => MovaSlot.bottom;

  /// Builds the visible replacement marker.
  ///
  /// 构建可见的替换标记。
  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) =>
      const Text('custom');
}

/// Requests the available width when replacing the center control.
///
/// 替换中央控件时请求占满可用宽度。
class _FullWidthControl extends MovaComponent {
  static const String componentName = 'fullWidthControl';
  @override
  String get name => componentName;
  @override
  MovaSlot get slot => MovaSlot.center;

  /// Builds a control that requires bounded horizontal constraints.
  ///
  /// 构建需要有界横向约束的控件。
  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) =>
      const SizedBox(
        key: ValueKey('fullWidthControl'),
        width: double.infinity,
        height: 40,
      );
}

/// Models a rejected, rewritten, or failed seek using the existing API fake.
///
/// 基于现有 API 夹具模拟拒绝、改写或失败的跳转。
class _SeekApi extends FakeMovaApi {
  String mode = 'reject';

  /// Emits only the target actually accepted by the engine.
  ///
  /// 仅发出引擎实际接受的目标。
  @override
  Future<void> seek(Duration target) async {
    if (mode == 'fail') throw StateError('seek failed');
    if (mode != 'reject') pushEvent(const MovaSeek(Duration(seconds: 20)));
  }
}

/// Rewrites or refuses the real engine's seek request.
///
/// 改写或拒绝真实引擎的跳转请求。
class _SeekHook extends MovaHook {
  /// Selects the accepted target; null rejects the request.
  ///
  /// 指定接受的目标；null 表示拒绝请求。
  _SeekHook(this.target);
  final Duration? target;

  /// Returns the host-approved target.
  ///
  /// 返回宿主批准的目标。
  @override
  Future<Duration?> beforeSeek(Duration value) async => target;
}

/// Runs the final UI review regressions with deterministic async gates.
///
/// 使用确定性异步门闩运行 UI 终审回归测试。
void main() {
  for (final action in ['hide', 'close']) {
    testWidgets('E2 no-op $action preserves pending close callback', (t) async {
      final api = FakeMovaApi(
        options: const MovaOpts(mini: MovaMiniConfig(enabled: true)),
      );
      final mini = MovaMini();
      final closed = <MovaApi>[];
      mini.onClosed = closed.add;
      await mini.show(api);
      api.pauseGate = Completer<void>();
      final closing = mini.close();
      expect(mini.api, isNull);
      if (action == 'hide') await mini.hide();
      if (action == 'close') await mini.close();
      expect(closed, isEmpty);
      api.pauseGate!.complete();
      await closing;
      expect(closed, [api]);
      expect(api.calls.where((call) => call == 'pause'), hasLength(1));
      expect(api.state.mini, isFalse);
      expect(mini.mount, MovaMiniMount.none);
      mini.dispose();
      await api.dispose();
    });
  }

  for (final target in [null, const Duration(seconds: 20)]) {
    testWidgets('E6 real beforeSeek target=$target settles paused slider', (
      t,
    ) async {
      final kernel = FakeKernel();
      final api = MovaEngine(
        options: const MovaOpts(preview: MovaPreviewConfig(enabled: false)),
        fetcher: const MovaTestHttpFetch(),
        kernel: kernel,
        interceptors: [_SeekHook(target)],
      );
      await api.open(const MovaSource('https://h/video'), autoPlay: false);
      kernel.emitDuration(const Duration(seconds: 100));
      kernel.emitPosition(const Duration(seconds: 10));
      await t.pump();
      await pumpComponent(t, api, MovaSeekBarComponent());
      final slider = t.widget<Slider>(find.byType(Slider));
      slider.onChanged!(60000);
      slider.onChangeEnd!(60000);
      await t.pump();
      await t.pump();
      expect(
        t.widget<Slider>(find.byType(Slider)).value,
        target == null ? 10000 : 20000,
      );
      await t.pumpWidget(const SizedBox());
      // Match widget teardown: cancel synchronously, then drain pending work.
      //
      // 沿用组件拆树方式：同步取消，再排空待处理操作。
      unawaited(api.dispose());
      await t.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('E2 superseded same-api show still observes external mini exit', (
    t,
  ) async {
    final api = _MiniApi();
    final mini = MovaMini();
    final first = mini.show(api);
    final second = mini.show(api);
    api.gate.complete();
    await Future.wait([first, second]);
    expect(mini.mount, MovaMiniMount.persistent);
    api.emitMini(false);
    await t.pump();
    expect(mini.mount, MovaMiniMount.none);
    mini.dispose();
    await api.dispose();
  });

  testWidgets('E2 delayed close cannot clear a newer show on the same API', (
    t,
  ) async {
    final api = FakeMovaApi(
      options: const MovaOpts(mini: MovaMiniConfig(enabled: true)),
    );
    final mini = MovaMini();
    await mini.show(api);
    api.pauseGate = Completer<void>();
    final closing = mini.close();
    await mini.show(api);
    api.pauseGate!.complete();
    await closing;
    await t.pump();
    expect(mini.mount, MovaMiniMount.persistent);
    expect(api.state.mini, isTrue);
    mini.dispose();
    await api.dispose();
  });
  for (final action in ['dispose', 'release', 'failure']) {
    testWidgets(
      'E1 initialization $action releases player without opening media',
      (t) async {
        final player = _Player();
        final extractor = MovaFrameExtractor(playerFactory: () => player);
        final pending = extractor.extract(
          'https://h/video',
          Duration.zero,
          width: 100,
          hwdec: false,
        );
        await t.pump();
        if (action == 'dispose') await extractor.dispose();
        if (action == 'release') await extractor.release();
        player.platform.fail = action == 'failure';
        player.platform.gate.complete();
        await t.pump();
        expect(await pending, isNull);
        expect(player.disposals, 1);
        expect(player.opens, 0);
        await extractor.dispose();
        expect(player.disposals, 1);
      },
    );
  }

  for (final page in [false, true]) {
    for (final cancel in ['hide', 'close', 'dispose']) {
      testWidgets(
        'E2 ${page ? 'page' : 'persistent'} show cancelled by $cancel stays hidden',
        (t) async {
          final api = _MiniApi();
          final mini = MovaMini();
          late BuildContext context;
          await t.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox();
                },
              ),
            ),
          );
          final pending = page ? mini.showInPage(context, api) : mini.show(api);
          await t.pump();
          if (cancel == 'hide') await mini.hide();
          if (cancel == 'close') await mini.close();
          if (cancel == 'dispose') mini.dispose();
          api.gate.complete();
          await pending;
          await t.pump();
          expect(mini.api, isNull);
          expect(mini.mount, MovaMiniMount.none);
          expect(api.state.mini, isFalse);
          expect(find.byType(MovaMiniWindow), findsNothing);
          expect(t.takeException(), isNull);
          if (cancel != 'dispose') mini.dispose();
          await api.dispose();
        },
      );
    }
  }

  for (final cancel in ['hide', 'close', 'persistent']) {
    testWidgets('E3 page entry removed before first build by $cancel', (
      t,
    ) async {
      final api = FakeMovaApi(
        options: const MovaOpts(mini: MovaMiniConfig(enabled: true)),
      );
      final mini = MovaMini();
      late BuildContext context;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await mini.showInPage(context, api);
      if (cancel == 'hide') await mini.hide();
      if (cancel == 'close') await mini.close();
      if (cancel == 'persistent') await mini.show(api);
      await t.pump();
      expect(find.byType(MovaMiniWindow), findsNothing);
      expect(t.takeException(), isNull);
      mini.dispose();
      await api.dispose();
    });
  }

  testWidgets('E5 removed center control and all top controls build safely', (
    t,
  ) async {
    final api = FakeMovaApi();
    final center = applyPatches(
      [MovaCenterPlayComponent()],
      [const MovaPatch.remove('centerPlay/playPause')],
    ).single;
    await pumpComponent(t, api, center);
    expect(t.takeException(), isNull);
    final top = MovaTopBarComponent();
    final empty = applyPatches(
      [top],
      [
        for (final child in top.children)
          MovaPatch.remove('topBar/${child.name}'),
      ],
    ).single;
    await pumpComponent(t, api, empty);
    expect(t.takeException(), isNull);
    await api.dispose();
  });

  testWidgets('E5 single replacement can fill the available center width', (
    t,
  ) async {
    final api = FakeMovaApi();
    final center = applyPatches(
      [MovaCenterPlayComponent()],
      [MovaPatch.replace('centerPlay/playPause', _FullWidthControl())],
    ).single;
    await pumpComponent(t, api, center);
    expect(t.takeException(), isNull);
    final control = find.byKey(const ValueKey('fullWidthControl'));
    expect(t.getSize(control).width, t.getSize(find.byType(Stack)).width);
    expect(t.getSize(control).height, 40);
    await api.dispose();
  });

  testWidgets('E5 removing title does not expand the first remaining button', (
    t,
  ) async {
    final api = FakeMovaApi();
    final top = applyPatches(
      [MovaTopBarComponent()],
      [const MovaPatch.remove('topBar/title')],
    ).single;
    await pumpComponent(t, api, top);
    expect(find.byType(Expanded), findsNothing);
    expect(t.takeException(), isNull);
    await api.dispose();
  });

  testWidgets('E7 renamed seek replacement retains VOD and live layout role', (
    t,
  ) async {
    final api = FakeMovaApi();
    final bottom = applyPatches(
      [MovaBottomBarComponent()],
      [MovaPatch.replace('bottomBar/seekBar', _Marker())],
    ).single;
    for (final type in [MovaStreamType.vod, MovaStreamType.live]) {
      api.push(
        MovaState(
          type: type,
          duration: const Duration(seconds: 100),
          liveSeekable: true,
        ),
      );
      await pumpComponent(t, api, bottom);
      expect(find.text('custom'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('custom'), matching: find.byType(Expanded)),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    }
    await api.dispose();
  });

  for (final mode in ['reject', 'rewrite', 'fail', 'timeout', 'source']) {
    testWidgets('E6 $mode seek releases the original slider target', (t) async {
      final api = _SeekApi()..mode = mode;
      api.push(const MovaState(duration: Duration(seconds: 100)));
      await pumpComponent(t, api, MovaSeekBarComponent());
      api.pushProgress(const MovaProg(position: Duration(seconds: 10)));
      await t.pump();
      var slider = t.widget<Slider>(find.byType(Slider));
      slider.onChanged!(60000);
      slider.onChangeEnd!(60000);
      await t.pump();
      slider = t.widget<Slider>(find.byType(Slider));
      if (mode == 'rewrite') {
        expect(slider.value, 20000);
        api.pushEvent(const MovaSeeked(Duration(seconds: 20)));
        await t.pump();
      } else if (mode == 'timeout') {
        await t.pump(const Duration(seconds: 4));
      } else if (mode == 'source') {
        api.pushEvent(const MovaSourceChange(MovaSource('https://h/new')));
        api.push(api.state.copyWith(duration: const Duration(seconds: 30)));
        await t.pump();
        await t.pump();
      }
      api.pushProgress(const MovaProg(position: Duration(seconds: 12)));
      await t.pump();
      await t.pump();
      expect(t.widget<Slider>(find.byType(Slider)).value, 12000);
      await t.pumpWidget(const SizedBox());
      await api.dispose();
    });
  }

  testWidgets(
    'E9 loader end bounds PageView and prevents further black pages',
    (t) async {
      final fleet = <FakeMovaApi>[];
      final end = Completer<MovaFeedItem?>();
      await t.pumpWidget(
        MaterialApp(
          home: MovaFeedPlayer(
            engineFactory: () {
              final api = FakeMovaApi();
              fleet.add(api);
              return api;
            },
            prefetchDepth: 0,
            loader: (index) async => index == 0
                ? const MovaFeedItem(source: MovaSource('https://h/0'))
                : end.future,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.drag(find.byType(PageView), const Offset(0, -650));
      await t.pumpAndSettle();
      end.complete(null);
      await t.pumpAndSettle();
      final pages = t.widget<PageView>(find.byType(PageView));
      expect(pages.childrenDelegate.estimatedChildCount, 1);
      expect(pages.controller!.page, 0);
      await t.drag(find.byType(PageView), const Offset(0, -650));
      await t.pumpAndSettle();
      expect(pages.controller!.page, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final velocity in [const Offset(5, -2000), const Offset(2000, 5)]) {
    testWidgets('E11 tangential corner fling $velocity keeps mini open', (
      t,
    ) async {
      final api = FakeMovaApi(
        options: const MovaOpts(mini: MovaMiniConfig(enabled: true)),
      );
      final mini = MovaMini();
      late BuildContext context;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await mini.showInPage(context, api);
      await t.pump();
      final gesture = t.widget<GestureDetector>(
        find.byKey(const ValueKey('movaMiniWindowGesture')),
      );
      final towardsCorner = velocity.dy < 0
          ? const Offset(1000, 1000)
          : const Offset(-1000, 1000);
      gesture.onPanUpdate!(
        DragUpdateDetails(globalPosition: Offset.zero, delta: towardsCorner),
      );
      await t.pump();
      gesture.onPanEnd!(
        DragEndDetails(velocity: Velocity(pixelsPerSecond: velocity)),
      );
      await t.pumpAndSettle();
      expect(mini.mount, MovaMiniMount.page);
      expect(api.state.mini, isTrue);
      expect(api.calls, isNot(contains('pause')));
      expect(find.byType(MovaMiniWindow), findsOneWidget);
      expect(t.takeException(), isNull);
      mini.dispose();
      await api.dispose();
    });
  }

  for (final direction in [
    const Offset(-1000, 0),
    const Offset(1000, 0),
    const Offset(0, -1000),
    const Offset(0, 1000),
  ]) {
    testWidgets('E11 default-margin outward fling $direction closes mini', (
      t,
    ) async {
      final api = FakeMovaApi(
        options: const MovaOpts(mini: MovaMiniConfig(enabled: true)),
      );
      final mini = MovaMini();
      late BuildContext context;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await mini.showInPage(context, api);
      await t.pump();
      final gesture = t.widget<GestureDetector>(
        find.byKey(const ValueKey('movaMiniWindowGesture')),
      );
      gesture.onPanUpdate!(
        DragUpdateDetails(globalPosition: Offset.zero, delta: direction),
      );
      await t.pump();
      gesture.onPanEnd!(
        DragEndDetails(velocity: Velocity(pixelsPerSecond: direction * 2)),
      );
      await t.pumpAndSettle();
      expect(mini.mount, MovaMiniMount.none);
      expect(api.calls, contains('pause'));
      mini.dispose();
      await api.dispose();
    });
  }
}
