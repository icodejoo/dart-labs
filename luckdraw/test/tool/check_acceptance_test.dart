import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_acceptance.dart';

/// 默认的虚拟测试路径。
const String _path = 'test/example_test.dart';

/// 默认的虚拟测试注册。
const String _source = "group('outer', () { test('works', () {}); });";

/// 默认的完整矩阵引用。
const String _ref = '$_path :: outer > works';

/// 从用例单元格构造最小矩阵。
String _matrix(String cases, {String id = 'R4-03', String type = '工具'}) =>
    '## 需求和不变量\n| $id | 约束 | 设计 | $cases | $type | 通过 |\n';

/// 使用单个虚拟测试执行矩阵检查。
AcceptanceCheck _check(String matrix,
        {String source = _source, bool exists = true}) =>
    checkAcceptance(
        matrix: matrix,
        testSources: {_path: source},
        fileExists: (_) => exists);

/// 验证轻量词法器与矩阵双向检查。
void main() {
  group('check_acceptance', () {
    test('expands string literal list parameters without quotes', () {
      final result = _check(
          _matrix('`$_path :: colors > red`<br>`$_path :: colors > blue`'),
          source:
              r'''group('colors', () { for (final color in ['red', "blue"]) { test('$color', () {}); } });''');
      expect(result.errors, isEmpty);
      expect(result.registrations, hasLength(2));
    });
    test('reports missing and unmapped references', () {
      final result = _check(_matrix('`$_path :: missing`'));
      expect(result.errors, contains(contains('MISSING')));
      expect(result.errors, contains(contains('UNMAPPED')));
    });
    test('scans integration_test and bench directories', () {
      const integration = 'example/integration_test/flow_test.dart';
      const bench = 'tool/bench/integration_test/speed_test.dart';
      final result = checkAcceptance(
          matrix: _matrix(
              '`$integration :: outer > works`<br>`$bench :: outer > works`'),
          testSources: {
            integration: _source,
            bench: _source,
            'unrelated/ignored_test.dart': _source
          },
          fileExists: (_) => true);
      expect(result.errors, isEmpty);
      expect(result.registrations, hasLength(2));
    });
    test('validates cmd references point at existing scripts', () {
      final matrix =
          _matrix('`$_ref`<br>`cmd: dart run tool/coverage.dart --min=100`');
      expect(_check(matrix).errors, isEmpty);
      expect(_check(matrix, exists: false).errors.single, contains('BAD CMD'));
    });
    test('tracks nested groups and ignores strings and comments', () {
      final result = testNames(_path, '''
// test('fake', () {});
const text = "test('fake', () {})";
group('outer', () {
  group('inner', () { testWidgets('widget', (tester) async {}); });
  test('works', () { final braces = '{}'; });
});
''');
      expect(result.active, {'$_path :: outer > inner > widget', _ref});
      expect(result.skipped, isEmpty);
    });
    test('skipped tests and groups must not be referenced', () {
      final result = _check(_matrix('`$_ref`'),
          source: "group('outer', () { test('works', () {}); }, skip: true);");
      expect(result.registrations, isEmpty);
      expect(result.errors.single, contains('SKIPPED'));
      final names = testNames(_path,
          "test('active', () {}, skip: false); test('null', () {}, skip: null); test('skip', () {}, skip: 'reason');");
      expect(names.active, hasLength(2));
      expect(names.skipped, hasLength(1));
    });
    test('rejects duplicate ids empty rows and nonliteral names', () {
      final duplicate = '${_matrix('`$_ref`')}| R4-03 | x | x | | 工具 | 待定 |';
      expect(_check(duplicate).errors, contains(contains('DUPLICATE ID')));
      expect(_check(duplicate).errors, contains(contains('EMPTY ROW')));
      final manual = checkAcceptance(
          matrix: _matrix('', type: '人工'),
          testSources: {},
          fileExists: (_) => true);
      expect(manual.errors, isEmpty);
      expect(_check(_matrix('`$_ref`'), source: 'test(name, () {});').errors,
          contains(contains('Nonliteral')));
      expect(
          _check(_matrix('`$_ref`'), source: "test('a' + 'b', () {});").errors,
          contains(contains('Nonliteral')));
    });
    test(
        'rejects unknown interpolations repeated loop variables and duplicate tests',
        () {
      expect(() => testNames(_path, r"test('$unknown', () {});"),
          throwsFormatException);
      expect(
          () => testNames(_path,
              r"for (final x in ['a']) { test('$x one', () {}); } for (final x in ['b']) { test('$x two', () {}); }"),
          throwsFormatException);
      expect(
          () => testNames(_path, "test('same', () {}); test('same', () {});"),
          throwsFormatException);
    });
  });
}
