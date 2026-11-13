/// 扩展入口：会话、无缝切换、预览、平台端口及上报等高级接缝。
/// 下方单独公告的内部 helper 仅为兼容保留，计划下个版本从公开入口隐藏；
/// 宿主应优先实现端口或使用 createMova。其余扩展契约继续保留。
library;

export 'src/core/guard/auto_pause.dart';
export 'src/core/interceptor/interceptor.dart';
export 'src/core/live/timeshift.dart';
export 'src/core/platform/platform.dart';
export 'src/core/preview/cache.dart';
export 'src/core/preview/dir_provider.dart';
export 'src/core/preview/disk_cache.dart';
export 'src/core/preview/extractor.dart';
export 'src/core/preview/fetcher.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/core/preview/hash.dart';
export 'src/core/preview/models.dart';
export 'src/core/preview/net_probe.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/core/preview/platform_kind.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/core/preview/service.dart';
export 'src/core/preview/source.dart';
export 'src/core/preview/two_level_cache.dart';
export 'src/core/preview/vtt.dart';
export 'src/core/preview/vtt_source.dart';
export 'src/core/recovery/fail.dart';
export 'src/core/render/first_frame.dart';
export 'src/core/report/error_policy.dart';
export 'src/core/report/report.dart';
export 'src/core/report/session.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/core/report/session_id.dart';
export 'src/core/report/stall.dart';
export 'src/core/report/stats_probe.dart';
export 'src/core/keep_alive/keep_alive.dart';
export 'src/core/cutover/api.dart';
export 'src/core/cutover/plan.dart';
export 'src/core/cutover/cutover.dart';
export 'src/core/cutover/trigger.dart';
export 'src/core/cutover/warm.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/platform_impl/mpv_extractor_impl.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/platform_impl/net_probe_impl.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/platform_impl/thumb_dir_impl.dart';
export 'src/ui/guard/auto_pause.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/platform_impl/brightness_impl.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/platform_impl/orient_impl.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/platform_impl/pip_impl.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/platform_impl/volume_impl.dart';
export 'src/core/session/session.dart' show MovaSession, MovaLoadOutcome;
export 'src/core/session/cursor.dart';
export 'src/core/session/events.dart';
export 'src/core/session/timeline.dart' show MovaNodeKind, MovaNodeId;
export 'src/core/session/arbiter.dart' show MovaNodeFailVerdict;
