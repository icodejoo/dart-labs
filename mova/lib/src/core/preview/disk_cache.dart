import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'cache.dart';
import 'dir_lease.dart';
import 'dir_provider.dart';

/// File-name suffix used for every cached thumbnail.
///
/// 每个缓存缩略图文件使用的扩展名后缀。
const String _kSuffix = '.thumb';

/// A [IMovaThumbCache] backed by a directory of files, evicting by total bytes
/// with least-recently-touched-first ordering.
///
/// Recency is the file's last-modified stamp: [write] sets it implicitly and
/// [read] refreshes it, so a thumbnail that keeps getting re-read survives.
/// Every filesystem error is swallowed — a broken cache directory must degrade
/// the preview feature, never crash playback.
///
/// 以文件目录为后端的 [IMovaThumbCache]，按总字节数淘汰，最久未触碰者先删。
///
/// "最近使用"以文件的 last-modified 时间戳为准：[write] 会隐式更新它，
/// [read] 会主动刷新它，因此反复被读取的缩略图不会被淘汰。所有文件系统错误
/// 都被吞掉——缓存目录坏掉只能让预览功能降级，绝不能让播放崩溃。
class MovaDiskThumbCache implements IMovaThumbCache {
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
  final IMovaThumbDirProvider dir;

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
  File _file(Directory d, String key) =>
      File('${d.path}${Platform.pathSeparator}$key$_kSuffix');

  /// 首次访问时异步扫描一次，后续操作增量维护索引。
  final Map<String, ({int size, DateTime touched})> _index = {};

  /// 索引是否已从磁盘读取。
  bool _indexed = false;

  /// 串行化索引与文件操作，避免并发写入破坏预算。
  Future<void> _queue = Future<void>.value();

  /// 将 [action] 排入操作队列；返回该操作的结果。
  Future<T> _run<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object e, StackTrace st) {});
    return result;
  }

  /// 在 [d] 下异步读取文件元数据；比较器只读内存。
  Future<void> _loadIndex(Directory d) async {
    if (_indexed) return;
    await for (final entity in d.list()) {
      if (entity is! File || !entity.path.endsWith(_kSuffix)) continue;
      try {
        final stat = await entity.stat();
        final name = entity.uri.pathSegments.last;
        _index[name.substring(0, name.length - _kSuffix.length)] = (
          size: stat.size,
          touched: stat.modified,
        );
      } on FileSystemException {
        // 外部删除的文件不入索引。
      }
    }
    _indexed = true;
  }

  /// Sums encoded bytes from the current index. / 汇总当前索引中的编码字节数。
  int get _indexedBytes =>
      _index.values.fold<int>(0, (sum, entry) => sum + entry.size);

  /// Evicts oldest entries only when the byte budget is exceeded.
  ///
  /// 按内存索引删除 [d] 中的最旧条目，直到满足预算；未超预算时跳过排序。
  Future<void> _evict(Directory d) async {
    var total = _indexedBytes;
    if (total <= maxBytes) return;
    final keys = _index.keys.toList()
      ..sort((a, b) => _index[a]!.touched.compareTo(_index[b]!.touched));
    for (final key in keys) {
      if (total <= maxBytes) break;
      try {
        final file = _file(d, key);
        if (await file.exists()) await file.delete();
        total -= _index.remove(key)!.size;
      } on FileSystemException {
        // 无法删除时保留索引，留给下次淘汰重试。
      }
    }
  }

  /// 返回索引中的编码字节总数；无参数。示例：`await cache.totalBytes()`。
  Future<int> totalBytes() => _run(() async {
    try {
      final d = await _dir();
      if (d == null) return 0;
      await _loadIndex(d);
      return _indexedBytes;
    } on FileSystemException {
      return 0;
    }
  });

  /// 淘汰至 [maxBytes]；无返回值。示例：`await cache.evict()`。
  Future<void> evict() => _run(() async {
    try {
      final d = await _dir();
      if (d == null) return;
      await _loadIndex(d);
      await _evict(d);
    } on FileSystemException {
      // 缓存失败不影响播放。
    }
  });

  @override
  Uint8List? peek(String key) => null;

  @override
  Future<Uint8List?> read(String key) => _run(() async {
    try {
      final d = await _dir();
      if (d == null) return null;
      await _loadIndex(d);
      final file = _file(d, key);
      if (!await file.exists()) {
        _index.remove(key);
        return null;
      }
      final bytes = await file.readAsBytes();
      final now = DateTime.now();
      await file.setLastModified(now);
      _index[key] = (size: bytes.lengthInBytes, touched: now);
      return bytes;
    } on FileSystemException {
      return null;
    }
  });

  @override
  Future<void> write(String key, Uint8List bytes) => _run(() async {
    if (maxBytes <= 0) return;
    try {
      final d = await _dir();
      if (d == null) return;
      await _loadIndex(d);
      await _file(d, key).writeAsBytes(bytes, flush: true);
      _index[key] = (size: bytes.lengthInBytes, touched: DateTime.now());
      await _evict(d);
    } on FileSystemException {
      // 文件失败不影响播放。
    }
  });

  @override
  Future<void> clear() => _run(() async {
    try {
      final d = await _dir();
      if (d == null) return;
      await _loadIndex(d);
      for (final key in _index.keys.toList()) {
        try {
          final file = _file(d, key);
          if (await file.exists()) await file.delete();
          _index.remove(key);
        } on FileSystemException {
          // 无法删除时保留条目以便重试。
        }
      }
    } on FileSystemException {
      // 目录不可用时静默降级。
    }
  });

  @override
  Future<void> dispose() async {
    await _queue;
    // Only leased providers opt into cache-owned teardown; ordinary directory
    // resolvers retain their contract without a new port requirement.
    //
    // 只有租约 provider 选择由缓存负责销毁；普通解析器契约不变，端口不加新要求。
    if (dir case final IMovaThumbDirLease lease) await lease.dispose();
  }
}
