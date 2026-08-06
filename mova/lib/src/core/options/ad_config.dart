import '../model/ad.dart';

/// Configuration for pre/mid/post-roll ads.
///
/// Disabled and empty by default so enabling it is an explicit host decision.
/// The controller (`MovaAdCtrl`) is host-constructed and orchestrates the
/// content↔ad source swaps; this bundle only carries the schedule and the
/// [onAdEvent] hook (the sole way click-through is surfaced — mova never
/// opens a URL itself).
///
/// 前/中/后贴片广告的配置。
///
/// 默认关闭且列表为空，是否启用由宿主显式决定。控制器（`MovaAdCtrl`）由宿主
/// 构造并编排正片↔广告的源切换；本配置只承载排期与 [onAdEvent] 钩子（点击跳转的
/// 唯一暴露途径——mova 从不自行打开 URL）。
class MovaAdConfig {
  /// Master switch; no ads play when `false`.
  ///
  /// 总开关；为 `false` 时不播放任何广告。
  final bool enabled;

  /// The ad breaks to schedule.
  ///
  /// 要排期的广告位列表。
  final List<MovaAdBreak> breaks;

  /// Host hook notified of every ad lifecycle event, including
  /// [MovaAdEventType.clicked] (which carries the click-through URL to act on).
  ///
  /// 宿主钩子，接收每个广告生命周期事件，包括 [MovaAdEventType.clicked]
  /// （携带可供处理的点击跳转地址）。
  final void Function(MovaAdEvent event)? onAdEvent;

  /// Creates an ad configuration; disabled and empty by default.
  ///
  /// 创建广告配置；默认关闭且列表为空。
  ///
  /// - [enabled]: master switch / 总开关
  /// - [breaks]: ad break schedule / 广告位排期
  /// - [onAdEvent]: lifecycle hook / 生命周期钩子
  const MovaAdConfig({
    this.enabled = false,
    this.breaks = const <MovaAdBreak>[],
    this.onAdEvent,
  });

  /// Returns a copy with the given fields replaced; omitted fields keep their
  /// current value.
  ///
  /// 返回一份替换了指定字段的拷贝；未指定的字段保持当前值。
  MovaAdConfig copyWith({
    bool? enabled,
    List<MovaAdBreak>? breaks,
    void Function(MovaAdEvent event)? onAdEvent,
  }) {
    return MovaAdConfig(
      enabled: enabled ?? this.enabled,
      breaks: breaks ?? this.breaks,
      onAdEvent: onAdEvent ?? this.onAdEvent,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaAdConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          identical(breaks, other.breaks) &&
          onAdEvent == other.onAdEvent;

  @override
  int get hashCode => Object.hash(enabled, breaks, onAdEvent);
}
