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

## 动画路径 `<clipPath>` 内容上的 `transform` 被静默忽略(2026-08-26,做几何缓存时发现)

在给动画路径加"几何 `ui.Path` 按节点缓存"这项性能优化时,顺手读 `_resolveClipPath` 的代码,发现这一行:

```dart
geometry.transform(_affineToMatrix4(accum));   // ← 返回值被丢弃
union.addPath(geometry, Offset.zero);
```

`dart:ui` 的 `Path.transform` 是**返回**一份变换后的副本、**不修改**接收者(官方文档原文:"Returns a copy of the path with all the segments of every sub-path transformed by the given matrix")。所以这里的返回值被丢弃,加进并集的仍是**未经变换**的原始几何——`<clipPath>` 内部元素自身的 `transform`(以及其上的 `<animateTransform>` 采样结果)全部被静默忽略,裁剪区域落在错误的位置。附带代价:每个裁剪节点每帧还白白分配了一整份 Path 副本。

**为什么一直没被发现**:`SvgNode.transform` 由 Rust 的 `parse_transform` 桥填入(`native_svg_values.dart`),而在纯 `flutter test` 环境下原生库加载不到、该函数按设计退化为返回 null。因此任何"从标记文本解析 + 断言像素"的测试里,`<clipPath>` 内容上的 `transform` 本来就是 null,走不到这个分支——**测试环境天然掩盖了这个 bug**。

**修复**:改用 `addPath` 自带的 `matrix4` 参数,在追加线段时就地应用变换,既正确又不产生中间副本:

```dart
union.addPath(geometry, Offset.zero, matrix4: _affineToMatrix4(accum));
```

**回归测试**:`test/animation/clip_mask_test.dart` 新增 "a transform inside a clipPath is applied to its geometry"。它**手工构造 `SvgNode` 树**并直接给 `transform: const [1, 0, 0, 1, 50, 0]`,绕开上面那个"测试环境里 transform 恒为 null"的陷阱——否则测试会因为错误的原因通过。用例让裁剪矩形覆盖左半边再右移 50 单位,断言存活的是**右**半边(x=75 处 alpha=255、x=25 处 alpha=0);修复前存活的是左半边。**已实测验证:把修复改回原写法,该测试确实失败**(`Expected: <255> Actual: <0>`),不是只在修复后跑通就收工。

**结果**:`flutter test` 119/119 通过,`flutter analyze` 0 issue。性能侧的记录见 `docs/performance-benchmarks.md` 的"Dart 侧性能优化专项(2026-08-26)"。

## 动画路径缺少 SVG 视口裁剪 → mask/blur 的 `saveLayer` 全屏化，真机 100 个动画图标即永久黑屏(2026-08-27)

**现象**：真机(华为 STG-AL00,Android 12,Impeller **GLES** 后端 —— 不是 Vulkan,实测 timeline 里出现的是 `SurfaceGLES::WrapOnScreenFBO`)上,`benchmark/bench_app` profile 模式跑 `LIB=bare`/`LIB=anim_fps` 的千图标动画网格,**永久黑屏、无任何崩溃/异常/报错日志**;`1.raster` 线程持续 ~100% CPU 超过两分钟,`dumpsys SurfaceFlinger` 的 `queued-frames=0`,屏幕截图恒为 16225 字节纯黑 PNG。100 项黑屏、10 项正常。看起来完全像 GPU 驱动死锁/活锁。

**排查手段**：`simpleperf` 在这台华为机上被内核挡死(`perf_event_open: Permission denied`,`security.perf_harden=0` 也无效),无 root 也用不了 `debuggerd`。真正拿到证据的是 **VM Service timeline**(`benchmark/bench_app/tool/capture_timeline.dart`)—— Flutter engine 的 C++ `TRACE_EVENT` 与 Dart timeline 共用同一个记录器,所以 raster 线程的原生调用区间是能抓到的。按 `Rasterizer::DoDraw` 切帧统计,黑屏状态下每一帧稳定是:

```
frame 0: dur=2530.2ms encodes=57 saveLayers=56
frame 1: dur=2443.3ms encodes=57 saveLayers=56
...(共 11 帧,每帧 2.2-2.5 秒)
```

**根因**(不是死锁,是一帧真的要画 2.4 秒)：`animated_svg_painter.dart` 的 `_paintNode` 为 `<mask>` 和 `feGaussianBlur` 开 `canvas.saveLayer(null, ...)`。bounds 传 `null` 意味着"无界",渲染器只能拿**当前裁剪区**来决定离屏渲染目标的尺寸;而 `CustomPaint` **不裁剪自己的画布**,动画路径此前也没有自己加裁剪 —— 于是裁剪区就是整个窗口(1080x2376)。399 个真实 line-md/eos 图标里有 65 个用 `<mask>`(16.3%),约 140 个可见格子里就有约 23 个带 mask,每个 mask 要开 2 个图层(目标层 + 覆盖度层)= 约 56 个 `saveLayer`,每个都分配一张**全屏**离屏纹理并跑一个全屏渲染通道:timeline 里对应 57 个 `RenderPassGLES::EncodeCommandsInReactor`,每个约 43ms,合计每帧约 2450ms。屏幕因此始终不更新、raster 线程 100% 忙 —— 所谓"黑屏卡死"只是"一帧要 2.4 秒"。

**为什么静态路径没这个问题**：`rust_static_svg.dart` 一直是对的 —— 它 `canvas.clipRect(maskRect)` 之后再 `canvas.saveLayer(maskRect, Paint())`,bounds 是显式的。这是两条路径之间一个纯粹的疏漏性不对称。

**为什么之前一直没暴露**：`flutter test` 用 `TestWidgetsFlutterBinding`,离屏图层大小不影响任何断言,像素测试全过;`LIB=compare` 在真机上"能跑"是因为它的动画阶段可见格子更少、成本还没越过肉眼可察的临界点(实测 ~7 FPS)。

**修复**(`lib/src/animation/animated_svg_painter.dart` 的 `paint()`)：绘制任何内容之前先裁剪到 SVG 视口:

```dart
canvas.clipRect(Rect.fromLTWH(0, 0, intrinsicSize.width, intrinsicSize.height));
```

这一行同时解决两件事:(1) **正确性** —— 按 SVG 规范最外层 `<svg>` 的 `overflow` 默认为 hidden,超出 viewBox 的内容不该绘制,静态(usvg)路径本来就是这个行为;(2) **性能** —— 无界 `saveLayer` 的覆盖范围从整个窗口塌缩到图标盒子(32x32 逻辑像素)。

**真机实测(同一台 STG-AL00,每次都 force-stop + uninstall 干净重装)**：

| 场景 | 修复前 | 修复后 |
|---|---|---|
| `LIB=bare ITEMS=1000` 冷启动截图 | 16225 字节纯黑,永不变化 | 124150 字节,整屏图标正常渲染 |
| 每帧 raster 耗时(timeline 按 `Rasterizer::DoDraw` 切帧) | ~2450ms/帧 | raster avg 23.3ms / p90 32.0ms |
| `1.raster` 线程 CPU(动画播完后) | 100%,持续 2 分钟以上 | 空闲(`top -H` 里 0 running) |
| `LIB=anim_fps ITEMS=1000`(6 轮滚动) | **从来跑不完,永久黑屏,一次报告都没产出过** | `frames=226 real_fps=20.79`,build avg 35.4ms(滚动时 GridView 挂载churn 主导),raster avg 23.3ms,rss_peak 207MB |

**结果**：`flutter test` 147/147 通过,`dart analyze` 无新增 issue。

**顺带清理**：本轮排查期间加的一次性诊断开关全部移除 —— `DASH_NO_AA`(`animated_svg_painter.dart`)、`STRIP_DASHARRAY`/`USE_SPINNER`(`anim_icon_gen.dart`)、`WARM_FIRST`/`SKIP_PROBE`(`anim_fps_bench_screen.dart`)。`benchmark/bench_app/lib/bare_anim_grid.dart`(`LIB=bare`)保留为这个 bug 的最小回归用例。

**被否决的方向,记录在案**：中途试过"渐进挂载/首帧热身"(分 20 帧把已构建条目数爬升到满额)。真机实测**仍然黑屏**,而且方向本身是错的 —— 它只是把并发压力往后摊,没有降低单帧成本。用户明确否决:"如果连 35 个图标都无法并发,那就是不可用状态。"
