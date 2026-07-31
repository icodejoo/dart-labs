/// videoman — a media_kit-based (libmpv/ffmpeg) video player library with a
/// self-built gesture control layer for VOD and live playback.
///
/// videoman —— 基于 media_kit（libmpv/ffmpeg）的视频播放库，自研手势控制层，
/// 支持点播与直播。
library;

export 'src/core/api.dart';
export 'src/core/compat.dart';
export 'src/core/engine.dart';
export 'src/core/events/events.dart';
export 'src/core/interceptor/interceptor.dart';
export 'src/core/model/fit.dart';
export 'src/core/model/quality.dart';
export 'src/core/model/source.dart';
export 'src/core/options/options.dart';
export 'src/core/platform/ports.dart';
export 'src/core/preview/hash.dart';
export 'src/core/preview/models.dart';
export 'src/core/state/progress.dart';
export 'src/core/state/state.dart';
export 'src/core/state/ui_state.dart';
export 'src/platform_impl/wiring.dart';
export 'src/ui/components/bottom_bar.dart';
export 'src/ui/components/center_play.dart';
export 'src/ui/components/common.dart';
export 'src/ui/components/gesture_layer.dart';
export 'src/ui/components/hud_layer.dart';
export 'src/ui/components/live_bar.dart';
export 'src/ui/components/overlays.dart';
export 'src/ui/components/top_bar.dart';
export 'src/ui/fit_ext.dart';
export 'src/ui/format.dart';
export 'src/ui/player.dart';
export 'src/ui/scope/scope.dart';
export 'src/ui/scope/selector.dart';
export 'src/ui/skins/default_skin.dart';
export 'src/ui/skins/skin.dart';
export 'src/ui/slots/component.dart';
export 'src/ui/slots/patch.dart';
export 'src/ui/slots/slot.dart';
export 'src/ui/slots/tree.dart';
