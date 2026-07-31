import 'dart:typed_data';

import 'cache.dart';

/// Composes a fast synchronous level (memory) over a slow persistent one
/// (disk).
///
/// [peek] only ever consults [memory], so a scrub that lands on an already
/// resident bucket renders in the same frame. [read] falls through to [disk]
/// and back-fills [memory] so the next scrub over the same bucket is
/// instantaneous. [write] fans out to both levels.
///
/// 把一个同步的快速层（内存）叠加在慢速持久层（磁盘）之上。
///
/// [peek] 只查 [memory]，因此拖到已驻留的桶时可在同一帧渲染出来。[read] 会
/// 下探到 [disk] 并回填 [memory]，让下次拖到同一个桶时瞬时命中。[write] 同时
/// 写入两层。
class VmTwoLevelCache implements VmThumbCache {
  /// Creates a two-level cache over [memory] and [disk].
  ///
  /// 用 [memory] 与 [disk] 组成两级缓存。
  ///
  /// - [memory]: the fast, synchronously peekable level / 可同步 peek 的快速层
  /// - [disk]: the slow, persistent level / 慢速持久层
  VmTwoLevelCache({required this.memory, required this.disk});

  /// The fast level; must answer [VmThumbCache.peek] without I/O.
  ///
  /// 快速层；其 [VmThumbCache.peek] 必须不做 I/O。
  final VmThumbCache memory;

  /// The slow, persistent level.
  ///
  /// 慢速持久层。
  final VmThumbCache disk;

  @override
  Uint8List? peek(String key) => memory.peek(key);

  @override
  Future<Uint8List?> read(String key) async {
    final hit = memory.peek(key);
    if (hit != null) return hit;
    final fromDisk = await disk.read(key);
    if (fromDisk != null) await memory.write(key, fromDisk);
    return fromDisk;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    await memory.write(key, bytes);
    await disk.write(key, bytes);
  }

  @override
  Future<void> clear() async {
    await memory.clear();
    await disk.clear();
  }

  @override
  Future<void> dispose() async {
    await memory.dispose();
    await disk.dispose();
  }
}
