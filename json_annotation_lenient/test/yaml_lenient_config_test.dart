// Exercises the `options.lenient` build.yaml config and its precedence
// against class-/field-level annotations. Imports `src/` directly to reach
// `debugApplyLenientRewrite`, the test-only hook into the otherwise
// library-private rewrite pipeline.
//
// 覆盖 build.yaml 的 `options.lenient` 配置，以及它和类级/字段级注解之间的
// 优先级。直接 import `src/` 是为了拿到 `debugApplyLenientRewrite`——那个
// 通往库私有改写流程的测试专用入口。

import 'package:json_annotation_lenient/src/auto_default_builder.dart';
import 'package:test/test.dart';

/// A stand-in for what json_serializable emits for a class with one field of
/// each scalar shape we care about.
///
/// 模拟 json_serializable 对每种关心的标量形状生成的代码。
String sourceFor(Map<String, String> fields) {
  final args = fields.entries.map((e) => '  ${e.key}: ${e.value},').join('\n');
  return 'Foo _\$FooFromJson(Map<String, dynamic> json) => Foo(\n$args\n);\n';
}

const intField = "(json['count'] as num).toInt()";
const doubleField = "(json['score'] as num).toDouble()";
const boolField = "json['active'] as bool";
const stringField = "json['label'] as String";
const dateTimeField = "DateTime.parse(json['createdAt'] as String)";

void main() {
  group('yml lenient config — enabling', () {
    test('enables a type for a class with no annotation at all', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'count': intField}),
        lenientOptions: {
          'int': {'enabled': true},
        },
        classAnnotated: false,
      );

      expect(
        out,
        contains("const LenientIntConverter().fromJson(json['count'])"),
      );
    });

    test(
      'leaves a type alone when the yml disables it and nothing else opts in',
      () {
        final out = debugApplyLenientRewrite(
          sourceFor({'count': intField}),
          lenientOptions: {
            'int': {'enabled': false},
          },
          classAnnotated: false,
        );

        expect(out, isNot(contains('LenientIntConverter')));
        expect(out, contains("(json['count'] as num?)?.toInt() ?? 0"));
      },
    );

    test('yml overrides a class-level annotation that turned the type off', () {
      // @LenientConverter(double: false) on the class, yml says double: true.
      final out = debugApplyLenientRewrite(
        sourceFor({'score': doubleField}),
        lenientOptions: {
          'double': {'enabled': true},
        },
        classEnabledTypes: const {'int', 'num', 'bool', 'String', 'DateTime'},
      );

      expect(
        out,
        contains("const LenientDoubleConverter().fromJson(json['score'])"),
      );
    });

    test('yml overrides a class-level annotation that turned the type on', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'score': doubleField}),
        lenientOptions: {
          'double': {'enabled': false},
        },
        classEnabledTypes: const {'double'},
      );

      expect(out, isNot(contains('LenientDoubleConverter')));
    });

    test('a field-level annotation beats the yml', () {
      // yml enables int project-wide, but @LenientConverter(int: false) sits
      // on the field itself — the field wins.
      final out = debugApplyLenientRewrite(
        sourceFor({'count': intField}),
        lenientOptions: {
          'int': {'enabled': true},
        },
        fieldOverrides: const {
          'count': {'double', 'num', 'bool', 'String', 'DateTime'},
        },
      );

      expect(out, isNot(contains('LenientIntConverter')));
      expect(out, contains("(json['count'] as num?)?.toInt() ?? 0"));
    });

    test('a field-level annotation enables a type the yml turned off', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'count': intField}),
        lenientOptions: {
          'int': {'enabled': false},
        },
        fieldOverrides: const {
          'count': {'int'},
        },
      );

      expect(
        out,
        contains("const LenientIntConverter().fromJson(json['count'])"),
      );
    });

    test('@DisableLenient still wins over everything', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'count': intField}),
        lenientOptions: {
          'int': {'enabled': true, 'defaultValue': 5},
        },
        disabledFields: const {'count'},
      );

      // Nothing at all to rewrite -> null, source untouched.
      expect(out, isNull);
    });

    test(
      'a class-level annotation still applies to types the yml never mentions',
      () {
        final out = debugApplyLenientRewrite(
          sourceFor({'active': boolField}),
          lenientOptions: {
            'int': {'enabled': true},
          },
          classEnabledTypes: const {'bool'},
        );

        expect(
          out,
          contains("const LenientBoolConverter().fromJson(json['active'])"),
        );
      },
    );
  });

  group('yml lenient config — default values', () {
    test('yml defaultValue is threaded into the converter call', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'count': intField}),
        lenientOptions: {
          'int': {'enabled': true, 'defaultValue': 5},
        },
        classAnnotated: false,
      );

      expect(
        out,
        contains("const LenientIntConverter().fromJson(json['count'], 5)"),
      );
    });

    test('a field @JsonKey(defaultValue:) beats the yml default', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'count': "(json['count'] as num?)?.toInt() ?? 9"}),
        lenientOptions: {
          'int': {'enabled': true, 'defaultValue': 5},
        },
        classAnnotated: false,
      );

      expect(
        out,
        contains("const LenientIntConverter().fromJson(json['count'], 9)"),
      );
      expect(out, isNot(contains(', 5)')));
    });

    test(
      'yml default also replaces the plain auto-default when leniency is off',
      () {
        final out = debugApplyLenientRewrite(
          sourceFor({
            'count': intField,
            'score': doubleField,
            'label': stringField,
          }),
          lenientOptions: {
            'int': {'defaultValue': 7},
            'double': {'defaultValue': 1.5},
            'string': {'defaultValue': 'n/a'},
          },
          classAnnotated: false,
        );

        expect(out, contains("(json['count'] as num?)?.toInt() ?? 7"));
        expect(out, contains("(json['score'] as num?)?.toDouble() ?? 1.5"));
        expect(out, contains("json['label'] as String? ?? 'n/a'"));
      },
    );

    test('string defaults are escaped into a valid Dart literal', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'label': stringField}),
        lenientOptions: {
          'string': {'defaultValue': r"it's a \ $tricky one"},
        },
        classAnnotated: false,
      );

      expect(
        out,
        contains(r"json['label'] as String? ?? 'it\'s a \\ \$tricky one'"),
      );
    });

    test('bool default renders as a bool literal', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'active': boolField}),
        lenientOptions: {
          'bool': {'enabled': true, 'defaultValue': true},
        },
        classAnnotated: false,
      );

      expect(
        out,
        contains("const LenientBoolConverter().fromJson(json['active'], true)"),
      );
    });

    test('Map keeps its const {} fallback — the yml has no Map key', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'extras': "Map<String, int>.from(json['extras'] as Map)"}),
        lenientOptions: {
          'string': {'defaultValue': 'nope'},
        },
        classAnnotated: false,
      );

      expect(
        out,
        contains("Map<String, int>.from(json['extras'] as Map? ?? const {})"),
      );
    });
  });

  group('yml lenient config — dateTime', () {
    test('defaultValue on dateTime is ignored, not an error', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'createdAt': dateTimeField}),
        lenientOptions: {
          'dateTime': {'enabled': true, 'defaultValue': '2024-01-01'},
        },
        classAnnotated: false,
      );

      expect(
        out,
        contains(
          "const LenientDateTimeConverter(dateTimeUtc: false)"
          ".fromJson(json['createdAt'])",
        ),
      );
      expect(out, isNot(contains('2024-01-01')));
    });

    test('yml utc flag is threaded into the converter constructor', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'createdAt': dateTimeField}),
        lenientOptions: {
          'dateTime': {'enabled': true, 'utc': true},
        },
        classAnnotated: false,
      );

      expect(out, contains('LenientDateTimeConverter(dateTimeUtc: true)'));
    });

    test(
      'yml utc overrides the class annotation but not a field annotation',
      () {
        final classLevel = debugApplyLenientRewrite(
          sourceFor({'createdAt': dateTimeField}),
          lenientOptions: {
            'dateTime': {'enabled': true, 'utc': true},
          },
          classEnabledTypes: const {'DateTime'},
        );
        expect(classLevel, contains('dateTimeUtc: true'));

        final fieldLevel = debugApplyLenientRewrite(
          sourceFor({'createdAt': dateTimeField}),
          lenientOptions: {
            'dateTime': {'enabled': true, 'utc': true},
          },
          fieldOverrides: const {
            'createdAt': {'DateTime'},
          },
          fieldDateTimeUtcOverrides: const {'createdAt': false},
        );
        expect(fieldLevel, contains('dateTimeUtc: false'));
      },
    );
  });

  group('yml lenient config — lenient parsing', () {
    test('a null / absent lenient section changes nothing', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'count': intField}),
        classAnnotated: false,
      );

      expect(out, contains("(json['count'] as num?)?.toInt() ?? 0"));
    });

    test('unknown type keys and non-map sections are skipped', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'count': intField}),
        lenientOptions: {
          'nope': {'enabled': true},
          'double': 'not-a-map',
          'int': {'enabled': true},
        },
        classAnnotated: false,
      );

      expect(
        out,
        contains("const LenientIntConverter().fromJson(json['count'])"),
      );
    });

    test('a mistyped enabled/defaultValue is skipped rather than thrown', () {
      final out = debugApplyLenientRewrite(
        sourceFor({'count': intField, 'label': stringField}),
        lenientOptions: {
          // enabled must be a bool, defaultValue must match the type
          'int': {'enabled': 'yes', 'defaultValue': 'five'},
          'string': {'enabled': true, 'defaultValue': 42},
        },
        classAnnotated: false,
      );

      expect(out, contains("(json['count'] as num?)?.toInt() ?? 0"));
      // string leniency still turned on, but with no yml default
      expect(
        out,
        contains("const LenientStringConverter().fromJson(json['label'])"),
      );
    });
  });
}
