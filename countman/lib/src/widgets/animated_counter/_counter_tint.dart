part of 'animated_counter.dart';

// ── 方向变色 ──────────────────────────────────────────────────────────────────

/// 数值增减时数字短暂染成方向色再渐变回原色：有限档位色板 + 文字样式缓存。
mixin _CounterTint<W extends _BaseAnimatedCounter> on State<W> {
  /// 每帧通知两条渲染路径刷新；由状态机实现。
  void _onFrameUpdate();

  Color? _directionColor;
  int   _colorAnimKey = 0;
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

  /// 量化方向色并直接更新数字；子树与 painter 均不依赖外层文字继承。
  Widget _wrapColorTint(Widget child, Color baseColor) {
    if (_directionColor == null) return child;
    if (_paletteKey != _colorAnimKey) {
      _paletteKey = _colorAnimKey;
      _tintPalette = List<Color>.generate(_tintSteps,
          (i) => Color.lerp(_directionColor, baseColor, i / (_tintSteps - 1))!);
      _tintBucket = 0;
      _appliedTintBucket = -1;
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(_colorAnimKey),
      tween: Tween(begin: 0, end: 1),
      duration: widget.colorFadeDuration,
      builder: (_, t, ch) {
        final bucket = (t * (_tintSteps - 1)).round();
        if (_appliedTintBucket != bucket) {
          _tintBucket = bucket;
          _appliedTintBucket = bucket;
          _onFrameUpdate();
        }
        return ch!;
      },
      child: child,
    );
  }
}
