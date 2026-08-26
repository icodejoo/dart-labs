# FFI 数据搬运审计结论

> 从 `CLAUDE.md` 拆出(原"FFI 数据搬运审计结论"及其三次补充调研小节)。这是**结论性审计记录**,已审计完毕、无需改动,后续不用为同一问题重新调研。

## 主体结论(2026-08-25,已审计,无需改动)

审计了 `parse_svg` 的 Dart↔Rust 数据搬运方式,结论:**当前实现已经是 FRB 2.12 sync/generalized 架构下能做到的最优,没有可落地的优化空间**。关键事实(已核实,非猜测):

- **本项目生成的是 SSE(序列化)编解码,不是 DCO(原生零拷贝)编解码**——`lib/src/rust/frb_generated.dart` 里 `parse_svg`(以及所有其他函数)都接的是 `SseCodec`,不是走 `allo-isolate` 的 `DartNativeExternalTypedData` 零拷贝路径。后者只对 DCO 编解码生效,本项目压根没用那条路径。
- **`points: Vec<f32>`/`verbs: Vec<u8>` 这类大字段,sync 模式下确实有一次拷贝**——但是**整块 bulk copy,不是逐元素循环**。FRB 自己在 `read_buffer.dart` 里有原话注释:"Must copy when in `sync` mode, because the underlying buffer is a Rust pointer and will be freed later (but in non-sync mode, we can optimize this and do not copy)"——这是 FRB 为了避免访问已释放的 Rust 内存,故意加的安全拷贝,不是实现疏漏。
- **想去掉这次拷贝,唯一办法是把 `parse_svg` 从 sync 改成 async**——但这条路已经在"性能验收条件"里评估过并明确否决(sync 单次解析 avg=0.026-0.106ms,1000 图标场景零掉帧,量级可忽略,不值得为了省这一次 bulk copy 换成跨 isolate 派发的 async)。
- **`String` 入参换成 `Uint8List` 没有意义**:UTF-8 编码这一步不可避免只会发生一次,搬到调用方代码里做和留在 FRB 生成代码里做,总成本一样,不会减少。查了 `flutter_svg` 自己的 `SvgBytesLoader.provideSvg`,它也是先 `utf8.decode` 成 `String` 再解析,业界通用做法一致,不是我们独有的反模式。
- **flutter_svg 的缓存 key 也是对完整字符串做 hash**(`Object.hash(_svg, theme, colorMapper)`),和 svgx 的 `(String, int?)` 缓存 key 成本量级相同——没有可以借鉴的更便宜方案。

**结论**:不改代码。如实记录"审计过、现状已经足够好"这个结论,以后不用再为这个问题重新调研或纠结。

## 补充调研一(2026-08-25,ZeroCopyBuffer/DCO 专项)

确认当前 `parse_svg` 走的是 **SSE(序列化)编解码,非 DCO/ZeroCopyBuffer**——`rust/src/api/svg.rs` 的 `SvgPath`(`points: Vec<f32>`/`verbs: Vec<u8>`)未用 `ZeroCopyBuffer<Vec<u8>>` 包装,`lib/src/rust/frb_generated.dart` 用的是 `SseCodec`。FRB 2.x 里 ZeroCopyBuffer 对应的免拷贝路径是 **DCO codec**(经 `allo-isolate` 的 `Dart_PostCObject` 机制),但这条路径**天然要求 async 调用**(`executeNormal`),和当前 `#[frb(sync)]` 互斥——要用 DCO 就必须先把 `parse_svg` 改成 async,这和"是否值得为省一次 bulk copy 换成 async"是同一个决策,已经在上面否决过。收益上,DCO 省下的是当前 avg 0.026-0.106ms 里最小的一块(序列化 bulk copy),而 async 化引入的跨 isolate 调度/`Completer` 开销大概率超过这点节省。**结论:不做**,维持 sync + SSE 现状。

## 补充调研二(2026-08-25,"Uint8List 触发共享内存零拷贝"传闻核实)

有说法称"Dart 传 `Uint8List` 给 Rust 会触发共享内存从而避免拷贝",核实为**误传,方向搞反了**。FRB 的零拷贝机制描述的是 **Rust → Dart** 方向(`ZeroCopyBuffer` 把 Rust 的 `Vec<u8>` 免拷贝映射成 Dart 的 `ExternalTypedData`),而 `parse_svg` 的入参方向是 **Dart → Rust**,本来就不在这个机制覆盖范围内。即便方向对了,FRB 官方文档也明确写"同步传输仍需要拷贝",零拷贝只在 async 模式下生效,与当前 `#[frb(sync)]` 互斥。手动把 SVG 字符串 `utf8.encode` 成 `Uint8List` 再传,只是把编码步骤从 FRB 生成代码搬到调用方代码,总拷贝次数不变,没有意义。

## 补充调研三(2026-08-25,手写 dart:ffi 绕开 FRB 能否同步零拷贝)

结论为**部分能,但不值得换**。

- Dart→Rust 方向:`Uint8List.address`(Dart 3.5+)理论上可传裸指针,但 Dart 是可整理(compacting)GC,官方未明确承诺同步 FFI 调用期间该内存会被自动 pin 住,存在地址失效风险;改用 `malloc.allocate`(native heap)内存稳定,但**把 Dart String 编码进这块 buffer 本身就是一次拷贝**——UTF-16→UTF-8 编码这一步,FRB 和手写 FFI 都躲不掉,零拷贝只能省掉"编码完之后再搬一次",省不掉编码本身。
- Rust→Dart 方向:`Pointer.asTypedList()` 配合 `NativeFinalizerFunction`(Dart 3.1+)可做到不拷贝的视图,但生命周期正确性完全靠开发者手动保证,Dart SDK 的 GitHub issue(`dart-lang/sdk#55800`)记录过跨 isolate 场景下的 use-after-free 真实 bug。
- FRB 官方文档(zero-copy guide)自己承认:sync 模式下的零拷贝是"理论上可行但尚未实现"的路线图项,当前 FRB sync 就是强制拷贝的 codec。手写 FFI 没有这层限制,架构上确实能做到 FRB sync 做不到的事。
- **代价**:彻底放弃 FRB 的类型安全生成,内存安全责任全部转移给开发者(GC 移动、手动 pin/finalizer、跨调用生命周期管理),换来的只是省掉一次微秒级的 bulk copy(当前 avg 0.026-0.106ms,1000 图标场景零掉帧)。
- **结论:不建议做**。收益(省一次微秒级拷贝)远小于代价(放弃类型安全 + 内存安全风险 + 维护成本),与 ZeroCopyBuffer/DCO 那次结论方向一致——现状(FRB sync + SSE)已经是当前数据量级下的最优解。

## 补充调研四(2026-08-26,FRB 同步零拷贝:从"文档说法"升级为源码级定论)

补充调研三只引用了 FRB 官方文档的说法。这次直接读了 FRB master 源码,把结论钉死:**FRB 的同步模式在任何 codec 下都不可能零拷贝,这是当前实现的既成事实,不是配置问题。**

**版本基准**:flutter_rust_bridge 2.13.0(pub.dev 最新)。翻了最近约 40 条 changelog,**没有任何** zero-copy / sync / NativeFinalizer / ExternalTypedData 相关条目——即下面的结论对当前版本成立,不是过期快照。

**三条路径的完整矩阵**(比原来只谈 sync 更完整):

| 方向 / 模式 | 零拷贝 | 机制 |
|---|---|---|
| Rust → Dart,**async** 的 `Vec<u8>`/`Vec<f32>` 等 prim list | ✅ | `Dart_PostCObject` + ExternalTypedData,由 Dart VM 直接接管,**仅原生平台** |
| Rust → Dart,**Stream** | ✅ | 同上(Android/iOS/Win/macOS/Linux) |
| Rust → Dart,**`#[frb(sync)]`** | ❌ | 见下方源码证据,强制 `.clone()` |
| Rust → Dart,**Web/WASM** | ❌ | 无对应 VM API |
| Dart → Rust,**任何模式** | ❌ | CST 编码模板显式 memcpy |
| **SSE codec(本项目所用),任何方向** | ❌ | 整个返回值序列化进一条字节流,天然多一次拷贝 |

**源码证据一(sync 强制拷贝)**——`frb_dart/lib/src/dart_c_object_into_dart/_io.dart` 是同步返回值在 Dart 侧的唯一解码点,两个 typed-data 分支都是"建视图 → 立刻 clone":

```dart
case Dart_CObject_kTypedData:
  return _typedDataIntoDart(...).clone();        // clone() = Uint8List.fromList,memcpy

case Dart_CObject_kExternalTypedData:
  final ans = _typedDataIntoDart(...).clone();   // 先复制
  callback(length, peer);                        // 再立刻调 finalizer 释放 Rust 侧内存
  return ans;
```

同一文件里**留着一整段被注释掉的零拷贝实现**,并写明放弃理由:"The commented approach enables zero-copy, but it does not tell Dart VM the external object size, thus Dart VM may choose to GC too sparsely",后续用 `NativeFinalizer` 优化被标为"等当前非零拷贝方案慢到不能忍再说"。**即:代码写过、能跑,是作者因 GC 压力主动关掉的**,不是没实现。这比"官方文档说尚未实现"硬得多,也说明短期内不会变。

**源码证据二(Dart → Rust 必拷贝)**——codegen 的 CST 编码模板(`.../codec/cst/encoder/ty/primitive_list.rs`)生成的 Dart 代码就是显式 memcpy,和补充调研二的判断一致:

```dart
final ans = wire.cst_new_list_prim_u_8_strict(raw.length);
ans.ref.ptr.asTypedList(raw.length).setAll(0, raw);   // 复制
return ans;
```

**对 svgx 的意义**:本项目走 SSE,连"唯一那条零拷贝路径(async + DCO + 原生平台)"的射程都没进。想吃到它,要同时满足**改 async + 换 DCO codec + 只在原生平台生效**三个条件,而 async 化早已在性能验收里被否决。**维持现状,此问题闭环。**

## 补充调研五(2026-08-26,"开一块 Dart/Rust 共享内存避免拷贝"可行性)

**技术上完全可行,而且根本不需要 OS 级共享内存(mmap/shm)**——Dart VM 和 Rust 编译进**同一个进程、同一个地址空间**,所谓"共享内存"就是双方指向同一块 native heap。三种落地形态:

| 形态 | 谁分配 | Dart 侧 | Rust 侧 | 生命周期归属 |
|---|---|---|---|---|
| A. Rust 出内存,一次性移交 | Rust `Box::leak` / `Vec::into_raw_parts` | `Pointer.asTypedList(len, finalizer:, token:)` | 返回 `(ptr, len)` | Dart GC + NativeFinalizer |
| B. Dart 出内存,Rust 写入(**最稳**) | Dart `malloc.allocate` | `asTypedList` 视图,可复用同一 arena | `slice::from_raw_parts_mut(ptr, len)` | Dart 显式 `malloc.free` |
| C. 直供 Dart GC heap | Dart `Uint8List(n)` | `Uint8List.address`(Dart 3.5+) | 裸指针 | **仅在 `@Native(isLeaf: true)` 调用期间有效** |

关键 API 事实(已核实):`Pointer<Uint8>.asTypedList(int length, {Pointer<NativeFinalizerFunction>? finalizer, Pointer<Void>? token})`,`finalizer`/`token` 自 **Dart 3.1** 起可用,返回的是**真视图不是拷贝**,写视图 = 写 native 内存。

**硬约束(决定这条路值不值)**:

1. **内存必须在 native heap**,不能是 Dart GC heap——Dart 是可整理(compacting)GC,对象会被移动;形态 C 只在 leaf call 期间安全,**不能跨调用持有地址**。
2. **生命周期正确性 100% 靠人**。Dart SDK 有真实未修复 issue `dart-lang/sdk#55800`:`asTypedList` 的视图跨 isolate 共享会 use-after-free,根因是 native finalizer 绑在 isolate 而非 isolate group 上。2024-05 开的,至今 open。
3. **并发要自己同步**。sync 调用是串行的没问题;一旦 Rust 在别的线程写(async/后台线程),必须自己上原子/双缓冲/ring buffer。
4. **放弃 FRB 的结构化返回**。FRB 的 SSE 把整个嵌套结构序列化;要用共享 arena,就得自己定义 arena 内的二进制布局——**等于自己发明一套序列化协议**,还得手写 ffigen 绑定。

**对 svgx 的收益核算:不做。理由是数据流形状不对,不是嫌麻烦。**

- **省下的拷贝会被下一步吃掉**:`lib/src/rust_static_svg.dart` 的 `_replay(verbs, points)` 是**逐 verb 调 `ui.Path.moveTo/lineTo/cubicTo`**(dart:ui 没有"批量灌 verbs+points"的 API)。也就是说 points 无论躺在哪块内存里,Dart 都要**逐点读一遍并逐条调 dart:ui**,`ui.Path` 内部还会再存一份。共享内存省掉的是这条链路上最便宜的一环。
- **这是一次性成本,不是每帧成本**:静态路径解析结果最终缓存成 `ui.Picture`,同一个 SVG 只解析一次。共享 arena 优化的是首次成本,而首次成本已实测 avg 0.026-0.106ms、1000 图标滚动零掉帧。
- **适用场景对不上**:共享 arena 真正划算的是"大块、原始、Dart 侧直接消费或长期持有"的数据——像素 buffer、音频 PCM、网络帧。生态里那个 `zerocopy` pub 包(SIMD 对齐 + `asTypedList` + 原子自旋锁 + NativeFinalizer,机制和形态 B 一样)宣传的基准就是 **10MB payload**;而 svgx 是"小块 + 高度结构化 + 一次性"。顺带一提该包只有个位数下载量,不构成可依赖的生态方案,只能当"有人这么干过"的先例读。
- **架构上还被排除一次**:CLAUDE.md 已定"光栅化交给 Flutter GPU,Rust 永不参与"——最需要共享内存的那类数据(像素 buffer)在 svgx 里压根不存在。

**什么时候值得重新评估(留口子,不是关死)**:仅当以下条件**同时**成立——(a) 动画的每帧采样真的下沉到 Rust,即 FFI 从"一次性"变成"每帧";且 (b) profile 实测数据搬运在帧预算里占比 >10%。在那之前不要再为这个问题开调研。

**结论稳定性**:本问题已做五次交叉验证(DCO 专项、Uint8List 传闻、手写 dart:ffi、FRB 源码级定论、共享内存 arena),方向一致——**现状(FRB sync + SSE)是当前数据形状与量级下的最优解。**

## 补充调研六(2026-08-26,**实测**:把上面的推理换成数字)

前五次都是推理与源码论证。这次直接测了。**结论没有被推翻,但补上了三个推理时没看到的事实**(尤其第 2、3 条,它们比"占比小"更能决定这个方向的死活)。

**复现方式**:隔离 worktree 分支 `bench/ffi-copy-share`(`.claude/worktrees/ffi-copy-bench`),两个测试文件 `svgx/test/ffi_copy_share_bench_test.dart`、`svgx/test/raster_vs_gpu_bench_test.dart`,数据源为 `benchmark/bench_app/lib/mdi_icons_1000.dart` 那 1000 个真实 Mdi 图标。为给对照方最有利条件,Rust 侧临时改 `opt-level = "z"` → `3` 并临时引入 `resvg`(**都只在该 worktree 内,正式库依旧不依赖 resvg**)。

### 实验一:一次 `parse_svg` 的层次拆解(1000 图标 × 10 轮)

| 层 | ns/icon | 占 `parseSvg` | 共享内存能消除吗 |
|---|---|---|---|
| **A** `parseSvg` 总计 | 14203 | 100% | — |
| **L1** SSE decode(Dart 侧反序列化) | **422** | **2.97%** | ✅ **唯一能消的** |
| **L2** 纯读坐标(不调 dart:ui) | 554 | 3.90% | ❌ 内存在哪都要读 |
| **L3** 重建 `ui.Path` | 2077 | 14.62% | ❌ |
| **L3−L2** 纯 Dart→native 调用 | **1523** | **10.72%** | ❌ |

搬运的数据量:**406 字节/图标**(94140 个 `f32` + 29809 个 verb,摊到 1000 个图标)——比之前估的"几 KB"小一个数量级。

**读法**:共享内存的收益上界是 **2.97%**,而它消不掉的 `ui.Path` native 调用是 **10.72%**——后者是前者的 **3.6 倍**。另外 422ns 解 406 字节远慢于纯 memcpy(几十 ns 量级),说明 L1 的大头是**逐字段遍历嵌套结构**而非 bulk copy;共享 arena 只能省掉里面那点 memcpy,结构遍历照做。**即真实收益远低于 2.97% 这个上界。**

### 实验二:resvg CPU 光栅 + 共享内存读像素 vs 现有 Flutter GPU 管线(48×48,3 轮)

| 路径 | 测点 | us/icon |
|---|---|---|
| **GPU**(现有) | G1 `parseSvg` | 27.96 ※ |
| | G2 重建 `ui.Path` | 3.95 |
| | G3 录制 `ui.Picture` | 5.52 |
| | **CPU 合计** | **37.42** |
| **RASTER**(resvg) | R1 纯光栅(丢弃像素) | 29.99 |
| | R2 光栅 + **共享内存**读回 | 34.24 → handoff **4.25** |
| | R3 光栅 + SSE 拷贝读回 | 37.26 → handoff **7.27** |
| | R4 像素 → `ui.Image` | **122.00** |
| | **CPU 合计(R2+R4)** | **156.23** |

※ 该轮 warmup 不足(仅 200 图标),G1 偏高;实验一充分预热下同一 dll 测得 14.20。用 14.20 修正后 GPU 侧 CPU 合计 23.67 us/icon。

**三个推理阶段没看到的事实**:

1. **共享内存的 handoff 不是 0,是 4.25us**。它有自己的簿记成本:Rust 侧 alloc + `Box::into_raw`、FFI 返回句柄、Dart 侧 `Pointer.fromAddress` + `asTypedList`、外加 `free_pixels` **第二次 FFI 调用**。对 9216 字节的像素,共享内存只省掉 **41%**(3.02/7.27)的搬运成本,**不是 100%**。数据越小,这个固定簿记占比越高——对 406 字节的 `parse_svg` 场景,它很可能**净亏**。
2. **真正的拷贝瓶颈不在 Rust→Dart,在 Dart→engine**。`R4 = 122us/icon`,是 handoff(4–7us)的 **17–29 倍**。任何要显示的像素最终都得过 `ImmutableBuffer.fromUint8List` 交给 engine,那一跳的拷贝无法用共享内存绕开。**共享内存省下的 3us,在下游这一跳面前直接消失。**
3. **CPU 光栅路线整体比 GPU 路线贵 4.2 倍(用修正后的 G1 则为 6.6 倍)CPU**,而 GPU 路线这份 CPU 成本里**还不含光栅化本身**(已卸载到 GPU)。单是 resvg 光栅 R1=29.99us 就已逼近整条 GPU 路径的 CPU 总成本。这为 `CLAUDE.md` 架构决策"不采用 resvg / 光栅化交给 Flutter GPU"补上了本项目自己的实测证据(此前理由是无动画 + 体积 +0.5MB)。

### 方法学局限(如实标注)

- **环境是 `flutter test` host VM(JIT),不是 profile AOT**。Dart 侧的 L1/L2/L3 被 JIT 拖慢,Rust 侧是 AOT 的 dll 不受影响 → **L1 占比被高估**,AOT 下只会更低。偏差方向对结论保守。
- 10000 次 `Stopwatch.start/stop` 的开销全部计入 L1,同样是高估。
- **headless 环境未测真实 GPU 光栅耗时**,GPU 路径只统计了 CPU 侧成本。参考量级见 `docs/performance-benchmarks.md` 的 raster avg 1.5–1.8ms(1000 图标一屏)。
- 实验二 warmup 不足导致 G1 偏高,使 raster/gpu 比值被**低估**(4.2x 是下界,修正后 6.6x)。偏差方向同样对结论保守。
- R4 的 122us 含 3 次 `await` 的异步调度开销,可能高估;但即便扣除,9216 字节拷贝 + engine 侧纹理准备仍远大于 handoff 量级。

### 最终结论

**不做共享内存 arena,不换 CPU 光栅路线。**收益上界实测 2.97% 且真实值更低,而共享内存自身的固定簿记成本在本项目 406 字节/图标的数据量级下很可能把这点收益吃光;真正的拷贝大头(Dart→engine,122us)共享内存够不着。**本问题至此从"推理结论"升级为"实测结论",彻底闭环。**

重新评估的触发条件不变(见补充调研五):动画每帧采样下沉 Rust **且** profile 实测搬运占帧预算 >10%。

## 补充调研七(2026-08-26,"让 resvg 调 GPU 提速"可行性)

**结论:resvg 不能调 GPU;换成 Rust 侧的 GPU 渲染器(vello)也是错误方向。**

> 数据来源标注:23.67us / 122us / 29.99us 来自补充调研六本项目实测;readback 量级、tiny-skia 声明来自公开资料引用,**未单独实测**。

- **resvg 本身没有 GPU 后端可调**。它唯一的渲染后端 `tiny-skia` 在 README 里把 GPU rendering 明确列为 *out of scope / not planned*。resvg 早期有过 qt/cairo/raqote/skia 多后端,后来全部移除统一到 tiny-skia,**连开关都不存在**。
- **真正的障碍不在渲染器,在两个 GPU 上下文之间的桥**。Rust 用 wgpu/vello 渲染,结果在 Rust 自己的 GPU 上下文里;Flutter 用 Impeller/Skia 的上下文。跨过去只有两条路,都不通:

  | 路径 | 成本 | 判定 |
  |---|---|---|
  | GPU readback(GPU→CPU→Flutter GPU) | readback 普遍毫秒级;公开数据:Android 720p RGBA GPU→CPU ~5ms + CPU→GPU ~5ms | 现有整条 GPU 路径 CPU 成本仅 **23.67us**,一次 readback 是其 **200 倍以上**。出局 |
  | external texture 共享(`Texture` widget + `TextureRegistry`) | 每平台需写原生插件代码(纯 FFI plugin 做不到);**每个纹理需一个 textureId + 一个 Texture widget** | 该模型是为"一路视频/相机预览"设计,不适用于 **1000 个 24dp 图标**;桌面支持弱。出局 |

- **现有方案本来就在用 GPU**。`ui.Picture` → Impeller/Skia 就是 GPU 光栅。问题从不是"要不要 GPU",而是"用谁的 GPU"——现在用 Flutter 自己那块:零桥接、零额外上下文,Impeller 还能跨图标批合并 draw。引入第二个 GPU 上下文只是凭空多一道墙。
- **小图标场景 GPU 也不划算**:48×48 = 2304 像素。GPU 优势在并行填充**大量**像素,而每次 draw 的固定开销(command buffer 提交、state change、同步)是常数(wgpu 的 state change 开销本身即被记录为"相对 vulkan 偏高")。这点填充量撑不起固定成本。
- **体积直接否决**:wgpu + vello 是**几 MB 级**依赖,而本项目正为 resvg 的 0.5MB 纠结(见 `docs/SIZE_OPTIMIZATION.md`)。

**统一规律(补充调研六的延伸)**:**任何"Rust 侧自己出像素"的方案,都必须在 Rust 与 Flutter engine 之间过一道墙**——CPU 光栅过的是 memcpy 墙(实测 R4 = 122us/icon),GPU 光栅过的是 readback 墙(毫秒级,更厚)。而现有方案**根本不过墙**:它把几何(406 字节 verbs/points)交给 Flutter,由 Flutter 自己在 GPU 上光栅。

**因此 `CLAUDE.md` 架构决策"光栅化交给 Flutter GPU,Rust 永不参与"的真正价值不是省 CPU,而是完全绕开了这道墙。**此结论一并闭环,后续不必再为"Rust 侧上 GPU"重新调研。
