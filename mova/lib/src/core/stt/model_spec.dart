/// One file a model needs, already extracted and individually downloadable
/// (not a `.tar.bz2` bundle — see `doc/notes/2026-08-04-stt-engine-decision.md`
/// for why: sherpa-onnx's official GitHub Releases ship archives, so the
/// default source re-hosts the already-extracted plain files rather than
/// decompressing on-device).
///
/// 模型所需的单个文件，已解压、可单独下载（不是 `.tar.bz2` 压缩包——原因见
/// `doc/notes/2026-08-04-stt-engine-decision.md`：sherpa-onnx 官方 GitHub
/// Releases 发布的是压缩包，因此默认源改为重新托管已解压好的裸文件，而不是
/// 在端上解压）。
class MovaSttModelFile {
  /// Creates a model file descriptor.
  ///
  /// 创建一个模型文件描述。
  const MovaSttModelFile({required this.name, required this.url, this.sha256, this.sizeBytes});

  /// Relative filename this file is cached under, e.g. `'encoder.int8.onnx'`.
  ///
  /// 该文件在缓存中使用的相对文件名，如 `'encoder.int8.onnx'`。
  final String name;

  /// The URL to download this file from.
  ///
  /// 下载该文件的 URL。
  final Uri url;

  /// Expected SHA-256 hex digest, informational only: mova does not verify it.
  /// The legitimacy of a model's source is the host's responsibility; the
  /// loader only downloads and reports failures.
  ///
  /// 预期的 SHA-256 十六进制摘要，仅作信息记录：mova 不校验它。模型来源是否合法
  /// 由宿主自行保证，加载器只负责下载并报告失败。
  final String? sha256;

  /// Expected size in bytes, if known; a cached file whose size matches is
  /// reused instead of downloaded again.
  ///
  /// 已知的预期字节数；已缓存文件大小与之相符时直接复用，不再重新下载。
  final int? sizeBytes;
}

/// A named, versioned set of files one STT engine needs on disk before it
/// can be constructed.
///
/// 一个具名、带版本的文件集合，某个 STT 引擎在构造前需要它们都已落盘。
class MovaSttModelSpec {
  /// Creates a model spec.
  ///
  /// 创建一个模型描述。
  ///
  /// - [id]: a stable identifier used as the cache sub-directory name and to
  ///   distinguish this model/version from others, e.g.
  ///   `'zipformer-zh-en-2023-11-22'` / 作为缓存子目录名、用于与其他模型/
  ///   版本区分的稳定标识
  /// - [files]: every file required / 所需的全部文件
  const MovaSttModelSpec({required this.id, required this.files});

  /// Stable identifier for this model/version.
  ///
  /// 该模型/版本的稳定标识。
  final String id;

  /// Every file required before this model is usable.
  ///
  /// 该模型可用前所需的全部文件。
  final List<MovaSttModelFile> files;
}

/// The resolved local paths for a [MovaSttModelSpec] once every file is cached.
///
/// [MovaSttModelSpec] 的每个文件都已缓存落盘后，解析出的本地路径集合。
class MovaSttModelFiles {
  /// Creates a resolved file-path set.
  ///
  /// 创建一个已解析的文件路径集合。
  const MovaSttModelFiles(this.paths);

  /// Maps each [MovaSttModelFile.name] to its absolute local path.
  ///
  /// 把每个 [MovaSttModelFile.name] 映射到其本地绝对路径。
  final Map<String, String> paths;

  /// Returns the local path cached under [name], or null if not present.
  ///
  /// 返回缓存在 [name] 下的本地路径；不存在则返回 null。
  ///
  /// - [name]: the file name to look up / 要查找的文件名
  String? operator [](String name) => paths[name];
}
