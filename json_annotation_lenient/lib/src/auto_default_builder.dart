// This file is a build_runner-only tool, never shipped or imported by an
// app's runtime code.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:json_serializable/json_serializable.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:source_gen/source_gen.dart';
import 'package:yaml/yaml.dart';

import 'json_converters.dart' show LenientConverter, DisableLenient;

/// Replaces the stock `json_serializable` + `source_gen:combining_builder`
/// pipeline with a single builder that runs [JsonSerializableGenerator] and
/// [JsonEnumGenerator] itself, then post-processes the generated
/// `*FromJson` functions in two ways:
///
/// 1. Every non-nullable field with no explicit `@JsonKey(defaultValue:)`
///    falls back to a type-based default (`''`, `0`, `0.0`, `false`,
///    `const []`, `const {}`) instead of throwing on a missing/null value.
/// 2. A class annotated `@LenientConverter(int: true, ...)` gets its
///    matching-type fields routed through the corresponding
///    `Lenient*Converter` (see `lib/src/json_converters.dart`) — no need
///    to stack `@LenientIntConverter()`/`@LenientDoubleConverter()`/...
///    A field marked `@DisableLenient()` is left completely untouched by
///    both of the above (pure stock `json_serializable` behavior).
/// 3. The builder's own `options.lenient` section in `build.yaml` can turn
///    leniency on/off per scalar type project-wide and override the fallback
///    default value for each — see [_YamlLenientConfig] and
///    [_ClassLenientConfig.isEnabledFor] for the precedence rules.
///
/// 用一个 builder 替换掉默认的 `json_serializable` + `source_gen:combining_builder`
/// 流程：自己跑一遍 [JsonSerializableGenerator]/[JsonEnumGenerator]，再对生成的
/// `*FromJson` 函数做两件事：
///
/// 1. 没有显式写 `@JsonKey(defaultValue:)` 的非空字段，统一按类型兜底默认值
///    （`''`、`0`、`0.0`、`false`、`const []`、`const {}`），而不是在 key
///    缺失/为 null 时抛异常。
/// 2. 类上标了 `@LenientConverter(int: true, ...)` 的话，匹配类型的字段会被
///    改写成走对应的 `Lenient*Converter`（见 `lib/src/json_converters.dart`）
///    ——不用再叠 `@LenientIntConverter()`/`@LenientDoubleConverter()`/...。
///    字段标了 `@DisableLenient()` 的话完全不受以上两条影响（纯官方
///    `json_serializable` 行为）。
/// 3. `build.yaml` 里本 builder 的 `options.lenient` 段可以按标量类型全局
///    开关宽松转换，并覆盖各自的兜底默认值——优先级规则见
///    [_YamlLenientConfig] 和 [_ClassLenientConfig.isEnabledFor]。
///
/// Why not a `PostProcessBuilder` reading json_serializable's own `.g.dart`
/// output: build_runner refuses to let one rewrite the very asset it read as
/// input (confirmed in `build_runner`'s `post_process_build_step_impl.dart`
/// — writing back to the input id throws
/// `InvalidOutputException('Asset already exists')`). Producing a second
/// part file alongside also doesn't work: `source_gen`'s combining builder
/// refuses to run at all unless the *exact* `part 'x.g.dart';` directive is
/// present, and including it verbatim alongside a second part would
/// duplicate every generated top-level declaration. Fully replacing the
/// pipeline sidesteps both problems.
///
/// 为什么不用 `PostProcessBuilder` 去读 json_serializable 自己生成的 `.g.dart`
/// 再改：build_runner 不允许它把内容写回自己读取的那个输入文件（见 build_runner
/// 源码 `post_process_build_step_impl.dart`——写回 input id 会抛
/// `InvalidOutputException('Asset already exists')`）。另外生成第二个 part 文件
/// 也不行：source_gen 的 combining builder 必须看到一模一样的
/// `part 'x.g.dart';` 才会运行，而如果把这行也保留、同时再加一个 part，会导致
/// 每个生成的顶层声明重复定义。所以只能整体替换掉这条流水线。
Builder autoDefaultJsonBuilder(BuilderOptions options) {
  final config = JsonSerializable.fromJson(
    _resolveJsonSerializableConfig(options.config),
  );

  final rawLenient = options.config[_lenientOptionKey];
  final yml = _YamlLenientConfig.fromOptions(
    rawLenient is Map ? rawLenient : null,
  );

  final explicitPageWidth = _readPageWidth(options.config);
  final explicitTrailingCommas = _readTrailingCommas(options.config);
  // Only bother walking the filesystem when at least one of the two is
  // actually missing — an explicit `options:` value always wins anyway.
  final detected = (explicitPageWidth == null || explicitTrailingCommas == null)
      ? _detectFormatterOptionsFromAnalysisOptions()
      : _emptyDetectedFormatterOptions;

  return PartBuilder(
    [
      _LenientAwareGenerator(JsonSerializableGenerator(config: config), yml),
      const JsonEnumGenerator(),
    ],
    '.g.dart',
    formatOutput: _formatCodeWith(
      explicitPageWidth ?? detected.pageWidth,
      explicitTrailingCommas ?? detected.trailingCommas,
    ),
  );
}

/// `page_width:` key for this builder's own `options:` — see [_readPageWidth].
///
/// 本 builder 自己的 `options:` 里 `page_width:` 键名——见 [_readPageWidth]。
const _pageWidthOptionKey = 'page_width';

/// `trailing_commas:` key for this builder's own `options:` — see
/// [_readTrailingCommas]. Same values `dart_style` itself accepts in
/// `analysis_options.yaml`'s `formatter:` section: `'automate'`/`'preserve'`.
///
/// 本 builder 自己的 `options:` 里 `trailing_commas:` 键名——见
/// [_readTrailingCommas]。取值和 `dart_style` 自己在 `analysis_options.yaml`
/// 的 `formatter:` 段里认的一样：`'automate'`/`'preserve'`。
const _trailingCommasOptionKey = 'trailing_commas';

/// Reads `options.page_width` as an `int`, or null when absent/mistyped.
/// An explicit value here always wins over whatever
/// [_detectFormatterOptionsFromAnalysisOptions] finds.
///
/// 把 `options.page_width` 读成 `int`；没写或类型不对就返回 null。这里显式写的
/// 值永远优先于 [_detectFormatterOptionsFromAnalysisOptions] 探测到的结果。
int? _readPageWidth(Map<String, Object?> rawConfig) {
  final value = rawConfig[_pageWidthOptionKey];
  return value is int ? value : null;
}

/// Reads `options.trailing_commas` as a [TrailingCommas], or null when
/// absent/mistyped. Same precedence as [_readPageWidth].
///
/// 把 `options.trailing_commas` 读成 [TrailingCommas]；没写或类型不对就返回
/// null。优先级规则同 [_readPageWidth]。
TrailingCommas? _readTrailingCommas(Map<String, Object?> rawConfig) =>
    _parseTrailingCommas(rawConfig[_trailingCommasOptionKey]);

/// Parses the two string values `dart_style` itself accepts for
/// `trailing_commas` (`'automate'`/`'preserve'`) into a [TrailingCommas], or
/// null for anything else (absent, wrong type, unrecognized string).
///
/// 把 `dart_style` 自己认的两个 `trailing_commas` 字符串取值
/// （`'automate'`/`'preserve'`）解析成 [TrailingCommas]；其它情况（没写、
/// 类型不对、字符串不认识）一律返回 null。
TrailingCommas? _parseTrailingCommas(Object? value) => switch (value) {
  'automate' => TrailingCommas.automate,
  'preserve' => TrailingCommas.preserve,
  _ => null,
};

/// Result of [_detectFormatterOptionsFromAnalysisOptions] — either field may
/// be null when nothing was found (or nothing needed finding).
///
/// [_detectFormatterOptionsFromAnalysisOptions] 的结果——没探测到（或者根本
/// 不需要探测）的字段就是 null。
typedef _DetectedFormatterOptions = ({
  int? pageWidth,
  TrailingCommas? trailingCommas,
});

const _emptyDetectedFormatterOptions = (pageWidth: null, trailingCommas: null);

/// Walks up from the current working directory — the project root
/// `build_runner` is invoked from — looking for the nearest
/// `analysis_options.yaml`, and reads its `formatter: page_width:`/
/// `trailing_commas:` keys, the same two (and only two) keys `dart_style`'s
/// own CLI reads there (see [_readPageWidth]'s dartdoc for why we can't just
/// call into `dart_style`'s own reader). This is a from-scratch,
/// deliberately simplified reimplementation: it only follows a single local
/// (non-`package:`) `include:` path per file, not the full include-merging
/// `dart_style` itself supports — an `analysis_options.yaml` whose
/// `formatter:` section lives behind a `package:` include won't be picked
/// up; set `options.page_width`/`options.trailing_commas` explicitly in
/// that case.
///
/// Only called once from [autoDefaultJsonBuilder] — not from inside the
/// per-file `formatOutput` callback, which is synchronous and has no
/// filesystem access at all. A real, synchronous filesystem read is safe
/// here specifically because this runs directly on the local machine during
/// builder construction, not inside build_runner's sandboxed per-asset
/// build graph.
///
/// 从当前工作目录（也就是跑 build_runner 时的项目根目录）向上查找最近的
/// `analysis_options.yaml`，读出 `formatter: page_width:`/`trailing_commas:`
/// ——跟 `dart_style` 自己 CLI 读的那两个（也只有那两个）键一样（为什么不能
/// 直接调用 `dart_style` 自己的读取逻辑，见 [_readPageWidth] 的 dartdoc）。
/// 这里是从零实现的简化版：每个文件只跟随一层本地（非 `package:`）的
/// `include:` 路径，不支持 `dart_style` 自己那种完整的 include 合并——如果
/// `formatter:` 配置藏在一个 `package:` include 背后，探测不到；这种情况下
/// 请显式配置 `options.page_width`/`options.trailing_commas`。
///
/// 只在 [autoDefaultJsonBuilder] 里调用一次——不是在同步、完全没有文件系统
/// 访问权限的 `formatOutput` 回调里。这里真去做同步文件系统读取是安全的，
/// 因为这段代码是在 builder 构造阶段、直接跑在本机进程里的，不在
/// build_runner 沙箱化的逐 asset 构建图里面。
_DetectedFormatterOptions _detectFormatterOptionsFromAnalysisOptions() {
  var dir = Directory.current;
  while (true) {
    final file = File(
      '${dir.path}${Platform.pathSeparator}analysis_options.yaml',
    );
    if (file.existsSync()) {
      try {
        return _readFormatterSection(file, <String>{});
      } on Object {
        // Malformed yaml, unreadable file, etc. — behave as if nothing was
        // configured rather than failing the whole build over a formatting
        // nicety.
        return _emptyDetectedFormatterOptions;
      }
    }

    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return _emptyDetectedFormatterOptions;
}

/// Reads the `formatter:` section of [file], following a single local
/// `include:` path (skipped if it's a `package:` URI) for whichever key
/// [file] itself doesn't set. [visited] guards against an include cycle.
///
/// 读取 [file] 的 `formatter:` 段；[file] 自己没设的键会跟一层本地
/// `include:` 路径（`package:` URI 直接跳过）。[visited] 用来防止 include
/// 循环引用。
_DetectedFormatterOptions _readFormatterSection(
  File file,
  Set<String> visited,
) {
  if (!visited.add(file.absolute.path)) return _emptyDetectedFormatterOptions;

  final doc = loadYaml(file.readAsStringSync());
  if (doc is! Map) return _emptyDetectedFormatterOptions;

  var pageWidth = switch (doc['formatter']) {
    Map formatter => switch (formatter['page_width']) {
      final int width => width,
      _ => null,
    },
    _ => null,
  };
  var trailingCommas = switch (doc['formatter']) {
    Map formatter => _parseTrailingCommas(formatter['trailing_commas']),
    _ => null,
  };

  if (pageWidth == null || trailingCommas == null) {
    final include = doc['include'];
    if (include is String && !include.startsWith('package:')) {
      final includeFile = File(
        '${file.parent.path}${Platform.pathSeparator}$include',
      );
      if (includeFile.existsSync()) {
        final fromInclude = _readFormatterSection(includeFile, visited);
        pageWidth ??= fromInclude.pageWidth;
        trailingCommas ??= fromInclude.trailingCommas;
      }
    }
  }

  return (pageWidth: pageWidth, trailingCommas: trailingCommas);
}

/// `explicit_to_json:` key this builder defaults to `true` when a consuming
/// project's `build.yaml` doesn't set it at all.
///
/// 消费方 `build.yaml` 完全没配 `explicit_to_json:` 时，本 builder 兜底成
/// `true` 用的键名。
const _explicitToJsonKey = 'explicit_to_json';

/// Strips this builder's own `options:` keys (see [_nonJsonSerializableKeys])
/// and fills in `explicit_to_json: true` when the consuming project's
/// `build.yaml` doesn't mention it at all — nested `@JsonSerializable`
/// fields almost always need their own `.toJson()` called explicitly, and
/// stock `json_serializable` defaults that to `false`, so every consumer
/// would otherwise have to opt in by hand. An explicit `explicit_to_json:
/// false` in the consuming project's own config is still honored — this
/// only fills the gap when the key is absent.
///
/// 摘掉本 builder 自己的 `options:` 键（见 [_nonJsonSerializableKeys]），并且
/// 在消费方 `build.yaml` 完全没提 `explicit_to_json:` 时兜底成 `true`——嵌套的
/// `@JsonSerializable` 字段几乎总是需要显式调用 `.toJson()`，而官方
/// `json_serializable` 默认是 `false`，不然每个消费方都得自己手动开一遍。
/// 消费方自己显式写的 `explicit_to_json: false`依然生效——这里只是在完全
/// 没写这个键时补上默认值。
Map<String, Object?> _resolveJsonSerializableConfig(
  Map<String, Object?> rawConfig,
) {
  final configJson = Map<String, Object?>.of(rawConfig)
    ..removeWhere((key, _) => _nonJsonSerializableKeys.contains(key));
  configJson.putIfAbsent(_explicitToJsonKey, () => true);
  return configJson;
}

/// yml `options:` key holding this builder's own `lenient:` section.
///
/// yml `options:` 里属于本 builder 自己的 `lenient:` 配置段的键名。
const _lenientOptionKey = 'lenient';

/// `options:` keys consumed by this builder itself — they must be stripped
/// before the rest is handed to [JsonSerializable.fromJson], which rejects
/// unknown keys.
///
/// 本 builder 自己消费的 `options:` 键——必须先摘掉再把剩下的交给
/// [JsonSerializable.fromJson]，否则它会因为不认识这些键而报错。
const _nonJsonSerializableKeys = <String>{
  'run_only_if_triggered',
  _lenientOptionKey,
  _pageWidthOptionKey,
  _trailingCommasOptionKey,
};

/// yml type key -> Dart type name, e.g. `dateTime` -> `DateTime`. Mirrors the
/// keys of [_converterClassNames].
///
/// yml 里的类型键 -> Dart 类型名，比如 `dateTime` -> `DateTime`。和
/// [_converterClassNames] 的键一一对应。
const _ymlTypeKeys = <String, String>{
  'int': 'int',
  'double': 'double',
  'num': 'num',
  'bool': 'bool',
  'string': 'String',
  'dateTime': 'DateTime',
};

/// Project-wide leniency config read from the builder's `options.lenient`
/// section in `build.yaml`. Every entry is optional — only the keys actually
/// written in the yml are represented here, so an absent key means "no
/// opinion" and lets the per-class/per-field annotations decide.
///
/// 从 `build.yaml` 里 builder 的 `options.lenient` 段读出来的全局宽松配置。
/// 每一项都是可选的——只有 yml 里真正写了的键才会出现在这里；没写的键表示
/// "不表态"，交给类级/字段级注解决定。
class _YamlLenientConfig {
  _YamlLenientConfig(this._enabled, this._defaults, this.dateTimeUtc);

  /// The "nothing configured" instance, used when `options.lenient` is absent
  /// or unparseable.
  ///
  /// "什么都没配"的实例，`options.lenient` 缺失或解析不了时用它。
  static final empty = _YamlLenientConfig(const {}, const {}, null);

  /// Dart type name -> explicit `enabled:` flag from the yml.
  final Map<String, bool> _enabled;

  /// Dart type name -> `defaultValue:` rendered as a Dart literal source
  /// string (`0`, `0.0`, `false`, `'foo'`).
  final Map<String, String> _defaults;

  /// Global `dateTime.utc:` flag, or null when the yml doesn't mention it.
  final bool? dateTimeUtc;

  /// Leniently parses the `lenient:` yml section — anything with an
  /// unexpected shape is skipped rather than thrown, so one bad key can't
  /// take down the whole build.
  ///
  /// 宽松解析 `lenient:` yml 段——形状不对的项直接跳过而不是抛异常，
  /// 免得一个写错的键把整个构建搞崩。
  factory _YamlLenientConfig.fromOptions(Map<Object?, Object?>? raw) {
    if (raw == null) return empty;

    final enabled = <String, bool>{};
    final defaults = <String, String>{};
    bool? dateTimeUtc;

    for (final MapEntry(key: ymlKey, value: typeName) in _ymlTypeKeys.entries) {
      final section = raw[ymlKey];
      if (section is! Map) continue;

      final enabledValue = section['enabled'];
      if (enabledValue is bool) enabled[typeName] = enabledValue;

      if (typeName == 'DateTime') {
        // DateTime has no const constructor, so `defaultValue:` can't be
        // rendered as a Dart literal — ignore it (rather than fail) and only
        // honor `utc:` here.
        final utcValue = section['utc'];
        if (utcValue is bool) dateTimeUtc = utcValue;
        continue;
      }

      final literal = _renderDefault(typeName, section['defaultValue']);
      if (literal != null) defaults[typeName] = literal;
    }

    return _YamlLenientConfig(enabled, defaults, dateTimeUtc);
  }

  /// The yml's explicit `enabled:` for [typeName], or null when the yml says
  /// nothing about that type.
  ///
  /// yml 对 [typeName] 显式写的 `enabled:`；yml 没提这个类型时返回 null。
  bool? enabledFor(String typeName) => _enabled[typeName];

  /// The yml's `defaultValue:` for [typeName] as Dart literal source, or null
  /// when unset/unsupported.
  ///
  /// yml 给 [typeName] 配的 `defaultValue:`（Dart 字面量源码形式）；没配或不
  /// 支持时返回 null。
  String? defaultFor(String typeName) => _defaults[typeName];
}

/// Renders a yml scalar into Dart literal source for [typeName], or null when
/// the value's runtime type doesn't match the target type.
///
/// 把 yml 里的标量值渲染成 [typeName] 对应的 Dart 字面量源码；值的实际类型和
/// 目标类型对不上时返回 null。
String? _renderDefault(String typeName, Object? value) {
  if (value == null) return null;
  return switch (typeName) {
    'String' => value is String ? _dartStringLiteral(value) : null,
    'bool' => value is bool ? value.toString() : null,
    'int' => value is int ? value.toString() : null,
    'double' => value is num ? value.toDouble().toString() : null,
    'num' => value is num ? value.toString() : null,
    _ => null,
  };
}

/// Escapes [value] into a single-quoted Dart string literal.
///
/// 把 [value] 转义成单引号包裹的 Dart 字符串字面量。
String _dartStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}

/// Builds the [PartBuilder.formatOutput] callback, closing over the
/// resolved `pageWidth`/`trailingCommas` (explicit `options:` value, or
/// whatever [_detectFormatterOptionsFromAnalysisOptions] found) —
/// [PartBuilder] only passes `(code, languageVersion)` to this callback, so
/// these have to be captured ahead of time rather than threaded through per
/// call.
///
/// 构造 [PartBuilder.formatOutput] 回调，把解析好的 `pageWidth`/`trailingCommas`
/// （显式 `options:` 值，或者 [_detectFormatterOptionsFromAnalysisOptions]
/// 探测到的结果）提前捕获进闭包——[PartBuilder] 调用这个回调时只传
/// `(code, languageVersion)`，这些配置没法逐次传进来，只能提前捕获。
String Function(String code, Version languageVersion) _formatCodeWith(
  int? pageWidth,
  TrailingCommas? trailingCommas,
) =>
    (code, languageVersion) => DartFormatter(
      languageVersion: languageVersion,
      pageWidth: pageWidth,
      trailingCommas: trailingCommas,
    ).format(code);

/// Per-class config extracted from `@LenientConverter(...)` and
/// `@DisableLenient()` — which scalar types should route through a
/// converter, and which fields opt out entirely.
///
/// 从 `@LenientConverter(...)` 和 `@DisableLenient()` 提取出的按类配置——
/// 哪些标量类型要走 converter，哪些字段整体退出。
class _ClassLenientConfig {
  _ClassLenientConfig(
    this.enabledTypes,
    this.disabledFields,
    this.fieldOverrides,
    this.dateTimeUtc, [
    this.dateTimeUtcOverrides = const {},
  ]);

  /// The "class carries no `@LenientConverter`/`@DisableLenient` at all"
  /// instance — such a class still goes through the rewrite so a yml-level
  /// `lenient:` config can enable leniency for it.
  ///
  /// "这个类完全没标 `@LenientConverter`/`@DisableLenient`" 时用的实例——
  /// 它依然会走一遍改写流程，好让 yml 里的 `lenient:` 全局配置对它生效。
  static final empty = _ClassLenientConfig(const {}, const {}, const {}, false);

  /// Class-level `@LenientConverter(...)` flags (empty if the class itself
  /// isn't annotated — a field can still have its own override).
  final Set<String> enabledTypes;
  final Set<String> disabledFields;

  /// Class-level `@LenientConverter(dateTimeUtc: ...)` flag, threaded through
  /// to the generated `LenientDateTimeConverter(dateTimeUtc: ...)` call.
  final bool dateTimeUtc;

  /// Field name -> that field's own `@LenientConverter(...)` flags, when a
  /// field carries the annotation directly. Takes priority over
  /// [enabledTypes] for that field.
  final Map<String, Set<String>> fieldOverrides;

  /// Field name -> that field's own `@LenientConverter(dateTimeUtc: ...)`,
  /// when a field carries the annotation directly. Takes priority over
  /// [dateTimeUtc] for that field.
  final Map<String, bool> dateTimeUtcOverrides;

  /// Whether [typeName] leniency applies to [fieldName]. Priority: the
  /// field's own `@LenientConverter(...)` wins outright; otherwise the yml's
  /// explicit `enabled:` for that type overrides the class annotation;
  /// otherwise the class annotation decides.
  ///
  /// [fieldName] 上的 [typeName] 是否启用宽松转换。优先级：字段自己的
  /// `@LenientConverter(...)` 最高，yml 不能覆盖；其次是 yml 对该类型的显式
  /// `enabled:`（会覆盖类级注解）；最后才是类级注解。
  bool isEnabledFor(String fieldName, String typeName, _YamlLenientConfig yml) {
    final fieldOverride = fieldOverrides[fieldName];
    if (fieldOverride != null) return fieldOverride.contains(typeName);
    return yml.enabledFor(typeName) ?? enabledTypes.contains(typeName);
  }

  /// The `dateTimeUtc` flag for [fieldName]. Priority: field annotation >
  /// yml `dateTime.utc` > class annotation.
  ///
  /// [fieldName] 用的 `dateTimeUtc`。优先级：字段注解 > yml 的
  /// `dateTime.utc` > 类注解。
  bool dateTimeUtcFor(String fieldName, _YamlLenientConfig yml) =>
      dateTimeUtcOverrides[fieldName] ?? yml.dateTimeUtc ?? dateTimeUtc;
}

Set<String> _readEnabledTypes(ConstantReader reader) => {
  if (reader.read('intEnabled').boolValue) 'int',
  if (reader.read('doubleEnabled').boolValue) 'double',
  if (reader.read('numEnabled').boolValue) 'num',
  if (reader.read('boolEnabled').boolValue) 'bool',
  if (reader.read('stringEnabled').boolValue) 'String',
  if (reader.read('dateTimeEnabled').boolValue) 'DateTime',
};

bool _readDateTimeUtc(ConstantReader reader) =>
    reader.read('dateTimeUtc').boolValue;

const _converterClassNames = <String, String>{
  'int': 'LenientIntConverter',
  'double': 'LenientDoubleConverter',
  'num': 'LenientNumConverter',
  'bool': 'LenientBoolConverter',
  'String': 'LenientStringConverter',
  'DateTime': 'LenientDateTimeConverter',
};

const _lenientConverterChecker = TypeChecker.typeNamed(LenientConverter);
const _disableLenientChecker = TypeChecker.typeNamed(DisableLenient);

/// Wraps [JsonSerializableGenerator], scans the library for
/// `@LenientConverter`/`@DisableLenient` usage, and post-processes the
/// generated text using that per-class config.
///
/// 包一层 [JsonSerializableGenerator]，扫描库里的
/// `@LenientConverter`/`@DisableLenient` 用法，用这份按类配置对生成文本做
/// 二次处理。
class _LenientAwareGenerator extends Generator {
  _LenientAwareGenerator(this._inner, this._yml);

  final JsonSerializableGenerator _inner;

  /// Project-wide `options.lenient` config from `build.yaml`.
  final _YamlLenientConfig _yml;

  @override
  Future<String?> generate(LibraryReader library, BuildStep buildStep) async {
    final raw = await _inner.generate(library, buildStep);
    if (raw.trim().isEmpty) return raw;

    // `LibraryReader.annotatedWith` only walks the library's direct
    // children (top-level declarations) — class *fields* are children of
    // the class, not the library, so they're invisible to it. Walk classes
    // and their fields ourselves instead.
    final configs = <String, _ClassLenientConfig>{};
    for (final element in library.allElements) {
      if (element is! ClassElement) continue;
      final className = element.name;
      if (className == null) continue;

      final classAnnotation = _lenientConverterChecker.firstAnnotationOfExact(
        element,
      );
      final enabled = classAnnotation == null
          ? const <String>{}
          : _readEnabledTypes(ConstantReader(classAnnotation));
      final classDateTimeUtc = classAnnotation == null
          ? false
          : _readDateTimeUtc(ConstantReader(classAnnotation));

      final disabledFields = <String>{};
      final fieldOverrides = <String, Set<String>>{};
      final dateTimeUtcOverrides = <String, bool>{};
      // json_serializable's own field collection unions inherited fields
      // into the generated constructor call, so a `@DisableLenient()` or
      // field-level `@LenientConverter(...)` on a superclass field must be
      // visible here too, not just `element.fields` (which excludes them).
      final allFields = <FieldElement>[
        ...element.fields,
        for (final supertype in element.allSupertypes)
          ...supertype.element.fields,
      ];
      for (final field in allFields) {
        final fieldName = field.name;
        if (fieldName == null) continue;
        if (_disableLenientChecker.hasAnnotationOfExact(field)) {
          disabledFields.add(fieldName);
          continue;
        }
        final fieldAnnotation = _lenientConverterChecker.firstAnnotationOfExact(
          field,
        );
        if (fieldAnnotation != null) {
          final reader = ConstantReader(fieldAnnotation);
          fieldOverrides[fieldName] = _readEnabledTypes(reader);
          dateTimeUtcOverrides[fieldName] = _readDateTimeUtc(reader);
        }
      }

      // Skip entirely only if nothing on this class is relevant — avoids
      // building an empty config for every plain @JsonSerializable() class.
      if (classAnnotation == null &&
          disabledFields.isEmpty &&
          fieldOverrides.isEmpty) {
        continue;
      }
      configs[className] = _ClassLenientConfig(
        enabled,
        disabledFields,
        fieldOverrides,
        classDateTimeUtc,
        dateTimeUtcOverrides,
      );
    }

    // A generated part file has no imports of its own — it inherits the
    // enclosing library's. Routing a field through `LenientIntConverter` et
    // al. only compiles if this library itself imports the package; a
    // yml-only setup (no @LenientConverter/@DisableLenient anywhere) is the
    // case most likely to omit that import, since nothing else in the file
    // would otherwise need it.
    final hasLenientImport = library.element.firstFragment.importedLibraries
        .any((lib) => lib.identifier.contains('json_annotation_lenient'));
    if (configs.isNotEmpty && !hasLenientImport) {
      log.warning(
        "options.lenient (or @LenientConverter) is active for ${library.element.identifier} "
        "but it doesn't import package:json_annotation_lenient/json_annotation_lenient.dart — "
        'add that import or the generated code will fail to compile with an undefined name.',
      );
    }

    return _applyDefaults(
          raw,
          configs,
          _yml,
          routeThroughConverters: hasLenientImport,
        ) ??
        raw;
  }
}

const _typeDefaults = <String, String>{
  'String': "''",
  'int': '0',
  'double': '0.0',
  'num': '0',
  'bool': 'false',
  'Map': 'const {}',
};

final _fromJsonName = RegExp(r'^_\$(.+)FromJson$');

/// Injects `?? <type default>` into every recognized non-nullable,
/// no-explicit-default field assignment inside a generated `*FromJson`
/// function body, and — where [configs] enables it for the enclosing
/// class — routes scalar fields through the matching `Lenient*Converter`
/// instead.
///
/// 给生成的 `*FromJson` 函数体里,每一个可识别的、非空且没有显式默认值的字段赋值
/// 表达式,注入 `?? <类型默认值>`；如果 [configs] 里对应的类开启了某个标量类型,
/// 就改成走对应的 `Lenient*Converter`。
String? _applyDefaults(
  String source,
  Map<String, _ClassLenientConfig> configs,
  _YamlLenientConfig yml, {
  bool routeThroughConverters = true,
}) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final edits = <(int start, int end, String replacement)>[];

  for (final declaration in unit.declarations) {
    if (declaration is! FunctionDeclaration) continue;
    final match = _fromJsonName.firstMatch(declaration.name.lexeme);
    if (match == null) continue;
    final className = match.group(1)!;
    // A class with no relevant annotations still gets the full treatment —
    // the yml `lenient:` config alone can enable leniency for its fields.
    final classConfig = configs[className] ?? _ClassLenientConfig.empty;

    final body = declaration.functionExpression.body;
    if (body is! ExpressionFunctionBody) continue;

    // Without full resolution, `ClassName(...)` parses as a bare
    // MethodInvocation, not an InstanceCreationExpression — the parser
    // can't distinguish a constructor call from a function call by syntax
    // alone. We only need its ArgumentList, so handle both shapes.
    final expr = body.expression;
    final argumentList = switch (expr) {
      InstanceCreationExpression() => expr.argumentList,
      MethodInvocation() => expr.argumentList,
      _ => null,
    };
    if (argumentList == null) continue;

    for (final arg in argumentList.arguments) {
      if (arg is! NamedArgument) continue;
      final fieldName = arg.name.lexeme;

      if (classConfig.disabledFields.contains(fieldName)) {
        // @DisableLenient(): leave this field exactly as stock
        // json_serializable generated it — no leniency, no auto default.
        continue;
      }

      final scalar = _extractScalarShape(arg.argumentExpression);
      if (scalar != null &&
          routeThroughConverters &&
          classConfig.isEnabledFor(fieldName, scalar.typeName, yml)) {
        final converterClass = _converterClassNames[scalar.typeName]!;
        final ctorArgs = scalar.typeName == 'DateTime'
            ? '(dateTimeUtc: ${classConfig.dateTimeUtcFor(fieldName, yml)})'
            : '()';
        // The field's own @JsonKey(defaultValue:) wins; the yml default is
        // the project-wide fallback; neither means "let the converter use
        // its own built-in default".
        final defaultSource =
            scalar.defaultSource ?? yml.defaultFor(scalar.typeName);
        final callArgs = defaultSource == null
            ? scalar.jsonAccess
            : '${scalar.jsonAccess}, $defaultSource';
        edits.add((
          arg.argumentExpression.offset,
          arg.argumentExpression.end,
          'const $converterClass$ctorArgs.fromJson($callArgs)',
        ));
        continue;
      }

      final edit = _edit(arg.argumentExpression, yml);
      if (edit != null) edits.add(edit);
    }
  }

  if (edits.isEmpty) return null;

  edits.sort((a, b) => a.$1.compareTo(b.$1));
  final buffer = StringBuffer();
  var cursor = 0;
  for (final (start, end, replacement) in edits) {
    buffer
      ..write(source.substring(cursor, start))
      ..write(replacement);
    cursor = end;
  }
  buffer.write(source.substring(cursor));
  return buffer.toString();
}

/// Recognizes the scalar shapes json_serializable emits for a plain (no
/// converter) `bool`/`num`/`int`/`double` field, with or without an
/// `@JsonKey(defaultValue: ...)` — e.g. `json['x'] as bool`,
/// `json['x'] as bool? ?? true`, `(json['x'] as num).toInt()`, or
/// `(json['x'] as num?)?.toInt() ?? 5` — and extracts the raw JSON access
/// expression, the logical field type, and any existing default.
///
/// 识别 json_serializable 给纯标量字段（没用 converter）生成的几种形状——
/// 不管有没有 `@JsonKey(defaultValue: ...)`，比如 `json['x'] as bool`、
/// `json['x'] as bool? ?? true`、`(json['x'] as num).toInt()`、
/// `(json['x'] as num?)?.toInt() ?? 5`——提取出原始 JSON 取值表达式、字段的
/// 逻辑类型，以及已有的默认值（如果有）。
({String jsonAccess, String typeName, String? defaultSource})?
_extractScalarShape(Expression expr) {
  Expression core = expr;
  String? defaultSource;
  if (expr is BinaryExpression && expr.operator.lexeme == '??') {
    core = expr.leftOperand;
    defaultSource = expr.rightOperand.toSource();
  }

  if (core is AsExpression) {
    final type = core.type;
    if (type is NamedType &&
        (type.name.lexeme == 'bool' ||
            type.name.lexeme == 'num' ||
            type.name.lexeme == 'String')) {
      return (
        jsonAccess: core.expression.toSource(),
        typeName: type.name.lexeme,
        defaultSource: defaultSource,
      );
    }
    return null;
  }

  if (core is MethodInvocation &&
      (core.methodName.name == 'toInt' || core.methodName.name == 'toDouble')) {
    var target = core.target;
    if (target is ParenthesizedExpression) target = target.expression;
    if (target is! AsExpression) return null;
    final type = target.type;
    if (type is! NamedType || type.name.lexeme != 'num') return null;
    return (
      jsonAccess: target.expression.toSource(),
      typeName: core.methodName.name == 'toInt' ? 'int' : 'double',
      defaultSource: defaultSource,
    );
  }

  if (core is MethodInvocation && core.methodName.name == 'parse') {
    // json_serializable emits `DateTime.parse(json['x'] as String)` for a
    // non-nullable DateTime field — no defaultValue is ever possible here
    // (DateTime has no const constructor), so this never needs a `??`
    // rewrite, just routing through the Lenient converter when enabled.
    final target = core.target;
    if (target is! SimpleIdentifier || target.name != 'DateTime') return null;
    final args = core.argumentList.arguments;
    if (args.length != 1 || args.single is! AsExpression) return null;
    final inner = args.single as AsExpression;
    final innerType = inner.type;
    if (innerType is! NamedType || innerType.name.lexeme != 'String') {
      return null;
    }
    return (
      jsonAccess: inner.expression.toSource(),
      typeName: 'DateTime',
      defaultSource: defaultSource,
    );
  }

  return null;
}

/// Returns the (start, end, replacement) edit to apply to [expr], or null if
/// [expr] already has an explicit fallback or isn't a recognized
/// non-nullable cast/list-mapping shape.
///
/// 返回 [expr] 对应的 (start, end, replacement) 编辑；如果 [expr] 已经有显式
/// 兜底，或者不是可识别的"非空 cast / list 映射"形状，返回 null。
(int, int, String)? _edit(Expression expr, _YamlLenientConfig yml) {
  if (expr is BinaryExpression && expr.operator.lexeme == '??') {
    return null;
  }

  if (expr is ConditionalExpression) {
    // json_serializable emits `json['x'] == null ? <default> : const
    // Converter().fromJson(json['x'])` when a field has both an explicit
    // `@JsonKey(defaultValue: ...)` and a directly-annotated `JsonConverter`
    // (the older per-field override style). Fold the default into the
    // `fromJson` call itself as its second positional argument, instead of
    // keeping it as an external null-check:
    // `const Converter().fromJson(json['x'], <default>)`. Only applied when
    // the converter is one of our own Lenient*Converter classes, which are
    // guaranteed to accept that optional second `defaultValue` parameter —
    // see the `ctorName` check below.
    final condition = expr.condition;
    if (condition is! BinaryExpression || condition.operator.lexeme != '==') {
      return null;
    }
    if (condition.leftOperand is! NullLiteral &&
        condition.rightOperand is! NullLiteral) {
      return null;
    }

    final elseExpr = expr.elseExpression;
    if (elseExpr is! MethodInvocation ||
        elseExpr.methodName.name != 'fromJson') {
      return null;
    }
    final creation = elseExpr.target;
    if (creation is! InstanceCreationExpression) return null;

    // Only fold the default into one of *our own* Lenient*Converter calls —
    // a third-party JsonConverter's fromJson may not accept a second
    // positional defaultValue argument, and rewriting it would push a
    // compile error into generated code the user never opted leniency into.
    final ctorName = creation.constructorName.type.name.lexeme;
    if (!_converterClassNames.values.contains(ctorName)) return null;

    final targetSource = creation.toSource();
    final defaultSource = expr.thenExpression.toSource();
    final fromJsonArgs = [
      ...elseExpr.argumentList.arguments.map((a) => a.toSource()),
      defaultSource,
    ].join(', ');

    return (expr.offset, expr.end, '$targetSource.fromJson($fromJsonArgs)');
  }

  if (expr is AsExpression) {
    final type = expr.type;
    if (type is NamedType && type.question == null) {
      // A yml `defaultValue:` for this type replaces the built-in fallback
      // (`'Map'` has no yml counterpart, so it always keeps `const {}`).
      final defaultText =
          yml.defaultFor(type.name.lexeme) ?? _typeDefaults[type.name.lexeme];
      if (defaultText != null) {
        // `json['x'] as String` throws on a null value before `??` ever
        // runs — non-nullable casts don't evaluate to null, they throw.
        // The cast itself has to become nullable for the fallback to have
        // any effect: `json['x'] as String? ?? ''`. Kept explicit (rather
        // than relying on the implicit dynamic-to-String assignment,
        // which behaves identically here) to match json_serializable's
        // own generated style and stay compatible with projects that
        // enable `strict-casts` in analysis_options.yaml.
        final operand = expr.expression.toSource();
        final typeSource = type.toSource();
        return (
          expr.offset,
          expr.end,
          '$operand as $typeSource? ?? $defaultText',
        );
      }
    }
    return null;
  }

  if (expr is MethodInvocation &&
      (expr.methodName.name == 'toInt' || expr.methodName.name == 'toDouble')) {
    // json_serializable emits `(json['x'] as num).toInt()` / `.toDouble()`
    // for `int`/`double` fields (so a JSON number of the "wrong" numeric
    // subtype still converts). The inner `as num` is non-nullable and
    // throws on a missing/null value before `.toInt()`/`.toDouble()` ever
    // run — same problem as the List case, needs the same nullable-chain
    // rebuild: `(json['x'] as num?)?.toInt() ?? 0`.
    var target = expr.target;
    if (target is ParenthesizedExpression) target = target.expression;
    if (target is! AsExpression) return null;
    final type = target.type;
    if (type is! NamedType || type.question != null) return null;
    if (type.name.lexeme != 'num') return null;

    final isInt = expr.methodName.name == 'toInt';
    final defaultText =
        yml.defaultFor(isInt ? 'int' : 'double') ?? (isInt ? '0' : '0.0');
    final operand = target.expression.toSource();
    return (
      expr.offset,
      expr.end,
      '($operand as num?)?.${expr.methodName.name}() ?? $defaultText',
    );
  }

  if (expr is InstanceCreationExpression) {
    // json_serializable emits `Map<K, V>.from(json['x'] as Map)` for a
    // non-nullable `Map<K, V>` field whose value type isn't `dynamic` (e.g.
    // `Map<String, int>`). The inner `as Map` is non-nullable and throws on
    // a missing/null value before `.from()` ever runs — same "cast throws
    // before the conversion can help" problem as List/num. `Map.from` has
    // no `?.`-chainable form, so the fix lives inside its single argument:
    // `Map<K, V>.from(json['x'] as Map? ?? const {})`.
    final ctorType = expr.constructorName.type;
    if (ctorType.name.lexeme != 'Map' ||
        expr.constructorName.name?.name != 'from') {
      return null;
    }
    final args = expr.argumentList.arguments;
    if (args.length != 1) return null;
    final inner = args.single;
    if (inner is! AsExpression) return null;
    final innerType = inner.type;
    if (innerType is! NamedType ||
        innerType.question != null ||
        innerType.name.lexeme != 'Map') {
      return null;
    }

    final operand = inner.expression.toSource();
    final innerTypeSource = innerType.toSource();
    return (
      inner.offset,
      inner.end,
      '$operand as $innerTypeSource? ?? const {}',
    );
  }

  if (expr is MethodInvocation &&
      (expr.methodName.name == 'toList' || expr.methodName.name == 'toSet')) {
    final mapCall = expr.target;
    if (mapCall is! MethodInvocation || mapCall.methodName.name != 'map') {
      return null;
    }
    var innerExpr = mapCall.target;
    if (innerExpr is ParenthesizedExpression) innerExpr = innerExpr.expression;
    if (innerExpr is! AsExpression) return null;
    final type = innerExpr.type;
    if (type is! NamedType) return null;

    // json_serializable emits `(json['x'] as List<dynamic>).map(...).toList()`
    // (or `.toSet()` for a `Set<T>` field) for a non-nullable field with no
    // defaultValue — the inner cast itself throws on null before
    // `.map`/`.toList()`/`.toSet()` ever run, so a trailing `?? const []`
    // alone would be dead code. Rebuild the whole chain nullable-safe:
    // `(json['x'] as List<dynamic>?)?.map(...).toList() ?? const []`.
    if (type.question == null) {
      final indexSource = innerExpr.expression.toSource();
      final typeSource = type.toSource();
      final mapArgSource = mapCall.argumentList.arguments.single.toSource();
      final fallback = expr.methodName.name == 'toSet'
          ? 'const {}'
          : 'const []';
      return (
        expr.offset,
        expr.end,
        '($indexSource as $typeSource?)?.map($mapArgSource).${expr.methodName.name}() ?? $fallback',
      );
    }

    // Already nullable-safe (an explicit @JsonKey(defaultValue:) was given,
    // or some other generator already handled it) — leave untouched; the
    // top-level `??` check above already skips the case where a fallback
    // follows this expression.
    return null;
  }

  return null;
}

/// Test-only entry point into the (library-private) rewrite pipeline: feeds
/// [generatedSource] — a chunk of already-generated `*FromJson` code — through
/// the same `lenient:` yml parsing and per-class/per-field precedence rules
/// the real builder uses, without needing a resolved analyzer element model.
///
/// Not exported from `package:json_annotation_lenient/builder.dart`; import
/// `src/auto_default_builder.dart` directly from this package's own tests.
///
/// 仅供测试的入口：把一段已经生成好的 `*FromJson` 代码 [generatedSource] 送进
/// 和真实 builder 完全一样的 `lenient:` yml 解析 + 类级/字段级优先级流程，不需要
/// 真的跑一遍 analyzer 的元素解析。
///
/// 它没有从 `package:json_annotation_lenient/builder.dart` 导出；包内测试直接
/// import `src/auto_default_builder.dart` 使用。
///
/// - [lenientOptions]: the raw `options.lenient` map, exactly as it would come
///   out of `build.yaml`; null means "no yml config".
/// - [classAnnotated]: false simulates a class carrying neither
///   `@LenientConverter` nor `@DisableLenient` (no config entry at all).
/// - [classEnabledTypes] / [classDateTimeUtc]: the class-level
///   `@LenientConverter(...)` flags, as Dart type names (`'int'`, `'String'`).
/// - [fieldOverrides] / [fieldDateTimeUtcOverrides]: per-field
///   `@LenientConverter(...)` flags; [disabledFields] holds `@DisableLenient()`.
///
/// Returns the rewritten source, or null when nothing needed rewriting.
///
/// Example:
/// ```dart
/// final out = debugApplyLenientRewrite(
///   "Foo _\$FooFromJson(Map<String, dynamic> json) => Foo(n: (json['n'] as num).toInt());",
///   lenientOptions: {'int': {'enabled': true}},
///   classAnnotated: false,
/// );
/// // out contains: const LenientIntConverter().fromJson(json['n'])
/// ```
String? debugApplyLenientRewrite(
  String generatedSource, {
  Map<Object?, Object?>? lenientOptions,
  String className = 'Foo',
  bool classAnnotated = true,
  Set<String> classEnabledTypes = const {},
  bool classDateTimeUtc = false,
  Set<String> disabledFields = const {},
  Map<String, Set<String>> fieldOverrides = const {},
  Map<String, bool> fieldDateTimeUtcOverrides = const {},
}) {
  final configs = <String, _ClassLenientConfig>{};
  if (classAnnotated) {
    configs[className] = _ClassLenientConfig(
      classEnabledTypes,
      disabledFields,
      fieldOverrides,
      classDateTimeUtc,
      fieldDateTimeUtcOverrides,
    );
  }
  return _applyDefaults(
    generatedSource,
    configs,
    _YamlLenientConfig.fromOptions(lenientOptions),
  );
}

/// Test-only entry point into [_resolveJsonSerializableConfig] — lets a test
/// assert on the merged `options:` map (this builder's own keys stripped,
/// `explicit_to_json` defaulted) without spinning up a real [BuilderOptions]
/// or [Builder].
///
/// 仅供测试的入口，暴露 [_resolveJsonSerializableConfig] 的结果——不用真的
/// 构造 [BuilderOptions]/[Builder]，就能断言合并后的 `options:` map（本
/// builder 自己的键已摘掉、`explicit_to_json` 已经补上默认值）。
Map<String, Object?> debugResolveJsonSerializableConfig(
  Map<String, Object?> rawConfig,
) => _resolveJsonSerializableConfig(rawConfig);

/// Test-only entry point into [_readPageWidth].
///
/// 仅供测试的入口，暴露 [_readPageWidth]。
int? debugReadPageWidth(Map<String, Object?> rawConfig) =>
    _readPageWidth(rawConfig);

/// Test-only entry point into [_readFormatterSection] — lets a test point it
/// at a real `analysis_options.yaml` file it wrote to a temp directory,
/// without needing to change [Directory.current] (which
/// [_detectFormatterOptionsFromAnalysisOptions] itself walks up from).
///
/// 仅供测试的入口，暴露 [_readFormatterSection]——让测试可以指向自己写到临时
/// 目录里的一份真实 `analysis_options.yaml`，不用去改
/// [Directory.current]（[_detectFormatterOptionsFromAnalysisOptions] 自己
/// 才需要从那里往上走）。
({int? pageWidth, TrailingCommas? trailingCommas}) debugReadFormatterSection(
  File file,
) => _readFormatterSection(file, <String>{});
