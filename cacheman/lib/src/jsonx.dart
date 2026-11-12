import 'dart:convert';

const _flag = '#t'; // json type tag — same convention as the sibling TS project's JSONX

/// Tagged payload field. / 类型标签的负载字段。
const _value = 'value';

const _kDateTime = 'DateTime';
const _kDuration = 'Duration';
const _kSet = 'Set';
const _kBigInt = 'BigInt';
const _kUri = 'Uri';
const _kRegExp = 'RegExp';
const _kMap = 'Map'; // 转义“恰好长得像标签”的普通 Map

/// Strict tagged-shape check (exact `{flag, value}` two-key shape, not just
/// "has a `flag` key") — lowers the odds of colliding with real user data
/// that happens to carry a same-named field, and guarantees a false match
/// never silently drops sibling fields (mismatched shape returns the value
/// untouched). Mirrors a fix in the sibling `@codejoo/storage` TS project's
/// `JSONX`.
///
/// 严格外壳形状检查（恰好 `{flag, value}` 两键，不只是"带 flag 字段"）——
/// 降低跟真的带同名字段的用户数据撞车的概率，且保证误判不会静默丢掉兄弟
/// 字段（形状不符原样返回）。对齐姊妹 TS 项目 `@codejoo/storage` 的 `JSONX`
/// 修过的一个坑。
bool _isTagged(dynamic v) =>
    v is Map && v.length == 2 && v.containsKey(_flag) && v.containsKey(_value);

/// Recursively escapes tag-shaped maps before encoding, preserving user fields.
/// 编码前递归转义：形如标签的普通 Map 改存成 `{#t: Map, value: [[k, v], ...]}`，
/// 避免解码时被误还原；reviver 自底向上，所以必须换掉形状而不是加标记。
dynamic _escape(dynamic v) {
  if (v is Map) {
    if (_isTagged(v)) {
      return {
        _flag: _kMap,
        _value: [
          for (final e in v.entries) [e.key, _escape(e.value)]
        ]
      };
    }
    return {for (final e in v.entries) e.key: _escape(e.value)};
  }
  if (v is List) return [for (final e in v) _escape(e)];
  if (v is Set) return {for (final e in v) _escape(e)};
  return v;
}

/// Encodes extended types, preserving DateTime instants and UTC/local mode.
/// 编码扩展类型，保留 DateTime 的时间点及 UTC/本地模式。
dynamic _toEncodable(dynamic value) {
  if (value is DateTime) {
    return {
      _flag: _kDateTime,
      _value: [value.microsecondsSinceEpoch, value.isUtc]
    };
  }
  if (value is Duration) return {_flag: _kDuration, _value: value.inMicroseconds};
  if (value is Set) return {_flag: _kSet, _value: value.toList()};
  if (value is BigInt) return {_flag: _kBigInt, _value: value.toString()};
  if (value is Uri) return {_flag: _kUri, _value: value.toString()};
  if (value is RegExp) {
    return {
      _flag: _kRegExp,
      _value: {
        'pattern': value.pattern,
        'multiLine': value.isMultiLine,
        'caseSensitive': value.isCaseSensitive,
        'unicode': value.isUnicode,
        'dotAll': value.isDotAll,
      },
    };
  }
  // Like jsonEncode, preserve the original toJson failure as the cause.
  // 与 jsonEncode 一致，保留 toJson 原始异常作为 cause。
  return _escape((value as dynamic).toJson());
}

/// Restores tags, accepting legacy DateTime strings and [microseconds, isUtc].
/// 还原标签，兼容旧 DateTime 字符串及 [微秒时间戳, isUtc]。
dynamic _reviver(dynamic key, dynamic value) {
  if (!_isTagged(value)) return value;
  final tag = value[_flag];
  final raw = value[_value];
  switch (tag) {
    case _kDateTime:
      if (raw is String) return DateTime.parse(raw);
      if (raw case [int us, bool isUtc]) {
        return DateTime.fromMicrosecondsSinceEpoch(us, isUtc: isUtc);
      }
      return value;
    case _kDuration:
      return Duration(microseconds: raw as int);
    case _kSet:
      return (raw as List).toSet();
    case _kBigInt:
      return BigInt.parse(raw as String);
    case _kUri:
      return Uri.parse(raw as String);
    case _kMap:
      // 结构不合法说明是旧版留下的普通 Map，原样保留
      if (raw is! List || !raw.every((p) => p is List && p.length == 2 && p[0] is String)) return value;
      return {for (final p in raw) (p as List)[0] as String: p[1]};
    case _kRegExp:
      final m = raw as Map;
      return RegExp(
        m['pattern'] as String,
        multiLine: m['multiLine'] as bool,
        caseSensitive: m['caseSensitive'] as bool,
        unicode: m['unicode'] as bool,
        dotAll: m['dotAll'] as bool,
      );
    default:
      return value;
  }
}

/// `dart:convert`-compatible serializer that additionally round-trips
/// [DateTime] / [Duration] / [Set] / [BigInt] / [Uri] / [RegExp] — types
/// `jsonEncode`/`jsonDecode` don't natively support. Pass
/// [Jsonx.encode]/[Jsonx.decode] as [CachemanOptions]'s
/// `serialize`/`deserialize` (wrap to match the `CacheEntity -> String`
/// signature — see the example).
///
/// [encode]'s `T` documents the input shape at the call site (inferred from
/// the argument, rarely needs spelling out). [decode]'s `T` is load-bearing:
/// there's no way to know the decoded shape at compile time otherwise, so it
/// casts the `jsonDecode` result to `T` — pass the type you expect (e.g.
/// `Jsonx.decode<Map<String, dynamic>>(s)`); a shape mismatch throws
/// [TypeError], same as any other bad `as` cast.
///
/// Enum encoding throws [JsonUnsupportedObjectError]; define a custom toJson
/// or use ValueAdapter to convert it to name. Maps with non-String keys are
/// rejected by jsonEncode before the toEncodable hook runs.
/// DateTime stores [microsecondsSinceEpoch, isUtc], preserving the instant
/// across timezones; legacy ISO 8601 strings remain readable.
///
/// ```dart
/// final cache = Cacheman(
///   options: CachemanOptions(
///     serialize: (e) => Jsonx.encode(e.toJson()),
///     deserialize: (s) => CacheEntity.fromJson(Jsonx.decode<Map<String, dynamic>>(s)),
///   ),
/// );
/// await cache.ensureInitialized();
/// cache.write('x', {'when': DateTime.now(), 'ids': {1, 2}}); // round-trips exactly
/// ```
///
/// 兼容 `dart:convert` 的序列化器，额外支持 [DateTime]/[Duration]/[Set]/
/// [BigInt]/[Uri]/[RegExp] 的可逆往返——`jsonEncode`/`jsonDecode` 原生不支持
/// 这些类型。把 [Jsonx.encode]/[Jsonx.decode] 传给 [CachemanOptions] 的
/// `serialize`/`deserialize`（包一层去对上 `CacheEntity -> String` 的签名，
/// 见上面的例子）。
///
/// [encode] 的 `T` 只是标注调用处的输入形状（从实参推断，基本不用手写）。
/// [decode] 的 `T` 是真正起作用的——编译期没法知道解码出来是什么形状，靠它
/// 把 `jsonDecode` 的结果转型成 `T`（比如 `Jsonx.decode<Map<String,
/// dynamic>>(s)`）；形状不对会像任何 `as` 转型失败一样抛 [TypeError]。
///
/// Enum 编码会抛 [JsonUnsupportedObjectError]，请自定义 toJson 或用 ValueAdapter
/// 转成 name。key 不是 String 的 Map 会在 toEncodable 钩子之前被 jsonEncode 拒绝。
/// DateTime 存为 [microsecondsSinceEpoch, isUtc]，跨时区保留时间点；兼容旧 ISO 8601 字符串。
///
/// Plain `Map`s that happen to look like a type tag (`{'#t': ..., 'value': ...}`)
/// are escaped on encode and round-trip unchanged. Objects with a `toJson()`
/// fall back to it, like plain `jsonEncode`.
///
/// 恰好形如类型标签的普通 `Map`（`{'#t': ..., 'value': ...}`）编码时会被转义，
/// 往返不变。带 `toJson()` 的对象回退到它，与原生 `jsonEncode` 一致。
///
/// Circular references are not supported (inherits `jsonEncode`'s own
/// behavior — throws).
///
/// 不支持循环引用（继承自 `jsonEncode` 自身的行为——会抛错）。
class Jsonx {
  const Jsonx._(); // coverage:ignore-line

  static String encode<T>(T value) => jsonEncode(_escape(value), toEncodable: _toEncodable);

  static T decode<T>(String text) => jsonDecode(text, reviver: _reviver) as T;
}
