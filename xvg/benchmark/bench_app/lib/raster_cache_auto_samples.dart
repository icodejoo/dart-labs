import 'dart:math' as math;

// ignore: implementation_imports
import 'package:xvg/src/rust/api/svg.dart';

import 'complex_svg_samples.dart';
import 'mdi_icons_1000.dart';

/// 透明度入层与裁剪入栈的原生显示列表命令编号。
const _pushOpacity = 2, _pushClip = 4;

/// 已在采样前指定用途的 SVG。
typedef AutoSample = ({String id, String source, bool validation});

/// 返回固定样本集；外部插画由调用方在运行时读取。
List<AutoSample> autoSamples(String aurora, String runtimeSvg) => [
  for (final index in [0, 12, 236, 500, 789, 999])
    (
      id: 'mdi-$index',
      source: mdiIcons1000[index],
      validation: index == 236 || index == 999,
    ),
  for (var index = 0; index < complexSvgSamples.length; index++)
    (
      id: 'complex-${index + 1}',
      source: complexSvgSamples[index],
      validation: index == 1 || index == 5,
    ),
  (id: 'aurora', source: aurora, validation: false),
  (id: '233KB', source: runtimeSvg, validation: true),
  for (final count in [50, 200, 1000, 5000, 20000])
    for (final variant in ['plain', 'blur-grad', 'layers-grad', 'blur-layers'])
      (
        id: 'synthetic-$count-$variant',
        source: syntheticAutoSvg(
          count,
          blur: variant.startsWith('blur'),
          layers: variant.contains('layers'),
          gradients: variant.endsWith('grad'),
        ),
        validation: count == 1000 || (count == 5000 && variant == 'blur-grad'),
      ),
  for (final variant in ['blur', 'layers', 'grad', 'blur-layers-grad'])
    (
      id: 'synthetic-200-$variant',
      source: syntheticAutoSvg(
        200,
        blur: variant.startsWith('blur'),
        layers: variant.contains('layers'),
        gradients: variant.endsWith('grad'),
      ),
      validation: variant == 'blur-layers-grad',
    ),
];

/// 生成 [count] 条可见路径；效果始终施加在独立且有重叠的固定数量图元上。
String syntheticAutoSvg(
  int count, {
  bool blur = false,
  bool layers = false,
  bool gradients = false,
}) {
  const span = 512;
  const overlayCount = 4;
  const paint = 'url(#paint)';
  const fill = '#4969ba';
  const backdrop = '<path fill="#152446" d="M0 0H512V512H0Z"/>';
  final svg = StringBuffer('''
<svg xmlns="http://www.w3.org/2000/svg" width="$span" height="$span" viewBox="0 0 $span $span">
<defs>
  <linearGradient id="paint" x2="1" y2="1">
    <stop stop-color="#64d3c3"/><stop offset="1" stop-color="#945dba"/>
  </linearGradient>
  <filter id="soft"><feGaussianBlur stdDeviation="12"/></filter>
  <clipPath id="inset"><rect x="8" y="8" width="496" height="496" rx="40"/></clipPath>
  <mask id="coverage" mask-type="alpha" maskUnits="userSpaceOnUse" x="0" y="0" width="$span" height="$span">
    <ellipse cx="256" cy="256" rx="225" ry="210" fill="white"/>
  </mask>
</defs>
$backdrop
''');
  final color = gradients ? paint : fill;
  if (layers) svg.write('<g clip-path="url(#inset)" opacity=".82">');
  for (var index = 0; index < overlayCount; index++) {
    final start = 38 + index * 34;
    final filter = blur ? ' filter="url(#soft)"' : '';
    final mask = layers && index.isEven ? ' mask="url(#coverage)"' : '';
    svg.write(
      '<path fill="$color" fill-opacity=".46"$filter$mask '
      'd="M$start 72 C410 15 478 225 372 326 C190 488 24 356 $start 72Z"/>',
    );
  }
  if (layers) svg.write('</g>');

  final random = math.Random(1107);
  final smallCount = count - overlayCount - 1;
  final columns = math.sqrt(smallCount).ceil();
  final step = span / columns;
  for (var index = 0; index < smallCount; index++) {
    final x = ((index % columns + .15 + random.nextDouble() * .24) * step)
        .toStringAsFixed(2);
    final y = ((index ~/ columns + .12 + random.nextDouble() * .24) * step)
        .toStringAsFixed(2);
    final size = step * (.55 + random.nextDouble() * .36);
    final end = size.toStringAsFixed(2);
    final half = (size / 2).toStringAsFixed(2);
    final lift = (-size / 3).toStringAsFixed(2);
    final stroke = index % 7 == 0
        ? ' stroke="#e6d8ff" stroke-width="${(step / 12).toStringAsFixed(2)}"'
        : '';
    final particleColor = gradients && index % 5 == 0 ? paint : fill;
    svg.write(
      '<path fill="$particleColor"$stroke d="M$x $y '
      'c$half $lift $end 0 $end $half q0 $half -$half $half l-$half -$half Z"/>',
    );
  }
  svg.write('</svg>');
  return svg.toString();
}

/// 从原生场景的主绘制列表提取每次录制只需计算一次的计数。
Map<String, int> autoFeatures(SvgScene scene) {
  var verbs = 0, points = 0, strokes = 0, gradients = 0;
  var opacity = 0, clips = 0, masks = 0, blurs = 0;
  for (final path in scene.paths) {
    verbs += path.verbs.length;
    points += path.points.length ~/ 2;
    if (path.hasStroke) strokes++;
    if (path.fillGradient != null) gradients++;
    if (path.strokeGradient != null) gradients++;
    if (path.effects?.mask != null) masks++;
    if (path.effects?.blur != null) blurs++;
  }
  for (final image in scene.images) {
    if (image.mask != null) masks++;
    if (image.blur != null) blurs++;
  }
  for (final command in scene.displayList?.commands ?? const <SvgCommand>[]) {
    if (command.kind == _pushOpacity) opacity++;
    if (command.kind == _pushClip) clips++;
  }
  return {
    'paths': scene.paths.length,
    'verbs': verbs,
    'points': points,
    'strokes': strokes,
    'gradients': gradients,
    'opacity': opacity,
    'clips': clips,
    'masks': masks,
    'blurs': blurs,
    'images': scene.images.length,
  };
}

/// 补充 Picture 坐标中的内容边界、面积比及原生图案数。
Map<String, Object?> autoR2Features(SvgScene scene) {
  final bounds = scene.contentBounds;
  final known =
      bounds != null &&
      [
        bounds.left,
        bounds.top,
        bounds.right,
        bounds.bottom,
      ].every((v) => v.isFinite);
  final contentArea = known
      ? math.max(0.0, bounds.right - bounds.left) *
            math.max(0.0, bounds.bottom - bounds.top)
      : null;
  var patterns = 0;
  for (final path in scene.paths) {
    final effects = path.effects;
    if (effects?.fillPattern != null) patterns++;
    if (effects?.strokePattern != null) patterns++;
  }
  return {
    ...autoFeatures(scene),
    'patterns': patterns,
    'picture_width': scene.width,
    'picture_height': scene.height,
    'content_bounds': known
        ? [bounds.left, bounds.top, bounds.right, bounds.bottom]
        : null,
    'content_area': contentArea,
    'content_area_ratio':
        contentArea == null || scene.width <= 0 || scene.height <= 0
        ? null
        : contentArea / (scene.width * scene.height),
    'content_overflow': known
        ? bounds.left < 0 ||
              bounds.top < 0 ||
              bounds.right > scene.width ||
              bounds.bottom > scene.height
        : null,
  };
}

/// 识别原生复杂度限制，避免输出 SVG 原文或本机路径。
String autoR2Error(Object error) {
  final message = error.toString();
  if (RegExp(
    'too complex|budget|exceeds .*limit',
    caseSensitive: false,
  ).hasMatch(message)) {
    return 'complexity_budget';
  }
  return error.runtimeType.toString();
}
