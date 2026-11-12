import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/src/compat/json_reader.dart';

/// 验证读取器保留显式假值、共享警告与括号感知切分。
void main() {
  group('compat json reader', () {
    test('nested reads preserve false zero and diagnostic paths', () {
      final warnings = <LuckyCanvasCompatWarning>[];
      final reader = CompatJsonReader({
        'enabled': false,
        'count': 0,
        'items': [1, 'x'],
        'style': <Object?, Object?>{'fontSize': 12, 3: true},
        'badObject': true,
        'badArray': 'bad',
        'callback': () {},
      }, warnings);
      expect(reader.read('enabled'), isFalse);
      expect(reader.read('count'), 0);
      expect(reader.has('enabled'), isTrue);
      expect(reader.has('missing'), isFalse);
      expect(reader.read('missing'), isNull);
      expect(reader.array('items'), [1, 'x']);
      expect(reader.array('missing'), isEmpty);
      expect(reader.array('badArray'), isEmpty);
      expect(warnings.single.path, 'badArray');
      final style = reader.object('style');
      expect(style.read('fontSize'), 12);
      style.warn('fontSize', '测试诊断');
      expect(warnings.last,
          const LuckyCanvasCompatWarning('style.fontSize', '测试诊断'));
      expect(warnings[1].path, 'style');
      expect(reader.object('badObject').data, isEmpty);
      expect(reader.object('missing').data, isEmpty);
      final indexed =
          CompatJsonReader({}, warnings, path: 'prizes[2].fonts[0]');
      indexed.warn('fontSize', '无法解析');
      expect(warnings.last.path, 'prizes[2].fonts[0].fontSize');
      final before = warnings.length;
      reader.warnUnknown(
          {'enabled', 'count', 'items', 'style', 'badObject', 'badArray'});
      expect(warnings.length, before + 1);
      expect(warnings.last.path, 'callback');
      expect(warnings.last.message, contains('忽略'));
    });
    test(
        'comma splitting preserves nested calls and rejects unmatched parentheses',
        () {
      expect(splitCompatCommas('red, rgba(1, 2, 3, .5), nested(rgb(1,2,3))'),
          ['red', 'rgba(1, 2, 3, .5)', 'nested(rgb(1,2,3))']);
      expect(splitCompatCommas(''), ['']);
      expect(splitCompatCommas('a,'), ['a', '']);
      expect(splitCompatCommas('a),b'), isNull);
      expect(splitCompatCommas('a(b,c'), isNull);
    });
  });
}
