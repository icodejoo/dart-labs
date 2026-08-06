/// Resolves the on-disk directory pre-generated (batch) subtitle files are
/// cached in.
///
/// A distinct port from [MovaSttModelDirProv] even though both resolve to
/// a similar "app support sub-folder" answer by default — they cache
/// different things with different lifetimes (a handful of small text files
/// keyed by source, vs. a handful of large model files keyed by model id),
/// and a host may reasonably want to point them at different places (e.g.
/// clearing subtitle cache without re-downloading models). The concrete
/// implementation lives in
/// `lib/src/platform_impl/stt_subtitle_dir_impl.dart`.
///
/// 解析预生成（批量）字幕文件的磁盘缓存目录。
///
/// 与 [MovaSttModelDirProv] 是两个独立的端口，即便两者默认都落在类似的
/// "应用支持目录子文件夹"——它们缓存的是不同的东西、生命周期也不同（少量
/// 按来源做 key 的小文本文件，vs 少量按模型 id 做 key 的大模型文件），宿主
/// 完全可能想把它们指到不同位置（例如只清字幕缓存、不用重新下载模型）。
/// 具体实现放在 `lib/src/platform_impl/stt_subtitle_dir_impl.dart`。
abstract class MovaSttSubDirProv {
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

/// A [MovaSttSubDirProv] that always returns one fixed path.
///
/// Lets hosts pin the subtitle cache location and keeps tests free of plugin
/// channels.
///
/// 恒定返回同一路径的 [MovaSttSubDirProv]。
///
/// 既支持宿主固定字幕缓存位置，也让测试无需依赖插件通道。
class FixedSttSubtitleDirProvider implements MovaSttSubDirProv {
  /// Creates a provider pinned to [path].
  ///
  /// 创建一个固定指向 [path] 的 provider。
  ///
  /// - [path]: absolute cache directory path / 缓存目录的绝对路径
  const FixedSttSubtitleDirProvider(this.path);

  /// The fixed cache directory path.
  ///
  /// 固定的缓存目录路径。
  final String path;

  @override
  Future<String> resolve() async => path;
}
