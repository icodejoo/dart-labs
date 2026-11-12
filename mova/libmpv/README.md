# mova libmpv 瘦身产物（消费侧）

构建配方、flavor 脚本、CI 定义在独立子工程 [`mova-libmpv`](../../../mova-libmpv/README.md)。
本目录只保留 CI 回写的构建产物。

## 当前版本：只有 n9

全部平台以 n9 为主：ffmpeg n9.0.2 + mpv v0.41.0 + WHEP/WebRTC。旧 n6 产物
（Android 四 ABI、Linux、Windows 旧目录、iOS/macOS 裸 dylib）已于 2026-10-26 移除，不再保留回退。

| 平台 | 位置 | 说明 |
|---|---|---|
| Android | `../packages/media_kit_libs_android_video_slim/android/src/main/jniLibs/<abi>/` | 不在本目录；`libmpv.so` 由 `build-mova-libmpv.yml` 注入，`libmediakitandroidhelper.so` 为上游原样提取 |
| Windows x64 | `windows-x64/{libmpv-2.dll,libmpv-2.def,libmpv.dll.a}` | n9；2026-10-28 起目录与文件名固定，`media_kit_libs_windows_video_slim` 的 CMakeLists 直接引用；版本信息见 `VERSION`；拉取/检查 LFS 用 `python tool/libmpv_hydrate.py` |
| Linux x64 | 无入库产物 | 由 n9 CI 出 artifact |
| iOS / macOS | 不在本目录 | n9；`Mpv.xcframework` 直接由 CI 回写到 `../packages/media_kit_libs_{ios,macos}_video_slim/{ios,macos}/Frameworks/`（与 Android 把 `.so` 放进包里同一个组织方式）。本目录下原来的 `ios-arm64/`、`macos-*/` n6 裸 dylib 已删除 |

## 约定

- 产物由 [`.github/workflows/build-mova-libmpv.yml`](../../.github/workflows/build-mova-libmpv.yml)
  构建并 commit 回来；push 自动构建开关见 `mova-libmpv/tools/whep-flavor/ci-platform`
  （默认 `none`，需要时用手动 dispatch 指定平台）。
- mova 工程侧的接入方式见 `mova-libmpv/README.md` 的"接入 mova 工程"一节。
- 改 flavor 脚本、patch、构建选项、平台支持范围，去 `mova-libmpv` 改；这里不要再放
  任何构建配方文件。

## 接入指南（从项目 README 迁入）

以下为消费侧接入说明；构建配方与 CI 继续见独立 mova-libmpv 文档。

### 进阶：接入自研瘦身版 libmpv（可选，仅进阶用户）

默认情况下（不做任何配置）安装 mova 会走官方 `media_kit_libs_video` 依赖，能正常播放，
只是体积比自研瘦身版大一些（Android 约 11.8MB → 6.05MB；Windows 约 14.66MB →
13.41MB。二进制越裁越小，具体数字见各平台产物目录）。项目自己维护了一套体积更小的
瘦身版 libmpv 构建（独立子工程 `mova-libmpv`，产物通过 CI 自动同步推送到本仓库
`packages/` 各对应平台包内）。**这是可选的进阶操作，普通用户完全不需要做，装了 mova 也不会自动生效。**

**能力面被裁过，接入前请知悉**：瘦身版去掉了 VP8/VP9 软解、收窄了音频
decoder/demuxer 白名单、砍掉了部分协议（ftp/async/cache/subfile/httpproxy），且
avfilter（`overlay`/`equalizer`，用于 OSD/字幕合成/音频均衡）移除后的真机播放影响
**尚未做过系统性验证**。如果你的场景依赖这些能力，先别接入。

### 机制：同名整包替换（同一套思路适用所有已落地平台）

不管哪个平台，接入方式都是**同一个模式**：本仓库提供一个与官方包**同名**的 fork 包
（`publish_to: 'none'`，只能通过 path/git 依赖引用，不会被误装），装了它并在你项目的
`pubspec.yaml` 里用 `dependency_overrides` 指过去之后，官方包**完全退出依赖图**——
不是"两份二进制打架、谁赢的问题"，而是从一开始就只有一个提供方，天然没有冲突，
也不需要额外的合并规则。删掉 `dependency_overrides` 那几行，就干净回退到官方版本，
零残留、零副作用。

### Android

```yaml
# 你项目自己的 pubspec.yaml —— 复制粘贴即可用，把 ref 换成你想锁定的 commit/tag
dependency_overrides:
  media_kit_libs_android_video:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: mova/packages/media_kit_libs_android_video_slim
      ref: main
```

如果你是把 `dart-labs` 仓库 clone 到自己项目旁边本地开发（而不是走 git 依赖），
把上面 `git:` 那三行换成一行相对路径即可（假设两个仓库是兄弟目录）：

```yaml
    path: ../dart-labs/mova/packages/media_kit_libs_android_video_slim
```

不需要改任何 Gradle 文件、不需要 `pickFirsts`——加这一行依赖覆盖就是全部操作。
这个 fork 包内含两个原生库：mova-libmpv 自建的瘦身版 `libmpv.so`，以及
**原样提取自官方 release 的** `libmediakitandroidhelper.so`（负责 `content://`
URI 打开等，mova-libmpv 不构建这个，必须保留，否则会丢功能）。

验证方式（不用信我们说的，自己核对，`<mova-repo>` 换成你本地 clone 的路径）：

```bash
unzip -p build/app/outputs/flutter-apk/app-release.apk lib/arm64-v8a/libmpv.so | sha256sum
sha256sum <mova-repo>/mova/packages/media_kit_libs_android_video_slim/android/src/main/jniLibs/arm64-v8a/libmpv.so
# 两个 sha256 应完全一致
```

### Windows

```yaml
dependency_overrides:
  media_kit_libs_windows_video:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: mova/packages/media_kit_libs_windows_video_slim
      ref: main
```

同样只需要这一行（本地 clone 用法同上，把 `git:` 换成 `path: ../dart-labs/mova/...`）；
这个 fork 包自带自研瘦身版 `libmpv/windows-x64/libmpv-2.dll`（路径相对 mova 工程） 以及对应的导入库与公共头文件，完全自包含，
跳过官方 7z 下载。参考本仓库 [example/pubspec.yaml](example/pubspec.yaml) 的实际写法（长期用于真机验证）。

### iOS / macOS

**CI 已验证到编译、链接与 WHEP 端到端冒烟；iOS 真机起播未验证（见本节末）**：

```yaml
dependency_overrides:
  media_kit_libs_ios_video:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: mova/packages/media_kit_libs_ios_video_slim
      ref: main
  media_kit_libs_macos_video:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: mova/packages/media_kit_libs_macos_video_slim
      ref: main
```

`packages/media_kit_libs_ios_video_slim` 与 `_macos_video_slim` 两个 fork 包里的
`Frameworks/Mpv.xcframework` 由 CI（`build-mova-libmpv.yml` 的 `apple-whep` +
`apple-package`）直接编译并回写（LFS），是 n9 线的 WHEP 版 libmpv：ffmpeg n9.0.2 + WHEP/DTLS-SRTP
+ mpv v0.41.0，单文件静态，只依赖系统库。iOS 为真机 arm64 + 模拟器 arm64/x86_64，macOS 为
arm64 + x86_64 的 universal；`install name` 为 `@rpath/Mpv.framework/Mpv`，最低版本 iOS 13 / macOS 10.15。
podspec 里**没有 `prepare_command`**（CocoaPods 对 `:path` pod 不执行它），`Frameworks/.symlinks/mpv`
由 podspec 求值时生成（已 `.gitignore`）。

**TLS 行为变化**：Apple 版 libmpv 的 TLS/DTLS 全部走静态 mbedtls（securetransport 做不了 DTLS-SRTP），
所以与 Android 一样：`tlsVerify` 为 true 时必须同时给 `tlsCaFile`（读不了系统钥匙串）；
mbedtls 3.4 不匹配证书 SAN 里的 IP 地址，IP 字面量主机名的 https 在校验开启时必然失败，请用域名。
ffmpeg 因此为 `--enable-version3`，整体 **LGPLv3**。

**宿主 App 需要自己做的**：`NSLocalNetworkUsageDescription`（WHEP 连局域网地址时 iOS 14+ 会弹本地网络权限）；
macOS 沙盒需要 `com.apple.security.network.client`；macOS 的 Developer ID 签名/公证、iOS 签名由宿主 App
嵌入 framework 时完成（包内只做了 ad-hoc 签名）；App Store 出口合规问卷从"只用系统加密"变成"自带 mbedtls"，请自行确认。

**仍未验证（CI 做不了）**：iOS 真机起播与 VideoToolbox 硬解（runner 上 `hwdec-current` 是 no）、前后台切换、
真机的本地网络权限弹窗。
详见 [doc/plans/2026-09-25-libmpv-pub-package.md](../doc/plans/2026-09-25-libmpv-pub-package.md)
「Darwin（iOS/macOS）同名替换设计」一节；欢迎有 Mac 环境的贡献者验证并回填结论。

### Linux

libmpv 在 Linux 上来自系统（`media_kit_video` 走 pkg-config 找 mpv/epoxy），
不存在"包提供二进制"这个位置可占，本方案模型不适用，接入需要走系统包管理或
自建 RPATH，不在本方案范围内。

### 免责声明

这是社区/进阶用法，mova 官方不对接入后的行为提供支持保证；瘦身版二进制版本与 mova
包版本没有强绑定关系，升级前建议自己按上面的 sha256 核对方式重新验证一次。
