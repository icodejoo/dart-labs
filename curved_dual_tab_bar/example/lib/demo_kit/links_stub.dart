import 'package:flutter/services.dart';

/// 非网页平台复制外链，返回是否已打开新窗口。
Future<bool> openDemoLink(String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  return false;
}
