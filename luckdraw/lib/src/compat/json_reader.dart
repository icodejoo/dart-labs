import 'package:flutter/painting.dart';

import '../core/easing/easing.dart';
import '../core/foundation/box_block.dart';
import '../core/foundation/cell_style.dart';
import '../core/foundation/constants.dart';
import '../core/foundation/fill.dart';
import '../core/foundation/image.dart';
import '../core/foundation/length.dart';
import '../core/foundation/text.dart';
import '../core/motion/motion_options.dart';
import 'compat_options.dart';
import 'css_color.dart';
import 'css_fill.dart';
import 'css_length.dart';
import 'css_misc.dart';
import 'css_shadow.dart';
import 'easing_names.dart';

/// 三个独立转换入口共用的上游 JSON 键，不从 compat.dart 导出。
abstract final class CompatKeys {
  /// 默认行为配置键。
  static const defaultConfig = 'defaultConfig';

  /// 默认样式键。
  static const defaultStyle = 'defaultStyle';

  /// 背景块列表键。
  static const blocks = 'blocks';

  /// 奖品列表键。
  static const prizes = 'prizes';

  /// 按钮列表键。
  static const buttons = 'buttons';

  /// 旧单按钮键。
  static const button = 'button';

  /// 逻辑宽度键。
  static const width = 'width';

  /// 逻辑高度键。
  static const height = 'height';

  /// 背景键。
  static const background = 'background';

  /// 图片列表键。
  static const imgs = 'imgs';

  /// 图片来源键。
  static const src = 'src';

  /// 激活图片来源键。
  static const activeSrc = 'activeSrc';

  /// 内边距键。
  static const padding = 'padding';

  /// 圆角键。
  static const borderRadius = 'borderRadius';

  /// 阴影键。
  static const shadow = 'shadow';

  /// 选奖权重键。
  static const range = 'range';

  /// 间距键。
  static const gutter = 'gutter';

  /// 文字颜色键。
  static const fontColor = 'fontColor';

  /// 文字字号键。
  static const fontSize = 'fontSize';

  /// 字体族键。
  static const fontStyle = 'fontStyle';

  /// 字重键。
  static const fontWeight = 'fontWeight';

  /// 行高键。
  static const lineHeight = 'lineHeight';

  /// 换行键。
  static const wordWrap = 'wordWrap';

  /// 每行宽度键。
  static const lengthLimit = 'lengthLimit';

  /// 行数限制键。
  static const lineClamp = 'lineClamp';

  /// 顶部偏移键。
  static const top = 'top';

  /// 左侧偏移键。
  static const left = 'left';

  /// 缓动名称键。
  static const speedFunction = 'speedFunction';

  /// 单格横坐标键。
  static const x = 'x';

  /// 单格纵坐标键。
  static const y = 'y';

  /// 合并列数键。
  static const col = 'col';

  /// 合并行数键。
  static const row = 'row';

  /// 滚轮奖品顺序键。
  static const order = 'order';

  /// 速度键。
  static const speed = 'speed';

  /// 方向键。
  static const direction = 'direction';
}

/// 内部 JSON 读取器；子读取器共享警告列表，不从 compat 入口导出。
final class CompatJsonReader {
  /// 创建读取器；[path] 为空表示配置根节点。
  CompatJsonReader(this.data, this.warnings,
      {this.path = '', this.options = const LuckyCanvasCompatOptions()});

  /// 当前迁移选项；子节点沿用同一组选项。
  final LuckyCanvasCompatOptions options;

  /// 已读取的键，用于转换结束后诊断未知字段。
  final Set<String> _readKeys = {};

  /// 当前节点的数据。
  final Map<String, Object?> data;

  /// 共享的警告收集器。
  final List<LuckyCanvasCompatWarning> warnings;

  /// 当前节点路径。
  final String path;

  /// 返回子字段的完整路径。
  String fieldPath(String key) => path.isEmpty ? key : '$path.$key';

  /// 返回原始值，保留显式 false 和零。
  Object? read(String key) {
    _readKeys.add(key);
    return data[key];
  }

  /// 判断字段是否显式出现。
  bool has(String key) => data.containsKey(key);

  /// 给指定字段添加诊断。
  void warn(String key, String message) =>
      warnings.add(LuckyCanvasCompatWarning(fieldPath(key), message));

  /// 读取对象；类型错误时警告并返回空对象。
  CompatJsonReader object(String key) {
    final value = read(key);
    final map = <String, Object?>{};
    if (value is Map<Object?, Object?>) {
      for (final entry in value.entries) {
        if (entry.key is String) {
          map[entry.key! as String] = entry.value;
        } else {
          warn(key, '对象键必须是字符串');
        }
      }
    } else if (value != null) {
      warn(key, '需要 JSON 对象');
    }
    return CompatJsonReader(map, warnings,
        path: fieldPath(key), options: options);
  }

  /// 读取数组；缺失返回空数组，类型错误另外警告。
  List<Object?> array(String key) {
    final value = read(key);
    if (value is List<Object?>) return value;
    if (value != null) warn(key, '需要 JSON 数组');
    return const [];
  }

  /// 对未列入 [known] 的字段逐一警告，包含无法迁移的回调。
  void warnUnknown(Set<String> known) {
    for (final key in data.keys) {
      if (!known.contains(key)) warn(key, '忽略不支持的字段或回调');
    }
  }

  /// 诊断所有尚未读取的数据键，包含不可迁移的回调。
  void finish() => warnUnknown(_readKeys);

  /// 读取字符串，类型不符时返回 null 并警告。
  String? string(String key) {
    final value = read(key);
    if (value == null) return null;
    if (value is String) return value;
    warn(key, '需要字符串');
    return null;
  }

  /// 读取有限数字，不把字符串当作数字。
  double? number(String key) {
    final value = read(key);
    if (value == null) return null;
    if (value is num && value.isFinite) return value.toDouble();
    warn(key, '需要有限数字');
    return null;
  }

  /// 按 Number(value) 读取格子坐标；无效值使用 [fallback]。
  int integer(String key, {int fallback = 0, bool falsyFallback = false}) {
    final value = read(key);
    final number = value is bool
        ? (value ? 1.0 : 0.0)
        : value == null || value == ''
            ? 0.0
            : double.tryParse(value.toString());
    if (number == null || !number.isFinite) {
      warn(key, '需要可转换为数字的整数');
      return fallback;
    }
    return falsyFallback && number == 0 ? fallback : number.toInt();
  }

  /// 读取布尔值，显式 false 保持有效。
  bool? boolean(String key) {
    final value = read(key);
    if (value == null) return null;
    if (value is bool) return value;
    warn(key, '需要布尔值');
    return null;
  }

  /// 读取对象数组，保留元素原始路径；非法元素警告并按空对象转换。
  List<CompatJsonReader> objects(String key) {
    final values = array(key);
    return List.generate(values.length, (index) {
      final itemKey = '$key[$index]';
      return CompatJsonReader({itemKey: values[index]}, warnings,
              path: path, options: options)
          .object(itemKey);
    });
  }

  /// 按 JS 假值回退规则读取可空字段；空列表及空对象仍是真值。
  Object? truthy(String key) {
    final value = read(key);
    return value == null ||
            value == false ||
            value == '' ||
            value == 0 ||
            value is num && value.isNaN
        ? null
        : value;
  }

  /// 读取长度；[falsy] 表示上游使用 || 回退。
  LuckyLength? length(String key, {bool falsy = false}) {
    final value = falsy ? truthy(key) : read(key);
    return value == null
        ? null
        : parseCssLength(value, options, (message) => warn(key, message));
  }

  /// 读取没有百分比基准的逻辑像素长度。
  double? pixels(String key, {bool falsy = false}) {
    final result = length(key, falsy: falsy);
    return result == null ? null : resolveBaseless(result);
  }

  /// 读取宿主尺寸；百分比必须交给父布局，故返回 null 并警告。
  double? dimension(String key) {
    final result = length(key);
    if (result is LuckyPercent) {
      warn(key, '百分比尺寸由父布局决定');
      return null;
    }
    return result == null ? null : (result as LuckyPx).value;
  }

  /// 读取背景，透明关键字仍保留无背景语义。
  LuckyFill? fill(String key) =>
      parseCssFill(truthy(key), (message) => warn(key, message));

  /// 读取文字覆盖值；局部假值回退，wordWrap 使用 has 语义。
  LuckyText text({bool button = false}) {
    final family = parseCssFontFamily(truthy(CompatKeys.fontStyle));
    final color = truthy(CompatKeys.fontColor);
    final weight = truthy(CompatKeys.fontWeight);
    final result = LuckyText(read('text').toString(),
        top: length(CompatKeys.top),
        left: length(CompatKeys.left),
        color: color == null
            ? null
            : parseCssColor(
                color.toString(), (m) => warn(CompatKeys.fontColor, m)),
        fontSize: pixels(CompatKeys.fontSize, falsy: true),
        fontFamily: family.family,
        fontFamilyFallback: family.fallback,
        fontWeight: weight == null ? null : parseCssFontWeight(weight),
        lineHeight: pixels(CompatKeys.lineHeight, falsy: true),
        wordWrap: button ? null : boolean(CompatKeys.wordWrap),
        lengthLimit:
            button ? null : length(CompatKeys.lengthLimit, falsy: true),
        lineClamp: button ? null : number(CompatKeys.lineClamp)?.toInt());
    finish();
    return result;
  }

  /// 读取全部文字，按钮仅接受上游按钮支持的字段。
  List<LuckyText> texts({bool button = false}) => List.unmodifiable(
      objects('fonts').map((item) => item.text(button: button)));

  /// 读取默认文字，不消耗背景等同级样式键。
  LuckyTextDefaults textDefaults() {
    final family = parseCssFontFamily(truthy(CompatKeys.fontStyle));
    final color = read(CompatKeys.fontColor);
    final weight = read(CompatKeys.fontWeight);
    return LuckyTextDefaults(
        color: color == null
            ? kLuckyDefaultFontColor
            : parseCssColor(
                    color.toString(), (m) => warn(CompatKeys.fontColor, m)) ??
                kLuckyDefaultFontColor,
        fontSize: pixels(CompatKeys.fontSize) ?? kLuckyDefaultFontSize,
        fontFamily: family.family,
        fontFamilyFallback: family.fallback,
        fontWeight: weight == null
            ? FontWeight.w400
            : parseCssFontWeight(weight) ?? FontWeight.w400,
        lineHeight: pixels(CompatKeys.lineHeight),
        wordWrap: boolean(CompatKeys.wordWrap) ?? true,
        lengthLimit: length(CompatKeys.lengthLimit) ?? kLuckyDefaultLengthLimit,
        lineClamp: number(CompatKeys.lineClamp)?.toInt());
  }

  /// 读取格子装饰；[falsyRadius] 只用于九宫格的局部圆角回退。
  LuckyCellStyle cellStyle({bool falsyRadius = false, bool active = false}) {
    final background = fill(CompatKeys.background);
    final shadow = parseCssShadow(
        read(CompatKeys.shadow), (m) => warn(CompatKeys.shadow, m));
    if (!active) {
      return LuckyCellStyle(
          background: background,
          shadow: shadow,
          borderRadius: pixels(CompatKeys.borderRadius, falsy: falsyRadius));
    }
    final family = parseCssFontFamily(truthy(CompatKeys.fontStyle));
    final color = truthy(CompatKeys.fontColor);
    final weight = truthy(CompatKeys.fontWeight);
    final font = LuckyTextOverride(
        color: color == null
            ? null
            : parseCssColor(
                color.toString(), (m) => warn(CompatKeys.fontColor, m)),
        fontSize: pixels(CompatKeys.fontSize, falsy: true),
        fontFamily: family.family,
        fontFamilyFallback: family.fallback,
        fontWeight: weight == null ? null : parseCssFontWeight(weight),
        lineHeight: pixels(CompatKeys.lineHeight, falsy: true));
    return LuckyCellStyle(
        background: background,
        shadow: shadow,
        text: font == const LuckyTextOverride() ? null : font);
  }

  /// 读取图片来源；无效来源警告后跳过该图片。
  LuckyImage? image() {
    final provider = imageProviderFromSrc(
        read(CompatKeys.src), options, (m) => warn(CompatKeys.src, m));
    final result = provider == null
        ? null
        : LuckyImage(provider,
            top: length(CompatKeys.top),
            left: length(CompatKeys.left),
            width: length(CompatKeys.width),
            height: length(CompatKeys.height));
    return result;
  }

  /// 读取普通图片列表，诊断 formatter 等无法迁移的键。
  List<LuckyImage> images() {
    final result = <LuckyImage>[];
    for (final item in objects(CompatKeys.imgs)) {
      final value = item.image();
      item.finish();
      if (value != null) result.add(value);
    }
    return List.unmodifiable(result);
  }

  /// 读取矩形背景块；padding 仍遵循上游四值顺序。
  List<LuckyBoxBlock> blocks() =>
      List.unmodifiable(objects(CompatKeys.blocks).map((item) {
        final result = LuckyBoxBlock(
            background: item.fill(CompatKeys.background),
            borderRadius: item.pixels(CompatKeys.borderRadius) ?? 0,
            padding: parseCssPadding(item.read(CompatKeys.padding), options,
                (m) => item.warn(CompatKeys.padding, m)),
            images: item.images());
        item.finish();
        return result;
      }));

  /// 读取三玩法共用动画字段；只有显式启用时才按名字查找缓动。
  LuckyMotionOptions motion({bool speedFunction = false}) {
    final name = speedFunction ? string(CompatKeys.speedFunction) : null;
    final easing = options.honorSpeedFunction && name != null
        ? kLuckyCanvasEasingNames[name]
        : null;
    if (options.honorSpeedFunction && name != null && easing == null) {
      warn(CompatKeys.speedFunction, '未知缓动名称');
    }
    return LuckyMotionOptions(
        speed: number(CompatKeys.speed) ?? kLuckyDefaultSpeed,
        accelerationTime:
            _duration('accelerationTime', kLuckyDefaultAccelerationTime),
        decelerationTime:
            _duration('decelerationTime', kLuckyDefaultDecelerationTime),
        accelerationEasing: easing ?? LuckyEasings.quad,
        decelerationEasing: easing ?? LuckyEasings.quad,
        timebase: options.timebase,
        stopSolver: options.stopSolver);
  }

  /// 将毫秒四舍五入到微秒，保持小数毫秒精度。
  Duration _duration(String key, Duration fallback) {
    final value = number(key);
    return value == null
        ? fallback
        : Duration(
            microseconds:
                (value * Duration.microsecondsPerMillisecond).round());
  }
}

/// 括号感知地切分逗号；非法括号返回 null；不从公共入口导出。
List<String>? splitCompatCommas(String value) {
  final result = <String>[];
  var depth = 0;
  var start = 0;
  for (var index = 0; index < value.length; index++) {
    final char = value[index];
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (depth < 0) return null;
    if (char == ',' && depth == 0) {
      result.add(value.substring(start, index).trim());
      start = index + 1;
    }
  }
  if (depth != 0) return null;
  result.add(value.substring(start).trim());
  return result;
}
