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
