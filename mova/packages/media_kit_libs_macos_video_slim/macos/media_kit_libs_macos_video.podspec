#
# [mova slim fork] Same package name as upstream media_kit_libs_macos_video —
# see the iOS sibling package's podspec comment for the full rationale
# (same-name dependency_overrides, prepare_command symlinks, unverified
# status). Frameworks/Mpv.xcframework here wraps mova-libmpv's
# macos-universal/libmpv.dylib (expected arm64+x86_64 fat binary — not
# independently confirmed with `lipo`/`otool`, no Mac available).
#
# ⚠️ UNVERIFIED: see doc/plans/2026-09-25-libmpv-pub-package.md
# "Darwin（iOS/macOS）同名替换设计".
#
Pod::Spec.new do |s|
  s.prepare_command = <<-CMD
    mkdir -p Frameworks/.symlinks/mpv
    sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv
  CMD

  s.name             = 'media_kit_libs_macos_video'
  s.version          = '1.0.4'
  s.summary          = '[mova slim fork] macOS dependency package for package:media_kit'
  s.description      = <<-DESC
  [mova slim fork] macOS dependency package for package:media_kit, using
  mova-libmpv's own slimmed libmpv instead of upstream's prebuilt archive.
                       DESC
  s.homepage         = 'https://github.com/icodejoo/dart-labs'
  s.license          = { :type => 'MIT', :text => 'See package:media_kit (MIT) for the Classes/ glue; Frameworks/Mpv.xcframework is LGPL-2.1 (mpv/FFmpeg via mova-libmpv).' }
  s.author           = { 'Hitesh Kumar Saini' => 'saini123hitesh@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.vendored_frameworks = 'Frameworks/*.xcframework'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
