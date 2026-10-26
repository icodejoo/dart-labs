# mova × mova-libmpv：瘦身 libmpv 走 GitHub Release 分发、mova 侧下载使用 —— 架构设计

**日期：** 2026-10-26
**状态：** 设计稿，待用户拍板（见第 10 节开放问题）。本文不改任何代码、workflow、pubspec。
**基线：** mova 0.3.1（已发布 pub.dev）；mova-libmpv 主配方 = WHEP 版（ffmpeg n9.0.2 + mpv v0.41.0），
正式构建 workflow 为 `.github/workflows/build-mova-libmpv-whep.yml`。

**一句话目标：** mova-libmpv 负责"构建 + 产出版本化的 GitHub Release"，mova 负责"按锁定版本下载这些产物并用起来"，
让 pub.dev 上的 mova 使用者不 clone 本仓库、不依赖 Git LFS，也能用上瘦身版 libmpv。

---

## 1. 现状核实（2026-10-26 实读）

### 1.1 Release 会发在哪

| 事实 | 证据 | 结论 |
|---|---|---|
| `origin` 的 fetch 是 codeup（阿里云效，ap-southeast-1），push 同时推 codeup 与 GitHub | `git remote -v` | 代码两边都有 |
| 所有 workflow 在 `.github/workflows/` 下，跑在 **GitHub Actions** | 两个 libmpv workflow 的注入步骤都是 `git push origin` 到 GitHub runner 的 checkout | CI 只存在于 GitHub 侧 |
| `icodejoo/dart-labs` 是 **PUBLIC** 仓库，目前 **0 个 tag、0 个 release** | `gh repo view` / `gh release list` / `git ls-remote --tags` | 新建 tag 前缀不会和任何现存东西冲突 |
| CI 注入的产物只推到 GitHub，codeup 端 LFS 对象长期缺失 | `mova/CLAUDE.md`「运维踩坑记录（2026-09-17）」 | LFS 不适合作为对外分发渠道 |

**结论：Release 发在 GitHub（`https://github.com/icodejoo/dart-labs/releases`）。** 理由：CI 只在 GitHub 上跑，
`gh release create` 用 runner 自带的 `GITHUB_TOKEN` 就能完成；公开仓库的 Release 资产匿名可下、不占 LFS 配额、
不受 codeup/GitHub 双端 LFS 同步问题影响。codeup 发行版没有 CI 可以写入，不作为主源；
是否另设镜像列为开放问题 Q9。

### 1.2 现在 libmpv 怎么到达应用（按使用者分）

| 使用者 / 平台 | 到达路径 | 状态 |
|---|---|---|
| **pub.dev 普通使用者（全平台）** | `mova` → `media_kit_libs_video` 伞包 → 官方各平台包在构建期自行下载官方二进制（Android 下 jar、Windows 下 7z、iOS/macOS 在 podspec 里 `make`+curl、Linux 用系统 libmpv） | 正常，默认路径，本设计不改变 |
| **monorepo example · Android** | `dependency_overrides` → `packages/media_kit_libs_android_video_slim_v041`（同名 fork），`android/src/main/jniLibs/{arm64-v8a,armeabi-v7a}/` 里放 `libmpv.so` + `libmediakitandroidhelper.so` | arm64 由 WHEP workflow 注入；**armeabi-v7a 是 2026-10-25 在 WSL 本地构建后手工提交的，CI 不产出**；两者都是 LFS + `.gitignore` 忽略后 `git add -f` |
| **monorepo example · Windows** | `dependency_overrides` → `packages/media_kit_libs_windows_video_slim`；其 CMake 从 `${CMAKE_SOURCE_DIR}/../../libmpv/windows-x86_64-whep/` 取 `libmpv-2.dll`+`libmpv.dll.a`，头文件取包内 `mpv-headers/`；ANGLE 构建期下载并校验 sha256 | 已真机验证（2026-10-25）。**头文件仍是旧 pin 78d4374，DLL 是 v0.41.0**（已知风险） |
| **monorepo example · iOS/macOS** | 未 override，走官方 | `_ios_video_slim`/`_macos_video_slim` 只是结构，未验证；且只有旧 n6 movaslim 产物，WHEP 配方没有 Darwin 构建 |
| **monorepo example · Linux** | 系统 libmpv | WHEP workflow 只上传 artifact，不注入 |
| **外部使用者照 README 做 git override** | README「进阶」一节 | **基本不可用或已过时**，见下 |

README「进阶：接入自研瘦身版 libmpv」现存问题（这也是本设计要解决的痛点）：

1. Android 一节仍指向旧 n6 包 `media_kit_libs_android_video_slim`，不是 v041。
2. Windows 一节说 fork 包"自带 `windows/libmpv-2.dll`、完全自包含"——该 DLL 已于 2026-10-25 `git rm`，
   CMake 改为按 monorepo 相对路径找 `mova/libmpv/...`。外部 app 用 git override 时，`CMAKE_SOURCE_DIR` 是
   **使用者自己的** `windows/`，插件目录又是 `.plugin_symlinks` 链接（2026-10-25 笔记已记录 `..` 推导不可靠），
   **高概率直接 FATAL**（推断，未实测）。
3. 两个平台的二进制都在 LFS 里。pub 缓存 git 依赖时能否拿到真实内容，取决于使用者机器的 git-lfs 全局配置，
   而且 LFS 带宽额度是仓库所有者的；**没有任何环节保证外部使用者拿到的是真二进制而不是 132 字节的指针**
   （本机检出的 `mova/libmpv/*` 大部分就是指针）。

### 1.3 两份早期方案做到哪一步、哪些已过时

| 方案 | 当时结论 | 实际进展 | 已过时的部分 | 仍有价值的部分 |
|---|---|---|---|---|
| `2026-09-25-libmpv-auto-download.md`（A2：构建期自动下载） | GitHub Release + 随包清单 + 默认关闭 + fail-loud | **未开工，用户当时否决**（理由：内网构建不应依赖联网下载） | 产物清单（n6 四 ABI、mpv 78d4374）；以 `build-mova-libmpv.yml` 为主 workflow（现在仅手动）；Android 接线用 `syncMovaLibmpv`+`pickFirsts`（已被同名 fork 取代）；`C:\workspace` 路径 | Release 优于 LFS 的论证；清单锁死 tag+sha256；按 tag 缓存；sha256 失配绝不降级；LGPL 随 Release 附说明 |
| `2026-09-25-libmpv-pub-package.md`（C：二进制进 pub 包） | 拆平台包发 pub.dev + LGPL 四件套 | **以另一种形式部分落地**：同名 fork + `dependency_overrides`（Android/Windows 已验证，iOS/macOS 仅结构）；**pub.dev 发布与四件套用户已放弃** | 尺寸与 ABI 数据（n6）；Windows CMake 路径（已改）；"Windows 本期已拿到最好结果"的判断（git override 已不自包含）；README 改写要点 | 决策 0（Android 只有"共存+pickFirst"与"同名独占"两种拓扑）；决策 2（默认不反转，瘦身版 opt-in）；决策 4（切换开关的思路） |

**2026-10-25 之后的新事实（两份方案都没覆盖）：**

- 正式配方换成 WHEP/v041：Android arm64-v8a 6,354,048 B、armeabi-v7a 5,702,540 B；Windows `libmpv-2.dll` 10,876,416 B。
- 正式 workflow 是 `build-mova-libmpv-whep.yml`：只构建 Android **arm64**、Windows x64、Linux（仅 artifact）；
  **不构建 armeabi-v7a，也不构建 iOS/macOS**；有 `concurrency: cancel-in-progress: true`。
- Android x86/x86_64 在 v041 里已不提供（模拟器上用 v041 包会缺 libmpv）。
- Windows 需要的不只是 DLL：链接期还要 `libmpv.dll.a` 与匹配版本的头文件，三者必须同源。

---

## 2. 设计约束（从历史决策继承，不重新讨论）

1. **默认行为不变**：mova 继续依赖 `media_kit_libs_video`，瘦身版是使用者主动 opt-in（pub-package 方案决策 2）。
2. **替换机制沿用"同名 fork + dependency_overrides"**：这是 pub 生态里唯一能让官方包完全退出依赖图、
   不需要 pickFirst 的方法（决策 0）。pub 没有其他替换传递依赖的手段，所以使用者**至少要写一次 override**，这一点任何方案都绕不开。
3. **sha256 失配绝不降级**；"静默用错二进制"是这条线上被坑过的故障形态。
4. **不引入未经同意的第三方依赖**；不在 SDK 运行时打广告日志。
5. 用户曾明确"内网构建环境不应依赖联网下载"——本次要求"下载"，说明可以接受网络，但**构建本身能否离线**仍是重要评价维度。

---

## 3. 核心分歧：下载发生在什么时候

三个候选，外加一个远期备选：

- **方案 A：构建期自动下载。** 同名 fork 包的 Gradle task / CMake 配置期 / podspec 求值时，按锁文件联网拉产物、校验、缓存。
- **方案 B：首次运行时下载。** App 安装后首次启动从 Release 下 `.so/.dll` 到私有目录再动态加载。
- **方案 C：使用者显式命令预取 + 构建期只读缓存。** 使用者执行 `dart run mova:fetch_libmpv`，
  下载到用户级缓存并校验；fork 包的构建脚本只从缓存（或显式目录）取文件、再校验一次，**构建过程不联网**，缺失就 fail 并给出命令。
- （远期备选 D：mova 直接依赖自己的 provider 包，反转默认。技术上最干净，但就是 pub-package 方案决策 2 否掉的方向，本期不展开。）

### 3.1 各平台可行性

| 平台 | A 构建期下载 | B 运行时下载 | C 显式预取 + 构建读缓存 |
|---|---|---|---|
| **Android** | 可行。fork 包本身就是唯一提供方，`jniLibs.srcDirs` 指向缓存目录即可，无需 pickFirst | **不可行**：①从自有服务器下载可执行原生代码违反 Google Play「设备和网络滥用」政策；②`AndroidHelper` 按裸 soname 打开 `libmpv.so`，需要先 `System.load` 绝对路径，改动侵入 media_kit 初始化；③首次启动离线 = 播放器不可用 | 可行，同 A，只是下载步骤前移到命令 |
| **Windows** | 可行。CMake 配置期 `file(DOWNLOAD)`+`file(SHA256)`，fork 包已有现成的 `download_and_verify()`（ANGLE 在用） | **不可行**：`media_kit_video` 的插件 DLL 在链接期链 `libmpv.dll.a`，是**加载期导入**；`libmpv-2.dll` 不在 exe 旁边进程直接起不来，没有"先启动再下载"的机会 | 可行。CMake 只读缓存，`bundled_libraries` 把 DLL 放到 exe 旁 |
| **iOS** | 可行（官方包就是在 podspec 求值时 `system("make")` 下载）。注意：现有 slim podspec 用的 `prepare_command` 对 `:path` 形式的开发 pod **不执行**（CocoaPods 文档所述，Flutter 插件都是 `:path` pod，未在本仓库实测），应改为 podspec 内直接执行 Ruby 逻辑 | **不可行**：App Store 审核指南 2.5.2 禁止下载可执行代码；iOS 也不允许 dlopen 未随包签名的 dylib | 可行。podspec 求值时从缓存拷进 `Frameworks/`，随 app 一起签名；动态 framework 在 App Store 合规 |
| **macOS** | 可行，同 iOS | 基本不可行：Hardened Runtime 的库校验拒绝加载签名不一致的 dylib，除非开 `disable-library-validation` 权限，且公证分发不鼓励 | 可行，同 iOS |
| **Linux** | 无位置可占（libmpv 来自系统 pkg-config） | 无位置可占 | 无位置可占；Release 可附 Linux 产物供进阶使用者自理（Q5） |

方案 B 在四个有意义的平台上都被硬约束挡住，**直接否决**，下文只比较 A 与 C。

### 3.2 A 与 C 的全面对比

| 维度 | A 构建期自动下载 | C 显式预取 + 构建读缓存（推荐） |
|---|---|---|
| 使用者操作 | 写 override + 设开关（建议默认关、显式开） | 写 override + 跑一次 `dart run mova:fetch_libmpv` |
| 构建是否联网 | 缓存未命中时联网；内网 CI 直接挂 | **永不联网**；联网只发生在一个独立、可在别的机器上执行的命令里 |
| 实现位置 | Gradle(Groovy/Kotlin) + CMake + Ruby 三套下载/解压/重试/镜像逻辑 | **下载只有一套 Dart 实现**；三个构建脚本只做"定位 + sha256 校验"，逻辑小 |
| 慢网/断点续传 | Gradle/CMake 内置下载是单连接、无续传；要做好得三处各写一遍 | Dart 工具里统一做：`.part` + HTTP Range 续传；检测到 `aria2c` 时用多连接（`-x16 -s16 --continue`）；多个 base URL 依次故障转移 |
| 离线/内网 | 需额外 `LOCAL_DIR` 口子 | 天然支持：`--from-dir` 从拷来的目录导入；或在有网机器跑完后整体拷缓存目录 |
| CI 友好 | 缓存目录要配进 CI cache；首次构建慢 | CI 先跑 fetch（key = 锁文件里的 tag），再构建；失败点清晰分离 |
| 版本锁定 | 锁文件 → 构建脚本 | 锁文件 → 工具与构建脚本**同读一份**；构建期再校验一次，命令跑过旧版本也会被发现 |
| 失败表现 | 构建中途网络错误，信息混在 Gradle/CMake 日志里 | 构建期只有一种失败："缓存里没有/不匹配"，报错直接给出要跑的命令 |
| 和"内网构建不联网"原则 | 冲突（需要开关兜底） | 一致 |
| 遗忘风险 | 低（自动） | 中：忘跑命令会构建失败（fail-loud，不会静默用错）；后续可加可选的"构建期自动调用同一工具"（Q1） |
| 对 pub 包影响 | mova 包内多一个锁文件 | mova 包内多一个锁文件 + 一个纯 Dart `bin/` 脚本（KB 级） |
| 实现成本 | 中高（三套下载） | 中（一套下载 + 三套轻量读取） |

**判断：C 更好。** A 唯一的优势是"少跑一个命令"，代价是三套下载逻辑和构建联网；C 把网络隔离到一个独立步骤，
正好对上本仓库已经吃过亏的两件事（单连接慢、内网构建）。A 的便利性可以在 C 之上以"可选自动触发同一个 Dart 工具"
的方式补回来（构建脚本通过 `FLUTTER_ROOT` 找到 `dart` 调 `fetch_libmpv`），不必再写第二套下载。

---

## 4. 推荐方案：C（显式预取 + 构建期只读缓存）

### 4.1 整体数据流

```
mova-libmpv 配方 ──(build-mova-libmpv-whep.yml)──> workflow artifacts（30 天）
                                                      │  人工/真机验证通过后
                                                      ▼
                            release-mova-libmpv.yml（按 run_id 晋升）
                                                      │
                                                      ▼
        GitHub Release  mova-libmpv-r<N>：各平台 tar.gz + manifest.json + SHA256SUMS + 合规文件
                                                      │
    mova（pub 包）tool/libmpv.lock.json 钉死 tag + 每个资产的 sha256
                                                      │
        使用者：dart run mova:fetch_libmpv  ──下载/续传/校验──>  用户级缓存 <MOVA_LIBMPV_HOME>/<tag>/<asset-key>/
                                                      │
        同名 fork 包（git override，包内不再含二进制）构建期：定位 mova 锁文件 → 定位缓存 → sha256 校验 → 交给 AGP/CMake/CocoaPods
```

### 4.2 版本对应与锁定

- **锁文件放在 mova 包里**：`mova/tool/libmpv.lock.json`，随 pub 包发布（`.pubignore` 的 `libmpv/` 只匹配目录，不影响这个文件；
  落地时加单测断言 dry-run 文件清单含它）。于是 **mova 版本 ↔ Release tag 一对一**：mova 0.4.0 锁 `mova-libmpv-r1`，
  装了 0.4.0 的人永远拿到同一批字节。另一种放法（放在 fork 包里、由 git ref 决定）见 Q2。
- **换 tag 规则**：锁文件 tag 变化 ⇒ mova 至少 minor 版本号上升，CHANGELOG 单列一行 `libmpv: mova-libmpv-rN`。
- **fork 包如何找到锁文件**：读使用者 app 的 `.dart_tool/package_config.json`（pub 必定生成，含所有包的 rootUri，
  不受 mova 声明了哪些平台影响；兼容 pub workspace 时向上找）。Gradle 从 `rootProject.projectDir/..`、CMake 从
  `${CMAKE_SOURCE_DIR}/..`、podspec 从 `ios/`（或 `macos/`）的上一级出发。
- **锁文件内容**是 Release `manifest.json` 的子集（tag、base_urls、每个资产的文件名/大小/sha256/内含文件 sha256）。
  校验以**锁文件**为准，Release 上的 manifest 只用于生成锁文件和人工核对；即使有人替换了 Release 资产，sha 也对不上锁文件。
- **兼容性锚点**：manifest 记录 `ffmpeg`/`mpv` 版本、配方 commit、以及验证过的 `media_kit`/`media_kit_video` 版本区间；
  mova 升级 media_kit 依赖时要复核这一项（写进 SPEC 检查清单）。

### 4.3 下载工具 `dart run mova:fetch_libmpv`

```
dart run mova:fetch_libmpv
    [--platform android,windows]          # 默认：按当前 app 存在的平台目录推断
    [--abi arm64-v8a,armeabi-v7a]         # Android 子集
    [--cache-dir <dir>]                   # 覆盖 MOVA_LIBMPV_HOME
    [--base-url <url>]...                 # 镜像，可多个，依次故障转移；也读 MOVA_LIBMPV_BASE_URLS
    [--from-dir <dir>]                    # 离线导入：从手工下载的资产目录导入（仍校验）
    [--downloader auto|aria2|dart]        # auto = PATH 上有 aria2c 就用
    [--verify-only] [--print-path]
```

- 位置：`mova/bin/fetch_libmpv.dart`，纯 `dart:io`，**不得 import flutter**（否则 `dart run` 跑不起来）。
- 缓存根 `MOVA_LIBMPV_HOME` 默认：Windows `%LOCALAPPDATA%\mova\libmpv`，macOS `~/Library/Caches/mova/libmpv`，
  Linux `${XDG_CACHE_HOME:-~/.cache}/mova/libmpv`。布局 `<home>/<tag>/<asset-key>/<文件>` + `.verified`（写入归档 sha256）。
  三个构建脚本用同一套规则计算路径（Gradle 要实现三种宿主 OS；CMake 只需 Windows；podspec 只需 macOS）。
- 下载：先写 `.part`，Dart 实现用 HTTP Range 续传；aria2 模式参数 `-x16 -s16 -k1M --continue=true --max-tries=0`，
  多个 base URL 一起传给 aria2 让它自己切换。资产都在 6–11 MB 量级，单连接 0.2–0.6 MB/s 下约 20–60 秒，aria2 是加速项不是必需项。
  直接拼 `releases/download/<tag>/<file>` URL，**不调 GitHub API**（避开匿名 60 次/小时限流）。
- 校验：归档 sha256 → 解压 → 内含文件 sha256 → 写 `.verified`；任一步失配就删掉并报错，**不重试成功前不留半成品**。
- sha256 与解压的实现方式涉及依赖选择（`crypto`/`archive` 已是 mova 的**传递**依赖，升为直接依赖仍需同意；
  或调系统 `tar`/`certutil`/`shasum`），见 Q8。

### 4.4 各平台 fork 包怎么改（落地时做，本文只定形状）

**共同规则（构建期）：** 解析锁文件 → 计算缓存目录 → 若设置了 `MOVA_LIBMPV_DIR` 则改用该目录 →
对用到的每个文件做 sha256，与锁文件比对 → 不一致或缺失则失败，报错包含三条出路：
① 运行 `dart run mova:fetch_libmpv`；② 设 `MOVA_LIBMPV_DIR` 指向手工目录；③ 删掉 `dependency_overrides` 回到官方。
`MOVA_LIBMPV_SKIP_VERIFY=1` 只对 `MOVA_LIBMPV_DIR` 生效（给自己编 libmpv 的人用，也是 LGPL 可替换性的实际路径），
对缓存目录永远强制校验。构建日志打印一行身份：`[mova-libmpv] mova-libmpv-r1 (mpv v0.41.0, ffmpeg n9.0.2) android arm64-v8a`。

| 平台 | 包 | 改动要点 |
|---|---|---|
| Android | `media_kit_libs_android_video_slim_v041` | `build.gradle` 增加：配置期定位 + 校验，`android.sourceSets.main.jniLibs.srcDirs` 指向缓存里的 `android-<abi>-whep/` 目录；删除包内 `jniLibs/**/*.so`。缓存里每个 ABI 目录含 `libmpv.so` + `libmediakitandroidhelper.so`。只提供 arm64-v8a/armeabi-v7a，README 写明使用者需 `abiFilters` 限定这两个，否则 x86_64 模拟器上缺库 |
| Windows | `media_kit_libs_windows_video_slim` | CMake 候选目录变成：`MOVA_LIBMPV_DIR` → 缓存 `windows-x86_64-whep/` → monorepo 相对路径（过渡期保留给 example）；`file(SHA256)` 校验；头文件改取资产里的 `include/mpv/*.h`（v0.41.0），删除包内旧 `mpv-headers/`；ANGLE 逻辑不动 |
| iOS / macOS | `_ios_video_slim` / `_macos_video_slim` | 远期（阶段 8）：资产直接是打好的 `Mpv.xcframework`（CI 在 macOS runner 上用 `install_name_tool`/`lipo` 产出，解决当前"Windows 上手工拼装、未验证"的问题）；podspec 求值时从缓存拷入 `Frameworks/`，不用 `prepare_command` |
| Linux | 无 | 不做接入；Release 是否附产物见 Q5 |

### 4.5 失败与回退

- 默认 **fail-loud**：fork 包是同名唯一提供方，拿不到瘦身版时它没有"官方二进制"可退，静默继续只会得到一个缺 libmpv 的 app。
- 回退到官方 `media_kit_libs_video` = 删除 `dependency_overrides`，零残留，这是唯一推荐的回退方式。
- 可选增强（Q10）：在 fork 包里复刻官方包的下载逻辑（官方 URL+md5，MIT），由 `MOVA_LIBMPV_FALLBACK=official` 显式开启，
  实现"不改 pubspec 临时切回官方"。成本是要跟踪官方包版本变化，默认不做。

### 4.6 对现有 dependency_overrides / 本地包的处理

| 对象 | 处理 |
|---|---|
| `example/pubspec.yaml` 的两个 override | 保留（仍指向本地 path）。example 改为**和外部使用者走同一条路**（先 fetch 再构建）来"吃自己的狗粮"；过渡期 Windows 保留 monorepo 相对路径兜底 |
| `media_kit_libs_android_video_slim_v041` | 变"瘦"：只剩 Java 胶水 + `build.gradle` 读缓存逻辑，不含二进制 → git override 不再依赖 LFS |
| `media_kit_libs_windows_video_slim` | 同上，去掉 `mpv-headers/` |
| 旧 n6 包 `media_kit_libs_android_video_slim` | r1 验证通过后可删除（git 历史可找回），见 Q6 |
| `mova/libmpv/*`（CI 注入目录，大多是 LFS 指针） | 过渡期保留；CI 停止回写后删除，见 Q6 |
| ios/macos slim 包 | 阶段 8 前不动 |
| README「进阶」一节 | 阶段 6 整节重写：override 指向 tag 而不是 `main`，加 fetch 步骤、缓存/CI/离线说明、能力裁剪说明、ABI 限制 |

### 4.7 pub 包体积与 pub.dev 政策

- mova 包只新增一个几 KB 的锁文件和一个 Dart 脚本，二进制仍不进包，体积不变（`.pubignore` 继续排除 `libmpv/`、`packages/`）。
- pub.dev 不限制"构建期/命令行下载原生库"，`media_kit_libs_*` 官方包就是构建期下载；本方案连构建期都不下，风险更低。
- `bin/` 下的脚本不需要在 pubspec 声明 `executables`，`dart run mova:fetch_libmpv` 对任何依赖了 mova 的项目可用。
- **LGPL**：本文不下法律结论。但公开 Release 就是向公众分发 LGPL 二进制（严格说，当前公开仓库里的 LFS 二进制也已经是），
  建议每个 Release 附 `NOTICE.md`（组件、版本、协议）、`LICENSES/`（LGPL-2.1、GPL-2.0 文本）、`SOURCE.md`
  （配方 commit、上游源码 tag、补丁列表、构建入口）。这些都能从配方自动生成，成本低，见 Q11。

---

## 5. Release 产物规范

### 5.1 Tag 命名

- 推荐：`mova-libmpv-r<N>`，`N` 单调递增整数（`r1`、`r2`…），与 mova 包版本解耦，ffmpeg/mpv 版本写在 manifest 与 Release 说明里。
  前缀 `mova-libmpv-` 避免和 monorepo 其他子工程将来的 tag 冲突；不用 `/`、`+`，下载 URL 不需要转义。
- 备选：`mova-libmpv-mpv0.41.0-ff9.0.2-r<N>`，tag 自描述但长（Q3）。
- **不可变**：同一 tag 资产发出后不得替换；有问题就发 `r<N+1>`。workflow 遇到已存在的 tag 直接失败；
  如 GitHub 仓库设置里提供"不可变 Release"选项可一并开启（Q14）。
- tag 指向**配方 commit**（构建 run 的 `head_sha`），不是 CI 注入产物的 `[skip ci]` commit。
- tag 只建在 GitHub 上，codeup 不会自动有；本设计不依赖 codeup 上的 tag。

### 5.2 资产命名与内容

格式：`mova-libmpv-<tag-N>-<os>-<arch>-<flavor>.tar.gz`，统一 tar.gz（保留符号链接，Apple framework 也能用；
Windows 10 自带 `tar.exe`，CMake `-E tar`、Gradle `tarTree` 都能解）。打包用确定性参数
（`--sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner`，`gzip -n`），同一批文件重打包 sha256 不变。

| asset-key | 文件名示例 | 归档内容 | 首批 |
|---|---|---|---|
| `android-arm64-v8a-whep` | `mova-libmpv-r1-android-arm64-v8a-whep.tar.gz` | `libmpv.so`、`libmediakitandroidhelper.so` | ✅ |
| `android-armeabi-v7a-whep` | `mova-libmpv-r1-android-armeabi-v7a-whep.tar.gz` | 同上 | ✅（需先让 CI 构建 v7a） |
| `windows-x86_64-whep` | `mova-libmpv-r1-windows-x86_64-whep.tar.gz` | `libmpv-2.dll`、`libmpv.dll.a`、`libmpv-2.def`、`include/mpv/{client,render,render_gl,stream_cb}.h` | ✅ |
| `linux-x86_64-whep` | `mova-libmpv-r1-linux-x86_64-whep.tar.gz` | `libmpv.so` | Q5 |
| `ios-arm64-whep` / `macos-universal-whep` | `…-ios-arm64-whep.tar.gz` | `Mpv.xcframework/` | 阶段 8 |

另附：`manifest.json`、`SHA256SUMS`（`sha256sum` 标准格式，覆盖所有 tar.gz，可 `sha256sum -c`）、`NOTICE.md`、`LICENSES.tar.gz`、`SOURCE.md`。

`libmediakitandroidhelper.so` 是 media_kit 官方 MIT JNI 小库，和 ffmpeg/mpv 版本无关。放进我们的 Release 可以让使用者只依赖一个下载源；
CI 获取它的方式建议改为"从官方 release jar 下载 + 校验 md5 后提取"，不再从 LFS 里的旧包拷（Q12）。

### 5.3 `manifest.json` 格式（schema 1）

```json
{
  "schema": 1,
  "tag": "mova-libmpv-r1",
  "created_at": "2026-11-01T00:00:00Z",
  "recipe": {
    "commit": "<dart-labs 配方 commit sha>",
    "workflow_run": "https://github.com/icodejoo/dart-labs/actions/runs/<run_id>",
    "flavor": "whep",
    "ffmpeg": "n9.0.2",
    "mpv": "v0.41.0"
  },
  "compat": { "media_kit": ">=1.2.6 <1.3.0", "media_kit_video": ">=2.0.1 <2.1.0" },
  "assets": {
    "android-arm64-v8a-whep": {
      "file": "mova-libmpv-r1-android-arm64-v8a-whep.tar.gz",
      "size": 0,
      "sha256": "<64 位小写 hex>",
      "contents": {
        "libmpv.so": { "size": 6354048, "sha256": "<hex>" },
        "libmediakitandroidhelper.so": { "size": 386696, "sha256": "<hex>" }
      }
    }
  }
}
```

mova 的 `tool/libmpv.lock.json` = 上面的子集 + `base_urls`（默认只有
`https://github.com/icodejoo/dart-labs/releases/download/<tag>`）。锁文件由 monorepo 内的生成脚本从 Release 的 manifest
生成，不手写（谁来跑、是否由 workflow 自动提交，见 Q4）。

---

## 6. CI 改造要点（只列要点，不改文件）

### 6.1 `build-mova-libmpv-whep.yml`（产出可发布的 artifact）

1. Android job 改成 `matrix.abi: [arm64-v8a, armeabi-v7a]`，v7a 用现成的 `e2e-armv7.sh`（`ARCH=armv7l`）；
   缓存键、产物文件名、符号检查都按 ABI 参数化；`check-symbols-android.sh` 里 `dav1d_open` 的旧判据需同步更新（2026-10-25 笔记已指出）。
2. 每个 Android artifact 同时带上该 ABI 的 `libmediakitandroidhelper.so` 和 `build-info.json`（ffmpeg/mpv 版本、文件 sha256、run 信息）。
   helper 的来源改为官方 jar（见 5.2），去掉对 LFS 旧包的依赖。
3. Windows artifact 追加 mpv v0.41.0 源码树里的 `include/mpv/*.h` 与 `build-info.json`（当前构建脚本不产出头文件，要在 stage 步骤补拷贝）。
4. artifact 命名固定为 `mova-libmpv-<asset-key>`，与 5.2 的 asset-key 一致，晋升 workflow 按名取。
5. `concurrency.cancel-in-progress: true` 会取消准备晋升的 run：晋升前确认 run 是 success；或者手动 dispatch 用单独的 concurrency 组（实现时二选一）。
6. 回写仓库的注入步骤**过渡期保留**（example 仍可用），阶段 7 再决定是否删除（Q6）。

### 6.2 新增 `release-mova-libmpv.yml`（按 run_id 晋升，推荐）

- 触发：仅 `workflow_dispatch`，输入 `run_id`（必填）、`tag`（必填，校验 `^mova-libmpv-r[0-9]+$`）、
  `assets`（默认 `android-arm64-v8a-whep,android-armeabi-v7a-whep,windows-x86_64-whep`）、`draft`（默认 true）。
- 权限：`contents: write`、`actions: read`。
- 步骤要点：
  1. `gh run view <run_id>` 确认来自 `build-mova-libmpv-whep.yml` 且 `conclusion == success`，取 `headSha`；
  2. `gh release view <tag>` 若存在则失败（不可变）；
  3. `actions/download-artifact@v4` 带 `run-id` + `github-token` 拉指定 artifact，缺任一个即失败；
  4. 确定性打包 → 生成 `manifest.json`（python3/jq，runner 自带）→ `SHA256SUMS`；
  5. 由配方生成 `NOTICE.md`/`SOURCE.md`，附 `LICENSES`；
  6. `gh release create <tag> --target <headSha> --draft --title ... --notes-file ...` 上传全部资产；
  7. 自检：`gh release download` 到全新目录，`sha256sum -c SHA256SUMS` 必须全过，并把 manifest 写进 job summary；
  8. `draft=false` 时才转正；推荐保持 draft，真机验证完人工点"Publish"。
- 为什么独立成"晋升"而不是在构建 workflow 里加 `release_tag` 输入（2026-09-25 方案的做法）：
  发出去的字节 = 真机验证过的字节，不会因为"重新构建一次再发"引入差异；构建 workflow 也保持单一职责（Q4）。

### 6.3 `build-mova-libmpv.yml`（旧 n6 配方）

不动，不参与 Release。

---

## 7. 分阶段落地（每步小而可验证）

| 阶段 | 内容 | 验收（客观证据） | 依赖 |
|---|---|---|---|
| **0** | 用户就第 10 节开放问题拍板 | 本文档更新为"已决策"版 | — |
| **1.1** | WHEP workflow：Android 加 armeabi-v7a 矩阵 | 一次 `platform=android` dispatch 产出两个 artifact，两 ABI 符号检查全过；v7a 体积与本地 5,702,540 B 同量级 | 0 |
| **1.2** | artifact 补齐 helper / 头文件 / `build-info.json`，命名对齐 asset-key | 下载 artifact，文件清单与 5.2 表一致；helper sha 与官方 jar 提取值一致 | 1.1 |
| **2.1** | 新建晋升 workflow，对 1.2 的 run 发 draft `mova-libmpv-r1` | draft 上资产齐全；workflow 自检 `sha256sum -c` 全过；对同一 tag 再跑一次被拒绝 | 1.2 |
| **2.2** | 合规文件随 Release | Release 资产含 `NOTICE.md`/`LICENSES.tar.gz`/`SOURCE.md`，`SOURCE.md` 中 commit 可在 GitHub 打开 | 2.1 |
| **2.3** | 用 Release 字节做实机验证后转正 | Android arm64 真机（STG-AL00）+ Windows 本机播放通过，APK 内 / exe 旁的文件 sha256 = manifest 值；记录数字后 Publish | 2.2 |
| **3.1** | mova 新增 `tool/libmpv.lock.json` + 生成脚本 + schema 单测 | 单测绿；`flutter pub publish --dry-run` 清单含锁文件；锁内 sha 与 Release manifest 一致 | 2.3 |
| **3.2** | `bin/fetch_libmpv.dart` + 单测（参数解析、缓存路径、校验失败清理、续传、多源故障转移、`--from-dir`） | 在 example 执行：缓存生成、再次执行零下载；断网 + `--from-dir` 成功；改坏一个字节报错且无残留；有 aria2 时走 aria2 | 3.1（Q8 决定依赖方式） |
| **4** | Android v041 包改读缓存，删包内 `.so` | example `flutter build apk --target-platform android-arm,android-arm64`：APK 内两 ABI 的 `libmpv.so` sha256 = 锁文件；清空缓存后构建失败且报错含 fetch 命令；真机起播 | 3.2 |
| **5** | Windows 包改读缓存 + v0.41.0 头文件 | `flutter build windows` 通过，exe 旁 `libmpv-2.dll` sha256 = 锁文件；播放出画；清缓存构建失败且报错含命令 | 3.2 |
| **6** | 仓库外干净 Flutter 工程端到端：依赖 mova（path 指向 dry-run 解包内容）+ git override（`ref: <tag>`）+ fetch；改写 README/CHANGELOG | Android 与 Windows 都构建运行成功；该工程机器上**没有 git-lfs** 也成功（证明不再依赖 LFS）；发版时机由用户决定 | 4、5 |
| **7（可选）** | 停止 CI 回写二进制；删除 `mova/libmpv/*` 与旧 n6 包 | 全新 clone 后 example 仍可按 fetch 流程构建 | 6、Q6 |
| **8（远期）** | iOS/macOS：WHEP 配方的 Darwin CI、xcframework 资产、podspec 读缓存、Mac 实机验证 | `pod install` + 真机/实机播放；与 iOS PiP 共用 Mac 门槛 | Mac 环境 |

**如果只做一步：做到 2.3。** 单独把经过实机验证的二进制发成带 sha256 的 Release，就已经把"只能 clone 仓库/依赖 LFS"
换成了"一个可校验的下载链接"，且不改任何使用者行为。

---

## 8. 风险

| # | 风险 | 应对 |
|---|---|---|
| 1 | 使用者忘跑 fetch，构建失败 | fail-loud + 报错给出完整命令；README 把 override 与 fetch 写在同一个代码块；后续可加可选自动触发（Q1） |
| 2 | GitHub 在使用者所在网络慢/不通 | `--base-url` 多源 + aria2；`--from-dir` 离线导入；缓存命中后不再联网 |
| 3 | 锁文件与 Release 不一致（发了忘更新） | 锁文件由脚本从 manifest 生成；单测断言锁内 tag 不是占位值；阶段 3.1 验收要求逐项比对 |
| 4 | artifact 过期（30 天）来不及晋升 | 过期就重新构建再验证；晋升 workflow 对缺失 artifact 直接失败 |
| 5 | Windows 头文件与 DLL 版本不一致（现状就是如此） | 头文件进资产，与 DLL 同源；fork 包不再自带头文件 |
| 6 | Android 只有 arm64/v7a，x86_64 模拟器缺库 | README 写明 `abiFilters`；是否补 x86_64 见 Q5 |
| 7 | fork 包定位 `.dart_tool/package_config.json` 在某些布局（pub workspace、自定义目录）下失败 | 向上逐级查找；仍失败时提示设置 `MOVA_LIBMPV_DIR`；阶段 6 用仓库外工程实测 |
| 8 | iOS slim podspec 的 `prepare_command` 对 `:path` pod 不执行（据 CocoaPods 文档） | 阶段 8 改为 podspec 内直接执行；在此之前 README 不推荐 iOS/macOS override |
| 9 | 公开分发 LGPL 二进制的合规义务 | 随 Release 附 NOTICE/LICENSES/SOURCE（Q11），具体法律判断由用户决定 |
| 10 | 维护成本 | 日常 = 构建 → 实机验证 → 手动 dispatch 晋升 → 跑生成脚本更新锁文件 → mova 发版；无定时任务、无额外服务 |

---

## 9. 被否决的路线（简记）

| 路线 | 否决原因 |
|---|---|
| B 运行时下载 | Play 政策、App Store 2.5.2、Windows 加载期导入，三条硬约束（3.1） |
| 继续用 LFS + git override 分发 | 外部使用者拿到真二进制无保证；LFS 带宽算在仓库所有者头上；codeup/GitHub 双端不同步 |
| 二进制进 pub 包 | 用户已放弃；pub 无条件依赖，所有人为所有平台付流量 |
| mova 自己的 Gradle/CMake 覆盖官方二进制（共存 + pickFirst） | pickFirst 只能写在 app 模块，插件无法代劳；2026-09-25 两份方案已论证 |

---

## 10. 需要用户拍板的开放问题

> 每题标出推荐项，但最终由用户决定。

**Q1 下载时机**
- (a) **C：显式命令 + 构建只读缓存**（推荐）
- (b) A：构建期自动下载（默认关、显式开）
- (c) C 为主，后续再加"缓存缺失时构建脚本自动调用同一个 Dart 工具"的开关

**Q2 锁文件放哪**
- (a) **mova 包内 `tool/libmpv.lock.json`**，mova 版本 ↔ tag 一对一（推荐）
- (b) fork 包内，由使用者 override 的 git ref 决定版本，与 mova 版本无关

**Q3 tag 命名**
- (a) **`mova-libmpv-r<N>`**（推荐）
- (b) `mova-libmpv-mpv0.41.0-ff9.0.2-r<N>`
- (c) 其他

**Q4 发布触发与锁文件更新**
- 触发：(a) **独立晋升 workflow，按已验证的 run_id 发布**（推荐）；(b) 构建 workflow 加 `release_tag` 输入，构建完直接发
- 默认发 draft，人工 Publish？(是 / 否)
- 锁文件更新：(i) **人工跑生成脚本后提交**（推荐，和 mova 发版节奏一起）；(ii) 晋升 workflow 自动提交到 main

**Q5 首批平台**
- (a) **Android arm64-v8a + armeabi-v7a + Windows x86_64**（推荐）
- (b) 再加 Android x86_64（模拟器用，需要 CI 增加构建）
- (c) 再加 Linux x86_64，作为"不提供接入、仅供自理"的实验资产

**Q6 仓库里的二进制怎么处理**
- CI 回写：(a) **过渡期保留，阶段 7 停止**（推荐）；(b) 立即停止；(c) 永久保留
- 旧 n6 包与 `mova/libmpv/` 下旧目录：(a) **r1 实机验证通过后删除**（推荐）；(b) 继续留作回退

**Q7 缓存位置**
- (a) **用户级全局缓存**（推荐，多项目共享，CI 好配）
- (b) 项目内 `.mova/libmpv/`（可以提交进使用者自己的仓库，方便纯内网团队）
- (c) 默认 (a)，同时支持 (b)

**Q8 fetch 工具的 sha256 与解压实现**（涉及依赖，必须由用户同意）
- (a) 把 `crypto` 与 `archive`（目前已是 mova 的传递依赖）升为直接依赖
- (b) 零新依赖：调系统命令（`tar`；`certutil` / `shasum` / `sha256sum`）
- (c) 只升 `crypto`，解压用系统 `tar`

**Q9 镜像**
- (a) **只用 GitHub Release**（推荐先这样）
- (b) 另设二级下载源（比如阿里云 OSS 新加坡），由晋升 workflow 同步上传
- 是否需要把 tag 同步到 codeup？(否 / 是)

**Q10 拿不到瘦身版时**
- (a) **fail-loud，回退靠删 override**（推荐）
- (b) 另做 `MOVA_LIBMPV_FALLBACK=official`，在 fork 包里复刻官方下载

**Q11 LGPL 合规文件**
- (a) **每个 Release 附 NOTICE/LICENSES/SOURCE，由配方自动生成**（推荐）
- (b) 不附

**Q12 `libmediakitandroidhelper.so` 的来源**
- (a) **CI 从官方 release jar 下载并校验 md5 后提取，放进我们的 Release**（推荐）
- (b) 继续从 LFS 旧包拷
- (c) 不进 Release，fork 包构建期另去官方源取

**Q13 fork 包对外路径**
- 是否借这次改名（比如 `media_kit_libs_android_video_slim_v041` → `media_kit_libs_android_video_mova`），让 README 里的 git `path` 长期稳定？(是 / 否)

**Q14** 如果 GitHub 仓库设置提供"不可变 Release"之类的选项，是否开启？(是 / 否)
