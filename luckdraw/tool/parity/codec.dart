/// JSON 字符串转义表。
const Map<String, String> _escapes = {
  '"': '"',
  '\\': '\\',
  '/': '/',
  'b': '\b',
  'f': '\f',
  'n': '\n',
  'r': '\r',
  't': '\t',
};

/// 将 JSON [source] 解为基础值；不完整、重复键或非法数值抛出 [FormatException]。
///
/// 示例：`decodeParityJson('{"frame":0}')` 返回字符串键的 Map。
Object? decodeParityJson(String source) => _JsonReader(source).read();

/// 将 null、布尔、有限数值、字符串、列表或字符串键 Map [value] 编码为 JSON。
///
/// 不支持的值抛出 [FormatException]；示例：`encodeParityJson([16]) == '[16]'`。
String encodeParityJson(Object? value) {
  if (value == null || value is bool) return '$value';
  if (value is num && value.isFinite) return '$value';
  if (value is String) {
    final buffer = StringBuffer('"');
    for (final unit in value.codeUnits) {
      if (unit == 34 || unit == 92) {
        buffer.write('\\${String.fromCharCode(unit)}');
      } else if (unit < 32) {
        buffer.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return '$buffer"';
  }
  if (value is List<Object?>) {
    return '[${value.map(encodeParityJson).join(',')}]';
  }
  if (value is Map<String, Object?>) {
    return '{${value.entries.map((e) => '${encodeParityJson(e.key)}:${encodeParityJson(e.value)}').join(',')}}';
  }
  throw const FormatException('Unsupported JSON value');
}

/// 无外部依赖的严格 JSON 读取器。
class _JsonReader {
  /// 使用完整 JSON 文本构造读取器。
  _JsonReader(this.source);

  /// 待解析的源文本。
  final String source;

  /// 下一个待消费字符的位置。
  int offset = 0;

  /// 跳过 JSON 允许的空白字符。
  void _space() {
    while (offset < source.length && ' \r\n\t'.contains(source[offset])) {
      offset++;
    }
  }

  /// 消费一个指定字符，返回是否匹配。
  bool _take(String character) {
    _space();
    if (offset == source.length || source[offset] != character) return false;
    offset++;
    return true;
  }

  /// 解析完整值并拒绝尾随内容。
  Object? read() {
    final result = _value();
    _space();
    if (offset != source.length) throw const FormatException('Trailing JSON');
    return result;
  }

  /// 解析当前位置的单个 JSON 值。
  Object? _value() {
    _space();
    if (offset == source.length) throw const FormatException('Incomplete JSON');
    if (source[offset] == '"') return _string();
    if (_take('{')) {
      final result = <String, Object?>{};
      if (_take('}')) return result;
      do {
        _space();
        final key = _string();
        if (result.containsKey(key) || !_take(':')) {
          throw const FormatException('Invalid JSON object');
        }
        result[key] = _value();
        if (_take('}')) return result;
      } while (_take(','));
      throw const FormatException('Unclosed JSON object');
    }
    if (_take('[')) {
      final result = <Object?>[];
      if (_take(']')) return result;
      do {
        result.add(_value());
        if (_take(']')) return result;
      } while (_take(','));
      throw const FormatException('Unclosed JSON array');
    }
    for (final entry in const {
      'true': true,
      'false': false,
      'null': null,
    }.entries) {
      if (source.startsWith(entry.key, offset)) {
        offset += entry.key.length;
        return entry.value;
      }
    }
    final match = RegExp(
      r'-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?',
    ).matchAsPrefix(source, offset);
    if (match == null) throw const FormatException('Invalid JSON token');
    offset = match.end;
    final number = num.parse(match[0]!);
    if (!number.isFinite) throw const FormatException('Non-finite JSON number');
    return number;
  }

  /// 解析字符串及其转义字符。
  String _string() {
    if (!_take('"')) throw const FormatException('Expected JSON string');
    final buffer = StringBuffer();
    while (offset < source.length) {
      final character = source[offset++];
      if (character == '"') return buffer.toString();
      if (character.codeUnitAt(0) < 32) {
        throw const FormatException('Control character in JSON string');
      }
      if (character != '\\') {
        buffer.write(character);
      } else {
        if (offset == source.length) break;
        final escape = source[offset++];
        if (escape == 'u' && offset + 4 <= source.length) {
          final hex = source.substring(offset, offset + 4);
          if (!RegExp(r'^[a-fA-F0-9]{4}$').hasMatch(hex)) {
            throw const FormatException('Invalid Unicode escape');
          }
          buffer.writeCharCode(int.parse(hex, radix: 16));
          offset += 4;
        } else if (_escapes.containsKey(escape)) {
          buffer.write(_escapes[escape]);
        } else {
          throw const FormatException('Invalid JSON escape');
        }
      }
    }
    throw const FormatException('Unclosed JSON string');
  }
}

/// PNG 文件的固定签名。
const List<int> kParityPngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

/// 解码 Canvas [dataUrl] 的 PNG；错误前缀、编码或文件签名抛出 [FormatException]。
///
/// 返回可交给 `File.writeAsBytes` 的字节，不接受其它 data URL 格式。
List<int> decodeParityPng(String dataUrl) {
  const prefix = 'data:image/png;base64,';
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  if (!dataUrl.startsWith(prefix)) {
    throw const FormatException('Expected PNG URL');
  }
  final encoded = dataUrl.substring(prefix.length);
  if (encoded.length % 4 != 0 ||
      !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(encoded)) {
    throw const FormatException('Invalid base64 PNG');
  }
  final result = <int>[];
  var bits = 0;
  var buffer = 0;
  for (final character in encoded.split('')) {
    if (character == '=') break;
    buffer = (buffer << 6) | alphabet.indexOf(character);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      result.add((buffer >> bits) & 255);
      buffer &= (1 << bits) - 1;
    }
  }
  final padding = encoded.endsWith('==') ? 2 : (encoded.endsWith('=') ? 1 : 0);
  if (buffer != 0 ||
      (padding == 2 && bits != 4) ||
      (padding == 1 && bits != 2) ||
      (padding == 0 && bits != 0) ||
      !hasParityPngSignature(result)) {
    throw const FormatException('Invalid PNG payload');
  }
  return result;
}

/// 判断 [bytes] 是否至少包含完整的 PNG 签名；不解码像素。
bool hasParityPngSignature(List<int> bytes) =>
    bytes.length >= kParityPngSignature.length &&
    Iterable<int>.generate(
      kParityPngSignature.length,
    ).every((i) => bytes[i] == kParityPngSignature[i]);
