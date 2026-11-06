import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/smil_animation.dart';

/// 创建时序判定专用的变换动画。
SmilTransformAnimation _animation({
  Duration begin = Duration.zero,
  Duration duration = const Duration(seconds: 1),
  bool freeze = false,
  SmilRepeatCount repeat = SmilRepeatCount.once,
  SmilDirection direction = SmilDirection.normal,
  bool replaces = false,
}) => SmilTransformAnimation(
  type: SmilTransformType.translate,
  values: const [
    [0, 0, 0],
    [1, 2, 0],
  ],
  duration: duration,
  begin: begin,
  fillFreeze: freeze,
  repeatCount: repeat,
  direction: direction,
  replacesStaticTransform: replaces,
);

/// 禁止插值求值，证明 isActiveAt 只走时序路径。
class _UncallableEasing implements SmilSegmentEasing {
  /// 若时序查询误入插值路径则立即失败。
  @override
  double transform(double t) => throw StateError('时序查询不应求缓动');
}

/// 验证静态替换标记、时序真值表及随机一致性。
void main() {
  test('静态替换标记默认为 false，可显式开启', () {
    expect(_animation().replacesStaticTransform, isFalse);
    expect(_animation(replaces: true).replacesStaticTransform, isTrue);
  });
  test('生效时序真值表覆盖 delay、冻结、负 begin、无限与零时长', () {
    for (final direction in SmilDirection.values) {
      for (final freeze in [false, true]) {
        final delayed = _animation(
          begin: const Duration(seconds: 1),
          freeze: freeze,
          direction: direction,
        );
        for (final (ms, active) in [
          (999, false),
          (1000, true),
          (1500, true),
          (1999, true),
          (2000, freeze),
          (2500, freeze),
        ]) {
          final t = Duration(milliseconds: ms);
          expect(delayed.isActiveAt(t), active);
          expect(delayed.isActiveAt(t), delayed.sample(t) != null);
        }
        final negative = _animation(
          begin: const Duration(milliseconds: -500),
          freeze: freeze,
          direction: direction,
        );
        expect(negative.isActiveAt(Duration.zero), isTrue);
        expect(negative.isActiveAt(const Duration(milliseconds: 500)), freeze);
        final infinite = _animation(
          repeat: const SmilRepeatCount.indefinite(),
          direction: direction,
          freeze: freeze,
        );
        expect(infinite.isActiveAt(const Duration(days: 365)), isTrue);
        final zero = _animation(
          begin: const Duration(seconds: 1),
          duration: Duration.zero,
          direction: direction,
          freeze: freeze,
        );
        expect(zero.isActiveAt(const Duration(milliseconds: 999)), isFalse);
        expect(zero.isActiveAt(const Duration(seconds: 1)), isTrue);
        expect(zero.isActiveAt(const Duration(days: 365)), isTrue);
      }
    }
  });
  test('时序查询不会调用缓动', () {
    final a = SmilTransformAnimation(
      type: SmilTransformType.translate,
      values: const [
        [0, 0, 0],
        [1, 2, 0],
      ],
      duration: const Duration(seconds: 1),
      begin: Duration.zero,
      fillFreeze: true,
      calcMode: SmilCalcMode.spline,
      keySplines: [_UncallableEasing()],
    );
    expect(a.isActiveAt(const Duration(milliseconds: 500)), isTrue);
  });
  test('10000 组随机参数与 sample 非空判定一致', () {
    final random = Random(0x543361);
    for (var i = 0; i < 10000; i++) {
      final a = _animation(
        begin: Duration(microseconds: random.nextInt(4000001) - 2000000),
        duration: Duration(
          microseconds: i % 7 == 0 ? 0 : random.nextInt(2000001),
        ),
        freeze: random.nextBool(),
        replaces: random.nextBool(),
        repeat: i % 3 == 0
            ? const SmilRepeatCount.indefinite()
            : SmilRepeatCount.finite(0.1 + random.nextInt(40) / 10),
        direction: SmilDirection.values[i % SmilDirection.values.length],
      );
      for (final t in [
        a.begin - const Duration(microseconds: 1),
        a.begin,
        a.begin + a.duration,
        Duration(microseconds: random.nextInt(10000001) - 2000000),
      ]) {
        expect(a.isActiveAt(t), a.sample(t) != null, reason: '$i/$t');
      }
    }
  });
}
