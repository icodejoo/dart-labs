# iOS / macOS WHEP 版 libmpv 构建方案（架构设计）

> 日期：2026-10-26　｜　状态：**已落地**（方案 A：静态 mbedtls + Nix overlay；CI 全绿，见 README 顶部"Apple n9 要点"。下文是落地前的设计稿，Q1-Q11 已按"n6 废弃、一切以 n9 为准"定案：Q1=a Q2=a Q3=a Q4=b（模拟器 arm64+x86_64）Q5=c（直接替换 slim 包）Q6=a Q7=a Q8=b Q9=要 PrivacyInfo Q10=b Q11=c）　｜　范围：iOS arm64、iOS 模拟器、macOS arm64 / x86_64 / universal
>
> 目标：让 Apple 平台产出和 Windows / Android **同一条线**的 WHEP 版 libmpv：ffmpeg n9.0.2 + `patches/ffmpeg-whep` 0001–0012（whep demuxer + DTLS-SRTP）+ mpv v0.41.0 + `patches/mpv-v041`。
>
> 标注约定：**实测** = 本次在本机跑过命令或读过源码确认；**引用** = 仓库里已有文档的实测结论；**推断** = 没验证，需要后续步骤证实。

---

## 0. 一页结论

- **securetransport 做不了 WHEP**（实测源码，见 §1）。Apple 上必须引入一个第三方 DTLS 后端。
- **推荐方案 A：换成静态 mbedtls**，直接复用 Android 已经在真机跑通的 0007 / 0009。
  - 补丁量最小：上游 `libmpv-darwin-build` 本来就带 `mk-pkg-mbedtls`，movaslim 当初是**主动去掉**它的。
  - 和 Android 走同一份 DTLS 代码路径。
  - 代价有三条：
    - ffmpeg 要 `--enable-version3`，许可证变成 LGPLv3。这和 Android 现状一样，也和 media_kit 官方 Apple 包一样。
    - 每个架构体积大约 +0.5～0.8 MB（推断）。
    - HTTPS 改由 mbedtls 处理后，`tls-verify=yes` 需要 `tls-ca-file`，和 Android 一样。
- 构建路线建议**继续走 Nix（`libmpv-darwin-build`）**，在现有 `libmpv-darwin-build-mova-slim.patch` 上叠一份 overlay 补丁。分 7 步小步推进，每步都有 CI 关卡（§4）。
- macOS runner 能**真跑** MediaMTX + libmpv 冒烟，所以 WHEP 握手、解密、出帧在 macOS 上能在 CI 里端到端验证。iOS 只能验证到模拟器，真机要用户自己验。
- **顺带发现两个现存缺陷（实测）**，都在现有 n6 线的 Apple slim 包里，WHEP 线必须一并修：
  - 现有 Apple slim 包的 `Mpv` 二进制，install name 都是 `@rpath/libmpv.dylib`，不是 framework 约定的 `@rpath/Mpv.framework/Mpv`。
  - macOS 包的 arm64 切片依赖一个没随包发出的 `@rpath/libz.dylib`。

---

## 1. 核实：Apple 上 ffmpeg n9.0.2 到底有哪些 DTLS 后端

源码：本机 `D:\whep-win\libmpv\src\ffmpeg-n9.0.2`。干净的 n9.0.2：`RELEASE` 文件内容为 `9.0.2`，没有 `whep.c`。

| 事实 | 出处（行号为 n9.0.2） | 结论 |
|---|---|---|
| `dtls_protocol_deps_any="openssl schannel gnutls mbedtls"` | `configure:4115` | **securetransport 不在 DTLS 后端列表里** |
| `tls_protocol_deps_any="gnutls openssl schannel securetransport libtls mbedtls"` | `configure:4112` | securetransport 只能做 TLS（https） |
| `securetransport_conflict="openssl gnutls libtls mbedtls"` | `configure:4108` | **securetransport 不能和 mbedtls / openssl 同时启用**：一旦换 DTLS 后端，https 也要跟着换 |
| `SSLCreateContext(..., kSSLStreamType)` 是该后端唯一的建上下文调用；文件里只定义了 `ff_tls_protocol` | `tls_securetransport.c:276`、`:417` | 只走流式 TLS，没有 `ff_dtls_protocol` |
| `ff_dtls_export_materials` / `ff_ssl_gen_key_cert` / `ff_ssl_read_key_cert` 只在 gnutls、mbedtls、openssl、schannel 四个后端里有实现 | `tls_*.c` grep | whep.c 依赖的三个函数 securetransport 一个都没有 |
| `OBJS-$(CONFIG_DTLS_PROTOCOL) += tls.o $(TLS-OBJS-yes)` | `libavformat/Makefile:723-730` | TLS 和 DTLS 共用"唯一被启用的那个后端"的目标文件 |
| mbedtls 在 `EXTERNAL_LIBRARY_VERSION3_LIST` 里 | `configure:2051-2060`，`LICENSE.md:108-111` | 用 mbedtls 必须 `--enable-version3`，产物是 LGPLv3 |
| OpenSSL ≥3 只在 `--enable-gpl` 时才要求 version3；`LICENSE.md` 称 OpenSSL "compatible with the LGPL" | `configure:7551-7557`，`LICENSE.md:125-127` | 用 OpenSSL 时按 ffmpeg 自己的口径仍是 LGPLv2.1+（法律上见 §2 备注） |

另外两条 Apple 系统路线的判断：

- **SecureTransport 自己的 DTLS**（`kSSLDatagramType`）：系统 API 本身有 DTLS 模式。但没有 `use_srtp` 扩展，也没有 RFC 5705 的密钥导出，拿不到 SRTP 密钥。而且 iOS 13 / macOS 10.15 起已被标为废弃。**不可行**（推断：基于公开头文件里找不到这两个能力）。
- **Network.framework**：`sec_protocol_options` 公开 API 里没找到 `use_srtp` 扩展协商。它还自己持有 socket，不能像 ffmpeg 的 `external_sock` 那样，把 DTLS 记录塞进 whep.c 已经在做 ICE、RTP 分流的那个 UDP socket。**不可行**（推断：本次没在 Apple 文档里找到反证，查证范围有限）。

**结论：Apple 上要做 WHEP，只能从 mbedtls / openssl / gnutls 里选一个静态带进来，或者自己改 ffmpeg 让两个后端共存。**

---

## 2. 方案对比

### 2.1 候选

- **A. 全面换 mbedtls**：TLS 和 DTLS 都走 mbedtls，删掉 securetransport。
- **B. 全面换 OpenSSL 3**：TLS 和 DTLS 都走 openssl。0004 的 `tls_openssl.c` 改动就是 WHEP 最初开发、Linux ASan 验证用的平台。
- **C. 混合**：https 继续用 securetransport，只让 mbedtls 承担 `dtls` 协议。要新写 ffmpeg 补丁，解除 `securetransport_conflict`，并避免 `ff_tls_protocol` 重复定义。
- 直接否掉的：SecureTransport DTLS、Network.framework（§1）；自写 DTLS（要自己实现 ECDHE / ECDSA，ffmpeg 没有椭圆曲线原语，安全风险不可接受）；GnuTLS（拖着 nettle / gmp / libtasn1 一串依赖，iOS 交叉编译和体积都不划算）；BoringSSL（没有版本承诺，ffmpeg 不正式支持）。

### 2.2 对比表

| 维度 | A. mbedtls（推荐） | B. OpenSSL 3 | C. securetransport + mbedtls 混合 |
|---|---|---|---|
| ffmpeg 许可 | **LGPLv3**（`--enable-version3`，configure 强制） | 按 ffmpeg 口径 **LGPLv2.1+**（备注 1） | **LGPLv3**（mbedtls 仍然链入） |
| 与现状对照 | 和 Android 现状（`flavors-mova-slim*.sh` 都带 `--enable-version3`）、media_kit 官方 Apple 包（上游 `mk-pkg-ffmpeg/meson.build` 默认 `--enable-mbedtls --enable-version3`，实测）一致；比 Apple 现行 movaslim（v2.1+）更紧 | 和 Windows（SChannel，v2.1+）一致 | 同 A |
| 体积增量（每架构，推断） | **+0.5～0.8 MB**。依据：Linux x86_64 链入后 mbedtls 约 0.55 MB（引用 extreme-slim-config）；Windows 换 SChannel 省 773,632 B（引用）；L1 裁剪还能省约 115 KB | **+1.5～3 MB**。依据：没有裁剪版 OpenSSL 的实测；未裁剪版 Windows 上 14.86 MB 对 9.30 MB（引用）只能当上界参考 | ≈ A + 几十 KB（securetransport 胶水代码很小） |
| ffmpeg 补丁量 | **0 个新补丁**：0007 / 0009 已经在 0001–0012 里；`whep.c` 守卫已含 `CONFIG_MBEDTLS` | **0 个新补丁**（0004 本来就改 openssl） | **新补丁约 30–60 行**：configure 冲突表、`tls_mbedtls.c` 里 `ff_tls_protocol` 加条件编译、Makefile。ffmpeg 升级时要一起维护 |
| Nix 构建改动 | 小：恢复上游已有的 `mk-pkg-mbedtls`，改静态、开 `MBEDTLS_SSL_DTLS_SRTP`、关 programs/tests（旧分支 v9 线做过前两项，引用） | 大：新写 `mk-pkg-openssl`。OpenSSL 用 Perl `Configure`，不是 meson / cmake，要另做交叉包装和 iOS / macOS target，再定一套 `no-*` 裁剪清单 | 同 A，另加 ffmpeg 补丁 |
| CI 可验证性 | 高：Android 真机已跑通 DTLS-SRTP（引用 android-whep-build-and-device / 2026-10-26 设备验证）；macOS runner 能端到端冒烟 | 高：Linux 上验证最充分（ASan、丢包、NACK）；macOS runner 同样能冒烟 | 中：后端组合是自造的，上游和其他平台都没跑过 |
| 与 Win / Android 行为一致性 | **DTLS 代码路径和 Android 完全相同**（同一 `tls_mbedtls.c` + 0007 / 0009） | DTLS 和 Linux 开发验证平台相同，和两个出货平台都不同 | DTLS 同 Android，https 同 Apple 现状 |
| HTTPS 行为变化 | `tls-verify=yes` 要配 `tls-ca-file`（mbedtls 读不了钥匙串），和 Android 相同；mova 的 `tlsCaFile` 文档要把 "Android 上必需" 扩成 "Android / Apple 上必需" | 同 A（OpenSSL 也读不了 iOS 钥匙串） | **不变**（继续用系统信任库） |
| 安全维护 | 上游锁 mbedtls 3.4.1，3.4 线已停止维护（推断）；建议另立任务升 3.6 LTS，Android 同步 | OpenSSL 3.x 维护活跃，但版本升级跨度大 | 同 A |
| 加密出口合规（App Store） | 从"只用系统加密"变成"自带加密库"，出口合规问卷的答案可能要变（不下结论，§5 R8） | 同 A | DTLS 部分同 A |

> 备注 1：OpenSSL 3 是 Apache-2.0。FSF 的立场是 Apache-2.0 与 (L)GPLv2 不兼容；ffmpeg 的 `LICENSE.md` 那句 "compatible with the LGPL" 没有区分 OpenSSL 3 之前和之后的许可证。所以"B 能保住 v2.1"只是 ffmpeg 项目的口径，法律确定性低于 A 的"明确 v3"。本文不下法律结论。

### 2.3 为什么推荐 A

1. **一致性最高、风险最低**：DTLS 代码和已在 Android 真机跑通的完全一致。0009 修的悬空指针也正是 mbedtls 3.4.x 才会暴露的问题，上游 darwin 锁的恰好是 3.4.1。
2. **改动最少**：不写新 ffmpeg 补丁，Nix 侧只是把 movaslim 当初去掉的 mbedtls 加回来，而且改静态。
3. 许可证从 v2.1+ 变成 v3，是 A 唯一实质性的代价。这项必须用户拍板（Q2）：
   - 如果不接受 LGPLv3，就选 B（体积代价大、Nix 工作量大）。
   - 如果连 https 行为都不想变，选 C，但要承担一份自维护的 ffmpeg 补丁。

---

## 3. 现状核实（本次实测 + 引用）

### 3.1 构建链现状

| 项 | 现状 | 出处 |
|---|---|---|
| 上游 `media-kit/libmpv-darwin-build` 锁定版本 | ffmpeg **6.0**、mpv **0.36.0**、mbedtls 3.4.1、dav1d 1.2.1、freetype 2.13.2、fribidi 1.0.13、harfbuzz 8.1.1、libass 0.17.1、libpng 1.6.40；**没有 libplacebo** | 实测：上游 `packages.lock.nix`（main） |
| 上游 ffmpeg 通用选项 | 含 `--enable-mbedtls`、`--enable-version3`、`--enable-small`；有 `--ar`，没有 `--ranlib` | 实测：上游 `mk-pkg-ffmpeg/meson.build` |
| 上游 mbedtls 构建 | meson 的 cmake 子项目，默认只出共享库 | 实测：上游 `mk-pkg-mbedtls/meson.build` |
| mova 的 movaslim 补丁 | `libmpv-darwin-build-mova-slim.patch`（1138 行），换成 securetransport、全静态单 dylib、LTO、dead_strip、7 个坑的修法 | 引用：`README.md` iOS / macOS 行 |
| `packages.lock.nix` 是全局的 | 没有按 flavor 区分版本：一旦升 ffmpeg / mpv，同一 checkout 里所有 flavor 都会跟着升 | 引用：`reference/ffmpeg9-zhangfly` 补丁注释 |
| 旧分支 v9 线（存档） | ffmpeg n9.0 + mpv 0.41.0 + libplacebo 7.351 在这套 Nix 里 **iOS arm64 跑绿过**（10.15 MiB），macOS 在 0.41 上没有跑绿的记录 | 引用：`reference/ffmpeg9-zhangfly/tools/ffmpeg-slim/README.md` |
| v9 线踩过、本方案直接复用的坑 | 上游 4 个 ffmpeg 补丁对 n9 的处理（`vp9-hwaccel` 引用 n9 已删除的 `FF_CODEC_CAP_ALLOCATE_PROGRESS`，编译失败）；`mpv-audiounit-shared-session.patch` 在 0.41 上打不上；0.41 的 cocoa 依赖 `osdep/mac/swift.h`（用 sed 去掉 `app_bridge.m` 和 `clipboard-mac.m`）；0.41 删掉的一批 meson 选项；iOS 要显式关 `coreaudio` / `avfoundation`；libplacebo 在 darwin 上即使 `-Dvulkan=disabled` 也要 Vulkan-Headers；mbedtls 加 `-fvisibility=hidden` 后 programs 链接失败（要 `ENABLE_PROGRAMS=false`） | 引用：同上补丁内注释 |
| CI | `build-mova-libmpv.yml` 的 `darwin`（macOS 三架构矩阵）和 `ios` job，`macos-15` runner，Nix 加 Xcode 16.1；上游仓库**没有钉 ref** | 实测：读 workflow |
| WHEP workflow | `build-mova-libmpv-whep.yml` 只有 android / windows / linux；文件头已列出 Apple 的三个缺口 | 实测：读 workflow |

### 3.2 现有 Apple slim 包二进制体检（实测，新发现）

方法：用 `git lfs smudge` 把 LFS 对象取到 scratchpad（不动工作区），再用一个自写的 Python Mach-O 解析脚本读加载命令。

| 包 | 字节 | 架构 | `LC_ID_DYLIB` | 最低系统 | 非系统依赖 |
|---|---:|---|---|---|---|
| `media_kit_libs_ios_video_slim/.../ios-arm64/Mpv.framework/Mpv` | 5,741,680 | arm64 | **`@rpath/libmpv.dylib`** | iOS 9.0（`LC_VERSION_MIN_IPHONEOS`）；framework 的 Info.plist 写的是 12.0 | 无（`/usr/lib/libiconv.2.dylib`、`libz.1.dylib` 都是系统库） |
| `media_kit_libs_macos_video_slim/.../macos-arm64_x86_64/Mpv.framework/Mpv` | 15,377,120 | x86_64 + arm64（fat，确认） | **`@rpath/libmpv.dylib`** | x86_64 10.9；arm64 11.0 | **arm64 切片 `LC_LOAD_DYLIB @rpath/libz.dylib`**，x86_64 切片没有这一项 |

后果（推断，没上机验证）：

1. CocoaPods 的 `vendored_frameworks` 会把 `-framework Mpv` 链进 App，链接器记下的是 `@rpath/libmpv.dylib`。运行时 dyld 去 `Frameworks/` 找 `libmpv.dylib` 找不到，App 启动就崩，报 "Library not loaded"。
2. macOS Apple Silicon 上，`@rpath/libz.dylib` 在 App 包里不存在，同样加载失败。依赖名是 `@rpath/libz.dylib` 而不是 SDK 的 `/usr/lib/libz.1.dylib`，说明 arm64 这条腿链到了非 SDK 的 zlib（来源未查）。
3. 这两点验证了 `mova/doc/plans/2026-09-25-libmpv-pub-package.md` 里 "install name 未确认" 的担心。**WHEP 线的打包步骤必须改写 install name，并加 `otool -L` 白名单关卡**（§4 S6）。现有 n6 包要不要单独先修，见 Q8。

### 3.3 iOS / macOS 打包约束（已知 + 推断）

- **iOS 动态库**：只能以 `.framework` 形式放在 App 的 `Frameworks/` 里。签名在 App 归档时由 Xcode / CocoaPods 的 `[CP] Embed Pods Frameworks` 用 App 的证书统一完成。**库这一侧不需要也不应该在 CI 里用真证书签名**（推断，依据：CocoaPods 的标准行为）。
- **macOS**：链接器会给 arm64 自动加 ad-hoc 签名（上表 arm64 切片有 `CODESIG`，实测）。`install_name_tool` 改过之后签名会失效，CI 必须 `codesign -f -s -` 重新做 ad-hoc 签名。正式分发时的 Developer ID、hardened runtime、公证都由 App 侧完成。
- **`prepare_command` 风险**：CocoaPods 对 `:path` 形式的 pod 不执行 `prepare_command`，而 Flutter 插件都是 `:path` pod（引用：release-download 设计 §3.1，本仓库没实测）。现有 slim podspec 靠它建 `.symlinks/mpv/*`。WHEP 打包时要改成在 podspec 求值时直接执行 Ruby 或 `system(...)`，上游官方包也是这么做的。
- **xcframework 的 Info.plist**：要用 `xcodebuild -create-xcframework` 生成，不要手写。framework 的 `MinimumOSVersion` 要和二进制的 `minos` 一致，由 CI 从 `vtool -show-build` 读出来再写进去。
- **隐私清单**：ffmpeg / mpv 会调用 `stat`（文件时间戳）、`mach_absolute_time`（开机时间）这类 Apple 列为 "required reason API" 的函数。Mpv.framework 是否要附 `PrivacyInfo.xcprivacy`，见 Q9（推断）。
- **本地网络权限**：WHEP 连局域网地址（例如 `192.168.x.x` 上的 MediaMTX）时，iOS 14+ 和 macOS 15+ 会弹本地网络权限，宿主 App 要配 `NSLocalNetworkUsageDescription`（推断）。ATS 只管 URLSession / CFNetwork，管不到 ffmpeg 的 BSD socket，`whep+http://` 明文信令不受 ATS 限制（推断）。

---

## 4. 推荐方案：分步落地计划

### 4.1 总体形态

```
dart-labs CI（macos-15）
  checkout media-kit/libmpv-darwin-build @ <钉死的 SHA>
  git apply mova-libmpv/libmpv-darwin-build-mova-slim.patch      # 现有，n6 线也在用，不改
  git apply mova-libmpv/libmpv-darwin-build-whep.patch           # 新增 overlay：版本对齐 + mbedtls + whep
  cp -r mova-libmpv/patches/{ffmpeg-whep,mpv-v041} build-root/patches/mova/   # 进入 flake 源
  git add -A                                                     # Nix git+file 只看被跟踪的文件（坑 ①）
  nix develop -c make TARGET=mk-out-archive-libs-<os>-<arch>-video-movaslim
  → libmpv.dylib（单文件，全静态）→ Mach-O 关卡 → 冒烟 → xcframework 组装
```

为什么是 overlay 补丁，而不是改现有补丁：

- 老 `darwin` / `ios` job 还在用现有补丁出 n6 产物。
- `packages.lock.nix` 是全局的，只有"同一 checkout 里叠 overlay"才能让两条线互不干扰。
- 和 Android 的 `libmpv-android-video-build.patch` + `patches/android-v041/buildscripts-v041.patch` 是同一个模式。

### 4.2 版本对齐清单

| 组件 | 现在（darwin n6 线） | WHEP 线目标 | 依据 / 做法 |
|---|---|---|---|
| ffmpeg | 6.0 | **n9.0.2**（GitHub `n9.0.2.tar.gz`，sha256 首次跑 CI 时由 Nix 报出再写死） | 和 Win / Android 同线；WHEP 补丁基于 `946fcce` |
| mpv | 0.36.0 | **v0.41.0** | 同上 |
| libplacebo | 无 | **v7.360.0**，最小静态（`-Dvulkan/d3d11/glslang/shaderc/lcms/dovi/libdovi/xxhash/unwind=disabled`，`demos/tests/bench/fuzz=false`） | 和 Android `buildscripts-v041.patch` 同开关（引用）；子模块 jinja / markupsafe / fast_float / glad 按 v7.360.0 的 `.gitmodules` 逐个钉 commit 拉取（v9 线的做法，引用）；Vulkan-Headers 作为备用（v9 线在 darwin 上遇到过，引用） |
| mbedtls | 3.4.1，共享库（movaslim 下根本不构建） | **3.4.1 静态**，开 `MBEDTLS_SSL_DTLS_SRTP`，关 programs / tests | Android 用 3.4.0 + 同一处 sed（`whep-android.patch`，引用）；`KEEP_PEER_CERTIFICATE`、`TIMING_C`、`X509_CRT_PARSE_C` 在 3.x 默认就开；升 3.6 见 Q7 |
| dav1d / freetype / fribidi / harfbuzz / libass / libpng | 上游版本 + movaslim 静态化 | **不动** | 先求绿；Android n9 链也沿用上游各自的旧版本（引用） |
| uchardet / libxml2 / iconv | movaslim 已去掉 | 保持去掉 | 引用坑 ⑥⑦ |
| zlib | arm64 macOS 链到了 `@rpath/libz.dylib`（实测） | **只允许 SDK 的 `/usr/lib/libz.1.dylib`** | 由 S1 的 `otool -L` 白名单关卡逼出根因再修 |
| Xcode | `Xcode_16.1.0.app`，找不到就回退默认 | 同左，回退时打 warning | runner 镜像轮换 Xcode 是 R1 |
| 最低系统 | iOS 9.0 / macOS amd64 10.9 / arm64 11.0（上游写死） | 建议 iOS 13.0 / macOS 10.15，和 podspec、Flutter 对齐 | Q6 |

### 4.3 新增 / 改动补丁清单

**新文件 `mova-libmpv/libmpv-darwin-build-whep.patch`**（叠在 mova-slim 补丁之上；按下面的步骤分批写进去，每步一次 CI）：

| 改动位置（build-root 内） | 内容 | 来自 |
|---|---|---|
| `packages.lock.nix` | ffmpeg → n9.0.2；mpv → v0.41.0；新增 libplacebo + 4 个子模块（必要时加 Vulkan-Headers） | v9 线补丁 |
| `nix/packages/mk-pkg-libplacebo/`（新） | `default.nix` + 拼子模块；最小静态选项 | v9 线补丁 + Android 开关 |
| `mk-pkg-ffmpeg/default.nix` | 不再打上游 4 个 n6 补丁：`vp9-hwaccel` 直接删；`hls-mp4-seek` 和 `dash-base-url-escape` 按 Android 结论 "n9 已含" 删；`ios-hdr-texture` 用 `patch --dry-run` **严格**试打，不用 v9 线那种 `--fuzz=5` 加不致命，打不上就 fail（Q10）；按编号严格 `git apply` / `patch -p1` 打 `patches/mova/ffmpeg-whep/0001–0012`；buildInputs 和 `PKG_CONFIG_PATH` 加回 mbedtls（只要静态） | 新写 |
| `mk-pkg-ffmpeg/meson.build`（movaslim 分支） | 去掉 `--enable-securetransport`，换成 `--enable-mbedtls --enable-version3`；保留 `--pkg-config-flags=--static`；n9 差异：`--disable-iamf`、去掉不存在的 `--disable-postproc`（对照 `flavors-mova-slim-n9.sh`）；协议加 `dtls`、demuxer 加 `whep`（S3 才加） | 对照 Android n9 flavor |
| `mk-pkg-mbedtls/meson.build` + `default.nix` | `USE_STATIC=true`、`USE_SHARED=false`、`ENABLE_PROGRAMS=false`、`ENABLE_TESTING=false`；patchedSource 里 sed 打开 `MBEDTLS_SSL_DTLS_SRTP`，并加 grep 自检；安装 `*.a` | v9 线 + `whep-android.patch` |
| `mk-pkg-mpv/default.nix` | 0.41 的选项表（删掉被移除的选项）；打 `patches/mova/mpv-v041` 的 **0001 / 0003 / 0004 / 0006 / 0007**（跳过 0002 javavm、0005 win-rc，和 Windows 的挑选规则一致）；跳过 `mpv-audiounit-shared-session.patch`；sed 去掉 swift 依赖的两个源文件（macOS）；iOS 关 `coreaudio` / `avfoundation`；buildInputs 加 libplacebo；`PKG_CONFIG_PATH` 显式列全 | v9 线补丁 + mova 补丁 |
| `mk-out-libs/default.nix` | movaslim 下依旧只出 `libmpv.dylib`，确保不会因为 mbedtls 变成 buildInput 又多出 3 个 dylib | 现有补丁的延伸 |

**ffmpeg / mpv 源码层面**：Apple 不需要任何新的源码补丁（方案 A）。0008（schannel）会照样按顺序打上，它只改 `tls_schannel.c`，Apple 不编译这个文件，没有影响，和 Windows 打全部补丁的做法一致。

**新脚本**（放 `mova-libmpv/tools/whep-flavor/`）：

- `apple-macho-check.sh`：检查 `otool -L` 白名单（只允许 `/System/Library/`、`/usr/lib/`，自身 id 除外）、`LC_ID_DYLIB`、`vtool -show-build` 的 minos、`lipo -archs`、导出符号表（现有 10 个 `mpv_*` 加上 `mpv_create_weak_client`）。
- `apple-xcframework.sh`：
  - `dsymutil` 生成 dSYM（在 strip 之前）；
  - `strip -S -x`；
  - `install_name_tool -id @rpath/Mpv.framework/Mpv`；
  - macOS 重做 ad-hoc 签名；
  - 生成 framework 的 `Info.plist`，minos 从二进制里读；
  - 拷 `Headers/` 和 `Modules/module.modulemap`；
  - 用 `xcodebuild -create-xcframework` 组装，打 tar.gz。
- `apple-smoke.c`（或复用 `tools/libplacebo-eval/smoke2.c` 的思路）：`mpv_create` → `loadfile` → 轮询 `time-pos`，同时用于 macOS 和 iOS 模拟器。

### 4.4 分步计划（每步小而可 CI 验证）

> 每一步只构建当步需要的最小 target，先用 `macos-arm64`：它最快，而且 runner 能直接运行产物。

| 步 | 做什么 | CI 关卡（全过才进下一步） | 预计改动 |
|---|---|---|---|
| **S0 基线与钉版本** | workflow 里给 `libmpv-darwin-build` 钉 SHA（取最近一次绿 run 实际用到的 commit）；whep workflow 的 `plan` job 加 `apple` 平台选项和对应 job 骨架（只 checkout、apply 现有补丁、构建现有 n6 movaslim 的 `macos-arm64`）；接上 `apple-macho-check.sh` | 构建绿；`apple-macho-check.sh` 应该能**复现** §3.2 的两个缺陷（预期失败项先设为 warning），证明关卡本身有效 | workflow + 1 个脚本 |
| **S1 版本对齐（不带 WHEP，仍用 securetransport）** | overlay 补丁第一批：ffmpeg n9.0.2、mpv v0.41.0、libplacebo、mpv 0001 / 0006 / 0007、上游补丁处理；**TLS 先不动** | `macos-arm64` 构建绿；Mach-O 关卡转为**硬失败**（含 zlib 根因修复）；macOS 冒烟：本地 mp4 播 5 秒，`time-pos` 前进，`vo=null`、`ao=null`；`strings` 里有 `mpv 0.41.0` 和 ffmpeg `9.0.2` | overlay 第一批 |
| **S2 TLS 换 mbedtls** | movaslim 分支改用 mbedtls 加 version3；mbedtls 静态加 DTLS_SRTP | ffmpeg `configure.log` / `config.h`：`CONFIG_MBEDTLS 1`、`CONFIG_SECURETRANSPORT 0`、`CONFIG_DTLS_PROTOCOL 1`；`otool -L` 里没有 Security.framework 之外的新依赖（mbedtls 已静态折进）；https 冒烟：runner 上起自签 https 服务放 HLS，`tls-verify=no` 能播，`tls-verify=yes` + `tls-ca-file` 能播，换无关 CA 失败；记录体积增量 | overlay 第二批 |
| **S3 接入 WHEP** | 打 ffmpeg 0001–0012、mpv 0003 / 0004；flavor 加 `whep` 和 `dtls` | `CONFIG_WHEP_DEMUXER 1`；**macOS 端到端**：runner 上起 MediaMTX（官方有 darwin_arm64 发布包）和 brew 的 ffmpeg，推 testsrc2 加 opus，冒烟程序拉 `whep+http://127.0.0.1:8889/test/whep` 播 15 秒，`time-pos` 前进、出帧数 >0；复用 `whep_tamper_proxy.py` 的 `fp` 模式验证指纹被篡改时拒绝、`dead` 模式验证超时干净返回；可选 `lossy` 模式，看 NACK 计数非 0 | overlay 第三批 |
| **S4 macOS 其余架构** | 矩阵扩到 `macos-amd64`、`macos-universal` | 构建绿；`lipo -archs` 为 `x86_64 arm64`；x86_64 冒烟用 Intel runner 或 Rosetta（runner 上有没有 Rosetta 要实测，推断） | 只改 workflow |
| **S5 iOS** | `ios-arm64`；按 Q4 决定是否加 `iossimulator-arm64` | 构建绿 + Mach-O 关卡（platform=iOS、minos 符合预期）；有模拟器切片时，把冒烟程序编成 simulator 可执行文件，用 `xcrun simctl spawn` 在 runner 的模拟器里对宿主机上的 MediaMTX 跑 S3 同款 WHEP 冒烟（模拟器和宿主共用网络，推断，要实测） | 只改 workflow |
| **S6 打包** | `apple-xcframework.sh` 组装 iOS（`ios-arm64` 加可选模拟器切片）和 macOS（`macos-arm64_x86_64`）两份 `Mpv.xcframework`；podspec 去掉 `prepare_command`，改成求值时执行 | `xcodebuild -create-xcframework` 成功；用 `pubspec_overrides` 指向产物，`flutter build ios --no-codesign` 和 `flutter build macos` 编 `mova/example`，验证 pod install、链接，以及 install name 修复后能正常链接；macOS 再跑一次 `example.app`：只验证启动不崩、dyld 正常加载（无头 runner 上能做到哪一步要实测） | 2 个脚本 + podspec |
| **S7 交付与真机** | 按 Q5 决定交付方式：只出 artifact 交给 release 设计的阶段 8，或者注入 LFS 包；用户在真 iPhone / Mac 上跑 WHEP 播放 | 用户真机清单：iOS 真机 WHEP 起播、VideoToolbox 硬解、前后台切换、本地网络权限弹窗；macOS 正式签名 / 公证后能启动 | 视 Q5 |

每步失败的处理和既有做法一致：

- 修补丁，重跑同一个 target。
- 不用 `--fuzz` 之类的"带病放行"。

### 4.5 workflow 草案要点（`build-mova-libmpv-whep.yml`）

- **触发路径**加上 `mova-libmpv/libmpv-darwin-build-mova-slim.patch`、`mova-libmpv/libmpv-darwin-build-whep.patch`、`mova-libmpv/tools/whep-flavor/apple-*`。
- **`plan` job**：`platform` 选项加 `apple`（以及只跑 iOS 或只跑 macOS 的细分，Q4 / Q5 定了再细化），`ci-platform` 文件同步支持；输出 `apple_matrix`。
- **`apple-whep` job**：
  - `runs-on: macos-15`，`timeout-minutes: 180`；
  - `strategy.matrix.target`：`macos-arm64` / `macos-amd64` / `macos-universal` / `ios-arm64` /（可选）`iossimulator-arm64`；`fail-fast: false`；
  - 步骤：两次 checkout（dart-labs 用 `path: dart-labs`；build-root 钉 `ref: <SHA>`）→ 打两份补丁、拷 mova 补丁目录、`git add -A` → `nix-installer-action` + `magic-nix-cache-action` → 解析 Xcode 路径 → `nix develop -c make TARGET=mk-out-archive-libs-<target>-video-movaslim` → 解包、Mach-O 关卡、配置宏检查 → 冒烟（只在 macOS 和模拟器上跑）→ 上传 artifact `mova-libmpv-<target>-whep`（unstripped dylib、dSYM、`configure.log`、冒烟日志）。
- **`apple-xcframework` job**（needs `apple-whep`）：下载各切片 → 组装两份 xcframework → `flutter build ios --no-codesign`、`flutter build macos` → 上传 `mova-libmpv-apple-whep-xcframeworks`。是否 commit 回仓库，由 `commit_artifact` 和 Q5 共同决定；**默认不注入**。
- **产物路径**（建议，Q5 定稿后再改）：
  - artifact：`ios/Mpv.xcframework`、`macos/Mpv.xcframework`，和 release 设计 §5.2 的 `ios-arm64-whep` / `macos-universal-whep` 资产名对齐；
  - 如果注入：参照 Android 的 `media_kit_libs_android_video_slim_v041`，新建 `mova/packages/media_kit_libs_{ios,macos}_video_slim_v041/`，不覆盖 n6 包。
- **安全约束沿用现有规则**：只允许 main 的 push 和手动 dispatch；注入提交带 `[skip ci]`；先 `git lfs push` 再 `push`；`fetch + reset` 重试。
- **成本**：仓库是 PUBLIC（引用 release 设计 §1.1），标准 macOS runner 不计分钟；但 macOS 并发上限较低，5 条腿可能排队（推断）。

---

## 5. 风险

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | 上游 `libmpv-darwin-build` 一直没钉 ref；runner 镜像轮换会让 `Xcode_16.1.0.app` 消失 | 某天无故红 | S0 钉 SHA；Xcode 回退时打 warning，并在 summary 里写实际用的 Xcode 版本 |
| R2 | mpv 0.41 在 **macOS** 上的 cocoa / swift 问题：v9 线只在 iOS 跑绿过 | S1 可能要多轮 | 先用 sed 摘源文件；不行再评估 `-Dswift-build` 或关 cocoa（会影响 macOS 音频，`coreaudio` 依赖 cocoa 的说法要核实） |
| R3 | libplacebo 在 darwin 上要 Vulkan 头、子模块拼接路径对不对 | S1 多轮 | v9 线已有现成做法 |
| R4 | mbedtls 3.4.x 已停止维护；面向网络的 TLS / DTLS 栈有已知 CVE 的可能（推断） | 安全 | Q7：Android 和 Apple 一起升 3.6 LTS，另立任务 |
| R5 | §3.2 的两个现存二进制缺陷 | 现有 n6 Apple slim 包大概率启动即崩（推断） | WHEP 线 S1 / S6 修；n6 包看 Q8 |
| R6 | 没有 Apple 真机：模拟器不等于真机（VideoToolbox、GLES、蜂窝网络和 NAT、后台挂起） | iOS 只能验证到模拟器 | S7 列真机清单交给用户 |
| R7 | 许可证 LGPLv3 进 App Store：v3 的 "Installation Information" 条款和 App Store 签名、分发模式之间的张力业界一直有争议；v2.1 也有争议但相对弱（不下结论） | 合规 | Q2；用动态 framework 便于替换（现状已是）；Release 附源码和许可说明（release 设计 §4.7） |
| R8 | 加密出口合规：从"只用 Apple 系统加密"变成"自带 mbedtls" | App Store 提交问卷答案、可能的自我分类报告 | 用户或法务确认（Q2 一起看） |
| R9 | 隐私清单 required-reason API | 上架提示或拒审（推断） | Q9 |
| R10 | 本地网络权限、Mac App Store 沙盒的网络 entitlement（UDP 收发是否只需 `network.client`，推断） | 局域网 WHEP 在弹窗前或沙盒里失败 | 写进 mova 的接入文档；S7 真机核对 |
| R11 | HTTPS 证书校验行为变化（系统信任库改为必须 `tls-ca-file`） | 开了 `tlsVerify` 的宿主 App 在 Apple 上 https 播放失败 | 文档同步；或者选 C 方案 |
| R12 | 体积：每架构 +0.5～0.8 MB（推断）；macOS universal 翻倍；加上 n9 + mpv 0.41 自身的增量（Android 上约 +4.5%，引用） | 包体 | S2 实测记录；必要时用 mbedtls L1 裁剪（−115 KB，Linux 实测，引用） |
| R13 | Nix 的 `fetch-tarball` sha256、子模块 commit 首次都要靠 CI 报错来回填 | S1 多一两轮 | 正常现象，记录在提交说明里 |
| R14 | `whep.c` 的 `poll()` 等待、UDP `connect` 后的 ICE，在 Darwin 上的细节差异（推断风险较低：都是 POSIX） | 握手异常 | S3 的 macOS 端到端就是为了尽早暴露 |

---

## 6. 需要用户拍板的问题（选项化，不替你决定）

| # | 问题 | 选项 | 说明 |
|---|---|---|---|
| **Q1** | Apple 的 TLS / DTLS 后端 | (a) A：mbedtls　(b) B：OpenSSL 3　(c) C：securetransport + mbedtls 混合 | 本文推荐 (a)，理由见 §2.3 |
| **Q2** | 能否接受 Apple 版 libmpv 变成 **LGPLv3** | (a) 接受（和 Android、media_kit 官方 Apple 包一致）　(b) 不接受，必须保住 v2.1+，那就只能选 B 并承担体积代价和法律确定性问题　(c) 先找法务确认再定 | 加密出口合规（R8）建议一并问 |
| **Q3** | 构建路线 | (a) Nix overlay 补丁（推荐，复用 7 个坑的修法和 v9 线经验）　(b) fork `libmpv-darwin-build` 到自己的组织，直接改源码，不用补丁文件　(c) 去掉 Nix，写 `build-apple.sh`，和 `build-windows.sh` / `build-linux.sh` 同风格 | (c) 最直观，但 README 记录过"从零手写的 iOS 交叉构建（v2）从未跑绿"，风险偏高 |
| **Q4** | iOS 模拟器切片 | (a) 加 `iossimulator-arm64`（能在 CI 模拟器里跑 WHEP 冒烟，开发者也能 `flutter run` 到模拟器）　(b) arm64 + x86_64 两个模拟器切片　(c) 只要真机 `ios-arm64`（和现状一样） | 模拟器切片不进 App Store 包，只增加 CI 时间和下载体积 |
| **Q5** | 产物去向 | (a) 只出 CI artifact，交给 release-download 设计的阶段 8 晋升为 GitHub Release（推荐，和该设计一致）　(b) 注入新建的 `media_kit_libs_{ios,macos}_video_slim_v041`（LFS）　(c) 直接覆盖现有 n6 slim 包 | 影响 S6 / S7 和 workflow 的提交步骤 |
| **Q6** | 最低系统版本 | (a) iOS 13.0 / macOS 10.15（和 podspec、Flutter 对齐）　(b) 沿用上游写死的 iOS 9 / macOS 10.9 / 11.0　(c) 你指定 | 现状不一致：iOS 二进制写 9.0、plist 写 12.0、podspec 写 9.0 |
| **Q7** | mbedtls 版本 | (a) 先用上游 3.4.1 求绿，之后另立任务和 Android 一起升 3.6 LTS（推荐）　(b) 这次直接升 3.6　(c) 维持 3.4.x | 3.6 在 Linux 上已验证过 WHEP（引用 0007 说明） |
| **Q8** | §3.2 现有 n6 Apple slim 包的两个缺陷 | (a) 单独开一个小任务，先修 n6 包（只改 workflow 的打包步骤）　(b) 只在 WHEP 线修，n6 包等被替换　(c) 先在真机上确认确实会崩再说 | 现在 iOS / macOS 的 slim 包都还没被 mova example 实际 override 使用（引用 release 设计 §1.2） |
| **Q9** | Mpv.framework 附带哪些东西 | `PrivacyInfo.xcprivacy`：要 / 不要 / 先查清再定；dSYM：随 artifact 发 / 不发 | 都不影响构建，影响上架体验 |
| **Q10** | 上游 `ffmpeg-fix-ios-hdr-texture.patch` 在 n9.0.2 上打不上时 | (a) 丢掉，记 TODO　(b) 移植到 n9.0.2　(c) 先查上游是否已修 | 本文建议严格试打，不做模糊匹配 |
| **Q11** | 老 `build-mova-libmpv.yml` 的 `darwin` / `ios` job | (a) Apple WHEP 跑绿后改为只能手动触发（和其他平台旧配方一致）　(b) 保持现状　(c) 删除 | |

---

## 7. 参考

- 本仓库：`patches/ffmpeg-whep/README.md`（0007 / 0008 / 0009 说明）、`patches/android-v041/README.md`、`patches/mpv-v041/README.md`、`doc/plans/2026-10-01-whep-receiver.md`（D2 / D3 / A8 / R3 / Q4）、`doc/notes/2026-10-02-extreme-slim-config.md`（mbedtls 体积和 L1 裁剪）、`reference/ffmpeg9-zhangfly/`（v9 线 darwin 补丁和结论）、`mova/doc/plans/2026-10-26-libmpv-release-download-design.md`（Release 分发和 Apple 阶段 8）、`mova/doc/plans/2026-09-25-libmpv-pub-package.md`（install name 未确认的原始记录）。
- 上游：`media-kit/libmpv-darwin-build`（main 分支）的 `packages.lock.nix`、`nix/packages/mk-pkg-ffmpeg/meson.build`、`nix/packages/mk-pkg-mbedtls/meson.build`，本次实读。
- ffmpeg n9.0.2：`configure`、`libavformat/{Makefile,tls.h,tls_securetransport.c,tls_*.c}`、`LICENSE.md`，本机源码树实读。
