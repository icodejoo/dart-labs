import '../model/fit.dart';

/// Externalised, replaceable UI copy for the player overlay.
///
/// All strings default to Simplified Chinese, matching the product's
/// current single-locale requirement. Apps that need another locale can
/// construct a whole replacement instance (`const VmStrings(live: 'ON AIR')`)
/// and pass it into [VmOptions].
///
/// 播放器覆盖层的外置、可替换文案。
///
/// 所有字段默认简体中文，对应产品当前的单语言需求。需要其他语言的应用可以
/// 整体构造替换实例（`const VmStrings(live: 'ON AIR')`）并传入 [VmOptions]。
class VmStrings {
  /// Label for [VmFit.contain].
  ///
  /// [VmFit.contain] 的标签文案。
  final String fitContain;

  /// Label for [VmFit.cover].
  ///
  /// [VmFit.cover] 的标签文案。
  final String fitCover;

  /// Label for [VmFit.fill].
  ///
  /// [VmFit.fill] 的标签文案。
  final String fitFill;

  /// Badge text shown while a stream is live.
  ///
  /// 直播状态下显示的角标文案。
  final String live;

  /// Button text to jump back to the live edge.
  ///
  /// 跳回直播边缘的按钮文案。
  final String backToLive;

  /// Label indicating the stream is in time-shift mode.
  ///
  /// 表示当前处于时移模式的标签文案。
  final String timeshift;

  /// Label for automatic quality selection.
  ///
  /// 自动清晰度选择的标签文案。
  final String auto;

  /// Label for the quality-selection control.
  ///
  /// 清晰度选择控件的标签文案。
  final String quality;

  /// Suffix appended to the pinch-zoom HUD's numeric scale (e.g. `x` for
  /// `1.5x`).
  ///
  /// 双指缩放 HUD 数值倍率后追加的后缀（例如 `1.5x` 中的 `x`）。
  final String zoomSuffix;

  /// Suffix appended to the playback-speed button's numeric multiplier (e.g.
  /// `x` for `1.5x`). Distinct from [zoomSuffix] so a host can word or
  /// localize zoom and speed independently.
  ///
  /// 倍速按钮数值倍率后追加的后缀（例如 `1.5x` 中的 `x`）。与 [zoomSuffix] 分开，
  /// 使宿主可对缩放与倍速独立措辞或本地化。
  final String speedSuffix;

  /// Label for the "turn subtitles off" row in the subtitle picker.
  ///
  /// 字幕选择器中"关闭字幕"一行的标签文案。
  final String subtitleOff;

  /// Heading on the "next up" card shown near the end of a playlist item.
  ///
  /// 播放列表项临近结束时"下一集"卡片的标题文案。
  final String nextUp;

  /// Label for the "play the next item now" button on the next-up card.
  ///
  /// "下一集"卡片上"立即播放下一项"按钮的文案。
  final String playNow;

  /// Label for the "dismiss the next-up card" button.
  ///
  /// "关闭下一集卡片"按钮的文案。
  final String cancel;

  /// Badge marking the currently-playing media as an advertisement.
  ///
  /// 标记当前播放内容为广告的角标文案。
  final String adBadge;

  /// Label for the "skip this ad" button.
  ///
  /// "跳过广告"按钮的文案。
  final String skipAd;

  /// Creates a strings bundle; defaults to the product's Simplified Chinese
  /// copy.
  ///
  /// 创建文案集合；默认使用产品的简体中文文案。
  const VmStrings({
    this.fitContain = '适应',
    this.fitCover = '裁剪',
    this.fitFill = '拉伸',
    this.live = 'LIVE',
    this.backToLive = '回到直播',
    this.timeshift = '时移',
    this.auto = '自动',
    this.quality = '清晰度',
    this.zoomSuffix = 'x',
    this.speedSuffix = 'x',
    this.subtitleOff = '关闭字幕',
    this.nextUp = '即将播放',
    this.playNow = '立即播放',
    this.cancel = '取消',
    this.adBadge = '广告',
    this.skipAd = '跳过广告',
  });

  /// Resolves the display label for a [VmFit] mode.
  ///
  /// 解析某个 [VmFit] 模式对应的显示标签。
  ///
  /// - [fit]: fill mode / 填充模式
  ///
  /// Returns the display label / 返回显示文案。
  String fitLabel(VmFit fit) => switch (fit) {
        VmFit.contain => fitContain,
        VmFit.cover => fitCover,
        VmFit.fill => fitFill,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmStrings &&
          runtimeType == other.runtimeType &&
          fitContain == other.fitContain &&
          fitCover == other.fitCover &&
          fitFill == other.fitFill &&
          live == other.live &&
          backToLive == other.backToLive &&
          timeshift == other.timeshift &&
          auto == other.auto &&
          quality == other.quality &&
          zoomSuffix == other.zoomSuffix &&
          speedSuffix == other.speedSuffix &&
          subtitleOff == other.subtitleOff &&
          nextUp == other.nextUp &&
          playNow == other.playNow &&
          cancel == other.cancel &&
          adBadge == other.adBadge &&
          skipAd == other.skipAd;

  @override
  int get hashCode => Object.hash(
        fitContain,
        fitCover,
        fitFill,
        live,
        backToLive,
        timeshift,
        auto,
        quality,
        zoomSuffix,
        speedSuffix,
        subtitleOff,
        nextUp,
        playNow,
        cancel,
        adBadge,
        skipAd,
      );
}
