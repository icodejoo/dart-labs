// Parse-time bridge from the Dart animation engine to the Rust value parsers
// (`parse_color`/`parse_transform`, backed by `svgtypes` — the same crate usvg
// parses with). Deliberately NOT used per animation frame: every helper here is
// called once per attribute while building the [SvgDocument], and its result is
// stored in the document model, so the per-frame sampling/painting path stays
// pure Dart numeric work (see fsvg CLAUDE.md: per-frame work must not cross FFI).
//
// If the native library isn't loaded (plain `flutter test` on the host VM, where
// no Flutter build step produced `fsvg.dll`/`.so`), every helper degrades to
// `null` instead of throwing — matching this engine's "unsupported construct
// renders as invisible, never crashes" convention. The unavailability is latched
// after the first failure so a document full of colours doesn't pay repeated
// exception costs.
//
// Dart 动画引擎在**解析阶段**通往 Rust 取值解析器（`parse_color`/
// `parse_transform`，底层是 `svgtypes`——usvg 自身解析用的同一个 crate）的桥。
// 刻意不用于每一动画帧：本文件的每个函数都只在构建 [SvgDocument] 时按属性调用
// 一次，结果存进文档模型，因此逐帧采样/绘制路径仍是纯 Dart 数值运算（见 fsvg
// CLAUDE.md：每帧的活不得跨 FFI）。
//
// 若原生库未加载（纯 `flutter test` 的 host VM 下没有 Flutter 构建步骤产出的
// `fsvg.dll`/`.so`），所有函数退化为返回 `null` 而非抛错——符合本引擎"不支持的
// 结构表现为不可见、绝不崩溃"的一贯约定。首次失败后会记住不可用状态，避免一份
// 含大量颜色的文档反复付出异常开销。

import '../rust/api/svg.dart' as rust;

bool _nativeUnavailable = false;

/// Resolves any CSS3/SVG colour string to `#RRGGBBAA` hex via Rust, or null
/// when it isn't a colour (or the native library is unavailable).
///
/// The point is the **named-colour table** (`red`, `cornflowerblue`, ...):
/// `svgtypes` already carries the complete CSS3 one, so the Dart engine
/// doesn't hand-roll it. Plain hex is handled in Dart (see `svg_style.dart`)
/// and never reaches here.
///
/// 通过 Rust 把任意 CSS3/SVG 颜色字符串解析为 `#RRGGBBAA` 十六进制串；不是颜色
/// （或原生库不可用）时返回 null。
///
/// 意义在于**具名颜色表**（`red`、`cornflowerblue` 等）：`svgtypes` 已有完整的
/// CSS3 颜色表，Dart 侧不必手写。纯十六进制由 Dart 自行处理（见
/// `svg_style.dart`），不会走到这里。
///
/// Example:
/// ```dart
/// resolveColorToHex('red'); // '#FF0000FF'
/// ```
String? resolveColorToHex(String raw) {
  if (_nativeUnavailable) return null;
  try {
    final rgba = rust.parseColor(s: raw);
    if (rgba == null) return null;
    final hex = StringBuffer('#');
    for (final byte in rgba) {
      hex.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return hex.toString().toUpperCase();
  } catch (_) {
    _nativeUnavailable = true;
    return null;
  }
}

/// Parses a full SVG `transform` list into the composed affine matrix
/// `[a, b, c, d, e, f]` via Rust, or null when malformed / the native library
/// is unavailable.
///
/// Handles the whole grammar (`translate`/`scale`/`rotate` with an optional
/// pivot/`skewX`/`skewY`/`matrix`, in any combination), which is exactly the
/// part not worth re-implementing in Dart.
///
/// 通过 Rust 把完整的 SVG `transform` 列表解析为合成后的仿射矩阵
/// `[a, b, c, d, e, f]`；格式非法或原生库不可用时返回 null。
///
/// 覆盖整套语法（`translate`/`scale`/带可选支点的 `rotate`/`skewX`/`skewY`/
/// `matrix` 的任意组合），正是不值得在 Dart 里重写的那部分。
///
/// Example:
/// ```dart
/// parseTransformMatrix('translate(10,20)'); // [1, 0, 0, 1, 10, 20]
/// ```
List<double>? parseTransformMatrix(String raw) {
  if (_nativeUnavailable) return null;
  try {
    final matrix = rust.parseTransform(s: raw);
    if (matrix == null || matrix.length != 6) return null;
    return matrix.map((v) => v.toDouble()).toList(growable: false);
  } catch (_) {
    _nativeUnavailable = true;
    return null;
  }
}
