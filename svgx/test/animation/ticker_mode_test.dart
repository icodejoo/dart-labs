import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/smil_animation.dart';
import 'package:svgx/svgx.dart';

const _source =
    '<svg width="24" height="24">'
    '<rect width="24" height="24">'
    '<animate attributeName="opacity" values="0;1" dur="1s" '
    'repeatCount="indefinite"/></rect></svg>';

// 直接统计时间线采样，避免只断言画面没变化却漏掉后台空转。
class _CountingAnimation extends SmilAnimation {
  _CountingAnimation()
    : super(
        attributeName: 'opacity',
        values: [0, 1],
        duration: const Duration(seconds: 1),
        begin: Duration.zero,
        fillFreeze: false,
        repeatCount: const SmilRepeatCount.indefinite(),
      );

  int samples = 0;

  @override
  double? sample(Duration t) {
    samples++;
    return super.sample(t);
  }
}

_CountingAnimation _countSamples(String source) {
  final animation = _CountingAnimation();
  SvgxDocumentCache.instance
          .getOrParse(source)
          .document
          .root
          .children
          .single
          .animations[0] =
      animation;
  return animation;
}

Widget _scene(
  bool first, {
  bool? second,
  String source = _source,
  double rate = 1,
  VoidCallback? onStart,
  VoidCallback? onComplete,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Column(
    children: [
      TickerMode(
        enabled: first,
        child: SvgxAnimated.string(
          source,
          key: const ValueKey('first'),
          playbackRate: rate,
          onAnimationStart: onStart,
          onAnimationComplete: onComplete,
        ),
      ),
      if (second != null)
        TickerMode(
          enabled: second,
          child: const SvgxAnimated.string(_source, key: ValueKey('second')),
        ),
    ],
  ),
);

AnimatedSvgPainter _painter(WidgetTester tester, String key) =>
    tester
            .widget<CustomPaint>(
              find
                  .descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byType(CustomPaint),
                  )
                  .first,
            )
            .painter!
        as AnimatedSvgPainter;

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _frames(tester);
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(SvgxDocumentCache.instance.clear);
  tearDown(SvgxDocumentCache.instance.clear);

  testWidgets('initially disabled does not sample and resumes from zero', (
    tester,
  ) async {
    final animation = _countSamples(_source);
    var starts = 0;
    await tester.pumpWidget(_scene(false, onStart: () => starts++));
    final initialSamples = animation.samples;
    await _frames(tester);
    expect(animation.samples, initialSamples);
    expect(starts, 0);
    expect(_painter(tester, 'first').time, Duration.zero);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_scene(true, onStart: () => starts++));
    await _frames(tester);
    expect(animation.samples, greaterThan(initialSamples));
    expect(starts, 1);
    expect(_painter(tester, 'first').time, greaterThan(Duration.zero));
    await _dispose(tester);
  });

  testWidgets('pause freezes samples and time, resume preserves progress', (
    tester,
  ) async {
    final animation = _countSamples(_source);
    var starts = 0;
    await tester.pumpWidget(_scene(true, onStart: () => starts++));
    await _frames(tester);
    await tester.pumpWidget(_scene(false, onStart: () => starts++));
    final pausedTime = _painter(tester, 'first').time;
    final pausedSamples = animation.samples;
    await _frames(tester);
    expect(animation.samples, pausedSamples);
    expect(_painter(tester, 'first').time, pausedTime);
    expect(tester.binding.transientCallbackCount, 0);

    // 暂停期间改速率不应把隐藏时间计入播放进度。
    await tester.pumpWidget(_scene(true, rate: 2, onStart: () => starts++));
    expect(_painter(tester, 'first').time, pausedTime);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      _painter(tester, 'first').time,
      pausedTime + const Duration(milliseconds: 32),
    );
    expect(animation.samples, greaterThan(pausedSamples));
    expect(starts, 1);
    await _dispose(tester);
  });

  testWidgets('hidden sibling freezes while visible sibling keeps ticking', (
    tester,
  ) async {
    await tester.pumpWidget(_scene(true, second: true));
    await _frames(tester);
    await tester.pumpWidget(_scene(false, second: true));
    final hiddenTime = _painter(tester, 'first').time;
    final visibleTime = _painter(tester, 'second').time;
    await _frames(tester);
    expect(_painter(tester, 'first').time, hiddenTime);
    expect(_painter(tester, 'second').time, greaterThan(visibleTime));

    await tester.pumpWidget(_scene(true, second: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      _painter(tester, 'first').time,
      hiddenTime + const Duration(milliseconds: 16),
    );
    await tester.pumpWidget(_scene(false, second: false));
    final first = _painter(tester, 'first').time;
    final second = _painter(tester, 'second').time;
    await _frames(tester);
    expect(_painter(tester, 'first').time, first);
    expect(_painter(tester, 'second').time, second);
    expect(tester.binding.transientCallbackCount, 0);
    await _dispose(tester);
  });

  testWidgets('source swap while hidden waits for TickerMode', (tester) async {
    await tester.pumpWidget(_scene(true));
    await _frames(tester);
    await tester.pumpWidget(_scene(false));
    final replacement = _source.replaceAll('dur="1s"', 'dur="2s"');
    await tester.pumpWidget(_scene(false, source: replacement));
    await _frames(tester);
    expect(_painter(tester, 'first').time, Duration.zero);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_scene(true, source: replacement));
    await _frames(tester);
    expect(_painter(tester, 'first').time, greaterThan(Duration.zero));
    await _dispose(tester);
  });

  testWidgets('settled animation stays settled after TickerMode toggles', (
    tester,
  ) async {
    final finite = _source.replaceAll('repeatCount="indefinite"', '');
    var completions = 0;
    await tester.pumpWidget(
      _scene(true, source: finite, onComplete: () => completions++),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 2));
    expect(completions, 1);
    final settled = _painter(tester, 'first').time;
    await tester.pumpWidget(
      _scene(false, source: finite, onComplete: () => completions++),
    );
    await tester.pumpWidget(
      _scene(true, source: finite, onComplete: () => completions++),
    );
    await _frames(tester);
    expect(_painter(tester, 'first').time, settled);
    expect(completions, 1);
    expect(tester.binding.transientCallbackCount, 0);
    await _dispose(tester);
  });
}
