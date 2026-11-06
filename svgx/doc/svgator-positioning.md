# SVGator 定位评估与决策

> 2026-11-03 评估并拍板。状态:**决策已定(方案 A),渲染层 R1/R2 待 spike,三处现存缺口已修复(见第 4 节)**。这份文档推翻了 `CLAUDE.md` 里原先的两条结论("CSS 动画:不做"和"不追加 CSS 相关投入"),`CLAUDE.md` 已同步改写。

## 1. 决策

- **采用方案 A**:只承诺"SMIL + SVGator CSS 导出 + 通用 CSS 动画子集"。
- **不支持 SVGator 的 JS 导出**(定论,理由见第 2 节)。
- **渲染层怎么补(R1 还是 R2)**:等 spike 出结果再定,见第 7 节。

一句话结论:**能做一半,做不到"通用"**。CSS 导出能做,而且和现有架构契合;JS 导出里最出彩的东西(路径变形、曲线运动、交互触发、播放 API)走的是私有格式加闭源播放器,不碰。

## 2. 为什么只能做一半

### 2.1 CSS 导出能做,且和现有架构契合

- 做法:在**解析期**把 `<style>` 里的 `@keyframes` 编译进现有的时间线模型。逐帧引擎、FFI 边界、按资产分流都不用推翻。
- F(`full_svg_flutter`)的 `css_to_smil_converter` 走的就是这条路,代码约 2100 行,可作覆盖面参考(取思路,需要抄代码时遵守 `CLAUDE.md` 的"硬规则"一节)。
- **工作量的大头不在 CSS 语法,而在把动画路径的渲染能力从"图标级"补到"插画级"**(见第 5 节表 B)。

### 2.2 JS 导出不做

SVGator 最出彩的能力都在 JS 导出里。188 个 JS 样本中:

| 能力 | 样本数 | 占比 |
|---|---|---|
| 路径变形(`d` 轨道) | 90 | 48% |
| 曲线运动(位置轨道带控制点) | 94 | 50% |
| 交互触发 | 64 | 34%(hover 54、scroll 5、click 4、programmatic 1) |
| 播放 API | 官方 Player JS API 提供 play/pause/seek 等 | |

但它是**私有格式加闭源播放器**:

- **载荷没有公开规范**。检索官方帮助和 Player API,只找到播放器控制 API 的文档,没有载荷 schema。
- **格式在变**:`version` 字段出现过 4 种取值(2022-05-04、2024-09-05、2025-02-04、2025-04-07),另有 31 个样本没有该字段。
- **刻意混淆**:163/188 个样本的播放设置字段做过混淆(插入干扰字符、Base64、十六进制偏移;本次统计为取证做过解码,产品里不打算这么做)。
- **依赖联网**:115/188 个样本要从 `cdn.svgator.com/ply/` 拉取播放器。
- **服务条款**:SVGator ToS 2.1 原文 "You also agree that you have no right to access, view, or alter any Company's source code or object code.";2.2(4) 禁止 copy/redistribute/exploit 服务内容。用户保留自己作品的所有权。
- **F 的上游踩过这条路**:内嵌 QuickJS 跑官方播放器,结果 `cusp` 关键帧算错,又用 Dart 重写了 526 行插值(`svgator_interpolator.dart`)。
- **和 svgx 的原则冲突**:内嵌 JS 引擎违背"不执行 JS、体积优先";自己解析载荷,又等于去追一个刻意不公开的格式。

### 2.3 需求信号很弱

- `flutter_svg` 的 issue 里搜 "svgator"、"css animation" 都是 0 条。
- flutter/flutter #132029(Support for animated SVG)0 个 👍,被 github-actions bot 关闭。
- pub.dev 数据(2026-11-03 查询):

| 包 | likes | 30 天下载 | 说明 |
|---|---|---|---|
| full_svg_flutter | 29 | 3112 | 能播 SVGator JS 导出(QuickJS) |
| svgator_player_flutter | 5 | 80 | 官方 WebView 播放器 |
| lottie | 4582 | 2,233,945 | |
| rive | 1950 | 521,164 | |
| flutter_svg | 5938 | 6,066,633 | |

用户现有的替代方案有两个:

- **SVGator 官方 Flutter 导出**:本质是 `webview_flutter`,官方原文是 "our Flutter animations can't have transparent background"。
- **Lottie 导出**:会丢掉 mask path、mask opacity、Add/Subtract/Intersect、Alpha Inverted Matte、Gaussian blur、Drop shadow、Fill Rule、动画 skew 等。

svgx 能占的缝:**不走 WebView、能透明背景、不受 Safari 限制的 CSS 导出播放器**。缝是真的,但不大。

## 3. iOS / WebKit 的说明

- iOS 上所有浏览器都必须用 WebKit(App Review 2.5.6;欧盟和日本可以申请替代引擎)。Safari 不支持的,WKWebView 同样不支持:
  - CSS `d: path()` 路径变形:Safari 至今没有可用的实现,MDN 标为"有限可用"。
  - CSS 运动路径 `offset-path`:caniuse 记录 Safari 16 起支持;SVGator 自己的兼容表保守地写 18.6+。
  - SMIL:WebKit 一直支持。
- SVGator 排障页说 JS 导出在主流浏览器里看起来一样,CSS 导出"可能不一样"。
- svgx 在 iOS 上由 Impeller 自己绘制,不受 WebKit 限制。这是相对 WebView 方案的卖点。
- 反过来,设计师在 Safari 里测过的 CSS 导出会主动避开变形,所以 CSS 导出天然偏简单:样本里用到变形的只有 4/55。
- 在 iOS App 里执行 JS 只有三条路:WKWebView、JavaScriptCore(App 进程里没有 JIT)、自带解释器。App Review 2.5.2 不允许下载执行"引入或改变功能"的代码,而 115/188 个 JS 样本要从 CDN 现拉播放器,用自带解释器跑至少是灰区。
- **一处官方文档冲突**:SVGator 导出概览页说 CSS 不支持 morph 和曲线运动路径,但兼容表和真实样本(包括 SVGator 官网自己的 3 个 CSS 文件)里都有 `d: path()` 和 `offset-path`。准确的说法是:CSS 模式能导出这些,只是 Safari 播不了。

## 4. 现存的三处缺口

这三处是**图标路径本来就有的问题,与定位升级无关**。状态:**已修复(2026-11-03)**。验证:`test/animation` 241 个用例全过(1 个因本机缺 `svgx.dll` 跳过),新增 `fill_stroke_opacity_test`、`path_morph_test`、`set_element_test`,以及按 399 个 Iconify 图标数量对账的 `real_corpus_smil_coverage_test`。能力边界与已知限制见 `doc/animation-engine-features.md`。

依据是仓库语料 `benchmark/bench_app/lib/anim_icons_real.dart`(399 个 Iconify 动画图标):

| 缺口 | 范围 | 原因 |
|---|---|---|
| `fill-opacity` 被丢掉(静态值和动画都丢) | 163 个图标有动画(共 305 处),60 个有静态值 | `ResolvedStyle` 没有这个字段 |
| `d` 路径变形 | 48 个图标、72 处 | `parseSmilValues` 只认数字 |
| `<set>` 不处理 | 106 个(d 64 / opacity 28 / fill-opacity 14) | 检测器能识别,解析器不处理 |

## 5. 差距清单

样本来源:243 个真实 SVGator 导出(CSS 55、JS 188)。13 项关键数字由主会话独立重数,全部一致。

### 表 A:动画语义(中等工作量,分母为 55 个 CSS 样本)

| 项 | 样本 | svgx 现状 |
|---|---|---|
| 识别 CSS 动画并分流到动画路径 | 55 | ✗ 只认 SMIL,CSS 文件现在被当成静态图,只画静态属性值 |
| `<style>` + `#id` 选择器 | 53 个只用 `#id` | ✗ 动画路径不解析 `<style>` |
| transform 关键帧(包装 `<g>` 按 `_to/_tr/_ts` 分通道) | 54 | 有 animateTransform,缺 CSS 变换列表插值 |
| 逐关键帧 cubic-bezier / steps | 26 / 7 | cubic-bezier 可复用 keySplines;steps ✗ |
| opacity、stroke-dashoffset、stroke-width | 13 / 7 / 2 | ✓ |
| fill-opacity | 8 | ✗(修复中) |
| offset-path 运动路径 | 7 | 可复用 animateMotion 的弧长表 |
| fill 颜色 / d 变形 | 4 / 4 | ✗(颜色只支持 stop-color;d 修复中,SMIL 侧) |

表 A 之外,时间语义很简单:49 个是无限循环;fill-mode 全部是 forwards;没有负 delay;alternate 和 alternate-reverse 各出现在 1 个文件里。

### 表 B:渲染能力(工作量大头,分母为 243 个样本,"现状"指动画路径)

| 项 | 样本 | 现状 |
|---|---|---|
| `style=""` 属性 | 108(44%) | ✗ 完全不读 |
| 组 opacity | 102(42%) | ✓ 动画路径已修复(2026-11-04):组先离屏合成再淡化,opacity 不继承、嵌套合成相乘;静态路径由 usvg 处理 |
| gradientTransform | 97 | ✓ |
| clipPath / mask | 78 / 60 | ✓(仅非嵌套) |
| filter | 61 | 只支持模糊;其中 26 个是投影链,按代码逻辑会被画成整体模糊 |
| fill-rule / clip-rule | 47 / 30 | ✗ |
| text(tspan、@font-face 也都是 39) | 39 | 不支持 tspan 和网络字体;静态路径完全不画文字 |
| 静态 fill-opacity | 36 | ✗(修复中) |
| 嵌套 mask/clip | 26 | ✗ |
| mix-blend-mode | 19 | ✗ |

表 B 之外:组不透明度、嵌套 mask、混合模式、滤镜链都需要"图层树"这一层结构,而两条渲染路径都是按图标场景设计的。

### C:运行时

- **播放控制**:目前只有 `playbackRate` 和开始、结束两个回调,没有 play/pause/seek/restart。
- **大画布性能**:离屏图层开销按面积增长。STG-AL00 实测:图标尺寸约 221µs/通道,整窗约 43ms/通道。动画路径每帧从根节点重画整棵树,现有的降级策略是为"大量小图标"设计的。样本元素数 p90 为 280,最大 1791;轨道数 p90 为 36(CSS)/ 77(JS)。
- **对照测试**:要说"通用",得有一套"浏览器在时刻 t 的截图 vs svgx 同一时刻画面"的比对框架。

## 6. 非阻塞默认项

- CSS 解析:**自研子集解析器**(2026-11-03 拍板,推翻此前"优先用 `csslib`"的默认项)。验证过 `csslib` 1.0.2:能零错误解析 SVGator 风格的 CSS,但键帧的块、百分比、函数参数全是私有字段,只能靠 Visitor 加 `CssPrinter` 回印再拆字符串;`span.text` 只返回首个 token;畸形输入的错误恢复会静默丢掉后面的规则;还要新增 5 个纯 Dart 生产依赖。SVGator 导出是机器生成的规整格式,自研约 1100 行(含大量文档注释),零依赖、结构直接可用。
- 样本不入库,只保留 `benchmark/svgator_corpus/index.csv`(URL + sha256)作为以后的对照基准。

## 7. 渲染层方案(待 spike)

- **R1:两条路径按频次各自逐项补。** 好处是增量、风险低;坏处是同一能力要做两遍,长尾很长。
- **R2:统一成 usvg 解析,生成保留 id 的图层树,交给一个 Dart 渲染器,动画按 id 逐帧覆写属性。** usvg 会给 `<g>`/`<use>` 保留 id(在 0.46 源码 `converter.rs` 的 `convert_group` 里确认;项目原用的 0.44 与现用的 0.49 均已复核,行为一致),SVGator 又正好把动画挂在包装 `<g>` 上,理论上走得通,但要改 FFI 数据模型。

倾向:**先做 R2 的 spike 再定**,因为 R1 补到最后等于在 Dart 里重写半个 usvg。`CLAUDE.md` 的"架构决策(定论)"一节暂不改动,R2 的 spike 结果可能会改它,到时另行处理。

## 8. 样本语料与方法

- **清单位置**:`benchmark/svgator_corpus/index.csv`(编号、模式、来源 URL、体积、sha256,243 行)。样本文件本身是第三方内容,**不入库**,要对照时按 URL 重新取,用 sha256 校验。
- **构成**:243 个样本,官网/CDN 132 个,GitHub 111 个(来自 82 个仓库)。
- **去重**:按 SHA-256 去重,另排除改色、改名、只换触发方式等近似变体 39 个。
- **归属判定**:JS 样本靠 SVGator 播放器特征加载荷;CSS 样本中,10 个由官网展示页确认,45 个按 `_to/_tr/_ts` 生成命名推定(其中可能含作者手工编辑过的导出物)。
- **统计口径**:数字是"出现该特性的文件数",属性存在就计入,文件级共现不能相加。嵌套 mask/clip 用"有效引用链"口径(26),不是原始 DOM 祖先口径(106)。
- **局限**:
  - 这是**便利取样**,统计的是内容特性的出现频率,**不是用户导出占比或市场渗透率**。
  - 没有运行下载的 JS,也没做浏览器与 Flutter 的视觉一致性测试。
  - 官网 URL 可能随部署更新,保存的字节与 sha256 才是当时的证据。
- 取证时的统计脚本和原始统计数据没有入库;要复现,就按 `index.csv` 重新取样本、校验 sha256,再按本节口径重新统计。

## 9. 实施进度

CSS 动画支持分五个阶段推进,每阶段独立可验证。

| 阶段 | 内容 | 状态 |
|---|---|---|
| 1 | 自研 CSS 子集解析器:样式表、`@keyframes`、`animation` 简写与长写、时间与缓动值解析 | 已完成(2026-11-03):`css_stylesheet.dart`、`css_animation_values.dart`、`css_chars.dart`,152 个单测 |
| 2 | `<style>`(`#id`、`*`,兼顾 class/标签/后代)与 `style=""` 接入动画路径的属性层叠 | 已完成(2026-11-03):`css_cascade.dart`,90 个单测 |
| 3 | `@keyframes` 编译进时间线:数值属性(逐关键帧 cubic-bezier)、transform 列表、`steps` 缓动、`alternate`/`alternate-reverse` 方向;CSS transform 替换静态 transform 属性 | 已完成(2026-11-03):`css_keyframes_compiler.dart`,43/54 样本可完整播放 |
| 4 | `offset-path` 运动路径 → `fill` 颜色 → mask 内动画验证 → `d` 变形 → dasharray 列表值 | 已完成(2026-11-03):`css_keyframes_compiler_channels.dart` + painter 的颜色/列表覆盖通道;54/54 样本可编译且 432/432 帧绘制成功,零跳过 |
| 5 | 检测器分流,以及与浏览器截图的像素对照 | 已完成(2026-11-03):`AnimationDetector` 识别 `@keyframes`;Chrome 逐帧比对 378 帧,见下 |

第 1 阶段由 Codex 初审实现、主会话终审;终审时把两个文件里重复的字符判断收进了 `css_chars.dart`。解析器是纯 Dart,不依赖 `dart:ui` 与 `package:xml`,与动画引擎解耦。

### 第 3/4 阶段的范围依据(2026-11-03 样本分析)

按 55 个 CSS 样本逐特性统计(样本 111 的动画全部指向不存在的 id,有效分母 54;关键数字由主会话抽核过:498 个含 transform 的关键帧块签名全部一致、`transform-origin`/`transform-box`/`animation-delay` 全语料 0 次、fill-mode 全是 `forwards`)。

| 累计特性 | 完整播放的样本 |
|---|---|
| 只做数值属性 + cubic-bezier | **0** / 54 |
| + transform 列表 | 38 |
| + `steps`、`alternate` 方向 | 43(**阶段 3 终点**) |
| + `offset-path` 运动路径 | 46 |
| + `fill` 颜色、mask 内动画验证 | 49 |
| + `d` 变形、dasharray 列表值 | 54 |

- **推翻此前的划分**:原计划阶段 3 只做数值属性与 `steps`,按数据它完整播放 0 个样本(transform 占全部动画轨道的 62.9%),所以 transform 提前进阶段 3。
- **不需要包围盒**:SVGator 把枢轴放在包装 `<g>` 的结构里,不写 `transform-origin`/`transform-box`,现有变换模型够用。
- **transform 的编译方式**:同一个 `@keyframes` 里各 stop 的函数序列一致(最多 5 个槽位、顺序不固定),按"第 k 个函数各自插值"编译成按序叠加的变换动画,等价于矩阵连乘。
- **R3(最关键的风险)**:CSS 的 `transform` 会**替换**元素静态的 `transform` 属性,而引擎是"先应用静态、再叠加动画"。463 条轨道、49 个样本受影响,其中 452 条静态值恰好等于 0% 关键帧,不处理会位移翻倍。**拍板方案 1**:节点带"替换静态 transform"标记,CSS transform 动画生效期间绘制时跳过静态矩阵,未生效时用静态值(符合 CSS 语义,绘制处改动小)。方案 2(编译期直接丢掉静态 transform)对"有 delay 或无 forwards"的文档不对,否决。
- **其它风险**(阶段 3/4 设计时逐条对照):38 条孤儿动画必须安静忽略;样本 137 依赖 `*{…!important}` 的层叠;opacity 动画作用在 `<g>` 上的逐元素近似已于 2026-11-04 改为组离屏合成;回弹曲线(y 超出 0~1)在 `d` 通道会被钳制;行内样式里的动画元素可能没有 id,绑定要按节点;`alternate` 的编译方式尚未验证。
- **不用做**:`transform-origin`/`transform-box`、`matrix`/百分比/3D transform、同一属性被多个动画重复驱动、`<use>` 上的动画,语料里都是 0。

### 第 3~5 阶段的结果(2026-11-03)

- **覆盖**:54 个有效样本(111 为孤儿样本)全部编译、八个时刻全部绘制成功(432/432)。接线轨道:transform 471 块/620 槽位、数值 132、运动 33、`d` 变形 10、颜色 89(节点)+6(渐变 stop)、dasharray 11,**无跳过、无近似**。入库期望表 `test/animation/css_real_samples_expected.json`(样本本身不入库,需设 `SVGX_CSS_SAMPLES`)。
- **渲染保真度缺口(由比对发现并已修)**:`fill-rule`/`clip-rule` evenodd、`mask-type="alpha"`、`feGaussianBlur` 双值、紧凑圆弧标志位、`opacity` 钳制。
- **与 Chrome 的逐帧比对**(378 帧,256×256,viewBox 为固有尺寸,每样本取 t=1ms 与 ¼/½/¾ 等时刻;指标 diffRatio = 任一通道差 >32 的像素占比):实现根 `<svg style="background-color">` 背景、修复 `display="none"` 与 clip-path/mask 坐标系、比较器补解码 `<image>` 之后,中位数 0.33%、p90 2.6%、p99 25.2%、最大 26.8%;高于 3% 的帧 35 个、高于 6% 的 8 个。
  未实现根背景色时,中位数 0.34%、p90 5.4%、p99 94%、最大 97%——每个 SVGator 导出都带这个背景,所以它是必须补的一项,现已完成。
- **比对发现并修复的两个渲染缺口**:`display="none"` 此前完全不处理(样本 159 的整套隐藏场景被画出来);`clip-path` 与 `transform` 在同一节点时,裁剪被放在父坐标系而非节点自身坐标系(按规范应随节点 transform)。修后 159 从最差 48.1% 降到 0.4% 以内。`mask` 与 `transform` 同节点时遮罩同样改为在节点自身坐标系绘制(`_applyOwnTransform` 供内容与遮罩共用)。
- **样本 156 的 14.7% 不是渲染缺陷**:比较器没调用 `resolveImageNodes`,内嵌截图 `<image>` 没解码;补上后降到 3.4%,剩余差异来自三个 `mix-blend-mode:multiply` 渐变矩形的压暗与一处按钮位置,未深挖。
- **仍偏差较大的样本**:137(文字用嵌入字体,26.8%)、170(6.0%)、149(4.7%)、131(4.1%)、127(3.8%)、156(3.4%)。
- **每帧绘制耗时(T9,`flutter test` JIT 环境、只含 Dart 侧录制 `paintAt`,仅作相对参考)**:样本 159 约 90~140µs,104 约 1.0~1.6ms,109 约 0.8~1.2ms,050 约 40~50µs,均远低于 16ms 帧预算;AOT 真机数字另测。
- 详细限制清单见 `doc/animation-engine-features.md`"明确不支持"。

### 第 2 阶段的实现要点

- **接入点**:所有元素属性表都出自 `_attributesOf()`,在它之后加一步 CSS 层叠,覆盖元素、渐变 `<stop>`、`<use>` 包装元素。层叠逻辑在纯 Dart 的 `css_cascade.dart`,解析器里只有一个 XML 适配器,`package:xml` 仍只出现在 `svg_document_parser.dart`。
- **优先级**(从低到高):XML 表现属性 → `<style>` 规则(按 specificity,再按源码顺序) → `style=""` → `!important` 规则 → `!important` 内联。选择器按最右复合条件分桶索引,不对每个元素扫描全部规则。
- **声明的去向**:`animation*` 解析成 `SvgNode.cssAnimations`;`transform`、`offset-*`、`d`、`mix-blend-mode`、`isolation` 只存进 `SvgNode.cssProperties`,**不**覆盖属性表(CSS 的 transform 带 `px`/`deg` 单位,会被现有的 SVG transform 解析误读);其余声明覆盖属性表,恰为 `<数字>px` 的值去掉单位;含 `var()`/`calc()`/`env()`、值为 `inherit`/`initial`/`unset`/`revert` 的声明整条忽略。
  `@keyframes` 挂在 `SvgDocument.cssKeyframes`。
- **当前效果与限制**:CSS 对颜色、不透明度、描边等静态属性已经生效;**动画本身还没有播放**(阶段 3 才把 `cssAnimations` 与 `cssKeyframes` 编译进时间线,阶段 5 才让检测器识别 CSS 动画),静态的 CSS `transform` 也要等阶段 4。
- **性能**:没有 CSS 的文档走快路径,不建索引、不分配;399 个 Iconify 图标解析中位数 81.5ms → 82.6ms(约 +1.4%,统计上不显著);55 个 SVGator 样本整体 120ms,最慢的 877 个元素的样本 20ms。
- **真实样本**:55/55 解析成功,787 组关键帧、749 条动画,引用的关键帧无一缺失;另有 38 条动画规则指向 XML 里根本不存在的 id(SVGator 导出的残留规则,分布在 8 个样本),被自然丢弃。

### 第 1 阶段的真实样本验证(55 个 CSS 导出,样本不入库)

- 55/55 下载成功且 sha256 一致,全部解析无异常;共 61 个 `<style>`、84 个行内样式、758 条规则、787 个 `@keyframes`,787 个动画引用全部能找到对应关键帧。关键数字由主会话用 grep 独立复核过。
- **选择器**:757 个纯 `#id`、1 个 `*`,没有 class、标签、复合、后代、子代。被丢弃的只有 4 个:`#…:hover *` 两个(hover 交互)、`*::before`、`*::after`(重置规则)。
- **`style=""` 必须处理**:`offset-path`(33)与 `offset-rotate`(33)只出现在行内样式里,另有 `mix-blend-mode`(6)、`isolation`(3)、`stop-color`(24)、`background-color`(10);107、118 两个样本的动画完全由行内样式指定。
- **关键帧里出现的属性**(声明次数):transform 2608、fill 323、offset-distance 283、opacity 232、stroke-dashoffset 174、fill-opacity 104、stroke-width 75、stroke-dasharray 55、`d` 46、stop-color 36、rx 与 ry 各 15。
- **transform 列表只有这几个函数**:translate 2036、rotate 718、scale 561、skewX 43、skewY 43,没有 matrix。
- **缓动**:`cubic-bezier` 1079;`steps(` 4、`step-end` 38、`step-start` 4。
- **没覆盖**:6 个样本带 `@font-face`(共 7 条,内嵌字体),属于文字渲染,不在本轮范围;2 次 `animation-play-state` 来自被丢弃的 hover 规则。

## 10. 来源

- [SVGator 导出设置](https://www.svgator.com/help/export-and-file-formats/svg-export-settings)
- [SVGator 浏览器兼容表](https://www.svgator.com/help/integrating-your-animations/browser-support)
- [SVGator Flutter 导出](https://www.svgator.com/help/export-and-file-formats/export-flutter-animations)
- [SVGator Lottie 支持说明](https://www.svgator.com/help/export-and-file-formats/lottie-support-in-svgator)
- [SVGator 排障:导出文件看起来不一样](https://svgator.com/help/technical-issues/exported-file-looks-different)
- [SVGator 服务条款](https://www.svgator.com/terms-of-service)
- [MDN: CSS `d`](https://developer.mozilla.org/en-US/docs/Web/CSS/d)
- [caniuse: CSS 运动路径](https://caniuse.com/css-motion-path)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [flutter/flutter #132029](https://github.com/flutter/flutter/issues/132029)
- [pub.dev: lottie](https://pub.dev/packages/lottie)
- [pub.dev: full_svg_flutter](https://pub.dev/packages/full_svg_flutter)
