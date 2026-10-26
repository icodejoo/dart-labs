import 'dart:convert';

/// mpv 键值列表（key-value list）选项名：本源选项按"增删自己的键"处理，不整体覆盖。
const Set<String> kMpvKeyValueListOptions = {'demuxer-lavf-o', 'stream-lavf-o'};

/// 解析 mpv 键值列表语法（`k1=v1,k2=%3%a,b,k3="x y"`）里的键值对，按出现顺序返回。
///
/// 值支持四种写法：普通（到逗号为止）、`%字节数%值`、`"…"`/`'…'` 引号、`[…]`/`{…}` 嵌套。
/// 空串返回空列表；语法不合法（缺 `=`、`%` 长度越界、引号/括号未闭合）返回 `null`。
///
/// - [source]: 键值列表字符串 / key-value list string
///
/// 返回键值对（值已去掉引号/长度前缀），非法时为 `null`。
///
/// 示例：`parseMpvKeyValueList('a=1,b=%3%x,y')` 得到 `a=1`、`b=x,y` 两项
List<MapEntry<String, String>>? parseMpvKeyValueList(String source) {
  final out = <MapEntry<String, String>>[];
  var i = 0;
  while (i < source.length) {
    final eq = source.indexOf('=', i);
    if (eq <= i) return null;
    final key = source.substring(i, eq);
    if (key.contains(',')) return null;
    final value = _readValue(source, eq + 1);
    if (value == null) return null;
    out.add(MapEntry(key, value.text));
    i = value.end;
    if (i < source.length) {
      // 逗号之后必须还有下一项。
      if (source[i] != ',' || ++i >= source.length) return null;
    }
  }
  return out;
}

/// 从 mpv 打印出的键值列表字符串里宽松地找出 [key] 的值；找不到返回 `null`。
///
/// mpv 打印时不一定给含逗号的值加引（如 `protocol_whitelist=file,crypto`），所以不按严格语法切，
/// 而是把"逗号后紧跟 `名字=`"当作下一项的起点。只用于还原被覆盖的同名键。
///
/// - [printed]: mpv 读出的属性字符串 / property string read back from mpv
/// - [key]: 要找的键 / key to look up
///
/// 返回该键原值，没有则 `null`。
///
/// 示例：`lookupMpvKeyValue('a=1,w=x,y,b=2', 'w')` 得到 `x,y`
String? lookupMpvKeyValue(String printed, String key) {
  final starts = <int>[0, for (final m in _itemStart.allMatches(printed)) m.start + 1];
  final prefix = '$key=';
  for (var n = 0; n < starts.length; n++) {
    final start = starts[n];
    if (!printed.startsWith(prefix, start)) continue;
    final valueStart = start + prefix.length;
    // 带 `%长度%` 前缀时按长度取，其余取到下一项起点前。
    if (printed.startsWith('%', valueStart)) {
      final sized = _readValue(printed, valueStart);
      if (sized != null) return sized.text;
    }
    final end = n + 1 < starts.length ? starts[n + 1] - 1 : printed.length;
    return printed.substring(valueStart, end);
  }
  return null;
}

/// 逗号后紧跟 `名字=` 的位置（下一项的起点）。
final RegExp _itemStart = RegExp(r',(?=[A-Za-z0-9_.\-]+=)');

/// 读到的值与其结束下标。
typedef _Value = ({String text, int end});

/// 从 [from] 起读一个值；非法返回 `null`。
_Value? _readValue(String s, int from) {
  if (from >= s.length) return (text: '', end: from);
  final c = s[from];
  if (c == '%') {
    final close = s.indexOf('%', from + 1);
    final len = close < 0 ? null : int.tryParse(s.substring(from + 1, close));
    if (len == null || len < 0) return null;
    final bytes = utf8.encode(s.substring(close + 1));
    if (len > bytes.length) return null;
    final text = utf8.decode(bytes.sublist(0, len), allowMalformed: true);
    return (text: text, end: close + 1 + text.length);
  }
  if (c == '"' || c == "'") {
    final close = s.indexOf(c, from + 1);
    return close < 0 ? null : (text: s.substring(from + 1, close), end: close + 1);
  }
  if (c == '[' || c == '{') {
    final closer = c == '[' ? ']' : '}';
    var depth = 0;
    for (var i = from; i < s.length; i++) {
      if (s[i] == c) depth++;
      if (s[i] == closer && --depth == 0) return (text: s.substring(from, i + 1), end: i + 1);
    }
    return null;
  }
  final comma = s.indexOf(',', from);
  final end = comma < 0 ? s.length : comma;
  return (text: s.substring(from, end), end: end);
}
