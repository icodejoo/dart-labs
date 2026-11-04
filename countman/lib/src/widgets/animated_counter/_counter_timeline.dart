part of 'animated_counter.dart';

// ── 时间轴解析 ────────────────────────────────────────────────────────────────

/// 把配置里的时长、曲线、倍速折算成当前过渡实际使用的值。
extension _CounterTimelineResolution<W extends _BaseAnimatedCounter> on _BaseCounterState<W> {
  /// 单列滚动的基础时长：控制器临时覆盖 > 递减专用时长 > 常规时长（未按倍速缩放）。
  Duration get _baseDuration =>
      (widget.controller != null && widget.controller!.overrideDuration != null)
          ? widget.controller!.overrideDuration!
          : ((_isAnimatingDecrease && widget._timeReverseDuration != null)
              ? widget._timeReverseDuration!
              : widget._timeDuration);

  /// 零时长命令跳过错峰，其他时长统一按倍速缩放。
  Duration get _effectiveDuration {
    final base = _baseDuration;
    // 系统减少动画时直接落位；错峰按原始时间累加后统一缩放一次。
    if (_reduceMotion || base == Duration.zero) return Duration.zero;
    Duration d = base;
    final stagger = widget._timeStaggerDelay;
    if (stagger != null && stagger > Duration.zero) {
      d += stagger * (_engine.maxDigits - 1);
    }
    return widget._timeSpeedMultiplier == 1.0
        ? d
        : Duration(microseconds: (d.inMicroseconds / widget._timeSpeedMultiplier).round());
  }

  Curve get _effectiveCurve {
    if (_isAnimatingDecrease && widget._timeReverseCurve != null) return widget._timeReverseCurve!;
    return widget._timeCurve;
  }

  /// 递减时翻转后的滚动方向，交给组件树路径的 DigitColumn 使用。
  AxisDirection get _effectiveFlipDirection =>
      effectiveRollDirection(widget.flipDirection, !_isAnimatingDecrease);

  Duration? get _effectiveStaggerDelay {
    if (widget._timeStaggerDelay == null) return null;
    return widget._timeSpeedMultiplier == 1.0
        ? widget._timeStaggerDelay
        : Duration(microseconds: (widget._timeStaggerDelay!.inMicroseconds / widget._timeSpeedMultiplier).round());
  }

  Duration get _effectiveNegativeSignDuration => widget._timeSpeedMultiplier == 1.0
      ? widget.negativeSignDuration
      : Duration(microseconds: (widget.negativeSignDuration.inMicroseconds / widget._timeSpeedMultiplier).round());

  Duration get _effectivePositiveSignDuration {
    final base = widget.positiveSignDuration ?? widget.negativeSignDuration;
    return widget._timeSpeedMultiplier == 1.0
        ? base
        : Duration(microseconds: (base.inMicroseconds / widget._timeSpeedMultiplier).round());
  }

  /// 单列滚动时长（微秒，已按倍速缩放，不含错峰）；零时长按 1µs 计避免除零。
  double get _baseDurationUs {
    Duration base = _baseDuration;
    if (base == Duration.zero) base = const Duration(microseconds: 1);
    return base.inMicroseconds.toDouble() / widget._timeSpeedMultiplier;
  }
}
