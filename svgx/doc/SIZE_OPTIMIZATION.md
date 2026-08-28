# svgx 体积优化全记录

本文件汇总 svgx（Rust 核心通过 `flutter_rust_bridge` 编成 cdylib、预编译分发）体积瘦身工作的**全部已落地项、候选项、已排除项**及各自理由。目的是避免以后重复调研已经有结论的方向。

- 具体改动的代码位置：`tool/prebuilt_common.dart`（`kToolchain`/`kBaseRustFlags`/`kBuildStdFlags`）、`tool/build_prebuilt.dart`（`_crossEnv()` 里 Android 专属 RUSTFLAGS）、`rust/Cargo.toml`（`[profile.release]` + 依赖 feature）。
- 每次新增改动，请在本文件"已落地"表格追加一行，并在"验证方法论"一节的流程下走完整套验证再合入。
- 与 `docs/size-optimization-history.md` 的关系：那份文件保留每项改动的完整调研过程记录（面向"当初为什么这么决定"的历史脉络），本文件是**结论速查表**（面向"现在到底采纳了什么、还剩什么可以试"），两者不冲突，改动落地时两边都应更新。

## 一、已落地

全部改动统一走 `rust-toolchain = nightly-2026-06-24` + `-Z build-std=std,panic_abort`（全平台，不止 Android），在此基础上叠加：

| # | 改动 | 动机 | 实测收益（Android，4 ABI） | 落地日期 |
|---|---|---|---|---|
| 1 | `usvg` 依赖 `default-features = false`（关闭 `text`/`system-fonts`/`memmap-fonts`） | 图标渲染场景用不上字体排版/系统字体加载，代价是静态路径 `<text>` 不再渲染（动画路径 `TextPainter` 不受影响） | Windows DLL 实测 1.052MiB→0.468MiB（−55.5%），是全项目单项收益最大的一次 | 2026-08-25 首次，2026-08-26 因改名事故重新应用 |
| 2 | `[profile.release]`：`opt-level="z"`、`lto=true`、`codegen-units=1`、`strip=true`、`panic="abort"` | 常规 Rust release 体积优化标准做法；`panic=abort` 经核实 flutter_rust_bridge 2.12.0 的 `#[frb(sync)]` 路径本就不做 unwind 捕获，对本项目无安全网损失 | 未单独测量（与其余优化叠加在一起的基线） | 2026-08-25 |
| 3 | 固定 nightly 工具链 + `-Z build-std=std,panic_abort` + `-Cpanic=immediate-abort` | 重编 std 本身，配合 immediate-abort panic 策略移除 unwind 相关机制 | 项目注释记录约 21% 额外收益（早期评估数字，未在本文件的分项表格里单独拆出） | 2026-08-25 起（全平台统一，CI 见 `.github/workflows/svgx-prebuilt.yml`） |
| 4 | `-Zlocation-detail=none` + `-Zfmt-debug=none`（叠加进 `kBaseRustFlags`） | 去掉 panic/track_caller 的文件名行号信息 + 精简 `#[derive(Debug)]` 实现 | arm64-v8a 653,336→641,280（−1.85%）、armeabi-v7a 450,464→443,560（−1.53%）、x86_64 739,928→727,952（−1.62%）、x86 773,504→761,224（−1.59%） | 2026-08-26 |
| 5 | `-Z build-std-features=`（空值，清空 std 默认 feature 集，去掉 `backtrace`/`panic-unwind`） | build-std 默认会拉入 `backtrace`/`panic-unwind` feature，连带 gimli/addr2line/miniz_oxide 等符号化代码；项目从不 unwind（只链 `panic_abort`）也从不格式化 backtrace（`immediate-abort` 直接终止），这些代码是纯浪费 | arm64-v8a 641,280→502,248（−21.7%）、armeabi-v7a 443,560→345,000（−22.2%）、x86_64 727,952→561,128（−22.9%）、x86 761,224→584,336（−23.2%）——**目前收益最大的单项改动** | 2026-08-26 |
| 6 | `-C link-arg=-Wl,--icf=all`（lld 相同代码折叠，只写在 `build_prebuilt.dart` 的 Android 分支） | 折叠泛型单态化产生的字节相同函数体；采纳前已穷举审查本仓库 Rust 源码（无函数指针地址比较/fn 指针当 key/vtable 比较），FRB 走按名 `dlsym` + 索引分发，不依赖地址唯一性 | arm64-v8a 508,808→502,248（−1.29%）、armeabi-v7a 347,464→345,000（−0.71%）、x86_64 567,720→561,128（−1.16%）、x86 591,568→584,336（−1.22%）。**注意 baseline 是当场摘掉 flag 重建的对照组**，不是 #5 行记录的数字（两者对不上，详见 `docs/size-optimization-history.md` 该小节的"数据口径提醒"） | 2026-08-26 |
| 7 | `-Z build-std-features=optimize_for_size`（在已落地的空值基础上叠加） | 让 build-std 重编的 core/alloc/std 走体积优先而非速度优先的内部实现（排序/整数格式化/float 转换等） | arm64-v8a 502,248→491,384（−2.16%）、armeabi-v7a 345,000→338,856（−1.78%）、x86_64 561,128→548,792（−2.20%）、x86 584,336→572,968（−1.95%） | 2026-08-26 |

**方法学局限（对 #4、#5、#6、#7 都适用）**：仅在本机用 Android NDK 交叉编译验证了 Android 四个 target；iOS/macOS/Linux/Windows 其余 9 个 slice 理论上同一套 flag 生效，但未逐一实测验证，会在下次跑 `svgx-prebuilt.yml` 或本地重建这些平台时自动带上新 flag。`cargo test`（`rust/`）24 项全过，未跑 `flutter test`（本次未重新构建宿主 `.dll`）。

### 当前基线（截至 #7 落地，2026-08-26）

以下是**当前工作区里 `prebuilt/android/jniLibs/*/libsvgx.so` 的实际字节数**（已核对与 `prebuilt/MANIFEST.json` 一致），是叠加上表 1-7 项全部优化后的已知最小值，后续新优化项应以这组数字作为改动前 baseline：

| ABI | 字节数 |
|---|---|
| arm64-v8a | 491,328 |
| armeabi-v7a | 338,584 |
| x86_64 | 548,480 |
| x86 | 572,528 |

2026-08-26 评估 `--retain-symbols-file` 时用 `ls -l` 核对过上一版数字（491,384 / 338,856 / 548,792 / 572,968），该项最终未落地、产物未变。

上表已更新为 **Rust 侧性能优化落地后**的字节数（2026-08-26，见 `docs/performance-benchmarks.md` 的"Rust 侧专项优化"一节）。该轮改的是 `rust/src/api/svg.rs` 的解析代码，不是瘦身项，但顺带让四个 ABI 各小了 72~440 字节（去掉了 `format!` 的 `UpperHex` 格式化路径与 tiny-skia `PathSegmentsIter` 的单态化代码）；Windows x64 反而 +512 字节。净效果视为**体积中性**，作为新 baseline 记录在此。

⚠️ **这组数字截至写入时是最新的，但可能已被后续正在验证的候选项（见下方"二、候选项"）覆盖**——引用前先看本节上方"已落地"表格是否已经追加了 #8 及之后的行，那里的"实测收益"列会给出更新的对照组。

## 二、候选项（调研过、有正面预期，尚未验证/落地）

| 选项 | 预期收益 | 与现有配置的关系/冲突 | 未落地原因 |
|---|---|---|---|
| `-Wl,--retain-symbols-file=<file>`（链接器符号白名单） | 他人在 LTO+DCE 组合下实测最高 −90%（场景不同，数字仅供参考量级，不代表 svgx 能达到） | 与现有 flags 无冲突 | **已摸底，结论是不做**（2026-08-26）。按流程先用 NDK r28.2 的 `llvm-nm -D --defined-only` / `llvm-readelf -S` 摸清基线，两条硬事实直接否掉这项：①四个 ABI 的动态导出符号**各只有 25 个**，全部是 flutter_rust_bridge 运行时按名 `dlsym` 的桥接入口（14 个 `frb_*` + `store_dart_post_cobject` + 10 个 ICF 已折叠成 3 个地址的 `free_zero_copy_buffer_*`），**必需集合几乎等于全集**，理论上限也就省几百字节（≈0.13%）；②该 flag 过滤的是 `.symtab`，而 `[profile.release] strip=true` 已让产物**根本不含 `.symtab` 段**（`llvm-readelf -S` 实测 0 个），所以它在当前配置下是保证为零的空操作。收益上限远低于 1%、且写错白名单会引入运行时 `dlsym` 失败的崩溃风险，性价比为负。详见 `docs/size-optimization-history.md` |
| `-Zno-unique-section-names` | 定性收益，只在 ELF（Android/Linux）目标生效，量级未知 | 风险低，与现有配置无冲突 | **已尝试，失败原因是：无收益**。2026-08-26 已用 `rustc +nightly-2026-06-24 -Z help` 确认该 flag 确实存在，并实测 Android 四个 target ——但四个 `.so` 逐字节完全无变化（0 差异）。原因：该 flag 的帮助文本注明只在 `-Z function-sections` 被使用时才有效果，而项目当前的 RUSTFLAGS 里没有传 `-Z function-sections`，因此是纯粹的空操作。已从 `tool/build_prebuilt.dart` 移除，详见 `docs/size-optimization-history.md` |
| `-Zdump-mono-stats` | 不是瘦身选项本身，是诊断工具 | 无冲突 | 用途是配合 `cargo-bloat`/`twiggy` 定位泛型单态化的体积热点，指导后续裁剪方向，不直接产生体积变化——按需使用，不算"要不要落地"的候选 |

### 反方向的一张表：`opt-level` 是"可以花体积买速度"的旋钮（2026-08-26 实测，未落地）

本文件其余部分都在讨论"怎么更小"。这一条相反，是**已落地第 2 项 `opt-level="z"` 的机会成本**，实测数字放在这里是为了以后有人问"我们为速度付了多少体积"时不用重新调研。完整表格与方法学局限见 `docs/performance-benchmarks.md` 的"`opt-level`：实测取舍全表"。

| 配置 | 四 ABI 合计字节 | vs `"z"` | `mdi1000` parse avg | vs `"z"` |
|---|---|---|---|---|
| **`"z"`（现状）** | **1,950,920** | — | 12.288 µs | — |
| `"s"` | 2,188,324 | **+12.2%** | 8.188 µs | **−33.4%** |
| `2` | 2,639,364 | +35.3% | 7.409 µs | −39.7% |
| `3` | 2,704,276 | +38.6% | 7.088 µs | −42.3% |

结论：`"s"` 是帕累托甜点（+12% 体积买 −33% 解析耗时），但**本轮没有改**——`parse_svg` 现在只有 0.0136ms、1000 图标滚动本就 0 掉帧，速度收益落不到任何用户可见指标上，而 +237KB 是实打实要下发的。属于需要 owner 拍板的产品取舍，不是技术优化。

**顺带排除掉一个方向**：按包 `opt-level` 覆盖（`[profile.release.package.usvg] opt-level = 3` 之类）已实测，**每一种都被全局 `"s"` 在体积和速度两个维度同时压倒**，因为 fat LTO 之后单独提高某个 crate 的优化级别买不到速度却全额付了它的代码膨胀。这条路排除，不要重复试。

**候选表已清空**：上表三行里，`--retain-symbols-file` 与 `-Zno-unique-section-names` 都已实测/摸底否掉，`-Zdump-mono-stats` 本就是诊断工具而非瘦身项。**暂无其他待验证的候选项**——历史上调研过并否决的方向全部列在下方"三、已排除"区，新想到的方向先去那张表里查一遍，别重复劳动。若要继续瘦身，剩下的空间基本只在"砍功能/砍依赖/砍 ABI"这类产品级取舍上（已排除表最后几行），不再是加一个编译 flag 能解决的了。

## 三、已排除（不要重新调研）

| 方向 | 排除理由 |
|---|---|
| UPX 压缩 `.so` | Android linker 要求 `.so` 未压缩且页对齐，压缩后加载崩溃，无变通空间（多个 GitHub issue 印证：`upx/upx#835` 等） |
| `-Z share-generics` | 与项目已采用的 `-Z build-std` 组合已知产生 undefined symbol 链接错误（`rust-lang/rust#96486`） |
| `-Zvirtual-function-elimination` | 官方文档警告可能在"外部 crate 构造 dyn trait"场景下 miscompile——svgx 是 cdylib+FFI，正中风险模式 |
| `-Ztune-cpu` | 只影响 x86 指令调度，Android/iOS 目标是 aarch64，无效 |
| `-Z merge-functions` | nightly 默认已开启 `aliases`（PR `#100035` 修复了 opt-level=s/z 下不生效的历史 bug），显式传无增量收益 |
| `-Z trim-paths` | release profile 默认已是 `object`，且与已采纳的 `-Zlocation-detail=none` 高度重叠，预期约等于零 |
| `-Zdefault-visibility=hidden` | cdylib 已靠 version script 只导出 `#[no_mangle]` 符号，增量收益存疑；`protected` 值在老版本 GNU ld 上直接链接失败 |
| 换掉 roxmltree/tiny-skia-path 等 usvg 底层依赖 | 没查到任何成熟先例，投入产出比不明 |
| `regex` crate | 核实过依赖树里**根本没有引入**，usvg 的 CSS 选择器走的是 `simplecss`（非正则实现）——历史上常见的体积大户，但本项目里不存在，可直接排除、不用再查 |
| `imagesize`/`flate2`/`miniz_oxide`/`crc32fast`（usvg 的 `.svgz`/内嵌位图尺寸探测支持） | usvg 0.44 没有把这些做成可选 feature（能通过 feature 关掉的只有已关闭的 `text`/`system-fonts`/`memmap-fonts`），要去掉只能 fork/patch usvg 源码，且会破坏 `<image>` 支持等正常功能，性价比低 |
| `flutter_rust_bridge` 传递依赖（tokio/futures/backtrace/threadpool 等） | 实测占比很小（tokio 仅 2.4%，且已是窄 feature 集），FRB 版本锁定 `=2.12.0`，逐一 `default-features=false` 去精简收益极低且可能破坏 FRB 运行时期望能力 |
| `svgtypes` 可选 feature | 该 crate 本身没有额外可选 feature，当前用法已是最小依赖面 |
| 换成静态链接（`.a`）而非动态 `.so` | 不会缩小体积（占大头的是代码本身，跟链接方式无关），反而会重新引入已经刻意移除的 NDK 依赖要求（见 `android/build.gradle` 的 `PRECOMPILED_MIGRATION_PLAN` 迁移背景），是架构倒退 |
| 砍 armeabi-v7a / x86（32 位 ABI） | 能省约 1.22MB（四包总体积的一半），但**只在下游打 universal/fat APK 时才对终端用户体积有实质收益**——如果下游走 Android App Bundle + Play 动态分发，Play 按设备 ABI 做 split delivery，砍不砍对终端下载体积影响很小。这是产品/兼容性决策，不是纯技术优化，需要先确认下游打包方式再评估 |
| nightly `build-std` 本身要不要切（历史遗留问题，现已不适用） | **已经是既成事实**：全平台（不止 Android）统一用固定 nightly 工具链 + build-std，见上文"已落地"表格 #3。以后不要再问"要不要切 nightly" |

## 四、验证方法论

每次改动瘦身相关 flag，按以下流程走，不要跳步：

1. 改 `tool/prebuilt_common.dart` 的 `kToolchain`/`kBaseRustFlags`/`kBuildStdFlags`（或 `tool/build_prebuilt.dart` 的 `_crossEnv()` 里 Android 专属 flags）。
2. 本机用 Android NDK 交叉编译：`cd svgx && dart run tool/build_prebuilt.dart --group android`。
3. 记录改动前后 4 个 ABI 的字节数——**必须是真实命令输出，不能估算**。
4. `cargo test`（`rust/` 目录）必须全过，确认功能未受影响。
5. 有实测正收益才覆盖 `prebuilt/android/jniLibs/*/libsvgx.so`，并跑 `dart run tool/build_prebuilt.dart --restage` 更新 `MANIFEST.json`。
6. 在本文件"已落地"表格追加一行，并在 `docs/size-optimization-history.md` 按既有风格追加完整调研过程记录。
7. 如果改动跨平台（比如换 nightly 版本号），如实标注"仅在 Android 验证，其余平台未逐一实测"这类方法学局限，不要假装已全平台验证。

## 五、跨平台架构候选（不是 RUSTFLAGS 调优，是链接方式变更）

这类候选不改 Rust 编译参数，改的是"静态链接 vs 动态链接"这个更底层的分发架构，收益量级和验证方式都跟上面几节的 flag 试验不同，单独记录。

### iOS：staticlib + `-force_load` → cdylib + XCFramework（2026-08-26 立项，进行中）

- **动机**：Windows 上实测过，同一份代码 staticlib 比 cdylib 大 **3.69×**（`svgx.lib` 1,813,706 字节 vs `svgx.dll` 491,008 字节，见 `docs/PRECOMPILED_MIGRATION_PLAN.md`）——staticlib 没有"最终链接"这一步，rustc 无法做死代码消除，项目又用 `-force_load` 主动关掉了 Xcode 端本可做的裁剪（保住 flutter_rust_bridge 的符号注册）。当前 iOS 产物：`ios/device/libsvgx.a` 1,153,600 字节（单架构 arm64）、`ios/simulator/libsvgx.a` 1,870,912 字节（lipo 合并 arm64-sim+x86_64）。
- **方案**：iOS target 改产出 cdylib（`libsvgx.dylib`），打包成 `.xcframework`（device + simulator 两个 platform variant，simulator 内部仍需 lipo 合并 arm64+x86_64），`ios/svgx.podspec` 从 `vendored_libraries`+`-force_load` 改为 `vendored_frameworks`。iOS App Store 不允许裸 `.dylib`，必须走 framework 封装，但这一步完全由 CI 在打包阶段完成，`Embed & Sign` 由 CocoaPods+Xcode 自动处理，消费方零手动操作。
- **状态**：已派 agent 实施+用 CI 的 macOS runner 验证（本机 Windows 没有 Apple 工具链，无法本地验证），结果未回收，见对话记录后续更新。
- **已知风险**：CocoaPods 对"动态库"XCFramework 的支持比"静态库"XCFramework 成熟（项目之前否决静态 XCFramework 正是因为 CocoaPods 有对应 issue），但仍需 CI 实测确认没有新的坑。

### macOS：staticlib + `-force_load` → cdylib + framework（2026-08-26 立项，**已完成并 CI 验证**）

- **动机**：同样的 3.7× 结构性膨胀在 macOS 上存在。改造前 `prebuilt/macos/libsvgx.a` 1,849,136 字节（lipo 合并 arm64+x86_64 的 fat 归档）。
- **实测收益**：改造后 `macos/svgx.framework/Versions/A/svgx` **881,208 字节**（同样是 arm64+x86_64 的 fat 二进制），加 786 字节的 `Info.plist` 共 881,994 字节，**降幅 52.3%**。导出符号 14 个 `frb_*`，`install_name` 为 `@rpath/svgx.framework/Versions/A/svgx`。
- **方案（与 iOS 的差异）**：macOS 只有**一个平台变体**，arm64 与 x86_64 只是同一个 fat 二进制的两个架构，没有需要 XCFramework 去区分的 slice——因此**不套 `.xcframework`，直接分发一个通用 `.framework`**。但 bundle 必须是**版本化**的（`Versions/A/…` 加三个符号链接），macOS 的 `codesign` 不接受 iOS 那种扁平 framework。`macos/svgx.podspec` 从 `vendored_libraries`+`-force_load` 改为 `vendored_frameworks = 'svgx.framework'`，同时删掉 `Classes/`（有源文件时 CocoaPods 会另编一个同名 framework 撞车）。
- **符号链接与 git**：三个符号链接以 mode `120000` 直接写进 index。它们**不进 MANIFEST.json** —— Windows 检出（`core.symlinks=false`）会把它们落成普通文本文件，纳入哈希会让清单依赖宿主。改由 CI 的 macOS job 断言其存在，那也是唯一能真正证明布局正确的手段。
- **Notarization / Hardened Runtime**：未出现问题。产物不预签名，Xcode 在 `Embed & Sign` 阶段用消费方证书重新签名；CI 的 `codesign --verify` 对嵌入后的 bundle 检查通过。这条 macOS 专属风险到此关闭。

### 已排除：把现有 fat `.a` 拆成两个单架构 `.a`，靠 `OTHER_LDFLAGS[arch=...]` 条件加载（2026-08-26）

- **表面上的论证是"universal app 场景不亏、单架构 app 场景能省"，实际不成立**：`-force_load` + fat archive 机制下，链接器读取 fat `.a` 时本来就只抽取匹配当前目标架构的 thin slice——不管是不是拆成两个文件，单架构 app 场景下最终链接进产物的字节数已经是最小的了，没有"另一半被浪费"这回事。拆分唯一可能省的是**仓库/pod 下载体积**（fat 归档本身的 lipo 对齐开销），量级很小，不影响最终 app 体积。
- **代价是真实的**：要按架构选文件必须绕开 `vendored_libraries`（该字段不支持按 `[arch=]` 条件筛选，会无脑把两个文件都塞进链接行），改手写 `OTHER_LDFLAGS[arch=arm64]`/`[arch=x86_64]` 条件分支——这条路径在 CocoaPods 生态里踩坑案例比 `[sdk=]`（设备/模拟器）分支少得多，正确性没法本机验证。
- **结论**：收益边际、有真实正确性风险，不做。真正能解决体积问题的是上面的"改动态库"方向，不是这个。
