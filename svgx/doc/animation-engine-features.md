# 渲染引擎能力清单(静态路径 + 动画路径)

> 从 `CLAUDE.md` 拆出。这是**当前能力边界**的权威参考——支持什么、明确不支持什么、已知限制是什么。本文件只保留**最终状态**;早期中间态的能力清单(比如"第二轮扩展"时的支持范围)已被后续更新取代,不再赘述,仅在下方"历史沿革"一节留一句话背景。

## 静态路径(Rust usvg → 显示列表 → `ui.Picture`)

支持:`<svg>`/`<g>`/基础形状/`<use>`/`<switch>`/`<marker>`(usvg 解析期即展开或求值,svgx 零成本继承)、`currentColor`+`PaintOrder`(`parse_svg(data, currentColor)`,`SvgPath.strokeFirst` 控制先描边后填充)、静态渐变(线性/径向,`objectBoundingBox`/`userSpaceOnUse`)、`<clipPath>`、`<mask>`、`<pattern>`(基础形态)、`feGaussianBlur`(仅此一种 filter 图元)、`<image>`(内嵌 base64 位图,PNG/JPEG/GIF/WEBP)。

**不支持 / 已牺牲**:

- **`<text>` 完全不渲染**(2026-08-26,体积优先的刻意取舍):`usvg` 依赖改为 `default-features = false` 关闭了 `text`/`system-fonts`/`memmap-fonts`,静态路径的 `<text>` 元素被静默跳过,不产生任何路径几何,不报错。换来 release DLL 体积从 1.052MiB 降到 0.468MiB(−55.5%)。详细调研过程见 `docs/size-optimization-history.md`。动画路径的 `<text>`(独立 `TextPainter` 实现)不受影响。
- **filter 只做 `feGaussianBlur`**:`feColorMatrix`/`feComposite`/`feOffset`/`feBlend`/`feDropShadow`/光照类图元等全部列为后续工作,当前一律不生效(不是画错,是不画)。多图元滤镜链同样整体忽略。
- **mask/blur 是"最近祖先优先",不支持嵌套叠加**:真要嵌套需要完整的图层树,而扁平显示列表刻意不做这层结构。多层祖先都声明 mask/filter 时只有最内层生效。clip **不受此限**——多个祖先的裁剪会正确求交集。
- **clip 内部的形状按并集处理**,实现方式是把一个 `<clipPath>` 的所有子形状塞进同一条 `ui.Path`。重叠 + 反向绕向的极端情况下,非零环绕规则的结果与真正的布尔并集可能不同。
- **`<clipPath>` 内部元素自身再带 `clip-path` 会被忽略**(clipPath 的 `clip-path` 属性本身是支持的,走 `build_clips` 递归)。
- **遮罩矩形在有旋转时取的是变换后 4 角的轴对齐包围盒**,不是真正的旋转矩形。
- **遮罩内容 / 图案贴片内容按"朴素"方式绘制**:不再递归应用它们内部的 clip/mask/blur/pattern。也不支持遮罩内的 `<image>`。
- **`<pattern>` 贴片分辨率上限 1024px/轴**,按图案→绝对矩阵的缩放量推算;极端放大时会糊。贴片 `ui.Image` 由 shader 持有,不显式 dispose(交给 Dart GC)。
- **不支持嵌套 SVG**(`<image href="...svg">` 或 `ImageKind::SVG`)——静态路径直接跳过。
- **图片 z-order 简化**:图片一律先于路径/形状绘制,不支持"图片和路径交替出现在文档顺序中、按顺序层叠"这种排布。
- **`<image href>` 只解析内嵌 `data:` URI**:本地路径、UNC 路径、`file://` 一律不读取(安全策略,防止不可信 SVG 读本地文件);`data:image/svg+xml` 同样跳过。累计解码图片超过 **64 MiB** 预算后,后续图片被**静默丢弃**(不报错,与"嵌套 SVG 跳过"同一类行为)。
- **输入与复杂度上限(畸形/恶意 SVG 防护,超限返回错误而不是崩溃)**:源串 ≤ 32 MiB;元素嵌套与 `url(#id)` 引用链有深度上限(嵌套 128 层、引用链 64 层,按 1 MiB 线程栈估算);clip/mask 展开到每条 path 后的累计点数 ≤ 4,000,000、路径数 ≤ 100,000。含实体声明且实体值内有标记的 SVG 会被拒绝(防实体展开栈溢出)。正常图标/插画远低于这些上限。
- **已知限制**:`<style>` CSS 规则里的 `url()` 引用链、`<use>` 链、marker、feImage 的超深链(数百层)仍可能在小栈线程上栈溢出(usvg 内部递归;HEAD 同样存在),属后续工作。可用大栈线程兜底,但有每次解析的线程开销,暂不做。

## 动画路径(原创 SMIL 引擎,`lib/src/animation/`)

**元素**:`<svg>`/`<g>`(含 `transform`)/`<path>`/`<circle>`/`<rect>`(含 `rx`/`ry`)/`<ellipse>`/`<line>`/`<polyline>`/`<polygon>`/`<use>`/`<text>`/`<image>`/`<linearGradient>`/`<radialGradient>`/`<clipPath>`/`<mask>`。

**SMIL 动画**:

- 时钟值支持 `HH:MM:SS(.fff)`、`MM:SS`、`Nh`、`Nmin`、`Ns`、`Nms` 和纯数字(秒);所有使用 `parseSmilDuration` 的时序字段共用此解析。非法值沿用零回退;有限时长超过 1e7 秒时饱和至 1e7 秒,正向 `begin` 超限则永不开始。`NaN`/`Infinity` 仍按非法值处理。

- `<animate>`:`values`/`from-to`、`dur`、`begin`(数值偏移 **与 syncbase**;不支持分号列表)、`fill="freeze"` vs 复原、`repeatCount`(有限/`indefinite`)、`calcMode`(`linear`/`discrete`/`paced`/`spline`)、`keyTimes`、`keySplines`;任意单数值展示属性动画(通用,不限于 `stroke-dashoffset`)。`fill-opacity`/`stroke-opacity` 已是真正生效的展示属性(见下一条)。
- `fill-opacity`/`stroke-opacity`(静态属性与 `<animate>`/`<set>` 驱动均支持):**继承属性**(与不继承的 `opacity` 不同),取值钳制到 `[0, 1]`;最终 alpha = 颜色自身 alpha × `fill-opacity`(描边为 `stroke-opacity`)× `opacity`;纯色、渐变着色器、`<text>` 填充都生效。`opacity` 是**本节点自身的不透明度,不继承**;祖先与子节点在合成时相乘(两层 `.5` 得 `.25`)。半透明 `<g>`、根 `<svg>`、展开后的 `<use>` 包装节点先用 `saveLayer` 合成整个子树,重叠子元素不会额外加深。叶子只画 fill 或 stroke 时把自身 opacity 乘进 Paint/渐变 alpha;同时有 fill 与 stroke 时先合成二者再应用 opacity。效果顺序统一为 filter → clip → mask → opacity,SMIL/CSS opacity 动画同样适用。当前帧采样 opacity 为 0 时，在任何节点级 save/saveLayer 前跳过整棵子树；后续非零帧恢复绘制。无 mask 隔层的 blur 将 opacity 合入模糊层 Paint；opacity 下推需同时满足：包装组自身无 blur/clip/mask，且其唯一子节点是单笔几何叶子（非 `<text>`/`<image>`、非组、自身无 blur/clip/mask）；满足时包装组的 opacity 与叶子自身 opacity 相乘后下推给叶子，避免开层（自重叠 stroke 下推后统一 alpha 的行为只在 Skia 上验证过，Impeller 真机未验证）。带自身 transform 的节点现在在 transform 后开启 mask/blur 图层：blur sigma 随节点自身 transform 缩放（更符合 SVG 规范），clip 裁剪模糊后的结果，与无自身 transform 的节点统一；此前带自身 transform 时是先 clip 再模糊。规范见 [SVG 1.1 §14.5](https://www.w3.org/TR/SVG11/masking.html#ObjectAndGroupOpacityProperties),回归见 `test/animation/group_opacity_test.dart`。
- `<animate attributeName="d">`(路径变形):各关键帧的 `d` 在**解析期**规范化为绝对 `M`/`L`/`C`/`Q`/`A`/`Z`(相对坐标转绝对、`H`/`V`→`L`、`S`→`C`、`T`→`Q`),命令序列与参数个数完全一致时逐参数插值,逐帧直接用数值构建 `ui.Path`(不再解析字符串);不一致则退化为**离散**(按规范,`n` 个值把时长等分为 `n` 段切换)。支持 `values`/`from-to`、`keyTimes`、`calcMode`(`linear`/`discrete`/`spline`+`keySplines`;`paced` 对路径无定义,按 `linear` 处理)、`begin`(偏移与 syncbase)、`dur`、`repeatCount`、`fill="freeze"`,计时与数值动画共用同一套设施(`SmilTimed`/`_resolveTiming`/`_locateSegment`)。
- `<set>`:单值离散动画。`begin` 之前不覆盖(显示静态属性);**无 `dur` = 活动期无限**,从 `begin` 起一直保持;有 `dur` 且无 `fill="freeze"` 时结束后撤销覆盖。数值属性(`opacity`/`fill-opacity` 等,`to` 必须是纯数字)复用数值通道,`d` 复用路径通道;无 `dur` 的 `<set>` 忽略 `repeatCount`,其结束时刻按 `begin` 计,不会让 Ticker 一直跑。
- `<animateTransform>`:`type="translate"/"scale"/"rotate"/"skewX"/"skewY"`(`rotate` 支持 `angle`/`angle cx cy`),同一元素多个按文档顺序合成,叠加在静态 `<g transform>` 之上。
- `<animateMotion>`:自身 `path="..."` 与 `<mpath href="#id">`;弧长参数化用 `dart:ui` 的 `Path.computeMetrics()`+`getTangentForOffset()`(129 个等弧长采样点,逐帧线性插值);`rotate="auto"`/`"auto-reverse"`/固定角度;`keyPoints`/`keyTimes`/`keySplines`/`calcMode`(无 `keyPoints` 时行为等价默认 `paced`,有 `keyPoints` 但未指定 `calcMode` 时默认 `linear`,是与 SVG 规范默认值不同的已知简化)。
- `<use href>`/`xlink:href`:解析阶段从源 XML 重新解析目标(SVG2"影子树"读法,含目标自身动画),前向引用/环检测均支持(`_maxUseDepth = 10` 兜底)。
- syncbase `begin`(`id.begin`/`id.end` ± 偏移):三色 DFS 解析绝对时间,支持任意长依赖链、前向引用;成环 → 该动画 `begin` 置为 `kSmilNeverBegins`(永不触发);引用不存在的 id → 回退纯偏移;引用 `repeatCount="indefinite"` 动画的 `end` → 同样失效。
- 具名 CSS 颜色、`rgb()`/`hsl()`:靠 Rust 侧 `svgtypes` 一次性归一化为 hex(仅解析阶段调用,逐帧仍是纯 Dart 数值插值)。
- 动画渐变:`<stop>` 的 `stop-color`/`stop-opacity`、渐变自身 `x1/y1/x2/y2/cx/cy/r/fx/fy` 均可被 `<animate>` 驱动,每帧重采样重建 shader(无假设静止的缓存)。
- 动画 `<clipPath>`/`<mask>`:裁剪路径/遮罩内容按当前帧采样(不是只按静止态生效一次)。
- **CSS 动画(SVGator CSS 导出 + 通用子集,2026-11-03 起播放)**:检测器识别 `@keyframes`(含 `-webkit-`/`-moz-`/`-o-`/`-ms-` 前缀,只有 `@keyframes` 无引用也走动画路径,属保守误判),解析期把 `@keyframes` 编译进现有时间线,不新增运行期通道。
  - 层叠:`<style>`(`#id`、class、标签、后代、子代、属性选择器、`*`、`!important`)与 `style=""`,按特异性与顺序层叠覆盖属性表。
  - `animation` 简写与长写:`duration`/`delay`/`iteration-count`(含 `infinite`)/`fill-mode`/`direction`(`normal`/`reverse`/`alternate`/`alternate-reverse`)/`timing-function`;逐关键帧 `animation-timing-function`(`cubic-bezier`/`steps`/关键字),缺省取 `animation` 级缓动;缺端点按元素静态值补齐。
  - 数值属性(`opacity`、`stroke-width`、`stroke-dashoffset` 等)、`transform` 列表(`translate`/`rotate`/`scale`/`skew`,按"第 k 个函数各自插值"编译为按序叠加的变换动画;CSS `transform` 生效期间**替换**静态 `transform` 属性,未生效时用静态值)、`offset-path: path()` + `offset-distance`/`offset-rotate`(自适应等弧长采样 128~2048 段)、`d: path()` 变形(命令不兼容时退化为离散并记为近似)、`fill`/`stroke`/`stop-color` 颜色(含与 `none` 之间的切换,按进度 ≥0.5 翻转)、`stroke-dasharray` 列表(各帧补齐到公倍长度,上限 32)。
  - `alternate`/`reverse` 在全部通道(数值、变换、运动、颜色、路径、列表)按时间反转实现;`steps()` 缓动在各通道一致。
  - 带颜色动画的节点位于 `<mask>` 内时自动走精确管线;`<mask>` 内的 `transform` 动画经 M2 验证有效。
- **补齐的渲染保真度(2026-11-03,由浏览器逐帧比对发现)**:`fill-rule`/`clip-rule`(`evenodd`,含继承、`style`/`<style>` 来源,混用规则的 clipPath 经 `Path.combine`)、`<mask mask-type="alpha">`(精确与近似两条管线都按 alpha 判定)、`feGaussianBlur stdDeviation` 双值(`"x y"`,取平均近似,非均匀模糊未实现)、紧凑圆弧标志位(`a1 1 0 011 1` 写法)、`opacity` 钳制到 `[0, 1]`、`display="none"` 整棵子树不绘制、`clip-path`/`mask` 随节点自身 `transform` 生效(此前落在父坐标系)、根 `<svg>` 的 `background-color`/`background` 纯色背景(含 `style=""` 与 `<style>` 规则来源)铺满整个绘制区域(与浏览器一致;只认十六进制、`rgb()`、`transparent`)。
- `<text>`:`TextPainter` 渲染,支持 `x`/`y`(基线锚点)/`font-size`/`font-family`/`text-anchor`,`fill`/`opacity` 走通用动画机制;不支持 `<tspan>`/textPath,文字内容本身不可被动画驱动。
- `<image>`:`resolvedImage` 异步解码 `data:` URI(base64),ticker 等解码完成后才启动,避免动画偷跑进度。
- `feGaussianBlur`(通过 `filter="blur(Npx)"` 或 `filter="url(#id)"` 指向单个 `<feGaussianBlur>`(in 为空或 SourceGraphic) 或下述透明 Figma 前缀的 filter):`canvas.saveLayer` + `ui.ImageFilter.blur` 包裹节点子树。

**驱动方式**:原始 `Ticker`(非绑定 `[0,1]` 的 `AnimationController`)——文档含 `repeatCount="indefinite"` 时永久 ticking,否则在所有动画的 `begin + dur * repeatCount` 都结束后自动停止,不白白消耗帧(无 `dur` 的 `<set>` 在 `begin` 之后值即恒定,按 `begin` 计结束)。

**明确不支持**:

- **luminance mask 已知限制**：忽略遮罩内容自身的 alpha（opacity/fill-opacity 不生效，例如 mask 内 opacity=.5 的叶子或组按 255 处理，浏览器应为 128）；alpha mask 正常。该问题与组 opacity 改动无关，为原有限制。现状用例为 `group_opacity_test.dart` 的 `knownLimitation` 测试；`css_animation_pixel_test.dart` 原有 255 断言保持不动。
- CSS 动画的边界:`transition-*` 不支持(243 个 SVGator 样本里 0 次);`@media`、`@import` 整块忽略;`calc()` 声明直接忽略,保留前面的有效 CSS 值;带逗号回退的 `var(--x, fallback)` 也保留前值,不解析自定义属性、不套用 fallback。无回退 `var()`、`env()` 及 `inherit`/`initial`/`unset`/`revert`/`revert-layer` 仍清除同属性已累计的 CSS 值,随后回落到元素表现属性(未写表现属性时再按继承/默认值处理);SVGator **JS 导出**不支持(闭源播放器、无公开规范,见 `doc/svgator-positioning.md`)。
- CSS 动画的已知限制:`d` 动画的缓动 y 值过冲时被钳制在 `[0, 1]`;`offset-path` 与 `transform` 同时存在时的合成顺序未与浏览器逐项核对;嵌入 `@font-face` 的文字不渲染对应字体(回退到系统字体)。
- `begin` 分号列表(如 `0;a.end`、`0;2s`)明确不支持,不取第一项、不实现多次触发;整个值回退到零偏移,表现为立即开始。
- CSS `currentColor` 关键帧与需要该静态值补端点的颜色动画:当前颜色时间线只保存字面 ARGB,无法逐帧按主题解析,因此整条颜色通道跳过并返回 `currentColorRuntimeUnsupported` 诊断。静态 `currentColor`(含大小写变体)仍在运行时按 theme 解析;具名颜色、`hsl()` 关键帧复用原生颜色归一化钩子,无 DLL 时按已有颜色解析可用性降级。
- CSS 正延迟配合 `backwards`/`both`:SMIL 时间线仅有 remove/freeze,延迟期仍显示静态值,返回 `backwardsFillUnsupported` **近似**诊断;开始后的动画和 `both` 的结束定格正常。
- 同一元素的多个 transform 动画按列表顺序覆盖:仅 `unknownKeyframes`、`noValidValue`、`zeroDurationWithoutForwards`、`iterationCountZero` 允许回落到早先轨道。`paused`、签名不一致、矩阵函数、全 none 及不支持的 origin/box 仍压掉早先轨道,只返回相应诊断(暂停帧尚未编译)。已知偏差(边角情形):`animation-iteration-count: 0` 且 `fill-mode` 为 `forwards`/`both` 时,浏览器定格在 0% 关键帧并压掉前面轨道,当前实现仍回落到前面的轨道。
- `transform-origin` 支持两个 px/无单位长度(`10px 20px`),通过 `translate(origin) … translate(-origin)` 包裹变换列表;百分比、关键字、其他形式、关键帧内的 origin/box 变化及显式 `transform-box` 暂不处理,对应 transform 通道跳过并返回 `transformOriginUnsupported`,不静默忽略。`transform-box` 涉及坐标空间,百分比需元素 bbox,不在本批实现。
- filter 支持单个 `feGaussianBlur`(输入为空或 `SourceGraphic`),以及恰为 `feFlood`(flood-opacity=0 或颜色 alpha=0) + `feBlend`(mode=normal、in=SourceGraphic,显式 in2 须指向该 flood) + `feGaussianBlur`(in 为空或前一图元的 result) 的 Figma 本体模糊。其它多图元链、其他输入和投影链(`feOffset` + `feGaussianBlur` + `feMerge`)整体忽略,不再错误渲染为本体模糊。CSS `blur(Npx)` 仅接受单独一个 blur。
- 解析时重复 id 一律取文档中首个元素(包含 `<use>` 引用、渐变、clipPath、mask);渐变 `href`/`xlink:href` 均按 local name 继承。渐变色标保持文档顺序,offset 逐项按 `max(prev, offset)` 钳制,无效色标与对应动画节点同步跳过;径向渐变 `r<=0` 使用最后色标的纯色。
- `stroke-dasharray` 接受逐词元 px 单位;任一负数、百分比或非法词元使整个列表退化为 none。描边宽度/偏移支持 px。虚线预估划线与间隙合计段数超过 5000(约 2500 段实际划线)、全零或总和非正时退化实线;零长度 dash 配合 round cap 的圆点仍未实现。
- `<use>` 展开有全局 100000 单位预算(含包装节点),与原有深度/环检测共同生效;预估与展开均按 `_attributesOf` 的 local-name 后写覆盖规则读取 href/id。动画子元素、不支持的子元素及无法解析目标的 use 各计额外遍历单位,与实例化节点合计检查同一上限;额外单位单独累计,保留正常文档的 SvgNode 数量及既有节点统计。展开前饱和估算整个实例,剩余预算不足时整实例跳过,不会画出半个 symbol,后续较小实例仍可使用剩余额度。`SvgDocument.useExpansionTruncated` 仅为内部标识,未从 `lib/svgx.dart` 导出为公共 API;指数引用、动画及悬空引用放大回归要求解析在 2 秒内完成。
- 事件类 `begin`(`begin="click"`/`"id.click"`)——已评估,不做:需要"事件监听 + 时间线动态重触发",与当前"一次性建好全时间线、之后纯按 elapsed 驱动"的架构相冲突,属于架构级改动,建议单独排期。当前行为:解析为零偏移(立即开始)。
- `<tspan>`、textPath。
- `<set>` 只支持数值属性与 `d`:`to` 为非数字(如 `visibility="hidden"`、`fill="red"`、带单位的 `"2px"`)的 `<set>` 解析期丢弃。`<animate>` 驱动 `fill`/`stroke` 颜色同样仍是缺口。
- 路径变形的已知限制:各帧命令序列/参数个数不同,或圆弧的 large/sweep 标志位不同,退化为离散(不做点重采样、不做子路径对齐);`keySplines` 的 y 值超出 `[0, 1]`(过冲)时进度被钳制在 `[0, 1]`;不支持 `by`/`additive`/`accumulate`;`fill-opacity`/`stroke-opacity` 不支持百分比写法。
- 动画渐变以外的"作用在渐变属性/`<stop>` 上无效"仅限 `<animate>`;OKLCH 等感知色彩空间插值不支持,只做逐字节 ARGB 插值。
- `<use>` 指向 `<symbol>`/`<svg>` 时,不应用其 `width`/`height`/`viewBox` 缩放(按普通 `<g>` 处理);`<use>` 自身的 `width`/`height` 同样忽略。
- 不支持嵌套 mask/clip(嵌套内容里的 `clip-path`/`mask` 属性被忽略);mask 内容里的 `<image>` 不支持。
- mask 未读取 SVG 的 `maskUnits`/`x`/`y`/`width`/`height`(即不按官方默认的 bbox ±10%/120% 去**裁剪** mask 区域;mask 内容画到哪里就覆盖到哪里)。曾有过一项"按 mask 内容自身几何边界分配离屏图层"的无损优化(`tightMaskLayerBounds`),已评估并否决(收益不足),见下方一条。
- **高并发下的故意有损降级**(`SvgxAnimationQuality`,阈值 24 个并发动画图标以内一律不生效):(1) 逐图标降采样,**默认开启**——超过阈值后普通图标按 30Hz、带 `mask`/模糊的文档按 20Hz 推进时间线,像素不变、只是时间采样点变少;(2) 内容为纯不透明黑/白填充的 `<mask>` 改用等价 `clipPath` 绘制,**默认关闭、需手动开启**(真机实测它把 raster 换成了 build、净 real_fps −2.4%,详见 `docs/performance-benchmarks.md`),代价是 mask 边界的边缘抗锯齿略有差异(带描边/任何不透明度/非二值或渐变填充/文本/嵌套 clip-mask-模糊 的 mask 一律保持精确管线;同时带 mask 与 blur 的节点也保持精确管线,因为裁剪会把管线重排成 `Blur(Mask())`)。两项均可用 `SvgxAnimationQuality.exact` 全局或逐控件关闭(第 2 项另需显式 `approximateSimpleMasksAsClip: true` 才会启用),完整说明与实测归因见 `docs/performance-benchmarks.md`。**已评估并否决**:更进一步把合格 mask 与纯色内容几何求交(`Path.combine`)、连 `clipPath` 都省掉的方案(曾短暂加入为 `approximateSimpleMasksAsPathIntersect`)已实测——raster 确实比方案(2)更省,但 build 端开销更贵,仍打不过"只跳帧"的默认方案,代码已撤销,详细数据见 `docs/performance-benchmarks.md`「2026-08-27 三轮」一节。**同样已评估并否决**:把一帧内多个不重叠的带 mask 图标合并进一对共享离屏图层(把每帧约 46 次 `saveLayer` 砍到 2 次)——数学等价性实测成立(不重叠时逐位一致),但本仓库自己的真机数据显示离屏通道开销是**面积主导**(图标尺寸通道约 221µs vs 窗口尺寸通道约 43ms),合并后图层面积≈整个视口,净开销反而差一个数量级;此外它还会作废跳帧默认值、丢掉中间图层效果。详见「2026-08-27 四轮」一节。
- **`tightMaskLayerBounds`——已评估并否决(收益不足)**:曾实现过让 `<mask>` 的两个 `saveLayer` 按 mask 内容自身边界分配,而不是留成无界(=按整个 SVG 视口分配),像素等价(真实语料 488 次全帧比对逐位一致)、真实语料离屏面积平均少 21.5%,代价 +4.1~5.5µs/图标/帧(主机侧)。但两台真机(vivo V2283A、华为 STG-AL00 消除臂序偏置后)验证 real_fps 均无实质提升(只有 vivo 上 raster 平均值有小幅噪声量级改善,从未传导到 fps),判定为不通用/收益不足,代码已撤销。成本模型分析、合并方案否决推导等底层调研成果依然保留供参考,详见 `docs/performance-benchmarks.md`。

## 像素级验证结果(12 项已实现功能的真实像素验证)

**验证方式**:主要复用仓库既有的 `test/` 套件(`flutter test`)+ `rust/` 侧 `cargo test`,核查其中标注 "pixel-level" 的用例确实是 `toByteData` 采样 + 对具体像素 alpha/RGB 通道做 `expect` 断言,不是只测 DOM 结构。

| # | 功能 | 静态路径证据 | 动画路径证据 | 结论 |
|---|---|---|---|---|
| 1 | `<image>` base64 位图 | `rust_image_smoke_test.dart` | `image_smoke_test.dart`(11 例,含真实 base64 解码为 `ui.Image`) | 通过 |
| 2 | 具名 CSS 颜色 | Rust 单测 | `transform_and_color_test.dart` | 通过 |
| 3 | `<g transform>` + skewX/skewY | Rust 单测 | `transform_and_color_test.dart` + painter skew 矩阵分支 | 通过 |
| 4 | `<use>`(含引用目标自身动画) | — | `use_element_test.dart`(13 例) | 通过 |
| 5 | syncbase `begin` | — | `syncbase_begin_test.dart`(事件类 `begin` 仍标注为已知差距) | 通过 |
| 6 | `<animateMotion>` | — | `animate_motion_test.dart`(13 例) | 通过 |
| 7 | 静态+动画渐变 | `rust_gradient_smoke_test.dart` | `gradient_test.dart` | 通过 |
| 8 | `<clipPath>` | alpha 断言(内>200/外<16) | 同 + 动画帧采样验证 | 通过 |
| 9 | `<mask>` | 白色/未覆盖区断言 | 同 + 全黑遮罩隐藏 + 动画帧采样 | 通过 |
| 10 | `<pattern>` | tile 重复位置断言 | 未列入原始任务范围(仅要求静态) | 通过 |
| 11 | `feGaussianBlur` | 核心/边缘/远处 alpha 梯度断言 | 见下方"发现并修复"记录 | 通过 |
| 12 | `<text>` | 静默跳过(体积取舍) | 逐字形像素断言(24 采样点精确纯红) | 通过 |

**发现并修复的真实 bug(动画路径 `feGaussianBlur`)**:核查前 `lib/src/animation/svg_dom.dart`/`svg_document_parser.dart`/`animated_svg_painter.dart` 完全没有 `filter`/`feGaussianBlur` 相关代码——动画路径与静态路径是两条独立渲染管线,`filter` 属性此前在动画路径里被直接丢弃。修复:`SvgNode` 新增 `blurSigma`,`_parseBlurSigma` 识别 `filter="blur(Npx)"` 与 `filter="url(#id)"` 指向单个 `feGaussianBlur`,`animated_svg_painter.dart` 用 `saveLayer`+`ImageFilter.blur` 包裹节点子树。采样验证:无模糊时 255→0 硬跳变(1 像素内完成);`blur(8px)` 时横跨约 30 像素的渐变衰减,且原始几何边缘之外仍有渗出(bleed)。详见 `docs/bugfix-history.md`。

**汇总**:`flutter test` 119/119 通过,`flutter analyze` 0 issue,`cargo test`(`rust/`)24/24 通过。(109 → 119 是 2026-08-26 的 Dart 侧性能优化专项新增的 10 个用例:`SvgxDocumentCache` 5 例、动画组件不逐帧重建 2 例、`AnimationDetector` 合并正则的标签边界 2 例、`<clipPath>` 内 `transform` 回归 1 例;详见 `docs/performance-benchmarks.md` 与 `docs/bugfix-history.md`。)

## 历史沿革(早期能力清单已被取代,不再展开)

- **第二轮扩展**(2026-08-25)记录过一份"当前支持"清单(基础形状 + `<animate>`/`<animateTransform>` 的 `values`/`repeatCount`/`calcMode`/`keyTimes`/`keySplines` 等),已被"第三轮扩展"完全覆盖并取代,不再单独罗列。
- **第三轮扩展**(2026-08-25)一次性补齐了具名颜色、静态 `<g transform>`、`skewX`/`skewY`、`<use>`、syncbase `begin`、`<animateMotion>`、静态渐变共 7 项,并把 `parse_color`/`parse_transform` 值解析下沉到 Rust(`rust/src/api/svg.rs` 新增两个 `#[frb(sync)]` 函数,依赖 `svgtypes` crate,MIT/Apache-2.0,与 usvg 共用同一份 `0.15.3`)。这份清单已被本文件"动画路径"一节的最终状态完全吸收。
- **`<image>` 支持**:最初是已确认的功能缺口(静态/动画路径均不支持,usvg 能解析但显示列表模型没留位图字段),随后按设计补齐——静态路径 `SvgScene` 新增 `images: Vec<SvgImage>` 字段(与 `paths` 并列),动画路径新增 `SvgNodeKind.image`/`resolvedImage`,详见本文件"静态路径"/"动画路径"两节的最终状态描述。
- **静态路径 clipPath/mask/pattern/feGaussianBlur/text 补齐**(2026-08-25):`<marker>`/`<switch>` 实验证实 usvg 解析期已零成本处理,其余 5 项(clipPath/mask/pattern/filter MVP/`<text>`)逐项实现,`<text>` 随后又在体积优化中被撤回(见上方"静态路径"一节)。关键实现决定:
  - **坐标空间**:clipPath/mask/pattern 的内容在 usvg 里是"子根"(subroot),其 `abs_transform()` 相对各自的根,不含引用元素的祖先变换。统一做法是 `base.pre_concat(node.abs_transform())`,`base` 取引用元素分组的 `abs_transform()`。
  - **`patternUnits` 不用自己处理**:usvg 在树公开前已归一到 userSpaceOnUse。
  - **`Inherited` 累加器必须标 `#[frb(ignore)]`**:FRB 2.12 会扫到 api 模块里的私有 struct 并给它生成 codec(然后因字段私有编译失败),已修。
  - **亮度系数**:`0.2125/0.7154/0.0721`(SVG 1.1 `feColorMatrix type="luminanceToAlpha"` 常量)。矩阵排布与 `dstIn`+`ColorFilter.matrix` 的手法改编自 F(`full_svg_flutter`,MIT)的 `animated_svg_painter_mask_luminance.dart::_createLuminanceMaskPaint`,已按硬规则署名来源(F 用 sRGB 系数 0.2126/0.7152/0.0722,差异小于 1 个 8 位色阶)。
- **动画引擎四项功能扩展**(2026-08-25,`lib/src/animation/` 范围内):`<clipPath>`/`<mask>`(像素级验证 8 例)、`<text>`(8 例)、`<animateMotion>` keyPoints/keyTimes/calcMode(4 例)、动画渐变(6 例)。每项独立验证零回归后进入下一项,均在 `example/lib/main.dart` 新增可视化 demo。最终 `flutter test` 101/101、`cargo test` 24/24、`flutter analyze` 0 issue。触及文件:`lib/src/animation/{svg_dom,svg_document_parser,smil_animation,animated_svg_painter,animated_svg_widget,svg_gradient}.dart` 及对应测试。


### Dart 加载与 Widget 生命周期

- `Svgx` 按源串缓存 SMIL/CSS 动画检测结果；动画与静态路径均应用 `colorFilter`，动画未设置滤镜时不添加包装层。
- 网络源按 URL 与排序后的 headers 比较，文件源按路径比较；替换加载期间继续显示上次成功内容。源缓存区分 asset/bundle、file、network 与请求头，并合并同键在途请求。网络连接和响应头等待各有 30 秒超时。
- `SvgxTheme` 按全部字段值比较，避免相同主题触发图片缓存失效和多余重绘。
- ImageProvider 异常经 completer 上报；动画帧不重入，监听者离开或销毁后的在途结果被释放。4096 像素上限按比例整体缩放，并校正逻辑尺寸对应的 scale。
- 静态图片逐张解码，坏图跳过，录制失败也释放已解码图片。Picture 淘汰仅移除缓存引用，不 dispose 仍可能被使用的 Picture。
- 静态冷加载按帧计时，异常工作也计入预算；排队按源与颜色去重，执行前跳过已卸载的调用方。
- 动画文档缓存保留随机淘汰策略，运行时缩小上限会持续淘汰至满足限制；含图片的文档不共享。本 State 独占的解码图片在换源、卸载及过期解码完成时释放，解码失败仍展示文档并启动时钟。
- `playbackRate` 运行中切换会累计已播放的虚拟时间并重设基线，时间线保持连续。替换文本布局缓存时释放旧 `TextPainter`。
