import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/stt/subtitle_dir_provider.dart';

/// The default [MovaSttSubDirProv]: a named folder under the
/// platform's persistent application-support directory, e.g.
/// `<app support>/mova_stt_subtitles`.
///
/// Persistent, like [TempSttModelDirProvider] and for the same reason: a
/// batch-transcribed subtitle file is exactly the kind of thing that should
/// survive OS temp-directory cleanup, since regenerating it means paying for
/// a full re-transcription.
///
/// Lives outside `lib/src/core/**` because `path_provider` is a Flutter
/// plugin and the core layer must stay plugin-free.
///
/// 默认的 [MovaSttSubDirProv]：应用持久化支持目录下的一个命名文件夹，
/// 例如 `<app support>/mova_stt_subtitles`。
///
/// 持久化，理由与 [TempSttModelDirProvider] 相同：批量转写出的字幕文件正是
/// 那种该扛得住系统清理临时目录的东西——重新生成意味着要再付一次完整转写的
/// 代价。
///
/// 放在 `lib/src/core/**` 之外，因为 `path_provider` 是 Flutter 插件，
/// core 层必须与插件解耦。
class TempSttSubtitleDirProvider implements MovaSttSubDirProv {
  /// Creates a provider rooted at the application-support directory.
  ///
  /// 创建一个以应用支持目录为根的 provider。
  ///
  /// - [folderName]: sub-folder name under the application-support
  ///   directory / 应用支持目录下的子文件夹名
  const TempSttSubtitleDirProvider({this.folderName = 'mova_stt_subtitles'});

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
