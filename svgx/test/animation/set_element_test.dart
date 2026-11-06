// `<set>`：单值离散动画。数值属性走数值通道、`d` 走路径通道；begin 之前显示静态
// 值，无 dur 则永久保持，有 dur 无 freeze 则结束后撤销；并验证 Ticker 的停止依据
// （无 dur 的 `<set>` 不能让时钟一直跑）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/smil_animation.dart';
import 'package:svgx/svgx.dart';

import 'node_test_utils.dart';
import 'pixel_test_utils.dart';

/// 整张 100x100 的黑色矩形，附带 [children]。
String _rect(String attrs, String children) =>
    '<rect width="100" height="100" fill="#000" $attrs>$children</rect>';

void main() {
  setUp(SvgxDocumentCache.instance.clear);
  tearDown(SvgxDocumentCache.instance.clear);

  group('数值属性', () {
    test('opacity：begin 之前显示静态值，之后永久保持', () async {
      final doc = parsePixelDoc(
        _rect('', '<set attributeName="opacity" to="0" begin="0.5s"/>'),
      );
      expect(alphaAt(await renderAt(doc, kMs * 400), 50, 50), 255);
      expect(alphaAt(await renderAt(doc, kMs * 500), 50, 50), 0);
      expect(
        alphaAt(await renderAt(doc, const Duration(minutes: 5)), 50, 50),
        0,
      );
    });

    test('fill-opacity：与数值通道一致', () async {
      final doc = parsePixelDoc(
        _rect(
          'fill-opacity="0"',
          '<set attributeName="fill-opacity" to="1" begin="1s"/>',
        ),
      );
      expect(alphaAt(await renderAt(doc, kMs * 900), 50, 50), 0);
      expect(alphaAt(await renderAt(doc, kMs * 1100), 50, 50), 255);
    });

    test('有 dur 无 freeze：结束后撤销覆盖', () async {
      final doc = parsePixelDoc(
        _rect('', '<set attributeName="opacity" to="0" begin="1s" dur="1s"/>'),
      );
      expect(alphaAt(await renderAt(doc, kMs * 500), 50, 50), 255);
      expect(alphaAt(await renderAt(doc, kMs * 1500), 50, 50), 0);
      expect(
        alphaAt(await renderAt(doc, kMs * 2500), 50, 50),
        255,
        reason: '活动期结束，恢复静态属性',
      );
    });

    test('有 dur 且 fill=freeze：结束后继续保持', () async {
      final doc = parsePixelDoc(
        _rect(
          '',
          '<set attributeName="opacity" to="0" begin="1s" dur="1s" '
              'fill="freeze"/>',
        ),
      );
      expect(alphaAt(await renderAt(doc, kMs * 5000), 50, 50), 0);
    });

    test('syncbase begin 与其它动画协同', () async {
      final doc = parsePixelDoc(
        _rect(
          '',
          '<animate id="a" attributeName="fill-opacity" values="1;1" dur="1s"/>'
              '<set attributeName="opacity" to="0" begin="a.end+0.5s"/>',
        ),
      );
      final set = numericAnimationsOf(doc.root).last;
      expect(set.begin, kMs * 1500);
      expect(alphaAt(await renderAt(doc, kMs * 1400), 50, 50), 255);
      expect(alphaAt(await renderAt(doc, kMs * 1600), 50, 50), 0);
    });

    test('to 不是数字（如 visibility）被丢弃', () {
      final doc = parsePixelDoc(
        _rect('', '<set attributeName="visibility" to="hidden"/>'),
      );
      expect(numericAnimationsOf(doc.root), isEmpty);
    });

    test('缺 to 被丢弃', () {
      final doc = parsePixelDoc(_rect('', '<set attributeName="opacity"/>'));
      expect(numericAnimationsOf(doc.root), isEmpty);
    });
  });

  group('d 路径', () {
    // 静态形状是左半（高 50），set 之后变成整块。
    const left = 'M0 0h50v100h-50z';
    const full = 'M0 0h100v100h-100z';
    String path(String child) => '<path fill="#000" d="$left">$child</path>';

    test('begin 之前显示静态 d，之后永久换成 to', () async {
      final doc = parsePixelDoc(
        path('<set attributeName="d" to="$full" begin="0.5s"/>'),
      );
      expect(alphaAt(await renderAt(doc, kMs * 400), 75, 50), 0);
      expect(alphaAt(await renderAt(doc, kMs * 500), 75, 50), 255);
      expect(
        alphaAt(await renderAt(doc, const Duration(hours: 1)), 75, 50),
        255,
      );
    });

    test('有 dur 无 freeze：结束后回到静态 d', () async {
      final doc = parsePixelDoc(
        path('<set attributeName="d" to="$full" begin="1s" dur="1s"/>'),
      );
      expect(alphaAt(await renderAt(doc, kMs * 1500), 75, 50), 255);
      expect(alphaAt(await renderAt(doc, kMs * 2500), 75, 50), 0);
    });

    test('解析为单帧、离散、不带数值变形数据的 SmilPathAnimation', () {
      final doc = parsePixelDoc(
        path('<set attributeName="d" to="$full" begin="0.5s"/>'),
      );
      final anim = doc.root.children.single.pathAnimations.single;
      expect(anim.frames, [full]);
      expect(anim.morph, isNull);
      expect(anim.calcMode, SmilCalcMode.discrete);
      expect(anim.sample(kMs * 100), isNull);
      expect(anim.sample(kMs * 500), 0);
    });

    test('与 animate d 叠用：set 在其开始后覆盖', () async {
      final doc = parsePixelDoc(
        path(
          '<animate attributeName="d" values="$left;$full" dur="2s" fill="freeze"/>'
          '<set attributeName="d" to="$left" begin="1s"/>',
        ),
      );
      // t=0.5s：animate 插值到 x 约 62；t=1.5s：set 生效，回到 left。
      expect(alphaAt(await renderAt(doc, kMs * 500), 60, 50), 255);
      expect(alphaAt(await renderAt(doc, kMs * 1500), 75, 50), 0);
    });
  });

  group('Ticker 停止依据', () {
    test('无 dur 的 set：totalDuration 等于 begin，且不算无限循环', () {
      final doc = parsePixelDoc(
        _rect('', '<set attributeName="opacity" to="0" begin="0.5s"/>'),
      );
      expect(doc.totalDuration, kMs * 500);
      expect(doc.hasIndefiniteLoop, isFalse);
    });

    test('无 dur 的 set 即使写了 repeatCount=indefinite 也不算无限循环', () {
      final doc = parsePixelDoc(
        _rect(
          '',
          '<set attributeName="opacity" to="0" begin="0.5s" '
              'repeatCount="indefinite"/>',
        ),
      );
      expect(doc.hasIndefiniteLoop, isFalse);
      expect(doc.totalDuration, kMs * 500);
    });

    test('有 dur 的 set：totalDuration = begin + dur', () {
      final doc = parsePixelDoc(
        _rect('', '<set attributeName="opacity" to="0" begin="1s" dur="2s"/>'),
      );
      expect(doc.totalDuration, kMs * 3000);
    });

    test('作用于 d 的无 dur set 同样如此', () {
      final doc = parsePixelDoc(
        '<path d="M0 0h10v10z"><set attributeName="d" to="M0 0h20v20z" '
        'begin="2s"/></path>',
      );
      expect(doc.totalDuration, kMs * 2000);
      expect(doc.hasIndefiniteLoop, isFalse);
    });

    testWidgets('控件在 begin 之后停表并只回调一次完成', (tester) async {
      var completeCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SvgxAnimated.string(
            '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
            '<rect width="24" height="24" fill="#000">'
            '<set attributeName="opacity" to="0" begin="0.2s" '
            'repeatCount="indefinite"/></rect></svg>',
            width: 24,
            height: 24,
            onAnimationComplete: () => completeCount++,
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(completeCount, 1);
      // 停表之后不应再有待处理的帧。
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
