import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/smil_animation.dart';

/// 单次迭代时长（毫秒）。
const _durationMs = 1000;

/// 数值比较容差。
const _tolerance = 1e-9;

/// 构造默认 [10,20]→[20,40] 的列表动画，可覆盖各项参数。
SmilListAnimation _list({
  List<List<double>> values = const [
    [10, 20],
    [20, 40],
  ],
  int beginMs = 0,
  bool freeze = true,
  SmilRepeatCount repeat = SmilRepeatCount.once,
  SmilDirection direction = SmilDirection.normal,
  SmilCalcMode mode = SmilCalcMode.linear,
  List<double>? keyTimes,
  List<SmilSegmentEasing>? splines,
}) => SmilListAnimation(
  attributeName: 'stroke-dasharray',
  values: values,
  duration: const Duration(milliseconds: _durationMs),
  begin: Duration(milliseconds: beginMs),
  fillFreeze: freeze,
  repeatCount: repeat,
  direction: direction,
  calcMode: mode,
  keyTimes: keyTimes,
  keySplines: splines,
);

/// 取第 [ms] 毫秒的采样值。
List<double>? _at(SmilListAnimation a, int ms) =>
    a.sample(Duration(milliseconds: ms));

/// 断言列表逐项接近期望值。
void _expectList(List<double>? actual, List<double> expected) {
  expect(actual, isNotNull);
  expect(actual!.length, expected.length);
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], closeTo(expected[i], _tolerance), reason: 'index $i');
  }
}

/// 验证 [SmilListAnimation] 的时序、插值与结果独立性。
void main() {
  test('width 与 attributeName', () {
    final a = _list();
    expect(a.width, 2);
    expect(a.attributeName, 'stroke-dasharray');
    expect(
      _list(
        values: const [
          [1, 2, 3],
          [4, 5, 6],
        ],
      ).width,
      3,
    );
  });

  test('线性：[10,20]→[20,40] 中点是 [15,30]', () {
    final a = _list();
    _expectList(_at(a, 0), [10, 20]);
    _expectList(_at(a, 500), [15, 30]);
    _expectList(_at(a, 250), [12.5, 25]);
  });

  test('逐项算术与标量插值表达式一致（a + (b-a)*t）', () {
    final a = _list(
      values: const [
        [0.1, 7],
        [0.7, 3],
      ],
    );
    final s = SmilAnimation(
      attributeName: 'x',
      values: const [0.1, 0.7],
      duration: const Duration(milliseconds: _durationMs),
      begin: Duration.zero,
      fillFreeze: true,
    );
    for (var ms = 0; ms <= _durationMs; ms += 37) {
      final t = Duration(milliseconds: ms);
      expect(a.sample(t)![0], s.sample(t));
    }
  });

  test('多段与 keyTimes', () {
    final a = _list(
      values: const [
        [0, 0],
        [10, 100],
        [20, 0],
      ],
      keyTimes: const [0, 0.2, 1],
    );
    _expectList(_at(a, 100), [5, 50]);
    _expectList(_at(a, 200), [10, 100]);
    _expectList(_at(a, 600), [15, 50]);
  });

  group('spline', () {
    test('贝塞尔缓动作用于每一项', () {
      const curve = CubicBezier(0.42, 0, 0.58, 1);
      final a = _list(mode: SmilCalcMode.spline, splines: const [curve]);
      final eased = curve.transform(0.3);
      _expectList(_at(a, 300), [10 + 10 * eased, 20 + 20 * eased]);
    });

    test('steps(2, end)：阶跃处整体跳变', () {
      final a = _list(
        mode: SmilCalcMode.spline,
        splines: const [SmilStepsEasing(2)],
      );
      _expectList(_at(a, 400), [10, 20]);
      _expectList(_at(a, 600), [15, 30]);
      _expectList(_at(a, 1000), [20, 40]);
    });

    test('缺失的段线性回退', () {
      final a = _list(mode: SmilCalcMode.spline, splines: const []);
      _expectList(_at(a, 500), [15, 30]);
    });
  });

  group('discrete 与 paced', () {
    test('discrete 等分为帧数个区间，与 SmilAnimation 同语义', () {
      final a = _list(
        mode: SmilCalcMode.discrete,
        values: const [
          [1, 1],
          [2, 2],
          [3, 3],
        ],
      );
      _expectList(_at(a, 100), [1, 1]);
      _expectList(_at(a, 600), [2, 2]);
      _expectList(_at(a, 1000), [3, 3]);
    });

    test('paced 按 linear 处理', () {
      final p = _list(mode: SmilCalcMode.paced);
      final l = _list();
      for (final ms in [0, 123, 500, 999, 1000]) {
        expect(_at(p, ms), _at(l, ms));
      }
    });
  });

  group('direction', () {
    test('reverse：有向进度取反', () {
      final a = _list(direction: SmilDirection.reverse);
      _expectList(_at(a, 250), [17.5, 35]);
    });

    test('alternate 跨迭代交替方向', () {
      final a = _list(
        direction: SmilDirection.alternate,
        repeat: const SmilRepeatCount.indefinite(),
      );
      _expectList(_at(a, 250), [12.5, 25]);
      _expectList(_at(a, 1250), [17.5, 35]);
      _expectList(_at(a, 2250), [12.5, 25]);
    });

    test('alternateReverse 首轮反向', () {
      final a = _list(
        direction: SmilDirection.alternateReverse,
        repeat: const SmilRepeatCount.indefinite(),
      );
      _expectList(_at(a, 250), [17.5, 35]);
      _expectList(_at(a, 1250), [12.5, 25]);
    });
  });

  group('时序与定格', () {
    test('延迟内返回 null，到点开始', () {
      final a = _list(beginMs: 500);
      expect(_at(a, 0), isNull);
      expect(_at(a, 499), isNull);
      _expectList(_at(a, 500), [10, 20]);
      _expectList(_at(a, 1000), [15, 30]);
    });

    test('结束后：freeze 定格末值，无 freeze 返回 null', () {
      _expectList(_at(_list(), 5000), [20, 40]);
      expect(_at(_list(freeze: false), 5000), isNull);
      expect(_at(_list(freeze: false), 999), isNotNull);
      expect(_at(_list(freeze: false), 1000), isNull);
    });

    test('小数重复次数的定格', () {
      final a = _list(repeat: const SmilRepeatCount.finite(1.5));
      _expectList(_at(a, 5000), [15, 30]);
    });

    test('无限循环不会返回 null', () {
      final a = _list(
        repeat: const SmilRepeatCount.indefinite(),
        freeze: false,
      );
      _expectList(_at(a, 1250), [12.5, 25]);
    });
  });

  group('返回值独立性', () {
    test('插值结果每次都是新实例', () {
      final a = _list();
      final x = _at(a, 500)!;
      final y = _at(a, 500)!;
      expect(identical(x, y), isFalse);
      x[0] = 999;
      _expectList(_at(a, 500), [15, 30]);
    });

    test('discrete 不暴露内部关键帧列表', () {
      final a = _list(mode: SmilCalcMode.discrete);
      final x = _at(a, 100)!;
      expect(identical(x, a.values[0]), isFalse);
      x[0] = 999;
      expect(a.values[0][0], 10);
    });
  });

  test('关键帧长度不一致在 debug 下触发断言', () {
    expect(
      () => SmilListAnimation(
        attributeName: 'stroke-dasharray',
        values: const [
          [1, 2],
          [3],
        ],
        duration: const Duration(seconds: 1),
        begin: Duration.zero,
        fillFreeze: true,
      ),
      throwsAssertionError,
    );
  });

  test('同步基准解析：可参与 resolveSmilBeginTimes', () {
    final a = _list();
    final b = SmilListAnimation(
      attributeName: 'stroke-dasharray',
      values: const [
        [0],
        [1],
      ],
      duration: const Duration(seconds: 1),
      begin: Duration.zero,
      fillFreeze: true,
      beginSpec: const SmilBeginSpec(
        offset: Duration(milliseconds: 100),
        syncbaseId: 'a',
        onSyncbaseEnd: true,
      ),
    );
    final named = SmilListAnimation(
      attributeName: 'stroke-dasharray',
      values: a.values,
      duration: a.duration,
      begin: Duration.zero,
      fillFreeze: true,
      elementId: 'a',
    );
    resolveSmilBeginTimes([named, b]);
    expect(b.begin, const Duration(milliseconds: 1100));
  });
}
