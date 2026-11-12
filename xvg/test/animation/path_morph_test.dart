// `<animate attributeName="d">` 路径变形：规范化与兼容性判断、采样位置语义
// （keyTimes / spline / discrete / freeze / repeat / begin）、像素断言。

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/smil_animation.dart';
import 'package:xvg/src/animation/svg_path_morph.dart';

import 'node_test_utils.dart';
import 'pixel_test_utils.dart';

SmilPathAnimation _anim({
  required List<String> frames,
  Duration duration = const Duration(seconds: 1),
  Duration begin = Duration.zero,
  bool freeze = false,
  SmilRepeatCount repeat = SmilRepeatCount.once,
  SmilCalcMode calcMode = SmilCalcMode.linear,
  List<double>? keyTimes,
  List<CubicBezier>? keySplines,
}) => SmilPathAnimation(
  frames: frames,
  morph: buildPathMorphData(frames),
  duration: duration,
  begin: begin,
  fillFreeze: freeze,
  repeatCount: repeat,
  calcMode: calcMode,
  keyTimes: keyTimes,
  keySplines: keySplines,
);

const _short = 'M0 0h100v50h-100z';
const _tall = 'M0 0H100V100H0Z';

void main() {
  group('buildPathMorphData 规范化', () {
    test('相对/绝对、H/V/L 写法不同但命令序列一致 -> 兼容', () {
      final data = buildPathMorphData([_short, _tall])!;
      expect(data.ops, [
        kMorphMove,
        kMorphLine,
        kMorphLine,
        kMorphLine,
        kMorphClose,
      ]);
      // 相对坐标已转为绝对：h100 v50 h-100
      expect(data.frames[0], [0, 0, 100, 0, 100, 50, 0, 50]);
      expect(data.frames[1], [0, 0, 100, 0, 100, 100, 0, 100]);
    });

    test('M 之后的隐式坐标对按 L 处理', () {
      final data = buildPathMorphData(['M0 0 10 10 20 0', 'M0 0L5 5L9 9'])!;
      expect(data.ops, [kMorphMove, kMorphLine, kMorphLine]);
    });

    test('S 规范化为 C（反射控制点），T 规范化为 Q', () {
      final cubic = buildPathMorphData([
        'M0 0C0 10 10 10 10 0S20 -10 20 0',
        'M0 0C0 20 20 20 20 0C20 -20 40 -20 40 0',
      ])!;
      expect(cubic.ops, [kMorphMove, kMorphCubic, kMorphCubic]);
      // 反射控制点 = 2 * 当前点(10,0) - 上一个 x2(10,10) = (10,-10)
      expect(cubic.frames[0].sublist(8, 14), [10, -10, 20, -10, 20, 0]);
      final quad = buildPathMorphData([
        'M0 0Q5 5 10 0T20 0',
        'M0 0Q5 5 10 0Q15 -5 20 0',
      ])!;
      expect(quad.ops, [kMorphMove, kMorphQuad, kMorphQuad]);
    });

    test('命令序列或参数个数不同 -> null（退化为离散）', () {
      expect(buildPathMorphData(['M0 0h10', 'M0 0h10v10']), isNull);
      expect(buildPathMorphData(['M0 0L1 1', 'M0 0Q1 1 2 2']), isNull);
    });

    test('圆弧标志位不同 -> null；相同则兼容', () {
      expect(
        buildPathMorphData(['M0 0A5 5 0 0 1 10 0', 'M0 0A5 5 0 1 1 10 0']),
        isNull,
      );
      final data = buildPathMorphData([
        'M0 0A5 5 0 0 1 10 0',
        'M0 0a8 8 0 0 1 20 0',
      ])!;
      expect(data.ops, [kMorphMove, kMorphArc]);
      expect(data.frames[1].sublist(2), [8, 8, 0, 0, 1, 20, 0]);
    });

    test('残缺路径 -> null', () {
      expect(buildPathMorphData(['M0', 'M0 0L1 1']), isNull);
      expect(buildPathMorphData(['10 10', 'M0 0L1 1']), isNull);
      expect(buildPathMorphData(['M0 0L1 1', 'M0 0L1']), isNull);
      expect(buildPathMorphData(['M0 0L1 1']), isNull, reason: '至少两帧');
    });
  });

  group('parseSmilPathValues', () {
    test('values 按分号切分并丢弃空项', () {
      expect(parseSmilPathValues(values: 'M0 0L1 1; M0 0L2 2;'), [
        'M0 0L1 1',
        'M0 0L2 2',
      ]);
    });

    test('回退到 from/to；不足两项返回 null', () {
      expect(parseSmilPathValues(from: 'M0 0', to: 'M1 1'), ['M0 0', 'M1 1']);
      expect(parseSmilPathValues(values: 'M0 0'), isNull);
      expect(parseSmilPathValues(), isNull);
    });
  });

  group('SmilPathAnimation.sample 位置语义', () {
    test('linear：位置 = 关键帧下标 + 段内进度', () {
      final a = _anim(frames: [_short, _tall, _short]);
      expect(a.sample(Duration.zero), 0);
      expect(a.sample(kMs * 250), closeTo(0.5, 1e-9));
      expect(a.sample(kMs * 500), closeTo(1, 1e-9));
      expect(a.sample(kMs * 750), closeTo(1.5, 1e-9));
    });

    test('keyTimes 决定各段占比', () {
      final a = _anim(frames: [_short, _tall, _short], keyTimes: [0, 0.2, 1]);
      expect(a.sample(kMs * 100), closeTo(0.5, 1e-9)); // 第一段 0..0.2
      expect(a.sample(kMs * 600), closeTo(1.5, 1e-9)); // 第二段 0.2..1
    });

    test('spline 缓动段内进度，并钳制到 [0, 1]', () {
      final eased = _anim(
        frames: [_short, _tall],
        calcMode: SmilCalcMode.spline,
        keySplines: [const CubicBezier(0.5, 0, 0.5, 1)],
      );
      final p = eased.sample(kMs * 250)!;
      expect(p, greaterThan(0));
      expect(p, lessThan(0.25), reason: 'ease-in-out 前半段慢于线性');
      final overshoot = _anim(
        frames: [_short, _tall],
        calcMode: SmilCalcMode.spline,
        keySplines: [const CubicBezier(0.5, 2, 0.5, 2)],
      );
      for (var ms = 0; ms < 1000; ms += 50) {
        final v = overshoot.sample(kMs * ms)!;
        expect(v, inInclusiveRange(0, 1));
      }
    });

    test('paced 按 linear 处理', () {
      final a = _anim(
        frames: [_short, _tall, _short],
        calcMode: SmilCalcMode.paced,
      );
      expect(a.sample(kMs * 250), closeTo(0.5, 1e-9));
    });

    test('discrete：时长等分为 n 个区间，位置恒为整数', () {
      final a = _anim(
        frames: [_short, _tall, _short],
        calcMode: SmilCalcMode.discrete,
      );
      expect(a.sample(kMs * 100), 0);
      expect(a.sample(kMs * 400), 1);
      expect(a.sample(kMs * 900), 2);
    });

    test('discrete + keyTimes：按 keyTimes 切换', () {
      final a = _anim(
        frames: [_short, _tall, _short],
        calcMode: SmilCalcMode.discrete,
        keyTimes: [0, 0.8, 0.9],
      );
      expect(a.sample(kMs * 700), 0);
      expect(a.sample(kMs * 850), 1);
      expect(a.sample(kMs * 950), 2);
    });

    test('形状不兼容 -> 退化为离散（两帧在 50% 处切换）', () {
      final a = _anim(frames: [_short, 'M0 0h100v100z']);
      expect(a.morph, isNull);
      expect(a.interpolates, isFalse);
      expect(a.sample(kMs * 250), 0);
      expect(a.sample(kMs * 750), 1);
    });

    test('begin 之前为 null；结束后无 freeze 为 null，有 freeze 定格末帧', () {
      final remove = _anim(frames: [_short, _tall], begin: kMs * 1000);
      expect(remove.sample(kMs * 999), isNull);
      expect(remove.sample(kMs * 1000), 0);
      expect(remove.sample(kMs * 2500), isNull);
      final freeze = _anim(
        frames: [_short, _tall],
        begin: kMs * 1000,
        freeze: true,
      );
      expect(freeze.sample(kMs * 9000), 1);
    });

    test('repeatCount：有限次数与 indefinite', () {
      final twice = _anim(
        frames: [_short, _tall],
        repeat: const SmilRepeatCount.finite(2),
      );
      expect(twice.sample(kMs * 1500), closeTo(0.5, 1e-9));
      expect(twice.sample(kMs * 2500), isNull);
      final forever = _anim(
        frames: [_short, _tall],
        repeat: const SmilRepeatCount.indefinite(),
      );
      expect(forever.sample(kMs * 7250), closeTo(0.25, 1e-9));
    });
  });

  group('解析', () {
    test('d 动画进入 pathAnimations，且不再出现在数值 animations 里', () {
      final doc = parsePixelDoc(
        '<path d="$_short" fill="#000">'
        '<animate attributeName="d" values="$_short;$_tall" dur="1s"/></path>',
      );
      final path = doc.root.children.single;
      expect(path.animations, isEmpty);
      final anim = path.pathAnimations.single;
      expect(anim.morph, isNotNull);
      expect(anim.frames, [_short, _tall]);
    });

    test('from/to 简写与 syncbase begin', () {
      final doc = parsePixelDoc(
        '<path d="$_short"><animate id="a" attributeName="d" '
        'from="$_short" to="$_tall" dur="1s"/>'
        '<animate attributeName="d" values="$_tall;$_short" dur="1s" '
        'begin="a.end+0.5s"/></path>',
      );
      final anims = pathAnimationsOf(doc.root);
      expect(anims, hasLength(2));
      expect(anims[1].begin, const Duration(milliseconds: 1500));
    });

    test('只有一个值的 d 动画被丢弃', () {
      final doc = parsePixelDoc(
        '<path d="$_short"><animate attributeName="d" values="$_tall" '
        'dur="1s"/></path>',
      );
      expect(pathAnimationsOf(doc.root), isEmpty);
    });
  });

  group('像素', () {
    // 动画把矩形高度从 50 变到 100；采样 x=50 一列。
    String morph(String extra) =>
        '<path fill="#000" d="$_short"><animate attributeName="d" '
        'values="$_short;$_tall" dur="1s" $extra/></path>';

    test('线性插值：t=0.5s 时高度约 75', () async {
      final doc = parsePixelDoc(morph('fill="freeze"'));
      final px = await renderAt(doc, kMs * 500);
      expect(alphaAt(px, 50, 70), 255);
      expect(alphaAt(px, 50, 80), 0);
      final start = await renderAt(doc, Duration.zero);
      expect(alphaAt(start, 50, 45), 255);
      expect(alphaAt(start, 50, 55), 0);
    });

    test('freeze 定格末帧；无 freeze 回到静态 d', () async {
      final frozen = await renderAt(
        parsePixelDoc(morph('fill="freeze"')),
        const Duration(seconds: 5),
      );
      expect(alphaAt(frozen, 50, 95), 255);
      final removed = await renderAt(
        parsePixelDoc(morph('')),
        const Duration(seconds: 5),
      );
      expect(alphaAt(removed, 50, 45), 255);
      expect(alphaAt(removed, 50, 55), 0, reason: '回到静态 d（高度 50）');
    });

    test('begin 偏移：开始之前显示静态 d', () async {
      final doc = parsePixelDoc(morph('begin="1s" fill="freeze"'));
      final before = await renderAt(doc, kMs * 500);
      expect(alphaAt(before, 50, 55), 0);
      final after = await renderAt(doc, const Duration(seconds: 3));
      expect(alphaAt(after, 50, 95), 255);
    });

    test('不兼容的形状离散切换：前半显示第一帧，后半显示第二帧', () async {
      final doc = parsePixelDoc(
        '<path fill="#000" d="$_short"><animate attributeName="d" '
        'values="$_short;M0 0h100v100z" dur="1s" fill="freeze"/></path>',
      );
      final first = await renderAt(doc, kMs * 250);
      expect(alphaAt(first, 50, 45), 255);
      expect(alphaAt(first, 50, 80), 0);
      final second = await renderAt(doc, kMs * 750);
      expect(alphaAt(second, 90, 80), 255, reason: '第二帧是右上三角形');
    });

    test('calcMode=discrete：即使形状兼容也只显示整数帧，不插值', () async {
      final doc = parsePixelDoc(
        '<path fill="#000" d="$_short"><animate attributeName="d" '
        'values="$_short;$_tall" dur="1s" calcMode="discrete" fill="freeze"/>'
        '</path>',
      );
      final early = await renderAt(doc, kMs * 400);
      expect(alphaAt(early, 50, 45), 255);
      expect(alphaAt(early, 50, 55), 0, reason: '仍是第一帧，高度 50');
      final late = await renderAt(doc, kMs * 600);
      expect(alphaAt(late, 50, 95), 255, reason: '已切到第二帧，高度 100');
    });
  });
}
