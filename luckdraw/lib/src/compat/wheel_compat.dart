import '../wheel/model/wheel_config.dart';
import '../wheel/model/wheel_parts.dart';
import 'compat_options.dart';
import 'css_length.dart';
import 'json_reader.dart';

/// 将上游转盘 JSON [data] 转成类型化配置、可选尺寸与字段警告。
///
/// [options] 控制单位、资源与兼容策略；例如
/// `wheelFromLuckyCanvasConfig({'prizes': []}).config` 返回空奖品配置。
/// 未知键与回调仅产生警告，返回列表均不可修改。
LuckyCanvasCompatResult<WheelConfig> wheelFromLuckyCanvasConfig(
    Map<String, Object?> data,
    {LuckyCanvasCompatOptions options = const LuckyCanvasCompatOptions()}) {
  final warnings = <LuckyCanvasCompatWarning>[];
  final root = CompatJsonReader(data, warnings, options: options);
  final defaults = root.object(CompatKeys.defaultConfig);
  final style = root.object(CompatKeys.defaultStyle);
  final blocks = root.objects(CompatKeys.blocks).map((item) {
    final padding = item.read(CompatKeys.padding);
    final token = padding is String ? padding.split(' ').first : padding;
    final length = token == null
        ? null
        : parseCssLength(
            token, options, (m) => item.warn(CompatKeys.padding, m));
    final images = <WheelBlockImage>[];
    for (final image in item.objects(CompatKeys.imgs)) {
      final value = image.image();
      final rotate = image.boolean('rotate') ?? false;
      image.finish();
      if (value != null) {
        images.add(WheelBlockImage(value.image,
            top: value.top,
            left: value.left,
            width: value.width,
            height: value.height,
            rotate: rotate));
      }
    }
    final result = WheelBlock(
        padding: length == null ? 0 : resolveBaseless(length),
        background: item.fill(CompatKeys.background),
        images: List.unmodifiable(images));
    item.finish();
    return result;
  }).toList(growable: false);
  final prizes = root.objects(CompatKeys.prizes).map((item) {
    final result = WheelPrize(
        background: item.fill(CompatKeys.background),
        texts: item.texts(),
        images: item.images(),
        weight: item.number(CompatKeys.range));
    item.finish();
    return result;
  }).toList(growable: false);
  final buttons = root.objects(CompatKeys.buttons).map((item) {
    final result = WheelButton(
        radius: item.length('radius') ?? const WheelButton().radius,
        pointer: item.boolean('pointer') ?? false,
        background: item.fill(CompatKeys.background),
        texts: item.texts(button: true),
        images: item.images());
    item.finish();
    return result;
  }).toList(growable: false);
  final config = WheelConfig(
      blocks: List.unmodifiable(blocks),
      prizes: List.unmodifiable(prizes),
      buttons: List.unmodifiable(buttons),
      options: WheelOptions(
          gutter: defaults.pixels(CompatKeys.gutter) ?? 0,
          offsetDegree: defaults.number('offsetDegree') ?? 0,
          stopRange: defaults.pixels('stopRange') ?? 0,
          motion: defaults.motion(speedFunction: true)),
      style: WheelStyle(
          background: style.has(CompatKeys.background)
              ? style.fill(CompatKeys.background)
              : const WheelStyle().background,
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
