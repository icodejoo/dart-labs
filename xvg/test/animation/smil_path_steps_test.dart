import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/smil_animation.dart';

/// 单次迭代时长（毫秒）。
const _durationMs = 1000;

/// 构造可插值的路径动画，[frameCount] 帧共享同一指令序列。
SmilPathAnimation _path({
  int frameCount = 2,
  SmilCalcMode mode = SmilCalcMode.spline,
  List<SmilSegmentEasing>? splines,
  SmilDirection direction = SmilDirection.normal,
  List<double>? keyTimes,
}) => SmilPathAnimation(
  frames: [for (var i = 0; i < frameCount; i++) 'M0 0L$i 0'],
  morph: PathMorphData(
    ops: const [kMorphMove, kMorphLine],
    frames: [
      for (var i = 0; i < frameCount; i++)
        Float64List.fromList([0, 0, i * 10.0, 0]),
    ],
  ),
  duration: const Duration(milliseconds: _durationMs),
  begin: Duration.zero,
  fillFreeze: true,
  calcMode: mode,
  keySplines: splines,
  keyTimes: keyTimes,
  direction: direction,
);

/// 取第 [ms] 毫秒的「位置」。
double? _at(SmilPathAnimation a, int ms) =>
    a.sample(Duration(milliseconds: ms));

/// 验证路径通道接受阶跃缓动与方向。
void main() {
  test('steps(2, end)：位置在 0.5 处从 0 跳到 0.5', () {
    final a = _path(splines: const [SmilStepsEasing(2)]);
    expect(_at(a, 100), 0);
    expect(_at(a, 490), 0);
    expect(_at(a, 510), 0.5);
    expect(_at(a, 990), 0.5);
    expect(_at(a, 5000), 1); // 定格终点
  });

  test('steps(2, start)：起点即跳到 0.5，末端跳到 1', () {
    final a = _path(
      splines: const [SmilStepsEasing(2, SmilStepPosition.start)],
    );
    expect(_at(a, 10), 0.5);
    expect(_at(a, 490), 0.5);
    expect(_at(a, 510), 1);
  });

  test('steps(1, end) 等价 step-end：整段保持起点', () {
    final a = _path(splines: const [SmilStepsEasing(1)]);
    expect(_at(a, 10), 0);
    expect(_at(a, 990), 0);
  });

  test('steps(1, start) 等价 step-start：整段取终点', () {
    final a = _path(
      splines: const [SmilStepsEasing(1, SmilStepPosition.start)],
    );
    expect(_at(a, 10), 1);
    expect(_at(a, 990), 1);
  });

  test('多段：位置整数部分是段下标，小数是阶跃输出', () {
    final a = _path(
      frameCount: 3,
      splines: const [SmilStepsEasing(2), SmilStepsEasing(4)],
    );
    // 第一段 0..0.5：局部进度 0.6 → steps(2) 得 0.5。
    expect(_at(a, 300), 0.5);
    // 第二段 0.5..1：局部进度 0.5 → steps(4) 得 0.5。
    expect(_at(a, 750), 1.5);
    expect(_at(a, 640), 1.25); // 局部 0.28 → floor(1.12)=1 → 0.25
  });

  test('阶跃输出本就在 [0,1]，钳制不改变阶跃位置', () {
    final a = _path(
      splines: const [SmilStepsEasing(3, SmilStepPosition.jumpBoth)],
    );
    for (final ms in [10, 200, 300, 600, 900]) {
      final v = _at(a, ms)!;
      expect(v, inInclusiveRange(0, 1));
    }
  });

  test('keySplines 仍可传 List<CubicBezier>', () {
    final curves = <CubicBezier>[const CubicBezier(0.42, 0, 0.58, 1)];
    final a = SmilPathAnimation(
      frames: const ['M0 0L0 0', 'M0 0L10 0'],
      morph: PathMorphData(
        ops: const [kMorphMove, kMorphLine],
        frames: [
          Float64List.fromList([0, 0, 0, 0]),
          Float64List.fromList([0, 0, 10, 0]),
        ],
      ),
      duration: const Duration(milliseconds: _durationMs),
      begin: Duration.zero,
      fillFreeze: true,
      calcMode: SmilCalcMode.spline,
      keySplines: curves,
    );
    expect(_at(a, 500), closeTo(0.5, 1e-9));
    expect(_at(a, 250), closeTo(curves.first.transform(0.25), 1e-12));
  });

  test('回弹曲线仍被钳制在段内（已知偏差，保持）', () {
    final a = _path(splines: const [CubicBezier(0.175, 0.885, 0.32, 1.275)]);
    for (var ms = 0; ms <= _durationMs; ms += 20) {
      expect(_at(a, ms)!, inInclusiveRange(0, 1));
    }
  });

  test('direction：反向时阶跃按有向进度', () {
    final a = _path(
      splines: const [SmilStepsEasing(2)],
      direction: SmilDirection.reverse,
    );
    expect(_at(a, 100), 0.5); // 有向进度 0.9
    expect(_at(a, 900), 0); // 有向进度 0.1
  });

  test('direction：alternate 下离散切换也随方向', () {
    final a = SmilPathAnimation(
      frames: const ['A', 'B', 'C'],
      duration: const Duration(milliseconds: _durationMs),
      begin: Duration.zero,
      fillFreeze: false,
      repeatCount: const SmilRepeatCount.indefinite(),
      direction: SmilDirection.alternate,
      calcMode: SmilCalcMode.discrete,
    );
    expect(_at(a, 100), 0);
    expect(_at(a, 500), 1);
    expect(_at(a, 900), 2);
    expect(_at(a, 1100), 2); // 第二轮反向：有向进度 0.9
    expect(_at(a, 1900), 0);
  });

  test('direction 默认 normal', () {
    expect(_path().direction, SmilDirection.normal);
  });
}
