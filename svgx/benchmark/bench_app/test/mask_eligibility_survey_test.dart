// Deterministic survey of how much of the real 399-icon SMIL corpus the
// mask-as-clip fast path actually covers, and therefore how many
// `canvas.saveLayer` offscreen render passes it removes per frame. Host-side
// and exact, so it does not depend on getting a clean window on a shared
// physical device.
//
// 对真实 399 图标 SMIL 语料中 mask-转-clip 快路径实际覆盖比例的确定性统计，据此
// 推算每帧能去掉多少个 `canvas.saveLayer` 离屏渲染通道。纯主机侧、精确，因此不依赖
// 在共用真机上抢到一个干净的测量窗口。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_dom.dart';
import 'package:svgx/src/animation/svg_theme.dart';

import 'package:bench_app/anim_icons_real.dart';

void main() {
  test('mask-as-clip coverage over the real animated-icon corpus', () {
    var iconsWithMaskedNodes = 0;
    var maskedNodeRefs = 0;
    var maskedNodeRefsEligible = 0;
    var maskDefs = 0;
    var maskDefsEligible = 0;

    for (final source in animIconsReal) {
      final document = parseAnimatedSvgDocument(source);
      if (document.masks.isEmpty) continue;

      // One paint with the approximation enabled forces the eligibility
      // judgement to be computed and cached on each referenced mask root.
      //
      // 打开近似绘制一次，迫使每个被引用的 mask 根节点计算并缓存合格性判定。
      final recorder = ui.PictureRecorder();
      AnimatedSvgPainter(
        root: document.root,
        intrinsicSize: Size(document.width, document.height),
        clock: ValueNotifier(const Duration(milliseconds: 400)),
        theme: const SvgTheme(),
        fit: BoxFit.contain,
        alignment: Alignment.center,
        gradients: document.gradients,
        clipPaths: document.clipPaths,
        masks: document.masks,
        approximateMasks: () => true,
      ).paint(Canvas(recorder), const Size(32, 32));
      recorder.endRecording();

      for (final def in document.masks.values) {
        maskDefs++;
        if (def.maskClipEligible ?? false) maskDefsEligible++;
      }

      var refs = 0;
      var eligibleRefs = 0;
      void walk(SvgNode node) {
        final id = node.maskId;
        if (id != null) {
          final def = document.masks[id];
          if (def != null) {
            refs++;
            if (def.maskClipEligible ?? false) eligibleRefs++;
          }
        }
        for (final child in node.children) {
          walk(child);
        }
      }

      walk(document.root);
      if (refs > 0) iconsWithMaskedNodes++;
      maskedNodeRefs += refs;
      maskedNodeRefsEligible += eligibleRefs;
    }

    // Printed rather than asserted against magic numbers: this is a survey of
    // third-party icon data, and a corpus refresh changing the ratio is not a
    // test failure. The assertions below only pin the facts the optimization's
    // rationale depends on.
    //
    // 用打印而非对魔法数字做断言：这是对第三方图标数据的统计，语料更新导致比例变化
    // 不是测试失败。下面的断言只钉住优化立论所依赖的事实。
    // ignore: avoid_print
    print(
      'corpus=${animIconsReal.length} '
      'iconsWithMaskedNodes=$iconsWithMaskedNodes '
      'maskDefs=$maskDefs eligibleDefs=$maskDefsEligible '
      'maskedNodeRefs=$maskedNodeRefs eligibleRefs=$maskedNodeRefsEligible '
      'saveLayersPerMaskedRef=2 '
      'saveLayersRemovedShare='
      '${(maskedNodeRefsEligible / maskedNodeRefs * 100).toStringAsFixed(1)}%',
    );

    expect(
      maskedNodeRefs,
      greaterThan(0),
      reason: 'sanity: the corpus must actually contain masked nodes',
    );
    expect(
      maskedNodeRefsEligible,
      greaterThan(0),
      reason: 'the fast path must cover at least part of real icon data',
    );
    expect(
      maskedNodeRefsEligible,
      lessThan(maskedNodeRefs),
      reason:
          'and it must NOT claim to cover all of it — stroke-painted masks '
          'are expected to keep the exact pipeline',
    );
  });

  test('how many masked nodes are FULLY STATIC (parse-time bake feasibility)', () {
    // Settles a specific architectural proposal: "since we are intersecting
    // geometry anyway, do it once at parse time in Rust (usvg/tiny-skia)
    // instead of per frame in Dart". That is only possible for a mask whose
    // definition AND whose masked content are both untouched by the whole
    // timeline — if either side moves, there is no single 'final path' to bake.
    // So the question is purely empirical: how many such pairs exist in real
    // icon data?
    //
    // 用来给一个具体的架构提案下结论："既然反正要做几何求交，那就在解析期用 Rust
    // （usvg/tiny-skia）算一次，而不是在 Dart 里逐帧算"。这只对"mask 定义与被遮罩内容
    // 两侧都完全不受整条时间线影响"的 mask 成立——任一侧在动，就不存在唯一的"最终
    // 路径"可烘焙。所以这是一个纯经验问题：真实图标数据里有多少这样的组合？
    var refs = 0;
    var maskDefStatic = 0;
    var contentStatic = 0;
    var bothFullyStatic = 0;

    /// Whether anything anywhere in [node]'s subtree is animated.
    ///
    /// [node] 子树内是否有任何东西带动画。
    ///
    /// [node] — subtree root. / 子树根。
    ///
    /// Returns true when the subtree contains any timeline.
    ///
    ///   子树内含任何时间线时返回 true。
    bool subtreeAnimated(SvgNode node) {
      if (node.animations.isNotEmpty ||
          node.transformAnimations.isNotEmpty ||
          node.motionAnimations.isNotEmpty ||
          node.colorAnimations.isNotEmpty) {
        return true;
      }
      for (final child in node.children) {
        if (subtreeAnimated(child)) return true;
      }
      return false;
    }

    for (final source in animIconsReal) {
      final document = parseAnimatedSvgDocument(source);
      if (document.masks.isEmpty) continue;

      // `ancestorAnimated` is threaded down because an `<animateTransform>` on
      // a wrapping `<g>` moves the masked content just as surely as one on the
      // content itself — content is only static if nothing above it moves
      // either.
      //
      // `ancestorAnimated` 要向下传递：包装用 `<g>` 上的 `<animateTransform>` 让被
      // 遮罩内容移动的效果，与挂在内容自身上的完全一样——只有上方也没有东西在动，
      // 内容才算静态。
      void walk(SvgNode node, bool ancestorAnimated) {
        final selfAnimated =
            node.animations.isNotEmpty ||
            node.transformAnimations.isNotEmpty ||
            node.motionAnimations.isNotEmpty ||
            node.colorAnimations.isNotEmpty;
        final animatedHere = ancestorAnimated || selfAnimated;
        final id = node.maskId;
        if (id != null) {
          final def = document.masks[id];
          if (def != null) {
            refs++;
            final defStatic = !subtreeAnimated(def);
            final ownContentStatic = !animatedHere && !subtreeAnimated(node);
            if (defStatic) maskDefStatic++;
            if (ownContentStatic) contentStatic++;
            if (defStatic && ownContentStatic) bothFullyStatic++;
          }
        }
        for (final child in node.children) {
          walk(child, animatedHere);
        }
      }

      walk(document.root, false);
    }

    // ignore: avoid_print
    print(
      'maskRefs=$refs maskDefStatic=$maskDefStatic '
      'contentStatic=$contentStatic bothFullyStatic=$bothFullyStatic',
    );

    expect(
      refs,
      greaterThan(0),
      reason: 'sanity: the corpus must contain masked nodes',
    );
    // Pinned as an assertion, not just printed, because a whole design
    // direction rests on it: if a corpus refresh ever makes this non-zero,
    // parse-time baking becomes worth building and this test should fail loudly
    // to say so.
    //
    // 这一条钉成断言而不只是打印，因为有一整个设计方向以它为前提：如果哪天语料更新
    // 让它不再为 0，解析期烘焙就值得做了，而这个测试应该大声失败来通知这件事。
    expect(
      bothFullyStatic,
      0,
      reason:
          'no mask in this corpus has BOTH a static definition and static '
          'content, so there is nothing a parse-time (Rust/usvg) bake could '
          'pre-compute — a mask in an icon set exists because it animates',
    );
  });
}
