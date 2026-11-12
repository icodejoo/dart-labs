import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/smil_animation.dart' as nw;

import '_oracle/smil_animation_oracle.dart' as old;
import 'discrete_reference.dart';

/// 每个通道的随机参数组数。
const _casesPerChannel = 12000;

/// 每组参数的采样时刻数。
const _timesPerCase = 12;

/// 固定随机种子，保证失败可复现。
const _seed = 20261103;

/// 一组随机 SMIL 参数，同时用于构造新旧两套实现。
class _Spec {
  _Spec(math.Random r, {required this.valueCount}) {
    durationMs = r.nextInt(8) == 0 ? 0 : 1 + r.nextInt(3000);
    beginMs = switch (r.nextInt(3)) {
      0 => 0,
      1 => -r.nextInt(1500),
      _ => r.nextInt(2000),
    };
    freeze = r.nextBool();
    repeatKind = r.nextInt(4);
    repeatValue = switch (repeatKind) {
      0 => 1.0,
      1 => (1 + r.nextInt(4)).toDouble(),
      2 => (r.nextInt(80) + 1) / 10,
      _ => 1.0,
    };
    mode = nw.SmilCalcMode.values[r.nextInt(4)];
    // keyTimes：缺省 / 合法 / 长度不匹配。
    final timesKind = r.nextInt(3);
    if (timesKind == 1 || timesKind == 2) {
      final n = timesKind == 1 ? valueCount : valueCount + 1 + r.nextInt(2);
      final raw = [for (var i = 0; i < n; i++) r.nextDouble()]..sort();
      raw[0] = 0;
      raw[n - 1] = 1;
      keyTimes = raw;
    }
    // keySplines：缺省，或长度可能偏短/偏长的贝塞尔。
    if (r.nextInt(3) != 0) {
      final n = math.max(0, valueCount - 1 + r.nextInt(3) - 1);
      splines = [
        for (var i = 0; i < n; i++)
          [
            r.nextDouble(),
            r.nextDouble() * 2 - 0.5,
            r.nextDouble(),
            r.nextDouble() * 2 - 0.5,
          ],
      ];
      if (r.nextInt(6) == 0 && splines!.isNotEmpty) {
        // 线性控制点走缓动函数的快速返回分支。
        splines![0] = [0, 0, 1, 1];
      }
    }
  }

  final int valueCount;
  late final int durationMs;
  late final int beginMs;
  late final bool freeze;
  late final int repeatKind;
  late final double repeatValue;
  late final nw.SmilCalcMode mode;
  List<double>? keyTimes;
  List<List<double>>? splines;

  Duration get duration => Duration(milliseconds: durationMs);
  Duration get begin => Duration(milliseconds: beginMs);

  nw.SmilRepeatCount get newRepeat => repeatKind == 3
      ? const nw.SmilRepeatCount.indefinite()
      : nw.SmilRepeatCount.finite(repeatValue);
  old.SmilRepeatCount get oldRepeat => repeatKind == 3
      ? const old.SmilRepeatCount.indefinite()
      : old.SmilRepeatCount.finite(repeatValue);
  double? referenceProgress(Duration t) => referenceNormalProgress(
    time: t,
    begin: begin,
    duration: duration,
    indefinite: newRepeat.indefinite,
    repeatCount: repeatValue,
    freeze: freeze,
  );

  old.SmilCalcMode get oldMode => old.SmilCalcMode.values[mode.index];

  List<nw.CubicBezier>? get newSplines => splines == null
      ? null
      : [for (final s in splines!) nw.CubicBezier(s[0], s[1], s[2], s[3])];
  List<old.CubicBezier>? get oldSplines => splines == null
      ? null
      : [for (final s in splines!) old.CubicBezier(s[0], s[1], s[2], s[3])];

  /// 覆盖开始前、迭代内、边界、结束后的采样时刻（微秒级随机 + 整毫秒边界）。
  List<Duration> times(math.Random r) {
    final end = beginMs + durationMs * (repeatKind == 3 ? 4 : repeatValue);
    return [
      for (var i = 0; i < _timesPerCase; i++)
        switch (i) {
          0 => Duration(milliseconds: beginMs - 1),
          1 => Duration(milliseconds: beginMs),
          2 => Duration(microseconds: (end * 1000).round()),
          3 => Duration(microseconds: (end * 1000).round() - 1),
          4 => Duration(microseconds: (end * 1000).round() + 1),
          5 => Duration(milliseconds: beginMs + durationMs),
          _ => Duration(
            microseconds:
                beginMs * 1000 +
                (r.nextDouble() * (end + 500 - beginMs) * 1000).round() -
                500000,
          ),
        },
    ];
  }
}

/// 逐位比较 double：NaN 视为相等，-0.0 与 0.0 视为不同。
void _expectBits(double? actual, double? expected, String reason) {
  if (actual == null || expected == null) {
    expect(actual, expected, reason: reason);
  } else if (expected.isNaN) {
    expect(actual.isNaN, isTrue, reason: reason);
  } else {
    final data = ByteData(16)
      ..setFloat64(0, actual)
      ..setFloat64(8, expected);
    expect(data.getUint64(0), data.getUint64(8), reason: reason);
  }
}

/// 随机生成 `[0, 1]` 附近的数值，偶尔越界。
double _rand(math.Random r, double lo, double hi) =>
    lo + r.nextDouble() * (hi - lo);

/// 离散 motion/color 按独立规范参考比对，其余按改动前的完整库逐位回归。
void main() {
  test('motion：discrete 按规范，其余与旧实现逐位相同', () {
    final r = math.Random(_seed);
    var compared = 0;
    for (var c = 0; c < _casesPerChannel; c++) {
      final tableSize = 2 + r.nextInt(11);
      final raw = [
        for (var i = 0; i < tableSize; i++)
          [
            _rand(r, -200, 200),
            _rand(r, -200, 200),
            r.nextInt(5) == 0 ? 359.0 - r.nextInt(3) : _rand(r, -180, 360),
          ],
      ];
      final useKeyPoints = r.nextBool();
      final points = useKeyPoints
          ? [for (var i = 0; i < 2 + r.nextInt(4); i++) _rand(r, -0.3, 1.3)]
          : null;
      final spec = _Spec(r, valueCount: points?.length ?? 2);
      final a = nw.SmilMotionAnimation(
        samples: [for (final s in raw) nw.SmilMotionSample(s[0], s[1], s[2])],
        duration: spec.duration,
        begin: spec.begin,
        fillFreeze: spec.freeze,
        repeatCount: spec.newRepeat,
        keyPoints: points,
        keyTimes: spec.keyTimes,
        keySplines: spec.newSplines,
        calcMode: spec.mode,
      );
      final b = old.SmilMotionAnimation(
        samples: [for (final s in raw) old.SmilMotionSample(s[0], s[1], s[2])],
        duration: spec.duration,
        begin: spec.begin,
        fillFreeze: spec.freeze,
        repeatCount: spec.oldRepeat,
        keyPoints: points,
        keyTimes: spec.keyTimes,
        keySplines: spec.oldSplines,
        calcMode: spec.oldMode,
      );
      for (final t in spec.times(r)) {
        final x = a.sample(t);
        final p = spec.referenceProgress(t);
        final y = spec.mode == nw.SmilCalcMode.discrete && points != null
            ? _referenceMotion(raw, points, spec.keyTimes, p)
            : b.sample(t);
        final reason = 'case $c t=$t';
        if (x == null || y == null) {
          expect(x == null, y == null, reason: reason);
          continue;
        }
        _expectBits(x.x, y.x, '$reason x');
        _expectBits(x.y, y.y, '$reason y');
        _expectBits(x.angleDegrees, y.angleDegrees, '$reason angle');
        compared++;
      }
    }
    expect(compared, greaterThan(_casesPerChannel * 4));
  });

  test('color：discrete 按规范，其余与旧实现逐位相同', () {
    final r = math.Random(_seed + 1);
    var compared = 0;
    for (var c = 0; c < _casesPerChannel; c++) {
      final n = 2 + r.nextInt(5);
      final values = [for (var i = 0; i < n; i++) r.nextInt(0x100000000)];
      final spec = _Spec(r, valueCount: n);
      final a = nw.SmilColorAnimation(
        values: values,
        duration: spec.duration,
        begin: spec.begin,
        fillFreeze: spec.freeze,
        repeatCount: spec.newRepeat,
        calcMode: spec.mode,
        keyTimes: spec.keyTimes,
        keySplines: spec.newSplines,
      );
      final b = old.SmilColorAnimation(
        values: values,
        duration: spec.duration,
        begin: spec.begin,
        fillFreeze: spec.freeze,
        repeatCount: spec.oldRepeat,
        calcMode: spec.oldMode,
        keyTimes: spec.keyTimes,
        keySplines: spec.oldSplines,
      );
      for (final t in spec.times(r)) {
        final x = a.sample(t);
        final p = spec.referenceProgress(t);
        final y = spec.mode == nw.SmilCalcMode.discrete
            ? (p == null
                  ? null
                  : values[referenceDiscreteIndex(p, n, spec.keyTimes)])
            : b.sample(t);
        expect(x, y, reason: 'case $c t=$t');
        if (x != null) compared++;
      }
    }
    expect(compared, greaterThan(_casesPerChannel * 4));
  });

  test('path：默认参数下与旧实现逐位相同', () {
    final r = math.Random(_seed + 2);
    var compared = 0;
    for (var c = 0; c < _casesPerChannel; c++) {
      final n = 1 + r.nextInt(6);
      final frames = [for (var i = 0; i < n; i++) 'M0 0L$i $c'];
      final morphable = r.nextBool();
      final data = [
        for (var i = 0; i < n; i++)
          [for (var k = 0; k < 4; k++) _rand(r, -50, 50)],
      ];
      final spec = _Spec(r, valueCount: n);
      final a = nw.SmilPathAnimation(
        frames: frames,
        duration: spec.duration,
        begin: spec.begin,
        fillFreeze: spec.freeze,
        morph: morphable
            ? nw.PathMorphData(
                ops: const [nw.kMorphMove, nw.kMorphLine],
                frames: [for (final d in data) Float64List.fromList(d)],
              )
            : null,
        repeatCount: spec.newRepeat,
        calcMode: spec.mode,
        keyTimes: spec.keyTimes,
        keySplines: spec.newSplines,
      );
      final b = old.SmilPathAnimation(
        frames: frames,
        duration: spec.duration,
        begin: spec.begin,
        fillFreeze: spec.freeze,
        morph: morphable
            ? old.PathMorphData(
                ops: const [old.kMorphMove, old.kMorphLine],
                frames: [for (final d in data) Float64List.fromList(d)],
              )
            : null,
        repeatCount: spec.oldRepeat,
        calcMode: spec.oldMode,
        keyTimes: spec.keyTimes,
        keySplines: spec.oldSplines,
      );
      for (final t in spec.times(r)) {
        final x = a.sample(t);
        final y = b.sample(t);
        _expectBits(x, y, 'case $c t=$t');
        if (x != null) compared++;
      }
    }
    expect(compared, greaterThan(_casesPerChannel * 4));
  });
}

/// 按规范选取 keyPoint 后，以弧长在采样表上插值；角度保持所在段角度。
old.SmilMotionSample? _referenceMotion(
  List<List<double>> samples,
  List<double> points,
  List<double>? times,
  double? progress,
) {
  if (progress == null) return null;
  final point = points[referenceDiscreteIndex(progress, points.length, times)];
  final scaled = (point * (samples.length - 1)).clamp(
    0.0,
    (samples.length - 1).toDouble(),
  );
  final index = scaled.floor().clamp(0, samples.length - 2);
  final fraction = scaled - index;
  final a = samples[index];
  final b = samples[index + 1];
  return old.SmilMotionSample(
    a[0] + (b[0] - a[0]) * fraction,
    a[1] + (b[1] - a[1]) * fraction,
    a[2],
  );
}
