/// Resolves the on-disk directory thumbnails are cached in.
///
/// Kept as a port because the default answer needs `path_provider`
/// (`getTemporaryDirectory()`), a Flutter plugin that must not be imported
/// from `lib/src/core/**`. The concrete implementation lives in
/// `lib/src/platform_impl/thumb_dir_impl.dart`.
///
/// 解析缩略图磁盘缓存所在目录。
///
/// 之所以做成端口，是因为默认答案需要 `path_provider`
/// （`getTemporaryDirectory()`）——它是 Flutter 插件，`lib/src/core/**`
/// 下不允许引入。具体实现放在 `lib/src/platform_impl/thumb_dir_impl.dart`。
abstract class MovaThumbDirProv {
  /// Returns the absolute path of the cache directory; the caller creates it
  /// if it does not exist yet.
  ///
  /// 返回缓存目录的绝对路径；目录不存在时由调用方负责创建。
  ///
  /// Returns the directory path.
  ///
  /// 返回目录路径。
  Future<String> resolve();
}

/// A [MovaThumbDirProv] that always returns one fixed path.
///
/// Backs the `diskDir` config knob and keeps disk-cache tests free of
/// plugin channels.
///
/// 恒定返回同一路径的 [MovaThumbDirProv]。
///
/// 既支撑 `diskDir` 配置项，也让磁盘缓存测试无需依赖插件通道。
class FixedThumbDirProvider implements MovaThumbDirProv {
  /// Creates a provider pinned to [path].
  ///
  /// 创建一个固定指向 [path] 的 provider。
  ///
  /// - [path]: absolute cache directory path / 缓存目录的绝对路径
  const FixedThumbDirProvider(this.path);

  /// The fixed cache directory path.
  ///
  /// 固定的缓存目录路径。
  final String path;

  @override
  Future<String> resolve() async => path;
}
