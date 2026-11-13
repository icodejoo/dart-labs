/// 短视频流入口：Feed、播放器池、预取端口、条目及播放器控制器。
/// 播放器与通用播放类型由 mova.dart 提供。
library;

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/core/feed/feed_pool.dart';
export 'src/core/feed/feed.dart';
export 'src/core/feed/feed_prefetcher.dart';
export 'src/core/model/feed_item.dart';
export 'src/ui/components/feed_social.dart';
export 'src/ui/feed_player.dart';
