#
# [mova slim fork] Same package name as upstream media_kit_libs_ios_video, so
# a dependency_overrides path/git override makes this the sole provider of
# com.alexmercerind.media_kit_libs_ios_video — upstream never enters the pod
# graph, so there is nothing to conflict with (media_kit_video's
# media_kit_utils.rb only aborts when it finds *more than one* package named
# media_kit_libs_ios_*, which can't happen once the override is in effect).
#
# Unlike upstream (which downloads a prebuilt xcframework archive via `make`
# + curl at `pod install` time), Frameworks/Mpv.xcframework here is committed
# directly — built from mova-libmpv's own slimmed libmpv.dylib. The
# Frameworks/.symlinks/mpv/<slice> symlinks upstream's Makefile also creates
# are instead created by `prepare_command` below (runs at `pod install` time
# on the real Mac build machine), reusing upstream's own
# create_framework_symlinks.sh verbatim (MIT).
#
# ⚠️ UNVERIFIED: assembled without Xcode/macOS tooling (no `otool`,
# `install_name_tool`, `xcodebuild`, or a Mac to test on). Structurally
# mirrors upstream's xcframework/podspec conventions, but has never been
# through `pod install` / a real build. See doc/plans/2026-09-25-libmpv-pub-package.md
# "Darwin（iOS/macOS）同名替换设计" for what's still unverified.
#
Pod::Spec.new do |s|
  s.prepare_command = <<-CMD
    mkdir -p Frameworks/.symlinks/mpv
    sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv
  CMD

  s.name             = 'media_kit_libs_ios_video'
  s.version          = '1.0.4'
  s.summary          = '[mova slim fork] iOS dependency package for package:media_kit'
  s.description      = <<-DESC
  [mova slim fork] iOS dependency package for package:media_kit, using
  mova-libmpv's own slimmed libmpv instead of upstream's prebuilt archive.
                       DESC
  s.homepage         = 'https://github.com/icodejoo/dart-labs'
  # No LICENSE file shipped in this internal fork (matches the existing
  # windows/android slim packages in this monorepo); Classes/ glue is MIT
  # like upstream, Frameworks/Mpv.xcframework is LGPL-2.1 (mpv/FFmpeg).
  s.license          = { :type => 'MIT', :text => 'See package:media_kit (MIT) for the Classes/ glue; Frameworks/Mpv.xcframework is LGPL-2.1 (mpv/FFmpeg via mova-libmpv).' }
  s.author           = { 'Hitesh Kumar Saini' => 'saini123hitesh@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  s.vendored_frameworks = 'Frameworks/*.xcframework'

  s.platform = :ios, '9.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
