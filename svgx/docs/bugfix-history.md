# 已发现并修复的 bug(历史记录)

> 从 `CLAUDE.md` 拆出。一次性的"发现并修复"记录,按发现时间追加。以后如果还有类似的"用户/测试发现问题→排查→修复"记录,继续往这个文件追加,不要散落进功能记录里。

## 用户肉眼验证发现的 3 个 demo bug(2026-08-25)

用户跑 `example/lib/main.dart`(Windows 桌面)肉眼验证时发现 3 个新特性 demo 渲染不对。逐个排查后:**2 个是引擎真实 bug(已修),1 个是 example 自身数据损坏(已修,非引擎问题)**。诚实记录,不夸大也不掩盖。

### 1. `<image>` base64 PNG 完全不显示 —— 根因是 example 的 base64 数据本身损坏,不是引擎 bug

逐字节核实:`example/lib/main.dart` 里 `kEmbeddedImageSvg` 手打的 base64 字符串解码后 IDAT zlib 流只还原出 3 字节,而 1x1 RGBA PNG 至少需要 5 字节(1 filter + 4 通道)——数据被截断/打错。usvg 解析嵌入位图时需要先解出其固有尺寸,遇到损坏的 PNG 数据会导致整个 `parse_svg` 返回 `Err`,而 `SvgXStatic` 在没有 `errorBuilder` 时的兜底就是渲染一个空白 `SizedBox`——这就是"完全不显示"的表现,但触发原因是数据损坏而非渲染逻辑缺陷。

**修复**:把 `kEmbeddedImageSvg` 的 base64 换成 `rust/src/api/svg.rs` 测试里已验证过的合法 1x1 PNG(`iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==`)。引擎侧的 `<image>` 解析/解码/绘制链路本身未发现问题(`rust/src/api/svg.rs::convert_image`、`rust_static_svg.dart::getOrRenderAsync/_decodeImage` 代码审查 + 既有测试均覆盖过合法数据路径,行为正确)。

### 2. `<animateMotion>` 完全不动 —— 引擎真实 bug,`animation_detector.dart` 检测正则缺失

`AnimationDetector.hasAnimations` 给 `<animate>`/`<animateTransform>`/`<set>` 各写了一条独立正则(此前已修过 `<animateTransform>` 的 `\b` 单词边界坑,见下方"相关的早期同类坑"),但唯独漏了 `<animateMotion>`——它和 `<animateTransform>` 踩的是同一类坑("animate" 紧跟大写字母 "M")。只含 `<animateMotion>`(没有 `<animate>`/`<animateTransform>`/`<set>`)的 SVG 被静默误判为静态,路由去 Rust usvg 路径,而 usvg 会丢弃 SMIL——元素完全不动。

引擎本身的 `_parseAnimateMotion`/`_sampleMotionPath`(`svg_document_parser.dart`/`smil_animation.dart`)实现是对的(`test/animation/animate_motion_test.dart` 全部通过),纯粹是检测层漏了这一个标签。

**修复**:`animation_detector.dart` 新增 `_animateMotionPattern = RegExp(r'<animateMotion[\s>]')` 并纳入 `hasAnimations` 的判定;新增回归测试 `test/animation/animation_detector_test.dart` 显式验证"仅含 `<animateMotion>` 的 SVG 必须被判定为动画"。

**可复查的模式**:往检测器加新标签时,任何形如 "animate" 后紧跟大写字母的新 SMIL 标签(未来若支持更多)都要单独建正则,不能假设已有的 `<animate>`/`<animateTransform>` 覆盖了它。

**相关的早期同类坑**:更早一轮(第三轮扩展)就已经踩过并修过一次几乎相同的 bug——`animation_detector.dart` 原先用单条合并正则 `<\s*(animate|set)\b` 判断是否走动画引擎,`\b` 单词边界在 "animate" 紧跟 "Transform" 时不成立,导致只用 `<animateTransform>`(没有 `<animate>`)的 SVG 被静默误判为静态,动画完全不播放。参考 `full_svg_flutter` 自身 `animation_detector.dart` 的分标签正则写法(每个标签单独一条 `<tag[\s>]`,而非合并 + `\b`)重写后修复,过了 4 个不同相位的截图验证。本条(`<animateMotion>`)是同一类坑在第三个标签上的复现,说明"分标签独立正则"这个模式本身要在每次新增标签时手动跟进,不会自动覆盖。

### 3. `linearGradient` 只显示纯蓝色,没有渐变过渡 —— 引擎真实 bug,Dart 侧完全没读取 Rust 已解析出的渐变字段

审计 `rust/src/api/svg.rs` 发现 Rust 侧其实早就做完了渐变解析的硬活:`convert_path` 会调用 `build_gradient` 把 `<linearGradient>`/`<radialGradient>` 完整解析进 `SvgPath.fillGradient`/`strokeGradient`(含全部色标、已烘焙进绝对坐标空间的端点/矩阵)。但 `lib/src/rust_static_svg.dart` 的 `_recordScene` 里 `paintFill`/`paintStroke` 只读了 `path.fillArgb`/`path.strokeArgb`,从未检查过 `fillGradient`/`strokeGradient` 字段是否非空——渐变数据被 Rust 算出来又被 Dart 侧完全无视。之所以看到"纯蓝色":Rust 的 `paint_argb`(给非渐变字段兜底用的函数)对渐变 paint 会回退取*首个*色标颜色,例子里第一个 stop 正是蓝色 `#2A6DF4`,所以呈现出"看起来选对了起始色、但没有过渡"的假象。

**注意**:动画路径(`svg_gradient.dart`)的渐变支持是完整且已有测试覆盖的(`test/animation/gradient_test.dart`),这个 bug 只存在于静态 usvg 路径。

**修复**:`rust_static_svg.dart` 新增 `_buildGradientShader`,按 `SvgGradient.kind` 分别用 `ui.Gradient.linear`(线性,直接用已绝对化的两端点)或 `ui.Gradient.radial`(径向,用局部焦点/圆心/半径 + `matrix4` 应用 `SvgGradient.matrix`)构建 shader,`paintFill`/`paintStroke` 优先检查对应 gradient 字段,非空则用 shader 而非纯色 `Paint().color`;单色标退化渐变(SVG 语法允许但极少见)复制该色标为 2 份规避 `ui.Gradient` 至少需要 2 色的限制,不崩溃。新增回归测试 `test/rust_gradient_smoke_test.dart` 验证 `fillGradient` 非空且两个 stop 颜色互不相同。

### 验证方式与方法学局限

`cargo test`(14 通过,未改 Rust 逻辑本身,仅审计确认)、`flutter analyze`(无告警)、`flutter test`(70 通过,含本轮新增的 3 个回归测试:`animation_detector_test.dart` 5 例 + `rust_gradient_smoke_test.dart` 2 例)。

**诚实标注一个方法学局限**:本轮受限于当时 shell 工具环境无 GUI/无法弹出 Windows 桌面窗口(`flutter build windows` 在该环境下因 MSBuild/CMake 安装步骤报 `MSB3073` 失败,与本次代码改动无关),**未能在真正弹出的 Windows 窗口里肉眼截图确认三个 demo 视觉效果**,结论建立在:①字节级验证损坏的 base64(手动 inflate zlib 流对比合法/非法 PNG 数据)、②代码审查确认 Rust 侧数据已正确解析、Dart 侧确实遗漏读取、③新增回归测试断言"关键字段非空/取值符合预期"三重交叉验证之上,不是拍脑袋猜测,但仍建议在实机上 `cd example && flutter run -d windows` 肉眼复核一遍这三个 demo,如有出入请反馈。

## 动画路径 `feGaussianBlur` 完全未实现(2026-08-25,像素验证补齐时发现)

在补齐"像素级验证结果"表格第 11 项(feGaussianBlur)的动画侧像素断言时,发现此前"动画路径消费该 sigma 走的是同一套静态 Picture 缓存路径"这个判断是**误判**:动画路径(`SvgXAnimated`/`AnimatedSvgPainter`)与静态路径(`SvgXStatic`/Rust usvg)是两条完全独立的渲染管线,前者从不经过后者的 Picture 缓存,`filter` 属性在动画路径里此前是被直接丢弃的——不是"结构性证据薄弱",是**功能缺失**。

**修复**(最小范围实现,非泛化 filter 系统):

- `lib/src/animation/svg_dom.dart` 新增 `SvgNode.blurSigma`(`double?`)。
- `lib/src/animation/svg_document_parser.dart` 新增 `_parseBlurSigma`,识别两种写法:CSS 简写 `filter="blur(Npx)"`,以及 `filter="url(#id)"` 指向 `<filter><feGaussianBlur stdDeviation="N"/></filter>`(仅支持单个 `feGaussianBlur` 图元)。
- `lib/src/animation/animated_svg_painter.dart` 的 `_paintNode` 在 `blurSigma` 非空时用 `canvas.saveLayer(null, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: s, sigmaY: s))` 包裹该节点(含子树)的绘制。

**采样结果(50×100 蓝色矩形,几何右边缘在 x=50,y=50 行采样)**:无模糊时 `x=41..59` 的 alpha 序列硬跳变(255→0 只用 1 个像素);`filter="blur(8px)"` 时 `x=31..69` 呈现明显渐变衰减(横跨约 30 像素),且原始几何边缘之外多个像素仍有非零 alpha,证明确有渗出(bleed)。`filter="url(#id)"` 写法同样验证通过。

**结果**:新增 `test/animation/blur_pixel_test.dart`、`test/animation/text_pixel_test.dart`(后者确认 `<text>` 原实现已正确,不是 bug,只是补齐像素断言力度),`flutter test` 106/106 通过,无回归。详见 `docs/animation-engine-features.md` 的能力清单与像素验证表格。
