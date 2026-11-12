import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_acceptance.dart';
import '../../tool/check_imports.dart';
import '../../tool/coverage.dart';

/// 门禁反例使用的实现路径。
const String _path = 'lib/a.dart';

/// 反例测试路径。
const String _testPath = 'test/phantom_test.dart';

/// 同时包含真实测试与未调用注册函数的源码。
const String _phantom =
    "void unused() { test('phantom', () {}); } void main() { test('real', () {}); }";

/// 从引用生成最小验收矩阵。
String _matrix(String references) =>
    '## 需求和不变量\n| ISS-R3 | 反例 | F1 | $references | 工具 | 已落地 |\n';

/// 验证评审发现的词法器、豁免范围和运行注册反例。
void main() {
  group('F1 gates', () {
    test('nested Dart comments cannot hide uninstrumented executable code', () {
      const source =
          '/* outer /* inner */ const marker = """\n*/\nint answer() => 42;\nconst text = """; // """;\n';
      expect(hasNoExecutableLines(source), isFalse);
      final report =
          computeCoverage(lcov: '', sources: {_path: source}, exemptions: {});
      expect(report.errors, contains(contains('MISSING coverage record')));
      for (final uncertain in [
        '/* unfinished',
        "const text = 'unfinished",
        r'''const text = '${unclosed'''
      ]) {
        expect(hasNoExecutableLines(uncertain), isFalse, reason: uncertain);
      }
      expect(
          hasNoExecutableLines(
              r'''/* a /* b */ c */ const text = r"/* not a comment */";'''),
          isTrue);
    });
    test(
        'exemptions reject matching ids and files used outside the registered location',
        () {
      final exemptions =
          parseExemptions('## 覆盖率豁免\n| COV-01 | $_path | 第1行 | 仅 profile |\n');
      final report = computeCoverage(
          lcov: 'SF:$_path\nDA:1,1\nDA:2,0\nend_of_record',
          sources: {
            _path:
                'void trace() {} // coverage:ignore-line COV-01\nint business() => 42; // coverage:ignore-line COV-01'
          },
          exemptions: exemptions);
      expect(report.errors, contains(contains('LOCATION MISMATCH')));
      expect(report.files.single.missing, [2]);
      final expanded = computeCoverage(
          lcov: 'SF:$_path\nDA:2,0\nend_of_record',
          sources: {
            _path:
                '// coverage:ignore-start COV-01\nint business() => 42;\n// coverage:ignore-end'
          },
          exemptions: exemptions);
      expect(expanded.errors, contains(contains('LOCATION MISMATCH')));
      expect(expanded.files.single.missing, [2]);
      final symbolic = parseExemptions(
          '## 覆盖率豁免\n| COV-01 | $_path | trace 的 Timeline.startSync 一行 | 仅 profile |');
      final scoped = computeCoverage(
          lcov: 'SF:$_path\nDA:2,0\nDA:5,0\nend_of_record',
          sources: {
            _path:
                'void trace() {\n developer.Timeline.startSync("trace"); // coverage:ignore-line COV-01\n}\nvoid business() {\n developer.Timeline.startSync("business"); // coverage:ignore-line COV-01\n}'
          },
          exemptions: symbolic);
      expect(scoped.errors, contains(contains('LOCATION MISMATCH')));
      expect(scoped.files.single.missing, [5]);
    });
    test(
        'Dart escaped import URIs and evaluated string interpolations obey import rules',
        () {
      const path = 'lib/src/core/foundation/a.dart';
      for (final (source, rule) in [
        (r"import 'package:flutter/\u006daterial.dart';", 'IMP-R10'),
        (r"import 'package:flutter/\u{77}idgets.dart';", 'IMP-R11'),
        (r"import 'dart:\x6dirrors';", 'IMP-R7'),
        (r"String dispatch(Object o) => '${o.runtimeType}';", 'IMP-R9'),
        (r'''String nested(Object o) => "${'${o.runtimeType}'}";''', 'IMP-R9'),
      ]) {
        expect(
            checkImports(libSources: {path: source}, pubspec: 'name: luckdraw'),
            contains(contains(rule)),
            reason: source);
      }
      expect(
          checkImports(libSources: {
            path:
                r'''const text = r"${o.runtimeType}"; const escaped = '\${o.runtimeType}';'''
          }, pubspec: 'name: luckdraw'),
          isEmpty);
    });
    test('static acceptance rejects phantom tests inside uncalled functions',
        () {
      final report = checkAcceptance(
          matrix: _matrix('`$_testPath :: phantom`<br>`$_testPath :: real`'),
          testSources: {_testPath: _phantom},
          fileExists: (_) => true);
      expect(report.errors, contains(contains('INVALID TEST')));
      expect(report.registrations, isNot(contains('$_testPath :: phantom')));
      for (final invalid in [
        "void unused() => test('phantom', () {}); void main() { test('real', () {}); }",
        "void main() { void unused() { test('phantom', () {}); } test('real', () {}); }",
        "void main() { test('real', () { test('phantom', () {}); }); }",
      ]) {
        expect(() => testNames(_testPath, invalid), throwsFormatException,
            reason: invalid);
      }
    });
    test(
        'ordinary literal loops are not mistaken for parameterized test registration',
        () {
      final names = testNames(_testPath,
          "void main() { test('real', () { for (final x in [Object(), Object()]) { expect(x, isNotNull); } for (final x in [1]) { expect(x, 1); } }); }");
      expect(names.active, {'$_testPath :: real'});
    });
    test(
        'runtime JSON acceptance rejects phantom references and validates the completed run',
        () async {
      final directory =
          Directory.systemTemp.createTempSync('luckdraw-f1-json-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final source = File('${directory.path}/$_testPath')
        ..parent.createSync(recursive: true);
      source.writeAsStringSync(_phantom);
      final matrix = File('${directory.path}/ACCEPTANCE.md')
        ..writeAsStringSync(
            _matrix('`$_testPath :: phantom`<br>`$_testPath :: real`'));
      final run = File('${directory.path}/run.json');
      final events = [
        {
          'type': 'suite',
          'suite': {'id': 0, 'path': source.absolute.path}
        },
        {
          'type': 'testStart',
          'test': {
            'id': 1,
            'name': 'real',
            'suiteID': 0,
            'metadata': {'skip': false}
          }
        },
        {
          'type': 'testDone',
          'testID': 1,
          'result': 'success',
          'skipped': false,
          'hidden': false
        },
        {'type': 'done', 'success': true},
      ];
      run.writeAsStringSync(events.map(jsonEncode).join('\n'));
      final script = File('tool/check_acceptance.dart').absolute.path;
      final result = await Process.run(
          'dart', [script, '--matrix=${matrix.path}', '--from-json', run.path],
          workingDirectory: directory.path);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('MISSING'));
      expect(result.stderr, contains('phantom'));
      matrix.writeAsStringSync(_matrix('`$_testPath :: real`'));
      final valid = await Process.run(
          'dart', [script, '--matrix=${matrix.path}', '--from-json', run.path],
          workingDirectory: directory.path);
      expect(valid.exitCode, 0, reason: '${valid.stderr}');
      run.writeAsStringSync(events.take(3).map(jsonEncode).join('\n'));
      final truncated = await Process.run(
          'dart', [script, '--matrix=${matrix.path}', '--from-json', run.path],
          workingDirectory: directory.path);
      expect(truncated.exitCode, 1);
      expect(truncated.stderr, contains('INCOMPLETE'));
    });
  });
}
