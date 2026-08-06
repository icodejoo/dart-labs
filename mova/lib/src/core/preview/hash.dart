/// 64-bit FNV-1a offset basis.
///
/// FNV-1a 64 位算法的初始偏移量。
const int _kOffsetBasis = 0xcbf29ce484222325;

/// 64-bit FNV-1a prime.
///
/// FNV-1a 64 位算法的质数因子。
const int _kPrime = 0x100000001b3;

/// Computes a 64-bit FNV-1a hash of [input], masked to a non-negative Dart int.
///
/// Self-written on purpose: cache keys need no cryptographic strength, and this
/// keeps `package:crypto` out of the dependency list (DESIGN §12).
///
/// 计算 [input] 的 64 位 FNV-1a 哈希，并掩码为非负 Dart int。
///
/// 刻意自写：缓存 key 不需要密码学强度，这样可以不引入 `package:crypto`
/// （DESIGN §12）。
///
/// - [input]: the string to hash / 要哈希的字符串
///
/// Returns a non-negative 63-bit hash value.
///
/// 返回一个非负的 63 位哈希值。
int fnv1a64(String input) {
  var hash = _kOffsetBasis;
  for (var i = 0; i < input.length; i++) {
    final unit = input.codeUnitAt(i);
    hash ^= unit & 0xFF;
    hash = (hash * _kPrime) & 0xFFFFFFFFFFFFFFFF;
    if (unit > 0xFF) {
      hash ^= (unit >> 8) & 0xFF;
      hash = (hash * _kPrime) & 0xFFFFFFFFFFFFFFFF;
    }
  }
  return hash & 0x7FFFFFFFFFFFFFFF;
}

/// Builds the default cache key for one thumbnail.
///
/// Shape is `<fnv1a64(sourceKey) in base36>_<bucketSec>_<width>` — the hash
/// keeps the key filename-safe and bounded, while bucket and width stay in
/// clear text so a cache directory can be eyeballed while debugging.
///
/// 生成一张缩略图的默认缓存 key。
///
/// 形如 `<fnv1a64(sourceKey) 的 36 进制>_<bucketSec>_<width>`——哈希保证 key
/// 可作文件名且长度有界，桶秒数与宽度保留明文，便于调试时肉眼查看缓存目录。
///
/// - [sourceKey]: stable identifier of the media source, usually its URI /
///   媒体源的稳定标识，通常是其 URI
/// - [bucketSec]: bucket-aligned position in whole seconds / 桶对齐位置（整秒）
/// - [width]: requested frame width in pixels / 请求的帧宽度（像素）
///
/// Returns the cache key.
///
/// 返回缓存 key。
String defaultCacheKey(String sourceKey, int bucketSec, int width) =>
    '${fnv1a64(sourceKey).toRadixString(36)}_${bucketSec}_$width';

/// Strategy for building thumbnail cache keys; see [defaultCacheKey].
///
/// 缩略图缓存 key 的构建策略；参见 [defaultCacheKey]。
///
/// - [sourceKey]: stable identifier of the media source / 媒体源的稳定标识
/// - [bucketSec]: bucket-aligned position in whole seconds / 桶对齐位置（整秒）
/// - [width]: requested frame width in pixels / 请求的帧宽度（像素）
///
/// Returns the cache key.
///
/// 返回缓存 key。
typedef MovaCacheKeyBldr = String Function(String sourceKey, int bucketSec, int width);
