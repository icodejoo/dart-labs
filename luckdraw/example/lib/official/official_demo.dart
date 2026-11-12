import 'package:flutter/material.dart';
import 'package:luckdraw/luckdraw.dart';

/// 官方示例站（100px.net）中的一个条目，用于和 luckdraw 的渲染结果逐项对照。
///
/// 例如 `OfficialDemo(id: 'wheel-block-padding', title: '通过padding挤出边框',
/// refAsset: 'wheel_01', builder: (_) => OfficialWheel(config: ...))`。
class OfficialDemo {
  /// 创建条目；[refAsset] 是 `assets/official_ref/` 下不带扩展名的官方截图名。
  const OfficialDemo(
      {required this.id,
      required this.title,
      required this.refAsset,
      required this.builder});

  /// 稳定标识，沿用官方示例键名，如 `wheel-block-padding`。
  final String id;

  /// 官方页面上的中文标题。
  final String title;

  /// 官方截图资源名（不含目录和扩展名），如 `wheel_01`。
  final String refAsset;

  /// 构建可运行的示例，内部自行持有并释放控制器。
  final WidgetBuilder builder;
}

/// 一组示例（对应官方站的一个页面或分区）。
class OfficialSection {
  /// 创建分区；例如 `OfficialSection('大转盘', wheelDemos)`。
  const OfficialSection(this.title, this.demos);

  /// 分区标题。
  final String title;

  /// 分区内按官方顺序排列的示例。
  final List<OfficialDemo> demos;
}

/// 官方素材图，对应官方 `/static/imgs/<name>`；例如 `officialImage('wheel-bg.png')`。
AssetImage officialImage(String name) => AssetImage('assets/imgs/$name');

/// 像素长度，对应官方的 `'10px'`；例如 `px(10)`。
LuckyLength px(double value) => LuckyLength.px(value);

/// 百分比长度，对应官方的 `'10%'`；例如 `pct(10)`。
LuckyLength pct(double value) => LuckyLength.percent(value);

/// 把 `#rrggbb` / `#rgb` 十六进制色转成不透明 [Color]；例如 `hex('#869cfa')`。
Color hex(String value) {
  var body = value.replaceFirst('#', '');
  if (body.length == 3) {
    body = body.split('').map((c) => '$c$c').join();
  }
  return Color(0xFF000000 | int.parse(body, radix: 16));
}

/// 纯色填充，对应官方的 `background: '#e9e8fe'`；例如 `fill('#e9e8fe')`。
LuckyFill fill(String color) => LuckyFill.color(hex(color));
