# mova：把瘦身版 libmpv 作为 pub.dev 依赖包分发（方向 C）— 实现计划

**日期：** 2026-09-25
**状态：** 规划（未落地，未开工）
**基线：** mova 0.1.0（pubspec），测试 **815 项全绿**、`flutter analyze` 0 issues（仅剩既有 `feed_player.dart` 警告）
**取代：** [2026-09-25-libmpv-auto-download.md](2026-09-25-libmpv-auto-download.md)（方向 A2，构建期自动下载，**用户已否决**）。
本文复用它的现状调研，但核心机制完全不同：**不做构建期下载，改为把二进制打进 pub 包，
靠 pub 生态自身的包下载机制分发。**

---

## Goal

1. 下游使用者不必 clone mova 仓库源码、不必手写 `Copy` task，就能拿到瘦身版 libmpv 二进制——
   二进制随一个正常的 pub 依赖下发（形态对标 `media_kit_libs_android_video`，但**包内自带二进制**，
   不像官方那样构建时联网下载 jar）。
2. **保留切换能力**：用户随时能回到官方 media_kit 二进制，或换成自己编译的瘦身版，
   且切换动作要简单、可验证、不依赖我们的配合。

**明确不做的**：构建脚本层面的运行时下载（A2 被否决的核心机制）；不改变 mova 现有默认行为
（理由见决策 2）；不在本期承诺 iOS / macOS / Linux。

---

## 现状核实（2026-09-25 实读，含 pub cache 里官方包的真实实现）

| 事实 | 位置 / 证据 | 说明 |
|---|---|---|
| 二进制产物 10 个目录齐全 | `C:\workspace\dart-labs\mova\libmpv\` | Android 4 ABI `libmpv.so`：arm64-v8a **6,050,104**、armeabi-v7a **5,677,832**、x86 **6,190,732**、x86_64 **7,732,664** 字节（合计 **25.65 MB**）；`windows-x86_64/libmpv-2.dll` **14,075,392**；`ios-arm64/libmpv.dylib` **5,741,680**；`macos-arm64` 7,398,112 / `macos-amd64` 7,957,944 / `macos-universal` 15,377,120；`linux-x86_64/libmpv.so` 7,550,784 |
| 产物只托管在 git（Git LFS） | `.gitattributes` + CI "Commit built artifact to dist/" | 每平台 job 各自 commit 回 `mova/libmpv/<平台>/` |
| CI 已有全平台 artifact 上传 | `C:\workspace\dart-labs\.github\workflows\build-mova-libmpv.yml:178/351/516/726/926/1289` | artifact 名 `mova-libmpv-android-<abi>` / `-ios-arm64-movaslim` / `-macos-<arch>-movaslim` / `-linux-x86_64` / `-windows-x86_64`。**新 job 可直接 `download-artifact` 消费** |
| **官方 `media_kit_libs_android_video` 自己不含二进制** | `<pub cache>/media_kit_libs_android_video-1.3.8/android/build.gradle` | `task downloadDependencies(type: Exec)` 从 `libmpv-android-video-build` Release 下 4 个 `default-<abi>.jar`（校验 MD5），落到 `$buildDir/output`，再 `implementation fileTree(dir: "$buildDir/output", include: "*.jar")`。**`.so` 是通过 jar 里的 `lib/<abi>/libmpv.so` 进 APK 的**，`assemble.dependsOn(downloadDependencies)`——**无条件执行，没有开关** |
| Android 现有接线是"app 本地 Copy + pickFirsts" | `example/android/app/build.gradle.kts:48-71` | `packaging { jniLibs { pickFirsts += "**/libmpv.so" } }` 在 **app 模块**；`syncMovaLibmpv`（`Copy`）把 `../../../libmpv/<abi>/libmpv.so` 拷进 **app 的** `src/main/jniLibs/<abi>/` |
| Windows 现有接线是**同名整包替换** | `packages/media_kit_libs_windows_video_slim/pubspec.yaml` → `name: media_kit_libs_windows_video`、`publish_to: 'none'` | 靠 `dependency_overrides` 的 path 依赖把官方包名指到 fork 实现，**官方包根本不参与构建**，所以不存在任何合并冲突 |
| `media_kit_video` 对 Windows libmpv 的约定是**硬编码的** | `<pub cache>/media_kit_video-2.0.1/windows/CMakeLists.txt:17,62` | `set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")`、链接 `"${LIBMPV_SRC}/libmpv.dll.a"`、include `"${LIBMPV_SRC}/include"`；运行期 DLL 靠变量 `media_kit_libs_windows_video_bundled_libraries`（**按这个确切的名字被读**） |
| Linux 的 libmpv **来自系统**，不来自包 | `<pub cache>/media_kit_libs_linux-1.2.1/linux/CMakeLists.txt` | 这个包只干 mimalloc；`media_kit_video/linux/CMakeLists.txt` 走 pkg-config 找 mpv/epoxy |
| iOS/macOS 官方包用 `vendored_frameworks` | `media_kit_libs_ios_video-1.1.4/ios/*.podspec` | `system("make")`（pod install 期下载解包）+ `s.vendored_frameworks = 'Frameworks/*.xcframework'` |
| `media_kit_libs_video` 只是伞包 | `<pub cache>/media_kit_libs_video-1.0.7/pubspec.yaml` | 依赖 android/ios/macos/windows/linux 五个子包，**没有任何自己的代码** |
| mova 依赖的是这个伞包 | `mova/pubspec.yaml` | `media_kit_libs_video: ^1.0.7` |
| `.pubignore` 排除了 `libmpv/`、`packages/`、`doc/` | `mova/.pubignore` | 新包是**独立包目录**、独立发布，不受 mova 这份 `.pubignore` 影响 |
| README 当前说法 | `README.md`「进阶：接入自研瘦身版 libmpv」 | 明写二进制"**唯一的获取渠道**是 clone mova 仓库源码" |

---

## 架构决策

### 决策 0（全篇的地基）：Android 上只有两种拓扑，没有第三种

这是问题 2 的技术答案，先把它讲透，后面所有决策都由它推导。

Android 侧 `libmpv.so` 进 APK 的路径只有两条：官方包的 jar（`lib/<abi>/libmpv.so`）、
我们的产物（jniLibs 或 AAR）。AGP 的 `MergeNativeLibsTask` 对同一条 `lib/<abi>/libmpv.so`
路径出现两次的反应是**直接报冲突失败**（不是随便挑一个），除非有 `pickFirsts` 规则。于是：

| 拓扑 | 条件 | 后果 |
|---|---|---|
| **A. 共存 + pickFirst** | 官方包与我们的包同时在依赖图里 | **必须**有 `packaging { jniLibs { pickFirsts += "**/libmpv.so" } }`，且这行**只能写在最终 app 模块**（见下），谁赢还要靠 sha256 验证 |
| **B. 独占（sole provider）** | 依赖图里只有一个提供方 | 零冲突、零配置、无需 pickFirst；但要求官方 `media_kit_libs_android_video` **根本不出现在依赖图里** |

**`pickFirsts` 能不能由插件自己声明？不能。** AGP 里 library module 的
`android.packaging`/`packagingOptions` 只影响**该 library 自己 AAR 的打包**，
最终 APK 的 native 库合并用的是 **app 模块**的 `packaging.jniLibs`。
Flutter 插件的 `android/build.gradle` 是作为 subproject 被 include 的 library module，
**没有任何受支持的方式让它替 app 模块声明合并策略**。
（技术上可以在插件里写 `rootProject.subprojects { ... }` + `afterEvaluate` 反向改 `:app` 的配置——
这能跑，但是对宿主工程的隐式侵入，一旦与宿主自己的 `packaging` 配置或其它插件打架，
排查成本极高，**明确否决**，与 A2 计划的结论一致。）

**所以："装上包什么都不做就是瘦身版" 在拓扑 A 下做不到，在拓扑 B 下可以做到。**
这是本计划必须如实交代的第一件事。

**还有一个更隐蔽的坑（拓扑 A 独有，必须写进验收）**：`pickFirst` 的"first"是
**合并输入顺序里的第一个**，而输入顺序由 project-local sources 与依赖 classpath 顺序决定。
app 模块自己的 `src/main/jniLibs/` 排在所有依赖之前——这是 example 今天能稳定赢的原因。
但如果我们的 `.so` 是**从 AAR 依赖**贡献的，那就变成"两个 library 依赖争第一"，
**谁赢没有任何契约保证**（不是我们能控制的顺序）。
结论：拓扑 A 下，我们的包不应该把 `.so` 做成 AAR 里的 jniLibs 去赌合并顺序，
而应该提供一个 Gradle 脚本，把 `.so` 拷进 **app 自己的 jniLibs**——
这样 pickFirst 的胜者是确定的（app-local 永远排第一），也正是 example 今天已验证的形状。

### 决策 1：包结构 —— **按平台拆包，且第一期只发一个（`mova_libmpv_android`）**

**结论：**

- 按平台拆：`mova_libmpv_android` / （将来）`mova_libmpv_ios` / …，**不做"一个包含全平台"的大包**。
- **第一期只发 `mova_libmpv_android` 一个**（理由见决策 6 与分期建议）。

**理由（这里的决定性因素不是 pub.dev 的体积上限，是"pub 没有条件依赖"）：**

1. **pub.dev 的硬上限不是瓶颈。** 单版本上限 100 MB；全平台二进制加起来约 63 MB 原始、
   压缩后大致 30 MB 量级，单 Android 四 ABI 原始 25.65 MB、压缩后约 11–13 MB。
   **都在限内，"会不会被拒"不是真问题。**
2. **真问题是 `pub get` 不区分平台。** Dart/Flutter 的依赖解析**没有条件依赖**：
   凡是出现在依赖图里的包，**所有用户、所有平台都会下载并永久缓存**。
   一个只做 iOS 的用户会为 Android 的 `.so` 付流量，一个大包会让所有人为所有平台付流量。
   官方 `media_kit_libs_*` 之所以感觉不到这个成本，正是因为**它们包里没有二进制**（构建时才下）。
   我们选了"随包发二进制"，就必须用**拆包 + 按需引入**来把这个成本压到最小。
3. **各平台的替换机制根本不同**（决策 6/7），塞进一个包里会逼出一个"什么平台都要照顾"的
   万能构建脚本，违反"不过度设计"。拆开后每个包只对自己那套原生工程负责。
4. **失败隔离与节奏自由**：Android 的包可以先发 1.0.0 迭代几轮，不用等 iOS 接线完成。

**被否决的备选：**

| 备选 | 否决理由 |
|---|---|
| 单个全平台大包 `mova_libmpv` | 上述第 2、3 条；且任何一个平台的产物重建都要发全量新版本 |
| 发一个"伞包" `mova_libmpv_video`（仿 `media_kit_libs_video`） | 伞包会把所有平台子包拖进依赖图，等价于大包，**把拆包的唯一好处抵消掉**。第一期只有一个子包时它更是纯冗余。将来若真有 ≥3 个平台包再评估 |
| 把二进制作为 pub 包的 `assets` 由 Dart 运行时释放 | 原生库必须在 APK 打包期就位（`System.loadLibrary`），运行时释放到私有目录再 dlopen 在 Android 上是可行但极其边缘的做法，且 media_kit 不支持自定义加载路径。**否决** |

### 决策 2（最关键）：默认值方向 —— **默认仍走官方，瘦身版 opt-in；不把默认反过来**

用户提的"mova 默认依赖自己的瘦身版包，想用官方才 override"这条路线，**技术上成立**
（就是决策 0 的拓扑 B：mova 的 `pubspec.yaml` 把 `media_kit_libs_video` 伞包拆开写成
`media_kit_libs_ios_video` + `_macos_video` + `_windows_video` + `_linux`，Android 位置换成
`mova_libmpv_android`；官方 Android 包不进依赖图 → 无冲突 → 真·零配置生效）。
**但我建议不这么做**，理由如下，按权重排序：

1. **瘦身版的能力面是被主动裁过的，不适合当所有人的默认。** CLAUDE.md 与 mova-libmpv
   的记录里，瘦身构建明确砍掉了 VP8/VP9 软解、收窄了音频 decoder/demuxer 白名单、
   砍掉了部分协议（ftp/async/cache/subfile/httpproxy），并且**"去掉 avfilter 这一步至今
   未过真机播放验证，上线前必须实测 OSD/字幕合成/音频均衡是否受影响"**。
   把这样一个产物变成"装了 mova 就自动生效"，等于让下游在毫不知情的情况下失去解码能力，
   出问题时的表现是"某些片子播不了"——**最难排查的一类故障**。
   一个已发布到 pub.dev 的插件不该这么做。
2. **反向默认会把二进制强加给每一个用户。** 见决策 1 理由 2：mova 一旦依赖
   `mova_libmpv_android`，所有平台的所有用户都要在 `pub get` 时下 11–13 MB，
   包括只做 iOS/Web/桌面的人。当前默认（官方包，包内无二进制）没有这个成本。
3. **反向默认是对既有用户的行为变更。** mova 已发布在 pub.dev，一次 minor 升级
   悄悄换掉底层解码库，违反最小意外原则；真要做也得是大版本 + CHANGELOG 顶格警告。
4. **收益不对称。** 正向默认下，想省体积的人多写 2 行；反向默认下，被裁掉的能力
   要由不知情的人去发现。前者成本可控，后者不可控。

**结论：mova 的 `pubspec.yaml` 保持 `media_kit_libs_video: ^1.0.7` 不动。**
瘦身版是下游主动加的一个依赖。

> **重要的可复议点（如实记录）**：如果将来 ① avfilter/字幕/OSD 真机验证通过、
> ② codec 白名单覆盖面经过一轮下游实测、③ 我们愿意为"默认瘦身"背书，
> 那么切到拓扑 B（反向默认）在技术上是**干净可行**的，而且比拓扑 A 更干净
> （零冲突、无 pickFirst、无合并顺序赌博）。**那应该是一次单独的、有数据支撑的大版本决定，
> 不是本计划顺手改掉的。** 本计划的 Task 设计会保证那天到来时改动很小（只改 mova 的 pubspec
> 依赖列表 + 包内一个开关的默认值）。

### 决策 3：Android 的 opt-in 形态 —— **两行，且 `.so` 走 app-local jniLibs（不赌 AAR 合并顺序）**

**用户最小操作（这就是问题 2 要的"讲清楚的最小操作"）：**

```yaml
# ① 应用自己的 pubspec.yaml
dependencies:
  mova_libmpv_android: ^1.0.0        # 只有这一行是"引入"
```

```kotlin
// ② 应用自己的 android/app/build.gradle.kts
android {
    packaging { jniLibs { pickFirsts += "**/libmpv.so" } }   // 让我们的赢过官方 jar 里的那份
}
// 把包内二进制同步进 app 自己的 jniLibs（app-local 在合并里排第一，胜负确定）
apply(from = project(":mova_libmpv_android").projectDir.resolve("mova_libmpv.gradle"))
```

要点：

- **`project(":mova_libmpv_android").projectDir` 是稳定可写的定位方式**：Flutter 工具链会把
  每个带 `android/` 的插件包作为 Gradle subproject include 进来，项目名就是 pub 包名。
  这比去猜 pub cache 路径或 `.flutter-plugins-dependencies` 稳得多。
  （Task 3 的一个明确子目标就是**实测确认**这条引用在 `flutter build apk` 下成立；
  如果不成立，退路是让用户把一小段 Copy task 直接贴进自己的 build 文件——仍然比今天
  "clone 整个 monorepo 拿二进制"好，因为二进制来自 pub cache。）
- **为什么不干脆把 `.so` 放进我们 AAR 的 `src/main/jniLibs/` 让它自动参与合并？**
  见决策 0 最后一段：两个 library 依赖争 pickFirst 的"first"没有契约保证。
  我们**会**同时把 `.so` 放在包内（它必须在包里），但**打包路径不放在 `android/src/main/jniLibs/`**，
  而是放在 `android/libs-slim/<abi>/libmpv.so` 这种不被 AGP 自动收集的位置，
  由脚本显式拷进 app——把胜负从"赌顺序"变成"确定"。
- **两行不能压成一行。** 只要官方包还在依赖图里（决策 2 的默认下它一定在），
  `pickFirsts` 那行就省不掉，且只能由 app 模块声明。**这一点不要在 README 里含糊。**
  漏掉它的表现是构建失败（AGP 报重复 `.so`），不是静默用错——这点尚可接受。

### 决策 4：三种"切换"各自怎么做（这是本方向存在的理由）

| 想要什么 | 怎么做 | 机制 |
|---|---|---|
| **官方 media_kit（默认）** | 什么都不做 | mova 依赖伞包，官方 jar 唯一提供 `.so` |
| **从瘦身版切回官方** | 删掉 pubspec 那一行依赖 + 删掉 app 的 `apply(from=...)` 那行（`pickFirsts` 留着也无害） | 依赖图里只剩官方，回到独占拓扑 |
| **临时切回而不改依赖** | `android/gradle.properties` 加 `mova.libmpv.slim=false` | 我们的 gradle 脚本读到后**整段跳过**（不拷任何文件），只剩官方那份 → 无冲突 |
| **换成自己编译的瘦身版** | `mova.libmpv.dir=/abs/path/to/<abi>/libmpv.so 的父目录` | 脚本从该目录取 `.so`，完全不碰包内自带的那份；同时**跳过 sha256 校验**（自编产物当然对不上清单） |
| **只替换个别 ABI** | `mova.libmpv.abis=arm64-v8a,x86_64` | 未列出的 ABI 保持官方版本 |

三个开关都是 Gradle property（也接受同名环境变量），**不需要改我们的包、不需要 fork、
不需要联网**。这套"可切换"的设计是方向 C 相对方向 B 唯一真正的增量，
Task 4 要把它当作一等功能实现和验收，而不是顺带。

### 决策 5：版本管理 —— **包版本独立 semver + 包内锁死一份 `MANIFEST.json`**

- **`mova_libmpv_android` 用自己的 semver，与 mova 主包版本号解耦。**
  理由：二进制重建的节奏（mpv 升级、flavor 调整）与 mova 的功能迭代节奏完全无关，
  硬绑会逼出大量空版本。
- **每个版本包内附 `MANIFEST.json`（随包发布，可被下游/CI 读）**：

```json
{
  "schema": 1,
  "package_version": "1.0.0",
  "flavor": "movaslim",
  "mpv_commit": "78d43740f52db817d98bcf24fb30a76ab6fa13ff",
  "built_at": "2026-09-25T00:00:00Z",
  "ci_run_id": "35948800700",
  "validated_against": { "media_kit": "^1.2.6", "media_kit_video": "^2.0.1" },
  "abis": {
    "arm64-v8a":   { "file": "arm64-v8a/libmpv.so",   "size": 6050104, "sha256": "…" },
    "armeabi-v7a": { "file": "armeabi-v7a/libmpv.so", "size": 5677832, "sha256": "…" },
    "x86":         { "file": "x86/libmpv.so",         "size": 6190732, "sha256": "…" },
    "x86_64":      { "file": "x86_64/libmpv.so",      "size": 7732664, "sha256": "…" }
  }
}
```

- **升级错配的防线有三道**：
  1. `MANIFEST.json` 的 `validated_against` 写明本批二进制验证过的 `media_kit`/`media_kit_video` 范围；
     mova 的 README 给出"mova x.y ↔ mova_libmpv_android ^a.b"对照表（**一张表，不是散落各处的说法**）。
  2. 包的 Gradle 脚本在配置期打印一行 `[mova-libmpv] using <version> (mpv <commit short>)`，
     让构建日志里永远能看出实际生效的是哪批字节。
  3. Task 4 的 sha256 校验：拷进 app jniLibs 前核对 `MANIFEST.json`，
     防止包内容被本地改动/半截解压污染（`mova.libmpv.dir` 自编路径除外）。
- **版本号语义约定**（写进包的 README，避免以后自己都记不清）：
  - **major**：ABI/能力面不兼容变化（换 mpv 大版本、砍掉某个 codec/协议）；
  - **minor**：重建二进制、体积/构建选项变化但能力面不变；
  - **patch**：只改 Gradle 脚本/文档，二进制字节未变。

### 决策 6：平台落地范围 —— **只做 Android；Windows 改进走"git override 同名 fork"，其余不做**

这是问题 2 的后半段（各平台机制是否一致）的结论。**答案是：完全不一致，不能照抄 Android。**

| 平台 | 官方提供方式 | 我们另起包名后会怎样 | 本期结论 |
|---|---|---|---|
| **Android** | 下载 jar → `implementation fileTree` → jar 内 `lib/<abi>/libmpv.so` 参与 native merge | 同名 `.so` 重复 → 合并冲突，靠 app 的 `pickFirsts` 解决（决策 0/3） | **做**（唯一必做） |
| **Windows** | `media_kit_libs_windows_video` 在**配置期** `file(COPY)` 出 `${CMAKE_BINARY_DIR}/libmpv/{libmpv.dll.a,include/}`，并导出变量 `media_kit_libs_windows_video_bundled_libraries`；`media_kit_video` **按这两个确切名字/路径**取用 | 另起包名后：① 我们无法向那个**按名字读取**的变量供货（DLL 不会被 bundle）；② 两个包都在配置期写同一个 `${CMAKE_BINARY_DIR}/libmpv`，谁后写谁赢，而插件 CMake 的 `add_subdirectory` 顺序不由我们控制。**CMake 没有 pickFirst 这种东西。** → 另起包名在 Windows 上是结构性敌对的 | **不做 pub 包**。改为把现有 fork 的分发从"clone 仓库"升级成 **git `dependency_overrides`**（Task 7），这才是 Windows 的正解 |
| **iOS / macOS** | podspec `system("make")` 下载 + `s.vendored_frameworks = 'Frameworks/*.xcframework'` | CocoaPods **没有 pickFirst**；两个 pod 各自 vendor 一份 mpv framework → 重复符号 / `Multiple commands produce` 的 embed 冲突。且我们的 darwin 产物是**单个静态链接的 `libmpv.dylib`**，官方是**多 dylib 的 xcframework 集**，形态不同，还要处理 embed + 签名。mova **从未在 iOS 上接过线** | **不做**（分期建议第 3 期） |
| **Linux** | libmpv **来自系统**（`media_kit_video/linux` 走 pkg-config 找 mpv/epoxy）；`media_kit_libs_linux` 只管 mimalloc | 根本没有"包提供 libmpv"这个位置可占；要生效得动 RPATH/系统安装 | **不做**（模型不适用，README 如实说明） |

### 决策 7：LGPL 合规 —— **必做的一个 Task，不是文档润色**

把 LGPL 二进制打进一个公开分发的 pub 包，和"只在自己仓库里放着"是两回事：
**发布到 pub.dev 就是向不特定公众分发目标代码**，LGPL 的附随义务从这一刻起才真正触发。
我不给法律结论，但按 LGPL-2.1 的一般要求，这个包发布时**至少**应当附带：

1. **完整的许可证文本**：`LICENSE`（我们自己那点 Gradle/Dart 胶水，MIT）
   + `LICENSE.LGPL-2.1`（mpv/FFmpeg 及其 LGPL 依赖）
   + LGPL-2.1 正文里引用到的 **GPL-2.0 文本**（LGPL-2.1 第 3 节允许转换为 GPL，
     其正文对 GPL 有引用，惯例是一并附上）。
   pub.dev 只按根 `LICENSE` 判定协议，**必须在 `LICENSE` 顶部显著写明"本包同时分发 LGPL 二进制，
   见 LICENSE.LGPL-2.1 与 NOTICE"**，不能让人误以为整包是 MIT。
2. **`NOTICE` / `THIRD_PARTY.md`**：逐条列出二进制里静态链接进去的每个组件、版本/commit、协议
   （mpv、FFmpeg、dav1d、libass、freetype、fribidi、harfbuzz、libpng、zlib……以 flavor 脚本实际启用项为准），
   **这份清单要从构建配方生成，不许手写**（手写必然漂移）。
3. **"如何取得对应完整源码"的书面声明**：给出 mova-libmpv 的仓库地址 + 本批产物对应的
   **确切 commit / tag** + flavor 补丁文件名 + 构建脚本入口，
   并保证该地址在合理期限内可访问（LGPL 的 written offer 精神）。
4. **重新链接（relink）能力的说明**：这是 LGPL 对静态链接最敏感的一条。
   我们的形态是：FFmpeg 等**静态链接进 `libmpv.so`**，而 `libmpv.so` 本身是
   **动态库、由 app 在运行期 `dlopen`/`System.loadLibrary` 加载**。
   也就是说，**最终 app 与 LGPL 代码之间是动态链接**，使用者可以用自己编译的
   `libmpv.so` 直接替换（这正是决策 4 的 `mova.libmpv.dir` 开关提供的能力）。
   → **文档里必须明确写出这一条替换路径**，它既是产品功能也是合规论据。
   同时要说明 `libmpv.so` 内部静态链接的那些 LGPL 组件，其"可重新链接"由
   mova-libmpv 的完整构建配方 + 源码可得来满足。
5. **GPL-only 组件的排除证据**：把本批构建实际使用的关键开关（mpv `-Dgpl=false`、
   FFmpeg `--disable-gpl --disable-nonfree` 及禁用的 GPL 组件清单）**原样记进包内文档**，
   不要只说"我们避开了 GPL"。CLAUDE.md 里"构建卡 LGPL，避开 GPL-only 组件"这句
   目前没有随产物一起可核查的证据，**发布前必须补上**。

> ⚠️ **这一步不能跳过、不能"发了再补"。** 一旦包上了 pub.dev，历史版本**无法删除**
> （pub.dev 只能 retract，文件仍可下载），合规缺失会永久留在分发历史里。
> 因此 Task 6（合规资料）在 Task 顺序里**排在首次 `pub publish` 之前**，且是发布的硬门槛。

---

## Tech Stack / 依赖

- Gradle（Groovy 脚本，JDK 自带 `MessageDigest`，无外部依赖）
- GitHub Actions + `actions/download-artifact`（已有）+ pub.dev **automated publishing（OIDC）**
- Dart：新包本身**没有 Dart 运行时代码**（对标官方 libs 包，只有一个空插件类占位），
  `MANIFEST.json` 的 schema 单测放在 mova 主包的 `test/` 里

**新增第三方依赖：无。**（生成 sha256 用 CI 的 `sha256sum` / Gradle 的 `MessageDigest`，
**不要为此引入 `package:crypto`**——那属于需要先问用户的新依赖。）

---

## 文件结构

**新建包（独立 pub 包，不在 mova 包内）**

| 文件 | 用途 | Task |
|---|---|---|
| `mova/packages/mova_libmpv_android/pubspec.yaml` | 包元数据（`name: mova_libmpv_android`，Flutter plugin，只声明 android 平台） | 1 |
| `mova/packages/mova_libmpv_android/android/build.gradle` | AAR 骨架（**不含 jniLibs**，只为让它成为 Gradle subproject 供定位） | 1 |
| `mova/packages/mova_libmpv_android/android/src/main/AndroidManifest.xml` | 空 manifest | 1 |
| `mova/packages/mova_libmpv_android/android/libs-slim/<abi>/libmpv.so` | **二进制本体**（CI 注入，git 里走 LFS） | 2 |
| `mova/packages/mova_libmpv_android/mova_libmpv.gradle` | 下游 `apply(from=...)` 的脚本：读开关 → 校验 sha256 → 拷进 app jniLibs | 3/4 |
| `mova/packages/mova_libmpv_android/MANIFEST.json` | 版本/commit/每 ABI sha256（决策 5） | 2 |
| `mova/packages/mova_libmpv_android/README.md` | 安装两行、三个开关、切换回官方、LGPL 声明 | 5/6 |
| `mova/packages/mova_libmpv_android/CHANGELOG.md` | 每个版本对应的 mpv commit / CI run | 5 |
| `mova/packages/mova_libmpv_android/LICENSE` / `LICENSE.LGPL-2.1` / `LICENSE.GPL-2.0` / `NOTICE` | 合规四件套（决策 7） | 6 |
| `mova/packages/mova_libmpv_android/lib/mova_libmpv_android.dart` | 空占位（pub.dev 要求包有 `lib/`；对标官方 libs 包） | 1 |

**修改**

| 文件 | 改动 | Task |
|---|---|---|
| `C:\workspace\dart-labs\.github\workflows\build-mova-libmpv.yml` | 新增 `package-pub-android` job（组装包目录 + 生成 MANIFEST + 上传 artifact） | 2 |
| `C:\workspace\dart-labs\.github\workflows\publish-mova-libmpv-android.yml`（新文件） | tag 触发的 pub.dev OIDC 发布 | 8 |
| `C:\workspace\dart-labs\mova\README.md` | 「进阶：接入自研瘦身版 libmpv」整节重写（Android 改成两行；Windows 改成 git override；iOS/macOS/Linux 如实说明） | 7 |
| `C:\workspace\dart-labs\mova\CHANGELOG.md` | 记录"提供了 `mova_libmpv_android` 可选依赖"，并强调**默认行为未变** | 7 |
| `C:\workspace\dart-labs\mova\doc\SPEC.md` | 新增「瘦身版 libmpv 分发」一节 | 7 |
| `C:\workspace\dart-labs\mova\packages\media_kit_libs_windows_video_slim\windows\CMakeLists.txt` | **Windows git-override 化**：DLL 路径从 `${CMAKE_SOURCE_DIR}/../../libmpv/...` 改为包内自带（Task 7 的前置，否则 git 依赖取不到 LFS 产物） | 7 |
| `C:\workspace\dart-labs\mova\.gitattributes` / LFS 配置 | 新包内二进制纳入 LFS | 2 |
| `C:\workspace\dart-labs\mova\example\android\app\build.gradle.kts` | **只在 Task 9 的验证里临时切换，验证完还原**（example 用本地 `Copy` 是对的，不该依赖 pub 包） | 9 |

**测试数量推进**（基线 **815**）：Task 1 → 815、**Task 2 → 819**（MANIFEST schema 单测 +4）、
Task 3–9 → 819。

> 说明：本计划绝大部分是构建脚本与发布流程，**Dart 侧只有 `MANIFEST.json` 这一处值得单测**。
> 不要为 Gradle 脚本编造 Dart 单测——它们的验收靠 APK 内 `.so` 的 sha256 比对（Task 9）。

---

## Task 1：新包骨架（不含二进制）

**Files:** `mova/packages/mova_libmpv_android/` 下的 `pubspec.yaml` / `android/build.gradle` /
`android/src/main/AndroidManifest.xml` / `lib/mova_libmpv_android.dart`

**做什么：**

1. `pubspec.yaml`：

```yaml
name: mova_libmpv_android
description: >-
  Prebuilt slimmed libmpv (LGPL) for Android, as used by package:mova.
  Optional drop-in replacement for the binary shipped by
  media_kit_libs_android_video. Opt-in: adding this package alone does
  nothing until the app applies mova_libmpv.gradle (see README).
version: 1.0.0
homepage: https://github.com/icodejoo/dart-labs/tree/main/mova/packages/mova_libmpv_android
repository: https://github.com/icodejoo/dart-labs
topics: [media-kit, libmpv, android, native]

environment:
  sdk: ^3.12.2
  flutter: '>=3.3.0'

dependencies:
  flutter: {sdk: flutter}

flutter:
  plugin:
    platforms:
      android:
        package: com.icodejoo.mova.libmpv
        pluginClass: MovaLibmpvAndroidPlugin   # 空实现，仅为成为 Gradle subproject
```

2. `android/build.gradle`：最小 `com.android.library`，`namespace`、`compileSdk`、`minSdk 24`。
   **关键：不要有 `sourceSets { main { jniLibs.srcDirs ... } }`，`libs-slim/` 必须不被 AGP 自动收集**
   （决策 3：不赌合并顺序）。加一条注释解释为什么故意不收集。
3. 空 Dart 文件 + 空 Kotlin plugin 类（对标 `media_kit_libs_android_video` 的形状）。

**验证：** 在 example 里用 path 依赖加上它，`flutter build apk --debug` 成功，
且 `unzip -l app-debug.apk | grep libmpv` **只有一份**（官方那份）——
证明空骨架不会意外引入第二个 `.so`。

---

## Task 2：CI 组装包目录 + 生成 MANIFEST + LFS 落地

**Files:** 修改 `C:\workspace\dart-labs\.github\workflows\build-mova-libmpv.yml`；
新增 `mova/packages/mova_libmpv_android/MANIFEST.json`；`.gitattributes`；
新增 `mova/test/tool/mova_libmpv_manifest_test.dart`

**做什么：** 新增 job（**不改任何现有 job**）：

```yaml
  # Assembles the four Android ABIs into the publishable
  # packages/mova_libmpv_android/ layout and regenerates MANIFEST.json.
  # Publishing itself is a separate, human-triggered workflow (Task 8):
  # a pub.dev version is permanent, so minting one must never be a
  # side effect of an ordinary CI run.
  package-pub-android:
    name: "Assemble mova_libmpv_android package"
    runs-on: ubuntu-22.04
    needs: [android-arm64, android-other-abi]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with: { path: raw, pattern: mova-libmpv-android-* }
      - name: Lay out packages/mova_libmpv_android/android/libs-slim/<abi>/libmpv.so
        run: |
          set -euo pipefail
          pkg=mova/packages/mova_libmpv_android
          for abi in arm64-v8a armeabi-v7a x86 x86_64; do
            src=$(find "raw/mova-libmpv-android-$abi" -type f -name '*.so' | head -1)
            test -n "$src" || { echo "::error::missing artifact for $abi"; exit 1; }
            mkdir -p "$pkg/android/libs-slim/$abi" && cp "$src" "$pkg/android/libs-slim/$abi/libmpv.so"
          done
      - name: Regenerate MANIFEST.json
        run: bash mova/tool/gen_mova_libmpv_manifest.sh    # sha256sum + jq，无新依赖
      - uses: actions/upload-artifact@v4
        with: { name: mova-libmpv-android-pub-package, path: mova/packages/mova_libmpv_android }
```

另加：`.gitattributes` 把 `mova/packages/mova_libmpv_android/android/libs-slim/**` 纳入 LFS；
**并在 job 里复用现有 "Commit built artifact to dist/" 那一套**（`fetch + reset --hard` 干净基线、
commit 前显式 `git lfs push origin main`、windows job 之外无需 `shell: bash` 特例）——
这三个坑 CLAUDE.md 已记录过，**照抄现有写法，不要重新发明**。

**单测（+4，815 → 819）** `mova/test/tool/mova_libmpv_manifest_test.dart`：
- `MANIFEST.json` 存在且可 `jsonDecode`，`schema == 1`；
- `abis` 恰好含 4 个键，且与 `example/android/app/build.gradle.kts` 里 `syncMovaLibmpv` 的 ABI 列表一致（防漂移）；
- 每个 `sha256` 是 64 位小写 hex，`size > 0`；
- `validated_against.media_kit` 与 mova `pubspec.yaml` 里的 `media_kit` 约束**不矛盾**（简单前缀比对即可，防止二进制验证基线落后于依赖升级）。

**验证：** 手动 dispatch 跑一次 → artifact 里是一个完整可 `flutter pub publish --dry-run` 的包目录；
`sha256sum` 与 MANIFEST 逐条一致。

---

## Task 3：`mova_libmpv.gradle` —— 定位方式与注入路径（先把决策 3 的假设实测掉）

**Files:** 新建 `mova/packages/mova_libmpv_android/mova_libmpv.gradle`

**本 Task 的首要目标是证伪/证实一个假设**：下游 app 能否稳定地用
`project(":mova_libmpv_android").projectDir` 拿到包目录。**先做这个实测，再写逻辑**——
如果拿不到，后面全白写。备选定位方式（按优先级实测）：

1. `project(":mova_libmpv_android").projectDir`（首选）；
2. `rootProject.file(".flutter-plugins-dependencies")` 解析 JSON 取 path；
3. 让用户自己写死 pub cache 路径（**最差，README 不推荐**）。

脚本骨架（本 Task 只做结构与定位，校验/开关在 Task 4）：

```groovy
// mova_libmpv_android: copies this package's prebuilt slimmed libmpv.so into
// the *app's* own jniLibs, so the app-local copy deterministically wins the
// native-library merge against media_kit_libs_android_video's bundled jar.
//
// mova_libmpv_android：把本包自带的瘦身版 libmpv.so 拷进 *app 自己的* jniLibs。
// app 本地的那份在 native 合并里排第一，胜负确定，不依赖依赖顺序。
//
// Requires in the app module / app 模块还需要:
//   android { packaging { jniLibs { pickFirsts += "**/libmpv.so" } } }

def pkgDir = project(':mova_libmpv_android').projectDir
def manifest = new groovy.json.JsonSlurper().parse(new File(pkgDir, '../MANIFEST.json'))
def abis = (findProperty('mova.libmpv.abis') ?: 'arm64-v8a,armeabi-v7a,x86,x86_64').toString().split(',')

def syncMovaLibmpv = tasks.register('syncMovaLibmpv', Copy) {
    abis.each { abi ->
        from(new File(pkgDir, "libs-slim/${abi}/libmpv.so")) { into abi }
    }
    destinationDir = file("${buildDir}/mova-libmpv/jniLibs")
}
android { sourceSets { main { jniLibs.srcDirs += "${buildDir}/mova-libmpv/jniLibs" } } }
tasks.named('preBuild') { dependsOn syncMovaLibmpv }
```

> ⚠️ 注意：`jniLibs.srcDirs +=` 加的是 **app 模块自己的** source set（脚本是被 app 的
> build.gradle.kts `apply(from=)` 进来的，`project` 就是 `:app`），
> 这与 example 今天写进 `src/main/jniLibs` 是同一类"app-local"，
> **合并顺序上同样排在依赖之前**——Task 9 必须用 sha256 实测确认这一点，不许推断。

**验证：**
- app 里 `apply(from=...)` 后 `./gradlew :app:dependencies` 能看到 `:mova_libmpv_android` 是个 subproject；
- `./gradlew :app:assembleDebug` 成功，`syncMovaLibmpv` 出现在 task 列表里；
- 若**不加** `pickFirsts`：构建**应当失败**并报重复 `lib/<abi>/libmpv.so`——
  **这条要专门验一次**，它决定 README 怎么写（失败是好事：说明漏配会被发现，不会静默走错）。

---

## Task 4：三个开关 + sha256 校验（决策 4 的一等功能）

**Files:** 修改 `mova/packages/mova_libmpv_android/mova_libmpv.gradle`

实现（property 优先，环境变量兜底）：

| 开关 | property | 环境变量 | 行为 |
|---|---|---|---|
| 总开关 | `mova.libmpv.slim`（默认 `true`） | `MOVA_LIBMPV_SLIM` | `false` → 脚本**整段 return**，一个文件都不拷，日志打印一行 disabled，回到纯官方 |
| 自建目录 | `mova.libmpv.dir` | `MOVA_LIBMPV_DIR` | 从该目录取 `<abi>/libmpv.so`，**跳过 sha256**（自编产物本就对不上清单），打印 warning 说明"来源是用户自建，mova 不对其行为负责" |
| ABI 子集 | `mova.libmpv.abis` | `MOVA_LIBMPV_ABIS` | 逗号分隔；未列出的 ABI 不拷 → 那个 ABI 保持官方版本 |

校验逻辑（仅对包内自带二进制）：

```groovy
def sha256 = { File f ->
    def md = java.security.MessageDigest.getInstance('SHA-256')
    f.withInputStream { s -> byte[] b = new byte[1 << 16]; int n; while ((n = s.read(b)) > 0) md.update(b, 0, n) }
    md.digest().collect { String.format('%02x', it) }.join()
}
// 校验失败 = 包内容被污染（LFS 未拉全、半截解压），直接失败，绝不降级：
// 静默用错二进制正是这条线上最难排查的故障（CLAUDE.md 记录过 libmpv/ 与 jniLibs/ 长期静默不同步）。
```

日志必须包含一行可被构建日志检索的身份标识：
`[mova-libmpv] slim libmpv 1.0.0 (mpv 78d4374) -> arm64-v8a, x86_64`。

**验证：**
1. 默认构建 → 拷 4 个 ABI，日志有身份行；
2. `-Pmova.libmpv.slim=false` → 无 `syncMovaLibmpv` 输出、日志有 disabled 行，
   APK 内 `.so` sha256 **等于官方** jar 里那份；
3. `-Pmova.libmpv.dir=<repo>/libmpv` → 走自建路径、有 warning、APK 内 sha256 等于该目录文件；
4. 手工改坏包内一个 `.so` 的一个字节 → 构建**失败**并报 sha256 mismatch；
5. `-Pmova.libmpv.abis=arm64-v8a` 且 app 开了多 ABI → 只有 arm64-v8a 是我们的，
   其余 sha256 等于官方（**逐 ABI 比对，不看体积**）。

---

## Task 5：包内 README / CHANGELOG

**Files:** `mova/packages/mova_libmpv_android/README.md`、`CHANGELOG.md`

README 必须写清、且**不许美化**的六件事：

1. **安装是两行**（pubspec 一行 + app build.gradle.kts 两处：`pickFirsts` 与 `apply(from=)`），
   并解释**为什么 `pickFirsts` 不能由本包代劳**（AGP 里 library 的 packaging 只管自己的 AAR）；
2. **这个包不会自动生效**——只加依赖不 apply 脚本，行为与不装完全一样（这是刻意设计，不是 bug）；
3. **瘦身版的能力面是被裁过的**：列出已知砍掉的项（VP8/VP9 软解、音频 codec/demuxer 白名单收窄、
   ftp/async/cache/subfile/httpproxy 协议、avfilter），并明写
   **"avfilter 移除对 OSD/字幕合成/音频均衡的影响尚未经过真机验证"**——
   不能等用户踩到才知道；
4. **三个开关**与"切回官方"的完整操作；
5. **版本对照表**（mova ↔ 本包 ↔ mpv commit）；
6. **LGPL 声明**（指向 Task 6 的四件套，含"你可以用自己编译的 libmpv.so 替换"这条 relink 路径）。

---

## Task 6：LGPL 合规四件套（**首次发布的硬门槛**）

**Files:** `mova/packages/mova_libmpv_android/` 下的
`LICENSE`、`LICENSE.LGPL-2.1`、`LICENSE.GPL-2.0`、`NOTICE`，
以及 `mova/tool/gen_mova_libmpv_notice.sh`

按决策 7 的五条逐项落实：

1. 根 `LICENSE`：顶部一段醒目说明"本包的脚本/Dart 代码为 MIT；包内 `android/libs-slim/**/*.so`
   为 LGPL-2.1 二进制，见 `LICENSE.LGPL-2.1` 与 `NOTICE`"，再接 MIT 正文；
2. `LICENSE.LGPL-2.1` + `LICENSE.GPL-2.0` 原文；
3. `NOTICE`：**由 `gen_mova_libmpv_notice.sh` 从 mova-libmpv 的 flavor 脚本 / 构建产物元数据生成**，
   逐条列组件 + 版本 + 协议；同时写入本批产物对应的 mova-libmpv commit/tag 与 flavor 补丁文件名；
4. `NOTICE` 里单列一节 **"Obtaining the corresponding source / 获取对应源码"**：仓库地址、
   确切 commit、补丁、构建入口命令；
5. `NOTICE` 里单列一节 **"Relinking / 替换为你自己的构建"**：说明 `libmpv.so` 是动态加载的、
   给出 `mova.libmpv.dir` 的用法（把合规论据与产品功能绑在一起，两边都不会腐烂）；
6. **GPL-only 排除证据**：把本批构建实际的关键开关（mpv `-Dgpl=false`、
   FFmpeg `--disable-gpl --disable-nonfree` 及被禁用的 GPL 组件清单）原样贴进 `NOTICE`。
   **如果发现实际构建脚本里拿不出这些开关的确证，本 Task 不算完成——
   要先回 mova-libmpv 补齐再谈发布。**

**验证：** `flutter pub publish --dry-run` 的文件清单里四个文件齐全；
`NOTICE` 里每个组件都能在 mova-libmpv 的 flavor 脚本里找到对应启用项（人工抽查 5 条）。

---

## Task 7：mova 主包文档改写 + **Windows 走 git override**（本期性价比最高的一个 Task）

**Files:** `mova/README.md`、`mova/CHANGELOG.md`、`mova/doc/SPEC.md`、
`mova/packages/media_kit_libs_windows_video_slim/windows/CMakeLists.txt`

**7a. Android 一节**改写为 Task 5 的两行装法，并明确"默认仍是官方版本，这是可选项"。

**7b. Windows 一节**：把"clone 仓库 / 复制 fork 包"改成 **git `dependency_overrides`**：

```yaml
dependency_overrides:
  media_kit_libs_windows_video:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: mova/packages/media_kit_libs_windows_video_slim
      ref: <tag>
```

这是 Windows 的正解（决策 6）：**同名整包替换 → 官方包不参与构建 → 零冲突**，
且不需要 pub.dev（包名被占用，本来也发不了）。

> ⚠️ **前置改动（不做则 git override 必然失败）**：现在的 `windows/CMakeLists.txt` 用
> `${CMAKE_SOURCE_DIR}/../../libmpv/windows-x86_64` 去仓库里取 DLL，
> 而 pub 用 git 依赖时只会把**该 package 子目录**放进缓存，
> 且 LFS 内容是否被 smudge 取决于用户机器上有没有 git-lfs。
> → 必须把 DLL（以及 `windows-devlib/`、`mpv-headers/`）**移进 fork 包目录自身**，
> CMake 路径改为包内相对路径。**这个改动本身要在 Windows 上重新跑一次
> `flutter run -d windows` 验证**（当前接线是真实生效的，不能改坏）。

**7c. iOS / macOS / Linux 一节**：如实写明
「暂无 pub 包方案」+ 各自原因（CocoaPods 无 pickFirst / 产物形态不同 / Linux 用系统 libmpv），
以及"如需接入请提 issue"。**不要暗示很快会有。**

**7d. CHANGELOG**：单列一行，措辞必须强调 **默认行为零变化**。

---

## Task 8：pub.dev 发布流水线（OIDC 自动发布）

**Files:** 新建 `C:\workspace\dart-labs\.github\workflows\publish-mova-libmpv-android.yml`

- 在 pub.dev 的包设置里开 **Automated publishing**，绑定 `icodejoo/dart-labs` 仓库 +
  tag 模式 `mova_libmpv_android-v{{version}}`；
- workflow 用官方 `dart-lang/setup-dart/.github/workflows/publish.yml` 复用工作流
  （`permissions: id-token: write`），**无需在仓库存放任何 pub 凭据**（符合"不硬编码密钥"）；
- 触发方式：**只认 tag push**，不挂在 `build-mova-libmpv.yml` 上——
  一个 pub 版本是永久的，不能是某次普通 CI 的副作用；
- 发布前 checklist（写进 workflow 的 job summary，人工过一遍）：
  MANIFEST 已回填真实 sha256 / Task 6 四件套齐全 / Task 9 真机验证已过 / CHANGELOG 已更新。

**验证：** 先打一个 `-dev.1` 预发布版本走通整条链，确认 pub.dev 页面上
协议显示正确、文件清单里有 4 个 `.so` 与合规文件、包体积在预期（压缩后 11–13 MB 量级）。

---

## Task 9：端到端真机验证（Android，**发布前的硬门槛**）

**Files:** 临时修改 `mova/example/android/app/build.gradle.kts`（**验证完必须还原**）

> example 自己**不改成依赖 pub 包**——它与源码同机，本地 `Copy` 就是对的。
> 这里只借它做端到端验证。更贴近真实下游的做法是另建一个**仓库外的空 Flutter 工程**。

步骤（每步留客观数字，遵循 CLAUDE.md「真机验证前必须先设计基于真实事件的测量方法」）：

1. 仓库外新建空 Flutter 工程，依赖 mova（path 或 dry-run 产物解压后 path）+
   `mova_libmpv_android`（path 依赖到 Task 2 产出的包目录），按 README 配两行；
2. `flutter build apk --release --target-platform android-arm64`；
3. `unzip -p app-release.apk lib/arm64-v8a/libmpv.so | sha256sum`
   **必须等于** `MANIFEST.json` 里 `arm64-v8a.sha256`（**这是决策 3 "app-local 必赢" 的唯一证据，
   不许用体积代替**）；
4. `-Pmova.libmpv.slim=false` 重建 → 同样命令取 sha256 **必须不等于**上面那个，
   且大小 ≈ 11.8 MiB（确认关闭态真的回到官方，不是"两种情况其实一样"）；
5. **不加 `pickFirsts`** 重建 → 构建**必须失败**且报重复 `.so`（确认漏配会被发现）；
6. APK 体积开/关两态字节数对比，记录差值（预期约 −5 MiB/ABI）；
7. 真机（STG AL00 arm64 Android 12）：装开启态 APK，播一条 HLS + 一条 MP4，
   出画出声；`adb logcat | grep -i mediacodec` 确认硬解 codec 被选中（不是软解回退）；
8. **决策 7/Task 5 遗留项的实测**：至少验一次**字幕/OSD 显示**
   （avfilter 被移除后是否受影响——这是 CLAUDE.md 点名"上线前必须实测"的一项，
   **在把二进制公开分发之前把它测掉**）；
9. 结论 + 数字回写「附录 A」。

**验收标准：** 3、4、5、7、8 全过。任何一项不过，**不得进入 Task 8 的发布**。

---

## 风险清单

| # | 风险 | 缓解 / 结论 |
|---|---|---|
| 1 | **"零配置自动生效"做不到**（拓扑 A 下 `pickFirsts` 只能由 app 声明） | 这是物理事实，不是可以绕开的工程问题。对策是**如实写清两行操作**，并保证漏配是**构建失败**而非静默走错（Task 9 第 5 步专门验这个）。**不得在 README 里许诺"装上即生效"** |
| 2 | **pickFirst 的胜者不由我们决定** | 正因如此不走 AAR 合并，改走"拷进 app-local jniLibs"（决策 3）；且验收一律用 sha256 而非体积（Task 9 第 3 步） |
| 3 | **所有用户都要下载 11–13 MB**（若将来改成 mova 硬依赖） | 这正是决策 2 不反转默认的理由之一。当前设计下只有主动加依赖的人付这个成本 |
| 4 | **瘦身版能力面被裁，用户播不了某些片子** | 决策 2 的首要理由。对策：默认不生效 + 包 README 显著列出裁剪项 + Task 9 第 8 步补测 avfilter 影响。**这一条是本方向最大的产品风险，不要弱化** |
| 5 | **pub.dev 版本不可删除，合规缺失会永久留存** | Task 6 排在 Task 8 之前且是硬门槛；先用 `-dev.1` 预发布走通流程 |
| 6 | **官方 media_kit 升级导致 ABI 漂移** | `MANIFEST.json` 的 `mpv_commit` + `validated_against` 是锚点；Task 2 的单测做一条弱一致性断言；mova 升 `media_kit` 依赖时必须复核（写进 SPEC 检查清单） |
| 7 | **Windows git override 改造把现有能跑的接线改坏** | Task 7 的前置改动必须在 Windows 上重跑 `flutter run -d windows` 验证；`--no-enable-impeller` 的已知规避手段照旧 |
| 8 | **维护成本膨胀成"多包发布流水线"** | 这正是决策 1 只发一个包、决策 6 只做 Android 的原因。日常成本 = CI 自动组装 + 打一个 tag；无定时任务、无额外服务 |
| 9 | **`project(":mova_libmpv_android").projectDir` 定位方式在某些 Flutter 版本下不成立** | Task 3 把它当成**待证伪假设**先实测，给了两条退路 |
| 10 | **二进制在 git 里再占一份空间**（`libmpv/` 与包目录各一份） | 都走 LFS；如果实测冗余可观，可让 CI 只在 `package-pub-android` job 里临时组装、不 commit 进 git（用 artifact → 发布 workflow 直接消费）。**Task 2 落地时按实际 LFS 增量决定，二选一即可** |

---

## 分期建议（明确结论）

**第 1 期（本计划全部内容）：只做 Android 一个包，共 9 个 Task。**
顺序 **1 → 2 → 3 → 4 → 5 → 6 → 9 → 8**（Task 7 文档可与 5/6 并行，但
**Task 9 真机验证必须在 Task 8 发布之前**）。
第 1 期的意义是**把"用 pub 包分发自建原生二进制"这套机制整体跑通一次**——
包骨架、CI 组装、开关设计、合规四件套、OIDC 发布，全都是可复用到其它平台的。

**第 2 期（独立立项，不在本期承诺内）：Windows。**
但结论很可能**不是发 pub 包**，而是 Task 7b 那条 git override 路线就已经够用且更干净
（同名替换、零冲突、已验证真机可用）。第 2 期真正要做的只是
"把 DLL 挪进 fork 包目录 + 验证 git 依赖可用"——那已经包含在 Task 7 里了。
**所以务实地说：Windows 在本期就已经拿到它能拿到的最好结果，不需要第 2 期。**

**第 3 期（远期，有 Mac 环境后）：iOS / macOS。**
前置门槛是 mova 自己先把 iOS 接线从零做出来（podspec 引用 `dist/darwin/` 产物），
这与「iOS PiP」那条线共用同一个 Mac 真机门槛，应当合并立项。

**Linux：不做。** 模型不适用（系统 libmpv），README 如实说明即可。

**如果只能做一件事：做 Task 7b（Windows git override）+ Task 7a 的文档改写。**
零发布风险、零新包，就已经把 README 里「唯一获取渠道是 clone 仓库源码」这句最劝退的话
从 Windows 这条线上抹掉了。Android 的 pub 包是更大的收益，但也是更长的链路。

---

## 附录 A：Task 9 实测结论（待填）

> 落地 agent 在 Task 9 完成后回填：APK 内各 ABI `.so` 的 sha256（开/关两态）、
> 漏配 `pickFirsts` 时的真实报错文本、APK 体积差、硬解 codec 名、字幕/OSD 实测结论、
> 真机型号与系统版本、测试时间。**不要写"目测通过"**——本项目的验证约定要求客观数字。
