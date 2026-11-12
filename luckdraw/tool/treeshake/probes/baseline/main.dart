import 'package:flutter/widgets.dart';

/// 不引用 luckdraw 的 Web 体积基线。
void main() {
  runApp(const Directionality(
      textDirection: TextDirection.ltr, child: Text('luckdraw')));
}
