import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/mini/placement.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/ui/mini/mini_ctl.dart';
import 'package:mova/src/ui/mini/mini_window.dart';
import 'package:mova/src/ui/player.dart';

import '../../support/fake_api.dart';

/// Pumps [MovaMiniWindow] inside a [size]-sized box, so tests control
/// `bounds` precisely instead of relying on the default test surface size.
///
/// 把 [MovaMiniWindow] 塞进一个 [size] 大小的盒子里 pump，使测试能精确控制
/// `bounds`，而非依赖默认的测试画布尺寸。
Future<void> pumpWindow(
  WidgetTester tester, {
  required MovaMiniCtl ctl,
  required FakeMovaApi api,
  MovaMiniConfig config = const MovaMiniConfig(enabled: true),
  Size size = const Size(400, 800),
}) async {
  await tester.binding.setSurfaceSize(Size(size.width + 20, size.height + 20));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: MovaMiniWindow(key: ValueKey(size), ctl: ctl, api: api, config: config),
      ),
    ),
  ));
}

void main() {
  late MovaMiniCtl ctl;
  late FakeMovaApi api;

  setUp(() {
    ctl = MovaMiniCtl();
    api = FakeMovaApi(options: const MovaOpts());
  });

  for (final corner in MovaMiniCorner.values) {
    testWidgets('first frame lands at ${corner.name}', (tester) async {
      await pumpWindow(
        tester,
        ctl: ctl,
        api: api,
        config: MovaMiniConfig(enabled: true, initialCorner: corner, margin: 10, width: 100),
      );
      final topLeft = tester.getTopLeft(find.byKey(const ValueKey('movaMiniWindowGesture')));
      final expected = rectForCorner(
        corner,
        width: 100,
        height: 100 / (16 / 9),
        bounds: const MovaMiniRect(left: 0, top: 0, width: 400, height: 800),
        insets: const MovaMiniInsets(),
        margin: 10,
      );
      expect(topLeft.dx, closeTo(expected.left, 0.5));
      expect(topLeft.dy, closeTo(expected.top, 0.5));
    });
  }

  testWidgets('drag moves the window and clamps at the boundary', (tester) async {
    // Disable snapToEdge — with it on, release re-snaps to an edge and would
    // mask whether the plain drag-clamp math actually moved/clamped the
    // window; a plain-clamp placement isolates that.
    //
    // 关掉 snapToEdge——开着的话松手会重新吸边，会掩盖"拖动-钳制"这段数学本身
    // 到底有没有真的移动/钳制；纯钳制落点策略把它单独隔离出来看。
    const config = MovaMiniConfig(enabled: true, snapToEdge: false, settleDuration: Duration.zero);
    await pumpWindow(tester, ctl: ctl, api: api, config: config);
    final before = tester.getTopLeft(find.byKey(const ValueKey('movaMiniWindowGesture')));
    await tester.drag(find.byKey(const ValueKey('movaMiniWindowGesture')), const Offset(-30, 0));
    await tester.pump();
    final after = tester.getTopLeft(find.byKey(const ValueKey('movaMiniWindowGesture')));
    expect(after.dx, isNot(before.dx));

    // Drag far past the left edge — must clamp, never go negative.
    await tester.drag(find.byKey(const ValueKey('movaMiniWindowGesture')), const Offset(-2000, 0));
    await tester.pump();
    final clamped = tester.getTopLeft(find.byKey(const ValueKey('movaMiniWindowGesture')));
    expect(clamped.dx, greaterThanOrEqualTo(-0.5));
  });

  testWidgets('release settles to the value returned by the injected placement policy', (tester) async {
    final injected = _FixedPlacement(const MovaMiniRect(left: 5, top: 5, width: 180, height: 101.25));
    await pumpWindow(
      tester,
      ctl: ctl,
      api: api,
      config: MovaMiniConfig(enabled: true, placement: injected),
    );
    await tester.drag(find.byKey(const ValueKey('movaMiniWindowGesture')), const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(injected.calls, greaterThan(0));
    final topLeft = tester.getTopLeft(find.byKey(const ValueKey('movaMiniWindowGesture')));
    expect(topLeft.dx, closeTo(5, 1));
    expect(topLeft.dy, closeTo(5, 1));
  });

  testWidgets('tapping the picture calls ctl.hide(), not ctl.close()', (tester) async {
    await pumpWindow(tester, ctl: ctl, api: api);
    await ctl.show(api);
    // The exact center coincides with MovaMiniSkin's center play/pause
    // button (deliberately still tappable to toggle playback) — tap a corner
    // of the window's own hit area instead, well clear of that button and of
    // the close (✕) button in the opposite corner.
    //
    // 正中心与 MovaMiniSkin 的中央播放/暂停按钮重合（刻意保留可点，用于切换
    // 播放）——改点窗口自身命中区域的一角，避开该按钮，也避开另一角的关闭
    // （✕）按钮。
    final rect = tester.getRect(find.byKey(const ValueKey('movaMiniWindowGesture')));
    await tester.tapAt(rect.bottomLeft + const Offset(4, -4));
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.lastMini, isFalse);
    expect(api.calls, isNot(contains('pause')));
  });

  testWidgets('tapping the close button calls ctl.close()', (tester) async {
    await pumpWindow(tester, ctl: ctl, api: api);
    await ctl.show(api);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(api.calls, contains('pause'));
  });

  testWidgets('dismissible: false ignores a fast fling-away and only clamps back', (tester) async {
    await pumpWindow(
      tester,
      ctl: ctl,
      api: api,
      config: const MovaMiniConfig(enabled: true, dismissible: false),
    );
    await ctl.show(api);
    await tester.fling(find.byKey(const ValueKey('movaMiniWindowGesture')), const Offset(-400, 0), 3000);
    await tester.pumpAndSettle();
    expect(api.calls, isNot(contains('pause')), reason: 'close() should never fire when dismissible is false');
  });

  testWidgets('shrinking the outer constraints (simulated rotation) keeps the window fully inside', (tester) async {
    await pumpWindow(tester, ctl: ctl, api: api, size: const Size(400, 800));
    await pumpWindow(tester, ctl: ctl, api: api, size: const Size(200, 150));
    final rect = tester.getRect(find.byKey(const ValueKey('movaMiniWindowGesture')));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(200.5));
    expect(rect.bottom, lessThanOrEqualTo(150.5));
  });

  testWidgets('bounds come from the outer constraints, not MediaQuery.size', (tester) async {
    // Wrap MovaMiniWindow inside a half-screen box under a full-screen
    // MaterialApp — MediaQuery.size reports the full screen, but the window
    // must place itself relative to its own (smaller) box.
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          height: 200,
          child: MovaMiniWindow(
            ctl: ctl,
            api: api,
            config: const MovaMiniConfig(enabled: true, width: 100, margin: 0),
          ),
        ),
      ),
    ));
    final topLeft = tester.getTopLeft(find.byKey(const ValueKey('movaMiniWindowGesture')));
    // bottomRight default: right edge should sit at 200 (the box), not the
    // full MediaQuery screen width (usually 800 in tests).
    expect(topLeft.dx + 100, closeTo(200, 1));
  });

  testWidgets('MovaMiniWindow build root is LayoutBuilder, not Positioned', (tester) async {
    await pumpWindow(tester, ctl: ctl, api: api);
    expect(
      find.descendant(of: find.byType(MovaMiniWindow), matching: find.byType(LayoutBuilder)),
      findsOneWidget,
    );
    expect(tester.widget(find.byType(MovaMiniWindow)), isNot(isA<Positioned>()),
        reason: 'MovaMiniWindow must never be a Positioned itself — mount-agnostic constraint');
  });

  testWidgets('internal MovaPlayer has autoLoadQualities false', (tester) async {
    await pumpWindow(tester, ctl: ctl, api: api);
    final player = tester.widget<MovaPlayer>(find.byType(MovaPlayer));
    expect(player.autoLoadQualities, isFalse);
  });

  testWidgets('exactly one MovaPlayer exists throughout a drag (no Draggable feedback subtree)', (tester) async {
    await pumpWindow(tester, ctl: ctl, api: api);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('movaMiniWindowGesture'))));
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();
    expect(find.byType(MovaPlayer), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(MovaPlayer), findsOneWidget);
  });
}

/// A fixed-answer [MovaMiniPlacement] test double that records how many
/// times it was consulted.
///
/// 固定答案的 [MovaMiniPlacement] 测试替身，记录被咨询的次数。
class _FixedPlacement implements MovaMiniPlacement {
  _FixedPlacement(this.answer);

  final MovaMiniRect answer;
  int calls = 0;

  @override
  MovaMiniRect settle(
    MovaMiniRect current, {
    required MovaMiniRect bounds,
    required MovaMiniInsets insets,
    double velocityX = 0,
    double velocityY = 0,
  }) {
    calls++;
    return answer;
  }
}
