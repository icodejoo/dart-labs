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

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  #
  # Classes/dummy_file.c must stay: a pod needs at least one compilable source
  # file for CocoaPods to create a target that can carry the OTHER_LDFLAGS
  # below.
  #
  # Classes/dummy_file.c 必须保留：pod 至少要有一个可编译源文件，CocoaPods 才会
  # 生成一个能承载下面 OTHER_LDFLAGS 的 target。
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'
  s.swift_version = '5.0'

  # svgx ships precompiled Rust static libraries (see
  # PRECOMPILED_MIGRATION_PLAN.md). There is no `script_phase` any more —
  # nothing is compiled on the consumer's machine, and no Rust toolchain is
  # required.
  #
  # svgx 随包分发预编译的 Rust 静态库（见 PRECOMPILED_MIGRATION_PLAN.md）。
  # 不再有 `script_phase`——用户机器上不编译任何东西，也不需要 Rust 工具链。
  #
  # Deliberately NOT using `s.vendored_libraries`: that would put both archives
  # on the link line at once, and device/simulator both being arm64 makes them
  # collide. `preserve_paths` is also unnecessary — Flutter consumes plugins as
  # local `:path` pods (via .symlinks), so the archives are reachable in place
  # at $(PODS_TARGET_SRCROOT)/../prebuilt/. This is the same mechanism the
  # previous `$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh` relied on.
  #
  # 刻意不用 `s.vendored_libraries`：那会把两个归档同时放进链接行，而 device 与
  # simulator 同为 arm64 会互相冲突。也不需要 `preserve_paths`——Flutter 是以本地
  # `:path` pod（经 .symlinks）消费插件的，归档在
  # $(PODS_TARGET_SRCROOT)/../prebuilt/ 原地即可访问，与此前
  # `$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh` 依赖的是同一套机制。
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain an i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # -force_load is mandatory: nothing on the C side references the
    # flutter_rust_bridge exports, so a plain static link dead-strips them.
    # The per-SDK branch picks the right archive — device and simulator are
    # both arm64, so `lipo` physically cannot merge them into one file.
    #
    # -force_load 是必须的：C 侧没有任何代码引用 flutter_rust_bridge 导出的符号，
    # 普通静态链接会把它们死代码剥离掉。按 SDK 分支选对应归档——device 与
    # simulator 都是 arm64，`lipo` 物理上无法合并成一个文件。
    'OTHER_LDFLAGS[sdk=iphoneos*]' =>
      '-force_load $(PODS_TARGET_SRCROOT)/../prebuilt/ios/device/libsvgx.a',
    'OTHER_LDFLAGS[sdk=iphonesimulator*]' =>
      '-force_load $(PODS_TARGET_SRCROOT)/../prebuilt/ios/simulator/libsvgx.a',
  }
end
