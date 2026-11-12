import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/shared_animation_clock.dart';
import 'package:xvg/xvg.dart';

/// Finite multichannel CSS fixture with a crossed begin boundary.
/// 开始边界可被穿越的有限多通道 CSS 样例。
const _source = '''<svg width="24" height="24"><style>
@keyframes pulse {
from {opacity:0;transform:translate(0px)}
to {opacity:1;transform:translate(10px)}
}
</style><rect width="10" height="10"
style="animation:pulse 1s linear 250ms 3 forwards"/></svg>''';

/// One second of playback. / 一秒播放步长。
const _second = Duration(seconds: 1);

/// Positive delay that the controller crosses. / 控制器会穿越的正延迟。
const _delay = Duration(milliseconds: 250);

/// Lifecycle labels in forward order. / 正向顺序的生命周期标签。
const _expected = [
  'begin:pulse',
  'repeat:pulse:1',
  'repeat:pulse:2',
  'end:pulse',
];

/// Extracts element events independently of document status events.
/// 独立于文档状态事件提取元素事件。
List<String> _labels(List<XvgAnimationEvent> events) => [
  for (final event in events)
    if (event is XvgAnimationElementBegin)
      'begin:${event.id}'
    else if (event is XvgAnimationElementRepeat)
      'repeat:${event.id}:${event.iteration}'
    else if (event is XvgAnimationElementEnd)
      'end:${event.id}',
];

/// Verifies CSS lifecycle delivery through public widget/controller APIs.
/// 验证公共控件和控制器 API 的 CSS 生命周期事件派发。
void main() {
  setUpAll(() async => RustLib.init());
  setUp(() {
    XvgDocumentCache.instance.clear();
  });

  for (final implicit in [true, false]) {
    testWidgets('CSS onEvent lifecycle with implicit=$implicit', (
      tester,
    ) async {
      final controller = XvgAnimationController();
      final listenerEvents = <XvgAnimationEvent>[];
      final widgetEvents = <XvgAnimationEvent>[];
      controller.addEventListener(listenerEvents.add);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: XvgAnimated.string(
            _source,
            controller: implicit ? null : controller,
            onEvent: widgetEvents.add,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(_delay);
      await tester.pump(_second);
      await tester.pump(_second);
      await tester.pump(_second);
      expect(_labels(widgetEvents), _expected);
      expect(_labels(listenerEvents), implicit ? isEmpty : _expected);
      expect(SharedAnimationClock.instance.subscriberCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'CSS controller listener works without onEvent and seek is silent',
    (tester) async {
      final controller = XvgAnimationController(autoplay: false);
      final events = <XvgAnimationEvent>[];
      controller.addEventListener(events.add);
      await tester.pumpWidget(
        XvgAnimated.string(_source, controller: controller),
      );
      controller.seek(_second + _delay);
      expect(_labels(events), isEmpty);
      controller.play();
      await tester.pump();
      await tester.pump(_second * 2);
      expect(_labels(events), _expected.skip(2));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('CSS onEvent follows Flutter Animation forward and reverse', (
    tester,
  ) async {
    final animation = AnimationController(vsync: tester, duration: _second * 4);
    final events = <XvgAnimationEvent>[];
    await tester.pumpWidget(
      XvgAnimated.string(
        _source,
        animation: animation,
        animationSpan: _second * 4,
        onEvent: events.add,
      ),
    );
    animation.value = 1;
    expect(_labels(events), _expected);
    events.clear();
    animation.value = 0;
    expect(_labels(events), _expected.reversed);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    animation.dispose();
  });
}
