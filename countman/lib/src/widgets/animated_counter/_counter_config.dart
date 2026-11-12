part of 'animated_counter.dart';

// ── 配置解析 ──────────────────────────────────────────────────────────────────
// 平铺参数与 format / timeline 配置对象的合并：配置对象的非空字段优先，空字段回退到平铺参数。

/// 把 [CounterFormat]、[CounterTimeline] 与平铺参数合并成有效值。
extension _CounterConfigResolution on _BaseAnimatedCounter {
  /// 已解析的小数位数。
  int get _fmtFractionDigits => format?.fractionDigits ?? fractionDigits;
  /// 已解析的最少整数位数。
  int get _fmtWholeDigits => format?.wholeDigits ?? wholeDigits;
  /// 已解析的是否隐藏整数前导零。
  bool get _fmtHideLeadingZeroes => format?.hideLeadingZeroes ?? hideLeadingZeroes;
  /// 已解析的整数分组分隔符。
  String? get _fmtThousandSeparator => format?.thousandSeparator ?? thousandSeparator;
  /// 已解析的从右向左的分组位数
  List<int> get _fmtGroupingPattern => format?.groupingPattern ?? groupingPattern;
  /// 已解析的小数分隔符。
  String get _fmtDecimalSeparator => format?.decimalSeparator ?? decimalSeparator;
  /// 已解析的是否使用紧凑缩写。
  bool get _fmtCompactNotation => format?.compactNotation ?? compactNotation;
  /// 已解析的紧凑缩写的小数位数。
  int? get _fmtCompactFractionDigits => format?.compactFractionDigits ?? compactFractionDigits;
  /// 已解析的阈值到缩写的映射
  Map<num, String>? get _fmtCompactAbbreviations => format?.compactAbbreviations ?? compactAbbreviations;
  /// 已解析的是否显示正号。
  bool get _fmtShowPositiveSign => format?.showPositiveSign ?? showPositiveSign;
  /// 已解析的数字字形体系。
  NumeralSystem get _fmtNumeralSystem => format?.numeralSystem ?? numeralSystem;
  /// 已解析的将 digit（0–9）映射为字形的函数。
  String Function(int digit)? get _fmtNumeralMapper => format?.numeralMapper ?? numeralMapper;

  /// 用解析后的字段比较有效格式，忽略配置对象的实例身份。
  CounterFormat get _resolvedFormat => CounterFormat(
    fractionDigits: _fmtFractionDigits,
    wholeDigits: _fmtWholeDigits,
    hideLeadingZeroes: _fmtHideLeadingZeroes,
    thousandSeparator: _fmtThousandSeparator,
    groupingPattern: _fmtGroupingPattern,
    decimalSeparator: _fmtDecimalSeparator,
    compactNotation: _fmtCompactNotation,
    compactFractionDigits: _fmtCompactFractionDigits,
    compactAbbreviations: _fmtCompactAbbreviations,
    showPositiveSign: _fmtShowPositiveSign,
    numeralSystem: _fmtNumeralSystem,
    numeralMapper: _fmtNumeralMapper,
  );

  /// 已解析的正向滚动时长。
  Duration get _timeDuration => timeline?.duration ?? duration;

  /// 已解析的滚动曲线。
  Curve get _timeCurve => timeline?.curve ?? curve;

  /// 已解析的递减时的滚动时长。
  Duration? get _timeReverseDuration => timeline?.reverseDuration ?? reverseDuration;

  /// 已解析的递减时的滚动曲线。
  Curve? get _timeReverseCurve => timeline?.reverseCurve ?? reverseCurve;

  /// 已解析的开始滚动前的延迟；同样受倍速影响。
  Duration? get _timeStartDelay => timeline?.startDelay ?? startDelay;

  /// 已解析的播放倍速，必须大于零。
  double get _timeSpeedMultiplier => timeline?.speedMultiplier ?? speedMultiplier;

  /// 已解析的相邻数位的启动间隔。
  Duration? get _timeStaggerDelay => timeline?.staggerDelay ?? staggerDelay;

  /// 已解析的数位错峰的启动方向。
  StaggerDirection get _timeStaggerDirection => timeline?.staggerDirection ?? staggerDirection;

  /// 已解析的线性曲线自动转为缓动的数值跨度阈值。
  double get _timeAutoEaseThreshold => timeline?.autoEaseThreshold ?? autoEaseThreshold;

  /// 已解析的按从左到右的 digitIndex 返回逐位曲线；返回空时使用整体曲线。
  Curve? Function(int digitIndex)? get _timeCurveForDigit => timeline?.curveForDigit ?? curveForDigit;

  /// 已解析的根据起点 from、终点 to 与曲线进度 t 计算数位值。
  double Function(double from, double to, double t)? get _timeInterpolation => timeline?.interpolation ?? interpolation;

  /// 已解析的落位回弹幅度，必须非负；零表示关闭回弹。
  double get _timeBounceOvershoot => timeline?.bounceOvershoot ?? bounceOvershoot;

  /// 已解析的是否让每个数位仅滚动一步。
  bool get _timeFast => timeline?.fast ?? fast;

  /// 按有效字段值比较时间轴，忽略对象实例身份及被覆盖的平铺参数。
  CounterTimeline get _resolvedTimeline => CounterTimeline(
    duration: _timeDuration,
    curve: _timeCurve,
    reverseDuration: _timeReverseDuration,
    reverseCurve: _timeReverseCurve,
    startDelay: _timeStartDelay,
    speedMultiplier: _timeSpeedMultiplier,
    staggerDelay: _timeStaggerDelay,
    staggerDirection: _timeStaggerDirection,
    autoEaseThreshold: _timeAutoEaseThreshold,
    curveForDigit: _timeCurveForDigit,
    interpolation: _timeInterpolation,
    bounceOvershoot: _timeBounceOvershoot,
    fast: _timeFast,
  );
}
