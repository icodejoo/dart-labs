import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../game/frame.dart';
import '../game/layout.dart';

/// 条目几何接口，供自定义 Widget 内容使用。
abstract interface class LuckyItemGeometry<L extends LuckyLayout,
    F extends LuckyFrame> {
  /// 返回布局中的条目数。
  int itemCount(L layout);

  /// 返回第 [index] 个条目的逻辑尺寸。
  Size itemSize(L layout, int index);

  /// 写入第 [index] 个条目的变换；不可见时返回 false。
  bool transformFor(L layout, F frame, int index, Matrix4 out);
}

/// 可选裁剪 SPI；几何同时实现此接口时，条目裁剪到指定的宿主坐标区域。
abstract interface class LuckyItemClipGeometry<L extends LuckyLayout> {
  /// 返回第 [index] 个条目的可见区域，例如老虎机所属轮的窗口。
  Rect clipRectFor(L layout, int index);
}

/// 把 [children] 一一放到 [geometry] 的条目盒子内，并随帧更新变换。
///
/// 只在需要 Widget 内容的奖品（如 GIF）时使用，有额外布局和绘制成本。
/// 例如 children 可传入 Image Widget；普通图片优先使用 Canvas 奖品内容。
class LuckyItemOverlay<L extends LuckyLayout, F extends LuckyFrame>
    extends StatelessWidget {
  /// 创建叠加层；[children] 数量必须等于 geometry.itemCount(layout)。
  const LuckyItemOverlay(
      {super.key,
      required this.geometry,
      required this.layout,
      required this.frame,
      required this.frameListenable,
      required this.children});

  /// 条目几何策略。
  final LuckyItemGeometry<L, F> geometry;

  /// 当前布局。
  final L layout;

  /// 由控制器原地更新的帧缓冲；每次变化后须通知 [frameListenable]。
  final F frame;

  /// 帧通知器。
  final Listenable frameListenable;

  /// 每个条目的 Widget。
  final List<Widget> children;

  /// 按裁剪区域分组布局；帧通知只更新绘制变换，不重建子树。
  @override
  Widget build(BuildContext context) {
    assert(children.length == geometry.itemCount(layout));
    final clipGeometry = geometry;
    final groups = <Rect?, List<int>>{};
    for (var i = 0; i < children.length; i++) {
      final clip = clipGeometry is LuckyItemClipGeometry<L>
          ? (clipGeometry as LuckyItemClipGeometry<L>).clipRectFor(layout, i)
          : null;
      (groups[clip] ??= []).add(i);
    }
    return SizedBox.fromSize(
      size: layout.size,
      child: Stack(fit: StackFit.expand, children: [
        for (final group in groups.entries)
          ClipRect(
            clipper: _ItemClipper(group.key),
            child: Flow(
              delegate: _ItemFlowDelegate<L, F>(
                  geometry, layout, frame, frameListenable, group.value),
              children: [for (final i in group.value) children[i]],
            ),
          ),
      ]),
    );
  }
}

/// 固定宿主坐标的裁剪，避免滚动内容覆盖装饰块与其它列。
final class _ItemClipper extends CustomClipper<Rect> {
  /// 保存可选区域；null 时使用整个盒子。
  const _ItemClipper(this.rect);

  /// 固定区域。
  final Rect? rect;

  /// 返回宿主坐标内的可见范围。
  @override
  Rect getClip(Size size) => rect ?? Offset.zero & size;

  /// 区域变化时更新裁剪。
  @override
  bool shouldReclip(_ItemClipper oldClipper) => rect != oldClipper.rect;
}

/// 帧驱动的条目变换；每个子节点拥有独立的矩阵实例。
final class _ItemFlowDelegate<L extends LuckyLayout, F extends LuckyFrame>
    extends FlowDelegate {
  /// 保存布局与帧缓冲，并把帧通知交给 Flow 的重绘路径。
  _ItemFlowDelegate(this.geometry, this.layout, this.frame,
      this.frameListenable, this.indices)
      : super(repaint: frameListenable);

  /// 条目几何。
  final LuckyItemGeometry<L, F> geometry;

  /// 当前布局。
  final L layout;

  /// 当前可变帧缓冲。
  final F frame;

  /// 帧通知源。
  final Listenable frameListenable;

  /// 本裁剪分组对应的全局条目下标。
  final List<int> indices;

  /// 返回布局的逻辑尺寸。
  @override
  Size getSize(BoxConstraints constraints) =>
      constraints.constrain(layout.size);

  /// 子节点严格使用对应条目的逻辑盒子。
  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tight(geometry.itemSize(layout, indices[i]));

  /// 写入独立的新矩阵，避免 TransformLayer 保留并共享同一矩阵。
  @override
  void paintChildren(FlowPaintingContext context) {
    for (var i = 0; i < context.childCount; i++) {
      final transform = Matrix4.identity();
      if (geometry.transformFor(layout, frame, indices[i], transform)) {
        context.paintChild(i, transform: transform);
      }
    }
  }

  /// 布局或策略变化时重新测量子节点。
  @override
  bool shouldRelayout(covariant _ItemFlowDelegate<L, F> oldDelegate) =>
      geometry != oldDelegate.geometry || layout != oldDelegate.layout;

  /// 帧缓冲、监听器、几何或分组发生变化时重新绘制。
  @override
  bool shouldRepaint(covariant _ItemFlowDelegate<L, F> oldDelegate) =>
      shouldRelayout(oldDelegate) ||
      frame != oldDelegate.frame ||
      frameListenable != oldDelegate.frameListenable ||
      !listEquals(indices, oldDelegate.indices);
}
