/// Resolves the on-disk directory downloaded STT model files are cached in.
///
/// Kept as a port for the same reason as `MovaThumbDirProv`: the default
/// answer needs `path_provider` (`getApplicationSupportDirectory()`), a
/// Flutter plugin that must not be imported from `lib/src/core/**`. The
/// concrete implementation lives in
/// `lib/src/platform_impl/stt_model_dir_impl.dart`.
///
/// 解析已下载 STT 模型文件的磁盘缓存目录。
///
/// 做成端口的原因与 `MovaThumbDirProv` 相同：默认答案需要 `path_provider`
/// （`getApplicationSupportDirectory()`）——它是 Flutter 插件，
/// `lib/src/core/**` 下不允许引入。具体实现放在
/// `lib/src/platform_impl/stt_model_dir_impl.dart`。
abstract class MovaSttModelDirProv {
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

/// A [MovaSttModelDirProv] that always returns one fixed path.
///
/// Lets hosts pin the model cache location and keeps tests free of plugin
/// channels.
///
/// 恒定返回同一路径的 [MovaSttModelDirProv]。
///
/// 既支持宿主固定模型缓存位置，也让测试无需依赖插件通道。
class FixedSttModelDirProvider implements MovaSttModelDirProv {
  /// Creates a provider pinned to [path].
  ///
  /// 创建一个固定指向 [path] 的 provider。
  ///
  /// - [path]: absolute cache directory path / 缓存目录的绝对路径
  const FixedSttModelDirProvider(this.path);

  /// The fixed cache directory path.
  ///
  /// 固定的缓存目录路径。
  final String path;

  @override
  Future<String> resolve() async => path;
}
