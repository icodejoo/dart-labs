import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/state/ui_state.dart';
import '../format.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// Composite component that hosts the 4 transient HUD overlays (volume,
/// brightness, seek, zoom) and shows whichever one matches the current
/// [VmUiState.hud] — mirroring 0.1.0's single-HUD-at-a-time behaviour.
///
/// 承载 4 种临时 HUD 浮层（音量/亮度/进度/缩放）的组合组件，只显示与当前
/// [VmUiState.hud] 匹配的那一个——对应 0.1.0"同时只显示一个 HUD"的行为。
class HudLayerComponent extends VmComponent {
  /// Creates the HUD-layer composite with its 4 fixed children.
  ///
  /// 创建带 4 个固定子组件的 HUD 层组合组件。
  HudLayerComponent();

  @override
  String get name => 'hudLayer';

  @override
  VmSlot get slot => VmSlot.hud;

  @override
  List<VmComponent> get children => [
        VolumeHudComponent(),
        BrightnessHudComponent(),
        SeekHudComponent(),
        ZoomHudComponent(),
      ];

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return Stack(children: children);
  }
}

/// Volume HUD; visible only while [VmUiState.hud] is [VmHud.volume].
///
/// 音量 HUD；仅在 [VmUiState.hud] 为 [VmHud.volume] 时可见。
class VolumeHudComponent extends VmComponent {
  /// Creates the volume HUD leaf component.
  ///
  /// 创建音量 HUD 叶子组件。
  VolumeHudComponent();

  @override
  String get name => 'volumeHud';

  @override
  VmSlot get slot => VmSlot.hud;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return VmUiSelector<VmHud>(
      selector: (s) => s.hud,
      builder: (context, hud) {
        if (hud != VmHud.volume) return const SizedBox.shrink();
        return VmSelector<double>(
          selector: (s) => s.volume,
          builder: (context, volume) => _HudBadge(
            api: api,
            icon: volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            text: '${volume.round()}%',
          ),
        );
      },
    );
  }
}

/// Brightness HUD; visible only while [VmUiState.hud] is [VmHud.brightness].
///
/// 亮度 HUD；仅在 [VmUiState.hud] 为 [VmHud.brightness] 时可见。
class BrightnessHudComponent extends VmComponent {
  /// Creates the brightness HUD leaf component.
  ///
  /// 创建亮度 HUD 叶子组件。
  BrightnessHudComponent();

  @override
  String get name => 'brightnessHud';

  @override
  VmSlot get slot => VmSlot.hud;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return VmUiSelector<VmHud>(
      selector: (s) => s.hud,
      builder: (context, hud) {
        if (hud != VmHud.brightness) return const SizedBox.shrink();
        return VmSelector<double>(
          selector: (s) => s.brightness,
          builder: (context, brightness) => _HudBadge(
            api: api,
            icon: Icons.brightness_6_rounded,
            text: '${(brightness * 100).round()}%',
          ),
        );
      },
    );
  }
}

/// Seek-preview HUD; visible only while [VmUiState.hud] is [VmHud.seek].
///
/// 拖动进度预览 HUD；仅在 [VmUiState.hud] 为 [VmHud.seek] 时可见。
class SeekHudComponent extends VmComponent {
  /// Creates the seek HUD leaf component.
  ///
  /// 创建进度 HUD 叶子组件。
  SeekHudComponent();

  @override
  String get name => 'seekHud';

  @override
  VmSlot get slot => VmSlot.hud;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return VmUiSelector<VmHud>(
      selector: (s) => s.hud,
      builder: (context, hud) {
        if (hud != VmHud.seek) return const SizedBox.shrink();
        return VmUiSelector<Duration?>(
          selector: (s) => s.previewAt,
          builder: (context, previewAt) => _HudBadge(
            api: api,
            text: previewAt != null ? formatDuration(previewAt) : '',
          ),
        );
      },
    );
  }
}

/// Zoom HUD; visible only while [VmUiState.hud] is [VmHud.zoom].
///
/// 缩放 HUD；仅在 [VmUiState.hud] 为 [VmHud.zoom] 时可见。
class ZoomHudComponent extends VmComponent {
  /// Creates the zoom HUD leaf component.
  ///
  /// 创建缩放 HUD 叶子组件。
  ZoomHudComponent();

  @override
  String get name => 'zoomHud';

  @override
  VmSlot get slot => VmSlot.hud;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return VmUiSelector<VmHud>(
      selector: (s) => s.hud,
      builder: (context, hud) {
        if (hud != VmHud.zoom) return const SizedBox.shrink();
        return VmSelector<double>(
          selector: (s) => s.zoom,
          builder: (context, zoom) => _HudBadge(
            api: api,
            text: '${zoom.toStringAsFixed(1)}${api.options.strings.zoomSuffix}',
          ),
        );
      },
    );
  }
}

/// Small centered pill used to render every HUD, themed from [VmApi.options].
///
/// Shows an optional leading [icon] followed by [text] — volume/brightness
/// pass an icon plus a `NN%` string so the gesture has legible feedback;
/// seek/zoom pass text only.
///
/// 用于渲染各 HUD 的居中小胶囊，配色取自 [VmApi.options]。
///
/// 可选的前置 [icon] 加 [text]——音量/亮度传入图标加 `NN%` 文本，让手势有清晰
/// 反馈；进度/缩放只传文本。
class _HudBadge extends StatelessWidget {
  /// Creates a themed HUD badge.
  ///
  /// [api] supplies the theme. [text] is the content shown; [icon] is an
  /// optional leading glyph.
  ///
  /// 创建带主题的 HUD 徽标。
  ///
  /// [api] 提供主题。[text] 为展示内容；[icon] 为可选前置图标。
  const _HudBadge({required this.api, required this.text, this.icon});

  /// Capability surface supplying [VmApi.options].
  ///
  /// 提供 [VmApi.options] 的能力面。
  final VmApi api;

  /// The text content to display inside the badge.
  ///
  /// 徽标内展示的文本内容。
  final String text;

  /// Optional leading icon shown before [text].
  ///
  /// [text] 之前展示的可选前置图标。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = api.options.theme;
    final color = Color(theme.textColor);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Color(theme.barGradientColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: theme.titleFontSize + 2),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: TextStyle(color: color, fontSize: theme.titleFontSize),
            ),
          ],
        ),
      ),
    );
  }
}
