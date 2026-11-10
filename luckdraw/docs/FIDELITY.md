# luckdraw 上游行为对照表（FIDELITY）

> 状态：已按落地事实对齐（第三轮，2026-11-10）。真机集成、最低版本与 Web/APK 摇树已取得本地证据；真机性能验收未完全通过，Linux/远程 CI 与真实发布仍待验证。
> 上游：lucky-canvas `7a8c0bbcb992a297b390e3a2ebaa1a3385c1f2f9`，`packages/core/src`（1.7.26）。行号均指该 commit。
> 用途：落地者"照着翻译"的依据。每一行写清：上游位置 → luckdraw 位置 → 一致性等级 → 公式/伪代码 → 偏离量与理由。
> 一致性等级（定义见 ARCHITECTURE §11.1）：**逐位**、**等价**、**IMP**（为规避上游问题的有意改进）、**DEV**（有意偏离，非 issue 驱动）、**N/A**（不支持）。
> 编号：`FID-L*` 基类、`FID-U*` 工具函数、`FID-W*` 转盘、`FID-G*` 九宫格、`FID-S*` 老虎机、`IMP-*`、`DEV-*`、`U-*`（上游疑点）。验收矩阵（TEST_STRATEGY §5）按这些编号挂测试。

---

## 1. 移植时必须遵守的数值规则

| 规则 | 说明 |
| --- | --- |
| JS `%` → Dart `.remainder()` | JS 取余结果与被除数同号；Dart 的 `%` 是欧几里得取模（`-30 % 360 == 330`，本机实测），**凡移植上游 `%` 一律用 `x.remainder(y)`** |
| `>> 0` → `.toInt()` 之后转回 double | 向零截断（上游只用于正数字号、渐变端点与 `currIndex`，不涉及 int32 溢出） |
| 运算顺序照抄 | 例如 quad easeIn 必须写成 `c * x * x + b`（`x = t / d`），不能化简成 `b + c * x * x`；停止候选必须按上游加减顺序书写（见各节） |
| JS 假值 → Dart null | 上游 `a \|\| b` 在 `a` 为 `''`/`0`/`undefined` 时取 `b`；类型化 API 用 `null` 表示"未设置"，compat 负责把 `''`、`0`（凡上游会被 `\|\|` 吞掉的位置）转成 null |
| `Math.random()` → 注入的 `math.Random.nextDouble()` | 调用次数与顺序与上游一致：`stop()` 无 index 时 1 次（`computeRange`），转盘减速开始时 1 次（`stopRange`，即使 `stopRange == 0` 也调用） |
| `Date.now()` → 有效时间（毫秒，double） | 由 `LuckyTimeline` 提供 |
| 超越函数 | `cos/sin/tan/pow/sqrt` 在 Dart VM 与 V8 可能差 1 ulp，对照测试用相对误差 1e-9 |

B1/D3 已接受默认 `time` + `MonotonicStopSolver`。本文「逐帧逐位」仅指 compat `strictUpstream()` 的 `frame` + `UpstreamStopSolver` 及已列出的 IMP/DEV 例外，不承诺默认时间归一化轨迹逐帧等于上游。最终对照：转盘 6 例 2520 帧、九宫格 5 例 2100 帧、老虎机 5 例 2100 帧全部精确相等（老虎机按 U-06/IMP-05 映射首减速帧）。基线来自 npm lucky-canvas@1.7.26，MANIFEST 锁定 SHA-256，16 用例 / 96 产物（6720 数值帧、80 PNG）。

图像最终分层（TEST_STRATEGY §6.5）：通道阈值 32，标准层差异像素 ≤1.8% / 均误 ≤1.8；text-heavy 只含 w04/60（670 个差异像素全部在文字区，去文字后为零）；edge-aa 只含 s03/60、s03/240、s05/settled、s05/240，逐帧实测 ×1.1，均不超过 4% / 2.5。DIAG/DIAG2/DIAG3 确认残余为文字光栅化和 reel 列边界 1 像素抗锯齿采样，几何位置无误；s03/s05 已解除跳过并通过。s05 的 settled 是取消截图标签，不表示中奖结算。依据见 `test/parity/FINDINGS.md` 最终 DIAG3 节，早期 skip 结论为历史记录。

---

## 2. 文件级映射

| 上游文件 | 行数 | luckdraw 位置 | 等级 |
| --- | --- | --- | --- |
| `index.ts` | 8 | `lib/luckdraw.dart`、`lib/wheel.dart`、`lib/grid.dart`、`lib/slot.dart` | 等价（导出 `cutRound`/`opacity` 的替代见 FID-U18/U19） |
| `lib/lucky.ts` | 434 | `core/widgets/game_view.dart`（生命周期/尺寸）、`core/geometry/image_box.dart`、`core/foundation/length.dart`、`core/image/image_resolver.dart` | 部分 N/A，见 §3 |
| `lib/wheel.ts` | 566 | `lib/src/wheel/**` | 见 §5 |
| `lib/grid.ts` | 651 | `lib/src/grid/**` | 见 §6 |
| `lib/slot.ts` | 630 | `lib/src/slot/**` | 见 §7 |
| `utils/math.ts` | 226 | `core/geometry/*`、`core/foundation/fill.dart`（legacyLinear） | 见 §3 |
| `utils/tween.ts` | 98 | `core/easing/easing.dart` | 逐位 |
| `utils/index.ts` | 201 | `core/text/split_text.dart`、`core/picker/prize_picker.dart`、`core/foundation/edge_insets.dart`、`core/foundation/fill.dart`（hasBackground 语义）、`slot/layout/slot_layout.dart`（getSortedArrayByIndex） | 见 §3 |
| `utils/image.ts` | 133 | `core/foundation/image.dart`（`borderRadius`/`opacity` 字段） | 见 §3.6（FID-U18…U21） |
| `utils/polyfill.js` | 108 | — | N/A（JS 运行时补丁） |
| `observer/*`（5 个文件，257 行） | 257 | — | N/A（Flutter Widget 生命周期替代） |
| `types/*.ts` | 345 | 各 `model/*.dart`、`core/foundation/*.dart` | 见 §4 |

---

## 3. 函数级映射：基类与工具函数

### 3.1 `lib/lucky.ts`

| 编号 | 上游 | 行号 | luckdraw | 等级 | 说明 |
| --- | --- | --- | --- | --- | --- |
| FID-L01 | `constructor`（el/divElement/canvas 创建、click 监听、resize 节流 300ms、MutationObserver） | 26-73 | `LuckyGameView`（Widget 树、`GestureDetector`、`LayoutBuilder`） | N/A→等价 | 尺寸变化由 Flutter 布局驱动；无 300ms 节流（布局变化当帧生效，IMP-07） |
| FID-L02 | `resize()`：beforeResize → setHTMLFontSize → setDpr → resetWidthAndHeight → zoomCanvas | 78-88 | 宿主在尺寸/dpr 变化时：`hooks.beforeResize` → 重算布局 → `hooks.afterResize` | 等价 | 转盘子类在 resize 里 `translate(Radius, Radius)` 后立即 draw（wheel.ts:79-85）；luckdraw 在下一帧 paint |
| FID-L03 | `initLucky()`：resize，宽高为 0 时 `console.error` | 93-98 | 尺寸为 0 → 布局 `isEmpty`，不绘制 | 等价 | ARCHITECTURE §10 |
| FID-L04 | `handleClick(e)` 空实现 | 104 | `LuckyGame.hitTestAll` | 等价 | |
| FID-L05 | `setHTMLFontSize()` | 109-112 | compat `LuckyCanvasCompatOptions.remBase`（默认 16） | N/A（核心）/等价（compat） | |
| FID-L06 | `clearCanvas()` | 115-118 | — | N/A | Flutter 每帧画布本就是新的 |
| FID-L07 | `setDpr()` | 124-133 | `MediaQuery.devicePixelRatioOf` | N/A | |
| FID-L08 | `resetWidthAndHeight()`：`getLength(data.width \|\| config.width) \|\| offsetWidth` | 138-155 | Widget `width`/`height`，缺省取父约束 | 等价 | 上游 `width: '80%'` 按分母 1 解析为 0.8px（U-26），compat 对百分比宽高给 warning 并返回 null（交给父约束） |
| FID-L09 | `zoomCanvas()` | 160-172 | — | N/A | |
| FID-L10 | `initWindowFunction()`（rAF/setTimeout 注入） | 177-203 | `LuckyClock` | N/A→等价 | |
| FID-L11 | `isWeb()` | 205-207 | — | N/A | |
| FID-L12 | `loadImg(src, info)`：WEB 下 `new Image()` + crossorigin；其它平台把 resolve 挂在 info 上交给外部 | 214-234 | `LuckyImageResolver` | 等价 | 空 src 在上游 reject；类型化 API 要求非空 `ImageProvider` |
| FID-L13 | `drawImage(ctx, img, ...rect)`（4 或 8 参数；小程序 getImageData 分支；try/catch 吞 Safari IndexSizeError） | 241-280 | `canvas.drawImageRect(img, src, dst, paint)`，`paint.filterQuality = FilterQuality.low`（≈ Canvas 默认双线性） | 等价 | 8 参数形式只用于老虎机离屏复制，luckdraw 无此用法（ADR-11） |
| FID-L14 | `computedWidthAndHeight(img, info, maxW, maxH)` | 290-316 | `computeImageBox(naturalSize, width, height, maxWidth, maxHeight)` | 逐位 | 见下 |
| FID-L15 | `changeUnits(value, denominator = 1)`：正则 `^([-]*[0-9.]*)([a-z%]*)$`；`%`→`n*(d/100)`、`px`→`n*1`、`rem`→`n*htmlFontSize`、`vw`→`n/100*innerWidth`，其它交给 `handleCssUnit`/`unitFunc`，再没有就返回 `n` | 324-338 | compat `parseCssLength`；核心 `LuckyPercent.resolve(base) = value * (base / 100)` | 逐位（compat）| 匹配失败时 `Number(value)` 得 NaN（例如 `'10 px'`）；compat 返回 null + warning（DEV-16） |
| FID-L16 | `getLength(length, maxLength)`：number 原样；string 走 changeUnits；其它 0 | 346-350 | `LuckyLength?.resolve(base) ?? 0` | 逐位 | |
| FID-L17 | `getOffsetX(width, maxWidth = 0) = (maxWidth - width) / 2` | 357-359 | 内联在各 layout | 逐位 | |
| FID-L18 | `getOffscreenCanvas(w, h)` | 361-382 | — | N/A（ADR-11） | |
| FID-L19 | `$set`/`$computed`/`$watch` | 390-433 | `didUpdateWidget` + 不可变配置 | N/A | |
| FID-L20 | `config.beforeCreate` | wheel.ts:74 | — | N/A | Flutter 无"构造后、初始化前"的外部可见时机 |
| FID-L21 | `config.beforeInit`/`afterInit`/`beforeDraw(ctx)`/`afterDraw(ctx)`/`afterStart`/`beforeResize`/`afterResize` | 各子类 | `LuckyHooks` 同名字段 | 等价 | `afterInit` 时机见 IMP-04、U-22；`beforeDraw`/`afterDraw` 收到 `(Canvas, Size)` |

`computeImageBox`（FID-L14，逐位）：

```dart
// width/height 为 LuckyLength?；natural = 图片自然尺寸（逻辑像素）
if (width == null && height == null) return Size(natural.width, natural.height);
if (width != null && height == null) {
  final w = width.resolve(maxWidth);
  return Size(w, natural.height * (w / natural.width));
}
if (width == null && height != null) {
  final h = height.resolve(maxHeight);
  return Size(natural.width * (h / natural.height), h);
}
return Size(width!.resolve(maxWidth), height!.resolve(maxHeight));
```

### 3.2 `utils/math.ts`

| 编号 | 上游 | 行号 | luckdraw | 等级 | 说明 |
| --- | --- | --- | --- | --- | --- |
| FID-U01 | `getAngle(deg) = Math.PI / 180 * deg` | 6-8 | `luckyDegToRad(double deg) => math.pi / 180 * deg` | 逐位 | 顺序：先 `π/180` 再乘 deg |
| FID-U02 | `getArcPointerByDeg(deg, r) = [+(cos(deg)*r).toFixed(8), +(sin(deg)*r).toFixed(8)]` | 16-18 | `buildFanPath` 内部 | 等价 | `toFixed(8)` 舍入到 1e-8，对像素无影响；luckdraw 不做舍入（DEV-02 范畴） |
| FID-U03 | `getTangentByPointer` | 26-30 | — | N/A | 上游未使用 |
| FID-U04 | `fanShapedByArc(ctx, minR, maxR, start, end, gutter)` | 33-61 | `Path buildFanPath({required double outerRadius, required double start, required double end, required double gutter})` | 等价 | 见下；`minRadius` 上游只用于算 `minGutter`（未使用），扇形内侧是一个顶点而不是内弧 |
| FID-U05 | `roundRectByArc(ctx, x, y, w, h, r)` | 64-82 | `Path buildRoundRectPath(Rect rect, double radius)` → `Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)))` | 等价 | `r > min(w,h)/2` 时钳到 `min/2`；luckdraw 另外把负 `r` 当 0、`w<=0\|\|h<=0` 返回空 Path（IMP-10） |
| FID-U06 | `getLinearGradient(ctx, x, y, w, h, background)` | 87-127 | 几何：`LuckyLegacyLinearFill.endpoints(Rect)`（core）；字符串解析：`parseCssFill`（compat） | 逐位（几何）/ IMP（色标） | 见 §3.5 |

`buildFanPath`（FID-U04）：

```dart
// start/end 为弧度；gutter 为像素
final maxGutter = luckyDegToRad(90 / math.pi / outerRadius * gutter); // 与上游同序：90/π/R*g 再转弧度 = g/(2R)
final maxStart = start + maxGutter;
final maxEnd = end - maxGutter;
final path = Path();
if (!(outerRadius > 0)) return path;                      // IMP-10（上游负半径 arc 抛 IndexSizeError）
path.addArc(Rect.fromCircle(center: Offset.zero, radius: outerRadius), maxStart, canvasArcSweep(maxStart, maxEnd));
final apexR = gutter / 2 / (math.sin((start - end) / 2)).abs();
final mid = (start + end) / 2;
path.lineTo(math.cos(mid) * apexR, math.sin(mid) * apexR);
path.close();
```

`canvasArcSweep(start, end)`（Canvas 规范，`anticlockwise == false`）：`d = end - start`；若 `d >= 2π` 返回 `2π`；否则 `d = d.remainder(2π)`，`d < 0` 时 `d += 2π`。当 gutter 大于扇区弧长时 `maxEnd < maxStart`，Canvas 会画出近乎整圆的弧，luckdraw 照此语义（等价）。`gutter == 0` 时 `apexR == 0`（`0 / x`）；单个奖品（sweep=2π）且 `gutter > 0` 时 `sin(π)≈1.2e-16`，`apexR` 极大——上游同样如此，照搬。

### 3.3 `utils/tween.ts`（FID-U08a–g，全部逐位）

| 编号 | 缓动 | 行号 | easeIn（Dart，`if (t >= d) t = d;` 在前） | easeOut |
| --- | --- | --- | --- | --- |
| FID-U08a | quad | 17-26 | `final x = t / d; return c * x * x + b;` | `final x = t / d; return -c * x * (x - 2) + b;` |
| FID-U08b | cubic | 29-38 | `final x = t / d; return c * x * x * x + b;` | `final y = t / d - 1; return c * (y * y * y + 1) + b;` |
| FID-U08c | quart | 41-50 | `final x = t / d; return c * x * x * x * x + b;` | `final y = t / d - 1; return -c * (y * y * y * y - 1) + b;` |
| FID-U08d | quint | 53-62 | `final x = t / d; return c * x * x * x * x * x + b;` | `final y = t / d - 1; return c * (y * y * y * y * y + 1) + b;` |
| FID-U08e | sine | 65-74 | `return -c * math.cos(t / d * (math.pi / 2)) + c + b;` | `return c * math.sin(t / d * (math.pi / 2)) + b;` |
| FID-U08f | expo | 77-86 | `return (t == 0) ? b : c * math.pow(2, 10 * (t / d - 1)) + b;` | `return (t == d) ? b + c : c * (-math.pow(2, -10 * t / d) + 1) + b;` |
| FID-U08g | circ | 89-98 | `final x = t / d; return -c * (math.sqrt(1 - x * x) - 1) + b;` | `final y = t / d - 1; return c * math.sqrt(1 - y * y) + b;` |

注意：JS `c * (t /= d) * t` 是 `(c * x) * x`；Dart `c * x * x` 左结合，相同。`-c * …` 中一元负号先结合，`(-c) * x * (x - 2)` 与 JS 相同。expo easeOut 的 `-10 * t / d` 是 `((-10) * t) / d`。上游 `d == 0` 时 `t/d` 为 NaN；luckdraw 的 const `LuckyMotionOptions` 不比较 Duration，debug 正时长断言放在玩法 `motion.configure`；运行期 accelerationMs/decelerationMs 至少为 1ms，含不足 1ms 的正时长（IMP-08）。

`const CurveEasing(Curve curve, {Curve? outCurve})`（新增）：令 `x = (t / d).clamp(0.0, 1.0)`，`easeIn = b + c * curve.transform(x)`；`easeOut = b + c * (outCurve == null ? 1 - curve.transform(1 - x) : outCurve.transform(x))`。使用 Flutter 翻转曲线等价公式直接求值，保留 const 且不分配 FlippedCurve 包装（R2-05 / ADR-28）。

### 3.4 `utils/index.ts`

| 编号 | 上游 | 行号 | luckdraw | 等级 | 说明 |
| --- | --- | --- | --- | --- | --- |
| FID-U09 | `isExpectType`、`get`、`has` | 7-23 | — | N/A | 类型系统替代；`has(font, 'wordWrap')` 的"显式 false 也算设置"语义 → `bool? wordWrap`（null=未设置） |
| FID-U10 | `removeEnter(str)`：删掉所有 `\n` | 30-32 | `removeLineBreaks(String)`：`text.replaceAll('\n', '')` | 逐位 | 只删 `\n`，不删 `\r` |
| FID-U11 | `getNumber(num)` | 38-49 | — | N/A | 只被 `hasBackground` 用（见 U-02） |
| FID-U12 | `hasBackground(color)`：非字符串 false；`'transparent'` false；`rgba(...)` 想判断 alpha 为 0，但 `getNumber` 收到的是正则结果数组 → NaN → **永远 true** | 55-64 | `background != null` | 等价 | 类型化 API：null = 无背景。compat：`'transparent'`（不区分大小写、trim）→ null；`rgba(…,0)` → `Color(0x00000000)`（**有背景**，与上游一致，U-02） |
| FID-U13 | `computePadding(block, getLength)`：`padding.split(' ')` 1–4 值；**4 值顺序 top, bottom, left, right**（非 CSS）；`paddingTop/Bottom/Left/Right` 单独字段算进 `res` 后**没有返回**（U-01） | 70-107 | compat `parseCssPadding(Object? value, LuckyCanvasCompatOptions options, void Function(String) warn)` → `LuckyEdgeInsets`；核心 `LuckyEdgeInsets.css(List<double>)` 用 CSS 顺序 | 逐位（compat）/DEV（核心） | value 可为字符串或含 padding 的 Map；Map 中单边键忽略并逐项 warning。四值映射上、下、左、右；连续字面空格保留空 token，按 0 处理；null 为零边距，其它非字符串警告并按零处理 |
| FID-U14 | `throttle(fn, 300)` | 115-125 | — | N/A | |
| FID-U15 | `computeRange(rangeArr)` | 132-147 | `WeightedPrizePicker.pick` | 逐位 | 见下 |
| FID-U16 | `splitText(ctx, text, getWidth, lineClamp = Infinity)` | 155-188 | `splitLuckyText(String text, LuckyTextWidth measure, double Function(int finishedLines) maxWidthOf, {int? lineClamp})` | 逐位（BMP）/IMP-06（代理对） | 见下 |
| FID-U17 | `getSortedArrayByIndex(arr, order)` | 191-201 | `SlotLayout` 内 `reelCells` 构建 | 逐位 | 见 §7 |

`WeightedPrizePicker.pick`（FID-U15，逐位）：

```dart
// weights[i]：类型化为 double?；null/NaN/<=0 都视为不可选（上游 Number(undefined)=NaN、<=0 都 push NaN）
final ascending = List<double>.filled(n, double.nan);
var sum = 0.0;
for (var i = 0; i < n; i++) {
  final w = (disabled[i] && honorDisabled) ? double.nan : (weights[i] ?? double.nan);
  if (w > 0) { sum = sum + w; ascending[i] = sum; }   // NaN > 0 为 false，与 JS 一致
}
final r = random.nextDouble() * sum;                    // 即使 sum==0 也调用一次 random（与上游调用次数一致）
for (var i = 0; i < n; i++) { if (r <= ascending[i]) return i; } // NaN 比较恒 false
return null;                                            // 上游返回 -1 → 本局作废
```

`honorDisabled` 是 `WeightedPrizePicker` 的构造参数，类型化 API 默认 true（IMP-13），compat 产出的配置不设 `disabled`（`honorDisabled` 对其无影响，见 FID-G11）。

`splitLuckyText`（FID-U16）：

```dart
List<String> splitLuckyText(String text, LuckyTextWidth measure, double Function(int finishedLines) maxWidthOf, {int? lineClamp}) {
  final clamp = (lineClamp == null || lineClamp <= 0) ? -1 : lineClamp; // -1 表示无限（上游 Infinity）
  var str = '';
  final lines = <String>[];
  final endWidth = measure('...');
  String? lastChar;
  for (final rune in text.runes) {                 // IMP-06：上游 for i < text.length 逐 UTF-16 码元
    final ch = String.fromCharCode(rune);
    str += ch;
    var currWidth = measure(str);
    final maxWidth = maxWidthOf(lines.length);
    if (clamp == lines.length + 1) currWidth += endWidth;
    if (maxWidth < 0) return lines;
    if (currWidth > maxWidth) {
      lines.add(str.substring(0, str.length - ch.length)); // 上游 str.slice(0, -1)
      str = ch;
    }
    if (clamp == lines.length) {
      lines[lines.length - 1] += '...';
      return lines;
    }
  }
  if (str.isNotEmpty) lines.add(str);
  if (lines.isEmpty) lines.add(text);
  return lines;
}
```

注意点：(1) `maxWidthOf` 每个字符都调用一次，参数是"已完成的行数"（转盘的每行宽度依赖行号，wheel.ts:375-383）；(2) 第一字符就超宽时会 push 一个空串行（上游同样）；(3) `lineClamp == 1` 时第一次换行即返回；(4) 文本为空时返回 `['']`。

### 3.5 线性渐变（FID-U06 细节）

上游解析：`/linear-gradient\((.+)\)/` 取括号内 → `split(',')` → trim → 第一个元素是方向，其余是色标。

方向端点（逐位，`x,y,w,h` 为目标矩形；`tan(deg) = Math.tan(deg / 180 * Math.PI)`）：

| 条件 | 端点 `[x0, y0, x1, y1]` |
| --- | --- |
| 含 `deg`，`deg = parseFloat(去掉末尾 3 字符) % 360`（JS 取余） | |
| `0 ≤ deg < 45` | `[x, y+h, x+w, y+h - w·tan(deg-0)]` |
| `45 ≤ deg < 90` | `[x, y+h, (x+w) - h·tan(deg-45), y]` |
| `90 ≤ deg < 135` | `[x+w, y+h, (x+w) - h·tan(deg-90), y]` |
| `135 ≤ deg < 180` | `[x+w, y+h, x, y + w·tan(deg-135)]` |
| `180 ≤ deg < 225` | `[x+w, y, x, y + w·tan(deg-180)]` |
| `225 ≤ deg < 270` | `[x+w, y, x + h·tan(deg-225), y+h]` |
| `270 ≤ deg < 315` | `[x, y, x + h·tan(deg-270), y+h]` |
| `315 ≤ deg < 360` | `[x, y, x+w, y+h - w·tan(deg-315)]` |
| 负角度（不落入任何区间） | `[0,0,0,0]`（退化渐变，Canvas 规范下什么也不画，U-24）→ luckdraw 先 `+360` 归一化（IMP-20） |
| 含 `top` | `[x, y+h, x, y]` |
| 否则含 `bottom` | `[x, y, x, y+h]` |
| 否则含 `left` | `[x+w, y, x, y]` |
| 否则含 `right` | `[x, y, x+w, y]` |
| 都不含 | `[0,0,0,0]`（同上） |

四个端点各自 `>> 0`（向零截断）后传给 `createLinearGradient`。luckdraw 的端点同样 `.toInt().toDouble()`；重合时不绘制（透明且无 shader），包括无方向和亚像素截断的退化情形，不能画成最后色标纯色；其余用 `ui.Gradient.linear(Offset(x0,y0), Offset(x1,y1), colors, stops)`（R1-01）。

色标（上游 `addColorStop`）：单 token → `addColorStop(index, color)`（**用下标当偏移**，3 个以上无位置色标时偏移 2 越界抛 `IndexSizeError`，整帧绘制中断、rAF 链断开，U-10）；双 token → `addColorStop(token0, token1)`，即"位置在前、颜色在后"（`'0.5 red'` 可用，CSS 标准 `'red 50%'` 会抛错）。另外 `split(',')` 会把 `rgb(…)` 里的逗号拆开。

luckdraw 的处理（IMP-09，compat `parseCssFill`）：括号感知地按逗号切分；色标同时接受 `pos color`（上游写法，pos 是 0–1 小数）与 `color pos%`/`color pos`（CSS 写法）；无位置色标 ≤2 个时偏移为 0、1（与上游一致），>2 个时按 CSS 均分（上游此时抛错）。核心 `LuckyLegacyLinearFill(direction, stops)` 只负责端点几何。

### 3.6 `utils/image.ts`

| 编号 | 上游 | 行号 | luckdraw | 等级 | 说明 |
| --- | --- | --- | --- | --- | --- |
| FID-U18 | `cutRound(img, radius)`：离屏 canvas `roundRectByArc` + `clip` + `drawImage` | 24-34 | `LuckyImage.borderRadius`（录制 Picture 时 `canvas.clipRRect`） | 等价（形态变化） | 上游是导出的工具函数，供 `formatter` 使用；luckdraw 改成字段，零额外纹理 |
| FID-U19 | `opacity(img, opacity)`：`ctx.filter = opacity(...)` 或逐像素乘 alpha | 42-67 | `LuckyImage.opacity`（`Paint.color = Color.fromRGBO(0,0,0,opacity)` 绘制） | 等价 | 不产生新纹理、不用 saveLayer |
| FID-U20 | `getMatrix`/`blur`（循环体为空、`console.log`，未完成） | 75-129 | — | N/A | 上游未完成，U-19 |
| FID-U21 | `getImage`、`getBase64Image`（空） | 9-16、131-133 | — | N/A | |

---

## 4. 配置项与默认值

约定：表中"类型化字段"是 luckdraw 的 Dart 字段；"compat 解析"写 `compat` 如何从上游 JSON 得到它。未列出的上游键 compat 一律忽略并产生 warning。

### 4.1 转盘（`types/wheel.ts`、wheel.ts:123-152）

| 上游键 | 上游类型 | 上游默认 | 类型化字段 | 类型化默认 | compat 解析 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| `width`/`height` | string\|number | 必填 | `LuckyWheel.width/height` | null（取约束） | `parseCssLength(...)` 后取 px；百分比→null+warning | U-26 |
| `blocks[]` | | `[]` | `WheelConfig.blocks: List<WheelBlock>` | `const []` | | |
| `blocks[].padding` | string | undefined | `WheelBlock.padding: double` | `0` | `getLength(padding.split(' ')[0])`（**只取第一个 token**，百分比按分母 1） | U-15 |
| `blocks[].background` | string | undefined | `WheelBlock.background: LuckyFill?` | null | `parseCssFill`（上游转盘不解析渐变，见 IMP-09） | |
| `blocks[].imgs[]` | | | `WheelBlock.images: List<WheelBlockImage>` | `const []` | | |
| `blocks[].imgs[].rotate` | boolean | undefined | `WheelBlockImage.rotate: bool` | `false` | `== true` | |
| `prizes[]` | | `[]` | `WheelConfig.prizes: List<WheelPrize>` | `const []` | | |
| `prizes[].range` | number | undefined | `WheelPrize.weight: double?` | null | 数字原样；非数字→null | 选奖权重 |
| （无） | | | `WheelPrize.sectorWeight: double` | `1` | 不设 | IMP-17，#151 |
| （无） | | | `WheelPrize.disabled: bool` | `false` | 不设 | IMP-13 |
| （无） | | | `WheelPrize.painter: WheelPrizePainter?` | null | 不设 | 自定义绘制 |
| `prizes[].background` | string | undefined | `WheelPrize.background: LuckyFill?` | null（→ 取 `style.background`） | `parseCssFill` | |
| `prizes[].fonts[]` | | | `WheelPrize.texts: List<LuckyText>` | `const []` | 见 §4.5 | |
| `prizes[].imgs[]` | | | `WheelPrize.images: List<LuckyImage>` | `const []` | 见 §4.6 | |
| `buttons[]` | | `[]` | `WheelConfig.buttons: List<WheelButton>` | `const []` | | |
| `buttons[].radius` | string | undefined（→0） | `WheelButton.radius: LuckyLength` | `LuckyLength.zero` | `parseCssLength` | 基准 prizeRadius |
| `buttons[].pointer` | boolean | undefined | `WheelButton.pointer: bool` | `false` | `== true` | |
| `buttons[].background` | string | undefined | `WheelButton.background: LuckyFill?` | null | `parseCssFill` | 按钮**不**取 defaultStyle.background（wheel.ts:401） |
| `buttons[].fonts[]` | FontItemType | | `WheelButton.texts: List<LuckyText>` | `const []` | 只读 text/top/left/fontColor/fontSize/fontStyle/fontWeight/lineHeight | 按钮文字不换行 |
| `buttons[].imgs[]` | | | `WheelButton.images: List<LuckyImage>` | `const []` | | |
| `defaultConfig.gutter` | string\|number | `'0px'` | `WheelOptions.gutter: double` | `0` | `getLength` 无基准 | |
| `defaultConfig.offsetDegree` | number | `0` | `WheelOptions.offsetDegree: double` | `0` | 原样 | |
| `defaultConfig.speed` | number | `20` | `LuckyMotionOptions.speed: double` | `20` | 原样 | 度/参考帧 |
| `defaultConfig.speedFunction` | string | `'quad'` | `LuckyMotionOptions.accelerationEasing/decelerationEasing` | `LuckyEasings.quad` | 默认**忽略**（上游 `run()` 不读，U-09）；`honorSpeedFunction: true` 时按 `kLuckyCanvasEasingNames` 映射 | IMP-14 |
| `defaultConfig.accelerationTime` | number(ms) | `2500` | `LuckyMotionOptions.accelerationTime: Duration` | `2500ms` | `Duration(microseconds: (ms * 1000).round())` | |
| `defaultConfig.decelerationTime` | number(ms) | `2500` | `LuckyMotionOptions.decelerationTime: Duration` | `2500ms` | 同上 | |
| `defaultConfig.stopRange` | number | `0` | `WheelOptions.stopRange: double` | `0` | `getLength(stopRange)` 无基准（上游写法，wheel.ts:450） | 0–1 |
| `defaultStyle.background` | string | `'rgba(0,0,0,0)'` | `WheelStyle.background: LuckyFill?` | `LuckyFill.color(Color(0x00000000))` | `parseCssFill` | 非 null，"有背景"（U-02） |
| `defaultStyle.fontColor` | string | `'#000'` | `LuckyTextDefaults.color: Color` | `Color(0xFF000000)` | `parseCssColor` | |
| `defaultStyle.fontSize` | string | `'18px'` | `LuckyTextDefaults.fontSize: double` | `18` | `getLength` 无基准 | |
| `defaultStyle.fontStyle` | string | `'sans-serif'` | `LuckyTextDefaults.fontFamily: String?` + `fontFamilyFallback` | null（平台默认无衬线） | 按逗号拆：首个为 family，其余进 fallback；`sans-serif` → null；`serif`/`monospace` 原样 | DEV-01 |
| `defaultStyle.fontWeight` | string | `'400'` | `LuckyTextDefaults.fontWeight: FontWeight` | `FontWeight.w400` | `parseCssFontWeight` | |
| `defaultStyle.lineHeight` | string | undefined | `LuckyTextDefaults.lineHeight: double?` | null | `getLength` 无基准 | |
| `defaultStyle.wordWrap` | boolean | `true` | `LuckyTextDefaults.wordWrap: bool` | `true` | 原样 | |
| `defaultStyle.lengthLimit` | string\|number | `'90%'` | `LuckyTextDefaults.lengthLimit: LuckyLength` | `LuckyLength.percent(90)` | `parseCssLength` | |
| `defaultStyle.lineClamp` | number | undefined | `LuckyTextDefaults.lineClamp: int?` | null | `0`/非正→null | |
| `start` / `end` | function | | `LuckyWheel.onStart` / `onEnd` | null | JSON 中出现则 warning | |
| （无） | | | `LuckyMotionOptions.timebase` | `LuckyTimebase.time` | `strictUpstream()` 时 `frame` | IMP-03 |
| （无） | | | `LuckyMotionOptions.stopSolver` | `MonotonicStopSolver()` | `strictUpstream()` 时 `UpstreamStopSolver()` | IMP-01 |
| （无） | | | `LuckyMotionOptions.maxFrameDelta` | `100ms` | | IMP-02 |
| （无） | | | `LuckyMotionOptions.idleSpinSpeed` | `2` | | #370 |

### 4.2 九宫格（`types/grid.ts`、grid.ts:142-179）

| 上游键 | 上游默认 | 类型化字段 | 类型化默认 | compat 解析 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `rows` / `cols` | `Number(x) \|\| 3` | `GridConfig.rows/cols: int` | `3` | 同上游（0/NaN→3） | |
| `blocks[]` | `[]` | `GridConfig.blocks: List<LuckyBoxBlock>` | `const []` | | |
| `blocks[].borderRadius` | undefined→0 | `LuckyBoxBlock.borderRadius: double` | `0` | `getLength` 无基准 | |
| `blocks[].background` | undefined | `LuckyBoxBlock.background: LuckyFill?` | null | `parseCssFill`（支持 linear-gradient，grid.ts:494-507） | 九宫格 block **不**取 defaultStyle 背景 |
| `blocks[].padding` | undefined→`[0]` | `LuckyBoxBlock.padding: LuckyEdgeInsets` | `LuckyEdgeInsets.zero` | `parseCssPadding`（上游 4 值顺序） | U-14 |
| `blocks[].paddingTop/Right/Bottom/Left` | 无效（U-01） | — | — | 忽略 + warning | |
| `blocks[].imgs[]` | | `LuckyBoxBlock.images: List<LuckyImage>` | `const []` | | |
| （无） | | `LuckyBoxBlock.border: LuckyBorder?` | null | 不设 | IMP-17 |
| `prizes[]` | `[]` | `GridConfig.prizes: List<GridPrize>` | `const []` | | |
| `prizes[].x/y` | 必填 | `GridCell.x/y: int` | 必填 | `Number()` | |
| `prizes[].col/row` | `\|\| 1` | `GridCell.col/row: int` | `1` | `\|\| 1` | |
| `prizes[].background/shadow/borderRadius` | undefined | `GridCell.style: LuckyCellStyle?` 的同名字段 | null | `parseCssFill`/`parseCssShadow`/`getLength`；**`borderRadius: 0` → null**（上游 `cell.borderRadius ? … : default`，U-11） | |
| `prizes[].fonts[]` | | `GridCell.texts: List<LuckyText>` | `const []` | §4.5 | |
| `prizes[].imgs[]`（含 `activeSrc`） | | `GridCell.images: List<GridImage>` | `const []` | `activeSrc` → `GridImage.activeImage` | |
| `prizes[].range` | | `GridPrize.weight: double?` | null | | |
| `prizes[].disabled` | 声明了但未使用（U-18） | `GridPrize.disabled: bool` | `false` | 默认**不**映射；`honorDisabled: true` 时映射 | IMP-13 |
| `buttons[]` + 旧字段 `button` | `[]` | `GridConfig.buttons: List<GridButton>` | `const []` | `button` 存在时追加到末尾（grid.ts:338-342） | |
| `buttons[].callback` | | `LuckyGrid.onButtonTap(int index, LuckyPhase phase)` | null | 忽略 + warning | |
| `defaultConfig.gutter` | `5` | `GridOptions.gutter: double` | `5` | `getLength` 无基准 | |
| `defaultConfig.speed` | `20`（内部 `/40`） | `LuckyMotionOptions.speed` | `20` | 原样；`GridMotion` 内部 `/40` | |
| `defaultConfig.accelerationTime/decelerationTime` | `2500` | 同转盘 | `2500ms` | | |
| `defaultStyle.borderRadius` | `20` | `GridStyle.cell.borderRadius` | `20` | | |
| `defaultStyle.background` | `'rgba(0,0,0,0)'` | `GridStyle.cell.background` | `LuckyFill.color(Color(0x00000000))` | | |
| `defaultStyle.shadow` | `''` | `GridStyle.cell.shadow` | null | `parseCssShadow` | |
| `defaultStyle.font*`/`lineHeight`/`wordWrap`/`lengthLimit`/`lineClamp` | 同转盘 | `GridStyle.text: LuckyTextDefaults` | 同转盘 | 同转盘 | |
| `activeStyle.background` | `'#ffce98'` | `GridConfig.activeStyle.background` | `LuckyFill.color(Color(0xFFFFCE98))` | | |
| `activeStyle.shadow` | `''` | `GridConfig.activeStyle.shadow` | null | | |
| `activeStyle.fontColor/fontSize/fontStyle/fontWeight/lineHeight` | undefined | `GridConfig.activeStyle.text: LuckyTextOverride?` | null | | |
| （无） | | `activeStyle.borderRadius/border/foreground` | null | | IMP-17（#304/#347） |

### 4.3 老虎机（`types/slot.ts`、slot.ts:133-164）

| 上游键 | 上游默认 | 类型化字段 | 类型化默认 | compat 解析 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `blocks[]` | `[]` | `SlotConfig.blocks: List<LuckyBoxBlock>` | `const []` | 同九宫格 | 老虎机 block 背景缺省时**取 defaultStyle.background**（slot.ts:392） |
| `prizes[]` | `[]` | `SlotConfig.prizes: List<SlotPrize>` | `const []` | | |
| `prizes[].borderRadius` | undefined | `SlotPrize.borderRadius: double?` | null | **`has(cell,'borderRadius')` 语义：0 也算设置**（slot.ts:316） | 与九宫格不同 |
| `prizes[].background` | undefined | `SlotPrize.background: LuckyFill?` | null | `parseCssFill` | |
| `prizes[].fonts[]`/`imgs[]` | | `SlotPrize.texts/images` | `const []` | | |
| （无） | | `SlotPrize.weight: double?`、`disabled`、`painter` | null/false/null | | IMP-15 |
| `slots[]` | `[]` | `SlotConfig.reels: List<SlotReel>` | `const []` | | 改名：reel 更贴切 |
| `slots[].order` | prizes 下标顺序 | `SlotReel.order: List<int>?` | null | 原样 | |
| `slots[].speed` | `\|\| defaultConfig.speed` | `SlotReel.speed: double?` | null | `0` → null | |
| `slots[].direction` | `\|\| defaultConfig.direction` | `SlotReel.direction: int?` | null | `0` → null | |
| （无） | | `SlotReel.stopDelay: Duration` | `Duration.zero` | 不设 | 错峰停轮（拉霸机，§9）；0 时与上游逐位一致 |
| `defaultConfig.mode` | `'vertical'` | `SlotOptions.mode: SlotMode` | `SlotMode.vertical` | `'horizontal'`→horizontal，其它 vertical | |
| `defaultConfig.direction` | `1` | `SlotOptions.direction: int` | `1` | | |
| `defaultConfig.rowSpacing` | `0` | `SlotOptions.rowSpacing: double` | `0` | `getLength` 无基准 | |
| `defaultConfig.colSpacing` | `5` | `SlotOptions.colSpacing: double` | `5` | 同上 | |
| `defaultConfig.speed` | `20` | `LuckyMotionOptions.speed` | `20` | | 像素/参考帧 |
| `defaultConfig.accelerationTime/decelerationTime` | `2500` | 同转盘 | | | |
| （无） | | `SlotOptions.cellAspectRatio: double?` | null（正方形） | | IMP-17（#265） |
| `defaultStyle.borderRadius` | `0` | `SlotStyle.cell.borderRadius` | `0` | | |
| `defaultStyle.background` | `'rgba(0,0,0,0)'` | `SlotStyle.cell.background` | `LuckyFill.color(Color(0x00000000))` | | |
| `defaultStyle.font*`… | 同转盘 | `SlotStyle.text` | 同转盘 | | |
| `end` | | `LuckySlotMachine.onEnd(SlotResult)` | | | |
| （无） | | `SlotConfig.winPredicate: SlotWinPredicate` | `upstreamSlotWinPredicate` | | #182 |

### 4.4 `LuckyLength` 字段的解析基准（上游 `getLength(x, base)` 的第二参数）

| 字段 | 转盘 block 图 | 转盘奖品 | 转盘按钮 | 九宫格 block 图 | 九宫格格子 | 老虎机 block 图 | 老虎机格子 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 图片 `width` | `2r`（该 block 半径） | `prizeAng × prizeRadius`（弧长） | `2r`（按钮半径） | block 当前 `w` | 格子 `width`（阴影收缩后） | block `w` | `cellWidth` |
| 图片 `height` | `2r` | `prizeHeight = prizeRadius − maxBtnRadius` | `2r` | block `h` | 格子 `height` | block `h` | `cellHeight` |
| 图片 `left` | `2r` | `shortSide = prizeRadius·sin(prizeAng/2)·2` | `r`（**不是 2r**） | `w` | `width` | `w` | `cellWidth` |
| 图片 `top` | `2r`（结果再 `− r`） | `prizeHeight` | `r` | `h` | `height` | `h` | `cellHeight` |
| 文字 `left` | — | `shortSide` | **`shortSide`（奖品弦长，U-17）** | — | `width` | — | `cellWidth` |
| 文字 `top` | — | `prizeHeight` | `r` | — | `height` | — | `cellHeight` |
| 文字 `lengthLimit` | — | 每行动态 `maxWidth`（§5.3） | 不换行 | — | `width` | — | `cellWidth` |
| 按钮 `radius` | — | — | `prizeRadius` | — | — | — | — |

扇区不等分时，转盘奖品的 `prizeAng` 换成该扇区自己的弧度 `sweep_k`（`shortSide`、弧长、每行宽度公式里的 `prizeAng/2` 同理），等分时与上游逐位相同。

### 4.5 文字项（`FontItemType` + `FontExtendType`）

| 上游键 | 类型化字段 `LuckyText` | 解析/回退规则（`font.x \|\| defaultStyle.x`） |
| --- | --- | --- |
| `text` | `text: String` | `String(font.text)`；compat 把非字符串 `toString()` |
| `top`/`left` | `top/left: LuckyLength?` | null → 0 |
| `fontColor` | `color: Color?` | `?? defaults.color` |
| `fontSize` | `fontSize: double?` | `?? defaults.fontSize`；绘制/测量用 `truncate()` |
| `fontStyle` | `fontFamily: String?`、`fontFamilyFallback: List<String>?` | `?? defaults.fontFamily` |
| `fontWeight` | `fontWeight: FontWeight?` | `?? defaults.fontWeight` |
| `lineHeight` | `lineHeight: double?` | `text.lineHeight ?? defaults.lineHeight ?? text.fontSize ?? defaults.fontSize`（**未截断**的字号） |
| `wordWrap` | `wordWrap: bool?` | `?? defaults.wordWrap`（上游 `has()`：显式 false 生效） |
| `lengthLimit` | `lengthLimit: LuckyLength?` | `?? defaults.lengthLimit` |
| `lineClamp` | `lineClamp: int?` | `?? defaults.lineClamp`；≤0 视为无限 |

九宫格激活态覆盖（grid.ts:443-462）：`fontFamily/fontWeight/fontSize/color` 在 `isActive && activeStyle.text?.x != null` 时用激活值；**行高**在激活态为 `activeStyle.text?.lineHeight ?? (text.lineHeight ?? defaults.lineHeight ?? text.fontSize ?? defaults.fontSize)`——即激活字号**不**参与行高回退（照搬）。

测量/绘制将 Canvas 空白 `\t \n \f \r \v U+2028 U+2029 U+0085` 按 U+0020 处理；splitLuckyText 保留显式换行与逐码点拆分。alphabetic 基线从实际绘制 painter 读取，不能用空格基线替代含回退字体的实际行（R1-02/03）。

### 4.6 图片项（`ImgItemType`）

F1 的资源契约：naturalSize 取 formatter 输出尺寸；取消仅使请求失效，异步 formatter 完成前不能释放源图，完成后再释放源图和失效产物。DefaultAssetBundle 身份变化重新解析请求（R3-02…04），详见 ARCHITECTURE §8.4。

| 上游键 | 类型化字段 `LuckyImage` | 说明 |
| --- | --- | --- |
| `src` | `image: ImageProvider` | compat：`http(s)://` → `NetworkImage`；`data:` → `MemoryImage`（base64 解码）；其它 → `AssetImage`（可用 `assetResolver` 选项覆盖） |
| `top`/`left`/`width`/`height` | `LuckyLength?` | 基准见 §4.4 |
| `formatter` | `formatter: LuckyImageFormatter?` | `FutureOr<ui.Image> Function(ui.Image source)`；compat 忽略 + warning（DEV-05） |
| `activeSrc`（九宫格奖品） | `GridImage.activeImage: ImageProvider?` | |
| `rotate`（转盘 block 图） | `WheelBlockImage.rotate: bool` | |
| （无） | `borderRadius: double?`、`opacity: double`（默认 1）、`fallback: ImageProvider?` | FID-U18/U19、IMP-04 |

### 4.7 基类 `ConfigType`（types/index.ts:37-63）

| 上游键 | luckdraw | 等级 |
| --- | --- | --- |
| `flag`/`el`/`divElement`/`canvasElement`/`ctx`/`rAF`/`setTimeout`/`setInterval`/`clearTimeout`/`clearInterval`/`nodeType` | — | N/A |
| `dpr` | `MediaQuery.devicePixelRatioOf` | N/A |
| `handleCssUnit`/`unitFunc` | `LuckyCanvasCompatOptions.handleCssUnit` | 等价（compat） |
| `beforeCreate` | — | N/A（FID-L20） |
| `beforeResize`/`afterResize`/`beforeInit`/`afterInit`/`beforeDraw`/`afterDraw`/`afterStart` | `LuckyHooks` | 等价（FID-L21） |

---

## 5. 转盘 `lib/wheel.ts`

### 5.1 函数映射

| 编号 | 上游 | 行号 | luckdraw | 等级 |
| --- | --- | --- | --- | --- |
| FID-W01 | 字段 `Radius/prizeRadius/prizeDeg/prizeAng/rotateDeg/maxBtnRadius/startTime/endTime/stopDeg/endDeg/FPS/step/prizeFlag` | 32-57 | 几何类进 `WheelLayout`；动画类进 `WheelMotion`（`step`、`prizeFlag`、`rotateDeg`…同名私有字段） | 等价 |
| FID-W02 | `resize()`：`Radius = min(w,h)/2`，`translate(Radius, Radius)` | 79-85 | `WheelLayout.radius = math.min(size.width, size.height) / 2`；`center` 由 `alignment` 决定，默认 `topLeft` → `(radius, radius)` | 逐位（默认） |
| FID-W03 | `initLucky()` 重置字段，`prizeFlag = -1`，`step = 0` | 87-102 | `WheelMotion.reset()` | 逐位 |
| FID-W04 | `initComputed()` 默认值 | 123-152 | §4.1 | 逐位 |
| FID-W05 | `initWatch()` | 157-184 | `didUpdateWidget`（ARCHITECTURE §11.4） | IMP-07 |
| FID-W06 | `init()`：beforeInit → draw ×2 → 加载图片 → afterInit | 189-200 | 宿主 initState：`hooks.beforeInit` →（布局）→ 首帧 → 图片全部有结论后 `hooks.afterInit` + `onReady` | 等价（时机见 U-22、U-23） |
| FID-W07 | `initImageCache()`/`loadAndCacheImg()` | 202-269 | `LuckyImageResolver` | IMP-04 |
| FID-W08 | `handleClick(e)`：以 `maxBtnRadius` 画圆 `isPointInPath`；`step !== 0` 时不触发 `start` | 230-237 | `WheelGame.hitTestAll`：在包含点击点的同心按钮中取最小半径者，不依赖配置半径排序；`onStart` 只在 idle/settled/idleSpinning 触发，`onButtonTap` 总是触发 | 等价 + IMP-12 |
| FID-W09 | `drawBlock(radius, block)` | 271-290 | `WheelLayout` 的 block 段 + `WheelPainter` 录制 | 逐位几何 |
| FID-W10 | `draw()` | 295-440 | `computeWheelLayout`（几何）+ `WheelPainter`（录制/回放） | 等价，见 §5.2 |
| FID-W11 | `carveOnGunwaleOfAMovingBoat()` | 445-462 | `WheelMotion._carve()` + `LuckyStopSolver` | 逐位（Upstream 求解器）/IMP-01（默认） |
| FID-W12 | `play()` / `stop(index)` | 467-500 | `WheelController.play/stop/stopAt/cancel` → `WheelMotion` | 逐位（含 index 回绕） |
| FID-W13 | `run(num)` | 506-555 | `WheelMotion.tick(tMs, dtMs)` | 逐位（`frame`）/IMP-03（`time`） |
| FID-W14 | `conversionAxis` | 562-565 | — | N/A（未被使用） |

### 5.2 绘制（几何）逐步对照

坐标系：原点在圆心，x 右、y 下，角度 0 指向右、顺时针为正（Canvas 与 Flutter 相同）。指针在 −90°（正上方）。

```text
// wheel.ts:300-305  blocks
radius = R
for block in blocks:
  drawBlock(radius, block)                  // 背景：整圆 radius（hasBackground 时）；图片：见下
  radius = radius - padding(block)          // padding 只取第一个 token（U-15）
prizeRadius = radius                        // luckdraw：max(0, radius)（IMP-10）

// drawBlock 图片（271-290）
[tw, th] = computeImageBox(img, info, maxW = radius*2, maxH = radius*2)
x = getOffsetX(tw) + getLength(left, radius*2)       // = -tw/2 + left
y = getLength(top, radius*2) - radius
rotate == true 时：先 ctx.rotate(getAngle(rotateDeg)) 再画（绕圆心随盘转）

// 307-309
prizeDeg = 360 / n ;  prizeAng = getAngle(prizeDeg)
shortSide = prizeRadius * sin(prizeAng / 2) * 2
// 311
start = getAngle(rotateDeg - 90 + prizeDeg / 2 + offsetDegree)      // 弧度

// luckdraw：layout 在 rotateDeg = 0 下计算，渲染时整体旋转 rotateDeg（数学等价）
//   等分：middle_k = luckyDegToRad(-90 + prizeDeg / 2 + offsetDegree) + k * prizeAng
//   不等分（IMP-17）：sweepDeg_k = 360 * w_k / Σw；startDeg_k = Σ_{j<k} sweepDeg_j
//                    middle_k = luckyDegToRad(-90 + offsetDegree + startDeg_k + sweepDeg_k / 2)
//   （等分时两种写法的差在 1e-15 弧度量级，只影响录制几何，不影响动画数值）

for k, prize in prizes:                        // 324-394
  mid = start + k * prizeAng
  prizeHeight = prizeRadius - maxBtnRadius     // 328（上游这里用的是"上一次 draw 留下的" maxBtnRadius，U-23）
  bg = prize.background || defaultStyle.background
  if hasBackground(bg): fan(maxR = prizeRadius, start = mid - prizeAng/2, end = mid + prizeAng/2, gutter)
  // 局部坐标：原点移到外缘中点并旋转，使局部 +y 指向圆心
  translate(cos(mid) * prizeRadius, sin(mid) * prizeRadius); rotate(mid + getAngle(90))
  for img: [tw, th] = box(img, maxW = prizeAng * prizeRadius, maxH = prizeHeight)
           x = -tw/2 + getLength(left, shortSide);  y = getLength(top, prizeHeight)
  for font:
    color/weight/size/family 按 §4.5；ctx.font = `${weight} ${size >> 0}px ${family}`
    if wordWrap:
      lines = splitText(removeEnter(text), maxWidthOf(L) = getLength(lengthLimit,
                 (prizeRadius - fontY(font, prizeHeight, L)) * tan(prizeAng / 2) * 2 - getLength(gutter)), lineClamp)
      // 原文：adjacentSide = prizeRadius - getFontY(font, prizeHeight, lines.length)
      //       shortSide' = adjacentSide * Math.tan(prizeAng / 2);  maxWidth = shortSide' * 2 - gutter
    else lines = text.split('\n')
    lines = lines.where(nonEmpty)              // 387：转盘奖品文字**过滤空行**（行号按过滤后重排）
    for i, line: fillText(line, x = -measure(line)/2 + getLength(font.left, shortSide), y = fontY(font, prizeHeight, i))
  // fontY(font, height, i) = getLength(font.top, height) + (i + 1) * getLength(lineHeight)   （317-321，y 为基线）
  rotate/translate 还原

// 按钮 397-437（在 prizes 之后绘制；maxBtnRadius 在这里累积）
for btn:
  r = getLength(btn.radius, prizeRadius);  maxBtnRadius = max(maxBtnRadius, r)
  if hasBackground(btn.background): 整圆 r
  if btn.pointer && hasBackground(btn.background): 三角形 (-r,0) → (r,0) → (0,-2r)，同色填充
  img: box(maxW = 2r, maxH = 2r)；x = -tw/2 + getLength(left, r)；y = getLength(top, r)
  font: 不换行，text.split('\n')（**不过滤空行**）；
        x = -measure(line)/2 + getLength(font.left, shortSide)   // shortSide 是奖品弦长（U-17）
        y = getLength(font.top, r) + (i + 1) * getLength(lineHeight)
```

luckdraw 的 `maxBtnRadius` 在布局开始时先由全部按钮算出（DEV-08），因此首帧就正确，不需要上游的"画两次"（wheel.ts:194-195）。

### 5.3 动画逐帧（`WheelMotion.tick`，FID-W13；`frame` 时间基准下逐位）

```dart
// 状态：step(0..3)、prizeFlag(int?：null=上游 undefined，-1，>=0)、rotateDeg、startTime、endTime、stopDeg、endDeg、fps(=16.6)、num(=0)
// 输入：t = 有效时间(ms)，dt = 有效增量(ms)；k = timebase == frame ? 1.0 : dt / kLuckyReferenceFrameMs
void tick(double t, double dt) {
  if (_pendingStart) { startTime = t; _pendingStart = false; num = 0; }      // 上游 play() 里 Date.now()
  if (step == 0) return;                                                     // 结束回调已在置 0 的那一 tick 发出（DEV-06）
  if (prizeFlag == -1) return;                                               // 上游 515，实际不可达
  if (step == 3 && !_solved) { _carve(t); _solved = true; }                   // 517；独立标记实现 DEV-07，不能以零位移判断未求解
  final startInterval = t - startTime;
  final endInterval = t - endTime;
  var deg = rotateDeg;
  if (step == 1 || startInterval < accTime) {                                // 523
    if (timebase == frame && num > 0) fps = startInterval / num;             // 525（DEV-12：num==0 时上游得 NaN，下一帧被覆盖）
    final currSpeed = accEase.easeIn(startInterval, base, speed - base, accTime); // base：正常 0；从 idleSpin 起步为 idleSpinSpeed
    if (currSpeed == speed) step = 2;                                         // 528
    deg = deg + currSpeed.remainder(360) * k;                                 // 531
  } else if (step == 2) {
    deg = deg + speed.remainder(360) * k;                                     // 534
    if (prizeFlag != null && prizeFlag! >= 0) { step = 3; stopDeg = 0; endDeg = 0; _solved = false; }  // 536-541
  } else if (step == 3) {
    deg = decEase.easeOut(endInterval, stopDeg, endDeg, decTime);             // 544
    if (endInterval >= decTime) step = 0;                                     // 545-547 → 发 onEnd(prizes[prizeFlag])
  } else {
    _cancel();                                                                // 550 stop(-1)
  }
  rotateDeg = deg;
  num++;
}
```

`frame` 模式下 `k == 1.0`，`x * 1.0 == x` 在 IEEE 754 下精确，故与上游逐位相同。

D7 / SM-E09：提前 stop 把 step 置 2，但加速时长未满仍走加速分支；越过时长直接走上述 step=2 分支并置 3，对外 accelerating → decelerating，没有独立 cruising 帧。九宫格同构；老虎机 §7.4 的加速/停止判定不同，上游路径保留 cruising 帧。不得为统一阶段插帧。ISS-120HZ 的 time 口径为最终停点一致、加速段中间相位差 ≤6°；默认参数右端采样在 60/120Hz 加速终点差约 5.0167°，不改变积分公式。

停止求解（`_carve`，wheel.ts:445-462）：

```dart
void _carve(double t) {
  endTime = t;
  stopDeg = rotateDeg;
  final r = random.nextDouble();                                // 上游 Math.random()，即使 stopRange==0 也调用
  final sweep = layout.sectorSweepDeg(prizeFlag!);              // 等分时 == prizeDeg
  final stopRangeOffset = (r * sweep - sweep / 2) * stopRange;  // 450
  final startDeg = layout.sectorStartDeg(prizeFlag!);           // 等分时 == prizeFlag * prizeDeg（必须按此式计算以保持逐位）
  double candidate(int i) => 360 * i - startDeg - rotateDeg - offsetDegree + stopRangeOffset - sweep / 2; // 453 运算顺序
  endDeg = stopSolver.solve(LuckyStopProblem(
      start: stopDeg, candidate: candidate, cruiseSpeed: speed,
      frameMs: timebase == frame ? fps : kLuckyReferenceFrameMs,
      decelerationMs: decTime, easing: decEase, selection: LuckyStopSelection.nearest, direction: 1))
    + 360.0 * extraRevolutions;
}
```

上游选择规则（`UpstreamStopSolver`，selection = nearest，wheel.ts:451-461）：

```dart
var i = 0; var prevSpeed = 0.0; var prevDeg = 0.0;
while (++i <= maxIterations) {
  final endDeg = candidate(i);
  final currSpeed = easing.easeOut(frameMs, start, endDeg, decelerationMs) - start;
  if (currSpeed > cruiseSpeed) {
    return (cruiseSpeed - prevSpeed > currSpeed - cruiseSpeed) ? endDeg : prevDeg;
  }
  prevDeg = endDeg; prevSpeed = currSpeed;
}
```

`MonotonicStopSolver` 的唯一区别：在 `return` 处，若将要返回 `prevDeg` 且 `!(prevDeg * direction > 0)`，改返回 `endDeg`。

nearest 搜索的 #205 半周期首帧速度差上界须以「未触发方向修正」为前提；舍弃非正候选后可能超过该界，现有测试同时覆盖此前提及反例。不要为满足无条件上界改变 IMP-01。

泛化（luckdraw 内部）：上面的 `currSpeed` 实际按 `(easeOut(...) - start) * direction` 计算再与 `cruiseSpeed` 比较；转盘/九宫格 `direction = 1`，乘 1 精确，与上游逐位相同。`direction = -1` 只被数字转盘的小球使用（上游无对应）。

最终角度验证：`rotateDeg_final = stopDeg + endDeg = 360·i − startDeg − offsetDegree + stopRangeOffset − sweep/2`，代入绘制公式得目标扇区中线位于 `−90° + stopRangeOffset`，即指针下（`|stopRangeOffset| < sweep/2`）。settled 时反算并断言目标一致（ISS-448）。唯一零位移哨兵例外为兼容组合 `frame` + `UpstreamStopSolver`：上游 prevDeg 初值 0 未必与目标同余，仍按 DEV-07 正常结算并豁免该次对齐；默认单调及非零位移不豁免。

`play()`（467-479）：`step != 0` 返回 false；`_pendingStart = true; prizeFlag = null; step = 1; hooks.afterStart`。
`stop(index)`（485-500）：`step == 0 || step == 3` 返回 false；`index == null` → `picker.pick(...)`（null 视为 -1）；`index < 0` → `step = 0; prizeFlag = -1`（作废，发 onEnd(cancelled)）；否则 `step = 2; prizeFlag = index.remainder(n)`。

---

## 6. 九宫格 `lib/grid.ts`

### 6.1 函数映射

| 编号 | 上游 | 行号 | luckdraw | 等级 |
| --- | --- | --- | --- | --- |
| FID-G01 | 字段（含未使用的 `demo`/`timer`） | 31-75 | `GridMotion`、`GridLayout` | 等价（`demo/timer` N/A） |
| FID-G02 | `initLucky()` | 102-116 | `GridMotion.reset()`（`prizeFlag = -1`，无高亮） | 逐位 |
| FID-G03 | `initComputed()`：`gutter = getLength(gutter)`、`speed = speed / 40`；样式默认值 | 142-179 | §4.2；`GridMotion` 内部 `speed / 40` | 逐位 |
| FID-G04 | `initWatch()`：`rows/cols` 变化 → `init()` 全重置 | 184-214 | 结构类变更（游戏视图在所有运动阶段排队至本局结算后） | IMP-07 |
| FID-G05 | `handleClick(e)`：遍历 `[...buttons, button]`，用 `getGeometricProperty`（不含阴影收缩）的矩形命中；`step !== 0` 时不触发；先 `btn.callback(btn)` 再 `start(e, btn)` | 262-281 | `GridGame.hitTestAll`：按钮按声明顺序逐个判断（多个都命中时**全部**触发，与上游 forEach 一致）；`onStart` 仅 idle 类阶段；`onButtonTap` 总是；奖品格命中 → `onCellTap`（新增） | 等价 + IMP-12 |
| FID-G06 | `loadAndCacheImg`：`src` 与 `activeSrc` 并行加载，formatter 分别处理 | 290-326 | `LuckyImageResolver`（`GridImage.activeImage` 作为独立槽） | IMP-04 |
| FID-G07 | `draw()` | 331-483 | `computeGridLayout` + `GridPainter` | 见 §6.2 |
| FID-G08 | `handleBackground`：含 `linear-gradient` 则按当前矩形生成渐变 | 494-507 | `LuckyFill.createShader(rect)` | 逐位（几何） |
| FID-G09 | `carveOnGunwaleOfAMovingBoat()` | 512-528 | `GridMotion._carve()` | 逐位/IMP-01 |
| FID-G10 | `play()`/`stop()`/`run()` | 533-621 | `GridMotion` | 逐位/IMP-03 |
| FID-G11 | `getGeometricProperty([x, y, col, row])` | 628-640 | `GridLayout.cellRect(x, y, col, row)` | 逐位 |
| FID-G12 | `conversionAxis` | 647-650 | — | N/A |

### 6.2 绘制（几何）

```text
cells = [...prizes, ...buttons, (button)]，col/row 缺省 1
area = {x:0, y:0, w:boxW, h:boxH}
for block in blocks:                                   // 348-376
  [pt, pb, pl, pr] = computePadding(block)             // 上游 4 值顺序
  r = block.borderRadius ? getLength(block.borderRadius) : 0
  if hasBackground(block.background): fill roundRect(area.x, area.y, area.w, area.h, r) with handleBackground(area)
  img: box(maxW = area.w, maxH = area.h); x = area.x + (area.w - tw)/2 + getLength(left, area.w); y = area.y + getLength(top, area.h)
  area = {x + pl, y + pt, w - pl - pr, h - pt - pb}    // luckdraw：w/h 钳到 >= 0（IMP-10）
cellWidth  = (area.w - gutter * (cols - 1)) / cols     // 378
cellHeight = (area.h - gutter * (rows - 1)) / rows     // 379
cellRect(x, y, col, row) = [area.x + (cellWidth + gutter) * x, area.y + (cellHeight + gutter) * y,
                            cellWidth * col + gutter * (col - 1), cellHeight * row + gutter * (row - 1)]   // 628-640

for idx, cell in cells:
  [x, y, w, h] = cellRect(cell)
  isActive = (prizeFlag == undefined || prizeFlag > -1) && idx == (currIndex % prizes.length) >> 0   // 384-388
  bg = isActive ? activeStyle.background : (cell.background || defaultStyle.background)
  if hasBackground(bg):
    shadowStr = isActive ? activeStyle.shadow : (cell.shadow || defaultStyle.shadow)
    shadow = shadowStr.replace(/px/g,'').split(',')[0].split(' ').map((n,i) => i < 3 ? Number(n) : n)
    if shadow.length == 4:
      shadowColor = shadow[3]; offsetX = shadow[0]*dpr; offsetY = shadow[1]*dpr; blur = shadow[2]   // Canvas 设备像素语义
      shadow[0] > 0 ? (w -= shadow[0]) : (w += shadow[0], x -= shadow[0])     // 406
      shadow[1] > 0 ? (h -= shadow[1]) : (h += shadow[1], y -= shadow[1])     // 407
    fill roundRect(x, y, w, h, getLength(cell.borderRadius ? cell.borderRadius : defaultStyle.borderRadius)) with handleBackground(x,y,w,h)
    清除阴影
  // 注意：x/y/w/h 被阴影收缩后，**图片与文字也用收缩后的矩形**
  img: src 必须已加载；renderImg = (isActive && activeImg) || img
       box(maxW = w, maxH = h); x + (w - tw)/2 + getLength(left, w); y + getLength(top, h)
  font（§4.5 的激活覆盖规则）：ctx.font = `${weight} ${size >> 0}px ${family}`
    lines = wordWrap ? splitText(removeEnter(text), () => getLength(lengthLimit, w), lineClamp) : text.split('\n')
    // 九宫格**不过滤空行**
    fillText(line, x + (w - measure(line))/2 + getLength(font.left, w), y + getLength(font.top, h) + (i+1) * getLength(lineHeight))
```

luckdraw 渲染：每格normal/active内容仍独立录制Picture；auto仅缓存有背景且有阴影的格子背景纹理（受maxRasterSide约束），几何与阴影收缩仍遵循上面规则；`foreground`（新增）在文字之后绘制，`border`（新增）在背景之后、图片之前描边（`Paint.style = stroke`，沿收缩后圆角矩形内缩 `width/2`）。

### 6.3 动画逐帧（GridMotion，逐位）

SM-E09 按 D7 保留提前 stop 直接进入 decelerating 的语义，无单独 cruising 帧。F2 已修正 g05 第 157 帧的人造阶段投影，完整 420 帧数值与阶段验证通过并解除跳过；老虎机仍按 §7.4 保留上游路径的 cruising 帧。

与 §5.3 结构相同，差异：

```dart
// 状态量 currIndex 代替 rotateDeg；n = prizes.length；speed = options.motion.speed / 40；base = 0.1（从 idleSpin 起步时为 idleSpinSpeed / 40）
加速：currSpeed = accEase.easeIn(startInterval, base, speed - base, accTime);   // grid.ts:592（b=0.1，c=speed-0.1）
      if (currSpeed == speed) step = 2;   // 浮点上可能永远不相等（例如 speed=0.7/…），上游此时 step 保持 1 但位移相同；phase 按时间派生，见 ARCHITECTURE §9.1
      currIndex = currIndex + currSpeed.remainder(n) * k;
匀速：currIndex = currIndex + speed.remainder(n) * k;
减速：currIndex = decEase.easeOut(endInterval, stopIndex, endIndex, decTime);
求解：candidate(i) => n * i + prizeFlag - stopIndex;     // grid.ts:519 运算顺序：(n*i + flag) - stop
      selection nearest；frameMs 同转盘
activeIndex = (prizeFlag == null || prizeFlag > -1) && n > 0 ? currIndex.remainder(n).toInt() : -1
```

通知：`activeIndex` 与上次不同才 `notify()`（ADR-16），同时触发 `onActiveChanged`。上游 `n == 0` 时 `NaN >> 0 == 0` 会把第 0 个 cell（按钮）标成激活（U-27）；luckdraw 在 `n == 0` 时不 play、不激活。

---

## 7. 老虎机 `lib/slot.ts`

### 7.1 函数映射

| 编号 | 上游 | 行号 | luckdraw | 等级 |
| --- | --- | --- | --- | --- |
| FID-S01 | 字段（含 `_offscreenCanvas`、`scroll[]`、`stopScroll[]`、`endScroll[]`、`defaultOrder`） | 26-71 | `SlotMotion`（`Float64List scroll/stopScroll/endScroll`）、`SlotLayout`（`reelCells`） | 等价 |
| FID-S02 | `initLucky()`：`prizeFlag = undefined` | 98-113 | `SlotMotion.reset()` | 逐位 |
| FID-S03 | `initComputed()`：`rowSpacing/colSpacing = getLength(...)` | 133-164 | §4.3 | 逐位 |
| FID-S04 | `initWatch()`：`slots` 变化重画离屏 | 169-196 | 结构类变更 | IMP-07 |
| FID-S05 | `drawOffscreenCanvas()` | 273-380 | `computeSlotLayout`（格子几何）+ `SlotPainter`（每奖品一张格子 Picture） | DEV-09/ADR-11 |
| FID-S06 | `drawBlocks()`：背景 `block.background \|\| defaultStyle.background` | 385-414 | `SlotLayout` blocks 段 | 逐位 |
| FID-S07 | `draw()`：可见窗口 `start = displacement(-(h - hs)/2, -(w - ws)/2)`、取模回绕、整块复制 | 419-454 | `SlotPainter` 可见格回放 | 等价 |
| FID-S08 | `carveOnGunwaleOfAMovingBoat()` | 459-481 | `SlotMotion._carve()` | 逐位/IMP-16 |
| FID-S09 | `play()` | 486-498 | `SlotController.play` | 逐位 |
| FID-S10 | `stop(index \| index[])` | 500-525 | `SlotController.stop/stopEach/cancel` | 逐位/DEV-15/IMP-21 |
| FID-S11 | `run(num)` | 531-595 | `SlotMotion.tick` | 逐位/IMP-05 |
| FID-S12 | `displacement(a, b)` / `displacementWidthOrHeight()` | 598-629 | `SlotLayout` 内按 `mode` 选择 | 逐位 |

### 7.2 布局

```text
// displacementWidthOrHeight（603-629），area 来自 drawBlocks
n = slots.length
vertical:   cellWidth  = (area.w - colSpacing * (n - 1)) / n ; cellHeight = cellWidth
horizontal: cellHeight = (area.h - rowSpacing * (n - 1)) / n ; cellWidth  = cellHeight
// IMP-17：cellAspectRatio != null 时，vertical: cellHeight = cellWidth / ratio；horizontal: cellWidth = cellHeight * ratio
widthAndSpacing = cellWidth + colSpacing ; heightAndSpacing = cellHeight + rowSpacing
cellAndSpacing = horizontal ? widthAndSpacing : heightAndSpacing

// 每列的格子（drawOffscreenCanvas 296-364）
order = slot.order || defaultOrder(0..prizes.length-1)
newPrizes = getSortedArrayByIndex(prizes, order)   // order 里越界/指向缺失的下标留洞（稀疏）
for cellIndex, cell in newPrizes（跳过洞）:
  vertical:   格子左上 = (列 x, heightAndSpacing * cellIndex + rowSpacing / 2)，大小 (cellWidth, cellHeight)
  horizontal: 格子左上 = (widthAndSpacing * cellIndex + colSpacing / 2, 行 y)
  背景：roundRect(_x, _y, cellWidth, cellWidth, r)   // 上游高度也用 cellWidth（正方形时等价）；luckdraw 用 cellHeight（IMP-17 前提下才不同）
       r = getLength(has(cell,'borderRadius') ? cell.borderRadius : defaultStyle.borderRadius)
  图片：box(maxW = cellWidth, maxH = cellHeight); _x + (cellWidth - tw)/2 + getLength(left, cellWidth); _y + getLength(top, cellHeight)
  文字：lengthLimit 基准 cellWidth；不过滤空行；x/y 规则同九宫格（基准 cellWidth/cellHeight）
周期 _p = cellAndSpacing * order.length   // 注意：用 order.length 而不是实际格子数（洞会造成错位，U-20；luckdraw 照搬，测试覆盖）
```

### 7.3 绘制（每帧）

```text
for r, slot:
  order = slot.order || defaultOrder ; _p = cellAndSpacing * order.length
  start = vertical ? -(area.h - heightAndSpacing) / 2 : -(area.w - widthAndSpacing) / 2
  s = scroll[r] + start
  if (s < 0) s = s % _p + _p        // JS 取余 → remainder
  if (s > _p) s = s % _p
  上游：从离屏图 (列 x, s) 处截取 (cellWidth × area.h) 贴到 (area.x + widthAndSpacing * r, area.y)
  luckdraw：clipRect(列矩形)；对窗口 [s, s + 窗口长度] 内的每个格子 j（含 +_p、+2_p 的循环副本），
            translate(列 x, area.y + (格子 j 在条带上的起点 + m * _p - s)) 后 drawPicture(格子 j)
```

### 7.4 动画逐帧（SlotMotion，逐位，IMP-05 除外）

SM-E09 的老虎机路径保留上游 cruising 帧（slot.ts:562–581）：本帧以局部 step0 判断各列分支，加速完成与待停减速的衔接不同于 wheel/grid。不得把 D7 的 wheel/grid 直接减速解释为所有玩法都删除 cruising 帧；stopDelay=0 的逐帧对照仍用 frame + UpstreamStopSolver。
```dart
void tick(double t, double dt) {
  if (_pendingStart) { startTime = t; _pendingStart = false; num = 0; }
  final step0 = step;                                                   // 上游在 run 开头解构的局部 step（532），整帧各列共用
  if (step0 == 0) return;                                               // 结束判定已在置 0 时完成
  if (prizeFlag != null && prizeFlag!.isEmpty) return;                  // 549
  if (step == 3 && endScroll.isEmpty) _carve(t);                        // 551
  final startInterval = t - startTime, endInterval = t - endTime;
  for (var r = 0; r < reels.length; r++) {
    final order = orderOf(r); if (order.isEmpty) continue;
    final p = cellAndSpacing * order.length;
    final speed = (reels[r].speed ?? options.speed).abs();             // 560 Math.abs
    final dir = reels[r].direction ?? options.direction;
    double s = 0; final prev = scroll[r];                               // 562：let scroll = 0
    if (step0 == 1 || startInterval < accTime) {
      if (timebase == frame && num > 0) fps = startInterval / num;
      final currSpeed = accEase.easeIn(startInterval, base, speed - base, accTime);
      if (currSpeed == speed) step = 2;
      s = (prev + currSpeed * dir * k).remainder(p);                  // 571
    } else if (step0 == 2) {
      s = (prev + speed * dir * k).remainder(p);                        // 574
      if (prizeFlag != null && prizeFlag!.length == reels.length) { step = 3; stopScroll.clear(); endScroll.clear(); } // 576-581
    } else if (step0 == 3) {                                            // 上游：step === 3 && endInterval（非 0）
      s = decEase.easeOut(endInterval, stopScroll[r], endScroll[r], decTime);   // IMP-05：endInterval == 0 时得 stopScroll，上游此时 s 保持 0（U-06）
      if (endInterval >= decTime) step = 0;
    }
    scroll[r] = s;
  }
  num++;
  if (step == 0) _emitEnd();                                            // 535-547 的判定，见下
}
```

`frame` 模式 `k == 1`：`currSpeed * dir * k` 的运算顺序是 `(currSpeed * dir) * 1.0`，与上游 `currSpeed * direction` 相同。注意 `step == 3` 后 `stopScroll/endScroll` 是可增长列表（上游数组），luckdraw 用 `Float64List(reels.length)` + 一个 `bool _carved` 标志代替 `endScroll.length == 0` 判断。

求解（459-481，selection = firstExceeding）：

```dart
endTime = t;
for r: order 为空跳过
  final speed = reels[r].speed ?? options.speed;                      // 466：**不取绝对值**
  final dir = reels[r].direction ?? options.direction;
  final orderIndex = order.indexOf(prizeFlag![r]);                    // 可能为 -1（U-08）
  final p = cellAndSpacing * order.length;
  stopScroll[r] = scroll[r];
  candidate(i) => cellAndSpacing * orderIndex + (p * i * dir) - stopScroll[r];   // 473 运算顺序
  // Upstream：第一个 |easeOut(fps, stop, cand, dec) - stop| > speed 的候选
  // Monotonic（IMP-16）：额外要求 cand * dir > 0
```

结束（535-547）：`flag = prizeFlag[0]`；逐列若 `!order.contains(prizeFlag[r]) || flag != prizeFlag[r]` 则 `flag = -1`；`onEnd(SlotResult(indices: prizeFlag, index: flag >= 0 ? flag : null, prize: …))`。luckdraw 把这段判定抽成 `upstreamSlotWinPredicate(indices, config)`，可被 `SlotConfig.winPredicate` 替换（#182）。

`stop(index)`（500-525）：number → 每列同值；数组长度不符 → 上游 `stop(-1)` + `console.error`，luckdraw `stopEach` 抛 `ArgumentError`（DEV-15）；含 `-1` → `prizeFlag = []; step = 0`，**不发 onEnd**（SM-E25）。luckdraw 把任何负数都视为取消（IMP-21，上游只认 -1）。`stop()` 不带参数上游报错并取消；luckdraw 走 picker（IMP-15）。

---

## 8. 偏离与疑点清单

### 8.1 有意改进（IMP，为规避上游问题）

IMP-05 是无开关修复，在 `frame + UpstreamStopSolver` 下也无条件生效；U-06 仅在对照侧映射为「首减速帧等于 stopScroll」，不得恢复归零。DEV-07/IMP-18 的零位移哨兵对齐例外属于停止求解，不能扩展成 IMP-05 的例外。

原则：每条改进可被测试区分、在验收矩阵单列，并写明影响范围及兼容开关。默认单调求解在上游正常候选区间保持数值；默认 time 的归一化会改变采样轨迹，不能把「未出问题路径一致」扩大为所有默认动画逐帧一致（D3/B1）。

| 编号 | 改进内容 | 规避的问题 | 对 1:1 对照的影响 | 兼容开关 / 对比口径 | 验收 |
| --- | --- | --- | --- | --- | --- |
| IMP-01 | `MonotonicStopSolver`：候选 i−1 只有方向正确（`cand × direction > 0`）才可被选 | #419 倒转；U-04 位移 0 永不停 | 上游候选为正的参数区间内**逐位相同**；#419 区间内不同 | `LuckyMotionOptions.stopSolver: UpstreamStopSolver()`；`strictUpstream()` 预设已包含；1:1 测试一律用 Upstream | ISS-419、FID-W11 |
| IMP-02 | 有效时间轴：单帧 dt 钳制 `maxFrameDelta`（默认 100ms）+ 后台/显式暂停冻结 | #308/#378（根因未确认） | 伪时钟 16ms 步长下不触发，无影响 | `maxFrameDelta` 设为极大值、`pauseWhenHidden: false` 可关闭 | ISS-308 |
| IMP-03 | 默认 `LuckyTimebase.time`：位移按 `dt / (1000/60)` 归一，求解用固定 `1000/60` ms | 高刷屏转速翻倍（C5，推测；源码可证匀速段按帧累加） | time 与上游按帧轨迹不同；ISS-120HZ 按 D7 验最终停点一致、加速段中间相位差 ≤6° | `timebase: LuckyTimebase.frame`；`strictUpstream()` 已包含 | ISS-120HZ |
| IMP-04 | 图片：`onImageError`、`fallback`、`onReady`；失败不影响其它类别重绘；`afterInit` 在全部图片有结论后触发 | #417、#264；上游 `Promise.all` 一张失败整类不重绘（wheel.ts:218-221） | 无 fallback 且全部加载成功时与上游最终画面一致；`afterInit` 触发时机不同（U-22） | 无需开关 | ISS-417、ISS-264 |
| IMP-05 | 老虎机减速首帧（`endInterval == 0`）取 `stopScroll`，不归零 | U-06（一帧跳到起点，#205 同类） | 该帧不同（上游 scroll=0） | 无开关；1:1 对比**排除**每列减速首帧并改断言"等于 stopScroll" | FID-S11 |
| IMP-06 | `splitLuckyText` 逐码点 | emoji 代理对被切开 | BMP 文本逐位相同；对照用例只用 ASCII | 无 | FID-U16 |
| IMP-07 | 受控更新：外观立即且不重置动画；结构变更在 accelerating/cruising/decelerating/idleSpinning 全部排队到本局结算后；尺寸只重算布局；老虎机滚动量随 `cellAndSpacing` 缩放 | #382 #287 #550 #246 #146 | 对照用例不含运行中改配置，无影响；motion configure 另做钳制/重映射 | 无 | ISS-382、ISS-287、ISS-146 |
| IMP-08 | 非有限值/零奖品/零时长保护：零奖品 `play()` 返回 false；求解迭代上限 100000；时长 ≤0 按 1ms | U-05、U-13（死循环）、0/0 | 上游在这些输入下卡死或 NaN，无可比性 | 无 | R2-11、R3-21、R3-25 |
| IMP-09 | 三玩法背景都支持渐变（`LuckyFill`）；compat 色标解析修正（两种写法 + >2 色均分 + 括号感知切分） | #402、U-10 | 转盘/老虎机上游写渐变串为无效输入（Canvas 忽略赋值、沿用上一个 fillStyle）；九宫格 ≤2 个无位置色标时一致 | 无（复刻"沿用上一个 fillStyle"无意义） | ISS-402 |
| IMP-10 | 几何钳制：半径/宽高 `max(0, …)`，负值段跳过 | #336 #416（根因未确认） | 上游在这些输入下抛异常 | 无 | ISS-336 |
| IMP-11 | 类型化 API 中格子 `borderRadius: 0` 生效 | U-11 | compat 照搬上游（0 → 默认 20），对照无影响 | compat 自动 | FID-G07 |
| IMP-12 | `onButtonTap` 在任意阶段触发；`idleSpin()`；`onCellTap` | #370、#153 | `onStart` 语义不变，无影响 | 无 | ISS-370、ISS-153 |
| IMP-13 | `WeightedPrizePicker(honorDisabled: true)` 排除 `disabled` 奖品 | U-18（字段声明却未用） | compat 不映射 `disabled`，无影响 | `honorDisabled: false`；compat `honorDisabled` 选项 | R3-08 |
| IMP-14 | compat 的 `honorSpeedFunction` 选项 | U-09 | 默认忽略（与上游一致） | 选项默认 false | R3-30 |
| IMP-15 | 老虎机 `stop()` 无参数时走 picker | #355 同类；上游报错并取消 | 上游为错误路径 | 无 | R3-15 |
| IMP-16 | 老虎机求解同样受单调约束 | U-25（direction −1 时首个候选可能为正，反向滚动） | 上游正常区间内逐位相同 | `UpstreamStopSolver` | FID-S08 |
| IMP-17 | 新增中性字段：`sectorWeight`、`cellAspectRatio`、`LuckyImage.borderRadius/opacity/fallback`、`LuckyCellStyle.border/foreground/borderRadius(激活)` | #151 #331 #265 #254 #304 #347 | 默认值下与上游一致 | 不设即可 | ISS-151、ISS-265、ISS-254、ISS-304 |
| IMP-18 | settled 时反算指针下扇区并 `assert` 与目标一致 | #448（未确认） | 兼容组合 frame + UpstreamStopSolver 的零位移哨兵按 DEV-07 豁免；默认单调和非零结果仍断言 | 例外仅限兼容模式 | ISS-448 |
| IMP-19 | 每帧绘制自包含（save/restore 平衡），不跨帧累积变换 | #176 #278（根因未确认） | 无 | — | ISS-176 |
| IMP-20 | 线性渐变负角度先 `+360` | U-24 | 上游画不出（退化渐变） | 无 | R3-04 |
| IMP-21 | 老虎机任何负数 index 都视为取消 | U-08（上游只认 -1，-2 会停到最后一格且结果为未中奖） | 上游为错误用法 | 无 | R3-16 |

### 8.2 有意偏离（DEV，非 issue 驱动）

`LuckyCacheMode`三值：picture矢量回放、raster使用支持段位图、auto运动位图/静止矢量（新默认）；超maxRasterSide退回Picture，缓存键含DPR、原点及尺寸。低层缓存和strictUpstream仍picture，详见ARCHITECTURE §8。默认 auto 缓存使转盘典型帧 Raster 由约16.4ms降到约5ms，AB2 的 Impeller 三轮极稳；vivo V2417（Android 16）上仍有约三成轮次整轮落入12–17ms高档，与亮度、监控轮询、渲染后端（Skia/Impeller）均无关，根因未解释，不是 luckdraw 已知缺陷，也未证明是设备缺陷。因此真机性能验收**未完全通过**；Raster/掉帧目标未放宽，转盘、数字转盘、大乐透因双峰判不稳定。三轮样本不能据此估计总体发生概率。

Skia/Impeller 各三次阴影对照已采集：半径差1–2物理像素、扫描线峰值差20.8–23.8/255；sigma 调整建议待决定，未修改公式。老虎机阴影在视口内被裁剪，缺少可观察样本，不能宣称其阴影验收通过。

| 编号 | 偏离 | 原因 | 影响 | 验收 |
| --- | --- | --- | --- | --- |
| DEV-01 | 文字用 `TextPainter` 测量/绘制；`fontStyle` 映射为 `fontFamily` + `fontFamilyFallback`；字体回退链与浏览器不同 | 平台差异 | 换行位置可能不同；1:1 图像对比只用 ASCII + 两端同一 Roboto | FID-U16、parity 用例 |
| DEV-02 | 静态段Picture录制代替逐帧重画；默认auto运动期使用受限位图、静止期矢量；扇形顶点不做 `toFixed(8)` | 性能（ADR-03/ADR-32） | auto有位图重采样差异；strictUpstream与1:1测试保持picture及原容差 | R2-02 |
| DEV-03 | 阴影：`LuckyShadow.blurSpace`；compat 产出 `device`（`sigma = blur/2/dpr`），类型化默认 `logical`（`sigma = blur/2`）；偏移按逻辑像素（上游乘 dpr 后作用于设备像素，等价） | Canvas 阴影不受变换影响 | 与 Chrome 的高斯核实现不同，阴影用例单独容差 | R3-05 |
| DEV-04 | 阴影 alpha 乘以**纯色**填充的 alpha；渐变填充不乘 | Canvas 阴影取自绘制内容 alpha，Flutter 需手动模拟 | 半透明渐变 + 阴影的组合与上游不同 | R3-05 |
| DEV-05 | `formatter` 签名为 `FutureOr<ui.Image> Function(ui.Image)`；返回的新图片所有权归 luckdraw（淘汰时 dispose）；compat 忽略 JSON 里的 formatter | 无 DOM | 无法源码兼容 | R3-10 |
| DEV-06 | `onEnd` 在置 `step = 0` 的同一 tick 发出（上游在下一帧 `run()` 开头） | 少一帧延迟、Ticker 可立即停止 | 回调早约 16ms；画面无差异 | SM-E11 |
| DEV-07 | 兼容组合 frame + UpstreamStopSolver 求得零位移时只求解一次，照常减速并 settled | 避免上游零哨兵每帧重解而冻结 | 零哨兵可能不与目标同余，仅此兼容模式豁免 IMP-18；默认单调和非零结果无此例外 | ISS-419 |
| DEV-08 | `maxBtnRadius` 布局前先算，首帧即正确；按钮半径变小时立即生效（上游只增不减直到 `init()`） | 布局纯函数化 | 上游首帧扇形内侧点在圆心（随后第二次 draw 修正），luckdraw 无此中间态 | FID-W10 |
| DEV-09 | 老虎机无离屏长图；水平模式不受上游复制循环上界 bug 影响（U-07） | ADR-11 | 上游在 U-07 情形下右侧可能露白，luckdraw 总是完整 | ISS-297 |
| DEV-10 | 老虎机按列 `clipRect`，格子内容溢出不会串到相邻列 | 上游离屏列宽 = cellWidth 紧挨，溢出会被相邻列截取显示 | 仅内容溢出格子时不同 | FID-S07 |
| DEV-11 | `alignment` 参数（默认 topLeft = 上游） | 非正方形容器的常见需求 | 默认无影响 | R3-17 |
| DEV-12 | `frame` 模式下第 0 帧不更新 `fps`（上游 0/0=NaN，下一帧覆盖） | 避免 NaN 进入状态 | 仅当停止求解发生在第 1 帧之前才有差别（上游此时死循环，U-05） | FID-W13 |
| DEV-13 | 图片自然尺寸取 `image.width / ImageInfo.scale`；显式尺寸时按绘制尺寸×dpr 解码（宽高比有 ≤1px 取整误差） | Flutter 资源分辨率体系、内存 | 1x 资源下与上游一致 | R2-08 |
| DEV-14 | 首帧不等图片；图片逐张到达即重录对应静态段（上游按 blocks/prizes/buttons 三类各自 `Promise.all` 后整体重画） | 渐进显示 | 中间帧不同，最终画面一致 | ISS-417 |
| DEV-15 | `stopEach` 长度不符抛 `ArgumentError`（上游取消 + console.error） | 编程错误应显式暴露 | 错误路径 | R3-22 |
| DEV-16 | compat 解析失败（`'10 px'`、未知颜色）返回 null + warning；上游得到 NaN/无效 fillStyle | 可诊断 | 错误路径 | R3-27 |

### 8.3 不支持（N/A）

平台 flag 与小程序分支（lucky.ts:205-280 中的 `UNI-*`/`TARO-*`/`MP-WX` 分支）、`dpr` 配置、`rAF`/定时器注入、`$set/$computed/$watch` 与 `observer/*`、`beforeCreate`、`clearCanvas`、`conversionAxis`、`getOffscreenCanvas`、`throttle`、`getTangentByPointer`、`image.ts` 的 `blur/getMatrix/getImage/getBase64Image`、`polyfill.js`、九宫格未使用的 `demo/timer` 字段、按钮 `callback`（由 `onButtonTap` 代替）、`imgs[].formatter` 的源码兼容。

### 8.4 上游疑点 / 潜在 bug（源码阅读所得；"推测"均未在浏览器复现）

| 编号 | 位置 | 现象 | 依据 | luckdraw 处理 |
| --- | --- | --- | --- | --- |
| U-01 | index.ts:98-106 | `paddingTop/Bottom/Left/Right` 单独字段计算进 `res` 后没有返回，永远无效 | 源码 | compat 忽略 + warning |
| U-02 | index.ts:55-64 | `hasBackground('rgba(0,0,0,0)')` 为 true：`getNumber` 收到正则结果数组得 NaN | 源码 | 照搬语义（非 null 即有背景） |
| U-03 | index.ts:132-147 | 全部 `range` 缺省时返回 -1，`stop()` 静默取消本局 | 源码 | 照搬；文档写明；SM-E15 |
| U-04 | wheel.ts:451-461、grid.ts:518-527 | 选中的 i−1 候选可能 ≤0：<0 倒转（#419）；=0 时 `!this.endDeg` 每帧重解、`endTime` 每帧重置 → 永不停止（推测） | 源码推导（ARCHITECTURE §11.3 给出触发条件） | IMP-01、DEV-07 |
| U-05 | wheel.ts:525、445-462 | 极短 `accelerationTime` 且在第 1 帧前 `stop()`：`FPS = 0/0 = NaN`，求解 `while (++i)` 永不退出（推测） | 源码推导 | DEV-12 + 迭代上限 |
| U-06 | slot.ts:551-590 | 求解与 `endInterval` 在同一 `run()` 内计算，`endInterval` 通常为 0 → `step === 3 && endInterval` 不成立 → 该帧 `scroll = 0`，画面跳到起点一帧（推测，概率高） | 源码 | IMP-05 |
| U-07 | slot.ts:370 | 复制循环上界固定用 `maxOffHeight`，水平模式应为宽度方向，可能复制不足（推测） | 源码 | DEV-09 |
| U-08 | slot.ts:517 | 只把 `-1` 当取消；`-2` 时 `findIndex` 得 -1，停到最后一格且结果为"未中奖" | 源码 | IMP-21 |
| U-09 | wheel.ts:130 vs 526/544 | `speedFunction` 有默认值但从未读取 | 源码 | IMP-14 |
| U-10 | math.ts:121-126 | 色标 `addColorStop(...info)` 参数顺序为（位置, 颜色）；无位置时用下标当偏移，≥3 个越界抛错中断绘制；`split(',')` 拆坏 `rgb()` | 源码 + Canvas 规范 | IMP-09 |
| U-11 | grid.ts:411 | 格子 `borderRadius: 0` 是假值，无法覆盖默认 20 | 源码 | IMP-11 |
| U-12 | wheel.ts:400 | `maxBtnRadius` 只增不减，直到 `init()` | 源码 | DEV-08 |
| U-13 | wheel.ts:498、grid.ts:564 | 零奖品时 `stop(0)` 得 `prizeFlag = 0 % 0 = NaN`，求解死循环（推测） | 源码推导 | IMP-08 |
| U-14 | index.ts:92-96 | 4 值 padding 顺序是 top, bottom, left, right（非 CSS） | 源码 | compat 照搬；核心用 CSS 顺序 |
| U-15 | wheel.ts:304 | 转盘 block `padding` 只取第一个 token，百分比按分母 1 | 源码 | compat 照搬 |
| U-16 | grid.ts:393-399 | 阴影串按 `,` 切分取第一个，`rgba(…)` 颜色会被拆坏；blur 不乘 dpr | 源码 | compat 括号感知切分；DEV-03 |
| U-17 | wheel.ts:313-315、434 | 按钮文字 `left` 的百分比基准是奖品弦长 `shortSide` | 源码 | 照搬 |
| U-18 | types/grid.ts:200 | `disabled` 声明了但没有任何代码读取 | 源码 | IMP-13 |
| U-19 | image.ts:105-129 | `blur` 未完成（空循环 + console.log） | 源码 | N/A |
| U-20 | index.ts:191-201、slot.ts:301-312/433 | `order` 含无效下标时，离屏只画存在的格子，但周期按 `order.length` 计算，滚动错位 | 源码 | 照搬（测试覆盖，避免"修了反而对不上"） |
| U-21 | wheel.ts:510-512 | 结束回调比最终画面晚一帧 | 源码 | DEV-06 |
| U-22 | wheel.ts:202-224 | `initImageCache` 的 Promise 在**第一个**类别完成时 resolve；某类别无图片时几乎立即 resolve，`afterInit` 早于图片加载完成 | 源码 | IMP-04 |
| U-23 | wheel.ts:194-195、328 | 首次 draw 时 `maxBtnRadius = 0`，扇形顶点在圆心，所以 `init()` 画两次 | 源码注释 | DEV-08 |
| U-24 | math.ts:100-112 | 负角度不落入任何扇区，端点全 0（退化渐变） | 源码 | IMP-20 |
| U-25 | slot.ts:472-478 | `direction = -1` 时第一个候选可能为正、且 `\|速度\|` 已超阈值 → 反向滚动（推测，需短减速时长） | 源码推导 | IMP-16 |
| U-26 | lucky.ts:147-148 | `width: '80%'` 无分母按 1 解析为 0.8px | 源码 | compat 返回 null + warning |
| U-27 | grid.ts:387 | 零奖品时 `NaN >> 0 == 0`，第 0 个 cell（按钮）被判为激活 | 源码 | 不 play、不激活 |

---

## 9. 用户追加玩法（上游无对应）

拉霸机、扭蛋机、数字转盘（刻度 + 小球）、抽签、大乐透是用户在设计阶段追加的玩法，lucky-canvas 中**没有对应实现**，因此：

| 玩法 | 上游关系 | 一致性等级 | 说明 |
| --- | --- | --- | --- |
| 拉霸机 `LuckyLeverSlotMachine` | 基于上游老虎机（slot.ts） | 老虎机部分逐位（`stopDelay = 0` 时）；拉杆、错峰、赔付线为新增 | 错峰开启后每列独立求解，与上游"同时停"不同，属于新增行为，不算偏离 |
| 扭蛋机 `LuckyCapsuleMachine` | 无 | 新增 | 复用上游缓动公式（FID-U08）与选奖（FID-U15） |
| 数字转盘 `LuckyNumberWheel` | 无（与上游大转盘不同：转的是圆盘 + 反向小球） | 新增 | 小球相对角复用停止求解器（`direction = -1`，§5.3 泛化说明） |
| 抽签 `LuckyLots` | 无 | 新增 | 复用缓动与选奖 |
| 大乐透 `LuckyLotto` | 无 | 新增 | 抽样为每池无放回均匀抽样（不经 `computeRange`） |

这些玩法不参加 1:1 对照测试；其行为由 ARCHITECTURE §21 与 IMPLEMENTATION_GUIDE M5 定义，验收编号 R7-*。
