import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/platform_file_web.dart';
import 'package:xvg/src/animation/document_parse_worker_inline.dart';

/// 在 VM 上验证 web 的文件拒绝及内联解析行为。
void main() {
  test('web file paths fail with actionable diagnostics', () async {
    const file = File('file:///private.svg');
    final unsupported = isA<UnsupportedError>().having(
      (error) => error.message,
      'message',
      contains('asset, memory or network'),
    );
    await expectLater(file.readAsBytes(), throwsA(unsupported));
    await expectLater(file.readAsString(), throwsA(unsupported));
  });

  test(
    'inline parser preserves a large SMIL document without a worker',
    () async {
      final source =
          '<svg width="24" height="24">'
          '${'<rect width="2" height="2"/>' * 150}'
          '<circle r="2"><animate attributeName="opacity" values="0;1" '
          'dur="1s" repeatCount="indefinite"/></circle></svg>';
      final document = await DocumentParseWorker.instance.parse(source);
      expect(document.width, 24);
      expect(document.root.children, hasLength(151));
      expect(document.hasIndefiniteLoop, isTrue);
    },
  );

  test('inline parser reports malformed XML through its Future', () async {
    await expectLater(
      DocumentParseWorker.instance.parse('<svg><'),
      throwsA(anything),
    );
    await DocumentParseWorker.instance.dispose();
  });
}
