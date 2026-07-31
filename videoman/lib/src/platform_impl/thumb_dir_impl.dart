import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/preview/dir_provider.dart';

/// The default [VmThumbDirProvider]: a named folder under the platform
/// temporary directory, e.g. `<tmp>/videoman_thumbs`.
///
/// Lives outside `lib/src/core/**` because `path_provider` is a Flutter
/// plugin and the core layer must stay plugin-free.
///
/// 默认的 [VmThumbDirProvider]：平台临时目录下的一个命名文件夹，
/// 例如 `<tmp>/videoman_thumbs`。
///
/// 放在 `lib/src/core/**` 之外，因为 `path_provider` 是 Flutter 插件，
/// core 层必须与插件解耦。
class TempThumbDirProvider implements VmThumbDirProvider {
  /// Creates a provider rooted at the temporary directory.
  ///
  /// 创建一个以临时目录为根的 provider。
  ///
  /// - [folderName]: sub-folder name under the temp directory /
  ///   临时目录下的子文件夹名
  const TempThumbDirProvider({this.folderName = 'videoman_thumbs'});

  /// Sub-folder name under the platform temporary directory.
  ///
  /// 平台临时目录下的子文件夹名。
  final String folderName;

  @override
  Future<String> resolve() async {
    final tmp = await getTemporaryDirectory();
    return '${tmp.path}${Platform.pathSeparator}$folderName';
  }
}
