import 'package:flutter/material.dart';

/// Web 不启用原生脚本入口；公开压测页由 demo_kit 导航提供。
Widget buildBenchApp(String initialRoute) => const SizedBox.shrink();
