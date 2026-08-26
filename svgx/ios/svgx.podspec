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
  s.dependency 'Flutter'
  # Must not exceed kIosDeploymentTarget in tool/prebuilt_common.dart — that is
  # the version the vendored binary itself is built for.
  #
  # 不得高于 tool/prebuilt_common.dart 的 kIosDeploymentTarget——那是分发二进制自身
  # 的构建目标版本。
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'

  # svgx ships one precompiled Rust XCFramework (see
  # docs/PRECOMPILED_MIGRATION_PLAN.md). There is no `script_phase` — nothing is
  # compiled on the consumer's machine, and no Rust toolchain is required.
  #
  # svgx 随包分发一个预编译的 Rust XCFramework（见
  # docs/PRECOMPILED_MIGRATION_PLAN.md）。没有 `script_phase`——用户机器上不编译任何
  # 东西，也不需要 Rust 工具链。
  #
  # The Rust core is a `cdylib` wrapped in `svgx.framework`, not a `staticlib`:
  # rustc dead-strips everything the `#[no_mangle]` exports cannot reach, which
  # the old archive + `-force_load` combination specifically prevented.
  #
  # Rust 核心是包在 `svgx.framework` 里的 `cdylib`，不再是 `staticlib`：rustc 会剥离
  # `#[no_mangle]` 导出不可达的全部代码，而旧的“归档 + `-force_load`”组合恰恰阻止了
  # 这一点。
  #
  # There are deliberately no `source_files` and no `Classes/` directory. With
  # them, CocoaPods would build the pod into its own dynamic `svgx.framework`
  # and collide with the vendored bundle of the same name. The name has to be
  # `svgx`: flutter_rust_bridge's iOS loader ends up at
  # `DynamicLibrary.open('svgx.framework/svgx')`, so renaming it would force
  # every consumer to hand `RustLib.init()` a custom `ExternalLibrary`.
  #
  # 刻意不设 `source_files`、也不保留 `Classes/` 目录。一旦有源文件，CocoaPods 会把
  # pod 自身也编成一个动态 `svgx.framework`，与同名的 vendored bundle 撞车。而名字
  # 必须是 `svgx`：flutter_rust_bridge 的 iOS 加载器最终走
  # `DynamicLibrary.open('svgx.framework/svgx')`，改名等于强迫所有下游给
  # `RustLib.init()` 传自定义 `ExternalLibrary`。
  #
  # The XCFramework carries its own per-slice architecture split, so the old
  # `[sdk=iphoneos*]` / `[sdk=iphonesimulator*]` branch and the
  # `EXCLUDED_ARCHS` workaround are gone: `xcodebuild` picks the right slice.
  # It is shipped unsigned — Xcode re-signs embedded frameworks with the
  # consuming app's identity at "Embed & Sign" time.
  #
  # XCFramework 自带按 slice 的架构划分，所以旧的 `[sdk=...]` 分支与
  # `EXCLUDED_ARCHS` 变通都已删除：`xcodebuild` 会自己选对 slice。产物不签名分发——
  # Xcode 在 “Embed & Sign” 阶段会用宿主 App 的身份重新签名嵌入的 framework。
  #
  # Flutter consumes plugins as local `:path` pods (via .symlinks), so the
  # `../prebuilt/` path resolves in place — the same mechanism the previous
  # `$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh` relied on.
  #
  # Flutter 以本地 `:path` pod（经 .symlinks）消费插件，`../prebuilt/` 原地即可解析
  # ——与此前 `$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh` 依赖的是同一套机制。
  s.vendored_frameworks = '../prebuilt/ios/svgx.xcframework'
end
