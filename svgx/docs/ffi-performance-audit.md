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

**结论稳定性**:本问题已做五次交叉验证(DCO 专项、Uint8List 传闻、手写 dart:ffi、FRB 源码级定论、共享内存 arena),方向一致——**现状(FRB sync + SSE)是当前数据形状与量级下的最优解,以后无需重新调研。**
