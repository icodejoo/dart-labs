# mova：构建期自动下载自研瘦身版 libmpv（方向 A2）— 实现计划

**日期：** 2026-09-25
**状态：** 规划（未落地，未开工）
**基线：** mova 0.1.0（pubspec），测试 **815 项全绿**、`flutter analyze` 0 issues（仅剩既有 `feed_player.dart` 警告）

---

## Goal

让下游使用者**不必 clone mova 仓库源码、不必手写 `dependency_overrides`**，就能在自己的项目里用上
mova 自研的瘦身版 libmpv：在 app 构建期由构建系统（Gradle / CMake / CocoaPods）从网络拉取对应
平台的二进制、校验 sha256、覆盖官方 `media_kit_libs_*` 提供的那份。

**明确不做的**：不把二进制塞进 pub 包（`.pubignore` 已排除 `libmpv/`，这条不动）；不做"零配置默认
生效"（见「架构决策 2」——这是本计划最关键的一个决策，结论是 **默认关闭、显式 opt-in**）。

---

## 现状核实（2026-09-25 实读，行号/内容以实际代码为准）

| 事实 | 位置 | 说明 |
|---|---|---|
| 二进制产物 10 个平台目录齐全 | `C:\workspace\dart-labs\mova\libmpv\` | `arm64-v8a`/`armeabi-v7a`/`x86`/`x86_64`（`libmpv.so`）、`ios-arm64`/`macos-amd64`/`macos-arm64`/`macos-universal`（`libmpv.dylib`）、`linux-x86_64`（`libmpv.so`）、`windows-x86_64`（`libmpv-2.dll`） |
| 产物只托管在 git（Git LFS） | `.gitattributes` + CI 的 "Commit built artifact to dist/" 步骤 | 每个平台 job 各自 `git fetch/reset --hard/cp/commit/git lfs push origin main/git push`，5 次重试 |
| CI 已产出 artifact | `C:\workspace\dart-labs\.github\workflows\build-mova-libmpv.yml` | 每个 job 都有 `actions/upload-artifact`：`mova-libmpv-android-<abi>`、`mova-libmpv-ios-arm64-movaslim`、`mova-libmpv-macos-<arch>-movaslim`、Linux/Windows 同理。**已经有现成的上传步骤可以直接被 release job 消费** |
| CI 已有 sha/尺寸检查的位置 | 各 job 的 "Strip and verify" 步骤 | 目前只写 `$GITHUB_STEP_SUMMARY`，没有 sha256 清单 |
| Android 现有接线是**本地 Copy**，不是下载 | `C:\workspace\dart-labs\mova\example\android\app\build.gradle.kts:59-71` | `syncMovaLibmpv`（`Copy`）从 `../../../libmpv/<abi>/libmpv.so` 拷进 `src/main/jniLibs/<abi>/`，`tasks.named("preBuild") { dependsOn(...) }` |
| Android 覆盖官方 .so 的手法 | 同文件 `:48-52` | `packaging { jniLibs { pickFirsts += "**/libmpv.so" } }` |
| Windows 现有接线是**本地 fork 包** | `C:\workspace\dart-labs\mova\packages\media_kit_libs_windows_video_slim\windows\CMakeLists.txt` | 跳过官方 7z 下载；从 `CMAKE_SOURCE_DIR/../../libmpv/windows-x86_64/` 取 dll，再用 `../windows-devlib/libmpv.dll.a` + `../mpv-headers/*.h` 拼出 `${CMAKE_BINARY_DIR}/libmpv` 给 `media_kit_video` 链接。`example/pubspec.yaml` 用 `dependency_overrides` 指过去 |
| 官方 CMake 侧本来就有"下载+校验"先例 | 同文件的 `download_and_verify(url md5 archive)` + ANGLE 下载 | `file(DOWNLOAD)` + `file(MD5)`，A2 的 CMake 侧可直接照抄这个形状（换成 SHA256） |
| `.pubignore` 排除了 `libmpv/`、`packages/`、`doc/` | `C:\workspace\dart-labs\mova\.pubignore` | **清单文件必须放在不被排除的路径**（本计划放 `tool/`，Task 1 要加一条断言防回归） |
| README 当前说法 | `C:\workspace\dart-labs\mova\README.md:435-475` | 「进阶：接入自研瘦身版 libmpv（可选，仅进阶用户）」，明确写着二进制"**唯一的获取渠道**是 clone mova 仓库源码……尚未提供 GitHub Release 一类更方便的分发渠道" |

---

## 架构决策

### 决策 1：托管方式 —— **GitHub Release（`icodejoo/dart-labs` 仓库），不用 LFS raw 链接**

**结论：** 新增一条独立于代码版本的二进制发行线，tag 形如 `mova-libmpv-v1`、`mova-libmpv-v2`……
每个平台一个压缩包资产 + 一份 `SHA256SUMS` 文本资产。

**理由：**

1. **LFS raw 链接会把整个仓库拖下水。** GitHub 免费账户 LFS 带宽是每月 1 GiB 配额，且**配额耗尽后
   整个仓库的 LFS 会被禁读**（不是只影响这条链路，是包括团队自己 `git clone`/CI checkout 在内全挂）。
   下游一次 Android 四 ABI 构建就是约 25 MiB；40 次构建打爆配额。这不是"有点风险"，是**把下游流量
   接到自己开发链路的单点上**，不能接受。
2. **Release 资产不计入 LFS 配额**，走 GitHub 自己的对象存储 + CDN，公开仓库对匿名下载没有额度限制
   （只有粗粒度限流，见「风险 2」）。
3. **可版本化、可回滚、不可变。** 二进制一旦随某个 tag 发布就不会被后续 CI 覆盖，而 LFS raw 指向的是
   `main` 分支的当前内容——CI 每次重建都会悄悄换掉下游拉到的东西，这与「决策 4」的版本锁定直接冲突。
4. **规避已知运维坑。** CLAUDE.md 记录过：本仓库 `origin` 双 push-url（codeup + GitHub），
   `git lfs push --object-id origin` 只会推到其中一个端点，**codeup 端长期缺对象是这套架构的常态**。
   把下游分发挂在 LFS 上等于把这个已知的、需要人工补传的脆弱点暴露给外部用户。Release 资产没有这个问题。

**被否决的备选：**

| 备选 | 否决理由 |
|---|---|
| Git LFS raw 链接（`media.githubusercontent.com`） | 上述 1/3/4 |
| 自建 CDN / 对象存储 | 团队是个人/小团队维护，多一个要付费、要续期、要监控的外部资源，违反「不要设计需要专职团队维护的发布流水线」 |
| 发一个单独的 pub 包装二进制（仿 `media_kit_libs_android_video`） | 官方那个包**本身也不含二进制**，它也是构建时下载。真把二进制塞进 pub 包会直接撞上 pub.dev 的包体积限制（100 MB）与审核观感 |
| 继续纯手动（方向 B） | 就是现状，不叫 A2 |

**Tag 命名与节奏：** `mova-libmpv-v<N>`，`N` 单调递增整数，**与 mova 包版本号解耦**（理由见决策 4）。
只有在二进制内容真的变化并且团队愿意为它背书时才手动打 tag（`workflow_dispatch` 触发，不自动发），
避免每次 CI 重建都产生一个新 release。

### 决策 2（最关键）：**提供显式开关，默认关闭（opt-in）**

**结论：** 自动下载**默认不启用**。使用者必须显式打开：

| 平台 | 开关 | 值 |
|---|---|---|
| 全平台统一兜底 | 环境变量 `MOVA_LIBMPV_SLIM` | `1` / `true` 启用 |
| Android | `gradle.properties` 里 `mova.libmpv.slim=true` | 优先级高于环境变量 |
| Windows / Linux | CMake `-DMOVA_LIBMPV_SLIM=ON` | 优先级高于环境变量 |
| iOS / macOS | 环境变量 `MOVA_LIBMPV_SLIM=1`（podspec 只有这一个口子） | — |

另外**必须同时提供离线口子** `MOVA_LIBMPV_LOCAL_DIR`（Android 对应 `mova.libmpv.localDir`）：指向一个
已经手工放好二进制的本地目录，构建脚本跳过网络直接用它（仍做 sha256 校验）。

**理由（这一条要顶住"装了就自动是瘦身版"的诱惑）：**

1. **与项目已经拍过板的原则直接一致，不是冲突。** 用户此前明确说过"内网构建环境不应该依赖运行时联网
   下载二进制"。那条原则的**本质**不是"只约束 mova 自己的 example"，而是**"构建不应该被一个可选的
   优化项拖成必须联网"**。如果 A2 默认开启，任何一个内网 CI 里的下游用户，仅仅因为 `pub add mova`
   就会在构建期挂在一个访问不到的 GitHub 地址上——把我们自己明确拒绝过的痛，原样转嫁给了别人。
   默认关闭 + `MOVA_LIBMPV_LOCAL_DIR`，等于把同一条原则完整地传递下去。
2. **默认联网下载二进制是 pub 生态里的敏感行为。** 用户装一个视频播放器插件，不应该在毫不知情的情况下
   多出一次对第三方地址的网络请求和一个未经其审阅的原生二进制。默认关闭把这件事变成一次明确的知情选择。
3. **收益/风险不对称。** 打开的收益是每 ABI 省约 5 MiB（arm64-v8a 11.8 → 6.5 MiB）——真实但不是刚需；
   默认打开的风险是**下游构建从"一定能过"变成"取决于网络"**。为一个可选优化牺牲构建确定性，划不来。
4. **opt-in 的成本极低。** Android 两行（`gradle.properties` 一行 + app 模块 `pickFirsts` 一行），
   其余平台一个环境变量。愿意省体积的人不会被这两行劝退。

**反方意见（如实记录，供拍板时对照）：** "默认关闭 = 几乎没人会用，A2 相比方向 B 只省了下载二进制这一步"。
这个批评成立。缓解办法不是改默认值，而是把开启方式写到 README 最显眼处，并在 mova 首次运行时**不做**
任何形式的提示（不要在 SDK 里打广告日志）。如果将来实测确实无人使用，再单独立项讨论是否改默认——
**但那应该是一个有数据支撑的独立决定，不是本计划顺手改掉的**。

### 决策 3：下载失败的降级行为 —— **构建失败（fail loud），不静默回退**

**结论：** 开关打开后，下载失败 / sha256 不匹配 / 清单缺该平台条目 → **构建直接失败**，错误信息里给出
三条出路（关掉开关、用 `MOVA_LIBMPV_LOCAL_DIR`、换镜像 `MOVA_LIBMPV_BASE_URL`）。
另提供一个显式的宽松开关 `MOVA_LIBMPV_FALLBACK=official`，打开后下载失败降级为 warning + 用官方版本。

**理由：** 静默回退会制造"以为在用瘦身版、其实不是"的不可观测状态。本项目**已经被这种漂移坑过一次**：
CLAUDE.md 记录 `libmpv/` 与 `example/android/.../jniLibs/` 曾长期静默不同步，正是因为没有任何一环会
报错。二进制来源必须是可断言的：要么确定是瘦身版，要么构建停下来告诉你为什么不是。
sha256 不匹配尤其**绝不允许**降级——那已经不是网络问题，是内容不可信。

### 决策 4：版本对齐 —— **随包发布一份锁死的清单文件，mova 版本 ↔ release tag 一对一**

**结论：** mova 包内新增 `tool/libmpv_manifest.json`（几 KB 纯文本，随 pub 包发布），内容形如：

```json
{
  "schema": 1,
  "release_tag": "mova-libmpv-v1",
  "base_url": "https://github.com/icodejoo/dart-labs/releases/download/mova-libmpv-v1",
  "mpv_commit": "78d43740f52db817d98bcf24fb30a76ab6fa13ff",
  "platforms": {
    "android-arm64-v8a":  { "asset": "mova-libmpv-android-arm64-v8a.tar.gz",  "file": "libmpv.so",     "size": 6190732, "sha256": "…" },
    "android-armeabi-v7a":{ "asset": "mova-libmpv-android-armeabi-v7a.tar.gz","file": "libmpv.so",     "size": 0,       "sha256": "…" },
    "android-x86":        { "asset": "mova-libmpv-android-x86.tar.gz",        "file": "libmpv.so",     "size": 0,       "sha256": "…" },
    "android-x86_64":     { "asset": "mova-libmpv-android-x86_64.tar.gz",     "file": "libmpv.so",     "size": 0,       "sha256": "…" },
    "windows-x86_64":     { "asset": "mova-libmpv-windows-x86_64.tar.gz",     "file": "libmpv-2.dll",  "size": 0,       "sha256": "…" }
  }
}
```

- **清单是常量，不是"最新"指针。** mova 0.7.0 发布时清单里写死 `mova-libmpv-v1`，那么全世界所有
  装了 mova 0.7.0 的人，永远只会拉到 `mova-libmpv-v1` 的那批字节。CI 后续重建二进制**不影响**已发布的
  mova 版本——这正是 LFS raw 链接做不到的事。
- **升级 mova 才可能换二进制**，而且会体现在 CHANGELOG 里（Task 7 要求：清单 `release_tag` 变更必须
  在 CHANGELOG 单列一行）。
- **只有一个真相源。** 四个平台的构建脚本都读同一个 JSON，不许在 Gradle/CMake/podspec 里各自硬编码
  URL 或哈希。
- **兼容性锚点。** 清单里记 `mpv_commit`，与 `media_kit_libs_windows_video_slim` 的 `mpv-headers/`
  所 pin 的 commit 必须一致，否则链接期 ABI 会不匹配（这是 Windows 侧已经踩过的形状，见现状核实表）。

### 决策 5：校验哈希机制

- **生成侧（CI）：** 新增 `package` job（见 Task 2），`needs` 所有平台 job，用
  `actions/download-artifact` 把各 job 已有的 artifact 全拉下来，逐个打成 `.tar.gz`，
  `sha256sum *.tar.gz > SHA256SUMS`，连同压缩包一起 `gh release create/upload`。
  同时把**包内单文件**（`libmpv.so` / `libmpv-2.dll`）的 sha256 也写进 `SHA256SUMS.files`——
  构建脚本解压后校验的是这一层，比校验压缩包更贴近"最终进入 APK 的那个字节流"。
- **消费侧（各平台）：**
  - Gradle：`java.security.MessageDigest.getInstance("SHA-256")`，JDK 自带，无新依赖。
  - CMake：`file(SHA256 <path> <var>)`，CMake 内置，无新依赖。照抄现有 `download_and_verify()`
    的形状，把 `file(MD5)` 换成 `file(SHA256)`。
  - podspec / `script_phase`：`shasum -a 256`，macOS 自带。
- **失配处理：** 删除已下载文件 + `FATAL`/`throw GradleException`，不重试、不降级（决策 3）。

### 决策 6：平台落地优先级

| 平台 | 优先级 | 理由 |
|---|---|---|
| **Android（4 个 ABI）** | **P0，本计划唯一必做** | ①收益最大（arm64 11.8→6.5 MiB，且 APK 体积对 Android 用户最敏感）；②是唯一已有**真机验证过**的接线路径（`syncMovaLibmpv` + `pickFirsts`），A2 只需把 `Copy` 的来源从本地换成"下载+缓存"，风险最低；③四个 ABI 产物都是单文件 `.so`，形态最简单 |
| **Windows x86_64** | P1，本计划只列 spike Task，不承诺落地 | 已有 fork 包经验，但 **A2 形态与 fork 包完全不同**：A2 不能要求下游做 `dependency_overrides`（那就退回方向 B 了），必须让 mova 自己的 `windows/CMakeLists.txt` 在官方包**之后**覆盖输出目录里的 `libmpv-2.dll`。可行性未验证（链接期仍用官方的 `libmpv.dll.a`，依赖两边 ABI 兼容——理论上成立因为 pin 了同一个 mpv commit，但必须实测）。**先做一次 spike，结论出来再决定要不要排 Task** |
| **iOS / macOS** | P2，本期不做，文档明确"走方向 B" | ①iOS 产物是**多 dylib bundle**（`libs` 归档格式把 ffmpeg/dav1d/libass/freetype/harfbuzz/fribidi 拆成独立 dylib），不是 Android 那种单文件，替换 `media_kit_libs_ios_video` 的 Frameworks 要处理签名、embed、bitcode 等一整套；②mova 自己**从未在 iOS 上接线过自研产物**（CLAUDE.md：「iOS 尚未接线，podspec 还没引用 dist/darwin/ 产物」），从零开始；③没有 Mac 真机验证环境这件事在 iOS PiP 那条线上已经是已知门槛 |
| **Linux x86_64** | P3，本期不做，文档明确"走方向 B" | 下游占比最低，且 Linux 产物是动态链接系统 libass/dav1d 的形态，替换后对宿主机依赖敏感，收益/风险比最差 |

---

## Tech Stack / 依赖

- Gradle Kotlin DSL（JDK 自带 `java.net.URI`/`HttpURLConnection`/`MessageDigest`）
- CMake 内置 `file(DOWNLOAD)` / `file(SHA256)`
- GitHub Actions + `gh` CLI（runner 自带）
- Dart：只有清单的 schema 校验单测用 `dart:convert` + `flutter_test`

**新增第三方依赖：无。**

> ⚠️ **需要用户确认的潜在新依赖（本计划不引入，仅备案）**：如果将来想提供
> `dart run mova:fetch_libmpv` 这种"构建前预下载"CLI（内网场景下在有网机器上先拉好），
> 用 `dart:io` 的 `HttpClient` 就够，**仍然不需要新依赖**；只有当想做断点续传/进度条/重试策略时
> 才会想引入 `http`/`dio`——那**属于需要用户先同意的新依赖**，不得在落地时顺手加进去。

---

## 文件结构

**新建（随 pub 包发布）**

| 文件 | 用途 | Task |
|---|---|---|
| `tool/libmpv_manifest.json` | 唯一真相源：release tag / base_url / 每平台 asset+sha256 | 1 |
| `tool/gen_libmpv_manifest.dart` | 从本地 `libmpv/` 或 CI 产物目录生成上表（开发者工具，不参与运行时） | 1 |
| `android/mova_libmpv.gradle` | 下游 `apply from:` 的 Gradle 脚本：读清单 → 下载 → 校验 → 缓存 → 注入 jniLibs | 3/4/5 |
| `test/tool/libmpv_manifest_test.dart` | 清单 schema/完整性单测 + `.pubignore` 回归断言 | 1 |

**新建（不随包发布，仓库内）**

| 文件 | 用途 | Task |
|---|---|---|
| `doc/notes/2026-XX-XX-windows-auto-download-spike.md` | Windows P1 spike 的结论 | 8 |

**修改**

| 文件 | 改动 | Task |
|---|---|---|
| `C:\workspace\dart-labs\.github\workflows\build-mova-libmpv.yml` | 新增 `package-release` job（`needs` 全平台，`workflow_dispatch` 输入 tag） | 2 |
| `C:\workspace\dart-labs\mova\.pubignore` | 确认 `tool/` 不被排除（当前未排除，加注释固化） | 1 |
| `C:\workspace\dart-labs\mova\README.md` | 「进阶：接入自研瘦身版 libmpv」整节重写 | 7 |
| `C:\workspace\dart-labs\mova\CHANGELOG.md` | 记录新增能力 + 清单 `release_tag` | 7 |
| `C:\workspace\dart-labs\mova\doc\SPEC.md` | 新增「瘦身版 libmpv 分发」一节 | 7 |
| `C:\workspace\dart-labs\mova\example\android\app\build.gradle.kts` | **只在 Task 6 的验证里临时切换**，验证完保留本地 `Copy` 方式不变（example 是内网优先场景，不该依赖下载） | 6 |

**测试数量推进**（基线 **815**）：Task 1 → 821、Task 2 → 821、Task 3 → 821、Task 4 → 821、
Task 5 → 821、Task 6 → 821（真机/构建验证，无单测）、Task 7 → 821、Task 8 → 821。

> 说明：本计划几乎全是构建脚本，Dart 侧只有清单这一处可单测。**不要为了凑数给 Gradle/CMake 脚本
> 编造 Dart 单测**——它们的验收靠真实构建产物的 sha256 比对（Task 6）。

---

## Task 1：清单文件 + 生成脚本 + schema 单测

**Files:**
- 新建：`C:\workspace\dart-labs\mova\tool\libmpv_manifest.json`
- 新建：`C:\workspace\dart-labs\mova\tool\gen_libmpv_manifest.dart`
- 新建：`C:\workspace\dart-labs\mova\test\tool\libmpv_manifest_test.dart`
- 修改：`C:\workspace\dart-labs\mova\.pubignore`（加一行注释固化"`tool/` 必须随包发布"）

**做什么：**

1. 按「决策 4」的形状写出 `tool/libmpv_manifest.json`。**首版 `release_tag` 先填占位
   `mova-libmpv-v0-unreleased`、sha256 全填空串**，Task 2 跑完真实 release 后由
   `gen_libmpv_manifest.dart` 回填。
2. `gen_libmpv_manifest.dart`：接受一个目录参数（默认 `libmpv/`），遍历平台子目录，算每个文件的
   sha256 与字节数，输出新的 JSON 到 stdout。骨架：

```dart
// Regenerates tool/libmpv_manifest.json from a directory of built libmpv
// artifacts. Developer tool only — never imported by lib/.
//
// 从一批已构建的 libmpv 产物目录重新生成 tool/libmpv_manifest.json。
// 仅供开发者使用，lib/ 永不引用。
//
// Usage / 用法:
//   dart run tool/gen_libmpv_manifest.dart --tag mova-libmpv-v1 --dir libmpv
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart'; // ⚠️ 见下方说明，落地时不要直接用

const _platformFiles = <String, String>{
  'android-arm64-v8a': 'arm64-v8a/libmpv.so',
  'android-armeabi-v7a': 'armeabi-v7a/libmpv.so',
  'android-x86': 'x86/libmpv.so',
  'android-x86_64': 'x86_64/libmpv.so',
  'windows-x86_64': 'windows-x86_64/libmpv-2.dll',
};
```

> ⚠️ **依赖提示（必须遵守）**：`package:crypto` 是 mova 当前**没有**的依赖。
> 落地时**不要**加它——这个脚本只在开发者机器上手工跑，直接 `Process.run('sha256sum'/'certutil', ...)`
> 或读 CI 已生成的 `SHA256SUMS` 回填即可。如果落地 agent 认为确实需要 `crypto`，
> **必须先问用户**（CLAUDE.md 依赖管理约定），不得自行 `pub add`。

3. 单测 `test/tool/libmpv_manifest_test.dart`（**+6 项**）：
   - 清单文件存在且能被 `jsonDecode`；
   - `schema == 1`；
   - `release_tag` / `base_url` / `mpv_commit` 非空；
   - `platforms` 至少包含 4 个 Android ABI 键，键名与 `example/android/app/build.gradle.kts` 里
     `syncMovaLibmpv` 用的 ABI 目录名一一对应（防止两边命名漂移）；
   - 每个平台条目的 `sha256` 要么是空串（未发布占位），要么是 64 位小写 hex；
   - `.pubignore` 的文本里**不包含** `tool/` 这一行（回归断言：防止将来有人顺手把 `tool/` 也排除掉，
     导致清单不随包发布、下游脚本读不到文件）。

**验证：** `flutter test test/tool/libmpv_manifest_test.dart` 6 项绿；
`flutter pub publish --dry-run` 的文件清单里能看到 `tool/libmpv_manifest.json`。

---

## Task 2：CI 新增 `package-release` job（发布二进制到 GitHub Release）

**Files:** 修改 `C:\workspace\dart-labs\.github\workflows\build-mova-libmpv.yml`

**做什么：** 在文件末尾追加一个新 job。**不改动任何现有 job**（现有的 "Commit built artifact to dist/"
步骤保留——git/LFS 仍是团队自己的真相源，Release 只是对外分发层）。

```yaml
  # 2026-XX-XX: packages every platform's already-uploaded artifact into a
  # GitHub Release, so downstream projects can fetch the slimmed libmpv at
  # build time without cloning this repo (see mova/doc/plans/
  # 2026-09-25-libmpv-auto-download.md). Manual-dispatch only: a release tag
  # is a promise about a specific set of bytes, not something every CI run
  # should mint.
  package-release:
    name: "Package + publish GitHub Release"
    runs-on: ubuntu-22.04
    needs: [android-arm64, android-other-abi, darwin, ios, linux, windows]
    if: github.event_name == 'workflow_dispatch' && inputs.release_tag != ''
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4

      - name: Download every platform artifact
        uses: actions/download-artifact@v4
        with:
          path: raw

      - name: Repack into per-platform tarballs + SHA256SUMS
        run: |
          mkdir -p out
          # raw/<artifact-name>/<file> —— artifact 名见各 job 的 upload 步骤
          pack() {  # $1=平台键  $2=artifact 目录  $3=归档内文件名
            src=$(find "raw/$2" -type f | head -1)
            test -n "$src" || { echo "::error::missing artifact $2"; exit 1; }
            mkdir -p "stage/$1" && cp "$src" "stage/$1/$3"
            tar -czf "out/mova-libmpv-$1.tar.gz" -C "stage/$1" "$3"
            echo "$(sha256sum "stage/$1/$3" | cut -d' ' -f1)  $1/$3" >> out/SHA256SUMS.files
          }
          pack android-arm64-v8a   mova-libmpv-android-arm64-v8a   libmpv.so
          pack android-armeabi-v7a mova-libmpv-android-armeabi-v7a libmpv.so
          pack android-x86         mova-libmpv-android-x86         libmpv.so
          pack android-x86_64      mova-libmpv-android-x86_64      libmpv.so
          pack windows-x86_64      mova-libmpv-windows-x86_64      libmpv-2.dll
          # iOS/macOS/Linux 暂不纳入（见计划「决策 6」），产物仍只在 git/LFS
          ( cd out && sha256sum *.tar.gz > SHA256SUMS )
          cat out/SHA256SUMS out/SHA256SUMS.files >> "$GITHUB_STEP_SUMMARY"

      - name: Ship LGPL compliance files
        run: |
          # LGPL：分发二进制必须附带许可证文本与"如何取得对应源码/重新链接"的说明。
          cp mova-libmpv/README.md out/BUILD-RECIPE.md
          cp LICENSE out/LICENSE-mova.txt 2>/dev/null || true
          printf '%s\n' \
            "These binaries are LGPL-2.1 builds of mpv/FFmpeg." \
            "Build recipe: see BUILD-RECIPE.md and the mova-libmpv/ directory of" \
            "https://github.com/icodejoo/dart-labs at tag ${{ inputs.release_tag }}." \
            > out/README-LICENSING.txt

      - name: Create release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "${{ inputs.release_tag }}" out/* \
            --title "mova slimmed libmpv ${{ inputs.release_tag }}" \
            --notes "Prebuilt slimmed libmpv for mova. See README-LICENSING.txt."
```

同时给 `on.workflow_dispatch` 加输入：

```yaml
on:
  workflow_dispatch:
    inputs:
      release_tag:
        description: "Publish a GitHub Release with this tag (e.g. mova-libmpv-v1). Leave empty to only rebuild."
        required: false
        default: ''
```

**验证：**
1. 手动 `workflow_dispatch` 跑一次，`release_tag` 留空 → `package-release` 被跳过，其余 job 行为与今天完全一致；
2. 再跑一次填 `mova-libmpv-v1` → Release 页面出现 5 个 `.tar.gz` + `SHA256SUMS` + `SHA256SUMS.files` + 许可证文件；
3. 在一台干净机器上 `curl -L <asset-url> | tar -xz` 后 `sha256sum` 与 `SHA256SUMS.files` 逐字节一致；
4. 用 Task 1 的生成脚本把真实 sha256 回填进 `tool/libmpv_manifest.json`，`release_tag` 改为 `mova-libmpv-v1`。

---

## Task 3：Android —— `android/mova_libmpv.gradle` 骨架与注入方式验证

**Files:** 新建 `C:\workspace\dart-labs\mova\android\mova_libmpv.gradle`

**这个 Task 要先解决一个必须诚实面对的结构问题：**

"装了 mova 就自动是瘦身版"在 Android 上**做不到完全零配置**。原因：Flutter plugin 的
`android/build.gradle` 是作为 subproject 被 include 的，它**无法**替 app 模块声明
`packaging { jniLibs { pickFirsts += "**/libmpv.so" } }`，而没有这一行，AGP 在合并
`media_kit_libs_android_video` 的 `libmpv.so` 和我们的同名 `.so` 时会**直接报重复冲突**
（或取到不确定的一份）。从 mova 的 subproject 去反向配置 `:app` 是可以写出来的
（`rootProject.subprojects { ... }` + `afterEvaluate`），但那是对宿主工程的隐式侵入，
一旦冲突极难排查——**明确否决**。

因此 A2 在 Android 上的最终形态是**两行 opt-in**：

```kotlin
// android/app/build.gradle.kts
android {
    packaging { jniLibs { pickFirsts += "**/libmpv.so" } }   // ① 让我们的 .so 赢
}
apply(from = "${rootProject.projectDir}/../.dart_tool/… /mova/android/mova_libmpv.gradle")  // ② 挂上下载 task
```

（②的实际路径由 `flutter pub get` 生成的 plugin 路径决定，Task 3 的一个子目标就是确定一条**稳定可写**
的引用路径并写进 README；如果发现没有稳定路径，退而要求用户把脚本内容复制进自己的 build 文件——
这仍然比方向 B 的"clone 整个仓库拿二进制"好，因为脚本是随 pub 包发的、二进制是自动下的。）

**脚本骨架（本 Task 只做结构，下载逻辑在 Task 4）：**

```groovy
// mova: fetches the project's slimmed libmpv at build time and feeds it into
// the app's jniLibs. Opt-in — does nothing unless explicitly enabled.
//
// mova：构建期拉取瘦身版 libmpv 并注入 app 的 jniLibs。默认不启用。
//
// Enable / 启用: gradle.properties -> mova.libmpv.slim=true
//                或环境变量 MOVA_LIBMPV_SLIM=1
// Offline / 离线: mova.libmpv.localDir=<dir>  或 MOVA_LIBMPV_LOCAL_DIR=<dir>

def enabled = (project.findProperty('mova.libmpv.slim') ?: System.getenv('MOVA_LIBMPV_SLIM') ?: 'false').toString()
if (!(enabled in ['true', '1'])) {
    logger.lifecycle("[mova] slim libmpv disabled (set mova.libmpv.slim=true to enable)")
    return
}

def manifestFile = file("${projectDir}/../tool/libmpv_manifest.json")   // 随包发布
def manifest = new groovy.json.JsonSlurper().parse(manifestFile)
def abis = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
def cacheRoot = new File("${System.getProperty('user.home')}/.gradle/caches/mova-libmpv/${manifest.release_tag}")

def fetchMovaLibmpv = tasks.register('fetchMovaLibmpv') { /* Task 4 填充 */ }

def syncMovaLibmpv = tasks.register('syncMovaLibmpv', Copy) {
    dependsOn fetchMovaLibmpv
    abis.each { abi -> from(new File(cacheRoot, "${abi}/libmpv.so")) { into abi } }
    destinationDir = file("${buildDir}/mova-libmpv/jniLibs")
}

android {
    sourceSets { main { jniLibs.srcDirs += "${buildDir}/mova-libmpv/jniLibs" } }
}
tasks.named('preBuild') { dependsOn syncMovaLibmpv }
```

**验证：**
- 开关关闭时：`./gradlew :app:assembleDebug` 的 task 列表里**没有** `fetchMovaLibmpv`/`syncMovaLibmpv`，
  日志有一行 disabled 提示，APK 里的 `lib/arm64-v8a/libmpv.so` 大小 ≈ 11.8 MiB（官方版）。
- 开关打开、`localDir` 指向本仓库 `libmpv/`（Task 5 的口子，先于 Task 4 可用）：
  `unzip -p app-debug.apk lib/arm64-v8a/libmpv.so | sha256sum` **等于** `libmpv/arm64-v8a/libmpv.so` 的 sha256。
  **这条比"大小对得上"强，必须用 sha256 而不是看体积。**

---

## Task 4：Android 下载 + sha256 校验 + 缓存

**Files:** 修改 `C:\workspace\dart-labs\mova\android\mova_libmpv.gradle`

填充 `fetchMovaLibmpv`：

```groovy
def fetchMovaLibmpv = tasks.register('fetchMovaLibmpv') {
    outputs.dir(cacheRoot)
    doLast {
        def baseUrl = System.getenv('MOVA_LIBMPV_BASE_URL') ?: manifest.base_url
        abis.each { abi ->
            def entry = manifest.platforms["android-${abi}"]
            if (entry == null) throw new GradleException("[mova] manifest has no entry for android-${abi}")
            def dest = new File(cacheRoot, "${abi}/libmpv.so")
            if (dest.exists() && sha256(dest) == entry.sha256) return   // 缓存命中，跳过网络
            dest.parentFile.mkdirs()
            def tmp = new File(dest.parentFile, 'libmpv.so.part')
            def url = "${baseUrl}/${entry.asset}"
            logger.lifecycle("[mova] downloading ${url}")
            try {
                // tar.gz 解包用 Gradle 内置的 resources.gzip/tarTree，避免外部命令依赖
                def archive = new File(dest.parentFile, entry.asset)
                new URL(url).withInputStream { i -> archive.withOutputStream { o -> o << i } }
                copy { from tarTree(resources.gzip(archive)); into dest.parentFile }
            } catch (Exception e) {
                throw new GradleException(
                    "[mova] failed to download slimmed libmpv for ${abi} from ${url}: ${e.message}\n" +
                    "  - set mova.libmpv.slim=false to use the official media_kit binary\n" +
                    "  - or set mova.libmpv.localDir=<dir> to use a pre-downloaded copy (offline/intranet)\n" +
                    "  - or set MOVA_LIBMPV_BASE_URL=<mirror> to use a mirror", e)
            }
            def actual = sha256(dest)
            if (actual != entry.sha256) {
                dest.delete()
                throw new GradleException(
                    "[mova] sha256 mismatch for android-${abi}: expected ${entry.sha256}, got ${actual}. " +
                    "Refusing to use an unverified native binary.")
            }
        }
    }
}

def sha256(File f) {
    def md = java.security.MessageDigest.getInstance('SHA-256')
    f.withInputStream { s -> byte[] buf = new byte[1 << 16]; int n; while ((n = s.read(buf)) > 0) md.update(buf, 0, n) }
    return md.digest().collect { String.format('%02x', it) }.join()
}
```

要点：
- **缓存键是 `release_tag`**，命中即完全跳过网络 → 同一台机器第二次构建不联网（对 CI 缓存友好，
  README 要教用户把 `~/.gradle/caches/mova-libmpv` 加进 CI 缓存路径）。
- **命中判定用 sha256 而不是"文件存在"**，防止半截下载的残留被当成有效缓存。
- **不做重试、不做超时兜底后降级**（决策 3）；只把三条出路写进错误信息。

**验证：**
1. 清空 `~/.gradle/caches/mova-libmpv`，开开关构建 → 日志出现 downloading，APK 里的 `.so` sha256 与清单一致；
2. 再构建一次 → 没有 downloading 日志（缓存命中），构建时长明显更短；
3. 故意把清单里某个 `sha256` 改错一位 → 构建**失败**，错误信息含 "sha256 mismatch"，且缓存文件被删除；
4. 断网构建（缓存已清空）→ 构建**失败**，错误信息三条出路齐全，**没有**静默用官方版本。

---

## Task 5：离线 / 内网逃生口 `localDir`

**Files:** 修改 `C:\workspace\dart-labs\mova\android\mova_libmpv.gradle`

```groovy
def localDir = project.findProperty('mova.libmpv.localDir') ?: System.getenv('MOVA_LIBMPV_LOCAL_DIR')
if (localDir) {
    logger.lifecycle("[mova] using local slim libmpv from ${localDir} (no network)")
    // 仍然校验 sha256：本地目录也可能是旧版本
    abis.each { abi ->
        def f = new File("${localDir}/${abi}/libmpv.so")
        if (!f.exists()) throw new GradleException("[mova] ${f} not found")
        def expected = manifest.platforms["android-${abi}"]?.sha256
        if (expected && expected != '' && sha256(f) != expected) {
            throw new GradleException(
                "[mova] local libmpv for ${abi} does not match manifest ${manifest.release_tag}. " +
                "Either update the local copy, or set mova.libmpv.skipVerify=true if you know what you're doing.")
        }
    }
    cacheRoot = new File(localDir)   // 下游 Copy 直接吃这个目录
}
```

外加 `mova.libmpv.skipVerify=true`：**只对 `localDir` 生效，不对网络下载生效**——自己手工放进来的
文件允许自己负责（比如用户自己重新编了一版），但从网上拉的东西永远必须校验。

**验证：**
- `-Pmova.libmpv.localDir=<repo>/libmpv` 全程不联网构建成功，APK 里的 `.so` sha256 匹配；
- 指向一个内容被改过的目录 → 失败并提示；加 `-Pmova.libmpv.skipVerify=true` → 通过并有 warning；
- 用 `MOVA_LIBMPV_LOCAL_DIR` 环境变量走同样两条路径。

---

## Task 6：端到端真机验证（Android）

**Files:** 临时修改 `C:\workspace\dart-labs\mova\example\android\app\build.gradle.kts`（**验证完必须还原**）

> example 自己**不改成下载方式**——它是内网优先的开发场景，本地 `Copy` 就是对的。
> 这里只是借它做一次端到端验证。

**步骤（每一步都要留下客观数字，遵循 CLAUDE.md「真机验证前必须先设计基于真实事件的测量方法」）：**

1. 新建一个**干净的**空 Flutter 工程（不在 monorepo 内，不能访问 `libmpv/` 相对路径），
   `pubspec.yaml` 里用 path 依赖指向 mova（或用 `pub publish --dry-run` 打出的包解压后 path 依赖，
   更贴近真实下游），按 README 新写的两行 opt-in 配置；
2. `flutter build apk --release --target-platform android-arm64`；
3. `unzip -p build/app/outputs/flutter-apk/app-release.apk lib/arm64-v8a/libmpv.so | sha256sum`
   **必须等于** `tool/libmpv_manifest.json` 里 `android-arm64-v8a.sha256`；
4. 关掉开关重建，同样命令取 sha256 **必须不等于**上面那个，且文件大小 ≈ 11.8 MiB（确认关闭态真的
   走官方版本，不是"两种情况其实一样"）；
5. APK 体积对比：开/关两次 `ls -l app-release.apk` 的字节数，记录差值（预期约 −5 MiB/ABI）；
6. 真机播放（STG AL00）：装开启态 APK，播一条 HLS + 一条 MP4，确认出画出声、硬解正常
   （`adb logcat | grep -i mediacodec` 能看到硬解 codec 被选中，不是软解回退）；
7. 结论连同 6 个数字回写本文件「附录 A」。

**验收标准：** 3、4、6 三项全部通过。任何一项不过，A2 不算跑通，不得进入 Task 7 的文档改写。

---

## Task 7：README / CHANGELOG / SPEC 文档改写

**Files:**
- `C:\workspace\dart-labs\mova\README.md`（`:435-475` 整节重写）
- `C:\workspace\dart-labs\mova\CHANGELOG.md`
- `C:\workspace\dart-labs\mova\doc\SPEC.md`

**README 改写要点（当前那一节的三处说法必须改）：**

| 当前说法（`README.md`） | 改成 |
|---|---|
| `:453-454`「二进制目前**唯一的获取渠道**是 clone `mova` 仓库源码……尚未提供 GitHub Release 一类更方便的分发渠道」 | 「Android 支持构建期自动下载（默认关闭，两行开启）；其余平台仍需手工获取，二进制现已发布在 GitHub Release `mova-libmpv-v<N>`」 |
| `:445-454` Android 小节整段（教人写 `Copy` task 从本地仓库拷） | 换成 opt-in 两行 + 缓存目录说明 + 离线 `localDir` 说明 + 错误信息对照表 |
| `:472-475` 免责声明「瘦身版二进制版本与 mova 包版本没有强绑定关系」 | 改成「自动下载路径下二者是强绑定的：每个 mova 版本的 `tool/libmpv_manifest.json` 锁死一个 release tag；手工路径仍需自己对齐」 |

新增必须写清的四件事：

1. **为什么默认关闭**（一句话：不想让任何人的构建在毫不知情的情况下变成必须联网）；
2. **内网/离线怎么办**（`MOVA_LIBMPV_LOCAL_DIR`，以及从 Release 页面手工下载哪几个文件）；
3. **CI 缓存怎么配**（缓存 `~/.gradle/caches/mova-libmpv`，key 挂 mova 版本号）；
4. **iOS / macOS / Linux 明确"暂不支持自动下载，走手工方式"**，并给出 Release 资产地址
   （比今天的"clone 仓库"已经好一截）。

CHANGELOG 单列一行 `libmpv manifest: mova-libmpv-v1`，今后每次换 tag 都要在 CHANGELOG 体现。

---

## Task 8（P1，先 spike 再决定要不要做）：Windows 自动下载可行性

**Files:** 新建 `C:\workspace\dart-labs\mova\doc\notes\2026-XX-XX-windows-auto-download-spike.md`
（**本 Task 只产出结论文档，不改构建文件**）

**要回答的三个问题：**

1. mova 自己的 `windows/CMakeLists.txt` 能否在官方 `media_kit_libs_windows_video` 之后，
   把输出目录里的 `libmpv-2.dll` 换成我们的？（Flutter Windows 的 bundled_libraries 是 install 阶段
   copy，理论上可以挂一个 `install(CODE ...)` 或 `add_custom_command(POST_BUILD)` 覆盖——**要实测**）
2. **链接期**用官方包的 `libmpv.dll.a` 去链，运行期换成我们的 `libmpv-2.dll`，ABI 是否兼容？
   （两边 pin 的 mpv commit 见清单的 `mpv_commit` 字段 `78d4374…`；如果官方包的 mpv 版本不同，
   这条路直接死，只能退回 fork 包方案 = 方向 B）
3. 若 1 或 2 不成立，是否存在"随包发一个自动生成 fork 包"的中间路线？（估计过于复杂，**倾向直接放弃
   Windows 自动下载，文档写清走方向 B**）

**产出：** 三个问题各一段结论 + 一个明确建议（做 / 不做）。**不做也是合格产出**，不要为了凑齐平台硬上。

---

## 风险清单

| # | 风险 | 缓解 / 结论 |
|---|---|---|
| 1 | **下游 CI/内网无外网，构建直接失败** | 这是默认关闭（决策 2）的**首要理由**。开了才会联网，且有 `MOVA_LIBMPV_LOCAL_DIR` 离线口子 + 错误信息明写三条出路。**接受** |
| 2 | **GitHub Release 被限流 / 国内访问慢或不通** | 提供 `MOVA_LIBMPV_BASE_URL` 镜像变量（用户可指向自己的内网 HTTP 服务或镜像站）；缓存命中后不再联网。**接受** |
| 3 | **mova-libmpv 停止维护 → 悬空链接** | Release 资产不随代码变动消失，只有整仓库删除才会断；且 `LOCAL_DIR` 路径永远可用。团队应在 README 明说"这是可选优化，官方 `media_kit_libs_video` 永远是默认且受支持的路径"。**接受** |
| 4 | **pub.dev 对"构建期下载二进制"的观感/审核** | 官方 `media_kit_libs_*` 自己就是这么干的（连本仓库 fork 包里保留的 ANGLE 下载都是 `file(DOWNLOAD)`），所以不是新范式；但我们额外做了三件事降低风险：默认关闭、sha256 强校验、清单随包锁定版本。**接受** |
| 5 | **sha256 清单与实际 Release 资产不同步**（发了 release 忘了回填清单） | Task 2 的验证步骤 4 明确要求回填；建议再加一条轻量保险：`test/tool/libmpv_manifest_test.dart` 断言 `release_tag` 不是 `*-unreleased`（发布前会红） |
| 6 | **`pickFirsts` 胜出的是官方那份而不是我们的**（静默用错二进制） | 这正是 Task 3/6 一律用 **sha256 比对 APK 内实际字节**、而不是看文件大小的原因。**必须照做** |
| 7 | **LGPL 合规**：分发二进制要附许可证与源码获取途径 | Task 2 的 "Ship LGPL compliance files" 步骤把 `BUILD-RECIPE.md` + `README-LICENSING.txt` 一并放进 Release。**落地时不得省略这一步** |
| 8 | **官方 media_kit 升级导致 ABI 漂移**（官方换了 mpv 版本，我们的 .so 对不上） | 清单里的 `mpv_commit` 是锚点；mova 升级 `media_kit` 依赖时，必须复核这个字段——写进 SPEC 的检查清单 |
| 9 | **Android 侧"两行配置"被用户漏掉一行**（只开开关没加 `pickFirsts`） | AGP 会报重复 `.so` 冲突（构建失败，不是静默），且 README 要把两行放在同一个代码块里不拆开。**接受** |
| 10 | **维护成本膨胀成"发布流水线"** | 这正是决策 6 只做 Android 的原因。每次发二进制就是手动 dispatch 一次 workflow + 回填一次清单，约 10 分钟人工，没有定时任务、没有自动 tag、没有额外服务 |

---

## 分期建议（明确结论）

**先只做 Android，跑通再说。** 具体是 **Task 1 → 2 → 3 → 4 → 5 → 6 → 7**，共 7 个 Task；
Task 8（Windows spike）作为独立后续，**不在本期承诺范围内**；iOS / macOS / Linux **本期完全不做**，
README 明写走手工方式（但受益于 Task 2，手工方式也从"clone 整个仓库"升级成"从 Release 下一个 10 MB 的包"，
这本身就是对全部平台生效的改善）。

**理由：**

1. **Android 是唯一已经有真机验证过接线路径的平台**，A2 在它身上只是把 `Copy` 的来源换掉，
   剩下的（`pickFirsts` 覆盖、jniLibs 注入、真机播放）都是已经走通过的老路；
2. **iOS 的 multi-dylib bundle 形态 + 从未接线 + 无 Mac 验证环境**，三个未知叠在一起，是另一个量级的
   工作量，不该和"验证 A2 这套机制本身行不行"混在一期；
3. **Task 2 的 Release 发布是全平台共享的收益**——哪怕别的平台永远只走手工，"从 Release 下一个包"也
   已经比"clone 一个带 LFS 的 monorepo"好太多，这是本期性价比最高的一个 Task；
4. **小团队维护**：7 个 Task 里真正有技术风险的只有 Task 3（注入路径是否稳定）和 Task 6（端到端），
   其余都是脚本 + 文档，一两个工作日能收口。

**如果只能做一个 Task：做 Task 2。** 单独把二进制发到 GitHub Release，就已经推翻了 README 里
「唯一获取渠道是 clone 仓库源码」这句最劝退的话，且零风险、不改任何下游行为。

---

## 附录 A：Task 6 实测结论（待填）

> 落地 agent 在 Task 6 完成后回填：APK 内 `.so` 的 sha256（开/关两态）、APK 体积差、
> 硬解 codec 名、真机型号与系统版本、测试时间。**不要写"目测通过"**——本项目的验证约定要求客观数字。
