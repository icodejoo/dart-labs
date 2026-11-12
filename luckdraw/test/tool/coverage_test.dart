import 'package:flutter_test/flutter_test.dart';

import '../../tool/coverage.dart';

/// 覆盖率夹具中的实现路径。
const String _path = 'lib/src/core/a.dart';

/// 夹具中的实现源码。
const String _source = 'int answer() => 42;';

/// 夹具中的一行命中记录。
const String _hit = 'SF:$_path\nDA:1,1\nend_of_record';

/// 夹具中的豁免编号。
const String _id = 'COV-01';

/// 使用单个实现夹具运行纯函数覆盖率门禁。
CoverageReport _report(
        {String source = _source,
        String lcov = _hit,
        Map<String, CoverageExemption> exemptions = const {}}) =>
    computeCoverage(
        lcov: lcov, sources: {_path: source}, exemptions: exemptions);

/// 验证覆盖率、未采集文件与双向豁免登记。
void main() {
  group('coverage gate', () {
    test('plain enums pass without coverage records', () {
      const source = '''
/// 时间基准。
enum LuckyTimebase { /* 时间。 */ time, // 帧。
frame, }
enum Other { value }
enum WithSeparator { value; }
enum WithTrailingComma { value,; }
const answer = 42;
''';
      final report = _report(source: source, lcov: '');
      expect(hasNoExecutableLines(source), isTrue);
      expect(report.errors, isEmpty);
      expect(report.total, 0);
      expect(report.percent, 100);
    });
    test('enhanced enums still require coverage records', () {
      for (final enhanced in [
        'enum E { a; int get value => 1; }',
        'enum E { a; void method() {} }',
        'enum E { a; final int field = 1; }',
        'enum E { a(1); const E(this.x); final int x; }',
        'enum E implements Comparable<E> { a; }',
        'enum E { a() }',
        'enum E { a',
        'enum E {}',
      ]) {
        expect(hasNoExecutableLines(enhanced), isFalse, reason: enhanced);
        expect(_report(source: enhanced, lcov: '').errors.single,
            contains('MISSING coverage record'));
      }
    });
    test('pure const files pass without coverage records', () {
      const source = '''
import 'dart:ui';
library;
// 常量中的分号与注释符不影响声明边界。
const url = 'https://example.org;/* */';
const durations = <Duration>[Duration(milliseconds: 1)];
const table = <String, int>{'a': 1};
''';
      expect(hasNoExecutableLines(source), isTrue);
      final report = _report(source: source, lcov: '');
      expect(report.errors, isEmpty);
      expect(report.total, 0);
      expect(report.percent, 100);
    });
    test('runtime final initializers still require coverage records', () {
      expect(_report(source: 'final x = foo();', lcov: '').errors.single,
          contains('MISSING coverage record'));
      expect(hasNoExecutableLines('const x = 1; final y = foo();'), isFalse);
    });
    test('classes and functions still require coverage records', () {
      for (final source in ['class A {}', 'int foo() => 1;']) {
        expect(_report(source: source, lcov: '').errors.single,
            contains('MISSING coverage record'));
      }
      for (final invalidSource in [
        'const x = () => 1;',
        'const x = () { return 1; };',
        'const x = () {};',
        'const x = 1',
        'const x = [1;',
        'const x = ];',
        "part 'a.dart';"
      ]) {
        expect(hasNoExecutableLines(invalidSource), isFalse,
            reason: invalidSource);
      }
    });
    test('typedef declarations have no executable lines', () {
      expect(
          hasNoExecutableLines('typedef F = void Function({int x});'), isTrue);
      expect(hasNoExecutableLines('part of sample; typedef F(int x);'), isTrue);
      expect(_report(source: 'typedef F = void Function();', lcov: '').errors,
          isEmpty);
    });
    test('ignore markers require a registered exemption id', () {
      expect(_report(source: '$_source // coverage:ignore-line').errors.single,
          contains('MARKER WITHOUT ID'));
      expect(
          _report(source: '$_source // coverage:ignore-line $_id')
              .errors
              .single,
          contains('UNREGISTERED'));
      final valid = _report(
          source: '$_source // coverage:ignore-line $_id',
          exemptions: {
            _id: const CoverageExemption(_path, '第1行', '仅 profile')
          });
      expect(valid.errors, isEmpty);
      expect(valid.total, 0);
      expect(valid.percent, 100);
      expect(
          _report(source: '$_source // coverage:ignore-line $_id', exemptions: {
            _id: const CoverageExemption('lib/b.dart', '第1行', '仅 profile')
          }).errors.single,
          contains('FILE MISMATCH'));
    });
    test('unused registered exemptions fail the gate', () {
      expect(
          _report(exemptions: {
            _id: const CoverageExemption(_path, '第1行', '仅 profile')
          }).errors.single,
          contains('UNUSED'));
    });
    test('strings cannot impersonate exemption comments', () {
      final report = _report(
          source: 'const text = "// coverage:ignore-line $_id";',
          lcov: 'SF:$_path\nDA:1,0\nend_of_record',
          exemptions: {
            _id: const CoverageExemption(_path, '第1行', '仅 profile')
          });
      expect(report.total, 1);
      expect(report.hit, 0);
      expect(report.errors.single, contains('UNUSED'));
    });
    test('uninstrumented implementation files fail the gate', () {
      for (final lcov in ['', 'SF:$_path\nend_of_record']) {
        expect(_report(lcov: lcov).errors.single,
            contains('MISSING coverage record'));
      }
      final report = computeCoverage(lcov: _hit, sources: {
        _path: _source,
        'lib/missing.dart': 'final answer = foo();'
      }, exemptions: {});
      expect(report.errors.single, contains('lib/missing.dart'));
    });
    test('empty libraries pass while implementation records remain mandatory',
        () {
      final empty = computeCoverage(lcov: '', sources: {}, exemptions: {});
      expect(empty.errors, isEmpty);
      expect(empty.percent, 100);
      final directives = _report(
          source: '/// 空入口。\nlibrary;\nexport\n "x.dart" show X;\n/* 注释 */',
          lcov: '');
      expect(directives.errors, isEmpty);
      expect(directives.percent, 100);
      expect(
          _report(source: 'const url = "https://example.org";', lcov: '')
              .errors,
          isEmpty);
    });
    test('normalizes absolute Windows paths and merges duplicate records', () {
      final report = _report(
          lcov:
              'SF:E:\\work\\luckdraw\\lib\\src\\core\\a.dart\nDA:1,0\nend_of_record\n$_hit');
      expect(report.errors, isEmpty);
      expect(report.hit, 1);
      expect(report.total, 1);
      expect(report.percent, 100);
      final missed = _report(lcov: 'SF:$_path\nDA:1,0\nend_of_record');
      expect(missed.percent, 0);
      expect(missed.files.single.missing, [1]);
    });
    test('block exemptions exclude only their registered lines', () {
      final report = _report(
          source:
              '// coverage:ignore-start $_id\n$_source\n// coverage:ignore-end\n$_source',
          lcov: 'SF:$_path\nDA:2,0\nDA:4,1\nend_of_record',
          exemptions: {
            _id: const CoverageExemption(_path, '第1-3行', '仅 profile')
          });
      expect(report.errors, isEmpty);
      expect(report.hit, 1);
      expect(report.total, 1);
      expect(report.percent, 100);
    });
    test('malformed blocks and invalid DA records fail explicitly', () {
      expect(_report(source: '// coverage:ignore-end\n$_source').errors,
          isNotEmpty);
      expect(
          _report(
              source: '// coverage:ignore-start $_id\n$_source',
              exemptions: {
                _id: const CoverageExemption(_path, '第1-2行', '仅 profile')
              }).errors.single,
          contains('UNCLOSED'));
      expect(_report(lcov: 'SF:$_path\nDA:x,1\nDA:1,-1\nDA:5,1').errors,
          hasLength(3));
    });
    test('exemption table requires unique ids locations and reasons', () {
      const header = '## 覆盖率豁免\n';
      const row = '| $_id | $_path | 第 1 行 | 仅 profile 可达 |\n';
      final registered = parseExemptions('$header$row');
      expect(registered[_id]!.path, _path);
      expect(registered[_id]!.location, '第 1 行');
      expect(registered[_id]!.reason, '仅 profile 可达');
      expect(() => parseExemptions('$header$row$row'), throwsFormatException);
      expect(() => parseExemptions('$header| $_id | $_path | 第 1 行 | |'),
          throwsFormatException);
      expect(parseExemptions('## 其他\n$row'), isEmpty);
    });
  });
}
