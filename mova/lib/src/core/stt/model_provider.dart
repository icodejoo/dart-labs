import 'dart:async';
import 'dart:io';

import 'model_dir_provider.dart';
import 'model_spec.dart';
import '../preview/fetcher.dart';

/// One step of progress while [MovaSttModelProv.ensure] downloads a spec's
/// files.
///
/// [MovaSttModelProv.ensure] 下载某个 spec 的文件时的一步进度。
class MovaSttModelProg {
  /// Creates a progress step.
  ///
  /// 创建一步进度。
  const MovaSttModelProg({
    required this.modelId,
    required this.fileName,
    required this.completedFiles,
    required this.totalFiles,
  });

  /// The [MovaSttModelSpec.id] this progress belongs to.
  ///
  /// 该进度所属的 [MovaSttModelSpec.id]。
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

/// Thrown by [MovaSttModelProv.ensure] when a file could not be obtained.
///
/// [MovaSttModelProv.ensure] 在某个文件无法获取时抛出。
class MovaSttModelLoadError implements Exception {
  /// Creates the exception.
  ///
  /// 创建该异常。
  const MovaSttModelLoadError(this.modelId, this.fileName);

  /// The [MovaSttModelSpec.id] the failing file belongs to.
  ///
  /// 失败文件所属的 [MovaSttModelSpec.id]。
  final String modelId;

  /// The [MovaSttModelFile.name] that failed to download.
  ///
  /// 下载失败的 [MovaSttModelFile.name]。
  final String fileName;

  @override
  String toString() => 'MovaSttModelLoadError: failed to fetch "$fileName" for "$modelId"';
}

/// Downloads and caches an [MovaSttModelSpec]'s files on disk, skipping files
/// already cached, and resolves to their local paths once every file is
/// present.
///
/// Unlike the scrub-preview cache (which degrades silently on any failure —
/// a missing thumbnail is a non-event), a missing model file blocks the STT
/// feature outright, so [ensure] throws [MovaSttModelLoadError] instead
/// of swallowing the failure.
///
/// 把 [MovaSttModelSpec] 的文件下载并缓存到磁盘，跳过已缓存的文件，待所有
/// 文件就绪后解析出本地路径。
///
/// 与拖动预览缓存（任何失败都静默降级——缺一张缩略图不算事）不同，缺一个
/// 模型文件会直接挡住整个 STT 功能，因此 [ensure] 会抛出
/// [MovaSttModelLoadError]，而不是吞掉失败。
abstract class MovaSttModelProv {
  /// Emits one [MovaSttModelProg] step per file as [ensure] works through
  /// a spec.
  ///
  /// [ensure] 处理一个 spec 时，每个文件产出一步 [MovaSttModelProg]。
  Stream<MovaSttModelProg> get progress;

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
  /// Throws [MovaSttModelLoadError] if any file cannot be obtained.
  ///
  /// 若任一文件无法获取，抛出 [MovaSttModelLoadError]。
  Future<MovaSttModelFiles> ensure(MovaSttModelSpec spec);

  /// Deletes every cached file for [modelId], if any.
  ///
  /// 删除 [modelId] 下所有已缓存的文件（若有）。
  ///
  /// - [modelId]: the [MovaSttModelSpec.id] to remove / 要删除的
  ///   [MovaSttModelSpec.id]
  Future<void> remove(String modelId);
}

/// The production [MovaSttModelProv]: one sub-directory per model id,
/// skipping files whose cached size already matches
/// [MovaSttModelFile.sizeBytes].
///
/// 生产环境的 [MovaSttModelProv]：每个模型 id 一个子目录，若已缓存文件的
/// 大小已匹配 [MovaSttModelFile.sizeBytes] 则跳过下载。
class MovaSttModelLoader implements MovaSttModelProv {
  /// Creates a downloader.
  ///
  /// 创建一个下载器。
  ///
  /// - [dir]: resolves the root cache directory / 解析缓存根目录
  /// - [fetcher]: downloads each file's bytes / 下载每个文件的字节
  MovaSttModelLoader({required this.dir, required this.fetcher});

  /// Resolves the root cache directory; each model gets a sub-directory
  /// named after [MovaSttModelSpec.id] under it.
  ///
  /// 解析缓存根目录；每个模型在其下拥有一个以 [MovaSttModelSpec.id] 命名的
  /// 子目录。
  final MovaSttModelDirProv dir;

  /// Downloads each file's bytes.
  ///
  /// 下载每个文件的字节。
  final MovaHttpFetch fetcher;

  final StreamController<MovaSttModelProg> _progress =
      StreamController<MovaSttModelProg>.broadcast();

  @override
  Stream<MovaSttModelProg> get progress => _progress.stream;

  @override
  Future<MovaSttModelFiles> ensure(MovaSttModelSpec spec) async {
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
        if (bytes == null) throw MovaSttModelLoadError(spec.id, file.name);
        await local.writeAsBytes(bytes, flush: true);
      }
      paths[file.name] = path;
      completed++;
      if (!_progress.isClosed) {
        _progress.add(MovaSttModelProg(
          modelId: spec.id,
          fileName: file.name,
          completedFiles: completed,
          totalFiles: spec.files.length,
        ));
      }
    }
    return MovaSttModelFiles(paths);
  }

  @override
  Future<void> remove(String modelId) async {
    final root = await dir.resolve();
    final modelDir = Directory('$root${Platform.pathSeparator}$modelId');
    if (await modelDir.exists()) await modelDir.delete(recursive: true);
  }
}
