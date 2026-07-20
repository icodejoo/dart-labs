/// 指令管道（Command Pipeline）。
///
/// 在 compute 输出与渲染层之间开放横切处理点。管道按注册顺序依次执行，每个
/// transform 收上一个的输出（纯函数链）。用途：水印、灰度滤镜等全局效果，不改
/// 任何插件。移植自 `src/core/pipeline.ts`。
library;

import 'types.dart';

/// 指令变换函数类型。
typedef CommandTransform = List<DrawCommand> Function(
  List<DrawCommand> commands,
  CommandTransformContext ctx,
);

/// 变换上下文（只读，禁止就地修改）。
class CommandTransformContext {
  /// 路 id。
  final String roadId;

  /// 当前布局。
  final RoadLayout layout;

  /// 当前主题。
  final Theme theme;

  const CommandTransformContext({required this.roadId, required this.layout, required this.theme});
}

/// 指令管道。
///
/// ```dart
/// final pipeline = createPipeline();
/// final unuse = pipeline.use('watermark', watermarkTransform('TEST'));
/// final finalCmds = pipeline.run(commands, ctx);
/// unuse(); // 卸载
/// ```
class Pipeline {
  // 保持插入顺序的有序 Map。
  final _transforms = <String, CommandTransform>{};

  /// 注册变换函数（同名覆盖），返回卸载函数。
  void Function() use(String name, CommandTransform fn) {
    _transforms[name] = fn;
    return () => _transforms.remove(name);
  }

  /// 按注册顺序执行管道，返回最终指令列表（新列表，不修改入参）。
  List<DrawCommand> run(List<DrawCommand> commands, CommandTransformContext ctx) {
    var current = commands;
    for (final fn in _transforms.values) {
      current = fn(current, ctx);
    }
    return current;
  }
}

/// 创建一个空的指令管道实例。
Pipeline createPipeline() => Pipeline();

/// 全局默认管道（所有面板共用，可在应用入口注册全局 transform）。
final Pipeline globalPipeline = createPipeline();

/// 水印选项。
class WatermarkOptions {
  /// 水印不透明度（0-1），默认 0.15。
  final double alpha;

  /// 字号（逻辑像素），默认 14。
  final double fontSize;

  /// 文字颜色，默认白色。
  final int fill;

  const WatermarkOptions({this.alpha = 0.15, this.fontSize = 14, this.fill = 0xFFFFFFFF});
}

/// 右下角水印 transform（追加低 alpha badge 指令）。
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

/// 灰度 transform：将所有颜色（fill/stroke）转为灰度亮度值。颜色统一是 ARGB
/// 32 位整数，不需要像 TS 版本那样解析 hex/rgba 字符串。
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

/// 把一个 ARGB 颜色转为等亮度的灰度颜色，保留原有 alpha 通道。
int _grayColor(int argb) {
  final a = (argb >> 24) & 0xFF;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final luma = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
  return (a << 24) | (luma << 16) | (luma << 8) | luma;
}
