# json_annotation_lenient

**Lenient JSON conversion for `json_serializable`. Converters turn loose `int`/`double`/`num`/`bool`/`String`/`DateTime` values into the right type instead of throwing, and a build_runner builder fills in type-based defaults for missing fields.**

**English** · [简体中文](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/README.zh-CN.md)

[![pub.dev](https://img.shields.io/pub/v/json_annotation_lenient.svg)](https://pub.dev/packages/json_annotation_lenient)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/LICENSE)

---

## Why json_annotation_lenient?

Real APIs often send JSON with the wrong types: an `int` field arrives as `"42"`,
a `bool` field as `1`, and a timestamp is a string one day and an epoch number
the next. Stock `json_serializable` throws on all of these.
`json_annotation_lenient` has two separate tools for this:

1. **Converters**: six `JsonConverter` classes that accept the common alternate
   shapes of `int`/`double`/`num`/`bool`/`String`/`DateTime`. When the value is
   missing or `null`, each one returns a default.
2. **A build_runner builder**: `autoDefaultJsonBuilder` replaces the stock
   `json_serializable` builder. For every non-nullable field without an
   explicit `@JsonKey(defaultValue:)`, it fills in a default based on the
   type. For a class marked `@LenientConverter(...)`, it also rewrites the
   matching fields to use the converters above, so you don't have to put
   `@LenientIntConverter()` / `@LenientDoubleConverter()` / ... on every field.

You can use either one alone: the converters with the stock builder, or the
builder just for its auto-defaults, even on classes that never use
`@LenientConverter`.

---

## Installation

```yaml
dependencies:
  json_annotation_lenient: ^1.1.0
```

Add it as a **regular** dependency, not under `dev_dependencies`, even if your
project only uses it at build time. A `build.yaml` builder plugin has to be
resolvable from the project's regular dependency graph.

---

## Using the converters

```dart
import 'package:json_annotation/json_annotation.dart';
import 'package:json_annotation_lenient/json_annotation_lenient.dart';

part 'foo.g.dart';

@JsonSerializable()
class Foo {
  @LenientIntConverter()
  final int count;       // accepts 42, 42.0, or "42"

  @LenientBoolConverter()
  final bool active;     // accepts true, 1, "1", or "true"

  @LenientDateTimeConverter()
  final DateTime createdAt; // accepts ISO 8601, "2024/01/01 10:00:00", or an epoch number

  Foo(this.count, this.active, this.createdAt);
}
```

When the JSON value is missing or `null`, each converter returns a default:
`0` for int/num, `0.0` for double, `false` for bool, `''` for string, and the
Unix epoch for `DateTime`. You can change the default with the generated
`@JsonKey(defaultValue: ...)` where the type allows a const default.
`DateTime` doesn't, because it has no const constructor.

### `@LenientConverter` — enable leniency for a whole class

Instead of one converter annotation per field, mark the class. Every field of a
matching scalar type then goes through the corresponding converter (this needs
the `autoDefaultJsonBuilder`, see below):

```dart
@LenientConverter() // int/double/num/bool/String/DateTime are all enabled
@JsonSerializable()
class Foo {
  final int count;       // routed through LenientIntConverter
  final bool active;     // routed through LenientBoolConverter

  @LenientConverter(double: false)
  final double score;    // untouched: opted out for this field only

  @DisableLenient()
  final int strictId;    // untouched: opted out of everything

  Foo(this.count, this.active, this.score, this.strictId);
}
```

`@LenientConverter(dateTimeUtc: true)` (on a class or a field) decides how a
`DateTime` value without a timezone is interpreted. The full rules are in the
dartdoc of `LenientDateTimeConverter`.

---

## Using the builder

Add a `build.yaml` at your project root. It turns off the stock
`json_serializable` builder and turns on the replacement from `json_annotation_lenient`:

```yaml
targets:
  $default:
    builders:
      json_serializable:
        enabled: false
      json_annotation_lenient:auto_default:
        enabled: true
        options:
          explicit_to_json: true
```

This package's own `build.yaml` already declares the `auto_default` builder
(with `auto_apply: none`). Don't declare a `builders:` block in your own
`build.yaml`: it would register a second builder that writes the same `.g.dart`
files, and `build_runner` stops with a "conflicting outputs" error.

Then run `build_runner` as usual:

```
dart run build_runner build --delete-conflicting-outputs
```

The builder formats every generated `.g.dart` with the `dart_style` package. It
also reads `page_width` and `trailing_commas` from your project's
`analysis_options.yaml` if you set them (see `options.page_width` /
`options.trailing_commas` below for how this works and where it falls short).
Even so, the `dart_style` on pub.dev is a separate package from the formatter
inside your SDK's `dart format` command. Their versions can differ, for example
when the pub.dev release lags behind the formatter bundled with a newer Dart SDK.
Then the generated files may not match what a plain `dart format .` produces for
the rest of your project. If CI or a pre-commit hook runs
`dart format --set-exit-if-changed`, run a real format pass after generation so
the files match your SDK's formatter:

```
dart run build_runner build --delete-conflicting-outputs && dart format .
```

With this builder active:

- Every non-nullable field without an explicit `@JsonKey(defaultValue:)` falls
  back to a default based on its type (`''`, `0`, `0.0`, `false`, `const []`,
  `const {}`) instead of throwing when the key is missing or null.
- In a class annotated `@LenientConverter(...)`, fields of a matching type are
  routed through the corresponding `Lenient*Converter`. You don't need an
  annotation on each field.
- A field marked `@DisableLenient()` is left untouched by both of the above
  (plain stock `json_serializable` behavior).

`options` under `json_annotation_lenient:auto_default` are passed unchanged to
the underlying `JsonSerializableGenerator`. These are the same options the stock
`json_serializable` builder accepts (`explicit_to_json`, `field_rename`, ...).
The one exception is the `lenient:` section below, which the builder reads itself.

**`explicit_to_json` defaults to `true`** when you don't set it. Nested
`@JsonSerializable` fields need their own `.toJson()` call to serialize
correctly, and the stock default of `false` made every project turn it on by
hand. If you rely on the old implicit-`toJson` behavior, write
`explicit_to_json: false`. An explicit value, true or false, is always honored.

### `options.lenient` — project-wide leniency, no annotations needed

`@LenientConverter` works per class. To apply the same policy to the whole
project, configure it once in `build.yaml`:

```yaml
targets:
  $default:
    builders:
      json_annotation_lenient:auto_default:
        enabled: true
        options:
          explicit_to_json: true
          lenient:
            int:
              enabled: true
              defaultValue: 0
            double:
              enabled: true
              defaultValue: 0.0
            num:
              enabled: false
            bool:
              enabled: true
              defaultValue: false
            string:
              enabled: true
              defaultValue: ""
            dateTime:
              enabled: false
              utc: false
```

The six type keys map to the six converters (`int`, `double`, `num`, `bool`,
`string`, `dateTime`). Every key, including `enabled`, `defaultValue` and `utc`,
is optional. Only what you write is applied; everything else keeps the
annotation-driven behavior. Classes with no `@LenientConverter` or
`@DisableLenient` annotation are covered too, so a yml-only setup works,
**as long as the model file still imports**
`package:json_annotation_lenient/json_annotation_lenient.dart`. The rewrite
puts a bare `LenientIntConverter()` (or similar) into the generated part file.
A part file has no imports of its own and uses those of its library. Without
that import, the generated code fails with an undefined-name error (the builder
also logs a warning at build time when this happens).

**Precedence for `enabled`**, highest first:

1. The field's own `@LenientConverter(...)`. The yml can never override it.
2. The yml's `enabled:` for that type. It overrides the class-level annotation.
3. The class-level `@LenientConverter(...)`.

`@DisableLenient()` on a field still beats all three: the field stays exactly as
stock `json_serializable` generated it.

**Precedence for the fallback value**, highest first:

1. The field's `@JsonKey(defaultValue: ...)`.
2. The yml's `defaultValue:` for that type.
3. The built-in type default (`''`, `0`, `0.0`, `false`).

A yml `defaultValue:` also applies to plain auto-defaulted fields, not just
lenient ones. With `string.defaultValue: "n/a"`, a non-lenient `String` field
generates `json['x'] as String? ?? 'n/a'`.

**`dateTime` specifics:** it accepts `enabled:` and `utc:`. `utc:` overrides a
class-level `@LenientConverter(dateTimeUtc:)` but not a field-level one.
`defaultValue:` is not supported: `DateTime` has no const constructor, so there
is no Dart literal to generate. A `defaultValue:` under `dateTime` is ignored,
not treated as an error.

The whole section is parsed leniently: a malformed entry (wrong shape or wrong
value type) is skipped, and the build does not fail.

### `options.page_width` / `options.trailing_commas` — matching your formatter config

`dart_style`'s public `DartFormatter` class is the only thing this builder (or any
other `PartBuilder`-based generator) can call, and it never reads a project's
`analysis_options.yaml`. The code that does is private to `dart_style`'s own
CLI. So by default, generated `.g.dart` files always use `dart_style`'s built-in
page width (80) and trailing-comma policy (`automate`), whatever your project
configures.

To close that gap, the builder does two things:

1. It looks for `formatter: page_width:` / `trailing_commas:` in the nearest
   `analysis_options.yaml`, walking up from the directory where `build_runner`
   runs. This is a simplified implementation written from scratch. It follows
   at most one local (non-`package:`) `include:` path per file. If the
   `formatter:` section sits behind a `package:` include (for example a shared
   team lint package), it is not found.
2. It uses the values you set explicitly:

   ```yaml
   options:
     page_width: 100
     trailing_commas: preserve # or 'automate'
   ```

   A value set in `options:` always wins over auto-detection. Use it to override
   the detected values, or when your settings are behind a `package:` include.

---

## Known limitations

The auto-default rewrite only recognizes the code shapes `json_serializable`
generates for `bool`/`num`/`int`/`double`/`String`/`DateTime` scalars,
`List<T>`/`Set<T>` and `Map<K, V>`. A few field shapes are left untouched on
purpose. They behave exactly like stock `json_serializable` (they still throw on
a missing or null value) and are not silently broken:

- **Nested `@JsonSerializable` object fields** (`final Bar bar;` generating
  `Bar.fromJson(json['bar'] as Map<String, dynamic>)`) get no auto-default.
  If you need one, give the field its own `@JsonKey(defaultValue: ...)` or make
  it nullable.
- **`@JsonKey(fromJson: ..., toJson: ...)`** custom function fields, and any
  third-party `@JsonConverter` not from this package, pass through unchanged.
  The rewrite never touches a shape it doesn't recognize, so it can't generate
  code that fails to compile.
- **`enum` fields** get no made-up fallback value. Unlike `0`/`''`/`false` for
  scalars, no enum member is a generally correct default. For a missing or null
  key, use `@JsonKey(defaultValue: MyEnum.foo)` (works with stock
  `json_serializable`, no leniency needed). For a value that isn't one of the
  enum's cases, use `@JsonKey(unknownEnumValue: MyEnum.foo)`.

---

## Contributing

Issues and PRs are welcome.

- [Open an issue](https://github.com/icodejoo/dart-labs/issues)
- [Send a PR](https://github.com/icodejoo/dart-labs/pulls). Please run
  `dart analyze` and `dart test` (from `json_annotation_lenient/`) first.

## License

MIT — see [LICENSE](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/LICENSE).
