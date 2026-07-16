/// 加载骨架屏：整体数据刷新期间盖住面板，避免空白闪烁。
///
/// 移植自 `src/panel/ux/skeleton.ts`。TS 版本是可插拔的适配器接口（默认实现
/// 用纯 DOM/CSS 画点阵 + 斜向高光扫描）；Flutter 版本同样保留可插拔接口，默认
/// 实现改用 `ShaderMask` + `LinearGradient` 做等价的扫光效果。
library;

import 'package:flutter/material.dart';

/// 骨架屏渲染的上下文信息。
class SkeletonContext {
  /// 面板宽度。
  final double panelWidth;

  /// 面板高度。
  final double panelHeight;

  /// 背景色。
  final Color background;

  /// 前景（点阵/高光）色。
  final Color foreground;

  const SkeletonContext({
    required this.panelWidth,
    required this.panelHeight,
    required this.background,
    required this.foreground,
  });
}

/// 可插拔的骨架屏渲染策略：实现 [build] 返回要叠加显示的 widget。
abstract class SkeletonAdapter {
  Widget build(SkeletonContext ctx);
}

/// 默认骨架屏实现：背景色块 + 一条循环扫过的高光带。
class DefaultSkeletonAdapter extends SkeletonAdapter {
  @override
  Widget build(SkeletonContext ctx) => _ShimmerBlock(ctx: ctx);
}

/// 内置默认骨架屏适配器实例。
final SkeletonAdapter defaultSkeletonAdapter = DefaultSkeletonAdapter();

class _ShimmerBlock extends StatefulWidget {
  final SkeletonContext ctx;
  const _ShimmerBlock({required this.ctx});

  @override
  State<_ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<_ShimmerBlock> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    return SizedBox(
      width: ctx.panelWidth,
      height: ctx.panelHeight,
      child: Container(
        color: ctx.background,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => ShaderMask(
            shaderCallback: (bounds) {
              final t = _controller.value;
              return LinearGradient(
                colors: [ctx.background, ctx.foreground, ctx.background],
                stops: const [0.35, 0.5, 0.65],
                begin: Alignment(-1 + 2 * t, 0),
                end: Alignment(1 + 2 * t, 0),
              ).createShader(bounds);
            },
            child: Container(color: ctx.foreground.withValues(alpha: 0.08)),
          ),
        ),
      ),
    );
  }
}

/// 骨架屏渲染器：包装一个 [SkeletonAdapter]，暴露 `build` 给消费方叠加显示。
class SkeletonRenderer {
  final SkeletonAdapter adapter;
  const SkeletonRenderer(this.adapter);

  Widget build(SkeletonContext ctx) => adapter.build(ctx);
}

/// 创建骨架屏渲染器，缺省用内置的扫光实现。
SkeletonRenderer createSkeletonRenderer([SkeletonAdapter? adapter]) =>
    SkeletonRenderer(adapter ?? defaultSkeletonAdapter);
