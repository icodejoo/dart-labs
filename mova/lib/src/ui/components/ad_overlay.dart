import 'package:flutter/widgets.dart';

import '../../core/ad/ad_controller.dart';
import '../../core/api.dart';
import '../../core/options/theme.dart';
import '../../core/state/progress.dart';
import '../scope/plugin.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// Overlay shown while an ad plays: an "ad" badge, a skip control that appears
/// once the ad passes its skippable threshold, and a full-surface tap that
/// reports a click-through (the host, not the library, opens any URL). Renders
/// nothing when ads are disabled or no ad is currently playing.
///
/// Host-wired: the host constructs a [MovaAdCtrl] and passes it in (e.g. via
/// a skin patch). Visibility follows the controller's phase; the skip countdown
/// follows the throttled progress stream against [MovaAdBreak.skippableAfter].
///
/// 广告播放时显示的叠层："广告"角标、广告超过可跳过阈值后出现的跳过控件，以及
/// 覆盖整个画面、上报点击跳转的点按（打开 URL 由宿主而非库负责）。广告关闭或当前
/// 没有广告在播时不渲染任何内容。
///
/// 由宿主接线：宿主构造一个 [MovaAdCtrl] 并传入（例如经皮肤补丁）。显隐跟随
/// 控制器阶段；跳过倒计时依节流进度流对比 [MovaAdBreak.skippableAfter]。
class AdOverlayComponent extends MovaComp {
  /// Creates the ad overlay bound to [controller].
  ///
  /// 创建绑定到 [controller] 的广告叠层。
  ///
  /// - [controller]: the ad controller driving playback / 驱动播放的广告控制器
  AdOverlayComponent(this.controller);

  /// The ad controller this overlay reads and drives.
  ///
  /// 该叠层读取并驱动的广告控制器。
  final MovaAdCtrl controller;

  @override
  String get name => 'adOverlay';

  @override
  MovaSlot get slot => MovaSlot.overlay;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    if (!api.options.ads.enabled) return const SizedBox.shrink();
    return _AdOverlayView(api: api, controller: controller);
  }
}

/// Stateful body of [AdOverlayComponent]: tracks the ad's elapsed position for
/// the skip countdown and rebuilds when the ad phase changes.
///
/// [AdOverlayComponent] 的有状态主体：为跳过倒计时跟踪广告已播位置，并在广告阶段
/// 变化时重建。
class _AdOverlayView extends StatefulWidget {
  /// Creates the internal ad overlay view.
  ///
  /// 创建内部广告叠层视图。
  const _AdOverlayView({required this.api, required this.controller});

  /// The capability surface followed for the ad's position.
  ///
  /// 用于跟随广告位置的能力面。
  final MovaApi api;

  /// The ad controller providing phase, current break, and skip/click actions.
  ///
  /// 提供阶段、当前广告位与跳过/点击动作的广告控制器。
  final MovaAdCtrl controller;

  @override
  State<_AdOverlayView> createState() => _AdOverlayViewState();
}

/// State for [_AdOverlayView]; owns the last-seen ad position used to derive the
/// skip countdown independent of controller-callback ordering.
///
/// [_AdOverlayView] 的状态；持有最近观测到的广告位置，用于独立于控制器回调顺序地
/// 推导跳过倒计时。
class _AdOverlayViewState extends State<_AdOverlayView> with MovaPlugin<_AdOverlayView> {
  /// Ad elapsed time as of the last progress tick; reset to zero each time an
  /// ad phase begins.
  ///
  /// 最近一次进度 tick 时的广告已播时长；每次进入广告阶段时归零。
  Duration _adPos = Duration.zero;

  @override
  void initState() {
    super.initState();
    bind(api.progress, _onProgress);
    // A phase change (ad start/end/skip) rebuilds and re-zeros the countdown.
    //
    // 阶段变化（广告开始/结束/跳过）触发重建并把倒计时归零。
    bind(widget.controller.changes, (_) {
      setState(() => _adPos = Duration.zero);
    });
  }

  /// Advances the tracked ad position while an ad is on screen.
  ///
  /// 广告在屏期间推进跟踪的广告位置。
  void _onProgress(MovaProg p) {
    if (widget.controller.isShowingAd) setState(() => _adPos = p.position);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final b = controller.currentBreak;
    if (!controller.isShowingAd || b == null) return const SizedBox.shrink();
    final theme = widget.api.options.theme;
    final strings = widget.api.options.strings;
    final after = b.skippableAfter;
    final canSkip = after != null && _adPos >= after;
    // Round the remaining time up so a 4.9s remainder reads "5", not "4".
    //
    // 剩余时间向上取整，使 4.9 秒显示为 "5" 而非 "4"。
    final secondsLeft = after == null
        ? 0
        : ((after - _adPos).inMilliseconds / 1000).ceil().clamp(0, 1 << 31);
    return Stack(
      children: [
        // Full-surface click-through: reported only, never navigated here.
        //
        // 覆盖整个画面的点击跳转：仅上报，不在此处跳转。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: controller.notifyClicked,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: _Badge(label: strings.adBadge, theme: theme),
        ),
        if (after != null)
          Positioned(
            bottom: 24,
            right: 16,
            child: canSkip
                ? _SkipButton(
                    label: strings.skipAd,
                    theme: theme,
                    onTap: controller.skip,
                  )
                : _Countdown(seconds: secondsLeft, theme: theme),
          ),
      ],
    );
  }
}

/// The small "ad" badge.
///
/// 小型"广告"角标。
class _Badge extends StatelessWidget {
  /// Creates the badge.
  ///
  /// 创建角标。
  const _Badge({required this.label, required this.theme});

  /// Badge text.
  ///
  /// 角标文案。
  final String label;

  /// The theme supplying colors.
  ///
  /// 提供配色的主题。
  final MovaTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Color(theme.textColor),
          fontSize: theme.badgeFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The "skip ad" button, shown once the ad is skippable.
///
/// 广告可跳过后显示的"跳过广告"按钮。
class _SkipButton extends StatelessWidget {
  /// Creates the skip button.
  ///
  /// 创建跳过按钮。
  const _SkipButton({
    required this.label,
    required this.theme,
    required this.onTap,
  });

  /// Button text.
  ///
  /// 按钮文案。
  final String label;

  /// The theme supplying colors.
  ///
  /// 提供配色的主题。
  final MovaTheme theme;

  /// Tap handler.
  ///
  /// 点击回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xB3000000),
          border: Border.all(color: Color(theme.textColor)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Color(theme.textColor),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The "skippable in N seconds" countdown pill.
///
/// "N 秒后可跳过"倒计时小药丸。
class _Countdown extends StatelessWidget {
  /// Creates the countdown pill.
  ///
  /// 创建倒计时药丸。
  const _Countdown({required this.seconds, required this.theme});

  /// Whole seconds remaining until the ad becomes skippable.
  ///
  /// 距广告可跳过还剩的整秒数。
  final int seconds;

  /// The theme supplying colors.
  ///
  /// 提供配色的主题。
  final MovaTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$seconds',
        style: TextStyle(
          color: Color(theme.textColor),
          fontSize: 13,
        ),
      ),
    );
  }
}
