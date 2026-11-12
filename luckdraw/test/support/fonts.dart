import 'dart:io';

import 'package:flutter/services.dart';

/// Roboto 是否已成功加载，供 golden 与 parity 测试检查。
bool luckyTestFontsLoaded = false;

/// Flutter SDK 中测试字体的相对路径。
const String kLuckyRobotoPath =
    'bin/cache/artifacts/material_fonts/roboto-regular.ttf';

/// 查找 SDK 的 Roboto；显式 [flutterRoot] 优先，否则从 [executable] 上溯。
///
/// 字体不存在时抛出带候选路径的 [FileSystemException]。
File findLuckyTestFont({String? flutterRoot, required String executable}) {
  final candidates = <String>[];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    candidates.add('$flutterRoot/$kLuckyRobotoPath');
  } else {
    var directory = File(executable).absolute.parent;
    while (true) {
      candidates.add('${directory.path}/$kLuckyRobotoPath');
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
  }
  for (final path in candidates) {
    final font = File(path);
    if (font.existsSync()) return font;
  }
  throw FileSystemException(
      'Roboto 测试字体不存在；请设置 FLUTTER_ROOT 并运行 flutter precache --universal。已检查: ${candidates.join(', ')}');
}

/// 从 Flutter SDK 加载 family 为 Roboto 的测试字体；失败时明确报错。
Future<void> loadLuckyTestFonts() async {
  if (luckyTestFontsLoaded) return;
  final font = findLuckyTestFont(
      flutterRoot: Platform.environment['FLUTTER_ROOT'],
      executable: Platform.resolvedExecutable);
  final loader = FontLoader('Roboto')
    ..addFont(
        Future<ByteData>.value(ByteData.sublistView(await font.readAsBytes())));
  await loader.load();
  luckyTestFontsLoaded = true;
}
