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
/// Host-wired: the host constructs a [MovaAdController] and passes it in (e.g. via
/// a skin patch). Visibility follows the controller's phase; the skip countdown
/// follows the throttled progress stream against [MovaAdBreak.skippableAfter].
///
/// 广告播放时显示的叠层："广告"角标、广告超过可跳过阈值后出现的跳过控件，以及
/// 覆盖整个画面、上报点击跳转的点按（打开 URL 由宿主而非库负责）。广告关闭或当前
/// 没有广告在播时不渲染任何内容。
///
/// 由宿主接线：宿主构造一个 [MovaAdController] 并传入（例如经皮肤补丁）。显隐跟随
/// 控制器阶段；跳过倒计时依节流进度流对比 [MovaAdBreak.skippableAfter]。
class MovaAdOverlayComponent extends MovaComponent {
  /// Creates the ad overlay bound to [controller].
  ///
  /// 创建绑定到 [controller] 的广告叠层。
  ///
  /// - [controller]: the ad controller driving playback / 驱动播放的广告控制器
  MovaAdOverlayComponent(this.controller);

  /// The ad controller this overlay reads and drives.
  ///
  /// 该叠层读取并驱动的广告控制器。
  final MovaAdController controller;

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

/// Stateful body of [MovaAdOverlayComponent]: tracks the ad's elapsed position for
/// the skip countdown and rebuilds when the ad phase changes.
///
/// [MovaAdOverlayComponent] 的有状态主体：为跳过倒计时跟踪广告已播位置，并在广告阶段
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
  final MovaAdController controller;

  @override
  State<_AdOverlayView> createState() => _AdOverlayViewState();
}

/// State for [_AdOverlayView]; owns the last-seen ad position used to derive the
/// skip countdown independent of controller-callback ordering.
///
/// [_AdOverlayView] 的状态；持有最近观测到的广告位置，用于独立于控制器回调顺序地
/// 推导跳过倒计时。
class _AdOverlayViewState extends State<_AdOverlayView>
    with MovaPlugin<_AdOverlayView> {
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
    if (widget.controller.isShowingAd) {
      setState(() => _adPos = p.position);
    } else if (widget.controller.isAdPending) {
      // The delay countdown is derived from the content position, so it only
      // moves when a content tick arrives.
      //
      // 倒计时由正片位置推导，因此只在正片 tick 到达时才走动。
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = widget.api.options.theme;
    final strings = widget.api.options.strings;
    // The pending phase: the content is still playing and the viewer has not
    // been interrupted, so this renders *only* the countdown — no ad badge, and
    // no full-surface tap layer that would swallow the content's own gestures.
    //
    // Deliberately nothing at all for the default mid-roll shape (delay zero,
    // silently waiting for readiness): that wait is meant to be imperceptible,
    // and drawing a "loading the ad" hint would turn something the viewer never
    // notices into something they do.
    //
    // 待播阶段：正片仍在播放、观众尚未被打断，因此这里*只*渲染倒计时——没有广告
    // 角标，也没有会吞掉正片自身手势的全屏点击层。
    //
    // 对中插的默认形态（delay 为零、静默等待就绪）刻意什么都不画：那段等待本就
    // 该是用户无感的，画一个"正在加载广告"的提示只会把本来无感的事变成有感的事。
    final pendingLeft = controller.delayRemaining;
    if (controller.isAdPending && pendingLeft != null) {
      final left = (pendingLeft.inMilliseconds / 1000).ceil().clamp(0, 1 << 31);
      return Stack(
        children: [
          Positioned(
            bottom: 24,
            right: 16,
            child: _Pill(
              text: strings.adStartingIn(left),
              theme: theme,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              borderRadius: 999,
            ),
          ),
        ],
      );
    }
    final b = controller.currentBreak;
    if (!controller.isShowingAd || b == null) return const SizedBox.shrink();
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
          child: _Pill(
            text: strings.adBadge,
            theme: theme,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            borderRadius: 4,
            fontSize: theme.badgeFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (after != null)
          Positioned(
            bottom: 24,
            right: 16,
            child: canSkip
                ? _Pill(
                    text: strings.skipAd,
                    theme: theme,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    borderRadius: 999,
                    bordered: true,
                    onTap: controller.skip,
                    fontWeight: FontWeight.w600,
                  )
                : _Pill(
                    text: '$secondsLeft',
                    theme: theme,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    borderRadius: 999,
                  ),
          ),
      ],
    );
  }
}

/// Shared dark rounded-pill chrome for the ad badge, skip button, and
/// countdown — same container/text styling, differing only in corner
/// radius, border, tap handler and font weight.
///
/// 广告角标、跳过按钮、倒计时共用的深色圆角药丸外观——三者容器/文字样式一致，
/// 只在圆角、描边、点击、字重上有差异。
class _Pill extends StatelessWidget {
  /// Creates the pill.
  ///
  /// 创建药丸组件。
  const _Pill({
    required this.text,
    required this.theme,
    required this.padding,
    required this.borderRadius,
    this.bordered = false,
    this.onTap,
    this.fontSize = 13,
    this.fontWeight,
  });

  /// The text content to display.
  ///
  /// 展示的文本内容。
  final String text;

  /// The theme supplying colors.
  ///
  /// 提供配色的主题。
  final MovaTheme theme;

  /// Inner padding around [text].
  ///
  /// [text] 周围的内边距。
  final EdgeInsets padding;

  /// Corner radius of the pill.
  ///
  /// 药丸的圆角半径。
  final double borderRadius;

  /// Whether to draw a [MovaTheme.textColor] border (used by the skip button).
  ///
  /// 是否绘制 [MovaTheme.textColor] 描边（跳过按钮使用）。
  final bool bordered;

  /// Optional tap handler; when set the pill becomes tappable.
  ///
  /// 可选点击回调；设置后药丸变为可点击。
  final VoidCallback? onTap;

  /// Text font size, defaults to 13.
  ///
  /// 文字字号，默认 13。
  final double fontSize;

  /// Optional text font weight.
  ///
  /// 可选文字字重。
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        border: bordered ? Border.all(color: Color(theme.textColor)) : null,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Color(theme.textColor),
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
    );
    return onTap == null ? pill : GestureDetector(onTap: onTap, child: pill);
  }
}
