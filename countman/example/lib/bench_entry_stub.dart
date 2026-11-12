import 'package:flutter/material.dart';

/// Web 不编译任何桌面基准页面，此函数只用于条件导入。
Widget buildBenchApp(String initialRoute) => const SizedBox.shrink();
