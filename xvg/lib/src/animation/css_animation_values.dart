import 'css_chars.dart';
import 'css_stylesheet.dart';

/// 在顶层逗号处分隔列表，忽略空项。
///
/// 参数 [value] 是待拆分的值，括号与引号内部保持完整。
/// 返回去掉首尾空白的非空项列表。
///
/// ```dart
/// final items = splitCssList('fade, steps(2, end)');
/// ```
List<String> splitCssList(String value) => _split(value, comma: true);

/// 在顶层空白处分隔词元。
///
/// 参数 [value] 是待拆分的值，括号与引号内部保持完整。
/// 返回去掉首尾空白的非空词元列表。
///
/// ```dart
/// final tokens = splitCssTokens('fade 2s steps(2, end)');
/// ```
List<String> splitCssTokens(String value) => _split(value, comma: false);

/// 分隔扫描使用的字符编码。
const _backslash = 92,
    _singleQuote = 39,
    _doubleQuote = 34,
    _leftParen = 40,
    _rightParen = 41,
    _listComma = 44,
    _newline = 10,
    _carriageReturn = 13,
    _formFeed = 12;

/// 单遍拆分值列表或词元。
List<String> _split(String value, {required bool comma}) {
  final result = <String>[];
  var start = 0, depth = 0, quote = 0;
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c == _backslash) {
      // 十六进制转义后的可选空白仍属于当前标识符。
      var digits = 0;
      while (i + 1 < value.length &&
          digits < 6 &&
          cssHexValue(value.codeUnitAt(i + 1)) >= 0) {
        i++;
        digits++;
      }
      if (digits == 0) {
        if (i + 1 < value.length) i++;
      } else if (i + 1 < value.length && isCssSpace(value.codeUnitAt(i + 1))) {
        i++;
        if (value.codeUnitAt(i) == _carriageReturn &&
            i + 1 < value.length &&
            value.codeUnitAt(i + 1) == _newline) {
          i++;
        }
      }
      continue;
    }
    if (quote != 0) {
      if (c == quote) quote = 0;
    } else if (c == _singleQuote || c == _doubleQuote) {
      quote = c;
    } else if (c == _leftParen) {
      depth++;
    } else if (c == _rightParen && depth > 0) {
      depth--;
    } else if (depth == 0 && (comma ? c == _listComma : isCssSpace(c))) {
      final item = value.substring(start, i).trim();
      if (item.isNotEmpty) result.add(item);
      start = i + 1;
    }
  }
  final item = value.substring(start).trim();
  if (item.isNotEmpty) result.add(item);
  return result;
}

/// 有单位时间及普通数值的语法。
const _numberSyntax = r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?';

/// 有单位的时间匹配器。
final _timePattern = RegExp('^($_numberSyntax)(ms|s)\$', caseSensitive: false);

/// 普通数值匹配器。
final _numberPattern = RegExp('^$_numberSyntax\$');

/// 解析带秒或毫秒单位的时间。
///
/// 参数 [token] 是单个时间词元，支持小数、指数和负数。
/// 返回精确到微秒的时长；无单位、非有限或超出整数范围时返回空值。
///
/// ```dart
/// final duration = parseCssTime('.5s');
/// ```
Duration? parseCssTime(String token) {
  final match = _timePattern.firstMatch(token.trim());
  if (match == null) return null;
  final number = double.tryParse(match[1]!);
  if (number == null || !number.isFinite) return null;
  final micros = number * (match[2]!.toLowerCase() == 'ms' ? 1000 : 1000000);
  if (!micros.isFinite || micros.abs() >= 9223372036854775808.0) return null;
  return Duration(microseconds: micros.round());
}

/// 阶跃函数的跳跃位置。
enum CssStepPosition {
  /// 每段开始时跳跃。
  start,

  /// 每段结束时跳跃。
  end,

  /// 两端都不跳跃。
  jumpNone,

  /// 两端都跳跃。
  jumpBoth,
}

/// 可比较的三次贝塞尔或阶跃缓动值。
class CssTimingFunction {
  /// 创建三次贝塞尔缓动。
  const CssTimingFunction.cubicBezier(this.x1, this.y1, this.x2, this.y2)
    : stepCount = null,
      stepPosition = null;

  /// 创建阶跃缓动。
  const CssTimingFunction.steps(
    int count, [
    CssStepPosition position = CssStepPosition.end,
  ]) : stepCount = count,
       stepPosition = position,
       x1 = 0,
       y1 = 0,
       x2 = 1,
       y2 = 1;

  /// 匀速缓动。
  static const linear = CssTimingFunction.cubicBezier(0, 0, 1, 1);

  /// 默认缓动。
  static const ease = CssTimingFunction.cubicBezier(.25, .1, .25, 1);

  /// 缓入。
  static const easeIn = CssTimingFunction.cubicBezier(.42, 0, 1, 1);

  /// 缓出。
  static const easeOut = CssTimingFunction.cubicBezier(0, 0, .58, 1);

  /// 缓入缓出。
  static const easeInOut = CssTimingFunction.cubicBezier(.42, 0, .58, 1);

  /// 开始时跳至终值。
  static const stepStart = CssTimingFunction.steps(1, CssStepPosition.start);

  /// 结束时跳至终值。
  static const stepEnd = CssTimingFunction.steps(1);

  /// 第一控制点横坐标。
  final double x1;

  /// 第一控制点纵坐标。
  final double y1;

  /// 第二控制点横坐标。
  final double x2;

  /// 第二控制点纵坐标。
  final double y2;

  /// 阶跃数量，贝塞尔缓动为空。
  final int? stepCount;

  /// 阶跃位置，贝塞尔缓动为空。
  final CssStepPosition? stepPosition;

  /// 是否为阶跃缓动。
  bool get isSteps => stepCount != null;

  /// 是否为沿对角线的匀速贝塞尔曲线。
  bool get isLinear => !isSteps && x1 == y1 && x2 == y2;

  /// 比较缓动参数。
  @override
  bool operator ==(Object other) =>
      other is CssTimingFunction &&
      x1 == other.x1 &&
      y1 == other.y1 &&
      x2 == other.x2 &&
      y2 == other.y2 &&
      stepCount == other.stepCount &&
      stepPosition == other.stepPosition;

  /// 根据全部参数生成散列。
  @override
  int get hashCode => Object.hash(x1, y1, x2, y2, stepCount, stepPosition);

  /// 返回便于诊断的缓动文本。
  @override
  String toString() => isSteps
      ? 'steps($stepCount, ${stepPosition!.name})'
      : 'cubic-bezier($x1, $y1, $x2, $y2)';
}

/// 关键字缓动表。
const _timings = {
  'linear': CssTimingFunction.linear,
  'ease': CssTimingFunction.ease,
  'ease-in': CssTimingFunction.easeIn,
  'ease-out': CssTimingFunction.easeOut,
  'ease-in-out': CssTimingFunction.easeInOut,
  'step-start': CssTimingFunction.stepStart,
  'step-end': CssTimingFunction.stepEnd,
};

/// 阶跃位置关键字表。
const _positions = {
  'start': CssStepPosition.start,
  'jump-start': CssStepPosition.start,
  'end': CssStepPosition.end,
  'jump-end': CssStepPosition.end,
  'jump-none': CssStepPosition.jumpNone,
  'jump-both': CssStepPosition.jumpBoth,
};

/// 匹配单个函数值。
final _function = RegExp(r'^([a-z-]+)\((.*)\)$', dotAll: true);

/// 解析缓动关键字、三次贝塞尔或阶跃函数。
///
/// 参数 [value] 是一个完整的缓动值，关键字不区分大小写。
/// 返回合法的缓动参数；控制点越界、参数错误或未知值返回空值。
///
/// ```dart
/// final timing = parseCssTimingFunction('steps(3, jump-none)');
/// ```
CssTimingFunction? parseCssTimingFunction(String value) {
  final lower = value.trim().toLowerCase();
  if (_timings.containsKey(lower)) return _timings[lower];
  final match = _function.firstMatch(lower);
  if (match == null) return null;
  final body = match[2]!;
  final args = splitCssList(body);
  // 列表拆分会丢弃空项，函数参数则不允许空项。
  if (args.length != body.split(',').length) return null;
  if (match[1] == 'cubic-bezier' && args.length == 4) {
    final numbers = args.map(_finiteNumber).toList();
    if (numbers.any((n) => n == null)) return null;
    final x1 = numbers[0]!, x2 = numbers[2]!;
    if (x1 < 0 || x1 > 1 || x2 < 0 || x2 > 1) return null;
    return CssTimingFunction.cubicBezier(x1, numbers[1]!, x2, numbers[3]!);
  }
  if (match[1] == 'steps' && (args.length == 1 || args.length == 2)) {
    if (!_integerPattern.hasMatch(args[0])) return null;
    final count = int.tryParse(args[0]);
    final position = args.length == 1
        ? CssStepPosition.end
        : _positions[args[1]];
    if (count == null ||
        count <= 0 ||
        position == null ||
        (position == CssStepPosition.jumpNone && count < 2)) {
      return null;
    }
    return CssTimingFunction.steps(count, position);
  }
  return null;
}

/// 正整数允许的词法形式。
final _integerPattern = RegExp(r'^\+?\d+$');

/// 解析有限数值。
double? _finiteNumber(String value) {
  if (!_numberPattern.hasMatch(value)) return null;
  final number = double.tryParse(value);
  return number != null && number.isFinite ? number : null;
}

/// 动画的播放方向。
enum CssAnimationDirection {
  /// 正向播放。
  normal,

  /// 反向播放。
  reverse,

  /// 先正后反交替播放。
  alternate,

  /// 先反后正交替播放。
  alternateReverse,
}

/// 动画有效时间之外的填充方式。
enum CssAnimationFillMode {
  /// 不填充。
  none,

  /// 结束后保留终态。
  forwards,

  /// 开始前使用初态。
  backwards,

  /// 开始前及结束后均填充。
  both,
}

/// 一项解析完成的动画配置。
class CssAnimation {
  /// 创建动画配置。
  const CssAnimation({
    required this.name,
    required this.duration,
    required this.delay,
    required this.timing,
    required this.iterationCount,
    required this.direction,
    required this.fillMode,
    required this.paused,
  });

  /// 区分大小写的动画名。
  final String name;

  /// 一次播放时长。
  final Duration duration;

  /// 播放延迟，可为负数。
  final Duration delay;

  /// 全局缓动。
  final CssTimingFunction timing;

  /// 重复次数，无限循环使用正无穷。
  final double iterationCount;

  /// 播放方向。
  final CssAnimationDirection direction;

  /// 时间范围之外的填充。
  final CssAnimationFillMode fillMode;

  /// 是否暂停。
  final bool paused;
}

/// 动画属性名及重复使用的关键字。
const _animation = 'animation',
    _name = 'animation-name',
    _duration = 'animation-duration',
    _delay = 'animation-delay',
    _timing = 'animation-timing-function',
    _count = 'animation-iteration-count',
    _direction = 'animation-direction',
    _fill = 'animation-fill-mode',
    _play = 'animation-play-state',
    _none = 'none',
    _infinite = 'infinite',
    _paused = 'paused',
    _running = 'running';

/// 播放方向关键字。
const _directions = {
  'normal': CssAnimationDirection.normal,
  'reverse': CssAnimationDirection.reverse,
  'alternate': CssAnimationDirection.alternate,
  'alternate-reverse': CssAnimationDirection.alternateReverse,
};

/// 填充方式关键字。
const _fills = {
  _none: CssAnimationFillMode.none,
  'forwards': CssAnimationFillMode.forwards,
  'backwards': CssAnimationFillMode.backwards,
  'both': CssAnimationFillMode.both,
};

/// 每个长写属性的初始值。
const Map<String, Object> _defaults = {
  _name: _none,
  _duration: Duration.zero,
  _delay: Duration.zero,
  _timing: CssTimingFunction.ease,
  _count: 1.0,
  _direction: CssAnimationDirection.normal,
  _fill: CssAnimationFillMode.none,
  _play: false,
};

/// 根据已排序声明解析动画简写和长写。
///
/// 参数 [declarations] 须已按层叠顺序排列，后者覆盖前者；重要标记不另行排序。
/// 返回按名称列顺序展开的非空动画，其他列循环取值，非法声明整条忽略。
///
/// ```dart
/// final animations = parseCssAnimations([
///   CssDeclaration('animation', 'fade 2s linear infinite'),
/// ]);
/// ```
List<CssAnimation> parseCssAnimations(Iterable<CssDeclaration> declarations) {
  final columns = <String, List<Object>>{
    for (final entry in _defaults.entries) entry.key: [entry.value],
  };
  for (final declaration in declarations) {
    final property = declaration.property.toLowerCase();
    final parts = splitCssList(declaration.value);
    if (parts.isEmpty || !_validList(declaration.value, parts)) continue;
    if (property == _animation) {
      final rows = parts.map(_shorthand).toList();
      if (rows.any((row) => row == null)) continue;
      for (final key in _defaults.keys) {
        columns[key] = [for (final row in rows) row![key] ?? _defaults[key]!];
      }
    } else if (_defaults.containsKey(property)) {
      final values = parts.map((part) => _longhand(property, part)).toList();
      if (values.any((value) => value == null)) continue;
      columns[property] = values.cast<Object>();
    }
  }
  final result = <CssAnimation>[];
  for (var i = 0; i < columns[_name]!.length; i++) {
    final name = columns[_name]![i] as String;
    if (name.toLowerCase() == _none) continue;
    result.add(
      CssAnimation(
        name: name,
        duration: _column<Duration>(columns, _duration, i),
        delay: _column<Duration>(columns, _delay, i),
        timing: _column<CssTimingFunction>(columns, _timing, i),
        iterationCount: _column<double>(columns, _count, i),
        direction: _column<CssAnimationDirection>(columns, _direction, i),
        fillMode: _column<CssAnimationFillMode>(columns, _fill, i),
        paused: _column<bool>(columns, _play, i),
      ),
    );
  }
  return result;
}

/// 验证逗号列表没有空项，避开函数内部的逗号。
bool _validList(String value, List<String> parts) {
  var depth = 0, quote = 0, nonempty = false, count = 0;
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c == _backslash) {
      nonempty = true;
      i++;
      continue;
    }
    if (quote != 0) {
      if (c == quote) quote = 0;
    } else if (c == _singleQuote || c == _doubleQuote) {
      quote = c;
    } else if (c == _leftParen) {
      depth++;
    } else if (c == _rightParen) {
      if (--depth < 0) return false;
    } else if (depth == 0 && c == _listComma) {
      if (!nonempty) return false;
      count++;
      nonempty = false;
      continue;
    }
    if (!isCssSpace(c)) nonempty = true;
  }
  return nonempty && depth == 0 && quote == 0 && count + 1 == parts.length;
}

/// 循环读取一列。
T _column<T>(Map<String, List<Object>> columns, String key, int index) {
  final values = columns[key]!;
  return values[index % values.length] as T;
}

/// 解析某个长写列中的单个值。
Object? _longhand(String key, String value) {
  final lower = value.toLowerCase();
  switch (key) {
    case _name:
      return _animationName(value);
    case _duration:
      final time = parseCssTime(value);
      return time != null && !time.isNegative ? time : null;
    case _delay:
      return parseCssTime(value);
    case _timing:
      return parseCssTimingFunction(value);
    case _count:
      if (lower == _infinite) return double.infinity;
      final number = _finiteNumber(value);
      return number != null && number >= 0 ? number : null;
    case _direction:
      return _directions[lower];
    case _fill:
      return _fills[lower];
    case _play:
      return lower == _paused ? true : (lower == _running ? false : null);
  }
  return null;
}

/// 解析一项简写，优先填充关键字槽位，再解释为名字。
Map<String, Object>? _shorthand(String value) {
  final row = <String, Object>{};
  for (final token in splitCssTokens(value)) {
    final time = parseCssTime(token);
    if (time != null) {
      final key = row.containsKey(_duration) ? _delay : _duration;
      if (row.containsKey(key) || (key == _duration && time.isNegative)) {
        return null;
      }
      row[key] = time;
      continue;
    }
    var matched = false;
    for (final key in const [_timing, _count, _direction, _fill, _play]) {
      if (row.containsKey(key)) continue;
      final parsed = _longhand(key, token);
      if (parsed != null) {
        row[key] = parsed;
        matched = true;
        break;
      }
    }
    if (matched) continue;
    final name = _animationName(token);
    if (name == null || row.containsKey(_name)) return null;
    row[_name] = name;
  }
  return row.isEmpty ? null : row;
}

/// 解码字符串或标识符形式的动画名。
String? _animationName(String value) {
  if (value.isEmpty) return null;
  var source = value;
  final first = value.codeUnitAt(0);
  final quoted = first == _singleQuote || first == _doubleQuote;
  if (quoted) {
    if (value.length < 2 || value.codeUnitAt(value.length - 1) != first) {
      return null;
    }
    source = value.substring(1, value.length - 1);
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == _backslash) {
        i++;
      } else if (source.codeUnitAt(i) == first) {
        return null;
      }
    }
  } else if (_finiteNumber(value) != null) {
    return null;
  }
  final out = StringBuffer();
  for (var i = 0; i < source.length; i++) {
    final c = source.codeUnitAt(i);
    if (c != _backslash) {
      if (!quoted && !isCssNameChar(c)) return null;
      out.writeCharCode(c);
      continue;
    }
    if (++i >= source.length) return null;
    var code = 0, digits = 0;
    while (i < source.length &&
        digits < 6 &&
        cssHexValue(source.codeUnitAt(i)) >= 0) {
      code = code * 16 + cssHexValue(source.codeUnitAt(i++));
      digits++;
    }
    if (digits == 0) {
      final escaped = source.codeUnitAt(i);
      if (escaped == _newline ||
          escaped == _carriageReturn ||
          escaped == _formFeed) {
        return null;
      }
      out.writeCharCode(source.codeUnitAt(i));
      continue;
    }
    if (i < source.length && isCssSpace(source.codeUnitAt(i))) {
      if (source.codeUnitAt(i) == _carriageReturn &&
          i + 1 < source.length &&
          source.codeUnitAt(i + 1) == _newline) {
        i++;
      }
    } else {
      i--;
    }
    if (code == 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) {
      code = 0xfffd;
    }
    out.writeCharCode(code);
  }
  return out.toString();
}
