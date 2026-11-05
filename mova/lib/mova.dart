/// mova — a media_kit-based (libmpv/ffmpeg) video player library with a
/// self-built gesture control layer for VOD and live playback.
///
/// mova —— 基于 media_kit（libmpv/ffmpeg）的视频播放库，自研手势控制层，
/// 支持点播与直播。
library;

export 'src/core/api.dart';
export 'src/core/engine.dart';
export 'src/core/events/events.dart';
export 'src/core/model/danmaku.dart';
export 'src/core/model/fit.dart';
export 'src/core/model/orientation.dart';
export 'src/core/model/playlist.dart';
export 'src/core/model/quality.dart';
export 'src/core/model/rate.dart';
export 'src/core/model/source.dart';
export 'src/core/options/options.dart';
export 'src/core/playlist/playlist.dart';
export 'src/core/preview/api.dart';
export 'src/core/state/progress.dart';
export 'src/core/state/state.dart';
export 'src/core/state/ui_state.dart';
export 'src/deprecated_names.dart';
export 'src/platform_impl/wiring.dart';
export 'src/ui/player.dart';
export 'src/ui/view.dart';
export 'src/core/capability.dart';

export 'skin.dart';
export 'ads.dart';
export 'feed.dart';
export 'mini.dart';

/// 兼容公告：扩展入口中的内部 helper 计划下个版本隐藏，本版仍导出同一符号。
export 'extend.dart';

/// 兼容公告：STT 仅转导出一个版本，下个版本从主入口撤下。
/// 请改用 package:mova/stt.dart；MovaApi.stt 保留，不添加成员级弃用注解。
export 'stt.dart';
