import '../core/foundation/cell_style.dart';
import '../slot/model/slot_config.dart';
import '../slot/model/slot_parts.dart';
import 'compat_options.dart';
import 'json_reader.dart';

/// 将上游老虎机 JSON [data] 转成配置、可选尺寸与字段警告。
///
/// [options] 控制单位及兼容策略；`slots` 映射到 `reels`，零速度及方向继承全局值。
/// 例如 `slotFromLuckyCanvasConfig({'slots': [{}]}).config.reels` 返回一列。
LuckyCanvasCompatResult<SlotConfig> slotFromLuckyCanvasConfig(
    Map<String, Object?> data,
    {LuckyCanvasCompatOptions options = const LuckyCanvasCompatOptions()}) {
  final warnings = <LuckyCanvasCompatWarning>[];
  final root = CompatJsonReader(data, warnings, options: options);
  final defaults = root.object(CompatKeys.defaultConfig);
  final style = root.object(CompatKeys.defaultStyle);
  final cell = style.cellStyle();
  final prizes = root.objects(CompatKeys.prizes).map((item) {
    final result = SlotPrize(
        background: item.fill(CompatKeys.background),
        borderRadius: item.pixels(CompatKeys.borderRadius),
        texts: item.texts(),
        images: item.images());
    item.finish();
    return result;
  }).toList(growable: false);
  final reels = root.objects('slots').map((item) {
    final order =
        item.has(CompatKeys.order) && item.read(CompatKeys.order) != null
            ? item.array(CompatKeys.order)
            : null;
    final indices = order == null
        ? null
        : List.generate(
            order.length,
            (index) => CompatJsonReader({'index': order[index]}, warnings,
                    path: '${item.fieldPath(CompatKeys.order)}[$index]',
                    options: options)
                .integer('index'));
    final speed = item.number(CompatKeys.speed);
    final direction = item.number(CompatKeys.direction);
    final result = SlotReel(
        order: indices == null ? null : List.unmodifiable(indices),
        speed: speed == 0 ? null : speed,
        direction: direction == 0 ? null : direction?.toInt());
    item.finish();
    return result;
  }).toList(growable: false);
  final config = SlotConfig(
      blocks: root.blocks(),
      prizes: List.unmodifiable(prizes),
      reels: List.unmodifiable(reels),
      options: SlotOptions(
          mode: defaults.string('mode') == 'horizontal'
              ? SlotMode.horizontal
              : SlotMode.vertical,
          direction: defaults.number(CompatKeys.direction)?.toInt() ?? 1,
          rowSpacing: defaults.pixels('rowSpacing') ?? 0,
          colSpacing:
              defaults.pixels('colSpacing') ?? const SlotOptions().colSpacing,
          motion: defaults.motion()),
      style: SlotStyle(
          cell: LuckyCellStyle(
              background: style.has(CompatKeys.background)
                  ? cell.background
                  : const SlotStyle().cell.background,
              borderRadius:
                  cell.borderRadius ?? const SlotStyle().cell.borderRadius),
          text: style.textDefaults()));
  final width = root.dimension(CompatKeys.width);
  final height = root.dimension(CompatKeys.height);
  defaults.finish();
  style.finish();
  root.finish();
  return LuckyCanvasCompatResult(
      config: config,
      width: width,
      height: height,
      warnings: List.unmodifiable(warnings));
}
