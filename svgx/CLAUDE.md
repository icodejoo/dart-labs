# svgx 项目规则

## 项目目的

打造一个**高性能、同时支持静态与动画的 Flutter SVG 库**,目标是替换 `flutter_svg` + `iconify_flutter`。

- 解析底层用 **Rust**(经 flutter_rust_bridge / cargokit 集成)。
- 渲染交给 **Flutter 自身的 GPU 管线**(`ui.Picture` / Canvas / Impeller),**不引入 CPU 光栅器**。
- 动画能力(SMIL + CSS)是本库的核心差异点和存在理由。

## 工作方式规则

- **不重复造轮子**:实现新的非平凡逻辑(算法、解析器、协议处理、数据结构)前,优先去 crates.io、GitHub、pub.dev 等地方调研是否已有成熟方案(如本项目对 usvg/svg-rs/`full_svg_flutter` 的取舍方式),能采用/封装就不要自己从零写。参考下方"参考对象"章节的判断方式。
- **用 subagent 落地任务,主 agent 只负责调度**:非平凡的多步骤任务(调研、实现、重构、基准测试)应派发给 subagent(Agent 工具)去做,主 agent 负责拆解任务、分派、review 结果、维护整体上下文,不要自己大包大揽做具体执行。简单的单步操作(读一个文件、改一行、查个状态)不必走这个流程。

## 参考对象(取长补短)

| 代号 | 对象 | 定位 | 我们怎么用 |
|---|---|---|---|
| **U** | `usvg`(crates.io) | 成熟的**静态** SVG 解析/简化器:shape→绝对路径、解析 use/switch/marker、base64 图片、全部 filter 类型 | **静态解析直接采用** |
| **R** | `resvg` | 在 U 之上的 **CPU(tiny-skia)光栅器** | **不采用**:无动画、CPU 渲染比 Flutter GPU 慢、体积 +~0.5MB(实测 1.13MB→1.63MB) |
| **svg-rs** | `github.com/ginokent/svg-rs` | 零依赖 Rust **SMIL 求值器**(给定 t 返回属性值),支持 `<animate>`/`<set>`/`<animateTransform>` | **动画的 SMIL 参考实现**;但它无 CSS 动画、无 filter/mask/text、成熟度低,不直接依赖 |
| **F** | `full_svg_flutter` fork,位于 `E:\workspaces\bingo\packages\full_svg_flutter` | Dart 动画渲染器:SMIL + CSS `@keyframes` + path morph + filter;已剥离 quickjs;已加静态快路径(缓存 `ui.Picture`) | **仅作性能对比的基准实现**,**不进入 `lib/`**;动画语义参考它的思路,但要写原创代码 |

**动画能力 = 参考 svg-rs 与 F 的思路,原创实现**:svg-rs 提供零依赖、干净的 SMIL 采样思路;F 提供更全的动画语义(CSS keyframes、path morph、filter)覆盖面参考。**取二者之"思路"而非"代码"**——学它们怎么做,自己写。

## CSS 支持范围(调研结论,避免重复纠结)

- **usvg 的 CSS 支持比预期扎实**:靠 `simplecss`(CSS 2.1 级)真正解析 `<style>` 块,支持 element/class/id/后代/子代/属性选择器 + 优先级级联。**明确不支持**:`@media`、`@import`、CSS 变量 `var()`、`calc()`、伪元素——这些是 usvg 上游自己的边界,不是我们要补的缺口。
- **`lightningcss` 不值得引入**:它是给 bundler 用的 CSS 转换/压缩工具,没有针对 DOM 的选择器匹配能力,替代不了 usvg 已经在用的 `simplecss`。
- **"SVG 里的高级 CSS"是伪需求(针对 svgx 的图标场景)**:查了 `flutter_svg` 全部 1116 个 issue,`<style>`/CSS class 相关的实质性 issue 只有 4 个(<0.4%),且全部来自 Illustrator/CorelDRAW 导出的手工 SVG,没有一个来自图标资产。
- **结论**:不追加 CSS 相关投入。如果以后真遇到 `<style>` 块场景,先确认 usvg 现有解析是否够用,而不是新造轮子。

## CSS 动画支持:有证据支撑的"不做"(注意与上面"CSS 支持范围"是两个不同问题)

原创动画引擎排除 CSS `@keyframes`/`animation-*`/`transition-*` 不是图省事,是查过真实数据后的决策:

- 直接 grep 了 Iconify 真实数据(`iconify/icon-sets` 仓库的 JSON):`line-md`(5310 个 `<animate>`、192 个 `animateTransform`、**0 个 CSS**)、`svg-spinners`(262/38/0)、`eos-icons`(33/7/0)——每一个检查过的动画图标集,100% 是 SMIL,零 CSS。
- flutter_svg issue 搜 `keyframes` 只有 1 个命中(#772,开的当天就被维护者回"No, sorry"关掉)。
- F 的上游 `full_svg_flutter` 号称支持 CSS keyframes,但最近 30 个 issue 里没有一个提到这个功能。

**结论**:不做 CSS 动画。只有当 svgx 定位从"图标替换"扩展到"通用 SVGator 风格装饰性动画内容"时才重新评估。

## ⚠️ 硬规则:`lib/` 禁止整包 vendor,但允许精确抄小段代码

**`lib/` 是要发布的库代码,不能把别的项目的整个文件/子系统复制粘贴进来当自己的实现;但为了实现一个明确需要的具体功能点,直接摘取 F 的一小段代码是允许的——前提是符合下面的许可证边界和"不延伸"原则。**

- 曾把 `full_svg_flutter/lib` **原样 vendor** 进了 `lib/src/fvendor/` 并从 `lib/svgx.dart` 导出——**这仍然是错误做法**:整包搬运 + 对外导出,属于下面明确禁止的"延伸"。已移除,教训保留。

### 按来源分两种规则,不能混用

- **F(`full_svg_flutter`,MIT 许可,已核实)**:**允许抄代码**。为实现一个具体功能点(比如 keySpline 三次贝塞尔求值、SMIL clock-value 格式解析),可以直接从 `benchmark/baseline_f/full_svg_flutter_lib/` 摘取对应的一小段代码放进 `lib/`。抄的时候:
  - 只抄**当前明确要用到的最小单元**,不抄它周边没用到的抽象、辅助类型、扩展点——**禁止延伸**。判断标准:如果发现自己在复制一整个文件的结构骨架、或者把用不到的辅助函数也搬了过来"以防万一",就是延伸了,停下来只留真正用的部分。
  - 抄过来的代码块**必须加注释标明来源**(来自 F/`full_svg_flutter` 的哪个文件、哪个函数),满足 MIT 许可的署名要求。
- **svg-rs**:**禁止抄代码**——核实过 GitHub API,它的 `license` 字段是 `null`,默认视为"保留所有权利",复制它的代码在法律上都不安全。**只能读它的思路/算法做交叉验证,自己重新实现,一行代码都不能直接照抄。**

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

4. **Dart 先行是刻意的,但必须留切换缝隙,不是关死这扇门**:
   - **为什么先 Dart**:动画解析是一次性、小体量成本,用 Dart 快速验证 SMIL 语义正确性(改一行热重载就能看效果),比隔着 FFI+FRB codegen 反复调试快得多。这是效率选择,不是"Rust 做不到"。
   - **必须保留的缝隙**:动画引擎对外的接口要设计成**可替换实现**,而不是把"用 Dart 解析"焊死在调用方代码里。解析入口收敛成一个清晰的函数/接口边界(输入 SVG 字符串 → 输出一个自描述的时间线数据模型,不含 Dart 专属类型),`svgx_widget.dart` 的分发逻辑只依赖这个边界。时间线数据模型本身要能被一次性的 Rust 解析结果填充。不要为了"将来可能换 Rust"而现在就搭一层花哨的抽象/插件系统。
   - **已验证满足**:唯一解析入口是 `SvgDocument parseAnimatedSvgDocument(String source)`(`lib/src/animation/svg_document_parser.dart`),返回纯数据模型,`package:xml` 类型只存在于这一个文件内。详见 `doc/acceptance-criteria.md`。

## 环境

Rust 1.96 / flutter_rust_bridge 2.12 / Flutter 3.47 / Dart 3.13 / Android NDK 28 + 四架构 target 均就绪。resvg/usvg 最新 0.48。

## 文档索引

细节文档全部收在 `doc/` 下,不散落在根目录(`README.md`/`CHANGELOG.md`/本文件三者因平台/工具强制约定留根目录;`example/README.md` 是 Flutter 脚手架生成的子包文档,不在本索引范围)。

| 文件 | 讲什么 | 什么时候该去读 |
|---|---|---|
| `doc/acceptance-criteria.md` | 功能验收标准 + 性能验收硬指标(1000 图标滚动、真实 FPS 等)+ 是否达标的结论性记录 | 要确认"这个库到底算不算做完了""性能门槛是什么"时 |
| `doc/animation-engine-features.md` | **能力清单权威参考**:静态路径 + 动画路径当前分别支持/不支持哪些标签和语法,含 12 项功能的像素级验证结果 | 要确认"某个 SVG 特性 svgx 支不支持"、开发新功能前先看现状时 |
| `doc/performance-benchmarks.md` | 性能基准套件说明 + 每一轮功能改动后的完整复测数据(`LIB=compare` 方法学、`SvgEffects` 重构前后对比等) | 要复测性能、要看某轮改动是否引入回归、要理解基准方法学演进时 |
| `doc/ffi-performance-audit.md` | FFI(Dart↔Rust)数据搬运的专项审计结论:为什么不用 DCO/ZeroCopyBuffer、为什么不手写 dart:ffi、为什么不开 Dart/Rust 共享内存 arena(含 FRB 源码级证据) | 有人提议"用零拷贝/共享内存/手写 FFI 优化 parse_svg"时,先看这份,已有稳定结论 |
| `doc/bugfix-history.md` | 历史上"发现并修复"的真实 bug 记录(3 个 demo bug、动画路径 blur 缺失等) | 想了解踩过哪些坑、或又发现类似问题要往哪追加记录时 |
| `doc/wsa-impeller-debugging.md` | WSA(Windows Subsystem for Android)上"内容全黑"问题的完整排查记录,结论:与 svgx 无关,是 Material AppBar + Impeller 模拟驱动的问题 | 在 WSA/模拟器上做目视验证遇到黑屏时 |
| `doc/size-optimization-history.md` | 体积优化每一项改动的**完整调研过程**(动机、前提确认、实测数据、方法学局限) | 想知道"当初为什么这么决定"时 |
| `doc/SIZE_OPTIMIZATION.md` | 体积优化**结论速查表**:已落地/候选/已排除三张表 + 验证方法论 | 讨论瘦身方向前先查这份,别重复调研 |
| `doc/PRECOMPILED_MIGRATION_PLAN.md` | 预编译产物(prebuilt .so/.dll)迁移方案 | 涉及预编译分发、CI 构建产物相关改动时 |
| `README.md` | pub.dev 包主页展示内容(根目录强制位置,不要移动) | 面向库使用者 |
| `CHANGELOG.md` | 版本变更记录(根目录强制位置,不要移动) | 发版时 |
