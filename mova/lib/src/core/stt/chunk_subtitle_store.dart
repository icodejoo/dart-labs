import 'dart:io';

import '../preview/hash.dart';
import 'cue.dart';
import 'srt.dart';
import 'subtitle_dir_provider.dart';

/// Caches per-chunk transcription results for the streaming-chunked STT
/// pipeline (see `doc/plans/2026-08-06-stt-streaming-chunked-transcription.md`),
/// keyed by `(sourceKey, chunkIndex)` — a distinct concept from
/// [MovaSttSubStore], which caches one whole-source result from a
/// single-shot batch transcription. Re-opening the same source only
/// re-queues the chunks that never finished; [SttChunkState.done] chunks
/// load straight from here.
///
/// 流式分片转写流水线（见
/// `doc/plans/2026-08-06-stt-streaming-chunked-transcription.md`）的按分片
/// 缓存，按 `(sourceKey, chunkIndex)` 做 key——与 [MovaSttSubStore]（缓存
/// 一次性整段批量转写结果）是不同的概念。重新打开同一来源时，只有没转完的
/// 分片需要重新入队；已 `done` 的分片直接从这里加载。
abstract class MovaSttChunkSubStore {
  /// Returns the cached cues for chunk [chunkIndex] of [sourceKey], or null
  /// if that chunk hasn't been cached yet.
  ///
  /// 返回 [sourceKey] 第 [chunkIndex] 片的已缓存字幕；该分片尚未缓存则返回
  /// null。
  ///
  /// - [sourceKey]: stable identifier of the media source / 媒体源的稳定标识
  /// - [chunkIndex]: index of the chunk within the source's manifest /
  ///   分片在该来源清单中的序号
  Future<List<MovaSttCue>?> loadChunk(String sourceKey, int chunkIndex);

  /// Caches [cues] for chunk [chunkIndex] of [sourceKey], overwriting any
  /// previous entry for that chunk.
  ///
  /// 把 [cues] 缓存为 [sourceKey] 第 [chunkIndex] 片，覆盖该分片此前的缓存。
  ///
  /// - [sourceKey]: stable identifier of the media source / 媒体源的稳定标识
  /// - [chunkIndex]: index of the chunk within the source's manifest /
  ///   分片在该来源清单中的序号
  /// - [cues]: the cues to cache for this chunk / 该分片要缓存的字幕
  Future<void> saveChunk(String sourceKey, int chunkIndex, List<MovaSttCue> cues);

  /// Deletes every cached chunk for [sourceKey] — call when the source's
  /// content may have changed and stale per-chunk results shouldn't be
  /// reused.
  ///
  /// 删除 [sourceKey] 下全部已缓存分片——当来源内容可能变化、不该复用旧的
  /// 按分片结果时调用。
  ///
  /// - [sourceKey]: stable identifier of the media source / 媒体源的稳定标识
  Future<void> removeAllChunks(String sourceKey);
}

/// The production [MovaSttChunkSubStore]: one `.srt` file per
/// `(sourceKey, chunkIndex)` pair, named by [fnv1a64] of a composite key —
/// same key-shape convention as [MovaFileSttSubStore] and the
/// scrub-preview cache's `defaultCacheKey`.
///
/// 生产环境的 [MovaSttChunkSubStore]：每个 `(sourceKey, chunkIndex)` 组合
/// 一个 `.srt` 文件，以复合 key 的 [fnv1a64] 命名——与 [MovaFileSttSubStore]
/// 和拖动预览缓存的 `defaultCacheKey` 是同一套 key 命名约定。
class MovaFileSttChunkSubStore implements MovaSttChunkSubStore {
  /// Creates a file-based per-chunk subtitle store.
  ///
  /// 创建一个基于文件的按分片字幕存储。
  ///
  /// - [dir]: resolves the cache directory (shared with
  ///   [MovaFileSttSubStore]'s whole-source cache — chunk files are
  ///   distinguished by their composite key, so they don't collide) /
  ///   解析缓存目录（与 [MovaFileSttSubStore] 的整段缓存共用同一目录——
  ///   分片文件靠复合 key 区分，不会冲突）
  MovaFileSttChunkSubStore({required this.dir});

  /// Resolves the cache directory.
  ///
  /// 解析缓存目录。
  final MovaSttSubDirProv dir;

  @override
  Future<List<MovaSttCue>?> loadChunk(String sourceKey, int chunkIndex) async {
    final file = await _fileFor(sourceKey, chunkIndex);
    if (!await file.exists()) return null;
    try {
      return parseSrt(await file.readAsString());
    } on Object {
      // A corrupt cache file degrades to "not cached" rather than crashing —
      // the caller re-decodes this chunk and overwrites it.
      //
      // 缓存文件损坏时降级为"未缓存"而非崩溃——调用方会重新解码本分片并
      // 覆盖它。
      return null;
    }
  }

  @override
  Future<void> saveChunk(String sourceKey, int chunkIndex, List<MovaSttCue> cues) async {
    final file = await _fileFor(sourceKey, chunkIndex);
    await file.parent.create(recursive: true);
    await file.writeAsString(formatSrt(cues), flush: true);
  }

  @override
  Future<void> removeAllChunks(String sourceKey) async {
    final root = Directory(await dir.resolve());
    if (!await root.exists()) return;
    final prefix = '${_sourcePrefix(sourceKey)}.';
    await for (final entry in root.list()) {
      if (entry is File && entry.uri.pathSegments.last.startsWith(prefix)) {
        await entry.delete();
      }
    }
  }

  Future<File> _fileFor(String sourceKey, int chunkIndex) async {
    final root = await dir.resolve();
    return File('$root${Platform.pathSeparator}${_sourcePrefix(sourceKey)}.$chunkIndex.srt');
  }

  // Chunk files share a `<sourceHash>.` name prefix (distinct from
  // [MovaFileSttSubStore]'s bare `<sourceHash>.srt`) so [removeAllChunks]
  // can find every chunk belonging to a source by prefix scan without a
  // separate index file.
  //
  // 分片文件共用 `<sourceHash>.` 前缀（区别于 [MovaFileSttSubStore] 的
  // 裸 `<sourceHash>.srt`），使 [removeAllChunks] 能靠前缀扫描找到某个来源
  // 的全部分片，不需要额外的索引文件。
  String _sourcePrefix(String sourceKey) => 'chunk-${fnv1a64(sourceKey).toRadixString(36)}';
}
