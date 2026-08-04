import 'dart:io';

import '../preview/hash.dart';
import 'cue.dart';
import 'srt.dart';
import 'subtitle_dir_provider.dart';

/// Caches a batch-transcribed cue list on disk, keyed by source, so a VOD
/// only ever gets transcribed once regardless of how many times it's
/// re-watched.
///
/// A distinct concept from [VmSttEngine]'s live `feed`/`cues` loop: this
/// store holds the *finished result* of a one-shot batch transcription
/// (see `doc/notes/2026-08-04-stt-engine-decision.md`'s "批量预转写" section),
/// not a running recognizer.
///
/// 把一次性批量转写出的字幕列表缓存到磁盘，按来源做 key，使同一个点播视频
/// 不管重播多少次都只转写一次。
///
/// 与 [VmSttEngine] 那套 `feed`/`cues` 实时循环是不同的概念：本存储持有的是
/// 一次性批量转写的**完成结果**（见
/// `doc/notes/2026-08-04-stt-engine-decision.md` 的"批量预转写"一节），而不是
/// 一个正在运行的识别器。
abstract class VmSttSubtitleStore {
  /// Returns the cached cues for [sourceKey], or null if nothing is cached.
  ///
  /// 返回 [sourceKey] 已缓存的字幕；未缓存则返回 null。
  ///
  /// - [sourceKey]: stable identifier of the media source, usually its URI /
  ///   媒体源的稳定标识，通常是其 URI
  Future<List<VmSttCue>?> load(String sourceKey);

  /// Caches [cues] under [sourceKey], overwriting any previous entry.
  ///
  /// 把 [cues] 缓存到 [sourceKey] 下，覆盖此前的条目。
  ///
  /// - [sourceKey]: stable identifier of the media source / 媒体源的稳定标识
  /// - [cues]: the cues to cache / 要缓存的字幕
  Future<void> save(String sourceKey, List<VmSttCue> cues);

  /// Deletes the cached cues for [sourceKey], if any.
  ///
  /// 删除 [sourceKey] 已缓存的字幕（若有）。
  ///
  /// - [sourceKey]: stable identifier of the media source / 媒体源的稳定标识
  Future<void> remove(String sourceKey);
}

/// The production [VmSttSubtitleStore]: one `.srt` file per source, named by
/// [fnv1a64] of [sourceKey] (same key-shape convention as the scrub-preview
/// cache's `defaultCacheKey`).
///
/// 生产环境的 [VmSttSubtitleStore]：每个来源一个 `.srt` 文件，以 [sourceKey]
/// 的 [fnv1a64] 命名（与拖动预览缓存 `defaultCacheKey` 同一套 key 命名约定）。
class VmFileSttSubtitleStore implements VmSttSubtitleStore {
  /// Creates a file-based subtitle store.
  ///
  /// 创建一个基于文件的字幕存储。
  ///
  /// - [dir]: resolves the cache directory / 解析缓存目录
  VmFileSttSubtitleStore({required this.dir});

  /// Resolves the cache directory.
  ///
  /// 解析缓存目录。
  final VmSttSubtitleDirProvider dir;

  @override
  Future<List<VmSttCue>?> load(String sourceKey) async {
    final file = await _fileFor(sourceKey);
    if (!await file.exists()) return null;
    try {
      return parseSrt(await file.readAsString());
    } on Object {
      // A corrupt cache file degrades to "not cached" rather than crashing —
      // the caller re-transcribes and overwrites it.
      //
      // 缓存文件损坏时降级为"未缓存"而非崩溃——调用方会重新转写并覆盖它。
      return null;
    }
  }

  @override
  Future<void> save(String sourceKey, List<VmSttCue> cues) async {
    final file = await _fileFor(sourceKey);
    await file.parent.create(recursive: true);
    await file.writeAsString(formatSrt(cues), flush: true);
  }

  @override
  Future<void> remove(String sourceKey) async {
    final file = await _fileFor(sourceKey);
    if (await file.exists()) await file.delete();
  }

  Future<File> _fileFor(String sourceKey) async {
    final root = await dir.resolve();
    final name = fnv1a64(sourceKey).toRadixString(36);
    return File('$root${Platform.pathSeparator}$name.srt');
  }
}
