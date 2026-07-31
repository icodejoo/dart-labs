#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint videoman.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'videoman'
  s.version          = '0.3.0'
  s.summary          = 'media_kit (libmpv/ffmpeg) video player plugin with a self-built gesture and controls layer.'
  s.description      = <<-DESC
A Flutter video player plugin built on media_kit (libmpv/ffmpeg): custom gesture
layer, VOD and live control bars, HLS quality switching with buffering-based ABR,
scrub-preview thumbnails, live timeshift, and Android picture-in-picture.
                       DESC
  s.homepage         = 'https://github.com/icodejoo/dart-labs/tree/main/videoman'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'jelon' => 'jelon@tbu.net' }
  s.source           = { :path => '.' }
  s.source_files = 'videoman/Sources/videoman/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'videoman_privacy' => ['videoman/Sources/videoman/PrivacyInfo.xcprivacy']}
end
