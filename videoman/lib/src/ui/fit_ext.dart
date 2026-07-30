import 'package:flutter/widgets.dart';

import '../core/model/fit.dart';

/// Maps a [VmFit] to the Flutter [BoxFit] used by the video surface.
///
/// 把 [VmFit] 映射为视频画面使用的 Flutter [BoxFit]。
///
/// - [fit]: fill mode / 填充模式
///
/// Returns the matching [BoxFit].
///
/// 返回对应的 [BoxFit]。
BoxFit vmBoxFit(VmFit fit) => switch (fit) {
      VmFit.contain => BoxFit.contain,
      VmFit.cover => BoxFit.cover,
      VmFit.fill => BoxFit.fill,
    };

/// Resolves a [VmFit]'s [VmFit.labelKey] to its Chinese display label.
///
/// 把 [VmFit] 的 [VmFit.labelKey] 解析为中文显示文案。
///
/// - [fit]: fill mode / 填充模式
///
/// Returns the display label.
///
/// 返回显示文案。
String vmFitLabel(VmFit fit) => switch (fit) {
      VmFit.contain => '适应',
      VmFit.cover => '裁剪',
      VmFit.fill => '拉伸',
    };
