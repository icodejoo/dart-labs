import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart' show RustLib;
import 'package:svgx/src/animation/svg_document_parser.dart';

// Optional read-only corpus check; third-party SVGs remain outside the repo.
// 可选只读语料检查；第三方 SVG 留在仓库外。
void main() {
  final directory = Platform.environment['SVGX_TO_ANIMATION_SAMPLES'];
  if (directory == null) return;
  setUpAll(() async => RustLib.init());
  test('external to-animation corpus parses without exceptions', () {
    final files = Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.svg'))
        .toList();
    expect(files, isNotEmpty);
    var timelines = 0;
    for (final file in files) {
      final document = parseAnimatedSvgDocument(file.readAsStringSync());
      timelines += document.timelines.length;
    }
    // Print counts only, never the third-party source or frame payloads.
    // 只输出数量，不输出第三方源码或帧数据。
    // ignore: avoid_print
    print('to-animation corpus: ${files.length} SVGs, $timelines timelines');
    final minimum = int.tryParse(
      Platform.environment['SVGX_TO_ANIMATION_MIN_TIMELINES'] ?? '',
    );
    if (minimum != null) expect(timelines, greaterThanOrEqualTo(minimum));
  });
}
