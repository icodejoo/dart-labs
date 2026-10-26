# mova libmpv 瘦身产物（消费侧）

构建配方、flavor 脚本、CI 定义在独立子工程 [`mova-libmpv`](../../../mova-libmpv/README.md)。
本目录只保留 CI 回写的构建产物。

## 当前版本：只有 n9

全部平台以 n9 为主：ffmpeg n9.0.2 + mpv v0.41.0 + WHEP/WebRTC。旧 n6 产物
（Android 四 ABI、Linux、Windows 旧目录）已于 2026-10-26 移除，不再保留回退。

| 平台 | 位置 | 说明 |
|---|---|---|
| Android | `../packages/media_kit_libs_android_video_slim_v041/android/src/main/jniLibs/<abi>/` | 不在本目录；`libmpv.so` 由 `build-mova-libmpv-whep.yml` 注入，`libmediakitandroidhelper.so` 为上游原样提取 |
| Windows x64 | `windows-x86_64-whep/{libmpv-2.dll,libmpv-2.def,libmpv.dll.a}` | n9；目录名保持 `-whep`，`media_kit_libs_windows_video_slim` 的 CMakeLists 直接引用 |
| Linux x64 | 无入库产物 | 由 n9 CI 出 artifact |
| iOS / macOS | `ios-arm64/`、`macos-*/` | 仍是 n6 旧产物，待 Apple 的 n9 构建落地后替换 |

## 约定

- 产物由 [`.github/workflows/build-mova-libmpv-whep.yml`](../../.github/workflows/build-mova-libmpv-whep.yml)
  构建并 commit 回来；push 自动构建开关见 `mova-libmpv/tools/whep-flavor/ci-platform`
  （默认 `none`，需要时用手动 dispatch 指定平台）。
- mova 工程侧的接入方式见 `mova-libmpv/README.md` 的"接入 mova 工程"一节。
- 改 flavor 脚本、patch、构建选项、平台支持范围，去 `mova-libmpv` 改；这里不要再放
  任何构建配方文件。
