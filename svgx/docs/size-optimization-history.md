# 体积优化:调研过程记录

> 从 `CLAUDE.md` 拆出。本文件回答"当初为什么这么决定"——每项体积优化改动落地时的完整调研过程、实测数据、方法学局限。**结论速查表**(现在采纳了什么、还剩什么候选/已排除)在 `docs/SIZE_OPTIMIZATION.md`,以后讨论瘦身方向先查那份,不要在这里重复记录汇总表;两者互补。

## `usvg` `default-features = false`(2026-08-25 首次执行,2026-08-26 因改名事故重新应用)

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
- `<text>` 的按需字体库方案(先嗅探 `<text` 再走 `system_fontdb()` 单例)已随本次撤回而废弃。

## `-Zlocation-detail=none` + `-Zfmt-debug=none`(2026-08-26)

- **动机**:在已有的 `-Cpanic=immediate-abort` + `-Z build-std=std,panic_abort` 基础上,叠加两个 nightly-only 的 rustc `-Z` flag 进一步压缩预编译产物:`-Zlocation-detail=none` 去掉 `caller_location`(panic/track_caller)携带的文件名/行号信息,`-Zfmt-debug=none` 精简 `#[derive(Debug)]` 的实现。
- **前提确认**:用 `rustc +nightly-2026-06-24 -Z help` 实测确认两者都是独立的 rustc `-Z` 标志,不依赖 `-Zunstable-options`(后者只解锁 cargo 自身的 unstable 选项,与 rustc 的 `-Z` 标志是否可用无关),纯 nightly 工具链即可直接用,无需额外前提。
- **改动**:`tool/prebuilt_common.dart` 的 `kBaseRustFlags` 追加 `-Zlocation-detail=none -Zfmt-debug=none`。
- **验证方式**:Android 交叉编译(4 个 target:`aarch64-linux-android`/`armv7-linux-androideabi`/`x86_64-linux-android`/`i686-linux-android`),通过本机 `ANDROID_HOME=E:\sdk\android`(NDK r28.2.13676358 已装)在 Windows 宿主上直接交叉编译,不是用 Windows 平台代理验证。`dart run tool/build_prebuilt.dart --group android` 构建成功,产物直接落位 `prebuilt/android/jniLibs/*/libsvgx.so`。
- **实测体积**(改动前 baseline 取自当前已提交 `prebuilt/` 下的产物,均为 nightly + build-std,只是不带这两个新 flag):

  | target | 改动前 | 改动后 | 降幅 |
  |---|---|---|---|
  | arm64-v8a | 653,336 字节 | 641,280 字节 | −12,056 字节(−1.85%) |
  | armeabi-v7a | 450,464 字节 | 443,560 字节 | −6,904 字节(−1.53%) |
  | x86_64 | 739,928 字节 | 727,952 字节 | −11,976 字节(−1.62%) |
  | x86 | 773,504 字节 | 761,224 字节 | −12,280 字节(−1.59%) |

  实测降幅约 1.5%–1.9%,比预期的"约 2-5% + 2%"要小,但四个 target 上全部为真实正收益,无一持平或变大。
- **方法学局限**:仅验证了 Android 四个 target 的交叉编译与体积;未在 iOS/macOS/Linux/Windows 其余 9 个 slice 上实测(理论上同一套 RUSTFLAGS 对所有 target 生效,但未逐一验证)。`cargo test`(rust/,默认 stable 工具链,不受此 RUSTFLAGS 影响)24 通过,仅确认功能未受影响,不是该 flag 组合本身的正确性证明。因为本轮构建的是 Android(非 host 平台),未跑 `flutter test`(`frb_generated.dart` 只从 `rust/target/release/` 加载宿主库,与本次 Android 产物无关)。
- **结论**:**保留**该改动。`tool/prebuilt_common.dart` 的 `kBaseRustFlags` 追加两个 flag;`prebuilt/android/jniLibs/*/libsvgx.so` 四个文件已用新产物覆盖;`prebuilt/MANIFEST.json` 已由构建脚本本身在写产物时同步更新(源码哈希 `1f22b2c26395d21bb2ac2d125adcd5d83225f3d8d779b75d0f276521bfd2b97e`)。其余平台的 `prebuilt/` 产物尚未用新 flag 重新构建,后续跑 CI 或本地重建这些平台时会自动带上新 flag。

## `-Z build-std-features=`(清空 std 默认 feature,2026-08-26)

- **动机**:已有的 `-Z build-std=std,panic_abort` 不带显式 `-Z build-std-features=...` 时,会拉入 std 的 DEFAULT feature 集合,其中包含 `backtrace` 与 `panic-unwind`(见 rust-lang/rust#147257),连带把 gimli/addr2line/miniz_oxide 等符号化/反解析代码编进二进制——即便本项目从不 unwind(只链接 `panic_abort` 这一个 panic 运行时)、也从不格式化 backtrace(`-Cpanic=immediate-abort` 直接 abort,无 panic hook)。
- **前提确认**:本地检查 nightly-2026-06-24 工具链的 `std/Cargo.toml`(`rustup component add rust-src` 后位于 sysroot 下的 `lib/rustlib/src/rust/library/std/Cargo.toml`)——`[features]` 下只有 `backtrace = [...]`、`panic-unwind = [...]` 等具名 feature,**没有 `default = [...]` 条目**;说明"默认启用 backtrace/panic-unwind"是 cargo 的 `-Z build-std` 机制自己注入的,不是 std 包声明的默认值。同时检查 `panic_abort/Cargo.toml`:只依赖 `core`(Android 上额外依赖 `libc`/`alloc`),与 `backtrace` feature 完全无关,清空默认 feature 不会破坏编译。`-Z build-std-features` 用法与 `-Z build-std` 一致,均为 cargo 侧 `-Z` 参数,空字符串 `-Z build-std-features=` 表示清空默认集合(先在 host target `x86_64-pc-windows-msvc` 上跑通验证语法与编译可行性,再做 Android 交叉编译)。
- **改动**:`tool/prebuilt_common.dart` 的 `kBuildStdFlags` 追加 `-Z build-std-features=`。
- **验证方式**:与上一条同样的 Android 交叉编译流程(`ANDROID_HOME=E:\sdk\android`,NDK r28.2.13676358,Windows 宿主直接交叉编译四个 target),`dart run tool/build_prebuilt.dart --group android` 构建成功。
- **实测体积**(改动前 baseline 取自上一条改动落地后已提交的 `prebuilt/` 产物):

  | target | 改动前 | 改动后 | 降幅 |
  |---|---|---|---|
  | arm64-v8a | 641,280 字节 | 502,248 字节 | −139,032 字节(−21.7%) |
  | armeabi-v7a | 443,560 字节 | 345,000 字节 | −98,560 字节(−22.2%) |
  | x86_64 | 727,952 字节 | 561,128 字节 | −166,824 字节(−22.9%) |
  | x86 | 761,224 字节 | 584,336 字节 | −176,888 字节(−23.2%) |

  四个 target 降幅均在 21.7%–23.2% 之间,是这一轮体积优化里收益最大的单项改动。
- **`cargo test`(`rust/`)**:**24 passed / 0 failed**,与改动前完全一致,功能未受影响。
- **方法学局限**:与上一条相同,仅验证了 Android 四个 target;未逐一验证 iOS/macOS/Linux/Windows 其余 9 个 slice(理论上同一套 `-Z` 参数对所有 target 生效)。未跑 `flutter test`(本次未重新构建宿主 `.dll`)。
- **结论**:**保留**该改动。`tool/prebuilt_common.dart` 的 `kBuildStdFlags` 追加 `-Z build-std-features=`;`prebuilt/android/jniLibs/*/libsvgx.so` 四个文件已用新产物覆盖;`prebuilt/MANIFEST.json` 已由 `dart run tool/build_prebuilt.dart --group android` 在写产物时同步更新。其余平台的 `prebuilt/` 产物尚未用新 flag 重新构建。

## `-Wl,--icf=all`(lld 相同代码折叠,2026-08-26)

- **动机**:Rust 泛型单态化会产出大量字节完全一致的函数体(本项目里最典型的就是 `free_zero_copy_buffer_u8`/`_i8`、`_u16`/`_i16` 这类只有类型参数不同的桥接辅助函数)。lld 的 `--icf=all` 在链接期把这些字节相同、重定位目标也相同的 section 折叠成一份,原有符号全部别名到同一地址。NDK r28 用的就是 lld,不需要额外前提。
- **正确性风险审查(改动前先做,这是本项目采纳该 flag 的前置条件)**:`--icf=all` 属于"激进折叠",连被取地址的函数也一起折叠,因此**任何依赖"不同函数地址必定不同"的代码都会被它破坏**。逐项检查了 `rust/src/**`(含 `frb_generated.rs`,全部 5 个文件、2837 行):
  - 没有把函数指针 `as usize`/`as *const ()` 后做 `==` 比较的代码;
  - 没有 `std::ptr::fn_addr_eq`、没有对 fn item 做裸指针相等判断;
  - 没有把函数指针当 `HashMap`/`HashSet` key 或去重/缓存 key 用(整个 crate 里根本没有 `HashMap`/`HashSet`);
  - 没有 `dyn Trait` 的 vtable 指针比较,也没有 `Any`/`downcast`;
  - 唯一的 `unsafe` 用法是 `frb_generated.rs` 里 5 处 `Dart2RustMessageSse::from_wire(...)`(把 Dart 侧传来的字节缓冲还原成消息),与代码地址无关。
  - flutter_rust_bridge 2.12.0 在本项目用的是 PDE dispatcher 模式(导出面只有 `frb_pde_ffi_dispatcher_primary`/`_sync` 等 25 个符号,没有 per-function 的 `frbgen_*` 导出),Dart 侧一律**按符号名 `dlsym`**、再按索引分发,不比较地址;而两个字节完全一致的函数在语义上本就等价,折叠后调哪一份行为都一样。**风险结论:无实际风险,可以采纳。**
- **改动**:`tool/build_prebuilt.dart` 的 `_crossEnv()` 里,Android 分支的 `RUSTFLAGS` 在已有的 `-C link-arg=-Wl,-z,max-page-size=16384` 之后追加 `-C link-arg=-Wl,--icf=all`。
- **验证方式**:与前两条相同的 Android 交叉编译流程(`ANDROID_HOME=E:\sdk\android`,NDK r28.2.13676358,Windows 宿主直接交叉编译四个 target),`dart run tool/build_prebuilt.dart --group android` 四个 target 全部构建成功。
- **实测体积**(**本轮 baseline 是当场重新构建出来的对照组**,不是取 `prebuilt/` 里已有的产物——见下面"数据口径提醒"):

  | target | 改动前(当场重建) | 改动后 | 降幅 |
  |---|---|---|---|
  | arm64-v8a | 508,808 字节 | 502,248 字节 | −6,560 字节(−1.29%) |
  | armeabi-v7a | 347,464 字节 | 345,000 字节 | −2,464 字节(−0.71%) |
  | x86_64 | 567,720 字节 | 561,128 字节 | −6,592 字节(−1.16%) |
  | x86 | 591,568 字节 | 584,336 字节 | −7,232 字节(−1.22%) |

  收益约 0.7%–1.3%,四个 target 全部为真实正收益,无一持平或变大。x86/arm64 两组数字都用"单 target 构建"和"`--group android` 整组构建"各测了一遍,两种方式结果完全一致(可复现,非噪声)。
- **数据口径提醒(重要,别照抄上一条的表)**:开工时 `prebuilt/android/jniLibs/` 里躺着的四个 `.so` 是 641,280/443,560/727,952/761,224 字节,即上一条 `-Zlocation-detail` 记录的"改动后"产物——它们**早于 `-Z build-std-features=` 落地**,拿它们当本轮 baseline 会把上一条的 ~22% 收益重复计入本条。因此本轮特地把 flag 摘掉重新构建了一组真 baseline。另外注意:上一条 `-Z build-std-features=` 小节记录的"改动后"四个数字(502,248/345,000/561,128/584,336)与**本轮加了 `--icf=all` 之后**的数字逐字节相同,而本轮不带 `--icf=all` 重建出来的是 508,808 等偏大一点的值——两者对不上,原因未查明(该小节的产物当时并未留在 `prebuilt/` 下)。以后引用那一条的绝对值时留个心眼。
- **正确性验证**:
  - `cargo test`(`rust/`):**24 passed / 0 failed**,与改动前一致。
  - **导出符号比对**:用 NDK 的 `llvm-nm -D --defined-only` 分别 dump 不带/带 `--icf=all` 的 x86 产物,两边都是**同样的 25 个动态导出符号,`diff` 完全一致**——桥接入口(`frb_pde_ffi_dispatcher_primary`/`_sync`、`frb_get_rust_content_hash`、`store_dart_post_cobject`、`free_zero_copy_buffer_*` 等)一个都没被折没。
  - **真机 dlopen 冒烟**:`adb devices` 有一台在线设备(WSA,`ro.product.cpu.abi=x86_64`,API 33)。用 NDK 的 `x86_64-linux-android21-clang` 编了一个 20 行的 C 小程序,push 到 `/data/local/tmp/svgx_smoke/` 后 `dlopen` 本轮构建的 x86_64 `.so` 并逐个 `dlsym` 上述关键符号:**加载成功,9 个符号全部解析到非空地址,RESULT PASS**。同时肉眼可见 `free_zero_copy_buffer_u8`/`_i8` 落在同一地址、`_u16`/`_i16` 落在同一地址(这类同布局实例本来就会共用一份实现,不带 `--icf=all` 时同样如此)。
- **方法学局限(如实标注)**:
  - 只在 Android 四个 target 上实测,iOS/macOS/Linux/Windows 未验证(且本轮改动只写在 `_crossEnv()` 的 Android 分支里,本就只对 Android 生效)。
  - 风险审查是对**本仓库自己的 Rust 源码**做的穷举;`usvg`/`svgtypes`/`flutter_rust_bridge`/std 这些依赖内部是否存在依赖函数地址唯一性的代码,只做了"本项目的调用方式不涉及"这一层推断,**没有逐依赖审计,也没有做函数指针身份相关的 fuzz**。
  - 真机冒烟只做到"加载 + 符号解析"这一层,**没有在设备上跑通完整的 `parse_svg` 渲染链路**(WSA 上跑 Flutter example 另有 Impeller 黑屏的已知坑,见 `docs/wsa-impeller-debugging.md`),也没有跑 `flutter test`(本轮未重建宿主库)。
- **结论**:**保留**该改动。`tool/build_prebuilt.dart` 的 Android 分支 `RUSTFLAGS` 追加 `-C link-arg=-Wl,--icf=all`;`prebuilt/android/jniLibs/*/libsvgx.so` 四个文件已用新产物覆盖;`prebuilt/MANIFEST.json` 已由 `dart run tool/build_prebuilt.dart --restage` 同步(源码哈希 `1f22b2c26395d21bb2ac2d125adcd5d83225f3d8d779b75d0f276521bfd2b97e`,与前两条一致——本轮只动链接参数,未动 Rust 源码)。

## `-Z build-std-features=optimize_for_size`(2026-08-26)

- **动机**:已落地的 `-Z build-std-features=`(空值)只是清空 std 默认 feature 集(去掉 `backtrace`/`panic-unwind`),还没有让 build-std 重编的 core/alloc/std 本身走体积优先的代码路径。`optimize_for_size` 是 std 自带的一个具名 feature,开启后排序、整数格式化、float 转换等一部分内部实现会换成体积优先而非速度优先的版本(min-sized-rust 项目记录过量级参考,但那是极简 hello-world 场景,不直接等于本项目收益)。
- **前提确认**:该 feature 是"叠加项"而非与已落地的 `-Z build-std-features=`(空值)二选一——`kBuildStdFlags` 里把值从空字符串改成 `optimize_for_size` 即可,不需要额外的工具链前提(仍是同一 nightly + `-Z build-std=std,panic_abort`)。
- **改动**:`tool/prebuilt_common.dart` 的 `kBuildStdFlags`,`-Z build-std-features=` 的值从空改为 `-Z build-std-features=optimize_for_size`。
- **验证方式**:与既有流程相同的 Android 交叉编译(`ANDROID_HOME=E:\sdk\android`,NDK r28.2.13676358,Windows 宿主直接交叉编译四个 target),`dart run tool/build_prebuilt.dart --group android` 四个 target 全部构建成功,无编译错误。
- **实测体积**(改动前 baseline 取自当前已提交 `prebuilt/` 下的产物,即上一条 `--icf=all` 落地后的状态):

  | target | 改动前 | 改动后 | 降幅 |
  |---|---|---|---|
  | arm64-v8a | 502,248 字节 | 491,384 字节 | −10,864 字节(−2.16%) |
  | armeabi-v7a | 345,000 字节 | 338,856 字节 | −6,144 字节(−1.78%) |
  | x86_64 | 561,128 字节 | 548,792 字节 | −12,336 字节(−2.20%) |
  | x86 | 584,336 字节 | 572,968 字节 | −11,368 字节(−1.95%) |

  四个 target 降幅在 1.78%–2.20% 之间,均为真实正收益,无一持平或变大。
- **`cargo test`(`rust/`)**:**24 passed / 0 failed**,与改动前完全一致,功能未受影响。
- **方法学局限**:仅验证了 Android 四个 target;未逐一验证 iOS/macOS/Linux/Windows 其余 9 个 slice(理论上同一套 `-Z` 参数对所有 target 生效)。未跑 `flutter test`(本次未重新构建宿主 `.dll`)。
- **结论**:**保留**该改动。`tool/prebuilt_common.dart` 的 `kBuildStdFlags` 中 `-Z build-std-features=` 改为 `-Z build-std-features=optimize_for_size`;`prebuilt/android/jniLibs/*/libsvgx.so` 四个文件已用新产物覆盖;`prebuilt/MANIFEST.json` 已由 `dart run tool/build_prebuilt.dart --restage` 同步(源码哈希 `1f22b2c26395d21bb2ac2d125adcd5d83225f3d8d779b75d0f276521bfd2b97e`)。

## `-Z no-unique-section-names`(验证后跳过,2026-08-26)

- **动机**:候选项列表里记录的"顺手一试"低风险项——只对 ELF 目标生效,预期让 rustc 复用统一的 `.text`/`.data` 段名而非每符号一个独立段名,理论上略微减小节头表开销。
- **前提确认**:未凭记忆直接加。先用 `rustc +nightly-2026-06-24 -Z help` 实测确认该 flag 在此 nightly 下确实存在,拼写正确:
  ```
  -Z    no-unique-section-names=val -- do not use unique names for text and data
        sections when -Z function-sections is used
  ```
  同时确认了 `-Z function-sections` 本身也存在,但项目当前的 RUSTFLAGS(`kBaseRustFlags`/`kBuildStdFlags`/Android 专属追加)里**没有**显式传 `-Z function-sections`——`no-unique-section-names` 的帮助文本明确写着它只在 `-Z function-sections` 被使用时才有效果,因此这次验证已经预期到收益可能是零,仍按流程实测确认。
- **改动**:仅追加到 `tool/build_prebuilt.dart` 的 `_crossEnv()` Android 分支(未放进全局 `kBaseRustFlags`)——因为该 flag 只对 ELF 布局有意义,Windows(PE)/macOS/iOS(Mach-O)上的行为未经验证,不适合放进全平台共用常量。
- **验证方式**:与既有流程相同的 Android 交叉编译,`dart run tool/build_prebuilt.dart --group android` 四个 target 全部构建成功,无编译错误。
- **实测体积**(改动前 baseline 是上一条 `optimize_for_size` 落地后的产物):

  | target | 改动前 | 改动后 | 差值 |
  |---|---|---|---|
  | arm64-v8a | 491,384 字节 | 491,384 字节 | 0(无变化) |
  | armeabi-v7a | 338,856 字节 | 338,856 字节 | 0(无变化) |
  | x86_64 | 548,792 字节 | 548,792 字节 | 0(无变化) |
  | x86 | 572,968 字节 | 572,968 字节 | 0(无变化) |

  四个 target 逐字节完全相同,无任何体积变化——与前提确认阶段的预期一致(项目未启用 `-Z function-sections`,该 flag 因此是无效果的空操作)。
- **`cargo test`(`rust/`)**:**24 passed / 0 failed**,功能未受影响(但这项本就不是功能相关改动)。
- **结论**:**跳过,不落地**。实测确认该 flag 在当前配置下是纯粹的空操作(zero-byte 差异),没有任何体积收益,徒增一个不产生价值的 `-Z` unstable flag,故已从 `tool/build_prebuilt.dart` 中移除。`prebuilt/android/jniLibs/*/libsvgx.so` 最终产物对应的是"仅 `optimize_for_size`"这一改动状态,不含本条改动。若未来想真正拿到这项收益,需要先评估是否要连带引入 `-Z function-sections`(会改变默认代码布局,需要单独评估影响)。

## `-Wl,--retain-symbols-file=<file>`(摸底后判定不做,2026-08-26)

- **动机**:候选项表里最后一个未验证项,也是被标注"工程量较大、风险较高"的一项。思路是给链接器一份显式的符号白名单,把白名单之外的符号全部当死代码丢弃。网上能查到的最激进案例(LTO+DCE 组合)宣称最高 −90%,但那是"库导出面很宽、白名单能砍掉绝大部分"的场景,与 svgx 的形态是否匹配需要先摸底才知道。
- **纪律**:按 `docs/SIZE_OPTIMIZATION.md` 候选表里自己写下的前置条件——"动手前必须先用 `nm -D`/`readelf --dyn-syms` 摸清现有符号表基线"——先摸底再决定动不动手,不凭预期直接改构建脚本。

### 第一步:摸清导出符号基线

工具用 Android NDK r28.2.13676358 自带的 `llvm-nm.exe` / `llvm-readelf.exe`(`E:\sdk\android\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\`)。

`llvm-nm -D --defined-only prebuilt/android/jniLibs/arm64-v8a/libsvgx.so` 的完整输出(**25 个符号,一个不多**):

```
frb_create_shutdown_callback                        frb_rust_vec_u8_free
frb_dart_fn_deliver_output                          frb_rust_vec_u8_new
frb_dart_opaque_dart2rust_encode                    frb_rust_vec_u8_resize
frb_dart_opaque_drop_thread_box_persistent_handle   free_zero_copy_buffer_f32 / f64
frb_dart_opaque_rust2dart_decode                    free_zero_copy_buffer_i8 / i16 / i32 / i64
frb_free_wire_sync_rust2dart_dco                    free_zero_copy_buffer_u8 / u16 / u32 / u64
frb_free_wire_sync_rust2dart_sse                    store_dart_post_cobject
frb_get_rust_content_hash
frb_init_frb_dart_api_dl
frb_pde_ffi_dispatcher_primary
frb_pde_ffi_dispatcher_sync
```

四个 ABI 逐一核对,**全部都是 25 个 defined 导出符号**(undefined 导入数分别为 arm64 63 / v7a 54 / x86 61 / x86_64 61,那是 libc/liblog 等外部依赖,与本项目导出无关):

| ABI | defined 导出 | undefined 导入 | `.symtab` 段数 | `.dynstr` 大小 |
|---|---|---|---|---|
| arm64-v8a | 25 | 63 | 0 | 0x581(1409 B) |
| armeabi-v7a | 25 | 54 | 0 | 0x507(1287 B) |
| x86_64 | 25 | 61 | 0 | 0x561(1377 B) |
| x86 | 25 | 61 | 0 | 0x561(1377 B) |

这印证了 `docs/SIZE_OPTIMIZATION.md` 已排除区里 `-Zdefault-visibility=hidden` 那一行的判断:cdylib 已经靠 version script 把导出面收到了最小,`.text` 里的内部符号根本没进 `.dynsym`。

### 第二步:核实"运行时必需"的最小集合

不沿用之前 `--icf=all` 验证时留下的"PDE 分发模式、25 个导出符号"这个数字,重新从两侧核对:

- Dart 侧生成代码本身不含符号名字符串。`lib/src/rust/frb_generated.io.dart` 里的 `RustLibWire` 只持有一个 `_lookup = dynamicLibrary.lookup`,把按名查找委托给了 flutter_rust_bridge 运行时——这正是 PDE(primary dispatcher)模式的形态:所有业务 API 不各自导出一个 `wire_xxx` 符号,而是统一走 `frb_pde_ffi_dispatcher_primary` / `_sync` 两个入口 + 索引分发。
- 在 pub cache 的 `flutter_rust_bridge` 包源码里 grep 符号名字面量,查到**14 个 `frb_*`** 全部被按名 `dlsym`,与上面 dump 出的 14 个 `frb_*` 逐一对应,外加 `store_dart_post_cobject`(Dart VM 回调注册,`dart_api_dl` 必需)。合计 **15 个铁定不能丢**。
- 剩下 10 个 `free_zero_copy_buffer_{i,u}{8,16,32,64}` / `_f{32,64}` 是 zero-copy 类型化数组的释放回调,由 Dart VM 的 external typed data finalizer 在运行时按名解析。**关键观察**:这 10 个符号在 `nm -D` 输出里只占 3 个不同地址(`0x31430` / `0x31450` / `0x31470` 和 `0x31490` 共 4 个,按位宽合并),`--icf=all` 早已把它们折叠掉了——也就是说这 10 个名字对应的代码体积几乎为零,只剩符号表条目本身的开销。

### 第三步:算裁剪空间 —— 结论是接近零

两条硬事实,任一条都足以否掉这项:

1. **必需集合几乎等于全集**。25 个里 15 个铁定必需,另外 10 个是运行时按名解析的 finalizer,砍掉它们的收益上限是:`.dynsym` 条目 10 × 24 B = 240 B,加 `.dynstr` 里的名字约 280 B,加 `.hash`/`.gnu.hash` 桶的少量收缩,合计 **约 600 字节,占 arm64 产物 491,384 字节的 0.12%**。而代价是把一组"看起来没人引用、其实由 VM 按名解析"的符号删掉——这正是最容易在真机上炸成 `dlsym` failed 的那类改动。收益 0.12%、风险是运行时崩溃,性价比明确为负。
2. **这个 flag 在当前配置下根本不产生作用**。用 `ld.lld --help` 确认其定位:它和 `--strip-all` / `--discard-all` / `--discard-locals` 归在同一族,过滤的是**静态符号表 `.symtab`**,而不是动态链接必需的 `.dynsym`(后者少一个符号就会导致运行时解析失败,链接器不会替你删)。而项目 `[profile.release]` 早已开了 `strip=true`,`llvm-readelf -S` 实测四个 ABI 的产物**全都是 0 个 `.symtab` 段**(总共只有 25 个 section,连 `llvm-nm` 不带 `-D` 都直接报 `no symbols`)。也就是说这个 flag 要过滤的东西已经被 `strip=true` 整段删光了,加上它是**保证为零**的空操作,和上一条 `-Zno-unique-section-names` 是同一类结局。

> 顺带说明网上那个 −90% 案例为什么不适用:那类场景是一个导出面很宽的 C/C++ 库(动辄成千上万个导出符号),白名单能让链接器把大片不可达代码真正 DCE 掉。svgx 是 cdylib + FRB 的 PDE 分发模式,导出面本来就只有 25 个,代码可达性早已由 `lto=true` + version script 收紧到位,没有留给白名单发挥的空间。

- **是否落地**:**不落地,不做任何代码改动**。既没有新建 `tool/android_retain_symbols.txt`,也没有动 `tool/build_prebuilt.dart` 的 `_crossEnv()`。
- **为什么没走完"实测编译对比"流程**:这次在第一步摸底就拿到了确定性结论(`.symtab` 已不存在 → flag 必然零效果;必需符号占全集 15/25 → 上限 0.12%),继续跑一遍四 ABI 交叉编译只会得到一份和 `-Zno-unique-section-names` 一模一样的全零差值表,不产生新信息。本条记录里的所有符号数、段数、字节数均为上述 `llvm-nm` / `llvm-readelf` / `ls -l` 的真实输出,不含估算(唯一的估算是"约 600 字节"这个理论上限,已在文中标明算法)。
- **产物状态**:`prebuilt/android/jniLibs/*/libsvgx.so` 未重建、未改动,仍是 `optimize_for_size` 落地后的那组产物(arm64-v8a 491,384 / armeabi-v7a 338,856 / x86_64 548,792 / x86 572,968 字节,已用 `ls -l` 重新核对)。`MANIFEST.json` 无需 restage。
- **结论**:候选项表里这一行更新为"已摸底,判定不做"。至此候选表三项全部有了终局结论,**暂无其他待验证候选项**;后续瘦身若还要继续,剩下的只有"砍功能/砍依赖/砍 32 位 ABI"这类产品级取舍(见 `docs/SIZE_OPTIMIZATION.md` 已排除区末尾几行),不再是加编译 flag 能解决的范畴。
