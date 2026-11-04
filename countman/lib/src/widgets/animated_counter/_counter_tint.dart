part of 'animated_counter.dart';

// ── 方向变色 ──────────────────────────────────────────────────────────────────

/// 数值增减时数字短暂染成方向色再渐变回原色。
///
/// 渐变由解析出的 [Counter] 插件上的一个 0→1 任务驱动（共享 ticker），onUpdate 里
/// 量化成有限档位并通知两条渲染路径重绘；build 阶段只记录基准色，不产生任何副作用，
/// 渐变期间不会重建 State。色板与文字样式按档位缓存，帧间复用。
mixin _CounterTint<W extends _BaseAnimatedCounter> on State<W>, _CounterScope<W> {
  /// 每帧通知两条渲染路径刷新；由状态机实现。
  void _onFrameUpdate();

  /// 渐变的起始色（方向色）；尚未发生过增减时为空。
  Color? _directionColor;

  /// 当前渐变的标识，每次新渐变加一；与 [_paletteKey] 不一致表示色板需要重建。
  int _colorAnimKey = 0;

  /// 最近一次 build 解析出的原色（渐变终点）；build 以前为空。
  Color? _tintBaseColor;

  /// 驱动渐变的 0→1 任务；渐变结束或被新渐变取代后为空。
  CounterHandle? _tintHandle;

  /// 一次方向变色仅生成有限档位，帧间复用颜色和段落。
  List<Color> _tintPalette = const [];
  /// 当前色板对应的文字样式，避免 Builder 每帧复制 TextStyle。
  List<TextStyle> _tintStyles = const [];
  /// 文字样式缓存的基准配置。
  TextStyle? _tintStyleBase;
  /// 文字样式缓存对应的色板。
  List<Color>? _tintStylePalette;
  /// 上次应用的档位，避免同一量化档位重复触发重绘。
  int _appliedTintBucket = -1;
  /// 当前颜色档位；未配置方向色时保持空色板。
  int _tintBucket = 0;
  /// 已准备色板的动画标识。
  int _paletteKey = -1;
  /// 当前数字颜色；Builder 和 painter 共用同一档位。
  Color? get _digitTint => _tintPalette.isEmpty ? null : _tintPalette[_tintBucket];
  /// 方向色渐变的有限档位数。
  static const int _tintSteps = 16;

  /// 开始一次新的方向变色：渐变从 [target]（方向色）出发，经 `colorFadeDuration`
  /// 回到原色。取代仍在进行的旧渐变；时长为零时立即落到原色。
  void _startTint(Color target) {
    _directionColor = target;
    _colorAnimKey++;
    _tintHandle?.cancel();
    _tintHandle = null;
    final fade = _effColorFadeDuration;
    if (fade <= Duration.zero) {
      _onTintTick(1.0);
      return;
    }
    _tintHandle = _counterPlugin.add(CounterOptions(
      from: 0.0,
      to: 1.0,
      duration: fade,
      curve: Curves.linear,
      allowNegative: false,
      onUpdate: _onTintTick,
      onComplete: (_) => _tintHandle = null,
    ));
  }

  /// 渐变进度 [t]（0–1）到达：必要时重建色板，档位变化才通知渲染路径。
  ///
  /// 在插件 tick 中调用，不在 build 里。尚未 build 过（没有基准色）时忽略，下一帧补上。
  void _onTintTick(double t) {
    final base = _tintBaseColor;
    final from = _directionColor;
    if (!mounted || base == null || from == null) return;
    if (_paletteKey != _colorAnimKey) {
      _paletteKey = _colorAnimKey;
      _tintPalette = List<Color>.generate(
          _tintSteps, (i) => Color.lerp(from, base, i / (_tintSteps - 1))!);
      _tintBucket = 0;
      _appliedTintBucket = -1;
    }
    final bucket = (t * (_tintSteps - 1)).round();
    if (_appliedTintBucket == bucket) return;
    _tintBucket = bucket;
    _appliedTintBucket = bucket;
    _onFrameUpdate();
  }

  /// 返回当前方向色的缓存文字样式；每次配置变更最多构建一个有限色板。
  TextStyle _digitStyleFor(TextStyle base) {
    if (_tintPalette.isEmpty) return base;
    if (_tintStyleBase != base || !identical(_tintStylePalette, _tintPalette)) {
      _tintStyleBase = base;
      _tintStylePalette = _tintPalette;
      _tintStyles = [for (final color in _tintPalette) base.copyWith(color: color)];
    }
    return _tintStyles[_tintBucket];
  }

  @override
  void dispose() {
    _tintHandle?.cancel();
    _tintHandle = null;
    super.dispose();
  }
}
