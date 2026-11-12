import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/wheel.dart';

/// 仅调用转盘配置转换函数，验证其它兼容转换函数能够被摇掉。
void main() {
  final result = wheelFromLuckyCanvasConfig(
      jsonDecode('{"prizes":[{"fonts":[{"text":"奖品"}]}]}')
          as Map<String, dynamic>);
  runApp(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: LuckyWheel(config: result.config))));
}
