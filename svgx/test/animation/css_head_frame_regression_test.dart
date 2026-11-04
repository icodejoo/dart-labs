import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart' show RustLib;
import 'package:svgx/src/animation/svg_document_parser.dart';

import 'pixel_test_utils.dart';

// Optional exact HEAD comparison. Record with SVGX_CSS_FRAME_RECORD, then
// compare with SVGX_CSS_FRAME_BASELINE; third-party samples stay out of git.
void main() {
  final directory = Platform.environment['SVGX_CSS_SAMPLES'];
  final record = Platform.environment['SVGX_CSS_FRAME_RECORD'];
  final baseline = Platform.environment['SVGX_CSS_FRAME_BASELINE'];
  if (directory == null || (record == null && baseline == null)) return;
  setUpAll(() async {
    await RustLib.init();
  });
  test('real CSS corpus exact RGBA frames match HEAD', () async {
    final expected = baseline == null
        ? null
        : jsonDecode(File(baseline).readAsStringSync()) as Map;
    final frames = <String, String>{};
    final files =
        Directory(directory)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.svg'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, hasLength(55));
    for (final file in files) {
      final doc = parseAnimatedSvgDocument(file.readAsStringSync());
      await resolveImageNodes(doc);
      for (final ms in [0, 250, 500, 990, 1010, 1500, 5000, 61000]) {
        final bytes = await renderAt(doc, Duration(milliseconds: ms));
        final key = '${file.uri.pathSegments.last}:$ms';
        final rgba = base64Encode(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        if (expected != null) {
          expect(rgba == expected[key], isTrue, reason: key);
        }
        frames[key] = rgba;
      }
    }
    expect(frames, hasLength(440));
    if (record != null) File(record).writeAsStringSync(jsonEncode(frames));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
