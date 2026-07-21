/// Command Pipeline.
///
/// Opens up cross-cutting hook points between compute output and the render
/// layer. The pipeline runs registered transforms in registration order,
/// each transform consuming the previous one's output (a pure function
/// chain). Use cases: watermarking, grayscale filters, and other global
/// effects, without modifying any plugin. Ported from `src/core/pipeline.ts`.
library;

import 'types.dart';

/// Command transform function type.
typedef CommandTransform = List<DrawCommand> Function(
  List<DrawCommand> commands,
  CommandTransformContext ctx,
);

/// Transform context (read-only, must not be mutated in place).
class CommandTransformContext {
  /// Road id.
  final String roadId;

  /// Current layout.
  final RoadLayout layout;

  /// Current theme.
  final Theme theme;

  const CommandTransformContext({required this.roadId, required this.layout, required this.theme});
}

/// Command pipeline.
///
/// ```dart
/// final pipeline = createPipeline();
/// final unuse = pipeline.use('watermark', watermarkTransform('TEST'));
/// final finalCmds = pipeline.run(commands, ctx);
/// unuse(); // unregister
/// ```
class Pipeline {
  // Ordered map preserving insertion order.
  final _transforms = <String, CommandTransform>{};

  /// Registers a transform function (overwrites same name), returning an unregister function.
  void Function() use(String name, CommandTransform fn) {
    _transforms[name] = fn;
    return () => _transforms.remove(name);
  }

  /// Runs the pipeline in registration order, returning the final command list (a new list, input left unmodified).
  List<DrawCommand> run(List<DrawCommand> commands, CommandTransformContext ctx) {
    var current = commands;
    for (final fn in _transforms.values) {
      current = fn(current, ctx);
    }
    return current;
  }
}

/// Creates an empty pipeline instance.
Pipeline createPipeline() => Pipeline();

/// Global default pipeline (shared by all panels; register global transforms at app entry).
final Pipeline globalPipeline = createPipeline();

/// Watermark options.
class WatermarkOptions {
  /// Watermark opacity (0-1), default 0.15.
  final double alpha;

  /// Font size (logical pixels), default 14.
  final double fontSize;

  /// Text color, default white.
  final int fill;

  const WatermarkOptions({this.alpha = 0.15, this.fontSize = 14, this.fill = 0xFFFFFFFF});
}

/// Bottom-right watermark transform (appends a low-alpha badge command).
///
/// ```dart
/// pipeline.use('watermark', watermarkTransform('DEMO', const WatermarkOptions(alpha: 0.2)));
/// ```
CommandTransform watermarkTransform(String text, [WatermarkOptions opts = const WatermarkOptions()]) {
  return (commands, ctx) {
    final w = ctx.layout.contentWidth;
    final h = ctx.layout.contentHeight;
    if (w <= 0 || h <= 0) return commands;

    final badge = BadgeCommand(
      x: w - opts.fontSize,
      y: h - opts.fontSize * 0.8,
      text: text,
      fill: opts.fill,
      fontSize: opts.fontSize,
      alpha: opts.alpha,
    );
    return [...commands, badge];
  };
}

/// Grayscale transform: converts all colors (fill/stroke) to grayscale
/// luminance values. Colors are uniformly ARGB 32-bit integers, so there's
/// no need to parse hex/rgba strings like the TS version does.
///
/// ```dart
/// pipeline.use('gray', grayscaleTransform());
/// ```
CommandTransform grayscaleTransform() => (commands, ctx) => commands.map(_toGray).toList();

DrawCommand _toGray(DrawCommand cmd) => switch (cmd) {
  CircleCommand c => CircleCommand(
    x: c.x,
    y: c.y,
    r: c.r,
    fill: c.fill != null ? _grayColor(c.fill!) : null,
    stroke: c.stroke != null ? _grayColor(c.stroke!) : null,
    lineWidth: c.lineWidth,
    alpha: c.alpha,
  ),
  LineCommand c => LineCommand(points: c.points, stroke: _grayColor(c.stroke), lineWidth: c.lineWidth, alpha: c.alpha),
  SlashCommand c =>
    SlashCommand(x: c.x, y: c.y, r: c.r, stroke: _grayColor(c.stroke), lineWidth: c.lineWidth, alpha: c.alpha),
  DotCommand c => DotCommand(x: c.x, y: c.y, r: c.r, fill: _grayColor(c.fill), alpha: c.alpha),
  BadgeCommand c => BadgeCommand(
    x: c.x,
    y: c.y,
    text: c.text,
    fill: c.fill != null ? _grayColor(c.fill!) : null,
    fontSize: c.fontSize,
    alpha: c.alpha,
  ),
  RectCommand c => RectCommand(
    x: c.x,
    y: c.y,
    w: c.w,
    h: c.h,
    fill: c.fill != null ? _grayColor(c.fill!) : null,
    stroke: c.stroke != null ? _grayColor(c.stroke!) : null,
    radius: c.radius,
    alpha: c.alpha,
  ),
};

/// Converts an ARGB color to a grayscale color of equal luminance, preserving the original alpha channel.
int _grayColor(int argb) {
  final a = (argb >> 24) & 0xFF;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final luma = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
  return (a << 24) | (luma << 16) | (luma << 8) | luma;
}
