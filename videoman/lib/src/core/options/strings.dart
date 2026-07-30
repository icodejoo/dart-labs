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

  /// Button text to jump back to the (DVR/time-shift) edge.
  ///
  /// 跳回（DVR/时移）边缘的按钮文案。
  final String backToEdge;

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
    this.backToEdge = '回到边缘',
    this.auto = '自动',
    this.quality = '清晰度',
    this.zoomSuffix = 'x',
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
          backToEdge == other.backToEdge &&
          auto == other.auto &&
          quality == other.quality &&
          zoomSuffix == other.zoomSuffix;

  @override
  int get hashCode => Object.hash(
        fitContain,
        fitCover,
        fitFill,
        live,
        backToLive,
        timeshift,
        backToEdge,
        auto,
        quality,
        zoomSuffix,
      );
}
