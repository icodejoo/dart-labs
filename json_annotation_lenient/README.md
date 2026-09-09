# json_annotation_lenient

**Lenient JSON conversion for `json_serializable` — coerce loose `int`/`double`/`num`/`bool`/`String`/`DateTime` values instead of throwing, plus a drop-in build_runner builder that auto-fills type-based defaults for missing fields.**

**English** · [简体中文](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/README.zh.md)

[![pub.dev](https://img.shields.io/pub/v/json_annotation_lenient.svg)](https://pub.dev/packages/json_annotation_lenient)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/LICENSE)

---

## Why json_annotation_lenient?

Real-world APIs rarely send perfectly-typed JSON — an `int` field shows up as
`"42"`, a `bool` field shows up as `1`, a timestamp shows up as a string one
day and an epoch number the next. Stock `json_serializable` throws on all of
these. `json_annotation_lenient` gives you two independent tools to deal with it:

1. **Converters** — six `JsonConverter` implementations that coerce common
   alternate shapes for `int`/`double`/`num`/`bool`/`String`/`DateTime`, each
   falling back to a sensible default when the value is missing or `null`.
2. **A build_runner builder** — `autoDefaultJsonBuilder`, a full replacement
   for the stock `json_serializable` builder. It auto-fills type-based
   defaults for any non-nullable field with no explicit
   `@JsonKey(defaultValue:)`, and — for a class marked
   `@LenientConverter(...)` — rewrites its matching fields to route through
   the converters above automatically, so you don't have to stack a
   `@LenientIntConverter()` / `@LenientDoubleConverter()` / ... annotation on
   every single field.

Both pieces work independently: use just the converters with the stock
builder, or pull in the builder for its auto-defaults even on classes that
never use `@LenientConverter`.

---

## Installation

```yaml
dependencies:
  json_annotation_lenient: ^0.3.0
```

`json_annotation_lenient` is designed to be a **regular** dependency (not
`dev_dependencies`) even in a project that only uses it at build time — a
`build.yaml` builder plugin has to be resolvable from the depending project's
regular dependency graph.

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

Each converter falls back to a default value when the JSON value is missing
or `null` — `0` for int/num, `0.0` for double, `false` for bool, `''` for
string, and the Unix epoch for `DateTime` (override via the generated
`@JsonKey(defaultValue: ...)` where the type allows a const default —
`DateTime` doesn't, since it has no const constructor).

### `@LenientConverter` — enable leniency for a whole class

Rather than stacking one converter annotation per field, mark the class
itself and every field of a matching scalar type gets routed through the
corresponding converter automatically (this requires the
`autoDefaultJsonBuilder`, see below):

```dart
@LenientConverter() // int/double/num/bool/String/DateTime all enabled
@JsonSerializable()
class Foo {
  final int count;       // routed through LenientIntConverter
  final bool active;     // routed through LenientBoolConverter

  @LenientConverter(double: false)
  final double score;    // untouched — opted out just for this field

  @DisableLenient()
  final int strictId;    // untouched — opts out of everything

  Foo(this.count, this.active, this.score, this.strictId);
}
```

`@LenientConverter(dateTimeUtc: true)` (class- or field-level) controls how a
timezone-less `DateTime` value is interpreted — see the dartdoc on
`LenientDateTimeConverter` for the full rules.

---

## Using the builder

Add a `build.yaml` at your project root that disables the stock
`json_serializable` builder and enables `json_annotation_lenient`'s replacement instead:

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

The `auto_default` builder itself is already declared by this package's own
`build.yaml` (with `auto_apply: none`) — don't redeclare a `builders:` block
in your own `build.yaml`, it would register a second builder writing the same
`.g.dart` output and `build_runner` will refuse to run with a
"conflicting outputs" error.

Then run `build_runner` as usual:

```
dart run build_runner build --delete-conflicting-outputs
```

With this builder active:

- Every non-nullable field with no explicit `@JsonKey(defaultValue:)` falls
  back to a type-based default (`''`, `0`, `0.0`, `false`, `const []`,
  `const {}`) instead of throwing on a missing/null value.
- A class annotated `@LenientConverter(...)` gets its matching-type fields
  routed through the corresponding `Lenient*Converter` — no per-field
  annotation needed.
- A field marked `@DisableLenient()` is left completely untouched by both of
  the above (pure stock `json_serializable` behavior).

`options` under `json_annotation_lenient:auto_default` are passed straight through to
the underlying `JsonSerializableGenerator` (`explicit_to_json`,
`field_rename`, ... — the same options the stock `json_serializable` builder
accepts) — except for the `lenient:` section below, which the builder consumes
itself.

### `options.lenient` — project-wide leniency, no annotations needed

`@LenientConverter` is per-class. If you want the same policy across the whole
project, configure it once in `build.yaml` instead:

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
`string`, `dateTime`). Every key — including `enabled`, `defaultValue` and
`utc` — is optional: only what you actually write is applied, and everything
else keeps the annotation-driven behavior. Classes with no
`@LenientConverter`/`@DisableLenient` annotation at all are covered too, so a
yml-only setup works — **as long as the model file itself still imports**
`package:json_annotation_lenient/json_annotation_lenient.dart`. The rewrite
emits a bare `LenientIntConverter()`/etc. reference into the generated part
file, which has no imports of its own and inherits the library's; without
that import the generated code fails with an undefined-name error (the
builder also logs a build-time warning when this happens).

**Precedence for `enabled`**, highest first:

1. The field's own `@LenientConverter(...)` — the yml can never override it.
2. The yml's `enabled:` for that type — overrides the class-level annotation.
3. The class-level `@LenientConverter(...)`.

`@DisableLenient()` on a field still trumps all three (the field is left
exactly as stock `json_serializable` generated it).

**Precedence for the fallback value**, highest first:

1. The field's `@JsonKey(defaultValue: ...)`.
2. The yml's `defaultValue:` for that type.
3. The built-in type default (`''`, `0`, `0.0`, `false`).

A yml `defaultValue:` applies to plain auto-defaulted fields too, not just
lenient ones — with `string.defaultValue: "n/a"` a non-lenient `String` field
generates `json['x'] as String? ?? 'n/a'`.

**`dateTime` specifics:** it accepts `enabled:` and `utc:` (the latter
overrides a class-level `@LenientConverter(dateTimeUtc:)`, but not a
field-level one), and does *not* support `defaultValue:` — `DateTime` has no
const constructor, so there's no Dart literal to emit. A `defaultValue:`
written under `dateTime` is ignored rather than treated as an error.

The whole section is parsed leniently: a malformed entry (wrong shape, wrong
value type) is skipped rather than failing the build.

---

## Known limitations

The auto-default rewrite only recognizes the specific code shapes
`json_serializable` emits for `bool`/`num`/`int`/`double`/`String`/`DateTime`
scalars, `List<T>`/`Set<T>`, and `Map<K, V>`. A few field shapes are
deliberately left untouched — they behave exactly like stock
`json_serializable` (i.e. still throw on a missing/null value), not silently
broken:

- **Nested `@JsonSerializable` object fields** (`final Bar bar;` generating
  `Bar.fromJson(json['bar'] as Map<String, dynamic>)`) get no auto-default.
  Give the field its own `@JsonKey(defaultValue: ...)`, or make it nullable,
  if you need one.
- **`@JsonKey(fromJson: ..., toJson: ...)`** custom function fields and any
  third-party `@JsonConverter` not from this package pass straight through
  unmodified — the rewrite never touches a shape it doesn't explicitly
  recognize, precisely so it can't emit code that fails to compile.
- **`enum` fields** are not given an invented fallback value — there's no
  generically "correct" default enum member the way `0`/`''`/`false` are for
  scalars. Use `@JsonKey(defaultValue: MyEnum.foo)` (works out of the box
  with stock `json_serializable`, no leniency needed) for a missing/null
  key, and/or `@JsonKey(unknownEnumValue: MyEnum.foo)` for a value that
  isn't one of the enum's cases.

---

## Contributing

Issues and PRs are welcome.

- 🐛 [Open an issue](https://github.com/icodejoo/dart-labs/issues)
- 🔧 [Send a PR](https://github.com/icodejoo/dart-labs/pulls) — please run
  `dart analyze` and `dart test` (from `json_annotation_lenient/`) before submitting.

## License

MIT — see [LICENSE](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/LICENSE).
