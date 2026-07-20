/// 长龙金圈庆祝效果控制器。
///
/// 移植自 `src/panel/ux/celebration.ts`（简化为开关控制器，理由同
/// `pulse.dart`——具体庆祝动画交给消费方按需叠加）。
library;

/// 触发庆祝的模式。
enum CelebrationPattern { dragon, singleHop, doubleHop }

/// 庆祝效果选项。
class CelebrationOptions {
  /// 触发模式，默认只在长龙时触发。
  final List<CelebrationPattern> pattern;

  const CelebrationOptions({this.pattern = const [CelebrationPattern.dragon]});
}

/// 长龙金圈庆祝效果控制器。
class CelebrationEffect {
  bool enabled;
  final CelebrationOptions options;

  CelebrationEffect({this.enabled = true, this.options = const CelebrationOptions()});

  /// 切换开关。
  void toggle(bool on) => enabled = on;
}

/// 创建长龙庆祝效果控制器（默认开启）。
CelebrationEffect createCelebrationEffect({CelebrationOptions options = const CelebrationOptions()}) =>
    CelebrationEffect(options: options);
