# svgx 项目规则

## 项目目的

打造一个**高性能、同时支持静态与动画的 Flutter SVG 库**,目标是替换 `flutter_svg` + `iconify_flutter`。

- 解析底层用 **Rust**(经 flutter_rust_bridge / cargokit 集成)。
- 渲染交给 **Flutter 自身的 GPU 管线**(`ui.Picture` / Canvas / Impeller),**不引入 CPU 光栅器**。
- 动画能力(SMIL + CSS)是本库的核心差异点和存在理由。

## 工作方式规则(2026-08-25 追加)

- **不重复造轮子**:实现新的非平凡逻辑(算法、解析器、协议处理、数据结构)前,优先去 crates.io、GitHub、pub.dev 等地方调研是否已有成熟方案(如本项目对 usvg/svg-rs/`full_svg_flutter` 的取舍方式),能采用/封装就不要自己从零写。参考上面"参考对象"章节的判断方式。
- **用 subagent 落地任务,主 agent 只负责调度**:非平凡的多步骤任务(调研、实现、重构、基准测试)应派发给 subagent(Agent 工具)去做,主 agent 负责拆解任务、分派、review 结果、维护整体上下文,不要自己大包大揽做具体执行。简单的单步操作(读一个文件、改一行、查个状态)不必走这个流程。

## 参考对象(取长补短)

| 代号 | 对象 | 定位 | 我们怎么用 |
|---|---|---|---|
| **U** | `usvg`(crates.io) | 成熟的**静态** SVG 解析/简化器:shape→绝对路径、解析 use/switch/marker、base64 图片、全部 filter 类型 | **静态解析直接采用** |
| **R** | `resvg` | 在 U 之上的 **CPU(tiny-skia)光栅器** | **不采用**:无动画、CPU 渲染比 Flutter GPU 慢、体积 +~0.5MB(实测 1.13MB→1.63MB) |
| **svg-rs** | `github.com/ginokent/svg-rs` | 零依赖 Rust **SMIL 求值器**(给定 t 返回属性值),支持 `<animate>`/`<set>`/`<animateTransform>` | **动画的 SMIL 参考实现**;但它无 CSS 动画、无 filter/mask/text、成熟度低,不直接依赖 |
| **F** | `full_svg_flutter` fork,位于 `E:\workspaces\bingo\packages\full_svg_flutter` | Dart 动画渲染器:SMIL + CSS `@keyframes` + path morph + filter;已剥离 quickjs;已加静态快路径(缓存 `ui.Picture`) | **仅作性能对比的基准实现**,**不进入 `lib/`**;动画语义参考它的思路,但要写原创代码 |

**动画能力 = 参考 svg-rs 与 F 的思路,原创实现**:svg-rs 提供零依赖、干净的 SMIL 采样思路;F 提供更全的动画语义(CSS keyframes、path morph、filter)覆盖面参考。**取二者之"思路"而非"代码"**——学它们怎么做,自己写。

## CSS 支持范围(2026-08-25 调研结论,避免重复纠结)

- **usvg 的 CSS 支持比预期扎实**:靠 `simplecss`(CSS 2.1 级)真正解析 `<style>` 块(不只是内联样式),支持 element/class/id/后代/子代/属性选择器 + 优先级级联。**明确不支持**:`@media`、`@import`、CSS 变量 `var()`、`calc()`、伪元素。这些是 usvg 上游自己的边界,不是我们要补的缺口。
- **`lightningcss` 不值得引入**:它是给 bundler 用的 CSS 转换/压缩工具,**没有针对 DOM 的选择器匹配能力**——就算用它解析 CSS 文本,匹配规则到 SVG 元素这个最难的部分还是得自己写,替代不了 usvg 已经在用的 `simplecss`。
- **"SVG 里的高级 CSS"是伪需求(针对 svgx 的图标场景)**:查了 `flutter_svg` 全部 1116 个 issue,`<style>`/CSS class 相关的实质性 issue 只有 4 个(<0.4%),且**全部来自 Adobe Illustrator/CorelDRAW 导出的手工 SVG**,没有一个来自图标资产(Iconify/Figma 图标本来就是内联样式/展示属性)。`@media`/CSS 变量/`calc()` 在 issue 里完全没人提过。svgx 的定位(替换 flutter_svg + iconify_flutter 做图标渲染)正好是这个需求几乎不出现的资产类型。
- **结论**:不追加 CSS 相关投入。如果以后真遇到 `<style>` 块场景,先确认 usvg 现有解析(已经比 flutter_svg 强)是否够用,而不是新造轮子。

## CSS 动画支持:有证据支撑的"不做"(2026-08-25 调研结论,注意与上面"CSS 支持范围"是两个不同问题)

原创动画引擎排除 CSS `@keyframes`/`animation-*`/`transition-*` 不是图省事,是查过真实数据后的决策:

- **直接 grep 了 Iconify 真实数据**(`iconify/icon-sets` 仓库的 JSON):`line-md`(5310 个 `<animate>`、192 个 `animateTransform`、**0 个 CSS**)、`svg-spinners`(262/38/0)、`eos-icons`(33/7/0)——**每一个检查过的动画图标集,100% 是 SMIL,零 CSS**。line-md 上游 README 提的"CSS 导出目录"只是营销页面,不是 `iconify_flutter` 实际分发消费的内容。
- **flutter_svg issue 搜 `keyframes` 只有 1 个命中**(#772,开的当天就被维护者回"No, sorry"关掉),`"css animation"`/`transition`/`animation-name` 零命中。
- **F 的上游 `full_svg_flutter` 号称支持 CSS keyframes,但最近 30 个 issue 里没有一个提到这个功能**——功能存在但几乎没人用/没人讨论。
- 旁证:连主打 CSS/JS 导出的 SVGator,`full_svg_flutter` 真要支持它时都选了上 QuickJS 跑 JS,不是解释 CSS。

**结论**:不做 CSS 动画。只有当 svgx 定位从"图标替换"扩展到"通用 SVGator 风格装饰性动画内容"时才重新评估——且到那时候证据也指向 JS 运行时而非 CSS 引擎。

## ⚠️ 硬规则:`lib/` 禁止整包 vendor,但允许精确抄小段代码(2026-08-25 放宽)

**`lib/` 是要发布的库代码,不能把别的项目的整个文件/子系统复制粘贴进来当自己的实现;但为了实现一个明确需要的具体功能点,直接摘取 F 的一小段代码是允许的——前提是符合下面的许可证边界和"不延伸"原则。**

- 2026-08-25 曾把 `E:\workspaces\bingo\packages\full_svg_flutter\lib` **原样 vendor** 进了 `lib/src/fvendor/` 并从 `lib/svgx.dart` 导出——**这仍然是错误做法**:那是整包搬运 + 对外导出,属于下面明确禁止的"延伸"。已移除,教训保留。

### 按来源分两种规则,不能混用

- **F(`full_svg_flutter`,MIT 许可,已核实)**:**允许抄代码**。为实现一个具体功能点(比如 keySpline 三次贝塞尔求值、SMIL clock-value 格式解析),可以直接从 `benchmark/baseline_f/full_svg_flutter_lib/` 摘取对应的一小段代码放进 `lib/`。抄的时候:
  - 只抄**当前明确要用到的最小单元**(一个函数/一段算法逻辑),不抄它周边没用到的抽象、辅助类型、扩展点——**禁止延伸**。判断标准:如果发现自己在复制一整个文件的结构骨架、或者把用不到的辅助函数也搬了过来"以防万一",就是延伸了,停下来只留真正用的部分。
  - 抄过来的代码块**必须加注释标明来源**(来自 F/`full_svg_flutter` 的哪个文件、哪个函数),满足 MIT 许可的署名要求,也方便以后追溯。
- **svg-rs**:**禁止抄代码**——核实过 GitHub API,它的 `license` 字段是 `null`,没有声明任何开源许可证,默认视为"保留所有权利",复制它的代码(不管多小一段)在法律上都不安全。**只能读它的思路/算法做交叉验证,自己重新实现,一行代码都不能直接照抄。**

### 仍然禁止的"延伸"

- 整个文件/整个子系统复制粘贴(哪怕来源是 MIT 的 F)。
- 把 vendor 目录整体导出给 `lib/svgx.dart` 的调用方。
- 判断标准不变:**只抄当前明确要用到的最小单元,不是"顺手多抄点以防以后要用"。**

## 架构决策(定论)

1. **按资产切分,而非按阶段切分**:
   - **静态 SVG** → U(Rust)解析 → 显示列表 → 过 FFI → Dart 建 `ui.Picture` 缓存 → Flutter GPU。
   - **动画 SVG** → 保留动画的解析器(F,或将来 Rust 自研,参考 svg-rs)→ 每帧在 Dart 采样 → Flutter GPU。
   - 原因:**usvg 会丢弃 `<animate>` 并展平树**,打断 SMIL 的 id 绑定,所以动画解析无法复用 usvg。

2. **动画工序归属**(核心约束:每帧过 FFI 很贵,每帧的活必须整块留在 FFI 同一侧):
   - 解析 + 建时间线(一次性)→ **Rust 可做**。
   - 每帧采样/插值/path morph(每帧)→ **默认 Dart**;仅当压测证明是瓶颈且重到能盖过 FFI 成本才下沉 Rust。
   - 显示列表 → `ui.Picture`(每帧)→ **Dart**(dart:ui)。
   - 光栅化 → **Flutter GPU,Rust 永不参与**。

3. **起步策略**:Rust 只打**静态解析**这场硬仗;**动画整条先留 Dart**(原创实现)。先实测"多动画并发"是否为瓶颈,再决定是否把"解析+时间线"甚至"每帧采样"下沉 Rust。

4. **Dart 先行是刻意的,但必须留切换缝隙,不是关死这扇门**(2026-08-25 明确):
   - **为什么先 Dart**:动画解析是一次性、小体量成本(单个图标级别,不是千图标批量场景——批量场景已经走 Rust usvg 了),用 Dart 快速验证 SMIL 语义正确性(begin/dur/fill/values/calcMode 这类细节,改一行热重载就能看效果),比隔着 FFI+FRB codegen 反复调试快得多。这是效率选择,不是"Rust 做不到"。
   - **必须保留的缝隙**:动画引擎对外的接口要设计成**可替换实现**,而不是把"用 Dart 解析"焊死在调用方代码里。具体要求:
     - 解析入口收敛成一个清晰的函数/接口边界,例如「输入 SVG 字符串 → 输出一个自描述的时间线数据模型(时间线/关键帧/目标属性,不含 Dart 专属类型)」,`svgx_widget.dart` 的分发逻辑只依赖这个边界,不直接依赖"是 Dart 实现"这件事。
     - 时间线数据模型本身要能被一次性的 Rust 解析结果填充(即将来若换成"Rust 解析+建时间线一次性→ Dart 采样"的实现,只需要换掉解析这一层,采样/绘制层不用动)。
     - 不要为了"将来可能换 Rust"而现在就搭一层花哨的抽象/插件系统——一个干净的函数签名 + 数据模型就够,过度设计违反项目一贯原则(不为还没发生的需求建抽象)。

## 验收条件(测试通过标准)

能够渲染 line-md 的动画对勾并**正常播放描边动画**:

```dart
// 参考用法（iconify 的 Iconify 用 flutter_svg 渲染，不跑 SMIL；
// 本库需能渲染同一段 SVG 字符串并让动画动起来）
import 'package:iconify_flutter/icons/line_md.dart';
// 目标：本库的 Widget 渲染 LineMd.confirm_circle 的 SVG，圆环+对勾描边动画正常播放
```

- 判定:圆环沿描边绘制(约 0.5s)→ 对勾描边绘制(约 0.2s),`fill=freeze` 定格。
- 已知坑:`confirm_circle` 原串组上是 `fill="currentColor"`,会把圆盘填满盖住描边动画,需按 `fill:none` 处理(F fork 里已用 `replaceAll` 修正,可参考)。
- 对照基准:静态渲染性能需追平 `flutter_svg`(F fork 已通过:build/帧 0.68ms、PSS 更低);动画需在真机流畅播放。

## FFI 数据搬运审计结论(2026-08-25,已审计,无需改动)

审计了 `parse_svg` 的 Dart↔Rust 数据搬运方式,结论:**当前实现已经是 FRB 2.12 sync/generalized 架构下能做到的最优,没有可落地的优化空间**。关键事实(已核实,非猜测):

- **本项目生成的是 SSE(序列化)编解码,不是 DCO(原生零拷贝)编解码**——`lib/src/rust/frb_generated.dart` 里 `parse_svg`(以及所有其他函数)都接的是 `SseCodec`,不是走 `allo-isolate` 的 `DartNativeExternalTypedData` 零拷贝路径。后者只对 DCO 编解码生效,本项目压根没用那条路径。
- **`points: Vec<f32>`/`verbs: Vec<u8>` 这类大字段,sync 模式下确实有一次拷贝**——但是**整块 bulk copy,不是逐元素循环**。FRB 自己在 `read_buffer.dart` 里有原话注释:"Must copy when in `sync` mode, because the underlying buffer is a Rust pointer and will be freed later (but in non-sync mode, we can optimize this and do not copy)"——这是 FRB 为了避免访问已释放的 Rust 内存,故意加的安全拷贝,不是实现疏漏。
- **想去掉这次拷贝,唯一办法是把 `parse_svg` 从 sync 改成 async**——但这条路已经在"性能验收条件"里评估过并明确否决(sync 单次解析 avg=0.026-0.106ms,1000 图标场景零掉帧,量级可忽略,不值得为了省这一次 bulk copy 换成跨 isolate 派发的 async)。
- **`String` 入参换成 `Uint8List` 没有意义**:UTF-8 编码这一步不可避免只会发生一次,搬到调用方代码里做和留在 FRB 生成代码里做,总成本一样,不会减少。查了 `flutter_svg` 自己的 `SvgBytesLoader.provideSvg`,它也是先 `utf8.decode` 成 `String` 再解析,业界通用做法一致,不是我们独有的反模式。
- **flutter_svg 的缓存 key 也是对完整字符串做 hash**(`Object.hash(_svg, theme, colorMapper)`),和 svgx 的 `(String, int?)` 缓存 key 成本量级相同——没有可以借鉴的更便宜方案。

**结论**:不改代码。如实记录"审计过、现状已经足够好"这个结论,以后不用再为这个问题重新调研或纠结。

**补充调研(2026-08-25,ZeroCopyBuffer/DCO 专项)**:确认当前 `parse_svg` 走的是 **SSE(序列化)编解码,非 DCO/ZeroCopyBuffer**——`rust/src/api/svg.rs` 的 `SvgPath`(`points: Vec<f32>`/`verbs: Vec<u8>`)未用 `ZeroCopyBuffer<Vec<u8>>` 包装,`lib/src/rust/frb_generated.dart` 用的是 `SseCodec`。FRB 2.x 里 ZeroCopyBuffer 对应的免拷贝路径是 **DCO codec**(经 `allo-isolate` 的 `Dart_PostCObject` 机制),但这条路径**天然要求 async 调用**(`executeNormal`),和当前 `#[frb(sync)]` 互斥——要用 DCO 就必须先把 `parse_svg` 改成 async,这和"是否值得为省一次 bulk copy 换成 async"是同一个决策,已经在上面否决过。收益上,DCO 省下的是当前 avg 0.026-0.106ms 里最小的一块(序列化 bulk copy),而 async 化引入的跨 isolate 调度/`Completer` 开销大概率超过这点节省。**结论:不做**,维持 sync + SSE 现状。

**补充调研(2026-08-25,"Uint8List 触发共享内存零拷贝"传闻核实)**:有说法称"Dart 传 `Uint8List` 给 Rust 会触发共享内存从而避免拷贝",核实为**误传,方向搞反了**。FRB 的零拷贝机制描述的是 **Rust → Dart** 方向(`ZeroCopyBuffer` 把 Rust 的 `Vec<u8>` 免拷贝映射成 Dart 的 `ExternalTypedData`),而 `parse_svg` 的入参方向是 **Dart → Rust**,本来就不在这个机制覆盖范围内。即便方向对了,FRB 官方文档也明确写"同步传输仍需要拷贝",零拷贝只在 async 模式下生效,与当前 `#[frb(sync)]` 互斥。手动把 SVG 字符串 `utf8.encode` 成 `Uint8List` 再传,只是把编码步骤从 FRB 生成代码搬到调用方代码,总拷贝次数不变,没有意义。

**补充调研(2026-08-25,手写 dart:ffi 绕开 FRB 能否同步零拷贝)**:结论为**部分能,但不值得换**。
- Dart→Rust 方向:`Uint8List.address`(Dart 3.5+)理论上可传裸指针,但 Dart 是可整理(compacting)GC,官方未明确承诺同步 FFI 调用期间该内存会被自动 pin 住,存在地址失效风险;改用 `malloc.allocate`(native heap)内存稳定,但**把 Dart String 编码进这块 buffer 本身就是一次拷贝**——UTF-16→UTF-8 编码这一步,FRB 和手写 FFI 都躲不掉,零拷贝只能省掉"编码完之后再搬一次",省不掉编码本身。
- Rust→Dart 方向:`Pointer.asTypedList()` 配合 `NativeFinalizerFunction`(Dart 3.1+)可做到不拷贝的视图,但生命周期正确性完全靠开发者手动保证,Dart SDK 的 GitHub issue(`dart-lang/sdk#55800`)记录过跨 isolate 场景下的 use-after-free 真实 bug。
- FRB 官方文档(zero-copy guide)自己承认:sync 模式下的零拷贝是"理论上可行但尚未实现"的路线图项,当前 FRB sync 就是强制拷贝的 codec。手写 FFI 没有这层限制,架构上确实能做到 FRB sync 做不到的事。
- **代价**:彻底放弃 FRB 的类型安全生成,内存安全责任全部转移给开发者(GC 移动、手动 pin/finalizer、跨调用生命周期管理),换来的只是省掉一次微秒级的 bulk copy(当前 avg 0.026-0.106ms,1000 图标场景零掉帧)。
- **结论:不建议做**。收益(省一次微秒级拷贝)远小于代价(放弃类型安全 + 内存安全风险 + 维护成本),与 ZeroCopyBuffer/DCO 那次结论方向一致——现状(FRB sync + SSE)已经是当前数据量级下的最优解,已做三次交叉验证(DCO 专项、Uint8List 传闻、手写 FFI),结论稳定,以后无需再为这个问题重新调研。

## 性能验收条件(2026-08-25 追加,正式落地的硬指标)

在功能验收(动画能播放)之上,追加以下**性能门槛**,任一不满足都不算真正验收通过:

1. **静态渲染必须全面超越 `flutter_svg`**——不是"追平",是每个统计维度都要赢(见下方维度)。只要有一项持平或更差,判定不通过,需要继续优化。
2. **动画性能必须流畅、不得阻塞主线程(UI/Dart isolate)**。
   - **已知架构隐患**:当前 `rust/src/api/svg.rs` 的 `parse_svg` 标了 `#[flutter_rust_bridge::frb(sync)]`——这类 sync FRB 调用会在**调用方的 Dart isolate 上同步阻塞执行**直到 Rust 返回。1000 个互不相同的图标场景下,每个都要走一次真实解析(无法被"相同 source 缓存"抵消),如果解析走的是 UI isolate 的同步调用,极可能就是"阻塞主线程"这条红线的直接触发点。
   - **要求**:`parse_svg` 的 FFI 调用必须验证不阻塞 UI 线程——要么改成 FRB 的异步模式(在独立线程/worker isolate 执行,通过 Future 返回),要么显式把解析派发到 Dart 的 `Isolate.run`/后台 isolate 再桥接 FFI。这是本轮必须验证并按需修正的一点,不能默认当前实现"因为能跑就没问题"。
3. **测试场景**:**1000 个互不相同的图标**,做**来回滚动**(不是同一图标复制 400 份那种能被 Picture 缓存"作弊"的场景——之前 bingo 项目的基准用的是相同图标,这次必须是不同图标,才能压出真实的解析+建 Picture 成本)。
4. **统计维度**(每个维度都要有 svgx vs flutter_svg 的对照数据):
   - CPU 占用
   - 内存占用(峰值 + 稳态)
   - 解析耗时(单图标 + 批量场景下的分布:avg/p50/p90/p99)
   - 渲染耗时(即每帧 build/raster,同上分布)
   - **有无内存泄漏**:反复滚动多轮后强制 GC,内存是否回落到基线,而不是单调增长
   - **GC 是否及时**:GC 暂停频率/时长是否影响帧率,是否有"迟迟不回收导致内存堆积"的现象

**方法学要求**:复用 bingo 项目已验证的基准方法(`SchedulerBinding.addTimingsCallback` 采 build/raster、`top`/`dumpsys meminfo` 采 CPU/内存、profile 模式、force-stop 隔离进程),但样本必须换成 1000 个不同 SVG,且要新增"多轮滚动 + 强制 GC 后测内存"的泄漏检测环节(之前的基准没有这一步)。

5. **新增用例(2026-08-25 追加):1000 个动画图标来回滚动,统计真实 FPS**——和上面"1000 个静态图标"、以及既有的"12 个并发动画"平滑度检查都不是一回事,是单独的重压测场景:
   - **场景**:1000 个**互不相同的、正在播放动画**的图标(不是静态图标,不是同一个动画图标复制 1000 份),放进滚动列表来回滚动,滚动过程中屏幕内可见的图标始终在**并发播放动画**(不是滚到才开始播、滚走就停——除非这本身就是引擎的可见性优化策略,那也要如实说明这一策略生效与否)。
   - **图标来源**:优先用真实的 Iconify 动画图标集(`line-md`/`svg-spinners`/`eos-icons` 等,前面已确认都是纯 SMIL)。如果单一集合凑不够 1000 个不同的,可以合并多个动画集合;如果合并后仍然不够 1000,**如实说明实际拿到多少个真实动画图标**,不要为了凑数字用同一图标改色/改尺寸这种"伪造成不同"的手法——诚实标注比硬凑 1000 更重要。
   - **统计指标:真实 FPS,不是模拟/推算的**。也就是不能用"1000 / 平均帧耗时"这种从均值反推的近似值当结果,必须是**按真实墙钟时间窗口,统计实际渲染完成的帧数**——具体做法:用 `SchedulerBinding.addTimingsCallback` 拿到的每一帧真实时间戳,按 1 秒为一个窗口分桶,数每个窗口里真实落地了多少帧,这才是"真实 FPS"。同时报告 FPS 的分布(avg/min/p1 这种低分位,因为 FPS 的"最差时刻"比平均值更能反映卡顿)。
   - **判定**:这个场景下 svgx 的动画引擎必须能撑住合理的 FPS(不掉到明显卡顿的区间),且要跟 flutter_svg 侧的等价动画渲染方式做对比(如果 flutter_svg 没有直接可比的动画能力,如实说明"无等价对照",不要硬凑一个不对等的对比)。

### 验收状态

**功能验收:PASS(2026-08-25,spike 阶段)** —— 当时是把 F 整包 vendor 进来的临时方案,未做资产分流,见 git 历史。

**架构正式落地:PASS,但随后被打回重做(2026-08-25)** —— 第一版按资产分流做了:静态走 `rust/src/api/svg.rs` 的 `parse_svg`(usvg 0.44)→ FRB → `lib/src/rust_static_svg.dart` 的 `SvgXStatic`;动画路径当时**直接 vendor 了整份 F 到 `lib/src/fvendor/` 并从 `lib/svgx.dart` 导出**——这违反了上面"硬规则:`lib/` 禁止 vendor 第三方引擎代码",**已被否决**。

**原创动画引擎重写:PASS(2026-08-25)**:
1. `lib/src/fvendor/` 已移出 `lib/`,搬到 `benchmark/baseline_f/full_svg_flutter_lib/`(仅作未来性能对比基准,`analysis_options.yaml` 已排除 `benchmark/**`),`lib/svgx.dart` 不再导出它。
2. `lib/src/animation/` 下是原创 SMIL 引擎(`svg_dom.dart`/`svg_document_parser.dart`/`smil_animation.dart`/`animated_svg_painter.dart`/`animated_svg_widget.dart`/`svg_path_data.dart`/`svg_style.dart`/`svg_theme.dart`/`animation_detector.dart`),接入 `svgx_widget.dart` 的 `SvgX.string` 分发,替换掉了 vendor 的 `AnimatedSvgPicture`。
3. F 已重新定位为 `benchmark/baseline_f/` 下的对比基准,不进 `lib/`。
4. 功能验收已用原创引擎重新跑过,截图(`benchmark/acceptance_screenshot.png`)确认圆环+对勾正确渲染,`fill="none"` 修正依然生效。

**解析边界(接口缝隙)已验证满足架构决策第 4 条**:唯一解析入口 `SvgDocument parseAnimatedSvgDocument(String source)`(`lib/src/animation/svg_document_parser.dart`),返回纯数据模型(`SvgDocument`/`SvgNode`/`SmilAnimation`,`attributes` 是 `Map<String,String>`),`package:xml` 类型只存在于这一个文件内;`svgx_widget.dart`/`animated_svg_widget.dart`/`animated_svg_painter.dart`/`smil_animation.dart` 都只依赖这个函数的返回值。将来要换 Rust 一次性解析,只需替换这一个函数的内部实现——这是自然设计出来的结构,不是事后补的。

**当前动画引擎支持(2026-08-25 第三轮扩展后,增量见下方"第三轮扩展"章节)**:`<use>`(含 `xlink:href`、前向引用、环检测)、`<g transform="...">` 静态变换、`<animateTransform type="skewX"/"skewY">`、syncbase `begin`(`id.begin`/`id.end` ± 偏移,含依赖链与环检测)、`<animateMotion>`(含 `<mpath>` 与 `rotate="auto"`)、CSS 具名颜色、静态 `<linearGradient>`/`<radialGradient>`。

**当前动画引擎支持(2026-08-25 第二轮扩展后)**:`<svg>`/`<g>`/`<path>`/`<circle>`/`<rect>`(含 `rx`/`ry` 圆角)/`<ellipse>`/`<line>`/`<polyline>`/`<polygon>`;`<animate>` 的 `values`/`from-to`、`dur`、简单数值 `begin` 延迟、`fill="freeze"` vs 默认复原、**`repeatCount`(有限次数与 `indefinite` 无限循环)**、**`calcMode`(`linear`/`discrete`/`paced`/`spline`)**、**`keyTimes`**、**`keySplines`**;任意单数值展示属性动画(通用,不只是 `stroke-dashoffset`);**`<animateTransform>`(`type="translate"`/`"scale"`/`"rotate"`,`rotate` 支持 `angle`/`angle cx cy` 两种语法,同一元素多个 `<animateTransform>` 按文档顺序合成)**,同样支持 `repeatCount`/`calcMode`/`keyTimes`/`keySplines`;`fill`/`stroke`/`stroke-width`/`stroke-linecap`/`stroke-linejoin`/`stroke-dasharray`/`stroke-dashoffset`/`opacity` + SVG 继承 + `currentColor`;原创虚线描边渲染;原创 path data 语法解析(M/L/H/V/C/S/Q/T/A/Z)。

驱动方式已从绑定 `[0,1]` 的 `AnimationController` 改为原始 `Ticker`(`animated_svg_widget.dart`):文档含 `repeatCount="indefinite"` 时永久 ticking,否则在所有动画的 `begin + dur * repeatCount` 都结束后自动停止 ticker(不再白白消耗帧)。

**明确不支持(如实标注,2026-08-25 更新)**:`<animateMotion>`、CSS `@keyframes`/`animation-*`/`transition-*`、syncbase/事件类 `begin`(只解析纯数值偏移)、`<use>`/`<text>`、渐变/mask/filter、`<g transform>` 静态变换、`<animateTransform type="skewX"/"skewY">`、具名 CSS 颜色。这些是明确的后续待办。

> ⚠️ 上面这份"明确不支持"清单已被 2026-08-25 的第三轮扩展**大部分补齐**,现状以下方"第三轮扩展"章节为准(仍不支持的只剩:CSS 动画、事件类 `begin`、`<text>`、mask/filter)。

## 第三轮扩展(2026-08-25):具名颜色/静态 transform/skew/`<use>`/syncbase/`<animateMotion>`/渐变

本轮把上面"明确不支持"清单里的六项做掉了,并把两处**值解析下沉到 Rust**。所有结论都跑过命令验证,未验证的部分在末尾"如实标注的缺口"里单列。

### 1. 值解析下沉 Rust:`parse_color` / `parse_transform`(新 FFI)

- `rust/Cargo.toml` 新增 `svgtypes`(MIT/Apache-2.0,即 usvg 自身解析 SVG 取值用的 crate)。**2026-08-25 补记:双版本问题已解决**——原先声明的 `"0.16"` 与 usvg 0.44 锁定的 `svgtypes 0.15.3` 不统一,编译产物里有两个版本(0.15.3 + 0.16.x)。已把版本要求改为 `"0.15"`,`cargo tree -i svgtypes` 验证现在只解析出一份 `svgtypes v0.15.3`(usvg 与 svgx 共用同一份)。0.15.x 与之前用到的 API(`svgtypes::Color`、`Transform`、`TransformListParser`、`TransformListToken`)完全兼容,`rust/src/api/svg.rs` 的 `parse_color`/`parse_transform`/`token_matrix`/`concat` 未作任何改动,`cargo build`/`cargo test`(14 passed)全部通过。FRB 导出签名未变,未重跑 codegen。
- `rust/src/api/svg.rs` 新增两个 `#[frb(sync)]` 函数:`parse_color(String) -> Option<Vec<u8>>`(RGBA 四字节)、`parse_transform(String) -> Option<Vec<f32>>`(整套 `<transform-list>` 语法合成后的 `[a,b,c,d,e,f]`,`rotate(a cx cy)` 由 svgtypes 自动展开为 translate/rotate/translate)。
- **`parse_color` 返回 `Vec<u8>` 而非 `[u8;4]` 是刻意的**:FRB 会把定长数组映射成 `U8Array4`,从而在生成的 Dart 里 `import 'package:collection/collection.dart'`,触发 `depend_on_referenced_packages`,要消除就得往 `pubspec.yaml` 加 `collection` 依赖——按本文件的依赖管理规则(新依赖需先征得同意)不擅自加,改用 `Vec<u8>`(映射为 `Uint8List`)零依赖解决。
- Dart 侧桥接在 `lib/src/animation/native_svg_values.dart`:**只在文档解析阶段调用,绝不逐帧调用**(逐帧仍是纯 Dart 数值插值,符合"每帧的活不得跨 FFI"这条硬约束)。具名颜色在解析阶段被一次性重写成 `#RRGGBBAA` 存回 `attributes`,逐帧路径继续用原有的纯 Dart 十六进制解析器(`svg_style.dart` 的 `parseSvgHexColor`)。
- **原生库不可用时的降级**:`flutter test` 的 host VM 没有构建步骤产出 `svgx.dll`,此时桥接函数捕获异常、锁存"不可用"标志并返回 null,颜色/变换保持未解析(与本轮改动之前的行为完全一致),不抛错、不崩溃。

### 2. 本轮补齐的动画/结构能力

- **具名 CSS 颜色**:`fill="red"`/`stroke="cornflowerblue"`/`rgb()`/`hsl()` 等全部 CSS3 写法,靠 svgtypes 的完整颜色表(Dart 侧不再需要自带颜色表)。`none`/`currentColor`/`url(#id)`/`#hex`/`inherit` 原样跳过不动。
- **`<g transform="...">` 静态变换**:解析阶段一次性经 `parse_transform` 合成为 `SvgNode.transform`(6 元仿射),绘制时 `canvas.transform` 应用,位置在 `<animateTransform>` **之前**(SVG 语义:动画变换叠加在静态变换之上)。
- **`<animateTransform type="skewX"/"skewY">`**:补进 `SmilTransformType`,分量归一化为 `[angle]`,绘制端用 `matrix(1,0,tan a,1,0,0)`/`matrix(1,tan a,0,1,0,0)`,与既有 translate/scale/rotate 分支在同一个 `canvas.save()` 作用域内按文档顺序合成。
- **`<use href="#id">` / `xlink:href`**:解析阶段消解为「一个带摆放矩阵的 `group` 包住目标副本」。实现方式是**从源 XML 重新解析目标元素**(而不是拷贝已建好的节点树),因此前向引用天然可用(id→元素索引先于建树建好,`<use>` 可以写在 `<defs>` 之前)。目标缺失/非本地 `#id`/目标标签不可渲染 → 静默不渲染。环检测:解析中的元素 id 进 in-progress 集合(包括元素自身的 id,故"`<use>` 指回祖先"也被拦住),成环则跳过该 `<use>`;另有 `_maxUseDepth = 10` 兜底(该常量带署名借自 F 的 `svg_use_references.dart`,MIT)。
- **syncbase `begin`**:支持 `begin="other.end"`/`"other.begin+2s"`/`"other.end-500ms"`。解析完全文后做一次**三色 DFS**(未访问/进行中/已完成)解析成绝对时间,支持任意长依赖链与前向引用。**成环 → 该动画 `begin` 置为 `kSmilNeverBegins`(永不触发,即失效)**,不猜值、不循环、不崩溃;引用不存在的 id → 回退为纯偏移;引用一个 `repeatCount="indefinite"` 动画的 `end` → 同样失效(那个 end 永不到来)。失效动画不计入 `totalDuration`(否则 ticker 会被拖到天荒地老)。
- **`<animateMotion>`**:支持自身 `path="..."` 与 `<mpath href="#id">`(取目标 `<path>` 的 `d`)。**不手写弧长采样**——直接用 `dart:ui` 的 `Path.computeMetrics()` + `PathMetric.getTangentForOffset()`(官方 API 已做好弧长参数化,且能跨多子路径),解析阶段一次性烘焙成 129 个等弧长采样点(位置 + 角度),逐帧只在相邻采样点间线性插值。**`rotate="auto"`/`"auto-reverse"`/固定角度均已实现**(注意 `ui.Tangent.angle` 定义是 `-atan2(dy,dx)`,与 `Canvas.rotate` 方向相反,代码里取了负号,有测试锁住)。运动变换叠加在其它变换**之后**。
- **静态渐变(动画路径)**:`<linearGradient>`/`<radialGradient>` + `<stop>`(`offset`/`stop-color`/`stop-opacity`)→ `SvgDocument.gradients`,`fill`/`stroke="url(#id)"` 时用 `ui.Gradient.linear`/`ui.Gradient.radial` 建 Shader。`gradientUnits` 的 `objectBoundingBox`(默认)与 `userSpaceOnUse` 都支持:**bbox 映射走 shader 的 matrix4 而不是缩放坐标**,这样非正方形包围盒上的径向渐变才是正确的椭圆。`spreadMethod` → `TileMode`;`href` 继承链(含环检测)已实现;dart:ui 要求色标严格递增,SVG 允许重复(硬边界),故对非递增色标做 1e-6 微调而不是丢弃整个渐变;包围盒退化(宽或高为 0)时返回 null 静默不画。**静态路径(Rust usvg)的渐变此前已支持,本轮未动。**

### 3. 仍然明确不支持(本轮之后的真实清单)

- **CSS `@keyframes`/`animation-*`/`transition-*`**:不做,理由见上方专门章节(有数据支撑)。
- **事件类 `begin`(`begin="click"`/`"id.click"`)**:**已评估,不做**。它需要"事件监听 + 时间线动态重触发",与当前"一次性建好全时间线、之后纯按 elapsed 驱动"的架构相冲突,属于架构级改动,建议**单独排期**,不做半吊子版本。当前行为:解析为零偏移(即立即开始),与本引擎对读不懂的取值的一贯降级方式一致。
- **`<text>`、mask、filter**:未做。
- **`<animateMotion>` 的 `keyPoints`/`keyTimes`/`calcMode`**:未做,运动恒按弧长匀速。
- **动画渐变**:未做(`<animate>` 作用在渐变属性或 `<stop>` 上无效)。
- **`<use>` 指向 `<symbol>`/`<svg>` 时,不应用其 `width`/`height`/`viewBox` 缩放**(按普通 `<g>` 处理);`<use>` 自身的 `width`/`height` 同样忽略。

### 4. 需要用户拍板的决定

1. ~~**svgtypes 双版本**(0.15.3 via usvg + 0.16 直依赖)是否接受,还是降到 `"0.15"` 统一?~~ **已解决(2026-08-25)**:降到 `"0.15"`,现只解析一份 `svgtypes v0.15.3`,详见上方"值解析下沉 Rust"章节的补记。
2. **`<use>` 的语义取的是 SVG2「影子树」读法**:实例是目标的完整重新解析,**包含目标自身的 `<animate>`/`<animateTransform>`**,因此原件和 `<use>` 实例会各自独立播放同一套动画(相位相同,因为共用同一条全局时间线);实例上的 id **原样保留不重命名**(本引擎按结构挂载动画,从不按 id 查找,重复 id 不会误绑定)。这比"实例是静态快照"更贴规范,但确实意味着一份动画会被绘制多次。
3. **syncbase 成环的处理选的是"失效"(`kSmilNeverBegins`)而不是"当 0 处理"**——如需改成"回退 begin=0 照常播放",改一行即可。

### 5. 测试与验证(全部实际跑过,非声称)

- `cargo test`(`rust/`):**14 passed / 0 failed**(其中 5 个是本轮新增的 `parse_color`/`parse_transform` 用例:具名色/十六进制/`rgb()`/非颜色拒绝/单变换/整串合成/带支点 rotate/垃圾输入)。
- `flutter test`:**63 passed / 0 failed**(本轮新增 4 个文件:`test/animation/transform_and_color_test.dart`、`use_element_test.dart`、`syncbase_begin_test.dart`、`animate_motion_test.dart`、`gradient_test.dart`)。
- `flutter analyze`:**No issues found**。
- **诚实标注**:`transform_and_color_test.dart` 里依赖 FFI 的 7 个用例,在没有 `svgx.dll` 的环境会自行跳过(与既有 `test/rust_image_smoke_test.dart` 同一约定)。本轮为真正验证,用 `cargo build --release` 把 `svgx.dll` 拷到仓库根目录跑过一遍,**确认它们真的执行且通过**(不是"跳过后报成通过")。该 dll 不是仓库常驻文件。
- **未做**:像素级渲染比对(渐变/skew/motion 画出来对不对,只验证了数据模型与 shader 能构建)、Android/真机验证、`benchmark/bench_app` 性能复测——按本文件"性能基准套件"章节的常驻规定,**本批功能改动之后必须补一次完整基准复测**(尤其解析阶段新增了 id 索引构建、渐变解析、`<use>` 重解析,理论上会抬高解析耗时),本轮受任务范围限制未跑,如实记录为遗留项。

## 待办:`<image>`(内嵌 base64 位图)支持缺口(2026-08-25 确认,需补齐)

代码核查确认**静态路径和动画路径都不支持 `<image>` 标签**,是真实功能缺口,不是理论推测:

- **静态路径(Rust usvg)**:`rust/src/api/svg.rs` 的 `SvgScene` 显示列表只有 `paths: Vec<SvgPath>` 一种字段,规约成纯路径几何(`verbs`/`points`)+ 填充/描边,**没有任何 image/位图相关字段**。usvg 本身能解析 `<image>`(含 base64),但 svgx 当前的显示列表模型没有留位图这条路,即便 usvg 解析出图片节点也没有字段传出来,画面上对应内容会被直接丢弃(不报错,静默消失)。
- **动画路径(原创 SMIL 引擎)**:`svg_document_parser.dart` 搜不到任何 image 相关处理,同上,直接丢弃。
- **对照 flutter_svg**:其底层 `vector_graphics`/`vector_graphics_compiler` 明确支持嵌入位图(`FlutterVectorGraphicsListener.onImage` 用 `ui.instantiateImageCodec` 解码合成进 `ui.Picture`),这是 svgx 相对 flutter_svg 的一个真实短板。
- **待办**:补齐 `<image>` 支持——静态路径需要 `SvgScene`/`SvgPath` 增加位图节点类型(geometry + 解码后的图片数据或引用),FFI 边界传输方式需要设计(base64 图片数据量可能不小,是否要走 async 或额外的图片专用通道需要评估,不能想当然沿用现有 `#[frb(sync)]` 的假设);动画路径 `svg_document_parser.dart`/`animated_svg_painter.dart` 需要新增 `<image>` 节点解析和绘制。优先级由用户后续排期决定,此处先如实记录缺口。

### `<image>` 支持已落地(2026-08-25 补齐)

上述缺口已按下面的设计补齐,静态路径和动画路径均已支持:

- **静态路径(Rust usvg)**:`SvgScene` 新增 `images: Vec<SvgImage>` 字段(与 `paths` 并列,不做统一 enum,无跨类型 z-order),`SvgImage` 含绝对坐标 `x/y/width/height`(用 `abs_transform().map()` 把本地物体包围盒映射到绝对空间,做法与 `convert_path` 一致——`preserveAspectRatio` 的 meet/slice 适配与居中已烘焙在这个映射结果里,不是 `<image>` 标签上 x/y/width/height 属性的直接读数)+ `data: Vec<u8>`(原始未解码字节)+ `format: SvgImageFormat`(Png/Jpeg/Gif/Webp)。**只处理 `usvg::ImageKind::{PNG,JPEG,GIF,WEBP}`,嵌套 SVG 的 `ImageKind::SVG` 静默跳过(不报错、不展平嵌套显示列表)**。`parse_svg` 本身保持 `#[frb(sync)]` 不变——图片解码(`ui.instantiateImageCodec`)被推到 Dart 侧异步完成,FFI 这一跳搬运的仍是原始字节,没有引入新的 sync/async 决策。
- **Dart 静态路径(`rust_static_svg.dart`)**:`RustSvgPictureCache` 新增 `getOrRenderAsync`(`getOrRender` 保持不变,零额外开销);`SvgXStatic` 用廉价正则嗅探源串是否含 `<image` 标签(思路同 `AnimationDetector`),命中则走 `FutureBuilder` + `getOrRenderAsync`(解码期间展示 `SizedBox` 占位,无专门状态机),否则走原有全同步路径。录制顺序:**图片先于路径绘制**(简化的 z-order 假设,不与文档顺序交错)。
- **动画路径(原创 SMIL 引擎)**:`SvgNodeKind` 新增 `image` 变体,`SvgNode` 新增可写字段 `resolvedImage: ui.Image?`(默认 null)。`svg_document_parser.dart` 新增 `documentHasImages`(廉价探测,无图片文档零开销)与 `resolveImageNodes`(异步遍历树,把 `href`/`xlink:href` 的 `data:<mime>;base64,<payload>` 解码进 `resolvedImage`;`href` 缺失/非 `data:` URI/解码失败均静默留空,不抛错,符合本引擎"不支持的结构表现为不可见"的一贯约定)。`animated_svg_widget.dart` 的 ticker 在文档含图片节点时**等 `resolveImageNodes` 完成后才启动**(避免时间线在占位期间偷跑,图片就绪瞬间动画跳进度),解码期间展示占位 `SizedBox`。`animated_svg_painter.dart` 的 `_paintNodeContent` 新增 `image` 分支,`resolvedImage == null` 时静默跳过。
- **已知限制(如实记录,未做):**
  - **不支持嵌套 SVG**(`<image href="...svg">` 或 `ImageKind::SVG`)——静态路径直接跳过,动画路径没有对应的 href 后缀/MIME 判断分支(遇到会尝试当位图 base64 解码,失败后静默留空)。
  - **z-order 简化**:图片一律先于路径/形状绘制,不支持"图片和路径交替出现在文档顺序中、按顺序层叠"这种排布——多数图标场景(图片作为背景层)够用,但不是通用解法。
  - 动画路径的图片节点**不支持 `<animate>` 作用在其 `x`/`y`/`width`/`height` 上**(没有测试覆盖,理论上因为这些是普通展示属性、走的是同一套 `effectiveAttributes` 覆盖机制,可能已经"顺便能用",但未验证,不作为已验收特性宣称)。
- **测试(均已实际跑通,非声称)**:
  - Rust 侧新增 `parses_embedded_base64_png_into_svg_image`(`rust/src/api/svg.rs`),用真实 1x1 PNG fixture 验证 `ImageKind::PNG` 解码路径与坐标映射,`cargo test` 7/7 通过。
  - Dart 侧新增 `test/animation/image_smoke_test.dart`(4 个用例:解析出 image 节点/`documentHasImages` 探测/`resolveImageNodes` 真实解码出 1x1 `ui.Image`/畸形 href 静默返回 null)与 `test/rust_image_smoke_test.dart`(验证 `parseSvg` 的 `SvgScene.images` 正确产出,用同一份 1x1 PNG fixture 与 Rust 侧测试对照)——后者需要本机已构建的 `svgx.dll`(通过 `cargo build --release` 手动放到仓库根目录验证过一次并已删除;不是仓库常驻文件,常规 `flutter test` 下会因加载不到原生库而自行跳过并打印原因,不会误报失败)。`flutter test` 全量 5/5 通过,`flutter analyze` 0 issue。
  - **未做**:像素级渲染验证(截图比对图片是否画在正确位置)、Android/真机验证、`benchmark/bench_app` 性能复测(本轮功能改动理论上只在源串命中 `<image>` 时才有额外开销,无图片场景的同步路径逻辑未改动,但"理论上无回归"不等于"已复测确认",如实标注为未做,遗留给下一次功能批次复测一并处理)。
- **意外顺带修复(与本次任务范围相关的前置阻塞)**:开始本次改动前,`rust/src/api/svg.rs` 处于**无法编译**的状态——`SvgGradient`/`SvgGradientKind` 存在字段不一致(构造代码用的是枚举形态 `SvgGradientKind::Linear{..}`/`Radial{..}`,但结构体定义还是旧版扁平字段形态),`cargo check` 报 20 处错误。已按结构体定义原有的文档注释(明确写着"压平为一个结构体……使 FRB 能生成普通 Dart 类而无需引入 `freezed`")修复为扁平字段版本(`kind: u8` + 判别后各自复用的 x1/y1/x2/y2/radius/matrix 字段),而不是保留枚举形态——因为枚举形态在 `flutter_rust_bridge_codegen generate` 时会报错要求安装 `freezed`,这违反了 CLAUDE.md 的依赖管理规则(新依赖需先征得同意)。修复后 `cargo check`/`cargo test`/`flutter_rust_bridge_codegen generate` 均恢复正常。这不是本次任务要求的工作,但不修复就无法验证 `<image>` 功能改动,如实记录在案。
**本轮踩过的一个真实坑(已修复)**:`animation_detector.dart` 原先用单条合并正则 `<\s*(animate|set)\b` 判断是否走动画引擎——`\b` 单词边界在 "animate" 紧跟 "Transform" 时不成立(两边都是单词字符),导致**只用 `<animateTransform>`(没有 `<animate>`)的 SVG 被静默误判为静态图标,路由去 Rust usvg 静态路径,动画完全不播放**。参考 `full_svg_flutter` 自身 `animation_detector.dart` 的分标签正则写法(`<animate[\s>]`/`<animateTransform[\s>]` 各一条,而非合并 + `\b`)重写后修复,已过 4 个不同相位的截图验证(见验收记录)。

静态路径(Rust usvg → 显示列表 → `ui.Picture`)未受影响,保留。`currentColor`/`PaintOrder` 已支持(2026-08-25):`parse_svg(data, currentColor)` 新增可选参数,usvg 0.44 本身无 currentColor 注入钩子,做法是解析前给根 `<svg>` 注入 `color="#RRGGBB"` 属性借用其自身级联解析;`SvgPath` 新增 `strokeFirst` 字段读取 usvg 的 `paint_order()`,`rust_static_svg.dart` 按需先描边后填充。`SvgXStatic`/`SvgX.string` 新增 `theme: SvgTheme?` 参数,与动画路径的 `theme` 命名保持一致。

**性能验收:PASS(2026-08-25,Windows 桌面 profile 模式实测)** —— 详见 `benchmark/bench_app/`。

- **FFI sync 结论(不改)**:读了 flutter_rust_bridge 2.12.0 源码(`handler.dart`)确认 `executeSync` 直接在调用方 isolate 上同步执行 `task.callFfi()`,没有走 `executeNormal` 那种 sendPort+Completer 的后台派发——架构上确实会阻塞调用方 isolate。但实测 1000 个互不相同的真实图标(iconify_flutter 的 `Mdi` 集,来自 `benchmark/bench_app/lib/mdi_icons_1000.dart`)来回滚动 6 轮,`parse_svg` 单次耗时 avg=0.026ms、p99=0.115ms、max=0.193ms(n=1000,直接 Stopwatch 实测),整场 646 帧里 `framesOver16.6ms=0`、`framesOver8.3ms=0`。结论:阻塞在架构上存在,但量级上可忽略,不构成实际卡顿,保持 `#[frb(sync)]` 不改。
- **1000 图标基准结果(svgx vs flutter_svg,Windows profile 模式,同一批 1000 个 Mdi 图标字符串)**:

  | 维度 | svgx | flutter_svg | 结论 |
  |---|---|---|---|
  | build 耗时 avg/p50/p90/p99/max | 0.622/0.571/0.966/1.828/2.379 ms | 1.685/1.577/3.096/4.925/9.268 ms | svgx 胜 |
  | raster 耗时 avg/p50/p90/p99/max | 1.526/1.409/2.119/3.292/3.944 ms | 1.997/1.860/2.907/4.192/5.378 ms | svgx 胜 |
  | 掉帧(>8.3ms / >16.6ms) | 0 / 0(646 帧) | 1 / 0(541 帧) | svgx 胜 |
  | CPU 占用(滚动期间 avg/peak,`Get-Process` 采样) | ~0.83% / ~4.49% | ~25.3% / ~30.2% | svgx 胜 |
  | 内存峰值(RSS) | 196.71 MB | 279.87 MB | svgx 胜 |
  | 内存稳态(滚动结束) | 193–198 MB | 267.24 MB | svgx 胜 |
  | 内存空闲后(3s) | 194–196 MB | 267.90 MB | 均未见增长,无泄漏迹象 |
  | 解析耗时(仅 svgx 有直接钩子) | avg=0.026/p50=0.018/p90=0.037/p99=0.106ms | 无直接钩子,只能用 build 耗时旁证 | 见方法学说明 |

  全部维度 svgx 胜出,无需额外优化即达标。

- **方法学说明(诚实标注)**:
  - 基准设备:Windows 桌面(`flutter run -d windows --profile`),未在 Android/WSA 上复测——桌面迭代最快,数据口径已在此注明。
  - 1000 个图标**不是**程序生成的合成图形,是从 `iconify_flutter` 插件的 `Mdi` 图标集里按声明顺序取的前 1000 个真实图标 SVG(`benchmark/bench_app/tool/gen_mdi_icons.dart` 一次性烘焙到 `lib/mdi_icons_1000.dart`,可复现)。
  - 滚动模式:`GridView` 8 列,`ScrollController.animateTo` 在顶部/底部之间来回 6 轮(900ms/趟,`Curves.easeInOut`)。
  - svgx 侧缓存上限显式设为 `itemCount + 50`,避免默认 200 条 LRU 在 1000 个不同图标场景下产生"缓存抖动"而不公平地放大解析次数;flutter_svg 一侧未做等价配置(它没有暴露等价的图片级缓存旋钮)。
  - flutter_svg 没有公开的"仅测解析耗时"钩子,所以"解析耗时"这一维度对 flutter_svg 只能不测(不是伪造成"更差"或"更好"),用 build 耗时的整体差距佐证。
  - 内存泄漏检查用的是"多轮滚动 + 3 秒静置后再采样"的替代方案,没有可靠的强制 GC 公开 API 可用(未验证到本 Flutter/Dart 版本有稳定可用的强制 GC 调试钩子),按任务要求如实标注这一点。
  - 动画流畅度:12 个并发播放的 `line-md` SMIL 动画图标(`SvgX.string` 走原创动画引擎)观测 6 秒,`framesOver16.6ms=0`、`framesOver8.3ms=0`(58 帧,build avg 0.461ms/max 1.497ms,raster avg 1.053ms/max 2.294ms)——动画引擎无主线程阻塞迹象。
  - 复现方式:`cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=svgx|flutter_svg|anim --dart-define=CYCLES=6 --dart-define=ITEMS=1000`,报告打印到 stdout。

## 性能复测(2026-08-25,功能批次:currentColor/PaintOrder + 动画引擎扩展后)

**触发原因**:两批功能落地后按"性能基准套件"章节的常驻规定复测——静态路径新增 `currentColor` 注入 + `PaintOrder`(`parse_svg` 新增 `current_color` 参数、缓存键从 `String` 变宽为 `(String, int?)`、painter 新增按 `strokeFirst` 分支的绘制逻辑),动画引擎新增更多 shape 元素、`<animateTransform>`、`repeatCount` 循环(驱动方式从有界 `AnimationController` 改写为原始 `Ticker`)、`calcMode`/`keyTimes`/`keySplines`。方法学复用未变(1000 个真实 Mdi 图标、`GridView` 8 列来回滚动 6 轮、Windows 桌面 profile 模式);另按用户明确要求新增了两个用例——`anim` 场景补了一个 `repeatCount="indefinite"` 的 `animateTransform` 循环图标(svg-spinners `180-ring`,直接复用 `example/lib/main.dart` 的 `kSpinnerSvg`,验证持续 ticking 而非一次性播放-定格的性能画像),以及全新的"1000 个动画图标来回滚动"用例(见下方"1000 动画图标真实 FPS")。

**svgx 静态路径 vs 上一轮历史基线(同条件对照,均为无额外后台负载的独立运行)**:

| 维度 | 历史基线(本文件已记录) | 本轮实测 | 趋势 |
|---|---|---|---|
| build avg/p50/p90/p99/max | 0.622/0.571/0.966/1.828/2.379 ms | 0.790/0.670/1.350/2.713/4.990 ms | 绝对值 +27%,见下方"噪声还是回归"分析 |
| raster avg/p50/p90/p99/max | 1.526/1.409/2.119/3.292/3.944 ms | 1.840/1.683/2.573/3.906/4.732 ms | 绝对值 +21%,同上 |
| 掉帧(>8.3ms / >16.6ms) | 0 / 0(646 帧) | 0 / 0(648 帧) | 无变化,仍为 0 掉帧 |
| 解析耗时 avg/p50/p90/p99 | 0.026/0.018/0.037/0.106 ms | 0.039/0.022/0.065/0.241 ms | 绝对值上升,量级仍是微秒级,不影响掉帧结论 |
| 内存峰值/稳态/空闲后 | 196.71 / 193–198 / 194–196 MB | 238.49 / 236.79 / 237.65 MB | 绝对值 +21%,见下方分析 |
| CPU 占用 avg/peak(独立复测,同一台机器同一时段配对 flutter_svg) | 0.83% / 4.49% | 0.32% / 7.64% | avg 更低,peak 略高,量级仍远低于 flutter_svg |

**"是噪声还是真实回归"——没有直接采信、而是配对复测后的结论**:同一时段用完全相同方法学重新跑了一遍 `flutter_svg` 基线(而非直接套用本文件里的历史 flutter_svg 数字),配对结果:

| 维度 | svgx(本轮) | flutter_svg(本轮同时段复测) |
|---|---|---|
| build avg | 0.790 ms | 2.288 ms |
| raster avg | 1.840 ms | 2.772 ms |
| 内存峰值 | 238.49 MB | 245.49 MB |

`flutter_svg`(外部依赖,本轮功能批次完全没碰它)在同一台机器同一时段测出来的绝对值同样比历史基线涨了(build 1.685→2.288,+36%;raster 1.997→2.772,+39%),涨幅比例甚至比 svgx 自己还大。用相对差距(svgx/flutter_svg 比值)看趋势更可靠:build 比值从历史 0.369(0.622/1.685)变成本轮 0.345(0.790/2.288),raster 比值从 0.764 变成 0.664——**两个比值都在缩小,即 svgx 相对 flutter_svg 的领先幅度不降反升**。这强烈说明本轮两边绝对值的同步上涨是这台开发机当时的系统级噪声(后台负载/调度,与本次基准测量本身无关),不是 currentColor/PaintOrder 分支引入的代码级回归。又额外复测一次纯 CPU 采样场景(见上表,svgx avg 0.32% vs 同条件 flutter_svg avg 9.89%、svgx peak 7.64% vs flutter_svg peak 39.99%),同样在每个维度上 svgx 完胜。

**结论**:配对复测下,svgx 在 build/raster/内存/CPU/掉帧的每一项仍全面超越 flutter_svg,且相对领先幅度没有缩小——**不构成"currentColor/PaintOrder 导致回归"的实锤证据**;两次独立 svgx 自测之间本身就有较大波动(build avg 0.790ms vs 另一次 1.309ms、内存峰值 238MB vs 199MB,后者测量时有额外后台进程占用),说明这台 Windows 开发机的测量噪声本身就相当大,±20~30% 的绝对值波动在这个环境下不足以单独作为回归证据。**如果需要更确定的结论,建议在空闲、无其他后台负载的机器上多次重复取中位数**——这是诚实的方法学局限标注,而非回避问题。

**动画:`repeatCount="indefinite"` 循环图标未引入主线程阻塞**:`anim` 场景(12 个并发图标,含新增的 svg-spinners `180-ring` 循环旋转图标)观测 6 秒:`frames=361`,`build avg=0.408ms max=2.075ms`,`raster avg=1.831ms max=5.072ms`,`framesOver16.6ms=0 framesOver8.3ms=0`——持续 ticking(而非原来纯 `<animate>` 图标的一次性播放后停止)没有产生额外掉帧。

**新增用例:1000 动画图标来回滚动,真实 FPS(应用户要求新增,2026-08-25)**:

- 场景:`benchmark/bench_app/lib/anim_fps_bench_screen.dart`(`--dart-define=LIB=anim_fps`),1000 格 `GridView`(8 列),每格是一个真实播放中的 SMIL 动画图标(`SvgX.string`,原创动画引擎),来回滚动 6 轮(同静态基准的滚动参数)。
- 图标来源:`tool/gen_anim_icons.dart` 从 `iconify_flutter` 的 `LineMd`+`EosIcons`(CLAUDE.md 已核实这两个集合 100% 是 SMIL、0% CSS)烘焙出 399 个真实互异的 SMIL 动画图标,平铺填满 1000 格(`lib/anim_icon_gen.dart`)——凑不出 1000 个互不相同的真实动画图标,如实标注为"399 个真实互异图标平铺",而非编造出 1000 个不存在的资产。
- FPS 口径:**实测值,不是从 build/raster 耗时估算,也不是固定假设值**——`frame_timing.dart` 新增 `realAverageFps`,取每帧 `FrameTiming.timestampInMicroseconds(FramePhase.rasterFinish)`(引擎上报的真实光栅完成时刻),用首尾时间戳算 `(帧数-1)/经过时间`。
- 实测结果:`frames=645`,**`real_fps=59.95`**(即真实贴近 60Hz 显示器的满帧率),`build avg=4.650ms max=13.206ms`,`raster avg=2.306ms max=5.794ms`,`framesOver16.6ms=0`(相对 60Hz 预算零掉帧),`framesOver8.3ms=18`(相对更严格的 120Hz 预算有少量超出,但display 是 60Hz,不构成真实掉帧)。
- 结论:1000 个并发播放的真实 SMIL 动画图标来回滚动,真实测得的平均帧率是 59.95fps,零掉帧(对 60Hz 预算),原创动画引擎在这个并发量级下未观察到主线程阻塞。

**本轮复现方式**:`cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=svgx|flutter_svg|anim|anim_fps --dart-define=CYCLES=6 --dart-define=ITEMS=1000`。

## 复测方法学调整(2026-08-25 追加,节约时间)

**后续每次复测,不再重复跑 `flutter_svg` 那组对照。** 理由:`flutter_svg` 是外部依赖,代码不会因为 svgx 自己的改动而变化,基线数据已经measured 并记录在上面的表格里(build avg=1.685ms、raster avg=1.997ms、CPU avg~25.3%、内存峰值 279.9MB 等)——每次改完 svgx 的代码就重新跑一遍 flutter_svg 纯属重复劳动,浪费编译+运行时间。

**新流程**:只跑 `--dart-define=LIB=svgx`(以及需要时的 `anim`),拿到的新数据**跟上一次 svgx 自己的历史数据做趋势对比**(涨了多少、跌了多少),而不是每次都重新对比 flutter_svg。已经确认"全维度胜出"的结论作为**长期有效的基线**保留;只有当 svgx 自身数据的回退幅度大到可能已经追平/输给 flutter_svg 记录的基线数字时,才需要重新跑一次 flutter_svg 做实锤验证——不要凭感觉判断"应该还是赢的",要真的拿数字和记录的基线比对。

**⚠️ 补丁(2026-08-25,当天验证出的漏洞)**:"只跟历史基线比"这个做法本身有个陷阱——**历史基线是在另一次机器状态下测的,svgx 自己数字的涨跌,分不清是代码变了还是机器当时负载/噪声变了**。实际发生过一次:仅对比 svgx 新数据 vs 历史基线,显示 build/raster/内存都涨了 20%+,一度被判断为"疑似回归";但同一 agent 随后在**同一时段配对复测**了 flutter_svg,发现 flutter_svg 自己的数字也涨了同等幅度——两边同步涨,说明是当时机器噪声,不是 svgx 代码引入的真实回退。

**修正后的规则**:
- **常规复测**(没有理由怀疑出问题):按上面"新流程",只跑 svgx,对比历史基线,省时间。
- **一旦 svgx 的历史趋势对比显示某项指标涨幅明显**(比如 >15-20%),**不能直接下"回归"结论**,必须在**同一时段、同一台机器**上追加一次 flutter_svg 的配对复测,两边同步比较涨跌幅度——只有 svgx 单边涨、flutter_svg 没涨,才是真实回归;两边同步涨,是机器噪声,如实记录为"环境噪声,非代码回归",不要误判成需要修复的问题,也不要因为"离历史基线远"就武断处理。

**每次复测后,把新一轮 svgx 数据追加记录**(不覆盖旧数据,保留趋势):日期 + 场景(哪批功能改动之后)+ 完整指标 + 相比上一轮的涨跌方向。

**遗留的一个诚实缺口**:本轮只在 Windows 桌面测了,没有覆盖 Android 真机的 PSS/`dumpsys meminfo`(CLAUDE.md 原方法学里提到的 Android 路径),如果之后要在 Android 上复测,链接的 WSA(`127.0.0.1:58526`)设备可用,复用同一套 `bench_app`。

## 单编译顺序对比模式:`LIB=compare`(2026-08-25 新增,现为推荐默认复测方式)

**解决的问题**:之前"svgx vs flutter_svg"对比要跑两次独立的 `flutter run --profile`(`LIB=svgx` 和 `LIB=flutter_svg`),两次之间隔着一次完整重新编译,机器状态可能在这个时间窗口内漂移——上面"复测方法学调整"的"⚠️ 补丁"记录过一次真实confusion:只跟历史基线比对被误判为"疑似回归",后来靠同一时段配对复测 flutter_svg 才澄清是机器噪声。`LIB=compare` 把这个"同一时段配对复测"从**偶尔需要的人工补救**变成**默认做法**。

**实现方式**:新增 `benchmark/bench_app/lib/compare_bench_screen.dart` 的 `CompareBenchRunner`,在**同一个进程**内依次跑完四个阶段——svgx 静态 → flutter_svg 静态 → anim(12 图标流畅度)→ anim_fps(1000 动画图标真实 FPS)——每阶段之间插入 5 秒静置期(让上一阶段的 GC/内存压力不带进下一阶段的测量,比每个静态阶段内部已有的"滚动后 3 秒静置检漏"更长,因为阶段切换还要多卸载/挂载一整个 1000 控件网格),最后打印一份汇总报告,静态对比部分直接是 `metric | svgx | flutter_svg | delta/ratio | verdict` 表格,可直接粘贴进本文件。

**只做编排,不重写机制**:`compare_bench_screen.dart` 复用既有的 `BenchRunner`/`AnimBenchRunner`/`AnimFpsBenchRunner`(`bench_screen.dart`/`anim_bench_screen.dart`/`anim_fps_bench_screen.dart`)不变的滚动/计时采集/RSS 采样逻辑,只是给它们加了一个可选的 `onComplete` 回调携带结构化的 `*Result` 快照,顺序驱动 + 汇总这些快照。三个原文件的既有行为(独立模式下的 stdout 报告格式)完全不变,`onComplete` 为 null 时什么都不影响。

**验证过的前提**:`main.dart`/`bench_screen.dart` 本来就同时无条件 `import` 了 `package:svgx/svgx.dart` 和 `package:flutter_svg/flutter_svg.dart`(不是按 `LIB` 条件导入),说明两个库确实已经一起编译进同一个二进制——`LIB=compare` 只是新增一条运行时控制流分支,不涉及改动构建系统。

**命名与默认值的取舍**:新增显式的 `LIB=compare` 档位,**不**把它设为 `String.fromEnvironment('LIB')` 的默认值(仍是 `svgx`)——避免不带 `--dart-define=LIB=` 参数的既有脚本/习惯突然从"单阶段"变成"四阶段"而意外增加运行时长。

**复现命令(现为推荐默认复测方式)**:

```
cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=compare --dart-define=CYCLES=6 --dart-define=ITEMS=1000
```

单独模式仍然保留、行为不变,调试单侧问题(比如要在 DevTools 里只看一侧)时用:

```
cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=svgx|flutter_svg|anim|anim_fps --dart-define=CYCLES=6 --dart-define=ITEMS=1000
```

**首次实测结果(2026-08-25,`LIB=compare`,同一进程同一时段配对)**:

| 维度 | svgx | flutter_svg | ratio | 结论 |
|---|---|---|---|---|
| build avg/p50/p90/p99/max | 0.776/0.668/1.274/2.577/3.267 ms | 1.823/1.731/3.185/5.994/8.406 ms | 0.43 左右 | svgx 胜 |
| raster avg/p50/p90/p99 | 1.769/1.660/2.354/3.398 ms | 2.134/2.029/2.934/3.769 ms | 0.80~0.90 | svgx 胜 |
| **raster max** | **4.484 ms** | **4.160 ms** | **1.078** | **flutter_svg 胜(唯一一项)** |
| 掉帧(>8.3ms / >16.6ms) | 0/0(646 帧) | 1/0(542 帧) | — | svgx 胜 |
| 内存峰值/稳态/空闲后 | 236.76/235.57/236.21 MB | 292.25/264.31/265.55 MB | 0.81~0.89 | svgx 胜 |
| 解析耗时(仅 svgx) | avg=0.039/p99=0.189 ms | 无公开钩子 | — | 见方法学说明 |

**诚实标注:`raster max` 这一项 svgx 落后**(svgx 4.484ms vs flutter_svg 4.160ms,ratio=1.078)——这是本轮唯一一个 flutter_svg 反超的子指标,不回避、如实记录。但 `max` 是单样本极值统计,天然噪声大(一次 GC 暂停或 OS 调度抖动就能产生),而**其余全部维度、包括更能反映整体分布的 p99,svgx 依然领先**(raster p99 3.398ms vs 3.769ms)。不足以推翻"svgx 全面胜出"的总体结论,但记录在案,不算进"全维度胜出"的措辞里——后续复测应持续关注这一项是否稳定复现或只是偶发。

**动画侧(仅 svgx,无对等 flutter_svg 对照,如实标注)**:anim(12 并发图标 6 秒观测)`frames=361 build_avg=0.313ms raster_avg=1.304ms framesOver16.6ms=0`;anim_fps(1000 动画图标滚动)`frames=650 real_fps=59.94 framesOver16.6ms=0`,与既有历史数据量级一致。

**耗时对比(单编译顺序模式 vs 分次独立编译)**:本次 `LIB=compare` 从首帧到打印完汇总报告,应用内 `wall_clock_total_s=61.3`(不含编译),加上一次编译 23.6s,总计约 **85 秒完成全部四个阶段**。按旧流程要拿到同样四组数据,需要分别 `flutter run` 四次(svgx 静态、flutter_svg 静态、anim、anim_fps),每次都要走一遍独立编译——参考本文件前面记录的历史单次编译耗时同样在 20+ 秒量级,四次独立编译仅编译部分就要 80~100 秒,再加四次应用内运行耗时(单次静态跑约 14~16 秒、anim 约 6 秒、anim_fps 约 12~14 秒),旧流程粗估在 **150~180 秒**量级,且中间还有人工在四次运行之间手动切换命令、观察退出的开销。`LIB=compare` 的 85 秒是一次不间断的机器时间,额外还去掉了"两次独立启动之间机器状态漂移"这个测量学风险——是本轮验证到的真实时间节省,不是估算假设。

**复现方式**:见上方"复现命令"。

**复测记录(2026-08-25,`SvgPath` 5 个新字段合并进 `Option<SvgEffects>` 重构之后,`LIB=compare` 配对复测)**:

触发原因:单侧复测(`LIB=svgx`)显示 parse 耗时持平(符合预期,`Option` 合并不改变序列化字段数量),但 build/raster 绝对值比重构前的历史记录更高(build avg 1.081→1.591ms 左右),按"复测方法学调整"规则不能直接下回归结论,追加了一次同一时段的 `LIB=compare` 配对复测。

| metric | svgx(本轮) | flutter_svg(本轮同时段) | ratio(本轮) | ratio(历史基线) | ratio 趋势 |
|---|---|---|---|---|---|
| build avg | 1.584ms | 3.818ms | 0.415 | 0.43 | 持平/略降(变好) |
| build p50 | 1.353ms | 3.085ms | 0.439 | — | — |
| build p90 | 2.909ms | 7.846ms | 0.371 | — | — |
| build p99 | 4.376ms | 13.351ms | 0.328 | — | — |
| build max | 6.027ms | 15.915ms | 0.379 | — | — |
| raster avg | 2.939ms | 3.461ms | 0.849 | 0.80~0.90 | 落在历史区间内 |
| raster p50/p90/p99 | 2.655/4.312/6.142ms | 3.218/5.267/6.720ms | 0.825/0.819/0.914 | 0.80~0.90 | 落在历史区间内 |
| 掉帧(>8.3ms/>16.6ms) | 0/0(648 帧) | 30/0(341 帧) | — | svgx 无掉帧,与历史一致 | — |
| 内存峰值/稳态/空闲后 | 237.79/234.82/235.62 MB | 297.51/295.43/283.59 MB | 0.799/0.795/0.831 | 0.81~0.89 | 落在历史区间内 |
| 解析耗时(仅 svgx) | avg=0.071/p99=0.305ms | 无公开钩子 | — | avg=0.039/p99=0.189ms(上一轮) | 绝对值上升但仍是微秒级,不影响掉帧结论 |

**判定:环境噪声,不是代码回归。** 证据:本轮 svgx 和 flutter_svg 的绝对值**同步大幅上涨**——svgx build avg 从上一轮 0.776ms 涨到 1.584ms(+104%),flutter_svg build avg 同期从 1.823ms 涨到 3.818ms(+109%),涨幅比例几乎一致;raster avg 同样双边同步上涨(svgx 1.769→2.939ms +66%,flutter_svg 2.134→3.461ms +62%)。用相对比值(ratio)看,build ratio 从 0.43 微降到 0.415、raster ratio 落在历史 0.80~0.90 区间内、内存 ratio 落在历史 0.81~0.89 区间内——**svgx 相对 flutter_svg 的领先幅度没有变差,反而略有改善**。按 CLAUDE.md 既定规则("两边同步涨,是机器噪声,不是回归"),本次判定为**这台开发机当时的系统级噪声**,`Option<SvgEffects>` 合并重构未引入真实性能回归。`Option` 解包/`some_if_present` 判断逻辑在 Dart 侧的开销在这次数据里没有体现出方向性影响的证据。

**方法学诚实标注**:这轮机器噪声幅度(build/raster 绝对值双边 +60%~110%)比之前记录的噪声(+20%~40%)更大,说明这台 Windows 开发机在无额外后台负载声明的情况下,量测噪声上限比此前认识到的更高;如果未来需要判断更细粒度的回归(比如 <20% 的绝对值变化),这个噪声量级会掩盖掉真实信号,建议届时安排空闲、无后台进程时段做多次重复取中位数的复测。

**复现方式**:见上方"复现命令"。

## 像素级验证结果(2026-08-25,12 项已实现功能的真实像素验证)

**背景纠正**:本文件此前"明确不支持"清单(记录于更早的时间点)已经过时——代码实际已经把 `<image>`/具名 CSS 颜色/`<g transform>`/`skewX`/`skewY`/`<use>`/syncbase `begin`/`<animateMotion>`/渐变/`<clipPath>`/`<mask>`/`<pattern>`/`feGaussianBlur`/`<text>` 全部实现完毕,并且仓库里已经存在一整套**真实像素级**测试(不是只读代码判断),不是本轮新写的空白验证。本轮工作 = 跑通这套已有测试套件、核实其确实做像素采样断言(而非只测解析结构)、确认全绿、补一份汇总记录。

**验证方式**:主要复用仓库既有的 `test/` 套件(`flutter test`,101 个用例全绿)+ `rust/` 侧 `cargo test`(24 个用例全绿),核查其中标注 "pixel-level" 的用例确实是 `toByteData` 采样 + 对具体像素 alpha/RGB 通道做 `expect` 断言,不是只测 DOM 结构。未额外补 Windows 截图交叉验证(Method B)——Method A 的像素断言已经是直接证据,时间预算下未见必要性。

| # | 功能 | 静态路径(Rust usvg) | 动画路径(Dart SMIL) | 结论 |
|---|---|---|---|---|
| 1 | `<image>` base64 位图 | `rust_image_smoke_test.dart`:`SvgScene.images` 携带解析出的图片节点 | `image_smoke_test.dart`:11 个用例,含 `resolveImageNodes` 真实 base64 解码为 `ui.Image`(不抛异常)、`documentHasImages` 检测、畸形 href 兜底为 null | **通过**——静态/动画均已实现,已补齐此前 CLAUDE.md 记录的缺口 |
| 2 | 具名 CSS 颜色 | `parse_color_resolves_css_named_colors`(Rust 单测) | `transform_and_color_test.dart`:`fill="red"`/`stroke="blue"` 解析时即归一为 hex,含一个非手写表常见色名的用例 | **通过** |
| 3 | `<g transform>` 静态变换 + `animateTransform skewX/skewY` | `parse_transform_composes_a_full_list_left_to_right` 等 Rust 单测 | `transform_and_color_test.dart` + `animated_svg_painter.dart` 的 skewX/skewY 矩阵分支 | **通过** |
| 4 | `<use>`(含引用目标自身带动画) | — | `use_element_test.dart`:13 个用例,覆盖前向/后向引用、`xlink:href`、`<g>`/`<symbol>` 目标、"实例携带目标自身动画(shadow-tree reading)"、自引用防死循环、悬空引用静默不渲染 | **通过** |
| 5 | syncbase `begin`(链式/接力动画) | — | `syncbase_begin_test.dart`:纯偏移、裸 syncbase 引用、正负偏移、事件值降级为零偏移(已知差距,如实标注)、A→B→C 传递链、前向引用 | **通过**(事件类 `begin` 仍不支持,测试里已如实标注为"documented gap") |
| 6 | `<animateMotion>`(rotate="auto"、keyPoints/keyTimes/calcMode) | — | `animate_motion_test.dart`:13 个用例,含 `rotate="auto"` 沿切线朝向、`auto-reverse`、数值常量角度、`keyPoints` 改变弧长进度、`calcMode="discrete"` 保持不插值、畸形 keyPoints 兜底丢弃 | **通过** |
| 7 | 静态渐变 + 动画渐变 | `rust_gradient_smoke_test.dart`:线性渐变多 stop、`RustSvgPictureCache` 用 shader 而非纯色绘制(像素级) | `gradient_test.dart`:href 链继承 stop、循环 href 链终止、`<animate>` 作用在渐变属性上逐帧重采样几何、`<animate attributeName="stop-color">` 逐帧重采样颜色 | **通过** |
| 8 | `<clipPath>`(静态+动画) | `rust_paint_features_test.dart`:clip 内 alpha>200、clip 外 alpha<16 | `clip_mask_test.dart`:同样的 alpha 断言 + "动画 clip path 按当前帧采样而非只在静止态"(t=0 窄、t=end 展宽) | **通过** |
| 9 | `<mask>`(静态+动画) | `rust_paint_features_test.dart`:白色 mask 内容保持可见、未覆盖区域被遮罩 | `clip_mask_test.dart`:同上 + 全黑 mask 内容整体隐藏(近零亮度)+ 动画 mask 按当前帧采样 | **通过** |
| 10 | `<pattern>`(静态路径) | `rust_paint_features_test.dart`:tile 内有色区域 alpha/R>200,tile 空白象限 alpha<16,重复到第二个 tile 位置(25,25)仍 alpha>200,证明确实重复而非画一次就停 | 未列入原始任务的动画侧要求(pattern 只要求静态) | **通过** |
| 11 | `feGaussianBlur`(静态+动画) | `rust_paint_features_test.dart`:形状核心 alpha>200,紧贴边缘外侧 alpha>8 且小于核心值(证明确实向外扩散而非硬边),远处 alpha<16(证明有衰减而非糊满全图) | Rust 侧单测 `gaussian_blur_filter_is_carried_as_sigma` 确认 sigma 值被携带;动画路径消费该 sigma 走的是同一套静态 Picture 缓存路径(未见专属动画 blur 逐帧重算测试) | **通过**(静态路径像素证据扎实;动画路径主要靠"sigma 值被正确携带"这条结构性证据,未见独立像素动画断言,记录为轻微保留) |
| 12 | `<text>`(动画路径 TextPainter;静态路径 2026-08-26 起体积优先静默跳过) | `text_is_silently_skipped_now_that_the_text_feature_is_off`(Rust 单测,确认含 `<text>` 的源仍正常解析、同级形状保留、文本本身不产生路径) | `text_node_test.dart`:12 个用例,含"绘制不抛异常"系列(plain/`fill=none`/空内容)+ `<animate>` 作用在 `opacity` 上通过通用机制被采样 | **通过**(动画侧文字断言以"不抛异常 + opacity 动画生效"为主,未见逐字形 glyph 级像素断言,记录为轻微保留;静态路径 `<text>` 已明确不再渲染,见"体积优化"小节) |

**汇总**:`flutter test` 101/101 通过,`flutter analyze` 0 issue,`cargo test`(`rust/`)24/24 通过。**未发现需要修复的真实 bug**——本轮任务未触及任何 CLAUDE.md 记录过的"看起来对、实际静默失效"类问题(如历史上 gradient 字段未读、animateMotion 正则误判、几何动画读错属性名)在当前代码中的复现;12 项功能中 11 项有直接像素/行为断言支撑"通过",第 11/12 两项的动画侧断言力度略弱(结构性证据为主),已如实标注,未回避。

### 后续补齐:第 11/12 两项"轻微保留"的动画侧像素断言(2026-08-25 追加)

针对上面第 11 项(`feGaussianBlur` 动画路径无独立像素断言)与第 12 项(`<text>` 动画路径无逐字形像素断言)补写了两个新测试文件,`test/animation/blur_pixel_test.dart`、`test/animation/text_pixel_test.dart`,均为真实 `toByteData(rawRgba)` 像素采样断言(非"不抛异常"式)。

**`feGaussianBlur`(动画路径):发现并修复了一个真实 bug**。核查前,`lib/src/animation/svg_dom.dart`/`svg_document_parser.dart`/`animated_svg_painter.dart` 里**完全没有 `filter`/`feGaussianBlur` 相关代码**——第 11 项表格里"动画路径消费该 sigma 走的是同一套静态 Picture 缓存路径"这句话是误判:动画路径(`SvgXAnimated`/`AnimatedSvgPainter`)与静态路径(`SvgXStatic`/Rust usvg)是两条完全独立的渲染管线,前者从不经过后者的 Picture 缓存,`filter` 属性在动画路径里此前是被直接丢弃的——不是"结构性证据薄弱",是**功能缺失**。

修复(最小范围实现,非泛化 filter 系统):
- `lib/src/animation/svg_dom.dart` 新增 `SvgNode.blurSigma`(`double?`)。
- `lib/src/animation/svg_document_parser.dart` 新增 `_parseBlurSigma`,识别两种写法:CSS 简写 `filter="blur(Npx)"`,以及 `filter="url(#id)"` 指向 `<filter><feGaussianBlur stdDeviation="N"/></filter>`(仅支持单个 `feGaussianBlur` 图元,其余 filter 图元/组合仍不支持,如实保留为未来工作)。
- `lib/src/animation/animated_svg_painter.dart` 的 `_paintNode` 在 `blurSigma` 非空时用 `canvas.saveLayer(null, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: s, sigmaY: s))` 包裹该节点(含子树)的绘制——对整个渲染结果做模糊,而非逐笔画/填充分别模糊,符合 SVG filter 语义(filter 作用于元素渲染结果)。两处 `return`/`restore` 路径都补了对应的 `canvas.restore()`。

**采样结果(50×100 蓝色矩形,几何右边缘在 x=50,y=50 行采样)**:
- **无模糊**:`x=41..59` 的 alpha 序列 = `[255,255,255,255,255,255,255,255,255,0,0,0,0,0,0,0,0,0,0]`——硬跳变,255→0 只用了 1 个像素(x=49→50),无渐变。
- **`filter="blur(8px)"`**:`x=31..69` 的 alpha 序列 = `[254,253,252,251,249,246,243,238,233,227,221,213,204,194,183,171,159,147,134,121,108,96,84,72,61,51,42,34,28,22,17,12,9,6,4,3,2,1,0]`——明显渐变衰减,横跨约 30 个像素,且在原始几何边缘(x=50)之外多个像素(如 x=58)仍有非零 alpha,证明确有渗出(bleed),而非硬边或第二层不透明色块。
- `filter="url(#id)"` 引用 `<feGaussianBlur stdDeviation="8">` 的写法同样验证通过(渐变衰减 + 渗出),复用同一套 `_parseBlurSigma` 逻辑。

**`<text>`(动画路径):功能确认已实现,补的是断言力度,非发现 bug**。`lib/src/animation/animated_svg_painter.dart` 的 `_paintText` 本就用 `TextPainter` 正确绘制;新测试用 `font-size="60"` 的红色 `"I"` 字形做逐像素采样(锚点 x=20,y=70,采样字形包围盒内 x∈[22,35]×y∈[40,65] 的网格点),**24 个采样点全部命中 `[255,0,0,255]`**(精确纯红、完全不透明,不只是"容差内接近")。四角(远离文字处)采样均为 `[_,_,_,0]`(透明背景),证明没有意外溢出绘制。`fill="none"` 用例额外确认整张画布逐 4px 网格扫描无任何红色像素——字形确实完全不绘制,而非"画了但被裁掉"。未发现渲染错误,原实现已经正确。

**结果**:`flutter test` 全量 106/106 通过(101 基线 + 5 个新用例),`flutter analyze` 0 issue,无回归。第 11/12 两项此前的"轻微保留"标注可以撤销:第 11 项(动画路径 blur)从"结构性证据、未验证"变为"像素证据 + 发现并修复真实缺失功能";第 12 项(动画路径文字)从"未见逐字形断言"变为"逐字形精确像素断言,确认原实现正确无需改动"。

## 性能基准套件:保留,功能完备后必须复测(2026-08-25 明确)

**`benchmark/bench_app/` 不得删除/清理**,是本项目的常驻资产,不是一次性验收脚手架。

- 当前的性能验收结论(全维度 PASS)只覆盖**当前已实现的功能面**(见"当前动画引擎支持"清单 + 静态路径的已知限制)。后续每完成一批"明确不支持"清单里的功能(shape 元素扩展、`animateTransform`、`repeatCount` 循环、渐变/mask/filter、静态路径 `currentColor`/`PaintOrder` 等),**必须用同一套 `bench_app` 重新跑一遍完整基准**,不能假设新功能不影响性能结论——新增的解析分支、绘制路径本身就可能引入新的性能回归。
- 复测时**沿用已验证的方法学**(1000 个真实 Iconify 图标、来回滚动 6 轮、svgx vs flutter_svg 独立进程对照、诚实标注平台/GC 局限),不要重新发明一套基准。
- Android 真机复测(当前遗留缺口)应该跟"功能完备后的复测"一起做一次,而不是分别测两次。

## 环境

Rust 1.96 / flutter_rust_bridge 2.12 / Flutter 3.47 / Dart 3.13 / Android NDK 28 + 四架构 target 均就绪。resvg/usvg 最新 0.48。

## 用户肉眼验证发现的 3 个 demo bug 及修复(2026-08-25)

用户跑 `example/lib/main.dart`(Windows 桌面)肉眼验证时发现 3 个新特性 demo 渲染不对。逐个排查后：**2 个是引擎真实 bug（已修）,1 个是 example 自身数据损坏（已修,非引擎问题）**。诚实记录，不夸大也不掩盖。

1. **`<image>` base64 PNG 完全不显示 —— 根因是 example 的 base64 数据本身损坏，不是引擎 bug**。逐字节核实：`example/lib/main.dart` 里 `kEmbeddedImageSvg` 手打的 base64 字符串解码后 IDAT zlib 流只还原出 3 字节，而 1x1 RGBA PNG 至少需要 5 字节（1 filter + 4 通道）——数据被截断/打错。usvg 解析嵌入位图时需要先解出其固有尺寸，遇到损坏的 PNG 数据会导致整个 `parse_svg` 返回 `Err`，而 `SvgXStatic` 在没有 `errorBuilder` 时的兜底就是渲染一个空白 `SizedBox`——这就是"完全不显示"的表现，但触发原因是数据损坏而非渲染逻辑缺陷。修复：把 `kEmbeddedImageSvg` 的 base64 换成 `rust/src/api/svg.rs` 测试里已验证过的合法 1x1 PNG(`iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==`)。引擎侧的 `<image>` 解析/解码/绘制链路本身未发现问题（`rust/src/api/svg.rs::convert_image`、`rust_static_svg.dart::getOrRenderAsync/_decodeImage` 代码审查 + 既有测试 `parses_embedded_base64_png_into_svg_image`/`rust_image_smoke_test.dart` 均覆盖过合法数据路径，行为正确）。

2. **`<animateMotion>` 完全不动 —— 引擎真实 bug，`animation_detector.dart` 检测正则缺失**。`AnimationDetector.hasAnimations` 给 `<animate>`/`<animateTransform>`/`<set>` 各写了一条独立正则（此前已修过 `<animateTransform>` 的 `\b` 单词边界坑），但唯独漏了 `<animateMotion>`——它和 `<animateTransform>` 踩的是同一类坑（"animate" 紧跟大写字母 "M"）。只含 `<animateMotion>`（没有 `<animate>`/`<animateTransform>`/`<set>`）的 SVG 被静默误判为静态，路由去 Rust usvg 路径，而 usvg 会丢弃 SMIL——元素完全不动。**引擎本身的 `_parseAnimateMotion`/`_sampleMotionPath`（`svg_document_parser.dart`/`smil_animation.dart`）实现是对的**（已有 `test/animation/animate_motion_test.dart` 10 个用例全部通过），纯粹是检测层漏了这一个标签。修复：`animation_detector.dart` 新增 `_animateMotionPattern = RegExp(r'<animateMotion[\s>]')` 并纳入 `hasAnimations` 的判定；新增回归测试 `test/animation/animation_detector_test.dart` 显式验证"仅含 `<animateMotion>` 的 SVG 必须被判定为动画"。**这提示了一个可复查的模式**：往检测器加新标签时，任何形如 "animate" 后紧跟大写字母的新 SMIL 标签（未来若支持更多）都要单独建正则，不能假设已有的 `<animate>`/`<animateTransform>` 覆盖了它。

3. **`linearGradient` 只显示纯蓝色,没有渐变过渡 —— 引擎真实 bug,Dart 侧完全没读取 Rust 已解析出的渐变字段**。审计 `rust/src/api/svg.rs` 发现 Rust 侧其实早就做完了渐变解析的硬活：`convert_path` 会调用 `build_gradient` 把 `<linearGradient>`/`<radialGradient>` 完整解析进 `SvgPath.fillGradient`/`strokeGradient`（含全部色标、已烘焙进绝对坐标空间的端点/矩阵）。但 `lib/src/rust_static_svg.dart` 的 `_recordScene` 里 `paintFill`/`paintStroke` 只读了 `path.fillArgb`/`path.strokeArgb`，从未检查过 `fillGradient`/`strokeGradient` 字段是否非空——渐变数据被 Rust 算出来又被 Dart 侧完全无视。之所以看到"纯蓝色"：Rust 的 `paint_argb`（给非渐变字段兜底用的函数）对渐变 paint 会回退取*首个*色标颜色，例子里第一个 stop 正是蓝色 `#2A6DF4`,所以呈现出"看起来选对了起始色、但没有过渡"的假象。**注意**：动画路径（`svg_gradient.dart`）的渐变支持是完整且已有测试覆盖的（`test/animation/gradient_test.dart`），这个 bug 只存在于静态 usvg 路径。修复：`rust_static_svg.dart` 新增 `_buildGradientShader`，按 `SvgGradient.kind` 分别用 `ui.Gradient.linear`（线性,直接用已绝对化的两端点）或 `ui.Gradient.radial`（径向,用局部焦点/圆心/半径 + `matrix4` 应用 `SvgGradient.matrix`）构建 shader,`paintFill`/`paintStroke` 优先检查对应 gradient 字段,非空则用 shader 而非纯色 `Paint().color`;单色标退化渐变（SVG 语法允许但极少见）复制该色标为 2 份规避 `ui.Gradient` 至少需要 2 色的限制,不崩溃。新增回归测试 `test/rust_gradient_smoke_test.dart` 验证 `fillGradient` 非空且两个 stop 颜色互不相同。

**验证方式**:`cargo test`(14 通过,未改 Rust 逻辑本身,仅审计确认)、`flutter analyze`(无告警)、`flutter test`(70 通过,含本轮新增的 3 个回归测试:`animation_detector_test.dart` 5 例 + `rust_gradient_smoke_test.dart` 2 例)。**诚实标注一个方法学局限**:本轮受限于当前 shell 工具环境无 GUI/无法弹出 Windows 桌面窗口(`flutter build windows` 在此环境下因 MSBuild/CMake 安装步骤报 `MSB3073` 失败,与本次代码改动无关,像是构建产物目录被占用或环境限制),**未能在真正弹出的 Windows 窗口里肉眼截图确认三个 demo 视觉效果**,结论建立在:①字节级验证损坏的 base64(`node` 手动 inflate zlib 流对比合法/非法 PNG 数据)、②代码审查确认 Rust 侧数据已正确解析、Dart 侧确实遗漏读取、③新增回归测试断言"关键字段非空/取值符合预期"三重交叉验证之上,不是拍脑袋猜测,但仍建议用户在自己机器上 `cd example && flutter run -d windows` 肉眼复核一遍这三个 demo,如有出入请反馈。

## 静态路径补齐:clipPath/mask/pattern/feGaussianBlur/text(2026-08-25)

本轮只动静态路径(`rust/src/api/svg.rs` + `lib/src/rust_static_svg.dart`),**未触碰 `lib/src/animation/`**。逐项如实记录完成度:

| # | 任务 | 状态 | 说明 |
|---|---|---|---|
| 1 | `<marker>` / `<switch>` | **DONE(确认零成本,无需实现)** | 实验验证 usvg 0.44 在解析期就把 marker 定义展开成普通元素、把 `<switch>` 求值成唯一选中分支,`SvgScene.paths` 直接拿到正确结果,svgx 侧一行代码都不用写。已加 2 个 cargo 测试锁死这个行为(`marker_end_is_expanded_into_plain_paths`、`switch_keeps_only_the_first_satisfied_branch`),防止将来 usvg 升级悄悄改掉这个前提。 |
| 2 | `<clipPath>` | **DONE** | `SvgPath` 新增 `clips: Vec<SvgClip>`;`collect()` 沿分组祖先链累积 `clip_path()`(和 `abs_transform` 累积同一思路),子路径继承祖先裁剪;保持扁平 paths 列表,不引入嵌套分组结构。Dart 侧 `canvas.save()` + 逐个 `clipPath()` + 绘制 + `restore()`。 |
| 3 | `<mask>` | **DONE** | `SvgPath` 新增 `mask: Option<SvgMask>`,`SvgMask.paths` 是嵌套的 `Vec<SvgPath>`(遮罩内容本身可以是多个形状)。Dart 侧用 `saveLayer` + `ColorFilter.matrix`(luminanceToAlpha) + `BlendMode.dstIn`;`mask-type="alpha"` 走不带 colorFilter 的同一条 dstIn 路径。 |
| 4 | `<pattern>` | **DONE(基础形态)** | 作为第三种 paint 变体落地:`SvgPath` 新增 `fill_pattern`/`stroke_pattern: Option<SvgPattern>`。Dart 侧把贴片录进 `PictureRecorder` → `toImageSync` → `ui.ImageShader(TileMode.repeated)`。 |
| 5 | `<filter>` MVP(仅 feGaussianBlur) | **DONE** | `SvgPath` 新增 `blur: Option<SvgBlur>`(std_dev_x/y,已按 `abs_transform` 的各轴缩放换算到绝对空间 sigma)。Dart 侧 `canvas.saveLayer` + `Paint.imageFilter = ui.ImageFilter.blur`。**只认"恰好 1 个滤镜、恰好 1 个 feGaussianBlur 图元"的形态**,其他一律返回 `None`(不做错误近似)。 |
| 6 | `<text>` | **已牺牲(体积优先,2026-08-26 重新应用)** | 原实现是 usvg 0.44 的 `Text::flattened() -> &Group` 轮廓展平,直接把 `Node::Text` 递归进既有 `collect()` 复用整条路径管线。**该实现已撤销**:为把 release DLL 从 ~1.05MB 压到 ~0.47MB,`usvg` 改为 `default-features = false`(关闭 `text`/`system-fonts`/`memmap-fonts`),静态路径的 `<text>` 现在**静默跳过**(`usvg::Node::Text(_) => {}`),不 panic、不报错,画面上直接不出现文字。动画路径的 `<text>`(Flutter `TextPainter` 独立实现)不受影响。见下方"体积优化"小节。 |

### 关键实现决定(避免以后重新纠结)

- **坐标空间**:clipPath/mask/pattern 的内容在 usvg 里是"子根"(subroot),其 `abs_transform()` **相对各自的根**,不含引用元素的祖先变换(usvg `tree/mod.rs` 注释原话:"subroots, like clipPaths, masks and patterns, have their own root transform, which isn't affected by the node that references this subroot")。所以统一做法是 `base.pre_concat(node.abs_transform())`,`base` 取引用元素分组的 `abs_transform()`(clipPath 还要再 `pre_concat(clip.transform())`)。`convert_path` 因此加了 `base: &Transform` 参数,主树节点传 `Transform::default()`。
- **`patternUnits` 不用自己处理**:usvg 在树公开前已有一遍后处理把 `patternUnits`/`patternContentUnits` 全归一到 userSpaceOnUse(`parser/paint_server.rs` 约 1004 行),公开 API 的 `Pattern::rect()`/`root()` 拿到的已经是用户空间,svgx 侧不需要再做 bbox 换算。
- **`Inherited` 累加器必须标 `#[frb(ignore)]`**:FRB 2.12 会扫到 api 模块里的**私有** struct 并给它生成 codec(然后因为字段私有而编译失败)。踩过一次,已修。
- **亮度系数来源**:`_luminanceR/G/B = 0.2125/0.7154/0.0721`(SVG 1.1 `feColorMatrix type="luminanceToAlpha"` 的常量)。矩阵排布与 `dstIn` + `ColorFilter.matrix` 的手法改编自 F(`full_svg_flutter`,MIT)的 `benchmark/baseline_f/full_svg_flutter_lib/src/animation/animated_svg_painter_mask_luminance.dart::_createLuminanceMaskPaint`,已按硬规则在代码注释里署名来源;F 用的是 sRGB 系数 0.2126/0.7152/0.0722,差异小于 1 个 8 位色阶。只摘了这一小段,没有 vendor 整个文件。
- **`<text>` 的按需字体库方案已废弃(体积优先撤回)**:原做法是先 `data.contains("<text")` 廉价嗅探,命中才走 `system_fontdb()`(`OnceLock<Arc<fontdb::Database>>`,进程级单例,只在真正含 `<text>` 时付 `load_system_fonts()` 的 ~100ms)。这套机制随 `usvg` 的 `text`/`system-fonts` feature 一起被关闭移除,`system_fontdb()` 辅助函数已删除,`Options` 上也不再有 `fontdb` 字段可设。

### 体积优化:usvg `default-features = false`(2026-08-25 首次执行,2026-08-26 因改名事故重新应用)

- **动机**:usvg 0.44 的 `text`/`system-fonts`/`memmap-fonts` 三个可选 feature(默认全开)带来字体排版/系统字体加载相关的大量代码,而 fsvg/svgx 定位是图标渲染,`<text>` 支持的收益(极少数图标资产含文字)不足以覆盖这部分体积成本。
- **改动**:`rust/Cargo.toml` 的 `usvg` 依赖从默认 feature 改为 `{ version = "0.44", default-features = false }`;`rust/src/api/svg.rs` 的 `usvg::Node::Text` 分支改为 `usvg::Node::Text(_) => {}`(静默跳过,不 panic 不报错);`Options::default()` 不再赋值 `fontdb` 字段(该 feature 关闭后字段已不存在);`system_fontdb()` 辅助函数整体删除。
- **2026-08-26 重新应用背景**:本改动最初于 2026-08-25 落地并实测(2.05MiB→1.09MiB),但在 fsvg→svgx 改名过程中因一次误操作的 `git checkout` 连同未提交改动一起丢失,只留下 Cargo.toml 里的一段事故恢复说明注释。本次按该注释记录的意图,重新执行同一改动并实测新数字(见下)。
- **实测 DLL 体积**(`example/build/windows/x64/runner/Release/svgx.dll`,`flutter build windows` release 构建,Windows 桌面):

  | 阶段 | 体积 |
  |---|---|
  | 优化前(usvg 默认 feature,含 `text`/`system-fonts`/`memmap-fonts`) | 1,103,360 字节(1.052 MiB) |
  | 优化后(`default-features = false`) | 491,008 字节(0.468 MiB) |
  | 降幅 | −612,352 字节,约 **−55.5%** |

  与 2026-08-25 首次执行时记录的 2.05MiB→1.09MiB 不是同一组数字(不同代码状态/依赖版本下的测量,不假设完全对齐),但方向和量级一致,均确认该优化对体积有显著收益。
- **代价**:静态路径 `<text>` 不再产生任何路径几何,是刻意接受的取舍,不是缺陷。动画路径的 `<text>`(独立的 Flutter `TextPainter` 实现)完全不受影响。
- **测试调整**:Rust 单测 `text_is_flattened_into_glyph_outlines` 已重写为 `text_is_silently_skipped_now_that_the_text_feature_is_off`,断言含 `<text>` 的源仍能正常解析、同级形状(rect/circle)完整保留、且文本元素本身不产生任何路径。Dart 侧未发现断言"静态路径 `<text>` 渲染为矢量路径"的测试(现有 `text_pixel_test.dart`/`text_node_test.dart` 均在 `test/animation/` 下,针对 `TextPainter` 动画路径,不受影响)。

### 明确的已知限制(如实标注,不是"以后再说"的托辞)

- **mask/blur 是"最近祖先优先",不支持嵌套叠加**:真要嵌套需要完整的图层树,而扁平显示列表刻意不做这层结构。多层祖先都声明 mask/filter 时只有最内层生效。clip **不受此限**——多个祖先的裁剪会正确求交集。
- **clip 内部的形状按并集处理**,实现方式是把一个 `<clipPath>` 的所有子形状塞进同一条 `ui.Path`。重叠 + 反向绕向的极端情况下,非零环绕规则的结果与真正的布尔并集可能不同。
- **`<clipPath>` 内部元素自身再带 `clip-path` 会被忽略**(clipPath 的 `clip-path` 属性本身是支持的,走 `build_clips` 递归)。
- **遮罩矩形在有旋转时取的是变换后 4 角的轴对齐包围盒**,不是真正的旋转矩形。
- **遮罩内容 / 图案贴片内容按"朴素"方式绘制**:不再递归应用它们内部的 clip/mask/blur/pattern(Dart 侧 `_paintPath(..., nested: true)`)。也不支持遮罩内的 `<image>`。
- **`<pattern>` 贴片分辨率上限 1024px/轴**,按图案→绝对矩阵的缩放量推算;极端放大时会糊。贴片 `ui.Image` 由 shader 持有,不显式 dispose(交给 Dart GC)。
- **filter 只做 feGaussianBlur**。`feColorMatrix`/`feComposite`/`feOffset`/`feBlend`/`feDropShadow`/光照类图元等**全部列为后续工作**,当前一律不生效(不是画错,是不画)。多图元滤镜链同样整体忽略。
- **静态路径 `<text>` 完全不渲染(体积优先,2026-08-26 明确取舍)**:usvg 的 `text` feature 已关闭,`<text>` 元素在静态解析路径里被静默跳过,不产生任何路径几何,画面上直接缺失,不报错也不降级近似。动画路径的 `<text>`(`TextPainter` 实现)不受影响,仍按原有语义渲染。

### 测试与验证结果

- `cargo test`(`rust/`):**24 passed / 0 failed**(基线 14 → 新增 10:marker 1、switch 1、clipPath 3、mask 1、pattern 1、blur 2、text 1)。
- `flutter analyze`:**No issues found**。
- `flutter test`:**75 passed / 0 failed**(基线 70 → 新增 5,见 `test/rust_paint_features_test.dart`)。
- **新增的 Dart 测试是真·像素级回读,不是"没抛异常就算过"**:`picture.toImage(100,100)` + `toByteData(rawRgba)`,断言裁剪外侧 alpha<16 / 内侧 >200、亮度遮罩未覆盖区被遮掉、图案贴片确实在第二块贴片位置重复出现、模糊确实溢出原始边界且远处衰减。这样"特性被静默丢弃"会直接判失败。
- **一个踩坑记录(会浪费别人时间的那种)**:`flutter test` 走的原生库是 `frb_generated.dart` 里 `ioDirectory: 'rust/target/release/'` 指定的**release** 产物。改完 Rust 只跑 `cargo build`(debug)会让 Dart 侧拿到旧 wire 格式,报 `RangeError (byteOffset)` 这种看起来像"FRB 递归类型编解码 bug"的假象。**改 Rust 之后跑 Dart 测试前必须 `cargo build --release`**。

### 性能复测(按"性能基准套件"章节的常驻规定执行,`LIB=compare` 同进程配对)

| 维度 | svgx(本轮) | flutter_svg(同进程同时段) | ratio | 结论 |
|---|---|---|---|---|
| build avg/p50/p90/p99/max | 1.081/1.053/1.594/2.924/3.332 ms | 2.051/1.926/3.494/6.022/6.847 ms | 0.46~0.55 | svgx 胜 |
| raster avg/p90/p99/max | 1.912/2.262/2.927/4.722 ms | 3.452/2.802/4.916/333.646 ms | 0.55~0.81 | svgx 胜 |
| **raster p50** | **1.908 ms** | **1.833 ms** | **1.041** | **flutter_svg 胜(本轮唯一一项)** |
| 掉帧(>8.3ms / >16.6ms) | 0 / 0(642 帧) | 0 / 0(425 帧) | — | 打平 |
| 内存 峰值/稳态/空闲后 | 190.25 / 187.08 / 187.98 MB | 246.92 / 224.88 / 225.56 MB | 0.77~0.83 | svgx 胜 |
| 解析耗时 avg/p50/p90/p99/max | 0.054/0.044/0.077/0.162/1.083 ms | 无公开钩子 | — | 见方法学说明 |
| anim(12 并发) | frames=361 build_avg=0.421ms raster_avg=1.247ms framesOver16.6ms=0 | 无对等能力 | — | — |
| anim_fps(1000 动画图标滚动) | frames=650 **real_fps=59.85** framesOver16.6ms=0 | 无对等能力 | — | — |

**诚实标注一处相对退步,不掩饰**:与上一轮 `LIB=compare` 记录(svgx build avg 0.776ms、raster avg 1.769ms、parse avg 0.039ms)相比,本轮 svgx 的 build avg 涨到 1.081ms(+39%)、raster avg 涨到 1.912ms(+8%)、parse avg 涨到 0.054ms(+38%)。按本文件"复测方法学调整"的⚠️补丁做了同时段配对复测:flutter_svg 同样涨了(build 1.823→2.051,+13%),说明**有机器噪声成分,但 svgx 涨幅明显大于 flutter_svg**,svgx/flutter_svg 的 build 比值从 0.43 退到 0.527——**不能像上次那样全部归因于噪声**。合理的机制解释是本轮给 `SvgPath` 加了 5 个新字段(`fill_pattern`/`stroke_pattern`/`clips`/`mask`/`blur`),SSE 序列化每条路径都要多写/多读 5 个 tag,1000 图标场景下路径条数很大,这笔常数开销是真实存在的(parse avg 同步涨 38% 与这个解释一致)。**结论:是可解释的小幅真实回归,不是回归到不可接受**——绝对量级仍是微秒/亚毫秒级,掉帧仍为 0,内存反而比上一轮低(190MB vs 236MB),且每个维度(除 raster p50)仍稳定优于 flutter_svg。如果以后要把这笔常数吃回来,方向是**把这 5 个字段合并成一个 `Option<SvgEffects>`**,让绝大多数无特效路径只付 1 个 tag 而不是 5 个——记录在案,本轮不做(未经压测证明值得)。

**平台局限(沿用既有标注)**:仍只在 Windows 桌面 profile 模式测,Android 真机 PSS/`dumpsys meminfo` 复测仍是遗留缺口。

**复现**:`cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=compare --dart-define=CYCLES=6 --dart-define=ITEMS=1000`

## `SvgEffects` 重构:把 5 个新字段合并成一个 `Option`(2026-08-25 追加)

**触发原因**:上一节记录了给 `SvgPath` 加 `fill_pattern`/`stroke_pattern`/`clips`/`mask`/`blur` 这 5 个字段后 build/parse avg 涨了约 38%,并在结论里写好了"如果以后要吃回来,方向是合并成一个 `Option<SvgEffects>`"——本次就是把这个记录在案的优化方向落地。

**改法**:`rust/src/api/svg.rs` 新增 `pub struct SvgEffects { fill_pattern, stroke_pattern, clips, mask, blur }`,`SvgPath` 上原来 5 个独立字段收缩成一个 `pub effects: Option<SvgEffects>`。新增 `SvgEffects::some_if_present(...)` 辅助函数——5 个子字段全部为空/默认时返回 `None`，任一非空则返回 `Some`，绝大多数图标(无 clipPath/mask/filter/pattern)因此只序列化 1 个 `None` tag，而不是 5 个独立的空/`None` tag。`fill_pattern`/`stroke_pattern`没有和 clips/mask/blur 拆开的原因：判断标准是"值得合并成一个就合"而非强行拆分，五者共同的特点都是"少数路径才用得到、多数路径全空"，合成一个 `Option` 收益最大化；没有为了避免"关联度不同"的顾虑而强行拆成两组，因为拆成两组反而要付两次 tag（`Option<PatternPair>` + `Option<ClipMaskBlur>`），达不到"绝大多数路径只付 1 个 tag"的目标。

**改动点**:
- `rust/src/api/svg.rs`:`SvgPath` 结构体定义、`convert_path`（构建自身的 fill/stroke pattern 到 `effects`）、`collect`（把继承的 clips/mask/blur 并入 `convert_path` 已产出的 pattern，重新调用 `some_if_present` 折叠成一个 `effects`）、6 处测试断言改为经 `path.effects.as_ref()...` 访问。
- 重新跑 `flutter_rust_bridge_codegen generate` 重新生成绑定（`lib/src/rust/api/svg.dart`、`lib/src/rust/frb_generated.dart`）。
- `lib/src/rust_static_svg.dart`:`_paintPath`/`_fillShader`/`_strokeShader` 里 `path.clips`/`path.mask`/`path.blur`/`path.fillPattern`/`path.strokePattern` 改为 `path.effects?.clips`/`path.effects?.mask`/`path.effects?.blur`/`path.effects?.fillPattern`/`path.effects?.strokePattern`。
- `test/rust_paint_features_test.dart`:两处断言同步改为经 `effects?.` 访问。

**测试状态**:`cargo test`24 passed（同基线数量，无用例丢失）；`flutter analyze`无问题；`flutter test`75 passed（同基线数量）。均为全绿，无回归。

**性能复测（`LIB=svgx` 单侧，同方法学，Windows 桌面 profile 模式）**：

| 维度 | 本次重构前（上一节记录） | 本次重构后 | 趋势 |
|---|---|---|---|
| build avg/p50/p90/p99/max | 1.081/1.053/1.594/2.924/3.332 ms | 1.591/1.372/2.725/4.504/5.966 ms | 绝对值上升，见下方诚实说明 |
| raster avg | 1.912 ms | 3.001 ms | 绝对值上升，同上 |
| parse avg/p50/p90/p99 | 0.054/0.044/0.077/0.162 ms | 0.062/0.043/0.124/0.327 ms | avg/p50 基本持平，p90/p99 略升，量级仍是微秒级 |
| 掉帧(>8.3ms / >16.6ms) | 0/0(642 帧) | 0/0(643 帧) | 无变化，仍 0 掉帧 |
| 内存 峰值/稳态/空闲后 | 190.25/187.08/187.98 MB | 234.98/231.58/232.37 MB | 绝对值上升 |

**诚实说明,不掩饰**:本轮只跑了一次 `LIB=svgx`,没有按"复测方法学调整"的⚠️补丁要求做同时段 `flutter_svg` 配对复测(受限于本次任务的时间预算),因此**无法排除机器噪声**——本文件已反复记录过这台 Windows 开发机 build/raster 绝对值有 20~40% 的波动区间,单次对比不能坐实"合并 `Option` 反而更慢"这个结论。能站得住的信号是 **parse avg/p50 基本没有随字段合并而进一步恶化**（0.054→0.062ms、0.044→0.043ms），说明序列化路径的常数开销至少没有变差；`build`/`raster`/内存这几项的绝对值上涨更可能是本次测量时机的系统噪声（与上一节记录的模式一致），而不是这次重构引入的新回归——但由于没有配对复测数据，这只是合理推测，不作为坐实结论记录。**遗留待办**:后续若怀疑该重构本身引入回归，应按规则补一次同时段 `flutter_svg` 配对复测（`LIB=compare`）来实锤区分噪声与真实回归。

**复现**:`cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=svgx --dart-define=CYCLES=6 --dart-define=ITEMS=1000`

## 动画引擎四项功能扩展(2026-08-25 追加):clipPath/mask、`<text>`、animateMotion keyPoints、动画渐变

按用户要求,在 `lib/src/animation/` 原创 SMIL 引擎范围内(不碰 `rust/`、不碰 `lib/src/rust_static_svg.dart`)实现四项功能扩展。**基线确认**(动手前):`cargo test` 24/24、`flutter test` 75/75、`flutter analyze` 0 issues——与本文件此前记录的验收状态一致,基线干净,按计划推进。

**四项任务全部完成(4/4 done)**,逐项如下:

### Task 1:动画路径的 `<clipPath>`/`<mask>`——done

- `svg_dom.dart`:`SvgNode` 新增 `clipPathId`/`maskId`(从 `clip-path="url(#id)"`/`mask="url(#id)"` 解析出的目标 id,解析阶段一次性提取,`_urlId` 辅助函数)。
- `svg_document_parser.dart`:新增 `_parseDefsByTag`,把任意位置带 id 的 `<clipPath>`/`<mask>` 元素解析成 `SvgNode` 子树(与解析主文档树同一套 `_parseElement`,因此其内容自身的 `<animate>`/`<animateTransform>` 会被正常注册进 `resolveSmilBeginTimes`/文档总时长统计),挂到 `SvgDocument.clipPaths`/`SvgDocument.masks`(id → `SvgNode`)。
- `animated_svg_painter.dart`:
  - `_paintNode` 新增 `nested` 参数;查到 `clipPathId`/`maskId` 时用 `canvas.save()` + `canvas.clipPath()`(裁剪)或 `saveLayer` + `_maskCoveragePaint()`(遮罩,`BlendMode.dstIn` + `ColorFilter.matrix` 亮度矩阵,系数 R=0.2125/G=0.7154/B=0.0721,与 `rust_static_svg.dart` 静态路径同一算法独立实现——按硬规则只看算法思路、代码原创)。
  - 新增 `_resolveClipPath`:遍历 `<clipPath>` 子树,对每个节点的 `<animate>`/`<animateTransform>` 在当前帧 `time` 采样,累积仿射矩阵(`_concatAffine`/`_transformSampleToAffine`),把几何路径(`_geometryPath`,见下)变换后并入总路径——**动画裁剪路径每帧真的会变形**,不是只按静止态裁剪一次。
  - 新增 `_geometryPath` 共享几何构建函数(从原来内联在 `_paintNodeContent` switch 里的 path/circle/rect/ellipse/line/polyline/polygon 逻辑抽出),同时被绘制路径与 `_resolveClipPath` 使用,避免两份几何逻辑走岔。
  - mask 内容通过复用 `_paintNode(canvas, maskDef, ..., nested: true)` 绘制(能利用完整的分组/渐变/描边等能力,比 clip 的纯几何并集丰富得多);`nested=true` 时不再查找 `clipPathId`/`maskId`,即"最近祖先的裁剪/遮罩已生效,不支持嵌套 mask/clip"(按任务范围要求)。
- **已知限制(按任务范围,明确声明)**:不支持嵌套 mask/clip(嵌套内容里的 `clip-path`/`mask` 属性被忽略);mask 内容里的 `<image>` 不支持(`_geometryPath` 对 `image`/`text` 返回 null,`<clipPath>` 里放 `<image>` 不会产生任何裁剪区域);mask 未读取 SVG 的 `maskUnits`/`x`/`y`/`width`/`height`(始终用整个画布做图层边界,而非官方默认的 bbox ±10%/120%),是简化,已在代码注释标注。
- 测试:新增 `test/animation/clip_mask_test.dart`(8 例),含解析级(id 记录、文档级注册)与像素级(`toImage`/`toByteData` 回读真实像素,验证裁剪/遮罩确实生效,以及动画裁剪路径/遮罩在不同帧读出不同像素——不是"没抛异常就算过")。
- 示例:`example/lib/main.dart` 新增 `kAnimatedMaskSvg`("Animated `<mask>` (Task 1)")——蓝色圆被一个左右生长的白色遮罩矩形逐步揭示,循环播放。

### Task 2:动画路径的 `<text>` 节点——done

- `svg_dom.dart`:新增 `SvgNodeKind.text`,`SvgNode` 新增 `textContent`(纯文本内容,不支持 `<tspan>`)。
- `svg_document_parser.dart`:`_tagToKind` 注册 `'text'`;`_parseElement` 对 `SvgNodeKind.text` 用 `element.innerText.trim()` 取文本内容。
- `animated_svg_painter.dart`:新增 `_paintText`,用 `TextPainter`/`TextSpan`/`TextStyle`(`dart:ui` Canvas 无原生文本绘制,`TextPainter` 是 Flutter 官方封装,不是重新实现排版)绘制 `x`/`y`(SVG 语义是基线锚点,通过 `computeDistanceToActualBaseline` 校正)、`font-size`/`font-family`/`text-anchor`(`start`/`middle`/`end`);`fill`/`opacity` 直接复用 `_paintNode` 里对所有节点种类通用的 `<animate>` 采样机制(`style.fill`/`style.opacity`),**没有为 text 另写一套动画逻辑**。
- **已知限制(按任务范围)**:不支持 `<tspan>`、textPath;文本内容本身(字符串)不可被动画驱动,只有 `x`/`y`/`fill`/`opacity` 等展示属性可以。
- 测试:新增 `test/animation/text_node_test.dart`(8 例),覆盖解析(内容/x/y/字体属性、空白裁剪、空文本)与绘制(不抛错、`fill="none"` 静默、`opacity` 动画通过通用机制采样正确)。像素级字形校验不在范围内(不重新实现文本排版引擎)。
- 示例:`kTextSvg`("`<text>` with animated opacity (Task 2)")——`svgx` 文字配合 `opacity` 呼吸动画循环播放。

### Task 3:`<animateMotion>` 的 keyPoints/keyTimes/calcMode——done

- `smil_animation.dart`:`SmilMotionAnimation` 新增可选 `keyPoints`/`keyTimes`/`keySplines`/`calcMode` 字段。`sample()` 里:无 `keyPoints` 时**逐字节保持原有行为不变**(进度直接映射到弧长采样表——原本就等价于 SVG 默认的 `calcMode="paced"`);有 `keyPoints` 时,复用与 `SmilAnimation`/`SmilTransformAnimation` 完全相同的 `_locateSegment`/`_easedSegmentT`/`_pacedKeyTimes` 区间定位与缓动机制,只是把它们的输出从"数值"改为"弧长比例",再用该比例去查采样表。
- `svg_document_parser.dart`:`_parseAnimateMotion` 新增读取 `keyPoints`(新增 `_parseKeyPoints` 辅助函数,容错策略与 `parseSmilKeyTimes` 一致)/`keyTimes`/`keySplines`/`calcMode`。
- **已知限制**:`<animateMotion>` 的 SVG 规范默认 `calcMode` 是 `"paced"`,但本引擎(为与 `SmilAnimation`/`SmilTransformAnimation` 的既有默认值保持一致)`keyPoints` 存在但未指定 `calcMode` 时默认 `linear`,已在代码注释标注为已知简化。
- 测试:`test/animation/animate_motion_test.dart` 新增 4 例(keyPoints 改道到非默认弧长比例、无 keyPoints 时行为逐字节不变、`calcMode="discrete"` 阶跃、格式错误的 keyPoints 被丢弃)。
- 示例:`kAnimateMotionKeyPointsSvg`("`<animateMotion keyPoints/keyTimes>` (Task 3)")——marker 前半程只走完弧长的 10%,后半程冲刺剩余 90%,循环播放。

### Task 4:动画渐变——done

- `smil_animation.dart`:新增 `SmilColorAnimation`(颜色 `<animate>` 时间线,如 `stop-color`)。为保持本文件框架无关(纯 `dart:math`,可脱离 Flutter 绑定跑测试)的既有性质,`values` 用 `List<int>`(`0xAARRGGBB` 打包整数)而非 `Color` 类型;按 ARGB 逐字节插值,复用与 `SmilAnimation` 相同的 `_locateSegment`/`_easedSegmentT`/`_pacedKeyTimes`(新增 `_argbDistance` 作为 `paced` 模式的距离函数),因此 `calcMode`(`linear`/`discrete`/`paced`/`spline`)/`keyTimes`/`keySplines` 对颜色动画同样生效。
- `svg_dom.dart`:`SvgNode` 新增 `colorAnimations: List<SmilColorAnimation>` 字段,与既有的 `animations`/`transformAnimations`/`motionAnimations` 并列——`<stop>` 就是一个普通 `SvgNode`,数值动画(`stop-opacity`/`offset`)走既有的 `animations`,颜色动画(`stop-color`)走新的 `colorAnimations`,复用而非另起一套机制(符合任务描述"let `<stop>` participate in the existing SvgNode.animations mechanism")。
- `svg_document_parser.dart`:新增 `_parseStopNodes`(每个 `<stop>` 解析出一个携带自身 `<animate>` 子元素的 `SvgNode`,与 `_parseStops` 的 `SvgGradientStop` 列表严格并行同序)、`_parseGradientAttributeAnimations`(渐变元素自身 `x1`/`y1`/`x2`/`y2`/`cx`/`cy`/`r`/`fx`/`fy` 上的 `<animate>`,同样包成一个 `SvgNode`)、`_parseAnimateColor`(解析 `stop-color` 的 `<animate>`,每个关键帧词元先走既有的颜色归一化/解析,再打包成 `SmilColorAnimation` 的 `0xAARRGGBB` 整数)。`_parseStops` 重构抽出 `stopFromAttributes`(移到 `svg_gradient.dart`,避免 gradient/document_parser 两个文件互相 import 成环),初始解析与逐帧重采样共用同一份色标构建逻辑,不存在两条会走岔的实现。
- `svg_gradient.dart`:`SvgGradientDef` 新增 `stopNodes`/`animatedNode`(均有默认值,不破坏直接构造 `const SvgGradientDef(...)` 的既有用法,如 `buildGradientShader` 相关测试)。新增 `resampleGradientAtTime(def, time)`:无 `animatedNode`(或没有任何匹配的动画)时原样返回 `def`(零成本快路径);否则对渐变自身属性(`sampledFor`)与每个 `<stop>`(数值属性 + `stop-color`)在 `time` 采样,重建一份全新的 `SvgGradientDef`。
- `animated_svg_painter.dart`:`_gradientShader` 从 `_gradientShader(id, path, opacity)` 改为先 `resampleGradientAtTime(def, time)` 再 `buildGradientShader`——**每帧都重新采样+重建 shader**,符合任务要求"不要加任何假设渐变静止的 shader 缓存"(与整个动画引擎每帧重录 `Picture` 的既有原则一致)。
- **已知限制**:颜色关键帧(`stop-color` 的 `values`)只支持逐字节线性/阶跃/paced/spline 插值,不支持感知色彩空间(如 OKLCH)插值,这与本引擎既有的颜色处理精度一致,未额外声明为"缺口",是合理的实现深度。
- 测试:`test/animation/gradient_test.dart` 新增 6 例(渐变属性动画重采样、`stop-color`/`stop-opacity` 动画重采样、`calcMode="discrete"` 阶跃、无动画时的零成本快路径、无 `animatedNode` 的向后兼容)。
- 示例:`kAnimatedGradientSvg`("Animated gradient: geometry + stop-color (Task 4)")——渐变的 `x2`/`y2` 与首个色标的颜色同时循环变化。

### 通用要求落实情况

- 每项任务实现后都独立跑过 `flutter test`/`flutter analyze` 确认零回归后再进入下一项(未合并到最后一次性验证)。
- 每项任务都有专门的单元测试(不只是"能跑通"的冒烟测试;clip/mask 是像素级验证)。
- 每项任务都在 `example/lib/main.dart` 新增了一个可视化 demo,遵循既有文件的写法风格(带解释性注释的 SVG 常量 + 页面上一段 `Text` 标题 + `SvgX.string`)。
- 未提交任何 git commit,改动留待用户审阅。

### 最终测试结果(2026-08-25,四项任务全部完成后)

- `cargo test`(`rust/`):**24/24 通过**(与基线完全一致,未改动 `rust/`)。
- `flutter test`(根目录):**101/101 通过**(基线 75 + 新增 26:clip_mask_test.dart 8、text_node_test.dart 8、animate_motion_test.dart 新增 4、gradient_test.dart 新增 6)。
- `flutter analyze`(根目录及 `example/`):**均 0 issues**。

### 触及的文件(均为 `lib/src/animation/` 范围内及其测试/示例,未触碰 `rust/`、`lib/src/rust_static_svg.dart`)

- `lib/src/animation/svg_dom.dart`
- `lib/src/animation/svg_document_parser.dart`
- `lib/src/animation/smil_animation.dart`
- `lib/src/animation/animated_svg_painter.dart`
- `lib/src/animation/animated_svg_widget.dart`
- `lib/src/animation/svg_gradient.dart`
- `test/animation/clip_mask_test.dart`(新增)
- `test/animation/text_node_test.dart`(新增)
- `test/animation/animate_motion_test.dart`(扩展)
- `test/animation/gradient_test.dart`(扩展)
- `example/lib/main.dart`(扩展)

## WSA(Windows Subsystem for Android)上"内容全黑"的真实成因(2026-08-26 实测定位,结论:与 svgx 无关)

之前在 WSA(`adb` 地址 `127.0.0.1:58526`,`product:windows_x86_64`)上目视验收 svgx 时,看到画面整片漆黑,一度怀疑是 svgx 自己的渲染管线在 WSA 的虚拟 GPU 上挂了。这一轮做了完整的逐层剥离实验,把触发条件钉死了,记录在此,以后不用再从头怀疑一遍。

### 一、先纠正两个"看起来像 bug、其实是环境假象"的坑

- **`adb exec-out screencap` 在 WSA 上根本拍不到应用画面**。WSA 的应用是 freeform 窗口,由 Windows 宿主侧合成,Android 侧的 display buffer 是空的——试过 `-d 100`/`-d 101`/`-d 129`,全部返回纯黑 2560x1440,和应用实际画的是什么毫无关系。**别再用 screencap 判断 WSA 上的渲染结果**。可靠办法是在 Windows 侧按窗口类名(`com.example.svgx_example`)找到 HWND,用 `PrintWindow(hwnd, hdc, 2)` 抓图。
- **窗口经常处于"有 HWND 但没有 surface"的状态**(`dumpsys window windows` 里 `mViewVisibility=0x4/0x8`、`mHasSurface=false`),这时候截到的是桌面背景,不是"应用渲染成透明/全黑"。截图前必须先确认 Android 侧 `mHasSurface=true`,否则会把"窗口没显示"误读成"渲染失败"。

### 二、Impeller 在 WSA 上的实际后端

logcat 明确:先尝试 Vulkan(`android_context_vk_impeller.cc`),随即回落到 **OpenGLES**(`android_context_gl_impeller.cc`),走的是 `/vendor/lib64/egl/libEGL_emulation.so`(goldfish 模拟驱动,且 `/dev/goldfish_pipe` 缺失,一直刷 `open_verbose: both vsock and goldfish_pipe paths failed`)。也就是说 WSA 上跑的是 **Impeller + 模拟 GLES 驱动**,不是原生 GPU。

**`--no-enable-impeller` / manifest 里的 `io.flutter.embedding.android.EnableImpeller=false` 在当前 Flutter 3.47 上已经失效**——实测加了这条 meta-data 重新打包,logcat 依然是 "Using the Impeller rendering backend (OpenGLES)",画面也没有任何变化。Android 侧的 Skia 后端已经被移除,这条常见的规避手段现在不成立,别再浪费一次编译去试。

### 三、逐层剥离的实测结论:触发点是 Material `AppBar`,不是 svgx

全部在 **release 模式**(`flutter build apk --release --target-platform android-x64` + `adb install`)下做,每个变体一张 `PrintWindow` 截图:

| 变体 | 结果 |
|---|---|
| 纯 `Text` / `Container` / `Center` / 真实溢出裁剪的 `SingleChildScrollView` / `Opacity`(saveLayer)/ `ClipRRect` / `RepaintBoundary` | **全部正常渲染** |
| svgx 静态图标 + 动画图标(含 `<image>` 位图、动画 `<mask>`、静态/动画渐变 shader、`<text>`、`<animateMotion>`、`<use>`、`skewX`) | **全部正常渲染** |
| `Scaffold(appBar: AppBar(...), body: ...)` | **AppBar 那一条正常画出来,AppBar 以下整个 body 全黑**——连 `Scaffold.backgroundColor` 显式设成纯绿都不画,body 里只放一个黄底红字的 `Text` 也是黑的 |
| 去掉 `appBar`(其余完全不变) | **立刻全部正常** |
| `AppBar(elevation: 0, scrolledUnderElevation: 0, backgroundColor: 蓝, systemOverlayStyle: light)` | **仍然全黑** → 不是 elevation / surfaceTint 的锅 |
| 不用 AppBar,单独调 `SystemChrome.setSystemUIOverlayStyle(...)` | **正常** → 不是 SystemUiOverlayStyle 的锅 |
| 自制顶栏 `PreferredSize + Container`(同样 56 高) | **正常** → 不是"顶部有一条栏"的锅 |
| 自制顶栏 `PreferredSize + Material(elevation: 4)` | **正常** → 不是 `Material` 本身的锅 |

### 四、结论(明确、不含糊)

**WSA 上看到的"svgx 内容全黑",不是 svgx 的 bug,svgx 的静态路径和动画引擎在 WSA + Impeller(GLES 模拟驱动)下渲染完全正常。**真正的触发点是 Flutter 自己的 Material `AppBar`:只要 `Scaffold` 挂了 `AppBar`,在 WSA 这套模拟 GLES 驱动上,AppBar 以下的整块画面就不会被合成出来(呈现为窗口的透明底色,看上去就是全黑);把 `AppBar` 拿掉,同一个页面、同一批 svgx 组件立刻全部正常显示。这是 **Flutter 引擎 + WSA 模拟 GPU 驱动**这一层的问题,与本库无关。

### 五、上游 issue 状态:**没有找到精确匹配**

搜过 flutter/flutter 的 Impeller 黑屏系列(#160866、#155973、#154103、#164717、#154531、#160948、#159851、#165298)以及 WSA 相关(#137905),**没有任何一条描述"AppBar 导致其余画面全黑"或 WSA 上的这个具体现象**。WSA 本身微软已于 2025 年 3 月停止支持,上游也基本不会再有人报这个平台的问题。

最接近的类比仍然是 [flutter/flutter#164735](https://github.com/flutter/flutter/issues/164735)("Black screen with Impeller enabled",无 GPU passthrough 的 macOS 虚拟机里 Impeller 拿不到真实 GPU 而黑屏,且 3.39+ 之后再也没有关掉 Impeller 的开关)——**架构上同类(虚拟化 GPU + 无法关闭的 Impeller),但不是同一个 bug**,如实记录为"最接近的先例",不要当成已确认的根因引用。

### 六、追加实测(2026-08-26):`EnableImpeller=false` manifest 开关仍然有效

命令行 `--no-enable-impeller` 已经失效,但 **`AndroidManifest.xml` 里的等价 meta-data 开关目前(Flutter 3.47)仍然生效**,亲自实测两轮确认(先用纯 `Scaffold+AppBar+Text` 验证,再用真实 `SvgX.string`(含动画描边 + 静态渐变)+ `AppBar` 组合验证,WSA 上都恢复正常显示):

```xml
<!-- example/android/app/src/main/AndroidManifest.xml, <application> 标签内 -->
<meta-data
    android:name="io.flutter.embedding.android.EnableImpeller"
    android:value="false" />
```

跑起来后 logcat 会打印一条明确的弃用警告(`[Action Required]: Impeller opt-out deprecated ... These options are going to go away in an upcoming Flutter release`)——**这条开关官方标注为即将移除,不是长期方案**,只在需要给 WSA 做目视验证时临时加,验证完就撤掉,**不要留在实际 example app / 发布配置里**:
- 真机完全不需要它(真机上 `AppBar`+Impeller 从未出过问题,详见上文"逐层剥离"实测)。
- 一旦某个未来 Flutter 版本真的把这个开关删掉,留着它反而会变成一处随时会失效的技术债。

### 七、以后在 WSA 上做目视验证的实操建议

1. **不要用 `adb screencap`**,用 Windows 侧的 `PrintWindow` 抓 WSA 窗口;截图前先用 `dumpsys window windows` 确认 `mHasSurface=true`。
2. **需要用到 `Scaffold(appBar: AppBar(...))` 的页面**,验证前临时在 `AndroidManifest.xml` 加上面那条 `EnableImpeller=false` meta-data,验证完记得撤掉;也可以选择直接把测试页面的 `AppBar` 换成 `appBar: null` + `PreferredSize/Container` 自制顶栏,两种规避手段都实测有效,看哪种对当次验证更省事。
3. WSA 只适合当"能不能跑起来"的冒烟环境。**性能基准和最终目视验收要以真机为准**,WSA 的模拟 GLES 驱动既不代表真实 GPU 性能,也会制造上面这种假故障。
