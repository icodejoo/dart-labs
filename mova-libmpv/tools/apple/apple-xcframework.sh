#!/bin/bash
# 把各切片的 libmpv.dylib 装配成两份 Mpv.xcframework（iOS：真机+模拟器；macOS：arm64+x86_64 合成 universal）。
# 用法：apple-xcframework.sh <切片目录> <输出目录>
#   切片目录下需有 <target>/libmpv.dylib（已 strip），target 为：
#   macos-arm64 macos-amd64 ios-arm64 iossimulator-arm64 iossimulator-amd64
#   输出：<输出目录>/ios/Mpv.xcframework、<输出目录>/macos/Mpv.xcframework
# 要点：
#   - install name 统一改成 @rpath/Mpv.framework/Mpv（Nix 出来的是 @rpath/libmpv.dylib，链进 App 后 dyld 找不到）
#   - 依赖只允许系统库（由 apple-macho-check.sh 把关），不再依赖包外的 @rpath/libz.dylib
#   - Info.plist 的最低系统版本从二进制 LC_BUILD_VERSION 读出，三处（二进制/Info.plist/podspec）保持一致
#   - macOS framework 用标准的 Versions/A 布局，符号链接要靠 tar 打包保留
#   - 附 PrivacyInfo.xcprivacy；全部 ad-hoc 签名（install_name_tool 之后原签名失效），正式签名由 App 侧嵌入时完成
set -euo pipefail
ART="${1:?切片目录}"; OUT="${2:?输出目录}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VER="${MPV_VERSION:-0.41.0}"
BUNDLE_ID="${BUNDLE_ID:-com.icodejoo.mova.libmpv}"
INSTALL_NAME="@rpath/Mpv.framework/Mpv"

# 读二进制某个架构的最低系统版本
minos_of() { vtool -arch "$2" -show-build "$1" | awk '/minos/ {print $2; exit}'; }

# 写 Info.plist：$1=路径 $2=支持平台(iPhoneOS|iPhoneSimulator|MacOSX) $3=最低版本键名 $4=最低版本值
write_plist() {
  cat > "$1" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Mpv</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Mpv</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>${VER}</string>
	<key>CFBundleVersion</key>
	<string>${VER}</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>$2</string>
	</array>
	<key>$3</key>
	<string>$4</string>
</dict>
</plist>
PLIST
  plutil -lint "$1"
}

# 装配 iOS（扁平）framework：$1=dylib $2=目标目录 $3=支持平台
make_ios_framework() {
  local fw="$2/Mpv.framework"
  rm -rf "$fw"; mkdir -p "$fw/Headers" "$fw/Modules"
  cp "$1" "$fw/Mpv"; chmod u+w "$fw/Mpv"
  install_name_tool -id "$INSTALL_NAME" "$fw/Mpv"
  cp "$HERE"/Headers/*.h "$fw/Headers/"
  cp "$HERE/module.modulemap" "$fw/Modules/module.modulemap"
  cp "$HERE/PrivacyInfo.xcprivacy" "$fw/PrivacyInfo.xcprivacy"
  # 多架构时取各切片 minos 的最小值（arm64 模拟器 14.0、x86_64 模拟器 13.0 -> 13.0）
  local m=""
  for a in $(lipo -archs "$fw/Mpv"); do m="$m $(minos_of "$fw/Mpv" "$a")"; done
  write_plist "$fw/Info.plist" "$3" MinimumOSVersion "$(echo $m | tr ' ' '
' | sort -V | head -1)"
  codesign -f -s - "$fw"
}

# 装配 macOS（Versions/A）framework：$1=dylib(universal) $2=目标目录
make_macos_framework() {
  local fw="$2/Mpv.framework" v="$2/Mpv.framework/Versions/A"
  rm -rf "$fw"; mkdir -p "$v/Headers" "$v/Modules" "$v/Resources"
  cp "$1" "$v/Mpv"; chmod u+w "$v/Mpv"
  install_name_tool -id "$INSTALL_NAME" "$v/Mpv"
  cp "$HERE"/Headers/*.h "$v/Headers/"
  cp "$HERE/module.modulemap" "$v/Modules/module.modulemap"
  cp "$HERE/PrivacyInfo.xcprivacy" "$v/Resources/PrivacyInfo.xcprivacy"
  # 最低系统版本取 x86_64 切片（arm64 切片硬件下限是 11.0）
  write_plist "$v/Resources/Info.plist" MacOSX LSMinimumSystemVersion "$(minos_of "$v/Mpv" x86_64)"
  ln -s A "$fw/Versions/Current"
  ln -s Versions/Current/Mpv "$fw/Mpv"
  ln -s Versions/Current/Headers "$fw/Headers"
  ln -s Versions/Current/Modules "$fw/Modules"
  ln -s Versions/Current/Resources "$fw/Resources"
  codesign -f -s - "$fw"
}

rm -rf "$OUT"; mkdir -p "$OUT/ios" "$OUT/macos" "$OUT/work"
W="$OUT/work"

# ---- iOS ----
make_ios_framework "$ART/ios-arm64/libmpv.dylib" "$W/ios-device" iPhoneOS
# 模拟器切片：arm64 + x86_64 合成 fat（flutter build ios --simulator 默认两个架构都链）
mkdir -p "$W/ios-sim-fat"
lipo -create "$ART/iossimulator-arm64/libmpv.dylib" "$ART/iossimulator-amd64/libmpv.dylib" -output "$W/ios-sim-fat/libmpv.dylib"
make_ios_framework "$W/ios-sim-fat/libmpv.dylib" "$W/ios-sim" iPhoneSimulator
xcodebuild -create-xcframework \
  -framework "$W/ios-device/Mpv.framework" \
  -framework "$W/ios-sim/Mpv.framework" \
  -output "$OUT/ios/Mpv.xcframework"

# ---- macOS ----
mkdir -p "$W/macos-fat"
lipo -create "$ART/macos-arm64/libmpv.dylib" "$ART/macos-amd64/libmpv.dylib" -output "$W/macos-fat/libmpv.dylib"
make_macos_framework "$W/macos-fat/libmpv.dylib" "$W/macos"
xcodebuild -create-xcframework -framework "$W/macos/Mpv.framework" -output "$OUT/macos/Mpv.xcframework"

echo "== 产物 =="
( cd "$OUT" && find ios macos -maxdepth 3 | sort )
plutil -p "$OUT/ios/Mpv.xcframework/Info.plist" | head -40
plutil -p "$OUT/macos/Mpv.xcframework/Info.plist" | head -30
