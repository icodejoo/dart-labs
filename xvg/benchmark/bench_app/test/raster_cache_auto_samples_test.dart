import 'dart:typed_data';

import 'package:bench_app/raster_cache_auto_samples.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:xvg/src/rust/api/svg.dart';

/// 验证阈值输入是解析后的绘制特征，并覆盖可复用的样本生成器。
void main() {
  test('统计内容面积及其溢出状态，并保留未知边界', () {
    const bounds = SvgContentBounds(left: -5, top: 10, right: 45, bottom: 40);
    const scene = SvgScene(
      width: 100,
      height: 50,
      paths: [],
      images: [],
      contentBounds: bounds,
    );
    final features = autoR2Features(scene);
    expect(features['content_bounds'], [-5, 10, 45, 40]);
    expect(features['content_area'], 1500);
    expect(features['content_area_ratio'], .3);
    expect(features['content_overflow'], isTrue);
    const unknown = SvgScene(width: 100, height: 50, paths: [], images: []);
    expect(autoR2Features(unknown)['content_overflow'], isNull);
  });

  test('每个合成变体保持路径总数，按开关施加效果', () {
    const pathCount = 50;
    final plain = syntheticAutoSvg(pathCount);
    final decorated = syntheticAutoSvg(
      pathCount,
      blur: true,
      layers: true,
      gradients: true,
    );
    final draws = RegExp(r'<path ');
    expect(draws.allMatches(plain), hasLength(pathCount));
    expect(draws.allMatches(decorated), hasLength(pathCount));
    expect(plain, isNot(contains('url(#soft)')));
    expect(decorated, contains('filter="url(#soft)"'));
    expect(decorated, contains('clip-path="url(#inset)"'));
    expect(decorated, contains('mask="url(#coverage)"'));
    expect(decorated, contains('opacity=".82"'));
    expect(decorated, contains('fill="url(#paint)"'));
  });

  test('整张 SVG 留出，运行时内容保留专用匿名编号', () {
    final samples = autoSamples('public', 'runtime');
    expect(
      samples.map((sample) => sample.id).toSet(),
      hasLength(samples.length),
    );
    expect(
      samples.where((sample) => sample.validation).map((sample) => sample.id),
      containsAll(['mdi-236', '233KB', 'synthetic-1000-plain']),
    );
    expect(
      samples.singleWhere((sample) => sample.source == 'runtime').id,
      '233KB',
    );
  });

  test('按解析后实际使用次数统计画笔、入栈及路径和图片效果', () {
    const mask = SvgMask(
      kind: 1,
      x: 0,
      y: 0,
      width: 12,
      height: 12,
      paths: [],
      commands: [],
    );
    const blur = SvgBlur(stdDevX: 2, stdDevY: 2);
    final gradient = SvgGradient(
      kind: 0,
      x1: 0,
      y1: 0,
      x2: 12,
      y2: 12,
      radius: 0,
      matrix: Float32List(0),
      stops: const [],
      spread: 0,
    );
    final path = SvgPath(
      verbs: Uint8List.fromList([0, 3, 4]),
      points: Float32List.fromList([0, 0, 2, 4, 6, 8, 10, 12]),
      hasFill: true,
      fillArgb: 0xff112233,
      evenOdd: false,
      hasStroke: true,
      strokeArgb: 0xff112233,
      strokeWidth: 1,
      strokeFirst: false,
      fillGradient: gradient,
      strokeGradient: gradient,
      effects: const SvgEffects(mask: mask, blur: blur),
    );
    final image = SvgImage(
      x: 0,
      y: 0,
      width: 12,
      height: 12,
      matrix: Float32List.fromList([1, 0, 0, 1, 0, 0]),
      data: Uint8List(0),
      format: SvgImageFormat.png,
      mask: mask,
      blur: blur,
    );
    final scene = SvgScene(
      width: 12,
      height: 12,
      paths: [path],
      images: [image],
      displayList: SvgDisplayList(
        clips: const [],
        commands: [
          for (final kind in [2, 4, 0, 1, 5, 3])
            SvgCommand(kind: kind, index: 0, opacity: .5),
        ],
      ),
    );
    expect(autoFeatures(scene), {
      'paths': 1,
      'verbs': 3,
      'points': 4,
      'strokes': 1,
      'gradients': 2,
      'opacity': 1,
      'clips': 1,
      'masks': 2,
      'blurs': 2,
      'images': 1,
    });
  });
}
