// Hand-written SVGs exercising `<mask>`, `<linearGradient>`/`<radialGradient>`,
// and `<clipPath>` — techniques the MDI icon corpus in mdi_icons_1000.dart
// barely touches, used by the mask/gradient/clipPath cold-start deep-dive in
// doc/performance-benchmarks.md. All 32x32 viewBox, matching the 32x32 cell
// size the other static-window benchmarks use, so results are comparable.
//
// 手写的 SVG 样本，分别用到 `<mask>`、`<linearGradient>`/`<radialGradient>`、
// `<clipPath>`——这几种技巧在 mdi_icons_1000.dart 的 MDI 图标语料里几乎不出现，
// 供 doc/performance-benchmarks.md 里 mask/gradient/clipPath 冷启动深挖使用。
// 统一 32x32 viewBox，与其它静态窗口基准的 32x32 格子尺寸一致，结果可比。

/// Two `<mask>`, two gradient-fill, two `<clipPath>` samples — six sources
/// total, small enough to hand-verify by eye, varied enough that cold-start
/// rendering does real geometry/compositing work for each technique.
///
/// 两个 `<mask>`、两个渐变填充、两个 `<clipPath>` 样本，共六个源——数量小到能
/// 肉眼核对，种类够多，让每种技巧的冷启动渲染都有真实的几何/合成工作量。
///
/// Example:
/// ```dart
/// final n = complexSvgSamples.length; // 6
/// ```
final List<String> complexSvgSamples = [
  // mask #1: a circle mask cut out of a filled square.
  // mask 一号：从实心方块上抠出一个圆形遮罩。
  '''
<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <mask id="m1">
      <rect x="0" y="0" width="32" height="32" fill="white"/>
      <circle cx="16" cy="16" r="10" fill="black"/>
    </mask>
  </defs>
  <rect x="0" y="0" width="32" height="32" fill="#2b6cb0" mask="url(#m1)"/>
</svg>
''',
  // mask #2: a luminance gradient mask fading a shape out.
  // mask 二号：用亮度渐变遮罩让形状渐隐。
  '''
<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="mg2" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="white"/>
      <stop offset="1" stop-color="black"/>
    </linearGradient>
    <mask id="m2">
      <rect x="0" y="0" width="32" height="32" fill="url(#mg2)"/>
    </mask>
  </defs>
  <polygon points="16,2 30,30 2,30" fill="#c53030" mask="url(#m2)"/>
</svg>
''',
  // gradient #1: linear gradient fill across a rounded rect.
  // 渐变一号：圆角矩形上的线性渐变填充。
  '''
<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g1" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#f6ad55"/>
      <stop offset="0.5" stop-color="#ed8936"/>
      <stop offset="1" stop-color="#dd6b20"/>
    </linearGradient>
  </defs>
  <rect x="3" y="3" width="26" height="26" rx="6" fill="url(#g1)"/>
</svg>
''',
  // gradient #2: radial gradient fill on a circle.
  // 渐变二号：圆形上的径向渐变填充。
  '''
<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="g2" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#9ae6b4"/>
      <stop offset="1" stop-color="#276749"/>
    </radialGradient>
  </defs>
  <circle cx="16" cy="16" r="14" fill="url(#g2)"/>
</svg>
''',
  // clipPath #1: a star clipped to a circular viewport.
  // clipPath 一号：五角星被圆形裁剪区裁掉边角。
  '''
<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <clipPath id="c1">
      <circle cx="16" cy="16" r="12"/>
    </clipPath>
  </defs>
  <polygon points="16,1 20,12 31,12 22,19 25,30 16,23 7,30 10,19 1,12 12,12"
    fill="#805ad5" clip-path="url(#c1)"/>
</svg>
''',
  // clipPath #2: two overlapping rects clipped to an ellipse.
  // clipPath 二号：两个重叠矩形被椭圆裁剪区裁掉边角。
  '''
<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <clipPath id="c2">
      <ellipse cx="16" cy="16" rx="15" ry="9"/>
    </clipPath>
  </defs>
  <g clip-path="url(#c2)">
    <rect x="0" y="0" width="16" height="32" fill="#3182ce"/>
    <rect x="16" y="0" width="16" height="32" fill="#e53e3e"/>
  </g>
</svg>
''',
];
