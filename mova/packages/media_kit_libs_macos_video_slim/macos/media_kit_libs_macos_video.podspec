#
# [mova slim fork] 与上游 media_kit_libs_macos_video 同名，靠 dependency_overrides 整体替换，
# 上游包不进 pod 依赖图。Frameworks/Mpv.xcframework 是 mova-libmpv 的 n9 WHEP 版（ffmpeg n9.0.2 +
# whep demuxer + DTLS-SRTP，mpv v0.41.0），由 CI 编译后直接随包提交（LFS），不在 pod install 时下载。
#
# media_kit_video 的 podspec 从 Frameworks/.symlinks/mpv/<平台> 找 Mpv.framework，这些符号链接
# 原先靠 prepare_command 生成；但 CocoaPods 对 :path 形式的 pod（Flutter 插件都是）不执行
# prepare_command，所以改在 podspec 求值时建（上游官方包也是在这里 system("make")）。
#
# 许可证：ffmpeg 开了 --enable-version3（静态 mbedtls），整体为 LGPLv3。
#
Pod::Spec.new do |s|
  # 求值时重建符号链接（先删后建，幂等）
  fw_dir = File.join(File.dirname(__FILE__), 'Frameworks')
  system("rm -rf '#{fw_dir}/.symlinks/mpv' && mkdir -p '#{fw_dir}/.symlinks/mpv' && "          "sh '#{File.dirname(__FILE__)}/create_framework_symlinks.sh' '#{fw_dir}/Mpv.xcframework' '#{fw_dir}/.symlinks/mpv'")

  s.name             = 'media_kit_libs_macos_video'
  s.version          = '1.0.4'
  s.summary          = '[mova slim fork] macOS dependency package for package:media_kit'
  s.description      = <<-DESC
  [mova slim fork] macOS dependency package for package:media_kit, using
  mova-libmpv's own slimmed libmpv instead of upstream's prebuilt archive.
                       DESC
  s.homepage         = 'https://github.com/icodejoo/dart-labs'
  s.license          = { :type => 'LGPL-3.0', :text => 'Classes/ glue: MIT (package:media_kit). Frameworks/Mpv.xcframework: LGPLv3 (mpv + FFmpeg built with --enable-version3, static mbedTLS) via mova-libmpv.' }
  s.author           = { 'Hitesh Kumar Saini' => 'saini123hitesh@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.vendored_frameworks = 'Frameworks/*.xcframework'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
