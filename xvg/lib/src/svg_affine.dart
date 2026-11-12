/// Shared affine-matrix helpers for SVG's `[a, b, c, d, e, f]` convention
/// (`x' = a·x + c·y + e`, `y' = b·x + d·y + f`).
///
/// Used by both the static (`rust_static_svg.dart`) and animated
/// (`animation/animated_svg_painter.dart`, `animation/svg_gradient.dart`)
/// rendering pipelines — previously each hand-rolled its own copy of the same
/// formulas.
///
/// SVG `[a, b, c, d, e, f]` 约定下的共享仿射矩阵工具函数
/// （`x' = a·x + c·y + e`，`y' = b·x + d·y + f`）。
///
/// 静态渲染管线（`rust_static_svg.dart`）和动画渲染管线
/// （`animation/animated_svg_painter.dart`、`animation/svg_gradient.dart`）
/// 共用——此前两条管线各自手写了一份相同公式。
library;

import 'dart:typed_data';

/// Composes two `[a, b, c, d, e, f]` affine transforms, returning
/// `first ∘ second` — [second] applies first, then [first].
///
/// 合成两个 `[a, b, c, d, e, f]` 仿射变换，返回 `first ∘ second`——先作用
/// [second]，再作用 [first]。
List<double> concatAffine(List<double> first, List<double> second) => [
  first[0] * second[0] + first[2] * second[1],
  first[1] * second[0] + first[3] * second[1],
  first[0] * second[2] + first[2] * second[3],
  first[1] * second[2] + first[3] * second[3],
  first[0] * second[4] + first[2] * second[5] + first[4],
  first[1] * second[4] + first[3] * second[5] + first[5],
];

/// Expands an `[a, b, c, d, e, f]` affine transform into the column-major
/// 4x4 [Float64List] expected by `Canvas`/`Shader` transform APIs.
///
/// 把 `[a, b, c, d, e, f]` 仿射变换展开为 `Canvas`/`Shader` 变换 API 所需的
/// 列主序 4x4 [Float64List]。
Float64List affineToMatrix4(List<double> m) {
  final out = Float64List(16);
  out[0] = m[0];
  out[1] = m[1];
  out[4] = m[2];
  out[5] = m[3];
  out[10] = 1;
  out[12] = m[4];
  out[13] = m[5];
  out[15] = 1;
  return out;
}
