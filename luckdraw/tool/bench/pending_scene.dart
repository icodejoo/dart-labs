import 'package:flutter/material.dart';

import 'lib/main.dart' show kBenchSize;

/// 构造统一冷push页面；[scene] 为 null 时只有 Scaffold 与空 SizedBox。
///
/// 非空玩法使用与历史基准一致的320逻辑像素约束，不在这里启动动画或预热玩法。
Widget pendingFirstFramePage(Widget? scene) => Scaffold(
    body: scene == null
        ? const SizedBox.shrink()
        : Center(child: SizedBox.square(dimension: kBenchSize, child: scene)));
