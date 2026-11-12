// 动画路径测试共用的节点树工具：遍历 SvgNode 子树、收集各类动画，以及时间常量。

import 'package:xvg/src/animation/smil_animation.dart';
import 'package:xvg/src/animation/svg_dom.dart';

/// 1 毫秒；测试里用 `kMs * n` 表示时间点。
const Duration kMs = Duration(milliseconds: 1);

/// 深度优先（先自身后子节点）遍历 [root] 子树。
Iterable<SvgNode> walkNodes(SvgNode root) sync* {
  yield root;
  for (final child in root.children) {
    yield* walkNodes(child);
  }
}

/// [root] 子树上的所有数值动画，按遍历顺序。
List<SmilAnimation> numericAnimationsOf(SvgNode root) => [
  for (final node in walkNodes(root)) ...node.animations,
];

/// [root] 子树上的所有路径动画，按遍历顺序。
List<SmilPathAnimation> pathAnimationsOf(SvgNode root) => [
  for (final node in walkNodes(root)) ...node.pathAnimations,
];
