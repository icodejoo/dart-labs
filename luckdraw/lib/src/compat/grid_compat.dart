import '../core/foundation/cell_style.dart';
import '../grid/model/grid_config.dart';
import '../grid/model/grid_parts.dart';
import 'compat_options.dart';
import 'css_misc.dart';
import 'json_reader.dart';

/// 将上游九宫格 JSON [data] 转成配置、可选尺寸与字段警告。
///
/// [options] 控制单位及兼容策略；旧 `button` 追加在 `buttons` 后面。
/// 例如 `gridFromLuckyCanvasConfig({'rows': 4}).config.rows` 返回 4。
LuckyCanvasCompatResult<GridConfig> gridFromLuckyCanvasConfig(
    Map<String, Object?> data,
    {LuckyCanvasCompatOptions options = const LuckyCanvasCompatOptions()}) {
  final warnings = <LuckyCanvasCompatWarning>[];
  final root = CompatJsonReader(data, warnings, options: options);
  final defaults = root.object(CompatKeys.defaultConfig);
  final style = root.object(CompatKeys.defaultStyle);
  final active = root.object('activeStyle');
  final prizes = root.objects(CompatKeys.prizes).map((item) {
    final result = GridPrize(
        x: item.integer(CompatKeys.x),
        y: item.integer(CompatKeys.y),
        col: item.integer(CompatKeys.col, fallback: 1, falsyFallback: true),
        row: item.integer(CompatKeys.row, fallback: 1, falsyFallback: true),
        style: item.cellStyle(falsyRadius: true),
        texts: item.texts(),
        images: _images(item),
        weight: item.number(CompatKeys.range),
        disabled: (item.boolean('disabled') ?? false) && options.honorDisabled);
    item.finish();
    return result;
  }).toList(growable: false);
  final buttonItems = root.objects(CompatKeys.buttons);
  if (root.truthy(CompatKeys.button) != null) {
    buttonItems.add(root.object(CompatKeys.button));
  }
  final buttons = buttonItems.map((item) {
    final result = GridButton(
        x: item.integer(CompatKeys.x),
        y: item.integer(CompatKeys.y),
        col: item.integer(CompatKeys.col, fallback: 1, falsyFallback: true),
        row: item.integer(CompatKeys.row, fallback: 1, falsyFallback: true),
        style: item.cellStyle(falsyRadius: true),
        texts: item.texts(),
        images: _images(item));
    item.finish();
    return result;
  }).toList(growable: false);
  final defaultCell = style.cellStyle();
  final activeCell = active.cellStyle(active: true);
  final config = GridConfig(
      rows: root.integer('rows',
          fallback: kLuckyGridDefaultDimension, falsyFallback: true),
      cols: root.integer('cols',
          fallback: kLuckyGridDefaultDimension, falsyFallback: true),
      blocks: root.blocks(),
      prizes: List.unmodifiable(prizes),
      buttons: List.unmodifiable(buttons),
      options: GridOptions(
          gutter:
              defaults.pixels(CompatKeys.gutter) ?? const GridOptions().gutter,
          motion: defaults.motion()),
      style: GridStyle(
          cell: LuckyCellStyle(
              background: style.has(CompatKeys.background)
                  ? defaultCell.background
                  : const GridStyle().cell.background,
              borderRadius: defaultCell.borderRadius ??
                  const GridStyle().cell.borderRadius,
              shadow: defaultCell.shadow),
          text: style.textDefaults()),
      activeStyle: LuckyCellStyle(
          background: active.has(CompatKeys.background)
              ? activeCell.background
              : const GridConfig().activeStyle.background,
          shadow: activeCell.shadow,
          text: activeCell.text));
  final width = root.dimension(CompatKeys.width);
  final height = root.dimension(CompatKeys.height);
  defaults.finish();
  style.finish();
  active.finish();
  root.finish();
  return LuckyCanvasCompatResult(
      config: config,
      width: width,
      height: height,
      warnings: List.unmodifiable(warnings));
}

/// 将普通来源及激活来源合并为九宫格图片，保留每个元素的诊断路径。
List<GridImage> _images(CompatJsonReader parent) {
  final result = <GridImage>[];
  for (final item in parent.objects(CompatKeys.imgs)) {
    final image = item.image();
    final source = item.truthy(CompatKeys.activeSrc);
    final activeImage = source == null
        ? null
        : imageProviderFromSrc(
            source, item.options, (m) => item.warn(CompatKeys.activeSrc, m));
    item.finish();
    if (image != null) {
      result.add(GridImage(image.image,
          top: image.top,
          left: image.left,
          width: image.width,
          height: image.height,
          activeImage: activeImage));
    }
  }
  return List.unmodifiable(result);
}
