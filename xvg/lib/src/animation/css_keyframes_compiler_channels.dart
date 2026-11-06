part of 'css_keyframes_compiler.dart';

/// 新通道的属性名与旋转关键字。
const _offsetDistance = 'offset-distance',
    _offsetPath = 'offset-path',
    _offsetRotate = 'offset-rotate',
    _pathProperty = 'd',
    _dasharray = 'stroke-dasharray',
    _fill = 'fill',
    _stroke = 'stroke',
    _stopColor = 'stop-color',
    _none = 'none',
    _auto = 'auto',
    _autoReverse = 'auto-reverse';

/// 交由阶段四处理的属性。
const _channelProperties = {
  _offsetDistance,
  _fill,
  _stroke,
  _stopColor,
  _pathProperty,
  _dasharray,
};

/// 补齐后的列表最大宽度，限制公共倍数的内存成本。
const _maxListLength = 32;

/// 数值列表中允许的空白分隔符。
final _listWhitespace = RegExp(r'\s+');

/// 一个属性的编译上下文，只在本次纯函数调用中使用。
class _Channel {
  /// 保存属性、时序、静态基准和注入能力。
  const _Channel(
    this.animation,
    this.property,
    this.raw,
    this.timing,
    this.attributes,
    this.cssProperties,
    this.hooks,
  );

  /// 当前动画配置。
  final CssAnimation animation;

  /// 当前属性名。
  final String property;

  /// 属性自己的原始关键帧序列。
  final List<_Stop<String>> raw;

  /// 共用的动画时序映射。
  final _Timing timing;

  /// 层叠后的静态 SVG 属性。
  final Map<String, String> attributes;

  /// 运动等仅在 CSS 中存在的静态属性。
  final Map<String, String> cssProperties;

  /// 外部注入的路径处理能力。
  final CssCompileHooks hooks;

  /// 构建当前属性的跳过结果。
  CssCompileResult skip(CssCompileSkipReason reason) => CssCompileResult(
    skipped: [CssCompileSkip(animation.name, reason, property)],
  );

  /// 为当前属性计算时间点与逐段缓动。
  _Intervals intervals<T>(List<_Stop<T>> stops) =>
      _intervals(stops, animation.timing);
}

/// 解析属性序列，忽略无效值，并按需从静态基准补齐端点。
({List<_Stop<T>>? stops, CssCompileSkipReason? reason}) _channelStops<T>(
  _Channel channel,
  T? Function(String) parse,
  T? Function() base,
) {
  final stops = <_Stop<T>>[];
  for (final stop in channel.raw) {
    final value = parse(stop.value);
    if (value != null) stops.add(_Stop(stop.offset, value, stop.easing));
  }
  if (stops.isEmpty) {
    return (stops: null, reason: CssCompileSkipReason.noValidValue);
  }
  if (_needsEndpoints(stops)) {
    final value = base();
    if (value == null) {
      return (
        stops: null,
        reason: CssCompileSkipReason.impliedEndpointUnavailable,
      );
    }
    _addEndpoints(stops, value);
  }
  return (stops: stops, reason: null);
}

/// Compiles percentage distance and a static path into a motion timeline.
/// 把百分数距离和静态运动路径编译为现有运动时间线。
CssCompileResult _compileMotion(_Channel c) {
  final rawPath = c.cssProperties[_offsetPath];
  if (rawPath == null) return c.skip(CssCompileSkipReason.motionPathMissing);
  final path = parseCssPathFunction(rawPath);
  final rotate = _motionRotate(c.cssProperties[_offsetRotate] ?? _auto);
  if (path == null || rotate == null) {
    return c.skip(CssCompileSkipReason.unsupportedMotion);
  }
  final parsed = _channelStops(c, parseCssPercent, () {
    final raw = c.cssProperties[_offsetDistance];
    return raw == null ? 0.0 : parseCssPercent(raw);
  });
  if (parsed.reason != null) return c.skip(parsed.reason!);
  final stops = parsed.stops!;
  final samples = c.hooks.sampleMotionPath?.call(path, rotate);
  if (samples == null || samples.length < 2) {
    return c.skip(CssCompileSkipReason.hookUnavailable);
  }
  final intervals = c.intervals(stops);
  final t = c.timing;
  return CssCompileResult(
    motion: [
      SmilMotionAnimation(
        samples: samples,
        keyPoints: [for (final stop in stops) stop.value],
        keyTimes: intervals.keyTimes,
        keySplines: intervals.keySplines,
        calcMode: intervals.calcMode,
        interpolateAngle: rotate == _auto || rotate == _autoReverse,
        duration: t.duration,
        begin: t.begin,
        beginSpec: t.beginSpec,
        eventGroup: t.eventGroup,
        fillFreeze: t.fillFreeze,
        repeatCount: t.repeatCount,
        direction: t.direction,
      ),
    ],
  );
}

/// 把支持的 CSS 旋转值转换为采样钩子的 SVG 旋转参数。
String? _motionRotate(String raw) {
  final text = raw.trim().toLowerCase();
  if (text == _auto) return _auto;
  if (text == 'reverse') return _autoReverse;
  final degrees = parseCssAngleDegrees(text);
  if (degrees == null) return null;
  return degrees == degrees.truncateToDouble()
      ? degrees.toInt().toString()
      : degrees.toString();
}

/// 解析颜色或表示无绘制的哨兵，保留与透明色的区别。
int? _channelColor(String raw) =>
    raw.trim().toLowerCase() == _none ? kSmilColorNone : parseCssColor(raw);

/// Compiles fill, stroke or stop colors into a color timeline.
/// 把填充、描边或渐变站点颜色编译为颜色时间线。
CssCompileResult _compileColor(_Channel c) {
  bool currentColor(String value) =>
      value.trim().toLowerCase() == 'currentcolor';
  if (c.raw.any((stop) => currentColor(stop.value)) ||
      ((_needsEndpoints(c.raw)) &&
          currentColor(c.attributes[c.property] ?? ''))) {
    return c.skip(CssCompileSkipReason.currentColorRuntimeUnsupported);
  }
  int? color(String raw) {
    final literal = _channelColor(raw);
    if (literal != null) return literal;
    final hex = c.hooks.resolveColorToHex?.call(raw);
    return hex == null ? null : parseCssColor(hex);
  }

  final parsed = _channelStops(c, color, () {
    final raw = c.attributes[c.property];
    return raw == null ? null : color(raw);
  });
  if (parsed.reason != null) return c.skip(parsed.reason!);
  final stops = parsed.stops!;
  final intervals = c.intervals(stops);
  final t = c.timing;
  return CssCompileResult(
    color: [
      SmilColorAnimation(
        attributeName: c.property,
        values: [for (final stop in stops) stop.value],
        keyTimes: intervals.keyTimes,
        keySplines: intervals.keySplines,
        calcMode: intervals.calcMode,
        duration: t.duration,
        begin: t.begin,
        beginSpec: t.beginSpec,
        eventGroup: t.eventGroup,
        fillFreeze: t.fillFreeze,
        repeatCount: t.repeatCount,
        direction: t.direction,
      ),
    ],
  );
}

/// Compiles path frames, reporting discrete fallback for incompatible paths.
/// 把路径函数编译为变形时间线，不兼容时返回离散近似诊断。
CssCompileResult _compilePath(_Channel c) {
  final parsed = _channelStops(c, parseCssPathFunction, () {
    final raw = c.attributes[_pathProperty];
    return raw == null || raw.trim().isEmpty ? null : raw;
  });
  if (parsed.reason != null) return c.skip(parsed.reason!);
  final build = c.hooks.buildPathMorph;
  if (build == null) return c.skip(CssCompileSkipReason.hookUnavailable);
  final stops = parsed.stops!;
  final frames = [for (final stop in stops) stop.value];
  final morph = build(frames);
  final intervals = c.intervals(stops);
  final t = c.timing;
  return CssCompileResult(
    paths: [
      SmilPathAnimation(
        frames: frames,
        morph: morph,
        keyTimes: intervals.keyTimes,
        keySplines: intervals.keySplines,
        calcMode: morph == null ? SmilCalcMode.discrete : intervals.calcMode,
        duration: t.duration,
        begin: t.begin,
        beginSpec: t.beginSpec,
        eventGroup: t.eventGroup,
        fillFreeze: t.fillFreeze,
        repeatCount: t.repeatCount,
        direction: t.direction,
      ),
    ],
    approximations: [
      if (morph == null)
        CssCompileApproximation(
          c.animation.name,
          c.property,
          CssCompileApproximationReason.pathIncompatibleDiscrete,
        ),
    ],
  );
}

/// 解析逗号或空白分隔的像素列表，拒绝空项和非法词元。
List<double>? _channelList(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final values = <double>[];
  for (final group in text.split(',')) {
    if (group.trim().isEmpty) return null;
    for (final token in group.trim().split(_listWhitespace)) {
      final value = parseCssLengthPx(token);
      if (value == null) return null;
      values.add(value);
    }
  }
  return values;
}

/// Repeats dash lists to a common width and compiles a list timeline.
/// 把虚线列表按最小公倍数重复补齐，再编译为列表时间线。
CssCompileResult _compileList(_Channel c) {
  final parsed = _channelStops(c, _channelList, () {
    final raw = c.attributes[_dasharray];
    return raw == null ? null : _channelList(raw);
  });
  if (parsed.reason != null) return c.skip(parsed.reason!);
  final stops = parsed.stops!;
  var width = 1;
  for (final stop in stops) {
    final length = stop.value.length;
    // 先除后乘；一旦超限立即退出，不按公共长度分配内存。
    width = (width ~/ width.gcd(length)) * length;
    if (width > _maxListLength) return c.skip(CssCompileSkipReason.listTooLong);
  }
  final intervals = c.intervals(stops);
  final t = c.timing;
  return CssCompileResult(
    lists: [
      SmilListAnimation(
        attributeName: c.property,
        values: [
          for (final stop in stops)
            [for (var i = 0; i < width; i++) stop.value[i % stop.value.length]],
        ],
        keyTimes: intervals.keyTimes,
        keySplines: intervals.keySplines,
        calcMode: intervals.calcMode,
        duration: t.duration,
        begin: t.begin,
        beginSpec: t.beginSpec,
        eventGroup: t.eventGroup,
        fillFreeze: t.fillFreeze,
        repeatCount: t.repeatCount,
        direction: t.direction,
      ),
    ],
  );
}

/// 与数值通道一致，全线性时不用样条模式。
