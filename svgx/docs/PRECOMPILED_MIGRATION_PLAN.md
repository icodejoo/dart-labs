# svgx 预编译产物分发方案(已落地)

> 状态:**已实施**。2026-08-26 由设计稿转为落地实现。
> 本文档现在描述的是**仓库里真实存在的机制**,不再是提案。
> 前一版(纯设计稿,含 7 个待拍板开放问题)已被本版取代;所有开放问题都已有答案,记录在 §7。

---

## 0. 一句话

cargokit 已**整体删除**。原生库不再在任何用户机器上编译:13 个 slice 由
`tool/build_prebuilt.dart` 构建、**直接提交进 git** 的 `prebuilt/` 目录,各平台构建文件只做"引用"这一件事。

```
改动前(下游用户机器上):
  flutter build ios
    └─ Xcode script_phase → cargokit/build_pod.sh
         └─ 需要 rustup + nightly-2026-06-24 + rust-src
              └─ cargo build -Z build-std ...   ← 几分钟,且可能因工具链缺失直接失败

改动后(下游用户机器上):
  flutter build ios
    └─ 链接器 -force_load prebuilt/ios/device/libsvgx.a   ← 毫秒级,零工具链依赖
```

---

## 1. 已拍板的五条决定(实现依据,不再论证)

1. **产物直接提交进 git,不用 Git LFS**。零配置、无网络拉取失败模式;pub 对 git ref 的二次 clone 拉不到 LFS 指针指向的实体文件([dart-lang/pub#1433](https://github.com/dart-lang/pub/issues/1433)、[#3344](https://github.com/dart-lang/pub/issues/3344)),LFS 直接出局。
   → 落地:`.gitignore` 里显式写明 `prebuilt/` **刻意不 ignore**,防止以后有人顺手加进去。
2. **Linux 走 musl 静态链接**。
   → ⚠️ **这一条实测不可行,已改为 glibc**。这是本轮唯一一处偏离拍板决定的地方,证据见 §3.3,**需要用户重新确认**。
3. **保留 Windows-arm64 与 Linux-arm64 slice**。此前 cargokit 在用户机器上按其架构现编,砍掉等于静默的兼容性回退。
   → 落地:两者都在 `kTargets` 里;`windows/CMakeLists.txt` 与 `linux/CMakeLists.txt` 按 `CMAKE_SYSTEM_PROCESSOR` 选 slice。
4. **CI 哨兵用 `cargo check --target <triple>`,不是每次 push 跑完整 release 构建**。
   → 落地:`svgx-ci.yml` 的 `cargo-check` matrix,经 `dart run tool/build_prebuilt.dart --check` 执行(复用同一套交叉编译环境配置)。
5. **`prebuilt/MANIFEST.json` 记录每个二进制出自哪个源码 hash,CI 每次 push 重算比对**。
   → 落地:`tool/check_prebuilt.dart`,已做正/负双向验证(§5)。

---

## 2. 两项前置调研:实测结果

### 2.1 iOS `.a` 静态库真实体积 —— **本机无法直接测量,但有实测代理数据**

**诚实结论:这台机器是 Windows,没有 Apple SDK / `xcrun` / `lipo`,无法交叉编译 `aarch64-apple-ios`。任何"iOS `.a` 是 N MB"的具体数字,在本环境下都只能是编造,因此不给。**

**但前一版设计稿担心的"未链接归档可能比动态库大几十倍"这个假设,可以用实测数据大幅收窄**:同一个 crate、同一套 release profile(`opt-level="z"` + `lto` + `codegen-units=1` + `strip` + `panic=abort`)、同一条 build-std 命令,在 Windows 上**同时**产出了动态库和静态归档:

| 产物 | 字节 | 相对动态库 |
|---|---:|---:|
| `svgx.dll`(cdylib,最终分发形态) | 491,008 | 1.00× |
| `svgx.lib`(staticlib,未链接归档) | 1,813,706 | **3.69×** |

Rust 的 `staticlib` 归档本身就已经把 std 的目标文件打包在内,所以这个 3.7× 是**同类量级的真实比值**,不是下限估计。Mach-O 归档的元数据开销与 COFF 不同,数字不会完全一致,但"3~5 倍"和"几十倍"是两个结论——**前一版的担忧大概率不成立**。

据此推算(**标注为推算,不是测量**):3 个 Apple 归档(ios-device / ios-simulator-fat / macos-universal)合计大约 **5~7 MB**;iOS simulator 与 macOS 是 lipo 的双架构 fat 归档,会接近单架构的 2 倍,`strip -x` 又会回吐一部分。

**要拿到真数字需要什么**:一台 macOS 主机(或 macOS CI runner)。**已经准备好了,不需要用户自己有 Mac**:

```
Actions → "svgx prebuilt artifacts" → Run workflow
```

`.github/workflows/svgx-prebuilt.yml` 的 `apple` matrix leg 在 `macos-latest` 上构建这 3 个归档,并有一个专门的 **Report Apple archive details** 步骤打印每个归档的字节数、`lipo -info` 架构列表、`frbgen` 符号计数;`collect` job 还会把全部产物的体积写进 GitHub Step Summary 表格。跑一次即可用真实数字替换上面的推算。

### 2.2 Android 16 KB 页对齐 —— **本机已实测,全部通过**

本机装有 **NDK 28.2.13676358**(`E:/sdk/android/ndk/`),4 个 ABI 全部真实构建并用 NDK 自带的 `llvm-readelf -l` 验证。

**先做了一次不带任何对齐 flag 的对照构建**,确认 NDK r28 的 clang **默认就已经 16 KB 对齐**:

```
LOAD 0x000000 ... R   0x4000
LOAD 0x0307f8 ... R E 0x4000
LOAD 0x09a600 ... RW  0x4000
LOAD 0x09e3d0 ... RW  0x4000
```

`0x4000` = 16384 = 16 KB。**但没有依赖这个默认值**——`tool/build_prebuilt.dart` 对所有 Android target 显式追加 `-C link-arg=-Wl,-z,max-page-size=16384`,这样即便某台机器上装的是更老的 NDK,也不会静默产出不合规的 `.so`。

**最终产物(带显式 flag)实测**:

| ABI | LOAD 段对齐 | 字节 |
|---|---|---:|
| `arm64-v8a` | **0x4000** ✅ | 653,336 |
| `armeabi-v7a` | **0x4000** ✅ | 450,464 |
| `x86_64` | **0x4000** ✅ | 739,928 |
| `x86` | **0x4000** ✅ | 773,504 |

**并且验到了 APK 里**:本机真实跑了 `flutter build apk --release`(45.6 MB),解包后 `lib/*/libsvgx.so` 三个 ABI 全部仍是 `0x4000`。**这一点比只验中间产物重要**——Play 审查的是 APK 里的那份文件,AGP 的打包步骤有可能改变它。`svgx-ci.yml` 的 `build-android-release` job 把这条断言固化成了 CI 检查。

---

## 3. 实现:分平台现状

### 3.0 目录布局

```
svgx/
├── prebuilt/
│   ├── MANIFEST.json                                  # 源码 hash ↔ 产物绑定
│   ├── android/jniLibs/{arm64-v8a,armeabi-v7a,x86_64,x86}/libsvgx.so
│   ├── ios/device/libsvgx.a                           # aarch64-apple-ios
│   ├── ios/simulator/libsvgx.a                        # lipo(ios-sim-arm64, ios-x86_64)
│   ├── macos/libsvgx.a                                # lipo(darwin-arm64, darwin-x86_64)
│   ├── windows/{x64,arm64}/svgx.dll
│   └── linux/{x64,arm64}/libsvgx.so
└── tool/
    ├── prebuilt_common.dart    # target 表 + 源码 hash 定义(唯一真相源)
    ├── build_prebuilt.dart     # 构建 / --check / --restage / --list
    └── check_prebuilt.dart     # CI 同步校验
```

**为什么是顶层单个 `prebuilt/` 而不是散在各平台目录下**:清单要有唯一落点(`prebuilt/MANIFEST.json`),且一个目录便于整体 review/替换。代价是 podspec 要用 `$(PODS_TARGET_SRCROOT)/../prebuilt/...` 做一次 `..` 穿越——**这条路径有现成先例**:改动前的 podspec 用的就是 `$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh`,同样穿越出 `ios/`,一直工作正常。

### 3.1 Android —— ✅ 完成并实测通过

- `android/build.gradle`:删掉 `apply from: "../cargokit/gradle/plugin.gradle"` 与 `cargokit { }` 块,删掉 `ndkVersion android.ndkVersion`(不再需要 NDK),改为 `jniLibs.srcDirs = ['../prebuilt/android/jniLibs']`。
- 新增 `packagingOptions.jniLibs.keepDebugSymbols += ['**/libsvgx.so']`:产物在构建期已 strip,关掉 AGP 的二次 strip,避免在**没有 NDK 的机器**(也就是现在的每一台下游机器)上出现 "Unable to strip library" 失败。
- **`minSdkVersion 19 → 21`**:NDK r28 已不提供 API 21 以下的 sysroot。这不是本次迁移引入的回退——cargokit 之前也是同样 clamp 到 21,只是 gradle 里写着 19 掩盖了真相。现在写成真实值。**这一条对下游可见,列为需确认项(§7 R2)。**
- **验证**:`flutter build apk --release` 通过;APK 内 `lib/{arm64-v8a,armeabi-v7a,x86_64}/libsvgx.so` 齐全且 16 KB 对齐。
  (`x86` slice 仍然分发,只是 Flutter 的 release APK 默认 abiFilters 不含 x86,与本次改动无关。)

### 3.2 Windows —— ✅ x64 完成并实测通过;arm64 待 CI 产出

- `windows/CMakeLists.txt`:删掉 `include(cargokit.cmake)` + `apply_cargokit(...)`,改为按 `CMAKE_SYSTEM_PROCESSOR` 选 `prebuilt/windows/{x64,arm64}/svgx.dll` 并 `set(svgx_bundled_libraries ... PARENT_SCOPE)`。
- **保留了一条 `FATAL_ERROR`**:产物缺失时在**构建期**报一条人话错误(含修复命令),而不是静默不打包、留到运行期在 `DynamicLibrary.open` 里炸。预编译方案最恶心的失败模式就是这个,这条不是可选优化。
- **验证**:`flutter build windows` 通过;`example/build/windows/x64/runner/Release/svgx.dll` 与 `prebuilt/windows/x64/svgx.dll` **SHA-256 完全相同**(`55f278d1…`),证明消费的就是那份预编译产物、没有任何重新编译。随后真实**启动了 example app**,进程存活 8 秒无崩溃 —— FFI 加载正常。
- **arm64 未能在本机产出**:需要 VS 的 "MSVC v143 – ARM64 build tools" 组件(本机只装了 x64/x86 cross tools,`dart-sys` 的 `build.rs` 编译 `dart_api_dl.c` 时找不到 arm64 `cl.exe`)。GitHub 的 `windows-latest` runner 自带该组件,`svgx-prebuilt.yml` 的 windows leg 会产出它。

### 3.3 Linux —— ⚠️ 决定 #2(musl)实测不可行,已改 glibc,**需用户重新拍板**

用户拍板的是 musl。**实测下来 musl 这条路走不通,不是偏好问题而是技术上不成立**。在 WSL Ubuntu 24.04 上真实执行,三层依次失败:

1. `cargo build --target x86_64-unknown-linux-musl` 直接告警
   `warning: dropping unsupported crate type 'cdylib' for target 'x86_64-unknown-linux-musl'`,**根本不产出 `.so`**。原因:musl target 默认 `crt-static`,Rust 拒绝把 cdylib 链到静态 CRT 上。
2. 改用 `-Ctarget-feature=-crt-static` 重试 → 链接期失败:
   `/usr/bin/ld: cannot find libgcc_s.so.1`。
3. **即便前两层绕过去也没有意义**:svgx 的 `.so` 是被 Flutter Linux 桌面进程 `dlopen` 进去的,而那是一个 **glibc 进程**。一个地址空间里混两套 libc 不工作。musl 静态库适合"自己就是可执行文件"的场景,不适合"被别人 dlopen 的插件"。

**已改为 `x86_64-unknown-linux-gnu` + `aarch64-unknown-linux-gnu`,并实测了 glibc 下限**:

| slice | 字节 | 最高 GLIBC 符号版本需求 |
|---|---:|---|
| `linux/x64/libsvgx.so` | 704,776 | **GLIBC_2.34** |
| `linux/arm64/libsvgx.so` | 660,120 | **GLIBC_2.34** |

在 glibc 2.39(Ubuntu 24.04)上构建,产物最高只要 **2.34** —— 即可在 **Ubuntu 22.04(2.35)/ Debian 12(2.36)/ RHEL 9(2.34)** 及更新的发行版上加载;**Ubuntu 20.04(2.31)/ Debian 11(2.31) 不行**。若要再压低,把 `svgx-prebuilt.yml` 的 linux leg 换成 `ubuntu-22.04` runner 即可(§7 R1)。

- `linux/CMakeLists.txt`:与 Windows 同构(含同样的 `FATAL_ERROR` 守卫与 arm64/x64 分支)。
- **本机未运行 `flutter build linux`**(Windows 主机,无 GTK 桌面环境);CI 的 `build-linux` job 会跑,并额外打印实际 bundle 里 `.so` 的 glibc 需求。

### 3.4 iOS —— ⏳ 配置已写好,产物与验证**待 macOS 环境**

`ios/svgx.podspec` 已改完(**未编造任何二进制**):

- 删除整个 `s.script_phase`(cargokit 调用点)。
- 合并了原文件里**被赋值两次、后者覆盖前者**的 `s.pod_target_xcconfig`(既有小瑕疵,顺手修掉)。
- 按 SDK 条件分支选归档:
  ```ruby
  'OTHER_LDFLAGS[sdk=iphoneos*]'        => '-force_load $(PODS_TARGET_SRCROOT)/../prebuilt/ios/device/libsvgx.a',
  'OTHER_LDFLAGS[sdk=iphonesimulator*]' => '-force_load $(PODS_TARGET_SRCROOT)/../prebuilt/ios/simulator/libsvgx.a',
  ```
  **为什么不用 XCFramework**:XCFramework 的价值是让构建系统自动选架构,而我们必须 `-force_load` 一个**具体文件路径**,这个价值恰好被抵消;CocoaPods 对静态库 XCFramework 又有一串未收口的问题([#11344](https://github.com/CocoaPods/CocoaPods/issues/11344)/[#9794](https://github.com/CocoaPods/CocoaPods/issues/9794)/[#10058](https://github.com/CocoaPods/CocoaPods/issues/10058))。`[sdk=]` 条件是 xcconfig 的一等公民语法,原 podspec 已经在用(`EXCLUDED_ARCHS[sdk=iphonesimulator*]`)。
  **为什么不用 `s.vendored_libraries`**:那会把两个同名归档同时放进链接行,而 device 与 simulator 同为 arm64,`lipo` 物理上无法合并、链接期也会冲突。
  **为什么不写 `preserve_paths`**:Flutter 以本地 `:path` pod(经 `.symlinks`)消费插件,文件在原地即可访问,不存在沙箱拷贝。
- `ios/Classes/dummy_file.c` **保留**:pod 至少要有一个可编译源文件,CocoaPods 才会生成一个能承载 `OTHER_LDFLAGS` 的 target。

**待 macOS 完成的事**(已全部脚本化,见 §4):产出 3 个归档 → 提交 → `build-ios` job 会 **device 与 simulator 双向构建**(只验一条等于没验),并断言 `otool -L` 里没有多余的 svgx 动态库(证明"静态链接"这个承诺兑现)、`nm` 里 `frbgen` 符号还在(证明 `-force_load` 真的生效、没被死代码剥离)。

### 3.5 macOS —— ⏳ 同上

`macos/svgx.podspec` 已改完:删 `script_phase`、合并重复 xcconfig、`-force_load $(PODS_TARGET_SRCROOT)/../prebuilt/macos/libsvgx.a`,并**删掉了从 iOS podspec 抄来的、在 macOS 上毫无意义的 `EXCLUDED_ARCHS[sdk=iphonesimulator*]`**。macOS 两个 slice 都是 device slice,不存在 iOS 那种 arm64 撞车,一个 lipo 通用归档即可,所以没有 `[sdk=]` 分支。

### 3.6 `rust/Cargo.toml` —— **刻意不改**

保持 `crate-type = ["cdylib", "staticlib"]`。Cargo 不支持按 target 声明 crate-type;要按平台裁剪只能改用 `cargo rustc --crate-type=...`,那会让构建脚本显著复杂化。代价只是在动态库平台上多产出一个用不到的 `.a`(不分发、不进包),换来构建命令对所有平台完全一致。**这是有意识的取舍,不是遗漏。**

---

## 4. 怎么产出产物

### 本地

```bash
cd svgx
dart run tool/build_prebuilt.dart --list                       # 看 13 个 slice
dart run tool/build_prebuilt.dart --group windows              # 本机能建的
dart run tool/build_prebuilt.dart --group android              # 需要 NDK
dart run tool/build_prebuilt.dart --all                        # 本机能建的全建,其余明确 SKIP
dart run tool/check_prebuilt.dart                              # 校验
```

宿主不匹配的 target 会打印 `SKIP <triple>: requires a <host> host`,**不会伪造产物**。
构建宿主自身的动态库时,会顺带镜像一份到 `rust/target/release/`,因为 `lib/src/rust/frb_generated.dart` 的 `ioDirectory: 'rust/target/release/'` 是纯 `flutter test` 场景的加载路径。

### CI(**含"没有 Mac 也能拿到 Apple 产物"的路径**)

`.github/workflows/svgx-prebuilt.yml`,`workflow_dispatch` 手动触发(以及 `svgx-v*` tag):

1. Actions → "svgx prebuilt artifacts" → Run workflow
2. 下载 `svgx-prebuilt` artifact
3. 解压覆盖到本地 checkout 的 `svgx/prebuilt/`
4. `cd svgx && dart run tool/build_prebuilt.dart --restage`
5. `dart run tool/check_prebuilt.dart` → 必须打印 OK,然后提交

matrix 四条腿:`android`/`linux`(ubuntu)、`windows`(windows-latest,含 arm64)、`apple`(macos-latest,3 个归档)。`collect` job 合并全部产物、重算清单、并用**严格模式**(不带 `--allow-incomplete`)校验完整性——一条 matrix leg 悄悄少产一个 slice 会在这里被抓住。

固定 nightly 版本号从 `tool/prebuilt_common.dart` 的 `kToolchain` 里 `grep` 出来,不在 workflow 里重复写死。原先散在 `cargokit.yaml`/`build-release.ps1`/`svgx-ci.yml`/`README.md`/`CLAUDE.md` **五处**的版本号,现在 `cargokit.yaml` 已随 cargokit 删除。

---

## 5. 产物/源码同步保护(决定 #5)

删掉 cargokit 就一并删掉了它那套"crate 内容 SHA256 做产物身份"的保护。等价物已经补上:

`prebuilt/MANIFEST.json` 为每个产物记录 `sourceHash`(= `rust/Cargo.lock` + `rust/Cargo.toml` + `rust/src/**` 全部文件的排序哈希汇总)、产物自身 `sha256`、字节数、构建宿主与工具链。`tool/check_prebuilt.dart` 在 CI 每次 push 重算并比对。

> `Cargo.toml` 也纳入哈希(用户原话只提了 `Cargo.lock` + `rust/src/**`)。理由:`[profile.release]` 的 `opt-level`/`lto`/`strip`/`panic` 改一个字都会改变二进制,不纳入就会漏。这是严格加强,不是放宽。

**已做正/负双向验证**:
- 正向:7 个已提交产物 → `OK: 7 prebuilt artifact(s) match source hash 1f22b2c2…`
- 负向:往 `rust/src/api/svg.rs` 追加一行注释 → 立即 `FAIL`,同时报出总 hash 不匹配 + 逐个产物过期,退出码 1;还原后回到 OK。

**`--allow-incomplete`**:把"某 slice 还没构建"从错误降级为警告,同时**保留全部过期检查为致命**。这是迁移窗口期的临时开关(Apple 3 个 + windows-arm64 尚未产出),`svgx-ci.yml` 里带了 `TODO(migration)` 标注。**产物齐全后必须从 CI 里去掉。**

---

## 6. CI 结构变化

原 `svgx-ci.yml` 的 6 个 `build-*` job 验证的是"cargokit 能不能在各平台交叉编译"。现在编译这件事不存在了,CI 要证明的变成三件不同的事:

| 类别 | job | 验证什么 |
|---|---|---|
| 快检查(不变) | `rust-test` / `dart-analyze` / `flutter-test` | 源码本身健康 |
| **新增** | `prebuilt-sync` | 已提交二进制 ↔ 当前 Rust 源码是否同步(决定 #5) |
| **新增** | `cargo-check` matrix(android/linux/windows/apple) | 每个 triple 还编得过(决定 #4);仅类型检查,不带 build-std/LTO/链接 |
| **语义改变** | `build-windows` / `build-android` / `build-android-release` / `build-linux` / `build-ios` / `build-macos` | 下游消费路径能通,**且产物真的进了 bundle** |
| **新增(独立 workflow)** | `svgx-prebuilt.yml` | 产物怎么造出来 |

**"产物真的进了 bundle" 这半句是新增的、以前不存在的检查**。预编译方案的失败模式就是"编译过了但产物没进包",不显式断言就是裸奔。各平台断言:

- Windows:runner 目录下有 `svgx.dll`,且与 `prebuilt/` 的 **SHA-256 相同**
- Android:APK 里有 `lib/arm64-v8a/libsvgx.so`;release 还断言**每个 `.so` 的 LOAD 段对齐 = 0x4000**
- Linux:bundle 里有 `libsvgx.so`,并打印实际 glibc 需求
- iOS/macOS:`otool -L` 里**没有** svgx 动态库(静态链接承诺兑现)+ `nm` 里 `frbgen` 符号存在(`-force_load` 生效)

**这些 job 全都不再安装 Rust / nightly / rust-src / NDK。这个"没有"本身就是测试**:任何一个还需要 Rust 工具链,就说明迁移没达成目标。

`build-ios` / `build-macos` 目前带一个 `TODO(migration)` 守卫:`prebuilt/ios/*`、`prebuilt/macos/*` 不存在时打 warning 并跳过,而不是在一个**已知且已记录**的缺失上把 CI 刷红。产物提交后删掉守卫。

---

## 7. 需要用户确认的事项

### R1(重要)—— Linux:musl 决定实测不成立,glibc 底线定在哪?

决定 #2 是 musl,但 §3.3 的三层实测证明它对"被 dlopen 的插件 `.so`"这个形态不成立。当前实现是 glibc,下限 **GLIBC_2.34**(覆盖 Ubuntu 22.04 / Debian 12 / RHEL 9 及以上)。请确认:

- (a) 接受 GLIBC_2.34,维持现状;
- (b) 把 `svgx-prebuilt.yml` 的 linux leg 改到 `ubuntu-22.04` runner(glibc 2.35 构建环境),把下限再压低一档,覆盖到 Ubuntu 20.04 一代;
- (c) 用 manylinux 容器(glibc 2.28)构建,覆盖最广,CI 复杂度上一个台阶。

改动量都很小(只动 workflow 的 `runs-on`),但需要你按 svgx 的 Linux 桌面用户画像判断。

### R2 —— Android `minSdkVersion` 从 19 提到 21,可接受吗?

这是把**既有的事实**写成真实值(cargokit 时代也是链到 21,gradle 里的 19 是虚的),不是新的能力损失。但它对下游是可见的声明变化,如果有消费方的 app 声明了 minSdk 19/20,`pub get` 后会撞到 Gradle 的 minSdk 冲突报错。

### R3 —— Apple 产物什么时候产?

配置已就位,一次 `workflow_dispatch` 即可产出并拿到真实体积。产出并提交前:iOS/macOS 的 CI job 处于 warning-skip 状态,`check_prebuilt.dart` 需要 `--allow-incomplete`。**这两处都带 `TODO(migration)` 标注,产物到位后要一起清掉。**

### R4 —— `rust/build-release.ps1` 保留还是删? **已决策:删**(2026-08-26)

它的功能已被 `tool/build_prebuilt.dart` 完全覆盖(后者还多做了镜像到 `rust/target/release/` 这一步)。用户拍板删除,已移除文件,相关引用(`tool/prebuilt_common.dart` 的同步说明注释)已同步更新。

---

## 8. 已删除的东西

| 路径 | 说明 |
|---|---|
| `cargokit/`(整个目录) | 含 4 个文件的 SVGX-LOCAL 本地补丁(`options.dart` / `builder.dart` / `rustup.dart` / `gradle/plugin.gradle`)。其中 `gradle/plugin.gradle` 那个补丁本身就是被 Gradle 9 移除 `Project.exec(Closure)` 打脸后临时缝的,以后 Gradle 每升一个大版本都要重缝——**删掉它是本次迁移净收益最大的一块**。 |
| `rust/cargokit.yaml` | 其中的 nightly + build-std flag 组合(实测省 21% 体积)**已原样搬进 `tool/prebuilt_common.dart` 的 `kToolchain`/`kBaseRustFlags`/`kBuildStdFlags`**,没有随文件一起丢失。 |
| `analysis_options.yaml` 的 `- cargokit/**` 排除项 | 目标已不存在。 |

**删除前已 grep 全仓确认无残留引用**:仅剩注释里提及"此前 cargokit 如何如何"的历史说明,无任何构建路径依赖。

## 9. 新增的东西

| 路径 | 说明 |
|---|---|
| `prebuilt/`(含 `MANIFEST.json`) | 提交进 git 的原生产物 |
| `tool/prebuilt_common.dart` | target 表 + 源码 hash 定义,**唯一真相源** |
| `tool/build_prebuilt.dart` | 构建 / `--check` / `--restage` / `--list` |
| `tool/check_prebuilt.dart` | CI 同步校验 |
| `.pubignore` | 排除 `rust/`(下游不再编译,源码+`target/` 是纯负担)与 `benchmark/`;**`prebuilt/` 刻意不排除** |
| `.github/workflows/svgx-prebuilt.yml` | 产物构建 workflow |
| `pubspec.yaml` 的 `crypto` dev 依赖 | 仅 `tool/*.dart` 使用,不传递给下游 |
