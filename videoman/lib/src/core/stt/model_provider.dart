import 'dart:async';
import 'dart:io';

import 'model_dir_provider.dart';
import 'model_spec.dart';
import '../preview/fetcher.dart';

/// One step of progress while [VmSttModelProvider.ensure] downloads a spec's
/// files.
///
/// [VmSttModelProvider.ensure] 下载某个 spec 的文件时的一步进度。
class VmSttModelProgress {
  /// Creates a progress step.
  ///
  /// 创建一步进度。
  const VmSttModelProgress({
    required this.modelId,
    required this.fileName,
    required this.completedFiles,
    required this.totalFiles,
  });

  /// The [VmSttModelSpec.id] this progress belongs to.
  ///
  /// 该进度所属的 [VmSttModelSpec.id]。
  final String modelId;

  /// The file just finished (downloaded or found already cached).
  ///
  /// 刚完成的文件（下载完成或发现已缓存）。
  final String fileName;

  /// How many of [totalFiles] are done, including this one.
  ///
  /// 含本次在内，[totalFiles] 中已完成的数量。
  final int completedFiles;

  /// Total files in the spec being ensured.
  ///
  /// 本次 ensure 的 spec 总文件数。
  final int totalFiles;
}

/// Thrown by [VmSttModelProvider.ensure] when a file could not be obtained.
///
/// [VmSttModelProvider.ensure] 在某个文件无法获取时抛出。
class VmSttModelDownloadException implements Exception {
  /// Creates the exception.
  ///
  /// 创建该异常。
  const VmSttModelDownloadException(this.modelId, this.fileName);

  /// The [VmSttModelSpec.id] the failing file belongs to.
  ///
  /// 失败文件所属的 [VmSttModelSpec.id]。
  final String modelId;

  /// The [VmSttModelFile.name] that failed to download.
  ///
  /// 下载失败的 [VmSttModelFile.name]。
  final String fileName;

  @override
  String toString() => 'VmSttModelDownloadException: failed to fetch "$fileName" for "$modelId"';
}

/// Downloads and caches an [VmSttModelSpec]'s files on disk, skipping files
/// already cached, and resolves to their local paths once every file is
/// present.
///
/// Unlike the scrub-preview cache (which degrades silently on any failure —
/// a missing thumbnail is a non-event), a missing model file blocks the STT
/// feature outright, so [ensure] throws [VmSttModelDownloadException] instead
/// of swallowing the failure.
///
/// 把 [VmSttModelSpec] 的文件下载并缓存到磁盘，跳过已缓存的文件，待所有
/// 文件就绪后解析出本地路径。
///
/// 与拖动预览缓存（任何失败都静默降级——缺一张缩略图不算事）不同，缺一个
/// 模型文件会直接挡住整个 STT 功能，因此 [ensure] 会抛出
/// [VmSttModelDownloadException]，而不是吞掉失败。
abstract class VmSttModelProvider {
  /// Emits one [VmSttModelProgress] step per file as [ensure] works through
  /// a spec.
  ///
  /// [ensure] 处理一个 spec 时，每个文件产出一步 [VmSttModelProgress]。
  Stream<VmSttModelProgress> get progress;

  /// Ensures every file in [spec] is present on disk, downloading whatever is
  /// missing, and returns their resolved local paths.
  ///
  /// 确保 [spec] 里的每个文件都已落盘，缺失的会被下载，返回已解析的本地路径。
  ///
  /// - [spec]: the model to ensure / 要确保就绪的模型
  ///
  /// Returns the resolved local file paths.
  ///
  /// 返回已解析的本地文件路径。
  ///
  /// Throws [VmSttModelDownloadException] if any file cannot be obtained.
  ///
  /// 若任一文件无法获取，抛出 [VmSttModelDownloadException]。
  Future<VmSttModelFiles> ensure(VmSttModelSpec spec);

  /// Deletes every cached file for [modelId], if any.
  ///
  /// 删除 [modelId] 下所有已缓存的文件（若有）。
  ///
  /// - [modelId]: the [VmSttModelSpec.id] to remove / 要删除的
  ///   [VmSttModelSpec.id]
  Future<void> remove(String modelId);
}

/// The production [VmSttModelProvider]: one sub-directory per model id,
/// skipping files whose cached size already matches
/// [VmSttModelFile.sizeBytes].
///
/// 生产环境的 [VmSttModelProvider]：每个模型 id 一个子目录，若已缓存文件的
/// 大小已匹配 [VmSttModelFile.sizeBytes] 则跳过下载。
class VmSttModelDownloader implements VmSttModelProvider {
  /// Creates a downloader.
  ///
  /// 创建一个下载器。
  ///
  /// - [dir]: resolves the root cache directory / 解析缓存根目录
  /// - [fetcher]: downloads each file's bytes / 下载每个文件的字节
  VmSttModelDownloader({required this.dir, required this.fetcher});

  /// Resolves the root cache directory; each model gets a sub-directory
  /// named after [VmSttModelSpec.id] under it.
  ///
  /// 解析缓存根目录；每个模型在其下拥有一个以 [VmSttModelSpec.id] 命名的
  /// 子目录。
  final VmSttModelDirProvider dir;

  /// Downloads each file's bytes.
  ///
  /// 下载每个文件的字节。
  final VmHttpFetcher fetcher;

  final StreamController<VmSttModelProgress> _progress =
      StreamController<VmSttModelProgress>.broadcast();

  @override
  Stream<VmSttModelProgress> get progress => _progress.stream;

  @override
  Future<VmSttModelFiles> ensure(VmSttModelSpec spec) async {
    final root = await dir.resolve();
    final modelDir = Directory('$root${Platform.pathSeparator}${spec.id}');
    if (!await modelDir.exists()) await modelDir.create(recursive: true);

    final paths = <String, String>{};
    var completed = 0;
    for (final file in spec.files) {
      final path = '${modelDir.path}${Platform.pathSeparator}${file.name}';
      final local = File(path);
      final cached = await local.exists() &&
          (file.sizeBytes == null || await local.length() == file.sizeBytes);
      if (!cached) {
        final bytes = await fetcher.get(file.url);
        if (bytes == null) throw VmSttModelDownloadException(spec.id, file.name);
        await local.writeAsBytes(bytes, flush: true);
      }
      paths[file.name] = path;
      completed++;
      if (!_progress.isClosed) {
        _progress.add(VmSttModelProgress(
          modelId: spec.id,
          fileName: file.name,
          completedFiles: completed,
          totalFiles: spec.files.length,
        ));
      }
    }
    return VmSttModelFiles(paths);
  }

  @override
  Future<void> remove(String modelId) async {
    final root = await dir.resolve();
    final modelDir = Directory('$root${Platform.pathSeparator}$modelId');
    if (await modelDir.exists()) await modelDir.delete(recursive: true);
  }
}
