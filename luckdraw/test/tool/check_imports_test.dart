import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_imports.dart';

/// 默认纯逻辑源文件位置。
const String _core = 'lib/src/core/foundation/a.dart';

/// 虚拟包清单。
const String _pubspec = 'name: luckdraw\n';

/// 字符串到实现的常量表规则号。
const String _implementationTableRule = 'TS-CONST-MAP';

/// 以单文件虚拟源码运行依赖门禁。
List<String> _check(String source, {String path = _core}) =>
    checkImports(libSources: {path: source}, pubspec: _pubspec);

/// 验证依赖图、入口限制和全部静态规则的通过与失败样例。
void main() {
  group('check_imports', () {
    test(
        'rejects core const implementation tables but permits compat and aliases',
        () {
      const table =
          "const easings = {'quad': QuadEasing(), 'expo': LuckyEasings.expo};";
      expect(
          _check(table)
              .where((error) => error.contains(_implementationTableRule)),
          hasLength(1));
      expect(_check(table, path: 'lib/src/compat/easings.dart'), isEmpty);
      expect(_check("const table = {'quad': const easing.QuadEasing()};"),
          contains(contains(_implementationTableRule)));
      expect(_check("const numbers = {'one': 1}; const text = {'a': 'b'};"),
          isEmpty);
      expect(
          _check(
              'abstract final class Easings { static const quad = QuadEasing(); }'),
          isEmpty);
      expect(_check('// const table = {\'q\': QuadEasing()};'), isEmpty);
    });
    test('function typedefs pass while top-level mutable variables fail', () {
      expect(_check('typedef Foo = void Function(int value);'), isEmpty);
      expect(_check('typedef Foo = void Function({int value});'), isEmpty);
      expect(_check('typedef Foo = void Function(); final x = foo();').single,
          contains('IMP-R8'));
      expect(_check('var x = 1;').single, contains('IMP-R8'));
    });
    test('accepts the allowed dependency graph', () {
      final sources = <String, String>{
        _core:
            "import 'dart:math'; import 'package:flutter/painting.dart'; const n = 1;",
        'lib/luckdraw.dart':
            "library; export 'src/core/foundation/a.dart' show A;",
        'lib/extend.dart':
            "library; export 'src/core/foundation/a.dart' show A;",
        'lib/compat.dart': "library; export 'src/compat/a.dart' show A;",
        'lib/testing.dart': "library; export 'src/testing/a.dart' show A;",
        'lib/src/compat/a.dart':
            "import '../core/foundation/a.dart'; import '../wheel/a.dart'; import '../grid/a.dart'; import '../slot/a.dart';",
        'lib/src/testing/a.dart':
            "import '../core/foundation/a.dart'; import 'other.dart';",
      };
      for (final game in [
        'wheel',
        'grid',
        'slot',
        'capsule',
        'number_wheel',
        'lots',
        'lotto'
      ]) {
        sources['lib/$game.dart'] =
            "library; export 'luckdraw.dart'; export 'src/$game/a.dart' show A;";
        sources['lib/src/$game/a.dart'] =
            "import '../core/foundation/a.dart'; import 'other.dart';";
      }
      expect(checkImports(libSources: sources, pubspec: _pubspec), isEmpty);
    });
    test('rejects core importing a game', () {
      expect(_check("import '../../wheel/a.dart';").single, contains('IMP-R1'));
    });
    test('allows only the four conformance games from its implementation', () {
      const path = 'lib/src/testing/conformance.dart';
      final allowedGames = ['wheel', 'grid', 'slot', 'lots'];
      for (final game in allowedGames) {
        expect(_check("import '../$game/a.dart';", path: path), isEmpty);
        expect(
            _check("import '../$game/a.dart';", path: 'lib/src/testing/a.dart'),
            contains(contains('IMP-R4')));
      }
      final forbiddenZones = ['capsule', 'number_wheel', 'lotto', 'compat'];
      for (final zone in forbiddenZones) {
        expect(_check("import '../$zone/a.dart';", path: path),
            contains(contains('IMP-R4')));
      }
    });
    test('rejects a game importing another game or compat', () {
      final errors = _check(
          "import '../wheel/a.dart'; import '../compat/a.dart';",
          path: 'lib/src/grid/a.dart');
      expect(errors, isNotEmpty);
      expect(errors.every((e) => e.contains('IMP-R2')), isTrue);
    });
    test('rejects top-level side-effect initializers and part directives', () {
      for (final declaration in [
        'final registry = Registry();',
        'var registry = Registry();',
        'late final Registry registry = Registry();',
        'Registry registry = Registry();',
        'class C { static final registry = Registry(); }'
      ]) {
        expect(_check(declaration), contains(contains('IMP-R8')),
            reason: declaration);
      }
      expect(_check("part 'x.dart';").single, contains('IMP-R6'));
      expect(_check('part of x;').single, contains('IMP-R6'));
    });
    test('rejects runtimeType dispatch mirrors and material imports', () {
      final errors = _check(
          "import 'dart:mirrors';\nimport 'package:flutter/material.dart';\nimport 'package:flutter/cupertino.dart';\nObject f(Object o) => o.runtimeType;\nconst map = <Type, int>{};");
      expect(errors, contains(contains('IMP-R7')));
      expect(errors.where((e) => e.contains('IMP-R10')), hasLength(2));
      expect(errors.where((e) => e.contains('IMP-R9')), hasLength(2));
      expect(_check('const map = {Wheel: 1};'), contains(contains('IMP-R9')));
    });
    test('rejects asset or font declarations in pubspec', () {
      for (final field in ['assets', 'fonts']) {
        expect(
            checkImports(
                    libSources: {}, pubspec: "'flutter':\n  '$field': []\n")
                .single,
            contains('IMP-R12'));
        expect(
            checkImports(libSources: {}, pubspec: 'flutter:\n  $field: []\n')
                .single,
            contains('IMP-R12'));
        expect(
            checkImports(libSources: {}, pubspec: 'flutter: {$field: []}')
                .single,
            contains('IMP-R12'));
      }
      expect(
          checkImports(
              libSources: {},
              pubspec:
                  'dependencies:\n  flutter:\n    sdk: flutter\n# assets: []\n'),
          isEmpty);
    });
    test('restricts compat testing and external package dependencies', () {
      expect(
          _check("import '../capsule/a.dart';", path: 'lib/src/compat/a.dart')
              .single,
          contains('IMP-R3'));
      expect(
          _check("import '../slot/a.dart';", path: 'lib/src/testing/a.dart')
              .single,
          contains('IMP-R4'));
      expect(_check("import 'package:other/other.dart';").single,
          contains('IMP-R1'));
      expect(_check("import '../core/a.dart';", path: 'lib/src/compat/a.dart'),
          isEmpty);
    });
    test('restricts entry contents destinations and explicit show lists', () {
      for (final source in [
        "library; export 'src/grid/a.dart' show A;",
        "import 'dart:math';",
        'const x = 1;',
        "library; export 'src/wheel/a.dart';"
      ]) {
        expect(_check(source, path: 'lib/wheel.dart'),
            contains(contains('IMP-R5')));
      }
      expect(_check('/// 入口。\nlibrary;', path: 'lib/wheel.dart'), isEmpty);
    });
    test('rejects self package imports and conditional forbidden imports', () {
      expect(_check("import 'package:luckdraw/luckdraw.dart';"),
          contains(contains('IMP-R7')));
      expect(
          _check("import 'a.dart' if (dart.library.io) '../../wheel/a.dart';"),
          contains(contains('IMP-R1')));
    });
    test('enforces widgets exclusions with clock and render exceptions', () {
      const widgets = "import 'package:flutter/widgets.dart';";
      for (final directory in [
        'foundation',
        'geometry',
        'text',
        'easing',
        'motion',
        'picker'
      ]) {
        expect(_check(widgets, path: 'lib/src/core/$directory/a.dart').single,
            contains('IMP-R11'));
      }
      for (final gameDirectory in ['model', 'layout', 'motion']) {
        expect(
            _check(widgets, path: 'lib/src/wheel/$gameDirectory/a.dart').single,
            contains('IMP-R11'));
      }
      expect(_check(widgets, path: 'lib/src/core/motion/clock.dart'), isEmpty);
      expect(_check(widgets, path: 'lib/src/wheel/render/a.dart'), isEmpty);
    });
    test(
        'permits instance state local variables constants and reasoned exceptions',
        () {
      expect(
          _check(
              'const a = 1;\nclass C { final x = 1; static const y = 2; void f() { final z = 3; } }'),
          isEmpty);
      expect(
          _check(
              'final registry = Registry(); // imports:allow-global 显式平台边界\nType type(Object o) => o.runtimeType; // imports:allow-runtimeType 诊断用途'),
          isEmpty);
      expect(_check('final registry = Registry(); // imports:allow-global'),
          contains(contains('IMP-R8')));
    });
    test('string examples cannot grant exceptions and Type values are allowed',
        () {
      expect(_check('final text = "// imports:allow-global 示例";'),
          contains(contains('IMP-R8')));
      expect(_check('List<Type> types() => <Type>[];'), isEmpty);
      expect(
          _check(
              'Type type(Object o) => o.runtimeType; // imports:allow-runtimeType'),
          contains(contains('IMP-R9')));
    });
    test('ignores forbidden words inside comments and multiline strings', () {
      expect(_check('''
// runtimeType; part; final x = sideEffect();
const example = """import 'package:flutter/material.dart'; runtimeType;""";
/* import '../../wheel/a.dart'; */
'''), isEmpty);
    });
  });
}
