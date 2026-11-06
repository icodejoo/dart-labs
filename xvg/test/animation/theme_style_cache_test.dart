// Shared-document style caching must compare theme values across painters.
//
// 跨绘制器共享文档时，样式缓存必须比较主题值。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/svg_document_cache.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/svg_theme.dart';

import 'node_test_utils.dart';

/// Canvas side in pixels.
///
/// 画布边长，单位像素。
const _size = 24;

/// Opaque red theme color.
///
/// 不透明红色主题色。
const _red = Color(0xFFFF0000);

/// Opaque blue theme color.
///
/// 不透明蓝色主题色。
const _blue = Color(0xFF0000FF);

/// Alternating-painter repetitions.
///
/// 交替绘制器的重复次数。
const _rounds = 3;

/// Channels in a raw RGBA pixel.
///
/// 原始 RGBA 像素的通道数。
const _channels = 4;

/// Fully opaque channel value.
///
/// 完全不透明的通道值。
const _opaque = 255;

/// Animated source whose styles remain constant.
///
/// 样式保持不变的动画源。
const _source =
    '<svg xmlns="http://www.w3.org/2000/svg" width="$_size" height="$_size">'
    '<g><rect width="$_size" height="$_size" fill="currentColor">'
    '<animateTransform attributeName="transform" type="translate" '
    'values="0 0;1 0" dur="1s" repeatCount="indefinite"/>'
    '</rect></g></svg>';

/// Creates a distinct runtime theme for [color].
///
/// 为 [color] 创建一个不同身份的运行时主题。
XvgTheme _theme(Color color) => XvgTheme(currentColor: color);

/// Records a frame using the shared document and a fresh painter.
///
/// 使用共享文档和新绘制器录制一帧。
ui.Picture _record(SvgDocument document, XvgTheme theme) {
  final recorder = ui.PictureRecorder();
  final clock = ValueNotifier(Duration.zero);
  AnimatedSvgPainter(
    root: document.root,
    intrinsicSize: Size(document.width, document.height),
    clock: clock,
    theme: theme,
    fit: BoxFit.fill,
    alignment: Alignment.center,
  ).paint(Canvas(recorder), Size(_size.toDouble(), _size.toDouble()));
  clock.dispose();
  return recorder.endRecording();
}

/// Reads the center pixel after painting with [theme].
///
/// 使用 [theme] 绘制后读取中心像素。
Future<List<int>> _centerPixel(SvgDocument document, XvgTheme theme) async {
  final picture = _record(document, theme);
  final image = await picture.toImage(_size, _size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = ((_size ~/ 2) * _size + _size ~/ 2) * _channels;
  final pixel = bytes!.buffer
      .asUint8List(bytes.offsetInBytes + offset, _channels)
      .toList();
  image.dispose();
  picture.dispose();
  return pixel;
}

/// Verifies theme cache reuse and color isolation.
///
/// 验证主题缓存复用与颜色隔离。
void main() {
  setUp(XvgDocumentCache.instance.clear);
  tearDown(XvgDocumentCache.instance.clear);

  test('equal distinct themes reuse every shared node style', () {
    final first = XvgDocumentCache.instance.getOrParse(_source).document;
    final second = XvgDocumentCache.instance.getOrParse(_source).document;
    final firstTheme = _theme(_red);
    final secondTheme = _theme(_red);
    expect(second, same(first));
    expect(secondTheme, isNot(same(firstTheme)));
    expect(secondTheme, firstTheme);
    expect(secondTheme.hashCode, firstTheme.hashCode);

    _record(first, firstTheme).dispose();
    final nodes = walkNodes(first.root).toList();
    final styles = [for (final node in nodes) node.cachedStyle];
    expect(styles, everyElement(isNotNull));
    for (var round = 0; round < _rounds; round++) {
      for (final theme in [secondTheme, firstTheme]) {
        _record(second, theme).dispose();
        for (var i = 0; i < nodes.length; i++) {
          expect(
            nodes[i].cachedStyle,
            same(styles[i]),
            reason: 'node $i must reuse its style for an equal theme',
          );
        }
      }
    }
  });

  test('different themes keep their own pixels on a shared document', () async {
    final first = XvgDocumentCache.instance.getOrParse(_source).document;
    final second = XvgDocumentCache.instance.getOrParse(_source).document;
    final redTheme = _theme(_red);
    final blueTheme = _theme(_blue);
    expect(second, same(first));
    expect(redTheme, isNot(blueTheme));

    for (var round = 0; round < _rounds; round++) {
      expect(await _centerPixel(first, redTheme), [_opaque, 0, 0, _opaque]);
      expect(await _centerPixel(second, blueTheme), [0, 0, _opaque, _opaque]);
    }
  });
}
