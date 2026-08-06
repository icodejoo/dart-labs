import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import 'common.dart';

/// The fixed cycle of playback-rate multipliers [SpeedButtonComponent] steps
/// through.
///
/// [SpeedButtonComponent] 循环切换所用的固定倍速档位表。
const List<double> _kSpeedSteps = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Playback-rate cycling button; label shows the active multiplier (e.g.
/// `1.5x`), tap advances to the next step in [_kSpeedSteps], wrapping around.
///
/// Purely a UI addition over the existing [MovaApi.setRate] — no new core
/// capability was needed.
///
/// 播放倍速循环切换按钮；标签展示当前倍速（如 `1.5x`），点击切换到
/// [_kSpeedSteps] 中的下一档，到头后回绕。
///
/// 只是在既有 [MovaApi.setRate] 之上新增的 UI——无需任何新的 core 能力。
class SpeedButtonComponent extends MovaComp {
  /// Creates the speed-button leaf component.
  ///
  /// 创建倍速按钮叶子组件。
  SpeedButtonComponent();

  @override
  String get name => 'speedButton';

  @override
  MovaSlot get slot => MovaSlot.top;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    final suffix = api.options.strings.speedSuffix;
    return MovaSelect<double>(
      selector: (s) => s.rate,
      builder: (context, rate) {
        return MovaIconButton(
          icon: Icons.speed_rounded,
          theme: theme,
          caption: '${_formatRate(rate)}$suffix',
          onPressed: () => api.setRate(_nextRate(rate)),
        );
      },
    );
  }

  /// Returns the next rate in [_kSpeedSteps] after [current], wrapping to the
  /// first step past the last one. Falls back to the first step if [current]
  /// isn't an exact step (e.g. a host set a custom rate directly).
  ///
  /// 返回 [_kSpeedSteps] 中紧跟 [current] 之后的一档，越过末档后回绕到首档。
  /// 若 [current] 不是某个精确档位（例如宿主直接设了自定义倍速），回退到首档。
  ///
  /// - [current]: the active rate / 当前生效的倍速
  ///
  /// Returns the next rate to apply / 返回下一档要应用的倍速。
  static double _nextRate(double current) {
    final idx = _kSpeedSteps.indexOf(current);
    if (idx == -1) return _kSpeedSteps.first;
    return _kSpeedSteps[(idx + 1) % _kSpeedSteps.length];
  }

  /// Formats [rate] without a trailing `.0` for whole-number steps (`1x`
  /// rather than `1.0x`), matching common video-player captions.
  ///
  /// 格式化 [rate]，整数档位不带多余的 `.0`（`1x` 而非 `1.0x`），对齐常见
  /// 播放器的倍速文案习惯。
  static String _formatRate(double rate) {
    return rate == rate.roundToDouble() ? rate.toInt().toString() : rate.toString();
  }
}
