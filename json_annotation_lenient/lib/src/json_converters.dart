import 'package:json_annotation/json_annotation.dart';

/// Class-level marker that turns on `Lenient*Converter`-style value
/// coercion (see [LenientIntConverter] etc.) for every field of the enabled
/// types, without stacking a separate `@LenientIntConverter()` /
/// `@LenientDoubleConverter()` / ... annotation per type.
///
/// This class does nothing at runtime by itself — it's read at build time
/// by `lib/src/auto_default_builder.dart`, which rewrites the
/// generated `fromJson` code to route matching fields through the
/// corresponding converter. A field can opt out entirely with
/// `@DisableLenient()`.
///
/// 类级别标记：给启用的类型统一打开 `Lenient*Converter` 那种值容错转换（见
/// [LenientIntConverter] 等），不用再为每个类型单独叠一个
/// `@LenientIntConverter()`/`@LenientDoubleConverter()`/...。
///
/// 这个类本身在运行时什么都不做——由
/// `lib/src/auto_default_builder.dart` 在编译期读取，把匹配类型的字段
/// 生成代码改写成走对应 converter。单个字段可以用 `@DisableLenient()` 完全退出。
///
/// All four types default to `true` — `@LenientConverter()` with no
/// arguments enables leniency for every `int`/`double`/`num`/`bool` field on
/// the class. Pass `false` for a type to opt it out class-wide, or use
/// `@DisableLenient()`/a field-level `@LenientConverter(...)` for per-field
/// control (see [DisableLenient]).
///
/// 四个开关默认都是 `true`——不传参数的 `@LenientConverter()` 就是给这个类里
/// 所有 `int`/`double`/`num`/`bool` 字段都打开宽松转换。某个类型传 `false`
/// 可以整类关掉；要精确到单个字段，用 `@DisableLenient()` 或者直接在字段上写
/// `@LenientConverter(...)`（见 [DisableLenient]）。
///
/// Example:
/// ```dart
/// @LenientConverter() // int/double/num/bool all enabled
/// @JsonSerializable()
/// class Foo {
///   final int count;       // routed through LenientIntConverter
///   final bool active;     // routed through LenientBoolConverter
///   @LenientConverter(double: false)
///   final double score;    // untouched — opted out just for this field
///   @DisableLenient()
///   final int strictId;    // untouched — opts out of everything
///   Foo(this.count, this.active, this.score, this.strictId);
/// }
/// ```
class LenientConverter {
  final bool intEnabled;
  final bool doubleEnabled;
  final bool numEnabled;
  final bool boolEnabled;
  final bool stringEnabled;
  final bool dateTimeEnabled;

  /// Whether [LenientDateTimeConverter] should treat a timezone-less value
  /// (an epoch number, or a string with no `Z`/offset suffix) as UTC rather
  /// than local time. Defaults to `false` to match stock `DateTime.parse`.
  ///
  /// [LenientDateTimeConverter] 在遇到没有时区信息的值（纯数值时间戳，或者没有
  /// `Z`/偏移量后缀的字符串）时，是否按 UTC 解释而不是本地时间。默认 `false`，
  /// 和官方 `DateTime.parse` 的行为保持一致。
  final bool dateTimeUtc;

  const LenientConverter({
    bool int = true,
    bool double = true,
    bool num = true,
    bool bool = true,
    bool string = true,
    bool dateTime = true,
    this.dateTimeUtc = false,
  }) : intEnabled = int,
       doubleEnabled = double,
       numEnabled = num,
       boolEnabled = bool,
       stringEnabled = string,
       dateTimeEnabled = dateTime;
}

/// Field-level marker: opts this field out of the enclosing class's
/// `@LenientConverter(...)` entirely. The field behaves exactly like stock
/// `json_serializable` — strict cast, no auto default, throws on a
/// missing/null value.
///
/// 字段级标记：让这个字段完全退出所在类的 `@LenientConverter(...)` 配置。
/// 该字段的行为跟纯官方 `json_serializable` 完全一致——严格 cast、不自动兜底，
/// 缺失/null 时直接抛异常。
class DisableLenient {
  const DisableLenient();
}

/// Lenient int converter: accepts int, double, or numeric string from JSON;
/// missing/null values fall back to [defaultValue].
///
/// 宽松 int 转换器：兼容 JSON 中的 int、double 或数字字符串；缺失/null 时
/// 兜底为 [defaultValue]。
///
/// Example:
/// ```dart
/// @LenientIntConverter()
/// @JsonSerializable()
/// class Foo {
///   final int count;
///   @JsonKey(defaultValue: 1) // per-field override of the 0 class default
///   final int retryCount;
///   Foo(this.count, this.retryCount);
/// }
/// ```
class LenientIntConverter implements JsonConverter<int, dynamic> {
  const LenientIntConverter();

  @override
  int fromJson(dynamic json, [int defaultValue = 0]) => switch (json) {
    null => defaultValue,
    int v => v,
    double v => _finiteDoubleToInt(v, json),
    String v =>
      int.tryParse(v) ??
          _finiteDoubleToInt(
            double.tryParse(v) ?? _throwInt(json),
            json,
          ),
    _ => _throwInt(json),
  };

  static int _finiteDoubleToInt(double v, dynamic original) {
    if (!v.isFinite) {
      throw FormatException(
        'Cannot convert to int: not a finite number (${v.runtimeType}: $original)',
      );
    }
    return v.toInt();
  }

  static Never _throwInt(dynamic json) => throw FormatException(
    'Cannot convert to int: unsupported value (${json.runtimeType}: $json)',
  );

  @override
  dynamic toJson(int object) => object;
}

/// Lenient num converter: accepts int, double, or numeric string from JSON,
/// keeping whichever numeric subtype the value actually is (unlike
/// [LenientIntConverter]/[LenientDoubleConverter], which coerce); missing/null
/// values fall back to [defaultValue].
///
/// 宽松 num 转换器：兼容 JSON 中的 int、double 或数字字符串，保留数值本身的
/// 具体子类型（不像 [LenientIntConverter]/[LenientDoubleConverter] 那样强制
/// 转换）；缺失/null 时兜底为 [defaultValue]。
///
/// Example:
/// ```dart
/// @LenientNumConverter()
/// @JsonSerializable()
/// class Foo {
///   final num amount;
///   @JsonKey(defaultValue: 1) // per-field override of the 0 class default
///   final num weight;
///   Foo(this.amount, this.weight);
/// }
/// ```
class LenientNumConverter implements JsonConverter<num, dynamic> {
  const LenientNumConverter();

  @override
  num fromJson(dynamic json, [num defaultValue = 0]) => switch (json) {
    null => defaultValue,
    num v => v,
    String v =>
      num.tryParse(v) ??
          (throw FormatException(
            'Cannot convert to num: unsupported string ($v)',
          )),
    _ => throw FormatException(
      'Cannot convert to num: unsupported value (${json.runtimeType}: $json)',
    ),
  };

  @override
  dynamic toJson(num object) => object;
}

/// Lenient double converter: accepts int, double, or numeric string from
/// JSON; missing/null values fall back to [defaultValue].
///
/// 宽松 double 转换器：兼容 JSON 中的 int、double 或数字字符串；缺失/null 时
/// 兜底为 [defaultValue]。
///
/// Example:
/// ```dart
/// @LenientDoubleConverter()
/// @JsonSerializable()
/// class Foo {
///   final double score;
///   @JsonKey(defaultValue: 1.5) // per-field override of the 0.0 class default
///   final double weight;
///   Foo(this.score, this.weight);
/// }
/// ```
class LenientDoubleConverter implements JsonConverter<double, dynamic> {
  const LenientDoubleConverter();

  @override
  double fromJson(dynamic json, [double defaultValue = 0.0]) => switch (json) {
    null => defaultValue,
    double v => v,
    int v => v.toDouble(),
    String v =>
      double.tryParse(v) ??
          (throw FormatException(
            'Cannot convert to double: unsupported string ($v)',
          )),
    _ => throw FormatException(
      'Cannot convert to double: unsupported value (${json.runtimeType}: $json)',
    ),
  };

  @override
  dynamic toJson(double object) => object;
}

/// Lenient bool converter: accepts bool, numeric, or string ("true"/"1")
/// from JSON; missing/null values fall back to [defaultValue].
///
/// 宽松 bool 转换器：兼容 JSON 中的 bool、数字或字符串（"true"/"1"）；缺失/null
/// 时兜底为 [defaultValue]。
///
/// Example:
/// ```dart
/// @LenientBoolConverter()
/// @JsonSerializable()
/// class Foo {
///   final bool active;
///   @JsonKey(defaultValue: true) // per-field override of the false class default
///   final bool enabled;
///   Foo(this.active, this.enabled);
/// }
/// ```
class LenientBoolConverter implements JsonConverter<bool, dynamic> {
  const LenientBoolConverter();

  @override
  bool fromJson(dynamic json, [bool defaultValue = false]) => switch (json) {
    null => defaultValue,
    bool v => v,
    num v => v != 0,
    String v => switch (v.trim().toLowerCase()) {
      'true' || '1' || 'yes' || 'y' || 'on' => true,
      'false' || '0' || 'no' || 'n' || 'off' || '' => false,
      _ => throw FormatException('Cannot convert to bool: unsupported string ($v)'),
    },
    _ => throw FormatException(
      'Cannot convert to bool: unsupported value (${json.runtimeType}: $json)',
    ),
  };

  @override
  dynamic toJson(bool object) => object;
}

/// Lenient string converter: accepts a JSON string as-is, or stringifies a
/// number/bool; missing/null values fall back to [defaultValue].
///
/// 宽松 string 转换器：JSON 里本来就是字符串就直接收，是数字/布尔就转成字符串；
/// 缺失/null 时兜底为 [defaultValue]。
///
/// Example:
/// ```dart
/// @LenientStringConverter()
/// @JsonSerializable()
/// class Foo {
///   final String gameId;
///   @JsonKey(defaultValue: 'n/a') // per-field override of the '' class default
///   final String label;
///   Foo(this.gameId, this.label);
/// }
/// ```
class LenientStringConverter implements JsonConverter<String, dynamic> {
  const LenientStringConverter();

  @override
  String fromJson(dynamic json, [String defaultValue = '']) => switch (json) {
    null => defaultValue,
    String v => v,
    num v => v.toString(),
    bool v => v.toString(),
    _ => throw FormatException(
      'Cannot convert to String: unsupported value (${json.runtimeType}: $json)',
    ),
  };

  @override
  dynamic toJson(String object) => object;
}

/// Lenient DateTime converter: accepts an ISO 8601 string, a handful of
/// non-standard string formats (see below), or an epoch number whose unit
/// (seconds/milliseconds/microseconds) is guessed from its magnitude;
/// missing/null values fall back to [defaultValue] (the Unix epoch if not
/// given — the closest thing `DateTime` has to a "zero" value).
///
/// 宽松 DateTime 转换器：兼容 ISO 8601 字符串、几种常见的不规范字符串格式（见下）、
/// 或者一个按数值大小猜单位（秒/毫秒/微秒）的数值时间戳；缺失/null 时兜底为
/// [defaultValue]（不传的话是 Unix 纪元——`DateTime` 里最接近"零值"的东西）。
///
/// Epoch numbers (`int`/`double`/`num`, or a numeric string) are classified
/// by digit count, the same heuristic dayjs uses: `>= 1e14` is microseconds,
/// `>= 1e11` is milliseconds, anything smaller is seconds.
///
/// 数值时间戳（`int`/`double`/`num`，或者纯数字字符串）按位数分类，跟 dayjs
/// 用的经验规则一样：`>= 1e14` 当微秒，`>= 1e11` 当毫秒，更小的当秒。
///
/// Non-standard string formats normalized before parsing: `/` as the date
/// separator (`2024/01/01`), a space instead of `T` between date and time
/// (`2024-01-01 10:00:00`), and date-only strings (`2024-01-01`) — the last
/// of these is already handled by stock `DateTime.parse`.
///
/// 解析前会先归一化的不规范字符串格式：用 `/` 做日期分隔符（`2024/01/01`）、
/// 日期和时间之间用空格而不是 `T`（`2024-01-01 10:00:00`）、仅日期
/// （`2024-01-01`）——最后这种官方 `DateTime.parse` 本来就支持。
///
/// [dateTimeUtc] controls how a *timezone-less* value is interpreted — an
/// epoch number (which has no timezone concept of its own) or a string with
/// no `Z`/offset suffix. `false` (the default, matching stock
/// `DateTime.parse`) reads it as local time; `true` reads it as UTC. A
/// string that already carries an explicit `Z`/offset is always honored as
/// given, regardless of this flag.
///
/// [dateTimeUtc] 控制"没有时区信息"的值该怎么解释——数值时间戳（本身没有时区
/// 概念）或者没有 `Z`/偏移量后缀的字符串。`false`（默认，和官方 `DateTime.parse`
/// 一致）按本地时间解释；`true` 按 UTC 解释。字符串本身如果已经带了明确的
/// `Z`/偏移量，不管这个参数是什么都按原样遵守。
///
/// Only covers non-nullable `DateTime` fields — `@JsonKey(defaultValue: ...)`
/// isn't usable on a `DateTime` field anyway (it has no const constructor,
/// so it can't be a compile-time constant), and a nullable `DateTime?`
/// field already defaults to `null` correctly via stock json_serializable.
///
/// 只覆盖非空 `DateTime` 字段——`DateTime` 没有 const 构造函数，本来就没法用
/// `@JsonKey(defaultValue: ...)`；可空的 `DateTime?` 字段走官方 json_serializable
/// 自己的处理就已经能正确兜底成 `null`。
///
/// Example:
/// ```dart
/// @LenientDateTimeConverter(dateTimeUtc: true)
/// @JsonSerializable()
/// class Foo {
///   final DateTime createdAt; // accepts "2024/01/01 00:00:00", "1704067200000", 1704067200000000
///   Foo(this.createdAt);
/// }
/// ```
class LenientDateTimeConverter implements JsonConverter<DateTime, dynamic> {
  const LenientDateTimeConverter({this.dateTimeUtc = false});

  final bool dateTimeUtc;

  /// Combined shape check for [_fromString]: in one scan, tells whether the
  /// (trimmed) string is a pure numeric epoch value (named group `numeric`)
  /// or already ends with a `Z`/offset timezone suffix (named group `tz`).
  /// Safe to run against the raw value before `/`→`-` / space→`T`
  /// normalization, since neither of those transforms touches the trailing
  /// timezone suffix.
  ///
  /// [_fromString] 的合并形态判断：一次扫描内判断（trim 后的）字符串是纯数字
  /// 时间戳（命名组 `numeric`），还是已经带 `Z`/偏移量时区后缀（命名组
  /// `tz`）。可以直接在做 `/`→`-`、空格→`T` 归一化之前的原始值上跑，因为这两种
  /// 归一化都不会碰到字符串末尾的时区后缀。
  static final RegExp _stringShapePattern = RegExp(
    r'^(?<numeric>[+-]?\d+(\.\d+)?)$|(?<tz>Z|[+-]\d{2}:?\d{2})$',
  );

  @override
  DateTime fromJson(dynamic json, [DateTime? defaultValue]) => switch (json) {
    null => defaultValue ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    DateTime v => v,
    num v => _fromEpoch(v, dateTimeUtc),
    String v => _fromString(v, dateTimeUtc),
    _ => throw FormatException(
      'Cannot convert to DateTime: unsupported value (${json.runtimeType}: $json)',
    ),
  };

  /// Matches a bare `yyyyMMdd` string (8 digits, plausible year/month/day) —
  /// checked before the epoch-by-magnitude heuristic so a compact date isn't
  /// misread as an 8-digit epoch-seconds value (which would land in
  /// 1970-1973, a range no real payload uses for "now").
  static final RegExp _yyyyMMddPattern = RegExp(r'^(\d{4})(\d{2})(\d{2})$');

  static DateTime _fromEpoch(num value, bool utc) {
    if (!value.isFinite) {
      throw FormatException('Cannot convert to DateTime: not a finite number ($value)');
    }
    final magnitude = value.abs();
    if (magnitude >= 1e14) {
      return DateTime.fromMicrosecondsSinceEpoch(value.round(), isUtc: utc);
    }
    if (magnitude >= 1e11) {
      return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: utc);
    }
    final millis = value * 1000;
    if (!millis.isFinite || millis.abs() > 8640000000000000) {
      throw FormatException('Cannot convert to DateTime: epoch value out of range ($value)');
    }
    return DateTime.fromMillisecondsSinceEpoch(millis.round(), isUtc: utc);
  }

  static DateTime _fromString(String raw, bool utc) {
    final value = raw.trim();

    final dateMatch = _yyyyMMddPattern.firstMatch(value);
    if (dateMatch != null) {
      final year = int.parse(dateMatch.group(1)!);
      final month = int.parse(dateMatch.group(2)!);
      final day = int.parse(dateMatch.group(3)!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return utc ? DateTime.utc(year, month, day) : DateTime(year, month, day);
      }
    }

    final shape = _stringShapePattern.firstMatch(value);
    if (shape?.namedGroup('numeric') != null) {
      return _fromEpoch(num.parse(value), utc);
    }

    var normalized = value.replaceAll('/', '-');
    final spaceIndex = normalized.indexOf(' ');
    if (spaceIndex > 0) {
      normalized = normalized.replaceRange(spaceIndex, spaceIndex + 1, 'T');
    }

    final hasTimezone = shape?.namedGroup('tz') != null;
    if (utc && !hasTimezone) {
      normalized = '${normalized}Z';
    }

    return DateTime.parse(normalized);
  }

  @override
  dynamic toJson(DateTime object) => object.toIso8601String();
}
