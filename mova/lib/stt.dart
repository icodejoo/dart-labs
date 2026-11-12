/// 语音转字幕入口：识别端口、字幕、模型与存储接缝及配置。
/// 本包不内置识别引擎，MovaApi.stt 继续保留。
/// 模型下载为实验实现，当前下载与缓存行为保持不变。
/// mova.dart 仅保留一个版本的兼容转导出，请迁移为 package:mova/stt.dart。
library;

export 'src/core/stt/api.dart';
export 'src/core/stt/audio_extractor.dart';
export 'src/core/stt/cue.dart';
export 'src/core/stt/model_dir_provider.dart';
export 'src/core/stt/model_provider.dart';
export 'src/core/stt/model_spec.dart';
export 'src/core/stt/port.dart';
export 'src/core/stt/chunk_subtitle_store.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/core/stt/service.dart';
export 'src/core/stt/srt.dart';
export 'src/core/stt/subtitle_dir_provider.dart';
export 'src/core/stt/subtitle_store.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/platform_impl/mpv_audio_extractor_impl.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/platform_impl/stt_model_dir_impl.dart';

/// 兼容公告：此内部 helper 计划下个版本从公开入口隐藏；本版保留原符号。
export 'src/platform_impl/stt_subtitle_dir_impl.dart';
export 'src/core/options/stt_config.dart';
