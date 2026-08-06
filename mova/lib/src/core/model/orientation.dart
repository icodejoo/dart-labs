/// Forced screen-orientation override for the player.
///
/// [auto] keeps the 0.1.0 behavior — fullscreen picks landscape/portrait from
/// the video's aspect ratio, non-fullscreen allows all. [portrait]/[landscape]
/// force that orientation regardless of aspect ratio or fullscreen state.
///
/// 播放器的强制屏幕方向覆盖。
///
/// [auto] 保持 0.1.0 行为——全屏时按视频宽高比选横/竖屏，非全屏放开全部方向；
/// [portrait]/[landscape] 则无视宽高比与全屏状态，强制该方向。
enum MovaOrient {
  /// Follow aspect ratio when fullscreen; allow all otherwise.
  ///
  /// 全屏时跟随宽高比；否则放开全部方向。
  auto,

  /// Force portrait.
  ///
  /// 强制竖屏。
  portrait,

  /// Force landscape.
  ///
  /// 强制横屏。
  landscape;

  /// The orientation a single toggle press should switch to: [landscape]
  /// flips to [portrait], while [auto] and [portrait] flip to [landscape].
  ///
  /// So the button behaves as a plain landscape↔portrait switch, treating the
  /// initial [auto] as "not yet landscape".
  ///
  /// 单次切换按钮应切到的方向：[landscape] 翻到 [portrait]，[auto] 与
  /// [portrait] 翻到 [landscape]。
  ///
  /// 于是按钮表现为一个纯粹的横↔竖切换，把初始的 [auto] 视作"尚未横屏"。
  MovaOrient get toggled =>
      this == MovaOrient.landscape ? MovaOrient.portrait : MovaOrient.landscape;
}
