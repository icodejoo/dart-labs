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
  s.module_name      = 'svgx'

  # Classes/dummy_file.c must stay: a pod needs at least one compilable source
  # file for CocoaPods to create a target that can carry the OTHER_LDFLAGS
  # below.
  #
  # Classes/dummy_file.c 必须保留：pod 至少要有一个可编译源文件，CocoaPods 才会
  # 生成一个能承载下面 OTHER_LDFLAGS 的 target。
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.11'
  s.swift_version = '5.0'

  # svgx ships a precompiled universal (arm64 + x86_64) Rust static library,
  # lipo'd by tool/build_prebuilt.dart. No script_phase, no Rust toolchain on
  # the consumer's machine. See PRECOMPILED_MIGRATION_PLAN.md.
  #
  # svgx 随包分发预编译的通用（arm64 + x86_64）Rust 静态库，由
  # tool/build_prebuilt.dart 用 lipo 合并产出。没有 script_phase，用户机器上也不需要
  # Rust 工具链。见 PRECOMPILED_MIGRATION_PLAN.md。
  #
  # Both macOS slices are device slices, so unlike iOS there is no
  # device/simulator arm64 collision and one universal archive suffices — hence
  # no `[sdk=...]` branch here. The stray
  # `EXCLUDED_ARCHS[sdk=iphonesimulator*]` that used to sit in this file was
  # copy-pasted from the iOS podspec and is meaningless on macOS; it is gone.
  #
  # macOS 的两个 slice 都是 device slice，不存在 iOS 那种 device/simulator arm64
  # 撞车问题，一个通用归档就够，所以这里没有 `[sdk=...]` 分支。原先文件里那条
  # `EXCLUDED_ARCHS[sdk=iphonesimulator*]` 是从 iOS podspec 抄来的、在 macOS 上
  # 毫无意义，已删除。
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # -force_load is mandatory: nothing on the C side references the
    # flutter_rust_bridge exports, so a plain static link dead-strips them.
    #
    # -force_load 是必须的：C 侧没有任何代码引用 flutter_rust_bridge 导出的符号，
    # 普通静态链接会把它们死代码剥离掉。
    'OTHER_LDFLAGS' =>
      '-force_load $(PODS_TARGET_SRCROOT)/../prebuilt/macos/libsvgx.a',
  }
end
