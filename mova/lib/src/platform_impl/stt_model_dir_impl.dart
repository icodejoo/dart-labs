import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/stt/model_dir_provider.dart';

/// The default [MovaSttModelDirProv]: a named folder under the platform's
/// persistent application-support directory, e.g.
/// `<app support>/mova_stt_models`.
///
/// Unlike thumbnails (cheap to re-derive, so [TempThumbDirProvider] uses the
/// OS temp directory), STT model files are large downloads that should
/// survive OS temp-directory cleanup — hence application-support rather than
/// temporary storage.
///
/// Lives outside `lib/src/core/**` because `path_provider` is a Flutter
/// plugin and the core layer must stay plugin-free.
///
/// 默认的 [MovaSttModelDirProv]：应用持久化支持目录下的一个命名文件夹，
/// 例如 `<app support>/mova_stt_models`。
///
/// 与缩略图不同（重新生成代价很低，因此 `TempThumbDirProvider` 用系统临时
/// 目录）——STT 模型文件是体积较大的下载产物，应当扛得住系统清理临时目录，
/// 因此用应用支持目录而非临时存储。
///
/// 放在 `lib/src/core/**` 之外，因为 `path_provider` 是 Flutter 插件，
/// core 层必须与插件解耦。
class TempSttModelDirProvider implements MovaSttModelDirProv {
  /// Creates a provider rooted at the application-support directory.
  ///
  /// 创建一个以应用支持目录为根的 provider。
  ///
  /// - [folderName]: sub-folder name under the application-support
  ///   directory / 应用支持目录下的子文件夹名
  const TempSttModelDirProvider({this.folderName = 'mova_stt_models'});

  /// Sub-folder name under the platform application-support directory.
  ///
  /// 平台应用支持目录下的子文件夹名。
  final String folderName;

  @override
  Future<String> resolve() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}$folderName';
  }
}
