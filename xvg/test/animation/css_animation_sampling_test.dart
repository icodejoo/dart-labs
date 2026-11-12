import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/smil_animation.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/svg_dom.dart';

/// 单周期毫秒数，便于独立计算进度。
const _period = 1000;

/// 数值参考容差。
const _epsilon = 1e-5;

/// 常用的透明度关键帧。
const _fade = 'from{opacity:0}to{opacity:1}';

/// 构造没有 id 与静态变换的 CSS 动画节点。
SvgDocument _document(String frames, String animation) =>
    parseAnimatedSvgDocument('''<svg width="100" height="100">
<style>@keyframes a {$frames} rect {animation:$animation}</style>
<rect width="10" height="10"/></svg>''');

/// 取得唯一图形节点。
SvgNode _node(String frames, String animation) =>
    _document(frames, animation).root.children.single;

/// 毫秒采样时间。
Duration _at(int milliseconds) => Duration(milliseconds: milliseconds);

/// 以二分法独立反解贝塞尔横坐标，再求纵坐标。
double _bezier(double x, List<double> points) {
  /// 独立的三次多项式。
  double coordinate(double t, double a, double b) =>
      3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t;
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 100; i++) {
    final mid = (low + high) / 2;
    if (coordinate(mid, points[0], points[2]) < x) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return coordinate((low + high) / 2, points[1], points[3]);
}

/// 验证解析、层叠、编译与逐帧采样的衔接。
void main() {
  for (final curve in <List<double>>[
    [.68, -.55, .265, 1.55],
    [1, 0, 0, 1],
  ]) {
    test('无 id 节点的 cubic-bezier $curve 与独立二分参考一致', () {
      final node = _node(
        'from{x:0;transform:translate(0px)}to{x:100;transform:translate(100px)}',
        'a 1s cubic-bezier(${curve.join(',')}) forwards',
      );
      for (final ms in [1, 101, 249, 401, 499, 501, 599, 751, 899, 999]) {
        final expected = 100 * _bezier(ms / _period, curve);
        expect(
          node.animations.single.sample(_at(ms)),
          closeTo(expected, _epsilon),
        );
        expect(
          node.transformAnimations.single.sample(_at(ms))!.first,
          closeTo(expected, _epsilon),
        );
      }
    });
  }
  for (final entry in <String, (int, bool)>{
    'step-end': (1, false),
    'step-start': (1, true),
    'steps(3,end)': (3, false),
    'steps(2,start)': (2, true),
  }.entries) {
    test('${entry.key} 与独立阶梯公式一致', () {
      final node = _node(_fade, 'a 1s ${entry.key}');
      final (count, start) = entry.value;
      for (final ms in [1, 249, 251, 332, 334, 499, 501, 665, 667, 999]) {
        final expected =
            ((ms / _period * count).floor() + (start ? 1 : 0)) / count;
        expect(
          node.animations.single.sample(_at(ms)),
          closeTo(expected, _epsilon),
        );
      }
    });
  }
  test('rotate 0 到 720 保持数值线性，不折叠转角', () {
    final track = _node(
      'from{transform:rotate(0deg)}to{transform:rotate(720deg)}',
      'a 1s linear',
    ).transformAnimations.single;
    for (final ms in [250, 500, 750]) {
      expect(
        track.sample(_at(ms))!.first,
        closeTo(720 * ms / _period, _epsilon),
      );
    }
  });
  test('alternate 第二周期与第一周期镜像且 forwards 冻结回起点', () {
    final doc = _document(_fade, 'a 1s linear 2 alternate forwards');
    final track = doc.root.children.single.animations.single;
    expect(doc.totalDuration, _at(2 * _period));
    expect(doc.hasIndefiniteLoop, isFalse);
    for (final ms in [1001, 1249, 1501, 1751, 1999]) {
      expect(
        track.sample(_at(ms)),
        closeTo(track.sample(_at(2 * _period - ms))!, _epsilon),
      );
    }
    expect(track.sample(_at(2001)), 0);
  });
  test('alternate-reverse 从终点开始，infinite 持续采样', () {
    final doc = _document(_fade, 'a 1s linear infinite alternate-reverse');
    final track = doc.root.children.single.animations.single;
    expect(track.sample(Duration.zero), 1);
    expect(doc.hasIndefiniteLoop, isTrue);
    expect(doc.totalDuration, Duration.zero);
    expect(track.sample(_at(61251)), closeTo(.251, _epsilon));
  });
  test('delay 经 begin 解析后仍保留，有限动画结束移除或冻结', () {
    for (final forwards in [false, true]) {
      final doc = _document(
        'from{opacity:.2}to{opacity:.8}',
        'a 1s linear 500ms 2 ${forwards ? 'forwards' : 'none'}',
      );
      final track = doc.root.children.single.animations.single;
      expect(track.begin, _at(500));
      expect(doc.totalDuration, _at(2500));
      expect(track.sample(_at(499)), isNull);
      expect(track.sample(_at(501)), closeTo(.2006, _epsilon));
      expect(
        track.sample(_at(2501)),
        forwards ? closeTo(.8, _epsilon) : isNull,
      );
    }
  });
  test('同一节点多个动画分别驱动属性，CSS 变换先于 SMIL', () {
    final doc = parseAnimatedSvgDocument('''<svg><style>
@keyframes a{from{opacity:0}to{opacity:1}}
@keyframes b{from{x:10;transform:translate(0px)}to{x:30;transform:translate(20px)}}
rect{animation:a 1s linear,b 2s linear}</style><rect>
<animateTransform type="scale" values="1;2" dur="2s"/>
</rect></svg>''');
    final node = doc.root.children.single;
    expect(node.animations.map((a) => a.attributeName), ['opacity', 'x']);
    expect(node.animations[0].sample(_at(501)), closeTo(.501, _epsilon));
    expect(node.animations[1].sample(_at(501)), closeTo(15.01, _epsilon));
    expect(node.transformAnimations.map((a) => a.type), [
      SmilTransformType.translate,
      SmilTransformType.scale,
    ]);
  });
}
