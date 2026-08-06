import 'dart:io';
import 'dart:typed_data';

import 'cache.dart';
import 'dir_provider.dart';

/// File-name suffix used for every cached thumbnail.
///
/// 每个缓存缩略图文件使用的扩展名后缀。
const String _kSuffix = '.thumb';

/// A [MovaThumbCache] backed by a directory of files, evicting by total bytes
/// with least-recently-touched-first ordering.
///
/// Recency is the file's last-modified stamp: [write] sets it implicitly and
/// [read] refreshes it, so a thumbnail that keeps getting re-read survives.
/// Every filesystem error is swallowed — a broken cache directory must degrade
/// the preview feature, never crash playback.
///
/// 以文件目录为后端的 [MovaThumbCache]，按总字节数淘汰，最久未触碰者先删。
///
/// "最近使用"以文件的 last-modified 时间戳为准：[write] 会隐式更新它，
/// [read] 会主动刷新它，因此反复被读取的缩略图不会被淘汰。所有文件系统错误
/// 都被吞掉——缓存目录坏掉只能让预览功能降级，绝不能让播放崩溃。
class MovaDiskThumbCache implements MovaThumbCache {
  /// Creates a disk cache rooted at [dir]'s resolved path.
  ///
  /// 创建一个以 [dir] 解析出的路径为根的磁盘缓存。
  ///
  /// - [dir]: directory resolver / 目录解析器
  /// - [maxBytes]: total byte budget; `0` or negative disables caching /
  ///   总字节预算；为 `0` 或负数时禁用缓存
  MovaDiskThumbCache({required this.dir, this.maxBytes = 64 * 1024 * 1024});

  /// Resolver for the cache directory.
  ///
  /// 缓存目录的解析器。
  final MovaThumbDirProv dir;

  /// Total byte budget across all cached files.
  ///
  /// 所有缓存文件加起来的字节预算。
  final int maxBytes;

  /// Memoised, already-created cache directory, or null before first use or
  /// when the directory could not be created.
  ///
  /// 已创建并缓存下来的目录对象；首次使用前或目录创建失败时为 null。
  Directory? _resolved;

  /// Resolves and creates the cache directory once, returning null when the
  /// filesystem refuses.
  ///
  /// 一次性解析并创建缓存目录；文件系统拒绝时返回 null。
  ///
  /// Returns the directory, or null when unusable.
  ///
  /// 返回目录对象；不可用时返回 null。
  Future<Directory?> _dir() async {
    final cached = _resolved;
    if (cached != null) return cached;
    try {
      final d = Directory(await dir.resolve());
      if (!await d.exists()) await d.create(recursive: true);
      _resolved = d;
      return d;
    } on FileSystemException {
      return null;
    }
  }

  /// Maps [key] to its backing file inside [d].
  ///
  /// 把 [key] 映射为 [d] 目录下对应的文件。
  ///
  /// - [d]: the cache directory / 缓存目录
  /// - [key]: the cache key / 缓存 key
  ///
  /// Returns the backing file handle.
  ///
  /// 返回对应的文件句柄。
  File _file(Directory d, String key) => File('${d.path}${Platform.pathSeparator}$key$_kSuffix');

  /// Lists every cached file, newest-touched last; empty when unusable.
  ///
  /// 列出全部缓存文件，最近被触碰的排在最后；不可用时返回空列表。
  ///
  /// Returns the sorted file list.
  ///
  /// 返回排序后的文件列表。
  Future<List<File>> _entries() async {
    final d = await _dir();
    if (d == null) return const <File>[];
    try {
      final files = (await d.list().toList())
          .whereType<File>()
          .where((f) => f.path.endsWith(_kSuffix))
          .toList();
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      return files;
    } on FileSystemException {
      return const <File>[];
    }
  }

  /// Sums the byte size of every cached file.
  ///
  /// 统计全部缓存文件的字节总和。
  ///
  /// Returns the total size in bytes; `0` when the cache is unusable.
  ///
  /// 返回总字节数；缓存不可用时返回 `0`。
  Future<int> totalBytes() async {
    var total = 0;
    for (final f in await _entries()) {
      try {
        total += await f.length();
      } on FileSystemException {
        continue;
      }
    }
    return total;
  }

  /// Deletes least-recently-touched files until the total fits [maxBytes].
  ///
  /// 从最久未触碰的文件开始删，直到总量落回 [maxBytes] 以内。
  Future<void> evict() async {
    final files = await _entries();
    var total = 0;
    final sizes = <File, int>{};
    for (final f in files) {
      try {
        final len = await f.length();
        sizes[f] = len;
        total += len;
      } on FileSystemException {
        continue;
      }
    }
    for (final f in files) {
      if (total <= maxBytes) break;
      try {
        await f.delete();
        total -= sizes[f] ?? 0;
      } on FileSystemException {
        continue;
      }
    }
  }

  @override
  Uint8List? peek(String key) => null;

  @override
  Future<Uint8List?> read(String key) async {
    final d = await _dir();
    if (d == null) return null;
    final f = _file(d, key);
    try {
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      await f.setLastModified(DateTime.now());
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (maxBytes <= 0) return;
    final d = await _dir();
    if (d == null) return;
    try {
      await _file(d, key).writeAsBytes(bytes, flush: true);
    } on FileSystemException {
      return;
    }
    await evict();
  }

  @override
  Future<void> clear() async {
    for (final f in await _entries()) {
      try {
        await f.delete();
      } on FileSystemException {
        continue;
      }
    }
  }

  @override
  Future<void> dispose() async {}
}
