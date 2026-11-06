import 'css_animation_values.dart';
import 'css_stylesheet.dart';
import 'css_transform_list.dart';
import 'css_values.dart';

import 'smil_animation.dart';

part 'css_keyframes_compiler_channels.dart';

/// 由解析器注入依赖图形运行时的能力，空值表示不可用。
///
/// 参数 [sampleMotionPath] 把路径及旋转值转换为等弧长采样表；
/// [buildPathMorph] 将各帧路径转换为变形数据；两者失败时返回空值。
/// ```dart
/// const hooks = CssCompileHooks();
/// ```
class CssCompileHooks {
  /// 保存可选的路径采样及变形构建函数。
  const CssCompileHooks({
    this.sampleMotionPath,
    this.buildPathMorph,
    this.resolveColorToHex,
  });

  /// 解析期颜色归一化，复用文档解析器的原生/Dart 回退能力。
  /// Parse-time color normalization, sharing the document parser's native/Dart fallback.
  final String? Function(String value)? resolveColorToHex;

  /// 路径文本与旋转值（auto、auto-reverse 或度数字符串）转换为采样表。
  final List<SmilMotionSample>? Function(String pathData, String rotate)?
  sampleMotionPath;

  /// 各帧路径转换为变形数据；命令不兼容时返回空值。
  final PathMorphData? Function(List<String> frames)? buildPathMorph;
}

/// 已编译轨道的语义近似原因，返回于近似诊断。
///
/// ```dart
/// const reason = CssCompileApproximationReason.pathIncompatibleDiscrete;
/// ```
enum CssCompileApproximationReason {
  /// 不兼容路径按关键帧时刻切换，近似 CSS 的段中点切换。
  pathIncompatibleDiscrete,

  /// 延迟的 backwards/both 填充无法用 SMIL remove/freeze 表达。
  /// Delayed backwards/both fill cannot be represented by the SMIL remove/freeze model.
  backwardsFillUnsupported,
}

/// 保存已编译但语义近似的动画名、属性和原因。
///
/// 参数依次为 [animationName]、[property]、[reason]，用于返回近似诊断。
/// ```dart
/// const diagnostic = CssCompileApproximation('shape', 'd',
///   CssCompileApproximationReason.pathIncompatibleDiscrete);
/// ```
class CssCompileApproximation {
  /// 保存动画名称、属性及近似原因。
  const CssCompileApproximation(this.animationName, this.property, this.reason);

  /// 原始动画名称。
  final String animationName;

  /// 发生近似的属性。
  final String property;

  /// 近似原因。
  final CssCompileApproximationReason reason;
}

/// 动画或属性无法编译的诊断原因。
///
/// 返回于 [CssCompileSkip.reason]，例如：
/// ```dart
/// final reason = CssCompileSkipReason.unknownKeyframes;
/// ```
enum CssCompileSkipReason {
  /// 没有对应的关键帧定义。
  unknownKeyframes,

  /// 模型只存打包的颜色字面量，无法逐帧解析主题颜色。
  /// Colors in this model are packed literals and cannot resolve a theme per frame.
  currentColorRuntimeUnsupported,

  /// 显式变换原点/参考框需要坐标空间或包围盒解析。
  /// Explicit transform origin/box requires coordinate-space or bbox resolution.
  transformOriginUnsupported,

  /// 暂不编译暂停状态。
  paused,

  /// 迭代次数不大于零。
  iterationCountZero,

  /// 零时长且结束后不保留结果。
  zeroDurationWithoutForwards,

  /// 属性不在支持范围内。
  unsupportedProperty,

  /// 缺少静态运动路径。
  motionPathMissing,

  /// 运动路径或旋转语法不在支持范围内。
  unsupportedMotion,

  /// 未注入所需能力或路径采样失败。
  hookUnavailable,

  /// 数值列表公共长度超过上限。
  listTooLong,

  /// 属性没有合法关键帧值。
  noValidValue,

  /// 缺少端点且无法确定静态基准值。
  impliedEndpointUnavailable,

  /// 变换函数的有序种类不同。
  transformSignatureMismatch,

  /// 变换包含无法逐函数插值的矩阵。
  transformUnsupportedFunction,

  /// 变换全部为单位变换且无函数签名。
  transformAllNone,

  /// 变换被列表中更后的动画覆盖。
  overriddenByLaterAnimation,
}

/// 一条跳过诊断；参数为动画名称、原因及可选属性名。
///
/// 用于返回局部失败，不阻断其他属性的编译。
/// ```dart
/// const skip = CssCompileSkip('fade', CssCompileSkipReason.paused);
/// ```
class CssCompileSkip {
  /// 保存 [animationName]、[reason] 和可选的 [property]。
  const CssCompileSkip(this.animationName, this.reason, [this.property]);

  /// 原始动画名称。
  final String animationName;

  /// 跳过原因。
  final CssCompileSkipReason reason;

  /// 局部失败的属性；整条动画失败时为空。
  final String? property;
}

/// 编译返回的数值轨道、变换槽位与诊断。
///
/// 参数 [numeric] 按动画列表顺序排列，[transforms] 按函数顺序排列，
/// [skipped] 保存无法编译的条目。
/// ```dart
/// const result = CssCompileResult();
/// ```
class CssCompileResult {
  /// 创建编译结果，未提供的集合使用共享空列表。
  const CssCompileResult({
    this.numeric = const [],
    this.transforms = const [],
    this.skipped = const [],
    this.motion = const [],
    this.color = const [],
    this.paths = const [],
    this.lists = const [],
    this.approximations = const [],
  });

  /// 按动画列表顺序排列的数值属性轨道，后者覆盖前者。
  final List<SmilAnimation> numeric;

  /// 按函数顺序排列且替换静态变换的槽位。
  final List<SmilTransformAnimation> transforms;

  /// 被跳过的动画或属性。
  final List<CssCompileSkip> skipped;

  /// 按动画列表顺序排列的运动路径轨道。
  final List<SmilMotionAnimation> motion;

  /// 按动画列表顺序排列的颜色轨道。
  final List<SmilColorAnimation> color;

  /// 按动画列表顺序排列的路径变形轨道。
  final List<SmilPathAnimation> paths;

  /// 按动画列表顺序排列的数值列表轨道。
  final List<SmilListAnimation> lists;

  /// 已编译轨道的近似诊断。
  final List<CssCompileApproximation> approximations;

  /// 无动画时的共享结果。
  static const CssCompileResult empty = CssCompileResult();
}

/// 多处使用的属性名与声明前缀。
const _transformOrigin = 'transform-origin',
    _transformBox = 'transform-box',
    _transform = 'transform',
    _timingProperty = 'animation-timing-function',
    _animationPrefix = 'animation-',
    _transitionPrefix = 'transition';

/// 白名单与默认表共用的数值属性名。
const _opacity = 'opacity',
    _fillOpacity = 'fill-opacity',
    _strokeOpacity = 'stroke-opacity',
    _strokeWidth = 'stroke-width',
    _strokeDashoffset = 'stroke-dashoffset';

/// 可编译成单一数值的属性。
const _numericProperties = {
  _opacity,
  _fillOpacity,
  _strokeOpacity,
  _strokeWidth,
  _strokeDashoffset,
  'rx',
  'ry',
  'r',
  'cx',
  'cy',
  'x',
  'y',
  'width',
  'height',
};

/// 不需要布局或祖先样式即可确定的默认基准值。
const _defaults = {
  _opacity: 1.0,
  _fillOpacity: 1.0,
  _strokeOpacity: 1.0,
  _strokeWidth: 1.0,
  _strokeDashoffset: 0.0,
};

/// 混合缓动中线性区间使用的共享曲线。
const _linearEasing = CubicBezier(0, 0, 1, 1);

/// Compiles one element's CSS animations without mutating the inputs.
/// 编译一个元素的 CSS 动画，不修改输入集合。
///
/// [animations] 为层叠后的动画列表，[keyframes] 为文档关键帧表。
/// [attributes] 提供数值隐式端点及静态 SVG 变换是否存在的信息；
/// [cssProperties] 提供静态变换和运动属性，[hooks] 提供路径采样与变形能力。
/// 返回现有时间线对象与跳过诊断，局部无效值不影响其他属性。
/// ```dart
/// final result = compileCssAnimations(
///   animations: parseCssAnimations(parseCssDeclarations('animation: fade 1s')),
///   keyframes: parseCssStylesheet(
///     '@keyframes fade { from { opacity: 0 } to { opacity: 1 } }',
///   ).keyframes,
/// );
/// ```
CssCompileResult compileCssAnimations({
  required List<CssAnimation> animations,
  required Map<String, CssKeyframes> keyframes,
  Map<String, String> attributes = const {},
  Map<String, String> cssProperties = const {},
  CssCompileHooks hooks = const CssCompileHooks(),
}) {
  if (animations.isEmpty) return CssCompileResult.empty;
  final numeric = <SmilAnimation>[];
  final transforms = <SmilTransformAnimation>[];
  final motion = <SmilMotionAnimation>[];
  final color = <SmilColorAnimation>[];
  final paths = <SmilPathAnimation>[];
  final lists = <SmilListAnimation>[];
  final approximations = <CssCompileApproximation>[];
  List<CssCompileSkip>? skipped;

  /// 仅在首次跳过时分配诊断列表。
  void skip(CssAnimation a, CssCompileSkipReason reason, [String? property]) {
    (skipped ??= []).add(CssCompileSkip(a.name, reason, property));
  }

  // 每个关键帧定义只收集一次，也用于判定最后一个含变换的动画。
  final collected = <String, Map<String, List<_Stop<String>>>>{};
  var lastTransform = -1;
  for (var i = 0; i < animations.length; i++) {
    final name = animations[i].name;
    final frames = keyframes[name];
    if (frames == null) continue;
    final properties = collected.putIfAbsent(name, () => _collectStops(frames));
    final rawTransform = properties[_transform];
    final timingReason = _Timing(animations[i]).reason;
    // 只有浏览器也不应用的后续动画才允许回落；编译器不支持仍应覆盖。
    if ((timingReason == null || timingReason == CssCompileSkipReason.paused) &&
        rawTransform != null &&
        _parseTransforms(rawTransform, attributes, cssProperties).reason !=
            CssCompileSkipReason.noValidValue) {
      lastTransform = i;
    }
  }
  for (var i = 0; i < animations.length; i++) {
    final a = animations[i];
    final properties = collected[a.name];
    if (properties == null) {
      skip(a, CssCompileSkipReason.unknownKeyframes);
      continue;
    }
    final timeline = _Timing(a);
    final reason = timeline.reason;
    if (reason != null) {
      skip(a, reason);
      continue;
    }
    if (a.delay > Duration.zero &&
        (a.fillMode == CssAnimationFillMode.backwards ||
            a.fillMode == CssAnimationFillMode.both)) {
      approximations.add(
        CssCompileApproximation(
          a.name,
          'animation-fill-mode',
          CssCompileApproximationReason.backwardsFillUnsupported,
        ),
      );
    }
    for (final entry in properties.entries) {
      final property = entry.key;
      if (property == _transform) {
        if (properties.containsKey(_transformOrigin) ||
            properties.containsKey(_transformBox)) {
          skip(a, CssCompileSkipReason.transformOriginUnsupported, property);
          continue;
        }
        // 后续变换独立报告失败原因；覆盖优先级已由预扫描确定。
        final parsed = _parseTransforms(entry.value, attributes, cssProperties);
        if (parsed.reason != null) {
          skip(a, parsed.reason!, property);
          continue;
        }
        if (i != lastTransform) {
          skip(a, CssCompileSkipReason.overriddenByLaterAnimation, property);
          continue;
        }
        final stops = parsed.stops!;
        final timing = _intervals(stops, a.timing);
        final splines = timing.keySplines;
        final signature = stops.first.value;
        for (var slot = 0; slot < signature.length; slot++) {
          transforms.add(
            SmilTransformAnimation(
              type: _transformType(signature[slot].kind),
              values: [for (final stop in stops) _components(stop.value[slot])],
              duration: timeline.duration,
              begin: timeline.begin,
              beginSpec: timeline.beginSpec,
              eventGroup: timeline.eventGroup,
              fillFreeze: timeline.fillFreeze,
              repeatCount: timeline.repeatCount,
              direction: timeline.direction,
              replacesStaticTransform: true,
              keyTimes: timing.keyTimes,
              calcMode: timing.calcMode,
              keySplines: splines,
            ),
          );
        }
      } else if (_numericProperties.contains(property)) {
        final channel = _Channel(
          a,
          property,
          entry.value,
          timeline,
          attributes,
          cssProperties,
          hooks,
        );
        final parsed = _channelStops<double>(channel, parseCssLengthPx, () {
          final raw = attributes[property];
          return (raw == null ? null : parseCssLengthPx(raw)) ??
              _defaults[property];
        });
        if (parsed.reason != null) {
          skip(a, parsed.reason!, property);
          continue;
        }
        final stops = parsed.stops!;
        final timing = channel.intervals(stops);
        numeric.add(
          SmilAnimation(
            attributeName: property,
            values: [for (final stop in stops) stop.value],
            duration: timeline.duration,
            begin: timeline.begin,
            beginSpec: timeline.beginSpec,
            eventGroup: timeline.eventGroup,
            fillFreeze: timeline.fillFreeze,
            repeatCount: timeline.repeatCount,
            direction: timeline.direction,
            keyTimes: timing.keyTimes,
            calcMode: timing.calcMode,
            keySplines: timing.keySplines,
          ),
        );
      } else if (_channelProperties.contains(property)) {
        final channel = _Channel(
          a,
          property,
          entry.value,
          timeline,
          attributes,
          cssProperties,
          hooks,
        );
        final result = switch (property) {
          _offsetDistance => _compileMotion(channel),
          _pathProperty => _compilePath(channel),
          _dasharray => _compileList(channel),
          _ => _compileColor(channel),
        };
        motion.addAll(result.motion);
        color.addAll(result.color);
        paths.addAll(result.paths);
        lists.addAll(result.lists);
        approximations.addAll(result.approximations);
        if (result.skipped.isNotEmpty) {
          (skipped ??= []).addAll(result.skipped);
        }
      } else {
        skip(a, CssCompileSkipReason.unsupportedProperty, property);
      }
    }
  }
  return CssCompileResult(
    numeric: numeric,
    transforms: transforms,
    motion: motion,
    color: color,
    paths: paths,
    lists: lists,
    approximations: approximations,
    skipped: skipped ?? const [],
  );
}

/// Timing and event group shared by the channels of one declaration.
/// 所有编译通道共用的时序映射，保留阶段三的零时长规则。
class _Timing {
  /// 从层叠后的动画配置计算时序字段和整条动画的跳过原因。
  /// Maps timing and creates a distinct event group for this declaration.
  _Timing(CssAnimation a)
    : eventGroup = SmilEventGroup(a.name),
      duration = a.duration,
      begin = a.delay,
      beginSpec = SmilBeginSpec.offset(a.delay),
      fillFreeze =
          a.fillMode == CssAnimationFillMode.forwards ||
          a.fillMode == CssAnimationFillMode.both,
      repeatCount = a.duration == Duration.zero
          ? SmilRepeatCount.once
          : a.iterationCount == double.infinity
          ? const SmilRepeatCount.indefinite()
          : SmilRepeatCount.finite(a.iterationCount),
      direction = _direction(a.direction) {
    reason = a.paused
        ? CssCompileSkipReason.paused
        : a.iterationCount <= 0
        ? CssCompileSkipReason.iterationCountZero
        : duration == Duration.zero && !fillFreeze
        ? CssCompileSkipReason.zeroDurationWithoutForwards
        : null;
  }

  /// One declaration's event group, shared by all successful channels.
  /// 一项声明的事件组，由所有成功编译的通道共享。
  final SmilEventGroup eventGroup;

  /// 单轮时长。
  final Duration duration;

  /// 全局开始偏移。
  final Duration begin;

  /// 与开始偏移一致的开始描述。
  final SmilBeginSpec beginSpec;

  /// 结束后是否保留结果。
  final bool fillFreeze;

  /// 已处理无限次数和零时长的重复规则。
  final SmilRepeatCount repeatCount;

  /// 整体播放方向。
  final SmilDirection direction;

  /// 整条动画不能编译的原因。
  late final CssCompileSkipReason? reason;
}

/// 某个属性独有的关键帧位置、值与出段缓动。
class _Stop<T> {
  /// 保存位置、值及可选缓动。
  const _Stop(this.offset, this.value, this.easing);

  /// 归一化位置。
  final double offset;

  /// 原始或解析后的值。
  final T value;

  /// 该位置开始的区间缓动，空值回退动画缓动。
  final CssTimingFunction? easing;
}

/// 按属性收集声明，忽略重要声明与动画、过渡控制声明。
Map<String, List<_Stop<String>>> _collectStops(CssKeyframes frames) {
  final result = <String, List<_Stop<String>>>{};
  for (final stop in frames.stops) {
    CssTimingFunction? easing;
    final values = <String, String>{};
    for (final declaration in stop.declarations) {
      if (declaration.important) continue;
      final property = declaration.property;
      if (property == _timingProperty) {
        easing = parseCssTimingFunction(declaration.value) ?? easing;
      } else if (!property.startsWith(_animationPrefix) &&
          property != 'animation' &&
          !property.startsWith(_transitionPrefix)) {
        values[property] = declaration.value;
      }
    }
    for (final entry in values.entries) {
      (result[entry.key] ??= []).add(_Stop(stop.offset, entry.value, easing));
    }
  }
  return result;
}

/// 检查属性自己的序列是否缺少首尾端点。
bool _needsEndpoints<T>(List<_Stop<T>> stops) =>
    stops.first.offset > 0 || stops.last.offset < 1;

/// 以静态基准补齐首尾；空缓动表示回退到动画自身缓动。
void _addEndpoints<T>(List<_Stop<T>> stops, T base) {
  if (stops.first.offset > 0) stops.insert(0, _Stop(0, base, null));
  if (stops.last.offset < 1) stops.add(_Stop(1, base, null));
}

/// 同一动画内可按值复用的区间数据，避免多属性块重复保存时序。
class _Intervals {
  /// 保存时间点和出段缓动，末点缓动不参与比较。
  _Intervals(this.keyTimes, this.easings);

  /// 与关键帧值一一对应的时间点。
  final List<double> keyTimes;

  /// 每段已回退到动画默认值的缓动。
  final List<CssTimingFunction> easings;

  /// 全线性时为空；否则每段恰好一个引擎缓动。
  late final List<SmilSegmentEasing>? keySplines =
      easings.every((timing) => timing.isLinear)
      ? null
      : [for (final timing in easings) _easing(timing)];

  /// 有逐段缓动时为样条模式，否则线性。
  SmilCalcMode get calcMode =>
      keySplines == null ? SmilCalcMode.linear : SmilCalcMode.spline;
}

/// 由关键帧序列算出时间点与逐段缓动（缺省回退到动画级缓动）。
_Intervals _intervals<T>(List<_Stop<T>> stops, CssTimingFunction fallback) =>
    _Intervals(
      [for (final stop in stops) stop.offset],
      [for (var i = 0; i < stops.length - 1; i++) stops[i].easing ?? fallback],
    );

/// 将 CSS 缓动转换为引擎区间缓动。
SmilSegmentEasing _easing(CssTimingFunction timing) {
  if (timing.isLinear) return _linearEasing;
  if (!timing.isSteps) {
    return CubicBezier(timing.x1, timing.y1, timing.x2, timing.y2);
  }
  return SmilStepsEasing(timing.stepCount!, switch (timing.stepPosition!) {
    CssStepPosition.start => SmilStepPosition.start,
    CssStepPosition.end => SmilStepPosition.end,
    CssStepPosition.jumpNone => SmilStepPosition.jumpNone,
    CssStepPosition.jumpBoth => SmilStepPosition.jumpBoth,
  });
}

/// 保留 CSS 的整体时间方向。
SmilDirection _direction(CssAnimationDirection direction) =>
    switch (direction) {
      CssAnimationDirection.normal => SmilDirection.normal,
      CssAnimationDirection.reverse => SmilDirection.reverse,
      CssAnimationDirection.alternate => SmilDirection.alternate,
      CssAnimationDirection.alternateReverse => SmilDirection.alternateReverse,
    };

/// 变换解析结果，失败时只返回诊断原因。
typedef _TransformResult = ({
  List<_Stop<List<CssTransformOp>>>? stops,
  CssCompileSkipReason? reason,
});

/// 校验变换签名，并在可确定静态基准时补齐端点。
_TransformResult _parseTransforms(
  List<_Stop<String>> raw,
  Map<String, String> attributes,
  Map<String, String> cssProperties,
) {
  final rawOrigin =
      cssProperties[_transformOrigin] ?? attributes[_transformOrigin];
  List<double>? origin;
  if (rawOrigin != null) {
    final tokens = rawOrigin.trim().split(RegExp(r'\s+'));
    if (tokens.length == 2) {
      final x = parseCssLengthPx(tokens[0]);
      final y = parseCssLengthPx(tokens[1]);
      if (x != null && y != null) origin = [x, y];
    }
  }
  if (cssProperties.containsKey(_transformBox) ||
      attributes.containsKey(_transformBox) ||
      (rawOrigin != null && origin == null)) {
    return (
      stops: null,
      reason: CssCompileSkipReason.transformOriginUnsupported,
    );
  }
  final stops = <_Stop<List<CssTransformOp>>>[];
  List<CssTransformOp>? signature;
  for (final stop in raw) {
    final ops = parseCssTransformList(stop.value);
    if (ops == null) continue;
    if (ops.any((op) => op.kind == CssTransformKind.matrix)) {
      return (
        stops: null,
        reason: CssCompileSkipReason.transformUnsupportedFunction,
      );
    }
    if (ops.isNotEmpty) signature ??= ops;
    stops.add(_Stop(stop.offset, ops, stop.easing));
  }
  if (stops.isEmpty) {
    return (stops: null, reason: CssCompileSkipReason.noValidValue);
  }
  if (signature == null) {
    return (stops: null, reason: CssCompileSkipReason.transformAllNone);
  }
  final identity = [
    for (final op in signature)
      CssTransformOp(op.kind, switch (op.kind) {
        CssTransformKind.scale => const [1, 1],
        CssTransformKind.translate => const [0, 0],
        _ => const [0],
      }),
  ];
  for (var i = 0; i < stops.length; i++) {
    final stop = stops[i];
    if (stop.value.isEmpty) {
      stops[i] = _Stop(stop.offset, identity, stop.easing);
    } else if (!_sameSignature(signature, stop.value)) {
      return (
        stops: null,
        reason: CssCompileSkipReason.transformSignatureMismatch,
      );
    }
  }
  if (_needsEndpoints(stops)) {
    final rawBase = cssProperties[_transform];
    final parsed = rawBase == null ? null : parseCssTransformList(rawBase);
    // 不能用单位变换猜测 SVG 空格语法、不同签名或无法解析的 CSS 基准。
    if ((rawBase != null && parsed == null) ||
        (parsed == null && attributes.containsKey(_transform)) ||
        (parsed != null &&
            parsed.isNotEmpty &&
            !_sameSignature(signature, parsed))) {
      return (
        stops: null,
        reason: CssCompileSkipReason.impliedEndpointUnavailable,
      );
    }
    _addEndpoints(stops, parsed == null || parsed.isEmpty ? identity : parsed);
  }
  if (origin != null) {
    for (var i = 0; i < stops.length; i++) {
      final stop = stops[i];
      stops[i] = _Stop(stop.offset, [
        CssTransformOp(CssTransformKind.translate, origin),
        ...stop.value,
        CssTransformOp(CssTransformKind.translate, [-origin[0], -origin[1]]),
      ], stop.easing);
    }
  }
  return (stops: stops, reason: null);
}

/// 比较规范化后函数种类的有序序列。
bool _sameSignature(List<CssTransformOp> a, List<CssTransformOp> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].kind != b[i].kind) return false;
  }
  return true;
}

/// 将已排除矩阵的种类映射到引擎；矩阵分支不可到达。
SmilTransformType _transformType(CssTransformKind kind) => switch (kind) {
  CssTransformKind.translate => SmilTransformType.translate,
  CssTransformKind.scale => SmilTransformType.scale,
  CssTransformKind.rotate => SmilTransformType.rotate,
  CssTransformKind.skewX => SmilTransformType.skewX,
  CssTransformKind.skewY => SmilTransformType.skewY,
  CssTransformKind.matrix => SmilTransformType.translate,
};

/// 归一化为引擎要求的三个分量，旋转圆心固定为原点。
List<double> _components(CssTransformOp op) => [
  op.args[0],
  op.args.length > 1 ? op.args[1] : 0,
  0,
];
