#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint svgx.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'svgx'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.dependency 'FlutterMacOS'
  # Must match kMacosDeploymentTarget in tool/prebuilt_common.dart — that is the
  # version written into the vendored framework's Info.plist.
  #
  # 必须与 tool/prebuilt_common.dart 的 kMacosDeploymentTarget 一致——那是写进分发
  # framework Info.plist 的版本号。
  s.platform = :osx, '10.11'
  s.swift_version = '5.0'

  # svgx ships one precompiled Rust framework (see
  # docs/PRECOMPILED_MIGRATION_PLAN.md). There is no `script_phase` — nothing is
  # compiled on the consumer's machine, and no Rust toolchain is required.
  #
  # svgx 随包分发一个预编译的 Rust framework（见
  # docs/PRECOMPILED_MIGRATION_PLAN.md）。没有 `script_phase`——用户机器上不编译任何
  # 东西，也不需要 Rust 工具链。
  #
  # The Rust core is a `cdylib` wrapped in `svgx.framework`, not a `staticlib`
  # pulled in with `-force_load`: `-force_load` exists precisely to defeat dead
  # stripping, so the old combination shipped every object file in the archive.
  # A `cdylib` is linked by rustc itself and keeps only the graph reachable from
  # the `#[no_mangle]` exports.
  #
  # Rust 核心是包在 `svgx.framework` 里的 `cdylib`，不再是靠 `-force_load` 拉进来的
  # `staticlib`：`-force_load` 的作用恰恰就是关掉死代码剥离，旧方案因此把归档里每个
  # object 都塞进了产物。`cdylib` 由 rustc 自己链接，只保留 `#[no_mangle]` 导出可达
  # 的部分。
  #
  # There are deliberately no `source_files` and no `Classes/` directory. With
  # them, CocoaPods would build the pod into its own dynamic `svgx.framework`
  # and collide with the vendored bundle of the same name. The name has to be
  # `svgx`: flutter_rust_bridge's loader ends up at
  # `DynamicLibrary.open('svgx.framework/svgx')`, so renaming it would force
  # every consumer to hand `RustLib.init()` a custom `ExternalLibrary`.
  #
  # 刻意不设 `source_files`、也不保留 `Classes/` 目录。一旦有源文件，CocoaPods 会把
  # pod 自身也编成一个动态 `svgx.framework`，与同名的 vendored bundle 撞车。而名字
  # 必须是 `svgx`：flutter_rust_bridge 的加载器最终走
  # `DynamicLibrary.open('svgx.framework/svgx')`，改名等于强迫所有下游给
  # `RustLib.init()` 传自定义 `ExternalLibrary`。
  #
  # Unlike iOS this is a plain `.framework`, not an `.xcframework`: macOS is a
  # single platform variant, so arm64 and x86_64 are just two architectures of
  # one fat binary and there is no slice for an XCFramework to disambiguate.
  # It is a *versioned* bundle (`Versions/A/...`), which macOS — unlike iOS —
  # requires: `codesign` rejects a flat framework here. It ships unsigned;
  # Xcode re-signs embedded frameworks with the consuming app's identity at
  # "Embed & Sign" time.
  #
  # 与 iOS 不同，这里是普通 `.framework` 而非 `.xcframework`：macOS 只有一个平台变
  # 体，arm64 与 x86_64 只是同一个 fat 二进制的两个架构，没有需要 XCFramework 去区分
  # 的 slice。它是*版本化* bundle（`Versions/A/...`），这是 macOS（不同于 iOS）的硬
  # 要求：扁平 framework 会被 `codesign` 拒绝。产物不签名分发——Xcode 在 “Embed &
  # Sign” 阶段会用宿主 App 的身份重新签名。
  #
  # The bundle sits here, next to the podspec, and NOT under `prebuilt/` with
  # every other artifact. A `vendored_frameworks` path that leaves the pod root
  # is silently broken: CocoaPods emits no FRAMEWORK_SEARCH_PATHS for it and
  # never adds it to the embed phase (CocoaPods#7554, CocoaPods#10731), so the
  # app builds fine and then fails at launch. Measured on the iOS side of this
  # same migration.
  #
  # bundle 就放在这里、与 podspec 同级，而不是和其它产物一起放在 `prebuilt/` 下。
  # `vendored_frameworks` 一旦跳出 pod 根目录就会静默失效：CocoaPods 既不生成
  # FRAMEWORK_SEARCH_PATHS，也不把它加进 embed 阶段（CocoaPods#7554、
  # CocoaPods#10731），于是 App 构建通过、启动即崩。本次迁移的 iOS 一侧已实测。
  s.vendored_frameworks = 'svgx.framework'
end
