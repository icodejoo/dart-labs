# Changelog

## 1.2.0

### Added
- New `options.page_width` / `options.trailing_commas` for
  `json_annotation_lenient:auto_default` — `dart_style`'s public
  `DartFormatter` API never reads a project's `analysis_options.yaml`
  `formatter:` section at all (that logic is private to `dart_style`'s own
  CLI), so generated `.g.dart` previously always used `dart_style`'s
  built-in defaults regardless of your project's configured page width or
  trailing-comma style. Set these explicitly to match.
- The builder now also auto-detects `formatter: page_width:`/
  `trailing_commas:` from the nearest `analysis_options.yaml` (walking up
  from the project root) when `options.page_width`/`options.trailing_commas`
  aren't set explicitly — a from-scratch, simplified reimplementation that
  follows a single local (non-`package:`) `include:` path per file. An
  `analysis_options.yaml` whose `formatter:` section lives behind a
  `package:` include isn't picked up; use the explicit options in that case.
  An explicit `options:` value always wins over auto-detection.

## 1.1.0

### Changed
- **Behavior change:** `autoDefaultJsonBuilder` now defaults `explicit_to_json`
  to `true` when a consuming project's `build.yaml` doesn't set it at all
  (nested `@JsonSerializable` fields need it to serialize correctly almost
  all the time, and the stock `json_serializable` default of `false` meant
  every consumer had to opt in by hand). If your project relies on the old
  implicit-`toJson` behavior for nested objects, add `explicit_to_json:
  false` explicitly under this builder's `options:` — an explicit value in
  either direction is always honored; this only fills the gap when the key
  is absent.

## 1.0.0

### Fixed
- `LenientBoolConverter` now accepts numeric `double` values and normalizes
  string input case-insensitively (`"TRUE"`, `"Yes"`, ...); an unrecognized
  string now throws instead of silently returning `false`, matching every
  other converter.
- `LenientIntConverter` now accepts decimal strings (`"42.5"`) via a
  `double` fallback, and throws instead of producing a bogus `int` for
  non-finite (`NaN`/`Infinity`) input.
- `LenientDateTimeConverter` no longer misreads an 8-digit `yyyyMMdd` string
  (e.g. `"20240101"`) as an epoch-seconds timestamp; out-of-range epoch
  values now throw instead of raising an unrelated `RangeError`.
- All converters raise English `FormatException`s naming the offending
  value's runtime type, instead of a Chinese-only message with no type info.
- The `options.lenient` yml no longer accepts a `double` literal for an
  `int` default (it produced code that failed to compile); `double`
  defaults are now always rendered with an explicit `.0`.
- The builder now warns at build time when `@LenientConverter`/
  `options.lenient` is active on a library that doesn't import
  `package:json_annotation_lenient/json_annotation_lenient.dart` (a
  yml-only setup needs that import; without it the generated code fails
  with an undefined-name error) and skips the converter rewrite for that
  library rather than emitting code that won't compile.
- `@DisableLenient()` / a field-level `@LenientConverter(...)` on an
  *inherited* field is now honored — previously only the class's own
  fields were scanned.
- The `json['x'] == null ? d : const Converter().fromJson(json['x'])` fold
  now only applies to our own `Lenient*Converter` classes, so it no longer
  rewrites a third-party `JsonConverter` into a call shape it may not
  support.
- `Set<T>` fields are now covered by the same auto-default rewrite as
  `List<T>` (`.toSet()` alongside `.toList()`).

### Performance
- The generated-source rewrite now applies all edits in a single
  `StringBuffer` pass instead of repeated `String.replaceRange` calls
  (previously O(edits × file size) per build).

### Docs
- Removed a `builders:` block from both READMEs' `build.yaml` example — it
  registered a second builder that collided with this package's own
  (`auto_apply: none`) declaration and would fail `build_runner` with a
  "conflicting outputs" error.
- Fixed stale `lib/tool/build/...` / `lib/utils/...` path references in
  dartdoc comments (pre-restructuring paths that don't exist in this
  package).
- `environment.sdk` lowered floor corrected to `^3.11.0` to match what
  `analyzer`/`build`/`dart_style` actually require — the previous `^3.5.0`
  advertised a compatibility this package couldn't deliver.

## 0.2.0

### Builder
- New `options.lenient` section in `build.yaml`: turn leniency on/off per
  scalar type (`int`/`double`/`num`/`bool`/`string`/`dateTime`) project-wide,
  and override each type's fallback default value — no annotation needed on
  the model classes at all.

  ```yaml
  options:
    lenient:
      int:
        enabled: true
        defaultValue: 0
      string:
        enabled: true
        defaultValue: ""
      dateTime:
        enabled: false
        utc: false
  ```

  Every key is optional; only what you write is applied. Precedence, highest
  first: a field's own `@LenientConverter(...)` → the yml `enabled:` → the
  class-level `@LenientConverter(...)`. `@DisableLenient()` still opts a field
  out of everything. For default values: a field's `@JsonKey(defaultValue:)` →
  the yml `defaultValue:` → the built-in type default.
- `dateTime` accepts `enabled:`/`utc:` but not `defaultValue:` (`DateTime` has
  no const constructor); a `defaultValue:` written there is ignored rather
  than an error. Malformed entries anywhere in the `lenient:` section are
  skipped instead of failing the build.
- A yml `defaultValue:` also replaces the plain auto-default injected into
  non-lenient fields (`json['x'] as String? ?? '<yours>'`).
- A class with no `@LenientConverter`/`@DisableLenient` annotation at all is
  now still processed, so a yml-only setup works.

## 0.1.0

Initial release.

Extracted from an app's internal `json_serializable` tooling into a
standalone package.

### Converters
- `LenientIntConverter` / `LenientDoubleConverter` / `LenientNumConverter` /
  `LenientBoolConverter` / `LenientStringConverter` — accept a small set of
  common alternate JSON shapes (numeric strings, `"true"`/`"1"`, mismatched
  numeric subtypes, ...) instead of throwing, with a per-field fallback
  default.
- `LenientDateTimeConverter` — accepts ISO 8601 strings, a few non-standard
  string formats (`/` date separator, space instead of `T`), and epoch
  numbers whose unit (seconds/milliseconds/microseconds) is guessed from
  magnitude; `dateTimeUtc` controls how timezone-less values are interpreted.
- `@LenientConverter(...)` class-level annotation to turn on leniency for
  every field of a given scalar type at once; `@DisableLenient()` to opt a
  single field out entirely.

### Builder
- `autoDefaultJsonBuilder` (`package:json_annotation_lenient/builder.dart`) — a
  build_runner builder that replaces the stock `json_serializable` builder.
  Auto-fills type-based defaults (`''`, `0`, `0.0`, `false`, `const []`,
  `const {}`) for non-nullable fields with no explicit
  `@JsonKey(defaultValue:)`, and rewrites matching fields to route through
  the `Lenient*Converter` classes when a class/field opts in via
  `@LenientConverter`.
