import '../style/style.dart';
import '../../core/session/events.dart' show MovaNodeStart;

import 'package:flutter/widgets.dart';

import '../../core/ad/ads.dart';
import '../../core/api.dart';
import '../../core/options/theme.dart';
import '../../core/state/progress.dart';
import '../scope/plugin.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// Shared countdown bounds and presentation for pending and playing ads.
///
/// 待播与播放中广告共用的倒计时上限及展示尺寸。
const _maxCountdownSeconds = 1 << 31;
const _countdownPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 7);
const double _countdownRadius = 999;
const double _countdownBottom = 24;
const double _countdownRight = 16;

/// Overlay shown while an ad plays: an "ad" badge, a skip control that appears
/// once the ad passes its skippable threshold, and a full-surface tap that
/// reports a click-through (the host, not the library, opens any URL). Renders
/// nothing when ads are disabled or no ad is currently playing.
///
/// Host-wired: the host constructs a [MovaAds] and passes it in (e.g. via
/// a UI kit patch). Visibility follows the phase of [MovaAds]; the skip countdown
/// follows the throttled progress stream against [MovaAdBreak.skippableAfter].
///
/// 广告播放时显示的叠层："广告"角标、广告超过可跳过阈值后出现的跳过控件，以及
/// 覆盖整个画面、上报点击跳转的点按（打开 URL 由宿主而非库负责）。广告关闭或当前
/// 没有广告在播时不渲染任何内容。
///
/// 由宿主接线：宿主构造一个 [MovaAds] 并传入（例如经 UI 套件补丁）。显隐跟随
/// [MovaAds] 的阶段；跳过倒计时依节流进度流对比 [MovaAdBreak.skippableAfter]。
class MovaAdOverlayComponent extends MovaComponent {
  /// Creates the ad overlay bound to [ads].
  ///
  /// 创建绑定到 [ads] 的广告叠层。
  ///
  /// - [ads]: the ads orchestrator driving playback / 驱动播放的广告编排对象
  /// [ads] 为借用的广告编排对象，返回广告覆盖层组件。
  /// 示例：`MovaAdOverlayComponent(ads)`。
  MovaAdOverlayComponent(this.ads);

  /// The ads orchestrator this overlay reads and drives.
  ///
  /// 该叠层读取并驱动的广告编排对象。
  /// 返回组件借用的广告编排对象；示例：`overlay.ads.skip()`。
  final MovaAds ads;

  /// This component's path segment for `MovaPatch` addressing.
  ///
  /// 该组件在 `MovaPatch` 寻址体系里的路径片段。
  static const String componentName = 'adOverlay';

  @override
  String get name => componentName;

  @override
  MovaSlot get slot => MovaSlot.overlay;

  /// Builds enabled ads with subscriptions owned by the [MovaAds] identity.
  ///
  /// 为已启用的广告构建叠层，订阅归 [MovaAds] 实例身份持有。
  @override
  Widget build(BuildContext context, IMovaApi api, List<Widget> children) {
    if (!api.options.ads.enabled) return const SizedBox.shrink();
    // The MovaAds identity owns the subscriptions and their lifecycle.
    //
    // 订阅及其生命周期归属于 MovaAds 实例身份。
    return _AdOverlayView(key: ObjectKey(ads), ads: ads);
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
  /// The scoped capability surface is followed for the ad's position.
  ///
  /// 创建内部广告叠层视图。
  /// 跟随作用域内能力面提供的广告位置。
  const _AdOverlayView({super.key, required this.ads});

  /// The ads orchestrator providing phase, current break, and skip/click actions.
  ///
  /// 提供阶段、当前广告位与跳过/点击动作的广告编排对象。
  final MovaAds ads;

  @override
  State<_AdOverlayView> createState() => _AdOverlayViewState();
}

/// Rebuilds on phase, node and progress changes; the session owns skip rules.
///
/// 阶段、节点与进度变化触发重建；跳过判据由会话统一维护。
class _AdOverlayViewState extends State<_AdOverlayView>
    with MovaPlugin<_AdOverlayView> {
  @override
  void initState() {
    super.initState();
    bind(api.progress, _onProgress);
    bind(widget.ads.changes, (_) => setState(() {}));
    bind(widget.ads.session.events, (event) {
      if (event is MovaNodeStart) setState(() {});
    });
  }

  /// Progress only rebuilds; the session filters stale landing positions.
  ///
  /// 进度只触发重建，落地窗口内旧媒体的位置由会话过滤。
  void _onProgress(MovaProg p) {
    if (widget.ads.isShowingAd || widget.ads.isAdPending) {
      setState(() {});
    }
  }

  /// Renders the pending countdown or the active ad's controls.
  ///
  /// 展示待播倒计时或播放中广告的控件。
  @override
  Widget build(BuildContext context) {
    final ads = widget.ads;
    final theme = MovaPlayerStyle.themeOf(context);
    final strings = MovaPlayerStyle.stringsOf(context);
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
    final pendingLeft = ads.delayRemaining;
    if (ads.isAdPending && pendingLeft != null) {
      final left = (pendingLeft.inMilliseconds / Duration.millisecondsPerSecond)
          .ceil()
          .clamp(0, _maxCountdownSeconds);
      return Stack(
        children: [
          Positioned(
            bottom: _countdownBottom,
            right: _countdownRight,
            child: _Pill(
              text: strings.adStartingIn(left),
              theme: theme,
              padding: _countdownPadding,
              borderRadius: _countdownRadius,
            ),
          ),
        ],
      );
    }
    final b = ads.currentBreak;
    if (!ads.isShowingAd || b == null) return const SizedBox.shrink();
    final after = b.skippableAfter;
    final canSkip = ads.canSkip;
    final skipIn = ads.skipIn;
    // Round the remaining time up so a 4.9s remainder reads "5", not "4".
    //
    // 剩余时间向上取整，使 4.9 秒显示为 "5" 而非 "4"。
    final secondsLeft = skipIn == null
        ? 0
        : (skipIn.inMicroseconds / Duration.microsecondsPerSecond).ceil().clamp(
            0,
            _maxCountdownSeconds,
          );
    return Stack(
      children: [
        // Full-surface click-through: reported only, never navigated here.
        //
        // 覆盖整个画面的点击跳转：仅上报，不在此处跳转。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: ads.notifyClicked,
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
            bottom: _countdownBottom,
            right: _countdownRight,
            child: canSkip
                ? _Pill(
                    text: strings.skipAd,
                    theme: theme,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    borderRadius: _countdownRadius,
                    bordered: true,
                    onTap: ads.skip,
                    fontWeight: FontWeight.w600,
                  )
                : _Pill(
                    text: '$secondsLeft',
                    theme: theme,
                    padding: _countdownPadding,
                    borderRadius: _countdownRadius,
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
