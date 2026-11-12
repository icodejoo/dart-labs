import 'package:flutter/painting.dart';

import '../core/foundation/edge_insets.dart';
import 'compat_options.dart';
import 'css_length.dart';

/// CSS 静态字重的步长。
const double _weightStep = 100;

/// padding 四值上限；上游超过四值仍只读取前四项。
const int _paddingLimit = 4;

/// Flutter 默认无衬线字体对应的 CSS 通用族名称。
const String _sansSerif = 'sans-serif';

/// 上游无效的单边 padding 键。
const Set<String> _individualPaddingKeys = {
  'paddingTop',
  'paddingBottom',
  'paddingLeft',
  'paddingRight',
};

/// 解析上游 padding；[options] 提供单位基准，无效项警告并按零处理。
///
/// 字符串按字面空格切分；四值顺序为上、下、左、右。
/// 也接受含 padding 的对象，忽略单边字段并警告。例如 '1 2 3 4'。
LuckyEdgeInsets parseCssPadding(Object? value, LuckyCanvasCompatOptions options,
    void Function(String message) warn) {
  var source = value;
  if (source is Map<Object?, Object?>) {
    for (final key in _individualPaddingKeys) {
      if (source.containsKey(key)) warn('$key 被忽略：上游单边 padding 不生效 (U-01)');
    }
    source = source['padding'];
  }
  if (source == null) return LuckyEdgeInsets.zero;
  if (source is! String) {
    warn('padding 必须是字符串');
    return LuckyEdgeInsets.zero;
  }
  // 上游 utils/index.ts:74，连续空格产生空字符串，按 Number('') = 0 处理。
  final values = source.split(' ').take(_paddingLimit).map((token) {
    final length = parseCssLength(token, options, warn);
    return length == null ? 0.0 : resolveBaseless(length);
  }).toList();
  if (values.length == _paddingLimit) {
    return LuckyEdgeInsets.only(
        top: values[0], bottom: values[1], left: values[2], right: values[3]);
  }
  return LuckyEdgeInsets.css(values);
}

/// 解析数字或 normal/bold/bolder/lighter；未知值返回 null。
///
/// 数字按最近的百位映射到 w100–w900；例如 'bold' 返回 FontWeight.w700。
FontWeight? parseCssFontWeight(Object? value) {
  final text = value is String ? value.trim().toLowerCase() : value.toString();
  final keyword = switch (text) {
    'normal' => FontWeight.w400,
    'bold' || 'bolder' => FontWeight.w700,
    'lighter' => FontWeight.w300,
    _ => null,
  };
  if (keyword != null) return keyword;
  final number = double.tryParse(text);
  if (number == null || !number.isFinite) return null;
  final index =
      (number / _weightStep).round().clamp(1, FontWeight.values.length) - 1;
  return FontWeight.values[index];
}

/// 内部字体族解析器；返回首选 family 和按序 fallback，sans-serif 映射为 null。
///
/// 例如 '"Roboto", Arial, sans-serif' 返回 Roboto 与 Arial 回退列表。
({String? family, List<String>? fallback}) parseCssFontFamily(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return (family: null, fallback: null);
  }
  final parts = <String>[];
  var start = 0;
  String? quote;
  for (var index = 0; index < value.length; index++) {
    final char = value[index];
    if (quote != null) {
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == ',') {
      parts.add(value.substring(start, index));
      start = index + 1;
    }
  }
  parts.add(value.substring(start));
  final families = parts
      .map((token) => token.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), ''))
      .where((token) => token.isNotEmpty)
      .toList();
  if (families.isEmpty) return (family: null, fallback: null);
  final family =
      families.first.toLowerCase() == _sansSerif ? null : families.first;
  final fallback = families
      .skip(1)
      .where((token) => token.toLowerCase() != _sansSerif)
      .toList();
  return (
    family: family,
    fallback: fallback.isEmpty ? null : List.unmodifiable(fallback)
  );
}

/// 内部图片来源解析器；http(s) 使用 NetworkImage，data URI 使用 MemoryImage，其余为资源。
///
/// [options.assetResolver] 可替代 AssetImage；无效来源返回 null 并调用 [warn]。
ImageProvider<Object>? imageProviderFromSrc(Object? value,
    LuckyCanvasCompatOptions options, void Function(String message) warn) {
  if (value is! String || value.isEmpty) {
    warn('图片 src 必须是非空字符串');
    return null;
  }
  final lower = value.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return NetworkImage(value);
  }
  if (lower.startsWith('data:')) {
    try {
      return MemoryImage(UriData.parse(value).contentAsBytes());
    } on FormatException {
      warn('图片 data URI 无效');
      return null;
    }
  }
  return options.assetResolver?.call(value) ?? AssetImage(value);
}
