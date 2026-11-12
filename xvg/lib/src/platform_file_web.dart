import 'dart:typed_data';

/// 浏览器不支持本地 file: 路径，请使用 asset、memory 或 network。
class File {
  /// 保存路径用于诊断。
  const File(this.path);

  /// 原始文件路径。
  final String path;

  /// 浏览器无法读取本地路径。
  Future<Uint8List> readAsBytes() => Future.error(UnsupportedError(_message));

  /// 浏览器无法读取本地路径。
  Future<String> readAsString() => Future.error(UnsupportedError(_message));
}

/// 不支持本地文件的诊断。
const _message =
    'Xvg: file: paths are unsupported on web; use asset, memory or network';
