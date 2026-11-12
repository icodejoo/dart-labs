import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/xvg.dart';
import 'package:xvg_example/animation_control_page.dart';

/// Time step crossing the beacon begin event. / 跨过 beacon 开始事件的时间步长。
const _eventStep = Duration(milliseconds: 400);

/// Verifies the real page's playback, seeking and element log.
/// 验证真实页面的播放、定位与元素日志。
void main() {
  setUpAll(Xvg.ensureInitialized);
  testWidgets('animation controls pause, seek and log element events', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AnimationControlPage()));
    await tester.pump();
    expect(find.text(AnimationControlPage.title), findsOneWidget);
    final controller = tester
        .widgetList<Xvg>(find.byType(Xvg))
        .firstWhere((widget) => widget.controller != null)
        .controller!;
    await tester.pump(_eventStep);
    expect(controller.time.value, greaterThan(Duration.zero));
    await tester.tap(find.text('pause'));
    await tester.pump();
    final paused = controller.time.value;
    await tester.pump(const Duration(seconds: 1));
    expect(controller.time.value, paused);

    final slider = find.byKey(AnimationControlPage.progressKey);
    await tester.drag(slider, const Offset(120, 0));
    await tester.pump();
    expect(controller.time.value, isNot(paused));
    expect(controller.status, XvgPlaybackStatus.paused);
    await tester.tap(find.text('stop'));
    await tester.tap(find.text('play'));
    await tester.pump();
    await tester.pump(_eventStep);

    final log = find.byKey(AnimationControlPage.eventsKey);
    await tester.ensureVisible(log);
    await tester.pump();
    expect(
      find.descendant(of: log, matching: find.text('begin: beacon')),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
