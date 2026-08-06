import 'package:flutter/widgets.dart';

import '../core/model/fit.dart';

/// Maps a [MovaFit] to the Flutter [BoxFit] used by the video surface.
///
/// 把 [MovaFit] 映射为视频画面使用的 Flutter [BoxFit]。
///
/// - [fit]: fill mode / 填充模式
///
/// Returns the matching [BoxFit].
///
/// 返回对应的 [BoxFit]。
BoxFit movaBoxFit(MovaFit fit) => switch (fit) {
      MovaFit.contain => BoxFit.contain,
      MovaFit.cover => BoxFit.cover,
      MovaFit.fill => BoxFit.fill,
    };
