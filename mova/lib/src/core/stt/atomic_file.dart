import 'dart:io';

/// Writes flushed bytes to a unique sibling before replacing [target].
/// Failed writes leave the previous cache entry intact.
///
/// 将字节刷入唯一的同级临时文件后替换 [target]；写入失败保留旧缓存。
///
/// - [target]: final cache path / 最终缓存路径
/// - [bytes]: complete payload / 完整内容
Future<void> writeSttCacheFile(File target, List<int> bytes) async {
  await target.parent.create(recursive: true);
  final staging = await target.parent.createTemp('.mova-stt-pending-');
  try {
    final temporary = File('${staging.path}${Platform.pathSeparator}data');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  } finally {
    await staging.delete(recursive: true);
  }
}
