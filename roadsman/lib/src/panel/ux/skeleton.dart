/// Loading skeleton: covers the panel during a full data refresh to avoid a
/// blank flash.
///
/// Ported from `src/panel/ux/skeleton.ts`. The TS version is a pluggable
/// adapter interface (the default implementation draws a dot-matrix + a
/// diagonal shimmer sweep with plain DOM/CSS); the Flutter version likewise
/// keeps a pluggable interface, with the default implementation using
/// `ShaderMask` + `LinearGradient` for an equivalent shimmer effect.
library;

import 'package:flutter/material.dart';

/// Contextual info for rendering the skeleton.
class SkeletonContext {
  /// Panel width.
  final double panelWidth;

  /// Panel height.
  final double panelHeight;

  /// Background color.
  final Color background;

  /// Foreground (dot-matrix/shimmer) color.
  final Color foreground;

  const SkeletonContext({
    required this.panelWidth,
    required this.panelHeight,
    required this.background,
    required this.foreground,
  });
}

/// Pluggable skeleton rendering strategy: implement [build] to return the
/// widget to overlay.
abstract class SkeletonAdapter {
  Widget build(SkeletonContext ctx);
}

/// Default skeleton implementation: a background block plus a shimmer band
/// that sweeps across in a loop.
class DefaultSkeletonAdapter extends SkeletonAdapter {
  @override
  Widget build(SkeletonContext ctx) => _ShimmerBlock(ctx: ctx);
}

/// Built-in default skeleton adapter instance.
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

/// Skeleton renderer: wraps a [SkeletonAdapter] and exposes `build` for the
/// consumer to overlay.
class SkeletonRenderer {
  final SkeletonAdapter adapter;
  const SkeletonRenderer(this.adapter);

  Widget build(SkeletonContext ctx) => adapter.build(ctx);
}

/// Create a skeleton renderer, defaulting to the built-in shimmer
/// implementation.
SkeletonRenderer createSkeletonRenderer([SkeletonAdapter? adapter]) =>
    SkeletonRenderer(adapter ?? defaultSkeletonAdapter);
