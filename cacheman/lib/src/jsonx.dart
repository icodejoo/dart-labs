import 'dart:convert';

const _flag = '#t'; // json type tag — same convention as the sibling TS project's JSONX

const _kDateTime = 'DateTime';
const _kDuration = 'Duration';
const _kSet = 'Set';
const _kBigInt = 'BigInt';
const _kUri = 'Uri';
const _kRegExp = 'RegExp';

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
bool _isTagged(dynamic v) => v is Map && v.length == 2 && v.containsKey(_flag) && v.containsKey('value');

dynamic _toEncodable(dynamic value) {
  if (value is DateTime) return {_flag: _kDateTime, 'value': value.toIso8601String()};
  if (value is Duration) return {_flag: _kDuration, 'value': value.inMicroseconds};
  if (value is Set) return {_flag: _kSet, 'value': value.toList()};
  if (value is BigInt) return {_flag: _kBigInt, 'value': value.toString()};
  if (value is Uri) return {_flag: _kUri, 'value': value.toString()};
  if (value is RegExp) {
    return {
      _flag: _kRegExp,
      'value': {
        'pattern': value.pattern,
        'multiLine': value.isMultiLine,
        'caseSensitive': value.isCaseSensitive,
        'unicode': value.isUnicode,
        'dotAll': value.isDotAll,
      },
    };
  }
  throw JsonUnsupportedObjectError(value);
}

dynamic _reviver(dynamic key, dynamic value) {
  if (!_isTagged(value)) return value;
  final tag = value[_flag];
  final raw = value['value'];
  switch (tag) {
    case _kDateTime:
      return DateTime.parse(raw as String);
    case _kDuration:
      return Duration(microseconds: raw as int);
    case _kSet:
      return (raw as List).toSet();
    case _kBigInt:
      return BigInt.parse(raw as String);
    case _kUri:
      return Uri.parse(raw as String);
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
/// Not round-trippable, and not fixable here: custom `Enum`s (decode has no
/// way to know which concrete enum type to reconstruct — only a `.name`
/// string survives) and `Map`s with non-`String` keys (`jsonEncode` rejects
/// those before this file's `toEncodable` hook even runs).
///
/// ```dart
/// final cache = await Cacheman.create(
///   options: CachemanOptions(
///     serialize: (e) => Jsonx.encode(e.toJson()),
///     deserialize: (s) => CacheEntity.fromJson(Jsonx.decode<Map<String, dynamic>>(s)),
///   ),
/// );
/// cache.ls.set('x', {'when': DateTime.now(), 'ids': {1, 2}}); // round-trips exactly
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
/// 修不了、也不可逆的：自定义 `Enum`（解码时不知道该还原成哪个具体枚举
/// 类型——只留得下一个 `.name` 字符串）和 key 不是 `String` 的 `Map`
/// （`jsonEncode` 在走到本文件的 `toEncodable` 钩子之前就直接拒绝了）。
///
/// Circular references are not supported (inherits `jsonEncode`'s own
/// behavior — throws).
///
/// 不支持循环引用（继承自 `jsonEncode` 自身的行为——会抛错）。
class Jsonx {
  const Jsonx._();

  static String encode<T>(T value) => jsonEncode(value, toEncodable: _toEncodable);

  static T decode<T>(String text) => jsonDecode(text, reviver: _reviver) as T;
}
