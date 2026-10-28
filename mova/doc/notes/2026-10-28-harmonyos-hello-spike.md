# 鸿蒙版 Flutter 最小 HAP 验证（HarmonyOS 4.2 真机能否运行）

> 日期 2026-10-28。目标：在本机搭鸿蒙版 Flutter，构建最小工程 HAP，供主会话装到 STG-AL00（HarmonyOS 4.2.0.125）上验证。
> 本次**没有碰手机**（未装 HAP、未跑 `hdc` 连接）。例外：`flutter doctor -v` 的「Connected device」一项会自动做设备枚举，触发过一次 adb/hdc 只读列设备，没有任何写入。
> 符号：**[实测]** 本机跑出来的；**[源码]** 读过源码/清单；**[待确认]** 没有证据。
> **代码与脚本已归档到 [`tool/harmonyos-spike/`](../../tool/harmonyos-spike/README.md)**（两个最小工程源码、环境脚本、OBS 回源代理、HAP 哈希；HAP 本体不入库）。文中的 `E:\w`、`E:\sdk` 是当时的本机路径。

## 0. 结论（先看这个）

1. **已产出 HAP，但是未签名**。debug 96MB、release 19.5MB，路径见 §6。签名需要华为账号（AGC 调试证书 + 绑定设备 UDID 的 Profile），属人工步骤，见 §5。
2. **HarmonyOS 4.2 大概率装不上，而且不是签名问题，是 API 级别问题 [实测]**：Flutter-OH 的嵌入层 HAR（`@ohos/flutter_ohos`）自己声明最低 `compatibleSdkVersion: 12`（HarmonyOS 5.0.0）。把工程压到 9 时 hvigor 直接拒绝：
   `The project's compatibleSdkVersion: 9 cannot be lower than the minimum compatible version 12 required by the dependencies: @ohos/flutter_ohos`。
   产出的 HAP `minAPIVersion=12`，目标机上报的 API 为 8/9（`hw_sc.build.os.apiversion=8`、`persist.sys.ohc.apiversion=9`）。4.x 系统的 API 是 9–11（见 §1），都低于 12。预期现象是 **`hdc install` 就报版本/SDK 不兼容**，应用起不来。
3. 想硬试的话只有改 HAR 的最低版本绕过 hvigor 校验（本次没做）：即便装上，嵌入层用了 API 12 以后的 ArkUI/窗口接口，运行期大概率崩。不建议花时间。
4. 因此"HarmonyOS 4.2 真机能不能跑鸿蒙版 Flutter"，**当前证据指向不能**。装机清单（§7）仍然给出，主要用来拿到设备侧的原始报错作实锤。

## 1. 设备 API 的核实情况（没有猜）

| 项 | 结论 | 依据 |
|---|---|---|
| `hw_sc.build.os.apiversion=8` / `persist.sys.ohc.apiversion=9` 的官方含义 | **[待确认]** 没找到官方文档定义这两个属性 | 搜索只命中一个第三方 GitCode 仓库里的 `ohos_system.prop` 样例，注释为"ohos API version"，没有华为定义 |
| HarmonyOS 4.x 对应 API | 3.1/4.0 为 API 9（en.wikipedia "HarmonyOS version history"，另 IT 之家映射表 3.1/4.0 对应 OpenHarmony API 9）；4.2 **[待确认]** 没找到明确对照（常见说法是 API 10–11），无论哪个都 < 12 | Wikipedia、IT 之家 |
| 5.0.0 对应 API | 12（Wikipedia：HarmonyOS NEXT 商用版 API 12） | 同上 |
| Flutter-OH 最低要求 | API 12 | **[实测]** hvigor 报错；`oh_modules/@ohos/flutter_ohos/oh-package.json5` 里 `"compatibleSdkVersion":12` |

## 2. 工具链版本表

| 组件 | 版本 | 位置 | 出处 / 校验 |
|---|---|---|---|
| 鸿蒙版 Flutter | `3.41.9+ohos-1.0.2`（Dart 3.11.5，引擎 `42d3d75a56`，ohos 引擎 `4cbeea6a36…`） | `E:\sdk\flutter-ohos-3.41.9` | gitcode `CPF-Flutter/flutter_flutter` 分支 `oh-3.41.9-release` 的压缩包（根目录名即 `3.41.9+ohos-1.0.2`）；[实测] `flutter --version` |
| 备选 Flutter-OH | `3.35.7+ohos-1.0.5`（Dart 3.9.2） | `E:\sdk\flutter-ohos-3.35.7` | 同上，分支 `oh-3.35.7-release`；已装，但与现成 SDK 都编不过，见 §4 |
| OpenHarmony 公开 SDK | **7.0-Release，`26.0.0.38-Beta`（API 26）** | `E:\sdk\ohos-sdk7\sdk\26` | `repo.huaweicloud.com/openharmony/os/7.0-Release/ohos-sdk-windows_linux-public.tar.gz`，**SHA-256 `130a438c…338f` 与官方 `.sha256` 一致 [实测]**，匿名可下 |
| Command Line Tools（hvigor/ohpm/node） | `6.0.1.251`：hvigor 6.21.1、ohpm 6.0.1、Node v18.20.1、内置 HarmonyOS 6.0.1（API 21） | `E:\sdk\ohos-cli6\command-line-tools` | HuggingFace 镜像 `csukuangfj/harmonyos-commandline-tools`；SHA-256 `fced75a6…2dec32` 与 HF 记录一致。**不是华为官方直链**，见 §5 |
| Command Line Tools 5.0.5.200 | 内置 HarmonyOS 5.0.1（API 13）、ohpm 5.0.10 | `E:\sdk\ohos-cli\command-line-tools` | 同上镜像；SHA-256 `c8aab291…5ba`。编不过 3.41.9，仅留作对照 |
| JDK | 17.0.18+8 | `E:\sdk\jdk\jdk-17.0.18+8` | 本机已有 |
| hdc | 3.2.0f（SDK 26 自带）/ 3.1.0b（5.0.5 自带）；仅 `-v` 验证 | `E:\sdk\ohos-sdk7\sdk\26\toolchains\hdc.exe` | — |

环境脚本：`E:\sdk\ohos-env.ps1`（dot-source，只改当前会话，不动全局 PATH）。构建用：

```powershell
$env:OHOS_SDK='7'; . E:\sdk\ohos-env.ps1
$env:FLUTTER_OHOS_STORAGE_BASE_URL='http://127.0.0.1:8099'   # 本地 OBS 回源代理，见 §3；已停，需要再下引擎产物时再起
```

## 3. 每步实际做了什么（命令与结果）

1. **读要求**：Flutter-OH README / 环境搭建文档（经 `api.gitcode.com` 的 contents 接口取）：要 JDK17、DevEco 或命令行工具、`HOS_SDK_HOME`、`~/.npmrc`。模板默认 `compatibleSdkVersion 5.0.5(17)`、`targetSdkVersion 26.0.0`、`modelVersion 5.1.0`，即**按 API 26 的 SDK 设计**。
2. **命令行工具**：华为官方下载中心要登录，没有匿名直链；用 HF 镜像（aria2，12MiB/s）。
3. **Flutter-OH 源码**：git 协议不通；`raw.gitcode.com/<repo>/archive/refs/heads/<分支>.zip` 会 302 到 OBS 签名链接，可下。包里没有 `.git`，本地 `git init` + 提交 + `git tag 3.41.9+ohos-1.0.2`（Flutter 靠它算版本）。
4. **`flutter --version` 的三个坑 [实测]**：
   - `flutter_tools` 依赖两个 gitcode **git 包**（`code_assets`、`hooks_runner`，ref `flutter_3.41.9_deps`），git 协议拉不动 → 下 `fluttertpc_dart_native` 对应分支压缩包，把 `packages/flutter_tools/pubspec.yaml` 的 `dependency_overrides` 改成本地 `path:`（改动已提交到本地 git）。
   - `bin/internal/engine.version` 被 gitignore，`update_engine_version.ps1` 用 `git ls-files` 判断是否读它，不在库里就回落到内容哈希，算出错误的引擎哈希（`8ac666df…`）→ `git add -f` 之后恢复正常。
   - pwsh 的 PATH 里没有 git，补 `C:\Program Files\Git\cmd`。
5. **华为云 OBS 引擎产物**：`flutter-ohos.obs.cn-south-1.myhuaweicloud.com` 对本机极不稳（TLS 握手经常被重置，只有 Range 请求偶尔通过）。写了一个本地回源代理（分块并行 + 无限重试 + 落盘缓存，`FLUTTER_OHOS_STORAGE_BASE_URL` 指过去）。Dart SDK（199MB）、`ohos-arm64{,-profile,-release}` 等产物约 1.5 小时拉完，缓存在 `E:\sdk\_dl\obs-cache`（代理脚本在本会话 scratchpad，已停）。
6. **`flutter doctor -v`**：HarmonyOS toolchain 一项 `[√]`。
7. **工程**：`flutter create --platforms ohos --org com.example.mova hello_ohos`，首页一个 `Text` + 一个 `ElevatedButton`（点击 +1）。工程放 `E:\w\hello_ohos`（scratchpad 里路径太长，见下）。
8. **构建**：见 §4 的试错表，最终组合成功：`flutter build hap --debug --no-codesign` 与 `--release --no-codesign` 都 `exit=0`。

## 4. 试错记录（SDK/路径/模板）

| # | 组合 | 结果 |
|---|---|---|
| 1 | 3.41.9 + CLI 5.0.5（SDK API 13） | hvigor 先报 `Unsupported modelVersion 5.1.0`（模板写 5.1.0，该 hvigor 只认 5.0.2），改后 ArkTS 编译 `flutter_ohos` 报 46 个错（`getGlobalWindowMode`、`AxisEvent` 等不存在） |
| 2 | 3.41.9 + CLI 6.0.1（SDK API 21） | 19 个错（`CompetitionStrategy`、`isInFreeWindowMode` 不存在）：嵌入层用了 API 21 以后的接口 |
| 3 | 3.35.7 + CLI 5.0.5（API 13） | 46 个错，同 #1 |
| 4 | 3.35.7 + CLI 6.0.1（API 21） | 19 个错（`autoFillManager.*` 类型不存在） |
| 5 | **3.41.9 + OpenHarmony 7.0 SDK（API 26）+ CLI 6.0.1 的 hvigor** | 成功，需要下面几处改动 |

#5 需要的改动（均在 `E:\w\hello_ohos\ohos`）：
- `build-profile.json5`：`runtimeOS` 改 `OpenHarmony`（产品与 `entry/build-profile.json5` 两处），`compatibleSdkVersion: 12`，加 `compileSdkVersion: 26`、`targetSdkVersion: 26`（整数，OpenHarmony 工程要这么写）。
- `entry/src/main/module.json5`：`deviceTypes` 由 `phone` 改 `default`（OpenHarmony 下 `phone` 导致 `SyscapTransform` 报"多设备系统能力交集为空"）。
- `oh-package.json5`：去掉 `@ohos/hypium` devDependency（默认 ohpm 源是华为内网域名，解析不到；最小工程不需要）。
- **hack**：hvigor 6.21.1 只认 SDK 元数据 `metaVersion` 3.0.0–3.0.1，而 26.0.0.38 是 3.0.2，不改会报 `Unable to find the following components: toolchains:26, ArkTS:26…`。把 `E:\sdk\ohos-sdk7\sdk\26\{ets,js,native,previewer,toolchains}\oh-uni-package.json` 的 `metaVersion` 改成 `3.0.1`（原文件留有 `.orig`）。只改描述字段，没动 SDK 内容；更干净的办法是换配套的新版 hvigor（下载中心的新版命令行工具）。
- 环境变量 `OHOS_BASE_SDK_HOME`（hvigor 对 OpenHarmony 工程必需）。
- **路径长度**：工程放在 scratchpad 会触发 `The length of path exceeds the maximum length: 259`（ohpm 的哈希目录很深），所以搬到短路径 `E:\w\hello_ohos`。

**注意这个 HAP 是 OpenHarmony 运行时（`compileSdkType: OpenHarmony`、`deviceTypes: default`）**，不是用 HarmonyOS SDK 编的。装 HarmonyOS 4.2 之外的"纯血"机型是否被接受**[待确认]**。要产出 `runtimeOS: HarmonyOS` 的包，需要华为下载中心里 SDK 26 对应的 Command Line Tools（需登录，见 §5）。

## 5. 需要用户人工做的事

1. **签名（必需）**。HAP 目前是 unsigned，零售华为机只认华为签发的调试证书，且 Profile 要绑定设备 UDID。二选一：
   - **DevEco Studio 自动签名**：装 DevEco Studio，登录华为账号（需实名），打开 `E:\w\hello_ohos\ohos`，`File → Project Structure → Signing Configs`，勾 "Automatically generate signature"，真机连接后会自动申请调试证书和 Profile。
   - **AGC 手动签名**：登录 AppGallery Connect → 创建应用（Bundle name 填 `com.example.mova.hello_ohos`，或者改工程的 bundleName 与已有应用一致）→ 注册设备 UDID（`hdc shell bm get -u`）→ 申请调试证书（需 CSR：`hap-sign-tool generate-keypair` + `generate-csr` 生成）和调试 Profile（`.p7b`）→ 用 `hap-sign-tool sign-app` 对 HAP 签名：
     ```
     java -jar E:\sdk\ohos-sdk7\sdk\26\toolchains\lib\hap-sign-tool.jar sign-app -keyAlias <别名> -signAlg SHA256withECDSA -mode localSign ^
       -appCertFile <调试证书.cer> -profileFile <调试profile.p7b> -inFile hello_ohos-release-unsigned.hap -keystoreFile <你的.p12> -outFile hello_ohos-release-signed.hap -keyPwd <口令> -keystorePwd <口令>
     ```
     （命令按 SDK 自带 `hap-sign-tool` 帮助整理，**未实跑**。）
2. **可选**：到华为下载中心 `https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos` 取官方 Command Line Tools，与本次 HF 镜像包比对 SHA-256（`commandline-tools-windows-x64-6.0.1.251.zip` = `FCED75A65E23D0FDBB76123A854F83232C361971B027F69BEFDAFD243C2DEC32`）。工具链是第三方镜像拿的，建议核对后再长期使用。
3. 本机试过用 OpenHarmony SDK 自带的调试证书签名（`E:\sdk\ohos-sign-oh.ps1`），`sign-app` 报证书链校验失败，**未跑通**；即使跑通，零售华为机也不会信这个证书。不建议再投入。

## 6. 产物

| 文件 | 大小 | SHA-256 |
|---|---|---|
| `E:\w\out\hello_ohos-release-unsigned.hap` | 20,454,453 | `d1b8d065318c36ff856a94ddbef11931dfc11143d3b8dab87c8fb5566aa689fc` |
| `E:\w\out\hello_ohos-debug-unsigned.hap` | 95,927,806 | `a2319230f2fa1dc04db0885fe611fe05f7f190b4211b7ea0cff95d8e2f6525a2` |

HAP 关键元数据 [实测]：`bundleName=com.example.mova.hello_ohos`、`minAPIVersion=12`、`targetAPIVersion=26`、`compileSdkType=OpenHarmony`、`deviceTypes=[default]`、`libs/arm64-v8a/libflutter.so`（仅 arm64）、入口 `EntryAbility`。

构建命令（工程根 `E:\w\hello_ohos`，需先 `$env:OHOS_SDK='7'; . E:\sdk\ohos-env.ps1`）：

```powershell
flutter build hap --debug   --no-codesign   # → build\ohos\hap\entry-default-unsigned.hap
flutter build hap --release --no-codesign
```

release 输出尾部：`√ Built build\ohos\hap\entry-default-unsigned.hap (19.5MB).`

## 7. 待主会话执行的装机清单（签名之后）

> hdc 与 adb 互不冲突：hdc server 默认监听 8710，adb 是 5037，可同时运行；但同一台手机能否同时被两者枚举取决于 USB 配置 **[待确认]**。若 `hdc list targets` 看不到设备：开发者选项里确认「USB 调试」已开、USB 连接模式选"传输文件"、手机上点掉"允许 USB 调试"授权弹窗。HarmonyOS 4.2 是否暴露 hdc 接口 **[待确认]**，这本身就是要验证的东西之一。
> 设备此刻在被别的测试占用，装之前先和那边协调（`hdc` 不会影响 adb，但 `install -r` 会改动设备）。

```powershell
$hdc = 'E:\sdk\ohos-sdk7\sdk\26\toolchains\hdc.exe'     # 若连不上，换 E:\sdk\ohos-cli\command-line-tools\sdk\default\openharmony\toolchains\hdc.exe（3.1.0b）
& $hdc list targets -v                                   # 设备应出现；记下序列号
& $hdc shell bm get -u                                   # 取 UDID（签名 Profile 要用）
& $hdc -t <sn> install -r E:\w\out\hello_ohos-release-signed.hap
& $hdc -t <sn> shell aa start -a EntryAbility -b com.example.mova.hello_ohos -m entry
& $hdc -t <sn> shell hilog -x                            # 取日志，建议另开窗口，启动应用前先开始抓
& $hdc -t <sn> shell bm dump -n com.example.mova.hello_ohos   # 查安装后的包信息
& $hdc -t <sn> uninstall com.example.mova.hello_ohos     # 清理
```

预期现象与失败时要收集的东西：

| 阶段 | 预期 | 要收集 |
|---|---|---|
| `list targets` 为空 | 设备没暴露 hdc | 开发者选项截图、`hdc -v`、`adb devices`（只读）对照 |
| `install` 报错 | **最可能**：版本不兼容（minAPI 12 > 设备）。错误文本里可能含 `older sdk version in the device`；具体错误码**待确认**。其余可能：签名/Profile 校验失败（`verify signature failed`、`not trusted app source`、`parse profile prop check error`）、UDID 不在 Profile 里 | 完整 `hdc install` 输出原文、`hilog` 里同一时刻的 BMS（`BundleMgr`）日志 |
| 装上但启动即退 | 嵌入层调用了设备没有的接口 | `hilog` 里 `FATAL`/`JsError`/`libflutter` 相关行、`hdc shell hidumper -s AbilityManagerService` 输出 |
| 装上且出现 "Hello HarmonyOS Flutter count=0" 与 "+1" 按钮 | 点击 count 加一，说明 4.2 能跑 Flutter-OH（与 §0 的预判相反，值得单独记录） | 截图（`hdc shell snapshot_display -f /data/local/tmp/s.jpeg` 后 `hdc file recv`） |

## 8. 遇到的坑汇总

- 华为官方命令行工具要登录，无匿名直链；HF 镜像是第三方（哈希只能与镜像自己的记录核对）。
- 模板与 SDK/hvigor 版本强耦合：`modelVersion`、`compileSdkVersion`、SDK `metaVersion` 三处各卡一次。
- bsdtar 解压 2.5GB 的 zip 在这台机器上约 15–25 分钟（大量小文件 + Defender）。
- Git Bash 的 `tar` 不认 zip；PowerShell 里 `Remove-Item` 对 `E:\w` 被安全钩子拦截（避免对该路径做删除）。
- `flutter doctor` 会枚举设备（adb/hdc），本次已触发一次，后续构建没有再跑。
- 机器上还有 `adb`、`hdc` 进程在跑（来源：`flutter doctor` 或另一个测试的 adb server），我没有去杀。

## 9. 本次动过的机器状态

- 新增目录：`E:\sdk\{ohos-cli,ohos-cli6,ohos-sdk7,flutter-ohos-3.41.9,flutter-ohos-3.35.7,flutter-ohos-deps,flutter-ohos-deps335,_dl}`、`E:\w`、`E:\sdk\pub-cache-ohos`；脚本 `E:\sdk\ohos-env.ps1`、`E:\sdk\ohos-sign-oh.ps1`（未跑通）。`E:\sdk\_dl` 里留有安装包与 OBS 缓存，可按需清理（约 12GB）。
- 没主动改：全局环境变量、PATH、用户的 `~/.npmrc`/ohpm 配置（hvigor/ohpm 运行时可能自己在用户目录写缓存，未逐项核查）、`E:\workspaces\dart-labs\mova` 下除本文档外的任何文件。
- 没做：git commit/push、手机上的任何操作。
